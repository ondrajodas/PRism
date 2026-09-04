import Foundation
import ServiceManagement

/// Kdo umí zapsat a přečíst přihlašovací položku (#529).
///
/// Za protokolem ze stejného důvodu jako zbytek `Environment`: `register()` **zapisuje do
/// systému**, a to je jediná věc v téhle aplikaci, která po sobě nechá stopu i po smazání
/// bundlu. Test, který by ji zapsal doopravdy, by ji nechal v Nastavení systému toho, kdo
/// suitu pustil — a odregistrovat by ji už neuměl nikdo, protože bundle hostitele testů
/// mezitím zmizí s `build.noindex/`.
@MainActor
protocol LoginItemControlling: AnyObject {
    /// Co o položce říká systém **teď**. Čte se při každém otevření stránky `Systém`, ne jednou:
    /// vypnout ji jde i v Nastavení systému a přepínač, který o tom neví, tvrdí opak.
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Živá implementace nad `SMAppService` — tedy **systémová přihlašovací položka**, ne vlastní
/// launch agent v `~/Library/LaunchAgents`.
///
/// `SMAppService.mainApp` míří na ten bundle, ze kterého se běží, takže se sem nic nepředává.
/// Právě proto o tom, jestli se to vůbec smí, rozhoduje `Policy.loginItemAvailability` **před**
/// zápisem: `mainApp` slotové instance je `PRism-d`, a ta by v systému zůstala i po
/// `bin/slot-cleanup.sh`, který o systémových položkách nic neví.
final class SMAppServiceLoginItem: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        // Neznámý budoucí případ se bere jako „položka v systému není“ — viz `LoginItemStatus`.
        @unknown default: .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Živý cíl pro `AppStore`.
///
/// Existuje ze stejného důvodu jako `AppAppearance` u vzhledu (#278): `App/Store/` pak nemusí na
/// `ServiceManagement` vidět a jméno systémového typu v něm nestojí ani jednou. Store o položce
/// rozhoduje (zná instalaci), ale zápis do systému není jeho práce. Hlídá to
/// `DockBadgeWiringTests`.
enum LoginItemService {
    @MainActor static var live: any LoginItemControlling { SMAppServiceLoginItem() }
}
