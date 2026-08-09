import Foundation

/// Tvar odpovědi mutace `addPullRequestReviewThreadReply`.
///
/// Vlastní DTO, ne sdílení s `GhConversationResponse`: ta popisuje **dotaz** na konverzaci
/// a je zanořená do `repository.pullRequest`. Kdyby se sdílelo, změna jednoho tvaru by hýbala
/// druhým — tatáž úvaha, kvůli které má `GhSubmittedReview` vlastní `CodingKeys` proti
/// GraphQL review z #63.
struct GhThreadReplyResponse: Decodable {
    let data: Payload

    struct Payload: Decodable {
        let addPullRequestReviewThreadReply: Result?
    }

    struct Result: Decodable {
        let comment: Comment?
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

    /// `nil` = odpovědi nerozumíme, **ne** „nic se neodeslalo“.
    ///
    /// Změřeno v sandboxu, že `comment: null` přijde s exit kódem **nula** — u prázdného těla,
    /// které publisher nepustí (`PublishRequest.isSendable`). Jiné příčiny neznáme, takže se
    /// z toho dělá `malformedResponse`, tedy „možná odešlo, zkontroluj to“. Vydávat to za
    /// úspěch by přidalo do vlákna komentář, který tam není.
    func comment() -> ThreadComment? {
        guard let comment = data.addPullRequestReviewThreadReply?.comment,
              let author = comment.author?.login,
              let createdAt = comment.createdAt,
              let url = comment.url
        else { return nil }

        return ThreadComment(
            id: comment.id,
            author: author,
            body: comment.body ?? "",
            createdAt: createdAt,
            url: url,
            replyToID: comment.replyTo?.id
        )
    }
}

/// Tvar odpovědi mutací `resolveReviewThread` a `unresolveReviewThread`.
///
/// Jedna struktura pro obě: liší se jen jménem klíče, kdežto `thread` uvnitř je stejný —
/// dvě struktury by znamenaly dvě mapování téhož a druhé z nich by se dřív nebo později
/// rozešlo s prvním.
struct GhThreadResolutionResponse: Decodable {
    let data: Payload

    struct Payload: Decodable {
        let resolveReviewThread: Result?
        let unresolveReviewThread: Result?
    }

    struct Result: Decodable {
        let thread: Thread?
    }

    struct Thread: Decodable {
        let id: String
        let isResolved: Bool?
        let viewerCanResolve: Bool?
        let viewerCanUnresolve: Bool?
    }

    /// `nil` = odpovědi nerozumíme.
    ///
    /// Chybějící `isResolved` se **nedoplňuje**: stav vyřešení je celý výsledek téhle operace,
    /// takže hádat ho znamená tvrdit v okně něco, co GitHub neřekl. Práva se naopak berou jako
    /// „smíš“, stejně jako při čtení konverzace — tlačítko schované kvůli údaji, který
    /// nedorazil, vypadá jako rozbitá aplikace.
    func resolution() -> ThreadResolution? {
        guard let result = data.resolveReviewThread ?? data.unresolveReviewThread,
              let thread = result.thread,
              let isResolved = thread.isResolved
        else { return nil }

        return ThreadResolution(
            threadID: thread.id,
            isResolved: isResolved,
            canResolve: thread.viewerCanResolve ?? true,
            canUnresolve: thread.viewerCanUnresolve ?? true
        )
    }
}
