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

    /// Jak se režim jmenuje v okně.
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

    /// Ikona v railu — **jedna na režim**, protože z ní se pozná, co platí.
    ///
    /// Tlačítko v railu klikem cykluje a popisek u sebe nemá, takže ikona je jediné místo, kde je
    /// stav vidět bez hoveru. Vybrané jsou obrysové varianty, ne plné: rail má obrysové i ostatní
    /// ikony (`square.grid.2x2`, `tray.full`, `square.and.pencil`), takže plná by v pruhu ztěžkla.
    /// `a.circle` je „auto“ — kolečko s písmenem, tedy tvar, který se v té velikosti nepřečte jako
    /// slunce ani měsíc.
    ///
    /// **Návrh to od #299 kreslí stejně** — v railu je kolečko s „A“, tedy výchozí automat, a
    /// poznámka u sekce 01 popisuje cyklení. Do té doby to byla vědomá odchylka (mockup měl jedno
    /// půlkolečko bez ohledu na stav); vyžádal si ji uživatel a důvod je v záznamu rozhodnutí.
    var railSymbol: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "a.circle"
        }
    }

    /// Kam klik v railu povede.
    ///
    /// Pořadí je **světlý → tmavý → podle systému → světlý**: jde od nejsvětlejšího k nejtmavšímu
    /// a automat je až za nimi, protože není třetí stupeň jasu, ale odpověď „rozhodni ty“. Tři
    /// klikáním dosažitelné stavy znamenají, že se z každého dostaneš do každého nejvýš dvěma
    /// kliknutími, takže na pořadí nezáleží kvůli rychlosti, ale kvůli tomu, aby bylo **předvídatelné**.
    var next: AppearanceMode {
        switch self {
        case .light: .dark
        case .dark: .system
        case .system: .light
        }
    }
}
