import Foundation

/// GraphQL dotaz na konverzaci a argumenty, kterými se posílá. Čisté funkce, žádné I/O.
///
/// **GraphQL, ne tři REST endpointy.** REST nemá `isResolved` vůbec, takže by otázka „co
/// s vyřešenými vlákny“ neměla odpověď — a byly by to tři podprocesy místo jednoho.
/// Ověřeno na živém API: celý dotaz stojí **1 bod z 5000/h**, ať se ptá na PR se dvěma
/// vlákny nebo s osmatřiceti.
enum ConversationQuery {
    /// Kolik se bere z každého seznamu. Sto komentářů na PR je řádově víc, než kolik jich
    /// vzniká; přes to se nestránkuje, ale **spočítá se, co chybí** (`ConversationPage`),
    /// protože utnutá data nesmí vypadat jako úplná.
    static let pageSize = 100

    static func arguments(for id: PRIdentifier, pageSize: Int = Self.pageSize) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(document)",
            "-F", "owner=\(id.repo.owner)",
            "-F", "repo=\(id.repo.name)",
            "-F", "number=\(id.number)",
            "-F", "page=\(pageSize)",
        ]
    }

    /// `-F` posílá typovanou hodnotu (číslo jako číslo), `-f` řetězec. `number` a `page`
    /// jsou v GraphQL `Int!`, takže přes `-f` by dotaz spadl na typu.
    static let document = """
    query($owner: String!, $repo: String!, $number: Int!, $page: Int!) {
      viewer { login }
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          number
          reviews(first: $page) {
            totalCount
            pageInfo { hasNextPage }
            nodes { id state body submittedAt author { login } }
          }
          reviewThreads(first: $page) {
            totalCount
            pageInfo { hasNextPage }
            nodes {
              id isResolved isOutdated path line originalLine diffSide
              comments(first: $page) {
                totalCount
                pageInfo { hasNextPage }
                nodes { id body createdAt url author { login } replyTo { id } }
              }
            }
          }
          comments(first: $page) {
            totalCount
            pageInfo { hasNextPage }
            nodes { id body createdAt url author { login } }
          }
        }
      }
    }
    """
}
