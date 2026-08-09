import Foundation

/// Co se dá dělat s rozepsaným komentářem pod PR (#216). Jeden parametr místo čtyř closures,
/// které patří k sobě — stejný vzor jako `ThreadActions` a `DraftActions`.
///
/// Že je to **volitelný** parametr `ConversationView`, není jen pohodlí pro náhledy: composer
/// bez cesty ven by byl pole, do kterého se dá psát a nic se s tím nedá udělat. Kde se
/// odesílat nedá vůbec (chybí `gh`), se nekreslí; kde se nesmí (repo mimo `PublishScope`),
/// zůstane s vyplněným `block`.
struct ConversationComposer {
    /// Rozepsaný text, jak ho zná store.
    var text: String = ""
    var setText: (String) -> Void = { _ in }
    /// Odešle rozepsaný komentář. Text si bere store, ne tenhle volající — aby se nemohlo
    /// odeslat něco jiného, než co je vidět. Tatáž úvaha jako u `ThreadActions.send`.
    var send: () -> Void = {}
    /// Co se právě děje. `nil` = nic.
    var state: CommentActionState?

    /// Proč se odesílat nedá. `nil` = dá se. Tlačítko se kvůli tomu **neschovává**, zůstane
    /// zakázané s tímhle důvodem v nápovědě.
    var block: String?
}
