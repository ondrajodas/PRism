import Foundation

/// Tvar GraphQL odpovědi na hlavičku a slévatelnost víc pull requestů (#572) — schválně oddělený
/// od doménových modelů, ze stejného důvodu jako `GhPullRequestHeadsResponse`: o tvaru odpovědi
/// nerozhodujeme my.
struct GhMergeReadinessResponse: Decodable {
    /// Aliasy dotazu (`pr0`, `pr1`, …) → repozitář.
    ///
    /// **Slovník, ne pojmenovaná pole**: kolik jich je, ví až volající. `null` u aliasu je běžná
    /// odpověď, ne rozbitý JSON — GitHub ho vrátí u přejmenovaného repa, u smazaného PR i tam, kam
    /// nevidíme, a přiloží k tomu `errors` (`gh` u toho skončí nenulově, ale data pošle).
    let data: [String: Repository?]?

    struct Repository: Decodable {
        let pullRequest: Node?

        private enum CodingKeys: String, CodingKey { case pullRequest }

        /// **`try?` je tady kontrakt, ne spolknutá chyba.** Chybějící alias a uzel, kterému
        /// nerozumíme, znamenají totéž — o téhle PR se nic nedozvíme a **v mapě prostě nebude**.
        /// Přísné dekódování by z jedné PR bez autora (smazaný účet, bot) udělalo prázdnou odpověď
        /// na celou sadu, tedy prázdný pruh `K merge` kvůli jedinému cizímu záznamu. Ta samá úvaha
        /// jako u `fetchHeads`: částečná odpověď je odpověď.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pullRequest = try? container.decode(Node.self, forKey: .pullRequest)
        }
    }

    /// Jeden pull request — **dva dekodéry nad jedním kontejnerem**, ne třetí typ s opsanými poli.
    ///
    /// `GhPullRequestDetail` a `GhBranchStatus` čtou tatáž jména, jaká vrací `gh pr view --json`,
    /// protože ten je nad GraphQL. Opsat je sem znovu by znamenalo, že se doplněné pole projeví
    /// u jedné cesty a u druhé ne.
    struct Node: Decodable {
        let detail: GhPullRequestDetail
        let status: GhBranchStatus

        init(from decoder: any Decoder) throws {
            detail = try GhPullRequestDetail(from: decoder)
            status = try GhBranchStatus(from: decoder)
        }
    }

    /// Odpovědi spárované se **vstupním** polem, ve stejném pořadí, v jakém se dotaz skládal.
    ///
    /// **Chybějící alias v mapě není**, a je to celý kontrakt téhle metody: „na tuhle PR nevíme“
    /// se od „zeptali jsme se a tohle vyšlo“ musí poznat, protože z prvního se nesmí nic tvrdit.
    ///
    /// **Nedopočítaná slévatelnost se zahazuje taky** (`BranchStatus.isSettled`). `UNKNOWN` je
    /// u GitHubu „ještě jsem nepočítal“ a zapsat ho jako odpověď by znamenalo, že se na to PR do
    /// příštího pushnutí nikdo nezeptá — na desce by zůstalo v `Čeká` i poté, co je dávno čisté.
    /// Neuložená odpověď se naopak zeptá příští tik, a je to **jedno volání pro celou sadu**.
    func readiness(of ids: [PRIdentifier]) -> [PRIdentifier: MergeReadiness] {
        guard let data else { return [:] }
        var readiness: [PRIdentifier: MergeReadiness] = [:]
        for (index, id) in ids.enumerated() {
            guard let node = data[MergeReadinessQuery.alias(index)]??.pullRequest else { continue }
            guard let detail = try? node.detail.pullRequest(id: id) else { continue }
            let status = node.status.status
            guard status.isSettled else { continue }
            readiness[id] = MergeReadiness(detail: detail, status: status)
        }
        return readiness
    }
}
