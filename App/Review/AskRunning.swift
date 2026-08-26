import Foundation

/// Jedna otázka v rozhovoru nad pull requestem (#452).
struct AskRequest: Sendable, Equatable {
    let pullRequest: PRIdentifier
    /// Celý prompt, i s kontraktem session. Skládá ho `Policy.askPrompt` — runner text neskládá,
    /// jinak by existovalo druhé místo, kde se do promptu dá sáhnout.
    let prompt: String
    /// Pracovní strom na hlavě PR — **tentýž, jaký dostal reviewer** (tvrdá podmínka č. 3).
    /// `nil` = session poběží bez pracovní kopie, tedy bez kódu; volající to nedělá, ale typ to
    /// dovoluje kvůli testům.
    let worktree: URL?
    /// `session_id`, na které se navazuje. `nil` = první otázka, session začíná od nuly.
    let resuming: String?
    let timeout: Duration

    init(
        pullRequest: PRIdentifier,
        prompt: String,
        worktree: URL?,
        resuming: String? = nil,
        timeout: Duration = AskCommand.timeout
    ) {
        self.pullRequest = pullRequest
        self.prompt = prompt
        self.worktree = worktree
        self.resuming = resuming
        self.timeout = timeout
    }
}

/// Co z jedné otázky vyleze (#452).
///
/// Nese odpověď **i důvod, proč není celá**, ne jedno nebo druhé — tatáž úvaha jako
/// u `IntentTextResult`: session umí odpovědět a přitom vytimeoutovat uprostřed, a zahodit
/// text kvůli tomu, že u něj stojí hláška, by znamenalo zaplatit odpověď a nezobrazit ji.
struct AskAnswer: Sendable, Equatable {
    /// Text odpovědi z posledního sdělení session. `nil` = žádné nedorazilo.
    var text: String?
    /// `session_id` **téhle** session — tím se navazuje příště. `claude --resume` vrací id nové
    /// session (větev z původní), takže se přepisuje po každé odpovědi.
    var sessionID: String?
    /// Soubory, které si session otevřela.
    var readFiles: [String] = []
    var usage: RunUsage?
    /// Věta pro okno, když odpověď není celá. `nil` = doběhlo.
    var failure: String?
}

/// Co se v odpovědi právě děje — podklad pro řádek u prstýnku (#452).
enum AskProgress: Sendable, Equatable {
    /// Session naběhla.
    case started(sessionID: String)
    /// Session si řekla o nástroj. **Pokus, ne použití** — odmítnutý nástroj je tu taky.
    case attemptedTool(ToolAttempt)
}

/// Kam běh hlásí, co dělá. Synchronní ze stejného důvodu jako `ReviewProgressHandler`:
/// události mají pořadí a to pořadí je v okně vidět.
typealias AskProgressHandler = @Sendable (AskProgress) -> Void

/// Rozhovor s Claudem nad jedním pull requestem (#452).
///
/// Za protokolem ze stejného důvodu jako `ReviewRunning` a `IntentTextFetching`: v testech se
/// nahradí fakem a **z typu je vidět, co to umí**. Jedna metoda, která bere otázku a vrací
/// odpověď; není tu nic, čím by se dalo zapsat nebo odeslat, takže tvrdá podmínka č. 1 se tímhle
/// nemění.
///
/// **Selhání session není chyba volání**, jako u revieweera: spadlá i vytimeoutovaná session se
/// vrací jako `AskAnswer` s vyplněným `failure`, protože je to výsledek, který se zobrazuje.
/// Vyhodí se jen `CancellationError`.
protocol AskRunning: Sendable {
    func ask(_ request: AskRequest, progress: @escaping AskProgressHandler) async throws -> AskAnswer
}

extension AskRunning {
    func ask(_ request: AskRequest) async throws -> AskAnswer {
        try await ask(request, progress: { _ in })
    }
}
