import Foundation

/// Překládá `stream-json` výstup `claude` na to, co aplikaci zajímá.
///
/// **Nikdy nevyhodí výjimku.** Stream přichází z cizího procesu, který se dá zabít
/// uprostřed řádku, a jediná rozbitá řádka nesmí zahodit nálezy, které už dorazily.
/// Co se nepodaří přečíst, se **spočítá** — tiché zahození je horší než chyba, protože
/// se v UI nedá odlišit od čistého review.
///
/// Tvar eventů je ověřený proti skutečným běhům, ne odhadnutý — viz `docs/claude-cli.md`
/// a fixtures v `Tests/Fixtures/stream-json/`.
struct StreamParser: Sendable {
    func summarize(_ lines: [String]) -> StreamSummary {
        var summary = StreamSummary()
        for line in lines {
            consume(line, into: &summary)
        }
        return summary
    }

    /// Jeden řádek, jak vzniká. `ReviewRunner` čte výstup průběžně, takže nesmí být nucený
    /// držet celý stream v paměti — a u zabitého běhu jsou částečné nálezy to jediné,
    /// co zbylo.
    func consume(_ line: String, into summary: inout StreamSummary) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            summary.malformedLines += 1
            return
        }

        // `session_id` nese **každý** event (ověřeno u #12), takže se bere z prvního, který
        // dorazí — spoléhat jen na `init` by u useknutého začátku znamenalo přijít o něj
        // zrovna u zabitého běhu, kde je `claude --resume` k něčemu dobrý.
        if summary.sessionID == nil {
            summary.sessionID = object["session_id"] as? String
        }

        switch object["type"] as? String {
        case "assistant":
            consumeAssistant(object, into: &summary)
        case "user":
            consumeUser(object, into: &summary)
        case "result":
            consumeResult(object, into: &summary)
        default:
            // Neznámý event není chyba: `claude` do streamu přidává i věci, které aplikace
            // nepotřebuje (hooky, rate limity, thinking tokeny), a přidá další.
            break
        }
    }

    private func consumeAssistant(_ object: [String: Any], into summary: inout StreamSummary) {
        let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []

        for block in content where block["type"] as? String == "tool_use" {
            guard let name = block["name"] as? String else { continue }
            summary.attemptedTools.append(ToolAttempt(
                name: name,
                input: block["input"] as? [String: Any],
                id: block["id"] as? String
            ))

            guard name == "ReportFindings" else { continue }
            summary.calledReportFindings = true
            consumeFindings(in: block, into: &summary)
        }
    }

    /// Odpovědi na pokusy o nástroje (#326).
    ///
    /// Chodí v `user` eventech jako bloky `tool_result` v `message.content[]` a párují se
    /// s `tool_use` přes `tool_use_id` — ověřeno na všech osmi fixtures, kde je pokusů a odpovědí
    /// vždycky stejně a `id` z `tool_use` sedí na `tool_use_id` z odpovědi.
    ///
    /// `tool_result_meta` leží **na eventu, ne v bloku**, takže se k odpovědi hledá taky podle
    /// `id`. Do #326 se `user` eventy nečetly vůbec a krok v ose vypadal jako provedený od chvíle,
    /// kdy si o něj model řekl.
    private func consumeUser(_ object: [String: Any], into summary: inout StreamSummary) {
        let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        let kinds = nonExecutionKinds(in: object)

        for block in content where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String else { continue }
            resolve(id, with: Policy.toolOutcome(
                isError: block["is_error"] as? Bool ?? false,
                nonExecutionKind: kinds[id],
                text: resultText(of: block["content"])
            ), into: &summary)
        }
    }

    /// `non_execution_kind` po `tool_use_id` — podle čeho se odmítnutí pozná od chyby nástroje.
    private func nonExecutionKinds(in object: [String: Any]) -> [String: String] {
        let meta = object["tool_result_meta"] as? [[String: Any]] ?? []
        return meta.reduce(into: [:]) { result, entry in
            guard let id = entry["id"] as? String,
                  let kind = entry["non_execution_kind"] as? String
            else { return }
            result[id] = kind
        }
    }

    /// Text odpovědi nástroje. Bývá to řetězec, ale u některých nástrojů je to pole bloků
    /// (`ToolSearch` vrací `tool_reference`), a z těch nás zajímají jen textové — hlášku
    /// o odmítnutí nese `text`.
    private func resultText(of value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let blocks = value as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }
        return texts.isEmpty ? nil : texts.joined(separator: " ")
    }

    /// Zapíše odpověď k pokusu, ke kterému patří.
    ///
    /// Páruje se **poslední nezavřený pokus** s tím `id`: `tool_use_id` se v jednom běhu
    /// neopakuje, ale kdyby se to stalo, patří odpověď k tomu, co běželo naposled.
    ///
    /// Odpověď na pokus, který v soupisu **není** — rozbitý řádek s `tool_use`, nebo pokus
    /// zavřený už dřív —, se zahazuje. Není k čemu ji přilepit a vyrobit z ní vlastní krok by
    /// znamenalo krok, o kterém se neví, co v něm běželo.
    private func resolve(
        _ id: String,
        with outcome: ToolAttempt.Outcome,
        into summary: inout StreamSummary
    ) {
        guard let index = summary.attemptedTools.lastIndex(where: {
            $0.id == id && $0.outcome == nil
        }) else { return }

        summary.attemptedTools[index].outcome = outcome
        summary.resolvedTools.append(ToolResolution(id: id, outcome: outcome))
    }

    private func consumeFindings(in block: [String: Any], into summary: inout StreamSummary) {
        guard let reported = (block["input"] as? [String: Any])?["findings"] as? [[String: Any]] else {
            // Nástroj se zavolal, ale obsah se nepodařilo přečíst. Bez záznamu by z toho
            // vyšlo „čisté review“.
            summary.droppedFindings += 1
            return
        }

        // Sada se skládá **celá**, a teprve pak se slévá: rozhoduje totiž to, co v jednom
        // volání stojí vedle sebe (#381). Kdyby se položky přidávaly po jedné, dvě různé
        // věci na jednom řádku z jednoho volání by se potkaly jako „dřívější a pozdější
        // sada“ a slily by se do jedné.
        var batch: [ReportedFinding] = []
        for object in reported {
            guard let finding = finding(from: object) else {
                summary.droppedFindings += 1
                continue
            }
            batch.append(finding)
        }

        // Pozdější hlášení přepíše dřívější — a doplňuje se s ním `verdict` a `category`,
        // na kterých stojí blokující příznak; držet se prvního by z potvrzeného nálezu
        // v blokující kategorii udělalo neblokující. Rozhodnutí o tom, co je „týž nález“,
        // leží v `Policy`, ne tady.
        summary.findings = Policy.mergedFindings(summary.findings, reporting: batch)
    }

    private func consumeResult(_ object: [String: Any], into summary: inout StreamSummary) {
        summary.outcome = ReviewOutcome(
            isError: object["is_error"] as? Bool ?? false,
            subtype: object["subtype"] as? String ?? "",
            text: object["result"] as? String
        )
        rescueDenials(object["permission_denials"] as? [[String: Any]] ?? [], into: &summary)
        summary.usage = usage(from: object)
    }

    /// Odmítnutí z `permission_denials` jako **záchrana** pro pokus, kterému odpověď nedorazila
    /// nebo se nedala přečíst (#326).
    ///
    /// Není to duplicita té cesty z `tool_result`, je to druhý zdroj téhož pro případ, kdy ta
    /// první nedoběhla — rozbitý řádek, useknutý `user` event, starší CLI bez `tool_result_meta`.
    /// **Když dorazí obě, platí ta ze streamu**: přišla ve chvíli, kdy se to stalo, a nese
    /// trvání. Přepsat se smí jedině `failed`, protože „nemělo povolení“ je o té odpovědi
    /// silnější tvrzení než hláška, kterou nástroj vrátil.
    ///
    /// Páruje se **jen po `tool_use_id`**. Bez něj se nepáruje nic: `tool_name` k pokusu
    /// jednoznačně nepatří — `Bash` je v jednom běhu i padesátkrát a odmítnutý z nich je jeden.
    private func rescueDenials(_ denials: [[String: Any]], into summary: inout StreamSummary) {
        for id in denials.compactMap({ $0["tool_use_id"] as? String }) {
            guard let index = summary.attemptedTools.lastIndex(where: { $0.id == id }) else { continue }
            let kind = summary.attemptedTools[index].outcome?.kind
            guard kind == nil || kind == .failed else { continue }

            let outcome = ToolAttempt.Outcome(kind: .denied)
            summary.attemptedTools[index].outcome = outcome
            summary.resolvedTools.append(ToolResolution(id: id, outcome: outcome))
        }
    }

    /// Cena, trvání a počet kol z `result` eventu (#148).
    ///
    /// Vrací `nil`, když z toho nedorazilo **nic** — prázdný obal by se od „nevíme“ nedal
    /// odlišit. Jednotlivé pole je `nil` samo o sobě taky: `result` bez `total_cost_usd`
    /// je pořád konec běhu.
    private func usage(from object: [String: Any]) -> RunUsage? {
        let usage = RunUsage(
            cost: nonNegative(object["total_cost_usd"]),
            duration: wholeNumber(object["duration_ms"]).map(Duration.milliseconds),
            turns: wholeNumber(object["num_turns"])
        )
        return usage.isEmpty ? nil : usage
    }

    /// Nezáporné konečné číslo, nebo `nil`.
    ///
    /// `JSONSerialization` mapuje `true` na `NSNumber`, takže bez té kontroly by z něj vyšla
    /// cena 1 $. Záporná hodnota se zahazuje schválně: šla by do denního součtu a **snížila
    /// by ho**, tedy tvrdila, že mě běh vydělal.
    private func nonNegative(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !(value is Bool) else { return nil }
        let candidate = number.doubleValue
        return candidate.isFinite && candidate >= 0 ? candidate : nil
    }

    /// Totéž jako celé číslo. **`Int(_:)` nad `Double`m tady být nesmí** — na hodnotě mimo
    /// rozsah `Int`u (`"duration_ms": 1e300`) neselže, ale **spadne**, a parser, který nikdy
    /// nevyhodí výjimku, o to míň smí položit celý proces. `Int(exactly:)` vrátí `nil`.
    private func wholeNumber(_ value: Any?) -> Int? {
        nonNegative(value).flatMap { Int(exactly: $0.rounded(.down)) }
    }

    /// Povinné je jen `summary` — bez něj není co ukázat. Zbytek volání tím netrpí; jeden
    /// vadný nález nemá zahodit ostatní.
    private func finding(from object: [String: Any]) -> ReportedFinding? {
        guard let summary = object["summary"] as? String else { return nil }

        return ReportedFinding(
            file: object["file"] as? String,
            line: line(from: object["line"]),
            category: object["category"] as? String,
            verdict: (object["verdict"] as? String).flatMap(FindingVerdict.init(rawValue:)),
            shortSummary: object["short_summary"] as? String,
            summary: summary,
            failureScenario: object["failure_scenario"] as? String
        )
    }

    /// Číslo řádku snese i text, ale musí to být **kladné celé číslo**.
    ///
    /// `JSONSerialization` mapuje `true` na `NSNumber`, takže `as? Int` by z něj udělalo
    /// řádek 1. A `13.5` by se oříznulo na 13. Obojí by nález ukázalo na cizí místo
    /// v souboru, což je horší než nález bez řádku — ten aspoň skončí v tabulce.
    private func line(from value: Any?) -> Int? {
        let candidate: Int?
        if let number = value as? NSNumber, !(value is Bool) {
            let whole = number.intValue
            candidate = Double(whole) == number.doubleValue ? whole : nil
        } else {
            candidate = (value as? String).flatMap(Int.init)
        }
        return candidate.flatMap { $0 > 0 ? $0 : nil }
    }
}
