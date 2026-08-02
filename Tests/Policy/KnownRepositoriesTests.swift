import Foundation
import Testing

@testable import PRism

/// Seznam repozitářů pro okno nastavení. Čistá funkce, nemockuje se nic.
@Suite("Policy — známé repozitáře")
struct KnownRepositoriesTests {
    private func summary(_ repo: String, _ number: Int) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier("\(repo)#\(number)")!,
            title: "Titulek",
            author: "kdokoli",
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 0),
            state: .open
        )
    }

    private func configuration(_ repos: String...) -> Configuration {
        var configuration = Configuration.standard
        configuration.repositories = Dictionary(
            uniqueKeysWithValues: repos.map { (RepoID($0)!, RepositoryConfig(mode: .automatic)) }
        )
        return configuration
    }

    @Test("Spojí repa ze seznamu PR a z konfigurace")
    func mergesBothSources() {
        let known = Policy.knownRepositories(
            in: [summary("cli/cli", 1), summary("cli/go-gh", 2)],
            configuration: configuration("ondrajodas/PRism")
        )

        #expect(known.map(\.description) == ["cli/cli", "cli/go-gh", "ondrajodas/PRism"])
    }

    /// Repo, na které zrovna nečeká PR, z okna zmizet nesmí — jinak se nedá vypnout
    /// nastavení, které dál platí.
    @Test("Repo bez otevřeného PR v seznamu zůstane")
    func keepsConfiguredRepositoriesWithoutPullRequests() {
        let known = Policy.knownRepositories(in: [], configuration: configuration("cli/cli"))

        #expect(known.map(\.description) == ["cli/cli"])
    }

    @Test("Repo ve dvou PR je v seznamu jednou")
    func deduplicates() {
        let known = Policy.knownRepositories(
            in: [summary("cli/cli", 1), summary("cli/cli", 2)],
            configuration: .standard
        )

        #expect(known.map(\.description) == ["cli/cli"])
    }

    /// Bez řazení by pořadí určoval slovník, tedy náhoda — a řádky by mezi překresleními
    /// poskakovaly.
    @Test("Řadí se podle jména bez ohledu na velikost písmen")
    func sortsCaseInsensitively() {
        let known = Policy.knownRepositories(
            in: [summary("zeta/one", 1), summary("Alpha/two", 2), summary("beta/three", 3)],
            configuration: .standard
        )

        #expect(known.map(\.description) == ["Alpha/two", "beta/three", "zeta/one"])
    }

    @Test("Bez PR i bez konfigurace je seznam prázdný")
    func emptyWhenThereIsNothing() {
        #expect(Policy.knownRepositories(in: [], configuration: .standard).isEmpty)
    }
}
