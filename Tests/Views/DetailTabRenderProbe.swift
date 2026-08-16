import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#294): vyrendruje **detail PR ve všech sedmi tabech**, aby se dalo vidět, kde
/// postranní lišta panelu je a kde není.
///
/// Existuje vedle `PanelFreeTabWidthTests` proto, že měření odpovídá na „přeteklo, nebo ne“, kdežto
/// otázka „je v tomhle tabu proužek panelu, nebo tam není“ je otázka na obrázek. A rendruje se
/// **celý detail přes `NSHostingView`**, ne jednotlivé taby: to, co se schovává, není obsah tabu,
/// ale jeho **sourozenec** v `HStack`u — takže render samotného tabu by o tom neřekl nic.
///
/// Dvě věci, kvůli kterým je to `NSHostingView` a ne `ImageRenderer`:
///
/// - `ImageRenderer` **nerasterizuje obsah `ScrollView`u**, a všech sedm tabů v něm sedí;
/// - `Link` v něm vyjde jako žlutý placeholder (poučení z #291), a odkazy jsou i v `Kontrolách`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda tabů detailu (#294)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DetailTabRenderProbe {
    /// Co se rendruje: široké okno a to nejužší, na které se dá přijít (podlaha 700 bez railu) —
    /// a v tom úzkém **obojí složení panelu**. Složený proužek je to, co je na snímku v zadání
    /// #294, a je to zrovna ten stav, ve kterém se schování dá přehlédnout: proužek je úzký, takže
    /// se z jednoho renderu nepozná od hrany okna.
    private let cases: [(width: CGFloat, expanded: Bool)] = [
        (1400, true),
        (648, true),
        (648, false),
    ]

    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    @Test("Vyrendrovat všech sedm tabů detailu")
    func rendersEveryTab() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        let (store, cache) = try await prepared()
        defer { _ = cache }

        for scenario in cases {
            store.isReviewPanelExpanded = scenario.expanded
            for tab in PullRequestTab.allCases {
                store.setDetailTab(tab, for: pr)
                let panel = scenario.expanded ? "rozlozeny" : "slozeny"
                let name = "detail-\(Self.slug(of: tab))-\(Int(scenario.width))-\(panel)"
                let url = directory.appending(path: "\(name).png")
                try capture(store: store, width: scenario.width, to: url)
                print("SONDA \(url.path) — \(tab.czechLabel), lišta \(tab.showsReviewPanel ? "ANO" : "NE")")
            }
        }
    }

    /// Tab `Změněné soubory` v rozsahovém pohledu (#284) — **lišta nad diffem**.
    ///
    /// Návrh tuhle obrazovku nekreslí (sekce 02 má jen tlačítko, ne stav po jeho stisknutí), takže
    /// je to jediné místo, kde se dá posoudit: rozsahový diff vypadá jako celý diff, jen kratší,
    /// a jestli je z lišty poznat proč, se z kódu nezjistí.
    @Test("Vyrendrovat rozsahový diff")
    func rendersTheIncrementalDiff() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        let (store, cache) = try await prepared()
        defer { _ = cache }

        store.setDetailTab(.filesChanged, for: pr)
        store.incrementalDiffs[pr] = IncrementalDiff(
            range: IncrementalDiffRange(seen: "4f2ac9188cd", head: "aaaa1111"),
            content: .loaded(DiffParser.parse(Self.diffText))
        )
        for width in [1400.0, 648.0] as [CGFloat] {
            let url = directory.appending(path: "detail-soubory-rozsah-\(Int(width)).png")
            try capture(store: store, width: width, to: url)
            print("SONDA \(url.path) — rozsahový diff")
        }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u `Přehledu`
    /// (#291), bloku kódu (#236) a odpočtu (#269), viz `docs/testovani.md`.
    private func capture(store: AppStore, width: CGFloat, to url: URL) throws {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil)
        )
        .frame(width: width, height: Self.height)
        .background(Palette.background)

        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
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
        // Hierarchie se doskládá až po jednom kole smyčky; `.task` v detailu si navíc dotahuje diff
        // a konverzaci z fake gatewaye, takže se na to musí nechat čas.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    /// Store s načteným detailem, diffem, checky, uloženými nálezy **a rozdělaným review** — tedy
    /// se všemi sedmi taby, ve kterých je co vidět.
    ///
    /// Draft je v tom schválně: složený proužek panelu nese kromě počtu nálezů i **značku
    /// rozdělaného review**, a v tabech, kde proužek není, se ta informace musí dát přečíst odjinud.
    /// Z renderu je vidět, odkud: chip `rozdělané review` v hlavičce PR, která je ve všech tabech.
    private func prepared() async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(Self.diffText)]
        )
        gateway.checks = Self.checks
        gateway.commits = Self.commits
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        store.checks[pr] = Self.checks
        store.reviewRecords[pr] = Self.record
        store.setDraftBody("Zbytek vypadá dobře, jen ta jedna kontrola.", for: pr)
        store.openTab(pr)
        store.reviewPanelTab = .findings
        // Složka se vrací s storem: `TemporaryDirectory` maže v `deinit`, takže by se cache draftu
        // ztratila ještě před renderem.
        return (store, directory)
    }

    private static func slug(of tab: PullRequestTab) -> String {
        switch tab {
        case .overview: "prehled"
        case .filesChanged: "soubory"
        case .commits: "commity"
        case .conversation: "konverzace"
        case .checks: "kontroly"
        case .findings: "nalezy"
        case .progress: "prubeh"
        }
    }

    private static let height: CGFloat = 820

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
        body: """
            ## Popis

            Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
            aby se v úzkém tabu zalomil na několik řádků.
            """
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

    /// Commity do tabu `Commity` (#316): jeden obyčejný, jedno sloučení a jeden bez účtu na
    /// GitHubu — tedy všechny tři podoby řádku, které se od sebe mají poznat. Poslední je hlava
    /// (`headSha` v `detail`), takže nese pilulku `hlava`.
    private static let commits: [PullRequestCommit] = [
        PullRequestCommit(
            sha: "c82266c2dcc3285033605501837434af1faeddfe",
            message: "Warn instead of failing when issue fields can't be set",
            authorName: "imkp1",
            authorLogin: "imkp1",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_900_000),
            isMerge: false
        ),
        PullRequestCommit(
            sha: "96a469b6bd159d4cff137d5eab4d13ceee4c9807",
            message: "Merge branch 'trunk' into fix/13804-gh-issue-create-errors-after-successful",
            authorName: "Kumar Prateek",
            authorLogin: "imkp1",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_950_000),
            isMerge: true
        ),
        PullRequestCommit(
            sha: "aaaa1111",
            message: "Resolve deferred issue fields before creating the issue",
            authorName: "Jiří Novák",
            authorLogin: nil,
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_990_000),
            isMerge: false
        ),
    ]

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

    private static var record: ReviewRecord {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: nil)
        let clock = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.queued, at: clock)
        timeline.record(.started(sessionID: "6f1c2b7a"), at: clock)
        timeline.record(.findings(count: 2), at: clock)
        timeline.finish(.finished, at: clock)

        let reported = [
            makeReported(
                file: "pkg/cmd/autolink/list.go",
                line: 26,
                category: "correctness",
                summary: "Návratová hodnota se zahazuje, takže selhání zápisu vypadá v UI jako „nic tu nebylo“."
            ),
            makeReported(category: "tests", summary: "Chybí test na to, že se nic neodešle."),
        ]
        return ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(findings: reported, headSha: "aaaa1111", timeline: timeline.stored())]
        )
    }
}
