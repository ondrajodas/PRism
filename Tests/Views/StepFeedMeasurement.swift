import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Kolik stojí **jedna událost v otevřeném výpisu kroků** (#325) — a kolik to stálo předtím.
///
/// Zadání #325 chce číslo „před i po, offscreen renderem o 300 řádcích“, jako u #275. Měří se dvě
/// věci, protože #325 mění dvě:
///
/// - **Složení drah.** Do #325 skládal `Policy.lanes` dráhu osmi průchody polem při každém
///   překreslení tabu; od #325 je čte ze souhrnu (`ReviewerTimeline.Digest`). Kontrolní strana
///   měření je ten průchod, přepsaný sem — bez něj by z čísla nebylo poznat, jestli se ubralo,
///   nebo jen přepsalo (poučení z #275).
/// - **Rozvržení výpisu.** Do #325 to byl `VStack` **všech** událostí pod rozbalením, který
///   s každou událostí narostl a posunul obsah pod sebou; od #325 je to `LazyVStack` v okně
///   o pevné výšce. Tady se měří CPU hlavního vlákna při nasypání událostí do hostovaného view,
///   tedy ta cesta, kterou kód doopravdy jde (#275).
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. **Pouští se ručně**:
/// `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Cena výpisu kroků (#325)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct StepFeedMeasurement {
    private let worktree = URL(filePath: "/tmp/cache/worktrees/keboola/job-queue/725-c66a21")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Složení drah

    @Test("Kolik stojí složení dráhy z osy o 300 událostech")
    func costOfComposingALane() {
        let timelines = [timeline(entries: 300)]
        print("SONDA \(timelines[0].entries.count) událostí v ose")

        measure("Policy.lanes ze souhrnu (#325)") {
            Policy.lanes(of: timelines, skills: ["code-review"], running: ["code-review"]).count
        }
        measure("Policy.lanes průchodem polem (do #325)") {
            timelines.reduce(0) { $0 + Self.scannedDerivations(of: $1) }
        }
    }

    /// Osm průchodů, které `Policy.lanes` dělal do #325 — přepsané tak, aby se dal změřit jejich
    /// součet a nic víc.
    private static func scannedDerivations(of timeline: ReviewerTimeline) -> Int {
        var reached = 0
        for entry in timeline.entries {
            switch entry.kind {
            case .started: reached = max(reached, 1)
            case .tool: reached = max(reached, 2)
            case .findings: reached = max(reached, 3)
            default: break
            }
        }
        let finish = timeline.entries.reversed().lazy.compactMap { entry -> Date? in
            guard case .finished = entry.kind else { return nil }
            return entry.at
        }.first
        let lastTool = timeline.entries.reversed().lazy.compactMap { entry -> ToolAttempt? in
            guard case .tool(let tool) = entry.kind else { return nil }
            return tool
        }.first
        let findings = timeline.entries.reversed().lazy.compactMap { entry -> Int? in
            guard case .findings(let count) = entry.kind else { return nil }
            return count
        }.first
        let steps = timeline.entries.count { if case .tool = $0.kind { true } else { false } }
        let queued = timeline.entries.contains { if case .queued = $0.kind { true } else { false } }
        let loaded = timeline.entries.lazy.compactMap { entry -> String? in
            guard case .tool(let tool) = entry.kind, tool.name == "Skill" else { return nil }
            return tool.detail
        }.first
        let gap = timeline.entries.lazy.compactMap { entry -> IntentGap? in
            guard case .intentGap(let value) = entry.kind else { return nil }
            return value
        }.first
        return reached + steps + (findings ?? 0) + (queued ? 1 : 0)
            + (finish == nil ? 0 : 1) + (lastTool == nil ? 0 : 1)
            + (loaded == nil ? 0 : 1) + (gap == nil ? 0 : 1)
    }

    // MARK: - Rozvržení výpisu

    /// Cena jedné události v hostovaném okně: nové okno o pevné výšce proti tomu, co tam bylo
    /// do #325 (rostoucí `VStack` všech řádků).
    ///
    /// Dvě věci z #274: **kontrolní série má stejný počet kol smyčky** (takže se od ceny odečítá
    /// samo kolo), a **série se střídají** (A/B/A/B) — drift sezení je v okně větší než hledaný
    /// rozdíl, takže dvě série za sebou by se srovnávaly s jinak vytíženým strojem.
    @Test("Cena jedné události v otevřeném výpisu")
    func costOfOneEventInTheFeed() {
        let events = 20
        let variants = [("okno o pevné výšce (#325)", false), ("rostoucí seznam (do #325)", true)]
        for (round, (label, growing)) in (variants + variants).enumerated().map({ ($0.offset / 2 + 1, $0.element) }) {
            let model = FeedModel(timeline: timeline(entries: 300))
            let hosting = host(FeedHarness(model: model, growing: growing))
            defer { hosting.window?.orderOut(nil) }
            settle(hosting)

            let idle = drive(hosting, spins: events) { _ in }
            let busy = drive(hosting, spins: events) { step in model.append(step: step) }
            print(String(
                format: "MĚŘENÍ %d. série, %@: %.2f ms na událost (%d prvků v hierarchii, klid %.0f ms)",
                round,
                label,
                max(busy - idle, 0) / Double(events) * 1000,
                Self.descendants(of: hosting),
                idle * 1000
            ))
        }
    }

    // MARK: - Materiál

    private func timeline(entries count: Int) -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        timeline.record(.queued, at: start)
        timeline.record(.started(sessionID: "abc123"), at: start + 1)
        for index in 0..<count {
            timeline.record(
                .attemptedTool(ToolAttempt(
                    name: index % 3 == 0 ? "Bash" : "Read",
                    detail: worktree.path(percentEncoded: false) + "/libs/api/src/Job\(index).php",
                    id: "t\(index)"
                )),
                at: start + 2 + Double(index)
            )
            timeline.record(
                .resolvedTool(ToolResolution(id: "t\(index)", outcome: .init(kind: .passed))),
                at: start + 2.2 + Double(index)
            )
        }
        return timeline
    }

    /// Osa, do které se za měření sype. `@Observable`, aby zašpinění šlo tou samou cestou jako
    /// ze storu.
    @Observable
    @MainActor
    final class FeedModel {
        var timeline: ReviewerTimeline

        init(timeline: ReviewerTimeline) {
            self.timeline = timeline
        }

        func append(step: Int) {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "src/Nový\(step).php", id: "n\(step)")),
                at: Date()
            )
        }
    }

    /// Scéna měření: dráha s výpisem, buď v okně (`StepFeedView`), nebo tak, jak to bylo
    /// do #325 — všechny řádky pod sebou v `VStack`u bez stropu a bez scrollu.
    private struct FeedHarness: View {
        let model: FeedModel
        let growing: Bool

        var body: some View {
            let lane = Policy.lanes(
                of: [model.timeline],
                skills: ["code-review"],
                running: ["code-review"]
            )[0]
            VStack(alignment: .leading, spacing: 0) {
                if growing {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lane.entries) { entry in
                            TimelineEntryRow(entry: entry, worktree: lane.worktree)
                        }
                    }
                } else {
                    StepFeedView(lane: lane, state: .expanded, toggle: {})
                }
            }
            .frame(width: 900, alignment: .leading)
            .background(Palette.surface)
        }
    }

    // MARK: - Mechanika (tatáž jako u `DetailProgressMeasurement`)

    private func host(_ scene: some View) -> NSHostingView<some View> {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        return hosting
    }

    private func settle(_ hosting: NSHostingView<some View>) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    /// Projede `spins` kol smyčky a před každým udělá, co je v `work`. Vrací **CPU hlavního
    /// vlákna**, ne nástěnný čas. Mezera mezi událostmi je podmínka: nasypané hned za sebou by
    /// je SwiftUI slil do jednoho průchodu.
    private func drive(
        _ hosting: NSHostingView<some View>,
        spins: Int,
        gap: TimeInterval = 0.25,
        work: (Int) -> Void
    ) -> TimeInterval {
        let start = mainThreadCPUSeconds()
        for step in 0..<spins {
            work(step)
            RunLoop.current.run(until: Date().addingTimeInterval(gap))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        return mainThreadCPUSeconds() - start
    }

    /// Hodinky bez přípravy uvnitř (#274) a s vráceným výsledkem, aby ho optimalizátor nezahodil.
    private func measure(_ label: String, iterations: Int = 200, _ body: () -> Int) {
        let clock = ContinuousClock()
        var sink = body()
        let elapsed = clock.measure {
            for _ in 0..<iterations { sink &+= body() }
        }
        print("MĚŘENÍ \(label): \((elapsed / iterations).milliseconds) na volání (kontrolní součet \(sink))")
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }
}
