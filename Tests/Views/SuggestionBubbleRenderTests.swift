import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že se návrh změny (#528) v okně **doopravdy kreslí** — a že se na cizím PR
/// `Do zadání pro agenta` **nekreslí vůbec**.
///
/// Druhá půlka je to podstatné a je to tvrzení o tom, co na obrazovce **není**. Nad
/// `ThreadActions` samotným se ověřit nedá: `nil` v modelu ještě neznamená, že se view zachovalo
/// správně — a kdyby se tlačítko začalo kreslit zašedle, v modelu by se nezměnilo nic.
///
/// **Rozdíl bitmap, ne čtení textu**: accessibility tree se v hostovaném okně nenaplní (změřeno
/// u `DashboardCountdownRedrawTests`). Tatáž cesta i tytéž meze jako u `EditorButtonRenderTests`;
/// okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Návrh změny se kreslí, do zadání jen na vlastním PR (#528)")
struct SuggestionBubbleRenderTests {
    // MARK: - Vlákno

    /// Na vlastním PR je pod vláknem tlačítko navíc, na cizím ne.
    @Test("U vlákna s návrhem je Do zadání pro agenta jen na vlastním PR")
    func theHandoffIsOnlyOnOwnPullRequests() throws {
        let foreign = try bitmap("vlakno-navrh-cizi", height: 420) {
            threadBubble(handoff: nil, body: Self.suggestionBody)
        }
        let mine = try bitmap("vlakno-navrh-vlastni", height: 420) {
            threadBubble(handoff: { _ in }, body: Self.suggestionBody)
        }

        #expect(foreign != mine)
    }

    /// **A u vlákna bez návrhu se nekreslí ani na vlastním PR.** Tohle je ta věta, která se rozbije
    /// potichu: kdyby se řádek s tlačítkem přestal vázat na návrh, přibyl by pod **každým** vláknem
    /// na vlastním PR — a nic by nespadlo.
    @Test("Vlákno bez návrhu tlačítko nedostane ani na vlastním PR")
    func anOrdinaryThreadGetsNoHandoff() throws {
        let foreign = try bitmap("vlakno-bez-navrhu-cizi", height: 420) {
            threadBubble(handoff: nil, body: "TTL bych nechal přebít z konfigurace tenanta.")
        }
        let mine = try bitmap("vlakno-bez-navrhu-vlastni", height: 420) {
            threadBubble(handoff: { _ in }, body: "TTL bych nechal přebít z konfigurace tenanta.")
        }

        #expect(foreign == mine)
    }

    /// Že se návrh kreslí **jinak než blok kódu** — to je celý důvod, proč #528 vzniklo. Tentýž
    /// text jen s jiným jazykem fence musí vyjít jinak.
    @Test("Návrh se ve vlákně kreslí jinak než obyčejný blok kódu")
    func aSuggestionLooksDifferentFromCode() throws {
        let code = try bitmap("vlakno-blok-kodu", height: 420) {
            threadBubble(handoff: nil, body: Self.suggestionBody.replacingOccurrences(of: "```suggestion", with: "```php"))
        }
        let suggestion = try bitmap("vlakno-navrh", height: 420) {
            threadBubble(handoff: nil, body: Self.suggestionBody)
        }

        #expect(code != suggestion)
    }

    // MARK: - Composer

    /// `Návrh změny` se kreslí jen tam, kde se na nabídku někdo ptal — bublina bez ní (náhled,
    /// sonda, test skládání řádků) tlačítko nemá.
    @Test("Tlačítko Návrh změny přibude, jen když se na nabídku někdo ptá")
    func theComposerButtonNeedsAnOffer() throws {
        let without = try bitmap("composer-bez-nabidky", height: 200) { composer(offer: nil) }
        let with = try bitmap("composer-s-nabidkou", height: 200) {
            composer(offer: .available(CodeSuggestion(original: Self.original, replacement: Self.original)))
        }

        #expect(without != with)
    }

    /// Náhled se čte z **těla komentáře**: tentýž komentář s blokem a bez něj musí vyjít jinak,
    /// jinak by mini diff kreslil něco, co v komentáři není.
    @Test("Náhled mini diffu se kreslí podle těla komentáře")
    func thePreviewFollowsTheBody() throws {
        let offer = SuggestionOffer.available(CodeSuggestion(original: Self.original, replacement: Self.original))
        let plain = try bitmap("composer-bez-navrhu", height: 260) {
            composer(offer: offer, body: "Fallback bych otočil.")
        }
        let withBlock = try bitmap("composer-s-navrhem", height: 260) {
            composer(offer: offer, body: Self.suggestionBody)
        }

        #expect(plain != withBlock)
    }

    // MARK: - Scény

    private func threadBubble(handoff: ((ReviewThread) -> Void)?, body: String) -> some View {
        ThreadBubbleView(
            thread: Self.thread(body: body),
            viewer: "ondrajodas",
            indent: 0,
            actions: ThreadActions(handoff: handoff),
            placement: .code
        )
    }

    private func composer(offer: SuggestionOffer?, body: String = Self.suggestionBody) -> some View {
        DraftCommentBubbleView(
            comment: ReviewDraftComment(
                path: "src/Vault/SecretClient.php",
                anchor: DraftAnchor(
                    line: 81,
                    side: .right,
                    start: DraftAnchor.Endpoint(line: 80, side: .right)
                ),
                body: body,
                origin: .own
            ),
            indent: 0,
            suggestion: offer
        )
    }

    // MARK: - Data

    private static let original = [
        "        $row = $this->cache->get($key) ?? $this->client->fetch($key);",
        "        return $row['value'] ?? '';",
    ]

    private static let suggestionBody = """
        TTL bych nechal přebít z konfigurace tenanta:

        ```suggestion
                private readonly int $ttl = self::MAX_TTL, private readonly ?int $ttlCeiling = null,
        ```
        """

    private static func thread(body: String) -> ReviewThread {
        ReviewThread(
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
                        body: body,
                        createdAt: Date(timeIntervalSince1970: 1_754_000_000),
                        url: URL(string: "https://github.com/ondrajodas/PRism/pull/412#discussion_r1")!
                    )
                ],
                total: 1,
                hasNextPage: false
            )
        )
    }

    /// **Vzhled se nastavuje na svém okně**, ne na `NSApp` (#367). Tatáž cesta jako
    /// u `EditorButtonRenderTests` — bitmapa je tvrzení, ale dá se pustit i na disk.
    private func bitmap<Content: View>(
        _ name: String,
        width: CGFloat = 360,
        height: CGFloat,
        _ content: () -> Content
    ) throws -> Data {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var result: Result<Data, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let scene = content()
                    .frame(width: width, height: height, alignment: .topLeading)
                    .environment(\.colorScheme, .dark)
                    .tint(Palette.accent)
                    .background(Palette.surface)
                let hosting = NSHostingView(rootView: scene)
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
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "navrh-\(name).png")
                    try png.write(to: url)
                    print("RENDER \(url.path)")
                }
                result = .success(png)
            } catch {
                result = .failure(error)
            }
        }
        return try #require(result).get()
    }
}
