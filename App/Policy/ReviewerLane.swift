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
        /// Je v nastavené sadě, ale na tomhle PR ještě neběžel (#242).
        ///
        /// **Není to `queued`** a slít se to nesmí: `queued` znamená „review běží a tenhle čeká na
        /// volný slot“, tohle „nespustilo se vůbec“. Je to tatáž hranice, jakou `CLAUDE.md` hlídá
        /// u `čisté` vs. `failed` — jeden z nich je stav běhu, druhý jeho absence. Stejný fakt
        /// pojmenovává `ReviewerChip.State.notStarted`, proto stejné jméno.
        case notStarted
        /// Běh v záznamu **je**, ale jeho osa ne (#242). Tak vypadají soubory z doby před #203.
        ///
        /// Třetí stav, který se nesmí slít s předchozími dvěma: `nespuštěno` by o doběhlém běhu
        /// lhalo (změřeno na skutečné cache — 25 z 31 uložených běhů osu nemá, mezi nimi PR ve
        /// frontě) a vynechat dráhu úplně je horší: tab by vypsal zrovna ty reviewery, které
        /// **ne**běžely, a ten jeden, který běžel, by v něm chyběl.
        case missingProgress
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
        /// Neví se — běh proběhl, ale jeho osa se neuložila (#242).
        ///
        /// Zvlášť od `idle`: „nedošlo na ni“ je tvrzení o běhu, tohle o tom, co o něm víme. Čtečka
        /// obrazovky čte stav fáze, takže by `idle` přečetlo nepravdu.
        case unknown
    }

    struct Phase: Hashable, Sendable {
        let title: String
        /// Co se v té fázi stalo — počet kroků, počet nálezů. `nil` = není co dodat.
        let detail: String?
        let state: PhaseState
    }

    /// Popisky fází na jednom místě. Skládají je čtyři různá místa (osa, nespuštěná dráha, dráha bez
    /// průběhu, poměr šířky ve view) a literál na každém z nich znamená, že se přejmenováním jednoho
    /// tiše rozejdou — `prochází kód` je navíc to, podle čeho `ReviewerLaneView` pozná nejširší
    /// kapsli.
    enum Title {
        static let waiting = "čeká na slot"
        static let session = "session"
        static let code = "prochází kód"
        static let findings = "hlásí nálezy"
        static let missing = "průběh se neuložil"
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
    /// Je skill v **dnešní** nastavené sadě pro repo? `false` u osy po skillu, který se z nastavení
    /// odebral nebo přejmenoval (#242).
    ///
    /// Dráha nezmizí — to by zahodilo doběhlé review, které v záznamu je a jehož nálezy jsou
    /// v tabu `Nálezy` vidět. Musí ale být poznat, že není z dnešního nastavení, jinak by tab
    /// tvrdil, že tenhle reviewer patří do sady, ze které se review pouští.
    let isConfigured: Bool

    var id: String { skill }

    /// Proč to spadlo. `nil` u všeho, co nespadlo — chybová hláška u zrušeného běhu je text,
    /// který tvrdí víc, než data unesou.
    var failure: String? {
        guard case .failed(let detail) = state else { return nil }
        return detail
    }
}

extension Policy {
    /// Dráhy do tabu `Průběh` — na každého revieweera jedna.
    ///
    /// Skládají se ze **čtyř** zdrojů: nastavená sada, zaznamenané osy, běhy z uloženého záznamu
    /// a reviewery, které právě běží. Tab odpovídá na otázku „kde je které z **mých** review“, takže
    /// nastavená sada je ten hlavní — bez ní by dráhu dostal jen ten, kdo už někdy běžel, a před
    /// prvním review by byl celý tab prázdný. „Ještě nezačalo“ je taky odpověď a od „takový reviewer
    /// neexistuje“ se musí dát rozeznat.
    ///
    /// **Vypisuje tytéž reviewery jako chipy v pruhu běhu** (`Policy.chips`) — sada plus to, co po
    /// sobě nechal uložený běh. Dvě různé odpovědi na „koho se to na tomhle PR týká“ by znamenaly,
    /// že chip tvrdí `doběhlo` nad reviewerem, který v tabu vůbec není; je na to test.
    ///
    /// - Parameters:
    ///   - skills: nastavená sada pro repo, **v jejím pořadí**. Bere se z `AppStore.reviewSkills(for:)`,
    ///     tedy z téhož místa, ze kterého se review pouští — dvě různá by znamenala, že tab slibuje
    ///     jinou sadu, než jaká se spustí.
    ///   - record: uložený záznam. Rozhoduje o tom, jestli je „bez osy“ **nespuštěný** běh, nebo
    ///     doběhlý, jehož průběh se neuložil (`missingProgress`) — bez něj by tab o doběhlém běhu
    ///     tvrdil, že se nespustil. `nil` = na tomhle PR nic uloženého není.
    ///   - running: reviewery, které právě běží. Ty, které osu ještě nemají, dostanou dráhu ve
    ///     stavu `queued` — bez toho by běžící review ukazovalo prázdný tab, tedy přesně ten stav,
    ///     který vypadá jako porucha.
    static func lanes(
        of timelines: [ReviewerTimeline],
        skills: [String],
        record: ReviewRecord? = nil,
        running: Set<String> = []
    ) -> [ReviewerLane] {
        let configured = Set(skills)
        let recorded = record?.runs.map(\.skillID) ?? []
        let hasRun = Set(recorded)
        // Slovníkem, ne `first(where:)` v cyklu: tenhle kód běží při každém překreslení tabu.
        let bySkill = Dictionary(timelines.map { ($0.skill, $0) }, uniquingKeysWith: { first, _ in first })

        return order(skills: skills, timelines: timelines, recorded: recorded, running: running).map { skill in
            let isConfigured = configured.contains(skill)
            if let timeline = bySkill[skill] {
                return lane(of: timeline, isRunning: running.contains(skill), isConfigured: isConfigured)
            }
            if running.contains(skill) { return queuedLane(of: skill, isConfigured: isConfigured) }
            if hasRun.contains(skill) { return missingProgressLane(of: skill, isConfigured: isConfigured) }
            return notStartedLane(of: skill, isConfigured: isConfigured)
        }
    }

    /// V jakém pořadí dráhy stojí. **Stabilní mezi tiky, a to je podmínka**: přeskakující dráhy se
    /// nedají porovnat, a porovnání je jediný důvod, proč fáze stojí vedle sebe.
    ///
    /// Pořadí drží nastavená sada; co v ní není, jde za ní v pořadí, ve kterém přišly osy a za nimi
    /// běhy v záznamu (tedy stejně jako u chipů), a běžící bez obojího **abecedně** — `Set` žádné
    /// pořadí nemá, takže by jeho iterace dráhy mezi dvěma překreslením zpřeházela.
    ///
    /// Zdvojený skill dá **jednu** dráhu: `ReviewerLane.id` je jméno skillu, takže dvě stejná by
    /// `ForEach`i daly dvě položky s jednou identitou.
    private static func order(
        skills: [String],
        timelines: [ReviewerTimeline],
        recorded: [String],
        running: Set<String>
    ) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for skill in skills + timelines.map(\.skill) + recorded + running.sorted() where !seen.contains(skill) {
            seen.insert(skill)
            ordered.append(skill)
        }
        return ordered
    }

    /// Nastavený reviewer, na kterém se na tomhle PR ještě nic nedělo.
    ///
    /// **Tři fáze, všechny `idle`** — ne jedna souhrnná kapsle „nespuštěno“. Fáze nejsou plán, ale
    /// tvar, který má každý běh (náběh session → kroky nad kódem → nahlášení nálezů), a `idle`
    /// znamená doslova „nedošlo na ni“; nic navíc se tím netvrdí. Jedna široká kapsle by proti tomu
    /// rozbila rastr, ve kterém jsou fáze u všech drah na stejném místě — a srovnat „co už běželo
    /// a co ještě ne“ je zrovna ta otázka, kvůli které tenhle stav vzniká.
    ///
    /// `čeká na slot` mezi nimi **není**: ta fáze se kreslí jen tehdy, když ji osa zaznamenala, a
    /// reviewer, který se nespustil, na žádný slot nečekal.
    private static func notStartedLane(of skill: String, isConfigured: Bool) -> ReviewerLane {
        ReviewerLane(
            skill: skill,
            state: .notStarted,
            phases: [
                ReviewerLane.Phase(title: ReviewerLane.Title.session, detail: nil, state: .idle),
                ReviewerLane.Phase(title: ReviewerLane.Title.code, detail: nil, state: .idle),
                ReviewerLane.Phase(title: ReviewerLane.Title.findings, detail: nil, state: .idle),
            ],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            entries: [],
            // Dnes je to vždycky `true` — co v sadě není a nemá ani osu, ani běh, se do pořadí
            // drah nedostane. Předává se přesto: ta pravda drží jen pořadím větví ve `lanes`,
            // a to je slabší záruka než parametr.
            isConfigured: isConfigured
        )
    }

    /// Běh, který v záznamu je, ale jeho osa ne (soubory z doby před #203).
    ///
    /// **Jedna kapsle, jako u `queued`** — a ze stejného důvodu: příběh fází se tady nedá vyprávět,
    /// takže by ho čtyři vyšisované kapsle jen předstíraly. `unknown`, ne `idle`: „nedošlo na ni“ by
    /// o proběhlém běhu lhalo. Jak to dopadlo, se čte z chipu revieweera a z tabu `Nálezy` — tam ta
    /// data jsou, jen k nim chybí průběh.
    private static func missingProgressLane(of skill: String, isConfigured: Bool) -> ReviewerLane {
        ReviewerLane(
            skill: skill,
            state: .missingProgress,
            phases: [ReviewerLane.Phase(title: ReviewerLane.Title.missing, detail: nil, state: .unknown)],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            entries: [],
            isConfigured: isConfigured
        )
    }

    private static func queuedLane(of skill: String, isConfigured: Bool) -> ReviewerLane {
        ReviewerLane(
            skill: skill,
            state: .queued,
            phases: [ReviewerLane.Phase(title: ReviewerLane.Title.waiting, detail: nil, state: .running)],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            entries: [],
            isConfigured: isConfigured
        )
    }

    private static func lane(
        of timeline: ReviewerTimeline,
        isRunning: Bool,
        isConfigured: Bool
    ) -> ReviewerLane {
        let reached = reachedStage(in: timeline)
        let state = laneState(of: timeline, isRunning: isRunning, reached: reached)
        return ReviewerLane(
            skill: timeline.skill,
            state: state,
            phases: state == .queued
                ? [ReviewerLane.Phase(title: ReviewerLane.Title.waiting, detail: nil, state: .running)]
                : phases(of: timeline, state: state, reached: reached),
            lastTool: lastTool(in: timeline),
            finishedAt: finishTime(in: timeline),
            reportedFindings: reportedFindings(in: timeline),
            usage: timeline.usage,
            sessionID: timeline.sessionID,
            worktree: timeline.worktree,
            droppedEntries: timeline.droppedEntries,
            loadedSkill: timeline.loadedADifferentSkill ? timeline.loadedSkill : nil,
            entries: timeline.entries,
            isConfigured: isConfigured
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
        // `notStarted` ani `missingProgress` sem nedojdou — dráha bez osy se skládá vlastní cestou
        // (`notStartedLane`, `missingProgressLane`). Stojí u `queued`, protože kdyby došly, není
        // v ose co značit.
        case .running, .finished, .queued, .notStarted, .missingProgress: reached
        }

        var phases: [ReviewerLane.Phase] = []
        if timeline.entries.contains(where: { if case .queued = $0.kind { true } else { false } }) {
            phases.append(ReviewerLane.Phase(title: ReviewerLane.Title.waiting, detail: nil, state: .done))
        }
        phases.append(ReviewerLane.Phase(
            title: ReviewerLane.Title.session,
            detail: nil,
            state: phaseState(of: 1, marked: marked, lane: state)
        ))
        phases.append(ReviewerLane.Phase(
            title: ReviewerLane.Title.code,
            detail: steps > 0 ? Plural.czech(steps, one: "krok", few: "kroky", many: "kroků") : nil,
            state: phaseState(of: 2, marked: marked, lane: state)
        ))
        phases.append(ReviewerLane.Phase(
            title: ReviewerLane.Title.findings,
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
        // `notStarted` ani `missingProgress` sem nedojdou (viz `marked` výš); jsou u `queued`
        // ze stejného důvodu.
        case .finished, .queued, .notStarted, .missingProgress: .done
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
