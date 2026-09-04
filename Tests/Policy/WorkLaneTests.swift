import Foundation
import Testing

@testable import PRism

/// Rozřazení pull requestu do pruhu desky (#515).
///
/// **Testuje se vyčerpávajícím výčtem**, a je to jediný způsob, jak to udělat: `Policy.lane` má
/// **pět** vstupních os (čí PR to je, v jakém stavu je review, leží tu draft, co zbývá předat
/// a v jakém stavu to předání je, dá se to mergnout) a **každá kombinace musí vyjít do právě
/// jednoho pruhu**. Rozřazení je věc, kterou se dá pokazit potichu — vypadne-li PR z desky, na
/// obrazovce po něm nezbude nic a počty pruhů budou dál vypadat platně.
///
/// **Osa `Stage` v rozhodování od druhého proklikání #515 nehraje roli, a právě proto ve výčtu
/// zůstává**: je to stráž, která nepustí `stage` do `Policy.lane` zpátky (viz
/// `handoffStageChangesNothing`).
///
/// Tvrdí se tedy trojice, ne jeden příklad:
///
/// 1. **totalita** — nad každou kombinací vyjde pruh (drží `switch` a nevolitelný návrat, ale
///    kombinací je 13 × 2 × 2 × 2 × 5 × 2 a rozhodování má priority, takže se to prochází);
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

    /// Report se **dvěma** osami výčtu: kolik zbývá předat a v jakém stavu to je. Do rozřazování
    /// se dostane jedině to první (`awaitsMove`) a je na to dvojice tvrzení
    /// (`handoffStageChangesNothing`, `ignoresTheRestOfTheReport`).
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

    /// A totéž o **stavech předání**: `Stage` má asociovaný typ, takže `CaseIterable` být nemůže
    /// a výčet je ruční. Vlastní tvrzení má proto, že se na tu osu ptá **celý výčet** níž —
    /// přidaný stav by z něj bez tohohle čísla vypadl beze slova.
    @Test("Výčet stavů předání je úplný")
    func coversEveryHandoffStage() {
        #expect(Self.stages.count == 5)
    }

    /// **Nad každou kombinací vyjde pruh** — a je to 1 040 kombinací, ne jeden příklad.
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

    /// Pruhů je šest **v datech**, i když jsou prázdné — o kresbě to netvrdí nic: prázdný pruh
    /// se od proklikání #515 nekreslí (`Board.visibleLanes`), ale z `Board.lanes` zmizet nesmí,
    /// protože z nich mluví věta pod pozdravem.
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

    /// Vlastní PR: **slévatelnost vyhrává vždycky** (druhé proklikání #515 — ruší výjimku pro
    /// `changed`, kterou tady stálo po prvním).
    ///
    /// Vzniklo z toho, že schválený PR se všemi checky zelenými ležel v `Předat agentovi`
    /// (`keboola/job-queue-daemon#934`): `pending > 0` rozhodovalo dřív než merge. Slévatelnost je
    /// ale nejsilnější signál, jaký vlastní PR má, a tah „mergni to“ má **dobu trvanlivosti** —
    /// takže mergnutelný PR patří do `K merge`, tečka.
    ///
    /// Tvrdí se to **přes všech pět stavů předání**, protože přesně tady se lišila předchozí verze:
    /// plošné „přebíjí vždycky“ i výjimka pro jeden stav by prošly jedním příkladem.
    @Test("Vlastní PR: merge přebíjí předání ve všech pěti stavech")
    func mergeBeatsHandoff() {
        for stage in Self.stages {
            #expect(
                lane(.clean, ownership: .mine, pending: 2, stage: stage, isMergeReady: true) == .merge,
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
        // A nemergnutelný PR **bez** čeho předat čeká, ať je stav předání jaký chce: `handOff`
        // rozhoduje počet, ne razítko.
        for stage in Self.stages {
            #expect(
                lane(.clean, ownership: .mine, pending: 0, stage: stage, isMergeReady: false) == .waiting,
                "\(stage)"
            )
        }
    }

    /// **Stav předání na pruh nemá vliv, a je to stráž, ne poznámka** (druhé proklikání #515).
    ///
    /// Po prvním proklikání tu byla výjimka: `changed` držel PR v `Předat agentovi` i nad
    /// slévatelnou větví. Pokyn ji zrušil celou, takže `HandoffReport.outranksMerge` zanikl — a to
    /// se dá tvrdit jedině takhle: nad **celou mřížkou** vstupů musí `stage` vyjít nerozlišitelně.
    /// Kdyby se vrátila jakákoli podmínka na `stage`, spadne to tady, ne v renderu.
    @Test("Stav předání pruhem nehýbe v žádné kombinaci")
    func handoffStageChangesNothing() {
        for state in Self.states {
            for ownership in [PullRequestOwnership.theirs, .mine] {
                for hasDraft in [false, true] {
                    for pending in [0, 3] {
                        for ready in [false, true] {
                            let reference = lane(
                                state,
                                ownership: ownership,
                                hasDraft: hasDraft,
                                pending: pending,
                                stage: .never,
                                isMergeReady: ready
                            )
                            for stage in Self.stages {
                                #expect(
                                    lane(
                                        state,
                                        ownership: ownership,
                                        hasDraft: hasDraft,
                                        pending: pending,
                                        stage: stage,
                                        isMergeReady: ready
                                    ) == reference,
                                    "\(state) \(ownership) draft=\(hasDraft) pending=\(pending) \(stage)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// **`handOff` je poslední pravidlo, které něco tvrdí — a tichý pruh je fallback** (třetí
    /// proklikání #515: *„předat agentovi poslední jsem myslel jako poslední pravidlo, ne poslední
    /// box“*).
    ///
    /// Je to tvrzení o tom, co se **nestalo**, a proto je z téhle sady nejcennější: kdyby se
    /// pravidlo o předání posunulo **za** `waiting`, do `Předat agentovi` by nespadlo **nikdy nic**
    /// a všechny vlastní PR by se svezly na tichém pruhu. Deska by přitom vypadala platně — pruh se
    /// při nule nekreslí, takže by po něm nezbylo ani prázdné okýnko.
    ///
    /// Tvrdí se to **z obou stran**: dokud něco zbývá předat, do tichého pruhu se PR nedostane
    /// (leda že review běží — to je pravidlo výš), a naopak `waiting` u vlastního PR nastane jedině
    /// tehdy, když nezbývá nic.
    @Test("Předání je poslední pravidlo, které něco tvrdí")
    func handOffIsTheLastRuleThatClaimsAnything() {
        let running: [ReviewState] = [.queued, .cloning, .running(finished: 1, total: 3)]
        for state in Self.states {
            for hasDraft in [false, true] {
                for stage in Self.stages {
                    for ready in [false, true] {
                        let lane = lane(
                            state,
                            ownership: .mine,
                            hasDraft: hasDraft,
                            pending: 3,
                            stage: stage,
                            isMergeReady: ready
                        )
                        #expect(
                            lane != .waiting || running.contains(state),
                            "\(state) draft=\(hasDraft) \(stage) ready=\(ready)"
                        )
                    }
                }
            }
        }
        // A z druhé strany: `waiting` je **konec výčtu**, ne pravidlo — u vlastního PR nastane
        // jedině tehdy, když se nedá tvrdit ani předání, ani merge.
        for state in Self.states where !running.contains(state) {
            #expect(lane(state, ownership: .mine, pending: 0, isMergeReady: false) == .waiting, "\(state)")
            #expect(lane(state, ownership: .mine, pending: 1, isMergeReady: false) == .handOff, "\(state)")
        }
    }

    /// Do rozřazování jde z reportu **jedině `pending`** (přes `awaitsMove`), nic jiného. Kdyby se
    /// opřelo o `staleFindings` nebo o razítko, začal by pruh záležet na tom, jestli se načetla
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
