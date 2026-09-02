import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Vejdou se kolony diffu do okna?** — sonda k vadě z proklikání #503: obsah diffu zalézal pod
/// složený proužek panelu vpravo.
///
/// Měří to, co se dá měřit: **rámec scrolleru diffu v souřadnicích okna**. Scroller je
/// `NSScrollView`, tedy skutečné AppKitové view — na rozdíl od kolon, které jsou SwiftUI a v okně
/// testovacího hostu se nedají přečíst z accessibility tree (změřeno u `DashboardCountdownRedrawTests`).
///
/// Ptá se přes **pásmo šířek**, ne u jedné (#236): vada se hlásila při varování `72 znaků na
/// stranu`, tedy u úzkého okna ve `Vedle sebe`, a u širokého se neprojeví.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, kresba do `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Vejdou se kolony diffu do okna? (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffColumnFitProbe {
    /// Šířky, na kterých se to zkouší. **700 je podlaha, ne odhad**: `RootView` má
    /// `frame(minWidth: 700)` a `PRismApp` `windowResizability(.contentMinSize)`, takže užší okno
    /// v aplikaci nevznikne. Zkoušet 509 **nemá smysl a je to zaplacená slepá ulička**: obsah se
    /// pod svým minimem rozvrhne na 700 a přeteče o 153 bodů, což je artefakt sondy, ne vada
    /// aplikace.
    private static let widths = [700.0, 820.0, 1100.0, 1400.0]

    @Test("Rámec scrolleru diffu proti šířce okna")
    func columnsFit() async throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for width in Self.widths {
            for layout in [DiffLayout.split, .unified] {
                for findings in [true, false] {
                    for forced in Forced.allCases {
                        let scene = try await Scene.make(width: width, layout: layout, findings: findings)
                        defer { scene.window.orderOut(nil) }
                        await scene.letItSettle()
                        // **Ruční stav se nasazuje až po usazení**, ne před ním: `task(id: columns)`
                        // v `DiffView` při vzniku srovná strom i panel podle `Policy`, takže
                        // hodnota nastavená dřív by se přepsala. Po usazení se `columns` nemění,
                        // takže tenhle zápis už nikdo nesundá — a je to týž stav, do jakého se
                        // člověk dostane `⌘1` / `⌘2`.
                        await scene.force(forced)
                        let slug = String(format: "%.0f-%@-%@-%@", width,
                                          layout == .split ? "vedle" : "podsebou",
                                          findings ? "nalezy" : "bez", forced.rawValue)
                        print("SONDA \(slug): \(scene.report(findings: findings))")
                        if let directory, width <= 820 {
                            scene.write(to: URL(filePath: directory).appending(path: "kolony-\(slug).png"))
                        }
                    }
                }
            }
        }
    }

    /// Co si člověk přebil ručně proti tomu, co `Policy.diffSideColumns` rozhodla.
    ///
    /// Je to podstatná část mřížky, ne úplnost: automatika sáhne na strom a panel **jednou na
    /// rozhodnutí** (`task(id: columns)` se stráží `appliedColumns`), takže stav *split a k tomu
    /// rozložený strom* je normální a **drží se**, dokud se pohled nezmění.
    enum Forced: String, CaseIterable {
        case none = "auto"
        case tree = "strom"
        case panel = "panel"
        case both = "strom+panel"
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let store: AppStore
        let defaults: ScratchDefaults
        let directory: TemporaryDirectory
        let width: Double

        static func make(width: Double, layout: DiffLayout, findings: Bool) async throws -> Scene {
            let defaults = try ScratchDefaults("diffColumnFit")
            let directory = try TemporaryDirectory()
            let gateway = FakeGitHubGateway(
                always: .success([summary]),
                detail: .success(detail),
                diffs: [.success(material())],
                conversations: [.success(ConversationFixture.conversation(comments: 8))]
            )
            let store = AppStore(
                gateway: gateway,
                time: FakeTimeSource(stopAfter: 1),
                drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
            )
            await store.refresh()
            await store.loadDetail(for: summary)
            await store.loadDiff(for: summary)
            await store.loadConversation(for: summary)
            if findings {
                store.reviewRecords[pr] = ReviewRecord(
                    pullRequest: summary.id,
                    headSha: "aaaa1111",
                    runs: [makeStoredRun(findings: reported, headSha: "aaaa1111")]
                )
            }
            store.openTab(pr)
            store.setDetailTab(.filesChanged, for: pr)
            store.setDiffLayout(layout)

            let clock = RelayoutClock()
            let host = NSHostingView(
                rootView: WindowRelayoutHost(store: store, summary: summary, scene: .window, clock: clock)
                    .background(Palette.background)
                    .defaultAppStorage(defaults.store)
            )
            host.sizingOptions = [.minSize]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.setContentSize(NSSize(width: width, height: 800))
            window.setFrameOrigin(NSPoint(x: 20, y: 20))
            window.level = .floating
            window.orderFrontRegardlessUnanimated()
            return Scene(window: window, store: store, defaults: defaults,
                         directory: directory, width: width)
        }

        /// Nechá scénu usadit. **Jméno není `settle()`** schválně: `settle()` je globální
        /// odmlka z `Tests/Support/TestWaiting.swift` (#296) a metoda téhož jména by ji uvnitř
        /// typu zastínila — volalo by se tady dokola samo sebe.
        func letItSettle() async {
            for _ in 0..<12 { await settle() }
        }

        /// Nasadí ruční stav (`⌘1` / `⌘2`) a nechá scénu znovu usadit.
        func force(_ forced: Forced) async {
            switch forced {
            case .none: return
            case .tree: defaults.store.set(true, forKey: "diffTreeExpanded")
            case .panel: store.isReviewPanelExpanded = true
            case .both:
                defaults.store.set(true, forKey: "diffTreeExpanded")
                store.isReviewPanelExpanded = true
            }
            await letItSettle()
        }

        /// Co se v okně naměřilo. **Scroller diffu je ta kolona s kódem**, takže jeho pravá hrana
        /// říká, kam obsah dosahuje — a šířka okna, kam dosahovat smí.
        ///
        /// K tomu se hlásí **rozdíl proti očekávanému pravému chromu**: obsah má končit tam, kde
        /// začíná okraj s kartami (300) nebo složený proužek panelu (38). Kladné `přetečení`
        /// znamená, že obsah zalézá pod ně.
        func report(findings: Bool) -> String {
            guard let root = window.contentView,
                  let scroller = Self.tallestScroller(in: root)
            else { return "scroller v okně není" }
            let frame = scroller.convert(scroller.bounds, to: nil)
            let right = width - frame.maxX
            // **Očekávání se skládá z `Policy`, ne z vlastních konstant**: sonda se jinak ptá na
            // jiné rozhodnutí, než jaké aplikace udělala, a její „přetečení“ pak měří rozdíl
            // dvou názorů místo vady. (Stalo se: první podoba sondy hlásila −306 tam, kde okno
            // sedělo na bod.)
            let columns = Policy.diffSideColumns(
                layout: store.configuration.global.diffLayout,
                hasMargin: findings,
                available: width - Self.railWidth - (store.isReviewPanelExpanded
                    ? Self.expandedPanelFloor : Self.collapsedPanelWidth)
            )
            let panelWidth = store.isReviewPanelExpanded ? Self.expandedPanelFloor : Self.collapsedPanelWidth
            let needed = Policy.marginColumnWidth(shown: columns.margin) + panelWidth
            return String(
                format: "okno %.0f | scroller x %.0f…%.0f (šířka %.0f) | vpravo zbývá %.0f,"
                    + " potřeba %.0f → PŘETEČENÍ %.0f | okraj %@ strom %@",
                width, frame.minX, frame.maxX, frame.width, right, needed, needed - right,
                columns.margin ? "ano" : "ne", columns.tree ? "ano" : "ne"
            )
        }

        /// Šířka railu a mez panelu — **jen na skládání očekávání v sondě**. Rail je AppKitu
        /// neznámý (SwiftUI) a panel se dá táhnout, takže se bere jeho **podlaha**: kdyby obsah
        /// sahal dál než k ní, panel by se musel zmáčknout pod svoje minimum.
        static let railWidth = 56.0
        static let collapsedPanelWidth = 38.0
        static let expandedPanelFloor = 246.0

        static func tallestScroller(in view: NSView) -> NSScrollView? {
            var best = view as? NSScrollView
            for child in view.subviews {
                guard let found = tallestScroller(in: child) else { continue }
                let height = found.documentView?.frame.height ?? 0
                if height > (best?.documentView?.frame.height ?? 0) { best = found }
            }
            return best
        }

        func write(to url: URL) {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: url)
                print("SONDA kresba → \(url.lastPathComponent)")
            } catch {
                print("SONDA kresba \(url.lastPathComponent) se neuložila: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Materiál

    /// Nový soubor s dlouhými řádky — tedy ta scéna z proklikání: levá strana je celá šrafovaná
    /// a přesah je na ní vidět lépe než jinde.
    private static func material() -> String {
        var out = "diff --git a/App/Policy/PullRequestMap.swift b/App/Policy/PullRequestMap.swift\n"
        out += "new file mode 100644\n"
        out += "index 0000000..2222222\n"
        out += "--- /dev/null\n"
        out += "+++ b/App/Policy/PullRequestMap.swift\n"
        out += "@@ -0,0 +1,347 @@\n"
        for line in 0..<347 {
            out += "+    let segment\(line) = PullRequestMapSegment(file: file, rows: rows, kind: .added)\n"
        }
        return out
    }

    private static let reported: [ReportedFinding] = (0..<4).map { index in
        makeReported(
            file: "App/Policy/PullRequestMap.swift",
            line: 12 + index * 40,
            category: index.isMultiple(of: 2) ? "correctness" : "style",
            summary: "Návratová hodnota se zahazuje, takže selhání zápisu vypadá jako „nic tu nebylo“."
        )
    }

    private static let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    private static let summary = PullRequestSummary(
        id: pr,
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
        body: "Popis pull requestu, nad kterým se měří, jestli se kolony vejdou."
    )
}
