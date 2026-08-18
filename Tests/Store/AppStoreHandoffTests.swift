import Foundation
import Testing

@testable import PRism

/// Razítko předání ve store (#334) — zápis, odznak po předání a co se stane po pushi.
///
/// Proti **skutečnému** `HandoffLedger`u nad dočasnou složkou: to hlavní tvrzení je, že razítko
/// přežije restart, a o tom rozhoduje obsah disku — fake by měřil sám sebe.
///
/// Tři tvrzení jsou z těch, které se rozbijí potichu: po předání **nesvítí** odznak, po pushi se
/// review **nespustí samo** a zastaralý nález **nezmizí**.
@Suite("AppStore — předání zadání (#334)")
@MainActor
struct AppStoreHandoffTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail(headSha: String = "9c1de02aaaa") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "ondra",
            headSha: headSha,
            baseSha: "bbbb2222",
            headRef: "issue-320-timeout",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "ondra",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Totéž PR po pushi: novější `updatedAt`, takže se detail i konverzace dotáhnou znovu.
    private var pushedSummary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "ondra",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 200),
            state: .open
        )
    }

    private func comment(id: String, at seconds: TimeInterval) -> ThreadComment {
        ThreadComment(
            id: id,
            author: "kolega",
            body: "text \(id)",
            createdAt: Date(timeIntervalSince1970: seconds),
            url: URL(string: "https://github.com/cli/cli/pull/42#discussion_r\(id)")!
        )
    }

    private func thread(id: String, comments: [ThreadComment]) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "Cart.swift",
            line: 27,
            originalLine: 27,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func conversation(threads: [ReviewThread]) -> Conversation {
        Conversation(
            viewer: "ondra",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private func configuration() -> Configuration {
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondra"]
        return configuration
    }

    /// Store s načteným detailem, konverzací a uloženým nálezem — tedy PR, na kterém je co předat.
    private func prepared(
        conversations: [Result<Conversation, any Error>] = [],
        commits: [PullRequestCommit] = [],
        time: FakeTimeSource = FakeTimeSource(),
        ledger: HandoffLedger? = nil
    ) async throws -> (store: AppStore, gateway: FakeGitHubGateway, ledger: HandoffLedger) {
        let gateway = FakeGitHubGateway(
            always: .success([summary]),
            detail: .success(detail()),
            conversations: conversations
        )
        gateway.commits = commits
        let handoffs = ledger ?? HandoffLedger(layout: layout, time: time)
        let reviews = ReviewStore(layout: layout, time: time)
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(),
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: []),
            reviews: reviews,
            handoffs: handoffs
        )
        // Nález uložený tou cestou, kterou vzniká doopravdy — přes `ReviewStore`, ne dosazením
        // do stavu: report ho čte ze záznamu a záznam se skládá na disku.
        var summaryOfRun = StreamSummary()
        summaryOfRun.findings = [makeReported(file: "Cart.swift", line: 13, summary: "total() ignoruje množství")]
        summaryOfRun.calledReportFindings = true
        let run = ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "9c1de02aaaa", skillID: "code-review"),
            summary: summaryOfRun,
            outcome: .finished
        )
        let record = try await reviews.save(run)
        store.reviewRecords[pr] = record
        await store.loadDetail(for: summary)
        if !conversations.isEmpty { await store.loadConversation(for: summary) }
        return (store, gateway, handoffs)
    }

    // MARK: - Zápis razítka

    /// Razítko nese **hlavu i identity předaných položek** — bez hlavy by po pushi tvrdilo
    /// „předáno“ dál, bez identit by nešlo poznat, co zbývá.
    @Test("Předání zapíše čas, hlavu i položky")
    func writesTheStamp() async throws {
        let (store, _, _) = try await prepared()

        store.noteHandoff(of: store.agentPrompt(for: pr))

        let stamp = store.handoff(for: pr)
        #expect(stamp?.headSha == "9c1de02aaaa")
        #expect(stamp?.count == 1)
        #expect(stamp?.at == FakeTimeSource().now)
    }

    /// **Nejcennější tvrzení**: po předání zhasne odznak i pilulka, i když nález dál existuje.
    @Test("Po předání nezbývá nic k předání")
    func clearsThePendingCountAfterTheHandoff() async throws {
        let (store, _, _) = try await prepared()

        #expect(store.pendingHandoffCount(for: pr) == 1)

        store.noteHandoff(of: store.agentPrompt(for: pr))

        #expect(store.pendingHandoffCount(for: pr) == 0)
        #expect(store.handoffReport(for: pr).stage == .delivered)
        // Nález nezmizel — jen je předaný.
        #expect(store.reviewRecord(for: pr)?.activeFindings.count == 1)
    }

    /// Razítko se ukládá **do cache**, takže ho najde další start.
    @Test("Razítko přežije nový store")
    func survivesInTheCache() async throws {
        let time = FakeTimeSource()
        let ledger = HandoffLedger(layout: layout, time: time)
        let (store, _, _) = try await prepared(time: time, ledger: ledger)
        store.noteHandoff(of: store.agentPrompt(for: pr))

        // Zápis na disk běží v `Task`u — pravda za běhu je paměť, disk je záloha.
        #expect(await waitUntil("razítko dopadne na disk") { await !ledger.load().isEmpty })

        let (restarted, _, _) = try await prepared(time: time, ledger: HandoffLedger(layout: layout, time: time))
        await restarted.loadStoredHandoffs()

        #expect(restarted.handoff(for: pr)?.headSha == "9c1de02aaaa")
        #expect(restarted.pendingHandoffCount(for: pr) == 0)
    }

    // MARK: - Po pushi

    /// Po pushi zadání zastará: odznak se rozsvítí, panel má co říct a **nálezy zůstávají**.
    @Test("Po pushi zadání zastará a nálezy zůstanou")
    func goesOutdatedAfterAPush() async throws {
        let (store, gateway, _) = try await prepared(commits: [])
        store.noteHandoff(of: store.agentPrompt(for: pr))
        #expect(store.pendingHandoffCount(for: pr) == 0)

        // Agent opravil a pushnul: PR má novou hlavu a `updatedAt`, takže se detail dotáhne znovu.
        gateway.detailFromNowOn = .success(detail(headSha: "ff11223bbbb"))
        await store.loadDetail(for: pushedSummary)

        let report = store.handoffReport(for: pr)
        #expect(report.stage == .outdated)
        #expect(report.awaitsMove)
        #expect(report.staleFindings == 1)
        #expect(store.reviewRecord(for: pr)?.activeFindings.count == 1)
    }

    /// **Tvrzení, že se něco nestalo**: po pushi se review nespustí samo. Automat se vlastních PR
    /// netýká vůbec (#332) a na vlastním PR se pushuje často, takže by každý commit spustil kolo,
    /// které nikdo nečte.
    @Test("Po pushi se review nespustí samo")
    func neverStartsAReviewOnItsOwn() async throws {
        let (store, gateway, _) = try await prepared()
        store.noteHandoff(of: store.agentPrompt(for: pr))

        gateway.detailFromNowOn = .success(detail(headSha: "ff11223bbbb"))
        await store.loadDetail(for: pushedSummary)
        await settle()

        #expect(store.handoffReport(for: pr).stage == .outdated)
        #expect(!store.isReviewing(pr))
        #expect(store.reviewTasks.isEmpty)
        #expect(store.automaticReviews.isEmpty)
    }

    /// Počet commitů v panelu se bere ze **seznamu commitů**, tedy z toho, co se tahá s detailem.
    @Test("Panel po pushi ví, kolik commitů přišlo")
    func countsCommitsSinceTheHandoff() async throws {
        let commits = ["aaa0001", "9c1de02aaaa", "bbb0003", "ff11223bbbb"].map {
            PullRequestCommit(
                sha: $0,
                message: "c",
                authorName: "Ondra",
                authorLogin: "ondra",
                avatarURL: nil,
                committedAt: Date(timeIntervalSince1970: 100),
                isMerge: false
            )
        }
        let (store, gateway, _) = try await prepared(commits: commits)
        store.noteHandoff(of: store.agentPrompt(for: pr))
        gateway.detailFromNowOn = .success(detail(headSha: "ff11223bbbb"))
        await store.loadDetail(for: pushedSummary)

        #expect(store.handoffReport(for: pr).commits == 2)
    }

    // MARK: - Zúžené zadání

    /// `Sestavit i tak (jen nové vlákno)` nese **jen novou diskuzi**, ne nálezy proti staré hlavě.
    @Test("Zúžené zadání nese jen novou diskuzi")
    func narrowsTheFreshPrompt() async throws {
        let before = conversation(threads: [thread(id: "t1", comments: [comment(id: "c1", at: 500)])])
        let after = conversation(threads: [
            thread(id: "t1", comments: [comment(id: "c1", at: 500)]),
            thread(id: "t2", comments: [comment(id: "c2", at: 2_000_000)]),
        ])
        let (store, _, _) = try await prepared(conversations: [.success(before), .success(after)])
        store.noteHandoff(of: store.agentPrompt(for: pr))
        #expect(store.pendingHandoffCount(for: pr) == 0)

        // Kolega napsal nové vlákno — konverzace se dotáhne znovu, protože se změnilo `updatedAt`
        // (načtená se drží právě podle něj, viz `hasCurrentConversation`).
        await store.loadConversation(for: pushedSummary)

        let fresh = store.freshAgentPrompt(for: pr)
        #expect(fresh != nil)
        #expect(fresh?.included.total == 1)
        #expect(fresh?.text.contains("text c2") == true)
        #expect(fresh?.text.contains("total() ignoruje množství") == false)
    }

    /// Když po předání nepřišlo nic, zúžené zadání **nevznikne** — prázdný sheet s hlavičkou
    /// a bez položek vypadá jako rozbitá aplikace, takže tlačítko zůstane zakázané.
    @Test("Bez novinek se zúžené zadání nesestaví")
    func refusesAnEmptyFreshPrompt() async throws {
        let (store, _, _) = try await prepared()
        store.noteHandoff(of: store.agentPrompt(for: pr))

        #expect(store.freshAgentPrompt(for: pr) == nil)
    }
}
