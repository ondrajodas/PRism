import Foundation

/// `ReviewBodyWriting` nad `claude` CLI (#521).
///
/// Jedno tělo = jedna headless session **bez jediného nástroje a bez pracovního adresáře**. Tři
/// věci, které v tomhle typu schválně **nejsou**, a každá je vlastní tvrzení — tatáž trojice jako
/// u `ClaudeBriefWriter`:
///
/// - **`gh` tu není vůbec.** Ostatní session dostávají cestu k němu kvůli credential helperu
///   (`ClaudeCommand.environment(gh:)`), protože si `git` dotahuje bloby z partial klonu. Tahle
///   `git` nemá, takže helper nepotřebuje — a typ, který cestu k `gh` ani nedostane, je silnější
///   tvrzení než prostředí, ve kterém zrovna nefiguruje.
/// - **`workingDirectory` je `nil`.** Session nemá čím adresář použít; nasadit jí pracovní strom by
///   znamenalo tvrdit, že v něm něco dělá — a je na to negativní test.
/// - **Model se nevolí** — proč, a proč je to opačné rozhodnutí než u briefu, je
///   u `ReviewBodyCommand.arguments(prompt:)`.
///
/// Streamem, ne bufferovaně, kvůli **ceně**: účet nese `result` event a session, která stojí peníze
/// a neukáže kolik, je vada.
struct ClaudeReviewBodyWriter: ReviewBodyWriting {
    private let claude: URL
    private let runner: any ProcessStreaming
    private let parser = StreamParser()

    init(claude: URL, runner: any ProcessStreaming) {
        self.claude = claude
        self.runner = runner
    }

    func write(_ request: ReviewBodyRequest) async throws -> ReviewBodyAnswer {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: ReviewBodyCommand.arguments(
                prompt: ReviewBodyCommand.prompt(input: request.input)
            ),
            environment: [:],
            workingDirectory: nil,
            timeout: request.timeout
        )

        do {
            for try await event in events {
                switch event {
                case .line(let line): parser.consume(line, into: &summary)
                case .finished(let code, let standardError): exit = (code, standardError)
                }
            }
        } catch ProcessError.timedOut {
            // **Nedopsané tělo se nebere**, jako u briefu — a tady o stupeň důrazněji: je to text,
            // který se odesílá na GitHub pod mým jménem, takže uříznutá věta umí tvrdit opak toho,
            // co měla. Cena se přesto vrací: zabitá session peníze stála.
            return ReviewBodyAnswer(
                text: nil,
                usage: summary.usage,
                failure: "Tělo review nedoběhlo v limitu \(Self.minutes(request.timeout))."
            )
        } catch ProcessError.launchFailed(let detail) {
            return ReviewBodyAnswer(text: nil, usage: summary.usage, failure: "Session se nespustila. \(detail)")
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušeného běhu vypadl
        // odstavec, jako by doběhl.
        try Task.checkCancellation()

        let failure = Self.failure(of: exit, summary: summary)
        let text = failure == nil ? ReviewBodyCommand.parse(summary.outcome?.text) : nil
        return ReviewBodyAnswer(
            text: text,
            usage: summary.usage,
            // **Doběhlá session, která nic nenapsala, je porucha.** Prázdný composer je
            // k nerozeznání od vypnutého návrhu, takže se to musí říct větou.
            failure: failure ?? (text == nil ? "Session nevrátila žádný text." : nil)
        )
    }

    /// Proč běh nedoběhl. `nil` = doběhl v pořádku. Tatáž klasifikace jako u briefu, agenta
    /// a konfliktů: nenulový exit kód sám o sobě chyba není, rozhoduje `result.is_error` i kód.
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
