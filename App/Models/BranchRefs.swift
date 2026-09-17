import Foundation

/// Větve pull requestu — jak se jmenuje jeho hlava a proti čemu se merguje (#513).
///
/// **Vlastní model vedle `PullRequestHead`, ne pole navíc v shrnutí.** `gh search prs` větve
/// nevrací vůbec (ověřeno na CLI u #513), takže je `PullRequestSummary` mít nemůže — dají se
/// dotáhnout jedině dotazem. Dávkový dotaz na hlavy (#420) je nese od #513 s sebou, protože jde
/// na tentýž uzel a nestojí volání navíc.
///
/// **`isCrossRepository` je součást téže odpovědi schválně.** `headRefName` u pull requestu
/// z forku pojmenovává větev **cizího** repozitáře, takže by se dala shodou jmen spárovat
/// s `baseRefName` někoho úplně jiného. `nil` (nevíme) se proto počítá jako **zákaz, ne
/// povolení** — tatáž škola jako u guardu force pushe (tvrdá podmínka č. 1).
struct BranchRefs: Hashable, Sendable {
    /// Jméno větve, na které PR stojí (`headRefName`).
    let head: String
    /// Jméno větve, do které se merguje (`baseRefName`).
    let base: String
    /// Je hlava větev jiného repozitáře (fork)? `nil` = nevíme.
    var isCrossRepository: Bool?

    /// Smí se tahle hlava brát jako větev **tohohle** repozitáře, tedy jako možný základ série?
    ///
    /// Vlastnost, ne `if` u volajícího: ptá se na ni `Policy.series(in:refs:)` a bude se na ni ptát
    /// každý další, kdo by chtěl větve párovat — dvě různá čtení `nil`u by znamenala dvě odpovědi
    /// na jednu otázku.
    var livesInBaseRepository: Bool { isCrossRepository == false }
}

extension BranchRefs {
    /// Větve z **načteného detailu** (`gh pr view`). Druhá cesta k téže hodnotě, ne druhá pravda:
    /// detail se dotahuje u otevřené záložky a u vlastních PR (#572), kdežto rozhlídka po hlavách
    /// pokrývá frontu — a kdo se ptá, ptá se `AppStore.branchRefs(for:)`, ne jednoho z těch dvou.
    ///
    /// `nil` u prázdných jmen: `PullRequest` je má jako `String` s prázdnou výchozí hodnotou
    /// (starší uložené odpovědi je nemají), a prázdné jméno větve je „nevíme“, ne větev.
    init?(_ detail: PullRequest) {
        guard !detail.headRef.isEmpty, !detail.baseRef.isEmpty else { return nil }
        self.init(head: detail.headRef, base: detail.baseRef, isCrossRepository: detail.isCrossRepository)
    }
}
