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

    /// Uložený běh **bez osy** — tak vypadají soubory z doby před #203.
    private func storedRun(_ skill: String, findings: Int = 0) -> StoredReviewRun {
        var summary = StreamSummary()
        summary.calledReportFindings = true
        summary.findings = (0..<findings).map {
            ReportedFinding(
                file: "App/Main.swift",
                line: $0 + 1,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "nález \($0)",
                failureScenario: nil
            )
        }
        return StoredReviewRun(
            ReviewRun(
                key: ReviewRunKey(pullRequest: PRIdentifier("cli/cli#1")!, headSha: "abc", skillID: skill),
                summary: summary,
                outcome: .finished
            ),
            finishedAt: clock
        )
    }

    private func record(_ runs: [StoredReviewRun]) -> ReviewRecord {
        ReviewRecord(pullRequest: PRIdentifier("cli/cli#1")!, headSha: "abc", runs: runs)
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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

        #expect(lane.reportedFindings == 0)
        #expect(lane.phases.last?.state == .done)
    }

    @Test("Běžící session má rozjetou tu fázi, ve které je, a zbytek nedotčený")
    func running() throws {
        let timeline = timeline { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"]).first)

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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: []).first)

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

            let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

            #expect(lane.state == expected)
            #expect(lane.failure == nil)
        }
    }

    // MARK: - Fronta

    @Test("Reviewer, který jen čeká na slot, má jednu fázi a nezačal")
    func queued() throws {
        let timeline = timeline { $0.record(.queued, at: clock) }

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"]).first)

        #expect(lane.state == .queued)
        #expect(lane.phases.count == 1)
        #expect(lane.phases.first?.title == "čeká na slot")
    }

    /// Běžící review s prázdným tabem vypadá jako porucha. Reviewer, který ještě nestihl poslat
    /// první událost, proto dostane dráhu ve frontě.
    @Test("Běžící reviewer bez osy dostane dráhu ve frontě")
    func runningWithoutTimeline() {
        let lanes = Policy.lanes(of: [], skills: ["code-review", "docs"], running: ["docs", "code-review"])

        #expect(lanes.map(\.skill) == ["code-review", "docs"])
        #expect(lanes.allSatisfy { $0.state == .queued })
    }

    // MARK: - Nastavená sada

    /// Tab odpovídá na „kde je které z **mých** review“, takže nastavený reviewer dráhu dostane,
    /// i když na tomhle PR nikdy neběžel. Bez toho je „ještě nezačalo“ k nerozeznání od „takový
    /// reviewer neexistuje“ — a před prvním review je celý tab prázdný.
    @Test("Nastavený reviewer, který neběžel, dostane dráhu ve stavu nespuštěno")
    func notStarted() throws {
        let lanes = Policy.lanes(of: [], skills: ["code-review:code-review", "security-review"])

        #expect(lanes.map(\.skill) == ["code-review:code-review", "security-review"])
        #expect(lanes.allSatisfy { $0.state == .notStarted })
        #expect(lanes.allSatisfy { $0.isConfigured })
        // Nespuštěno **není** čekání ve frontě: nic neběží, takže se na nic nečeká.
        #expect(lanes.allSatisfy { $0.state != .queued })

        let lane = try #require(lanes.first)
        // Invariant „nikdy prázdné“ platí i tady, a jsou to fáze každého běhu — ne plán a ne
        // čekání na slot, na který se nikdy nečekalo.
        #expect(lane.phases.map(\.title) == ["session", "prochází kód", "hlásí nálezy"])
        #expect(lane.phases.allSatisfy { $0.state == .idle })
        #expect(lane.entries.isEmpty)
        #expect(lane.reportedFindings == nil)
        #expect(lane.failure == nil)
    }

    /// Přejmenovaný nebo odebraný skill nesmí osu zahodit — jeho nálezy v záznamu jsou a v tabu
    /// `Nálezy` je vidět, takže dráha, ze které se vzaly, musí zůstat. Jen musí být poznat, že
    /// není z dnešního nastavení.
    @Test("Počet drah je nastavení plus záznamy; osa po skillu mimo sadu zůstane označená")
    func configuredPlusRecorded() throws {
        let old = timeline(skill: "code-review") { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 3), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lanes = Policy.lanes(of: [old], skills: ["code-review:code-review", "security-review"])

        #expect(lanes.map(\.skill) == ["code-review:code-review", "security-review", "code-review"])
        // Osa doběhlého běhu zůstala celá — stav i počet nálezů.
        let dropped = try #require(lanes.last)
        #expect(dropped.state == .finished)
        #expect(dropped.reportedFindings == 3)
        #expect(dropped.isConfigured == false)
        // A nastavené dráhy se tím nezmátly.
        #expect(lanes.prefix(2).allSatisfy { $0.state == .notStarted && $0.isConfigured })
    }

    /// Přeskakující dráhy jsou horší než špatné pořadí: fáze u všech drah na stejném místě jsou
    /// jediný důvod, proč tab vypadá takhle. `Set` sám žádné pořadí nemá, takže se běžící bez osy
    /// musí doplnit abecedně.
    @Test("Pořadí drah je mezi tiky stabilní — sada dává pořadí, běžící bez osy jdou abecedně")
    func stableOrder() {
        let second = timeline(skill: "security-review") { $0.record(.started(sessionID: "s"), at: clock) }
        let first = timeline(skill: "code-review:code-review") { $0.record(.started(sessionID: "c"), at: clock) }

        // Osy přišly v obráceném pořadí, než je sada — rozhoduje sada.
        let ordered = Policy.lanes(
            of: [second, first],
            skills: ["code-review:code-review", "security-review"],
            running: ["security-review", "code-review:code-review"]
        )
        #expect(ordered.map(\.skill) == ["code-review:code-review", "security-review"])

        // A co v sadě ani v osách není, jde abecedně, ne v pořadí iterace `Set`u.
        for running in [Set(["zeta", "alfa"]), Set(["alfa", "zeta"])] {
            #expect(Policy.lanes(of: [], skills: [], running: running).map(\.skill) == ["alfa", "zeta"])
        }
    }

    /// `ReviewerLane.id` je jméno skillu, takže dvě stejná by `ForEach`i daly dvě položky s jednou
    /// identitou — a SwiftUI by kreslil jednu.
    @Test("Zdvojený skill v nastavení dá jednu dráhu")
    func duplicateSkill() {
        let lanes = Policy.lanes(of: [], skills: ["code-review", "code-review"])

        #expect(lanes.count == 1)
    }

    /// Prázdno v tabu zbývá **jen** na repo bez nastaveného skillu — a právě proto o tom prázdný
    /// stav mluví jako o nastavení, ne jako o tom, že se „zatím nic nedělo“.
    @Test("Prázdné dráhy zbydou jedině u prázdné sady bez záznamu")
    func emptyOnlyWithoutSkills() {
        #expect(Policy.lanes(of: [], skills: []).isEmpty)
        #expect(!Policy.lanes(of: [], skills: ["code-review"]).isEmpty)
    }

    // MARK: - Běh bez uložené osy

    /// Uložený běh z doby před #203 osu nemá (změřeno: 25 z 31 běhů ve skutečné cache). `nespuštěno`
    /// by o něm lhalo — chip nad tabem u něj ukazuje `doběhlo` a nálezy v tabu `Nálezy` jsou.
    @Test("Doběhlý běh bez uložené osy není nespuštěný — má vlastní stav")
    func missingProgress() throws {
        let lanes = Policy.lanes(
            of: [],
            skills: ["code-review:code-review", "security-review"],
            record: record([storedRun("code-review:code-review", findings: 3)])
        )

        #expect(lanes.map(\.skill) == ["code-review:code-review", "security-review"])
        let ran = try #require(lanes.first)
        #expect(ran.state == .missingProgress)
        #expect(ran.state != .notStarted)
        #expect(ran.isConfigured)
        // Jedna kapsle, jako u čekání ve frontě: příběh fází se tady vyprávět nedá. A `unknown`,
        // ne `idle` — „nedošlo na ni“ by o proběhlém běhu tvrdilo nepravdu.
        #expect(ran.phases.map(\.title) == ["průběh se neuložil"])
        #expect(ran.phases.allSatisfy { $0.state == .unknown })
        #expect(ran.failure == nil)
        // A ten druhý, který doopravdy neběžel, zůstává nespuštěný.
        #expect(lanes.last?.state == .notStarted)
    }

    /// Uložená osa přebíjí: běh, který ji má, dostane plnou dráhu, ne „bez průběhu“.
    @Test("Běh s uloženou osou dráhu bez průběhu nedostane")
    func recordWithTimelineKeepsTheLane() throws {
        let saved = timeline(skill: "code-review") { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 1), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lanes = Policy.lanes(
            of: [saved],
            skills: ["code-review"],
            record: record([storedRun("code-review", findings: 1)])
        )

        #expect(lanes.count == 1)
        #expect(lanes.first?.state == .finished)
    }

    /// Dvě místa, jedna odpověď na „koho se to na tomhle PR týká“. Kdyby se rozešla, tvrdil by chip
    /// `doběhlo` nad reviewerem, který v tabu `Průběh` vůbec není — a rozejde se to potichu.
    @Test("Dráhy vypisují tytéž reviewery jako chipy v pruhu běhu")
    func lanesMatchChips() {
        let skills = ["code-review:code-review", "security-review"]
        let stored = record([
            storedRun("code-review:code-review", findings: 2),
            // Skill, který v sadě už není — chip ho přidává na konec, dráha musí taky.
            storedRun("php-review", findings: 1),
        ])
        let running: Set<String> = ["security-review"]

        let lanes = Policy.lanes(of: [], skills: skills, record: stored, running: running)
        let chips = Policy.chips(for: stored, skills: skills, running: running)

        #expect(lanes.map(\.skill) == chips.map(\.skill))
        // A `isConfigured` sedí s tím, co je v sadě.
        #expect(lanes.map(\.isConfigured) == [true, true, false])
    }

    @Test("Reviewer, který osu má, se nezdvojí")
    func noDuplicateLanes() {
        let timeline = timeline { $0.record(.started(sessionID: "abc"), at: clock) }

        let lanes = Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"])

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

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

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

        #expect(try #require(Policy.lanes(of: [same], skills: ["code-review"]).first).loadedSkill == nil)
        #expect(try #require(Policy.lanes(of: [other], skills: ["code-review"]).first).loadedSkill == "code-review:code-review")
    }

    // MARK: - Příznak zadání (#345)

    /// Příznak jde na dráhu, ale **fáze neposouvá**: přišel dřív, než se cokoli spustilo, a fáze
    /// popisují běh. Kdyby posouval, dráha ve frontě by tvrdila, že už něco dělá.
    @Test("Příznak zadání je na dráze a fáze neposouvá")
    func carriesTheIntentGapWithoutMovingThePhases() throws {
        let onlyGap = timeline { timeline in
            timeline.record(.intentGap(.toolDenied), at: clock)
        }

        let lane = try #require(Policy.lanes(of: [onlyGap], skills: ["code-review"], running: ["code-review"]).first)

        #expect(lane.intentGap == .toolDenied)
        // Nic se nespustilo, takže dráha čeká na slot — stejně jako by čekala bez příznaku.
        #expect(lane.state == .queued)
        #expect(lane.phases.map(\.title) == ["čeká na slot"])
    }

    /// Doběhlý běh s příznakem má fáze **hotové**: zadání nebylo celé, ale běh proběhl celý.
    @Test("Příznak zadání doběhlou dráhu nezhorší")
    func doesNotDowngradeAFinishedLane() throws {
        let timeline = timeline { timeline in
            timeline.record(.intentGap(.noAnswer), at: clock)
            timeline.record(.queued, at: clock)
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php")), at: clock)
            timeline.record(.findings(count: 0), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lane = try #require(Policy.lanes(of: [timeline], skills: ["code-review"]).first)

        #expect(lane.intentGap == .noAnswer)
        #expect(lane.state == .finished)
        #expect(lane.phases.allSatisfy { $0.state == .done })
        // Příznak se **nepočítá za krok nad kódem** — jinak by dráha tvrdila o jeden krok víc.
        #expect(lane.phases.first { $0.title == "prochází kód" }?.detail == "1 krok")
    }

    /// **U syntetických drah je příznak `nil`**: dráha bez osy o zadání nic neví, takže o něm nic
    /// netvrdí. Vymyšlené „zadání dostal celé“ by bylo tvrzení, které data neunesou.
    @Test("Dráhy bez osy o zadání netvrdí nic")
    func syntheticLanesCarryNoGap() {
        let notStarted = Policy.lanes(of: [], skills: ["code-review"])
        let queued = Policy.lanes(of: [], skills: ["code-review"], running: ["code-review"])
        let missing = Policy.lanes(of: [], skills: ["code-review"], record: record([storedRun("code-review")]))

        #expect(notStarted.map(\.state) == [.notStarted])
        #expect(queued.map(\.state) == [.queued])
        #expect(missing.map(\.state) == [.missingProgress])
        #expect((notStarted + queued + missing).allSatisfy { $0.intentGap == nil })
    }

    // MARK: - Routing (#518)

    /// Přeskočená dráha má **jednu** fázi, ne tři vyšisované jako `nespuštěno`: rozhodlo se, že
    /// tady tenhle reviewer běžet nemá, takže tvar běhu předstírat nemá co. A netvrdí nic o ceně
    /// ani o nálezech — session se nespustila.
    @Test("Přeskočená dráha má jednu fázi a nic netvrdí o výsledku")
    func skippedLane() throws {
        let lanes = Policy.lanes(
            of: [],
            skills: ["php-review", "security-review"],
            skipped: ["security-review": ["src/Auth/**"]]
        )

        #expect(lanes.map(\.skill) == ["php-review", "security-review"])
        #expect(lanes.first?.state == .notStarted)
        let skipped = try #require(lanes.last)
        #expect(skipped.state == .skipped(patterns: ["src/Auth/**"]))
        #expect(skipped.phases.map(\.title) == [ReviewerLane.Title.routed])
        #expect(skipped.phases.map(\.state) == [.idle])
        #expect(skipped.reportedFindings == nil)
        #expect(skipped.usage == nil)
        #expect(skipped.sessionID == nil)
        #expect(skipped.intentGap == nil)
        #expect(skipped.increment == nil)
    }

    /// Osa přebíjí přeskočení: reviewer, který v tomhle sezení běžel, má dráhu z osy — jinak by
    /// `Pustit přesto` doběhlo a dráha by dál tvrdila, že se nepustilo nic.
    @Test("Osa přebíjí přeskočení")
    func aTimelineWinsOverASkip() throws {
        let saved = timeline(skill: "security-review") { timeline in
            timeline.record(.started(sessionID: "abc"), at: clock)
            timeline.record(.findings(count: 0), at: clock)
            timeline.finish(.finished, at: clock)
        }

        let lanes = Policy.lanes(
            of: [saved],
            skills: ["security-review"],
            skipped: ["security-review": ["src/Auth/**"]]
        )

        #expect(lanes.map(\.state) == [.finished])
    }
}
