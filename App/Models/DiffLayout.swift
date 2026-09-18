import Foundation

/// Jak se kreslí diff — pod sebou, nebo vedle sebe.
///
/// Uzavřený výčet ze stejného důvodu jako `FindingsLanguage`: hodnota jde do **českého
/// popisku v okně** a do rozhodnutí ve view, takže volný řetězec by neuměl ani jedno.
///
/// Je to nastavení **člověka, ne repa** — proto žije jen v `GlobalConfig` a `RepositoryConfig`
/// ho nemá. Jak se čte diff, se u konkrétního repozitáře nedá odůvodnit.
enum DiffLayout: String, CaseIterable, Codable, Hashable, Sendable {
    /// Dnešní pohled: odebrané a přidané řádky pod sebou, obě čísla vlevo.
    case unified
    /// Starý obsah vlevo, nový vpravo, spárovaný po řádcích.
    case split

    /// Jak se pohled jmenuje v okně — v nastavení i v liště nad diffem.
    var displayName: String {
        switch self {
        case .unified: "Pod sebou"
        case .split: "Vedle sebe"
        }
    }

    /// Ikona do segmentovaného přepínače v liště diffu.
    ///
    /// Jméno symbolu je tu vedle `displayName` schválně: obojí pojmenovává tentýž pohled
    /// pro uživatele a dvě místa by se rozešla. Precedens je `FindingsLanguage.displayName`.
    var symbol: String {
        switch self {
        case .unified: "rectangle.grid.1x2"
        case .split: "rectangle.split.2x1"
        }
    }

    /// Nápověda u segmentu v liště. Stojí **u každého segmentu zvlášť**, ne u celého přepínače:
    /// od #593 se přepínač v tísni srazí na samotné ikony, a pak je nápověda jediné, co jméno
    /// pohledu nese (`Policy.diffToolbarFloor(.layout)`).
    var help: String {
        switch self {
        case .unified: "Pod sebou — odebrané a přidané řádky v jednom sloupci"
        case .split: "Vedle sebe — starý obsah vlevo, nový vpravo"
        }
    }
}
