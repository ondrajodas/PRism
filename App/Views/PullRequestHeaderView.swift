import SwiftUI

/// Souřadnice pull requestu pod titulkem (#174).
///
/// Odpovídá na dvě otázky, které se do #174 v okně zodpovědět nedaly a chodilo se kvůli nim
/// do prohlížeče: **kam se to merguje** a **proti čemu platí nálezy, které jsou na obrazovce**.
///
/// Druhá z nich je trivia ve chvíli, kdy se obě sha rovnají — a nejdůležitější údaj na obrazovce
/// ve chvíli, kdy ne.
struct PullRequestHeaderView: View {
    let pullRequest: PullRequestSummary
    /// Načtený detail. `nil` = ještě nedorazil, takže větve ani hlavu neukazujeme; hádat je
    /// horší než je chvíli nemít.
    var detail: PullRequest?
    /// Sha, proti které platí uložené nálezy. `nil` = žádné nejsou.
    var findingsHead: String?

    var body: some View {
        HStack(spacing: 9) {
            state
            if let detail, !detail.headRef.isEmpty, !detail.baseRef.isEmpty {
                merge(detail)
            }
            Text(verbatim: pullRequest.repo.description)
                .foregroundStyle(.secondary)
            Link("otevřít na GitHubu", destination: pullRequest.url)
        }
        .font(.callout)
    }

    /// Stav PR jako chip. Slovo, ne jen barevná ikona v seznamu — v detailu je místa dost
    /// a `draft` se od `open` musí poznat, aniž by se muselo najíždět myší.
    private var state: some View {
        Text(verbatim: pullRequest.state.czechLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(stateTint.opacity(0.16), in: .capsule)
            .foregroundStyle(stateTint)
    }

    /// `autor chce sloučit větev → base`. Větve jsou v mono, protože je to identifikátor,
    /// který se čte po znacích a občas kopíruje.
    private func merge(_ detail: PullRequest) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: pullRequest.author)
                .fontWeight(.medium)
            Text("chce sloučit")
                .foregroundStyle(.secondary)
            branch(detail.headRef)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            branch(detail.baseRef)
        }
    }

    private func branch(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var stateTint: Color {
        switch pullRequest.state {
        case .open: .green
        case .draft: .secondary
        case .merged: .purple
        case .closed: .red
        }
    }
}

/// Hlava PR a sha, proti které platí nálezy (#174).
///
/// Kreslí se **jen když se ty dvě rozejdou**. Dokud se rovnají, je to trivia, která by
/// v hlavičce zabírala řádek; jakmile se rozejdou, je to ta nejdůležitější věc na obrazovce,
/// protože všechno pod ní mluví o kódu, který na větvi už není.
struct StaleHeadView: View {
    let head: String
    let findingsHead: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text("Nálezy jsou proti")
            sha(findingsHead)
            Text(", hlava PR je")
            sha(head)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Co je na obrazovce, platí ke staršímu commitu. Nové review je proti aktuální hlavě.")
    }

    private func sha(_ value: String) -> some View {
        Text(verbatim: String(value.prefix(7)))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
}

#Preview {
    let id = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)
    let summary = PullRequestSummary(
        id: id,
        title: "chore: modernize dependencies",
        author: "odinuv",
        url: URL(string: "https://github.com/keboola/vault/pull/85")!,
        updatedAt: Date(),
        state: .open
    )

    return VStack(alignment: .leading, spacing: 10) {
        PullRequestHeaderView(
            pullRequest: summary,
            detail: PullRequest(
                id: id,
                title: summary.title,
                author: "odinuv",
                headSha: "9c1de0212ab",
                baseSha: "4f2ac9188cd",
                headRef: "chore/deps-2026",
                baseRef: "main",
                url: summary.url,
                updatedAt: Date(),
                state: .open
            )
        )
        StaleHeadView(head: "9c1de0212ab", findingsHead: "4f2ac9188cd")
    }
    .padding()
    .frame(width: 700)
}
