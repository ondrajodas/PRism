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
