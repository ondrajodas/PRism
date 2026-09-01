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
        let scenes: [(String, [RebasedCommit], Int, ConflictResolution?)] = [
            ("bezne", Self.ordinary, 3, nil),
            ("z-base", Self.ordinary, 1, nil),
            ("dlouhy-titulek", Self.longTitles, 2, nil),
            ("hodne-commitu", Self.many, 44, nil),
            ("jeden", [Self.ordinary[0]], 1, nil),
            // #467 — po doběhnutí session, před přetlačením (návrh sekce 36). Tři scény, protože
            // jsou to tři různé otázky na obrázek: jestli je pod výpisem a diffem **pořád vidět
            // výstraha o lease**, jestli se dlouhý diff usekne na stropu, a jak vypadá stav, ve
            // kterém session soubory nezměnila.
            ("konflikt", Self.ordinary, 3, Self.resolution),
            ("konflikt-dlouhy-diff", Self.ordinary, 3, Self.longDiffResolution),
            ("konflikt-bez-diffu", Self.ordinary, 3, Self.emptyDiffResolution),
        ]
        for (name, commits, replayed, resolution) in scenes {
            for scheme in [ColorScheme.light, .dark] {
                let file = "push-\(name)-\(scheme == .dark ? "tmavy" : "svetly").png"
                let url = directory.appending(path: file)
                try render(commits, replayed: replayed, resolution: resolution, scheme: scheme, to: url)
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
        resolution: ConflictResolution? = nil,
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
            base: "main",
            resolution: resolution,
            pusher: { NeverPusher() },
            afterSuccess: { _ in }
        )
        let scene = BranchPushSheet(
            submission: submission,
            close: {},
            discard: {},
            // Terminál se kreslí **jedině nad výsledkem session** (#467), takže sonda tu podmínku
            // musí kopírovat — jinak by ukazovala patku, jakou aplikace nikdy nenakreslí.
            openTerminal: resolution == nil ? nil : {}
        )
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

    // MARK: - Výsledek session (#467)

    /// Účet ze zákresu (návrh sekce 36) — dva slité soubory a jeden, který session nechala být.
    private static let resolution = ConflictResolution(
        files: [
            ResolvedConflictFile(path: "composer.lock", action: .tookBoth),
            ResolvedConflictFile(path: "src/Vault/SecretClient.php", action: .manual),
            ResolvedConflictFile(path: "tests/VaultTest.php", action: .unchanged),
        ],
        diff: """
            diff --git a/src/Vault/SecretClient.php b/src/Vault/SecretClient.php
            index 8948000..0663daf 100644
            --- a/src/Vault/SecretClient.php
            +++ b/src/Vault/SecretClient.php
            @@ -112,7 +112,7 @@ final class SecretClient
                     $client = $this->factory->create();
            -        $timeout = 30;
            +        $timeout = $this->config->timeout();
                     return $client->withTimeout($timeout);
            """,
        rounds: 1,
        usage: RunUsage(cost: 0.68),
        caveats: "U composer.lock jsem obě sady balíčků jen slil — lockfile může chtít přegenerovat."
    )

    /// Diff přes strop: otázka je, jestli se usekne a jestli pod ním **zůstane vidět výstraha
    /// o lease**. Neomezený výpis by ji odrolil pod hranu a z potvrzení by zbyl diff.
    private static var longDiffResolution: ConflictResolution {
        var resolution = resolution
        resolution.diff = (0..<120)
            .map { $0 % 3 == 0 ? "+ pridany radek \($0)" : ($0 % 3 == 1 ? "- smazany radek \($0)" : "  kontext \($0)") }
            .joined(separator: "\n")
        return resolution
    }

    /// Session soubory nezměnila (vzala jednu stranu tak, jak byla), nebo se diff nepodařilo
    /// přečíst. **Prázdné místo pod nadpiskem se nesmí čtl jako „nic se nezměnilo“**, takže sonda
    /// kontroluje, že tam stojí věta.
    private static var emptyDiffResolution: ConflictResolution {
        var resolution = resolution
        resolution.diff = ""
        resolution.caveats = nil
        return resolution
    }

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
