import Foundation

/// Jedno kolo slévání konfliktů (#467).
struct ConflictRequest: Sendable, Equatable {
    let pullRequest: PRIdentifier
    /// Celý prompt. Skládá ho `Policy.conflictPrompt` — runner text neskládá, jinak by existovalo
    /// druhé místo, kde se do promptu dá sáhnout (tatáž úmluva jako u rozhovoru, #452).
    let prompt: String
    /// Strom, ve kterém rebase uvázl. **Zároveň rozsah, na který se omezí `Write` a `Edit`**
    /// (`ConflictCommand.allowedTools(in:)`) — proto tady není `URL?` jako u rozhovoru: session
    /// bez stromu by měla povolení bez rozsahu, tedy zápis kamkoli.
    let worktree: URL
    let timeout: Duration

    /// **Kolidující soubory tady nejsou, a je to schválně.** Session je dostane **v promptu**
    /// (`Policy.conflictPrompt` je vypíše jmény, protože si je bez `Bash`e nezjistí) a aplikace si
    /// je drží ve svém cyklu — druhé pole s týmž obsahem by byl stav, který nikdo nečte a který
    /// svádí k tomu se na něj spolehnout.
    init(
        pullRequest: PRIdentifier,
        prompt: String,
        worktree: URL,
        timeout: Duration = ConflictCommand.timeout
    ) {
        self.pullRequest = pullRequest
        self.prompt = prompt
        self.worktree = worktree
        self.timeout = timeout
    }
}

/// Co se v kole právě děje — podklad pro věty v panelu (#467).
enum ConflictProgress: Sendable, Equatable {
    /// Session naběhla. **Bez `session_id`**: kola na sebe nenavazují (`--resume` tady není), takže
    /// by to byl stav, který nikdo nečte.
    case started
    /// Session si řekla o nástroj. **Pokus, ne použití** — odmítnutý zápis je tu taky, a je to
    /// zrovna ten, kvůli kterému se to čte.
    case attemptedTool(ToolAttempt)
}

typealias ConflictProgressHandler = @Sendable (ConflictProgress) -> Void

/// Session, která slévá konflikty — **jediná v téhle aplikaci, která smí měnit soubory** (#467).
///
/// Za protokolem ze stejného důvodu jako `ReviewRunning` a `AskRunning`: v testech se nahradí
/// fakem a **z typu je vidět, co to umí**. Jedna metoda, která bere kolo a vrací účet; není tu
/// nic, čím by se dalo commitnout, pushnout nebo odeslat na GitHub — commituje **aplikace**
/// (`RepoCheckout.continueRebase`) a do remote píše jedině `BranchPushing`. Tvrdá podmínka č. 1
/// se tímhle tedy nemění, mění se **č. 2**.
///
/// **Selhání session není chyba volání**, jako u revieweera: spadlá i vytimeoutovaná session se
/// vrací jako `ConflictAnswer` s vyplněným `failure`, protože je to výsledek, který se ukazuje.
/// Vyhodí se jen `CancellationError`.
protocol ConflictResolving: Sendable {
    func resolve(
        _ request: ConflictRequest,
        progress: @escaping ConflictProgressHandler
    ) async throws -> ConflictAnswer
}

extension ConflictResolving {
    func resolve(_ request: ConflictRequest) async throws -> ConflictAnswer {
        try await resolve(request, progress: { _ in })
    }
}
