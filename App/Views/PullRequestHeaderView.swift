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
            separator
            // **Bez čísla** (#218). To se od #218 sází vedle titulku, velké a tlumené, jak ho
            // má návrh; tady by byla druhá kopie téhož — a `owner/repo#4` je tvar, ve kterém
            // číslo nikdo nehledá.
            Text(verbatim: pullRequest.repo.description)
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
            // Tečka jde **před** každou položkou, ne za ní: souhrn checků se u PR bez CI
            // nekreslí, a tečka za ním by pak visela ve vzduchu.
            checksChip
            separator
            Link("otevřít na GitHubu", destination: pullRequest.url)
        }
        .font(.callout)
    }

    /// Tečka mezi souřadnicemi, jak ji má návrh (`.pr-meta`). Sama o sobě neříká nic, takže
    /// ji odečítání nemá číst.
    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(Palette.ink3)
            .accessibilityHidden(true)
    }

    /// Stav PR jako **plná kapsle** (#218, `.state-chip`): puntík, slovo a barva na podkladu,
    /// ne tlumený odznak.
    ///
    /// Do #218 to byl text v barvě stavu na patnáctiprocentní výplni — tedy nejtišší prvek
    /// pruhu, přestože je to údaj, kvůli kterému se na hlavičku dívám první. Návrh ho má jako
    /// jediné plné pole v celém pruhu.
    private var state: some View {
        HStack(spacing: 5) {
            Circle()
                .frame(width: 6, height: 6)
            Text(verbatim: pullRequest.state.czechLabel)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        // Text v barvě **podkladu okna** (`--panel`), ne bíle: v tmavém režimu je bílá na
        // zelené oslnivá a návrh na ni v obou režimech sází barvu plochy.
        .foregroundStyle(Palette.surface)
        .background(stateTint, in: .capsule)
    }

    /// `autor chce sloučit větev → base`. Větve jsou v mono, protože je to identifikátor,
    /// který se čte po znacích a občas kopíruje.
    private func merge(_ detail: PullRequest) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: pullRequest.author)
                .fontWeight(.medium)
            Text("chce sloučit")
            branch(detail.headRef)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(Palette.ink3)
            branch(detail.baseRef)
        }
        .foregroundStyle(Palette.ink2)
    }

    private func branch(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.raised, in: .rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.lineSoft) }
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    /// Barva kapsle. Všechny čtyři stavy jdou z palety návrhu — systémové `.green` a `.red`
    /// by v plné kapsli s textem v barvě plochy vyšly příliš světle, a `.purple` s `.secondary`
    /// by do neutrálů posunutých do modrofialové nesedly vůbec.
    private var stateTint: Color {
        switch pullRequest.state {
        case .open: Palette.ok
        case .draft: Palette.ink3
        // Fialová z návrhu je jen jedna a je to akcent; mergnutý PR je jediné místo, kde ji
        // nese stav, a plete se s ní jen `Spustit review` o řádek výš.
        case .merged: Palette.accent
        case .closed: Palette.crit
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
            separator
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

    /// Z palety návrhu, ne systémová: souhrn stojí v jedné řadě s kapslí stavu PR, a dvě
    /// různé zelené vedle sebe vypadají jako dva různé významy.
    private func color(of outcome: PullRequestCheck.Outcome) -> Color {
        switch outcome {
        case .passed: Palette.ok
        case .failed, .cancelled: Palette.crit
        case .running: Palette.accent
        case .skipped: Palette.ink3
        }
    }
}
