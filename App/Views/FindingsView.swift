import SwiftUI

/// Nálezy z posledního review — zatím surově.
///
/// Bubliny u diffu jsou M4; tohle je seznam, ze kterého se dá poznat, jestli mašinerie
/// dělá to, co má. Řazení i skupiny počítá `Policy`, tenhle typ jen kreslí.
struct FindingsView: View {
    let record: ReviewRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            verdict
            if record.findings.isEmpty {
                emptyExplanation
            } else {
                list
            }
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

    private var verdict: some View {
        HStack(spacing: 8) {
            Label(verdictText, systemImage: verdictSymbol)
                .foregroundStyle(verdictColor)
                .font(.headline)
            if record.isStale {
                Text("proti staršímu commitu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let finishedAt = record.finishedAt {
                Text(finishedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(Policy.sections(record.findings), id: \.category) { section in
                Section(section.category ?? "bez kategorie") {
                    ForEach(section.findings, id: \.self) { finding in
                        row(finding)
                    }
                }
            }
        }
        .listStyle(.inset)
        // Bez toho si `List` uvnitř `VStack`u vezme jen svoji ideální výšku a u delšího
        // seznamu se nálezy schovají místo aby šly scrollovat.
        .frame(maxHeight: .infinity)
    }

    private func row(_ finding: Finding) -> some View {
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
        .padding(.vertical, 2)
    }

    /// Skládá se do `String`, ne do `Text` — tam by interpolace šla přes locale a z řádku
    /// 21663 by udělala „21 663“, což není množství.
    private func location(of finding: Finding) -> String {
        guard let file = finding.file else { return "bez místa" }
        guard let line = finding.line else { return file }
        return "\(file):\(line)"
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
