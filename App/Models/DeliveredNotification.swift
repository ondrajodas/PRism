import Foundation

/// Poslední notifikace, která se doopravdy doručila (#138).
///
/// Je z ní vidět, že notifikace **fungují**: „nic nepřišlo, protože nic nebylo“ se od „nic
/// nepřišlo, protože je něco rozbité“ jinak odlišit nedá. Že je zakázalo oprávnění, řekne
/// hláška ve stavovém řádku (#88), ale to je jen jedna z příčin mlčení.
///
/// **Není `Codable`**, jako `Release` nebo `ReviewVerdict`: drží se v paměti do konce běhu.
/// Odpovídá na otázku „funguje mi to teď“, a k té je čas z minulého spuštění zavádějící —
/// puntíky služeb se po restartu počítají znovu ze stejného důvodu.
///
/// Čas a titulek jdou spolu jako jedna hodnota, ne dvě vlastnosti storu: čas bez toho, čeho se
/// týkal, se v nápovědě nedá vysvětlit, a dvě vlastnosti se dají rozejít.
struct DeliveredNotification: Hashable, Sendable {
    let at: Date
    /// Titulek doručené notifikace — nápověda z něj řekne, čeho se to týkalo.
    let title: String
}
