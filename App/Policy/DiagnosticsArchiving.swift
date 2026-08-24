import Foundation

extension Policy {
    /// Kolik záznamů se vedle aktivního drží — **počet** (#412).
    ///
    /// Dvě meze, každá na jinou poruchu: bez počtu by se cache zaplnila stovkami skoro prázdných
    /// souborů (jedno spuštění se zapnutou diagnostikou = jeden záznam, a `bin/run.sh` běží po
    /// každém mergi), bez bajtů by dvacet plných souborů zabralo 160 MB.
    ///
    /// Dvacet je z měření, ne od oka: restartuje se **šestkrát denně**, takže dvacet záznamů je
    /// přes tři dny historie — a u #361 se čte zpětně, v pátek to byl záznam dva dny starý.
    static let diagnosticsArchiveFiles = 20

    /// Kolik smí zabrat **všechny** uložené záznamy dohromady (#412). 64 MB je osm plných sezení;
    /// běžné sezení má řádově megabajt (změřeno 986 kB za 11,5 h se třemi restarty).
    static let diagnosticsArchiveBytes = 64 * 1024 * 1024

    /// Kolik různých jmen se smí zkusit, než se rotace vzdá. Kolize znamená dvě rotace v jedné
    /// sekundě nad souborem s týmž časem posledního zápisu — praktiky nemožné, ale jméno se nesmí
    /// vybrat tak, že se jím přepíše cizí záznam.
    static let diagnosticsArchiveNameAttempts = 100

    /// Jméno, pod kterým se dosavadní záznam uloží vedle aktivního (#412).
    ///
    /// **`do-<čas posledního zápisu>`, ne `<čas rotace>`**: sezení, které skončilo v pátek ráno, má
    /// mít v názvu pátek i tehdy, když se aplikace spustí v pondělí — jinak by jméno tvrdilo něco
    /// o obsahu, co v souboru není. Je to tatáž úvaha jako u `diagnostics-do-2026-08-22.log`, což
    /// je jméno, které si člověk u #412 vyrobil rukou; tohle ho jen dělá samo a se sekundami,
    /// protože se za den restartuje víckrát.
    ///
    /// **Bez dvojtečky a bez posunu pásma.** Dvojtečka je v cestách na macOS zrádná (Finder ji
    /// kreslí jako `/`), a posun pásma je na **každém řádku uvnitř** souboru — jméno slouží
    /// k tomu, aby se soubor našel a dal seřadit, ne k počítání s časem. Formát je proto
    /// `yyyy-MM-dd'T'HH-mm-ss` s POSIX locale, ať jméno nezávisí na nastavení stroje.
    ///
    /// `attempt` je pojistka na kolizi: nultý pokus je jméno bez přípony, další nesou `-2`, `-3`.
    static func diagnosticsArchiveName(upTo lastWrite: Date, in zone: TimeZone, attempt: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
        return "\(diagnosticsArchivePrefix)\(formatter.string(from: lastWrite))\(suffix).log"
    }

    /// Je to jméno uloženého záznamu? Rozhoduje o tom, na co se smí sáhnout při úklidu — v kořeni
    /// cache leží i nálezy, drafty a `sessions.json`, takže se maže **jedině podle tohohle vzoru**.
    static func isDiagnosticsArchive(_ name: String) -> Bool {
        name.hasPrefix(diagnosticsArchivePrefix) && name.hasSuffix(".log")
    }

    static let diagnosticsArchivePrefix = "diagnostics-do-"

    /// Které uložené záznamy jdou pryč, aby obě meze platily (#412). Vrací je **od nejstaršího**.
    ///
    /// **Nejnovější se nemaže nikdy**, ani když sám přeteče bajtovou mez. Rotace, která zahodí to,
    /// co právě uložila, je u #361 horší než strop — ten aspoň nechá v souboru napsáno, co se
    /// stalo.
    ///
    /// Řadí se podle času zápisu, při shodě podle jména: jméno nese čas, takže shoda znamená dvě
    /// rotace v jedné sekundě, a tam je pořadí jmen jediné, co se dá srovnat.
    static func diagnosticsArchivesToDelete(
        _ archives: [DiagnosticsArchiveEntry],
        keepFiles: Int = diagnosticsArchiveFiles,
        keepBytes: Int = diagnosticsArchiveBytes
    ) -> [DiagnosticsArchiveEntry] {
        let newestFirst = archives.sorted {
            $0.modified == $1.modified ? $0.name > $1.name : $0.modified > $1.modified
        }
        var kept = 0
        var bytes = 0
        var doomed: [DiagnosticsArchiveEntry] = []
        for entry in newestFirst {
            let fits = kept < keepFiles && bytes + entry.bytes <= keepBytes
            if kept == 0 || fits {
                kept += 1
                bytes += entry.bytes
            } else {
                doomed.append(entry)
            }
        }
        return doomed.reversed()
    }

    /// Co rotace udělala — **do záznamu**, ne jen na stderr (#412).
    ///
    /// Je to tatáž úvaha jako u limitního řádku: záznam, který začíná od nuly, se nedá odlišit od
    /// aplikace, která si předchozí sezení nepamatuje. Z těchhle řádků se pozná, **kde je zbytek**
    /// a co se cestou smazalo, takže se historie neztrácí potichu.
    ///
    /// Když se nerotovalo (první sezení nad prázdnou cache), nevrací se **nic** — prázdný soubor
    /// není událost.
    static func diagnosticsRotationLines(
        _ rotation: DiagnosticsRotation,
        at moment: Date,
        in zone: TimeZone
    ) -> [String] {
        var lines: [String] = []
        if let archived = rotation.archived {
            lines.append("\(stamp(of: moment, in: zone)) předchozí záznam"
                + " (\(rotation.archivedBytes) B) uložen jako \(archived)")
        }
        if !rotation.deleted.isEmpty {
            lines.append("\(stamp(of: moment, in: zone)) smazáno \(rotation.deleted.count)"
                + " nejstarších záznamů (\(rotation.deletedBytes) B, drží se nejvýš"
                + " \(diagnosticsArchiveFiles) souborů a \(diagnosticsArchiveBytes) B):"
                + " \(diagnosticsDeletedNames(rotation.deleted))")
        }
        // Nepovedená rotace je **taky řádek v záznamu**, ne ticho: sezení, které píše do souboru po
        // předchůdci, má jinak dlouhý zbytek stropu, a to je potřeba vidět u čtení, ne dohadovat.
        for problem in rotation.problems {
            lines.append("\(stamp(of: moment, in: zone)) rotace záznamu se nepovedla: \(problem)")
        }
        return lines
    }

    /// Kolik smazaných jmen se do řádku vypíše, než se zbytek přizná počtem. Šest jako u histogramu
    /// zásobníku (#397) a ze stejného důvodu: zamlčený zbytek by z výčtu udělal tvrzení, které
    /// neplatí.
    static let diagnosticsDeletedNameLimit = 6

    private static func diagnosticsDeletedNames(_ names: [String]) -> String {
        guard names.count > diagnosticsDeletedNameLimit else { return names.joined(separator: " ") }
        let shown = names.prefix(diagnosticsDeletedNameLimit).joined(separator: " ")
        return "\(shown) +\(names.count - diagnosticsDeletedNameLimit) dalších"
    }
}
