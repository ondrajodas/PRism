import Foundation

extension Policy {
    /// Jak se dráha anotací jmenuje v tabu `Průběh` (#524).
    ///
    /// **Není to jméno skillu a nesmí se s ním potkat**: dráha se do seznamu reviewerů nedává,
    /// kreslí se pod ním zvlášť (viz `annotationLane`), takže by dvě stejná `id` nemohla vzniknout
    /// ani tehdy, kdyby se nějaký skill takhle jmenoval.
    static let annotationLaneName = "anotace"

    /// Dráha sedmé session do tabu `Průběh` (#524). `nil` = **nekreslí se nic**.
    ///
    /// **Vlastní funkce, ne další položka v `Policy.lanes`**, a je to podmínka, ne uspořádání:
    /// `lanes` vypisuje **tytéž reviewery jako `Policy.chips`** (je na to test) a anotace mezi ně
    /// nepatří — chip vedle nich nese počet nálezů, který sedmá session nemá a mít nebude. Kreslí
    /// se proto **pod** dráhami reviewerů a `ReviewProgressView` ji bere zvlášť.
    ///
    /// Přednost má **běh** před uloženým výsledkem: dokud session běží, je pravdou o tom PR ona,
    /// i kdyby na disku ležel výsledek z minula.
    ///
    /// **Hlava se hlídá u obojího** (tvrdá podmínka č. 5). Uložený výsledek přes
    /// `annotations(of:head:)`, běh přes `AnnotationPass.headSha` — dráha z běhu nad **starou**
    /// hlavou by v tabu tvrdila „popsáno, 1 anotace“ o diffu, ze kterého se v okně nic nekreslí,
    /// protože anotace vázané na starou hlavu se nevydají. Anotace z jiné hlavy se tedy neukáže
    /// ani jako dráha, ať je odkudkoli.
    ///
    /// - Parameters:
    ///   - pass: co session v tomhle sezení udělala. `nil` = v tomhle sezení neběžela.
    ///   - stored: co leží na disku.
    ///   - head: hlava, kterou PR má teď. `nil` = detail se ještě nenačetl, takže se o platnosti
    ///     nedá nic tvrdit — a to je **zákaz, ne povolení**.
    static func annotationLane(
        pass: AnnotationPass?,
        stored: StoredAnnotations?,
        head: String?
    ) -> ReviewerLane? {
        if let pass, let head, !head.isEmpty, pass.headSha == head { return lane(of: pass) }
        guard let stored = annotations(of: stored, head: head) else { return nil }
        return lane(of: stored)
    }

    /// Dráha z běhu, který v tomhle sezení proběhl nebo běží.
    private static func lane(of pass: AnnotationPass) -> ReviewerLane {
        let state = laneState(of: pass)
        return ReviewerLane(
            skill: annotationLaneName,
            kind: .annotations(hunks: pass.hunks, files: pass.files, dropped: pass.dropped),
            state: state,
            phases: phases(of: pass, state: state),
            lastTool: pass.lastTool,
            finishedAt: pass.finish?.at,
            // **Navěky `nil`, a je to to tvrzení**: anotace není nález, takže dráha nesmí nést
            // číslo, které se čte jako „tolik toho našla“. Co nahlásila, nese `kind`.
            reportedFindings: nil,
            usage: pass.usage,
            sessionID: pass.sessionID,
            worktree: pass.worktree,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            // Rozbalovací výpis kroků dráha nemá — nedrží osu, viz `AnnotationPass`. Prázdné pole
            // znamená, že `Policy.stepFeed` nic nevydá, tedy že se šipka u dráhy nenakreslí.
            entries: [],
            increment: nil,
            wholeReason: nil,
            // **`true`, ne `false`**: kapsle `mimo sadu` mluví o skillu, který z nastavení zmizel,
            // a u anotací by tvrdila, že sem tahle dráha nepatří. Sada s nimi nemá co dělat.
            isConfigured: true
        )
    }

    /// Dráha z uloženého výsledku — po restartu, kdy o průběhu nevíme nic.
    ///
    /// **Fáze jsou `done`, ne `unknown`**, na rozdíl od `missingProgress` u revieweera: tady se
    /// nic neztratilo. Průběh se u anotací **schválně neukládá** (`AnnotationPass`), takže „běh
    /// doběhl a kroky neznáme“ je normální stav téhle dráhy, ne díra v datech.
    private static func lane(of stored: StoredAnnotations) -> ReviewerLane {
        let finished = stored.outcome == .finished
        return ReviewerLane(
            skill: annotationLaneName,
            kind: .annotations(
                hunks: stored.answered ? stored.hunks.count : nil,
                files: stored.answered ? stored.files.count : nil,
                dropped: stored.dropped
            ),
            state: state(of: stored.outcome),
            phases: [
                ReviewerLane.Phase(title: ReviewerLane.Title.session, detail: nil, state: .done),
                ReviewerLane.Phase(
                    title: ReviewerLane.Title.code,
                    detail: nil,
                    state: finished ? .done : .failed
                ),
                ReviewerLane.Phase(
                    title: ReviewerLane.Title.annotations,
                    detail: stored.answered ? annotationDetail(hunks: stored.hunks.count) : nil,
                    state: stored.answered ? .done : (finished ? .idle : .failed)
                ),
            ],
            lastTool: nil,
            finishedAt: stored.finishedAt,
            reportedFindings: nil,
            usage: stored.usage,
            sessionID: stored.sessionID,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            entries: [],
            increment: nil,
            wholeReason: nil,
            isConfigured: true
        )
    }

    /// Kde dráha stojí, když běh známe z tohohle sezení.
    private static func laneState(of pass: AnnotationPass) -> ReviewerLane.State {
        guard let finish = pass.finish else {
            // Session, která ještě neposlala ani `session_id`, na něco čeká — `queued` je o tom
            // pravdivější než `running`, přesně jako u revieweera.
            return pass.reached == 0 ? .queued : .running
        }
        return state(of: finish.outcome)
    }

    /// Překlad konce běhu na stav dráhy. **`finished` není „něco nahlásila“** — tatáž hranice
    /// jako u revieweera, jen o vrstvu výš.
    private static func state(of outcome: ReviewRunOutcome) -> ReviewerLane.State {
        switch outcome {
        case .finished: .finished
        case .timedOut: .timedOut
        case .interrupted: .interrupted
        case .failed(let detail): .failed(detail: detail)
        }
    }

    /// Fáze běhu, který známe z tohohle sezení. **Tři, jako u revieweera** — tvar běhu je tentýž
    /// (náběh session → kroky nad kódem → nahlášení), liší se jen ta poslední a její popisek.
    private static func phases(of pass: AnnotationPass, state: ReviewerLane.State) -> [ReviewerLane.Phase] {
        guard state != .queued else {
            return [ReviewerLane.Phase(title: ReviewerLane.Title.waiting, detail: nil, state: .running)]
        }
        return [
            ReviewerLane.Phase(
                title: ReviewerLane.Title.session,
                detail: nil,
                state: phaseState(reached: pass.reached, at: 1, state: state)
            ),
            ReviewerLane.Phase(
                title: ReviewerLane.Title.code,
                detail: pass.toolSteps > 0
                    ? Plural.czech(pass.toolSteps, one: "krok", few: "kroky", many: "kroků")
                    : nil,
                state: phaseState(reached: pass.reached, at: 2, state: state)
            ),
            ReviewerLane.Phase(
                title: ReviewerLane.Title.annotations,
                detail: pass.hunks.map(annotationDetail(hunks:)),
                state: phaseState(reached: pass.reached, at: 3, state: state)
            ),
        ]
    }

    /// Jak stojí jedna fáze. `done` až tehdy, když se běh dostal **dál** — fáze, ve které se právě
    /// je, běží; fáze, ke které se běh nedostal a už nedostane, je `failed` u spadlého běhu
    /// a `idle` u doběhlého.
    private static func phaseState(
        reached: Int,
        at step: Int,
        state: ReviewerLane.State
    ) -> ReviewerLane.PhaseState {
        if reached > step { return .done }
        if reached == step {
            switch state {
            case .running: return .running
            case .finished: return .done
            case .stopped: return .stopped
            default: return .failed
            }
        }
        switch state {
        case .running, .queued, .finished: return .idle
        case .stopped: return .stopped
        default: return .failed
        }
    }

    /// Co se píše do fáze `píše anotace`. **Počet hunků, ne nálezů** — a jméno funkce to říká.
    private static func annotationDetail(hunks: Int) -> String {
        Plural.czech(hunks, one: "anotace", few: "anotace", many: "anotací")
    }
}
