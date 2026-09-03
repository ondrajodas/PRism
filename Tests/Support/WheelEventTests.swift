import AppKit
import CoreGraphics
import Foundation
import SwiftTerm
import Testing

@testable import PRism

/// **Stráž nad zdrojáky, ne nad během** (#490) — tatáž konstrukce jako `UnanimatedWindowTests`,
/// `GlobalAppearanceTests` a `SingleWayOutTests`.
///
/// Za běhu se to tvrdit nedá, a je to celý důvod, proč je stráž nad zdrojáky: událost složená
/// s `nil` zdrojem má **prázdné** `flags` ve chvíli, kdy nikdo nic nedrží, tedy skoro vždycky.
/// Test „složená událost nemá modifikátory“ by proto zezelenal nad rozbitou i opravenou verzí
/// a netvrdil by nic (#478). Zato se dá přečíst ze zdrojáků, **kdo událost skládá**.
///
/// K tomu jsou tady dva testy, které měří to druhé: **co zděděný modifikátor doopravdy udělá.**
/// Bez nich by stráž byla pravidlo bez ceny — je z nich vidět, že rozdíl mezi „drží se klávesa“
/// a „nedrží“ je rozdíl mezi zeleným a červeným `main`em.
@MainActor
@Suite("Události skládané pro test nedědí živý stav (#490)")
struct WheelEventTests {
    private static let tests = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Dva soubory, které se odečítají: sám helper (jeho obsah **je** ta jediná povolená cesta)
    /// a tahle stráž, kde zakázaný vzor stojí jako literál. Prefix `WheelEvent` sedne na oba
    /// a je proto i v grepu v `CLAUDE.md`.
    private static let exempt = ["Support/WheelEvent.swift", "Support/WheelEventTests.swift"]

    /// Jediný vzor, a je to celý konstruktor `CGEvent`u, ne jen ten scrollovací. Všechny jeho
    /// varianty berou zdroj a **`nil` u každé z nich znamená živý stav sezení**, takže se ta cesta
    /// zavírá naráz. Explicitní továrny AppKitu (`NSEvent.keyEvent(with:…)`) v tom nejsou: ty si
    /// modifikátory berou z argumentu, takže nemají odkud dědit.
    ///
    /// **Bez mezery za jménem** — hledá se v `condensed`, takže `CGEvent (…)` neuteče.
    private static let forbidden = "CGEvent("

    @Test("Žádný test neskládá `CGEvent` mimo `WheelEvent`")
    func composesEventsOnlyThroughTheHelper() throws {
        var offenders: [String] = []
        for source in try Self.sources() where !Self.exempt.contains(source.path) {
            if source.condensed.contains(Self.forbidden) { offenders.append(source.path) }
        }
        #expect(
            offenders.isEmpty,
            """
            `CGEvent` složený v testu si stav vstupu domýšlí ze živého systému (#490) — s `nil` \
            zdrojem přebere modifikátory, které měl člověk v tu sekundu zmáčknuté. Skládej ho \
            přes `WheelEvent`. Nálezy: \(offenders.sorted().joined(separator: ", "))
            """
        )
    }

    /// **Ani helper nesmí `nil` zdroj podstrčit.** Bez tohohle tvrzení by se pravidlo dalo splnit
    /// tím, že se rozbitá cesta přestěhuje do jediného povoleného souboru.
    ///
    /// **Hledá se v kódu bez mezer**, a je to nález Copilota na tomhle PR: `Source: nil` jako
    /// substring jde obejít pouhým přeformátováním (`Source:nil`, nebo zalomení za dvojtečkou),
    /// takže by stráž zezelenala nad tou chybou, na kterou je. Ve Swiftu je mezera uvnitř volání
    /// volná, takže **jakákoli stráž nad zdrojákem musí porovnávat text bez ní**.
    @Test("Helper skládá událost z privátního zdroje a modifikátory nasazuje sám")
    func theHelperNeverPassesANilSource() throws {
        let sources = try Self.sources()
        let helper = try #require(
            sources.first { $0.path == "Support/WheelEvent.swift" },
            "helper se nenašel"
        )
        // **Do `Bool`u schválně**: `#expect` vypíše celý výraz, a to by u `condensed` byl celý
        // slepený zdroják v hlášce. Rozhodnutí je v proměnné, důvod v textu.
        let passesNilSource = helper.condensed.contains("Source:nil")
        let takesPrivateState = helper.condensed.contains("stateID:.privateState")
        let assignsFlags = helper.condensed.contains("wheel.flags=modifiers")
        #expect(!passesNilSource, "helper podstrkuje `nil` zdroj")
        #expect(takesPrivateState, "helper nebere privátní stav")
        #expect(assignsFlags, "helper nenasazuje `flags` z argumentu")
    }

    /// Pojistka proti tomu, aby stráž zezelenala tím, že přestane číst nebo přestane hledat.
    @Test("Stráž doopravdy čte zdrojáky testů a vzor na nich sedí")
    func readsTheTestSources() throws {
        let sources = try Self.sources()
        #expect(sources.count > 100, "Čekaly se stovky zdrojáků, přišlo \(sources.count).")
        let helper = try #require(sources.first { $0.path == "Support/WheelEvent.swift" })
        #expect(
            helper.condensed.contains(Self.forbidden),
            "V helperu nesedl hledaný vzor — stráž hledá něco, co v kódu není."
        )
        // A že se doopravdy zahazují **mezery**, ne jen řádky s komentářem: helper má za dvojtečkou
        // mezeru, takže bez toho zahození by `stateID:.privateState` nesedlo nikde.
        let hasWhitespace = helper.condensed.contains(where: { $0.isWhitespace })
        #expect(!hasWhitespace, "v `condensed` zůstaly mezery")
    }

    // MARK: - Kdyby ta klávesa doopravdy držela

    /// **Naměřilo by to rozdíl, kdyby ta chyba byla?** (#478) Tady je odpověď: `Control` v `flags`
    /// přebarví tlačítko z 64 na 80 — tedy přesně to tvrzení, které v `TerminalWheelTests` padalo.
    ///
    /// Zároveň je to tvrzení o aplikaci, které stojí za to mít: modifikátory **patří** do hlášení
    /// myši (`encodeButton` je bere), takže se na tuhle cestu nesmí sáhnout bez povšimnutí.
    @Test("Zděděný Control by z tlačítka 64 udělal 80")
    func aHeldControlWouldChangeTheButton() throws {
        let plain = Self.surface()
        plain.handle(wheel: try WheelEvent.line(lines: 3))
        let control = Self.surface()
        control.handle(wheel: try WheelEvent.line(lines: 3, modifiers: .maskControl))
        let option = Self.surface()
        option.handle(wheel: try WheelEvent.line(lines: 3, modifiers: .maskAlternate))

        #expect(plain.text.hasPrefix("\u{1B}[<64;"), "bez modifikátoru: \(plain.escaped)")
        #expect(control.text.hasPrefix("\u{1B}[<80;"), "s Controlem: \(control.escaped)")
        #expect(option.text.hasPrefix("\u{1B}[<72;"), "s Optionem: \(option.escaped)")
    }

    /// A tohle je ta druhá polovina, kvůli které padala **`TerminalScrollProbe`**: se `Shift`em
    /// překlopí AppKit osu, takže `deltaY` je nula a delta leží v `deltaX`. Knihovní `scrollWheel`
    /// pak skončí na prvním `if` (výřezem se nepohne) a `Policy.terminalWheelReport` nedostane, co
    /// by hlásila — v obou suitách to vypadá jako „kolečko nefunguje“.
    ///
    /// **Není to tvrzení o naší kresbě**, je to tvrzení o AppKitu: kdyby ten překlop přestal dělat,
    /// tenhle test spadne a pravidlo o dědění tím neztratí platnost — jen mu ubude jeden projev.
    @Test("Zděděný Shift překlopí osu, takže se nepohne výřez ani nic nehlásí")
    func aHeldShiftWouldSwapTheAxis() throws {
        let event = try WheelEvent.line(lines: 3, modifiers: .maskShift)
        #expect(event.deltaY == 0, "AppKit osu nepřeklopil: deltaY \(event.deltaY)")
        #expect(event.deltaX == 3, "delta neskončila na ose X: deltaX \(event.deltaX)")

        let scrolled = Self.surface(reportsMouse: false)
        let before = scrolled.terminal.buffer.yDisp
        scrolled.scrollWheel(with: event)
        #expect(scrolled.terminal.buffer.yDisp == before, "výřez se přesto pohnul")

        let reporting = Self.surface()
        reporting.handle(wheel: event)
        #expect(reporting.sent.isEmpty, "něco se přesto ohlásilo: \(reporting.escaped)")
    }

    // MARK: - Scéna

    /// Ploška se 400 nakrmenými řádky, výřez na dně. `reportsMouse` zapíná hlášení **toutéž**
    /// sekvencí, jakou pošle `claude` (`ESC[?1000h`, `ESC[?1006h`).
    private static func surface(reportsMouse: Bool = true) -> RecordingWheelView {
        let view = RecordingWheelView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        view.font = TerminalHost.font
        view.feed(text: (1...400).map { "radek \($0)\r\n" }.joined())
        if reportsMouse {
            view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
            // Bez tohohle tvrzení by se „nic neodešlo“ dalo splnit i tím, že si emulátor o myš
            // vůbec neřekl — a test o modifikátorech by pak zelenal nad nezapnutým hlášením.
            #expect(view.terminal.mouseMode != .off, "emulátor si o myš neřekl")
        }
        view.sent.removeAll()
        return view
    }

    private struct Source {
        let path: String

        /// Kód **bez jediné mezery a bez zalomení**. Hledá se nad tímhle, protože ve Swiftu je
        /// mezera uvnitř volání volná: `CGEvent (…)` i `Source:\n    nil` jsou platný zápis téhož,
        /// takže stráž nad surovým textem by je pustila (nález Copilota na #490).
        ///
        /// **Uložený, ne počítaný** (#550) — jeden průchod přes 518 zdrojáků (5,1 MB) stojí 0,23 s
        /// v optimalizovaném buildu, takže se zhušťuje **jednou při čtení**, ne při každém dotazu.
        /// Surový text se nedrží: nikdo ho tady nečte. Tři stráže z #550 mají tentýž tvar.
        let condensed: String

        /// `code` je kód **bez řádkových komentářů** — bez toho by stráž zakazovala i to, aby se
        /// pravidlo v komentáři vysvětlilo.
        init(path: String, code: String) {
            self.path = path
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

    private static func sources() throws -> [Source] {
        guard let walker = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil) else {
            throw SourceReadError.unreadable(tests.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: tests.path + "/", with: ""),
                    code: lines.joined(separator: "\n")
                )
            )
        }
        return files
    }

    private enum SourceReadError: Error {
        case unreadable(String)
    }
}

/// Ploška, která si zapamatuje, co odešlo do procesu — totéž, co `TerminalWheelTests`, ale ta svou
/// podtřídu má `private`, takže se odsud brát nedá.
@MainActor
private final class RecordingWheelView: EmbeddedTerminalView {
    var sent: [UInt8] = []

    var text: String { String(decoding: sent, as: UTF8.self) }

    /// Totéž, ale s viditelným `ESC` — do hlášky v testu.
    var escaped: String { text.replacingOccurrences(of: "\u{1B}", with: "^[") }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }
}
