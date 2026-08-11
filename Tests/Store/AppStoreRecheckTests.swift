import Foundation
import Testing

@testable import PRism

/// Kontrola nálezů z minula (#150) — od toho, kdy se nabízí, po to, co se uloží.
///
/// Dvě věci, které se rozbijí potichu, a proto mají vlastní test: **kontrola se nesmí nabídnout,
/// když není co kontrolovat** (chybějící vstup by skončil session, která hádá) a **nesmí se
/// vydávat za review** (chip, nález, návrh verdiktu).
@Suite("AppStore — kontrola nálezů")
@MainActor
struct AppStoreRecheckTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let time = FakeTimeSource()

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail(headSha: String) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "base0000",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        reviews: ReviewStore,
        headSha: String = "new2222"
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary]),
                detail: .success(detail(headSha: headSha))
            ),
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: reviews
        )
    }

    private func reviewStore() -> ReviewStore {
        ReviewStore(layout: layout, time: time)
    }

    /// Uložený záznam se **starším** commitem a jedním nálezem — přesně stav, kvůli kterému #150
    /// vzniklo: „co jsem hlásil minulý týden a je to opravené?“
    private func storedFindings(
        in reviews: ReviewStore,
        summary text: String = "chybí kontrola nulového množství"
    ) async throws -> Finding {
        var stream = StreamSummary()
        stream.calledReportFindings = true
        stream.findings = [makeReported(file: "Cart.swift", line: 13, summary: text)]
        try await reviews.save(ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "old1111", skillID: "code-review"),
            summary: stream,
            outcome: .finished
        ))
        return try #require(await reviews.record(for: pr, at: "old1111")?.findings.first)
    }

    /// Načte záznam do storu a dotáhne detail — tedy stav po startu aplikace nad otevřeným PR.
    private func prepared(_ store: AppStore) async {
        await store.loadStoredReviews()
        await store.loadDetail(for: summary)
    }

    private func waitUntilIdle(_ store: AppStore) async {
        for _ in 0..<100_000 where store.isRechecking(pr) { await Task.yield() }
        #expect(!store.isRechecking(pr))
    }

    // MARK: - Kdy se nabízí

    @Test("Bez uloženého záznamu není co kontrolovat")
    func withoutARecordThereIsNothingToRecheck() async {
        let store = store(reviews: reviewStore())
        await prepared(store)

        #expect(store.recheckMaterial(for: pr) == nil)
    }

    /// Nad tou samou hlavou se „spravily to nové commity“ nemá koho ptát — žádné nové nejsou.
    @Test("Nad hlavou PR se kontrola nenabízí")
    func aRecordForTheCurrentHeadIsNotOffered() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let store = store(reviews: reviews, headSha: "old1111")
        await prepared(store)

        #expect(store.recheckMaterial(for: pr) == nil)
    }

    /// Nálezy, které jsem odmítl (#113), nejsou nálezy — session by se ptala na věty, o kterých
    /// už jsem rozhodl.
    @Test("Se samými odmítnutými nálezy se kontrola nenabízí")
    func onlyDismissedFindingsAreNotOffered() async throws {
        let reviews = reviewStore()
        let finding = try await storedFindings(in: reviews)
        try await reviews.dismiss(finding, as: .invalid, in: pr)
        let store = store(reviews: reviews)
        await prepared(store)

        #expect(store.recheckMaterial(for: pr) == nil)
    }

    @Test("Se záznamem proti staršímu commitu se nabízí")
    func anOlderRecordIsOffered() async throws {
        let reviews = reviewStore()
        let finding = try await storedFindings(in: reviews)
        let store = store(reviews: reviews)
        await prepared(store)

        let material = try #require(store.recheckMaterial(for: pr))

        #expect(material.headSha == "old1111")
        #expect(material.findings == [finding])
    }

    /// Bez materiálu se nesmí spustit ani přímým voláním: brána nesmí ležet jen v tom, že se
    /// tlačítko nenakreslilo.
    @Test("Bez materiálu se nespustí nic")
    func withoutMaterialNothingRuns() async {
        let reviewer = FakeReviewRunner()
        let store = store(reviewer: reviewer, reviews: reviewStore())
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        #expect(reviewer.requests.isEmpty)
    }

    // MARK: - Běh

    @Test("Kontrola pošle nálezy do session a uloží její verdikty")
    func theRecheckStoresTheVerdicts() async throws {
        let reviews = reviewStore()
        let finding = try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(
            resultText: #"[{"id": 0, "status": "resolved", "note": "commit abc přidal kontrolu"}]"#
        )
        let store = store(reviewer: reviewer, reviews: reviews)
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        // Zadání dostalo nálezy jako materiál, ne jako nový nástroj — a je to vlastní druh běhu.
        let request = try #require(reviewer.requests.first)
        #expect(request.key.kind == .recheck)
        #expect(request.recheck?.headSha == "old1111")
        #expect(request.recheck?.findings == [finding])

        // Verdikt leží u nálezů z minula, ne u nové hlavy.
        let record = try #require(store.reviewRecord(for: pr))
        #expect(record.headSha == "old1111")
        #expect(record.recheck?.againstHeadSha == "new2222")
        #expect(record.recheck?.statuses[Policy.key(of: finding)]?.verdict == .resolved)
        #expect(record.recheck?.statuses[Policy.key(of: finding)]?.note == "commit abc přidal kontrolu")
        #expect(store.recheckFailures[pr] == nil)
    }

    /// „Vyřešeno“ je tvrzení modelu, ne fakt: nález zůstává v okně a sundá ho jedině odmítnutí
    /// (#113). Tenhle test tvrdí, že se **nic neschovalo**.
    @Test("Vyřešený nález nemizí")
    func aResolvedFindingStays() async throws {
        let reviews = reviewStore()
        let finding = try await storedFindings(in: reviews)
        let store = store(
            reviewer: FakeReviewRunner(resultText: #"[{"id": 0, "status": "resolved"}]"#),
            reviews: reviews
        )
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        let record = try #require(store.reviewRecord(for: pr))
        #expect(record.activeFindings == [finding])
        #expect(record.dismissals.isEmpty)
        #expect(store.reviewState(for: pr) == .stale)
    }

    /// Kontrola se nesmí vydávat za review: žádný chip, žádný nález, žádný běh v `runs`.
    @Test("Kontrola nepřidá reviewera ani nález")
    func theRecheckIsNotAReviewer() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let store = store(
            reviewer: FakeReviewRunner(resultText: #"[{"id": 0, "status": "resolved"}]"#),
            reviews: reviews
        )
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        let record = try #require(store.reviewRecord(for: pr))
        #expect(record.runs.map(\.skillID) == ["code-review"])
        #expect(record.findings.count == 1)
    }

    /// Odpověď, kterou nikdo nepošle (zabitá session), se **nedopočítává** — nález zůstane
    /// nezodpovězený a věta v hlavičce to řekne.
    @Test("Bez odpovědi se nic nedomyslí")
    func withoutAnAnswerNothingIsGuessed() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let store = store(reviewer: FakeReviewRunner(outcome: .timedOut), reviews: reviews)
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        let record = try #require(store.reviewRecord(for: pr))
        #expect(record.recheck?.statuses.isEmpty == true)
        #expect(record.recheck?.outcome == .timedOut)
        guard case .current(let tally) = store.recheckReport(for: pr) else {
            Issue.record("čekal se platný report")
            return
        }
        #expect(tally.unanswered == 1)
        #expect(tally.answered == 0)
    }

    @Test("Zrušená kontrola neuloží nic")
    func acancelledRecheckStoresNothing() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(holdsUntilRelease: true, resultText: #"[{"id": 0, "status": "resolved"}]"#)
        let store = store(reviewer: reviewer, reviews: reviews)
        await prepared(store)

        store.startRecheck(for: pr)
        await reviewer.waitForStarts(1)
        store.cancelRecheck(for: pr)
        await waitUntilIdle(store)

        #expect(store.reviewRecord(for: pr)?.recheck == nil)
        #expect(store.recheckFailures[pr] == nil)
    }

    /// Kontrola je `claude` session jako každá jiná, takže platí všechno, co platí pro běžící
    /// běh: nesmí přežít zavření aplikace (#264), chrání repo před eviction a počítá se do
    /// dialogu při ukončení.
    @Test("Běžící kontrola se počítá jako běh a zavírání ji zabije")
    func aRunningRecheckCountsAsARun() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer, reviews: reviews)
        await prepared(store)

        store.startRecheck(for: pr)
        await reviewer.waitForStarts(1)

        #expect(store.runningReviews == 1)
        #expect(store.busyRepositories.contains(pr.repo))

        await store.stopReviewsBeforeTermination()

        #expect(store.runningReviews == 0)
        #expect(!store.isRechecking(pr))
        // A po zahájení zavírání se nová nespustí — session, která se rozjede po tom, co se
        // ostatní zabily, aplikaci přežije.
        store.startRecheck(for: pr)
        #expect(!store.isRechecking(pr))
    }

    @Test("Druhé zmáčknutí za běhu nespustí druhou session")
    func aSecondPressDoesNothing() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(reviewer: reviewer, reviews: reviews)
        await prepared(store)

        store.startRecheck(for: pr)
        await reviewer.waitForStarts(1)
        store.startRecheck(for: pr)
        reviewer.releaseAll()
        await waitUntilIdle(store)

        #expect(reviewer.requests.count == 1)
    }

    /// Spadlá kontrola se nesmí tvářit jako kontrola, která nic nenašla — to druhé se čte jako
    /// „nálezy pořád platí“.
    @Test("Selhání kontroly je vidět")
    func aFailureIsVisible() async throws {
        let reviews = reviewStore()
        _ = try await storedFindings(in: reviews)
        let store = store(
            reviewer: FakeReviewRunner(failing: GitHubError.notFound("PR nenalezen")),
            reviews: reviews
        )
        await prepared(store)

        store.startRecheck(for: pr)
        await waitUntilIdle(store)

        #expect(store.recheckFailures[pr] != nil)
        #expect(store.reviewRecord(for: pr)?.recheck == nil)
    }
}
