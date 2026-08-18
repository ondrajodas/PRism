import Foundation
import Testing

@testable import PRism

/// Která místa mluví o **frontě** a která o celém seznamu (#332).
///
/// Sada je celá o tvrzeních, že se něco **nestalo**, protože všechno tady se rozbije potichu:
/// odznak fronty, karty dashboardu a souhrn ve stavovém řádku by po přidání vlastního PR do
/// seznamu jen ukázaly jiné číslo (nahlášeno z provozu: `Čeká na mě` tvrdilo 32 = 13 cizích
/// + 19 vlastních), kdežto úklid cache a okno nastavení by naopak potichu **zmenšily** to,
/// co vidí — a neuklizená cache roste, dokud si toho někdo nevšimne.
@Suite("AppStore — fronta jsou cizí PR (#332)")
@MainActor
struct AppStoreQueueScopeTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func summary(author: String, _ identifier: String = "cli/cli#1") -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Store po jednom tiku. Login se bere **z konfigurace** (`ownLogins`), ne z `gh`: je to
    /// tatáž množina (`Policy.ownLogins`) a nezávisí to na tom, kolikátý dotaz fake gateway
    /// zrovna vydává.
    private func loaded(
        _ list: [PullRequestSummary],
        reviews: ReviewStore? = nil
    ) async -> AppStore {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        // Jeden zdroj, ne výchozí dva: fake gateway spotřebovává odpovědi po dotazech, takže by
        // druhý zdroj posunul celou sekvenci (tatáž úvaha jako v `AppStoreAutomaticTests`).
        configuration.global.sources = [.reviewRequested]
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success(list)),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            reviews: reviews
        )
        await store.keepFresh()
        return store
    }

    private func run(for pr: PRIdentifier) -> ReviewRun {
        var summary = StreamSummary()
        summary.sessionID = "session-1"
        summary.calledReportFindings = true
        summary.findings = [makeReported()]
        return ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "aaaa1111", skillID: "code-review"),
            summary: summary,
            outcome: .finished
        )
    }

    // MARK: - Fronta a její odznak

    /// **Nejcennější test odznaku**: vlastní PR v seznamu s ním nesmí hnout. Do #332 hnul, a bylo
    /// to jediné, co bylo z railu vidět — odznak tvrdil, že po mně chce review devatenáct lidí,
    /// kteří o nic nežádali.
    @Test("Vlastní PR v seznamu odznak fronty nezvedne")
    func keepsTheQueueBadgeOverTheirPullRequests() async {
        let theirs = summary(author: "kolega", "cli/cli#2")
        let withoutMine = await loaded([theirs])
        #expect(withoutMine.railQueueCount == 1)

        let withMine = await loaded([summary(author: "ondrajodas", "cli/cli#1"), theirs])

        #expect(withMine.railQueueCount == 1)
        // A seznam, ze kterého se uklízí, zůstává plný.
        #expect(withMine.pullRequests.count == 2)
    }

    @Test("Sekce Fronta kreslí jen cizí PR")
    func showsOnlyTheirPullRequestsInTheQueue() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.visibleQueuePullRequests.map(\.number) == [2])
        #expect(store.queuePullRequests.map(\.number) == [2])
    }

    /// Tik přinesl **jen vlastní PR**, takže polling o prázdnu nic neříká a fronta je prázdná.
    /// Bez vlastního důvodu by v okně zbyl prázdný seznam bez věty.
    @Test("Prázdná fronta nad vlastními PR řekne, že nikdo o review nepožádal")
    func explainsTheEmptyQueueOverOwnPullRequests() async {
        let store = await loaded([summary(author: "ondrajodas", "cli/cli#1")])

        #expect(store.listEmptyReason == .poll(.noPullRequests))
        // Polling prázdno nehlásí — seznam prázdný není.
        #expect(store.emptyReason == nil)
    }

    // MARK: - Dashboard a souhrn

    @Test("Karta Čeká na mě a blok fronty počítají jen cizí PR")
    func countsOnlyTheirPullRequestsOnTheDashboard() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.dashboard.queue.pullRequests == 1)
        #expect(store.dashboardQueue.map(\.id.number) == [2])
        // Vlastní PR z dashboardu nezmizel — má vedle vlastní kartu i blok.
        #expect(store.dashboard.mine.pullRequests == 1)
        #expect(store.dashboardOwnPullRequests.map(\.id.number) == [1])
    }

    @Test("Souhrn ve stavovém řádku sčítá jen frontu")
    func summarizesOnlyTheQueue() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.queueSummary?.pullRequests == 1)
    }

    /// Souhrn se **neukáže vůbec**, když ve frontě nic není: o tom, že po mně nikdo nechce review,
    /// mluví prázdný stav seznamu. Vlastní PR ho tedy nesmí držet naživu.
    @Test("Samotná vlastní PR souhrn nevyrobí")
    func showsNoSummaryWithoutTheirPullRequests() async {
        let store = await loaded([summary(author: "ondrajodas", "cli/cli#1")])

        #expect(store.queueSummary == nil)
    }

    /// Hromadné spuštění je akce nad **frontou** (`Pustit review na vše, co neběželo`), takže
    /// z jednoho kliknutí nesmí utratit session za vlastní PR.
    @Test("Hromadné spuštění nabídne jen cizí PR")
    func offersOnlyTheirPullRequestsForTheBulkRun() async {
        let store = await loaded([
            summary(author: "ondrajodas", "cli/cli#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.pullRequestsNotReviewed.map(\.number) == [2])
    }

    // MARK: - Co se zmenšit nesmí

    /// **Ta nejdražší chyba tohohle issue.** Kdyby se úklid navázal na frontu, PR, který v seznamu
    /// je, by z pohledu `ReviewStore` zmizel — dostal by razítko `closedAt` a po lhůtě by se jeho
    /// nálezy smazaly. Klon vlastního PR přitom zabírá místo stejně jako cizí.
    @Test("Úklid nálezů vlastní PR za zmizelý nepovažuje")
    func neverMarksOwnPullRequestsAsClosed() async throws {
        let mine = summary(author: "ondrajodas", "cli/cli#1")
        let reviews = ReviewStore(layout: layout, time: FakeTimeSource())
        try await reviews.save(run(for: mine.id))

        _ = await loaded([mine, summary(author: "kolega", "cli/cli#2")], reviews: reviews)

        let record = try await reviews.load().records.first { $0.pullRequest == mine.id }
        #expect(record != nil)
        #expect(record?.closedAt == nil)
    }

    /// Okno nastavení musí vidět i repo, ve kterém mám jen svoje PR — je to zrovna to, u kterého
    /// chci vypnout automat nebo povolit odesílání.
    @Test("Okno nastavení vidí i repo z vlastního PR")
    func offersRepositoriesFromOwnPullRequests() async {
        let store = await loaded([
            summary(author: "ondrajodas", "ondrajodas/PRism#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.knownRepositories.map(\.description) == ["cli/cli", "ondrajodas/PRism"])
    }

    /// Nabídka filtru se počítá z plného seznamu (#199), takže vlastní PR z ní nesmí vypadnout —
    /// filtr zúží **obě** sekce a hodnota, která v nabídce není, se nedá odškrtnout.
    @Test("Nabídka filtru zná i vlastní PR")
    func offersFilterValuesFromOwnPullRequests() async {
        let store = await loaded([
            summary(author: "ondrajodas", "ondrajodas/PRism#1"),
            summary(author: "kolega", "cli/cli#2"),
        ])

        #expect(store.filterOptions.authors.map(\.value) == ["kolega", "ondrajodas"])
    }

    /// Sekce `Rozdělaná` je o **mojí** práci, ne o frontě: draft na vlastním PR z doby před #333
    /// se nesmí ztratit, protože je odkud ho dopsat nebo zahodit.
    @Test("Sekce Rozdělaná drží i draft na vlastním PR")
    func keepsDraftsOnOwnPullRequests() async {
        let mine = summary(author: "ondrajodas", "cli/cli#1")
        let store = await loaded([mine])
        // Draft se zapíše přímo do stavu: `canComposeDraft` ho na vlastním PR od #333 založit
        // nedovolí, a tady jde o ten starší, který na disku už leží.
        store.drafts[mine.id] = ReviewDraft(pullRequest: mine.id, headSha: "aaaa1111", body: "rozepsané")

        #expect(store.pullRequestsWithDraft.map(\.number) == [1])
        #expect(store.dashboard.drafts.pullRequests == 1)
    }
}
