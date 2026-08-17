import AppKit
import Testing

@testable import PRism

/// Výška okýnka s koncem logu (#292, strop zvednutý u #303).
///
/// Počítá se z metriky **toho fontu, kterým se kreslí** (#236) — kdo si říká o velikost, musí ji
/// měřit na tom, na čem kreslí. Bez zalamování je to přesné, takže se to dá tvrdit: jeden řádek
/// textu je jeden řádek sazby.
///
/// Co se dá pokazit potichu: **zastropovat i krátký log** (pod třířádkovým logem by zbylo 445 bodů
/// prázdna) a **nezastropovat dlouhý** (šest tisíc řádků naplno odtlačí seznam checků mimo
/// obrazovku, což je zrovna to, kvůli čemu se detail stěhoval z `Přehledu`).
///
/// **Tvrzení o rezervě na vodorovný scroller je odsud pryč** (#347) — přestěhovalo se do
/// `LogTailScrollerReserveTests`, protože se musí měřit na kresbě, ne dopočítávat z API s ručně
/// vybranou velikostí scrolleru. Tady zůstává jen aritmetika **nad** tou konstantou.
@Suite("Výška konce logu")
struct LogTailHeightTests {
    private let fontSize = CheckDetailView.logFontSize
    private let spacing = CheckDetailView.logLineSpacing
    /// **Skutečný strop z aplikace, ne opsané číslo.** Kdyby se zvedl bez rozmyslu, spadne
    /// `capIsAWholeNumberOfLines` níž — a to je to jediné, co u téhle konstanty jde tvrdit testem.
    private let limit = CheckDetailView.logMaxHeight

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

    /// **Tohle je ta mez, na které záleží.** Šest tisíc řádků je od #303 běžný stav, ne krajní.
    @Test("Dlouhý log se zastropuje", arguments: [300, 2_000, 6_000, 10_000, 25_000])
    func longLogIsCapped(lines: Int) {
        #expect(height(lines) == limit)
    }

    /// **Strop musí padnout na celý řádek** (#303). Půl řádku na spodní hraně okýnka není jen
    /// nevzhledné: okýnko se otevírá **na konci logu**, takže by ta půlka byla zrovna na tom řádku,
    /// kvůli kterému se log otevírá. Kontroluje se to výpočtem, ne opsanou hodnotou — jinak by test
    /// jen zopakoval konstantu.
    @Test("Strop je celý počet řádků")
    func capIsAWholeNumberOfLines() {
        let manager = NSLayoutManager()
        let lineHeight = manager.defaultLineHeight(for: LogTailTextView.font(size: fontSize)) + spacing
        let usable = limit - 2 * LogTailTextView.inset.height - LogTailTextView.horizontalScrollerHeight
        let lines = (usable / lineHeight).rounded(.down)
        #expect(
            abs(usable - lines * lineHeight) < 0.01,
            "strop \(limit) končí uprostřed řádku — celé řádky jsou na 14N + 25"
        )
        #expect(lines == 30, "strop \(limit) má ukázat 30 řádků, ukazuje \(lines)")
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
