import Foundation
import Testing

@testable import PRism

/// Srovnání větve, jak ho skládá store (#466) — `Rebase`.
///
/// **Nic se nepushuje.** `git` je podstrčený shell skript v dočasné složce, který zapíše, s jakými
/// argumenty byl spuštěn, a vypíše připravený výstup. Fake pusher by se sem podstrčit nedal —
/// `AppStore` si podle tvrdé podmínky č. 1 nesmí držet ani továrnu na cestu ven —, takže je zápis
/// argumentů **jediný** způsob, jak ověřit, že se nepushovalo. Tatáž scéna jako u merge (#465).
///
/// Nejcennější tvrzení jsou tady ta, která říkají, že se **nestalo nic**: bez povolení, na cizím
/// PR, nad konfliktem ani nad rozdělaným rebasem se `git push` nespustí.
@Suite("AppStore — srovnání větve")
@MainActor
struct AppStoreBranchSyncTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#8")!
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "git-calls.log")
    }

    // MARK: - Prostředí testu

    private func configuration(publishing: Bool, mine: Bool) -> Configuration {
        var configuration = Configuration.standard
        if publishing {
            configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        }
        configuration.global.ownLogins = mine ? ["autor"] : []
        return configuration
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "chore: sync probe",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(
        state: PullRequestState = .open,
        crossRepository: Bool? = false
    ) -> PullRequest {
        PullRequest(
            id: pr,
            title: "chore: sync probe",
            author: "autor",
            headSha: Self.head,
            baseSha: "bbbb2222",
            headRef: "prism-sync-probe",
            baseRef: "master",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: crossRepository
        )
    }

    /// Stav větve, která je **o dva commity pozadu** — tedy stav, ve kterém se akce nabízí.
    private func behind(_ behind: Int = 2, ahead: Int = 1) -> BranchStatus {
        BranchStatus(
            mergeability: .mergeable,
            mergeState: .clean,
            divergence: BranchDivergence(ahead: ahead, behind: behind)
        )
    }

    /// Pracovní strom **v cache**, jak ho vydá skutečný checkout. Mimo cache by pusher odmítl
    /// pushnout (tvrdá podmínka č. 3) a testy o úspěšné cestě by měřily tu kontrolu, ne push.
    private func syncWorktree() throws -> URL {
        let url = layout.syncWorktree(for: pr)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Hlava PR ve scéně. Vyjmenovaná jako konstanta, protože na ní stojí **lease**: plán
    /// přetlačení musí nést tuhle hodnotu, ne tu, kterou má detail v okamžiku potvrzení.
    private static let head = "aaaa1111"

    private func rebasedBranch(
        headSha: String = "cccc3333",
        from: String = AppStoreBranchSyncTests.head,
        replayed: Int = 2
    ) throws -> RebasedBranch {
        RebasedBranch(
            worktree: try syncWorktree(),
            headSha: headSha,
            rebasedFrom: from,
            arriving: Self.commits(replayed),
            replayed: replayed
        )
    }

    private func rebased(
        headSha: String = "cccc3333",
        from: String = AppStoreBranchSyncTests.head,
        replayed: Int = 2
    ) throws -> RebaseOutcome {
        .rebased(try rebasedBranch(headSha: headSha, from: from, replayed: replayed))
    }

    /// `N` přehraných commitů. Počet se v testech zadává jako číslo (na tom stojí věty v panelu),
    /// seznam je to, co drží model — tak se dopočítá.
    static func commits(_ count: Int) -> [RebasedCommit] {
        (0..<count).map { RebasedCommit(sha: "sha\($0)0000000", title: "chore: krok \($0)") }
    }

    /// Podstrčený `git`: zapíše celou svoji řádku argumentů a skončí zadaným kódem.
    private func fakeGit(output: String = "", exitCode: Int32 = 0) throws -> URL {
        let script = directory.url.appending(path: "git-\(UUID().uuidString).sh")
        let redirect = exitCode == 0 ? "" : ">&2"
        let text = """
        #!/bin/sh
        echo "$@" >> "\(calls.path(percentEncoded: false))"
        cat \(redirect) <<'PRISMOUT'
        \(output)
        PRISMOUT
        exit \(exitCode)
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Řádky, se kterými se `git` doopravdy spustil. Prázdno znamená „nepushovalo se“.
    private func gitCalls() -> [String] {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return [] }
        return TextLines.nonEmpty(text).map(String.init)
    }

    /// `git` se předává **vždycky**, i v testech, které tvrdí, že se nepushovalo: bez cesty ke
    /// `gitu` by akci zakázala už brána (`Policy.metadataEditing`) a tvrzení „nepushlo se“ by
    /// měřilo chybějící nástroj, ne guard, o kterém má být řeč.
    private func prepared(
        git: URL? = nil,
        publishing: Bool = true,
        mine: Bool = true,
        state: PullRequestState = .open,
        crossRepository: Bool? = false,
        status: BranchStatus? = nil,
        outcome: Result<RebaseOutcome, CheckoutError>? = nil,
        worktree: SyncWorktreeState = .empty
    ) async -> (AppStore, FakeRepoCheckout, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail(state: state, crossRepository: crossRepository))
        )
        gateway.branchStatus = status ?? behind()
        let checkout = FakeRepoCheckout()
        if let outcome { checkout.rebaseOutcome = outcome }
        checkout.syncWorktree = worktree
        let tool = try? git ?? fakeGit()
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(publishing: publishing, mine: mine),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            checkout: checkout,
            gh: tool,
            git: tool,
            cacheLayout: layout
        )
        await store.loadDetail(for: summary())
        store.openTab(pr)
        return (store, checkout, gateway)
    }

    // MARK: - Kdy se akce nabízí

    @Test("Vlastní PR pozadu za základem akci nabízí")
    func offersOnAnOwnBranchBehindItsBase() async throws {
        let (store, _, _) = await prepared()

        let section = try #require(store.branchSection(for: pr))
        #expect(section.sync.isAllowed)
        #expect(section.syncPlan?.branch == "prism-sync-probe")
        #expect(section.syncPlan?.expectedRemoteSha == "aaaa1111")
        #expect(section.syncPlan?.behind == 2)
    }

    /// **Otázka na polohu větve jde s hlavou z detailu, ne s jménem větve** — tatáž úvaha jako
    /// u prvního guardu: jméno se dá nastavit na cokoli.
    @Test("Na polohu větve se ptáme základem a hlavou z detailu")
    func asksAboutDivergenceWithTheHeadOid() async throws {
        let (_, _, gateway) = await prepared()

        #expect(
            gateway.branchStatusQueries
                == [FakeGitHubGateway.BranchStatusQuery(id: pr, base: "master", head: "aaaa1111")]
        )
    }

    @Test("Srovnaná větev se nenabízí")
    func doesNotOfferOnABranchThatIsUpToDate() async throws {
        let (store, _, _) = await prepared(status: behind(0))

        let section = try #require(store.branchSection(for: pr))
        #expect(!section.sync.isAllowed)
        #expect(section.sync.obstacles.contains(.upToDate(base: "master")))
    }

    // MARK: - Nepushovalo se

    /// **Bez povolení se nesloží ani snímek akce**, takže se k pushi nedá dokliknout ani tehdy,
    /// kdyby se na zakázané tlačítko nějak kliknout dalo.
    @Test("Bez povolení se nepushuje a akce se nesloží")
    func refusesToBuildASubmissionWithoutPermission() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), publishing: false)

        #expect(store.branchPushSubmission(for: summary()) == nil)
        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests.isEmpty)
        #expect(gitCalls().isEmpty)
    }

    /// **Na cizím PR se sekce nekreslí vůbec**, takže se odsud nepushuje ani omylem.
    @Test("Na cizí PR se nepushuje a sekce se nekreslí")
    func doesNothingOnAForeignPullRequest() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), mine: false)

        #expect(store.branchSection(for: pr) == nil)
        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests.isEmpty)
        #expect(gitCalls().isEmpty)
        // Sekce se nekreslí, takže se ani nemá co hlásit — hláška u nekreslené sekce by byla
        // věta, kterou nemá kdo přečíst.
        #expect(store.branchSyncState(for: pr) == nil)
    }

    /// **Hlava z forku je zákaz**, ne jen varování: `origin` je základní repozitář, takže by push
    /// mířil jinam, než na co se člověk dívá.
    @Test("Na PR z forku se nepushuje")
    func doesNotPushIntoAFork() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), crossRepository: true)

        let section = try #require(store.branchSection(for: pr))
        #expect(section.sync.obstacles.contains(.foreignBranch(known: true)))
        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests.isEmpty)
        #expect(gitCalls().isEmpty)
    }

    /// **„Nevím, kde větev leží“ je taky zákaz.** Starší uložený detail pole nemá, a z chybějící
    /// odpovědi neplyne, kam se píše.
    @Test("Bez odpovědi o původu větve se nepushuje")
    func doesNotPushWithUnknownBranchOrigin() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), crossRepository: nil)

        let section = try #require(store.branchSection(for: pr))
        #expect(section.sync.obstacles.contains(.foreignBranch(known: false)))
        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests.isEmpty)
        #expect(gitCalls().isEmpty)
    }

    /// **Konflikt se nepřetlačuje.** Rebase se zahodil, v cache po něm nic nezůstalo — a `git`
    /// se spustil jedině na ten rebase, ne na push.
    @Test("Nad konfliktem se nepushuje")
    func doesNotPushOverAConflict() async throws {
        let (store, checkout, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(.conflicted(files: ["composer.lock"], aborted: true))
        )

        await store.syncBranch(summary())

        #expect(checkout.rebaseRequests == [pr])
        #expect(gitCalls().isEmpty)
        #expect(store.branchSyncState(for: pr) == .conflicted(files: ["composer.lock"]))
    }

    /// **Nezměněná hlava znamená, že se nesáhne na remote.** Push, po kterém se na remote nic
    /// nezmění, je zbytečné sáhnutí na cizí server a v panelu věta, která tvrdí víc, než co se
    /// stalo — proto vlastní stav, ne `pushed(0)`.
    @Test("Když se hlava nezměnila, do remote se nesáhne")
    func doesNotPushWhenTheHeadDidNotMove() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased(headSha: Self.head, replayed: 0))
        )

        await store.syncBranch(summary())

        #expect(gitCalls().isEmpty)
        #expect(store.branchSyncState(for: pr) == .alreadyInSync)
    }

    /// **Rozdělaný rebase v cache akci zastaví**, dokud ho člověk nezahodí — a je to jediné
    /// místo, odkud se to dělá.
    @Test("Rozdělaný rebase akci zastaví a jde zahodit")
    func stopsOnAnUnfinishedRebaseAndCanDiscardIt() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), worktree: .unfinishedRebase)

        #expect(store.branchSyncState(for: pr) == .unfinished(files: []))
        let section = try #require(store.branchSection(for: pr))
        #expect(!section.sync.isAllowed)
        #expect(section.sync.obstacles.contains(.unfinishedRebase))

        await store.discardSync(for: pr)

        #expect(checkout.discardRequests == [pr])
        #expect(store.branchSyncState(for: pr) == nil)
        #expect(gitCalls().isEmpty)
        #expect(try #require(store.branchSection(for: pr)).sync.isAllowed)
    }

    /// **Rozdělaná práce se hledá při každém otevření vlastního PR**, ne jen po neúspěšném pokusu
    /// — ale **nález nepřepíše hlášku z právě proběhlého pokusu**. Ta zná jména kolidujících
    /// souborů, kdežto nález ne, takže by věta v panelu zhrubla.
    @Test("Hláška z posledního pokusu se nálezem nepřepíše")
    func doesNotOverwriteAFresherState() async throws {
        let (store, checkout, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(.conflicted(files: ["src/App.php"], aborted: false))
        )

        await store.syncBranch(summary())
        #expect(store.branchSyncState(for: pr) == .unfinished(files: ["src/App.php"]))

        // Druhý příchod na PR — v cache to tam ten rebase doopravdy leží, ale jména nezná.
        checkout.syncWorktree = .unfinishedRebase
        await store.loadBranchStatus(for: summary())

        #expect(store.branchSyncState(for: pr) == .unfinished(files: ["src/App.php"]))
    }

    /// **Selhání zahození se hlásí**, nespolkne: rozdělaný rebase by v cache zůstal, kdežto okno
    /// by hlásilo uklizeno.
    @Test("Nepovedené zahození se hlásí")
    func reportsAFailedDiscard() async throws {
        let (store, checkout, _) = await prepared(git: try fakeGit(), worktree: .unfinishedRebase)
        checkout.discardFailure = .gitFailed(exitCode: 128, message: "no rebase in progress")

        await store.discardSync(for: pr)

        #expect(store.branchSyncState(for: pr)?.isBusy == false)
        #expect(store.branchSyncState(for: pr)?.hasUnfinishedRebase == false)
        let sentence = try #require(store.branchSyncState(for: pr)?.sentence)
        #expect(sentence.contains("Nepovedlo se"))
    }

    // MARK: - První krok nepushuje

    /// **Nejcennější test celého rozdělení akce**: první krok doběhne, v cache leží srovnaná větev
    /// — a `git push` se **nespustil**.
    ///
    /// Do rozdělení dělalo jedno kliknutí obojí naráz. Teď je mezi tím potvrzení, a kdyby se to
    /// někdy „zjednodušilo“ zpátky, pozná se to tady: nula spuštění `gitu` je jediné, co o tom
    /// dokáže něco tvrdit (fake pusher se do store podstrčit nedá — tvrdá podmínka č. 1 mu tam
    /// nedovolí ani továrnu).
    @Test("Rebase nepushuje a skončí mezistavem")
    func rebaseDoesNotPush() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased())
        )

        await store.syncBranch(summary())

        #expect(gitCalls().isEmpty)
        #expect(store.branchSyncState(for: pr) == .rebased(try rebasedBranch()))
        let sentence = try #require(store.branchSyncState(for: pr)?.sentence)
        #expect(sentence.contains("Do remote se zatím nesáhlo"))
    }

    /// **Nad přerovnanou větví se druhý rebase nenabízí.** Přehrát commity znovu nad výsledkem,
    /// který ještě neodešel, by tu práci zahodilo potichu.
    @Test("Nad přerovnanou větví se rebase nenabízí")
    func doesNotOfferASecondRebase() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())

        let section = try #require(store.branchSection(for: pr))
        #expect(!section.sync.isAllowed)
        #expect(section.sync.obstacles.contains(.rebasedNotPushed))
    }

    /// **Hlášku o práci v cache nejde „zavřít“.** Zavřít ji by tu práci schovalo, aniž by zmizela
    /// — a to je zrovna ten tichý stav, kterému se celá akce vyhýbá. Zahodit ano, schovat ne.
    @Test("Mezistav se nedá zavřít, jen zahodit")
    func refusesToHideDiscardableWork() async throws {
        let (store, checkout, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())

        store.clearBranchSync(for: pr)
        #expect(store.branchSyncState(for: pr)?.rebasedBranch != nil)

        await store.discardSync(for: pr)
        #expect(checkout.discardRequests == [pr])
        #expect(store.branchSyncState(for: pr) == nil)
        #expect(gitCalls().isEmpty)
    }

    /// **Mezistav se hledá i po restartu aplikace.** Mezi rebasem a potvrzením může být libovolně
    /// dlouhá pauza; strom v cache **je** ten záznam, nikam jinam se to nezapisuje.
    @Test("Přerovnaná větev v cache se najde při otevření PR")
    func findsARebasedBranchOnOpening() async throws {
        let branch = try rebasedBranch()
        let (store, _, _) = await prepared(git: try fakeGit(), worktree: .rebased(branch))

        #expect(store.branchSyncState(for: pr) == .rebased(branch))
        #expect(gitCalls().isEmpty)
    }

    // MARK: - Druhý krok: jedině přes potvrzení

    /// **Bez mezistavu se potvrzení nesloží**, takže se nedá pushnout nic, co nikdo nepřehrál.
    @Test("Bez přerovnané větve se potvrzení nesloží")
    func refusesToBuildAPushWithoutARebasedBranch() async throws {
        let (store, _, _) = await prepared(git: try fakeGit())

        #expect(store.branchPushSubmission(for: summary()) == nil)
        #expect(gitCalls().isEmpty)
    }

    /// **Brána se ověřuje i u druhého kroku.** Mezi rebasem a potvrzením se mohla vypnout
    /// v nastavení — a tlačítko, které skončí na bráně, je horší než zašedlé.
    @Test("Vypnutá brána zastaví i druhý krok")
    func refusesToBuildAPushWithoutPermission() async throws {
        let branch = try rebasedBranch()
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            publishing: false,
            worktree: .rebased(branch)
        )

        #expect(store.branchPushSubmission(for: summary()) == nil)
        #expect(gitCalls().isEmpty)
    }

    /// **Lease se skládá z hlavy, ze které se rebasovalo** — ne z té, kterou má detail teď.
    ///
    /// Je to pojistka, která vznikla až rozdělením akce: mezi rebasem a potvrzením se hlava PR může
    /// pohnout (push z jiného stroje, z terminálu, z GitHubu). S **aktuální** hodnotou by lease
    /// prošel a ten nový commit přepsal; s touhle na něj narazí pre-flight a nepřetlačí nic.
    @Test("Lease nese hlavu, ze které se rebasovalo")
    func leaseCarriesTheHeadTheRebaseStartedFrom() async throws {
        let branch = try rebasedBranch(from: "starahlava")
        let (store, _, _) = await prepared(git: try fakeGit(), worktree: .rebased(branch))

        let submission = try #require(store.branchPushSubmission(for: summary()))

        #expect(submission.plan.expectedRemoteSha == "starahlava")
        #expect(submission.plan.expectedRemoteSha != Self.head)
        #expect(submission.plan.sha == branch.headSha)
        #expect(submission.replayed == branch.replayed)
        // Snímek se složil a **pořád se nepushovalo** — na to je potřeba klik v sheetu.
        #expect(gitCalls().isEmpty)
    }

    /// Úspěšná cesta: potvrzení, a teprve pak push s **vypsaným leasem**.
    @Test("Potvrzení pushne s lease na hlavu z rebase")
    func pushesWithALeaseAfterConfirming() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))

        await submission.push()

        let push = try #require(gitCalls().first { $0.contains(" push ") })
        #expect(push.contains("--force-with-lease=refs/heads/prism-sync-probe:\(Self.head)"))
        #expect(push.contains("cccc3333:refs/heads/prism-sync-probe"))
        // Zdrojová strana je **sha z rebase, ne `HEAD`**: mezi rebasem a pushem si člověk mohl
        // ve stromě něco zkusit z terminálu.
        #expect(!push.contains(" HEAD:"))
        #expect(store.branchSyncState(for: pr) == .pushed(replayed: 2))
    }

    /// **Záložka zůstává otevřená**, na rozdíl od merge (#465): pull request žije dál a člověk na
    /// něm obvykle pokračuje.
    @Test("Po přetlačení se záložka nezavírá")
    func keepsTheTabOpenAfterPushing() async throws {
        let (store, _, gateway) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))

        await submission.push()

        #expect(store.openTabs == [pr])
        // Hlava se změnila, takže se detail i stav větve načtou znovu — jinak by v panelu stála
        // stará hlava a akce by se nabízela podruhé nad tím, co už je hotové.
        #expect(gateway.detailRequests.count > 1)
    }

    // MARK: - Po force pushi se hlava dotáhne (z proklikání)

    /// **Po úspěšném force pushi musí být hlava PR nová, jinak nejde mergnout.**
    ///
    /// Merge posílá `sha` **v payloadu** (tvrdá podmínka č. 1, druhá pojistka z #465), takže
    /// s vlastní starou hlavou skončí na `409`. Po pushi se proto zahazuje `detailStates`
    /// a detail se načte znovu.
    ///
    /// **Hlava se nezapisuje z výsledku rebasu, ptá se GitHub** — a je to rozhodnutí. Náš sha je
    /// pravda k okamžiku pushe; kdyby nás mezitím někdo přeběhl, byla by z něj lež a panel by
    /// tvrdil hlavu, kterou nikdo nepotvrdil. Navíc se po force pushi **přepočítávají checky**,
    /// které merge blokují, takže se detail musí načíst celý, ne jen jedno pole. Že se ref po
    /// acku pushe čte **okamžitě aktuální**, je změřené na `prism-review-sandbox`
    /// (`git/ref/heads/…` vrátilo novou hlavu na první pokus).
    ///
    /// Scéna je vyjádřitelná jedině proto, že fake umí **změnit odpověď** (`detailFromNowOn`) —
    /// tatáž věc, která u posunu základu chyběla.
    @Test("Po úspěšném force pushi je hlava nová")
    func fetchesTheNewHeadAfterASuccessfulPush() async throws {
        let (store, _, gateway) = await prepared(outcome: .success(try rebased()))
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        // **Pre-flight ještě vidí starou hlavu** (jinak by push odmítl jako `headMoved`),
        // po pushi už je na remote ta nová. Poslední odpověď se opakuje.
        gateway.detailsInOrder = [.success(detail()), .success(pushedDetail())]
        let before = gateway.detailRequests.count

        await submission.push()

        #expect(submission.state == .pushed("cccc3333"))
        #expect(gateway.detailRequests.count > before, "detail se po pushi musí načíst znovu")
        #expect(store.detail(of: pr)?.headSha == "cccc3333")
        // A to je zrovna ta hodnota, kterou merge posílá v payloadu.
        #expect(Policy.mergeProposal(of: store.detail(of: pr), commits: [])?.headSha == "cccc3333")
    }

    /// **Druhý směr: po neúspěšném pushi se hlava nemění.** Tohle je ta cennější polovina —
    /// přepsat detail po selhání by zahodilo stav, ve kterém je vidět, co se nepovedlo, a hlavně
    /// by tvrdilo hlavu, která na remote není.
    @Test("Po neúspěšném force pushi se hlava nemění")
    func keepsTheOldHeadAfterAFailedPush() async throws {
        let refusal = """
        To https://github.com/ondrajodas/prism-review-sandbox.git
         ! [rejected]        cccc3333 -> prism-sync-probe (stale info)
        error: failed to push some refs
        """
        let (store, _, gateway) = await prepared(
            git: try fakeGit(output: refusal, exitCode: 1),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        // Pre-flight vidí starou hlavu, takže se dojde až k pushi — a ten selže. Druhá odpověď je
        // v sekvenci schválně: kdyby se po selhání detail načítal, dostala by se do okna nová
        // hlava, která na remote **není**.
        gateway.detailsInOrder = [.success(detail()), .success(pushedDetail())]

        await submission.push()

        #expect(submission.state == .failed(.leaseRejected))
        // **Tvrdí se uložená hlava, ne počet dotazů.** Pre-flight se na detail ptá vždycky, i když
        // push potom selže, takže počet by tady měřil pre-flight — ne to, jestli se po selhání
        // obnovovalo. Rozhoduje, co zůstalo v okně.
        #expect(store.detail(of: pr)?.headSha == Self.head)
        // A stav větve zůstává taky, takže je pořád vidět, co selhalo.
        #expect(store.branchSyncState(for: pr)?.rebasedBranch != nil)
    }

    /// **Po pushi se čeká na hlavu, a teprve pak se tahá detail** (#466, z proklikání).
    ///
    /// Změřeno na `prism-review-sandbox#10`: objekt pull requestu je po force pushi 1,45–2,16 s
    /// nekonzistentní, takže detail načtený hned po acku pushe nese **starou** hlavu — a merge
    /// s ní skončí na `409`, protože ji posílá v payloadu. Tady se to modeluje tím, že `fetchHeads`
    /// vrátí nejdřív starou hlavu a až potom tu novou.
    @Test("Po pushi se čeká, dokud PR nehlásí pushnutou hlavu")
    func waitsForThePushedHead() async throws {
        let (store, _, gateway) = await prepared(outcome: .success(try rebased()))
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        gateway.detailsInOrder = [.success(detail()), .success(pushedDetail())]
        // **Sekvence, ne odmlka**: první dva dotazy vidí starou hlavu, třetí tu novou. Časovat to
        // pauzou nešlo — první dotaz padne až za podprocesem `git`, takže test měřil něco jiného.
        gateway.headsInOrder = [
            [pr: PullRequestHead(sha: Self.head, committedAt: nil)],
            [pr: PullRequestHead(sha: Self.head, committedAt: nil)],
            [pr: PullRequestHead(sha: "cccc3333", committedAt: nil)],
        ]

        await submission.push()

        #expect(submission.state == .pushed("cccc3333"))
        #expect(store.detail(of: pr)?.headSha == "cccc3333")
        // **Ptalo se `fetchHeads`, ne plným detailem** — je to `cost = 1` a jedna hodnota.
        #expect(gateway.headRequests == [[pr], [pr], [pr]])
    }

    /// **Čekání má tvrdý strop.** Kdyby ho nemělo, byl by z toho dotazovací cyklus nad cizím API —
    /// a to je ta věc, které se stráž z #465 vyhýbá. Tady hlava nedorazí **nikdy**, takže se musí
    /// přestat ptát a nechat, co GitHub říká; příští tik nebo `⟳` to dorovná.
    @Test("Když pushnutá hlava nedorazí, přestane se ptát")
    func stopsAskingWhenTheHeadNeverArrives() async throws {
        let (store, _, gateway) = await prepared(outcome: .success(try rebased()))
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        // Hlava nedorazí nikdy — poslední odpověď sekvence se opakuje.
        gateway.headsInOrder = [[pr: PullRequestHead(sha: Self.head, committedAt: nil)]]

        await submission.push()

        #expect(submission.state == .pushed("cccc3333"))
        #expect(gateway.headRequests.count == Policy.pushedHeadAttempts)
        // A **netvrdí se nová hlava**: co GitHub naposled řekl, to v okně zůstane.
        #expect(store.detail(of: pr)?.headSha == Self.head)
    }

    /// **Selhání dotazu na hlavu čekání ukončí**, neopakuje se. „Nezeptal jsem se“ není „hlava
    /// nedorazila“, a opakovat něco, co spadlo na síti, by jen protahovalo zavření sheetu.
    @Test("Selhání dotazu na hlavu se neopakuje")
    func doesNotRetryAfterAFailedHeadQuery() async throws {
        let (store, _, gateway) = await prepared(outcome: .success(try rebased()))
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        gateway.headsFailure = GitHubError.timedOut

        await submission.push()

        #expect(submission.state == .pushed("cccc3333"))
        #expect(gateway.headRequests.count == 1)
    }

    /// **Hláška o úspěchu je v panelu dřív, než začne úklid** — na tom stojí zavírání sheetu.
    /// Sheet se na `.pushed` zavře, takže kdyby výsledek nesl jen on, zmizel by s ním.
    @Test("Panel nese výsledek pushe, i když se sheet zavře")
    func theOutcomeStaysInThePanel() async throws {
        let (store, _, gateway) = await prepared(outcome: .success(try rebased()))
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))
        gateway.detailsInOrder = [.success(detail()), .success(pushedDetail())]
        gateway.headsInOrder = [[pr: PullRequestHead(sha: "cccc3333", committedAt: nil)]]

        await submission.push()

        #expect(submission.closesItself, "sheet se po úspěchu zavírá")
        let sentence = try #require(store.branchSyncState(for: pr)?.sentence)
        #expect(sentence.contains("force push"))
        #expect(sentence.contains("2"), "věta nese počet přehraných commitů")
    }

    /// **Po selhání se sheet nezavírá** — je to jediné místo, kde je vidět, co server odmítl.
    @Test("Po selhání se sheet nezavírá")
    func keepsTheSheetOpenOnFailure() async throws {
        let refusal = """
        To https://github.com/ondrajodas/prism-review-sandbox.git
         ! [rejected]        cccc3333 -> prism-sync-probe (stale info)
        error: failed to push some refs
        """
        let (store, _, _) = await prepared(
            git: try fakeGit(output: refusal, exitCode: 1),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))

        await submission.push()

        #expect(!submission.closesItself)
    }

    /// Detail s **novou** hlavou — tedy to, co na remote leží po úspěšném force pushi.
    private func pushedDetail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "chore: sync probe",
            author: "autor",
            headSha: "cccc3333",
            baseSha: "bbbb2222",
            headRef: "prism-sync-probe",
            baseRef: "master",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            isCrossRepository: false
        )
    }

    /// **Odmítnutý lease je vlastní stav a vlastní věta** (zadání #466): remote se pohnul a nic se
    /// nepřepsalo. Text `stale info` je ten, který `git` v té situaci doopravdy vypíše — změřeno na
    /// `prism-review-sandbox`.
    ///
    /// **Druhý pokus se odsud ale nenabízí, a je to změna ze čtvrtého kola revize.** Do té doby tu
    /// stálo „dá se to zkusit znovu“ a `canPush` se tvrdilo `true`. Retry přitom posílá **tentýž
    /// plán** s tímtéž `expectedRemoteSha`, takže by lease odmítl **identicky** — cesta dál vede
    /// přes obnovení dat, a to je to, co říká i věta u té chyby.
    @Test("Odmítnutý lease se pozná od jiné chyby")
    func tellsARejectedLeaseFromOtherFailures() async throws {
        let refusal = """
        To https://github.com/ondrajodas/prism-review-sandbox.git
         ! [rejected]        cccc3333 -> prism-sync-probe (stale info)
        error: failed to push some refs
        """
        let (store, _, _) = await prepared(
            git: try fakeGit(output: refusal, exitCode: 1),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))

        await submission.push()

        #expect(submission.state == .failed(.leaseRejected))
        #expect(BranchSyncError.leaseRejected.sentence.contains("pohnula"))
        #expect(!BranchSyncError.leaseRejected.sentence.contains("stale info"))
        // **Druhý pokus se nenabízí**: tentýž plán by narazil na tentýž lease.
        #expect(!submission.canPush)
        // A **mezistav v cache zůstává**, takže se k druhému pokusu dá vrátit i po zavření sheetu.
        #expect(store.branchSyncState(for: pr)?.rebasedBranch != nil)
    }

    /// Jiné selhání pushe **nesmí** vyjít jako odmítnutý lease: z lease plyne „zkus to znovu“,
    /// z odmítnutého přihlášení něco jiného. A tlačítko se u něj **zakáže**.
    @Test("Jiné selhání pushe má jinou větu a nepustí druhý pokus")
    func hasADifferentSentenceForOtherFailures() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(output: "fatal: could not read Username", exitCode: 128),
            outcome: .success(try rebased())
        )
        await store.syncBranch(summary())
        let submission = try #require(store.branchPushSubmission(for: summary()))

        await submission.push()

        #expect(submission.state != .failed(.leaseRejected))
        if case .failed = submission.state {} else { Issue.record("čekalo se selhání") }
        #expect(store.branchSyncState(for: pr)?.rebasedBranch != nil)
    }

    // MARK: - Selhání prvního kroku

    /// **Selhání rebase se nevydává za konflikt.** Neznámý základ nebo nespustitelný `git` jsou
    /// chyby, ze kterých plyne něco jiného než „vyřeš to v terminálu“.
    @Test("Selhání rebase se hlásí jako chyba, ne jako konflikt")
    func reportsARebaseFailureAsAFailure() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .failure(.gitFailed(exitCode: 128, message: "unknown revision"))
        )

        await store.syncBranch(summary())

        #expect(gitCalls().isEmpty)
        #expect(store.branchSyncState(for: pr)?.hasDiscardableWork == false)
        let sentence = try #require(store.branchSyncState(for: pr)?.sentence)
        #expect(!sentence.contains("konflikt"))
    }

    /// Hlášku, za kterou v cache **nic neleží**, jde zavřít.
    @Test("Hláška bez práce v cache se zavře")
    func clearsANoticeWithNothingBehindIt() async throws {
        let (store, _, _) = await prepared(
            git: try fakeGit(),
            outcome: .success(try rebased(headSha: Self.head, replayed: 0))
        )
        await store.syncBranch(summary())
        #expect(store.branchSyncState(for: pr) == .alreadyInSync)

        store.clearBranchSync(for: pr)
        #expect(store.branchSyncState(for: pr) == nil)
    }
}
