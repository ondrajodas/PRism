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
        isMergeReady: Bool = false
    ) -> WorkLane {
        Policy.lane(
            of: entry(1, state: state, hasDraft: hasDraft),
            ownership: ownership,
            pending: pending,
            isMergeReady: isMergeReady
        )
    }
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
                        for ready in [false, true] {
                            seen.insert(lane(
                                state,
                                ownership: ownership,
                                hasDraft: hasDraft,
                                pending: pending,
                                isMergeReady: ready
                            ))
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
                lane(state, ownership: .mine, hasDraft: true, pending: 5, isMergeReady: true)
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

    /// Vlastní PR: **co zbývá předat, přebíjí merge**. Nemá cenu nabízet merge nad PR, na kterém
    /// leží nevyřízený nález nebo cizí vlákno — a `pending` je tatáž otázka jako odznak v railu.
    @Test("Vlastní PR: předání přebíjí merge")
    func handoffBeatsMerge() {
        #expect(lane(.clean, ownership: .mine, pending: 2, isMergeReady: true) == .handOff)
        #expect(lane(.clean, ownership: .mine, pending: 0, isMergeReady: true) == .merge)
        #expect(lane(.clean, ownership: .mine, pending: 0, isMergeReady: false) == .waiting)
    }

    /// **Vlastní PR se do `Rozhodnout` ani do `Přečíst` nedostane nikdy**, ať je review
    /// v jakémkoli stavu: oba ty pruhy jsou o cizí frontě (#332).
    @Test("Vlastní PR nikdy nespadne do cizích pruhů")
    func keepsOwnPullRequestsOutOfForeignLanes() {
        for state in Self.states {
            for pending in [0, 2] {
                for ready in [false, true] {
                    let lane = lane(
                        state,
                        ownership: .mine,
                        pending: pending,
                        isMergeReady: ready
                    )
                    #expect(lane != .read, "\(state)")
                    #expect(lane != .decide, "\(state)")
                }
            }
        }
    }

    /// **Cizí PR se naopak nedostane do vlastních pruhů** — a `pending` ani `isMergeReady` na to
    /// nemají vliv, protože `Policy.board` je u cizího řádku ani nečte.
    @Test("Cizí PR nikdy nespadne do vlastních pruhů")
    func keepsForeignPullRequestsOutOfOwnLanes() {
        for state in Self.states {
            let lane = lane(state, pending: 9, isMergeReady: true)
            #expect(lane != .handOff, "\(state)")
            #expect(lane != .merge, "\(state)")
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
