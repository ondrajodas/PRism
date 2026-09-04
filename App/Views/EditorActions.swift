import SwiftUI

/// Co okno umí s otevřením souboru v editoru (#530).
///
/// **Volitelný parametr, ne příznak `isEnabled`.** `nil` znamená, že se tlačítko **nekreslí** —
/// tak vypadá stav bez zvoleného editoru. Zašedlé tlačítko by slibovalo akci, která se dá zapnout
/// tady, kdežto zapíná se v nastavení; zašedlá akce s důvodem patří jedině tam, kde se stav mění
/// na téže obrazovce (`CLAUDE.md`, tvrdá podmínka č. 1 bod 2).
///
/// Tentýž vzorec jako `DiffReadActions`: popisek a věta jsou **hotový text z `Policy`**, protože
/// jméno editoru i to, ze kterého stromu se otevírá, je rozhodnutí, ne sazba.
/// **`@MainActor`, protože si tenhle typ kreslí tlačítka sám.** `open` je uzávěr nad storem, tedy
/// hodnota, kterou nejde poslat mimo hlavní vlákno — a bez anotace by ji `Button` bral jako
/// task-isolovanou. `DiffReadActions` anotaci nemá, protože kreslí až volající; tady jsou obě
/// podoby tlačítka schválně na jednom místě.
@MainActor
struct EditorActions {
    /// `Otevřít v Cursoru` — `Policy.openInEditorTitle`.
    let title: String
    /// Věta o tom, že se otevírá **kopie z cache**, ne uživatelův klon —
    /// `Policy.editorNote(_:ownership:)`. Kreslí se jako nápověda u tlačítka.
    let note: String
    /// Cesta v diffu a řádek. `nil` u nálezu, který k řádku nepatří — soubor se otevře na začátku.
    let open: (String, Int?) -> Void

    /// Tlačítko v **hlavičce souboru**: jen ikona.
    ///
    /// Hlavička nese cestu, odznaky změny, nálezy, počty i zaškrtávátko `Prošlo` a u padesáti
    /// souborů se ta řádka opakuje padesátkrát — `Otevřít v Cursoru` v ní by se pralo o šířku
    /// s tím, kvůli čemu se hlavička čte. Jméno editoru je proto v **nápovědě** a v nastavení,
    /// kde se vybíralo.
    func headerButton(path: String, line: Int? = nil) -> some View {
        Button {
            open(path, line)
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .help(help)
    }

    /// Tlačítko na **kartě nálezu**: popisek celý.
    ///
    /// Na kartě je místo (panel má 300 bodů a akce stojí pod cestou) a hlavně je to ta akce, kvůli
    /// které #530 vzniklo — z nálezu se skáče do kódu, aby se opravil. Ikona bez popisku by tady
    /// byla hádanka, kdežto v hlavičce souboru je to jedna z pěti věcí na řádce.
    func cardButton(path: String, line: Int?) -> some View {
        Button {
            open(path, line)
        } label: {
            Label(title, systemImage: "arrow.up.forward.app")
                .font(.caption)
                .lineLimit(1)
        }
        .buttonStyle(.accentLink)
        .help(help)
    }

    /// Nápověda u obou tlačítek — popisek a **věta o tom, že se otevírá kopie z cache**.
    ///
    /// Věta je u tlačítka, ne jen v nastavení, a je to podmínka téhle akce: kdo v otevřeném
    /// souboru začne psát, musí vědět, že nepíše do svého klonu. Vidět celá je v nastavení,
    /// protože tam se ta volba dělá — na kartě nálezu by se opakovala u každého z nich.
    private var help: String { "\(title) · \(note)" }
}
