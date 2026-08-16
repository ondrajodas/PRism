import Foundation
import Testing

@testable import PRism

/// Cesta šablony promptu z nastavení do běhu (#281).
///
/// Dvě tvrzení, obě o tom, co se **nestane**: šablona se v runneru nečte znovu (putuje
/// s požadavkem), a s neplatnou šablonou se review vůbec nespustí — nespadne na výchozí
/// potichu.
@Suite("AppStore — prompt review")
@MainActor
struct AppStorePromptTests {
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

    private func store(prompt: String, reviewer: FakeReviewRunner) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.reviewPrompt = prompt
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )
    }

    @Test("Šablona z nastavení dojede až k běhu")
    func theConfiguredTemplateReachesTheRun() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(prompt: "Look at {{skill}} over {{baseSha}}.", reviewer: reviewer)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let request = try #require(reviewer.requests.first)
        #expect(request.promptTemplate == "Look at {{skill}} over {{baseSha}}.")
        // A složí se z ní ten prompt, který session dostane — i s jádrem, které tam napsané není.
        let prompt = ClaudeCommand.prompt(for: request)
        #expect(prompt.hasPrefix("Look at code-review:code-review over bbbb2222."))
        #expect(prompt.contains("ReportFindings"))
    }

    /// Okno neplatnou šablonu neuloží, takže sem se dá dostat jedině ručně editovaným
    /// `config.json`. **Nespustit** je tam jediná poctivá odpověď: prompt bez `{{baseSha}}` by
    /// reviewer odpracoval proti ničemu a v okně by z toho vyšlo „čisté review“.
    @Test("S neplatnou šablonou se review nespustí")
    func aBrokenTemplateStopsTheRun() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(prompt: "Review {{skill}} and be quick.", reviewer: reviewer)

        store.startReview(for: pr)
        await waitUntil("pokus o review doběhne") { !store.isReviewing(self.pr) }

        #expect(reviewer.requests.isEmpty)
        // A je to vidět: v hlavičce PR stojí, co chybí, ne prázdno.
        guard case .failed(let detail) = store.reviewPhases[pr] else {
            Issue.record("čekal se stav failed, přišlo \(String(describing: store.reviewPhases[pr]))")
            return
        }
        #expect(detail.contains("{{baseSha}}"))
    }

    /// Prázdná šablona **není** neplatná — znamená „ber výchozí“, takže běh proběhne
    /// a session dostane text, se kterým aplikace běžela před #281.
    @Test("S prázdnou šablonou běh proběhne s výchozím textem")
    func anEmptyTemplateStillRuns() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(prompt: "", reviewer: reviewer)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let request = try #require(reviewer.requests.first)
        #expect(ClaudeCommand.prompt(for: request) == Policy.reviewPrompt(
            template: ReviewPromptTemplate.standard,
            skillID: "code-review:code-review",
            baseSha: "bbbb2222"
        ))
    }
}
