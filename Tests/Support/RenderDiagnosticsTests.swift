import Foundation
import Testing

@testable import PRism

/// Diagnostika kreslení (#361) — počitadla, soubor a hlavně to, co dělat **nesmí**.
///
/// Je to nástroj na hledání kola v rozvržení, takže nejcennější tvrzení jsou negativní: vypnutá
/// nesmí počítat nic ani zakládat soubor, a zapnutá nesmí sahat na hodiny při každém průchodu
/// tělem. Kdyby cokoli z toho neplatilo, měřidlo by měnilo to, co měří.
@Suite("Diagnostika kreslení (#361)")
struct RenderDiagnosticsTests {
    /// **Vypnutá diagnostika nezakládá ani prázdný soubor.** Kdyby ho zakládala, nedalo by se
    /// z cache poznat, jestli sezení běželo se zapnutou diagnostikou — a to je první věc, na
    /// kterou se u přiloženého záznamu ptám.
    @Test("Vypnutá diagnostika nepočítá nic a soubor nezaloží")
    func disabledDoesNothing() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        // `current` je nil, dokud se diagnostika nezapne — a `pass(_:)` je celá jen tenhle
        // dotaz. Tady se ověřuje ten stav, ve kterém aplikace běžně žije.
        #expect(RenderDiagnostics.current == nil)
        RenderDiagnostics.pass(RenderDiagnosticsTests.self)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Průchody tělem se počítají po typech")
    func countsByType() throws {
        let (diagnostics, _, _) = try make()
        diagnostics.note(id: ObjectIdentifier(String.self), name: "MarkdownText")
        diagnostics.note(id: ObjectIdentifier(String.self), name: "MarkdownText")
        diagnostics.note(id: ObjectIdentifier(Int.self), name: "ConversationNodeView")
        #expect(diagnostics.snapshot() == ["MarkdownText": 2, "ConversationNodeView": 1])
    }

    /// Jméno typu se skládá reflexí, takže se smí spočítat **jen u prvního průchodu**. V hořícím
    /// okně jde o tisíce volání za sekundu — kdyby v každém byla reflexe, diagnostika by sama
    /// přispěla do toho, co má měřit.
    @Test("Jméno typu se skládá jen u prvního průchodu")
    func nameResolvedOnce() throws {
        let (diagnostics, _, _) = try make()
        let counter = NameCounter()
        for _ in 0..<5 {
            diagnostics.note(id: ObjectIdentifier(String.self), name: counter.name("DiffView"))
        }
        #expect(counter.resolved == 1)
        #expect(diagnostics.snapshot() == ["DiffView": 5])
    }

    /// **Vypnutá diagnostika nesmí sáhnout ani na graf** (#361). `inGraph(_:)` sedí na cestě
    /// identity líného seznamu, tedy tam, kde se v hořícím kole volá tisíckrát za sekundu — a bez
    /// zapnuté diagnostiky je z něj jeden load `Optional`u.
    @Test("Vypnutá diagnostika nepočítá ani místa v grafu")
    func disabledIgnoresGraphSites() {
        #expect(RenderDiagnostics.current == nil)
        RenderDiagnostics.inGraph(.diffRowIdentity)
        #expect(RenderDiagnostics.current == nil)
    }

    /// Hák diagnostiky **nesmí změnit identitu řádku** (#361): kdyby `diagnosedID` vydalo jinou
    /// hodnotu než `id`, líný seznam by při zapnuté diagnostice přerovnal obsah a měřilo by se
    /// něco jiného než při vypnuté.
    @Test("diagnosedID vrací tutéž identitu jako id")
    func diagnosedIdentityMatches() {
        let row = ConversationRow(id: "uzel-1", node: .commits([]), isFirstNew: false)
        #expect(row.diagnosedID == row.id)
        let diffRow = DiffRow.note("soubor.swift#0", "binárka")
        #expect(diffRow.diagnosedID == diffRow.id)
    }

    /// Počty míst v grafu jdou do řádku **za** hlavní řádek úseku, a odsazené — v souboru se čtou
    /// jako příloha k té sekundě, ne jako další sekunda.
    @Test("Místa v grafu se počítají a jdou do řádku za úsekem")
    func countsGraphSites() throws {
        let (diagnostics, file, directory) = try make()
        defer { _ = directory }
        diagnostics.note(site: .diffRowIdentity)
        diagnostics.note(site: .diffRowIdentity)
        diagnostics.note(site: .pairBlockGeometry)
        #expect(diagnostics.graphSnapshot() == ["DiffRow.id": 2, "DiffPairBlockRow.geometry": 1])
        diagnostics.noteCycle()
        #expect(diagnostics.flush(at: start.addingTimeInterval(1), cpu: 0.5))
        #expect(diagnostics.graphSnapshot().isEmpty)
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines.count >= 2)
        #expect(lines[1] == "    graf: DiffRow.id=2 DiffPairBlockRow.geometry=1")
    }

    /// **Ticho nedostane přílohu.** Úsek, ve kterém není ani kolo runloopu, ani průchod tělem, ani
    /// hoření, se nezapisuje — a řádky o grafu proto taky ne, i když se v něm identita čte. Jinak
    /// by se soubor plnil nad aplikací, která nic nedělá.
    @Test("Bez hlavního řádku se řádky o grafu nezapíšou")
    func silentSliceHasNoGraphLines() throws {
        let (diagnostics, file, directory) = try make()
        defer { _ = directory }
        diagnostics.note(site: .conversationRowIdentity)
        #expect(diagnostics.flush(at: start.addingTimeInterval(1), cpu: 0))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // Nasbírané se přitom **zahodí**, jinak by to nesl další úsek a čísla by se přičítala
        // k sekundě, ve které se nic z toho nestalo.
        #expect(diagnostics.graphSnapshot().isEmpty)
    }

    /// **Vzorků zásobníku se za úsek vezme nejvýš `stackBudget`** — bez toho stropu by hořící kolo
    /// vyrobilo tisíce dotazů za sekundu a diagnostika by se stala tím, co měří.
    ///
    /// `interval: 0` je tady schválně: odstup mezi vzorky je `interval / stackBudget`, takže
    /// s nulou se rozhoduje **jen** rozpočtem a test nezávisí na hodinách. Že odstup zabírá,
    /// tvrdí test pod tímhle.
    @Test("Za úsek se vezme nejvýš osm vzorků zásobníku")
    func stackSamplesAreCapped() throws {
        let (diagnostics, file, directory) = try make(interval: 0)
        defer { _ = directory }
        for _ in 0..<500 { diagnostics.note(site: .fileIdentity) }
        diagnostics.noteCycle()
        #expect(diagnostics.flush(at: start.addingTimeInterval(1), cpu: 0.5))
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines[1] == "    graf: FileDiff.id=500")
        // Vzorky jsou nulové, protože v testu žádný graf neaktualizuje — a je to **v řádku
        // vidět**: „8 dotazů, 0 vzorků“ je jiný stav než „nikdo se neptal“.
        #expect(lines[2] == "    zásobník: \(RenderDiagnostics.stackBudget) dotazů, 0 vzorků")
    }

    /// **Odstup mezi vzorky drží**: s úsekem o sekundě je mezi vzorky 1/8 sekundy, takže se
    /// v jedné smyčce vezme právě jeden. Bez toho by osm vzorků padlo do jedné milisekundy a
    /// souhrn by nebyl histogram, ale osmkrát tentýž bod.
    @Test("Vzorky se v jedné smyčce nevezmou všechny")
    func stackSamplesAreSpaced() throws {
        let (diagnostics, file, directory) = try make(interval: 1)
        defer { _ = directory }
        for _ in 0..<500 { diagnostics.note(site: .lineGeometry) }
        diagnostics.noteCycle()
        #expect(diagnostics.flush(at: start.addingTimeInterval(1), cpu: 0.5))
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines[2] == "    zásobník: 1 dotazů, 0 vzorků")
    }

    /// Řádek uzavírá úsek: co se nasbíralo, se do něj zapíše a počitadla se vynulují, aby další
    /// řádek popisoval **další** úsek, ne celý běh.
    @Test("Řádek uzavře úsek a počitadla se vynulují")
    func flushClosesTheSlice() throws {
        let (diagnostics, file, _) = try make()
        diagnostics.note(id: ObjectIdentifier(String.self), name: "ConversationNodeView")
        diagnostics.noteCycle()
        diagnostics.noteCycle()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(diagnostics.snapshot() == ["ConversationNodeView": 1])

        #expect(diagnostics.flush(at: start.addingTimeInterval(2), cpu: 0.4))
        #expect(diagnostics.snapshot().isEmpty)
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines == ["1970-01-01T00:00:02Z za 2.00 s: 2 kol runloopu, 0.400 s CPU,"
            + " body: ConversationNodeView=1"])
    }

    /// **Zapisuje se i tehdy, když hlavní vlákno nepustí runloop ke slovu** (#391) — a tohle je
    /// ten scénář, kvůli kterému se to přepisovalo: ve čtvrtém záchvatu (#361) diagnostika
    /// přestala psát **v okamžiku ztuhnutí**, protože řádky vypisoval observer na `beforeWaiting`.
    ///
    /// Kolo se vyrábí tak, jak se v tom záchvatu chovalo SwiftUI: observer na `beforeWaiting`
    /// s **nižším pořadím**, který se nevrátí. Runloop je tedy uvnitř callbacku, hoří a naše
    /// počitadlo kol (`observeRunLoop`, pořadí 2 000 000) se na řadu vůbec nedostane.
    ///
    /// **Čte se snímek souboru z chvíle, kdy záchvat ještě trval** — bere ho ten blokující
    /// observer, než se vrátí. Po záchvatu by to nic nedokazovalo: tehdy už runloop běží a řádek
    /// by mohl napsat kdokoli.
    ///
    /// **Strop je hned u toho, jak se to píše** (pravidlo z #379): blokuje se `Self.burn` a ani
    /// o milisekundu víc, protože měřicí smyčka bez stropu tady už jednou sebrala obrazovku.
    @MainActor
    @Test("Zapisuje i v kole, ze kterého se runloop nevrátí")
    func writesWhileMainThreadNeverReturns() throws {
        let (diagnostics, file, directory) = try makeLive(interval: 0.1)
        // Složku drží test, jinak ji `deinit` smaže hned a soubor by se zakládal do prázdna.
        defer {
            diagnostics.stop()
            _ = directory
        }
        diagnostics.observeRunLoop()
        diagnostics.startWriting()
        let duringFit = try burnMainThread(watching: file)

        // Aspoň dva řádky **z doby záchvatu** a všechny s tou větou. Kdyby je psal observer
        // hlavního runloopu, nebyl by tam ani jeden — což tvrdí test níž.
        #expect(duringFit.count >= 2)
        #expect(duringFit.allSatisfy { $0.contains("0 kol runloopu") })
        #expect(duringFit.allSatisfy { $0.contains("HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU") })
        print("SONDA řádky ze zaseknutého kola:\n" + duringFit.joined(separator: "\n"))
    }

    /// **Kontrola z druhé strany, tedy vložená regrese**: tentýž záchvat, ale řádky vypisuje
    /// observer runloopu, jako do #391. Ze záchvatu nezůstane **nic** — a bez tohohle tvrzení by
    /// test výš nedokazoval, že ty řádky přineslo zapisovací vlákno, a ne shoda okolností.
    @MainActor
    @Test("Zápis z observeru runloopu ze zaseknutého kola nezachytí nic")
    func withoutWriterNothingIsRecorded() throws {
        let (diagnostics, file, directory) = try makeLive(interval: 0.1)
        defer {
            diagnostics.stop()
            _ = directory
        }
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            2_000_000
        ) { _, _ in
            diagnostics.flush(at: Date(), cpu: threadCPUSeconds())
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }

        #expect(try burnMainThread(watching: file).isEmpty)
    }

    /// **Druhé zapisovací vlákno se nepustí.** Dva zapisovatelé si přebírají počitadla po sobě
    /// (každý flush je nuluje), takže by se úseky rozpadly na polovic a řádky by tvrdily, že se nic
    /// nedělo — přesně ta věta, kvůli které se záznam bere. Poznat je to na počtu řádků: se dvěma
    /// vlákny jich za tu chvíli je dvojnásobek.
    @MainActor
    @Test("Druhé volání startWriting nepustí druhé vlákno")
    func writerStartsOnlyOnce() throws {
        let (diagnostics, file, directory) = try makeLive(interval: 0.1)
        defer {
            diagnostics.stop()
            _ = directory
        }
        diagnostics.startWriting()
        diagnostics.startWriting()
        diagnostics.startWriting()
        let duringFit = try burnMainThread(watching: file)
        // Za `burn` sekundy při cadenci 0,1 s je řádků nejvýš deset. Tři vlákna by dala víc —
        // a hlavně by se hořící sekunda rozpadla na úseky, ve kterých není vidět nic.
        #expect(duringFit.count <= 10)
        #expect(!duringFit.isEmpty)
    }

    /// Nechá hlavní vlákno hořet `Self.burn` uvnitř observeru na `beforeWaiting` a vrátí to, co
    /// v souboru bylo **na konci toho hoření**, tedy ještě než se runloop vrátil.
    @MainActor
    private func burnMainThread(watching file: URL) throws -> [Substring] {
        let snapshot = Snapshot()
        // Pořadí **nižší** než 2 000 000 z `observeRunLoop()`, aby se počitadlo kol dostalo na
        // řadu až po tomhle — a tohle se v tom kole nevrátí, takže vůbec.
        let blocker = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            false,
            0
        ) { _, _ in
            let until = Date().addingTimeInterval(Self.burn)
            // Zaměstnané, ne spící vlákno: `sleep` by CPU nespálil a řádek by pak tvrdil, že se
            // nic nedělo. Tohle je ta pravdivá reprodukce — hoření bez jediného kola runloopu.
            while Date() < until { snapshot.spin() }
            snapshot.text = try? String(contentsOf: file, encoding: .utf8)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), blocker, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), blocker, .commonModes) }
        _ = spinMainRunLoop(seconds: Self.burn + 0.3)
        return TextLines.content(snapshot.text ?? "")
    }

    /// Jak dlouho se v testu hoří. Deset úseků zapisovacího vlákna po 0,1 s — dost na to, aby
    /// „aspoň dva řádky“ nebylo na hraně, a málo na to, aby to někoho zdrželo.
    private static let burn: TimeInterval = 1

    /// Strop se **napíše do souboru** a další řádky se zahodí. Soubor, který prostě přestane
    /// růst, se nedá odlišit od aplikace, která přestala hořet.
    @Test("Po vyčerpání stropu se zapíše proč a dál už nic")
    func stopsAtLimit() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let log = DiagnosticsLog(url: file, limit: 20, zone: .gmt)
        #expect(log.append("první řádek přes dvacet bytů, takže strop padne hned za ním"))
        #expect(!log.append("druhý"))
        #expect(!log.append("třetí"))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("strop 20 B vyčerpán"))
        #expect(!text.contains("druhý"))
        #expect(!text.contains("třetí"))
    }

    /// Dvě sezení jsou dvě části jednoho souboru: posílá se jeden soubor a hlavička každého
    /// sezení je v něm vidět.
    @Test("Druhé sezení přípisuje, nepřepisuje")
    func appendsAcrossSessions() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        DiagnosticsLog(url: file).append("první sezení")
        DiagnosticsLog(url: file).append("druhé sezení")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text == "první sezení\ndruhé sezení\n")
    }

    /// **Strop platí na soubor, ne na sezení** (nález Copilota na #386). Kdyby se počítal od nuly
    /// při každém startu, přípisovalo by každé sezení dalších 8 MB a mez by nedělala nic — což je
    /// zrovna to, co „vyjmenovaná mez“ nemá být.
    @Test("Nové sezení nad plným souborem nezapíše nic")
    func limitHoldsAcrossSessions() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let first = DiagnosticsLog(url: file, limit: 20, zone: .gmt)
        #expect(first.append("první řádek, který strop naplní až nad hlavu"))
        #expect(!first.append("druhý"))
        let full = try String(contentsOf: file, encoding: .utf8)

        // Druhé sezení: hlavička se **nezapíše** a `false` je to, z čeho `RenderDiagnostics.start()`
        // pozná, že se diagnostika nemá zapínat.
        let second = DiagnosticsLog(url: file, limit: 20, zone: .gmt)
        #expect(!second.append("hlavička druhého sezení"))
        #expect(!second.append("a další řádek"))
        // Soubor je **beze změny** — ani o limitní řádek: ten už v něm je od sezení, které na strop
        // narazilo, a druhý stejný by byl bajty nad strop a věta dvakrát.
        #expect(try String(contentsOf: file, encoding: .utf8) == full)
        #expect(full.components(separatedBy: "strop 20 B vyčerpán").count - 1 == 1)
    }

    // MARK: - Pomůcky

    private var start: Date { Date(timeIntervalSince1970: 0) }

    private func make(interval: TimeInterval = 1) throws -> (RenderDiagnostics, URL, TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: file, zone: .gmt),
            zone: .gmt,
            interval: interval,
            now: start,
            cpu: 0
        )
        // Složka se vrací, aby ji test držel: `deinit` ji uklidí, jakmile poslední reference
        // zmizí — a bez toho by soubor zmizel dřív, než se do něj kdokoli podívá.
        return (diagnostics, file, directory)
    }

    /// Diagnostika se **skutečnými hodinami a skutečným CPU hlavního vlákna** — pro testy, ve
    /// kterých zapisuje zapisovací vlákno. S razítkem z roku 1970 a nulovým CPU by úsek vyšel na
    /// půl století a hoření na 0 %, takže by se nezapsalo nic.
    @MainActor
    private func makeLive(interval: TimeInterval) throws -> (RenderDiagnostics, URL, TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: file, zone: .gmt),
            zone: .gmt,
            interval: interval
        )
        return (diagnostics, file, directory)
    }
}

/// Snímek souboru z chvíle, kdy záchvat ještě trval, plus spalovač CPU.
///
/// Třída, protože blok observeru je escaping a musí do něj jít reference; `@unchecked Sendable`,
/// protože se celý život odehraje na hlavním vlákně a zámek by tady jen zastíral, o čem test je.
private final class Snapshot: @unchecked Sendable {
    var text: String?
    private var sink = 0

    /// Kousek práce, který jde vidět v CPU. Zaměstnané, ne spící vlákno — spící by CPU nespálilo
    /// a řádek by pak tvrdil, že se nic nedělo.
    func spin() {
        sink = sink &+ (0..<2000).reduce(0, &+)
    }
}

/// Počitadlo toho, kolikrát se jméno typu skutečně složilo.
///
/// Třída, ne `inout Int`: hodnota se do `note(id:name:)` předává `@autoclosure`, a ta by `inout`
/// zachytit nesměla — což je zároveň důkaz, že se `@autoclosure` doopravdy vyhodnocuje líně.
private final class NameCounter {
    var resolved = 0

    func name(_ value: String) -> String {
        resolved += 1
        return value
    }
}
