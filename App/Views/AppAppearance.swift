import AppKit

/// Kdo umí přepnout vzhled celé aplikace (#278).
///
/// Protokol je tu kvůli testům, ze stejného důvodu jako u `Environment`: živý cíl je `NSApp`,
/// což je v testech **hostitel testů** — vynucený režim by z jednoho testu přetekl do render
/// sond, které si režim nastavují samy, a ty by pak měřily něco jiného, než o co si řekly.
@MainActor
protocol AppearanceApplying: AnyObject {
    func applyAppearance(_ mode: AppearanceMode)
}

/// Vzhled se nastavuje **aplikaci**, ne oknu.
///
/// `NSApp.appearance` platí na všechna okna naráz — hlavní okno, nastavení, novinky, sheety
/// i to okno, které v době přepnutí není vpředu. `.preferredColorScheme` na scéně by znamenalo
/// zapsat totéž u každé scény zvlášť a na tu čtvrtou by se zapomnělo.
///
/// **Přiřazuje se bezpodmínečně, i když se režim nezměnil**, a je to v pořádku: konfigurace se
/// načítá při každém návratu do aplikace, takže tudy chodí i beze změny — `NSAppearance(named:)`
/// ale vrací **tutéž instanci** (změřeno), takže se přiřazuje hodnota, kterou tam AppKit už má.
/// Podmínka „jen když se to změnilo“ by byla druhé místo, kde se rozhoduje o vzhledu, výměnou za
/// nic.
extension NSApplication: AppearanceApplying {
    func applyAppearance(_ mode: AppearanceMode) {
        appearance = mode.nsAppearance
    }
}

/// Živý cíl pro `AppStore`.
///
/// Existuje proto, aby `App/Store/` nemusel importovat AppKit: store o vzhledu rozhoduje
/// (dostal konfiguraci), ale kreslení není jeho práce.
enum AppAppearance {
    @MainActor static var application: any AppearanceApplying { NSApplication.shared }
}

extension AppearanceMode {
    /// Vzhled, který se nastaví aplikaci. **`nil` jedině u `.system`** — tam se nic nevynucuje
    /// a rozhoduje systém, což je celé, co `nil` v `NSApp.appearance` znamená.
    ///
    /// U vynuceného režimu se `nil` vrátit **nesmí**: byl by k nerozeznání od „podle systému“,
    /// takže by volba tiše nezabrala. Jméno vzhledu je systémová konstanta, takže selhat nemá
    /// čím — a přesně na to je test, aby to nebyl tichý `?? default`.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }
}
