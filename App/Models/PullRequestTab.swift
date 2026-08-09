import Foundation

/// Který tab pull requestu je vidět — jako na GitHubu.
///
/// Je to **volba pohledu**, ne údaj o PR, a přesto nežije ve view: `PullRequestDetailView` si
/// SwiftUI mezi pull requesty ponechá (stejná pozice ve stromu), takže `@State` by přetekl
/// z jednoho PR na druhý. Drží se proto per PR ve `AppStore`, stejně jako výběr řádku.
///
/// Jako `ReviewVerdict` **není `Codable`** — neukládá se. Kdyby se ukládal, znamenalo by to
/// pamatovat si napříč restarty, na co se člověk koukal minulý týden.
enum PullRequestTab: Hashable, Sendable, CaseIterable {
    /// Popis PR a konverzace, která se neváže k žádnému řádku. **Výchozí** — viz `standard`.
    case overview
    /// Diff s bublinami.
    case filesChanged
    /// Časová osa toho, co se na PR dělo (#183).
    ///
    /// **Vlastní tab, ne sekce v `Přehledu`.** Jsou to dvě různé otázky: `Přehled` odpovídá na
    /// „jak to teď stojí“ (popis, fakta, co se změnilo od minule), konverzace na „co se dělo“.
    /// V jednom scrollu se přitom to druhé čte tak, že se přes první přeroluje.
    case conversation

    /// Se kterým tabem se PR otevírá.
    ///
    /// **Změna proti zadání #72**, které předepisovalo `filesChanged` s tím, že kvůli diffu je
    /// aplikace otevřená. Vyžádané při zkoušení a je to správně: popis PR a diskuze je to, co
    /// se čte **než** se člověk podívá na kód — a stejně to má GitHub, kde je `Overview`
    /// vstupní tab. Diff je jedno kliknutí daleko a volba se pamatuje per PR.
    static let standard = PullRequestTab.overview

    /// Jak se tab jmenuje v okně.
    ///
    /// Česky, jako zbytek UI — anglické `Files changed` by bylo jediné anglické místo v okně.
    /// „Soubory“ samo by se přitom pletlo se stromem souborů v liště diffu, takže je z názvu
    /// vidět, že jde o **změny**.
    var czechLabel: String {
        switch self {
        case .overview: "Přehled"
        case .filesChanged: "Změněné soubory"
        case .conversation: "Konverzace"
        }
    }
}
