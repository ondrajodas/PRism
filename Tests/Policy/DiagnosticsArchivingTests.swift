import Foundation
import Testing

@testable import PRism

/// Rotace záznamu diagnostiky kreslení (#412) — jméno, co se maže a co se o tom napíše do záznamu.
///
/// Je to čistá funkce ze stejného důvodu jako řádek úseku: rozhoduje o tom, **co z historie
/// zůstane**, a to se nedá otestovat, když to závisí na hodinách a na obsahu složky.
@Suite("Rotace záznamu diagnostiky (#412)")
struct DiagnosticsArchivingTests {
    private let moment = Date(timeIntervalSince1970: 1_755_600_000)

    /// Jméno nese **čas posledního zápisu**, ne čas rotace: sezení, které skončilo v pátek, má mít
    /// v názvu pátek i tehdy, když se aplikace spustí v pondělí.
    @Test("Jméno je z času posledního zápisu, bez dvojtečky")
    func nameFromLastWrite() {
        #expect(Policy.diagnosticsArchiveName(upTo: moment, in: .gmt)
            == "diagnostics-do-2025-08-19T10-40-00.log")
        // Pásmo se předává, takže se dá napsat literálem — v aplikaci je to místní čas, aby šlo
        // jméno spárovat s řádky uvnitř.
        #expect(Policy.diagnosticsArchiveName(upTo: moment, in: TimeZone(identifier: "Europe/Prague")!)
            == "diagnostics-do-2025-08-19T12-40-00.log")
    }

    /// Kolize je prakticky nemožná (dvě rotace nad souborem s týmž časem zápisu), ale **přepsat cizí
    /// záznam se nesmí** — proto má každý další pokus vlastní jméno.
    @Test("Další pokus o jméno má příponu s číslem")
    func nameCollisionGetsSuffix() {
        #expect(Policy.diagnosticsArchiveName(upTo: moment, in: .gmt, attempt: 1)
            == "diagnostics-do-2025-08-19T10-40-00-2.log")
        #expect(Policy.diagnosticsArchiveName(upTo: moment, in: .gmt, attempt: 9)
            == "diagnostics-do-2025-08-19T10-40-00-10.log")
    }

    /// **Nejcennější případ z téhle trojice: úklid nesmí sáhnout na nic jiného.** V kořeni cache
    /// leží nálezy, drafty, `sessions.json`, `activity.json` i aktivní záznam — mazání se proto drží
    /// jednoho vzoru jména, ne přípony a ne času.
    @Test("Za uložený záznam se počítá jen jméno podle vzoru")
    func onlyArchivesMatch() {
        #expect(Policy.isDiagnosticsArchive("diagnostics-do-2026-08-22T04-01-36.log"))
        // Jméno vyrobené rukou (takhle si ho u #412 člověk odložil) se pořád počítá.
        #expect(Policy.isDiagnosticsArchive("diagnostics-do-2026-08-22.log"))
        #expect(!Policy.isDiagnosticsArchive("diagnostics.log"))
        #expect(!Policy.isDiagnosticsArchive("activity.json"))
        #expect(!Policy.isDiagnosticsArchive("sessions.json"))
        #expect(!Policy.isDiagnosticsArchive("diagnostics-do-2026-08-22T04-01-36.log.bak"))
        #expect(!Policy.isDiagnosticsArchive("interrupted.json"))
    }

    /// Strop na **počet**: co je nad ním, jde pryč od nejstaršího. Bez toho by se cache zaplnila
    /// skoro prázdnými soubory — jedno spuštění se `--diagnose` je jeden záznam.
    @Test("Nad počtem se maže od nejstaršího")
    func countLimitDeletesOldest() {
        let archives = (0..<5).map { index in
            DiagnosticsArchiveEntry(
                name: "diagnostics-do-\(index).log",
                bytes: 100,
                modified: moment.addingTimeInterval(TimeInterval(index) * 60)
            )
        }
        let doomed = Policy.diagnosticsArchivesToDelete(archives, keepFiles: 2, keepBytes: 10_000)
        #expect(doomed.map(\.name) == [
            "diagnostics-do-0.log",
            "diagnostics-do-1.log",
            "diagnostics-do-2.log",
        ])
    }

    /// Strop na **bajty** je druhá mez, na jinou poruchu: dvacet plných souborů by bylo 160 MB.
    @Test("Nad bajty se maže od nejstaršího")
    func byteLimitDeletesOldest() {
        let archives = [
            DiagnosticsArchiveEntry(name: "a.log", bytes: 400, modified: moment),
            DiagnosticsArchiveEntry(name: "b.log", bytes: 400, modified: moment.addingTimeInterval(60)),
            DiagnosticsArchiveEntry(name: "c.log", bytes: 400, modified: moment.addingTimeInterval(120)),
        ]
        let doomed = Policy.diagnosticsArchivesToDelete(archives, keepFiles: 10, keepBytes: 900)
        #expect(doomed.map(\.name) == ["a.log"])
    }

    /// **Nejnovější se nemaže nikdy**, ani když sám přeteče bajtovou mez. Rotace, která zahodí to,
    /// co právě uložila, je u #361 horší než strop — ten aspoň nechá v souboru napsáno, co se stalo.
    @Test("Nejnovější záznam přežije i nad bajtovou mezí")
    func newestSurvivesOverBudget() {
        let archives = [
            DiagnosticsArchiveEntry(name: "starý.log", bytes: 10, modified: moment),
            DiagnosticsArchiveEntry(
                name: "obr.log",
                bytes: 9_000_000,
                modified: moment.addingTimeInterval(60)
            ),
        ]
        let doomed = Policy.diagnosticsArchivesToDelete(archives, keepFiles: 10, keepBytes: 1_000)
        #expect(doomed.map(\.name) == ["starý.log"])
    }

    /// Při shodném času zápisu rozhoduje jméno — jinak by pořadí mazání záviselo na tom, jak složku
    /// zrovna vypsal filesystém, a dva běhy by smazaly něco jiného.
    @Test("Při shodném času rozhoduje jméno")
    func tiesBrokenByName() {
        let archives = [
            DiagnosticsArchiveEntry(name: "b.log", bytes: 10, modified: moment),
            DiagnosticsArchiveEntry(name: "a.log", bytes: 10, modified: moment),
        ]
        let doomed = Policy.diagnosticsArchivesToDelete(archives, keepFiles: 1, keepBytes: 10_000)
        #expect(doomed.map(\.name) == ["a.log"])
    }

    /// Co rotace udělala, se píše **do záznamu**: soubor, který začíná od nuly, se jinak nedá
    /// odlišit od aplikace, která o předchozím sezení neví.
    @Test("Uložení i smazání jsou v záznamu vidět")
    func rotationLines() {
        var rotation = DiagnosticsRotation.none
        rotation.archived = "diagnostics-do-2026-08-22T04-01-36.log"
        rotation.archivedBytes = 4_859_815
        rotation.deleted = ["diagnostics-do-2026-08-01T09-00-00.log"]
        rotation.deletedBytes = 1_024
        let lines = Policy.diagnosticsRotationLines(rotation, at: moment, in: .gmt)
        #expect(lines == [
            "2025-08-19T10:40:00Z předchozí záznam (4859815 B) uložen jako"
                + " diagnostics-do-2026-08-22T04-01-36.log",
            "2025-08-19T10:40:00Z smazáno 1 nejstarších záznamů (1024 B, drží se nejvýš"
                + " \(Policy.diagnosticsArchiveFiles) souborů a \(Policy.diagnosticsArchiveBytes) B):"
                + " diagnostics-do-2026-08-01T09-00-00.log",
        ])
    }

    /// **Když se nerotovalo, nepíše se nic.** První sezení nad prázdnou cache není událost a řádek
    /// „nic se nestalo“ by u čtení jen překážel.
    @Test("Bez rotace nejsou žádné řádky")
    func nothingRotatedNothingWritten() {
        #expect(Policy.diagnosticsRotationLines(.none, at: moment, in: .gmt).isEmpty)
    }

    /// **Nepovedená rotace je taky řádek**, ne ticho: sezení pak píše do souboru po předchůdci
    /// a má jinak dlouhý zbytek stropu, což se musí poznat u čtení, ne dohadovat.
    @Test("Nepovedená rotace se přizná v záznamu")
    func problemsAreWritten() {
        var rotation = DiagnosticsRotation.none
        rotation.problems = ["diagnostics.log nejde uložit jako x.log — chyba"]
        let lines = Policy.diagnosticsRotationLines(rotation, at: moment, in: .gmt)
        #expect(lines == [
            "2025-08-19T10:40:00Z rotace záznamu se nepovedla:"
                + " diagnostics.log nejde uložit jako x.log — chyba",
        ])
    }

    /// Výčet smazaných má mez a **zbytek se přizná počtem** — zamlčený zbytek by z výčtu udělal
    /// tvrzení, které neplatí (tatáž úvaha jako u histogramu zásobníku, #397).
    @Test("Dlouhý výčet smazaných se ořeže a zbytek se přizná")
    func deletedNamesAreCapped() {
        var rotation = DiagnosticsRotation.none
        rotation.deleted = (0..<9).map { "d\($0).log" }
        rotation.deletedBytes = 9
        let line = Policy.diagnosticsRotationLines(rotation, at: moment, in: .gmt).first
        #expect(line?.hasSuffix("d0.log d1.log d2.log d3.log d4.log d5.log +3 dalších") == true)
        #expect(line?.contains("smazáno 9 nejstarších") == true)
    }
}
