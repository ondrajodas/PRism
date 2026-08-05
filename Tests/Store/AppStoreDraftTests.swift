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

    // MARK: - Rozsah řádků (#110)

    /// ⇧ klik roztáhne **naposledy přidaný** komentář, ne nový vedle něj: rozsah je oprava
    /// toho, co jsem právě napsal („ono to patří k celému bloku“).
    @Test("Šift klik roztáhne poslední komentář na rozsah")
    func extendsTheLastCommentIntoARange() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.addDraftComment(at: DraftAnchor(line: 25, side: .right), path: "Cart.php", for: pr)
        store.extendDraftComment(to: DraftAnchor(line: 27, side: .right), path: "Cart.php", for: pr)
        await settle()

        let comment = try #require(store.draftComments(for: pr).first)
        #expect(store.draftComments(for: pr).count == 1, "roztažení komentář nezdvojí")
        #expect(comment.anchor.start?.line == 25)
        #expect(comment.line == 27)
        // Identita zůstává, jinak by editor přišel o rozepsaný text a bublina by přeskočila.
        #expect(store.draftComments(for: pr).first?.id == comment.id)
    }

    @Test("Rozsah přežije restart")
    func keepsTheRangeAcrossRestart() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.addDraftComment(at: DraftAnchor(line: 25, side: .right), path: "Cart.php", body: "blok", for: pr)
        store.extendDraftComment(to: DraftAnchor(line: 27, side: .right), path: "Cart.php", for: pr)
        await settle()

        let restarted = self.store(drafts)
        await restarted.loadStoredDrafts()
        let comment = try #require(restarted.draftComments(for: pr).first)
        #expect(comment.anchor.start?.line == 25)
        #expect(comment.line == 27)
    }

    /// Kliknutí, po kterém se nestane nic, vypadá jako rozbitá aplikace — takže když není co
    /// roztahovat, vznikne obyčejný komentář.
    @Test("Šift klik bez předchozího komentáře založí obyčejný komentář")
    func fallsBackToAPlainComment() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.extendDraftComment(to: DraftAnchor(line: 26, side: .right), path: "Cart.php", for: pr)
        await settle()

        let comment = try #require(store.draftComments(for: pr).first)
        #expect(comment.anchor.start == nil)
        #expect(comment.line == 26)
    }

    /// Rozsah přes dva soubory GitHub nezná a nedal by se ani zobrazit.
    @Test("Šift klik v jiném souboru rozsah nespojí")
    func doesNotJoinTwoFiles() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.addDraftComment(at: DraftAnchor(line: 25, side: .right), path: "Cart.php", for: pr)
        store.extendDraftComment(to: DraftAnchor(line: 3, side: .right), path: "Jinde.php", for: pr)
        await settle()

        #expect(store.draftComments(for: pr).count == 2)
        #expect(store.draftComments(for: pr).allSatisfy { $0.anchor.start == nil })
    }

    /// Roztažení se dá zopakovat — druhý ⇧ klik posune konec dál, ne že by rozsah zahodil.
    @Test("Druhé roztažení posune konec rozsahu")
    func extendsTwice() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.addDraftComment(at: DraftAnchor(line: 25, side: .right), path: "Cart.php", for: pr)
        store.extendDraftComment(to: DraftAnchor(line: 26, side: .right), path: "Cart.php", for: pr)
        store.extendDraftComment(to: DraftAnchor(line: 27, side: .right), path: "Cart.php", for: pr)
        await settle()

        let comment = try #require(store.draftComments(for: pr).first)
        #expect(store.draftComments(for: pr).count == 1)
        #expect(comment.anchor.start?.line == 25)
        #expect(comment.line == 27)
    }

    // MARK: - Tažení rozsahu (#110)

    @Test("Tažení přes řádky založí komentář na rozsah")
    func dragsARange() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.dragCommentRange(
            path: "Cart.php",
            from: DraftAnchor(line: 25, side: .right),
            to: DraftAnchor(line: 27, side: .right),
            for: pr
        )
        store.finishCommentRange()
        await settle()

        let comment = try #require(store.draftComments(for: pr).first)
        #expect(comment.anchor.start?.line == 25)
        #expect(comment.line == 27)
        #expect(store.commentDrag == nil, "po dotažení se stav tažení uklidí")
    }

    /// Zvýraznění při tažení kreslí **tentýž** rozsah, který z něj vznikne — proto se skládá už
    /// během tažení a store ho drží složený.
    @Test("Rozdělané tažení je vidět jako rozsah")
    func exposesTheDraggedRange() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.dragCommentRange(
            path: "Cart.php",
            from: DraftAnchor(line: 27, side: .right),
            to: DraftAnchor(line: 25, side: .right),
            for: pr
        )

        let drag = try #require(store.commentDrag)
        // Pořadí se srovnává podle diffu, ne podle toho, kterým směrem myš táhla.
        #expect(drag.anchor.start?.line == 25)
        #expect(drag.anchor.line == 27)
        #expect(store.draftComments(for: pr).isEmpty, "komentář vzniká teprve na konci tažení")
    }

    /// Tažení, které nikam nedošlo, dá jednořádkový komentář — je to totéž co tlačítko u řádku.
    @Test("Tažení na jednom řádku dá jednořádkový komentář")
    func dragsASingleLine() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        let anchor = DraftAnchor(line: 26, side: .right)
        store.dragCommentRange(path: "Cart.php", from: anchor, to: anchor, for: pr)
        store.finishCommentRange()
        await settle()

        #expect(store.draftComments(for: pr).first?.anchor.start == nil)
    }

    /// Konec v jiném souboru rozsah nesloží, takže se **drží poslední platný** — rozsah, který
    /// při vyjetí z diffu poskočí zpátky na jeden řádek, by se nedal dotáhnout.
    @Test("Konec mimo soubor nechá poslední platný rozsah")
    func keepsTheLastValidRange() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.dragCommentRange(
            path: "Cart.php",
            from: DraftAnchor(line: 25, side: .right),
            to: DraftAnchor(line: 27, side: .right),
            for: pr
        )
        store.dragCommentRange(
            path: "Cart.php",
            from: DraftAnchor(line: 25, side: .right),
            to: DraftAnchor(line: 900, side: .right),
            for: pr
        )

        #expect(store.commentDrag?.anchor.line == 27)
    }

    /// **Nahlášené při zkoušení #110:** při jízdě přes prázdnou protistranu (vlevo nic, vpravo
    /// přidané řádky) se rozsah srazil na první řádek a po přejetí na další řádek se zase objevil.
    /// Přejetí přes místo, kde řádek není, není zrušení výběru.
    @Test("Přejetí přes prázdné místo rozsah nezruší")
    func keepsTheRangeOverAGap() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())
        let start = DraftAnchor(line: 25, side: .right)

        store.dragCommentRange(path: "Cart.php", from: start, to: DraftAnchor(line: 27, side: .right), for: pr)
        store.dragCommentRange(path: "Cart.php", from: start, to: nil, for: pr)

        #expect(store.commentDrag?.anchor.start?.line == 25)
        #expect(store.commentDrag?.anchor.line == 27, "rozsah se drží, nesrazí se na začátek")
    }

    /// Dokud rozsah žádný není, platí samotný začátek — z tažení má vzniknout aspoň jednořádkový
    /// komentář, i když se první pohyb trefí mimo řádky.
    @Test("Bez rozsahu a bez cíle platí začátek")
    func startsFromTheAnchorWithoutATarget() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.dragCommentRange(path: "Cart.php", from: DraftAnchor(line: 26, side: .right), to: nil, for: pr)

        #expect(store.commentDrag?.anchor.line == 26)
        #expect(store.commentDrag?.anchor.start == nil)
    }

    @Test("Bez načteného diffu se tažením nic nezaloží")
    func ignoresADragWithoutADiff() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)

        store.dragCommentRange(
            path: "Cart.php",
            from: DraftAnchor(line: 25, side: .right),
            to: DraftAnchor(line: 27, side: .right),
            for: pr
        )
        store.finishCommentRange()
        await settle()

        #expect(store.commentDrag == nil)
        #expect(!store.hasDraft(pr))
    }

    // MARK: - Přenesení na nový commit (#69)

    /// Diff po novém commitu: komentovaný řádek se posunul o dva dolů.
    private var shiftedDiffText: String {
        """
        diff --git a/Cart.php b/Cart.php
        --- a/Cart.php
        +++ b/Cart.php
        @@ -25,3 +25,5 @@
         kontext
        +navíc
        +
        -staré
        +nové
         další
        """
    }

    /// Komentář se zakládá **se snímkem kódu** — bez něj by revalidace nemohla říct nic než
    /// „nevím“, a to je zrovna to, kvůli čemu se snímek ukládá.
    @Test("Komentář si uloží text řádku, ke kterému se psal")
    func storesTheAnchoredText() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())

        store.addDraftComment(at: anchor, path: "Cart.php", body: "text", for: pr)
        await settle()

        #expect(store.draftComments(for: pr).first?.anchoredText == "nové")
    }

    /// Bez načteného diffu snímek nevznikne — a nesmí se z toho stát tvrzení, že kotva sedí.
    @Test("Bez diffu je snímek prázdný")
    func leavesTheSnapshotEmptyWithoutADiff() async throws {
        let drafts = drafts()
        let store = await prepared(drafts)

        store.addDraftComment(at: anchor, path: "Cart.php", body: "text", for: pr)
        await settle()

        #expect(store.draftComments(for: pr).first?.snapshot.isEmpty == true)
    }

    /// Zastaralý draft se dá přenést, jen když je proti čemu: bez diffu a bez hlavy PR by se
    /// rozhodovalo naslepo.
    @Test("Přenést se dá jen zastaralý draft, a jen s diffem")
    func offersTheTransferOnlyWhenItMakesSense() async throws {
        let drafts = drafts()
        let store = await prepared(drafts, diffs: [.success(diffText)])
        await store.loadDiff(for: summary())
        store.addDraftComment(at: anchor, path: "Cart.php", body: "text", for: pr)
        await settle()

        #expect(!store.canTransferDraft(for: pr), "draft proti aktuální hlavě zastaralý není")
    }

    /// **To hlavní z #69:** draft psaný proti starému commitu jde po revizi odeslat proti novému
    /// a kotva se přenese na řádek, kde ten kód teď je.
    @Test("Přenesení posune kotvu a odblokuje odeslání")
    func transfersTheDraftToTheNewCommit() async throws {
        let drafts = drafts()
        let store = self.store(
            drafts,
            detail: .success(detail(headSha: "bbbb2222")),
            diffs: [.success(shiftedDiffText)]
        )
        // Draft z minula: psaný proti starší hlavě, s kotvou na řádku 26 a snímkem toho řádku.
        try await drafts.save(
            ReviewDraft(
                pullRequest: pr,
                headSha: "aaaa1111",
                verdict: .comment,
                comments: [
                    ReviewDraftComment(
                        path: "Cart.php",
                        anchor: DraftAnchor(line: 26, side: .right),
                        snapshot: DraftSnapshot(anchored: "nové"),
                        body: "tady chybí kontrola",
                        origin: .own
                    ),
                ]
            )
        )
        await store.loadStoredDrafts()
        await store.loadDetail(for: summary())
        await store.loadDiff(for: summary())

        #expect(store.isDraftStale(for: pr))
        #expect(store.canTransferDraft(for: pr))
        // V novém diffu je „nové“ na řádku 28 — kotva se má posunout, ne zůstat na 26.
        let states = store.draftAnchorStates(for: pr)
        #expect(states.count == 1)
        guard case .moved(let anchor) = try #require(states.first?.state) else {
            Issue.record("čekal jsem posun, přišlo \(String(describing: states.first?.state))")
            return
        }
        #expect(anchor.line == 28)

        // Cíl přenesení je hlava PR, ne commit, proti kterému je draft psaný. Že ho okno dostane,
        // hlídají testy `ReviewSubmission` — store bez cesty ke `gh` potvrzení nesloží.
        #expect(store.head(of: pr) == "bbbb2222")

        store.transferDraft(for: pr)
        await settle()

        #expect(store.draftComments(for: pr).first?.line == 28)
        #expect(!store.isDraftStale(for: pr), "po přenesení už zastaralý není")
        // A hlavně: zastarání už není důvod, proč to nejde odeslat.
        if case .stale = store.draftSendBlock(for: pr) {
            Issue.record("po přenesení nesmí odeslání blokovat zastarání")
        }
        // A přežije to restart — přenesení je zápis na disk, ne jen do paměti.
        let restarted = self.store(drafts, detail: .success(detail(headSha: "bbbb2222")))
        await restarted.loadStoredDrafts()
        #expect(restarted.draft(for: pr)?.headSha == "bbbb2222")
        #expect(restarted.draftComments(for: pr).first?.line == 28)
    }

    /// Draft, ze kterého se všechno vyjme, se **smaže** — „draft existuje“ musí znamenat „je co
    /// poslat“. Tatáž zásada jako u prázdného komentáře.
    @Test("Přenesení, které vyjme všechno, draft smaže")
    func deletesADraftEmptiedByTheTransfer() async throws {
        let drafts = drafts()
        let store = self.store(
            drafts,
            detail: .success(detail(headSha: "bbbb2222")),
            diffs: [.success(shiftedDiffText)]
        )
        let comment = ReviewDraftComment(
            path: "Cart.php",
            anchor: DraftAnchor(line: 26, side: .right),
            snapshot: DraftSnapshot(anchored: "nové"),
            body: "tady chybí kontrola",
            origin: .own
        )
        try await drafts.save(
            ReviewDraft(pullRequest: pr, headSha: "aaaa1111", comments: [comment])
        )
        await store.loadStoredDrafts()
        await store.loadDetail(for: summary())
        await store.loadDiff(for: summary())

        store.transferDraft(for: pr, choices: [comment.id: .delete])
        await settle()

        #expect(!store.hasDraft(pr))
        #expect(try await drafts.load().drafts.isEmpty)
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
