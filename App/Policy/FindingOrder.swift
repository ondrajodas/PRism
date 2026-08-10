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
    /// Kritéria odshora: odmítnuté naspod, pak blokující kategorie, kategorie abecedně,
    /// uvnitř `CONFIRMED` nad `PLAUSIBLE` a nakonec podle `file:line`.
    ///
    /// Blokující kategorie nahoře je jediné místo, kde se odvozený příznak promítá do
    /// řazení — žádná nová škála z toho nevzniká, jen se nejdůležitější věc nemusí hledat.
    /// Poslední kritérium je `summary`, aby bylo pořadí **úplné**: bez něj by dva nálezy
    /// stejného druhu na stejném řádku přeskakovaly mezi překresleními. Porovnává se
    /// obyčejně, ne podle jazyka — je to rozhodčí na shody, ne řazení, které někdo čte.
    ///
    /// Odmítnuté (#113) jdou **naspod, ne pryč**: v tabulce zabírají jeden ztlumený řádek,
    /// takže nekonkurují platným, a přesto je vidět, co jsem odmítl. Je to první kritérium,
    /// protože i odmítnutý blokující nález má ustoupit platnému stylistickému.
    static func sorted(
        _ findings: [Finding],
        categories: Set<String> = defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [Finding] {
        let blocking = Set(categories.map(normalized(category:)))
        // Klíč se skládá **jednou na nález**, ne při každém porovnání: staví se z něj řetězce
        // (`lowercased()` u kategorie a od #113 celý `Policy.key(of:)`), takže v komparátoru
        // by se tatáž práce udělala log n krát.
        return findings
            .map { (finding: $0, key: sortKey(of: $0, blocking: blocking, dismissals: dismissals)) }
            .sorted { $0.key < $1.key }
            .map(\.finding)
    }

    /// Nález, kterým se začíná — první v `sorted`, tedy ten nahoře v panelu (#200).
    ///
    /// **Žádná nová škála závažnosti z toho nevzniká**: rozhodují tatáž kritéria, podle kterých
    /// se nálezy kreslí, takže notifikace ukáže přesně to, co je po otevření okna první na ráně.
    /// Druhé pravidlo pro „nejzávažnější“ by znamenalo, že banner a panel ukazují každý něco
    /// jiného — tatáž úvaha jako u `blockingCount`, který proto bydlí u `isBlocking`.
    ///
    /// Počítá se z **platných** nálezů, takže odmítnutý (#113) se do notifikace nedostane ani
    /// tehdy, když by jinak byl první. Řadí se celý seznam kvůli jedné položce schválně:
    /// komparátor je privátní (a má být, je to jedno pravidlo), a tohle se počítá jednou za
    /// doběhlé review, ne při každém překreslení.
    static func mostSevereFinding(
        in record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> Finding? {
        sorted(record.activeFindings, categories: categories).first
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
    ///
    /// Jmenuje se `sortKey`, ne `key`: `Policy.key(of:)` je **identita nálezu** napříč běhy
    /// (#113), tohle jsou kritéria řazení. Dvě různé věci se stejným jménem se pletou —
    /// tatáž úvaha jako u tří „review“ v modelech.
    private static func sortKey(
        of finding: Finding,
        blocking: Set<String>,
        dismissals: [FindingKey: FindingDismissal]
    ) -> SortKey {
        let category = finding.category.map(normalized(category:))

        return SortKey(
            dismissedRank: dismissals[key(of: finding)] == nil ? 0 : 1,
            // Chybějící hodnoty jdou dozadu, a proto pořadí, ne příznak: `Bool` v Swiftu
            // není `Comparable` a možnosti jsou tři, ne dvě.
            categoryRank: category.map { blocking.contains($0) ? 0 : 1 } ?? 2,
            category: category ?? "",
            verdictRank: finding.verdict == .confirmed ? 0 : 1,
            fileRank: finding.file == nil ? 1 : 0,
            file: finding.file ?? "",
            line: finding.line ?? Int.max,
            summary: finding.summary
        )
    }

    /// Kritéria řazení v pořadí důležitosti.
    ///
    /// Vlastní typ, ne n-tice: těch je porovnatelných jen šest prvků a hlavně by kritéria
    /// neměla jména — u osmi hodnot v závorce se pak dá pořadí přehodit, aniž si toho
    /// někdo všimne.
    private struct SortKey: Comparable {
        let dismissedRank: Int
        let categoryRank: Int
        let category: String
        let verdictRank: Int
        let fileRank: Int
        let file: String
        let line: Int
        let summary: String

        static func < (left: SortKey, right: SortKey) -> Bool {
            if left.dismissedRank != right.dismissedRank { return left.dismissedRank < right.dismissedRank }
            if left.categoryRank != right.categoryRank { return left.categoryRank < right.categoryRank }
            if left.category != right.category { return left.category < right.category }
            if left.verdictRank != right.verdictRank { return left.verdictRank < right.verdictRank }
            if left.fileRank != right.fileRank { return left.fileRank < right.fileRank }
            if left.file != right.file { return left.file < right.file }
            if left.line != right.line { return left.line < right.line }
            return left.summary < right.summary
        }
    }
}
