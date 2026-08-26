import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#278): vykreslí **rail s přepínačem vzhledu** přes `NSHostingView`, aby se dal
/// **vidět** — v obou režimech a ve všech třech stavech volby.
///
/// **Polohu hlídá test** (`SidebarRailTests`, měří pásy v bitmapě) — odsud se kouká na to, co
/// z čísel poznat nejde: jakou má ikona barvu a jak sedí vedle odznaků. Tím se u #278 našlo, že
/// `.menuStyle(.borderlessButton)` obarví půlkolečko akcentem, takže vypadá jako aktivní sekce.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — `xcodebuild` posílá do testovacího procesu jen proměnné
/// s tímhle prefixem, bez něj se suita tiše přeskočí.
@MainActor
@Suite(
    "Sonda vzhledu (#278)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AppearanceRenderProbe {
    @Test("Vyrendrovat rail do PNG")
    func rendersTheRail() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for mode in AppearanceMode.allCases {
            for dark in [false, true] {
                let url = directory.appending(path: "rail-\(mode.rawValue)-\(dark ? "tmavy" : "svetly").png")
                try write(mode: mode, dark: dark, to: url)
                print("SONDA \(url.path)")
            }
        }
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(mode: AppearanceMode, dark: Bool, to url: URL) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let hosting = NSHostingView(rootView: rail(mode: mode, dark: dark))
                let window = offscreenWindow(for: hosting)
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try #require(rep.representation(using: .png, properties: [:])).write(to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Rail tak, jak ho skládá okno — s odznaky, aby bylo vidět, že se s přepínačem nepotkají.
    private func rail(mode: AppearanceMode, dark: Bool = false) -> some View {
        SidebarRail(
            section: .constant(.queue),
            queueCount: 5,
            draftCount: 2,
            appearance: mode
        )
        .frame(height: 260)
        .environment(\.colorScheme, dark ? .dark : .light)
        .tint(Palette.accent)
    }

    private func offscreenWindow(for hosting: NSHostingView<some View>) -> NSWindow {
        hosting.frame = NSRect(x: 0, y: 0, width: 52, height: 260)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe víc
        // instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        return window
    }
}
