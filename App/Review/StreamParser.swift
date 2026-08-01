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
            summary.attemptedTools.append(name)

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
            // dodal každý nález dvakrát.
            if !summary.findings.contains(finding) {
                summary.findings.append(finding)
            }
        }
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
