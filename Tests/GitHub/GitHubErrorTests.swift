import Foundation
import Testing

@testable import PRism

/// Klasifikace chyb `gh` je čistá funkce nad `ProcessResult`, takže se dá projet tabulkou
/// bez jediného podprocesu. Texty jsou skutečné výstupy `gh` (viz specifikace).
@Suite("GitHubError – klasifikace výstupu gh")
struct GitHubErrorTests {
    private func error(exitCode: Int32 = 1, stderr: String = "", stdout: String = "") -> GitHubError {
        GitHubError(
            failure: ProcessResult(exitCode: exitCode, standardOutput: stdout, standardError: stderr)
        )
    }

    @Test("Exit kód 4 znamená nepřihlášeno")
    func exitFourIsNotAuthenticated() {
        let stderr = """
            To get started with GitHub CLI, please run:  gh auth login
            Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
            """

        #expect(error(exitCode: 4, stderr: stderr) == .notAuthenticated)
    }

    @Test("Zamítnutý token je taky nepřihlášeno, i když exit kód je obyčejná jednička")
    func badCredentialsAreNotAuthenticated() {
        let stderr = "HTTP 401: Bad credentials (https://api.github.com/search/issues)"

        #expect(error(stderr: stderr) == .notAuthenticated)
    }

    @Test("Vyčerpaný rate limit se pozná a nese text")
    func rateLimitIsRecognised() {
        let stderr = "HTTP 403: API rate limit exceeded for user ID 12143866."

        #expect(error(stderr: stderr) == .rateLimited(stderr))
    }

    @Test("Sekundární rate limit se pozná taky")
    func secondaryRateLimitIsRecognised() {
        let stderr = "You have exceeded a secondary rate limit. Please wait a few minutes."

        #expect(error(stderr: stderr) == .rateLimited(stderr))
    }

    @Test("Nedostupná síť se odliší od chyby serveru")
    func connectionFailureIsNetwork() {
        let stderr = """
            error connecting to api.github.com
            check your internet connection or https://githubstatus.com
            """

        #expect(error(stderr: stderr) == .network(stderr))
    }

    @Test("Nepřeložené DNS je taky síť")
    func dnsFailureIsNetwork() {
        let stderr = "Get \"https://api.github.com\": dial tcp: lookup api.github.com: no such host"

        #expect(error(stderr: stderr) == .network(stderr))
    }

    @Test("Neexistující PR se pozná z GraphQL hlášky")
    func unknownPullRequestIsNotFound() {
        let stderr = "GraphQL: Could not resolve to a PullRequest with the number of 99999. (repository.pullRequest)"

        #expect(error(stderr: stderr) == .notFound(stderr))
    }

    @Test("HTTP 404 je taky nenalezeno")
    func httpNotFoundIsNotFound() {
        let stderr = "HTTP 404: Not Found (https://api.github.com/repos/ondrajodas/nope)"

        #expect(error(stderr: stderr) == .notFound(stderr))
    }

    @Test("Nezařaditelná chyba si nese exit kód i text")
    func unknownFailureKeepsExitCodeAndText() {
        #expect(error(exitCode: 2, stderr: "něco se pokazilo") == .commandFailed(exitCode: 2, message: "něco se pokazilo"))
    }

    @Test("Když stderr mlčí, vezme se stdout")
    func fallsBackToStandardOutput() {
        #expect(error(exitCode: 2, stdout: "unknown flag") == .commandFailed(exitCode: 2, message: "unknown flag"))
    }

    @Test("Když mlčí obojí, řekne alespoň exit kód")
    func reportsExitCodeWhenOutputIsEmpty() {
        #expect(error(exitCode: 9) == .commandFailed(exitCode: 9, message: "gh skončil s kódem 9."))
    }
}
