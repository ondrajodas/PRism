import AppKit
import SwiftUI

/// Kód v `CodeTextSheet`u jako **jeden** text — read-only `NSTextView` (#157).
///
/// **Ne SwiftUI `Text` se `.textSelection(.enabled)`.** Ten dává selekci po jednotlivých `Text`ech,
/// takže by šlo vybrat jen jeden řádek — a ani jeden `Text` s odřádkováním to nespravil (zkoušeno
/// u #157). `NSTextView` je proti tomu plnohodnotné textové zobrazení: výběr myší přes řádky, ⌘A,
/// ⌘C i kontextové menu se `Copy` dostaneme od systému, ne z vlastního kódu. Tatáž úvaha pak
/// dovedla i **diff sám** k `DiffTextView`.
///
/// Zůstává i po tom přepisu, protože umí něco, co diff neumí: **vybrat přes hranice bloků**. Blok
/// v diffu končí u bubliny, u hlavičky hunku a u rozbalovacího řádku; tady je hunk celý a naráz.
struct SelectableCodeView: NSViewRepresentable {
    let code: String
    /// Jazyk na obarvení. **`nil` = jednou barvou**, a u logu je to podmínka, ne shoda: obarvení po
    /// řádcích stojí na 8,78MB logu 155 ms proti 7,9 ms (změřeno u #214). Do #417 tady byla cesta
    /// k souboru a o jazyku se rozhodovalo tady — u logu tedy tím, že `Language(path:)` v jméně
    /// checku nic nepoznal, což je náhoda, ne rozhodnutí.
    let language: Language?
    let colorScheme: ColorScheme

    /// Šířka jednoho znaku písma, kterým se sází. Mono má všechny znaky stejně široké, takže stačí
    /// změřit jeden — na tomhle systému 8,036 bodu pro mono 13 b. **Měří se na písmu**, protože je
    /// to hodnota fontu, ne konstanta aplikace; tatáž úvaha jako u lišty diffu (#188). Patička
    /// sheetu z ní počítá, kolik řádků se nevešlo na šířku.
    ///
    /// Bere se z `FontMetric` (#407): je to `static let`, tedy **jedno měření na proces navždycky**,
    /// takže nula z metriky by tady zůstala do konce běhu — a měřidlo ji nepamatuje.
    static let characterWidth = FontMetric.shared.characterWidth(of: font)

    /// Písmo, kterým se sází — **jedno místo pro kresbu i pro měření**, jinak by se spočítaná
    /// kapacita řádku rozešla s tím, co se nakreslí (tatáž past jako u `MiniButtonStyle.labelFont`,
    /// #284).
    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView() }

    /// Rolovací plocha s textovým view, nastavená tak, jak se kreslí.
    ///
    /// **Vlastní továrnička, ne tělo `makeNSView`** — tatáž úvaha jako u `LogTailTextView` (#303):
    /// `NSViewRepresentableContext` se v testu nepostaví, takže by se odsazení a zalamování daly
    /// ověřit jedině nad ruční kopií toho nastavení. A druhé místo, kde se to nastavuje, je druhá
    /// pravda o jedné šířce — přitom se z odsazení počítá kapacita řádku pro patičku sheetu.
    static func makeScrollView() -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        // Read-only, ale **vybíratelné** — o tohle tu jde.
        textView.isSelectable = true
        textView.drawsBackground = false
        // Odsazení je z `Policy`, ne literál: počítá se z něj kapacita řádku (`codeSheetCharacters`),
        // takže dvě čísla by znamenala dvě pravdy o jedné šířce.
        textView.textContainerInset = NSSize(width: Policy.codeSheetTextInset, height: 8)
        // Zalamování místo vodorovného scrollu, jako v diffu. Zalomení není znak, takže se do
        // vybraného textu nedostane.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // **Fokus musí dostat text, jinak mu nechodí klávesy** — ⌘A ani ⌘C. Změřeno u #157: bez
        // tohohle zůstala schránka po ⌘A+⌘C nedotčená, protože first responder bylo okno sheetu.
        // Odloženě, protože v `makeNSView` view ještě žádné okno nemá.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    /// **Stráž s klíčem v `Coordinator`u tady není, a je to změřené rozhodnutí, ne opomenutí**
    /// (#417, potvrzuje #393). Roztahovatelný sheet vypadal jako ten případ, kvůli kterému stráž
    /// existuje u bloku diffu: přeměření plochy při každém kroku tažení znamená průchod tělem
    /// sheetu, a přesázení by **zrušilo rozdělaný výběr**. Změřeno na skutečném okně sheetu
    /// (patnáct kroků tažení za okraj po 12 bodech): `updateNSView` se za celé tažení nezavolal
    /// **ani jednou** a výběr zůstal. SwiftUI aktualizaci nepošle, dokud se hodnota representable
    /// nezmění — a `code`, `language` ani `colorScheme` se tažením nemění.
    ///
    /// Platí proto pravidlo z `CLAUDE.md`: stráž, kterou nemá co vyvolat, **se nedává** — nešla by
    /// ověřit vloženou regresí (vyzkoušeno: bez stráže tentýž test projde). Co drží výběr, je
    /// `DiffBlockUpdateTests.codeSheetKeepsTheSelectionWhileResizing` — kdyby si tohle view někdy
    /// začalo říkat o vlastní velikost (`sizeThatFits`), aktualizace by přišly a ten test spadne.
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // Přepisuje se celý obsah, ne rozdíl: je to jeden hunk nebo celý log, a děje se to při
        // otevření okna a při přepnutí světlého a tmavého režimu.
        textView.textStorage?.setAttributedString(
            Self.attributed(code, language: language, colorScheme: colorScheme)
        )
    }

    /// Obarvení jde přes tentýž `SyntaxHighlighter` jako diff — jedno místo, kde se rozhoduje, co
    /// je klíčové slovo. Jen se výsledek slepí do jednoho `NSAttributedString`, aby to byl **jeden**
    /// text a selekce v něm byla jedna.
    static func attributed(_ code: String, language: Language?, colorScheme: ColorScheme) -> NSAttributedString {
        let font = Self.font
        let palette = SyntaxPalette.forScheme(colorScheme)
        // **Barva textu se nasazuje vždycky** (#393): chybějící `.foregroundColor` v atributovaném
        // řetězci znamená černou, ne „dědí z okolí“, takže hunk bez rozpoznaného jazyka i obyčejné
        // identifikátory v něm byly v tmavém režimu černé na tmavém. Viz `SyntaxColors.plain`.
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Palette.ink)]

        // **Bez známého jazyka se text neskládá po řádcích** (#214). Dělení a slepování řádek po
        // řádce nic nepřidá, když se nemá co obarvovat — a u velkého textu je to celá cena: změřeno
        // na dvoumegovém logu z Actions **38 ms po řádcích proti 2,2 ms jednolitě** (17×), na
        // 8,78 MB 155 ms proti 7,9 ms. Konec logu (#214) tudy chodí vždycky, protože `.log` žádný
        // jazyk nemá; sheetu s kódem to pomůže u souborů, které `Language` nezná.
        guard let language else {
            return NSAttributedString(string: code, attributes: base)
        }

        let result = NSMutableAttributedString()

        // `TextLines.all`, ať prázdné řádky nezmizí — v kódu drží strukturu a bez nich by se
        // vložený text rozešel s originálem. A dělí se **na jakémkoli zakončení** (#295): text
        // s `CRLF` by přes `split(separator: "\n")` zůstal jeden, takže by se obarvoval jako jediný
        // řádek — a jeho celý objem by se uložil jako jeden klíč do `SyntaxRunCache`, který je
        // klíčovaný textem řádku (#224).
        for (index, line) in TextLines.all(code).enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: base))
            }
            for run in SyntaxHighlighter.runs(of: String(line), in: language) {
                var attributes = base
                // `nil` u obyčejného textu nechává základní barvu z `base`, jako v diffu.
                if let color = palette.color(for: run.kind) {
                    attributes[.foregroundColor] = NSColor(color)
                }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        return result
    }
}
