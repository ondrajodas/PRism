import Foundation
import Testing

@testable import PRism

/// Notifikace o doběhlém review (#82) ze strany store: kdy se pošle a kdy ne.
///
/// Text skládá `Policy` a testuje se u ní; tady jde o **kdy**. To hlavní jsou dvě věci, které
/// se dají pokazit tiše: že za jedno review přijde **jedna** notifikace (ne jedna na skill)
/// a že se **zrušené review neoznamuje** — hláška o tom, co jsem právě sám zastavil, je
/// vyrušení za nic.
@Suite("AppStore — notifikace o doběhlém review")
@MainActor
struct AppStoreReviewNotificationTests {
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

    private func gateway(detail: Result<PullRequest, any Error>? = nil) -> FakeGitHubGateway {
        FakeGitHubGateway(always: .success([]), detail: detail ?? .success(self.detail))
    }

    /// Sada dvou skillů — na jedno review pak jedou dva běhy a je na čem ověřit, že
    /// notifikace přijde **jedna**.
    private var twoSkills: Configuration {
        var configuration = Configuration.standard
        configuration.global.skills = ["one", "two"]
        return configuration
    }

    private func store(
        gateway: FakeGitHubGateway,
        center: FakeNotificationCenter,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        checkout: FakeRepoCheckout = FakeRepoCheckout(),
        configuration: Configuration = .standard
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: checkout,
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            notifications: center
        )
    }

    private func finding(category: String = "correctness") -> ReportedFinding {
        ReportedFinding(
            file: "Cart.swift",
            line: 13,
            category: category,
            verdict: .confirmed,
            shortSummary: nil,
            summary: "total() ignoruje množství",
            failureScenario: nil
        )
    }

    private func waitUntilIdle(_ store: AppStore) async throws {
        for _ in 0 ..< 100_000 where store.isReviewing(pr) { await Task.yield() }
        #expect(!store.isReviewing(pr))
    }

    @Test("Doběhlé review s nálezy pošle jednu notifikaci")
    func notifiesAboutFindings() async throws {
        let center = FakeNotificationCenter()
        let store = store(
            gateway: gateway(),
            center: center,
            reviewer: FakeReviewRunner(findings: [finding()])
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.pullRequest == pr)
        #expect(center.delivered.first?.title == "1 nález · 1 blokuje")
        #expect(center.delivered.first?.body == "correctness: total() ignoruje množství\ncli/cli#42")
    }

    @Test("V notifikaci stojí ten nejzávažnější z nálezů")
    func namesTheMostSevereFinding() async throws {
        // Store musí do `Policy` poslat **nález i počet blokujících z téhož záznamu** (#200) —
        // jinak by titulek mluvil o blokujícím a řádek pod ním o kosmetice.
        let center = FakeNotificationCenter()
        let store = store(
            gateway: gateway(),
            center: center,
            reviewer: FakeReviewRunner(findings: [
                finding(category: "style"),
                finding(category: "correctness"),
            ])
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.first?.title == "2 nálezy · 1 blokuje")
        #expect(center.delivered.first?.body.hasPrefix("correctness: ") == true)
    }

    @Test("Dva skilly nad jedním PR dají jednu notifikaci, ne dvě")
    func notifiesOncePerPullRequest() async throws {
        // Reviewery jedou paralelně a tři notifikace za jedno PR jsou tři vyrušení za jednu
        // věc. Proto se posílá tam, kde se review **uzavírá**, ne u ukládání každého běhu —
        // jinak by přišlo „čisté“ a za minutu „3 nálezy“ za totéž PR.
        let center = FakeNotificationCenter()
        let store = store(
            gateway: gateway(),
            center: center,
            reviewer: FakeReviewRunner(findings: [finding()]),
            configuration: twoSkills
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
    }

    @Test("Čisté review dá vědět taky")
    func notifiesAboutACleanRun() async throws {
        let center = FakeNotificationCenter()
        let store = store(gateway: gateway(), center: center)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.title == "Čisté review")
        #expect(center.delivered.first?.body == "Reviewer nenašel žádný nález.\ncli/cli#42")
    }

    @Test("Nereportující běh se nesmí ohlásit jako čistý")
    func doesNotReportAnInconclusiveRunAsClean() async throws {
        // Běh, který nezavolal `ReportFindings`, není ani čistý, ani spadlý — a „nenašel
        // žádný nález“ by z něj udělalo schválený PR s neohlášenou chybou.
        let center = FakeNotificationCenter()
        let store = store(
            gateway: gateway(),
            center: center,
            reviewer: FakeReviewRunner(calledReportFindings: false)
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.first?.title == "Review se nepovedlo")
        #expect(center.delivered.first?.title != "Čisté review")
    }

    @Test("Selhaný checkout dá vědět, a jinými slovy než spadlá session")
    func notifiesAboutACheckoutFailure() async throws {
        let center = FakeNotificationCenter()
        let checkout = FakeRepoCheckout(outcome: .failure(.notAuthenticated("Nejsi přihlášený v gh.")))
        let store = store(gateway: gateway(), center: center, checkout: checkout)

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.title == "Nepovedlo se připravit pracovní kopii")
        #expect(center.delivered.first?.body.contains("Nejsi přihlášený v gh.") == true)
        // `CheckoutError.userDescription` lepí výstup `gitu` za prázdný řádek — na dvou
        // řádcích těla trvá i tak, jinak by se PR propadlo mimo banner.
        #expect(center.delivered.first?.body.split(separator: "\n").count == 2)
    }

    @Test("Selhání GitHubu dá vědět")
    func notifiesWhenGitHubFails() async throws {
        let center = FakeNotificationCenter()
        let store = store(
            gateway: gateway(detail: .failure(GitHubError.notFound("PR nenalezen."))),
            center: center
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.title == "Review se nepovedlo")
    }

    @Test("Zrušené review se neoznamuje")
    func staysQuietWhenCancelled() async throws {
        // Zrušil si ho člověk, takže o něm ví. Tenhle test je ten nejdůležitější z celého
        // issue: bez něj by stačilo přidat notifikaci do `defer` a nikdo by si nevšiml.
        let center = FakeNotificationCenter()
        let reviewer = FakeReviewRunner(holdsUntilRelease: true)
        let store = store(gateway: gateway(), center: center, reviewer: reviewer)

        store.startReview(for: pr)
        for _ in 0 ..< 100_000 where !store.isReviewing(pr) { await Task.yield() }
        store.cancelReview(for: pr)
        try await waitUntilIdle(store)

        #expect(center.delivered.isEmpty)
        reviewer.releaseAll()
    }

    @Test("Bez notifikačního centra review proběhne stejně")
    func worksWithoutACenter() async throws {
        // Notifikace jsou nepovinná závislost — chybějící centrum nesmí review položit.
        let store = AppStore(
            gateway: gateway(),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: [finding()]),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )

        store.startReview(for: pr)
        try await waitUntilIdle(store)

        #expect(store.reviewState(for: pr) == .completed(findings: 1))
    }
}
