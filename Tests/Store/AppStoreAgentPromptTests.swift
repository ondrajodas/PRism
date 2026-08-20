import Foundation
import Testing

@testable import PRism

/// Zadání pro agenta ve store (#333) a brána na zakládání draftu u vlastního PR.
///
/// Proti **skutečnému** `ReviewDraftStore` nad dočasnou složkou: to hlavní tvrzení je, že na
/// vlastním PR draft **nevznikne** — a existující se nezahodí. O obojím rozhoduje obsah disku,
/// takže fake by měřil sám sebe.
@Suite("AppStore — zadání pro agenta")
@MainActor
struct AppStoreAgentPromptTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    /// Autor PR. `mine` znamená, že se shoduje s tím, kdo se dívá.
    private func detail(author: String) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: author,
            headSha: "9c1de02aaaa",
            baseSha: "bbbb2222",
            headRef: "issue-320-timeout",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary(author: String) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func conversation(
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = []
    ) -> Conversation {
        Conversation(
            viewer: "ondra",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func comment(id: String = "c1", body: String = "tohle se potká s #318") -> ThreadComment {
        ThreadComment(
            id: id,
            author: "kolega",
            body: body,
            createdAt: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/cli/cli/pull/42#issuecomment-1")!
        )
    }

    /// Login, který se počítá za můj. Bere se z konfigurace, takže test nemusí čekat na `gh` —
    /// je to tatáž cesta jako u `viewer`, obojí složí `Policy.ownLogins`.
    private func configuration(mine: [String]) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.ownLogins = mine
        return configuration
    }

    private func store(
        author: String,
        mine: [String],
        drafts: ReviewDraftStore? = nil,
        findings: [ReportedFinding] = [],
        conversations: [Result<Conversation, any Error>] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary(author: author)]),
                detail: .success(detail(author: author)),
                conversations: conversations
            ),
            configuration: configuration(mine: mine),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            drafts: drafts ?? ReviewDraftStore(layout: layout)
        )
    }

    /// Store s načteným detailem — bez něj se neví, kdo je autor ani proti které hlavě.
    private func prepared(
        author: String,
        mine: [String],
        drafts: ReviewDraftStore? = nil,
        findings: [ReportedFinding] = [],
        conversations: [Result<Conversation, any Error>] = []
    ) async -> AppStore {
        let store = store(
            author: author,
            mine: mine,
            drafts: drafts,
            findings: findings,
            conversations: conversations
        )
        await store.loadDetail(for: summary(author: author))
        return store
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

    // MARK: - Brána na draft

    /// **Nejdůležitější test celého #333.** Draft na vlastním PR nesmí ani vzniknout: odeslat ho
    /// není kudy (GitHub review na vlastní PR odmítne), takže by z něj byl PR uvízlý v sekci
    /// `Rozdělaná`, ze které se nedá nic udělat.
    @Test("Na vlastním PR se draft nedá založit, i když je hlava známá")
    func refusesToComposeOnMyOwnPullRequest() async {
        let store = await prepared(author: "ondra", mine: ["ondra"])

        #expect(store.head(of: pr) == "9c1de02aaaa")
        #expect(!store.canComposeDraft(for: pr))
    }

    @Test("Na cizím PR se draft zakládat dá")
    func allowsComposingOnSomebodyElsesPullRequest() async {
        let store = await prepared(author: "kolega", mine: ["ondra"])

        #expect(store.canComposeDraft(for: pr))
    }

    /// Rozřazení je **necitlivé na velikost písmen** (#330), protože `gh` vrací kanonický tvar,
    /// kdežto do konfigurace si člověk píše, co vidí v prohlížeči.
    @Test("Login se porovnává bez ohledu na velikost písmen")
    func comparesLoginsCaseInsensitively() async {
        let store = await prepared(author: "OndraJodas", mine: ["ondrajodas"])

        #expect(!store.canComposeDraft(for: pr))
    }

    /// Dokud se neví, kdo se dívá, je podle `Policy.ownership` všechno cizí — tedy bezpečná
    /// strana pro seznam. Cena je, že se na vlastním PR dá draft založit, dokud login nedorazí;
    /// je to tentýž kompromis jako u předvyplněného verdiktu (#114).
    @Test("Bez známého loginu se brána nezavře")
    func staysOpenWhileTheLoginIsUnknown() async {
        let store = await prepared(author: "ondra", mine: [])

        #expect(store.canComposeDraft(for: pr))
    }

    /// **Existující draft se nezahodí.** Zůstává vidět (bubliny v diffu ho kreslí z komentářů,
    /// panel ze zadání) a jde smazat — tiše zmizelá data jsou horší než data, která nejdou
    /// odeslat.
    @Test("Draft z dřívějška zůstane a dá se smazat")
    func keepsAnExistingDraftReadableAndDeletable() async throws {
        let drafts = ReviewDraftStore(layout: layout)
        // Draft se zakládá jako cizí PR, tedy tou cestou, kterou doopravdy vznikl — až potom se
        // z PR stane vlastní. Přesně ten stav, do kterého se dostane, kdo si dopsal `author:@me`.
        let composing = await prepared(author: "kolega", mine: ["ondra"], drafts: drafts)
        composing.setDraftBody("rozepsáno", for: pr)
        await waitForStoredDraft(of: pr, in: drafts)

        let mineStore = await prepared(author: "ondra", mine: ["ondra"], drafts: drafts)
        await mineStore.loadStoredDrafts()

        #expect(!mineStore.canComposeDraft(for: pr))
        #expect(mineStore.hasDraft(pr))
        #expect(mineStore.draft(for: pr)?.body == "rozepsáno")

        mineStore.discardDraft(for: pr)
        #expect(!mineStore.hasDraft(pr))
    }

    /// Panel `Moje review` na vlastním PR není, takže odkaz na rozdělané review musí vést tam,
    /// kde ten draft doopravdy je — jinak by se přepnulo na segment, který se nekreslí.
    @Test("Odkaz na rozdělané review vede na vlastním PR do zadání")
    func revealsTheAgentPromptInsteadOfTheDraft() async {
        let store = await prepared(author: "ondra", mine: ["ondra"])
        store.revealDraft(in: pr)

        #expect(store.reviewPanelTab == .agentPrompt)
        #expect(store.isReviewPanelExpanded)
    }

    @Test("Na cizím PR vede odkaz pořád do rozdělaného review")
    func stillRevealsTheDraftOnSomebodyElses() async {
        let store = await prepared(author: "kolega", mine: ["ondra"])
        store.revealDraft(in: pr)

        #expect(store.reviewPanelTab == .draft)
    }

    // MARK: - Zadání

    /// Zadání se skládá z **uloženého záznamu i z načtené konverzace**, a nese hlavu, proti které
    /// platí (tvrdá podmínka č. 5).
    @Test("Zadání nese nálezy, komentáře, větev i hlavu")
    func composesThePromptFromEverythingItKnows() async {
        let store = await prepared(
            author: "ondra",
            mine: ["ondra"],
            findings: [blockingFinding()],
            conversations: [.success(conversation(comments: [comment()]))]
        )
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
        await store.loadConversation(for: summary(author: "ondra"))

        let prompt = store.agentPrompt(for: pr)

        #expect(prompt.included.count(of: .findings) == 1)
        #expect(prompt.included.count(of: .comments) == 1)
        #expect(prompt.blocking == 1)
        #expect(prompt.text.contains("cli/cli#42"))
        #expect(prompt.text.contains("ve větvi issue-320-timeout"))
        #expect(prompt.text.contains("hlava 9c1de0"))
        #expect(prompt.text.contains("total() ignoruje množství"))
        #expect(prompt.text.contains("tohle se potká s #318"))
    }

    /// Nenačtená konverzace se **nesmí** projevit jako „nikdo nic nenapsal“ — je to mezera v tom,
    /// co aplikace ví, a `Conversation` se nepersistuje, takže po startu je to normální stav.
    @Test("Bez načtené konverzace to zadání přizná")
    func admitsThatTheConversationIsMissing() async {
        let store = await prepared(author: "ondra", mine: ["ondra"], findings: [blockingFinding()])
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }

        let prompt = store.agentPrompt(for: pr)

        #expect(!prompt.isConversationLoaded)
        #expect(prompt.text.contains("Konverzace k PR se nenačetla"))
    }

    /// Odmítnutý nález v zadání není, dokud se o něj výslovně neřekne — a pak v něm je i s tím,
    /// že je odmítnutý. Přepnutí volby se musí projevit v **textu**, ne jen v počtu.
    @Test("Volba se přepne a projeví se v textu")
    func togglesAnOptionAndRecomposes() async {
        let dismissed = ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "style",
            verdict: .plausible,
            shortSummary: nil,
            summary: "prý chyba",
            failureScenario: nil
        )
        let store = await prepared(author: "ondra", mine: ["ondra"], findings: [dismissed])
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
        guard let finding = store.reviewRecord(for: pr)?.findings.first else {
            Issue.record("nález se neuložil")
            return
        }
        await store.dismissFinding(finding, as: .invalid, for: pr)

        #expect(store.agentPrompt(for: pr).included.total == 0)
        #expect(!store.hasAgentPromptItems(for: pr))

        store.toggleAgentPromptOption(.dismissedFindings)

        #expect(store.agentPrompt(for: pr).included.count(of: .dismissedFindings) == 1)
        #expect(store.hasAgentPromptItems(for: pr))
        #expect(store.agentPrompt(for: pr).text.contains("prý chyba"))
    }

    /// `⌘⇧P` se ptá při každém překreslení, takže se **nesmí** ptát skládáním textu. Odpověď
    /// musí být tatáž jako u hotového zadání, jinak by byla zkratka zakázaná nad neprázdným
    /// panelem.
    @Test("Předfiltr pro zkratku odpovídá hotovému zadání")
    func agreesWithTheComposedPrompt() async {
        let empty = await prepared(author: "ondra", mine: ["ondra"])
        #expect(!empty.hasAgentPromptItems(for: pr))
        #expect(empty.agentPrompt(for: pr).isEmpty)

        let store = await prepared(author: "ondra", mine: ["ondra"], findings: [blockingFinding()])
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }

        #expect(store.hasAgentPromptItems(for: pr))
        #expect(!store.agentPrompt(for: pr).isEmpty)
    }

    // MARK: - `Prompt →` z řádku

    /// Akce tlačítka z řádku seznamu (#331, napojená #333): **otevřít PR a v něm panel**.
    ///
    /// Otevření záložky je součást akce, ne krok před ní — bez něj se nenačte konverzace a zadání by
    /// z řádku vyšlo bez vláken a komentářů, tedy bez většiny toho, co se předává.
    @Test("Prompt z řádku otevře PR a v něm panel se zadáním")
    func opensThePullRequestAndItsPanel() async {
        let store = await prepared(author: "ondra", mine: ["ondra"])
        store.isReviewPanelExpanded = false
        // `Kontroly`, ne `Commity`: od #392 panel v `Commitech` **je**, takže by se nepřepínalo
        // nic a test by tvrdil něco o tabu, ve kterém ta situace nenastane.
        store.setDetailTab(.checks, for: pr)

        store.openAgentPrompt(in: pr)

        #expect(store.activeTab == .pullRequest(pr))
        #expect(store.openTabs.contains(pr))
        #expect(store.reviewPanelTab == .agentPrompt)
        #expect(store.isReviewPanelExpanded)
        // Panel v tabu `Kontroly` není, takže se musí přepnout na ten, ve kterém je — jinak se
        // rozloží něco, co není vidět.
        #expect(store.detailTab(for: pr) == .standard)
    }

    /// **Nezakazuje se, když není co předat.** Je to navigace: `hasAgentPromptItems` hlídá sazbu
    /// textu (zkratka, `Sestavit prompt →`), kdežto v seznamu by měřilo stav před otevřením PR
    /// a schovalo by cestu k panelu zrovna u PR, jehož materiál leží v diskuzi.
    @Test("Prompt z řádku vede do panelu i nad prázdným zadáním")
    func opensThePanelEvenWithNothingToHandOver() async {
        let store = await prepared(author: "ondra", mine: ["ondra"])

        #expect(!store.hasAgentPromptItems(for: pr))

        store.openAgentPrompt(in: pr)

        #expect(store.activeTab == .pullRequest(pr))
        #expect(store.reviewPanelTab == .agentPrompt)
    }
}
