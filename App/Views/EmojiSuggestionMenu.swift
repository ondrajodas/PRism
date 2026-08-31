import SwiftUI

/// Nabídka emotikonů nad textovým polem (#483) — **tentýž popover jako u labelů** (návrh, sekce 38).
///
/// Nadpis, řádky, patka s klávesami. **Hledací pole v ní ale není a nemá být**: dotaz se píše rovnou
/// do zprávy (`:ta`), takže druhé pole by ukazovalo totéž na dvou místech a jedno z nich by bylo to
/// falešné. Ze stejného důvodu dotaz nestojí ani v nadpisu — `PickerHeading` je `textCase(.uppercase)`
/// a z `:ta` by udělal `:TA`, přitom u shortcodu je malé písmeno **data**, ne dekorace (tatáž past
/// jako u slugu v #413).
///
/// **Není to `popover`, a je to podmínka, ne styl.** `NSPopover` si bere fokus, takže by v poli
/// přestalo jít psát — a psaní je tady zároveň to hledání. Kreslí se proto `overlay`em
/// (`emojiMenuAbove`), čímž fokus zůstane tam, kde je. **Nasazuje ho volající**, ne pole: ořezávající
/// předek by nabídku uřízl, a dvě ze tří polí v takovém předkovi sedí (viz `EmojiSuggestionBox`).
///
/// **Řádky se nedají kliknout, a je to rozhodnutí.** Vložení stojí celé na tom, kde je kurzor;
/// kliknutí do plochy nad zaměřeným polem je zrovna ta jediná interakce, po které se první responder
/// umí přesunout jinam — a bez kurzoru není kam vkládat. Vstup je proto klávesnice, jak ho kreslí
/// patka. Návrh o kliknutí nemluví.
///
/// **Čte si `EmojiSuggestionBox` sama, ne přes parametry**, a je to výkonové rozhodnutí (#472):
/// kdyby řádky přišly jako hodnota, přečetl by je majitel nabídky ve svém těle — a majitelem je tab
/// `Konverzace`, panel a bublina. Úhoz by pak překreslil je, ne nabídku. Ze stejného důvodu je
/// **prázdný stav tady**: `if box.rows.isEmpty` u volajícího by byl týž problém.
struct EmojiSuggestionMenu: View {
    let suggestions: EmojiSuggestionBox

    /// Šířka `.pkr` z návrhu. **`maxWidth`, ne pevná**: v návrhu je to `width: min(300px, 100%)`,
    /// takže v široké konverzaci si nabídka bere svých 300 bodů a v úzkém panelu jeho šířku. Jako
    /// `overlay` dostane návrh šířky té plochy, na které visí, tedy přesně to `100%` — u composeru
    /// je to pruh přes celý tab (nabídka tedy 300), v panelu jeho vytažená šířka.
    ///
    /// `nonisolated`, aby si ji mohla vzít i sonda: `arguments:` v testu se vyhodnocuje mimo actor.
    nonisolated static let width = 300.0

    /// `--radius-sm` z návrhu.
    private static let radius = 7.0

    var body: some View {
        if suggestions.rows.isEmpty {
            EmptyView()
        } else {
            list(of: suggestions.rows, highlighted: suggestions.highlighted)
        }
    }

    private func list(of rows: [Policy.EmojiSuggestion], highlighted: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PickerHeading(title: "Emotikon")
            ForEach(rows) { row in
                self.row(row, isSelected: rows[safely: highlighted]?.id == row.id)
            }
            PickerKeyHints(confirm: "vloží")
        }
        .frame(maxWidth: Self.width)
        .background(Palette.surface, in: .rect(cornerRadius: Self.radius))
        .overlay { RoundedRectangle(cornerRadius: Self.radius).strokeBorder(Palette.line) }
        // **Stín tady není schválně** — nasazuje ho `emojiMenuAbove`, tedy to místo, které nabídku
        // pokládá nad obsah. Je to dělení podle toho, čí ta vlastnost je: `--shadow-lg` existuje
        // proto, že nabídka **visí nad něčím**, ne proto, že je to seznam. A prakticky:
        // rozostřený stín kreslí body **za** rámem nabídky, takže by sonda na přetečení
        // (`OverflowProbe`) měřila jeho rozostření místo obsahu.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("nabídka emotikonů")
    }

    /// Jeden řádek: **znak, `:jméno:` a — když shoda přišla přes alias — alias vpravo**.
    ///
    /// Řádek je **na znak, ne na jméno**: `:+1:` a `:thumbsup:` je jeden 👍, takže dva řádky by byly
    /// nabídka, ve které se nedá vybrat ani dobře, ani špatně. Alias je vidět vpravo, jinak by řádek
    /// `:+1:` vypadal na dotaz `:thu` jako omyl nabídky.
    ///
    /// **Jméno se zalomí, neořeže** (`overflow-wrap: anywhere` z návrhu): je jediné, podle čeho se
    /// pozná, který znak se vloží — tatáž úvaha jako u jména nového labelu v #413. Zlomy nabízí
    /// `Policy.emojiShortcodeLabel(of:)`, protože `Text` sám uvnitř slova nezalamuje a nejdelší jméno
    /// v katalogu (`:hand_with_index_finger_and_thumb_crossed:`, 42 znaků) se do 278 bodů nevejde.
    private func row(_ suggestion: Policy.EmojiSuggestion, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            Text(verbatim: suggestion.emoji.character)
                .font(.system(size: 14))
                .frame(width: 18, alignment: .leading)
            Text(verbatim: Policy.emojiShortcodeLabel(of: suggestion.emoji.name))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 7)
            if let alias = suggestion.alias {
                Text(verbatim: alias)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background { if isSelected { Rectangle().fill(Palette.accentWeak) } }
        // Čtečce se řádek čte **celou větou**, jako položky nabídek v panelu: samotný znak s mono
        // jménem vedle sebe se přečte jako dvě nesouvisející věci.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(of: suggestion))
    }

    private func label(of suggestion: Policy.EmojiSuggestion) -> String {
        guard let alias = suggestion.alias else { return "vložit \(suggestion.emoji.name)" }
        return "vložit \(suggestion.emoji.name), nalezeno jako \(alias)"
    }
}
