import Foundation
import Testing

@testable import PRism

@Suite("GitRepoCheckout – worktrees")
struct WorktreeTests {
    private let git = URL(filePath: KnownPath.git)
    private let gh = URL(filePath: KnownPath.gh)
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)
    private let headSha = "7a9a8266ad6fa94a8e3332a10fc759f30187286f"

    private let workspace: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        workspace = try TemporaryDirectory()
        layout = CacheLayout(root: workspace.url)
    }

    private func checkout(_ runner: ProcessRunning) -> GitRepoCheckout {
        GitRepoCheckout(git: git, gh: gh, layout: layout, runner: runner)
    }

    /// Hotový klon v cache, ať se `prepare` chová jako při druhém setkání s repem.
    private func makeCompleteClone() throws {
        let clone = layout.bareClone(for: pr.repo)
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        try Data().write(to: layout.cloneMarker(for: pr.repo))
    }

    // MARK: - Cesty

    @Test("Worktree má v názvu repo, číslo PR i celý sha")
    func worktreePathCarriesTheKey() {
        let path = layout.worktree(for: pr, at: headSha).lastPathComponent

        #expect(path == "keboola-vault-85-\(headSha)")
    }

    @Test("Jiný sha znamená jiný worktree")
    func differentShaMeansDifferentWorktree() {
        // Nálezy visí na `headSha`; dva běhy nad různými commity si nesmí sáhnout na totéž.
        let other = layout.worktree(for: pr, at: "3fd94af22d625e2415dd80224a47878d21e959b4")

        #expect(layout.worktree(for: pr, at: headSha) != other)
    }

    // MARK: - Vytvoření

    @Test("Worktree se přidá odpojený a na zadaném commitu")
    func addsDetachedWorktreeAtCommit() async throws {
        try makeCompleteClone()
        // fetch (prepare), cat-file (commit je v klonu), worktree add
        let runner = ScriptedProcessRunner(exitCodes: [0, 0, 0])

        let path = try await checkout(runner).worktree(for: pr, at: headSha)

        #expect(path == layout.worktree(for: pr, at: headSha))
        let add = try #require(runner.commands.last)
        #expect(add.contains("worktree"))
        #expect(add.contains("add"))
        #expect(add.contains("--detach"))
        #expect(add.contains(headSha))
        #expect(add.contains(path.path(percentEncoded: false)))
    }

    @Test("Chybějící commit se dotáhne přes ref pull requestu")
    func fetchesPullRequestRefWhenCommitIsMissing() async throws {
        try makeCompleteClone()
        // fetch (prepare), cat-file selže, fetch PR refu, cat-file projde, worktree add
        let runner = ScriptedProcessRunner(exitCodes: [0, 1, 0, 0, 0])

        _ = try await checkout(runner).worktree(for: pr, at: headSha)

        // Refspec je jeden argument (`+refs/pull/85/head:refs/prism/pr/85`), takže se
        // v něm hledá podřetězec — `contains` nad polem porovnává celé prvky.
        let fetch = try #require(runner.commands.first { $0.contains { $0.contains("refs/pull/85/head") } })
        #expect(fetch.contains("fetch"))
    }

    @Test("Commit, který nedorazí ani s ref pull requestu, je rozlišitelná chyba")
    func missingCommitAfterFetchIsAnError() async throws {
        try makeCompleteClone()
        // fetch (prepare), cat-file selže, fetch PR refu, cat-file selže zas
        let runner = ScriptedProcessRunner(exitCodes: [0, 1, 0, 1])

        await #expect(throws: CheckoutError.commitNotFound(headSha)) {
            try await checkout(runner).worktree(for: pr, at: headSha)
        }
    }

    @Test("Použitelný worktree se použije znovu, nepřidává se podruhé")
    func existingWorktreeIsReused() async throws {
        try makeCompleteClone()
        try FileManager.default.createDirectory(
            at: layout.worktree(for: pr, at: headSha),
            withIntermediateDirectories: true
        )
        // Strom se použije znovu jen tehdy, když v něm `git` odpoví a stojí na tom
        // commitu — samotná existence složky nestačí.
        let runner = ScriptedProcessRunner([
            .success(ProcessResult(exitCode: 0, standardOutput: headSha + "\n", standardError: "")),
        ])

        let path = try await checkout(runner).worktree(for: pr, at: headSha)

        #expect(path == layout.worktree(for: pr, at: headSha))
        #expect(runner.commands.count == 1)
        #expect(!runner.commands.contains { $0.contains("add") })
    }

    // MARK: - Úklid

    @Test("Úklid worktree projde přes remove i prune")
    func removingWorktreePrunesTheClone() async throws {
        // `prune` je tam kvůli stromům, které zmizely **bez** `remove` — po pádu aplikace
        // nebo ručním smazání složky. Sám `remove` po sobě administrativu uklidí.
        try makeCompleteClone()
        let runner = ScriptedProcessRunner(exitCodes: [0, 0])

        try await checkout(runner).removeWorktree(for: pr, at: headSha)

        #expect(runner.commands.first?.contains("remove") == true)
        #expect(runner.commands.last?.contains("prune") == true)
    }

    @Test("Cesta, která worktree není, úklid neshodí")
    func removingSomethingThatIsNotAWorktreeIsFine() async throws {
        // `git worktree remove` na takovou cestu vrátí 128 (`is not a working tree`).
        // Stav se musí dát srovnat, ne zaseknout.
        try makeCompleteClone()
        let runner = ScriptedProcessRunner(exitCodes: [128, 0])

        try await checkout(runner).removeWorktree(for: pr, at: headSha)

        #expect(runner.commands.last?.contains("prune") == true)
    }
}

extension WorktreeTests {
    @Test("Rozdělaný worktree se zahodí a založí znovu")
    func brokenWorktreeIsRebuilt() async throws {
        // Zabitý `worktree add` nechá složku i se zámkem `initializing`; `git` v ní na
        // `rev-parse` neodpoví. Bez tohohle by aplikace vydala uříznutý strom jako hotový.
        try makeCompleteClone()
        try FileManager.default.createDirectory(
            at: layout.worktree(for: pr, at: headSha),
            withIntermediateDirectories: true
        )
        // rev-parse selže, remove, prune, fetch, cat-file, add
        let runner = ScriptedProcessRunner(exitCodes: [128, 0, 0, 0, 0, 0])

        _ = try await checkout(runner).worktree(for: pr, at: headSha)

        #expect(runner.commands.contains { $0.contains("remove") })
        #expect(runner.commands.last?.contains("add") == true)
    }
}
