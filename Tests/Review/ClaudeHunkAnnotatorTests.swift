import Foundation
import Testing

@testable import PRism

/// Anotační session jako podproces (#524) — od streamu k výsledku.
///
/// **Tvrzení, kvůli kterému tahle sada je**: odpověď se sbírá z **posledního sdělení**, takže
/// běh, který se do něj nedostal, nepřináší **nic** — a v okně to musí být poznat. Je to rozdíl
/// proti revieweerovi, kterému zabití vezme jen zbytek, a je to ta cesta, kterou umí sběr tiše
/// nefungovat (`docs/claude-cli.md`).
@Suite("ClaudeHunkAnnotator (#524)")
struct ClaudeHunkAnnotatorTests {
    private let claude = URL(filePath: "/usr/local/bin/claude")
    private let gh = URL(filePath: "/opt/homebrew/bin/gh")

    private func request() -> AnnotationRequest {
        AnnotationRequest(
            pullRequest: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42),
            headSha: "aaaa1111",
            worktree: URL(filePath: "/tmp/prism/worktrees/cli/cli/42-aaaa1111"),
            baseSha: "bbbb2222",
            language: .czech,
            timeout: .seconds(600)
        )
    }

    private func annotator(_ streamer: FakeProcessStreamer) -> ClaudeHunkAnnotator {
        ClaudeHunkAnnotator(claude: claude, gh: gh, runner: streamer, model: { "sonnet" })
    }

    /// Řádek `system`/`init` a pak `result` s odpovědí — nejmenší stream, ve kterém odpověď je.
    private func lines(result: String, sessionID: String = "s-42") -> [String] {
        let escaped = String(
            data: try! JSONSerialization.data(withJSONObject: [result], options: []),
            encoding: .utf8
        )!.dropFirst().dropLast()
        return [
            #"{"type":"system","subtype":"init","session_id":"\#(sessionID)"}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":\#(escaped)}"#,
        ]
    }

    @Test("Z odpovědi vypadnou anotace i session id")
    func readsTheAnswer() async throws {
        let streamer = FakeProcessStreamer(
            lines: lines(
                result: """
                    {"hunks": [{"file": "a.swift", "hunk": 1, "why": "přidává bránu"}], \
                    "files": [{"file": "a.swift", "kind": "behaviour"}]}
                    """
            )
        )

        let run = try await annotator(streamer).annotate(request())

        #expect(run.outcome == .finished)
        #expect(run.answered)
        #expect(run.hunks.map(\.why) == ["přidává bránu"])
        #expect(run.files == [FileAnnotation(file: "a.swift", kind: .behaviour)])
        #expect(run.sessionID == "s-42")
    }

    /// **Zabitý běh nepřináší nic**, a je to vlastnost cesty odpovědi, ne opomenutí: bez `result`
    /// eventu není odkud číst. `answered == false` je to, čím se to v okně pozná.
    @Test("Zabitá session nepřinese ani kus odpovědi")
    func aTimedOutRunCarriesNothing() async throws {
        let streamer = FakeProcessStreamer([
            .timeout(after: [
                #"{"type":"system","subtype":"init","session_id":"s-42"}"#,
                // Session už dokonce psala — jenže do posledního sdělení se nedostala.
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"{\"hunks\": []}"}]}}"#,
            ])
        ])

        let run = try await annotator(streamer).annotate(request())

        #expect(run.outcome == .timedOut)
        #expect(!run.answered)
        #expect(run.hunks.isEmpty)
        #expect(run.files.isEmpty)
        // Session id se **uchová i tak** — `claude --resume` se na zabitý běh navázat dá.
        #expect(run.sessionID == "s-42")
    }

    /// **Odpověď mimo tvar nesebere nic.** Session, která si popis nepřečte, napíše prózu — a to
    /// se nesmí slít s „diff nemá co popsat“.
    @Test("Próza místo odpovědi nesebere nic")
    func proseCollectsNothing() async throws {
        let streamer = FakeProcessStreamer(
            lines: lines(result: "PR přidává bránu do konfigurace a test k ní.")
        )

        let run = try await annotator(streamer).annotate(request())

        #expect(run.outcome == .finished)
        #expect(!run.answered)
        #expect(run.hunks.isEmpty)
    }

    /// Prázdné seznamy jsou **odpověď**. Rozdíl proti testu nad tímhle je jediné pole.
    @Test("Prázdná odpověď je pořád odpověď")
    func emptyListsAreAnAnswer() async throws {
        let streamer = FakeProcessStreamer(lines: lines(result: #"{"hunks": [], "files": []}"#))

        let run = try await annotator(streamer).annotate(request())

        #expect(run.answered)
        #expect(run.hunks.isEmpty)
    }

    /// Průběh se hlásí v pořadí a **anotace až s odpovědí**: dřív není co počítat.
    @Test("Průběh ohlásí session, kroky a nakonec počty")
    func reportsProgressInOrder() async throws {
        let streamer = FakeProcessStreamer(lines: [
            #"{"type":"system","subtype":"init","session_id":"s-42"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x/a.swift"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"{\"hunks\": [{\"file\": \"a.swift\", \"hunk\": 1, \"why\": \"v\"}], \"files\": []}"}"#,
        ])
        let reported = Reported()

        _ = try await annotator(streamer).annotate(request()) { reported.append($0) }

        #expect(reported.events.count == 3)
        #expect(reported.events.first == .started(sessionID: "s-42"))
        if case .attemptedTool(let tool) = reported.events[1] {
            #expect(tool.name == "Read")
        } else {
            Issue.record("druhá událost měla být pokus o nástroj")
        }
        #expect(reported.events.last == .annotated(hunks: 1, files: 0))
    }

    /// **Nepřečtená odpověď událost nevydá**, tedy ani `annotated(0, 0)`: nula by v dráze tvrdila
    /// „nemá co dodat“ místo pravdy „nedalo se to přečíst“.
    @Test("Nepřečtená odpověď se do průběhu nehlásí")
    func doesNotReportAnUnreadableAnswer() async throws {
        let streamer = FakeProcessStreamer(lines: lines(result: "nic strukturovaného"))
        let reported = Reported()

        _ = try await annotator(streamer).annotate(request()) { reported.append($0) }

        #expect(!reported.events.contains { if case .annotated = $0 { true } else { false } })
    }

    /// Limit z požadavku musí dojít **až k procesu** — runner si ho nikam neukládá, takže je to
    /// jediné místo, kde se to dá zkontrolovat.
    @Test("Do procesu jde limit i model z konfigurace")
    func passesTimeoutAndModel() async throws {
        let streamer = FakeProcessStreamer(lines: lines(result: #"{"hunks": []}"#))

        _ = try await annotator(streamer).annotate(request())

        let invocation = try #require(streamer.invocations.first)
        #expect(invocation.timeout == .seconds(600))
        #expect(invocation.workingDirectory == request().worktree)
        #expect(invocation.arguments.contains("--model"))
        #expect(invocation.arguments.contains("sonnet"))
        // **Navazovat se schválně nikdy nemá**: anotace je tvrzení o jedné hlavě, ne rozhovor.
        #expect(!invocation.arguments.contains("--resume"))
    }

    /// Nespuštěná binárka je **selhání běhu, ne chyba volání** — jako u revieweera.
    @Test("Nespuštěná binárka je selhání běhu")
    func aFailedLaunchIsAFailedRun() async throws {
        let streamer = FakeProcessStreamer([.launchFailure("claude nejde spustit")])

        let run = try await annotator(streamer).annotate(request())

        #expect(run.outcome == .failed(detail: "claude nejde spustit"))
        #expect(!run.answered)
    }

    /// Sběrač událostí. Třída, protože handler je `@Sendable` a musí zapisovat ven.
    private final class Reported: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [AnnotationProgress] = []

        var events: [AnnotationProgress] { lock.withLock { recorded } }

        func append(_ event: AnnotationProgress) { lock.withLock { recorded.append(event) } }
    }
}
