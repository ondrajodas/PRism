import Foundation
import Testing

@testable import PRism

/// Co se s labely a reviewery **smí** (#392) — a hlavně to, co se nesmí.
///
/// Tři z pěti testů v téhle suitě tvrdí, že se něco **NEstalo**: na cizím PR nejsou akce, bez
/// povolené brány se nesmí nic odeslat, a z výběru nejde vyrobit label, který repo nezná.
@Suite("Labely a reviewery — co se smí")
struct PanelMetadataEditingTests {
    private static let repo = RepoID(owner: "cli", name: "cli")

    /// **Na cizím PR akce nejsou** — `.absent`, tedy se nekreslí vůbec. Ne zašedlé: zašedlé tlačítko
    /// tvrdí „tady se to dělá, jen teď ne“, a přeštítkovat cizí PR se odsud nedělá nikdy.
    @Test("Na cizím PR se akce nekreslí vůbec")
    func foreignPullRequestHasNoActions() {
        let editing = Policy.metadataEditing(
            ownership: .theirs,
            repo: Self.repo,
            scope: .allowing(Self.repo),
            hasTool: true
        )

        #expect(editing == .absent)
        #expect(!editing.isVisible)
        #expect(!editing.isAllowed)
        #expect(editing.reason == nil, "na cizím PR není co vysvětlovat — akce tam prostě není")
    }

    /// **Bez povolené brány se nic neodešle.** Na vlastním PR se ale akce **kreslí zakázaná
    /// s důvodem**: „tady se to dělá, jen teď ne“ je u vypnutého přepínače pravda, a chybějící
    /// tlačítko by vypadalo jako rozbitá aplikace.
    @Test("Bez povoleného odesílání je akce zakázaná, ne schovaná")
    func withoutTheGateTheActionIsBlocked() {
        let editing = Policy.metadataEditing(
            ownership: .mine,
            repo: Self.repo,
            scope: .standard,
            hasTool: true
        )

        #expect(!editing.isAllowed)
        #expect(editing.isVisible)
        // Tatáž věta, na které skončí publisher — okno se neptá dvakrát jinak.
        #expect(editing.reason == PublishError.publishingNotAllowed(Self.repo).userDescription)
    }

    /// Brána je **tatáž** jako u review a komentářů (`allowsPublishing`), takže povolené repo akci
    /// odemkne. Žádný druhý přepínač — ten by byl druhé místo, kde se dá „samo nic neodejde“ porušit.
    @Test("S povolenou branou se na vlastním PR měnit smí")
    func ownPullRequestWithTheGateIsAllowed() {
        let editing = Policy.metadataEditing(
            ownership: .mine,
            repo: Self.repo,
            scope: .allowing(Self.repo),
            hasTool: true
        )

        #expect(editing == .allowed)
    }

    /// Chybějící `gh` je porucha prostředí, ne nastavení — proto vlastní věta a proto se **hlásí
    /// dřív** než brána: bez nástroje nemá čím odejít nic.
    @Test("Bez gh se akce zakáže s jinou větou než brána")
    func withoutGhTheReasonIsDifferent() {
        let editing = Policy.metadataEditing(
            ownership: .mine,
            repo: Self.repo,
            scope: .allowing(Self.repo),
            hasTool: false
        )

        #expect(!editing.isAllowed)
        #expect(editing.reason != PublishError.publishingNotAllowed(Self.repo).userDescription)
        #expect(editing.reason?.contains("gh") == true)
    }

    /// Brána se ptá **per repo**, ne globálně na všechno: povolení jednoho repa neodemkne druhé.
    @Test("Povolení jednoho repa neodemkne jiné")
    func theGateIsPerRepository() {
        let other = RepoID(owner: "keboola", name: "connection")
        let scope = PublishScope.allowing(Self.repo)

        #expect(Policy.metadataEditing(ownership: .mine, repo: Self.repo, scope: scope, hasTool: true).isAllowed)
        #expect(!Policy.metadataEditing(ownership: .mine, repo: other, scope: scope, hasTool: true).isAllowed)
    }

    // MARK: - Uzavřená množina labelů

    /// **Z výběru nejde vyrobit label, který repo nezná.** `nil` znamená „neodesílat nic“, takže se
    /// neznámé jméno nemá jak dostat do sady — a nový label se z okna omylem nevyrobí.
    @Test("Label, který repo nezná, se neodešle")
    func unknownLabelIsNotSendable() {
        let known = [PullRequestLabel(name: "bug"), PullRequestLabel(name: "go")]

        #expect(Policy.toggledLabels(PullRequestLabel(name: "vymyšlený"), on: [], known: known) == nil)
    }

    /// Prázdná nabídka je **bezpečná**: dokud repo labely nedorazí, nedá se přidat nic.
    @Test("Nad prázdnou nabídkou se neodešle nic")
    func nothingIsSendableWithoutTheRepositoryList() {
        #expect(Policy.toggledLabels(PullRequestLabel(name: "bug"), on: [], known: []) == nil)
    }

    @Test("Známý label se přidá na konec sady")
    func knownLabelIsAdded() {
        let known = [PullRequestLabel(name: "bug"), PullRequestLabel(name: "go")]

        #expect(Policy.toggledLabels(
            PullRequestLabel(name: "go"),
            on: [PullRequestLabel(name: "bug")],
            known: known
        ) == ["bug", "go"])
    }

    /// Klik je **přepínač**, takže se stejným tlačítkem label sundá — a je to jediný důvod, proč
    /// nedostal potvrzovací sheet.
    @Test("Druhý klik label sundá")
    func secondClickRemovesTheLabel() {
        let known = [PullRequestLabel(name: "bug"), PullRequestLabel(name: "go")]

        #expect(Policy.toggledLabels(
            PullRequestLabel(name: "bug"),
            on: [PullRequestLabel(name: "bug"), PullRequestLabel(name: "go")],
            known: known
        ) == ["go"])
    }

    /// Sundání **posledního** labelu je prázdná sada, ne `nil`: `nil` znamená „nic neposílat“, kdežto
    /// tady se posílá `{"labels": []}`. Splynutí by znamenalo, že se poslední štítek sundat nedá.
    @Test("Sundání posledního labelu dá prázdnou sadu, ne nic")
    func removingTheLastLabelSendsAnEmptySet() {
        let known = [PullRequestLabel(name: "bug")]

        #expect(Policy.toggledLabels(
            PullRequestLabel(name: "bug"),
            on: [PullRequestLabel(name: "bug")],
            known: known
        ) == [])
    }

    /// Sada se posílá **celá**, takže v ní musí zůstat i to, co repo mezitím přestalo znát —
    /// smazaný label na PR je pořád na PR a přidání jiného ho nemá sundat.
    @Test("Přidání labelu nesmaže ten, který repo nezná")
    func keepsLabelsTheRepositoryNoLongerLists() {
        let known = [PullRequestLabel(name: "bug"), PullRequestLabel(name: "go")]

        #expect(Policy.toggledLabels(
            PullRequestLabel(name: "go"),
            on: [PullRequestLabel(name: "smazaný-v-repu")],
            known: known
        ) == ["smazaný-v-repu", "go"])
    }

    // MARK: - Nabídka reviewerů

    /// Kdo už **čeká**, v nabídce není: bylo by to tlačítko, po kterém se nic nestane.
    @Test("Kdo už čeká, v nabídce není")
    func waitingReviewersAreNotOffered() {
        let candidates = Policy.reviewerCandidates(
            assignable: ["adam", "bara", "cyril"],
            reviewers: [RequestedReviewer(login: "bara", answer: .waiting)]
        )

        #expect(candidates == [.person("adam"), .person("cyril")])
    }

    /// Kdo **odpověděl**, v nabídce zůstává — vyžádat review po opravě je zrovna to, kvůli čemu se
    /// na nabídku kliká.
    @Test(
        "Kdo odpověděl, v nabídce zůstává",
        arguments: [ReviewerAnswer.approved, .changesRequested]
    )
    func answeredReviewersStayOffered(answer: ReviewerAnswer) {
        let candidates = Policy.reviewerCandidates(
            assignable: ["adam", "bara"],
            reviewers: [RequestedReviewer(login: "bara", answer: answer)]
        )

        #expect(candidates == [.person("adam"), .person("bara")])
    }

    @Test("Prázdný seznam assignable dá prázdnou nabídku")
    func emptyAssignableGivesNothing() {
        #expect(Policy.reviewerCandidates(assignable: [], reviewers: []).isEmpty)
    }

    // MARK: - Týmy (#392)

    /// **Týmy jsou druhá polovina nabídky, a jsou za lidmi.** Odpověď je to, kvůli čemu se na sekci
    /// kouká, a tu nese jedině člověk; tým říká jen „leží to na skupině“.
    @Test("Nabídka nese lidi i týmy, lidi první")
    func candidatesCarryPeopleThenTeams() {
        let candidates = Policy.reviewerCandidates(
            assignable: ["cyril", "adam"],
            teams: ["platform", "ajda-swimlane"],
            reviewers: []
        )

        #expect(candidates == [
            .person("adam"), .person("cyril"), .team("ajda-swimlane"), .team("platform"),
        ])
    }

    /// **Už vyžádaný tým se nenabízí** — bylo by to tlačítko, po kterém se nic nestane. U člověka
    /// se to řídí odpovědí `čeká`, u týmu prostě tím, že už je vyžádaný: tým odpověď nemá.
    @Test("Vyžádaný tým v nabídce není, i když člověk s odpovědí ano")
    func alreadyRequestedTeamsAreDropped() {
        let candidates = Policy.reviewerCandidates(
            assignable: ["adam"],
            teams: ["platform", "ajda-swimlane"],
            reviewers: [RequestedReviewer(login: "adam", answer: .approved)],
            requestedTeams: ["ajda-swimlane"]
        )

        #expect(candidates == [.person("adam"), .team("platform")])
    }

    /// **Slug se zbavuje předpony organizace.** `gh pr view` dává `keboola/ajda-swimlane`, REST
    /// a `orgs/{org}/teams` `ajda-swimlane` — a tu druhou podobu chce zápis. Kdyby se obě potkaly
    /// v panelu, vypadal by týž tým jako dva.
    @Test("Předpona organizace ve slugu padá a duplikáty se slijí")
    func stripsTheOrganisationPrefix() {
        #expect(Policy.requestedTeams(["keboola/ajda-swimlane", "ajda-swimlane"]) == ["ajda-swimlane"])
    }

    @Test("Prázdný slug se zahodí")
    func dropsEmptySlugs() {
        #expect(Policy.requestedTeams(["", "keboola/"]).isEmpty)
    }

    /// Pořadí je abecední, ne to, co přišlo z API — přeskládaný seznam se nedá přečíst dvakrát
    /// stejně.
    @Test("Týmy se řadí abecedně")
    func sortsTeams() {
        #expect(Policy.requestedTeams(["platform", "ai", "keboola/ajda"]) == ["ai", "ajda", "platform"])
    }
}
