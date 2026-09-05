import Foundation
import Testing

@testable import PRism

/// Slévatelnost vlastních PR dotažená **tikem**, bez otevírání záložky (#572).
///
/// Cenná polovina jsou tvrzení o tom, co se **nestane**: na mergnutý ani zavřený PR se neptáme
/// (nad ním vrací GitHub `UNKNOWN` navždycky, změřeno na `PRism#470`), na cizí se neptáme vůbec,
/// klidný tik nevyrábí volání a za tik se pošle **jeden** dotaz na celou sadu, ne jeden na PR.
/// Všechno to se rozbije potichu — okno vypadá stejně, jen se každou minutu platí desetinásobek.
@Suite("AppStore — slévatelnost vlastních PR z tiku (#572)")
@MainActor
struct AppStoreMergeReadinessTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func configuration() -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "author:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        return configuration
    }

    private func summary(
        _ text: String,
        author: String = "ondrajodas",
        state: PullRequestState = .open,
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "feat: něco",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? start,
            state: state
        )
    }

    private func detail(of summary: PullRequestSummary) -> PullRequest {
        PullRequest(
            id: summary.id,
            title: summary.title,
            author: summary.author,
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "vetev",
            baseRef: "main",
            url: summary.url,
            updatedAt: summary.updatedAt,
            state: summary.state
        )
    }

    private func readiness(
        of summary: PullRequestSummary,
        mergeability: BranchStatus.Mergeability = .mergeable,
        mergeState: BranchStatus.MergeState = .clean
    ) -> MergeReadiness {
        MergeReadiness(
            detail: detail(of: summary),
            status: BranchStatus(mergeability: mergeability, mergeState: mergeState)
        )
    }

    /// **Ledger návštěv jde dovnitř v paměti**, ne výchozí přes `UserDefaults.standard` (#411):
    /// tvrzení „hromadná odpověď se nepočítá za návštěvu“ by jinak četlo skutečný ledger na disku,
    /// takže by ho ovlivnil běh vedle i běh minulý.
    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration(),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(start: start),
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences()),
            activityVisits: ActivityVisitLedger(preferences: InMemoryPreferences())
        )
    }
}

// MARK: - Co se stane

extension AppStoreMergeReadinessTests {
    /// **Tohle je celé #572**: po startu, bez jediného kliknutí, je vlastní PR na pruhu `K merge`.
    /// Do té doby se hlavička i slévatelnost dotahovaly teprve při otevření záložky, takže deska
    /// odpovídala `waiting` u všech vlastních PR — pravidlo z #563 platilo až po otevření.
    @Test("Po tiku je vlastní PR k mergnutí, bez otevřené záložky")
    func fillsTheLaneWithoutOpeningATab() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.mergeReadiness = [mine.id: readiness(of: mine)]
        let store = store(gateway)

        await store.refresh()

        #expect(store.detail(of: mine.id)?.headSha == "aaaa1111", "hlavička je z tiku")
        #expect(store.branchStatusState(for: mine.id)?.status?.mergeability == .mergeable)
        #expect(store.isMergeReadyForLane(mine.id))
        // A tou cestou, kterou to jde doopravdy — přes desku, ne jen přes předfiltr.
        let lane = store.board.lanes.first { $0.lane == .merge }
        #expect(lane?.rows.map(\.pullRequest.id) == [mine.id])
    }

    /// **Jeden dotaz na celou sadu, ne jeden na PR.** Tohle je to tvrzení, kvůli kterému se u #572
    /// zamítla cesta „dotáhnout detail po jednom“: nad 23 vlastními PR to bylo 46 volání a 29,6 s
    /// proti jednomu volání a 2,60–3,64 s.
    @Test("Za tik jeden dotaz na celou sadu")
    func asksOnceForTheWholeSet() async {
        let mine = ["ondrajodas/PRism#569", "keboola/scheduler#150", "keboola/db-writer-oracle#32"]
            .map { summary($0) }
        let gateway = FakeGitHubGateway(always: .success(mine))
        gateway.mergeReadiness = Dictionary(uniqueKeysWithValues: mine.map { ($0.id, readiness(of: $0)) })
        let store = store(gateway)

        await store.refresh()

        #expect(gateway.mergeReadinessRequests.count == 1, "jedno volání, ne tři")
        #expect(Set(gateway.mergeReadinessRequests.first ?? []) == Set(mine.map(\.id)))
        #expect(mine.allSatisfy { store.isMergeReadyForLane($0.id) })
    }

    /// Konflikt je odpověď, ne prázdno: PR se dotáhne, ale na pruh `K merge` nepatří. „Nevím“
    /// zůstává „nevím“ **a „nejde“ zůstává „nejde“** — obojí je `waiting`, každé z jiného důvodu.
    @Test("Konfliktní větev se dotáhne, ale k mergi nepatří")
    func keepsAConflictingBranchOutOfTheLane() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.mergeReadiness = [mine.id: readiness(of: mine, mergeability: .conflicting, mergeState: .dirty)]
        let store = store(gateway)

        await store.refresh()

        #expect(store.branchStatusState(for: mine.id)?.status?.mergeability == .conflicting)
        #expect(!store.isMergeReadyForLane(mine.id))
    }

    /// Otevření záložky si po hromadné odpovědi dotáhne **polohu větve proti základu** — ta
    /// v hromadném dotazu být nemůže (`compare` potřebuje jméno základu a hlavu z téže odpovědi).
    /// A **slévatelnost už znovu netahá**: otevření vlastního PR tím zlevnilo z dvou volání na jedno.
    @Test("Záložka doplní polohu větve a slévatelnost už netahá")
    func topsUpTheDivergenceWhenOpeningATab() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]), detail: .success(detail(of: mine)))
        gateway.mergeReadiness = [mine.id: readiness(of: mine)]
        gateway.divergence = BranchDivergence(ahead: 2, behind: 1)
        let store = store(gateway)
        await store.refresh()

        await store.loadDetail(for: mine)

        #expect(store.branchStatusState(for: mine.id)?.status?.divergence?.behind == 1)
        #expect(gateway.branchStatusQueries.isEmpty, "slévatelnost je z tiku, znovu se netahá")
        #expect(gateway.divergenceQueries.count == 1)
    }
}

// MARK: - Co se NEstane

extension AppStoreMergeReadinessTests {
    /// **Na mergnutý ani zavřený PR se neptáme.** Nad ním vrací GitHub `mergeable: UNKNOWN`
    /// navždycky (změřeno na `PRism#470`), takže by se odpověď tik co tik zahazovala jako
    /// nedopočítaná a ptalo by se na něj donekonečna. Stav se pozná ze **shrnutí**, tedy z toho,
    /// co seznam vydá už dneska.
    @Test("Na mergnutý ani zavřený PR se neptáme")
    func neverAsksAboutAFinishedPullRequest() async {
        let open = summary("ondrajodas/PRism#569")
        let merged = summary("ondrajodas/PRism#568", state: .merged)
        let closed = summary("ondrajodas/PRism#567", state: .closed)
        let gateway = FakeGitHubGateway(always: .success([open, merged, closed]))
        gateway.mergeReadiness = [open.id: readiness(of: open)]
        let store = store(gateway)

        await store.refresh()

        #expect(gateway.mergeReadinessRequests == [[open.id]])
        #expect(store.branchStatusState(for: merged.id) == nil)
        #expect(store.branchStatusState(for: closed.id) == nil)
    }

    /// **Na cizí PR se neptáme vůbec.** Sekce `Větev` se na nich nekreslí a mergnout cizí frontu
    /// se odsud nedělá nikdy — byl by to dotaz za odpověď, kterou nikdo nepřečte.
    @Test("Na cizí PR se neptáme")
    func neverAsksAboutSomeoneElsesPullRequest() async {
        let theirs = summary("cli/cli#14278", author: "odinuv")
        let gateway = FakeGitHubGateway(always: .success([theirs]))
        let store = store(gateway)

        await store.refresh()

        #expect(gateway.mergeReadinessRequests.isEmpty)
        #expect(store.branchStatusState(for: theirs.id) == nil)
    }

    /// **Tichý tik nevyrábí volání.** Razítko `updatedAt` je tatáž cache, jakou má otevřená
    /// záložka: dokud se pull request nepohne, není se nač ptát — a prázdný seznam se nespouští.
    @Test("Tichý tik druhý dotaz neposílá")
    func staysSilentOnAQuietTick() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.mergeReadiness = [mine.id: readiness(of: mine)]
        let store = store(gateway)

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(gateway.mergeReadinessRequests.count == 1, "tři tiky, jeden dotaz")
    }

    /// Posunutý pull request se naopak zeptá **znovu** — razítko je `updatedAt`, ne příznak
    /// „už jsme se ptali“. Bez toho by v pruhu `K merge` zůstal PR, který mezitím dostal konflikt.
    @Test("Posunutý PR se zeptá znovu")
    func asksAgainAfterThePullRequestMoves() async {
        let mine = summary("ondrajodas/PRism#569")
        let moved = summary("ondrajodas/PRism#569", updatedAt: start.addingTimeInterval(60))
        let gateway = FakeGitHubGateway([.success([mine]), .success([moved])])
        gateway.mergeReadiness = [mine.id: readiness(of: mine)]
        let store = store(gateway)

        await store.refresh()
        gateway.mergeReadiness = [moved.id: readiness(of: moved, mergeability: .conflicting, mergeState: .dirty)]
        await store.refresh()

        #expect(gateway.mergeReadinessRequests.count == 2)
        #expect(store.branchStatusState(for: mine.id)?.status?.mergeability == .conflicting)
        #expect(!store.isMergeReadyForLane(mine.id))
    }

    /// **Chybějící odpověď se nezapisuje.** „Na tuhle PR nevíme“ se od „zeptali jsme se a tohle
    /// vyšlo“ musí poznat — z prázdna se nesmí nic tvrdit —, a příští tik se zeptá znovu.
    @Test("Chybějící odpověď nic nezapíše a zkusí se znovu")
    func writesNothingForAMissingAnswer() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        let store = store(gateway)

        await store.refresh()
        #expect(store.branchStatusState(for: mine.id) == nil)
        #expect(store.detailStates[mine.id] == nil)
        #expect(!store.isMergeReadyForLane(mine.id))

        await store.refresh()
        #expect(gateway.mergeReadinessRequests.count == 2, "razítko se neposunulo, ptá se znovu")
    }

    /// **Selhání nic nemaže a nic nehlásí** — tatáž nesymetrie jako u `refreshStaleHeads`.
    @Test("Selhaný dotaz nechá prázdno a zkusí to znovu")
    func survivesAFailure() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.mergeReadinessFailure = GitHubError.malformedOutput("nic")
        let store = store(gateway)

        await store.refresh()

        #expect(store.branchStatusState(for: mine.id) == nil)
        #expect(!store.isMergeReadyForLane(mine.id))
        await store.refresh()
        #expect(gateway.mergeReadinessRequests.count == 2)
    }

    /// **Návštěva se z toho nestane.** Ledger odpovídá na „co jsem u toho PR naposledy viděl“,
    /// takže zapsat mu hlavu, na kterou se nikdo nepodíval, znamená spolknout příští
    /// „přibyly commity“.
    @Test("Hromadná odpověď se nepočítá za návštěvu")
    func doesNotCountAsAVisit() async {
        let mine = summary("ondrajodas/PRism#569")
        let gateway = FakeGitHubGateway(always: .success([mine]))
        gateway.mergeReadiness = [mine.id: readiness(of: mine)]
        let store = store(gateway)

        await store.refresh()

        #expect(store.seenHeads[mine.id] == nil)
        #expect(store.movedHead(for: mine.id) == nil)
    }
}
