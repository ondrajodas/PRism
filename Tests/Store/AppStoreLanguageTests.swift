import Foundation
import Testing

@testable import PRism

/// Odvození sady skillů z jazyka repa při **prvním** review. Fake checkout dodá výpis
/// souborů, skutečný `ConfigStore` nad dočasnou složkou rozhoduje, co v souboru zůstane.
@Suite("AppStore — jazyk repa")
@MainActor
struct AppStoreLanguageTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let repo = RepoID(owner: "cli", name: "cli")
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var detail: PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Konfigurace se zapíše na disk, aby ji store načetl stejnou cestou jako v provozu.
    private func store(
        files: Result<[String], CheckoutError> = .success([]),
        skillsByLanguage: [ProjectLanguage: [String]] = [:],
        repositories: [RepoID: RepositoryConfig] = [:]
    ) async throws -> AppStore {
        var configuration = Configuration.standard
        configuration.global.skillsByLanguage = skillsByLanguage
        configuration.repositories = repositories
        try await ConfigStore(layout: layout).save(configuration)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(files: files),
            reviewer: FakeReviewRunner(),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )
        await store.reloadConfiguration()
        return store
    }

    private func runReview(_ store: AppStore) async throws {
        store.startReview(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    @Test("Rozpoznaný jazyk zapíše sadu skillů k repu")
    func writesTheDetectedSetToTheRepository() async throws {
        let store = try await store(
            files: .success(["composer.json", "src/Cart.php"]),
            skillsByLanguage: [.php: ["code-review", "php-quality"]]
        )

        try await runReview(store)

        #expect(store.reviewSkills(for: repo) == ["code-review", "php-quality"])
        // A přežije to restart — v souboru, ne jen v paměti.
        let reloaded = await ConfigStore(layout: layout).load()
        #expect(reloaded.configuration.repositories[repo]?.skills == ["code-review", "php-quality"])
    }

    /// Zápis „stejné jako globální“ by byl override, o který nikdo nežádal — a pozdější
    /// změna globální sady by tenhle repo tiše minula.
    @Test("Sada shodná s globální se nezapisuje")
    func doesNotWriteWhatMatchesTheGlobalSet() async throws {
        let store = try await store(files: .success(["src/Cart.php"]))

        try await runReview(store)

        #expect(store.configuration.repositories[repo] == nil)
    }

    /// Ruční hodnota má přednost — a **i prázdná**. Přepsat ji by znamenalo vracet
    /// uživateli jeho rozhodnutí zpátky.
    @Test("Ruční sada se detekcí nepřepíše")
    func neverOverwritesAHandWrittenSet() async throws {
        let store = try await store(
            files: .success(["composer.json"]),
            skillsByLanguage: [.php: ["php-quality"]],
            repositories: [repo: RepositoryConfig(skills: ["moje"])]
        )

        try await runReview(store)

        #expect(store.reviewSkills(for: repo) == ["moje"])
    }

    @Test("Prázdná ruční sada se detekcí nepřepíše")
    func neverOverwritesADeliberateEmptySet() async throws {
        let store = try await store(
            files: .success(["composer.json"]),
            skillsByLanguage: [.php: ["php-quality"]],
            repositories: [repo: RepositoryConfig(skills: [])]
        )

        try await runReview(store)

        #expect(store.configuration.repositories[repo]?.skills == [])
    }

    /// Režim ani kategorie u repa se detekcí ztratit nesmí — zapisuje se jedna položka,
    /// ne celý záznam.
    @Test("Zápis sady nechá ostatní nastavení repa být")
    func keepsTheOtherRepositorySettings() async throws {
        let store = try await store(
            files: .success(["composer.json"]),
            skillsByLanguage: [.php: ["php-quality"]],
            repositories: [repo: RepositoryConfig(mode: .automatic, blockingCategories: ["security"])]
        )

        try await runReview(store)

        #expect(store.resolved(for: repo).mode == .automatic)
        #expect(store.resolved(for: repo).blockingCategories == ["security"])
        #expect(store.reviewSkills(for: repo) == ["php-quality"])
    }

    /// Nepovedený výpis znamená, že se sada neodvodí a poběží globální — tedy přesně to,
    /// co běželo před #24. Review kvůli tomu spadnout nesmí.
    @Test("Selhaný výpis souborů review nepoloží")
    func survivesAFailedFileListing() async throws {
        let store = try await store(
            files: .failure(.notAuthenticated("fatal: not a git repository")),
            skillsByLanguage: [.php: ["php-quality"]]
        )

        try await runReview(store)

        #expect(store.reviewState(for: pr) == .clean)
        #expect(store.configuration.repositories[repo] == nil)
    }

    /// Detekce musí proběhnout **před** spuštěním skillů, jinak by první review jelo se
    /// starou sadou a odvozená by se projevila až podruhé.
    @Test("Reviewer dostane rovnou odvozenou sadu")
    func runsTheDetectedSetRightAway() async throws {
        let reviewer = FakeReviewRunner()
        var configuration = Configuration.standard
        configuration.global.skillsByLanguage = [.go: ["go-review"]]
        try await ConfigStore(layout: layout).save(configuration)
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(files: .success(["go.mod", "main.go"])),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )
        await store.reloadConfiguration()

        try await runReview(store)

        #expect(reviewer.requests.map(\.key.skillID) == ["go-review"])
    }
}
