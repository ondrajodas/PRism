import Foundation
import Testing

@testable import PRism

/// Skládání rozdělaného review. Proti **skutečnému** `ReviewDraftStore` nad dočasnou složkou
/// — to hlavní na draftu je, že přežije restart, a to fake ověřit neumí.
@Suite("AppStore — rozdělané review")
@MainActor
struct AppStoreDraftTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var head: String { "aaaa1111" }

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary(updatedAt: Date = Date(timeIntervalSince1970: 100)) -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: updatedAt,
            state: .open
        )
    }

    /// Diff s hunkem na nových řádcích 25–27.
    private var diffText: String {
        """
        diff --git a/Cart.php b/Cart.php
        --- a/Cart.php
        +++ b/Cart.php
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """
    }

    private func drafts() -> ReviewDraftStore {
        ReviewDraftStore(layout: layout)
    }

    private func store(
        _ drafts: ReviewDraftStore,
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: detail ?? .success(self.detail()),
                diffs: diffs
            ),
            time: FakeTimeSource(),
            drafts: drafts
        )
    }

    /// Detail je to, odkud se ví, proti kterému commitu se review píše.
    private func prepared(
        _ drafts: ReviewDraftStore,
        detail: Result<PullRequest, any Error>? = nil,
        diffs: [Result<String, any Error>] = []
    ) async -> AppStore {
        let store = store(drafts, detail: detail, diffs: diffs)
        await store.loadDetail(for: summary())
        return store
    }

    private var anchor: DraftAnchor { DraftAnchor(line: 26, side: .right) }

    // MARK: - Komentáře

    @Test("Komentář se uloží a přežije restart")
    func keepsACommentAcrossRestart() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)

        store.addDraftComment(at: anchor, path: "Cart.php", body: "tady chybí kontrola", for: pr)
        await settle()

        #expect(store.draftComments(for: pr).map(\.body) == ["tady chybí kontrola"])
        let restarted = self.store(drafts)
        await restarted.loadStoredDrafts()
        #expect(restarted.draftComments(for: pr).map(\.body) == ["tady chybí kontrola"])
        #expect(restarted.draft(for: pr)?.headSha == head)
    }

    /// Draft se zakládá až v okamžiku, kdy se do něj něco napíše — jinak by v cache ležel
    /// soubor po každém PR, které si někdo jen otevřel.
    @Test("Bez úpravy žádný draft nevzniká")
    func createsNothingWithoutAnEdit() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)

        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    /// Bez `headSha` by draft nešlo označit za zastaralý ani odeslat, takže se nezakládá —
    /// a UI to musí říct místo mlčky zakázaného tlačítka.
    @Test("Bez známé hlavy PR se draft nezakládá")
    func refusesToComposeWithoutTheHead() async throws {
        let drafts = drafts()
        let store = store(drafts, detail: .failure(GitHubError.notFound("nic")))
        await store.loadDetail(for: summary())

        store.addDraftComment(at: anchor, path: "Cart.php", body: "text", for: pr)
        await settle()

        #expect(!store.canComposeDraft(for: pr))
        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    /// Prázdný komentář GitHub odmítne a s ním celé review, takže se zahazuje.
    @Test("Vyprázdnění textu komentář zahodí")
    func dropsAnEmptiedComment() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.addDraftComment(at: anchor, path: "Cart.php", body: "něco", for: pr)
        let id = try #require(store.draftComments(for: pr).first?.id)

        store.updateDraftComment(id, body: "   ", for: pr)
        await settle()

        #expect(store.draftComments(for: pr).isEmpty)
        // A s ním celý draft, protože v něm nic jiného nebylo.
        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    /// Prázdný draft se **maže** — „draft existuje“ musí znamenat „je co poslat“.
    @Test("Vyjmutí posledního komentáře smaže i soubor")
    func deletesTheFileWithTheLastComment() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.addDraftComment(at: anchor, path: "Cart.php", body: "něco", for: pr)
        await settle()
        #expect(try await drafts.load().drafts.count == 1)
        let id = try #require(store.draftComments(for: pr).first?.id)

        store.removeDraftComment(id, for: pr)
        await settle()

        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    /// Za běhu prázdný komentář uklidí bublina, když se od ní odejde. Pád aplikace nebo
    /// zabití zvenčí k té chvíli nedojde — a prázdný komentář blokuje odeslání **celého**
    /// review, takže by po restartu zůstal ležet jako nevysvětlitelný důvod, proč to nejde
    /// poslat.
    @Test("Prázdný komentář nepřežije restart")
    func prunesABlankCommentOnLoad() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.addDraftComment(at: anchor, path: "Cart.php", body: "napsané", for: pr)
        store.addDraftComment(
            at: DraftAnchor(line: 27, side: .right),
            path: "Cart.php",
            body: " \n ",
            for: pr
        )
        await settle()
        #expect(store.draftComments(for: pr).count == 2)

        let restarted = self.store(drafts)
        await restarted.loadStoredDrafts()
        await settle()

        #expect(restarted.draftComments(for: pr).map(\.body) == ["napsané"])
        // A srovná se i disk, ať se to nemusí dělat po každém startu znovu.
        let onDisk = try await drafts.load().drafts.first
        #expect(onDisk?.comments.map(\.body) == ["napsané"])
    }

    /// Draft, ve kterém nezůstane nic než prázdný komentář, se má smazat celý — „draft
    /// existuje“ musí znamenat „je co poslat“.
    @Test("Draft s jediným prázdným komentářem se po restartu smaže")
    func deletesADraftLeftWithOnlyABlankComment() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.addDraftComment(at: anchor, path: "Cart.php", body: "   ", for: pr)
        await settle()
        #expect(try await drafts.load().drafts.count == 1)

        let restarted = self.store(drafts)
        await restarted.loadStoredDrafts()
        await settle()

        #expect(!restarted.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    // MARK: - Verdikt a tělo

    /// Schválení bez prózy je plnohodnotné review, takže samotný verdikt draft zakládá.
    @Test("Samotný verdikt draft založí a přežije restart")
    func keepsAVerdictOnlyDraft() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)

        store.setDraftVerdict(.approve, for: pr)
        await settle()

        let restarted = self.store(drafts)
        await restarted.loadStoredDrafts()
        #expect(restarted.draft(for: pr)?.verdict == .approve)
    }

    /// Vybraný verdikt se musí dát vzít zpátky — jinak by šel draft zrušit jedině celý.
    @Test("Zrušení verdiktu prázdný draft smaže")
    func clearingTheVerdictDeletesAnEmptyDraft() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.setDraftVerdict(.approve, for: pr)
        await settle()

        store.setDraftVerdict(nil, for: pr)
        await settle()

        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
    }

    @Test("Zahození smaže tělo, verdikt i komentáře")
    func discardsEverything() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)
        store.setDraftBody("celkem dobré", for: pr)
        store.setDraftVerdict(.comment, for: pr)
        store.addDraftComment(at: anchor, path: "Cart.php", body: "poznámka", for: pr)
        await settle()

        store.discardDraft(for: pr)
        await settle()

        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
        // Zmáčknout dvakrát nic nerozbije.
        store.discardDraft(for: pr)
        await settle()
        #expect(!store.hasDraft(pr))
    }

    // MARK: - Převzetí nálezu

    @Test("Nález na řádku diffu se převezme jako komentář")
    func adoptsAFindingAsALineComment() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())
        let finding = makeFinding(file: "Cart.php", line: 26, summary: "ignoruje množství")

        store.adoptFinding(finding, for: pr)
        await settle()

        let comment = try #require(store.draftComments(for: pr).first)
        #expect(comment.body == "ignoruje množství")
        #expect(comment.line == 26)
        #expect(comment.side == .right)
        #expect(comment.origin == .finding(reviewer: "code-review"))
        #expect(store.isAdopted(finding, in: pr))
        // Tělo zůstane prázdné — komentář sedl k řádku.
        #expect(store.draft(for: pr)?.body.isEmpty == true)
    }

    /// Řádkový komentář mimo hunk GitHub odmítne a s ním celé review, takže nález mimo diff
    /// jde do těla jako permalink — jinak by se z odeslaného review tiše ztrácel.
    @Test("Nález mimo diff se převezme do těla jako odkaz")
    func adoptsAFindingOutsideTheDiffIntoTheBody() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())
        let finding = makeFinding(file: "Cart.php", line: 120, summary: "chybí kontrola")

        store.adoptFinding(finding, for: pr)
        await settle()

        let body = try #require(store.draft(for: pr)?.body)
        #expect(body.contains("https://github.com/cli/cli/blob/\(head)/Cart.php#L120"))
        #expect(body.contains("chybí kontrola"))
        #expect(store.draftComments(for: pr).isEmpty)
        #expect(store.isAdopted(finding, in: pr))
    }

    /// Dvě položky v těle se nesmí přepsat — druhé převzetí nesmí zahodit první.
    @Test("Druhý nález v těle první nepřepíše")
    func keepsBothBodyItems() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.adoptFinding(makeFinding(file: "Cart.php", line: 120, summary: "první"), for: pr)
        store.adoptFinding(makeFinding(file: "Cart.php", line: 130, summary: "druhý"), for: pr)
        await settle()

        let body = try #require(store.draft(for: pr)?.body)
        #expect(body.contains("první"))
        #expect(body.contains("druhý"))
        #expect(body.contains("#L120"))
        #expect(body.contains("#L130"))
    }

    // MARK: - Zastarání

    @Test("Draft proti hlavě PR zastaralý není")
    func isFreshAgainstTheHead() async throws {
        let store = await prepared(drafts())
        store.setDraftVerdict(.approve, for: pr)

        #expect(!store.isDraftStale(for: pr))
    }

    /// Nový commit draft **nemaže**, jen zablokuje odeslání a řekne to bannerem.
    @Test("Nový commit draft označí za zastaralý, ale nechá ho")
    func goesStaleOnANewCommit() async throws {
        let gateway = FakeGitHubGateway(always: .success([summary()]), detail: .success(detail()))
        let store = AppStore(gateway: gateway, time: FakeTimeSource(), drafts: drafts())
        await store.loadDetail(for: summary())
        store.setDraftBody("rozepsané", for: pr)

        gateway.detailFromNowOn = .success(detail(headSha: "cccc3333"))
        await store.loadDetail(for: summary(updatedAt: Date(timeIntervalSince1970: 200)))

        #expect(store.isDraftStale(for: pr))
        #expect(store.draft(for: pr)?.body == "rozepsané")
        #expect(store.draft(for: pr)?.headSha == head, "draft si drží commit, proti kterému se psal")
    }

    /// „Nevím“ není „zastaralé“ — banner o zablokovaném odeslání nad načítajícím se detailem
    /// by lhal.
    @Test("Bez známé hlavy se draft za zastaralý nevydává")
    func doesNotClaimStalenessWithoutTheHead() async throws {
        let drafts = drafts()
        let prepared = await prepared(drafts)
        prepared.setDraftBody("rozepsané", for: pr)
        await settle()

        let restarted = store(drafts, detail: .failure(GitHubError.notFound("nic")))
        await restarted.loadStoredDrafts()

        #expect(restarted.hasDraft(pr))
        #expect(!restarted.isDraftStale(for: pr))
        // Do rozepsaného draftu se psát dá i tak — svůj commit už zná.
        #expect(restarted.canComposeDraft(for: pr))
    }

    // MARK: - Úklid

    /// Rozdělané review je ručně psaná práce. PR, které vypadlo ze seznamu, se umí vrátit
    /// (znovuotevření), takže se draft z paměti nezahazuje.
    @Test("Draft přežije zmizení PR ze seznamu")
    func survivesThePullRequestLeavingTheList() async throws {
        let gateway = FakeGitHubGateway([.success([summary()]), .success([])], detail: .success(detail()))
        let store = AppStore(gateway: gateway, time: FakeTimeSource(), drafts: drafts())
        await store.refresh()
        await store.loadDetail(for: summary())
        store.setDraftBody("rozepsané", for: pr)
        await settle()

        await store.refresh()

        #expect(store.hasDraft(pr))
    }

    /// Uložení běží v tasku, takže se na něj musí počkat, než se sáhne na disk. Točení přes
    /// `Task.yield()` je stejná cesta jako u ostatních testů store — čekat na continuation
    /// by znamenalo, že se test při chybě zasekne místo aby spadl.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
