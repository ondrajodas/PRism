import Foundation
import Testing

@testable import PRism

/// Zkrácení toho, co se o nástroji ukáže v tabu Průběh.
///
/// Reviewer běží v pracovním stromě, takže **každá** cesta začíná stejnými sedmdesáti
/// znaky cache — a v ose z nich není poznat nic.
@Suite("ToolAttempt — zkrácení")
struct ToolAttemptTests {
    private let worktree = URL(filePath: "/Users/x/Library/Application Support/PRism/worktrees/keboola/job-queue/725-c66a21")

    /// Skutečný nástroj dostane cestu **nekódovanou** — `path()` by ji procentoval
    /// a test by pak ověřoval vstup, který nikdy nevznikne.
    private var path: String { worktree.path(percentEncoded: false) }

    private func attempt(_ name: String, _ detail: String) -> ToolAttempt {
        ToolAttempt(name: name, detail: detail)
    }

    @Test("Cesta v pracovním stromě se zkrátí na relativní")
    func makesPathsRelativeToTheWorktree() {
        let read = attempt("Read", path + "/libs/api/src/PlainJob.php")

        #expect(read.shortened(inside: worktree) == "libs/api/src/PlainJob.php")
    }

    /// `cd <strom> && …` je nejčastější tvar příkazu a je na každém řádku stejný.
    @Test("Úvodní cd do pracovního stromu se zahodí")
    func dropsTheLeadingChangeDirectory() {
        let bash = attempt("Bash", "cd \"\(path)\" && sed -n 260,300p libs/api/src/PlainJob.php")

        #expect(bash.shortened(inside: worktree) == "sed -n 260,300p libs/api/src/PlainJob.php")
    }

    @Test("Cesta uvnitř příkazu se zkrátí taky")
    func makesPathsInsideACommandRelative() {
        let bash = attempt("Bash", "grep -rn \"delay\" \(path)/apps/api")

        #expect(bash.shortened(inside: worktree) == "grep -rn \"delay\" apps/api")
    }

    @Test("Co se stromem nesouvisí, zůstane beze změny")
    func leavesUnrelatedDetailAlone() {
        #expect(attempt("Grep", "TODO").shortened(inside: worktree) == "TODO")
    }

    @Test("Bez stromu se nic nezkracuje")
    func changesNothingWithoutAWorktree() {
        let path = "/jinde/App/Main.swift"

        #expect(attempt("Read", path).shortened(inside: nil) == path)
    }

    @Test("Nástroj bez detailu detail nedostane")
    func keepsAMissingDetailMissing() {
        #expect(ToolAttempt(name: "Read", detail: nil).shortened(inside: worktree) == nil)
    }

    /// Cesty se zkracují od začátku (zajímavé je jméno souboru), příkazy od konce
    /// (zajímavé je, co se spouští).
    @Test("Cesta a příkaz se ořezávají z jiné strany")
    func trimsPathsAndCommandsFromDifferentEnds() {
        #expect(attempt("Read", "a/b.php").keepsTail)
        #expect(attempt("Bash", "grep x").keepsTail == false)
        #expect(attempt("Grep", "TODO").keepsTail == false)
    }
}
