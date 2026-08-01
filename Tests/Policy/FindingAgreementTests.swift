import Foundation
import Testing

@testable import PRism

@Suite("Policy.groups")
struct FindingAgreementTests {
    @Test("Dva reviewery na jednom řádku jsou jedna skupina s odznakem 2×")
    func twoReviewersOnOneLineAgree() {
        let groups = Policy.groups(of: [
            makeFinding(file: "Cart.swift", line: 13, reviewer: "code-review"),
            makeFinding(file: "Cart.swift", line: 13, reviewer: "security-review"),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.agreement == 2)
        // Texty se neslučují — nesouhlas dvou reviewerů je informace.
        #expect(groups.first?.findings.count == 2)
    }

    @Test("Tři reviewery dají 3×")
    func threeReviewersAgree() {
        let groups = Policy.groups(of: [
            makeFinding(file: "Cart.swift", line: 13, reviewer: "code-review"),
            makeFinding(file: "Cart.swift", line: 13, reviewer: "security-review"),
            makeFinding(file: "Cart.swift", line: 13, reviewer: "perf-review"),
        ])

        #expect(groups.first?.agreement == 3)
    }

    @Test("Jeden nález je 1×")
    func aLoneFindingIsOne() {
        let groups = Policy.groups(of: [makeFinding(file: "Cart.swift", line: 13)])

        #expect(groups.first?.agreement == 1)
    }

    @Test("Jeden reviewer si dvěma nálezy nepřikyvuje")
    func oneReviewerDoesNotAgreeWithItself() {
        // Dva různé problémy na jednom řádku nejsou shoda dvou názorů.
        let groups = Policy.groups(of: [
            makeFinding(file: "Cart.swift", line: 13, summary: "první"),
            makeFinding(file: "Cart.swift", line: 13, summary: "druhý"),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.findings.count == 2)
        #expect(groups.first?.agreement == 1)
    }

    @Test("Různá místa se neslučují")
    func differentPlacesStayApart() {
        let groups = Policy.groups(of: [
            makeFinding(file: "Cart.swift", line: 13),
            makeFinding(file: "Cart.swift", line: 14),
            makeFinding(file: "Order.swift", line: 13),
        ])

        #expect(groups.count == 3)
    }

    @Test("Nálezy bez řádku se neslučují")
    func findingsWithoutALineStayApart() {
        // „Stejný soubor bez řádku" není místo — takové nálezy patří do tabulky, každý sám.
        let groups = Policy.groups(of: [
            makeFinding(file: "Cart.swift", line: nil, reviewer: "code-review"),
            makeFinding(file: "Cart.swift", line: nil, reviewer: "security-review"),
            makeFinding(file: nil, line: nil),
        ])

        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.agreement == 1 })
    }

    @Test("Pořadí skupin kopíruje pořadí vstupu")
    func groupOrderFollowsTheInput() {
        // Setříděný vstup dá setříděný výstup, takže `Policy` nemá dvě různá řazení.
        let groups = Policy.groups(of: [
            makeFinding(file: "Order.swift", line: 99),
            makeFinding(file: "Cart.swift", line: 13),
            makeFinding(file: "Order.swift", line: 99, reviewer: "security-review"),
        ])

        #expect(groups.map(\.file) == ["Order.swift", "Cart.swift"])
        #expect(groups.first?.agreement == 2)
    }

    @Test("Prázdný vstup nedá žádnou skupinu")
    func nothingInNothingOut() {
        #expect(Policy.groups(of: []).isEmpty)
    }
}
