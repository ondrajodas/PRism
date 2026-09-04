import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#502): vykreslí **řádek fronty s mini pásem mapy PR ve dvou šířkách** a v obou
/// režimech, aby se dalo **vidět**, co se do řádku vejde.
///
/// Existuje vedle `QueueMapStripTests` proto, že měření odpovídá na „zůstal řádek na jedné řádce“,
/// kdežto otázka #502 je „je ten pás v řádku k něčemu“ — jestli se z něj pozná, kde v PR je co
/// k vyřízení, když má 110 bodů. Na to se dá odpovědět jedině obrázkem.
///
/// **Dvě šířky, a obě jsou hranice**, ne vzorky: **636 bodů** je obsah nejužšího povoleného okna
/// bez railu (tam se pás tluče s titulkem a odznakem) a **900** je běžná šířka seznamu. Na plátně
/// jsou pod sebou i řádky, u kterých se pás **nekreslí** — bez nich by z obrázku nešlo poznat,
/// jestli je prázdno záměr, nebo vada.
///
/// **`NSHostingView`, ne `ImageRenderer`** — tatáž cesta jako `PillRenderProbe`, viz
/// `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — **prefix `TEST_RUNNER_` je povinný**, `xcodebuild` posílá do
/// testovacího procesu jen proměnné s ním. Bez něj se sonda tiše přeskočí a vypadá to, že prošla.
@MainActor
@Suite(
    "Sonda řádku fronty s mapou PR (#502)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct QueueRowRenderProbe {
    @Test("Vyrendrovat řádek fronty ve dvou šířkách")
    func rendersTheRowAtTwoWidths() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in [636.0, 900.0] {
            for dark in [false, true] {
                let url = directory.appending(path: "radek-fronty-\(Int(width))-\(dark ? "tmavy" : "svetly").png")
                let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
                var thrown: (any Error)?
                appearance.performAsCurrentDrawingAppearance {
                    do {
                        try capture(scene(dark: dark, width: width), width: width, to: url)
                    } catch {
                        thrown = error
                    }
                }
                if let thrown { throw thrown }
                print("SONDA \(url.path)")
            }
        }
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func scene(dark: Bool, width: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("s pásem — blokující nález v `composer.lock`, dva soubory prošlé")
            row(map: map(blocking: true), blocking: 1)
            label("s pásem — nálezy, nic neblokuje")
            row(map: map(blocking: false), blocking: 0)
            label("bez pásu — na PR nic neběželo (`neběželo`)")
            row(map: nil, state: .notStarted)
            label("bez pásu — review běželo, ale diff aplikace ještě neviděla")
            row(map: nil)
        }
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        .tint(Palette.accent)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func row(
        map: PullRequestMap?,
        state: ReviewState = .completed(findings: 3),
        blocking: Int = 0
    ) -> some View {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("keboola/vault#85")!,
                title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/85")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: state,
            row: QueueRow(blocking: blocking),
            map: map
        )
        .padding(.horizontal, 10)
    }

    /// Referenční rozložení ze sekce 42 návrhu — sedm souborů `keboola/vault#85`, ve kterých
    /// `composer.lock` mění 2 790 řádků. **Tatáž data jako v obou sadách nad mapou**, ať obrázek
    /// a čísla mluví o jednom pásu.
    private func map(blocking: Bool) -> PullRequestMap {
        Policy.pullRequestMap(
            files: [
                ("src/Vault/SecretClient.php", 24),
                ("src/Vault/Encryptor.php", 43),
                ("src/Vault/SecretNotFound.php", 21),
                ("tests/SecretClientTest.php", 64),
                ("composer.json", 4),
                ("composer.lock", 2790),
                ("phpunit.xml.dist", 6),
            ].map(file(_:)),
            findings: Policy.groups(of: [
                makeFinding(
                    file: "composer.lock",
                    line: 2,
                    category: blocking ? "correctness" : "style",
                    verdict: .confirmed,
                    summary: "nález v locku"
                ),
                makeFinding(
                    file: "src/Vault/Encryptor.php",
                    line: 2,
                    category: "style",
                    verdict: .confirmed,
                    summary: "nález v Encryptoru"
                ),
            ]),
            readStates: [
                "src/Vault/SecretClient.php": .read(at: Date(timeIntervalSince1970: 1_000_000)),
                "composer.json": .read(at: Date(timeIntervalSince1970: 1_000_000)),
            ]
        )
    }

    private func file(_ input: (path: String, lines: Int)) -> FileDiff {
        FileDiff(
            oldPath: input.path,
            newPath: input.path,
            change: .modified,
            isBinary: false,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: input.lines,
                    newStart: 1,
                    newCount: input.lines,
                    heading: "",
                    lines: (0..<input.lines).map {
                        DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "nové")
                    }
                )
            ],
            blobs: "aaa..bbb"
        )
    }

    private func capture(_ scene: some View, width: Double, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle sebe běží víc slotů.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
