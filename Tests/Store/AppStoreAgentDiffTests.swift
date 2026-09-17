import Foundation
import Testing

@testable import PRism

/// Prohlédnutí commitu, který po sobě agent nechal v kopii repa (#511).
///
/// **Nejcennější tvrzení jsou dvě negativní**: že se u toho **nesahá na GitHub** (ten commit tam
/// není, takže by volání buď spadlo, nebo vrátilo cizí diff) a že se po `Zahodit` **nenechá
/// otevřený** pohled na kód, který ve stromě už neleží.
@Suite("AppStore — diff agenta (#511)")
@MainActor
struct AppStoreAgentDiffTests {
    private let pr = PRIdentifier("ondrajodas/PRism#511")!
    private let worktree = URL(filePath: "/tmp/cache/worktrees/ondrajodas/PRism/511-sync")

    private func store(_ checkout: FakeRepoCheckout, _ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, configuration: .standard, checkout: checkout)
    }

    private var gateway: FakeGitHubGateway { FakeGitHubGateway([.success([])]) }

    private func agentWork(files: Int = 2) -> BranchSyncState {
        .rebased(
            RebasedBranch(
                worktree: worktree,
                headSha: "cccc3333",
                rebasedFrom: "aaaa1111",
                arriving: [RebasedCommit(sha: "cccc3333", title: "fix: address review feedback")],
                replayed: 1,
                origin: .agent,
                fix: AgentFixAnswer(files: (0..<files).map { "App/A\($0).swift" })
            )
        )
    }

    private var commit: AgentFixCommit {
        AgentFixCommit(
            sha: "cccc3333",
            message: "fix: address review feedback (#511)",
            authorName: "Ondřej Jodas",
            committedAt: Date(timeIntervalSince1970: 1_000_000),
            diff: """
                diff --git a/App/A0.swift b/App/A0.swift
                index 1111111..2222222 100644
                --- a/App/A0.swift
                +++ b/App/A0.swift
                @@ -1,2 +1,2 @@
                -let a = 1
                +let a = 2
                 let b = 3

                """
        )
    }

    /// Základní směr: přepne se tab, přečte se `git` v cache a diff se ukáže **toutéž kresbou jako
    /// diff commitu** — tedy přes `commitDiffs`.
    @Test("Prohlédnutí čte git v cache a otevře diff v tabu Commity")
    func opensTheCommitFromTheWorktree() async throws {
        let checkout = FakeRepoCheckout()
        checkout.agentFixCommitAnswer = .success(commit)
        let gateway = gateway
        let store = store(checkout, gateway)
        store.branchSyncStates[pr] = agentWork()

        store.openAgentDiff(in: pr)
        await waitUntil("diff agenta se načte") { store.agentCommit(in: pr) != nil }

        #expect(store.detailTab(for: pr) == .commits)
        #expect(store.openedCommit(in: pr) == "cccc3333")
        // **Čte se strom `-sync` a proti hlavě PR**, ne proti základu větve: force push přetlačí
        // přesně tenhle rozdíl.
        let read = try #require(checkout.agentFixCommitRequests.first)
        #expect(read.worktree == worktree)
        #expect(read.since == "aaaa1111")
        // **Na GitHub se nesáhlo.** Ten commit tam není, takže by odpověď mluvila o jiném kódu.
        #expect(gateway.commitDiffRequests.isEmpty)

        let row = try #require(store.agentCommit(in: pr))
        let state = store.commitDiffState(of: row, in: pr)
        guard case .diff(let diff) = state else {
            Issue.record("v tabu není diff, ale \(state)")
            return
        }
        #expect(diff.files.count == 1)
    }

    /// **Do seznamu commitů pull requestu se nepřimíchává**: na GitHubu není, takže by v seznamu
    /// tvrdil, že na PR leží.
    @Test("Commit agenta se v seznamu commitů PR neobjeví")
    func agentCommitStaysOutOfTheList() async throws {
        let checkout = FakeRepoCheckout()
        checkout.agentFixCommitAnswer = .success(commit)
        let store = store(checkout, gateway)
        store.branchSyncStates[pr] = agentWork()

        store.openAgentDiff(in: pr)
        await waitUntil("diff agenta se načte") { store.agentCommit(in: pr) != nil }

        let list: [PullRequestCommit] = []
        #expect(Policy.openCommit("cccc3333", in: list) == nil)
        #expect(
            Policy.openCommit("cccc3333", in: list, local: store.agentCommit(in: pr))?.sha
                == "cccc3333"
        )
    }

    /// **Bez práce agenta v cache se nestane nic** — kontrola je ve store podruhé, protože
    /// spoléhat na to, že si to pohlídá zašedlé tlačítko, je o jedno místo k zapomenutí víc.
    @Test("Nad rebasem ani nad prázdnem se diff agenta neotevře")
    func doesNothingWithoutAgentWork() async {
        let checkout = FakeRepoCheckout()
        checkout.agentFixCommitAnswer = .success(commit)
        let store = store(checkout, gateway)
        var afterRebase = agentWork()
        if case .rebased(var branch) = afterRebase {
            branch.origin = .rebase
            afterRebase = .rebased(branch)
        }

        store.branchSyncStates[pr] = afterRebase
        store.openAgentDiff(in: pr)
        store.branchSyncStates[pr] = nil
        store.openAgentDiff(in: pr)
        await settle()

        #expect(checkout.agentFixCommitRequests.isEmpty)
        #expect(store.openedCommit(in: pr) == nil)
    }

    /// **Nepovedené čtení skončí v poruše, ne v mlčení**: strom se dá mezitím zahodit a věčné
    /// `Načítám diff commitu…` vypadá jako zaseknutá aplikace.
    @Test("Nepovedené čtení stromu skončí ve stavu, ze kterého vede Zkusit znovu")
    func failedReadEndsInAFailure() async throws {
        let checkout = FakeRepoCheckout()
        checkout.agentFixCommitAnswer = .failure(
            .gitFailed(exitCode: 128, message: "not a git repository")
        )
        let store = store(checkout, gateway)
        store.branchSyncStates[pr] = agentWork()

        store.openAgentDiff(in: pr)
        await waitUntil("čtení skončí") {
            if case .failed = store.commitDiffs[pr]?.content { return true }
            return false
        }

        // Řádek commitu nevznikne — hlavička o commitu, jehož diff se nepřečetl, by tvrdila víc,
        // než se ví.
        #expect(store.agentCommit(in: pr) == nil)
    }

    /// **Po `Zahodit` nesmí zůstat otevřený diff commitu, který ve stromě už není** — to je zrovna
    /// ten tichý stav v cache, kterému se celá akce vyhýbá.
    @Test("Zahození práce agenta zavře i jeho diff")
    func discardingClosesTheDiff() async {
        let checkout = FakeRepoCheckout()
        checkout.agentFixCommitAnswer = .success(commit)
        let store = store(checkout, gateway)
        store.branchSyncStates[pr] = agentWork()

        store.openAgentDiff(in: pr)
        await waitUntil("diff agenta se načte") { store.agentCommit(in: pr) != nil }
        await store.discardSync(for: pr)

        #expect(store.agentCommit(in: pr) == nil)
        #expect(store.openedCommit(in: pr) == nil)
        #expect(store.commitDiffs[pr] == nil)
        #expect(store.branchSyncState(for: pr) == nil)
    }
}
