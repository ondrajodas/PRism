import Testing

@testable import PRism

/// Zapamatované obarvení řádků (#224).
///
/// Cache se dá pokazit potichu dvěma způsoby a oba jsou tady: **vrátit cizí obarvení** (klíč bez
/// jazyka) a **růst bez hranice** (nic ji nevyprazdňuje). Obojí by v okně vypadalo normálně —
/// první jako divně obarvený soubor, druhé jako aplikace, která po dni používání ubírá paměť.
@Suite("SyntaxRunCache (#224)")
struct SyntaxRunCacheTests {
    private let lines = [
        "    let value = compute(1)",
        "# poznámka",
        "func handle() throws -> Int {",
        "",
        "    return \"a $name b\"  // konec",
    ]

    @Test("Zapamatované obarvení je totéž jako spočítané")
    func matchesTheScanner() {
        let cache = SyntaxRunCache()
        for line in lines {
            let computed = SyntaxHighlighter.scan(line, in: .swift)
            // Podruhé už jde o odpověď z cache — musí vyjít stejně jako průchod řádkem.
            #expect(cache.runs(of: line, in: .swift) == computed)
            #expect(cache.runs(of: line, in: .swift) == computed)
        }
    }

    @Test("Obarvení přes SyntaxHighlighter jde přes cache a nic tím nemění")
    func highlighterGoesThroughTheCache() {
        for line in lines {
            #expect(SyntaxHighlighter.runs(of: line, in: .swift) == SyntaxHighlighter.scan(line, in: .swift))
        }
    }

    // MARK: - Klíč

    /// **Tohle je ten tichý případ.** Bez jazyka v klíči by se `# poznámka` obarvená v shellu
    /// vrátila i pro Swift — tedy komentář tam, kde je to obyčejný text.
    @Test("Tentýž text v jiném jazyce dostane své obarvení")
    func keepsLanguagesApart() {
        let cache = SyntaxRunCache()
        let line = "# poznámka"

        #expect(cache.runs(of: line, in: .shell).map(\.kind) == [.comment])
        #expect(cache.runs(of: line, in: .swift).allSatisfy { $0.kind == .plain })
        // A zpátky, ať je vidět, že se druhý jazyk nepřepsal přes první.
        #expect(cache.runs(of: line, in: .shell).map(\.kind) == [.comment])
    }

    @Test("Prázdný řádek nevrací nic")
    func handlesAnEmptyLine() {
        let cache = SyntaxRunCache()
        #expect(cache.runs(of: "", in: .swift).isEmpty)
    }

    // MARK: - Meze

    @Test("Cache nepřeroste počet řádků")
    func staysWithinTheLineLimit() {
        let cache = SyntaxRunCache(capacity: 10)
        for index in 0..<200 {
            _ = cache.runs(of: "    let value\(index) = compute(\(index))", in: .swift)
            #expect(cache.count <= 10)
        }
    }

    @Test("Cache nepřeroste rozpočet na délku řádků")
    func staysWithinTheByteBudget() {
        // Kapacita vysoko, ať mez drží opravdu rozpočet: 40 řádků po ~100 bajtech je 4 kB.
        let cache = SyntaxRunCache(capacity: 10_000, budget: 1024)
        for index in 0..<40 {
            _ = cache.runs(of: String(repeating: "x", count: 100) + "\(index)", in: .swift)
            #expect(cache.count <= 12)
        }
    }

    @Test("Po vyprázdnění se řádek spočítá znovu a vyjde stejně")
    func recomputesAfterAFlush() {
        let cache = SyntaxRunCache(capacity: 4)
        let first = "    let value = compute(0)  // první"
        let computed = SyntaxHighlighter.scan(first, in: .swift)
        #expect(cache.runs(of: first, in: .swift) == computed)

        for index in 1...20 {
            _ = cache.runs(of: "    let value\(index) = compute(\(index))", in: .swift)
        }
        #expect(cache.count <= 4)
        #expect(cache.runs(of: first, in: .swift) == computed)
    }

    // MARK: - Souběh

    /// Cache je sdílená a `SyntaxHighlighter.runs` je volatelný odkudkoli, takže se do ní může
    /// psát ze dvou míst naráz. Zámek se nedá otestovat tvrzením — tenhle test hlídá, že se
    /// souběžný přístup nerozsype a že z něj vypadne správné obarvení.
    @Test("Souběžné čtení a zápis vrátí správné obarvení")
    func survivesConcurrentUse() async {
        let cache = SyntaxRunCache(capacity: 50)
        let shared = lines
        let expected = shared.map { SyntaxHighlighter.scan($0, in: .swift) }

        await withTaskGroup(of: Bool.self) { group in
            for round in 0..<50 {
                group.addTask {
                    // Půlka úloh míří na tytéž řádky (čtení z cache), půlka přidává nové (zápis
                    // a vyprazdňování) — jinak by se souběh na zámku nikdy nepotkal.
                    if round.isMultiple(of: 2) {
                        return zip(shared, expected).allSatisfy { cache.runs(of: $0, in: .swift) == $1 }
                    }
                    let line = "    let value\(round) = compute(\(round))"
                    return cache.runs(of: line, in: .swift) == SyntaxHighlighter.scan(line, in: .swift)
                }
            }
            for await matched in group { #expect(matched) }
        }
        #expect(cache.count <= 50)
    }
}
