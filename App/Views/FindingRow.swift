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
    /// Co o nálezu řekla kontrola z minula (#150). `nil` = neběžela nebo se k němu nevyjádřila.
    ///
    /// **Neřadí ani neschovává** — je to odznak, který karta kreslí **pod textem** nálezu
    /// (v hlavičce se ve 300 bodech zkrátil, viz `FindingCardView`). „Vyřešeno“ je tvrzení
    /// modelu, takže z nálezu nesmí ubrat nic než pozornost.
    let recheck: RecheckStatus?

    /// Nálezy v pořadí, ve kterém je řadí `Policy`.
    static func rows(
        of findings: [Finding],
        blocking categories: Set<String> = Policy.defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:],
        rechecks: [FindingKey: RecheckStatus] = [:]
    ) -> [FindingRow] {
        preserving(
            Policy.sorted(findings, categories: categories, dismissals: dismissals),
            blocking: categories,
            dismissals: dismissals,
            rechecks: rechecks
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
        dismissals: [FindingKey: FindingDismissal] = [:],
        rechecks: [FindingKey: RecheckStatus] = [:]
    ) -> [FindingRow] {
        findings.enumerated().map { index, finding in
            // Klíč se skládá **jednou** pro obě mapy: `Policy.key(of:)` sype řetězec, takže
            // dvojí složení na nález je práce navíc při každém překreslení panelu.
            let key = Policy.key(of: finding)
            return FindingRow(
                id: index,
                finding: finding,
                category: finding.category ?? "bez kategorie",
                reviewer: finding.reviewer,
                location: location(of: finding),
                locationHelp: locationHelp(of: finding),
                summary: finding.summary,
                isBlocking: Policy.isBlocking(finding, categories: categories),
                dismissal: dismissals[key],
                recheck: rechecks[key]
            )
        }
    }

    /// Co u nálezu stojí v odznaku závažnosti a jestli se jeho text přeškrtne (#150).
    /// Rozhoduje `Policy` — ten odznak kreslí víc míst a každé z nich se dívá sem.
    var severityBadge: FindingSeverityBadge {
        Policy.severityBadge(isBlocking: isBlocking, recheck: recheck, dismissal: dismissal)
    }

    /// Blokující **a platný**. Výstražná ikona u nálezu, který jsem odmítl, by tvrdila, že
    /// PR pořád na něčem stojí — a přitom se z něj právě proto nepočítá.
    ///
    /// Odvozené z odznaku, ne druhou podmínkou: „blokuje“ je fakt, který se nesmí ztratit ani
    /// tehdy, když kontrola nález má za opravený, a dvě pravidla pro jednu věc se rozejdou.
    var showsBlockingWarning: Bool { severityBadge.showsBlocking }

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
