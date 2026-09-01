import Foundation
import Testing

@testable import PRism

/// Slévání konfliktů při srovnání větve (#467) — kolo za kolem, jak ho řídí store.
///
/// **Nejcennější tvrzení jsou tady ta, která říkají, že se něco NEstalo**: že se nezapsalo do
/// indexu nad souborem se značkami, že se nedokončil rebase po zápisu mimo strom, že se neplatilo
/// za čtvrté kolo. Ty se totiž rozbijí potichu — výsledek je v obou případech „hláška v panelu“
/// a rozdíl je jedině v tom, co leží v cache a co se commitlo.
///
/// **Nic se nepushuje**: `git` je podstrčený skript, který zapíše svoji řádku, takže je zápis
/// argumentů jediný způsob, jak to ověřit (tatáž scéna jako u #465 a #466).
@Suite("AppStore — slévání konfliktů")
@MainActor
struct AppStoreConflictSyncTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#12")!
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "git-calls.log")
    }

    private static let head = "aaaa1111"

    // MARK: - Scéna

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "chore: conflict probe",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "chore: conflict probe",
            author: "autor",
            headSha: Self.head,
            baseSha: "bbbb2222",
            headRef: "prism-conflict-probe-467",
            baseRef: "master",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            isCrossRepository: false
        )
    }

    /// **Konfliktní stav větve, jako na sondě `#12`**: `mergeable=CONFLICTING`,
    /// `mergeStateStatus=DIRTY`, `ahead 1 / behind 1`. Do #467 tenhle stav akci **zakazoval**;
    /// od #467 je to zrovna ten stav, ve kterém má fungovat.
    private func conflicting() -> BranchStatus {
        BranchStatus(
            mergeability: .conflicting,
            mergeState: .dirty,
            divergence: BranchDivergence(ahead: 1, behind: 1)
        )
    }

    private func syncWorktree() throws -> URL {
        let url = layout.syncWorktree(for: pr)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakeGit() throws -> URL {
        let script = directory.url.appending(path: "git-\(UUID().uuidString).sh")
        let text = """
        #!/bin/sh
        echo "$@" >> "\(calls.path(percentEncoded: false))"
        exit 0
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    private func gitCalls() -> [String] {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return [] }
        return TextLines.nonEmpty(text).map(String.init)
    }

    private func rebasedBranch(headSha: String = "cccc3333") throws -> RebasedBranch {
        RebasedBranch(
            worktree: try syncWorktree(),
            headSha: headSha,
            rebasedFrom: Self.head,
            arriving: [RebasedCommit(sha: "cccc3333000", title: "chore: krok")],
            replayed: 1
        )
    }

    private func conflict(_ files: [String] = ["conflict-probe-467.md"]) throws -> RebaseOutcome {
        .conflicted(files: files, aborted: false, worktree: try syncWorktree())
    }

    /// Store se scénou konfliktní vlastní větve. `resolver == nil` znamená **aplikaci bez
    /// `claude`**, tedy chování do #466.
    private func prepared(
        resolver: FakeConflictResolver?,
        outcome: Result<RebaseOutcome, CheckoutError>,
        staging: ConflictStaging = ConflictStaging(diff: "+ slito\n"),
        continueOutcomes: [Result<RebaseOutcome, any Error>] = [],
        status: BranchStatus? = nil
    ) async throws -> (AppStore, FakeRepoCheckout) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail())
        )
        gateway.branchStatus = status ?? conflicting()
        let checkout = FakeRepoCheckout()
        checkout.rebaseOutcome = outcome
        checkout.staging = staging
        checkout.continueOutcomes = continueOutcomes
        var configuration = Configuration.standard
        configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        configuration.global.ownLogins = ["autor"]
        let tool = try fakeGit()
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: checkout,
            conflicts: resolver,
            spend: SpendLedger(layout: layout, time: FakeTimeSource()),
            gh: tool,
            git: tool,
            cacheLayout: layout
        )
        await store.loadDetail(for: summary())
        store.openTab(pr)
        return (store, checkout)
    }

    // MARK: - Nabídka

    /// **Bez `claude` se konflikt přiznává** — chování do #466. Je to ten druhý směr téhož
    /// tvrzení: `resolvesConflicts` musí doopravdy propadnout ze store až do nabídky.
    @Test("Bez slévání zůstává konflikt překážkou")
    func withoutResolverTheConflictBlocks() async throws {
        let (store, _) = try await prepared(resolver: nil, outcome: .success(try conflict()))

        let section = try #require(store.branchSection(for: pr))
        #expect(!section.sync.isAllowed)
        #expect(section.sync.obstacles.contains(.conflicting(base: "master")))
        #expect(!section.resolvesConflicts)
    }

    @Test("Se sléváním se konfliktní větev srovnat dá")
    func withResolverTheConflictIsNoObstacle() async throws {
        let (store, _) = try await prepared(
            resolver: FakeConflictResolver(),
            outcome: .success(try conflict())
        )

        let section = try #require(store.branchSection(for: pr))
        #expect(section.sync.isAllowed)
        #expect(section.resolvesConflicts)
    }

    // MARK: - Rebase se pro session nechává stát

    /// **Oba směry jednoho rozhodnutí.** Session umí pracovat jedině nad rebasem, který **stojí** —
    /// v zahozeném žádné značky nejsou. Bez resolveru se naopak zahazuje, protože by ho nemělo kdo
    /// dokončit.
    ///
    /// Scéna bez resolveru má **čistý** stav větve, a je to podstatné: nad `CONFLICTING` je tlačítko
    /// bez `claude` zakázané, takže by se rebase vůbec nespustil a tvrzení by měřilo zakázanou akci,
    /// ne to, co se s konfliktem stane. `mergeStateStatus` navíc konflikt neslibuje — `git` na něj
    /// umí narazit i nad `CLEAN` větví, což je zrovna ten případ.
    @Test("Konflikt se nechává stát jen tehdy, když ho má kdo slít")
    func keepsTheConflictOnlyForTheSession() async throws {
        let (withResolver, keeping) = try await prepared(
            resolver: FakeConflictResolver(),
            outcome: .success(try conflict()),
            continueOutcomes: [.success(.rebased(try rebasedBranch()))]
        )
        await withResolver.syncBranch(summary())
        #expect(keeping.keptConflicts == [true])

        let (withoutResolver, aborting) = try await prepared(
            resolver: nil,
            outcome: .success(.conflicted(files: ["a.md"], aborted: true, worktree: try syncWorktree())),
            status: BranchStatus(
                mergeability: .mergeable,
                mergeState: .clean,
                divergence: BranchDivergence(ahead: 1, behind: 1)
            )
        )
        await withoutResolver.syncBranch(summary())
        #expect(aborting.keptConflicts == [false])
        // A stav je ten z #466: zahozený konflikt, v cache po něm nic nezůstalo.
        #expect(withoutResolver.branchSyncState(for: pr) == .conflicted(files: ["a.md"]))
    }

    /// **Zahozený konflikt se neslévá, i když je resolver po ruce** — a je to tvrzení o tom, že se
    /// něco **nestane**. V zahozeném rebase nejsou v souborech žádné značky, takže by session
    /// dostala zaplaceno za čtení nedotčeného stromu.
    ///
    /// Druhá polovina je konflikt **bez cesty ke stromu**: není kam poslat session, a vymyslet si
    /// cestu nesmíme. Sem se dá dojít se starým výsledkem, který to pole ještě nenese.
    @Test("Zahozený konflikt ani konflikt bez stromu se neslévá")
    func doesNotResolveAnAbortedOrPathlessConflict() async throws {
        let aborted = FakeConflictResolver()
        let (first, _) = try await prepared(
            resolver: aborted,
            outcome: .success(.conflicted(files: ["a.md"], aborted: true, worktree: try syncWorktree()))
        )
        await first.syncBranch(summary())
        #expect(aborted.rounds == 0)
        #expect(first.branchSyncState(for: pr) == .conflicted(files: ["a.md"]))

        let pathless = FakeConflictResolver()
        let (second, _) = try await prepared(
            resolver: pathless,
            outcome: .success(.conflicted(files: ["a.md"], aborted: false, worktree: nil))
        )
        await second.syncBranch(summary())
        #expect(pathless.rounds == 0)
        #expect(second.branchSyncState(for: pr) == .unfinished(files: ["a.md"]))
    }

    // MARK: - Doběhlá cesta

    /// Celý happy path: session slije, aplikace zapíše do indexu, dokončí rebase — a **výsledek
    /// čeká na potvrzení**, do remote se nesáhlo.
    @Test("Slitý konflikt skončí mezistavem, ne pushem")
    func resolvedConflictEndsInTheIntermediateState() async throws {
        let resolver = FakeConflictResolver(answers: [
            ConflictAnswer(
                files: [ResolvedConflictFile(path: "conflict-probe-467.md", action: .tookBoth)],
                caveats: "Pořadí odstavců jsem odhadl.",
                usage: RunUsage(cost: 0.5)
            )
        ])
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict()),
            continueOutcomes: [.success(.rebased(try rebasedBranch()))]
        )

        await store.syncBranch(summary())

        let state = try #require(store.branchSyncState(for: pr))
        let rebased = try #require(state.rebasedBranch)
        let resolution = try #require(rebased.resolution)
        #expect(resolution.files == [ResolvedConflictFile(path: "conflict-probe-467.md", action: .tookBoth)])
        #expect(resolution.diff == "+ slito\n")
        #expect(resolution.rounds == 1)
        #expect(resolution.caveats == "Pořadí odstavců jsem odhadl.")
        // **Zapsalo se do indexu právě to, co kolidovalo**, a rebase se dokončil.
        #expect(checkout.staged.map(\.paths) == [["conflict-probe-467.md"]])
        #expect(checkout.continued == [pr])
        // **A nic neodešlo.** `git` se spustil jedině přes fake checkout (ten `git` nevolá vůbec),
        // takže prázdný výpis je doklad, že se nepushovalo.
        #expect(!gitCalls().contains { $0.contains("push") })
    }

    /// **Rozsah zápisu je ten strom, ve kterém rebase uvázl.** Je to ta hodnota, ze které se skládá
    /// `Write(//…)` — kdyby se předal jiný strom, session by uměla psát mimo rozdělaný rebase.
    @Test("Session dostane strom, ve kterém rebase uvázl")
    func sessionGetsTheStuckWorktree() async throws {
        let resolver = FakeConflictResolver()
        let (store, _) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict()),
            continueOutcomes: [.success(.rebased(try rebasedBranch()))]
        )

        await store.syncBranch(summary())

        #expect(resolver.requests.map(\.worktree) == [layout.syncWorktree(for: pr)])
        // **Kolidující soubory jdou v promptu**, ne vlastním polem: session si je bez `Bash`e
        // nezjistí, takže výčet jmen v textu je jediná cesta, jak se dozví, kde konflikt je.
        #expect(resolver.requests.first?.prompt.contains("- conflict-probe-467.md") == true)
    }

    /// **Kol je tolik, kolik je kolizních commitů.** Rebase se zastaví u každého — druhé kolo je
    /// normální průběh, ne porucha.
    @Test("Druhý kolizní commit dostane druhé kolo")
    func runsAsManyRoundsAsThereAreConflicts() async throws {
        let resolver = FakeConflictResolver(answers: [
            ConflictAnswer(usage: RunUsage(cost: 0.2)),
            ConflictAnswer(usage: RunUsage(cost: 0.3)),
        ])
        let (store, _) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"])),
            continueOutcomes: [
                .success(try conflict(["b.md"])),
                .success(.rebased(try rebasedBranch())),
            ]
        )

        await store.syncBranch(summary())

        #expect(resolver.rounds == 2)
        // **Druhé kolo mluví o druhém souboru** — prompt se skládá znovu z toho, na čem rebase
        // uvázl teď, ne z toho, co kolidovalo poprvé.
        #expect(resolver.requests.first?.prompt.contains("- a.md") == true)
        #expect(resolver.requests.last?.prompt.contains("- b.md") == true)
        #expect(resolver.requests.last?.prompt.contains("- a.md") == false)
        let resolution = try #require(store.branchSyncState(for: pr)?.rebasedBranch?.resolution)
        #expect(resolution.rounds == 2)
        // **Útrata se sečte přes kola** — a do `Dneska stálo` se zapisuje každé kolo zvlášť.
        #expect(resolution.usage?.cost == 0.5)
        let spent = try #require(store.dailySpend)
        #expect(spent.runs == 2)
        #expect(abs(spent.cost - 0.5) < 0.0001)
    }

    /// **Strop je proti účtu.** Po třech kolech se přestane platit a řekne se to — v cache přitom
    /// **zůstane rozdělaný rebase**, takže se nabídne zahodit i terminál.
    @Test("Po třech kolech se přestane platit a přizná se to")
    func stopsAfterTheRoundLimit() async throws {
        let resolver = FakeConflictResolver(answers: [ConflictAnswer(usage: RunUsage(cost: 0.1))])
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"])),
            // Rebase se zastaví po každém kole znovu — tedy stav, ve kterém by se bez stropu
            // platilo dokola.
            continueOutcomes: [.success(try conflict(["a.md"]))]
        )

        await store.syncBranch(summary())

        #expect(resolver.rounds == Policy.maxConflictRounds)
        let state = try #require(store.branchSyncState(for: pr))
        #expect(state.hasUnfinishedRebase)
        #expect(state.offersTerminal)
        #expect(state.sentence.contains("terminálu"))
        // Čtvrté kolo se nedokončilo, takže se ani nedokončoval rebase počtvrté.
        #expect(checkout.continued.count == Policy.maxConflictRounds)
    }

    // MARK: - Co se NEstane

    /// **Soubor se značkami se do indexu nezapíše a rebase se nedokončí.** Zapsat značky do
    /// commitu je ta nejdražší podoba uhádaného slití: projde a rozbije se až buildem.
    @Test("Se zbylými značkami se nedokončuje rebase")
    func doesNotContinueWithLeftoverMarkers() async throws {
        let resolver = FakeConflictResolver(answers: [
            ConflictAnswer(
                files: [ResolvedConflictFile(path: "a.md", action: .manual)],
                caveats: "Nevím, jak to slít."
            )
        ])
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"])),
            staging: ConflictStaging(diff: "", unresolved: ["a.md"])
        )

        await store.syncBranch(summary())

        #expect(checkout.continued.isEmpty)
        let state = try #require(store.branchSyncState(for: pr))
        #expect(state == .unresolved(files: ["a.md"], detail: "Nevím, jak to slít."))
        #expect(state.hasUnfinishedRebase)
        #expect(state.rebasedBranch == nil)
        #expect(!gitCalls().contains { $0.contains("push") })
    }

    /// **Zápis mimo strom je konec, a ještě před `git add`.** Brána v `--allowedTools` je změřená;
    /// tohle je druhá vrstva — kdyby se ta brána změnila, nesmí se commitnout nic.
    @Test("Zápis mimo strom výsledek nepřijme a nic nezapíše")
    func rejectsWritesOutsideTheWorktree() async throws {
        let resolver = FakeConflictResolver(answers: [
            ConflictAnswer(
                files: [ResolvedConflictFile(path: "a.md", action: .manual)],
                writesOutside: ["/Users/ondra/Projects/prism/App/x.swift"]
            )
        ])
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"]))
        )

        await store.syncBranch(summary())

        // **Ani `git add`, ani `rebase --continue`.**
        #expect(checkout.staged.isEmpty)
        #expect(checkout.continued.isEmpty)
        let state = try #require(store.branchSyncState(for: pr))
        #expect(state.hasUnfinishedRebase)
        #expect(state.sentence.contains("mimo kopii repa"))
        #expect(state.sentence.contains("Session konflikt nerozřešila"))
        #expect(state.sentence.contains("App/x.swift"))
    }

    /// **Strom mimo cache se neslévá vůbec** (tvrdá podmínka č. 3). Session dostává strom jako
    /// rozsah, na který smí psát — cesta mimo cache by znamenala povolení psát do cizího klonu.
    @Test("Strom mimo cache session nedostane")
    func refusesAWorktreeOutsideTheCache() async throws {
        let outside = URL(filePath: "/tmp/mimo-cache")
        let resolver = FakeConflictResolver()
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(.conflicted(files: ["a.md"], aborted: false, worktree: outside))
        )

        await store.syncBranch(summary())

        #expect(resolver.rounds == 0)
        #expect(checkout.staged.isEmpty)
        #expect(store.branchSyncState(for: pr) == .failed(.outsideCache(outside.path(percentEncoded: false))))
    }

    /// **Nedoběhlá session není konec, když `git` značky nevidí.** Mohla polovinu souborů slít
    /// správně a na další vytimeoutovat — rozhoduje `git`, ne to, jak session skončila. Věta ale
    /// musí zůstat vidět: je to zaplacená informace.
    @Test("Timeout session se přijme, když v souborech značky nezůstaly")
    func acceptsAPartialAnswerWithoutMarkers() async throws {
        let resolver = FakeConflictResolver(answers: [
            ConflictAnswer(
                files: [ResolvedConflictFile(path: "a.md", action: .manual)],
                failure: "Slévání nedoběhlo v limitu 10 minut."
            )
        ])
        let (store, _) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"])),
            continueOutcomes: [.success(.rebased(try rebasedBranch()))]
        )

        await store.syncBranch(summary())

        let resolution = try #require(store.branchSyncState(for: pr)?.rebasedBranch?.resolution)
        #expect(resolution.caveats == "Slévání nedoběhlo v limitu 10 minut.")
    }

    // MARK: - Zrušení

    /// **Zrušení nechá rozdělaný rebase a řekne to.** Je to rozdíl proti #466: tam byl rebase
    /// volání `gitu` a po zrušení v cache nic nezůstalo, kdežto session v souborech nechá
    /// rozdělanou práci — takže `Přerušeno.` by ta tlačítka na úklid nenabídlo.
    @Test("Zrušené slévání nabídne úklid, ne jen hlášku Přerušeno")
    func cancellingLeavesTheRebaseAndSaysSo() async throws {
        let resolver = FakeConflictResolver()
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict(["a.md"]))
        )
        // Zrušení **uprostřed** kola: fake si o něj řekne ve chvíli, kdy už request přišel.
        resolver.beforeAnswer = { [weak store] _ in
            Task { @MainActor in store?.cancelBranchSync(for: self.pr) }
        }
        resolver.failure = CancellationError()

        await store.syncBranch(summary())

        #expect(checkout.staged.isEmpty)
        #expect(checkout.continued.isEmpty)
        let state = try #require(store.branchSyncState(for: pr))
        #expect(state == .unresolved(files: ["a.md"], detail: "slévání jsi zrušil"))
        #expect(state.hasUnfinishedRebase)
    }

    /// Během zavírání aplikace se **nic nespouští** (#264) — tatáž brána jako u review a rozhovoru.
    @Test("Při zavírání aplikace se srovnání nespustí")
    func doesNotStartWhileTerminating() async throws {
        let resolver = FakeConflictResolver()
        let (store, checkout) = try await prepared(
            resolver: resolver,
            outcome: .success(try conflict())
        )
        store.isTerminating = true

        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests.isEmpty)
        #expect(resolver.rounds == 0)
        #expect(store.branchSyncState(for: pr) == nil)
    }

    /// **Běžící slévání drží repo proti eviction** — jinak by se pod session mohl uklidit klon,
    /// ve kterém pracuje.
    ///
    /// **Tvrdí se to nad zapsaným záznamem, ne časováním běhu.** Měřidlo, které by chtělo trefit
    /// okamžik uprostřed session, by u fake resolveru (odpovídá hned) vydalo tutéž hodnotu pro
    /// „chrání“ i „nechrání“ — a takové měření netvrdí nic (#478). Rozhodující je mapování
    /// `branchSyncTasks` → `busyRepositories`, a to se dá tvrdit **oběma směry**.
    @Test("Běžící slévání chrání repo před úklidem")
    func runningResolutionProtectsTheRepository() async throws {
        let (store, _) = try await prepared(
            resolver: FakeConflictResolver(),
            outcome: .success(try conflict())
        )

        #expect(!store.busyRepositories.contains(pr.repo))
        store.branchSyncTasks[pr] = Task {}
        #expect(store.busyRepositories.contains(pr.repo))
        store.branchSyncTasks[pr] = nil
        #expect(!store.busyRepositories.contains(pr.repo))
    }

    /// **Po doběhnutí se záznam maže** — jinak by repo zůstalo chráněné navždycky a eviction by na
    /// ten klon nikdy nesáhla.
    @Test("Po doběhnutí srovnání záznam nezůstává")
    func clearsTheTaskAfterTheRun() async throws {
        let (store, _) = try await prepared(
            resolver: FakeConflictResolver(),
            outcome: .success(try conflict()),
            continueOutcomes: [.success(.rebased(try rebasedBranch()))]
        )

        await store.syncBranch(summary())

        #expect(store.branchSyncTasks[pr] == nil)
        #expect(!store.busyRepositories.contains(pr.repo))
        #expect(store.branchSyncActivityLine(for: pr) == nil)
    }
}
