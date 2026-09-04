import Foundation
import Testing

@testable import PRism

/// Sekce `Větev` a nabídka merge (#465) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou ta záporná: na cizím PR se akce **nekreslí vůbec**, nad
/// nenačteným stavem se **nenabízí**, a nad červeným checkem se **nenabízí**, i když by GitHub
/// merge pustil. Merge je nevratný, takže omyl v téhle funkci se nedá vzít zpět.
@Suite("Sekce Větev a merge")
struct BranchMergeTests {
    private let mine = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 465)

    private func detail(
        state: PullRequestState = .open,
        head: String = "issue-465-merge-from-panel",
        base: String = "main",
        title: String = "feat: merge own pull request from the panel"
    ) -> PullRequest {
        PullRequest(
            id: mine,
            title: title,
            author: "ondrajodas",
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            baseSha: "7b3f740e",
            headRef: head,
            baseRef: base,
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/465")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    private func commits(_ count: Int) -> [PullRequestCommit] {
        (0..<count).map {
            PullRequestCommit(
                sha: String(format: "%040d", $0),
                message: "chore: krok \($0)",
                authorName: "ondrajodas",
                authorLogin: "ondrajodas",
                avatarURL: nil,
                committedAt: Date(timeIntervalSince1970: 100),
                isMerge: false
            )
        }
    }

    private func check(_ name: String, _ outcome: PullRequestCheck.Outcome) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: outcome, link: nil, startedAt: nil, completedAt: nil)
    }

    private func status(
        _ mergeability: BranchStatus.Mergeability = .mergeable,
        _ state: BranchStatus.MergeState = .clean
    ) -> BranchStatusState {
        .loaded(
            BranchStatus(mergeability: mergeability, mergeState: state),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    /// Nabídka nad výchozí scénou. **„Stav se ještě nenačetl“ se tudy předat nedá** — `nil` by
    /// znamenalo „nech výchozí“, což je jiná odpověď; ten případ jde přes `Policy.mergeOffer`
    /// přímo, viz `doesNotOfferWithoutStatus`.
    private func offer(
        editing: Policy.MetadataEditing = .allowed,
        detail: PullRequest? = nil,
        commits count: Int? = 2,
        status: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = []
    ) -> Policy.MergeOffer {
        let detail = detail ?? self.detail()
        return Policy.mergeOffer(
            editing: editing,
            proposal: Policy.mergeProposal(of: detail, commits: count.map(commits)),
            state: detail.state,
            status: status ?? self.status(),
            checks: checks
        )
    }

    /// Nabídka nad **nenačteným** stavem větve — jediné místo, kde se `status` předává doslova.
    private func offerWithoutStatus(state: PullRequestState = .open) -> Policy.MergeOffer {
        let detail = detail(state: state)
        return Policy.mergeOffer(
            editing: .allowed,
            proposal: Policy.mergeProposal(of: detail, commits: commits(2)),
            state: detail.state,
            status: nil,
            checks: []
        )
    }

    // MARK: - Kdy se to nekreslí vůbec

    /// **Na cizím PR se akce nekreslí, ne zašedne.** Mergnout frontu někoho jiného se odsud nedělá
    /// nikdy, takže zašedlé tlačítko by tvrdilo „tady se to dělá, jen teď ne“ — a to je nepravda.
    @Test("Na cizím PR se sekce nekreslí vůbec")
    func drawsNothingOnAForeignPullRequest() {
        #expect(offer(editing: .absent) == .absent)
        #expect(
            Policy.branchSection(
                editing: .absent,
                detail: detail(),
                commits: commits(2),
                status: status(),
                checks: []
            ) == nil
        )
    }

    /// Vypnutá brána je naopak stav, který se **mění** — tlačítko zůstane, jen zašedlé, a **věta
    /// je ta, na které skončí publisher**, aby se okno neptalo dvakrát jinak.
    @Test("Vypnutá brána tlačítko nechá, jen ho zamkne s důvodem")
    func keepsTheButtonWhenPublishingIsOff() {
        let reason = PublishError.publishingNotAllowed(mine.repo).userDescription
        let offer = offer(editing: .blocked(reason))

        #expect(offer.isVisible)
        #expect(!offer.isAllowed)
        #expect(offer.obstacles.first == .notAllowed(reason))
        #expect(offer.obstacles.first?.sentence == reason)
    }

    // MARK: - Kdy to jde

    @Test("Zeleno, srovnaná větev a otevřený PR merge pustí")
    func allowsMergeWhenEverythingIsGreen() {
        #expect(offer(checks: [check("test", .passed)]) == .allowed)
    }

    /// **Běžící check merge nebrání**: mergnout rozběhnutou CI je legitimní rozhodnutí a povinný
    /// check zavře GitHub sám (`BLOCKED`).
    @Test("Běžící check merge nezakazuje")
    func aRunningCheckDoesNotBlock() {
        #expect(offer(checks: [check("test", .running), check("lint", .passed)]) == .allowed)
    }

    /// Přeskočený check není úspěch (kvůli hlavičce), ale merge nebrání — je to stav, ve kterém
    /// se běžně merguje.
    @Test("Přeskočený check merge nezakazuje")
    func aSkippedCheckDoesNotBlock() {
        #expect(offer(checks: [check("build", .skipped)]) == .allowed)
    }

    // MARK: - Kdy to nejde a proč

    /// **Spadlý check merge blokuje, i když by ho GitHub pustil** — u `UNSTABLE` merge dovolí.
    /// Aplikace je tady schválně striktnější; zeleno je jediný stav, ve kterém se dá mergnout bez
    /// čtení.
    @Test("Červený check merge zakáže a pojmenuje ho")
    func blocksOnAFailedCheck() {
        let offer = offer(
            status: status(.mergeable, .unstable),
            checks: [check("test-php 8.3", .failed), check("lint", .passed)]
        )

        #expect(offer.obstacles == [.failingChecks(["test-php 8.3"])])
        #expect(offer.obstacles.first?.sentence == "Check „test-php 8.3“ neprošel.")
    }

    /// **Zrušený se počítá ke spadlým** — stejně jako v `Policy.summary(of:)`. Druhé pravidlo by
    /// znamenalo hlavičku a panel v rozporu.
    @Test("Zrušený check se počítá ke spadlým")
    func countsCancelledAsFailed() {
        #expect(offer(checks: [check("e2e", .cancelled)]).obstacles == [.failingChecks(["e2e"])])
    }

    /// `UNSTABLE` bez načtených checků: **mlčet se nesmí**, ale jméno se nevymýšlí.
    @Test("UNSTABLE bez načtených checků řekne aspoň to, že něco spadlo")
    func reportsUnstableWithoutCheckNames() {
        let offer = offer(status: status(.mergeable, .unstable), checks: nil)

        #expect(offer.obstacles == [.failingChecks([])])
        #expect(offer.obstacles.first?.sentence == "Některý check neprošel.")
    }

    @Test("Konflikt, pozadu a chráněná větev mají každý svou větu")
    func namesEveryBranchObstacle() {
        #expect(offer(status: status(.conflicting, .dirty)).obstacles == [.conflicting(base: "main")])
        #expect(offer(status: status(.mergeable, .behind)).obstacles == [.behind(base: "main")])
        #expect(offer(status: status(.mergeable, .blocked)).obstacles == [.protected])
        #expect(Policy.MergeObstacle.conflicting(base: "main").sentence == "Větev je v konfliktu s main.")
        #expect(Policy.MergeObstacle.behind(base: "main").sentence == "Větev je pozadu za main.")
    }

    /// **`UNKNOWN` je odpověď „ještě nevím“, ne konflikt** — a hlásí se jedině tehdy, když se
    /// konflikt nehlásí, jinak by nad větou „je konflikt“ stála věta „nevím“.
    @Test("Nespočítaná slévatelnost merge zakáže, ale konflikt nepřebije")
    func doesNotGuessWhenGitHubDoesNotKnow() {
        #expect(offer(status: status(.unknown, .unknown)).obstacles == [.statusUnknown])
        #expect(offer(status: status(.unknown, .dirty)).obstacles == [.conflicting(base: "main")])
    }

    /// **Nenačtený stav merge nenabídne.** Je to ta nejdůležitější záporná odpověď v celé funkci:
    /// tvrdit o nevratné akci něco z chybějících dat je horší než neodpovědět.
    @Test("Bez načteného stavu větve se merge nenabízí")
    func doesNotOfferWithoutStatus() {
        #expect(offerWithoutStatus().obstacles == [.statusLoading])
        #expect(offer(status: .loading).obstacles == [.statusLoading])
        #expect(offer(status: .failed("gh není přihlášený")).obstacles == [.statusFailed("gh není přihlášený")])
    }

    /// Bez hlavičky nebo bez commitů **není z čeho složit plán**, takže není co potvrzovat.
    @Test("Bez hlavičky a bez commitů se merge nenabízí")
    func doesNotOfferWithoutFacts() {
        #expect(offer(detail: detail(head: ""), commits: 2).obstacles == [.factsMissing])
        #expect(offer(commits: nil).obstacles == [.factsMissing])
        #expect(
            Policy.mergeOffer(
                editing: .allowed,
                proposal: nil,
                state: nil,
                status: status(),
                checks: []
            ).obstacles == [.factsMissing]
        )
    }

    /// **Nad mergnutým PR výčet končí.** Věty o slévatelnosti nebo o checcích by nad hotovou věcí
    /// jen zabíraly místo; jediná pravdivá je ta o stavu.
    @Test("Zavřený a mergnutý PR ukončí výčet jednou větou")
    func stopsAtAClosedPullRequest() {
        let merged = offerWithoutStatus(state: .merged)
        #expect(merged.obstacles == [.notOpen(.merged)])
        #expect(merged.obstacles.first?.sentence == "Pull request není otevřený — je mergnutý.")

        let closed = offerWithoutStatus(state: .closed)
        #expect(closed.obstacles == [.notOpen(.closed)])
    }

    /// Draft merge zakazuje, ale výčet **neukončuje**: rozpracovaný PR se dá zároveň opravovat,
    /// takže o červeném checku má smysl vědět.
    @Test("Draft merge zakáže a zbytek důvodů zůstane")
    func blocksOnADraftAndKeepsTheRest() {
        let offer = offer(
            detail: detail(state: .draft),
            status: status(.mergeable, .draft),
            checks: [check("test", .failed)]
        )

        #expect(offer.obstacles == [.draftPullRequest, .failingChecks(["test"])])
    }

    /// **Vlastní blokující nález merge nezakazuje** (#563, ruší rozhodnutí z #465) — a v jednom
    /// testu k tomu druhá věta, která se s ní nesmí rozejít: **spadlý check zakazuje dál**.
    ///
    /// Nález je názor *revieweera* na kód, ne stav *pull requestu*; tatáž třída jako brána
    /// odesílání (`isPublishingGate`), jen o úroveň dál. Do funkce se od #563 **nedostane vůbec**,
    /// takže se to tvrdí přes výčet toho, co vydat umí: scéna z `keboola/platform-libraries#566`
    /// (slévatelný, čistý, zelené i přeskočené checky) vyjde `allowed`, kdežto tatáž scéna
    /// s červeným checkem `blocked`.
    ///
    /// Že se nález **neztratil**, tvrdí `AppStoreMergeTests.keepsTheBlockingFindingVisible` nad
    /// celým řetězcem (řádek, filtr, souhrn).
    @Test("Blokující nález merge nezakáže, spadlý check ano")
    func doesNotBlockOnABlockingFinding() {
        // Případ #566: 22 zelených, 22 přeskočených, žádný spadlý.
        let clean = (0..<22).map { check("pass-\($0)", .passed) }
            + (0..<22).map { check("skip-\($0)", .skipped) }
        #expect(offer(checks: clean) == .allowed)
        // A tatáž scéna s jedním spadlým checkem — jediná změna proti řádku výš.
        #expect(
            offer(checks: clean + [check("test-php 8.3", .failed)]).obstacles
                == [.failingChecks(["test-php 8.3"])]
        )
    }

    /// Výčet **všeho, co `mergeOffer` vydat umí**, a nic z toho nemluví o nálezech (#563).
    ///
    /// Tvrzení o tom, co se **nestalo**, takže z téhle sady nejcennější: kdyby se překážka
    /// z nálezu vrátila, přibude sem věta, kterou tenhle výčet nezná. Jsou to **tytéž věty**,
    /// jaké prochází `WorkLaneTests.respectsEveryRealObstacle` (deset překážek, ne jedenáct).
    @Test("Ve výčtu překážek není žádná o nálezech")
    func neverSpeaksAboutFindings() {
        let every: [Policy.MergeObstacle] = [
            .notAllowed("odesílání je vypnuté"),
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
        ]
        #expect(every.count == 11)
        for obstacle in every {
            #expect(!obstacle.sentence.localizedCaseInsensitiveContains("nález"), "\(obstacle)")
            // **Vyčerpávající `switch` je tu stráž, ne kosmetika**: nová překážka tenhle test
            // nepustí přeložit, takže se u ní musí rozhodnout, jestli mluví o pull requestu, nebo
            // o názoru na kód — a to druhé sem od #563 nepatří.
            switch obstacle {
            case .notAllowed, .factsMissing, .statusLoading, .statusFailed, .statusUnknown,
                 .conflicting, .behind, .protected, .draftPullRequest, .notOpen, .failingChecks:
                break
            }
        }
    }

    /// Důvodů může být víc a **každý vede jinam**, takže se nesčítají do jednoho. Pořadí je pořadí,
    /// ve kterém se s nimi dá něco dělat.
    @Test("Víc důvodů se vypíše všechny a v pořadí")
    func listsEveryObstacleInOrder() {
        let offer = offer(
            status: status(.mergeable, .behind),
            checks: [check("test-php 8.3", .failed)]
        )

        #expect(offer.obstacles == [
            .behind(base: "main"),
            .failingChecks(["test-php 8.3"]),
        ])
    }

    /// Jména spadlých checků se **vypisují nejvýš tři** — panel má 300 bodů.
    @Test("Ze seznamu spadlých checků se vypíšou nejvýš tři")
    func trimsTheListOfFailedChecks() {
        let names = ["a", "b", "c", "d", "e"]
        #expect(
            Policy.MergeObstacle.failingChecks(names).sentence
                == "Neprošly checky „a“, „b“, „c“ a 2 další."
        )
        #expect(
            Policy.MergeObstacle.failingChecks(["a", "b"]).sentence == "Neprošly checky „a“, „b“."
        )
    }

    // MARK: - Řádky stavu

    @Test("Řádky stavu říkají, kam se to slévá a jak to dopadlo")
    func describesTheBranch() {
        let facts = Policy.branchFacts(
            proposal: Policy.mergeProposal(of: detail(), commits: commits(3)),
            commits: commits(3),
            status: status(),
            checks: [check("a", .passed), check("b", .passed)]
        )

        #expect(facts.count == 2)
        #expect(facts[0].text == "issue-465-merge-from-panel → main")
        #expect(facts[0].answer == "srovnaná")
        #expect(facts[0].tone == .done)
        #expect(facts[1].text == "3 commity · 2 checky")
        #expect(facts[1].answer == "zeleno")
        #expect(facts[1].tone == .done)
    }

    @Test("Za základem a červený check se v řádcích poznají")
    func showsBlockedAnswers() {
        let facts = Policy.branchFacts(
            proposal: Policy.mergeProposal(of: detail(), commits: commits(1)),
            commits: commits(1),
            status: status(.mergeable, .behind),
            checks: [check("a", .failed), check("b", .passed)]
        )

        #expect(facts[0].answer == "za základem")
        #expect(facts[0].tone == .blocked)
        #expect(facts[1].text == "1 commit · 2 checky")
        #expect(facts[1].answer == "1 neprošel")
        #expect(facts[1].tone == .blocked)
    }

    /// **„Nic tu není“ a „nevím“ se nesmí slít** ani v řádcích: PR bez CI je běžný stav, kdežto
    /// nenačtené checky nejsou odpověď o PR.
    @Test("Bez checků a s nenačtenými checky jsou dvě různé odpovědi")
    func separatesEmptyFromUnknown() {
        let plan = Policy.mergeProposal(of: detail(), commits: commits(2))
        let empty = Policy.branchFacts(proposal: plan, commits: commits(2), status: status(), checks: [])
        let unknown = Policy.branchFacts(proposal: plan, commits: commits(2), status: status(), checks: nil)

        #expect(empty[1].answer == "bez checků")
        #expect(unknown[1].answer == "checky se načítají")
    }

    @Test("Nenačtený stav větve řádek nezmate")
    func showsUnknownSyncHonestly() {
        let plan = Policy.mergeProposal(of: detail(), commits: commits(2))
        #expect(Policy.branchFacts(proposal: plan, commits: commits(2), status: nil, checks: []).first?.answer == "zjišťuju")
        #expect(
            Policy.branchFacts(proposal: plan, commits: commits(2), status: .failed("nic"), checks: [])
                .first?.answer == "nevím"
        )
        #expect(
            Policy.branchFacts(proposal: nil, commits: nil, status: nil, checks: nil).first?.text
                == "větev se načítá"
        )
    }

    // MARK: - Návrh a plán

    /// Titulek squash commitu je `titulek PR (#číslo)` — **posílá se doslova**, protože bez
    /// `commit_title` si ho GitHub skládá podle nastavení repozitáře, do kterého aplikace nevidí.
    ///
    /// Ověřeno proti skutečnému mergi (`prism-review-sandbox#8`): titulek výsledného commitu byl
    /// přesně to, co šlo v `commit_title`.
    ///
    /// **Od #556 je návrh a payload dvojice**: návrh nese titulek **pull requestu**, payload
    /// titulek **commitu** — a ten se skládá až podle metody. Tvrdí se proto obojí, jinak by se
    /// dalo rozbít skládání a test by pořád zeleně kontroloval jen fakta o PR.
    @Test("Návrh nese větev, hlavu a počet commitů, payload z něj titulek")
    func buildsThePlan() throws {
        let proposal = try #require(Policy.mergeProposal(of: detail(), commits: commits(3)))

        #expect(proposal.pullRequest == mine)
        #expect(proposal.head == "issue-465-merge-from-panel")
        #expect(proposal.base == "main")
        #expect(proposal.commits == 3)
        #expect(proposal.headSha == "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90")
        #expect(proposal.title == "feat: merge own pull request from the panel")

        let plan = proposal.plan(with: .squash)
        #expect(plan.method == .squash)
        #expect(plan.commitTitle == "feat: merge own pull request from the panel (#465)")
    }

    /// **Výchozí metoda je squash, i když se o ni nikdo neřekne** (#556) — tak se aplikace chovala
    /// do #556 a po zavedení pole se nesmí začít chovat jinak.
    @Test("Návrh bez zadané metody nese squash a nic o repozitáři netvrdí")
    func defaultsToSquash() throws {
        let proposal = try #require(Policy.mergeProposal(of: detail(), commits: commits(1)))

        #expect(proposal.defaultMethod == .squash)
        // `nil` = **nevím**, tedy stav, ve kterém se nabídnou všechny tři metody.
        #expect(proposal.repository == nil)
    }

    @Test("Bez jména větve nebo bez commitů plán nevznikne")
    func refusesToBuildAnIncompletePlan() {
        #expect(Policy.mergeProposal(of: nil, commits: commits(1)) == nil)
        #expect(Policy.mergeProposal(of: detail(), commits: nil) == nil)
        #expect(Policy.mergeProposal(of: detail(head: ""), commits: commits(1)) == nil)
        #expect(Policy.mergeProposal(of: detail(base: ""), commits: commits(1)) == nil)
    }

    /// Číslo PR se sází **ručně**, ne formátováním: `#4650` není množství a v české locale by
    /// z něj vyšlo `#4 650`.
    @Test("Číslo PR v titulku se neformátuje")
    func doesNotGroupThePullRequestNumber() {
        #expect(Policy.squashTitle(of: "fix: něco", number: 4650) == "fix: něco (#4650)")
    }
}
