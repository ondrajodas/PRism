import Foundation

/// Jedno srovnání větve — **jediný volající `BranchPushing`** (#466).
///
/// Existuje ze stejného důvodu jako `MetadataSubmission`: pusher se skládá **až uvnitř** akce
/// a zaniká s ní, takže cesta do remote není otevřená po celou dobu běhu aplikace a `AppStore` ji
/// nemá kde uložit (drží jen cestu ke `gitu` a stav). Je to tvarem `MetadataSubmission`, ne
/// `MergeSubmission`: akce se ovládá z panelu, nemá potvrzovací sheet, a stav, který po ní
/// zůstane, patří do okna (`BranchSyncState`), aby přežil překliknutí tabu.
///
/// **Rebase v cache tudy nejde.** Přehrání commitů je lokální práce a dělá ji `RepoCheckout`;
/// tenhle typ je jenom to místo, kde se **zapisuje ven**. Skládá je `AppStore.syncBranch(_:)`,
/// protože jedině on ví, co je v panelu a jaký stav se má ukázat.
struct BranchSyncSubmission {
    let plan: BranchSyncPlan

    /// Jak vyrobit **cestu do remote**. Volá se až v `push`.
    private let pusher: @MainActor () -> any BranchPushing

    init(plan: BranchSyncPlan, pusher: @escaping @MainActor () -> any BranchPushing) {
        self.plan = plan
        self.pusher = pusher
    }

    /// Ostrá cesta: pusher se skládá z `gitu`, `gh` (přihlášení), read-only gateway (pre-flight),
    /// brány a mých loginů — a skládá se **až** ve chvíli pushnutí.
    init(
        plan: BranchSyncPlan,
        git: URL,
        gh: URL,
        gateway: any GitHubGateway,
        scope: PublishScope,
        mine: Set<String>
    ) {
        self.init(plan: plan) {
            GitBranchPush(
                git: git,
                gh: gh,
                runner: SubprocessRunner(),
                gateway: gateway,
                scope: scope,
                mine: mine
            )
        }
    }

    /// Přetlačí výsledek rebase. **Jediné místo v aplikaci, které volá `BranchPushing.push`.**
    ///
    /// Chyby **nepřevádí ani nepolyká** — volající z nich skládá stav, ve kterém je vidět, co se
    /// nepovedlo, a hlavně jestli šlo o odmítnutý lease. `CancellationError` propouští jako
    /// `BranchSyncError.interrupted` ze stejného důvodu jako u review: zrušit jde jedině *během*
    /// volání, takže „nic se nestalo“ by bylo tvrzení, které nemáme čím podložit.
    @MainActor func push(_ rebased: RebasedBranch) async throws -> String {
        do {
            return try await pusher().push(
                BranchPushPlan(
                    pullRequest: plan.pullRequest,
                    branch: plan.branch,
                    expectedRemoteSha: plan.expectedRemoteSha,
                    sha: rebased.headSha,
                    worktree: rebased.worktree
                )
            )
        } catch is CancellationError {
            throw BranchSyncError.interrupted
        }
    }
}
