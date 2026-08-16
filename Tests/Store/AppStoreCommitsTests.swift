import Foundation
import Testing

@testable import PRism

/// Načítání commitů (#316) — kdy se pro ně jde a co se stane, když se to nepovede.
///
/// Rozhodování o tom, **co je v tabu vidět**, je vyčerpané v `CommitsTabStateTests`; tady se hlídá
/// jen to, co se dá pokazit ve store:
///
/// - **udělat z poruchy prázdno.** U checků prázdno znamená „PR nemá CI“; u commitů je to samo
///   o sobě nemožný stav, takže tiché prázdno by z chyby sítě udělalo nesmysl;
/// - **zapsat zrušení jako poruchu.** Přepnutí PR není chyba;
/// - **tahat seznam při každém příchodu na PR**, tedy udělat z commitů polling;
/// - **nedotáhnout to, co zrušení minulo** — bez toho svítí `Načítám commity…` navždycky;
/// - **otočit pořadí už při ukládání.** Pořadí kresby je rozhodnutí `Policy`, ne vlastnost dat.
@Suite("AppStore — commity PR")
@MainActor
struct AppStoreCommitsTests {
    private let first = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: first,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private var detail: PullRequest {
        PullRequest(
            id: first,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: summary.url,
            updatedAt: summary.updatedAt,
            state: .open,
            body: ""
        )
    }

    private func commit(_ sha: String) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: "feat: \(sha)",
            authorName: "Odin Uv",
            authorLogin: "odinuv",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 90),
            isMerge: false
        )
    }

    private func gateway(
        commits: [PullRequestCommit] = [],
        failure: (any Error)? = nil,
        detail: Result<PullRequest, any Error>? = nil
    ) -> FakeGitHubGateway {
        let gateway = FakeGitHubGateway(always: .success([summary]), detail: detail)
        gateway.commits = commits
        gateway.commitsFailure = failure
        return gateway
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, time: FakeTimeSource())
    }

    // MARK: - Stav se skládá ze dvou map

    @Test("Stav tabu se skládá z commitů a z poruchy")
    func buildsTheTabStateFromBothMaps() {
        let store = store(gateway())
        let list = [commit("aaa")]

        #expect(store.commitsTabState(for: first) == .loading)

        store.commits[first] = list
        #expect(store.commitsTabState(for: first) == .list(list, failure: nil))

        store.commitFailures[first] = "timeout"
        #expect(store.commitsTabState(for: first) == .list(list, failure: "timeout"))

        store.commits[first] = nil
        #expect(store.commitsTabState(for: first) == .failed("timeout"))
    }

    /// **Kdo drží co**: mapa nese pořadí z API (od nejstaršího), stav tabu je v pořadí kresby (od
    /// nejnovějšího, #316). Kdyby se otáčelo už při ukládání, stalo by se z pořadí kresby uložená
    /// vlastnost dat — a nešlo by ho pak změnit na jednom místě.
    @Test("Store drží pořadí z API, tab ho otočí")
    func keepsTheApiOrderAndFlipsItForTheTab() async {
        let gateway = gateway(commits: [commit("aaa"), commit("bbb"), commit("ccc")])
        let store = store(gateway)

        await store.loadCommits(for: first)

        #expect(store.commits[first]?.map(\.sha) == ["aaa", "bbb", "ccc"],
                "mapa přerovnala to, co přišlo z API")
        guard case .list(let list, _) = store.commitsTabState(for: first) else {
            Issue.record("seznam se nedostal do tabu")
            return
        }
        #expect(list.map(\.sha) == ["ccc", "bbb", "aaa"], "tab kreslí v pořadí z API")
    }

    // MARK: - Selhání

    /// **Nejcennější test téhle sady**: porucha se nesmí zapsat jako prázdný seznam. U commitů je
    /// to horší než u checků — prázdno tam znamená „PR nemá CI“, tady by znamenalo pull request,
    /// který nemůže existovat.
    @Test("Selhání se zapíše, prázdno se z něj nestane")
    func recordsAFailureInsteadOfAnEmptyList() async {
        let store = store(gateway(failure: GitHubError.toolUnavailable("gh není po ruce")))

        await store.loadCommits(for: first)

        #expect(store.commits[first] == nil, "porucha se zapsala jako „žádné commity“")
        #expect(store.commitsTabState(for: first)
            == .failed(GitHubError.toolUnavailable("gh není po ruce").userDescription))
    }

    /// Zrušení není porucha — přepnutí PR uprostřed volání nemá v okně zanechat chybovou hlášku.
    @Test("Zrušené načtení se nezapisuje jako chyba")
    func doesNotRecordCancellation() async {
        let store = store(gateway(failure: CancellationError()))

        await store.loadCommits(for: first)

        #expect(store.commitFailures[first] == nil)
        #expect(store.commitsTabState(for: first) == .loading, "zrušení se nesmí čít jako porucha")
    }

    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád lepší
    /// než plocha s chybou místo commitů, které se před chvílí načetly.
    @Test("Selhané načtení nezahodí to, co už bylo")
    func keepsPreviousCommitsAfterAFailure() async {
        let list = [commit("aaa")]
        let gateway = gateway(commits: list)
        let store = store(gateway)
        await store.loadCommits(for: first)

        gateway.commitsFailure = GitHubError.timedOut
        await store.loadCommits(for: first)

        #expect(store.commits[first] == list, "zastaralý seznam se zahodil")
        #expect(store.commitsTabState(for: first)
            == .list(list, failure: GitHubError.timedOut.userDescription))
    }

    /// Selhaný pokus se musí dát **zopakovat**: `loadDetail` má cache podle `updatedAt`, takže by
    /// po chybě sítě seznam nikdo nedotáhl a tab by v poruše zůstal do dalšího commitu. Tlačítko
    /// `Zkusit znovu` chodí přímo sem.
    @Test("Zkusit znovu poruchu opravdu přepíše")
    func retriesAfterAFailure() async {
        let gateway = gateway(failure: GitHubError.timedOut)
        let store = store(gateway)
        await store.loadCommits(for: first)
        #expect(store.commitsTabState(for: first) == .failed(GitHubError.timedOut.userDescription))

        gateway.commits = [commit("aaa")]
        gateway.commitsFailure = nil
        await store.loadCommits(for: first)

        #expect(store.commitsTabState(for: first) == .list(gateway.commits, failure: nil))
    }

    // MARK: - Kdy se pro ně jde

    /// Seznam se tahá **s detailem**, ne pollingem — a **i tehdy, když detail spadl**: tab je
    /// v pruhu vždycky, takže by nad nenačtenou hlavičkou svítilo `Načítám commity…` navždycky.
    @Test("Spadlý detail nezastaví načtení commitů")
    func loadsCommitsEvenWhenTheDetailFails() async {
        let gateway = gateway(
            commits: [commit("aaa")],
            detail: .failure(GitHubError.notFound("PR neznám."))
        )
        let store = store(gateway)

        await store.loadDetail(for: summary)

        #expect(store.commitsTabState(for: first) == .list(gateway.commits, failure: nil),
                "commity se kvůli spadlému detailu nedotáhly — tab by tvrdil, že se načítají")
    }

    /// **Tvrdí, že se něco NEstalo**: hotová odpověď se návratem na PR nepřepisuje. Kdyby ano,
    /// byl by z commitů polling — jedno volání `gh` při každém projetí seznamu šipkami.
    @Test("Návrat na PR seznam znovu netahá")
    func doesNotRefetchOnEveryVisit() async {
        let gateway = gateway(commits: [commit("aaa")], detail: .success(detail))
        let store = store(gateway)

        await store.loadDetail(for: summary)
        await store.loadDetail(for: summary)
        await store.loadDetail(for: summary)

        #expect(gateway.commitRequests.count == 1, "seznam se tahal víckrát než jednou")
    }

    /// **Zrušené načtení se musí dotáhnout po návratu na PR** — tatáž past jako u checků (#306).
    /// `loadCommits` běží až po detailu, takže přepnutí PR uprostřed volání ho zruší; zrušení se
    /// schválně nezapisuje, jenže detail je po návratu z cache, takže by bez dotažení v `guardu`
    /// v tabu svítilo `Načítám commity…` navždycky a nic by neběželo.
    @Test("Po zrušeném načtení se commity dotáhnou při návratu na PR")
    func fetchesCommitsMissedByCancellation() async {
        let gateway = gateway(failure: CancellationError(), detail: .success(detail))
        let store = store(gateway)
        await store.loadDetail(for: summary)
        #expect(store.commitsTabState(for: first) == .loading)

        gateway.commits = [commit("aaa")]
        gateway.commitsFailure = nil
        await store.loadDetail(for: summary)

        #expect(store.commitsTabState(for: first) == .list(gateway.commits, failure: nil))
    }

    /// Odznak u záložky mluví o **témž stavu** jako plocha tabu, protože se skládá z týchž map.
    @Test("Odznak je počet a jen nad načteným seznamem")
    func badgeFollowsTheTabState() async {
        let gateway = gateway(commits: [commit("aaa"), commit("bbb")], detail: .success(detail))
        let store = store(gateway)

        #expect(Policy.commitsBadge(of: store.commitsTabState(for: first)) == nil)

        await store.loadDetail(for: summary)

        #expect(Policy.commitsBadge(of: store.commitsTabState(for: first)) == .count(2))
    }
}
