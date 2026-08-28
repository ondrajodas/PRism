import AppKit
import Testing

@testable import PRism

/// Rámečky řádků bloku jedním průchodem místo dotazu na každý řádek (#476).
///
/// `lineFrames()` se do #476 ptalo `boundingRect(forGlyphRange:in:)` **na každý řádek** a byla to
/// drahá cesta: ve vzorku z přepínání tabů drželo 697 vzorků z 1 519, které stál celý
/// `updateNSView` bloku. Od #476 se fragmenty vyberou **naráz** (`enumerateLineFragments`)
/// a přiřadí se řádkům podle pozice znaku.
///
/// **Nejcennější tvrzení je tady to, že se nic nezměnilo.** Zrychlení, které vydá jiné rámečky, je
/// tichá vada: z rámečků se počítá geometrie gutteru (#252), poloha pilulky na komentář a kotvy pro
/// ⇧ klik (`DiffRowFrames`), takže posunutý nebo chybějící řádek se **nikde neohlásí** — jen se
/// klikne vedle. Referencí je proto `frame(ofLine:)`, tedy ta stará cesta, která v kódu zůstala.
///
/// **Ověřeno tím, že to hned chytlo skutečnou chybu**, ne dodatečně vloženou: první podoba brala
/// `usedRect` fragmentu tak, jak přišel, a ten **obsahuje `lineFragmentPadding`** — rámečky vyšly
/// o **5 bodů** vedle (`minX` 5,0 proti toleranci 0,5). Druhé kolo pak chytlo, že u **zalomeného**
/// řádku vrací `boundingRect` šířku celého kontejneru, kdežto sjednocení fragmentů jen tu použitou
/// (rozdíl 70–78 bodů). Obojí je přesně ta tichá vada, kvůli které tenhle test je: pilulka na
/// komentář a kotva pro ⇧ klik by seděly vedle a nic by se neohlásilo.
@Suite("Rámečky řádků bloku (#476)")
@MainActor
struct DiffLineFramesTests {
    /// Blok, ve kterém je od každého něco: krátký řádek, **prázdný** (nemá glyfy, takže mu výšku
    /// dává písmo) a **dlouhý**, který se na úzké šířce zalomí do víc fragmentů.
    private func view(width: Double) -> DiffTextView {
        let texts = [
            "let value = compute(1)",
            "",
            String(repeating: "// hodně dlouhý komentář, který se má zalomit ", count: 6),
            "    return modern(value)",
            "",
            "}",
        ]
        let view = DiffTextView.wrappingBlock()
        view.gutterWidth = DiffLineView.contentInset(for: .unified)
        view.show(
            DiffBlock(lines: texts.enumerated().map { index, text in
                DiffLine(kind: index % 2 == 0 ? .added : .context, oldNumber: nil, newNumber: index + 1, text: text)
            }),
            style: DiffBlockStyle(language: Language(path: "Cart.swift"), colorScheme: .light),
            words: { [:] }
        )
        let height = view.height(forWidth: width) ?? 400
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return view
    }

    /// **Hlavní tvrzení**: jeden průchod dá totéž co dotaz na každý řádek — na šířce, kde se dlouhý
    /// řádek zalomí, i na šířce, kde se vejde celý.
    @Test("Jeden průchod vydá tytéž rámečky jako dotaz po řádcích", arguments: [320.0, 900.0])
    func matchesThePerLineAnswer(width: Double) throws {
        let view = self.view(width: width)
        let frames = view.lineFrames()

        #expect(frames.count == view.lines.count, "žádný řádek nesmí vypadnout — chybějící je díra v gutteru i v kotvách")
        for entry in frames {
            let reference = try #require(view.frame(ofLine: entry.index))
            #expect(abs(entry.rect.minY - reference.minY) < 0.5, "řádek \(entry.index) začíná jinde")
            #expect(abs(entry.rect.height - reference.height) < 0.5, "řádek \(entry.index) má jinou výšku")
            #expect(abs(entry.rect.minX - reference.minX) < 0.5, "řádek \(entry.index) začíná v jiném sloupci")
            #expect(abs(entry.rect.width - reference.width) < 0.5, "řádek \(entry.index) je jinak široký")
        }
    }

    /// **Zalomený řádek si své fragmenty sjednotí.** Kdyby se jich vzal jen první, byl by rámeček
    /// nižší než nakreslený text a pilulka na komentář by seděla nad druhou půlkou řádku.
    @Test("Zalomený řádek je vyšší než nezalomený")
    func wrappedLineUnionsItsFragments() throws {
        let narrow = try #require(view(width: 320).lineFrames().first { $0.index == 2 })
        let wide = try #require(view(width: 1400).lineFrames().first { $0.index == 2 })

        #expect(narrow.rect.height > wide.rect.height, "na úzké šířce se ten řádek musí zalomit")
    }

    /// Prázdný řádek nemá glyfy, takže by vyšel nulově vysoký — výšku mu dává písmo. Bez toho by
    /// gutter u prázdných řádků neměl kam kreslit číslo.
    @Test("Prázdný řádek má výšku písma, ne nulu")
    func emptyLineKeepsItsHeight() throws {
        let frames = view(width: 900).lineFrames()
        let empty = try #require(frames.first { $0.index == 1 })

        #expect(empty.rect.height > 0)
    }
}
