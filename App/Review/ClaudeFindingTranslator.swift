import Foundation

/// Překlad nálezů jednou krátkou `claude -p` session na celý běh.
///
/// **Jedno volání na běh, ne na nález** — to bylo v zadání #52 přeceněné. Proti
/// patnáctiminutové review session je krátký překlad drobnost.
struct ClaudeFindingTranslator: FindingTranslating {
    private let claude: URL
    private let runner: any ProcessRunning
    private let timeout: Duration

    init(claude: URL, runner: any ProcessRunning, timeout: Duration = .seconds(120)) {
        self.claude = claude
        self.runner = runner
        self.timeout = timeout
    }

    func translate(
        _ findings: [ReportedFinding],
        to language: FindingsLanguage
    ) async throws -> [FindingTranslation?] {
        guard !findings.isEmpty else { return [] }

        let result = try await runner.run(
            claude,
            arguments: TranslationCommand.arguments(prompt: TranslationCommand.prompt(for: findings, to: language)),
            timeout: timeout
        )
        // Selhání překladu **není** selhání review. Nálezy dorazily a jsou uložené;
        // nepřeložené se ukážou v originále, což je vidět na první pohled. Vyhodit to jako
        // chybu by znamenalo, že drobnost kolem zobrazení shodí výsledek, který už máme.
        guard result.exitCode == 0 else { return Array(repeating: nil, count: findings.count) }

        return TranslationCommand.parse(result.standardOutput, count: findings.count)
    }
}

/// Jak se překladač volá a jak se čte jeho odpověď. Čisté funkce, žádné I/O.
enum TranslationCommand {
    /// **Bez jediného nástroje.** Překlad je transformace textu — session, která nemůže nic
    /// spustit, nemůže ani omylem sáhnout na repozitář. Zákazy zůstávají jako pojistka,
    /// aby tvrdá podmínka „na GitHub se nic neposílá“ nestála na tom, že je povolený seznam
    /// prázdný.
    static func arguments(prompt: String) -> [String] {
        [
            "-p", prompt,
            "--allowedTools", "",
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
    }

    /// Vstup nese `id`, aby se odpověď dala spárovat podle něj a ne podle pořadí. Model,
    /// který jednu položku vynechá nebo prohodí, by u pozičního párování přiřadil překlady
    /// cizím nálezům — a to je horší než nepřeložit vůbec.
    static func prompt(for findings: [ReportedFinding], to language: FindingsLanguage) -> String {
        let input = findings.enumerated().map { index, finding in
            var item: [String: String] = ["id": "\(index)", "summary": finding.summary]
            item["short_summary"] = finding.shortSummary
            item["failure_scenario"] = finding.failureScenario
            return item
        }
        // `[[String: String]]` se serializovat vždycky dá, takže je `?? "[]"` nedosažitelné.
        // Kdyby přece, model dostane prázdný vstup a vrátí prázdnou odpověď — nepřeloží se
        // nic. To je stejný konec jako u každého jiného selhání překladu, ne špatný překlad.
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        Translate these code-review findings into \(language.promptName). \
        Return only a JSON array — no prose, no code fences, no explanation. \
        Keep every "id" exactly as given and translate only the fields that are present. \
        Leave code identifiers, file paths, type names and anything inside backticks \
        exactly as they are; translate only the prose around them. \
        Input: \(json)
        """
    }

    /// Odpověď se čte **defenzivně**, ne přes `Codable`.
    ///
    /// Je to volný text od modelu, ne formát, na kterém bychom se dohodli: může přijít
    /// obalený v ```-blocích, s větou navíc, nebo úplně jinak. Typované dekódování by na
    /// tom padalo a nepřeložený nález je pořád použitelný nález.
    static func parse(_ output: String, count: Int) -> [FindingTranslation?] {
        var translations = [FindingTranslation?](repeating: nil, count: count)
        guard
            let data = jsonArray(in: output),
            let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return translations }

        for item in items {
            guard
                let index = index(of: item["id"], within: count),
                let summary = item["summary"] as? String
            else { continue }
            translations[index] = FindingTranslation(
                summary: summary,
                shortSummary: item["short_summary"] as? String,
                failureScenario: item["failure_scenario"] as? String
            )
        }
        return translations
    }

    /// `id` může přijít jako číslo i jako řetězec — model si vybírá sám. Mimo rozsah se
    /// zahazuje: přiřadit překlad podle vymyšleného indexu by ho dalo cizímu nálezu.
    private static func index(of id: Any?, within count: Int) -> Int? {
        let parsed = (id as? Int) ?? (id as? String).flatMap(Int.init)
        guard let parsed, parsed >= 0, parsed < count else { return nil }
        return parsed
    }

    /// Vykrojí z odpovědi pole. Hledá se první `[` a poslední `]`, takže projde
    /// i odpověď obalená v ```json bloku nebo s větou před ním.
    private static func jsonArray(in output: String) -> Data? {
        guard
            let start = output.firstIndex(of: "["),
            let end = output.lastIndex(of: "]"),
            start < end
        else { return nil }
        return String(output[start...end]).data(using: .utf8)
    }
}
