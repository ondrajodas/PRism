import SwiftUI

/// Obsah scény `Settings` (⌘,).
///
/// Existuje kvůli jedinému rozhodnutí: dokud neprošel preflight, není `AppStore` a není
/// tedy ani co nastavovat. Scéna se přitom otevřít dá — ⌘, funguje i nad blokující
/// obrazovkou — takže ten stav musí něco vysvětlit.
struct SettingsScene: View {
    let preflight: PreflightModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            // **Nastavení zůstává před hlavním oknem, dokud je otevřené** (#243). Hladina je
            // vlastnost okna, ne formuláře, takže se nastavuje tady — platí tím i pro stav bez
            // storu, ve kterém by se okno jinak umělo schovat za hlavní okno stejně jako předtím
            // ten formulář. Co přesně se s hladinou děje, je u `AuxiliaryWindowLevel`.
            .keptInFrontOfApp()
    }

    /// **Esc nastavení zavře** (#151) — a zkratka je v každém stavu **právě jedna**.
    ///
    /// Je to změna proti #127, kde stálo, že to okno Esc schválně nemá, protože je to
    /// `Settings` a bylo by to proti zvyklosti systému. Zvyklost to není: Esc zavírá
    /// i systémové nastavení, a hlavně se sem chodí přepnout jednu věc a jít zpátky k review,
    /// takže cesta ven má být pod rukou.
    ///
    /// **Ve formuláři si ji drží `SettingsView`**, protože tam u ní musí být doručení rozepsané
    /// hodnoty (`SettingsModel.flush`). Tady zbývá jen ten druhý stav, kde žádný formulář není
    /// a není co doručovat — okno, které jde zavřít jinak než ostatní, by se od nich nedalo
    /// odlišit. Dvě zkratky naráz to být nesmí: byly by to dvě registrace téže klávesy a která
    /// vyhraje, není dané.
    @ViewBuilder private var content: some View {
        if let store = preflight.store {
            SettingsView(store: store)
        } else {
            EmptyStateView(
                nature: .waiting,
                symbol: "gearshape",
                title: "Nastavení zatím není k dispozici",
                message: "Otevře se, jakmile projde kontrola prostředí."
            )
            .frame(width: 480, height: 260)
            .hiddenShortcuts {
                Button("Zavřít nastavení") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
