import Foundation

extension Policy {
    /// Převypráví tenhle souhrn jen diff, který agent má sám? (#377)
    ///
    /// **Jediná heuristika v celém výběru položek** — a stojí ve vlastním souboru schválně: je to
    /// ta jediná předvolba, která může vypnout i něco užitečného, takže musí jít **vyhodit bez
    /// dotyku na zbytek**. Smazat tenhle soubor a jeho jediné volání v
    /// `Policy.agentPromptExclusion(of:options:conversation:)` znamená, že se souhrny přestanou
    /// předvybírat jako vypnuté; nic dalšího se tím nerozbije.
    ///
    /// Pozná se to na **nadpisu `Pull request overview`**, kterým Copilot začíná každé review.
    /// Doslovný nadpis, ne zmínka kdekoli v textu: kolegova věta „viz Pull request overview výš“
    /// je próza, ne převyprávěný diff.
    ///
    /// **Tabulka změněných souborů se jako druhá podmínka zamítla**, i když ji dnešní Copilot pod
    /// nadpis přikládá (`<details>` s `| File | Description |`). Změřeno na dvou skutečných
    /// review: `ondrajodas/PRism#378` tabulku má, ale starší formát na `cli/cli#11451` je jen
    /// nadpis a odrážky — a zrovna ten je čistý převyprávěný diff („Replaces generic JSON decoding
    /// error…“). Druhá podmínka by ho tedy pustila dovnitř a heuristika by nedělala nic právě
    /// v tom případě, na který je.
    ///
    /// Na komentáře pod PR se **nepouští**. Walkthrough od CodeRabbita je tentýž problém, ale jiný
    /// tvar — a vymyslet k němu druhý vzor znamená druhou heuristiku, tedy přesně to, co tohle
    /// issue zakazuje.
    static func summarizesDiff(_ body: String) -> Bool {
        // `TextLines`, ne `split(separator: "\n")`: těla z GitHubu mají `CRLF` (ve fixture
        // `gh/review-copilot-overview.md` na 9 řádcích), a to je ve Swiftu **jeden** `Character`.
        TextLines.nonEmpty(body).contains { markdownHeading(of: $0)?.lowercased() == "pull request overview" }
    }

    /// Nezůstane ze souhrnu po odstranění nadpisů nic? (#377)
    ///
    /// **Není to heuristika, ale syntaktický test** — a proto smí stát vedle té jedné heuristiky:
    /// neptá se, co text znamená, jen jestli v něm kromě nadpisů a HTML komentářů něco je.
    /// Schválení s prázdným tělem je čtvrtina vzorku (`cli/cli#11451`), takže tenhle stav je běžný
    /// a nemá cenu ho agentovi předávat: v zadání by z něj zbyl nadpis bez tvrzení.
    ///
    /// Prázdné tělo vyjde `true` (`allSatisfy` nad prázdným seznamem), a to je správně — je to
    /// tentýž „bez obsahu“, jen bez jediného znaku.
    static func hasNoContent(_ body: String) -> Bool {
        TextLines.nonEmpty(body).allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || (trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->"))
        }
    }

    /// Text nadpisu markdownu — `## Pull request overview` → `Pull request overview`.
    /// `nil` = řádek nadpis není.
    private static func markdownHeading(of line: some StringProtocol) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        return String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
    }
}
