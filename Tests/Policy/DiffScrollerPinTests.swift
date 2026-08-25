import CoreGraphics
import Testing

@testable import PRism

/// **Kde stojí vodorovný pruh bloku dvojic** (#428) — čistá funkce, vyčerpávajícím výčtem.
///
/// Celé pravidlo je `y = min(vlastní pás, hrana výřezu − pás)`, tedy jedna funkce posunu. Testuje se
/// tady, protože je to jediné místo, kde se o poloze rozhoduje: kontejner už jen zapisuje rámce.
///
/// Souřadnice jsou takové, jaké dostane z aplikace — **`y` roste dolů** a obdélníky jsou v jedné
/// soustavě. Kontejner navíc počítá v soustavě, ve které je blok na nule (je to `bounds` jeho plochy),
/// a proto to tak má polovina scénářů; zbytek posouvá blok, aby bylo vidět, že na absolutní poloze
/// nezáleží.
@MainActor
@Suite("Poloha pruhu v bloku (#428)")
struct DiffScrollerPinTests {
    /// Pás z AppKitu, ne konstanta 17 — tatáž hodnota, jakou si blok rezervuje ve `height(forWidth:)`.
    private static let band = DiffPairScrollView.scrollerHeight
    /// Výška řádku kódu. Nemusí být na bod ta z písma: rozhoduje jen ve heuristice tří řádků.
    private static let row = 16.0
    /// Výřez z měření v zadání: `.work` při okně 723,8 b.
    private static let viewport = CGRect(x: 0, y: 0, width: 700, height: 448)

    private func y(block: CGRect, viewport: CGRect = DiffScrollerPinTests.viewport) -> Double {
        Policy.pinnedScrollerY(ofBlock: block, in: viewport, band: Self.band, rowHeight: Self.row)
    }

    private func block(at top: Double, height: Double) -> CGRect {
        CGRect(x: 0, y: top, width: 700, height: height)
    }

    /// Blok, který je celý vidět, **pruh nepřišpendlí**: vyhrává vlastní pás, tedy tam, kde ho
    /// nechalo #422. Kdyby vyhrál druhý člen, sedl by pruh pod dolní hranu bloku.
    @Test("Blok celý vidět má pruh ve svém pásu")
    func aFullyVisibleBlockKeepsTheBarInItsBand() {
        let block = block(at: 100, height: 200)
        #expect(y(block: block) == 200 - Self.band)
        // A na hraně, kde se blok dolní hrany výřezu **dotýká**: pořád vlastní pás, protože jsou to
        // tytéž souřadnice — přechod není skok.
        #expect(y(block: self.block(at: 248, height: 200)) == 200 - Self.band)
    }

    /// Blok přesahující dolů — pruh sedí **na hraně výřezu**, tedy o pás nad ní.
    @Test("Blok přesahující dolů má pruh na hraně výřezu")
    func aBlockHangingBelowPinsToTheEdge() {
        let block = block(at: 300, height: 400)
        #expect(y(block: block) == 448 - 300 - Self.band)
        // Uvnitř bloku, ne za ním — to je ta vlastnost, kterou drží minimum.
        #expect(y(block: block) < Double(block.height) - Self.band)
        #expect(y(block: block) > 0)
    }

    /// Blok, který přesahuje **nahoru i dolů** (tedy delší než výřez): tentýž člen vyhrává a poloha
    /// pruhu v okně se rolováním nemění.
    @Test("Blok přes celý výřez má pruh na hraně")
    func aBlockTallerThanTheViewportPinsToTheEdge() {
        let block = block(at: -100, height: 700)
        #expect(y(block: block) == 448 + 100 - Self.band)
        #expect(y(block: block) < Double(block.height) - Self.band)
    }

    /// **Jediná heuristika**: pod třemi viditelnými řádky se pruh nepřišpendlí. Tři řádky jsou
    /// 48 bodů, takže se to dá tvrdit na bod — a z obou stran, jinak by test procházel i funkci,
    /// která heuristiku nemá.
    @Test("Pod třemi viditelnými řádky se pruh nepřišpendlí")
    func theBarDoesNotPinUnderThreeVisibleRows() {
        // Přesně tři řádky vidět: špendlí se.
        let three = block(at: 448 - 3 * Self.row, height: 400)
        #expect(y(block: three) == 3 * Self.row - Self.band)
        // O bod méně: zůstane ve svém pásu, tedy mimo obrazovku.
        let less = block(at: 448 - 3 * Self.row + 1, height: 400)
        #expect(y(block: less) == 400 - Self.band)
        // A daleko pod hranou taky — blok, ze kterého vykoukl jeden řádek.
        #expect(y(block: block(at: 448 - Self.row, height: 400)) == 400 - Self.band)
    }

    /// Blok **mimo výřez** — vyjezdil nahoru, nebo ještě nepřijel zdola. Pruh zůstává ve svém pásu
    /// a ptát se na to zvlášť není potřeba: viditelná výška je nula, takže to spadne do heuristiky.
    @Test("Blok mimo výřez má pruh ve svém pásu")
    func aBlockOutsideTheViewportKeepsTheBarInItsBand() {
        #expect(y(block: block(at: -500, height: 200)) == 200 - Self.band)
        #expect(y(block: block(at: 600, height: 200)) == 200 - Self.band)
    }

    /// **Nulová výška řádku znamená nepřišpendlit.** Blok, který se ještě nerozložil, o výšce řádku
    /// neví — a dělit heuristiku nulou by znamenalo přišpendlit pruh do bloku, ze kterého není vidět
    /// nic.
    @Test("Bez známé výšky řádku se pruh nepřišpendlí")
    func anUnlaidBlockKeepsTheBarInItsBand() {
        let block = block(at: 300, height: 400)
        #expect(
            Policy.pinnedScrollerY(ofBlock: block, in: Self.viewport, band: Self.band, rowHeight: 0)
                == 400 - Self.band
        )
    }

    /// **Průjezd celým posunem** — tvrzení, která se u jedné polohy nedají udělat.
    ///
    /// Tři vlastnosti naráz: pruh **nikdy neopustí svůj blok** (tohle je to tvrzení, které padne bez
    /// `min(…)`), v připíchnutém pásmu se hýbe **rychlostí posunu** (spojitá funkce, ne skoky) a na
    /// obou koncích průjezdu končí ve vlastním pásu.
    @Test("Pruh při průjezdu neopustí blok a jde rychlostí posunu")
    func theBarRidesWithinTheBlockAcrossTheWholeSweep() {
        let height = 700.0
        let own = height - Self.band
        var resting = 0
        var firstPinned: Double?
        var lastPinned: Double?
        var previous: Double?
        var previousPinned = false

        // Blok přijíždí zdola (`top` = dolní hrana výřezu) a vyjíždí nahoru za horní hranu.
        for top in stride(from: 448.0, through: -height - 100, by: -1) {
            let value = y(block: block(at: top, height: height))
            #expect(value >= 0, "posun \(top): pruh vyjel nad blok (\(value))")
            #expect(value <= own, "posun \(top): pruh vyjel pod blok (\(value))")

            let isPinned = value < own
            if isPinned {
                if firstPinned == nil { firstPinned = top }
                lastPinned = top
            } else {
                resting += 1
            }
            // V připíchnutém pásmu se pruh hýbe **s posunem**: o krok, ne skokem. Na hranici
            // heuristiky (a jen tam) skok je, a to je zrovna ta chvíle, kdy pruh vidět není.
            if let previous, isPinned, previousPinned {
                #expect(abs(value - previous) == 1, "posun \(top): skok z \(previous) na \(value)")
            }
            previous = value
            previousPinned = isPinned
        }

        // Z druhé strany, ať test netvrdí nic o průjezdu, ve kterém se nic nedělo: obě pásma se
        // musela projet a hranice jsou obě spočitatelné. Připíchne se od chvíle, kdy jsou vidět
        // tři řádky, a naposledy o bod dřív, než pás bloku vjede do výřezu.
        #expect(firstPinned == 448 - 3 * Self.row, "první připíchnutí \(firstPinned ?? .nan)")
        #expect(lastPinned == 448 - Self.band - own + 1, "poslední připíchnutí \(lastPinned ?? .nan)")
        #expect(resting > 0, "vlastní pás \(resting)×")
    }

    /// Na absolutní poloze nezáleží — **posun obou obdélníků o totéž dá tutéž hodnotu**. Je to ta
    /// vlastnost, kvůli které smí kontejner počítat v soustavě své plochy (blok na nule).
    @Test("Poloha je vůči soustavě netečná")
    func theResultIsTranslationInvariant() {
        for shift in [-1_000.0, -13.5, 0, 240, 5_000] {
            let value = y(
                block: block(at: 300 + shift, height: 400),
                viewport: Self.viewport.offsetBy(dx: 0, dy: shift)
            )
            #expect(value == 448 - 300 - Self.band, "posun \(shift)")
        }
    }
}
