import Foundation

extension Policy {
    /// Návrh verdiktu nad výsledky jednoho PR.
    ///
    /// Mechanický, žádná agregační session: je-li mezi nálezy blokující → `requestChanges`,
    /// jinak `approve`. Zajímavé je, kdy **nevznikne nic**.
    ///
    /// `nil` znamená „není z čeho soudit“ a je to vlastní odpověď, ne opatrné `approve`.
    /// Schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou tahle aplikace umí
    /// udělat — a od `clean` se to nedá odlišit ničím jiným než tímhle rozlišením.
    static func suggestedVerdict(
        for record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> ReviewVerdict? {
        // Zastaralý záznam patří ke commitu, který už v PR není. Verdikt z něj by mluvil
        // o kódu, který neexistuje.
        guard !record.isStale else { return nil }

        // Nález z vytimeoutovaného běhu je pořád nález — session se nedopočítala, ale co
        // stihla nahlásit, platí.
        if record.findings.contains(where: { isBlocking($0, categories: categories) }) {
            return .requestChanges
        }

        return record.runs.contains(where: isConclusive) ? .approve : nil
    }

    /// Dá se z běhu vyvodit, že je čisto?
    ///
    /// Tři podmínky, každá kvůli jinému způsobu, jak se dá „nic jsem nenašel“ splést
    /// s „nemám co říct“:
    ///
    /// - **doběhl** — spadlá ani zabitá session o čistotě kódu nevypovídá,
    /// - **zavolal `ReportFindings`** — bez toho se nálezy neměly kde vzít (typicky proto,
    ///   že nástroj chyběl v `--allowedTools`),
    /// - **nic nezahodil** — nález bez povinného pole znamená, že reviewer něco hlásil
    ///   a aplikace to nepřečetla.
    static func isConclusive(_ run: StoredReviewRun) -> Bool {
        run.outcome == .finished && run.calledReportFindings && run.droppedFindings == 0
    }
}
