import Foundation

/// GraphQL dotaz na **hlavu a počet příspěvků** víc pull requestů naráz (#512). Čisté funkce,
/// žádné I/O.
///
/// **Jeden dotaz na všechna odložená PR, ne jeden na PR.** Tvar je tentýž jako u
/// `PullRequestHeadsQuery` (#420) a ze stejného důvodu: GraphQL bere víc aliasovaných kořenových
/// polí v jednom dokumentu, takže z počtu PR neroste počet volání. Změřeno u #420, že dvacet
/// aliasů stojí **1 bod z 5000/h**, tedy tolik co jeden.
///
/// **Vlastní dotaz vedle toho na hlavy, ne rozšíření toho existujícího.** Obě rozhlídky mají jiný
/// předfiltr (zastaralé nálezy se ptají na cizí PR s uloženými nálezy, tahle na odložená), takže
/// společný dotaz by musel spojit dvě různé množiny a jedné z nich vozit pole, které nepřečte.
/// Cena za oddělení je **jedno volání navíc v nejhorším případě**; obě rozhlídky mají předfiltr
/// přes `updatedAt`, takže na klidný den je to nula.
///
/// **Owner, jméno a číslo jdou jako typované proměnné**, ne do textu dokumentu — tatáž past jako
/// u `PullRequestHeadsQuery`: `number` je v GraphQL `Int!`, takže by ho `-f` položilo na typu.
///
/// **Prázdný seznam se sem nedostane**: `query() { }` není platný dokument, takže se na nic
/// neptáme už u volajícího (`GhGateway.fetchSnoozeSignals(of:)`).
enum SnoozeProbeQuery {
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
    /// **Pozice, ne `owner/name#číslo`**: alias musí být platné GraphQL jméno, kdežto ve jménech
    /// repozitářů jsou pomlčky a tečky. Odpověď se páruje se **vstupním polem**.
    static func alias(_ index: Int) -> String { "pr\(index)" }

    static func document(for count: Int) -> String {
        let declarations = (0..<count)
            .map { "$owner\($0): String!, $name\($0): String!, $number\($0): Int!" }
            .joined(separator: ", ")
        let fields = (0..<count)
            .map { index in
                """
                  \(alias(index)): repository(owner: $owner\(index), name: $name\(index)) {
                    pullRequest(number: $number\(index)) { \(probeFields) }
                  }
                """
            }
            .joined(separator: "\n")
        return "query(\(declarations)) {\n\(fields)\n}"
    }

    /// **Součty, ne seznamy.** `totalCount` na spojení je jedno číslo bez stránkování, takže se
    /// nestahuje ani jeden komentář — odložení se ptá „přibylo něco“, ne „co přibylo“.
    ///
    /// **Dvě spojení, ne jedno.** `comments` jsou příspěvky pod pull requestem, `reviews` odeslaná
    /// review — a odpověď ve vlákně u kódu je v GitHubu review o jednom komentáři, takže bez
    /// druhého by odložení „do dalšího komentáře“ přeslechlo zrovna tu diskuzi, která je o kódu.
    /// `commits` v tom schválně **nejsou**: od pushe je tu `headRefOid`, a míchat je do jednoho
    /// čísla by znamenalo, že „přišel komentář“ vyjde po pushi.
    private static let probeFields = """
    headRefOid comments { totalCount } reviews { totalCount }
    """
}
