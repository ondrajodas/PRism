import Foundation
import Testing

@testable import PRism

/// Tělo návrhu review ze strany store (#521) — kdy se osmá session pustí, co dostane, co po ní
/// zbude v composeru a co na disku.
///
/// **Nejcennější tvrzení téhle sady jsou ta, která říkají, že se něco NEstalo**: že se nic
/// neodeslalo (`gh` se ani nespustilo, a to při **povoleném** odesílání), že se session nepustila
/// podruhé nad týmž razítkem, že ve vstupu není cesta na disk a že se **můj vlastní text
/// nepřepsal**. Ta se rozbijí potichu — výsledkem porušení není chyba, ale odstavec v těle review,
/// který jsem nenapsal, a který pak odešle potvrzení.
///
/// Proti **skutečnému** `ReviewStore`, `ReviewDraftStore` i `ReviewVoiceLedger` nad dočasnou
/// složkou: celý smysl razítka i vzorku hlasu je, že přežijí restart, a to fake ověřit neumí.
@Suite("AppStore — tělo návrhu review (#521)")
@MainActor
struct AppStoreReviewBodyTests {
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

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
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

    /// Diff s hunkem na nových řádcích 25–27 — místem, které unese **řádkový** komentář.
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

    /// Odesílání je **povolené schválně**: tvrzení „nic se neodeslalo“ má něco znamenat i tam, kde
    /// by odeslat šlo. S vypnutou branou by to netvrdilo nic.
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
        writer: FakeReviewBodyWriter?,
        autoDraft: Bool = true,
        voice: ReviewVoiceLedger? = nil,
        reviews: ReviewStore? = nil,
        conversations: [Result<Conversation, any Error>] = []
    ) throws -> AppStore {
        // Skutečný `SpendLedger` nad dočasnou složkou: tvrzení „cena se nese i u nepovedeného
        // běhu“ se bez něj nedá ověřit — `recordSpend` by se bez ledgeru vrátil rovnou.
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .success(detail()),
                diffs: [.success(diffText), .success(diffText)],
                conversations: conversations
            ),
            configuration: configuration(autoDraft: autoDraft),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: reviews ?? ReviewStore(layout: layout, time: FakeTimeSource()),
            drafts: ReviewDraftStore(layout: layout),
            reviewBodyWriter: writer,
            reviewVoice: voice,
            spend: SpendLedger(layout: layout, time: FakeTimeSource()),
            gh: try countingGh(),
            activityLog: ActivityLog(layout: layout)
        )
    }

    private func opened(_ store: AppStore) async {
        await store.loadDetail(for: summary())
        await store.loadDiff(for: summary())
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }
        await waitUntil("tělo doběhne") { !store.isWritingReviewBody(self.pr) }
    }

    // MARK: - Nic se neodeslalo

    /// **Nejcennější tvrzení téhle sady.** Tělo je text v composeru, ne odeslané review — a pozná
    /// se to na tom, že se `gh` **vůbec nespustilo**, i když je odesílání povolené.
    @Test("Napsané tělo neodešle nic")
    func sendsNothing() async throws {
        let writer = FakeReviewBodyWriter()
        let store = try makeStore(findings: [finding()], writer: writer)
        await opened(store)

        await runReview(store)

        #expect(store.draft(for: pr)?.body == "Díky, tři věci jsou k opravě a dvě si rozmyslím.")
        #expect(ghCalls() == 0)
        // A verdikt zůstává **návrhem** (#114): do draftu se nezapisuje ani teď.
        #expect(store.draft(for: pr)?.verdict == nil)
    }

    // MARK: - Brána

    /// **Tělo nemá vlastní bránu, jede na `autoDraft` z #520** (výchozí vypnuto) — takže bez
    /// návrhu se session nesmí pustit vůbec.
    @Test("S vypnutou branou návrhu se tělo nepíše")
    func doesNothingWithTheGateClosed() async throws {
        let writer = FakeReviewBodyWriter()
        let store = try makeStore(findings: [finding()], writer: writer, autoDraft: false)
        await opened(store)

        await runReview(store)

        #expect(writer.runs == 0)
        #expect(store.draft(for: pr) == nil)
        #expect(store.reviewBodyNote(for: pr) == nil)
        #expect(store.reviewBodyLane(for: pr) == nil)
    }

    /// Nezapojená session = stav před #521. Návrh se složí, tělo se nepíše a pruh o něm **mlčí**.
    @Test("Bez zapojené session zbyde návrh bez těla")
    func worksWithoutTheSession() async throws {
        let store = try makeStore(findings: [finding()], writer: nil)
        await opened(store)

        await runReview(store)

        #expect(store.draft(for: pr)?.comments.count == 1)
        #expect(store.draft(for: pr)?.body == "")
        #expect(store.reviewBodyNote(for: pr) == nil)
    }

    // MARK: - Co session dostala

    /// **Negativní test na úrovni storu**, ne jen `Policy`: zadání skládá store z živých dat, takže
    /// tohle je to místo, kde by se cesta do cache mohla do vstupu dostat.
    @Test("Ve vstupu není cesta do cache ani pracovní strom")
    func neverSendsAPath() async throws {
        let writer = FakeReviewBodyWriter()
        let store = try makeStore(findings: [finding()], writer: writer)
        await opened(store)

        await runReview(store)

        let input = try #require(writer.requests.first?.input)
        #expect(!input.contains(directory.url.path(percentEncoded: false)))
        #expect(!input.contains("Application Support"))
        #expect(input.contains("Převzaté nálezy (1)"))
    }

    /// **Session se pustí jednou.** Razítko o těle je to, co drží cenu: bez něj by druhé volání
    /// (a v aplikaci druhé načtení diffu) znamenalo druhou session za tytéž peníze.
    ///
    /// Tvrdí se to **přímým druhým voláním**, ne druhým otevřením PR: to by se zastavilo dřív,
    /// o bránu „draft už existuje“ (#520) — a test by pak procházel, i kdyby tahle brána nebyla.
    @Test("Podruhé nad týmž razítkem se session nepustí")
    func runsOnlyOnce() async throws {
        let writer = FakeReviewBodyWriter()
        let store = try makeStore(findings: [finding()], writer: writer)
        await opened(store)
        await runReview(store)
        #expect(writer.runs == 1)

        let record = try #require(store.reviewRecord(for: pr))
        store.startReviewBody(for: pr, plan: Policy.autoDraftPlan(of: record))
        await waitUntil("druhé tělo by doběhlo") { !store.isWritingReviewBody(self.pr) }

        #expect(writer.runs == 1)
    }

    /// **Návrh ze samých sporných nálezů draft nezakládá** (#520) — a tělo to nemá změnit: bylo by
    /// jediným obsahem rozdělaného review, takže by v řádku fronty přibylo „je co poslat“ nad
    /// návrhem, který schválně nic nepřevzal.
    @Test("Bez převzatého nálezu se tělo nepíše")
    func writesNothingWithoutAnAdoptedFinding() async throws {
        let writer = FakeReviewBodyWriter()
        let store = try makeStore(findings: [finding(verdict: .plausible)], writer: writer)
        await opened(store)

        await runReview(store)

        #expect(store.autoDraftStamp(for: pr)?.contested.count == 1)
        #expect(store.draft(for: pr) == nil)
        #expect(writer.runs == 0)
        #expect(store.reviewBodyNote(for: pr) == nil)
    }

    // MARK: - Co po běhu zbude

    @Test("Po doběhnutí pruh řekne, z kolika review se hlas bral")
    func notesTheVoice() async throws {
        let voice = ReviewVoiceLedger(layout: layout)
        await voice.record([
            ReviewVoiceSample(id: "r1", at: Date(timeIntervalSince1970: 1), body: String(repeating: "á", count: 60)),
            ReviewVoiceSample(id: "r2", at: Date(timeIntervalSince1970: 2), body: String(repeating: "é", count: 60)),
        ])
        let store = try makeStore(findings: [finding()], writer: FakeReviewBodyWriter(), voice: voice)
        await opened(store)

        await runReview(store)

        #expect(store.reviewBodyNote(for: pr) == "Tělo je podle tvých posledních review (2).")
        #expect(store.reviewBodyLane(for: pr)?.kind == .reviewBody(samples: 2, used: true))
    }

    /// **Nový uživatel**: žádné uložené review, tělo neutrálně — a pruh to řekne.
    @Test("Bez uložených review je pruh o neutrálním těle")
    func notesTheNeutralFallback() async throws {
        let store = try makeStore(
            findings: [finding()],
            writer: FakeReviewBodyWriter(),
            voice: ReviewVoiceLedger(layout: layout)
        )
        await opened(store)

        await runReview(store)

        #expect(
            store.reviewBodyNote(for: pr)
                == "Tělo je napsané neutrálně — žádné tvoje odeslané review se ještě neuložilo."
        )
    }

    /// **Spadlá session: prázdný composer a věta v pruhu** (zadání #521) — a hlavně **ne pád
    /// návrhu**: převzaté komentáře v panelu zůstávají.
    @Test("Spadlá session nechá composer prázdný a návrh stát")
    func failedSessionKeepsTheDraft() async throws {
        let writer = FakeReviewBodyWriter(answers: [
            ReviewBodyAnswer(text: nil, usage: RunUsage(cost: 0.02), failure: "Session skončila chybou (error).")
        ])
        let store = try makeStore(findings: [finding()], writer: writer)
        await opened(store)

        await runReview(store)

        #expect(store.draft(for: pr)?.comments.count == 1)
        #expect(store.draft(for: pr)?.body == "")
        #expect(
            store.reviewBodyNote(for: pr)
                == "Tělo se nenapsalo, composer zůstal prázdný. Session skončila chybou (error)."
        )
        // **Cena se nese i u nepovedeného běhu**: zabitá session peníze stála taky.
        #expect(store.reviewBodyLane(for: pr)?.usage?.cost == 0.02)
        #expect((store.dailySpend?.cost ?? 0) > 0)
    }

    /// **Selhání se zapíše na disk**, aby se session nepustila po každém dalším otevření PR —
    /// a aby pruh po restartu pořád vysvětloval prázdný composer.
    @Test("Selhání v razítku přežije restart")
    func remembersTheFailure() async throws {
        let writer = FakeReviewBodyWriter(answers: [
            ReviewBodyAnswer(text: nil, usage: nil, failure: "Session nevrátila žádný text.")
        ])
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        let store = try makeStore(findings: [finding()], writer: writer, reviews: reviews)
        await opened(store)
        await runReview(store)

        let restarted = try makeStore(findings: [], writer: nil, reviews: reviews)
        await restarted.loadStoredReviews()

        let body = try #require(restarted.autoDraftStamp(for: pr)?.body)
        #expect(body.failure == .session(detail: "Session nevrátila žádný text."))
        #expect(
            restarted.reviewBodyNote(for: pr)
                == "Tělo se nenapsalo, composer zůstal prázdný. Session nevrátila žádný text."
        )
    }

    // MARK: - Sběr hlasu

    /// **Sbírá se čtením konverzace**, tedy z toho, co je na GitHubu — a cizí review do vzorků
    /// nesmí. Kdyby prosáklo, psal by návrh mým jménem cizím hlasem.
    @Test("Načtená konverzace zapíše do ledgeru jen moje review")
    func collectsTheVoiceFromConversations() async throws {
        let mine = String(repeating: "á", count: 60)
        let conversation = Conversation(
            viewer: "octocat",
            reviews: ConversationPage(
                items: [
                    SubmittedReview(
                        id: "1",
                        author: "octocat",
                        state: .changesRequested,
                        body: mine,
                        submittedAt: Date(timeIntervalSince1970: 10)
                    ),
                    SubmittedReview(
                        id: "2",
                        author: "hubot",
                        state: .approved,
                        body: mine,
                        submittedAt: Date(timeIntervalSince1970: 20)
                    ),
                ],
                total: 2,
                hasNextPage: false
            ),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
        let voice = ReviewVoiceLedger(layout: layout)
        let store = try makeStore(
            findings: [],
            writer: nil,
            voice: voice,
            conversations: [.success(conversation)]
        )

        await store.loadConversation(for: summary())

        #expect(await voice.samples().map(\.id) == ["1"])
    }
}
