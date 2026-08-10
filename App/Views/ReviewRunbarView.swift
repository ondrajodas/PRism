import SwiftUI

/// Pruh běhu v hlavičce PR (#218, `.runbar`): chipy reviewerů vlevo, za nimi proužek průběhu
/// a popisek `test-coverage · 2 z 3 hotovo · 1:12`.
///
/// Do #218 se z hlavičky o běžícím review nedalo poznat nic — tlačítko se přepnulo na `Zrušit`
/// a zbytek se odehrával v panelu `Průběh`, do kterého se při čtení diffu nechodí. Chipy a běh
/// jsou přitom jedna věc: chip říká, jak reviewer dopadl, proužek to, kolik jich ještě běží.
///
/// Když neběží nic, zbude z pruhu **jen řada chipů** — prázdný proužek by tvrdil, že se něco
/// děje.
struct ReviewRunbarView: View {
    let chips: [ReviewerChip]
    /// Reviewery, jejichž nálezy jsou schované (filtr, ne obsah).
    @Binding var muted: Set<String>
    /// Pustit znovu jen tohohle revieweera (#149). `nil` = odsud se nespouští.
    var rerun: ((String) -> Void)?
    /// Průběh běžícího review. `nil` = neběží nic.
    var progress: ReviewRunProgress?

    var body: some View {
        HStack(spacing: 12) {
            ReviewerChipsView(
                chips: chips,
                muted: $muted,
                rerun: rerun,
                isReviewing: progress != nil
            )
            // Kapsle si o místo řeknou **první**: mají ho tolik, kolik je v nich textu,
            // kdežto dráha se umí stáhnout. Bez priority si `GeometryReader` v dráze vezme
            // všechno, co `HStack` nabídne, a jména reviewerů se zalomí uvnitř kapslí.
            .layoutPriority(1)
            if let progress {
                run(progress)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func run(_ progress: ReviewRunProgress) -> some View {
        // Proužek jen tehdy, když se ví, z čeho počítat podíl. Během přípravy pracovní kopie
        // je prázdná dráha jediné, co by šlo nakreslit — a to vypadá jako zaseknutý běh,
        // přestože se to hýbe. Že se něco děje, drží tikající hodiny v popisku.
        if case .running = progress.stage {
            track(progress)
        } else {
            Spacer(minLength: 0)
        }
        // Hodiny musí tikat, takže se popisek překresluje po sekundě. `TimelineView` je jedno
        // místo, které se překresluje, ne časovač ve store — ten by budil celé okno.
        TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
            Text(verbatim: Self.label(progress, names: shortNames, at: context.date))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
        }
        // Popisek se taky nekrátí — je to jediné místo, kde se čas a poměr dozvím. Ubírat
        // se má **dráze**, protože ta nese totéž a jen obrázkem.
        .layoutPriority(1)
    }

    /// Dráha průběhu (`.runbar .track`): hotový díl přechodem z návrhu, běžící díl tiše za ním.
    ///
    /// Běžící díl je tam schválně — nad prvním reviewerem ze tří je hotovo nic, takže by
    /// dráha zůstala prázdná celé minuty a vypadala by jako rozbitá. Tiché krytí říká
    /// „pracuje se na tom“, sytá barva „hotovo“, a nesplývají.
    private func track(_ progress: ReviewRunProgress) -> some View {
        let done = progress.fraction ?? 0
        let inFlight = min(Self.share(of: progress.running.count, in: progress.stage), 1 - done)
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Palette.accent, Palette.accent2],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * done)
                Palette.accentWeak
                    .frame(width: proxy.size.width * inFlight)
                Spacer(minLength: 0)
            }
        }
        // Dráha se smí stáhnout, ale ne na nulu: dvoubodový proužek už nic neukazuje a vypadá
        // jako smítko. Pod tuhle šířku se ubírá jménům v kapslích, která se zkracují.
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 4, maxHeight: 4)
        .background(Palette.raised)
        .clipShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Průběh review")
        .accessibilityValue(Self.label(progress, names: shortNames, at: .now))
    }

    /// Zkrácená jména do popisku. Tatáž mapa jako u chipů vedle — dvě různá zkrácení téhož
    /// skillu v jednom řádku by vypadala jako dva reviewery.
    private var shortNames: [String: String] {
        Policy.shortReviewerNames(of: chips.map(\.skill))
    }

    /// Podíl, který v dráze zabírá `count` běžících reviewerů.
    private nonisolated static func share(of count: Int, in stage: ReviewRunProgress.Stage) -> Double {
        guard case .running(_, let total) = stage, total > 0 else { return 0 }
        return min(Double(count) / Double(total), 1)
    }

    /// Popisek pruhu: kdo běží, kolik je hotovo a jak dlouho to trvá.
    ///
    /// `at` je „teď“ zvenčí, aby se text dal vyčerpat testem — hodiny počítané uvnitř by
    /// nešly zafixovat.
    nonisolated static func label(_ progress: ReviewRunProgress, names: [String: String], at now: Date) -> String {
        var parts: [String] = []
        switch progress.stage {
        case .preparing:
            parts.append("připravuji pracovní kopii")
        case .running(let finished, let total):
            // Prázdný výčet je reálný stav: poslední reviewer doběhl a běh se ještě uklízí.
            // Věta o tom, kolik je hotovo, dává smysl i bez jmen.
            let running = progress.running.map { names[$0] ?? $0 }
            if !running.isEmpty { parts.append(running.joined(separator: ", ")) }
            parts.append("\(finished) z \(total) hotovo")
        }
        parts.append(RunUsageText.elapsed(.seconds(now.timeIntervalSince(progress.startedAt))))
        return parts.joined(separator: " · ")
    }
}

#Preview {
    @Previewable @State var muted: Set<String> = []

    return VStack(alignment: .leading, spacing: 14) {
        ReviewRunbarView(
            chips: [
                ReviewerChip(skill: "php-review", state: .findings(2)),
                ReviewerChip(skill: "security-review", state: .findings(1)),
                ReviewerChip(skill: "docs", state: .clean)
            ],
            muted: $muted
        )
        ReviewRunbarView(
            chips: [
                ReviewerChip(skill: "php-review", state: .findings(2)),
                ReviewerChip(skill: "security-review", state: .clean),
                ReviewerChip(skill: "test-coverage", state: .running)
            ],
            muted: $muted,
            progress: ReviewRunProgress(
                stage: .running(finished: 2, total: 3),
                running: ["test-coverage"],
                startedAt: .now.addingTimeInterval(-72)
            )
        )
    }
    .padding()
    .frame(width: 760)
}
