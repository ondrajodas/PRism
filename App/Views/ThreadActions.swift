import Foundation

/// Co se dá dělat s vláknem konverzace. Jeden parametr místo sedmi closures, které patří
/// k sobě — stejný vzor jako `DraftActions` a `DiffExpansionActions`.
///
/// Rozbalení tady bydlí spolu s odpovídáním schválně: do #73 se posílalo zvlášť, ale je to
/// tentýž předmět (jedno vlákno) a tentýž důvod, proč stav nežije ve view — bublina je buňka
/// líného seznamu, kterou odscrollování zahodí.
///
/// Výchozí hodnoty jsou prázdné, aby se bubliny daly postavit i bez store (testy skládání
/// řádků, náhledy).
struct ThreadActions {
    /// Je vlákno rozbalené? Rozhoduje store: výchozí stav se odvozuje z vlákna a překliknutí
    /// se drží jako odchylka (`Policy.isThreadExpanded`).
    var isExpanded: (ReviewThread) -> Bool = { _ in true }
    var toggle: (ReviewThread) -> Void = { _ in }

    /// Rozepsaná odpověď, jak ji zná store.
    var reply: (ReviewThread) -> String = { _ in "" }
    var setReply: (ReviewThread, String) -> Void = { _, _ in }
    /// Odešle rozepsanou odpověď. Text si bere store, ne tenhle volající — aby se nemohlo
    /// odeslat něco jiného, než co je vidět.
    var send: (ReviewThread) -> Void = { _ in }
    var setResolved: (ReviewThread, Bool) -> Void = { _, _ in }
    /// Co se s vláknem právě děje. `nil` = nic.
    var state: (ReviewThread) -> ThreadActionState? = { _ in nil }

    /// Vzít vlákno **do zadání pro agenta** (#528) — na vlastním PR, u vlákna s návrhem změny.
    ///
    /// `nil` znamená, že se tlačítko **nekreslí vůbec**, ne zašedle: na cizím PR se návrh jen
    /// čte, protože aplikovat ho je věc autora. Zašedlé tlačítko tvrdí „tady se to dělá, jen
    /// teď ne“ — a na cizím PR se to nedělá nikdy (tatáž úvaha jako u `+ label` v panelu, #392).
    ///
    /// **Není to cesta ven.** Otevře panel se zadáním; aplikovat návrh je zápis do repozitáře
    /// a ten jde přes agenta a `git push` se sheetem (#466), ne přes tohle tlačítko.
    var handoff: ((ReviewThread) -> Void)?

    /// Proč se odesílat nedá. `nil` = dá se.
    ///
    /// Je to stav, ne akce, ale patří k `send` stejně jako `DraftActions.sendBlock` k odeslání
    /// review: tlačítko se kvůli tomu **neschovává**, zůstane zakázané s tímhle důvodem
    /// v nápovědě. Mlčky zmizelé tlačítko vypadá jako rozbitá aplikace.
    var block: String?
}
