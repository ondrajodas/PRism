import AppKit
import SwiftTerm
import SwiftUI
import Testing

@testable import PRism

/// Sonda rolování v zásuvce (#460) — **rozlišuje tři různé „nejde scrollovat“**.
///
/// Vznikla na hlášení „nejde mi scrollovat v tom terminálu“. Odpověď se rozpadá na tři otázky
/// a **každá znamená jinou opravu**, takže se měří zvlášť:
///
/// 1. **Dostane se kolečko k emulátoru?** Zásuvka je zanořená ve SwiftUI, takže událost může
///    spolknout něco nad ní. Měří se `hitTest` na ploše zásuvky — `scrollWheel` dostane view pod
///    kurzorem, takže tohle je ta otázka doslova.
/// 2. **Má čím rolovat?** Scrollback `SwiftTermu` je nastavitelný a nula by znamenala, že není kam
///    couvnout. Měří se skutečnou hodnotou po nakrmení emulátoru, ne z dokumentace.
/// 3. **Neběží tam celoobrazovkové TUI?** V alternativním bufferu (do kterého kreslí `claude`)
///    scrollback **schválně není** a kolečko nedělá nic — tam je „nejde rolovat“ **správné
///    chování** a roluje se uvnitř té aplikace.
///
/// Poslední bod je celý důvod, proč sonda existuje: bez něj by se to opravovalo tam, kde je to
/// v pořádku.
@MainActor
@Suite("Sonda rolování v zásuvce (#460)")
struct TerminalScrollProbe {
    private let slot = TerminalSlot(pullRequest: PRIdentifier("cli/cli#42")!, role: .shell)

    /// **Kdo dostane kolečko.** Kdyby ho bral `ScrollView` diffu nebo obal zásuvky, terminál by
    /// o něm nevěděl — a to je úplně jiná oprava než chybějící scrollback.
    ///
    /// **Měří se v okně, ne nad holým `NSHostingView`** (#462 pro způsob ukázání): bez okna
    /// SwiftUI hostitele nedostaví do stavu, ve kterém se hit test chová jako za běhu — změřeno,
    /// že tam `hitTest` vrátí kořen a plochu emulátoru vůbec nenajde, přestože v hierarchii je.
    @Test("Kolečko nad zásuvkou padne na plochu emulátoru")
    func theWheelLandsOnTheEmulator() throws {
        let host = ProbeScrollHost()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: drawer(host: host))
        window.contentView = hosting
        window.orderFrontUnanimated()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        let surface = try #require(host.made)

        // Bod uprostřed plochy emulátoru, převedený do souřadnic hostitele. `hitTest` bere bod
        // v souřadnicích **nadřazeného** view, a `hosting` je `contentView`, takže sedí.
        let middle = surface.convert(
            CGPoint(x: surface.bounds.midX, y: surface.bounds.midY),
            to: hosting
        )
        let hit = hosting.hitTest(middle)
        print("SONDA hitTest v bodě \(middle) → \(type(of: hit as Any))")
        print("SONDA plocha \(surface.frame) v okně \(surface.convert(surface.bounds, to: nil))")

        let terminalUnderCursor = sequence(first: hit, next: { $0?.superview })
            .contains { $0 === surface }
        #expect(terminalUnderCursor, "kolečko by dostal někdo jiný než emulátor")
    }

    /// **Má čím rolovat.** Scrollback se měří tím, že se emulátor nakrmí víc řádky, než se vejde
    /// na plochu, a pošle se mu kolečko — `yDisp` je pozice výřezu v bufferu.
    @Test("V shellu s dlouhým výpisem kolečko rolovat umí")
    func theNormalBufferScrolls() throws {
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())

        let before = view.terminal.buffer.yDisp
        view.scrollWheel(with: try Self.wheel(lines: 3))
        let after = view.terminal.buffer.yDisp
        print("SONDA scrollback \(view.terminal.options.scrollback) řádků, yDisp \(before) → \(after)")

        #expect(view.terminal.options.scrollback > 0, "emulátor nemá scrollback vůbec")
        #expect(after < before, "kolečko výřezem nehnulo: \(before) → \(after)")
    }

    /// **A tady „nejde rolovat“ znamená, že je všechno v pořádku.** `claude` kreslí do
    /// alternativního bufferu (`ESC[?1049h`), který scrollback **nemá** — kolečko proto nedělá nic
    /// a rolovat se má uvnitř té aplikace. Přesně tak se chová `Terminal.app` i `iTerm`.
    @Test("Nad celoobrazovkovým TUI kolečko schválně nedělá nic")
    func thealternateBufferDoesNotScroll() throws {
        let view = EmbeddedTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        // Přepnutí do alternativního bufferu — tohle pošle každé celoobrazovkové TUI, když startuje.
        view.feed(text: "\u{1B}[?1049h")

        let before = view.terminal.buffer.yDisp
        view.scrollWheel(with: try Self.wheel(lines: 3))
        let after = view.terminal.buffer.yDisp
        print("SONDA alternativní buffer: yDisp \(before) → \(after)")

        #expect(view.terminal.isCurrentBufferAlternate, "nepřepnulo se do alternativního bufferu")
        #expect(after == before, "alternativní buffer se posunul, což by byla chyba emulátoru")
    }

    // MARK: - Scéna

    private func drawer(host: any TerminalHosting) -> some View {
        TerminalDrawerView(
            rows: Policy.terminalSlotRows([slot], active: slot, states: [slot: .running]),
            activeSlot: slot,
            directory: FileManager.default.temporaryDirectory,
            host: host,
            available: 420,
            select: { _ in },
            close: {}
        )
    }

    /// Klasické kolečko (ne trackpad): `scrollingDeltaY` v řádcích.
    private static func wheel(lines: Int32) throws -> NSEvent {
        let source = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: lines,
                wheel2: 0,
                wheel3: 0
            )
        )
        return try #require(NSEvent(cgEvent: source))
    }
}

/// Hostitel, který vyrobí skutečnou plochu emulátoru a zapamatuje si ji, ale žádný shell nespustí.
@MainActor
private final class ProbeScrollHost: TerminalHosting {
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
