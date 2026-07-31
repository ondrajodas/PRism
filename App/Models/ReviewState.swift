import Foundation

/// Stav review na jednom PR — to, co se ukazuje v řádku seznamu.
///
/// Chybové stavy jsou schválně rozlišené, ne slité do jednoho „nepovedlo se“. `clean`
/// (doběhlo, nic nenašlo) a `failed` (session spadla) říkají opak jedno o druhém;
/// `checkoutFailed` se spraví opakováním clonu, `failed` ne. Když se rozliší tady,
/// nemusí UI hádat.
enum ReviewState: Hashable, Codable, Sendable {
    /// Ještě se nespouštělo — default, dokud se nemáčkne tlačítko.
    case notStarted
    /// Čeká na volný slot v limitu souběžných session.
    case queued
    /// Připravuje se checkout. U neznámého repa je clone reálně citelný, takže má
    /// vlastní stav místo tvářit se, že PR ještě není připravený.
    case cloning
    /// Clone nebo fetch selhal; `detail` je stderr z gitu, na kterém stojí tlačítko opakovat.
    case checkoutFailed(detail: String)
    /// Běží — `finished` z `total` reviewerů je hotovo.
    case running(finished: Int, total: Int)
    /// Doběhlo a nic nenašlo.
    case clean
    /// Doběhlo a nálezy jsou. Kolik z nich blokuje, odvozuje `Policy`, ne tenhle typ.
    case completed(findings: Int)
    /// Session skončila nenulovým kódem; `detail` je uchovaný stderr.
    case failed(detail: String)
    /// Session byla zabita timeoutem. Částečné nálezy se zachovávají.
    case timedOut(findings: Int)
    /// Nálezy patří ke staršímu `headSha`, než jaký PR má teď.
    case stale

    /// Stav doběhlého review podle počtu nálezů.
    ///
    /// Jediné místo, kde vzniká `clean` — jinak by se dřív nebo později objevilo
    /// `completed(findings: 0)`, což je totéž vyjádřené hůř.
    static func finished(findingCount: Int) -> ReviewState {
        findingCount == 0 ? .clean : .completed(findings: findingCount)
    }
}
