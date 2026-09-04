import AppKit

/// Kdo umí napsat na dlaždici v Docku (#529).
///
/// Protokol je tu ze **stejného důvodu jako `AppearanceApplying`** (#278): živý cíl je `NSApp`,
/// což je v testech hostitel testů. Odznak je globální stav procesu, tedy zrovna ta třída, která
/// v tomhle repu už pětkrát vyrobila falešně červený `main` (#367 vzhled, #411 `UserDefaults`,
/// #462 okno s animací, #490 `CGEvent`, #550 stráže nad surovým textem) — a odznak by k tomu
/// zůstal viset v Docku i po skončení běhu.
@MainActor
protocol DockBadgeApplying: AnyObject {
    /// `nil` = prázdná dlaždice. Zvlášť od prázdného řetězce se to nerozlišuje: `badgeLabel = ""`
    /// nakreslí prázdný červený puntík, kdežto `nil` odznak sundá.
    func applyBadge(_ label: String?)
}

/// Odznak se nastavuje **dlaždici aplikace**, ne oknu — a proto to nemůže dělat view.
///
/// Celý smysl odznaku je, že je vidět, když se do aplikace nikdo nedívá. Ve view by se hodnota
/// uplatnila jedině tehdy, když je okno na obrazovce, tedy právě tehdy, kdy odznak nikdo
/// nepotřebuje.
///
/// **Přiřazuje se bezpodmínečně, i když se hodnota nezměnila**, ze stejného důvodu jako u vzhledu:
/// podmínka „jen když se to změnilo“ by byla druhé místo, kde se o odznaku rozhoduje, výměnou za
/// nic — `dockTile.badgeLabel` je jedno přiřazení řetězce.
extension NSApplication: DockBadgeApplying {
    func applyBadge(_ label: String?) {
        dockTile.badgeLabel = label
    }
}

/// Živý cíl pro `AppStore`.
///
/// Existuje proto, aby `App/Store/` nemusel importovat AppKit: store o odznaku rozhoduje (má
/// frontu i konfiguraci), ale kreslení není jeho práce. Hlídá to `DockBadgeWiringTests`.
enum DockBadgeTile {
    @MainActor static var application: any DockBadgeApplying { NSApplication.shared }
}
