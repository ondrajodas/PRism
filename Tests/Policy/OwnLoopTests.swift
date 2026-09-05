import Foundation
import Testing

@testable import PRism

/// Dráha smyčky vlastního PR (#508) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou ta záporná: na **cizím** PR se dráha nekreslí vůbec, nad
/// **nenačtenou** slévatelností se netvrdí `nejde` (#572), nad **mergnutým** PR se netvrdí, že
/// zbývá předat zadání, a stanice **za** aktivní netvrdí nic (`idle`). Všechna čtyři se rozbijí
/// potichu — dráha zůstane zelená a bude ukazovat vedle.
@Suite("Dráha smyčky vlastního PR (#508)")
struct OwnLoopTests {
    // MARK: - Stavba vstupů

    /// Report, ve kterém není co předávat — smyčka jím projde na `Agent`.
    private let nothingToHandOff = HandoffReport.never

    private func handed(
        _ count: Int,
        head: String? = "9c1de02aa1b2c3",
        at: Date = .init(timeIntervalSince1970: 100)
    ) -> HandoffReport {
        HandoffReport(
            stage: .delivered,
            handoff: Handoff(at: at, headSha: head, handed: Set((0..<count).map { "item-\($0)" })),
            pending: 0,
            freshDiscussion: [],
            staleFindings: 0,
            commits: nil
        )
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

    private func check(_ name: String, _ outcome: PullRequestCheck.Outcome) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: outcome, link: nil, startedAt: nil, completedAt: nil)
    }

    /// Smyčka, ve které **všechno projde**, dokud se v parametru neřekne jinak. Bez toho by každý
    /// test o jedné stanici musel vypsat šest ostatních, a to je zrovna ten způsob, jakým se
    /// z matice stane šum.
    private func walk(
        ownership: PullRequestOwnership = .mine,
        state: PullRequestState = .open,
        review: ReviewState = .clean,
        handoff: HandoffReport? = nil,
        sync: BranchSyncState? = nil,
        status branchStatus: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = [],
        reviewers: [RequestedReviewer]? = [],
        merge: Policy.MergeOffer = .allowed
    ) -> OwnLoop? {
        Policy.ownLoop(
            ownership: ownership,
            state: state,
            review: review,
            handoff: handoff ?? nothingToHandOff,
            sync: sync,
            status: branchStatus ?? status(),
            checks: checks,
            reviewers: reviewers,
            merge: merge
        )
    }

    // MARK: - Kde se dráha nekreslí

    /// **Na cizím PR se dráha nekreslí, ne zašedne.** Smyčka je „co udělám se svojí větví“;
    /// nad cizí je to nadpis bez obsahu — tatáž hranice jako u sekce `Větev` (#465).
    @Test("Cizí PR dráhu nemá")
    func foreignPullRequestHasNoLane() {
        #expect(walk(ownership: .theirs) == nil)
        // A není to jen o výchozích vstupech: ani nad rozpracovanou smyčkou se nekreslí.
        #expect(
            walk(
                ownership: .theirs,
                review: .completed(findings: 3),
                merge: .blocked([.failingChecks(["build"])])
            ) == nil
        )
    }

    // MARK: - Tvar dráhy

    /// Sedm stanic, vždycky a v pořadí. Kdyby jich dráha vydala míň, srovnat dvě dráhy vedle sebe
    /// by nešlo — a porovnání je jediný důvod, proč stanice stojí vedle sebe.
    @Test("Vždycky sedm stanic v pořadí smyčky")
    func sevenStationsInOrder() throws {
        #expect(OwnLoop.Station.allCases.count == 7)
        for reviewState in Self.everyReviewState {
            let loop = try #require(walk(review: reviewState))
            #expect(loop.stations.map(\.station) == OwnLoop.Station.allCases)
        }
    }

    /// **Walk**: co je před zastávkou, je hotové; co je za ní, je `idle`. Tvrdí to nad celou
    /// maticí, ne nad jedním případem — pořadí je to jediné, co dráha slibuje.
    @Test("Před zastávkou hotovo, za ní nic")
    func stationsAfterTheStopClaimNothing() throws {
        for (index, sample) in Self.matrix.enumerated() {
            let loop = try #require(sample.build(), "vzorek \(index)")
            guard let active = loop.active else {
                #expect(
                    loop.stations.allSatisfy { $0.state == .done || $0.state == .stopped },
                    "vzorek \(index): dráha bez zastávky nesmí mít rozdělanou stanici"
                )
                continue
            }
            let position = try #require(OwnLoop.Station.allCases.firstIndex(of: active))
            for (offset, stop) in loop.stations.enumerated() {
                if offset < position {
                    #expect(stop.state == .done, "vzorek \(index): \(stop.station) před zastávkou")
                } else if offset > position {
                    #expect(stop.state == .idle, "vzorek \(index): \(stop.station) za zastávkou")
                    #expect(stop.detail == nil, "vzorek \(index): \(stop.station) něco tvrdí")
                } else {
                    #expect(stop.state != .done && stop.state != .idle, "vzorek \(index): zastávka")
                }
            }
        }
    }

    /// Věta pod dráhou je vždycky, i když se nic neděje. Prázdný řádek by vypadal jako rozbitá
    /// kresba, a dráha bez věty neřekne, **co dělat**.
    @Test("Věta o tom, co je na tahu, nikdy nechybí")
    func lastSentenceIsNeverEmpty() throws {
        for (index, sample) in Self.matrix.enumerated() {
            let loop = try #require(sample.build(), "vzorek \(index)")
            #expect(!loop.last.isEmpty, "vzorek \(index)")
        }
    }

    /// Akci má jedině aktivní stanice — a **jen některá**. Akce nad dojetou smyčkou by byla
    /// nabídka bez místa, kam vede.
    @Test("Akce existuje jen se zastávkou")
    func moveNeedsAStop() throws {
        for (index, sample) in Self.matrix.enumerated() {
            let loop = try #require(sample.build(), "vzorek \(index)")
            if loop.active == nil { #expect(loop.move == nil, "vzorek \(index)") }
        }
    }

    // MARK: - Stanice Nálezy

    private static let everyReviewState: [ReviewState] = [
        .notStarted, .queued, .cloning, .checkoutFailed(detail: "fatal"),
        .running(finished: 1, total: 3), .clean, .completed(findings: 3), .dismissed(findings: 2),
        .inconclusive(reason: .droppedFindings), .inconclusive(reason: .noReport),
        .inconclusive(reason: .unreadCode), .failed(detail: "spadlo"), .timedOut(findings: 1),
        .interrupted(findings: 1), .stale,
    ]

    /// Vyčerpávající výčet stavů review: **které pustí smyčku dál a které ne**.
    @Test("Nálezy: jen doběhlé review pustí dál", arguments: OwnLoopTests.everyReviewState)
    func findingsStation(_ review: ReviewState) throws {
        let loop = try #require(walk(review: review))
        let passes = switch review {
        case .clean, .completed, .dismissed: true
        default: false
        }
        if passes {
            #expect(loop.state(of: .findings) == .done)
            #expect(loop.active != .findings)
        } else {
            #expect(loop.active == .findings, "\(review) nesmí projít")
            #expect(loop.state(of: .findings) != .done)
            // **Stanice `Nálezy` nikdy nenabízí akci** (#508, z proklikání): `Spustit review` stojí
            // v hlavičce a #218 mu vyhradilo jediné akcentové místo v pruhu. Rozbije se to potichu
            // — druhé tlačítko nic neshodí, jen z hlavičky udělá semafor.
            #expect(loop.move == nil, "\(review) nesmí mít akci na dráze")
        }
    }

    /// **Neprůkazné review smyčku zastaví, a je to `unknown`, ne `failed`** (#383). Kdyby
    /// prošlo, přečetlo by se jako `čisto` — a přesně proti tomu ten stav vznikl.
    @Test("Neprůkazné review zastaví a nelže o tom")
    func inconclusiveStops() throws {
        for reason in InconclusiveReason.allCases {
            let loop = try #require(walk(review: .inconclusive(reason: reason)))
            #expect(loop.active == .findings)
            #expect(loop.state(of: .findings) == .unknown)
            // **Bez akce**: `Spustit review` stojí v hlavičce a druhá kopie na dráze by z ní
            // udělala semafor (#218, rozhodnuto v #508 po proklikání).
            #expect(loop.move == nil)
        }
    }

    // MARK: - Stanice Zadání a Agent

    /// Vyčerpávající výčet stavů předání. **Rozhoduje `pending`, ne `stage`** — `changed` s nulou
    /// (nová hlava, žádná položka) je platný stav a zastávka by v něm neměla obsah.
    @Test("Zadání: zastaví se, jen když něco zbývá")
    func handoffStation() throws {
        let cases: [(HandoffReport, Bool)] = [
            (.never, false),
            (report(.never, pending: 4), true),
            (
                report(
                    .unverified,
                    pending: 2,
                    stamp: Handoff(at: .init(timeIntervalSince1970: 1), headSha: nil, handed: ["a"])
                ),
                true
            ),
            (report(.outdated, pending: 6, stale: 3, movedHead: true), true),
            (report(.changed, pending: 1), true),
            (report(.changed, pending: 0, movedHead: true), false),
            (handed(6), false),
        ]
        for (report, stops) in cases {
            let loop = try #require(walk(handoff: report))
            if stops {
                #expect(loop.active == .handoff, "\(report.stage) / \(report.pending)")
                #expect(loop.state(of: .handoff) == .running)
                #expect(loop.move == .openHandoff)
            } else {
                #expect(loop.state(of: .handoff) == .done, "\(report.stage) / \(report.pending)")
            }
        }
    }

    /// **Agent netvrdí, že běží** (#508; živý obsah dodá #511). Aplikace o cizím terminálu neví
    /// nic, takže je stanice `unknown` — `running` by bylo tvrzení, které data neunesou.
    @Test("Agent: předáno a čekám na commit je nevím, ne běží")
    func agentDoesNotClaimARunningSession() throws {
        let delivered = try #require(walk(handoff: handed(6)))
        #expect(delivered.active == .agent)
        #expect(delivered.state(of: .agent) == .unknown)
        #expect(delivered.move == nil, "dokud se neví, není co nabídnout")

        // Commit dorazil → agent svoje odvedl a smyčka jde dál.
        let moved = try #require(walk(handoff: report(.changed, pending: 0, movedHead: true)))
        #expect(moved.state(of: .agent) == .done)
        #expect(moved.active != .agent)

        // Nikdy se nepředávalo → agent nemá co dělat a `čekám na commit` by tam viselo navždycky.
        let never = try #require(walk(handoff: .never))
        #expect(never.state(of: .agent) == .done)
    }

    private func report(
        _ stage: HandoffReport.Stage,
        pending: Int,
        stale: Int = 0,
        movedHead: Bool = false,
        stamp: Handoff? = nil
    ) -> HandoffReport {
        HandoffReport(
            stage: stage,
            handoff: stage == .never
                ? nil
                : (stamp ?? Handoff(at: .init(timeIntervalSince1970: 1), headSha: "9c1de02", handed: ["a"])),
            pending: pending,
            freshDiscussion: [],
            staleFindings: stale,
            commits: nil,
            hasMovedHead: movedHead
        )
    }

    // MARK: - Stanice Push

    /// Vyčerpávající výčet stavů větve v cache. **Rozdělaná práce přebíjí GitHub** — ten o rebase
    /// v cache neví vůbec, takže by nad ní tvrdil `srovnaná`.
    @Test("Push: co leží v cache, přebíjí stav na GitHubu")
    func pushStationReadsTheCacheFirst() throws {
        let rebased = RebasedBranch(
            worktree: URL(filePath: "/tmp/499-sync"),
            headSha: "abc1234",
            rebasedFrom: "9c1de02",
            arriving: [],
            replayed: 2
        )
        let cases: [(BranchSyncState, ReviewerLane.PhaseState)] = [
            (.rebasing, .running),
            (.resolving(round: 1, files: ["a.swift"]), .running),
            (.pushing, .running),
            (.discarding, .running),
            (.rebased(rebased), .running),
            (.conflicted(files: ["a.swift"]), .failed),
            (.unfinished(files: []), .failed),
            (.unresolved(files: ["a.swift"], detail: nil), .failed),
            (.failed(.leaseRejected), .failed),
        ]
        for (sync, expected) in cases {
            let loop = try #require(walk(sync: sync))
            #expect(loop.active == .push, "\(sync)")
            #expect(loop.state(of: .push) == expected, "\(sync)")
            #expect(loop.move == .openBranch, "\(sync)")
        }
        // Doběhlé srovnání o **dnešní** poloze větve nerozhoduje — tu řekne `BranchStatus`.
        for sync in [BranchSyncState.pushed(replayed: 2), .alreadyInSync] {
            let loop = try #require(walk(sync: sync))
            #expect(loop.state(of: .push) == .done, "\(sync)")
        }
    }

    /// Vyčerpávající výčet toho, co o větvi říká GitHub.
    @Test("Push: poloha větve nad základem")
    func pushStationReadsBranchStatus() throws {
        for state in BranchStatus.MergeState.allCases {
            let loop = try #require(walk(status: status(.mergeable, state)))
            let stops = state == .behind || state == .dirty
            #expect((loop.active == .push) == stops, "\(state)")
        }
        // Konflikt je konflikt, ať `mergeStateStatus` říká cokoli.
        let conflicting = try #require(walk(status: status(.conflicting, .clean)))
        #expect(conflicting.state(of: .push) == .failed)
        // Počet z `compare` (#466) — `mergeStateStatus` na tuhle otázku neodpovídá.
        let behind = try #require(walk(status: status(.mergeable, .clean, behind: 4)))
        #expect(behind.active == .push)
        #expect(behind.stations.first { $0.station == .push }?.detail == "o 4 vzadu")
    }

    /// **„Nevím“ je odpověď, ne „nejde“** (#572): stav větve se dotahuje až s detailem, takže hned
    /// po startu se o ní nedá tvrdit nic — a `failed` by nad nevratnou akcí byla ta nejdražší
    /// strana omylu.
    @Test("Push: nenačtený stav je nevím, ne porucha")
    func pushStationDoesNotGuess() throws {
        for state: BranchStatusState in [.loading, .failed("gh spadlo")] {
            let loop = try #require(walk(status: state))
            #expect(loop.active == .push, "\(state)")
            #expect(loop.state(of: .push) == .unknown, "\(state)")
            #expect(loop.move == nil, "nad nevědomím se nic nenabízí")
        }
        // A `nil` doopravdy: chybějící stav se nesmí tvářit jako načtený.
        let missing = Policy.ownLoop(
            ownership: .mine,
            state: .open,
            review: .clean,
            handoff: .never,
            checks: [],
            reviewers: [],
            merge: .allowed
        )
        #expect(missing?.active == .push)
        #expect(missing?.state(of: .push) == .unknown)
    }

    // MARK: - Stanice CI

    /// **`nil` a `[]` se nesmí slít**: nenačtené checky jsou „nevím“, prázdné pole odpověď
    /// „tenhle PR nemá CI“ — a to je běžný stav, ne porucha.
    @Test("CI: nenačteno není bez checků")
    func checksStation() throws {
        let loading = try #require(walk(checks: nil))
        #expect(loading.active == .ci)
        #expect(loading.state(of: .ci) == .unknown)

        let none = try #require(walk(checks: []))
        #expect(none.state(of: .ci) == .done)
        #expect(none.stations.first { $0.station == .ci }?.detail == "bez checků")

        let green = try #require(walk(checks: [check("build", .passed)]))
        #expect(green.state(of: .ci) == .done)

        let skipped = try #require(walk(checks: [check("build", .skipped)]))
        #expect(skipped.state(of: .ci) == .done)
        #expect(skipped.stations.first { $0.station == .ci }?.detail == "přeskočeno")

        let running = try #require(walk(checks: [check("build", .running), check("test", .passed)]))
        #expect(running.active == .ci)
        #expect(running.state(of: .ci) == .running)
        #expect(running.move == .openChecks)

        // Nejhorší vyhrává: dvanáct zelených a jeden červený je červený stav.
        let red = try #require(
            walk(checks: [check("build", .failed), check("test", .passed), check("lint", .running)])
        )
        #expect(red.active == .ci)
        #expect(red.state(of: .ci) == .failed)

        // Zrušený se počítá ke spadlým, jako v `Policy.summary(of:)`.
        let cancelled = try #require(walk(checks: [check("build", .cancelled)]))
        #expect(cancelled.state(of: .ci) == .failed)
    }

    // MARK: - Stanice Review

    /// Vyčerpávající výčet odpovědí reviewera. **`čeká` nemá akci** — čekat na kolegu není můj tah.
    @Test("Review: chce změny blokuje, čeká jen zdrží")
    func reviewStation() throws {
        let unknown = try #require(walk(reviewers: nil))
        #expect(unknown.active == .review)
        #expect(unknown.state(of: .review) == .unknown)

        let empty = try #require(walk(reviewers: []))
        #expect(empty.state(of: .review) == .done)

        let approved = try #require(walk(reviewers: [RequestedReviewer(login: "a", answer: .approved)]))
        #expect(approved.state(of: .review) == .done)

        let waiting = try #require(
            walk(reviewers: [
                RequestedReviewer(login: "a", answer: .approved),
                RequestedReviewer(login: "b", answer: .waiting),
            ])
        )
        #expect(waiting.active == .review)
        #expect(waiting.state(of: .review) == .running)
        #expect(waiting.move == nil, "čekat na kolegu není můj tah")

        // `chce změny` přebíjí `čeká`: je to jediná odpověď, která něco blokuje.
        let changes = try #require(
            walk(reviewers: [
                RequestedReviewer(login: "a", answer: .waiting),
                RequestedReviewer(login: "b", answer: .changesRequested),
            ])
        )
        #expect(changes.state(of: .review) == .failed)
        #expect(changes.move == .openConversation)
    }

    // MARK: - Stanice Merge

    /// Vyčerpávající výčet překážek merge. **Ty, které znamenají „ještě nevím“, se nesmí kreslit
    /// jako `nejde`** (#572) — a je to tatáž hranice, kterou drží `MergeObstacle` sám.
    @Test("Merge: nevím a nejde se nesmí slít", arguments: OwnLoopTests.everyObstacle)
    func mergeStation(_ obstacle: Policy.MergeObstacle) throws {
        let loop = try #require(walk(merge: .blocked([obstacle])))
        #expect(loop.active == .merge, "\(obstacle)")
        if obstacle.isUnknownYet {
            #expect(loop.state(of: .merge) == .unknown, "\(obstacle)")
            #expect(loop.move == nil, "\(obstacle): nad nevědomím se nic nenabízí")
        } else {
            #expect(loop.state(of: .merge) == .failed, "\(obstacle)")
            #expect(loop.move == .openBranch, "\(obstacle)")
        }
        #expect(loop.last == obstacle.sentence, "\(obstacle): věta se skládá u případu")
    }

    /// Zeleno je zastávka, ne konec: mergnout musí člověk, a je to nevratné.
    @Test("Merge: zeleno je můj tah")
    func mergeAllowedIsAStop() throws {
        let loop = try #require(walk(merge: .allowed))
        #expect(loop.active == .merge)
        #expect(loop.state(of: .merge) == .running)
        #expect(loop.move == .openBranch)
    }

    /// `isUnknownYet` výčtem — je to jediné místo, které rozhoduje, co je „ještě nevím“.
    @Test("Které překážky znamenají nevím", arguments: OwnLoopTests.everyObstacle)
    func unknownObstacles(_ obstacle: Policy.MergeObstacle) {
        let expected = switch obstacle {
        case .factsMissing, .statusLoading, .statusFailed, .statusUnknown: true
        default: false
        }
        #expect(obstacle.isUnknownYet == expected, "\(obstacle)")
    }

    private static let everyObstacle: [Policy.MergeObstacle] = [
        .notAllowed("Odesílání je vypnuté."),
        .factsMissing,
        .statusLoading,
        .statusFailed("gh spadlo"),
        .statusUnknown,
        .conflicting(base: "main"),
        .behind(base: "main"),
        .protected,
        .draftPullRequest,
        .notOpen(.closed),
        .failingChecks(["build"]),
    ]

    // MARK: - Mergnutý a zavřený PR

    /// **Nad mergnutým PR se netvrdí, že zbývá předat zadání.** Bez téhle zkratky by walk zastavil
    /// tam, kde zrovna zbylo něco nepředaného — a to je rada, kterou nemá kdo splnit.
    @Test("Mergnutý PR má smyčku dojetou")
    func mergedLoopIsDone() throws {
        let loop = try #require(
            walk(
                state: .merged,
                review: .completed(findings: 3),
                handoff: report(.never, pending: 6),
                sync: .conflicted(files: ["a.swift"]),
                checks: [check("build", .failed)],
                merge: .blocked([.notOpen(.merged)])
            )
        )
        #expect(loop.active == nil)
        #expect(loop.move == nil)
        #expect(loop.stations.allSatisfy { $0.state == .done })
        #expect(loop.last.contains("Mergnuto"))
    }

    /// Zavřený PR není hotová smyčka — je to smyčka, která nikam nevede. `stopped` je ta hodnota,
    /// kterou dráha reviewera používá pro „nedoběhlo“, takže se nový stav nezavádí.
    @Test("Zavřený PR není hotový")
    func closedLoopIsStopped() throws {
        let loop = try #require(walk(state: .closed, handoff: report(.never, pending: 6)))
        #expect(loop.active == nil)
        #expect(loop.stations.allSatisfy { $0.state == .stopped })
        #expect(!loop.last.contains("Mergnuto"))
    }

    /// Draft smyčku nezkracuje — pracuje se na něm dál, jenom se nedá mergnout.
    @Test("Draft se smyčkou prochází jako otevřený")
    func draftWalksTheLoop() throws {
        let loop = try #require(walk(state: .draft, merge: .blocked([.draftPullRequest])))
        #expect(loop.active == .merge)
        #expect(loop.state(of: .merge) == .failed)
    }

    // MARK: - Razítko v hlavičce

    @Test("Razítko se kreslí jen tam, kde se předávalo")
    func stampFollowsTheHandoff() throws {
        #expect(try #require(walk(handoff: .never)).stamp == nil)
        let stamped = try #require(walk(handoff: handed(6)))
        #expect(stamped.stamp == "předáno 6 položek · proti 9c1de02")
        // Bez hlavy se hlava netvrdí — razítko o ní mlčí, místo aby si ji vymyslelo.
        let headless = try #require(walk(handoff: handed(1, head: nil)))
        #expect(headless.stamp == "předáno 1 položka")
    }

    // MARK: - Matice

    /// Jeden vzorek matice `handoff × větev × CI × review × merge`. Skládá se ve struktuře, ne
    /// v poli hotových `OwnLoop`ů: helper `walk(…)` je metoda suity a `arguments:` by ho neviděl.
    private struct Sample {
        let review: ReviewState
        let handoff: HandoffReport
        let sync: BranchSyncState?
        let status: BranchStatusState?
        let checks: [PullRequestCheck]?
        let reviewers: [RequestedReviewer]?
        let merge: Policy.MergeOffer
        let state: PullRequestState

        func build() -> OwnLoop? {
            Policy.ownLoop(
                ownership: .mine,
                state: state,
                review: review,
                handoff: handoff,
                sync: sync,
                status: status,
                checks: checks,
                reviewers: reviewers,
                merge: merge
            )
        }
    }

    /// Kříž přes všech pět os. **Ne kartézský součin všeho** — ten by měl tisíce prvků a testoval
    /// by pořád totéž pravidlo; tohle je po jedné ose měněná sada, kterou se dá projít pohledem.
    private static let matrix: [Sample] = {
        let clean = HandoffReport.never
        let pending = HandoffReport(
            stage: .never, handoff: nil, pending: 4, freshDiscussion: [], staleFindings: 0, commits: nil
        )
        let delivered = HandoffReport(
            stage: .delivered,
            handoff: Handoff(at: Date(timeIntervalSince1970: 1), headSha: "9c1de02", handed: ["a"]),
            pending: 0,
            freshDiscussion: [],
            staleFindings: 0,
            commits: nil
        )
        let ok = BranchStatusState.loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let green = [PullRequestCheck(name: "build", outcome: .passed, link: nil, startedAt: nil, completedAt: nil)]
        let red = [PullRequestCheck(name: "build", outcome: .failed, link: nil, startedAt: nil, completedAt: nil)]

        var samples: [Sample] = []
        for review in everyReviewState {
            samples.append(
                Sample(
                    review: review, handoff: clean, sync: nil, status: ok, checks: green,
                    reviewers: [], merge: .allowed, state: .open
                )
            )
        }
        for handoff in [clean, pending, delivered] {
            for checks in [green, red, nil] {
                for merge in [Policy.MergeOffer.allowed, .blocked([.statusLoading]), .blocked([.protected])] {
                    samples.append(
                        Sample(
                            review: .clean, handoff: handoff, sync: nil, status: ok, checks: checks,
                            reviewers: [], merge: merge, state: .open
                        )
                    )
                }
            }
        }
        for sync: BranchSyncState? in [nil, .rebasing, .conflicted(files: []), .pushed(replayed: 1)] {
            for status: BranchStatusState? in [nil, .loading, .failed("gh"), ok] {
                samples.append(
                    Sample(
                        review: .clean, handoff: delivered, sync: sync, status: status, checks: green,
                        reviewers: [RequestedReviewer(login: "a", answer: .waiting)],
                        merge: .allowed, state: .open
                    )
                )
            }
        }
        for state in [PullRequestState.open, .draft, .merged, .closed] {
            samples.append(
                Sample(
                    review: .completed(findings: 2), handoff: pending, sync: nil, status: ok,
                    checks: red, reviewers: nil, merge: .blocked([.notOpen(state)]), state: state
                )
            )
        }
        return samples
    }()
}
