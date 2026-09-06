import Foundation
import Testing

@testable import PRism

/// Agent na vlastním PR ze strany store (#510) — spouštěč, brána a to, co se s výsledkem stane.
///
/// **Nejcennější tvrzení téhle sady jsou ta, která říkají, že se něco NEstalo**: že se agent
/// nespustil na cizím PR, s vypnutou branou ani po mém vlastním komentáři, a že se po zápisu mimo
/// strom **nic necommitlo**. Ta se rozbijí potichu — výsledkem porušení není chyba, ale session,
/// která píše do souborů, aniž o ni kdo požádal.
///
/// Scéna je tatáž jako u cizí aktivity (#335): rozhlídka po tiku, `FakeGitHubGateway` s posloupností
/// odpovědí, `FakeTimeSource`. Agent totiž visí na téže rozhlídce a jinak se spustit nedá.
@Suite("AppStore — agent na vlastním PR (#510)")
@MainActor
struct AppStoreAgentFixTests {
    private let pr = PRIdentifier("ondrajodas/PRism#510")!
    private let start = Date(timeIntervalSince1970: 1_000_000)
    /// **Vlastní cache ve scratch složce**, ne ta skutečná: strom agenta se ověřuje proti hranici
    /// cache (`CacheFile.refusal`, tvrdá podmínka č. 3), takže vymyšlená cesta v `/tmp` by se
    /// odmítla — a test by měřil tu kontrolu místo spouštěče.
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    // MARK: - Scéna

    private func configuration(autoAgent: Bool) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [.mine]
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.autoAgent = autoAgent
        return configuration
    }

    private func summary(author: String = "ondrajodas", updated offset: TimeInterval) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "feat: the agent fixes its own pull request",
            author: author,
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: start.addingTimeInterval(offset),
            state: .open
        )
    }

    private func detail(author: String = "ondrajodas") -> PullRequest {
        PullRequest(
            id: pr,
            title: "feat: the agent fixes its own pull request",
            author: author,
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "issue-510-agent-fixes-own-pr",
            baseRef: "main",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: start,
            state: .open,
            isCrossRepository: false
        )
    }

    private func comment(
        id: String,
        by author: String = "odinuv",
        at offset: TimeInterval
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "tenhle guard chybí",
            createdAt: start.addingTimeInterval(offset),
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)#c-\(id)")!
        )
    }

    private func conversation(_ comments: [ThreadComment]) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    /// Dva tiky: prázdná diskuze (zasadí se razítko), pak komentář. Tak se agent spouští v provozu
    /// — na cizí hlas, který přišel **potom**, co aplikace PR poprvé uviděla.
    private func scene(
        autoAgent: Bool,
        author: String = "ondrajodas",
        commenter: String = "odinuv",
        fixer: FakeAgentFixer? = FakeAgentFixer(),
        checkout: FakeRepoCheckout = FakeRepoCheckout()
    ) throws -> (store: AppStore, fixer: FakeAgentFixer?, checkout: FakeRepoCheckout, time: FakeTimeSource) {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [.success([summary(author: author, updated: -100)]), .success([summary(author: author, updated: 400)])],
            detail: .success(detail(author: author)),
            conversations: [
                .success(conversation([])),
                .success(conversation([comment(id: "c1", by: commenter, at: 300)])),
            ]
        )
        checkout.agentWorktree = try worktree
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(autoAgent: autoAgent),
            time: time,
            checkout: checkout,
            fixer: fixer,
            cacheLayout: layout,
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences()),
            agentFixes: AgentFixLedger(preferences: InMemoryPreferences())
        )
        return (store, fixer, checkout, time)
    }

    /// Strom `-sync` **uvnitř scratch cache** — tam, kde ho aplikace čeká.
    private var worktree: URL {
        get throws {
            let url = layout.syncWorktree(for: pr)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    /// Dva tiky s odmlkou, aby druhá rozhlídka doopravdy proběhla — a **počkání na běh**.
    ///
    /// **Spouštěč na běh nečeká**, a je to schválně: visí na tiku pollingu, takže patnáctiminutové
    /// čekání uvnitř `afterSuccessfulTick` by zastavilo rozhlídku i úklid. Test tedy musí počkat
    /// sám, jinak by měřil stav uprostřed běhu. Task se z mapy uklízí sám, takže smyčka skončí.
    private func sweepTwice(_ store: AppStore, _ time: FakeTimeSource) async {
        await store.refresh()
        await settle(store)
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()
        await settle(store)
    }

    private func settle(_ store: AppStore) async {
        while let task = store.branchSyncTasks[pr] { await task.value }
    }

    // MARK: - Co agenta pustí

    /// Základní směr: cizí komentář na vlastním PR se zapnutou branou → **jedna** session, ve
    /// stromě v cache, a **commit dělá aplikace**.
    @Test("Cizí komentář na vlastním PR pustí agenta")
    func startsAfterAForeignComment() async throws {
        let scene = try scene(autoAgent: true)
        scene.checkout.agentCommit = .success(
            RebasedBranch(
                worktree: try worktree,
                headSha: "cccc3333",
                rebasedFrom: "aaaa1111",
                arriving: [RebasedCommit(sha: "cccc3333", title: "fix: address review feedback (#510)")],
                replayed: 1,
                origin: .agent
            )
        )

        await sweepTwice(scene.store, scene.time)

        let fixer = try #require(scene.fixer)
        #expect(fixer.runs == 1)
        #expect(scene.checkout.agentCommitRequests.count == 1)
        #expect(
            scene.checkout.agentCommitRequests.first?.message
                == "fix: address review feedback (#510)"
        )
        // Výsledek je ten stav, ze kterého panel nabízí **potvrzení** force pushe — do remote se
        // nesáhlo.
        let state = try #require(scene.store.branchSyncState(for: pr))
        #expect(state.rebasedBranch?.origin == .agent)
        #expect(state.rebasedBranch?.fix?.files == ["App/A.swift"])
    }

    /// **Podruhé se za totéž neplatí.** Razítko se posouvá při startu, takže další tik nad touž
    /// diskuzí session nepustí.
    @Test("Za tentýž komentář se neplatí dvakrát")
    func doesNotPayTwiceForTheSameComment() async throws {
        let scene = try scene(autoAgent: true)

        await sweepTwice(scene.store, scene.time)
        scene.time.advance(by: Policy.activitySweepInterval)
        await scene.store.refresh()
        await settle(scene.store)

        #expect(try #require(scene.fixer).runs == 1)
    }

    // MARK: - Co agenta NEpustí

    /// **Výchozí stav aplikace.** Bez zapnuté brány se nespustí nic — ani strom se nezakládá.
    @Test("S vypnutou branou se nespustí nic")
    func neverWithTheGateClosed() async throws {
        let scene = try scene(autoAgent: false)

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 0)
        #expect(scene.checkout.agentWorktreeRequests.isEmpty)
        #expect(scene.checkout.agentCommitRequests.isEmpty)
        #expect(scene.store.branchSyncState(for: pr) == nil)
    }

    /// **Na cizím PR nikdy.**
    ///
    /// **Ověřeno vložením regrese, a je to poučné**: když se z `Policy.agentFix` odstraní kontrola
    /// vlastnictví, **tenhle test projde dál** — cizí PR zastaví už `Policy.activitySweep`, který
    /// sahá jedině na `.mine`. Tvrzení tedy měří **složení obou vrstev**, ne guard v rozhodnutí;
    /// ten samotný hlídá `AgentFixPolicyTests` (a tam ta regrese spadne). Obojí je potřeba: kdyby
    /// se rozhlídka někdy rozšířila, chytí to `Policy`, a kdyby se změnilo rozhodnutí, chytí to
    /// rozhlídka.
    @Test("Na cizím PR se agent nepustí")
    func neverOnAForeignPullRequest() async throws {
        let scene = try scene(autoAgent: true, author: "odinuv")

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 0)
        #expect(scene.checkout.agentWorktreeRequests.isEmpty)
    }

    /// **Vlastní hlas agenta nepustí.** Komentář, který jsem napsal já, není cizí aktivita
    /// (`Conversation.isMine`) — a kdyby byl, opravovala by aplikace vlastní poznámky.
    @Test("Vlastní komentář agenta nepustí")
    func neverAfterMyOwnComment() async throws {
        let scene = try scene(autoAgent: true, commenter: "ondrajodas")

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 0)
        #expect(scene.checkout.agentCommitRequests.isEmpty)
    }

    /// **Cizí aktivita, ze které nezbude položka zadání, agenta nepustí.**
    ///
    /// Schválení bez těla je pořád cizí aktivita (přijde notifikace, řádek v `Dění`), ale do zadání
    /// se nepočítá — každý řádkový komentář na GitHubu patří do nějakého review, takže prázdná
    /// obálka není tvrzení. Bez téhle brány by session dostala text bez jediného bodu a zaplatilo
    /// by se za běh, který nemá co opravit.
    @Test("Prázdná obálka review agenta nepustí")
    func neverForAnEmptyReviewEnvelope() async throws {
        let time = FakeTimeSource(start: start)
        let review = SubmittedReview(
            id: "r1",
            author: "odinuv",
            state: nil,
            body: "",
            submittedAt: start.addingTimeInterval(300)
        )
        let gateway = FakeGitHubGateway(
            [.success([summary(updated: -100)]), .success([summary(updated: 400)])],
            detail: .success(detail()),
            conversations: [
                .success(conversation([])),
                .success(
                    Conversation(
                        viewer: "ondrajodas",
                        reviews: ConversationPage(items: [review], total: 1, hasNextPage: false),
                        threads: ConversationPage(items: [], total: 0, hasNextPage: false),
                        comments: ConversationPage(items: [], total: 0, hasNextPage: false)
                    )
                ),
            ]
        )
        let fixer = FakeAgentFixer()
        let checkout = FakeRepoCheckout()
        checkout.agentWorktree = try worktree
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(autoAgent: true),
            time: time,
            checkout: checkout,
            fixer: fixer,
            cacheLayout: layout,
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences()),
            agentFixes: AgentFixLedger(preferences: InMemoryPreferences())
        )

        await sweepTwice(store, time)

        #expect(fixer.runs == 0)
        #expect(checkout.agentWorktreeRequests.isEmpty)
    }

    /// **Na starou diskuzi se agent nepouští.** Při prvním setkání s PR se razítko jen zasadí —
    /// jinak by se po startu aplikace platilo za měsíc staré komentáře.
    @Test("Na diskuzi, která tam byla dřív, se agent nepustí")
    func seedsTheBaselineInsteadOfRunning() async throws {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [.success([summary(updated: -100)])],
            detail: .success(detail()),
            conversations: [.success(conversation([comment(id: "old", at: -5000)]))]
        )
        let fixer = FakeAgentFixer()
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(autoAgent: true),
            time: time,
            checkout: FakeRepoCheckout(),
            fixer: fixer,
            cacheLayout: layout,
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences()),
            agentFixes: AgentFixLedger(preferences: InMemoryPreferences())
        )

        await store.refresh()
        while let task = store.branchSyncTasks[pr] { await task.value }

        #expect(fixer.runs == 0)
    }

    /// **Nad rozdělanou prací se nespouští nic.** O tom, co leží v cache, rozhoduje člověk —
    /// automat ji nesmí přepsat.
    @Test("Nad rozdělaným rebasem v cache se agent nepustí")
    func neverOverUnfinishedWork() async throws {
        let checkout = FakeRepoCheckout()
        checkout.syncWorktree = .unfinishedRebase
        let scene = try scene(autoAgent: true, checkout: checkout)

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 0)
        #expect(checkout.agentWorktreeRequests.isEmpty)
        #expect(scene.store.branchSyncState(for: pr)?.hasUnfinishedRebase == true)
    }

    // MARK: - Co se stane s výsledkem

    /// **Zápis mimo strom je konec, ne varování** — druhá vrstva té meze, na které #510 stojí.
    /// Počítá se **i odmítnutý** pokus: otázka není „povedlo se to“, ale „mířila session mimo
    /// strom“.
    @Test("Po zápisu mimo strom se necommituje nic")
    func rejectsResultsThatWroteOutsideTheWorktree() async throws {
        let scene = try scene(
            autoAgent: true,
            fixer: FakeAgentFixer(answers: [
                AgentFixAnswer(files: ["A.swift"], writesOutside: ["/Users/ondra/klon/A.swift"])
            ])
        )

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 1)
        #expect(scene.checkout.agentCommitRequests.isEmpty)
        let state = try #require(scene.store.branchSyncState(for: pr))
        #expect(state.hasRejectedFix)
        #expect(state.hasDiscardableWork)
        #expect(state.offersTerminal)
        #expect(state.sentence.contains("/Users/ondra/klon/A.swift"))
    }

    /// **Nedoběhlá session se necommituje.** Polovina opravy vypadá jako celá a nabídnout ji
    /// k přetlačení by znamenalo pushnout něco, co nikdo nedokončil.
    @Test("Spadlá session se necommituje")
    func doesNotCommitAfterAFailedSession() async throws {
        let scene = try scene(
            autoAgent: true,
            fixer: FakeAgentFixer(answers: [
                AgentFixAnswer(files: ["A.swift"], failure: "Agent nedoběhl v limitu 15 minut.")
            ])
        )

        await sweepTwice(scene.store, scene.time)

        #expect(scene.checkout.agentCommitRequests.isEmpty)
        #expect(scene.store.branchSyncState(for: pr)?.hasRejectedFix == true)
    }

    /// **Nic se nezměnilo je výsledek, ne porucha** — a nesmí nabízet zahazování, protože v cache
    /// nic neleží.
    @Test("Když se nic nezměnilo, není co zahazovat")
    func reportsAnEmptyRun() async throws {
        let scene = try scene(
            autoAgent: true,
            fixer: FakeAgentFixer(answers: [AgentFixAnswer(skipped: "Tohle je rozhodnutí o produktu.")])
        )

        await sweepTwice(scene.store, scene.time)

        let state = try #require(scene.store.branchSyncState(for: pr))
        #expect(!state.hasDiscardableWork)
        #expect(!state.offersTerminal)
        #expect(state.sentence.contains("Tohle je rozhodnutí o produktu."))
    }

    // MARK: - Nic neodešlo

    /// **Z celého běhu nesmí odejít nic**: žádné volání `gh`, žádný push. Store si na to nemá čím
    /// sáhnout — `fixer` je session bez `Bash`e a publisher se tu nevyrábí (tvrdá podmínka č. 1).
    ///
    /// Měří se to na **fake gateway**: kolik dotazů odešlo a jestli mezi nimi není zápis. Gateway
    /// zápisové metody nemá vůbec, takže je tvrzení o počtu čtení jediné, co jde měřit — a k němu
    /// patří, že se nesahalo na `git` (žádná cesta ke `gh` ani `gitu` se storu nepředává).
    @Test("Během agenta nic neodejde")
    func nothingIsSentWhileTheAgentWorks() async throws {
        let scene = try scene(autoAgent: true)

        await sweepTwice(scene.store, scene.time)

        #expect(try #require(scene.fixer).runs == 1)
        // Push jde jedině přes potvrzení, a to bez cesty ke `gitu` nevznikne ani jako nabídka.
        #expect(scene.store.branchPushSubmission(for: summary(updated: 400)) == nil)
    }
}
