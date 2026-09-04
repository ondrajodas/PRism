import Foundation
import Testing

@testable import PRism

/// Volba metody merge (#556) — **vyčerpávající výčet**, protože je to čistá funkce a je to jediné
/// místo, kde se o nabídce, o předvybrané hodnotě a o textech rozhoduje.
///
/// Nejcennější tvrzení v téhle suitě jsou ta, která říkají, že se něco **NEstalo**: že se
/// nepovolená metoda nepodstrčí jinou, že se nepovolená pilulka z nabídky neztratí a že se u řádku
/// `commitů` nad nevybranou metodou nevypíše číslo.
@Suite("Volba metody merge (#556)")
struct MergeMethodChoiceTests {
    /// Změřený stav `ondrajodas/PRism`: všechny tři metody, tělo squashe ze zpráv commitů.
    private let all = RepositoryMergeSettings(
        allowsMergeCommit: true,
        allowsSquash: true,
        allowsRebase: true,
        squashBody: .commitMessages,
        mergeCommitBody: .pullRequestTitle
    )

    /// Změřený stav `keboola/job-queue-daemon`: rebase nepovolený.
    private let withoutRebase = RepositoryMergeSettings(
        allowsMergeCommit: true,
        allowsSquash: true,
        allowsRebase: false,
        squashBody: .commitMessages,
        mergeCommitBody: .pullRequestTitle
    )

    // MARK: - Nabídka

    /// **Pořadí je pevné**, ne podle toho, co repo povoluje: nabídka, ve které se pilulky
    /// přeskládají podle repa, se nedá naučit.
    @Test("Nabídka má tři metody v pevném pořadí")
    func offersThreeInAFixedOrder() {
        #expect(Policy.mergeMethods == [.squash, .mergeCommit, .rebase])
        #expect(Policy.mergeMethodOptions(in: all).map(\.method) == [.squash, .mergeCommit, .rebase])
        #expect(
            Policy.mergeMethodOptions(in: nil).map(\.method) == [.squash, .mergeCommit, .rebase]
        )
    }

    /// **Nepovolená metoda z nabídky nezmizí, jen se nedá vybrat.** Zmizet nesmí, jinak se nedá
    /// poznat rozdíl mezi „repo to nepustí“ a „tuhle metodu GitHub nemá“.
    @Test("Nepovolená metoda v nabídce zůstane, jen nevybratelná")
    func keepsTheRefusedMethodInTheOffer() {
        let options = Policy.mergeMethodOptions(in: withoutRebase)

        #expect(options.count == 3)
        #expect(options.first { $0.method == .rebase }?.isSelectable == false)
        #expect(options.filter(\.isSelectable).map(\.method) == [.squash, .mergeCommit])
    }

    /// **„Nevím“ se chová jako „ano“.** Nad repem bez práva zápisu (`cli/cli`) vrací GitHub
    /// všechny tři příznaky jako `null`; rozhodnout z toho, že metoda nejde, je u nevratné akce
    /// tatáž chyba jako rozhodnout, že jde.
    @Test("Nezjištěné příznaky nabídnou všechny tři a nic netvrdí")
    func unknownFlagsOfferEverything() {
        // `allSatisfy(\.isSelectable)` uvnitř `#expect` neprojde: keypath se převede na funkci,
        // kterou překladač u `rethrows` bere jako potenciálně vyhazující. Proto výčet, ne predikát.
        #expect(Policy.mergeMethodOptions(in: nil).map(\.isSelectable) == [true, true, true])
        #expect(
            Policy.mergeMethodOptions(in: RepositoryMergeSettings()).map(\.isSelectable)
                == [true, true, true]
        )
        // A **výčet povolených zůstane prázdný**: „nevíme“ není totéž jako „povoluje všechny“, jen
        // se to v nabídce chová stejně. Věta „repozitář povoluje …“ se z toho složit nedá.
        #expect(Policy.allowedMergeMethods(in: nil).isEmpty)
        #expect(Policy.allowedMergeMethods(in: RepositoryMergeSettings()).isEmpty)
    }

    /// **Jedna podmínka pro kresbu i pro zápis do konfigurace.** Nabídka v potvrzení, přeškrtnutá
    /// položka v nastavení a stráž, která zahazuje zápis nepovolené metody, se ptají **téže**
    /// funkce — dvě podmínky by znamenaly, že se dá uložit hodnota, kterou nabídka nedovolí vybrat.
    @Test("Vybratelnost rozhoduje jedna funkce, a nevím znamená ano")
    func decidesSelectabilityInOnePlace() {
        #expect(Policy.isMergeMethodSelectable(.rebase, in: withoutRebase) == false)
        #expect(Policy.isMergeMethodSelectable(.squash, in: withoutRebase))
        #expect(Policy.isMergeMethodSelectable(.rebase, in: nil))
        #expect(Policy.isMergeMethodSelectable(.rebase, in: RepositoryMergeSettings()))
        // A nabídka z ní doopravdy vychází, ne z druhé podmínky.
        #expect(
            Policy.mergeMethodOptions(in: withoutRebase).map(\.isSelectable)
                == Policy.mergeMethods.map { Policy.isMergeMethodSelectable($0, in: withoutRebase) }
        )
    }

    @Test("Povolené metody se vypíšou v pevném pořadí")
    func listsAllowedMethods() {
        #expect(Policy.allowedMergeMethods(in: all) == [.squash, .mergeCommit, .rebase])
        #expect(Policy.allowedMergeMethods(in: withoutRebase) == [.squash, .mergeCommit])
    }

    // MARK: - Předvybraná metoda

    @Test("Povolená výchozí metoda se předvybere")
    func preselectsTheDefault() {
        #expect(Policy.initialMergeMethod(default: .squash, in: all) == .squash)
        #expect(Policy.initialMergeMethod(default: .mergeCommit, in: all) == .mergeCommit)
        // Nezjištěné příznaky nesmí předvybrání zabít — to by z běžného stavu (repo bez práva
        // zápisu) udělalo zastavený merge.
        #expect(Policy.initialMergeMethod(default: .rebase, in: nil) == .rebase)
    }

    /// **Nepovolená výchozí metoda se nepodstrčí jinou** — tohle je to tvrzení, kvůli kterému
    /// funkce existuje. Tiše přepnout na první povolenou by znamenalo, že u nevratné akce odejde
    /// něco, o co nikdo nepožádal.
    @Test("Nepovolená výchozí metoda nevybere nic")
    func doesNotSubstituteARefusedDefault() {
        #expect(Policy.initialMergeMethod(default: .rebase, in: withoutRebase) == nil)
        // A **není to jen „ne rebase“**: první povolená metoda se nesmí objevit nikde v odpovědi.
        #expect(Policy.initialMergeMethod(default: .rebase, in: withoutRebase) != .squash)
        #expect(Policy.initialMergeMethod(default: .rebase, in: withoutRebase) != .mergeCommit)
    }

    // MARK: - Výstraha

    /// Věta se objeví **jedině** nad nepovolenou výchozí metodou. Nad povolenou by to byla
    /// výstraha o ničem.
    @Test("Výstraha vyjmenuje, co repo povoluje, a řekne, co s tím")
    func warnsWithTheNextStep() {
        #expect(Policy.mergeMethodWarning(default: .squash, in: all) == nil)
        #expect(Policy.mergeMethodWarning(default: .rebase, in: nil) == nil)

        let warning = Policy.mergeMethodWarning(default: .rebase, in: withoutRebase)
        #expect(
            warning == "Výchozí metoda rebase tady nejde — repozitář povoluje squash"
                + " a merge commit. Vyber jednu z nich, nebo přepni výchozí hodnotu v nastavení"
                + " tohohle repa."
        )
    }

    /// Jedna povolená metoda dá **jiné sloveso** — „Vyber jednu z nich“ nad jediným jménem je
    /// věta, která tvrdí výběr, kde žádný není.
    @Test("Nad jednou povolenou metodou se neříká jednu z nich")
    func warnsAboutASingleAllowedMethod() {
        let single = RepositoryMergeSettings(
            allowsMergeCommit: false,
            allowsSquash: true,
            allowsRebase: false
        )

        #expect(
            Policy.mergeMethodWarning(default: .rebase, in: single)
                == "Výchozí metoda rebase tady nejde — repozitář povoluje jen squash. Vyber ji,"
                + " nebo přepni výchozí hodnotu v nastavení tohohle repa."
        )
    }

    /// **Prázdný výčet je stav, ne nemožnost.** GitHub aspoň jednu metodu povolit musí, ale kdyby
    /// přišlo samé `false`, nesmí z toho vzniknout věta „repozitář povoluje“ s ničím za ní.
    @Test("Bez jediné povolené metody věta neslibuje výběr")
    func warnsWhenNothingIsAllowed() throws {
        let none = RepositoryMergeSettings(
            allowsMergeCommit: false,
            allowsSquash: false,
            allowsRebase: false
        )
        let warning = try #require(Policy.mergeMethodWarning(default: .squash, in: none))

        #expect(!warning.contains("repozitář povoluje"))
        #expect(warning.contains("nepovoluje ani žádnou jinou"))
    }

    // MARK: - Věta o jednorázovém přepnutí

    @Test("Věta o přepnutí je jen po přepnutí")
    func notesTheOverrideOnlyWhenOverridden() {
        #expect(Policy.mergeMethodOverrideNote(selected: .squash, default: .squash) == nil)
        #expect(
            Policy.mergeMethodOverrideNote(selected: .mergeCommit, default: .squash)
                == "Přepnutá metoda platí pro tenhle merge — výchozí hodnota v nastavení zůstává"
                + " squash."
        )
    }

    // MARK: - Řádky výpisu

    /// **`commitů 3 → 1` je věta o squashi**, ne údaj o PR — proto se s metodou přepisuje. Řádek
    /// payloadu, který nad jinou metodou lže, je horší než řádek, který tam není.
    @Test("Řádek commitů se s metodou přepíše")
    func rewritesTheCommitsLine() {
        #expect(Policy.mergeCommitsLine(method: .squash, commits: 3) == "3 → 1")
        #expect(Policy.mergeCommitsLine(method: .mergeCommit, commits: 3) == "3 + merge commit")
        #expect(Policy.mergeCommitsLine(method: .rebase, commits: 3) == "3 přehrané")
    }

    /// **Skloňuje se** — „1 přehrané“ a „5 přehrané“ jsou zrovna ty chyby, kvůli kterým `Plural`
    /// existuje.
    @Test("Počet přehraných commitů se skloňuje")
    func declinesTheRebaseCount() {
        #expect(Policy.mergeCommitsLine(method: .rebase, commits: 1) == "1 přehraný")
        #expect(Policy.mergeCommitsLine(method: .rebase, commits: 4) == "4 přehrané")
        #expect(Policy.mergeCommitsLine(method: .rebase, commits: 7) == "7 přehraných")
    }

    /// **Titulek se posílá u dvou metod ze tří.** U rebase žádný commit nevzniká, takže by to bylo
    /// pole, které GitHub zahodí — a potvrzení by slibovalo titulek, který se nikde neobjeví.
    @Test("Titulek je u squashe, u merge commitu jiný a u rebase žádný")
    func buildsTheTitlePerMethod() {
        #expect(
            Policy.mergeCommitTitle(
                method: .squash, title: "chore: deps", number: 85, head: "chore/deps"
            ) == "chore: deps (#85)"
        )
        #expect(
            Policy.mergeCommitTitle(
                method: .mergeCommit, title: "chore: deps", number: 85, head: "chore/deps"
            ) == "Merge pull request #85 from chore/deps"
        )
        #expect(
            Policy.mergeCommitTitle(
                method: .rebase, title: "chore: deps", number: 85, head: "chore/deps"
            ) == nil
        )
    }

    /// Číslo PR se sází **ručně**, ne formátováním: `#1085` není množství a v české locale by
    /// z něj vyšlo `#1 085`. Platí to i pro titulek merge commitu, ne jen pro squash.
    @Test("Číslo PR v titulku merge commitu se neformátuje")
    func doesNotGroupTheNumber() {
        #expect(
            Policy.mergeCommitTitle(
                method: .mergeCommit, title: "x", number: 21663, head: "b"
            ) == "Merge pull request #21663 from b"
        )
    }

    /// **Věta o těle se přestala hádat.** Do #556 tvrdila zprávy commitů vždycky; teď se skládá
    /// z přečteného nastavení, takže v repu s `PR_BODY` řekne popis pull requestu.
    @Test("Věta o těle vychází z přečteného nastavení repozitáře")
    func tellsWhereTheBodyComesFrom() {
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 3, base: "main", in: all)
                == "Tělo squash commitu složí GitHub ze zpráv 3 commitů."
        )
        #expect(
            Policy.mergeBodyNotice(method: .mergeCommit, commits: 3, base: "main", in: all)
                == "Tělo merge commitu složí GitHub z titulku pull requestu."
        )
        let body = RepositoryMergeSettings(squashBody: .pullRequestBody, mergeCommitBody: .blank)
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 3, base: "main", in: body)
                == "Tělo squash commitu složí GitHub z popisu pull requestu."
        )
        #expect(
            Policy.mergeBodyNotice(method: .mergeCommit, commits: 3, base: "main", in: body)
                == "Tělo merge commitu zůstane prázdné."
        )
    }

    /// **Kde se to zjistit nepodařilo, zůstává přiznání** — nevědět je vlastní odpověď, tatáž
    /// úvaha jako u `nevím` v řádku stavu větve.
    @Test("Bez přečteného nastavení se tělo přizná, ne uhádne")
    func admitsAnUnknownBody() {
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 3, base: "main", in: nil)
                == "Tělo squash commitu složí GitHub podle nastavení repozitáře."
        )
        // A **nesmí to být dnešní věta o commitech**: právě ta v repu s `PR_BODY` lhala.
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 3, base: "main", in: nil)
                .contains("ze zpráv") == false
        )
    }

    /// Skloňuje se i tady — „ze zpráv 1 commitů“ je ta chyba, kvůli které `Plural` existuje.
    @Test("Počet commitů ve větě o těle se skloňuje")
    func declinesTheBodyCount() {
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 1, base: "main", in: all)
                == "Tělo squash commitu složí GitHub ze zpráv 1 commitu."
        )
        #expect(
            Policy.mergeBodyNotice(method: .squash, commits: 12, base: "main", in: all)
                == "Tělo squash commitu složí GitHub ze zpráv 12 commitů."
        )
    }

    /// **U rebase se o těle nemluví vůbec** — mluvit o „nastavení repozitáře“ by tady bylo
    /// tvrzení o poli, které se u rebase nečte.
    @Test("U rebase věta mluví o přehrání, ne o těle")
    func explainsRebaseInsteadOfABody() {
        let notice = Policy.mergeBodyNotice(method: .rebase, commits: 3, base: "main", in: all)

        #expect(notice == "Rebase žádný commit nevytváří — commity se přehrají nad main,"
            + " jak jsou, i s titulky a těly.")
        #expect(!notice.contains("nastavení repozitáře"))
    }

    // MARK: - Payload

    /// **Payload se skládá z návrhu, ne drží zvlášť** — a to je to, co drží kresbu a odesílané
    /// dohromady: sheet i `MergeRequest.Payload` čtou tentýž `MergePlan`.
    @Test("Návrh složí payload pro každou metodu jinak")
    func buildsAPlanPerMethod() {
        let proposal = MergeProposal(
            pullRequest: PRIdentifier("ondrajodas/PRism#556")!,
            headSha: "9bb4352",
            head: "chore/deps",
            base: "main",
            commits: 3,
            title: "chore: modernize dependencies"
        )

        #expect(proposal.plan(with: .squash).commitTitle == "chore: modernize dependencies (#556)")
        #expect(
            proposal.plan(with: .mergeCommit).commitTitle
                == "Merge pull request #556 from chore/deps"
        )
        #expect(proposal.plan(with: .rebase).commitTitle == nil)
        // Hlava se metodou **nemění** — je to podmínka volání, ne údaj o metodě.
        #expect(Policy.mergeMethods.map { proposal.plan(with: $0).headSha } == ["9bb4352", "9bb4352", "9bb4352"])
    }
}
