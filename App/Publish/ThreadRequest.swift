import Foundation

/// Dotazy, kterými se odpovídá do vlákna a přepíná jeho vyřešení. Čisté funkce, žádné I/O.
///
/// **GraphQL, ne REST — změna proti zadání #73**, které jmenovalo
/// `POST /pulls/{n}/comments/{id}/replies`. Změřeno na živém API v sandboxu:
///
/// - `addPullRequestReviewThreadReply` bere `pullRequestReviewThreadId`, tedy **to `id`, které
///   už v modelu je** (`ReviewThread.id`). REST by potřeboval `databaseId` komentáře, které se
///   dnes z konverzace netahá — takže by se musel rozšířit dotaz, model i mapování, a hlavně
///   by se muselo rozhodnout, na **který** komentář ve vlákně se odpovídá. Vlákno má jednu
///   odpověď, ne odpověď na konkrétní komentář, takže by to bylo rozhodnutí bez opory v datech.
/// - Vyřešení GraphQL vyžaduje tak či tak (`isResolved` v RESTu vůbec není, viz #63), takže
///   jedna cesta místo dvou: jeden způsob volání, jedna klasifikace chyb.
/// - Odpověď mutace nese přesně to, co potřebuje `ThreadComment` (`id`, `body`, `createdAt`,
///   `url`, `author`, `replyTo`), takže se komentář dá do vlákna vložit bez dalšího čtení.
enum ThreadRequest {
    // MARK: - Odpověď

    static let replyDocument = """
    mutation($thread: ID!, $body: String!) {
      addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $thread, body: $body}) {
        comment { id body createdAt url author { login } replyTo { id } }
      }
    }
    """

    /// Tělo jde přes `-f` (řetězec), `thread` taky — `ID!` je v GraphQL řetězec, na rozdíl od
    /// `Int!` u čísla PR v `ConversationQuery`, kde je potřeba `-F`.
    static func replyArguments(to target: ThreadTarget, body: String) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(replyDocument)",
            "-f", "thread=\(target.threadID)",
            "-f", "body=\(body)",
        ]
    }

    // MARK: - Vyřešení

    /// Dvě mutace, ne jedna s příznakem — GitHub jinou možnost nedává.
    static func resolutionDocument(resolved: Bool) -> String {
        let mutation = resolved ? "resolveReviewThread" : "unresolveReviewThread"
        return """
        mutation($thread: ID!) {
          \(mutation)(input: {threadId: $thread}) {
            thread { id isResolved viewerCanResolve viewerCanUnresolve }
          }
        }
        """
    }

    static func resolutionArguments(of target: ThreadTarget, resolved: Bool) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(resolutionDocument(resolved: resolved))",
            "-f", "thread=\(target.threadID)",
        ]
    }

}
