import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#291): vykreslí `Přehled` přes `NSHostingView`, aby se dal **vidět**.
///
/// Existuje vedle `OverviewWidthTests` proto, že měření odpovídá na „přeteklo, nebo ne“, kdežto
/// otázka „vejde se hlavička karty do zúženého tabu“ je otázka na vzhled. `ImageRenderer` na ni
/// odpovědět neumí: `Link` v něm vyjde jako **žlutý placeholder**, takže se z něj šířka popisku
/// `Otevřít na GitHubu` nepozná — a přesně ten popisek byl v #291 odříznutý. `NSHostingView` kreslí
/// skutečnou hierarchii, takže odkaz v něm stojí ve své šířce.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda Přehledu (#291)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct OverviewRenderProbe {
    /// Nejužší tab, na který se dá v okně přijít (okno 700 s panelem na 300), a pohodlná šířka
    /// nad ním. Sazba se v každé zalomí jinak, takže jedna nestačí.
    private let widths: [CGFloat] = [320, 560, 900]

    @Test("Vyrendrovat Přehled do PNG")
    func rendersOverview() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in widths {
            for dark in [false, true] {
                let url = directory.appending(path: "prehled-\(Int(width))-\(dark ? "tmavy" : "svetly").png")
                try write(width: width, dark: dark, to: url)
                print("SONDA \(url.path)")
            }
        }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u bloku kódu
    /// (#236) a u odpočtu (#269), viz `docs/testovani.md`.
    ///
    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(width: CGFloat, dark: Bool, to url: URL) throws {
        let scene = OverviewView(
            description: Self.description,
            facts: Self.facts,
            lastVisit: Date(timeIntervalSince1970: 1_754_000_000),
            pullRequest: Self.pullRequest
        )
        .content
        .availableWidth(width)
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        .environment(\.colorScheme, dark ? .dark : .light)

        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                try capture(scene, width: width, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Scéna do okna, okno do bitmapy, bitmapa do souboru.
    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu vedle sebe
        // stojí víc instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        // Hierarchie se doskládá až po jednom kole smyčky, takže se výška bere znovu až za ní.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static let pullRequest = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let description = """
        ## Popis

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
        aby se v úzkém tabu zalomil na několik řádků.

        - první odrážka
        - [x] hotová položka

        > [!NOTE]
        > Poznámka od bota.

        ```swift
        let x = 1
        ```
        """

    private static let facts = PullRequestFacts(
        tiles: [
            .init(caption: "Commity", value: "12", note: "3 nové"),
            .init(caption: "Soubory", value: "8", note: "2 s nálezem"),
            .init(caption: "Hlava", value: "abc1234", isMonospaced: true),
            .init(caption: "Nálezy proti", value: "def5678", isMonospaced: true, isStale: true),
        ]
    )
}
