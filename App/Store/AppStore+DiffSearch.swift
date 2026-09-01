import Foundation

/// Klíč hledání — jeden pruh na jeden diff.
///
/// `commit` je součást klíče ze stejného důvodu jako u `FileExpansionKey`: diff commitu je jiný
/// obsah na týchž souřadnicích, takže sdílený stav by ukazoval počet výskytů z jiného diffu, než
/// je zrovna v okně.
struct DiffSearchKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// `nil` = hlava PR, tedy tab `Změněné soubory`.
    var commit: String?
}

/// Hledání v diffu (#152) — otevření pruhu, dotaz a přeskládání výskytů.
///
/// **Stav drží store, ne view**: pruh musí přežít přepnutí tabu (nálezy a zpátky) i složení panelu,
/// po kterém se `DiffView` staví znovu. Samotné hodnoty ale nejsou pole store, jsou to vlastnosti
/// **objektu** `DiffSearchState` — kdyby ležely ve slovníku, probudilo by každé písmeno všechny
/// čtenáře toho slovníku, tedy i tělo detailu PR (#472). Podrobnosti u toho typu.
///
/// **Skládání výskytů je čistá funkce** (`DiffSearch.hits`); tady se jen doplňuje, co k ní patří —
/// diff a rozbalený kontext. Volá se **jen tehdy, když se něco změnilo** (dotaz, rozbalení, nový
/// diff), nikdy z těla view: přepočítávat při každém překreslení je zakázaná třída (#224).
extension AppStore {
    /// Stav hledání, když už se v tom diffu hledalo. `nil` = pruh nikdy nebyl otevřený.
    ///
    /// **Nevytváří se čtením.** Zápis do slovníku uprostřed skládání těla view by byl změna
    /// observable stavu při jeho čtení — a hlavně by pruh vznikl i tam, kde o něj nikdo neřekl.
    func diffSearch(in pr: PRIdentifier, commit: String? = nil) -> DiffSearchState? {
        diffSearches[DiffSearchKey(pullRequest: pr, commit: commit)]
    }

    /// ⌘F: otevře pruh a řekne poli, ať se zaostří.
    ///
    /// Nad **už otevřeným** pruhem se jen zvýší `focusRequests` — druhé ⌘F má vrátit fokus do pole,
    /// ne pruh zavřít. Zavírá se `⎋` a `✕`, tedy pojmenovanou akcí.
    func openDiffSearch(in pr: PRIdentifier, commit: String? = nil) {
        let state = search(in: pr, commit: commit)
        state.isOpen = true
        state.focusRequests += 1
        // Výskyty se mohly přeskládat, dokud byl pruh zavřený (nový commit, rozbalený kontext),
        // takže se při otevření počítají znovu — jinak by pruh ukázal počet z minula.
        recompute(state, in: pr, commit: commit)
    }

    /// `⎋` nebo `✕`: zavře pruh.
    ///
    /// **Dotaz se nemaže** (druhé ⌘F pokračuje tam, kde první skončilo), ale zvýraznění zhasne —
    /// kreslí se z `DiffSearchState.drawnQuery`, a ta zavřený pruh nezvýrazňuje. Pozice se zapomíná:
    /// stát na výskytu má smysl jen s pruhem, ve kterém je vidět, kolikátý to je.
    func closeDiffSearch(in pr: PRIdentifier, commit: String? = nil) {
        guard let state = diffSearch(in: pr, commit: commit) else { return }
        state.isOpen = false
        state.current = nil
    }

    /// Dotaz z pole. Výskyty se přeskládají a **pozice se zapomene**.
    ///
    /// Zapomenutá pozice není opomenutí: po přepsání dotazu je seznam jiný, takže by starý index
    /// ukazoval na výskyt, který v něm není. Nové hledání proto začíná před prvním výskytem
    /// (`17 výskytů`) a `⏎`/`⌘G` skočí na první — **samo se neskáče**, jinak by se diff hýbal pod
    /// rukama při každém písmenu.
    func setDiffSearchQuery(_ text: String, in pr: PRIdentifier, commit: String? = nil) {
        let state = search(in: pr, commit: commit)
        guard state.query != text else { return }
        state.query = text
        state.current = nil
        recompute(state, in: pr, commit: commit)
    }

    /// Kapsle `Aa`. Přeskládá výskyty ze stejného důvodu jako dotaz.
    func setDiffSearchCaseSensitive(_ on: Bool, in pr: PRIdentifier, commit: String? = nil) {
        let state = search(in: pr, commit: commit)
        guard state.isCaseSensitive != on else { return }
        state.isCaseSensitive = on
        state.current = nil
        recompute(state, in: pr, commit: commit)
    }

    /// Šipka v pruhu (a `⌘G`). Vrací výskyt, na který se má skočit — kotvu si dopočítá diff,
    /// protože jedině on ví, jaký pohled kreslí a co je v souboru rozbalené.
    func stepDiffSearch(
        _ direction: NavigationStep,
        in pr: PRIdentifier,
        commit: String? = nil
    ) -> DiffSearchHit? {
        guard let state = diffSearch(in: pr, commit: commit) else { return nil }
        guard let index = Policy.searchStep(current: state.current, total: state.hits.count, direction)
        else { return nil }
        state.current = index
        return state.currentHit
    }

    /// Přeskládat výskyty, protože se změnil diff pod nima — nový commit, rozbalený nebo sbalený
    /// kontext.
    ///
    /// **Nic nedělá, dokud se nehledá**: zavřený pruh ani prázdné pole nemají co přepočítávat,
    /// takže tik pollingu nad diffem nic nestojí.
    ///
    /// **Zavřený pruh se počítá jako „nehledá se“, a je to podmínka, ne úspora** (nález Copilota
    /// z #152): dotaz si zavřený pruh **drží** (druhé ⌘F pokračuje tam, kde první skončilo), takže
    /// samotné `searchQuery.isActive` by nechalo přepočítávat celý diff při každém rozbalení
    /// kontextu i při každém novém diffu — a výsledek by se **neměl kde nakreslit**: zvýrazňuje se
    /// z `drawnQuery` (zavřený pruh nezvýrazňuje) a kapsle v hlavičce souboru chce `isOpen`.
    /// Při otevření se výskyty skládají znovu (`openDiffSearch`), takže se tím nic neztratí.
    func refreshDiffSearch(in pr: PRIdentifier, commit: String? = nil) {
        guard let state = diffSearch(in: pr, commit: commit), state.isOpen, state.searchQuery.isActive
        else { return }
        recompute(state, in: pr, commit: commit)
    }

    /// Přeskládat výskyty ve **všech** pruzích toho PR — po novém diffu se mění hlava, takže se to
    /// týká i pruhu v rozkliknutém commitu.
    func refreshDiffSearches(in pr: PRIdentifier) {
        for key in diffSearches.keys where key.pullRequest == pr {
            refreshDiffSearch(in: pr, commit: key.commit)
        }
    }

    // MARK: - Uvnitř

    /// Stav toho diffu, a když ještě není, tak nový. **Jediné místo, které do slovníku zapisuje.**
    private func search(in pr: PRIdentifier, commit: String?) -> DiffSearchState {
        let key = DiffSearchKey(pullRequest: pr, commit: commit)
        if let state = diffSearches[key] { return state }
        let state = DiffSearchState()
        diffSearches[key] = state
        return state
    }

    /// Spočítá výskyty a počty po souborech.
    ///
    /// Prázdný dotaz je **vyprázdnění, ne přeskočení**: kdyby se seznam nechal, zůstal by v pruhu
    /// počet výskytů slova, které v poli už není.
    private func recompute(_ state: DiffSearchState, in pr: PRIdentifier, commit: String?) {
        let query = state.searchQuery
        guard query.isActive, let diff = diff(in: pr, commit: commit) else {
            state.hits = []
            state.counts = [:]
            state.current = nil
            return
        }
        let hits = DiffSearch.hits(in: diff, query: query) { file in
            expansion(of: file.displayPath, in: pr, commit: commit)
        }
        state.hits = hits
        state.counts = DiffSearch.counts(of: hits)
        // Pozice se **uřízne, ne posune**: po přeskládání ukazuje starý index na jiný výskyt, takže
        // je poctivější stát nikde než někde jinde, než kde jsem byl.
        if let current = state.current, !hits.indices.contains(current) { state.current = nil }
    }

    /// Diff, ve kterém se hledá. `commit == nil` = hlava PR, jinak rozkliknutý commit.
    private func diff(in pr: PRIdentifier, commit: String?) -> Diff? {
        guard let commit else {
            guard case .loaded(let diff, _) = diffStates[pr] else { return nil }
            return diff
        }
        guard let stored = commitDiffs[pr], stored.sha == commit,
              case .loaded(let diff) = stored.content
        else { return nil }
        return diff
    }
}
