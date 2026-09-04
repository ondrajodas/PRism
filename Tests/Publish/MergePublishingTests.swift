import Foundation
import Testing

@testable import PRism

/// Merge vlastního PR (#465) — publisher proti `FakeProcessRunner`.
///
/// **Osmá cesta ven a ta nejnevratnější**: šest z předchozích sedmi sahalo na pull request nebo na
/// diskuzi, sedmá na labely repozitáře, tahle mění `main`. Testy tady proto tvrdí hlavně to, že se
/// **nemergovalo**: brána, zavřený PR a zastaralá hlava musí skončit dřív, než se sáhne na `gh`.
///
/// Fixtures jsou **skutečné odpovědi**, změřené na `ondrajodas/prism-review-sandbox#8`: úspěšný
/// merge a `409` po pokusu s cizí hlavou. Sonda tam byla pro tenhle účel založená, třikrát
/// pushnutá a nakonec mergnutá.
@Suite("Merge na GitHub")
struct MergePublishingTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 8
    )
    private let head = "0355f856265798748a4bb459223c3641308aeaf0"

    private func detail(state: PullRequestState = .open, head: String? = nil) -> PullRequest {
        PullRequest(
            id: sandbox,
            title: "chore: merge probe for 465",
            author: "ondrajodas",
            headSha: head ?? self.head,
            baseSha: "7b3f740e",
            headRef: "prism-merge-probe-465",
            baseRef: "master",
            url: URL(string: "https://github.com/\(sandbox.repo)/pull/\(sandbox.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    /// Payload té metody, kterou aplikace posílala do #556 — **jeden plán, ať se testy o metodě
    /// nemusí ptát**. Skládá se z návrhu (`MergeProposal`) touž cestou jako v okně, takže se
    /// titulek nemůže rozejít s tím, co vypisuje potvrzení.
    private var plan: MergePlan { proposal.plan(with: .squash) }

    private var proposal: MergeProposal {
        MergeProposal(
            pullRequest: sandbox,
            headSha: head,
            head: "prism-merge-probe-465",
            base: "master",
            commits: 3,
            title: "chore: merge probe for 465"
        )
    }

    private func publisher(
        _ runner: ProcessRunning,
        detail: Result<PullRequest, any Error>? = nil,
        scope: PublishScope? = nil
    ) -> GhReviewPublisher {
        GhReviewPublisher(
            gh: gh,
            runner: runner,
            gateway: FakeGitHubGateway(
                always: .success([]),
                detail: detail ?? .success(self.detail())
            ),
            scope: scope ?? .allowing(sandbox.repo)
        )
    }

    private func merged() throws -> FakeProcessRunner {
        try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/pr-merged.json"))
    }

    // MARK: - Nic se nemergovalo

    /// **Ve výchozím nastavení neodejde nic** — a brána je **první** kontrola v cestě, takže se na
    /// nepovolené repo ani neptáme na detail.
    @Test("Bez povolení se nemerguje")
    func doesNotMergeWithoutPermission() async throws {
        let runner = try merged()
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.merge(plan)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Povolení **jiného** repa nestačí: brána se ptá per repo.
    @Test("Povolení jiného repa merge neodemkne")
    func theGateIsPerRepository() async throws {
        let runner = try merged()
        let publisher = publisher(
            runner,
            scope: .allowing(RepoID(owner: "keboola", name: "connection"))
        )

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.merge(plan)
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Na zavřený a mergnutý PR se nemerguje")
    func doesNotMergeAClosedPullRequest() async throws {
        for state in [PullRequestState.closed, .merged] {
            let runner = try merged()
            let publisher = publisher(runner, detail: .success(detail(state: state)))

            await #expect(throws: PublishError.pullRequestNotOpen(state)) {
                try await publisher.merge(plan)
            }
            #expect(runner.invocations.isEmpty, "pre-flight jde přes gateway, takže se `gh` nespustí")
        }
    }

    /// **Hlava se u merge ověřuje, na rozdíl od labelů a komentářů.** Mergnout kód, který jsi
    /// neviděl, je tatáž záměna jako approve na kód, který jsi neviděl — a merge se na commit
    /// váže, kdežto štítek ne.
    @Test("Na posunutou hlavu se nemerguje")
    func doesNotMergeAMovedHead() async throws {
        let runner = try merged()
        let pushed = "1111111111111111111111111111111111111111"
        let publisher = publisher(runner, detail: .success(detail(head: pushed)))

        await #expect(throws: PublishError.staleDraft(draft: head, head: pushed)) {
            try await publisher.merge(plan)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Prázdná hlava se **nevolá**: bez `sha` by GitHub mergnul, co je zrovna nahoře — tedy přesně
    /// to, čemu ta podmínka brání.
    @Test("Bez hlavy se nic nevolá")
    func doesNotMergeWithoutAHead() async throws {
        let runner = try merged()
        let publisher = publisher(runner)
        let blind = MergeProposal(
            pullRequest: sandbox,
            headSha: "  ",
            head: "prism-merge-probe-465",
            base: "master",
            commits: 3,
            title: "chore: merge probe for 465"
        ).plan(with: .squash)

        await #expect(throws: PublishError.mergeWithoutHead) {
            try await publisher.merge(blind)
        }
        #expect(runner.invocations.isEmpty)
    }

    // MARK: - Co odejde

    /// **Jedno atomické volání** — tvrdá podmínka č. 5 je u merge splněná triviálně.
    @Test("Merge odejde jedním PUT a payload je soubor")
    func sendsOnePut() async throws {
        let runner = try merged()
        let publisher = publisher(runner)

        _ = try await publisher.merge(plan)

        #expect(runner.invocations.count == 1)
        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments[0] == "api")
        #expect(arguments[1] == "repos/ondrajodas/prism-review-sandbox/pulls/8/merge")
        #expect(arguments.contains("PUT"))
        #expect(arguments.contains("--input"))
    }

    /// Payload nese **tři pole a žádné jiné**: `commit_title`, `merge_method` a `sha`.
    ///
    /// `commit_message` v něm schválně **není** — bez něj složí tělo squash commitu GitHub ze zpráv
    /// slévaných commitů, což je v tomhle repu celá historie `main`u. Ověřeno mergem sondy
    /// (`prism-review-sandbox#8`): titulek byl přesně poslaný `commit_title` a pod ním odrážky se
    /// třemi zprávami z větve.
    @Test("Payload nese titulek, metodu a hlavu — a nic víc")
    func buildsTheExpectedPayload() throws {
        let data = try MergeRequest.encoded(MergeRequest.Payload(plan))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json == """
        {"commit_title":"chore: merge probe for 465 (#8)","merge_method":"squash","sha":"\(head)"}
        """)
    }

    /// **Metoda je v plánu a payload ji jen opíše** (#556). Do #556 to byla konstanta; teď je
    /// jedno místo `MergePlan`, ze kterého kreslí potvrzení **i** kóduje payload, takže se ta dvě
    /// místa nemají jak rozejít.
    ///
    /// `rawValue` se porovnává s **literálem**, ne s enumem: je to hodnota, kterou bere GitHub,
    /// takže přepsat ji v enumu musí spadnout tady, ne až u odmítnutého merge.
    @Test("Metodu payload bere z plánu a posílá ji doslova")
    func sendsTheMethodFromThePlan() {
        #expect(MergeRequest.Payload(proposal.plan(with: .squash)).mergeMethod == "squash")
        #expect(MergeRequest.Payload(proposal.plan(with: .mergeCommit)).mergeMethod == "merge")
        #expect(MergeRequest.Payload(proposal.plan(with: .rebase)).mergeMethod == "rebase")
    }

    /// **U merge commitu odejde titulek úmluvou GitHubu, u rebase žádný.**
    ///
    /// `commit_title` se u rebase **vynechává celý**, ne posílá prázdný: `""` by GitHub vzal jako
    /// titulek. Že to synteticky generovaný `encode(to:)` udělá (`encodeIfPresent`), tvrdí tenhle
    /// test nad JSONem, ne nad polem struktury.
    @Test("Payload u rebase titulek vůbec neposílá")
    func omitsTheTitleForRebase() throws {
        let commit = try MergeRequest.encoded(MergeRequest.Payload(proposal.plan(with: .mergeCommit)))
        #expect(try #require(String(data: commit, encoding: .utf8)) == """
        {"commit_title":"Merge pull request #8 from prism-merge-probe-465","merge_method":"merge","sha":"\(head)"}
        """)

        let rebase = try MergeRequest.encoded(MergeRequest.Payload(proposal.plan(with: .rebase)))
        #expect(try #require(String(data: rebase, encoding: .utf8)) == """
        {"merge_method":"rebase","sha":"\(head)"}
        """)
    }

    /// Odpověď se čte **z toho, co potvrdil GitHub** — fixture je skutečný výstup mergnuté sondy.
    @Test("Z odpovědi se přečte commit, který vznikl")
    func readsTheMergeCommit() async throws {
        let publisher = publisher(try merged())

        let merged = try await publisher.merge(plan)

        #expect(merged.sha == "d5e454dd4838a98ce88339531517411941233813")
    }

    /// **`merged: false` není úspěch.** Návratový kód byl nula, takže volání prošlo — ale z odpovědi
    /// neplyne, že se mergovalo, a tvrdit to by bylo tvrzení nad rámec dat.
    @Test("Odpověď bez potvrzeného merge se nebere jako úspěch")
    func refusesAnUnconfirmedMerge() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"{"merged":false,"message":"Base branch was modified."}"#
        )
        let publisher = publisher(runner)

        await #expect(throws: PublishError.malformedResponse("Base branch was modified.")) {
            try await publisher.merge(plan)
        }
    }

    // MARK: - Chyby

    /// **`409` znamená, že zabrala hlava v payloadu** — GitHub nemergnul commit, který nikdo
    /// neviděl. Text je skutečný, změřený pokusem s cizí `sha` na sondě.
    @Test("Posunutá větev se pozná z odpovědi a nic se nemergovalo")
    func classifiesAMovedBranch() throws {
        let text = try Fixture.text("gh/merge-error-head-modified.json")
        let error = PublishError(
            failure: ProcessResult(exitCode: 1, standardOutput: "", standardError: text)
        )

        guard case .branchMoved = error else {
            Issue.record("čekal se branchMoved, přišlo \(error)")
            return
        }
        #expect(!error.mightHaveReachedGitHub)
        #expect(error.userDescription.contains("nemergovalo"))
    }

    /// `Base branch was modified` je totéž z druhé strany a vede ke stejnému kroku, takže se
    /// poznává společný kus věty.
    @Test("Posunutý základ se pozná stejně jako posunutá hlava")
    func classifiesAMovedBase() {
        let error = PublishError(
            failure: ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "gh: Base branch was modified. Review and try the merge again. (HTTP 409)"
            )
        )

        guard case .branchMoved = error else {
            Issue.record("čekal se branchMoved, přišlo \(error)")
            return
        }
    }

    /// `405` znamená, že se stav větve mezi načtením panelu a kliknutím změnil.
    ///
    /// **Text je z dokumentace GitHubu, ne změřený** — vyrobit `405` by chtělo PR v konfliktu nebo
    /// draft, a to se v sandboxu nepodařilo (pokus o převedení PR na draft zakázala permission
    /// brána). Je to inline JSON schválně, aby se nepletl se skutečnými fixtures.
    @Test("Neproveditelný merge se pozná a neradí zkoušet znovu")
    func classifiesAnUnmergeablePullRequest() {
        let error = PublishError(
            failure: ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: #"{"message":"Pull Request is not mergeable","status":"405"}"#
            )
        )

        guard case .notMergeable = error else {
            Issue.record("čekal se notMergeable, přišlo \(error)")
            return
        }
        #expect(!error.mightHaveReachedGitHub)
        #expect(!error.userDescription.contains("Zkus"))
    }

    /// **Druhý pokus se nesmí nabídnout tam, kde se nedá tvrdit, že se nic nestalo** — a takové
    /// stavy jsou dva, ne jeden: `timedOut` a `malformedResponse`. U obou mohl `PUT` doběhnout,
    /// takže druhé kliknutí by mergovalo něco, co už je mergnuté. Odmítnutí od GitHubu (`405`,
    /// `409`) i neodeslaný pokus (`mergeWithoutHead`) jsou naopak jistota, že se nesáhlo na nic.
    @Test("Po nejasném konci se merge nenabízí znovu")
    func doesNotOfferARetryAfterATimeout() {
        #expect(PublishError.timedOut.mightHaveReachedGitHub)
        #expect(PublishError.malformedResponse("").mightHaveReachedGitHub)
        #expect(!PublishError.notMergeable("").mightHaveReachedGitHub)
        #expect(!PublishError.branchMoved("").mightHaveReachedGitHub)
        #expect(!PublishError.mergeWithoutHead.mightHaveReachedGitHub)
    }
}
