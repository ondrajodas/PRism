import Foundation

/// GraphQL dotaz na to, **o kolik je větev vedle základu** (#466), a argumenty, kterými se posílá.
/// Čisté funkce, žádné I/O.
///
/// **Proč vlastní dotaz, a ne pole navíc v `gh pr view --json`:** `mergeStateStatus` na otázku
/// „je větev pozadu“ **neodpovídá**. Změřeno na `prism-review-sandbox#9` — větev o commit pozadu
/// za `master` vrátila `CLEAN`, ne `BEHIND`. `BEHIND` GitHub vydá jedině tam, kde je na základu
/// ochrana *Require branches to be up to date*; jinde je „pozadu“ stav, který mergi nebrání,
/// takže o něm `mergeStateStatus` mlčí. Sekce `Větev` ho přesto potřebuje: podle něj se rozhoduje,
/// jestli má smysl nabízet `Srovnat s main`, a stojí v ní jako `o N commitů vzadu`.
///
/// **`compare` na `Ref`, ne `compare` REST API.** REST `GET /compare` vrací k tomu jednomu číslu
/// i seznam souborů (do 300 položek), kdežto GraphQL vydá jen ta tři pole. Změřeno na živém API:
/// `ref(master).compare(headRef: <commit o jeden zpátky>)` vrátilo `aheadBy: 0, behindBy: 1,
/// status: BEHIND`, na větvi s vlastním commitem `aheadBy: 1, behindBy: 1, status: DIVERGED` —
/// **čísla jsou tedy z pohledu hlavy**, ne základu.
///
/// **Hlava se posílá jako `oid`, ne jako jméno větve.** Je to tatáž úvaha jako u prvního guardu
/// tvrdé podmínky č. 1: jméno větve se dá nastavit na cokoli, kdežto `headRefOid` patří k pull
/// requestu — a odpověď má popisovat tu hlavu, kterou okno ukazuje, ne tu, na kterou se větev
/// mezitím pohnula.
enum BranchDivergenceQuery {
    static func arguments(repo: RepoID, base: String, head: String) -> [String] {
        [
            "api", "graphql", "-f", "query=\(document)",
            "-F", "owner=\(repo.owner)",
            "-F", "name=\(repo.name)",
            "-F", "base=refs/heads/\(base)",
            "-F", "head=\(head)",
        ]
    }

    /// **Owner, jméno i refy jdou jako typované proměnné, ne do textu dokumentu** — jinak by se
    /// řešily uvozovky v hodnotách, které aplikace nemá odkud kontrolovat (jméno repa
    /// je z konfigurace). Tatáž past jako u `ConversationQuery` a `PullRequestHeadsQuery`.
    static let document = """
    query($owner: String!, $name: String!, $base: String!, $head: String!) {
      repository(owner: $owner, name: $name) {
        ref(qualifiedName: $base) {
          compare(headRef: $head) { aheadBy behindBy }
        }
      }
    }
    """
}

/// Odpověď na `BranchDivergenceQuery` (#466).
///
/// **Všechno je optional až po `compare`**, a je to schválně: smazaná základní větev (`ref: null`)
/// i hlava, kterou GitHub nezná, jsou stavy, ze kterých plyne „nevím“ — a to je v sekci `Větev`
/// vlastní odpověď (`BranchStatus.divergence == nil`), ne nula.
struct GhBranchDivergence: Decodable {
    struct Data: Decodable {
        let repository: Repository?
    }

    struct Repository: Decodable {
        let ref: Ref?
    }

    struct Ref: Decodable {
        let compare: Comparison?
    }

    struct Comparison: Decodable {
        let aheadBy: Int
        let behindBy: Int
    }

    let data: Data?

    /// Model, nebo `nil` když se to nedá říct.
    var divergence: BranchDivergence? {
        guard let comparison = data?.repository?.ref?.compare else { return nil }
        return BranchDivergence(ahead: comparison.aheadBy, behind: comparison.behindBy)
    }
}
