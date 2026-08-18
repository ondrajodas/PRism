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
    ///
    /// **Vlastní PR automat nevydá nikdy** (#332) — ani při globálním `mode: automatic`, ani když
    /// si o automat řekne repo svým `RepositoryConfig`. Je to **pravidlo, ne výchozí hodnota**,
    /// a přepínač do nastavení se k tomu **zamítl** ze tří důvodů:
    ///
    /// - **Automat existuje kvůli čekání.** Smysl je, aby na cizí PR bylo review hotové dřív, než
    ///   se k němu dostanu. U vlastního PR není na co čekat — review si na něm pouštím ve chvíli,
    ///   kdy ho chci, protože vím, kdy jsem dopsal.
    /// - **Vlastní PR se mění pod rukama.** Píše se na něm a pushuje, takže každý push je nová
    ///   hlava a nové kolo automatu: nálezy proti kódu, který za deset minut nebude.
    /// - **Přepínač je cesta, jak si to zapnout omylem.** Jediné, co by přinesl, je způsob, jak to
    ///   pravidlo porušit.
    ///
    /// Filtr je proto **první v řadě**: co je moje, se dál nezvažuje, ať si repo řeklo cokoli.
    /// Ruční spuštění (`AppStore.startReview`) tím dotčené **není** — pravidlo se týká automatu,
    /// ne tlačítka.
    ///
    /// `mine` proto **nemá výchozí hodnotu**, na rozdíl od `Policy.dashboard`: prázdná množina
    /// znamená „nikdo nejsem“, takže by zapomenutý parametr to pravidlo tiše vypnul — a tady se
    /// za každý průchod platí session.
    static func automaticallyReviewable(
        in summaries: [PullRequestSummary],
        configuration: Configuration,
        /// Loginy, které se počítají za moje (`Policy.ownLogins`). Prázdné = neví se, kdo se dívá,
        /// takže je podle `ownership(of:mine:)` všechno cizí — tatáž bezpečná strana jako všude.
        mine: Set<String>,
        /// `updatedAt`, se kterým se PR naposledy zvažoval. Co v mapě není, se nezvažovalo.
        considered: [PRIdentifier: Date],
        /// PR, nad kterými něco běží — druhý běh nad týmž PR nedává smysl.
        running: Set<PRIdentifier>
    ) -> [PRIdentifier] {
        summaries
            .filter { ownership(of: $0, mine: mine) == .theirs }
            .filter { configuration.resolved(for: $0.repo).mode == .automatic }
            .filter { !running.contains($0.id) }
            // Draft se nereviewuje sám: autor na něm ještě pracuje a každý push by stál
            // session. Ruční spuštění zůstává.
            .filter { $0.state != .draft }
            .filter { considered[$0.id] != $0.updatedAt }
            .map(\.id)
    }
}
