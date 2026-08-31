import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test: vyrendruje **potvrzení force pushe** ve stavech, ke kterým se klikáním
/// nedostaneš — dlouhý titulek commitu a velký počet commitů (#466, z proklikání).
///
/// Proč zrovna tyhle dva: sheet je široký jako `minWidth` (`idealWidth` u něj SwiftUI zahodí),
/// takže se dlouhý titulek musí vejít **zalomením**, a počet commitů je neomezený, takže má
/// `Policy.pushedCommitList` strop. Obojí je otázka na obrázek — co se dá tvrdit číslem, je
/// v `BranchSyncOfferTests` (strop výčtem) a v `RealBranchRebaseTests` (titulky z rebasu).
///
/// Sondu na sondu klikáním nenahradíš: k padesáti přehraným commitům by bylo potřeba PR, které je
/// o padesát commitů pozadu.
///
/// `NSHostingView` + `cacheDisplay`, ne `ImageRenderer`, ze stejného důvodu jako
/// `CodeSheetRenderProbe`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — prefix `TEST_RUNNER_` je to, čím `xcodebuild` proměnnou předá
/// hostu. **Bez něj se sonda nespustí a vypadá to, že prošla** (`Test run with 1 test … passed`
/// a nula obrázků); je to tatáž past, na kterou upozorňuje `CodeSheetRenderProbe`.
@MainActor
@Suite(
    "Sonda potvrzení force pushe (#466)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct BranchPushSheetRenderProbe {
    @Test("Vyrendrovat potvrzení s dlouhým titulkem a s mnoha commity")
    func rendersTheHardCases() throws {
        let directory = Self.outputDirectory
        // `replayed` je počet **tvých** přehraných; zbytek seznamu je z base a v kresbě dostane
        // značku. Scéna `z-base` je ta, kvůli které tenhle rozdíl vznikl (změřeno 1 proti 2).
        let scenes: [(String, [RebasedCommit], Int)] = [
            ("bezne", Self.ordinary, 3),
            ("z-base", Self.ordinary, 1),
            ("dlouhy-titulek", Self.longTitles, 2),
            ("hodne-commitu", Self.many, 44),
            ("jeden", [Self.ordinary[0]], 1),
        ]
        for (name, commits, replayed) in scenes {
            for scheme in [ColorScheme.light, .dark] {
                let file = "push-\(name)-\(scheme == .dark ? "tmavy" : "svetly").png"
                let url = directory.appending(path: file)
                try render(commits, replayed: replayed, scheme: scheme, to: url)
                print("SONDA \(url.path) — \(commits.count) na větvi, \(replayed) tvých")
            }
        }
    }

    /// Šířka, ve které se sheet doopravdy otevírá: `minWidth` z `BranchPushSheet.body`, protože
    /// `idealWidth` u sheetu SwiftUI zahodí. Výška je štědrá schválně — sonda má ukázat, jak
    /// vysoký ten obsah **je**, ne jak se ořízne.
    private static let size = CGSize(width: 460, height: 620)

    private func render(
        _ commits: [RebasedCommit],
        replayed: Int,
        scheme: ColorScheme,
        to url: URL
    ) throws {
        // **Pusher, který nikdy nespustí nic** — sonda jen kreslí. Bere se ten init, který cestu
        // ven dostane jako uzávěr, takže se sem `gh` ani brána nemusí tahat.
        let submission = BranchPushSubmission(
            pullRequest: Self.summary,
            plan: Self.plan,
            arriving: commits,
            replayed: replayed,
            pusher: { NeverPusher() },
            afterSuccess: { _ in }
        )
        let scene = BranchPushSheet(submission: submission, close: {}, discard: {})
            .environment(\.colorScheme, scheme)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Palette.surface)
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try png.write(to: url)
        window.orderOut(nil)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    // MARK: - Scény

    private static let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)

    private static var summary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "chore: modernize dependencies",
            author: "ondrajodas",
            url: URL(string: "https://github.com/keboola/vault/pull/85")!,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            state: .open
        )
    }

    private static var plan: BranchPushPlan {
        BranchPushPlan(
            pullRequest: pr,
            branch: "chore/deps-2026",
            expectedRemoteSha: "9bb4352aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            sha: "5c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            worktree: URL(filePath: "/tmp/prism-probe/sync")
        )
    }

    private static func commit(_ sha: String, _ title: String) -> RebasedCommit {
        RebasedCommit(sha: sha + String(repeating: "0", count: max(0, 40 - sha.count)), title: title)
    }

    private static let ordinary: [RebasedCommit] = [
        commit("a1b2c3d", "chore: bump symfony to 8.0"),
        commit("b2c3d4e", "fix: nezahazovat token při souběžném refreshi"),
        commit("c3d4e5f", "test: pokrýt prázdný secret"),
    ]

    /// Titulky, které se **musí zalomit**: sheet se kvůli nim rozšířit nemůže.
    private static let longTitles: [RebasedCommit] = [
        commit(
            "d4e5f60",
            "refactor: rozdělit BranchAwareClient na dvě třídy a přesunout cachování secretů "
                + "do vlastní vrstvy, protože se to jinak nedá otestovat bez živého Vaultu"
        ),
        commit("e5f6071", "fix: prázdný secret už neprojde fallbackem dál jako platná hodnota"),
        commit(
            "f607182",
            "chore(deps): PHPUnit 11, anotace nahrazeny atributy, deprecations z CI vyřešené "
                + "a composer.lock přegenerovaný proti novému minoru"
        ),
    ]

    /// Padesát commitů — tedy stav, ve kterém se pozná, jestli strop drží a jestli je pod výpisem
    /// pořád vidět výstraha o lease.
    private static let many: [RebasedCommit] = (0..<50).map {
        commit(String(format: "%07x", 0xA00000 + $0), "chore: krok \($0) v dlouhé řadě commitů")
    }
}

/// Cesta ven, která **nikdy nic neudělá**. Sonda kreslí, nepushuje — a `BranchPushSubmission`
/// pusher potřebuje, protože ho `push()` volá až za kliknutím.
private struct NeverPusher: BranchPushing {
    func push(_ plan: BranchPushPlan) async throws -> String {
        throw BranchSyncError.interrupted
    }
}
