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
            summary.attemptedTools.append(ToolAttempt(name: name, input: block["input"] as? [String: Any]))

            guard name == "ReportFindings" else { continue }
            summary.calledReportFindings = true
            consumeFindings(in: block, into: &summary)
        }
    }

    private func consumeFindings(in block: [String: Any], into summary: inout StreamSummary) {
        guard let reported = (block["input"] as? [String: Any])?["findings"] as? [[String: Any]] else {
            // Nástroj se zavolal, ale obsah se nepodařilo přečíst. Bez záznamu by z toho
            // vyšlo „čisté review“.
            summary.droppedFindings += 1
            return
        }

        for object in reported {
            guard let finding = finding(from: object) else {
                summary.droppedFindings += 1
                continue
            }
            // Reviewer, který hlásí průběžně a na konci pošle kompletní seznam, by jinak
            // dodal každý nález dvakrát. Pozdější hlášení toho **přepíše** dřívější a
            // zůstane na jeho místě: průběžné bývá náčrt, závěrečné doplněné. A doplňuje se
            // i `verdict` s `category`, na kterých stojí blokující příznak — držet se
            // prvního by z potvrzeného nálezu v blokující kategorii udělalo neblokující.
            if let existing = summary.findings.firstIndex(where: { isSameFinding($0, finding) }) {
                summary.findings[existing] = finding
            } else {
                summary.findings.append(finding)
            }
        }
    }

    /// Je to tentýž nález?
    ///
    /// Porovnává se **místo a povinné `summary`**, ne celá hodnota. Ověřeno na skutečném
    /// běhu (#17): reviewer nahlásil tentýž problém dvakrát, jednou průběžně a jednou
    /// v závěrečném seznamu, a mezitím si přeformuloval `short_summary` — porovnání celé
    /// hodnoty ho proto propustilo a v UI byl dvakrát.
    ///
    /// Dva **různé** problémy na jednom řádku se tím neslijí: liší se v `summary`, které je
    /// jediné povinné pole, takže prázdné být nemůže.
    private func isSameFinding(_ left: ReportedFinding, _ right: ReportedFinding) -> Bool {
        left.file == right.file && left.line == right.line && left.summary == right.summary
    }

    private func consumeResult(_ object: [String: Any], into summary: inout StreamSummary) {
        summary.outcome = ReviewOutcome(
            isError: object["is_error"] as? Bool ?? false,
            subtype: object["subtype"] as? String ?? "",
            text: object["result"] as? String
        )
        let denials = object["permission_denials"] as? [[String: Any]] ?? []
        for name in denials.compactMap({ $0["tool_name"] as? String }) where !summary.deniedTools.contains(name) {
            summary.deniedTools.append(name)
        }
        summary.usage = usage(from: object)
    }

    /// Cena, trvání a počet kol z `result` eventu (#148).
    ///
    /// Vrací `nil`, když z toho nedorazilo **nic** — prázdný obal by se od „nevíme“ nedal
    /// odlišit. Jednotlivé pole je `nil` samo o sobě taky: `result` bez `total_cost_usd`
    /// je pořád konec běhu.
    private func usage(from object: [String: Any]) -> RunUsage? {
        let usage = RunUsage(
            cost: nonNegative(object["total_cost_usd"]),
            duration: nonNegative(object["duration_ms"]).map { Duration.milliseconds(Int($0)) },
            turns: nonNegative(object["num_turns"]).map(Int.init)
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
