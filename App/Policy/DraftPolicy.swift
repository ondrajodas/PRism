import Foundation

/// Rozhodování nad rozdělaným review. Čisté funkce, žádné I/O.
extension Policy {
    /// Ke které straně diffu by šel komentář na tomhle řádku — `nil` znamená „nedá se
    /// komentovat“.
    ///
    /// Pravidla jsou GitHubova, ověřená u #62 na živém API:
    /// - **řádek uvnitř hunku** komentovat jde, a to i **kontextový** (nezměněný);
    /// - **řádek mimo hunky** GitHub odmítne (`422 Line could not be resolved`) — a odmítne
    ///   s ním **celé** review, takže se to nesmí zkoušet naslepo;
    /// - `meta` řádek (`\ No newline at end of file`) není obsah souboru, takže nikdy.
    ///
    /// Strana se řídí druhem řádku: přidaný a kontextový patří k nové verzi (`right`, což je
    /// i výchozí strana GitHubu), odebraný ke staré (`left`). Odebraný řádek totiž v novém
    /// souboru neexistuje a jeho číslo je ze starého — bez správné strany by komentář odešel
    /// na jiný řádek.
    ///
    /// **Rozbalený kontext (#47) komentovat nejde.** Jsou to řádky, které v diffu nejsou:
    /// dotáhly se ze souboru, aby se nález mimo diff dal přečíst. Pozná se to tím, že řádek
    /// v žádném hunku není — `DiffRow` je skládá jako obyčejný kontext s oběma čísly, takže
    /// ze samotného `DiffLine` to poznat nelze a příslušnost k hunku se musí ověřit.
    static func commentableSide(of line: DiffLine, in file: FileDiff) -> DiffSide? {
        guard let side = side(of: line.kind) else { return nil }
        guard file.hunks.contains(where: { $0.lines.contains(line) }) else { return nil }
        return side
    }

    /// Dá se na tenhle řádek komentovat?
    static func isCommentable(_ line: DiffLine, in file: FileDiff) -> Bool {
        commentableSide(of: line, in: file) != nil
    }

    private static func side(of kind: DiffLine.Kind) -> DiffSide? {
        switch kind {
        case .added, .context: .right
        case .removed: .left
        case .meta: nil
        }
    }

    /// Je draft psaný proti staršímu commitu, než je hlava PR?
    ///
    /// Nový commit draft **nemaže**, jen zablokuje odeslání — vlastní próza nezastarává tak
    /// rychle jako strojové nálezy, takže ji zahodit je dražší než ji nechat s poctivým
    /// příznakem. Přenesení na nový commit řeší #67.
    ///
    /// Odvozuje se, neukládá: na rozdíl od `ReviewRecord.isStale` je hlava PR v tu chvíli
    /// po ruce (aplikace ji má z detailu), takže není důvod držet příznak, který se může
    /// rozejít s pravdou.
    static func isStale(_ draft: ReviewDraft, head headSha: String) -> Bool {
        draft.headSha != headSha
    }

    /// Dá se draft odeslat?
    ///
    /// Musí být z čeho poslat (`!isEmpty`), musí být vybraný verdikt a nesmí být zastaralý.
    /// Chybějící verdikt je vlastní důvod: `event` je v API povinný a hádat ho za člověka
    /// znamená odeslat něco jiného, než chtěl.
    static func isSendable(_ draft: ReviewDraft, head headSha: String) -> Bool {
        !draft.isEmpty && draft.verdict != nil && !isStale(draft, head: headSha)
    }
}
