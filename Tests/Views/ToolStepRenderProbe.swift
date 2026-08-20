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
/// Rendruje se `TimelineEntryRow`, ne celá dráha: výpis kroků je v `ReviewerLaneView` pod
/// rozbalením a jeho `@State` se zvenčí otevřít nedá. Rozbalený výpis kreslí #325 — pak má
/// sonda kde vyrůst.
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
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
