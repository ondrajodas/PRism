import Foundation

/// Dráha jednoho revieweera v tabu `Průběh` (#242).
///
/// **Proč dráha a ne seznam událostí.** V panelu to byly karty pod sebou a odpověď na otázku „kdo
/// je hotový, kdo běží a kdo spadl“ se z nich musela sesbírat scrollováním. Dráha ji dává jedním
/// pohledem, protože fáze jsou u všech reviewerů na stejném místě.
///
/// **Fáze se neberou z návrhu, ale z dat.** Mockup kreslí `klon ✓ · čte diff ✓ · prochází 7
/// souborů ✓`, jenže o klonu ani o počtu souborů, které si reviewer předsevzal, session nic
/// neříká — jsou to tvrzení, která by data neunesla. Zbývají čtyři věci, které v ose doopravdy
/// jsou: čekání na slot, náběh session, kroky nad kódem a nahlášení nálezů.
struct ReviewerLane: Identifiable, Equatable, Sendable {
    /// Kde běh skončil, nebo že neskončil.
    ///
    /// `finished` **není** „něco našel“ a `failed` se s ním nesmí slít — je to tatáž hranice,
    /// kterou hlídá `ReviewRunOutcome`, jen o jednu vrstvu výš.
    enum State: Equatable, Sendable {
        /// Čeká na volný slot — nezačalo.
        case queued
        case running
        /// Doběhlo s nulovým kódem.
        case finished
        case timedOut
        /// Skončilo s aplikací (#97).
        case interrupted
        /// Nespustilo se nebo skončilo nenulovým kódem; `detail` je stderr.
        case failed(detail: String)
        /// V ose něco je, konec v ní není a nic neběží — zrušený běh.
        case stopped
    }

    /// Jak dráha stojí v jedné fázi.
    ///
    /// `stopped` je zvlášť od `failed` schválně: „nedoběhlo, protože jsem to zrušil“ a „spadlo“
    /// vedou jinam, a odznak selhání nad zrušeným během by tvrdil nepravdu.
    enum PhaseState: Equatable, Sendable {
        case done
        case running
        case failed
        case stopped
        /// Nedošlo na ni.
        case idle
    }

    struct Phase: Hashable, Sendable {
        let title: String
        /// Co se v té fázi stalo — počet kroků, počet nálezů. `nil` = není co dodat.
        let detail: String?
        let state: PhaseState
    }

    let skill: String
    let state: State
    /// Nikdy prázdné — i běh, který jen čeká na slot, má jednu fázi.
    let phases: [Phase]
    /// Poslední pokus o nástroj — z něj se skládá věta „právě čte…“.
    let lastTool: ToolAttempt?
    let finishedAt: Date?
    /// Kolik nálezů reviewer nahlásil. **`nil` = nenahlásil nic, ani prázdný seznam** — což není
    /// totéž jako nula a nesmí se to slít; přesně tohle rozlišení dělá z „čisto“ tvrzení, které
    /// data unesou.
    let reportedFindings: Int?
    let usage: RunUsage?
    let sessionID: String?
    let worktree: URL?
    let droppedEntries: Int
    /// Skill, který si session doopravdy načetla, když je jiný než nastavený. `nil` = sedí.
    let loadedSkill: String?
    /// Celá osa. Dráha ji nese, aby view mělo **jeden** vstup — jinak by si lane a osu muselo
    /// párovat podle jména skillu a při přejmenování by se tiše rozešly.
    let entries: [ReviewerTimeline.Entry]

    var id: String { skill }

    /// Proč to spadlo. `nil` u všeho, co nespadlo — chybová hláška u zrušeného běhu je text,
    /// který tvrdí víc, než data unesou.
    var failure: String? {
        guard case .failed(let detail) = state else { return nil }
        return detail
    }
}

extension Policy {
    /// Dráhy do tabu `Průběh`, v pořadí, v jakém přišly osy.
    ///
    /// - Parameter running: reviewery, které právě běží. Ty, které osu ještě nemají, dostanou
    ///   dráhu ve stavu `queued` — bez toho by běžící review ukazovalo prázdný tab, tedy přesně
    ///   ten stav, který vypadá jako porucha.
    static func lanes(
        of timelines: [ReviewerTimeline],
        running: Set<String> = []
    ) -> [ReviewerLane] {
        let known = Set(timelines.map(\.skill))
        return timelines.map { lane(of: $0, isRunning: running.contains($0.skill)) }
            + running.subtracting(known).sorted().map(queuedLane(of:))
    }

    private static func queuedLane(of skill: String) -> ReviewerLane {
        ReviewerLane(
            skill: skill,
            state: .queued,
            phases: [ReviewerLane.Phase(title: "čeká na slot", detail: nil, state: .running)],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            entries: []
        )
    }

    private static func lane(of timeline: ReviewerTimeline, isRunning: Bool) -> ReviewerLane {
        let reached = reachedStage(in: timeline)
        let state = laneState(of: timeline, isRunning: isRunning, reached: reached)
        return ReviewerLane(
            skill: timeline.skill,
            state: state,
            phases: state == .queued
                ? [ReviewerLane.Phase(title: "čeká na slot", detail: nil, state: .running)]
                : phases(of: timeline, state: state, reached: reached),
            lastTool: lastTool(in: timeline),
            finishedAt: finishTime(in: timeline),
            reportedFindings: reportedFindings(in: timeline),
            usage: timeline.usage,
            sessionID: timeline.sessionID,
            worktree: timeline.worktree,
            droppedEntries: timeline.droppedEntries,
            loadedSkill: timeline.loadedADifferentSkill ? timeline.loadedSkill : nil,
            entries: timeline.entries
        )
    }

    /// Kam se běh dostal. Fáze se z toho odvozují **jedním** číslem, aby nemohly být v rozporu —
    /// „hlásí nálezy hotovo“ nad „session ještě nenaběhla“ je stav, který by se jinak dal napsat.
    private static func reachedStage(in timeline: ReviewerTimeline) -> Int {
        var reached = 0
        for entry in timeline.entries {
            switch entry.kind {
            case .queued: break
            case .started: reached = max(reached, 1)
            case .tool: reached = max(reached, 2)
            case .findings: reached = max(reached, 3)
            case .finished: break
            }
        }
        return reached
    }

    private static func laneState(
        of timeline: ReviewerTimeline,
        isRunning: Bool,
        reached: Int
    ) -> ReviewerLane.State {
        for entry in timeline.entries.reversed() {
            guard case .finished(let outcome) = entry.kind else { continue }
            return switch outcome {
            case .finished: .finished
            case .timedOut: .timedOut
            case .interrupted: .interrupted
            case .failed(let detail): .failed(detail: detail)
            }
        }
        if isRunning { return reached == 0 ? .queued : .running }
        // Bez konce a bez běhu: buď se na slot nikdy nedostalo, nebo běh někdo zrušil.
        return reached == 0 ? .queued : .stopped
    }

    private static func phases(
        of timeline: ReviewerTimeline,
        state: ReviewerLane.State,
        reached: Int
    ) -> [ReviewerLane.Phase] {
        let steps = timeline.entries.count { if case .tool = $0.kind { true } else { false } }
        let findings = reportedFindings(in: timeline)
        // Fáze, která nese konec běhu. U špatného konce je to **aspoň `session`**, i když se běh
        // nikam nedostal: session, která spadla při startu, jinak nemá kde selhat a dráha by
        // vypadala k nerozeznání od té, co ještě nezačala.
        let marked = switch state {
        case .failed, .stopped, .timedOut, .interrupted: max(reached, 1)
        case .running, .finished, .queued: reached
        }

        var phases: [ReviewerLane.Phase] = []
        if timeline.entries.contains(where: { if case .queued = $0.kind { true } else { false } }) {
            phases.append(ReviewerLane.Phase(title: "čeká na slot", detail: nil, state: .done))
        }
        phases.append(ReviewerLane.Phase(
            title: "session",
            detail: nil,
            state: phaseState(of: 1, marked: marked, lane: state)
        ))
        phases.append(ReviewerLane.Phase(
            title: "prochází kód",
            detail: steps > 0 ? Plural.czech(steps, one: "krok", few: "kroky", many: "kroků") : nil,
            state: phaseState(of: 2, marked: marked, lane: state)
        ))
        phases.append(ReviewerLane.Phase(
            title: "hlásí nálezy",
            // **Jen číslo, bez slova**: chip je na skloňované „2 nálezy“ v nejmenším okně krátký
            // a ořezané `hlásí… 2 nál…` neřekne nic (změřeno offscreen renderem na 620 bodech).
            // Za popiskem `hlásí nálezy` je číslo jednoznačné a plná věta je pod dráhou.
            detail: findings.map { "\($0)" },
            state: phaseState(of: 3, marked: marked, lane: state)
        ))
        return phases
    }

    /// Stav jedné fáze.
    ///
    /// Fáze **za** tou, kam se běh dostal, zůstává `idle` i u doběhlého běhu — reviewer, který
    /// skončil bez zavolání `ReportFindings`, nálezy nenahlásil, a `hotovo` u téhle fáze by
    /// tvrdilo, že nahlásil prázdný seznam. To je ta záměna, kvůli které tenhle tab vzniká.
    private static func phaseState(
        of stage: Int,
        marked: Int,
        lane: ReviewerLane.State
    ) -> ReviewerLane.PhaseState {
        if stage < marked { return .done }
        if stage > marked { return .idle }
        return switch lane {
        case .running: .running
        case .failed: .failed
        case .timedOut, .interrupted, .stopped: .stopped
        case .finished, .queued: .done
        }
    }

    private static func lastTool(in timeline: ReviewerTimeline) -> ToolAttempt? {
        timeline.entries.reversed().lazy.compactMap { entry -> ToolAttempt? in
            guard case .tool(let tool) = entry.kind else { return nil }
            return tool
        }.first
    }

    private static func reportedFindings(in timeline: ReviewerTimeline) -> Int? {
        timeline.entries.reversed().lazy.compactMap { entry -> Int? in
            guard case .findings(let count) = entry.kind else { return nil }
            return count
        }.first
    }

    private static func finishTime(in timeline: ReviewerTimeline) -> Date? {
        timeline.entries.reversed().lazy.compactMap { entry -> Date? in
            guard case .finished = entry.kind else { return nil }
            return entry.at
        }.first
    }
}
