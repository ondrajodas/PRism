import SwiftUI

/// Sloupcový graf útraty za posledních pár dní (#181).
///
/// **Vlastní soubor od #515**: `DashboardView` odešel s kartami a graf zůstal — kreslí ho blok
/// `Dneska stálo` v pravém sloupci desky (`BoardView`).
///
/// **Dnešek je zvýrazněný**, ostatní dny jsou tlumené: blok mluví o dnešku a graf je kontext,
/// ne druhé číslo. Den bez útraty zůstává v řadě jako **čárka o jednom bodu** — nulová výška by
/// z něj udělala prázdné místo a sloupce by přestaly znamenat dny.
struct SpendSparkline: View {
    let days: [DaySpend]

    var body: some View {
        // **Nejdražší den se hledá jednou, ne u každého sloupce** (nález Copilota): škála je
        // vlastnost celé řady, ne jednotlivého dne, takže se předává argumentem. S dotazem uvnitř
        // `height(of:)` to bylo kvadratické v počtu dní — u sedmi je to pár porovnání, ale kresba
        // se počítá při **každém** průchodu tělem a řada se dá rozšířit jednou konstantou.
        let peak = days.map(\.spend.cost).max() ?? 0
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days) { day in
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(Palette.accent)
                    .opacity(day.id == days.last?.id ? 1 : 0.45)
                    .frame(height: Self.height(of: day, peak: peak))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.fullHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Útrata za posledních \(days.count) dní")
    }

    /// Výška podle nejdražšího dne v okně. Kdyby se škálovalo podle absolutní částky, byl by
    /// graf u levného týdne plochý a nedalo by se z něj nic přečíst.
    ///
    /// **Podlaha je jeden bod, ne nula** — i den, ve kterém se neutratilo nic, musí být v řadě
    /// vidět, jinak se nedá spočítat, kolikátý zleva je dnešek.
    ///
    /// `peak` je **argument, ne dotaz na `days`**: viz `body`.
    private static func height(of day: DaySpend, peak: Double) -> Double {
        guard peak > 0 else { return floorHeight }
        return max(floorHeight, fullHeight * day.spend.cost / peak)
    }

    private static let fullHeight = 26.0
    private static let floorHeight = 1.0
}
