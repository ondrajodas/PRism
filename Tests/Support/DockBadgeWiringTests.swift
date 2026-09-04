import Foundation
import Testing

@testable import PRism

/// **Odznak v Docku a přihlašovací položka jsou globální stav procesu, takže se na ně netvrdí nic
/// za běhu — tvrdí se to nad zdrojáky** (#529).
///
/// Je to **šestá podoba** téhož kořene, na kterém už pětkrát vznikl falešný test: #367 vzhled,
/// #411 `UserDefaults`, #421 cache hostitele, #462 okno s animací, #490 `CGEvent` dědící stav
/// klávesnice. A obojí je horší než ty předchozí, protože stopa přežije běh: odznak zůstane
/// v Docku hostitele testů, přihlašovací položka v systému toho, kdo suitu pustil — a odregistrovat
/// ji už neumí nikdo, protože bundle hostitele mezitím zmizí s `build.noindex/`.
///
/// Konstrukce je tatáž jako u `GlobalAppearanceTests`, včetně zahazování komentářových řádků:
/// o dlaždici i o `SMAppService` se v dokumentaci mluví a vysvětlení nemá test zakazovat.
@Suite("Odznak v Docku a přihlašovací položka (#529)")
struct DockBadgeWiringTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Tenhle soubor si musí sám sebe odečíst: hledané řetězce v něm stojí jako literály, takže by
    /// se našel jako první porušení pravidla, které vyslovuje.
    private static let guardFile = "Support/DockBadgeWiringTests.swift"

    private struct Source {
        let path: String
        /// Řádky `import …`, tak jak v souboru stojí. **Nezhušťují se**: je to výčet povolených,
        /// a ten se mezerou obejít nedá.
        let imports: [String]
        /// Kód **bez jediné mezery a bez zalomení** (#490, sem u #550). Ve Swiftu je mezera uvnitř
        /// volání volná, takže `NSApplication . shared` je platný zápis téhož — stráž nad surovým
        /// textem by ho pustila, tedy zezelenala právě nad tou chybou, na kterou je.
        let condensed: String

        init(path: String, code: String, imports: [String]) {
            self.path = path
            self.imports = imports
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

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

    /// Store **nemá čím** na dlaždici ani na systémovou položku sáhnout, a to je celý ten důkaz:
    /// `App/Store/` nevidí AppKit ani `ServiceManagement`, takže se v něm `NSApplication`
    /// a `SMAppService` nedají ani napsat. Rozhoduje o odznaku (má frontu i konfiguraci), ale
    /// kreslení a zápis do systému není jeho práce — proto nepovinné cíle `DockBadgeApplying`
    /// a `LoginItemControlling`.
    ///
    /// **Importy se hlídají výčtem povolených, ne zákazem jmen** (nález z review na #400): zákaz
    /// `import AppKit` obchází `import Cocoa` a zákaz `import ServiceManagement` by obešel
    /// kterýkoli modul, který ho tahá s sebou.
    @Test("Store nemá čím sáhnout na dlaždici ani na systém")
    func keepsTheStoreAwayFromTheSystem() throws {
        let allowed = ["import Foundation", "import Observation"]

        for file in try sources(under: "App/Store") {
            #expect(!file.condensed.contains("SMAppService"), "Store/\(file.path) sahá na systém")
            #expect(!file.condensed.contains("dockTile"), "Store/\(file.path) sahá na dlaždici")
            for line in file.imports {
                #expect(allowed.contains(line), "Store/\(file.path) importuje „\(line)“, a to sem nepatří")
            }
        }
    }

    /// Živý cíl se v aplikaci jmenuje **jednou**: při složení živého storu. Kdyby ho vzal za
    /// výchozí hodnotu i ten init, kterým se store staví v testech, nasadil by odznak dlaždici
    /// hostitele — a ten by tam zůstal i po běhu.
    @Test("Živé cíle se zapojují na jednom místě")
    func wiresTheLiveTargetsOnce() throws {
        let application = try sources(under: "App")

        for name in ["DockBadgeTile.application", "LoginItemService.live"] {
            let wiring = application.filter { $0.condensed.contains(name) }.map(\.path).sorted()
            #expect(wiring == ["Store/AppStore.swift"], "\(name) se zapojuje odjinud")
            let store = try #require(application.first { $0.path == "Store/AppStore.swift" })
            #expect(store.condensed.components(separatedBy: name).count - 1 == 1)
        }

        // Uplatňuje se **jedině** optional-chainem na injektovaný cíl. `??` s živým cílem by byla
        // druhá cesta k dlaždici, a to potichu — v testech by se objevila jako odznak hostitele.
        // Vzory jsou **bez mezery za `??`**, protože se hledá v `condensed`.
        let store = try #require(application.first { $0.path == "Store/AppStore.swift" })
        #expect(!store.condensed.contains("??DockBadgeTile"))
        #expect(!store.condensed.contains("??NSApplication"))
        #expect(!store.condensed.contains("??LoginItemService"))
    }

    /// Kdo umí zapsat na dlaždici a do systému, je **výčet**. `applyBadge` zná protokol, živá
    /// implementace a to jedno místo ve storu, které ho volá; `SMAppService` zná jedině živá
    /// implementace v `Environment`.
    @Test("Zápis na dlaždici a do systému má vyjmenovaná místa")
    func enumeratesEveryWriter() throws {
        let application = try sources(under: "App")

        let badge = application.filter { $0.condensed.contains("applyBadge") }.map(\.path).sorted()
        #expect(badge == ["Store/AppStore+System.swift", "Views/DockBadgeTile.swift"])

        let dockTile = application.filter { $0.condensed.contains("dockTile") }.map(\.path).sorted()
        #expect(dockTile == ["Views/DockBadgeTile.swift"])

        let service = application.filter { $0.condensed.contains("SMAppService") }.map(\.path).sorted()
        #expect(service == ["Environment/LoginItemControl.swift"])

        // Zapisovat se dá jedině `register`/`unregister`, a jedině z toho jednoho místa ve storu.
        let callers = application
            .filter { $0.condensed.contains("loginItems.register(") || $0.condensed.contains("loginItems.unregister(") }
            .map(\.path)
            .sorted()
        #expect(callers == ["Store/AppStore+System.swift"])
    }

    /// **Žádný test nesahá na dlaždici procesu ani na systémovou položku.** Ani čtením (bylo by to
    /// tvrzení o hodnotě, kterou mezitím přepsal někdo jiný), ani zápisem — a u přihlašovací
    /// položky by zápis přežil celý běh.
    @Test("Žádný test nesahá na dlaždici ani na systém")
    func keepsEveryTestOffTheProcessState() throws {
        let tests = try sources(under: "Tests").filter { $0.path != Self.guardFile }

        for file in tests {
            #expect(!file.condensed.contains("dockTile"), "\(file.path) sahá na dlaždici procesu")
            #expect(!file.condensed.contains("SMAppService"), "\(file.path) sahá na systémovou položku")
            #expect(
                !file.condensed.contains("LoginItemService.live"),
                "\(file.path) staví živou přihlašovací položku"
            )
        }
    }

    /// Pojistka proti tomu, aby stráž zezelenala tím, že přestane hledat: hledané vzory musí na
    /// **tomhle** souboru sedět (stojí v něm jako literály) a v `condensed` nesmí zůstat mezery.
    /// Bez toho druhého tvrzení by se `NSApplication . shared . dockTile` neodhalilo (#550).
    @Test("Stráž hledá v kódu bez mezer a vzory na ní sedí")
    func searchesTheCondensedCode() throws {
        let tests = try sources(under: "Tests")
        #expect(tests.count > 100, "Čekaly se stovky zdrojáků, přišlo \(tests.count).")
        let guardFile = try #require(tests.first { $0.path == Self.guardFile }, "stráž se nenašla")

        #expect(guardFile.condensed.contains("dockTile"))
        #expect(guardFile.condensed.contains("SMAppService"))
        #expect(
            !guardFile.condensed.contains(where: { $0.isWhitespace }),
            "v `condensed` zůstaly mezery"
        )
    }
}
