import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#303): **kolik místa v okně zbude na seznam checků**, když okýnko s koncem logu
/// vyroste.
///
/// Existuje proto, že výška okýnka se nezvedá odhadem. Původní 320 bodů má zapsaný důvod — 300 řádků
/// nasázených naplno odtlačilo zbytek seznamu checků mimo obrazovku, tedy zrovna to, kvůli čemu se
/// detail checku stěhoval z `Přehledu` do vlastního tabu (#215). Nová výška je tedy kompromis, který
/// se **dá spočítat**: sonda vyrendruje tab `Kontroly` s rozbaleným spadlým checkem, najde
/// v hierarchii **viewport tabu** i **okýnko logu** a vypíše, kolik bodů zbylo pod ním — a kolik je
/// to řádků seznamu.
///
/// **Rendruje se `PullRequestDetailView`, ne `ChecksView`**: nad tabem je hlavička PR a pruh záložek,
/// a ty z výšky okna ukusují dřív, než se na seznam checků dostane. Výška okna se z nich odvozuje
/// zpátky (`windowHeights` mínus hlavička okna a stavový řádek), takže čísla mluví o oknu, ne
/// o abstraktní ploše.
///
/// **Kandidáti na výšku se nerendrují jeden po druhém.** Vše kromě okýnka je ve výšce pevné, takže
/// z jednoho renderu vyjde konstanta a zbytek je odčítání — a druhý render (s už zvolenou výškou)
/// slouží k tomu, aby se to dalo **vidět**.
///
/// **Pouští se ručně**, `TEST_RUNNER_PRISM_MEASURE` jako ostatní sondy; PNG jde do
/// `TEST_RUNNER_PRISM_RENDER_DIR`:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     -only-testing:PRismTests/CheckLogRoomProbe > /tmp/probe.log 2>&1
/// ```
@MainActor
@Suite(
    "Sonda místa pro konec logu (#303)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct CheckLogRoomProbe {
    /// Výšky **okna**, ne tabu: 952 je okno na tomhle stroji (změřeno), 700 výchozí `defaultSize`
    /// z `PRismApp`, 560 menší běžné a 400 podlaha z `RootView`, pod kterou okno stáhnout nejde.
    /// Menší okna jsou v zadání výslovně — na celé obrazovce se vejde všechno a rozhodnutí by z toho
    /// vyšlo falešně velkorysé.
    private let windowHeights: [CGFloat] = [952, 810, 700, 560, 400]

    /// Šířka okna z `defaultSize` mínus rail (52 + linka), tedy to, co dostane obsah.
    private let contentWidth: CGFloat = 1100 - 53

    /// Kandidáti na strop, na které se odčítáním přepočítává zbylé místo. Hodnoty jsou `14N + 25`
    /// (řádek 14 bodů, `2 × inset` 8 a rezerva na vodorovný scroller 17), takže na každém z nich
    /// končí okýnko **celým řádkem**, ne půlkou.
    ///
    /// **Přepočítáno u #347** z `14N + 21`, kde ta rezerva byla 13 — odměřená na `.small` scrolleru
    /// místo na `.regular`, který se kreslí. Je to tentýž výčet řádků (21, 26, 28, 30, 32, 36), jen
    /// posazený na správnou rezervu; každá hodnota tedy vyrostla o 4 body. První je stav před #303,
    /// čtvrtá je dnešní strop.
    private let candidates: [CGFloat] = [319, 389, 417, 445, 473, 529]

    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue-daemon"), number: 858)

    @Test("Kolik zbude na seznam checků")
    func measuresRoomLeftForTheList() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        let (store, cache) = try await prepared()
        defer { _ = cache }

        print("MĚŘENÍ řádek seznamu: \(fmt(rowHeight)) bodů, stavový řádek \(fmt(statusBarHeight)) bodů")
        print("MĚŘENÍ strop dnes: \(fmt(CheckDetailView.logMaxHeight)) bodů, \(lines(in: CheckDetailView.logMaxHeight)) řádků logu")

        for window in windowHeights {
            let height = window - Self.windowHeaderHeight - statusBarHeight
            let url = directory.appending(path: "kontroly-log-okno-\(Int(window)).png")
            let measured = try render(store: store, height: height, to: url)
            print("""
                MĚŘENÍ okno \(Int(window)) → tab \(fmt(height)) bodů, viewport \(fmt(measured.viewport)) bodů, \
                okýnko logu \(fmt(measured.log)) bodů, pod ním zbylo \(fmt(measured.below)) bodů \
                (\(Int(measured.below / rowHeight)) řádků seznamu) — \(url.lastPathComponent)
                """)
            for candidate in candidates {
                let below = measured.below - (candidate - CheckDetailView.logMaxHeight)
                print("""
                    \tkandidát \(fmt(candidate)) (\(lines(in: candidate)) řádků logu): \
                    zbylo \(fmt(below)) bodů = \(Int((below / rowHeight).rounded(.down))) řádků seznamu
                    """)
            }
        }

        // **Krátký log si nemá vzít celý strop.** Je to tvrzení `LogTailHeightTests`, ale ta počítají
        // výšku — jak to vypadá, se počítáním nezjistí, a od #303 se okýnko skládá ručně
        // (`makeScrollView`), takže se to má vidět na kresbě, ne dovodit.
        let url = directory.appending(path: "kontroly-log-kratky.png")
        let short = try render(store: store, height: 700 - Self.windowHeaderHeight - statusBarHeight, to: url, log: "PHPUnit 11.5.0\nOK (3 tests, 5 assertions)\n##[error]Process completed with exit code 1.")
        print("MĚŘENÍ krátký log (3 řádky): okýnko \(fmt(short.log)) bodů, pod ním zbylo \(fmt(short.below)) bodů — \(url.lastPathComponent)")

        // **A ten samý krátký log s řádkem, který se nevejde na šířku** (#347). Rezerva na vodorovný
        // scroller se z výšky ukusuje jedině tehdy, když ten scroller doopravdy je — u předchozího
        // renderu se `autohidesScrollers` postará o to, že není, takže z něj rezervu nevidět. Tohle je
        // ten stav, ve kterém rozhoduje: s rezervou odměřenou na `.small` (13 bodů) bylo okýnko o 2 body
        // nižší než jeho vlastní dokument, takže log, který se měl vejít celý, dostal svislý scroller.
        let wide = directory.appending(path: "kontroly-log-kratky-dlouhy-radek.png")
        let long = String(repeating: "x", count: 2_258)
        let wideRoom = try render(
            store: store,
            height: 700 - Self.windowHeaderHeight - statusBarHeight,
            to: wide,
            log: "PHPUnit 11.5.0\n\(long)\n##[error]Process completed with exit code 1."
        )
        print("MĚŘENÍ krátký log s dlouhým řádkem: okýnko \(fmt(wideRoom.log)) bodů — \(wide.lastPathComponent)")
    }

    // MARK: - Měření

    /// Hlavička okna z `ContentView` — 40 bodů a linka pod nimi. Opsané číslo, protože je to
    /// `frame(height: 40)` uvnitř `private var header`; kdyby se rozešlo, vyjde tab o bod vyšší,
    /// ne o řád.
    private static let windowHeaderHeight: CGFloat = 41

    /// Co se z renderu vyčetlo.
    private struct Room {
        /// Výška viewportu tabu `Kontroly` — tedy toho `NSScrollView`u, ve kterém seznam sedí.
        let viewport: CGFloat
        /// Výška okýnka s koncem logu.
        let log: CGFloat
        /// Kolik bodů viewportu zbývá **pod** okýnkem logu. To je to místo, ve kterém může být
        /// vidět zbytek seznamu checků.
        let below: CGFloat
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u sondy tabů
    /// (#294), `Přehledu` (#291) a odpočtu (#269). `ImageRenderer` by nestačil: obsah
    /// `NSScrollView`u nerasterizuje, a přesně ten je tady předmětem měření.
    ///
    /// **Log dorazí až po prvním rozložení**, ne s hierarchií naráz — a je to podmínka, ne
    /// pohodlí: v aplikaci se stahuje na kliknutí, takže `NSTextView` vzniká do už rozloženého
    /// okna a `scrollToEndOfDocument` má na čem pracovat. Když se text podá hned při stavbě,
    /// okýnko zůstane na **začátku** ocasu — a to je vlastnost sondy, ne aplikace (změřeno u #303,
    /// obě cesty vedle sebe).
    private func render(store: AppStore, height: CGFloat, to url: URL, log: String = Self.log) throws -> Room {
        // Každý render začíná bez logu, i ten druhý a třetí v řadě — jinak by se do nově postavené
        // hierarchie podal text hned a okýnko by zůstalo na začátku ocasu.
        store.checkDetails[Self.logKey]?.log = .loading(bytes: 1_695_207)
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil)
        )
        .frame(width: contentWidth, height: height)
        .background(Palette.background)

        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním vývoji stojí vedle sebe
        // víc instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        // Hierarchie se doskládá až po kole smyčky; `.task` v detailu si k tomu dotahuje diff
        // a konverzaci z fake gatewaye.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        // Teprve teď log — jako v aplikaci, kde dorazí ze sítě do rozloženého okna.
        store.checkDetails[Self.logKey]?.log = .loaded(full: Policy.jobLog(log, fetchedAt: .now), tail: Policy.logTail(log))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        let room = try room(in: hosting)
        window.orderOut(nil)
        return room
    }

    /// Viewport tabu a okýnko logu z **hierarchie**, ne z odhadu.
    ///
    /// Okýnko logu se pozná podle toho, že jeho `documentView` je `NSTextView` (tak si ho
    /// `LogTailTextView` staví), a viewport tabu je ten `NSScrollView`, který ho obsahuje.
    private func room(in hosting: NSView) throws -> Room {
        let scrolls = Self.scrollViews(in: hosting)
        let log = try #require(
            scrolls.first { $0.documentView is NSTextView },
            "okýnko konce logu se v hierarchii nenašlo — rendruje se ten správný tab?"
        )
        let viewport = try #require(
            scrolls.first { $0 !== log && $0.isDescendant(of: hosting) && log.isDescendant(of: $0) },
            "viewport tabu Kontroly se nenašel"
        )
        let logRect = log.convert(log.bounds, to: viewport)
        // `NSScrollView` má nepřevrácené souřadnice (y roste nahoru), takže „pod okýnkem" je
        // vzdálenost od spodní hrany viewportu k spodní hraně okýnka. Převrácené se ošetřuje,
        // protože to je vlastnost view, ne konstanta.
        let below = viewport.isFlipped
            ? viewport.bounds.maxY - logRect.maxY
            : logRect.minY - viewport.bounds.minY
        return Room(viewport: viewport.bounds.height, log: logRect.height, below: below)
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for child in view.subviews { found.append(contentsOf: scrollViews(in: child)) }
        return found
    }

    /// Výška jednoho řádku seznamu i s linkou pod ním — **rozdílem dvou sazeb**, ne z konstant ve
    /// view: `padding` se dá změnit, aniž by si toho tahle sonda všimla.
    private var rowHeight: CGFloat {
        let one = cardHeight(checks: Array(Self.checks.prefix(2)))
        let two = cardHeight(checks: Array(Self.checks.prefix(3)))
        return two - one
    }

    private func cardHeight(checks: [PullRequestCheck]) -> CGFloat {
        let view = ChecksView(checks: checks).content.frame(width: contentWidth)
        return NSHostingView(rootView: view).fittingSize.height
    }

    private var statusBarHeight: CGFloat {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())
        let view = StatusBarView(store: store).frame(width: contentWidth)
        return NSHostingView(rootView: view).fittingSize.height
    }

    /// Kolik řádků logu se do stropu vejde — z metriky **toho** fontu, kterým se kreslí (#236),
    /// a z **jednoho měřidla** (`FontMetric`, #407).
    private func lines(in limit: CGFloat) -> Int {
        let lineHeight = FontMetric.shared.lineHeight(of: LogTailTextView.font(size: CheckDetailView.logFontSize))
            + CheckDetailView.logLineSpacing
        let usable = limit - 2 * LogTailTextView.inset.height - LogTailTextView.horizontalScrollerHeight
        return Int((usable / lineHeight).rounded(.down))
    }

    private func fmt(_ value: CGFloat) -> String { String(format: "%.0f", value) }

    // MARK: - Scéna

    /// Store s načteným detailem a **rozbaleným spadlým checkem**, jehož log je dlouhý natolik, aby
    /// se okýnko zastropovalo.
    ///
    /// Checky jsou opsané ze skutečného PR (`keboola/job-queue-daemon#858`): tři `Tests`, build
    /// a tři `Prepare ENV`. Rozbalený je ten spadlý, a ten stojí v seznamu **první** (`Policy.sorted`
    /// řadí spadlé nahoru) — tedy v tom nejhorším případě, kdy detail odtlačuje všechno ostatní.
    private func prepared() async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(Self.diffText)]
        )
        gateway.checks = Self.checks
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        store.checks[pr] = Self.checks
        store.openTab(pr)
        store.setDetailTab(.checks, for: pr)
        store.expandedChecks[pr] = Self.logKey.check
        store.checkDetails[Self.logKey] = CheckDetailState(
            annotations: .loaded(CheckAnnotations(items: [
                CheckAnnotation(
                    path: ".github",
                    line: 5015,
                    level: .failure,
                    message: "Process completed with exit code 1."
                ),
            ])),
            // Log dorazí až po rozložení okna, viz `render(store:height:to:)`.
            log: .loading(bytes: 1_695_207)
        )
        return (store, directory)
    }

    private static let logKey = CheckKey(
        pullRequest: PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue-daemon"), number: 858),
        check: "Tests (aws)"
    )

    /// Log o počtu řádků nad stropem, ať se okýnko zastropuje. Tvar podle skutečného
    /// (`Tests (aws)` má 5 899 řádků), ale bez timestampů — ty `Policy.logTail` stejně sundá.
    private static let log = (0..<Policy.logTailLines + 200)
        .map { "PHPUnit \($0): assertion failed, expected 'ok' but got 'nope' in JobRunnerTest.php" }
        .joined(separator: "\n")

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue-daemon"), number: 858),
        title: "Retry failed jobs per row",
        author: "ondrajodas",
        url: URL(string: "https://github.com/keboola/job-queue-daemon/pull/858")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "3d8cf6bd",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Popis PR na jeden odstavec, ať hlavička vypadá jako na skutečném PR."
    )

    private static let diffText = """
        diff --git a/src/JobRunner.php b/src/JobRunner.php
        --- a/src/JobRunner.php
        +++ b/src/JobRunner.php
        @@ -25,3 +25,3 @@
         	$job = $this->queue->pop();
        -	$this->run($job);
        +	$this->runWithRetry($job);
         	return $job;
        """

    private static let checks: [PullRequestCheck] = [
        PullRequestCheck(
            name: "Tests (aws)",
            outcome: .failed,
            link: URL(string: "https://github.com/keboola/job-queue-daemon/actions/runs/1/job/90007149348"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 934)
        ),
        PullRequestCheck(
            name: "Tests (azure)",
            outcome: .passed,
            link: URL(string: "https://github.com/keboola/job-queue-daemon/actions/runs/1/job/90007149470"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 903)
        ),
        PullRequestCheck(
            name: "Tests (gcp)",
            outcome: .passed,
            link: URL(string: "https://github.com/keboola/job-queue-daemon/actions/runs/1/job/90007149263"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 912)
        ),
        PullRequestCheck(
            name: "Build Docker Images",
            outcome: .passed,
            link: URL(string: "https://github.com/keboola/job-queue-daemon/actions/runs/1/job/90005919224"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 187)
        ),
        PullRequestCheck(
            name: "Prepare ENV / Prepare aws ENV",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 61)
        ),
        PullRequestCheck(
            name: "Prepare ENV / Prepare gcp ENV",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 58)
        ),
        PullRequestCheck(name: "Prepare variables", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
    ]
}
