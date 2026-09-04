import Foundation

@testable import PRism

/// Dlaždice v Docku, na kterou se dá tvrdit, že se na ni **nesáhlo** (#529).
///
/// Existuje ze stejného důvodu jako `FakeAppearanceTarget` (#278): živý cíl je dlaždice procesu,
/// tedy v testech dlaždice hostitele testů. Odznak z jednoho testu by přetekl do všech ostatních
/// a po skončení běhu zůstal viset v Docku — je to ta pátá podoba téhož kořene, kvůli které
/// vzniklo `GlobalAppearanceTests`.
@MainActor
final class FakeDockTile: DockBadgeApplying {
    /// Co se nasazovalo, v pořadí — **včetně `nil`**, protože prázdná dlaždice je odpověď, ne
    /// „nesáhlo se“. Na tomhle seznamu stojí i tvrzení, že se odznak nenasadil.
    private(set) var applied: [String?] = []

    func applyBadge(_ label: String?) {
        applied.append(label)
    }
}

/// Přihlašovací položka, která **nikam nezapisuje** (#529).
///
/// Nepovinný cíl ve storu je nepovinný o důvod naléhavěji než dlaždice: zapsanou položku by
/// testovací host neuklidil, protože jeho bundle zmizí s `build.noindex/`, kdežto záznam
/// v systému zůstane. Fake proto počítá pokusy a stav si drží sám.
@MainActor
final class FakeLoginItem: LoginItemControlling {
    /// Co se `status` zeptá. Nastavuje si to test — a `setLoginItem` ho po pokusu přečte, takže
    /// se dá složit i scéna „`register()` prošel, ale systém chce schválení“.
    var status: LoginItemStatus

    /// Kolikrát se zkusilo zapsat a odebrat. **Na těchhle dvou číslech stojí to nejcennější
    /// tvrzení celého issue**: ze slotové instance se do systému nesáhne.
    private(set) var registered = 0
    private(set) var unregistered = 0

    /// Čím `register()` a `unregister()` spadnou. `nil` = projdou.
    var failure: (any Error)?

    /// Na jaký stav se položka přepne po povedeném zápisu. `nil` = nechá se, co je v `status`.
    var statusAfterRegister: LoginItemStatus?

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registered += 1
        if let failure { throw failure }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregistered += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

/// Chyba, kterou `FakeLoginItem` vyhazuje. Vlastní typ, aby se ve větě pod přepínačem poznalo,
/// že tam doopravdy stojí hláška ze systému, a ne obecný text.
struct FakeLoginItemError: LocalizedError {
    let errorDescription: String? = "Systém to odmítl."
}

/// Selhání sítě pro scénu „tik neprošel“. Vlastní typ, aby se nemíchalo s chybou systému výš.
struct SystemTestError: LocalizedError {
    let errorDescription: String? = "Síť nedostupná."
}
