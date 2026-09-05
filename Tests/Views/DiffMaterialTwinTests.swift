import Testing

@testable import PRism

/// Že **syntetické dvojče má rozměry své předlohy** (#541).
///
/// Dvojče je měřidlo, ne produkční kód — a právě proto na něm test je. Celý závěr #541 („ostrý diff
/// není zvláštní, je jen větší“) stojí na tom, že se `DiffMaterial.twin(of:)` velikostí předloze
/// **vyrovná**. Kdyby vydávalo diff o desetině řádků, vyšlo by dvojče levněji, z toho by se
/// usoudilo, že cenu drží obsah — a měřidlo by u toho vypadalo zeleně. Učebnicový #478.
///
/// **Nejcennější je tady ten `CRLF` případ.** `twin(of:)` čte cizí diff ze souboru, takže řádky
/// dělí `TextLines` (#292, #295); s `split(separator: "\n")` je `CRLF` diff **jeden** řádek, takže
/// by z něj vyšlo nula hunků a nula řádků obsahu — a `max(…, 1)` uvnitř by z toho udělalo
/// jednořádkový diff místo dvaasedmdesátiřádkového. Ověřeno vložením regrese: s `split`em spadnou
/// obě tvrzení o `CRLF` fixture.
@Suite("Syntetické dvojče drží rozměry předlohy (#541)")
struct DiffMaterialTwinTests {
    /// Kolik má diff souborů, hunků a řádků obsahu. `TextLines`, ne `split` — ze stejného důvodu,
    /// jaký tenhle test hlídá.
    private func shape(of diff: String) -> (files: Int, hunks: Int, content: Int) {
        let lines = TextLines.content(diff)
        return (
            files: lines.count { $0.hasPrefix("diff --git") },
            hunks: lines.count { $0.hasPrefix("@@") },
            content: lines.count { $0.hasPrefix(" ") || $0.hasPrefix("+") || $0.hasPrefix("-") }
        )
    }

    @Test("Dvojče má tolik souborů co předloha a řádků do pěti procent")
    func keepsTheShapeOfAnOrdinaryDiff() throws {
        let source = try Fixture.text("gh/pr-diff-ordinary.diff")
        let origin = shape(of: source)
        let twin = shape(of: DiffMaterial.twin(of: source))

        #expect(twin.files == origin.files)
        // Hunky se dělí rovným dílem na soubor, takže se celočíselným dělením kus ztratí — ale
        // **aspoň jeden na soubor** a nikdy víc, než kolik jich má předloha.
        #expect(twin.hunks >= twin.files)
        #expect(twin.hunks <= origin.hunks)
        // Pět procent je celočíselné dělení `content / (files * hunksPerFile)`, nic víc. Kdyby se
        // dvojče rozešlo s předlohou doopravdy, minulo by o řády, ne o procenta.
        let drift = abs(Double(twin.content - origin.content)) / Double(origin.content)
        #expect(drift < 0.05, "dvojče má \(twin.content) řádků obsahu proti \(origin.content)")
    }

    @Test("Nad CRLF diffem se dvojče nescvrkne na jednu řádku")
    func doesNotCollapseOnCRLF() throws {
        let source = try Fixture.text("gh/pr-diff-crlf.diff")
        let origin = shape(of: source)
        // Fixture musí opravdu být `CRLF`, jinak tenhle test netvrdí nic (#353: doklad je obsah,
        // ne řádka v `.gitattributes`).
        #expect(source.contains("\r\n"))
        #expect(origin.hunks > 1, "fixture přestala mít víc hunků, test tím ztratil smysl")

        let twin = shape(of: DiffMaterial.twin(of: source))
        #expect(twin.files == origin.files)
        #expect(twin.hunks == origin.hunks)
        let drift = abs(Double(twin.content - origin.content)) / Double(origin.content)
        #expect(drift < 0.05, "dvojče má \(twin.content) řádků obsahu proti \(origin.content)")
    }

    @Test("Dvojče je jiný text než předloha — jinak by neablovalo nic")
    func isGeneratedNotCopied() throws {
        let source = try Fixture.text("gh/pr-diff-ordinary.diff")
        #expect(DiffMaterial.twin(of: source) != source)
    }
}
