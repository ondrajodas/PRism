import Foundation
import Testing

@testable import PRism

/// Kdo se dívá a čí jsou PR v seznamu (#330).
@Suite("AppStore — kdo se dívá (#330)")
@MainActor
struct AppStoreOwnershipTests {
    private func summary(author: String, _ identifier: String = "cli/cli#1") -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ gateway: FakeGitHubGateway, ownLogins: [String] = []) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ownLogins
        return AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    // MARK: - Než login dorazí

    /// **Tohle je ten test, který tvrdí, že se něco nestalo**: dokud login není načtený, nesmí být
    /// nic „moje“. Obrácené výchozí chování by na okamžik po spuštění přehodilo celý seznam
    /// a fronta cizích PR by zmizela.
    @Test("Než se login načte, je všechno cizí")
    func everythingIsTheirsUntilTheViewerArrives() {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        let store = store(gateway)

        // Store existuje, ale `keepFresh()` ještě neproběhl.
        #expect(store.viewer.isEmpty)
        #expect(store.ownLogins.isEmpty)
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .theirs)
        #expect(gateway.viewerRequests == 0)
    }

    /// Když se login zjistit nepovede, zůstává „nevím“ — a to je pořád `.theirs`, ne `.mine`.
    @Test("Selhání dotazu nedělá z cizích PR moje")
    func aFailedViewerLookupNeverClaimsOwnership() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        gateway.viewerFailure = GitHubError.network("bez sítě")
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 1)
        )

        await store.keepFresh()

        #expect(gateway.viewerRequests == 1)
        #expect(store.viewer.isEmpty)
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .theirs)
    }

    // MARK: - Se známým loginem

    @Test("Login se dotáhne při startu a rozřadí seznam")
    func loadsTheViewerAtStartUp() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "OndraJodas"
        let store = store(gateway)

        await store.loadViewer()

        // Drží se tak, jak ho `gh` vrátil; na velikost písmen se neptá porovnání, ne uložení.
        #expect(store.viewer == "OndraJodas")
        #expect(store.ownership(of: summary(author: "ondrajodas")) == .mine)
        #expect(store.ownership(of: summary(author: "kolega")) == .theirs)
    }

    /// Není to údaj o PR, takže na tik pollingu nepatří: tři tiky, jeden dotaz.
    @Test("Login se tahá jednou za spuštění, ne na každý tik")
    func asksForTheViewerOnlyOnce() async {
        let gateway = FakeGitHubGateway(always: .success([summary(author: "kolega")]))
        gateway.viewer = "ondrajodas"
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 3)
        )

        await store.keepFresh()

        #expect(gateway.viewerRequests == 1)
        #expect(store.viewer == "ondrajodas")
    }

    /// Loginy z konfigurace se k viewerovi **přidávají** — na tom stojí PR agenta s vlastním účtem.
    @Test("Loginy z konfigurace se přidají k viewerovi")
    func configuredLoginsJoinTheViewer() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"
        let store = store(gateway, ownLogins: ["github-actions[bot]", "  "])

        await store.loadViewer()

        #expect(store.ownLogins == ["ondrajodas", "github-actions[bot]"])
        #expect(store.ownership(of: summary(author: "github-actions[bot]")) == .mine)
    }

    // MARK: - Zdroj vlastních PR

    @Test("Výchozí konfigurace vlastní PR sleduje, uložená bez toho zdroje ne")
    func knowsWhetherOwnPullRequestsAreTracked() {
        let gateway = FakeGitHubGateway(always: .success([]))
        #expect(store(gateway).tracksOwnPullRequests)

        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        let withoutOwnSource = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource()
        )
        #expect(!withoutOwnSource.tracksOwnPullRequests)
    }

    // MARK: - Sekce `Moje PR` (#331)

    /// Store po jednom tiku, ve kterém dorazil daný seznam a znám login.
    private func loaded(
        _ list: [PullRequestSummary],
        viewer: String = "ondrajodas",
        sources: [Source]? = nil
    ) async -> AppStore {
        let gateway = FakeGitHubGateway(always: .success(list))
        gateway.viewer = viewer
        var configuration = Configuration.standard
        if let sources { configuration.global.sources = sources }
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()
        return store
    }

    @Test("Sekce ukazuje moje PR, fronta cizí")
    func narrowsTheListByAuthor() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.visibleOwnPullRequests.map(\.number) == [1])
        // Fronta je od #332 druhá strana téhož rozřazení.
        #expect(store.visibleQueuePullRequests.map(\.number) == [2])
        // **Tvrzení, že se něco nestalo**: rozřazení je pohled, takže plný ani zúžený seznam
        // nezmenší — na plném visí úklid cache a okno nastavení.
        #expect(store.pullRequests.count == 2)
        #expect(store.visiblePullRequests.count == 2)
    }

    /// Filtr je pohled a rozřazení podle autora je **další zúžení nad tímtéž** — takže se skládají
    /// a schované moje PR se počítají zvlášť od schovaných cizích.
    @Test("Filtr se na sekci Moje PR skládá s rozřazením")
    func combinesTheFilterWithTheOwnership() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "ondrajodas", "ondrajodas/PRism#2"),
            summary(author: "kolega", "cli/cli#3"),
        ])

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/cli")!]))

        #expect(store.visibleOwnPullRequests.map(\.number) == [1])
        #expect(store.hiddenOwnPullRequestCount == 1)
        // Schoval jedno **moje** a nic cizího, takže nad frontou nemá lišta co hlásit (#332):
        // společné číslo by tam mluvilo o řádku, který ve frontě nikdy nebyl.
        #expect(store.hiddenQueuePullRequestCount == 0)
    }

    @Test("Odznak počítá vlastní PR, na kterých leží tah")
    func countsTheBadgeFromWork() async {
        let mine = summary(author: "ondrajodas", "cli/cli#1")
        let store = await loaded([mine, summary(author: "ondrajodas", "cli/cli#2")])

        #expect(store.railMineCount == 0)

        store.reviewRecords[mine.id] = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])

        #expect(store.railMineCount == 1)
    }

    /// Druhá polovina odznaku: **nevyřešené cizí vlákno** z načtené konverzace. Testuje to
    /// zapojení, ne pravidlo (to má `OwnPullRequestsTests`) — podstrčit sem cestu k jiné konverzaci
    /// by z odznaku udělalo číslo o cizí diskuzi.
    ///
    /// **Obrácené #335** (do té doby tenhle test tvrdil, že odznak před kliknutím do PR vlákno
    /// nepočítá, protože konverzace v paměti není). Rozhlídka po cizí aktivitě si o konverzaci
    /// vlastních PR řekne **sama při tiku**, takže se odznak dozví o vlákně bez kliknutí — a to je
    /// zrovna ta spodní hranice, kterou #331 zapsalo jako vědomou a #335 posunulo. Zbývá jen tam,
    /// kam rozhlídka za jeden průchod nedosáhne (`Policy.activitySweepLimit`).
    @Test("Odznak počítá i nevyřešené cizí vlákno z načtené konverzace")
    func countsForeignThreadsFromLoadedConversations() async {
        let mine = summary(author: "ondrajodas", "cli/cli#1")
        let thread = ReviewThread(
            id: "t1",
            path: "Cart.php",
            line: 27,
            originalLine: 27,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(
                items: [
                    ThreadComment(
                        id: "c1",
                        author: "kolega",
                        body: "tohle přepiš",
                        createdAt: Date(timeIntervalSince1970: 1_000),
                        url: URL(string: "https://github.com/cli/cli/pull/1#discussion_c1")!
                    ),
                ],
                total: 1,
                hasNextPage: false
            )
        )
        let gateway = FakeGitHubGateway(
            always: .success([mine]),
            conversations: [
                .success(
                    Conversation(
                        viewer: "ondrajodas",
                        reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
                        threads: ConversationPage(items: [thread], total: 1, hasNextPage: false),
                        comments: ConversationPage(items: [], total: 0, hasNextPage: false)
                    )
                ),
            ]
        )
        gateway.viewer = "ondrajodas"
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()

        // Konverzaci dotáhla **rozhlídka po cizí aktivitě** (#335) uvnitř prvního tiku, takže
        // odznak o vlákně ví bez kliknutí do PR.
        #expect(gateway.conversationRequests == [mine.id])
        #expect(store.railMineCount == 1)

        // A druhé načtení nic nemění — konverzace v paměti platí, dokud se nepohne `updatedAt`.
        await store.loadConversation(for: mine)

        #expect(gateway.conversationRequests == [mine.id])
        #expect(store.railMineCount == 1)
    }

    /// Nula nad nenačteným seznamem vypadá jako hotovo — tatáž úvaha jako u fronty.
    @Test("Odznak je nil, dokud se seznam nenačte")
    func hasNoBadgeBeforeTheFirstTick() {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.viewer = "ondrajodas"

        #expect(store(gateway).railMineCount == nil)
    }

    @Test("Prázdná sekce bez zdroje řekne, že zdroj chybí")
    func explainsTheMissingSource() async {
        let store = await loaded([summary(author: "kolega", "cli/cli#2")], sources: [.reviewRequested])

        #expect(store.ownListEmptyReason == .ownSourceMissing)
    }

    @Test("Prázdná sekce se zdrojem i loginem je ten dobrý stav")
    func explainsTheGoodEmptiness() async {
        let store = await loaded([summary(author: "kolega", "cli/cli#2")])

        #expect(store.ownListEmptyReason == .noOwnPullRequests)
    }

    /// Selhaný dotaz na login (#330) končí prázdným viewerem, a **tohle** je ta věta, kterou to
    /// v okně vysvětlí — ne „nic vlastního nemáš“.
    @Test("Bez načteného loginu řekne sekce, že neví, kdo jsem")
    func explainsTheUnknownViewer() async {
        let store = await loaded([summary(author: "ondrajodas", "cli/cli#1")], viewer: "")

        #expect(store.ownListEmptyReason == .unknownViewer)
        #expect(store.visibleOwnPullRequests.isEmpty)
    }

    @Test("Neprázdná sekce žádný důvod nedá")
    func hasNoReasonWithOwnPullRequests() async {
        let store = await loaded([summary(author: "ondrajodas", "cli/cli#1")])

        #expect(store.ownListEmptyReason == nil)
    }

    /// Deska bere **plný** seznam, ne zúžený filtrem — tvrdí o tom, co je na tahu, ne o tom,
    /// co je zrovna vidět v seznamu.
    @Test("Moje PR na desce se filtrem neschovají")
    func keepsTheBoardIntact() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "ondrajodas", "ondrajodas/PRism#2"),
        ])

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/cli")!]))

        #expect(store.boardEntries.count == 2)
        #expect(store.visibleOwnPullRequests.count == 1)
    }
}
