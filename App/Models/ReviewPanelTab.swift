import Foundation

/// Co je vidět v panelu vpravo od diffu.
///
/// **Dva taby, ne tři** (#242): `Průběh` se odstěhoval do vlastní záložky PR, protože se u kódu
/// nečte a u spadlé session se do 300 bodů nevešel ani důvod, ani konec logu. Nálezy v panelu
/// **zůstávají** — tab `Nálezy` je druhý pohled na tu samou věc (tabulka přes celé okno), ne
/// přesun; u kódu se hledá „co je tady“, v tabulce „co všechno se našlo“.
///
/// Dva jsou **na jednom PR**, ne v celém výčtu (#333). Který z `draft` a `agentPrompt` se kreslí,
/// rozhoduje `Policy.reviewPanelTabs(for:)` podle toho, čí PR to je: na cizím se sbírá verdikt, na
/// vlastním zadání pro agenta — a `APPROVE` ani `REQUEST_CHANGES` na vlastní PR GitHub nepustí
/// (změřeno u #62), takže verdikt tam nemá co dělat. Nikdy nejsou vidět oba.
///
/// Jako `PullRequestTab` **není `Codable`** — neukládá se. Pamatovat si napříč restarty, co jsem
/// měl v panelu minulý týden, k ničemu není.
enum ReviewPanelTab: Hashable, Sendable, CaseIterable {
    case findings
    /// Rozdělané review — tělo, verdikt a řádkové komentáře. Jen na cizím PR.
    case draft
    /// Zadání pro agenta (#333) — z nálezů a konverzace se skládá text k předání. Jen na vlastním.
    case agentPrompt
}
