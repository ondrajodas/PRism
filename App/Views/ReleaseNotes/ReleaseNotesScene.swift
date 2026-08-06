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
            // **Esc okno zavře.** Je to okno na čtení — nic se v něm nerozepisuje a nic se
            // z něj neodesílá, takže tu není co ztratit; jinak je na to jediná cesta ⌘W.
            // Hlavní okno ani nastavení to schválně nemají: v prvním se pracuje a druhé je
            // `Settings`, kde by to bylo proti zvyklosti systému.
            //
            // Jde to **schovaným tlačítkem**, ne `onExitCommand`: ten se váže na fokus a Esc
            // spolkne `List` v bočním panelu dřív, než se k němu dostane (zkoušeno na běžící
            // aplikaci — okno bylo `AXFocused` a nezavřelo se). Klávesová zkratka se naproti
            // tomu registruje na celé okno. `opacity(0)` a nulový rámec, ne `hidden()`:
            // schovanému view zkratka nechodí.
            .background {
                Button("Zavřít okno") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder private var content: some View {
        if let model = preflight.releaseNotes {
            ReleaseNotesView(model: model)
        } else {
            ContentUnavailableView(
                "Novinky zatím nejsou k dispozici",
                systemImage: "sparkles",
                description: Text("Stahují se přes gh, takže se ukážou, až projde kontrola prostředí.")
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
