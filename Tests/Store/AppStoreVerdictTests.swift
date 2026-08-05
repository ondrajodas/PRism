import Foundation
import Testing

@testable import PRism

/// Předvyplnění verdiktu návrhem z nálezů (#114).
///
/// Proti **skutečnému** `ReviewStore` i `ReviewDraftStore` nad dočasnou složkou: to hlavní
/// tvrzení celého issue je, že se předvyplněním **nic neuloží** — a to fake ověřit neumí,
/// protože právě obsah disku rozhoduje, jestli draft existuje.
@Suite("AppStore — předvyplněný verdikt")
@MainActor
struct AppStoreVerdictTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var detail: PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "kolega",
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
            author: "kolega",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func blockingFinding() -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: "total() ignoruje množství",
            failureScenario: nil
        )
    }

    /// Konverzace, ve které se dívá `viewer` — z ní se pozná vlastní PR.
    private func conversation(viewer: String) -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Odesílání povolené pro tohle repo — brána je první důvod v `sendBlock`, takže bez ní
    /// by testy odesílatelnosti měřily ji, ne verdikt.
    private var publishing: Configuration {
        var configuration = Configuration.standard
        configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        return configuration
    }

    private func store(
        findings: [ReportedFinding] = [],
        drafts: ReviewDraftStore? = nil,
        conversations: [Result<Conversation, any Error>] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .success(detail),
                conversations: conversations
            ),
            configuration: publishing,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            drafts: drafts ?? ReviewDraftStore(layout: layout),
            gh: URL(filePath: "/usr/bin/true")
        )
    }

    /// Detail je to, odkud se ví, proti kterému commitu se review píše — a taky kdo je autor.
    private func reviewed(
        findings: [ReportedFinding] = [],
        drafts: ReviewDraftStore? = nil,
        conversations: [Result<Conversation, any Error>] = []
    ) async -> AppStore {
        let store = self.store(findings: findings, drafts: drafts, conversations: conversations)
        await store.loadDetail(for: summary())
        store.startReview(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        return store
    }

    /// Uložení draftu běží v tasku, takže se na něj musí počkat, než se sáhne na disk. Točení
    /// přes `Task.yield()` je stejná cesta jako u ostatních testů store — čekat na continuation
    /// by znamenalo, že se test při chybě zasekne místo aby spadl.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Předvyplnění

    /// **Nejdůležitější test celého #114.** Verdikt je navržený, ale rozdělané review
    /// nevzniklo: kdyby se předvyplněná hodnota zapsala, existoval by draft po každém PR,
    /// které si někdo jen otevřel — a „draft existuje“ musí znamenat „je co poslat“, protože
    /// na tom stojí indikátor v řádku seznamu i mazání prázdného draftu.
    @Test("Předvyplnění nic neuloží")
    func suggestsWithoutCreatingADraft() async throws {
        let drafts = ReviewDraftStore(layout: layout)
        let store = await reviewed(drafts: drafts)

        #expect(store.effectiveVerdict(for: pr) == EffectiveVerdict(verdict: .approve, origin: .suggested))
        // Indikátor v řádku seznamu i tlačítka v panelu se ptají tímhle.
        #expect(!store.hasDraft(pr))
        #expect(store.draft(for: pr) == nil)
        // A na disku po tom nezůstalo nic ani pro restart.
        #expect(try await drafts.load().drafts.isEmpty)
        let restarted = self.store()
        await restarted.loadStoredDrafts()
        #expect(!restarted.hasDraft(pr))
    }

    /// Blokující nález navrhne `Vyžádat změny`, ne `Schválit` — jinak by předvyplnění
    /// schvalovalo PR s nahlášenou chybou.
    @Test("Blokující nález navrhne vyžádání změn")
    func suggestsRequestChangesForABlockingFinding() async {
        let store = await reviewed(findings: [blockingFinding()])

        #expect(store.effectiveVerdict(for: pr)?.verdict == .requestChanges)
        #expect(store.effectiveVerdict(for: pr)?.isSuggested == true)
    }

    /// Bez doběhlého review není z čeho soudit, takže se **nepředvyplní nic** a odeslání dál
    /// čeká na ruční volbu. Schválit PR proto, že review neproběhlo, je nejdražší chyba, jakou
    /// tahle aplikace umí udělat.
    @Test("Bez doběhlého review se nepředvyplní nic")
    func doesNotSuggestWithoutAReview() async {
        let store = self.store()
        await store.loadDetail(for: summary())
        store.setDraftBody("tělo", for: pr)
        await settle()

        #expect(store.effectiveVerdict(for: pr) == nil)
        #expect(store.draftSendBlock(for: pr) == .noVerdict)
    }

    /// S návrhem se dá odeslat, aniž by se na verdikt kliklo — to je celý smysl #114.
    @Test("S návrhem odpadá důvod „vyber verdikt“")
    func stopsBlockingOnAMissingVerdict() async {
        let store = await reviewed()
        store.setDraftBody("tělo", for: pr)
        await settle()

        #expect(store.draft(for: pr)?.verdict == nil)
        #expect(store.draftSendBlock(for: pr) == nil)
    }

    /// Moje volba přebíjí návrh a druhý klik ji ruší — pak se návrh vrátí. Tím se z panelu
    /// nedá dostat do stavu „nevybráno“, dokud je z čeho navrhovat.
    @Test("Moje volba přebije návrh a zrušení ho vrátí")
    func theChoiceOverridesAndCancelBringsTheSuggestionBack() async {
        let store = await reviewed()

        store.setDraftVerdict(.requestChanges, for: pr)
        await settle()
        #expect(store.effectiveVerdict(for: pr) == EffectiveVerdict(verdict: .requestChanges, origin: .chosen))
        #expect(store.hasDraft(pr))

        store.setDraftVerdict(nil, for: pr)
        await settle()
        #expect(store.effectiveVerdict(for: pr) == EffectiveVerdict(verdict: .approve, origin: .suggested))
        // Draft, ve kterém po zrušení nic nezůstalo, se maže — návrh ho nedrží naživu.
        #expect(!store.hasDraft(pr))
    }

    // MARK: - Vlastní PR

    /// Na vlastním PR GitHub `APPROVE` ani `REQUEST_CHANGES` nevezme (změřeno u #62), takže
    /// se návrh nenabídne — jinak by předvyplnění dovedlo k `422` snáz než dnes.
    @Test("Na vlastním PR se návrh nepředvyplní")
    func doesNotPrefillOnMyOwnPullRequest() async {
        let store = await reviewed(conversations: [.success(conversation(viewer: "kolega"))])
        await store.loadConversation(for: summary())

        #expect(store.isOwnPullRequest(pr))
        #expect(store.effectiveVerdict(for: pr) == nil)
        // Návrh z nálezů sám nezmizel — v potvrzení odeslání se pořád ukazuje k porovnání.
        #expect(store.suggestedVerdict(for: pr) == .approve)
    }

    /// Cizí PR je běžný případ: `viewer` je někdo jiný než autor a předvyplní se.
    @Test("Na cizím PR se návrh předvyplní")
    func prefillsOnSomebodyElsesPullRequest() async {
        let store = await reviewed(conversations: [.success(conversation(viewer: "ondra"))])
        await store.loadConversation(for: summary())

        #expect(!store.isOwnPullRequest(pr))
        #expect(store.effectiveVerdict(for: pr)?.origin == .suggested)
    }

    /// Dokud konverzace nedorazí, nevíme, kdo se dívá — a opatrnost by návrh schovala u každého
    /// PR, dokud se nenačte. Cena omylu je jedna chyba od GitHubu, která si o `Jen komentář`
    /// řekne sama.
    @Test("Bez načtené konverzace se předvyplňuje dál")
    func prefillsWhileTheConversationIsNotLoaded() async {
        let store = await reviewed()

        #expect(!store.isOwnPullRequest(pr))
        #expect(store.effectiveVerdict(for: pr)?.origin == .suggested)
    }

    // MARK: - Co odejde

    /// **Co je v potvrzení vidět, to se odešle** — takže snímek nese předvyplněný verdikt,
    /// i když ho uložený draft nemá. Že je z návrhu, se pozná z `verdictOrigin`.
    @Test("Odesílaný snímek nese návrh, uložený draft ne")
    func sendsTheSuggestionWithoutStoringIt() async throws {
        let drafts = ReviewDraftStore(layout: layout)
        let store = await reviewed(drafts: drafts)
        store.setDraftBody("tělo", for: pr)
        await settle()

        let submission = store.submission(for: summary())

        #expect(submission?.draft.verdict == .approve)
        #expect(submission?.verdictOrigin == .suggested)
        #expect(submission?.isVerdictSuggested == true)
        // Rozchod je vyhrazený **vědomému** přepnutí, takže předvyplněný verdikt jím není.
        #expect(submission?.contradictsSuggestion == false)
        // A na disku pořád leží draft bez verdiktu.
        #expect(try await drafts.load(for: pr)?.verdict == nil)
    }

    /// Vybraný verdikt se snímkem nepřepisuje — návrh doplňuje jen tam, kde žádný není.
    @Test("Vybraný verdikt se v snímku nepřepíše návrhem")
    func keepsMyChoiceInTheSnapshot() async {
        let store = await reviewed(findings: [blockingFinding()])
        store.setDraftVerdict(.approve, for: pr)
        await settle()

        let submission = store.submission(for: summary())

        #expect(submission?.draft.verdict == .approve)
        #expect(submission?.verdictOrigin == .chosen)
        // Vědomé přepnutí návrhu se v potvrzení hlásí nahlas.
        #expect(submission?.contradictsSuggestion == true)
    }
}
