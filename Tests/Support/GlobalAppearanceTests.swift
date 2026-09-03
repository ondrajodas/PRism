import Foundation
import Testing

@testable import PRism

/// **Globální vzhled procesu není náš, takže se na něj netvrdí nic** (#367).
///
/// Do #367 stálo v `AppStoreAppearanceTests` tvrzení „store bez cíle na `NSApp` nesáhne“ tak, že si
/// vzalo `NSApp.appearance` před a po a porovnalo je. Je to jedna hodnota na celý testovací proces
/// a v paralelním běhu z toho byl **falešně červený `main`**: spadl ten test, který zrovna měřil.
///
/// **Píše ji sám hostitel testů, a je to změřené**, ne odvozené: v běhu, ve kterém žádná jiná suita
/// na vzhled nesahá, je `NSApp.appearance` po startu `nil` a asi **300 ms** poté už
/// `NSAppearanceNameAqua` — to je živý `AppStore`, který uplatní volbu z konfigurace uživatele.
/// Žádné `.serialized` ani zámek v testech proti tomu nepomůže, protože ten zápis nedělá test.
///
/// Zbylo z toho tvrzení o **struktuře kódu**, ne o běhu: „kdo smí sáhnout na globální vzhled“ se za
/// běhu zjistit nedá, zato se to dá přečíst ze zdrojáků. Je to tatáž konstrukce jako
/// `SingleWayOutTests` a `GraphSiteWiringTests`, včetně zahazování řádkových komentářů
/// (`grep -vE ':[0-9]+: *//'`) — o `NSApp.appearance` se v dokumentaci mluví a vysvětlení nemá test
/// zakazovat.
@Suite("Globální vzhled (#367)")
struct GlobalAppearanceTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Tenhle soubor si musí sám sebe odečíst: hledané řetězce v něm stojí jako literály, takže by
    /// se našel jako první porušení pravidla, které vyslovuje.
    private static let guardFile = "Support/GlobalAppearanceTests.swift"

    private struct Source {
        let path: String
        /// Řádky `import …`, tak jak v souboru stojí.
        ///
        /// **Tyhle se schválně nezhušťují** (na rozdíl od `condensed` níž): je to **výčet povolených**,
        /// a ten se mezerou obejít nedá — cokoli napsaného jinak než přesně `import Foundation` v něm
        /// není, takže stráž spadne. Zhuštění by tady jen ubralo hlášce čitelnost.
        let imports: [String]

        /// Kód **bez jediné mezery a bez zalomení** (#490, sem u #550). Hledá se nad tímhle, protože
        /// ve Swiftu je mezera uvnitř volání i za operátorem volná: `NSApp . appearance`
        /// a `foo ??\n    AppAppearance` jsou platný zápis téhož, takže stráž nad surovým textem by
        /// je pustila — tedy zezelenala by právě nad tou chybou, na kterou je.
        ///
        /// **Uložený, ne počítaný** — čísla jsou u `UnanimatedWindowTests.Source.condensed`: jeden
        /// průchod přes 518 zdrojáků stojí 0,23 s, takže dva vzory z computed property stály dva.
        /// Surový text se nedrží: nikdo ho tady nečte.
        let condensed: String

        /// `code` je kód **bez řádkových komentářů** — o `NSApp.appearance` se v dokumentaci mluví
        /// a vysvětlení nemá být porušením pravidla, které vysvětluje.
        init(path: String, code: String, imports: [String]) {
            self.path = path
            self.imports = imports
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

    /// Zdrojáky pod složkou repa, s cestou relativní k ní.
    private func sources(under folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    code: lines.joined(separator: "\n"),
                    imports: lines.map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0.hasPrefix("import ") }
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// Store **nemá čím** na globální vzhled sáhnout, a to je celý ten důkaz: `App/Store/` nevidí
    /// AppKit, takže se v něm `NSApp` nedá ani napsat. Rozhoduje o vzhledu (dostal konfiguraci),
    /// ale kreslení není jeho práce — proto nepovinný cíl `AppearanceApplying`.
    ///
    /// **Importy se hlídají výčtem povolených, ne zákazem AppKitu** (nález z review na #400):
    /// zákaz `import AppKit` obchází `import Cocoa`, a stejně tak by ho obešel kterýkoli další
    /// modul, který AppKit tahá s sebou. Výčet dvou povolených jmen se obejít nedá a **spadne
    /// i tehdy, když ten nový import s vzhledem nesouvisí** — což je v pořádku: `App/Store/` je
    /// vrstva bez kreslení a nový modul v ní je věc do review.
    @Test("Store nemá čím sáhnout na NSApp")
    func keepsTheStoreAwayFromTheApplication() throws {
        let allowed = ["import Foundation", "import Observation"]

        for file in try sources(under: "App/Store") {
            // `NSApp` chytá i `NSApplication` a `NSAppearance` — je to prefix všech tří.
            #expect(!file.condensed.contains("NSApp"), "Store/\(file.path) sahá na aplikaci")
            for line in file.imports {
                #expect(allowed.contains(line), "Store/\(file.path) importuje „\(line)“, a to sem nepatří")
            }
        }
    }

    /// Živý cíl se jmenuje v aplikaci **jednou**: při složení živého storu. Kdyby ho vzal za výchozí
    /// hodnotu i ten init, kterým se store staví v testech, přebarvil by jeden test hostitele —
    /// a render sondy by měřily jiný režim, než o který si řekly.
    @Test("Živý cíl se zapojuje na jednom místě")
    func wiresTheLiveTargetOnce() throws {
        let application = try sources(under: "App")
        let wiring = application.filter { $0.condensed.contains("AppAppearance.application") }.map(\.path).sorted()

        #expect(wiring == ["Store/AppStore.swift"])

        let store = try #require(application.first { $0.path == "Store/AppStore.swift" })
        #expect(store.condensed.components(separatedBy: "AppAppearance.application").count - 1 == 1)
        // Uplatňuje se **jedině** optional-chainem na injektovaný cíl. `??` s živým cílem by byla
        // druhá cesta k `NSApp`, a to potichu: v testech by se objevila jako přebarvený hostitel.
        //
        // **Zakázané vzory jsou bez mezery za `??`** (#550) — hledá se v `condensed`, takže se ta
        // druhá cesta nedá otevřít ani zápisem `?? AppAppearance`, ani zalomením za operátorem.
        #expect(store.condensed.contains("appearance?.applyAppearance("))
        #expect(!store.condensed.contains("??AppAppearance"))
        #expect(!store.condensed.contains("??NSApplication"))

        let applying = application.filter { $0.condensed.contains("applyAppearance") }.map(\.path).sorted()
        #expect(applying == ["Store/AppStore.swift", "Views/AppAppearance.swift"])
    }

    /// **Žádný test si vzhled hostitele nebere.** Ani čtením (bylo by to tvrzení o hodnotě, kterou
    /// mezitím přepsal někdo jiný), ani zápisem (přetekl by do všeho, co zrovna kreslí).
    ///
    /// Kdo potřebuje vynucený režim, nastaví ho na **svém** okně nebo view
    /// (`AppearanceSwitchProbe`), nebo si obalí kreslení `performAsCurrentDrawingAppearance`
    /// (`DiffPaletteTests`, `SidebarRailTests`) — obojí platí jen tam, kde se zrovna měří.
    @Test("Žádný test neměří vzhled hostitele")
    func keepsEveryTestOffTheHostAppearance() throws {
        let tests = try sources(under: "Tests").filter { $0.path != Self.guardFile }

        for file in tests {
            #expect(!file.condensed.contains("NSApp.appearance"), "\(file.path) sahá na vzhled hostitele")
            #expect(
                !file.condensed.contains("NSApplication.shared.appearance"),
                "\(file.path) sahá na vzhled hostitele"
            )
        }
    }

    /// Pojistka proti tomu, aby stráž zezelenala tím, že přestane hledat: hledané vzory musí na
    /// **tomhle** souboru sedět (stojí v něm jako literály) a v `condensed` doopravdy nesmí zůstat
    /// mezery. Bez toho druhého tvrzení by se `NSApp . appearance` v testu neodhalilo (#550).
    @Test("Stráž hledá v kódu bez mezer a vzory na ní sedí")
    func searchesTheCondensedCode() throws {
        let tests = try sources(under: "Tests")
        #expect(tests.count > 100, "Čekaly se stovky zdrojáků, přišlo \(tests.count).")
        let guardFile = try #require(tests.first { $0.path == Self.guardFile }, "stráž se nenašla")
        #expect(guardFile.condensed.contains("NSApp.appearance"))
        #expect(guardFile.condensed.contains("NSApplication.shared.appearance"))
        #expect(
            !guardFile.condensed.contains(where: { $0.isWhitespace }),
            "v `condensed` zůstaly mezery"
        )
    }
}
