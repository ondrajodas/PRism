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

    @State private var filter: ConversationFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            timeline
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        let nodes = Policy.conversation(of: entries, filter: filter)
        if nodes.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        // Značka se kreslí **před** první novou položkou, ne za poslední starou:
                        // říká „odsud dolů je nové“, což je směr, ve kterém se osa čte.
                        if isFirstNew(node, at: index, in: nodes) {
                            SinceMarker(at: lastVisit)
                        }
                        ConversationNodeView(
                            node: node,
                            viewer: viewer,
                            threadActions: threadActions,
                            isStale: isStale,
                            rerun: rerun
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    /// Je tohle první uzel, který přibyl od poslední návštěvy? Bez `lastVisit` nikdy —
    /// „nové“ se nedá tvrdit, když není proti čemu.
    private func isFirstNew(_ node: ConversationNode, at index: Int, in nodes: [ConversationNode]) -> Bool {
        guard let lastVisit, let date = node.date, date > lastVisit else { return false }
        // První uzel značku dostat **smí**: když je nové všechno, patří značka úplně nahoru.
        // Nález Copilota — původní `index > 0` ji v tom případě zahodil.
        guard index > 0 else { return true }
        // Jinak musí být předchozí uzel starý, jinak by se značka kreslila u každé nové položky.
        return nodes[index - 1].date.map { $0 <= lastVisit } ?? false
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
