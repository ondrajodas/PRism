import Foundation
import Testing

@testable import PRism

/// Dráha smyčky vlastního PR (#508) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou ta záporná: na **cizím** PR se dráha nekreslí vůbec, nad
/// **mergnutým** PR se netvrdí, že zbývá předat zadání, stanice za zastávkou **nezezelená
/// z neznámých ani neaktuálních dat** (#508, druhé kolo) a od čtvrtého kola **nedostane ani
/// důvod, který neplatí**: stanice, která se kvůli chybějícím faktům nevyhodnocovala, mlčí.
/// Všechna se rozbijí potichu — dráha zůstane hezká a bude ukazovat vedle.
@Suite("Dráha smyčky vlastního PR (#508)")
struct OwnLoopTests {
    // MARK: - Stavba vstupů

    /// Report, ve kterém není co předávat — smyčka jím projde na `Push`.
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

    /// Přerovnaná, **nepřetlačená** větev — commity leží ve stromě v cache a v remote nejsou.
    private static let rebasedBranch = RebasedBranch(
        worktree: URL(filePath: "/tmp/566-sync"),
        headSha: "abc1234",
        rebasedFrom: "9c1de02",
        arriving: [],
        replayed: 2
    )

    private func check(_ name: String, _ outcome: PullRequestCheck.Outcome) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: outcome, link: nil, startedAt: nil, completedAt: nil)
    }

    /// Smyčka, ve které **všechno projde**, dokud se v parametru neřekne jinak. Bez toho by každý
    /// test o jedné stanici musel vypsat čtyři ostatní, a to je zrovna ten způsob, jakým se
    /// z matice stane šum.
    private func walk(
        ownership: PullRequestOwnership = .mine,
        state: PullRequestState = .open,
        review: ReviewState = .clean,
        handoff: HandoffReport? = nil,
        sync: BranchSyncState? = nil,
        status branchStatus: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = [],
        reviewers: [RequestedReviewer]? = []
    ) -> OwnLoop? {
        Policy.ownLoop(
            ownership: ownership,
            state: state,
            review: review,
            handoff: handoff ?? nothingToHandOff,
            sync: sync,
            status: branchStatus ?? status(),
            checks: checks,
            reviewers: reviewers
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
                checks: [check("build", .failed)]
            ) == nil
        )
    }

    // MARK: - Tvar dráhy

    /// **Pět stanic, vždycky a v pořadí** — a je to změna proti prvnímu kolu (#508, čtvrté kolo).
    ///
    /// `Agent` a `Merge` odešly, protože v okně nikdy nic neukázaly: první nemá živý obsah
    /// (aplikace o cizím terminálu neví nic), druhá stojí na celém kole, takže je prakticky
    /// vždycky šedá. Že jich je pět, se tvrdí **číslem i výčtem**: kdyby se některá vrátila jen
    /// do `allCases`, dráha by o ní mlčky nakreslila prázdnou kapsli.
    @Test("Vždycky pět stanic v pořadí smyčky")
    func fiveStationsInOrder() throws {
        #expect(OwnLoop.Station.allCases.count == 5)
        #expect(OwnLoop.Station.allCases == [.findings, .handoff, .push, .ci, .review])
        #expect(OwnLoop.Station.allCases.map(\.title) == ["Nálezy", "Zadání", "Push", "CI", "Review"])
        for reviewState in Self.everyReviewState {
            let loop = try #require(walk(review: reviewState))
            #expect(loop.stations.map(\.station) == OwnLoop.Station.allCases)
        }
    }

    /// **Walk**: co je před zastávkou, je hotové; za ní je jedině `done`, nebo `idle`.
    ///
    /// **Rozdělaná stanice smí být nejvýš jedna — ta aktivní** (#508, druhé kolo). Kdyby jich bylo
    /// víc, věta pod dráhou by mluvila o jedné z nich a nedalo by se poznat o které.
    ///
    /// **Šedá stanice smí od čtvrtého kola mít text, ale jedině jedno slovo bez čísla.** Číslo
    /// v šedé kapsli se nad cizí větou čte jako tvrzení o tom, co je zrovna na tahu — a přesně
    /// tomu se dráha vyhýbá. Je to zároveň jediná stráž nad tím, že se do šedé kapsle nedostane
    /// `detail` aktivní stanice (`o 21 vzadu`, `3 neprošly`) místo `reason`u.
    @Test("Před zastávkou hotovo, za ní zelená nebo jedno slovo")
    func stationsAfterTheStopAreDoneOrSilent() throws {
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
                    #expect(
                        stop.state == .done || stop.state == .idle,
                        "vzorek \(index): \(stop.station) za zastávkou je rozdělaná"
                    )
                    if stop.state == .idle, let word = stop.detail {
                        #expect(
                            Self.isSingleWord(word),
                            "vzorek \(index): \(stop.station) má za zastávkou „\(word)“"
                        )
                    }
                } else {
                    #expect(stop.state != .done && stop.state != .idle, "vzorek \(index): zastávka")
                }
            }
        }
    }

    /// Jedno slovo: neprázdné, bez mezery a **bez číslice**. Počet patří do detailu aktivní
    /// stanice, kterou pod fázemi vysvětluje věta — v šedé kapsli by tvrdil víc, než unese.
    private static func isSingleWord(_ word: String) -> Bool {
        !word.isEmpty && !word.contains(" ") && !word.contains(where: \.isNumber)
    }

    // MARK: - Co smí zezelenat za zastávkou

    /// **Případ #566 doslova: schváleno, CI zeleně, walk stojí na `Zadání`.**
    ///
    /// Tohle je ta změna zadání z proklikání (#508, druhé kolo): do ní byly `CI` i `Review` šedé,
    /// protože se walk zastavil dřív. Fakta o nich jsou přitom **známá a aktuální** — kód je
    /// pushnutý, checky nad touhle hlavou doběhly a schválení platí.
    @Test("Za zastávkou zelená stanice: schváleno a CI zeleně nad nepředaným zadáním")
    func doneStationsShowPastTheStop() throws {
        let loop = try #require(
            walk(
                review: .completed(findings: 6),
                handoff: report(.never, pending: 1),
                status: status(.mergeable, .clean),
                checks: [check("build", .passed), check("test", .passed)],
                reviewers: [RequestedReviewer(login: "kolega", answer: .approved)]
            )
        )
        // Aktivní stanice se změnou nehýbe: pořád první nehotová, pořád s větou a akcí.
        #expect(loop.active == .handoff)
        #expect(loop.move == .openHandoff)
        #expect(loop.state(of: .handoff) == .running)

        // A za ní zezelená, co je hotové.
        #expect(loop.state(of: .push) == .done)
        #expect(loop.state(of: .ci) == .done)
        #expect(loop.state(of: .review) == .done)
        #expect(loop.detail(of: .ci) == "zeleno")
        #expect(loop.detail(of: .review) == "schváleno")
    }

    /// **Nenačtená data se nesmí kreslit jako hotová.** Je to ten vzor, který Copilot v tomhle repu
    /// nachází opakovaně: text, který tvrdí víc, než data unesou. `nil` u checků ani u reviewerů
    /// není zeleno — a nad zastávkou se to pozná jedině tím, že zůstane `idle`.
    @Test("Za zastávkou nezezelená to, co se neví")
    func unknownFactsNeverGoGreenPastTheStop() throws {
        let noChecks = try #require(
            walk(handoff: report(.never, pending: 2), checks: nil, reviewers: [])
        )
        #expect(noChecks.active == .handoff)
        #expect(noChecks.state(of: .ci) == .idle, "nenačtené checky nejsou zeleno")
        // A od čtvrtého kola k tomu řekne **proč** — `zjišťuju`, ne `neprošlo`.
        #expect(noChecks.detail(of: .ci) == "zjišťuju")

        let noReviewers = try #require(
            walk(handoff: report(.never, pending: 2), checks: [], reviewers: nil)
        )
        #expect(noReviewers.active == .handoff)
        #expect(noReviewers.state(of: .review) == .idle, "nenačtení reviewery nejsou zeleno")
        #expect(noReviewers.detail(of: .review) == "zjišťuju")

        // Červené checky za zastávkou taky nezezelenají — a nekreslí se jako druhá porucha.
        let red = try #require(
            walk(handoff: report(.never, pending: 2), checks: [check("build", .failed)])
        )
        #expect(red.active == .handoff)
        #expect(red.state(of: .ci) == .idle, "spadlý check za zastávkou není druhá červená kapsle")
        #expect(red.detail(of: .ci) == "neprošlo")
    }

    /// **Nepřetlačená práce v cache drží `CI` a `Review` šedé** — a je to ta jediná půlka
    /// původního zdůvodnění, která platí. Dokud commity leží ve stromě v cache a v remote nejsou,
    /// je zelený check věta o **minulém** pushi.
    @Test("Nepřetlačená práce v cache drží CI a Review šedé i nad zelenými daty")
    func unpushedWorkKeepsTheHeadStationsSilent() throws {
        let cases: [(String, BranchSyncState)] = [
            ("přerovnáno, nepřetlačeno", .rebased(Self.rebasedBranch)),
            ("konflikt v cache", .conflicted(files: ["a.swift"])),
            ("nedokončený rebase", .unfinished(files: ["a.swift"])),
            ("nerozřešený konflikt", .unresolved(files: ["a.swift"], detail: nil)),
            ("push spadl", .failed(.leaseRejected)),
            ("zrovna se rebasuje", .rebasing),
            ("zrovna se pushuje", .pushing),
            ("agent opravuje", .fixing(items: 3)),
            ("výsledek agenta nepřijat", .fixRejected(detail: "Zapsala mimo strom.")),
        ]
        for (name, sync) in cases {
            let loop = try #require(
                walk(
                    sync: sync,
                    checks: [check("build", .passed)],
                    reviewers: [RequestedReviewer(login: "kolega", answer: .approved)]
                )
            )
            #expect(loop.active == .push, "\(name)")
            #expect(loop.state(of: .ci) == .idle, "\(name): CI mluví o jiné hlavě")
            #expect(loop.state(of: .review) == .idle, "\(name): Review mluví o jiné hlavě")
        }
    }

    /// **Poloha větve proti základu hlavou nehýbe** (#508, třetí kolo — mění druhé).
    ///
    /// Tohle je ta vada, kterou nahlásil uživatel na `keboola/platform-libraries#566`: PR
    /// schválený, CI zelené, a dráha přesto obojí zhasla — protože byla větev o jednadvacet
    /// commitů pozadu a `Push` tím nebyl hotový. Pozadu, konflikt se základem i nezjištěný stav
    /// větve jsou **fakta o poloze**, ne o tom, čí je hlava na GitHubu; checky nad ní doběhly
    /// a schválení na ni platí. `Push` si přitom svoje dál říká sám — proto se tvrdí i to, že
    /// zastávka zůstala na něm.
    @Test("Větev pozadu ani nezjištěný stav CI a Review nezhasne")
    func branchPositionDoesNotSilenceTheHeadStations() throws {
        // `nil` (ještě se neptalo) v `walk` vyjádřit nejde — helper si dosadí srovnanou větev —,
        // a je to totéž jako `.loading`: `pushStep` je bere jednou větví.
        let cases: [(String, BranchStatusState)] = [
            ("o 21 commitů pozadu (#566)", status(.mergeable, .clean, behind: 21)),
            ("za základem", status(.mergeable, .behind)),
            ("konflikt se základem", status(.conflicting, .dirty)),
            ("stav se nedotáhl", .loading),
            ("stav se nepodařilo zjistit", .failed("gh spadlo")),
        ]
        for (name, branch) in cases {
            let loop = try #require(
                walk(
                    status: branch,
                    checks: [check("build", .passed)],
                    reviewers: [RequestedReviewer(login: "kolega", answer: .approved)]
                )
            )
            #expect(loop.active == .push, "\(name): zastávka zůstává na Pushi")
            #expect(loop.state(of: .push) != .done, "\(name): Push si svoje říká dál")
            #expect(loop.state(of: .ci) == .done, "\(name): checky nad touhle hlavou doběhly")
            #expect(loop.state(of: .review) == .done, "\(name): schválení na tuhle hlavu platí")
        }
    }

    /// **Uvolnilo se jen to, co se uvolnit mělo.** Nad toutéž větví pozadu zůstává „nevím“
    /// šedé a spadlé červené se za zastávkou nekreslí — jinak by z opravy vzniklo tvrzení
    /// z chybějících dat, tedy přesně ten vzor, kvůli kterému pravidlo vzniklo.
    @Test("Nad větví pozadu nezezelená to, co se neví ani co spadlo")
    func branchPositionDoesNotTurnUnknownFactsGreen() throws {
        let behind = status(.mergeable, .clean, behind: 21)

        let noChecks = try #require(walk(status: behind, checks: nil, reviewers: []))
        #expect(noChecks.active == .push, "zastávka je pořád na Pushi")
        #expect(noChecks.state(of: .ci) == .idle, "nenačtené checky nejsou zeleno")

        let noReviewers = try #require(walk(status: behind, checks: [], reviewers: nil))
        #expect(noReviewers.active == .push)
        #expect(noReviewers.state(of: .review) == .idle, "nenačtení reviewery nejsou zeleno")

        let red = try #require(
            walk(
                status: behind,
                checks: [check("build", .failed)],
                reviewers: [RequestedReviewer(login: "kolega", answer: .changesRequested)]
            )
        )
        #expect(red.active == .push)
        #expect(red.state(of: .ci) == .idle, "spadlé checky se za zastávkou nekreslí")
        #expect(red.state(of: .review) == .idle, "chce změny za zastávkou nezezelená")
    }

    /// **`Push` na ničem nestojí, `Nálezy` taky ne** — a je to ten rozdíl, kvůli kterému má #566
    /// zelené kapsle. Nepředané zadání z pushnuté a srovnané větve nedělá nepravdu.
    @Test("Push zezelená i nad zastávkou na Nálezech a na Zadání")
    func pushDoesNotDependOnEarlierStations() throws {
        for review in [ReviewState.notStarted, .running(finished: 1, total: 3), .stale] {
            let loop = try #require(walk(review: review, checks: [check("build", .passed)]))
            #expect(loop.active == .findings, "\(review)")
            #expect(loop.state(of: .push) == .done, "\(review): větev je pushnutá, ať review dělá co chce")
            #expect(loop.state(of: .ci) == .done, "\(review): checky nad touhle hlavou doběhly")
            #expect(loop.state(of: .handoff) == .idle, "\(review): zadání stojí na nálezech")
        }
    }

    /// Výčet předpokladů — **jediné místo, které o hranici rozhoduje**, takže se tvrdí jmenovitě,
    /// a od třetího kola nad **oběma** podobami větve. Kdyby `.push` přibyl `CI` a `Review`
    /// natvrdo, byla by zpátky vada z `#566`.
    @Test("Na čem stojí fakta které stanice", arguments: OwnLoop.Station.allCases)
    func factsOfEachStation(_ station: OwnLoop.Station) {
        // Vlevo větev, o které se **neví**, že by byla rozešlá; vpravo nepřetlačená práce v cache.
        let expected: (Set<OwnLoop.Station>, Set<OwnLoop.Station>) = switch station {
        case .findings: ([], [])
        case .handoff: ([.findings], [.findings])
        case .push: ([], [])
        case .ci, .review: ([], [.push])
        }
        let quiet = Policy.ownLoopFacts(of: station)
        let unpushed = Policy.ownLoopFacts(of: station, branch: .rebased(Self.rebasedBranch))
        #expect(quiet == expected.0, "\(station): bez rozdělané práce")
        #expect(unpushed == expected.1, "\(station): s nepřetlačenou prací v cache")
        // Předpoklad smí být jedině **dřívější** stanice — jinak by se dráha nedala projít jedním
        // průchodem a `done` by odpovídalo na otázku, na kterou se ještě neptalo. Iteruje se přes
        // to, co funkce **vydala**, ne přes očekávání: jinak by nový pozdější předpoklad prošel.
        let position = OwnLoop.Station.allCases.firstIndex(of: station)
        for fact in quiet.union(unpushed) {
            #expect(
                (OwnLoop.Station.allCases.firstIndex(of: fact) ?? 0) < (position ?? 0),
                "\(station) stojí na pozdější \(fact)"
            )
        }
    }

    /// **Co se počítá za „práce, která na GitHubu ještě není“** — výčtem přes všechny stavy
    /// srovnání větve. Rozdíl mezi nimi je jediná věc, která `CI` a `Review` zhasíná, takže se
    /// tvrdí jmenovitě: `.pushed` a `.alreadyInSync` jsou hotové odpovědi, `nil` je „nevím
    /// o ničem“ (ne důkaz), zbytek drží commity v cache.
    @Test("Které stavy srovnání drží hlavu mimo GitHub")
    func syncStatesThatHoldTheHeadBack() {
        // **Agent, který nic nezměnil, hlavu nedrží** (#510) — v cache po něm nic neleží,
        // takže je to tentýž případ jako `alreadyInSync`.
        let onGitHub: [BranchSyncState] = [
            .pushed(replayed: 2), .alreadyInSync, .fixedNothing(detail: nil),
        ]
        let held: [BranchSyncState] = [
            .rebasing,
            .resolving(round: 1, files: ["a.swift"]),
            // Běžící agent i jeho **nepřijatý** výsledek: v obou případech může ve stromě `-sync`
            // ležet změna, o které GitHub neví (#510).
            .fixing(items: 3),
            .fixRejected(detail: "Session zapsala mimo strom."),
            .rebased(Self.rebasedBranch),
            .pushing,
            .discarding,
            .conflicted(files: ["a.swift"]),
            .unfinished(files: ["a.swift"]),
            .unresolved(files: ["a.swift"], detail: nil),
            .failed(.leaseRejected),
        ]
        #expect(Policy.ownLoopFacts(of: .ci, branch: nil).isEmpty, "nevím o ničem není důkaz")
        for sync in onGitHub {
            #expect(Policy.ownLoopFacts(of: .ci, branch: sync).isEmpty, "\(sync)")
            #expect(Policy.ownLoopFacts(of: .review, branch: sync).isEmpty, "\(sync)")
        }
        for sync in held {
            #expect(Policy.ownLoopFacts(of: .ci, branch: sync) == [.push], "\(sync)")
            #expect(Policy.ownLoopFacts(of: .review, branch: sync) == [.push], "\(sync)")
        }
    }

    // MARK: - Jedno slovo za zastávkou (#508, čtvrté kolo)

    /// **`Push` za zastávkou řekne jedním slovem, proč není zelený** — a je to ta vada, kterou
    /// uživatel viděl na obrazovce: dráha stála na `Nálezech`, větev byla o jednadvacet commitů
    /// pozadu a `Push` visel šedý **bez textu**, takže to z hlavičky nešlo poznat vůbec.
    ///
    /// Vyčerpávající výčet přes všechny podoby stavu větve. Zastávka je pokaždé na `Nálezech`
    /// (`notStarted`), takže se `Push` vyhodnocuje **za** ní.
    @Test("Push za zastávkou pojmenuje překážku jedním slovem")
    func pushSaysWhyItIsNotGreenPastTheStop() throws {
        let cases: [(String, BranchSyncState?, BranchStatusState?, String?)] = [
            ("o 21 commitů pozadu (#566)", nil, status(.mergeable, .clean, behind: 21), "pozadu"),
            ("za základem podle mergeState", nil, status(.mergeable, .behind), "pozadu"),
            ("konflikt se základem", nil, status(.conflicting, .clean), "konflikt"),
            ("dirty", nil, status(.mergeable, .dirty), "konflikt"),
            ("stav se dotahuje", nil, .loading, "zjišťuju"),
            ("stav se nepodařilo zjistit", nil, .failed("gh spadlo"), "nevím"),
            ("přerovnáno, nepřetlačeno", .rebased(Self.rebasedBranch), status(), "nepřetlačeno"),
            ("rebasuje se", .rebasing, status(), "probíhá"),
            ("slévají se konflikty", .resolving(round: 1, files: ["a.swift"]), status(), "probíhá"),
            ("pushuje se", .pushing, status(), "probíhá"),
            ("zahazuje se", .discarding, status(), "probíhá"),
            ("konflikt v cache", .conflicted(files: ["a.swift"]), status(), "rebase"),
            ("rozdělaný rebase", .unfinished(files: []), status(), "rebase"),
            ("session nerozřešila", .unresolved(files: ["a.swift"], detail: nil), status(), "rebase"),
            ("agent opravuje", .fixing(items: 3), status(), "probíhá"),
            // **`nepřijato`, ne `rebase`** (#510): po agentovi žádný rozdělaný rebase ve stromě
            // neleží, takže by to slovo pojmenovalo něco, co se nestalo.
            ("výsledek agenta nepřijat", .fixRejected(detail: "Zapsala mimo strom."), status(), "nepřijato"),
            ("agent nic nezměnil", .fixedNothing(detail: nil), status(), "srovnaná"),
            ("push spadl", .failed(.leaseRejected), status(), "rebase"),
            ("srovnaná větev", nil, status(), "srovnaná"),
        ]
        for (name, sync, branch, word) in cases {
            let loop = try #require(walk(review: .notStarted, sync: sync, status: branch))
            #expect(loop.active == .findings, "\(name): zastávka je na Nálezech")
            #expect(loop.detail(of: .push) == word, "\(name)")
            // Slovo z ní **neudělá aktivní kapsli** — rozdělaná zůstává jedna, ta se zastávkou.
            let expected: ReviewerLane.PhaseState = word == "srovnaná" ? .done : .idle
            #expect(loop.state(of: .push) == expected, "\(name)")
        }
    }

    /// **Nezjištěný stav větve je `zjišťuju` nebo `nevím`, nikdy `pozadu`.** Je to ta mez, která
    /// u téhle změny bolí nejvíc: slovo v šedé kapsli nemá pod sebou větu, která by ho upřesnila,
    /// takže se čte jako fakt. Kdyby `pushStep` u nenačteného stavu spadl do větve `pozadu`, dráha
    /// by nad načítáním tvrdila něco o poloze větve — a nikdo by si toho nevšiml.
    @Test("Nezjištěný stav větve se za zastávkou nevydává za pozadu")
    func unknownBranchStateNeverClaimsBehind() throws {
        for branch: BranchStatusState? in [nil, .loading, .failed("gh spadlo")] {
            let loop = try #require(
                Policy.ownLoop(
                    ownership: .mine,
                    state: .open,
                    review: .notStarted,
                    handoff: .never,
                    status: branch,
                    checks: [],
                    reviewers: []
                )
            )
            let word = try #require(loop.detail(of: .push), "\(String(describing: branch))")
            #expect(word == "zjišťuju" || word == "nevím", "\(String(describing: branch)): \(word)")
            #expect(loop.state(of: .push) == .idle)
        }
    }

    /// **`CI` a `Review` za zastávkou taky pojmenují překážku** — pravidlo je *nehotová stanice
    /// řekne jedním slovem proč*, ne výjimka pro `Push`. Výjimka pro jednu stanici by znamenala,
    /// že se z dráhy dá vyčíst důvod jen někdy, a to je horší než kdyby se nedal nikdy.
    @Test("CI a Review za zastávkou pojmenují překážku jedním slovem")
    func checksAndReviewSayWhyPastTheStop() throws {
        let checks: [(String, [PullRequestCheck]?, String?)] = [
            ("nenačteno", nil, "zjišťuju"),
            ("spadlé", [check("build", .failed), check("test", .passed)], "neprošlo"),
            ("běžící", [check("build", .running)], "běží"),
            ("zeleno", [check("build", .passed)], "zeleno"),
            ("bez CI", [], "bez checků"),
        ]
        for (name, value, word) in checks {
            let loop = try #require(walk(review: .notStarted, checks: value))
            #expect(loop.detail(of: .ci) == word, "checky \(name)")
        }

        let reviewers: [(String, [RequestedReviewer]?, String?)] = [
            ("nenačteno", nil, "zjišťuju"),
            ("chce změny", [RequestedReviewer(login: "a", answer: .changesRequested)], "změny"),
            ("čeká", [RequestedReviewer(login: "a", answer: .waiting)], "čeká"),
            ("schváleno", [RequestedReviewer(login: "a", answer: .approved)], "schváleno"),
            ("nikdo", [], "bez reviewerů"),
        ]
        for (name, value, word) in reviewers {
            let loop = try #require(walk(review: .notStarted, reviewers: value))
            #expect(loop.detail(of: .review) == word, "reviewery \(name)")
        }
    }

    /// **Stanice, která se nevyhodnocovala, mlčí — a je to to nejcennější tvrzení téhle změny.**
    ///
    /// Když v cache leží nepřetlačená práce, `CI` a `Review` stojí na `Push`i (`ownLoopFacts`)
    /// a ten hotový není. Vymyslet jim za takového stavu důvod by znamenalo mluvit o **jiné**
    /// hlavě, než jaká je na GitHubu; ticho je jediná odpověď, kterou data unesou. Totéž platí
    /// o `Zadání`, které stojí na `Nálezech`.
    @Test("Nevyhodnocená stanice nedostane ani důvod")
    func stationsWithoutFactsStaySilent() throws {
        let unpushed = try #require(
            walk(
                review: .notStarted,
                sync: .rebased(Self.rebasedBranch),
                checks: [check("build", .failed)],
                reviewers: [RequestedReviewer(login: "a", answer: .changesRequested)]
            )
        )
        #expect(unpushed.active == .findings)
        #expect(unpushed.state(of: .ci) == .idle)
        #expect(unpushed.detail(of: .ci) == nil, "CI mluví o jiné hlavě, takže mlčí")
        #expect(unpushed.state(of: .review) == .idle)
        #expect(unpushed.detail(of: .review) == nil, "Review mluví o jiné hlavě, takže mlčí")
        // `Push` se naopak vyhodnocuje vždycky — na ničem nestojí.
        #expect(unpushed.detail(of: .push) == "nepřetlačeno")

        // `Zadání` stojí na `Nálezech`: dokud review nedoběhlo, není z čeho skládat zadání.
        #expect(unpushed.state(of: .handoff) == .idle)
        #expect(unpushed.detail(of: .handoff) == nil)
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

    /// **Hotové kolo o mergi netvrdí, že jde — jen kam pro něj jít** (#508, čtvrté kolo).
    ///
    /// Stanice `Merge` odešla, takže se dráha nad zeleným PR dojde do konce bez zastávky. Věta
    /// pod fázemi proto ukazuje na sekci `Větev`, kde merge bydlí — je to údaj o **místě**, ne
    /// tvrzení o slévatelnosti, kterou tahle funkce od čtvrtého kola ani nedostává.
    @Test("Zelené kolo posílá na merge do sekce Větev")
    func finishedLoopPointsAtTheBranchSection() throws {
        let loop = try #require(
            walk(
                review: .clean,
                handoff: handed(6),
                checks: [check("build", .passed)],
                reviewers: [RequestedReviewer(login: "a", answer: .approved)]
            )
        )
        #expect(loop.active == nil)
        #expect(loop.move == nil, "dráha merge nenabízí — je v sekci Větev")
        #expect(loop.stations.allSatisfy { $0.state == .done })
        #expect(loop.last.contains("Větev"))
        // A netvrdí, že se to dá mergnout: o slévatelnosti dráha nic neví.
        #expect(!loop.last.contains("Zeleno"))
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

    // MARK: - Stanice Zadání

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
            // **Zapisující session agenta je běžící práce jako slévání konfliktů** (#510),
            // nepřijatý výsledek je porucha jako `unresolved`: v obou případech se rozhoduje
            // o tom, co leží ve stromě `-sync`.
            (.fixing(items: 3), .running),
            (.fixRejected(detail: "Session zapsala mimo strom."), .failed),
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
        // **Agent, který nic nezměnil, je tentýž případ** (#510): v cache po něm nic neleží,
        // takže o poloze větve nerozhoduje ani on.
        for sync in [BranchSyncState.pushed(replayed: 2), .alreadyInSync, .fixedNothing(detail: nil)] {
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
        // Počet z `compare` (#466) — `mergeStateStatus` na tuhle otázku neodpovídá. **Počet je
        // v detailu aktivní stanice**, kdežto za zastávkou stojí jen slovo (viz test výš).
        let behind = try #require(walk(status: status(.mergeable, .clean, behind: 4)))
        #expect(behind.active == .push)
        #expect(behind.detail(of: .push) == "o 4 vzadu")
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
            reviewers: []
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
        #expect(none.detail(of: .ci) == "bez checků")

        let green = try #require(walk(checks: [check("build", .passed)]))
        #expect(green.state(of: .ci) == .done)

        let skipped = try #require(walk(checks: [check("build", .skipped)]))
        #expect(skipped.state(of: .ci) == .done)
        #expect(skipped.detail(of: .ci) == "přeskočeno")

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

        let waiting = try #require(walk(reviewers: [RequestedReviewer(login: "b", answer: .waiting)]))
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

    /// **Schválený PR má `Review` hotové, i když na něm visí další žádost** (#508, třetí kolo).
    ///
    /// Doslova `keboola/platform-libraries#566`: `odinuv` schválil, `MiroCillik` je vyžádaný
    /// a nevyjádřil se. Do třetího kola z toho dráha skládala `čeká 1`, tedy `Review` nehotové nad
    /// schváleným PR. Rozhodl to uživatel: jedno schválení stanici zavírá.
    ///
    /// **A ta druhá půlka se uvolnit nesmí**: `chce změny` nezezelená ani vedle schválení.
    @Test("Review: schválení přebíjí visící žádost, chce změny ne")
    func approvalOutranksAPendingRequest() throws {
        let approvedWithPending = try #require(
            walk(reviewers: [
                RequestedReviewer(login: "odinuv", answer: .approved),
                RequestedReviewer(login: "MiroCillik", answer: .waiting),
            ])
        )
        #expect(approvedWithPending.state(of: .review) == .done)
        #expect(approvedWithPending.detail(of: .review) == "schváleno")
        // Walk došel do konce — `Review` byla poslední stanice od chvíle, kdy `Merge` odešel.
        #expect(approvedWithPending.active == nil)

        let approvedButBlocked = try #require(
            walk(reviewers: [
                RequestedReviewer(login: "odinuv", answer: .approved),
                RequestedReviewer(login: "kolega", answer: .changesRequested),
                RequestedReviewer(login: "MiroCillik", answer: .waiting),
            ])
        )
        #expect(approvedButBlocked.active == .review, "chce změny přebíjí schválení")
        #expect(approvedButBlocked.state(of: .review) == .failed)
    }

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
                checks: [check("build", .failed)]
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

    /// Draft smyčku nezkracuje — pracuje se na něm dál, jenom se nedá mergnout. **A od čtvrtého
    /// kola se na to dráha ani neptá**: merge mezi stanicemi není, takže je draft se zeleným
    /// kolem k nerozeznání od otevřeného PR. Že draft mergnout nejde, říká sekce `Větev`.
    @Test("Draft se smyčkou prochází jako otevřený")
    func draftWalksTheLoop() throws {
        let loop = try #require(walk(state: .draft, handoff: report(.never, pending: 2)))
        #expect(loop.active == .handoff)
        #expect(loop.state(of: .handoff) == .running)
        #expect(loop.stations.map(\.station) == OwnLoop.Station.allCases)
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

    /// Jeden vzorek matice `review × handoff × větev × CI × review`. Skládá se ve struktuře, ne
    /// v poli hotových `OwnLoop`ů: helper `walk(…)` je metoda suity a `arguments:` by ho neviděl.
    private struct Sample {
        let review: ReviewState
        let handoff: HandoffReport
        let sync: BranchSyncState?
        let status: BranchStatusState?
        let checks: [PullRequestCheck]?
        let reviewers: [RequestedReviewer]?
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
                reviewers: reviewers
            )
        }
    }

    /// Kříž přes všechny osy. **Ne kartézský součin všeho** — ten by měl tisíce prvků a testoval
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
        let behind = BranchStatusState.loaded(
            BranchStatus(
                mergeability: .mergeable,
                mergeState: .clean,
                divergence: BranchDivergence(ahead: 1, behind: 21)
            ),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let green = [PullRequestCheck(name: "build", outcome: .passed, link: nil, startedAt: nil, completedAt: nil)]
        let red = [PullRequestCheck(name: "build", outcome: .failed, link: nil, startedAt: nil, completedAt: nil)]

        var samples: [Sample] = []
        for review in everyReviewState {
            for status: BranchStatusState? in [ok, behind, .loading, .failed("gh"), nil] {
                samples.append(
                    Sample(
                        review: review, handoff: clean, sync: nil, status: status, checks: green,
                        reviewers: [], state: .open
                    )
                )
            }
        }
        for handoff in [clean, pending, delivered] {
            for checks in [green, red, nil] {
                for reviewers: [RequestedReviewer]? in [
                    [], nil, [RequestedReviewer(login: "a", answer: .changesRequested)],
                ] {
                    samples.append(
                        Sample(
                            review: .clean, handoff: handoff, sync: nil, status: behind,
                            checks: checks, reviewers: reviewers, state: .open
                        )
                    )
                }
            }
        }
        for sync: BranchSyncState? in [
            nil, .rebasing, .rebased(rebasedBranch), .conflicted(files: []), .pushed(replayed: 1),
        ] {
            for status: BranchStatusState? in [nil, .loading, .failed("gh"), ok, behind] {
                samples.append(
                    Sample(
                        review: .clean, handoff: delivered, sync: sync, status: status, checks: green,
                        reviewers: [RequestedReviewer(login: "a", answer: .waiting)],
                        state: .open
                    )
                )
            }
        }
        for state in [PullRequestState.open, .draft, .merged, .closed] {
            samples.append(
                Sample(
                    review: .completed(findings: 2), handoff: pending, sync: nil, status: ok,
                    checks: red, reviewers: nil, state: state
                )
            )
        }
        return samples
    }()
}
