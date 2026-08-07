import Foundation

/// Tvar GraphQL odpovědi na konverzaci — schválně oddělený od doménových modelů.
///
/// Stejný důvod jako u `GhOutput`: kdyby `Conversation` dekódovala rovnou GraphQL, propsalo
/// by se do ní `data.repository.pullRequest`, `nodes`, `pageInfo` i `author.login`. Tady je
/// ta vrstva navíc ještě potřebnější než u `gh --json`, protože o tvaru GraphQL odpovědi
/// nerozhodujeme my, ale schéma GitHubu.
struct GhConversationResponse: Decodable {
    let data: Payload

    struct Payload: Decodable {
        let viewer: Viewer
        let repository: Repository?
    }

    struct Viewer: Decodable {
        let login: String
    }

    struct Repository: Decodable {
        let pullRequest: PullRequest?
    }

    struct PullRequest: Decodable {
        let number: Int
        let reviews: Connection<Review>
        let reviewThreads: Connection<Thread>
        let comments: Connection<Comment>
        /// Volitelné, protože odpovědi z doby před #171 ji nemají — a starší fixture se kvůli
        /// novému poli nesmí přestat dekódovat.
        let timelineItems: Connection<TimelineItem>?
    }

    /// GraphQL stránka. `nodes` může chybět i být `null`, takže se bere jako prázdné —
    /// PR bez jediného komentáře je normální stav, ne rozbitá odpověď.
    struct Connection<Node: Decodable>: Decodable {
        let totalCount: Int
        let pageInfo: PageInfo?
        let nodes: [Node]?

        struct PageInfo: Decodable {
            let hasNextPage: Bool?
        }

        func page<Element: Hashable & Codable & Sendable>(
            _ transform: (Node) throws -> Element?
        ) rethrows -> ConversationPage<Element> {
            ConversationPage(
                items: try (nodes ?? []).compactMap(transform),
                total: totalCount,
                hasNextPage: pageInfo?.hasNextPage ?? false
            )
        }
    }

    struct Review: Decodable {
        let id: String
        let state: String?
        let body: String?
        let submittedAt: Date?
        let author: GhAuthor?
    }

    struct Thread: Decodable {
        let id: String
        let isResolved: Bool?
        let isOutdated: Bool?
        let path: String?
        let line: Int?
        let originalLine: Int?
        let diffSide: String?
        let viewerCanResolve: Bool?
        let viewerCanUnresolve: Bool?
        let comments: Connection<Comment>
    }

    /// Jedna položka časové osy (#171).
    ///
    /// **Jeden plochý tvar se všemi poli volitelnými**, ne typ na každou událost: `nodes` je
    /// union a rozhoduje `__typename`, takže jedenáct `Decodable` typů by znamenalo jedenáct
    /// míst, kde se dá zapomenout na `actor`. Co která událost doopravdy má, říká `kind()`.
    struct TimelineItem: Decodable {
        /// Který druh události to je. Jediné pole, které dorazí **vždycky** — typ uvedený
        /// v `itemTypes` bez fragmentu nemá ani `id` (změřeno na živém API).
        let type: String
        let id: String?
        let createdAt: Date?
        let actor: Actor?
        let commit: Commit?
        let requestedReviewer: Reviewer?
        let beforeCommit: CommitReference?
        let afterCommit: CommitReference?
        let mergeRefName: String?
        let previousRefName: String?
        let currentRefName: String?

        enum CodingKeys: String, CodingKey {
            case type = "__typename"
            case id, createdAt, actor, commit, requestedReviewer
            case beforeCommit, afterCommit, mergeRefName, previousRefName, currentRefName
        }

        /// Kdo událost udělal. Vlastní tvar, protože potřebuje `avatarUrl` a `__typename` —
        /// `GhAuthor` má jen `login` a nese ho komentář, kde na obrázku nezáleží.
        struct Actor: Decodable {
            let type: String?
            let login: String
            let avatarUrl: URL?

            enum CodingKeys: String, CodingKey {
                case type = "__typename"
                case login, avatarUrl
            }
        }

        struct Commit: Decodable {
            let oid: String
            let messageHeadline: String?
            let committedDate: Date?
            let author: Author?

            /// Autor commitu. `user` je `null` u commitu s e-mailem, který nesedí na účet —
            /// pak zbývá `name` z commitu.
            struct Author: Decodable {
                let name: String?
                let user: Actor?
            }
        }

        /// Vyžádaný reviewer. `User`, `Bot` a `Mannequin` mají `login`, `Team` má `name`.
        struct Reviewer: Decodable {
            let login: String?
            let name: String?
        }

        struct CommitReference: Decodable {
            let oid: String
        }
    }

    struct Comment: Decodable {
        let id: String
        let body: String?
        let createdAt: Date?
        let url: URL?
        let author: GhAuthor?
        let replyTo: Reference?
        /// Unified diff od začátku hunku po komentovaný řádek, jak ho GitHub pořídil proti
        /// commitu, na kterém komentář vznikl. Do modelu jde na **vlákno**, ne na komentář —
        /// viz `Thread.thread()`.
        let diffHunk: String?

        struct Reference: Decodable {
            let id: String
        }
    }
}

extension GhConversationResponse {
    /// Konverzace z odpovědi.
    ///
    /// Chybějící `repository` nebo `pullRequest` je chyba — na to jsme se ptali a prázdná
    /// odpověď by v okně vypadala jako PR bez konverzace, tedy jako by kolegové nic
    /// nenapsali. Chybějící **položky uvnitř** naopak chyba nejsou, viz `Connection`.
    ///
    /// Číslo se ověřuje ze stejného důvodu jako u `GhPullRequestDetail`: tichý rozchod by
    /// přilepil komentáře kolegů k cizímu PR a v okně by to vypadalo naprosto v pořádku.
    /// Dotaz se sice ptá číslem, takže cesta k rozchodu není vidět — ale kontrola, která
    /// jinde v repu je, tady nemá chybět jen proto, že si zrovna myslíme, že nehrozí.
    func conversation(id: PRIdentifier) throws -> Conversation {
        guard let repository = data.repository, let pullRequest = repository.pullRequest else {
            throw GitHubError.malformedOutput("GraphQL nevrátil pull request \(id).")
        }
        guard pullRequest.number == id.number else {
            throw GitHubError.malformedOutput(
                "GraphQL vrátil konverzaci PR číslo \(pullRequest.number), ptali jsme se na \(id)."
            )
        }

        return Conversation(
            viewer: data.viewer.login,
            reviews: pullRequest.reviews.page { $0.review() },
            threads: pullRequest.reviewThreads.page { $0.thread() },
            comments: pullRequest.comments.page { $0.comment() },
            events: pullRequest.timelineItems.eventPage()
        )
    }
}

private extension GhConversationResponse.Connection<GhConversationResponse.TimelineItem>? {
    /// Časová osa z odpovědi. Chybějící `timelineItems` = prázdná osa (odpověď před #171).
    ///
    /// **Celkový počet se schválně nebere.** `timelineItems` s `itemTypes` vrací `totalCount`
    /// bez ohledu na filtr — změřeno na `cli/cli#13084`: 49, zatímco uzlů dorazilo 29 a bez
    /// filtru je jich taky 49. Z rozdílu by vyšlo „chybí dvacet událostí“ na PR, kde nechybí
    /// nic, a hláška o zkrácení by svítila pořád. Viz `ConversationPage.init(items:hasNextPage:)`.
    func eventPage() -> ConversationPage<TimelineEvent> {
        ConversationPage(
            items: (self?.nodes ?? []).compactMap { $0.event() },
            hasNextPage: self?.pageInfo?.hasNextPage ?? false
        )
    }
}

private extension GhConversationResponse.Review {
    /// `nil` = review, které se nedá zobrazit. Autor je jediné, bez čeho to nejde: „někdo
    /// schválil PR“ bez toho kdo je informace, se kterou se nedá nic udělat.
    ///
    /// Zahození se **nepočítá** jako u nálezů, protože se počítat nemá čím: `totalCount`
    /// z GraphQL je pravda o PR, ne o tom, kolik jsme jich přečetli, takže rozdíl mezi nimi
    /// už `ConversationPage.missing` hlásí — a hlásí ho i pro tenhle případ.
    func review() -> SubmittedReview? {
        guard let author = author?.login else { return nil }
        return SubmittedReview(
            id: id,
            author: author,
            state: state.flatMap(SubmittedReview.State.init(rawValue:)),
            body: body ?? "",
            submittedAt: submittedAt
        )
    }
}

private extension GhConversationResponse.Thread {
    /// `nil` = vlákno bez cesty, které se nemá kde ukázat.
    func thread() -> ReviewThread? {
        guard let path else { return nil }
        return ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: diffSide.flatMap(DiffSide.init(rawValue:)),
            // Chybějící příznak se bere jako „nevyřešeno“ a „neaktuální ne“: vlákno
            // schované jako vyřešené je horší než vlákno zbytečně otevřené.
            isResolved: isResolved ?? false,
            isOutdated: isOutdated ?? false,
            // Chybějící **právo** se naopak bere jako „smíš“ — opačný směr než u příznaků výš,
            // a schválně. Živé API obě pole vždycky vrátí, takže `nil` znamená starou odpověď,
            // ne odepřené právo; a tlačítko schované kvůli údaji, který nedorazil, vypadá jako
            // rozbitá aplikace. Když právo doopravdy nemám, GitHub akci odmítne hláškou,
            // ze které je vidět, co se stalo.
            canResolve: viewerCanResolve ?? true,
            canUnresolve: viewerCanUnresolve ?? true,
            // Hunk je vlastnost **vlákna**, i když ho GraphQL vrací u komentáře: kotva je
            // jedna a odpovědi ve vlákně nesou tentýž úryvek (změřeno na `cli/cli#13084`,
            // všech 38 vláken). Bere se z prvního komentáře, **který ho má** — ne z prvního
            // komentáře: kdyby ho GitHub u některého vynechal, vlákno by o kontext přišlo
            // kvůli pořadí.
            diffHunk: comments.nodes?.compactMap(\.diffHunk).first,
            comments: comments.page { $0.comment() }
        )
    }
}

private extension GhConversationResponse.TimelineItem {
    /// `nil` = položka, které nerozumíme, nebo která nemá identitu.
    ///
    /// Obojí se **nekreslí**. Změřeno na živém API, že typ uvedený v `itemTypes` bez
    /// odpovídajícího fragmentu dorazí jako `{"__typename": "…"}` a nic víc — z takového uzlu
    /// by v okně vyšel prázdný řádek, tedy událost, o které nejde říct ani co to bylo, ani kdo
    /// za ní stojí. Zahození se nepočítá ze stejného důvodu jako u review: `totalCount` je
    /// u časové osy nepoužitelný (viz `eventPage()`), takže se nemá o co odečítat.
    func event() -> TimelineEvent? {
        guard let id, let kind = kind() else { return nil }
        return TimelineEvent(id: id, kind: kind, actor: eventActor(), at: date())
    }

    /// Druh události podle `__typename`. `nil` = tohle neumíme zobrazit.
    private func kind() -> TimelineEvent.Kind? {
        switch type {
        case "PullRequestCommit":
            guard let commit else { return nil }
            return .commit(oid: commit.oid, headline: commit.messageHeadline ?? "")
        case "ReviewRequestedEvent":
            return .reviewRequested(reviewer: requestedReviewer?.reviewerName)
        case "ReviewRequestRemovedEvent":
            return .reviewRequestRemoved(reviewer: requestedReviewer?.reviewerName)
        case "HeadRefForcePushedEvent":
            return .forcePushed(before: beforeCommit?.oid, after: afterCommit?.oid)
        case "ReadyForReviewEvent": return .readyForReview
        case "ConvertToDraftEvent": return .convertedToDraft
        case "MergedEvent": return .merged(into: mergeRefName)
        case "ClosedEvent": return .closed
        case "ReopenedEvent": return .reopened
        case "BaseRefChangedEvent":
            return .baseChanged(from: previousRefName, to: currentRefName)
        default: return nil
        }
    }

    /// Kdo za událostí stojí.
    ///
    /// U commitu je to jeho autor, ne `actor` — commit `actor`a nemá. Když e-mail nesedí na
    /// účet, `user` je `null` a zbývá jméno z commitu: bez avataru a bez odkazu, ale řádek
    /// bez autora by z toho vyjít nesměl.
    private func eventActor() -> EventActor? {
        if let author = commit?.author {
            if let user = author.user { return user.eventActor() }
            guard let name = author.name, !name.isEmpty else { return nil }
            return EventActor(login: name, avatarURL: nil, isBot: false)
        }
        return actor?.eventActor()
    }

    /// Kdy. Commit má jen datum commitu — `pushedDate` GitHub už neplní, viz `TimelineEvent.at`.
    private func date() -> Date? { commit?.committedDate ?? createdAt }
}

private extension GhConversationResponse.TimelineItem.Actor {
    func eventActor() -> EventActor {
        EventActor(login: login, avatarURL: avatarUrl, isBot: type == "Bot")
    }
}

private extension GhConversationResponse.TimelineItem.Reviewer {
    /// Jméno cíle. `User`, `Bot` a `Mannequin` ho mají v `login`, `Team` v `name` — pro okno
    /// je to jedna a tatáž věta („vyžádal review od …“), takže se to slévá už tady.
    var reviewerName: String? { login ?? name }
}

private extension GhConversationResponse.Comment {
    /// `nil` = komentář bez autora, času nebo odkazu.
    ///
    /// Autor u smazaného účtu chybí (GitHub vrací `null`), a komentář „od nikoho“ nemá
    /// v konverzaci co říct. Tady je zahození nejcitlivější, proto to hlásí `missing`.
    func comment() -> ThreadComment? {
        guard let author = author?.login, let createdAt, let url else { return nil }
        return ThreadComment(
            id: id,
            author: author,
            body: body ?? "",
            createdAt: createdAt,
            url: url,
            replyToID: replyTo?.id
        )
    }
}
