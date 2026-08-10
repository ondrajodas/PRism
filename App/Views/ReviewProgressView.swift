import SwiftUI

/// Tab `Průběh` (#242, `.lanes`): dráha na revieweera, ne sloupec karet pod sebou.
///
/// **Nahrazuje `ReviewTimelineView`**, který kreslil jeden dlouhý seznam událostí přes všechny
/// reviewery. Ten odpovídal na „co se dělo“, ale ne na „kdo kde je“ — a v panelu o 300 bodech se
/// z něj nedalo přečíst ani jedno. Události zůstávají, jen se z hlavního obsahu staly podrobnosti
/// pod rozbalením každé dráhy.
struct ReviewProgressView: View {
    let lanes: [ReviewerLane]
    /// Pustí jednoho revieweera znovu (#149). `nil` = nejde to, typicky protože něco běží.
    var rerun: ((String) -> Void)?
    /// Zkopíruje do schránky příkaz, jakým by se ten reviewer spustil teď. `nil` = neví se, proti
    /// čemu se diffuje, takže by příkaz nebyl spustitelný a tlačítko se nekreslí.
    var copyCommand: ((String) -> Void)?

    /// Zkrácená jména reviewerů. Počítá se z **celé** sady naráz, protože zkrátit se smí jen to,
    /// co zůstane jednoznačné vůči ostatním.
    private var shortNames: [String: String] {
        Policy.shortReviewerNames(of: lanes.map(\.skill))
    }

    var body: some View {
        if lanes.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    ForEach(lanes) { lane in
                        ReviewerLaneView(
                            lane: lane,
                            shortName: shortNames[lane.skill] ?? lane.skill,
                            rerun: rerun.map { rerun in { rerun(lane.skill) } },
                            copyCommand: copyCommand.map { copy in { copy(lane.skill) } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    /// **Ne `ContentUnavailableView`** (#182): ten se vystředí, nadpis vysází na velikost titulku
    /// a nad text vloží prázdno přes půl okna. Je to vysvětlivka — patří nahoru a drobným písmem.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zatím se nic nedělo.")
            Text("Až se review spustí, poběží tady dráha na každého revieweera — co právě čte, kde je a jak to skončilo.")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
