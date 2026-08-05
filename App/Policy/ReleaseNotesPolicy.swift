import Foundation

extension Policy {
    /// Vydání od nejnovějšího.
    ///
    /// Řadí se **tady, ne v gateway** a nespoléhá se na pořadí, ve kterém je vrátí GitHub:
    /// „co je nejnovější“ je otázka, na které stojí značka naposledy viděného vydání
    /// i výchozí výběr v okně, takže odpověď na ni má být vidět v jedné čisté funkci.
    ///
    /// Řadí se podle **data vydání**, ne podle tagu. Verze v tomhle repu jde nahoru
    /// (`v0.<milník>.<pořadí>`, pak `v1.x`), takže by to zatím vyšlo stejně — ale porovnávat
    /// tagy znamená rozumět schématu verzí, a to je druhé pravidlo navíc k tomu, které už
    /// v `CLAUDE.md` je. Datum je pravda z GitHubu.
    ///
    /// Druhé kritérium je tag: dvě vydání se stejným časem jsou nepravděpodobná, ale bez něj
    /// by mezi překresleními poskakovala — tatáž úvaha jako u řazení PR.
    static func sortedReleases(_ releases: [Release]) -> [Release] {
        releases.sorted { left, right in
            if left.publishedAt != right.publishedAt { return left.publishedAt > right.publishedAt }
            return left.tag > right.tag
        }
    }

    /// Vydání, která jsou novější než to, co si aplikace naposledy poznamenala jako viděné.
    ///
    /// Značka je **tag**, ne datum — aplikace neví, kolikátá je (`MARKETING_VERSION` je pořád
    /// `0.1` a tagy nikdy nesledoval), takže se poslední viděné vydání musí pamatovat samo.
    ///
    /// **Když značka v seznamu není, nové není nic.** Vydání se dá na GitHubu smazat nebo
    /// přetagovat, a v takové chvíli se „co jsem od té doby propásl“ poctivě říct nedá.
    /// Vrátit celou historii je z těch dvou možností ta dražší: okno by po jednom smazaném
    /// releasu zařvalo devětašedesáti novinkami. Přijít o jedno ohlášení je levnější — a je to
    /// tatáž úvaha jako u prvního spuštění, které mlčí ze stejného důvodu (#85).
    static func newReleases(in releases: [Release], since seenTag: String) -> [Release] {
        let sorted = sortedReleases(releases)
        guard let mark = sorted.firstIndex(where: { $0.tag == seenTag }) else { return [] }
        return Array(sorted.prefix(upTo: mark))
    }
}
