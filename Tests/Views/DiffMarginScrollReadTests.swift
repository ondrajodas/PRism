import Foundation
import Testing

@testable import PRism

/// **Kdo v diffu čte posun výřezu** (#469, rozšířeno #503) — tvrzení o **zdrojácích**, ne o běhu.
///
/// `DiffViewport.top` se mění při **každém** otočení kolečka, takže o cenu projíždění rozhoduje,
/// kolik věcí ho čte a jak velké tělo se kvůli němu přeloží. V harnessu se to změřit nedá (počet
/// průchodů tělem je vidět jedině z diagnostiky kreslení nad běžící aplikací, #361), zato se to dá
/// **přečíst**: je to tatáž konstrukce jako `GlobalAppearanceTests` a `SingleWayOutTests`, včetně
/// zahazování řádkových komentářů — o tomhle pravidle se v dokumentaci píše a vysvětlení nemá
/// test zakazovat.
///
/// Čtou ho **tři malá view a nic víc**, a `DiffView` ho zapisuje:
///
/// - `DiffPinnedHeader` (v `DiffFileSection.swift`) — ukotvená hlavička souboru, jedna na diff;
/// - `DiffReadShortcut` (#500) — `⌥V` na soubor pod ukotvenou hlavičkou, jedno průhledné tlačítko;
/// - `DiffMarginScroll` (v `DiffMarginView.swift`, #503) — posun okraje s kartami. Uvnitř
///   `body(content:)` je `content` **zástupný uzel**, takže se přeloží jedině ten modifikátor;
///   karty ani jejich obsah ne.
///
/// A **`DiffMarginView` sám ho čtít nesmí**: jeho tělo skládá karty, takže by se při každém
/// snímku přeložilo jedenáct nálezů. Pás na to má vlastní vlastnost (`DiffViewport.band`), která
/// je kvantovaná na násobky výřezu.
@Suite("Kdo čte posun výřezu (#503)")
struct DiffMarginScrollReadTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//` (včetně `///`), jsou pryč.
        let code: String
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
                    code: lines.joined(separator: "\n")
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// **Pět čtenářů plus zapisovatel, jmenovitě.** Šestý znamená, že se při každém snímku
    /// překládá něco dalšího — a je to věc do review, ne detail. Seznam **smí růst**, ale jedině
    /// vědomě: `DiffAnchorReporter` k němu přibyl s #527 (kotva scrollu do `tabs.json`) a projde
    /// tou samou zkouškou jako ostatní tři — je to **malé vyhrazené view**, které `top` čte
    /// v `onChange`, ne tělo, do kterého by se ta hodnota vlila i se vším ostatním.
    @Test("Posun výřezu čte pět míst")
    func onlyThreePlacesReadTheOffset() throws {
        let readers = try sources(under: "App")
            .filter { $0.code.contains("viewport.top") }
            .map(\.path)
            .sorted()

        #expect(readers == [
            // Kotva scrollu (#527) — hlásí polohu výřezu, aby ji restart obnovil.
            "Views/DiffAnchorReporter.swift",
            "Views/DiffFileSection.swift",
            "Views/DiffMarginView.swift",
            "Views/DiffReadShortcut.swift",
            // Zapisovatel — porovnává starou hodnotu s novou, takže to jméno v něm stojí taky.
            "Views/DiffView.swift",
            // Mapa PR (#501) — leží **nad pruhem záložek**, tedy mimo `DiffView`, a ptá se na
            // tutéž věc jako ukotvená hlavička: který soubor drží horní hranu. Čte `top` z krabice,
            // kterou jí podává detail, ne druhým měřením geometrie (#236).
            "Views/PullRequestMapView.swift",
        ])
    }

    /// **Zapisuje se na jednom místě** (#469): `DiffView` z `onScrollGeometryChange`. Druhý
    /// zapisovatel by znamenal, že se posun bere ze dvou různých geometrií.
    @Test("Posun výřezu zapisuje jedno místo")
    func onlyOnePlaceWritesTheOffset() throws {
        let writers = try sources(under: "App")
            .filter { $0.code.contains("viewport.top =") }
            .map(\.path)
            .sorted()

        #expect(writers == ["Views/DiffView.swift"])
    }

    /// **Tělo okraje čte pás, ne posun.** Jediný výskyt `viewport.top` v tom souboru musí stát
    /// **za** deklarací modifikátoru — tedy v něm, ne v `DiffMarginView`.
    @Test("Tělo okraje posun nečte, čte pás")
    func theMarginBodyReadsTheBand() throws {
        let margin = try #require(
            try sources(under: "App").first { $0.path == "Views/DiffMarginView.swift" }
        )
        #expect(margin.code.components(separatedBy: "viewport.top").count - 1 == 1)
        #expect(margin.code.contains("viewport.band"))

        let modifier = try #require(margin.code.range(of: "struct DiffMarginScroll: ViewModifier"))
        let read = try #require(margin.code.range(of: "viewport.top"))
        #expect(
            read.lowerBound > modifier.lowerBound,
            "posun se čte nad deklarací modifikátoru, tedy v těle okraje"
        )
    }

    /// A **pás čtou dvě místa** plus zapisovatel: slot bloku kódu (#469) a okraj (#503). Je to
    /// výčet k posouzení — každé další místo se bude překládat při každém projetém výřezu.
    @Test("Pás kolem výřezu čte slot bloku a okraj")
    func onlyTwoPlacesReadTheBand() throws {
        let readers = try sources(under: "App")
            .filter { $0.code.contains("viewport.band") }
            .map(\.path)
            .sorted()

        #expect(readers == [
            "Views/DiffBlockSlot.swift",
            "Views/DiffMarginView.swift",
            "Views/DiffView.swift",
        ])
    }
}
