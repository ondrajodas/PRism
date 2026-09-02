import Foundation

/// Změny jednoho souboru.
struct FileDiff: Hashable, Sendable, Identifiable {
    enum Change: Hashable, Sendable {
        case added
        case deleted
        case modified
        case renamed
    }

    /// `nil` u nově přidaného souboru.
    let oldPath: String?
    /// `nil` u smazaného souboru.
    let newPath: String?
    let change: Change
    /// Binárka nemá hunky — `gh pr diff` u ní pošle jen `Binary files … differ`.
    let isBinary: Bool
    let hunks: [DiffHunk]

    /// Otisk obsahu souboru v tomhle diffu — sha z řádky `index <základ>..<hlava>`, doslova
    /// tak, jak ji poslal git (#500). `nil` = diff žádnou takovou řádku neměl.
    ///
    /// **Je to celá dvojice, ne jen hlava**, a je to rozhodnutí: značka `Prošlo` říká „přečetl
    /// jsem **diff** tohohle souboru“, a ten se změní i tehdy, když se posune **základ** —
    /// typicky po rebase nad novým `main`em, který týž soubor taky sáhl. Otisk jedné strany by
    /// takovou změnu neviděl, i když se přečtené řádky přepsaly.
    ///
    /// **`nil` je platná hodnota, ne chyba.** Přejmenování se stoprocentní podobností (`similarity
    /// index 100%`) žádnou `index` řádku nemá, protože se obsah nezměnil — a takový soubor nemá
    /// ani hunky. Porovnává se proto **na rovnost včetně `nil`u**: dvakrát „nevím“ nad souborem,
    /// který se jen přesunul, je pořád tentýž soubor. Rozhoduje `Policy.fileReviewState(mark:blobs:)`.
    ///
    /// Sha je **zkrácená** (git ji zkracuje podle velikosti repa, 7–11 znaků) a v rámci jednoho
    /// repozitáře stabilní, takže se porovnává celá a přesně. Kdyby repo mezitím povyrostlo
    /// natolik, že se zkrácení prodlouží, značka spadne na `změněno od prošlého` — tedy do
    /// bezpečné strany a jedním kliknutím zpátky.
    ///
    /// **`var` s výchozí hodnotou** jen kvůli memberwise initu: diff složený v testu z hunků
    /// otisk nemá a nemá ho odkud vzít.
    var blobs: String?

    /// Odvozené z cest, ne generované: skok na soubor v #20 musí přežít překreslení,
    /// takže identita nesmí vzniknout pokaždé jiná.
    var id: String { "\(oldPath ?? "/dev/null") → \(newPath ?? "/dev/null")" }

    /// Pod jakým jménem soubor v okně vystupuje — po přejmenování pod novým.
    var displayPath: String { newPath ?? oldPath ?? "?" }

    /// Je tenhle řádek nového souboru v některém hunku? Podle toho se pozná nález, ke
    /// kterému se musí kód teprve dotáhnout.
    func showsLine(_ line: Int) -> Bool {
        hunks.contains { hunk in hunk.lines.contains { $0.newNumber == line } }
    }

    var additions: Int { count(of: .added) }
    var deletions: Int { count(of: .removed) }

    private func count(of kind: DiffLine.Kind) -> Int {
        var total = 0
        for hunk in hunks {
            total += hunk.lines.count(where: { $0.kind == kind })
        }
        return total
    }
}
