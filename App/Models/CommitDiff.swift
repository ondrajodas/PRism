import Foundation

/// Diff **jednoho commitu** (#317) — který to je a jak dopadlo jeho stažení.
///
/// Sha je **v hodnotě, ne v klíči**, a je to rozhodnutí o paměti: na PR je klíčem pull request,
/// takže se v okně drží nejvýš **jeden** diff commitu na PR. Mapa klíčovaná `(PR, sha)` by u PR
/// se stovkou commitů rostla o každý proklik a byly by to megabajty za obrazovky, které nikdo
/// nemá vidět — tatáž úvaha jako u `expandedChecks`, kde je rozbalený check taky jen jeden.
///
/// Poslední stažený diff se přitom **nezahazuje návratem do seznamu**: je to jediná cena, kterou
/// za tenhle strop platíme, a naopak nám dává, že zpátky a znovu do téhož commitu je zadarmo.
/// Zároveň je to paměť okna na to, **kde v seznamu člověk byl** — viz `AppStore.openCommit(in:)`.
struct CommitDiff: Equatable, Sendable {
    let sha: String
    var content: Content

    /// **Vlastní stav, ne `DiffState`.** Ten nese `updatedAt`, podle kterého se pozná, jestli se
    /// diff PR nemá načíst znovu; commit je neměnný, takže by to bylo razítko, které nikdo nečte —
    /// a držený stav, který nikdo nečte, svádí k tomu se na něj spolehnout. Tatáž úvaha jako
    /// u `IncrementalDiff.Content`.
    enum Content: Equatable, Sendable {
        case loading
        case loaded(Diff)
        case failed(String)
    }
}
