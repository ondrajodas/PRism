import Foundation
import Testing

@testable import PRism

/// Dotažení nálezů po pádu aplikace (#97).
///
/// Proti **skutečnému** `InterruptedRuns` i `ReviewStore` nad dočasnou složkou: rozhoduje disk,
/// protože celé issue je o tom, co přežije restart. Transcript se podstrkuje fakem — číst
/// `~/.claude/` z testů nechceme.
@Suite("AppStore — dotažení po pádu")
@MainActor
struct AppStoreRecoveryTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var pr: PRIdentifier { PRIdentifier("cli/cli#42")! }
    private var worktree: URL { URL(filePath: "/cache/worktrees/cli/cli/42-aaaa1111") }

    private func marker(skill: String = "code-review", session: String = "s-1") -> InterruptedRun {
        InterruptedRun(
            pullRequest: pr,
            headSha: "aaaa1111",
            skill: skill,
            sessionID: session,
            worktree: worktree
        )
    }

    private func summary(findings: Int) -> StreamSummary {
        var summary = StreamSummary()
        summary.calledReportFindings = true
        summary.findings = (1 ... findings).map {
            ReportedFinding(
                file: "Cart.php",
                line: $0,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález \($0)",
                failureScenario: nil
            )
        }
        return summary
    }

    private func store(
        interrupted: InterruptedRuns,
        transcripts: FakeTranscriptReader,
        reviews: ReviewStore? = nil
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource(),
            reviews: reviews ?? ReviewStore(layout: layout, time: FakeTimeSource()),
            interrupted: interrupted,
            transcripts: transcripts
        )
    }

    /// Nejdůležitější test celého issue: co se ztratilo pádem, je po startu zpátky.
    @Test("Nálezy ze zabité session se po startu dotáhnou")
    func recoversFindingsAfterACrash() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let transcripts = FakeTranscriptReader(["s-1": summary(findings: 2)])

        let store = store(interrupted: interrupted, transcripts: transcripts)
        await store.recoverInterruptedRuns()
        await store.loadStoredReviews()

        let record = try #require(store.reviewRecords[pr])
        #expect(record.findings.count == 2)
        // A na disku taky — jinak by to zmizelo dalším restartem.
        let onDisk = try await ReviewStore(layout: layout, time: FakeTimeSource()).load()
        #expect(onDisk.records.first?.findings.count == 2)
    }

    /// `clean` u přerušeného běhu by lhalo: chybí `result` event, takže se neví, jestli
    /// reviewer skončil.
    @Test("Dotažený běh se uloží jako přerušený, ne jako doběhlý")
    func marksTheRecoveredRunAsInterrupted() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let store = store(
            interrupted: interrupted,
            transcripts: FakeTranscriptReader(["s-1": summary(findings: 1)])
        )

        await store.recoverInterruptedRuns()

        #expect(store.reviewRecords[pr]?.runs.first?.outcome == .interrupted)
        #expect(store.reviewState(for: pr) == .interrupted(findings: 1))
    }

    /// Transcript má `sessionId`, `stream-json` `session_id` — parser proto z transcriptu id
    /// nevytáhne. Doplňuje se ze značky: bez něj neumí osa nabídnout `claude --resume`
    /// a brána proti přepsání uloženého běhu nemá co porovnávat.
    @Test("Dotažený běh si nese id session ze značky")
    func carriesTheSessionIdentifier() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        // Souhrn z transcriptu id nemá — přesně jako ten skutečný.
        var withoutIdentifier = summary(findings: 1)
        withoutIdentifier.sessionID = nil
        let store = store(
            interrupted: interrupted,
            transcripts: FakeTranscriptReader(["s-1": withoutIdentifier])
        )

        await store.recoverInterruptedRuns()

        #expect(store.reviewRecords[pr]?.runs.first?.sessionID == "s-1")
    }

    @Test("Dotažená značka se zahodí, takže se to podruhé nedělá")
    func forgetsTheMarkerAfterRecovery() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let transcripts = FakeTranscriptReader(["s-1": summary(findings: 1)])

        await store(interrupted: interrupted, transcripts: transcripts).recoverInterruptedRuns()
        #expect(await interrupted.pending().isEmpty)

        // Druhý start už transcript nečte.
        await store(interrupted: interrupted, transcripts: transcripts).recoverInterruptedRuns()
        #expect(transcripts.requests.count == 1)
    }

    /// Strom mohla sebrat eviction. Značka, ke které se transcript nikdy nenajde, by tam
    /// jinak ležela navždycky.
    @Test("Značka bez transcriptu se zahodí a nic se neuloží")
    func dropsAMarkerWithoutATranscript() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let store = store(interrupted: interrupted, transcripts: FakeTranscriptReader([:]))

        await store.recoverInterruptedRuns()

        #expect(store.reviewRecords[pr] == nil)
        #expect(await interrupted.pending().isEmpty)
    }

    /// Pád mezi zápisem výsledku a smazáním značky. Dotáhnout ho znovu by z hotového review
    /// udělalo nedodělek — `interrupted` by přepsalo `finished`.
    @Test("Značka nad uloženým během nepřepíše výsledek")
    func doesNotOverwriteAnAlreadySavedRun() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        var finished = StreamSummary()
        finished.calledReportFindings = true
        // **Táž session**: to je ten pád mezi uložením a smazáním značky.
        finished.sessionID = "s-1"
        try await reviews.save(
            ReviewRun(
                key: marker().key,
                summary: finished,
                outcome: .finished
            )
        )

        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let transcripts = FakeTranscriptReader(["s-1": summary(findings: 5)])
        let store = store(interrupted: interrupted, transcripts: transcripts, reviews: reviews)

        await store.recoverInterruptedRuns()
        await store.loadStoredReviews()

        #expect(store.reviewRecords[pr]?.runs.first?.outcome == .finished, "přepsal se doběhlý běh")
        #expect(store.reviewState(for: pr) == .clean)
        #expect(transcripts.requests.isEmpty, "transcript se vůbec neměl číst")
        #expect(await interrupted.pending().isEmpty)
    }

    /// Záznam pro tentýž commit může být ze **staršího** review — a to je zrovna situace, kdy
    /// se nálezy dotáhnout mají. Kdyby se porovnával skill místo session, zůstalo by nad novým
    /// během viset staré „čisté“. Vyšlo to najevo na živé zkoušce.
    @Test("Starší doběhlý běh dotažení nezastaví")
    func recoversOverAnOlderRunOfTheSameSkill() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        var older = StreamSummary()
        older.calledReportFindings = true
        older.sessionID = "s-starší"
        try await reviews.save(ReviewRun(key: marker().key, summary: older, outcome: .finished))

        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let store = store(
            interrupted: interrupted,
            transcripts: FakeTranscriptReader(["s-1": summary(findings: 4)]),
            reviews: reviews
        )

        await store.recoverInterruptedRuns()

        #expect(store.reviewRecords[pr]?.findings.count == 4, "nálezy z přerušeného běhu se ztratily")
        #expect(store.reviewState(for: pr) == .interrupted(findings: 4))
    }

    /// Nečitelný transcript není totéž co chybějící: nálezy v něm pořád leží, takže se značka
    /// nechává a příští start to zkusí znovu.
    @Test("Nečitelný transcript si značku nechá")
    func keepsTheMarkerWhenTheTranscriptCannotBeRead() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        let transcripts = FakeTranscriptReader([:])
        transcripts.failing = ["s-1"]

        await store(interrupted: interrupted, transcripts: transcripts).recoverInterruptedRuns()

        #expect(await interrupted.pending().count == 1, "značka zmizela i s nálezy v transcriptu")
    }

    @Test("Bez značek se nikam nesahá")
    func doesNothingWithoutMarkers() async {
        let transcripts = FakeTranscriptReader([:])

        await store(interrupted: InterruptedRuns(layout: layout), transcripts: transcripts)
            .recoverInterruptedRuns()

        #expect(transcripts.requests.isEmpty)
    }

    /// Dotažení je záchranná síť nad daty, která už jednou spadla pod stůl — jedno selhání
    /// nesmí zastavit ostatní ani položit start.
    @Test("Selhání jednoho dotažení nezastaví ostatní")
    func oneFailureDoesNotStopTheRest() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker(skill: "a", session: "s-a"))
        await interrupted.remember(marker(skill: "b", session: "s-b"))
        // Pro `s-a` transcript není, pro `s-b` ano.
        let store = store(
            interrupted: interrupted,
            transcripts: FakeTranscriptReader(["s-b": summary(findings: 3)])
        )

        await store.recoverInterruptedRuns()

        #expect(store.reviewRecords[pr]?.findings.count == 3)
    }

    /// Značka se maže **až po** uložení. Kdyby se mazala dřív, pád mezi tím by běh nechal
    /// bez značky i bez záznamu.
    @Test("Neuložený běh si značku nechá")
    func keepsTheMarkerWhenSavingFails() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        await interrupted.remember(marker())
        // Store nad cestou, do které se nedá zapsat — kořen je obsazený souborem.
        let blocked = directory.url.appending(path: "blokováno")
        try Data("ne".utf8).write(to: blocked)
        let store = store(
            interrupted: interrupted,
            transcripts: FakeTranscriptReader(["s-1": summary(findings: 1)]),
            reviews: ReviewStore(layout: CacheLayout(root: blocked), time: FakeTimeSource())
        )

        await store.recoverInterruptedRuns()

        #expect(await interrupted.pending().count == 1, "značka zmizela i bez uloženého záznamu")
    }
}

/// Transcripty v paměti — testy nesahají do `~/.claude/`.
final class FakeTranscriptReader: TranscriptReading, @unchecked Sendable {
    private let summaries: [String: StreamSummary]
    private let lock = NSLock()
    private var asked: [String] = []

    init(_ summaries: [String: StreamSummary]) {
        self.summaries = summaries
    }

    var requests: [String] { lock.withLock { asked } }

    /// Session, u kterých čtení **selže** — transcript je, ale nedá se přečíst.
    var failing: Set<String> = []

    func summary(ofSession sessionID: String, in worktree: URL) async throws -> StreamSummary? {
        lock.withLock { asked.append(sessionID) }
        if failing.contains(sessionID) { throw CocoaError(.fileReadCorruptFile) }
        return summaries[sessionID]
    }

    // MARK: - Přepis surové session (#327)

    /// Snímky po `sessionID`. Chybějící klíč = transcript **není**.
    var snapshots: [String: RawTranscript] = [:]
    /// Session, u kterých selže **čtení snímku** — transcript je, ale nedá se přečíst.
    ///
    /// Vlastní sada, ne `failing`: dotažení nálezů a přepis jsou dvě různá čtení téhož souboru
    /// a test na jedno nemá zapínat chování druhého.
    var snapshotFailing: Set<String> = []
    /// Velikost souboru **teď** — z ní se v patičce počítá přírůstek. `nil` = nevíme.
    var sizes: [String: Int] = [:]
    private var snapshotRequests: [String] = []

    /// Kolikrát se ptalo na snímek. Z toho se pozná, že `Načíst znovu` doopravdy čte znovu — a taky
    /// že tik přírůstku okno **nečte** podruhé.
    var snapshotCount: Int { lock.withLock { snapshotRequests.count } }

    func snapshot(ofSession sessionID: String, in worktree: URL, at time: Date) async throws -> RawTranscript? {
        lock.withLock { snapshotRequests.append(sessionID) }
        if snapshotFailing.contains(sessionID) { throw TranscriptUnreadable.invalidEncoding }
        guard var snapshot = snapshots[sessionID] else { return nil }
        snapshot.takenAt = time
        return snapshot
    }

    func size(ofSession sessionID: String, in worktree: URL) async -> Int? {
        sizes[sessionID]
    }
}

/// Zápis značky za běhu (#97).
///
/// Bez ní se po pádu nepozná, že něco běželo — dotažení by nemělo z čeho vycházet. Proti
/// **skutečnému** `InterruptedRuns` nad dočasnou složkou, protože jde právě o disk.
@Suite("AppStore — značka rozdělaného běhu")
@MainActor
struct AppStoreInterruptedMarkerTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var pr: PRIdentifier { PRIdentifier("cli/cli#42")! }

    private func summary(_ text: String) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: ""
        )
    }

    private func waitUntilIdle(_ store: AppStore) async throws {
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
    }

    /// Zrušené review se schválně neukládá („rozdělané review je horší než žádné“). Kdyby si
    /// nechalo značku, příští start by z transcriptu vzkřísil nálezy, které si člověk zrušil.
    @Test("Zrušené review si značku nenechá")
    func aCancelledReviewLeavesNoMarker() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        let reviewer = FakeReviewRunner(
            holdsUntilRelease: true,
            progress: [.started(sessionID: "s-42")]
        )
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary("cli/cli#42")]), detail: .success(detail())),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            interrupted: interrupted
        )
        await store.refresh()

        store.startReview(for: pr)
        await reviewer.waitForStarts(1)
        store.cancelReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.reviewRecord(for: pr) == nil, "zrušené review se uložilo")
        #expect(await interrupted.pending().isEmpty, "po zrušeném review zůstala značka")
    }

    @Test("Session, která nahlásí id, se poznamená — a po uložení značka zmizí")
    func marksAndForgetsARun() async throws {
        let interrupted = InterruptedRuns(layout: layout)
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary("cli/cli#42")]), detail: .success(detail())),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(progress: [.started(sessionID: "s-42")]),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            interrupted: interrupted
        )
        await store.refresh()

        store.startReview(for: pr)
        try await waitUntilIdle(store)
        // Běh doběhl a uložil se, takže po značce nesmí nic zůstat.
        #expect(store.reviewRecord(for: pr)?.findings.isEmpty == true)
        #expect(await interrupted.pending().isEmpty, "značka po doběhlém běhu zůstala")
    }
}
