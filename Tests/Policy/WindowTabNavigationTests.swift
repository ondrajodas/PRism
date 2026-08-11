import Foundation
import Testing

@testable import PRism

/// Cyklení pruhem záložek (#245). Vyčerpávající výčet nad `openTabs`, protože je to čistá funkce
/// a jediné místo, kde se rozhoduje, kam `⌃Tab` skočí.
@Suite("Policy — cyklení záložkami")
struct WindowTabNavigationTests {
    private let first = PRIdentifier("cli/cli#1")!
    private let second = PRIdentifier("cli/cli#2")!
    private let third = PRIdentifier("cli/cli#3")!

    @Test("Pruh začíná domácí záložkou a pokračuje v pořadí otevření")
    func theStripStartsAtHome() {
        // Pořadí pruhu je pořadí otevření, ne pořadí použití — přesně to, co je v okně vidět.
        #expect(Policy.tabStrip(open: []) == [.home])
        #expect(
            Policy.tabStrip(open: [first, second])
                == [.home, .pullRequest(first), .pullRequest(second)]
        )
    }

    @Test("Nad jedinou záložkou se nestane nic")
    func aSingleTabGoesNowhere() {
        // Ne pípnutí, ne přeskok domů: v pruhu je jen domácí záložka, takže není kam jít.
        #expect(Policy.tab(.forward, after: .home, open: []) == nil)
        #expect(Policy.tab(.backward, after: .home, open: []) == nil)
    }

    @Test("Domácí záložka cyklí s otevřeným PR")
    func homeCyclesWithTheOnlyPullRequest() {
        // Kvůli tomuhle je domácí záložka v pruhu: jinak by `⌃Tab` nad jedním otevřeným PR
        // nedělal nic, a domů se přitom chodí nejčastěji.
        #expect(Policy.tab(.forward, after: .home, open: [first]) == .pullRequest(first))
        #expect(Policy.tab(.forward, after: .pullRequest(first), open: [first]) == .home)
        #expect(Policy.tab(.backward, after: .home, open: [first]) == .pullRequest(first))
        #expect(Policy.tab(.backward, after: .pullRequest(first), open: [first]) == .home)
    }

    @Test("Dopředu se jde pruhem a za poslední záložkou je domácí")
    func forwardWrapsAroundToHome() {
        let open = [first, second, third]

        #expect(Policy.tab(.forward, after: .home, open: open) == .pullRequest(first))
        #expect(Policy.tab(.forward, after: .pullRequest(first), open: open) == .pullRequest(second))
        #expect(Policy.tab(.forward, after: .pullRequest(second), open: open) == .pullRequest(third))
        // Dokola, jako v prohlížeči.
        #expect(Policy.tab(.forward, after: .pullRequest(third), open: open) == .home)
    }

    @Test("Zpátky se jde pruhem a před domácí záložkou je poslední")
    func backwardWrapsAroundToTheLastTab() {
        let open = [first, second, third]

        // Zbytek po dělení je u negativního dělence negativní, takže tenhle případ je ten,
        // kterým se `-1` v indexu pozná.
        #expect(Policy.tab(.backward, after: .home, open: open) == .pullRequest(third))
        #expect(Policy.tab(.backward, after: .pullRequest(first), open: open) == .home)
        #expect(Policy.tab(.backward, after: .pullRequest(second), open: open) == .pullRequest(first))
        #expect(Policy.tab(.backward, after: .pullRequest(third), open: open) == .pullRequest(second))
    }

    @Test("Krok tam a zpátky se vrátí na tutéž záložku")
    func aStepThereAndBackReturns() {
        // Platí i na okrajích pruhu, kde se cyklí dokola — tam se to nejsnáz pokazí.
        let open = [first, second, third]
        for tab in Policy.tabStrip(open: open) {
            let there = Policy.tab(.forward, after: tab, open: open)
            #expect(there.flatMap { Policy.tab(.backward, after: $0, open: open) } == tab)
        }
    }

    @Test("Záložka, která v pruhu není, nikam nevede")
    func anActiveTabOutsideTheStripGoesNowhere() {
        // Stát se to nemá (`openTab` je jediná cesta k aktivní záložce na PR), ale hádat za
        // takového stavu sousedy by odneslo člověka od toho, co má na obrazovce.
        #expect(Policy.tab(.forward, after: .pullRequest(third), open: [first, second]) == nil)
        #expect(Policy.tab(.backward, after: .pullRequest(third), open: [first, second]) == nil)
    }
}
