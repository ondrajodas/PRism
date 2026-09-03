import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#517): vyrendruje dráhu v tabu `Průběh` ve všech stavech, které přírůstek
/// přinesl — **včetně těch, ke kterým se v okně nedá dojít**, dokud nepřijde druhý push.
///
/// Proč sonda: „vejde se kapsle `přírůstek` s rozsahem do hlavičky vedle ceny?“ a „přečte se ta
/// věta o starých nálezech?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem, je
/// v `IncrementalReportTests` (souhrn a odznaky), `IncrementalReviewScopeTests` (rozhodnutí)
/// a `AppStoreIncrementalTests` (celá cesta).
///
/// Šířky odpovídají tabu `Průběh` v úzkém a v širokém okně; v úzkém se hlavička dráhy láme
/// nejdřív, takže je to ta zajímavá.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda dráhy s přírůstkem (#517)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct IncrementalLaneRenderProbe {
    private let range = IncrementalDiffRange(seen: "4f2ac91d0e", head: "9c1de02ab7")

    private enum Scenario: String, CaseIterable {
        /// Přírůstek, jak vypadá v běžném druhém kole: nový nález, staré trvají, jeden vyřešený.
        case increment = "prirustek"
        /// Přírůstek, u kterého se běh k části starých nálezů nevyjádřil.
        case unanswered = "prirustek-bez-odpovedi"
        /// Přírůstek, u kterého se **nezeptalo** — materiál se nepodařilo uložit. Jiná věta.
        case notAsked = "prirustek-neposouzeno"
        /// Přírůstek běží: kapsle a rozsah stojí, souhrn ještě není.
        case running = "prirustek-bezi"
        /// Celý diff, protože reviewer minule nedoběhl — věta o důvodu.
        case wholeAfterFailure = "cely-diff-nedobehlo"
        /// Celý diff po force pushi. Druhý z těch tří vysvětlovaných důvodů.
        case wholeAfterForcePush = "cely-diff-force-push"
        /// Dnešní stav bez přírůstku — proti čemu se to srovnává.
        case plainWhole = "cely-diff-bez-vysvetlovani"
    }

    private func lane(for scenario: Scenario) -> ReviewerLane {
        var timeline = ReviewerTimeline(skill: "php-review", worktree: URL(filePath: "/tmp/wt"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.queued, at: start)
        if let scope = scope(for: scenario) {
            timeline.record(.scope(scope), at: start + 0.5)
        }
        timeline.record(.started(sessionID: "abc123"), at: start + 1)
        for index in 0..<21 {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "src/Cart.php", id: "t\(index)")),
                at: start + 2 + Double(index)
            )
        }
        if scenario != .running {
            timeline.record(.findings(count: 1), at: start + 30)
            timeline.finish(.finished, usage: RunUsage(cost: 0.12, duration: .seconds(48), turns: 4), at: start + 31)
        }

        let lanes = Policy.lanes(
            of: [timeline],
            skills: ["php-review"],
            record: record(for: scenario),
            running: scenario == .running ? ["php-review"] : []
        )
        return lanes[0]
    }

    private func scope(for scenario: Scenario) -> ReviewScope? {
        switch scenario {
        case .increment, .unanswered, .notAsked, .running: .increment(range)
        case .wholeAfterFailure: .whole(.noFinishedRun)
        case .wholeAfterForcePush: .whole(.rewroteHistory)
        case .plainWhole: nil
        }
    }

    /// Uložený záznam po tom běhu. `nil` u běžícího — ten uložený ještě není.
    private func record(for scenario: Scenario) -> ReviewRecord? {
        let previous = [
            makeFinding(file: "src/Secret.php", line: 41, summary: "Token se loguje v plné podobě", reviewer: "php-review", headSha: range.seen),
            makeFinding(file: "src/Cart.php", line: 88, summary: "Chybí test na prázdný košík", reviewer: "php-review", headSha: range.seen),
            makeFinding(file: "src/Order.php", line: 12, summary: "Návratový typ nesedí s docblokem", reviewer: "php-review", headSha: range.seen),
        ]
        let answers: [Int: RecheckStatus.Verdict] = switch scenario {
        case .increment: [0: .stillApplies, 1: .resolved, 2: .stillApplies]
        case .unanswered: [0: .stillApplies, 1: .resolved]
        case .notAsked: [:]
        default: [:]
        }
        let increment: IncrementalReviewOutcome? = switch scenario {
        case .increment, .unanswered, .notAsked:
            IncrementalReviewOutcome(
                range: range,
                carried: Policy.carriedFindings(of: previous, by: "php-review", to: range.head),
                statuses: Policy.incrementalStatuses(
                    answers.mapValues { RecheckStatus(verdict: $0) },
                    of: previous,
                    by: "php-review"
                ),
                wholeUsage: RunUsage(cost: 0.82),
                askedForVerdicts: scenario != .notAsked
            )
        default: nil
        }
        guard scenario != .running else { return nil }
        return makeRecord(
            runs: [makeStoredRun(
                skill: "php-review",
                findings: [makeReported(file: "src/Cart.php", line: 122, summary: "Přepočet slevy nekontroluje nulové množství")],
                headSha: range.head,
                usage: RunUsage(cost: 0.12, duration: .seconds(48), turns: 4),
                increment: increment
            )],
            headSha: range.head
        )
    }

    @Test("Vyrendrovat dráhu ve všech stavech přírůstku")
    func rendersEveryState() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
            ?? NSTemporaryDirectory())
        for scenario in Scenario.allCases {
            for width in [980.0, 620.0] as [CGFloat] {
                for dark in [false, true] {
                    let name = "lane-\(scenario.rawValue)-\(Int(width))-\(dark ? "tmavy" : "svetly")"
                    let url = directory.appending(path: "\(name).png")
                    try write(scenario: scenario, width: width, dark: dark, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    /// **Barevný režim se nastavuje dvakrát**, jako u ostatních sond: `NSAppearance` kvůli paletě
    /// a `colorScheme` kvůli `.primary`/`.secondary`.
    private func write(scenario: Scenario, width: CGFloat, dark: Bool, to url: URL) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let view = ReviewerLaneView(
                    lane: lane(for: scenario),
                    shortName: "php-review",
                    feed: .none,
                    toggleFeed: {}
                )
                .padding(12)
                .frame(width: width)
                .background(Palette.background)
                .environment(\.colorScheme, dark ? .dark : .light)
                .tint(Palette.accent)

                let hosting = NSHostingView(rootView: view)
                let height = max(hosting.fittingSize.height, 90)
                hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí
                // vedle sebe víc instancí a cizí okno je poslední, co má sonda rušit.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try #require(rep.representation(using: .png, properties: [:])).write(to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }
}
