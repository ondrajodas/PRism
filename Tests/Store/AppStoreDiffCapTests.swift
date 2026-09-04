import Foundation
import Testing

@testable import PRism

/// Pull request nad stropem GitHubu na počet souborů (#542).
///
/// Scéna je z ostrých dat: `home-assistant/core#181088` mění 3 632 souborů, takže `gh pr diff`
/// vrátí `HTTP 406` a diff nedorazí **nikdy**. Sada tvrdí dvě věci, a ta druhá je ta cennější:
///
/// 1. příčina se **pozná a pojmenuje** — nesmí spadnout do obecného „diff se nepodařilo načíst“;
/// 2. **zbytek okna zůstává k užitku** a **nespustí se nic**. Přehled, konverzace ani kontroly
///    na diffu nestojí, takže rozdíl mezi „nemám diff, tady je proč“ a „nemám nic“ musí být vidět
///    ze stavu záložky, ne až z toho, co si člověk domyslí z prázdné plochy.
@Suite("AppStore — PR nad stropem souborů (#542)")
@MainActor
struct AppStoreDiffCapTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let huge = PRIdentifier("home-assistant/core#181088")!
    private let listed = PRIdentifier("cli/cli#1")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek \(id.number)",
            author: "odinuv",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(_ id: PRIdentifier) -> PullRequest {
        PullRequest(
            id: id,
            title: "2026.9.0",
            author: "frenck",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "rc",
            baseRef: "master",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 300),
            state: .open
        )
    }

    /// Chyba tak, jak vznikne na té cestě, kterou aplikace jde: `gh` skončí nenulově a text
    /// je **skutečná odpověď** z `gh pr diff` nad tím pull requestem.
    private func capFailure() throws -> GitHubError {
        GitHubError(
            failure: ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: try Fixture.text("gh/pr-diff-too-large.txt")
            )
        )
    }

    /// Store po jednom tiku. Jeden zdroj, ne výchozí dva — fake gateway spotřebovává odpovědi
    /// po dotazech, takže by druhý posunul celou sekvenci.
    private func loaded(
        gateway: FakeGitHubGateway,
        reviewer: FakeReviewRunner = FakeReviewRunner(),
        mode: ReviewMode = .manual
    ) async -> AppStore {
        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested]
        configuration.global.mode = mode
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            autoRuns: AutoRunLedger(layout: layout, time: FakeTimeSource())
        )
        await store.keepFresh()
        return store
    }

    private func gateway(_ failure: GitHubError) -> FakeGitHubGateway {
        FakeGitHubGateway(
            always: .success([summary(listed)]),
            detail: .success(detail(huge)),
            diffs: [.failure(failure)],
            conversations: [.success(ConversationFixture.conversation(comments: 2))]
        )
    }

    @Test("Strop se v okně pojmenuje, ne schová do obecné chyby")
    func theCapIsNamed() async throws {
        let store = await loaded(gateway: gateway(try capFailure()))

        await store.loadDiff(for: summary(huge))

        guard case .failed(let failure) = store.diffState(for: huge) else {
            Issue.record("Čekal jsem selhání, přišlo \(String(describing: store.diffState(for: huge)))")
            return
        }
        guard case .tooManyFiles(let limit, _) = failure else {
            Issue.record("Čekal jsem strop, přišlo \(failure)")
            return
        }
        #expect(limit == 300)
        // A hlavně: **není to `other`**, tedy ta cesta, na které se do #542 slily všechny tři
        // příčiny do jedné věty.
        #expect(Policy.diffFailureNotice(failure).action == .openOnGitHub)
    }

    @Test("Zbytek pull requestu se čte dál — chybí jen diff")
    func theRestOfTheWindowStaysUsable() async throws {
        let store = await loaded(gateway: gateway(try capFailure()))

        store.openPullRequest(huge)
        await waitUntil("detail dorazí") { store.detailStates[huge] != .loading }
        let opened = store.summary(for: huge)
        await store.loadDiff(for: opened!)
        await store.loadConversation(for: opened!)

        // Záložka je **detail**, ne porucha: „nemám diff“ není „nemám nic“.
        #expect(store.tabContent(for: huge) == .detail(opened!))
        #expect(store.summary(for: huge)?.title == "2026.9.0")
        #expect(store.conversation(for: huge) != nil)
        // A taby se dají přepínat, i když se ten s diffem načíst nedá.
        for tab in PullRequestTab.allCases {
            store.setDetailTab(tab, for: huge)
            #expect(store.detailTab(for: huge) == tab)
        }
    }

    // MARK: - Co se nestalo

    /// **Nejcennější test sady.** Nad pull requestem, ke kterému nedorazil diff, se nemá co
    /// spustit — a rozbilo by se to potichu: jediné, co by bylo vidět, je utracená session.
    /// Automatický režim je zapnutý schválně, aby test tvrdil něco i tehdy, kdyby plánovač
    /// na přijatou záložku jednou sáhl.
    @Test("Nad pull requestem bez diffu se nespustí review")
    func nothingRuns() async throws {
        let reviewer = FakeReviewRunner()
        let store = await loaded(gateway: gateway(try capFailure()), reviewer: reviewer, mode: .automatic)

        store.openPullRequest(huge)
        await waitUntil("detail dorazí") { store.detailStates[huge] != .loading }
        await store.loadDiff(for: store.summary(for: huge)!)
        await store.refresh()
        await waitUntil("tik doběhne") { store.busyRepositories.isEmpty }

        #expect(reviewer.requests.map(\.key.pullRequest) == [listed])
        #expect(store.reviewTasks[huge] == nil)
    }
}
