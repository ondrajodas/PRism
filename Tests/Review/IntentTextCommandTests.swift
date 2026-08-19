import Foundation
import Testing

@testable import PRism

/// Dotažení textu issue — argumenty a čtení streamu (#345).
///
/// **Tři tvary selhání se testují na skutečných streamech** z průzkumu, a je to podmínka, ne
/// pohodlí: dva z nich vypadají jako úspěch (`exit 0`, `result` se `subtype: "success"`), takže
/// vymyšlený JSON by se dal napsat tak, aby test prošel nad rozborem, který se v reálu mýlí.
/// Fixtures jsou popsané v [`docs/claude-cli.md`](../../docs/claude-cli.md).
///
/// **Úspěšné dotažení fixture nemá** a je to napsané schválně: odpověď nese celý text skutečného
/// issue z firemního trackeru, a ten do fixtures nepatří (`CLAUDE.md`, *Testování*). Tvar eventů
/// kolem něj je pokrytý těmi třemi selháními — je to tentýž `init` a tentýž `result` —, takže
/// inline zbývá jen ten kus, který je **náš vlastní formát**: značky v odpovědi.
@Suite("Dotažení textu issue (#345)")
struct IntentTextCommandTests {
    private static let tool = "mcp__claude_ai_Linear__get_issue"
    private static let link = IntentLink(
        id: "AJDA-3003",
        url: URL(string: "https://linear.app/keboola/issue/AJDA-3003")!
    )
    private static let second = IntentLink(
        id: "COR-1775",
        url: URL(string: "https://linear.app/metalbear/issue/COR-1775")!
    )

    // MARK: - Argumenty

    /// **Tvrdá podmínka č. 2 se tímhle nemění.** Zákazy jsou tatáž konstanta jako u revieweera
    /// a v povoleních není nic, čím by se dalo zapsat — jen `ToolSearch` a ten jeden čtecí nástroj.
    @Test("Povolení jsou dva nástroje a zákazy jsou tytéž jako u revieweera")
    func keepsTheSessionReadOnly() {
        let arguments = IntentTextCommand.arguments(prompt: "cokoli", tool: Self.tool)

        let allowed = value(of: "--allowedTools", in: arguments)
        #expect(allowed == "ToolSearch,\(Self.tool)")
        #expect(value(of: "--disallowedTools", in: arguments) == ClaudeCommand.disallowedTools)
        // Literálem, ne konstantou: kdyby se konstanta změnila, má o tom být řeč tady.
        #expect(value(of: "--disallowedTools", in: arguments) == "Bash(gh:*),Bash(git push:*)")
        for forbidden in ["Write", "Edit", "Bash(git:*)", "ReportFindings", "Skill"] {
            #expect(allowed?.contains(forbidden) != true)
        }
    }

    /// **`--allowedTools ""` se z překladu opsat nedá** (změřeno): na tomhle stroji je v session
    /// 165 nástrojů, takže CLI schémata odkládá a model musí napřed zavolat `ToolSearch`.
    @Test("ToolSearch je v povoleních, protože bez něj se schéma nenačte")
    func allowsToolSearch() {
        let allowed = value(of: "--allowedTools", in: IntentTextCommand.arguments(prompt: "x", tool: Self.tool))
        #expect(allowed?.contains("ToolSearch") == true)
    }

    /// **Strop kol nesmí být 1–2**: úspěšné dotažení má ≥ 3 turny (`ToolSearch` → nástroj →
    /// odpověď). Test tvrdí číslo, ne jen „víc než dvě“ — kdyby se snížilo, má to být vidět.
    @Test("Strop kol dává místo na ToolSearch i na nástroj")
    func leavesRoomForTheToolSearchTurn() {
        let arguments = IntentTextCommand.arguments(prompt: "x", tool: Self.tool)
        #expect(value(of: "--max-turns", in: arguments) == "6")
        #expect(IntentTextCommand.maxTurns >= 3)
    }

    /// Bez `stream-json` není v odpovědi `init` event, tedy ani `mcp_servers[].status` — a to je
    /// **jediný strojově čitelný** signál o tom, jestli byl tracker na drátě. `--verbose` k tomu
    /// patří proto, že bez něj `claude` `stream-json` v print režimu odmítne.
    @Test("Session jede streamem, ne bufferovaně jako překlad")
    func runsAsAStream() {
        let arguments = IntentTextCommand.arguments(prompt: "x", tool: Self.tool)
        #expect(value(of: "--output-format", in: arguments) == "stream-json")
        #expect(arguments.contains("--verbose"))
        // A model se **nevynucuje** — `claude` si vybere sám, jako u překladu nálezů.
        #expect(!arguments.contains("--model"))
    }

    /// Prompt musí nést **jméno nástroje** (jinak si ho model má hledat mezi 165), **návod na
    /// `ToolSearch`** (bez něj na odložené schéma nepřijde) a **zákaz placeholderu** (vysvětlení
    /// modelu uložené jako text issue se od zadání nedá odlišit).
    @Test("Prompt jmenuje nástroj, ToolSearch a zakazuje placeholder")
    func promptCarriesWhatTheModelNeeds() {
        let prompt = IntentTextCommand.prompt(for: [Self.link, Self.second], tool: Self.tool)

        #expect(prompt.contains(Self.tool))
        #expect(prompt.contains("select:\(Self.tool)"))
        #expect(prompt.contains("AJDA-3003"))
        #expect(prompt.contains("COR-1775"))
        #expect(prompt.contains(Self.link.url.absoluteString))
        #expect(prompt.contains(IntentTextCommand.marked("AJDA-3003")))
        #expect(prompt.contains("do not write a placeholder"))
    }

    // MARK: - Tři tvary selhání ze skutečných streamů

    /// **Server chybí nebo není přihlášený.** Nejzrádnější z těch tří: `exit 0`, `result` se
    /// `subtype: "success"`, `permission_denials` prázdné — a v odpovědi próza modelu, že žádný
    /// server připojený není. Kdo čte exit kód nebo text, uloží tu prózu jako zadání.
    @Test("Chybějící server se pozná z init eventu, ne z textu odpovědi")
    func readsAMissingServerFromTheInitEvent() throws {
        let stream = try Fixture.text("stream-json/intent-server-missing.jsonl")

        let result = IntentTextCommand.parse(stream, tool: Self.tool, links: [Self.link])

        #expect(result.gap == .serverUnavailable(status: nil))
        #expect(result.issues.isEmpty)
        // Doklad, že to fixture doopravdy je ten zrádný tvar: session skončila úspěchem a próza
        // v odpovědi je.
        #expect(stream.contains("\"subtype\":\"success\""))
        #expect(stream.contains("žádný Linear MCP server není připojen"))
        // A ta próza se **nikam neuložila** — kdyby se čtení dělalo podle textu, byla by z ní
        // sekce zadání.
        #expect(!result.issues.contains { $0.text.contains("není připojen") })
    }

    /// **Server v konfiguraci je, ale nespustil se.** `exit 1`, `subtype: "error_max_turns"` a —
    /// to hlavní — v tom eventu **chybí klíč `result`**. Čtení, které ho čeká jen prázdný, dostane
    /// `nil` a tváří se, že odpověď přišla.
    @Test("Nespuštěný server hlásí status a result event nemá klíč result")
    func readsAFailedServerFromTheInitEvent() throws {
        let stream = try Fixture.text("stream-json/intent-server-failed.jsonl")

        // Fixture je z běhu, kde se server jmenoval `linear` — tedy jiné jméno než dnes; nástroj
        // se proto musí párovat podle **jeho** prefixu, ne podle toho v konfiguraci.
        let result = IntentTextCommand.parse(stream, tool: "mcp__linear__get_issue", links: [Self.link])

        #expect(result.gap == .serverUnavailable(status: "failed"))
        #expect(result.issues.isEmpty)
        #expect(stream.contains("\"subtype\":\"error_max_turns\""))
        // Doklad chybějícího klíče: v `result` eventu se `"result":` nevyskytuje.
        let resultEvent = try #require(TextLines.nonEmpty(stream).last { $0.contains("\"type\":\"result\"") })
        #expect(!resultEvent.contains("\"result\":"))
    }

    /// **Nástroj se odmítl.** Session doběhne `success`, takže je to poznat jedině
    /// z `permission_denials`.
    @Test("Odmítnutý nástroj se pozná z permission_denials")
    func readsADeniedToolFromTheResultEvent() throws {
        let stream = try Fixture.text("stream-json/intent-tool-denied.jsonl")

        let result = IntentTextCommand.parse(stream, tool: Self.tool, links: [Self.link])

        #expect(result.gap == .toolDenied)
        #expect(result.issues.isEmpty)
        #expect(stream.contains("\"subtype\":\"success\""))
        #expect(stream.contains("permission_denials"))
    }

    /// Server je připojený a nic se neodmítlo, ale text nedorazil — třetí odpověď, která se
    /// s předchozími dvěma nesmí slít.
    @Test("Připojený server bez použitelné odpovědi je noAnswer")
    func reportsNoAnswerWhenTheTextIsMissing() {
        let stream = Self.stream(serverStatus: "connected", result: "Tohle není značka.")

        let result = IntentTextCommand.parse(stream, tool: Self.tool, links: [Self.link])

        #expect(result.gap == .noAnswer)
    }

    /// Připojený server a `result` event **bez klíče `result`** (tak vypadá `error_max_turns`).
    /// Čtení na chybějícím klíči nesmí spadnout ani propsat `nil` dál jako text.
    @Test("Chybějící klíč result je noAnswer, ne prázdná odpověď")
    func handlesAResultEventWithoutTheResultKey() {
        let stream = """
        {"type":"system","subtype":"init","session_id":"s1","mcp_servers":[{"name":"claude.ai Linear","status":"connected"}]}
        {"type":"result","subtype":"error_max_turns","is_error":true,"permission_denials":[]}
        """

        let result = IntentTextCommand.parse(stream, tool: Self.tool, links: [Self.link])

        #expect(result.gap == .noAnswer)
        #expect(result.issues.isEmpty)
    }

    /// Stream, ze kterého se nedá přečíst ani hlavička (zabitá session, rozstřelený výstup),
    /// **netvrdí nic o serveru** — o něm se z něj neví.
    @Test("Prázdný stream netvrdí nic o serveru")
    func saysNothingAboutTheServerWithoutAnInitEvent() {
        #expect(IntentTextCommand.parse("", tool: Self.tool, links: [Self.link]).gap == .noAnswer)
        #expect(IntentTextCommand.parse("není to json\n{", tool: Self.tool, links: [Self.link]).gap == .noAnswer)
    }

    /// `needs-auth` je pro uživatele **tentýž stav** jako chybějící server (servery se `needs-auth`
    /// nemají v `tools` ani jednu položku) — jen se u něj hlásí, co stav říkal.
    @Test("Nepřihlášený server je taky serverUnavailable", arguments: ["needs-auth", "pending", "failed"])
    func treatsAnyNonConnectedStatusAsUnavailable(_ status: String) {
        let stream = Self.stream(serverStatus: status, result: IntentTextCommand.marked("AJDA-3003") + "\nText.")

        let result = IntentTextCommand.parse(stream, tool: Self.tool, links: [Self.link])

        #expect(result.gap == .serverUnavailable(status: status))
        // A text se **nebere**, i když v odpovědi je: nepřipojený server nemohl nic vrátit, takže
        // to, co v ní stojí, je próza modelu.
        #expect(result.issues.isEmpty)
    }

    // MARK: - Čtení odpovědi

    /// Náš vlastní formát, takže inline: text se vykrojí podle značek, próza před první značkou
    /// se zahodí a značka se páruje na `IntentLink.id`.
    @Test("Text se vykrojí podle značek a próza před nimi se zahodí")
    func readsTheMarkedText() {
        let answer = """
        Here are the issues:
        \(IntentTextCommand.marked("AJDA-3003"))
        # Titulek

        Popis s `backticky` a "uvozovkami".
        \(IntentTextCommand.marked("COR-1775"))
        Druhý.
        """

        let result = IntentTextCommand.parse(
            Self.stream(serverStatus: "connected", result: answer),
            tool: Self.tool,
            links: [Self.link, Self.second]
        )

        #expect(result.gap == nil)
        #expect(result.issues.map(\.id) == ["AJDA-3003", "COR-1775"])
        #expect(result.issues.first?.text == "# Titulek\n\nPopis s `backticky` a \"uvozovkami\".")
        #expect(result.issues.last?.text == "Druhý.")
        // Próza před první značkou se do zadání nedostane.
        #expect(!result.issues.contains { $0.text.contains("Here are the issues") })
    }

    /// **Vymyšlené issue se zahodí i s textem**, ne přiřadí k předchozímu: kdyby se text nalepil
    /// na sousední sekci, dostal by reviewer u jednoho issue text jiného.
    @Test("Neznámý identifikátor se zahodí i s textem")
    func dropsUnknownIdentifiersWithTheirText() {
        let answer = """
        \(IntentTextCommand.marked("AJDA-3003"))
        Správný.
        \(IntentTextCommand.marked("XXX-1"))
        Vymyšlený.
        """

        let result = IntentTextCommand.parse(
            Self.stream(serverStatus: "connected", result: answer),
            tool: Self.tool,
            links: [Self.link]
        )

        #expect(result.issues.map(\.id) == ["AJDA-3003"])
        #expect(result.issues.first?.text == "Správný.")
    }

    /// Značka s malými písmeny patří tomu issue, ne žádnému: `IntentLink.id` je kanonicky velkými.
    @Test("Značka se páruje bez ohledu na velikost písmen")
    func matchesTheMarkerCaseInsensitively() {
        let answer = "\(IntentTextCommand.marker) ajda-3003>>>\nText."

        let result = IntentTextCommand.parse(
            Self.stream(serverStatus: "connected", result: answer),
            tool: Self.tool,
            links: [Self.link]
        )

        #expect(result.issues.map(\.id) == ["AJDA-3003"])
    }

    /// Značka bez textu není text: prázdná sekce by v souboru vypadala jako issue, které nic
    /// neříká — a to je zrovna ta záměna, kterou #345 odstraňuje.
    @Test("Značka bez textu se nepočítá za dotažené issue")
    func doesNotCountAnEmptyMarker() {
        let result = IntentTextCommand.parse(
            Self.stream(serverStatus: "connected", result: IntentTextCommand.marked("AJDA-3003") + "\n   \n"),
            tool: Self.tool,
            links: [Self.link]
        )

        #expect(result.issues.isEmpty)
        #expect(result.gap == .noAnswer)
    }

    /// **Částečná odpověď gap nedostane**: jedno issue z dvou dorazilo, takže session neselhala —
    /// chybějící se pojmenuje ve své sekci v souboru (`Policy.intentBrief`).
    @Test("Částečná odpověď není selhání celého dotažení")
    func doesNotFlagAPartialAnswer() {
        let result = IntentTextCommand.parse(
            Self.stream(
                serverStatus: "connected",
                result: IntentTextCommand.marked("AJDA-3003") + "\nText."
            ),
            tool: Self.tool,
            links: [Self.link, Self.second]
        )

        #expect(result.issues.map(\.id) == ["AJDA-3003"])
        #expect(result.gap == nil)
    }

    /// Odpověď je cizí markdown, takže může přijít s `CRLF`. `split(separator: "\n")` by na něm
    /// **nerozdělil vůbec** (v Swiftu je to jeden `Character`) — celá odpověď by byla jeden řádek,
    /// tedy ani jedna značka a `noAnswer` nad odpovědí, ve které text byl.
    ///
    /// Text se přitom **skládá zpátky s `LF`**, ne s tím, co přišlo, a je to schválně: řádky se
    /// dělily, takže se zakončení nedochová, a soubor se zadáním je markdown, který skládáme my
    /// (`intentBrief` spojuje `\n`). Popis PR je jiný případ — ten se do souboru vkládá **doslova**,
    /// takže si `CRLF` nese (viz `ReviewIntentTests`).
    @Test("Odpověď s CRLF se rozdělí na řádky")
    func handlesCarriageReturnsInTheAnswer() {
        let answer = "\(IntentTextCommand.marked("AJDA-3003"))\r\nPrvní řádek.\r\nDruhý řádek.\r\n"

        let result = IntentTextCommand.parse(
            Self.stream(serverStatus: "connected", result: answer),
            tool: Self.tool,
            links: [Self.link]
        )

        #expect(result.issues.map(\.id) == ["AJDA-3003"])
        #expect(result.issues.first?.text == "První řádek.\nDruhý řádek.")
    }

    /// Nástroj, který **není** MCP, žádný server nemá — takže se stav serveru nekontroluje a
    /// rozhoduje odpověď. Hlásit „server chybí“ tam, kde žádný být nemá, by bylo hádání.
    @Test("Nástroj bez prefixu mcp__ se na server neptá")
    func skipsTheServerCheckForANonMcpTool() {
        let answer = "\(IntentTextCommand.marker) AJDA-3003>>>\nText."
        let stream = Self.stream(serverStatus: "failed", result: answer)

        let result = IntentTextCommand.parse(stream, tool: "Read", links: [Self.link])

        #expect(result.gap == nil)
        #expect(result.issues.map(\.id) == ["AJDA-3003"])
    }

    // MARK: - Pomůcky

    private func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Minimální stream se `init` a `result` eventem.
    ///
    /// Inline schválně: skutečná **úspěšná** odpověď nese text firemního issue a ten do fixtures
    /// nepatří. Klíče jsou ale opsané ze skutečných streamů (viz fixtures v téhle sadě), takže se
    /// tvar eventů nevymýšlí — vymýšlí se jen obsah odpovědi, který je náš vlastní formát.
    private static func stream(serverStatus: String, result: String) -> String {
        let servers = #"[{"name":"claude.ai Linear","status":"\#(serverStatus)"}]"#
        let initEvent = #"{"type":"system","subtype":"init","session_id":"s1","mcp_servers":\#(servers),"tools":["ToolSearch"]}"#
        let payload = String(
            data: try! JSONSerialization.data(
                withJSONObject: ["type": "result", "subtype": "success", "is_error": false, "result": result],
                options: [.sortedKeys]
            ),
            encoding: .utf8
        )!
        return initEvent + "\n" + payload + "\n"
    }
}
