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

    /// **Bez rotace** jsou dvě sezení dvě části jednoho souboru. Tuhle podobu má log v sondách
    /// a v testech, které si soubor v dočasné složce zakládají samy — v aplikaci se od #412 rotuje.
    @Test("Druhé sezení bez rotace přípisuje, nepřepisuje")
    func appendsAcrossSessions() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        DiagnosticsLog(url: file).append("první sezení")
        DiagnosticsLog(url: file).append("druhé sezení")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text == "první sezení\ndruhé sezení\n")
    }

    /// **Strop platí na soubor, ne na sezení** (nález Copilota na #386) — a pořád platí, když se
    /// nerotuje: bez seedu z velikosti souboru by každé sezení přípisovalo dalších 8 MB a mez by
    /// nedělala nic. S rotací se tenhle stav v aplikaci nestává, viz test pod tímhle.
    @Test("Nové sezení nad plným souborem nezapíše bez rotace nic")
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

    /// **Nejcennější případ z #412: sezení nad plným souborem zapisuje.** Do #412 se v tomhle stavu
    /// nezapsalo nic a diagnostika se nezapnula — naměřeno v provozu, že tak přišlo o 42 hodin.
    ///
    /// Ověřeno **vloženou regresí**: bez `archive` (tedy jak to bylo do #412) spadne první
    /// expectation, protože `append` vrátí `false` — to je zrovna test nad tímhle.
    @Test("Sezení s rotací zapisuje i nad plným souborem")
    func rotatedSessionWritesOverFullPredecessor() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let previous = DiagnosticsLog(url: file, limit: 20, zone: .gmt)
        #expect(previous.append("první sezení, které strop naplní až nad hlavu"))
        #expect(!previous.append("a tady už narazilo"))
        let before = try String(contentsOf: file, encoding: .utf8)

        let session = DiagnosticsLog(
            url: file,
            limit: 20,
            zone: .gmt,
            archive: DiagnosticsArchive(url: file, zone: .gmt)
        )
        #expect(session.append("hlavička druhého sezení"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "hlavička druhého sezení\n")

        // **A starý soubor se nezahodil** — u #361 se čte zpětně, takže rotace, která mazala
        // historii, by byla horší než strop.
        let archives = try archiveNames(in: directory.url)
        #expect(archives.count == 1)
        // `#require`, ne index: s vloženou regresí je pole prázdné, a test, který kvůli tomu složí
        // celý běh, by sebral výsledky i všem ostatním.
        let archived = try #require(archives.first)
        #expect(try String(contentsOf: directory.url.appending(path: archived), encoding: .utf8)
            == before)
        // Co rotace udělala, si vyzvedne `RenderDiagnostics.start()` a napíše to do záznamu.
        #expect(session.rotation.archived == archived)
        #expect(session.rotation.archivedBytes == before.utf8.count)
        #expect(session.rotation.problems.isEmpty)
    }

    /// **Prázdný ani chybějící záznam se nearchivuje**: soubor bez jediného řádku není historie, jen
    /// by se v cache hromadily nuly po každém spuštění.
    @Test("Nad prázdnou cache se nerotuje")
    func nothingToRotate() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let session = DiagnosticsLog(
            url: file,
            zone: .gmt,
            archive: DiagnosticsArchive(url: file, zone: .gmt)
        )
        #expect(session.append("první sezení vůbec"))
        #expect(session.rotation == .none)
        #expect(try archiveNames(in: directory.url).isEmpty)
    }

    /// Úklid maže **od nejstaršího** a nejnovější nechá — a jména smazaných jdou do záznamu, takže se
    /// historie neztrácí potichu.
    @Test("Nad mezí se maže nejstarší uložený záznam")
    func pruneDeletesOldest() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        try write("nejstarší", to: directory.url, named: "diagnostics-do-2026-08-20T10-00-00.log",
                  modified: start)
        try write("novější", to: directory.url, named: "diagnostics-do-2026-08-21T10-00-00.log",
                  modified: start.addingTimeInterval(60))
        try write("aktivní záznam", to: file, modified: start.addingTimeInterval(120))

        var archive = DiagnosticsArchive(url: file, zone: .gmt)
        archive.keepFiles = 2
        let session = DiagnosticsLog(url: file, zone: .gmt, archive: archive)
        #expect(session.append("nové sezení"))
        #expect(session.rotation.deleted == ["diagnostics-do-2026-08-20T10-00-00.log"])
        // Zbyly dva: ten novější z minula a ten právě uložený.
        #expect(try archiveNames(in: directory.url) == [
            "diagnostics-do-2026-08-21T10-00-00.log",
            "diagnostics-do-1970-01-01T00-02-00.log",
        ].sorted())
    }

    /// **Složka pojmenovaná jako záznam se nesmaže.** `removeItem` nad ní smaže celý podstrom, takže
    /// je to ta nejhorší věc, kterou by úklid mohl najít — a v kořeni cache leží i podsložky
    /// s nálezy a drafty. Do výčtu se proto dostane jedině obyčejný soubor a v záznamu je o tom
    /// věta.
    @Test("Složka se jménem záznamu se do úklidu nepočítá")
    func directoryNamedLikeArchiveSurvives() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let intruder = directory.url.appending(path: "diagnostics-do-2026-08-20T10-00-00.log")
        try FileManager.default.createDirectory(at: intruder, withIntermediateDirectories: false)
        try write("uvnitř", to: intruder.appending(path: "nález.json"), modified: start)
        try write("aktivní záznam", to: file, modified: start.addingTimeInterval(120))

        var archive = DiagnosticsArchive(url: file, zone: .gmt)
        archive.keepFiles = 1
        let session = DiagnosticsLog(url: file, zone: .gmt, archive: archive)
        #expect(session.append("nové sezení"))
        #expect(session.rotation.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: intruder.appending(path: "nález.json").path))
        #expect(session.rotation.problems.count == 1)
        #expect(session.rotation.problems[0].contains("není obyčejný soubor"))
    }

    /// **Symlink pojmenovaný jako záznam se nesmaže** (nález Copilota na #423) — a je to změřená
    /// vlastnost, ne úvaha: `resourceValues(forKeys: [.isRegularFileKey])` odkaz **nerozbaluje**,
    /// takže i odkaz na obyčejný soubor vypadne z výčtu jako cokoli, co obyčejný soubor není.
    /// Bezpečnější strana omylu: člověk, který si takový odkaz udělal, o něj nepřijde, a sám od sebe
    /// růst nemůže.
    @Test("Symlink se jménem záznamu se do úklidu nepočítá")
    func symlinkNamedLikeArchiveSurvives() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let target = directory.url.appending(path: "jinde.log")
        try write("cizí soubor", to: target, modified: start)
        let link = directory.url.appending(path: "diagnostics-do-2026-08-20T10-00-00.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try write("aktivní záznam", to: file, modified: start.addingTimeInterval(120))

        var archive = DiagnosticsArchive(url: file, zone: .gmt)
        archive.keepFiles = 1
        let session = DiagnosticsLog(url: file, zone: .gmt, archive: archive)
        #expect(session.append("nové sezení"))
        #expect(session.rotation.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: link.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(session.rotation.problems.count == 1)
        #expect(session.rotation.problems[0].contains("není obyčejný soubor"))
    }

    /// **Záchvat se zapisuje po sekundách, ne do souhrnu** (#412). Zajímavý je jeho náběh, takže
    /// hoření ani průchod tělem se sráží nesmí — jinak by z minutového souhrnu nebylo poznat, kdy
    /// kolo začalo.
    @Test("Hořící úseky jdou do souboru po sekundách")
    func burningSlicesAreNotFolded() throws {
        let (diagnostics, file, directory) = try make()
        defer { _ = directory }
        for second in 1...3 {
            #expect(diagnostics.flush(
                at: start.addingTimeInterval(TimeInterval(second)),
                cpu: TimeInterval(second)
            ))
        }
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.contains("HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU") })
    }

    /// Klid se sráží do **jednoho souhrnu za minutu** — 89 % hlavních řádků ve skutečném záznamu
    /// bylo právě tohle, takže je to šedesátina objemu.
    @Test("Klid se sráží do minutového souhrnu")
    func quietFoldsIntoSummary() throws {
        let (diagnostics, file, directory) = try make()
        defer { _ = directory }
        for second in 1...59 {
            diagnostics.noteCycle()
            diagnostics.noteCycle()
            #expect(diagnostics.flush(at: start.addingTimeInterval(TimeInterval(second)), cpu: 0))
        }
        // Do minuty v souboru **není nic** — ani prázdný soubor, aby se z cache poznalo, jestli
        // sezení běželo se zapnutou diagnostikou.
        #expect(!FileManager.default.fileExists(atPath: file.path))

        diagnostics.noteCycle()
        diagnostics.noteCycle()
        #expect(diagnostics.flush(at: start.addingTimeInterval(60), cpu: 0))
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines == ["1970-01-01T00:01:00Z za 60.00 s klid: 60 úseků, 120 kol runloopu,"
            + " 0.000 s CPU, 0 bez kola runloopu"])
    }

    /// **Souhrn jde před ten řádek, který klid přerušil**, takže časy v souboru zůstávají vzestupně
    /// — a náběh záchvatu se čte v tom pořadí, ve kterém se stal.
    @Test("Souhrn klidu se zapíše před řádkem, který klid ukončil")
    func quietSummaryPrecedesTheBusyLine() throws {
        let (diagnostics, file, directory) = try make()
        defer { _ = directory }
        for second in 1...3 {
            diagnostics.noteCycle()
            #expect(diagnostics.flush(at: start.addingTimeInterval(TimeInterval(second)), cpu: 0))
        }
        diagnostics.note(id: ObjectIdentifier(String.self), name: "DiffView")
        #expect(diagnostics.flush(at: start.addingTimeInterval(4), cpu: 0))
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines.count == 2)
        #expect(lines[0] == "1970-01-01T00:00:04Z za 3.00 s klid: 3 úseků, 3 kol runloopu,"
            + " 0.000 s CPU, 0 bez kola runloopu")
        #expect(lines[1].hasSuffix("body: DiffView=1"))
    }

    // MARK: - Pomůcky

    private var start: Date { Date(timeIntervalSince1970: 0) }

    /// Jména uložených záznamů ve složce, seřazená — v testech se porovnávají výčtem, ne podle toho,
    /// jak je zrovna vypsal filesystém.
    private func archiveNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter(Policy.isDiagnosticsArchive)
            .sorted()
    }

    private func write(
        _ text: String,
        to directory: URL,
        named name: String,
        modified: Date
    ) throws {
        try write(text, to: directory.appending(path: name), modified: modified)
    }

    /// Soubor s **nastaveným časem zápisu**: jméno uloženého záznamu i pořadí mazání se berou
    /// z něj, takže bez toho by test tvrdil něco o hodinách stroje.
    private func write(_ text: String, to file: URL, modified: Date) throws {
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: file.path
        )
    }

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
