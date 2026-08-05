import Foundation
import Testing

@testable import PRism

/// Odmítnutí nálezů (#113) proti **skutečnému** `ReviewStore` nad dočasnou složkou — jde
/// právě o to, co po odmítnutí zbude na disku a co z něj vyjde po restartu.
@Suite("AppStore — odmítnuté nálezy")
@MainActor
struct AppStoreDismissalTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
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

    private func blocking(_ summary: String = "total() ignoruje množství") -> ReportedFinding {
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

    private func reviews() -> ReviewStore {
        ReviewStore(layout: layout, time: FakeTimeSource())
    }

    private func store(_ reviews: ReviewStore, findings: [ReportedFinding] = []) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: findings),
            reviews: reviews
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        for _ in 0..<100_000 where store.isReviewing(pr) { await Task.yield() }
    }

    @Test("Odmítnutí posune návrh verdiktu a přežije restart")
    func aDismissalMovesTheVerdictAndSurvivesARestart() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [blocking()])
        await runReview(store)
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)
        #expect(store.suggestedVerdict(for: pr) == .requestChanges)

        await store.dismissFinding(finding, as: .invalid, for: pr)

        #expect(store.suggestedVerdict(for: pr) == .approve)
        #expect(store.reviewRecord(for: pr)?.activeFindings.isEmpty == true)
        #expect(store.dismissalFailure == nil)

        // A hlavně: platí to i po restartu, protože rozhoduje disk.
        let restarted = self.store(reviews)
        await restarted.loadStoredReviews()
        #expect(restarted.suggestedVerdict(for: pr) == .approve)
        #expect(restarted.reviewRecord(for: pr)?.dismissedCount == 1)
    }

    @Test("Vrátit odmítnutí zruší")
    func restoringUndoesTheDismissal() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [blocking()])
        await runReview(store)
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)
        await store.dismissFinding(finding, as: .invalid, for: pr)

        await store.restoreFinding(finding, for: pr)

        #expect(store.suggestedVerdict(for: pr) == .requestChanges)
        let restarted = self.store(reviews)
        await restarted.loadStoredReviews()
        #expect(restarted.reviewRecord(for: pr)?.dismissals.isEmpty == true)
    }

    /// **Nejdůležitější test celého #113.** `ReviewRecord.replace(_:)` celý běh přepíše,
    /// takže kdyby označení bydlelo na `Finding`u, zmizelo by přesně v okamžiku, kdy se ten
    /// samý falešný nález vrátí.
    @Test("Opakované review týmž skillem odmítnutí nezahodí")
    func rerunningTheSameSkillKeepsTheDismissal() async throws {
        let reviews = reviews()
        let store = store(reviews, findings: [blocking()])
        await runReview(store)
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)
        await store.dismissFinding(finding, as: .invalid, for: pr)

        await runReview(store)

        #expect(store.reviewRecord(for: pr)?.findings.count == 1)
        #expect(store.reviewRecord(for: pr)?.activeFindings.isEmpty == true)
        #expect(store.suggestedVerdict(for: pr) == .approve)
    }

    /// `clean` znamená „reviewer nic nenašel“. „Našel a já to zamítl“ je jiné tvrzení, takže
    /// řádek nesmí vypadat stejně jako u PR, na kterém opravdu nic nebylo.
    @Test("Řádek seznamu po odmítnutí všeho není čistý")
    func theRowIsNotCleanAfterDismissingEverything() async throws {
        let store = store(reviews(), findings: [blocking()])
        await runReview(store)
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)

        await store.dismissFinding(finding, as: .irrelevant, for: pr)

        #expect(store.reviewState(for: pr) == .dismissed(findings: 1))
    }

    @Test("Zbylý nález v řádku zůstane")
    func theRemainingFindingStaysInTheRow() async throws {
        let store = store(reviews(), findings: [blocking("falešný"), blocking("platný")])
        await runReview(store)
        let record = try #require(store.reviewRecord(for: pr))
        let dismissed = try #require(record.findings.first { $0.summary == "falešný" })

        await store.dismissFinding(dismissed, as: .invalid, for: pr)

        #expect(store.reviewState(for: pr) == .completed(findings: 1))
    }

    /// Cizí nález je cizí věta, můj převzatý komentář je moje próza — jeden bit ji mazat
    /// nesmí. Vyjímá se v tabu `Moje review`.
    @Test("Odmítnutí nevyjme převzatý komentář z draftu")
    func aDismissalKeepsTheAdoptedComment() async throws {
        let store = store(reviews(), findings: [blocking()])
        await runReview(store)
        await store.loadDetail(for: summary())
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)
        store.adoptFinding(finding, for: pr)
        for _ in 0..<1000 { await Task.yield() }
        #expect(store.draft(for: pr) != nil)

        await store.dismissFinding(finding, as: .invalid, for: pr)

        #expect(store.draft(for: pr) != nil)
    }

    /// Neuložené odmítnutí se po restartu vrátí a nikdo nebude vědět proč — takže se selhání
    /// zápisu nesmí spolknout.
    @Test("Selhání zápisu je vidět")
    func aFailedWriteIsVisible() async throws {
        let store = store(reviews(), findings: [blocking()])
        await runReview(store)
        let finding = try #require(store.reviewRecord(for: pr)?.findings.first)
        // Záznam pod rukama zmizí — z pohledu storu je to tentýž stav jako neúspěšný zápis.
        try FileManager.default.removeItem(
            at: layout.reviewFile(for: pr, at: finding.headSha)
        )

        await store.dismissFinding(finding, as: .invalid, for: pr)

        #expect(store.dismissalFailure != nil)
        // A v paměti se nic nezměnilo: kdyby se mapa měnila před zápisem, odmítnutí by bylo
        // vidět a po restartu zmizelo.
        #expect(store.reviewRecord(for: pr)?.dismissals.isEmpty == true)
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }
}
