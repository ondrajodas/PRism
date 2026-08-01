import Foundation

/// Nálezy jedné kategorie — jak je ukazuje UI.
struct FindingSection: Hashable, Sendable {
    /// `nil` u nálezů, které kategorii neuvedly. Je to platný stav, ne chyba.
    let category: String?
    let findings: [Finding]
}

extension Policy {
    /// Pořadí nálezů pro UI.
    ///
    /// Kritéria odshora: blokující kategorie první, pak kategorie abecedně, uvnitř
    /// `CONFIRMED` nad `PLAUSIBLE` a nakonec podle `file:line`.
    ///
    /// Blokující kategorie nahoře je jediné místo, kde se odvozený příznak promítá do
    /// řazení — žádná nová škála z toho nevzniká, jen se nejdůležitější věc nemusí hledat.
    /// Poslední kritérium je `summary`, aby bylo pořadí **úplné**: bez něj by dva nálezy
    /// stejného druhu na stejném řádku přeskakovaly mezi překresleními. Porovnává se
    /// obyčejně, ne podle jazyka — je to rozhodčí na shody, ne řazení, které někdo čte.
    static func sorted(
        _ findings: [Finding],
        categories: Set<String> = defaultBlockingCategories
    ) -> [Finding] {
        let blocking = Set(categories.map(normalized(category:)))
        return findings.sorted { key(of: $0, blocking: blocking) < key(of: $1, blocking: blocking) }
    }

    /// Nálezy po kategoriích, ve stejném pořadí jako `sorted`.
    ///
    /// Skupiny jsou podle `category`, tedy podle pojmenování od reviewera — aplikace si
    /// druhy problémů nevymýšlí. Porovnávají se bez ohledu na velikost písmen, aby
    /// `Correctness` a `correctness` nebyly dvě sekce téhož.
    static func sections(
        _ findings: [Finding],
        categories: Set<String> = defaultBlockingCategories
    ) -> [FindingSection] {
        var sections: [FindingSection] = []

        for finding in sorted(findings, categories: categories) {
            let category = finding.category.map(normalized(category:))
            if let last = sections.last, last.category == category {
                sections[sections.count - 1] = FindingSection(
                    category: category,
                    findings: last.findings + [finding]
                )
            } else {
                sections.append(FindingSection(category: category, findings: [finding]))
            }
        }
        return sections
    }

    /// Klíč řazení. Pole jsou v pořadí důležitosti a všechna jsou porovnatelná, takže se
    /// řazení dá napsat jedním porovnáním n-tice.
    ///
    /// Chybějící hodnoty jdou dozadu (`nil` kategorie i `nil` soubor), protože nálezy bez
    /// místa patří do tabulky pod bublinami, ne mezi ně.
    ///
    /// První kritérium je vlastnost **kategorie**, ne nálezu: kdyby se řadilo podle
    /// `isBlocking`, rozpadla by se kategorie, ve které je `CONFIRMED` i `PLAUSIBLE`, na
    /// dvě sekce se stejným názvem.
    /// Pořadí je v číslech, ne v příznacích: `Bool` v Swiftu **není `Comparable`**, takže
    /// n-tice s ním se porovnat nedá. Čísla zároveň unesou tři možnosti (blokující kategorie,
    /// obyčejná, žádná) na jednom místě místo dvou příznaků za sebou.
    private static func key(
        of finding: Finding,
        blocking: Set<String>
    ) -> (Int, String, Int, String, Int, String) {
        let category = finding.category.map(normalized(category:))
        let categoryRank =
            switch category {
            case .some(let name) where blocking.contains(name): 0
            case .some: 1
            case .none: 2
            }

        return (
            categoryRank,
            category ?? "",
            finding.verdict == .confirmed ? 0 : 1,
            finding.file ?? "",
            finding.line ?? Int.max,
            finding.summary
        )
    }
}
