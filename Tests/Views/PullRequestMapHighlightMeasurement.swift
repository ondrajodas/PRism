import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Měřidlo na **zvýraznění souboru pod výřezem** v pásu mapy PR (#501).
///
/// Proč vzniklo: `log₂` v pásu zůstalo, takže **šířka nese objem, a ne to, kde jsem** — a jediné,
/// co v pásu odpovídá na „který soubor zrovna čtu“, je značka souboru pod výřezem. Ta tedy musí
/// být spolehlivá, ne dekorace. `PullRequestMapDrawingTests` tvrdí, že obrys **je** v bitmapě
/// a že jde kolem segmentu, ne dovnitř; to je nutná podmínka, ne dostatečná: nad **sedmi** soubory
/// v širokém okně je segment 55 bodů široký, kdežto nad 45 a 158 soubory spadne na minimum tří
/// bodů (a v úzkém okně pod ně, na rovné dělení). Značka o téže velikosti pak ukazuje na několik
/// souborů naráz.
///
/// **Měří se z bitmapy, ne z tokenu** (#432): kontrast akcentu proti ploše hlavičky vyjde v pořádku
/// při každé šířce, protože je to vlastnost dvou barev — o tom, na co značka ukazuje, netvrdí nic.
/// Měřidlo proto srovnává **dva snímky téže scény** (bez souboru pod výřezem a s ním) a bere
/// **rozdílové body**: to je značka, a nic jiného v ní není.
///
/// Čtyři čísla na kombinaci:
///
/// - **`znacka`** — šířka a výška obálky rozdílových bodů v bodech, a jejich počet (plocha inkoustu).
/// - **`segment`** — nakreslená šířka cílového segmentu, jak ji vydá `Policy.mapWidths`.
/// - **`pokrytych`** — kolik segmentů obálka značky **potkává**. To je ta vlastnost, o kterou jde:
///   `1` znamená „ukazuje na jeden soubor“, `5` znamená „ukazuje do okolí“.
/// - **`podil`** — jaká část obálky značky je cílový segment (`segment / šířka značky`).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`. Obrázky ke koukání vydá
/// `PullRequestMapRenderProbe`.
@MainActor
@Suite(
    "Měřidlo zvýraznění v mapě PR (#501)",
    // **`.serialized`, a je to podmínka.** Měřidlo staví okna mimo obrazovku a `@MainActor` suite
    // paralelismus nevypíná; dvě hosting views rozvrhovaná z vnořených runloopů položí testovacího
    // hosta v `_postWindowNeedsUpdateConstraints` (`SIGABRT`, žádný `✘`). A u měření času by
    // souběžná série navíc měřila cizí práci (#274).
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct PullRequestMapHighlightMeasurement {
    /// Šířky **detailu PR**, tytéž jako u sondy: 347 je pohled vedle sebe, 647 nejužší okno bez
    /// railu, 1047 výchozí a 1347 široké.
    private let widths: [Double] = [347, 647, 1047, 1347]
    /// Počty souborů. `7` je rozložení ze sekce 42, `10` varianta W, `20` je ta hranice, kterou
    /// měřidlo hledá, `45` je `PRism#499` a `158` je `cli/cli#14320` — tedy tatáž pásma, na
    /// kterých se měřilo trefení a lagg. **Od tří**, protože se měří segment uvnitř pásu
    /// a u jednoho ani dvou souborů žádný takový není.
    private let counts = [3, 7, 10, 20, 45, 158]

    @Test("Změřit značku souboru pod výřezem přes pásmo počtů a šířek")
    func measuresTheHighlight() throws {
        print("")
        print("| souborů | šířka | segment | značka (š × v) | inkoust | pokrytých | podíl |")
        print("|---|---|---|---|---|---|---|")
        for count in counts {
            for width in widths {
                let files = Self.files(count: count)
                let map = Policy.pullRequestMap(files: files)
                // Cílem je **nejužší segment uvnitř pásu**: to je ten případ, o kterém se
                // rozhoduje, a kraj pásu se měřit nesmí (obrys má hranu mimo kreslicí plochu).
                let widthsInStrip = Self.stripWidths(of: map, at: width)
                let target = try #require(Self.narrowestInside(widthsInStrip))
                let mark = try measure(files: files, map: map, width: width, target: target)
                print(row(
                    count: count,
                    width: width,
                    strip: Self.stripWidth(of: map, at: width),
                    widths: widthsInStrip,
                    target: target,
                    mark: mark
                ))
            }
        }
        print("")
        // A totéž na **nejširším** segmentu, ať je vidět, že to není vlastnost pásu, ale šířky.
        print("| souborů | šířka | nejširší segment | značka (š × v) | inkoust | pokrytých | podíl |")
        print("|---|---|---|---|---|---|---|")
        for count in [7, 45, 158] {
            for width in widths {
                let files = Self.files(count: count)
                let map = Policy.pullRequestMap(files: files)
                let widthsInStrip = Self.stripWidths(of: map, at: width)
                let target = try #require(Self.widestInside(widthsInStrip))
                let mark = try measure(files: files, map: map, width: width, target: target)
                print(row(
                    count: count,
                    width: width,
                    strip: Self.stripWidth(of: map, at: width),
                    widths: widthsInStrip,
                    target: target,
                    mark: mark
                ))
            }
        }
        print("")
    }

    /// **Kolik inkoustu má značka proti čárce vlákna** — a to je ta otázka, na kterou samotné
    /// „obrys je v bitmapě“ neodpoví. Obojí je akcent a obojí přečnívá pás o čtyři body na každou
    /// stranu, takže když značka spadne na plochu jedné čárky, nekóduje už „tady jsem“, ale
    /// „tady je něco akcentem“.
    @Test("Změřit značku proti čárce vlákna")
    func measuresTheMarkAgainstAThreadTick() throws {
        let files = MapScene.files
        // **Vlákno se přesune, nepřidá** — a je to podmínka měřidla, ne detail: popisek vpravo
        // vlákna počítá, takže scéna *bez* vlákna má užší popisek, širší pás a **jiné** šířky
        // všech segmentů. Rozdílové body by pak byly celý pás, ne čárka (naměřeno: 1 930 b²
        // místo 36). Přesunuté vlákno nechá popisek i šířky beze změny, takže v rozdílu jsou
        // **dvě** čárky — stará a nová — a jedna má poloviční plochu.
        let here = Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: MapScene.findings),
            threads: MapScene.threads
        )
        let elsewhere = try #require(files[3].newPath)
        let moved = Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: MapScene.findings),
            threads: MapScene.threads.map { thread in
                ReviewThread(
                    id: thread.id,
                    path: elsewhere,
                    line: thread.line,
                    originalLine: thread.originalLine,
                    side: thread.side,
                    isResolved: thread.isResolved,
                    isOutdated: thread.isOutdated,
                    comments: thread.comments
                )
            }
        )
        for width in widths {
            let both = try measure(files: files, first: (here, nil), second: (moved, nil), width: width)
            let ink = (both?.ink ?? 0) / 2
            print("ČÁRKA šířka \(Int(width)) b — dvě čárky \(box(both)), jedna tedy inkoust \(ink) b²")
        }
        for count in counts {
            let scene = Self.files(count: count)
            let sceneMap = Policy.pullRequestMap(files: scene)
            let stripWidths = Self.stripWidths(of: sceneMap, at: 1047)
            guard let target = Self.narrowestInside(stripWidths) else { continue }
            let mark = try measure(files: scene, map: sceneMap, width: 1047, target: target)
            print("ZNAČKA \(count) souborů, 1047 b — \(box(mark))")
        }
    }

    /// **Co stojí jeden průchod tělem pásu** — a je to ta cena, kterou do #501 platil *hover*.
    ///
    /// Dokud `hovered` drželo tělo mapy, čtl ho `hoveredTooltip` v témže těle jako `Canvas`, takže
    /// přejezd hranice segmentu přeložil tělo a překreslil celou kresbu. Přejezd myší přes pás
    /// o 158 souborech je **158 hranic za jedno gesto**, takže se ta hodnota násobí.
    ///
    /// Měří se **zápisem do `DiffFileCursor`**, ne hoverem: `cursor.path` čte tatáž funkce těla
    /// (`strip`), takže zneplatní přesně tutéž množinu — a hover se v harnessu vyvolat nedá
    /// (offscreen okno hover nedostane a skládat `CGEvent` v testech tenhle repo zakazuje, #490).
    /// **Je to tedy měření té třídy, ne toho gesta**, a je to zapsaná mez měřidla.
    ///
    /// Série se střídají **A/B/A/B** (#274) a měří se **CPU hlavního vlákna**, ne hodiny.
    @Test("Změřit průchod tělem pásu přes pásmo počtů souborů")
    func measuresOneBodyPass() throws {
        var costs: [Int: [Double]] = [:]
        for _ in 0..<2 {
            for count in counts {
                costs[count, default: []].append(try bodyPassCost(count: count))
            }
        }
        for count in counts {
            let values = costs[count] ?? []
            let average = values.reduce(0, +) / Double(max(values.count, 1))
            print("PRŮCHOD \(count) souborů — "
                + values.map { String(format: "%.1f", $0 / Double(Self.passes) * 1000) }.joined(separator: " / ")
                + String(format: " ms na průchod (průměr %.1f ms; sweep %d hranic = %.0f ms)",
                         average / Double(Self.passes) * 1000,
                         count - 1,
                         average / Double(Self.passes) * 1000 * Double(count - 1)))
        }
    }

    /// Kolik průchodů v sérii. Jeden je pod rozlišením měřidla.
    private static let passes = 20

    private func bodyPassCost(count: Int) throws -> Double {
        let files = Self.files(count: count)
        let map = Policy.pullRequestMap(files: files)
        let tracking = DiffTracking()
        for (index, file) in files.enumerated() {
            tracking.extents.note(file.id, Double(index * 100)...Double((index + 1) * 100))
        }
        let hosting = NSHostingView(
            rootView: PullRequestMapView(map: map, files: files, tracking: tracking, jump: { _ in })
                .padding(.top, 10)
                .frame(width: 1047, alignment: .topLeading)
                .background(Palette.surface)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 1047, height: 40)
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
        // **Příprava se neměří** (#274): okno se nechá usadit a teprve pak se přerovnává.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let started = mainThreadCPUSeconds()
        for index in 0..<Self.passes {
            // **Jiná hodnota, ne tatáž**: zápis téže hodnoty toolchain nehlásí, takže by se
            // neměřilo nic (`PollObservationTests`).
            tracking.cursor.path = files[index % files.count].displayPath
            RunLoop.current.run(until: Date().addingTimeInterval(0.016))
        }
        return mainThreadCPUSeconds() - started
    }

    private func box(_ value: Box?) -> String {
        guard let value else { return "nenakreslila se" }
        return "\(value.width) × \(value.height) b, inkoust \(value.ink) b²"
    }

    private func row(
        count: Int,
        width: Double,
        strip: Double,
        widths: [Double],
        target: Int,
        mark: Box?
    ) -> String {
        guard let mark else {
            return "| \(count) | \(Int(width)) | \(fmt(widths[target])) | **nenakreslila se** | 0 | 0 | — |"
        }
        let spacing = Policy.mapSpacing(count: count, in: strip)
        let covered = Self.covered(widths: widths, spacing: spacing, target: target, mark: mark)
        let share = widths[target] / Double(mark.width)
        return "| \(count) | \(Int(width)) | \(fmt(widths[target])) | \(mark.width) × \(mark.height) |"
            + " \(mark.ink) | \(covered) | \(fmt(share * 100)) % |"
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    // MARK: - Měřidlo

    private struct Box {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int
        let ink: Int

        var width: Int { right - left + 1 }
        var height: Int { bottom - top + 1 }
    }

    /// Rozdílové body mezi snímkem **bez** souboru pod výřezem a **s ním**. To, co se mezi nimi
    /// změnilo, je značka a nic jiného.
    private func measure(files: [FileDiff], map: PullRequestMap, width: Double, target: Int) throws -> Box? {
        try measure(files: files, first: (map, nil), second: (map, target), width: width)
    }

    /// Rozdíl mezi dvěma snímky téže řádky — dvojice `(pás, soubor pod výřezem)`.
    private func measure(
        files: [FileDiff],
        first: (map: PullRequestMap, current: Int?),
        second: (map: PullRequestMap, current: Int?),
        width: Double
    ) throws -> Box? {
        let without = try pixels(files: files, map: first.map, width: width, current: first.current)
        let with = try pixels(files: files, map: second.map, width: width, current: second.current)
        var box: Box?
        var ink = 0
        for y in without.indices where with.indices.contains(y) {
            for x in without[y].indices where with[y].indices.contains(x) {
                guard without[y][x].distance(to: with[y][x]) > 0.02 else { continue }
                ink += 1
                box = Box(
                    left: min(box?.left ?? x, x),
                    right: max(box?.right ?? x, x),
                    top: box?.top ?? y,
                    bottom: y,
                    ink: 0
                )
            }
        }
        guard let box else { return nil }
        return Box(left: box.left, right: box.right, top: box.top, bottom: box.bottom, ink: ink)
    }

    /// Kolik segmentů obálka značky potkává — v souřadnicích pásu, tedy po odečtení odsazení.
    private static func covered(widths: [Double], spacing: Double, target: Int, mark: Box) -> Int {
        let geometry = PullRequestMapGeometry(widths: widths, spacing: spacing)
        let left = Double(mark.left) - PullRequestMapView.horizontalPadding
        let right = Double(mark.right) - PullRequestMapView.horizontalPadding
        return widths.indices.count { index in
            guard let span = geometry.span(of: index) else { return false }
            return span.upperBound >= left && span.lowerBound <= right
        }
    }

    /// Šířka pásu při dané šířce detailu — **tatáž úvaha, jakou dělá řádka**: odsazení na obě
    /// strany, a popisek jen tam, kde se vejde.
    ///
    /// Popisek se bere **z toho pásu, který se kreslí** (`map.summary`), ne skládaný znovu:
    /// složený z jiných čísel by vyšel jinak široký, a tím by se rozešla i spočítaná šířka
    /// segmentu s nakreslenou. Je to tatáž past jako #236, jen v měřidle.
    private static func stripWidth(of map: PullRequestMap, at width: Double) -> Double {
        let available = width - 2 * PullRequestMapView.horizontalPadding
        let label = PullRequestMapView.summaryWidth(of: map.summary)
        guard Policy.mapShowsSummary(available: available, label: label, gap: PullRequestMapView.summaryGap)
        else { return available }
        return available - label - PullRequestMapView.summaryGap
    }

    private static func stripWidths(of map: PullRequestMap, at width: Double) -> [Double] {
        Policy.mapWidths(
            of: map.segments,
            in: stripWidth(of: map, at: width),
            spacing: PullRequestMapView.stripSpacing
        )
    }

    /// Nejužší segment, který **není na kraji pásu**. Krajní se měřit nesmí: obrys prvního
    /// segmentu má levou hranu na `x = −4`, tedy mimo kreslicí plochu, a `Canvas` si kresbu
    /// ořezává — značka by u něj vyšla o dva body užší, než jaká v pásu je.
    private static func narrowestInside(_ widths: [Double]) -> Int? {
        let inside = Array(widths.indices).filter { $0 > 0 && $0 < widths.count - 1 }
        return inside.min { widths[$0] < widths[$1] }
    }

    private static func widestInside(_ widths: [Double]) -> Int? {
        let inside = Array(widths.indices).filter { $0 > 0 && $0 < widths.count - 1 }
        return inside.max { widths[$0] < widths[$1] }
    }

    /// `count` souborů s **různým** objemem: jeden lock a k němu drobnosti, tedy to rozložení,
    /// kvůli kterému logaritmus existuje. Nejmenší soubor leží **uvnitř** pásu, ne na kraji.
    static func files(count: Int) -> [FileDiff] {
        (0..<count).map { index in
            let lines = index == count / 3 && count > 3 ? 2790 : 4 + (index * 7) % 40
            return file("src/File\(index).swift", added: lines, removed: 0)
        }
    }

    private static func file(_ path: String, added: Int, removed: Int) -> FileDiff {
        let new = (0..<added).map {
            DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "nové \($0 + 1)")
        }
        return FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: [DiffHunk(oldStart: 1, oldCount: removed, newStart: 1, newCount: added,
                             heading: "", lines: new)],
            blobs: "aaa..bbb"
        )
    }

    private struct Rgb {
        let red: Double
        let green: Double
        let blue: Double

        init(_ color: NSColor) {
            let value = color.usingColorSpace(.sRGB) ?? color
            red = value.redComponent
            green = value.greenComponent
            blue = value.blueComponent
        }

        func distance(to other: Rgb) -> Double {
            ((red - other.red) * (red - other.red)
                + (green - other.green) * (green - other.green)
                + (blue - other.blue) * (blue - other.blue)).squareRoot()
        }
    }

    private func pixels(
        files: [FileDiff],
        map: PullRequestMap,
        width: Double,
        current: Int?
    ) throws -> [[Rgb]] {
        let tracking = DiffTracking()
        for (index, file) in files.enumerated() {
            tracking.extents.note(file.id, Double(index * 100)...Double((index + 1) * 100))
        }
        tracking.viewport.top = current.map { Double($0 * 100 + 50) } ?? -1000

        let appearance = try #require(NSAppearance(named: .aqua))
        var result: Result<[[Rgb]], any Error>?
        appearance.performAsCurrentDrawingAppearance {
            result = Result {
                // **Nad pásem musí být místo**, jinak měřidlo neměří kresbu, ale ořez bitmapy:
                // plocha `Canvas`u přečnívá řádku o čtyři body na každou stranu a v okně ten
                // přesah leží v odsazení hlavičky. Bez té mezery se horní hrana obrysu i čárky
                // ořeže hranou hosting view a značka vyjde nižší, než jaká je.
                let scene = PullRequestMapView(map: map, files: files, tracking: tracking, jump: { _ in })
                    .padding(.top, 10)
                    .frame(width: width, alignment: .topLeading)
                    .background(Palette.surface)
                    .environment(\.colorScheme, .light)
                    .tint(Palette.accent)
                let hosting = NSHostingView(rootView: scene)
                hosting.frame = NSRect(x: 0, y: 0, width: width, height: 40)
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
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))

                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = max(rep.pixelsWide / Int(width), 1)
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
}
