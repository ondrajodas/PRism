import Foundation
import Testing

@testable import PRism

/// Sekce `Větev` a merge, jak je skládá store (#465).
///
/// **Nic se nemerguje**: `gh` je podstrčený shell skript v dočasné složce, který vypíše
/// připravenou odpověď a zapíše, kolikrát byl spuštěn. Fake publisher by se sem podstrčit nedal —
/// `AppStore` si ho podle tvrdé podmínky č. 1 nesmí držet ani jako továrnu. Počítadlo spuštění je
/// jediný způsob, jak ověřit, že se **nevolalo nic**; tatáž scéna jako u labelů (#392).
@Suite("AppStore — větev a merge")
@MainActor
struct AppStoreMergeTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#8")!
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "gh-calls.log")
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
            title: "chore: merge probe",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(state: PullRequestState = .open) -> PullRequest {
        PullRequest(
            id: pr,
            title: "chore: merge probe",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "prism-merge-probe",
            baseRef: "master",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    private func commit() -> PullRequestCommit {
        PullRequestCommit(
            sha: "aaaa1111",
            message: "chore: merge probe",
            authorName: "autor",
            authorLogin: "autor",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 100),
            isMerge: false
        )
    }

    private let mergedOutput = """
    {"sha":"d5e454dd4838a98ce88339531517411941233813","merged":true,"message":"Pull Request successfully merged"}
    """

    /// Odmítnutí merge se zastaralou hlavou, **zkrácené na to, co store zajímá**. Plná změřená
    /// odpověď leží ve fixture `gh/merge-error-head-modified.json` a rozbor nad ní dělají
    /// `MergePublishingTests`; tady se testuje store, ne dekódování. Sdílené, protože o téže
    /// odpovědi tvrdí něco dva testy a rozejít se ta dvě tvrzení nesmí.
    private let refusalOutput = """
    {"message":"Head branch was modified. Review and try the merge again.","status":"409"}
    """

    private func fakeGh(_ output: String, exitCode: Int32 = 0) throws -> URL {
        let script = directory.url.appending(path: "gh-\(UUID().uuidString).sh")
        let redirect = exitCode == 0 ? "" : ">&2"
        let text = """
        #!/bin/sh
        echo "call" >> "\(calls.path(percentEncoded: false))"
        cat \(redirect) <<'PRISMJSON'
        \(output)
        PRISMJSON
        exit \(exitCode)
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Kolikrát se `gh` doopravdy spustilo. Nula znamená „nemergovalo se“.
    private func ghCalls() throws -> Int {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func prepared(
        gh: URL? = nil,
        publishing: Bool = true,
        mine: Bool = true,
        state: PullRequestState = .open,
        status: BranchStatus = BranchStatus(mergeability: .mergeable, mergeState: .clean),
        statusFailure: (any Error)? = nil,
        checks: [PullRequestCheck] = []
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail(state: state))
        )
        gateway.branchStatus = status
        gateway.branchStatusFailure = statusFailure
        gateway.checks = checks
        gateway.commits = [commit()]
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(publishing: publishing, mine: mine),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            gh: gh
        )
        await store.loadDetail(for: summary())
        // Merge se spouští z panelu, tedy nad **otevřenou záložkou** — a od #465 je zavření té
        // záložky součástí úklidu po mergi, takže scéna bez ní by o tom nemohla tvrdit nic.
        store.openTab(pr)
        return (store, gateway)
    }

    // MARK: - Kdy se stav vůbec tahá

    @Test("Stav větve se dotáhne s detailem")
    func loadsWithTheDetail() async throws {
        let (store, gateway) = await prepared()

        #expect(gateway.branchStatusRequests == [pr])
        #expect(store.branchStatusState(for: pr)?.status?.mergeability == .mergeable)
    }

    /// **Na cizí PR se neptáme vůbec.** Sekce se tam nekreslí, takže by to bylo volání za nic —
    /// a je to zrovna to volání, které si na straně GitHubu vyžádá výpočet.
    @Test("Na cizí PR se na slévatelnost neptáme")
    func doesNotAskOnAForeignPullRequest() async throws {
        let (store, gateway) = await prepared(mine: false)

        #expect(gateway.branchStatusRequests.isEmpty)
        #expect(store.branchSection(for: pr) == nil)
    }

    /// **Ani na mergnutý.** Vrací `UNKNOWN` navždycky (změřeno na `PRism#470`), takže by se na něm
    /// vyčerpaly všechny pokusy včetně čekání mezi nimi.
    @Test("Na mergnutý PR se na slévatelnost neptáme")
    func doesNotAskOnAMergedPullRequest() async throws {
        let (_, gateway) = await prepared(state: .merged)

        #expect(gateway.branchStatusRequests.isEmpty)
    }

    /// Načtený stav se **drží**: druhý příchod na PR se ptát nemá, jinak by z toho byl polling.
    @Test("Druhý příchod na PR se neptá znovu")
    func doesNotRefetchOnTheSecondVisit() async throws {
        let (store, gateway) = await prepared()

        await store.loadDetail(for: summary())

        #expect(gateway.branchStatusRequests == [pr])
    }

    // MARK: - Posun základu (#466, z proklikání)

    /// **Tohle je ta chybějící polovina tvrzení o cache.** „Druhý příchod na PR se neptá znovu“
    /// výš hlídá směr, ve kterém je držení stavu **správné** — a právě proto vada prošla: nic
    /// netvrdilo opačný směr, tedy že se stav přeptá, když se pohnul **základ**.
    ///
    /// Napsat se to s razítkem `updatedAt` ani nedalo. Změřeno na `prism-review-sandbox#9`: po
    /// commitu do `master`u zůstal `updated_at` PR **nezměněný** a `base.sha` i `baseRefOid`
    /// ukazovaly hlavu z doby vzniku PR — takže „PR se nezměnil, ale základ ano“ je stav, o kterém
    /// razítko PR nevypovídá vůbec.
    @Test("Tik přeptá polohu větve, i když se PR nezměnil")
    func refreshesDivergenceWhenTheBaseMoves() async throws {
        let (store, gateway) = await prepared()
        // Stav načtený s detailem tvrdí `srovnaná`.
        #expect(store.branchStatusState(for: pr)?.status?.divergence?.behind == nil)

        // Do základu přišel commit. Na pull requestu se tím nezměnilo nic — `summary()` vrací
        // pořád totéž razítko, což je celý ten měřený případ.
        gateway.divergence = BranchDivergence(ahead: 1, behind: 1)
        await store.refreshOpenDivergence()

        #expect(store.branchStatusState(for: pr)?.status?.divergence?.behind == 1)
        #expect(gateway.divergenceQueries.map(\.id) == [pr])
        // **Drahá polovina se nepřepočítávala**: stráž z #465 platí dál, takže na `mergeable` padl
        // pořád jen ten jeden dotaz z načtení detailu.
        #expect(gateway.branchStatusRequests == [pr])
    }

    /// **Na cizí PR se neptáme ani na polohu větve.** Sekce `Větev` se tam nekreslí, takže by to
    /// bylo volání za nic — tatáž podmínka jako u slévatelnosti.
    @Test("Na cizí PR se na polohu větve neptáme")
    func doesNotRefreshDivergenceOnAForeignPullRequest() async throws {
        let (store, gateway) = await prepared(mine: false)

        await store.refreshOpenDivergence()

        #expect(gateway.divergenceQueries.isEmpty)
    }

    /// **Bez otevřené záložky se neptáme.** Ta hodnota se kreslí jedině v panelu otevřeného PR;
    /// seznam ani přehled o „pozadu“ netvrdí nic, takže by je dotaz jen zdržoval.
    @Test("Bez otevřeného PR se na polohu větve neptáme")
    func doesNotRefreshDivergenceWithNoOpenPullRequest() async throws {
        let (store, gateway) = await prepared()
        store.closeTab(pr)

        await store.refreshOpenDivergence()

        #expect(gateway.divergenceQueries.isEmpty)
    }

    /// **Selhání nic nemaže.** Odpověď, kterou máme, je pořád lepší než prázdno — a příští tik to
    /// zkusí znovu. Kdyby se při chybě sítě stav zahodil, blikalo by „nezjistil jsem to“ nad
    /// panelem při každém odpojení.
    @Test("Selhání přeptání nezahodí, co už víme")
    func keepsTheKnownDivergenceOnFailure() async throws {
        let (store, gateway) = await prepared(
            status: BranchStatus(
                mergeability: .mergeable,
                mergeState: .clean,
                divergence: BranchDivergence(ahead: 3, behind: 0)
            )
        )
        gateway.divergenceFailure = GitHubError.timedOut

        await store.refreshOpenDivergence()

        #expect(store.branchStatusState(for: pr)?.status?.divergence?.ahead == 3)
    }

    /// **Bez načteného stavu se nepřeptává.** Načíst ho od nuly umí `loadBranchStatus`; dvě místa,
    /// která tahají tentýž stav, by po otevření PR znamenala dva souběžné dotazy.
    @Test("Nenačtený stav se přeptáním nezakládá")
    func doesNotCreateStatusFromScratch() async throws {
        let (store, gateway) = await prepared(mine: false)
        // Cizí PR stav nemá, takže je to zároveň scéna „stav chybí“.
        #expect(store.branchStatusState(for: pr) == nil)

        await store.refreshOpenDivergence()

        #expect(store.branchStatusState(for: pr) == nil)
        #expect(gateway.divergenceQueries.isEmpty)
    }

    /// **„Nedá se mergnout“ a „nezjistil jsem to“ se nesmí slít.** Po chybě sítě je stav `failed`
    /// a merge se nenabízí — ne proto, že by to nešlo, ale proto, že se to neví.
    @Test("Selhání se nezahodí do prázdna")
    func failureIsNotSilentlyEmpty() async throws {
        let (store, _) = await prepared(statusFailure: GitHubError.network("spadlo to"))

        #expect(store.branchStatusState(for: pr)?.status == nil)
        #expect(store.branchStatusState(for: pr)?.failure != nil)
        let section = try #require(store.branchSection(for: pr))
        #expect(!section.merge.isAllowed)
    }

    // MARK: - Nic se nemergovalo

    /// **Bez povolení se nemerguje**, a sheet se nad tím ani neotevře: `mergeSubmission(for:)`
    /// vrátí `nil`, takže se nedá dokliknout k tlačítku, které by publisher zavolalo.
    @Test("Bez povolení se merge ani nenabídne")
    func refusesToBuildASubmissionWithoutPermission() async throws {
        let (store, _) = await prepared(gh: try fakeGh(mergedOutput), publishing: false)

        #expect(store.mergeSubmission(for: summary()) == nil)
        #expect(try ghCalls() == 0)
    }

    @Test("Na cizím PR se merge nenabídne")
    func refusesToBuildASubmissionOnAForeignPullRequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(mergedOutput), mine: false)

        #expect(store.mergeSubmission(for: summary()) == nil)
    }

    /// **Červený check merge nenabídne**, i když by ho GitHub pustil — a kontrola je i tady, ne jen
    /// ve view: jediná kontrola ve view je kontrola, kterou příští obrazovka obejde.
    @Test("Nad červeným checkem se merge nenabídne")
    func refusesToBuildASubmissionOverAFailedCheck() async throws {
        let (store, _) = await prepared(
            gh: try fakeGh(mergedOutput),
            checks: [
                PullRequestCheck(name: "test", outcome: .failed, link: nil, startedAt: nil, completedAt: nil),
            ]
        )

        #expect(store.mergeSubmission(for: summary()) == nil)
        #expect(try ghCalls() == 0)
    }

    // MARK: - Co se stane po mergi

    /// Plán, který se potvrzuje, nese to, co je v panelu vidět — a **odesílá se z něj**, ne
    /// z aktuálního stavu storu.
    @Test("Plán nese větev, hlavu i počet commitů")
    func buildsThePlanFromWhatIsOnTheScreen() async throws {
        let (store, _) = await prepared(gh: try fakeGh(mergedOutput))

        let submission = try #require(store.mergeSubmission(for: summary()))

        #expect(submission.plan.head == "prism-merge-probe")
        #expect(submission.plan.base == "master")
        #expect(submission.plan.headSha == "aaaa1111")
        #expect(submission.plan.commits == 1)
        #expect(submission.plan.commitTitle == "chore: merge probe (#8)")
    }

    /// **Po mergi se stav PR načte znovu**, takže panel nenabízí `Mergnout…` u něčeho, co je
    /// mergnuté — a nečeká se na tik pollingu.
    ///
    /// Že se z toho stane `notOpen(.merged)`, tvrdí `BranchMergeTests` nad čistou funkcí; tady se
    /// tvrdí ta polovina, kterou umí říct jedině store: **že se pro ten stav došlo znovu**.
    /// Podstrčit mergnutý detail dopředu tady nejde — pre-flight publisheru se ptá tou samou
    /// gateway, takže by merge odmítl ještě před voláním.
    @Test("Po mergi se PR přečte znovu")
    func rereadsThePullRequestAfterMerging() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(mergedOutput))
        let submission = try #require(store.mergeSubmission(for: summary()))
        let beforeMerge = gateway.detailRequests.count

        await submission.merge()

        #expect(submission.state == .merged(
            MergedPullRequest(sha: "d5e454dd4838a98ce88339531517411941233813")
        ))
        #expect(try ghCalls() == 1, "merge je jedno volání")
        // Dvě čtení navíc: pre-flight publisheru a načtení stavu po mergi. To druhé je to, na čem
        // stojí, že panel nenabídne merge podruhé.
        #expect(gateway.detailRequests.count == beforeMerge + 2)
    }

    /// **Neúspěch nemění nic**: PR zůstává otevřený, sekce dál nabízí merge a chyba je vidět v tom
    /// jednom sheetu, který ji vyvolal.
    @Test("Po odmítnutém mergi zůstává nabídka i stav")
    func keepsTheOfferAfterARefusedMerge() async throws {
        let (store, _) = await prepared(gh: try fakeGh(refusalOutput, exitCode: 1))
        let submission = try #require(store.mergeSubmission(for: summary()))

        await submission.merge()

        guard case .failed(let error) = submission.state else {
            Issue.record("čekalo se selhání, přišlo \(submission.state)")
            return
        }
        guard case .branchMoved = error else {
            Issue.record("čekal se branchMoved, přišlo \(error)")
            return
        }
        #expect(submission.canMerge, "GitHub odmítl, takže se dá zkusit znovu")
        #expect(store.branchSection(for: pr)?.merge.isAllowed == true)
    }

    // MARK: - Záložka (#465)

    /// **Po úspěšném mergi se záložka zavře.** Zavírá ji klik na `Mergnout`, tedy člověk — pravidlo
    /// „mergnutý PR jde ještě dočíst a zavřít ho má člověk, ne tik pollingu“ se tím neruší, mluví
    /// o pollingu.
    ///
    /// Tvrdí se u toho i `closesItself`, protože sheet a záložka mají odejít **spolu**: sheet nad
    /// zavřenou záložkou by visel nad oknem, které o tom PR nic nekreslí.
    @Test("Po mergi se záložka zavře")
    func closesTheTabAfterMerging() async throws {
        let (store, _) = await prepared(gh: try fakeGh(mergedOutput))
        let submission = try #require(store.mergeSubmission(for: summary()))
        #expect(store.openTabs == [pr])

        await submission.merge()

        #expect(store.openTabs.isEmpty)
        #expect(store.activeTab == .home, "poslední záložka propadá domů")
        #expect(submission.closesItself, "sheet odchází se záložkou, ne zvlášť")
    }

    /// **A po selhání zůstane** — tohle je ta polovina, která se rozbije potichu: se zavřenou
    /// záložkou i sheetem by chybová hláška neměla kde být a `409` by vypadal jako úspěch.
    @Test("Po odmítnutém mergi záložka zůstane")
    func keepsTheTabAfterARefusedMerge() async throws {
        let (store, _) = await prepared(gh: try fakeGh(refusalOutput, exitCode: 1))
        let submission = try #require(store.mergeSubmission(for: summary()))

        await submission.merge()

        #expect(store.openTabs == [pr])
        #expect(store.activeTab == .pullRequest(pr))
        #expect(!submission.closesItself, "sheet zůstává otevřený i s hláškou")
    }

    /// **Zavřením záložky se nic nezahazuje.** Draft leží na disku, takže se zavírá bez ptaní —
    /// a kdyby ho merge smazal, bylo by to to jediné nevratné na jinak vratném zavření.
    ///
    /// Draft se sem **podstrkuje přímo**, na rozdíl od zbytku téhle sady: na vlastním PR se nedá
    /// založit žádnou cestou v aplikaci (#333), takže scéna, ve které leží, vzniká jedině takhle.
    /// Je to případ z minula (draft z doby, kdy PR nebyl můj) — a právě proto se nesmí ztratit
    /// potichu.
    @Test("Merge draft na PR nemaže")
    func keepsTheDraftAfterMerging() async throws {
        let (store, _) = await prepared(gh: try fakeGh(mergedOutput))
        store.drafts[pr] = ReviewDraft(pullRequest: pr, headSha: "aaaa1111", body: "rozepsáno")
        let submission = try #require(store.mergeSubmission(for: summary()))

        await submission.merge()

        #expect(store.hasDraft(pr))
        #expect(store.draft(for: pr)?.body == "rozepsáno")
    }
}
