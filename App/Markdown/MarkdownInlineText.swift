import SwiftUI

/// Formátování **uvnitř řádku**: tučné, kurzíva, `kód` a odkazy (#279 vytáhlo z `MarkdownText`).
///
/// Sází to **systém** (`AttributedString`), a to je zapsané rozhodnutí, ne shoda okolností: inline
/// zvládá dobře, kdežto bloky ve `Text`u **tiše spolkne**. Struktura je proto naše (`MarkdownParser`),
/// inline jeho. Tady zůstává jen to, co systém neumí: strhnout inline HTML (`MarkdownHTML`)
/// a podložit inline kód (`Palette.codeFill`).
///
/// Samostatný typ proto, že si o inline říká pět míst — odstavec, nadpis, položka seznamu, popisek
/// rozbalovátka a titulek výstrahy — a dokud to byla privátní metoda view, nešlo to otestovat.
enum MarkdownInlineText {
    /// Text jednoho řádku (odstavce) jako `AttributedString`.
    ///
    /// `inlineOnlyPreservingWhitespace` schválně: blokové značky už jsou pryč (odřízl je parser),
    /// takže tady nemá co spolknout, a mezery zůstanou tak, jak je autor napsal. Když parsování
    /// selže, vrací se **holý text** — nepřečtený komentář je horší než komentář bez tučného.
    ///
    /// - Parameter size: velikost prózy. Inline kód se od ní odvozuje, aby v drobnějším písmu
    ///   nevyskočil.
    static func rendered(_ source: String, size: Double) -> AttributedString {
        let text = MarkdownHTML.stripped(source).trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        highlightCode(in: &attributed, size: size)
        return attributed
    }

    /// Podloží inline kód, jak to má GitHub: monospace na jemném podkladu.
    ///
    /// Podklad je **plocha za písmem**, ne kapsle s odsazením — `AttributedString` umí nastavit
    /// barvu pozadí běhu, ale ne jeho výplň a rádius. Kapsle by znamenala kreslit každý běh jako
    /// vlastní view, tedy rozpadlé zalomení uprostřed větty; podklad je z toho ta část, kterou jde
    /// mít, a je to zrovna ta, kvůli které se inline kód pozná.
    ///
    /// Rozsahy se **posbírají dopředu** — mutace uprostřed procházení `runs` by kolekci pod rukama
    /// přerovnala.
    private static func highlightCode(in attributed: inout AttributedString, size: Double) {
        let ranges = attributed.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        guard !ranges.isEmpty else { return }

        for range in ranges {
            attributed[range].font = .system(size: MarkdownTypography.codeSize(base: size), design: .monospaced)
            attributed[range].backgroundColor = Palette.codeFill
        }
    }
}
