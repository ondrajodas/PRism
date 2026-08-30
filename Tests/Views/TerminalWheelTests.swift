import AppKit
import CoreGraphics
import SwiftTerm
import Testing

@testable import PRism

/// Kolečko v zásuvce (#478) — **co jde tvrdit bez pty**.
///
/// Bez pty se nedá spustit `claude` a nedá se přečíst, co doopravdy odešlo do procesu. Dá se ale
/// obojí obejít: emulátor se přepne do hlášení myši **tou samou sekvencí**, jakou pošle `claude`
/// (`ESC[?1000h` a `ESC[?1006h`), a to, co jde z plochy ven, se přečte z podtřídy, která si přepíše
/// `send(source:data:)`. Zbývá jedna věc, kterou tady ověřit nejde a **dělá to člověk**: že se
/// událost k téhle metodě doopravdy dostane, protože odběr událostí testovací host nerozpohybuje.
///
/// Tvrzení jsou čtyři a každé je jiná půlka problému z #478:
///
/// 1. **Při zapnutém hlášení se událost pošle** a tolikrát, kolik je řádků.
/// 2. **Při vypnutém se nepošle nic** a roluje se historie — v holém shellu se nesmělo nic změnit.
/// 3. **Křivka rychlosti se s knihovnou nerozešla** (opsaná `calcScrollingVelocity` je `private`).
/// 4. **Odrolovaný pohled přiteklý výstup nesrovná dolů** — druhá půlka „nejde rolovat“.
@MainActor
@Suite("Kolečko v zásuvce (#478)")
struct TerminalWheelTests {
    // MARK: - Hlásit, nebo rolovat

    /// **To tvrzení, kvůli kterému #478 vzniklo.** Knihovna kolečko aplikaci nepředá nikdy, takže
    /// `claude` o něm nevěděl — tady se ověřuje, že se pod zapnutým hlášením myši ozve.
    @Test("Aplikace, která si řekla o myš, dostane kolečko")
    func theWheelReachesAnAppThatAskedForIt() throws {
        let view = Self.surface()
        Self.enableMouseReporting(in: view)
        view.sent.removeAll()

        view.handle(wheel: try Self.wheel(lines: 3))

        #expect(!view.text.isEmpty, "aplikaci nepřišlo nic")
        #expect(view.text.hasPrefix("\u{1B}[<64;"), "nepřišlo hlášení kolečka: \(view.escaped)")
    }

    /// **A tohle je to tvrzení, které se rozbije potichu**: kdyby se hlásilo i tehdy, když o myš
    /// nikdo nestojí, objevily by se v `zsh` na promptu znaky místo rolování.
    @Test("Do shellu, který o myš nestojí, se nepošle nic")
    func nothingIsSentWhenTheAppDoesNotAsk() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        view.sent.removeAll()

        let before = view.terminal.buffer.yDisp
        view.handle(wheel: try Self.wheel(lines: 3))

        #expect(view.sent.isEmpty, "do procesu odešlo \(view.escaped)")
        #expect(view.terminal.buffer.yDisp < before, "místo hlášení se nerolovalo: \(before)")
    }

    /// Směr je **v čísle tlačítka**, ne ve znaménku souřadnice: `4` nahoru, `5` dolů (`xterm`).
    @Test("Nahoru je tlačítko 64, dolů 65")
    func theDirectionIsInTheButton() throws {
        let up = Self.surface()
        Self.enableMouseReporting(in: up)
        up.sent.removeAll()
        up.handle(wheel: try Self.wheel(lines: 1))

        let down = Self.surface()
        Self.enableMouseReporting(in: down)
        down.sent.removeAll()
        down.handle(wheel: try Self.wheel(lines: -1))

        #expect(up.text.hasPrefix("\u{1B}[<64;"), "nahoru: \(up.escaped)")
        #expect(down.text.hasPrefix("\u{1B}[<65;"), "dolů: \(down.escaped)")
    }

    /// **Rychlost je v počtu hlášení**, protože jedno hlášení nese jen „cvaklo“. Kdyby se posílalo
    /// jedno na událost, rolovalo by se v `claude` o řádek na otočku, kdežto v shellu vedle po
    /// trojicích — dvě různé rychlosti v jedné ploše.
    @Test("Hlášení odejde tolikrát, o kolik řádků by se rolovalo", arguments: [1, 3, 7, 12])
    func theReportRepeatsAsManyTimesAsLines(lines: Int) throws {
        let view = Self.surface()
        Self.enableMouseReporting(in: view)
        view.sent.removeAll()

        view.handle(wheel: try Self.wheel(lines: Int32(lines)))

        let wanted = Policy.terminalWheelLines(deltaY: CGFloat(lines), rows: view.terminal.rows)
        let reports = view.text.components(separatedBy: "\u{1B}[<").count - 1
        #expect(reports == wanted, "\(lines) řádků → \(reports) hlášení místo \(wanted)")
    }

    /// **V normálním bufferu se pod zapnutým hlášením historií nehne.** Kdyby se dělalo obojí,
    /// odrolovalo by se pod aplikací, která si o kolečko řekla — a ta by kreslila do výřezu, na
    /// který se nikdo nedívá.
    @Test("Když se hlásí, vlastní historie se nepohne")
    func reportingDoesNotAlsoScrollHistory() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        Self.enableMouseReporting(in: view)
        view.sent.removeAll()

        let before = view.terminal.buffer.yDisp
        view.handle(wheel: try Self.wheel(lines: 3))

        #expect(view.terminal.buffer.yDisp == before)
        #expect(!view.sent.isEmpty)
    }

    // MARK: - Křivka rychlosti

    /// **Opsaná křivka se s knihovnou umí rozejít potichu.** `calcScrollingVelocity` je `private`,
    /// takže se porovnává **chováním**: knihovní `scrollWheel` se pustí napřímo a změří se, o kolik
    /// se výřez posunul. Musí to být totéž číslo, jaké vydá `Policy` — jinak by po zapnutí hlášení
    /// myši jela tatáž otočka jinak rychle.
    @Test("Naše křivka rychlosti je pořád ta knihovní", arguments: [1, 3, 7, 12])
    func theCurveStillMatchesTheLibrary(lines: Int) throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        // Napřed na dno, ať se posun nezarazí o strop bufferu a neměřila se místo křivky mez.
        view.scrollDown(lines: 1000)

        let before = view.terminal.buffer.yDisp
        view.scrollWheel(with: try Self.wheel(lines: Int32(lines)))
        let moved = before - view.terminal.buffer.yDisp

        let wanted = Policy.terminalWheelLines(deltaY: CGFloat(lines), rows: view.terminal.rows)
        #expect(moved == wanted, "knihovna rolovala o \(moved), `Policy` čeká \(wanted)")
    }

    // MARK: - Kde výřez zůstane

    /// **Měření chyby v knihovně, ne našeho kódu** (#478, druhá půlka). `Terminal.userScrolling` se
    /// v `1.11.2` čte na třech místech a **nezapisuje se do něj z jediného** — `AppleTerminalView`
    /// sice `userScrolling` nastavuje, jenže to je stejnojmenná vlastnost **plochy**, kterou zase
    /// nikdo nečte. Tenhle test to tvrdí chováním: bez naší kompenzace srovná každý přiteklý řádek
    /// výřez na dno.
    ///
    /// **Kdyby zezelenal opačně**, tedy že výřez zůstal, je to zpráva o tom, že knihovna svou chybu
    /// opravila — a naše kompenzace v `dataReceived` může jít pryč.
    @Test("Bez kompenzace srovná knihovna výřez dolů na každý přiteklý řádek")
    func theLibrarySnapsTheViewportBack() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        view.scrollUp(lines: 20)
        #expect(view.scrollPosition < 1, "nerolovalo se, není co měřit")

        // **`feed` schválně, ne `dataReceived`**: jde o knihovnu samotnou, tedy o cestu bez naší
        // kompenzace. Ta se měří o test níž.
        view.feed(text: "dalsi radek\r\n")

        #expect(
            view.scrollPosition >= 1,
            "knihovna výřez nesrovnala — `Terminal.userScrolling` se možná začal nastavovat"
        )
    }

    /// A tohle je ta kompenzace: **výstup z pty** odrolovaný pohled nechá být.
    @Test("Odrolovaný pohled zůstane, i když pod ním přiteče výstup")
    func aScrolledViewportSurvivesOutput() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        view.handle(wheel: try Self.wheel(lines: 3))
        let scrolled = view.terminal.buffer.yDisp
        #expect(view.scrollPosition < 1, "nerolovalo se, není co měřit")

        view.dataReceived(slice: Array("dalsi radek\r\n".utf8)[...])

        #expect(view.terminal.buffer.yDisp == scrolled, "výřez ujel na \(view.terminal.buffer.yDisp)")
    }

    /// **Dole zaklesnutí není**, takže výstup rovnou plyne dál — to je ta správná odpověď a musí
    /// zůstat i po opravě.
    @Test("Pohled na dně jede s výstupem dál")
    func theBottomKeepsFollowing() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())

        view.dataReceived(slice: Array("dalsi radek\r\n".utf8)[...])

        #expect(view.scrollPosition >= 1)
    }

    /// **Start a konec celoobrazovkového TUI zaklesnutí zahodí.** Bez toho by poloha z doby před
    /// `claude` ožila ve chvíli, kdy se člověk vrátí do shellu — a výřez by se sám odrolil nahoru.
    @Test("Průchod alternativním bufferem zaklesnutí zahodí")
    func theAlternateBufferDropsThePin() throws {
        let view = Self.surface()
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        view.handle(wheel: try Self.wheel(lines: 3))
        #expect(view.scrollPosition < 1, "nerolovalo se")

        // Přesně to, co pošle `claude` při startu a při odchodu.
        view.feed(text: "\u{1B}[?1049h")
        view.feed(text: "\u{1B}[?1049l")
        view.dataReceived(slice: Array("dalsi radek\r\n".utf8)[...])

        #expect(
            view.scrollPosition >= 1,
            "zaklesnutí přežilo alternativní buffer a odrolovalo výřez zpátky nahoru"
        )
    }

    // MARK: - Scéna

    private static func surface() -> RecordingTerminalView {
        let view = RecordingTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        return view
    }

    /// Tytéž dvě sekvence, jakými si o myš řekne `claude`: `1000` je hlášení tlačítek, `1006`
    /// čitelné kódování `SGR` (bez něj by hlášení byly netisknutelné bajty).
    private static func enableMouseReporting(in view: RecordingTerminalView) {
        view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
        #expect(view.terminal.mouseMode != .off, "emulátor si o myš neřekl")
    }

    /// Klasické kolečko (ne trackpad): `deltaY` v řádcích. Kladné je nahoru.
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

/// Plocha, která si zapamatuje, co odešlo do procesu.
///
/// **`send(source:data:)` je jediná cesta ven z emulátoru** — `Terminal.sendEvent` skončí přes
/// `sendResponse` právě tady —, takže přepsat ji znamená přečíst si hlášení myši bez pty.
/// **Bez `super`**, a je to podmínka: `LocalProcessTerminalView.send` píše do `process`, který
/// v testu neběží.
@MainActor
private final class RecordingTerminalView: EmbeddedTerminalView {
    var sent: [UInt8] = []

    var text: String { String(decoding: sent, as: UTF8.self) }

    /// Totéž, ale s viditelným `ESC` — do hlášky v testu.
    var escaped: String { text.replacingOccurrences(of: "\u{1B}", with: "^[") }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }
}
