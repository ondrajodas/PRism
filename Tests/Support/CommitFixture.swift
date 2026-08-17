import Foundation
import Testing

@testable import PRism

/// Commity ze fixture `gh/pr-commits*.json` — **jedno místo, kde se ta odpověď dekóduje** (#339).
///
/// Existuje proto, že tutéž fixture čtou tři na sobě nezávislá místa: dekódování (`GhCommitTests`),
/// počet řádků těla zprávy (`CommitDiffTabStateTests`) a sonda (`CommitsTabRenderProbe`). Tři kopie
/// téhož `decode` by se rozešly zrovna v tom, na čem #339 stojí — stačilo by, aby si jedna z nich
/// zakončení řádků „pro pořádek“ znormalizovala, a sada by pak zeleně tvrdila něco o `CRLF`, které
/// v datech není.
///
/// Čte se přes `Fixture.data`, ne `Fixture.text`: dekodér chce `Data` a mezikrok přes `String` je
/// jen místo, kde se dá text potichu upravit.
enum CommitFixture {
    static func commits(_ relativePath: String) throws -> [PullRequestCommit] {
        try GhOutput.decoder
            .decode([GhCommit].self, from: Fixture.data(relativePath))
            .compactMap(\.pullRequestCommit)
    }

    /// Commit `415ab35` z `git-for-windows/git#6293` — **míchaná zakončení** (titulek `LF`, tělo
    /// `CRLF`), tedy to, na čem #339 stojí.
    static func crlfCommit() throws -> PullRequestCommit {
        try #require(commits("gh/pr-commits-crlf.json").first)
    }
}
