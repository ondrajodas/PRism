import Foundation

extension Policy {
    /// Repozitáře, o kterých aplikace ví — seznam, ze kterého vybírá okno nastavení.
    ///
    /// Spojuje dvě sady, protože ani jedna sama nestačí. V posledním seznamu PR jsou repa,
    /// pro která se nastavení teprve dělá; v konfiguraci ta, na která zrovna žádné PR
    /// nečeká. Kdyby se braly jen PR, zmizelo by z okna nastavení, které dál platí — a to
    /// je horší než řádek navíc, protože se pak nedá vypnout.
    static func knownRepositories(
        in pullRequests: [PullRequestSummary],
        configuration: Configuration
    ) -> [RepoID] {
        var known = Set(pullRequests.map(\.repo))
        known.formUnion(configuration.repositories.keys)
        return known.sorted(by: shouldPrecede)
    }

    /// Podle jména, bez ohledu na velikost písmen. Množina ani slovník pořadí nemají, takže
    /// bez řazení by seznam mezi překresleními poskakoval; druhé kritérium ho dodělává do
    /// úplného, aby se dvě jména lišící se jen velikostí písmen neprohazovala.
    private static func shouldPrecede(_ left: RepoID, _ right: RepoID) -> Bool {
        let byName = left.description.caseInsensitiveCompare(right.description)
        if byName != .orderedSame { return byName == .orderedAscending }
        return left.description < right.description
    }
}
