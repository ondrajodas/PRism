import Foundation

/// Diff „co od minule přibylo“ (#284) — nabídnout, načíst, zavřít.
///
/// Stav (`incrementalDiffs`) zůstává v `AppStore.swift` — dělí se metody, ne data.
extension AppStore {
    /// Rozsah, který by šlo ukázat. `nil` = tlačítko `Ukázat, co přibylo` se **nenabídne**.
    ///
    /// Rozhoduje `Policy`, protože je to rozhodnutí, ne skládání věty. Store k němu jen snese
    /// tři údaje: hlavu z minulé návštěvy, dnešní hlavu z detailu a to, jestli se od minule
    /// přepsala historie.
    ///
    /// Force push se bere z **téhož** `changesSinceLastVisit`, ze kterého se kreslí odrážky —
    /// vlastní průchod konverzací by byl druhá odpověď na tutéž otázku. Volá se z těla view,
    /// takže to znamená ještě jeden průchod jednou stránkou konverzace za překreslení; je to
    /// filtr přes stovky položek, ne obarvování tisíců řádků (#224), a jedna pravda za to stojí.
    func incrementalDiffRange(for pr: PRIdentifier) -> IncrementalDiffRange? {
        Policy.incrementalDiff(
            from: seenHeads[pr],
            to: loadedDetail(for: pr)?.headSha,
            // **`nil`, dokud není načtená konverzace**: bez časové osy se force push nemá odkud
            // dozvědět a `false` by tvrdilo, že historie zůstala nedotčená.
            rewroteHistory: conversation(for: pr).map { _ in
                !changesSinceLastVisit(for: pr).forcePushes.isEmpty
            }
        )
    }

    /// Co je z rozsahu načtené. `nil` = tab `Změněné soubory` kreslí celý diff.
    func incrementalDiff(for pr: PRIdentifier) -> IncrementalDiff? { incrementalDiffs[pr] }

    /// Ukáže jen to, co od minule přibylo.
    ///
    /// Nedělá **nic**, když se rozsah nedá sestavit — tlačítko, které to spouští, se v takovém
    /// případě vůbec nenabízí, takže tahle stráž hlídá jen závod s pollingem (mezitím dorazila
    /// nová hlava). Otevřít místo toho celý diff by bylo přesně to, co tlačítko slíbit nesmí.
    ///
    /// Načtený rozsah se **drží** a druhé kliknutí ho nenačítá znovu: klíčem jsou dvě sha, takže
    /// dokud se nezmění, je odpověď tatáž. Rozdělané načítání se ze stejného důvodu nespouští
    /// podruhé — **selhání ano**, jinak by tlačítko `Zkusit znovu` u chyby nic neudělalo.
    func showIncrementalDiff(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard let range = incrementalDiffRange(for: id) else { return }
        if let current = incrementalDiffs[id], current.range == range {
            switch current.content {
            case .loaded, .loading: return
            case .failed: break
            }
        }
        incrementalDiffs[id] = IncrementalDiff(range: range, content: .loading)
        // Zastávka `Od minule` v itineráři (#506): otevření rozsahu je záznam o tom, že jsem se
        // na přírůstek podíval. Zapisuje se **při vyžádání, ne po načtení** — kdo si o rozsah
        // řekl, ten si ho vyžádal, a selhání načtení je vidět na obrazovce zvlášť.
        noteSawChangesSinceLastVisit(for: id)

        do {
            let text = try await gateway.fetchDiff(repo: id.repo, from: range.seen, to: range.head)
            update(id, range: range) { $0 = .loaded(DiffParser.parse(text)) }
        } catch is CancellationError {
            // Přepnutí na jiné PR načítání zruší. Nechat tam `.loading` by znamenalo spinner,
            // který se nikdy nedotočí — a na rozdíl od celého diffu se tenhle sám znovu
            // nespustí, protože ho pouští jedině člověk.
            if incrementalDiffs[id]?.content == .loading, incrementalDiffs[id]?.range == range {
                incrementalDiffs[id] = nil
            }
        } catch let error as GitHubError {
            update(id, range: range) { $0 = .failed(error.userDescription) }
        } catch {
            update(id, range: range) { $0 = .failed(error.localizedDescription) }
        }
    }

    /// Zpátky na celý diff PR.
    func hideIncrementalDiff(for pr: PRIdentifier) {
        incrementalDiffs[pr] = nil
    }

    /// Zapíše výsledek, **jen když se mezitím rozsah nezměnil**. Bez té podmínky by doběhlé
    /// volání přepsalo rozsah, o který si mezitím řekl nový commit — a v okně by ležel diff,
    /// který k popisku nad ním nepatří.
    private func update(
        _ pr: PRIdentifier,
        range: IncrementalDiffRange,
        _ change: (inout IncrementalDiff.Content) -> Void
    ) {
        guard var current = incrementalDiffs[pr], current.range == range else { return }
        change(&current.content)
        incrementalDiffs[pr] = current
    }

    /// Načtený detail PR. `nil` u načítání i selhání — bez dnešní hlavy se rozsah nedá sestavit.
    private func loadedDetail(for pr: PRIdentifier) -> PullRequest? {
        guard case .loaded(let detail, _) = detailState(for: pr) else { return nil }
        return detail
    }
}
