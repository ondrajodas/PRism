import Foundation

/// Tvar GraphQL odpovědi na hlavy pull requestů (#420) — schválně oddělený od doménových modelů,
/// ze stejného důvodu jako `GhConversationResponse`: o tvaru odpovědi nerozhodujeme my.
struct GhPullRequestHeadsResponse: Decodable {
    /// Aliasy dotazu (`pr0`, `pr1`, …) → repozitář.
    ///
    /// **Slovník, ne pojmenovaná pole**: kolik jich je, ví až volající, takže se struktura s poli
    /// napsat nedá. `null` u aliasu je běžná odpověď, ne rozbitý JSON — GitHub ho vrátí u repa,
    /// které se přejmenovalo, u smazaného PR i tam, kam nevidíme, a přiloží k tomu `errors`
    /// (`gh` u toho skončí nenulově, ale data pošle).
    let data: [String: Repository?]?

    struct Repository: Decodable {
        let pullRequest: PullRequestNode?
    }

    struct PullRequestNode: Decodable {
        let headRefOid: String
        let commits: Commits?
    }

    struct Commits: Decodable {
        let nodes: [CommitNode]?
    }

    struct CommitNode: Decodable {
        let commit: Commit?
    }

    struct Commit: Decodable {
        let oid: String
        let committedDate: Date?
    }

    /// Hlavy spárované se **vstupním** polem, ve stejném pořadí, v jakém se dotaz skládal.
    ///
    /// **Chybějící alias v mapě není**, a je to celý kontrakt téhle metody: „na tuhle PR nevíme“
    /// se od „hlava se neposunula“ musí poznat, protože z prvního se nesmí nic tvrdit. Částečná
    /// odpověď je proto platná odpověď — jedna nedostupná PR nemá položit dotaz na zbytek fronty.
    func heads(of ids: [PRIdentifier]) -> [PRIdentifier: PullRequestHead] {
        guard let data else { return [:] }
        var heads: [PRIdentifier: PullRequestHead] = [:]
        for (index, id) in ids.enumerated() {
            guard let node = data[PullRequestHeadsQuery.alias(index)]??.pullRequest else { continue }
            heads[id] = PullRequestHead(sha: node.headRefOid, committedAt: node.date(of: node.headRefOid))
        }
        return heads
    }
}

extension GhPullRequestHeadsResponse.PullRequestNode {
    /// Datum commitu, **jen když je to opravdu ta hlava**.
    ///
    /// Spojení `commits(last: 1)` dává poslední commit PR a ten hlavou být má (změřeno na dvanácti
    /// PR: `oid` se s `headRefOid` shodovalo u všech). Kdyby přesto nesouhlasil, je odpověď
    /// **`nil`** — datum cizího commitu by v řádku dění stálo pod větou o téhle hlavě, tedy tvrdilo
    /// něco, co se nestalo.
    func date(of head: String) -> Date? {
        guard let commit = commits?.nodes?.last?.commit, commit.oid == head else { return nil }
        return commit.committedDate
    }
}
