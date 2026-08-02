import Foundation
import Testing

@testable import PRism

/// Nález, jehož řádek v diffu není, si svůj kód dotáhne sám.
///
/// Čekat u něj na kliknutí je přesně ten případ, kdy to nejvíc stojí: bublina mluví
/// o řádku 10 a řádek 10 nikde není.
@Suite("AppStore — dotažení kódu k nálezům")
@MainActor
struct AppStoreAutoRevealTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    /// Zdroje i sada skillů se berou z konfigurace, takže si ji test postaví.
    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }
    private let pr = PRIdentifier("cli/cli#1")!

    /// Diff mění řádek 2; nález na řádku 10 tedy v diffu není.
    private let diff = """
        diff --git a/App/Main.swift b/App/Main.swift
        --- a/App/Main.swift
        +++ b/App/Main.swift
        @@ -1,3 +1,3 @@
         první
        -druhý starý
        +druhý nový
         třetí
        """

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func finding(file: String = "App/Main.swift", line: Int?) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález",
                failureScenario: nil
            ),
            reviewer: "code-review",
            headSha: "abc"
        )
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "abc",
            baseSha: "base",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Nálezy vznikají skutečnou cestou — během reviewera. Testovací zadní vrátka do
    /// store by ověřovala cestu, kterou aplikace nikdy nepoužije.
    private func store(_ gateway: FakeGitHubGateway, reporting findings: [Finding]) throws -> AppStore {
        let workspace = try TemporaryDirectory()
        return AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: FakeReviewRunner(findings: findings.map(\.reported)),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url)),
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        for _ in 0..<400 where store.isReviewing(pr) {
            await Task.yield()
        }
    }

    private func waitForFile(_ gateway: FakeGitHubGateway) async {
        for _ in 0..<400 where gateway.fileRequests.isEmpty {
            await Task.yield()
        }
    }

    @Test("Nález mimo hunky si dotáhne okolí sám")
    func revealsTheCodeAroundAFindingOutsideTheDiff() async throws {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            detail: .success(detail()),
            diffs: [.success(diff)],
            files: [.success((1...20).map { "řádek \($0)" }.joined(separator: "\n"))]
        )
        let store = try store(gateway, reporting: [finding(line: 10)])
        await runReview(store)

        await store.loadDiff(for: summary())
        await waitForFile(gateway)
        for _ in 0..<400 where store.expansion(of: "App/Main.swift", in: pr).revealed.ranges.isEmpty {
            await Task.yield()
        }

        #expect(gateway.fileRequests.map(\.path) == ["App/Main.swift"])
        // Řádek nálezu a pár okolo — samotný řádek bez kontextu se čte špatně.
        let revealed = store.expansion(of: "App/Main.swift", in: pr).revealed
        #expect(revealed.ranges.first?.contains(10) == true)
        #expect(revealed.ranges.first?.contains(7) == true)
    }

    @Test("Nález, který v diffu je, se netahá")
    func leavesAFindingInsideTheDiffAlone() async throws {
        let gateway = FakeGitHubGateway(always: .success([]), detail: .success(detail()), diffs: [.success(diff)], files: [.success("x")])
        let store = try store(gateway, reporting: [finding(line: 2)])
        await runReview(store)

        await store.loadDiff(for: summary())
        for _ in 0..<200 { await Task.yield() }

        #expect(gateway.fileRequests.isEmpty)
    }

    @Test("Nález bez řádku nemá co dotahovat")
    func leavesAFindingWithoutALineAlone() async throws {
        let gateway = FakeGitHubGateway(always: .success([]), detail: .success(detail()), diffs: [.success(diff)], files: [.success("x")])
        let store = try store(gateway, reporting: [finding(line: nil)])
        await runReview(store)

        await store.loadDiff(for: summary())
        for _ in 0..<200 { await Task.yield() }

        #expect(gateway.fileRequests.isEmpty)
    }

    @Test("Nález na souboru, který v diffu není, nic nestahuje")
    func leavesAFindingOnAnUnknownFileAlone() async throws {
        let gateway = FakeGitHubGateway(always: .success([]), detail: .success(detail()), diffs: [.success(diff)], files: [.success("x")])
        let store = try store(gateway, reporting: [finding(file: "Jinde.swift", line: 3)])
        await runReview(store)

        await store.loadDiff(for: summary())
        for _ in 0..<200 { await Task.yield() }

        #expect(gateway.fileRequests.isEmpty)
    }

    /// Reviewer umí nahlásit řádek, který v souboru není. Odkrýt ho by znamenalo kotvu na
    /// řádek, který se nikdy nevykreslí — tedy skok, po kterém se nic nestane.
    @Test("Řádek za koncem souboru se neodkryje")
    func neverRevealsALineBeyondTheEndOfTheFile() async throws {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            detail: .success(detail()),
            diffs: [.success(diff)],
            files: [.success((1...20).map { "řádek \($0)" }.joined(separator: "\n"))]
        )
        let store = try store(gateway, reporting: [finding(line: 9999)])
        await runReview(store)

        await store.loadDiff(for: summary())
        for _ in 0..<400 where store.expansion(of: "App/Main.swift", in: pr).content.isEmpty {
            await Task.yield()
        }

        let revealed = store.expansion(of: "App/Main.swift", in: pr).revealed
        #expect(!revealed.ranges.contains { $0.contains(9999) })
    }

    /// Dva nálezy v jednom souboru spustí načtení jednou — a **oba** rozsahy musí přežít.
    @Test("Druhý nález se během načítání neztratí")
    func keepsTheSecondRangeRequestedWhileLoading() async throws {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            detail: .success(detail()),
            diffs: [.success(diff)],
            files: [.success((1...40).map { "řádek \($0)" }.joined(separator: "\n"))]
        )
        let store = try store(gateway, reporting: [finding(line: 10), finding(line: 30)])
        await runReview(store)

        await store.loadDiff(for: summary())
        for _ in 0..<400 where store.expansion(of: "App/Main.swift", in: pr).content.isEmpty {
            await Task.yield()
        }

        #expect(gateway.fileRequests.count == 1)
        let revealed = store.expansion(of: "App/Main.swift", in: pr).revealed
        #expect(revealed.ranges.contains { $0.contains(10) })
        #expect(revealed.ranges.contains { $0.contains(30) })
    }
}
