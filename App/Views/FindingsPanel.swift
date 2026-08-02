import SwiftUI

/// Spodní panel pod diffem: přehled nálezů a (zatím prázdný) průběh běhu.
///
/// Je to **jediné místo pro nálezy bez `file:line`** — chybějící testy, poznámky
/// k architektuře. Právě kvůli nim nestačí bubliny u kódu.
///
/// Sbalený ukazuje jen to podstatné: návrh verdiktu, počet nálezů a stáří. Diff je to
/// hlavní, kvůli čemu je okno otevřené, takže panel si o místo musí říct.
struct FindingsPanel: View {
    let record: ReviewRecord
    @Binding var isExpanded: Bool
    /// Odskok do diffu na místo nálezu.
    let jump: (Finding) -> Void

    private enum Tab: Hashable {
        case findings
        case progress
    }

    /// Výška si drží uživatel taháním a přežívá restart — kolik místa chce dát nálezům,
    /// ví jen on.
    @AppStorage("findingsPanelHeight") private var height = 220.0
    @State private var tab: Tab = .findings
    @State private var sortOrder: [KeyPathComparator<FindingRow>] = []
    @State private var selection: FindingRow.ID?
    /// Výška na začátku tažení. Bez ní se posun načítá z každé události znovu a panel
    /// utíká pryč.
    @State private var heightAtDragStart: Double?

    private static let minimumHeight = 120.0
    private static let maximumHeight = 600.0

    /// Uložená výška se ořezává **při použití**, ne jen při tažení: v `UserDefaults` může
    /// být cokoli (ruční editace, jiný rozsah ze starší verze) a `frame(height:)` se
    /// zápornou hodnotou rozhodí celý panel.
    private var clampedHeight: Double { clamp(height) }

    private func clamp(_ value: Double) -> Double {
        min(max(Self.minimumHeight, value), Self.maximumHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            bar
            if isExpanded {
                Divider()
                content.frame(height: clampedHeight)
            }
        }
        .background(.bar)
    }

    // MARK: - Lišta

    private var bar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            tabs
            Spacer()
            verdict
            if let finishedAt = record.finishedAt {
                Text(finishedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var tabs: some View {
        Picker("", selection: $tab) {
            Text(verbatim: countText).tag(Tab.findings)
            Text("Průběh").tag(Tab.progress)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        // Rozbalený panel bez obsahu vypadá jako chyba — přepnutí tabu ho proto otevře.
        .onChange(of: tab) { _, _ in isExpanded = true }
    }

    private var verdict: some View {
        HStack(spacing: 6) {
            Label(verdictText, systemImage: verdictSymbol)
                .foregroundStyle(verdictColor)
                .font(.callout.weight(.medium))
            if record.isStale {
                Text("proti staršímu commitu")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Tažením za horní hranu se panelu mění výška. Pruh je schválně vyšší než čára, aby
    /// se do něj dalo trefit.
    private var resizeHandle: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(height: 8)
                    .contentShape(.rect)
                    // `pointerStyle` místo ručního `NSCursor.push()`/`pop()`: když view
                    // zmizí uprostřed hoveru, druhá půlka páru se nikdy nezavolá a
                    // v aplikaci zůstane cizí kurzor.
                    .pointerStyle(.frameResize(position: .top))
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let start = heightAtDragStart ?? clampedHeight
                                heightAtDragStart = start
                                isExpanded = true
                                height = clamp(start - drag.translation.height)
                            }
                            .onEnded { _ in heightAtDragStart = nil }
                    )
            }
    }

    // MARK: - Obsah

    @ViewBuilder private var content: some View {
        switch tab {
        case .findings: findings
        case .progress: progress
        }
    }

    @ViewBuilder private var findings: some View {
        if record.findings.isEmpty {
            emptyExplanation
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            table
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Kategorie", value: \.category) { row in
                HStack(spacing: 4) {
                    if row.isBlocking {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption2)
                            .help("Blokující nález")
                    }
                    Text(verbatim: row.category)
                }
            }
            .width(min: 110, ideal: 140)

            TableColumn("Reviewer", value: \.reviewer) { row in
                Text(verbatim: row.reviewer)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Místo", value: \.location) { row in
                Text(verbatim: row.location)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(row.finding.file == nil ? .secondary : .primary)
            }
            .width(min: 140, ideal: 260)

            TableColumn("Nález", value: \.summary) { row in
                Text(verbatim: row.summary).lineLimit(2)
            }
        }
        // Výběr se hned zahazuje, aby se na totéž místo dalo skočit i podruhé — jinak by
        // druhé kliknutí na už vybraný řádek neudělalo nic.
        .onChange(of: selection) { _, chosen in
            guard let chosen, let row = rows.first(where: { $0.id == chosen }) else { return }
            jump(row.finding)
            selection = nil
        }
    }

    private var progress: some View {
        ContentUnavailableView(
            "Průběh přijde s dalším krokem",
            systemImage: "waveform",
            description: Text("Tady poběží živý výpis toho, co reviewer právě dělá.")
        )
    }

    /// Prázdná tabulka neznamená sama o sobě čisté review — reviewer taky nemusel nálezy
    /// nahlásit vůbec nebo se je nepodařilo přečíst. Vysvětlení se bere ze stavu, který
    /// z toho počítá `Policy`, ne z vlastní věty tady.
    @ViewBuilder private var emptyExplanation: some View {
        switch Policy.reviewState(for: record) {
        case .clean:
            Text("Review doběhlo a nic nenašlo.").foregroundStyle(.secondary)
        case .failed(let detail), .checkoutFailed(let detail):
            Text(detail).foregroundStyle(.orange)
        default:
            Text("Nálezy k tomuhle běhu nejsou.").foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    /// Bez řazení podle sloupce platí pořadí z `Policy` — tabulka nemá vlastní představu
    /// o tom, co patří nahoru.
    private var rows: [FindingRow] {
        let base = FindingRow.rows(of: record.findings)
        return sortOrder.isEmpty ? base : base.sorted(using: sortOrder)
    }

    private var countText: String {
        record.findings.isEmpty
            ? "Nálezy"
            : "Nálezy · \(record.findings.count)"
    }

    private var verdictText: String {
        switch Policy.suggestedVerdict(for: record) {
        case .approve: "Návrh: approve"
        case .requestChanges: "Návrh: request changes"
        case nil: "Návrh: není z čeho soudit"
        }
    }

    private var verdictSymbol: String {
        switch Policy.suggestedVerdict(for: record) {
        case .approve: "checkmark.seal"
        case .requestChanges: "exclamationmark.triangle"
        case nil: "questionmark.circle"
        }
    }

    private var verdictColor: Color {
        switch Policy.suggestedVerdict(for: record) {
        case .approve: .green
        case .requestChanges: .orange
        case nil: .secondary
        }
    }
}
