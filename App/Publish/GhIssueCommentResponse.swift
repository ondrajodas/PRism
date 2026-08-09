import Foundation

/// Tvar odpovědi `POST /repos/{repo}/issues/{n}/comments` (#216).
///
/// Vlastní DTO, ne sdílení s `GhConversationResponse`: REST používá `user`, `created_at`
/// a `html_url`, kdežto GraphQL v #63 `author`, `createdAt` a `url`. Je to tatáž úvaha jako
/// u `GhSubmittedReview` — dvě různá jména pro totéž se nemají slévat do jednoho typu, který
/// by pak musel umět obojí.
struct GhIssueCommentResponse: Decodable {
    let id: Int
    let body: String?
    let createdAt: Date?
    let htmlURL: URL?
    let user: GhAuthor?

    enum CodingKeys: String, CodingKey {
        case id, body, user
        case createdAt = "created_at"
        case htmlURL = "html_url"
    }

    /// `nil` = odpovědi nerozumíme.
    ///
    /// **Autor, čas ani odkaz se nedoplňují náhradou.** Vytvořený komentář má všechny tři
    /// vždycky, takže jejich absence znamená, že odpověď není tím, co čekáme — a vymyslet
    /// k němu prázdného autora nebo `Date()` je totéž jako vymyslet si, že se odeslalo.
    /// Volající z toho udělá `malformedResponse`, ze kterého je vidět, že se to má
    /// zkontrolovat na GitHubu. Tatáž úvaha jako u `GhSubmittedReview`.
    ///
    /// Prázdné **tělo** sem dojít nemůže — publisher ho nepustí (`PublishRequest.isSendable`),
    /// takže chybějící `body` je taky známka toho, že odpověď nesedí.
    func comment() -> ThreadComment? {
        guard let author = user?.login, let body, let createdAt, let htmlURL else { return nil }
        return ThreadComment(
            // REST dává číselné `id`, GraphQL řetězcové. `ThreadComment` drží řetězec,
            // protože z něj skládáme klíče a texty.
            id: String(id),
            author: author,
            body: body,
            createdAt: createdAt,
            url: htmlURL,
            // Komentář pod PR není ve vlákně, takže na co odpovídá, nemá smysl —
            // `Conversation` ho drží ve vlastní stránce, ne uvnitř vlákna.
            replyToID: nil
        )
    }
}
