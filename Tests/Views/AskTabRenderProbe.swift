import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#452): vyrendruje tab `Zeptat se` ve třech stavech, aby se dal položit vedle
/// sekce 33 návrhu.
///
/// Je to obrázková otázka — *sedí bublina na akcentu, je prstýnek na místě příští bubliny, mají
/// otázky k odpíchnutí přerušovaný okraj* —, na kterou měření neodpoví. Rendruje se **samotný
/// `AskView`**, ne celý detail: tab panel nemá (`showsReviewPanel == false`), takže o jeho
/// sourozencích není co říct.
///
/// `NSHostingView`, ne `ImageRenderer`: obsah je ve `ScrollView`u, který `ImageRenderer`
/// nerasterizuje (poučení z #291 a #294).
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, cesta ven přes `PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda tabu Zeptat se (#452)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AskTabRenderProbe {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)

    private static let chips = Policy.askContextChips(
        diffFiles: 8,
        findings: 3,
        blockingFindings: 1,
        comments: 12,
        checks: 6
    )

    private static let conversation: [AskMessage] = [
        AskMessage(
            speaker: .mine,
            text: "Proč se ten mutex bere kolem celého `fetch`, a ne jen kolem zápisu do cache?",
            at: now.addingTimeInterval(-120)
        ),
        AskMessage(
            speaker: .claude,
            text: """
                Protože `fetch` po minulé změně **sám plní cache**, ne jen čte — zámek kolem zápisu \
                by dvě souběžná volání pustil oběma do `client->fetch()` a druhé by přepsalo \
                čerstvější hodnotu.

                Stojí to na `a1f77c2`, kde se ta cesta obrátila. V tomhle PR je to \
                src/SecretClient.php:80.
                """,
            at: now.addingTimeInterval(-108),
            readFiles: ["SecretClient.php", "CacheWarmer.php"],
            usage: RunUsage(cost: 0.04, duration: .seconds(12), turns: 4)
        ),
        AskMessage(
            speaker: .mine,
            text: "A ten nález od **php-review** o timeoutu — je to reálné, nebo šum?",
            at: now
        ),
    ]

    @Test("Vyrendrovat tab Zeptat se")
    func rendersTheAskTab() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())

        let scenarios: [(name: String, view: AskView)] = [
            (
                "prazdny",
                AskView(content: Policy.askTab(conversation: nil, isAnswering: false), chips: Self.chips)
            ),
            (
                "rozhovor",
                AskView(
                    content: .thread(messages: Self.conversation, isAnswering: true),
                    chips: Self.chips,
                    activity: "čte nálezy…",
                    cancel: {},
                    jump: { _ in }
                )
            ),
            (
                "odpoved-hotova",
                AskView(
                    content: .thread(messages: Array(Self.conversation.prefix(2)), isAnswering: false),
                    chips: Self.chips,
                    draft: "Co bych měl prověřit, než tohle schválím?",
                    jump: { _ in }
                )
            ),
        ]

        for scenario in scenarios {
            for width in [1047.0, 647.0] as [CGFloat] {
                let url = directory.appending(path: "ask-\(scenario.name)-\(Int(width)).png")
                try capture(scenario.view, width: width, to: url)
                print("SONDA \(url.path) — \(scenario.name), šířka \(Int(width))")
            }
        }
    }

    private func capture(_ view: AskView, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(
            rootView: view
                .frame(width: width, height: 520)
                .background(Palette.surface)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 520)
        // Okno mimo obrazovku: `ScrollView` bez okna nerozvrhne obsah — tatáž potíž jako
        // u `DetailTabRenderProbe`.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
