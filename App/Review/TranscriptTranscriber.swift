import Foundation

/// Přepis transcriptu session `claude` na to, co se dá číst (#327).
///
/// **Přepis, ne syrový JSONL, a je to změřené.** Nejdelší řádek transcriptu má 7,5 MB a v řádku
/// o mediánové délce (1 604 B) je čitelného obsahu **247 B** — zbylých 86 % jsou strojová pole
/// (`uuid`, `parentUuid`, `cwd`, `version`, `requestId`) a struktura JSONu. Syrové řádky by tedy
/// ukázaly na obrazovku **míň** informace, ne víc; doslovnost tu není přesnost.
///
/// **Není to `StreamParser`, a nesmí to jím být.** Parser čte `stream-json` a odpovídá na otázku
/// „co z běhu zbylo“ — sbírá nálezy, pokusy o nástroje a konec běhu, tedy právě ten výběr, který
/// výpis kroků kreslí. Tady se kreslí to, co výpis **schválně zahazuje** (próza, `thinking`,
/// výstupy nástrojů, systémové události), takže by z parseru musela vylézt druhá, jiná datová
/// struktura — a dva různé výběry v jednom typu se rozejdou. Co je společné, se **použije**:
/// `ToolAttempt` na detail volání a `Policy.toolOutcome` na to, jestli byl nástroj odmítnutý.
///
/// **Formát transcriptu není `stream-json`**, i když si jsou blízké (ověřeno na skutečných
/// souborech pod `~/.claude/projects`):
///
/// | Ve streamu | V transcriptu |
/// |---|---|
/// | `session_id` | `sessionId` |
/// | `system` / `init` | není vůbec; místo něj `queue-operation` a `attachment` |
/// | `tool_result_meta` na eventu | není; místo něj `toolUseResult` |
/// | čas nikde | `timestamp` na skoro každém řádku |
///
/// Z toho plyne jedna věc, kterou je potřeba vědět dopředu: **odmítnutí nástroje se v transcriptu
/// pozná jinak než ve streamu.** `non_execution_kind` v souboru není, takže se `Policy.toolOutcome`
/// dostane `nil` a zbývá `is_error`. Aby z toho nebyl odznak `ODMÍTNUTO` nad `grep`em bez shody,
/// rozhoduje se to **stejně jako ve streamu** — tedy podle struktury, ne podle textu hlášky —
/// a `tool_result_meta` se čte, kdyby ho novější CLI do transcriptu přidalo.
struct TranscriptTranscriber: Sendable {
    /// Pracovní strom, ve kterém session běžela. Podle něj se zkracují cesty ve detailu volání —
    /// bez toho začíná každý řádek stejnými sedmdesáti znaky cache.
    let worktree: URL?

    /// Čas z transcriptu. `Date.ISO8601FormatStyle` je `Sendable`, takže se dá držet staticky —
    /// `ISO8601DateFormatter` je třída a v `Sendable` typu by být nemohl.
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    /// Co z okna transcriptu vyleze. **Ne `Result`** — ten je v jazyce a v přepisu by se pletl.
    struct Transcription: Equatable, Sendable {
        var events: [TranscriptEvent] = []
        var unreadableLines = 0
    }

    /// Přepis okna transcriptu. Řádky přicházejí v pořadí, v jakém v souboru stojí.
    func transcribe<S: StringProtocol>(_ lines: [S]) -> Transcription {
        var result = Transcription()
        /// `tool_use_id` → index události, do které patří odpověď. Odpověď se **nepřidává jako
        /// další událost**: jeden `tool_use` je jedna položka přepisu, ať se o něm dozvíme cokoli
        /// dalšího — druhý řádek „a takhle to dopadlo“ by přepis zdvojil.
        var pending: [String: Int] = [:]

        for line in lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                // **Nečitelný řádek se nezahazuje.** Tiše spolknutý řádek vypadá jako řádek, který
                // v transcriptu nebyl — a zrovna tady je to ten pravděpodobný případ: poslední
                // řádek rostoucího souboru je běžně rozepsaný a první řádek okna umí být zbytek
                // řádku, jehož začátek leží před oknem.
                result.unreadableLines += 1
                append(.unreadable, at: nil, body: text, into: &result)
                continue
            }
            consume(object, into: &result, pending: &pending)
        }
        return result
    }

    // MARK: - Jeden řádek

    private func consume(
        _ object: [String: Any],
        into result: inout Transcription,
        pending: inout [String: Int]
    ) {
        let at = time(of: object)
        switch object["type"] as? String {
        case "assistant":
            consumeAssistant(object, at: at, into: &result, pending: &pending)
        case "user":
            consumeUser(object, at: at, into: &result, pending: &pending)
        case let type?:
            // **Systémová událost, i když je neznámá.** `attachment`, `queue-operation`,
            // `last-prompt`, `summary`, `file-history-snapshot` — a cokoli, co do formátu přidá
            // příští verze CLI. Zahodit neznámý `type` by znamenalo, že se přepis potichu zkrátí
            // právě u té změny, kvůli které se do něj člověk podívá.
            append(
                .system(type),
                at: at,
                subject: systemSubject(of: object),
                into: &result
            )
        case nil:
            result.unreadableLines += 1
            append(.unreadable, at: at, body: "Řádek nemá `type`.", into: &result)
        }
    }

    /// Čeho se systémová událost týká. `attachment` nese druh v `attachment.type`, `queue-operation`
    /// v `operation` — bez toho by v přepisu stálo pětkrát `attachment` a nic víc.
    ///
    /// **Tělo systémová událost nedostane**, a je to schválně: obsahem `attachment`u je typicky celý
    /// výpis nainstalovaných skillů a obsahem prvního `queue-operation` tentýž prompt, který o řádek
    /// níž stojí jako `user` event. Obojí je materiál, ne to, co model dělal — a druhá kopie promptu
    /// by v okně o 4 MB zabrala místo, které patří krokům.
    private func systemSubject(of object: [String: Any]) -> String? {
        if let attachment = (object["attachment"] as? [String: Any])?["type"] as? String {
            return attachment
        }
        if let operation = object["operation"] as? String { return operation }
        if let subtype = object["subtype"] as? String { return subtype }
        return nil
    }

    // MARK: - Model

    private func consumeAssistant(
        _ object: [String: Any],
        at time: Date?,
        into result: inout Transcription,
        pending: inout [String: Int]
    ) {
        for block in blocks(of: object) {
            switch block["type"] as? String {
            case "text":
                let text = block["text"] as? String ?? ""
                append(.prose, at: time, subject: "próza · \(size(of: text))", body: text, into: &result)
            case "thinking":
                let text = block["thinking"] as? String ?? ""
                append(.thinking, at: time, subject: size(of: text), body: text, into: &result)
            case "tool_use":
                consumeToolUse(block, at: time, into: &result, pending: &pending)
            default:
                break
            }
        }
    }

    private func consumeToolUse(
        _ block: [String: Any],
        at time: Date?,
        into result: inout Transcription,
        pending: inout [String: Int]
    ) {
        guard let name = block["name"] as? String else { return }
        let input = block["input"] as? [String: Any]

        if name == "ReportFindings" {
            let findings = (input?["findings"] as? [[String: Any]])?.count
            append(
                .report,
                at: time,
                subject: findings.map { Plural.czech($0, one: "nález", few: "nálezy", many: "nálezů") },
                body: reportBody(input),
                into: &result
            )
            return
        }

        let attempt = ToolAttempt(name: name, input: input, id: block["id"] as? String)
        append(
            .tool(name),
            at: time,
            subject: attempt.shortened(inside: worktree),
            into: &result
        )
        // Tělo dorazí až s odpovědí, takže se index kroku schová a odpověď se do něj doplní.
        if let id = attempt.id { pending[id] = result.events.count - 1 }
    }

    /// Tělo `ReportFindings` — **jediné místo, kde tělo není doslovný text z transcriptu**.
    ///
    /// Nálezy leží v `input` jako JSON objekt, ne jako řetězec, takže doslovný tvar by znamenal
    /// pamatovat si bajtový rozsah uvnitř řádku a vracet se do něj. Serializuje se proto zpátky —
    /// je to tentýž obsah, jen s vlastním pořadím klíčů, a stojí to jeden průchod objektem, který
    /// má jednotky kilobajtů (v největším změřeném transcriptu je `ReportFindings` jednou).
    private func reportBody(_ input: [String: Any]?) -> String? {
        guard let input,
              let data = try? JSONSerialization.data(
                  withJSONObject: input,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Odpovědi nástrojů a vstup

    private func consumeUser(
        _ object: [String: Any],
        at time: Date?,
        into result: inout Transcription,
        pending: inout [String: Int]
    ) {
        // Zadání session: `message.content` je řetězec, ne pole bloků.
        if let prompt = (object["message"] as? [String: Any])?["content"] as? String {
            append(.prompt, at: time, subject: size(of: prompt), body: prompt, into: &result)
            return
        }

        let kinds = nonExecutionKinds(in: object)
        for block in blocks(of: object) {
            switch block["type"] as? String {
            case "tool_result":
                consumeToolResult(block, at: time, kinds: kinds, into: &result, pending: &pending)
            case "text":
                let text = block["text"] as? String ?? ""
                append(.input, at: time, subject: size(of: text), body: text, into: &result)
            case "image":
                append(.image(bytes: imageBytes(of: block)), at: time, into: &result)
            default:
                break
            }
        }
    }

    private func consumeToolResult(
        _ block: [String: Any],
        at time: Date?,
        kinds: [String: String],
        into result: inout Transcription,
        pending: inout [String: Int]
    ) {
        let content = resultContent(of: block["content"])
        let outcome = Policy.toolOutcome(
            isError: block["is_error"] as? Bool ?? false,
            nonExecutionKind: (block["tool_use_id"] as? String).flatMap { kinds[$0] },
            text: content.text
        )
        let body = Policy.rawSessionBody(content.text ?? "")

        guard let id = block["tool_use_id"] as? String, let index = pending[id] else {
            // Odpověď na pokus **mimo okno** — jeho `tool_use` leží před začátkem okna. Vlastní
            // událost, protože „výsledek bez kroku“ je jiné tvrzení než krok, a zahodit ji by
            // znamenalo zahodit zrovna ten výstup, kvůli kterému se sem člověk dívá.
            append(
                .result,
                at: time,
                subject: outcome.kind == .denied ? nil : content.note,
                body: content.text ?? "",
                denied: outcome.kind == .denied,
                into: &result
            )
            return
        }
        // Krok už v přepisu je, takže se do něj tělo jen doplní.
        result.events[index].body = body.text
        result.events[index].bodyCut = body.cut
        result.events[index].isDenied = outcome.kind == .denied
        if let note = content.note {
            result.events[index].bodyCut = [body.cut, note].compactMap { $0 }.joined(separator: "  ")
        }
        pending[id] = nil
    }

    /// `non_execution_kind` po `tool_use_id`.
    ///
    /// **V dnešním transcriptu to pole není** (ověřeno na souborech pod `~/.claude/projects`:
    /// `user` řádky mají `toolUseResult`, ne `tool_result_meta`), takže se z něj obvykle vrátí
    /// prázdno a o odmítnutí rozhodne `is_error`. Čte se přesto, a je to schválně: kdyby ho CLI
    /// do transcriptu přidalo, rozhodne se **stejně jako ve streamu** — a `Policy.toolOutcome`
    /// zůstává jedním místem, kde se to rozhoduje.
    private func nonExecutionKinds(in object: [String: Any]) -> [String: String] {
        let meta = object["tool_result_meta"] as? [[String: Any]] ?? []
        return meta.reduce(into: [:]) { result, entry in
            guard let id = entry["id"] as? String,
                  let kind = entry["non_execution_kind"] as? String
            else { return }
            result[id] = kind
        }
    }

    /// Text odpovědi nástroje a poznámka o tom, co se z ní nevypsalo.
    ///
    /// Bývá to řetězec, ale u některých nástrojů je to pole bloků — a mezi nimi umí být `image`.
    /// **Base64 obrázku se nevypisuje nikdy**: v jednom změřeném transcriptu jsou to 2,8 MB, ze
    /// kterých není k přečtení nic. Jen se přizná, že tam je a kolik váží.
    private func resultContent(of value: Any?) -> (text: String?, note: String?) {
        if let text = value as? String { return (text, nil) }
        guard let blocks = value as? [[String: Any]] else { return (nil, nil) }

        var texts: [String] = []
        var imageBytesTotal = 0
        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String { texts.append(text) }
            case "image":
                imageBytesTotal += imageBytes(of: block)
            default:
                break
            }
        }
        if imageBytesTotal > 0 {
            let size = imageBytesTotal.formatted(.byteCount(style: .file))
            return (
                texts.isEmpty ? nil : texts.joined(separator: "\n"),
                "… a obrázek (\(size)), který se nevypisuje"
            )
        }
        // Bloky **jsou**, ale ani jeden se nedal přečíst — a to se musí přiznat: krok bez těla
        // vypadá jako krok, jehož nástroj nic nevrátil. Nový druh bloku v příští verzi CLI je
        // pravděpodobnější než rozbitá odpověď, takže se z toho nedělá chyba, jen poznámka.
        guard !texts.isEmpty else {
            let kinds = Set(blocks.compactMap { $0["type"] as? String }).sorted().joined(separator: ", ")
            return (nil, kinds.isEmpty ? "odpověď v neznámém tvaru" : "odpověď v blocích: \(kinds)")
        }
        return (texts.joined(separator: "\n"), nil)
    }

    /// Kolik obrázek váží. Počítá se z **délky base64**, ne dekódováním: dekódovat 2,8 MB kvůli
    /// jednomu číslu v hlavičce je práce, kterou nikdo nechtěl. Base64 nese 3 bajty na 4 znaky.
    private func imageBytes(of block: [String: Any]) -> Int {
        let data = (block["source"] as? [String: Any])?["data"] as? String
        return (data?.utf8.count ?? 0) / 4 * 3
    }

    // MARK: - Drobnosti

    private func blocks(of object: [String: Any]) -> [[String: Any]] {
        (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
    }

    /// Čas řádku. `nil` = nemá ho (`last-prompt`), nebo se nedal přečíst — a **domýšlet se
    /// nebude**: čas z předchozí události by tvrdil, kdy se to stalo.
    private func time(of object: [String: Any]) -> Date? {
        guard let stamp = object["timestamp"] as? String else { return nil }
        if let parsed = try? Self.withFraction.parse(stamp) { return parsed }
        return try? Self.withoutFraction.parse(stamp)
    }

    private func size(of text: String) -> String {
        text.utf8.count.formatted(.byteCount(style: .file))
    }

    private func append(
        _ kind: TranscriptEvent.Kind,
        at time: Date?,
        subject: String? = nil,
        body: String? = nil,
        denied: Bool = false,
        into result: inout Transcription
    ) {
        // Strop na jednu událost platí **na všechna těla**, ne jen na výstupy nástrojů: `text`
        // v `user` eventu nese celý obsah skillu (změřeno 7 167 znaků v jednom bloku).
        let trimmed = body.map { Policy.rawSessionBody($0) }
        result.events.append(TranscriptEvent(
            id: result.events.count,
            at: time,
            kind: kind,
            subject: subject,
            body: trimmed?.text,
            bodyCut: trimmed?.cut,
            isDenied: denied
        ))
    }
}
