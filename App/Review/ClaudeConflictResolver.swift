import Foundation

/// `ConflictResolving` nad `claude` CLI (#467).
///
/// Jedno kolo = jedna headless session **v tom stromě, kde rebase uvázl**, s `Write` a `Edit`
/// omezenými právě na něj. Stream se čte průběžně ze dvou důvodů: v panelu je vidět, co session
/// zrovna otevírá, a z pokusů se pozná **zápis mimo strom** (`ConflictCommand.writesOutside`) —
/// tedy druhá vrstva té meze, na které celé #467 stojí.
struct ClaudeConflictResolver: ConflictResolving {
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

    func resolve(
        _ request: ConflictRequest,
        progress: @escaping ConflictProgressHandler
    ) async throws -> ConflictAnswer {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: ConflictCommand.arguments(
                prompt: request.prompt,
                worktree: request.worktree,
                model: model()
            ),
            // **Tytéž proměnné jako u revieweera.** Strom stojí nad partial klonem, takže i čtení
            // souboru umí sáhnout po chybějícím blobu — a bez credential helperu by u privátního
            // repa skončilo na přihlášení. `git` sama session nespouští (`Bash` v sadě není),
            // ale prostředí se kvůli tomu nedělí na druhou sadu, která by se s tou reviewerovou
            // rozešla.
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
            // Session mohla polovinu souborů slít a na další vytimeoutovat; co v nich je, se
            // z okna musí dát přečíst. Rozhodnutí pokračovat pak dělá `git` — soubor se značkami
            // se nepřijme.
            return answer(
                from: summary,
                request: request,
                failure: "Slévání konfliktů nedoběhlo v limitu \(Self.minutes(request.timeout))."
            )
        } catch ProcessError.launchFailed(let detail) {
            return answer(from: summary, request: request, failure: "Session se nespustila. \(detail)")
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušeného kola
        // vypadl účet, jako by doběhlo.
        try Task.checkCancellation()

        return answer(from: summary, request: request, failure: Self.failure(of: exit, summary: summary))
    }

    /// Průběh se hlásí z rozdílu proti stavu před řádkem — tentýž vzor jako u revieweera
    /// a rozhovoru. Parser sám nic neoznamuje; je to čistý překlad textu na data.
    private func consume(
        _ line: String,
        into summary: inout StreamSummary,
        reportingTo progress: ConflictProgressHandler
    ) {
        let hadSession = summary.sessionID != nil
        let tools = summary.attemptedTools.count

        parser.consume(line, into: &summary)

        if !hadSession, summary.sessionID != nil { progress(.started) }
        for tool in summary.attemptedTools[tools...] {
            progress(.attemptedTool(tool))
        }
    }

    /// Účet z posledního sdělení session (`result` event), ne z tool callu.
    ///
    /// Tatáž cesta jako u kontroly nálezů (#150) a rozhovoru (#452) a ze stejného důvodu: vlastní
    /// nástroj na odpověď by byl další věc, kterou session smí zavolat — a u session, která už
    /// smí psát, se výčet nemá rozšiřovat o nic navíc.
    private func answer(
        from summary: StreamSummary,
        request: ConflictRequest,
        failure: String?
    ) -> ConflictAnswer {
        let parsed = ConflictCommand.parse(summary.outcome?.text)
        return ConflictAnswer(
            files: parsed.files,
            caveats: parsed.caveats,
            usage: summary.usage,
            failure: failure,
            writesOutside: ConflictCommand.writesOutside(
                summary.attemptedTools,
                worktree: request.worktree
            )
        )
    }

    /// Proč kolo nedoběhlo. `nil` = doběhlo v pořádku. Tatáž klasifikace jako u rozhovoru:
    /// nenulový exit kód sám o sobě chyba není, rozhoduje `result.is_error` i kód.
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
