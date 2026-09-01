import AppKit
import Testing

@testable import PRism

/// Zvýraznění hledaného tak, jak se doopravdy nakreslí (#152).
///
/// Model se testuje v `DiffSearchTests`; tady se ověřuje to, co v modelu vidět není: že se
/// zvýraznění skládá **nad** obarvením syntaxe i nad word-level vrstvou, že sedí na správných
/// znacích a že **dotaz je v klíči sazby** — bez toho by se po jeho změně přesázení přeskočilo
/// a v okně by zůstalo svítit slovo z minula.
@Suite("Zvýraznění hledaného v textu bloku")
@MainActor
struct DiffSearchHighlightTests {
    private func query(_ text: String, caseSensitive: Bool = false) -> DiffSearchQuery {
        DiffSearchQuery(text: text, isCaseSensitive: caseSensitive)
    }

    private func highlight(_ text: String, current: DiffSearchHit? = nil) -> DiffSearchHighlight {
        DiffSearchHighlight(query: query(text), current: current)
    }

    private func show(
        _ lines: [DiffLine],
        in view: DiffTextView,
        search: DiffSearchHighlight = .none
    ) {
        view.show(
            DiffBlock(lines: lines),
            style: DiffBlockStyle(
                language: Language(path: "Cart.swift"),
                colorScheme: .light,
                search: search
            ),
            words: { WordDiff.spans(in: lines) }
        )
    }

    /// Kusy textu s podkladem a barva, kterou mají — tedy to, co v okně svítí.
    private func backgrounds(in view: DiffTextView) -> [(text: String, color: NSColor)] {
        guard let storage = view.textStorage else { return [] }
        var result: [(String, NSColor)] = []
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            result.append((storage.attributedSubstring(from: range).string, color))
        }
        return result
    }

    private func context(_ text: String, line: Int = 1) -> DiffLine {
        DiffLine(kind: .context, oldNumber: line, newNumber: line, text: text)
    }

    private func removed(_ text: String) -> DiffLine {
        DiffLine(kind: .removed, oldNumber: 1, newNumber: nil, text: text)
    }

    private func added(_ text: String) -> DiffLine {
        DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: text)
    }

    private var hitColor: NSColor { NSColor(Palette.searchHit) }
    private var currentColor: NSColor { NSColor(Palette.searchHitCurrent) }

    /// Svítí **všechny** výskyty na řádku, i ten, který se od dotazu liší velikostí — hledání ji
    /// nerozlišuje, dokud se o to neřekne kapslí `Aa`.
    @Test("Svítí jen nalezené kusy")
    func highlightsTheMatches() {
        let view = DiffTextView.wrappingBlock()
        show([context("let timeout = FLUSH_TIMEOUT")], in: view, search: highlight("TIMEOUT"))
        #expect(backgrounds(in: view).map(\.text) == ["timeout", "TIMEOUT"])

        let strict = DiffTextView.wrappingBlock()
        show(
            [context("let timeout = FLUSH_TIMEOUT")],
            in: strict,
            search: DiffSearchHighlight(query: query("TIMEOUT", caseSensitive: true), current: nil)
        )
        #expect(backgrounds(in: strict).map(\.text) == ["TIMEOUT"])
    }

    @Test("Bez dotazu nesvítí nic")
    func noQueryNoHighlight() {
        let view = DiffTextView.wrappingBlock()
        show([context("let timeout = FLUSH_TIMEOUT")], in: view, search: .none)
        #expect(backgrounds(in: view).isEmpty)
    }

    /// Zvýraznění **nemění text** — tentýž invariant jako u obarvení syntaxe a word-level vrstvy.
    @Test("Zvýraznění nemění text")
    func leavesTheTextAlone() {
        let view = DiffTextView.wrappingBlock()
        let lines = [context("$this->flush();"), context("// FLUSH_TIMEOUT", line: 2)]
        show(lines, in: view, search: highlight("FLUSH"))
        #expect(view.textStorage?.string == lines.map(\.text).joined(separator: "\n"))
    }

    /// Emoji je jeden `Character` a **dva** kódy v UTF-16 — a v nich měří `NSAttributedString`.
    /// S `count` místo `utf16.count` by podklad sedl o kus doprava (tatáž třída chyby jako #275).
    @Test("Podklad sedí na znak i za emoji")
    func landsOnTheRightCharactersAfterEmoji() {
        let view = DiffTextView.wrappingBlock()
        show([context("// 🚀 flush(FLUSH_TIMEOUT)")], in: view, search: highlight("FLUSH_TIMEOUT"))
        #expect(backgrounds(in: view).map(\.text) == ["FLUSH_TIMEOUT"])
    }

    /// Aktuální výskyt má **sytější podklad**, ostatní tlumený. Rozlišuje je barva, ne obrys —
    /// obrys by v `NSAttributedString` neměl čím vzniknout.
    @Test("Aktuální výskyt má jinou barvu než ostatní")
    func currentHitStandsOut() {
        let view = DiffTextView.wrappingBlock()
        let line = context("$key = $key . $key;")
        let current = DiffSearchHit(path: "Cart.swift", line: line, occurrence: 1)
        show([line], in: view, search: highlight("$key", current: current))

        let drawn = backgrounds(in: view)
        #expect(drawn.map(\.text) == ["$key", "$key", "$key"])
        #expect(drawn.map { $0.color == currentColor } == [false, true, false])
        #expect(drawn.filter { $0.color == hitColor }.count == 2)
    }

    /// **Hledání vyhrává nad word-level vrstvou** (#153), a je to zapsané rozhodnutí: je to jediná
    /// z těch vrstev, kterou si člověk zapnul sám. Ověřuje se to nad dvojicí, kde se výskyt trefí
    /// zrovna do změněného slova.
    @Test("Nad word-level vrstvou vyhrává hledání")
    func searchWinsOverTheWordLayer() {
        let view = DiffTextView.pairColumn()
        let lines = [
            removed("$this->client->put($key, self::FLUSH_TIMEOUT);"),
            added("$this->client->putMultiple($key, self::FLUSH_TIMEOUT_MS);"),
        ]
        show(lines, in: view, search: highlight("FLUSH_TIMEOUT"))

        let drawn = backgrounds(in: view)
        // Word-level vrstva svítí dál (`putMultiple`, `_MS`), ale na obou `FLUSH_TIMEOUT` leží
        // podklad hledání.
        #expect(drawn.filter { $0.color == hitColor }.map(\.text) == ["FLUSH_TIMEOUT", "FLUSH_TIMEOUT"])
        #expect(drawn.contains { $0.color == NSColor(Palette.diffAddedWord) })
    }

    /// Prázdná strana dvojice se do sloupce skládá jako **prázdný** řádek, takže na ní nemá co
    /// svítit. Kdyby ano, byl by to podklad nad kódem, který na té straně není.
    @Test("Prázdná strana dvojice nesvítí")
    func blankSideStaysDark() {
        let view = DiffTextView.pairColumn()
        show([DiffLine.blank, added("const FLUSH_TIMEOUT = 5;")], in: view, search: highlight("FLUSH"))
        #expect(backgrounds(in: view).filter { $0.color == hitColor }.count == 1)
    }

    // MARK: - Klíč sazby

    /// **Tohle je ten test, kvůli kterému je dotaz v `DiffBlockStyle`.** `show(…)` se z nezměněného
    /// obsahu vrátí hned (jinak by přesázení rušilo rozdělaný výběr při každém přejezdu myší),
    /// takže bez dotazu v klíči by změna hledaného slova sazbu **přeskočila** — a v okně by zůstalo
    /// zvýraznění toho předchozího. Potichu, protože text ani jazyk se nezměnily.
    @Test("Změna dotazu přesází blok")
    func changingTheQueryRetypesets() {
        let view = DiffTextView.wrappingBlock()
        let lines = [context("let timeout = FLUSH_TIMEOUT")]

        show(lines, in: view, search: highlight("FLUSH"))
        let after = view.typesettings
        #expect(backgrounds(in: view).map(\.text) == ["FLUSH"])

        // Tentýž obsah, jiný dotaz.
        show(lines, in: view, search: highlight("timeout"))
        #expect(view.typesettings == after + 1)
        #expect(backgrounds(in: view).map(\.text) == ["timeout", "TIMEOUT"])
    }

    @Test("Změna aktuálního výskytu přesází blok")
    func changingTheCurrentHitRetypesets() {
        let view = DiffTextView.wrappingBlock()
        let line = context("$key = $key;")
        show([line], in: view, search: highlight("$key"))
        let after = view.typesettings

        let current = DiffSearchHit(path: "Cart.swift", line: line, occurrence: 0)
        show([line], in: view, search: highlight("$key", current: current))
        #expect(view.typesettings == after + 1)
        #expect(backgrounds(in: view).first?.color == currentColor)
    }

    /// A obráceně: **nezměněný dotaz sazbu neopakuje.** Kdyby ano, ztratil by se výběr při každém
    /// přejezdu myší — přesně to, co #157 opravovalo klíčem obsahu.
    @Test("Nezměněný dotaz sazbu neopakuje")
    func sameQueryDoesNotRetypeset() {
        let view = DiffTextView.wrappingBlock()
        let lines = [context("let timeout = FLUSH_TIMEOUT")]
        show(lines, in: view, search: highlight("TIMEOUT"))
        let after = view.typesettings
        show(lines, in: view, search: highlight("TIMEOUT"))
        #expect(view.typesettings == after)
    }

    /// Zavřený pruh nezvýrazňuje nic — a rozhoduje o tom **stav**, ne volající: `⎋` jenom zavře
    /// a zvýraznění musí zhasnout bez toho, aby se dotaz mazal.
    @Test("Zavřený pruh nezvýrazňuje, dotaz si ale drží")
    func closedBarDoesNotHighlight() {
        let state = DiffSearchState()
        state.query = "FLUSH_TIMEOUT"
        state.isOpen = true
        #expect(state.drawnQuery.isActive)

        state.isOpen = false
        #expect(!state.drawnQuery.isActive)
        #expect(state.query == "FLUSH_TIMEOUT")
        #expect(Policy.searchHighlight(query: state.drawnQuery, current: nil, in: "a.php") == .none)
    }
}
