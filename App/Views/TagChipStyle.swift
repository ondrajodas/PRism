import AppKit
import SwiftUI

/// Sazba chipu z návrhu (`.tagchip`) — **a rozměry, ze kterých se počítá zalomení** (#532).
///
/// Metriky a kresba bydlí spolu ze stejného důvodu jako u `LabelChipStyle`: pravidlo #236 říká, že
/// kdo si říká o velikost, musí ji měřit na tom, na čem kreslí. Dvě místa znamenají dvě pravdy
/// o jedné šířce a rozejdou se při prvním doladění odsazení.
///
/// **Není to `LabelChipStyle` s jinými barvami, a je to rozdíl v návrhu, ne v odstínu.** `.lchip` je
/// **slovo z repozitáře** (label), takže je v UI fontu, semiboldem, s kapslovým poloměrem a
/// s puntíkem barvy. `.tagchip` je **hodnota, kterou jsem napsal** (organizace, login, jméno repa):
/// mono, regular, poloměr 5. Odlišení mono od UI fontu je u téhle dvojice zapsané v návrhu
/// v komentáři u `.lchip`.
///
/// Čísla jsou z návrhu doslova (`docs/navrh.html`, `.tagchip`, `.tagchip.plus`, `.chipline`):
/// mono 10,5, odsazení 2/7, obtažení 1, poloměr 5, mezera 5, barvy `--panel-3` / `--line-soft` /
/// `--ink-2`.
///
/// **Přidávací chip má z toho všeho jen dvě věci jinak, a je to přečtené z CSS, ne od oka**:
/// `.tagchip.plus` přebíjí **jen `color` a `border-style`**. Řez, velikost, odsazení, poloměr
/// **i podklad** si dědí, takže vlastní akční řez (UI font, medium — jak ho má `.chip-add`
/// u labelů), průhledná výplň nebo akcentový okraj jsou **tři různé odchylky od zákresu**. Všechny
/// tři měla první podoba a vypadly z renderu referenční kresby vedle aplikace.
enum TagChipStyle {
    /// `font-size: 10.5px`.
    static let fontSize = 10.5
    /// `padding: 2px 7px`.
    static let insetHorizontal = 7.0
    static let insetVertical = 2.0
    /// `border: 1px solid`. **Počítá se do šířky** (`box-sizing: border-box`) — tatáž past jako
    /// u `.lchip`, kde chip o okraj a odsazení přerostl řádek.
    static let borderWidth = 1.0
    /// `border-radius: 5px`.
    static let cornerRadius = 5.0
    /// `gap: 5px` — mezi chipy i uvnitř chipu.
    static let spacing = 5.0
    /// Křížek na odebrání. **V zákresu není** — chipy jsou tam nakreslené staticky a mazání v nich
    /// není vůbec, takže je to nejmenší přípustný přídavek: glyf v mřížce chipu, ne druhý řádek
    /// a ne skrytá akce. Je to tatáž volba, jakou má `.lchip` s puntíkem, který `.tagchip` nemá.
    static let removeGlyphSize = 8.0

    /// **Funkce, ne konstanta**: `NSFont` není `Sendable`, takže statická konstanta z něj je
    /// v Swiftu 6 chyba souběhu. Tentýž tvar jako `LabelChipStyle.nameFont()`.
    nonisolated static func font() -> NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Co si chip vezme mimo text — odsazení z obou stran a obě obtažení.
    ///
    /// Obtažení se počítá, protože v CSS leží **venku za odsazením**; v SwiftUI `overlay` rámeček
    /// frame nezvětšuje, takže se ten bod přidává k odsazení. Bez toho by chip vyšel o dva body
    /// užší než v zákresu.
    nonisolated static var textInset: Double { insetHorizontal + borderWidth }

    nonisolated static var verticalInset: Double { insetVertical + borderWidth }
}

/// Chip s napsanou hodnotou a křížkem na odebrání (`.tagchip`, #532).
struct TagChipView: View {
    let title: String
    /// Co se řekne čtečce obrazovky u křížku — `Odebrat organizaci keboola`.
    let removeLabel: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: TagChipStyle.spacing) {
            Text(verbatim: title)
                .font(Font(TagChipStyle.font()))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: remove) {
                Image(systemName: "xmark")
                    // **Řez, ne `imageScale`**: SF Symboly nemají jednu výšku (#325), a chip je
                    // vysoký osmnáct bodů — glyf odvozený od textového řezu by ho rozhoupal.
                    .font(.system(size: TagChipStyle.removeGlyphSize, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
            }
            .buttonStyle(.borderless)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
        }
        .padding(.horizontal, TagChipStyle.textInset)
        .padding(.vertical, TagChipStyle.verticalInset)
        .background {
            RoundedRectangle(cornerRadius: TagChipStyle.cornerRadius).fill(Palette.raised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TagChipStyle.cornerRadius)
                .strokeBorder(Palette.lineSoft, lineWidth: TagChipStyle.borderWidth)
        }
    }
}

/// Přidávací chip (`.tagchip.plus`) — akcentový text a **přerušovaný** okraj.
///
/// Přerušovaný proti plnému drží úmluvu z návrhu, tutéž jako u `AddChipLabel`: **plné je to, co
/// nastavené je, přerušované to, co se dá přidat.**
struct AddTagChipLabel: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            // Mono a `--accent`: `.tagchip.plus` mění barvu textu, ne řez.
            .font(Font(TagChipStyle.font()))
            .foregroundStyle(Palette.accent)
            .lineLimit(1)
            .padding(.horizontal, TagChipStyle.textInset)
            .padding(.vertical, TagChipStyle.verticalInset)
            // **Podklad zůstává** (`--panel-3`) — `.tagchip.plus` `background` nepřebíjí. Chip bez
            // výplně byl první podoba a proti zákresu se ztrácel.
            .background {
                RoundedRectangle(cornerRadius: TagChipStyle.cornerRadius).fill(Palette.raised)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TagChipStyle.cornerRadius)
                    .strokeBorder(
                        // **`--line-soft`, ne `--accent`**: `.tagchip.plus` mění `border-style`,
                        // ne `border-color`. Akcentový okraj byl druhá odchylka z téhož renderu.
                        Palette.lineSoft,
                        style: StrokeStyle(lineWidth: TagChipStyle.borderWidth, dash: [3, 2])
                    )
            }
            .contentShape(.rect)
    }
}
