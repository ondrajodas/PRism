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
    /// Poměr po částech — **od nejhoršího** a jen to, čeho je aspoň jeden. Nula v souhrnu je
    /// slovo navíc, ze kterého nic neplyne.
    ///
    /// Po částech, ne jednou větou, kvůli **chipu v hlavičce**: ten ukazuje jen tu první, tedy
    /// nejhorší stav, protože v úzké hlavičce má cenu právě ta. Kdyby si ji skládal sám, rozešel
    /// by se s tabem ve skloňování.
    ///
    /// Do #215 to byl `[Part]` s příznakem `isFailure`, protože souhrn v `Přehledu` spadlou část
    /// obarvoval. Souhrn z `Přehledu` odešel celý, takže příznak neměl čtenáře — a stav, který se
    /// drží a nikdo ho nečte, je mrtvá váha, která svádí spolehnout se na ni.
    static func parts(of summary: ChecksSummary) -> [String] {
        var parts: [String] = []
        if summary.failed > 0 {
            parts.append(Plural.czech(summary.failed, one: "selhala", few: "selhaly", many: "selhalo"))
        }
        if summary.running > 0 { parts.append("\(summary.running) běží") }
        if summary.passed > 0 {
            parts.append(Plural.czech(summary.passed, one: "prošla", few: "prošly", many: "prošlo"))
        }
        if summary.skipped > 0 { parts.append("\(summary.skipped) přeskočeno") }
        return parts
    }

    /// `1 selhala · 2 běží · 12 prošlo · 22 přeskočeno` — poměr na jeden řádek.
    static func summary(of summary: ChecksSummary) -> String {
        parts(of: summary).joined(separator: " · ")
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
