import Foundation
import Testing

@testable import PRism

/// Rozkliknutý commit ve store (#317) — co se dá pokazit mezi kliknutím a diffem na obrazovce.
///
/// Rozhodování o tom, **co je vidět**, je vyčerpané v `CommitDiffTabStateTests`. Tady se hlídá:
///
/// - **stáhnout diff podruhé** při každém návratu do commitu, tedy z jednoho kliknutí udělat
///   polling;
/// - **nechat chybu bez cesty ven** — `Zkusit znovu` musí doopravdy znovu stáhnout;
/// - **nechat doběhlé volání přepsat cizí commit**, tedy diff, který k hlavičce nad ním nepatří;
/// - **zapomenout, kde v seznamu člověk byl** — návrat se bez toho pozná až tehdy, když se
///   scrolluje odznova;
/// - **brát rozbalený kontext z hlavy PR**, ne z toho commitu: řádky by seděly na jiná čísla
///   a nikdo by to nepoznal;
/// - **sdílet sbalení souborů se `Změněnými soubory`**, takže by se v review schoval soubor,
///   který si někdo sbalil při čtení commitu.
@Suite("AppStore — diff commitu")
@MainActor
struct AppStoreCommitDiffTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private static let diffText = """
        diff --git a/Cart.php b/Cart.php
        --- a/Cart.php
        +++ b/Cart.php
        @@ -10,3 +10,4 @@
         <?php
        -$a = 1;
        +$a = 2;
        +$b = 3;
        """

    private func gateway(diff: String = diffText, failure: (any Error)? = nil) -> FakeGitHubGateway {
        let gateway = FakeGitHubGateway(always: .success([summary]))
        gateway.commitDiff = diff
        gateway.commitDiffFailure = failure
        return gateway
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, time: FakeTimeSource())
    }

    /// Je diff commitu stažený? **Vlastní pomůcka testu, ne getter na modelu** — v aplikaci se
    /// stav čte jedině přes `Policy.commitDiffTab`, takže `loaded` na `CommitDiff` by byla druhá
    /// cesta k témuž, kterou by nikdo mimo testy nepoužil.
    private func isLoaded(_ store: AppStore) -> Bool {
        if case .loaded = store.commitDiffs[pr]?.content { true } else { false }
    }

    private func commit(_ sha: String, merge: Bool = false) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: "feat: \(sha)",
            authorName: "Odin Uv",
            authorLogin: "odinuv",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 90),
            isMerge: merge
        )
    }

    // MARK: - Otevření a návrat

    @Test("Rozkliknutí stáhne diff toho commitu")
    func fetchesTheDiffOfTheClickedCommit() async {
        let gateway = gateway()
        let store = store(gateway)

        store.openCommit("aaa", in: pr)
        await waitUntil("diff dorazí") { self.isLoaded(store) }

        #expect(gateway.commitDiffRequests == ["aaa"])
        #expect(store.openedCommit(in: pr) == "aaa")
        #expect(store.commitDiffState(of: commit("aaa"), in: pr) == .diff(DiffParser.parse(Self.diffText)))
    }

    /// Commit je neměnný, takže druhé otevření téhož se **neptá znovu** — a zpátky do něj je
    /// proto zadarmo.
    @Test("Druhé otevření téhož commitu se neptá znovu")
    func doesNotFetchTheSameCommitTwice() async {
        let gateway = gateway()
        let store = store(gateway)

        store.openCommit("aaa", in: pr)
        await waitUntil("diff dorazí") { self.isLoaded(store) }
        store.closeCommit(in: pr)
        store.openCommit("aaa", in: pr)

        #expect(gateway.commitDiffRequests == ["aaa"], "z jednoho kliknutí se stal polling")
    }

    /// **Návrat nesmí zapomenout, kde v seznamu člověk byl.** Paměť je sha posledního otevřeného
    /// commitu — a bere se z téhož místa, ze kterého se diff kreslí, takže se to nemá s čím rozejít.
    @Test("Návrat do seznamu si pamatuje, který řádek byl otevřený")
    func remembersTheOpenedRowAfterGoingBack() async {
        let store = store(gateway())

        store.openCommit("aaa", in: pr)
        await waitUntil("diff dorazí") { self.isLoaded(store) }
        store.closeCommit(in: pr)

        #expect(store.openedCommit(in: pr) == nil, "po návratu má být vidět seznam")
        #expect(store.lastOpenedCommit(in: pr) == "aaa")
    }

    /// **Selhání se ptá znovu**, jinak by tlačítko `Zkusit znovu` nic neudělalo.
    @Test("Po selhání se dá stáhnout znovu")
    func retriesAfterAFailure() async {
        let gateway = gateway(failure: GitHubError.toolUnavailable("gh není po ruce"))
        let store = store(gateway)

        store.openCommit("aaa", in: pr)
        await waitUntil("chyba dorazí") { store.commitDiffs[self.pr]?.content != .loading }
        #expect(store.commitDiffState(of: commit("aaa"), in: pr)
            == .failed(GitHubError.toolUnavailable("gh není po ruce").userDescription))

        gateway.commitDiffFailure = nil
        store.openCommit("aaa", in: pr)
        await waitUntil("diff dorazí") { self.isLoaded(store) }

        #expect(gateway.commitDiffRequests == ["aaa", "aaa"])
    }

    /// **Žádná cesta nesmí skončit věčným spinnerem.** `Načítám diff commitu…` se sám nevrátí
    /// a tlačítko u něj není, takže stav, ve kterém by zůstal, je slepá ulička — a `CancellationError`
    /// je zrovna ta chyba, kterou jinde ve store „není porucha“ (tam ji ale posílá odchod
    /// z obrazovky, kdežto tuhle úlohu nikdo neruší).
    @Test("Ani zrušení nenechá v tabu věčný spinner")
    func neverLeavesTheSpinnerHanging() async {
        let store = store(gateway(failure: CancellationError()))

        store.openCommit("aaa", in: pr)
        await waitUntil("stav se usadí") { store.commitDiffs[self.pr]?.content != .loading }

        guard case .failed = store.commitDiffState(of: commit("aaa"), in: pr) else {
            Issue.record("Zrušené stažení nechalo tab v načítání, ze kterého nevede cesta ven")
            return
        }
    }

    /// Doběhlé volání nesmí přepsat commit, o který si mezitím řeklo druhé kliknutí — v okně by
    /// pak ležel diff, který k hlavičce nad ním nepatří.
    @Test("Doběhlé volání nepřepíše mezitím otevřený commit")
    func doesNotOverwriteAnotherCommit() async {
        let gateway = gateway()
        let gate = AsyncGate()
        gateway.commitDiffGate = gate
        let store = store(gateway)

        store.openCommit("aaa", in: pr)
        await gate.waitUntilReached()
        // Druhé kliknutí, ještě než první doběhne. Závora se pak pustí a **obě** volání dopadnou.
        gateway.commitDiffGate = nil
        store.openCommit("bbb", in: pr)
        await waitUntil("druhý diff dorazí") { self.isLoaded(store) }
        await gate.release()

        #expect(store.commitDiffs[pr]?.sha == "bbb")
        #expect(store.commitDiffState(of: commit("aaa"), in: pr) == .loading,
                "diff prvního commitu se kreslí pod hlavičkou druhého")
    }

    // MARK: - Úklid

    /// Diff commitu jsou megabajty, takže se drží jen pro to, co je v seznamu — a otevřený commit
    /// se uklízí **spolu s ním**, jinak by se PR po návratu do seznamu otevřelo rovnou v commitu.
    @Test("PR mimo seznam si diff commitu nenechá")
    func forgetsTheCommitDiffOfAVanishedPullRequest() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.commitDiff = Self.diffText
        let store = AppStore(gateway: gateway, time: FakeTimeSource(stopAfter: 1))
        store.openCommit("aaa", in: pr)
        await waitUntil("diff dorazí") { self.isLoaded(store) }

        await store.keepFresh()   // tik, ve kterém to PR není

        #expect(store.commitDiffs[pr] == nil)
        #expect(store.openedCommit(in: pr) == nil)
    }

    // MARK: - Rozbalování kontextu

    /// **Kontext se bere z toho commitu, ne z hlavy PR.** Na hlavě jsou po pár commitech jiná
    /// čísla řádků, takže by se odkryl kód, který kolem hunku nikdy nestál — a vypadal by úplně
    /// věrohodně.
    @Test("Rozbalení kontextu v commitu čte soubor v tom commitu")
    func revealsTheFileAtTheCommit() async {
        let gateway = gateway()
        gateway.commitFiles = [.success("a\nb\nc\nd\ne\n")]
        gateway.commitsFailure = nil
        let store = store(gateway)

        store.reveal(1...3, of: "Cart.php", in: pr, commit: "aaa")
        await waitUntil("obsah dorazí") {
            !store.expansion(of: "Cart.php", in: self.pr, commit: "aaa").content.isEmpty
        }

        #expect(gateway.commitFileRequests.map(\.commit) == ["aaa"])
        #expect(gateway.commitFileRequests.map(\.path) == ["Cart.php"])
        #expect(gateway.fileRequests.isEmpty, "sáhlo se na hlavu PR místo na commit")
    }

    /// Týž soubor, dva diffy — a **dva různé záznamy**. Sdílený by znamenal obsah z hlavy PR
    /// v diffu commitu, nebo naopak.
    @Test("Rozbalení v commitu a v diffu PR se nesdílí")
    func keepsTheTwoExpansionsApart() {
        let store = store(gateway())

        store.expansions[FileExpansionKey(pullRequest: pr, path: "Cart.php", commit: "aaa")] =
            FileExpansion(revealed: RevealedLines(), content: ["z commitu"])

        #expect(store.expansion(of: "Cart.php", in: pr).content.isEmpty)
        #expect(store.expansion(of: "Cart.php", in: pr, commit: "aaa").content == ["z commitu"])
    }

    /// A totéž pro `Zobrazit jen diff`: rozbalený kontext v commitu nesmí rozsvítit tlačítko nad
    /// diffem PR, kde by nebylo co sbalit.
    @Test("Rozbalený kontext v commitu nerozsvítí sbalení v diffu PR")
    func doesNotOfferCollapsingInTheOtherDiff() {
        let store = store(gateway())
        var expansion = FileExpansion()
        expansion.revealed.reveal(1...3)
        store.expansions[FileExpansionKey(pullRequest: pr, path: "Cart.php", commit: "aaa")] = expansion

        #expect(store.hasRevealedLines(in: pr) == false)
        #expect(store.hasRevealedLines(in: pr, commit: "aaa"))

        store.collapseRevealedLines(in: pr)
        #expect(store.hasRevealedLines(in: pr, commit: "aaa"), "sbalení v jednom diffu sáhlo do druhého")

        store.collapseRevealedLines(in: pr, commit: "aaa")
        #expect(store.hasRevealedLines(in: pr, commit: "aaa") == false)
    }

    // MARK: - Sbalování souborů

    @Test("Sbalení souboru v commitu se nepropíše do Změněných souborů")
    func keepsFoldingApart() {
        let store = store(gateway())

        store.toggleFolded("Cart.php", in: pr, commit: "aaa")

        #expect(store.isFolded("Cart.php", in: pr, commit: "aaa"))
        #expect(store.isFolded("Cart.php", in: pr) == false)

        store.unfoldAll(in: pr)
        #expect(store.isFolded("Cart.php", in: pr, commit: "aaa"), "rozbalit vše sáhlo do cizího diffu")
    }
}
