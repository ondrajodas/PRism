import Foundation

/// Nález převedený na to, co je vidět v tabulce.
///
/// Tabulka nemá vlastní představu o pořadí ani o závažnosti — obojí počítá `Policy`.
/// Tenhle typ jen skládá texty a drží identitu, kterou `Table` potřebuje.
struct FindingRow: Identifiable, Hashable, Sendable {
    /// Pořadí ve výchozím řazení. `Finding` identitu nemá a přidávat mu ji kvůli tabulce
    /// by znamenalo měnit doménový model kvůli zobrazení.
    let id: Int
    let finding: Finding
    let category: String
    let reviewer: String
    /// `file:line`, samotný soubor, nebo `—` u nálezu, který k místu v kódu nepatří.
    /// Právě kvůli němu tabulka existuje a nestačí bubliny.
    let location: String
    /// Co se o místu dozvíš z nápovědy. U nálezu s cestou je to `location` v plné délce —
    /// sloupec se ořezává zepředu, takže z dlouhé cesty je vidět jen konec.
    ///
    /// U nálezu bez místa **není prázdný ani `nil`**: samotné `—` ve sloupci nevysvětluje
    /// nic a tooltip s pomlčkou už vůbec. Věta je jediné, co k tomu jde říct.
    let locationHelp: String
    let summary: String
    let isBlocking: Bool

    /// Nálezy v pořadí, ve kterém je řadí `Policy`.
    static func rows(
        of findings: [Finding],
        blocking categories: Set<String> = Policy.defaultBlockingCategories
    ) -> [FindingRow] {
        Policy.sorted(findings, categories: categories).enumerated().map { index, finding in
            FindingRow(
                id: index,
                finding: finding,
                category: finding.category ?? "bez kategorie",
                reviewer: finding.reviewer,
                location: location(of: finding),
                locationHelp: locationHelp(of: finding),
                summary: finding.summary,
                isBlocking: Policy.isBlocking(finding, categories: categories)
            )
        }
    }

    /// Skládá se do `String`u, ne do `Text`u s interpolací — tam by číslo řádku prošlo
    /// přes locale a z 21663 by bylo „21 663“. Číslo řádku není množství.
    private static func location(of finding: Finding) -> String {
        guard let file = finding.file else { return "—" }
        guard let line = finding.line else { return file }
        return "\(file):\(line)"
    }

    private static func locationHelp(of finding: Finding) -> String {
        guard finding.file != nil else { return "Nález nepatří ke konkrétnímu místu v kódu." }
        return location(of: finding)
    }
}
