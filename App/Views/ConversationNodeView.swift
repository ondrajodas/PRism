import SwiftUI

/// Jeden uzel časové osy konverzace (#183).
///
/// **Osa je čára a uzel na ní**, ne odsazený seznam: svislá linka vlevo drží pořadí dějin
/// a puntík na ní nese druh tvarem, ne barvou — pravidlo z #171. Vpravo od ní je obsah:
/// karta u textu, řádek u události.
struct ConversationNodeView: View {
    let node: ConversationNode
    var viewer: String = ""
    var threadActions = ThreadActions()
    /// Zastaraly nálezy? U force-pushe se to říká **přímo u události**, ne jen v hlavičce —
    /// tam se člověk nedívá, když čte, co se dělo.
    var isStale = false
    var rerun: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            axis
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Linka pokračuje i za obsahem uzlu, takže osa nemá díry mezi položkami.
        .padding(.bottom, 10)
    }

    /// Čára s puntíkem. Puntík má **tvar podle druhu**: obrys u děje, výplň u textu.
    private var axis: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Palette.surface)
                    .overlay(Circle().strokeBorder(marker.color.opacity(0.5), lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                Image(systemName: marker.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(marker.color)
            }
            Rectangle()
                .fill(Palette.line)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 22)
    }

    @ViewBuilder private var content: some View {
        switch node {
        case .entry(let entry): entryContent(entry)
        case .commits(let events): commits(events)
        }
    }

    @ViewBuilder private func entryContent(_ entry: ConversationEntry) -> some View {
        switch entry {
        case .event(let event):
            VStack(alignment: .leading, spacing: 8) {
                ConversationEntryView(entry: entry, viewer: viewer, threadActions: threadActions)
                // Důsledek force-pushe patří **k události**: „přepsal historii větve“ samo
                // o sobě neřekne, že tím zastaraly nálezy, na kterých stojí moje review.
                if isStale, case .forcePushed = event.kind {
                    staleNotice
                }
            }
        default:
            ConversationEntryView(entry: entry, viewer: viewer, threadActions: threadActions)
        }
    }

    /// Commity v jednom uzlu — hlavička s počtem a pod ní seznam.
    ///
    /// **Jedenáct pushů nesmí utopit dva komentáře**, kvůli kterým se do konverzace chodí;
    /// jako skupina nesou totéž, co jednotlivě.
    private func commits(_ events: [TimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let actor = events.first?.actor {
                    AvatarView(login: actor.login, url: actor.avatarURL)
                    Text(verbatim: actor.login).font(.caption.weight(.semibold))
                }
                Text(verbatim: "pushnul \(Plural.czech(events.count, one: "commit", few: "commity", many: "commitů"))")
                    .font(.caption)
                Spacer(minLength: 8)
                if let at = events.last?.at {
                    Text(at, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }
            }
            VStack(spacing: 0) {
                ForEach(events) { event in
                    if case .commit(let oid, let headline) = event.kind {
                        HStack(spacing: 8) {
                            Text(verbatim: headline)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: String(oid.prefix(7)))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Palette.ink3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        if event.id != events.last?.id {
                            Rectangle().fill(Palette.lineSoft).frame(height: 1)
                        }
                    }
                }
            }
            .background(Palette.chrome, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1) }
        }
    }

    private var staleNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nálezy i rozdělané review zastaraly — byly proti commitu, který na větvi už není.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let rerun {
                    Button("Pustit review znovu", action: rerun)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }

    /// Tvar a barva puntíku podle druhu. Děj má obrysovou ikonu, text bublinu — z osy se tak
    /// dá přejetím očima poznat, kde se mluvilo a kde se něco stalo.
    private var marker: (symbol: String, color: Color) {
        switch node {
        case .commits: ("diamond.fill", Palette.accent)
        case .entry(let entry):
            switch entry {
            case .review(let review): (review.markerSymbol, review.markerColor)
            case .comment: ("bubble.left", Palette.ink3)
            case .thread: ("arrow.turn.down.right", Palette.ink3)
            case .event(let event):
                (TimelineEventRow(event: event).symbol, TimelineEventRow(event: event).color)
            }
        }
    }
}

extension SubmittedReview {
    /// Tvar a barva puntíku na ose (#183). Verdikt se pozná **tvarem**, ne jen odstínem:
    /// zaškrtnutí schvaluje, vykřičník vyžaduje změny, bublina jen mluví.
    var markerSymbol: String {
        switch state {
        case .approved: "checkmark"
        case .changesRequested: "exclamationmark"
        default: "bubble.left"
        }
    }

    var markerColor: Color {
        switch state {
        case .approved: .green
        case .changesRequested: .red
        default: Palette.ink3
        }
    }
}
