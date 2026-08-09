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
        HStack(alignment: .top, spacing: 8) {
            axis
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                // **Mezera patří obsahu, ne celému uzlu.** Kdyby odsazovala `HStack`, končila
                // by linka o jedenáct bodů dřív než uzel a osa by mezi položkami měla díry —
                // takhle se `axis` roztáhne přes celou výšku včetně mezery a linka je spojitá.
                .padding(.bottom, 11)
        }
    }

    /// Čára s puntíkem. Druh nese **symbol uvnitř** a barva obrysu — kolečko je pro všechny
    /// uzly stejné, aby osa držela svislou linku a nepřeskakovala v šířce.
    private var axis: some View {
        VStack(spacing: 0) {
            ZStack {
                // **24 bodů a plná barva obrysu**, jak to má návrh (`.tl-dot`). Neutrální uzel
                // je obrys `--line` a symbol `--ink-2`; barvu má jen ten, u kterého něco
                // znamená. Ztlumený obrys (`opacity(0.5)`) dělal ze zeleného schválení
                // nevýrazný šedozelený kroužek, ze kterého verdikt nešel přečíst.
                Circle()
                    .fill(Palette.chrome)
                    .overlay(Circle().strokeBorder(marker.tint ?? Palette.line, lineWidth: 1))
                    .frame(width: 24, height: 24)
                Image(systemName: marker.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(marker.tint ?? Palette.ink2)
            }
            Rectangle()
                .fill(Palette.line)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 24)
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
                if isStale, case .forcePushed(let before, _) = event.kind {
                    staleNotice(before: before)
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
            // Věta a čas **v jednom řádku**, jak to má návrh (`.tl-line`): čas odsunutý k pravé
            // hraně vypadal jako sloupec s údajem, který s větou nesouvisí.
            HStack(spacing: 7) {
                if let actor = events.first?.actor {
                    AvatarView(login: actor.login, url: actor.avatarURL, size: 16)
                    Text(verbatim: actor.login)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                Text("pushnul ") + Text(verbatim: Plural.czech(
                    events.count,
                    one: "commit",
                    few: "commity",
                    many: "commitů"
                )).fontWeight(.semibold).foregroundColor(Palette.ink)
                if let at = events.last?.at {
                    Text(at, format: .relative(presentation: .named))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink2)
            VStack(spacing: 0) {
                ForEach(events) { event in
                    if case .commit(let oid, let headline) = event.kind {
                        HStack(spacing: 9) {
                            Text(verbatim: headline)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.ink2)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: String(oid.prefix(7)))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Palette.ink3)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        if event.id != events.last?.id {
                            Rectangle().fill(Palette.lineSoft).frame(height: 1)
                        }
                    }
                }
            }
            .background(Palette.chrome, in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
        }
    }

    /// Důsledek force-pushe. **Na tokenu `stale`, ne na systémové oranžové** (#216): zastarání
    /// není výstraha, je to „platilo to, dneska už ne“ — vedle červené blokujícího nálezu se
    /// obojí systémovou barvou slévalo do jedné škály naléhavosti.
    ///
    /// Věta je rozdělená na **tvrzení** (`ink`) a **důvod** (`ink2`), jak ji sází návrh: dopad
    /// je to, co se má přečíst z odstupu, sha to, co se dočte, když člověk chce vědět proč.
    ///
    /// **Jen jedno tlačítko**, i když návrh kreslí i `Přenést komentáře`: přenos rozdělaného
    /// review (#69) se v aplikaci nabízí až v potvrzení odeslání, a to s volbou u každé
    /// poznámky zvlášť. Druhý vstup do téhož toku by znamenal buď přenést naslepo, nebo
    /// otevřít odsud tentýž sheet — tedy tlačítko, které jen odjinud zapne, co už jinde je.
    private func staleNotice(before: String?) -> some View {
        HStack(spacing: 9) {
            Text("Nálezy i rozdělané review zastaraly.").fontWeight(.semibold).foregroundColor(Palette.ink)
                + Text(verbatim: " ")
                + Text(verbatim: before.map { "Byly proti \(String($0.prefix(7))), která na větvi už není." }
                    ?? "Byly proti commitu, který na větvi už není.")
            Spacer(minLength: 8)
            if let rerun {
                Button("Pustit review znovu", action: rerun)
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 11.5))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.stale.opacity(0.09), in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Palette.stale.opacity(0.45), lineWidth: 1)
        }
    }

    /// Tvar a barva puntíku podle druhu. Děj má obrysovou ikonu, text bublinu — z osy se tak
    /// dá přejetím očima poznat, kde se mluvilo a kde se něco stalo.
    ///
    /// `tint == nil` znamená neutrální uzel, ne „šedá“: obrys a symbol mají u něj **různou**
    /// barvu, takže je skládá `axis`, ne tenhle výčet.
    private var marker: (symbol: String, tint: Color?) {
        switch node {
        case .commits: ("diamond.fill", Palette.accent)
        case .entry(let entry):
            switch entry {
            case .review(let review): (review.markerSymbol, review.markerTint)
            case .comment: ("bubble.left", nil)
            case .thread: ("arrow.turn.down.right", nil)
            case .event(let event):
                (TimelineEventRow(event: event).symbol, TimelineEventRow(event: event).tint)
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

    /// `nil` u review bez verdiktu — komentované review je na ose obyčejná řeč, takže má
    /// vypadat jako komentář. Barvu nese jedině schválení a vyžádané změny.
    var markerTint: Color? {
        switch state {
        case .approved: .green
        case .changesRequested: .red
        default: nil
        }
    }
}
