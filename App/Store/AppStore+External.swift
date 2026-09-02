import Foundation

/// Pull request otevřený **mimo zdroje** (#531) — z vloženého odkazu, z `prism://` nebo
/// z palety ⌘K.
///
/// Zdroje (#4) definují **frontu**: co se hledá, na to se čeká, to je na kartách, v odznaku
/// a v automatu. Tahle cesta k nim nic nepřidává — otevře **záložku ke čtení** nad PR, o kterém
/// seznam z pollingu nic neví. Review se na něm dá pustit ručně jako na každém jiném; sám se
/// nespustí, protože automat čte `summaries` z tiku.
///
/// **Nic se odsud neodesílá.** Dotahuje se jediná věc, a to čtením: `gh pr view` přes
/// `GitHubGateway`, který zápisové metody nemá (tvrdá podmínka č. 1).
extension AppStore {
    /// Otevře **jakýkoli** pull request jako záložku — i takový, který ve zdrojích není.
    ///
    /// **Jediný vstupní bod pro „otevři tenhle PR podle identifikátoru“.** Chodí sem řádek
    /// `Odkaz` z palety (`reveal(_:)`) i `prism://open?url=…`; obojí zná jen `owner/repo#číslo`,
    /// nic víc. PR ze seznamu se otevře **beze změny** proti dnešku, tedy bez jediného dotazu na
    /// GitHub — teprve když se o něm neví nic, začne se dotahovat detail.
    ///
    /// **Záložka vzniká hned, ne až po dotažení.** Kliknutí, po kterém se sekundu neděje nic, je
    /// k nerozeznání od kliknutí, které nic neudělalo; načítání i selhání jsou proto stavy
    /// záložky (`Policy.tabContent(summary:detail:origin:)`), ne čekání před ní.
    func openPullRequest(_ pullRequest: PRIdentifier) {
        if summary(for: pullRequest) == nil {
            externalPullRequests.insert(pullRequest)
            // **Značka umí detail oživit**, takže se ptáme až po ní: po zavření a znovuotevření
            // záložky ho tik ještě nemusel uklidit, a v tom případě je `summary(for:)` rovnou
            // zpátky. Ptát se znovu by stálo volání `gh` **a** vrátilo záložku na obrazovku
            // načítání nad daty, která už jsou v ruce.
            if summary(for: pullRequest) == nil {
                // Rovnou tady, ať `tabContent` nemá mezeru mezi otevřením záložky a začátkem
                // dotahování — v ní by se kreslilo „pull request zmizel“, tedy porucha nad
                // stavem, ve kterém se nic nepokazilo.
                detailStates[pullRequest] = .loading
                Task { await loadExternalDetail(of: pullRequest) }
            }
        }
        openTab(pullRequest)
    }

    /// Dotáhne detail PR, o kterém se ví jenom adresa.
    ///
    /// **Vlastní cesta vedle `loadDetail(for:)`, ne její obejití**: ta bere `PullRequestSummary`,
    /// tedy přesně to, co u téhle záložky chybí a co z tohohle volání teprve vznikne. Jakmile
    /// detail dorazí, umí `summary(for:)` shrnutí složit a záložka pokračuje **úplně stejnou
    /// cestou jako každá jiná** — checky, commity, labely i větev si dotáhne `loadDetail`, kterou
    /// si detail PR zavolá sám, a ta už nad čerstvým detailem nic neopakuje.
    ///
    /// Volá se i z tlačítka `Zkusit znovu` nad selháním, takže **nesmí být jednorázová**.
    func loadExternalDetail(of pullRequest: PRIdentifier) async {
        detailStates[pullRequest] = .loading
        do {
            let detail = try await gateway.fetchDetail(id: pullRequest)
            // Zavřená záložka se nedopisuje: mezi začátkem dotahování a odpovědí je sekunda,
            // ve které se dá kliknout na křížek — a zápis by v mapách nechal PR, který v okně
            // nikde není, i s jeho detailem. Tik po tom by ho neuklidil, protože značka `mimo
            // zdroje` se zavřením zmizela.
            guard externalPullRequests.contains(pullRequest) else { return }
            detailStates[pullRequest] = .loaded(detail, updatedAt: detail.updatedAt)
            // Hlavu si pamatuje i návštěva (#173) — tatáž věta jako v `refreshDetail`.
            noteHead(detail.headSha, for: pullRequest)
            // Snímek záložky (#201): PR mimo zdroje v seznamu není, takže bez tohohle by po
            // zavření a znovuotevření zmizel z pruhu i s křížkem, kterým se zavírá.
            openTabSnapshots[pullRequest] = PullRequestSummary(detail)
        } catch is CancellationError {
            if detailStates[pullRequest] == .loading { detailStates[pullRequest] = nil }
        } catch let error as GitHubError {
            detailStates[pullRequest] = .failed(error.userDescription)
        } catch {
            detailStates[pullRequest] = .failed(error.localizedDescription)
        }
    }

    /// Odkud se PR v okně vzal — ze zdrojů, nebo mimo ně.
    ///
    /// Rozhoduje `Policy`, ne `if` ve view: tatáž odpověď se čte v hlavičce (pilulka) i v paletě
    /// (podtitulek řádku `Odkaz`), a dvě místa by znamenala dvě pravdy o jednom PR.
    func origin(of pullRequest: PRIdentifier) -> PullRequestOrigin {
        Policy.origin(
            of: pullRequest,
            adopted: externalPullRequests,
            sources: Set(pullRequests.map(\.id))
        )
    }

    /// Co má otevřená záložka ukázat.
    func tabContent(for pullRequest: PRIdentifier) -> PullRequestTabContent {
        Policy.tabContent(
            summary: summary(for: pullRequest),
            detail: detailStates[pullRequest],
            origin: origin(of: pullRequest)
        )
    }

    /// Pull requesty, na kterých v okně něco stojí: seznam z tiku **plus** záložky mimo zdroje.
    ///
    /// Jedno místo pro tu množinu schválně — čte ji úklid map v paměti (`forget(whatIsNotIn:)`),
    /// eviction cache a mazání uložených nálezů, a kdyby se ty tři rozešly, zůstal by po
    /// otevřené záložce klon bez záznamu, nebo záznam bez klonu.
    ///
    /// Řadí se, protože se z toho skládají cesty na disku a poloha slovníku v paměti není
    /// stabilní: nesetříděná množina by dělala z každého tiku jiné pořadí mazání.
    func pullRequestsInPlay(besides summaries: [PullRequestSummary]) -> [PRIdentifier] {
        Set(summaries.map(\.id)).union(externalPullRequests).sorted()
    }
}
