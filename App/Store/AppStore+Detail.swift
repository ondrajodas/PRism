import Foundation

/// Detail PR a jeho záložky.
///
/// Detail se dotahuje **při výběru řádku**, ne pollingem: pro všech N PR by to byla tatáž
/// N+1 past, kvůli které se netahá konverzace.
extension AppStore {
    /// Který tab je vidět. Výchozí drží `PullRequestTab.standard`, ať je odpověď na jednom
    /// místě — čte ji i test, který hlídá, že se to nerozejde.
    func detailTab(for pr: PRIdentifier) -> PullRequestTab { detailTabs[pr] ?? .standard }

    func setDetailTab(_ tab: PullRequestTab, for pr: PRIdentifier) {
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        detailTabs[pr] = tab == .standard ? nil : tab
    }

    func detailState(for pr: PRIdentifier) -> DetailState? { detailStates[pr] }

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
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            if detailStates[id] == .loading { detailStates[id] = nil }
        } catch let error as GitHubError {
            detailStates[id] = .failed(error.userDescription)
        } catch {
            detailStates[id] = .failed(error.localizedDescription)
        }
    }

    private func hasCurrentDetail(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = detailStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }
}
