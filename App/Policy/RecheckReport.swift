import Foundation

extension Policy {
    /// Spáruje odpovědi kontroly s nálezy, na které se ptala (#150).
    ///
    /// Index je `id` z otázky, klíč skládá **`Policy.key(of:)`** — tedy tatáž funkce, kterou se
    /// klíčují odmítnutí. Druhé místo, kde by se klíč skládal, znamená tiché rozpárování: klíč je
    /// změřený proti přeformulovanému `short_summary` i proti překladu a kopie by o tom nevěděla.
    ///
    /// Párování jde **přes index, ne přes text**: kdyby se hledal nález podle věty, kterou model
    /// opíše, stačilo by jedno přeformulování a verdikt by spadl mimo. Index nese aplikace na obou
    /// stranách, takže se nemá čím rozejít.
    static func recheckStatuses(
        _ answers: [Int: RecheckStatus],
        of findings: [Finding]
    ) -> [FindingKey: RecheckStatus] {
        var statuses: [FindingKey: RecheckStatus] = [:]
        for (index, status) in answers {
            guard findings.indices.contains(index) else { continue }
            statuses[key(of: findings[index])] = status
        }
        return statuses
    }

    /// Co o uložených nálezech říká poslední kontrola (#150).
    ///
    /// **Kontrola platí jen pro hlavu, proti které běžela** (tvrdá podmínka č. 5). Jak se hlava
    /// posune, odznaky u nálezů zmizí a zbyde věta o tom, že se dá pustit znovu — schovat je
    /// potichu by znamenalo tvrdit „vyřešeno“ nad commity, které kontrola nikdy neviděla.
    ///
    /// - Parameter head: hlava PR, jak ji známe **teď**. `nil` (detail se nenačetl) vyjde jako
    ///   `outdated`: platnost, kterou nemáme čím potvrdit, se u odznaků nepředpokládá. Věta
    ///   z toho stavu se přitom nekreslí — `StaleHeadView` se bez známé hlavy neukazuje vůbec.
    static func recheck(of record: ReviewRecord?, head: String?) -> RecheckReport {
        guard let record, let recheck = record.recheck else { return .none }
        guard let head, recheck.againstHeadSha == head else {
            return .outdated(againstHeadSha: recheck.againstHeadSha)
        }
        return .current(tally(of: recheck, in: record))
    }

    /// Počty se sázejí z **platných** nálezů záznamu, ne z uložených odpovědí.
    ///
    /// Odmítnutý nález (#113) zmizí z okna, takže se nesmí počítat ani sem — jinak by věta nad
    /// diffem tvrdila „3 z 5“ nad čtyřmi nálezy. A nález, na který kontrola neodpověděla, se
    /// počítá do `unanswered`: „nevyjádřila se“ je vlastní odpověď a bez ní by z pěti nálezů
    /// vypadalo, že se probraly všechny.
    private static func tally(of recheck: StoredRecheck, in record: ReviewRecord) -> RecheckTally {
        var statuses: [FindingKey: RecheckStatus] = [:]
        var resolved = 0
        var stillApplies = 0
        var unclear = 0
        var findings = 0

        for finding in record.activeFindings {
            findings += 1
            // Klíč se skládá **jednou na nález**: je to řetězec a tohle běží při kreslení
            // hlavičky (#224). Nálezem Copilota na #271; tentýž vzor byl v bublině nálezu.
            let key = key(of: finding)
            guard let status = recheck.statuses[key] else { continue }
            statuses[key] = status
            switch status.verdict {
            case .resolved: resolved += 1
            case .stillApplies: stillApplies += 1
            case .unclear: unclear += 1
            }
        }

        return RecheckTally(
            statuses: statuses,
            resolved: resolved,
            stillApplies: stillApplies,
            unclear: unclear,
            // Rozdíl, ne druhý průchod. Dva platné nálezy s týmž klíčem by se do `statuses`
            // slily a číslo by vyšlo o jeden vyšší — jsou to ale různé věty od téhož revieweera
            // na tomtéž řádku, které `StreamParser` slučuje už při sběru, takže se to nestává.
            unanswered: findings - statuses.count,
            outcome: recheck.outcome,
            finishedAt: recheck.finishedAt
        )
    }

    /// Stav kontroly nálezů, jak se ukazuje v okně (#150).
    enum RecheckReport: Equatable, Sendable {
        /// Neběžela.
        case none
        /// Běžela proti jinému commitu, než na kterém PR stojí teď.
        case outdated(againstHeadSha: String)
        /// Platí pro hlavu, kterou PR má teď.
        case current(RecheckTally)

        /// Stavy, které se smí ukázat u nálezů — **jen z platné kontroly**. Prázdná mapa je to,
        /// co odznaky zháší, jakmile se hlava posune.
        var statuses: [FindingKey: RecheckStatus] {
            guard case .current(let tally) = self else { return [:] }
            return tally.statuses
        }
    }

    /// Kolik nálezů kontrola prošla a jak.
    struct RecheckTally: Equatable, Sendable {
        let statuses: [FindingKey: RecheckStatus]
        let resolved: Int
        let stillApplies: Int
        let unclear: Int
        /// Platné nálezy, ke kterým se kontrola nevyjádřila.
        let unanswered: Int
        /// Jak běh skončil. `timedOut`, `failed` a `interrupted` se v okně **nesmí** slít
        /// s doběhlým: kontrola, která spadla po dvou odpovědích, nemluví za zbytek.
        let outcome: ReviewRunOutcome
        let finishedAt: Date

        /// Na kolik nálezů odpověď je.
        var answered: Int { resolved + stillApplies + unclear }
    }
}
