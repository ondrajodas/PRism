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

        // Nálezy se berou ze **všech** běhů, i ze spadlých a vytimeoutovaných. Selhal
        // *běh*, ne nález: ten dorazil jako celý `ReportFindings` call a rozbité nálezy
        // parser dovnitř nepustí. Filtrovat je podle stavu běhu by znamenalo, že spadlý
        // reviewer s nahlášenou ztrátou dat vedle jednoho čistého běhu vyjde jako
        // `approve` — tedy přesně ta chyba, které se tenhle typ vyhýbá.
        //
        // Odmítnuté (#113) se nepočítají — a `isBlocking` se kvůli tomu **nemění**: blokující
        // je vlastnost nálezu a kategorie, kdežto „tomuhle nálezu nevěřím“ je můj názor nad
        // celým záznamem. Proto se filtruje tady a přes `activeFindings`, tedy tou samou
        // cestou jako v řádku seznamu.
        if record.activeFindings.contains(where: { isBlocking($0, categories: categories) }) {
            return .requestChanges
        }

        // Zahozený nález **kdekoli** v záznamu bere approve celému PR, ne jen svému běhu.
        // Víme, že reviewer něco hlásil a aplikace to nepřečetla — a čistý výsledek jiného
        // skillu o tom ztraceném nálezu nic neříká. Je to známá neznámá, tedy přesně ten
        // stav, ze kterého se nemá soudit.
        //
        // **Odmítnutím se to nespraví**, ať je odmítnuto cokoli: odmítnutí mluví o nálezu,
        // který znám, ne o tom, který se nepřečetl. Proto je tahle brána za filtrem výš.
        guard record.runs.allSatisfy({ $0.droppedFindings == 0 }) else { return nil }

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
