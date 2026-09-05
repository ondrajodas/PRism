import SwiftUI

/// Kde stojí výřez obsahu záložky — **jen to, jestli je na konci** (#507).
///
/// Mezerník si klávesu bere teprve tehdy, když už není kam scrollovat
/// (`Policy.itineraryStep`), takže to okno musí odněkud vědět. Tady je odpověď a nic víc:
/// poloha, výška ani rámečky sem nejdou, protože se mění při každém otočení kolečka a čtenář je
/// jeden jediný.
///
/// **`@Observable` třída, ne `@State` v detailu**, a je to výkonová podmínka (#503): hodnota se
/// mění při scrollování a `@State` detailu by za každou takovou změnu zaplatil průchodem tělem
/// celého detailu PR i s diffem. Takhle se překreslí jedno průhledné tlačítko.
///
/// **Hlášení nese, odkud je** (pull request a tab), a to je celé jádro téhle třídy: hodnota
/// z minulého tabu je v tom novém k nerozeznání od čerstvé, takže by mezerník po přepnutí
/// odskočil na základě obsahu, který už není na obrazovce. Nulovat to úlohou při přepnutí tabu
/// nejde spolehlivě — pořadí, ve kterém dorazí nulování a první hlášení nové geometrie, nikdo
/// negarantuje.
@Observable final class ContentEndState {
    /// Poslední hlášení. `nil` = **nikdo zatím nic nezměřil**.
    private(set) var report: Report?

    struct Report: Hashable, Sendable {
        let pullRequest: PRIdentifier
        let tab: PullRequestTab
        let isAtEnd: Bool
    }

    func note(_ isAtEnd: Bool, of pullRequest: PRIdentifier, in tab: PullRequestTab) {
        // Zápis téže hodnoty toolchain nehlásí (`PollObservationTests`), takže stráž na rovnost
        // tu není — a `Report` je `Equatable`, takže o případ #421 nejde.
        report = Report(pullRequest: pullRequest, tab: tab, isAtEnd: isAtEnd)
    }

    /// Je výřez na konci? **`nil` znamená „neměří se“**, ne „není“ — a `Policy.itineraryStep`
    /// z toho dělá totéž rozhodnutí (mezerník zůstane klávesou scrollu), protože tvrdit něco
    /// o obsahu, který nikdo nezměřil, nese víc, než data unesou.
    func isAtEnd(of pullRequest: PRIdentifier, in tab: PullRequestTab) -> Bool? {
        guard let report, report.pullRequest == pullRequest, report.tab == tab else { return nil }
        return report.isAtEnd
    }
}

extension View {
    /// Hlásí, jestli scroll dojel na konec obsahu (#507). `nil` = **tuhle obrazovku nikdo
    /// neposlouchá**, a pak se ani neměří.
    ///
    /// Bez posluchače se modifikátor **nepřipojí vůbec**: transformace `onScrollGeometryChange`
    /// běží uvnitř aktualizace grafu i tehdy, když se akce nespustí (#438), takže by to byla
    /// práce, jejíž výsledek nikdo nepřečte — v náhledech, v sondách a u diffu commitu, který
    /// s itinerářem nemá co do činění.
    @ViewBuilder func reportsContentEnd(_ report: ((Bool) -> Void)?) -> some View {
        if let report {
            onScrollGeometryChange(for: Bool.self) { geometry in
                Policy.contentAtEnd(
                    offset: geometry.contentOffset.y,
                    visible: geometry.containerSize.height,
                    content: geometry.contentSize.height
                )
            } action: { _, atEnd in
                report(atEnd)
            }
        } else {
            self
        }
    }
}
