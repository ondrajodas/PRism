import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#542): vyrendruje tab `Změněné soubory` **v obou podobách selhání**.
///
/// Proč sonda a ne měření: „pozná se z toho, co se stalo a co s tím?“ je otázka na obrázek. Co se
/// **dá** tvrdit číslem, je v `DiffFailureTests` (výčet příčin) a v `AppStoreDiffCapTests` (že se
/// nic nespustilo a že zbytek okna zůstal). Sonda je k tomu, aby se strop a obyčejné selhání daly
/// **přečíst vedle sebe** — je to jediné místo, kde je vidět, že u jednoho stojí `Otevřít na
/// GitHubu` a u druhého `Zkusit znovu`.
///
/// **Klikání v běžící aplikaci k tomuhle nestačilo**: přepnout na `Změněné soubory` znamená klik
/// a `osascript` v téhle session **nemá asistenční přístup** (`-25211`). Offscreen render tu cestu
/// obchází legálně — hostuje týž `PullRequestDetailView`, jaký je v okně.
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, cesta ven přes `PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda selhání diffu (#542)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DiffFailureRenderProbe {
    private enum Scenario: String, CaseIterable {
        /// Strop GitHub API na počet souborů — skutečná odpověď nad `home-assistant/core#181088`.
        case cap = "strop"
        /// Cokoli jiného, tady výpadek sítě: tatáž obrazovka, jiná věta i jiná nabídka.
        case network = "sit"
    }

    @Test("Vyrendrovat obě podoby selhání diffu")
    func rendersBothFailures() async throws {
        let directory = Self.outputDirectory
        for scenario in Scenario.allCases {
            let (store, cache) = try await prepared(scenario)
            defer { _ = cache }
            for width in [1400.0, 900.0] as [CGFloat] {
                let url = directory.appending(path: "diff-selhani-\(scenario.rawValue)-\(Int(width)).png")
                try await capture(store: store, width: width, to: url)
                print("SONDA \(url.path) — \(scenario.rawValue), \(Int(width)) b, "
                    + "stav \(String(describing: store.diffState(for: Self.summary.id)))")
            }
        }
    }

    private func prepared(_ scenario: Scenario) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let failure: any Error = switch scenario {
        case .cap: GitHubError(
            failure: ProcessResult(
                exitCode: 1,
                standardOutput: "",
                standardError: try Fixture.text("gh/pr-diff-too-large.txt")
            )
        )
        case .network: GitHubError.network("dial tcp: lookup api.github.com: no such host")
        }
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.failure(failure)]
        )
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        store.openTab(Self.summary.id)
        store.setDetailTab(.filesChanged, for: Self.summary.id)
        return (store, directory)
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond, viz `docs/testovani.md`.
    private func capture(store: AppStore, width: CGFloat, to url: URL) async throws {
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil),
            merge: .constant(nil),
            branchPush: .constant(nil)
        )
        .frame(width: width, height: Self.height)
        .background(Palette.background)

        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        // Tři kroky, a **pořadí je podmínka, ne opatrnost**. `.task` v detailu si diff dotáhne
        // znovu (spadlý se za platný nepovažuje), takže: (1) kolo smyčky, aby se hierarchie
        // složila a to dotažení vůbec začalo; (2) **čekání na jev, ne na čas** (#296) — smyčka
        // drží hlavní actor, takže se stav v ní nehne ani po 1,5 s (změřeno); (3) druhé kolo na
        // překreslení. Bez prvního kroku se čekání vrátí hned nad **starým** `.failed` a vyfotí
        // se `Načítám diff…`.
        _ = spinMainRunLoop(seconds: 0.3)
        await waitUntil("diff dopadne") {
            if case .failed = store.diffState(for: Self.summary.id) { true } else { false }
        }
        _ = spinMainRunLoop(seconds: 0.3)
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    private static let height: CGFloat = 700

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "home-assistant", name: "core"), number: 181_088),
        title: "2026.9.0",
        author: "frenck",
        url: URL(string: "https://github.com/home-assistant/core/pull/181088")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "29f9b353",
        baseSha: "759e4658",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Home Assistant 2026.9.0 release pull request."
    )
}
