import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#316): vyrendruje **tab `Commity` ve všech třech podobách** a k tomu **pruh
/// záložek se sedmou záložkou přes pásmo šířek**.
///
/// Proč sonda a ne měření: „pozná se seznam od poruchy?“ a „nevypadá zalomený pruh jako rozsypaná
/// čaj?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem, je v `CommitsTabStateTests` (tři stavy),
/// `AppStoreCommitsTests` (kdy se pro ně jde) a `TabStripWidthTests` (od jaké šířky je pruh na
/// jednom řádku) — sonda je k tomu, aby se ty tři stavy daly **přečíst vedle sebe**.
///
/// **Podoby jsou čtyři, i když `CommitsTabState` má tři případy**: `list` se kreslí dvakrát, se
/// zastaralostí a bez ní, a je to zrovna ten rozdíl, který se z kódu nepozná — okrová věta nad
/// seznamem je jediné, co říká, že to pod ní je poslední známý stav, ne dnešní.
///
/// **Prázdný stav mezi nimi není schválně.** Pull request bez commitů neexistuje, takže prázdná
/// odpověď je porucha; na snímku `porucha` je vidět, že se tak i hlásí.
///
/// `NSHostingView`, ne `ImageRenderer`, ze dvou důvodů zděděných po #294: obsah `ScrollView`u se
/// offscreen nerasterizuje a `ViewThatFits` v pruhu se v `ImageRenderer`u vyhodnocuje jinak než ve
/// skutečném okně.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda tabu Commity (#316)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CommitsTabRenderProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13899)

    private enum Scenario: String, CaseIterable {
        case loading = "nenacteno"
        case list = "seznam"
        case failed = "porucha"
        case stale = "zastaraly-seznam"
        /// PR s **jedním** commitem — jeden ze tří stavů, které se podle zadání nesmí slít.
        /// Kontroluje se na něm skloňování (`1 commit`, ne `1 commitů`).
        case single = "jeden-commit"
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
    @Test("Vyrendrovat seznam v tmavém režimu")
    func rendersTheListInDarkMode() async throws {
        let (store, cache) = try await prepared(.list)
        defer { _ = cache }
        let appearance = try #require(NSAppearance(named: .darkAqua))
        let url = Self.outputDirectory.appending(path: "commity-seznam-tmavy-1400.png")

        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do { try capture(store: store, width: 1400, dark: true, to: url) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        print("SONDA \(url.path) — seznam, tmavý režim")
    }

    /// Pruh záložek sám, přes pásmo šířek — **bez odznaků i se všemi**.
    ///
    /// Změřené hranice drží `TabStripWidthTests`; tady jde o to, jak zalomený pruh **vypadá**,
    /// protože právě to je cena, kterou sedmá záložka v úzkém okně platí.
    @Test("Vyrendrovat pruh se sedmi záložkami přes pásmo šířek")
    func rendersTheStrip() throws {
        let directory = Self.outputDirectory
        // Šířky **tabu**, ne okna: 647 je nejužší povolené okno (700) bez railu, 886 je hranice
        // jednoho řádku se všemi odznaky, 1047 je výchozí okno (1100).
        for width in [647.0, 729.0, 800.0, 886.0, 947.0, 1047.0] as [CGFloat] {
            for badges in [false, true] {
                let bar = PullRequestTabBar(
                    selection: .constant(.commits),
                    badge: badges ? Self.badge(of:) : { _ in nil }
                )
                .diffCounts((additions: 248, deletions: 96))
                .frame(width: width)
                .background(Palette.surface)

                let name = "pruh7-\(Int(width))-\(badges ? "s-odznaky" : "bez-odznaku")"
                let url = directory.appending(path: "\(name).png")
                let size = try render(bar, width: width, height: 180, to: url)
                print("SONDA \(url.path) — tab \(Int(width)) b, výška pruhu \(size.height)")
            }
        }
    }

    private static func badge(of tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        case .overview: .count(4)
        case .filesChanged: .count(7)
        case .commits: .count(7)
        case .conversation: .count(2)
        case .checks: .blocking(1)
        case .findings: .blocking(3)
        case .progress: .live
        }
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
        }
        return (store, directory)
    }

    private func capture(store: AppStore, width: CGFloat, dark: Bool = false, to url: URL) throws {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil)
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
        window.orderFront(nil)
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

    /// Hlava sedí na posledním commitu, takže nese pilulku `hlava`.
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

    /// Commity ze skutečného PR (`cli/cli#13899`): sedm, z toho tři sloučení. Poslední je hlava.
    /// Jeden má `authorLogin == nil`, aby byl na snímku vidět i monogram místo obrázku.
    private static let commits: [PullRequestCommit] = [
        commit("c82266c2dcc3285033605501837434af1faeddfe",
               "Warn instead of failing when issue fields can't be set", days: -23),
        commit("8fbdb9b1a2c3d4e5f60718293a4b5c6d7e8f9012",
               "Skip issue type picker without triage access", days: -22),
        commit("745dc68b1c2d3e4f5061728394a5b6c7d8e9f012",
               "Resolve deferred issue fields before creating the issue", days: -18, login: nil,
               name: "Kumar Prateek"),
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
