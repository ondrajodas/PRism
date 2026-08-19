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

    /// Řádek se zapíše, až když uplynula sekunda — a počitadla se tím vynulují, aby další řádek
    /// popisoval **další** sekundu, ne celý běh.
    @Test("Řádek se zapíše po sekundě a počitadla se vynulují")
    func flushesAfterASecond() throws {
        let (diagnostics, file, _) = try make()
        diagnostics.note(id: ObjectIdentifier(String.self), name: "ConversationNodeView")
        diagnostics.cycle(at: start.addingTimeInterval(0.5), cpu: 0.1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(diagnostics.snapshot() == ["ConversationNodeView": 1])

        diagnostics.cycle(at: start.addingTimeInterval(2), cpu: 0.4)
        #expect(diagnostics.snapshot().isEmpty)
        let lines = TextLines.content(try String(contentsOf: file, encoding: .utf8))
        #expect(lines == ["1970-01-01T00:00:02Z za 2.00 s: 2 kol runloopu, 0.400 s CPU,"
            + " body: ConversationNodeView=1"])
    }

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

    private func make() throws -> (RenderDiagnostics, URL, TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: file, zone: .gmt),
            zone: .gmt,
            now: start,
            cpu: 0
        )
        // Složka se vrací, aby ji test držel: `deinit` ji uklidí, jakmile poslední reference
        // zmizí — a bez toho by soubor zmizel dřív, než se do něj kdokoli podívá.
        return (diagnostics, file, directory)
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
