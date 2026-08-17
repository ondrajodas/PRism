import Foundation

/// Zdroj pull requestů — jeden pojmenovaný search dotaz.
///
/// Sledování PR je od začátku **seznam** zdrojů, i když v1 má jediný. Týmové review
/// requesty nebo repo, které chci hlídat celé, jsou pak nová položka konfigurace, ne
/// zásah do logiky. Proto slučování a deduplikace existují dřív, než je co slučovat.
struct Source: Hashable, Codable, Sendable {
    /// Jméno pro UI — v konfiguraci a u řádku, odkud PR přišel.
    ///
    /// `var`, protože zdroje se dají editovat v okně nastavení. Neplyne z toho, že by se
    /// měnily za běhu jinde — mění je jen ten editor.
    var name: String
    /// Search dotaz ve tvaru, kterému rozumí GitHub (`gh search prs`).
    var query: String

    /// Jediný zdroj, se kterým aplikace startuje.
    ///
    /// `is:open` tam je schválně: bez něj `gh search prs` vrací i zavřené a mergnuté PR
    /// a fronta k review by se plnila věcmi, se kterými se nedá nic dělat.
    static let reviewRequested = Source(
        name: "Vyžádaná review",
        query: "review-requested:@me is:open"
    )

    /// Vlastní pull requesty (#330) — druhá polovina toho, co je v okně vidět.
    ///
    /// `is:open` ze stejného důvodu jako u `reviewRequested`: bez něj `gh search prs` vrací
    /// i zavřené a mergnuté.
    ///
    /// **`author:@me`, ne vypsaný login.** Dotaz vyhodnocuje GitHub podle tokenu, kterým se `gh`
    /// přihlásil, takže zdroj funguje hned — nečeká na `fetchViewer()` a nerozbije se tomu, kdo
    /// se přihlásí jiným účtem. Rozřazení hotového seznamu je proti tomu věc **autora**
    /// (`Policy.ownership`), ne zdroje: jeden PR umí splňovat víc dotazů naráz.
    static let mine = Source(name: "Moje PR", query: "author:@me is:open")
}
