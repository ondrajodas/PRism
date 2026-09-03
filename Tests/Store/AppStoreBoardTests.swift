import Foundation
import Testing

@testable import PRism

/// Co deska bere ze store (#515, dřív dashboard #181).
///
/// Tři tvrzení, na kterých to stojí: pruhy se řadí **podle závažnosti**, ne podle času (v seznamu
/// je to naopak, a kdyby si store spletl getter, nikdo by si toho nevšiml); deska čte **plný**
/// seznam, ne zúžený filtrem; a hromadná akce pruhu `Přečíst` sáhne **jen na cizí PR, na kterých
/// review neběželo**.
@Suite("AppStore — deska")
@MainActor
struct AppStoreBoardTests {
    private func summary(
        _ identifier: String,
        author: String = "autor",
        updatedAt: TimeInterval = 100
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    /// - Parameter mine: moje loginy. **Bez nich je vsechno cizi** (`ownership(ofAuthor:mine:)`),
    ///   takze testy o vlastnich pruzich je musi nastavit - jinak tvrdi o desce neco, co v okne
    ///   neplati.
    private func store(
        _ pullRequests: [PullRequestSummary],
        mine: [String] = []
    ) async -> AppStore {
        var configuration = Configuration.standard
        configuration.global.ownLogins = mine
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success(pullRequests)),
            configuration: configuration,
            time: FakeTimeSource()
        )
        await store.refresh()
        return store
    }

    /// Řádky jednoho pruhu — pruh, který ve výčtu chybí, je prázdný, ne chybějící.
    private func rows(_ lane: WorkLane, in store: AppStore) -> [PRIdentifier] {
        store.board.lanes.first { $0.lane == lane }?.rows.map(\.id) ?? []
    }

    /// Seznam v záložce `Fronta` je od naposledy změněného; deska odpovídá na jinou otázku,
    /// takže nahoru patří blokující nález, i když je to nejstarší PR ve frontě.
    @Test("Pruh se řadí podle závažnosti, ne podle času")
    func ordersLanesByUrgency() async {
        let blocking = summary("cli/cli#1", updatedAt: 100)
        let newest = summary("cli/cli#2", updatedAt: 900)
        let store = await store([blocking, newest])
        store.reviewRecords[blocking.id] = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(category: "correctness", verdict: .confirmed)])]
        )
        store.reviewRecords[newest.id] = makeRecord(runs: [makeStoredRun(findings: [])])

        #expect(store.pullRequests.map(\.id) == [newest.id, blocking.id])
        #expect(rows(.decide, in: store) == [blocking.id, newest.id])
    }

    /// Zúžený seznam čte jedině seznam a detail (#117). Deska je tvrzení o tom, co je na tahu —
    /// kdyby četla filtr, zapnutí filtru by z ní udělalo jiná čísla než ze stavového řádku.
    @Test("Filtr seznamu desku nezúží")
    func ignoresTheListFilter() async {
        let store = await store([summary("cli/cli#1"), summary("cli/cli#2")])

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/other")!]))

        #expect(store.visiblePullRequests.isEmpty)
        #expect(store.boardEntries.count == 2)
        #expect(rows(.read, in: store).count == 2)
    }

    @Test("Řádek pruhu nese stav, blokující i tužku draftu")
    func carriesTheRowState() async throws {
        let pullRequest = summary("cli/cli#1")
        let store = await store([pullRequest])
        store.reviewRecords[pullRequest.id] = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(category: "correctness", verdict: .confirmed)])]
        )

        // `try #require`, ne `try?`: s optionalem by test nad prázdnou deskou prošel naprázdno.
        let lane = try #require(store.board.lanes.first { $0.lane == .decide })
        let entry = try #require(lane.rows.first)
        #expect(entry.state == .completed(findings: 1))
        #expect(entry.row.blocking == 1)
        #expect(entry.hasDraft == false)
    }

    // MARK: - Hromadná akce pruhu Přečíst

    @Test("Bez záznamu je PR ve výčtu toho, co neběželo")
    func listsPullRequestsWithoutARun() async {
        let clean = summary("cli/cli#1")
        let fresh = summary("cli/cli#2")
        let store = await store([clean, fresh])
        store.reviewRecords[clean.id] = makeRecord(runs: [makeStoredRun(findings: [])])

        #expect(store.pullRequestsNotReviewed == [fresh.id])
    }

    /// **Nejcennější test téhle sady** (#512, #332). Hromadná akce pruhu `Přečíst` je
    /// `startReviewsForNotReviewed()`, a ta čte **jen cizí PR** — vlastní se odsud nepustí ani
    /// tehdy, když na nich review neběželo. Kdyby si deska skládala vlastní seznam, vznikla by
    /// druhá cesta, jak review spustit, a #332 by na ní neplatilo.
    ///
    /// Tvrdí se to **z obou stran**: co pruh ukazuje, i co akce pustí. Samotné „počet se rovná“
    /// by prošlo i tehdy, kdyby v obou stálo prázdno.
    @Test("Hromadná akce pruhu nepustí vlastní PR")
    func neverRunsReviewsOnOwnPullRequests() async {
        let store = await store(
            [
                summary("cli/cli#1", author: "ondrajodas"),
                summary("cli/cli#2", author: "kolega"),
            ],
            mine: ["ondrajodas"]
        )
        let mine = PRIdentifier("cli/cli#1")!
        let theirs = PRIdentifier("cli/cli#2")!

        // Vlastní PR v pruhu `Přečíst` **není** — spadl do tichého, protože o merge se u něj
        // bez načteného detailu nedá tvrdit nic.
        #expect(rows(.read, in: store) == [theirs])
        #expect(rows(.waiting, in: store) == [mine])
        // A co akce doopravdy pustí, je tentýž seznam.
        #expect(store.pullRequestsNotReviewed == [theirs])
    }

    /// **Odložený PR se z pruhu nepustí taky** (#512): odkládání je zúžení pohledu na seznam
    /// (`PullRequestFilter`), kdežto akce pruhu jde přes `pullRequestsNotReviewed`, které stojí
    /// na `queuePullRequests` — tedy na **plném** seznamu cizích PR bez filtru. Že se ty dvě
    /// množiny nemají čím rozejít, je právě to tvrzení: zapnutý filtr počet akce nezmění.
    @Test("Zapnutý filtr počet u hromadné akce nezmění")
    func keepsTheBulkActionOutOfTheFilter() async {
        let store = await store([
            summary("cli/cli#1", author: "kolega"),
            summary("keboola/vault#2", author: "kolega"),
        ])

        store.setFilter(PullRequestFilter(repositories: [RepoID("cli/cli")!]))

        #expect(store.visibleQueuePullRequests.count == 1)
        #expect(store.pullRequestsNotReviewed.count == 2)
        #expect(rows(.read, in: store).count == 2)
    }

    /// Hromadné spuštění bez reviewera nesmí nic naplánovat — jinak by z jednoho kliknutí
    /// zůstala fronta běhů, které nemá kdo spustit.
    @Test("Bez reviewera se hromadným spuštěním nic nespustí")
    func startsNothingWithoutAReviewer() async {
        let store = await store([summary("cli/cli#1"), summary("cli/cli#2")])

        store.startReviewsForNotReviewed()

        #expect(store.runningReviews == 0)
    }

    // MARK: - Kam vede odkaz v hlavičce bloku

    /// Odkaz `celé dění →` a patka pod blokem vedou do sekce railu — a **včetně přepnutí na
    /// domácí záložku**, jinak by se nad otevřeným PR nestalo nic viditelného.
    @Test("Odkaz přepne na svou sekci i z otevřeného PR")
    func switchesToTheSectionFromAnOpenPullRequest() async {
        let pullRequest = summary("cli/cli#1")
        let store = await store([pullRequest])
        store.openTab(pullRequest.id)

        store.show(.activity)

        #expect(store.railSection == .activity)
        #expect(store.activeTab == .home)
    }

    /// **Strop v pruhu nesmí zúžit to, co se počítá.** Pruh hlásí třináct, i když kreslí pět —
    /// kdyby se strop protáhl do počítání, deska by začala lhát a poznalo by se to až za týden.
    /// Odznak v railu drží tentýž počet, protože čte tutéž množinu.
    @Test("Strop pruhu nezmění počet v hlavičce ani odznak v railu")
    func doesNotLetTheRowLimitShrinkTheCounts() async throws {
        let list = (1...13).map { summary("cli/cli#\($0)") }
        let store = await store(list)

        let lane = try #require(store.board.lanes.first { $0.lane == .read })
        let slice = Policy.laneSlice(lane.rows, of: .read, expanded: false)

        #expect(lane.count == 13)
        #expect(slice.rows.count == 5)
        #expect(slice.hidden == 8)
        #expect(store.railQueueCount == 13)
    }

    /// Vlastní PR **bez načteného detailu** se nesmí tvářit jako slévatelný: `mergeOffer` by nad
    /// chybějícím plánem vydal `factsMissing`, a předfiltr ve storu na to nesmí odpovědět jinak.
    /// Nad nenačtenými daty je „nevím“ vždycky `waiting`.
    @Test("Vlastní PR bez detailu není k merge")
    func doesNotClaimMergeWithoutDetail() async {
        let store = await store([summary("cli/cli#1", author: "ondrajodas")], mine: ["ondrajodas"])

        #expect(store.isMergeReadyForLane(PRIdentifier("cli/cli#1")!) == false)
        #expect(rows(.merge, in: store).isEmpty)
    }
}

/// Osa běhu po restartu (#203).
@Suite("AppStore — uložená osa")
@MainActor
struct AppStoreTimelineTests {
    private let pullRequest = PRIdentifier("cli/cli#1")!

    private func store() -> AppStore {
        AppStore(gateway: FakeGitHubGateway([.success([])]), time: FakeTimeSource())
    }

    private func stored(_ detail: String) -> StoredTimeline {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: detail)), at: Date())
        return timeline.stored()
    }

    @Test("Bez živé osy se vezme ta z uloženého záznamu")
    func fallsBackToTheStoredTimeline() {
        let store = store()
        store.reviewRecords[pullRequest] = makeRecord(runs: [makeStoredRun(timeline: stored("z disku.php"))])

        #expect(store.timelines(for: pullRequest).count == 1)
        // Jeden uložený krok a k němu **doplněný konec** z běhu (nahlášení nálezů a výsledek) —
        // uložený snímek osy ho v sobě nemá, viz `ReviewerTimeline.completeTail(from:)`.
        #expect(store.timelines(for: pullRequest).first?.entries.count == 3)
        #expect(store.timelines(for: pullRequest).first?.isFinished == true)
    }

    /// Rozhoduje **existence klíče, ne prázdnost pole**: nový běh si osu nuluje ještě před
    /// prvním eventem, takže by se v tom okně sáhlo na disk a nad rozjetým během by probliknul
    /// průběh toho předchozího. Nález Copilota na #205.
    @Test("Vynulovaná osa nového běhu nesáhne na disk")
    func doesNotFallBackWhileANewRunStarts() {
        let store = store()
        store.reviewRecords[pullRequest] = makeRecord(runs: [makeStoredRun(timeline: stored("z disku.php"))])
        store.reviewTimelines[pullRequest] = []

        #expect(store.timelines(for: pullRequest).isEmpty)
    }

    /// **Nejcennější test téhle sady.** Běžící review si osu drží v paměti a uložená patří
    /// předchozímu běhu — přebít živou tou z disku by nad novým během ukázalo starý průběh.
    @Test("Živá osa přebíjí tu uloženou")
    func prefersTheLiveTimeline() {
        let store = store()
        store.reviewRecords[pullRequest] = makeRecord(runs: [makeStoredRun(timeline: stored("z disku.php"))])
        var live = ReviewerTimeline(skill: "code-review")
        live.record(.attemptedTool(ToolAttempt(name: "Read", detail: "živý.php")), at: Date())
        store.reviewTimelines[pullRequest] = [live]

        let timelines = store.timelines(for: pullRequest)
        #expect(timelines.count == 1)
        if case .tool(let tool) = timelines.first?.entries.first?.kind {
            #expect(tool.detail == "živý.php")
        } else {
            Issue.record("osa není z paměti")
        }
    }
}
