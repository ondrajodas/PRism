import Foundation

/// Labely a vyžádaní reviewery v pravém panelu (#392).
///
/// Čte se **při výběru řádku**, spolu s detailem: panel je vidět ve čtyřech tabech ze sedmi
/// a rozložený je výchozí stav, takže „až na kliknutí“ by znamenalo prázdný panel při každém
/// otevření PR. Pollingem se to netahá — pro všech N PR je to tatáž N+1 past, kvůli které se
/// netahá detail.
///
/// Zapisuje se **jedinou cestou ven** (`MetadataSubmission`), a je to vědomé rozšíření tvrdé
/// podmínky č. 1 — zdůvodnění je u `ReviewPublishing`. Publisher se tady **nevyrábí**: skládá se
/// až uvnitř té akce, která odesílá, takže store drží jen cestu ke `gh` a stav.
extension AppStore {
    // MARK: - Čtení

    func metadataState(for pr: PRIdentifier) -> MetadataState? { metadataStates[pr] }

    /// Labely a reviewery, jak je aplikace naposledy viděla. `nil` = nevíme.
    func metadata(for pr: PRIdentifier) -> PullRequestMetadata? {
        metadataStates[pr]?.metadata
    }

    func metadataActionState(for pr: PRIdentifier) -> MetadataActionState? {
        metadataActionStates[pr]
    }

    /// Labely, které zná repo — nabídka k `+ label`. Prázdno = ještě se nenačetly, nebo je repo
    /// nemá; rozdíl drží `labelPickerFailure(in:)`.
    func knownLabels(in repo: RepoID) -> [PullRequestLabel] { repositoryLabels[repo] ?? [] }

    /// Proč je nabídka labelů prázdná. `nil` = poslední pokus prošel.
    func labelPickerFailure(in repo: RepoID) -> String? { repositoryLabelFailures[repo] }

    /// Proč je nabídka lidí prázdná. `nil` = poslední pokus prošel.
    func reviewerPickerFailure(in repo: RepoID) -> String? { assignableUserFailures[repo] }

    /// Dorazila už nabídka labelů? **Tři stavy, ne dva**: prázdná načtená nabídka znamená „repo
    /// žádné labely nezná“, kdežto nenačtená neznamená nic — a nabídka, která to slije, tvrdí o repu
    /// něco, co se ještě nezjistilo.
    func hasLoadedLabels(in repo: RepoID) -> Bool { repositoryLabels[repo] != nil }

    /// Dorazil už seznam lidí? Tatáž úvaha.
    func hasLoadedAssignableUsers(in repo: RepoID) -> Bool { assignableUsers[repo] != nil }

    /// Koho jde ještě vyžádat — lidi i **týmy**. Prázdno = seznam se ještě nenačetl, nebo jsou
    /// všichni vyžádaní.
    func reviewerCandidates(for pr: PRIdentifier) -> [ReviewerCandidate] {
        Policy.reviewerCandidates(
            assignable: assignableUsers[pr.repo] ?? [],
            teams: assignableTeams[pr.repo] ?? [],
            reviewers: metadata(for: pr)?.reviewers ?? [],
            requestedTeams: metadata(for: pr)?.teams ?? []
        )
    }

    /// Smí se na tomhle PR měnit label a vyžádat reviewer?
    ///
    /// **Jedna odpověď pro celý panel** — rozhoduje `Policy`, aby se okno neptalo dvakrát jinak.
    func metadataEditing(for pr: PRIdentifier) -> Policy.MetadataEditing {
        Policy.metadataEditing(
            ownership: ownership(of: pr),
            repo: pr.repo,
            scope: publishScope,
            hasTool: gh != nil
        )
    }

    /// Dotáhne labely a reviewery. Načtené se drží, dokud se nezmění `updatedAt` — stejná cache
    /// jako u detailu.
    ///
    /// **Selhání se neschovává do prázdna.** Prázdný snímek znamená „PR nemá labely ani vyžádané
    /// reviewery“, což je běžný stav, a sekce se pak nekreslí; kdyby z chyby sítě vyšlo totéž,
    /// vypadal by výpadek jako pull request bez štítků — a na vlastním PR by se dala kliknutím
    /// přepsat sada, kterou aplikace nezná.
    func loadMetadata(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentMetadata(for: pullRequest) else { return }
        metadataStates[id] = .loading

        do {
            let metadata = try await gateway.fetchMetadata(id: id)
            metadataStates[id] = .loaded(metadata, updatedAt: pullRequest.updatedAt)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            // Odchod z obrazovky není porucha.
            if metadataStates[id] == .loading { metadataStates[id] = nil }
        } catch let error as GitHubError {
            metadataStates[id] = .failed(error.userDescription)
        } catch {
            metadataStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Dotáhne labely repozitáře. **Jen když je nemáme** — nabídka se otevírá opakovaně a sada
    /// labelů se v repu nemění mezi dvěma kliknutími.
    ///
    /// **Selhání se neschovává do prázdna.** Prázdná nabídka je bezpečná (z ničeho se nedá vyrobit
    /// label), ale znamená „repo žádné labely nemá“ — a to je něco jiného než „nepodařilo se je
    /// zjistit“. Bez toho rozdílu by výpadek sítě poslal člověka hledat labely, které v repu jsou.
    /// Další otevření nabídky se ptá znovu, protože se seznam nezapsal.
    func loadRepositoryLabels(for repo: RepoID) async {
        guard repositoryLabels[repo] == nil else { return }
        do {
            repositoryLabels[repo] = try await gateway.fetchRepositoryLabels(repo: repo)
            repositoryLabelFailures[repo] = nil
        } catch is CancellationError {
            // Zavření nabídky není porucha.
        } catch let error as GitHubError {
            repositoryLabelFailures[repo] = error.userDescription
        } catch {
            repositoryLabelFailures[repo] = error.localizedDescription
        }
    }

    /// Dotáhne lidi **a týmy**, které na repo smí. Tatáž úvaha jako u labelů repozitáře.
    ///
    /// **Dvě volání, jedna nabídka a jedna porucha.** Když spadne kterékoli z nich, je nabídka
    /// nepřesná — a nepřesná nabídka se nemá tvářit jako úplná; ta věta je proto jedna. Týmy se
    /// tahají **za** lidmi, ne souběžně: obojí je `gh` podproces a paralelní spouštění by jich na
    /// jedno otevření nabídky zvedlo počet naráz běžících.
    func loadAssignableUsers(for repo: RepoID) async {
        guard assignableUsers[repo] == nil else { return }
        do {
            let logins = try await gateway.fetchAssignableUsers(repo: repo)
            let teams = try await gateway.fetchAssignableTeams(repo: repo)
            // **Zapisuje se až po obojím.** Kdyby se lidé zapsali hned, zůstala by po spadlých
            // týmech nabídka „načtená“ napůl — a další otevření by se už neptalo, protože stráž výš
            // se dívá jedině na lidi. Nabídka by pak hlásila poruchu **navždycky**, tedy „zkusit
            // znovu“, které nic nezkusí.
            assignableUsers[repo] = logins
            assignableTeams[repo] = teams
            assignableUserFailures[repo] = nil
        } catch is CancellationError {
            // Zavření nabídky není porucha.
        } catch let error as GitHubError {
            assignableUserFailures[repo] = error.userDescription
        } catch {
            assignableUserFailures[repo] = error.localizedDescription
        }
    }

    // MARK: - Zápis (jediná cesta ven)

    /// Přepne jeden label a zapíše sadu, kterou potvrdil GitHub.
    ///
    /// **Sada se posílá celá** a skládá ji `Policy.toggledLabels`, která zároveň hlídá, že v ní
    /// není label, který repo nezná. `nil` znamená **nic neodeslat** — z nabídky se do ní neznámý
    /// label dostat nemá, ale kontrola ve view je kontrola, kterou příští obrazovka obejde.
    func toggleLabel(_ label: PullRequestLabel, on pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard metadataEditing(for: id).isAllowed else { return }
        guard let current = metadata(for: id) else { return }
        guard let names = Policy.toggledLabels(
            label,
            on: current.labels,
            known: knownLabels(in: id.repo)
        ) else { return }
        guard let submission = metadataSubmission(for: id) else { return }
        // Dvojklik: druhé odeslání by přepsalo sadu, kterou první ještě nedokončil. Kontrola leží
        // **před** prvním `await`, takže mezi nimi není mezera, do které by se závod vešel.
        guard metadataActionStates[id]?.isBusy != true else { return }
        metadataActionStates[id] = .settingLabels

        do {
            let labels = try await submission.setLabels(names)
            metadataActionStates[id] = nil
            apply(labels: labels, to: pullRequest)
        } catch let error as PublishError {
            metadataActionStates[id] = .failed(error)
        } catch {
            metadataActionStates[id] = .failed(.unknown(error.localizedDescription))
        }
    }

    /// Založí nový label v repozitáři a hned ho přidá na PR — **dvě volání** (#413).
    ///
    /// **Tvrdá podmínka č. 5 (jedno atomické volání) pro tuhle akci neplatí** a je to vědomé:
    /// `POST /repos/{repo}/labels` a `PUT /issues/{n}/labels` se spojit nedají, takže mezi nimi
    /// existuje stav *label v repozitáři je, na PR není*. Zamítnutá alternativa je **samotné
    /// `Založit`** bez přidání: atomické by bylo, ale v devíti z deseti případů by po něm musel
    /// následovat klik na řádek v nabídce, tedy krok navíc za čistotu, kterou vidí jen dokumentace.
    ///
    /// Co za to platí: **selhání druhého volání nesmí vypadat jako selhání obojího**. Proto
    /// `MetadataActionState.createdNotAdded`, ne `failed` — a proto se založený label zapíše do
    /// nabídky ještě **před** druhým voláním, takže se to dá dorovnat jedním kliknutím.
    func createLabel(_ label: PullRequestLabel, on pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        let editing = metadataEditing(for: id)
        guard editing.isAllowed else { return }
        guard let current = metadata(for: id) else { return }
        // **Ověří se znovu tou samou funkcí, která akci nabízí.** Uzavřenost seznamu tady nepomůže
        // (nový label v něm z definice není), takže je to jediné místo, kde se dá zkontrolovat, že
        // se nezakládá prázdné jméno, duplikát ani barva vymyšlená mimo `Policy` — a jediná kontrola
        // ve view je kontrola, kterou příští obrazovka obejde.
        guard let offer = Policy.newLabelOffer(
            query: label.name,
            known: knownLabels(in: id.repo),
            isLoaded: hasLoadedLabels(in: id.repo),
            editing: editing
        ), offer == label else { return }
        guard let submission = metadataSubmission(for: id) else { return }
        guard metadataActionStates[id]?.isBusy != true else { return }
        metadataActionStates[id] = .creatingLabel

        let created: PullRequestLabel
        do {
            created = try await submission.createLabel(label)
        } catch let error as PublishError {
            metadataActionStates[id] = .failed(error)
            return
        } catch {
            metadataActionStates[id] = .failed(.unknown(error.localizedDescription))
            return
        }

        // **Řádek v nabídce od téhle chvíle je.** `loadRepositoryLabels` se podruhé neptá (sada se
        // v repu mezi dvěma kliknutími nemění), takže bez tohohle zápisu by se dorovnání kliknutím
        // nedalo udělat až do restartu — a věta v panelu by tvrdila víc, než data unesou.
        remember(created, in: id.repo)

        // Základ se čte **znovu**, ne z hodnoty před prvním voláním: mezi voláními se snímek mohl
        // načíst znovu (nové `updatedAt` z pollingu), a sada se posílá celá, takže starší základ by
        // sundal štítek, který mezitím někdo přidal.
        let base = metadata(for: id)?.labels ?? current.labels
        guard let names = Policy.toggledLabels(
            created,
            on: base,
            known: knownLabels(in: id.repo)
        ) else {
            // **Nesložená sada je taky mezistav, ne „nic“.** Dostat se sem jde: úklid cache
            // (`pruneCaches`) zahazuje `repositoryLabels` podle toho, které PR chceme, takže mezi
            // těmi dvěma voláními může nabídka zmizet — a `toggledLabels` pak label, který repo
            // „nezná“, odmítne. Label ale v repozitáři **je**, takže `nil` by tady byla ta nejhorší
            // možná odpověď: půlka se stala a v panelu by po tom nezůstalo nic.
            metadataActionStates[id] = .createdNotAdded(
                name: created.name,
                error: .unknown("Nabídka labelů se mezitím zahodila, takže se přidání nezkusilo.")
            )
            return
        }

        do {
            let labels = try await submission.setLabels(names)
            metadataActionStates[id] = nil
            apply(labels: labels, to: pullRequest)
        } catch let error as PublishError {
            metadataActionStates[id] = .createdNotAdded(name: created.name, error: error)
        } catch {
            metadataActionStates[id] = .createdNotAdded(
                name: created.name,
                error: .unknown(error.localizedDescription)
            )
        }
    }

    /// Vyžádá review od jednoho člověka a zapíše, na koho se podle GitHubu čeká.
    /// **Jen z nabídky.** Kontrola je i tady, ne jen ve view: uzavřená množina je to jediné, co
    /// drží slib, že se nevyžádá review od někoho, komu to GitHub odmítne — a jediná kontrola ve
    /// view je kontrola, kterou příští obrazovka obejde. Tatáž úvaha jako u labelů.
    func requestReview(from candidate: ReviewerCandidate, on pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard metadataEditing(for: id).isAllowed else { return }
        guard reviewerCandidates(for: id).contains(candidate) else { return }
        guard let submission = metadataSubmission(for: id) else { return }
        guard metadataActionStates[id]?.isBusy != true else { return }
        metadataActionStates[id] = .requestingReviewer

        do {
            let requested = try await submission.requestReview(from: candidate)
            metadataActionStates[id] = nil
            apply(requested: requested, to: pullRequest)
        } catch let error as PublishError {
            metadataActionStates[id] = .failed(error)
        } catch {
            metadataActionStates[id] = .failed(.unknown(error.localizedDescription))
        }
    }

    /// Přepne vlastní draft na *ready for review* (#482) a **načte stav PR znovu**.
    ///
    /// **Bez potvrzovacího sheetu**, na rozdíl od review (#68) a merge (#465): payload je jeden bit,
    /// takže sheet, jehož výpis *Co se stane* má jediný řádek, se neptá na obsah — ptá se „opravdu?“.
    /// Nevratná část na tom **je** (vyžádání review od `CODEOWNERS`), a odpovídá se na ni tak jako
    /// u `+ reviewer` v #392: **slovesem tam, kde se kliká**, a větou pod tlačítkem
    /// (`Policy.readyForReviewNote`).
    ///
    /// **Kontrola je i tady, ne jen ve view** — tou samou funkcí, která akci nabízí: `readyForReviewOffer`
    /// zná stav PR i bránu, a jediná kontrola ve view je kontrola, kterou příští obrazovka obejde.
    ///
    /// **Stav se po úspěchu načte znovu**, tatáž cesta jako po vlastním mergi
    /// (`pullRequestWasMerged`): odpověď `gh pr ready` je prázdná, takže jediné, z čeho se dá nový
    /// stav vzít, je pull request sám — a bez toho by v panelu zůstala výstraha o rozpracovanosti
    /// nad PR, který už draft není. Záložka se u toho ale **nezavírá**: přepnutím na *ready* práce
    /// na PR nekončí, začíná.
    func markReadyForReview(on pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard Policy.readyForReviewOffer(
            editing: metadataEditing(for: id),
            state: detail(of: id)?.state,
            action: metadataActionStates[id]
        ).isAllowed else { return }
        guard let submission = metadataSubmission(for: id) else { return }
        metadataActionStates[id] = .markingReady

        do {
            try await submission.markReadyForReview()
            metadataActionStates[id] = nil
            await pullRequestBecameReady(pullRequest)
        } catch let error as PublishError {
            metadataActionStates[id] = .readyFailed(error)
        } catch {
            metadataActionStates[id] = .readyFailed(.unknown(error.localizedDescription))
        }
    }

    /// Úklid po přepnutí na *ready for review*: **jen nové načtení detailu** (#482).
    ///
    /// Cache se zahazuje **ručně**, ze stejného důvodu jako u merge: detail jde podle `updatedAt`
    /// shrnutí, a to se v našem seznamu přepnutím draftu nemusí posunout dřív než při dalším tiku —
    /// takže bez toho zápisu by panel dál tvrdil, že je PR rozpracovaný.
    ///
    /// **Slévatelnost se zahazuje taky, a v tom se to od merge liší.** Na mergnutém PR se nová
    /// odpověď nemá kde vzít (`mergeable` vrací `UNKNOWN` navždycky) a `Policy.mergeOffer` ji
    /// stejně přebije stavem PR, takže tam se stará hodnota nechává být. Tady je to naopak ta
    /// **jediná** hodnota, která se přepnutím mění na užitečnou: draft má `mergeStateStatus`
    /// `DRAFT`, takže by po přepnutí zůstal v panelu řádek `rozpracovaný` a `Mergnout…` by se
    /// nerozsvítilo, dokud se nezmění `updatedAt`.
    ///
    /// **Záložka zůstává otevřená** — opak merge (#465). Tam ji zavírá tentýž klik, kterým člověk
    /// PR dokončil; tady se PR teprve předává ostatním a zavřít okno by znamenalo zahodit kontext
    /// zrovna ve chvíli, kdy se na něj bude odpovídat.
    ///
    /// **Volá se jedině `loadDetail`, ne k tomu i `loadBranchStatus`.** Ten si `loadDetail` na konci
    /// zavolá sám (a jen na vlastním PR, což je tady vždycky splněné), takže druhé volání by na
    /// stráži `hasCurrentBranchStatus` skončilo bez efektu — a stav zahozený o dva řádky výš je
    /// zrovna to, co mu dovolí se doopravdy zeptat.
    private func pullRequestBecameReady(_ pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        detailStates[id] = nil
        branchStatuses[id] = nil
        await loadDetail(for: pullRequest)
    }

    /// Zapomene chybu odesílání — po přečtení, ne sama. Chyba, která zmizí sama, je chyba, kterou
    /// nikdo nepřečte.
    func clearMetadataFailure(for pr: PRIdentifier) {
        guard metadataActionStates[pr]?.isBusy != true else { return }
        metadataActionStates[pr] = nil
    }

    // MARK: - Zápis do stavu okna

    /// Vloží potvrzenou sadu labelů do snímku, ať je vidět bez kola po síti.
    ///
    /// Když snímek načtený **není**, nezakládá se: bez něj se akce nedá ani vyvolat
    /// (`toggleLabel` na to čeká), takže by to byl stav složený z poloviny odpovědi.
    private func apply(labels: [PullRequestLabel], to pullRequest: PullRequestSummary) {
        let id = pullRequest.id
        guard case .loaded(var metadata, let updatedAt) = metadataStates[id] else { return }
        metadata.labels = labels
        metadataStates[id] = .loaded(metadata, updatedAt: updatedAt)
    }

    /// Vloží potvrzené vyžádání do snímku. Odpovědi ostatních **zůstávají** — GitHub je
    /// v odpovědi neposílá, takže je slévá `Policy`, tou samou funkcí jako při čtení.
    private func apply(requested: RequestedReview, to pullRequest: PullRequestSummary) {
        let id = pullRequest.id
        guard case .loaded(var metadata, let updatedAt) = metadataStates[id] else { return }
        metadata.reviewers = Policy.reviewers(
            requested: requested.reviewers.map(\.login),
            keeping: metadata.reviewers
        )
        // Týmy se přepisují **celé z odpovědi**: nemají odpověď, kterou by bylo potřeba zachovat,
        // takže `requested_teams` je úplný stav toho, na kterých týmech PR leží.
        metadata.teams = requested.teams
        metadataStates[id] = .loaded(metadata, updatedAt: updatedAt)
    }

    /// Přidá právě založený label do nabídky repozitáře (#413).
    ///
    /// Zapisuje se **jen do už načtené** nabídky: z `nil` (nenačtená, nebo spadlé načtení) by tím
    /// vzniklo tvrzení „repo zná právě jeden label“, což je nepravda. Nabídka je v tu chvíli načtená
    /// vždycky — `Policy.newLabelOffer` bez toho akci nenabídne —, takže je to stráž, ne větev.
    private func remember(_ label: PullRequestLabel, in repo: RepoID) {
        guard var labels = repositoryLabels[repo] else { return }
        guard !labels.contains(where: { $0.name == label.name }) else { return }
        labels.append(label)
        repositoryLabels[repo] = labels
    }

    /// Publisher se tu **nevyrábí** — jen se předá `gh`, read-only gateway a brána. Vzniká až
    /// uvnitř `MetadataSubmission`, viz tvrdá podmínka č. 1.
    private func metadataSubmission(for pr: PRIdentifier) -> MetadataSubmission? {
        guard let gh else { return nil }
        return MetadataSubmission(pullRequest: pr, gh: gh, gateway: gateway, scope: publishScope)
    }

    private func hasCurrentMetadata(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = metadataStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }
}
