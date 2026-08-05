import AppKit
import Foundation
import UserNotifications

/// `UNUserNotificationCenter` za protokolem `UserNotifying`.
///
/// **Jedna instance, a schválně statická.** Delegát je vlastnost systémového singletonu
/// (`UNUserNotificationCenter.current()`), takže druhá instance by první přebila delegáta
/// a kliknutí by tiše přestala chodit. Singleton tady tedy není kompromis kvůli tomu, že se
/// objekt nemá kudy protáhnout — je to obraz toho, že systémové centrum je jedno.
/// V testech se nepoužije: `AppStore` dostane fake parametrem a na `shared` nesáhne (v
/// testovacím hostu by `current()` navíc spadl na chybějícím bundle identifikátoru).
final class SystemNotificationCenter: UserNotifying {
    static let shared = SystemNotificationCenter()

    /// Delegáta drží `let`, protože systém si ho drží jen `weak` — kdyby zanikl, kliknutí
    /// by přestala chodit a nebylo by na čem to poznat.
    private let forwarder: NotificationClickForwarder
    private let stream: AsyncStream<PRIdentifier>

    private init() {
        let (stream, continuation) = AsyncStream<PRIdentifier>.makeStream()
        self.stream = stream
        forwarder = NotificationClickForwarder(clicks: continuation)
        // Nastavit se to musí **teď**, ne až u první notifikace: když aplikaci spustilo
        // právě kliknutí na notifikaci, systém ho doručí hned po startu — tedy dřív, než se
        // o oprávnění vůbec požádá. Proud si ho podrží, dokud si ho `AppStore` nevyzvedne.
        UNUserNotificationCenter.current().delegate = forwarder
    }

    /// Sáhne na `shared`, aby delegát existoval. Volá `AppDelegate` při startu.
    ///
    /// `static let` je lazy, takže bez tohohle by delegát vznikl teprve se složením store —
    /// a to je po preflightu, tedy klidně o sekundy později.
    static func prepare() {
        _ = shared
    }

    func deliver(_ notification: PullRequestNotification) async -> NotificationDelivery {
        let center = UNUserNotificationCenter.current()
        do {
            // Idempotentní: po prvním rozhodnutí systém dialog neukáže a jen vrátí stav,
            // takže si tady nemusíme pamatovat, že jsme se už ptali.
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                return .notAuthorized
            }
            try await center.add(request(for: notification))
            return .delivered
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func clicks() -> AsyncStream<PRIdentifier> {
        stream
    }

    private func request(for notification: PullRequestNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        // Zvuk schválně: smysl notifikace je dozvědět se to, i když se do aplikace nikdo
        // nedívá, a tichý banner se přehlédne. Vypnout se to dá v #86, seskupit v #87.
        content.sound = .default
        content.userInfo = [Self.pullRequestKey: notification.pullRequest.description]
        // Vlákno (#87): systém podle něj notifikace řadí k sobě, takže se v centru neroztrhají
        // mezi cizí hlášky. Skládá ho model, ne tahle vrstva — je to rozhodnutí o tom, co patří
        // k čemu, ne o tom, jak se to doručí.
        content.threadIdentifier = notification.threadIdentifier
        return UNNotificationRequest(
            // Stejná identita **nahradí** to, co ještě visí — druhý výsledek review nad tímtéž
            // PR je oprava toho prvního, ne druhá informace. Do #87 tu bylo náhodné `UUID`,
            // protože slévání ještě nebylo rozhodnuté.
            identifier: notification.identifier,
            content: content,
            // `nil` = doručit hned, ne za čas.
            trigger: nil
        )
    }

    static let pullRequestKey = "pullRequest"
}

/// Delegát systémového centra: převede kliknutí na hodnotu v proudu.
///
/// Vlastní typ, ne rozšíření `SystemNotificationCenter`u: delegát musí být `NSObject`,
/// kdežto centrum je obyčejná třída za protokolem.
private final class NotificationClickForwarder: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    /// `@unchecked` obstojí: jediný stav je tahle continuation a ta je sama `Sendable`.
    private let clicks: AsyncStream<PRIdentifier>.Continuation

    init(clicks: AsyncStream<PRIdentifier>.Continuation) {
        self.clicks = clicks
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Okno dopředu obstarává **tahle vrstva**, ne store: aktivace aplikace je přístup
        // ke stroji stejně jako doručení notifikace, takže store zůstane bez AppKitu a
        // v testech se nic neaktivuje. Dopředu se jde i tehdy, když identifikátoru
        // nerozumíme — kliknutí je pokyn otevřít aplikaci, ať už se v ní pak vybere cokoli.
        await MainActor.run { NSApplication.shared.activate() }
        let raw = response.notification.request.content.userInfo[SystemNotificationCenter.pullRequestKey]
        guard let text = raw as? String, let id = PRIdentifier(text) else { return }
        clicks.yield(id)
    }

    /// Doručovat i s aplikací vepředu.
    ///
    /// Bez tohohle macOS notifikaci potlačí, jakmile je aplikace aktivní — jenže review trvá
    /// minuty a mezitím se v okně dělá něco jiného (čte se jiný PR, píše se draft). Že je
    /// okno vidět, tedy neznamená, že se člověk dívá zrovna na to, co doběhlo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
