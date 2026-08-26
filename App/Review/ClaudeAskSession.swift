import Foundation

/// `AskRunning` nad `claude` CLI (#452).
///
/// Jedna otázka = jedna headless session v pracovním stromě PR, navázaná přes `--resume` na tu
/// předchozí. Stream se čte průběžně ze dvou důvodů: v okně je vidět, co session zrovna otevírá
/// (prstýnek na místě příští bubliny má u sebe řádek), a **zabitá session si nechá `session_id`**
/// — bez něj by se rozhovor po prvním timeoutu rozpadl na samostatné otázky.
struct ClaudeAskSession: AskRunning {
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

    func ask(_ request: AskRequest, progress: @escaping AskProgressHandler) async throws -> AskAnswer {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: AskCommand.arguments(
                prompt: request.prompt,
                resuming: request.resuming,
                model: model()
            ),
            // **Tytéž proměnné jako u revieweera**: pracovní strom stojí nad partial klonem, takže
            // `git diff` proti base commitu si bloby dotahuje ze sítě — a bez credential helperu
            // by u privátního repa skončil na přihlášení. Druhá sada by se s tou reviewerovou
            // rozešla zrovna u privátního repa, tedy tam, kde se to pozná nejpozději.
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
            // Částečná odpověď zůstává — kvůli tomu se stream čte průběžně. A `session_id` s ní,
            // takže se dá zeptat znovu ve **stejném** rozhovoru.
            return answer(
                from: summary,
                worktree: request.worktree,
                failure: "Odpověď nedoběhla v limitu \(Self.minutes(request.timeout)) — zkus se zeptat znovu."
            )
        } catch ProcessError.launchFailed(let detail) {
            return answer(from: summary, worktree: request.worktree, failure: "Session se nespustila. \(detail)")
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušené otázky
        // vypadla odpověď, jako by doběhla.
        try Task.checkCancellation()

        return answer(from: summary, worktree: request.worktree, failure: Self.failure(of: exit, summary: summary))
    }

    /// Průběh se hlásí z rozdílu proti stavu před řádkem — tentýž vzor jako
    /// u `ClaudeReviewRunner`. Parser sám nic neoznamuje; je to čistý překlad textu na data.
    private func consume(
        _ line: String,
        into summary: inout StreamSummary,
        reportingTo progress: AskProgressHandler
    ) {
        let hadSession = summary.sessionID != nil
        let tools = summary.attemptedTools.count

        parser.consume(line, into: &summary)

        if !hadSession, let sessionID = summary.sessionID {
            progress(.started(sessionID: sessionID))
        }
        for tool in summary.attemptedTools[tools...] {
            progress(.attemptedTool(tool))
        }
    }

    /// Odpověď z posledního sdělení session (`result` event), ne z tool callu.
    ///
    /// Je to tatáž cesta jako u kontroly nálezů (#150) a ze stejného důvodu: rozhovor nemá nástroj,
    /// kterým by odpověď posílal — a nástroj navíc by byl osmá věc, kterou session smí zavolat.
    private func answer(from summary: StreamSummary, worktree: URL?, failure: String?) -> AskAnswer {
        let text = summary.outcome?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AskAnswer(
            // Prázdný text je totéž jako žádný: bublina s prázdnou bublinou by vypadala jako
            // odpověď, kterou se nepodařilo vykreslit.
            text: (text?.isEmpty ?? true) ? nil : text,
            sessionID: summary.sessionID,
            readFiles: AskCommand.readFiles(from: summary.attemptedTools, worktree: worktree),
            usage: summary.usage,
            failure: failure
        )
    }

    /// Proč odpověď není celá. `nil` = doběhla v pořádku.
    ///
    /// **Nenulový exit kód sám o sobě chyba není** — `claude` jím hlásí i to, že model skončil
    /// `error_max_turns`, kdežto `result.is_error` mluví o běhu. Rozhoduje proto obojí: co
    /// z toho přišlo, to se použije, a stderr je poslední záchrana pro běh, který o sobě neřekl nic.
    private static func failure(of exit: (code: Int32, standardError: String)?, summary: StreamSummary) -> String? {
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
