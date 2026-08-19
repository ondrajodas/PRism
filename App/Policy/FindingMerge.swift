import Foundation

extension Policy {
    /// Sloučí **jednu sadu** nálezů z volání `ReportFindings` do toho, co dorazilo dřív (#381).
    ///
    /// Rozhoduje **struktura volání, ne text**: každé volání `ReportFindings` je celá sada, tedy
    /// poslední slovo revieweera. Pozdější sada proto na daném místě přepíše, co tam bylo —
    /// a je to jediné, čím se **korekce** dá odlišit od **druhého problému na tomtéž řádku**.
    /// Z obsahu to nejde: měřeno na skutečném běhu (#381) se dvě položky lišily jen
    /// přeformulovaným `summary` (`fáze` → `fázi`), zatímco reviewer ve svém logu hlásil jeden
    /// nález. Do #381 se porovnávalo `(file, line, summary)`, takže korekce prošla jako nový
    /// nález a v bublině ležel týž nález dvakrát.
    ///
    /// Tři vlastnosti, které z toho plynou a mají se držet:
    ///
    /// - **Uvnitř jedné sady se nic neslévá.** Dvě položky na jednom řádku v jednom volání jsou
    ///   dva problémy, protože je reviewer vyjmenoval vedle sebe — a je to doložené reálným
    ///   během (`review-with-findings` má dva nálezy na `Cart.swift:17`). Slití podle
    ///   `(file, line, category)` by z nich udělalo jeden, a to potichu.
    /// - **Nic se nezahodí potichu.** Nález z dřívější sady, o kterém pozdější sada mlčí,
    ///   **zůstane** — a to i tehdy, když pozdější sada nese na tom místě méně položek, než
    ///   kolik jich tam bylo. Ztracený blokující nález vypadá v okně jako „reviewer nic
    ///   nenašel“, kdežto nález navíc je vidět a dá se odmítnout (#113). Vychází z toho i to,
    ///   že **prázdná** pozdější sada nesmaže nic — nemá totiž místo, ke kterému by mlčení
    ///   patřilo.
    /// - **Nález bez místa se řídí jako dřív**, tedy podle `summary`. „Stejný soubor bez řádku“
    ///   není místo (tatáž úvaha jako u `Policy.groups(of:)`), takže by párování podle místa
    ///   dvě různé poznámky k architektuře slilo do jedné.
    ///
    /// Není to identita z `Policy.key(of:)` a **nemá být**: klíč odmítnutí páruje nálezy
    /// *napříč běhy*, kde se struktura volání nedochová, takže by tam místo samo odmítlo
    /// i nález, který jsem nikdy neviděl. Ceny těch dvou omylů jsou obrácené — chyba tady
    /// znamená duplikát v okně, chyba tam znamená skrytý nález.
    static func mergedFindings(
        _ collected: [ReportedFinding],
        reporting reported: [ReportedFinding]
    ) -> [ReportedFinding] {
        var unused = Array(reported.indices)
        var merged: [ReportedFinding] = []

        for finding in collected {
            // Pořadí se drží podle **dřívější** sady: nález, který se jen opravil, nemá
            // v okně poskočit jinam.
            guard let slot = unused.firstIndex(where: { isSameFinding(reported[$0], finding) }) else {
                merged.append(finding)
                continue
            }
            merged.append(reported[unused.remove(at: slot)])
        }

        return merged + unused.map { reported[$0] }
    }

    /// Týž nález ve dvou sadách? **Místo**, a u nálezu bez místa `summary`.
    private static func isSameFinding(_ left: ReportedFinding, _ right: ReportedFinding) -> Bool {
        if let mine = place(of: left), let theirs = place(of: right) { return mine == theirs }
        // Nález bez místa (chybějící testy, poznámka k architektuře) — přesně to porovnání,
        // které tu bylo do #381; pro něj se nic nemění, protože `file` i `line` jsou u obou
        // prázdné. Zároveň to drží, že nález **s** místem se s nálezem **bez** místa nespáruje.
        return left.file == right.file && left.line == right.line && left.summary == right.summary
    }

    /// Místo v kódu. Vyžaduje **obojí** — soubor bez řádku není místo, viz `Policy.groups(of:)`.
    private static func place(of finding: ReportedFinding) -> FindingPlace? {
        guard let file = finding.file, let line = finding.line else { return nil }
        return FindingPlace(file: file, line: line)
    }

    private struct FindingPlace: Equatable {
        let file: String
        let line: Int
    }
}
