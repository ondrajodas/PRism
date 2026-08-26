import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#326): vyrendruje **řádek kroku v každé podobě, jakou umí**.
///
/// Otázka je na obrázek — „pozná se pokus od hotového kroku a odmítnutí od chyby, aniž by
/// odmítnutí vypadalo jako spadlý běh?“ Čísla o tom, který stav se kdy kreslí, drží
/// `ToolStepOutcomeTests` a `ReviewerLaneTextTests`; tady se ty stavy dají **přečíst vedle sebe**
/// a srovnat se sekcí 20 návrhu.
///
/// **Od #325 rendruje i celé dráhy s výpisem kroků** — rozbalený (běžící reviewer), sbalený za
/// řádkem s počtem kroků (doběhlý) a rozbalený nad ořezanou osou, kde se zkrácení přiznává dvakrát.
/// To je ta obrazovka, kterou se srovnává sekce 20 návrhu; do #325 se výpis zvenčí otevřít nedal,
/// protože jeho rozbalení bylo `@State` uvnitř dráhy.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR`. Prefix `TEST_RUNNER_` je podmínka, ne ozdoba — `xcodebuild`
/// jinak proměnnou do testovacího procesu nepředá a suita se **tiše přeskočí**.
@MainActor
@Suite(
    "Sonda řádku kroku (#326)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ToolStepRenderProbe {
    private let worktree = URL(filePath: "/tmp/cache/worktrees/keboola/job-queue/725-c66a21")

    @Test("Vyrendrovat řádky kroků ve všech stavech")
    func rendersEveryStepState() throws {
        let directory = URL(
            filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory()
        )

        for width in [760.0, 420.0] as [CGFloat] {
            let url = directory.appending(path: "kroky-\(Int(width)).png")
            try render(scene(width: width), width: width, height: 190, to: url)
            print("SONDA \(url.path) — \(Int(width)) b")
        }
    }

    /// Dráhy s výpisem: **čerstvě spuštěná o třech krocích**, běžící s rozbaleným oknem, doběhlá
    /// sbalená a běžící nad ořezanou osou.
    ///
    /// Ta první je tam od opravy výšky (#402): okno je **obsah do stropu**, takže krátký běh má
    /// vysoké tři řádky a nemá přepínač `Sledovat konec` — a je to zrovna ten stav, ve kterém každé
    /// review začíná. Na obrázku se dá srovnat s dlouhými pod ním, kde strop platí.
    @Test("Vyrendrovat dráhy s výpisem kroků")
    func rendersLanesWithTheFeed() throws {
        let directory = URL(
            filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory()
        )

        for width in [1000.0, 620.0] as [CGFloat] {
            let url = directory.appending(path: "vypis-\(Int(width)).png")
            try render(feedScene(width: width), width: width, height: 820, to: url)
            print("SONDA \(url.path) — \(Int(width)) b")
        }
    }

    private func feedScene(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            lane(skill: "docs-review", running: true, steps: 3, expanded: true)
            lane(skill: "security-review", running: true, steps: 47, expanded: true)
            lane(skill: "php-review", running: false, steps: 312, expanded: false)
            lane(skill: "test-coverage", running: true, steps: 516, expanded: true)
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(Palette.background)
    }

    /// Dráha z **živé** osy, tedy tou cestou, kterou vzniká za běhu — včetně stropu, takže
    /// u dlouhého běhu je na obrázku vidět i přiznané zkrácení.
    private func lane(skill: String, running: Bool, steps: Int, expanded: Bool) -> some View {
        var timeline = ReviewerTimeline(skill: skill, worktree: worktree)
        let start = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.queued, at: start)
        timeline.record(.started(sessionID: "8c1f2ab3"), at: start + 1)
        for index in 0..<steps {
            let tool = Self.tools[index % Self.tools.count]
            timeline.record(
                .attemptedTool(ToolAttempt(name: tool.0, detail: tool.1(worktree), id: "t\(index)")),
                at: start + 2 + Double(index)
            )
            // Poslední krok běžící dráhy zůstane bez odpovědi — to je ten `běží…`.
            guard !running || index < steps - 1 else { continue }
            timeline.record(
                .resolvedTool(ToolResolution(
                    id: "t\(index)",
                    // Odmítá se `Bash`, jako v návrhu: `Bash(gh:*)` je to, co read-only reviewer
                    // odmítnout **má**.
                    outcome: .init(kind: tool.0 == "Bash" && index % 3 == 0 ? .denied : .passed)
                )),
                at: start + 2.2 + Double(index)
            )
        }
        if !running {
            timeline.record(.findings(count: 2), at: start + 2 + Double(steps))
            timeline.finish(.finished, usage: nil, at: start + 3 + Double(steps))
        }
        let lane = Policy.lanes(
            of: [timeline],
            skills: [skill],
            running: running ? [skill] : []
        )[0]
        return ReviewerLaneView(
            lane: lane,
            shortName: skill,
            feed: expanded ? .expanded : .collapsed,
            toggleFeed: {},
            // `Ukázat session` (#327). Sbalený řádek ho dostane taky — doběhlá dráha je ta
            // častější, takže na obrázku má být vidět v obou podobách.
            showRawSession: {},
            // `Otevřít session v Terminálu` (#453) — na obrázku je vidět vedle `⧉` v hlavičce,
            // tedy to, co kreslí sekce 34 návrhu.
            openInTerminal: {}
        )
    }

    /// Nástroje ve tvaru, v jakém chodí ze streamu — s celým prefixem pracovního stromu, aby se na
    /// obrázku vidělo, že se zkracuje.
    private static let tools: [(String, (URL) -> String)] = [
        ("Read", { $0.path(percentEncoded: false) + "/src/Client/SecretClient.php" }),
        ("Grep", { _ in "-rn \"getSecret\\|setSecret\" src tests --include=*.php" }),
        ("Bash", { "cd \"\($0.path(percentEncoded: false))\" && git log --oneline -20 -- src" }),
        ("Read", { $0.path(percentEncoded: false) + "/tests/Client/SecretClientTest.php" }),
        ("Glob", { _ in "src/**/*Secret*.php" }),
    ]

    private func scene(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { entry in
                TimelineEntryRow(entry: entry, worktree: worktree)
            }
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background(Palette.surface)
    }

    /// Osa, ve které je od každého stavu jeden krok — a k tomu událost, která krok není, aby se
    /// vidělo, že se značka lepí jen na nástroje.
    private var entries: [ReviewerTimeline.Entry] {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        let start = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.started(sessionID: "abc123"), at: start)
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Skill", detail: "code-review", id: "t1")),
            at: start
        )
        timeline.record(.resolvedTool(ToolResolution(id: "t1", outcome: .init(kind: .passed))), at: start + 0.1)
        timeline.record(
            .attemptedTool(ToolAttempt(
                name: "Read",
                detail: worktree.path(percentEncoded: false) + "/libs/api/src/PlainJob.php",
                id: "t2"
            )),
            at: start + 1
        )
        timeline.record(.resolvedTool(ToolResolution(id: "t2", outcome: .init(kind: .passed))), at: start + 1.2)
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Bash", detail: "gh pr view 412 --json reviews", id: "t3")),
            at: start + 2
        )
        timeline.record(
            .resolvedTool(ToolResolution(id: "t3", outcome: .init(
                kind: .denied,
                reason: "Claude requested permissions to use Bash, but you haven't granted it yet."
            ))),
            at: start + 2.1
        )
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Grep", detail: "-rn \"getSecret\" src tests", id: "t4")),
            at: start + 3
        )
        timeline.record(
            .resolvedTool(ToolResolution(id: "t4", outcome: .init(kind: .failed, reason: "Exit code 1"))),
            at: start + 3.4
        )
        // Poslední krok bez odpovědi — ten, který se v ose kreslí jako běžící.
        timeline.record(
            .attemptedTool(ToolAttempt(
                name: "Read",
                detail: worktree.path(percentEncoded: false) + "/libs/api/src/Cache/RequestScopedCache.php",
                id: "t5"
            )),
            at: start + 4
        )
        // A krok z osy uložené před #326: bez `id`, takže značku nemá žádnou.
        timeline.record(.attemptedTool(ToolAttempt(name: "Glob", detail: "src/**/*Secret*.php")), at: start + 5)
        return timeline.entries
    }

    private func render(_ scene: some View, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe
        // víc instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
