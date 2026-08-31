import Foundation
import Testing

@testable import PRism

/// Guardy jediné cesty do remote (#466).
///
/// **Nejcennější tvrzení jsou tady ta, že se NEpushlo**: na cizí PR, na PR z forku, na PR, jehož
/// původ neznáme, mimo cache, mimo bránu a na hlavu, která se mezitím pohnula. `git push` se nedá
/// vzít zpět a rozbije se potichu — v okně by se nic nezměnilo, jen by na GitHubu zmizel cizí
/// commit.
@Suite("Přetlačení větve")
struct GitBranchPushTests {
    private let git = URL(filePath: "/usr/bin/git")
    private let gh = URL(filePath: "/opt/homebrew/bin/gh")
    private let repo = RepoID(owner: "ondrajodas", name: "PRism")
    private let layout = CacheLayout(root: URL(filePath: "/tmp/prism-cache"))
    private var pr: PRIdentifier { PRIdentifier(repo: repo, number: 466) }

    private var worktree: URL { layout.syncWorktree(for: pr) }

    private func detail(
        author: String = "ondrajodas",
        state: PullRequestState = .open,
        head: String = "issue-466-sync-branch",
        headSha: String = "0000000000000000000000000000000000000001",
        cross: Bool? = false
    ) -> PullRequest {
        PullRequest(
            id: pr,
            title: "feat: sync own branch",
            author: author,
            headSha: headSha,
            baseSha: "b0",
            headRef: head,
            baseRef: "main",
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/466")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: cross
        )
    }

    private func plan(
        branch: String = "issue-466-sync-branch",
        expected: String = "0000000000000000000000000000000000000001",
        sha: String = "0000000000000000000000000000000000000002",
        worktree: URL? = nil
    ) -> BranchPushPlan {
        BranchPushPlan(
            pullRequest: pr,
            branch: branch,
            expectedRemoteSha: expected,
            sha: sha,
            worktree: worktree ?? self.worktree
        )
    }

    private func pusher(
        runner: ProcessRunning,
        detail: PullRequest? = nil,
        scope: PublishScope? = nil,
        mine: Set<String> = ["ondrajodas"]
    ) -> GitBranchPush {
        GitBranchPush(
            git: git,
            gh: gh,
            layout: layout,
            runner: runner,
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail ?? self.detail())),
            scope: scope ?? .allowing(repo),
            mine: mine
        )
    }

    private var ok: ScriptedProcessRunner {
        ScriptedProcessRunner([.success(ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))])
    }

    // MARK: - Co se pošle

    /// **`--force-with-lease` s vypsanou hodnotou, nikdy holé `--force`** — a zdrojová strana je
    /// `sha`, ne `HEAD`.
    @Test("Push jde s lease na očekávanou hlavu")
    func pushesWithALease() async throws {
        let runner = ok

        let sha = try await pusher(runner: runner).push(plan())

        #expect(sha == "0000000000000000000000000000000000000002")
        let arguments = try #require(runner.commands.first)
        #expect(arguments.contains("push"))
        #expect(
            arguments.contains(
                "--force-with-lease=refs/heads/issue-466-sync-branch:0000000000000000000000000000000000000001"
            )
        )
        #expect(
            arguments.contains(
                "0000000000000000000000000000000000000002:refs/heads/issue-466-sync-branch"
            )
        )
        #expect(arguments.contains("--force") == false)
        #expect(arguments.contains("HEAD:refs/heads/issue-466-sync-branch") == false)
        // Pushuje se **ze stromu v cache** a s přihlášením přes `gh`, ne z náhodné složky.
        #expect(arguments.prefix(2) == ["-C", worktree.path(percentEncoded: false)])
        #expect(arguments.contains { $0.hasPrefix("credential.helper=") })
    }

    // MARK: - Co se NEpošle

    private func expectNoPush(
        _ error: BranchSyncError,
        detail: PullRequest? = nil,
        scope: PublishScope? = nil,
        mine: Set<String> = ["ondrajodas"],
        plan: BranchPushPlan? = nil
    ) async {
        let runner = ok
        await #expect(throws: error) {
            try await pusher(runner: runner, detail: detail, scope: scope, mine: mine)
                .push(plan ?? self.plan())
        }
        #expect(runner.invocations.isEmpty, "spustil se git, přestože se pushnout nemělo")
    }

    /// **První guard, a posuzuje se proti datům pull requestu**, ne proti jménu větve: jméno si
    /// nastaví kdokoli.
    @Test("Na cizí pull request se nepushuje")
    func refusesForeignPullRequests() async {
        await expectNoPush(.notMine(author: "odinuv"), detail: detail(author: "odinuv"))
    }

    @Test("Na pull request z forku se nepushuje")
    func refusesForks() async {
        await expectNoPush(.foreignBranch, detail: detail(cross: true))
    }

    @Test("Bez odpovědi, kde větev leží, se nepushuje")
    func refusesUnknownOrigin() async {
        await expectNoPush(.unknownBranchOrigin, detail: detail(cross: nil))
    }

    @Test("Na zavřený pull request se nepushuje")
    func refusesClosedPullRequests() async {
        await expectNoPush(.pullRequestNotOpen(.merged), detail: detail(state: .merged))
    }

    /// **Druhý guard v pre-flightu**: hlava, kterou lease očekává, musí být pořád ta z pull
    /// requestu. Server ji ověří ještě jednou, ale z věty v okně má být poznat, co se stalo.
    @Test("Na posunutou hlavu se nepushuje")
    func refusesWhenTheHeadMoved() async {
        await expectNoPush(
            .headMoved(
                expected: "0000000000000000000000000000000000000001",
                actual: "00000000000000000000000000000000000000ff"
            ),
            detail: detail(headSha: "00000000000000000000000000000000000000ff")
        )
    }

    @Test("Na přejmenovanou větev se nepushuje")
    func refusesWhenTheBranchWasRenamed() async {
        await expectNoPush(
            .branchChanged(expected: "issue-466-sync-branch", actual: "jinak"),
            detail: detail(head: "jinak")
        )
    }

    /// **Brána je první, ještě před sítí**: na repo, které povolené není, se nemá ani ptát na
    /// detail.
    @Test("Bez povolení se nepushuje a ani neptá")
    func refusesWhenPublishingIsOff() async {
        await expectNoPush(
            .notAllowed(PublishError.publishingNotAllowed(repo).userDescription),
            scope: .standard
        )
    }

    /// **Tvrdá podmínka č. 3**: pracuje se výhradně v cache. Kontrola je tatáž jako u mazání
    /// a čtení (`CacheLayout.contains`).
    @Test("Ze stromu mimo cache se nepushuje")
    func refusesOutsideTheCache() async {
        let outside = URL(filePath: "/Users/ondra/Projects/PRism")
        await expectNoPush(
            .outsideCache(outside.path(percentEncoded: false)),
            plan: plan(worktree: outside)
        )
    }

    // MARK: - Jak se selhání rozliší

    /// **Odmítnutý lease se pozná od ostatních chyb a řekne se jinou větou** (zadání #466):
    /// znamená, že se nic nepřepsalo a dá se to zkusit znovu.
    @Test("Odmítnutý lease se pozná podle stale info")
    func recognizesARejectedLease() async {
        let runner = ScriptedProcessRunner([
            .success(
                ProcessResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: " ! [rejected]        HEAD -> feature (stale info)\n"
                        + "error: failed to push some refs to 'https://github.com/ondrajodas/PRism.git'"
                )
            ),
        ])

        await #expect(throws: BranchSyncError.leaseRejected) {
            try await pusher(runner: runner).push(plan())
        }
        // Retry s **týmž** plánem u odmítnutého lease nemá jak uspět (viz výčet níž), takže se
        // tady tvrdí jen ta věta — ta je na leaseRejected to podstatné.
        #expect(BranchSyncError.leaseRejected.sentence.contains("nic nepřepsalo"))
    }

    /// Ostatní selhání jdou přes tutéž klasifikaci jako u checkoutu — z odmítnutého přihlášení má
    /// být poznat, že jde o přihlášení, ne o pohnutou větev.
    @Test("Jiné selhání se od lease pozná")
    func classifiesOtherFailures() async throws {
        let runner = ScriptedProcessRunner([
            .success(
                ProcessResult(
                    exitCode: 128,
                    standardOutput: "",
                    standardError: "fatal: Authentication failed for 'https://github.com/'"
                )
            ),
        ])

        let error = await #expect(throws: BranchSyncError.self) {
            try await pusher(runner: runner).push(plan())
        }
        let failure = try #require(error)
        #expect(failure != .leaseRejected)
        #expect(failure.sentence.contains("Přihlášení odmítnuto"))
    }

    @Test("Timeout a nespustitelný git mají vlastní stav")
    func classifiesProcessFailures() async {
        await #expect(throws: BranchSyncError.timedOut) {
            try await pusher(runner: ScriptedProcessRunner([.failure(.timedOut)])).push(plan())
        }
        await #expect(throws: BranchSyncError.toolUnavailable("není")) {
            try await pusher(runner: ScriptedProcessRunner([.failure(.launchFailed("není"))]))
                .push(plan())
        }
    }

    /// **`canRetrySamePlan` se tvrdí výčtem všech třinácti případů, ne jedním.**
    ///
    /// **Dvě revize, dvě různé chyby na tomtéž místě** — a ta druhá je ta zajímavá:
    ///
    /// 1. Doc komentář tvrdil jediný retryovatelný případ, kód pouštěl šest. Prošlo to proto, že
    ///    test pinoval **jediný** z nich. Srovnalo se to tehdy **s kódem**.
    /// 2. Jenže špatně byl **kód**. Retry v sheetu posílá **tentýž plán**, takže u neshody stavu
    ///    (`leaseRejected`, `headMoved`, `branchChanged`) pre-flight srovnává tentýž očekávaný SHA
    ///    proti téže posunuté skutečnosti a druhý pokus dopadne **identicky**. Živé tlačítko vedle
    ///    věty „obnov okno a zkus to znovu“ zve k opakování, které nemůže vyjít.
    ///
    /// Poučení, které si tenhle test nese: **když se komentář rozejde s kódem, není předem jasné,
    /// která strana je ta chybná** — a výčet je to, co odpověď vynutí.
    ///
    /// Dělící čára je **nedokončený pokus proti neshodě stavu**: plán je pořád platný jedině tam,
    /// kde se push nedokončil.
    @Test("Zkusit znovu s týmž plánem jde jen u nedokončeného pokusu")
    func retriesOnlyUnfinishedAttempts() {
        // Pokus se nedokončil — plán platí dál, druhý má proti čemu uspět.
        let unfinished: [BranchSyncError] = [
            .timedOut,
            .interrupted,
            .failed("cokoli od gitu"),
        ]
        // Neshoda stavu: plán je zastaralý z definice, druhý pokus dopadne identicky.
        let mismatched: [BranchSyncError] = [
            .leaseRejected,
            .headMoved(expected: "aaa", actual: "bbb"),
            .branchChanged(expected: "moje", actual: "jina"),
        ]
        // Strukturální překážka: nezmění se opakováním nic.
        let structural: [BranchSyncError] = [
            .notAllowed("brána je vypnutá"),
            .notMine(author: "someone"),
            .foreignBranch,
            .unknownBranchOrigin,
            .pullRequestNotOpen(.closed),
            .outsideCache("/mimo/cache"),
            .toolUnavailable("git není"),
        ]

        for error in unfinished {
            #expect(error.canRetrySamePlan, "\(error): pokus se nedokončil, plán platí dál")
        }
        for error in mismatched + structural {
            #expect(!error.canRetrySamePlan, "\(error): druhý pokus s týmž plánem dopadne stejně")
        }
        // Že jsou to doopravdy **všechny** případy, drží tenhle součet — nový case bez zařazení
        // do jedné ze tří skupin ho položí, a s ním i tvrzení výš.
        #expect(unfinished.count + mismatched.count + structural.count == 13)
    }

    /// **U neshody stavu věta posílá obnovit data.** Je to protějšek zhasnutého tlačítka: kdyby
    /// text neřekl, co dělat, zůstal by uživatel u chyby bez cesty dál.
    @Test("Neshoda stavu posílá obnovit data")
    func mismatchSentencesPointAtRefreshing() {
        #expect(BranchSyncError.leaseRejected.sentence.contains("Načti pull request znovu"))
        #expect(
            BranchSyncError.headMoved(expected: "aaa", actual: "bbb").sentence.contains("Obnov okno")
        )
        #expect(
            BranchSyncError.branchChanged(expected: "a", actual: "b").sentence.contains("Obnov okno")
        )
    }

}
