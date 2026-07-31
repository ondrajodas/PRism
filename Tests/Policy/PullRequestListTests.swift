import Foundation
import Testing

@testable import PRism

@Suite("PullRequestList – slučování zdrojů")
struct PullRequestListTests {
    /// URL má tvar, jaký PR na GitHubu skutečně má. `owner/repo#číslo` je zápis pro nás,
    /// ne cesta — `#` by se v URL stal fragmentem a testovací data by přestala odpovídat
    /// tomu, co do modelu doopravdy přijde.
    private func summary(
        _ identifier: String,
        updatedAt: TimeInterval,
        title: String = "titulek"
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: title,
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    @Test("Stejný PR ze dvou zdrojů se objeví jednou")
    func deduplicatesAcrossSources() {
        let first = summary("cli/cli#1", updatedAt: 100)
        let second = summary("cli/cli#1", updatedAt: 100)

        let merged = PullRequestList.merged(from: [[first], [second]])

        #expect(merged.map(\.id) == [PRIdentifier("cli/cli#1")])
    }

    @Test("Při kolizi vyhrávají novější data")
    func newerDataWinsOnCollision() {
        let stale = summary("cli/cli#1", updatedAt: 100, title: "starý titulek")
        let fresh = summary("cli/cli#1", updatedAt: 200, title: "nový titulek")

        let merged = PullRequestList.merged(from: [[stale], [fresh]])

        #expect(merged.map(\.title) == ["nový titulek"])
    }

    @Test("Novější data vyhrají i když přijdou z prvního zdroje")
    func newerDataWinsRegardlessOfSourceOrder() {
        let fresh = summary("cli/cli#1", updatedAt: 200, title: "nový titulek")
        let stale = summary("cli/cli#1", updatedAt: 100, title: "starý titulek")

        let merged = PullRequestList.merged(from: [[fresh], [stale]])

        #expect(merged.map(\.title) == ["nový titulek"])
    }

    @Test("Různé PR zůstanou všechny")
    func keepsDistinctPullRequests() {
        let merged = PullRequestList.merged(from: [
            [summary("cli/cli#1", updatedAt: 100)],
            [summary("cli/go-gh#1", updatedAt: 200), summary("cli/cli#2", updatedAt: 300)],
        ])

        #expect(merged.count == 3)
    }

    @Test("Řadí se od naposledy změněného")
    func sortsByUpdatedAtDescending() {
        let merged = PullRequestList.merged(from: [[
            summary("cli/cli#1", updatedAt: 100),
            summary("cli/cli#3", updatedAt: 300),
            summary("cli/cli#2", updatedAt: 200),
        ]])

        #expect(merged.map(\.number) == [3, 2, 1])
    }

    @Test("Shodný čas změny nedovolí seznamu poskakovat")
    func equalTimestampsAreOrderedDeterministically() {
        // Bez druhého kritéria by se pořadí mezi pollingy měnilo a řádky by v seznamu
        // přeskakovaly pod rukou.
        let merged = PullRequestList.merged(from: [[
            summary("cli/go-gh#5", updatedAt: 100),
            summary("cli/cli#7", updatedAt: 100),
            summary("cli/cli#2", updatedAt: 100),
        ]])

        #expect(merged.map(\.id.description) == ["cli/cli#2", "cli/cli#7", "cli/go-gh#5"])
    }

    @Test("Prázdný zdroj nic nepokazí")
    func emptySourceIsHarmless() {
        let merged = PullRequestList.merged(from: [[], [summary("cli/cli#1", updatedAt: 100)], []])

        #expect(merged.map(\.id) == [PRIdentifier("cli/cli#1")])
    }

    @Test("Bez zdrojů je seznam prázdný")
    func noSourcesGiveEmptyList() {
        #expect(PullRequestList.merged(from: []).isEmpty)
    }
}
