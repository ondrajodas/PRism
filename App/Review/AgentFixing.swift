import Foundation

/// Jeden běh agenta, který opravuje **vlastní** PR podle cizí zpětné vazby (#510).
struct AgentFixRequest: Sendable, Equatable {
    let pullRequest: PRIdentifier
    /// Celý prompt. Skládá ho `Policy.agentFixPrompt` — runner text neskládá, jinak by existovalo
    /// druhé místo, kde se do promptu dá sáhnout (tatáž úmluva jako u konfliktů, #467).
    let prompt: String
    /// Strom `-sync` toho pull requestu. **Zároveň rozsah, na který se omezí `Write` a `Edit`**
    /// (`AgentFixCommand.allowedTools(in:)`) — proto tady není `URL?`: session bez stromu by měla
    /// povolení bez rozsahu, tedy zápis kamkoli.
    let worktree: URL
    let timeout: Duration

    init(
        pullRequest: PRIdentifier,
        prompt: String,
        worktree: URL,
        timeout: Duration = AgentFixCommand.timeout
    ) {
        self.pullRequest = pullRequest
        self.prompt = prompt
        self.worktree = worktree
        self.timeout = timeout
    }
}

/// Co se v běhu právě děje — podklad pro větu v panelu (#510).
enum AgentFixProgress: Sendable, Equatable {
    /// Session naběhla. **Bez `session_id`**: běhy na sebe nenavazují (`--resume` tady není),
    /// takže by to byl stav, který nikdo nečte.
    case started
    /// Session si řekla o nástroj. **Pokus, ne použití** — odmítnutý zápis je tu taky, a je to
    /// zrovna ten, kvůli kterému se to čte.
    case attemptedTool(ToolAttempt)
}

typealias AgentFixProgressHandler = @Sendable (AgentFixProgress) -> Void

/// Session, která opraví vlastní PR po cizím review (#510) — **druhá, která smí měnit soubory**,
/// a **první, kterou aplikace pouští bez kliknutí**.
///
/// **Sada povolení se tím nemění ani o položku**: bere tutéž, co slévání konfliktů
/// (`AgentFixCommand.allowedTools(in:)` je `ConflictCommand.allowedTools(in:)`), tedy `Write`
/// a `Edit` s vypsaným rozsahem stromu v cache, bez `Bash`e, s `gh` a `git push` v zákazu. Co je
/// na #510 nové, je **spouštěč**, ne to, co session smí — a proto se rozšiřuje tvrdá podmínka
/// č. 2 o větu, ne o řádek v tabulce sad.
///
/// Za protokolem ze stejného důvodu jako `ConflictResolving`: v testech se nahradí fakem a **z
/// typu je vidět, co to umí**. Jedna metoda, která bere běh a vrací účet; není tu nic, čím by se
/// dalo commitnout, pushnout nebo odeslat na GitHub — commituje **aplikace**
/// (`RepoCheckout.commitAgentFix`) a do remote píše jedině `BranchPushing`, po potvrzení.
/// Tvrdá podmínka č. 1 se tím tedy nemění.
///
/// **Selhání session není chyba volání**, jako u revieweera a u konfliktů: spadlá i vytimeoutovaná
/// session se vrací jako `AgentFixAnswer` s vyplněným `failure`, protože je to výsledek, který se
/// ukazuje. Vyhodí se jen `CancellationError`.
protocol AgentFixing: Sendable {
    func fix(
        _ request: AgentFixRequest,
        progress: @escaping AgentFixProgressHandler
    ) async throws -> AgentFixAnswer
}

extension AgentFixing {
    func fix(_ request: AgentFixRequest) async throws -> AgentFixAnswer {
        try await fix(request, progress: { _ in })
    }
}
