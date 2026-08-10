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
        return HStack(spacing: 7) {
            if let actor = event.actor {
                AvatarView(login: actor.login, url: actor.avatarURL, size: 16)
            }
            // **Odznak `Bot` u avataru, ne za větou.** Patří k tomu, kdo událost udělal —
            // a za větou se lepil na jméno toho, **komu** se review vyžádalo („od ondrajodas
            // Bot“), tedy tvrdil něco jiného, než co je pravda.
            if row.isBot {
                Text("Bot")
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.raised, in: .capsule)
                    .foregroundStyle(Palette.ink3)
            }
            title(of: row)
                .font(row.isTitleCode ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(2)
            // **Sha jsou odznaky vedle věty, ne údaj u pravé hrany** (#216): u force-pushe patří
            // ke slovesu („přepsal historii z X na Y“), a odsunuté doprava se četly jako sloupec,
            // který s větou nesouvisí.
            ForEach(Array(row.shas.enumerated()), id: \.offset) { index, sha in
                if index > 0 {
                    Text(verbatim: "→").font(.system(size: 11)).foregroundStyle(Palette.ink3)
                }
                shaBadge(sha)
            }
            if let date = event.at {
                Text(date, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
        }
        .frame(minHeight: 24)
    }

    /// Věta události. Tučné běhy z `attributedTitle` (jména) se dobarvují na `ink` — **barvu
    /// rozhoduje view**, řádek nese jen to, co jméno je.
    private func title(of row: TimelineEventRow) -> Text {
        var value = row.attributedTitle
        for run in value.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            value[run.range].foregroundColor = Palette.ink
        }
        return Text(value)
    }

    private func shaBadge(_ sha: String) -> some View {
        Text(verbatim: sha)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Palette.raised, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineSoft, lineWidth: 1) }
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
            accent: nil,
            url: comment.url
        )
    }

    /// Vlákno bez kotvy. Kreslí ho **tatáž bublina jako u kódu** — dvě podoby téhož vlákna by
    /// se rozešly. Liší se jen `placement`: na ose musí bublina sama říct, ke kterému místu se
    /// váže, a sama nakreslit úryvek (#158), protože nad ní žádný kód není. Cesta a odznaky jsou
    /// od #216 **uvnitř** bubliny, ne nad ní — v návrhu je vlákno jeden celek, kdežto řádek nad
    /// rámečkem vypadal jako popisek k něčemu, co začíná až pod ním.
    private func threadCard(_ thread: ReviewThread) -> some View {
        ThreadBubbleView(
            thread: thread,
            viewer: viewer,
            isExpanded: threadActions.isExpanded(thread),
            toggle: { threadActions.toggle(thread) },
            indent: 0,
            actions: threadActions,
            placement: .timeline
        )
    }

    private func card(
        author: String,
        date: Date?,
        badge: (text: String, color: Color)?,
        body: String,
        emptyNote: String?,
        accent: Color?,
        url: URL? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hlavička **na vlastní ploše a oddělená linkou**, jako u popisu PR (#198) a u bloku
            // kontrol (#209). Do #216 byla uvnitř šedého bloku bez linky, takže se od těla
            // nedala odlišit a karta se četla jako jeden odstavec začínající jménem.
            HStack(spacing: 6) {
                AvatarView(login: author, url: nil, size: 16)
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
                // **Čas až za mezerou, u pravé hrany** (`margin-left: auto` v návrhu).
                // Nalepený na odznak se s ním četl jako jeden údaj.
                Spacer(minLength: 8)
                if let date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                } else {
                    // Rozdělané review na GitHubu ještě odeslané není — a je to důvod, proč
                    // odsud nejde poslat naše (změřeno u #62: 422 `one pending review`).
                    Text("neodeslané")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.stale)
                }
                if let url {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                    }
                    .help("Otevřít na GitHubu")
                }
            }
            // Zúžení jde **před** odsazení, ať `filling()` níž čte plnou šířku karty a rámec
            // na ni dosáhne; děti uvnitř vidí o 22 bodů méně (#220).
            .narrowingWidth(by: 22)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .filling(alignment: .leading)
            .background(Palette.raised)

            Rectangle().fill(Palette.lineSoft).frame(height: 1)

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
            .narrowingWidth(by: 22)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .filling(alignment: .leading)
        }
        .filling(alignment: .leading)
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1) }
        // **Verdikt nese proužek na hraně**, ne jen odznak — tatáž škála jako v řádku fronty
        // a na kartě nálezu, takže se schválení od vyžádaných změn pozná periferně.
        .overlay(alignment: .leading) {
            if let accent {
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

    /// `nil` = **karta proužek nemá**. Volitelná, ne `.secondary`: „má tahle karta verdikt?“ se
    /// jinak musí ptát porovnáním barev, a to se při první změně palety tiše rozejde.
    private func verdictColor(_ review: SubmittedReview) -> Color? {
        switch review.state {
        case .approved: .green
        case .changesRequested: .red
        default: nil
        }
    }
}
