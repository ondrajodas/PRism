import Foundation

/// Commit, který po agentovi zůstal v kopii repa, **i s tím, co v něm je** (#511).
///
/// **Čte se z `gitu` v cache, ne z GitHubu**, a to je celý důvod, proč tenhle typ existuje: ten
/// commit **nikde jinde není**. Do #511 se dal prohlédnout jedině tak, že se potvrdil force push
/// a přečetl se na GitHubu — tedy až za nevratnou akcí. Tohle je ten krok před ní.
///
/// **Autor a datum se čtou, nevymýšlejí.** Commit dělá aplikace (`RepoCheckout.commitAgentFix`)
/// pod gitovou identitou toho, kdo u stroje sedí, a hlavička rozkliknutého commitu (#317) autora
/// kreslí. Dosadit sem „agent“ by znamenalo napsat do okna něco, co v repu nestojí.
struct AgentFixCommit: Equatable, Sendable {
    let sha: String
    /// Celá zpráva. Skládá ji `Policy.agentFixCommitMessage`, takže je určená daty — ale čte se
    /// **z commitu**, ne z té funkce: kdyby se ty dvě rozešly, má pravdu repozitář.
    let message: String
    let authorName: String
    /// `nil` = datum se nepodařilo přečíst. Hlavička si s tím poradí; vymyslet ho nesmíme.
    let committedAt: Date?
    /// `git diff <hlava PR>..<commit agenta>` — syrový text, parsuje ho `DiffParser`, jako
    /// všechno ostatní.
    ///
    /// **Prázdný je platná odpověď, ne porucha.** `commitAgentFix` sice commituje jedině nad
    /// změněným stromem, ale mezi commitem a prohlédnutím může být libovolně dlouhá pauza —
    /// a `Policy.commitDiffTab` na prázdný diff už větu má.
    let diff: String
}
