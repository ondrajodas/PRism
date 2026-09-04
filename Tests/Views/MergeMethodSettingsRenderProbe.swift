import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#556): vyrendruje **obě místa v nastavení**, ze kterých se bere výchozí metoda
/// merge — sekci `Merge vlastního PR` na stránce `Odesílání` a picker `Metoda merge` na stránce
/// `Repozitáře`.
///
/// Proč sonda: „sedí to se sekcí 48?“ je otázka na obrázek. Co se **dá** tvrdit číslem, je
/// v `MergeMethodChoiceTests` (nabídka, předvybraná metoda, texty) a v `ConfigurationTests`
/// (co se uloží do souboru).
///
/// **Per-repo picker je tady ta cenná polovina.** Přeškrtnutá metoda se v běžící instanci ukáže
/// jedině nad repem, které ji doopravdy nepovoluje, a **kterému aplikace ty příznaky už přečetla**
/// — takže je to stav, do kterého se klikáním dostat nemusí. Scéna ho podstrkuje z **měřených**
/// dat (`keboola/job-queue-daemon` nemá `allow_rebase_merge`).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda nastavení metody merge (#556)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct MergeMethodSettingsRenderProbe {
    @Test("Vyrendrovat výchozí metodu na stránce Odesílání")
    func rendersThePublishingPage() throws {
        for (name, method) in [("odesilani-squash", MergeMethod.squash), ("odesilani-merge", .mergeCommit)] {
            var configuration = Configuration.standard
            configuration.global.mergeMethod = method
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(
                AnyView(
                    PublishingSettingsView(
                        settings: SettingsModel(configuration: configuration) { _ in }
                    )
                    .background(Palette.chrome)
                ),
                width: 640,
                height: 520,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    /// Tři scény: repo bez override (bere globální), repo s vlastní metodou, a **repo, které dvě
    /// z těch tří metod nepovoluje** — to je ten stav, kvůli kterému sonda existuje.
    @Test("Vyrendrovat picker metody na stránce Repozitáře")
    func rendersTheRepositoryPage() throws {
        // Změřeno na živém API: `keboola/dbt-transformation` povoluje **jen** merge commit,
        // `keboola/job-queue-daemon` nemá rebase.
        let onlyMergeCommit = RepositoryMergeSettings(
            allowsMergeCommit: true,
            allowsSquash: false,
            allowsRebase: false,
            squashBody: .commitMessages,
            mergeCommitBody: .pullRequestTitle
        )
        let withoutRebase = RepositoryMergeSettings(
            allowsMergeCommit: true,
            allowsSquash: true,
            allowsRebase: false,
            squashBody: .commitMessages,
            mergeCommitBody: .pullRequestTitle
        )
        let scenes: [(String, MergeMethod?, RepositoryMergeSettings?)] = [
            // `nil` u nastavení = ještě se to nezjistilo, takže se nic neškrtá — a je to ten
            // stav, ve kterém se stránka otevře, dokud dotaz nedoběhne.
            ("repo-metoda-nezjisteno", nil, nil),
            ("repo-metoda-bez-rebase", .mergeCommit, withoutRebase),
            ("repo-metoda-jen-merge-commit", nil, onlyMergeCommit),
        ]

        for (name, override, merge) in scenes {
            var configuration = Configuration.standard
            if let override {
                configuration.setRepository(RepositoryConfig(mergeMethod: override), for: Self.repo)
            }
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(
                AnyView(
                    RepositorySettingsView(
                        settings: SettingsModel(configuration: configuration) { _ in },
                        repositories: [Self.repo],
                        mergeSettings: { _ in merge }
                    )
                    .background(Palette.chrome)
                ),
                width: 880,
                height: 620,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    private static let repo = RepoID(owner: "keboola", name: "job-queue-daemon")

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond (`docs/testovani.md`).
    private static func render(_ scene: AnyView, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene.frame(width: width, height: height))
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
