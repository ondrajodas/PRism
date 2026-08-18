import Foundation

/// Co se dá dělat se zadáním pro agenta (#333). Jeden parametr místo tří closures, které patří
/// k sobě — stejný vzor jako `DraftActions`.
///
/// **Není tu nic, co by odesílalo.** `compose` otevře sheet s textem; do schránky a do souboru se
/// sahá až tam, a nikam dál (tvrdá podmínka č. 1).
///
/// Výchozí hodnoty jsou prázdné, aby se panel dal postavit i bez storu — pro náhledy a sondy.
struct AgentPromptActions {
    var toggle: (AgentPromptChoice) -> Void = { _ in }
    var isEnabled: (AgentPromptChoice) -> Bool = { _ in false }
    var compose: () -> Void = {}
    /// Zadání jen z toho, co po předání přibylo v diskuzi (#334) — `Sestavit i tak (jen nové
    /// vlákno)`. Vlastní akce, ne příznak u `compose`: skládá se z jiného materiálu, takže by
    /// jeden uzávěr se `Bool`em znamenal dvě různá zadání pod jedním jménem.
    var composeFresh: () -> Void = {}
    /// Pustit review znovu po pushi (#334). Je to **tlačítko, ne automat** — vlastních PR se
    /// automat netýká vůbec (#332), protože na nich se pushuje často.
    var runReview: () -> Void = {}
}
