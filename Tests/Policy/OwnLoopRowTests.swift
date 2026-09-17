import Foundation
import Testing

@testable import PRism

/// Dráha vlastního PR zmenšená do řádku seznamu (#509) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou zase ta záporná a všechna se rozbijí potichu:
///
/// - **na cizím PR se z řádku nestane nic** — tečky by tvrdily, že se s cizí větví chystám něco
///   dělat;
/// - **tečky nejsou druhý výčet stanic.** Skládají se z `Policy.ownLoop`, takže se s dráhou
///   v hlavičce téhož PR nemají jak rozejít — a zrovna tohle by se poznalo jedině tak, že se
///   člověk dívá na obojí naráz;
/// - **dojetá smyčka neříká `k merge`.** Slévatelnost tahle funkce nezná (a `Policy.ownLoop` ji
///   od čtvrtého kola #508 nebere ani jako vstup), takže by to bylo tvrzení z cizích dat —
///   odpovídá na ně pruh `K merge` na desce (#515) a sekce `Větev` (#465);
/// - **slovo nikdy nepřijde prázdné.** Pilulka bez textu je díra v řádku, ze které se nedá
///   poznat, jestli se něco nespočítalo, nebo jestli je všechno v pořádku.
@Suite("Dráha vlastního PR v řádku seznamu (#509)")
struct OwnLoopRowTests {
    // MARK: - Stavba vstupů

    private func check(_ name: String, _ outcome: PullRequestCheck.Outcome) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: outcome, link: nil, startedAt: nil, completedAt: nil)
    }

    private func status(
        _ mergeability: BranchStatus.Mergeability = .mergeable,
        _ state: BranchStatus.MergeState = .clean,
        behind: Int? = nil
    ) -> BranchStatusState {
        .loaded(
            BranchStatus(
                mergeability: mergeability,
                mergeState: state,
                divergence: behind.map { BranchDivergence(ahead: 1, behind: $0) }
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func handed(_ count: Int) -> HandoffReport {
        HandoffReport(
            stage: .delivered,
            handoff: Handoff(
                at: Date(timeIntervalSince1970: 100),
                headSha: "9c1de02aa1b2c3",
                handed: Set((0..<count).map { "item-\($0)" })
            ),
            pending: 0,
            freshDiscussion: [],
            staleFindings: 0,
            commits: nil
        )
    }

    private func pendingHandoff(_ count: Int) -> HandoffReport {
        HandoffReport(
            stage: .never,
            handoff: nil,
            pending: count,
            freshDiscussion: [],
            staleFindings: 0,
            commits: nil
        )
    }

    /// Smyčka, ve které **všechno projde**, dokud se v parametru neřekne jinak — tentýž tvar jako
    /// v `OwnLoopTests`, aby se testy o jedné stanici nemusely rozepisovat o čtyřech ostatních.
    private func row(
        ownership: PullRequestOwnership = .mine,
        state: PullRequestState = .open,
        review: ReviewState = .clean,
        handoff: HandoffReport? = nil,
        sync: BranchSyncState? = nil,
        status branchStatus: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = [],
        reviewers: [RequestedReviewer]? = []
    ) -> OwnLoopRow? {
        Policy.ownLoopRow(
            Policy.ownLoop(
                ownership: ownership,
                state: state,
                review: review,
                handoff: handoff ?? handed(6),
                sync: sync,
                status: branchStatus ?? status(),
                checks: checks,
                reviewers: reviewers
            )
        )
    }

    // MARK: - Co se nekreslí

    @Test("Cizí PR řádek dráhy nemá")
    func drawsNothingOnForeignPullRequests() {
        #expect(row(ownership: .theirs) == nil)
        // A `nil` na vstupu je `nil` na výstupu: řádek bez storu (náhled, test) nemá dráhu
        // odkud vzít, a pět šedých koleček by tvrdilo, že se na tom PR nic nestalo.
        #expect(Policy.ownLoopRow(nil) == nil)
    }

    // MARK: - Tečky

    @Test("Teček je pět a jdou v pořadí, ve kterém se kolo jde")
    func hasFiveDotsInWalkOrder() throws {
        let drawn = try #require(row())

        #expect(drawn.dots.map(\.station) == OwnLoop.Station.allCases)
        #expect(drawn.dots.count == 5)
    }

    /// **Jeden zdroj, ne dvě odpovědi.** Kdyby si řádek stanice skládal sám, uměl by nad tímtéž
    /// PR ukázat jiné tečky než dráha v jeho hlavičce — a to se v okně nepozná jinak než tím, že
    /// se člověk dívá na obojí naráz. Testuje se to **nad celou maticí**, ne na jednom vzorku.
    @Test("Stav tečky je doslova stav stanice na dráze")
    func everyDotMatchesTheLane() throws {
        // **Matice se projde uvnitř testu, ne přes `arguments:`.** Vzorků jsou desetitisíce
        // a jako parametrizované případy by z nich byly desetitisíce řádků v protokolu běhu —
        // tvrzení je přitom jedno.
        for sample in Self.everySample {
            let loop = try #require(sample.loop, "vzorek \(sample) dráhu nedal")
            let drawn = try #require(Policy.ownLoopRow(loop))

            for dot in drawn.dots where dot.state != loop.state(of: dot.station) {
                Issue.record(
                    "\(sample): \(dot.station) v řádku \(dot.state), na dráze \(loop.state(of: dot.station))"
                )
            }
        }
    }

    // MARK: - Slovo

    @Test("Slovo je jméno aktivní stanice a její detail", arguments: [
        (ReviewState.notStarted, "Nálezy nespuštěno"),
        (.running(finished: 1, total: 3), "Nálezy 1/3"),
        (.failed(detail: "bum"), "Nálezy spadlo"),
        (.stale, "Nálezy zastaralé"),
    ])
    func namesTheActiveStationAndItsDetail(_ review: ReviewState, _ expected: String) throws {
        #expect(try #require(row(review: review)).word == expected)
    }

    @Test("Slovo mluví o té stanici, na které se walk zastavil")
    func speaksAboutTheStationTheWalkStoppedAt() throws {
        #expect(try #require(row(handoff: pendingHandoff(6))).word == "Zadání 6 k předání")
        #expect(try #require(row(status: status(behind: 4))).word == "Push o 4 vzadu")
        #expect(try #require(row(status: status(.conflicting, .dirty))).word == "Push konflikt")
        #expect(try #require(row(status: .loading)).word == "Push zjišťuju")
        #expect(try #require(row(checks: [check("build", .failed)])).word == "CI 1 neprošel")
        #expect(try #require(row(checks: nil)).word == "CI zjišťuju")
        #expect(
            try #require(row(reviewers: [RequestedReviewer(login: "a", answer: .changesRequested)])).word
                == "Review 1 chce změny"
        )
        #expect(
            try #require(row(reviewers: [RequestedReviewer(login: "a", answer: .waiting)])).word
                == "Review čeká 1"
        )
    }

    /// **Slovo nikdy nepřijde prázdné a vždycky začíná jménem stanice, nebo je to konec kola.**
    /// Prázdná pilulka je díra v řádku, ze které se nedá poznat, jestli se něco nespočítalo.
    @Test("Slovo je vždycky vyplněné")
    func alwaysSaysSomething() throws {
        for sample in Self.everySample {
            let loop = try #require(sample.loop)
            let drawn = try #require(Policy.ownLoopRow(loop))

            if drawn.word.isEmpty { Issue.record("\(sample): prázdné slovo") }
            if let active = loop.active {
                if !drawn.word.hasPrefix(active.title) {
                    Issue.record("\(sample): slovo `\(drawn.word)` nezačíná jménem stanice `\(active.title)`")
                }
            } else if !["hotovo", "zavřeno"].contains(drawn.word) {
                Issue.record("\(sample): dojetá smyčka řekla `\(drawn.word)`")
            }
        }
    }

    // MARK: - Konec kola

    @Test("Hotové kolo říká `hotovo`, ne `k merge`")
    func finishedLoopDoesNotClaimMergeability() throws {
        let drawn = try #require(row())

        #expect(drawn.word == "hotovo")
        #expect(drawn.tone == .done)
        #expect(drawn.dots.allSatisfy { $0.state == .done })
        // Slévatelnost tahle funkce nezná — odpovídá na ni pruh `K merge` (#515) a sekce `Větev`
        // (#465). Kdyby to tvrdila i dráha, byly by to dvě odpovědi na jednu otázku, každá
        // z jiných dat.
        #expect(!drawn.word.contains("merge"))
    }

    @Test("Mergnutý PR má pět hotových teček, zavřený pět nedojetých")
    func shortensTheLoopOnClosedPullRequests() throws {
        let merged = try #require(row(state: .merged, review: .notStarted, handoff: pendingHandoff(6)))
        #expect(merged.word == "hotovo")
        #expect(merged.dots.allSatisfy { $0.state == .done })

        let closed = try #require(row(state: .closed, review: .notStarted, handoff: pendingHandoff(6)))
        #expect(closed.word == "zavřeno")
        #expect(closed.tone == .stopped)
        #expect(closed.dots.allSatisfy { $0.state == .stopped })
    }

    // MARK: - Odstín

    @Test("Odstín je stav aktivní stanice")
    func toneIsTheActiveStationState() throws {
        for sample in Self.everySample {
            let loop = try #require(sample.loop)
            let drawn = try #require(Policy.ownLoopRow(loop))

            guard let active = loop.active else { continue }
            if drawn.tone != loop.state(of: active) {
                Issue.record("\(sample): odstín \(drawn.tone), stanice \(loop.state(of: active))")
            }
            // A **nikdy `idle`**: aktivní stanice je ta, na které se walk zastavil, takže se o ní
            // vždycky něco ví. `idle` v pilulce by znamenalo šedé slovo o tom, co je na tahu.
            if drawn.tone == .idle { Issue.record("\(sample): aktivní stanice vyšla `idle`") }
        }
    }

    // MARK: - Matice

    /// Jeden vzorek matice — **jméno se skládá až při pádu**, ne u každého z desetitisíců
    /// vzorků. Popis z asociovaných hodnot je dlouhý řetězec a matice se staví při každém běhu.
    struct Sample: CustomStringConvertible, Sendable {
        let review: ReviewState
        let handoff: HandoffReport
        let sync: BranchSyncState?
        let branch: BranchStatusState?
        let checks: [PullRequestCheck]?
        let reviewers: [RequestedReviewer]?
        let state: PullRequestState

        var loop: OwnLoop? {
            Policy.ownLoop(
                ownership: .mine,
                state: state,
                review: review,
                handoff: handoff,
                sync: sync,
                status: branch,
                checks: checks,
                reviewers: reviewers
            )
        }

        var description: String {
            "\(review) · \(handoff.pending) k předání · \(String(describing: sync)) · "
                + "\(String(describing: branch)) · \(String(describing: checks)) · "
                + "\(String(describing: reviewers)) · \(state)"
        }
    }

    /// **Matice, ne vybrané případy.** Řádek se skládá z dráhy, takže tvrzení „tečky sedí“ a
    /// „slovo je vyplněné“ musí platit nad vším, co dráha umí vydat — jinak by se dala vyrobit
    /// kombinace, ve které řádek mlčí, a nikdo by to nezjistil.
    static let everySample: [Sample] = {
        let green = [PullRequestCheck(name: "build", outcome: .passed, link: nil, startedAt: nil, completedAt: nil)]
        let red = [PullRequestCheck(name: "build", outcome: .failed, link: nil, startedAt: nil, completedAt: nil)]
        let ok = BranchStatusState.loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean, divergence: nil),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let behind = BranchStatusState.loaded(
            BranchStatus(
                mergeability: .mergeable,
                mergeState: .clean,
                divergence: BranchDivergence(ahead: 1, behind: 21)
            ),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let rebased = BranchSyncState.rebased(
            RebasedBranch(
                worktree: URL(filePath: "/tmp/566-sync"),
                headSha: "abc1234",
                rebasedFrom: "9c1de02",
                arriving: [],
                replayed: 2
            )
        )
        let clean = HandoffReport.never
        let waiting = HandoffReport(
            stage: .never, handoff: nil, pending: 6,
            freshDiscussion: [], staleFindings: 0, commits: nil
        )

        var samples: [Sample] = []
        let reviews: [ReviewState] = [
            .notStarted, .queued, .cloning, .running(finished: 1, total: 3),
            .checkoutFailed(detail: "bum"), .failed(detail: "bum"), .timedOut(findings: 0),
            .interrupted(findings: 0),
            .inconclusive(reason: .noReport), .stale, .clean, .completed(findings: 3), .dismissed(findings: 2),
        ]
        for review in reviews {
            for handoff in [clean, waiting] {
                for sync: BranchSyncState? in [nil, rebased, .conflicted(files: []), .rebasing] {
                    for branch: BranchStatusState? in [nil, .loading, .failed("gh"), ok, behind] {
                        for checks: [PullRequestCheck]? in [nil, [], green, red] {
                            for reviewers: [RequestedReviewer]? in [
                                nil, [],
                                [RequestedReviewer(login: "a", answer: .approved)],
                                [RequestedReviewer(login: "a", answer: .changesRequested)],
                                [RequestedReviewer(login: "a", answer: .waiting)],
                            ] {
                                for state in [PullRequestState.open, .draft, .merged, .closed] {
                                    samples.append(
                                        Sample(
                                            review: review,
                                            handoff: handoff,
                                            sync: sync,
                                            branch: branch,
                                            checks: checks,
                                            reviewers: reviewers,
                                            state: state
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        return samples
    }()
}
