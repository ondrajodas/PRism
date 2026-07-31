import Foundation
import Testing

@testable import PRism

@Suite("PullRequestSummary")
struct PullRequestSummaryTests {
    private let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .draft
    )

    @Test("Přežije cestu na disk a zpět")
    func survivesRoundTrip() throws {
        #expect(try roundTrip(summary) == summary)
    }

    @Test("Identifikátor je v JSONu řetězec")
    func encodesIdentifierAsString() throws {
        #expect(try encodedJSON(summary).contains("\"id\":\"cli\\/cli#14013\""))
    }

    @Test("Repo a číslo se čtou z identifikátoru")
    func exposesRepoAndNumber() {
        #expect(summary.repo == RepoID(owner: "cli", name: "cli"))
        #expect(summary.number == 14013)
    }
}
