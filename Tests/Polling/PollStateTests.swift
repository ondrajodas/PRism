import Foundation
import Testing

@testable import PRism

@Suite("PollState – co ukázat místo prázdného seznamu")
struct PollStateTests {
    private let network = GitHubError.network("error connecting to api.github.com")
    private let loaded = Date(timeIntervalSince1970: 1_000_000)
    private let retryAt = Date(timeIntervalSince1970: 1_000_120)

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier("cli/cli#1")!,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: loaded,
            state: .open
        )
    }

    @Test("Když jsou PR, není co řešit")
    func nothingToExplainWhenListHasContent() {
        let state = PollState(pullRequests: [summary()], status: .upToDate, lastSuccess: loaded)

        #expect(state.emptyReason == nil)
    }

    @Test("Před prvním doběhnutím se načítá")
    func emptyBeforeFirstRunIsLoading() {
        #expect(PollState().emptyReason == .loading)
    }

    @Test("Prázdno po úspěšném dotazu znamená, že žádné PR nejsou")
    func emptyAfterSuccessMeansNoPullRequests() {
        let state = PollState(status: .upToDate, lastSuccess: loaded)

        #expect(state.emptyReason == .noPullRequests)
    }

    @Test("Prázdno kvůli chybě není totéž co prázdno bez PR")
    func emptyBecauseOfFailureIsAFailure() {
        // Jinak by se u červeného banneru svítilo zelené „Žádné PR k review“.
        let state = PollState(status: .failing(since: loaded, reason: network))

        #expect(state.emptyReason == .failure(network))
    }

    @Test("Prázdno kvůli rate limitu řekne, kdy to zkusí znovu")
    func emptyBecauseOfRateLimitCarriesRetryTime() {
        let state = PollState(status: .rateLimited(since: loaded, retryAt: retryAt))

        #expect(state.emptyReason == .rateLimited(retryAt: retryAt))
    }

    @Test("Když už se to jednou povedlo, je prázdno prostě prázdno")
    func failureAfterASuccessfulLoadStillMeansNoPullRequests() {
        // Data jsme dostali a byla prázdná; že se teď obnovení nedaří, říká banner.
        let state = PollState(status: .failing(since: loaded, reason: network), lastSuccess: loaded)

        #expect(state.emptyReason == .noPullRequests)
    }
}
