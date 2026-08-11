import Foundation

/// Detail PR a jeho záložky.
///
/// Detail se dotahuje **při výběru řádku**, ne pollingem: pro všech N PR by to byla tatáž
/// N+1 past, kvůli které se netahá konverzace.
extension AppStore {
    /// Který tab je vidět. Výchozí drží `PullRequestTab.standard`, ať je odpověď na jednom
    /// místě — čte ji i test, který hlídá, že se to nerozejde.
    ///
    /// **Volba se zarovná na to, co je v pruhu** (#215): `Kontroly` se u PR bez CI nekreslí,
    /// takže uložená volba na ně smí ukazovat jen tehdy, když tam ta záložka je. Bez toho by
    /// v okně nesvítila žádná záložka a plocha tabu by zůstala prázdná.
    ///
    /// Uložená volba se přitom **nemaže** — jen se nepoužije. Checky se dotahují s detailem, takže
    /// jsou chvíli po přepnutí PR ještě neznámé; smazat kvůli tomu volbu by znamenalo, že se
    /// z tabu `Kontroly` vypadne při každém příchodu na PR, i když se checky za chvíli objeví.
    func detailTab(for pr: PRIdentifier) -> PullRequestTab {
        let selected = detailTabs[pr] ?? .standard
        return Policy.tabs(hasChecks: hasChecks(pr)).contains(selected) ? selected : .standard
    }

    func setDetailTab(_ tab: PullRequestTab, for pr: PRIdentifier) {
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        detailTabs[pr] = tab == .standard ? nil : tab
    }

    /// Které záložky se u tohohle PR kreslí (#215). Jedno místo pro pruh i pro zarovnání volby
    /// výš — dvě různá pravidla by znamenala tab, na který se dá přepnout, ale nekreslí se.
    func detailTabs(of pr: PRIdentifier) -> [PullRequestTab] {
        Policy.tabs(hasChecks: hasChecks(pr))
    }

    /// Je u PR aspoň jeden check? **Chybějící klíč i prázdné pole znamenají „ne“** — pruh
    /// záložek na tom rozdílu nestojí (není čím tab naplnit ani v jednom případě), kdežto
    /// `AppStore.checks` ty dva stavy drží odděleně kvůli souhrnu v `Přehledu`.
    func hasChecks(_ pr: PRIdentifier) -> Bool {
        !(checks[pr] ?? []).isEmpty
    }

    func detailState(for pr: PRIdentifier) -> DetailState? { detailStates[pr] }

    /// Ukáže rozdělané review v panelu — přepne na jeho tab a **rozloží složený panel**.
    ///
    /// Tudy chodí všechno, co do těla review něco doručí (#242). Do té doby stačilo přepnout tab,
    /// protože nálezy měly v panelu vlastní; po přidání záložky `Nálezy` se ale panel dá složit
    /// a rozepsaná věta by spadla za proužek na hraně okna, tedy tam, kde ji nikdo nehledá.
    func revealDraft() {
        reviewPanelTab = .draft
        isReviewPanelExpanded = true
    }

    /// Popis PR, jak ho napsal autor. `nil` = detail se ještě nenačetl.
    func description(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.body
    }

    /// Hlava PR, jak ji naposledy vrátil `gh pr view`. `nil` = ještě nevíme.
    ///
    /// Na tom visí dvě věci: proti čemu se zakládá nový draft a jestli je ten stávající
    /// zastaralý. „Nevím“ se přitom nesmí splést se „zastaralé“ — proto optional a ne
    /// prázdný řetězec.
    func head(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.headSha
    }

    /// Dotáhne detail vybraného PR. Načtený se drží, dokud se nezmění `updatedAt` — stejná
    /// cache jako u diffu.
    func loadDetail(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDetail(for: pullRequest) else { return }
        detailStates[id] = .loading

        do {
            let detail = try await gateway.fetchDetail(id: id)
            detailStates[id] = .loaded(detail, updatedAt: pullRequest.updatedAt)
            // Hlavu si pamatuje i návštěva (#173): datum commitu na poznání nových commitů
            // nestačí, protože po rebase je starší než moje poslední návštěva.
            noteHead(detail.headSha, for: id)
            // Checky se tahají **s detailem** (#209), ne pollingem přes všechna PR: to je
            // tatáž N+1 past, kvůli které se netahá ani detail.
            await loadChecks(for: id)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            if detailStates[id] == .loading { detailStates[id] = nil }
        } catch let error as GitHubError {
            detailStates[id] = .failed(error.userDescription)
        } catch {
            detailStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Dotáhne checky k PR. **Selhání se neschovává do prázdna** (#215).
    ///
    /// Do #215 tu stálo `(try? await gateway.fetchChecks(id: id)) ?? []` s tím, že checky jsou
    /// doplněk k PR, ne důvod položit načtení hlavičky. To první pořád platí — pád se sem
    /// nepropaguje —, ale prázdno je od #215 **tvrzení**: na něm visí, jestli se nakreslí tab
    /// `Kontroly`, takže z chyby sítě by tiše vyšlo „tenhle PR nemá CI“. Gateway se přitom
    /// snaží ten rozdíl udržet (prázdný výstup s nulovým kódem = PR bez checků, nenulový
    /// s prázdným výstupem = chyba), takže by ho zahodilo právě tohle místo.
    ///
    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád
    /// lepší než zmizelý tab. Zrušení (`.task` při přepnutí PR) se nezapisuje vůbec — to není
    /// porucha, to je odchod z obrazovky.
    func loadChecks(for id: PRIdentifier) async {
        do {
            checks[id] = try await gateway.fetchChecks(id: id)
            checkFailures[id] = nil
        } catch is CancellationError {
            // Nic: přepnutí PR není porucha.
        } catch let error as GitHubError {
            checkFailures[id] = error.userDescription
        } catch {
            checkFailures[id] = error.localizedDescription
        }
    }

    private func hasCurrentDetail(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = detailStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }
}
