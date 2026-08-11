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

    private func summary(_ id: PRIdentifier, title: String = "titulek", updatedAt: TimeInterval = 100) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: title,
            author: "kdosi",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    /// Store po jednom tiku, ve kterém dorazila daná PR.
    private func loaded(
        _ list: [PullRequestSummary],
        diffs: [Result<String, any Error>] = []
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(always: .success(list), diffs: diffs)
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
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
    func findingSubtitleAndKeywords() async {
        let (store, _) = await loaded([summary(vault)])
        store.reviewRecords[vault] = record([
            makeReported(file: "src/Vault/SecretClient.php", line: 81, summary: "schází secret"),
        ])

        let item = try! #require(items(of: store, group: .findings).first)
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

    @Test("Pull requesty jdou v pořadí seznamu a nesou repo i autora k hledání")
    func pullRequestItems() async {
        let (store, _) = await loaded([
            summary(connection, title: "fix: nezahazovat token", updatedAt: 200),
            summary(vault, title: "feat: šifrovaný secret"),
        ])

        let items = items(of: store, group: .pullRequests)

        #expect(items.map(\.title) == ["fix: nezahazovat token", "feat: šifrovaný secret"])
        #expect(items.first?.subtitle == "connection#21663")
        #expect(items.first?.keywords == ["keboola/connection", "kdosi"])
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
