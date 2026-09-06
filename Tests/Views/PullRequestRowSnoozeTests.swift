import SwiftUI
import Testing

@testable import PRism

/// Nabídka `Odložit` na řádku fronty (#512).
///
/// Dvě třídy tvrzení a obě jsou o tom, co se **nenakreslí**. **Bez nabídky se tlačítko nekreslí:**
/// vlastní řádek dostane prázdné `offers` (`Policy.canSnooze`), a tlačítko s prázdnou nabídkou je
/// tlačítko, po kterém se nic nestane — zrovna ten stav, kvůli kterému se v #333 přestala kreslit
/// zakázaná `Prompt →`. **Bez akce taky ne:** řádek, kterému o odložení nikdo nic neřekl (náhledy),
/// nemá odložení odkud vzít. V `body` se ani jedno tvrdit nedá, proto je rozhodnutí pojmenované.
@Suite("Řádek fronty — Odložit (#512)")
@MainActor
struct PullRequestRowSnoozeTests {
    private let offers = Policy.snoozeOffers(now: Date(timeIntervalSince1970: 1_700_000_000))

    private func row(action: SnoozeAction?) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("cli/cli#14252")!,
                title: "chore: modernize dependencies",
                author: "odinuv",
                url: URL(string: "https://github.com/cli/cli/pull/14252")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: .completed(findings: 6),
            snoozeAction: action
        )
    }

    @Test("S nabídkou i s akcí se Odložit kreslí")
    func drawsTheSnoozeAction() {
        #expect(row(action: SnoozeAction(offers: offers, snooze: { _ in })).showsSnoozeAction)
    }

    /// **Nejcennější tvrzení téhle sady.** Vlastní řádek dostane ze storu prázdné `offers`,
    /// protože `Policy.canSnooze` pustí jedině cizí PR — a kdyby se tlačítko kreslilo i nad
    /// prázdnou nabídkou, byl by z něj prvek, po kterém se nic nestane.
    @Test("S prázdnou nabídkou se Odložit nekreslí")
    func drawsNothingWithoutOffers() {
        #expect(!row(action: SnoozeAction(offers: [], snooze: { _ in })).showsSnoozeAction)
    }

    /// A **výchozí hodnota je „nekreslit“**: řádek, kterému o odložení nikdo nic neřekl (náhledy,
    /// testy), nabídku nemá — jinak by se objevila i tam, kde ji nikdo nemá odkud vzít.
    @Test("Řádek bez informace o odložení nabídku nemá")
    func defaultsToNoSnooze() {
        let bare = PullRequestRow(pullRequest: row(action: nil).pullRequest, reviewState: .notStarted)

        #expect(!bare.showsSnoozeAction)
        #expect(bare.snoozeAction == nil)
    }

    /// Že nabídka volá **tu podmínku, kterou dostala**. Sám `Button` se v testu stisknout nedá,
    /// takže se tvrdí uzávěr — jediná věc mezi řádkem a storem.
    @Test("Nabídka předá zvolenou podmínku")
    func passesTheChosenCondition() {
        var chosen: SnoozeCondition?
        let row = row(action: SnoozeAction(offers: offers, snooze: { chosen = $0 }))

        row.snoozeAction?.snooze(offers[1].condition)

        #expect(chosen == .nextPush(head: nil))
    }
}
