import Foundation
import Testing

@testable import PRism

/// Přepnutí vlastního draftu na *ready for review* (#482) — publisher proti `FakeProcessRunner`.
///
/// Je to **devátá metoda** `ReviewPublishing`, a rozšířit tvrdou podmínku č. 1 se smí jedině tak,
/// že si nová cesta ven ohlídá totéž co těch osm předchozích. Nejcennější testy tady proto
/// netvrdí, co odešlo, ale že se **nic neodeslalo**: brána a zavřený PR musí skončit dřív, než se
/// sáhne na `gh`.
///
/// **Zvlášť u téhle metody má cenu tvrzení o argumentech**: je to jediná cesta ven, která nejde
/// přes `gh api` — REST endpoint na tuhle věc neexistuje a `PATCH /pulls/{n}` s `draft=false`
/// vrací `200` a přepnutí **tiše zahodí** (změřeno na `prism-review-sandbox#11`, viz
/// `ReadyRequest`). Kdyby se to někdo pokusil „srovnat“ na `gh api`, má to spadnout tady.
@Suite("Ready for review na GitHub")
struct ReadyPublishingTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 11
    )
    private let head = "007e38472e6cbb96c2e2a42b29c22826a1ea6ec8"

    private func detail(state: PullRequestState = .draft) -> PullRequest {
        PullRequest(
            id: sandbox,
            title: "chore: ready probe for 482",
            author: "ondrajodas",
            headSha: head,
            baseSha: "ca42ae548ff9ba603c0a4cf50c4f9c4a09b5df40",
            headRef: "prism-ready-probe-482",
            baseRef: "prism-ready-base-482",
            url: URL(string: "https://github.com/\(sandbox.repo)/pull/\(sandbox.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: false
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

    // MARK: - Nic se neodeslalo

    /// **Ve výchozím nastavení neodejde nic** — a brána je **první** kontrola v cestě, takže se na
    /// nepovolené repo ani neptáme na detail.
    @Test("Bez povolení se nepřepíná")
    func doesNotMarkReadyWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.markReadyForReview(on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Povolení **jiného** repa nestačí: brána se ptá per repo.
    @Test("Povolení jiného repa přepnutí neodemkne")
    func theGateIsPerRepository() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(
            runner,
            scope: .allowing(RepoID(owner: "keboola", name: "connection"))
        )

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.markReadyForReview(on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Stav PR se ověřuje, a **striktněji než GitHub** — tatáž úvaha jako u labelů.
    @Test(
        "Na zavřený ani mergnutý PR se nepřepíná",
        arguments: [PullRequestState.closed, .merged]
    )
    func doesNotMarkReadyOnAClosedPullRequest(state: PullRequestState) async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(runner, detail: .success(detail(state: state)))

        await #expect(throws: PublishError.pullRequestNotOpen(state)) {
            try await publisher.markReadyForReview(on: sandbox)
        }
        #expect(runner.invocations.isEmpty, "pre-flight jde přes gateway, takže se `gh` nespustí")
    }

    /// **`headSha` se neověřuje**, a je to schválně: přepnutí se váže na pull request, ne na
    /// commit — je to jeho vlastnost, ne tvrzení o kódu. Kontrola hlavy by zakázala zrovna to, co
    /// se dělá po posledním pushi.
    @Test("Nová hlava přepnutí nezablokuje")
    func aNewHeadDoesNotBlockIt() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let pushed = PullRequest(
            id: sandbox,
            title: detail().title,
            author: detail().author,
            headSha: "0000000000000000000000000000000000000000",
            baseSha: detail().baseSha,
            url: detail().url,
            updatedAt: detail().updatedAt,
            state: .draft
        )
        let publisher = publisher(runner, detail: .success(pushed))

        try await publisher.markReadyForReview(on: sandbox)

        #expect(runner.invocations.count == 1)
    }

    // MARK: - Co odejde

    /// **`gh pr ready <n> --repo <repo>`, jedním voláním a bez `gh api`.**
    ///
    /// Tvrdí se to **doslova**, protože obojí je změřené rozhodnutí, ne styl: REST tuhle akci
    /// neumí (`PATCH` s `draft=false` vrátí `200` a nic neudělá) a `--repo` je povinné, protože
    /// aplikace procesu nenastavuje pracovní složku — bez něj by si `gh` repozitář hádal z toho,
    /// kde zrovna stojí.
    @Test("Odejde jedno gh pr ready s --repo")
    func sendsOneReadyCommand() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(runner)

        try await publisher.markReadyForReview(on: sandbox)

        #expect(runner.invocations.count == 1)
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments == ["pr", "ready", "11", "--repo", "ondrajodas/prism-review-sandbox"])
        #expect(!arguments.contains("api"), "REST tuhle akci neumí, viz ReadyRequest")
    }

    /// **Prázdný stdout není chyba** — `gh pr ready` na něj nic nepíše (potvrzení jde na stderr
    /// jako věta pro člověka). Metoda proto nic nedekóduje a nic nevrací; kdyby se to změnilo na
    /// dekódování, spadne to tady.
    @Test("Prázdná odpověď projde")
    func acceptsAnEmptyResponse() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(runner)

        try await publisher.markReadyForReview(on: sandbox)
    }

    // MARK: - Když to nedopadne

    /// Nenulový kód se **klasifikuje**, ne polkne. Text je skutečný výstup `gh pr ready`
    /// s neplatným tokenem (změřeno), tedy `HTTP 401` → `notAuthenticated`.
    @Test("Neplatný token vyjde jako nepřihlášeno")
    func classifiesABadToken() async throws {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardOutput: "",
            standardError: """
            HTTP 401: Bad credentials (https://api.github.com/graphql)
            Try authenticating with:  gh auth login
            """
        )
        let publisher = publisher(runner)

        await #expect(throws: PublishError.notAuthenticated) {
            try await publisher.markReadyForReview(on: sandbox)
        }
    }

    /// Selhaný pre-flight **nic nevolá**: chyba se pozná z toho, že se `gh` nespustil.
    @Test("Po spadlém pre-flightu se nevolá nic")
    func doesNotCallAfterAFailedPreflight() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "")
        let publisher = publisher(runner, detail: .failure(GitHubError.notAuthenticated))

        await #expect(throws: PublishError.notAuthenticated) {
            try await publisher.markReadyForReview(on: sandbox)
        }
        #expect(runner.invocations.isEmpty)
    }
}
