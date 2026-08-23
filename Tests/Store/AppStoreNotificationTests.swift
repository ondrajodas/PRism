import Foundation
import Testing

@testable import PRism

/// Základ notifikací (#88) ze strany store: co se doručí, co se o tom řekne v okně a co
/// udělá kliknutí.
///
/// To hlavní tady proto není text notifikace, ale tři věci, které se dají pokazit tiše: že se
/// **odmítnuté oprávnění dá poznat** (jinak je „nic mi nepřišlo“ k nerozeznání od „nic se
/// nestalo“), že se **kliknutí neztratí**, když dorazí dřív, než si ho má kdo vyzvednout, a že
/// klik **něco otevře**.
///
/// **Tvrzení o kliku jsou od #409 o `activeTab` a `openTabs`, ne o `selection`** — a je to ta
/// zajímavější polovina toho issue. Do té doby tvrdily čtyři testy `store.selection == pr`, tedy
/// přesně to jediné, co obsluha dělala: zelené byly právem a o tom, co uživatel vidí, neříkaly nic.
/// Otevření záložky obstarává od #180 `openTab(_:in:)`, takže bez něj zůstal `activeTab` na `.home`
/// a z kliknutí bylo „aplikace naskočila a nic“. Ověřeno vloženou regresí (vrátit `selection = pr`
/// místo `openTab(pr)` → padne šest testů ze sedmi v sekci níž; ten sedmý tvrdí, že se **nic
/// nestane**, takže projít má).
@Suite("AppStore — notifikace")
@MainActor
struct AppStoreNotificationTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        _ center: FakeNotificationCenter?,
        listing listed: [PRIdentifier] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success(listed.map(summary))),
            configuration: configuration,
            time: FakeTimeSource(),
            notifications: center
        )
    }

    private func notification(for pullRequest: PRIdentifier) -> PullRequestNotification {
        PullRequestNotification(
            pullRequest: pullRequest,
            title: "Review doběhlo",
            body: "2 nálezy",
            event: .findings
        )
    }



    @Test("Notifikace se doručí tak, jak se o ni řeklo")
    func deliversWhatItWasAskedFor() async {
        let center = FakeNotificationCenter()

        await store(center).notify(notification(for: pr))

        #expect(center.delivered == [notification(for: pr)])
    }

    @Test("Doručená notifikace nic nehlásí")
    func saysNothingWhenItWorked() async {
        let store = store(FakeNotificationCenter())

        await store.notify(notification(for: pr))

        #expect(store.notificationFailure == nil)
    }

    @Test("Bez notifikačního centra se nedoručuje a nic se nehlásí")
    func staysQuietWithoutACenter() async {
        // „Odsud se neposílá“ (testy) není porucha, o které by se mělo hlásit — jinak by
        // každý test s notifikacemi měl v okně větu o tom, že něco nefunguje.
        let store = store(nil)

        await store.notify(notification(for: pr))

        #expect(store.notificationFailure == nil)
    }

    @Test("Odmítnuté oprávnění je vidět a aplikaci nepoloží")
    func reportsRefusedPermission() async {
        let store = store(FakeNotificationCenter(outcome: .notAuthorized))

        await store.notify(notification(for: pr))

        // Věta musí říct, kde se to spraví — aplikace do Nastavení systému nedosáhne, takže
        // samotné „nemám oprávnění“ by nedávalo další krok.
        let failure = store.notificationFailure
        #expect(failure?.contains("Nastavení systému") == true)
    }

    @Test("Selhané doručení nese, co k tomu systém řekl")
    func reportsWhatTheSystemSaid() async {
        let store = store(FakeNotificationCenter(outcome: .failed("centrum neodpovědělo")))

        await store.notify(notification(for: pr))

        #expect(store.notificationFailure?.contains("centrum neodpovědělo") == true)
    }

    @Test("Povolené oprávnění hlášku smaže")
    func clearsTheNoticeOnceItWorks() async {
        // Oprávnění se dá povolit v Nastavení systému a příští doručení projde. Věta, která
        // by po něm zůstala, by posílala hledat vyřešený problém.
        let center = FakeNotificationCenter(outcome: .notAuthorized)
        let store = store(center)
        await store.notify(notification(for: pr))
        #expect(store.notificationFailure != nil)

        center.answer(with: .delivered)
        await store.notify(notification(for: pr))

        #expect(store.notificationFailure == nil)
    }

    // MARK: - Klik otevře záložku (#409)

    @Test("Klik na notifikaci otevře záložku jeho PR")
    func clickOpensATab() async {
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        await store.refresh()
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        // **Tohle je to tvrzení, které u #409 chybělo.** Do té doby obsluha nastavovala jedině
        // `selection`, tedy stav, který od záložek (#180) v domácí záložce nikdo nekreslí — takže
        // testy byly zelené právem a o tom, co uživatel vidí, neříkaly nic.
        #expect(store.activeTab == .pullRequest(pr))
        #expect(store.openTabs == [pr])
        // Výběr zůstává na téhle cestě taky: řádek v seznamu má být zvýrazněný, jako po kliknutí.
        #expect(store.selection == pr)
        watching.cancel()
    }

    /// Volba tabu je odpověď na „kam se v tomhle PR koukám“ a drží se per PR, takže klik na
    /// notifikaci ji **nepřepisuje** — proud kliknutí nese `PRIdentifier`, ne událost, takže by se
    /// tab vybíral naslepo. Jmenovat tab umí ten, kdo ví, o čem klik je (paleta ⌘K, #414).
    @Test("Klik nepřepíše tab, na kterém člověk skončil")
    func clickKeepsTheRememberedTab() async {
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        await store.refresh()
        store.setDetailTab(.conversation, for: pr)
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        #expect(store.detailTab(for: pr) == .conversation)
        watching.cancel()
    }

    @Test("Klik doručený před startem se neztratí")
    func keepsAClickThatArrivedTooEarly() async {
        // Když aplikaci spustilo právě kliknutí na notifikaci, systém ho doručí dřív, než se
        // `AppStore` vůbec složí. Proud si ho proto musí podržet — jinak to kliknutí nikdy
        // nikam nevede a vypadá to jako rozbitá notifikace.
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        await store.refresh()

        center.click(pr)
        let watching = Task { await store.handleNotificationClicks() }
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        #expect(store.openTabs == [pr])
        watching.cancel()
    }

    @Test("Klik před prvním tikem PR otevře, i když seznam je ještě prázdný")
    func opensBeforeTheFirstTick() async {
        // Tohle je ten scénář, kvůli kterému má proud buffer: aplikaci spustilo právě kliknutí
        // na notifikaci, takže polling ještě neproběhl. Prázdný seznam tady neznamená „PR je
        // zavřený“, ale „ještě nevím“ — zahodit klik by celý ten scénář rozbilo. Záložka se
        // dokreslí, jakmile první tik dorazí (do té doby v ní stojí, že PR ze seznamu zmizel).
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        #expect(store.status == .notStarted)
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        #expect(store.openTabs == [pr])
        watching.cancel()
    }

    /// Klik na notifikaci je výslovná žádost tenhle PR vidět, takže filtr (#117) ustoupí — jinak by
    /// PR byl otevřený v okně a v seznamu pod ním by nebyl. Rozhodnutí drží `Policy`, tady se hlídá,
    /// že store filtr doopravdy zruší, a to **tou samou cestou** jako tlačítko filtru.
    @Test("Klik na PR schovaný filtrem filtr zruší")
    func clearsTheFilterThatHidesThePullRequest() async {
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        await store.refresh()
        store.setFilter(PullRequestFilter(repositories: [RepoID("ondrajodas/PRism")!]))
        #expect(store.visiblePullRequests.isEmpty)
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        #expect(store.filter.isActive == false)
        #expect(store.visiblePullRequests.map(\.id) == [pr])
        #expect(store.openTabs == [pr])
        watching.cancel()
    }

    /// Notifikace se o vlastních PR hlásí jedině o **cizí aktivitě** na nich (#335), a klik na
    /// starší notifikaci může přijít i na PR, který se mezitím do sekce `Moje PR` (#331) přesunul.
    /// Záložka je na sekci railu nezávislá — detail si bere z **plného** seznamu —, takže se z toho
    /// nesmí stát zahozený klik ani prázdná záložka.
    @Test("Klik na vlastní PR otevře záložku taky")
    func opensAnOwnPullRequest() async {
        let center = FakeNotificationCenter()
        // „Moje“ je od #330 množina loginů z konfigurace, takže se viewer nemusí dotahovat.
        var mine = configuration
        mine.global.ownLogins = ["autor"]
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary(pr)])),
            configuration: mine,
            time: FakeTimeSource(),
            notifications: center
        )
        await store.refresh()
        #expect(store.visibleOwnPullRequests.map(\.id) == [pr])
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil("klik na notifikaci otevře záložku") { store.activeTab == .pullRequest(pr) }

        #expect(store.openTabs == [pr])
        // Záložka se má nakreslit, ne skončit prázdnem: shrnutí se hledá v plném seznamu.
        #expect(store.summary(for: pr) != nil)
        watching.cancel()
    }

    @Test("Klik na PR mimo seznam neotevře nic")
    func clickOnAPullRequestThatIsGoneOpensNothing() async {
        // Notifikace přežije tik, který PR odklidil (mergnul se, zavřel se). Otevřít záložku
        // naslepo by znamenalo prázdnou plochu s hláškou, že PR zmizel — skočit místo toho jinam
        // je horší než nechat na obrazovce to, co tam bylo. Okno je vepředu tak jako tak (dává ho
        // vrstva prostředí).
        let listed = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7)
        let center = FakeNotificationCenter()
        let store = store(center, listing: [listed])
        await store.refresh()
        store.openTab(listed)
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        // Není na co čekat — ověřuje se, že se nic nestane. Odmlka dá klikům šanci projít,
        // kdyby se přece jen zpracovávaly.
        await settle()

        #expect(store.activeTab == .pullRequest(listed))
        #expect(store.openTabs == [listed])
        watching.cancel()
    }
}
