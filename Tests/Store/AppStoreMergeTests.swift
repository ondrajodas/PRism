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
        let refusal = """
        {"message":"Head branch was modified. Review and try the merge again.","status":"409"}
        """
        let (store, _) = await prepared(gh: try fakeGh(refusal, exitCode: 1))
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
}
