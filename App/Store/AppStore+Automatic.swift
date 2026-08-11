import Foundation

/// Automatický režim (#25) — review, které se pustí samo, a jeho denní rozpočet.
///
/// Rozpočet se **utrácí až při zabrání běhu** (`claimAutomaticRun`), ne při naplánování:
/// jinak by se počítaly i běhy, které se nikdy nespustily.
extension AppStore {
    /// Nespustí automat nic? Počítá se **teď**, z aktuálního limitu.
    ///
    /// Pokrývá **dva důvody** a schválně je nerozlišuje: vyčerpaný limit a limit nastavený
    /// na nulu. Pro rozhodnutí „ukázat hlášku“ je to totéž — repo je v automatickém režimu
    /// a nic se nespustí. Který z těch dvou to je, rozlišuje až text hlášky, protože
    /// „vyčerpaný limit (0)“ by tvrdilo, že se něco spotřebovalo.
    var isAutomaticStopped: Bool {
        guard let automaticRunsToday else { return false }
        return automaticRunsToday >= configuration.global.autoRunsPerDay
    }

    /// Naplánuje review pro repa v automatickém režimu.
    ///
    /// Volá se **jen po úspěšném tiku**: po výpadku sítě je seznam prázdný, takže by se
    /// nespustilo nic a `consideredForAutomation` by se rozešlo se skutečností.
    func startAutomaticReviews(for summaries: [PullRequestSummary]) async {
        // Zavírá se aplikace (#264): plánovat běh, který ji přežije, je zrovna to, co se tím
        // zavíráním zastavuje. Ruční cesta má tutéž bránu v `startReview`.
        guard let autoRuns, !isTerminating else { return }
        let limit = configuration.global.autoRunsPerDay
        let anyAutomatic = summaries.contains { resolved(for: $0.repo).mode == .automatic }
        automaticRunsToday = anyAutomatic ? await autoRuns.used() : nil

        let candidates = Policy.automaticallyReviewable(
            in: summaries,
            configuration: configuration,
            considered: consideredForAutomation,
            running: Set(reviewTasks.keys)
        )
        let updates = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0.updatedAt) })

        // Vyčerpaný rozpočet zastaví plánování **dřív**, než se sáhne na síť. Jinak by
        // každý tik stál `gh pr view` za PR, které se stejně nespustí.
        //
        // `?? 0` není tichý default: hodnota se o dva řádky výš právě načetla z disku a
        // `nil` je jen ve stavu „žádné automatické repo“, kdy je `candidates` stejně prázdné.
        guard (automaticRunsToday ?? 0) < limit else { return }

        for pr in candidates {
            // Zapsat se to smí až potom, co se běh opravdu naplánoval. Obrácené pořadí by
            // znamenalo, že PR zamítnutý rozpočtem se už nikdy nezváží.
            consideredForAutomation[pr] = updates[pr]
            automaticReviews.insert(pr)
            reviewTasks[pr] = RunningReview(
                task: Task { [weak self] in await self?.review(pr) },
                skills: nil
            )
        }
    }

    /// Smí tenhle běh utratit session?
    ///
    /// Ruční se neptá — za tím vždycky někdo stojí. Automatický si sáhne o denní rozpočet,
    /// a jen když je co spustit: repo s prázdnou sadou skillů („tady nereviewuj nic“) žádnou
    /// session neutratí, takže by za ni neměl nikdo platit.
    func canSpendSession(on pr: PRIdentifier) async -> Bool {
        guard automaticReviews.contains(pr) else { return true }
        guard !reviewSkills(for: pr.repo).isEmpty else {
            reviewPhases[pr] = nil
            return false
        }
        guard await claimAutomaticRun(for: pr) else {
            reviewPhases[pr] = nil
            return false
        }
        return true
    }

    /// Sáhne si o rozpočet pro automatický běh. `false` = dnes už ne.
    ///
    /// Volá se **až potom, co je jasné, že se utratí session** — tedy za bránou na
    /// `headSha`. Strhávat ho v plánovači znamenalo počítat i běhy, které se po dotažení
    /// detailu zahodí, a protože se `consideredForAutomation` po restartu vynuluje, spálil
    /// každý restart rozpočet za všechna auto PR, aniž by se cokoli spustilo.
    private func claimAutomaticRun(for pr: PRIdentifier) async -> Bool {
        guard let autoRuns else { return true }
        let allowed = await autoRuns.take(limit: configuration.global.autoRunsPerDay)
        automaticRunsToday = await autoRuns.used()
        // Zamítnutý PR se musí dát zvážit znovu, jinak by o review přišel i zítra, kdy je
        // rozpočet volný — `updatedAt` se od té doby nemusí změnit.
        if !allowed { consideredForAutomation[pr] = nil }
        return allowed
    }
}
