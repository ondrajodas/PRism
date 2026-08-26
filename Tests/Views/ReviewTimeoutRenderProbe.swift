import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#320): vyrendruje obě místa, kde se nastavuje časový limit běhu, **včetně
/// stavu, ke kterému se v okně nedá dojít** — s hodnotou mimo meze.
///
/// Proč sonda: „je pod polem vidět, že se hodnota ze souboru srazila?“ a „vejde se ta věta do
/// užšího okna?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem, je v `ReviewTimeoutTests`
/// (meze, sráření, text hlášky) a v `AppStoreTimeoutTests` (limit dojede k běhu).
///
/// Hodnotu mimo meze pole samo neuloží (`SettingsNumberField` ořezává), takže se do konfigurace
/// dostane jedině ručně editovaným `config.json` — tady se dosadí přímo.
///
/// Šířky odpovídají obsahové části okna nastavení, stejně jako u `ReviewPromptRenderProbe`:
/// 669 při `idealWidth` a 509 při `minWidth`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda časového limitu (#320)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ReviewTimeoutRenderProbe {
    private let repo = RepoID(owner: "keboola", name: "sandboxes-notebook-utils")

    private enum Scenario: String, CaseIterable {
        /// Co uvidí každý, kdo okno otevře poprvé — patnáct minut.
        case standard = "globalni-vychozi"
        /// Zvednutý limit, tedy to, kvůli čemu #320 vzniklo.
        case raised = "globalni-zvednuty"
        /// Pod dolní mezí. Do souboru se dá napsat ručně.
        case tooShort = "globalni-pod-mezi"
        /// Nad horní mezí — „bez limitu“ se pokouší napsat takhle.
        case tooLong = "globalni-nad-mezi"
        /// Stránka `Repozitáře` bez override — vypsaná globální hodnota.
        case repositoryInherited = "repo-bere-globalni"
        /// Bez override, ale **globální hodnota je mimo meze**. Popisek musí říct, co repo
        /// doopravdy dostane, ne co je v souboru — nálezem Copilota na #324.
        case repositoryInheritsClamped = "repo-bere-globalni-srazenou"
        /// Stránka `Repozitáře` s vlastním limitem.
        case repositoryOverride = "repo-vlastni"
        /// Override mimo meze — tatáž stížnost jako globálně, jen o patro níž.
        case repositoryTooLong = "repo-nad-mezi"

        var isRepositoryPage: Bool {
            switch self {
            case .repositoryInherited, .repositoryInheritsClamped,
                 .repositoryOverride, .repositoryTooLong: true
            default: false
            }
        }
    }

    private func configuration(for scenario: Scenario) -> Configuration {
        var configuration = Configuration.standard
        switch scenario {
        case .standard, .repositoryInherited: break
        case .raised: configuration.global.reviewTimeoutMinutes = 45
        case .tooShort: configuration.global.reviewTimeoutMinutes = 2
        case .tooLong: configuration.global.reviewTimeoutMinutes = 240
        case .repositoryInheritsClamped: configuration.global.reviewTimeoutMinutes = 240
        case .repositoryOverride:
            configuration.setRepository(RepositoryConfig(reviewTimeoutMinutes: 45), for: repo)
        case .repositoryTooLong:
            configuration.setRepository(RepositoryConfig(reviewTimeoutMinutes: 999), for: repo)
        }
        return configuration
    }

    @Test("Vyrendrovat obě místa s limitem ve všech stavech")
    func rendersEveryState() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
            ?? NSTemporaryDirectory())
        for scenario in Scenario.allCases {
            for width in [669.0, 509.0] as [CGFloat] {
                for dark in [false, true] {
                    let name = "timeout-\(scenario.rawValue)-\(Int(width))-\(dark ? "tmavy" : "svetly")"
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
                let settings = SettingsModel(configuration: configuration(for: scenario)) { _ in }
                let page = page(for: scenario, settings: settings)
                    .frame(width: width, height: Self.height)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .tint(Palette.accent)

                let hosting = NSHostingView(rootView: page)
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
                window.orderFrontUnanimated()
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

    @ViewBuilder private func page(for scenario: Scenario, settings: SettingsModel) -> some View {
        if scenario.isRepositoryPage {
            RepositorySettingsView(settings: settings, repositories: [repo])
        } else {
            ReviewSettingsView(settings: settings)
        }
    }

    /// Vyšší než okno: stránka se scrolluje, takže na obrázku o velikosti okna by nebylo vidět
    /// všechno naráz.
    private static let height: CGFloat = 1400
}
