import AppKit
import SwiftUI

/// Tabulka `Jak si reviewery vedou` v Nastavení (#514) — plný výpis toho, co blok na domově
/// ukazuje jen po vrch.
///
/// **Čtení, ne nastavení**, a je to jediná taková sekce na téhle stránce. Leží tu proto, že
/// odpovídá na otázku, kterou si člověk položí **nad sadou skillů o pár řádků výš** („který
/// z nich mi vlastně k něčemu je“) — vlastní stránka by ji schovala zrovna od toho, s čím se čte.
///
/// **Rozhodování je v `Policy`** (`reviewerShare(of:)`, `skillFolder(of:in:)`); tady se kreslí.
struct ReviewerTallyTable: View {
    let tallies: [ReviewerTally]
    /// Cesty ke složkám skillů z konfigurace. Co v mapě není, tlačítko nedostane.
    let skillFolders: [String: String]

    var body: some View {
        if tallies.isEmpty {
            // **Věta, ne prázdná plocha.** Prázdno se nad tabulkou čte jako nenačtená data,
            // přitom je to běžný stav: po čistém startu a po třiceti dnech bez review tu opravdu
            // nic není.
            Text(verbatim: "Za posledních 30 dní neleží na disku žádné nálezy, takže není co sečíst.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(tallies) { tally in
                row(tally)
            }
        }
    }

    private func row(_ tally: ReviewerTally) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(verbatim: tally.repo.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                bar(tally)
                share(tally)
                // **Tlačítko je až za podílem**, tedy za tím, kvůli čemu se na řádek kouká:
                // jediná akce v tabulce má stát na konci věty, ne před ní.
                skillButton(tally)
            }
        } label: {
            Text(verbatim: tally.reviewer)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Pruh šířky 120 z návrhu (sekce 61) — širší než v bloku na domově, protože tady je místo
    /// a řádků je víc, takže se porovnávají mezi sebou.
    private func bar(_ tally: ReviewerTally) -> some View {
        let segments = ReviewerBarSegment.all(of: tally)
        return ProportionalColumns(ratios: segments.map(\.share), spacing: 1) {
            ForEach(segments) { segment in
                Rectangle().fill(segment.color)
            }
        }
        .frame(width: 120, height: 8)
        .background(Palette.raised)
        .clipShape(.rect(cornerRadius: 4))
        .help(breakdown(of: tally))
    }

    /// Procento toho, čeho je nejvíc. Barvu nese **ten důvod**, ne „je to zlé“ — na rozdíl od
    /// věty v bloku na domově, kde jde o to, že se něco ozývá. Obojí je z návrhu doslova.
    @ViewBuilder private func share(_ tally: ReviewerTally) -> some View {
        if let share = Policy.reviewerShare(of: tally) {
            Text(verbatim: share.text)
                .font(.system(size: 11.5))
                .foregroundStyle(color(of: share.aim))
                .lineLimit(1)
        }
    }

    private func color(of aim: ReviewerSignal.Aim) -> Color {
        switch aim {
        case .skill: Palette.crit
        case .repoRules: Palette.stale
        case .none: Palette.ink2
        }
    }

    /// `Otevřít skill ↗`. **Když aplikace složku nezná, nekreslí se vůbec** — ne zašedle:
    /// zašedlé tlačítko tvrdí „tady se to dělá, jen teď ne“, kdežto u skillu bez zapsané cesty
    /// se to nedá nikdy. Cestu drží `skillFolders` v `config.json`, viz `GlobalConfig`.
    @ViewBuilder private func skillButton(_ tally: ReviewerTally) -> some View {
        if let folder = Policy.skillFolder(of: tally.reviewer, in: skillFolders) {
            // Ve Finderu, ne „otevřít čím“: složka skillu je místo, do kterého se jde sáhnout na
            // soubory, takže se **vybere ve Finderu** — tatáž cesta, jakou se ukazuje session log.
            Button("Otevřít skill ↗") {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            .controlSize(.small)
            .help(folder.path(percentEncoded: false))
        }
    }

    /// Nápověda nad pruhem — celá čtveřice čísel. Pruh sám nese **poměr**, ne počty, a číslo
    /// z něj se odhadem přečíst nedá.
    private func breakdown(of tally: ReviewerTally) -> String {
        "\(tally.taken) převzato · \(tally.invalid) neplatí · \(tally.irrelevant) nepatří sem · "
            + "\(tally.undecided) nerozhodnuto"
    }
}
