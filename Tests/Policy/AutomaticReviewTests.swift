import Foundation
import Testing

@testable import PRism

/// Koho automat vybere. Čistá funkce — rozpočet ani spouštění sem nepatří.
@Suite("Policy — automatický režim")
struct AutomaticReviewTests {
    private let cli = RepoID(owner: "cli", name: "cli")

    private func summary(
        _ identifier: String,
        updatedAt: TimeInterval = 100,
        state: PullRequestState = .open
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: state
        )
    }

    private func configuration(automatic: Bool) -> Configuration {
        var configuration = Configuration.standard
        configuration.repositories = [cli: RepositoryConfig(mode: automatic ? .automatic : .manual)]
        return configuration
    }

    private func pick(
        _ summaries: [PullRequestSummary],
        automatic: Bool = true,
        considered: [PRIdentifier: Date] = [:],
        running: Set<PRIdentifier> = []
    ) -> [PRIdentifier] {
        Policy.automaticallyReviewable(
            in: summaries,
            configuration: configuration(automatic: automatic),
            considered: considered,
            running: running
        )
    }

    @Test("Repo v automatickém režimu se vybere")
    func picksAutomaticRepositories() {
        #expect(pick([summary("cli/cli#1")]) == [PRIdentifier("cli/cli#1")])
    }

    /// Neznámé repo nesmí bez dozoru spálit panel session — proto je výchozí `manual`.
    @Test("Manuální repo se nevybere")
    func skipsManualRepositories() {
        #expect(pick([summary("cli/cli#1")], automatic: false).isEmpty)
    }

    /// Stejný stav podruhé znamená, že se od minula nic nezměnilo.
    @Test("Už zvážený PR se stejným updatedAt se nevybere")
    func skipsWhatWasAlreadyConsidered() {
        let considered = [PRIdentifier("cli/cli#1")!: Date(timeIntervalSince1970: 100)]

        #expect(pick([summary("cli/cli#1", updatedAt: 100)], considered: considered).isEmpty)
    }

    @Test("Změněný PR se vybere znovu")
    func picksUpAChange() {
        let considered = [PRIdentifier("cli/cli#1")!: Date(timeIntervalSince1970: 100)]

        #expect(pick([summary("cli/cli#1", updatedAt: 200)], considered: considered).count == 1)
    }

    @Test("PR, nad kterým už něco běží, se nevybere")
    func skipsRunningPullRequests() {
        #expect(pick([summary("cli/cli#1")], running: [PRIdentifier("cli/cli#1")!]).isEmpty)
    }

    /// Autor na draftu ještě pracuje a každý push by stál session. Ruční spuštění zůstává.
    @Test("Draft se sám nereviewuje")
    func skipsDrafts() {
        #expect(pick([summary("cli/cli#1", state: .draft)]).isEmpty)
    }

    /// Vybírá se z posledního tiku, takže zavřený PR vypadne tím, že v seznamu není.
    @Test("Prázdný seznam nevybere nic")
    func picksNothingFromAnEmptyList() {
        #expect(pick([]).isEmpty)
    }
}
