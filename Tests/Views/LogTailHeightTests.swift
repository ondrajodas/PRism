import AppKit
import Testing

@testable import PRism

/// Výška okýnka s koncem logu (#292).
///
/// Počítá se z metriky **toho fontu, kterým se kreslí** (#236) — kdo si říká o velikost, musí ji
/// měřit na tom, na čem kreslí. Bez zalamování je to přesné, takže se to dá tvrdit: jeden řádek
/// textu je jeden řádek sazby.
///
/// Co se dá pokazit potichu: **zastropovat i krátký log** (pod třířádkovým logem by zbylo 320 bodů
/// prázdna) a **nezastropovat dlouhý** (dva tisíce řádků naplno odtlačí seznam checků mimo
/// obrazovku, což je zrovna to, kvůli čemu se detail stěhoval z `Přehledu`).
@Suite("Výška konce logu")
struct LogTailHeightTests {
    private let fontSize: CGFloat = 10.5
    private let spacing: CGFloat = 2
    private let limit: CGFloat = 320

    private func height(_ lines: Int) -> CGFloat {
        LogTailTextView.height(forLines: lines, fontSize: fontSize, lineSpacing: spacing, limit: limit)
    }

    /// Proti **layout manageru**, ne proti spočítané konstantě: kdyby se výška řádku brala odjinud
    /// než z fontu, vyšla by tady jiná — a přesně to je ta chyba, kterou #236 popisuje.
    @Test("Výška vychází z metriky fontu, kterým se kreslí")
    func usesTheDrawingFontMetric() {
        let manager = NSLayoutManager()
        let lineHeight = manager.defaultLineHeight(for: LogTailTextView.font(size: fontSize)) + spacing

        // Tři řádky se do stropu vejdou, takže se dá tvrdit přesná hodnota.
        let expected = 3 * lineHeight + 2 * LogTailTextView.inset.height
        #expect(abs(height(3) - expected - LogTailTextView.horizontalScrollerHeight) <= 1.0)
    }

    /// **Kontrola měřidla**: rezerva na vodorovný scroller je v kódu opsané číslo, protože
    /// `NSScroller.scrollerWidth` je vázaná na hlavní vlákno. Tenhle test je to jediné, co ji drží
    /// u systému — bez něj by se okýnko potichu rozešlo se scrollerem.
    @MainActor
    @Test("Rezerva na scroller odpovídá systému")
    func scrollerReserveMatchesTheSystem() {
        #expect(LogTailTextView.horizontalScrollerHeight
            == NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy))
    }

    @Test("Krátký log si nebere víc, než potřebuje")
    func shortLogStaysShort() {
        #expect(height(1) < limit)
        #expect(height(3) < limit)
        #expect(height(3) > height(1), "tři řádky mají být vyšší než jeden")
    }

    /// Prázdný ocas nesmí dát nulovou výšku — z okýnka bez výšky se nedá poznat, že tam log je.
    @Test("Prázdný ocas má aspoň jeden řádek")
    func emptyTailStillHasHeight() {
        #expect(height(0) > 0)
        #expect(height(0) == height(1))
    }

    /// **Tohle je ta mez, na které záleží.** Dva tisíce řádků je od #292 běžný stav, ne krajní.
    @Test("Dlouhý log se zastropuje", arguments: [300, 2_000, 10_000, 25_000])
    func longLogIsCapped(lines: Int) {
        #expect(height(lines) == limit)
    }

    /// Výška je **monotónní** a nikdy nepřeteče strop — kdyby se scroller přičítal nad strop,
    /// okýnko by vyrostlo právě u nejdelších logů.
    @Test("Výška roste a strop nepřeteče")
    func heightIsMonotonicAndBounded() {
        var previous: CGFloat = 0
        for lines in [0, 1, 5, 10, 20, 21, 22, 50, 300] {
            let current = height(lines)
            #expect(current >= previous, "výška se u \(lines) řádků zmenšila")
            #expect(current <= limit, "výška u \(lines) řádků přetekla strop")
            previous = current
        }
    }
}
