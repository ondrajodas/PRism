import Foundation

extension Policy {
    /// Varování v liště nad diffem — celá věta, sražená podoba a nápověda (#593).
    ///
    /// Do #593 se věta skládala ve view a sražená podoba neexistovala: v tísni se z varování
    /// nestalo nic, protože měla `fixedSize()` a přetékala za hranu lišty. Tady stojí obě podoby
    /// vedle sebe, takže se dá **vyčerpat výčtem**, co se zkrácením ztratí — a ukázat, že se to
    /// ztratit nedá: co ubude z lišty, **musí** být v nápovědě.
    struct DiffToolbarWarning: Equatable, Sendable {
        /// Věta, jak se kreslí, když je místa dost.
        let full: String
        /// Co zbude v tísni. **Číslo v tom zůstává** — je to jediné, co se z varování počítá.
        let short: String
        /// Nápověda. Nese **celou** větu, aby sražená podoba nic nezatajila.
        let help: String
    }

    /// Řádky diffu, které se nepodařilo přečíst.
    ///
    /// `nil` = nic se hlásit nemá. Prázdné varování by v liště zabíralo místo tvrzením „nic“.
    static func unreadableLinesWarning(_ count: Int) -> DiffToolbarWarning? {
        guard count > 0 else { return nil }
        let subject = Plural.czech(count, one: "řádek", few: "řádky", many: "řádků")
        return DiffToolbarWarning(
            full: "\(subject) diffu se nepodařilo přečíst",
            short: subject,
            help: "\(subject) diffu se nepodařilo přečíst, takže v něm nejsou vidět. "
                + "Celý diff má PR na GitHubu."
        )
    }

    /// Vlákna konverzace, která se nevešla do stránky z GitHubu.
    static func missingThreadsWarning(_ count: Int) -> DiffToolbarWarning? {
        guard count > 0 else { return nil }
        // Sloveso je **v tvarech**: „2 vlákna se nevešlo“ je špatně česky.
        let sentence = Plural.czech(
            count,
            one: "vlákno konverzace se nevešlo",
            few: "vlákna konverzace se nevešla",
            many: "vláken konverzace se nevešlo"
        )
        return DiffToolbarWarning(
            full: "\(sentence) — otevři PR na GitHubu",
            short: Plural.czech(count, one: "vlákno", few: "vlákna", many: "vláken"),
            help: "\(sentence) do stránky z GitHubu, takže je aplikace nekreslí. "
                + "Celou konverzaci má PR na GitHubu."
        )
    }

    /// Kolik znaků se vejde na stranu (#188) — hlásí se **jedině tehdy, když je slib porušený**.
    ///
    /// Nad `promisedCharactersPerSide` je to číslo, které nikoho nezajímá, kdežto pod ním je to
    /// jediné vysvětlení, proč se řádky lámou. `characters` se počítá z **měřeného** okna
    /// (`charactersPerSide`), ne z tabulky ze zadání.
    static func diffWidthWarning(characters: Int, contentWidth: Double) -> DiffToolbarWarning? {
        guard contentWidth > 0, characters < promisedCharactersPerSide else { return nil }
        return DiffToolbarWarning(
            full: "\(characters) znaků na stranu",
            short: "\(characters) znaků",
            help: "Aplikace slibuje \(promisedCharactersPerSide) znaků na stranu, tady se jich "
                + "vejde \(characters). Pomůže složit sloupce nebo přepnout na pohled pod sebou."
        )
    }
}
