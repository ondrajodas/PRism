import Foundation

/// Prohlédnutí toho, co agent nacommitoval v kopii repa (#511).
///
/// **Krok, který do #511 chyběl.** Po doběhnutí agenta (#510) leželo v cache commitnuté cizí dílo
/// a jediná cesta, jak se na ně podívat, vedla **skrz nevratnou akci**: potvrdit force push
/// a přečíst si diff na GitHubu. Tady se čte **před ní**.
///
/// **Je to čtení `gitu` v cache, ne volání GitHubu.** Ten commit nikde jinde není, takže by na něj
/// `GitHubGateway.fetchDiff(repo:commit:)` neměl co odpovědět. Tvrdých podmínek se to netýká —
/// nic se neodesílá a do remote se nesáhne.
///
/// **Kreslí to tatáž obrazovka jako diff commitu** (`CommitDiffView`, #317): oba pohledy,
/// zvýrazňování, strom souborů i hledání. Druhá kresba pro tentýž obsah by se s tou první rozešla
/// první úpravou sazby — a hlavně by to byl třetí způsob, jak se v tomhle okně dívá na diff.
///
/// Stav (`agentCommits`, `commitDiffs`, `openCommits`) zůstává v `AppStore.swift` — dělí se
/// metody, ne data.
extension AppStore {
    /// Commit, který po agentovi zůstal v kopii repa. `nil` = nic tam neleží, nebo se to nečetlo.
    ///
    /// Čte to `PullRequestDetailView`, aby ho mohlo předat `Policy.openCommit(_:in:local:)` —
    /// do seznamu commitů pull requestu **nepatří**, viz `AppStore.agentCommits`.
    func agentCommit(in pr: PRIdentifier) -> PullRequestCommit? { agentCommits[pr] }

    /// Otevře diff agenta v tabu `Commity` (#511).
    ///
    /// **Nejdřív se přepne tab, teprve pak se čte.** Kliknutí musí něco udělat hned — u čtení
    /// z lokálního `gitu` jde o desítky milisekund, ale okno, které po kliknutí chvíli mlčí, se
    /// čte jako rozbité. Do té doby je v tabu `Načítám diff commitu…`, tedy tentýž stav jako
    /// u commitu z GitHubu.
    ///
    /// **Bez rozdělané práce v cache nedělá nic.** `Prohlédnout diff agenta` se kreslí jedině nad
    /// `rebased` s původem `.agent`, takže sem se z okna jinak nedá dojít; kontrola je tu podruhé
    /// ze stejného důvodu jako u `syncBranch` — spoléhat se na to, že si to pohlídá view, je
    /// o jedno místo k zapomenutí víc.
    func openAgentDiff(in pr: PRIdentifier) {
        guard let branch = branchSyncStates[pr]?.rebasedBranch, branch.origin == .agent else {
            return
        }
        openCommits[pr] = branch.headSha
        commitDiffs[pr] = CommitDiff(sha: branch.headSha, content: .loading)
        setDetailTab(.commits, for: pr)
        Task { [weak self] in await self?.loadAgentDiff(branch, in: pr) }
    }

    /// Přečte commit agenta a jeho diff z pracovního stromu.
    ///
    /// **Zápis je podmíněný shodou sha**, jako u diffu commitu z GitHubu: než se čtení vrátí,
    /// může být otevřený jiný commit — a doběhlé volání pak nesmí přepsat jeho místo v mapě.
    ///
    /// **Selhání končí ve stavu, ze kterého vede `Zkusit znovu`**, ne v mlčení: strom se dá
    /// mezitím zahodit z druhého okna a věčné `Načítám diff commitu…` by vypadalo jako zaseknutá
    /// aplikace.
    func loadAgentDiff(_ branch: RebasedBranch, in pr: PRIdentifier) async {
        guard let checkout else {
            store(.failed("git není k dispozici."), of: branch.headSha, in: pr)
            return
        }
        do {
            let commit = try await checkout.agentFixCommit(
                in: branch.worktree,
                since: branch.rebasedFrom
            )
            guard commitDiffs[pr]?.sha == branch.headSha else { return }
            agentCommits[pr] = Policy.agentCommitRow(commit)
            commitDiffs[pr]?.content = .loaded(DiffParser.parse(commit.diff))
            // **Přeskládat výskyty hledání** (#152), jako u diffu commitu z GitHubu: pruh v tomhle
            // tabu mohl zůstat otevřený z minula, a než diff dorazil, neměl v čem hledat. Bez toho
            // by `⌘F` nad diffem agenta hlásilo nula výskytů nad textem, ve kterém jsou.
            refreshDiffSearch(in: pr, commit: branch.headSha)
        } catch let error as CheckoutError {
            store(.failed(error.userDescription), of: branch.headSha, in: pr)
        } catch {
            store(.failed(error.localizedDescription), of: branch.headSha, in: pr)
        }
    }

    /// Zapomene commit agenta a jeho diff — **po zahození jeho práce** (#511).
    ///
    /// Bez toho by v tabu `Commity` zůstal otevřený diff commitu, který ve stromě už neleží; a to
    /// je zrovna ten tichý stav v cache, kterému se celá akce `Zahodit` vyhýbá.
    func forgetAgentDiff(in pr: PRIdentifier) {
        guard let commit = agentCommits.removeValue(forKey: pr) else { return }
        if openCommits[pr] == commit.sha { openCommits[pr] = nil }
        if commitDiffs[pr]?.sha == commit.sha { commitDiffs[pr] = nil }
    }

    /// Zapíše výsledek, jen když se mezitím nezměnil otevřený commit. Tatáž konstrukce jako
    /// u `AppStore+CommitDiff`, jen nad lokálním čtením.
    private func store(_ content: CommitDiff.Content, of sha: String, in pr: PRIdentifier) {
        guard commitDiffs[pr]?.sha == sha else { return }
        commitDiffs[pr]?.content = content
    }
}
