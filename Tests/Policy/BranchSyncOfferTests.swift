import Foundation
import Testing

@testable import PRism

/// Nabídka `Srovnat s main` (#466) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou ta záporná: na **cizím** PR se akce nekreslí vůbec, na PR
/// z **forku** se nenabízí, nad **srovnanou** větví se nenabízí a nad **rozdělaným rebasem** se
/// nenabízí. `git push` je jediná věc, kterou aplikace zapisuje do remote — omyl v téhle funkci
/// končí přepsanou větví.
@Suite("Nabídka srovnání větve")
struct BranchSyncOfferTests {
    private let mine = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 466)

    private func detail(
        state: PullRequestState = .open,
        head: String = "issue-466-sync-branch",
        base: String = "main",
        headSha: String = "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
        cross: Bool? = false
    ) -> PullRequest {
        PullRequest(
            id: mine,
            title: "feat: sync own branch with main",
            author: "ondrajodas",
            headSha: headSha,
            baseSha: "7b3f740e",
            headRef: head,
            baseRef: base,
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/466")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: cross
        )
    }

    private func status(
        _ mergeability: BranchStatus.Mergeability = .mergeable,
        _ state: BranchStatus.MergeState = .clean,
        ahead: Int = 3,
        behind: Int = 4
    ) -> BranchStatusState {
        .loaded(
            BranchStatus(
                mergeability: mergeability,
                mergeState: state,
                divergence: BranchDivergence(ahead: ahead, behind: behind)
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func offer(
        editing: Policy.MetadataEditing = .allowed,
        detail: PullRequest?,
        status: BranchStatusState?,
        sync: BranchSyncState? = nil
    ) -> Policy.SyncOffer {
        Policy.branchSyncOffer(
            editing: editing,
            plan: Policy.branchSyncPlan(of: detail, status: status),
            detail: detail,
            status: status,
            sync: sync
        )
    }

    // MARK: - Kdy se nabízí

    @Test("Vlastní PR, zapnutá brána a větev pozadu — nabízí se")
    func offersOnOwnBranchThatIsBehind() {
        #expect(offer(detail: detail(), status: status()) == .allowed)
    }

    /// **Draft se srovnat smí.** Rozpracovaný PR je zrovna ten, na kterém se pushuje nejvíc —
    /// zakázat na něm rebase by akci vypnulo tam, kde je nejužitečnější.
    @Test("Rozpracovaný pull request se srovnat smí")
    func offersOnDrafts() {
        #expect(offer(detail: detail(state: .draft), status: status(.mergeable, .draft)) == .allowed)
    }

    /// **Červený check srovnání nebrání** — na rozdíl od merge. Srovnat větev je zrovna to, co se
    /// s rozbitou CI dělá.
    @Test("Nezelené checky srovnání nebrání")
    func ignoresChecks() {
        #expect(offer(detail: detail(), status: status(.mergeable, .unstable)) == .allowed)
    }

    // MARK: - Kdy se nenabízí (ta cennější půlka)

    /// Na cizím PR se akce **nekreslí vůbec**, ne zašedle: přetlačit cizí větev se odsud nedělá
    /// nikdy, takže „tady se to dělá, jen teď ne“ by byla nepravda.
    @Test("Na cizím PR se akce nekreslí")
    func hiddenOnForeignPullRequests() {
        #expect(offer(editing: .absent, detail: detail(), status: status()) == .absent)
    }

    @Test("Vypnutá brána akci zakáže i s důvodem")
    func blockedByTheGate() {
        let offer = offer(editing: .blocked("Odesílání není povolené."), detail: detail(), status: status())

        #expect(offer.isAllowed == false)
        #expect(offer.obstacles.contains(.notAllowed("Odesílání není povolené.")))
    }

    /// **Fork je zákaz**: `origin` je základní repozitář, takže by push mířil jinam, než na co se
    /// člověk dívá.
    @Test("Větev ve forku se odsud nesrovná")
    func refusesForks() {
        let offer = offer(detail: detail(cross: true), status: status())

        #expect(offer.obstacles == [.foreignBranch(known: true)])
    }

    /// **„Nevím, kde větev leží“ je taky zákaz.** Je to jediná odpověď, ze které neplyne, kam se
    /// píše — a u zápisu do remote se z nevědomosti povolení dělat nesmí.
    /// **Nenačtená hlavička není „neznámý původ větve“** (nález Copilota na #466). Jsou to dvě
    /// různé věci a v panelu se z nich píšou dvě různé věty: „hlavička ještě nedorazila“ se za
    /// chvíli spraví sama, kdežto „z dat neplyne, kde větev leží“ říká, že dorazila a mlčí.
    ///
    /// Druhá půlka tvrzení je o tom, co se předčasným `return`em **zahazovalo**: ostatní překážky.
    /// Zrovna ty jsou přitom to, se čím se dá něco dělat.
    @Test("Nenačtená hlavička není odpověď o původu větve")
    func doesNotBlameTheBranchOriginBeforeTheDetailArrives() throws {
        let waiting = offer(detail: nil, status: nil, sync: .unfinished(files: ["a.php"]))

        #expect(!waiting.isAllowed)
        #expect(waiting.obstacles.contains(.factsMissing))
        #expect(!waiting.obstacles.contains(.foreignBranch(known: false)))
        #expect(!waiting.obstacles.contains(.foreignBranch(known: true)))
        // Rozdělaný rebase i nenačtený stav větve se dozvíme dál — předčasný `return` je zahazoval.
        #expect(waiting.obstacles.contains(.unfinishedRebase))
        #expect(waiting.obstacles.contains(.statusLoading))
        // A výstraha v panelu o původu větve **mlčí**, protože ho nemá odkud znát.
        #expect(Policy.syncWarnings(waiting).isEmpty)
    }

    @Test("Neznámý původ větve se odsud nesrovná")
    func refusesUnknownOrigin() {
        let offer = offer(detail: detail(cross: nil), status: status())

        #expect(offer.obstacles == [.foreignBranch(known: false)])
    }

    @Test("Zavřený a mergnutý pull request výčet ukončí")
    func refusesClosedPullRequests() {
        for state in [PullRequestState.merged, .closed] {
            #expect(offer(detail: detail(state: state), status: status()).obstacles == [.notOpen(state)])
        }
    }

    /// **Srovnaná větev není důvod něco pushovat.** Nula commitů pozadu znamená, že by rebase
    /// vydal tutéž hlavu — a push, po kterém se nic nezmění, je sáhnutí na cizí server za nic.
    @Test("Srovnaná větev se nenabízí")
    func refusesWhenAlreadyInSync() {
        let offer = offer(detail: detail(), status: status(ahead: 3, behind: 0))

        #expect(offer.obstacles == [.upToDate(base: "main")])
    }

    /// Konflikt řeší #467. Do té doby se to **přiznává**, ne zkouší: rebase by skončil konfliktem
    /// a rozdělanou prací v cache.
    @Test("Konflikt srovnání zastaví")
    func refusesOnConflict() {
        let offer = offer(detail: detail(), status: status(.conflicting, .dirty))

        #expect(offer.obstacles.contains(.conflicting(base: "main")))
        #expect(offer.isAllowed == false)
    }

    /// Bez odpovědi na „o kolik je pozadu“ se **netvrdí nic**: `mergeStateStatus` na to
    /// neodpovídá (změřeno), takže by povolení bez divergence bylo hádání.
    @Test("Bez divergence se nenabízí")
    func refusesWithoutDivergence() {
        let status = BranchStatusState.loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(offer(detail: detail(), status: status).obstacles == [.factsMissing])
    }

    @Test("Nenačtený a nepovedený stav větve mají každý svou větu")
    func distinguishesLoadingFromFailure() {
        #expect(offer(detail: detail(), status: nil).obstacles.contains(.statusLoading))
        #expect(offer(detail: detail(), status: .loading).obstacles.contains(.statusLoading))
        #expect(
            offer(detail: detail(), status: .failed("gh spadl")).obstacles
                .contains(.statusFailed("gh spadl"))
        )
    }

    /// **Rozdělaný rebase v cache akci zastaví.** Napřed se musí zahodit — jinak by druhý pokus
    /// přehrával nad rozdělanou prací.
    @Test("Rozdělaný rebase srovnání zastaví")
    func refusesWithUnfinishedRebase() {
        let offer = offer(detail: detail(), status: status(), sync: .unfinished(files: ["a.swift"]))

        #expect(offer.obstacles.contains(.unfinishedRebase))
    }

    @Test("Běžící srovnání druhé nepustí")
    func refusesWhileRunning() {
        for state in [BranchSyncState.rebasing, .pushing, .discarding] {
            #expect(offer(detail: detail(), status: status(), sync: state).obstacles.contains(.running))
        }
    }

    // MARK: - Plán

    @Test("Plán nese větev, základ, hlavu a počty")
    func buildsThePlan() throws {
        let plan = try #require(Policy.branchSyncPlan(of: detail(), status: status(ahead: 3, behind: 4)))

        #expect(plan.pullRequest == mine)
        #expect(plan.branch == "issue-466-sync-branch")
        #expect(plan.base == "main")
        #expect(plan.expectedRemoteSha == "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90")
        #expect(plan.replaying == 3)
        #expect(plan.behind == 4)
    }

    @Test("Bez jména větve, základu nebo hlavy se plán nesloží")
    func refusesToPlanWithoutFacts() {
        #expect(Policy.branchSyncPlan(of: detail(head: ""), status: status()) == nil)
        #expect(Policy.branchSyncPlan(of: detail(base: ""), status: status()) == nil)
        #expect(Policy.branchSyncPlan(of: detail(headSha: ""), status: status()) == nil)
        #expect(Policy.branchSyncPlan(of: nil, status: status()) == nil)
    }

    /// Nápověda musí odpovědět na obojí, na co se u přetlačení ptáš: **kolik commitů** a **přes
    /// co**.
    @Test("Nápověda říká, co se stane, dřív než se to stane")
    func explainsWhatWillHappen() throws {
        let plan = try #require(Policy.branchSyncPlan(of: detail(), status: status(ahead: 3, behind: 4)))
        let help = Policy.branchSyncHelp(for: plan)

        #expect(help.contains("3 commity"))
        #expect(help.contains("main"))
        #expect(help.contains("issue-466-sync-branch"))
        #expect(help.contains("9c1de02"))
        #expect(help.contains("push selže"))
    }

    // MARK: - Která akce je hlavní

    /// Z návrhu (sekce 36): když je zeleno, je hlavní `Mergnout…`; jinak `Srovnat s main`.
    @Test("Hlavní akce se řídí tím, jestli jde mergnout")
    func picksThePrimaryAction() {
        #expect(Policy.primaryBranchAction(merge: .allowed) == .merge)
        #expect(Policy.primaryBranchAction(merge: .blocked([.behind(base: "main")])) == .sync)
        #expect(Policy.primaryBranchAction(merge: .absent) == .sync)
    }

    // MARK: - Řádek stavu

    /// Návrh kreslí `o 4 commity vzadu`. Do #466 tam stálo `za základem` bez čísla, protože
    /// `mergeStateStatus` na to neodpovídá — u větve o commit pozadu vrací `CLEAN` (změřeno na
    /// `prism-review-sandbox#9`).
    @Test("Řádek stavu nese počet commitů, o které je větev vzadu")
    func showsHowFarBehind() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(),
                commits: [],
                status: status(ahead: 3, behind: 4),
                checks: [],
                blockingFindings: 0
            )
        )

        #expect(section.facts.first?.answer == "o 4 commity vzadu")
        #expect(section.facts.first?.tone == .blocked)
    }

    @Test("Srovnaná větev zůstává srovnaná")
    func staysCleanWhenNotBehind() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(),
                commits: [],
                status: status(ahead: 3, behind: 0),
                checks: [],
                blockingFindings: 0
            )
        )

        #expect(section.facts.first?.answer == "srovnaná")
    }

    // MARK: - Jméno základu v popisku

    /// **Popisek nesmí tvrdit `main` v repozitáři, kde se základ jmenuje `master`.** Tři stavy,
    /// protože jméno dorazí ve **třech různých chvílích**: plán srovnání ho zná až s divergencí,
    /// plán merge už s detailem a commity, a než přijde hlavička, není odkud ho vzít.
    @Test("Popisek bere jméno základu z prvního plánu, který ho zná")
    func namesTheBaseFromTheFirstPlanThatKnowsIt() throws {
        let full = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(base: "master"),
                commits: [],
                status: status(),
                checks: [],
                blockingFindings: 0
            )
        )
        #expect(Policy.syncBase(of: full) == "master")

        // Bez divergence se plán srovnání nesloží — jméno ale zná plán merge, takže se `master`
        // v popisku **neztratí**.
        let withoutDivergence = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(base: "master"),
                commits: [],
                status: .loading,
                checks: [],
                blockingFindings: 0
            )
        )
        #expect(withoutDivergence.syncPlan == nil)
        #expect(Policy.syncBase(of: withoutDivergence) == "master")

        // Bez hlavičky PR není odkud jméno vzít; teprve tady platí `main` z návrhu — a v tom stavu
        // je tlačítko stejně zakázané.
        let empty = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: nil,
                commits: nil,
                status: nil,
                checks: nil,
                blockingFindings: 0
            )
        )
        #expect(Policy.syncBase(of: empty) == Policy.fallbackBase)
        #expect(!empty.sync.isAllowed)
    }

    // MARK: - Které překážky si žádají větu v panelu

    /// **Zašedlé tlačítko bez věty v panelu je otázka, na kterou okno neodpoví** (#392, #465) —
    /// ale většina překážek srovnání je v panelu napsaná **už jinde**, takže vypsat je všechny
    /// znamená totéž dvakrát. Tvrdí se tedy obojí: co větu dostane, a co ne.
    ///
    /// Fork je ten jediný důvod, o kterém v sekci nemluví nic jiného — ani řádek stavu, ani hláška
    /// pod akcemi. Bez věty by u něj tlačítko mlčelo.
    @Test("Vlastní větu v panelu dostane jedině hlava v jiném repozitáři")
    func warnsInThePanelOnlyAboutAForeignHead() throws {
        let fork = offer(detail: detail(cross: true), status: status())
        #expect(Policy.syncWarnings(fork) == [.foreignBranch(known: true)])

        let unknown = offer(detail: detail(cross: nil), status: status())
        #expect(Policy.syncWarnings(unknown) == [.foreignBranch(known: false)])

        // Vypnutá brána, stav PR a nenačtená hlavička jsou překážky **obou** akcí, takže je nese
        // výstraha mergnutí — druhá věta by byla tatáž věta podruhé.
        let gateOff = offer(
            editing: .blocked("Odesílání na GitHub je vypnuté."),
            detail: detail(),
            status: status()
        )
        #expect(Policy.syncWarnings(gateOff).isEmpty)
        #expect(!gateOff.obstacles.isEmpty)

        // O srovnané větvi, o konfliktu i o rozdělaném rebasu mluví řádky nad výstrahou, resp.
        // hláška pod akcemi — a ta je konkrétnější.
        #expect(Policy.syncWarnings(offer(detail: detail(), status: status(ahead: 3, behind: 0))).isEmpty)
        #expect(
            Policy.syncWarnings(offer(detail: detail(), status: status(.conflicting, .dirty))).isEmpty
        )
        #expect(
            Policy.syncWarnings(
                offer(detail: detail(), status: status(), sync: .unfinished(files: ["a.php"]))
            ).isEmpty
        )
        #expect(Policy.syncWarnings(offer(detail: detail(), status: .loading)).isEmpty)
        #expect(Policy.syncWarnings(offer(detail: detail(), status: status(), sync: .rebasing)).isEmpty)

        // A na povolené nabídce nemá co varovat.
        #expect(Policy.syncWarnings(offer(detail: detail(), status: status())).isEmpty)
    }
}
