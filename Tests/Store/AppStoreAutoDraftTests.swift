import Foundation
import Testing

@testable import PRism

/// Návrh review ze strany store (#520) — kdy se složí, co se do něj dostane a co po něm zbude
/// na disku.
///
/// **Nejcennější tvrzení téhle sady jsou ta, která říkají, že se něco NEstalo**: že se nic
/// neodeslalo (`gh` se ani nespustilo, a to při **povoleném** odesílání), že se sporný nález
/// nepřevzal, že odmítnutý neprošel a že ručně rozepsaný draft zůstal, jak byl. Ta se rozbijí
/// potichu — výsledkem porušení není chyba, ale komentář v rozdělaném review, o kterém jsem
/// nevěděl, a který pak odešle potvrzení.
///
/// Proti **skutečnému** `ReviewStore` i `ReviewDraftStore` nad dočasnou složkou: celý smysl
/// razítka je, že přežije restart, a to fake ověřit neumí.
@Suite("AppStore — návrh review (#520)")
@MainActor
struct AppStoreAutoDraftTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let calls: URL
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "gh-calls.txt")
    }

    // MARK: - Scéna

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Diff s hunkem na nových řádcích 25–27 — tedy místem, které unese **řádkový** komentář.
    private var diffText: String {
        """
        diff --git a/Cart.php b/Cart.php
        --- a/Cart.php
        +++ b/Cart.php
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """
    }

    private func finding(
        line: Int? = 26,
        verdict: FindingVerdict? = .confirmed,
        summary: String = "nález"
    ) -> ReportedFinding {
        makeReported(file: "Cart.php", line: line, verdict: verdict, summary: summary)
    }

    /// Odesílání je **povolené schválně**: tvrzení „nic se neodeslalo“ má něco znamenat i tam,
    /// kde by odeslat šlo. S vypnutou branou by to netvrdilo nic (`Policy.sendBlock` by zavřel
    /// cestu ven dřív, než by se k ní návrh dostal).
    private func configuration(autoDraft: Bool) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.allowsPublishing = true
        configuration.global.autoDraft = autoDraft
        return configuration
    }

    /// `gh`, které si zapisuje, že ho někdo spustil. Nula spuštění = neodeslalo se nic.
    private func countingGh() throws -> URL {
        let script = directory.url.appending(path: "gh.sh")
        try """
        #!/bin/sh
        echo "call" >> "\(calls.path(percentEncoded: false))"
        exit 0
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    private func ghCalls() -> Int {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func makeStore(
        findings: [ReportedFinding],
        autoDraft: Bool = true,
        reviews: ReviewStore? = nil,
        drafts: ReviewDraftStore? = nil,
        detail: PullRequest? = nil
    ) throws -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .success(detail ?? self.detail()),
                diffs: [.success(diffText), .success(diffText)]
            ),
            configuration: configuration(autoDraft: autoDraft),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: reviews ?? ReviewStore(layout: layout, time: FakeTimeSource()),
            drafts: drafts ?? ReviewDraftStore(layout: layout),
            gh: try countingGh(),
            activityLog: ActivityLog(layout: layout)
        )
    }

    /// Otevřený pull request: detail i diff načtené, tedy stav, ve kterém se na PR koukám.
    private func opened(_ store: AppStore) async {
        await store.loadDetail(for: summary())
        await store.loadDiff(for: summary())
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }
    }

    // MARK: - Nic se neodeslalo

    /// **Nejcennější tvrzení téhle sady.** Návrh je předvyplnění, ne odeslání — a pozná se to na
    /// tom, že se `gh` **vůbec nespustilo**, i když je odesílání v nastavení povolené.
    @Test("Složený návrh neodešle nic")
    func sendsNothing() async throws {
        let store = try makeStore(findings: [finding()])
        await opened(store)

        await runReview(store)

        #expect(store.draft(for: pr)?.comments.count == 1)
        #expect(ghCalls() == 0)
        // A verdikt zůstává **návrhem** (#114): do draftu se nezapisuje.
        #expect(store.draft(for: pr)?.verdict == nil)
    }

    // MARK: - Brána

    /// **Výchozí stav.** Bez tohohle by se panel začal plnit sám každému, kdo aplikaci aktualizuje.
    @Test("S vypnutou branou se nesloží nic")
    func doesNothingWithTheGateClosed() async throws {
        let store = try makeStore(findings: [finding()], autoDraft: false)
        await opened(store)

        await runReview(store)

        #expect(store.autoDraftStamp(for: pr) == nil)
        #expect(store.draft(for: pr) == nil)
        #expect(store.autoDraftPill(for: pr) == nil)
    }

    /// Skládání je odložené (draft vzniká až s diffem), takže se mezi rozhodnutím a složením dá
    /// volba vypnout — a pak už nemá vzniknout nic.
    @Test("Vypnutí volby zastaví i odložené složení draftu")
    func stopsDeferredCompositionWhenTheGateCloses() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = try makeStore(findings: [finding()], reviews: reviews)
        await store.loadDetail(for: summary())
        await runReview(store)
        #expect(store.autoDraftStamp(for: pr) != nil)

        // Volba se přepíná **tou samou cestou jako v okně nastavení** (`updateConfiguration`), ne
        // zápisem do storu: jinak by test měřil vlastní zadní vrátka.
        try await store.updateConfiguration(configuration(autoDraft: false))
        await store.loadDiff(for: summary())

        #expect(store.draft(for: pr) == nil)
    }

    // MARK: - Co se převezme a co ne

    @Test("Jistý nález se převezme, nejistý zůstane sporný")
    func adoptsOnlyConfirmed() async throws {
        let store = try makeStore(findings: [
            finding(verdict: .confirmed, summary: "jistý"),
            finding(line: 27, verdict: .plausible, summary: "nejistý"),
        ])
        await opened(store)

        await runReview(store)

        let draft = try #require(store.draft(for: pr))
        #expect(draft.comments.map(\.body) == ["jistý"])
        let stamp = try #require(store.autoDraftStamp(for: pr))
        #expect(stamp.adopted == 1)
        #expect(stamp.contested.count == 1)
        // A u sporného je v okně vidět proč.
        #expect(store.autoDraftDoubts(for: pr).values.first == .plausible)
    }

    /// Odmítnutý nález se nepřevezme **ani nenabídne jako sporný** — o něm je rozhodnuto (#113).
    @Test("Odmítnutý nález se do návrhu nedostane")
    func skipsDismissedFindings() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = try makeStore(findings: [finding(summary: "falešný")], reviews: reviews)
        await opened(store)
        await runReview(store)
        let first = try #require(store.reviewRecord(for: pr)?.findings.first)
        // Návrh z prvního běhu se zahodí, ať se druhý sklápí načisto.
        await store.discardAutoDraft(for: pr)
        await store.dismissFinding(first, as: .invalid, for: pr)

        await runReview(store)

        #expect(store.autoDraftStamp(for: pr) == nil, "z odmítnutého nálezu se návrh skládat nemá")
        #expect(store.draft(for: pr) == nil)
    }

    /// **Druhé nejcennější tvrzení.** Co jsem začal psát já, si aplikace nepřepíše.
    @Test("Ručně rozepsaný draft zůstane, jak byl")
    func keepsAManualDraft() async throws {
        let store = try makeStore(findings: [finding()])
        await opened(store)
        store.setDraftBody("tohle jsem psal já", for: pr)

        await runReview(store)

        #expect(store.draft(for: pr)?.body == "tohle jsem psal já")
        #expect(store.draft(for: pr)?.comments.isEmpty == true)
        #expect(store.autoDraftStamp(for: pr) == nil)
    }

    // MARK: - Hlava (tvrdá podmínka č. 5)

    /// Jak se hlava pohne, **převzetí zhasne** — nesloží se proti kódu, který v PR není.
    @Test("Nad posunutou hlavou se návrh nesloží")
    func doesNotComposeOverAMovedHead() async throws {
        let store = try makeStore(findings: [finding()])
        await opened(store)
        await runReview(store)
        await store.discardAutoDraft(for: pr)
        // Razítko zpátky, ale k nálezům na **jiné** hlavě, než na které PR stojí.
        var record = try #require(store.reviewRecord(for: pr))
        record.autoDraft = StoredAutoDraft(
            at: Date(timeIntervalSince1970: 1),
            adopted: 1,
            contested: [:]
        )
        record.isStale = true
        store.reviewRecords[pr] = record

        await store.materializeAutoDraft(for: pr)

        #expect(store.draft(for: pr) == nil)
    }

    /// **Nález vlastní revize.** Po pushi se záznam nevymění — jen se označí `isStale` —, takže
    /// bez brány v `Policy.autoDraftStamp` by řádek fronty dál tvrdil `návrh review · 1`
    /// nad nálezy, které patří jinému commitu.
    @Test("Po posunu hlavy razítko v okně zmlkne")
    func stampGoesSilentAfterAPush() async throws {
        let store = try makeStore(findings: [finding()])
        await opened(store)
        await runReview(store)
        #expect(store.autoDraftPill(for: pr) != nil)

        store.markStaleInMemory(for: pr, current: "bbbb2222")

        #expect(store.autoDraftStamp(for: pr) == nil)
        #expect(store.autoDraftPill(for: pr) == nil)
        #expect(store.autoDraftDoubts(for: pr).isEmpty)
    }

    /// **Nález vlastní revize, a ten nejdražší**: po odeslání review se draft maže — kdyby razítko
    /// zůstalo, složil by se při dalším načtení diffu znovu, tedy i po tom, co review odešlo.
    @Test("Zahození review razítko shodí, takže se návrh nevrátí")
    func discardingTheDraftAlsoForgetsTheStamp() async throws {
        let store = try makeStore(findings: [finding()])
        await opened(store)
        await runReview(store)
        #expect(store.draft(for: pr) != nil)

        store.discardDraft(for: pr)
        await settle()
        await store.materializeAutoDraft(for: pr)

        #expect(store.autoDraftStamp(for: pr) == nil)
        #expect(store.draft(for: pr) == nil)
    }

    /// Mezi rozhodnutím a složením uběhne čas — a dá se v něm nález odmítnout. Pruh pak nesmí
    /// tvrdit víc, než co v panelu leží.
    @Test("Odmítnutí mezi rozhodnutím a složením srovná i počty v razítku")
    func alignsTheStampWithWhatWasComposed() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = try makeStore(
            findings: [finding(summary: "první"), finding(line: 27, summary: "druhý")],
            reviews: reviews
        )
        await store.loadDetail(for: summary())
        await runReview(store)
        #expect(store.autoDraftStamp(for: pr)?.adopted == 2)
        let first = try #require(store.reviewRecord(for: pr)?.findings.first)
        await store.dismissFinding(first, as: .invalid, for: pr)

        await store.loadDiff(for: summary())

        #expect(store.draft(for: pr)?.comments.count == 1)
        #expect(store.autoDraftStamp(for: pr)?.adopted == 1)
    }

    // MARK: - Odložené složení

    /// Bez načteného diffu by se z **každého** nálezu stal odkaz do těla review. Návrh proto
    /// počká — a složí se, jakmile se PR otevře.
    @Test("Bez načteného diffu se draft nesloží, po otevření PR ano")
    func waitsForTheDiff() async throws {
        let store = try makeStore(findings: [finding()])
        await store.loadDetail(for: summary())

        await runReview(store)

        #expect(store.autoDraftStamp(for: pr) != nil, "rozhodnutí padne hned")
        #expect(store.draft(for: pr) == nil, "komentář bez diffu nevzniká")

        await store.loadDiff(for: summary())

        let draft = try #require(store.draft(for: pr))
        #expect(draft.comments.count == 1)
        // A je to **řádkový** komentář, ne odkaz v těle — to je celý důvod, proč se čekalo.
        #expect(draft.comments.first?.line == 26)
        #expect(draft.body.isEmpty)
    }

    // MARK: - Dění

    @Test("Do dění se zapíše řádek s oběma počty")
    func writesAnActivityRow() async throws {
        let store = try makeStore(findings: [
            finding(verdict: .confirmed, summary: "jistý"),
            finding(line: 27, verdict: .plausible, summary: "nejistý"),
        ])
        await opened(store)

        await runReview(store)

        let event = try #require(store.activityEvents.first { $0.kind == .autoDraft })
        #expect(event.headline == "Návrh review připraven")
        #expect(event.detail == "z 2 nálezů 1 převzat, 1 sporný")
        // **Banner za tím nechodí** a chip `bez banneru` se u něj nekreslí.
        #expect(!Policy.showsSilentChip(.autoDraft, announced: event.wasAnnounced))
    }

    // MARK: - Zahození a restart

    @Test("Zahození smaže návrh i razítko a přežije to restart")
    func discardingSurvivesARestart() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let drafts = ReviewDraftStore(layout: layout)
        let store = try makeStore(findings: [finding()], reviews: reviews, drafts: drafts)
        await opened(store)
        await runReview(store)
        #expect(store.draft(for: pr) != nil)

        await store.discardAutoDraft(for: pr)

        #expect(store.draft(for: pr) == nil)
        #expect(store.autoDraftStamp(for: pr) == nil)
        #expect(store.autoDraftDoubts(for: pr).isEmpty)

        let restarted = try makeStore(findings: [], reviews: reviews, drafts: drafts)
        await restarted.loadStoredReviews()
        #expect(restarted.autoDraftStamp(for: pr) == nil)
        // A nálezy zůstávají: zahozený návrh nálezy nesundává (#113).
        #expect(restarted.reviewRecord(for: pr)?.findings.count == 1)
    }

    @Test("Razítko přežije restart i se svými spornými")
    func stampSurvivesARestart() async throws {
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = try makeStore(
            findings: [
                finding(verdict: .confirmed, summary: "jistý"),
                finding(line: 27, verdict: .plausible, summary: "nejistý"),
            ],
            reviews: reviews
        )
        await opened(store)
        await runReview(store)

        let restarted = try makeStore(findings: [], reviews: reviews)
        await restarted.loadStoredReviews()

        let stamp = try #require(restarted.autoDraftStamp(for: pr))
        #expect(stamp.adopted == 1)
        #expect(stamp.contested.count == 1)
        #expect(restarted.autoDraftDoubts(for: pr).values.first == .plausible)
    }

    // MARK: - Pilulka v řádku

    @Test("Řádek fronty nese pilulku s oběma počty")
    func rowShowsThePill() async throws {
        let store = try makeStore(findings: [
            finding(verdict: .confirmed, summary: "jistý"),
            finding(line: 27, verdict: .plausible, summary: "nejistý"),
        ])
        await opened(store)

        await runReview(store)

        #expect(store.autoDraftPill(for: pr) == .composed(adopted: 1, contested: 1))
    }

    @Test("U čistého review zbude v řádku návrh verdiktu")
    func rowShowsTheVerdictOnCleanReview() async throws {
        let store = try makeStore(findings: [])
        await opened(store)

        await runReview(store)

        #expect(store.autoDraftStamp(for: pr) == nil)
        #expect(store.autoDraftPill(for: pr) == .verdict(.approve))
    }
}
