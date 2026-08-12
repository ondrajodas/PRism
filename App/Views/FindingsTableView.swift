import SwiftUI

/// Tabulka nálezů přes celou šířku tabu (#242, `.ftable`).
///
/// **Ne `Table`.** Ta je AppKit tabulka, takže se offscreen nevykreslí (viz `docs/testovani.md`)
/// a rozbalený nález pod řádkem v ní udělat nejde — a právě rozbalení je to, čím se tabulka
/// vyrovnává s tím, že se dlouhý nález na jeden řádek nevejde. Řazení podle hlavičky je proti tomu
/// pár řádků v `Policy`.
///
/// Řazení se **vrací** po #175, který ho zahodil kvůli šířce panelu: přes celé okno je sloupců
/// dost, aby mělo co dělat.
struct FindingsTableView: View {
    let rows: [FindingTableRow]
    let layout: FindingTableLayout
    /// Ke kterému PR tabulka patří. Není to popisek: podle něj se zapomíná, co bylo rozbalené —
    /// viz `expanded`.
    let pullRequest: PRIdentifier
    @Binding var sort: FindingTableSort?
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Kde stojí kurzor procházení nálezů (#187) — řádek na tom místě se podbarví, takže tabulka
    /// a lišta nad diffem ukazují totéž.
    var current: FindingPlace?
    var findingActions: FindingActions?
    var draft = FileDraftActions()
    let jump: (Finding) -> Void

    /// Která místa jsou rozbalená. Klíčem je **místo**, ne index řádku: přeřazením sloupce se
    /// indexy přečíslují a rozbalené by se přesunulo na cizí nález.
    ///
    /// **Nesmí přetéct mezi pull requesty**: `file:line` z cizího PR je náhodná shoda, takže by se
    /// na jiném PR sám od sebe rozbalil nález, na který nikdo neklikl. Je to tatáž past jako
    /// u kurzoru procházení (#187), a stejně jako on se resetuje při změně PR — detail si SwiftUI
    /// mezi pull requesty ponechá, takže `@State` sám nezmizí.
    @State private var expanded: Set<FindingPlace> = []
    /// Rozbalené nálezy **bez místa v kódu**. Ty `FindingPlace` nemají, takže je nese vlastní
    /// množina klíčovaná identitou nálezu — tou samou, kterou se klíčují odmítnutí.
    @State private var expandedWithoutPlace: Set<FindingKey> = []

    var body: some View {
        ScrollView {
            content
        }
        .task(id: pullRequest) {
            expanded = []
            expandedWithoutPlace = []
        }
    }

    /// Tabulka bez `ScrollView`u — **`internal` schválně, kvůli měření** (#294), stejně jako
    /// u `OverviewView` (#291): `NSScrollView` si obsah na svou šířku ukrojí, takže by se přesah
    /// nenakreslil a rozbitá šířka by od opravené nešla poznat. A zrovna tady je co měřit: šířky
    /// sloupců jsou **spočítané** z předané šířky (`Policy.findingTableLayout`), takže se dají
    /// spočítat i vedle.
    @ViewBuilder var content: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(rows) { row in
                    FindingTableRowView(
                        row: row,
                        layout: layout,
                        blockingCategories: blockingCategories,
                        isCurrent: isCurrent(row),
                        isExpanded: isExpanded(row),
                        findingActions: findingActions,
                        draft: draft,
                        toggle: { toggle(row) },
                        jump: { jump(row.representative.finding) }
                    )
                }
            } header: {
                header
            }
        }
    }

    // MARK: - Hlavička

    /// Hlavička sloupců (`.fcols`). Ukotvená, takže při scrollování zůstane vidět, podle čeho je
    /// tabulka setříděná.
    private var header: some View {
        HStack(alignment: .center, spacing: FindingTableLayout.spacing) {
            Color.clear.frame(width: FindingTableLayout.bar, height: 1)
            column("závažnost", .severity, width: layout.severity)
            column("shrnutí", .summary, width: layout.summary)
            column("místo", .location, width: layout.location)
            if let width = layout.reviewer {
                column("reviewer · kategorie", .reviewer, width: width)
            }
            Color.clear.frame(width: layout.actions, height: 1)
        }
        .padding(.horizontal, FindingTableLayout.inset)
        .padding(.vertical, 8)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func column(_ title: String, _ column: FindingTableColumn, width: Double) -> some View {
        Button {
            sort = FindingTableSort.toggled(column, from: sort)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .font(.system(size: 10))
                    .tracking(0.9)
                    .textCase(.uppercase)
                if sort?.column == column {
                    Image(systemName: sort?.isAscending == true ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(sort?.column == column ? Palette.ink2 : Palette.ink3)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Setřídit podle sloupce \(title)")
    }

    // MARK: - Rozbalení

    private func isCurrent(_ row: FindingTableRow) -> Bool {
        guard let current else { return false }
        return FindingPlace(row.group) == current
    }

    private func isExpanded(_ row: FindingTableRow) -> Bool {
        guard let place = FindingPlace(row.group) else {
            return expandedWithoutPlace.contains(Policy.key(of: row.representative.finding))
        }
        return expanded.contains(place)
    }

    private func toggle(_ row: FindingTableRow) {
        guard let place = FindingPlace(row.group) else {
            let key = Policy.key(of: row.representative.finding)
            expandedWithoutPlace.formSymmetricDifference([key])
            return
        }
        expanded.formSymmetricDifference([place])
    }
}
