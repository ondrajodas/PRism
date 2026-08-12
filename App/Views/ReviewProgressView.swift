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
                content
            }
        }
    }

    /// Dráhy bez `ScrollView`u — **`internal` schválně, kvůli měření** (#294), stejně jako
    /// u `OverviewView` (#291): `NSScrollView` si obsah na svou šířku ukrojí, takže by se přesah
    /// nenakreslil a rozbitá šířka by od opravené nešla poznat. Prázdný stav ve scrollu není,
    /// takže se měří přímo z `body`.
    @ViewBuilder var content: some View {
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

    /// **Ne `ContentUnavailableView`** (#182): ten se vystředí, nadpis vysází na velikost titulku
    /// a nad text vloží prázdno přes půl okna. Je to vysvětlivka — patří nahoru a drobným písmem.
    ///
    /// Věta říká **nastavení, ne „zatím se nic nedělo“**: od té doby, co dráhu dostane každý
    /// nastavený reviewer, se sem dá dojít jedině s prázdnou sadou skillů. „Zatím se nic nedělo“ by
    /// nad prázdným nastavením vypadalo jako čekání na běh, který se nemá čím spustit.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pro tohle repo není nastavený žádný reviewer.")
            Text("Dráha se kreslí na každý skill z nastavené sady. Dokud je prázdná, není co spustit ani co ukazovat — sada se mění v nastavení, globálně nebo jen pro tohle repo.")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
