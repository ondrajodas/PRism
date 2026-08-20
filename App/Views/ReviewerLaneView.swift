import SwiftUI

/// Jedna dráha v tabu `Průběh` (#242, `.lane`).
///
/// Fáze vedle sebe, protože otázka je **srovnávací**: kdo je hotový, kdo běží a kdo spadl. Karta
/// se svislým seznamem událostí na to neodpovídala — muselo se scrollovat a pamatovat si, kde kdo
/// byl. Podrobný výpis událostí tím ale nezmizel: schová se do rozbalení, protože „co reviewer
/// doopravdy přečetl“ je jediná odpověď na otázku, jestli se koukal tam, kam měl.
struct ReviewerLaneView: View {
    let lane: ReviewerLane
    /// Zkrácené jméno skillu. Počítá se z celé sady naráz (`Policy.shortReviewerNames`), takže
    /// ho dráha dostává hotové — zkrátit se smí jen to, co zůstane jednoznačné vůči ostatním.
    let shortName: String
    /// Pustí **jen tohohle** revieweera znovu (#149). `nil` = nejde to (běží jiný běh).
    var rerun: (() -> Void)?
    /// Zkopíruje příkaz k vložení do terminálu. `nil` = neví se, proti čemu se diffuje, takže by
    /// zkopírovaný příkaz nebyl spustitelný.
    ///
    /// **Closure, ne hotový `String`**: příkaz nese celý prompt, takže by se skládal při každém
    /// překreslení tabu, i když se na tlačítko nikdy neklikne.
    var copyCommand: (() -> Void)?

    @State private var showsEntries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            phases
            if let last = ReviewerLaneText.last(of: lane) {
                Text(verbatim: last)
                    .font(.callout)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if let failure = lane.failure { failureBlock(failure) }
            if !lane.entries.isEmpty { entriesDisclosure }
        }
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: 9) {
            Text(verbatim: shortName)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .help(lane.skill)
            statePill
            // Dráha po skillu, který v nastavené sadě není. Nezmizí (to by zahodilo doběhlé
            // review), ale nesmí se tvářit, že do dnešní sady patří.
            if !lane.isConfigured {
                Label("mimo sadu", systemImage: "slash.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help("Tenhle skill není v nastavené sadě pro tohle repo — dráha je ze zaznamenaného běhu, ne z dnešního nastavení.")
            }
            // Zadání, které nedorazilo celé (#345). Musí to být poznat **na dráze**, ne až
            // v souboru: review bez textu issue vypadá v okně stejně jako to s ním, a nález,
            // který se váže k zadání, se tak nemá čím nestat. Popisek je krátký schválně —
            // který díl chyběl, řekne nápověda; hlavička nese už jméno, stav a cenu.
            if let gap = lane.intentGap {
                Label(ReviewerLaneText.intentGapLabel, systemImage: "doc.badge.ellipsis")
                    .font(.caption)
                    .foregroundStyle(Palette.stale)
                    .lineLimit(1)
                    .help(ReviewerLaneText.intentGap(gap))
            }
            // Hlavička tvrdí, který skill běžel. Když si session načetla jiný, musí to říct —
            // jinak je to text, co tvrdí víc, než data unesou.
            if let loaded = lane.loadedSkill {
                Label("běžel \(loaded)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.stale)
                    // Jen to, co je jisté: detekce hlásí **jakoukoli** neshodu, takže tvrdit
                    // příčinu by bylo hádání vydávané za zjištění.
                    .help("Session si načetla jiný skill, než je nastavený (`\(lane.skill)`).")
            }
            Spacer(minLength: 8)
            if let usage = ReviewerLaneText.usage(of: lane) {
                Text(verbatim: usage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
                    .help("Cena, trvání a počet kol modelu, jak je nahlásila session (`result` event).")
            }
            if let sessionID = lane.sessionID { resume(sessionID) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statePill: some View {
        Text(verbatim: ReviewerLaneText.state(lane.state))
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(stateTint.opacity(0.15), in: .capsule)
            .foregroundStyle(stateTint)
    }

    private var stateTint: Color {
        switch lane.state {
        // Nejtišší z odznaků: nic se nestalo, takže nemá co přitahovat oko. `ink2` u `queued` je
        // proti tomu o odstín víc — tam se něco děje, jen ne tady.
        case .notStarted, .missingProgress: Palette.ink3
        case .queued, .stopped: Palette.ink2
        case .running: Palette.accent
        case .finished: Palette.ok
        case .timedOut, .interrupted: Palette.stale
        case .failed: Palette.crit
        }
    }

    /// Levná náhrada vestavěného terminálu: session se dá otevřít v tom svém.
    private func resume(_ sessionID: String) -> some View {
        Button("Zkopírovat resume", systemImage: "doc.on.doc") {
            Clipboard.copy("claude --resume \(sessionID)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
        .help("claude --resume \(sessionID)")
    }

    // MARK: - Fáze

    /// Fáze v poměru, ne rovným dílem: `prochází kód` je to, v čem běh tráví většinu času, takže
    /// dostává nejvíc místa. Šířky počítá `ProportionalColumns`, aby se nevyjednávaly na každé
    /// úrovni (#220).
    private var phases: some View {
        ProportionalColumns(ratios: lane.phases.map(ratio(of:)), spacing: 3) {
            ForEach(lane.phases, id: \.self) { phase in
                phaseChip(phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private func ratio(of phase: ReviewerLane.Phase) -> Double {
        phase.title == ReviewerLane.Title.code ? 2.6 : 1
    }

    private func phaseChip(_ phase: ReviewerLane.Phase) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: phase.title)
                .lineLimit(1)
            if let detail = phase.detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let mark = mark(of: phase.state) {
                Image(systemName: mark).font(.system(size: 8))
            }
        }
        .font(.system(size: 10.5, weight: phase.state == .running ? .semibold : .regular))
        .foregroundStyle(tint(of: phase.state))
        .padding(.horizontal, 8)
        // Chip **vyplní svůj podíl** (`.ph { flex }`), jinak jsou mezi fázemi mezery a dráhy se
        // nedají porovnat — a porovnání je jediný důvod, proč fáze stojí vedle sebe. `.infinity`
        // je tady bezpečné (a #220 to nezakazuje): `ProportionalColumns` navrhuje **konkrétní**
        // šířku, takže se nevyjednává, jen se roztáhne na to, co dostal.
        .frame(maxWidth: .infinity)
        .frame(height: 23)
        .background(background(of: phase.state), in: .rect(cornerRadius: 5))
        .accessibilityElement(children: .combine)
        // Stav **té fáze**, ne celé dráhy: ten by u všech fází přečetl totéž.
        .accessibilityValue(ReviewerLaneText.phase(phase.state))
    }

    /// Značka za popiskem. **`idle` nemá žádnou** — fáze, na kterou nedošlo, není ani hotová,
    /// ani rozbitá, a jakýkoli symbol by o ní tvrdil, že se něco stalo. Totéž platí o `unknown`:
    /// tam se neví, jak dopadla, takže značka by si vybírala za nás.
    private func mark(of state: ReviewerLane.PhaseState) -> String? {
        switch state {
        case .done: "checkmark"
        case .failed: "xmark"
        case .stopped: "minus"
        case .running, .idle, .unknown: nil
        }
    }

    private func tint(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .done: Palette.ok
        case .running: Palette.find
        case .failed: Palette.crit
        case .stopped: Palette.stale
        case .idle, .unknown: Palette.ink3
        }
    }

    private func background(of state: ReviewerLane.PhaseState) -> Color {
        switch state {
        case .idle, .unknown: Palette.raised
        default: tint(of: state).opacity(0.16)
        }
    }

    // MARK: - Spadlá session

    /// Důvod, konec logu a co s tím.
    ///
    /// **`čisté` a `spadlo` se nesmí slít** — do #242 se v panelu lišily jen barvou odznaku, protože
    /// na důvod ani na `stderr` nebylo v kartě místo. Přes celou šířku je, takže je vidět, na čem
    /// to skončilo, i to, že nálezy z tohohle revieweera **nejsou žádné**.
    private func failureBlock(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session skončila chybou, takže z tohohle revieweera nálezy nejsou — což není totéž jako čisto.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // `stderr` celý a k vybrání: je to jediné, z čeho se pozná, co dělat dál.
            Text(verbatim: detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.chrome, in: .rect(cornerRadius: 6))
            HStack(spacing: 8) {
                if let rerun {
                    Button("Pustit znovu", systemImage: "arrow.clockwise", action: rerun)
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                }
                if let copyCommand {
                    Button("Zkopírovat příkaz", systemImage: "doc.on.doc", action: copyCommand)
                    .buttonStyle(.bordered)
                    .font(.caption)
                    // Nesmí to slibovat zápis toho, co běželo: `baseSha` i model se od minula
                    // mohly změnit, takže je to příkaz, jakým by se reviewer spustil teď.
                    .help("Zkopíruje příkaz, jakým by se tenhle reviewer spustil teď — k vložení do terminálu.")
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.crit.opacity(0.06))
        .overlay(alignment: .leading) { Rectangle().fill(Palette.crit).frame(width: 3) }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    // MARK: - Události

    /// Podrobný výpis toho, co reviewer spouštěl — sbalený, protože dráha odpovídá na „kdo kde je“
    /// a tohle na „co doopravdy přečetl“. Zůstává schválně: bez něj by z okna zmizela jediná
    /// odpověď na to, jestli se reviewer koukal tam, kam měl.
    private var entriesDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsEntries.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showsEntries ? 90 : 0))
                        .font(.caption2)
                    Text(verbatim: entriesLabel)
                        .font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.ink3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showsEntries {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lane.entries) { entry in
                        TimelineEntryRow(entry: entry, worktree: lane.worktree)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var entriesLabel: String {
        let count = Plural.czech(
            lane.entries.count,
            one: "krok session",
            few: "kroky session",
            many: "kroků session"
        )
        // Zkrácená osa to musí říct (#203) — jinak vypadá, že běh začal uprostřed.
        guard lane.droppedEntries > 0 else { return count }
        return "\(count) · \(lane.droppedEntries) starších se nevešlo"
    }
}

/// Jedna událost osy — čas, ikona, co to bylo a nad čím.
///
/// Přesunuto z `ReviewTimelineView` (#242), který se překreslil na dráhy: sazba zůstala, jen se
/// z hlavního obsahu tabu stal detail pod rozbalením.
struct TimelineEntryRow: View {
    let entry: ReviewerTimeline.Entry
    let worktree: URL?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.at, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(verbatim: title)
                .font(.caption)
            if case .tool(let tool) = entry.kind, let detail = tool.shortened(inside: worktree) {
                // U cesty je zajímavý konec (jméno souboru), u příkazu začátek.
                Text(verbatim: detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(tool.keepsTail ? .head : .tail)
            }
            Spacer(minLength: 0)
            if case .tool(let tool) = entry.kind { mark(of: tool) }
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
    /// Akcent tu má svou druhou roli, tu samou jako `stateTint` u běžícího reviewera o pár set
    /// řádků výš: „tohle je ten krok, kvůli kterému se sem chodí“.
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
