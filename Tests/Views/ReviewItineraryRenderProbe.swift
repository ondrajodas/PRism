import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Jak vypadá itinerář review** (#506) — sonda, ne test: vyrendruje sloupec do PNG a napíše
/// cestu, aby se dal položit vedle sekce 47 návrhu.
///
/// Kreslí se v **okně bez animace** (#462) přes `NSHostingView`, ne `ImageRenderer`em: sloupec
/// je `ScrollView` a ten se offscreen nevykreslí vůbec.
///
/// Kreslí se **produkčním sloupcem** (`ItineraryColumnView`, od #506/2 vlastní typ v detailu PR),
/// takže se sonda s oknem rozejde jedině tehdy, když se rozejde kresba: do #506/2 si tu hlavičku
/// i proužek skládala sama, protože byly v `DiffView` privátní.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — `xcodebuild` předá do testovacího procesu jen proměnné s tím
/// prefixem, takže bez něj se sonda tiše přeskočí. **A je to podmínka, ne pohodlí**: vznikají
/// v ní `NSHostingView`y, a přesně v takovém procesu vydá `NSFont` přechodně nepoužitelnou
/// metriku (#407, #550) — v jednom běhu s `ItineraryColumnRoomTests` to tu jednou padlo na
/// `charactersPerSide == 0`.
@MainActor
@Suite(
    "Sonda — itinerář review (#506)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ReviewItineraryRenderProbe {
    private static let at = Date(timeIntervalSince1970: 1_756_000_000)

    /// Sada souborů ze sekce 03 návrhu, se stavy značek ze sekce 40.
    private var files: [FileDiff] {
        [
            ItineraryFileFactory.file("src/Vault/SecretClient.php", additions: 18, deletions: 6),
            ItineraryFileFactory.file("src/Vault/Encryptor.php", additions: 4, deletions: 2),
            ItineraryFileFactory.file(
                "src/Vault/SecretNotFound.php", change: .added, additions: 21, deletions: 0
            ),
            ItineraryFileFactory.file("tests/SecretClientTest.php", additions: 64, deletions: 0),
            ItineraryFileFactory.file("composer.json", additions: 2, deletions: 1),
            ItineraryFileFactory.file("composer.lock", additions: 1_402, deletions: 1_388),
            ItineraryFileFactory.file("phpunit.xml.dist", additions: 1, deletions: 1),
        ]
    }

    private var markers: [String: FileMarker] {
        [
            "src/Vault/SecretClient.php": .blocking,
            "src/Vault/Encryptor.php": .findings,
        ]
    }

    private var readStates: [String: FileReviewState] {
        [
            "src/Vault/SecretNotFound.php": .read(at: Self.at),
            "tests/SecretClientTest.php": .read(at: Self.at),
            "composer.lock": .changed(readAt: Self.at),
        ]
    }

    private var facts: ItineraryFacts {
        ItineraryFacts(
            hasVisitRecord: true,
            commitsSinceVisit: 3,
            sawChangesSinceVisit: true,
            descriptionKnown: true,
            hasDescription: true,
            descriptionScrolled: true,
            fileCount: 7,
            readFileCount: 2,
            unreadLineCount: 240,
            checks: ChecksSummary(passed: 11, failed: 1, running: 0, skipped: 0),
            openedFailedChecks: 0,
            verdictSubmitted: false,
            verdict: .requestChanges
        )
    }

    /// **Plný itinerář**: pět zastávek, dvě hotové, `Kontroly` se spadlým checkem, soubory podle
    /// rizika a tři konfigurace složené do jedné položky.
    @Test("Vyrendrovat itinerář s pěti zastávkami")
    func rendersTheFullItinerary() throws {
        try render(actions, expanded: true, named: "itinerar-plny", height: 400)
    }

    /// **Složený proužek** (`⌘1`) — 34 bodů s počtem souborů. Od #506/2 je vidět **ve všech
    /// tabech**, takže je to podoba, na kterou se kouká nejčastěji: v pohledu vedle sebe se
    /// sloupec skládá sám (#188).
    @Test("Vyrendrovat složený proužek sloupce")
    func rendersTheCollapsedRail() throws {
        try render(actions, expanded: false, named: "itinerar-slozeny", height: 200)
    }

    /// Zastávky a počítadlo z `Policy` — jedno místo pro obě kresby.
    private var actions: ItineraryActions {
        let stops = Policy.itinerary(facts)
        return ItineraryActions(
            stops: stops,
            progress: Policy.itineraryProgress(of: stops, facts: facts),
            select: { _ in }
        )
    }

    private func render(
        _ actions: ItineraryActions,
        expanded: Bool,
        named name: String,
        height: CGFloat
    ) throws {
        // **Šířka z produkční funkce, ne konstanta**: sonda se má s oknem rozejít jedině tehdy,
        // když se rozejde kresba.
        let width = expanded ? ItineraryColumnView.width : ItineraryRailView.width
        let column = ItineraryColumnView(
            items: Policy.filesByRisk(
                files,
                markers: markers,
                threadPaths: ["tests/SecretClientTest.php"]
            ),
            itinerary: actions,
            markers: markers,
            readStates: readStates,
            collapse: {},
            jump: { _ in }
        )
        let scene = Group {
            if expanded {
                column
            } else {
                ItineraryRailView(files: files.count) {}
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Palette.chrome)

        let url = Self.outputDirectory.appending(path: "\(name).png")
        try Self.render(AnyView(scene), width: width, height: height, to: url)
        print("SONDA \(url.path)")
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

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
