import Foundation
import Testing

@testable import PRism

@Suite("StreamParser")
struct StreamParserTests {
    private let parser = StreamParser()

    private func summary(of fixture: String) throws -> StreamSummary {
        parser.summarize(try Fixture.text("stream-json/\(fixture).jsonl").split(separator: "\n").map(String.init))
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
        #expect(result.attemptedTools.contains("Write"))
    }

    @Test("Nástroje, o které si reviewer řekl, se dají vyjmenovat")
    func listsToolsThatWereAttempted() throws {
        let result = try summary(of: "review-with-findings")

        #expect(result.attemptedTools.contains("Read"))
        #expect(result.attemptedTools.contains("ReportFindings"))
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
