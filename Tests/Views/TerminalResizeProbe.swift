import AppKit
import Darwin
import SwiftTerm
import SwiftUI
import Testing

@testable import PRism

/// Sonda změny velikosti zásuvky (#460) — **měří, co o rozměru ví emulátor a co jádro**.
///
/// Vznikla na hlášení „resize terminálu ne úplně funguje, asi se přeskládává text“ z #459.
/// Otázka se rozpadá na tři a každá se měří jinde:
///
/// 1. **Dojde nová šířka do emulátoru?** `terminal.cols` po rozvržení — stav, který `SwiftTerm`
///    mění **synchronně** v `setFrameSize`, takže na něj hladová hlavní fronta z #459 nedosáhne.
/// 2. **Dojde do jádra, a se správnými rozměry?** `TIOCGWINSZ` na master deskriptoru pty. Tohle
///    je ta půlka, kvůli které se `claude` uvnitř překreslí — `SIGWINCH` posílá jádro, ne emulátor.
/// 3. **Drží zásuvka výšku?** To je čistá funkce a je vyčerpaná v `TerminalDrawerTests`.
///
/// **Měří se přes `NSHostingView`, ne nad holým `EmbeddedTerminalView`**, a je to celý smysl:
/// mezi oknem a emulátorem stojí `TerminalSurface` (`NSViewRepresentable`) a rámec od SwiftUI.
/// Kdyby se rozměr ztrácel tam, sonda nad holým view by ho neviděla a hlásila by, že je čisto.
@MainActor
@Suite("Sonda změny velikosti zásuvky (#460)")
struct TerminalResizeProbe {
    private let slot = TerminalSlot(pullRequest: PRIdentifier("cli/cli#42")!, role: .shell)

    /// **Nejcennější tvrzení téhle sondy**: rozměr projde celou cestou okno → SwiftUI → emulátor.
    @Test("Šířka okna dojede přes SwiftUI až do emulátoru")
    func theWidthReachesTheEmulator() throws {
        let host = ProbeResizeHost()
        let hosting = NSHostingView(rootView: drawer(host: host))

        var measured: [(width: CGFloat, cols: Int, rows: Int)] = []
        for width in [1_200.0, 700.0, 1_000.0] as [CGFloat] {
            hosting.frame = CGRect(x: 0, y: 0, width: width, height: 460)
            hosting.layoutSubtreeIfNeeded()
            let view = try #require(host.made)
            measured.append((width, view.terminal.cols, view.terminal.rows))
        }
        for step in measured {
            print("SONDA šířka \(Int(step.width)) → \(step.cols)×\(step.rows) buněk")
        }

        let columns = measured.map(\.cols)
        #expect(columns[0] > columns[1], "zúžení okna sloupce nesrazilo: \(columns)")
        #expect(columns[2] > columns[1], "rozšíření zpátky sloupce nevrátilo: \(columns)")
        // Řádky drží výška zásuvky, ne šířka okna. Kdyby se hýbaly se šířkou, přesázel by se
        // obsah i tam, kde k tomu není důvod — a přesně tak vypadá „přeskládaný text“.
        #expect(Set(measured.map(\.rows)).count == 1, "řádky se hnuly se šířkou: \(measured.map(\.rows))")
    }

    /// Druhá půlka: co o rozměru ví **jádro**. Bez ní by první tvrzení mohlo platit a `claude`
    /// uvnitř by se stejně překreslil podle špatné šířky.
    ///
    /// **Se skutečným shellem**, takže jen pod `PRISM_MEASURE` — viz `EmbeddedTerminalProbe`.
    @Test(
        "Nová velikost dojede do jádra, a v buňkách i v pixelech",
        .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
    )
    func theKernelLearnsTheNewSize() throws {
        let directory = FileManager.default.temporaryDirectory
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        view.font = TerminalHost.font
        defer { view.kill() }
        view.start(in: directory)

        var measured: [(size: CGSize, cols: Int, rows: Int, kernel: winsize)] = []
        for size in [CGSize(width: 1_000, height: 300), CGSize(width: 600, height: 300)] {
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            measured.append(
                (size, view.terminal.cols, view.terminal.rows, Self.windowSize(of: view.process.childfd))
            )
        }
        for step in measured {
            print(
                "SONDA plocha \(Int(step.size.width))×\(Int(step.size.height)) → "
                    + "emulátor \(step.cols)×\(step.rows), jádro \(step.kernel.ws_col)×\(step.kernel.ws_row) "
                    + "buněk, \(step.kernel.ws_xpixel)×\(step.kernel.ws_ypixel) px"
            )
        }

        for step in measured {
            #expect(Int(step.kernel.ws_col) == step.cols, "jádro ví o jiné šířce než emulátor")
            #expect(Int(step.kernel.ws_row) == step.rows, "jádro ví o jiné výšce než emulátor")
            // Pixelové rozměry nejsou kosmetika: sixel i `kitty` protokol na nich stojí, a nula
            // v nich je stav, který se z okna nepozná.
            #expect(step.kernel.ws_xpixel > 0 && step.kernel.ws_ypixel > 0, "jádro nezná pixely")
        }
        #expect(measured[0].kernel.ws_col > measured[1].kernel.ws_col, "zúžení do jádra nedošlo")
    }

    /// Třetí otázka, kterou hlášení „přeskládává se text“ otevírá: **neposílá se to do jádra
    /// častěji, než se rozměr doopravdy mění?**
    ///
    /// Tažení za hranu okna vyrobí desítky `setFrameSize` na jeden bod, ale buňka je široká
    /// sedm — takže kdyby se `TIOCSWINSZ` posílalo na každý průchod, dostal by `claude` desítky
    /// `SIGWINCH` se **stejnou** velikostí a přesázel by se pokaždé. Sonda projede pásmo po
    /// jednom bodu a spočítá, kolikrát se odpověď jádra doopravdy změnila.
    @Test(
        "Do jádra jde jen skutečná změna, ne každý průchod rozvržení",
        .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
    )
    func onlyRealChangesReachTheKernel() throws {
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 700, height: 300))
        view.font = TerminalHost.font
        defer { view.kill() }
        view.start(in: FileManager.default.temporaryDirectory)

        var sizes: [UInt16] = []
        for width in stride(from: 700.0, through: 760.0, by: 1.0) {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 300)
            view.layoutSubtreeIfNeeded()
            sizes.append(Self.windowSize(of: view.process.childfd).ws_col)
        }
        let changes = zip(sizes, sizes.dropFirst()).count { $0 != $1 }
        print("SONDA 61 průchodů rozvržení přes 60 bodů → \(changes) změn šířky v jádře")
        print("SONDA šířky v jádře: \(Array(Set(sizes)).sorted())")

        // Buňka je široká ~7 bodů, takže na 60 bodech je změn řádově osm — ne šedesát.
        #expect(changes > 0, "za 60 bodů se šířka v jádře nezměnila ani jednou")
        #expect(changes < sizes.count / 2, "jádro dostalo změnu skoro na každý průchod: \(changes)")
    }

    // MARK: - Scéna

    private func drawer(host: any TerminalHosting) -> some View {
        TerminalDrawerView(
            rows: Policy.terminalSlotRows([slot], active: slot, states: [slot: .running]),
            activeSlot: slot,
            directory: FileManager.default.temporaryDirectory,
            host: host,
            available: 460,
            select: { _ in },
            close: {}
        )
    }

    private static func windowSize(of descriptor: Int32) -> winsize {
        var size = winsize()
        _ = ioctl(descriptor, TIOCGWINSZ, &size)
        return size
    }
}

/// Hostitel, který vyrobí **skutečnou plochu emulátoru** a zapamatuje si ji, ale žádný shell
/// nespustí. Rozměr do emulátoru dojde i bez procesu — `processSizeChange` na něm nezávisí.
@MainActor
private final class ProbeResizeHost: TerminalHosting {
    private(set) var made: EmbeddedTerminalView?

    var report: (@MainActor (TerminalSlot, TerminalRunState) -> Void)?
    var focusChanged: (@MainActor (Bool) -> Void)?
    var runningTerminals: Int { 0 }

    func terminal(for slot: TerminalSlot, in directory: URL) -> NSView {
        if let made { return made }
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        view.font = TerminalHost.font
        made = view
        return view
    }

    @discardableResult
    func run(
        _ commandLine: String,
        for slot: TerminalSlot,
        in directory: URL
    ) -> TerminalCommandOutcome { .noShell }

    @discardableResult func stopTerminal(for slot: TerminalSlot) -> Bool { false }
    @discardableResult func stopTerminals(for pr: PRIdentifier) -> Bool { false }
    func stopAllTerminals() {}
}
