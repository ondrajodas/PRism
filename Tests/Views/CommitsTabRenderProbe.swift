import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#316): vyrendruje **tab `Commity` ve všech třech podobách**.
///
/// Proč sonda a ne měření: „pozná se seznam od poruchy?“ je otázka na obrázek. Co se **dá** tvrdit
/// číslem, je v `CommitsTabStateTests` (tři stavy) a `AppStoreCommitsTests` (kdy se pro ně jde) —
/// sonda je k tomu, aby se ty tři stavy daly **přečíst vedle sebe**. Pruh záložek se od #318
/// rendruje jinde, v `TabStripRenderProbe`: stojí nad všemi sedmi taby, takže dvě sondy s ním
/// znamenaly dvě pásma šířek, která se nedají porovnat.
///
/// **Podoby jsou čtyři, i když `CommitsTabState` má tři případy**: `list` se kreslí dvakrát, se
/// zastaralostí a bez ní, a je to zrovna ten rozdíl, který se z kódu nepozná — okrová věta nad
/// seznamem je jediné, co říká, že to pod ní je poslední známý stav, ne dnešní.
///
/// **Prázdný stav mezi nimi není schválně.** Pull request bez commitů neexistuje, takže prázdná
/// odpověď je porucha; na snímku `porucha` je vidět, že se tak i hlásí.
///
/// `NSHostingView`, ne `ImageRenderer`, ze dvou důvodů zděděných po #294: obsah `ScrollView`u se
/// offscreen nerasterizuje a `ViewThatFits` v pruhu nad tabem se v `ImageRenderer`u vyhodnocuje
/// jinak než ve skutečném okně.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda tabu Commity (#316)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CommitsTabRenderProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13899)

    enum Scenario: String, CaseIterable {
        case loading = "nenacteno"
        case list = "seznam"
        case failed = "porucha"
        case stale = "zastaraly-seznam"
        /// PR s **jedním** commitem — jeden ze tří stavů, které se podle zadání nesmí slít.
        /// Kontroluje se na něm skloňování (`1 commit`, ne `1 commitů`).
        case single = "jeden-commit"
        /// Rozkliknutý commit (#317): hlavička s cestou zpět a pod ní diff přes celou plochu.
        case commitDiff = "diff-commitu"
        /// Tentýž commit se **sbaleným tělem zprávy** (#317). Na snímku se posuzuje to jediné, co
        /// se o sbalování nedá tvrdit číslem: že sbalená hlavička pořád odpovídá na „na co se to
        /// koukám“ — cesta zpět, titulek, sha, autor, čas i počty v ní zůstávají a zmizí jen
        /// odstavce pod titulkem. Kolik místa se tím získá, je vidět vedle snímku `diff-commitu`.
        case commitDiffCollapsed = "diff-commitu-sbalena-hlavicka"
        /// Sbalená hlavička nad commitem, jehož zpráva má **`CRLF`** (#339). Je to jediný způsob, jak
        /// si tenhle stav prohlédnout: normálním používáním by k němu musel v tabu `Commity` ležet PR
        /// s `CRLF` ve zprávě commitu. Na snímku se posuzuje jediná věc — že v popisku přepínače stojí
        /// skutečný počet řádků (`3 řádky`), ne `1 řádek`, který tam byl do #339.
        case commitDiffCRLF = "diff-commitu-sbalena-hlavicka-crlf"
        /// **Prázdný diff** — ten stav, který se z prázdné plochy nedá odlišit od poruchy, takže
        /// je na snímku vidět věta místo diffu. Sloučení, protože má vlastní znění.
        case emptyMerge = "diff-commitu-prazdne-slouceni"
        /// Stahuje se. Na snímku se posuzuje, že hlavička už stojí (sha, zpráva, cesta zpět)
        /// a čeká se jen na kód pod ní.
        case commitLoading = "diff-commitu-nenacteno"
        case commitFailed = "diff-commitu-porucha"
    }

    @Test("Vyrendrovat tab Commity ve všech stavech")
    func rendersEveryState() async throws {
        let directory = Self.outputDirectory
        for scenario in Scenario.allCases {
            let (store, cache) = try await prepared(scenario)
            defer { _ = cache }
            for width in [1400.0, 760.0] as [CGFloat] {
                let url = directory.appending(path: "commity-\(scenario.rawValue)-\(Int(width)).png")
                try capture(store: store, width: width, to: url)
                print("SONDA \(url.path) — \(scenario.rawValue), \(Int(width)) b")
            }
        }
    }

    /// Seznam **v tmavém režimu**. Vlastní test, ne šestý scénář: barvy se nekontrolují u každého
    /// stavu, ale u toho jednoho, ve kterém jsou všechny — mátová pilulka `hlava`, tichá `sloučení`,
    /// kapsle se sha na `raised` a pruh `chrome` nad seznamem.
    ///
    /// **Režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`) a
    /// `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém —
    /// poučení z `AppearanceRenderProbe` (#278).
    @Test(
        "Vyrendrovat seznam a diff commitu v tmavém režimu",
        arguments: [Scenario.list, .commitDiff, .commitDiffCollapsed, .emptyMerge]
    )
    func rendersInDarkMode(scenario: Scenario) async throws {
        let (store, cache) = try await prepared(scenario)
        defer { _ = cache }
        let appearance = try #require(NSAppearance(named: .darkAqua))
        let url = Self.outputDirectory.appending(path: "commity-\(scenario.rawValue)-tmavy-1400.png")

        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do { try capture(store: store, width: 1400, dark: true, to: url) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        print("SONDA \(url.path) — \(scenario.rawValue), tmavý režim")
    }

    // MARK: - Scéna

    /// Store s načteným detailem a commity nastavenými **až po** `loadDetail`.
    ///
    /// Pořadí je podmínka, ne detail: `loadDetail` si commity dotahuje sám, takže nastavené předem
    /// by je přepsal — a `.task` v detailu ho během renderu už nespustí, protože má cache podle
    /// `updatedAt`. Právě proto se tudy dá vyrobit i stav „nenačteno“, ke kterému se v aplikaci
    /// normálním používáním nedá vrátit.
    private func prepared(_ scenario: Scenario) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(Self.diffText)]
        )
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        store.openTab(pr)
        store.setDetailTab(.commits, for: pr)

        switch scenario {
        case .loading:
            store.commits[pr] = nil
            store.commitFailures[pr] = nil
            // Aby stav `nenačteno` **vydržel celý render**: `.task` v detailu volá `loadDetail`,
            // a ten si v cache větvi commity dotáhne, když o nich neví nic.
            gateway.commitsFailure = CancellationError()
        case .list:
            store.commits[pr] = Self.commits
            store.commitFailures[pr] = nil
        case .failed:
            store.commits[pr] = nil
            store.commitFailures[pr] = Self.failure
        case .stale:
            store.commits[pr] = Self.commits
            store.commitFailures[pr] = Self.failure
        case .single:
            store.commits[pr] = [Self.commits[0]]
            store.commitFailures[pr] = nil
        case .commitDiff, .commitDiffCollapsed, .commitDiffCRLF, .emptyMerge, .commitLoading, .commitFailed:
            store.commits[pr] = scenario == .commitDiffCRLF ? try Self.crlfCommits() : Self.commits
            store.commitFailures[pr] = nil
            // Stav diffu se **staví přímo**, ne přes `openCommit`: ten spouští `Task`, na který by
            // render čekal, a rozdělaný stav (`nenacteno`) by se tudy nedal vyrobit vůbec.
            let sha = Self.openSha(for: scenario)
            store.openCommits[pr] = sha
            store.commitDiffs[pr] = CommitDiff(sha: sha, content: content(for: scenario))
            store.isCommitMessageExpanded = ![.commitDiffCollapsed, .commitDiffCRLF].contains(scenario)
        }
        return (store, directory)
    }

    /// Obsah diffu commitu pro scénář. Sloučení dostane **prázdný** diff, protože právě u něj má
    /// věta jiné znění než u obyčejného commitu.
    private func content(for scenario: Scenario) -> CommitDiff.Content {
        switch scenario {
        case .emptyMerge: .loaded(DiffParser.parse(""))
        case .commitLoading: .loading
        case .commitFailed: .failed(Self.failure)
        default: .loaded(DiffParser.parse(Self.commitDiffText))
        }
    }

    private func capture(store: AppStore, width: CGFloat, dark: Bool = false, to url: URL) throws {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil),
            merge: .constant(nil),
            branchPush: .constant(nil)
        )
        .frame(width: width, height: Self.height)
        .background(Palette.background)
        .environment(\.colorScheme, dark ? .dark : .light)

        _ = try render(scene, width: width, height: Self.height, to: url)
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u `Kontrol`
    /// (#306), tabů (#294) a `Přehledu` (#291), viz `docs/testovani.md`.
    private func render(_ scene: some View, width: CGFloat, height: CGFloat, to url: URL) throws -> CGSize {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe víc
        // instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
        return hosting.bounds.size
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    private static let height: CGFloat = 700

    private static let failure = GitHubError
        .network("dial tcp: lookup api.github.com: no such host")
        .userDescription

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13899),
        title: "Warn instead of failing when issue fields can't be set",
        author: "imkp1",
        url: URL(string: "https://github.com/cli/cli/pull/13899")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    /// Hlava sedí na **posledním commitu z API**, tedy na tom, který tab kreslí nahoře (#316) —
    /// nese pilulku `hlava`. Že „nahoře“ a „hlava“ nejsou totéž, tvrdí `CommitsTabStateTests`;
    /// sonda je od toho, aby se ta mátová pilulka dala v seznamu **najít okem**.
    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "1c67e36ab1c2d3e4f5061728394051627384950a",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Popis PR."
    )

    /// Který commit je na snímku rozkliknutý (#317).
    ///
    /// Běžně ten **s tělem zprávy**, protože na jeho hlavičce je co posuzovat; u prázdného diffu
    /// **sloučení**, protože právě u něj má věta jiné znění — a snímek má ukázat to znění, které
    /// k tomu commitu patří.
    /// Sbalená hlavička dostane **týž commit s tělem** jako `diff-commitu`, jinak by se snímky
    /// nedaly položit vedle sebe a nebylo by vidět, kolik místa se sbalením získá.
    private static func openSha(for scenario: Scenario) -> String {
        scenario == .emptyMerge
            ? "96a469b6bd159d4cff137d5eab4d13ceee4c9807"
            : "745dc68b1c2d3e4f5061728394a5b6c7d8e9f012"
    }

    /// Diff rozkliknutého commitu: **dva soubory**, aby byl vidět strom vlevo i druhá hlavička,
    /// a jeden řádek přepsaný, aby bylo na čem posoudit word-level zvýraznění.
    private static let commitDiffText = """
        diff --git a/pkg/cmd/issue/create/create.go b/pkg/cmd/issue/create/create.go
        --- a/pkg/cmd/issue/create/create.go
        +++ b/pkg/cmd/issue/create/create.go
        @@ -128,7 +128,11 @@ func createRun(opts *CreateOptions) error {
         	if err != nil {
         		return err
         	}
        -	issue, err := api.IssueCreate(apiClient, repo, params)
        +	issue, err := api.IssueCreate(apiClient, repo, resolved)
        +	if err != nil {
        +		return fmt.Errorf("could not create issue: %w", err)
        +	}
         	fmt.Fprintln(opts.IO.Out, issue.URL)
         	return nil
         }
        diff --git a/pkg/cmd/issue/create/fields.go b/pkg/cmd/issue/create/fields.go
        new file mode 100644
        --- /dev/null
        +++ b/pkg/cmd/issue/create/fields.go
        @@ -0,0 +1,5 @@
        +package create
        +
        +func resolveFields(params map[string]interface{}) (map[string]interface{}, error) {
        +	return params, nil
        +}
        """

    private static let diffText = """
        diff --git a/pkg/cmd/issue/create/create.go b/pkg/cmd/issue/create/create.go
        --- a/pkg/cmd/issue/create/create.go
        +++ b/pkg/cmd/issue/create/create.go
        @@ -25,3 +25,3 @@
         	if err != nil {
        -		return err
        +		fmt.Fprintf(opts.IO.ErrOut, "warning: %v\\n", err)
         	}
        """

    /// Commity ze skutečného PR (`cli/cli#13899`): sedm, z toho tři sloučení. **V pořadí z API**,
    /// tedy od nejstaršího — store drží, co přišlo, a tab to otočí sám (`Policy.commitsNewestFirst`),
    /// takže na snímku je poslední z nich nahoře. Poslední je zároveň hlava. Jeden má
    /// `authorLogin == nil`, aby byl na snímku vidět i monogram místo obrázku.
    private static let commits: [PullRequestCommit] = [
        commit("c82266c2dcc3285033605501837434af1faeddfe",
               "Warn instead of failing when issue fields can't be set", days: -23),
        commit("8fbdb9b1a2c3d4e5f60718293a4b5c6d7e8f9012",
               "Skip issue type picker without triage access", days: -22),
        // **Jediný s tělem zprávy** — kvůli #317: v seznamu se tělo nekreslí, v hlavičce
        // rozkliknutého commitu ano, a je to ten blok, který se nejsnáz nasází špatně.
        commit("745dc68b1c2d3e4f5061728394a5b6c7d8e9f012",
               """
               Resolve deferred issue fields before creating the issue

               Fields that need triage access were resolved after the issue was
               created, so a failure left an issue with half the fields set.
               """,
               days: -18, login: nil, name: "Kumar Prateek"),
        commit("96a469b6bd159d4cff137d5eab4d13ceee4c9807",
               "Merge branch 'trunk' into fix/13804-gh-issue-create-errors-after-successful",
               days: -18, merge: true, name: "Kumar Prateek"),
        commit("0834fedb0a1c2d3e4f50617283940516273849a0",
               "Test unresolvable ref later in the blocked-by loop", days: -18),
        commit("05428031a2b3c4d5e6f70819203a4b5c6d7e8f90",
               "Merge branch 'trunk' into fix/13804-gh-issue-create-errors-after-successful",
               days: -17, merge: true, name: "Kumar Prateek"),
        commit("1c67e36ab1c2d3e4f5061728394051627384950a",
               "Merge branch 'trunk' into fix/13804-gh-issue-create-errors-after-successful",
               days: -8, merge: true, name: "Kumar Prateek"),
    ]

    /// Tentýž seznam, ale rozkliknutý commit má zprávu s **míchanými zakončeními** (#339).
    ///
    /// Zpráva se bere **ze skutečné odpovědi** `gh/pr-commits-crlf.json` (`git-for-windows/git`,
    /// commit `415ab35` — titulek `LF`, tělo `CRLF`), ne z literálu v tomhle souboru: ručně napsaná
    /// zpráva by nesla `LF` toho, kdo ji napsal, a sonda by kreslila stav, který `gh` nevrací.
    /// Ostatní commity zůstávají, aby se snímek dal položit vedle `diff-commitu-sbalena-hlavicka`.
    private static func crlfCommits() throws -> [PullRequestCommit] {
        let message = try CommitFixture.crlfCommit().message
        let openSha = openSha(for: .commitDiffCRLF)
        return commits.map { original in
            guard original.sha == openSha else { return original }
            return PullRequestCommit(
                sha: original.sha,
                message: message,
                authorName: original.authorName,
                authorLogin: original.authorLogin,
                avatarURL: nil,
                committedAt: original.committedAt,
                isMerge: original.isMerge
            )
        }
    }

    private static func commit(
        _ sha: String,
        _ message: String,
        days: Int,
        merge: Bool = false,
        login: String? = "imkp1",
        name: String = "imkp1"
    ) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: message,
            authorName: name,
            authorLogin: login,
            // Bez sítě se obrázek stejně nenačte, takže je všude monogram — a právě ten se má na
            // snímku posoudit.
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_754_000_000 + Double(days) * 86_400),
            isMerge: merge
        )
    }
}
