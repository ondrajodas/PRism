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
        /// Jen kód — řádky, které začínají `//`, jsou pryč.
        let code: String
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
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
                    code: TextLines.content(text)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                        .joined(separator: "\n")
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// Store **nemá čím** na globální vzhled sáhnout, a to je celý ten důkaz: `App/Store/`
    /// neimportuje AppKit, takže se v něm `NSApp` nedá ani napsat. Rozhoduje o vzhledu (dostal
    /// konfiguraci), ale kreslení není jeho práce — proto nepovinný cíl `AppearanceApplying`.
    @Test("Store nemá čím sáhnout na NSApp")
    func keepsTheStoreAwayFromTheApplication() throws {
        for file in try sources(under: "App/Store") {
            #expect(!file.code.contains("NSApp"), "Store/\(file.path) sahá na aplikaci")
            #expect(!file.code.contains("import AppKit"), "Store/\(file.path) importuje AppKit")
            #expect(!file.code.contains("import SwiftUI"), "Store/\(file.path) importuje SwiftUI")
        }
    }

    /// Živý cíl se jmenuje v aplikaci **jednou**: při složení živého storu. Kdyby ho vzal za výchozí
    /// hodnotu i ten init, kterým se store staví v testech, přebarvil by jeden test hostitele —
    /// a render sondy by měřily jiný režim, než o který si řekly.
    @Test("Živý cíl se zapojuje na jednom místě")
    func wiresTheLiveTargetOnce() throws {
        let application = try sources(under: "App")
        let wiring = application.filter { $0.code.contains("AppAppearance.application") }.map(\.path).sorted()

        #expect(wiring == ["Store/AppStore.swift"])

        let store = try #require(application.first { $0.path == "Store/AppStore.swift" })
        #expect(store.code.components(separatedBy: "AppAppearance.application").count - 1 == 1)
        // Uplatňuje se **jedině** optional-chainem na injektovaný cíl. `??` s živým cílem by byla
        // druhá cesta k `NSApp`, a to potichu: v testech by se objevila jako přebarvený hostitel.
        #expect(store.code.contains("appearance?.applyAppearance("))
        #expect(!store.code.contains("?? AppAppearance"))
        #expect(!store.code.contains("?? NSApplication"))

        let applying = application.filter { $0.code.contains("applyAppearance") }.map(\.path).sorted()
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
            #expect(!file.code.contains("NSApp.appearance"), "\(file.path) sahá na vzhled hostitele")
            #expect(
                !file.code.contains("NSApplication.shared.appearance"),
                "\(file.path) sahá na vzhled hostitele"
            )
        }
    }
}
