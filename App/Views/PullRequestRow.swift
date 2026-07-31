import SwiftUI

/// Jeden řádek seznamu PR.
///
/// Repo je nad titulkem schválně: seznam míchá repozitáře, takže „odkud to je“ je první
/// otázka, kterou má řádek zodpovědět.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    let reviewState: ReviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(pullRequest.repo.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // `verbatim`, jinak `Text` interpoluje číslo přes locale a z PR #21663
                // udělá „#21 663“ — číslo PR není množství.
                Text(verbatim: "#\(pullRequest.number)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                if pullRequest.state == .draft {
                    Text("draft")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                Spacer(minLength: 8)
                ReviewStateBadge(state: reviewState)
            }

            Text(pullRequest.title)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(pullRequest.author)
                Text("·")
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
            reviewState: .notStarted
        )
    }
}
