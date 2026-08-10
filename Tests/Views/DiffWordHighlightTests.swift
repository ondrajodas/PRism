import AppKit
import Testing

@testable import PRism

/// Word-level zvýraznění tak, jak se opravdu nakreslí (#153) — v textu bloku, ne jen v modelu.
///
/// Tady se ověřuje to, co se v modelu ověřit nedá: že se zvýraznění skládá **nad** obarvením
/// syntaxe a že nikde po cestě nezůstane viset u textu řádku.
@Suite("Zvýraznění v textu bloku")
@MainActor
struct DiffWordHighlightTests {
    private func show(_ lines: [DiffLine], signature: String, in view: DiffTextView) {
        view.show(
            DiffBlock(lines: lines),
            language: Language(path: "Cart.swift"),
            palette: .intelliJLight,
            signature: signature,
            words: { WordDiff.spans(in: lines) }
        )
    }

    /// Kusy textu, které mají pozadí navíc — tedy to, co v okně svítí.
    private func highlighted(in view: DiffTextView) -> [String] {
        guard let storage = view.textStorage else { return [] }
        var result: [String] = []
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            result.append(storage.attributedSubstring(from: range).string)
        }
        return result
    }

    private func removed(_ text: String) -> DiffLine {
        DiffLine(kind: .removed, oldNumber: 1, newNumber: nil, text: text)
    }

    private func added(_ text: String) -> DiffLine {
        DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: text)
    }

    @Test("Svítí jen přepsaná část, na obou stranách")
    func highlightsTheRewrittenPart() {
        let view = DiffTextView.pairColumn()
        show([removed("let total = price * amount"), added("let total = price * count")], signature: "a", in: view)
        #expect(highlighted(in: view) == ["amount", "count"])
    }

    /// Tentýž invariant jako u obarvení syntaxe: zvýraznění nesmí sáhnout na text.
    @Test("Zvýraznění nemění text")
    func leavesTheTextAlone() {
        let view = DiffTextView.pairColumn()
        let lines = [removed("let total = price * amount"), added("let total = price * count")]
        show(lines, signature: "a", in: view)
        #expect(view.textStorage?.string == lines.map(\.text).joined(separator: "\n"))
    }

    /// **Tohle je ten test, kvůli kterému zvýraznění nesmí do `SyntaxRunCache`.**
    ///
    /// Cache je klíčovaná `(text řádku, jazyk)`, jenže word-level zvýraznění závisí na
    /// **protějšku** — tentýž přidaný řádek proti jinému odebranému svítí jinde. Kdyby se
    /// přimíchalo mezi `SyntaxRun`y, druhé vykreslení by dostalo zvýraznění patřící cizí dvojici,
    /// a to potichu: obojí zvlášť by dál procházelo.
    @Test("Tentýž řádek proti jinému protějšku svítí jinde")
    func dependsOnTheCounterpart() {
        let view = DiffTextView.pairColumn()
        let line = added("let total = price * count")

        show([removed("let total = price * amount"), line], signature: "a", in: view)
        #expect(highlighted(in: view) == ["amount", "count"])

        show([removed("let subtotal = price * count"), line], signature: "b", in: view)
        #expect(highlighted(in: view) == ["subtotal", "total"])
    }

    /// Dvě vrstvy nad jedním textem: písmo patří syntaxi, pozadí word-diffu. Kdyby si braly totéž,
    /// jedna by tu druhou přebila.
    @Test("Obarvení syntaxe zůstává i pod zvýrazněním")
    func keepsSyntaxColorsUnderTheHighlight() throws {
        let view = DiffTextView.pairColumn()
        show([removed("let amount = 1"), added("let count = 1")], signature: "a", in: view)
        let storage = try #require(view.textStorage)

        // `let` je klíčové slovo, takže má barvu písma z palety — a leží mimo zvýrazněný kus.
        let keyword = storage.attributes(at: 0, effectiveRange: nil)
        #expect(keyword[.foregroundColor] as? NSColor == NSColor(SyntaxPalette.intelliJLight.keyword))
        #expect(keyword[.backgroundColor] == nil)

        let changed = try #require(storage.string.range(of: "amount"))
        let attributes = storage.attributes(at: storage.string.distance(from: storage.string.startIndex, to: changed.lowerBound), effectiveRange: nil)
        #expect(attributes[.backgroundColor] as? NSColor == DiffTextView.wordBackground(of: .removed))
    }

    /// Kontextový řádek se nezvýrazňuje, i kdyby mu rozsahy někdo podstrčil: co se nezměnilo,
    /// nemá co svítit.
    @Test("Kontextový řádek nesvítí")
    func leavesContextAlone() {
        let view = DiffTextView.pairColumn()
        let context = DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "let total = price * count")
        view.show(
            DiffBlock(lines: [context]),
            language: Language(path: "Cart.swift"),
            palette: .intelliJLight,
            signature: "a",
            words: { [0: [context.text.startIndex..<context.text.endIndex]] }
        )
        #expect(highlighted(in: view).isEmpty)
    }
}
