import Foundation

/// Co aplikace navrhuje udělat s PR.
///
/// **Návrh, ne akce.** Tvrdá podmínka: na GitHub se nikdy nic neposílá, takže tohle je
/// text v okně, ze kterého se ručně opíše rozhodnutí.
///
/// Neukládá se — odvozuje se z uložených nálezů, takže `Codable` by popisoval tvar, který
/// na disku nikdy není. Proto tu jako jediný z modelů chybí.
enum ReviewVerdict: Hashable, Sendable {
    case approve
    case requestChanges
}
