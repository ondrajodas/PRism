import Foundation

/// Řádkový soubor, do kterého diagnostika kreslení zapisuje (#361).
///
/// **Sezení se svým souborem rotuje** (#412), pokud dostane `archive`: dosavadní záznam se uloží
/// vedle jako `diagnostics-do-<čas>.log` a sezení začíná v prázdném souboru, tedy s celým stropem.
/// Do #412 se **přípisovalo** a strop platil na soubor napříč sezeními, takže n-té sezení mělo
/// místa podle toho, kolik zbylo po předchůdcích — naměřeno 3,5 MB, tedy necelých sedm hodin, a po
/// dalších restartech ještě méně. Proč rotace a ne strop na sezení, je u `DiagnosticsArchive`.
///
/// **Rotuje se u otevírání souboru, ne z volajícího.** Kdyby ji spouštěl volající, dala by se pořadím
/// pokazit: log s otevřeným deskriptorem by po přesunu zapisoval **do archivu**, takže by sezení
/// psalo do souboru, na který se nikdo nedívá. Takhle se rotace stane dřív, než existuje deskriptor,
/// a nedá se to udělat obráceně. Co udělala, si volající vyzvedne přes `rotation` a napíše do
/// záznamu (`Policy.diagnosticsRotationLines`).
///
/// **Strop pořád platí na soubor** (nález Copilota na #386). Rozpočet je 8 MB, tedy řádově sto tisíc
/// řádků; `written` se **seedne velikostí souboru** při jeho otevření. S rotací je to obvykle nula,
/// ale bez ní (nebo když se rotace nepovede) to je ta jediná mez, která drží: bez seedu by každé
/// sezení přípisovalo dalších 8 MB a mez by nedělala nic.
///
/// Z toho plyne, jak se sezení nad **už plným** souborem chová **bez rotace**: nezapíše **nic**
/// a `append` vrátí `false` hned u hlavičky. Limitní řádek už v souboru je od toho sezení, které na
/// strop narazilo, takže se nepřipisuje znovu; a `RenderDiagnostics.start()` z toho `false` pozná, že
/// se diagnostika **nezapnula**, a řekne to. S rotací se tenhle stav v aplikaci nestává — plný soubor
/// se odloží a nové sezení zapisuje.
///
/// **Dosažení stropu se zapisuje.** Soubor, který prostě přestane růst, se nedá odlišit od aplikace,
/// která přestala hořet — a to je zrovna ta věc, kvůli které se záznam bere.
///
/// **Chyba zápisu se hlásí na stderr a zavírá krám.** Není kam ji ukázat (diagnostika žádné UI
/// nemá) a `try?` by z ní udělal soubor, který mlčí ze dvou různých důvodů. Zůstává z toho, že
/// zápis, který se nepovedl, ukončí sezení nahlas.
final class DiagnosticsLog: @unchecked Sendable {
    /// Kolik toho smí **soubor** unést, než se zavře. Vyjmenovaná mez, ne odhad — bez ní je to
    /// únik místa s odkladem.
    static let byteLimit = 8 * 1024 * 1024

    private let url: URL
    private let limit: Int
    private let zone: TimeZone
    /// Kam se dosavadní záznam uloží, než sezení začne psát (#412). `nil` = **nerotovat**, jen
    /// přípisovat — tak to má sonda a testy, které si soubor v dočasné složce zakládají samy.
    private let archive: DiagnosticsArchive?
    private let lock = NSLock()
    private var handle: FileHandle?
    /// Co rotace udělala. Čte se **po prvním zapsaném řádku** (dřív soubor otevřený není), a to
    /// proto, aby se to dalo napsat do záznamu.
    private var rotated = DiagnosticsRotation.none
    /// Kolik už v souboru je — **včetně toho, co tam zbylo po minulých sezeních**, tedy bez rotace
    /// všechno, co se do něj kdy napsalo. Viz dokumentace typu.
    private var written = 0
    /// Kolik v souboru bylo, než tohle sezení začalo. Rozhoduje o tom, jestli se má limitní řádek
    /// připsat: nad souborem, který byl plný už při startu, tam jeden takový řádek už je.
    private var startedAt = 0
    /// Skončilo sezení? Buď stropem, nebo chybou zápisu — obojí je konec, ne pauza.
    private var isClosed = false

    /// Pásmo se **předává**, ne bere z `TimeZone.current` uvnitř: řádek o stropu jinak nese jiné
    /// pásmo než řádky s daty, a to je v jednom souboru rozdíl, který nikdo nečeká.
    init(
        url: URL,
        limit: Int = DiagnosticsLog.byteLimit,
        zone: TimeZone = .current,
        archive: DiagnosticsArchive? = nil
    ) {
        self.url = url
        self.limit = limit
        self.zone = zone
        self.archive = archive
    }

    /// Co rotace udělala, když se soubor otevíral (#412). Dokud se nic nezapsalo, je to
    /// `DiagnosticsRotation.none` — soubor se otevírá až u prvního řádku.
    var rotation: DiagnosticsRotation {
        lock.withLock { rotated }
    }

    /// Připíše jeden řádek. `false` = tenhle ani žádný další už se nezapsal.
    @discardableResult func append(_ line: String) -> Bool {
        lock.withLock {
            guard !isClosed else { return false }
            let data = Data((line + "\n").utf8)
            do {
                // Soubor se otevírá **před** kontrolou stropu, protože teprve otevřením se zjistí,
                // kolik v něm už je. Bez toho by se první řádek každého sezení zapsal vždycky.
                let handle = try openedHandle()
                guard written < limit else {
                    // Limitní řádek jen tehdy, když tohle sezení něco napsalo. Nad souborem, který
                    // byl plný už při startu, by to byl druhý stejný řádek a k tomu bajty nad strop.
                    if written > startedAt {
                        try write(data: Data(limitLine.utf8), to: handle)
                    }
                    isClosed = true
                    return false
                }
                try write(data: data, to: handle)
                return true
            } catch {
                // Nahlas: `try?` by udělal ze ztraceného záznamu ticho k nerozeznání od nečinnosti.
                FileHandle.standardError.write(
                    Data("PRism: diagnostiku nejde zapsat do \(url.path) — \(error)\n".utf8)
                )
                isClosed = true
                return false
            }
        }
    }

    private var limitLine: String {
        Policy.diagnosticLimitLine(at: Date(), in: zone, bytes: limit)
    }

    private func write(data: Data, to handle: FileHandle) throws {
        try handle.write(contentsOf: data)
        written += data.count
    }

    /// Otevřený soubor. Otevírá se **až u prvního řádku**: se vypnutou diagnostikou se nemá
    /// v cache objevit ani prázdný soubor, protože pak není poznat, jestli je zapnutá.
    ///
    /// **`written` se tady seedne skutečnou velikostí.** `offset()` po `seekToEnd()` je přesnější
    /// než dotaz na atributy souboru: čte se z toho samého deskriptoru, do kterého se pak zapisuje.
    ///
    /// **Rotace je tady, a je to schválně** (#412): musí proběhnout dřív, než existuje deskriptor —
    /// jinak by sezení zapisovalo do souboru, který se mezitím přesunul do archivu.
    private func openedHandle() throws -> FileHandle {
        if let handle { return handle }
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let archive { rotated = archive.rotate() }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        written = Int(try opened.offset())
        startedAt = written
        handle = opened
        return opened
    }
}
