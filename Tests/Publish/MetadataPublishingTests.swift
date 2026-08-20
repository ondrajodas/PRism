import Foundation
import Testing

@testable import PRism

/// Změna labelů a vyžádání reviewera (#392) — publisher proti `FakeProcessRunner`.
///
/// Nejdůležitější testy tady netvrdí, co se odeslalo, ale že se **nic neodeslalo**: brána, prázdný
/// seznam reviewerů a zavřený PR musí skončit dřív, než se sáhne na `gh`. Jsou to pátá a šestá
/// metoda `ReviewPublishing`, a rozšířit tvrdou podmínku č. 1 se smí jedině tak, že si nová cesta
/// ven ohlídá totéž co ty čtyři předchozí.
@Suite("Labely a reviewery na GitHub")
struct MetadataPublishingTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 4
    )
    private let head = "f213b4ee595585a3a918b67ff630099b616c2ea1"

    private func detail(state: PullRequestState = .open) -> PullRequest {
        PullRequest(
            id: sandbox,
            title: "Testovací PR",
            author: "ondrajodas",
            headSha: head,
            baseSha: "7b3f740e",
            url: URL(string: "https://github.com/\(sandbox.repo)/pull/\(sandbox.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    private func publisher(
        _ runner: ProcessRunning,
        detail: Result<PullRequest, any Error>? = nil,
        scope: PublishScope? = nil
    ) -> GhReviewPublisher {
        GhReviewPublisher(
            gh: gh,
            runner: runner,
            gateway: FakeGitHubGateway(
                always: .success([]),
                detail: detail ?? .success(self.detail())
            ),
            scope: scope ?? .allowing(sandbox.repo)
        )
    }

    /// Odpověď `PUT /issues/{n}/labels` je **pole labelů**, ne obálka — tvar je z `cli/cli`
    /// (`gh api repos/cli/cli/labels`), takže sedí na to, co API doopravdy vrací.
    private let labelsOutput = """
    [{"id":1,"name":"bug","color":"d73a4a","description":""},
     {"id":2,"name":"go","color":"16e2e2","description":"Pull requests that update Go code"}]
    """

    /// Odpověď `POST /pulls/{n}/requested_reviewers` je **pull request**, ze kterého nás zajímá
    /// `requested_reviewers`. Zkrácené na ta pole, která se čtou — zbytek odpovědi se do modelu
    /// nepřepisuje, protože to není čtení detailu.
    private let reviewersOutput = """
    {"number":4,"state":"open",
     "requested_reviewers":[{"login":"odinuv","id":11},{"login":"sergiou87","id":12}]}
    """

    // MARK: - Nic se neodeslalo

    /// **Ve výchozím nastavení neodejde nic** — a brána je **první** kontrola v cestě, takže se na
    /// nepovolené repo ani neptáme na detail.
    @Test("Bez povolení se labely neodešlou")
    func doesNotSetLabelsWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: labelsOutput)
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.setLabels(["bug"], on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Bez povolení se reviewer nevyžádá")
    func doesNotRequestReviewersWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: reviewersOutput)
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.requestReviewers(["odinuv"], on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Povolení **jiného** repa nestačí: brána se ptá per repo, takže se na sandbox pořád nesmí.
    @Test("Povolení jiného repa labely neodemkne")
    func theGateIsPerRepository() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: labelsOutput)
        let publisher = publisher(
            runner,
            scope: .allowing(RepoID(owner: "keboola", name: "connection"))
        )

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.setLabels(["bug"], on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// **Vyžádat nikoho není akce.** GitHub prázdné pole přijme a nic neudělá, takže by okno hlásilo
    /// vyžádané review, které nevzniklo — tatáž past jako u prázdného komentáře.
    @Test("Bez jediného loginu se nic nevolá")
    func doesNotCallWithoutLogins() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: reviewersOutput)
        let publisher = publisher(runner)

        await #expect(throws: PublishError.noReviewer) {
            try await publisher.requestReviewers([], on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Stav PR se ověřuje, a **striktněji než GitHub** — tatáž úvaha jako u komentáře: aplikace
    /// ukazuje otevřené PR, takže přeštítkovat mergnutý patří do prohlížeče.
    @Test("Na mergnutý PR se labely neposílají")
    func doesNotSetLabelsOnAMergedPullRequest() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: labelsOutput)
        let publisher = publisher(runner, detail: .success(detail(state: .merged)))

        await #expect(throws: PublishError.pullRequestNotOpen(.merged)) {
            try await publisher.setLabels(["bug"], on: sandbox)
        }
        #expect(runner.invocations.isEmpty, "pre-flight jde přes gateway, takže se `gh` nespustí")
    }

    @Test("Na zavřený PR se reviewer nevyžádá")
    func doesNotRequestReviewersOnAClosedPullRequest() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: reviewersOutput)
        let publisher = publisher(runner, detail: .success(detail(state: .closed)))

        await #expect(throws: PublishError.pullRequestNotOpen(.closed)) {
            try await publisher.requestReviewers(["odinuv"], on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// **`headSha` se u labelů neověřuje**, a je to schválně: štítek se váže na PR, ne na commit.
    /// Kontrola hlavy by zakázala zrovna to, kvůli čemu se štítkuje — přeštítkovat PR, který mezitím
    /// dostal push.
    @Test("Nová hlava labely nezablokuje")
    func aNewHeadDoesNotBlockLabels() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: labelsOutput)
        var pushed = detail()
        pushed = PullRequest(
            id: pushed.id,
            title: pushed.title,
            author: pushed.author,
            headSha: "0000000000000000000000000000000000000000",
            baseSha: pushed.baseSha,
            url: pushed.url,
            updatedAt: pushed.updatedAt,
            state: pushed.state
        )
        let publisher = publisher(runner, detail: .success(pushed))

        let labels = try await publisher.setLabels(["bug", "go"], on: sandbox)

        #expect(labels.map(\.name) == ["bug", "go"])
    }

    // MARK: - Co odejde

    /// **Jedno atomické volání** a sada se posílá **celá**: `PUT /issues/{n}/labels` ji nahrazuje.
    @Test("Labely odejdou jedním PUT a payload je soubor")
    func sendsLabelsAsOnePut() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: labelsOutput)
        let publisher = publisher(runner)

        _ = try await publisher.setLabels(["bug", "go"], on: sandbox)

        #expect(runner.invocations.count == 1)
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments[0] == "api")
        #expect(arguments[1] == "repos/ondrajodas/prism-review-sandbox/issues/4/labels")
        #expect(arguments.contains("PUT"))
        #expect(arguments.contains("--input"))
    }

    /// **Prázdná sada je platná akce** — sundání posledního štítku. Právě proto jde payload souborem:
    /// `gh api` bez jediného `-f` neposílá tělo vůbec.
    @Test("Sundání posledního labelu pošle prázdné pole")
    func sendsAnEmptySet() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")
        let publisher = publisher(runner)

        let labels = try await publisher.setLabels([], on: sandbox)

        #expect(labels.isEmpty)
        #expect(runner.invocations.count == 1)
    }

    /// Payload je `{"labels": […]}`, a testuje se **na hotových bajtech**: rozešlý tvar by GitHub
    /// odmítl 422, tedy až za sítí.
    @Test("Payload labelů má tvar, který API čeká")
    func encodesTheLabelPayload() throws {
        let data = try MetadataRequest.encoded(MetadataRequest.LabelsPayload(labels: ["bug", "go"]))

        #expect(String(decoding: data, as: UTF8.self) == #"{"labels":["bug","go"]}"#)
    }

    @Test("Prázdná sada se zakóduje jako prázdné pole")
    func encodesTheEmptyLabelPayload() throws {
        let data = try MetadataRequest.encoded(MetadataRequest.LabelsPayload(labels: []))

        #expect(String(decoding: data, as: UTF8.self) == #"{"labels":[]}"#)
    }

    /// Loginy jdou přes `-f`, ne `-F`: `--field` hodnotu typuje, takže login z číslic by v payloadu
    /// skončil jako číslo.
    @Test("Reviewer odejde jedním POST a login jde jako řetězec")
    func sendsReviewersAsOnePost() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: reviewersOutput)
        let publisher = publisher(runner)

        _ = try await publisher.requestReviewers(["odinuv"], on: sandbox)

        #expect(runner.invocations.count == 1)
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments[1] == "repos/ondrajodas/prism-review-sandbox/pulls/4/requested_reviewers")
        #expect(arguments.contains("POST"))
        #expect(arguments.contains("-f"))
        #expect(arguments.contains("reviewers[]=odinuv"))
        #expect(!arguments.contains("-F"))
    }

    /// Vrací se **to, co potvrdil GitHub**, ne to, co jsme poslali — a všichni v té odpovědi čekají,
    /// protože `requested_reviewers` je právě ten seznam, na koho se čeká.
    @Test("Vyžádaní reviewery se vrátí jako čekající")
    func returnsWhoIsWaiting() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: reviewersOutput)
        let publisher = publisher(runner)

        let requested = try await publisher.requestReviewers(["odinuv"], on: sandbox)

        #expect(requested == [
            RequestedReviewer(login: "odinuv", answer: .waiting),
            RequestedReviewer(login: "sergiou87", answer: .waiting),
        ])
    }

    /// Odpověď, které nerozumíme, je `malformedResponse` — exit kód byl nula, takže volání prošlo
    /// a nevíme jen, jak dopadlo.
    @Test("Nečitelná odpověď se hlásí jako nepřečtená, ne jako selhání")
    func reportsUnreadableAnswers() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "{tohle není JSON")
        let publisher = publisher(runner)

        await #expect(throws: (any Error).self) {
            try await publisher.setLabels(["bug"], on: sandbox)
        }
    }

    /// **Po pádu na disku nezůstane payload.** Je v něm jen sada jmen, ale platí tu totéž co
    /// u review: soubor v `/tmp` s naším obsahem se uklízí, ať to dopadne jakkoli.
    ///
    /// Cesta se bere **z argumentů, které publisher doopravdy poslal**, ne výpisem dočasné složky:
    /// výpis by v paralelně běžících testech chytal cizí soubory a tvrdil úklid, který se nestal
    /// (nebo naopak). Takhle se ptáme na ten jeden soubor, o kterém je řeč.
    @Test("Po odeslání nezůstane soubor s payloadem", arguments: [Int32(0), 1])
    func cleansUpTheTemporaryFile(exitCode: Int32) async throws {
        let runner = FakeProcessRunner(
            exitCode: exitCode,
            standardOutput: exitCode == 0 ? labelsOutput : "",
            standardError: exitCode == 0 ? "" : "HTTP 422"
        )
        let publisher = publisher(runner)

        _ = try? await publisher.setLabels(["bug"], on: sandbox)

        let arguments = try #require(runner.invocations.first?.arguments)
        let index = try #require(arguments.firstIndex(of: "--input"))
        let path = arguments[index + 1]
        #expect(path.contains("prism-labels-"), "payload má být poznat i podle jména")
        #expect(!FileManager.default.fileExists(atPath: path), "zůstal \(path)")
    }
}
