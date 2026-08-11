import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Prázdný protějšek dvojice tak, jak se **opravdu nakreslí** (#277).
///
/// V modelu se poznat nedá a je to schválně: prázdná strana se do sloupce skládá jako prázdný
/// kontextový řádek (`DiffLine.blank`), aby si strany odpovídaly. Do #277 z toho plynulo, že
/// „na téhle straně řádek není“ a „řádek se nezměnil“ byly v okně **tatáž plocha** — takže se to dá
/// ověřit jedině z bitmapy sloupce.
///
/// Testy jsou tři a druhý je ten cennější: tvrdí, že se kontextový řádek **nešrafuje**. Kdyby se
/// šrafa kreslila přes všechno, první by pořád procházel.
@Suite("Prázdný protějšek v bloku kódu")
@MainActor
struct DiffMissingRowTests {
    /// Sloupec dvojice se třemi řádky: kontext, prázdný protějšek, přidaný řádek.
    ///
    /// Texty jsou jednoznakové schválně — vzorkuje se plocha řádku, takže glyfy kódu by se do
    /// vzorku připletly jako další odstíny. Rámec se nastavuje **až po složení textu**, jako to dělá
    /// SwiftUI (`sizeThatFits`, pak `frame`): bez rámce nemají řádky geometrii.
    private func column(missing: Set<Int>) -> DiffTextView {
        let lines = [
            DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "a"),
            DiffLine.blank,
            DiffLine(kind: .added, oldNumber: nil, newNumber: 3, text: "b"),
        ]
        let view = DiffTextView.pairColumn()
        view.gutterWidth = DiffLineView.contentInset(for: .split)
        view.missingLines = missing
        view.show(
            DiffBlock(lines: lines),
            language: Language(path: "Cart.swift"),
            palette: .darcula,
            signature: "missing-\(missing.sorted())",
            words: { [:] }
        )
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: view.height(ofRows: lines.count))
        return view
    }

    /// Pixely napříč pruhem daného řádku. Vzorkuje se **vodorovně uprostřed řádku** a až za
    /// gutterem a za textem: pruhy šrafy jdou napříč, takže na jedné řádce pixelů je vidět plocha
    /// i pruh, kdežto čísla řádků a kód by do vzorku vnesly barvy písma.
    private func samples(ofRow index: Int, in view: DiffTextView) throws -> [NSColor] {
        let rect = try #require(view.frame(ofLine: index))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        let scaleX = Double(rep.pixelsWide) / view.bounds.width
        let scaleY = Double(rep.pixelsHigh) / view.bounds.height
        let y = Int((rect.midY * scaleY).rounded())
        let from = Int(((view.gutterWidth + 40) * scaleX).rounded())

        return stride(from: from, through: rep.pixelsWide - 2, by: 1).compactMap {
            rep.colorAt(x: $0, y: y)?.usingColorSpace(.sRGB)
        }
    }

    /// Odstíny v řádku od nejčastějšího k nejvzácnějšímu. Z počtu se pozná, jestli je plocha
    /// jednolitá, nebo prošrafovaná; z pořadí, co je plocha a co pruh.
    private func shades(ofRow index: Int, in view: DiffTextView) throws -> [(color: NSColor, count: Int)] {
        var result: [(color: NSColor, count: Int)] = []
        for sample in try samples(ofRow: index, in: view) {
            if let hit = result.firstIndex(where: { close($0.color, sample) }) {
                result[hit].count += 1
            } else {
                result.append((sample, 1))
            }
        }
        return result.sorted { $0.count > $1.count }
    }

    /// Shoda barev na oko — bitmapa je z komponovaného kreslení, takže se hodnoty o zlomek liší,
    /// a hrany šrafy jsou vyhlazené.
    private func close(_ first: NSColor, _ second: NSColor) -> Bool {
        abs(first.redComponent - second.redComponent) < 0.02
            && abs(first.greenComponent - second.greenComponent) < 0.02
            && abs(first.blueComponent - second.blueComponent) < 0.02
            && abs(first.alphaComponent - second.alphaComponent) < 0.02
    }

    /// Barva palety vyhodnocená v tmavém režimu — tedy tak, jak ji sloupec kreslí.
    private func dark(_ color: Color) throws -> NSColor {
        var result: NSColor?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB)
        }
        return try #require(result)
    }

    /// Prázdný protějšek je prošrafovaný, takže v jeho pruhu leží víc než jeden odstín — kdežto
    /// kontextový řádek zůstává jednolitý. Plocha se u něj **nemění**, tak to kreslí návrh.
    @Test("Prázdný protějšek se kreslí jinak než kontext")
    func missingRowIsDrawnDifferentlyThanContext() throws {
        let view = column(missing: [1])
        let context = try shades(ofRow: 0, in: view)
        let missing = try shades(ofRow: 1, in: view)

        #expect(context.count == 1, "Kontextový řádek má \(context.count) odstínů místo jednoho.")
        #expect(missing.count >= 2, "Prázdný protějšek má \(missing.count) odstínů, takže se nešrafuje.")

        let stripe = try dark(Palette.diffMissingStripe)
        let hit = missing.first { close($0.color, stripe) }
        #expect(hit != nil, "V prázdném protějšku není pruh Palette.diffMissingStripe, jen \(missing.map(\.color)).")

        // **Rozestup nese odlišení, ne kontrast** (pruh 5 bodů, mezera 5), takže pruhy musí zabírat
        // kolem poloviny řádku. Jeden tenký pruh by prošel tvrzením o dvou odstínech, ale v okně by
        // se ztratil.
        let covered = Double(hit?.count ?? 0) / Double(missing.reduce(0) { $0 + $1.count })
        #expect(covered > 0.25 && covered < 0.75, "Šrafa zabírá \(covered) řádku místo asi poloviny.")
    }

    /// **Tenhle test tvrdí, že se něco nestalo**: bez `missingLines` se nešrafuje nic. Jinak by
    /// stačila jedna záměna podmínky v `drawRows` a šrafa by se objevila i tam, kde řádek je —
    /// a první test by o tom mlčel.
    @Test("Bez prázdného protějšku se nešrafuje žádný řádek")
    func nothingIsHatchedWithoutMissingLines() throws {
        let view = column(missing: [])
        for index in 0..<3 {
            let shades = try shades(ofRow: index, in: view)
            #expect(shades.count == 1, "Řádek \(index) má \(shades.count) odstínů, takže se do něj kreslí šrafa.")
        }
    }

    /// Šrafa leží **nad** plochou řádku, nenahrazuje ji: plocha díry je v návrhu `transparent`,
    /// takže pod pruhy prosvítá to, co je pod nimi. Tvrdí se to na přidaném řádku, protože tam je ta
    /// plocha vidět — a kdyby ji šrafa překrývala celou, zmizela by zelená.
    @Test("Šrafa se kreslí nad plochou řádku, ne místo ní")
    func hatchDrawsOverTheRowPlane() throws {
        let view = column(missing: [2])
        let added = try shades(ofRow: 2, in: view)
        #expect(added.contains { close($0.color, try! dark(Palette.diffAdded)) }, "Pozadí přidaného řádku zmizelo pod šrafou.")
        #expect(added.contains { close($0.color, try! dark(Palette.diffMissingStripe)) }, "Na řádku není pruh šrafy.")
    }

    /// Které řádky jsou prázdné, ví jedině dvojice — přepis pole na množinu indexů.
    @Test("Prázdné strany dvojice se najdou podle pozice")
    func missingIndicesComeFromThePair() {
        let line = DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "a")
        #expect(DiffPairBlockContainer.missing(in: [nil, line, nil]) == [0, 2])
        #expect(DiffPairBlockContainer.missing(in: [line, line]).isEmpty)
    }
}
