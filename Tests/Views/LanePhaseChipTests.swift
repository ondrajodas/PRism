import Foundation
import Testing

@testable import PRism

/// **Dráhy jsou dvě a kapsle fáze je jedna** (#508) — tvrzeno nad zdrojáky, ne za běhu.
///
/// Issue #508 slibuje, že smyčka vlastního PR se kreslí `.ph` stavy **stejně jako Průběh, bez
/// nového vzoru**. Ten slib se za běhu ověřit nedá: obě dráhy vypadají zeleně i tehdy, když si
/// každá mapuje `PhaseState` na barvu sama — rozejdou se až tím, že někdo změní odstín na jednom
/// místě. Testuje se proto to, co ten slib doopravdy drží: **mapování je v jednom souboru
/// a kreslí z něj obě dráhy.**
///
/// Konstrukce je tatáž jako u `DockBadgeWiringTests`, včetně zahazování komentářových řádků
/// a porovnávání textu bez mezer (#490, #550): ve Swiftu je mezera uvnitř volání volná, takže
/// stráž nad surovým textem by pustila `LanePhaseChip (`.
@Suite("Kapsle fáze je jedna pro obě dráhy (#508)")
struct LanePhaseChipTests {
    private static let views = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App/Views")

    private struct Source {
        let name: String
        let condensed: String
    }

    private func sources() throws -> [Source] {
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.views, includingPropertiesForKeys: nil
        )
        let sources = files.filter { $0.pathExtension == "swift" }.map { url -> Source in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined()
            return Source(name: url.lastPathComponent, condensed: code.filter { !$0.isWhitespace })
        }
        #expect(!sources.isEmpty, "App/Views se nepodařilo přečíst")
        return sources
    }

    /// Mapování `PhaseState → barva` smí být **na jednom místě**. Hledá se podpis funkce, ne
    /// jednotlivá dvojice `case` — `case .done: Palette.ok` je legitimně i v `PanelBranchView`,
    /// jenže tam je to `BranchFact.Tone`, tedy jiný výčet nad jinou otázkou.
    @Test("Barvu fáze rozhoduje jediný soubor")
    func onlyOneFileMapsPhaseStateToColour() throws {
        let mapping = try sources()
            .filter { $0.condensed.contains(":ReviewerLane.PhaseState)->Color") }
            .map(\.name)
            .sorted()
        #expect(mapping == ["LanePhaseChip.swift"])
    }

    /// A o stavu fáze se ve views vůbec nerozhoduje jinde: `LanePhaseChip` kreslí, `ReviewerLaneText`
    /// z něj skládá to, co přečte odečítání obrazovky. Třetí soubor by byl třetí slovník.
    @Test("O stavu fáze rozhodují dva soubory")
    func phaseStateIsReadInTwoPlaces() throws {
        let readers = Set(
            try sources().filter { $0.condensed.contains("ReviewerLane.PhaseState") }.map(\.name)
        )
        #expect(readers == ["LanePhaseChip.swift", "ReviewerLaneText.swift"])
    }

    /// A obě dráhy z ní opravdu kreslí — jinak by pravidlo výš platilo tím, že kapsli nepoužívá
    /// nikdo.
    @Test("Obě dráhy kreslí sdílenou kapslí")
    func bothLanesUseTheSharedChip() throws {
        let users = Set(
            try sources().filter { $0.condensed.contains("LanePhaseChip(") }.map(\.name)
        )
        #expect(users == ["ReviewerLaneView.swift", "OwnLoopView.swift"])
    }
}
