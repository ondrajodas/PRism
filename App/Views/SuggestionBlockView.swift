import SwiftUI

/// Návrh změny kódu jako **mini diff** (#528) — červené původní řádky, zelené navrhované.
///
/// Kreslí se stejně v composeru (náhled toho, co odejde) i ve vlákně (co navrhl kolega), a je to
/// jedna komponenta schválně: druhá kresba téhož by dřív nebo později ukázala něco jiného, než co
/// GitHub s návrhem udělá. Blok je `.rv-sblock` z návrhu, sekce 54.
///
/// **Bez `.textSelection(.enabled)`**, jako bublina, ve které visí: je to buňka nad diffem
/// a selekce je v tomhle repu druhý zdroj nevykreslených řádků.
struct SuggestionBlockView: View {
    let suggestion: CodeSuggestion
    /// Poznámka vpravo v hlavičce — v composeru `upravuješ řádky 80–81`. `nil` = jen popisek.
    var note: String?
    /// Velikost prózy kolem. Sazba kódu se od ní odvozuje stejně jako u bloků markdownu.
    var size: Double = 12.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Identita je **pořadí**, ne text: dva stejné řádky v návrhu jsou běžné (prázdný
            // řádek, `}`) a `ForEach` by z nich udělal jeden. Indexy místo `enumerated()`,
            // protože tuple se u každého dotazu na identitu kopíruje (#361).
            ForEach(suggestion.original.indices, id: \.self) { index in
                row(suggestion.original[index], sign: "−", tint: Palette.crit, background: Palette.diffRemoved)
            }
            ForEach(suggestion.replacement.indices, id: \.self) { index in
                row(suggestion.replacement[index], sign: "+", tint: Palette.ok, background: Palette.diffAdded)
            }
        }
        .background(Palette.surface, in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1) }
        .clipShape(.rect(cornerRadius: 6))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(verbatim: Policy.suggestionLabel(of: suggestion))
            if let note {
                Spacer(minLength: 8)
                Text(verbatim: note)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .filling(alignment: .leading)
        .background(Palette.raised)
    }

    /// Jeden řádek mini diffu. Znaménko je vlastní `Text`, protože má vlastní barvu a v návrhu
    /// je to `::before` — tedy součást řádku, ne sloupec s vlastní šířkou.
    ///
    /// **Řádky se neobtékají, ořezávají** (`.rv-sblock .l` má `white-space: pre`
    /// a `text-overflow: ellipsis`). Zalomený řádek kódu v bublině široké 300 bodů se přestane
    /// číst jako řádek a mini diff by ztratil to jediné, čím je čitelný — že červené a zelené
    /// řádky stojí pod sebou ve stejném počtu.
    private func row(_ line: String, sign: String, tint: Color, background: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: sign)
                .foregroundStyle(tint)
            Text(verbatim: line)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: MarkdownTypography.codeSize(base: size), design: .monospaced))
        .padding(.horizontal, 8)
        .filling(alignment: .leading)
        .background(background)
    }
}
