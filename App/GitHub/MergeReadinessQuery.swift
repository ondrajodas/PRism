import Foundation

/// GraphQL dotaz na **hlavičku a slévatelnost víc vlastních pull requestů naráz** (#572)
/// a argumenty, kterými se posílá. Čisté funkce, žádné I/O.
///
/// **Jeden dotaz na celou sadu, ne jeden na pull request.** Je to tentýž vzor jako
/// `PullRequestHeadsQuery` (#420): GraphQL bere víc aliasovaných kořenových polí v jednom
/// dokumentu, takže se `repository(owner:name:)` napíše tolikrát, kolik je PR — a je z toho
/// **jedno** volání `gh`. Měřeno na živém API nad 23 vlastními PR z 16 repozitářů: **1 volání,
/// 2,60–3,64 s, 1 bod z 5000/h, 39,6 kB**. Po jednom (`gh pr view` na hlavičku plus `gh pr view`
/// na slévatelnost) to bylo **46 volání a 29,6 s** — a to je ta cesta, která se u #572 zamítla.
///
/// **Pole jsou doslova ta, která si aplikace tahá i po jednom** — `GhPullRequestDetail.jsonFields`
/// plus `GhBranchStatus.jsonFields`. `gh pr view --json` je nad GraphQL, takže se jména shodují
/// a odpověď dekódují **tytéž typy**. Jediná odchylka je `author { login }`: `--json author` vrací
/// objekt celý, v GraphQL se pole vyjmenovávají.
///
/// **`compare` tady není a je to rozhodnutí, ne opomenutí.** Poloha větve proti základu (#466)
/// potřebuje jméno základu a hlavu, tedy hodnoty **z odpovědi na tenhle dotaz** — GraphQL na
/// sourozenecké pole odkázat neumí, takže by z toho byl druhý dotaz. Deska ji přitom nepotřebuje:
/// `Policy.mergeOffer` se na `divergence` neptá. Dotahuje se proto dál až u otevřené záložky
/// (`AppStore.loadMissingDivergence(for:)`).
///
/// **Owner, jméno a číslo jdou jako typované proměnné, ne do textu dokumentu** — tatáž past jako
/// u `PullRequestHeadsQuery`: ve jménech repozitářů z konfigurace se uvozovky nemají odkud
/// kontrolovat a `number` je v GraphQL `Int!`.
///
/// **Prázdný seznam se sem nedostane**: `query() { }` není platný dokument, takže se na nic
/// neptáme už u volajícího (`GhGateway.fetchMergeReadiness(of:)`).
enum MergeReadinessQuery {
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

    /// Alias, pod kterým v odpovědi leží PR na téhle pozici dotazu. **Pozice, ne `owner/name#číslo`**
    /// — ze stejného důvodu jako u `PullRequestHeadsQuery`: alias musí být platné GraphQL jméno,
    /// kdežto ve jménech repozitářů jsou pomlčky a tečky.
    static func alias(_ index: Int) -> String { "pr\(index)" }

    static func document(for count: Int) -> String {
        let declarations = (0..<count)
            .map { "$owner\($0): String!, $name\($0): String!, $number\($0): Int!" }
            .joined(separator: ", ")
        let fields = (0..<count)
            .map { index in
                """
                  \(alias(index)): repository(owner: $owner\(index), name: $name\(index)) {
                    pullRequest(number: $number\(index)) { \(readinessFields) }
                  }
                """
            }
            .joined(separator: "\n")
        return "query(\(declarations)) {\n\(fields)\n}"
    }

    /// `mergeable` a `mergeStateStatus` jsou **líná pole GitHubu** — první dotaz po pushi vrací
    /// `UNKNOWN`. Tenhle dotaz se **neopakuje** (na rozdíl od `fetchBranchStatus`): opakovat celou
    /// sadu kvůli jednomu nedopočítanému PR by znamenalo platit za dvacet dalších. Nedopočítaná
    /// odpověď se proto **nezapisuje** a zeptá se na ni příští tik — „nevím“ zůstává „nevím“.
    private static let readinessFields = """
    number title author { login } headRefOid baseRefOid url updatedAt state isDraft body \
    headRefName baseRefName isCrossRepository mergeable mergeStateStatus
    """
}
