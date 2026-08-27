import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Kolik stojí **jedna událost průběhu review** v otevřeném detailu PR (#350).
///
/// Proč harness, a ne živé review: událost průběhu je jediná proměnná, která se v tom scénáři
/// hýbe, a živý běh k jejímu nasypání není potřeba — stojí dolary a jeho tempo se nedá řídit.
/// Frekvenci a tvar bere měření ze **skutečné `stream-json` fixture** (`countsRealProgressEvents`
/// níž), takže se z čísla na událost dá spočítat CPU při skutečném běhu.
///
/// **Měří se hostovaný detail, ne `ImageRenderer`.** Cena, která okno položila, je rozvržení
/// (`propagate_dirty` + `sizeThatFits` ve vzorku u #350), a to `ImageRenderer` nedělá tak, jak ho
/// dělá okno — v `ScrollView`u nerasterizuje vůbec (viz `DetailTabRenderProbe`).
///
/// Tři věci, bez kterých z toho vyjde nesmysl:
///
/// - **Příprava je mimo hodinky** (pravidlo z #274). Store, hostování ani usazení hierarchie se
///   nepočítá; do měřeného úseku patří jen nasypání události a kolo smyčky za ním.
/// - **Kontrolní série má stejný počet kol smyčky.** Samo kolo smyčky něco stojí, takže bez
///   odečtení by cena události vyšla o tu režii vyšší.
/// - **Čte se CPU hlavního vlákna, ne nástěnné hodiny.** Kolo smyčky většinu času spí; nástěnný
///   čas by měřil délku spánku.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Cena události průběhu v detailu PR (#350)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DetailProgressMeasurement {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)

    /// Kolik událostí se nasype v jedné sérii. Dost na to, aby se do průměru nevešel jeden
    /// odskok, a málo na to, aby série nad všemi sedmi taby netrvala minuty.
    private let events = 20

    // MARK: - Hlavní číslo

    @Test("Cena jedné události průběhu podle otevřeného tabu")
    func costOfOneProgressEvent() async throws {
        let (store, cache) = try await prepared()
        defer { _ = cache }
        let hosting = host(store: store)
        defer { hosting.window?.orderOut(nil) }

        print("MĚŘENÍ cena jedné události průběhu (\(events) událostí v sérii)")
        for tab in PullRequestTab.allCases {
            store.setDetailTab(tab, for: pr)
            settle(hosting)

            let idle = drive(hosting, spins: events) { _ in }
            let busy = drive(hosting, spins: events) { step in inject(step, into: store) }
            // **Kontrola, co se doopravdy platí**: `reviewPhases` je jiné pole storu, které tělo
            // detailu taky čte, a zápis do něj nedělá s časovou osou nic. Když cena vyjde stejně,
            // není to práce nad osou — je to samo **zašpinění těla**, a to je ta věc, která se má
            // opravit.
            let phases = drive(hosting, spins: events) { step in
                store.reviewPhases[pr] = .running(finished: 0, total: step % 3 + 1)
            }
            store.reviewPhases[pr] = .running(finished: 0, total: 1)
            print(String(
                format: "MĚŘENÍ %@: %.2f ms na událost, %.2f ms na jiné zašpinění těla"
                    + " (%d prvků v hierarchii, klid %.0f ms)",
                tab.czechLabel,
                max(busy - idle, 0) / Double(events) * 1000,
                max(phases - idle, 0) / Double(events) * 1000,
                Self.descendants(of: hosting),
                idle * 1000
            ))
        }
    }

    /// Jak cena roste s tím, **co je v okně**. Bez toho čísla se z harnessu nedá říct nic o okně
    /// uživatele: harness má malou scénu, skutečné okno je přes obrazovku a má rozbalený diff.
    ///
    /// Roste-li cena s výškou okna (tedy s počtem prvků, které líný seznam umístil), je z toho
    /// vidět, že se platí **velikost grafu**, ne jedna položka osy — a to je ten důvod, proč
    /// `propagate_dirty` ve vzorku u #350 sedí na vrcholu zásobníku.
    @Test("Jak cena události roste s obsahem okna")
    func costGrowsWithTheScene() async throws {
        let (store, cache) = try await prepared()
        defer { _ = cache }

        for tab in [PullRequestTab.conversation, .filesChanged] {
            for height in [600.0, 1200.0, 2400.0] as [CGFloat] {
                store.setDetailTab(tab, for: pr)
                let hosting = host(store: store, height: height)
                settle(hosting)
                let idle = drive(hosting, spins: events) { _ in }
                let busy = drive(hosting, spins: events) { step in inject(step, into: store) }
                print(String(
                    format: "MĚŘENÍ %@ ve výšce %.0f: %.2f ms na událost (%d prvků v hierarchii)",
                    tab.czechLabel,
                    height,
                    max(busy - idle, 0) / Double(events) * 1000,
                    Self.descendants(of: hosting)
                ))
                hosting.window?.orderOut(nil)
            }
        }
    }

    /// Z čeho se cena skládá: odznaky pruhu záložek se počítají **při každém průchodu tělem
    /// detailu**, protože `PullRequestTabBar` dostává jejich výpočet jako closure.
    ///
    /// Měří se ta samá trojice výrazů, jakou má `PullRequestDetailView.badge(in:)` — bez GUI, takže
    /// je z čísla vidět, kolik z ceny je počítání a kolik rozvržení.
    @Test("Kolik stojí odznaky pruhu záložek")
    func costOfTheTabBadges() async throws {
        let (store, cache) = try await prepared()
        defer { _ = cache }
        let rounds = 200

        let overview = measure(rounds) { _ = store.overview(for: pr).count { $0.isReadable } }
        let changes = measure(rounds) { _ = store.changesSinceLastVisit(for: pr).count }
        let tally = measure(rounds) {
            let findings = store.reviewRecord(for: pr)?.findings ?? []
            _ = Policy.tally(
                of: findings,
                dismissals: store.reviewRecord(for: pr)?.dismissals ?? [:],
                categories: store.resolved(for: pr.repo).blockingCategories
            )
        }
        print(String(format: "MĚŘENÍ odznak Konverzace (Policy.overview): %.3f ms", overview * 1000))
        print(String(format: "MĚŘENÍ odznak Přehled (changesSinceLastVisit): %.3f ms", changes * 1000))
        print(String(format: "MĚŘENÍ odznak Nálezy (Policy.tally): %.3f ms", tally * 1000))
    }

    /// Kolik událostí průběhu nadělá **skutečný** běh. Bez toho čísla se z ceny na událost nedá
    /// spočítat, kolik to je CPU — a odhad „nějakých pár“ by byl přesně to, co u #350 obrátilo
    /// hledání špatným směrem.
    @Test("Kolik událostí průběhu nadělá skutečná session")
    func countsRealProgressEvents() throws {
        for fixture in ["review-clean", "review-with-findings", "review-killed", "review-denied-write"] {
            let lines = TextLines.nonEmpty(try Fixture.text("stream-json/\(fixture).jsonl"))
            var summary = StreamSummary()
            var tools = 0
            var findings = 0
            for line in lines {
                let before = summary
                StreamParser().consume(String(line), into: &summary)
                tools += summary.attemptedTools.count - before.attemptedTools.count
                if summary.calledReportFindings, !before.calledReportFindings { findings += 1 }
            }
            print("MĚŘENÍ \(fixture): \(lines.count) řádků streamu → \(tools) událostí `attemptedTool`"
                + " + \(findings)× `findings`")
        }
        print("MĚŘENÍ strop uložených událostí na běh: \(ReviewerTimeline.entryLimit)")
    }

    // MARK: - Mechanika

    /// Nasype jednu událost průběhu **tou samou cestou, jakou ji zapisuje běh**
    /// (`AppStore.record(_:of:for:in:)`), ať harness neměří svoji kopii pravidla.
    ///
    /// Tvar kopíruje skutečný stream: většina událostí je pokus o nástroj, občas přijde počet
    /// nálezů. Ta proporce je z fixtures, viz `countsRealProgressEvents`.
    private func inject(_ step: Int, into store: AppStore) {
        let progress: ReviewProgress = step % 7 == 6
            ? .findings(count: step / 7)
            : .attemptedTool(ToolAttempt(name: "Read", input: ["file_path": "pkg/cmd/pr/view/view.go"]))
        store.record(progress, of: "code-review", for: pr, in: Self.worktree)
    }

    /// Projede `spins` kol smyčky a před každým udělá, co je v `work`. Vrací **CPU hlavního
    /// vlákna**, ne nástěnný čas.
    ///
    /// **Mezi událostmi se nechává čas na dokončení** (`gap`), a je to podmínka měření, ne
    /// pohodlí: události nasypané hned za sebou SwiftUI slije do jednoho průchodu, takže by
    /// cena na událost vyšla tolikrát menší, kolikrát se jich slilo. Skutečné události přicházejí
    /// po sekundách (jedna na pokus o nástroj), tedy každá si svůj průchod zaplatí celý.
    private func drive(
        _ hosting: NSHostingView<some View>,
        spins: Int,
        gap: TimeInterval = 0.25,
        work: (Int) -> Void
    ) -> TimeInterval {
        let start = mainThreadCPUSeconds()
        for step in 0..<spins {
            work(step)
            // Kolo smyčky doručí SwiftUI přeplánování, `layoutSubtreeIfNeeded` vynutí rozvržení —
            // teprve to je ta práce, kterou vzorek u #350 ukazoval.
            RunLoop.current.run(until: Date().addingTimeInterval(gap))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        return mainThreadCPUSeconds() - start
    }

    private func measure(_ rounds: Int, _ work: () -> Void) -> TimeInterval {
        let start = mainThreadCPUSeconds()
        for _ in 0..<rounds { work() }
        return (mainThreadCPUSeconds() - start) / Double(rounds)
    }

    /// Nechá hierarchii usadit — po přepnutí tabu se skládá obsah a to do měřeného úseku nepatří.
    private func settle(_ hosting: NSHostingView<some View>) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    /// Scéna do okna mimo obrazovku — tatáž cesta jako u `DetailTabRenderProbe`.
    private func host(store: AppStore, height: CGFloat = DetailProgressMeasurement.height) -> NSHostingView<some View> {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil),
            merge: .constant(nil)
        )
        .frame(width: Self.width, height: height)
        .background(Palette.background)

        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        return hosting
    }

    /// Store ve stavu, ve kterém okno u #350 stálo: načtený detail, diff, konverzace, uložené
    /// nálezy — a **běžící review**, protože jinak se pruh běhu vůbec nekreslí.
    ///
    /// Diff i konverzace jsou skutečné odpovědi z veřejných repozitářů: cena rozvržení roste
    /// s tím, co je v okně, takže vymyšlený dvouřádkový diff by měřil prázdné okno.
    private func prepared() async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let conversation = try Self.conversation()
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(try Fixture.text("gh/pr-diff-ordinary.diff"))],
            conversations: [.success(conversation)]
        )
        gateway.checks = Self.checks
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        await store.loadConversation(for: Self.summary)
        store.checks[pr] = Self.checks
        store.reviewRecords[pr] = Self.record
        store.noteVisit(to: pr)
        store.openTab(pr)
        // Běh, který „běží“: `isReviewing` se ptá jedině na tuhle mapu, takže se pruh a hodiny
        // rozjedou bez toho, aby se pouštěla session.
        store.reviewTasks[pr] = AppStore.RunningReview(task: Task {}, skills: nil)
        store.reviewPhases[pr] = .running(finished: 0, total: 1)
        store.reviewTimelines[pr] = []
        store.record(.queued, of: "code-review", for: pr, in: Self.worktree)
        store.record(.started(sessionID: "6f1c2b7a"), of: "code-review", for: pr, in: Self.worktree)
        return (store, directory)
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }

    private static let width: CGFloat = 1400
    private static let height: CGFloat = 900
    private static let worktree = URL(filePath: "/tmp/prism-350-worktree")

    private static func conversation() throws -> Conversation {
        let text = try Fixture.text("gh/conversation-threads.json")
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(text.utf8))
        return try response.conversation(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)
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
    ]

    private static var record: ReviewRecord {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: nil)
        let clock = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.queued, at: clock)
        timeline.record(.started(sessionID: "6f1c2b7a"), at: clock)
        timeline.finish(.finished, at: clock)

        let reported = (1...6).map { index in
            makeReported(
                file: "pkg/cmd/pr/view/view.go",
                line: index * 7,
                category: index.isMultiple(of: 2) ? "correctness" : "style",
                summary: "Nález číslo \(index): návratová hodnota se zahazuje, takže selhání "
                    + "zápisu vypadá v UI jako „nic tu nebylo“."
            )
        }
        return ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(findings: reported, headSha: "aaaa1111", timeline: timeline.stored())]
        )
    }
}
