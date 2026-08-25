import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Sémantická škála se kreslí z palety, ne ze systému** (#432).
///
/// Vzniklo z měření u #404: čtyři kapsle stály na systémové `.green`/`.red` a ve světlém režimu
/// měly kontrast **1,63 až 2,70**. Není to vada těch čtyř míst — systémové barvy jsou navržené jako
/// **výplň** ovládacího prvku s bílým textem, kdežto v tomhle okně je barva ze škály skoro vždycky
/// **text nebo glyf na tlumeném podkladu**. Tokeny (`ok`, `find`, `crit`, `stale`) jsou na to
/// ztmavené a mockup je má na všech těch místech. Je to tatáž třída jako `zastaralé` (#383), kde ta
/// vada ležela tiše od #172, a `dismissed` (#309).
///
/// **Tvrdí se to nad zdrojáky**, ne nad kresbou, a je to schválně: kolik kontrastu má jedna kapsle,
/// měří `PillTypesettingTests` z bitmapy — ale „nikde jinde v `App/` se systémová škála nekreslí“
/// se za běhu zjistit nedá. Je to tatáž konstrukce jako `GlobalAppearanceTests`, `SingleWayOutTests`
/// a `DesignPillTests`, včetně zahazování řádkových komentářů: o systémových barvách se
/// v dokumentaci mluví a vysvětlení nemá test zakazovat.
///
/// **Co ze systému zůstává, a proč** — všechno změřeno tímtéž harnessem jako kapsle
/// (`.purple`/`.blue` jako text na `Palette.surface`, světlý / tmavý):
///
/// | barva | kde | naměřeno | proč zůstává |
/// |---|---|---|---|
/// | `.secondary` | `notStarted`, `queued`, `draft`, neutrální ikony | — | Není barva ze škály, ale „nemám co říct“; drží se kontrastem okolí, ne tokenem |
/// | `.purple` | `merged` na ose a ve stavu PR | 3,42 / 5,71 | Nad hranicí 3 a paleta purpurovou mimo **akcent** nemá — a akcent je vyhrazený tomu, co aplikace dělá |
/// | `.blue` | `renamed` ve stromu, `moved` u přenosu draftu | **2,85** / 6,57 | Pod hranicí, ale mimo třídu #432 (zelená, červená, okrová) a mockup pro ni token nemá. Zapsáno jako známá mezera, ne jako záměr — patří to do vlastního issue s mockupem |
@Suite("Sémantická škála z palety (#432)")
struct StatusScaleTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// **Hlídá se `App/`, ne `Tests/`** — a je to schválně: testy o systémových barvách tvrdit
    /// **musí** (`color != .green` je to, co spadne, když se převod vrátí), takže by je stejný
    /// zákaz zakázal. Odsud plyne, že tenhle soubor si nemá co odečítat.
    ///
    /// Barvy, na kterých ta vada stála. `.blue` a `.purple` v tom výčtu **nejsou** — viz tabulka
    /// v hlavičce; kdyby se přidaly, spadne to na dvou místech, která se vědomě nechala.
    private static let banned = ["green", "red", "yellow", "orange"]

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč. **S původním číslem řádku**: bez něj
        /// posílá hláška na číslo v očištěném textu, tedy o desítky řádků mimo (ověřeno vloženou
        /// regresí, která hlásila 118 místo 186).
        let lines: [(number: Int, text: String)]
    }

    /// **Ani jedno místo v `App/` nekreslí systémovou barvu ze škály.**
    ///
    /// Hledá se `.green` a spol. s **nepísmenem za sebou**, takže `color.redComponent` ani
    /// `.redacted` se nepočítají — a `Color.green` se počítá, protože o tom, co je před tečkou,
    /// se nerozhoduje: v `App/` je každé takové jméno barva.
    @Test("V App/ není systémová barva ze škály")
    func keepsTheSystemScaleOutOfTheApplication() throws {
        for file in try sources(under: "App") {
            for name in Self.banned {
                let hits = occurrences(of: ".\(name)", in: file.lines)
                #expect(hits.isEmpty, "\(file.path) kreslí systémovou `.\(name)`: \(hits.joined(separator: ", "))")
            }
        }
    }

    /// **A ta čtyři místa z #432 berou doopravdy token**, ne jen „něco, co není systémové“.
    ///
    /// Tvrdí se to na hodnotách, ne nad zdrojáky: `switch` v `ReviewStateAppearance` a
    /// `VerdictAppearance` je to, co se kreslí, kdežto grep výš hlídá jen, že se nikam nevrátila
    /// systémová barva.
    @Test("Škála sedí na tokeny")
    func mapsEveryOutcomeOntoAToken() {
        #expect(ReviewStateAppearance.color(of: .clean) == Palette.ok)
        #expect(ReviewStateAppearance.color(of: .completed(findings: 3)) == Palette.find)
        #expect(ReviewStateAppearance.color(of: .completed(findings: 3), blocking: 1) == Palette.crit)
        #expect(ReviewStateAppearance.color(of: .stale) == Palette.stale)
        #expect(ReviewDraft.Verdict.approve.tint == Palette.ok)
        #expect(ReviewDraft.Verdict.requestChanges.tint == Palette.crit)
        #expect(PullRequestStateAppearance.color(of: .open) == Palette.ok)
        #expect(PullRequestStateAppearance.color(of: .closed) == Palette.crit)
    }

    /// **Měřidlo vidí to, co má vidět.** Tvrzení „nikde nic nenašel“ projde i tehdy, když je hledání
    /// rozbité, takže se sonda pustí i nad vzorkem, ve kterém ta vada je — a nad tím, který se jí
    /// jen podobá (`redComponent`, `.redacted`, jméno tokenu s barvou v názvu).
    @Test("Hledání pozná barvu od jména, ve kterém barva jen je")
    func tellsAColourFromAWordThatContainsOne() {
        #expect(occurrences(of: ".red", in: line("foregroundStyle(Color.red)")).count == 1)
        #expect(occurrences(of: ".red", in: line(".background(.red.opacity(0.1))")).count == 1)
        #expect(occurrences(of: ".red", in: line("let x = pixel.color.redComponent")).isEmpty)
        #expect(occurrences(of: ".red", in: line(".redacted(reason: .placeholder)")).isEmpty)
        #expect(occurrences(of: ".green", in: line("Palette.greenish")).isEmpty)
        // A hlásí **číslo řádku ze souboru**, ne z očištěného textu.
        #expect(occurrences(of: ".red", in: [(number: 186, text: "tint: .red)")]) == ["řádek 186"])
    }

    private func line(_ text: String) -> [(number: Int, text: String)] {
        [(number: 1, text: text)]
    }

    // MARK: - Měřidlo

    /// Výskyty jehly, za kterou **nestojí písmeno ani podtržítko** — s číslem řádku, ať se z hlášky
    /// dá jít rovnou na místo.
    private func occurrences(of needle: String, in lines: [(number: Int, text: String)]) -> [String] {
        var found: [String] = []
        for line in lines {
            var start = line.text.startIndex
            while let range = line.text.range(of: needle, range: start..<line.text.endIndex) {
                start = range.upperBound
                if range.upperBound < line.text.endIndex {
                    let next = line.text[range.upperBound]
                    if next.isLetter || next.isNumber || next == "_" { continue }
                }
                found.append("řádek \(line.number)")
            }
        }
        return found
    }

    /// Zdrojáky pod složkou repa, s cestou relativní k repu — tatáž konstrukce jako
    /// v `GlobalAppearanceTests`.
    private func sources(under folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text).enumerated()
                .map { (number: $0.offset + 1, text: String($0.element)) }
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            let path = folder + "/" + url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(Source(path: path, lines: lines))
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
