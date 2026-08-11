import CoreGraphics
import Testing

@testable import PRism

/// Rámečky řádků, ze kterých tažení pozná, přes který řádek je myš (#110).
///
/// Testuje se to, protože je to schránka **mimo observable stav** a dvakrát se u ní stala tatáž
/// chyba: nejdřív se rámečky nechávaly ležet a po přepnutí pohledu se pletly dvě sady, pak se
/// zvenčí vyprazdňovaly — a to je horší, protože se hlásí jen při **změně** geometrie, takže po
/// vyprázdnění už nic nenahlásí a tažení nemá co najít.
///
/// Od #252 se hlásí **po blocích, ne po řádcích**, takže se tady kontroluje i to, že blok
/// vyklidí svou plochu a **nevyhodí přitom sám sebe**.
@Suite("Rámečky řádků pro tažení")
@MainActor
struct DiffRowFramesTests {
    private func anchor(_ line: Int, _ side: DiffSide = .right) -> DraftAnchor {
        DraftAnchor(line: line, side: side)
    }

    private func rect(_ y: Double, height: Double = 15, x: Double = 0, width: Double = 1000) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    private func entry(_ id: String, _ rect: CGRect, _ anchor: DraftAnchor) -> DiffRowFrames.Entry {
        DiffRowFrames.Entry(id: id, rect: rect, anchor: anchor)
    }

    @Test("Bod uvnitř rámečku najde svůj řádek")
    func findsTheLineUnderThePoint() {
        let frames = DiffRowFrames()
        frames.note(
            [entry("a", rect(0), anchor(1)), entry("b", rect(15), anchor(2))],
            covering: rect(0, height: 30)
        )

        #expect(frames.anchor(at: CGPoint(x: 500, y: 20), on: nil) == anchor(2))
    }

    @Test("Bod mimo všechny rámečky nenajde nic")
    func findsNothingOutside() {
        let frames = DiffRowFrames()
        frames.note([entry("a", rect(0), anchor(1))], covering: rect(0))

        #expect(frames.anchor(at: CGPoint(x: 500, y: 900), on: nil) == nil)
    }

    /// Řádek, na který se komentovat nedá (meta, mimo hunky), se nehlásí — a tím z krabice
    /// vypadne. Kdyby v ní zůstal ležet, tažení by po rozbalení kontextu skončilo na kotvě,
    /// kterou GitHub odmítne.
    @Test("Řádek bez kotvy se z krabice smaže")
    func removesALineWithoutAnAnchor() {
        let frames = DiffRowFrames()
        frames.note([entry("a", rect(0), anchor(1))], covering: rect(0))

        frames.note([], covering: rect(0))

        #expect(frames.anchor(at: CGPoint(x: 500, y: 5), on: nil) == nil)
    }

    /// **Tohle je ta chyba z #110:** po přepnutí pohledu se rámečky pletly. Dva živé řádky se
    /// nepřekrývají, takže záznam v ploše bloku, který blok sám nehlásí, je zastaralý — a musí jít
    /// pryč, jinak vyhraje ten, na který hledání narazí první, a tažení vybírá řádky vedle.
    @Test("Nový blok vyklidí svou plochu od zastaralých rámečků")
    func evictsAnOverlappingFrame() {
        let frames = DiffRowFrames()
        // Unified řádek přes celou šířku…
        frames.note([entry("unified", rect(0, width: 1000), anchor(1))], covering: rect(0, width: 1000))

        // …a po přepnutí pohledu buňka dvojice na půlce, na tomtéž místě.
        frames.note(
            [entry("split|LEFT", rect(0, x: 0, width: 500), anchor(9, .left))],
            covering: rect(0, width: 1000)
        )

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: nil) == anchor(9, .left))
        // A ten starý zmizel i tam, kde nová buňka nesahá — jinak by na pravé půlce zůstal.
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: nil) == nil)
    }

    /// Vyklizení plochy nesmí sebrat rámečky **toho samého bloku** — ty leží uvnitř vyklízené
    /// plochy všechny, protože se hlásí naráz. Drží to **pořadí**: napřed úklid, potom zápis.
    /// Vyzkoušeno vložením regrese (úklid za zápisem): z bloku zbude poslední řádek a test spadne.
    @Test("Blok si vyklizením plochy nesebere vlastní řádky")
    func keepsItsOwnRows() {
        let frames = DiffRowFrames()
        let rows = (0..<5).map { entry("l\($0)", rect(Double($0) * 15), anchor($0 + 1)) }

        frames.note(rows, covering: rect(0, height: 75))

        for index in 0..<5 {
            #expect(frames.anchor(at: CGPoint(x: 500, y: Double(index) * 15 + 5), on: nil) == anchor(index + 1))
        }
    }

    /// Blok, který se ještě nerozložil, hlásí nulový rámeček. Vyklidit podle něj by znamenalo
    /// sebrat cizí záznamy na souřadnici nula — tedy první řádky diffu.
    @Test("Nulová plocha nevyklidí nic")
    func ignoresAnEmptyArea() {
        let frames = DiffRowFrames()
        frames.note([entry("a", rect(0), anchor(1))], covering: rect(0))

        frames.note([], covering: .zero)

        #expect(frames.anchor(at: CGPoint(x: 500, y: 5), on: nil) == anchor(1))
    }

    @Test("Rámečky, které se nepřekrývají, vedle sebe zůstanou")
    func keepsFramesThatDoNotOverlap() {
        let frames = DiffRowFrames()
        frames.note(
            [
                entry("left", rect(0, x: 0, width: 500), anchor(1, .left)),
                entry("right", rect(0, x: 501, width: 499), anchor(1))
            ],
            covering: rect(0, width: 1000)
        )

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: nil) == anchor(1, .left))
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: nil) == anchor(1))
    }

    /// Ve split pohledu se hledá **jen ve svém sloupci**: tažení, které začalo vpravo, nemá
    /// skočit vlevo, když myš zajede vedle nebo když levá protistrana chybí.
    @Test("Hledání se dá omezit na stranu")
    func searchesOnlyOneSide() {
        let frames = DiffRowFrames()
        frames.note(
            [
                entry("left", rect(0, x: 0, width: 500), anchor(1, .left)),
                entry("right", rect(0, x: 501, width: 499), anchor(1))
            ],
            covering: rect(0, width: 1000)
        )

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: .right) == nil)
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: .right) == anchor(1))
    }
}
