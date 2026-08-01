import Foundation
import Testing

@testable import PRism

/// Stejný princip jako u `GitHubError`: zařazení chyby je čistá funkce nad výsledkem
/// procesu, takže se dá projet tabulkou skutečných hlášek `gitu`.
@Suite("CheckoutError – klasifikace výstupu gitu")
struct CheckoutErrorTests {
    private func error(exitCode: Int32 = 128, stderr: String = "", stdout: String = "") -> CheckoutError {
        CheckoutError(
            failure: ProcessResult(exitCode: exitCode, standardOutput: stdout, standardError: stderr)
        )
    }

    @Test("Odmítnuté přihlášení")
    func authenticationFailure() {
        let stderr = "fatal: Authentication failed for 'https://github.com/keboola/vault.git/'"

        #expect(error(stderr: stderr) == .notAuthenticated(stderr))
    }

    @Test("Git se ptá na jméno, protože nemá terminál")
    func missingCredentialsIsAuthFailure() {
        let stderr = "fatal: could not read Username for 'https://github.com': terminal prompts disabled"

        #expect(error(stderr: stderr) == .notAuthenticated(stderr))
    }

    @Test("Nedostupný host je síť")
    func unresolvedHostIsNetwork() {
        let stderr = "fatal: unable to access 'https://github.com/x/y.git/': Could not resolve host: github.com"

        #expect(error(stderr: stderr) == .network(stderr))
    }

    @Test("Odmítnuté spojení je taky síť")
    func refusedConnectionIsNetwork() {
        let stderr = "fatal: unable to access 'https://github.com/x/y.git/': Failed to connect to github.com port 443"

        #expect(error(stderr: stderr) == .network(stderr))
    }

    @Test("Neexistující repozitář")
    func missingRepository() {
        let stderr = "remote: Repository not found.\nfatal: repository 'https://github.com/x/y.git/' not found"

        #expect(error(stderr: stderr) == .repositoryNotFound(stderr))
    }

    @Test("Nezařaditelná chyba si nese exit kód i text")
    func unknownFailureKeepsExitCodeAndText() {
        #expect(error(exitCode: 1, stderr: "něco se pokazilo") == .gitFailed(exitCode: 1, message: "něco se pokazilo"))
    }

    @Test("Když mlčí obojí, řekne alespoň exit kód")
    func reportsExitCodeWhenOutputIsEmpty() {
        #expect(error(exitCode: 9) == .gitFailed(exitCode: 9, message: "git skončil s kódem 9."))
    }
}
