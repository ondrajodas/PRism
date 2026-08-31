import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #350: **kolik CPU sežere okno, ve kterém se nic nemění.**
///
/// Vzorek ze ztuhlé aplikace (`sample`, 3709 vzorků hlavního vlákna) neukázal ani jeden rámec
/// aplikace — 97 % vzorků leželo v `NSDisplayCycleFlush → NSHostingView.layout()`, tedy
/// v **rozvrhování, které se opakuje samo**. To vylučuje práci vyvolanou událostmi průběhu
/// (těch je změřeno 0,07–0,37 za sekundu) a ukazuje na něco, co si nechá překreslovat okno
/// pořád dokola, dokud review běží.
///
/// Sonda proto neměří cenu jedné změny, ale **cenu nicnedělání**: hostuje detail PR
/// v okně, nechá smyčku běžet a čte CPU hlavního vlákna. Nad zdravým oknem to má být nula.
///
/// **Okno musí být na obrazovce.** Okno mimo obrazovku nedostává takt překreslování, takže
/// v něm smyčka nenastane ani tehdy, když v aplikaci je — a sonda by tvrdila, že je čisto.
/// Proto `orderFrontRegardlessUnanimated()` (bez aktivace, ať sonda nikomu neukradne klávesnici,
/// a bez animace objevení, viz `UnanimatedWindow`) a rovnou zpátky `orderOut`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Nečinné okno při běžícím review (#350)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct IdleWindowSpinProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)

    @Test("Kolik CPU sežere nečinné okno")
    func idleWindowBurnsNoCPU() async throws {
        // Čtvrtý případ je ten, na kterém stojí celá diagnóza: **prstýnek `SpinningRing`
        // v témže hostingu jako detail**. V aplikaci sedí v pruhu záložek PR (#180), tedy nad
        // detailem a ve **stejné** hierarchii SwiftUI — a `repeatForever` z něj dělá animaci,
        // která se sama nezastaví. Sonda ho proto přidává k téže scéně, ne do vedlejšího okna.
        let cases: [(name: String, running: Bool, chips: Bool, ring: Bool, detail: Bool)] = [
            ("review neběží", false, true, false, true),
            ("review běží (kapsle reviewerů)", true, true, false, true),
            ("review běží + prstýnek v pruhu záložek", true, true, true, true),
            // Poslední případ nese celý závěr: **týž prstýnek v prázdném okně**. Vyjde-li malé číslo,
            // cena není v prstýnku, ale v tom, co je vedle něj. Co se v okně hostuje, proto stojí
            // v tabulce jako vlastní pole — odvozovat to z názvu scénáře by znamenalo, že překlep
            // v próze potichu změní, co se měří.
            ("prstýnek bez detailu", false, false, true, false),
        ]
        for scenario in cases {
            let (store, cache) = try await prepared(running: scenario.running, chips: scenario.chips)
            defer { _ = cache }
            let window = show(store: store, ring: scenario.ring, detail: scenario.detail)
            defer { window.orderOut(nil) }
            // Usadit: po prvním zobrazení se hierarchie skládá a to do měření nepatří.
            _ = spinMainRunLoop(seconds: 1.5)

            let cpu = spinMainRunLoop(seconds: 3)
            print(String(format: "MĚŘENÍ %@: %.0f %% CPU hlavního vlákna v nečinném okně",
                         scenario.name, cpu / 3 * 100))
        }
    }

    /// Že se prstýnek po převodu do CoreAnimation **doopravdy točí**, se z čísla CPU nepozná —
    /// nulové CPU je stejně dobře nehybný prstýnek. Sonda proto vydá dvě věci: **kresbu** (obrázek
    /// prstýnku v klidové poloze, na kterém se dá zkontrolovat oblouk, krytí a šířka tahu) a
    /// **otočení z prezentační vrstvy** ve třech okamžicích, které se má hýbat.
    ///
    /// `screencapture` se na to nepoužívá schválně: testovací host oprávnění k nahrávání obrazovky
    /// nemá (terminál ano, ale to je jiná aplikace), takže z něj vyjde prázdno bez chybové hlášky.
    @Test("Prstýnek: kresba a otočení v čase")
    func ringKeepsTurning() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        let controller = NSHostingController(
            rootView: SpinningRing(size: 120, lineWidth: 16)
                .padding(40)
                .background(Palette.background)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: 60, y: 60))
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 1.0)

        let ring = try #require(controller.view.firstDescendant(ofType: SpinningRingView.self))
        let url = directory.appending(path: "prsten.png")
        let rep = try #require(ring.bitmapImageRepForCachingDisplay(in: ring.bounds))
        ring.cacheDisplay(in: ring.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        print("SONDA \(url.path(percentEncoded: false)) — kresba prstýnku \(ring.bounds.size)")
        print("SONDA oblouk zabírá \(Self.arcShare(in: rep, radius: 0.43)) kruhu (čeká se 0.3)")

        for step in 1...3 {
            let turn = ring.currentTurn.map { String(format: "%.3f rad", $0) } ?? "bez prezentace"
            print("SONDA otočení \(step): \(turn)")
            _ = spinMainRunLoop(seconds: 0.2)
        }
    }

    /// Jakou část kruhu zabírá **sytý** oblouk. Očima se to spočítat nedá: tichý kruh s krytím 25 %
    /// je nad světlým pozadím pořád jasně modrý, takže „kde končí oblouk“ je otázka na pixely.
    ///
    /// Rozhoduje **krytí, ne barva.** Prstýnek se kreslí do průhledna, takže barevné složky jsou
    /// premultiplikované: tichý kruh i prázdno mají červenou blízko nuly a podle ní by prázdno
    /// vyšlo jako oblouk (změřeno: první podoba téhle sondy tvrdila 1,00 kruhu i nad opraveným
    /// prstýnkem).
    private static func arcShare(in rep: NSBitmapImageRep, radius: CGFloat) -> String {
        let width = CGFloat(rep.pixelsWide)
        let center = CGPoint(x: width / 2, y: CGFloat(rep.pixelsHigh) / 2)
        var strong = 0
        var pale = 0
        let steps = 360
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let x = Int(center.x + radius * width * cos(angle))
            let y = Int(center.y + radius * width * sin(angle))
            guard let colour = rep.colorAt(x: x, y: y) else { continue }
            if colour.alphaComponent > 0.6 { strong += 1 } else if colour.alphaComponent > 0.1 { pale += 1 }
        }
        return String(format: "%.2f (tichý kruh %.2f)",
                      Double(strong) / Double(steps),
                      Double(pale) / Double(steps))
    }

    /// Okno s detailem PR **na obrazovce**, přes `NSHostingController` — tedy tou cestou, kterou
    /// scénu hostuje i `WindowGroup` (vlastní constraints, `minSize`), ne přes pevný `frame`.
    private func show(store: AppStore, ring: Bool, detail: Bool) -> NSWindow {
        let controller = NSHostingController(
            rootView: VStack(spacing: 0) {
                if ring { SpinningRing() }
                if detail {
                    PullRequestDetailView(
                        store: store,
                        pullRequest: Self.summary,
                        submission: .constant(nil),
                        merge: .constant(nil),
                branchPush: .constant(nil)
                    )
                }
            }
            .background(Palette.background)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        // **Nad ostatními okny, ale bez aktivace.** Zakryté okno takt překreslování nedostává,
        // takže by smyčka v něm nenastala ani tehdy, když v aplikaci je — a sonda by tvrdila, že
        // je čisto. Fokus si přitom nebere: sonda nemá terminálu ani cizímu PRismu sebrat
        // klávesnici.
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return window
    }

    private func prepared(running: Bool, chips: Bool) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(try Fixture.text("gh/pr-diff-ordinary.diff"))],
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
        await store.loadConversation(for: Self.summary)
        if chips { store.reviewRecords[pr] = Self.record }
        store.noteVisit(to: pr)
        store.openTab(pr)
        store.setDetailTab(.conversation, for: pr)
        guard running else { return (store, directory) }
        store.reviewTasks[pr] = AppStore.RunningReview(task: Task {}, skills: nil)
        store.reviewPhases[pr] = .running(finished: 0, total: 1)
        store.reviewTimelines[pr] = []
        store.record(.queued, of: "code-review", for: pr, in: Self.worktree)
        store.record(.started(sessionID: "6f1c2b7a"), of: "code-review", for: pr, in: Self.worktree)
        return (store, directory)
    }

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

    private static var record: ReviewRecord {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: nil)
        let clock = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.queued, at: clock)
        timeline.record(.started(sessionID: "6f1c2b7a"), at: clock)
        timeline.finish(.finished, at: clock)
        return ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(
                findings: [makeReported(file: "pkg/cmd/pr/view/view.go", line: 26)],
                headSha: "aaaa1111",
                timeline: timeline.stored()
            )]
        )
    }
}
