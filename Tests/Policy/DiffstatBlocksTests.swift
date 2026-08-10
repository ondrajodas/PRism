import Testing

@testable import PRism

/// Čtverečky poměru změny za `+X −Y` (#218).
///
/// Čistá funkce, takže výčtem — a je to jediné místo, kde se z čísel rozhoduje o obrázku.
@Suite("Poměr změny v čtverečcích")
struct DiffstatBlocksTests {
    /// Ukázka z návrhu: `+248 −96` → tři zelené, jeden červený, jeden šedý.
    @Test("Poměr z návrhu vyjde na 3 : 1 a jeden zbývá")
    func matchesTheDesign() {
        #expect(Policy.diffstatBlocks(additions: 248, deletions: 96) == [
            .added, .added, .added, .removed, .neither
        ])
    }

    /// Zaokrouhlení **dolů** je to jediné, které nelže: nahoru by z jednoho odebraného řádku
    /// ve dvousetřádkovém PR udělalo celý čtvereček, tedy pětinu změny.
    @Test("Jeden odebraný řádek proti dvěma stům nedostane vlastní čtvereček")
    func roundsDown() {
        #expect(Policy.diffstatBlocks(additions: 200, deletions: 1) == [
            .added, .added, .added, .added, .neither
        ])
    }

    @Test("Samé přidávání zabere všech pět")
    func fillsUpOnAdditionsOnly() {
        #expect(Policy.diffstatBlocks(additions: 40, deletions: 0)
            == Array(repeating: .added, count: 5))
    }

    @Test("Samé mazání zabere všech pět")
    func fillsUpOnDeletionsOnly() {
        #expect(Policy.diffstatBlocks(additions: 0, deletions: 40)
            == Array(repeating: .removed, count: 5))
    }

    /// Nastane u čistého přesunu — a je to poctivé: ani jedna strana nemá většinu.
    @Test("Přesně půl na půl nechá prostřední čtvereček šedý")
    func leavesTheMiddleOnAnEvenSplit() {
        #expect(Policy.diffstatBlocks(additions: 50, deletions: 50) == [
            .added, .added, .removed, .removed, .neither
        ])
    }

    /// **Ne pět šedých.** Pruh, který vypadá pořád stejně, nic neříká — a `+0 −0` vedle něj
    /// to řekne líp.
    @Test("Prázdný diff nedá žádný čtvereček")
    func drawsNothingForAnEmptyDiff() {
        #expect(Policy.diffstatBlocks(additions: 0, deletions: 0).isEmpty)
    }

    /// Záporné počty do modelu nepatří, ale spadnout se na nich nesmí: `Array(repeating:)`
    /// se zápornou délkou je pád, ne prázdné pole.
    @Test("Nesmyslná čísla nezpůsobí pád")
    func survivesNonsense() {
        #expect(Policy.diffstatBlocks(additions: -3, deletions: -8).isEmpty)
        #expect(Policy.diffstatBlocks(additions: 10, deletions: -8)
            == Array(repeating: .added, count: 5))
    }

    @Test("Součet je vždycky přesně pět")
    func alwaysAddsUpToFive() {
        for additions in 0...20 {
            for deletions in 0...20 where additions + deletions > 0 {
                let blocks = Policy.diffstatBlocks(additions: additions, deletions: deletions)
                #expect(blocks.count == 5, "\(additions)/\(deletions)")
            }
        }
    }
}
