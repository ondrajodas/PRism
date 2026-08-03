import Foundation

/// Markdown na bloky. Čisté funkce, žádné I/O, **nikdy nevyhodí výjimku**.
///
/// Je to stejná úvaha jako u `SyntaxHighlighter`: vlastní pravidla místo závislosti, protože
/// jde o čtení cizího textu a chyba se má projevit nanejvýš tím, že se odstavec vykreslí
/// natvrdo. Rozsah je podle toho, co se v popisech PR a v komentářích na GitHubu opravdu
/// objevuje — nadpisy, seznamy (včetně zaškrtávacích), bloky kódu, citace, oddělovače
/// a tabulky.
///
/// **Invariant: žádný řádek se neztratí.** Text ze všech bloků složený zpátky dá původní
/// vstup (až na prázdné řádky, které bloky oddělují). Je to na to test — tichá ztráta kusu
/// cizího komentáře je přesně to, čemu se tady vyhýbáme.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        /// Otevřený ` ``` ` blok: jazyk z fence a zatím posbírané řádky.
        var fence: (language: String?, lines: [String])?

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }
        func closeQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote))
            quote = []
        }
        func closeTable() {
            guard !table.isEmpty else { return }
            blocks.append(.table(table))
            table = []
        }
        func closeAll() {
            closeParagraph()
            closeQuote()
            closeTable()
        }

        var lines = text.components(separatedBy: .newlines)[...]
        while let line = lines.first {
            lines = lines.dropFirst()
            // Uvnitř fence se **nic** neinterpretuje, jinak by `# komentář` v kódu vyšel jako
            // nadpis. Zavírá ho jedině další fence.
            if var open = fence {
                if isFence(line) {
                    blocks.append(.code(language: open.language, lines: open.lines))
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // HTML z komentářů řeší dvě věci **struktura**, ne odstraňování tagů: komentář
            // `<!-- … -->` se nemá kreslit a `<details>` je rozbalovací blok s vnořeným
            // obsahem. Zbytek tagů (`<p>`, `<a>`) je inline a strhává je až view.
            if trimmed.hasPrefix("<!--") {
                closeAll()
                blocks.append(htmlComment(startingWith: line, trimmed: trimmed, rest: &lines))
                continue
            }
            if trimmed.lowercased().hasPrefix("<details") {
                closeAll()
                blocks.append(details(from: &lines))
                continue
            }

            if isFence(line) {
                closeAll()
                fence = (language: fenceLanguage(line), lines: [])
                continue
            }
            if trimmed.isEmpty {
                closeAll()
                continue
            }
            if isRule(trimmed) {
                closeAll()
                blocks.append(.rule)
                continue
            }
            if let heading = heading(trimmed) {
                closeAll()
                blocks.append(heading)
                continue
            }
            if trimmed.hasPrefix(">") {
                closeParagraph()
                closeTable()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if trimmed.hasPrefix("|") {
                closeParagraph()
                closeQuote()
                table.append(trimmed)
                continue
            }
            if let item = listItem(line) {
                closeAll()
                blocks.append(item)
                continue
            }
            closeQuote()
            closeTable()
            paragraph.append(line)
        }

        // Neuzavřený fence na konci textu **je** blok kódu: useknutý komentář se nesmí
        // vykreslit jako prázdno.
        if let open = fence {
            blocks.append(.code(language: open.language, lines: open.lines))
        }
        closeAll()
        return blocks
    }

    // MARK: - HTML bloky

    /// `<!-- … -->`, i přes víc řádků. Neuzavřený komentář na konci textu se bere celý —
    /// zahodit zbytek by znamenalo ztratit text, o kterém nevíme, že je pro stroje.
    private static func htmlComment(
        startingWith line: String,
        trimmed: String,
        rest lines: inout ArraySlice<String>
    ) -> MarkdownBlock {
        var body = [line]
        guard !trimmed.contains("-->") else { return .htmlComment(body) }
        while let next = lines.first {
            lines = lines.dropFirst()
            body.append(next)
            if next.contains("-->") { break }
        }
        return .htmlComment(body)
    }

    /// Obsah `<details>` až po jeho `</details>`, včetně zanoření.
    ///
    /// Vnitřek se parsuje **rekurzivně**: bývají v něm odstavce a seznamy, které by jako jeden
    /// slitý text nedávaly smysl. Neuzavřený `<details>` se uzavře koncem textu, ať se obsah
    /// neztratí.
    private static func details(from lines: inout ArraySlice<String>) -> MarkdownBlock {
        var summary = ""
        var inner: [String] = []
        var depth = 1

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix("<details") { depth += 1 }
            if trimmed.hasPrefix("</details") {
                depth -= 1
                if depth == 0 { break }
            }
            // Vlastní `<summary>` má jen ten `<details>`, který zpracováváme — vnořený patří
            // k vnořenému bloku, takže projde dovnitř jako obyčejný řádek.
            if depth == 1, summary.isEmpty, let text = summaryText(line) {
                summary = text
                continue
            }
            inner.append(line)
        }
        return .details(summary: summary, blocks: parse(inner.joined(separator: "\n")))
    }

    /// Text `<summary>`. Tagy se strhávají hned, protože z něj je popisek rozbalovátka —
    /// a odkaz uvnitř se přitom převede na Markdown, takže zůstane klikatelný.
    private static func summaryText(_ line: String) -> String? {
        guard line.lowercased().contains("<summary") else { return nil }
        let text = MarkdownHTML.stripped(line).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    // MARK: - Rozpoznávání

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func fenceLanguage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let tag = trimmed.drop(while: { $0 == "`" || $0 == "~" }).trimmingCharacters(in: .whitespaces)
        return tag.isEmpty ? nil : tag
    }

    /// Tři a víc `-`, `*` nebo `_` na samostatném řádku.
    ///
    /// `---` je v Markdownu i podtržení nadpisu, když stojí pod textem. Bereme ho vždycky jako
    /// oddělovač: v praxi se takhle nadpisy nepíšou a rozhodovat to podle předchozího řádku by
    /// znamenalo dvojí význam téhož řádku podle kontextu.
    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return ["-", "*", "_"].contains { symbol in
            trimmed.allSatisfy { String($0) == symbol }
        }
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes)
        // `#tag` nadpis není — za mřížkami musí být mezera.
        guard rest.first == " " else { return nil }
        return .heading(
            level: hashes,
            text: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    /// `- text`, `* text`, `+ text`, `1. text` a zaškrtávací `- [x] text`.
    private static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest = line.drop(while: { $0 == " " || $0 == "\t" })

        var marker: MarkdownBlock.Marker
        var text: Substring

        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            marker = .bullet
            text = rest.dropFirst(2)
        } else if let (number, after) = orderedMarker(rest) {
            marker = .number(number)
            text = after
        } else {
            return nil
        }

        // Zaškrtávátko je odrážka s `[ ]` nebo `[x]` na začátku textu.
        let content = text.drop(while: { $0 == " " })
        if content.hasPrefix("[ ] ") || content.hasPrefix("[] ") {
            marker = .task(isDone: false)
            text = content.drop(while: { $0 != "]" }).dropFirst()
        } else if content.lowercased().hasPrefix("[x] ") {
            marker = .task(isDone: true)
            text = content.drop(while: { $0 != "]" }).dropFirst()
        }

        return .listItem(
            // Dvě mezery = jedna úroveň, hlouběji než tři se nezanořuje: víc už se ve úzkém
            // panelu nedá odlišit a text by se stlačil.
            marker: marker,
            indent: min(indent / 2, 3),
            text: text.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func orderedMarker(_ rest: Substring) -> (Int, Substring)? {
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let separator = after.first, separator == "." || separator == ")" else { return nil }
        guard after.dropFirst().first == " " else { return nil }
        return (number, after.dropFirst(2))
    }
}
