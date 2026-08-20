import Foundation

/// Text issue jednou krátkou `claude -p` session na celé review (#345).
///
/// **Jedno volání na review, ne na issue.** Rozhoduje **boot session** (85–121 tis. cache-read
/// a ~21 tis. cache-create: systémový prompt, jména všech nástrojů, `SessionStart` hook), ne text
/// issue — takže víc issues v jednom PR je skoro zdarma, ale **každé review platí boot znovu**.
/// Změřeno u #345: $0,18 (sonnet) až $0,30 (opus-5) a ~20 s na dotažení.
///
/// **Tahá se vždycky, i v automatickém režimu** (rozhodnutí uživatele 2026-08-17). Zvažovalo se
/// omezit to na ručně spuštěné review nebo u automatu vynutit `sonnet`; zamítnuto — zadání vedle
/// diffu je důvod, proč tahle funkce existuje, a automat je zrovna ten režim, u kterého se člověk
/// na výsledek dívá až hotový.
struct ClaudeIntentTextFetcher: IntentTextFetching {
    private let claude: URL
    private let runner: any ProcessRunning
    private let timeout: Duration

    /// Dvě minuty, jako u překladu nálezů: měřených ~20 s je pod tím s rezervou a session, která
    /// visí, nemá držet review, které by jinak běželo.
    init(claude: URL, runner: any ProcessRunning, timeout: Duration = .seconds(120)) {
        self.claude = claude
        self.runner = runner
        self.timeout = timeout
    }

    func fetchText(of links: [IntentLink], using tool: String) async throws -> IntentTextResult {
        // Bez odkazů není na co se ptát. Volající sem s prázdnem nechodí, ale session za nic je
        // reálné peníze, takže se to hlídá i tady.
        guard !links.isEmpty else { return IntentTextResult() }

        let result: ProcessResult
        do {
            result = try await runner.run(
                claude,
                arguments: IntentTextCommand.arguments(
                    prompt: IntentTextCommand.prompt(for: links, tool: tool),
                    tool: tool
                ),
                timeout: timeout
            )
        } catch is CancellationError {
            // Jediná chyba, která smí ven. Zrušené review nemá pokračovat dotažením textu, za který
            // si nikdo neřekl — a spolknuté zrušení by se od „nepovedlo se“ nedalo odlišit.
            throw CancellationError()
        } catch {
            // Nespuštěná binárka ani timeout nesmí položit review. Zachytit se to musí **tady**,
            // ne `try?` u volajícího: záruka „selhání dotažení není selhání review“ nemá viset na
            // tom, že si ji každé volání zopakuje. A **nese to důvod dál** — `try?` by z chybějící
            // binárky udělal „issue nic neříká“.
            return IntentTextResult(gap: .sessionFailed(detail: detail(of: error)))
        }
        // **Exit kód se nečte a je to schválně.** Změřeno, že sám nerozhoduje: server, který chybí,
        // skončí nulou a `success`, kdežto server, který se nespustil, jedničkou — ale v obou
        // případech je pravda uvnitř streamu. Kdo čte exit kód, uloží si do zadání prózu modelu
        // („nemám povolení“) jako by to bylo zadání.
        return IntentTextCommand.parse(result.standardOutput, tool: tool, links: links)
    }

    /// Proč se session nepustila, větou pro okno. `ProcessError` má vlastní tvar, takže
    /// `localizedDescription` by z timeoutu udělalo `The operation couldn't be completed`.
    private func detail(of error: any Error) -> String {
        switch error as? ProcessError {
        case .timedOut: "vypršel čas"
        case .launchFailed(let reason): reason
        case nil: error.localizedDescription
        }
    }
}
