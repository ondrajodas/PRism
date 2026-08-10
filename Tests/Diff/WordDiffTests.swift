import Foundation
import Testing

@testable import PRism

/// Word-level rozdíl uvnitř přepsaného řádku (#153) — čistá funkce, testuje se výčtem.
///
/// Zvýrazněné kusy se v testech píšou v hranatých závorkách (`mark`), protože o to jde: kde
/// **na řádku** to svítí. Každé takové porovnání zároveň ověřuje invariant „zvýraznění nemění
/// text“ — bez závorek musí vyjít původní řádek, stejně jako u obarvení syntaxe platí, že
/// spojení run dá původní řádek.
@Suite("Word-level diff")
struct WordDiffTests {
    // MARK: - Pomůcky

    /// Řádek se zvýrazněnými kusy v závorkách. Cestou ověří, že rozsahy jdou po sobě,
    /// nepřekrývají se a že se text zvýrazněním nezměnil.
    private func mark(_ line: String, _ spans: [Range<String.Index>]) -> String {
        var result = ""
        var last = line.startIndex
        for span in spans {
            #expect(span.lowerBound >= last, "rozsahy musí jít po sobě a nepřekrývat se")
            result += line[last..<span.lowerBound]
            result += "[" + line[span] + "]"
            last = span.upperBound
        }
        result += line[last...]
        #expect(result.filter { $0 != "[" && $0 != "]" } == line.filter { $0 != "[" && $0 != "]" })
        return result
    }

    /// Obě strany dvojice se zvýrazněním, nebo `nil`, když se dvojice zvýrazňovat nemá.
    private func change(_ old: String, _ new: String) -> (old: String, new: String)? {
        guard let change = WordDiff.change(from: old, to: new) else { return nil }
        return (mark(old, change.old), mark(new, change.new))
    }

    private func line(_ kind: DiffLine.Kind, _ text: String) -> DiffLine {
        DiffLine(kind: kind, oldNumber: kind == .added ? nil : 1, newNumber: kind == .removed ? nil : 1, text: text)
    }

    /// Zvýraznění v úseku řádků, vypsané jako `index: řádek se závorkami`.
    private func marked(_ lines: [DiffLine], _ spans: WordDiff.Spans) -> [String] {
        spans.keys.sorted().map { "\($0): \(mark(lines[$0].text, spans[$0] ?? []))" }
    }

    // MARK: - Jedna dvojice

    @Test("Svítí jen přepsané slovo")
    func marksTheRewrittenWord() {
        let result = change("let total = price * amount", "let total = price * count")
        #expect(result?.old == "let total = price * [amount]")
        #expect(result?.new == "let total = price * [count]")
    }

    @Test("Vložené slovo svítí jen na nové straně")
    func marksAnInsertionOnTheNewSideOnly() {
        let result = change("foo(a, b)", "foo(a, x, b)")
        #expect(result?.old == "foo(a, b)")
        #expect(result?.new == "foo(a, [x, ]b)")
    }

    @Test("Smazané slovo svítí jen na staré straně")
    func marksADeletionOnTheOldSideOnly() {
        let result = change("foo(a, x, b)", "foo(a, b)")
        #expect(result?.old == "foo(a, [x, ]b)")
        #expect(result?.new == "foo(a, b)")
    }

    /// Operátor drží pohromadě: po znacích by se z `==` proti `!=` spárovalo první `=` a svítil by
    /// jeden znak ze dvou.
    @Test("Změna na dvou místech dá dva úseky")
    func marksTwoPlacesSeparately() {
        let result = change("if a == b && c == d", "if a != b && c != d")
        #expect(result?.old == "if a [==] b && c [==] d")
        #expect(result?.new == "if a [!=] b && c [!=] d")
    }

    /// Po tokenech, ne po znacích: `amount` → `account` nesmí svítit po písmenech, protože
    /// z přepsaného jména by zbyla skvrna se společnými `a`, `c` a `t` uprostřed.
    @Test("Přepsané jméno svítí celé, ne po písmenech")
    func marksAWholeIdentifier() {
        let result = change("let amount = 1", "let account = 1")
        #expect(result?.old == "let [amount] = 1")
        #expect(result?.new == "let [account] = 1")
    }

    @Test("Změna odsazení svítí na odsazení")
    func marksAnIndentationChange() {
        let result = change("  return x", "        return x")
        #expect(result?.old == "[  ]return x")
        #expect(result?.new == "[        ]return x")
    }

    // MARK: - Kdy se nezvýrazňuje

    @Test("Shodné řádky nemají co zvýraznit")
    func ignoresIdenticalLines() {
        #expect(WordDiff.change(from: "let x = 1", to: "let x = 1") == nil)
    }

    @Test("Prázdná strana se nezvýrazňuje")
    func ignoresAnEmptySide() {
        #expect(WordDiff.change(from: "", to: "let x = 1") == nil)
        #expect(WordDiff.change(from: "let x = 1", to: "") == nil)
    }

    /// Dvojice, ve které se řádky vůbec neshodují, je smazání a přidání, ne přepsání. Bez tohohle
    /// by na dvou nesouvisejících řádcích svítily závorky a mezery, které se v kódu potkají vždycky.
    @Test("Nepodobná dvojice zůstane obarvená jako dosud")
    func leavesAnUnrelatedPairAlone() {
        #expect(WordDiff.change(from: "folding.toggle(file)", to: "file: file,") == nil)
        #expect(WordDiff.change(from: "var rewroteHistory: Bool { !forcePushes.isEmpty }", to: "// se pozná z toho druhého") == nil)
    }

    /// Krátká, ale skutečná přepsání práh přežít musí — jinak by zvýraznění chybělo zrovna tam,
    /// kde je řádek nejkratší a rozdíl nejhůř vidět.
    @Test("Podobná dvojice práh přežije")
    func keepsASmallRewrite() {
        #expect(change(".font(.caption2)", ".font(.system(size: 10.5))")?.new == ".font(.[system(size: 10.5)])")
    }

    @Test("Práh se počítá z neprázdných znaků")
    func ignoresIndentationInTheSimilarity() {
        // Společné je jen odsazení; kdyby se počítalo, vyšla by tahle dvojice jako přepsání.
        #expect(WordDiff.change(from: "        let total = price * amount", to: "        return") == nil)
    }

    // MARK: - Meze

    /// Cena je součin počtu tokenů, takže dva obří řádky se po tokenech neporovnávají. Zvýrazní se
    /// celý rozdílný střed — horší zvýraznění, ne chybějící, a hlavně ohraničená práce.
    @Test("Obří dvojice se zvýrazní celá, ne po tokenech")
    func boundsTheWorkOnHugeLines() throws {
        // Společný začátek a konec drží podobnost nad prahem, ale středy jsou natolik dlouhé, že
        // se přes strop nedostanou (250 × 250 tokenů).
        let common = String(repeating: "word ", count: 300)
        let old = common + (0..<250).map { "a\($0)" }.joined(separator: " ") + " " + common
        let new = common + (0..<250).map { "b\($0)" }.joined(separator: " ") + " " + common
        let change = try #require(WordDiff.change(from: old, to: new))
        // Střed je jeden souvislý úsek, ne pět set kousků.
        #expect(change.old.count == 1)
        #expect(change.new.count == 1)
        #expect(old[change.old[0]].hasPrefix("a0 a1"))
    }

    // MARK: - Párování v pohledu pod sebou

    @Test("Blok odebraných se páruje s blokem přidaných jeden na jednoho")
    func pairsBlocksOneToOne() {
        let lines = [
            line(.context, "func total() {"),
            line(.removed, "    let a = 1"),
            line(.removed, "    let b = 2"),
            line(.added, "    let a = 10"),
            line(.added, "    let b = 20"),
        ]
        #expect(marked(lines, WordDiff.spans(in: lines)) == [
            "1:     let a = [1]",
            "2:     let b = [2]",
            "3:     let a = [10]",
            "4:     let b = [20]",
        ])
    }

    /// `+` po `-` je přepsání téhož místa, ale `-` po `+` už je další skupina — tatáž věta jako
    /// u `DiffRow.paired(_:)`. Napříč skupinami by se starý obsah porovnal s novým, který s ním
    /// nesouvisí.
    /// Skupiny musí být **nestejně velké**, jinak se chybějící pravidlo nepozná: zip po pořadí
    /// vyjde u dvou stejných skupin stejně jako u jedné dlouhé. Tady zbude vlevo přebytek, takže
    /// bez uzavírání by se `let c = 3` porovnalo s `let b = 20` — tedy starý obsah s novým, který
    /// s ním nesouvisí.
    @Test("Přidaný řádek skupinu uzavírá")
    func closesTheGroupOnAnAddedLine() {
        let lines = [
            line(.removed, "let a = 1"),
            line(.removed, "let b = 2"),
            line(.added, "let a = 10"),
            line(.removed, "let c = 3"),
            line(.added, "let c = 30"),
        ]
        #expect(marked(lines, WordDiff.spans(in: lines)) == [
            "0: let a = [1]",
            "2: let a = [10]",
            "3: let c = [3]",
            "4: let c = [30]",
        ])
    }

    @Test("Kontext i poznámka skupinu uzavírají")
    func closesTheGroupOnContext() {
        let lines = [
            line(.removed, "let a = 1"),
            line(.context, "// mezi tím"),
            line(.added, "let a = 2"),
        ]
        #expect(WordDiff.spans(in: lines).isEmpty)
    }

    @Test("Přebytek na jedné straně zůstane bez protějšku")
    func leavesTheSurplusAlone() {
        let lines = [
            line(.removed, "let a = 1"),
            line(.added, "let a = 2"),
            line(.added, "let c = 3"),
        ]
        let spans = WordDiff.spans(in: lines)
        #expect(spans[2] == nil)
        #expect(marked(lines, spans) == ["0: let a = [1]", "1: let a = [2]"])
    }

    // MARK: - Párování v pohledu vedle sebe

    @Test("Dvojice se porovná podle pozice ve sloupcích")
    func pairsColumnsByPosition() {
        let left: [DiffLine?] = [line(.context, "func total() {"), line(.removed, "let a = 1"), nil]
        let right: [DiffLine?] = [line(.context, "func total() {"), line(.added, "let a = 2"), line(.added, "let c = 3")]
        let spans = WordDiff.spans(left: left, right: right)
        #expect(spans.left.keys.sorted() == [1])
        #expect(spans.right.keys.sorted() == [1])
        #expect(mark(left[1]?.text ?? "", spans.left[1] ?? []) == "let a = [1]")
        #expect(mark(right[1]?.text ?? "", spans.right[1] ?? []) == "let a = [2]")
    }

    @Test("Kontextová dvojice se nezvýrazňuje")
    func leavesContextPairsAlone() {
        let same = line(.context, "func total() {")
        let spans = WordDiff.spans(left: [same], right: [same])
        #expect(spans.left.isEmpty)
        #expect(spans.right.isEmpty)
    }

    // MARK: - Oba pohledy musí říkat totéž

    /// **Dvě párovací pravidla se nesmí rozejít.** V pohledu vedle sebe páruje `DiffRow.paired(_:)`,
    /// pod sebou si dvojice hledá `WordDiff.spans(in:)` sám — a kdyby se ta pravidla lišila, svítilo
    /// by v každém pohledu něco jiného a nikdo by se to nedozvěděl. Testuje se na skutečném diffu,
    /// ne na vymyšleném.
    @Test("V obou pohledech svítí totéž")
    func agreesAcrossLayouts() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        #expect(!diff.files.isEmpty)

        for file in diff.files {
            let lines = DiffRow.rows(of: file).compactMap { row -> DiffLine? in
                guard case .line(_, let line) = row else { return nil }
                return line
            }
            let unified = WordDiff.spans(in: lines)

            let pairs = DiffRow.rows(of: file, layout: .split).compactMap { row -> (DiffLine?, DiffLine?)? in
                guard case .pair(_, let left, let right) = row else { return nil }
                return (left, right)
            }
            let split = WordDiff.spans(left: pairs.map(\.0), right: pairs.map(\.1))

            // Porovnává se **text**, ne indexy: v každém pohledu jsou řádky jinde.
            let fromUnified = unified.keys.sorted().map { mark(lines[$0].text, unified[$0] ?? []) }
            let fromSplit = (split.left.keys.map { (index: $0, side: pairs[$0].0) }
                + split.right.keys.map { (index: $0, side: pairs[$0].1) })
                .compactMap { item -> (String, String)? in
                    guard let line = item.side else { return nil }
                    let spans = (item.side?.kind == .removed ? split.left : split.right)[item.index] ?? []
                    return (line.text, mark(line.text, spans))
                }
            #expect(fromUnified.sorted() == fromSplit.map(\.1).sorted(), "soubor \(file.displayPath)")
        }
    }

    @Test("Na skutečném diffu se něco zvýraznit musí")
    func findsRewritesInTheFixture() throws {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let spans = diff.files.flatMap { file -> [Int] in
            let lines = DiffRow.rows(of: file).compactMap { row -> DiffLine? in
                guard case .line(_, let line) = row else { return nil }
                return line
            }
            return WordDiff.spans(in: lines).keys.sorted()
        }
        // Kdyby práh nebo párování zvýraznění vypnuly úplně, vyjde tenhle test na nulu a je to
        // jediné, z čeho by se to poznalo — funkce, která vždycky vrátí prázdno, projde všude jinde.
        #expect(spans.count >= 10)
    }
}
