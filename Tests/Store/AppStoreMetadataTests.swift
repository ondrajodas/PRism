import Foundation
import Testing

@testable import PRism

/// Labely a vyžádaní reviewery, jak je skládá store (#392).
///
/// **Nic neodchází na GitHub**: `gh` je podstrčený shell skript v dočasné složce, který vypíše
/// připravenou odpověď a zapíše, kolikrát byl spuštěn. Fake publisher by se sem podstrčit nedal —
/// `AppStore` si ho podle tvrdé podmínky č. 1 nesmí držet ani jako továrnu, takže se testuje celá
/// cesta včetně čtení výstupu. Počítadlo spuštění je jediný způsob, jak ověřit, že se **nevolalo
/// nic**. Tatáž scéna jako u komentářů pod PR (#216).
@Suite("AppStore — labely a reviewery")
@MainActor
struct AppStoreMetadataTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#4")!
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "gh-calls.log")
    }

    // MARK: - Prostředí testu

    /// Konfigurace, ve které je odesílání pro tohle repo **povolené** a autor PR se počítá za mě.
    private func configuration(publishing: Bool, mine: Bool) -> Configuration {
        var configuration = Configuration.standard
        if publishing {
            configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        }
        configuration.global.ownLogins = mine ? ["autor"] : []
        return configuration
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private static let metadata = PullRequestMetadata(
        labels: [PullRequestLabel(name: "bug", color: "d73a4a")],
        reviewers: [RequestedReviewer(login: "babakks", answer: .approved)]
    )

    private static let known = [
        PullRequestLabel(name: "bug", color: "d73a4a"),
        PullRequestLabel(name: "go", color: "16e2e2"),
    ]

    /// Odpověď `PUT /issues/{n}/labels` — celá nová sada.
    private let labelsOutput = """
    [{"id":1,"name":"bug","color":"d73a4a"},{"id":2,"name":"go","color":"16e2e2"}]
    """

    private let reviewersOutput = """
    {"number":4,"requested_reviewers":[{"login":"odinuv"}],"requested_teams":[]}
    """

    /// Odpověď u týmové žádosti — tvar změřený na `keboola/platform-architecture-and-concepts#278`.
    private let teamOutput = """
    {"number":4,"requested_reviewers":[],
     "requested_teams":[{"name":"ajda-swimlane","slug":"ajda-swimlane"}]}
    """

    /// Skript, který se tváří jako `gh`. Stejný jako u komentářů (#216) — `delay` je kvůli testu
    /// dvojkliku, bez něj by první volání doběhlo dřív, než druhé začne.
    private func fakeGh(_ output: String, exitCode: Int32 = 0, delay: Double = 0) throws -> URL {
        let script = directory.url.appending(path: "gh-\(UUID().uuidString).sh")
        let redirect = exitCode == 0 ? "" : ">&2"
        let text = """
        #!/bin/sh
        echo "call" >> "\(calls.path(percentEncoded: false))"
        \(delay > 0 ? "sleep \(delay)" : "")
        cat \(redirect) <<'PRISMJSON'
        \(output)
        PRISMJSON
        exit \(exitCode)
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Skript, který odpovídá **podle pořadí volání** (#413).
    ///
    /// Zakládání labelu jsou **dvě** volání za sebou a jejich odpovědi se liší — a hlavně se liší
    /// v tom, které z nich spadne. Jeden výstup pro obojí by mezistav „label v repu je, na PR není“
    /// nedokázal vyrobit vůbec, a to je zrovna ten stav, kvůli kterému pro tuhle akci neplatí tvrdá
    /// podmínka č. 5.
    private func fakeGhSequence(
        _ steps: [(output: String, exitCode: Int32)],
        delayFirst: Double = 0
    ) throws -> URL {
        let script = directory.url.appending(path: "gh-\(UUID().uuidString).sh")
        let path = calls.path(percentEncoded: false)
        // `wc -l < soubor`, ne `grep -c … | …`: bez roury nemá co dát SIGPIPE producentovi.
        let branches = steps.enumerated().map { index, step in
            let redirect = step.exitCode == 0 ? "" : ">&2"
            // Zdržení je **jen u prvního** volání, a to je celé, co test dvojkliku potřebuje: druhé
            // volání se stejně čeká celé, takže druhý spánek by běh jen prodloužil.
            let delay = index == 0 && delayFirst > 0 ? "sleep \(delayFirst)" : ""
            return """
            if [ "$n" -eq \(index + 1) ]; then
            \(delay)
            cat \(redirect) <<'PRISMSTEP'
            \(step.output)
            PRISMSTEP
            exit \(step.exitCode)
            fi
            """
        }
        let text = """
        #!/bin/sh
        echo "call" >> "\(path)"
        n=$(wc -l < "\(path)" | tr -d ' ')
        \(branches.joined(separator: "\n"))
        echo "volání \\$n nikdo nečekal" >&2
        exit 99
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Kolikrát se `gh` doopravdy spustilo. Nula znamená „neodeslalo se nic“.
    private func ghCalls() throws -> Int {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func prepared(
        gh: URL? = nil,
        publishing: Bool = true,
        mine: Bool = true,
        metadata: PullRequestMetadata? = nil,
        metadataFailure: (any Error)? = nil,
        known: [PullRequestLabel]? = nil,
        assignable: [String] = ["odinuv", "sergiou87"],
        teams: [String] = []
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail())
        )
        gateway.metadata = metadata ?? Self.metadata
        gateway.metadataFailure = metadataFailure
        gateway.repositoryLabels = known ?? Self.known
        gateway.assignableUsers = assignable
        gateway.assignableTeams = teams
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(publishing: publishing, mine: mine),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            gh: gh
        )
        await store.loadDetail(for: summary())
        return (store, gateway)
    }

    // MARK: - Čtení

    @Test("Snímek se dotáhne s detailem")
    func loadsWithTheDetail() async throws {
        let (store, gateway) = await prepared()

        #expect(store.metadata(for: pr) == Self.metadata)
        #expect(gateway.metadataRequests == [pr])
    }

    /// Načtený snímek se **drží**: druhý příchod na PR se ptát nemá, jinak by z labelů byl polling.
    @Test("Druhý příchod na PR se na labely neptá")
    func doesNotRefetchOnTheSecondVisit() async throws {
        let (store, gateway) = await prepared()

        await store.loadDetail(for: summary())

        #expect(gateway.metadataRequests == [pr])
    }

    /// **„PR nemá labely“ a „labely jsem nezjistil“ se nesmí slít.** Po chybě sítě je stav `failed`,
    /// ne prázdný snímek — jinak by výpadek vypadal jako pull request bez štítků a dalo by se
    /// kliknutím přepsat sada, kterou aplikace nezná.
    @Test("Selhání se nezahodí do prázdného snímku")
    func failureIsNotSilentlyEmpty() async throws {
        let (store, _) = await prepared(metadataFailure: GitHubError.network("spadlo to"))

        #expect(store.metadata(for: pr) == nil)
        #expect(store.metadataState(for: pr)?.failure != nil)
    }

    /// Prázdný snímek je naopak **platná odpověď** — a musí se od selhání poznat.
    @Test("Prázdný snímek je odpověď, ne porucha")
    func emptyMetadataIsAnAnswer() async throws {
        let (store, _) = await prepared(metadata: PullRequestMetadata())

        #expect(store.metadata(for: pr) == PullRequestMetadata())
        #expect(store.metadataState(for: pr)?.failure == nil)
    }

    /// Nabídky se tahají **na otevření a jen jednou**: sada labelů se v repu mezi dvěma kliknutími
    /// nemění, takže druhé volání by bylo za nic.
    @Test("Nabídky se dotáhnou jednou, ne při každém otevření")
    func loadsThePickersOnce() async throws {
        let (store, gateway) = await prepared()

        await store.loadRepositoryLabels(for: pr.repo)
        await store.loadRepositoryLabels(for: pr.repo)
        await store.loadAssignableUsers(for: pr.repo)
        await store.loadAssignableUsers(for: pr.repo)

        #expect(gateway.repositoryLabelRequests == [pr.repo])
        #expect(gateway.assignableUserRequests == [pr.repo])
        #expect(store.knownLabels(in: pr.repo).map(\.name) == ["bug", "go"])
    }

    /// **Nabídka se nedotahuje s detailem.** Je to volání `gh` navíc a otvírá se zřídka, takže by se
    /// platilo při každém výběru řádku.
    @Test("Nabídky se s detailem netahají")
    func doesNotLoadThePickersWithTheDetail() async throws {
        let (store, gateway) = await prepared()

        #expect(gateway.repositoryLabelRequests.isEmpty)
        #expect(gateway.assignableUserRequests.isEmpty)
        #expect(store.knownLabels(in: pr.repo).isEmpty)
    }

    /// **Prázdná nabídka a nenačtená nabídka nejsou totéž**, a po selhání je z toho třetí stav.
    /// Kdyby se slily, tvrdila by nabídka o repu něco, co se ještě nezjistilo — nebo po výpadku sítě
    /// to, že repo žádné labely nezná.
    @Test("Prázdná, nenačtená a selhaná nabídka jsou tři různé stavy")
    func thePickerHasThreeStates() async throws {
        let (store, _) = await prepared(known: [])

        #expect(!store.hasLoadedLabels(in: pr.repo))
        #expect(store.labelPickerFailure(in: pr.repo) == nil)

        await store.loadRepositoryLabels(for: pr.repo)
        #expect(store.hasLoadedLabels(in: pr.repo))
        #expect(store.knownLabels(in: pr.repo).isEmpty)
        #expect(store.labelPickerFailure(in: pr.repo) == nil)
    }

    /// **Selhání nabídky se neschovává do prázdna.** Nabídka, která po chybě sítě vypadá jako repo
    /// bez labelů, posílá člověka hledat labely, které tam jsou.
    @Test("Selhaná nabídka se pozná od repa bez labelů")
    func aFailedPickerIsNotAnEmptyRepository() async throws {
        let gateway = FakeGitHubGateway(always: .success([summary()]), detail: .success(detail()))
        gateway.metadata = Self.metadata
        gateway.repositoryLabelsFailure = GitHubError.network("spadlo to")
        gateway.assignableUsersFailure = GitHubError.network("spadlo to")
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(publishing: true, mine: true),
            time: FakeTimeSource()
        )

        await store.loadRepositoryLabels(for: pr.repo)
        await store.loadAssignableUsers(for: pr.repo)

        #expect(!store.hasLoadedLabels(in: pr.repo), "nenačtené se nesmí zapsat jako prázdné")
        #expect(store.labelPickerFailure(in: pr.repo) != nil)
        #expect(store.reviewerPickerFailure(in: pr.repo) != nil)
    }

    @Test("Nabídka reviewerů vynechá ty, kteří už čekají")
    func candidatesSkipWaitingReviewers() async throws {
        let (store, _) = await prepared(
            metadata: PullRequestMetadata(
                reviewers: [RequestedReviewer(login: "odinuv", answer: .waiting)]
            )
        )

        await store.loadAssignableUsers(for: pr.repo)

        #expect(store.reviewerCandidates(for: pr) == [.person("sergiou87")])
    }

    // MARK: - Nic se neodeslalo

    /// **Na cizím PR akce nejsou** — a i kdyby na ně někdo dosáhl, neodešlo by nic.
    @Test("Na cizím PR se label nezmění a nic se nevolá")
    func doesNothingOnSomebodyElsesPullRequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(labelsOutput), mine: false)
        await store.loadRepositoryLabels(for: pr.repo)

        #expect(store.metadataEditing(for: pr) == .absent)
        await store.toggleLabel(Self.known[1], on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadata(for: pr) == Self.metadata, "snímek se nezměnil")
        #expect(store.metadataActionState(for: pr) == nil)
    }

    @Test("Na cizím PR se reviewer nevyžádá a nic se nevolá")
    func doesNotRequestReviewersOnSomebodyElsesPullRequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(reviewersOutput), mine: false)
        await store.loadAssignableUsers(for: pr.repo)

        await store.requestReview(from: .person("odinuv"), on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadata(for: pr) == Self.metadata)
    }

    /// **Bez povolené brány se neodešle nic** — ani labely, ani reviewer. Akce se přitom pořád
    /// kreslí, jen zakázaná s důvodem.
    @Test("Bez povoleného odesílání se nic nevolá")
    func doesNothingWithoutTheGate() async throws {
        let (store, _) = await prepared(gh: try fakeGh(labelsOutput), publishing: false)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.loadAssignableUsers(for: pr.repo)
        await store.toggleLabel(Self.known[1], on: summary())
        await store.requestReview(from: .person("odinuv"), on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadata(for: pr) == Self.metadata)
        #expect(store.metadataEditing(for: pr).reason != nil, "má být vidět, proč to nejde")
    }

    /// **Z výběru nejde vyrobit label, který repo nezná** — a kontrola je i tady, ne jen v nabídce:
    /// jediná kontrola ve view je kontrola, kterou příští obrazovka obejde.
    @Test("Label, který repo nezná, se z okna neodešle")
    func doesNotSendAnUnknownLabel() async throws {
        let (store, _) = await prepared(gh: try fakeGh(labelsOutput))
        await store.loadRepositoryLabels(for: pr.repo)

        await store.toggleLabel(PullRequestLabel(name: "vymyšlený", color: "ffffff"), on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadata(for: pr) == Self.metadata)
    }

    /// Bez načtené nabídky se **taky neodešle nic**: sada by se skládala proti prázdné množině
    /// známých labelů.
    @Test("Bez načtené nabídky se label nezmění")
    func doesNotSendWithoutTheRepositoryList() async throws {
        let (store, _) = await prepared(gh: try fakeGh(labelsOutput))

        await store.toggleLabel(Self.known[1], on: summary())

        #expect(try ghCalls() == 0)
    }

    /// Bez načteného snímku se sada nemá odkud skládat — a přepsat neznámou sadu by znamenalo
    /// smazat štítky, o kterých aplikace neví.
    @Test("Nad nenačteným snímkem se label nezmění")
    func doesNotSendWithoutASnapshot() async throws {
        let (store, _) = await prepared(
            gh: try fakeGh(labelsOutput),
            metadataFailure: GitHubError.network("spadlo to")
        )
        await store.loadRepositoryLabels(for: pr.repo)

        await store.toggleLabel(Self.known[1], on: summary())

        #expect(try ghCalls() == 0)
    }

    /// Bez `gh` se nemá čím odeslat nic — a je to porucha prostředí, ne nastavení.
    @Test("Bez gh se nic nevolá")
    func doesNothingWithoutGh() async throws {
        let (store, _) = await prepared(gh: nil)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.toggleLabel(Self.known[1], on: summary())

        #expect(try ghCalls() == 0)
        #expect(!store.metadataEditing(for: pr).isAllowed)
    }

    /// **Vyžádat jde jen z nabídky.** Uzavřená množina je to jediné, co drží slib, že se nevyžádá
    /// review od někoho, komu to GitHub odmítne — a kontrola jen ve view je kontrola, kterou příští
    /// obrazovka obejde.
    @Test("Reviewer mimo nabídku se nevyžádá")
    func doesNotRequestSomebodyOutsideTheList() async throws {
        let (store, _) = await prepared(gh: try fakeGh(reviewersOutput))
        await store.loadAssignableUsers(for: pr.repo)

        await store.requestReview(from: .person("kdokoli"), on: summary())

        #expect(try ghCalls() == 0)
    }

    /// A bez načtené nabídky se **taky nevyžádá nic**: množina, ze které se vybírá, ještě neexistuje.
    @Test("Bez načtené nabídky se reviewer nevyžádá")
    func doesNotRequestWithoutTheList() async throws {
        let (store, _) = await prepared(gh: try fakeGh(reviewersOutput))

        await store.requestReview(from: .person("odinuv"), on: summary())

        #expect(try ghCalls() == 0)
    }

    /// **Tým je druhá polovina nabídky** (#392) — a je za lidmi, protože odpověď nese jedině člověk.
    @Test("Nabídka nese lidi i týmy")
    func candidatesCarryPeopleAndTeams() async throws {
        let (store, gateway) = await prepared(teams: ["ajda-swimlane"])

        await store.loadAssignableUsers(for: pr.repo)

        #expect(store.reviewerCandidates(for: pr)
            == [.person("odinuv"), .person("sergiou87"), .team("ajda-swimlane")])
        #expect(gateway.assignableTeamRequests == [pr.repo])
    }

    /// **Vyžádaný tým se v nabídce neopakuje** — bylo by to tlačítko, po kterém se nic nestane.
    @Test("Už vyžádaný tým v nabídce není")
    func alreadyRequestedTeamsAreNotOffered() async throws {
        let (store, _) = await prepared(
            metadata: PullRequestMetadata(teams: ["ajda-swimlane"]),
            teams: ["ajda-swimlane", "platform"]
        )

        await store.loadAssignableUsers(for: pr.repo)

        #expect(!store.reviewerCandidates(for: pr).contains(.team("ajda-swimlane")))
        #expect(store.reviewerCandidates(for: pr).contains(.team("platform")))
    }

    /// **Spadlé týmy nesmí nechat nabídku „načtenou“ napůl.** Kdyby se lidé zapsali hned, další
    /// otevření by se už neptalo (stráž se dívá na lidi) a nabídka by hlásila poruchu **navždycky** —
    /// tedy „zkusit znovu“, které nic nezkusí. Ověřeno i druhým pokusem, který po opravě projde.
    @Test("Spadlé týmy nechají nabídku nenačtenou, takže se dá zkusit znovu")
    func aFailedTeamListLeavesThePickerRetryable() async throws {
        let (store, gateway) = await prepared(teams: ["ajda-swimlane"])
        gateway.assignableTeamsFailure = GitHubError.network("spadlo to")

        await store.loadAssignableUsers(for: pr.repo)

        #expect(!store.hasLoadedAssignableUsers(in: pr.repo), "napůl načteno je horší než nenačteno")
        #expect(store.reviewerPickerFailure(in: pr.repo) != nil)

        // Druhý pokus se **doopravdy ptá** a po úspěchu je nabídka celá.
        gateway.assignableTeamsFailure = nil
        await store.loadAssignableUsers(for: pr.repo)

        #expect(gateway.assignableUserRequests.count == 2)
        #expect(store.hasLoadedAssignableUsers(in: pr.repo))
        #expect(store.reviewerPickerFailure(in: pr.repo) == nil)
        #expect(store.reviewerCandidates(for: pr).contains(.team("ajda-swimlane")))
    }

    /// **Tým mimo nabídku se nevyžádá** — tatáž uzavřenost jako u lidí a labelů.
    @Test("Tým mimo nabídku se nevyžádá")
    func doesNotRequestATeamOutsideTheList() async throws {
        let (store, _) = await prepared(gh: try fakeGh(teamOutput), teams: ["ajda-swimlane"])
        await store.loadAssignableUsers(for: pr.repo)

        await store.requestReview(from: .team("kdokoli"), on: summary())

        #expect(try ghCalls() == 0)
    }

    /// Vyžádaný tým se zapíše do snímku **bez dalšího dotazu**, a odpovědi lidí u toho zůstanou.
    @Test("Vyžádaný tým je v panelu bez dalšího dotazu")
    func showsTheRequestedTeam() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(teamOutput), teams: ["ajda-swimlane"])
        await store.loadAssignableUsers(for: pr.repo)
        let loaded = gateway.metadataRequests.count

        await store.requestReview(from: .team("ajda-swimlane"), on: summary())

        #expect(try ghCalls() == 1)
        #expect(store.metadata(for: pr)?.teams == ["ajda-swimlane"])
        #expect(store.metadata(for: pr)?.reviewers == Self.metadata.reviewers, "schválení zůstalo")
        #expect(gateway.metadataRequests.count == loaded)
    }

    // MARK: - Co se stane po odeslání

    @Test("Přidaný label je v panelu bez dalšího dotazu")
    func showsTheLabelWithoutRefetching() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(labelsOutput))
        await store.loadRepositoryLabels(for: pr.repo)
        let loaded = gateway.metadataRequests.count

        await store.toggleLabel(Self.known[1], on: summary())

        #expect(try ghCalls() == 1, "jedno atomické volání")
        #expect(store.metadata(for: pr)?.labels.map(\.name) == ["bug", "go"])
        #expect(gateway.metadataRequests.count == loaded, "snímek se znovu netahá")
        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// **Odpovědi ostatních po vyžádání zůstanou.** GitHub je v odpovědi neposílá, takže bez slití
    /// by z panelu po jednom kliknutí zmizelo schválení, které tam bylo.
    @Test("Vyžádání reviewera nesmaže schválení, které v panelu bylo")
    func keepsAnswersAfterARequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(reviewersOutput))
        // Nabídka se musí načíst — vyžádat jde **jen z ní**.
        await store.loadAssignableUsers(for: pr.repo)

        await store.requestReview(from: .person("odinuv"), on: summary())

        #expect(store.metadata(for: pr)?.reviewers == [
            RequestedReviewer(login: "babakks", answer: .approved),
            RequestedReviewer(login: "odinuv", answer: .waiting),
        ])
    }

    /// Selhání se **drží** a je z něj vidět, co se nepovedlo — chyba, která zmizí sama, je chyba,
    /// kterou nikdo nepřečte. Snímek u toho zůstává, jak byl.
    @Test("Po selhání zůstane chyba i původní sada")
    func keepsTheFailureAndTheOldSet() async throws {
        let (store, _) = await prepared(gh: try fakeGh("gh: HTTP 422", exitCode: 1))
        await store.loadRepositoryLabels(for: pr.repo)

        await store.toggleLabel(Self.known[1], on: summary())

        #expect(store.metadataActionState(for: pr)?.failure != nil)
        #expect(store.metadata(for: pr) == Self.metadata)

        store.clearMetadataFailure(for: pr)
        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// Dvojklik: druhé odeslání by přepsalo sadu, kterou první ještě nedokončil.
    @Test("Druhý klik během odesílání se zahodí")
    func refusesASecondClickWhileSending() async throws {
        let (store, _) = await prepared(gh: try fakeGh(labelsOutput, delay: 0.4))
        await store.loadRepositoryLabels(for: pr.repo)

        let first = Task { await store.toggleLabel(Self.known[1], on: summary()) }
        await waitUntil("odesílání běží") { store.metadataActionState(for: self.pr)?.isBusy == true }
        await store.toggleLabel(Self.known[0], on: summary())
        await first.value

        #expect(try ghCalls() == 1, "druhý klik nic neodeslal")
    }

    // MARK: - Založení nového labelu (#413)

    /// Odpověď `POST /repos/{repo}/labels` — **jeden** label, ne pole.
    private let newLabelOutput = #"{"id":9,"name":"design-debt","color":"d4c5f9"}"#

    /// Odpověď druhého volání: sada, kterou po přidání potvrdil GitHub.
    private let addedLabelsOutput = """
    [{"id":1,"name":"bug","color":"d73a4a"},{"id":9,"name":"design-debt","color":"d4c5f9"}]
    """

    /// Label tak, jak ho nabídne `Policy` — **barva odsud, ne vypsaná v testu**, jinak by se ta dvě
    /// místa mohla rozejít a store by pak nabídku odmítl.
    private static let newLabel = PullRequestLabel(
        name: "design-debt",
        color: Policy.labelColor(for: "design-debt")
    )

    /// **Dvě volání, jedna akce.** Tvrdá podmínka č. 5 pro tuhle akci neplatí, takže se tady tvrdí
    /// právě to, co za ni platí: obě volání proběhnou, label je v nabídce **i** na PR a stav je
    /// zpátky na `nil`.
    @Test("Založení a přidání jsou dvě volání a obojí se povede")
    func createsAndAddsWithTwoCalls() async throws {
        let gh = try fakeGhSequence([(newLabelOutput, 0), (addedLabelsOutput, 0)])
        let (store, _) = await prepared(gh: gh)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 2, "dvě volání, ne jedno a ne tři")
        #expect(store.knownLabels(in: pr.repo).map(\.name) == ["bug", "go", "design-debt"])
        #expect(store.metadata(for: pr)?.labels.map(\.name) == ["bug", "design-debt"])
        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// **Selhání druhého volání nesmí vypadat jako selhání obojího.** Label v repozitáři **je**, na
    /// PR není — a přesně to je stav, který má vlastní případ a vlastní věta v panelu. Řádek v nabídce
    /// u toho musí být, jinak by věta „přidáš ho kliknutím“ tvrdila víc, než data unesou.
    @Test("Když se přidání nepovede, mezistav je vidět a dá se dorovnat")
    func showsTheIntermediateState() async throws {
        let gh = try fakeGhSequence([(newLabelOutput, 0), ("gh: HTTP 500", 1)])
        let (store, _) = await prepared(gh: gh)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 2)
        #expect(store.metadataActionState(for: pr)?.noticePlace == .metadata)
        guard case .createdNotAdded(let name, _) = store.metadataActionState(for: pr) else {
            Issue.record("čekal se mezistav, přišlo \(String(describing: store.metadataActionState(for: pr)))")
            return
        }
        #expect(name == "design-debt")
        #expect(store.metadataActionState(for: pr)?.failure == nil, "není to `failed` — půlka se stala")
        #expect(store.knownLabels(in: pr.repo).map(\.name).contains("design-debt"), "řádek v nabídce je")
        #expect(store.metadata(for: pr)?.labels == Self.metadata.labels, "na PR se nedostal")
    }

    /// Mezistav se **dorovná jedním kliknutím** na řádek v nabídce — a je to tatáž cesta jako
    /// u každého jiného labelu, žádná opravná zvláštnost.
    @Test("Nepřidaný label se dorovná kliknutím v nabídce")
    func theIntermediateStateIsFixedByOneClick() async throws {
        let gh = try fakeGhSequence([
            (newLabelOutput, 0),
            ("gh: HTTP 500", 1),
            (addedLabelsOutput, 0),
        ])
        let (store, _) = await prepared(gh: gh)
        await store.loadRepositoryLabels(for: pr.repo)
        await store.createLabel(Self.newLabel, on: summary())

        let row = try #require(store.knownLabels(in: pr.repo).first { $0.name == "design-debt" })
        await store.toggleLabel(row, on: summary())

        #expect(store.metadata(for: pr)?.labels.map(\.name) == ["bug", "design-debt"])
        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// **Když spadne první volání, mezistav nevzniká** — v repozitáři nic není, takže je to obyčejné
    /// `failed` a v nabídce po tom nesmí zůstat řádek, který neexistuje.
    @Test("Spadlé založení není mezistav a nabídku nešpiní")
    func aFailedCreateLeavesNothingBehind() async throws {
        let gh = try fakeGhSequence([("gh: HTTP 403", 1)])
        let (store, _) = await prepared(gh: gh)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 1, "druhé volání se nemá čeho chytit")
        #expect(store.metadataActionState(for: pr)?.failure != nil)
        #expect(!store.knownLabels(in: pr.repo).map(\.name).contains("design-debt"))
        #expect(store.metadata(for: pr)?.labels == Self.metadata.labels)
    }

    /// **Na cizím PR se nezakládá nikdy** — akce tam není a i kdyby na ni někdo dosáhl, neodejde nic.
    @Test("Na cizím PR se label nezaloží a nic se nevolá")
    func doesNotCreateOnSomebodyElsesPullRequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(newLabelOutput), mine: false)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// **Bez povolené brány se nezaloží nic.** Je to tatáž brána jako u všeho ostatního, ne druhý
    /// přepínač.
    @Test("Bez povoleného odesílání se label nezaloží")
    func doesNotCreateWithoutTheGate() async throws {
        let (store, _) = await prepared(gh: try fakeGh(newLabelOutput), publishing: false)
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadataEditing(for: pr).reason != nil, "má být vidět, proč to nejde")
    }

    /// **Label, který v repu už je, se nezaloží** — ani ve jiné velikosti písmen. Store se na to ptá
    /// **tou samou funkcí**, která akci nabízí, takže se ta dvě místa nemohou rozejít.
    @Test("Existující jméno se nezakládá", arguments: ["bug", "Bug", "GO"])
    func doesNotCreateAnExistingLabel(name: String) async throws {
        let (store, _) = await prepared(gh: try fakeGh(newLabelOutput))
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(
            PullRequestLabel(name: name, color: Policy.labelColor(for: name)),
            on: summary()
        )

        #expect(try ghCalls() == 0)
    }

    /// **Bez načtené nabídky se nezakládá.** Není proti čemu hledat duplikát, takže by `Bug` prošlo
    /// vedle `bug` jen proto, že se seznam nestihl dotáhnout.
    @Test("Bez načtené nabídky se label nezaloží")
    func doesNotCreateWithoutTheRepositoryList() async throws {
        let (store, _) = await prepared(gh: try fakeGh(newLabelOutput))

        await store.createLabel(Self.newLabel, on: summary())

        #expect(try ghCalls() == 0)
    }

    /// **Barva musí být ta z `Policy`.** Kdyby si ji směl složit volající, byla by dvě skládání téhož
    /// — a náhled v potvrzení by mohl ukazovat jinou barvu, než jaká odejde.
    @Test("Barva vymyšlená mimo Policy se neodešle")
    func doesNotSendAFabricatedColor() async throws {
        let (store, _) = await prepared(gh: try fakeGh(newLabelOutput))
        await store.loadRepositoryLabels(for: pr.repo)

        await store.createLabel(PullRequestLabel(name: "design-debt", color: "ff0000"), on: summary())

        #expect(try ghCalls() == 0)
    }

    /// **Mezi těmi dvěma voláními se nesmí pustit nic dalšího.** Je to jedna akce, takže klik na
    /// jiný label během ní by přepsal sadu, kterou první ještě nedokončil.
    @Test("Klik během zakládání se zahodí")
    func refusesAClickWhileCreating() async throws {
        // Zdržení u prvního volání: bez něj by zakládání doběhlo dřív, než druhý klik začne.
        let gh = try fakeGhSequence([(newLabelOutput, 0), (addedLabelsOutput, 0)], delayFirst: 0.4)
        let (store, _) = await prepared(gh: gh)
        await store.loadRepositoryLabels(for: pr.repo)

        let creating = Task { await store.createLabel(Self.newLabel, on: summary()) }
        await waitUntil("zakládání běží") {
            store.metadataActionState(for: self.pr) == .creatingLabel
        }
        await store.toggleLabel(Self.known[1], on: summary())
        await creating.value

        #expect(try ghCalls() == 2, "klik uprostřed nepřidal třetí volání")
        #expect(store.metadata(for: pr)?.labels.map(\.name) == ["bug", "design-debt"])
    }

}
