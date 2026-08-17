import Foundation

/// Čí jsou pull requesty v seznamu (#330).
///
/// Samo **dotažení** loginu (`loadViewer()`) je v `AppStore.swift` u ostatních věcí, které se
/// načítají při startu — a taky proto, že `viewer` je `private(set)`: zapsat ho smí jedině ten
/// jeden loader, ne kterýkoli extension nebo view.
extension AppStore {
    /// Loginy, které se počítají za moje — viewer plus to, co je v konfiguraci (#330).
    ///
    /// **Počítá se při každém čtení, nedrží se ve stavu.** Jsou to jeden až dva loginy, kdežto
    /// uložená množina by měla dvě místa, která by ji musela obnovovat (dotažený login a `apply(_:)`
    /// konfigurace) — tedy dvě pravdy o tom, kdo jsem. Kdo ji potřebuje pro **celý seznam**, si ji
    /// má vzít jednou do lokální hodnoty a zavolat `Policy.ownership(of:mine:)` nad řádky, ne se
    /// ptát storu u každého z nich.
    var ownLogins: Set<String> {
        Policy.ownLogins(viewer: viewer, configured: configuration.global.ownLogins)
    }

    /// Čí je pull request. Dokud není znám `viewer`, je všechno `.theirs`.
    ///
    /// Počítá se **nad hotovým seznamem**, ne při slučování zdrojů: `PullRequestList.merged` je
    /// o deduplikaci, ne o tom, čí co je, a jeden PR umí přijít z víc zdrojů naráz.
    func ownership(of summary: PullRequestSummary) -> PullRequestOwnership {
        Policy.ownership(of: summary, mine: ownLogins)
    }

    /// Tatáž otázka nad samotnou identitou PR — pro místa, která shrnutí po ruce nemají (#333):
    /// který segment kreslí panel a jestli se smí zakládat draft.
    ///
    /// **Bere autora ze seznamu, a teprve když tam není, z detailu.** Shrnutí je u zobrazeného PR
    /// vždycky (přišlo z hledání), kdežto detail dorazí až po něm — a brána na zakládání draftu
    /// musí platit **od první obtažené obrazovky**, ne až od chvíle, kdy dojde `gh pr view`.
    func ownership(of pr: PRIdentifier) -> PullRequestOwnership {
        Policy.ownership(ofAuthor: author(of: pr), mine: ownLogins)
    }

    /// Autor PR — ze seznamu, jinak z dotaženého detailu. `nil` = ještě nevíme.
    ///
    /// **Jedno místo pro obojí**, protože se na autora ptají dvě různé otázky (co GitHub udělá
    /// s review a čí PR to je) a dvě cesty k němu by znamenaly, že jedna z nich odpoví jinak.
    /// Plný seznam, ne `visiblePullRequests`: čí je PR nesmí záviset na tom, co je zrovna po
    /// filtru vidět.
    func author(of pr: PRIdentifier) -> String? {
        if let summary = pullRequests.first(where: { $0.id == pr }) { return summary.author }
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.author
    }

    /// Je mezi zdroji ten, který přináší vlastní PR (#330)?
    ///
    /// Prázdná sekce `Moje PR` bez něj znamená „zdroj chybí“, ne „nic tam neleží“ — a to jsou dvě
    /// různé věty. Kreslí ji #331, poznat se to musí tady.
    ///
    /// Ptá se na **aktivní** zdroje, tedy tytéž, na které se aplikace doopravdy ptá: rozepsaný
    /// řádek bez dotazu se přeskakuje v `activeSources`, takže by jinak stačilo mít v nastavení
    /// prázdný řádek, aby si okno myslelo, že vlastní PR sleduje.
    var tracksOwnPullRequests: Bool {
        Policy.tracksOwnPullRequests(in: configuration.activeSources, mine: ownLogins)
    }
}
