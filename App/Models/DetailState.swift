import Foundation

/// Stav dotažení detailu jednoho PR. Co v mapě store není, se ještě nenačítalo.
///
/// Stejný tvar jako `DiffState` a `ConversationState`, ze stejného důvodu: razítko
/// `updatedAt` se drží **u dat**, ne vedle nich.
///
/// Proč se detail vůbec drží: `headSha` z vyhledávání nevyleze (`gh search prs` ho neumí,
/// viz #4) a rozdělané review musí vědět, proti kterému commitu je psané — jinak se nedá
/// ani označit za zastaralé, ani odeslat. Polling ho netahat nesmí (N+1), takže se dotahuje
/// při výběru řádku jako diff a konverzace.
///
/// Drží se **celý `PullRequest`**, i když se z něj zatím čte jen `headSha`. Je to snímek
/// jedné odpovědi gateway, ne odvozený stav: vytáhnout z něj jedno pole znamená, že si
/// odesílání (#68) musí stav PR dotáhnout podruhé, a druhý dotaz na totéž se s tímhle umí
/// rozejít. Stejný důvod, proč `DiffState` drží `Diff` a ne jen počet souborů.
enum DetailState: Equatable, Sendable {
    case loading
    case loaded(PullRequest, updatedAt: Date)
    case failed(String)
}
