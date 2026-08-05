import Foundation

@testable import PRism

/// Notifikační centrum, které nic nedoručuje — zapíše si, co po něm kdo chtěl, a odpoví,
/// jak si test předepsal.
///
/// Vlastní soubor, ne přírůstek do `EnvironmentFakes`: na tomhle faku stojí #82 a #85,
/// takže se k němu bude vracet víc suit než k jednomu z pomocníků na preflight.
final class FakeNotificationCenter: UserNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [PullRequestNotification] = []
    private var outcome: NotificationDelivery
    private let clicked: AsyncStream<PRIdentifier>
    private let clicks_: AsyncStream<PRIdentifier>.Continuation

    init(outcome: NotificationDelivery = .delivered) {
        self.outcome = outcome
        (clicked, clicks_) = AsyncStream<PRIdentifier>.makeStream()
    }

    /// Co se doručovalo, v pořadí. Na tomhle čísle stojí testy, které tvrdí, že se
    /// **nedoručilo nic** — a to je u notifikací ta cennější polovina.
    var delivered: [PullRequestNotification] { lock.withLock { sent } }

    /// Přepne, jak dopadne další doručení. Aby šlo v jednom testu projít odmítnuté oprávnění
    /// a pak povolené — hláška se totiž má úspěchem smazat.
    func answer(with delivery: NotificationDelivery) {
        lock.withLock { outcome = delivery }
    }

    func deliver(_ notification: PullRequestNotification) async -> NotificationDelivery {
        lock.withLock {
            sent.append(notification)
            return outcome
        }
    }

    func clicks() -> AsyncStream<PRIdentifier> {
        clicked
    }

    /// Simuluje kliknutí na notifikaci daného PR.
    func click(_ pullRequest: PRIdentifier) {
        clicks_.yield(pullRequest)
    }
}
