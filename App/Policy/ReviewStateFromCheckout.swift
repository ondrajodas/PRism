import Foundation

extension Policy {
    /// Co ukázat v řádku PR, když se ví jen o stavu jeho pracovní kopie.
    ///
    /// Čistá funkce, protože je to rozhodnutí, ne kreslení — a hlavně je to jediné místo,
    /// kde se stav klonu překládá na `ReviewState`. `ready` je schválně `notStarted`:
    /// `ReviewState` popisuje **review**, a to se checkoutem nespustilo. Že je kopie
    /// hotová, patří do detailu.
    static func reviewState(for checkout: CheckoutState) -> ReviewState {
        switch checkout {
        case .absent, .ready: .notStarted
        case .preparing: .cloning
        case .failed(let detail): .checkoutFailed(detail: detail)
        }
    }
}
