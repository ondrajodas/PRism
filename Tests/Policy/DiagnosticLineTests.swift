import Foundation
import Testing

@testable import PRism

/// Řádek záznamu diagnostiky kreslení (#361).
///
/// Skládání je čistá funkce právě proto, aby se dalo napsat literálem: soubor se posílá dál a je
/// jediné, co z hořícího okna zbyde, takže na něm musí být pořád totéž a ve stejném pořadí.
@Suite("Řádek diagnostiky kreslení (#361)")
struct DiagnosticLineTests {
    private let moment = Date(timeIntervalSince1970: 1_755_600_000)

    /// **Nejcennější případ: nečinnost nezapíše nic.** Bez toho by soubor rostl i nad aplikací,
    /// která nic nedělá, a mezera v záznamu by přestala znamenat „tady bylo ticho“.
    @Test("Bez kola a bez průchodů se řádek nezapisuje")
    func nothingToReport() {
        #expect(Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1.5,
            cycles: 0,
            cpu: 0,
            passes: [:]
        ) == nil)
    }

    /// **Úsek, ve kterém hlavní vlákno nepustilo runloop ke slovu, se zapsat musí** (#391), a to je
    /// změna proti #386: hlavní vlákno se z transakce nevrátí, takže kol runloopu je nula a průchodů
    /// tělem taky — a přesně tenhle řádek v souboru u čtvrtého záchvatu chyběl. Rozhoduje proto CPU.
    ///
    /// Věta v řádku přitom netvrdí „záchvat“, jen to změřené: **jeden** takový úsek může být i drahá
    /// práce na hlavním vlákně. Záchvat se pozná z toho, že takových řádků jde za sebou desítky.
    @Test("Hoření bez kola a bez průchodů se zapíše i s větou o runloopu")
    func stuckLoopIsWritten() {
        #expect(Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 0,
            cpu: 0.998,
            passes: [:]
        ) == "2025-08-19T10:40:00Z za 1.00 s: 0 kol runloopu, 0.998 s CPU"
            + " — HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU")
    }

    /// **Ta věta patří jedině k nule kol.** Když se runloop vrací, hoří to při práci — a to je jiný
    /// stav než kolo, ze kterého se hlavní vlákno nevrátilo.
    @Test("S koly runloopu se věta nepřipisuje, i když to hoří")
    func burningWithCyclesIsNotStuck() {
        let line = Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 42,
            cpu: 0.9,
            passes: [:]
        )
        #expect(line == "2025-08-19T10:40:00Z za 1.00 s: 42 kol runloopu, 0.900 s CPU")
    }

    /// A nečinnost se pořád nezapisuje: spící hlavní vlákno CPU nespotřebuje, takže ta hranice
    /// nesmí být tak nízko, aby ji přebilo zaokrouhlení.
    @Test("Nečinný úsek se nezapíše ani se stopou CPU")
    func idleWithTraceOfCPUStaysSilent() {
        #expect(Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 0,
            cpu: 0.014,
            passes: [:]
        ) == nil)
    }

    /// Hranice je **podíl z uplynulého času**, ne absolutní sekundy — jinak by u kratší cadence
    /// zapisovacího vlákna vycházela jinak než u delší a dva soubory by se nedaly srovnat.
    @Test("Hranice hoření je podíl z uplynulého času")
    func burnFloorScalesWithElapsed() {
        // 0,004 s za 0,1 s je 4 %, tedy pod hranicí; za 0,05 s je 8 %, tedy nad ní.
        #expect(Policy.diagnosticLine(
            at: moment, in: .gmt, over: 0.1, cycles: 0, cpu: 0.004, passes: [:]
        ) == nil)
        #expect(Policy.diagnosticLine(
            at: moment, in: .gmt, over: 0.05, cycles: 0, cpu: 0.004, passes: [:]
        )?.hasSuffix("HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU") == true)
    }

    /// Kolo bez jediného průchodu tělem **je** informace: runloop se probouzí, ale nic se
    /// nepřekresluje. Takový řádek se proto píše, jen bez sekce `body:`.
    @Test("Kolo bez průchodů tělem se zapíše bez sekce body")
    func cyclesWithoutBodies() {
        #expect(Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 7,
            cpu: 0.125,
            passes: [:]
        ) == "2025-08-19T10:40:00Z za 1.00 s: 7 kol runloopu, 0.125 s CPU")
    }

    /// Řazení je podle **počtu**, ne podle jména: hledá se ten typ, který se překresluje nejvíc.
    @Test("Průchody tělem jdou od nejčastějšího")
    func passesSortedByCount() {
        let line = Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 3,
            cpu: 1,
            passes: ["ContentView": 2, "ConversationNodeView": 900, "MarkdownText": 300]
        )
        #expect(line == "2025-08-19T10:40:00Z za 1.00 s: 3 kol runloopu, 1.000 s CPU,"
            + " body: ConversationNodeView=900 MarkdownText=300 ContentView=2")
    }

    /// Při shodném počtu rozhoduje jméno. Bez toho by se dva soubory ze dvou sezení nedaly
    /// srovnat — pořadí by záviselo na tom, jak se zrovna uspořádal slovník.
    @Test("Při shodném počtu rozhoduje jméno")
    func tiesBrokenByName() {
        let line = Policy.diagnosticLine(
            at: moment,
            in: .gmt,
            over: 1,
            cycles: 1,
            cpu: 0,
            passes: ["DiffView": 5, "ContentView": 5]
        )
        #expect(line?.hasSuffix("body: ContentView=5 DiffView=5") == true)
    }

    /// Hlavička nese PID a jméno bundlu — bez PIDu se k záznamu nedohledá `sample` a bez jména
    /// není poznat, který slot to psal (#228).
    @Test("Hlavička nese bundle, PID a jak se to vypne")
    func header() {
        #expect(Policy.diagnosticHeaderLine(at: moment, in: .gmt, bundle: "PRism-a", pid: 4242)
            == "2025-08-19T10:40:00Z diagnostika kreslení ZAPNUTÁ (PRISM_DIAGNOSE=1),"
            + " PRism-a pid 4242 — vypne se restartem bez toho přepínače")
    }

    /// Dosažený strop se **napíše**: soubor, který prostě přestane růst, se nedá odlišit od
    /// aplikace, která přestala hořet.
    @Test("Vyčerpaný strop je v souboru vidět")
    func limitLine() {
        #expect(Policy.diagnosticLimitLine(at: moment, in: .gmt, bytes: 1024)
            == "2025-08-19T10:40:00Z strop 1024 B vyčerpán, dál se nezapisuje — restartuj aplikaci")
    }
}
