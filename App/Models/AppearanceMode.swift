import Foundation

/// Jaký vzhled má okno mít (#278).
///
/// Do #278 se vzhled řídil **jen** systémem a nedal se přebít. Přepínač vznikl proto, že diff
/// se v obou režimech čte jinak (#277) a přehazovat kvůli jednomu PR celý systém je
/// nepřiměřené — chtěl jsem porovnat obojí nad tímtéž diffem.
///
/// **Volí režim, ne barvy.** Barvy zůstávají v `Palette` a vybírá je dynamický `NSColor`
/// podle vzhledu, ve kterém se zrovna kreslí; tenhle typ jen říká, který vzhled to je. Kdo by
/// kvůli přepínači začal někde větvit `if isDark`, obchází paletu.
///
/// Jména hodnot (`light`, `dark`, `system`) jsou schválně tatáž, jakými mluví návrh: mockup má
/// vedle `@media (prefers-color-scheme: dark)` i `:root[data-theme="dark"]` a jeho hostitel
/// přepíná mezi `light`, `dark` a `system`. Vynucený tmavý má v návrhu **stejné tokeny** jako
/// systémový tmavý, takže „tmavý“ znamená v aplikaci i v návrhu totéž.
enum AppearanceMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// Světlý, ať si systém myslí co chce.
    case light
    /// Tmavý, ať si systém myslí co chce.
    case dark
    /// Podle systému — **výchozí**, tedy chování před #278.
    case system

    /// Jak se režim jmenuje v okně nastavení.
    ///
    /// Vedle `rawValue` schválně, stejně jako u `DiffLayout` nebo `FindingsLanguage`: v souboru
    /// je anglický klíč, v okně česká věta a dvě místa by se rozešla.
    var displayName: String {
        switch self {
        case .light: "Světlý"
        case .dark: "Tmavý"
        case .system: "Podle systému"
        }
    }
}
