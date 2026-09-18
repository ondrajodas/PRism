import Foundation

/// `HunkAnnotating` nad `claude` CLI (#524).
///
/// Jedna hlava = jedna headless session v pracovním stromě PR. Stream se čte průběžně ze stejného
/// důvodu jako u revieweera: v tabu `Průběh` má být vidět, co session zrovna otevírá.
///
/// **Anotace samotné se ale odnášejí až ze závěrečného `result` eventu** (`AnnotateCommand.parse`),
/// protože odpovědí je poslední sdělení, ne volání nástroje — proč, je u `AnnotationSchema`. Má to
/// jeden důsledek, který se nesmí zamlčet: **zabitá session si nenechá nic**. Reviewer hlásí nálezy
/// průběžně, takže mu zabití vezme jen zbytek; tady se do posledního sdělení buď došlo, nebo ne.
///
/// **Navazuje se přes `--resume` schválně nikdy.** Anotace je jedno hotové tvrzení o jedné hlavě,
/// ne rozhovor: navázat na minulou session by znamenalo popsat dnešní diff s pamětí na ten včerejší.
struct ClaudeHunkAnnotator: HunkAnnotating {
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

    func annotate(
        _ request: AnnotationRequest,
        progress: @escaping AnnotationProgressHandler
    ) async throws -> AnnotationRun {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: AnnotateCommand.arguments(
                prompt: AnnotateCommand.prompt(
                    baseSha: request.baseSha,
                    // Jazyk **ze zadání**, ne z vlastní closury (#592): rozhoduje o něm konfigurace
                    // toho repa, kterou zná store.
                    language: request.language
                ),
                model: model()
            ),
            // **Tytéž proměnné jako u revieweera**: strom stojí nad partial klonem, takže
            // `git diff` i `git log` proti base commitu si objekty dotahují ze sítě — a bez
            // credential helperu by u privátního repa skončily na přihlášení.
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
            // **Nic se nepřenáší**, na rozdíl od revieweera: odpověď je poslední sdělení a zabitá
            // session se do něj nedostala. `outcome` to v okně říká.
            return run(from: summary, outcome: .timedOut)
        } catch ProcessError.launchFailed(let detail) {
            return run(from: summary, outcome: .failed(detail: detail))
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušené session
        // vypadly anotace, jako by doběhla.
        try Task.checkCancellation()

        return run(from: summary, outcome: Self.outcome(of: exit, summary: summary))
    }

    /// Průběh se hlásí z rozdílu proti stavu před řádkem — tentýž vzor jako u `ClaudeAskSession`.
    /// Parser sám nic neoznamuje; je to čistý překlad textu na data.
    ///
    /// **Anotace se ohlašují ve chvíli, kdy dorazí `result`**, tedy naposled a najednou: dřív
    /// odpověď neexistuje. Skládá se přitom **toutéž funkcí**, jakou se pak skládá výsledek, takže
    /// v okně nemůže stát jiné číslo, než jaké se uloží.
    private func consume(
        _ line: String,
        into summary: inout StreamSummary,
        reportingTo progress: AnnotationProgressHandler
    ) {
        let hadSession = summary.sessionID != nil
        let tools = summary.attemptedTools.count
        let hadOutcome = summary.outcome != nil

        parser.consume(line, into: &summary)

        if !hadSession, let sessionID = summary.sessionID {
            progress(.started(sessionID: sessionID))
        }
        for tool in summary.attemptedTools[tools...] {
            progress(.attemptedTool(tool))
        }
        if !hadOutcome, summary.outcome != nil {
            let answer = AnnotateCommand.parse(summary.outcome?.text)
            // **Nepřečtená odpověď událost nevydá**, tedy ani `annotated(0, 0)`: fáze `píše
            // anotace` má zůstat prázdná, protože nula by tvrdila „nic k popsání“ místo pravdy
            // „nedalo se to přečíst“. Je to tatáž úmluva jako `reportedFindings == nil`.
            if answer.answered {
                progress(.annotated(hunks: answer.hunks.count, files: answer.files.count))
            }
        }
    }

    /// Co se ze streamu odnáší. **Nálezy se z něj neberou, ani kdyby v něm byly** — session je
    /// nemá čím nahlásit (`ReportFindings` v její sadě není) a tenhle typ pro ně nemá pole.
    private func run(from summary: StreamSummary, outcome: ReviewRunOutcome) -> AnnotationRun {
        let answer = AnnotateCommand.parse(summary.outcome?.text)
        return AnnotationRun(
            hunks: answer.hunks,
            files: answer.files,
            outcome: outcome,
            sessionID: summary.sessionID,
            answered: answer.answered,
            dropped: answer.dropped,
            usage: summary.usage
        )
    }

    /// Jak běh dopadl. **Nenulový exit kód sám o sobě chyba není** — tatáž úvaha jako
    /// u `ClaudeAskSession.failure`: `claude` jím hlásí i `error_max_turns`, kdežto `result.is_error`
    /// mluví o běhu.
    private static func outcome(
        of exit: (code: Int32, standardError: String)?,
        summary: StreamSummary
    ) -> ReviewRunOutcome {
        if let outcome = summary.outcome, outcome.isError {
            return .failed(detail: "Session skončila chybou (\(outcome.subtype)).")
        }
        guard let exit, exit.code != 0 else { return .finished }
        let detail = exit.standardError.trimmingCharacters(in: .whitespacesAndNewlines).singleLine
        return .failed(
            detail: detail.isEmpty ? "Session skončila s návratovým kódem \(exit.code)." : detail
        )
    }
}
