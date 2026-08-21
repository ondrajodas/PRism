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
    /// Dvě podmínky: **doběhl** (spadlá ani zabitá session o čistotě kódu nevypovídá) a **není
    /// pro co ho zpochybnit** — a to druhé rozhoduje `inconclusiveReason(of:)`, aby to bylo na
    /// jednom místě. Do #383 tady stály tři podmínky vypsané, jenže tutéž dvojici si skládal
    /// i chip revieweera a díl proužku v řádku, tedy tři kopie jednoho pravidla.
    static func isConclusive(_ run: StoredReviewRun) -> Bool {
        run.outcome == .finished && inconclusiveReason(of: run) == nil
    }

    /// Proč se z **tohohle** běhu čistota tvrdit nedá. `nil` = dá se (nebo o ní běh nemluví).
    ///
    /// **Jediné místo, kde se ta otázka rozhoduje** (#383) — čte ho `isConclusive`, chip
    /// revieweera i díl proužku u řádku. Do #383 měl každý z těch tří vlastní `if` a lišily se:
    /// chip se ptal nejdřív na hlášení, řádek na ztracené nálezy, a čtení kódu nekontroloval
    /// nikdo.
    ///
    /// Pořadí uvnitř: **ztracený nález, chybějící hlášení, nepřečtený kód.** První dvě se
    /// v jednom běhu vylučují (ztratit se dá jen to, co dorazilo hlášením), takže je to pořadí
    /// spíš pro čitelnost než pro rozhodování.
    ///
    /// **Běh, který něco našel, se na čtení kódu neptá.** Nálezy mluví samy za sebe: buď se
    /// reviewer do kódu podíval, nebo ne, ale o čistotě netvrdí nic — a odmítnout kvůli tomu
    /// návrh verdiktu (`approve` nad neblokujícími nálezy) by byl poplach nad výsledkem, který
    /// je v okně celý vidět.
    static func inconclusiveReason(of run: StoredReviewRun) -> InconclusiveReason? {
        if run.droppedFindings > 0 { return .droppedFindings }
        if !run.calledReportFindings { return .noReport }
        guard run.findings.isEmpty else { return nil }
        return codeReading(of: run) == .unread ? .unreadCode : nil
    }

    /// Proč se z celého záznamu čistota tvrdit nedá — důvod, který se objeví v odznaku (#383).
    ///
    /// Volá se jedině tam, kde `suggestedVerdict` neřekl `approve`. V takovém záznamu **musí**
    /// aspoň jeden doběhlý běh důvod mít, jinak by byl průkazný; kdyby ho přesto neměl žádný,
    /// zbývá `noReport` — z těch tří tvrzení to nejslabší, takže nedomyšlený stav nevyrobí
    /// obvinění, které data neunesou.
    static func inconclusiveReason(for record: ReviewRecord) -> InconclusiveReason {
        let reasons = Set(record.runs.compactMap(inconclusiveReason(of:)))
        return InconclusiveReason.byPrecedence.first(where: reasons.contains) ?? .noReport
    }
}
