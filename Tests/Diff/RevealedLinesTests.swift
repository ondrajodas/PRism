import Testing

@testable import PRism

/// Které skryté řádky už uživatel rozbalil. Slučování je tu proto, aby dvě kliknutí na
/// sousední úsek nedala dva záznamy a řádek se nevykreslil dvakrát.
@Suite("RevealedLines")
struct RevealedLinesTests {
    @Test("Prázdné nic neodkrývá")
    func startsEmpty() {
        #expect(RevealedLines().ranges.isEmpty)
    }

    @Test("Nesousedící rozsahy zůstanou oddělené")
    func keepsDisjointRanges() {
        var revealed = RevealedLines()

        revealed.reveal(1...5)
        revealed.reveal(20...25)

        #expect(revealed.ranges == [1...5, 20...25])
    }

    @Test("Překrývající se rozsahy se slijí")
    func mergesOverlappingRanges() {
        var revealed = RevealedLines()

        revealed.reveal(1...10)
        revealed.reveal(5...15)

        #expect(revealed.ranges == [1...15])
    }

    /// Dvě kliknutí na sousední úseky mají dát jeden souvislý blok, ne dva slepené.
    @Test("Sousedící rozsahy se slijí")
    func mergesAdjacentRanges() {
        var revealed = RevealedLines()

        revealed.reveal(1...10)
        revealed.reveal(11...20)

        #expect(revealed.ranges == [1...20])
    }

    @Test("Rozsahy se drží v pořadí, ať přijdou jakkoli")
    func keepsRangesSorted() {
        var revealed = RevealedLines()

        revealed.reveal(30...35)
        revealed.reveal(1...5)
        revealed.reveal(10...15)

        #expect(revealed.ranges == [1...5, 10...15, 30...35])
    }

    @Test("Rozsah uvnitř už odkrytého nic nezmění")
    func ignoresContainedRange() {
        var revealed = RevealedLines()

        revealed.reveal(1...20)
        revealed.reveal(5...10)

        #expect(revealed.ranges == [1...20])
    }

    // MARK: - Dělení skrytého úseku

    @Test("Nedotčený úsek zůstane celý skrytý")
    func leavesAnUntouchedGapHidden() {
        let parts = RevealedLines().split(10...20)

        #expect(parts == [.hidden(10...20)])
    }

    @Test("Odkrytí uprostřed rozdělí úsek na tři")
    func splitsAGapInThree() {
        var revealed = RevealedLines()
        revealed.reveal(13...15)

        #expect(revealed.split(10...20) == [.hidden(10...12), .shown(13...15), .hidden(16...20)])
    }

    @Test("Úplně odkrytý úsek nemá co skrývat")
    func splitsAFullyRevealedGap() {
        var revealed = RevealedLines()
        revealed.reveal(1...100)

        #expect(revealed.split(10...20) == [.shown(10...20)])
    }

    /// Odkrytí přesahuje úsek na obě strany — do dělení se smí promítnout jen jeho průnik.
    @Test("Odkrytí mimo úsek se do něj nepromítne")
    func clipsRevealedRangesToTheGap() {
        var revealed = RevealedLines()
        revealed.reveal(1...12)
        revealed.reveal(18...30)

        #expect(revealed.split(10...20) == [.shown(10...12), .hidden(13...17), .shown(18...20)])
    }
}
