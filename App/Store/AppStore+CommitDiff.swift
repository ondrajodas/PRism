import Foundation

/// Diff jednoho commitu (#317) — rozkliknutí, návrat a stažení.
///
/// **Přepnutí obsahu tabu, ne rozbalení pod řádkem.** Seznam zmizí a diff dostane celou plochu,
/// jako to má GitHub; proč, je v `CommitDiffView`.
///
/// Stav (`openCommits`, `commitDiffs`) zůstává v `AppStore.swift` — dělí se metody, ne data.
extension AppStore {
    /// Sha rozkliknutého commitu. `nil` = v tabu je seznam.
    ///
    /// Je to **žádost okna**, ne tvrzení o PR: jestli se ten commit v seznamu doopravdy najde,
    /// rozhoduje `Policy.openCommit(_:in:)` — po force pushi umí z PR zmizet a tab pak spadne
    /// zpátky na seznam.
    func openedCommit(in pr: PRIdentifier) -> String? { openCommits[pr] }

    /// Který řádek seznamu je **naposledy otevřený** — kvůli podbarvení a návratu na místo.
    ///
    /// Bere se ze staženého diffu, ne z vlastní paměti: `commitDiffs` po návratu do seznamu
    /// zůstává (viz `CommitDiff`), takže je to tatáž hodnota a nemá se s čím rozejít. Druhá mapa
    /// „kde jsem byl“ by uměla tvrdit něco jiného než ta, ze které se kreslí.
    func lastOpenedCommit(in pr: PRIdentifier) -> String? { commitDiffs[pr]?.sha }

    /// Co je vidět místo seznamu. Skládá se **ve store**, protože obě mapy drží on.
    func commitDiffState(of commit: PullRequestCommit, in pr: PRIdentifier) -> CommitDiffTabState {
        Policy.commitDiffTab(commitDiffs[pr], of: commit)
    }

    /// Rozklikne commit — přepne obsah tabu a **jde pro diff, když ho ještě nemá**.
    ///
    /// Načtený diff se drží a druhé otevření téhož commitu se neptá znovu: commit je neměnný,
    /// takže odpověď je tatáž. **Selhání se ptá znovu**, jinak by `Zkusit znovu` u chyby nic
    /// neudělalo; rozdělané stahování taky ne, to by byla druhá session pro tentýž text.
    func openCommit(_ sha: String, in pr: PRIdentifier) {
        openCommits[pr] = sha
        if let current = commitDiffs[pr], current.sha == sha {
            switch current.content {
            case .loaded, .loading: return
            case .failed: break
            }
        }
        commitDiffs[pr] = CommitDiff(sha: sha, content: .loading)
        Task { [weak self] in await self?.loadCommitDiff(sha, in: pr) }
    }

    /// Zpátky na seznam. **Stažený diff se nezahazuje** — je to paměť na to, kde v seznamu člověk
    /// byl, a zpátky do téhož commitu je díky němu zadarmo.
    func closeCommit(in pr: PRIdentifier) {
        openCommits[pr] = nil
    }

    /// Stáhne diff commitu.
    ///
    /// **Nezruší se odchodem ze seznamu** a je to schválně: je to jedno volání v řádu vteřiny
    /// a jeho výsledek je přesně to, co si člověk při návratu do commitu vyžádá znovu. Zápis
    /// je proto podmíněný jen shodou sha — kdyby se mezitím otevřel jiný commit, doběhlé volání
    /// nesmí přepsat jeho místo v mapě.
    ///
    /// **Zrušení tady nemá vlastní větev, na rozdíl od `loadDiff` a `loadCommits`** — a je to
    /// rozhodnutí, ne opomenutí. Tam zrušení znamená „odešel jsi z obrazovky“ (`.task` při přepnutí
    /// PR), takže se nemá o čem hlásit; tuhle úlohu ale **nikdo neruší**: je nestrukturovaná
    /// a handle se nedrží, takže `CancellationError` by sem přišla jedině cestou, se kterou se
    /// nepočítalo. A kdyby se nechala „být, jak je“, zůstalo by v tabu `Načítám diff commitu…`
    /// **navždycky a bez tlačítka**, protože stav se sám nevrátí. Skončí proto jako porucha, tedy
    /// ve stavu, ze kterého vede `Zkusit znovu`.
    func loadCommitDiff(_ sha: String, in pr: PRIdentifier) async {
        do {
            let text = try await gateway.fetchDiff(repo: pr.repo, commit: sha)
            // **Prázdná odpověď není chyba.** Změřeno: commit z `git commit --allow-empty` vrátí
            // nula bajtů s nulovým návratovým kódem, takže z něj vyjde prázdný `Diff` — a ten se
            // v tabu vysvětlí větou (`Policy.commitDiffTab`), ne prázdnou plochou.
            store(.loaded(DiffParser.parse(text)), of: sha, in: pr)
        } catch let error as GitHubError {
            store(.failed(error.userDescription), of: sha, in: pr)
        } catch {
            store(.failed(error.localizedDescription), of: sha, in: pr)
        }
    }

    /// Zapíše výsledek, **jen když se mezitím nezměnil otevřený commit**. Bez té podmínky by
    /// doběhlé volání přepsalo diff, o který si mezitím řeklo druhé kliknutí — a v okně by ležel
    /// diff, který k hlavičce nad ním nepatří.
    private func store(_ content: CommitDiff.Content, of sha: String, in pr: PRIdentifier) {
        guard commitDiffs[pr]?.sha == sha else { return }
        commitDiffs[pr]?.content = content
    }
}
