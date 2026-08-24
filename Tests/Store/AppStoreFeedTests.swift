import Foundation
import Testing

@testable import PRism

/// Dění ze strany store (#414) — kdo se do něj zapisuje, kdy se posouvá značka návštěvy a co se
/// **nestane**.
///
/// Tři tvrzení o tom, co se nemá stát, jsou tady ta cenná část: **vypnuté notifikace zápis
/// nezastaví**, **značka se neposune vstupem** do sekce a **vlastní PR se do dění nedostane**.
/// Všechny tři se rozbijí potichu — na obrazovce po nich zůstane prázdno nebo přečtený záznam.
@Suite("AppStore — dění (#414)")
@MainActor
struct AppStoreFeedTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let start = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func configuration(notifications: Bool = true) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.notifications.isEnabled = notifications
        return configuration
    }

    private func summary(_ text: String, author: String = "odinuv") -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "chore: modernize dependencies",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: start,
            state: .open
        )
    }

    private func store(
        _ gateway: FakeGitHubGateway,
        center: FakeNotificationCenter? = nil,
        notifications enabled: Bool = true,
        preferences: InMemoryPreferences = InMemoryPreferences(),
        time: FakeTimeSource? = nil
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration(notifications: enabled),
            time: time ?? FakeTimeSource(start: start),
            notifications: center,
            announced: AnnouncedPullRequests(layout: layout),
            activityLog: ActivityLog(layout: layout),
            activityVisits: ActivityVisitLedger(preferences: preferences)
        )
    }
}

// MARK: - Zápis nezávisí na přepínačích

extension AppStoreFeedTests {
    /// **Kvůli tomuhle ta obrazovka je.** Přepínače (#86) rozhodují o **vyrušení**, ne o záznamu —
    /// takže se dění plní i tehdy, když je aplikace jinak úplně mlčící. Kdyby ho vypnutý přepínač
    /// zastavil, byla by sekce prázdná zrovna ve stavu, ve kterém je nejvíc potřeba.
    @Test("Vypnuté notifikace zápis do dění nezastaví")
    func recordsEvenWithNotificationsOff() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let store = store(gateway, center: center, notifications: false)

        await store.refresh()
        await store.refresh()

        // Banner nedorazil — brána ho zastavila dřív, než se o oprávnění vůbec řeklo.
        #expect(center.delivered.isEmpty)
        // Řádek přesto je, a přiznává, že banner nepřišel.
        #expect(store.activityEvents.map(\.kind) == [.newPullRequest])
        #expect(store.activityEvents.first?.pullRequest == PRIdentifier("cli/cli#2"))
        #expect(store.activityEvents.first?.wasAnnounced == false)
        #expect(Policy.showsSilentChip(.newPullRequest, announced: false))
    }

    /// Doručený banner chip nedostane — o tom, že nepřišel, není co říct.
    @Test("Doručený banner nechá řádek bez chipu")
    func marksADeliveredBanner() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()

        #expect(center.delivered.count == 1)
        #expect(store.activityEvents.first?.wasAnnounced == true)
    }

    /// Záznam se **nezahodí restartem** — tohle je ten rozdíl proti zvonku ve stavovém řádku,
    /// který je v paměti schválně (#138).
    @Test("Záznam přežije restart aplikace")
    func survivesARestart() async {
        let center = FakeNotificationCenter()
        let first = store(
            FakeGitHubGateway([
                .success([summary("cli/cli#1")]),
                .success([summary("cli/cli#1"), summary("cli/cli#2")]),
            ]),
            center: center
        )
        await first.refresh()
        await first.refresh()

        // Druhá instance nad tímtéž souborem — to je to, co se děje při dalším spuštění.
        let second = store(FakeGitHubGateway(always: .success([])), center: center)
        await second.loadStoredActivity()

        #expect(second.activityEvents.map(\.kind) == [.newPullRequest])
    }

    /// Odchod z fronty banner nedostane a nemá ho dostat: vyrušovat nemá, dohledat se má. Je to
    /// **doplněk nad tímtéž snímkem**, takže žádné volání navíc.
    @Test("PR, který odešel z fronty, dostane řádek a žádný banner")
    func recordsADeparture() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
            .success([summary("cli/cli#1")]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()

        #expect(center.delivered.isEmpty)
        #expect(store.activityEvents.map(\.kind) == [.leftQueue])
        #expect(store.activityEvents.first?.pullRequest == PRIdentifier("cli/cli#2"))
        // Chip `bez banneru` se u dopočítaného druhu nekreslí — banner za něj nechodí nikdy.
        #expect(!Policy.showsSilentChip(.leftQueue, announced: false))
    }

    /// **První tik nic nezapíše.** Snímek fronty ještě nikdy neexistoval, takže „všechno je nové“
    /// by byla lavina — a v dění by z toho byla stránka řádků o PR, které tam leží týden.
    @Test("První tik po startu dění neplní")
    func staysQuietOnTheFirstTick() async {
        let center = FakeNotificationCenter()
        let store = store(
            FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")])),
            center: center
        )

        await store.refresh()

        #expect(store.activityEvents.isEmpty)
    }

    /// **Jen cizí PR** (#332), a z dění se to nesmí obejít: „Nový PR k review“ o pull requestu,
    /// který jsem sám otevřel, je hláška o vlastním pushi.
    @Test("Vlastní PR se do dění nedostane")
    func skipsOwnPullRequests() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1", author: "ondrajodas")]),
            .success([
                summary("cli/cli#1", author: "ondrajodas"),
                summary("cli/cli#2", author: "ondrajodas"),
            ]),
        ])
        let store = store(gateway, center: center)

        await store.refresh()
        await store.refresh()

        #expect(center.delivered.isEmpty)
        #expect(store.activityEvents.isEmpty)
    }

    /// Bez záznamu i bez centra se snímek fronty **nespotřebuje**: jinak by po zapnutí notifikací
    /// vypadala první nová PR jako už ohlášená.
    @Test("Bez konzumenta se snímek fronty nezakládá")
    func keepsTheSnapshotUntouchedWithoutAConsumer() async {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary("cli/cli#1")])),
            configuration: configuration(),
            time: FakeTimeSource(start: start),
            announced: AnnouncedPullRequests(layout: layout)
        )

        await store.refresh()

        #expect(!FileManager.default.fileExists(atPath: layout.announcedFile.path))
    }
}

// MARK: - Značka poslední návštěvy

extension AppStoreFeedTests {
    private func stored(_ preferences: InMemoryPreferences) -> AppStore {
        store(FakeGitHubGateway(always: .success([])), preferences: preferences)
    }

    /// **Nejcennější tvrzení sady.** Kdyby značku přepsal vstup, přestalo by být nové zrovna to,
    /// na co koukám — je to tatáž nesymetrie jako u `seedVisitBaseline(for:)` (#335).
    @Test("Vstup do sekce značku neposune")
    func doesNotMoveTheMarkOnEntry() async {
        let preferences = InMemoryPreferences()
        let store = stored(preferences)
        await store.loadStoredActivity()

        store.show(.activity)

        #expect(store.activityVisitSnapshot == nil)
        #expect(ActivityVisitLedger(preferences: preferences).lastVisit() == nil)
    }

    @Test("Odchod ze sekce značku posune a zapíše")
    func movesTheMarkOnDeparture() async {
        let preferences = InMemoryPreferences()
        let time = FakeTimeSource(start: start)
        let store = store(
            FakeGitHubGateway(always: .success([])),
            preferences: preferences,
            time: time
        )
        await store.loadStoredActivity()

        store.show(.activity)
        store.show(.queue)

        #expect(store.activityVisitSnapshot == start)
        #expect(ActivityVisitLedger(preferences: preferences).lastVisit() == start)
    }

    /// Klik na řádek jde **jediným vstupním bodem** (#409) a **jmenuje tab**: řádek dění ví, o čem
    /// je, takže poslat člověka „tam, kde skončil“ by ho poslalo jinam, než na co klikl.
    @Test("Klik na řádek otevře záložku i cílový tab")
    func opensTheTargetTab() async {
        let store = store(FakeGitHubGateway(always: .success([summary("cli/cli#1")])))
        await store.refresh()
        let pr = PRIdentifier("cli/cli#1")!
        let event = Policy.staleFindingsActivity(
            for: pr,
            head: "9c1f0ab",
            commits: 2,
            headAt: nil,
            noticedAt: start
        )!

        store.show(event)

        #expect(store.activeTab == .pullRequest(pr))
        #expect(store.detailTab(for: pr) == .commits)
    }

    /// Řádek, který **do okna nevede** (PR z fronty odešel), tímhle vstupním bodem jít nemá —
    /// otevřel by záložku nad PR, které v seznamu není. Odkaz ven kreslí view.
    @Test("Řádek o odchodu z fronty záložku neotevře")
    func opensNoTabForADeparture() async {
        let store = store(FakeGitHubGateway(always: .success([])))
        let pr = PRIdentifier("cli/cli#9")!
        let event = Policy.departureActivity(for: pr, at: start)!

        store.show(event)

        #expect(store.activeTab == .home)
        #expect(store.openTabs.isEmpty)
    }

    /// Přepnutí na záložku PR je taky odchod: sekce railu je obsah **domácí** záložky, takže nad
    /// otevřeným PR vidět není.
    @Test("Otevření záložky PR je odchod ze sekce")
    func countsOpeningATabAsALeave() async {
        let preferences = InMemoryPreferences()
        let store = store(
            FakeGitHubGateway(always: .success([summary("cli/cli#1")])),
            preferences: preferences
        )
        await store.loadStoredActivity()

        store.show(.activity)
        store.openTab(PRIdentifier("cli/cli#1")!)

        #expect(store.activityVisitSnapshot == start)
    }

    /// Přepnutí uvnitř sekce (rail → tatáž sekce) značku nehýbe — jinak by ji spotřeboval každý
    /// klik na tutéž ikonu.
    @Test("Klik na tutéž sekci značku nehýbe")
    func staysPutWithinTheSection() async {
        let store = stored(InMemoryPreferences())
        await store.loadStoredActivity()

        store.show(.activity)
        store.show(.activity)

        #expect(store.activityVisitSnapshot == nil)
    }

    /// Snapshot se čte **jednou při startu**, takže se posunutá značka na disku neprojeví na tom,
    /// co je v tomhle běhu nad pruhem.
    @Test("Značka z předchozího spuštění se přečte při startu")
    func readsTheStoredMark() async {
        let preferences = InMemoryPreferences()
        ActivityVisitLedger(preferences: preferences).record(start.addingTimeInterval(-600))
        let store = stored(preferences)

        await store.loadStoredActivity()

        #expect(store.activityVisitSnapshot == start.addingTimeInterval(-600))
    }
}

// MARK: - Odznak a prázdný stav

extension AppStoreFeedTests {
    /// Odznak **počítá nepřečtené** a na aktivní sekci se nekreslí (v tomhle railu by překryl
    /// ikonu, poznámka 95 v návrhu).
    @Test("Odznak počítá nepřečtené a na aktivní sekci mlčí")
    func countsUnreadInTheBadge() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let store = store(gateway, center: center)
        await store.loadStoredActivity()

        await store.refresh()
        await store.refresh()

        #expect(store.railActivityCount == 1)
        store.show(.activity)
        #expect(store.railActivityCount == nil)
    }

    @Test("Prázdný záznam dá prázdný stav, plný ne")
    func picksTheEmptyState() async {
        let center = FakeNotificationCenter()
        let store = store(
            FakeGitHubGateway([
                .success([summary("cli/cli#1")]),
                .success([summary("cli/cli#1"), summary("cli/cli#2")]),
            ]),
            center: center
        )

        #expect(store.activityEmptyState == .calm)
        await store.refresh()
        await store.refresh()
        #expect(store.activityEmptyState == nil)
    }

    /// Rozbitý soubor a prázdný záznam dají obojí prázdný seznam, takže by nad ztracenou historií
    /// stálo klidné „nic se nestalo“. Store proto ten příznak z `ActivityLog` musí **donést**.
    @Test("Rozbitý soubor se v okně pozná od prázdna")
    func carriesTheUnreadableFlagIntoTheWindow() async throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("{ tohle není záznam".utf8).write(to: layout.activityFile)
        let store = store(FakeGitHubGateway(always: .success([])))

        await store.loadStoredActivity()

        #expect(store.activityEvents.isEmpty)
        #expect(store.activityEmptyState == .unreadable)
    }

    /// Vypnutý přepínač a zakázané oprávnění se nesmí slít: první se spravuje v nastavení
    /// aplikace, druhé v Nastavení systému.
    @Test("Vypnuté notifikace mají vlastní prázdný stav")
    func tellsOffFromDenied() {
        let store = store(FakeGitHubGateway(always: .success([])), notifications: false)

        #expect(store.activityEmptyState == .notificationsOff)
        store.notificationFailure = "Notifikace nemají povolení."
        #expect(store.activityEmptyState == .notificationsDenied)
    }
}
