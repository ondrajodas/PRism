import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#527): vyrendruje **pruh záložek okna se všemi pěti značkami** — v obou
/// režimech, ve dvou šířkách.
///
/// Proč sonda a ne měření: „pozná se dutý kroužek od plného puntíku?“ a „nesplyne s prstýnkem
/// běžícího review?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem — které patro vyhrává —,
/// je ve `WindowTabMarkTests`.
///
/// Kreslí se **všech pět značek naráz**, protože rozhodující je, jestli se od sebe poznají: samotný
/// kroužek na bílém pruhu vypadá dobře v jakékoli podobě.
///
/// `NSHostingView` a okno mimo obrazovku, tatáž cesta jako u ostatních sond (#294, #306, #316,
/// #318). **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda pruhu záložek okna (#527)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct WindowTabStripRenderProbe {
    /// Pět záložek, na každou jedna značka — v pořadí pater `Policy.tabMark`, ať se obrázek čte
    /// zleva doprava jako ta funkce.
    private static let scene: [(PRIdentifier, WindowTabMark)] = [
        (PRIdentifier("keboola/connection#21663")!, .running),
        (PRIdentifier("keboola/vault#85")!, .loading),
        (PRIdentifier("keboola/vault-cli#12")!, .draft),
        (PRIdentifier("ondrajodas/PRism#171")!, .pullRequest(.merged)),
        (PRIdentifier("cli/cli#14259")!, .review(.completed(findings: 3)))
    ]

    @Test("Vyrendrovat pruh se všemi značkami")
    func rendersEveryMark() throws {
        for width in [700.0, 1100.0] as [CGFloat] {
            try capture(width: width, dark: false, name: "okno-pruh-\(Int(width))")
        }
    }

    /// **V tmavém režimu**, protože dutý kroužek stojí a padá s tím, jak je vidět obrys.
    ///
    /// Režim se nastavuje **dvakrát** — `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`; s jedním z toho vyjde tmavý text na tmavém
    /// (poučení z `AppearanceRenderProbe`, #278).
    @Test("Vyrendrovat pruh v tmavém režimu")
    func rendersInDarkMode() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do { try capture(width: 1100, dark: true, name: "okno-pruh-tmavy") } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    private func capture(width: CGFloat, dark: Bool, name: String) throws {
        let marks = Dictionary(uniqueKeysWithValues: Self.scene)
        let strip = ReviewTabsView(
            active: .constant(.pullRequest(Self.scene[1].0)),
            tabs: Self.scene.map { Self.summary(of: $0.0) },
            mark: { marks[$0] ?? .review(.notStarted) },
            close: { _ in }
        )
        .frame(width: width)
        .background(Palette.chrome)
        .environment(\.colorScheme, dark ? .dark : .light)

        let url = Self.outputDirectory.appending(path: "\(name).png")
        let hosting = NSHostingView(rootView: strip)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe
        // víc instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
        print("SONDA \(url.path) — pruh \(Int(width)) b")
    }

    private static func summary(of id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek \(id.number)",
            author: "odinuv",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory()
        return URL(filePath: path)
    }
}
