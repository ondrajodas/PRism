import Foundation

/// Commity pull requestu (#316) — seznam do tabu `Commity`.
///
/// **Tahají se s detailem, ne pollingem.** Je to tatáž úvaha jako u checků (#209): pro všech N PR
/// ve frontě by to byla N+1 past, kvůli které se netahá ani detail. A tahají se **dopředu, ne až
/// při otevření tabu**, protože odznak u záložky je počet commitů — kdyby se čekalo na kliknutí,
/// objevil by se odznak až u tabu, který má člověk zrovna otevřený, a tedy zrovna tehdy, když ho
/// nepotřebuje.
extension AppStore {
    /// Co je v tabu `Commity` k vidění (#316).
    ///
    /// Skládá se **ve store, ne ve view**: čtou to dvě místa — odznak v pruhu záložek a plocha
    /// tabu — a obě mapy, ze kterých se to skládá, drží store. Dvě různá skládání by znamenala
    /// odznak, který mluví o jiném stavu než plocha pod ním.
    func commitsTabState(for pr: PRIdentifier) -> CommitsTabState {
        Policy.commitsTab(commits: commits[pr], failure: commitFailures[pr])
    }

    /// Dotáhne commity k PR. **Selhání se neschovává do prázdna** — prázdný seznam by tvrdil, že
    /// pull request nemá commity, což je nemožný stav (viz `Policy.commitsTab`).
    ///
    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád lepší
    /// než plocha s chybou místo commitů, které se před chvílí načetly. Zrušení (`.task` při
    /// přepnutí PR) se nezapisuje vůbec — to není porucha, to je odchod z obrazovky.
    func loadCommits(for id: PRIdentifier) async {
        do {
            commits[id] = try await gateway.fetchCommits(id: id)
            commitFailures[id] = nil
        } catch is CancellationError {
            // Nic: přepnutí PR není porucha.
        } catch let error as GitHubError {
            commitFailures[id] = error.userDescription
        } catch {
            commitFailures[id] = error.localizedDescription
        }
    }
}
