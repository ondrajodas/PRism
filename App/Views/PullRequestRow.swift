import SwiftUI

/// Jeden řádek seznamu PR (#172).
///
/// **Titulek je nahoře, souřadnice pod ním.** Do #172 to bylo obráceně — repo první, titulek
/// druhý — a seznam se tím čte místo skenuje: „odkud to je“ je otázka, na kterou dojde řada
/// až po „co to je“.
///
/// Stav review nese **hrana řádku**, ne jen odznak. Barva na kraji se přečte periferně, takže
/// se fronta dá přejet očima; odznak vedle ní říká totéž slovy, protože samotná barva nestačí.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    let reviewState: ReviewState
    /// Leží na tomhle PR rozdělané review? Ukazuje se ikonou, ne slovem: „draft“ je vedle
    /// v řádku obsazený **rozpracovaným pull requestem**, což je něco jiného.
    var hasDraft = false
    /// Odvozená čísla k výsledku — kolik blokuje a jak se nálezy rozdělily mezi reviewery.
    /// Prázdné u PR, na kterém nic neběželo.
    var row: QueueRow = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headline
            meta
        }
        .padding(.vertical, 4)
        .padding(.leading, 9)
        // Proužek přes celou výšku řádku. `overlay`, ne sloupec v `HStacku`: jinak by se
        // musela výška dopočítávat ručně a u dvouřádkového titulku by proužek nedosáhl.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(ReviewStateAppearance.color(of: reviewState, blocking: row.blocking))
                .frame(width: 3)
        }
    }

    private var headline: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.pull")
                .font(.caption)
                .foregroundStyle(stateTint)
                .help(pullRequest.state.czechLabel)
                .accessibilityLabel(pullRequest.state.czechLabel)
            Text(pullRequest.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !row.spectrum.isEmpty {
                SpectrumBar(shares: row.spectrum)
            }
            ReviewStateBadge(state: reviewState, blocking: row.blocking)
        }
    }

    private var meta: some View {
        HStack(spacing: 4) {
            // `verbatim`, jinak `Text` interpoluje číslo přes locale a z PR #21663 udělá
            // „#21 663“ — číslo PR není množství.
            Text(verbatim: "\(pullRequest.repo) #\(pullRequest.number)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            // Draft je **slovo**, ne jen odstín ikony. Tvar ikony je u otevřeného
            // a rozpracovaného PR tentýž, takže by rozdíl nesla pouze barva — a ta sama
            // nestačí. V prvním řádku pro něj místo není, tady zbývá.
            if pullRequest.state == .draft {
                Text(verbatim: "·")
                Text("draft")
            }
            Text(verbatim: "·")
            Text(verbatim: pullRequest.author)
            Text(verbatim: "·")
            Text(pullRequest.updatedAt, format: .relative(presentation: .named))
            Spacer(minLength: 8)
            if hasDraft {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.tint)
                    .help("Leží tu rozdělané review, které jsi ještě neodeslal")
                    .accessibilityLabel("Rozdělané review")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    /// Barva ikony pull requestu — stav **PR**, ne review. Ty dva se nesmí slít: PR může být
    /// otevřený a review selhané zároveň.
    private var stateTint: Color {
        switch pullRequest.state {
        case .open: .green
        case .draft: .secondary
        case .merged: .purple
        case .closed: .red
        }
    }
}

#Preview {
    List {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85),
                title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/85")!,
                updatedAt: Date().addingTimeInterval(-3600),
                state: .open
            ),
            reviewState: .completed(findings: 3),
            row: QueueRow(
                blocking: 1,
                spectrum: [
                    ReviewerShare(reviewer: "php-review", outcome: .blocking, weight: 2),
                    ReviewerShare(reviewer: "security-review", outcome: .findings, weight: 1),
                    ReviewerShare(reviewer: "docs", outcome: .clean, weight: 1),
                ]
            )
        )
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 171),
                title: "feat: události na časové ose konverzace",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/171")!,
                updatedAt: Date().addingTimeInterval(-300),
                state: .draft
            ),
            reviewState: .notStarted,
            hasDraft: true
        )
    }
    .frame(width: 420)
}
