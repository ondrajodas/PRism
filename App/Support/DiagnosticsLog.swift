import Foundation

/// Řádkový soubor, do kterého diagnostika kreslení zapisuje (#361).
///
/// **Přípisuje, nepřepisuje**: dvě sezení za sebou jsou dvě části jednoho souboru, protože se
/// posílá jeden soubor a hlavička každého sezení je v něm vidět.
///
/// **Strop je vyjmenovaný a jeho dosažení se zapisuje.** Soubor, který prostě přestane růst, se
/// nedá odlišit od aplikace, která přestala hořet — a to je zrovna ta věc, kvůli které se záznam
/// bere. Rozpočet je 8 MB, tedy řádově sto tisíc řádků: víc než den hořícího okna a míň, než by
/// vadilo v příloze.
///
/// **Chyba zápisu se hlásí na stderr a zavírá krám.** Není kam ji ukázat (diagnostika žádné UI
/// nemá) a `try?` by z ní udělal soubor, který mlčí ze dvou různých důvodů. Zůstává z toho, že
/// zápis, který se nepovedl, ukončí sezení nahlas.
final class DiagnosticsLog: @unchecked Sendable {
    /// Kolik toho smí sezení napsat, než se zavře. Vyjmenovaná mez, ne odhad — bez ní je to
    /// únik místa s odkladem.
    static let byteLimit = 8 * 1024 * 1024

    private let url: URL
    private let limit: Int
    private let zone: TimeZone
    private let lock = NSLock()
    private var handle: FileHandle?
    private var written = 0
    /// Skončilo sezení? Buď stropem, nebo chybou zápisu — obojí je konec, ne pauza.
    private var isClosed = false

    /// Pásmo se **předává**, ne bere z `TimeZone.current` uvnitř: řádek o stropu jinak nese jiné
    /// pásmo než řádky s daty, a to je v jednom souboru rozdíl, který nikdo nečeká.
    init(url: URL, limit: Int = DiagnosticsLog.byteLimit, zone: TimeZone = .current) {
        self.url = url
        self.limit = limit
        self.zone = zone
    }

    /// Připíše jeden řádek. `false` = tenhle ani žádný další už se nezapsal.
    @discardableResult func append(_ line: String) -> Bool {
        lock.withLock {
            guard !isClosed else { return false }
            guard written < limit else {
                // Poslední řádek dostane ještě prostor: bez něj by soubor končil uprostřed
                // provozu a nebylo by z čeho poznat, že to byl strop.
                write(Policy.diagnosticLimitLine(at: Date(), in: zone, bytes: limit))
                isClosed = true
                return false
            }
            return write(line)
        }
    }

    @discardableResult private func write(_ line: String) -> Bool {
        // `Data(_.utf8)`, ne `data(using:)`: to druhé je `Optional` a `nil` v něm znamená
        // „nešlo zakódovat“, což u UTF-8 nastat nemůže — byla by to mrtvá větev, ve které se
        // řádek tiše zahodí.
        let data = Data((line + "\n").utf8)
        do {
            try openedHandle().write(contentsOf: data)
            written += data.count
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

    /// Otevřený soubor. Otevírá se **až u prvního řádku**: se vypnutou diagnostikou se nemá
    /// v cache objevit ani prázdný soubor, protože pak není poznat, jestli je zapnutá.
    private func openedHandle() throws -> FileHandle {
        if let handle { return handle }
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return opened
    }
}
