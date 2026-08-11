import SwiftUI

/// Souhrn kontrol v tabu `Přehled` (#215) — **jeden řádek s poměrem, ne seznam**.
///
/// `Přehled` odpovídá na „jak to teď stojí“, takže „je to zelené“ tu zůstat musí; seznam checků
/// a detail spadlého (#214) se stěhoval do tabu `Kontroly`, protože roste. Zbývá tedy poměr
/// v hlavičce a **nejhorší check** pod ní jako ukazatel, kam jít dál.
///
/// **Zelené CI dostane jen hlavičku.** Řádek pod ní je pro to, co se má řešit — u zeleného PR by
/// jmenoval náhodný job z dvanácti a tvrdil by, že je na něm něco zajímavého.
struct ChecksSummaryView: View {
    let checks: [PullRequestCheck]
    /// Přepne do tabu `Kontroly`. `nil` = tab není kam otevřít, takže se odkaz nekreslí —
    /// nekliká se na text, který nic neudělá.
    var openChecks: (() -> Void)?

    var body: some View {
        // Souhrn se počítá **jednou** a použije se na poměr i na výběr nejhoršího checku:
        // dvě volání by při každém překreslení `Přehledu` počítala totéž dvakrát.
        let summary = Policy.summary(of: checks)
        return VStack(spacing: 0) {
            header(summary)
            if let worst = worst(of: summary) {
                Rectangle().fill(Palette.lineSoft).frame(height: 1)
                row(worst)
            }
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
    }

    /// Hlavička s poměrem (`.checks > header`). Spadlá část je **červená** — v `Přehledu` nese
    /// zvýraznění barva, protože pořadí je stejné jako v tabu (viz `ChecksText.parts`).
    private func header(_ summary: ChecksSummary) -> some View {
        HStack(spacing: 8) {
            Text("Kontroly na GitHubu")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            summaryText(summary)
                .font(.system(size: 11.5))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Poměr složený po částech, ať se spadlá dá obarvit. Skládá se z `ChecksText`, takže
    /// se s tabem nemá čím rozejít.
    private func summaryText(_ summary: ChecksSummary) -> some View {
        let parts = ChecksText.parts(of: summary)
        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(verbatim: " · ").foregroundStyle(Palette.ink2)
                }
                Text(verbatim: part.text)
                    .foregroundStyle(part.isFailure ? Palette.crit : Palette.ink2)
                    .fontWeight(part.isFailure ? .semibold : .regular)
            }
        }
    }

    /// Řádek nejhoršího checku a v něm cesta dál: jméno jobu, odkaz do tabu `Kontroly`
    /// a odkaz na GitHub.
    private func row(_ check: PullRequestCheck) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ChecksText.symbol(of: check.outcome))
                .font(.system(size: 11))
                .foregroundStyle(ChecksText.color(of: check.outcome))
                .frame(width: 13)
            // Jméno a věta o tabu jsou jeden odstavec, jak je má návrh — ne dva sloupce, mezi
            // kterými by se v úzkém okně roztáhla mezera.
            HStack(spacing: 4) {
                Text(verbatim: check.name)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                if let openChecks {
                    Text(verbatim: "— a co dál, je v tabu")
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                    Button("Kontroly", action: openChecks)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .help("Přepnout na tab Kontroly")
                }
            }
            .font(.system(size: 12))
            Spacer(minLength: 8)
            if let link = check.link {
                Link(destination: link) {
                    HStack(spacing: 3) {
                        Text("otevřít")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
                .help("Otevřít check na GitHubu")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Nejhorší check, tedy ten, na kterém záleží. `nil` u zeleného i přeskočeného CI —
    /// pak zbývá jen hlavička.
    ///
    /// Řadí to `Policy.sorted` (spadlé nahoru), ne vlastní hledání: pořadí v tabu a ten jeden
    /// řádek v `Přehledu` musí ukazovat na tentýž check.
    private func worst(of summary: ChecksSummary) -> PullRequestCheck? {
        switch summary.worst {
        case .failed, .cancelled, .running: Policy.sorted(checks).first
        case .passed, .skipped, nil: nil
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ChecksSummaryView(
            checks: [
                PullRequestCheck(
                    name: "phpstan (level 8)",
                    outcome: .failed,
                    link: URL(string: "https://github.com/cli/cli/actions/runs/1/job/2"),
                    startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: Date(timeIntervalSince1970: 134)
                ),
                PullRequestCheck(
                    name: "phpunit / 8.4",
                    outcome: .running,
                    link: nil,
                    startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: nil
                ),
                PullRequestCheck(
                    name: "phpcs",
                    outcome: .passed,
                    link: nil,
                    startedAt: nil,
                    completedAt: nil
                ),
            ],
            openChecks: {}
        )
        ChecksSummaryView(
            checks: [
                PullRequestCheck(
                    name: "phpcs",
                    outcome: .passed,
                    link: nil,
                    startedAt: nil,
                    completedAt: nil
                ),
            ],
            openChecks: {}
        )
    }
    .padding(16)
    .frame(width: 720)
}
