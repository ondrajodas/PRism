import SwiftUI

/// Obsah scény `Settings` (⌘,).
///
/// Existuje kvůli jedinému rozhodnutí: dokud neprošel preflight, není `AppStore` a není
/// tedy ani co nastavovat. Scéna se přitom otevřít dá — ⌘, funguje i nad blokující
/// obrazovkou — takže ten stav musí něco vysvětlit.
struct SettingsScene: View {
    let preflight: PreflightModel

    var body: some View {
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
        }
    }
}
