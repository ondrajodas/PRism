import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Legenda pásu mapy PR (#501, varianta A) — **výčet tónů, jejich pořadí a jeden zdroj barvy**.
///
/// Nejcennější tvrzení téhle sady jsou dvě a obě mluví o tom, co se **nestane**: že v legendě
/// nechybí tón, který pás umí nakreslit, a že si legenda barvy **nedosazuje sama**. Druhé jde
/// pokazit potichu — barva by byla ta samá, jen ze druhého místa, a při změně škály by se
/// rozešla, aniž by to bylo na obrázku vidět. Přesně to se stalo v zákresu (tam měla legenda
/// `style="background: var(--crit)"`) a opravilo se to na společný selektor.
@Suite("Legenda mapy PR (#501)")
struct PullRequestMapLegendTests {
    /// **Každý tón má v legendě právě jednu položku** — vyčerpávající výčet přes `CaseIterable`,
    /// ne „aspoň sedm“: nový tón v pásu je rozhodnutí, a tohle je to místo, kde se o něm musí
    /// rozhodnout i v legendě.
    @Test("Legenda pojmenuje každý tón právě jednou")
    func theLegendNamesEveryTone() {
        let items = Policy.mapLegend()
        #expect(items.count == PullRequestMapTone.allCases.count)
        #expect(Set(items.map(\.tone)) == Set(PullRequestMapTone.allCases))
        #expect(items.allSatisfy { !$0.label.isEmpty })
    }

    /// Pořadí je ze zákresu: **tři tóny závažnosti, pak druh souboru a stav značky, nakonec dva
    /// kanály, které barvu nenesou.** Vyjmenované, ne odvozené z `allCases` — pořadí `enum`u je
    /// věc kódu, kdežto tohle je věc obrázku.
    @Test("Legenda má pořadí ze zákresu")
    func theLegendKeepsTheDrawnOrder() {
        #expect(Policy.mapLegend().map(\.tone) == [
            .blocking, .findings, .new, .clean, .read, .thread, .current,
        ])
        #expect(Policy.mapLegend().map(\.label) == [
            "blokuje", "nález", "nový soubor", "bez nálezu", "prošlo", "vlákno", "čtu",
        ])
    }

    /// Zalomení po dvou: **čtyři řádky, poslední kratší, žádná prázdná** — a v součtu přesně to,
    /// co vydá `mapLegend()`, ve stejném pořadí.
    @Test(arguments: [1, 2, 3, 4, 7, 9])
    func theRowsCoverTheLegend(perRow: Int) {
        let rows = Policy.mapLegendRows(perRow: perRow)
        #expect(rows.allSatisfy { !$0.items.isEmpty }, "prázdná řádka v legendě")
        #expect(rows.map(\.index) == Array(rows.indices))
        #expect(rows.flatMap(\.items) == Policy.mapLegend())
        #expect(rows.allSatisfy { $0.items.count <= perRow })
        #expect(rows.count == (Policy.mapLegend().count + perRow - 1) / perRow)
    }

    /// **Nula na řádku nesmí položit ani vyrobit prázdno.** Je to obrana proti volajícímu, ne
    /// funkce — dělení nulou by v `stride` znamenalo nekonečno.
    @Test("Zalomení na nulu vydá jednu řádku se všemi")
    func zeroPerRowStillYieldsEverything() {
        let rows = Policy.mapLegendRows(perRow: 0)
        #expect(rows.count == 1)
        #expect(rows.first?.items == Policy.mapLegend())
    }

    /// Zákres má **dvě** položky na řádku, takže výchozí hodnota musí být dvě — jinak by legenda
    /// v okně vypadala jinak než na obrázku.
    @Test("Výchozí zalomení je po dvou")
    func theDefaultIsTwoPerRow() {
        #expect(Policy.mapLegendRows().allSatisfy { $0.items.count <= 2 })
        #expect(Policy.mapLegendRows().count == 4)
    }

    // MARK: - Výplň segmentu

    /// **`mapFill(of:)` vydá jedině tón výplně** — nikdy `read`, `thread` ani `current`.
    ///
    /// Ty tři nejsou barvy, ale jiné kanály: krytí, čárka a značka souboru pod výřezem. Kdyby se
    /// jeden z nich do výplně dostal, byl by v pásu pátý stav závažnosti a nikdo by si toho na
    /// obrázku nemusel všimnout — `accent` vedle `crit` vypadá jako „něco tu je“.
    @Test("Výplň segmentu je vždycky jeden ze čtyř tónů")
    func theFillIsAlwaysOneOfFour() {
        let markers: [FileMarker?] = [.blocking, .findings, nil]
        for marker in markers {
            for isNew in [false, true] {
                for state in [FileReviewState.unread, .read(at: .distantPast), .changed(readAt: .distantPast)] {
                    let tone = Policy.mapFill(of: Self.segment(marker: marker, isNew: isNew, readState: state))
                    let fills: [PullRequestMapTone] = [.blocking, .findings, .clean, .new]
                    #expect(fills.contains(tone),
                            "\(String(describing: marker))/\(isNew)/\(state) vydalo \(tone)")
                }
            }
        }
    }

    /// **Nejhorší nález přebíjí druh souboru**: nový soubor s blokujícím nálezem je červený, ne
    /// zelený. A stav značky do výplně nezasahuje vůbec — tlumení je krytí nad ní.
    @Test("Nález přebíjí nový soubor, značka do výplně nezasahuje")
    func theMarkerWinsOverTheFileKind() {
        #expect(Policy.mapFill(of: Self.segment(marker: .blocking, isNew: true)) == .blocking)
        #expect(Policy.mapFill(of: Self.segment(marker: .findings, isNew: true)) == .findings)
        #expect(Policy.mapFill(of: Self.segment(marker: nil, isNew: true)) == .new)
        #expect(Policy.mapFill(of: Self.segment(marker: nil, isNew: false)) == .clean)
        #expect(
            Policy.mapFill(of: Self.segment(marker: nil, isNew: true, readState: .read(at: .distantPast))) == .new
        )
    }

    /// Krytí prošlého je **jedna hodnota pro kresbu i pro legendu**. Vyjmenovaná: kdo ji změní,
    /// mění vzhled pásu, a to je rozhodnutí, ne úprava.
    @Test("Prošlý segment se tlumí na 35 %")
    func theReadOpacityIsPinned() {
        #expect(Policy.mapReadOpacity == 0.35)
    }

    // MARK: - Stráže nad zdrojáky

    /// **Legenda si barvy nedosazuje sama.** Tvrdí se to nad zdrojákem, protože z bitmapy se to
    /// poznat nedá: `Palette.crit` dosazená v legendě nakreslí přesně tutéž barvu jako
    /// `fill(of: .blocking)` — rozdíl se objeví teprve v tom průchodu, kdy se změní škála a projde
    /// se jen jedno ze dvou míst. Textové tokeny (`ink2`, `ink3`) v zákazu nejsou: legenda je
    /// z poloviny text a ten do pásu nepatří.
    @Test("V legendě nestojí žádná barva ze škály")
    func theLegendTakesItsColoursFromOnePlace() throws {
        let code = try Self.code(of: "App/Views/PullRequestMapLegendView.swift")
        for forbidden in ["Palette.crit", "Palette.find", "Palette.okWash", "Palette.raised", "Palette.accent"] {
            #expect(!code.contains { $0.contains(forbidden) },
                    "`\(forbidden)` v legendě — barvu vydává `PullRequestMapView.fill(of:)`")
        }
        #expect(code.contains { $0.contains("PullRequestMapView.fill(of:") },
                "legenda barvu odnikud nebere")
    }

    /// **Hover nežije v těle pásu, a je to výkonová podmínka** (#501, tatáž věta jako #358 a #438).
    ///
    /// Dokud ho drželo tělo mapy, čtl ho popisek nápovědy v témže těle jako `Canvas`, takže
    /// přejezd hranice segmentu přeložil tělo a překreslil celou kresbu. Změřeno: jeden průchod
    /// tělem stojí při 158 souborech **7,2 ms**, a přejezd pásu je 157 hranic, tedy **1,1 s** CPU
    /// hlavního vlákna za jedno gesto.
    ///
    /// Tvrdí se to nad zdrojákem, protože **hover se v harnessu vyvolat nedá**: offscreen okno ho
    /// nedostane a skládat `CGEvent` v testech tenhle repo zakazuje (#490). Je to zapsaná mez —
    /// číslo je z `PullRequestMapHighlightMeasurement`, tvrzení odsud.
    @Test("Nápověda a hover nejsou v těle pásu")
    func theHoverLivesInItsOwnLayer() throws {
        let strip = try Self.code(of: "App/Views/PullRequestMapView.swift")
        for forbidden in ["onContinuousHover", "hovered", "Policy.mapTooltip", ".help("] {
            #expect(!strip.contains { $0.contains(forbidden) },
                    "`\(forbidden)` je zpátky v těle pásu — hover nemá překreslovat kresbu")
        }
        let layer = try Self.code(of: "App/Views/PullRequestMapHoverLayer.swift")
        #expect(layer.contains { $0.contains("Policy.hoverChange") },
                "vrstva zapisuje hover bezpodmínečně (#358)")
        // A trefení má pořád **jeden** zdroj: vrstva se ptá geometrie, nepočítá si to sama.
        #expect(layer.contains { $0.contains("PullRequestMapGeometry") })
    }

    // MARK: - Kresba vzorku

    /// **Vzorek `prošlo` se nesmí splést se `bez nálezu`** — a to je jediná věc, kterou z legendy
    /// jde pokazit potichu: `opacity` je druhý kanál, takže vynechaná se pozná jedině z bitmapy.
    @MainActor
    @Test("Vzorek prošlého je tlumený, plný segment ne")
    func theReadSwatchIsDimmed() throws {
        let dimmed = try Self.swatchColour(of: .read)
        let plain = try Self.swatchColour(of: .clean)
        let surface = try Self.pixels(of: Rectangle().fill(Palette.surface), size: CGSize(width: 6, height: 6))[3][3]

        // Tlumený vzorek leží **mezi** plným a plochou pod ním, a od obojího se pozná.
        #expect(dimmed.distance(to: plain) > 0.02,
                "tlumený vzorek \(dimmed) je k nerozeznání od plného \(plain)")
        #expect(dimmed.distance(to: surface) > 0.005,
                "tlumený vzorek \(dimmed) splynul s plochou \(surface)")
    }

    /// Vzorky závažnosti se v legendě od sebe **poznají** — tedy že do bitmapy dojdou, ne jen že
    /// se `fill(of:)` volá.
    @MainActor
    @Test("Vzorky závažnosti se v legendě od sebe poznají")
    func theSeveritySwatchesStayApart() throws {
        let blocking = try Self.swatchColour(of: .blocking)
        let findings = try Self.swatchColour(of: .findings)
        let new = try Self.swatchColour(of: .new)
        #expect(blocking.distance(to: findings) > 0.05, "\(blocking) proti \(findings)")
        #expect(blocking.distance(to: new) > 0.05, "\(blocking) proti \(new)")
        #expect(findings.distance(to: new) > 0.05, "\(findings) proti \(new)")
    }

    // MARK: - Měřidlo

    private struct Rgb: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double

        init(_ color: NSColor) {
            let value = color.usingColorSpace(.sRGB) ?? color
            red = value.redComponent
            green = value.greenComponent
            blue = value.blueComponent
        }

        var description: String { String(format: "%.3f/%.3f/%.3f", red, green, blue) }

        func distance(to other: Rgb) -> Double {
            ((red - other.red) * (red - other.red)
                + (green - other.green) * (green - other.green)
                + (blue - other.blue) * (blue - other.blue)).squareRoot()
        }
    }

    /// Barva prostředního bodu vzorku toho tónu, **nakresleného tou cestou, jakou ho kreslí
    /// legenda** — jeden `Grid` po jedné položce by měřil totéž, jen dráž.
    @MainActor private static func swatchColour(of tone: PullRequestMapTone) throws -> Rgb {
        let fill = PullRequestMapView.fill(of: tone == .read ? .clean : tone)
        let swatch = RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .opacity(tone == .read ? Policy.mapReadOpacity : 1)
            .frame(width: 14, height: 9)
            .background(Palette.surface)
        return try pixels(of: swatch, size: CGSize(width: 14, height: 9))[4][7]
    }

    /// Kresba view po bodech — tatáž cesta jako u `PullRequestMapDrawingTests`, jen bez pásma
    /// režimů: tady se rozhoduje o **kanálu** (krytí), ne o barvě, a ten na režimu nezávisí.
    @MainActor private static func pixels(of view: some View, size: CGSize) throws -> [[Rgb]] {
        let appearance = try #require(NSAppearance(named: .aqua))
        var result: Result<[[Rgb]], any Error>?
        appearance.performAsCurrentDrawingAppearance {
            result = Result {
                let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
                hosting.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                hosting.layoutSubtreeIfNeeded()

                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = max(rep.pixelsWide / Int(size.width), 1)
                var rows: [[Rgb]] = []
                for y in stride(from: 0, to: rep.pixelsHigh, by: scale) {
                    var row: [Rgb] = []
                    for x in stride(from: 0, to: rep.pixelsWide, by: scale) {
                        row.append(Rgb(try #require(rep.colorAt(x: x, y: y))))
                    }
                    rows.append(row)
                }
                return rows
            }
        }
        return try #require(result).get()
    }

    private static func segment(
        marker: FileMarker?,
        isNew: Bool,
        readState: FileReviewState = .unread
    ) -> PullRequestMapSegment {
        PullRequestMapMapSegmentStub(marker: marker, isNew: isNew, readState: readState).value
    }

    /// Kód souboru bez komentářových řádků — stráž hlídá **kód, ne text**, protože se o týchž
    /// jménech píše v `///` komentářích (tatáž konstrukce jako u `SingleWayOutTests`).
    private static func code(of path: String) throws -> [String] {
        let source = try String(contentsOf: sourceRoot.appending(path: path), encoding: .utf8)
        return TextLines.all(source)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Kořen repa z cesty tohohle souboru. **Ne `Bundle`**: zdrojáky v bundlu testovacího hosta
    /// nejsou, a `#filePath` je jediné, co v obou (Xcode i `xcodebuild`) ukazuje na strom.
    private static var sourceRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

/// Segment mapy poskládaný jen z toho, co `mapFill(of:)` čte — zbytek je nula.
struct PullRequestMapMapSegmentStub {
    let marker: FileMarker?
    let isNew: Bool
    let readState: FileReviewState

    var value: PullRequestMapSegment {
        PullRequestMapSegment(
            path: "a.swift",
            name: "a.swift",
            changedLines: 1,
            additions: 1,
            deletions: 0,
            marker: marker,
            isNew: isNew,
            readState: readState,
            findings: marker == nil ? 0 : 1,
            threads: []
        )
    }
}
