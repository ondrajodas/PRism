import Foundation

extension Policy {
    /// Pull requesty, na které má automat spustit review.
    ///
    /// Čistá funkce — kdo je pustí a jestli na ně zbývá rozpočet, se rozhoduje jinde.
    /// Vybírá se z **posledního úspěšného tiku**, takže zavřený nebo mergnutý PR vypadne
    /// sám tím, že v seznamu není.
    ///
    /// Rozhoduje `updatedAt`, ne `headSha`: ten vyhledávání nedává (viz #4) a dotahovat
    /// detail každého PR při každém tiku by z jednoho pollu udělalo N podprocesů. Je to
    /// **hrubý filtr** — `updatedAt` se mění i po komentáři, takže projde i PR beze změny
    /// kódu. Session za to nezaplatíme: jestli pro ten `headSha` review už bylo, se pozná
    /// po dotažení detailu, a to je jedno `gh pr view`.
    static func automaticallyReviewable(
        in summaries: [PullRequestSummary],
        configuration: Configuration,
        /// `updatedAt`, se kterým se PR naposledy zvažoval. Co v mapě není, se nezvažovalo.
        considered: [PRIdentifier: Date],
        /// PR, nad kterými něco běží — druhý běh nad týmž PR nedává smysl.
        running: Set<PRIdentifier>
    ) -> [PRIdentifier] {
        summaries
            .filter { configuration.resolved(for: $0.repo).mode == .automatic }
            .filter { !running.contains($0.id) }
            // Draft se nereviewuje sám: autor na něm ještě pracuje a každý push by stál
            // session. Ruční spuštění zůstává.
            .filter { $0.state != .draft }
            .filter { considered[$0.id] != $0.updatedAt }
            .map(\.id)
    }
}
