import Foundation
import Testing

@testable import PRism

/// Nabídka `Rebase` (#466) — **výčtem, protože je to čistá funkce**.
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
        sync: BranchSyncState? = nil,
        resolvesConflicts: Bool = false
    ) -> Policy.SyncOffer {
        Policy.branchSyncOffer(
            editing: editing,
            plan: Policy.branchSyncPlan(of: detail, status: status),
            detail: detail,
            status: status,
            sync: sync,
            resolvesConflicts: resolvesConflicts
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

    /// **Bez `claude` se konflikt přiznává, ne zkouší** — je to chování do #467: rebase by skončil
    /// konfliktem a rozdělanou prací v cache, kterou by nemělo kdo slít.
    @Test("Konflikt srovnání zastaví, když ho nemá kdo slít")
    func refusesOnConflictWithoutResolver() {
        let offer = offer(detail: detail(), status: status(.conflicting, .dirty))

        #expect(offer.obstacles.contains(.conflicting(base: "main")))
        #expect(offer.isAllowed == false)
    }

    /// **Druhý směr, a je to celá pointa #467**: se session, která smí psát, konflikt překážka
    /// není. Bez tohohle tvrzení by se `resolvesConflicts` dalo zapomenout předat a `Rebase` by
    /// nad konfliktní větví zůstal zašedlý — tedy zrovna tam, kde má #467 fungovat.
    @Test("Konflikt srovnání nezastaví, když ho slije session")
    func allowsConflictWithResolver() {
        let allowed = offer(
            detail: detail(),
            status: status(.conflicting, .dirty),
            resolvesConflicts: true
        )

        #expect(allowed == .allowed)
        #expect(!allowed.obstacles.contains(.conflicting(base: "main")))
    }

    /// **Ostatní překážky slévání neodklízí.** Konflikt je jediné, co `resolvesConflicts` mění —
    /// vypnutá brána, zavřený PR ani rozdělaný rebase s ním nemají nic společného, a kdyby se ta
    /// podmínka napsala o řádek výš, spolkla by je taky.
    @Test("Slévání konfliktů neodklidí jiné překážky")
    func resolverDoesNotClearOtherObstacles() {
        let unfinished = offer(
            detail: detail(),
            status: status(.conflicting, .dirty),
            sync: .unfinished(files: ["a.php"]),
            resolvesConflicts: true
        )
        #expect(unfinished.obstacles == [.unfinishedRebase])

        let gateOff = offer(
            editing: .blocked("Odesílání je vypnuté."),
            detail: detail(),
            status: status(.conflicting, .dirty),
            resolvesConflicts: true
        )
        #expect(gateOff.obstacles == [.notAllowed("Odesílání je vypnuté.")])
    }

    /// **Věta u nesplněné překážky mluví o `claude`, ne o terminálu jako do #466.** Text v UI nesmí
    /// tvrdit víc, než data unesou: „konflikty odsud vyřešit neumím“ přestalo být pravda.
    @Test("Věta o konfliktu říká, že chybí claude")
    func conflictSentenceNamesTheMissingTool() {
        let sentence = Policy.SyncObstacle.conflicting(base: "main").sentence

        #expect(sentence.contains("nemá kdo"))
        #expect(sentence.contains("claude"))
    }

    /// **Nápověda u `Rebase` musí říct, že slévání stojí peníze** — a jedině tam, kde hrozí.
    /// Kliknutí, které umí spustit až tři session, je informace **před** kliknutím, ne po něm.
    @Test("Nápověda mluví o ceně slévání jen tam, kde se slévá")
    func helpMentionsCostOnlyWithResolver() {
        let plan = BranchSyncPlan(
            pullRequest: PRIdentifier(repo: RepoID(owner: "o", name: "r"), number: 1),
            branch: "feature",
            base: "main",
            expectedRemoteSha: "abc",
            replaying: 2,
            behind: 4
        )

        #expect(!Policy.branchSyncHelp(for: plan).contains("peníze"))
        #expect(Policy.branchSyncHelp(for: plan, resolvesConflicts: true).contains("peníze"))
        // Obojí pořád říká to podstatné: do remote se nesáhne.
        #expect(Policy.branchSyncHelp(for: plan, resolvesConflicts: true).contains("Do remote se nesáhne"))
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

    /// **Nápověda u prvního tlačítka mluví jen o prvním kroku, a je to celá pointa rozdělení
    /// akce.** Tlačítko přehraje commity v kopii repa a do remote nesáhne — takže **nesmí** slibovat
    /// přetlačení ani vysvětlovat lease. Ta věta se přestěhovala do potvrzení, kde patří.
    ///
    /// Tvrdí se proto obojí: co v nápovědě **je** a co v ní **není**. Bez té druhé půlky by se dala
    /// věta o pushi vrátit a nikdo by si toho nevšiml.
    @Test("Nápověda mluví o rebasu, ne o přetlačení")
    func explainsOnlyTheFirstStep() throws {
        let plan = try #require(Policy.branchSyncPlan(of: detail(), status: status(ahead: 3, behind: 4)))
        let help = Policy.branchSyncHelp(for: plan)

        #expect(help.contains("3 commity"))
        #expect(help.contains("main"))
        #expect(help.contains("kopii repa"))
        #expect(help.contains("Do remote se nesáhne"))
        // Co v ní být **nesmí**: lease ani slib, že se něco přetlačí.
        #expect(!help.contains("push selže"))
        #expect(!help.contains("9c1de02"))
        #expect(!help.lowercased().contains("force-with-lease"))
    }

    /// **Věta o pojistce patří do potvrzení** — tam, kde se doopravdy pushuje. Vypsané je, přes co
    /// se přetlačuje, na jakou hlavu lease čeká a **co se stane, když se remote pohnul**.
    @Test("Výstraha v potvrzení mluví o lease a o tom, co se stane")
    func warnsAboutTheLeaseInTheConfirmation() {
        let warning = Policy.leaseWarning(
            for: BranchPushPlan(
                pullRequest: mine,
                branch: "issue-466-sync-branch",
                expectedRemoteSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
                sha: "1111222233334444555566667777888899990000",
                worktree: URL(filePath: "/tmp/sync")
            )
        )

        #expect(warning.contains("issue-466-sync-branch"))
        #expect(warning.contains("--force-with-lease"))
        #expect(warning.contains("9c1de02"))
        #expect(warning.contains("push selže"))
        #expect(warning.contains("nic se nepřepíše"))
    }

    // MARK: - Která akce je hlavní

    /// Z návrhu (sekce 36): když je zeleno, je hlavní `Mergnout…`; jinak `Rebase`.
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
                checks: []
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
                checks: []
            )
        )

        #expect(section.facts.first?.answer == "srovnaná")
    }

    // MARK: - Jméno základu se z popisku přestěhovalo

    /// **Popisek je od té doby jen `Rebase`, ale jméno základu se neztratilo** — a tohle tvrzení
    /// je jeho pojistka.
    ///
    /// Do přejmenování akcí (rozhodnutí uživatele: `Rebase` a `Force push` místo českých sloves)
    /// nesl popisek `Srovnat s master`, takže se jméno základu tvrdilo přímo na tlačítku. Krátký
    /// popisek je změřený: `Srovnat s main` mělo 87 bodů a tři tlačítka v řadě potřebovala 279
    /// z 278 dostupných, takže `Rebase na master` by ten problém zhoršilo.
    ///
    /// Jméno proto nese **nápověda pod kurzorem** (a k tomu řádek stavu `head → base`, o kterém
    /// mluví `BranchMergeTests`). Kdyby zmizelo i odsud, přestalo by být v repozitáři s `master`
    /// poznat, nad co se vlastně rebasuje.
    @Test("Nápověda nese jméno základu, i když popisek už ne")
    func theHelpStillNamesTheBase() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(base: "master"),
                commits: [],
                status: status(),
                checks: []
            )
        )
        let plan = try #require(section.syncPlan)

        #expect(Policy.branchSyncHelp(for: plan).contains("master"))
        // A **ne** `main` z návrhu: v tomhle repozitáři se základ jmenuje jinak.
        #expect(!Policy.branchSyncHelp(for: plan).contains("main"))
    }

    /// Bez hlavičky PR se akce **nenabízí** — dřív to viselo u testu na jméno základu, ale je to
    /// vlastní tvrzení a s popiskem nemá co dělat.
    @Test("Bez hlavičky PR se rebase nenabízí")
    func offersNothingWithoutTheHeader() throws {
        let empty = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: nil,
                commits: nil,
                status: nil,
                checks: nil
            )
        )

        #expect(empty.syncPlan == nil)
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

    // MARK: - Na co se přeptat v tiku (#466, z proklikání)

    /// **Výčtem, protože je to čistá funkce a rozhoduje o dotazu na GitHub.**
    ///
    /// Existuje proto, že „pozadu“ nezávisí na hlavě PR: změřeno na `prism-review-sandbox#9`, že
    /// po commitu do `master`u zůstal `updated_at` PR nezměněný, takže se stav klíčovaný razítkem
    /// PR o posun základu nemá jak dozvědět.
    @Test("Přeptá se jen na otevřeném vlastním PR")
    func probesOnlyTheOpenOwnPullRequest() {
        let foreign = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 1)
        let ownership: (PRIdentifier) -> PullRequestOwnership = { $0 == self.mine ? .mine : .theirs }

        // Vlastní a otevřené — jediný případ, kdy se ptáme.
        #expect(Policy.divergenceProbe(open: .pullRequest(mine), ownership: ownership) == mine)

        // Cizí PR: sekce `Větev` se tam nekreslí, byl by to dotaz za nic.
        #expect(Policy.divergenceProbe(open: .pullRequest(foreign), ownership: ownership) == nil)

        // Domácí záložka: ta hodnota se nikde nekreslí.
        #expect(Policy.divergenceProbe(open: .home, ownership: ownership) == nil)
    }


    // MARK: - Výpis commitů v potvrzení (#466, z proklikání)

    /// **Výčtem u stropu, protože o něm rozhoduje jedno číslo a plete se o jeden.**
    @Test("Výpis commitů má strop a zbytek počítá")
    func capsTheCommitList() {
        func commits(_ n: Int) -> [RebasedCommit] {
            (0..<n).map { RebasedCommit(sha: "sha\($0)", title: "krok \($0)") }
        }

        // Pod stropem i na stropu se vypíše všechno a nic nezbývá.
        #expect(Policy.pushedCommitList(commits(0)) == ([], 0))
        #expect(Policy.pushedCommitList(commits(1)).shown.count == 1)
        #expect(Policy.pushedCommitList(commits(1)).hidden == 0)
        #expect(Policy.pushedCommitList(commits(8)).shown.count == 8)
        #expect(Policy.pushedCommitList(commits(8)).hidden == 0)

        // Nad stropem se vypíše strop a **zbytek se počítá**, neořezává potichu.
        #expect(Policy.pushedCommitList(commits(9)).shown.count == 8)
        #expect(Policy.pushedCommitList(commits(9)).hidden == 1)
        #expect(Policy.pushedCommitList(commits(70)).shown.count == 8)
        #expect(Policy.pushedCommitList(commits(70)).hidden == 62)

        // Součet vždycky vyjde na celý seznam — jinak by se něco „ztratilo“ mezi vypsaným
        // a spočítaným.
        for n in 0...20 {
            let list = Policy.pushedCommitList(commits(n))
            #expect(list.shown.count + list.hidden == n)
        }
    }

    /// **Vypisuje se od nejstaršího a v tom pořadí, v jakém leží na větvi** — pořadí je informace:
    /// z výpisu se má poznat, co se na co přehrálo.
    @Test("Výpis zachovává pořadí")
    func keepsTheOrder() {
        let commits = (0..<12).map { RebasedCommit(sha: "sha\($0)", title: "krok \($0)") }

        let shown = Policy.pushedCommitList(commits).shown

        #expect(shown.map(\.commit.title) == (0..<8).map { "krok \($0)" })
    }

    /// **Původ řádku vede po pořadí, a je to změřené:** po rebasu leží commity z base **dole**
    /// a přehrané nad nimi, takže prvních `fromBase` řádků je z base. Bez tohohle tvrzení by se
    /// značka `z base` mohla obrátit a nikdo by si toho nevšiml.
    @Test("Z base jsou první řádky, přehrané ty nad nimi")
    func marksTheCommitsThatCameFromTheBase() {
        let commits = (0..<5).map { RebasedCommit(sha: "sha\($0)", title: "krok \($0)") }

        // Dva z base, tři přehrané — tedy tvar, který vyšel z měření (#10: 1 z base, 1 přehraný).
        let rows = Policy.pushedCommitList(commits, fromBase: 2).shown

        #expect(rows.map(\.isFromBase) == [true, true, false, false, false])
        // A když z base nepřišlo nic, není označený ani jeden.
        #expect(Policy.pushedCommitList(commits, fromBase: 0).shown.allSatisfy { !$0.isFromBase })
        // Identita řádku je sha commitu, ne pořadí — na tom stojí `ForEach` bez `enumerated()`.
        #expect(rows.map(\.id) == commits.map(\.sha))
    }

    /// Krátká sha je **sedm znaků**, jako všude jinde v okně.
    @Test("Krátká sha má sedm znaků")
    func shortensTheSha() {
        let commit = RebasedCommit(sha: "1111222233334444555566667777888899990000", title: "x")

        #expect(commit.shortSha == "1111222")
    }

    // MARK: - Agent na vlastním PR (#510)

    /// **Věta o výsledku nesmí mluvit o rebase**, když žádný neproběhl — a rozhoduje o tom
    /// **původ**, ne počty. Je to tatáž třída chyby, jakou Copilot v tomhle repu nachází: text,
    /// který tvrdí víc, než data unesou.
    @Test("Commit agenta má vlastní větu, ne tu o rebase")
    func theAgentResultDoesNotClaimARebase() {
        let branch = RebasedBranch(
            worktree: URL(filePath: "/cache/PRism/x-sync"),
            headSha: "cccc",
            rebasedFrom: "aaaa",
            arriving: [RebasedCommit(sha: "cccc", title: "fix: address review feedback (#510)")],
            replayed: 1,
            origin: .agent,
            fix: AgentFixAnswer(files: ["App/A.swift", "Tests/ATests.swift"], summary: "opraveno")
        )

        let sentence = BranchSyncState.rebased(branch).sentence

        #expect(sentence.contains("Agent upravil 2 soubory"))
        #expect(!sentence.lowercased().contains("rebase"))
        // A po rebase zůstává věta z #466 beze změny.
        #expect(BranchSyncState.rebased(Self.rebased(replayed: 2)).sentence.hasPrefix("Rebase hotový"))
    }

    /// **Práce agenta se pozná i u úspěchu**, ne jen u nepřijatého výsledku — na tom stojí slovo na
    /// tlačítku (`Zahodit změny` místo `Zahodit rebase`). Vyšlo to z renderu sondy, kde pod větou
    /// „Agent upravil 2 soubory“ stálo `Zahodit rebase`.
    @Test("Práce agenta se pozná u přijatého i nepřijatého výsledku")
    func recognisesTheAgentsWork() {
        var branch = Self.rebased(replayed: 1)
        branch.origin = .agent

        #expect(BranchSyncState.rebased(branch).isAgentWork)
        #expect(BranchSyncState.fixRejected(detail: "psal mimo strom").isAgentWork)
        // Po rebase ne — tam v cache leží přehrané commity.
        #expect(!BranchSyncState.rebased(Self.rebased(replayed: 1)).isAgentWork)
        // A `nic se nezměnilo` taky ne: v cache po něm nic neleží, takže není co zahazovat.
        #expect(!BranchSyncState.fixedNothing(detail: nil).isAgentWork)
        #expect(!BranchSyncState.fixedNothing(detail: nil).hasDiscardableWork)
        #expect(!BranchSyncState.fixedNothing(detail: nil).offersTerminal)
    }

    /// Běžící agent je **vlastní odpověď na „co se děje“**, ne `running`: nespustilo to kliknutí.
    @Test("Běžící agent má vlastní překážku a vlastní větu")
    func theRunningAgentHasItsOwnObstacle() {
        let offer = Policy.branchSyncOffer(
            editing: .allowed,
            plan: nil,
            detail: detail(),
            status: nil,
            sync: .fixing(items: 2, since: .distantPast)
        )

        #expect(offer.obstacles.contains(.agentRunning))
        #expect(!offer.obstacles.contains(.running))
        #expect(Policy.SyncObstacle.agentRunning.sentence.contains("agent"))
        // A nepřijatá práce agenta brání rebasu ze stejného důvodu jako rozdělaný rebase.
        #expect(
            Policy.branchSyncOffer(
                editing: .allowed,
                plan: nil,
                detail: detail(),
                status: nil,
                sync: .fixRejected(detail: "psal mimo strom")
            )
            .obstacles.contains(.rejectedFix)
        )
    }

    private static func rebased(replayed: Int) -> RebasedBranch {
        RebasedBranch(
            worktree: URL(filePath: "/cache/PRism/x-sync"),
            headSha: "cccc",
            rebasedFrom: "aaaa",
            arriving: (0..<replayed).map { RebasedCommit(sha: "sha\($0)", title: "krok \($0)") },
            replayed: replayed
        )
    }
}
