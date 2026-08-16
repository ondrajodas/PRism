import Foundation
import Testing

@testable import PRism

/// Diff „co od minule přibylo“ ve store (#284) — kdy se nabídne, co se stáhne a co se drží.
@Suite("AppStore — co přibylo od minule (#284)")
@MainActor
struct AppStoreIncrementalDiffTests {
    private let repo = RepoID(owner: "cli", name: "cli")
    private let seen = "4f2ac9188cd"
    private let head = "9c1de0212ab"
    private var id: PRIdentifier { PRIdentifier(repo: repo, number: 42) }

    /// Co je na časové ose. `nil` = konverzace se vůbec nenačetla, tedy stav hned po otevření PR.
    private enum Timeline { case clean, forcePushed }

    // MARK: - Kdy se nabídne

    @Test("Posunutá hlava nad načtenou konverzací dá rozsah")
    func offersTheRange() async {
        let (store, _) = await prepared()

        #expect(store.incrementalDiffRange(for: id) == IncrementalDiffRange(seen: seen, head: head))
    }

    /// **Test, který tvrdí, že se něco NEstalo.** Bez načtené konverzace se o force pushi nemá
    /// aplikace odkud dozvědět — a je to stav, ve kterém je pokaždé, když se PR otevře. Kdyby se
    /// tlačítko nabídlo, po force pushi by otevřelo víc než celý diff PR.
    @Test("Bez konverzace se rozsah nenabídne")
    func refusesWithoutTheTimeline() async {
        let (store, _) = await prepared(timeline: nil)

        #expect(store.incrementalDiffRange(for: id) == nil)
    }

    @Test("Po force pushi se rozsah nenabídne")
    func refusesAfterAForcePush() async {
        let (store, _) = await prepared(timeline: .forcePushed)

        #expect(store.incrementalDiffRange(for: id) == nil)
    }

    @Test("Bez viděné hlavy se rozsah nenabídne")
    func refusesWithoutASeenHead() async {
        let (store, _) = await prepared(seenHead: nil)

        #expect(store.incrementalDiffRange(for: id) == nil)
    }

    // MARK: - Načtení

    @Test("Ptá se na viděnou hlavu proti dnešní")
    func asksForTheRightRange() async {
        let (store, gateway) = await prepared()

        await store.showIncrementalDiff(for: summary)

        #expect(gateway.rangeDiffRequests.count == 1)
        #expect(gateway.rangeDiffRequests.first?.repo == repo)
        #expect(gateway.rangeDiffRequests.first?.base == seen)
        #expect(gateway.rangeDiffRequests.first?.head == head)
    }

    @Test("Načtený rozsah se rozparsuje a drží")
    func keepsTheLoadedRange() async {
        let (store, _) = await prepared()

        await store.showIncrementalDiff(for: summary)

        let incremental = store.incrementalDiff(for: id)
        #expect(incremental?.range == IncrementalDiffRange(seen: seen, head: head))
        #expect(incremental?.loaded?.files.map(\.displayPath) == ["Cart.swift"])
    }

    /// **Rozsah se nestahuje podruhé, dokud je otevřený.** Klíčem jsou dvě sha, takže dokud se
    /// nezmění, je odpověď tatáž — a každé stažení je volání na GitHub.
    @Test("Opakované zobrazení už nestahuje")
    func doesNotFetchTwice() async {
        let (store, gateway) = await prepared()

        await store.showIncrementalDiff(for: summary)
        await store.showIncrementalDiff(for: summary)

        #expect(gateway.rangeDiffRequests.count == 1)
    }

    @Test("Selhání se ukáže, nezmizí")
    func keepsTheFailure() async {
        let (store, _) = await prepared(rangeDiffs: [.failure(GitHubError.notFound("nic tu není"))])

        await store.showIncrementalDiff(for: summary)

        guard case .failed(let detail)? = store.incrementalDiff(for: id)?.content else {
            Issue.record("čekal jsem chybový stav, přišlo \(String(describing: store.incrementalDiff(for: id)?.content))")
            return
        }
        #expect(!detail.isEmpty)
    }

    /// Po selhání se **smí** zkusit znovu — tlačítko `Zkusit znovu` u chyby by jinak nic neudělalo.
    @Test("Po selhání se zkusí znovu")
    func retriesAfterAFailure() async {
        let (store, gateway) = await prepared(
            rangeDiffs: [.failure(GitHubError.notFound("nic")), .success(Self.rangeDiff)]
        )

        await store.showIncrementalDiff(for: summary)
        await store.showIncrementalDiff(for: summary)

        #expect(gateway.rangeDiffRequests.count == 2)
        #expect(store.incrementalDiff(for: id)?.loaded != nil)
    }

    /// **Druhý test, který tvrdí, že se něco NEstalo.** Tlačítko se v takovém případě nenabízí,
    /// takže sem se dá dostat jedině závodem s pollingem — a i tehdy se nesmí stáhnout nic.
    @Test("Bez rozsahu se nestahuje nic")
    func staysQuietWithoutARange() async {
        let (store, gateway) = await prepared(seenHead: nil)

        await store.showIncrementalDiff(for: summary)

        #expect(gateway.rangeDiffRequests.isEmpty)
        #expect(store.incrementalDiff(for: id) == nil)
    }

    @Test("Zavření vrátí celý diff")
    func hidesTheRange() async {
        let (store, _) = await prepared()
        await store.showIncrementalDiff(for: summary)

        store.hideIncrementalDiff(for: id)

        #expect(store.incrementalDiff(for: id) == nil)
    }

    /// Celý diff je to, proti čemu se píše review — pohled na rozsah ho nesmí zahodit.
    @Test("Rozsah nesahá na celý diff")
    func leavesTheFullDiffAlone() async {
        let (store, _) = await prepared()
        await store.loadDiff(for: summary)

        await store.showIncrementalDiff(for: summary)

        #expect(store.loadedDiff(for: id)?.files.map(\.displayPath) == ["Basket.swift"])
        #expect(store.incrementalDiff(for: id)?.loaded?.files.map(\.displayPath) == ["Cart.swift"])
    }

    // MARK: - Materiál

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "odinuv",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private var detail: PullRequest {
        PullRequest(
            id: id,
            title: "titulek",
            author: "odinuv",
            headSha: head,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: ""
        )
    }

    /// Store s načteným detailem, viděnou hlavou a (volitelně) konverzací — tedy přesně tím, na
    /// čem `incrementalDiffRange` stojí.
    private func prepared(
        seenHead: String? = "4f2ac9188cd",
        timeline: Timeline? = .clean,
        rangeDiffs: [Result<String, any Error>] = [.success(rangeDiff)]
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary]),
            detail: .success(detail),
            diffs: [.success(Self.fullDiff)],
            rangeDiffs: rangeDiffs,
            conversations: timeline.map { [.success(conversation(with: $0))] } ?? []
        )
        let store = AppStore(gateway: gateway, time: FakeTimeSource())
        await store.loadDetail(for: summary)
        if let seenHead { store.seenHeads[id] = seenHead }
        // Bez snímku návštěvy vyjde `changesSinceLastVisit` prázdné bez ohledu na to, co
        // v konverzaci je — a force push by pak nešel rozeznat od klidné větve.
        store.visitSnapshots[id] = Date(timeIntervalSince1970: 0)
        if timeline != nil { await store.loadConversation(for: summary) }
        return (store, gateway)
    }

    private func conversation(with timeline: Timeline) -> Conversation {
        let events: [TimelineEvent] = timeline == .forcePushed
            ? [
                TimelineEvent(
                    id: "force",
                    kind: .forcePushed(before: seen, after: head),
                    actor: EventActor(login: "odinuv", avatarURL: nil, isBot: false),
                    at: Date(timeIntervalSince1970: 50)
                )
            ]
            : []
        return Conversation(
            viewer: "me",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false),
            events: ConversationPage(items: events, total: events.count, hasNextPage: false)
        )
    }

    private static let rangeDiff = """
        diff --git a/Cart.swift b/Cart.swift
        index 1111111..2222222 100644
        --- a/Cart.swift
        +++ b/Cart.swift
        @@ -1,2 +1,2 @@
         let a = 1
        -let b = 2
        +let b = 3
        """

    private static let fullDiff = """
        diff --git a/Basket.swift b/Basket.swift
        index 3333333..4444444 100644
        --- a/Basket.swift
        +++ b/Basket.swift
        @@ -1,2 +1,2 @@
         let a = 1
        -let b = 2
        +let b = 3
        """
}
