import Foundation
import Testing

@testable import PRism

/// Dráhy do tabu `Průběh` (#242).
///
/// Osy se skládají **tou cestou, kterou vznikají doopravdy** (`record(_:at:)`, `finish(_:at:)`) —
/// vlastní init jen pro test by dovolil poskládat stav, do kterého se aplikace nedostane.
@Suite("Policy — dráhy reviewerů")
struct ReviewerLaneTests {
    private let clock = Date(timeIntervalSince1970: 1_000_000)

    private func timeline(
        skill: String = "code-review",
        worktree: URL? = nil,
        build: (inout ReviewerTimeline) -> Void
    ) -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: skill, worktree: worktree)
        build(&timeline)
        return timeline
    }

    // MARK: - Stav

    @Test("Doběhlá session má hotové všechny fáze, kterými prošla")
    func finished() throws {
        let timeline = timeline { timeline in
            timeline.record(.queued, at: clock)
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
            timeline.record(.findings(count: 2), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline]).first)

        #expect(lane.state == .finished)
        #expect(lane.reportedFindings == 2)
        #expect(lane.phases.map(\.title) == ["čeká na slot", "session", "prochází kód", "hlásí nálezy"])
        #expect(lane.phases.allSatisfy { $0.state == .done })
        #expect(lane.failure == nil)
    }

    /// Reviewer, který `ReportFindings` nezavolal, o kódu neřekl nic — a to **není totéž jako
    /// čisto**. Fáze `hlásí nálezy` proto zůstává nedotčená, i když běh doběhl úspěšně.
    @Test("Doběhlá session bez nahlášených nálezů nemá fázi hlášení za hotovou")
    func finishedWithoutReporting() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline]).first)

        #expect(lane.reportedFindings == nil)
        #expect(lane.phases.last?.title == "hlásí nálezy")
        #expect(lane.phases.last?.state == .idle)
    }

    @Test("Prázdný seznam nálezů je nahlášená nula, ne nic")
    func reportedZero() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 0), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline]).first)

        #expect(lane.reportedFindings == 0)
        #expect(lane.phases.last?.state == .done)
    }

    @Test("Běžící session má rozjetou tu fázi, ve které je, a zbytek nedotčený")
    func running() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline], running: ["code-review"]).first)

        #expect(lane.state == .running)
        #expect(lane.phases.map(\.state) == [.done, .running, .idle])
        #expect(lane.lastTool?.detail == "a.php")
    }

    /// `spadlo` a `nedoběhlo` se nesmí slít — první je nenulový kód, druhé zrušený běh. Fáze proto
    /// mají dva různé stavy.
    @Test("Spadlá session značí selhání v té fázi, kam se dostala, a nese stderr")
    func failed() throws {
        let timeline = timeline { timeline in
            timeline.record(.queued, at: clock)
            timeline.finish(.failed(detail: "Unknown skill: perf-review"), at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline]).first)

        #expect(lane.state == .failed(detail: "Unknown skill: perf-review"))
        #expect(lane.failure == "Unknown skill: perf-review")
        #expect(lane.phases.first { $0.title == "session" }?.state == .failed)
    }

    @Test("Zrušený běh není spadlý — nemá důvod a fáze je jen zastavená")
    func stopped() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Grep", detail: "foo")), at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline], running: []).first)

        #expect(lane.state == .stopped)
        #expect(lane.failure == nil)
        #expect(lane.phases.first { $0.title == "prochází kód" }?.state == .stopped)
    }

    @Test("Timeout a přerušení aplikací mají vlastní stav, ne selhání")
    func timedOutAndInterrupted() throws {
        for (outcome, expected) in [
            (ReviewRunOutcome.timedOut, ReviewerLane.State.timedOut),
            (.interrupted, .interrupted),
        ] {
            let timeline = timeline { timeline in
                timeline.record(.started(sessionID: "abc"), at: clock)
                timeline.finish(outcome, at: clock)
            }

            let lane = try #require(Policy.lanes(of: [timeline]).first)

            #expect(lane.state == expected)
            #expect(lane.failure == nil)
        }
    }

    // MARK: - Fronta

    @Test("Reviewer, který jen čeká na slot, má jednu fázi a nezačal")
    func queued() throws {
        let timeline = timeline { $0.record(.queued, at: clock) }

        let lane = try #require(Policy.lanes(of: [timeline], running: ["code-review"]).first)

        #expect(lane.state == .queued)
        #expect(lane.phases.count == 1)
        #expect(lane.phases.first?.title == "čeká na slot")
    }

    /// Běžící review s prázdným tabem vypadá jako porucha. Reviewer, který ještě nestihl poslat
    /// první událost, proto dostane dráhu ve frontě.
    @Test("Běžící reviewer bez osy dostane dráhu ve frontě")
    func runningWithoutTimeline() {
        let lanes = Policy.lanes(of: [], running: ["docs", "code-review"])

        #expect(lanes.map(\.skill) == ["code-review", "docs"])
        #expect(lanes.allSatisfy { $0.state == .queued })
    }

    @Test("Reviewer, který osu má, se nezdvojí")
    func noDuplicateLanes() {
        let timeline = timeline { $0.record(.started(sessionID: "abc"), at: clock) }

        let lanes = Policy.lanes(of: [timeline], running: ["code-review"])

        #expect(lanes.count == 1)
    }

    // MARK: - Podrobnosti

    @Test("Dráha nese počet kroků a osu, aby šlo rozbalit, co reviewer doopravdy dělal")
    func steps() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Grep", detail: "foo")), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline]).first)

        #expect(lane.phases.first { $0.title == "prochází kód" }?.detail == "2 kroky")
        #expect(lane.entries.count == 4)
    }

    /// Načtený jiný skill musí být vidět, jinak dráha tvrdí, že běžel nastavený (#78).
    @Test("Jiný načtený skill se hlásí, stejný se nehlásí")
    func loadedSkill() throws {
        let same = timeline { timeline in
            timeline.record(.attemptedTool(ToolAttempt(name: "Skill", detail: "code-review")), at: clock)
        }
        let other = timeline { timeline in
            timeline.record(.attemptedTool(ToolAttempt(name: "Skill", detail: "code-review:code-review")), at: clock)
        }

        #expect(try #require(Policy.lanes(of: [same]).first).loadedSkill == nil)
        #expect(try #require(Policy.lanes(of: [other]).first).loadedSkill == "code-review:code-review")
    }
}
