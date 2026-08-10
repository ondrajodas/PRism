import AppKit
import Testing

@testable import PRism

/// Výška bloku kódu proti tomu, co blok opravdu nakreslí (#236).
///
/// Je to jedna třída chyby: **šířka pro měření ≠ šířka pro kreslení**. Blok si v `LazyVStack`u
/// řekne o výšku sám, takže když si řekne o menší, než jakou nakreslí, položí SwiftUI další řádek
/// (bublinu nálezu, vlákno, hlavičku hunku) do plochy, kterou `NSTextView` ještě kreslí — a protože
/// je AppKitové view nad SwiftUI obsahem, je vidět kód přes bublinu.
///
/// Referencí je tady vždycky **layout manager**, ne druhý výpočet: ptá se na skutečné rámečky řádků
/// (`frame(ofLine:)`) a na skutečnou výšku textu.
@Suite("Výška bloku kódu")
@MainActor
struct DiffBlockHeightTests {
    private static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    private func block(of lines: [String]) -> DiffBlock {
        DiffBlock(lines: lines.enumerated().map { index, text in
            DiffLine(kind: .added, oldNumber: nil, newNumber: index + 1, text: text)
        })
    }

    /// Blok pohledu pod sebou tak, jak ho složí `DiffCodeBlockView`.
    private func unified(_ lines: [String]) -> DiffTextView {
        let view = DiffTextView.wrappingBlock()
        view.gutterWidth = DiffLineView.contentInset(for: .unified)
        view.show(
            block(of: lines),
            language: Language(path: "Cart.swift"),
            palette: .intelliJLight,
            signature: lines.joined(),
            words: { [:] }
        )
        return view
    }

    /// Výška, o kterou si blok řekne, a k ní spodek nakresleného textu **po** nastavení rámce —
    /// v tom pořadí, v jakém to dělá SwiftUI: nejdřív `sizeThatFits`, pak `frame`.
    ///
    /// Rámečky se **vyžadují všechny**: `?? 0` nad chybějícím rámečkem by z tvrzení „vejde se to do
    /// změřené výšky“ udělalo „nula se vejde do čehokoli“, tedy test, který projde vždycky.
    private func measure(_ view: DiffTextView, width: Double) throws -> (height: Double, bottom: Double) {
        let height = try #require(view.height(forWidth: width))
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let bottoms = try (0..<view.lines.count).map { try #require(view.frame(ofLine: $0)).maxY }
        return (height, try #require(bottoms.max()))
    }

    /// Šířka řetězce vysázeného písmem kódu, i s odsazením, které si textový kontejner bere na obou
    /// koncích řádku.
    private func width(of text: String, in view: DiffTextView) throws -> Double {
        let padding = try #require(view.textContainer).lineFragmentPadding
        return NSAttributedString(string: text, attributes: [.font: Self.font]).size().width + padding * 2
    }

    /// **Tenhle test je celé #236.** Pásmo šířek, ne jedna: rozejde se to jedině tehdy, když délka
    /// nejdelšího řádku padne mezi změřenou a kreslenou šířku, a to pásmo se šířkou okna posouvá.
    ///
    /// Ověřeno vloženou regresí (`height(forWidth:)` měřená o gutter širší, tedy původní stav):
    /// padne 62 případů ze 165, přesně to pásmo. Bez sweepu by test u „hezké“ šířky prošel.
    @Test("Blok si řekne o tu výšku, kterou nakreslí")
    func asksForTheHeightItDraws() throws {
        let long = String(repeating: "x", count: 61)
        for count in [41, 48, 55, 57, 63, 70, 96] {
            let view = unified([String(repeating: "y", count: count), long])
            for width in stride(from: 300.0, through: 800.0, by: 17.0) {
                let result = try measure(view, width: width)
                // Co nakreslí, do toho se musí vejít — jinak text přeteče do řádku pod blokem.
                #expect(result.height >= result.bottom, "šířka \(width), \(count) znaků")
                // A z druhé strany: pod poslední řádek nemá zbýt víc než svislý inset. Bez toho by
                // test prošel i bloku, který si o výšku řekne s rezervou a nechá pod sebou mezeru.
                #expect(result.height <= result.bottom + 4, "šířka \(width), \(count) znaků")
            }
        }
    }

    /// Druhá polovina rozhodnutí #236: gutter ubírá místo **jen vlevo**, takže se kód zalomí až
    /// tehdy, když se vedle gutteru nevejde. Do #236 se zalamoval o šířku gutteru dřív (při šířce
    /// okna 600 to bylo 41 znaků místo 57) a u pravého okraje zůstávalo mrtvé místo.
    @Test("Kód se zalomí až tehdy, když se za gutter nevejde")
    func wrapsOnlyWhenTheCodeDoesNotFitNextToTheGutter() throws {
        let text = String(repeating: "x", count: 57)
        let view = unified([text])
        let gutter = DiffLineView.contentInset(for: .unified)
        let content = try width(of: text, in: view)
        let single = view.height(ofRows: 1)

        // Šířka, na kterou se kód za gutter vejde: jeden vizuální řádek. Do #236 se na téhle šířce
        // zalomil, protože gutter ubíral místo i vpravo.
        #expect(try #require(view.height(forWidth: content + gutter + 1)) == single)
        // A kontrola z druhé strany, ať test neprojde bloku, který nezalamuje vůbec.
        #expect(try #require(view.height(forWidth: content + gutter - 20)) > single)
    }

    /// Prázdný řádek nemá glyfy, takže by výška mohla vyjít nulová a v seznamu by po bloku zbyla
    /// mezera, na kterou se nedá kliknout.
    ///
    /// **Řádku s textem se rovnat nemusí** a je to změřené, ne odhad: `usedRect` u prázdného textu
    /// vrací výšku prázdného fragmentu, tedy o 2 pt menší (18 proti 20). Podstatné je, že se do ní
    /// nakreslený řádek vejde — o překryv jde, ne o dva body.
    @Test("Blok o jednom prázdném řádku má výšku aspoň nakresleného řádku")
    func keepsTheHeightOfAnEmptyRow() throws {
        let view = unified([""])
        let result = try measure(view, width: 600)
        #expect(result.height > 0)
        #expect(result.height >= result.bottom)
    }
}

/// Totéž pro pohled **vedle sebe** (#236). Sloupec dvojice se nezalamuje, takže se jeho výška
/// nemusí měřit z layoutu — ale spočítaná musí vyjít stejně, jinak se rozejde poloha pilulek
/// s kódem, ke kterému patří.
@Suite("Výška bloku dvojic")
@MainActor
struct DiffPairBlockHeightTests {
    private func lines(_ count: Int) -> [DiffLine] {
        (0..<count).map { DiffLine(kind: .context, oldNumber: $0 + 1, newNumber: $0 + 1, text: "let x\($0) = \($0)") }
    }

    private func container(rows: Int) -> DiffPairBlockContainer {
        let container = DiffPairBlockContainer()
        container.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        container.show(
            DiffPairBlock(left: lines(rows), right: lines(rows)),
            language: Language(path: "Cart.swift"),
            palette: .intelliJLight,
            signature: "rows\(rows)",
            gutter: DiffLineView.contentInset(for: .split)
        )
        return container
    }

    /// Sloupec složený stejně jako v kontejneru — reference, ze které se čte, kde text **opravdu**
    /// leží. Není to druhý výpočet téhož: odpovídá layout manager.
    private func column(rows: Int) -> DiffTextView {
        let column = DiffTextView.pairColumn()
        column.gutterWidth = DiffLineView.contentInset(for: .split)
        column.numberColumns = 1
        column.show(
            DiffBlock(lines: lines(rows)),
            language: Language(path: "Cart.swift"),
            palette: .intelliJLight,
            signature: "rows\(rows)",
            words: { [:] }
        )
        return column
    }

    /// Svislý inset patří bloku, ne řádku. Když ho nesla výška řádku, utíkal každý další řádek
    /// o 2 pt — na osmi řádcích 12 pt a na šedesátiřádkovém bloku 116 pt.
    @Test("Rámečky dvojic sedí na text sloupce")
    func rowFramesMatchTheDrawnText() {
        for rows in [1, 8, DiffBlock.maxLines] {
            let frames = container(rows: rows).lineFrames()
            let reference = column(rows: rows)
            #expect(frames.count == rows)
            for frame in frames {
                let drawn = reference.frame(ofLine: frame.index)
                #expect(frame.rect.minY == drawn?.minY, "\(rows) řádků, řádek \(frame.index)")
                #expect(frame.rect.height == drawn?.height, "\(rows) řádků, řádek \(frame.index)")
            }
        }
    }

    /// Spočítaná výška bloku proti té, kterou hlásí layout sloupce.
    @Test("Blok dvojic si řekne o výšku, kterou sloupec nakreslí")
    func asksForTheHeightTheColumnDraws() {
        for rows in [1, 8, DiffBlock.maxLines] {
            #expect(container(rows: rows).height(forWidth: 800) == column(rows: rows).height(forWidth: 800))
        }
    }
}
