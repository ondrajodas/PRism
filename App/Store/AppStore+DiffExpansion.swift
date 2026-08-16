import Foundation

/// Rozbalování kontextu mimo hunky (#47) — dotažení obsahu souboru a odhalené řádky.
///
/// Vlastní soubor, ne součást `AppStore+Diff`: je to jediná část diffu, která si sama chodí
/// na GitHub pro obsah souboru, a má vlastní stav odhalených řádků.
///
/// **Od #317 se totéž používá i v diffu commitu**, jen s jiným klíčem: `commit` v
/// `FileExpansionKey` říká, ze které verze souboru se čte. Jedna cesta pro obojí schválně —
/// druhá kopie by se rozešla zrovna v ořezávání rozsahů, na kterém stojí, že kotva ukazuje na
/// řádek, který se doopravdy vykreslí.
extension AppStore {
    /// Co je u souboru rozbalené. `commit == nil` = hlava PR (`Změněné soubory`).
    func expansion(of path: String, in pr: PRIdentifier, commit: String? = nil) -> FileExpansion {
        expansions[FileExpansionKey(pullRequest: pr, path: path, commit: commit)] ?? FileExpansion()
    }

    /// Je v diffu vidět něco navíc proti tomu, co poslal `gh`?
    ///
    /// Ptá se **na jeden diff**, ne na celé PR: rozbalený kontext v diffu commitu nesmí
    /// rozsvítit `Zobrazit jen diff` nad diffem PR, protože tam by nebylo co sbalit.
    func hasRevealedLines(in pr: PRIdentifier, commit: String? = nil) -> Bool {
        expansions.contains {
            $0.key.pullRequest == pr && $0.key.commit == commit && !$0.value.revealed.ranges.isEmpty
        }
    }

    /// Sbalí všechen rozbalený kontext zpátky na samotný diff.
    ///
    /// Načtený obsah souborů si **nechá**: kdyby ho zahodila, druhé rozbalení by znovu
    /// chodilo po síti pro něco, co už jednou dorazilo.
    ///
    /// Sbaluje **jen ten diff, ve kterém se na tlačítko kliklo** (stejný filtr jako
    /// `hasRevealedLines`) — jinak by tlačítko v `Změněných souborech` sbalilo i to, co si člověk
    /// rozbalil v diffu commitu, tedy na obrazovce, která zrovna není vidět.
    func collapseRevealedLines(in pr: PRIdentifier, commit: String? = nil) {
        // Zápis do `expansions` uprostřed iterace je bezpečný: slovník je hodnotový typ,
        // takže smyčka jede přes snapshot pořízený na jejím začátku. Ověřeno spuštěním
        // (1000 prvků, žádný přeskočený). Podmínka na prázdné rozsahy tu není kvůli
        // výkonu — zbytečný zápis by hlásil změnu i tam, kde se nic nezměnilo.
        for (key, expansion) in expansions where key.pullRequest == pr && key.commit == commit {
            guard !expansion.revealed.ranges.isEmpty else { continue }
            expansions[key]?.revealed = RevealedLines()
        }
    }

    /// Odkryje skryté řádky souboru. Obsah se dotáhne při prvním rozbalení a pak už se drží.
    ///
    /// Rozsah se zapíše **až po** načtení: kdyby se zapsal hned, zmizel by rozbalovací
    /// řádek i se spinnerem a zůstalo by po něm prázdno.
    func reveal(
        _ lines: ClosedRange<Int>,
        of path: String,
        in pr: PRIdentifier,
        commit: String? = nil
    ) {
        let key = FileExpansionKey(pullRequest: pr, path: path, commit: commit)
        var state = expansions[key] ?? FileExpansion()

        guard state.content.isEmpty else {
            state.revealed.reveal(lines)
            expansions[key] = state
            return
        }

        // Než obsah dorazí, rozsahy se schovávají stranou. Zahodit ten druhý (dva nálezy
        // v jednom souboru) by znamenalo bublinu bez kódu, o kterém mluví.
        state.pending.append(lines)
        guard !state.isLoading else {
            expansions[key] = state
            return
        }
        state.isLoading = true
        state.failure = nil
        expansions[key] = state
        Task { [weak self] in await self?.loadFile(key) }
    }

    private func loadFile(_ key: FileExpansionKey) async {
        do {
            let text = try await content(of: key)
            // Stav se čte **až po** awaitu: mezitím mohly přibýt další vyžádané rozsahy.
            var state = expansions[key] ?? FileExpansion()
            state.isLoading = false
            state.content = FileExpansion.lines(of: text)
            // Rozsahy se ořezávají na skutečnou délku souboru. Reviewer umí nahlásit řádek,
            // který v souboru není, a odkrytý neexistující řádek by dal kotvu na řádek,
            // který se nikdy nevykreslí — tedy skok, po kterém se nic nestane.
            for range in state.pending {
                guard let clamped = clamp(range, to: state.content.count) else { continue }
                state.revealed.reveal(clamped)
            }
            state.pending = []
            expansions[key] = state
        } catch is CancellationError {
            // Zrušení není selhání: úsek zůstane skrytý a další kliknutí to zkusí znovu.
            expansions[key]?.isLoading = false
        } catch {
            var state = expansions[key] ?? FileExpansion()
            state.isLoading = false
            state.pending = []
            state.failure = (error as? GitHubError)?.userDescription ?? error.localizedDescription
            expansions[key] = state
        }
    }

    /// Obsah souboru z té verze, o které klíč mluví — hlava PR, nebo konkrétní commit (#317).
    ///
    /// Rozhoduje se **tady, na jednom místě**, a ne u volajícího: `reveal` je tatáž operace pro
    /// obojí a jediné, co se liší, je odkud se text vezme.
    private func content(of key: FileExpansionKey) async throws -> String {
        guard let commit = key.commit else {
            return try await gateway.fetchFile(id: key.pullRequest, path: key.path)
        }
        return try await gateway.fetchFile(repo: key.pullRequest.repo, path: key.path, at: commit)
    }

    /// Dotáhne kód k nálezům, jejichž řádek v diffu není.
    ///
    /// Děje se to samo, ne na kliknutí (**změna proti #47**): bublina, která mluví
    /// o řádku 10, a řádek 10 nikde — to je přesně případ, kdy čekání na kliknutí stojí
    /// nejvíc. Týká se to jen souborů, kde nález opravdu je, takže se stahuje málo.
    func revealFindingsOutsideTheDiff(for pr: PRIdentifier) {
        guard case .loaded(let diff, _) = diffStates[pr], let record = reviewRecords[pr] else { return }

        for group in Policy.groups(of: record.findings) {
            guard let path = group.file, let line = group.line,
                  let file = diff.file(at: path),
                  // Smazaný soubor ani binárka nový obsah nemají, takže není co stahovat.
                  file.change != .deleted, !file.isBinary,
                  !file.showsLine(line)
            else { continue }

            reveal(max(1, line - Self.findingContext)...(line + Self.findingContext), of: file.displayPath, in: pr)
        }
    }

    private func clamp(_ range: ClosedRange<Int>, to length: Int) -> ClosedRange<Int>? {
        let lower = max(1, range.lowerBound)
        let upper = min(length, range.upperBound)
        return lower <= upper ? lower...upper : nil
    }
}
