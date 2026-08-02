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

    var body: some View {
        if timelines.isEmpty {
            ContentUnavailableView(
                "Zatím se nic nedělo",
                systemImage: "waveform",
                description: Text("Až se review spustí, poběží tady, co reviewer právě čte a spouští.")
            )
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
            Text(verbatim: timeline.skill)
                .font(.callout.weight(.semibold))
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func copyResume(_ sessionID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("claude --resume \(sessionID)", forType: .string)
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

    private var lastEntry: String? {
        guard let timeline = timelines.last, let entry = timeline.entries.last else { return nil }
        return identifier(of: entry, in: timeline)
    }
}
