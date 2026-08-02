import SwiftUI

/// Nálezy z posledního review jako **spodní lišta** pod diffem.
///
/// Sbalená ukazuje jen to podstatné — návrh verdiktu a kolik nálezů je. Diff je to hlavní,
/// kvůli čemu je okno otevřené, takže seznam nálezů si o místo musí říct.
///
/// Skok do diffu tu **už je** (kliknutím na nález); co zbývá na #20, je řaditelná tabulka
/// místo tohohle surového seznamu.
struct FindingsView: View {
    let record: ReviewRecord
    @Binding var isExpanded: Bool
    /// Odskok do diffu na místo nálezu. Nálezy bez souboru (chybějící testy,
    /// architektonické poznámky) proklik nemají — není kam.
    let jump: (Finding) -> Void

    /// Kolik místa si seznam nálezů nejvýš vezme. Zbytek okna patří diffu.
    private static let maximumHeight: CGFloat = 280

    @State private var contentHeight = FindingsView.maximumHeight

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            summaryBar
            if isExpanded {
                Divider()
                expanded
            }
        }
        .background(.bar)
    }

    private var summaryBar: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Label(verdictText, systemImage: verdictSymbol)
                    .foregroundStyle(verdictColor)
                    .font(.headline)
                Text(verbatim: "· \(countText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if record.isStale {
                    Text("proti staršímu commitu")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let finishedAt = record.finishedAt {
                    Text(finishedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var expanded: some View {
        if record.findings.isEmpty {
            emptyExplanation
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            list
        }
    }

    /// Prázdný seznam neznamená sám o sobě čisté review — reviewer taky nemusel nálezy
    /// nahlásit vůbec nebo se je nepodařilo přečíst. Vysvětlení se proto bere ze stavu,
    /// který z toho počítá `Policy`, ne z vlastní věty tady: dvě formulace téhož by se
    /// dřív nebo později rozešly.
    @ViewBuilder private var emptyExplanation: some View {
        switch Policy.reviewState(for: record) {
        case .clean:
            Text("Review doběhlo a nic nenašlo.")
                .foregroundStyle(.secondary)
        case .failed(let detail), .checkoutFailed(let detail):
            Text(detail)
                .foregroundStyle(.orange)
        default:
            Text("Nálezy k tomuhle běhu nejsou.")
                .foregroundStyle(.secondary)
        }
    }

    /// Vysoký přesně jako obsah, nejvýš `maximumHeight`.
    ///
    /// `ScrollView` je jinak nenasytný a vzal by strop i pro tři nálezy — a to místo
    /// v okně chybí diffu. Proto se obsah měří; než se změří, drží se strop, takže
    /// nejhorší možný výsledek je dnešní chování.
    ///
    /// Seznam je `VStack`, ne `LazyVStack`: líný stack hlásí výšku jen za řádky, které už
    /// vytvořil, takže by se panel po scrollu zvětšoval. Nálezů jsou jednotky až desítky.
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Policy.sections(record.findings), id: \.category) { section in
                    sectionHeader(section.category)
                    ForEach(section.findings, id: \.self) { finding in
                        row(finding)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, Self.maximumHeight))
    }

    private func sectionHeader(_ category: String?) -> some View {
        Text(category ?? "bez kategorie")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ finding: Finding) -> some View {
        if finding.file == nil {
            content(of: finding)
        } else {
            Button { jump(finding) } label: {
                content(of: finding).contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func content(of finding: Finding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if Policy.isBlocking(finding) {
                    Text("blokuje")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: .capsule)
                        .foregroundStyle(.red)
                }
                Text(location(of: finding))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(finding.verdict?.rawValue ?? "?") · \(finding.reviewer)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(finding.summary).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Skládá se do `String`, ne do `Text` — tam by interpolace šla přes locale a z řádku
    /// 21663 by udělala „21 663“, což není množství.
    private func location(of finding: Finding) -> String {
        guard let file = finding.file else { return "bez místa" }
        guard let line = finding.line else { return file }
        return "\(file):\(line)"
    }

    private var countText: String {
        guard !record.findings.isEmpty else { return "žádné nálezy" }
        return Plural.czech(record.findings.count, one: "nález", few: "nálezy", many: "nálezů")
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
