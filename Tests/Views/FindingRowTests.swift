import Testing

@testable import PRism

/// Řádek tabulky nálezů — převod nálezu na to, co je v tabulce vidět.
@Suite("FindingRow")
struct FindingRowTests {
    private func finding(
        file: String? = "App/Main.swift",
        line: Int? = 42,
        category: String? = "correctness",
        verdict: FindingVerdict? = .confirmed,
        reviewer: String = "code-review"
    ) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: category,
                verdict: verdict,
                shortSummary: nil,
                summary: "něco se pokazí",
                failureScenario: nil
            ),
            reviewer: reviewer,
            headSha: "abc"
        )
    }

    @Test("Místo je soubor s řádkem")
    func showsFileAndLine() throws {
        let row = try #require(FindingRow.rows(of: [finding()]).first)

        #expect(row.location == "App/Main.swift:42")
        #expect(row.category == "correctness")
        #expect(row.reviewer == "code-review")
        #expect(row.summary == "něco se pokazí")
    }

    /// Číslo řádku není množství. Přes locale by se z 21663 stalo „21 663“.
    @Test("Velké číslo řádku se neformátuje jako množství")
    func neverGroupsTheLineNumber() throws {
        let row = try #require(FindingRow.rows(of: [finding(line: 21663)]).first)

        #expect(row.location == "App/Main.swift:21663")
    }

    @Test("Nález bez řádku ukazuje jen soubor")
    func showsJustTheFileWithoutALine() throws {
        let row = try #require(FindingRow.rows(of: [finding(line: nil)]).first)

        #expect(row.location == "App/Main.swift")
    }

    /// Právě kvůli těmhle nálezům tabulka existuje — bublina by pro ně neměla kam sednout.
    @Test("Nález bez místa má pomlčku")
    func marksAFindingWithoutAPlace() throws {
        let row = try #require(FindingRow.rows(of: [finding(file: nil, line: nil)]).first)

        #expect(row.location == "—")
    }

    /// Sloupec se ořezává zepředu, takže z dlouhé cesty je vidět jen konec — nápověda je
    /// jediné místo, kde je celá.
    @Test("Nápověda u místa je celá cesta")
    func explainsThePlaceInFull() throws {
        let row = try #require(FindingRow.rows(of: [finding(file: "App/Views/FindingsPanel.swift")]).first)

        #expect(row.locationHelp == "App/Views/FindingsPanel.swift:42")
    }

    /// Tooltip s pomlčkou nevysvětluje nic. Věta ano — a tohle je ten druh nálezu, kvůli
    /// kterému tabulka existuje.
    @Test("Nápověda u nálezu bez místa vysvětluje pomlčku")
    func explainsAFindingWithoutAPlace() throws {
        let row = try #require(FindingRow.rows(of: [finding(file: nil, line: nil)]).first)

        #expect(row.location == "—")
        #expect(row.locationHelp == "Nález nepatří ke konkrétnímu místu v kódu.")
    }

    @Test("Nález bez řádku má v nápovědě samotný soubor")
    func explainsAFindingWithoutALine() throws {
        let row = try #require(FindingRow.rows(of: [finding(line: nil)]).first)

        #expect(row.locationHelp == "App/Main.swift")
    }

    @Test("Nález bez kategorie se pojmenuje")
    func namesAFindingWithoutACategory() throws {
        let row = try #require(FindingRow.rows(of: [finding(category: nil)]).first)

        #expect(row.category == "bez kategorie")
    }

    @Test("Blokující nález je označený")
    func marksABlockingFinding() throws {
        let rows = FindingRow.rows(of: [
            finding(category: "correctness", verdict: .confirmed),
            finding(category: "style", verdict: .confirmed),
        ])

        #expect(rows.first(where: { $0.category == "correctness" })?.isBlocking == true)
        #expect(rows.first(where: { $0.category == "style" })?.isBlocking == false)
    }

    /// Výchozí pořadí je to z `Policy`, ne pořadí, ve kterém nálezy dorazily — tabulka
    /// nemá mít vlastní představu o tom, co je nahoře.
    @Test("Výchozí pořadí je z Policy")
    func ordersByPolicyByDefault() {
        let findings = [
            finding(category: "style", verdict: .plausible),
            finding(category: "security", verdict: .confirmed),
            finding(category: "correctness", verdict: .confirmed),
        ]

        let rows = FindingRow.rows(of: findings)

        #expect(rows.map(\.finding) == Policy.sorted(findings))
    }

    @Test("Každý řádek má vlastní identitu")
    func givesEveryRowItsOwnIdentity() {
        let rows = FindingRow.rows(of: [finding(), finding(), finding()])

        #expect(Set(rows.map(\.id)).count == 3)
    }
}
