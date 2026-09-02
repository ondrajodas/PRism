import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#501): vyrendruje **mapu PR** přes pásmo šířek, v obou režimech a se souborem
/// pod výřezem i bez něj.
///
/// Proč sonda a ne měření: „pozná se v pásu, kde je co?“ a „nepřekrývá obrys sousedy?“ jsou
/// otázky na obrázek — a pás se navíc kreslí vedle zákresu v `docs/navrh.html`, takže se má čím
/// porovnat. Co se **dá** tvrdit číslem (šířky, barvy, kontrast akcentu), je
/// v `PullRequestMapDrawingTests`; scénu si obojí bere ze `MapScene`, ať se obrázek a čísla
/// nerozejdou.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — bez toho prefixu se do testovacího procesu nic nedostane.
@MainActor
@Suite(
    "Sonda mapy PR (#501)",
    // **`.serialized`, a je to podmínka, ne opatrnost.** Od chvíle, kdy má sonda dva testy, staví
    // dvě okna mimo obrazovku — a souběžně, protože `@MainActor` suite paralelismus nevypíná.
    // Dvě hosting views, která se rozvrhují z vnořených runloopů, položí testovacího hosta
    // v `_postWindowNeedsUpdateConstraints` uprostřed display cyklu (`SIGABRT`, žádný `✘`
    // a nezapsaný ani první obrázek). Tatáž konstrukce i tentýž důvod jako u `IdleDiffSpinProbe`.
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct PullRequestMapRenderProbe {
    /// Šířky **detailu PR**, ne okna: 647 je nejužší povolené okno (700) bez railu, 1047 je
    /// výchozí okno (1100) a 1347 je široké okno. Do 347 se pás dostane ve pohledu vedle sebe,
    /// kde je detail zúžený panelem.
    private let band: [CGFloat] = [347, 647, 1047, 1347]

    @Test("Vyrendrovat mapu přes pásmo šířek")
    func rendersTheBand() throws {
        for dark in [false, true] {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var thrown: (any Error)?
            appearance.performAsCurrentDrawingAppearance {
                do {
                    for width in band {
                        for current in [nil, 1] as [Int?] {
                            let suffix = current == nil ? "bez-vyrezu" : "s-vyrezem"
                            try capture(
                                width: width,
                                current: current,
                                dark: dark,
                                name: "mapa-\(dark ? "tmava" : "svetla")-\(Int(width))-\(suffix)"
                            )
                        }
                    }
                } catch { thrown = error }
            }
            if let thrown { throw thrown }
        }
    }

    /// Legenda z popisku (#501, varianta A) — **vlastní snímek**, protože v pásu není vidět:
    /// popover se staví, až se otevře, takže ho render řádky nezachytí.
    @Test("Vyrendrovat legendu pásu")
    func rendersTheLegend() throws {
        for dark in [false, true] {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var thrown: (any Error)?
            appearance.performAsCurrentDrawingAppearance {
                do {
                    // **`fixedSize()` tady musí být.** Popover si v okně bere vlastní okno
                    // a velikost od obsahu; hostovaný v pevném rámci mimo obrazovku položí
                    // testovacího hosta v `_postWindowNeedsUpdateConstraints`. Je to vlastnost
                    // sondy, ne legendy — proto se to řeší v ní.
                    let scene = PullRequestMapLegendPopover()
                        .fixedSize()
                        .frame(width: 330, height: 140, alignment: .topLeading)
                        .background(Palette.surface)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .tint(Palette.accent)
                    let name = "legenda-\(dark ? "tmava" : "svetla")"
                    let url = Self.outputDirectory.appending(path: "\(name).png")
                    let size = try render(scene, width: 330, height: 140, to: url)
                    print("SONDA \(url.path) — legenda, vlastní velikost \(size)")
                } catch { thrown = error }
            }
            if let thrown { throw thrown }
        }
    }

    private func capture(width: CGFloat, current: Int?, dark: Bool, name: String) throws {
        let tracking = DiffTracking()
        for (index, file) in MapScene.files.enumerated() {
            tracking.extents.note(file.id, Double(index * 100)...Double((index + 1) * 100))
        }
        tracking.viewport.top = current.map { Double($0 * 100 + 50) } ?? -1000

        let scene = PullRequestMapView(
            map: MapScene.map,
            files: MapScene.files,
            tracking: tracking,
            jump: { _ in }
        )
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        .environment(\.colorScheme, dark ? .dark : .light)
        .tint(Palette.accent)

        let url = Self.outputDirectory.appending(path: "\(name).png")
        let size = try render(scene, width: width, height: 40, to: url)
        print("SONDA \(url.path) — šířka \(Int(width)) b, výška \(size.height)")
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond, viz `docs/testovani.md`. **Dvě kola smyčky**, protože sonda výřezu zapisuje cestu do
    /// krabice až v prvním z nich.
    private func render(_ scene: some View, width: CGFloat, height: CGFloat, to url: URL) throws -> CGSize {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
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
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        return hosting.fittingSize
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }
}
