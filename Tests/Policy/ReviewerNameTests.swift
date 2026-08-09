import Foundation
import Testing

@testable import PRism

/// Zkrácená jména reviewerů do úzkých míst (#182).
///
/// To hlavní, co se dá pokazit potichu: **zkrátit dvě různá id na totéž**. V okně by pak dva
/// reviewery vypadaly jako jeden a nedalo by se poznat, který z nich nález nahlásil.
@Suite("Zkrácená jména reviewerů")
struct ReviewerNameTests {
    @Test("Plugin a skill stejného jména se zkrátí na jedno")
    func collapsesARepeatedName() {
        #expect(Policy.shortReviewerNames(of: ["code-review:code-review"]) == [
            "code-review:code-review": "code-review",
        ])
    }

    @Test("Zkracuje se na část za dvojtečkou")
    func keepsTheSkillPart() {
        #expect(Policy.shortReviewerNames(of: ["superpowers:requesting-code-review"]) == [
            "superpowers:requesting-code-review": "requesting-code-review",
        ])
    }

    @Test("Jméno bez dvojtečky zůstává, jak je")
    func leavesAPlainNameAlone() {
        #expect(Policy.shortReviewerNames(of: ["php-review"]) == ["php-review": "php-review"])
    }

    /// **Nejcennější test téhle sady.** Dva pluginy se stejně pojmenovaným skillem se zkrátit
    /// nesmí — obě jména by pak v okně byla `review` a nález by patřil neznámo komu.
    @Test("Kolize nechá obě jména celá")
    func keepsCollidingNamesInFull() {
        let names = Policy.shortReviewerNames(of: ["a:review", "b:review"])

        #expect(names["a:review"] == "a:review")
        #expect(names["b:review"] == "b:review")
    }

    /// Kolize se týká **jen těch dvou**: reviewer, který se s nikým nesráží, se zkrátí dál.
    @Test("Kolize nezastaví zkracování ostatních")
    func shortensTheRest() {
        let names = Policy.shortReviewerNames(of: ["a:review", "b:review", "superpowers:docs"])

        #expect(names["superpowers:docs"] == "docs")
        #expect(names["a:review"] == "a:review")
    }

    @Test("Prázdný seznam dá prázdnou mapu")
    func handlesAnEmptyList() {
        #expect(Policy.shortReviewerNames(of: [String]()).isEmpty)
    }

    /// Id, které na dvojtečku končí, nemá co zkracovat — prázdné jméno by v okně bylo díra.
    @Test("Id končící dvojtečkou se nechá celé")
    func leavesATrailingColonAlone() {
        #expect(Policy.shortReviewerNames(of: ["plugin:"]) == ["plugin:": "plugin:"])
    }
}
