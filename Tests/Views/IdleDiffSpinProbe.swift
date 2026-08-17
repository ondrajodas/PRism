import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361: **kolik CPU sežere okno s otevřeným diffem, ve kterém se nic nemění.**
///
/// Sestra `IdleWindowSpinProbe` (#350) pro druhou signaturu z tabulky u #350 — pro tu, ve které
/// v cestě není `NSDisplayCycleFlush` ani `runAnimationGroup`, ale
/// `flushObservers → beginTransaction → flushTransactions`. Ta se od animace liší tím, že ji
/// nepohání takt obrazovky: pohonem je něco, co si po každém kole nechá naplánovat další.
///
/// **Kurzor k tomu není potřeba a je to celý rozdíl proti #358.** Tam se smyčka zavírala přes
/// `onContinuousHover`, takže bez skutečné myši nad blokem kódu nenastala (změřeno, viz
/// `docs/testovani.md`). Tady se měří scéna sama.
///
/// Měří se **CPU hlavního vlákna**, ne nástěnný čas — smyčka většinu času spí. A **na obrazovce**,
/// ze stejného důvodu jako u #350: zakryté okno nedostává takt překreslování.
///
/// **Co sonda ukázala** (čísla v `docs/testovani.md`): nad žádným ze scénářů se smyčka nechytla,
/// tedy scéna sama ji nezavírá. Dvě věci se u toho **musely** srovnat, jinak sonda měří prázdno:
/// rozměr okna a to, že v něm doopravdy jsou bloky kódu — proto ta dvě čísla ve výpisu.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Nečinné okno s diffem (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct IdleDiffSpinProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)

    /// Kolik CPU stojí nečinné okno podle toho, co je v něm. Rozhoduje **rozdíl mezi řádky
    /// tabulky**, ne absolutní číslo: kolo smyčky samo něco stojí, takže se scénáře poměřují
    /// mezi sebou.
    @Test("Kolik CPU sežere nečinné okno s diffem")
    func idleDiffBurnsNoCPU() async throws {
        let scenarios: [(name: String, tab: PullRequestTab, layout: DiffLayout, big: Bool)] = [
            ("přehled (bez diffu)", .overview, .unified, true),
            ("diff pod sebou", .filesChanged, .unified, true),
            ("diff vedle sebe", .filesChanged, .split, true),
            ("diff vedle sebe, malý", .filesChanged, .split, false),
        ]
        for scenario in scenarios {
            try await measure(scenario.name, tab: scenario.tab, layout: scenario.layout, big: scenario.big)
        }
    }

    /// Celé okno, ne jen detail: rail, hlavička, pruh záložek se **třemi otevřenými PR**, nálezy
    /// v diffu a vlákna konverzace — tedy scéna, ve které se #361 chytila.
    @Test("Plné okno se třemi záložkami a bublinami")
    func idleFullWindow() async throws {
        try await measure(
            "plné okno, tři záložky, nálezy",
            tab: .filesChanged,
            layout: .split,
            big: true,
            seconds: 8,
            full: true
        )
    }

    /// Totéž, ale s diffem **odscrollovaným do prostředka**. Líný seznam si v tom stavu odhaduje
    /// polohy do obou stran a `LazyLayoutViewCache` si říká o předběžné načtení
    /// (`signalPrefetch` ve vzorku u #361), takže je to jiná situace než seznam na svém vršku.
    @Test("Plné okno s odscrollovaným diffem")
    func idleScrolledWindow() async throws {
        for offset in [2000.0, 8000.0] {
            try await measure(
                "plné okno, odscrollováno o \(Int(offset))",
                tab: .filesChanged,
                layout: .split,
                big: true,
                seconds: 6,
                full: true,
                scrollBy: offset
            )
        }
    }

    /// Dlouhý běh nad plným oknem, aby se dal vzít `sample` testovacího hosta a porovnat
    /// signatura s tou ze ztuhlé aplikace (postup v `docs/testovani.md`).
    @Test("Dlouhé nečinné okno k odvzorkování")
    func longIdleWindow() async throws {
        let (store, cache) = try await prepared(big: true, full: true)
        defer { _ = cache }
        store.setDetailTab(.filesChanged, for: pr)
        store.setDiffLayout(.split)
        let window = show(store: store, full: true)
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        print("SONDA odscrollováno na \(Self.scroll(window.contentView, by: 8000))")
        _ = spinMainRunLoop(seconds: 2)
        print("SONDA PID \(ProcessInfo.processInfo.processIdentifier), 8× 5 s")
        // Po pěti sekundách se vypisuje průběžně: z jednoho čísla za třicet sekund se nepozná,
        // jestli se něco doúčtovalo na začátku, nebo to hoří pořád.
        for slice in 1...8 {
            let cpu = spinMainRunLoop(seconds: 5)
            print(String(format: "MĚŘENÍ úsek %d: %.2f %% CPU hlavního vlákna", slice, cpu / 5 * 100))
        }
    }

    /// Jeden scénář: postavit okno, nechat ho stát a vypsat, co v něm je a kolik to stálo.
    ///
    /// Vypisuje se i **velikost okna**: `NSHostingController` cpe velikost scény do okna, takže
    /// okno, které si samo mění rozměr, je vidět — a nad takovým oknem měření nic neváží.
    private func measure(
        _ name: String,
        tab: PullRequestTab,
        layout: DiffLayout,
        big: Bool,
        seconds: TimeInterval = 4,
        full: Bool = false,
        scrollBy offset: Double = 0
    ) async throws {
        let (store, cache) = try await prepared(big: big, full: full)
        defer { _ = cache }
        store.setDetailTab(tab, for: pr)
        store.setDiffLayout(layout)
        let window = show(store: store, full: full)
        defer { window.orderOut(nil) }
        // Usadit: po prvním zobrazení se hierarchie skládá a to do měření nepatří.
        _ = spinMainRunLoop(seconds: 2)
        if offset > 0 {
            let scrolled = Self.scroll(window.contentView, by: offset)
            print("SONDA \(name): odscrollováno na \(scrolled)")
            // Po posunu se seznam přerovnává; usazení do měření nepatří.
            _ = spinMainRunLoop(seconds: 2)
        }

        let cpu = spinMainRunLoop(seconds: seconds)
        // Obsah okna se **vyžaduje**, ne dosazuje prázdným view: bez něj by počty prvků a bloků
        // vyšly nula a sonda by tvrdila „čisto“ nad oknem, do kterého se nepodívala.
        let root = try #require(window.contentView)
        print(String(
            format: "MĚŘENÍ %@: %.2f %% CPU hlavního vlákna v nečinném okně"
                + " (%d prvků, %d bloků kódu, %d souborů diffu, okno %.0f×%.0f)",
            name,
            cpu / seconds * 100,
            Self.descendants(of: root),
            Self.blocks(in: root),
            Self.files(in: store.diffState(for: pr)),
            window.frame.width,
            window.frame.height
        ))
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }

    private static func files(in state: DiffState?) -> Int {
        guard case .loaded(let diff, _) = state else { return 0 }
        return diff.files.count
    }

    /// Odscrolluje **ten nejvyšší** scroll view v okně, tedy seznam řádků diffu: sloupce dvojice
    /// jsou taky ve scroll view (kvůli ořezu, viz `DiffPairBlockContainer`), ale nízké.
    private static func scroll(_ root: NSView?, by offset: Double) -> String {
        guard let root, let scroller = tallestScroller(in: root) else { return "nenašel jsem scroller" }
        scroller.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scroller.reflectScrolledClipView(scroller.contentView)
        return "\(scroller.documentVisibleRect.origin) z obsahu \(scroller.documentView?.frame.height ?? 0)"
    }

    private static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }

    /// Kolik bloků kódu v okně doopravdy je. Bez toho čísla sonda netvrdí nic: nulové CPU nad
    /// oknem, ve kterém diff není, je stejně dobře prázdné okno — a přesně to se stalo, dokud
    /// se velikost okna nastavovala před kontrolérem (viz `show`).
    private static func blocks(in view: NSView) -> Int {
        view.subviews.reduce(view is DiffPairBlockContainer || view is DiffTextView ? 1 : 0) {
            $0 + blocks(in: $1)
        }
    }

    /// Okno se scénou **na obrazovce** — rozměr z té instance, na které se #361 chytila
    /// (1512×874).
    private func show(store: AppStore, full: Bool) -> NSWindow {
        let detail = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil)
        )
        let controller = NSHostingController(
            rootView: Group {
                if full { ContentView(store: store) } else { detail }
            }
            // **Rozměr se scéně předepisuje**, jinak okno spadne na ideální výšku obsahu: diff
            // uvnitř `GeometryReader`u je pružný, takže ideální výška je hlavička plus pruh
            // záložek a v okně nezbyde ani jeden blok kódu. Měřeno: bez tohohle se okno usadilo
            // na 1512×265 a sonda hlásila nulu nad prázdnem.
            .frame(width: 1512, height: 874)
            .background(Palette.background)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 874),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        // Velikost se nastavuje **až za kontrolérem** — `contentViewController` přebije
        // `contentRect` (tatáž past jako u #350).
        window.setContentSize(NSSize(width: 1512, height: 874))
        window.setFrameOrigin(NSPoint(x: 0, y: 20))
        // Nad ostatními okny, ale bez aktivace — fokus si sonda brát nesmí (#350).
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }

    /// Store s načteným diffem. `big` přidá k fixture syntetické soubory, aby se seznam dostal na
    /// tisíce řádků; `full` přidá to, co v okně u #361 bylo — tři otevřené záložky, nálezy
    /// v diffu a konverzaci.
    private func prepared(big: Bool, full: Bool) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        var text = try Fixture.text("gh/pr-diff-ordinary.diff")
        if big { text += Self.synthetic(files: 12, hunks: 4, lines: 40) }
        let gateway = FakeGitHubGateway(
            always: .success(Self.summaries),
            detail: .success(Self.detail),
            diffs: [.success(text)],
            conversations: [.success(try Self.conversation())]
        )
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        store.noteVisit(to: pr)
        guard full else {
            store.openTab(pr)
            return (store, directory)
        }
        await store.loadConversation(for: Self.summary)
        store.reviewRecords[pr] = Self.record
        // **Seznam se musí načíst tikem**, jinak `ContentView` detail vůbec nekreslí: záložka umí
        // jen PR, který je ve frontě. Bez tohohle sonda měřila okno bez jediného bloku kódu.
        await store.refresh()
        for summary in Self.summaries { store.openTab(summary.id) }
        store.activeTab = .pullRequest(pr)
        store.selection = pr
        return (store, directory)
    }

    /// Syntetický diff k fixture. Skutečný diff z veřejného repa je malý; cena rozvržení roste
    /// s počtem řádků v seznamu, takže se počet dorovnává tímhle.
    private static func synthetic(files: Int, hunks: Int, lines: Int) -> String {
        var out = ""
        for file in 0..<files {
            let path = "src/Module\(file)/Handler\(file).swift"
            out += "diff --git a/\(path) b/\(path)\n"
            out += "index 1111111..2222222 100644\n"
            out += "--- a/\(path)\n"
            out += "+++ b/\(path)\n"
            for hunk in 0..<hunks {
                let start = 1 + hunk * (lines + 20)
                out += "@@ -\(start),\(lines) +\(start),\(lines) @@ func handle()\n"
                for line in 0..<lines {
                    switch line % 5 {
                    case 3: out += "-    return legacy(value, \(line))\n"
                    case 4: out += "+    return modern(value, \(line))\n"
                    default: out += "     let value = compute(\(line))\n"
                    }
                }
            }
        }
        return out
    }

    private static func conversation() throws -> Conversation {
        let text = try Fixture.text("gh/conversation-threads.json")
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(text.utf8))
        return try response.conversation(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)
        )
    }

    /// Nálezy **v tom diffu**, který se kreslí: cesta i řádek jsou z fixture, jinak by se bublina
    /// nezavěsila na žádný řádek a scénář „s bublinami“ by byl scénář bez nich.
    private static var record: ReviewRecord {
        ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(
                findings: [
                    makeReported(file: "CLAUDE.md", line: 174, summary: "Nález na prvním souboru."),
                    makeReported(file: "README.md", line: 68, summary: "Nález na druhém souboru."),
                    makeReported(
                        file: "src/Module3/Handler3.swift",
                        line: 5,
                        summary: "Nález v syntetické části diffu."
                    ),
                ],
                headSha: "aaaa1111"
            )]
        )
    }

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/13084")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    /// Tři PR, tedy tři otevřené záložky jako v tom okně.
    private static let summaries: [PullRequestSummary] = [
        summary,
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13085),
            title: "Add --json to pr checks",
            author: "octocat",
            url: URL(string: "https://github.com/cli/cli/pull/13085")!,
            updatedAt: Date(timeIntervalSince1970: 1_754_001_000),
            state: .open
        ),
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13086),
            title: "Fix pager handling on Windows",
            author: "hubot",
            url: URL(string: "https://github.com/cli/cli/pull/13086")!,
            updatedAt: Date(timeIntervalSince1970: 1_754_002_000),
            state: .open
        ),
    ]

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
}
