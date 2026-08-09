import SwiftUI

/// Jedna položka konverzace — cizí review, komentář pod PR, vlákno bez kotvy nebo událost.
///
/// Vytažené z `OverviewView` (#183) při stěhování konverzace do vlastního tabu. Kreslí ho
/// **jen osa** (`ConversationNodeView`) — vlastní typ přesto, protože položka je něco jiného než
/// uzel osy: uzel drží čáru, značku a slučování, položka obsah. Slít je do jednoho view by
/// znamenalo, že se přidáním druhého místa (třeba náhledu vlákna) musí rozplétat.
struct ConversationEntryView: View {
    let entry: ConversationEntry
    var viewer: String = ""
    var threadActions = ThreadActions()

    var body: some View {
        switch entry {
        case .review(let review): reviewCard(review)
        case .comment(let comment): commentCard(comment)
        case .thread(let thread): threadCard(thread)
        case .event(let event): eventRow(event)
        }
    }

    // MARK: - Položky


    /// Co se na PR stalo (#171) — **jeden řádek**, ne karta jako u komentáře.
    ///
    /// Karta je pro text, který si člověk čte; událost je záznam děje o pěti slovech a ve
    /// stejném rámečku jako odstavec prózy by mezi komentáři vypadala důležitěji, než je.
    /// Tímhle se přehled taky čte jako časová osa na GitHubu: ikona, kdo, co, kdy.
    private func eventRow(_ event: TimelineEvent) -> some View {
        let row = TimelineEventRow(event: event)
        // **Symbol nese uzel na ose** (#183), takže se v řádku neopakuje — dvě ikony vedle sebe
        // vypadají jako dva různé údaje.
        return HStack(spacing: 6) {
            if let actor = event.actor {
                AvatarView(login: actor.login, url: actor.avatarURL)
            }
            Text(verbatim: row.title)
                .font(row.isTitleCode ? .system(.caption, design: .monospaced) : .caption)
                .lineLimit(2)
            if row.isBot {
                Text("Bot")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                    .foregroundStyle(.secondary)
            }
            if let date = event.at {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let detail = row.detail {
                Text(verbatim: detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    /// Cizí hotové review. Verdikt je odznak, próza pod ním — a schválení s prázdným tělem
    /// je plnohodnotná položka, takže se nekreslí jako „prázdné“.
    private func reviewCard(_ review: SubmittedReview) -> some View {
        card(
            author: review.author,
            date: review.submittedAt,
            badge: verdictBadge(review),
            body: review.body,
            emptyNote: review.body.isEmpty ? "bez komentáře" : nil,
            accent: verdictColor(review)
        )
    }

    private func commentCard(_ comment: ThreadComment) -> some View {
        card(
            author: comment.author,
            date: comment.createdAt,
            badge: nil,
            body: comment.body,
            emptyNote: nil,
            accent: .secondary,
            url: comment.url
        )
    }

    /// Vlákno bez kotvy. Kreslí ho **tatáž bublina jako u kódu**, jen bez odsazení do sloupce
    /// s čísly řádků — jinak by se totéž vlákno na dvou místech aplikace vykreslovalo dvakrát
    /// jinak. Nad ním je místo, kde bývalo, a pod tím úryvek kódu, ke kterému se váže (#158):
    /// `cesta:řádek` sama o sobě neřekne, o čem je řeč, a jinde se ten kód vzít nedá — číslo
    /// řádku je ze starého headu, takže se v diffu nekreslí.
    /// Vlákno bez kotvy. Kreslí ho **tatáž bublina jako u kódu** — dvě podoby téhož vlákna by
    /// se rozešly. Cesta a odznak jsou od #216 **uvnitř** bubliny (hlavička `ThreadBubbleView`),
    /// ne nad ní: v návrhu je vlákno jeden celek, kdežto řádek nad rámečkem vypadal jako
    /// popisek k něčemu, co začíná až pod ním.
    private func threadCard(_ thread: ReviewThread) -> some View {
        ThreadBubbleView(
            thread: thread,
            viewer: viewer,
            isExpanded: threadActions.isExpanded(thread),
            toggle: { threadActions.toggle(thread) },
            indent: 0,
            actions: threadActions,
            snippetContext: Policy.timelineSnippetContext
        )
    }

    /// `originalLine` je u zastaralého vlákna to jediné, co zbylo — `line` je `nil` právě
    /// u nich (ověřeno na `cli/cli#13084`: 24 ze 38 vláken).
    private func location(of thread: ReviewThread) -> String {
        guard let line = thread.anchorLine else { return thread.path }
        return "\(thread.path):\(line)"
    }

    private func card(
        author: String,
        date: Date?,
        badge: (text: String, color: Color)?,
        body: String,
        emptyNote: String?,
        accent: Color,
        url: URL? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hlavička **oddělená linkou**, jako u popisu PR (#198) a u kontrol (#209).
            // Do #216 byla uvnitř šedého bloku, takže se od těla nedala odlišit.
            HStack(spacing: 6) {
                AvatarView(login: author, url: nil, size: 18)
                Text(verbatim: author)
                    .font(.system(size: 12, weight: .semibold))
                if isMine(author) {
                    Text("já")
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                }
                if let badge {
                    Text(verbatim: badge.text)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.18), in: .capsule)
                        .foregroundStyle(badge.color)
                }
                if let date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                } else {
                    // Rozdělané review na GitHubu ještě odeslané není — a je to důvod, proč
                    // odsud nejde poslat naše (změřeno u #62: 422 `one pending review`).
                    Text("neodeslané")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                if let url {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                    }
                    .help("Otevřít na GitHubu")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 2)

            Group {
                if !body.isEmpty {
                    // Próza 12,5 jako všude jinde v okně — do #216 byla o stupeň větší než
                    // sousední bloky.
                    MarkdownText(text: body, font: .system(size: 12.5))
                } else if let emptyNote {
                    Text(verbatim: emptyNote)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
        // **Verdikt nese proužek na hraně**, ne jen odznak — tatáž škála jako v řádku fronty
        // a na kartě nálezu, takže se schválení od vyžádaných změn pozná periferně.
        .overlay(alignment: .leading) {
            if accent != .secondary {
                Rectangle().fill(accent).frame(width: 3)
            }
        }
        .clipShape(.rect(cornerRadius: 7))
    }

    /// Prázdný `viewer` znamená „nevím“, ne „to jsem já“ — jinak by se u nenačtené konverzace
    /// označilo za moje všechno bez autora. Stejné pravidlo jako v bublině vlákna.
    private func isMine(_ author: String) -> Bool {
        !viewer.isEmpty && author == viewer
    }

    private func verdictBadge(_ review: SubmittedReview) -> (text: String, color: Color)? {
        switch review.state {
        case .approved: ("schválil", .green)
        case .changesRequested: ("vyžádal změny", .red)
        case .dismissed: ("zamítnuté review", .secondary)
        case .pending: ("rozdělané review", .orange)
        // `commented` odznak nemá: je to komentář jako každý jiný a odznak „komentoval“ by
        // vedle jména autora neřekl nic. Neznámý stav (`nil`) taky ne — vymýšlet si k němu
        // popisek by znamenalo tvrdit něco, co jsme nedostali.
        case .commented, nil: nil
        }
    }

    private func verdictColor(_ review: SubmittedReview) -> Color {
        switch review.state {
        case .approved: .green
        case .changesRequested: .red
        default: .secondary
        }
    }
}
