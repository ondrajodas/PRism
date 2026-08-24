import Foundation

/// Jeden uložený záznam diagnostiky vedle toho aktivního (#412) — jméno, velikost a čas zápisu.
///
/// Čas se bere ze souboru, ne ze jména: jméno se dá přejmenovat rukou (u #412 se to tak dělalo),
/// takže by řazení podle něj mazalo podle toho, jak si kdo soubor pojmenoval.
struct DiagnosticsArchiveEntry: Equatable {
    let name: String
    let bytes: Int
    let modified: Date
}

/// Co rotace udělala — **materiál pro záznam**, ne návratový kód (#412).
///
/// Sezení si ho nechá napsat do svého souboru (`Policy.diagnosticsRotationLines`), protože soubor,
/// který začíná od nuly, se jinak nedá odlišit od aplikace, která o předchozím sezení neví.
struct DiagnosticsRotation: Equatable {
    /// Jméno, pod kterým leží dosavadní záznam. `nil` = nerotovalo se, protože nebylo co uložit.
    var archived: String?
    var archivedBytes = 0
    /// Jména smazaných záznamů, **od nejstaršího**.
    var deleted: [String] = []
    var deletedBytes = 0
    /// Co se nepovedlo. Píše se to do záznamu stejně jako úspěch — `try?` by z rotace udělal
    /// operaci, o které se nedá zjistit, jestli proběhla.
    var problems: [String] = []

    static let none = DiagnosticsRotation()
}

/// Uložení dosavadního záznamu diagnostiky vedle a úklid starých (#412).
///
/// **Proč rotace, a ne strop účtovaný na sezení.** Do #412 platil strop 8 MB na **soubor**, do
/// kterého se přípisovalo napříč sezeními — takže první sezení mělo 8 MB, druhé zbytek a n-té
/// prakticky nic. Naměřeno v provozu: záznam narazil na strop ve 4:01 ráno a dalších **42 hodin**
/// aplikace běžela bez záznamu; při restartu ve 12:34 hlásil `bin/run.sh` 4 859 815 B, tedy 3,5 MB
/// na celé sezení. Strop účtovaný na sezení by ten problém taky vyřešil, ale nechal by v cache jeden
/// soubor, který roste bez meze — a mez, která se dá porušit tím, že se aplikace restartuje, není
/// mez. Rotace dává obojí: **sezení má svoje okno** a cache má **vyjmenovaný** strop na počet
/// souborů i na bajty.
///
/// **Historie se nezahazuje.** U #361 se záznam čte zpětně (v pátek to byl soubor dva dny starý),
/// takže rotace, která nechá jen ten poslední, je horší než strop. Drží se proto
/// `Policy.diagnosticsArchiveFiles` souborů a `Policy.diagnosticsArchiveBytes` bajtů a **nejnovější
/// se nemaže nikdy** — viz `Policy.diagnosticsArchivesToDelete`.
///
/// **Maže se jedině podle vzoru jména** (`Policy.isDiagnosticsArchive`). V kořeni cache leží
/// i nálezy, drafty, `sessions.json` a `activity.json`; úklid, který by šel podle času nebo podle
/// přípony, by sáhl na ně. Je to tatáž ochrana jako u `CacheEviction` — mazání se drží u jednoho
/// pravidla, které je vidět.
struct DiagnosticsArchive {
    /// Aktivní záznam, tedy ten, do kterého sezení zapisuje.
    let url: URL
    var keepFiles = Policy.diagnosticsArchiveFiles
    var keepBytes = Policy.diagnosticsArchiveBytes
    /// Pásmo pro jméno souboru. Předává se ze stejného důvodu jako u řádků — jinak by se jméno
    /// v testu nedalo napsat literálem.
    var zone: TimeZone = .current

    private var directory: URL { url.deletingLastPathComponent() }

    /// Uloží dosavadní záznam vedle a uklidí staré. Volá se **jednou za sezení, dřív než se do
    /// souboru cokoli napíše** — proto to dělá `DiagnosticsLog` u otevírání souboru, ne volající.
    ///
    /// **Žádné hodiny to nepotřebuje**, a to je záměr: jméno se skládá z času, kdy se do souboru
    /// zapsalo naposled, takže „kdy je teď“ nemá na výsledek vliv. Razítko u řádků do záznamu si
    /// bere volající.
    func rotate() -> DiagnosticsRotation {
        var report = DiagnosticsRotation.none
        archiveCurrent(into: &report)
        prune(into: &report)
        return report
    }

    /// Přesune aktivní záznam pod jméno s časem jeho posledního zápisu.
    ///
    /// **Prázdný ani chybějící soubor se nearchivuje**: záznam bez jediného řádku není historie,
    /// jen by se v cache hromadily nuly po každém spuštění bez `--diagnose`. Chybějící soubor je
    /// přitom normální stav, kdežto soubor, který **existuje a nedá se přečíst**, je porucha —
    /// sezení pak píše do něj a má jinak dlouhý zbytek stropu, takže se to musí do záznamu napsat.
    private func archiveCurrent(into report: inout DiagnosticsRotation) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let current = attributes(of: url) else {
            report.problems.append("\(url.lastPathComponent) není obyčejný soubor nebo ho nejde"
                + " přečíst, píše se dál do něj")
            return
        }
        guard current.bytes > 0 else { return }
        guard let name = freeName(upTo: current.modified) else {
            report.problems.append("volné jméno pro dosavadní záznam se nenašlo ani na"
                + " \(Policy.diagnosticsArchiveNameAttempts). pokus, píše se dál do"
                + " \(url.lastPathComponent)")
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: directory.appending(path: name))
            report.archived = name
            report.archivedBytes = current.bytes
        } catch {
            report.problems.append("\(url.lastPathComponent) nejde uložit jako \(name) — \(error)")
        }
    }

    /// Smaže to, co se nad meze nevejde. **Nejstarší první**, aby po částečném selhání zbylo to
    /// novější.
    private func prune(into report: inout DiagnosticsRotation) {
        let doomed = Policy.diagnosticsArchivesToDelete(
            entries(into: &report),
            keepFiles: keepFiles,
            keepBytes: keepBytes
        )
        for entry in doomed {
            do {
                try FileManager.default.removeItem(at: directory.appending(path: entry.name))
                report.deleted.append(entry.name)
                report.deletedBytes += entry.bytes
            } catch {
                report.problems.append("\(entry.name) nejde smazat — \(error)")
            }
        }
    }

    /// Uložené záznamy ve složce. **Co není obyčejný soubor nebo se nedá přečíst, se do výčtu
    /// nedostane** — a tím to úklid nesmaže: `removeItem` nad složkou smaže celý podstrom, takže
    /// položka pojmenovaná jako záznam, která je složkou, je ta nejhorší věc, kterou by úklid mohl
    /// najít. Řekne se to do záznamu.
    ///
    /// **Hranici cache tady nehlídá nic dalšího, a je to schválně.** `CacheEviction` a `ReviewStore`
    /// mají `CacheLayout.contains(_:)` proto, že mažou **rekurzivně podle toho, co našly na disku**;
    /// tady jsou to plochá jména z jednoho `contentsOfDirectory`, takže se mazání z té složky nemá
    /// kudy dostat jinam. Symlink v položce je navíc neškodný — `removeItem` smaže odkaz, ne to, kam
    /// ukazuje.
    private func entries(into report: inout DiagnosticsRotation) -> [DiagnosticsArchiveEntry] {
        let manager = FileManager.default
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: directory.path)
        } catch {
            // Chybějící složka je normální stav před prvním sezením, ne porucha. Cokoli jiného ale
            // znamená, že se **neuklízí** — a to se nesmí stát potichu.
            if manager.fileExists(atPath: directory.path) {
                report.problems.append("uložené záznamy ve \(directory.lastPathComponent)"
                    + " nejde vypsat, neuklízí se — \(error)")
            }
            return []
        }
        var found: [DiagnosticsArchiveEntry] = []
        for name in names where Policy.isDiagnosticsArchive(name) {
            guard let file = attributes(of: directory.appending(path: name)) else {
                report.problems.append("\(name) není obyčejný soubor nebo ho nejde přečíst,"
                    + " do úklidu se nepočítá")
                continue
            }
            found.append(
                DiagnosticsArchiveEntry(name: name, bytes: file.bytes, modified: file.modified)
            )
        }
        return found
    }

    /// První jméno, na kterém ve složce nic neleží. Kolize znamená dvě rotace nad souborem s týmž
    /// časem posledního zápisu; přepsat cizí záznam se nesmí, takže se radši vzdá.
    private func freeName(upTo lastWrite: Date) -> String? {
        for attempt in 0..<Policy.diagnosticsArchiveNameAttempts {
            let name = Policy.diagnosticsArchiveName(upTo: lastWrite, in: zone, attempt: attempt)
            if !FileManager.default.fileExists(atPath: directory.appending(path: name).path) {
                return name
            }
        }
        return nil
    }

    /// Velikost a čas zápisu — **jedině u obyčejného souboru**. `nil` u složky je to, co drží úklid
    /// od `removeItem` nad podstromem, a u aktivního záznamu to znamená, že se nearchivuje.
    private func attributes(of file: URL) -> (bytes: Int, modified: Date)? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let values = try? file.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              let bytes = values.fileSize,
              let modified = values.contentModificationDate
        else { return nil }
        return (bytes, modified)
    }
}
