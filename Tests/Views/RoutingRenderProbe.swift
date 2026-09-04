import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#518): vyrendruje **přeskočenou dráhu** v tabu `Průběh` a **tabulku routingu**
/// v nastavení repa.
///
/// Proč sonda: „vejde se kapsle `přeskočeno`, důvod se vzory a cena `0,00 $` do jedné hlavičky?“,
/// „nevypadá `Pustit přesto` jako hlavní akce tabu?“ a „je z tabulky poznat, co prázdný řádek
/// znamená?“ jsou otázky na obrázek. Co se **dá** tvrdit číslem, je v `ReviewerRoutingTests`
/// (rozhodnutí a vzory), `AppStoreRoutingTests` (celá cesta), `ReviewerLaneTests` (fáze dráhy)
/// a `ReviewerLaneTextTests` (věty).
///
/// Šířky odpovídají tabu `Průběh` v širokém a v úzkém okně; v úzkém se hlavička láme nejdřív,
/// takže je to ta zajímavá — a proto je tady i scénář s **dlouhým** seznamem vzorů.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda přeskočené dráhy (#518)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct RoutingRenderProbe {
    private let repo = RepoID(owner: "keboola", name: "sandboxes-notebook-utils")

    private enum Scenario: String, CaseIterable {
        /// Zákres z návrhu, sekce 46: tři vzory a k nim důvod.
        case skipped = "preskoceno"
        /// Dlouhý seznam vzorů — tak vypadá pravidlo, které se vypisovalo z `.gitignore`.
        case longRule = "preskoceno-dlouhe-pravidlo"
        /// Přeskočeno v okamžiku, kdy něco běží: tlačítko se **nekreslí**, věta zůstane.
        case skippedWhileBusy = "preskoceno-nelze-pustit"
        /// Doběhlá dráha vedle — proti čemu se to srovnává (kapsle `doběhlo` a cena ze session).
        case finished = "dobehlo"
    }

    private func patterns(for scenario: Scenario) -> [String] {
        switch scenario {
        case .longRule:
            ["src/Auth/**", "src/Crypto/**", "*.env*", "composer.lock", "config/security/**"]
        default:
            ["src/Auth/**", "src/Crypto/**", "*.env*"]
        }
    }

    private func lane(for scenario: Scenario) -> ReviewerLane {
        guard scenario != .finished else { return finishedLane() }
        let lanes = Policy.lanes(
            of: [],
            skills: ["security-review"],
            skipped: ["security-review": patterns(for: scenario)]
        )
        return lanes[0]
    }

    private func finishedLane() -> ReviewerLane {
        var timeline = ReviewerTimeline(skill: "security-review", worktree: URL(filePath: "/tmp/wt"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        timeline.record(.started(sessionID: "abc123"), at: start)
        for index in 0..<8 {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "src/Auth/Token.php", id: "t\(index)")),
                at: start + Double(index)
            )
        }
        timeline.record(.findings(count: 0), at: start + 20)
        timeline.finish(.finished, usage: RunUsage(cost: 0.31, duration: .seconds(74), turns: 6), at: start + 21)
        return Policy.lanes(of: [timeline], skills: ["security-review"])[0]
    }

    @Test("Vyrendrovat přeskočenou dráhu")
    func rendersTheSkippedLane() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
            ?? NSTemporaryDirectory())
        for scenario in Scenario.allCases {
            for width in [980.0, 620.0] as [CGFloat] {
                for dark in [false, true] {
                    let name = "routing-\(scenario.rawValue)-\(Int(width))-\(dark ? "tmavy" : "svetly")"
                    let url = directory.appending(path: "\(name).png")
                    try write(scenario: scenario, width: width, dark: dark, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    // MARK: - Tabulka v nastavení

    private enum Page: String, CaseIterable {
        /// Repo bez pravidel — výchozí stav, ve kterém je vidět jen nabídka `Přidat reviewera`.
        case empty = "nastaveni-bez-pravidel"
        /// Dvě pravidla, z toho jedno po skillu, který v sadě repa **není**.
        case rules = "nastaveni-s-pravidly"
    }

    private func settings(for page: Page) -> SettingsModel {
        var configuration = Configuration.standard
        configuration.global.skills = ["php-review", "security-review"]
        var repository = RepositoryConfig()
        if page == .rules {
            repository.reviewerPaths = [
                "security-review": ["src/Auth/**", "*.env*"],
                "docs-review": ["docs/**"],
            ]
        }
        configuration.setRepository(repository, for: repo)
        return SettingsModel(configuration: configuration) { _ in }
    }

    @Test("Vyrendrovat tabulku routingu v nastavení repa")
    func rendersTheRoutingTable() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
            ?? NSTemporaryDirectory())
        for page in Page.allCases {
            for dark in [false, true] {
                let name = "routing-\(page.rawValue)-\(dark ? "tmavy" : "svetly")"
                let url = directory.appending(path: "\(name).png")
                try writePage(page, dark: dark, to: url)
                print("SONDA \(url.path)")
            }
        }
    }

    /// Šířka i výška jako u `ReviewTimeoutRenderProbe`: obsahová část okna nastavení při
    /// `idealWidth`, a vyšší než okno, protože stránka se scrolluje.
    private func writePage(_ page: Page, dark: Bool, to url: URL) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let view = RepositorySettingsView(settings: settings(for: page), repositories: [repo])
                    .frame(width: 900, height: 1400)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .tint(Palette.accent)
                try render(view, size: CGSize(width: 900, height: 1400), to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// **Barevný režim se nastavuje dvakrát**, jako u ostatních sond: `NSAppearance` kvůli paletě
    /// a `colorScheme` kvůli `.primary`/`.secondary`.
    private func write(scenario: Scenario, width: CGFloat, dark: Bool, to url: URL) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: (any Error)?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let view = ReviewerLaneView(
                    lane: lane(for: scenario),
                    shortName: "security-review",
                    // `nil` u scénáře `skippedWhileBusy`: tak to okno předává, když něco běží.
                    rerun: scenario == .skippedWhileBusy ? nil : {},
                    feed: .none,
                    toggleFeed: {}
                )
                .padding(12)
                .frame(width: width)
                .background(Palette.background)
                .environment(\.colorScheme, dark ? .dark : .light)
                .tint(Palette.accent)

                try render(view, size: nil, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Jedno místo, ze kterého jde bitmapa — dvě kopie okna a `cacheDisplay` by se rozešly.
    /// `size == nil` znamená „změř si výšku sám“ (dráha), jinak se nasadí (stránka nastavení).
    private func render(_ view: some View, size: CGSize?, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        let bounds = size ?? CGSize(
            width: hosting.fittingSize.width,
            height: max(hosting.fittingSize.height, 90)
        )
        hosting.frame = NSRect(origin: .zero, size: bounds)
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
    }
}
