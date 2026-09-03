import Foundation

extension Policy {
    /// Jak dopadlo review přírůstku — kolik starých nálezů trvá, kolik je nových (#517).
    ///
    /// **Počítá se z nálezů záznamu, ne z uložených čísel**, a je to tatáž úvaha jako u
    /// `RecheckTally`: odmítnutý nález (#113) z okna zmizí, takže by uložený počet tvrdil
    /// „3 staré trvají“ nad dvěma nálezy.
    struct IncrementalTally: Equatable, Sendable {
        let range: IncrementalDiffRange
        /// Kolik nálezů si běh přinesl z minula (po odmítnutích).
        let carried: Int
        let stillApplies: Int
        let resolved: Int
        let unclear: Int
        /// Přenesené nálezy, ke kterým se běh nevyjádřil. **Vlastní číslo, ne nula**: bez něj by
        /// z pěti starých nálezů vypadalo, že se probraly všechny.
        let unanswered: Int
        /// Dostal běh staré nálezy vůbec k posouzení? `false` = **nezeptali jsme se** (materiál se
        /// nepodařilo uložit), ne „neodpověděl“ — a v okně je z toho jiná věta, protože jedna
        /// z nich tvrdí něco o modelu a druhá o nás.
        let askedForVerdicts: Bool
        /// Nálezy, které běh nahlásil **v přírůstku** — tedy to nové.
        let new: Int
        /// Co stál celý běh z prvního kola. `nil` = nevíme.
        let wholeUsage: RunUsage?
    }

    /// Souhrn přírůstkového běhu jednoho revieweera. `nil` = běžel nad celým diffem.
    ///
    /// - Parameter record: záznam, ve kterém ten běh leží — kvůli odmítnutím, která jsou na něm.
    static func incrementalTally(
        of run: StoredReviewRun,
        in record: ReviewRecord
    ) -> IncrementalTally? {
        guard let increment = run.increment else { return nil }
        var carried = 0
        var stillApplies = 0
        var resolved = 0
        var unclear = 0
        var answered = 0
        var new = 0

        for finding in run.findings where record.dismissal(of: finding) == nil {
            guard finding.carriedFrom != nil else {
                new += 1
                continue
            }
            carried += 1
            // Klíč se skládá **jednou na nález**: je to řetězec a tohle běží při kreslení tabu
            // (#224) — tatáž úvaha jako v `Policy.recheck`.
            guard let status = increment.statuses[key(of: finding)] else { continue }
            answered += 1
            switch status.verdict {
            case .stillApplies: stillApplies += 1
            case .resolved: resolved += 1
            case .unclear: unclear += 1
            }
        }

        return IncrementalTally(
            range: IncrementalDiffRange(seen: increment.fromHeadSha, head: record.headSha),
            carried: carried,
            stillApplies: stillApplies,
            resolved: resolved,
            unclear: unclear,
            // Rozdíl, ne druhý průchod — jako u `RecheckTally`.
            unanswered: carried - answered,
            askedForVerdicts: increment.askedForVerdicts,
            new: new,
            wholeUsage: increment.wholeUsage
        )
    }

    /// Odznaky, které se smí ukázat u nálezů — **z obou zdrojů, na jednom místě** (#150, #517).
    ///
    /// Verdikt o nálezu umí od #517 přinést dvojí běh: kontrola nálezů (uložená u nálezů starší
    /// hlavy, `StoredRecheck`) a přírůstkové review (uložené u běhu na dnešní hlavě). Odznak
    /// v okně je přitom jeden, takže by dvě čtení znamenala, že se u nálezu ukáže jedno a ve větě
    /// nad diffem druhé.
    ///
    /// **Platnost drží tvrdá podmínka č. 5 v obou případech, jen se ptá jiné sha.** U kontroly je
    /// to `againstHeadSha` (hlava, proti které běžela), u přírůstku `record.headSha` (hlava, na
    /// které ten běh běžel a na kterou jsou přenesené nálezy přepsané). Jak se hlava PR posune,
    /// odznaky zhasnou — schovat je potichu by znamenalo tvrdit „vyřešeno“ nad commity, které
    /// nikdo neviděl.
    ///
    /// - Parameter head: hlava PR, jak ji známe **teď**. `nil` (nenačtený detail) = žádné odznaky.
    static func findingStatuses(
        of record: ReviewRecord?,
        head: String?
    ) -> [FindingKey: RecheckStatus] {
        guard let record else { return [:] }
        var statuses = recheck(of: record, head: head).statuses
        guard let head, record.headSha == head else { return statuses }
        for run in record.runs {
            guard let increment = run.increment else { continue }
            // Klíč nese revieweera (`Policy.key(of:)`), takže se dva běhy nemají čím přebít.
            // `uniquingKeysWith` tu přesto být musí — `merge` bez něj padá, a pád v kreslení
            // tabu je horší než verdikt, který přišel jako druhý.
            statuses.merge(increment.statuses) { _, second in second }
        }
        return statuses
    }
}
