import Foundation

/// Můj odeslaný komentář u řádku diffu — to, co v druhém kole čtu znovu (#522).
///
/// **Není to nález a není to `ThreadComment`.** Nález je věta revieweera o kódu, `ThreadComment`
/// je jeden příspěvek v konverzaci; tohle je **vlákno, které jsem založil**, zúžené na kotvu a na
/// text, kterým se ptám. Tři skoro stejné typy by znamenaly tři místa, kde se dá zapomenout, že
/// „moje“ se pozná z `Conversation.viewer`, a ne z příznaku na komentáři.
///
/// Drží se **první komentář vlákna**, ne celé vlákno: otázka do promptu zní „co jsem napsal“,
/// a odpovědi ostatních jsou druhá osa, která se čte z dat (viz `Policy.replies(of:head:in:)`).
struct SentComment: Hashable, Sendable {
    /// Identita vlákna z GitHubu. **Klíč, pod kterým se ukládá verdikt** — je stálý napříč koly,
    /// kdežto text se mezi koly mění (proto se páruje přes index, viz `RecheckCommand`).
    let threadID: String
    /// Soubor, u kterého vlákno visí.
    let path: String
    /// Řádek. `nil` = kotva zmizela (vlákno zastaralo) — `ReviewThread.anchorLine` v tom případě
    /// nabízí původní číslo, a právě to se sem dosazuje.
    let line: Int?
    /// Text, kterým jsem se ptal — tělo prvního komentáře vlákna.
    let body: String
}
