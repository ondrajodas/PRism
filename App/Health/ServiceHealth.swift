import Foundation

/// Puntík u jedné služby ve stavovém řádku.
///
/// **Pět případů, ne tři.** „Nezjištěno“ není „nefunguje“ (jinak by po startu svítilo, že
/// je všechno mimo) a „stroj je bez sítě“ není „služba je mimo“ (to je otázka, na kterou
/// řádek existuje). Slévat chybové stavy zakazuje `CLAUDE.md` a tady je to o důvod víc:
/// každý z nich vede k jinému dalšímu kroku.
enum ServiceHealth: Sendable, Equatable, CaseIterable {
    /// ○ Zatím neproběhlo žádné volání a stav služby se nezjistil.
    case unknown
    /// ● Poslední volání prošlo a žádná sledovaná komponenta nehlásí problém.
    case operational
    /// ● Sledovaná komponenta hlásí problém — i když volání zatím procházejí.
    case incident
    /// ● Poslední skutečné volání selhalo.
    case failing
    /// ● Stroj je bez sítě. Červený jako `failing`, ale vlastní důvod.
    case offline

    /// Jedno slovo do nápovědy. Nikdy prázdné — puntík bez popisu je dekorace.
    var label: String {
        switch self {
        case .unknown: "nezjištěno"
        case .operational: "funguje"
        case .incident: "hlášený problém"
        case .failing: "nefunguje"
        case .offline: "bez sítě"
        }
    }
}
