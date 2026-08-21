import Foundation

/// Proč se z doběhlého review **čistota tvrdit nedá** (#383).
///
/// Tři různá tvrzení, která v datech vypadají stejně — prázdná tabulka nálezů — a v UI znamenají
/// každé něco jiného. Do #383 se všechna tři kreslila jako `ReviewState.failed`, tedy jako
/// `selhalo`: nepravda, protože session doběhla `success`. A druhá strana téhož je horší:
/// `security-review` po 17. 8. hlásil nulu nálezů ve 12 ze 14 běhů a okno z toho kreslilo
/// `čisté`, protože počet nálezů byl nula a `ReportFindings` dorazilo.
///
/// **Nejde o počet nálezů, ale o to, jestli je z čeho soudit.** Proto je to vlastní typ a ne
/// text: podle důvodu se liší odznak, věta v tabu i notifikace, a texty ze tří míst by se
/// rozešly.
enum InconclusiveReason: String, Hashable, Codable, Sendable, CaseIterable {
    /// Reviewer nahlásil nález, ze kterého se nepodařilo přečíst povinné pole.
    ///
    /// Nejkonkrétnější z těch tří: **víme, že něco bylo**, a víme, že to nemáme.
    case droppedFindings
    /// `ReportFindings` se nezavolalo vůbec — nálezy se neměly kde vzít.
    case noReport
    /// Reviewer neotevřel ani jeden soubor z pracovní kopie (#383).
    ///
    /// Rozhoduje o tom `Policy.codeReading(of:)` z uložené osy, ne cena ani doba běhu — proč
    /// zrovna tak, je napsané tam.
    case unreadCode

    /// V jakém pořadí důvody přebíjejí jeden druhý, když se v jednom záznamu sejde víc běhů.
    ///
    /// Odshora od nejkonkrétnějšího: ztracený nález je fakt o **nálezu**, chybějící hlášení
    /// fakt o **výsledku** běhu a nepřečtený kód fakt o **jeho průběhu**. Vyhrává to, co se dá
    /// tvrdit nejadresněji — z „část nálezů se ztratila“ se pozná, co dělat, kdežto
    /// „nepřečetl kód“ je nad tímtéž během pravda taky, jen řekne méně.
    ///
    /// Je to **výčet, ne `allCases`**: pořadí případů v deklaraci je věc čitelnosti a nemá se
    /// stát skrytým pravidlem. Že jsou tu všechny, drží test.
    static let byPrecedence: [InconclusiveReason] = [.droppedFindings, .noReport, .unreadCode]
}
