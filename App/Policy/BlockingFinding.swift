import Foundation

extension Policy {
    /// Kategorie, které samy o sobě blokují. Konstanta; do konfigurace se přesune s #23.
    ///
    /// Je to **jediný knoflík**, kterým se dolaďuje, co se považuje za vážné — právě proto,
    /// aby se kvůli tomu nemusely přepisovat skilly.
    static let defaultBlockingCategories: Set<String> = ["correctness", "security", "data-loss"]

    /// Blokuje nález?
    ///
    /// Jediný odvozený boolean nad nálezy. Aplikace si **nevymýšlí vlastní škálu
    /// závažnosti** — `ReportFindings` pole pro severitu nemá, takže se používá to, co
    /// v datech je: `verdict` (jak si reviewer stojí) a `category` (druh problému).
    ///
    /// `PLAUSIBLE` neblokuje schválně: je to nález „možná“, a zastavit na něm PR by
    /// znamenalo, že se blokující příznak přestane brát vážně.
    static func isBlocking(
        _ finding: Finding,
        categories: Set<String> = defaultBlockingCategories
    ) -> Bool {
        guard finding.verdict == .confirmed, let category = finding.category else { return false }
        let wanted = normalized(category: category)
        // Sada je `Set`, tak se nejdřív zeptáme jako `Setu`. To sedne na default i na
        // cokoli rozumného z konfigurace; teprve když ne, platí se za porovnání bez ohledu
        // na velikost písmen.
        return categories.contains(wanted) || categories.contains { normalized(category: $0) == wanted }
    }

    /// Kolik z platných nálezů záznamu blokuje.
    ///
    /// Počítají se **platné** (`activeFindings`), tedy bez odmítnutých (#113) — blokující
    /// nález, kterému nevěřím, není důvod k vyrušení ani k červenému řádku.
    ///
    /// Bydlí to **tady, u `isBlocking`**, ne u toho, kdo se ptá: od #172 se na to ptají dvě
    /// místa (notifikace a řádek seznamu) a druhá kopie by znamenala, že banner a seznam umí
    /// napočítat každý něco jiného.
    static func blockingCount(
        in record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> Int {
        record.activeFindings.count { isBlocking($0, categories: categories) }
    }

    /// Kategorie se porovnávají bez ohledu na velikost písmen.
    ///
    /// Reviewer je píše jako volný slug, takže `Data-Loss` a `data-loss` znamenají totéž —
    /// a kdyby se lišily, PR s hlášenou ztrátou dat by tiše neblokoval nic.
    static func normalized(category: String) -> String {
        category.lowercased()
    }
}
