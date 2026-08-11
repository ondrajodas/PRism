import Foundation
import Testing

@testable import PRism

/// Volba tabu PR. Žije ve store, ne ve view — jinak by přetekla z jednoho PR na druhý.
@Suite("AppStore — taby PR")
@MainActor
struct AppStoreTabTests {
    private let first = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let second = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)

    private func summary(_ pr: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ summaries: [PullRequestSummary]) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success(summaries)),
            time: FakeTimeSource()
        )
    }

    /// Popis a diskuze je to, co se čte **než** se člověk podívá na kód — a stejně to má
    /// GitHub. Změna proti zadání #72, které předepisovalo `filesChanged`.
    @Test("PR se otevírá na přehledu")
    func defaultsToOverview() {
        #expect(PullRequestTab.standard == .overview)
        #expect(store([]).detailTab(for: first) == .overview)
    }

    @Test("Volba tabu se drží per PR")
    func keepsTheChoicePerPullRequest() {
        let store = store([])

        store.setDetailTab(.filesChanged, for: first)

        #expect(store.detailTab(for: first) == .filesChanged)
        #expect(store.detailTab(for: second) == .overview, "volba přetekla na jiné PR")
    }

    @Test("Přepnutí zpátky vrátí výchozí stav")
    func switchesBack() {
        let store = store([])
        store.setDetailTab(.filesChanged, for: first)

        store.setDetailTab(.overview, for: first)

        #expect(store.detailTab(for: first) == .overview)
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        #expect(store.detailTabs.isEmpty)
    }

    // MARK: - Tab Kontroly se kreslí jen s checky (#215)

    /// **Nenačteno a žádné jsou dva různé stavy** (`AppStore.checks`), ale pro pruh záložek
    /// z obou plyne totéž: není čím tab naplnit.
    @Test("Bez checků tab Kontroly v pruhu není")
    func hidesTheChecksTabWithoutChecks() {
        let store = store([])

        #expect(!store.hasChecks(first), "chybějící klíč se počítá jako žádné checky")
        #expect(!store.detailTabs(of: first).contains(.checks))

        store.checks[first] = []

        #expect(!store.hasChecks(first), "prázdné pole je taky žádné checky")
        #expect(!store.detailTabs(of: first).contains(.checks))
    }

    @Test("S checky tab Kontroly v pruhu je")
    func showsTheChecksTabWithChecks() {
        let store = store([])
        store.checks[first] = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]

        #expect(store.hasChecks(first))
        #expect(store.detailTabs(of: first).contains(.checks))
        #expect(store.detailTabs(of: second).contains(.checks) == false, "checky přetekly na jiné PR")
    }

    /// Kdyby se volba nezarovnala, nesvítila by v okně žádná záložka a plocha tabu by zůstala
    /// prázdná — dalo by se do toho stavu dostat přepnutím a novým commitem, po kterém checky
    /// zmizely.
    @Test("Volba na nekreslený tab spadne na Přehled")
    func clampsTheChoiceToDrawnTabs() {
        let store = store([])
        store.checks[first] = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        store.setDetailTab(.checks, for: first)
        #expect(store.detailTab(for: first) == .checks)

        store.checks[first] = []

        #expect(store.detailTab(for: first) == .overview)
    }

    /// Uložená volba se přitom **nemaže**. Checky se dotahují s detailem, takže jsou chvíli po
    /// přepnutí PR ještě neznámé — smazat kvůli tomu volbu by znamenalo vypadnout z tabu
    /// `Kontroly` při každém příchodu na PR.
    @Test("Volba se nemaže, jen se nepoužije")
    func keepsTheChoiceWhileChecksAreUnknown() {
        let store = store([])
        store.checks[first] = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        store.setDetailTab(.checks, for: first)

        // Jako po přepnutí PR: klíč zmizí, checky se teprve dotahují.
        store.checks[first] = nil
        #expect(store.detailTab(for: first) == .overview)

        // Jakmile dorazí, je člověk zpátky tam, kde byl.
        store.checks[first] = [
            PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
        ]
        #expect(store.detailTab(for: first) == .checks)
    }

    // MARK: - Selhané načtení checků není „PR bez CI“ (#215)

    private func gateway(
        checks: [PullRequestCheck] = [],
        failure: (any Error)? = nil
    ) -> FakeGitHubGateway {
        let gateway = FakeGitHubGateway(always: .success([summary(first)]))
        gateway.checks = checks
        gateway.checksFailure = failure
        return gateway
    }

    /// **Nejcennější test téhle sady.** Do #215 to bylo `try? … ?? []`, takže z chyby sítě vyšlo
    /// prázdno — a na prázdnu od #215 visí, jestli se nakreslí tab `Kontroly`. Tiše by tedy
    /// z poruchy vyšlo tvrzení „tenhle PR nemá CI“.
    @Test("Selhání se zapíše, prázdno se z něj nestane")
    func recordsAFailureInsteadOfEmptyChecks() async {
        let store = AppStore(
            gateway: gateway(failure: GitHubError.toolUnavailable("gh není po ruce")),
            time: FakeTimeSource()
        )

        await store.loadChecks(for: first)

        #expect(store.checks[first] == nil, "porucha se zapsala jako „žádné checky“")
        #expect(store.checkFailures[first] != nil)
        // A tab se nekreslí — ale je u toho vidět proč, což zajišťuje `checksFailure` v Přehledu.
        #expect(!store.detailTabs(of: first).contains(.checks))
    }

    /// PR bez CI je běžný stav, ne porucha — nesmí se z něj stát hlášení o chybě.
    @Test("PR bez checků žádnou poruchu nehlásí")
    func doesNotReportAFailureForAPullRequestWithoutCI() async {
        let store = AppStore(gateway: gateway(checks: []), time: FakeTimeSource())

        await store.loadChecks(for: first)

        #expect(store.checks[first] == [])
        #expect(store.checkFailures[first] == nil)
    }

    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád lepší
    /// než zmizelý tab.
    @Test("Selhané načtení nezahodí to, co už bylo")
    func keepsPreviousChecksAfterAFailure() async {
        let check = PullRequestCheck(
            name: "phpcs",
            outcome: .passed,
            link: nil,
            startedAt: nil,
            completedAt: nil
        )
        let gateway = gateway(checks: [check])
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadChecks(for: first)

        gateway.checksFailure = GitHubError.timedOut
        await store.loadChecks(for: first)

        #expect(store.checks[first] == [check], "zastaralý seznam se zahodil")
        #expect(store.checkFailures[first] != nil)
        #expect(store.detailTabs(of: first).contains(.checks), "tab zmizel kvůli chybě sítě")
    }

    /// Povedený pokus musí starou poruchu **smazat**, jinak by věta v `Přehledu` zůstala svítit
    /// nad načtenými checky.
    @Test("Povedené načtení poruchu smaže")
    func clearsTheFailureOnSuccess() async {
        let gateway = gateway(failure: GitHubError.timedOut)
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadChecks(for: first)
        #expect(store.checkFailures[first] != nil)

        gateway.checksFailure = nil
        await store.loadChecks(for: first)

        #expect(store.checkFailures[first] == nil)
        #expect(store.checks[first] == [])
    }

    /// Bez úklidu by mapa rostla donekonečna — drží klíč s celým identifikátorem PR.
    @Test("Volba tabu se zahodí s PR, které zmizelo ze seznamu")
    func forgetsTabsOfGonePullRequests() async {
        let store = AppStore(
            gateway: FakeGitHubGateway([.success([summary(first)]), .success([])]),
            time: FakeTimeSource()
        )
        await store.refresh()
        store.setDetailTab(.filesChanged, for: first)

        await store.refresh()

        #expect(store.detailTab(for: first) == .overview)
        #expect(store.detailTabs.isEmpty)
    }
}
