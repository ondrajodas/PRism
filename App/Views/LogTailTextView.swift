import AppKit
import SwiftUI

/// Konec logu jako **jeden `NSTextView`** (#292), ne SwiftUI `Text`.
///
/// **Tohle je to, co dovoluje ukázat tisíce řádků.** SwiftUI `Text` se `.fixedSize()` sází celý
/// naráz a u dlouhých řádků z Actions logu roste kvadraticky — změřeno na skutečném 8,78MB logu
/// (`keboola/job-queue-daemon`, job 93844012547):
///
/// | Řádků konce logu | SwiftUI `Text` | `NSTextView` |
/// |---|---|---|
/// | 300 | 107,85 ms | **2,06 ms** |
/// | 2 000 | 6 210,22 ms | **1,96 ms** |
/// | 10 000 | 156 432,33 ms | **6,81 ms** |
///
/// Dvě a půl minuty na deseti tisících řádcích nejsou opomenutí, které by šlo doladit: `Text` musí
/// znát velikost celku dopředu (a u řádků o 2 258 znacích je to 13 930 bodů na šířku), kdežto
/// TextKit sází **líně po viewportu**. Projíždění proto stojí 0,00 ms medián (nejhorší snímek
/// 0,01 ms) bez ohledu na velikost — a to je zrovna ta cena, na kterou si stěžuje #275.
///
/// Čísla jsou z `CheckLogPerformanceMeasurement`, takže se dají pustit znovu.
///
/// **Nezalamuje se**, jak to má návrh (`.logtail`): kontejner je „nekonečně" široký a scrolluje se
/// dvěma osami. Zalamování by u řádku o 2 258 znacích (v tom logu jich je 272 nad tisíc znaků)
/// snědlo celé okýnko jedním řádkem logu.
///
/// Vedlejší zisk, který se nehledal: konec logu je **vybíratelný**, takže se z něj dá kopírovat bez
/// otevírání sheetu — `⌘C` i kontextové menu dává systém.
struct LogTailTextView: NSViewRepresentable {
    let text: String
    /// Velikost písma. Drží se tady, protože z ní se počítá výška — a ta se musí měřit na tom, na
    /// čem se doopravdy kreslí (#236).
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let color: Color

    /// Odsazení textu od hran — dovnitř `NSTextView`u, ne paddingem ve SwiftUI, aby scroller
    /// nejezdil po prázdném pruhu.
    nonisolated static let inset = NSSize(width: 0, height: 4)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        // **Bez zalamování.** `widthTracksTextView = false` a „nekonečný" kontejner znamenají, že
        // dlouhý řádek zůstane jedním řádkem a jede se za ním do strany.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Co už je ve view nasázené. Drží se proto, aby se text **nepřepisoval při každém průchodu**
    /// `body`: přepsání zahodí výběr i polohu scrollu, takže by uživateli mizel pod rukama vybraný
    /// řádek pokaždé, když se v okně změní cokoli jiného.
    ///
    /// Porovnává se celý `String`, a není to drahé: SwiftUI podává tutéž hodnotu, takže obě strany
    /// ukazují na jednu paměť a `==` na ní končí hned. Rozejít se můžou jedině tím, že se text
    /// doopravdy změnil — a to je zrovna ta chvíle, kdy se přepsat má.
    ///
    /// Barva se sleduje spolu s textem, i když `Palette.ink2` je `NSColor` s dynamickým providerem
    /// a přepnutí režimu si tedy vyřídí sám. Je to pojistka na volajícího, který by podal barvu
    /// **staticky** rozhodnutou podle `colorScheme` — pak by se bez přepsání textu tmavý režim
    /// nakreslil světlou barvou, a to potichu.
    @MainActor
    final class Coordinator {
        var shownText: String?
        var shownColor: Color?
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        guard coordinator.shownText != text || coordinator.shownColor != color else { return }
        let textChanged = coordinator.shownText != text
        coordinator.shownText = text
        coordinator.shownColor = color

        textView.textStorage?.setAttributedString(Self.attributed(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            color: color
        ))

        // **Otevírá se na konci logu, ne na začátku ocasu** (#292). To, kvůli čemu se log otevírá
        // (selhaná assertace, exit code), je na posledních řádcích — a se dvěma tisíci řádků je
        // začátek ocasu sto obrazovek daleko. Do #292 na tom nezáleželo tolik, protože ocas měl
        // řádků tři stovky; zvednutím stropu by se z toho stal krok navíc při každém otevření.
        //
        // Vodorovně se vrací **na nulu**: skok na konec dokumentu jinak zůstane u konce nejdelšího
        // řádku (v tom logu 2 258 znaků), takže by okýnko začínalo uprostřed slova — chyceno
        // vykreslením `NSScrollView`u do PNG, z kódu to vidět není.
        guard textChanged else { return }
        DispatchQueue.main.async { [weak scroll, weak textView] in
            guard let scroll, let textView else { return }
            textView.scrollToEndOfDocument(nil)
            var origin = scroll.contentView.bounds.origin
            origin.x = 0
            scroll.contentView.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// **Jednolitý text, ne po řádcích.** Log žádný jazyk nemá, takže se nemá co obarvovat — dělení
    /// a slepování řádek po řádce stojí u dvoumegového textu 38 ms proti 2,2 ms (#214).
    nonisolated static func attributed(_ text: String, fontSize: CGFloat, lineSpacing: CGFloat, color: Color) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: Self.font(size: fontSize),
            .foregroundColor: NSColor(color),
            .paragraphStyle: paragraph,
        ])
    }

    nonisolated static func font(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Jak vysoké okýnko konec logu potřebuje, nejvýš `limit`.
    ///
    /// Počítá se **z metriky toho fontu, kterým se kreslí** (#236): kdo si říká o velikost, musí ji
    /// měřit na tom, na čem kreslí, jinak nakreslí jiný počet řádků, než na kolik si řekl. Bez
    /// zalamování je to přesné — jeden řádek textu je jeden řádek sazby.
    ///
    /// Krátký log tedy nedostane 320 bodů s prázdnem pod sebou a dlouhý se do 320 bodů zastropuje
    /// a scrolluje uvnitř.
    nonisolated static func height(forLines lines: Int, fontSize: CGFloat, lineSpacing: CGFloat, limit: CGFloat) -> CGFloat {
        let manager = NSLayoutManager()
        let lineHeight = manager.defaultLineHeight(for: font(size: fontSize)) + lineSpacing
        let content = CGFloat(max(lines, 1)) * lineHeight + 2 * inset.height
        // Vodorovný scroller si ukusuje z výšky, takže se k obsahu přidává — jinak by na
        // zastropovaném okýnku zakrýval poslední řádek, tedy ten, kvůli kterému se log otevírá.
        return min(limit, content + horizontalScrollerHeight)
    }

    /// Kolik se nechává na vodorovný scroller: **13 bodů**, tedy
    /// `NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy)` na tomhle systému.
    ///
    /// Rezervuje se **legacy** styl, protože jen ten místo doopravdy zabírá; overlay scrollery
    /// plavou nad obsahem. Na `NSScroller.preferredScrollerStyle` se schválně neptáme dvakrát:
    /// je vázaný na hlavní vlákno (výška se počítá i mimo něj) a **mění se za běhu** podle toho,
    /// jestli je připojená myš — okýnko, kterému se výška mění připojením myši, je horší než pár
    /// bodů rezervy u krátkého logu.
    ///
    /// Číslo je opsané, protože ta funkce je taky vázaná na hlavní vlákno. **Nedrží ho odhad, ale
    /// test** (`LogTailHeightTests`), který ho porovnává s tím, co vrací systém — kdyby se hodnota
    /// rozešla, spadne, místo aby se okýnko potichu rozešlo se scrollerem.
    nonisolated static let horizontalScrollerHeight: CGFloat = 13
}
