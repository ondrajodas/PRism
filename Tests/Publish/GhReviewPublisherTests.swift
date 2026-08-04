import Foundation
import Testing

@testable import PRism

/// Odesílání review — proti `FakeProcessRunner` a fake gateway.
///
/// Nejdůležitější testy tady netvrdí, co se odeslalo, ale že se **nic neodeslalo**: brána na
/// sandbox, neshoda `headSha` a zavřený PR musí skončit dřív, než se sáhne na `gh`.
@Suite("GhReviewPublisher")
struct GhReviewPublisherTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 4
    )
    private let head = "4a7469f930880b0683354191d315bacfe941ef93"

    private func draft(
        _ pr: PRIdentifier? = nil,
        headSha: String? = nil,
        verdict: ReviewDraft.Verdict? = .comment,
        comments: [ReviewDraftComment] = []
    ) -> ReviewDraft {
        ReviewDraft(
            pullRequest: pr ?? sandbox,
            headSha: headSha ?? head,
            body: "celkem to vypadá dobře",
            verdict: verdict,
            comments: comments
        )
    }

    private func detail(
        _ pr: PRIdentifier? = nil,
        headSha: String? = nil,
        state: PullRequestState = .open
    ) -> PullRequest {
        let id = pr ?? sandbox
        return PullRequest(
            id: id,
            title: "Testovací PR",
            author: "github-actions",
            headSha: headSha ?? head,
            baseSha: "7b3f740e",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    /// Brána je povinný parametr, takže publisher bez ní nevznikne. Testy ji dostávají
    /// otevřenou pro `sandbox` — kdyby výchozí byla `.standard`, skončil by každý test na
    /// bráně a nic dalšího by se neověřilo.
    private func publisher(
        _ runner: ProcessRunning,
        detail: Result<PullRequest, any Error>? = nil,
        scope: PublishScope? = nil
    ) -> GhReviewPublisher {
        GhReviewPublisher(
            gh: gh,
            runner: runner,
            gateway: FakeGitHubGateway(always: .success([]), detail: detail ?? .success(self.detail())),
            scope: scope ?? .allowing(sandbox.repo)
        )
    }

    private func success() throws -> FakeProcessRunner {
        try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/review-submitted.json"))
    }

    // MARK: - Brána na odesílání

    /// **Nejdůležitější test v tomhle souboru.** Ve výchozím nastavení se neodešle nic —
    /// a brána je **první** kontrola v cestě, takže se na nepovolené repo ani neptáme na
    /// detail. Kdyby se přesunula za pre-flight, sáhlo by se na síť kvůli repu, kam se
    /// posílat nemá.
    @Test("Ve výchozím nastavení se neodešle nic a nic se nezavolá")
    func refusesRepositoriesWithoutPermission() async throws {
        let runner = try success()

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher(runner, scope: .standard).submit(draft())
        }
        #expect(runner.invocations.isEmpty, "sáhlo se na gh, i když odesílání není povolené")
    }

    /// Povolení je per repo, takže jedno otevřené repo neotevře ostatní.
    @Test("Povolení jednoho repa neotevře jiné")
    func permissionDoesNotLeakToOtherRepositories() async throws {
        let runner = try success()
        let ostré = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)

        await #expect(throws: PublishError.publishingNotAllowed(ostré.repo)) {
            try await publisher(runner).submit(draft(ostré))
        }
        #expect(runner.invocations.isEmpty, "sáhlo se na gh, i když repo povolené není")
    }

    /// Sandbox **není výjimka v kódu** — od #107 se zapíná stejným přepínačem jako cokoli
    /// jiného. Výjimka by tvrdila něco jiného než nastavení.
    @Test("Sandbox sám o sobě povolený není")
    func theSandboxIsNotHardcoded() {
        #expect(!PublishScope.standard.allows(sandbox.repo))
    }

    // MARK: - Pre-flight

    /// GitHub proti odeslání proti zastaralému commitu **nechrání** — změřeno u #62, že
    /// review se starým `commit_id` přijme. Kontrola tedy musí být tady.
    @Test("Neshoda headSha odeslání zastaví a nic nezavolá")
    func refusesAStaleDraft() async throws {
        let runner = try success()
        let publisher = publisher(runner, detail: .success(detail(headSha: "jinýcommit")))

        await #expect(throws: PublishError.staleDraft(draft: head, head: "jinýcommit")) {
            try await publisher.submit(draft())
        }
        #expect(runner.invocations.isEmpty, "odeslalo se review proti commitu, který není hlava")
    }

    @Test("Zavřený PR odeslání zastaví")
    func refusesAClosedPullRequest() async throws {
        let runner = try success()
        let publisher = publisher(runner, detail: .success(detail(state: .closed)))

        await #expect(throws: PublishError.pullRequestNotOpen(.closed)) {
            try await publisher.submit(draft())
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Mergnutý PR odeslání zastaví")
    func refusesAMergedPullRequest() async throws {
        let runner = try success()
        let publisher = publisher(runner, detail: .success(detail(state: .merged)))

        await #expect(throws: PublishError.pullRequestNotOpen(.merged)) {
            try await publisher.submit(draft())
        }
    }

    /// Na draft PR se review poslat **dá** — je to otevřený stav a na GitHubu běžné.
    @Test("Draft PR se odeslat dá")
    func allowsADraftPullRequest() async throws {
        let runner = try success()
        let publisher = publisher(runner, detail: .success(detail(state: .draft)))

        _ = try await publisher.submit(draft())

        #expect(runner.invocations.count == 1)
    }

    @Test("Bez verdiktu se neodešle nic")
    func refusesADraftWithoutAVerdict() async throws {
        let runner = try success()

        await #expect(throws: PublishError.nothingToSend) {
            try await publisher(runner).submit(draft(verdict: nil))
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Selhání pre-flightu se přeloží a nic se neodešle")
    func translatesPreflightFailures() async throws {
        let runner = try success()
        let publisher = publisher(runner, detail: .failure(GitHubError.notAuthenticated))

        await #expect(throws: PublishError.notAuthenticated) {
            try await publisher.submit(draft())
        }
        #expect(runner.invocations.isEmpty)
    }

    // MARK: - Odeslání

    @Test("Review odejde jedním voláním gh api")
    func submitsInOneCall() async throws {
        let runner = try success()

        let review = try await publisher(runner).submit(draft())

        #expect(runner.invocations.count == 1)
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments.prefix(2) == ["api", "repos/ondrajodas/prism-review-sandbox/pulls/4/reviews"])
        #expect(arguments.contains("POST"))
        #expect(review.id == "4844232301")
        #expect(review.state == .commented)
        #expect(review.author == "ondrajodas")
        #expect(review.submittedAt != nil)
    }

    /// Payload jde souborem, protože `ProcessRunning` neumí stdin — a ten soubor nesmí
    /// zůstat na disku, ať odeslání dopadne jakkoli. Je v něm nezveřejněný text review.
    ///
    /// Kontroluje se **cesta z konkrétní invokace**, ne obsah dočasné složky: Swift Testing
    /// pouští testy paralelně, takže jiný test v téže suitě by do ní mezitím sáhl a porovnání
    /// „před a po“ by bylo flaky.
    @Test("Payload se předává souborem, který po sobě uklidí", arguments: [0, 1] as [Int32])
    func passesThePayloadInAFileAndCleansUp(exitCode: Int32) async throws {
        let runner = try FakeProcessRunner(
            exitCode: exitCode,
            standardOutput: exitCode == 0 ? Fixture.text("gh/review-submitted.json") : "",
            standardError: exitCode == 0 ? "" : "gh: Unprocessable Entity"
        )

        _ = try? await publisher(runner).submit(draft())

        let arguments = try #require(runner.invocations.first?.arguments)
        let index = try #require(arguments.firstIndex(of: "--input"))
        let path = arguments[index + 1]
        #expect(path.hasSuffix(".json"))
        #expect(!FileManager.default.fileExists(atPath: path), "dočasný soubor s review zůstal")
    }

    // MARK: - Klasifikace chyb

    /// Tabulka sedí na **skutečné** hlášky z fixtures, které vznikly voláním živého API
    /// u #62 a #67.
    @Test("Chyby gh se klasifikují podle skutečných hlášek", arguments: [
        ("review-error-line-outside-diff.json", PublishError.lineOutsideDiff("")),
        ("review-error-path-outside-diff.json", PublishError.pathOutsideDiff("")),
        ("review-error-pending-exists.json", PublishError.pendingReviewExists),
        ("review-error-approve-own-pr.json", PublishError.ownPullRequest("")),
        ("review-error-request-changes-own-pr.json", PublishError.ownPullRequest("")),
    ])
    func classifiesRealFailures(fixture: String, expected: PublishError) throws {
        let stderr = try Fixture.text("gh/\(fixture)")
        let error = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: stderr
        ))

        #expect(sameCase(error, expected), "\(fixture) vyšlo jako \(error)")
    }

    @Test("Nepřihlášené gh se pozná z exit kódu")
    func classifiesMissingAuth() {
        let error = PublishError(failure: ProcessResult(
            exitCode: 4,
            standardOutput: "",
            standardError: "To get started with GitHub CLI, please run: gh auth login"
        ))

        #expect(error == .notAuthenticated)
    }

    @Test("Rate limit a síť se rozliší")
    func classifiesRateLimitAndNetwork() {
        let rate = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "API rate limit exceeded"
        ))
        let network = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "error connecting to api.github.com"
        ))

        #expect(sameCase(rate, .rateLimited("")))
        #expect(sameCase(network, .network("")))
    }

    /// Neznámou hlášku se **nehádá** — text `gh` se nese dál, protože je to jediné, co o ní víme.
    @Test("Neznámá hláška zůstane neznámá i s textem")
    func keepsUnknownFailures() {
        let error = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "něco úplně nového"
        ))

        #expect(error == .unknown("něco úplně nového"))
    }

    @Test("Timeout a nespuštěné gh se od chyby gh odliší")
    func distinguishesProcessFailures() async {
        let timeout = publisher(FakeProcessRunner(failing: .timedOut))
        let launch = publisher(FakeProcessRunner(failing: .launchFailed("Permission denied")))

        await #expect(throws: PublishError.timedOut) { try await timeout.submit(draft()) }
        await #expect(throws: PublishError.toolUnavailable("Permission denied")) {
            try await launch.submit(draft())
        }
    }

    /// Review možná odešlo, takže se to nesmí spolknout — z hlášky musí být vidět, že se to
    /// má zkontrolovat na GitHubu.
    @Test("Nečitelná odpověď je vlastní chyba")
    func reportsAMalformedResponse() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "{ tohle není review")

        await #expect(throws: PublishError.self) {
            try await publisher(runner).submit(draft())
        }
    }

    /// Odeslané review vždycky autora má, takže jeho absence znamená, že odpověď není tím, co
    /// čekáme. Prázdné jméno by byla vymyšlená identita — tatáž úvaha jako u #63.
    @Test("Odpověď bez autora se nedoplní prázdným jménem")
    func refusesAResponseWithoutAnAuthor() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"{"id":1,"state":"COMMENTED","body":"","user":null}"#
        )

        await #expect(throws: PublishError.malformedResponse("V odpovědi chybí autor review.")) {
            try await publisher(runner).submit(draft())
        }
    }

    /// Prázdné **tělo** je naopak v pořádku — schválení bez prózy je plnohodnotné review.
    @Test("Odpověď s prázdným tělem projde")
    func acceptsAnEmptyBody() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"{"id":7,"state":"APPROVED","body":"","user":{"login":"kdosi"}}"#
        )

        let review = try await publisher(runner).submit(draft())

        #expect(review.body.isEmpty)
        #expect(review.state == .approved)
        #expect(review.author == "kdosi")
    }

    // MARK: - Zrušení a dočasný soubor

    /// Zrušení **není chyba nástroje**. Kdyby se přemapovalo na `toolUnavailable`, ukázalo by
    /// okno „gh se nepodařilo spustit“ nad odesláním, které si člověk sám zrušil — a stejné
    /// pravidlo drží `ReviewRunner`.
    @Test("Zrušení projde jako zrušení, ne jako chyba nástroje")
    func propagatesCancellation() async {
        let publisher = publisher(CancellingProcessRunner())

        await #expect(throws: CancellationError.self) {
            try await publisher.submit(draft())
        }
    }

    /// Je v něm text review, který ještě nikdo neviděl, a dočasná složka je společná pro celý
    /// systém. Práva se čtou **uvnitř** fake runneru, protože jen tam soubor ještě existuje.
    @Test("Soubor s review má práva 0600")
    func writesThePayloadPrivately() async throws {
        let runner = try PermissionCheckingRunner(
            standardOutput: Fixture.text("gh/review-submitted.json")
        )

        _ = try await publisher(runner).submit(draft())

        #expect(runner.permissions == 0o600, "payload měl práva \(String(runner.permissions ?? 0, radix: 8))")
    }

    // MARK: - Payload

    @Test("Payload nese verdikt, commit i komentáře")
    func buildsThePayload() throws {
        let comment = ReviewDraftComment(
            path: "Cart.php",
            anchor: DraftAnchor(line: 28, side: .right),
            body: "tady se ignoruje množství",
            origin: .finding(reviewer: "code-review")
        )
        let payload = try #require(PublishRequest.payload(
            for: draft(verdict: .requestChanges, comments: [comment])
        ))

        #expect(payload.event == "REQUEST_CHANGES")
        #expect(payload.commitID == head)
        #expect(payload.comments.count == 1)
        #expect(payload.comments.first?.side == "RIGHT")
    }

    /// Strana se posílá tak, jak ji chce API — bez ní by komentář k odebranému řádku sedl
    /// na jiný kód.
    @Test("Levá strana se posílá jako LEFT")
    func sendsTheLeftSide() throws {
        let comment = ReviewDraftComment(
            path: "Cart.php",
            anchor: DraftAnchor(line: 26, side: .left),
            body: "odebraný řádek",
            origin: .own
        )
        let payload = try #require(PublishRequest.payload(for: draft(comments: [comment])))

        #expect(payload.comments.first?.side == "LEFT")
    }

    /// Tvar payloadu je ověřený proti živému API (#67): tohle jsou přesně ty klíče, které
    /// GitHub přijal.
    @Test("Payload používá klíče, které bere GitHub")
    func encodesTheApiKeys() throws {
        let payload = try #require(PublishRequest.payload(for: draft()))
        let json = String(decoding: try PublishRequest.encoded(payload), as: UTF8.self)

        #expect(json.contains("\"commit_id\""))
        #expect(json.contains("\"event\""))
        #expect(!json.contains("\"commitID\""))
    }

    /// Rozsah jde jako `start_line`/`start_side` (#110) — přesně ten payload, který GitHub
    /// v sandboxu přijal a zapsal jako `start=26/RIGHT end=30/RIGHT`.
    @Test("Rozsah se posílá jako start_line a start_side")
    func sendsTheRangeEndpoints() throws {
        let comment = ReviewDraftComment(
            path: "Cart.php",
            anchor: DraftAnchor(line: 30, side: .right, start: DraftAnchor.Endpoint(line: 26, side: .right)),
            body: "tenhle blok patří do vlastní metody",
            origin: .own
        )
        let payload = try #require(PublishRequest.payload(for: draft(comments: [comment])))
        let json = String(decoding: try PublishRequest.encoded(payload), as: UTF8.self)

        #expect(payload.comments.first?.startLine == 26)
        #expect(payload.comments.first?.startSide == "RIGHT")
        #expect(json.contains("\"start_line\""))
        #expect(json.contains("\"start_side\""))
    }

    /// U jednořádkového komentáře v payloadu **nesmí být vůbec**: je to tentýž tvar, který
    /// prošel u #62 a #67, a rozsah délky 1 by byl druhá podoba téhož.
    @Test("Jednořádkový komentář posílá payload bez rozsahu")
    func omitsTheRangeForASingleLine() throws {
        let comment = ReviewDraftComment(
            path: "Cart.php",
            anchor: DraftAnchor(line: 28, side: .right),
            body: "jeden řádek",
            origin: .own
        )
        let payload = try #require(PublishRequest.payload(for: draft(comments: [comment])))
        let json = String(decoding: try PublishRequest.encoded(payload), as: UTF8.self)

        #expect(payload.comments.first?.startLine == nil)
        #expect(!json.contains("start_line"))
        #expect(!json.contains("start_side"))
    }

    /// Rozsah přes obě strany GitHub bere (změřeno u #110) — a strany se posílají každá svá,
    /// takže se nesmí odvozovat jedna z druhé.
    @Test("Rozsah přes obě strany posílá dvě různé strany")
    func sendsBothSidesOfAMixedRange() throws {
        let comment = ReviewDraftComment(
            path: "README.md",
            anchor: DraftAnchor(line: 5, side: .right, start: DraftAnchor.Endpoint(line: 6, side: .left)),
            body: "tady se to přepsalo",
            origin: .own
        )
        let payload = try #require(PublishRequest.payload(for: draft(comments: [comment])))

        #expect(payload.comments.first?.startSide == "LEFT")
        #expect(payload.comments.first?.side == "RIGHT")
        #expect(payload.comments.first?.startLine == 6)
        #expect(payload.comments.first?.line == 5)
    }

    @Test("Bez verdiktu payload nevznikne")
    func buildsNoPayloadWithoutAVerdict() {
        #expect(PublishRequest.payload(for: draft(verdict: nil)) == nil)
    }

    /// Porovnává jen **druh** chyby, ne text — ten nese hlášku `gh`, která se může měnit.
    private func sameCase(_ left: PublishError, _ right: PublishError) -> Bool {
        switch (left, right) {
        case (.lineOutsideDiff, .lineOutsideDiff), (.pathOutsideDiff, .pathOutsideDiff),
             (.pendingReviewExists, .pendingReviewExists), (.ownPullRequest, .ownPullRequest),
             (.notAuthenticated, .notAuthenticated), (.rateLimited, .rateLimited),
             (.network, .network), (.unknown, .unknown):
            true
        default:
            false
        }
    }
}

/// Runner, který volání zruší — `FakeProcessRunner` umí selhat jen `ProcessError`.
private final class CancellingProcessRunner: ProcessRunning, @unchecked Sendable {
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProcessResult {
        throw CancellationError()
    }
}

/// Runner, který si při volání přečte práva payload souboru. Jinde než tady to nejde —
/// po návratu je soubor smazaný.
private final class PermissionCheckingRunner: ProcessRunning, @unchecked Sendable {
    private let output: String
    private let lock = NSLock()
    private var seen: Int?

    init(standardOutput: String) { output = standardOutput }

    var permissions: Int? { lock.withLock { seen } }

    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> ProcessResult {
        if let index = arguments.firstIndex(of: "--input"), index + 1 < arguments.count {
            let attributes = try? FileManager.default.attributesOfItem(atPath: arguments[index + 1])
            lock.withLock { seen = attributes?[.posixPermissions] as? Int }
        }
        return ProcessResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}
