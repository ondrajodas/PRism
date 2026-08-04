import CoreGraphics
import Testing

@testable import PRism

/// Rámečky řádků, ze kterých tažení pozná, přes který řádek je myš (#110).
///
/// Testuje se to, protože je to schránka **mimo observable stav** a dvakrát se u ní stala tatáž
/// chyba: nejdřív se rámečky nechávaly ležet a po přepnutí pohledu se pletly dvě sady, pak se
/// zvenčí vyprazdňovaly — a to je horší, protože `onGeometryChange` se spustí jen při **změně**
/// geometrie, takže po vyprázdnění už nic nenahlásí a tažení nemá co najít.
@Suite("Rámečky řádků pro tažení")
@MainActor
struct DiffRowFramesTests {
    private func anchor(_ line: Int, _ side: DiffSide = .right) -> DraftAnchor {
        DraftAnchor(line: line, side: side)
    }

    private func rect(_ y: Double, height: Double = 15, x: Double = 0, width: Double = 1000) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    @Test("Bod uvnitř rámečku najde svůj řádek")
    func findsTheLineUnderThePoint() {
        let frames = DiffRowFrames()
        frames.note(rect(0), id: "a", anchor: anchor(1))
        frames.note(rect(15), id: "b", anchor: anchor(2))

        #expect(frames.anchor(at: CGPoint(x: 500, y: 20), on: nil) == anchor(2))
    }

    @Test("Bod mimo všechny rámečky nenajde nic")
    func findsNothingOutside() {
        let frames = DiffRowFrames()
        frames.note(rect(0), id: "a", anchor: anchor(1))

        #expect(frames.anchor(at: CGPoint(x: 500, y: 900), on: nil) == nil)
    }

    /// Řádek, na který se komentovat nedá (meta, mimo hunky), nesmí v krabici zůstat ležet —
    /// po rozbalení kontextu by tažení skončilo na kotvě, kterou GitHub odmítne.
    @Test("Řádek bez kotvy se z krabice smaže")
    func removesALineWithoutAnAnchor() {
        let frames = DiffRowFrames()
        frames.note(rect(0), id: "a", anchor: anchor(1))

        frames.note(rect(0), id: "a", anchor: nil)

        #expect(frames.anchor(at: CGPoint(x: 500, y: 5), on: nil) == nil)
    }

    /// **Tohle je ta chyba z #110:** po přepnutí pohledu se rámečky pletly. Dva živé řádky se
    /// nepřekrývají, takže překryv znamená zastaralý záznam — a ten musí jít pryč, jinak vyhraje
    /// ten, na který hledání narazí první, a tažení vybírá řádky vedle.
    @Test("Nový rámeček vyhodí ten, se kterým se překrývá")
    func evictsAnOverlappingFrame() {
        let frames = DiffRowFrames()
        // Unified řádek přes celou šířku…
        frames.note(rect(0, width: 1000), id: "unified", anchor: anchor(1))

        // …a po přepnutí pohledu buňka dvojice na půlce, na tomtéž místě.
        frames.note(rect(0, x: 0, width: 500), id: "split|LEFT", anchor: anchor(9, .left))

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: nil) == anchor(9, .left))
        // A ten starý zmizel i tam, kde nová buňka nesahá — jinak by na pravé půlce zůstal.
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: nil) == nil)
    }

    @Test("Rámečky, které se nepřekrývají, vedle sebe zůstanou")
    func keepsFramesThatDoNotOverlap() {
        let frames = DiffRowFrames()
        frames.note(rect(0, x: 0, width: 500), id: "left", anchor: anchor(1, .left))
        frames.note(rect(0, x: 501, width: 499), id: "right", anchor: anchor(1))

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: nil) == anchor(1, .left))
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: nil) == anchor(1))
    }

    /// Ve split pohledu se hledá **jen ve svém sloupci**: tažení, které začalo vpravo, nemá
    /// skočit vlevo, když myš zajede vedle nebo když levá protistrana chybí.
    @Test("Hledání se dá omezit na stranu")
    func searchesOnlyOneSide() {
        let frames = DiffRowFrames()
        frames.note(rect(0, x: 0, width: 500), id: "left", anchor: anchor(1, .left))
        frames.note(rect(0, x: 501, width: 499), id: "right", anchor: anchor(1))

        #expect(frames.anchor(at: CGPoint(x: 100, y: 5), on: .right) == nil)
        #expect(frames.anchor(at: CGPoint(x: 900, y: 5), on: .right) == anchor(1))
    }
}
