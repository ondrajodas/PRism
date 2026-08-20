import Foundation

/// Jak se `claude` volá kvůli textu issue a jak se čte jeho odpověď (#345). Čisté funkce, žádné I/O.
///
/// **Vzor `TranslationCommand` se opsat nedá** a jsou pro to dva změřené důvody:
///
/// - **`--allowedTools ""` tady nefunguje.** Na tomhle stroji je v session **165 nástrojů**, takže
///   CLI odkládá schémata: model musí napřed zavolat `ToolSearch` a **teprve pak** MCP nástroj.
///   Povolení proto vyjmenovává **oba** a `--max-turns` nesmí být 1–2 (dotažení je ≥ 3 turny).
/// - **Session jede streamem** (`--output-format stream-json --verbose`), kdežto překlad je
///   bufferovaný. Bez streamu není vidět `init.mcp_servers[].status`, a to je **jediný strojově
///   čitelný** signál o tom, jestli tracker vůbec byl na drátě — dva ze tří tvarů selhání jinak
///   vypadají jako úspěch (`exit 0`, `result` se `subtype: "success"`).
///
/// Měření i fixtures jsou v [`docs/claude-cli.md`](../../docs/claude-cli.md).
enum IntentTextCommand {
    /// Nástroj, kterým si model **nejdřív** vytáhne schéma toho MCP nástroje.
    ///
    /// Bez něj dotažení nefunguje vůbec: u víc než ~120 nástrojů CLI schémata odkládá a MCP nástroj
    /// se v session objeví jen jménem. Ověřeno ve **všech** bězích průzkumu.
    static let toolSearch = "ToolSearch"

    /// Strop kol modelu.
    ///
    /// **Ne 1–2**: úspěšné dotažení má ≥ 3 turny (`ToolSearch` → MCP nástroj → odpověď), změřeno.
    /// A ne přesně 3: u nedostupného serveru model zkouší `ToolSearch` znovu a strop 3 se vyčerpá
    /// (`error_max_turns`), takže by se úspěšné dotažení víc issues nevešlo do stejného čísla jako
    /// selhání jednoho. Šest kol dává místo na jedno zaváhání a nic navíc nestojí — cenu určuje
    /// **boot session** (85–121 tis. cache-read), ne počet kol.
    static let maxTurns = 6

    /// Řádka, kterou se v odpovědi pozná začátek jednoho issue.
    ///
    /// **Ne JSON**, na rozdíl od `TranslationCommand`, a je to vědomé: tady je hodnota **cizí
    /// markdown libovolné délky** (jedno issue z průzkumu mělo 4 439 znaků, s uvozovkami, zpětnými
    /// apostrofy a odsazenými bloky). Překódovat ho na JSONový řetězec je krok, ve kterém model
    /// utne nebo zkazí escapování — a selhání by pak zahodilo **všechny** texty naráz. Řádková
    /// značka se obsahem rozbít nedá a chybějící issue se pozná tím, že jeho značka nepřišla.
    static let marker = "<<<PRISM-ISSUE"

    /// Argumenty. **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy tatáž konstanta
    /// jako u revieweera — druhá sada zákazů by znamenala druhé místo, kde se dá tvrdá podmínka
    /// č. 2 porušit.
    ///
    /// **Model se nevynucuje.** Cena je rozhodnutá (tahá se vždycky, i v automatu), takže vlastní
    /// `--model` by byla jen třetí odpověď na otázku, se kterým modelem aplikace mluví; `claude` si
    /// vybere sám, stejně jako u překladu nálezů.
    static func arguments(prompt: String, tool: String) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", "\(toolSearch),\(tool)",
            "--disallowedTools", ClaudeCommand.disallowedTools,
            "--max-turns", "\(maxTurns)",
        ]
    }

    /// Prompt. **Jméno nástroje je v něm**, protože jinak si ho model musí najít v seznamu
    /// odložených nástrojů — a spoléhat na to, že si vybere ten správný z 165, je hádání.
    ///
    /// Dvě věci, které v textu stojí schválně:
    /// - **návod na `ToolSearch`** — bez něj model na odložené schéma nepřijde a skončí větou, že
    ///   nástroj neexistuje (změřeno);
    /// - **zákaz placeholderu u nedostupného issue** — vysvětlení modelu („server není připojený“)
    ///   uložené do souboru se zadáním by se od textu issue nedalo odlišit, a rozhodnutí
    ///   „dotáhlo se / nedotáhlo“ se **podle prózy modelu dělat nesmí**.
    static func prompt(for links: [IntentLink], tool: String) -> String {
        let list = links.map { "\($0.id) (\($0.url.absoluteString))" }.joined(separator: ", ")
        let example = marked(links.first?.id ?? "ABC-1")
        return """
        Read the tracker issues \(list) and print their text back verbatim. \
        Use the \(tool) tool. The tools in this session are deferred, so call \(toolSearch) \
        with the query "select:\(tool)" first to load its schema, then call it once per issue. \
        Start each issue with a line that is \(marker), the identifier exactly as given, and \
        >>> — for example: \(example) — and put the issue title and description under it. \
        Print nothing else: no commentary, no summary, no code fence around the answer. \
        If an issue cannot be read, leave out its line entirely; do not write a placeholder \
        and do not explain why.
        """
    }

    /// Značka pro dané id, tak jak se čeká v odpovědi. Jedno místo pro obě strany — příklad
    /// v promptu a rozbor odpovědi se nemají čím rozejít.
    static func marked(_ id: String) -> String { "\(marker) \(id)>>>" }

    /// Přečte stream. **Nikdy nevyhodí** — je to výstup cizího procesu, který se dá zabít uprostřed
    /// řádku, a rozbitá řádka nesmí zahodit texty, které dorazily.
    ///
    /// Pořadí, ve kterém se hledá důvod, je **pořadí příčin**, ne pořadí ošklivosti: nepřipojený
    /// server vysvětluje i to, že odpověď nic neobsahuje, kdežto obráceně to neplatí. Kdyby se
    /// napřed koukalo na text, uložil by se do zadání model, který vysvětluje, že nemá povolení.
    ///
    /// - Parameters:
    ///   - stream: stdout session (`stream-json`, jeden objekt na řádek).
    ///   - tool: jméno MCP nástroje — podle něj se pozná **jeho server** v `init` eventu.
    ///   - links: na co se to ptalo. Texty se párují podle `id`; co v odkazech není, se zahodí
    ///     (model, který si issue vymyslí, nemá čím naplnit sekci, která v souboru není).
    static func parse(_ stream: String, tool: String, links: [IntentLink]) -> IntentTextResult {
        // Rozbitá řádka se **zahazuje bez počítání**, na rozdíl od `StreamParser`, který si vede
        // `malformedLines`. Je to schválně a rozdíl je v tom, co se tím dá ztratit: tam je na řádku
        // nález, takže zahodit ho potichu vypadá jako „čisté review“. Tady se čtou **dva
        // pojmenované eventy** a přijít o kterýkoli z nich skončí na `.noAnswer` nebo na „o serveru
        // nevíme nic“ — tedy na odpovědi, které jsou pravdivé i tak.
        //
        // **Předfiltr na řetězec tady vědomě není.** Dekódují se všechny řádky, i ten největší
        // (`tool_result` s celým textem issue) — jsou to ale **jednotky desítek řádků jednou za
        // review** (16–21 kB v naměřených bězích), ne práce při každém tiku. Filtr podle substringu
        // `"init"` / `"result"` by ušetřil mikrosekundy a přidal předpoklad o tom, jak CLI klíče
        // píše; to je horší obchod.
        let events = TextLines.nonEmpty(stream).compactMap { line -> [String: Any]? in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
        let initEvent = events.last { $0["subtype"] as? String == "init" }
        let result = events.last { $0["type"] as? String == "result" }

        // Žádný `init` ani `result` = ze streamu se nedá přečíst nic. Není to „bez odpovědi“ ve
        // smyslu prázdné odpovědi — session nedala ani hlavičku, takže o serveru se nic neví.
        guard initEvent != nil || result != nil else {
            return IntentTextResult(gap: .noAnswer)
        }
        if let gap = serverGap(in: initEvent, tool: tool) { return IntentTextResult(gap: gap) }
        // **Jakékoli** odmítnutí, ne jen odmítnutí toho MCP nástroje: povolené jsou dva nástroje
        // a bez obou dotažení neproběhne, takže odmítnutý `ToolSearch` znamená totéž.
        if let denials = result?["permission_denials"] as? [[String: Any]], !denials.isEmpty {
            return IntentTextResult(gap: .toolDenied)
        }

        // **`result` se čeká jako nepřítomný klíč**, ne jen jako prázdný: u `error_max_turns` v tom
        // eventu **není vůbec** (změřeno u #345), takže se na něj nesmí sahat tak, aby na chybějícím
        // klíči spadlo nebo aby se `nil` propsalo dál jako text.
        //
        // Poznámka k tomu, co ten `guard` doopravdy drží: dnes je **rovnocenný** s `?? ""`, protože
        // prázdný text nevydá ani jednu značku a skončí stejným `.noAnswer` — ověřeno vložením té
        // regrese, sada zůstala zelená. Zůstává explicitní schválně: čtení, které chybějící klíč
        // vidí, se dá bezpečně rozšířit, kdežto `?? ""` mlčí a příští úprava (třeba rozlišení
        // „odpověď přišla a byla k ničemu“) by na něm tiše stála.
        guard let text = result?["result"] as? String else { return IntentTextResult(gap: .noAnswer) }

        let issues = issues(in: text, links: links)
        // Ani jeden text = odpověď byla, ale k ničemu. Částečný výsledek gap **nedostane**:
        // chybějící issue se pojmenuje ve své sekci v souboru (viz `Policy.intentBrief`), kdežto
        // příznak na ose je tvrzení o celém dotažení.
        return IntentTextResult(issues: issues, gap: issues.isEmpty ? .noAnswer : nil)
    }

    /// Byl server, který ten nástroj nese, připojený? `nil` = byl (nebo se to nedá zjistit).
    ///
    /// Server se páruje **podle jména z `init.mcp_servers`**, protože jméno nástroje ho v sobě nese:
    /// `mcp__claude_ai_Linear__get_issue` patří serveru `claude.ai Linear`. Nealfanumerické znaky
    /// se v tom prefixu mění na `_`, takže se porovnává sražené jméno se sraženým.
    ///
    /// Nástroj **bez** prefixu `mcp__` (kdyby si někdo do konfigurace napsal vestavěný) server
    /// nemá, takže se tady nic nekontroluje a rozhoduje až odpověď — hádat ze seznamu serverů by
    /// znamenalo hlásit nedostupný server tam, kde žádný být nemá.
    private static func serverGap(in initEvent: [String: Any]?, tool: String) -> IntentGap? {
        guard let server = serverSlug(of: tool) else { return nil }
        // Chybějící `init` u přítomného `result`: o serverech se neví nic, takže se netvrdí nic.
        guard let servers = initEvent?["mcp_servers"] as? [[String: Any]] else { return nil }

        let match = servers.first { slugged($0["name"] as? String ?? "") == server }
        // **Chybějící a nepřihlášený server je jeden stav** (`status: nil` vs. `"needs-auth"`):
        // server se `needs-auth` nemá v `tools` ani jednu položku, takže se od chybějícího nedá
        // odlišit ničím, co by pro uživatele znamenalo něco jiného.
        guard let match else { return .serverUnavailable(status: nil) }
        let status = match["status"] as? String
        guard status == "connected" else { return .serverUnavailable(status: status) }
        return nil
    }

    /// `mcp__claude_ai_Linear__get_issue` → `claude_ai_linear`. `nil` = není to MCP nástroj.
    private static func serverSlug(of tool: String) -> String? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let rest = tool.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__") else { return nil }
        let server = rest[rest.startIndex..<separator.lowerBound]
        return server.isEmpty ? nil : slugged(String(server))
    }

    /// Jméno serveru sražené na to, co z něj `claude` dělá v prefixu nástroje: malá písmena
    /// a nealfanumerické znaky na `_`.
    private static func slugged(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    /// Vykrojí z odpovědi texty podle značek.
    ///
    /// Text **před první značkou se zahazuje** (model rád začne větou „Here are the issues:“)
    /// a text za značkou patří k ní až do další značky nebo do konce. Řádky se dělí `TextLines` —
    /// odpověď nese cizí markdown a `CRLF` je ve Swiftu **jeden `Character`**, takže
    /// `split(separator: "\n")` by z celé odpovědi udělal jediný řádek.
    private static func issues(in text: String, links: [IntentLink]) -> [IntentIssueText] {
        let wanted = Set(links.map(\.id))
        var collected: [String: [String]] = [:]
        var order: [String] = []
        var current: String?

        for line in TextLines.all(text) {
            if let id = identifier(inMarker: line) {
                // Neznámé id se zahodí **i s obsahem** (`current = nil`), ne přiřadí k předchozímu:
                // vymyšlené issue nemá v souboru sekci, takže by se jeho text nalepil na cizí.
                guard wanted.contains(id) else {
                    current = nil
                    continue
                }
                current = id
                if collected[id] == nil {
                    collected[id] = []
                    order.append(id)
                }
                continue
            }
            guard let current else { continue }
            collected[current]?.append(String(line))
        }

        return order.compactMap { id in
            let text = (collected[id] ?? []).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : IntentIssueText(id: id, text: text)
        }
    }

    /// `<<<PRISM-ISSUE AJDA-892>>>` → `AJDA-892`. `nil`, když to značka není.
    ///
    /// Velikost písmen se srovnává nahoru, protože `IntentLink.id` je kanonicky velkými písmeny —
    /// model, který napíše `ajda-892`, má mít text u svého issue, ne u žádného.
    private static func identifier(inMarker line: some StringProtocol) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(marker), trimmed.hasSuffix(">>>") else { return nil }
        let inner = trimmed.dropFirst(marker.count).dropLast(3)
        let id = inner.trimmingCharacters(in: .whitespaces).uppercased()
        return id.isEmpty ? nil : id
    }
}
