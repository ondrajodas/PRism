import Foundation
import Testing

@testable import PRism

@Suite("GitRepoCheckout")
struct GitRepoCheckoutTests {
    private let git = URL(filePath: KnownPath.git)
    private let gh = URL(filePath: KnownPath.gh)
    private let vault = RepoID(owner: "keboola", name: "vault")

    /// Vlastní kořen cache pro každý test — nic se nesmí potkat s tím, co má aplikace.
    ///
    /// Swift Testing dělá pro každý test novou instanci suite, takže tímhle dostane každý
    /// vlastní složku a uklidí se sama, až instance zmizí. `prepare(_:)` totiž na disk
    /// **opravdu zapisuje** (zakládá složky pro klon) a bez úklidu by v `/tmp` zůstávaly
    /// kostry cache po každém běhu testů.
    private let workspace: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        workspace = try TemporaryDirectory()
        layout = CacheLayout(root: workspace.url)
    }

    private func checkout(_ runner: ProcessRunning) -> GitRepoCheckout {
        GitRepoCheckout(git: git, gh: gh, layout: layout, runner: runner)
    }

    @Test("První příprava klonuje bare a bez blobů")
    func firstPrepareClonesBare() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        let path = try await checkout(runner).prepare(vault)

        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments.contains("clone"))
        #expect(arguments.contains("--bare"))
        #expect(arguments.contains("--filter=blob:none"))
        #expect(arguments.contains("https://github.com/keboola/vault.git"))
        #expect(arguments.last == path.path(percentEncoded: false))
        #expect(path == layout.bareClone(for: vault))
    }

    @Test("Přihlášení se deleguje na gh přes credential helper")
    func authenticationIsDelegatedToGh() async throws {
        // Aplikace token nedrží ani nesmí sahat na globální git config uživatele —
        // helper se předává jako parametr jednoho volání.
        let runner = FakeProcessRunner(exitCode: 0)

        _ = try await checkout(runner).prepare(vault)

        let arguments = try #require(runner.invocations.first?.arguments)
        let helper = try #require(arguments.first { $0.contains("credential.helper") })
        #expect(helper.contains(gh.path(percentEncoded: false)))
        #expect(helper.contains("auth git-credential"))
    }

    @Test("Git se nesmí zeptat na heslo a čekat")
    func gitNeverPromptsForCredentials() async throws {
        // Podproces bez terminálu by na dotazu visel až do timeoutu.
        let runner = FakeProcessRunner(exitCode: 0)

        _ = try await checkout(runner).prepare(vault)

        #expect(runner.invocations.first?.environment["GIT_TERMINAL_PROMPT"] == "0")
    }

    @Test("Existující klon se jen aktualizuje")
    func existingCloneIsFetched() async throws {
        try FileManager.default.createDirectory(
            at: layout.bareClone(for: vault),
            withIntermediateDirectories: true
        )
        let runner = FakeProcessRunner(exitCode: 0)

        _ = try await checkout(runner).prepare(vault)

        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments.contains("fetch"))
        #expect(!arguments.contains("clone"))
        // Bez explicitního refspecu by fetch v bare klonu neaktualizoval vůbec nic —
        // `git clone --bare` `remote.origin.fetch` nenastavuje.
        #expect(arguments.contains("+refs/heads/*:refs/heads/*"))
        // `-C` místo pracovní složky procesu: běhy se nesmí přebíjet.
        #expect(arguments.prefix(2) == ["-C", layout.bareClone(for: vault).path(percentEncoded: false)])
    }

    @Test("Chyba gitu se zařadí, ne jen předá")
    func gitFailureIsClassified() async {
        let stderr = "remote: Repository not found.\nfatal: repository not found"
        let runner = FakeProcessRunner(exitCode: 128, standardError: stderr)

        await #expect(throws: CheckoutError.repositoryNotFound(stderr)) {
            try await checkout(runner).prepare(vault)
        }
    }

    @Test("Timeout se od chyby gitu odliší")
    func timeoutIsItsOwnError() async {
        let runner = FakeProcessRunner(failing: .timedOut)

        await #expect(throws: CheckoutError.timedOut) {
            try await checkout(runner).prepare(vault)
        }
    }

    @Test("Nespustitelný git se od chyby gitu odliší taky")
    func launchFailureIsItsOwnError() async {
        let runner = FakeProcessRunner(failing: .launchFailed("Permission denied"))

        await #expect(throws: CheckoutError.toolUnavailable("Permission denied")) {
            try await checkout(runner).prepare(vault)
        }
    }
}
