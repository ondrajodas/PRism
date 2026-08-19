import Foundation

/// Řádkový soubor, do kterého diagnostika kreslení zapisuje (#361).
///
/// **Přípisuje, nepřepisuje**: dvě sezení za sebou jsou dvě části jednoho souboru, protože se
/// posílá jeden soubor a hlavička každého sezení je v něm vidět.
///
/// **Strop platí na soubor, ne na sezení** (nález Copilota na #386). Rozpočet je 8 MB, tedy řádově
/// sto tisíc řádků; kdyby se počítal od nuly při každém startu, přípisovalo by každé sezení dalších
/// 8 MB a mez by nedělala nic — což je zrovna ta „vyjmenovaná mez“, kterou má mít. `written` se proto
/// **seedne velikostí souboru** při jeho otevření.
///
/// Z toho plyne, jak se sezení nad **už plným** souborem chová: nezapíše **nic** a `append` vrátí
/// `false` hned u hlavičky. Limitní řádek už v souboru je od toho sezení, které na strop narazilo,
/// takže se nepřipisuje znovu; a `RenderDiagnostics.start()` z toho `false` pozná, že se diagnostika
/// **nezapnula**, a řekne to. Souborem se pak musí zabývat člověk (smazat ho) — samo se to nesmaže,
/// protože záznam z hořícího okna je to jediné, co z něj zbylo.
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
    private let lock = NSLock()
    private var handle: FileHandle?
    /// Kolik už v souboru je — **včetně toho, co tam napsala minulá sezení**, viz dokumentace typu.
    private var written = 0
    /// Kolik v souboru bylo, než tohle sezení začalo. Rozhoduje o tom, jestli se má limitní řádek
    /// připsat: nad souborem, který byl plný už při startu, tam jeden takový řádek už je.
    private var startedAt = 0
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
        written = Int(try opened.offset())
        startedAt = written
        handle = opened
        return opened
    }
}
