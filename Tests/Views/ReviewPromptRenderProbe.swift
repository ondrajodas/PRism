import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#281): vyrendruje stránku `Review a skilly` **ve stavech, ke kterým se
/// v okně nedá snadno dojít** — s neplatnou šablonou, s prázdnou a s vlastní.
///
/// Proč sonda a ne měření: „je vidět, který zástupný text chybí?“ a „vejde se náhled do užšího
/// okna?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem, je v `ReviewPromptTemplateTests`
/// (dosazení, validace, jádro) a v `AppStorePromptTests` (šablona dojede k běhu).
///
/// Šířky odpovídají obsahové části okna nastavení: navigace je 210 bodů a dělič 1, takže při
/// `idealWidth` 880 zbývá 669 a při `minWidth` 720 jen 509. Užší z nich je to zajímavé —
/// jednořádkové popisky se do něj nevejdou.
///
/// `NSHostingView`, ne `ImageRenderer`: `Form` je `ScrollView`, jehož obsah se offscreen
/// nerasterizuje.
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, cesta ven přes `PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda promptu review (#281)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ReviewPromptRenderProbe {
    private enum Scenario: String, CaseIterable {
        /// Co uvidí každý, kdo okno otevře poprvé.
        case standard = "vychozi"
        /// Vlastní šablona, na které je vidět, že se náhled mění s polem.
        case custom = "vlastni"
        /// Smazaný `{{baseSha}}` — stav, na který se klikáním dostane jedině mazáním v poli.
        case broken = "chybi-zastupny-text"
        /// Prázdné pole. Bere se výchozí a je to napsané pod polem.
        case blank = "prazdna"
    }

    private func template(for scenario: Scenario) -> String {
        switch scenario {
        case .standard: ReviewPromptTemplate.standard
        case .custom:
            """
            Review this pull request with the {{skill}} skill. The head commit is checked out; \
            the change is `git diff {{baseSha}}...HEAD`. Be brief and skip style nits.
            """
        case .broken: "Review this pull request with the {{skill}} skill and be brief."
        case .blank: ""
        }
    }

    @Test("Vyrendrovat stránku Review a skilly ve všech stavech promptu")
    func rendersEveryState() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
            ?? NSTemporaryDirectory())
        for scenario in Scenario.allCases {
            for width in [669.0, 509.0] as [CGFloat] {
                for dark in [false, true] {
                    let name = "prompt-\(scenario.rawValue)-\(Int(width))-\(dark ? "tmavy" : "svetly")"
                    let url = directory.appending(path: "\(name).png")
                    try write(scenario: scenario, width: width, dark: dark, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(scenario: Scenario, width: CGFloat, dark: Bool, to url: URL) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do {
                var configuration = Configuration.standard
                configuration.global.reviewPrompt = template(for: scenario)
                let settings = SettingsModel(configuration: configuration) { _ in }
                let scene = ReviewSettingsView(settings: settings)
                    .frame(width: width, height: Self.height)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .tint(Palette.accent)

                let hosting = NSHostingView(rootView: scene)
                hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí
                // vedle sebe víc instancí a cizí okno je poslední, co má sonda rušit.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFront(nil)
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try #require(rep.representation(using: .png, properties: [:])).write(to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Vyšší než okno: stránka se scrolluje a sekce s promptem je až za skilly, takže na
    /// obrázku o velikosti okna by nebyla vidět.
    private static let height: CGFloat = 1500
}
