import Foundation

extension Policy {
    /// Kde smyčka vlastního PR stojí (#508) — **jedna čistá funkce pro celou dráhu**.
    ///
    /// **Na cizím PR vrací `nil`, a to je celý ten první test.** Smyčka je „co udělám se **svojí**
    /// větví“; nad cizí to je nadpis bez obsahu, stejně jako sekce `Větev` (#465). Nekreslí se
    /// zašedle, nekreslí se vůbec.
    ///
    /// **Walk, ne sedm nezávislých odznaků.** Stanice se procházejí v pořadí `Station.allCases`
    /// a walk se **zastaví na první, která není hotová**; ta je `active` a všechny za ní jsou
    /// `idle`. Zamlčené fakty se tím neztrácejí — CI je pořád v tabu `Kontroly` a překážky merge
    /// v sekci `Větev` —, jenže dráha odpovídá na **pořadí**, a zelený check nad kódem, který
    /// ještě nikdo nepushnul, je věta o **minulém** pushi.
    ///
    /// **Nepřebírá se pravidlo desky, že slévatelnost vyhrává vždycky** (#515). Deska vybírá
    /// **nejlevnější tah**, takže mergnutelný PR patří do `K merge`, i když na něm něco zbývá
    /// předat. Dráha odpovídá na jinou otázku — **kde v kole jsem** —, a `Zadání ✓` nad šesti
    /// nepředanými položkami by byla nepravda. Dvě odpovědi to nejsou: každá odpovídá na svoje.
    ///
    /// **„Nevím“ je odpověď, ne „nejde“** (#572). Slévatelnost i checky se dotahují až s detailem,
    /// takže hned po startu o nich okno neví nic — a stanice v tom stavu je `unknown` s větou
    /// `zjišťuju`, ne `failed`. Nad nevratnou akcí je to tatáž hranice, kterou drží `MergeObstacle`
    /// (`statusLoading` × `conflicting`).
    ///
    /// - Parameters:
    ///   - ownership: čí PR to je. Cokoli jiného než `.mine` vrací `nil`.
    ///   - state: stav pull requestu. `merged` a `closed` smyčku **zkracují** — nad mergnutým PR
    ///     nemá smysl tvrdit, že zbývá předat zadání.
    ///   - review: stav review na tomhle PR, tedy tatáž hodnota, jakou ukazuje řádek seznamu.
    ///   - handoff: co zbývá předat (#334). Čte se z něj `pending`, `stage` i `hasMovedHead` —
    ///     na rozdíl od desky, která bere jedině `awaitsMove`: dráha má dvě stanice (`Zadání`
    ///     a `Agent`) a rozlišení „nepředáno“ × „předáno a čekám na commit“ je právě to, co je
    ///     mezi nimi.
    ///   - sync: co se právě děje s větví (#466). `nil` = neděje se nic.
    ///   - status: co GitHub říká o slévatelnosti (#465). `nil` = ještě se neptalo.
    ///   - checks: kontroly. `nil` = nenačetly se (**„nevím“**), `[]` = PR bez CI (odpověď).
    ///   - reviewers: kdo na PR stojí a jak odpověděl (#392). `nil` = metadata se nenačetla.
    ///   - merge: nabídka merge z `mergeOffer(…)`, tedy z **téhož** místa, ze kterého se kreslí
    ///     tlačítko v sekci `Větev` — druhý seznam překážek by se s prvním rozešel.
    static func ownLoop(
        ownership: PullRequestOwnership,
        state: PullRequestState,
        review: ReviewState,
        handoff: HandoffReport,
        sync: BranchSyncState? = nil,
        status: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = nil,
        reviewers: [RequestedReviewer]? = nil,
        merge: MergeOffer = .absent
    ) -> OwnLoop? {
        guard ownership == .mine else { return nil }
        let stamp = handoffStamp(handoff)
        if let closed = closedLoop(state: state, stamp: stamp) { return closed }

        var stations: [OwnLoop.Stop] = []
        var stop: (station: OwnLoop.Station, sentence: String, move: OwnLoop.Move?)?

        for station in OwnLoop.Station.allCases {
            guard stop == nil else {
                stations.append(OwnLoop.Stop(station: station, state: .idle, detail: nil))
                continue
            }
            switch step(
                at: station,
                review: review,
                handoff: handoff,
                sync: sync,
                status: status,
                checks: checks,
                reviewers: reviewers,
                merge: merge
            ) {
            case .passed(let detail):
                stations.append(OwnLoop.Stop(station: station, state: .done, detail: detail))
            case .stopped(let state, let detail, let sentence, let action):
                stations.append(OwnLoop.Stop(station: station, state: state, detail: detail))
                stop = (station, sentence, action)
            }
        }
        return OwnLoop(
            stations: stations,
            active: stop?.station,
            // Bez zastávky došla smyčka do konce, aniž by byl PR mergnutý — stane se to mezi
            // úspěšným merge a dalším načtením stavu PR.
            last: stop?.sentence ?? "Všech sedm stanic je hotových — smyčka došla do konce.",
            move: stop?.move,
            stamp: stamp
        )
    }

    /// Co walk s jednou stanicí udělá: pustí dál, nebo se na ní zastaví.
    ///
    /// **Vnitřní typ, ne součást `OwnLoop`u**: je to mezikrok skládání, ne stav, který by někdo
    /// kreslil. Kdyby byl venku, dala by se dráha složit odjinud než tady.
    private enum LoopStep {
        case passed(detail: String?)
        case stopped(
            state: ReviewerLane.PhaseState,
            detail: String?,
            sentence: String,
            move: OwnLoop.Move?
        )
    }

    private static func step(
        at station: OwnLoop.Station,
        review: ReviewState,
        handoff: HandoffReport,
        sync: BranchSyncState?,
        status: BranchStatusState?,
        checks: [PullRequestCheck]?,
        reviewers: [RequestedReviewer]?,
        merge: MergeOffer
    ) -> LoopStep {
        switch station {
        case .findings: findingsStep(review)
        case .handoff: handoffStep(handoff)
        case .agent: agentStep(handoff)
        case .push: pushStep(sync: sync, status: status)
        case .ci: checksStep(checks)
        case .review: reviewStep(reviewers)
        case .merge: mergeStep(merge)
        }
    }

    // MARK: - Mergnutý a zavřený PR

    /// Smyčka nad PR, který už nikam nevede.
    ///
    /// **Zkracuje se celá, ne jen poslední stanice.** Nad mergnutým PR by walk zastavil tam, kde
    /// zrovna zbylo něco nepředaného — a věta `6 k předání` nad mergnutou větví je rada, kterou
    /// nemá kdo splnit. `merged` je proto sedm hotových stanic, `closed` sedm nedojetých:
    /// `stopped` je ta hodnota, kterou dráha reviewera používá pro „nedoběhlo, protože se to
    /// zastavilo“, takže se nový stav nezavádí.
    private static func closedLoop(state: PullRequestState, stamp: String?) -> OwnLoop? {
        switch state {
        case .open, .draft:
            return nil
        case .merged:
            return OwnLoop(
                stations: OwnLoop.Station.allCases.map {
                    OwnLoop.Stop(station: $0, state: .done, detail: nil)
                },
                active: nil,
                last: "Mergnuto — smyčka došla do konce.",
                move: nil,
                stamp: stamp
            )
        case .closed:
            return OwnLoop(
                stations: OwnLoop.Station.allCases.map {
                    OwnLoop.Stop(station: $0, state: .stopped, detail: nil)
                },
                active: nil,
                last: "Pull request je zavřený — smyčka nikam nevede.",
                move: nil,
                stamp: stamp
            )
        }
    }

    // MARK: - Stanice

    /// `Nálezy` — co o kódu řekly moje reviewery.
    ///
    /// **Neprůkazný běh smyčku zastaví** (#383), a je to schválně: `inconclusive` existuje právě
    /// proto, aby se nečetl jako `čisto`, a pustit ho dál by ho tiše přečetlo jako čisto. Stav je
    /// `unknown`, ne `failed` — session doběhla.
    private static func findingsStep(_ review: ReviewState) -> LoopStep {
        switch review {
        case .notStarted:
            .stopped(
                state: .running,
                detail: "nespuštěno",
                sentence: "Review na tomhle PR ještě neběželo — pusť ho, ať je z čeho složit zadání.",
                move: nil
            )
        case .queued:
            .stopped(
                state: .running,
                detail: "čeká na slot",
                sentence: "Review čeká na volný slot.",
                move: nil
            )
        case .cloning:
            .stopped(
                state: .running,
                detail: "kopie repa",
                sentence: "Připravuje se pracovní kopie repa.",
                move: nil
            )
        case .running(let finished, let total):
            .stopped(
                state: .running,
                detail: "\(finished)/\(total)",
                sentence: "Reviewery běží — hotových je \(finished) ze \(total).",
                move: nil
            )
        case .checkoutFailed(let detail):
            .stopped(
                state: .failed,
                detail: "kopie repa",
                sentence: "Pracovní kopii repa se nepodařilo připravit: \(detail)",
                move: nil
            )
        case .failed(let detail):
            .stopped(
                state: .failed,
                detail: "spadlo",
                sentence: "Review spadlo (\(detail)) — nálezy z něj nejsou, což není totéž jako čisto.",
                move: nil
            )
        case .timedOut:
            .stopped(
                state: .stopped,
                detail: "timeout",
                sentence: "Review nedoběhlo do limitu, takže za zbytek kódu nemluví.",
                move: nil
            )
        case .interrupted:
            .stopped(
                state: .stopped,
                detail: "přerušeno",
                sentence: "Review skončilo s aplikací, takže za zbytek kódu nemluví.",
                move: nil
            )
        case .inconclusive(let reason):
            .stopped(
                state: .unknown,
                detail: "neprůkazné",
                sentence: inconclusiveSentence(reason),
                move: nil
            )
        case .stale:
            .stopped(
                state: .stopped,
                detail: "zastaralé",
                sentence: "Nálezy platí ke staršímu commitu, než jaký PR má teď — pusť review znovu.",
                move: nil
            )
        case .clean:
            .passed(detail: "čisto")
        case .completed(let findings):
            .passed(detail: Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů"))
        case .dismissed(let findings):
            .passed(detail: "\(findings) odmítnuto")
        }
    }

    /// Proč se z běhu čisto tvrdit nedá. **Věta, ne odznak** — odznaky (`ztracené nálezy`,
    /// `bez hlášení`, `kód nepřečten`) skládá `ReviewStateAppearance` a v kapsli dráhy by se
    /// neušly; tady je celý důvod, protože `.last` je řádek pod fázemi.
    private static func inconclusiveSentence(_ reason: InconclusiveReason) -> String {
        switch reason {
        case .droppedFindings:
            "Review doběhlo, ale z části nálezů se nepodařilo přečíst povinné pole — čisto z toho neplyne."
        case .noReport:
            "Review doběhlo, aniž by nahlásilo nálezy — čisto z toho neplyne."
        case .unreadCode:
            "Review doběhlo, ale neotevřelo ani jeden soubor z kopie repa — čisto z toho neplyne."
        }
    }

    /// `Zadání` — co zbývá předat agentovi (#334).
    ///
    /// **Rozhoduje `pending`, ne `stage`.** `stage` říká, *proč* něco zbývá, a to je věta pod
    /// dráhou; jestli stanice pustí dál, je otázka „zbývá tu něco?“ — a na tu odpovídá jedno
    /// číslo. Kdyby to bylo obráceně, byla by `changed` s nulou (nová hlava, ale žádná položka)
    /// zastávka bez obsahu.
    private static func handoffStep(_ report: HandoffReport) -> LoopStep {
        guard report.pending > 0 else {
            guard let stamp = report.handoff else { return .passed(detail: "nic k předání") }
            return .passed(detail: "\(stamp.count) předáno")
        }
        let count = Plural.czech(report.pending, one: "položka", few: "položky", many: "položek")
        return .stopped(
            state: .running,
            detail: "\(report.pending) k předání",
            sentence: handoffSentence(report, count: count),
            move: .openHandoff
        )
    }

    /// Věta k nepředanému zadání. **U každého stavu jiná**, protože z každého plyne jiný další
    /// krok — a `outdated` je jediný, kde je tím krokem pustit review znovu.
    private static func handoffSentence(_ report: HandoffReport, count: String) -> String {
        switch report.stage {
        case .never:
            return "Čeká \(count) k předání agentovi."
        case .unverified:
            return "Zadání se předávalo proti neznámé hlavě, takže se nedá potvrdit, že platí — "
                + "\(count) k předání."
        case .outdated:
            let stale = Plural.czech(
                report.staleFindings, one: "nález", few: "nálezy", many: "nálezů"
            )
            return "Pod předaným zadáním přišel commit a \(stale) platí ke staršímu kódu — "
                + "pusť review znovu a předej to celé."
        case .changed:
            return report.hasMovedHead
                ? "Pod předaným zadáním přišel commit — \(count) k předání."
                : "Od předání přibylo \(count)."
        case .delivered:
            // Sem se nedojde: `delivered` znamená `pending == 0`, což odchytí `handoffStep`.
            // Vypsané je to proto, že vyčerpávající `switch` je jediné, co ohlídá nový stav
            // při překladu.
            return "Zadání je předané."
        }
    }

    /// `Agent` — **bez živého obsahu až do #511, a je to napsané, ne zamlčené.**
    ///
    /// Aplikace dneska neví, jestli nad předaným zadáním někdo pracuje: prompt se zkopíruje
    /// a odejde do cizího terminálu. Jediné, co se dá tvrdit, je **kdy se předalo** a **jestli od
    /// té doby přišel commit** — a přesně to stanice říká. Stav je proto `unknown`, ne `running`:
    /// `běží` by bylo tvrzení, které data neunesou (a zrovna tohle je vzor, který Copilot v tomhle
    /// repu nachází opakovaně).
    ///
    /// **Hotová je tehdy, když se hlava pohnula** (`HandoffReport.hasMovedHead`) — práce dorazila.
    /// A hotová je i tehdy, když se nikdy nic nepředávalo: na PR bez nálezů a bez diskuze nemá
    /// agent co dělat a `čekám na commit` by tam viselo navždycky.
    private static func agentStep(_ report: HandoffReport) -> LoopStep {
        if report.hasMovedHead { return .passed(detail: "commit dorazil") }
        guard let stamp = report.handoff else { return .passed(detail: "nebylo co předat") }
        return .stopped(
            state: .unknown,
            detail: "předáno",
            sentence: "Předáno "
                + "\(Plural.czech(stamp.count, one: "položka", few: "položky", many: "položek")). "
                + "Jestli na tom agent pracuje, aplikace zatím neví — dráha se pohne, až na větev přijde commit.",
            move: nil
        )
    }

    /// `Push` — srovnat větev nad základem a přetlačit ji (#466).
    ///
    /// **Rozdělaná práce v kopii repa přebíjí stav na GitHubu**, a je to pořadí, ne shoda: dokud
    /// v cache leží přerovnaná nebo rozdělaná větev, je další krok o ní, ne o tom, co si o větvi
    /// myslí GitHub (ten o rebase v cache neví vůbec).
    private static func pushStep(sync: BranchSyncState?, status: BranchStatusState?) -> LoopStep {
        if let sync, let step = syncStep(sync) { return step }
        switch status {
        case .none, .loading:
            return .stopped(
                state: .unknown,
                detail: "zjišťuju",
                sentence: "Zjišťuju, jak větev stojí nad základem.",
                move: nil
            )
        case .failed(let reason):
            // **Ne „konflikt“ a ne „srovnaná“** — tatáž hranice jako u `Policy.branchFacts`.
            return .stopped(
                state: .unknown,
                detail: "nevím",
                sentence: "Stav větve se nepodařilo zjistit. \(reason)",
                move: nil
            )
        case .loaded(let status, _):
            return branchStep(status)
        }
    }

    /// Krok podle toho, co leží v kopii repa. `nil` = neleží nic, co by rozhodovalo.
    private static func syncStep(_ sync: BranchSyncState) -> LoopStep? {
        if sync.isBusy {
            return .stopped(
                state: .running, detail: "pracuje se", sentence: sync.sentence, move: .openBranch
            )
        }
        if let branch = sync.rebasedBranch {
            return .stopped(
                state: .running,
                detail: "\(branch.replayed) přerovnáno",
                sentence: sync.sentence,
                move: .openBranch
            )
        }
        switch sync {
        case .conflicted, .unfinished, .unresolved, .failed:
            return .stopped(
                state: .failed, detail: "rebase", sentence: sync.sentence, move: .openBranch
            )
        case .pushed, .alreadyInSync, .rebasing, .resolving, .pushing, .discarding, .rebased:
            // Doběhlé srovnání o dnešní poloze větve nerozhoduje — to řekne `BranchStatus` níž.
            // Běžící a přerovnané stavy odchytily větve výš; vypsané jsou kvůli vyčerpávajícímu
            // `switch`i, který ohlídá nový případ při překladu.
            return nil
        }
    }

    private static func branchStep(_ status: BranchStatus) -> LoopStep {
        if status.mergeability == .conflicting || status.mergeState == .dirty {
            return .stopped(
                state: .failed,
                detail: "konflikt",
                sentence: "Větev je v konfliktu se základem — srovnej ji.",
                move: .openBranch
            )
        }
        if let divergence = status.divergence, divergence.isBehind {
            let commits = Plural.czech(divergence.behind, one: "commit", few: "commity", many: "commitů")
            return .stopped(
                state: .running,
                detail: "o \(divergence.behind) vzadu",
                sentence: "Větev je o \(commits) pozadu za základem — srovnej ji rebasem.",
                move: .openBranch
            )
        }
        if status.mergeState == .behind {
            return .stopped(
                state: .running,
                detail: "za základem",
                sentence: "Větev je pozadu za základem — srovnej ji rebasem.",
                move: .openBranch
            )
        }
        return .passed(detail: "srovnaná")
    }

    /// `CI` — kontroly na GitHubu.
    ///
    /// **`nil` a `[]` se nesmí slít**: nenačtené checky jsou „nevím“, prázdné pole je odpověď
    /// „tenhle PR nemá CI“ (a to je běžný stav, ne porucha).
    private static func checksStep(_ checks: [PullRequestCheck]?) -> LoopStep {
        guard let checks else {
            return .stopped(
                state: .unknown, detail: "zjišťuju", sentence: "Kontroly se načítají.", move: nil
            )
        }
        let summary = summary(of: checks)
        guard !summary.isEmpty else { return .passed(detail: "bez checků") }
        if summary.failed > 0 {
            let word = Plural.word(summary.failed, one: "neprošel", few: "neprošly", many: "neprošlo")
            return .stopped(
                state: .failed,
                detail: "\(summary.failed) \(word)",
                sentence: "\(Plural.czech(summary.failed, one: "check", few: "checky", many: "checků")) "
                    + "\(word) — oprav to a pushni znovu.",
                move: .openChecks
            )
        }
        if summary.running > 0 {
            return .stopped(
                state: .running,
                detail: "\(summary.running) běží",
                sentence: "\(Plural.czech(summary.running, one: "check", few: "checky", many: "checků")) "
                    + "ještě běží.",
                move: .openChecks
            )
        }
        return .passed(detail: summary.passed > 0 ? "zeleno" : "přeskočeno")
    }

    /// `Review` — kdo na PR stojí a jak odpověděl (#392).
    ///
    /// **U `čeká` není akce, a je to schválně**: čekat na kolegu není můj tah. `chce změny` akci
    /// má — vede do konverzace, kde ta věta stojí.
    private static func reviewStep(_ reviewers: [RequestedReviewer]?) -> LoopStep {
        guard let reviewers else {
            return .stopped(
                state: .unknown, detail: "zjišťuju", sentence: "Reviewery se načítají.", move: nil
            )
        }
        let blocking = reviewers.count { $0.answer == .changesRequested }
        if blocking > 0 {
            return .stopped(
                state: .failed,
                detail: "\(blocking) chce změny",
                sentence: Plural.czech(
                    blocking, one: "reviewer chce", few: "reviewery chtějí", many: "reviewerů chce"
                ) + " změny — přečti si je a předej je agentovi.",
                move: .openConversation
            )
        }
        let waiting = reviewers.count { $0.answer == .waiting }
        if waiting > 0 {
            return .stopped(
                state: .running,
                detail: "čeká \(waiting)",
                sentence: "Čeká se na \(Plural.czech(waiting, one: "reviewera", few: "reviewery", many: "reviewerů")) "
                    + "— tvůj tah to není.",
                move: nil
            )
        }
        let approved = reviewers.count { $0.answer == .approved }
        return .passed(detail: approved > 0 ? "schváleno" : "bez reviewerů")
    }

    /// `Merge` — poslední stanice (#465).
    ///
    /// **Zeleno je `running`, ne vlastní barva.** Návrh kreslí `k merge` mintově, jenže mint není
    /// ve slovníku fází dráhy reviewera — a přidat ho by byl přesně ten nový vzor, kterému se
    /// #508 vyhýbá. `running` je hodnota pro „tady se to zrovna děje / je to na tobě“ a v kresbě
    /// je to jediná zvýrazněná kapsle, což je přesně ta role.
    ///
    /// **Chybějící data jsou `unknown`, ne `failed`** (#572): `K merge` po startu slévatelnost
    /// nezná, protože se dotahuje až s detailem.
    private static func mergeStep(_ offer: MergeOffer) -> LoopStep {
        switch offer {
        case .absent:
            // Nad vlastním PR sem walk nedojde (`branchSection` kreslí sekci na každém vlastním),
            // ale tvrdit z toho `jde mergnout` by znamenalo tvrdit něco z chybějícího vstupu.
            return .stopped(
                state: .unknown, detail: "nevím", sentence: "O mergi se nedá říct nic.", move: nil
            )
        case .allowed:
            return .stopped(
                state: .running,
                detail: "k merge",
                sentence: "Zeleno — dá se to mergnout.",
                move: .openBranch
            )
        case .blocked(let obstacles):
            guard let first = obstacles.first else {
                // Prázdné `blocked` `mergeOffer(…)` nevydá; kdyby se to změnilo, ať dráha mlčí,
                // ne aby si důvod vymyslela.
                return .stopped(
                state: .unknown, detail: "nevím", sentence: "O mergi se nedá říct nic.", move: nil
            )
            }
            let waiting = obstacles.allSatisfy(\.isUnknownYet)
            return .stopped(
                state: waiting ? .unknown : .failed,
                detail: waiting ? "zjišťuju" : "nejde",
                sentence: first.sentence,
                move: waiting ? nil : .openBranch
            )
        }
    }

    /// Razítko do hlavičky dráhy — **počet předaných položek a hlava, proti které se předávalo**.
    /// `nil` = nepředávalo se, takže není co říct. Čas v něm **není**: formátovat datum je věc
    /// locale, a `Policy` je čistá funkce.
    private static func handoffStamp(_ report: HandoffReport) -> String? {
        guard let stamp = report.handoff else { return nil }
        let count = Plural.czech(stamp.count, one: "položka", few: "položky", many: "položek")
        guard let head = stamp.shortHead else { return "předáno \(count)" }
        return "předáno \(count) · proti \(head)"
    }
}

extension Policy.MergeObstacle {
    /// Je to překážka „ještě nevím“, ne „nejde to“ (#508, drží #572)?
    ///
    /// **Vlastní otázka vedle `isPublishingGate`**, protože se ptá na něco jiného: ta rozlišuje,
    /// o čem překážka mluví (o aplikaci × o pull requestu), tahle **jak jistá je**. Dráha na tom
    /// stojí celá: `K merge` po startu slévatelnost nezná, a `nejde mergnout` by nad načítáním
    /// bylo tvrzení z chybějících dat — tedy ta nejdražší strana omylu u nevratné akce.
    var isUnknownYet: Bool {
        switch self {
        case .factsMissing, .statusLoading, .statusFailed, .statusUnknown: true
        case .notAllowed, .conflicting, .behind, .protected, .draftPullRequest, .notOpen,
            .failingChecks:
            false
        }
    }
}
