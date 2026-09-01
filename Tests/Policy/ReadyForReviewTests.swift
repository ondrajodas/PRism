import Foundation
import Testing

@testable import PRism

/// `Připravit k review` (#482) — **výčtem, protože je to čistá funkce**.
///
/// Nejcennější tvrzení tady jsou ta záporná: na cizím PR se akce **nekreslí vůbec**, nad
/// nedraftem taky ne, a s vypnutou branou je **zašedlá s důvodem**. Přepnutí vyžádá review od
/// vlastníků kódu, tedy odešle upozornění, které se odebráním nevezme zpět — omyl v téhle funkci
/// se tedy nedá vzít zpět celý.
@Suite("Připravit k review")
struct ReadyForReviewTests {
    private let mine = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 482)

    private func detail(state: PullRequestState) -> PullRequest {
        PullRequest(
            id: mine,
            title: "feat: mark own draft as ready for review",
            author: "ondrajodas",
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            baseSha: "7b3f740e",
            headRef: "issue-482-ready-for-review",
            baseRef: "main",
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/482")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: false
        )
    }

    // MARK: - Kdy se kreslí

    /// **Vyčerpávající výčet stavů PR**: draft nabízí, ostatní tři se nekreslí vůbec.
    ///
    /// Tvrzení je nad **`isVisible`**, ne nad `isAllowed`, a v tom je celý rozdíl proti mergnutí:
    /// nad otevřeným PR není co přepínat, takže tam nemá být ani zašedlé tlačítko s větou. Kdyby
    /// se stav přehlédl a vyšlo `blocked`, přibyl by v panelu řádek, který nikam nevede.
    @Test(
        "Kreslí se jedině nad draftem",
        arguments: [
            (PullRequestState.draft, true),
            (PullRequestState.open, false),
            (PullRequestState.closed, false),
            (PullRequestState.merged, false),
        ]
    )
    func drawsOnlyOverADraft(state: PullRequestState, visible: Bool) {
        let offer = Policy.readyForReviewOffer(editing: .allowed, state: state, action: nil)
        #expect(offer.isVisible == visible)
        #expect(offer.isAllowed == visible)
    }

    /// **Nenačtený detail je zákaz, ne povolení.** `nil` znamená „neví se, jestli je PR draft“,
    /// a tlačítko, které se objeví a zmizí, je horší než tlačítko o průchod později.
    @Test("Bez detailu se nekreslí")
    func staysHiddenWithoutDetail() {
        #expect(Policy.readyForReviewOffer(editing: .allowed, state: nil, action: nil) == .absent)
    }

    /// **Na cizím PR se nekreslí nic** — a nad draftem taky ne, ať je stav jakýkoli.
    ///
    /// V okně to hlídá i `Policy.branchSection`, které nad cizím PR vrátí `nil` a sekce se
    /// nekreslí celá; tvrzení je tady **podruhé** schválně, protože nabídka je to místo, které
    /// o akci rozhoduje, a spoléhat na to, že ji nikdo nezavolá, není kontrola.
    @Test("Na cizím PR se nekreslí")
    func staysHiddenOnAForeignPullRequest() {
        #expect(Policy.readyForReviewOffer(editing: .absent, state: .draft, action: nil) == .absent)
    }

    // MARK: - Zašedlá s důvodem

    /// **Vypnutá brána = zašedlé s důvodem**, ne schované: je to stav, který se **mění** (v
    /// nastavení), takže tam tlačítko patří i tehdy, když se do něj nedá kliknout.
    ///
    /// Věta je **tatáž**, na které skončí publisher, a je to ta samá, kterou nese
    /// `MergeObstacle.notAllowed` — proto se do výstrahy nepřidává podruhé
    /// (`Policy.readyWarnings`).
    @Test("S vypnutou branou je zašedlé a důvod je znát")
    func blocksWithTheGateOff() {
        let reason = "Odesílání na GitHub není pro ondrajodas/PRism povolené."
        let offer = Policy.readyForReviewOffer(
            editing: .blocked(reason),
            state: .draft,
            action: nil
        )

        #expect(offer.isVisible)
        #expect(!offer.isAllowed)
        #expect(offer.obstacles == [.notAllowed(reason)])
        #expect(offer.obstacles.map(\.sentence) == [reason])
    }

    /// **Běžící odeslání druhé nepustí** — a je to překážka z nabídky, ne jen zakázané tlačítko
    /// ve view: `AppStore` druhé volání odmítne, takže by kliknutí neudělalo nic.
    ///
    /// Vyjmenované jsou **všechny činné případy**, protože jde o labely, reviewery, zakládání
    /// labelu **i tuhle akci samotnou** (ochrana proti dvojkliku).
    @Test(
        "Během jiného odeslání se nenabízí",
        arguments: [
            MetadataActionState.settingLabels,
            .requestingReviewer,
            .creatingLabel,
            .markingReady,
        ]
    )
    func blocksWhileSomethingElseIsInFlight(action: MetadataActionState) {
        let offer = Policy.readyForReviewOffer(editing: .allowed, state: .draft, action: action)

        #expect(offer.isVisible)
        #expect(!offer.isAllowed)
        #expect(offer.obstacles == [.running])
    }

    /// **Chyba z minula akci neblokuje.** Je to stav k přečtení, ne rozdělaná práce — po
    /// neúspěchu se to má dát zkusit znovu, jinak by jediné selhání tlačítko zamklo do restartu.
    @Test(
        "Chyba z minula nabídku nezavírá",
        arguments: [
            MetadataActionState.failed(.timedOut),
            .readyFailed(.timedOut),
            .createdNotAdded(name: "bug", error: .timedOut),
        ]
    )
    func staysOfferedAfterAFailure(action: MetadataActionState) {
        #expect(
            Policy.readyForReviewOffer(editing: .allowed, state: .draft, action: action) == .allowed
        )
    }

    // MARK: - Co jde do výstrahy

    /// **Výčet vět do výstrahy je prázdný, a je to odpověď.** `notAllowed` je v panelu napsaná už
    /// jednou (výstrahou mergnutí), `running` se odklidí sama.
    @Test("Do výstrahy nejde nic")
    func addsNothingToTheWarning() {
        let blocked = Policy.ReadyOffer.blocked([.notAllowed("Odesílání není povolené."), .running])
        #expect(Policy.readyWarnings(blocked).isEmpty)
        #expect(Policy.readyWarnings(.allowed).isEmpty)
        #expect(Policy.readyWarnings(.absent).isEmpty)
    }

    // MARK: - Sekce Větev jako celek

    /// Sekce `Větev` **nese nabídku přepnutí** a nad draftem ji nabídne.
    ///
    /// Tvrdí se tady i to, co s tím souvisí: nad draftem je `Mergnout…` zakázané a mezi jeho
    /// důvody stojí `draftPullRequest` — tedy zrovna ta překážka, kterou tlačítko odklízí.
    @Test("Nad vlastním draftem sekce akci nabídne")
    func offersInsideTheBranchSection() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(state: .draft),
                commits: [],
                status: .loaded(
                    BranchStatus(mergeability: .mergeable, mergeState: .draft),
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                checks: [],
                blockingFindings: 0
            )
        )

        #expect(section.ready == .allowed)
        #expect(!section.merge.isAllowed)
        #expect(section.merge.obstacles.contains(.draftPullRequest))
    }

    /// Nad **otevřeným** PR sekce je, ale přepnutí v ní není.
    @Test("Nad otevřeným PR sekce akci nenese")
    func hidesInsideTheBranchSection() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(state: .open),
                commits: [],
                status: .loaded(
                    BranchStatus(mergeability: .mergeable, mergeState: .clean),
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                checks: [],
                blockingFindings: 0
            )
        )

        #expect(section.ready == .absent)
    }

    /// **Běžící odeslání se do sekce dostane** — bez toho by tlačítko svítilo nad akcí, kterou
    /// store odmítne.
    @Test("Sekce zná běžící odeslání")
    func carriesTheInFlightStateIntoTheSection() throws {
        let section = try #require(
            Policy.branchSection(
                editing: .allowed,
                detail: detail(state: .draft),
                commits: [],
                status: nil,
                checks: nil,
                blockingFindings: 0,
                action: .settingLabels
            )
        )

        #expect(section.ready == .blocked([.running]))
    }

    // MARK: - Věta o překážce a věta pod tlačítkem

    /// **Věta o rozpracovanosti ztratila druhou půlku** (#482): návod „Označ ho na GitHubu jako
    /// připravený.“ by od tlačítka o řádek níž odváděl.
    ///
    /// Tvrdí se to **doslovným textem**, ne jen absencí slova — na tomhle textu stojí zdůvodnění
    /// celého issue, takže se nemá dát změnit zpátky bez povšimnutí.
    @Test("Věta o rozpracovanosti neposílá na GitHub")
    func shortensTheDraftSentence() {
        let sentence = Policy.MergeObstacle.draftPullRequest.sentence
        #expect(sentence == "Pull request je rozpracovaný.")
        #expect(!sentence.contains("GitHub"))
    }

    /// **Věta pod tlačítkem mluví o `CODEOWNERS` a o cestě zpátky** — je to část rozhodnutí
    /// nepotvrzovat sheetem, takže se testuje jako text, ne jako přítomnost popisku.
    @Test("Věta pod tlačítkem řekne, co je nevratné")
    func warnsAboutCodeOwners() {
        #expect(Policy.readyForReviewNote.contains("CODEOWNERS"))
        #expect(Policy.readyForReviewNote.contains("Zpátky do draftu se chodí na GitHub."))
    }

    // MARK: - Tlačítko bez výchozí akce

    /// **Sekce `Větev` nemá klávesovou zkratku, a je to podmínka, ne detail.**
    ///
    /// Akce odesílá bez potvrzení a vyžádá review od vlastníků kódu, takže se nesmí dát spustit
    /// průchodem klávesnicí — tatáž mez jako u potvrzení merge (#465) a u založení labelu (#413).
    /// Že `Enter` doopravdy nezabere, se v harnessu ověřit nedá (fokus ani klávesy testovací host
    /// nedostane, viz `docs/testovani.md`), takže se tvrdí to, co ověřit **jde**: v tom souboru
    /// není `keyboardShortcut` ani `.defaultAction`.
    ///
    /// Čte se **zdroják, ne chování**, jako u `SingleWayOutTests`. Komentáře se zahazují, protože
    /// obě jména v nich stojí — právě tam se to rozhodnutí vysvětluje.
    ///
    /// **Druhá půlka tvrzení je pozitivní schválně**: bez ní by prošel i test, který soubor
    /// přečte špatně (jiná cesta, prázdný obsah) — a „nenašlo se to, protože se nehledalo“ je
    /// zrovna ta stráž, která nechytá nic.
    @Test("Tlačítko nemá výchozí akci")
    func hasNoDefaultAction() throws {
        let file = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Views/PanelBranchView.swift")
        let code = TextLines.content(try String(contentsOf: file, encoding: .utf8))
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        #expect(code.contains("readyButton"), "sonda nečte ten soubor, který má")
        #expect(!code.contains("keyboardShortcut"), "sekce Větev si bere klávesu")
        #expect(!code.contains("defaultAction"), "tlačítko v sekci Větev je výchozí akce")
    }
}
