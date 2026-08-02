import Testing

@testable import PRism

@Suite("Plural")
struct PluralTests {
    @Test("Jedna dostane jednotné číslo")
    func usesSingularForOne() {
        #expect(Plural.czech(1, one: "nález", few: "nálezy", many: "nálezů") == "1 nález")
    }

    @Test("Dva až čtyři dostanou množné číslo")
    func usesFewForTwoToFour() {
        #expect(Plural.czech(2, one: "soubor", few: "soubory", many: "souborů") == "2 soubory")
        #expect(Plural.czech(4, one: "soubor", few: "soubory", many: "souborů") == "4 soubory")
    }

    @Test("Pět a víc dostane druhý pád")
    func usesManyFromFive() {
        #expect(Plural.czech(5, one: "řádek", few: "řádky", many: "řádků") == "5 řádků")
        #expect(Plural.czech(21, one: "řádek", few: "řádky", many: "řádků") == "21 řádků")
    }

    @Test("Nula dostane druhý pád")
    func usesManyForZero() {
        #expect(Plural.czech(0, one: "nález", few: "nálezy", many: "nálezů") == "0 nálezů")
    }

    /// Číslo se skládá **bez** locale formátování: `Text("\(count) řádků")` by z tisíce
    /// udělalo „1 000“, což je u počtu správně — ale tenhle typ dává řetězec, který se do
    /// `Text(verbatim:)` posílá hotový, takže se musí rozhodnout tady.
    @Test("Tisíce se skupinují")
    func groupsThousands() {
        let text = Plural.czech(1234, one: "řádek", few: "řádky", many: "řádků")

        // Na konkrétní oddělovač se netestuje: čeština používá úzkou nedělitelnou mezeru
        // a její přesná podoba je věc locale, ne tohohle typu.
        #expect(text.hasSuffix(" řádků"))
        #expect(!text.contains("1234"))
    }
}
