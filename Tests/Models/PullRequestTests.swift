import Foundation
import Testing

@testable import PRism

@Suite("PullRequest")
struct PullRequestTests {
    @Test("Přežije round-trip přes Codable")
    func survivesCodableRoundTrip() throws {
        let pr = Self.sample

        #expect(try roundTrip(pr) == pr)
    }

    @Test("Vystavuje repozitář a číslo z identifikátoru")
    func exposesRepoAndNumber() {
        #expect(Self.sample.repo == RepoID(owner: "ondrajodas", name: "PRism"))
        #expect(Self.sample.number == 12)
    }

    @Test(
        "Stav se kóduje čitelně",
        arguments: zip(
            PullRequestState.allCases,
            ["open", "draft", "merged", "closed"]
        )
    )
    func stateEncodesAsReadableString(state: PullRequestState, raw: String) throws {
        #expect(state.rawValue == raw)
        #expect(try roundTrip(state) == state)
    }

    @Test("Draft a otevřený jsou různé stavy")
    func draftIsDistinctFromOpen() {
        #expect(PullRequestState.draft != PullRequestState.open)
    }

    private static let sample = PullRequest(
        id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 12),
        title: "Doménové modely",
        author: "ondrajodas",
        headSha: "3fd94af2e1c4b8a9d0f6e5c4b3a29187f0e1d2c3",
        baseSha: "2e9a9e7f1b0c3d4e5a6b7c8d9e0f1a2b3c4d5e6f",
        url: URL(string: "https://github.com/ondrajodas/PRism/pull/12")!,
        updatedAt: Date(timeIntervalSince1970: 1_785_000_000),
        state: .open
    )
}
