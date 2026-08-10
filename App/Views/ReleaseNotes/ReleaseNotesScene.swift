import SwiftUI

/// Okno s novinkami (#127) — samostatná scéna vedle hlavního okna a nastavení.
///
/// Jedno okno, ne dvě: „co je nového“ i „historie verzí“ jsou tatáž data, takže dvě obrazovky
/// nad nimi by se dřív nebo později rozešly. Po aktualizaci se otevře samo s vybranou
/// nejnovější verzí, jinak se v něm vybírá ručně.
enum ReleaseNotesWindow {
    static let id = "release-notes"
    static let title = "Novinky v PRism"
}

/// Obsah scény.
///
/// Existuje kvůli témuž rozhodnutí jako `SettingsScene`: dokud neprošel preflight, není `gh`
/// a novinky se nemají čím stáhnout. Okno se přitom otevřít dá — položka v menu funguje
/// i nad blokující obrazovkou — takže ten stav musí něco vysvětlit.
struct ReleaseNotesScene: View {
    let preflight: PreflightModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            // Střed **hlavního okna**, ne obrazovky (#164). Okno se otevírá z jeho toolbaru,
            // z menu a po aktualizaci — tedy vždycky od něj, takže tam se člověk v tu chvíli
            // kouká. Mechanismus je tentýž, jakým se od začátku středí nastavení.
            .centeredInMainWindow()
            // **A zůstane před hlavním oknem, dokud je otevřené** (#243) — tou samou dvojicí jako
            // nastavení, viz `AuxiliaryWindowLevel`. Bez toho se okno vystředěné v hlavním okně
            // schová za ním celé a vypadá to, že se zavřelo.
            .keptInFrontOfApp()
            // **Esc okno zavře.** Je to okno na čtení — nic se v něm nerozepisuje a nic se
            // z něj neodesílá, takže tu není co ztratit; jinak je na to jediná cesta ⌘W.
            // Od #151 to má i nastavení, kde se rozepsaná hodnota doručí (`flush`) při zavření;
            // hlavní okno ne, v tom se pracuje.
            //
            // Jde to **schovaným tlačítkem**, ne `onExitCommand` — proč, je u `hiddenShortcuts`.
            .hiddenShortcuts {
                Button("Zavřít okno") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
    }

    @ViewBuilder private var content: some View {
        if let model = preflight.releaseNotes {
            ReleaseNotesView(model: model)
        } else {
            EmptyStateView(
                nature: .waiting,
                symbol: "sparkles",
                title: "Novinky zatím nejsou k dispozici",
                message: "Stahují se přes gh, takže se ukážou, až projde kontrola prostředí."
            )
            .frame(width: 480, height: 260)
        }
    }
}

/// Položka v menu aplikace, kterou se okno otevře kdykoli.
///
/// Vlastní `View` uvnitř `CommandGroup`, ne `@Environment` na `Commands`: tlačítko potřebuje
/// `openWindow`, a ve view se to čte tam, kde se používá.
struct ReleaseNotesMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(ReleaseNotesWindow.title) { openWindow(id: ReleaseNotesWindow.id) }
    }
}
