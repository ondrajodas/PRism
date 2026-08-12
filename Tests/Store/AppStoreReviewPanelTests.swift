import Foundation
import Testing

@testable import PRism

/// Panel vpravo: co ho rozloží a co ne (#242).
///
/// **Tohle je ta věc, která se rozbije potichu.** Poznámka do těla review přidaná z diffu spadne
/// do panelu — a od #242 se panel dá složit, takže by text zmizel za proužek na hraně okna, tedy
/// tam, kde ho nikdo nehledá. Do #242 to řešilo přepnutí tabu uvnitř `@State` detailu PR a nešlo
/// to otestovat vůbec.
@Suite("AppStore — panel s mým review")
@MainActor
struct AppStoreReviewPanelTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Diff s hunkem na nových řádcích 25–27, aby se poznal řádek, který komentář unese, od toho,
    /// který ne.
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

    /// Store s načteným detailem (odtud je `headSha`) a diffem.
    private func prepared(withDiff: Bool = true) async -> AppStore {
        let store = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary()]),
                detail: .success(detail()),
                diffs: withDiff ? [.success(diffText)] : []
            ),
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: layout)
        )
        await store.loadDetail(for: summary())
        if withDiff { await store.loadDiff(for: summary()) }
        return store
    }

    /// Panel složený a přepnutý na nálezy — tedy stav, ve kterém by rozepsaná věta zmizela.
    private func collapsed(_ store: AppStore) {
        store.isReviewPanelExpanded = false
        store.reviewPanelTab = .findings
    }

    @Test("Poznámka do těla review složený panel rozloží a přepne na rozdělané review")
    func noteRevealsThePanel() async throws {
        let store = await prepared()
        collapsed(store)

        store.appendDraftNote(text: "tady chybí kontrola", path: "Cart.php", line: 40, for: pr)
        await settle()

        #expect(store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .draft)
        #expect(store.draft(for: pr)?.body.contains("tady chybí kontrola") == true)
    }

    @Test("Převzetí nálezu bez místa v kódu panel rozloží taky — jde do těla review")
    func adoptingWithoutPlaceRevealsThePanel() async throws {
        let store = await prepared()
        collapsed(store)

        store.adoptFinding(makeFinding(file: nil, line: nil, summary: "chybí test"), for: pr)
        await settle()

        #expect(store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .draft)
    }

    /// A tady to, co se stát **nesmí**: řádkový komentář je vidět hned pod řádkem v diffu, takže
    /// rozložení panelu by uživateli přestavělo okno bez důvodu.
    @Test("Převzetí nálezu na řádku v diffu panel nerozloží")
    func adoptingOnALineKeepsThePanelCollapsed() async throws {
        let store = await prepared()
        collapsed(store)

        store.adoptFinding(makeFinding(file: "Cart.php", line: 26, summary: "tady"), for: pr)
        await settle()

        #expect(!store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .findings)
        #expect(store.draftComments(for: pr).count == 1)
    }

    @Test("Chip rozdělaného review v hlavičce panel rozloží")
    func chipRevealsThePanel() async throws {
        let store = await prepared()
        collapsed(store)

        store.revealDraft(in: pr)

        #expect(store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .draft)
    }

    // MARK: - Taby, ve kterých panel není (#294)

    /// **Skrytí je věc pohledu, ne uložený stav.** Kdo má panel rozbalený, přepne na `Nálezy`
    /// a zpět, musí ho najít rozbalený — jinak by se přepnutím tabu tiše zahodilo nastavení, které
    /// si člověk vytáhl.
    @Test("Rozbalený panel přežije průchod tabem, ve kterém není")
    func expansionSurvivesAHidingTab() async throws {
        let store = await prepared()
        store.isReviewPanelExpanded = true
        store.reviewPanelTab = .draft

        store.setDetailTab(.findings, for: pr)
        store.setDetailTab(.progress, for: pr)
        store.setDetailTab(.overview, for: pr)

        #expect(store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .draft)
    }

    /// A totéž složeným: přepnutí tabu ho **nesmí** rozložit. Kdyby to dělalo, „složeno“ by
    /// znamenalo „dokud nepřepneš tab“.
    @Test("Složený panel přepnutím tabu nezmizí ani se nerozloží")
    func collapseSurvivesAHidingTab() async throws {
        let store = await prepared()
        collapsed(store)

        store.setDetailTab(.checks, for: pr)
        store.setDetailTab(.filesChanged, for: pr)

        #expect(!store.isReviewPanelExpanded)
    }

    /// V tabu bez panelu by rozložení nebylo vidět, takže se k němu **přepne tab**. Bez toho by
    /// `Převzít` v tabu `Nálezy` neudělalo nic viditelného — a tichá ztráta rozepsané věty je to
    /// nejdražší, co tady umí zmizet (#242).
    @Test("Poznámka z tabu bez panelu přepne do tabu, ve kterém panel je")
    func noteLeavesAHidingTab() async throws {
        let store = await prepared()
        collapsed(store)
        store.setDetailTab(.findings, for: pr)

        store.appendDraftNote(text: "chybí test", path: nil, line: nil, for: pr)
        await settle()

        #expect(store.detailTab(for: pr).showsReviewPanel)
        #expect(store.detailTab(for: pr) == .overview)
        #expect(store.isReviewPanelExpanded)
        #expect(store.reviewPanelTab == .draft)
        #expect(store.draft(for: pr)?.body.contains("chybí test") == true)
    }

    /// A **z tabu, kde panel je, se nepřepíná nikam**: převzetí nálezu v diffu nesmí člověka
    /// vyhodit z kódu, který zrovna čte.
    @Test("Poznámka z tabu s panelem tab nemění")
    func noteKeepsATabThatHasThePanel() async throws {
        let store = await prepared()
        store.setDetailTab(.filesChanged, for: pr)

        store.appendDraftNote(text: "poznámka", path: nil, line: nil, for: pr)
        await settle()

        #expect(store.detailTab(for: pr) == .filesChanged)
    }

    /// Paleta ⌘K nabízí přepnutí panelu **jen tam, kde panel je**: z klávesnice by se jinak
    /// přestavěl tab, do kterého se člověk vrátí, a v okně by po tom nezůstala žádná stopa.
    @Test("Paleta nenabízí přepnutí panelu v tabu, kde panel není")
    func paletteOmitsThePanelActionInAHidingTab() async throws {
        let store = await prepared()
        store.openTab(pr)
        store.setDetailTab(.overview, for: pr)
        #expect(store.paletteItems.contains { $0.target == .action(.setReviewPanel(expanded: false)) })

        store.setDetailTab(.findings, for: pr)

        #expect(!store.paletteItems.contains { $0.target == .action(.setReviewPanel(expanded: false)) })
        #expect(!store.paletteItems.contains { $0.target == .action(.setReviewPanel(expanded: true)) })
        // Pohled na diff se nabízí dál — je to nastavení diffu, ne věc na téhle obrazovce.
        #expect(store.paletteItems.contains { $0.target == .action(.setDiffLayout(.split)) })
    }

    /// Rozložený panel se doručením poznámky nesmí složit — je to `reveal`, ne přepínač.
    @Test("Rozložený panel zůstane rozložený")
    func keepsAnExpandedPanel() async throws {
        let store = await prepared()
        store.isReviewPanelExpanded = true

        store.appendDraftNote(text: "poznámka", path: nil, line: nil, for: pr)
        await settle()

        #expect(store.isReviewPanelExpanded)
    }

    /// Uložení běží v tasku, takže se na něj musí počkat, než se sáhne na draft. Točení přes
    /// `Task.yield()` je stejná cesta jako u ostatních testů store — čekat na continuation by
    /// znamenalo, že se test při chybě zasekne místo aby spadl.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
