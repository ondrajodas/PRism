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
