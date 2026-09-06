import Foundation

/// `AgentFixing` nad `claude` CLI (#510).
///
/// Jeden běh = jedna headless session **ve stromě `-sync` toho pull requestu**, s `Write` a `Edit`
/// omezenými právě na něj. Stream se čte průběžně ze dvou důvodů: v panelu je vidět, co session
/// zrovna otevírá, a z pokusů se pozná **zápis mimo strom** (`AgentFixCommand.writesOutside`) —
/// tedy druhá vrstva té meze, na které #510 stojí.
///
/// **Vlastní typ vedle `ClaudeConflictResolver`, ne jeho druhé použití**, a je to schválně: účet
/// je jiný (co se opravilo, ne co s kterým konfliktem), limit je jiný a hlavně **volající je
/// jiný** — konflikt řeší kolo rebase, tohle spouští cizí hlas. Sdílené zůstává to, co se sdílet
/// musí: **sada povolení a rozsah zápisu** (`AgentFixCommand` je bere z `ConflictCommand`).
struct ClaudeAgentFixer: AgentFixing {
    private let claude: URL
    private let gh: URL
    private let runner: any ProcessStreaming
    private let parser = StreamParser()
    /// Volba modelu z konfigurace; `nil` = ten, který si `claude` zvolí sám.
    private let model: @Sendable () -> String?

    init(
        claude: URL,
        gh: URL,
        runner: any ProcessStreaming,
        model: @escaping @Sendable () -> String? = { nil }
    ) {
        self.claude = claude
        self.gh = gh
        self.runner = runner
        self.model = model
    }

    func fix(
        _ request: AgentFixRequest,
        progress: @escaping AgentFixProgressHandler
    ) async throws -> AgentFixAnswer {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: AgentFixCommand.arguments(
                prompt: request.prompt,
                worktree: request.worktree,
                model: model()
            ),
            // **Tytéž proměnné jako u revieweera a u konfliktů.** Strom stojí nad partial klonem,
            // takže i čtení souboru umí sáhnout po chybějícím blobu — a bez credential helperu by
            // u privátního repa skončilo na přihlášení. `git` sama session nespouští (`Bash`
            // v sadě není), ale prostředí se kvůli tomu nedělí na druhou sadu.
            environment: ClaudeCommand.environment(gh: gh),
            workingDirectory: request.worktree,
            timeout: request.timeout
        )

        do {
            for try await event in events {
                switch event {
                case .line(let line): consume(line, into: &summary, reportingTo: progress)
                case .finished(let code, let standardError): exit = (code, standardError)
                }
            }
        } catch ProcessError.timedOut {
            // **Rozdělaná práce v souborech zůstává, a proto se odpověď vrací, ne vyhazuje.**
            // Session mohla polovinu položek opravit a na další vytimeoutovat; co v souborech je,
            // se z okna musí dát přečíst. Jestli se to commitne, rozhoduje `git` a člověk.
            return answer(
                from: summary,
                request: request,
                failure: "Agent nedoběhl v limitu \(Self.minutes(request.timeout))."
            )
        } catch ProcessError.launchFailed(let detail) {
            return answer(from: summary, request: request, failure: "Session se nespustila. \(detail)")
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušeného běhu
        // vypadl účet, jako by doběhl.
        try Task.checkCancellation()

        return answer(from: summary, request: request, failure: Self.failure(of: exit, summary: summary))
    }

    /// Průběh se hlásí z rozdílu proti stavu před řádkem — tentýž vzor jako u revieweera,
    /// rozhovoru a konfliktů. Parser sám nic neoznamuje; je to čistý překlad textu na data.
    private func consume(
        _ line: String,
        into summary: inout StreamSummary,
        reportingTo progress: AgentFixProgressHandler
    ) {
        let hadSession = summary.sessionID != nil
        let tools = summary.attemptedTools.count

        parser.consume(line, into: &summary)

        if !hadSession, summary.sessionID != nil { progress(.started) }
        for tool in summary.attemptedTools[tools...] {
            progress(.attemptedTool(tool))
        }
    }

    /// Účet z posledního sdělení session (`result` event), ne z tool callu — tatáž cesta jako
    /// u konfliktů a ze stejného důvodu: vlastní nástroj na odpověď by byl další věc, kterou
    /// session smí zavolat, a u té, která už smí psát, se výčet nemá rozšiřovat o nic navíc.
    private func answer(
        from summary: StreamSummary,
        request: AgentFixRequest,
        failure: String?
    ) -> AgentFixAnswer {
        let parsed = AgentFixCommand.parse(summary.outcome?.text)
        return AgentFixAnswer(
            files: parsed.files,
            summary: parsed.summary,
            skipped: parsed.skipped,
            usage: summary.usage,
            failure: failure,
            writesOutside: AgentFixCommand.writesOutside(
                summary.attemptedTools,
                worktree: request.worktree
            )
        )
    }

    /// Proč běh nedoběhl. `nil` = doběhl v pořádku. Tatáž klasifikace jako u konfliktů: nenulový
    /// exit kód sám o sobě chyba není, rozhoduje `result.is_error` i kód.
    private static func failure(
        of exit: (code: Int32, standardError: String)?,
        summary: StreamSummary
    ) -> String? {
        if let outcome = summary.outcome, outcome.isError {
            return "Session skončila chybou (\(outcome.subtype))."
        }
        guard let exit, exit.code != 0 else { return nil }
        let detail = exit.standardError.trimmingCharacters(in: .whitespacesAndNewlines).singleLine
        return detail.isEmpty
            ? "Session skončila s návratovým kódem \(exit.code)."
            : "Session skončila chybou. \(detail)"
    }

    /// Limit slovy, do hlášky. `Duration` se do textu jinak vypíše jako dvojice čísel.
    private static func minutes(_ timeout: Duration) -> String {
        let seconds = Int(timeout.components.seconds)
        guard seconds >= 60, seconds % 60 == 0 else {
            return Plural.czech(seconds, one: "sekunda", few: "sekundy", many: "sekund")
        }
        return Plural.czech(seconds / 60, one: "minuta", few: "minuty", many: "minut")
    }
}
