import Foundation
import Testing

@testable import PRism

/// Překlad nálezů po doběhnutí běhu. Fake překladač, **skutečný** `ReviewStore` nad
/// dočasnou složkou — on rozhoduje, co se objeví po restartu.
@Suite("AppStore — překlad nálezů")
@MainActor
struct AppStoreTranslationTests {
    /// Přeloží každý nález na „CZ: <originál>“, nebo selže, když si o to test řekne.
    final class FakeTranslator: FindingTranslating, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [FindingsLanguage] = []
        private let failure: (any Error)?
        /// Který nález se přeložit nepodaří — na tom se pozná, že ostatní projdou.
        private let skipping: Int?

        init(failing: (any Error)? = nil, skipping: Int? = nil) {
            failure = failing
            self.skipping = skipping
        }

        var languages: [FindingsLanguage] { lock.withLock { recorded } }

        func translate(
            _ findings: [ReportedFinding],
            to language: FindingsLanguage
        ) async throws -> [FindingTranslation?] {
            lock.withLock { recorded.append(language) }
            if let failure { throw failure }
            return findings.enumerated().map { index, finding in
                index == skipping ? nil : FindingTranslation(summary: "CZ: \(finding.summary)")
            }
        }
    }

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

    private func finding(_ summary: String) -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: summary,
            failureScenario: nil
        )
    }

    private func store(
        findings: [ReportedFinding],
        translator: FakeTranslator?,
        language: FindingsLanguage = .czech
    ) async throws -> AppStore {
        var configuration = Configuration.standard
        configuration.global.findingsLanguage = language
        try await ConfigStore(layout: layout).save(configuration)

        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            translator: translator
        )
        await store.reloadConfiguration()
        return store
    }

    private func runReview(_ store: AppStore) async throws {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
        #expect(!store.isReviewing(pr))
    }

    @Test("Nálezy se po doběhnutí přeloží a uloží")
    func translatesAndStoresTheFindings() async throws {
        let store = try await store(findings: [finding("Total ignores quantity")], translator: FakeTranslator())

        try await runReview(store)

        #expect(store.reviewRecord(for: pr)?.findings.map(\.summary) == ["CZ: Total ignores quantity"])
        // Přežije to restart — překlad je na disku, ne jen v paměti.
        let reloaded = try await ReviewStore(layout: layout, time: FakeTimeSource()).load()
        let record = try #require(reloaded.records.first)
        #expect(record.findings.map(\.summary) == ["CZ: Total ignores quantity"])
        // A originál zůstal sáhnutelný.
        #expect(record.findings.map(\.reported.summary) == ["Total ignores quantity"])
    }

    /// Reviewer píše anglicky sám od sebe — volat kvůli tomu model by byla session za nic.
    @Test("Anglicky nastavené repo se nepřekládá")
    func skipsTranslationForEnglish() async throws {
        let translator = FakeTranslator()
        let store = try await store(
            findings: [finding("Total ignores quantity")],
            translator: translator,
            language: .english
        )

        try await runReview(store)

        #expect(translator.languages.isEmpty)
        #expect(store.reviewRecord(for: pr)?.findings.map(\.summary) == ["Total ignores quantity"])
    }

    @Test("Čisté review překladač neobtěžuje")
    func doesNotTranslateACleanRun() async throws {
        let translator = FakeTranslator()
        let store = try await store(findings: [], translator: translator)

        try await runReview(store)

        #expect(translator.languages.isEmpty)
        #expect(store.reviewState(for: pr) == .clean)
    }

    /// Selhání překladu review nepoloží: nálezy jsou uložené a v originále čitelné.
    @Test("Selhaný překlad nechá nálezy v originále")
    func aFailedTranslationKeepsTheOriginals() async throws {
        let store = try await store(
            findings: [finding("Total ignores quantity")],
            translator: FakeTranslator(failing: CocoaError(.fileNoSuchFile))
        )

        try await runReview(store)

        #expect(store.reviewState(for: pr) == .completed(findings: 1))
        #expect(store.reviewRecord(for: pr)?.findings.map(\.summary) == ["Total ignores quantity"])
    }

    /// Ztratit nález kvůli překladu je to nejhorší, co se tady může stát — nepřeložený
    /// musí projít vedle přeložených.
    @Test("Nepřeložený nález nezmizí vedle přeložených")
    func keepsAnUntranslatedFindingAlongsideTranslatedOnes() async throws {
        let store = try await store(
            findings: [finding("First"), finding("Second")],
            translator: FakeTranslator(skipping: 0)
        )

        try await runReview(store)

        #expect(store.reviewRecord(for: pr)?.findings.map(\.summary) == ["First", "CZ: Second"])
    }

    @Test("Překládá se do nastaveného jazyka")
    func usesTheConfiguredLanguage() async throws {
        let translator = FakeTranslator()
        let store = try await store(findings: [finding("A")], translator: translator)

        try await runReview(store)

        #expect(translator.languages == [.czech])
    }
}
