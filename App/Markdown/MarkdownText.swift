import SwiftUI

/// Vykreslí Markdown z GitHubu — popis PR, komentáře, těla review.
///
/// Bloky (nadpisy, seznamy, kód, citace, `<details>`) skládá `MarkdownParser`, **formátování
/// uvnitř řádku dělá systém** (`AttributedString`) a inline HTML strhává `MarkdownHTML`. Dělí
/// se to takhle proto, že systémový parser inline zvládá dobře, ale bloky ve `Text`u tiše
/// spolkne: `## Popis` vyjde jako „Popis“ obyčejným písmem a odrážky ztratí odrážku.
///
/// Parsuje se **při vykreslení**, ne dopředu: je to průchod po řádcích a text komentáře má
/// desítky řádků, ne tisíce. Stejná úvaha jako u obarvování řádku v diffu.
struct MarkdownText: View {
    let text: String
    /// Základní písmo. Nadpisy a kód se od něj odvozují, takže bublina u kódu může být menší
    /// než popis PR, aniž by se to muselo nastavovat po blocích.
    var font: Font = .callout

    var body: some View {
        MarkdownBlocksView(blocks: MarkdownParser.parse(text), font: font)
    }
}

/// Seznam bloků pod sebou.
///
/// Vlastní typ, ne metoda: `<details>` má vnořené bloky, takže se vykreslování volá samo —
/// a rekurze přes `some View` je typ definovaný sám sebou, což Swift odmítne. Nominální typ
/// tenhle problém nemá.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var font: Font = .callout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `id: \.offset`, ne obsah: dva stejné odstavce v jednom komentáři jsou možné
            // a `ForEach` by z nich udělal jeden.
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, font: font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Jeden blok Markdownu.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var font: Font = .callout

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 2 ? .headline : .subheadline)
                .padding(.top, 2)
        case .paragraph(let text):
            // Odstavec, ze kterého po strhnutí tagů nic nezbylo (`<p>`, `</ul>`), se
            // nekreslí — jinak by po každém takovém řádku zůstala mezera.
            paragraph(text)
        case .listItem(let marker, let indent, let text):
            item(marker: marker, indent: indent, text: text)
        case .code(_, let lines):
            code(lines)
        case .quote(let lines):
            quote(lines)
        case .rule:
            Rectangle().fill(.separator).frame(height: 1).padding(.vertical, 2)
        case .table(let rows):
            table(rows)
        case .details(let summary, let blocks):
            details(summary: summary, blocks: blocks)
        // `<!-- … -->` je značka pro stroje, ne text pro člověka — GitHub taky nekreslí nic.
        case .htmlComment:
            EmptyView()
        }
    }

    // MARK: - Bloky

    @ViewBuilder private func paragraph(_ text: String) -> some View {
        let rendered = inline(text)
        if !rendered.characters.isEmpty {
            Text(rendered)
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func item(marker: MarkdownBlock.Marker, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            bullet(marker)
            Text(inline(text))
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Double(indent) * 16)
    }

    @ViewBuilder private func bullet(_ marker: MarkdownBlock.Marker) -> some View {
        switch marker {
        case .bullet:
            Text(verbatim: "•").font(font).foregroundStyle(.secondary)
        case .number(let number):
            // `verbatim` a ruční tečka: `Text("\(number).")` protáhne číslo přes locale.
            Text(verbatim: "\(number).").font(font).foregroundStyle(.secondary).monospacedDigit()
        case .task(let isDone):
            // Zaškrtnutí je **jen obrázek**, ne přepínač: je to cizí text, ne můj formulář.
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .font(.caption)
                .foregroundStyle(isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }

    /// Blok kódu monospace a s pozadím. Neobarvuje se: jazyk z fence je volný řetězec
    /// (`sh`, `zsh`, `console`) a `Syntax.Language` se pozná z **cesty k souboru** — mapovat
    /// jedno na druhé znamená hádat, a špatně obarvený cizí kód je horší než neobarvený.
    ///
    /// Tagy se v něm **nestrhávají**: `<T>` uvnitř kódu je kód, ne HTML.
    private func code(_ lines: [String]) -> some View {
        Text(verbatim: lines.joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }

    private func quote(_ lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(.separator).frame(width: 3)
            Text(inline(lines.joined(separator: "\n")))
                .font(font)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Tabulka jako monospace řádky se svislítky. Vykreslit ji doopravdy (sloupce, zarovnání)
    /// je vlastní úloha; takhle je aspoň čitelná a **nic z ní nechybí**, což je to hlavní.
    private func table(_ rows: [String]) -> some View {
        ScrollView(.horizontal) {
            Text(verbatim: rows.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
        }
        .scrollIndicators(.automatic)
    }

    /// `<details>` jako rozbalovátko — sbalené, jako na GitHubu.
    ///
    /// Popisek bez `<summary>` má vlastní text: prázdné rozbalovátko se nedá ani rozbalit,
    /// protože není na co kliknout.
    private func details(summary: String, blocks: [MarkdownBlock]) -> some View {
        DisclosureGroup {
            MarkdownBlocksView(blocks: blocks, font: font)
                .padding(.top, 4)
        } label: {
            Text(summary.isEmpty ? AttributedString("Podrobnosti") : inline(summary))
                .font(font)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline

    /// Tučné, kurzíva, `kód` a odkazy uvnitř řádku — a před tím inline HTML.
    ///
    /// Tagy se strhávají **až tady**, ne v parseru: model tak drží to, co přišlo z GitHubu,
    /// a rozhodnutí „`<p>` se v okně nemá čím projevit“ je vidět tam, kde se kreslí. Odkazy
    /// `MarkdownHTML` převádí na Markdown, takže zůstanou klikatelné.
    ///
    /// `inlineOnlyPreservingWhitespace` schválně: blokové značky už jsou pryč (odřízl je
    /// parser), takže tady nemá co spolknout, a mezery zůstanou tak, jak je autor napsal.
    /// Když parsování selže, vrací se **holý text** — nepřečtený komentář je horší než
    /// komentář bez tučného.
    ///
    /// Známé omezení: `<div>` **uvnitř** zpětných apostrofů se strhne taky, protože se to dělá
    /// nad celým řádkem. Cizí HTML v inline kódu je vzácnější než bot, který posílá
    /// `<details>` v každém komentáři.
    private func inline(_ source: String) -> AttributedString {
        let text = MarkdownHTML.stripped(source).trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    MarkdownText(text: """
        ## Popis

        Tohle je **odstavec** s `kódem` a [odkazem](https://github.com).

        - odrážka
        - [x] hotová položka
        - [ ] nehotová
          - zanořená

        1. první
        2. druhá

        > citace od kolegy

        ```swift
        let x = 1  // # tohle není nadpis
        ```

        <!-- linear-linkback -->
        <details>
        <summary><a href="https://linear.app">AJDA-2222 Update Doctrine</a></summary>
        <p>
        Text uvnitř rozbalovátka.
        </p>
        </details>

        | a | b |
        |---|---|
        | 1 | 2 |
        """)
    .padding()
    .frame(width: 460)
}
