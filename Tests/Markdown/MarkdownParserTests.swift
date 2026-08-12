import Foundation
import Testing

@testable import PRism

/// Markdown na bloky. Čisté funkce, nic se nemockuje.
///
/// Každý test ověřuje i **invariant**: text ze všech bloků složený zpátky obsahuje všechno,
/// co bylo na vstupu. Tichá ztráta kusu cizího komentáře je přesně to, čemu se tady vyhýbáme
/// — je to tatáž pojistka jako „spojení run dá původní řádek“ u obarvování kódu.
@Suite("MarkdownParser")
struct MarkdownParserTests {
    /// Obsah, který se v blocích **nesmí** ztratit: běhy písmen a číslic.
    ///
    /// Interpunkce se zahazuje schválně — značky (`##`, `-`, `>`, ` ``` `) i prázdné řádky
    /// mezi bloky jsou struktura a tu parser převádí na typ bloku, ne na text. Ztrátu obsahu
    /// to zachytí, přeformátování ne, a to je přesně ta hranice, o kterou jde.
    private func content(of text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private func content(in blocks: [MarkdownBlock]) -> Set<String> {
        content(of: blocks.map(text(of:)).joined(separator: "\n"))
    }

    /// Do porovnání jde **i to, co blok drží mimo text** — číslo odrážky, zaškrtnutí a jazyk
    /// fence. Jsou to údaje ze vstupu, takže by je jinak invariant nahlásil jako ztracené,
    /// přitom je view vykreslí.
    private func text(of block: MarkdownBlock) -> String {
        switch block {
        case .heading(_, let text): text
        case .paragraph(let text): text
        case .listItem(let marker, _, let text): "\(markerText(marker)) \(text)"
        case .code(let language, let lines): ([language ?? ""] + lines).joined(separator: "\n")
        // Citace i výstraha nesou od #279 **bloky**, takže se do porovnání skládají rekurzivně.
        // U výstrahy jde do porovnání i její druh: `[!NOTE]` je ve vstupu slovo `NOTE` a v modelu
        // `kind`, ze kterého view kreslí titulek — bez něj by ho invariant nahlásil jako ztracený.
        case .quote(let blocks): blocks.map(text(of:)).joined(separator: "\n")
        case .alert(let kind, let blocks):
            ([kind.rawValue] + blocks.map(text(of:))).joined(separator: "\n")
        case .rule: ""
        case .table(let rows): rows.joined(separator: "\n")
        // Do porovnání jde i vnitřek `<details>` — je to obsah, jen zanořený.
        case .details(let summary, let blocks):
            ([summary] + blocks.map(text(of:))).joined(separator: "\n")
        case .htmlComment(let lines): lines.joined(separator: "\n")
        }
    }

    private func markerText(_ marker: MarkdownBlock.Marker) -> String {
        switch marker {
        case .bullet: ""
        case .number(let number): "\(number)."
        case .task(let isDone): isDone ? "[x]" : "[ ]"
        }
    }

    /// Zkontroluje invariant a vrátí bloky, ať to testy nemusí psát dvakrát.
    private func parse(_ text: String) -> [MarkdownBlock] {
        let blocks = MarkdownParser.parse(text)
        // Vstup se porovnává **po strhnutí HTML**: jména tagů (`details`, `p`) jsou značky,
        // ne text, a parser je vědomě nedrží. Že se přitom neztratí text ani URL z odkazu,
        // hlídá `MarkdownHTMLTests` zvlášť.
        let lost = content(of: MarkdownHTML.stripped(text)).subtracting(content(in: blocks))
        #expect(lost.isEmpty, "parser zahodil \(lost)")
        return blocks
    }

    // MARK: - Bloky

    @Test("Nadpis nese úroveň a text")
    func parsesHeadings() {
        #expect(parse("## Popis") == [.heading(level: 2, text: "Popis")])
        #expect(parse("###### Šest") == [.heading(level: 6, text: "Šest")])
    }

    /// `#tag` a `#######` nadpis nejsou — za mřížkami musí být mezera a jich nejvýš šest.
    @Test("Mřížka bez mezery ani sedm mřížek nadpis nedá")
    func refusesFakeHeadings() {
        #expect(parse("#tag") == [.paragraph("#tag")])
        #expect(parse("####### moc") == [.paragraph("####### moc")])
    }

    /// GitHub v komentářích zalomení respektuje, takže se řádky odstavce **nesmí slít**.
    @Test("Odstavec si nechá zalomení, prázdný řádek ho ukončí")
    func keepsSoftBreaksInsideAParagraph() {
        #expect(parse("první\ndruhý\n\ntřetí") == [.paragraph("první\ndruhý"), .paragraph("třetí")])
    }

    /// **`CRLF` z GitHubu nesmí odstavec rozsekat** (#295). Těla komentářů `CRLF` doopravdy mají
    /// (je ve třech fixtures konverzací) a do #295 se dělilo `components(separatedBy: .newlines)`,
    /// která pracuje po skalárech — takže `CRLF` byly **dva** oddělovače a mezi ně vložila prázdný
    /// řádek. A prázdný řádek je konec odstavce, takže se každý řádek cizího komentáře vysázel jako
    /// vlastní odstavec, tedy s mezerou pod sebou.
    @Test("CRLF dá tytéž bloky jako LF", arguments: ["\r\n", "\r"])
    func parsesCRLFSameAsLF(_ terminator: String) {
        let source = "## Popis\n\nprvní\ndruhý\n\n- odrážka\n"

        #expect(parse(source.replacingOccurrences(of: "\n", with: terminator)) == parse(source))
    }

    @Test("Odrážky, čísla a zaškrtávátka")
    func parsesListItems() {
        let blocks = parse("""
            - odrážka
            * jiná
            1. první
            2) druhá
            - [x] hotové
            - [ ] nehotové
            """)

        #expect(blocks == [
            .listItem(marker: .bullet, indent: 0, text: "odrážka"),
            .listItem(marker: .bullet, indent: 0, text: "jiná"),
            .listItem(marker: .number(1), indent: 0, text: "první"),
            .listItem(marker: .number(2), indent: 0, text: "druhá"),
            .listItem(marker: .task(isDone: true), indent: 0, text: "hotové"),
            .listItem(marker: .task(isDone: false), indent: 0, text: "nehotové"),
        ])
    }

    @Test("Zanoření se počítá po dvou mezerách a zaráží se na třetí úrovni")
    func countsIndentation() {
        let blocks = parse("""
            - první
              - druhá
                - třetí
                        - hluboká
            """)

        #expect(blocks.map(indent) == [0, 1, 2, 3])
    }

    private func indent(_ block: MarkdownBlock) -> Int? {
        guard case .listItem(_, let indent, _) = block else { return nil }
        return indent
    }

    /// Uvnitř fence se **nic** neinterpretuje — jinak by `# komentář` v kódu vyšel jako nadpis.
    @Test("Blok kódu si nechá řádky tak, jak jsou")
    func keepsCodeVerbatim() {
        let blocks = parse("""
            ```swift
            # tohle není nadpis
            - ani odrážka
            ```
            """)

        #expect(blocks == [.code(language: "swift", lines: ["# tohle není nadpis", "- ani odrážka"])])
    }

    @Test("Fence bez jazyka jazyk nemá")
    func parsesAFenceWithoutALanguage() {
        #expect(parse("```\nkód\n```") == [.code(language: nil, lines: ["kód"])])
    }

    /// Useknutý komentář se nesmí vykreslit jako prázdno.
    @Test("Neuzavřený blok kódu blokem zůstane")
    func closesAnUnterminatedFence() {
        #expect(parse("```\nzačátek") == [.code(language: nil, lines: ["začátek"])])
    }

    // MARK: - Citace

    @Test("Citace sbírá řádky za sebou a dá z nich odstavec")
    func parsesQuotes() {
        #expect(parse("> první\n> druhý") == [.quote([.paragraph("první\ndruhý")])])
    }

    /// To hlavní z #279: obsah citace se **parsuje na bloky**. Do té doby se řádky slepily do
    /// jednoho `Text`u, takže `## nadpis` i `- [ ]` uvnitř `> …` zůstaly v okně jako zdroj —
    /// a boti do citací píšou celé zprávy.
    @Test("Nadpis, odrážka a zaškrtávátko uvnitř citace se vysázejí")
    func parsesBlocksInsideAQuote() {
        let blocks = parse("""
            > ## Review skipped
            >
            > - [ ] 🔍 Trigger review
            > - odrážka
            """)

        #expect(blocks == [.quote([
            .heading(level: 2, text: "Review skipped"),
            .listItem(marker: .task(isDone: false), indent: 0, text: "🔍 Trigger review"),
            .listItem(marker: .bullet, indent: 0, text: "odrážka"),
        ])])
    }

    @Test("Vnořená citace je citace v citaci")
    func parsesANestedQuote() {
        #expect(parse("> vnější\n>\n> > vnitřní") == [.quote([
            .paragraph("vnější"),
            .quote([.paragraph("vnitřní")]),
        ])])
    }

    /// Odsazení uvnitř citace nese úroveň seznamu, takže se za `>` zahazuje **jedna** mezera,
    /// ne všechna. Do #279 se trimovalo všechno; při slepení do jednoho `Text`u to nebylo vidět.
    @Test("Citace si nechá odsazení zanořeného seznamu")
    func keepsIndentationInsideAQuote() {
        let blocks = parse("""
            > - první
            >   - druhá
            """)

        #expect(blocks == [.quote([
            .listItem(marker: .bullet, indent: 0, text: "první"),
            .listItem(marker: .bullet, indent: 1, text: "druhá"),
        ])])
    }

    /// `<details>` posílají do citací boti (CodeRabbit v rate-limit zprávě), takže se rekurze
    /// citace musí potkat s rekurzí rozbalovátka.
    @Test("`<details>` uvnitř citace zůstane rozbalovátkem")
    func parsesDetailsInsideAQuote() {
        let blocks = parse("""
            > text
            >
            > <details>
            > <summary>popisek</summary>
            >
            > uvnitř
            >
            > </details>
            """)

        guard case .quote(let inner) = blocks.first else {
            Issue.record("první blok není citace: \(String(describing: blocks.first))")
            return
        }
        #expect(inner.contains { if case .details = $0 { true } else { false } })
    }

    /// Zanoření má strop (`nestingLimit`) — proti `>>>>…` z mailového vlákna a proti hloubce
    /// stromu view (#220). **Obsah se přitom nesmí ztratit**, jen se nevysází.
    @Test("Citace přes strop zanoření zůstane textem, ne prázdnem")
    func keepsContentBeyondTheNestingLimit() {
        let markers = String(repeating: "> ", count: MarkdownParser.nestingLimit + 3)
        let blocks = parse("\(markers)hluboko")

        // Invariant v `parse(_:)` výš už ověřil, že slovo „hluboko“ v blocích zůstalo; tady jde
        // o to, že se rekurze zarazila a nespadla.
        #expect(blocks.count == 1)
    }

    /// Strop musí platit **i skrz `<details>`**, ne jen v citacích.
    ///
    /// Doplněno po nálezu z review #279: lokální počítadlo otevřených tagů se jmenovalo `depth`
    /// a zastínilo tím parametr s hloubkou rekurze, takže se strop porovnával s počtem tagů (po
    /// uzavření nula) — nezabral vůbec a `<details>` hloubku rekurze ještě resetoval. Ověřeno
    /// vrácením regrese: se stíněním tenhle test padá.
    @Test("Rozbalovátka přes strop zanoření zůstanou textem")
    func keepsContentBeyondTheNestingLimitInDetails() {
        let levels = MarkdownParser.nestingLimit + 2
        let opening = (0..<levels).map { "<details>\n<summary>úroveň \($0)</summary>" }
        let text = (opening + ["nejhlubší text"] + Array(repeating: "</details>", count: levels))
            .joined(separator: "\n")

        let blocks = parse(text)

        // Za stropem se vnitřek nechá textem, takže se v odstavci objeví surový tag. Dokud strop
        // nezabíral, šla rozbalovátka až na dno a žádný odstavec `<details>` neobsahoval.
        #expect(
            paragraphs(in: blocks).contains { $0.contains("<details") },
            "strop nezabral, zanoření šlo až na dno: \(paragraphs(in: blocks))"
        )
    }

    // MARK: - Výstrahy (#279)

    @Test("Pět druhů výstrahy se pozná podle prvního řádku citace")
    func parsesAlerts() {
        for kind in MarkdownBlock.Alert.allCases {
            let blocks = parse("> [!\(kind.rawValue)]\n> obsah")
            #expect(blocks == [.alert(kind: kind, blocks: [.paragraph("obsah")])], "druh \(kind)")
        }
    }

    @Test("Výstraha uvnitř citace je výstraha, ne text")
    func parsesAnAlertInsideAQuote() {
        let blocks = parse("> vnější\n>\n> > [!TIP]\n> > rada")

        #expect(blocks == [.quote([
            .paragraph("vnější"),
            .alert(kind: .tip, blocks: [.paragraph("rada")]),
        ])])
    }

    @Test("Obsah výstrahy se parsuje na bloky")
    func parsesBlocksInsideAnAlert() {
        let blocks = parse("> [!IMPORTANT]\n> ## Review skipped\n>\n> - [ ] Trigger review")

        #expect(blocks == [.alert(kind: .important, blocks: [
            .heading(level: 2, text: "Review skipped"),
            .listItem(marker: .task(isDone: false), indent: 0, text: "Trigger review"),
        ])])
    }

    /// **Neznámý druh se nezahazuje** — je z něj obyčejná citace, ve které ten řádek zůstane
    /// textem. Neumět něco vysázet je lepší než to spolknout.
    @Test("Neznámý druh výstrahy dá citaci, a řádek v ní zůstane")
    func keepsAnUnknownAlertKind() {
        #expect(parse("> [!FOO]\n> obsah") == [.quote([.paragraph("[!FOO]\nobsah")])])
    }

    /// Značka musí být sama na řádku, jako na GitHubu. Kdyby se brala i s pokračováním, text za ní
    /// by se ztratil v titulku výstrahy.
    @Test("Značka s textem na témže řádku výstrahu nedá")
    func refusesAnAlertMarkerWithTrailingText() {
        #expect(parse("> [!NOTE] a rovnou dál") == [.quote([.paragraph("[!NOTE] a rovnou dál")])])
    }

    @Test("Výstraha bez obsahu je výstraha bez bloků")
    func parsesAnEmptyAlert() {
        #expect(parse("> [!NOTE]") == [.alert(kind: .note, blocks: [])])
    }

    /// Druh se poznává bez ohledu na velikost písmen (tak to bere i GitHub) a v modelu se drží
    /// normalizovaně. Jde to **mimo** pomocnou `parse(_:)` s invariantem schválně: ten porovnává
    /// obsah po znacích, takže by normalizaci `note` → `NOTE` nahlásil jako ztrátu, přitom se
    /// druh kreslí titulkem.
    @Test("Malá písmena ve značce druh nezmění")
    func parsesAnAlertRegardlessOfCase() {
        #expect(MarkdownParser.parse("> [!note]\n> obsah") == [
            .alert(kind: .note, blocks: [.paragraph("obsah")]),
        ])
    }

    @Test("Tři a víc čárek dají oddělovač")
    func parsesRules() {
        #expect(parse("---") == [.rule])
        #expect(parse("***") == [.rule])
        #expect(parse("--") == [.paragraph("--")])
    }

    @Test("Tabulka zůstane surová, včetně svislítek")
    func keepsTableRows() {
        let blocks = parse("""
            | a | b |
            |---|---|
            | 1 | 2 |
            """)

        #expect(blocks == [.table(["| a | b |", "|---|---|", "| 1 | 2 |"])])
    }

    @Test("Prázdný text nedá žádný blok")
    func parsesNothing() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("\n\n  \n").isEmpty)
    }

    /// Inline značky si parser **nechává** — tučné a odkazy řeší až view přes
    /// `AttributedString`, takže je nesmí odříznout.
    @Test("Inline formátování zůstává v textu bloku")
    func leavesInlineMarkupAlone() {
        #expect(parse("**tučně** a [odkaz](https://x)") == [.paragraph("**tučně** a [odkaz](https://x)")])
    }

    // MARK: - HTML v komentářích

    /// Komentář `<!-- … -->` GitHub nevykreslí, ale v modelu **zůstává** — jinak by se ztráta
    /// textu nedala odlišit od chyby parsování.
    @Test("HTML komentář je vlastní blok, ne odstavec")
    func parsesAnHTMLComment() {
        #expect(parse("<!-- linear-linkback -->") == [.htmlComment(["<!-- linear-linkback -->"])])
    }

    @Test("HTML komentář přes víc řádků se sbalí do jednoho bloku")
    func parsesAMultilineHTMLComment() {
        let blocks = parse("<!-- první\ndruhý -->\ntext")

        #expect(blocks == [
            .htmlComment(["<!-- první", "druhý -->"]),
            .paragraph("text"),
        ])
    }

    /// Skutečný linkback od `linear-code`: komentář, rozbalovátko s odkazem v popisku
    /// a odstavce uvnitř.
    @Test("`<details>` má popisek a vnořené bloky")
    func parsesDetails() {
        let blocks = parse("""
            <!-- linear-linkback -->
            <details>
            <summary><a href="https://linear.app/x">AJDA-2222 Update Doctrine</a></summary>
            <p>
            První odstavec.
            </p>
            </details>
            """)

        #expect(blocks.count == 2)
        guard case .details(let summary, let inner) = blocks[1] else {
            Issue.record("druhý blok není rozbalovátko: \(blocks[1])")
            return
        }
        #expect(summary == "[AJDA-2222 Update Doctrine](https://linear.app/x)")
        #expect(inner == [.paragraph("<p>\nPrvní odstavec.\n</p>")])
    }

    /// Zanořené rozbalovátko se musí uzavřít tím **svým** `</details>`, ne prvním, které
    /// přijde — jinak by zbytek vnějšího obsahu vypadl.
    @Test("Zanořené `<details>` neuzavře vnější")
    func parsesNestedDetails() {
        let blocks = parse("""
            <details>
            <summary>vnější</summary>
            <details>
            <summary>vnitřní</summary>
            uvnitř
            </details>
            za vnitřním
            </details>
            """)

        guard case .details(let summary, let inner) = blocks.first else {
            Issue.record("chybí vnější rozbalovátko")
            return
        }
        #expect(summary == "vnější")
        #expect(inner.count == 2, "vnitřní rozbalovátko a odstavec za ním")
        #expect(inner.contains { if case .details = $0 { true } else { false } })
    }

    /// Useknutý komentář se nesmí vykreslit jako prázdno.
    @Test("Neuzavřené `<details>` se uzavře koncem textu")
    func closesUnterminatedDetails() {
        let blocks = parse("<details>\n<summary>popisek</summary>\nobsah")

        guard case .details(let summary, let inner) = blocks.first else {
            Issue.record("chybí rozbalovátko")
            return
        }
        #expect(summary == "popisek")
        #expect(inner == [.paragraph("obsah")])
    }

    /// Odstavec si HTML **nechává** — tagy strhává až view, aby model držel to, co přišlo
    /// z GitHubu.
    @Test("Inline HTML zůstává v textu bloku")
    func leavesInlineHTMLAlone() {
        #expect(parse("<p>text</p>") == [.paragraph("<p>text</p>")])
    }

    // MARK: - Skutečný text

    /// Popis PR ze **skutečné** fixture (`gh pr view` nad `cli/cli#13997`): parser musí projít
    /// cizí text, který nikdo nepsal pro test.
    @Test("Skutečný popis PR se rozloží bez ztráty")
    func parsesARealDescription() throws {
        let json = try Fixture.text("gh/pr-view-open.json")
        let detail = try GhOutput.decoder.decode(GhPullRequestDetail.self, from: Data(json.utf8))
        let body = try #require(detail.body)

        let blocks = parse(body)

        #expect(!blocks.isEmpty)
        #expect(blocks.contains { if case .heading = $0 { true } else { false } })
    }

    /// Skutečný komentář od `coderabbitai` (veřejné `coderabbitai/ast-grep-essentials#200`,
    /// zpráva o vyčerpaném limitu). Je to přesně ten text, kvůli kterému #279 vzniklo: `[!WARNING]`
    /// s nadpisem, odstavci, inline kódem, odkazem **a dvěma rozbalovátky uvnitř citace**.
    ///
    /// Tvrdí se na něm dvě věci, každá o jedné příčině z issue: že z citace vyšla **výstraha**
    /// a že se v ní `## Rate limit exceeded` stal **nadpisem**, ne řádkem se dvěma mřížkami.
    @Test("Skutečná zpráva od bota dá výstrahu s vysázeným obsahem")
    func parsesARealBotComment() throws {
        let body = try Fixture.text("gh/comment-coderabbit.md")

        let blocks = parse(body)

        guard case .alert(let kind, let inner) = blocks.first(where: { if case .alert = $0 { true } else { false } }) else {
            Issue.record("v komentáři není výstraha: \(blocks.prefix(3))")
            return
        }
        #expect(kind == .warning)
        #expect(inner.contains { $0 == .heading(level: 2, text: "Rate limit exceeded") })
        #expect(inner.contains { if case .details = $0 { true } else { false } })
        // A hlavně: **nikde nezůstal zdroj**. Řádek začínající `>` nebo `#` v žádném odstavci
        // znamená, že se blok nerozpoznal a v okně by stál Markdown, ne sazba.
        #expect(!paragraphs(in: blocks).contains { $0.hasPrefix(">") || $0.hasPrefix("#") })
    }

    /// Text všech odstavců, i těch zanořených — do citací, výstrah a rozbalovátek.
    private func paragraphs(in blocks: [MarkdownBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text): [text]
            case .quote(let inner), .alert(_, let inner), .details(_, let inner): paragraphs(in: inner)
            default: []
            }
        }
    }
}
