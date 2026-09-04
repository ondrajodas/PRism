import Foundation
import Testing

@testable import PRism

/// Cesta odznaku z fronty na dlaždici v Docku a přihlašovací položky do systému (#529).
///
/// Obojí je **mimo okno**, takže obojí se v okně nedá zkontrolovat: odznak je vidět zrovna tehdy,
/// když se do aplikace nikdo nedívá, a položku vypíná systém. Sada je proto z většiny o tom, co se
/// stát **nesmí** — nula na dlaždici, odznak nad nenačtenou frontou, zápis do systému ze slotu.
@Suite("AppStore — systém (#529)")
@MainActor
struct AppStoreSystemTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    /// Hlavní instalace. Cesta se **skládá z `MainWindow.title`**, ne z literálu, a jsou k tomu dva
    /// důvody: stráž z #411 zakazuje testům jmenovat nainstalovaný bundle hlavní instance (tady je
    /// to jen argument čisté funkce, ale ban je na literál a obcházet ho vlastním zápisem téhož by
    /// bylo horší), a pravidlo „jeden název všude“ říká, že jméno aplikace se v repu píše jednou.
    private let main = AppInstallation(
        name: MainWindow.title,
        path: "/Applications/\(MainWindow.title).app"
    )
    private let slot = AppInstallation(name: "PRism-d", path: "/Applications/PRism-d.app")

    private func summary(author: String = "kolega", _ identifier: String) -> PullRequestSummary {
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

    private func run(for pr: PRIdentifier) -> ReviewRun {
        var summary = StreamSummary()
        summary.sessionID = "session-1"
        summary.calledReportFindings = true
        summary.findings = [makeReported()]
        return ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "aaaa1111", skillID: "code-review"),
            summary: summary,
            outcome: .finished
        )
    }

    /// Store po jednom tiku, s dlaždicí. Login se bere **z konfigurace** (`ownLogins`), ne z `gh`
    /// — nezávisí to pak na tom, kolikátý dotaz fake gateway zrovna vydává.
    private func loaded(
        _ list: [PullRequestSummary],
        badge: DockBadgeMode = .waiting,
        reviews: ReviewStore? = nil,
        gateway: FakeGitHubGateway? = nil,
        dock: FakeDockTile
    ) async -> AppStore {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.sources = [.reviewRequested]
        configuration.global.dockBadge = badge
        let store = AppStore(
            gateway: gateway ?? FakeGitHubGateway(always: .success(list)),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            reviews: reviews,
            dock: dock,
            installation: main
        )
        await store.keepFresh()
        return store
    }

    // MARK: - Odznak v Docku

    /// **Odznak je rail v Docku**, tedy tatáž hodnota, jakou má odznak fronty — proto se tvrdí
    /// obojí naráz. Dvě čísla by se rozešla a nikdo by si toho nevšiml: v Docku a v railu se
    /// nikdo nekouká naráz.
    @Test("Odznak nese totéž číslo jako odznak fronty v railu")
    func drawsTheSameNumberAsTheRail() async {
        let dock = FakeDockTile()
        let store = await loaded(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            dock: dock
        )

        #expect(store.railQueueCount == 2)
        _ = await waitUntil("odznak se nasadil") { dock.applied.last == "2" }
        #expect(store.dockBadgeLabel == "2")
    }

    /// **Vlastní PR se do odznaku nepočítají** (#332): odznak fronty znamená „tolik lidí čeká na
    /// moje review“, a vlastní PR má v railu svůj.
    @Test("Vlastní PR odznak nezvedne")
    func keepsOwnPullRequestsOutOfTheBadge() async {
        let dock = FakeDockTile()
        _ = await loaded(
            [summary(author: "ondrajodas", "cli/cli#1"), summary("cli/cli#2")],
            dock: dock
        )

        _ = await waitUntil("odznak se nasadil") { dock.applied.last == "1" }
    }

    /// **Nejcennější tvrzení téhle části**: dokud tik neprošel, na dlaždici nic není. Nula ani
    /// číslo nad nenačtenou frontou by v Docku vypadaly jako hotovo — a to je ten nebezpečný směr.
    @Test("Před prvním úspěšným tikem se odznak nenasadí")
    func drawsNothingBeforeTheFirstTick() async {
        let dock = FakeDockTile()
        let store = await loaded(
            [summary("cli/cli#1")],
            gateway: FakeGitHubGateway(always: .failure(SystemTestError())),
            dock: dock
        )

        #expect(store.lastSuccess == nil)
        #expect(store.dockBadgeLabel == nil)
        // Nasadilo se prázdno, a nic jiného — `nil` je odpověď, ne „nesáhlo se“.
        #expect(dock.applied.allSatisfy { $0 == nil })
    }

    /// Prázdná fronta je **dobrá zpráva, ne položka k vyřízení** — a rail to dělá stejně.
    @Test("Prázdná fronta odznak nenakreslí")
    func drawsNothingOverAnEmptyQueue() async {
        let dock = FakeDockTile()
        let store = await loaded([], dock: dock)

        #expect(store.railQueueCount == 0)
        #expect(store.dockBadgeLabel == nil)
        #expect(dock.applied.allSatisfy { $0 == nil })
    }

    /// Volba `blokující` počítá **z těch samých PR**, takže nikdy nevyjde víc než `čekající`.
    @Test("Blokující kreslí jen PR s blokujícím nálezem")
    func drawsOnlyTheBlockingSubset() async throws {
        let blocked = summary("cli/cli#1")
        let clean = summary("cli/cli#2")
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        try await reviews.save(run(for: blocked.id))
        let dock = FakeDockTile()

        let store = await loaded([blocked, clean], badge: .blocking, reviews: reviews, dock: dock)

        #expect(store.railQueueCount == 2)
        _ = await waitUntil("odznak se nasadil") { dock.applied.last == "1" }
        #expect(store.dockBadgeLabel == "1")
    }

    /// Vypnuto znamená **prázdná dlaždice**, ne nula — a nesmí se na ni dostat ani plná fronta.
    @Test("Volba nic nenakreslí nic ani nad plnou frontou")
    func drawsNothingWhenTurnedOff() async {
        let dock = FakeDockTile()
        let store = await loaded(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            badge: .off,
            dock: dock
        )

        #expect(store.railQueueCount == 2)
        #expect(store.dockBadgeLabel == nil)
        #expect(dock.applied.allSatisfy { $0 == nil })
    }

    /// **Filtr platí i na odznak**, protože je to tatáž množina jako v railu (`visibleQueue…`).
    /// Kdyby odznak četl nefiltrovanou frontu, ukazoval by víc, než je v seznamu vidět — a to je
    /// zrovna ten rozdíl, kvůli kterému `blokující` nesmí brát ze souhrnu fronty.
    @Test("Co schová filtr, schová i odznak")
    func followsTheFilter() async {
        let dock = FakeDockTile()
        let store = await loaded(
            [summary("cli/cli#1"), summary("keboola/vault#2")],
            dock: dock
        )
        _ = await waitUntil("odznak se nasadil") { dock.applied.last == "2" }

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/cli")!]))

        _ = await waitUntil("odznak se zúžil") { dock.applied.last == "1" }
        #expect(store.railQueueCount == 1)
    }

    /// Store **bez** dlaždice na ni nesmí sáhnout — tak ho staví většina testů. Odznak je globální
    /// stav procesu, takže by z jednoho testu přetekl do všech ostatních a zůstal v Docku
    /// hostitele i po běhu.
    @Test("Bez cíle se odznak jen spočítá")
    func computesTheBadgeWithoutATarget() async {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.sources = [.reviewRequested]
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary("cli/cli#1")])),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            installation: main
        )

        await store.keepFresh()

        // Spočítat se dá, jen ji nemá kdo nasadit.
        #expect(store.dockBadgeLabel == "1")
    }

    // MARK: - Spuštění po přihlášení

    private func store(
        installation: AppInstallation,
        loginItems: FakeLoginItem?
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource(),
            loginItems: loginItems,
            installation: installation
        )
    }

    /// **Tvrzení, které se rozbije potichu**: ze slotové instance se do systému nesáhne. Zapsanou
    /// položku `bin/slot-cleanup.sh` neumí sundat, protože není v `config.json`, ale v systému —
    /// a bundle, na který ukazuje, zmizí s worktree.
    @Test("Slotová instance do systému nezapíše")
    func neverWritesFromASlotInstance() {
        let service = FakeLoginItem()
        let store = store(installation: slot, loginItems: service)

        store.setLoginItem(true)
        store.setLoginItem(false)

        #expect(service.registered == 0)
        #expect(service.unregistered == 0)
        #expect(!store.loginItem.isEnabled)
        #expect(store.loginItemFailure == nil)
    }

    /// A totéž bez cíle: store, jak ho staví testy, nemá čím do systému zapsat — a nesmí se u toho
    /// tvářit, že se něco povedlo.
    @Test("Bez cíle se do systému nezapisuje")
    func writesNothingWithoutAService() {
        let store = store(installation: main, loginItems: nil)

        store.setLoginItem(true)
        store.refreshLoginItem()

        #expect(store.loginItemStatus == .notRegistered)
        #expect(store.loginItemFailure == nil)
        #expect(!store.loginItem.isOn)
    }

    @Test("Zapnutí položku zapíše a přepínač zůstane zapnutý")
    func registersTheLoginItem() {
        let service = FakeLoginItem()
        let store = store(installation: main, loginItems: service)

        store.setLoginItem(true)

        #expect(service.registered == 1)
        #expect(store.loginItemStatus == .enabled)
        #expect(store.loginItem.isOn)
        #expect(store.loginItemFailure == nil)
    }

    @Test("Vypnutí položku odebere")
    func unregistersTheLoginItem() {
        let service = FakeLoginItem(status: .enabled)
        let store = store(installation: main, loginItems: service)

        store.setLoginItem(false)

        #expect(service.unregistered == 1)
        #expect(store.loginItemStatus == .notRegistered)
        #expect(!store.loginItem.isOn)
    }

    /// **Přepínač se po selhání nesmí tiše vrátit** (poznámka 181 v návrhu): tichý návrat do
    /// vypnuté polohy vypadá, jako by kliknutí nedošlo. A hláška ze systému zůstává, jak přišla —
    /// je to jediné, podle čeho se dá zjistit, co vadilo.
    @Test("Selhání zápisu je vidět a přepínač se nevrátí")
    func surfacesAFailedWrite() {
        let service = FakeLoginItem()
        service.failure = FakeLoginItemError()
        let store = store(installation: main, loginItems: service)

        store.setLoginItem(true)

        #expect(service.registered == 1)
        #expect(store.loginItemStatus == .notRegistered)
        #expect(store.loginItem.isOn)
        #expect(store.loginItem.note.contains("Systém to odmítl."))
    }

    /// Povedený zápis, po kterém systém **chce schválení**, se nesmí tvářit jako hotový: přepínač
    /// jde do vypnuté polohy, ale s větou a s dalším krokem. Není to selhání, takže se nehlásí
    /// jako chyba.
    @Test("Zápis, po kterém systém chce schválení, nabídne odskok")
    func reportsAnApprovalAfterASuccessfulWrite() {
        let service = FakeLoginItem()
        service.statusAfterRegister = .requiresApproval
        let store = store(installation: main, loginItems: service)

        store.setLoginItem(true)

        #expect(service.registered == 1)
        #expect(store.loginItemFailure == nil)
        #expect(!store.loginItem.isOn)
        #expect(store.loginItem.offersSystemSettings)
    }

    /// **Stav se čte zpátky ze systému, ne z `config.json`**: kdo si položku vypne v Nastavení
    /// systému, má to vidět v okně. A do konfigurace se u toho nesmí nic zapsat — jinak by v okně
    /// ležela druhá kopie systémového stavu.
    @Test("Vypnutí zvenčí je po obnovení vidět a do konfigurace nic nejde")
    func readsTheStatusBackFromTheSystem() {
        let service = FakeLoginItem(status: .enabled)
        let store = store(installation: main, loginItems: service)
        store.refreshLoginItem()
        #expect(store.loginItem.isOn)

        // Někdo ji vypnul v Nastavení systému.
        service.status = .notRegistered
        store.refreshLoginItem()

        #expect(!store.loginItem.isOn)
        // `Configuration` o přihlašovací položce nic neví, a je to celý smysl rozhodnutí:
        // druhá kopie by po ručním vypnutí ukazovala opak toho, co platí.
        #expect(store.configuration == Configuration.standard)
    }

    /// Věta o selhání **zmizí sama**, jak jí stav systému přestane odporovat — jinak by nad
    /// položkou, která se napodruhé zapsat povedla, zůstala viset stará chyba.
    @Test("Povedený druhý pokus starou chybu odklidí")
    func clearsTheFailureOnceItHolds() {
        let service = FakeLoginItem()
        service.failure = FakeLoginItemError()
        let store = store(installation: main, loginItems: service)
        store.setLoginItem(true)
        #expect(store.loginItem.note.contains("Systém to odmítl."))

        service.failure = nil
        store.setLoginItem(true)

        #expect(service.registered == 2)
        #expect(store.loginItem.isOn)
        #expect(!store.loginItem.note.contains("Systém to odmítl."))
    }
}
