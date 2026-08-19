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
