import Foundation

/// Co deska potřebuje k tomu, aby uměla říct, jestli vlastní PR jde mergnout (#572) — **jedním
/// dotazem na celou sadu vlastních PR**, ne po jednom při otevření záložky.
///
/// **Dvě věci, ne tři.** Hlavička (`detail`) a slévatelnost (`status`) jsou to jediné, co
/// `Policy.mergeOffer` k rozhodnutí o překážkách potřebuje. Commity v tom schválně nejsou:
/// `Policy.mergeProposal` je bere kvůli **počtu v potvrzení**, který deska nekreslí — a dotáhnout
/// je hromadně by znamenalo druhý zdroj téhož seznamu vedle `fetchCommits(id:)`.
///
/// **Není to druhý model detailu.** `PullRequest` je tentýž typ, který vrací `fetchDetail(id:)`,
/// a skládá ho **tentýž dekodér** (`GhPullRequestDetail`) — `gh pr view --json` je nad GraphQL,
/// takže se jména polí shodují do písmene. Kdyby se hlavička skládala zvlášť, měla by vlastní PR
/// po startu jiná data než po otevření záložky, a to je přesně ten rozdíl, který se v okně nepozná.
struct MergeReadiness: Hashable, Sendable {
    let detail: PullRequest
    let status: BranchStatus
}
