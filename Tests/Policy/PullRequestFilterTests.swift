import Foundation
import Testing

@testable import PRism

/// Filtr seznamu PR (#117) — čisté funkce, takže vyčerpávajícím výčtem a bez mockování.
@Suite("Filtr seznamu PR")
struct PullRequestFilterTests {
    private func pullRequest(_ number: Int, repo: String = "cli/cli", author: String = "kdosi") -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: "PR \(number)",
            author: author,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            state: .open
        )
    }

    private func filter(repos: [String] = [], authors: [String] = []) -> PullRequestFilter {
        PullRequestFilter(
            repositories: Set(repos.compactMap { RepoID($0) }),
            authors: Set(authors)
        )
    }

    // MARK: - Filtrování

    /// **Prázdný filtr propustí všechno**, ne nic. Obráceně než u prázdného seznamu skillů —
    /// filtr, který po prvním spuštění neukazuje nic, je rozbitá aplikace.
    @Test("Prázdný filtr propustí všechno")
    func passesEverythingWhenEmpty() {
        let list = [pullRequest(1), pullRequest(2, repo: "ondrajodas/PRism")]

        #expect(Policy.filtered(list, by: PullRequestFilter()).count == 2)
        #expect(!PullRequestFilter().isActive)
    }

    /// Uvnitř osy **sjednocení**: dvě repa znamenají „obojí“.
    @Test("Dvě repa dají sjednocení")
    func unionsWithinAnAxis() {
        let list = [
            pullRequest(1),
            pullRequest(2, repo: "ondrajodas/PRism"),
            pullRequest(3, repo: "keboola/job-queue"),
        ]

        let result = Policy.filtered(list, by: filter(repos: ["cli/cli", "ondrajodas/PRism"]))

        #expect(result.map(\.number) == [1, 2])
    }

    @Test("Dva autoři dají sjednocení")
    func unionsAuthors() {
        let list = [
            pullRequest(1, author: "první"),
            pullRequest(2, author: "druhý"),
            pullRequest(3, author: "třetí"),
        ]

        let result = Policy.filtered(list, by: filter(authors: ["první", "třetí"]))

        #expect(result.map(\.number) == [1, 3])
    }

    /// Mezi osami **průsečík**: repo + autor znamená „jeho PR v tomhle repu“.
    @Test("Repo a autor dají průsečík")
    func intersectsAcrossAxes() {
        let list = [
            pullRequest(1, repo: "cli/cli", author: "první"),
            pullRequest(2, repo: "cli/cli", author: "druhý"),
            pullRequest(3, repo: "ondrajodas/PRism", author: "první"),
        ]

        let result = Policy.filtered(list, by: filter(repos: ["cli/cli"], authors: ["první"]))

        #expect(result.map(\.number) == [1])
    }

    /// **Filtr na hodnotu, která v seznamu není, dá prázdno — ne všechno.** Kdyby propustil
    /// všechno, „schoval jsem si všechno“ by vypadalo jako „nic jsem neschoval“.
    @Test("Filtr na neexistující hodnotu dá prázdno")
    func yieldsNothingForAnUnknownValue() {
        let list = [pullRequest(1)]

        #expect(Policy.filtered(list, by: filter(repos: ["kdesi/jinde"])).isEmpty)
        #expect(Policy.filtered(list, by: filter(authors: ["nikdo"])).isEmpty)
    }

    /// Filtr **nesahá na řazení** — pořadí je od naposledy změněného (#5).
    @Test("Pořadí zůstává, jak přišlo")
    func keepsTheOrder() {
        let list = [pullRequest(3), pullRequest(1), pullRequest(2)]

        let result = Policy.filtered(list, by: filter(repos: ["cli/cli"]))

        #expect(result.map(\.number) == [3, 1, 2])
    }

    // MARK: - Nabídka hodnot

    @Test("Nabídka je z plného seznamu a řazená")
    func offersValuesFromTheFullList() {
        let list = [
            pullRequest(1, repo: "ondrajodas/PRism", author: "béta"),
            pullRequest(2, repo: "cli/cli", author: "alfa"),
        ]

        let options = Policy.filterOptions(in: list, filter: PullRequestFilter())

        #expect(options.repositories.map(\.description) == ["cli/cli", "ondrajodas/PRism"])
        #expect(options.authors == ["alfa", "béta"])
    }

    /// **Nejcennější test nabídky.** Bez sjednocení s aktivním filtrem zmizí odškrtávátko u repa,
    /// jehož PR se zavřelo — a filtr zůstane aktivní bez cesty zpátky.
    @Test("Nabídka drží hodnoty aktivního filtru, i když jejich PR zmizel")
    func keepsActiveFilterValuesInTheOptions() {
        let list = [pullRequest(1, repo: "cli/cli", author: "zbylý")]
        let active = filter(repos: ["zmizelo/repo"], authors: ["zmizelý"])

        let options = Policy.filterOptions(in: list, filter: active)

        #expect(options.repositories.map(\.description) == ["cli/cli", "zmizelo/repo"])
        #expect(options.authors == ["zbylý", "zmizelý"])
    }

    @Test("Prázdný seznam bez filtru nemá co nabídnout")
    func offersNothingForAnEmptyList() {
        #expect(Policy.filterOptions(in: [], filter: PullRequestFilter()).isEmpty)
    }

    @Test("Nabídka se neduplikuje, když má víc PR totéž repo")
    func deduplicatesOptions() {
        let list = [pullRequest(1), pullRequest(2), pullRequest(3, author: "jiný")]

        let options = Policy.filterOptions(in: list, filter: PullRequestFilter())

        #expect(options.repositories.count == 1)
        #expect(options.authors == ["jiný", "kdosi"])
    }

    // MARK: - Proč je seznam prázdný

    @Test("Neprázdný viditelný seznam žádný důvod nedá")
    func hasNoReasonWhenSomethingIsVisible() {
        #expect(Policy.listEmptyReason(poll: nil, visible: 2, hidden: 1) == nil)
    }

    /// Prázdný výsledek filtru má **vlastní** důvod, ne `noPullRequests`.
    @Test("Všechno schované filtrem dá vlastní důvod")
    func reportsTheFilterWhenItHidesEverything() {
        #expect(Policy.listEmptyReason(poll: nil, visible: 0, hidden: 3) == .filtered(hidden: 3))
    }

    /// **Pořadí důvodů se nesmí prohodit.** Nad selhaným tikem se hlásí chyba načtení, ne filtr:
    /// „schoval jsem ti to filtrem“ nad daty, která nedorazila, je nepravda.
    @Test("Nad selhaným tikem vyhrává chyba načtení, ne filtr")
    func prefersThePollFailureOverTheFilter() {
        let failure = PollEmptyReason.failure(.commandFailed(exitCode: 1, message: "bum"))

        #expect(Policy.listEmptyReason(poll: failure, visible: 0, hidden: 3) == .poll(failure))
        #expect(Policy.listEmptyReason(poll: .loading, visible: 0, hidden: 3) == .poll(.loading))
    }

    /// Prázdno bez filtru zůstává `noPullRequests` — tedy tím zeleným „všechno vyřízeno“.
    @Test("Prázdno bez filtru je pořád prázdno")
    func keepsTheEmptyReasonWithoutAFilter() {
        #expect(Policy.listEmptyReason(poll: .noPullRequests, visible: 0, hidden: 0) == .poll(.noPullRequests))
    }
}
