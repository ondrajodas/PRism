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
    /// Jak jsem nález posoudil (#113). `nil` = platí.
    ///
    /// Nový sloupec kvůli tomu **není**: při šířkách z #60 nemá kam, takže stav visí
    /// u `Kategorie` jako odznak a v nápovědě.
    let dismissal: FindingDismissal?

    /// Nálezy v pořadí, ve kterém je řadí `Policy`.
    static func rows(
        of findings: [Finding],
        blocking categories: Set<String> = Policy.defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [FindingRow] {
        preserving(
            Policy.sorted(findings, categories: categories, dismissals: dismissals),
            blocking: categories,
            dismissals: dismissals
        )
    }

    /// Řádky **v pořadí, v jakém přišly** — bez vlastního řazení.
    ///
    /// Potřebuje to tabulka nálezů (#242): uvnitř skupiny už je pořadí dané tím, podle kterého
    /// sloupce se řadí, takže druhé řazení podle závažnosti by přepsalo volbu uživatele a řádek
    /// by se popisoval jiným nálezem, než podle kterého se zařadil.
    static func preserving(
        _ findings: [Finding],
        blocking categories: Set<String> = Policy.defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [FindingRow] {
        findings.enumerated().map { index, finding in
            FindingRow(
                id: index,
                finding: finding,
                category: finding.category ?? "bez kategorie",
                reviewer: finding.reviewer,
                location: location(of: finding),
                locationHelp: locationHelp(of: finding),
                summary: finding.summary,
                isBlocking: Policy.isBlocking(finding, categories: categories),
                dismissal: dismissals[Policy.key(of: finding)]
            )
        }
    }

    /// Blokující **a platný**. Výstražná ikona u nálezu, který jsem odmítl, by tvrdila, že
    /// PR pořád na něčem stojí — a přitom se z něj právě proto nepočítá.
    var showsBlockingWarning: Bool { isBlocking && dismissal == nil }

    /// Co se o kategorii dozvíš z nápovědy. U odmítnutého nálezu i to, proč neplatí — sloupec
    /// unese odznak, ale ne celou větu.
    var categoryHelp: String {
        guard let dismissal else { return category }
        return "\(category) · odmítnuto: \(dismissal.reason.explanation)"
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
