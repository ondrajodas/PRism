import Foundation
import Testing

@testable import PRism

/// Rozřazení pull requestu do pruhu desky (#515).
///
/// **Testuje se vyčerpávajícím výčtem**, a je to jediný způsob, jak to udělat: `Policy.lane` má
/// čtyři vstupní osy (čí PR to je, v jakém stavu je review, leží tu draft, dá se to mergnout)
/// a **každá kombinace musí vyjít do právě jednoho pruhu**. Rozřazení je věc, kterou se dá
/// pokazit potichu — vypadne-li PR z desky, na obrazovce po něm nezbude nic a počty pruhů budou
/// dál vypadat platně.
///
/// Tvrdí se tedy trojice, ne jeden příklad:
///
/// 1. **totalita** — nad každou kombinací vyjde pruh (drží `switch` a nevoliteľný návrat, ale
///    kombinací je 13 × 2 × 2 × 2 × 2 a rozhodování má priority, takže se to prochází);
/// 2. **disjunktnost** — `Policy.board` každý řádek zařadí právě jednou, takže součet pruhů je
///    počet PR;
/// 3. **pravidla jmenovitě** — u každé priority jeden případ, který se dá přečíst jako věta.
@Suite("Pruhy desky")
struct WorkLaneTests {
    /// Všechny případy `ReviewState`, vypsané ručně.
    ///
    /// **Ne `CaseIterable`** — `ReviewState` má asociované hodnoty, takže ho mít nemůže. Že jsou
    /// tu všechny, drží tvrzení o počtu níž: nový stav si tak vynutí rozhodnutí, do kterého pruhu
    /// patří, místo aby se tiše svezl na `default`u.
    private static let states: [ReviewState] = [
        .notStarted,
        .queued,
        .cloning,
        .checkoutFailed(detail: "klon spadl"),
        .running(finished: 1, total: 3),
        .clean,
        .completed(findings: 2),
        .dismissed(findings: 1),
        .inconclusive(reason: .noReport),
        .failed(detail: "kód 1"),
        .timedOut(findings: 1),
        .interrupted(findings: 1),
        .stale,
    ]

    private func summary(_ number: Int, author: String = "kolega") -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID("cli/cli")!, number: number),
            title: "titulek \(number)",
            author: author,
            url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: Double(number)),
            state: .open
        )
    }

    private func entry(_ number: Int, state: ReviewState, hasDraft: Bool = false) -> QueueEntry {
        QueueEntry(
            pullRequest: summary(number),
            state: state,
            row: .empty,
            hasDraft: hasDraft
        )
    }

    private func lane(
        _ state: ReviewState,
        ownership: PullRequestOwnership = .theirs,
        hasDraft: Bool = false,
        pending: Int = 0,
        stage: HandoffReport.Stage = .never,
        isMergeReady: Bool = false
    ) -> WorkLane {
        Policy.lane(
            of: entry(1, state: state, hasDraft: hasDraft),
            ownership: ownership,
            handoff: Self.handoff(pending: pending, stage: stage),
            isMergeReady: isMergeReady
        )
    }

    /// Report s **jedním** rozhodujícím obsahem: kolik zbývá předat a v jakém stavu to je.
    /// Zbytek polí se do rozřazování nedostane a je na to tvrzení (`ignoresTheRestOfTheReport`).
    static func handoff(pending: Int, stage: HandoffReport.Stage) -> HandoffReport {
        HandoffReport(
            stage: stage,
            handoff: nil,
            pending: pending,
            freshDiscussion: [],
            staleFindings: 0,
            commits: nil
        )
    }

    /// **Všech pět stavů předání**, vyjmenovaných ručně: `Stage` má asociovaný typ `Equatable`,
    /// ale `CaseIterable` není, takže by přidaný stav z výčtu vypadl beze slova.
    static let stages: [HandoffReport.Stage] = [.never, .unverified, .outdated, .changed, .delivered]
}

// MARK: - Výčet: každá kombinace do právě jednoho pruhu

extension WorkLaneTests {
    /// Že je stavů třináct, je tvrzení, ne poznámka: bez něj by přidaný stav vypadl z celého
    /// výčtu níž a test by dál procházel.
    @Test("Výčet stavů review je úplný")
    func coversEveryReviewState() {
        #expect(Self.states.count == 13)
    }

    /// **Nad každou kombinací vyjde pruh** — a je to 208 kombinací, ne jeden příklad.
    ///
    /// Tvrzení je zdánlivě prázdné (návratový typ není optional), ale prázdné není: prochází se
    /// jím **pořadí priorit**, a to je to jediné, co se v téhle funkci dá pokazit. Kdyby se
    /// z rozhodování dala vyrobit nekonečná smyčka nebo pád (`fatalError` v `default`u), spadne
    /// to tady.
    @Test("Každá kombinace vstupů vydá pruh")
    func alwaysProducesALane() {
        var seen: Set<WorkLane> = []
        for state in Self.states {
            for ownership in [PullRequestOwnership.theirs, .mine] {
                for hasDraft in [false, true] {
                    for pending in [0, 3] {
                        for stage in Self.stages {
                            for ready in [false, true] {
                                seen.insert(lane(
                                    state,
                                    ownership: ownership,
                                    hasDraft: hasDraft,
                                    pending: pending,
                                    stage: stage,
                                    isMergeReady: ready
                                ))
                            }
                        }
                    }
                }
            }
        }
        // Všech šest pruhů je z těch kombinací dosažitelných — pruh, do kterého se nedá dostat,
        // by byl mrtvá kresba.
        #expect(seen == Set(WorkLane.allCases))
    }

    /// **Disjunktnost se tvrdí nad `Policy.board`**, ne nad `lane(of:…)`: tam je vidět to, na čem
    /// obrazovka doopravdy stojí — že se součet pruhů rovná počtu pull requestů. Kdyby se řádek
    /// zařadil dvakrát, počty by se nadsadily; kdyby vypadl, zmizel by z desky beze slova.
    @Test("Součet pruhů je počet pull requestů, ať jsou v jakémkoli stavu")
    func placesEveryPullRequestExactlyOnce() {
        let entries = Self.states.enumerated().map { index, state in
            entry(index + 1, state: state)
        }

        let board = Policy.board(entries: entries)

        #expect(board.lanes.reduce(0) { $0 + $1.count } == entries.count)
        // A identity se nesmí zdvojit ani prohodit: sjednocení pruhů je přesně vstup.
        let placed = board.lanes.flatMap { $0.rows.map(\.id) }
        #expect(Set(placed).count == entries.count)
        #expect(Set(placed) == Set(entries.map(\.id)))
    }

    /// Pruhů je šest a **kreslí se vždycky všechny**, i prázdné: mizející pruh by desku při
    /// každém tiku přeskládal.
    @Test("Deska má šest pruhů v pořadí z návrhu i nad prázdným vstupem")
    func alwaysHasSixLanesInOrder() {
        let board = Policy.board(entries: [])

        #expect(board.lanes.map(\.lane) == WorkLane.order)
        #expect(WorkLane.order.count == WorkLane.allCases.count)
        #expect(board.lanes.allSatisfy { $0.rows.isEmpty })
    }
}

// MARK: - Pravidla jmenovitě

extension WorkLaneTests {
    /// **Draft přebíjí všechno** — i běžící review, i vlastní PR s předáním. Rozdělané review je
    /// ručně psaná práce a ta se za stav review ani za autora neztrácí.
    @Test("Rozdělané review přebíjí každý jiný pruh")
    func draftBeatsEverything() {
        for state in Self.states {
            #expect(lane(state, hasDraft: true) == .finishReview)
            #expect(
                lane(state, ownership: .mine, hasDraft: true, pending: 5, stage: .changed, isMergeReady: true)
                    == .finishReview
            )
        }
    }

    /// **Běžící review je čekání**, ne `Přečíst`. Kdyby běžící PR zůstal v `Přečíst`, hlásil by
    /// pruh víc, než co jeho akce pustí — a poznalo by se to jedině účtem za session.
    @Test("Běžící review jde do tichého pruhu, ať je čí chce")
    func runningGoesToTheQuietLane() {
        for state in [ReviewState.queued, .cloning, .running(finished: 1, total: 3)] {
            #expect(lane(state) == .waiting)
            #expect(lane(state, ownership: .mine, pending: 4) == .waiting)
        }
    }

    /// Cizí PR se dělí **jedinou otázkou**: běželo, nebo neběželo. `notStarted` je `Přečíst`
    /// (tedy přesně to, co pustí hromadná akce), všechno ostatní `Rozhodnout` — včetně čistého
    /// review, protože schválit je taky rozhodnutí, a včetně selhání, kde je tahem podívat se
    /// a rozhodnout, co dál.
    @Test("Cizí PR: neběželo je Přečíst, všechno ostatní Rozhodnout")
    func splitsForeignByWhetherItRan() {
        let running: [ReviewState] = [.queued, .cloning, .running(finished: 1, total: 3)]

        #expect(lane(.notStarted) == .read)
        for state in Self.states where state != .notStarted {
            let expected: WorkLane = running.contains(state) ? .waiting : .decide
            #expect(lane(state) == expected, "\(state)")
        }
    }

    /// Vlastní PR: **merge přebíjí předání** (z proklikání #515, mění pravidlo přesně naopak).
    ///
    /// Vzniklo z toho, že schválený PR se všemi checky zelenými ležel v `Předat agentovi`
    /// (`keboola/job-queue-daemon#934`): `pending > 0` rozhodovalo dřív než merge. Slévatelnost je
    /// ale nejsilnější signál, jaký vlastní PR má, a tah „mergni to“ má **dobu trvanlivosti**.
    ///
    /// **Jedinou výjimkou je `changed`** — jediný stav předání, který mluví o něčem
    /// **nevyřízeném** (typicky o cizí odpovědi v předaném vlákně, a tu chci vidět **než** mergnu).
    /// Rozhoduje se po případech, ne plošně, takže se to tvrdí **přes všech pět stavů**.
    @Test("Vlastní PR: merge přebíjí předání, jedině changed ne")
    func mergeBeatsHandoff() {
        for stage in Self.stages {
            let expected: WorkLane = stage == .changed ? .handOff : .merge
            #expect(
                lane(.clean, ownership: .mine, pending: 2, stage: stage, isMergeReady: true) == expected,
                "\(stage)"
            )
        }
        // Nemergnutelný PR se dělí jako dřív — tam se nic nezměnilo, a je to ta polovina pravidla,
        // kterou by změna pořadí podmínek rozbila potichu.
        for stage in Self.stages {
            #expect(
                lane(.clean, ownership: .mine, pending: 2, stage: stage, isMergeReady: false) == .handOff,
                "\(stage)"
            )
        }
        #expect(lane(.clean, ownership: .mine, pending: 0, stage: .delivered, isMergeReady: true) == .merge)
        #expect(lane(.clean, ownership: .mine, pending: 0, stage: .delivered, isMergeReady: false) == .waiting)
        // A `changed` bez čeho předat je taky `merge`: přebíjí **nevyřízené položky**, ne sám sebe.
        #expect(lane(.clean, ownership: .mine, pending: 0, stage: .changed, isMergeReady: true) == .merge)
    }

    /// **`outranksMerge` je vlastnost stavu předání, a tvrdí se výčtem** — plošné „předání přebíjí
    /// merge“ i plošné „nepřebíjí nikdy“ by prošly jedním příkladem.
    @Test("Merge přebíjí čtyři stavy předání z pěti")
    func outranksMergeOnlyWhenSomethingIsUnresolved() {
        let outranking = Self.stages.filter { Self.handoff(pending: 1, stage: $0).outranksMerge }

        #expect(outranking == [.changed])
        #expect(Self.stages.count == 5)
    }

    /// Do rozřazování jde z reportu **`pending` a `stage`, nic jiného**. Kdyby se opřelo
    /// o `staleFindings` nebo o razítko, začal by pruh záležet na tom, jestli se načetla
    /// konverzace — a to je stav, který se mění pod rukou.
    @Test("Zbytek reportu na pruh nemá vliv")
    func ignoresTheRestOfTheReport() {
        let rich = HandoffReport(
            stage: .never,
            handoff: nil,
            pending: 2,
            freshDiscussion: ["a", "b"],
            staleFindings: 7,
            commits: 3,
            hasMovedHead: true,
            activity: .none
        )
        let plain = Self.handoff(pending: 2, stage: .never)

        for ready in [false, true] {
            #expect(
                Policy.lane(of: entry(1, state: .clean), ownership: .mine, handoff: rich, isMergeReady: ready)
                    == Policy.lane(of: entry(1, state: .clean), ownership: .mine, handoff: plain, isMergeReady: ready)
            )
        }
    }

    /// **Vlastní PR se do `Rozhodnout` ani do `Přečíst` nedostane nikdy**, ať je review
    /// v jakémkoli stavu: oba ty pruhy jsou o cizí frontě (#332).
    @Test("Vlastní PR nikdy nespadne do cizích pruhů")
    func keepsOwnPullRequestsOutOfForeignLanes() {
        for state in Self.states {
            for pending in [0, 2] {
                for stage in Self.stages {
                    for ready in [false, true] {
                        let lane = lane(
                            state,
                            ownership: .mine,
                            pending: pending,
                            stage: stage,
                            isMergeReady: ready
                        )
                        #expect(lane != .read, "\(state)")
                        #expect(lane != .decide, "\(state)")
                    }
                }
            }
        }
    }

    /// **Cizí PR se naopak nedostane do vlastních pruhů** — a `pending` ani `isMergeReady` na to
    /// nemají vliv, protože `Policy.board` je u cizího řádku ani nečte.
    @Test("Cizí PR nikdy nespadne do vlastních pruhů")
    func keepsForeignPullRequestsOutOfOwnLanes() {
        for state in Self.states {
            for stage in Self.stages {
                let lane = lane(state, pending: 9, stage: stage, isMergeReady: true)
                #expect(lane != .handOff, "\(state) \(stage)")
                #expect(lane != .merge, "\(state) \(stage)")
            }
        }
    }
}

// MARK: - Brána odesílání není překážka pull requestu

extension WorkLaneTests {
    /// **Vypnuté odesílání není překážka merge** (#515). Brána mluví o tom, co smí *aplikace*,
    /// ne o tom, jak stojí *pull request* — a s výchozím (vypnutým) odesíláním by jinak byl pruh
    /// `K merge` navždycky prázdný, tedy tvrzení o nastavení, ne o práci.
    @Test("Zavřená brána odesílání pruh K merge nevyprázdní")
    func ignoresThePublishingGate() {
        #expect(Policy.isMergeReady(.blocked([.notAllowed("odesílání je vypnuté")])))
        #expect(Policy.isMergeReady(.allowed))
    }

    /// Všechno ostatní překážka **je** — a `absent` (cizí PR) taky ne: nad ním se merge nekreslí
    /// vůbec a „nevím“ je na desce vždycky `waiting`.
    @Test("Každá jiná překážka pruh K merge zavře")
    func respectsEveryRealObstacle() {
        let real: [Policy.MergeObstacle] = [
            .factsMissing,
            .statusLoading,
            .statusFailed("gh spadl"),
            .statusUnknown,
            .conflicting(base: "main"),
            .behind(base: "main"),
            .protected,
            .draftPullRequest,
            .notOpen(.merged),
            .failingChecks(["test"]),
            .blockingFindings(1),
        ]
        for obstacle in real {
            #expect(!Policy.isMergeReady(.blocked([obstacle])), "\(obstacle)")
            // A ani ve dvojici s branou — jedna skutečná překážka stačí.
            #expect(
                !Policy.isMergeReady(.blocked([.notAllowed("vypnuto"), obstacle])),
                "\(obstacle)"
            )
        }
        #expect(!Policy.isMergeReady(.absent))
        // Že je jich jedenáct, drží výčet: nová překážka si vynutí rozhodnutí, jestli pruh
        // `K merge` zavírá.
        #expect(real.count == 11)
    }
}
