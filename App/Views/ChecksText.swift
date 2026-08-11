import SwiftUI

/// Texty a barvy checků (#215) — jedno místo pro tab `Kontroly`, souhrn v `Přehledu`
/// a chip v hlavičce PR.
///
/// Vzniklo rozdělením bloku na tab a souhrn: do #215 měl každý z těch tří kusů okna vlastní
/// kopii, a už tehdy se rozešly — blok kreslil `.green` a `.red` ze systému, chip
/// `Palette.ok` a `Palette.crit` z palety návrhu, takže dvě zelené v jednom okně znamenaly
/// jednu věc. Se třemi kopiemi by se to rozešlo znovu.
///
/// **Není to `Policy`**: vrací text a barvu, tedy kreslení, ne rozhodnutí. To, co se
/// rozhoduje — nejhorší stav, počty, odznak — je v `ChecksSummary` a `Policy.checksBadge`.
enum ChecksText {
    /// Jedna položka poměru — `1 selhala`, `2 běží`, …
    ///
    /// Vlastní typ, ne `String`: v `Přehledu` se spadlá část **obarvuje** (návrh, sekce 02),
    /// takže se poměr musí dát složit po částech. Jinak by ho `Přehled` psal sám a rozešel by
    /// se s tabem v pořadí i ve skloňování.
    struct Part: Hashable {
        let text: String
        /// Mluví o spadlých? Podle toho se v `Přehledu` obarvuje.
        let isFailure: Bool
    }

    /// Poměr po částech — jen to, čeho je aspoň jeden. Nula v souhrnu je slovo navíc, ze
    /// kterého nic neplyne.
    ///
    /// **Spadlé jsou první**, i v `Přehledu`, kde je návrh kreslí poslední. Je to vědomá
    /// odchylka: dvě různá pořadí téhož poměru se čtou jako dva různé údaje, a zvýraznění
    /// v `Přehledu` nese barva, ne pozice.
    static func parts(of summary: ChecksSummary) -> [Part] {
        var parts: [Part] = []
        if summary.failed > 0 {
            parts.append(Part(
                text: Plural.czech(summary.failed, one: "selhala", few: "selhaly", many: "selhalo"),
                isFailure: true
            ))
        }
        if summary.running > 0 { parts.append(Part(text: "\(summary.running) běží", isFailure: false)) }
        if summary.passed > 0 {
            parts.append(Part(
                text: Plural.czech(summary.passed, one: "prošla", few: "prošly", many: "prošlo"),
                isFailure: false
            ))
        }
        if summary.skipped > 0 {
            parts.append(Part(text: "\(summary.skipped) přeskočeno", isFailure: false))
        }
        return parts
    }

    /// `1 selhala · 2 běží · 12 prošlo · 22 přeskočeno` — poměr na jeden řádek.
    static func summary(of summary: ChecksSummary) -> String {
        parts(of: summary).map(\.text).joined(separator: " · ")
    }

    /// Co je za jménem checku: jak dopadl a jak dlouho běžel.
    static func detail(of check: PullRequestCheck) -> String {
        let state = switch check.outcome {
        case .passed: "prošlo"
        case .failed: "selhalo"
        case .running: "běží"
        case .skipped: "přeskočeno"
        case .cancelled: "zrušeno"
        }
        guard let duration = check.duration else { return state }
        return "\(state) · \(RunUsageText.duration(.seconds(duration)))"
    }

    /// Ikona v řádku seznamu. **Bez kolečka**, na rozdíl od chipu v hlavičce: ten stojí v řadě
    /// dalších kapslí, kde obtažený symbol drží tvar, kdežto v seznamu je vedle sebe pět stejných
    /// koleček a rozdíl se z nich čte hůř.
    static func symbol(of outcome: PullRequestCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark"
        case .failed: "xmark"
        case .running: "circle.dashed"
        case .skipped: "minus"
        case .cancelled: "slash.circle"
        }
    }

    /// Tatáž škála jako všude jinde v okně: červená se musí řešit teď, fialová běží, zelená je
    /// v pořádku, šedá nic netvrdí.
    ///
    /// **Z palety návrhu, ne systémová** (`.green`/`.red`): checky stojí v jedné řadě s kapslí
    /// stavu PR i s odznaky nálezů, a dvě různé zelené vedle sebe vypadají jako dva různé významy.
    static func color(of outcome: PullRequestCheck.Outcome) -> Color {
        switch outcome {
        case .passed: Palette.ok
        case .failed, .cancelled: Palette.crit
        case .running: Palette.accent
        case .skipped: Palette.ink3
        }
    }
}
