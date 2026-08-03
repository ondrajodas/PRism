import SwiftUI

/// Návrh verdiktu — **návrh, ne akce**.
///
/// Na verdiktu nevisí žádné tlačítko a od #66 to platí o důvod víc: verdikt, který se
/// odešle, se vybírá v tabu `Moje review` a **nepředvyplňuje se** odsud. Odhad aplikace se
/// nemá dát splést s mým rozhodnutím, takže je tohle i vizuálně doporučení, ne příkaz.
struct VerdictView: View {
    let record: ReviewRecord
    let blockingCategories: Set<String>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(color)
                if let note {
                    Text(verbatim: note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 6))
        .help("Návrh podle nálezů. Co se opravdu odešle, vybíráš v tabu Moje review.")
    }

    private var verdict: ReviewVerdict? {
        Policy.suggestedVerdict(for: record, categories: blockingCategories)
    }

    private var text: String {
        switch verdict {
        case .approve: "Návrh: approve"
        case .requestChanges: "Návrh: request changes"
        case nil: "Návrh: není z čeho soudit"
        }
    }

    /// Zastaralý záznam návrh nedá vůbec — a je potřeba říct proč, jinak to vypadá jako
    /// chyba aplikace.
    private var note: String? {
        if record.isStale { return "nálezy jsou proti staršímu commitu" }
        if verdict == nil { return "žádný běh nedoběhl tak, aby se z něj dalo soudit" }
        return nil
    }

    private var symbol: String {
        switch verdict {
        case .approve: "checkmark.seal"
        case .requestChanges: "exclamationmark.triangle"
        case nil: "questionmark.circle"
        }
    }

    private var color: Color {
        switch verdict {
        case .approve: .green
        case .requestChanges: .orange
        case nil: .secondary
        }
    }
}
