import Foundation
import Testing

@testable import PRism

/// **Stráž nad zdrojáky: kde se kreslí řádek fronty, tam musí být i `Odložit`** (#512, oprava po
/// proklikání).
///
/// Vzniklo z pravé příčiny, ne z projevu. Nabídka `Odložit` byla navěšená jedině ve
/// `PullRequestListView`, jenže `PullRequestRow` se kreslí na **třech** místech — v seznamu,
/// v sekci `Rozdělaná` (`HomeView`) a v pruhu desky (`BoardView`). Na dvou z nich se tedy odložit
/// nedalo, a na desce přitom stojí ve větě pod pozdravem `· 2 odložené`. Za běhu se to tvrdit
/// nedá: `body` každého z těch view je neprůhledný typ, takže „je v něm navěšená akce“ není
/// otázka, na kterou by šlo odpovědět jinak než pohledem do zdrojáku.
///
/// **Je to stráž na čtvrté místo**, ne na ta tři. Ta tři se opravila; tahle sada je jediné, co
/// řekne, že se na to zapomnělo znovu, až řádek přibude do čtvrtého view.
///
/// Konstrukce je tatáž jako u `UnanimatedWindowTests` a `SingleWayOutTests`: čte se `App/`,
/// řádkové komentáře se zahazují (vysvětlení pravidla nemá být jeho porušením) a hledá se
/// v textu **bez mezer**, protože `PullRequestRow (` je platný zápis téhož.
@Suite("Kde se kreslí řádek fronty, tam je i Odložit (#512)")
struct PullRequestRowSnoozeWiringTests {
    private static let app = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    /// Konstrukce řádku. Bez mezery za jménem schválně — hledá se v `condensed`.
    private static let construction = "PullRequestRow("

    /// Co u ní musí stát. Jméno parametru, ne jméno storu: řádek se dá nakreslit i mimo `AppStore`
    /// (náhled), a tam je odpověď `nil` — jenže **napsaná**, ne zapomenutá.
    private static let wiring = "snoozeAction:"

    /// Soubor, ve kterém řádek **bydlí**. Kreslí se v něm `#Preview`, tedy jediné legitimní místo
    /// bez odložení: náhled store nemá a `nil` je tam správná odpověď (tvrdí to
    /// `PullRequestRowSnoozeTests.defaultsToNoSnooze`).
    private static let home = "Views/PullRequestRow.swift"

    /// **Počítá se, neptá se na obsah.** Čtvrté místo nepřibude nutně jako nový soubor — spíš jako
    /// **druhý** `PullRequestRow(` v už zapojeném view, a ten by se za jediné `snoozeAction:`
    /// v souboru schoval. Tatáž konstrukce jako `EmojiFieldWiringTests`, a ze stejného důvodu.
    @Test("Každé kreslení řádku fronty mu předává odložení")
    func everyRowSiteWiresSnooze() throws {
        var offenders: [String] = []
        for source in try Self.sources() where source.path != Self.home {
            let sites = source.count(of: Self.construction)
            guard sites > 0 else { continue }
            let wired = source.count(of: Self.wiring)
            if wired != sites { offenders.append("\(source.path): \(sites)× řádek, \(wired)× odložení") }
        }
        #expect(
            offenders.isEmpty,
            """
            Řádek fronty se tu kreslí bez `snoozeAction:`, takže v tom místě nejde odložit \
            (#512) — a `Odložené` se přitom počítají do věty na desce. Předej \
            `store.snoozeAction(for:)`. Nálezy: \(offenders.sorted().joined(separator: ", "))
            """
        )
    }

    /// Pojistka proti stráži, která zezelená tím, že přestane číst nebo přestane hledat. Zároveň
    /// tvrdí to, co se v téhle opravě spravovalo: **místa jsou tři**, ne jedno.
    @Test("Stráž doopravdy čte zdrojáky a míst je pořád víc než jedno")
    func readsTheSources() throws {
        let sources = try Self.sources()
        #expect(sources.count > 100, "Čekaly se stovky zdrojáků, přišlo \(sources.count).")

        let sites = sources
            .filter { $0.path != Self.home && $0.condensed.contains(Self.construction) }
            .map(\.path)
            .sorted()
        #expect(
            sites == [
                "Views/BoardView.swift",
                "Views/HomeView.swift",
                "Views/PullRequestListView.swift",
            ],
            "Místa, kde se kreslí řádek fronty, se změnila: \(sites)"
        )

        let row = try #require(sources.first { $0.path == Self.home }, "\(Self.home) se nenašel")
        #expect(
            row.condensed.contains(Self.construction),
            "V \(Self.home) nesedl hledaný vzor — stráž hledá něco, co v kódu není."
        )
        #expect(!row.condensed.contains(where: { $0.isWhitespace }), "v `condensed` zůstaly mezery")
    }

    private struct Source {
        let path: String

        /// Kolikrát se ten vzor v souboru vyskytuje.
        func count(of needle: String) -> Int {
            condensed.components(separatedBy: needle).count - 1
        }

        /// Kód **bez jediné mezery a bez zalomení** (#490), ze stejného důvodu jako u ostatních
        /// stráží: ve Swiftu je mezera uvnitř volání volná, takže `PullRequestRow (` i
        /// `snoozeAction :` jsou platný zápis téhož. Uložený, ne počítaný — dva vzory nad pěti
        /// sty zdrojáky by jinak byly dva průchody.
        let condensed: String

        /// `code` je kód **bez řádkových komentářů**.
        init(path: String, code: String) {
            self.path = path
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

    private static func sources() throws -> [Source] {
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            throw SourceReadError.unreadable(app.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: app.path + "/", with: ""),
                    code: lines.joined(separator: "\n")
                )
            )
        }
        // **Pojistka uvnitř čtení, ne jen ve vedlejším testu**: kdyby složka přestala sedět,
        // prošel by hlavní test nad prázdnem — tedy zezelenal by právě tehdy, když nečte.
        guard !files.isEmpty else { throw SourceReadError.unreadable(app.path) }
        return files
    }

    private enum SourceReadError: Error {
        case unreadable(String)
    }
}
