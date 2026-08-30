import CoreGraphics
import Testing

@testable import PRism

/// Rozhodnutí o kolečku nad terminálem (#478) — **výčtem, jako každé `Policy`**.
///
/// Odpovídá na tři otázky, které se v ploše samé ověřit nedají bez pty: **hlásit, nebo rolovat?**,
/// **kolikrát?** a **kde výřez zůstane, když pod ním přiteče výstup?**
@Suite("Kolečko nad terminálem (#478)")
struct TerminalWheelPolicyTests {
    // MARK: - Hlásit, nebo rolovat

    /// **Vypnuté hlášení myši znamená `nil`, ať se kolečkem točí jakkoli.** Je to ta půlka, která
    /// se rozbije potichu: kdyby se hlásilo i do shellu, přišel by `zsh` o rolování historie a na
    /// obrazovce by z toho byly znaky `<64;1;1M` na promptu.
    @Test("Když aplikace o myš nestojí, nehlásí se nic")
    func silentWhenTheAppDoesNotAsk() {
        for delta in [-12.0, -3.0, -1.0, 1.0, 3.0, 12.0] as [CGFloat] {
            #expect(Policy.terminalWheelReport(deltaY: delta, reportsMouse: false, rows: 24) == nil)
        }
    }

    @Test("Nahoru je tlačítko 4, dolů 5")
    func directionPicksTheButton() {
        let up = Policy.terminalWheelReport(deltaY: 3, reportsMouse: true, rows: 24)
        let down = Policy.terminalWheelReport(deltaY: -3, reportsMouse: true, rows: 24)
        #expect(up?.button == 4)
        #expect(down?.button == 5)
        #expect(up?.button == Policy.terminalWheelUpButton)
        #expect(down?.button == Policy.terminalWheelDownButton)
    }

    /// **Nula se nehlásí.** Trackpad umí poslat událost s nulovým posunem (dojezd setrvačnosti)
    /// a hlášení z ní by v aplikaci bylo cvaknutí, které nikdo neudělal. Knihovna se na nule
    /// vrací taky (`if event.deltaY == 0 { return }`), takže se tím nic nerozchází.
    @Test("Nulová a nekonečná otočka se nehlásí")
    func nothingIsReportedForNoMovement() {
        #expect(Policy.terminalWheelReport(deltaY: 0, reportsMouse: true, rows: 24) == nil)
        #expect(Policy.terminalWheelReport(deltaY: .nan, reportsMouse: true, rows: 24) == nil)
        #expect(Policy.terminalWheelReport(deltaY: .infinity, reportsMouse: true, rows: 24) == nil)
        #expect(Policy.terminalWheelReport(deltaY: -.infinity, reportsMouse: true, rows: 24) == nil)
    }

    // MARK: - Kolikrát

    /// Křivka **opsaná ze `SwiftTermu`** (`calcScrollingVelocity`, `private`). Že se s knihovnou
    /// nerozešla, hlídá `TerminalWheelTests.theCurveStillMatchesTheLibrary` — tohle je ta druhá
    /// půlka: že ji čteme tak, jak je napsaná, včetně hranic mezi stupni.
    ///
    /// **Stupeň se určuje z celé části, ne ze zaokrouhlení** (`Int(abs(deltaY))`, jako v knihovně),
    /// takže `1,9` je pořád jeden řádek a `5,9` tři. Je to vidět v tabulce schválně: kdyby se to
    /// jednou opravilo na zaokrouhlení, rozejde se to s knihovnou a rolování bude v `claude` jinak
    /// rychlé než v shellu vedle.
    @Test(
        "Počet řádků na otočku jde po stupních 1 / 3 / 10 / stránka",
        arguments: [
            (0.0, 1), (0.5, 1), (1.0, 1), (1.9, 1),
            (2.0, 3), (5.0, 3), (5.9, 3),
            (6.0, 10), (9.0, 10), (9.9, 10),
            (10.0, 24), (100.0, 24),
        ] as [(CGFloat, Int)]
    )
    func theCurveGoesInSteps(delta: CGFloat, lines: Int) {
        #expect(Policy.terminalWheelLines(deltaY: delta, rows: 24) == lines)
        // Znaménko o počtu nerozhoduje — jen o směru.
        #expect(Policy.terminalWheelLines(deltaY: -delta, rows: 24) == lines)
    }

    /// **Nejvyšší stupeň je stránka, ale nejmíň dvacet řádků.** Na nízké ploše (zásuvka umí být
    /// vysoká pár řádků) by „o stránku“ znamenalo skoro nic.
    @Test("Nejvyšší stupeň je stránka, s podlahou na dvaceti řádcích")
    func theTopStepIsAPage() {
        #expect(Policy.terminalWheelLines(deltaY: 12, rows: 60) == 60)
        #expect(Policy.terminalWheelLines(deltaY: 12, rows: 20) == 20)
        #expect(Policy.terminalWheelLines(deltaY: 12, rows: 5) == 20)
    }

    /// Počet v hlášení je **tentýž počet**, o kolik by se posunula historie — jinak by se táž
    /// otočka chovala v `claude` jinak rychle než v `zsh` vedle.
    @Test("Hlášení nese tolik cvaknutí, o kolik řádků by se rolovalo")
    func theReportCarriesTheSameCount() {
        for delta in [1.0, 3.0, 7.0, 20.0] as [CGFloat] {
            let report = Policy.terminalWheelReport(deltaY: delta, reportsMouse: true, rows: 30)
            #expect(report?.count == Policy.terminalWheelLines(deltaY: delta, rows: 30))
        }
    }

    // MARK: - Kde výřez zůstane

    /// **Dole se nezaklesává** — tam je „jet s výstupem“ ta správná odpověď a zaklesnutí se ruší
    /// právě tím, že se člověk vrátí úplně dolů.
    @Test("Výřez se zaklesne jedině mimo dno")
    func onlyAScrolledViewportPins() {
        #expect(Policy.terminalViewportPin(row: 120, atBottom: false) == 120)
        #expect(Policy.terminalViewportPin(row: 0, atBottom: false) == 0)
        #expect(Policy.terminalViewportPin(row: 120, atBottom: true) == nil)
    }

    /// **Vrací se jen dolů → nahoru.** Výřez nad zaklesnutým řádkem znamená, že se mezitím
    /// rolovalo, a ta poloha je novější než uložená — přebít ji by bylo, jako by kolečko
    /// nefungovalo podruhé.
    @Test("Zpátky se výřez vrací jen o to, co ho výstup stáhl")
    func theRewindOnlyUndoesTheSnap() {
        #expect(Policy.terminalViewportRewind(pinned: nil, current: 500) == 0)
        #expect(Policy.terminalViewportRewind(pinned: 100, current: 140) == 40)
        #expect(Policy.terminalViewportRewind(pinned: 100, current: 100) == 0)
        #expect(Policy.terminalViewportRewind(pinned: 100, current: 60) == 0)
    }
}
