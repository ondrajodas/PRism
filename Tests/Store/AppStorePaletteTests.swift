import Foundation
import Testing

@testable import PRism

/// Command palette ⌘K ve storu (#184): co se v ní nabízí a co se stane po `↵`.
///
/// Nejcennější tvrzení je to, které mluví o tom, co se **nestalo**: paleta si nesmí nic
/// dotáhnout. Hledá se v paměti, takže po sestavení katalogu ani po vykonání cíle nesmí gateway
/// dostat jediné volání navíc — jinak by z každého stisku klávesy koukal podproces na GitHub.
@Suite("AppStore — command palette")
@MainActor
struct AppStorePaletteTests {
    private let vault = PRIdentifier("keboola/vault#85")!
    private let connection = PRIdentifier("keboola/connection#21663")!

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        return configuration
    }

    private func summary(
        _ id: PRIdentifier,
        title: String = "titulek",
        author: String = "kdosi",
        updatedAt: TimeInterval = 100
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: title,
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    /// Store po jednom tiku, ve kterém dorazila daná PR.
    ///
    /// `viewer` je `nil` schválně jako výchozí: většina testů palety se čí PR neptá a bez loginu je
    /// podle `Policy.ownership` všechno cizí (#330), takže katalog má jednu skupinu pull requestů.
    private func loaded(
        _ list: [PullRequestSummary],
        diffs: [Result<String, any Error>] = [],
        viewer: String? = nil,
        ownLogins: [String] = []
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(always: .success(list), diffs: diffs)
        gateway.viewer = viewer
        var config = configuration
        config.global.ownLogins = ownLogins
        let store = AppStore(
            gateway: gateway,
            configuration: config,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()
        return (store, gateway)
    }

    private func record(_ findings: [ReportedFinding], headSha: String = "aaaa1111") -> ReviewRecord {
        makeRecord(runs: [makeStoredRun(findings: findings, headSha: headSha)], headSha: headSha)
    }

    private func items(of store: AppStore, group: CommandPalette.Group) -> [CommandPalette.Item] {
        store.paletteItems.filter { $0.group == group }
    }

    /// Řádky, které pro dotaz vyjdou z dané skupiny — **přes `paletteSections(for:)`**, tedy tou
    /// cestou, kterou jde okno. Repozitáře se v `paletteItems` nevyskytují (skládají se až pro
    /// dotaz), takže by je pomocník výš nenašel.
    private func rows(
        of store: AppStore,
        group: CommandPalette.Group,
        query: String
    ) -> [CommandPalette.Item] {
        store.paletteSections(for: query)
            .first { $0.group == group }?
            .hits
            .map(\.item) ?? []
    }

    /// Store s katalogem repozitářů v cache v dočasné složce (#533).
    ///
    /// Katalog se **dotáhne** (`refreshStale`), aby v cache něco leželo, a pak se do storu podá
    /// tentýž objekt — okno by se k němu dostalo přes `store.repositoryCatalog`. Počty volání
    /// se čtou z gateway až **po** té přípravě, takže se do tvrzení o „paleta se nikoho neptá“
    /// nezaplete.
    private func withCatalog(
        _ list: [PullRequestSummary],
        organizations: [String],
        repositories: [String: OrganizationRepositories],
        failing: [String: any Error] = [:],
        ownLogins: [String] = [],
        viewer: String? = nil
    ) async throws -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(always: .success(list))
        gateway.viewer = viewer
        gateway.organizationRepositories = repositories
        gateway.organizationFailures = failing
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource(stopAfter: 1)
        let catalog = RepositoryCatalog(
            gateway: gateway,
            store: RepositoryCatalogStore(layout: CacheLayout(root: workspace.url)),
            time: time
        )
        var config = configuration
        config.global.searchOrganizations = organizations
        config.global.ownLogins = ownLogins
        let store = AppStore(
            gateway: gateway,
            configuration: config,
            time: time,
            repositoryCatalog: catalog
        )
        await store.keepFresh()
        await catalog.refreshStale(organizations: organizations)
        return (store, gateway)
    }

    private func listing(_ organization: String, _ repositories: [(String, Int)])
        -> OrganizationRepositories
    {
        OrganizationRepositories(
            repositories: repositories.map { name, open in
                OrganizationRepository(
                    repo: RepoID(owner: organization, name: name),
                    openPullRequests: open,
                    lastPushedAt: nil
                )
            },
            hitLimit: false
        )
    }

    // MARK: - Otevření

    @Test("⌘K paletu otevře a druhé zmáčknutí zavře")
    func togglingThePalette() async {
        let (store, _) = await loaded([])

        store.togglePalette()
        #expect(store.isPaletteOpen)

        store.togglePalette()
        #expect(!store.isPaletteOpen)
    }

    // MARK: - Katalog

    @Test("Nálezy se hledají ve všech PR, otevřený je první")
    func findingsComeFromEveryPullRequest() async {
        // Nález je to jediné, co tahle aplikace má a prohlížeč ne — hledat ho jen v otevřeném PR
        // by z první skupiny udělalo tu nejužší.
        let (store, _) = await loaded([summary(connection, updatedAt: 200), summary(vault)])
        store.reviewRecords[connection] = record([makeReported(file: "src/Client.php", line: 4, summary: "connection")])
        store.reviewRecords[vault] = record([makeReported(file: "src/Vault.php", line: 8, summary: "vault")])
        store.openTab(vault)

        let titles = items(of: store, group: .findings).map(\.title)

        #expect(titles == ["vault", "connection"])
    }

    @Test("Odmítnutý nález se v paletě nenabízí")
    func dismissedFindingsAreNotOffered() async {
        // Nález, kterému nevěřím, není místo, kam chci skočit.
        let (store, _) = await loaded([summary(vault)])
        let reported = makeReported(file: "src/Vault.php", line: 8, summary: "odmítnutý")
        var record = record([reported])
        record.dismissals = makeDismissals(record.findings)
        store.reviewRecords[vault] = record

        #expect(items(of: store, group: .findings).isEmpty)
    }

    @Test("Nález nese souřadnice PR a jméno souboru, cesta se dá hledat")
    func findingSubtitleAndKeywords() async throws {
        let (store, _) = await loaded([summary(vault)])
        store.reviewRecords[vault] = record([
            makeReported(file: "src/Vault/SecretClient.php", line: 81, summary: "schází secret"),
        ])

        let item = try #require(items(of: store, group: .findings).first)
        #expect(item.title == "schází secret")
        #expect(item.subtitle == "vault#85 · SecretClient.php:81")
        // Celá cesta se do podtitulku nevejde, ale hledat se podle ní musí dát.
        #expect(item.keywords.contains("src/Vault/SecretClient.php"))
        #expect(item.url == URL(string: "https://github.com/keboola/vault/pull/85"))
    }

    @Test("Soubory jsou jen z otevřeného PR")
    func filesComeFromTheOpenPullRequestOnly() async throws {
        // Diff jiného PR v paměti není a dotáhnout si ho by byl ten nový dotaz na GitHub, který
        // zadání zakazuje.
        let text = try Fixture.text("gh/pr-diff-ordinary.diff")
        let (store, gateway) = await loaded([summary(vault), summary(connection)], diffs: [.success(text)])

        #expect(items(of: store, group: .files).isEmpty)

        await store.loadDiff(for: summary(vault))
        store.openTab(vault)
        let files = items(of: store, group: .files)

        #expect(!files.isEmpty)
        #expect(files.allSatisfy { $0.target == .file(vault, path: $0.title) })
        // Odkaz vede na stránku, na které soubor doopravdy je.
        #expect(files.first?.url?.absoluteString.hasSuffix("/files") == true)
        #expect(gateway.diffRequests == [vault])
    }

    @Test("Pull requesty jdou v pořadí seznamu a autora nesou v podtitulku")
    func pullRequestItems() async {
        // Autor je **vidět**, ne jen v klíčových slovech: hledat podle jména se musí dát a z řádku
        // pak musí být poznat, proč vyšel. V klíčových slovech zůstává jen vlastník repa, kterého
        // v podtitulku nikde není.
        let (store, _) = await loaded([
            summary(connection, title: "fix: nezahazovat token", updatedAt: 200),
            summary(vault, title: "feat: šifrovaný secret"),
        ])

        let items = items(of: store, group: .pullRequests)

        #expect(items.map(\.title) == ["fix: nezahazovat token", "feat: šifrovaný secret"])
        #expect(items.first?.subtitle == "connection#21663 · kdosi")
        #expect(items.first?.keywords == ["keboola/connection"])
    }

    // MARK: - Vlastní PR jako druhá skupina (#336)

    @Test("Vlastní PR jsou vlastní skupina, cizí zůstávají v té první")
    func ownPullRequestsGetTheirOwnGroup() async {
        // Rozřazuje `Policy.ownership`, tedy tatáž funkce jako v railu a na dashboardu — podle
        // autora, ne podle zdroje, ze kterého PR přišel.
        let (store, _) = await loaded(
            [
                summary(connection, title: "fix: nezahazovat token", updatedAt: 200),
                summary(vault, title: "feat: šifrovaný secret", author: "OndraJodas"),
            ],
            viewer: "ondrajodas"
        )

        #expect(items(of: store, group: .pullRequests).map(\.title) == ["fix: nezahazovat token"])
        #expect(items(of: store, group: .myPullRequests).map(\.title) == ["feat: šifrovaný secret"])
    }

    /// **Tohle je ten test, který tvrdí, že se něco nestalo**: dokud login nedorazí, nesmí být nic
    /// „moje“ — jinak by paleta na okamžik po spuštění přehodila celý seznam do druhé skupiny.
    @Test("Než se login načte, jsou v paletě všechny PR cizí")
    func everythingIsTheirsUntilTheViewerArrives() async {
        let (store, _) = await loaded([summary(vault, author: "ondrajodas")])

        #expect(items(of: store, group: .myPullRequests).isEmpty)
        #expect(items(of: store, group: .pullRequests).count == 1)
    }

    /// Loginy z konfigurace se k viewerovi přidávají (#330) — na tom stojí PR agenta s vlastním
    /// účtem, který pushuje pod sebou.
    @Test("PR agenta z konfigurace patří do skupiny mých")
    func configuredLoginsCountAsMine() async {
        let (store, _) = await loaded(
            [summary(vault, author: "github-actions[bot]")],
            viewer: "ondrajodas",
            ownLogins: ["github-actions[bot]"]
        )

        #expect(items(of: store, group: .myPullRequests).count == 1)
        #expect(items(of: store, group: .pullRequests).isEmpty)
    }

    /// Skupina je **zařazení**, ne druhá cesta k témuž: druhý případ v `Target` by se rozešel.
    @Test("Vlastní PR má týž cíl i podtitulek jako cizí")
    func ownPullRequestKeepsTheSameTargetAndSubtitle() async throws {
        let (store, _) = await loaded(
            [summary(vault, title: "feat: šifrovaný secret", author: "ondrajodas")],
            viewer: "ondrajodas"
        )

        let item = try #require(items(of: store, group: .myPullRequests).first)
        #expect(item.target == .pullRequest(vault))
        // Podtitulek zůstává `repo#číslo · autor` — `6 k předání` z návrhu se dá napsat teprve
        // s razítkem předání (#334), tak jak to u řádku seznamu rozhodlo #331.
        #expect(item.subtitle == "vault#85 · ondrajodas")
        #expect(item.url == URL(string: "https://github.com/keboola/vault/pull/85"))

        #expect(store.reveal(item.target) == nil)
        #expect(store.openTabs == [vault])
    }

    @Test("Vlastní PR se najde dotazem stejně jako cizí")
    func searchingFindsOwnPullRequestsToo() async {
        let (store, _) = await loaded(
            [
                summary(connection, title: "fix: nezahazovat token", updatedAt: 200),
                summary(vault, title: "feat: token do nastavení", author: "ondrajodas"),
            ],
            viewer: "ondrajodas"
        )

        let sections = Policy.paletteResults(of: store.paletteItems, query: "token")

        #expect(sections.map(\.group) == [.pullRequests, .myPullRequests])
        #expect(sections.last?.hits.map(\.item.title) == ["feat: token do nastavení"])
    }

    @Test("Podle autora se najde pull request, podle repa i nález")
    func searchingByAuthorAndRepository() async throws {
        // Připomínka k #184: hledat se má i podle jména autora a podle jména repozitáře. Autor je
        // jen u PR (u nálezu je jméno v řádku reviewer, ne autor), repo je u nálezu i u PR.
        let text = try Fixture.text("gh/pr-diff-ordinary.diff")
        let (store, _) = await loaded([summary(vault, title: "feat: šifrovaný secret")], diffs: [.success(text)])
        await store.loadDiff(for: summary(vault))
        store.openTab(vault)
        store.reviewRecords[vault] = record([makeReported(file: "src/Vault.php", line: 8, summary: "schází secret")])

        let byAuthor = Policy.paletteResults(of: store.paletteItems, query: "kdosi")
        #expect(byAuthor.map(\.group) == [.pullRequests])
        #expect(byAuthor.first?.hits.first?.item.title == "feat: šifrovaný secret")

        let byRepository = Policy.paletteResults(of: store.paletteItems, query: "vault")
        // Nálezy a PR ano; **soubory ne** — jsou všechny z jednoho otevřeného PR, takže by se
        // vytáhly všechny naráz a v řádku (diffstat v podtitulku) by nebylo poznat proč. Ověřeno
        // vložením regrese: s repem v klíčových slovech souborů tenhle test padá, protože ve
        // výsledku přebude skupina `.files`.
        #expect(byRepository.map(\.group) == [.findings, .pullRequests, .actions])
    }

    @Test("Filtr seznamu paletu nezužuje")
    func theListFilterDoesNotHideResultsFromSearch() async {
        // Filtr je zúžení **seznamu**, kdežto paleta je způsob, jak něco najít — hledání, ze
        // kterého vypadne schovaný PR, je k nepotřebě právě tehdy, když je filtr zapnutý.
        let (store, _) = await loaded([summary(vault), summary(connection)])
        store.setFilter(PullRequestFilter(repositories: [vault.repo]))

        #expect(store.visiblePullRequests.count == 1)
        #expect(items(of: store, group: .pullRequests).count == 2)
    }

    // MARK: - Vykonání

    @Test("Pull request se otevře jako záložka")
    func revealingAPullRequestOpensATab() async {
        let (store, _) = await loaded([summary(vault)])

        #expect(store.reveal(.pullRequest(vault)) == nil)

        #expect(store.openTabs == [vault])
        #expect(store.activeTab == .pullRequest(vault))
    }

    @Test("Soubor otevře záložku, přepne na diff a položí žádost o skok")
    func revealingAFileAsksForAJump() async {
        let (store, _) = await loaded([summary(vault)])

        store.reveal(.file(vault, path: "src/Vault.php"))

        #expect(store.activeTab == .pullRequest(vault))
        #expect(store.detailTab(for: vault) == .filesChanged)
        #expect(store.paletteJump?.file == "src/Vault.php")
        #expect(store.paletteJump?.line == nil)
        // Zvýrazňuje se jen nález — u souboru by rámeček ukazoval, že tam nález je.
        #expect(store.paletteJump?.kind == .file)
    }

    @Test("Nález s místem v kódu vede do diffu")
    func revealingAFindingAsksForAJump() async {
        let (store, _) = await loaded([summary(vault)])

        store.reveal(.finding(vault, file: "src/Vault.php", line: 81))

        #expect(store.detailTab(for: vault) == .filesChanged)
        #expect(store.paletteJump?.line == 81)
        #expect(store.paletteJump?.kind == .finding)
    }

    @Test("Nález bez místa v kódu otevře tab Nálezy a o skok nežádá")
    func findingWithoutAPlaceOpensTheFindingsTab() async {
        // Skok naslepo do diffu je horší než skok tam, kde ten nález doopravdy je.
        let (store, _) = await loaded([summary(vault)])

        store.reveal(.finding(vault, file: nil, line: nil))

        #expect(store.detailTab(for: vault) == .findings)
        #expect(store.paletteJump == nil)
    }

    @Test("Žádost o skok se dá zopakovat")
    func theSameJumpCanBeAskedForTwice() async {
        // `task(id:)` se na shodné hodnotě podruhé nespustí, takže bez vlastního `id` by druhé
        // `↵` na tomtéž nálezu neudělalo nic.
        let (store, _) = await loaded([summary(vault)])

        store.reveal(.finding(vault, file: "src/Vault.php", line: 81))
        let first = store.paletteJump
        store.paletteJump = nil
        store.reveal(.finding(vault, file: "src/Vault.php", line: 81))

        #expect(first != store.paletteJump)
    }

    @Test("Nevyzvednutá žádost se zahodí, když PR ze seznamu vypadne")
    func jumpsAreForgottenWithTheirPullRequest() async {
        // PR mimo seznam se nemá kde nakreslit, takže by žádost zůstala ležet a nikdo by ji
        // nepřečetl.
        let gateway = FakeGitHubGateway([.success([summary(vault)]), .success([])])
        let store = AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource(stopAfter: 1))
        await store.keepFresh()
        store.reveal(.finding(vault, file: "src/Vault.php", line: 81))
        #expect(store.paletteJump != nil)

        // Tik, ve kterém už PR není — úklid jde stejnou cestou jako po pravidelném tiku.
        await store.refresh()

        #expect(store.paletteJump == nil)
    }

    @Test("Akce přepnou pohled na diff, panel a sekci railu")
    func actionsSwitchTheView() async {
        let (store, _) = await loaded([summary(vault)])
        store.openTab(vault)

        store.reveal(.action(.setDiffLayout(.split)))
        #expect(store.diffLayout == .split)

        store.reveal(.action(.setReviewPanel(expanded: false)))
        #expect(!store.isReviewPanelExpanded)

        store.reveal(.action(.openSection(.drafts)))
        #expect(store.railSection == .drafts)
        // Sekce railu je obsah domácí záložky — bez přepnutí by se nad otevřeným PR nestalo nic.
        #expect(store.activeTab == .home)
    }

    @Test("Nastavení si otevře okno, store ho neumí")
    func settingsIsHandedBackToTheWindow() async {
        // Okno nastavení je vlastní scéna, takže ho umí otevřít jedině view. Store to jen řekne
        // volajícímu a **nic si o tom nepamatuje**.
        let (store, _) = await loaded([summary(vault)])
        let before = store.activeTab

        #expect(store.reveal(.action(.openSettings)) == .openSettings)

        #expect(store.activeTab == before)
        #expect(store.paletteJump == nil)
    }

    // MARK: - Repozitáře a druhá úroveň (#533)

    @Test("Skupina Repozitáře se skládá z cache, nadpis vypisuje organizace se snímkem")
    func repositoriesComeFromTheCache() async throws {
        let (store, _) = try await withCatalog(
            [],
            organizations: ["keboola", "ondrajodas"],
            repositories: [
                "keboola": listing("keboola", [("vault", 7), ("vault-cli", 2)]),
                "ondrajodas": listing("ondrajodas", [("PRism", 3)]),
            ]
        )

        let section = try #require(
            store.paletteSections(for: "vault").first { $0.group == .repositories }
        )
        #expect(section.hits.map(\.item.title) == ["keboola/vault", "keboola/vault-cli"])
        // Nadpis mluví o tom, **kde se hledalo** — obě organizace mají snímek.
        #expect(section.detail == "keboola, ondrajodas")
    }

    /// **Organizace bez snímku se v nadpisu nevypisuje**: slibovala by, že se v ní hledalo,
    /// a přitom se ještě nikdy nedotáhla.
    ///
    /// Nedostupnost se dělá **selháním, ne prázdným výpisem** — a to je samo o sobě tvrzení:
    /// organizace, která vrátila prázdný seznam, **snímek má** a do nadpisu patří, protože se
    /// v ní doopravdy hledalo. Ty dva stavy se od #532 nesmí slít.
    @Test("Organizace bez snímku se do nadpisu nedostane")
    func organizationsWithoutASnapshotAreNotClaimed() async throws {
        let (store, _) = try await withCatalog(
            [],
            organizations: ["keboola", "nedostupna"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])],
            failing: ["nedostupna": GitHubError.notFound("neexistuje")]
        )

        let section = try #require(
            store.paletteSections(for: "vault").first { $0.group == .repositories }
        )
        #expect(section.detail == "keboola")
    }

    @Test("↵ na repu nechá v poli chip, dotáhne PR a nezavře paletu")
    func enteringARepositoryOpensTheSecondLevel() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])]
        )
        gateway.repositoryPullRequests = [
            vault.repo: [summary(vault, title: "secret TTL", updatedAt: 300)],
        ]
        store.openPalette()

        store.reveal(.repository(vault.repo))

        #expect(store.paletteLevel == .repository(vault.repo))
        // Paletu zavírá volající podle `Policy.paletteClosesAfter(_:)`, ne `reveal` — a ten cíl
        // ji nechává otevřenou.
        #expect(store.isPaletteOpen)
        #expect(store.paletteStage.chip == "keboola/vault")
        // Než odpověď dorazí, je v kartě věta o dotahování, ne prázdno.
        #expect(store.paletteRepository == .loading)

        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }
        #expect(gateway.repositoryPullRequestRequests == [vault.repo])
        let rows = rows(of: store, group: .repositoryPullRequests, query: "")
        #expect(rows.map(\.title) == ["#85 · secret TTL"])
    }

    @Test("Odznaky ve druhé úrovni se skládají z toho, co store už má")
    func badgesComeFromWhatTheStoreKnows() async throws {
        let queued = summary(vault, title: "cizí", author: "odinuv", updatedAt: 300)
        let mine = PRIdentifier("keboola/vault#84")!
        let (store, gateway) = try await withCatalog(
            [queued],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])],
            ownLogins: ["ondrajodas"],
            viewer: "ondrajodas"
        )
        gateway.repositoryPullRequests = [
            vault.repo: [
                queued,
                summary(mine, title: "moje", author: "ondrajodas", updatedAt: 200),
                summary(PRIdentifier("keboola/vault#88")!, title: "cizí bez fronty", updatedAt: 100),
            ],
        ]
        store.reveal(.repository(vault.repo))
        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }

        let rows = rows(of: store, group: .repositoryPullRequests, query: "")

        #expect(rows.map(\.badge) == [.inQueue, .mine, nil])
    }

    @Test("esc a ⌫ vrací o úroveň a dotažený seznam se zahodí")
    func leavingTheSecondLevelDropsTheList() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])]
        )
        gateway.repositoryPullRequests = [vault.repo: [summary(vault, updatedAt: 300)]]
        store.openPalette()
        store.reveal(.repository(vault.repo))
        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }

        store.leavePaletteRepository()

        #expect(store.paletteLevel == .top)
        #expect(store.paletteRepository == nil)
        // Paleta zůstává otevřená — `esc` v druhé úrovni **nezavírá**.
        #expect(store.isPaletteOpen)
    }

    @Test("Zavření palety ji vrátí do první úrovně")
    func closingThePaletteResetsTheLevel() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])]
        )
        gateway.repositoryPullRequests = [vault.repo: [summary(vault, updatedAt: 300)]]
        store.openPalette()
        store.reveal(.repository(vault.repo))
        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }

        store.closePalette()

        #expect(!store.isPaletteOpen)
        #expect(store.paletteLevel == .top)
        #expect(store.paletteRepository == nil)
    }

    @Test("Selhání dotažení se přizná větou z gh")
    func aFailedListingIsReported() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])]
        )
        gateway.repositoryPullRequestFailures = [vault.repo: GitHubError.notAuthenticated]

        store.reveal(.repository(vault.repo))
        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }

        #expect(store.paletteStage.notice == .failed(GitHubError.notAuthenticated.userDescription))
        // Prázdno by vypadalo jako repo bez otevřených PR, což je jiný stav.
        #expect(store.paletteSections(for: "").isEmpty)
    }

    /// Odpověď na repo, ve kterém paleta už nestojí, se **zahodí** — mezi dotazem a odpovědí se dá
    /// zmáčknout `esc`, a zápis by nakreslil cizí seznam pod chipem, který mluví o něčem jiném.
    @Test("Odpověď na opuštěné repo se do stavu nezapíše")
    func theAnswerForAbandonedRepositoryIsDropped() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7)])]
        )
        gateway.repositoryPullRequests = [vault.repo: [summary(vault, updatedAt: 300)]]

        store.reveal(.repository(vault.repo))
        store.leavePaletteRepository()
        await settle()

        #expect(store.paletteLevel == .top)
        #expect(store.paletteRepository == nil)
    }

    // MARK: - Co se nestalo

    @Test("Hledání ani vykonání se nikoho neptá na GitHub")
    func thePaletteNeverAsksGitHub() async throws {
        // Zadání issue: hledá se nad tím, co je v paměti. Bez tohohle testu by stačilo, aby si
        // katalog někdy dotáhl diff druhého PR, a z každého stisku klávesy by byl podproces.
        let text = try Fixture.text("gh/pr-diff-ordinary.diff")
        let (store, gateway) = await loaded([summary(vault), summary(connection)], diffs: [.success(text)])
        await store.loadDiff(for: summary(vault))
        store.openTab(vault)
        store.reviewRecords[vault] = record([makeReported(file: "src/Vault.php", line: 8, summary: "nález")])
        let searches = gateway.searchCount
        let diffs = gateway.diffRequests.count
        let details = gateway.detailRequests.count
        let conversations = gateway.conversationRequests.count

        // Postavit katalog, projít ho hledáním a vykonat každý druh cíle.
        let catalog = store.paletteItems
        _ = Policy.paletteResults(of: catalog, query: "vault")
        store.reveal(.pullRequest(connection))
        store.reveal(.file(vault, path: "src/Vault.php"))
        store.reveal(.finding(vault, file: "src/Vault.php", line: 8))
        store.reveal(.action(.setDiffLayout(.split)))
        store.reveal(.action(.openSection(.queue)))

        #expect(gateway.searchCount == searches)
        #expect(gateway.diffRequests.count == diffs)
        #expect(gateway.detailRequests.count == details)
        #expect(gateway.conversationRequests.count == conversations)
    }

    /// **Tohle je ten test, kvůli kterému má druhá úroveň jediné volání** (#533): jinak by
    /// z každého úhozu v repu s tisícem PR byl podproces `gh` — a z otevření palety výpis
    /// organizace, který stojí 46,8 s.
    @Test("Paleta nad repem nepustila nic než dotažení seznamu")
    func theSecondLevelAsksOnceAndNothingElse() async throws {
        let (store, gateway) = try await withCatalog(
            [],
            organizations: ["keboola"],
            repositories: ["keboola": listing("keboola", [("vault", 7), ("vault-cli", 2)])]
        )
        gateway.repositoryPullRequests = [vault.repo: [summary(vault, updatedAt: 300)]]
        let searches = gateway.searchCount
        let details = gateway.detailRequests.count
        let repositories = gateway.repositoryRequests.count
        store.openPalette()

        // Psaní v **první** úrovni: katalog rep se prochází z cache, nedotahuje se.
        for prefix in ["v", "va", "vau", "vaul", "vault"] {
            _ = store.paletteSections(for: prefix)
        }
        #expect(gateway.repositoryRequests.count == repositories)
        #expect(gateway.repositoryPullRequestRequests.isEmpty)

        // Vstup do repa: **jedno** volání, a to čtecí.
        store.reveal(.repository(vault.repo))
        await waitUntil("seznam PR repa dorazí") { store.paletteRepository != .loading }
        #expect(gateway.repositoryPullRequestRequests == [vault.repo])

        // Psaní ve **druhé** úrovni: filtruje se dotažený seznam, nic dalšího se neptá.
        for prefix in ["s", "se", "sec", "secr"] {
            _ = store.paletteSections(for: prefix)
        }

        #expect(gateway.repositoryPullRequestRequests == [vault.repo])
        #expect(gateway.repositoryRequests.count == repositories)
        #expect(gateway.searchCount == searches)
        #expect(gateway.detailRequests.count == details)
    }

    /// Otevření palety samo o sobě **nesmí** dotáhnout katalog rep: je to nejdražší čtení
    /// v aplikaci (46,8 s nad `keboola`) a spouští ho jedině okno nastavení.
    @Test("Start ani otevření palety katalog rep nedotahuje, jen čte disk")
    func startingUpOnlyReadsTheCatalogFromDisk() async throws {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.organizationRepositories = ["keboola": listing("keboola", [("vault", 7)])]
        let workspace = try TemporaryDirectory()
        var config = configuration
        config.global.searchOrganizations = ["keboola"]
        let store = AppStore(
            gateway: gateway,
            configuration: config,
            time: FakeTimeSource(stopAfter: 1),
            repositoryCatalog: RepositoryCatalog(
                gateway: gateway,
                store: RepositoryCatalogStore(layout: CacheLayout(root: workspace.url)),
                time: FakeTimeSource(stopAfter: 1)
            )
        )

        await store.keepFresh()
        store.openPalette()
        _ = store.paletteSections(for: "vault")

        #expect(gateway.repositoryRequests.isEmpty)
        // Cache je prázdná, takže skupina `Repozitáře` prostě není — a to je správná odpověď.
        #expect(store.paletteSections(for: "vault").allSatisfy { $0.group != .repositories })
    }

    @Test("Katalog má jednoznačná id")
    func catalogIdentifiersAreUnique() async throws {
        // Dva řádky se stejným `id` by SwiftUI slil do jednoho — a zmizel by ten druhý nález,
        // tedy zrovna to, co se v paletě hledá. `Policy.key(of:)` se proto na `id` nehodí: skládá
        // se z revieweera, místa a shrnutí, takže **týž reviewer, který nahlásí totéž dvakrát**,
        // dá dva stejné klíče. Ověřeno vložením regrese — s klíčem místo indexu tenhle test padá.
        let text = try Fixture.text("gh/pr-diff-ordinary.diff")
        let (store, _) = await loaded([summary(vault), summary(connection)], diffs: [.success(text)])
        await store.loadDiff(for: summary(vault))
        store.openTab(vault)
        let same = makeReported(file: "src/Vault.php", line: 8, summary: "tentýž nález")
        store.reviewRecords[vault] = makeRecord(runs: [makeStoredRun(findings: [same, same])])

        let ids = store.paletteItems.map(\.id)

        #expect(ids.count == Set(ids).count)
    }
}
