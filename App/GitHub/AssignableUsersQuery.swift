import Foundation

/// GraphQL dotaz na lidi, kteří na repo smí — nabídka k `+ reviewer` (#392). Čisté funkce,
/// žádné I/O.
///
/// **`assignableUsers`, ne `collaborators`.** REST `GET /repos/{o}/{r}/collaborators` chce push
/// právo, takže by na repu, kam se dá jen číst, skončil 403 — a to je stav, ve kterém se nabídka
/// otevřít nemá, ale jinou větou než „nepodařilo se“. `assignableUsers` je navíc přesně ta množina,
/// ze které GitHub sám dovolí review vyžádat, takže nabídka nemůže obsahovat volbu, kterou pak
/// zápis odmítne.
enum AssignableUsersQuery {
    /// Sto lidí je řádově víc, než kolik má tým, který si navzájem dělá review. Přes to se
    /// nestránkuje: nabídka není seznam, ve kterém se hledá, ale ta hrstka jmen, mezi kterými se
    /// vybírá.
    static let pageSize = 100

    static func arguments(for repo: RepoID, pageSize: Int = Self.pageSize) -> [String] {
        [
            "api", "graphql",
            "-f", "query=\(document)",
            "-F", "owner=\(repo.owner)",
            "-F", "repo=\(repo.name)",
            "-F", "page=\(pageSize)",
        ]
    }

    /// `-F` u `page`, protože `Int!` přes `-f` spadne na typu — tatáž past jako
    /// u `ConversationQuery`.
    static let document = """
    query($owner: String!, $repo: String!, $page: Int!) {
      repository(owner: $owner, name: $repo) {
        assignableUsers(first: $page) { nodes { login } }
      }
    }
    """
}
