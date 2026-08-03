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
        let comments: Connection<Comment>
    }

    struct Comment: Decodable {
        let id: String
        let body: String?
        let createdAt: Date?
        let url: URL?
        let author: GhAuthor?
        let replyTo: Reference?

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
            comments: pullRequest.comments.page { $0.comment() }
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
            comments: comments.page { $0.comment() }
        )
    }
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
