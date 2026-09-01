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
            // Nový diff = jiné řádky, takže výskyty hledání platí pro kód, který v okně už není
            // (#152). Bez tohohle by pruh ukazoval počet z minula a skok mířil do prázdna.
            refreshDiffSearches(in: id)
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

    /// Je soubor sbalený? `commit == nil` = diff PR (`Změněné soubory`), jinak diff commitu (#317).
    ///
    /// **Sbalení se mezi těmi dvěma diffy nesdílí**, i když jde o týž soubor: jsou to dvě různé
    /// obrazovky a sbalit si `Foo.php` při čtení commitu neznamená, že ho nechci vidět v review.
    /// Rozhoduje o tom `FileExpansionKey`, tedy tentýž klíč jako u rozbaleného kontextu — jedna
    /// hranice pro obojí, ať se nedá zapomenout jen v jednom z nich.
    func isFolded(_ path: String, in pr: PRIdentifier, commit: String? = nil) -> Bool {
        foldedFiles.contains(FileExpansionKey(pullRequest: pr, path: path, commit: commit))
    }

    func toggleFolded(_ path: String, in pr: PRIdentifier, commit: String? = nil) {
        let key = FileExpansionKey(pullRequest: pr, path: path, commit: commit)
        if foldedFiles.contains(key) {
            foldedFiles.remove(key)
        } else {
            foldedFiles.insert(key)
        }
    }

    /// Rozbalí soubor, ať se dá skočit dovnitř. Skok na sbalený soubor by jinak skončil
    /// nikde — jeho řádky v líném seznamu vůbec nejsou.
    ///
    /// Bez `commit`u schválně: skáče se jedině v diffu PR (z nálezu, z palety, z anotace CI),
    /// takže parametr, který by tady nikdo nevyplnil jinak než `nil`, by byl jen další místo,
    /// kde se dá splést.
    func unfold(_ path: String, in pr: PRIdentifier) {
        foldedFiles.remove(FileExpansionKey(pullRequest: pr, path: path))
    }

    /// Sbalí vyjmenované soubory. Cesty dodává volající, protože co je v diffu, store neví.
    func foldAll(_ paths: [String], in pr: PRIdentifier, commit: String? = nil) {
        foldedFiles.formUnion(paths.map {
            FileExpansionKey(pullRequest: pr, path: $0, commit: commit)
        })
    }

    /// Rozbalí všechno v tomhle diffu. Cesty netřeba — rozbalené je to, co v množině není.
    ///
    /// Sahá **jen na tohle PR a jen na tenhle diff**: sbalení v jiném je cizí stav a smazat ho
    /// při „rozbalit vše“ by znamenalo, že se tlačítko v jednom okně projeví jinde.
    func unfoldAll(in pr: PRIdentifier, commit: String? = nil) {
        foldedFiles = foldedFiles.filter { $0.pullRequest != pr || $0.commit != commit }
    }

    func loadedDiff(for pr: PRIdentifier) -> Diff? {
        guard case .loaded(let diff, _) = diffStates[pr] else { return nil }
        return diff
    }
}
