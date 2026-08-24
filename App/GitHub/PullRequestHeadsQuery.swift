import Foundation

/// GraphQL dotaz na hlavy **víc pull requestů naráz** (#420) a argumenty, kterými se posílá.
/// Čisté funkce, žádné I/O.
///
/// **Jeden dotaz na celou frontu, ne jeden na repozitář.** GraphQL bere víc pojmenovaných
/// (aliasovaných) kořenových polí v jednom dokumentu, takže se `repository(owner:name:)` napíše
/// tolikrát, kolik je pull requestů — a je z toho **jedno** volání `gh` bez ohledu na to, z kolika
/// repozitářů fronta je (u téhle instalace devět až jedenáct). Změřeno na živém API: 12 aliasů
/// z 10 repozitářů stojí **1 bod z 5000/h** a 1,25–2,59 s, 24 aliasů **pořád 1 bod** a 1,25–1,96 s —
/// takže cena je v tom dotazu, ne v počtu PR.
///
/// **Owner, jméno a číslo jdou jako typované proměnné, ne do textu dokumentu.** Vlepovat je do
/// řetězce znamená řešit uvozovky v hodnotách, které aplikace nemá odkud kontrolovat (jméno repa
/// je z konfigurace) — a `number` je v GraphQL `Int!`, takže by ho `-f` položil na typu, tatáž past
/// jako u `ConversationQuery`.
///
/// **Prázdný seznam se sem nedostane**: `query() { }` není platný dokument, takže se na nic
/// neptáme už u volajícího (`GhGateway.fetchHeads(of:)`).
enum PullRequestHeadsQuery {
    static func arguments(for ids: [PRIdentifier]) -> [String] {
        var arguments = ["api", "graphql", "-f", "query=\(document(for: ids.count))"]
        for (index, id) in ids.enumerated() {
            arguments += [
                "-F", "owner\(index)=\(id.repo.owner)",
                "-F", "name\(index)=\(id.repo.name)",
                "-F", "number\(index)=\(id.number)",
            ]
        }
        return arguments
    }

    /// Alias, pod kterým v odpovědi leží PR na téhle pozici dotazu.
    ///
    /// **Pozice, ne `owner/name#číslo`**: alias musí být platné GraphQL jméno (`[_A-Za-z][_0-9A-Za-z]*`),
    /// kdežto ve jménech repozitářů jsou pomlčky a tečky. Odpověď se proto páruje se **vstupním
    /// polem** — jedno místo skládá alias a jedno ho čte.
    static func alias(_ index: Int) -> String { "pr\(index)" }

    static func document(for count: Int) -> String {
        let declarations = (0..<count)
            .map { "$owner\($0): String!, $name\($0): String!, $number\($0): Int!" }
            .joined(separator: ", ")
        let fields = (0..<count)
            .map { index in
                """
                  \(alias(index)): repository(owner: $owner\(index), name: $name\(index)) {
                    pullRequest(number: $number\(index)) { \(headFields) }
                  }
                """
            }
            .joined(separator: "\n")
        return "query(\(declarations)) {\n\(fields)\n}"
    }

    /// `commits(last: 1)` je tam kvůli **času události** — kdy hlava vznikla. Je to jediná část
    /// dotazu, která něco stojí: bez ní vyjde odpověď za ~0,94 s, s ní za 1,25–2,15 s (střídavě
    /// měřeno, `cost` je v obou případech 1). Platí se to jedině v tiku, ve kterém se doopravdy
    /// ptáme, a bez ní by se řádek dění musel datovat okamžikem zjištění — tedy tvrdit, že nálezy
    /// zastaraly dneska, i kdyby se pushnulo před třemi dny.
    ///
    /// `oid` je v odpovědi proto, aby se dalo **ověřit**, že poslední commit v seznamu je
    /// opravdu ta hlava (spojení je řazené od nejstaršího; změřeno na dvanácti PR, že se `oid`
    /// s `headRefOid` shoduje u všech). Neshoda znamená „datum nevíme“, ne cizí datum.
    private static let headFields = """
    headRefOid commits(last: 1) { nodes { commit { oid committedDate } } }
    """
}
