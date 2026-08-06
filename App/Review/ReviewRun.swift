import Foundation

/// Výsledek jednoho běhu review.
struct ReviewRun: Sendable, Equatable {
    let key: ReviewRunKey
    /// Co vypadlo ze streamu — nálezy, session id, pokusy o nástroje, počty nepřečteného.
    let summary: StreamSummary
    let outcome: ReviewRunOutcome
    /// Překlady nálezů do jazyka z nastavení, **zarovnané se `summary.findings`**. Prázdné,
    /// dokud se nepřekládalo; `nil` na místě znamená nález, který se přeložit nepodařilo.
    ///
    /// Sedí tady, ne v `StreamSummary`: ta je obrazem toho, co reviewer poslal, a překlad
    /// vzniká až po něm.
    var translations: [FindingTranslation?] = []

    /// Nálezy doplněné o to, co ví jen aplikace: **kdo** je našel, **proti čemu** a jak se
    /// jejich texty čtou v nastaveném jazyce.
    var findings: [Finding] {
        summary.findings.enumerated().map { index, reported in
            Finding(
                reported: reported,
                reviewer: key.skillID,
                headSha: key.headSha,
                // Kratší pole překladů nesmí nález zahodit — `indices.contains` je tu
                // proto, že o délce rozhoduje odpověď modelu, ne náš kód.
                translation: translations.indices.contains(index) ? translations[index] : nil
            )
        }
    }

    var sessionID: String? { summary.sessionID }
}

/// Jak běh skončil.
///
/// `finished` **není** totéž co „něco našel“: doběhlá session bez nálezů je čisté review,
/// ne selhání. Rozlišit se to musí tady, protože výš už to nikdo nepozná — a schválený PR
/// s neohlášenou chybou je nejdražší chyba, kterou tahle aplikace umí udělat.
enum ReviewRunOutcome: Sendable, Hashable, Codable {
    /// Proces doběhl s nulovým návratovým kódem.
    case finished
    /// Nedoběhl v limitu a byl zabit. Nálezy, které do té doby dorazily, jsou v `summary`.
    case timedOut
    /// Nespustil se nebo skončil nenulovým kódem; `detail` je stderr, na kterém stojí UI.
    case failed(detail: String)
    /// Skončil s aplikací — pád, `kill`, restart Macu — a nálezy se dotáhly z transcriptu (#97).
    ///
    /// **Vlastní případ, ne `timedOut`.** Oba znamenají „nedoběhlo, částečné nálezy zůstaly“,
    /// ale vedou jinam: timeout říká, že je review moc pomalé (dá se zvednout limit), tohle že
    /// spadla aplikace (nedá se dělat nic než pustit znovu). A odznak v řádku by u přerušeného
    /// běhu tvrdil „timeout“, což je nepravda — přesně ten vzor, na který si `CLAUDE.md`
    /// stěžuje.
    case interrupted
}
