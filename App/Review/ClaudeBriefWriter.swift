import Foundation

/// `BriefWriting` nad `claude` CLI (#516).
///
/// Jeden brief = jedna headless session **bez jediného nástroje a bez pracovního adresáře**.
/// Tři věci, které v tomhle typu schválně **nejsou**, a každá je vlastní tvrzení:
///
/// - **`gh` tu není vůbec.** Ostatní session dostávají cestu k němu kvůli credential helperu
///   (`ClaudeCommand.environment(gh:)`), protože si `git` dotahuje bloby z partial klonu. Tahle
///   `git` nemá, takže helper nepotřebuje — a typ, který cestu k `gh` ani nedostane, je silnější
///   tvrzení než prostředí, ve kterém zrovna nefiguruje.
/// - **`workingDirectory` je `nil`.** Session nemá čím adresář použít; nasadit jí pracovní strom
///   by znamenalo tvrdit, že v něm něco dělá.
/// - **Model se nevolí**, jako u překladu nálezů — viz `BriefCommand.arguments(prompt:)`.
///
/// Streamem, ne bufferovaně, kvůli **ceně**: účet nese `result` event a session, která stojí
/// peníze a neukáže kolik, je vada.
struct ClaudeBriefWriter: BriefWriting {
    private let claude: URL
    private let runner: any ProcessStreaming
    private let parser = StreamParser()

    init(claude: URL, runner: any ProcessStreaming) {
        self.claude = claude
        self.runner = runner
    }

    func write(_ request: BriefRequest) async throws -> BriefAnswer {
        var summary = StreamSummary()
        var exit: (code: Int32, standardError: String)?

        let events = runner.stream(
            claude,
            arguments: BriefCommand.arguments(prompt: BriefCommand.prompt(input: request.input)),
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
            // **Nedopsaný brief se nebere.** Na rozdíl od agenta, kde v souborech zůstává odvedená
            // práce, je tu výsledkem jediný odstavec — a půlka odstavce je horší než věta o tom,
            // že se to nepovedlo. Cena se přesto vrací: zabitá session peníze stála.
            return BriefAnswer(
                text: nil,
                usage: summary.usage,
                failure: "Shrnutí nedoběhlo v limitu \(Self.minutes(request.timeout))."
            )
        } catch ProcessError.launchFailed(let detail) {
            return BriefAnswer(text: nil, usage: summary.usage, failure: "Session se nespustila. \(detail)")
        }

        // Zrušený proud skončí **bez chyby**, takže bez téhle kontroly by ze zrušeného běhu
        // vypadl brief, jako by doběhl.
        try Task.checkCancellation()

        let failure = Self.failure(of: exit, summary: summary)
        let text = failure == nil ? BriefCommand.parse(summary.outcome?.text) : nil
        return BriefAnswer(
            text: text,
            usage: summary.usage,
            // **Doběhlá session, která nic nenapsala, je porucha.** Prázdný blok je k nerozeznání
            // od vypnutého briefu, takže se to musí říct větou.
            failure: failure ?? (text == nil ? "Session nevrátila žádný text." : nil)
        )
    }

    /// Proč běh nedoběhl. `nil` = doběhl v pořádku. Tatáž klasifikace jako u agenta a konfliktů:
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
