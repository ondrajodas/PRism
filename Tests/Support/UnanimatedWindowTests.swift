import Foundation
import Testing

@testable import PRism

/// **Stráž nad zdrojáky, ne nad během** (#462) — tatáž konstrukce jako `GlobalAppearanceTests`
/// a `SingleWayOutTests`.
///
/// Za běhu se to tvrdit nedá: počet vláken procesu je vlastnost **celého** paralelního běhu, takže
/// by tvrzení o něm padalo podle toho, kdo běžel vedle — přesně ten falešně červený `main`, kvůli
/// kterému #367 zakázalo měřit globální stav procesu. Zato se dá přečíst ze zdrojáků, kdo okno
/// ukazuje; proč se ukazovat nemá, je u `NSWindow.orderFrontUnanimated()`.
///
/// Řádkové komentáře se zahazují, protože o `orderFront` se v dokumentaci mluví a vysvětlení nemá
/// být porušením pravidla, které vysvětluje.
@Suite("Okna v testech se objevují bez animace (#462)")
struct UnanimatedWindowTests {
    private static let tests = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Dva soubory, které se odečítají: sama stráž (zakázaná volání v ní stojí jako literály) a
    /// helper, jehož celý obsah je ta jediná povolená cesta. Prefix `UnanimatedWindow` je proto
    /// i v grepu v `CLAUDE.md` — sedne na oba.
    private static let exempt = ["Support/UnanimatedWindow.swift", "Support/UnanimatedWindowTests.swift"]

    /// Volání, kterými se okno ukáže s výchozí (tedy animovanou) `animationBehavior`. Bez tečky
    /// vpředu schválně: `orderFront(nil)` bez příjemce jde napsat i uvnitř podtřídy `NSWindow`.
    /// Jména helperů tím netrpí — `orderFrontUnanimated(` na `orderFront(` nesedne.
    ///
    /// **Bez mezery za jménem** — hledá se v `condensed`, takže `orderFront (nil)` neuteče (#550).
    private static let forbidden = ["orderFront(", "orderFrontRegardless(", "makeKeyAndOrderFront("]

    @Test("Žádný test neukazuje okno mimo `orderFrontUnanimated`")
    func showsWindowsOnlyThroughTheHelper() throws {
        var offenders: [String] = []
        for source in try Self.sources() where !Self.exempt.contains(source.path) {
            for call in Self.forbidden where source.condensed.contains(call) {
                offenders.append("\(source.path): \(call)")
            }
        }
        #expect(
            offenders.isEmpty,
            """
            Okno ukázané s výchozí `animationBehavior` si na dobu animace drží vlákno z globálního \
            dispatch poolu (#462). Použij `orderFrontUnanimated()`. Nálezy: \
            \(offenders.sorted().joined(separator: ", "))
            """
        )
    }

    /// Pojistka proti tomu, aby stráž zezelenala tím, že přestane číst nebo přestane hledat —
    /// kdyby se složka přejmenovala nebo `#filePath` přestal sedět, prošlo by nad prázdnem cokoli.
    ///
    /// Od #550 se tvrdí i to, že se v `condensed` doopravdy zahazují **mezery**: bez toho by stráž
    /// nad surovým textem propustila `orderFront (nil)`, tedy zezelenala právě nad tou chybou, na
    /// kterou je.
    @Test("Stráž doopravdy čte zdrojáky testů a vzory na nich sedí")
    func readsTheTestSources() throws {
        let sources = try Self.sources()
        #expect(sources.count > 100, "Čekaly se stovky zdrojáků, přišlo \(sources.count).")
        for path in Self.exempt {
            let exempt = try #require(sources.first { $0.path == path }, "\(path) se nenašel")
            #expect(
                Self.forbidden.contains { exempt.condensed.contains($0) },
                "V \(path) nesedl ani jeden hledaný vzor — stráž hledá něco, co v kódu není."
            )
            #expect(
                !exempt.condensed.contains(where: { $0.isWhitespace }),
                "v `condensed` u \(path) zůstaly mezery"
            )
        }
    }

    private struct Source {
        let path: String

        /// Kód **bez jediné mezery a bez zalomení** (#490, sem u #550). Hledá se nad tímhle, protože
        /// ve Swiftu je mezera uvnitř volání volná: `orderFront (nil)` i `orderFront(\n nil)` jsou
        /// platný zápis téhož.
        ///
        /// **Uložený, ne počítaný**, a je to změřené: jeden průchod přes 518 zdrojáků (5,1 MB) stojí
        /// 0,23 s v optimalizovaném buildu, takže tři vzory `forbidden` čtené z computed property
        /// stály tři průchody (0,69–0,77 s) za jednu stráž. Zhuštění se dělá **jednou při čtení**.
        ///
        /// **Surový text se nedrží vůbec** — nikdo ho tady nečte, a stav, který nikdo nečte, je
        /// mrtvá váha, která svádí se na ni spolehnout.
        let condensed: String

        /// `code` je kód **bez řádkových komentářů** — vysvětlení pravidla nemá být jeho porušením.
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
