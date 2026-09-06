import Foundation

/// Účet session, která opravila vlastní PR (#510).
///
/// **Dvě různá tvrzení a nesmí se slít**, jako u `ConflictResolution`: `files` a `summary` jsou
/// **text od modelu**, tedy to, co si session myslí, že udělala; co z toho doopravdy vzniklo,
/// vydává `git` — commit a jeho diff v potvrzení force pushe. Panel proto účet ukazuje jako
/// **shrnutí agenta**, ne jako výsledek měření.
struct AgentFixAnswer: Sendable, Hashable {
    /// Soubory, o kterých session tvrdí, že je změnila. Prázdné = neřekla nic, co by šlo přečíst;
    /// **neznamená to „nic nezměnila“** — o tom rozhoduje `git status` v `RepoCheckoutu`.
    var files: [String] = []
    /// Jedna česká věta o tom, co se opravilo. `nil` = session neřekla nic.
    var summary: String?
    /// Co session **nechala být** a proč (zadání #510: „ať se přizná“). `nil` = nic takového
    /// nehlásí.
    var skipped: String?
    var usage: RunUsage?
    /// Věta pro okno, když session nedoběhla. `nil` = doběhla.
    var failure: String?
    /// **Cesty, do kterých session psala mimo svůj pracovní strom.**
    ///
    /// Prázdné je normální stav — brána v `--allowedTools` je změřená (viz `ConflictCommand`)
    /// a takový pokus odmítne. Je to **druhá vrstva**: kdyby se ta brána někdy změnila, pozná se
    /// to tady a výsledek se **nepřijme**, místo aby se potichu commitl. Počítají se **i odmítnuté
    /// pokusy**: otázka není „povedlo se to“, ale „mířila session mimo strom“.
    var writesOutside: [String] = []
}
