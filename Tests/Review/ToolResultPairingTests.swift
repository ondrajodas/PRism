import Foundation
import Testing

@testable import PRism

/// Párování odpovědi na pokus o nástroj s krokem v ose (#326).
///
/// Tři věci se dají pokazit potichu: **krok bez odpovědi vypadat jako hotový** (do #326 tak
/// vypadal každý), **odpověď přidat jako druhý řádek** (osa by na jeden `tool_use` měla dva kroky
/// a posunula by se na něco, co krok není) a **shodit čtení starší osy** novým polem v souboru.
@Suite("Odpověď na pokus o nástroj")
struct ToolResultPairingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func timeline(attempt id: String?, name: String = "Bash") -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: URL(filePath: "/tmp/wt"))
        timeline.record(.started(sessionID: "abc123"), at: start)
        timeline.record(.attemptedTool(ToolAttempt(name: name, detail: "gh pr view", id: id)), at: start)
        return timeline
    }

    private func tool(in timeline: ReviewerTimeline) -> ToolAttempt? {
        timeline.entries.compactMap { entry -> ToolAttempt? in
            guard case .tool(let tool) = entry.kind else { return nil }
            return tool
        }.last
    }

    // MARK: - Zavření kroku

    @Test("Úspěšná odpověď krok zavře a nese, jak dlouho se čekalo")
    func closesTheStepWithItsDuration() throws {
        var timeline = timeline(attempt: "t1")

        timeline.record(
            .resolvedTool(ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .passed))),
            at: start.addingTimeInterval(0.7)
        )

        let step = try #require(tool(in: timeline))
        #expect(step.outcome?.kind == .passed)
        // **Pásmo, ne rovnost:** osa měří rozdílem dvou `Date` a ten je v desetinách sekundy
        // nepřesný (0,7 s vyjde jako 0,7000000476837158). A pozor na `Duration.milliseconds` —
        // v testovacím targetu je to `String` (`Tests/DurationText.swift`), ne číslo z `RunUsage`.
        let after = try #require(step.outcome?.after)
        #expect(after >= .milliseconds(700))
        #expect(after < .milliseconds(710))
    }

    /// **Nepřidává řádek, mění ten, který v ose je.** Kdyby přidávala, měl by jeden `tool_use`
    /// v ose dva kroky — a `newestEntry`, podle kterého se osa posouvá na konec, by ukazoval na
    /// událost, která žádný nový krok není.
    @Test("Odpověď osu neprodlouží")
    func doesNotGrowTheTimeline() {
        var timeline = timeline(attempt: "t1")
        let before = timeline.entries

        timeline.record(
            .resolvedTool(ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .denied))),
            at: start.addingTimeInterval(1)
        )

        #expect(timeline.entries.count == before.count)
        #expect(timeline.entries.map(\.id) == before.map(\.id))
        #expect(timeline.entries.map(\.at) == before.map(\.at))
    }

    @Test("Odmítnutý krok trvání nedostane")
    func aDeniedStepCarriesNoDuration() throws {
        var timeline = timeline(attempt: "t1")

        timeline.record(
            .resolvedTool(ToolResolution(
                id: "t1",
                outcome: ToolAttempt.Outcome(kind: .denied, reason: "no permission")
            )),
            at: start.addingTimeInterval(30)
        )

        let step = try #require(tool(in: timeline))
        #expect(step.outcome?.kind == .denied)
        // Nástroj neběžel, takže by to bylo trvání toho, jak dlouho se čekalo na „ne“ — a u
        // záchrany z `permission_denials` rovnou trvání celého zbytku běhu.
        #expect(step.outcome?.after == nil)
        #expect(step.outcome?.reason == "no permission")
    }

    // MARK: - Co se spárovat nemá

    /// Odpověď na cizí `id` osu **nechá být**. Ne „zavře nejbližší krok“ — to by u zabité session
    /// zavřelo zrovna ten krok, který zůstat otevřený má.
    @Test("Odpověď na neznámý krok nezmění nic")
    func changesNothingForAnUnknownIdentifier() throws {
        var timeline = timeline(attempt: "t1")

        timeline.record(
            .resolvedTool(ToolResolution(id: "jiné", outcome: ToolAttempt.Outcome(kind: .passed))),
            at: start.addingTimeInterval(1)
        )

        #expect(try #require(tool(in: timeline)).outcome == nil)
    }

    /// Krok bez `id` (osa uložená před #326) se nespáruje **nikdy** — ani s odpovědí, která
    /// přijde jako jediná.
    @Test("Krok bez id se nespáruje")
    func neverPairsAStepWithoutAnIdentifier() throws {
        var timeline = timeline(attempt: nil)

        timeline.record(
            .resolvedTool(ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .passed))),
            at: start.addingTimeInterval(1)
        )

        #expect(try #require(tool(in: timeline)).outcome == nil)
    }

    /// Druhá odpověď na tentýž krok ho nepřepíše: platí ta, která přišla, když se to stalo.
    @Test("Zavřený krok se podruhé nezavírá")
    func keepsTheFirstAnswer() throws {
        var timeline = timeline(attempt: "t1")
        let passed = ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .passed))
        timeline.record(.resolvedTool(passed), at: start.addingTimeInterval(0.2))

        timeline.record(
            .resolvedTool(ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .denied))),
            at: start.addingTimeInterval(9)
        )

        #expect(try #require(tool(in: timeline)).outcome?.kind == .passed)
    }

    /// Posunuté systémové hodiny nesmí do osy zapsat záporné trvání — tatáž pojistka jako
    /// u `RunUsageText.elapsed`.
    @Test("Záporné trvání se nezapíše")
    func neverWritesANegativeDuration() throws {
        var timeline = timeline(attempt: "t1")

        timeline.record(
            .resolvedTool(ToolResolution(id: "t1", outcome: ToolAttempt.Outcome(kind: .passed))),
            at: start.addingTimeInterval(-5)
        )

        #expect(try #require(tool(in: timeline)).outcome?.after == .zero)
    }

    // MARK: - Uložení a starší soubory

    @Test("Zavřený krok přežije kolečko přes JSON")
    func survivesAJSONRoundTrip() throws {
        var source = timeline(attempt: "t1")
        source.record(
            .resolvedTool(ToolResolution(
                id: "t1",
                outcome: ToolAttempt.Outcome(kind: .failed, reason: "Exit code 1")
            )),
            at: start.addingTimeInterval(1.5)
        )

        let data = try JSONEncoder().encode(source.stored())
        let decoded = try JSONDecoder().decode(StoredTimeline.self, from: data)

        #expect(decoded == source.stored())
        let text = try #require(String(data: data, encoding: .utf8))
        // Klíč nese jednotku, aby se do souboru dalo kouknout — `Duration` se `Codable`m kóduje
        // jako dvojice int128. Tatáž úmluva jako u `RunUsage`.
        #expect(text.contains("\"afterMS\":1500"))
        #expect(text.contains("\"kind\":\"failed\""))
    }

    /// **Osa uložená před #326 se musí načíst.** Nová pole jsou volitelná, takže je syntetizovaný
    /// dekodér bere přes `decodeIfPresent` — kdyby ne, spadlo by čtení celého záznamu a s ním
    /// zmizely nálezy, které v souboru leží vedle.
    ///
    /// Literál je tvar, který zapisoval encoder před #326: `id` ani `outcome` v něm nejsou. Že je
    /// to pořád **tentýž** tvar, hlídá test pod ním — pokus bez `id` se dneska ukládá stejně.
    @Test("Osa uložená před #326 se načte i bez nových polí")
    func readsATimelineStoredBeforeTheChange() throws {
        let json = """
            {"dropped":3,"worktree":"file:///tmp/wt","entries":[\
            {"kind":{"started":{}},"at":-977307200,"id":0},\
            {"kind":{"tool":{"_0":{"detail":"a.php","name":"Read"}}},"at":-977307199,"id":1}]}
            """

        let decoded = try JSONDecoder().decode(StoredTimeline.self, from: Data(json.utf8))

        #expect(decoded.entries.count == 2)
        #expect(decoded.dropped == 3)
        guard case .tool(let tool) = decoded.entries.last?.kind else {
            Issue.record("poslední událost není nástroj")
            return
        }
        #expect(tool.name == "Read")
        #expect(tool.detail == "a.php")
        #expect(tool.id == nil)
        #expect(tool.outcome == nil)
        // A hlavně: takový krok se v ose nesmí kreslit jako běžící. Odpověď se mu neměla s čím
        // spárovat, takže o něm nevíme nic — `běží…` u kroku doběhlého review z minulého týdne
        // je text, který tvrdí víc, než data unesou.
        #expect(Policy.toolStepMark(of: tool) == ToolStepMark.none)
    }

    /// Pojistka k testu výš: kdyby se nová pole začala ukládat i s `nil` hodnotou, přestal by ten
    /// literál být tvarem, jaký na disku doopravdy leží — a doklad o zpětné kompatibilitě by
    /// mlčky přestal platit.
    @Test("Pokus bez id a bez odpovědi se ukládá bez nových klíčů")
    func storesNothingExtraForAnUnpairedAttempt() throws {
        let data = try JSONEncoder().encode(timeline(attempt: nil, name: "Read").stored())

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("\"id\":\""))
        #expect(!text.contains("outcome"))
    }
}
