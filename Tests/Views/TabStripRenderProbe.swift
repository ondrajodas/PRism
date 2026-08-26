import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#318): vyrendruje **pruh záložek přes pásmo šířek** — v obou režimech, s odznaky
/// i bez a s každou aktivní záložkou.
///
/// Proč sonda a ne měření: „pozná se záložka bez popisku?“ a „nevypadá ikonový pruh jako řada
/// nesouvisejících značek?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem — od jaké šířky je
/// pruh na jednom řádku a která podoba se v ní vybere —, je v `TabStripWidthTests`.
///
/// **Jedno místo pro celý pruh.** Do #318 se tentýž pruh rendroval ve dvou sondách tabů
/// (`ChecksTabRenderProbe`, `CommitsTabRenderProbe`), pokaždé na jiném pásmu šířek a s jinou aktivní
/// záložkou — takže se obrázky nedaly porovnat a obě popisky u sebe měly text o tom, jak se pruh
/// zalomí, což už neplatí. Pruh není součást žádného z těch tabů; stojí nad všemi sedmi.
///
/// `NSHostingView`, ne `ImageRenderer`: ten `ViewThatFits` vyhodnocuje jinak než skutečné okno,
/// takže by sonda ukazovala jinou podobu, než jaká je v aplikaci.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — bez toho prefixu se do testovacího procesu nic nedostane.
@MainActor
@Suite(
    "Sonda pruhu záložek (#318)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct TabStripRenderProbe {
    /// Šířky **tabu**, ne okna: 647 je nejužší povolené okno (700) bez railu, 835 je uprostřed
    /// ikonového pásma, 887 je hranice popisků, 947 je pásmo bez `+X −Y`, 1047 je výchozí okno
    /// (1100) a 1347 je široké okno, ve kterém je vidět všechno.
    private let band: [CGFloat] = [647, 835, 887, 947, 1047, 1347]

    @Test("Vyrendrovat pruh přes pásmo šířek, s odznaky i bez")
    func rendersTheBand() throws {
        for width in band {
            for badges in [false, true] {
                let name = "pruh-\(Int(width))-\(badges ? "s-odznaky" : "bez-odznaku")"
                try capture(width: width, selection: .commits, badges: badges, dark: false, name: name)
            }
        }
    }

    /// **Ikonový stupeň s každou aktivní záložkou.** Popisek u aktivní je jediné, co se mezi nimi
    /// mění, takže je to zároveň obrázek na otázku „pozná se, kde jsem“ — a na tu druhou, jestli se
    /// ikony od sebe poznají bez textu.
    @Test("Vyrendrovat ikonový stupeň s každou aktivní záložkou")
    func rendersEveryActiveTabInTheNarrowStage() throws {
        for tab in PullRequestTab.allCases {
            try capture(width: 647, selection: tab, badges: true, dark: false,
                        name: "pruh-uzky-aktivni-\(Self.slug(of: tab))")
        }
    }

    /// **V tmavém režimu**, protože ikona bez popisku stojí a padá s tím, jak je vidět. Vlastní
    /// test, ne další rozměr pásma: režim se nekontroluje u každé šířky, ale u té jedné, ve které
    /// z pruhu zbyly samé ikony.
    ///
    /// **Režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém —
    /// poučení z `AppearanceRenderProbe` (#278).
    @Test("Vyrendrovat pruh v tmavém režimu")
    func rendersInDarkMode() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do {
                for width in [647.0, 947.0, 1347.0] as [CGFloat] {
                    try capture(width: width, selection: .commits, badges: true, dark: true,
                                name: "pruh-tmavy-\(Int(width))")
                }
            } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    // MARK: - Kreslení

    private func capture(width: CGFloat, selection: PullRequestTab, badges: Bool, dark: Bool,
                         name: String) throws {
        let bar = PullRequestTabBar(
            selection: .constant(selection),
            badge: badges ? Self.badge(of:) : { _ in nil }
        )
        .diffCounts((additions: 248, deletions: 96))
        .frame(width: width)
        .background(Palette.surface)
        .environment(\.colorScheme, dark ? .dark : .light)

        let url = Self.outputDirectory.appending(path: "\(name).png")
        let size = try render(bar, width: width, height: 120, to: url)
        print("SONDA \(url.path) — tab \(Int(width)) b, výška pruhu \(size.height)")
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond (#294, #306, #316), viz `docs/testovani.md`.
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
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe víc
        // instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
        return hosting.fittingSize
    }

    private static func slug(of tab: PullRequestTab) -> String {
        switch tab {
        case .overview: "prehled"
        case .filesChanged: "zmenene-soubory"
        case .commits: "commity"
        case .conversation: "konverzace"
        case .checks: "kontroly"
        case .findings: "nalezy"
        case .progress: "prubeh"
        }
    }

    /// Nejširší běžná sada odznaků — tedy ten případ, na kterém se pruh měří. Vyčerpávající
    /// `switch` schválně: osmá záložka bez odznaku by sondu tiše zlevnila.
    private static func badge(of tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        case .overview: .count(4)
        case .filesChanged: .count(7)
        case .commits: .count(7)
        case .conversation: .count(2)
        case .checks: .blocking(1)
        case .findings: .blocking(3)
        case .progress: .live
        }
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }
}
