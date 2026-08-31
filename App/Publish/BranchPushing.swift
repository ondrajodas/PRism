import Foundation

/// **Jediná cesta, kterou aplikace zapisuje do remote** (#466) — a druhá polovina tvrdé podmínky
/// č. 1, která do té doby mluvila jen o GitHub API.
///
/// Do #466 aplikace do remote **nezapisovala vůbec** a `git push` byl výslovně
/// v `--disallowedTools` revieweera. Změnilo se to vědomě, ne obejitím: srovnat vlastní větev,
/// když ujel `main`, je druhá věc, kvůli které se od hotového review odchází do prohlížeče (tou
/// první byl merge, #465). Co z podmínky **zůstává**:
///
/// - **`GitHubGateway` je pořád bez zápisu** a `RepoCheckout` taky — rebase je lokální práce
///   v cache a `RepoCheckout.rebase` nemá čím nic odeslat.
/// - **`grep BranchPushing App/` vyjmenuje všechna místa, odkud se pushuje**: protokol,
///   `GitBranchPush` (implementace) a `BranchPushSubmission` (jediný volající). Všechny leží
///   v `App/Publish/`, tedy tam, kde je i ta druhá cesta ven.
/// - **Protokol má jednu metodu.** `push` a nic jiného: žádné `commit`, žádné `pushTag`, žádné
///   `deleteBranch`. Výčet je krátký schválně — je z něj vidět, co všechno aplikace umí zapsat.
/// - **`--force-with-lease`, nikdy holé `--force`** (viz `GitBranchPush`).
/// - **Cílem smí být jedině hlava vlastního pull requestu**, a posuzuje se to proti **datům pull
///   requestu**, ne proti jménu větve.
/// - **Brána platí**: `PublishScope`, stejná jako u `ReviewPublishing`. Druhý přepínač by byl
///   druhé místo, kde se dá „samo nic neodejde“ porušit.
/// - **Pusher není pole `AppStore`**, stejně jako publisher: vzniká uvnitř té akce, která pushuje,
///   a zaniká s ní. Store si drží jen cestu ke `gitu` a stav (`BranchSyncState`).
///
/// **Zakázané zůstává**: cokoli, co by přepsalo cizí větev (proto lease), push do základní větve
/// (cílem je vždycky `plan.branch`, tedy hlava PR), mazání větví a tagy.
protocol BranchPushing: Sendable {
    /// Pushne větev vlastního pull requestu. **Jediná zápisová metoda tohohle protokolu.**
    ///
    /// Vrací se hlava, kterou remote přijal — tedy to, co se doopravdy stalo, ne to, co se
    /// chtělo. Chyby se **nepolykají**: odmítnutý lease je vlastní případ
    /// (`BranchSyncError.leaseRejected`), protože z něj plyne jiný další krok než z ostatních.
    func push(_ plan: BranchPushPlan) async throws -> String
}
