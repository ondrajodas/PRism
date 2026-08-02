import Testing

@testable import PRism

/// Obarvení řádku kódu. Není to parser jazyka — jde o to, aby se v diffu chytlo oko.
@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
    private func runs(_ line: String, _ language: Language) -> [SyntaxRun] {
        let runs = SyntaxHighlighter.runs(of: line, in: language)
        // Invariant, na kterém stojí všechno ostatní: obarvení nesmí text změnit.
        #expect(runs.map(\.text).joined() == line)
        return runs
    }

    private func kinds(_ line: String, _ language: Language) -> [SyntaxKind] {
        runs(line, language).map(\.kind)
    }

    private func text(_ line: String, _ language: Language, of kind: SyntaxKind) -> [String] {
        runs(line, language).filter { $0.kind == kind }.map(\.text)
    }

    @Test("Obyčejný řádek zůstane jednobarevný")
    func leavesPlainTextAlone() {
        #expect(kinds("    let x = y", .swift).allSatisfy { $0 == .plain || $0 == .keyword })
    }

    @Test("Prázdný řádek nic nevrátí")
    func handlesAnEmptyLine() {
        #expect(SyntaxHighlighter.runs(of: "", in: .swift).isEmpty)
    }

    // MARK: - Komentáře

    @Test("Komentář jde do konce řádku")
    func marksALineComment() {
        #expect(text("let x = 1  // proč to tady je", .swift, of: .comment) == ["// proč to tady je"])
    }

    @Test("Mřížka je komentář tam, kde jazyk komentáře mřížkou má")
    func marksAHashComment() {
        #expect(text("key: value  # poznámka", .yaml, of: .comment) == ["# poznámka"])
        // V Go mřížka komentář neuvozuje, takže se nesmí obarvit.
        #expect(text("x := 1 # tohle není komentář", .go, of: .comment).isEmpty)
    }

    @Test("Blokový komentář na jednom řádku")
    func marksABlockComment() {
        #expect(text("let x = /* proč */ 1", .swift, of: .comment) == ["/* proč */"])
    }

    /// Blok, který na řádku nekončí, obarvíme do konce řádku. Dál to nejde: diff je
    /// útržek a mezi hunky chybí řádky, ze kterých by se stav dopočítal.
    @Test("Neuzavřený blokový komentář končí s řádkem")
    func endsAnUnterminatedBlockCommentWithTheLine() {
        #expect(text("let x = 1 /* pokračuje jinde", .swift, of: .comment) == ["/* pokračuje jinde"])
    }

    // MARK: - Řetězce

    @Test("Řetězec se pozná i s uvozovkami")
    func marksAString() {
        #expect(text("echo \"ahoj\"", .shell, of: .string) == ["\"ahoj\""])
    }

    @Test("Komentář uvnitř řetězce zůstává řetězcem")
    func neverTreatsACommentInsideAStringAsAComment() {
        #expect(text("let x = \"// tohle není komentář\"", .swift, of: .comment).isEmpty)
        #expect(text("let x = \"// tohle není komentář\"", .swift, of: .string) == ["\"// tohle není komentář\""])
    }

    @Test("Uvozovka uvnitř komentáře nezačíná řetězec")
    func neverStartsAStringInsideAComment() {
        #expect(text("// říká \"ahoj\"", .swift, of: .string).isEmpty)
    }

    @Test("Escapovaná uvozovka řetězec neukončí")
    func keepsAStringOpenAcrossAnEscapedQuote() {
        #expect(text(#"let x = "a \" b""#, .swift, of: .string) == [#""a \" b""#])
    }

    @Test("Neuzavřený řetězec končí s řádkem")
    func endsAnUnterminatedStringWithTheLine() {
        #expect(text("let x = \"nedokončeno", .swift, of: .string) == ["\"nedokončeno"])
    }

    @Test("Apostrof v jazyce, který ho jako uvozovku nemá, řetězec nezačíná")
    func ignoresQuotesTheLanguageDoesNotUse() {
        // Ve Swiftu je apostrof obyčejný znak — jinak by ho každý anglický komentář
        // v kódu rozsvítil až do konce řádku.
        #expect(text("let x = 1 // don't", .swift, of: .string).isEmpty)
    }

    // MARK: - Klíčová slova a čísla

    @Test("Klíčové slovo se pozná")
    func marksAKeyword() {
        #expect(text("func run() {", .swift, of: .keyword) == ["func"])
    }

    @Test("Klíčové slovo uvnitř delšího jména se nepočítá")
    func neverMarksAKeywordInsideAnIdentifier() {
        #expect(text("let functional = 1", .swift, of: .keyword) == ["let"])
    }

    @Test("Čísla se poznají")
    func marksNumbers() {
        #expect(text("let x = 42 + 3.14", .swift, of: .number) == ["42", "3.14"])
    }

    @Test("Číslice uvnitř jména není číslo")
    func neverMarksDigitsInsideAnIdentifier() {
        #expect(text("let utf8 = encoding2", .swift, of: .number).isEmpty)
    }

    // MARK: - Proměnné

    /// Jen tam, kde je proměnná poznat ze syntaxe. V PHP a shellu ji uvozuje `$`;
    /// ve Swiftu nebo Go by se musel rozumět kód, ne řádek.
    @Test("Proměnná s dolarem se pozná")
    func marksASigilVariable() {
        #expect(text("$retryConfig = 1;", .php, of: .variable) == ["$retryConfig"])
        #expect(text("echo $HOME", .shell, of: .variable) == ["$HOME"])
    }

    @Test("Proměnná ve složených závorkách")
    func marksABracedVariable() {
        #expect(text("echo \"x\" ${HOME}/bin", .shell, of: .variable) == ["${HOME}"])
    }

    @Test("Za dolarem se barví jen proměnná, ne to, co následuje")
    func stopsAtTheEndOfTheVariableName() {
        #expect(text("$this->log($name);", .php, of: .variable) == ["$this", "$name"])
    }

    @Test("Osamocený dolar proměnná není")
    func neverMarksALoneSigil() {
        #expect(text("// cena v $ za kus", .php, of: .variable).isEmpty)
    }

    @Test("Dolar v jazyce bez proměnných se nebarví")
    func ignoresTheSigilWhereTheLanguageHasNoVariables() {
        // Ve Swiftu je `$0` argument uzávěry, ne proměnná se jménem — a rozeznat to od
        // sebe by chtělo rozumět kódu, ne řádku.
        #expect(text("array.map { $0.name }", .swift, of: .variable).isEmpty)
    }

    @Test("Proměnná uvnitř řetězce zůstává řetězcem")
    func keepsVariablesInsideStringsAsStrings() {
        // Rozbíjet řetězec na kusy by znamenalo dvě barvy v jedné uvozovkované hodnotě;
        // řetězec je tady silnější pravidlo.
        #expect(text("$this->log(\"běží $name\");", .php, of: .string) == ["\"běží $name\""])
        #expect(text("$this->log(\"běží $name\");", .php, of: .variable) == ["$this"])
    }

    // MARK: - Jazyky bez klíčových slov

    @Test("V Markdownu se barví jen kód v apostrofech")
    func marksOnlyCodeSpansInMarkdown() {
        #expect(text("běžný text s `kódem` uvnitř", .markdown, of: .string) == ["`kódem`"])
        #expect(text("# nadpis, ne komentář", .markdown, of: .comment).isEmpty)
    }

    @Test("V JSONu se barví klíče, hodnoty a čísla")
    func marksJSON() {
        let line = #"  "limit": 100,"#
        #expect(text(line, .json, of: .string) == [#""limit""#])
        #expect(text(line, .json, of: .number) == ["100"])
    }

    // MARK: - Diakritika

    /// Řetězce a komentáře v tomhle repu jsou české, takže se nesmí rozpadnout na
    /// vícebajtových znacích.
    @Test("Diakritika text nerozhodí")
    func keepsAccentedTextIntact() {
        #expect(text("// příliš žluťoučký kůň", .swift, of: .comment) == ["// příliš žluťoučký kůň"])
        #expect(text("let x = \"úpěl ďábelské ódy\"", .swift, of: .string) == ["\"úpěl ďábelské ódy\""])
    }
}
