import Foundation

/// Diff v `AppStore`: načtení, pohled a sbalování souborů.
///
/// Stav (`diffStates`, `diffLayoutOverride`, `foldedFiles`) zůstává v `AppStore.swift` — dělí
/// se metody, ne data.
extension AppStore {
    func diffState(for pr: PRIdentifier) -> DiffState? { diffStates[pr] }

    /// Načte diff vybraného PR. Načtený se drží — na GitHub se sáhne znovu, teprve když
    /// se změní `updatedAt`.
    ///
    /// `updatedAt` se mění i po komentáři, takže se občas načte zbytečně. Opačná chyba —
    /// ukázat diff, ve kterém chybí nový commit — je dražší.
    func loadDiff(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDiff(for: pullRequest) else { return }
        diffStates[id] = .loading

        do {
            let text = try await gateway.fetchDiff(id: id)
            diffStates[id] = .loaded(DiffParser.parse(text), updatedAt: pullRequest.updatedAt)
            revealFindingsOutsideTheDiff(for: id)
        } catch is CancellationError {
            // Přepnutí na jiné PR načítání zruší. Nechat tam `.loading` by znamenalo
            // spinner, který se nikdy nedotočí. Maže se **jen** rozdělaný stav: mezitím
            // spuštěné načtení už mohlo doběhnout a to se přepsat nesmí.
            if diffStates[id] == .loading { diffStates[id] = nil }
        } catch let error as GitHubError {
            diffStates[id] = .failed(error.userDescription)
        } catch {
            diffStates[id] = .failed(error.localizedDescription)
        }
    }

    /// Rozdělané načítání se za platný diff **nepovažuje** — dvě souběžná načtení jsou
    /// jen zbytečné volání navíc, kdežto přeskočit to jediné, které běží, znamená prázdno
    /// v okně, dokud si uživatel PR nevybere znovu.
    private func hasCurrentDiff(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = diffStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    /// S jakým pohledem se diff kreslí: odchylka z lišty, jinak hodnota z nastavení.
    var diffLayout: DiffLayout {
        diffLayoutOverride ?? configuration.global.diffLayout
    }

    /// Přepnutí z lišty nad diffem.
    ///
    /// Odchylka se zapíše **i tehdy, když se rovná nastavené hodnotě**. Je to totéž pravidlo
    /// jako u `Configuration.setRepository`, kde se maže podle prázdnosti a ne podle shody
    /// s globální hodnotou: kdo si pohled otočil sám, má ho podržet i po změně v nastavení.
    /// Do zavření aplikace — po restartu platí zase nastavení.
    func setDiffLayout(_ layout: DiffLayout) {
        diffLayoutOverride = layout
    }

    func isFolded(_ path: String, in pr: PRIdentifier) -> Bool {
        foldedFiles.contains(FileExpansionKey(pullRequest: pr, path: path))
    }

    func toggleFolded(_ path: String, in pr: PRIdentifier) {
        let key = FileExpansionKey(pullRequest: pr, path: path)
        if foldedFiles.contains(key) {
            foldedFiles.remove(key)
        } else {
            foldedFiles.insert(key)
        }
    }

    /// Rozbalí soubor, ať se dá skočit dovnitř. Skok na sbalený soubor by jinak skončil
    /// nikde — jeho řádky v líném seznamu vůbec nejsou.
    func unfold(_ path: String, in pr: PRIdentifier) {
        foldedFiles.remove(FileExpansionKey(pullRequest: pr, path: path))
    }

    /// Sbalí vyjmenované soubory. Cesty dodává volající, protože co je v diffu, store neví.
    func foldAll(_ paths: [String], in pr: PRIdentifier) {
        foldedFiles.formUnion(paths.map { FileExpansionKey(pullRequest: pr, path: $0) })
    }

    /// Rozbalí všechno v tomhle PR. Cesty netřeba — rozbalené je to, co v množině není.
    ///
    /// Sahá **jen na tohle PR**: sbalení v jiném je cizí stav a smazat ho při „rozbalit vše“
    /// by znamenalo, že se tlačítko v jednom okně projeví jinde.
    func unfoldAll(in pr: PRIdentifier) {
        foldedFiles = foldedFiles.filter { $0.pullRequest != pr }
    }

    func loadedDiff(for pr: PRIdentifier) -> Diff? {
        guard case .loaded(let diff, _) = diffStates[pr] else { return nil }
        return diff
    }
}
