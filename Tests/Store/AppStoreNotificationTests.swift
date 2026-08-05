import Foundation
import Testing

@testable import PRism

/// Základ notifikací (#88) ze strany store: co se doručí, co se o tom řekne v okně a co
/// udělá kliknutí.
///
/// Vrstva bez konzumenta — doručovat začne #82. To hlavní tady proto není text notifikace,
/// ale dvě věci, které se dají pokazit tiše: že se **odmítnuté oprávnění dá poznat** (jinak
/// je „nic mi nepřišlo“ k nerozeznání od „nic se nestalo“) a že se **kliknutí neztratí**,
/// když dorazí dřív, než si ho má kdo vyzvednout.
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

    /// Ohraničené čekání: test, který se nedočká, má spadnout na `#expect`, ne viset.
    /// Neomezený spin přes `Task.yield()` na `MainActoru` položil suitu u #68.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
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

    @Test("Klik na notifikaci vybere její PR")
    func clickSelectsThePullRequest() async {
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        await store.refresh()
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil { store.selection == pr }

        #expect(store.selection == pr)
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
        await waitUntil { store.selection == pr }

        #expect(store.selection == pr)
        watching.cancel()
    }

    @Test("Klik před prvním tikem PR vybere, i když seznam je ještě prázdný")
    func selectsBeforeTheFirstTick() async {
        // Tohle je ten scénář, kvůli kterému má proud buffer: aplikaci spustilo právě kliknutí
        // na notifikaci, takže polling ještě neproběhl. Prázdný seznam tady neznamená „PR je
        // zavřený“, ale „ještě nevím“ — zahodit klik by celý ten scénář rozbilo.
        let center = FakeNotificationCenter()
        let store = store(center, listing: [pr])
        #expect(store.status == .notStarted)
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        await waitUntil { store.selection == pr }

        #expect(store.selection == pr)
        watching.cancel()
    }

    @Test("Klik na PR mimo seznam výběr nemění")
    func clickOnAPullRequestThatIsGoneKeepsTheSelection() async {
        // Notifikace přežije tik, který PR odklidil (mergnul se, zavřel se). Vybrat řádek,
        // který v seznamu není, nejde — a skočit místo toho jinam by bylo horší než nechat na
        // obrazovce to, co tam bylo. Okno je vepředu tak jako tak (dává ho vrstva prostředí).
        let listed = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 7)
        let center = FakeNotificationCenter()
        let store = store(center, listing: [listed])
        await store.refresh()
        store.selection = listed
        let watching = Task { await store.handleNotificationClicks() }

        center.click(pr)
        // Není na co čekat — ověřuje se, že se nic nestane. Krátká odmlka dá klikům šanci
        // projít, kdyby se přece jen zpracovávaly.
        try? await Task.sleep(for: .milliseconds(20))

        #expect(store.selection == listed)
        watching.cancel()
    }
}
