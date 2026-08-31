import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#306): vyrendruje **tab `Kontroly` v každé podobě, jakou umí**.
///
/// Podob je **pět, i když `ChecksTabState` má čtyři případy**: `list` se kreslí dvakrát, se
/// zastaralostí a bez ní, a je to zrovna ten rozdíl, který se z kódu nepozná — okrová věta nad
/// `ScrollView`em je jediné, co říká, že seznam pod ní je poslední známý, ne dnešní.
///
/// Proč sonda a ne měření: „netvrdí prázdný tab, že se něco nepovedlo?“ je otázka na obrázek. Co se
/// **dá** tvrdit číslem, je v `ChecksTabStateTests` (čtyři stavy) a v `AppStoreTabTests` (volba tabu
/// přežije každý stav) — sonda je k tomu, aby se prázdný a nenačtený stav daly **přečíst** vedle
/// sebe. Pruh záložek se od #318 rendruje jinde, v `TabStripRenderProbe`: stojí nad všemi sedmi
/// taby, takže dvě sondy s ním znamenaly dvě pásma šířek, která se nedají porovnat.
///
/// `NSHostingView`, ne `ImageRenderer`, ze dvou důvodů zděděných po #294: obsah `ScrollView`u se
/// offscreen nerasterizuje a `Link` v `ImageRenderer`u vyjde jako žlutý placeholder — obojí je
/// v `Kontrolách`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda tabu Kontroly (#306)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ChecksTabRenderProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    /// Podoby tabu, každá pod svým jménem v souboru. Čtyři případy `ChecksTabState` a k tomu
    /// `stale`, což je `list(_, failure:)` — tedy pátá podoba téhož stavu, ne pátý stav.
    private enum Scenario: String, CaseIterable {
        case loading = "nenacteno"
        case empty = "bez-ci"
        case list = "seznam"
        case failed = "porucha"
        case stale = "zastaraly-seznam"
    }

    @Test("Vyrendrovat tab Kontroly ve všech stavech")
    func rendersEveryState() async throws {
        let directory = Self.outputDirectory
        for scenario in Scenario.allCases {
            let (store, cache) = try await prepared(scenario)
            defer { _ = cache }
            for width in [1400.0, 760.0] as [CGFloat] {
                let url = directory.appending(path: "kontroly-\(scenario.rawValue)-\(Int(width)).png")
                try capture(store: store, width: width, to: url)
                print("SONDA \(url.path) — \(scenario.rawValue), \(Int(width)) b, "
                    + "stav \(store.checksTabState(for: pr))")
            }
        }
    }

    // MARK: - Scéna

    /// Store s načteným detailem a diffem a s checky nastavenými **až po** `loadDetail`.
    ///
    /// Pořadí je podmínka, ne detail: `loadDetail` si checky dotahuje sám, takže nastavené předem
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
        await store.loadDiff(for: Self.summary)
        store.openTab(pr)
        store.setDetailTab(.checks, for: pr)

        switch scenario {
        case .loading:
            store.checks[pr] = nil
            store.checkFailures[pr] = nil
            // Aby stav `nenačteno` **vydržel celý render**: `.task` v detailu volá `loadDetail`, a ten
            // si od #306 v cache větvi checky dotáhne, když o nich neví nic — jinak by po zrušeném
            // načtení svítilo `Načítám kontroly…` navždycky. Zrušené volání je zrovna ten stav, ve
            // kterém se v aplikaci `nenačteno` drží, takže se tady nasadí i sondě.
            gateway.checksFailure = CancellationError()
        case .empty:
            store.checks[pr] = []
            store.checkFailures[pr] = nil
        case .list:
            store.checks[pr] = Self.checks
            store.checkFailures[pr] = nil
        case .failed:
            store.checks[pr] = nil
            store.checkFailures[pr] = Self.failure
        case .stale:
            store.checks[pr] = Self.checks
            store.checkFailures[pr] = Self.failure
        }
        return (store, directory)
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u tabů (#294),
    /// `Přehledu` (#291) a bloku kódu (#236), viz `docs/testovani.md`.
    private func capture(store: AppStore, width: CGFloat, to url: URL) throws {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil),
            merge: .constant(nil),
            branchPush: .constant(nil)
        )
        .frame(width: width, height: Self.height)
        .background(Palette.background)

        _ = try render(scene, width: width, height: Self.height, to: url)
    }

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
        // Hierarchie se doskládá až po jednom kole smyčky; `.task` v detailu si navíc dotahuje diff
        // a konverzaci z fake gatewaye, takže se na to musí nechat čas.
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

    private static let height: CGFloat = 820

    private static let failure = GitHubError
        .network("dial tcp: lookup api.github.com: no such host")
        .userDescription

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "aaaa1111",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "## Popis\n\nOdstavec s **tučným** a `inline kódem`."
    )

    private static let diffText = """
        diff --git a/pkg/cmd/autolink/list.go b/pkg/cmd/autolink/list.go
        --- a/pkg/cmd/autolink/list.go
        +++ b/pkg/cmd/autolink/list.go
        @@ -25,3 +25,3 @@
         	client := api.NewClientFromHTTP(httpClient)
        -	resp, err := http.Get(url)
        +	resp, err := client.REST(host, "GET", path, nil, &response)
         	return err
        """

    private static let checks: [PullRequestCheck] = [
        PullRequestCheck(
            name: "phpstan (level 8) / analyse",
            outcome: .failed,
            link: URL(string: "https://github.com/cli/cli/actions/runs/1/job/2"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 134)
        ),
        PullRequestCheck(
            name: "phpunit / 8.4",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 41)
        ),
        PullRequestCheck(name: "deploy", outcome: .skipped, link: nil, startedAt: nil, completedAt: nil),
    ]
}
