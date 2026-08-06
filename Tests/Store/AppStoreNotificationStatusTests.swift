import Foundation
import Testing

@testable import PRism

/// Kdy se naposledy něco ohlásilo (#138).
///
/// To hlavní není, že se čas zapíše, ale že se **nezapíše po nedoručené notifikaci**: jinak by
/// stavový řádek tvrdil, že notifikace fungují, zrovna když nefungují.
@Suite("AppStore — poslední ohlášení")
@MainActor
struct AppStoreNotificationStatusTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func notification() -> PullRequestNotification {
        PullRequestNotification(
            pullRequest: PRIdentifier("cli/cli#1")!,
            title: "Nový PR k review — cli/cli#1",
            body: "Opravit součet",
            event: .newPullRequest
        )
    }

    private func store(
        _ center: FakeNotificationCenter,
        notifications settings: NotificationSettings = NotificationSettings()
    ) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.notifications = settings
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(start: now),
            notifications: center
        )
    }

    @Test("Před prvním doručením není co ukázat")
    func nothingBeforeTheFirstDelivery() {
        #expect(store(FakeNotificationCenter()).lastDeliveredNotification == nil)
    }

    @Test("Doručená notifikace zapíše čas i titulek")
    func recordsTimeAndTitle() async {
        let store = store(FakeNotificationCenter())

        await store.notify(notification())

        #expect(store.lastDeliveredNotification?.at == now)
        // Titulek je to, z čeho nápověda řekne, čeho se ohlášení týkalo.
        #expect(store.lastDeliveredNotification?.title == "Nový PR k review — cli/cli#1")
    }

    /// Nejdůležitější test celého issue.
    @Test("Odmítnuté oprávnění čas neposune")
    func deniedPermissionDoesNotRecordAnything() async {
        let store = store(FakeNotificationCenter(outcome: .notAuthorized))

        await store.notify(notification())

        #expect(store.lastDeliveredNotification == nil)
        // A že nechodí, se pozná z hlášky — ta je od #88 a tohle ji nenahrazuje.
        #expect(store.notificationFailure != nil)
    }

    @Test("Selhání systému čas neposune")
    func aFailedDeliveryDoesNotRecordAnything() async {
        let store = store(FakeNotificationCenter(outcome: .failed("centrum neodpovědělo")))

        await store.notify(notification())

        #expect(store.lastDeliveredNotification == nil)
    }

    @Test("Vypnutá notifikace čas neposune")
    func aDisabledEventDoesNotRecordAnything() async {
        // Vrací se před `deliver(_:)`, takže se nic nedoručilo — a co se nedoručilo, se
        // neohlásilo.
        let center = FakeNotificationCenter()
        let store = store(center, notifications: NotificationSettings(isEnabled: false))

        await store.notify(notification())

        #expect(center.delivered.isEmpty)
        #expect(store.lastDeliveredNotification == nil)
    }

    @Test("Neúspěch po úspěchu čas nesmaže")
    func aLaterFailureKeepsTheLastSuccess() async {
        // Řádek odpovídá na „kdy naposledy něco odešlo“, ne na „jak dopadl poslední pokus“ —
        // to říká hláška o nedoručení vedle.
        let center = FakeNotificationCenter()
        let store = store(center)
        await store.notify(notification())

        center.answer(with: .failed("centrum neodpovědělo"))
        await store.notify(notification())

        #expect(store.lastDeliveredNotification?.at == now)
    }
}
