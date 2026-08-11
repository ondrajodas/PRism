import Foundation
import Testing

@testable import PRism

/// Sazba checků (#215) — poměr v hlavičce tabu i v souhrnu `Přehledu`, a stav za jménem jobu.
///
/// Je to jedno místo pro tři kusy okna (tab, souhrn, chip v hlavičce). Do #215 měl každý svou
/// kopii a už tehdy se rozešly v barvě, takže se tady hlídá, že poměr vyjde všude stejně.
@Suite("Sazba kontrol")
struct ChecksTextTests {
    private func check(
        _ name: String,
        _ bucket: String,
        started: TimeInterval? = nil,
        completed: TimeInterval? = nil
    ) -> PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .init(bucket: bucket),
            link: nil,
            startedAt: started.map { Date(timeIntervalSince1970: $0) },
            completedAt: completed.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func summary(_ buckets: [String]) -> ChecksSummary {
        Policy.summary(of: buckets.enumerated().map { check("c\($0.0)", $0.1) })
    }

    // MARK: - Poměr

    /// Návrh (sekce 05): `1 selhala · 2 běží · 12 prošlo · 22 přeskočeno`.
    @Test("Poměr jde od nejhoršího a skloňuje se")
    func summaryText() {
        let buckets = ["fail"]
            + Array(repeating: "pending", count: 2)
            + Array(repeating: "pass", count: 12)
            + Array(repeating: "skipping", count: 22)

        #expect(ChecksText.summary(of: summary(buckets))
            == "1 selhala · 2 běží · 12 prošlo · 22 přeskočeno")
    }

    /// Nula v souhrnu je slovo navíc, ze kterého nic neplyne.
    @Test("Čeho není ani jeden, v poměru není")
    func summaryOmitsZeroes() {
        #expect(ChecksText.summary(of: summary(["pass", "pass"])) == "2 prošly")
        #expect(ChecksText.summary(of: summary(["fail"])) == "1 selhala")
        #expect(ChecksText.summary(of: summary([])).isEmpty)
    }

    @Test("Skloňování drží u jedné, dvou i pěti")
    func summaryPlurals() {
        #expect(ChecksText.summary(of: summary(["pass"])) == "1 prošla")
        #expect(ChecksText.summary(of: summary(Array(repeating: "pass", count: 3))) == "3 prošly")
        #expect(ChecksText.summary(of: summary(Array(repeating: "pass", count: 5))) == "5 prošlo")
        #expect(ChecksText.summary(of: summary(Array(repeating: "fail", count: 2))) == "2 selhaly")
    }

    /// V `Přehledu` se spadlá část **obarvuje**, takže se musí dát rozeznat — a smí to být
    /// **jedině ta jedna**, jinak by červeně svítil celý poměr.
    @Test("Spadlá část je označená, ostatní ne")
    func marksTheFailingPart() {
        let parts = ChecksText.parts(of: summary(["fail", "pending", "pass"]))

        #expect(parts.map(\.text) == ["1 selhala", "1 běží", "1 prošla"])
        #expect(parts.map(\.isFailure) == [true, false, false])
    }

    /// Zrušený běh se počítá ke spadlým, takže se i obarvuje — z obojího plyne totéž.
    @Test("Zrušený se do spadlé části počítá")
    func countsCancelledAsFailure() {
        let parts = ChecksText.parts(of: summary(["cancel"]))

        #expect(parts.map(\.text) == ["1 selhala"])
        #expect(parts.map(\.isFailure) == [true])
    }

    /// Souhrn v `Přehledu` a hlavička tabu skládají poměr z týchž částí — kdyby se lišily,
    /// tvrdila by dvě místa v okně o jedné sadě checků něco jiného.
    @Test("Věta je složená z týchž částí, ze kterých se kreslí souhrn")
    func summaryIsJoinedParts() {
        let summary = summary(["fail", "pending", "pass", "skipping"])

        #expect(ChecksText.summary(of: summary)
            == ChecksText.parts(of: summary).map(\.text).joined(separator: " · "))
    }

    /// Chip v hlavičce ukazuje **první část poměru**, tedy to nejhorší. Nesmí se rozejít
    /// s `worst`, na kterém stojí jeho barva.
    @Test("První část poměru mluví o nejhorším stavu")
    func headlineMatchesTheWorstState() {
        #expect(ChecksText.parts(of: summary(["pass", "fail"])).first?.isFailure == true)
        #expect(ChecksText.parts(of: summary(["pass", "pending"])).first?.text == "1 běží")
        #expect(ChecksText.parts(of: summary(["pass", "skipping"])).first?.text == "1 prošla")
        // Prázdná sada nemá ani `worst`, ani první část — chip se pak nekreslí.
        #expect(ChecksText.parts(of: summary([])).first == nil)
        #expect(summary([]).worst == nil)
    }

    // MARK: - Stav za jménem jobu

    /// Trvání sází `RunUsageText`, tedy tentýž formát jako útrata a stopky v hlavičce —
    /// porovnává se proto **proti němu**, ne proti napsanému číslu: to by tvrdilo něco
    /// o formátování čísel v locale, ne o téhle sazbě.
    @Test("Za jménem je stav a trvání")
    func detailText() {
        #expect(ChecksText.detail(of: check("a", "fail", started: 0, completed: 134))
            == "selhalo · \(RunUsageText.duration(.seconds(134)))")
        #expect(ChecksText.detail(of: check("a", "pass", started: 0, completed: 41))
            == "prošlo · \(RunUsageText.duration(.seconds(41)))")
        // A že to trvání doopravdy nese, ne jen že se dvě volání téhož shodnou.
        #expect(ChecksText.detail(of: check("a", "fail", started: 0, completed: 134)).contains("14"))
    }

    /// Dokud check neskončil, trvání se **nehádá** — zbude slovo o stavu.
    @Test("Bez konce běhu zbude jen stav")
    func detailWithoutDuration() {
        #expect(ChecksText.detail(of: check("a", "pending", started: 0)) == "běží")
        #expect(ChecksText.detail(of: check("a", "skipping")) == "přeskočeno")
        #expect(ChecksText.detail(of: check("a", "cancel")) == "zrušeno")
    }

    // MARK: - Barvy a symboly

    /// **Z palety návrhu, ne systémová.** Do #215 kreslil seznam `.green`/`.red` ze SwiftUI,
    /// kdežto chip v hlavičce `Palette.ok`/`Palette.crit` — dvě zelené v jednom okně pro jednu
    /// věc. Test to drží pohromadě.
    @Test("Barvy jsou z palety návrhu")
    func colorsComeFromThePalette() {
        #expect(ChecksText.color(of: .passed) == Palette.ok)
        #expect(ChecksText.color(of: .failed) == Palette.crit)
        #expect(ChecksText.color(of: .cancelled) == Palette.crit)
        #expect(ChecksText.color(of: .running) == Palette.accent)
        #expect(ChecksText.color(of: .skipped) == Palette.ink3)
    }

    /// Každý stav má **rozlišitelný** symbol — jinak by se spadlý check poznal od přeskočeného
    /// jedině barvou.
    @Test("Každý stav má vlastní symbol")
    func symbolsAreDistinct() {
        let outcomes: [PullRequestCheck.Outcome] = [.passed, .failed, .running, .skipped, .cancelled]
        let symbols = outcomes.map(ChecksText.symbol(of:))

        #expect(Set(symbols).count == outcomes.count)
        #expect(!symbols.contains(""))
    }
}
