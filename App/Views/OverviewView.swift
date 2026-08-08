import SwiftUI

/// Tab `Přehled`: popis PR a konverzace, která se neváže k žádnému řádku.
///
/// Vzniklo to proto, že s M6 přibyl obsah, který v diffu nemá kde být — popis PR, komentáře
/// pod PR, review ostatních a vlákna, jejichž řádek v aktuálním diffu není. Nacpat ho do
/// spodního pruhu vedle kódu znamená čít ho v úzkém sloupci pod něčím, s čím nesouvisí.
///
/// **Je to jediný domov téhle konverzace** — vlákna *s kotvou* zůstávají bublinami u kódu.
/// Dvě místa by znamenala hledat komentář dvakrát.
struct OverviewView: View {
    /// Popis PR. `nil` = detail se ještě nenačetl, což je jiný stav než „autor nic nenapsal“.
    var description: String?
    var entries: [ConversationEntry] = []
    /// Stav načtení konverzace. `nil` = ještě se nezačalo.
    var state: ConversationState?
    /// Přihlášený uživatel — kvůli odlišení mých komentářů.
    var viewer: String = ""
    /// Kolik se toho do stránek konverzace nevešlo, po částech.
    var missing: ConversationShortfall = ConversationShortfall()
    /// Rozbalení, odpovídání a vyřešení vláken (#73) — jeden parametr, protože patří k sobě.
    var threadActions = ThreadActions()
    var refresh: () -> Void = {}
    /// Co přibylo od poslední návštěvy (#173). Prázdné = nic, nebo se ještě nenačetla
    /// konverzace; banner se v obou případech nekreslí.
    var changes: VisitChanges = .none
    /// Proti čemu se změny počítají.
    var lastVisit: Date?
    /// Zastaraly nálezy nebo rozdělané review? Tvrzení o **uložených datech**, ne o časové ose,
    /// takže ho počítá store.
    var isStale = false
    var rerun: (() -> Void)?
    /// „Přečteno“ — viz `SinceLastVisitView`.
    var dismissChanges: (() -> Void)?

    let pullRequest: PullRequestSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !changes.isEmpty {
                    SinceLastVisitView(
                        changes: changes,
                        since: lastVisit,
                        isStale: isStale,
                        rerun: rerun,
                        dismiss: dismissChanges
                    )
                }
                descriptionCard
                conversation
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Na rozdíl od diffu tady selekce **je**: není to líný seznam tisíců `Text`ů, ale
        // několik odstavců, a hlavní věc, kterou s cizím komentářem chci udělat, je zkopírovat
        // si z něj kus.
        .textSelection(.enabled)
    }

    // MARK: - Popis PR

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: pullRequest.author)
                    .font(.callout.weight(.semibold))
                Text(verbatim: pullRequest.state.czechLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Link(destination: pullRequest.url) {
                    Label("Otevřít na GitHubu", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
            descriptionBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }

    /// Popis se **renderuje** (`MarkdownText`) — je to Markdown a jako holý text s `##`
    /// a `- [x]` vypadá popis PR nečitelně.
    @ViewBuilder private var descriptionBody: some View {
        if let description, !description.isEmpty {
            MarkdownText(text: description)
        } else if description == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Načítám popis…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Text("Autor k PR nic nenapsal.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Konverzace

    @ViewBuilder private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Konverzace")
                    .font(.headline)
                Spacer(minLength: 0)
                Button("Obnovit konverzaci", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.callout)
                    // Kolega odpoví za minutu, kdežto tik pollingu chodí po minutách — a
                    // konverzace se načítá s ním. Tlačítko je levnější než čekat.
                    .help("Načíst konverzaci znovu z GitHubu")
            }
            if missing.any { shortfallNotice }
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading where entries.isEmpty:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Načítám konverzaci…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let detail):
            failure(detail)
        // Prázdný seznam smí říct „nikdo nic nenapsal“ **jen** nad načtenou konverzací.
        // Jinak by výpadek sítě vypadal jako klidná diskuze.
        case .loaded where entries.isEmpty:
            Text("Pod PR nikdo nic nenapsal a mimo diff nezůstalo žádné vlákno.")
                .font(.callout)
                .foregroundStyle(.secondary)
        default:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry(for: $0) }
            }
        }
    }

    @ViewBuilder private func entry(for entry: ConversationEntry) -> some View {
        switch entry {
        case .review(let review): reviewCard(review)
        case .comment(let comment): commentCard(comment)
        case .thread(let thread): threadCard(thread)
        case .event(let event): eventRow(event)
        }
    }

    /// Co se na PR stalo (#171) — **jeden řádek**, ne karta jako u komentáře.
    ///
    /// Karta je pro text, který si člověk čte; událost je záznam děje o pěti slovech a ve
    /// stejném rámečku jako odstavec prózy by mezi komentáři vypadala důležitěji, než je.
    /// Tímhle se přehled taky čte jako časová osa na GitHubu: ikona, kdo, co, kdy.
    private func eventRow(_ event: TimelineEvent) -> some View {
        let row = TimelineEventRow(event: event)
        return HStack(spacing: 6) {
            Image(systemName: row.symbol)
                .font(.caption)
                .foregroundStyle(row.color)
                .frame(width: 14)
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

    private func failure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Konverzaci se nepodařilo načíst", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(verbatim: detail)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            Button("Zkusit znovu", systemImage: "arrow.clockwise", action: refresh)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    /// Co se nevešlo. Musí to být vidět: chybějící komentář se od „nikdo nic nenapsal“
    /// nepozná, a v `Přehledu` není žádný jiný signál, ze kterého by to plynulo.
    private var shortfallNotice: some View {
        Label {
            Text(verbatim: "\(missing.summary) — otevři PR na GitHubu")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    // MARK: - Položky

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
    private func threadCard(_ thread: ReviewThread) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(verbatim: location(of: thread))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if thread.isOutdated {
                    Text("zastaralé")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .foregroundStyle(.secondary)
                        .help("Řádek, u kterého vlákno vzniklo, v aktuálním diffu není")
                }
                Spacer(minLength: 0)
            }
            if let snippet = Policy.snippet(of: thread) {
                ThreadSnippetView(snippet: snippet, path: thread.path)
            }
            ThreadBubbleView(
                thread: thread,
                viewer: viewer,
                isExpanded: threadActions.isExpanded(thread),
                toggle: { threadActions.toggle(thread) },
                indent: 0,
                actions: threadActions
            )
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: author)
                    .font(.caption.weight(.semibold))
                if isMine(author) {
                    Text("já")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                }
                if let badge {
                    Text(verbatim: badge.text)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.18), in: .capsule)
                        .foregroundStyle(badge.color)
                }
                if let date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // Rozdělané review na GitHubu ještě odeslané není — a je to důvod, proč
                    // odsud nejde poslat naše (změřeno u #62: 422 `one pending review`).
                    Text("neodeslané")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                if let url {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square").font(.caption2)
                    }
                    .help("Otevřít na GitHubu")
                }
            }
            if !body.isEmpty {
                MarkdownText(text: body)
            } else if let emptyNote {
                Text(verbatim: emptyNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) { Rectangle().fill(accent.opacity(0.6)).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 8))
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

/// Kolik se toho do stránek konverzace nevešlo, po částech.
///
/// Vlastní typ, ne tři parametry: do view se to předává na jednom místě a součet „něco chybí“
/// musí být jeden výraz, ne `||` opakované v každém volajícím.
struct ConversationShortfall: Hashable, Sendable {
    var reviews = 0
    var comments = 0
    var threads = 0
    /// Časová osa **bez počtu** (#171).
    ///
    /// Je to jediná část konverzace, u které se nedá říct kolik: `timelineItems` s `itemTypes`
    /// vrací `totalCount` bez ohledu na filtr, takže zbývá `hasNextPage`. Mlčet o tom nejde —
    /// chybějící push se od „nic se nestalo“ nepozná — ale číslo si nesmíme vymyslet.
    var events = false

    init(reviews: Int = 0, comments: Int = 0, threads: Int = 0, events: Bool = false) {
        self.reviews = reviews
        self.comments = comments
        self.threads = threads
        self.events = events
    }

    init(_ conversation: Conversation) {
        self.init(
            reviews: conversation.reviews.missing,
            comments: conversation.comments.missing,
            threads: conversation.threads.missing,
            events: conversation.events.isTruncated
        )
    }

    var any: Bool { reviews > 0 || comments > 0 || threads > 0 || events }

    /// Věta o tom, co chybí — po částech, protože „něco se nevešlo“ nedává důvod jít na
    /// GitHub, kdežto „12 komentářů“ ano.
    var summary: String {
        var parts: [String] = []
        if comments > 0 {
            parts.append(Plural.czech(comments, one: "komentář", few: "komentáře", many: "komentářů"))
        }
        if reviews > 0 {
            parts.append(Plural.czech(reviews, one: "review", few: "review", many: "review"))
        }
        if threads > 0 {
            parts.append(Plural.czech(threads, one: "vlákno", few: "vlákna", many: "vláken"))
        }
        // Bez počtu, protože ho neznáme — „část historie“ je všechno, co se dá poctivě říct.
        if events {
            parts.append("část historie")
        }
        return "Nevešlo se: \(parts.joined(separator: ", "))"
    }
}
