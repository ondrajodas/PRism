import Foundation
import Testing

@testable import PRism

@Suite("Policy – stav review podle checkoutu")
struct ReviewStateFromCheckoutTests {
    @Test("Nic v cache znamená, že se nespouštělo")
    func absentMeansNotStarted() {
        #expect(Policy.reviewState(for: .absent) == .notStarted)
    }

    @Test("Příprava je v řádku vidět jako clone")
    func preparingShowsAsCloning() {
        #expect(Policy.reviewState(for: .preparing) == .cloning)
    }

    @Test("Hotová kopie sama o sobě žádné review neznamená")
    func readyIsStillNotStarted() {
        // `ReviewState` popisuje review, ne checkout — „připraveno“ v něm případ nemá
        // a vymýšlet ho by znamenalo lhát odznakem.
        #expect(Policy.reviewState(for: .ready(URL(filePath: "/tmp/x"))) == .notStarted)
    }

    @Test("Selhání si nese text, ze kterého se pozná co dál")
    func failureCarriesItsDetail() {
        #expect(Policy.reviewState(for: .failed("fatal: nope")) == .checkoutFailed(detail: "fatal: nope"))
    }
}
