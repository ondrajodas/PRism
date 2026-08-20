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
        return try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: []).first)
    }

    @Test("Stavy mají každý vlastní slovo — spadlo a nedoběhlo se nesmí slít")
    func states() {
        let words = ReviewerLane.State.allCasesForTest.map(ReviewerLaneText.state)

        #expect(Set(words).count == words.count)
        #expect(ReviewerLaneText.state(.failed(detail: "kód 1")) == "spadlo")
        #expect(ReviewerLaneText.state(.stopped) == "nedoběhlo")
        // A `nespuštěno` se nesmí slít s `ve frontě`: první znamená „nespustilo se“, druhé
        // „review běží a tenhle čeká na slot“.
        #expect(ReviewerLaneText.state(.notStarted) == "nespuštěno")
        #expect(ReviewerLaneText.state(.queued) == "ve frontě")
    }

    /// Věta u nespuštěné dráhy nesmí tvrdit ani výsledek („nic nenašel“), ani čekání ve frontě —
    /// tenhle reviewer o kódu neřekl vůbec nic a nic se na něj nechystá.
    @Test("Nespuštěná dráha řekne, že je v sadě a ještě neběžela — a nic dalšího")
    func notStarted() throws {
        let lane = try #require(Policy.lanes(of: [], skills: ["code-review"]).first)

        let text = try #require(ReviewerLaneText.last(of: lane))

        #expect(text == "Nespustilo se — je v nastavené sadě, ale na tomhle PR ještě neběželo.")
        #expect(!text.contains("čisto"))
        #expect(!text.contains("frontě"))
    }

    /// Fáze má vlastní slovo pro každý stav — se stavem dráhy by čtečka obrazovky u všech fází
    /// přečetla totéž, tedy „doběhlo“ i nad fází, na kterou nedošlo.
    @Test("Stav fáze má vlastní slovo, různé od stavu dráhy")
    func phaseStates() {
        let states: [ReviewerLane.PhaseState] = [.done, .running, .failed, .stopped, .idle, .unknown]
        let words = states.map(ReviewerLaneText.phase)

        #expect(Set(words).count == states.count)
        #expect(ReviewerLaneText.phase(.idle) == "nedošlo na ni")
        // „Neví se“ není „nedošlo na ni“: u běhu bez uložené osy na fázi dojít mohlo.
        #expect(ReviewerLaneText.phase(.unknown) == "neví se")
        // A nesmí to být totéž co stav dráhy: „doběhlo“ patří dráze, „hotovo“ fázi.
        #expect(ReviewerLaneText.phase(.done) != ReviewerLaneText.state(.finished))
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
        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"]).first)

        #expect(ReviewerLaneText.last(of: lane) == "Právě: Read src/Cart.php")
    }

    @Test("Běžící session bez prvního kroku to řekne, místo aby mlčela")
    func runningWithoutTool() throws {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.started(sessionID: "abc"), at: clock)
        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"]).first)

        #expect(ReviewerLaneText.last(of: lane) == "Session naběhla, první krok ještě nepřišel.")
    }

    // MARK: - Příznak zadání (#345)

    private static let gaps: [IntentGap] = [
        .toolNotConfigured,
        .serverUnavailable(status: nil),
        .serverUnavailable(status: "failed"),
        .toolDenied,
        .noAnswer,
        .sessionFailed(detail: "vypršel čas"),
        .commentsUnavailable,
    ]

    /// **Každý důvod má vlastní větu**, jinak by se „nezkoušelo se“ a „nepovedlo se“ slily zpátky
    /// do jednoho — a to je celý smysl toho příznaku.
    @Test("Věty o nedotaženém zadání se od sebe liší")
    func namesEveryReason() {
        let sentences = Self.gaps.map(ReviewerLaneText.intentGap)
        let short = Self.gaps.map(ReviewerLaneText.intentGapReason)

        #expect(Set(sentences).count == Self.gaps.count)
        #expect(Set(short).count == Self.gaps.count)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }

    /// Věta **netvrdí, že je review špatné** — běželo, jen s menším zadáním. A nepředstírá, že
    /// zadání dorazilo: u každého důvodu je napsané, co reviewer doopravdy dostal, nebo proč ne.
    @Test("Věta o chybějícím nástroji nezní jako porucha")
    func doesNotCallAMissingToolAFailure() {
        let sentence = ReviewerLaneText.intentGap(.toolNotConfigured)

        #expect(sentence.contains("netahal"))
        #expect(sentence.contains("issueTextTool"))
        #expect(sentence.contains("Nic se nepokazilo"))
    }

    /// Stav serveru se do věty **propíše**, protože je to jediné, co o příčině víme. Bez něj by se
    /// `failed` a `needs-auth` nedaly rozeznat.
    ///
    /// A věta u toho **netvrdí, že se ty dva případy odlišit nedají** (nález Copilota na #388):
    /// u vypsaného stavu by si protiřečila, protože ten stav je zrovna to, čím se liší. Že je
    /// následek pro uživatele stejný, drží model (`IntentGap`), ne nápověda.
    @Test("Stav serveru je ve větě vidět a věta si neprotiřečí")
    func showsTheServerStatus() {
        #expect(ReviewerLaneText.intentGap(.serverUnavailable(status: "needs-auth")).contains("needs-auth"))
        #expect(ReviewerLaneText.intentGap(.serverUnavailable(status: nil)).contains("vůbec nebyl"))
        for status in [nil, "needs-auth", "failed"] {
            #expect(!ReviewerLaneText.intentGap(.serverUnavailable(status: status)).contains("nedá odlišit"))
        }
    }

    /// Odznak je krátký schválně: v hlavičce dráhy stojí vedle jména skillu, stavu a ceny, takže
    /// dlouhý popisek se v úzkém panelu ořeže do nesmyslu.
    @Test("Odznak je krátký a nejmenuje příčinu")
    func keepsTheBadgeShort() {
        #expect(ReviewerLaneText.intentGapLabel.count <= 20)
        #expect(!ReviewerLaneText.intentGapLabel.contains("server"))
    }
}

extension ReviewerLane.State {
    /// Výčet pro test úplnosti. **Není v produkčním kódu**: `State` nese u `failed` detail, takže
    /// `CaseIterable` se na něm nedá odvodit — a zástupná hodnota patří do testu, ne do modelu.
    static let allCasesForTest: [ReviewerLane.State] = [
        .notStarted, .missingProgress, .queued, .running, .finished, .timedOut, .interrupted,
        .failed(detail: "kód 1"), .stopped,
    ]
}
