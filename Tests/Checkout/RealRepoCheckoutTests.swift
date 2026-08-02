import Foundation
import Testing

@testable import PRism

/// Proti skutečnému `gitu` a skutečnému repozitáři na disku — bez sítě, remote je `file://`.
///
/// Fake runner ověří, jaké argumenty se posílají; tohle ověří, že jim `git` rozumí a že
/// z toho vznikne použitelný klon. Ta druhá půlka se namockovat nedá.
@Suite("RepoCheckout proti skutečnému gitu")
struct RealRepoCheckoutTests {
    /// Systémový `git`, ne `KnownPath.git`: tenhle test binárku skutečně spouští, a
    /// `/usr/bin/git` je na macOS vždycky — homebrew instalace být nemusí.
    private let git = URL(filePath: "/usr/bin/git")
    private let runner = SubprocessRunner()
    private let repo = RepoID(owner: "scratch", name: "sample")

    /// Pracovní složka **musí** být uložená v suite, ne lokální proměnná v testu.
    /// `TemporaryDirectory` se maže v `deinit`, takže lokální proměnná umí zmizet hned po
    /// posledním použití — a smazat složku `gitu` pod rukama uprostřed klonování. Projeví
    /// se to jako náhodně visící test, ne jako chyba.
    private let workspace: TemporaryDirectory
    private let origin: URL
    private let layout: CacheLayout

    init() throws {
        workspace = try TemporaryDirectory()
        origin = workspace.url.appending(path: "origin")
        layout = CacheLayout(root: workspace.url.appending(path: "cache"))
    }

    private func checkout(remote: String) -> GitRepoCheckout {
        GitRepoCheckout(
            git: git,
            gh: URL(filePath: "/usr/bin/false"),
            layout: layout,
            runner: runner,
            // `file://`, ne holá cesta: u holé cesty `git` vypíše
            // `--filter is ignored in local clones`, udělá klon s hardlinky a přenosový
            // protokol vůbec nepoužije. Test by pak nejel tou cestou kódu co aplikace.
            remote: { _ in remote }
        )
    }

    @Test("První příprava naklonuje, druhá jen dotáhne nové commity")
    func clonesThenFetches() async throws {
        try await makeScratchRepository(at: origin)
        let checkout = checkout(remote: origin.absoluteString)

        let clone = try await checkout.prepare(repo)

        #expect(clone == layout.bareClone(for: repo))
        #expect(FileManager.default.fileExists(atPath: clone.appending(path: "HEAD").path))
        let firstHead = try await revision("main", in: clone)

        let secondCommit = try await commit("druhý", to: origin)
        #expect(secondCommit != firstHead)

        _ = try await checkout.prepare(repo)

        #expect(try await revision("main", in: clone) == secondCommit)
    }

    @Test("Přerušený klon se opraví sám, nezasekne se na něm")
    func recoversFromAnInterruptedClone() async throws {
        // Nasimulovaný zbytek po klonu, který nedoběhl: složka je, `HEAD` ne. Bez úklidu
        // by každý další pokus šel na `fetch` a padal na „not a git repository“.
        try await makeScratchRepository(at: origin)
        let leftover = layout.bareClone(for: repo)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try "smetí".write(to: leftover.appending(path: "config"), atomically: true, encoding: .utf8)

        let clone = try await checkout(remote: origin.absoluteString).prepare(repo)

        #expect(FileManager.default.fileExists(atPath: clone.appending(path: "HEAD").path))
        #expect(try await revision("main", in: clone).isEmpty == false)
    }

    @Test("Dva worktrees z jednoho klonu vedle sebe, úklid nechá klon čistý")
    func twoWorktreesSideBySide() async throws {
        let pr = PRIdentifier(repo: repo, number: 42)
        try await makeScratchRepository(at: origin)
        let firstCommit = try await revision("HEAD", in: origin)
        let secondCommit = try await commit("druhý", to: origin)

        let checkout = checkout(remote: origin.absoluteString)
        let clone = try await checkout.prepare(repo)

        let older = try await checkout.worktree(for: pr, at: firstCommit)
        let newer = try await checkout.worktree(for: pr, at: secondCommit)

        #expect(older != newer)
        #expect(try await revision("HEAD", in: older) == firstCommit)
        #expect(try await revision("HEAD", in: newer) == secondCommit)
        #expect(try await worktreeCount(in: clone) == 3) // bare klon + dva stromy

        try await checkout.removeWorktree(for: pr, at: firstCommit)
        try await checkout.removeWorktree(for: pr, at: secondCommit)

        #expect(FileManager.default.fileExists(atPath: older.path) == false)
        #expect(FileManager.default.fileExists(atPath: newer.path) == false)
        // Bez `prune` by tu zbyly záznamy o stromech, které už nejsou.
        #expect(try await worktreeCount(in: clone) == 1)
    }

    @Test("Commit mimo větve se dotáhne přes ref pull requestu")
    func fetchesCommitThatOnlyExistsUnderThePullRequestRef() async throws {
        // Přesně situace PR z forku: commit není v žádné větvi originu, drží ho jen
        // `refs/pull/<n>/head`. Klon ho tedy nemá a musí ho dotáhnout.
        let pr = PRIdentifier(repo: repo, number: 42)
        try await makeScratchRepository(at: origin)
        let hidden = try await makeCommitOutsideBranches(number: 42, in: origin)

        let checkout = checkout(remote: origin.absoluteString)
        let clone = try await checkout.prepare(repo)
        #expect(try await isMissing(hidden, in: clone))

        let worktree = try await checkout.worktree(for: pr, at: hidden)

        #expect(try await revision("HEAD", in: worktree) == hidden)
    }

    /// Commit, na který nevede žádná větev — dosažitelný jen přes `refs/pull/<n>/head`.
    private func makeCommitOutsideBranches(number: Int, in url: URL) async throws -> String {
        try await git(["checkout", "--detach"], in: url)
        let sha = try await commit("z forku", to: url)
        try await git(["update-ref", "refs/pull/\(number)/head", sha], in: url)
        try await git(["checkout", "main"], in: url)
        return sha
    }

    private func isMissing(_ sha: String, in clone: URL) async throws -> Bool {
        let result = try await runner.run(
            git,
            arguments: ["-C", clone.path(percentEncoded: false), "cat-file", "-e", "\(sha)^{commit}"],
            environment: ["GIT_NO_LAZY_FETCH": "1"],
            timeout: .seconds(30)
        )
        return result.exitCode != 0
    }

    @Test("Existující worktree se použije znovu")
    func worktreeIsReusedForTheSameCommit() async throws {
        // Dva skilly nad jedním PR sdílejí jeden checkout — druhý běh nesmí klonovat znovu.
        let pr = PRIdentifier(repo: repo, number: 42)
        try await makeScratchRepository(at: origin)
        let head = try await revision("HEAD", in: origin)
        let checkout = checkout(remote: origin.absoluteString)

        let first = try await checkout.worktree(for: pr, at: head)
        let second = try await checkout.worktree(for: pr, at: head)

        #expect(first == second)
        #expect(try await worktreeCount(in: layout.bareClone(for: repo)) == 2)
    }

    private func worktreeCount(in clone: URL) async throws -> Int {
        let result = try await runner.run(
            git,
            arguments: ["-C", clone.path(percentEncoded: false), "worktree", "list"],
            timeout: .seconds(30)
        )
        return result.standardOutput.split(separator: "\n").count
    }

    /// Výpis souborů se dá ověřit jen spuštěním: že `ls-files` v odpojeném stromu nad
    /// partial klonem vůbec něco vrátí, z argumentů poznat nejde. A na tom výpisu stojí
    /// odhad jazyka, tedy sada skillů, která se pak repu zapíše.
    @Test("Výpis verzovaných souborů vrátí obsah stromu, ne ignorované soubory")
    func listsTrackedFilesFromTheWorktree() async throws {
        let pr = PRIdentifier(repo: repo, number: 42)
        try await makeScratchRepository(at: origin)
        try "vendor/\n".write(to: origin.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: origin.appending(path: "src"),
            withIntermediateDirectories: true
        )
        try "<?php\n".write(to: origin.appending(path: "src/Cart.php"), atomically: true, encoding: .utf8)
        try await git(["add", "."], in: origin)
        try await git(["commit", "-m", "zdrojáky"], in: origin)
        let head = try await revision("HEAD", in: origin)
        let checkout = checkout(remote: origin.absoluteString)

        let worktree = try await checkout.worktree(for: pr, at: head)
        // Ignorovaná složka existuje jen na disku — ve výpisu být nesmí, jinak by odhad
        // jazyka převážily závislosti.
        try FileManager.default.createDirectory(
            at: worktree.appending(path: "vendor"),
            withIntermediateDirectories: true
        )
        try "x\n".write(to: worktree.appending(path: "vendor/balik.php"), atomically: true, encoding: .utf8)

        let files = try await checkout.trackedFiles(in: worktree)

        #expect(files.contains("src/Cart.php"))
        #expect(files.contains("README.md"))
        #expect(!files.contains { $0.hasPrefix("vendor/") })
    }

    @Test("Neexistující remote skončí zařazenou chybou, ne pádem")
    func missingRemoteIsClassified() async throws {
        let missing = workspace.url.appending(path: "nikde").absoluteString

        await #expect(throws: CheckoutError.self) {
            try await checkout(remote: missing).prepare(repo)
        }
    }

    // MARK: - Scratch repozitář

    private func makeScratchRepository(at url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try await git(["init", "--initial-branch=main"], in: url)
        try await git(["config", "user.email", "test@example.com"], in: url)
        try await git(["config", "user.name", "Test"], in: url)
        _ = try await commit("první", to: url)
    }

    @discardableResult
    private func commit(_ message: String, to url: URL) async throws -> String {
        try "\(message)\n".write(to: url.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try await git(["add", "README.md"], in: url)
        try await git(["commit", "-m", message], in: url)
        return try await revision("HEAD", in: url)
    }

    private func revision(_ name: String, in url: URL) async throws -> String {
        let result = try await runner.run(
            git,
            arguments: ["-C", url.path(percentEncoded: false), "rev-parse", name],
            timeout: .seconds(30)
        )
        #expect(result.exitCode == 0, "git rev-parse: \(result.standardError)")
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func git(_ arguments: [String], in url: URL) async throws {
        let result = try await runner.run(
            git,
            arguments: ["-C", url.path(percentEncoded: false)] + arguments,
            timeout: .seconds(30)
        )
        #expect(result.exitCode == 0, "git \(arguments.joined(separator: " ")): \(result.standardError)")
    }
}
