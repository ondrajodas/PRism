import Foundation
import Testing

@testable import PRism

@Suite("GhGateway")
struct GhGatewayTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let prism = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 32)

    private func gateway(_ runner: ProcessRunning) -> GhGateway {
        GhGateway(gh: gh, runner: runner)
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    // MARK: - Vyhledávání

    @Test("Query se posílá po tokenech, ne jako jeden argument")
    func splitsQueryIntoArguments() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).searchPullRequests(query: "review-requested:@me is:open")

        // Jako jeden argument to gh rozbije na review-requested:"@me is:open" a odmítne.
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(Array(arguments.prefix(4)) == ["search", "prs", "review-requested:@me", "is:open"])
    }

    @Test("Vyhledávání si řekne o pole, ze kterých se skládá summary")
    func searchAsksForSummaryFields() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).searchPullRequests(query: "review-requested:@me")

        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "search", "prs", "review-requested:@me",
                "--limit", "100",
                "--json", "number,repository,title,author,url,updatedAt,state,isDraft",
            ]),
        ])
    }

    @Test("Skutečný výstup gh se přečte na summaries")
    func decodesRealSearchOutput() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/search-prs.json"))

        let found = try await gateway(runner).searchPullRequests(query: "org:cli")

        #expect(found.count == 4)
        let first = try #require(found.first)
        #expect(first.id == PRIdentifier(repo: RepoID(owner: "cli", name: "go-gh"), number: 275))
        #expect(first.title == "Add per-host API endpoint overrides")
        #expect(first.author == "williammartin")
        #expect(first.url == URL(string: "https://github.com/cli/go-gh/pull/275"))
        #expect(first.updatedAt == (try date("2026-07-31T15:32:50Z")))
        #expect(first.state == .draft)
        #expect(found.last?.state == .open)
    }

    @Test("Prázdný výsledek není chyba")
    func emptySearchIsNotAnError() async throws {
        let runner = try FakeProcessRunner(
            exitCode: 0,
            standardOutput: Fixture.text("gh/search-prs-empty.json")
        )

        #expect(try await gateway(runner).searchPullRequests(query: "org:cli").isEmpty)
    }

    @Test("Rozbitý JSON skončí rozlišitelnou chybou, ne pádem")
    func malformedSearchOutputThrows() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "{ tohle není pole")

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).searchPullRequests(query: "org:cli")
        }
    }

    @Test("Nesmyslné jméno repozitáře se nepropašuje dovnitř")
    func rejectsUnparsableRepository() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: """
            [{"number": 1, "repository": {"name": "x", "nameWithOwner": "bez-lomitka"},
              "title": "t", "author": {"login": "a"}, "url": "https://example.com",
              "updatedAt": "2026-07-31T15:32:50Z", "state": "open", "isDraft": false}]
            """)

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).searchPullRequests(query: "org:cli")
        }
    }

    // MARK: - Detail

    @Test("Detail se ptá na konkrétní PR v konkrétním repu")
    func detailAsksForOnePullRequest() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-view-merged.json"))

        _ = try await gateway(runner).fetchDetail(id: prism)

        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "pr", "view", "32",
                "--repo", "ondrajodas/PRism",
                "--json", "number,title,author,headRefOid,baseRefOid,url,updatedAt,state,isDraft,body,headRefName,baseRefName",
            ]),
        ])
    }

    @Test("Detail nese SHA, které search neumí")
    func detailCarriesShas() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-view-merged.json"))

        let pullRequest = try await gateway(runner).fetchDetail(id: prism)

        #expect(pullRequest.id == prism)
        #expect(pullRequest.headSha == "7a9a8266ad6fa94a8e3332a10fc759f30187286f")
        #expect(pullRequest.baseSha == "2e9a9e7351f17424d0e0b90ef225804fa65b2a32")
        #expect(pullRequest.state == .merged)
        #expect(pullRequest.author == "ondrajodas")
        #expect(pullRequest.updatedAt == (try date("2026-07-31T20:05:20Z")))
    }

    /// Popis PR jde do tabu `Přehled` (#72) a bere se z **téhož** detailu, kvůli kterému se
    /// `gh pr view` volá — tedy bez volání navíc.
    @Test("Detail nese popis PR")
    func detailCarriesTheDescription() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-view-merged.json"))

        let pullRequest = try await gateway(runner).fetchDetail(id: prism)

        #expect(pullRequest.body.hasPrefix("Řeší #3"))
    }

    /// Chybějící pole nemá položit celý detail — na `headSha` z něj stojí review.
    @Test("Detail bez popisu projde s prázdným tělem")
    func survivesAMissingDescription() async throws {
        let json = """
            {
              "number": 32,
              "title": "titulek",
              "author": { "login": "ondrajodas" },
              "headRefOid": "aaaa1111",
              "baseRefOid": "bbbb2222",
              "url": "https://github.com/ondrajodas/PRism/pull/32",
              "updatedAt": "2026-07-31T20:05:20Z",
              "state": "OPEN",
              "isDraft": false
            }
            """
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: json)

        let pullRequest = try await gateway(runner).fetchDetail(id: prism)

        #expect(pullRequest.body.isEmpty)
    }

    @Test("Otevřený PR se z detailu přečte jako otevřený")
    func detailReadsOpenState() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-view-open.json"))
        let id = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13997)

        let pullRequest = try await gateway(runner).fetchDetail(id: id)

        #expect(pullRequest.state == .open)
        #expect(pullRequest.title == "Route gpg key requests through api.Client")
        // Větve (#174) — bez nich se v hlavičce nedá říct, kam se to merguje.
        #expect(pullRequest.headRef == "williammartin-route-gpg-key-api")
        #expect(pullRequest.baseRef == "trunk")
    }

    @Test("Detail bez jmen větví se pořád přečte")
    func detailWithoutBranchNamesStillDecodes() async throws {
        // `headRefName` přibylo až s #174 a je optional schválně: chybějící pole nesmí položit
        // detail, na kterém stojí `headSha` pro review. V hlavičce se pak větve prostě
        // nekreslí — je to tatáž úvaha jako u `body`.
        let json = try Fixture.text("gh/pr-view-open.json")
        let stripped = json
            .split(separator: "\n")
            .filter { !$0.contains("\"headRefName\"") && !$0.contains("\"baseRefName\"") }
            .joined(separator: "\n")
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: stripped)
        let id = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13997)

        let pullRequest = try await gateway(runner).fetchDetail(id: id)

        #expect(pullRequest.headSha.isEmpty == false)
        #expect(pullRequest.headRef.isEmpty)
        #expect(pullRequest.baseRef.isEmpty)
    }

    @Test("Detail o jiném PR, než na který jsme se ptali, se zahodí")
    func rejectsDetailOfDifferentPullRequest() async throws {
        // Identifikátor se bere z dotazu, ne z odpovědi — kdyby se rozešly, klíčovaly by
        // se nálezy k cizímu PR. Tvrdá podmínka: nálezy visí na `headSha` toho PR.
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-view-open.json"))

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).fetchDetail(id: prism)
        }
    }

    // MARK: - Chybové stavy

    @Test("Nepřihlášené gh se pozná i uprostřed práce")
    func notAuthenticatedDuringSearch() async {
        let runner = FakeProcessRunner(
            exitCode: 4,
            standardError: "To get started with GitHub CLI, please run:  gh auth login"
        )

        await #expect(throws: GitHubError.notAuthenticated) {
            try await gateway(runner).searchPullRequests(query: "org:cli")
        }
    }

    @Test("Timeout se od chyby gh odliší")
    func timeoutIsItsOwnError() async {
        let runner = FakeProcessRunner(failing: .timedOut)

        await #expect(throws: GitHubError.timedOut) {
            try await gateway(runner).searchPullRequests(query: "org:cli")
        }
    }

    @Test("Nespustitelné gh se od chyby gh odliší taky")
    func launchFailureIsItsOwnError() async {
        let runner = FakeProcessRunner(failing: .launchFailed("Permission denied"))

        await #expect(throws: GitHubError.toolUnavailable("Permission denied")) {
            try await gateway(runner).searchPullRequests(query: "org:cli")
        }
    }

    @Test("Neexistující PR v detailu je nenalezeno")
    func detailOfUnknownPullRequestIsNotFound() async {
        let stderr = "GraphQL: Could not resolve to a PullRequest with the number of 99999. (repository.pullRequest)"
        let runner = FakeProcessRunner(exitCode: 1, standardError: stderr)

        await #expect(throws: GitHubError.notFound(stderr)) {
            try await gateway(runner).fetchDetail(id: prism)
        }
    }

    // MARK: - Diff

    @Test("Diff se ptá na konkrétní PR a vypíná barvy")
    func diffAsksForOnePullRequestWithoutColor() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")

        _ = try await gateway(runner).fetchDiff(id: prism)

        // `--color never` je pojistka: default `auto` se rozhoduje podle toho, jestli je
        // na výstupu terminál, a barevný diff by parseru přinesl ANSI escape sekvence.
        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "pr", "diff", "32",
                "--repo", "ondrajodas/PRism",
                "--color", "never",
            ]),
        ])
    }

    /// Gateway diffu **nerozumí** — tvar unified diffu není nic, co by `gh` definoval,
    /// takže překlad na model dělá `DiffParser`, ne tenhle typ.
    @Test("Diff se vrací jako syrový text")
    func diffIsReturnedRaw() async throws {
        let text = try Fixture.text("gh/pr-diff-deleted.diff")
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: text)

        #expect(try await gateway(runner).fetchDiff(id: prism) == text)
    }

    @Test("Neexistující PR v diffu je nenalezeno")
    func diffOfUnknownPullRequestIsNotFound() async {
        let stderr = "GraphQL: Could not resolve to a PullRequest with the number of 99999. (repository.pullRequest)"
        let runner = FakeProcessRunner(exitCode: 1, standardError: stderr)

        await #expect(throws: GitHubError.notFound(stderr)) {
            try await gateway(runner).fetchDiff(id: prism)
        }
    }

    // MARK: - Obsah souboru

    @Test("Obsah souboru se čte přes ref pull requestu, ne přes SHA")
    func fileIsReadThroughThePullRequestRef() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "obsah")

        _ = try await gateway(runner).fetchFile(id: prism, path: "App/Main.swift")

        // `refs/pull/<n>/head` má každý PR včetně forků, takže se `headSha` shánět nemusí.
        // Raw hlavička je to, co odliší text souboru od JSONu s base64.
        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "api", "repos/ondrajodas/PRism/contents/App/Main.swift?ref=refs/pull/32/head",
                "--header", "Accept: application/vnd.github.raw",
            ]),
        ])
    }

    @Test("Mezera v cestě se procentuje")
    func encodesSpacesInThePath() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "obsah")

        _ = try await gateway(runner).fetchFile(id: prism, path: "docs/můj soubor.md")

        let path = try #require(runner.invocations.first?.arguments[1])
        #expect(path.contains("m%C5%AFj%20soubor.md"))
    }

    @Test("Soubor, který na hlavě PR není, je nenalezen")
    func missingFileIsNotFound() async {
        let runner = FakeProcessRunner(exitCode: 1, standardError: "gh: Not Found (HTTP 404)")

        await #expect(throws: GitHubError.notFound("gh: Not Found (HTTP 404)")) {
            try await gateway(runner).fetchFile(id: prism, path: "nikde.md")
        }
    }

    // MARK: - Konverzace

    /// Fixture je `cli/cli#11451`, takže se na ni musí ptát stejný identifikátor — gateway
    /// od #63 ověřuje, že odpověď patří tomu PR, na které jsme se ptali.
    private let cliCLI = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 11451)

    @Test("Konverzace jde jedním voláním gh api graphql")
    func fetchesTheConversationInOneCall() async throws {
        let runner = try FakeProcessRunner(
            exitCode: 0,
            standardOutput: Fixture.text("gh/conversation-small.json")
        )

        let conversation = try await gateway(runner).fetchConversation(id: cliCLI)

        #expect(conversation.threads.items.count == 2)
        #expect(conversation.viewer == "ondrajodas")
        // Jeden podproces, ne tři — to je ten důvod, proč je to GraphQL a ne REST.
        #expect(runner.invocations.count == 1)
        #expect(runner.invocations.first?.arguments.prefix(2) == ["api", "graphql"])
        #expect(runner.invocations.first?.arguments.contains("number=11451") == true)
    }

    /// Konverzace přilepená k cizímu PR by v okně vypadala naprosto v pořádku, takže tichý
    /// rozchod je to nejhorší, co se tu může stát. Stejná kontrola jako u `fetchDetail`.
    @Test("Konverzace cizího PR se odmítne")
    func rejectsAConversationForADifferentPullRequest() async throws {
        let runner = try FakeProcessRunner(
            exitCode: 0,
            standardOutput: Fixture.text("gh/conversation-small.json")
        )

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).fetchConversation(id: prism)
        }
    }

    @Test("Rozbitá odpověď je malformedOutput, ne prázdná konverzace")
    func reportsMalformedConversation() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "{ tohle není odpověď")

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).fetchConversation(id: cliCLI)
        }
    }

    @Test("Chyba gh se klasifikuje i u konverzace")
    func classifiesConversationFailures() async {
        let runner = FakeProcessRunner(exitCode: 1, standardError: "gh: Not Found (HTTP 404)")

        await #expect(throws: GitHubError.notFound("gh: Not Found (HTTP 404)")) {
            try await gateway(runner).fetchConversation(id: cliCLI)
        }
    }

    // MARK: - Auth

    @Test("Kontrola přihlášení jde přes gh auth status")
    func checkAuthDelegatesToGh() async {
        let runner = FakeProcessRunner(exitCode: 0)

        let state = await gateway(runner).checkAuth()

        #expect(state == .loggedIn)
        #expect(runner.invocations == [.init(executable: gh, arguments: ["auth", "status"])])
    }
}
