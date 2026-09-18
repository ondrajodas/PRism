import Foundation

/// Jedno **moje** odeslané tělo review — vzorek hlasu pro osmou session (#521).
///
/// **Je to můj text, ne cizí obsah**, a proto to není `SubmittedReview`: ten je hotové rozhodnutí
/// z GitHubu se stavem, autorem a `id` (viz jeho dokumentace). Tady zůstává jedině to, co se dá
/// použít jako vzorek: **kdy** jsem to napsal a **co** v tom stálo. Autor v tom není schválně —
/// do ledgeru se nic cizího nedostane, takže pole „čí to je“ by mohlo tvrdit jedinou hodnotu.
///
/// `id` je `SubmittedReview.id`, a je to **jediný důvod, proč se drží**: totéž review přijde
/// v konverzaci pokaždé, když se PR otevře, a bez identity by se vzorek ukládal znovu a znovu, až
/// by z desítky posledních zbyla jedna věta v deseti kopiích.
struct ReviewVoiceSample: Codable, Hashable, Sendable, Identifiable {
    let id: String
    /// Kdy jsem review odeslal. Řadí se podle toho, takže *posledních deset* znamená deset
    /// nejnovějších, ne deset naposled viděných.
    let at: Date
    /// Próza review, jak odešla na GitHub.
    let body: String
}
