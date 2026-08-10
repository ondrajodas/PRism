import Foundation

/// Kolik je nálezů a kolik z nich blokuje (#242).
///
/// **Jeden zdroj pro tři místa**: odznak na záložce `Nálezy`, souhrn nad tabulkou a bubliny
/// v diffu. Do #242 si počet skládalo každé místo samo (`findings.count` v proužku panelu,
/// `blockingCount(in:)` u řádku seznamu) a přesně tak se dvě čísla o téže věci rozejdou — odznak
/// by tvrdil pět a v tabulce by byly čtyři řádky.
struct FindingsTally: Hashable, Sendable {
    /// Kolik nálezů je vidět — **včetně odmítnutých**, protože ty se v tabulce ztlumí, nezmizí.
    let total: Int
    /// Kolik z **platných** blokuje. Odmítnutý blokující nález se nepočítá: PR na něm právě proto
    /// nestojí.
    let blocking: Int
    let dismissed: Int

    var isEmpty: Bool { total == 0 }
}

extension Policy {
    /// Součty nad nálezy, které jsou vidět (tedy po filtru reviewerů).
    ///
    /// Bere `[Finding]` a mapu odmítnutí, ne `ReviewRecord`: filtr reviewerů je pohled, takže
    /// záznam o něm neví — a odznak má počítat to, co je na obrazovce.
    static func tally(
        of findings: [Finding],
        dismissals: [FindingKey: FindingDismissal] = [:],
        categories: Set<String> = defaultBlockingCategories
    ) -> FindingsTally {
        var blocking = 0
        var dismissed = 0
        for finding in findings {
            if dismissals[key(of: finding)] != nil {
                dismissed += 1
            } else if isBlocking(finding, categories: categories) {
                blocking += 1
            }
        }
        return FindingsTally(total: findings.count, blocking: blocking, dismissed: dismissed)
    }

    /// Odznak na záložku `Nálezy`. `nil` = není co hlásit; nula by tvrdila, že se počítalo
    /// a vyšlo prázdno, což je jiné tvrzení než „nálezy nejsou“.
    static func findingsBadge(of tally: FindingsTally) -> PullRequestTabBadge? {
        guard !tally.isEmpty else { return nil }
        return tally.blocking > 0 ? .blocking(tally.total) : .count(tally.total)
    }
}
