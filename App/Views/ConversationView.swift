import SwiftUI

/// Tab `Konverzace` (#183) — časová osa toho, co se na PR dělo.
///
/// **Skutečná osa s uzly**, ne seznam karet pod sebou: karta je něčí text, uzel je záznam děje,
/// a tvar uzlu nese druh — pravidlo, které zavedlo #171. Svislá čára mezi uzly je to, co z toho
/// dělá dějiny místo výpisu.
///
/// Vlákna **s kotvou** zůstávají bublinami u kódu; sem patří jen ta, která se v dnešním diffu
/// nemají kde ukázat. Jediný domov konverzace se nedělí, jen stěhuje z `Přehledu`.
struct ConversationView: View {
    var entries: [ConversationEntry] = []
    /// Stav načtení konverzace. `nil` = ještě se nezačalo.
    var state: ConversationState?
    var viewer: String = ""
    /// Kolik se toho do stránek nevešlo. **Musí zůstat vidět** — chybějící komentář se od
    /// „nikdo nic nenapsal“ jinak nepozná.
    var missing: ConversationShortfall = ConversationShortfall()
    var threadActions = ThreadActions()
    var refresh: () -> Void = {}
    /// Odkdy je co nové (#173). `nil` = značka se nekreslí.
    var lastVisit: Date?
    /// Zastaraly nálezy nebo rozdělané review? U force-pushe se to říká **přímo u události**.
    var isStale = false
    var rerun: (() -> Void)?
    /// Psaní do diskuze pod PR (#216). `nil` = composer se nekreslí — je to stav pro náhledy
    /// a testy skládání, kde není kam odesílat.
    var composer: ConversationComposer?

    @State private var filter: ConversationFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            // Plochu pod osou (`--panel`) maluje detail PR pro všechny tři taby najednou,
            // ať se nemůžou rozejít. Composer a lišta si nad ní kreslí vlastní `chrome`.
            timeline
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // **Composer je pod osou, ne v ní**: zůstává na místě, i když se osou scrolluje,
            // a nezmizí zúžením filtru. Rozepsaná věta se nesmí schovat tím, na co se člověk
            // zrovna dívá.
            if let composer {
                ConversationComposerView(
                    text: composer.text,
                    viewer: viewer,
                    state: composer.state,
                    block: composer.block,
                    commit: composer.setText,
                    send: composer.send
                )
            }
        }
    }

    // MARK: - Lišta

    private var toolbar: some View {
        HStack(spacing: 12) {
            filters
            if let loadedAt {
                Text(verbatim: "načteno v \(loadedAt)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            // Zkrácená konverzace to musí říct: chybějící komentář se od „nikdo nic nenapsal“
            // jinak nepozná — a zbytek je jedině na GitHubu.
            if missing.any {
                Label {
                    Text(verbatim: "\(missing.summary) — otevři PR na GitHubu")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Lišta je chrome, jako hlavička bloku kontrol a jako `.convbar` v návrhu.
        .background(Palette.chrome)
    }

    /// Zúžení osy. Počty jsou z **plné** osy: číslo, které se mění tím, na co se zrovna koukám,
    /// se nedá přečíst.
    private var filters: some View {
        let counts = Policy.conversationCounts(of: entries)
        return HStack(spacing: 2) {
            ForEach(ConversationFilter.allCases, id: \.self) { option in
                Button {
                    filter = option
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: option.czechLabel)
                        // U `Vše` se počet nepíše: je to celek, ne výběr z něj.
                        if option != .all, let count = counts[option], count > 0 {
                            Text(verbatim: "\(count)")
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink3)
                        }
                    }
                    .font(.system(size: 11.5, weight: filter == option ? .semibold : .regular))
                    .foregroundStyle(filter == option ? Palette.ink : Palette.ink2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        if filter == option {
                            RoundedRectangle(cornerRadius: 6).fill(Palette.raised)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
    }

    private var loadedAt: String? {
        guard case .loaded(_, let at) = state else { return nil }
        return at.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Osa

    @ViewBuilder private var timeline: some View {
        // **Řádky, ne uzly s indexem.** `ForEach` nad `Array(nodes.enumerated())` znamenal nové
        // pole tuplů při každém průchodu tělem a identitu čtenou keypathem přes tuple, tedy
        // kopii celého `ConversationNode` při každém dotazu líného seznamu na identitu (#361).
        // Značka poslední návštěvy je proto rozhodnutí v `Policy`, ne `if` nad sousedním uzlem.
        let rows = Policy.conversationRows(of: entries, filter: filter, since: lastVisit)
        if rows.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        if row.isFirstNew {
                            SinceMarker(at: lastVisit)
                        }
                        ConversationNodeView(
                            node: row.node,
                            viewer: viewer,
                            threadActions: threadActions,
                            isStale: isStale,
                            rerun: rerun
                        )
                    }
                }
                .padding(16)
                // Odsazení se musí odečíst, jinak by uzly dostaly šířku celé osy a přetekly
                // o těch 16 bodů na každé straně (#220).
                .narrowingWidth(by: 32)
            }
        }
    }

    @ViewBuilder private var empty: some View {
        switch state {
        case .failed(let reason):
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Konverzaci se nepodařilo načíst",
                message: "Bez ní není poznat, jestli je ticho, nebo se jen nenačetla.",
                detail: reason,
                primary: .init(title: "Zkusit znovu", run: refresh)
            )
        case .loading, .none:
            ProgressView("Načítám konverzaci…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            EmptyStateView(
                nature: .calm,
                symbol: "bubble.left.and.bubble.right",
                // **Prázdná osa a zúžená osa jsou dvě různá prázdna.** Když je konverzace
                // opravdu prázdná, „výběr to schovává“ by tvrdilo něco, co není pravda —
                // schovávat není co.
                title: entries.isEmpty ? "Zatím se nic nedělo" : "Zúžení nic nenechalo",
                message: entries.isEmpty
                    ? "Komentáře, review a to, co se s větví stalo, se objeví tady."
                    : "Na ose něco je, ale tenhle výběr to schovává.",
                primary: entries.isEmpty ? nil : .init(title: "Ukázat vše") { filter = .all }
            )
        }
    }
}

/// Značka `Nové od tvé poslední návštěvy` (#183, navazuje na #173).
private struct SinceMarker: View {
    let at: Date?

    var body: some View {
        HStack(spacing: 8) {
            Text("Nové od tvé poslední návštěvy")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Palette.accent)
            Rectangle().fill(Palette.accent.opacity(0.35)).frame(height: 1)
            if let at {
                Text(at, format: .dateTime.hour().minute())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 10)
    }
}
