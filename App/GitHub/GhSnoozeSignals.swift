import Foundation

/// Tvar GraphQL odpovědi na rozhlídku po odložených PR (#512) — schválně oddělený od doménových
/// modelů, ze stejného důvodu jako `GhPullRequestHeadsResponse`: o tvaru odpovědi nerozhodujeme my.
struct GhSnoozeSignalsResponse: Decodable {
    /// Aliasy dotazu (`pr0`, `pr1`, …) → repozitář.
    ///
    /// **Slovník, ne pojmenovaná pole**: kolik jich je, ví až volající. `null` u aliasu je běžná
    /// odpověď, ne rozbitý JSON — GitHub ho vrátí u přejmenovaného repa, u smazaného PR i tam, kam
    /// nevidíme, a přiloží k tomu `errors` (`gh` u toho skončí nenulově, ale data pošle).
    let data: [String: Repository?]?

    struct Repository: Decodable {
        let pullRequest: PullRequestNode?
    }

    struct PullRequestNode: Decodable {
        let headRefOid: String
        let comments: Connection?
        let reviews: Connection?
    }

    struct Connection: Decodable {
        let totalCount: Int
    }

    /// Měření spárovaná se **vstupním** polem, ve stejném pořadí, v jakém se dotaz skládal.
    ///
    /// **Chybějící alias v mapě není**, a je to celý kontrakt téhle metody: „na tuhle PR nevíme“
    /// se od „nezměnilo se nic“ musí poznat, protože z prvního se nesmí nic tvrdit — a u odložení
    /// je to ten rozdíl mezi „trvá dál“ a „vrátit ho do fronty“. Částečná odpověď je proto platná
    /// odpověď: jedno nedostupné PR nemá položit rozhlídku po zbytku.
    ///
    /// **Chybějící spojení se počítá jako nula, ne jako nedostupné.** Prázdné spojení GitHub
    /// vrací s `totalCount: 0`; `null` znamená, že pole v odpovědi nebylo — a nula je u počtu
    /// příspěvků bezpečná strana: `Policy.snoozeBaseline` z ní udělá nejvýš nižší základ, takže
    /// odložení trvá dál. Opačná volba (nula jako „přišel komentář“) neexistuje, protože se
    /// porovnává `>`.
    func signals(of ids: [PRIdentifier]) -> [PRIdentifier: SnoozeSignal] {
        guard let data else { return [:] }
        var signals: [PRIdentifier: SnoozeSignal] = [:]
        for (index, id) in ids.enumerated() {
            guard let node = data[SnoozeProbeQuery.alias(index)]??.pullRequest else { continue }
            signals[id] = SnoozeSignal(
                head: node.headRefOid,
                comments: (node.comments?.totalCount ?? 0) + (node.reviews?.totalCount ?? 0)
            )
        }
        return signals
    }
}
