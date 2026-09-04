import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#500): vyrendruje **hlavičku souboru se značkou `Prošlo`** ve všech třech
/// stavech — tedy to, co kreslí sekce 40 návrhu. Seznam souborů s ✓ a ↻ se od #506 rendruje
/// v `ReviewItineraryRenderProbe`, protože tam patří i hlavička sloupce a proužek podílu.
///
/// Proč sonda: „sedí to se sekcí 40?“ je otázka na obrázek. Co se **dá** tvrdit číslem, je
/// v `FileReviewStateTests` (stavy a popisky) a v `AppStoreReadMarkTests` (co se stane po pushi).
///
/// `NSHostingView`, ne `ImageRenderer` — tatáž cesta jako u ostatních sond, viz
/// `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — `xcodebuild` předá do testovacího procesu jen proměnné s tím
/// prefixem, takže bez něj se sonda tiše přeskočí.
@MainActor
@Suite(
    "Sonda značky Prošlo (#500)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct FileReadMarkRenderProbe {
    private static let at = Date(timeIntervalSince1970: 1_756_000_000)

    /// Čtyři hlavičky pod sebou, jak je má zákres: nepřečtený soubor s blokujícím nálezem, dva
    /// prošlé (jeden s odznakem `nový`) a jeden `změněno od prošlého`.
    @Test("Vyrendrovat hlavičky souborů se značkou")
    func rendersFileHeaders() throws {
        let scene = VStack(alignment: .leading, spacing: 0) {
            header("src/Vault/SecretClient.php", additions: 18, deletions: 6, blocking: true)
            header("src/Vault/SecretNotFound.php", additions: 21, deletions: 0, change: .added,
                   read: .read(at: Self.at), folded: true)
            header("tests/SecretClientTest.php", additions: 64, deletions: 0,
                   read: .read(at: Self.at), folded: true)
            header("composer.lock", additions: 1402, deletions: 1388,
                   read: .changed(readAt: Self.at), folded: true)
        }
        .frame(width: 860, alignment: .topLeading)
        .background(Palette.surface)

        let url = Self.outputDirectory.appending(path: "proslo-hlavicky.png")
        try Self.render(AnyView(scene), width: 860, height: 160, to: url)
        print("SONDA \(url.path)")
    }

    /// Tytéž hlavičky v **úzkém** místě: 420 bodů je diff v pohledu vedle sebe na podlaze okna
    /// (700 minus rail, minus druhá strana). Zaškrtávátko si bere ~90 bodů, takže se tady vidí, co
    /// ustoupí — a `CLAUDE.md` na to má pravidlo: jiná šířka je jiný design.
    @Test("Vyrendrovat hlavičky v úzkém sloupci")
    func rendersFileHeadersWhenNarrow() throws {
        let scene = VStack(alignment: .leading, spacing: 0) {
            header("src/Vault/SecretClient.php", additions: 18, deletions: 6, blocking: true)
            header("tests/SecretClientTest.php", additions: 64, deletions: 0,
                   read: .read(at: Self.at), folded: true)
            header("composer.lock", additions: 1402, deletions: 1388,
                   read: .changed(readAt: Self.at), folded: true)
        }
        .frame(width: 420, alignment: .topLeading)
        .background(Palette.surface)

        let url = Self.outputDirectory.appending(path: "proslo-hlavicky-uzke.png")
        try Self.render(AnyView(scene), width: 420, height: 130, to: url)
        print("SONDA \(url.path)")
    }

    // **Třetí render (sloupec bez zastávek) tady od #506/2 není.** Kreslil tu podobu, kterou měl
    // sloupec v diffu commitu a v rozsahu od minule — a ta zanikla: sloupec od #506/2 stojí vedle
    // všech tabů, hostí ho detail PR a zastávky má vždycky. Seznam souborů s ✓, ↻ a puntíky nálezů
    // se rendruje v `ReviewItineraryRenderProbe`, kde je i s hlavičkou a proužkem podílu.

    // MARK: - Scéna

    private func file(
        _ path: String,
        change: FileDiff.Change = .modified,
        additions: Int = 1,
        deletions: Int = 1
    ) -> FileDiff {
        FileDiff(
            oldPath: change == .added ? nil : path,
            newPath: path,
            change: change,
            isBinary: false,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: deletions,
                    newStart: 1,
                    newCount: additions,
                    heading: "",
                    lines: (0..<additions).map {
                        DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "x")
                    } + (0..<deletions).map {
                        DiffLine(kind: .removed, oldNumber: $0 + 1, newNumber: nil, text: "y")
                    }
                )
            ],
            blobs: "aaa..bbb"
        )
    }

    private func header(
        _ path: String,
        additions: Int,
        deletions: Int,
        change: FileDiff.Change = .modified,
        blocking: Bool = false,
        read: FileReviewState = .unread,
        folded: Bool = false
    ) -> some View {
        DiffFileHeaderView(
            file: file(path, change: change, additions: additions, deletions: deletions),
            isFolded: folded,
            findings: blocking
                ? [FindingGroup(file: path, line: 81, findings: [makeFinding(file: path, line: 81)])]
                : [],
            blockingCategories: Policy.defaultBlockingCategories,
            toggle: {},
            read: read,
            toggleRead: {}
        )
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond.
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
