import AppKit
import Foundation
import Testing

@testable import PRism

/// **Kolik znaků na stranu ubere širší levý sloupec** (#506) — zadání issue to žádá změřit,
/// protože z toho plyne jediné rozhodnutí: buď se v pohledu *Vedle sebe* itinerář skládá jako
/// dnes strom, nebo se za těch padesát bodů platí kódem.
///
/// Počítá se **produkční funkcí** (`Policy.charactersPerSide`, `Policy.diffCodeColumnWidth`)
/// a **skutečnými** rozměry: šířka znaku z mono písma, kterým se kód sází, a `gutter`
/// z `DiffLineView.contentInset(for:)`. Vlastní aritmetika v testu by měřila svoji kopii pravidla.
///
/// **Naměřeno** (štěrbina 1 047 b, znak 8,036 b): *Vedle sebe* **3 znaky na stranu** (41 → 38),
/// *Pod sebou* **6 znaků** (86 → 80). A ve `split`u se za to neplatí ani tím: sloupec se tam
/// **skládá** (#188), takže je z něj pruh 34 bodů v obou případech — ta trojka je cena za to, když
/// si ho tam člověk otevře `⌘1`. Slib 120 znaků se přitom v `split`u neplnil ani do #506 (41).
@Suite("Místo na diff vedle itineráře (#506)")
struct ItineraryColumnRoomTests {
    /// Plocha tabu na výchozím okně: 1100 minus rail 52 — tatáž hodnota, ze které počítá zákres
    /// a `CommitPanelRoomTests`.
    private let tabWidth = 1_047.0
    /// Šířka sloupce do #506 a od #506.
    private let before = 210.0
    private let after = 260.0

    /// Šířka znaku mono písma, kterým se kód sází — **z `FontMetric`** (#407), a **dočkaná**
    /// (#550): nepovedené měření vypadne jako `nil`, ne jako nula, takže by se z nuly jinak
    /// stalo tvrzení o tom, co se v tu sekundu dělo v procesu.
    private var characterWidth: Double {
        TestWait.settledFontMetric(
            .characterWidth,
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
    }

    private func charactersPerSide(_ width: Double, layout: DiffLayout) -> Int {
        Policy.charactersPerSide(
            contentWidth: width,
            characterWidth: characterWidth,
            layout: layout,
            gutter: DiffLineView.contentInset(for: layout)
        )
    }

    /// Kolona kódu **produkční funkcí**, ne odečítáním v testu: `diffCodeColumnWidth` odečítá
    /// i mezeru před tím, co stojí vpravo (#503), a dvě aritmetiky by se rozešly.
    ///
    /// **Od #506/2 se sloupec odečítá tady**, ne ve `diffCodeColumnWidth`: sloupec stojí vedle
    /// všech tabů, takže ho odečítá rozvržení detailu a diff dostane štěrbinu, ve které už není.
    /// Odečtení `tree` na téhle řádce je tedy to, co v okně dělá `HStack` v `content`.
    private func codeWidth(tree: Double, margin: Bool) -> Double {
        let columns = DiffSideColumns(tree: true, panel: false, margin: margin ? .cards : .hidden)
        return Policy.diffCodeColumnWidth(available: tabWidth - tree, columns: columns) ?? 0
    }

    @Test("Sloupec je 260 bodů, složený 34")
    func theColumnIsTwoHundredAndSixtyPointsWide() {
        #expect(Policy.treeColumnWidth(expanded: true) == after)
        #expect(Policy.treeColumnWidth(expanded: false) == 34)
    }

    /// **Ve `split`u se sloupec skládá, takže šířka nerozhoduje** (#188). Tohle je to tvrzení,
    /// kvůli kterému se za 260 bodů v pohledu vedle sebe **neplatí ničím** — a je to vlastnost
    /// rozhodnutí o kolonách, ne velikosti okna.
    @Test("Vedle sebe se sloupec složí, takže na kód zbude totéž")
    func sideBySideCollapsesTheColumnAnyway() {
        let split = Policy.diffSideColumns(layout: .split, hasMargin: false, available: tabWidth)
        #expect(!split.tree)
        // A i v okně přes celou 3440b obrazovku: `split` sloupec skládá bez ohledu na šířku.
        let wide = Policy.diffSideColumns(layout: .split, hasMargin: false, available: 3_388)
        #expect(!wide.tree)
    }

    /// **Kdyby si ho člověk v `split`u otevřel `⌘1`, stojí to tři znaky na stranu.** Padesát
    /// bodů dělených dvěma stranami a šířkou znaku (8,036 b) je 3,1 znaku — naměřeno **41 → 38**.
    ///
    /// Tvrdí se **rozdíl**, ne absolutní počty: ty závisí na šířce znaku, a tu drží vlastní
    /// tvrzení níž.
    @Test("Otevřený sloupec ve split pohledu ubere tři znaky na stranu")
    func theExtraFiftyPointsCostThreeCharactersPerSide() {
        let old = charactersPerSide(codeWidth(tree: before, margin: false), layout: .split)
        let new = charactersPerSide(codeWidth(tree: after, margin: false), layout: .split)
        #expect(old - new == 3, "do #506: \(old), od #506: \(new)")
        // Slib 120 znaků se ve `split`u na tomhle okně neplnil ani do #506 — proto se nic
        // nevynucuje a proto se sloupec skládá sám.
        #expect(old < Policy.promisedCharactersPerSide, "do #506: \(old) znaků")
    }

    /// **Pod sebou je to šest znaků** (86 → 80), protože se šířka nedělí na dvě strany a celých
    /// padesát bodů ukusuje z jedné kolony. Tady sloupec otevřený zůstává (`diffSideColumns` ho
    /// v `unified` skládá teprve pod podlahou kódu), takže je to ta cena, která se doopravdy platí
    /// každý den.
    ///
    /// **Slib 120 znaků se v tomhle okně neplnil ani do #506** (86), takže ta šestka nesahá na
    /// nic, co by aplikace slibovala — a v okně přes celou 3440b obrazovku se plní i po #506
    /// (tvrzení níž).
    @Test("Pod sebou ubere širší sloupec šest znaků")
    func unifiedPaysSixCharacters() {
        let old = charactersPerSide(codeWidth(tree: before, margin: false), layout: .unified)
        let new = charactersPerSide(codeWidth(tree: after, margin: false), layout: .unified)
        #expect(old - new == 6, "do #506: \(old), od #506: \(new)")
        #expect(old < Policy.promisedCharactersPerSide, "do #506: \(old) znaků")
    }

    /// **Na obrazovce, na které se dělá, se slib plní i po #506.** Ultrawide 3 440 b bez railu je
    /// 3 388; se sloupcem 260 a bez okraje zbude na kód 3 122 bodů, tedy **371 znaků** pod sebou.
    /// Padesát bodů je tam 6 znaků z 377 — proto se za tu šířku neplatí ničím, co by šlo poznat.
    @Test("Na širokém okně slib 120 znaků platí i se širším sloupcem")
    func theWideWindowKeepsThePromise() {
        let new = charactersPerSide(codeWidth(tree: after, margin: false) + (3_388 - tabWidth), layout: .unified)
        #expect(new > Policy.promisedCharactersPerSide, "od #506 na 3388: \(new) znaků")
    }

    /// **S okrajem karet nálezů (#503) se sloupec složí.** Strom jde první, protože je
    /// nejlevnější — a od #506 je o padesát bodů dražší, takže se to musí složit dřív než dřív.
    /// Zapsané měření: podlaha kódu je 360 (`unified`), okraj 300, takže na sloupec zbývá
    /// `1047 − 300 − 6 − 360 = 381` bodů, tedy se 260 pořád vejde.
    @Test("S okrajem karet se sloupec na výchozím okně pořád vejde")
    func theColumnStillFitsNextToTheFindingMargin() {
        let columns = Policy.diffSideColumns(layout: .unified, hasMargin: true, available: tabWidth)
        #expect(columns.tree)
        #expect(columns.margin == .cards)
        // A v okně na podlaze `RootView`u (700) se složí — jako do #506, jen o kus dřív.
        let narrow = Policy.diffSideColumns(layout: .unified, hasMargin: true, available: 700)
        #expect(!narrow.tree)
    }

    /// **Kde je ta hranice.** Se 210 se sloupec vešel do štěrbiny od 570 bodů, se 260 od **620** —
    /// tedy padesát bodů, přesně o kolik sloupec povyrostl, a obojí **pod** podlahou `RootView`u
    /// (700), takže se v žádném okně, které se dá otevřít, kvůli #506 neskládá nic navíc.
    /// S okrajem karet je to o 300 bodů výš, tedy **920** proti 870 — a tam je rozdíl vidět:
    /// v okně 900 se sloupec do #506 vešel a od #506 se složí.
    ///
    /// **Mezera před kolonou (#503) se v tom nepočítá schválně** — `diffSideColumns` ji neodečítá
    /// (odečítá ji až `diffCodeColumnWidth`), takže hranice je `podlaha + sloupec`. Kdo tu šestku
    /// přičte, dostane číslo o šest bodů vedle.
    @Test("Sloupec se pod sebou složí pod 620 bodů štěrbiny")
    func theColumnCollapsesBelowSixHundredAndTwenty() {
        let floor = Policy.minimumCodeWidth(layout: .unified)
        #expect(floor == 360)
        let boundary = floor + after
        #expect(boundary == 620)
        #expect(Policy.diffSideColumns(layout: .unified, hasMargin: false, available: boundary).tree)
        #expect(!Policy.diffSideColumns(layout: .unified, hasMargin: false, available: boundary - 1).tree)
        // S okrajem karet je to o 300 bodů výš — a `RootView` má podlahu 700, takže tuhle hranici
        // člověk doopravdy překročí.
        let withMargin = boundary + Policy.marginColumnWidth(form: .cards)
        #expect(withMargin == 920)
        #expect(Policy.diffSideColumns(layout: .unified, hasMargin: true, available: withMargin).tree)
        #expect(!Policy.diffSideColumns(layout: .unified, hasMargin: true, available: withMargin - 1).tree)
        // Do #506 se v okně 900 sloupec vešel; od #506 se složí. Je to **jediná** změna chování,
        // kterou ta šířka přinesla, a je vidět v okně, ne jen v čísle.
        #expect(900 < withMargin)
        #expect(900 > floor + before + Policy.marginColumnWidth(form: .cards))
    }

    /// **Čísla v dokumentaci platí pro změřenou šířku znaku** (8,04 bodu) — jediné místo, kde se
    /// ta hodnota v téhle sadě tvrdí.
    @Test("Dokumentovaná čísla platí pro změřenou šířku znaku")
    func theMeasuredCharacterWidthHoldsTheNumbers() {
        #expect(abs(characterWidth - 8.04) < 0.5, "šířka znaku: \(characterWidth), \(FontMetric.shared.tally)")
        #expect(DiffLineView.contentInset(for: .split) == 84)
        #expect(DiffLineView.contentInset(for: .unified) == 136)
    }
}
