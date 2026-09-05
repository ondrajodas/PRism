import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#528): vyrendruje **composer s návrhem** a **vlákno s návrhem** vedle sebe,
/// aby se dala kresba položit vedle sekce 54 návrhu.
///
/// Proč sonda: „drží mini diff rytmus diffu“ a „nesplývá náhled s polem, do kterého se píše“ jsou
/// otázky na obrázek, ne na číslo. Co se **dá** tvrdit číslem, je v `CodeSuggestionTests`.
///
/// Rendruje se v **obou motivech** a ve **dvou šířkách**: bublina u kódu dostane celou plochu
/// diffu, kdežto ve vlákně na ose konverzace stojí v panelu — a mini diff se v něm ořezává, což je
/// zrovna to, co má být vidět.
///
/// `NSHostingView`, ne `ImageRenderer`: `DraftTextEditor` je AppKitové pole a to se offscreen
/// nerasterizuje. Tatáž cesta jako u ostatních sond, viz `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda návrhu změny kódu (#528)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct SuggestionRenderProbe {
    private let original = [
        "        $row = $this->cache->get($key) ?? $this->client->fetch($key);",
        "        return $row['value'] ?? '';",
    ]

    private var body: String {
        """
        Fallback bych otočil — chybějící secret má být chyba, ne prázdný řetězec:

        ```suggestion
                $row = $this->cache->get($key) ?? $this->client->fetch($key);
                return $row['value'] ?? throw new SecretNotFound($key);
        ```
        """
    }

    @Test("Vyrendrovat composer s návrhem a vlákno s návrhem")
    func rendersBothSides() throws {
        let directory = Self.outputDirectory

        let comment = ReviewDraftComment(
            path: "src/Vault/SecretClient.php",
            anchor: DraftAnchor(line: 81, side: .right, start: DraftAnchor.Endpoint(line: 80, side: .right)),
            body: body,
            origin: .own
        )
        let composer = DraftCommentBubbleView(
            comment: comment,
            indent: 54,
            suggestion: .available(CodeSuggestion(
                original: original,
                replacement: [
                    "        $row = $this->cache->get($key) ?? $this->client->fetch($key);",
                    "        return $row['value'] ?? throw new SecretNotFound($key);",
                ]
            ))
        )

        // Odmítnutý výběr — věta musí být čitelná i v úzkém místě, protože tlačítko vedle ní je
        // zakázané a jinak se důvod nedozví nikdo.
        let refused = DraftCommentBubbleView(
            comment: ReviewDraftComment(
                path: "src/Vault/SecretClient.php",
                anchor: DraftAnchor(line: 120, side: .right, start: DraftAnchor.Endpoint(line: 81, side: .right)),
                body: "Tenhle výběr přeskakuje mezeru v diffu.",
                origin: .own
            ),
            indent: 54,
            suggestion: .refused(Policy.suggestionRefusalAcrossHunks)
        )

        let thread = ThreadBubbleView(
            thread: Self.thread,
            viewer: "ondrajodas",
            indent: 0,
            actions: ThreadActions(handoff: { _ in }),
            placement: .timeline
        )
        let foreign = ThreadBubbleView(
            thread: Self.thread,
            viewer: "ondrajodas",
            indent: 0,
            // Cizí PR: `handoff` je `nil`, takže se tlačítko **nemá nakreslit vůbec**.
            actions: ThreadActions(),
            placement: .timeline
        )

        for theme in [("svetly", NSAppearance(named: .aqua)), ("tmavy", NSAppearance(named: .darkAqua))] {
            let scene = VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: "composer u řádku — návrh vložený tlačítkem")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink3)
                composer
                Text(verbatim: "composer u řádku — výběr, ke kterému návrh napsat nejde")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink3)
                refused
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "vlákno na vlastním PR (300 b)")
                            .font(.system(size: 11)).foregroundStyle(Palette.ink3)
                        thread.frame(width: 300)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "vlákno na cizím PR (300 b) — bez tlačítka")
                            .font(.system(size: 11)).foregroundStyle(Palette.ink3)
                        foreign.frame(width: 300)
                    }
                }
            }
            .padding(16)
            .frame(width: 980, alignment: .topLeading)
            .background(Palette.surface)

            let url = directory.appending(path: "navrh-zmeny-\(theme.0).png")
            try render(scene, appearance: theme.1, width: 980, height: 900, to: url)
            print("SONDA \(url.path) — \(theme.0)")
        }
    }

    private func render(
        _ scene: some View,
        appearance: NSAppearance?,
        width: CGFloat,
        height: CGFloat,
        to url: URL
    ) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle běží další sloty.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    private static let thread = ReviewThread(
        id: "t1",
        path: "src/Vault/SecretClient.php",
        line: 41,
        originalLine: 41,
        side: .right,
        isResolved: false,
        isOutdated: false,
        diffHunk: """
            @@ -38,4 +38,5 @@ public function __construct(
                     private readonly CacheInterface $cache,
            -        private readonly int $ttl = 300,
            +        private readonly int $ttl = self::MAX_TTL,
            """,
        comments: ConversationPage(
            items: [
                ThreadComment(
                    id: "c1",
                    author: "odinuv",
                    body: """
                        TTL bych nechal přebít z konfigurace tenanta:

                        ```suggestion
                                private readonly int $ttl = self::MAX_TTL, private readonly ?int $ttlCeiling = null,
                        ```
                        """,
                    createdAt: Date(timeIntervalSince1970: 1_754_000_000),
                    url: URL(string: "https://github.com/ondrajodas/PRism/pull/412#discussion_r1")!
                )
            ],
            total: 1,
            hasNextPage: false
        )
    )
}
