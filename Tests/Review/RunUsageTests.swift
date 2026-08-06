import Foundation
import Testing

@testable import PRism

/// Cena, trvání a počet kol z `result` eventu (#148).
///
/// Proti **skutečným** streamům, protože čísla v nich jsou to jediné, co dokazuje, že se
/// čtou správná pole: `duration_ms` je celé trvání, kdežto `duration_api_ms` vedle něj je
/// jen čas v API a liší se o stovky milisekund.
@Suite("Cena běhu")
struct RunUsageTests {
    private let parser = StreamParser()

    private func summary(of fixture: String) throws -> StreamSummary {
        parser.summarize(try Fixture.text("stream-json/\(fixture).jsonl").split(separator: "\n").map(String.init))
    }

    @Test("Cena, trvání a počet kol se přečtou z result eventu")
    func readsUsageFromARealRun() throws {
        let usage = try #require(try summary(of: "review-with-findings").usage)

        #expect(usage.cost == 0.3273015)
        #expect(usage.duration == .milliseconds(49523))
        #expect(usage.turns == 3)
    }

    @Test("Čistý běh cenu má taky")
    func readsUsageFromACleanRun() throws {
        let usage = try #require(try summary(of: "review-clean").usage)

        #expect(usage.cost == 0.23157300000000003)
        #expect(usage.duration == .milliseconds(11809))
        #expect(usage.turns == 3)
    }

    @Test("Běh s odmítnutým zápisem cenu má taky")
    func readsUsageFromADeniedRun() throws {
        let usage = try #require(try summary(of: "review-denied-write").usage)

        #expect(usage.cost == 0.1404495)
        #expect(usage.turns == 2)
    }

    /// To nejdůležitější v celém issue: zabitý běh `result` event nemá, takže o ceně nevíme
    /// nic — a nula by tvrdila, že byl zdarma.
    @Test("Zabitý běh cenu nemá, a nemá ani nulu")
    func aKilledRunHasNoUsage() throws {
        let result = try summary(of: "review-killed")

        #expect(result.outcome == nil)
        #expect(result.usage == nil)
    }

    // MARK: - Co umí přijít místo čísla

    private func usage(inResult fields: String) -> RunUsage? {
        var summary = StreamSummary()
        parser.consume(#"{"type":"result","is_error":false,"subtype":"success",\#(fields)}"#, into: &summary)
        return summary.usage
    }

    /// `JSONSerialization` mapuje `true` na `NSNumber`, takže bez kontroly by z něj vyšla
    /// cena 1 $.
    @Test("Boolean není cena")
    func rejectsBooleans() {
        #expect(usage(inResult: #""total_cost_usd":true,"num_turns":true"#) == nil)
    }

    /// Záporná cena by šla do denního součtu a **snížila by ho** — tedy tvrdila, že mě běh
    /// vydělal.
    @Test("Záporná hodnota se zahodí")
    func rejectsNegativeValues() {
        #expect(usage(inResult: #""total_cost_usd":-1,"duration_ms":-5,"num_turns":-2"#) == nil)
    }

    /// `Int(_:)` nad `Double`m mimo rozsah **spadne**, nevrátí chybu — a parser, který nikdy
    /// nevyhodí výjimku, o to míň smí položit celý proces. Chytila to vlastní revize diffu.
    @Test("Nesmyslně velké číslo parser nepoloží")
    func survivesHugeNumbers() throws {
        let huge = try #require(usage(inResult: #""total_cost_usd":1e300,"duration_ms":1e300,"num_turns":1e300"#))

        #expect(huge.cost == 1e300)
        #expect(huge.duration == nil)
        #expect(huge.turns == nil)
    }

    /// Desetinné `num_turns` by po `Int(_:)` prošlo oříznutím tiše; tady se aspoň nezmění
    /// v nesmysl a řádek se z něj nestane.
    @Test("Desetinné trvání se ořízne dolů")
    func roundsFractionalValuesDown() throws {
        let fractional = try #require(usage(inResult: #""duration_ms":11809.7"#))

        #expect(fractional.duration == .milliseconds(11809))
    }

    @Test("Result bez čísel žádnou cenu nedá")
    func aResultWithoutNumbersHasNoUsage() {
        #expect(usage(inResult: #""result":"hotovo""#) == nil)
    }

    /// Prázdný obal by se od „nevíme“ nedal odlišit, ale chybějící **jedno** pole ostatní
    /// zahodit nesmí.
    @Test("Chybějící pole ostatní nezahodí")
    func keepsWhatArrived() throws {
        let partial = try #require(usage(inResult: #""total_cost_usd":0.5"#))

        #expect(partial.cost == 0.5)
        #expect(partial.duration == nil)
        #expect(partial.turns == nil)
    }

    // MARK: - Na disk a zpátky

    @Test("Cena přežije Codable")
    func survivesCodable() throws {
        let usage = RunUsage(cost: 0.25, duration: .milliseconds(11809), turns: 3)

        #expect(try roundTrip(usage) == usage)
    }

    /// Tvar na disku je vlastní, ne syntetizovaný: `Duration` se sám kóduje jako dvojice
    /// celých čísel int128 a v souboru, do kterého se dá kouknout, je to nečitelné.
    @Test("Na disku jsou milisekundy, ne komponenty Duration")
    func storesMillisecondsOnDisk() throws {
        let data = try JSONEncoder().encode(RunUsage(cost: 0.25, duration: .milliseconds(11809), turns: 3))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["durationMS"] as? Int == 11809)
        #expect(object["costUSD"] as? Double == 0.25)
        #expect(object["turns"] as? Int == 3)
    }

    @Test("Prázdná cena se pozná")
    func knowsWhenItIsEmpty() {
        #expect(RunUsage().isEmpty)
        #expect(!RunUsage(turns: 1).isEmpty)
    }

    // MARK: - Texty

    @Test("Řádek u revieweera vynechá, co nedorazilo")
    func summaryTextSkipsMissingValues() throws {
        let full = try #require(RunUsageText.summary(of: RunUsage(cost: 0.25, duration: .seconds(12), turns: 3)))
        let partial = try #require(RunUsageText.summary(of: RunUsage(turns: 3)))

        #expect(full.components(separatedBy: " · ").count == 3)
        #expect(partial == "3 kola")
    }

    /// Prázdný text by se v hlavičce kreslil jako prázdné místo, kterému nikdo nerozumí.
    @Test("Prázdná cena text nedá")
    func emptyUsageHasNoText() {
        #expect(RunUsageText.summary(of: RunUsage()) == nil)
    }

    /// Pod minutou vteřiny s desetinou, nad ní minuty — u dvou minut nikoho desetina nezajímá.
    @Test("Trvání se pod minutou píše s desetinou")
    func formatsShortDurations() {
        #expect(RunUsageText.duration(.milliseconds(11809)).hasSuffix(" s"))
        #expect(RunUsageText.duration(.milliseconds(11809)).contains("11"))
        #expect(!RunUsageText.duration(.seconds(125)).hasSuffix(" s"))
    }

    @Test("Kola se skloňují")
    func inflectsTurns() {
        #expect(RunUsageText.turns(1) == "1 kolo")
        #expect(RunUsageText.turns(3) == "3 kola")
        #expect(RunUsageText.turns(7) == "7 kol")
    }
}
