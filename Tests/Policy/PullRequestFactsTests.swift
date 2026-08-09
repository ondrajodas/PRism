import Foundation
import Testing

@testable import PRism

/// Dlaždice s fakty o PR (#198). Čistá funkce, takže výčtem.
///
/// Co se dá pokazit potichu: **nakreslit dlaždici s nulou**. Řádek plný nul je řádek, ve kterém
/// se ztratí to jedno číslo, na kterém záleží — a nula u souborů navíc tvrdí, že PR nic nemění,
/// i když se diff jen ještě nenačetl.
@Suite("Fakta o PR")
struct PullRequestFactsTests {
    private func facts(
        commits: Int = 0,
        areCommitsExact: Bool = true,
        newCommits: Int = 0,
        files: Int = 0,
        filesWithFindings: Int = 0,
        head: String? = nil,
        findingsHead: String? = nil
    ) -> PullRequestFacts {
        Policy.facts(
            commits: commits,
            newCommits: newCommits,
            files: files,
            filesWithFindings: filesWithFindings,
            areCommitsExact: areCommitsExact,
            headSha: head,
            findingsHeadSha: findingsHead
        )
    }

    @Test("Bez dat se nekreslí nic")
    func drawsNothingWithoutData() {
        #expect(facts().isEmpty)
    }

    @Test("Commity a soubory dají dlaždice s dovětkem")
    func showsCountsWithNotes() {
        let tiles = facts(commits: 12, newCommits: 3, files: 7, filesWithFindings: 2).tiles

        #expect(tiles.map(\.caption) == ["Commity", "Soubory"])
        #expect(tiles[0].value == "12")
        #expect(tiles[0].note == "3 nové")
        #expect(tiles[1].note == "2 s nálezem")
    }

    /// Dovětek se píše, **jen když je co říct**: „0 nových“ je řádek navíc, ze kterého nic
    /// neplyne.
    @Test("Nula v dovětku se nepíše")
    func leavesOutAnEmptyNote() {
        let tiles = facts(commits: 12, files: 7).tiles

        #expect(tiles.allSatisfy { $0.note == nil })
    }

    /// Utnutá stránka událostí znamená, že přesný počet **neznáme** — a menší číslo vydávané
    /// za úplné je horší než žádná dlaždice. Nález Copilota na #198.
    @Test("Neúplný počet commitů se nekreslí")
    func hidesAnInexactCommitCount() {
        #expect(facts(commits: 12, areCommitsExact: false).isEmpty)
    }

    /// Bez načtené hlavy není s čím se rozejít — dlaždice `Nálezy proti` by visela sama.
    @Test("Sha nálezů bez hlavy se nekreslí")
    func hidesTheFindingsShaWithoutAHead() {
        #expect(facts(findingsHead: "4f2ac91").isEmpty)
    }

    @Test("Sha se krátí na sedm znaků a sází mono")
    func shortensTheSha() {
        let tiles = facts(head: "9c1de02aaaaaaaa").tiles

        #expect(tiles.map(\.value) == ["9c1de02"])
        #expect(tiles[0].isMonospaced)
    }

    /// **Nejcennější test téhle sady.** Shodná sha nálezů je údaj, který nikoho nezajímá;
    /// rozešlá je důvod, proč nálezy neplatí (tvrdá podmínka č. 5).
    @Test("Sha nálezů se ukáže jen při rozchodu s hlavou")
    func showsTheFindingsShaOnlyWhenItDiffers() {
        let same = facts(head: "9c1de02", findingsHead: "9c1de02").tiles
        let different = facts(head: "9c1de02", findingsHead: "4f2ac91").tiles

        #expect(same.map(\.caption) == ["Hlava"])
        #expect(different.map(\.caption) == ["Hlava", "Nálezy proti"])
        #expect(different[1].isStale)
    }
}
