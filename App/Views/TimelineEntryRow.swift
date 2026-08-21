import SwiftUI

/// Jedna událost osy — čas, ikona, co to bylo a nad čím.
///
/// Přesunuto z `ReviewTimelineView` (#242), který se překreslil na dráhy: sazba zůstala, jen se
/// z hlavního obsahu tabu stal detail pod rozbalením. Od #325 sedí v okně výpisu (`StepFeedView`),
/// tedy v **líném** seznamu — takže si tady nic nesmí vyjednávat výšku ani polohu (#220, #252).
///
/// **Vlastní soubor od #325.** Do té doby ležela v `ReviewerLaneView.swift`, kde ale kreslí výpis
/// už někdo jiný; řádek je věc výpisu, ne dráhy.
struct TimelineEntryRow: View {
    let entry: ReviewerTimeline.Entry
    let worktree: URL?
    /// Nejnovější řádek výpisu se podbarvuje. **Podbarvení, ne rámeček** — rámeček by při každé
    /// události poskočil o řádek a v koutku oka to bliká.
    var isNewest = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.at, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(verbatim: title)
                .font(.caption)
                .fontWeight(titleWeight)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                // **Podlaha, aby detaily stály v jedné svislici** — výpis se čte po sloupci a
                // `Read`/`Bash`/`Grep` jsou různě dlouhé. Delší jméno (`ReportFindings`) ji
                // přeroste, a to je v pořádku; podlaha není strop.
                .frame(minWidth: 46, alignment: .leading)
            if case .tool(let tool) = entry.kind, let detail = tool.shortened(inside: worktree) {
                // U cesty je zajímavý konec (jméno souboru), u příkazu začátek.
                Text(verbatim: detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(tool.keepsTail ? .head : .tail)
                    // Celý zůstává v nápovědě: ořezaný příkaz je k přečtení, ne k vložení do
                    // terminálu, a příkaz, který se nedá vložit zpátky, se nedá zopakovat.
                    .help(detail)
            }
            Spacer(minLength: 0)
            if case .tool(let tool) = entry.kind { mark(of: tool) }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 1)
        .background {
            if isNewest { RoundedRectangle(cornerRadius: 4).fill(Palette.accentWeak) }
        }
    }

    /// Jak krok dopadl — na konci řádku, jak to kreslí návrh (#326).
    ///
    /// **Odmítnutí je štítek, ne červený řádek.** Read-only reviewer je tvrdá podmínka, takže
    /// `Bash(gh:*)` odmítnout **má** a session přesto skončí úspěchem; kdyby řádek vypadal jako
    /// chyba, začal by se ten režim vypínat.
    @ViewBuilder
    private func mark(of tool: ToolAttempt) -> some View {
        let mark = Policy.toolStepMark(of: tool)
        if let text = ReviewerLaneText.step(mark) {
            let label = markLabel(text, mark)
            // Nápověda jen tam, kde je co říct — prázdná by nad krokem otevřela prázdný obláček.
            if let help = ReviewerLaneText.stepHelp(of: tool) { label.help(help) } else { label }
        }
    }

    private func markLabel(_ text: String, _ mark: ToolStepMark) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, design: .monospaced))
            .monospacedDigit()
            .fontWeight(mark == .denied ? .bold : .regular)
            .foregroundStyle(Self.markColor(mark))
            .padding(.horizontal, mark == .denied ? 5 : 0)
            .background {
                if mark == .denied { Capsule().fill(Palette.crit.opacity(0.14)) }
            }
    }

    /// `find`, ne akcent, u běžícího kroku: je to tatáž role jako u puntíku revieweera, který
    /// zrovna něco dělá. Trvání je popiskové (`ink3` v návrhu), odmítnutí `crit`.
    private static func markColor(_ mark: ToolStepMark) -> Color {
        switch mark {
        case .pending: Palette.find
        case .denied: Palette.crit
        case .duration, .none: Palette.ink3
        }
    }

    private var title: String {
        switch entry.kind {
        case .queued: "čeká na volný slot"
        case .started: "session naběhla"
        case .tool(let tool): tool.name
        case .findings(let count): Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
        // Ve výpisu událostí stojí i **důvod** (#345), na rozdíl od odznaku v hlavičce: tady je
        // na řádek jedna věc, takže se místem šetřit nemusí.
        case .intentGap(let gap):
            "\(ReviewerLaneText.intentGapLabel) — \(ReviewerLaneText.intentGapReason(gap))"
        case .finished(let outcome): finishedTitle(outcome)
        }
    }

    private func finishedTitle(_ outcome: ReviewRunOutcome) -> String {
        switch outcome {
        case .finished: "doběhlo"
        case .timedOut: "vypršel čas"
        case .interrupted: "přerušeno aplikací"
        case .failed(let detail): "selhalo: \(detail)"
        }
    }

    /// Jméno kroku nese barvu ikony u těch tří řádků, kvůli kterým se do výpisu chodí: **nahlásil
    /// nálezy**, **doběhlo** a **krok, který zrovna běží** (#325, sekce 20 návrhu). Zbytek je
    /// popisek (`ink-2` jako v návrhu) — v ose o třech stech řádcích je zvýrazněný každý druhý
    /// k nerozeznání od nezvýrazněného.
    ///
    /// **Barva se nasazuje vždycky, `nil` se nepředává.** Ve SwiftUI by dědění šlo, jenže větev
    /// s `nil` znamená dvě různé cesty kreslení jednoho řádku a `--ink-2` je tady beztak
    /// ta správná hodnota, ne dědění z okolí.
    private var titleColor: Color {
        highlight ?? Palette.ink2
    }

    private var titleWeight: Font.Weight {
        highlight == nil ? .regular : .semibold
    }

    /// Barva zvýraznění, nebo `nil` u obyčejného řádku.
    private var highlight: Color? {
        switch entry.kind {
        case .findings, .finished: color
        case .tool(let tool): Policy.toolStepMark(of: tool) == .pending ? Palette.ink : nil
        case .queued, .started, .intentGap: nil
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .queued: "clock"
        case .started: "play.circle"
        case .tool(let tool): Self.toolSymbol(tool.name)
        case .findings: "text.magnifyingglass"
        case .intentGap: "doc.badge.ellipsis"
        case .finished(let outcome): outcome == .finished ? "checkmark.circle" : "exclamationmark.triangle"
        }
    }

    private static func toolSymbol(_ name: String) -> String {
        switch name {
        case "Read": "doc.text"
        case "Grep": "magnifyingglass"
        case "Glob": "folder"
        case "Bash": "terminal"
        case "ReportFindings": "flag"
        default: "wrench.and.screwdriver"
        }
    }

    /// **Akcent, ne mint** (#309), i když „nahlásil nálezy“ je stav: mint dělí stav od akce
    /// **tam, kde stojí vedle sebe**, a na ose žádná akce není — je to výpis toho, co se stalo.
    /// Akcent tu má svou druhou roli, tu samou jako `stateTint` u běžícího reviewera v hlavičce
    /// dráhy: „tohle je ten krok, kvůli kterému se sem chodí“.
    ///
    /// Do #309 to byla `Color.accentColor`, tedy systémová modrá — barva, kterou okno jinak nemá
    /// (`.tint(Palette.accent)` z kořene na `accentColor` nezabírá).
    private var color: Color {
        switch entry.kind {
        case .finished(let outcome): outcome == .finished ? Palette.ok : Palette.stale
        case .findings: Palette.accent
        // `stale`, ne `crit`: zadání, které nedorazilo celé, review nepoložilo — jen ho zúžilo.
        case .intentGap: Palette.stale
        default: .secondary
        }
    }
}
