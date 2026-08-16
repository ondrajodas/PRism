import Foundation
import Testing

@testable import PRism

/// Kdy se `Ukázat, co přibylo` **nabídne** (#284).
///
/// Čistá funkce, takže výčtem: každý z důvodů, proč tlačítko nemá být, se dá zrušit jedním
/// znakem v podmínce — a zrušený se pozná jedině tím, že na něj někdo míří testem.
///
/// **Nejcennější jsou tady ty záporné.** Tlačítko, které se nabídne, když nemá, otevře diff, jaký
/// člověk nečekal (po přepsané historii dokonce **víc než celý diff PR**, změřeno na
/// `cli/cli#14062`: 102 kB ve 22 souborech proti 15 kB ve třech) — a to je přesně to, co zadání
/// zakazuje.
@Suite("Policy — co přibylo od minule (#284)")
struct IncrementalDiffPolicyTests {
    private let seen = "4f2ac9188cd"
    private let head = "9c1de0212ab"

    @Test("Posunutá hlava bez přepsané historie dá rozsah")
    func offersTheRange() {
        let range = Policy.incrementalDiff(from: seen, to: head, rewroteHistory: false)

        #expect(range == IncrementalDiffRange(seen: seen, head: head))
    }

    /// Pořadí je půlka odpovědi: obráceně by `compare` vrátil, co z větve **zmizelo**.
    @Test("Rozsah jde od viděné hlavy k dnešní")
    func keepsTheDirection() {
        let range = Policy.incrementalDiff(from: seen, to: head, rewroteHistory: false)

        #expect(range?.seen == seen)
        #expect(range?.head == head)
    }

    @Test("Bez viděné hlavy se nenabídne nic")
    func needsASeenHead() {
        #expect(Policy.incrementalDiff(from: nil, to: head, rewroteHistory: false) == nil)
        #expect(Policy.incrementalDiff(from: "", to: head, rewroteHistory: false) == nil)
    }

    /// Dokud se nenačte detail, dnešní hlavu neznáme — a rozsah by neměl druhý konec.
    @Test("Bez dnešní hlavy se nenabídne nic")
    func needsAHead() {
        #expect(Policy.incrementalDiff(from: seen, to: nil, rewroteHistory: false) == nil)
        #expect(Policy.incrementalDiff(from: seen, to: "", rewroteHistory: false) == nil)
    }

    @Test("Stejná hlava znamená prázdný rozsah, tedy žádné tlačítko")
    func refusesAnEmptyRange() {
        #expect(Policy.incrementalDiff(from: head, to: head, rewroteHistory: false) == nil)
    }

    /// Po force pushi je společný předek obou hlav až tam, kde větev vznikla, takže by trojtečkový
    /// rozsah vrátil celý PR i s tím, co se mezitím přineslo z base větve.
    @Test("Po přepsané historii se nenabídne nic")
    func refusesAfterARewrite() {
        #expect(Policy.incrementalDiff(from: seen, to: head, rewroteHistory: true) == nil)
    }

    /// `nil` je „nevíme“ (nenačtená časová osa), ne „nepřepsala se“. Nabídnout rozsah, o kterém
    /// nevíme, jestli dává smysl, je horší než ho nenabídnout — a je to ten stav, ve kterém je
    /// aplikace pokaždé, když se PR otevře.
    @Test("Neznámá historie se chová jako přepsaná")
    func refusesWhenHistoryIsUnknown() {
        #expect(Policy.incrementalDiff(from: seen, to: head, rewroteHistory: nil) == nil)
    }
}
