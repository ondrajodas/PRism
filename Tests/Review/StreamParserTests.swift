import Foundation
import Testing

@testable import PRism

@Suite("StreamParser")
struct StreamParserTests {
    private let parser = StreamParser()

    /// **`TextLines`, ne `split(separator: "\n")`** — pravidlo repa (#292, #295) platí i v testech.
    private func summary(of fixture: String) throws -> StreamSummary {
        parser.summarize(TextLines.content(try Fixture.text("stream-json/\(fixture).jsonl")).map(String.init))
    }

    // MARK: - Proti skutečným streamům

    @Test("Ze streamu s nálezy vypadnou nálezy")
    func readsFindingsFromARealRun() throws {
        let result = try summary(of: "review-with-findings")

        #expect(result.calledReportFindings)
        #expect(result.findings.count == 4)
        let first = try #require(result.findings.first)
        #expect(first.file == "Cart.swift")
        #expect(first.line == 13)
        #expect(first.category == "correctness")
        #expect(first.verdict == .confirmed)
        #expect(first.summary.isEmpty == false)
        #expect(first.failureScenario?.isEmpty == false)
        // Dva ze čtyř nálezů leží na **tomtéž řádku** (`Cart.swift:17`) a přišly v jednom
        // volání. Je to doklad, že reviewer dva různé problémy na jeden řádek doopravdy
        // dává — proto se položky uvnitř jedné sady neslévají (#381).
        #expect(result.findings.filter { $0.file == "Cart.swift" && $0.line == 17 }.count == 2)
    }

    @Test("Opravené hlášení téhož nálezu je v okně jednou")
    func aCorrectedReportOfTheSameFindingIsOne() throws {
        // Fixture je poskládaná z uloženého záznamu z provozu (#381): reviewer zavolal
        // `ReportFindings` dvakrát, protože si první text opravil — do češtiny mu prosákla
        // ruština. V okně z toho byl týž nález dvakrát, oba `CONFIRMED` a oba na jednom
        // řádku, i když jeho vlastní log hlásil jeden.
        let result = try summary(of: "report-findings-corrected")

        #expect(result.findings.count == 1)
        let finding = try #require(result.findings.first)
        #expect(finding.file == "src/Flow/Conditional/PhaseTransitionHandler.php")
        #expect(finding.line == 346)
        #expect(finding.verdict == .confirmed)
        #expect(finding.category == "correctness")
        // Vyhrát má **pozdější** hlášení, tedy to opravené. Cyrilice je zrovna to, po čem
        // se první hlášení pozná: kdyby zůstalo, zbyla by v nálezu ruská slova.
        #expect(finding.shortSummary == "Chybná fáze zápisu: porušení atomicity")
        #expect(cyrillic(in: finding).isEmpty)
        // Přebitý nález **není** zahozený nález: `droppedFindings` je počítadlo nepřečteného
        // a rozsvítilo by v okně „nejisté“.
        #expect(result.droppedFindings == 0)
        #expect(result.outcome?.isError == false)
    }

    @Test("Fixture s korekcí nese cyrilici z prvního hlášení")
    func theCorrectionFixtureCarriesTheCyrillicFromTheFirstReport() throws {
        // Hlídá si to sada sama, ať test výš neplatí jen proto, že se z fixture cestou do
        // repa ztratily bajty, na kterých stojí. Tatáž pojistka jako u fixtures s `CRLF`.
        let text = try Fixture.text("stream-json/report-findings-corrected.jsonl")

        #expect(text.contains("второй"))
        #expect(text.contains("условие"))
    }

    /// Cyrilice v textech nálezu — čím se první (neopravené) hlášení pozná.
    private func cyrillic(in finding: ReportedFinding) -> String {
        let texts = [finding.summary, finding.shortSummary, finding.failureScenario]
        return String(texts.compactMap { $0 }.joined().unicodeScalars.filter {
            (0x0400...0x04FF).contains($0.value)
        }.map(Character.init))
    }

    @Test("Čistý běh nástroj zavolá, jen s prázdným seznamem")
    func aCleanRunStillCallsTheTool() throws {
        // Rozdíl proti běhu, který nástroj nezavolal vůbec — a ten rozdíl je podstatný:
        // „nic jsem nenašel“ není totéž co „nereportoval jsem“.
        let result = try summary(of: "review-clean")

        #expect(result.calledReportFindings)
        #expect(result.findings.isEmpty)
    }

    @Test("Session id se přečte z init eventu")
    func readsTheSessionIdentifier() throws {
        #expect(try summary(of: "review-with-findings").sessionID?.isEmpty == false)
    }

    @Test("Doběhlý běh je poznat podle result eventu")
    func finishedRunHasAnOutcome() throws {
        #expect(try summary(of: "review-with-findings").outcome?.isError == false)
    }

    @Test("Zabitý běh result event nemá")
    func killedRunHasNoOutcome() throws {
        // Jediný způsob, jak „doběhlo“ odlišit od „bylo zabito“ — ověřeno u #12.
        let result = try summary(of: "review-killed")

        #expect(result.outcome == nil)
        #expect(result.calledReportFindings == false)
    }

    @Test("Odmítnutý nástroj není chyba běhu")
    func aDeniedToolIsNotAFailedRun() throws {
        let result = try summary(of: "review-denied-write")

        #expect(result.outcome?.isError == false)
        #expect(result.deniedTools == ["Write"])
        // `Write` se **nepoužil**, jen se o něj řeklo — v tabu Průběh se to nesmí slít.
        #expect(result.attemptedTools.map(\.name).contains("Write"))
    }

    @Test("Nástroje, o které si reviewer řekl, se dají vyjmenovat")
    func listsToolsThatWereAttempted() throws {
        let result = try summary(of: "review-with-findings")

        #expect(result.attemptedTools.map(\.name).contains("Read"))
        #expect(result.attemptedTools.map(\.name).contains("ReportFindings"))
    }

    /// Samotné „Read“ v tabu Průběh nic neřekne — zajímavé je, **co** reviewer četl.
    @Test("Pokus o nástroj nese i to, nad čím běžel")
    func carriesWhatTheToolRanOn() throws {
        let result = try summary(of: "review-with-findings")

        let read = try #require(result.attemptedTools.first { $0.name == "Read" })
        #expect(read.detail?.hasSuffix(".swift") == true)
    }

    @Test("Detail se bere podle nástroje", arguments: [
        (#"{"pattern": "TODO"}"#, "Grep", "TODO"),
        (#"{"command": "git diff --stat"}"#, "Bash", "git diff --stat"),
        (#"{"file_path": "/tmp/x.swift"}"#, "Read", "/tmp/x.swift"),
        (#"{"path": "/tmp"}"#, "Glob", "/tmp"),
    ])
    func picksTheDetailByTool(input: String, tool: String, expected: String) throws {
        let line = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","name":"\(tool)","input":\(input)}]}}
            """

        let attempt = try #require(parser.summarize([line]).attemptedTools.first)

        #expect(attempt.name == tool)
        #expect(attempt.detail == expected)
    }

    @Test("Nástroj, ze kterého se nic vytáhnout nedá, detail nemá")
    func hasNoDetailWhenThereIsNothingToShow() throws {
        let line = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Divné","input":{"x":1}}]}}
            """

        #expect(parser.summarize([line]).attemptedTools.first?.detail == nil)
    }

    // MARK: - Odolnost

    @Test("Poškozený řádek parser nepoloží")
    func survivesAMalformedLine() {
        let result = parser.summarize([
            "{tohle není json",
            #"{"type":"system","subtype":"init","session_id":"abc"}"#,
            "",
        ])

        #expect(result.sessionID == "abc")
        #expect(result.malformedLines == 1)
    }

    @Test("Useknutý poslední řádek se přeskočí")
    func survivesATruncatedTrailingLine() {
        // Zabitý proces umí useknout řádek uprostřed.
        let result = parser.summarize([
            #"{"type":"system","subtype":"init","session_id":"abc"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x","name":"Rep"#,
        ])

        #expect(result.sessionID == "abc")
        #expect(result.malformedLines == 1)
    }

    @Test("Neznámý typ eventu se tiše přeskočí")
    func unknownEventsAreSkipped() {
        let result = parser.summarize([
            #"{"type":"neco_uplne_jineho","payload":42}"#,
            #"{"type":"system","subtype":"init","session_id":"abc"}"#,
        ])

        #expect(result.sessionID == "abc")
        #expect(result.malformedLines == 0)
    }

    @Test("Nález bez řádku i bez souboru je platný")
    func findingsWithoutFileOrLineAreValid() {
        // Chybějící testy nebo architektonická poznámka nepatří k žádnému řádku — a mají
        // se dostat do tabulky, ne zmizet.
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":{"findings":[{"summary":"Chybí testy","failure_scenario":"Nic to nekryje."}]}}]}}"#

        let result = parser.summarize([line])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.file == nil)
        #expect(result.findings.first?.line == nil)
    }

    @Test("Zahozený nález se spočítá, ne aby se běh tvářil jako čistý")
    func countsDroppedFindings() {
        // Bez počítadla je „nález bez povinného pole“ k nerozeznání od „nic jsem nenašel“
        // — tedy od schváleného PR s neohlášenou chybou.
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":{"findings":[{"file":"a.swift"},{"summary":"ok"}]}}]}}"#

        let result = parser.summarize([line])

        #expect(result.calledReportFindings)
        #expect(result.findings.count == 1)
        #expect(result.droppedFindings == 1)
    }

    @Test("Nečitelný obsah volání se taky spočítá")
    func countsAnUnreadableToolInput() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":"tohle není objekt"}]}}"#

        let result = parser.summarize([line])

        #expect(result.calledReportFindings)
        #expect(result.droppedFindings == 1)
    }

    @Test("Nález bez scénáře selhání se nezahazuje")
    func aFindingWithoutAFailureScenarioSurvives() {
        // Povinné je jen `summary`. Jiný skill nemusí scénář vyplňovat vůbec a nemá kvůli
        // tomu o nález přijít.
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":{"findings":[{"summary":"Něco je špatně"}]}}]}}"#

        let result = parser.summarize([line])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.failureScenario == nil)
        #expect(result.droppedFindings == 0)
    }

    @Test("Stejný nález ze dvou volání se nezdvojí")
    func doesNotDuplicateFindingsReportedTwice() {
        // Reviewer, který hlásí průběžně a na konci pošle kompletní seznam, je běžný.
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":{"findings":[{"summary":"s","failure_scenario":"f"}]}}]}}"#

        let result = parser.summarize([line, line])

        #expect(result.findings.count == 1)
    }

    @Test("Přeformulovaný popisek z nálezu druhý nález neudělá")
    func aRewordedShortSummaryIsStillTheSameFinding() {
        // Ověřeno na skutečném běhu (#17): reviewer nahlásil tentýž problém průběžně
        // a znovu v závěrečném seznamu, jen si mezitím upravil `short_summary`.
        // Porovnání celé hodnoty ho propustilo a v UI byl dvakrát. Od #381 to nedrží
        // shodné `summary`, ale shodné **místo** — u #381 se totiž přeformulovalo i ono.
        func call(shortSummary: String) -> String {
            """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
            "name":"ReportFindings","input":{"findings":[{"file":"A.php","line":96,\
            "summary":"delay node je inertní","short_summary":"\(shortSummary)"}]}}]}}
            """
        }

        let result = parser.summarize([
            call(shortSummary: "delay node can never match anything"),
            call(shortSummary: "delay node can never match"),
        ])

        #expect(result.findings.count == 1)
    }

    @Test("Doplněný verdikt a kategorie z druhého hlášení přebijí náčrt")
    func aLaterReportReplacesTheDraft() {
        // Průběžné hlášení bývá náčrt. Kdyby vyhrálo, přišel by nález o `verdict`
        // a `category` — a s nimi o blokující příznak, tedy o jediný odvozený boolean.
        let draft = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
        "name":"ReportFindings","input":{"findings":[{"file":"A.php","line":96,\
        "summary":"ztráta dat"}]}}]}}
        """
        let complete = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2",\
        "name":"ReportFindings","input":{"findings":[{"file":"A.php","line":96,\
        "summary":"ztráta dat","category":"data-loss","verdict":"CONFIRMED"}]}}]}}
        """

        let result = parser.summarize([draft, complete])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.verdict == .confirmed)
        #expect(result.findings.first?.category == "data-loss")
    }

    @Test("Dva různé problémy na jednom řádku zůstanou dva")
    func twoDifferentProblemsOnOneLineStayTwo() {
        // Uvnitř **jedné sady** se neslévá nic: reviewer je vyjmenoval vedle sebe, takže
        // jsou to dva problémy. Doložené reálným během (`review-with-findings`,
        // `Cart.swift:17`), takže slití podle `(file, line, category)` do parseru nepatří.
        let call = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
            "name":"ReportFindings","input":{"findings":[\
            {"file":"A.php","line":96,"category":"correctness","summary":"chybí kontrola prázdnosti"},\
            {"file":"A.php","line":96,"category":"correctness","summary":"celočíselné dělení useká zbytek"}\
            ]}}]}}
            """

        #expect(parser.summarize([call]).findings.count == 2)
    }

    @Test("Nález, o kterém pozdější volání mlčí, se nezahodí")
    func aFindingMissingFromTheLastReportIsNotDropped() {
        // Ztracený nález vypadá v okně jako „reviewer nic nenašel“, což je nejhorší možné
        // selhání téhle aplikace. Poslední sada proto přepisuje jen to, co sama nese —
        // zbytek zůstane a `droppedFindings` (počítadlo **nepřečteného**) se nehýbe.
        func call(file: String, line: Int) -> String {
            """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
            "name":"ReportFindings","input":{"findings":[{"file":"\(file)","line":\(line),\
            "summary":"ztráta dat"}]}}]}}
            """
        }

        let result = parser.summarize([call(file: "A.php", line: 10), call(file: "B.php", line: 20)])

        #expect(result.findings.count == 2)
        #expect(result.droppedFindings == 0)
    }

    @Test("Závěrečné volání s prázdným seznamem nálezy nesmaže")
    func anEmptyFinalReportDoesNotWipeFindings() {
        // Kdyby smazalo, běh s nahlášenou ztrátou dat by v okně vyšel jako čisté review.
        let withFinding = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
            "name":"ReportFindings","input":{"findings":[{"file":"A.php","line":10,\
            "summary":"ztráta dat"}]}}]}}
            """
        let empty = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"ReportFindings","input":{"findings":[]}}]}}"#

        let result = parser.summarize([withFinding, empty])

        #expect(result.findings.count == 1)
        #expect(result.droppedFindings == 0)
    }

    @Test("Nečitelné druhé volání nálezy nesmaže, jen se spočítá")
    func anUnreadableSecondReportDoesNotWipeFindings() {
        // Nečitelný vstup **není sada** — je to selhání čtení. Kdyby přepisoval, jedna
        // rozbitá řádka by zahodila nálezy, které už dorazily.
        let withFinding = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1",\
            "name":"ReportFindings","input":{"findings":[{"file":"A.php","line":10,\
            "summary":"ztráta dat"}]}}]}}
            """
        let broken = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"ReportFindings","input":"tohle není objekt"}]}}"#

        let result = parser.summarize([withFinding, broken])

        #expect(result.findings.count == 1)
        #expect(result.droppedFindings == 1)
    }

    @Test("Číslo řádku snese text, ale ne boolean")
    func readsLineNumbersDefensively() {
        // `JSONSerialization` mapuje `true` na `NSNumber`, takže z něj `as? Int` udělá
        // řádek 1 — nález by ukázal na cizí místo v souboru.
        func line(_ raw: String) -> Int? {
            let json = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"ReportFindings","input":{"findings":[{"summary":"s","line":"# + raw + #"}]}}]}}"#
            return parser.summarize([json]).findings.first?.line
        }

        #expect(line("13") == 13)
        #expect(line("\"13\"") == 13)
        #expect(line("true") == nil)
        // Neceločíselné by se oříznulo na jiný řádek, nula a záporná čísla neexistují —
        // nález bez řádku je lepší než nález ukazující jinam.
        #expect(line("13.5") == nil)
        #expect(line("0") == nil)
        #expect(line("-3") == nil)
    }

    @Test("Session id se přečte i bez init eventu")
    func readsTheSessionIdentifierFromAnyEvent() {
        // U useknutého začátku je to jediná cesta — a zrovna u zabitého běhu je session id
        // to, s čím se dá pokračovat přes `claude --resume`.
        let result = parser.summarize([
            #"{"type":"assistant","session_id":"xyz","message":{"content":[]}}"#,
        ])

        #expect(result.sessionID == "xyz")
    }

    @Test("Zabitý běh si session id nese")
    func aKilledRunStillCarriesItsSessionIdentifier() throws {
        #expect(try summary(of: "review-killed").sessionID?.isEmpty == false)
    }

    @Test("Chybu běhu parser přizná")
    func reportsAFailedRun() {
        let result = parser.summarize([
            #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#,
        ])

        #expect(result.outcome?.isError == true)
        #expect(result.outcome?.subtype == "error_during_execution")
        #expect(result.outcome?.text == "boom")
    }

    @Test("Prázdný vstup dá prázdný výsledek, ne pád")
    func emptyInputIsHandled() {
        let result = parser.summarize([])

        #expect(result.findings.isEmpty)
        #expect(result.sessionID == nil)
        #expect(result.outcome == nil)
    }

    @Test("Neznámý verdikt se nehádá")
    func unknownVerdictIsNotGuessed() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"ReportFindings","input":{"findings":[{"summary":"s","failure_scenario":"f","verdict":"MOZNA"}]}}]}}"#

        #expect(parser.summarize([line]).findings.first?.verdict == nil)
    }
}
