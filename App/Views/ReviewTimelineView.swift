import AppKit
import SwiftUI

/// Časová osa toho, co reviewery dělaly — sekce na revieweera, události pod sebou.
///
/// Vykresluje se **nativně z eventů**, ne přeposíláním textu ze session. Proto v první
/// verzi nepotřebuje vestavěný terminál; jedinou cestou zpět do session je
/// `claude --resume`, které se dá zkopírovat z hlavičky.
struct ReviewTimelineView: View {
    let timelines: [ReviewerTimeline]
    /// Při běžícím review se osa sama posouvá na konec.
    var followsTail = true

    /// Zkrácená jména reviewerů pro hlavičky sekcí. Počítá se z **celé** osy naráz, protože
    /// zkrátit se smí jen to, co zůstane jednoznačné vůči ostatním.
    private var shortNames: [String: String] {
        Policy.shortReviewerNames(of: timelines.map(\.skill))
    }

    var body: some View {
        if timelines.isEmpty {
            // **Ne `ContentUnavailableView`** (#182): ten se v panelu na výšku vystředí, nadpis
            // vysází na velikost titulku a nad text vloží prázdno přes půl okna. Ve svislém
            // panelu je to jen vysvětlivka — patří nahoru a psaná drobným písmem, stejně jako
            // prázdný stav nálezů vedle.
            VStack(alignment: .leading, spacing: 4) {
                Text("Zatím se nic nedělo.")
                Text("Až se review spustí, poběží tady, co reviewer právě čte a spouští.")
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
        } else {
            entries
        }
    }

    private var entries: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(timelines) { timeline in
                        Section {
                            ForEach(timeline.entries) { entry in
                                row(entry, in: timeline).id(identifier(of: entry, in: timeline))
                            }
                        } header: {
                            header(timeline)
                        }
                    }
                }
            }
            .onChange(of: lastEntry) { _, last in
                guard followsTail, let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    // MARK: - Reviewer

    private func header(_ timeline: ReviewerTimeline) -> some View {
        HStack(spacing: 8) {
            // Zkrácené jméno (#182): `code-review:code-review` se v panelu 300 bodů širokém
            // zalomí na tři řádky. Celé id zůstává v nápovědě — a zkracuje se jen tam, kde
            // tím jméno nepřestane být jednoznačné (`Policy.shortReviewerNames`).
            Text(verbatim: shortNames[timeline.skill] ?? timeline.skill)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .help(timeline.skill)
            // Hlavička tvrdí, který skill běžel. Když si session načetla jiný, musí to
            // říct — jinak je to text, co tvrdí víc, než data unesou.
            if timeline.loadedADifferentSkill, let loaded = timeline.loadedSkill {
                Label("běžel \(loaded)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    // Jen to, co je jisté. Nejčastější příčina je, že nastavené id na nic
                    // nemapuje, ale detekce hlásí **jakoukoli** neshodu — tvrdit příčinu
                    // by bylo hádání vydávané za zjištění.
                    .help("Session si načetla jiný skill, než je nastavený (`\(timeline.skill)`).")
            }
            // Zkrácená osa to musí říct (#203) — jinak vypadá, že běh začal uprostřed.
            if timeline.droppedEntries > 0 {
                Text(verbatim: "+\(timeline.droppedEntries) starších")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .help("Starší události se do uloženého záznamu nevešly.")
            }
            if let sessionID = timeline.sessionID {
                Text(verbatim: sessionID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Levná náhrada vestavěného terminálu: session se dá otevřít v tom svém.
                Button("Zkopírovat resume", systemImage: "doc.on.doc") {
                    copyResume(sessionID)
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .help("claude --resume \(sessionID)")
            }
            Spacer()
            usage(timeline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// Co běh stál (#148). Ukazuje se, **až když to dorazí** — cenu nese `result` event, takže
    /// běžící reviewer ji nemá a zabitý ji mít nebude. Nula by tvrdila, že běh byl zdarma.
    @ViewBuilder private func usage(_ timeline: ReviewerTimeline) -> some View {
        if let usage = timeline.usage, let summary = RunUsageText.summary(of: usage) {
            Text(verbatim: summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Cena, trvání a počet kol modelu, jak je nahlásila session (`result` event).")
        }
    }

    private func copyResume(_ sessionID: String) {
        Clipboard.copy("claude --resume \(sessionID)")
    }

    // MARK: - Událost

    private func row(_ entry: ReviewerTimeline.Entry, in timeline: ReviewerTimeline) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.at, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
            Image(systemName: symbol(of: entry.kind))
                .font(.caption)
                .foregroundStyle(color(of: entry.kind))
                .frame(width: 14)
            Text(verbatim: title(of: entry.kind))
                .font(.callout)
            if case .tool(let tool) = entry.kind, let detail = tool.shortened(inside: timeline.worktree) {
                // U cesty je zajímavý konec (jméno souboru), u příkazu začátek.
                Text(verbatim: detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(tool.keepsTail ? .head : .tail)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private func title(of kind: ReviewerTimeline.Entry.Kind) -> String {
        switch kind {
        case .queued: "čeká na volný slot"
        case .started: "session naběhla"
        case .tool(let tool): tool.name
        case .findings(let count): Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
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

    private func symbol(of kind: ReviewerTimeline.Entry.Kind) -> String {
        switch kind {
        case .queued: "clock"
        case .started: "play.circle"
        case .tool(let tool): toolSymbol(tool.name)
        case .findings: "text.magnifyingglass"
        case .finished(let outcome): outcome == .finished ? "checkmark.circle" : "exclamationmark.triangle"
        }
    }

    private func toolSymbol(_ name: String) -> String {
        switch name {
        case "Read": "doc.text"
        case "Grep": "magnifyingglass"
        case "Glob": "folder"
        case "Bash": "terminal"
        case "ReportFindings": "flag"
        default: "wrench.and.screwdriver"
        }
    }

    private func color(of kind: ReviewerTimeline.Entry.Kind) -> Color {
        switch kind {
        case .finished(let outcome): outcome == .finished ? .green : .orange
        case .findings: .accentColor
        default: .secondary
        }
    }

    /// Identita napříč sekcemi — pořadí události platí jen v rámci jednoho revieweera.
    private func identifier(of entry: ReviewerTimeline.Entry, in timeline: ReviewerTimeline) -> String {
        "\(timeline.skill)#\(entry.id)"
    }

    /// Kam posouvat, když je zapnuté sledování konce. Nejnovější událost se hledá
    /// **napříč** reviewery — viz `ReviewerTimeline.newestEntry(in:)`.
    private var lastEntry: String? {
        ReviewerTimeline.newestEntry(in: timelines).map { "\($0.skill)#\($0.entry)" }
    }
}
