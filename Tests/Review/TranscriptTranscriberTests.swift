import Foundation
import Testing

@testable import PRism

/// Přepis transcriptu na to, co se dá číst (#327).
///
/// Proti **skutečnému** transcriptu z veřejného `ondrajodas/prism-review-sandbox`
/// (`transcript/review-session.jsonl`, 18 řádků vybraných z běhu bajt po bajtu): `queue-operation`,
/// `attachment`, `last-prompt`, zadání session, próza, `thinking`, tři nástroje s odpověďmi
/// a `ReportFindings`. Žádný z těch typů ve `stream-json` **není**, takže vyrobená fixture by
/// popisovala formát, který CLI nepíše.
///
/// Co se ze skutečných dat nesehnalo, je **odmítnutý nástroj**: ve všech transcriptech pod
/// `~/.claude/projects` (včetně těch z aplikace) není ani jeden `non_execution_kind` — CLI ho do
/// souboru nepíše, na rozdíl od streamu. Testuje se proto inline JSONem, a je u toho napsané proč.
@Suite("Přepis transcriptu")
struct TranscriptTranscriberTests {
    private let worktree = URL(filePath: "/Users/ondra/cache/worktrees/o/r/6-abc")

    private func transcribe(_ text: String) -> TranscriptTranscriber.Transcription {
        TranscriptTranscriber(worktree: worktree).transcribe(TextLines.content(text))
    }

    private func fixture() throws -> TranscriptTranscriber.Transcription {
        transcribe(try Fixture.text("transcript/review-session.jsonl"))
    }

    // MARK: - Skutečný transcript

    @Test("Ze skutečného transcriptu vyleze próza, uvažování i výstupy nástrojů")
    func aRealTranscriptCarriesWhatTheStepFeedDrops() throws {
        let events = try fixture().events

        // Přesně to, co výpis kroků schválně zahazuje.
        #expect(events.contains { $0.kind == .prose })
        #expect(events.contains { $0.kind == .thinking })
        #expect(events.contains { $0.kind == .report })
        #expect(events.contains { if case .system = $0.kind { true } else { false } })
        // A vedle toho kroky, které výpis kreslí — jen s výstupem, který u nich nemá.
        let tools = events.filter { if case .tool = $0.kind { true } else { false } }
        #expect(tools.count == 3)
        #expect(tools.allSatisfy { $0.body?.isEmpty == false })
    }

    @Test("Ani jeden řádek skutečného transcriptu se neztratí jako nečitelný")
    func nothingInARealTranscriptIsUnreadable() throws {
        let transcribed = try fixture()

        #expect(transcribed.unreadableLines == 0)
        #expect(!transcribed.events.contains { $0.kind == .unreadable })
    }

    /// Kdyby se neznámý `type` zahazoval, přepis by se potichu zkrátil právě u té změny formátu,
    /// kvůli které se do něj člověk podívá.
    @Test("Neznámé typy řádků zůstanou jako systémové události")
    func unknownLineTypesStayVisible() throws {
        let events = try fixture().events
        let systems = events.compactMap { event -> String? in
            guard case .system(let type) = event.kind else { return nil }
            return type
        }

        #expect(systems.contains("queue-operation"))
        #expect(systems.contains("attachment"))
        #expect(systems.contains("last-prompt"))
    }

    @Test("Čas se čte z timestampu; řádek bez něj ho nedostane vymyšlený")
    func timesComeFromTheFile() throws {
        let events = try fixture().events

        #expect(events.first?.at != nil)
        // `last-prompt` časovou značku nenese vůbec.
        #expect(events.contains { $0.kind == .system("last-prompt") && $0.at == nil })
    }

    /// Detail volání se zkracuje **stejnou funkcí** jako ve výpisu kroků — bez toho začíná každý
    /// řádek stejnými sedmdesáti znaky cache.
    @Test("Cesty v detailu se zkracují o pracovní strom")
    func pathsAreShortened() throws {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":\
        "/Users/ondra/cache/worktrees/o/r/6-abc/src/Cart.php"}}]}}
        """

        #expect(transcribe(text).events.first?.subject == "src/Cart.php")
    }

    @Test("ReportFindings nese počet nálezů a jejich JSON jako tělo")
    func reportFindingsCarriesItsPayload() throws {
        let report = try #require(fixture().events.first { $0.kind == .report })

        #expect(report.subject?.hasSuffix("nálezy") == true || report.subject?.hasSuffix("nálezů") == true)
        #expect(report.body?.contains("findings") == true)
    }

    // MARK: - Odpovědi nástrojů

    /// Jeden `tool_use` je **jedna** položka přepisu, ať se o něm dozvíme cokoli dalšího — druhý
    /// řádek „a takhle to dopadlo“ by přepis zdvojil.
    @Test("Odpověď nástroje doplní tělo kroku, nepřidá druhý")
    func aResultFillsTheStepInsteadOfAddingOne() {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"tool_result","tool_use_id":"t1","content":"Cart.php\\nOrder.php"}]}}
        """

        let events = transcribe(text).events

        #expect(events.count == 1)
        #expect(events[0].kind == .tool("Bash"))
        #expect(events[0].subject == "ls")
        #expect(events[0].body == "Cart.php\nOrder.php")
    }

    /// Okno je ocas souboru, takže `tool_use` k odpovědi umí ležet před jeho začátkem. Zahodit ji by
    /// znamenalo zahodit zrovna ten výstup, kvůli kterému se sem člověk dívá.
    @Test("Odpověď na krok mimo okno je vlastní událost")
    func aResultWithoutItsStepStandsAlone() {
        let text = """
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"tool_result","tool_use_id":"pryc","content":"něco"}]}}
        """

        let events = transcribe(text).events

        #expect(events.count == 1)
        #expect(events[0].kind == .result)
        #expect(events[0].body == "něco")
    }

    /// **Inline JSON schválně**: `non_execution_kind` v žádném transcriptu na disku není (CLI ho
    /// píše do streamu, ne do souboru), takže se tvar bere z fixture streamu `review-denied-write`.
    @Test("Odmítnutý nástroj dostane štítek, ne nic")
    func aDeniedToolIsLabelled() {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh pr view 412"}}]}}
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","tool_result_meta":\
        [{"id":"t1","non_execution_kind":"user-rejected"}],"message":{"content":\
        [{"type":"tool_result","tool_use_id":"t1","is_error":true,\
        "content":"Claude requested permissions to use Bash, but you haven't granted it yet."}]}}
        """

        let events = transcribe(text).events

        #expect(events.count == 1)
        #expect(events[0].isDenied)
    }

    /// **`is_error` sám o sobě odmítnutí neznamená** (#326): `grep` bez shody vrací chybu pořád,
    /// a odznak `ODMÍTNUTO` u něj by znamenal „něco se nepovedlo“ místo „read-only režim zabral“ —
    /// tedy zrovna to rozlišení, na kterém stojí, aby se tvrdá podmínka č. 2 nezačala vypínat.
    @Test("Chyba nástroje není odmítnutí")
    func aToolErrorIsNotADenial() {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"nikde"}}]}}
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"No matches found"}]}}
        """

        let events = transcribe(text).events

        #expect(!events[0].isDenied)
        #expect(events[0].body == "No matches found")
    }

    // MARK: - Obrázky

    /// 2,8 MB base64 v jednom změřeném transcriptu, ze kterých není k přečtení nic.
    @Test("Base64 obrázku se nevypisuje, jen se přizná i s velikostí")
    func imagesAreAdmittedButNeverPrinted() throws {
        let payload = String(repeating: "A", count: 4000)
        let text = """
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"image","source":{"type":"base64","media_type":"image/png","data":"\(payload)"}}]}}
        """

        let events = transcribe(text).events

        #expect(events.count == 1)
        #expect(events[0].kind == .image(bytes: 3000))
        #expect(events[0].body == nil)
        // A hlavně: base64 se do přepisu nedostane ani v poznámce.
        #expect(RawSessionText.subject(of: events[0])?.contains(payload) == false)
    }

    @Test("Obrázek uvnitř odpovědi nástroje se přizná v poznámce u ořezu")
    func anImageInsideAToolResultIsAdmitted() throws {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"screencapture x.png"}}]}}
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"hotovo"},\
        {"type":"image","source":{"data":"\(String(repeating: "B", count: 400))"}}]}]}}
        """

        let events = transcribe(text).events

        #expect(events[0].body == "hotovo")
        #expect(events[0].bodyCut?.contains("obrázek") == true)
    }

    /// Krok bez těla vypadá jako krok, jehož nástroj nic nevrátil — takže se neznámý tvar odpovědi
    /// musí **přiznat**, ne spolknout. Nový druh bloku v příští verzi CLI je pravděpodobnější než
    /// rozbitá odpověď, proto poznámka a ne chyba.
    @Test("Odpověď v neznámých blocích se přizná, nezmizí")
    func anUnknownResultShapeIsAdmitted() throws {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"tool_use","id":"t1","name":"ToolSearch","input":{"query":"gh"}}]}}
        {"type":"user","timestamp":"2026-08-09T21:44:37.738Z","message":{"content":\
        [{"type":"tool_result","tool_use_id":"t1","content":[{"type":"tool_reference","name":"x"}]}]}}
        """

        let events = transcribe(text).events

        #expect(events.count == 1)
        #expect(events[0].body == nil)
        #expect(events[0].bodyCut == "odpověď v blocích: tool_reference")
    }

    // MARK: - Nečitelné řádky

    /// Poslední řádek rostoucího souboru je běžně rozepsaný a první řádek okna umí být zbytek řádku,
    /// jehož začátek leží před oknem. Tiše spolknutý řádek vypadá jako řádek, který v transcriptu
    /// nebyl.
    @Test("Rozbitý řádek se počítá a je vidět na svém místě")
    func aBrokenLineIsCountedAndShown() {
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"text","text":"první"}]}}
        {"type":"assistant","message":{"content":[{"type":"te
        """

        let transcribed = transcribe(text)

        #expect(transcribed.unreadableLines == 1)
        #expect(transcribed.events.count == 2)
        #expect(transcribed.events[1].kind == .unreadable)
        #expect(transcribed.events[1].body?.hasPrefix("{\"type\":\"assistant\"") == true)
    }

    @Test("Řádek bez type je nečitelný, ne systémová událost")
    func aLineWithoutATypeIsUnreadable() {
        let transcribed = transcribe(#"{"message":{"content":[]}}"#)

        #expect(transcribed.unreadableLines == 1)
        #expect(transcribed.events.first?.kind == .unreadable)
    }

    /// `"\r\n"` je ve Swiftu **jeden `Character`**, takže `split(separator: "\n")` by na `CRLF`
    /// nerozdělil vůbec a z celého okna by zbyl jeden nečitelný řádek. Transcript píše `claude`,
    /// takže dnes má `LF` — jenže zakončení řádků si nevybírá aplikace, a to je zrovna ten důvod,
    /// proč dělení drží `TextLines`.
    @Test("Řádky se dělí i na CRLF")
    func linesSplitOnCRLFToo() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"a"}]}}"#
        let transcribed = transcribe("\(line)\r\n\(line)\r\n")

        #expect(transcribed.unreadableLines == 0)
        #expect(transcribed.events.count == 2)
    }

    // MARK: - Strop na událost

    /// Strop platí na **všechna těla**, ne jen na výstupy nástrojů: blok `text` v `user` eventu nese
    /// celý obsah skillu (změřeno 7 167 znaků v jednom bloku skutečného transcriptu).
    @Test("Strop na událost platí i na prózu")
    func theEventLimitAppliesToProseToo() throws {
        let long = String(repeating: "x", count: Policy.rawSessionEventBytes * 2)
        let text = """
        {"type":"assistant","timestamp":"2026-08-09T21:44:37.683Z","message":{"content":\
        [{"type":"text","text":"\(long)"}]}}
        """

        let event = try #require(transcribe(text).events.first)

        #expect(event.body?.utf8.count == Policy.rawSessionEventBytes)
        #expect(event.bodyCut != nil)
    }
}
