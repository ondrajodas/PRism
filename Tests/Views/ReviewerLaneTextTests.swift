import Foundation
import Testing

@testable import PRism

/// Věty dráhy v tabu `Průběh` (#242).
///
/// Nejdůležitější je tady rozdíl mezi třemi doběhlými sessions: nahlásila nálezy, nahlásila
/// prázdný seznam, nebo nenahlásila nic. To poslední **není čisto** a nesmí se tak čtenáři jevit.
@Suite("Dráha revieweera — texty")
struct ReviewerLaneTextTests {
    private let clock = Date(timeIntervalSince1970: 1_000_000)

    private func lane(
        worktree: URL? = nil,
        build: (inout ReviewerTimeline) -> Void
    ) throws -> ReviewerLane {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        build(&timeline)
        return try #require(Policy.lanes(of: [timeline], running: []).first)
    }

    @Test("Stavy mají každý vlastní slovo — spadlo a nedoběhlo se nesmí slít")
    func states() {
        let words = ReviewerLane.State.allCasesForTest.map(ReviewerLaneText.state)

        #expect(Set(words).count == words.count)
        #expect(ReviewerLaneText.state(.failed(detail: "kód 1")) == "spadlo")
        #expect(ReviewerLaneText.state(.stopped) == "nedoběhlo")
    }

    @Test("Doběhlá session s nálezy je řekne v množném čísle")
    func finishedWithFindings() throws {
        let lane = try lane { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 2), at: clock)
            timeline.finish(.finished, at: clock)
        }

        #expect(ReviewerLaneText.last(of: lane) == "Doběhlo · 2 nálezy.")
    }

    @Test("Nahlášená nula je čisto")
    func finishedClean() throws {
        let lane = try lane { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 0), at: clock)
            timeline.finish(.finished, at: clock)
        }

        #expect(ReviewerLaneText.last(of: lane) == "Doběhlo a nahlásilo prázdný seznam, tedy čisto.")
    }

    /// Bez téhle věty by session, která `ReportFindings` nezavolala, vypadala v okně jako čisté
    /// review — tedy jako PR, na kterém reviewer nic nenašel.
    @Test("Session bez nahlášených nálezů to řekne a čisto neslibuje")
    func finishedWithoutReport() throws {
        let lane = try lane { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let text = try #require(ReviewerLaneText.last(of: lane))

        #expect(text.contains("nenahlásilo"))
        // Čisto se nesmí **slíbit**. Věta o něm mluvit smí, ale jen aby to popřela — proto se hlídá
        // formulace, kterou se čisto tvrdí u nahlášené nuly.
        #expect(!text.contains("tedy čisto"))
    }

    @Test("U spadlé session žádná věta není — důvod má vlastní blok")
    func failedHasNoSentence() throws {
        let lane = try lane { timeline in
            timeline.finish(.failed(detail: "kód 1"), at: clock)
        }

        #expect(ReviewerLaneText.last(of: lane) == nil)
    }

    /// Cesta v pracovním stromě začíná sedmdesáti znaky cache — v jedné větě by z ní nezbylo nic
    /// zajímavého, takže se zkracuje o strom, ve kterém běh běžel.
    @Test("Věta o běžícím kroku zkracuje cestu o pracovní strom")
    func runningShortensPath() throws {
        let worktree = URL(fileURLWithPath: "/tmp/cache/cli-cli-42")
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        timeline.record(.started(sessionID: "abc"), at: clock)
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Read", detail: "/tmp/cache/cli-cli-42/src/Cart.php")),
            at: clock
        )
        let lane = try #require(Policy.lanes(of: [timeline], running: ["code-review"]).first)

        #expect(ReviewerLaneText.last(of: lane) == "Právě: Read src/Cart.php")
    }

    @Test("Běžící session bez prvního kroku to řekne, místo aby mlčela")
    func runningWithoutTool() throws {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.started(sessionID: "abc"), at: clock)
        let lane = try #require(Policy.lanes(of: [timeline], running: ["code-review"]).first)

        #expect(ReviewerLaneText.last(of: lane) == "Session naběhla, první krok ještě nepřišel.")
    }
}

extension ReviewerLane.State {
    /// Výčet pro test úplnosti. **Není v produkčním kódu**: `State` nese u `failed` detail, takže
    /// `CaseIterable` se na něm nedá odvodit — a zástupná hodnota patří do testu, ne do modelu.
    static let allCasesForTest: [ReviewerLane.State] = [
        .queued, .running, .finished, .timedOut, .interrupted, .failed(detail: "kód 1"), .stopped,
    ]
}
