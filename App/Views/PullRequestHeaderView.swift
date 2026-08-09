import SwiftUI

/// Souřadnice pull requestu pod titulkem (#174).
///
/// Odpovídá na otázku, která se do #174 v okně zodpovědět nedala a chodilo se kvůli ní do
/// prohlížeče: **kam se to merguje**. Na tu druhou — proti čemu platí nálezy na obrazovce —
/// odpovídá `StaleHeadView` níž, protože se ukazuje jen občas.
struct PullRequestHeaderView: View {
    let pullRequest: PullRequestSummary
    /// Načtený detail. `nil` = ještě nedorazil, takže větve ani hlavu neukazujeme; hádat je
    /// horší než je chvíli nemít.
    var detail: PullRequest?
    /// Checky (#209). Souhrn patří **do hlavičky**, ne jen do tabu `Přehled`: „dá se to
    /// mergnout“ je otázka, kterou má okno zodpovědět bez přepínání, a při čtení diffu se
    /// do `Přehledu` nechodí.
    var checks: [PullRequestCheck] = []

    var body: some View {
        HStack(spacing: 9) {
            state
            if let detail, !detail.headRef.isEmpty, !detail.baseRef.isEmpty {
                merge(detail)
            }
            // Číslo zůstává u repa: v detailu jinde není a `owner/repo#číslo` je tvar, kterým
            // se PR v tomhle repu píše všude jinde (klíč nálezů, název souboru, commit).
            // `verbatim`, jinak locale udělá z #21663 „#21 663“.
            Text(verbatim: "\(pullRequest.repo)#\(pullRequest.number)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            checksChip
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


extension PullRequestHeaderView {
    /// Souhrn checků jedním chipem. **Barva podle nejhoršího** — dvanáct zelených a jeden
    /// červený je červený stav. Bez checků se nekreslí nic: PR bez CI je běžná věc a prázdný
    /// chip by tvrdil, že se něco nepovedlo.
    @ViewBuilder fileprivate var checksChip: some View {
        let summary = Policy.summary(of: checks)
        if let worst = summary.worst {
            HStack(spacing: 4) {
                Image(systemName: symbol(of: worst))
                    .font(.system(size: 10))
                Text(verbatim: text(of: summary))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(color(of: worst))
            .help("Kontroly na GitHubu — podrobnosti jsou v Přehledu")
        }
    }

    /// `1 selhala` u poruchy, jinak celý poměr: když je něco špatně, je to jediné, co má
    /// v úzké hlavičce cenu — zbytek se dočte v `Přehledu`.
    private func text(of summary: ChecksSummary) -> String {
        if summary.failed > 0 {
            return Plural.czech(summary.failed, one: "selhala", few: "selhaly", many: "selhalo")
        }
        if summary.running > 0 { return "\(summary.running) běží" }
        if summary.passed > 0 {
            return Plural.czech(summary.passed, one: "prošla", few: "prošly", many: "prošlo")
        }
        return "\(summary.skipped) přeskočeno"
    }

    private func symbol(of outcome: PullRequestCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark.circle"
        case .failed, .cancelled: "xmark.circle"
        case .running: "circle.dashed"
        case .skipped: "minus.circle"
        }
    }

    private func color(of outcome: PullRequestCheck.Outcome) -> Color {
        switch outcome {
        case .passed: .green
        case .failed, .cancelled: .red
        case .running: Palette.accent
        case .skipped: Palette.ink3
        }
    }
}
