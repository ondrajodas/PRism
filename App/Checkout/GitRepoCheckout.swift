import Foundation

/// `RepoCheckout` nad `git` CLI.
struct GitRepoCheckout: RepoCheckout {
    private let git: URL
    private let gh: URL
    private let layout: CacheLayout
    private let runner: ProcessRunning
    private let timeout: Duration
    private let remote: @Sendable (RepoID) -> String

    /// `remote` je švih pro integrační testy — ty klonují z `file://` scratch repa, aby
    /// nepotřebovaly síť ani přihlášení.
    init(
        git: URL,
        gh: URL,
        layout: CacheLayout = .applicationSupport,
        runner: ProcessRunning,
        timeout: Duration = .seconds(300),
        remote: @escaping @Sendable (RepoID) -> String = { "https://github.com/\($0).git" }
    ) {
        self.git = git
        self.gh = gh
        self.layout = layout
        self.runner = runner
        self.timeout = timeout
        self.remote = remote
    }

    func prepare(_ repo: RepoID) async throws -> URL {
        let clone = layout.bareClone(for: repo)

        if hasUsableClone(for: repo) {
            try await run(fetchArguments(in: clone))
            return clone
        }

        // Cílová složka může existovat i po **přerušeném** klonu — `git` po sobě neuklidí
        // vždycky a náš timeout ho zabíjí `SIGKILL`em, takže na to není spoleh. Rozhodovat
        // se podle pouhé existence složky by znamenalo, že další pokus jde na `fetch`
        // v něčem, co repozitář není, a opakování by se z toho nikdy nezotavilo.
        try? FileManager.default.removeItem(at: clone)
        try createParentDirectory(of: clone)
        try await run(cloneArguments(from: repo, into: clone))
        markCloneComplete(repo)
        return clone
    }

    /// Hotový klon poznáme podle **vlastní značky**, ne podle toho, co je uvnitř.
    /// `git` zakládá `HEAD`, `config` i `refs/` hned na začátku, takže zabitý klon vypadá
    /// zvenčí jako hotový repozitář — a fetch nad ním dokonce projde, jen z klonu tiše
    /// zmizí `promisor` a partial clone přestane platit.
    private func hasUsableClone(for repo: RepoID) -> Bool {
        FileManager.default.fileExists(
            atPath: layout.cloneMarker(for: repo).path(percentEncoded: false)
        )
    }

    /// Nezdařený zápis značky přípravu neshodí. Klon se povedl a je použitelný; chybějící
    /// značka znamená jen to, že se příště naklonuje znovu — což je nepříjemné, ne špatně.
    /// Opačné pořadí (shodit hotový klon kvůli souboru navíc) by bylo horší.
    private func markCloneComplete(_ repo: RepoID) {
        FileManager.default.createFile(
            atPath: layout.cloneMarker(for: repo).path(percentEncoded: false),
            contents: nil
        )
    }

    /// Partial clone: `--filter=blob:none` stáhne historii bez obsahu souborů a bloby
    /// doplní až na vyžádání. I velký monorepo se tím naklonuje v sekundách.
    private func cloneArguments(from repo: RepoID, into clone: URL) -> [String] {
        credentialConfiguration + [
            "clone", "--bare", "--filter=blob:none",
            remote(repo),
            clone.path(percentEncoded: false),
        ]
    }

    /// Refspec se musí napsat ručně. `git clone --bare` totiž **nenastaví**
    /// `remote.origin.fetch` (na rozdíl od běžného klonu i od `--mirror`), takže samotné
    /// `git fetch origin` jen zapíše `FETCH_HEAD` a větve v klonu zůstanou tam, kde byly.
    /// Odhalil to až integrační test proti skutečnému `gitu`.
    private func fetchArguments(in clone: URL) -> [String] {
        ["-C", clone.path(percentEncoded: false)] + credentialConfiguration + [
            "fetch", "--prune", "origin", "+refs/heads/*:refs/heads/*",
        ]
    }

    /// Přihlášení k privátním repům se deleguje na `gh`, stejně jako všude jinde —
    /// aplikace token nedrží.
    ///
    /// Helper se předává jako `-c` u jednoho volání, ne přes `gh auth setup-git`: ten
    /// zapisuje do **globálního** git configu uživatele, a do toho aplikace sahat nemá.
    /// `gh` se volá absolutní cestou, protože helper spouští shell, který `PATH`
    /// z GUI aplikace nezdědil.
    private var credentialConfiguration: [String] {
        ["-c", "credential.helper=!'\(gh.path(percentEncoded: false))' auth git-credential"]
    }

    /// Bez toho by se `git` na chybějící heslo zeptal a čekal — podproces bez terminálu
    /// by na tom visel až do timeoutu.
    private var environment: [String: String] {
        ["GIT_TERMINAL_PROMPT": "0"]
    }

    private func createParentDirectory(of clone: URL) throws {
        try FileManager.default.createDirectory(
            at: clone.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func run(_ arguments: [String]) async throws {
        let result: ProcessResult
        do {
            result = try await runner.run(
                git,
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
        } catch ProcessError.timedOut {
            throw CheckoutError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw CheckoutError.toolUnavailable(detail)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CheckoutError.toolUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else { throw CheckoutError(failure: result) }
    }
}
