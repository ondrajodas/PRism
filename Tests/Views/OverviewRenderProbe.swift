import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#291): vykreslí `Přehled` přes `NSHostingView`, aby se dal **vidět**.
///
/// Existuje vedle `OverviewWidthTests` proto, že měření odpovídá na „přeteklo, nebo ne“, kdežto
/// otázka „vejde se hlavička karty do zúženého tabu“ je otázka na vzhled. `ImageRenderer` na ni
/// odpovědět neumí: `Link` v něm vyjde jako **žlutý placeholder**, takže se z něj šířka popisku
/// `Otevřít na GitHubu` nepozná — a přesně ten popisek byl v #291 odříznutý. `NSHostingView` kreslí
/// skutečnou hierarchii, takže odkaz v něm stojí ve své šířce.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda Přehledu (#291)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct OverviewRenderProbe {
    /// Nejužší tab, na který se dá v okně přijít (okno 700 s panelem na 300), a pohodlná šířka
    /// nad ním. Sazba se v každé zalomí jinak, takže jedna nestačí.
    private let widths: [CGFloat] = [320, 560, 900]

    /// Stavy pruhu „od tvé poslední návštěvy“ (#284). **Všechny se posuzují okem**, protože se liší
    /// právě tím, co je v řadě pod odrážkami — a to se z kódu nepozná: odznak `nálezy zastaraly` má
    /// být jedině tam, kde nálezy doopravdy jsou, a `Ukázat, co přibylo` jedině tam, kde je co
    /// porovnat.
    private enum Scenario: String, CaseIterable {
        /// Bez pruhu — kvůli #280 zůstává: řada faktů má nad sebou buď pruh, nebo nic.
        case none = "bez-pruhu"
        /// Tři nové commity, review na PR ještě neběželo. Řada má jen `Ukázat, co přibylo`.
        case commits = "nove-commity"
        /// Nové commity a nálezy, které jimi zastaraly. **Nejširší řada** — odznak a dvě tlačítka.
        case staleFindings = "zastarale-nalezy"
        /// Přepsaná historie bez nálezů: `Pustit review znovu` ano, odznak ne, rozsah ne.
        case rewritten = "prepsana-historie"
        /// Přepsaná historie nad nálezy: odznak a `Pustit review znovu`, rozsah pořád ne.
        case rewrittenWithFindings = "prepsana-se-zastaralymi"
    }

    @Test("Vyrendrovat Přehled do PNG")
    func rendersOverview() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in widths {
            for dark in [false, true] {
                for scenario in Scenario.allCases {
                    let url = directory.appending(
                        path: "prehled-\(Int(width))-\(dark ? "tmavy" : "svetly")-\(scenario.rawValue).png"
                    )
                    try write(width: width, dark: dark, scenario: scenario, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u bloku kódu
    /// (#236) a u odpočtu (#269), viz `docs/testovani.md`.
    ///
    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(width: CGFloat, dark: Bool, scenario: Scenario, to url: URL) throws {
        let scene = OverviewView(
            description: Self.description,
            facts: Self.facts,
            // **Varianta s pruhem je kvůli #280.** Řada faktů se přesunula nad popis, takže jejím
            // novým sousedem shora je pruh „Od tvé poslední návštěvy“ — a ten je okrový
            // (`Palette.stale`) zrovna tak jako zastaralá sha v posledním boxíku. Dvě okrové plochy
            // nad sebou se posuzují okem, ne z kódu, takže se musí dát vidět.
            changes: Self.changes(in: scenario),
            lastVisit: Date(timeIntervalSince1970: 1_754_000_000),
            isStale: scenario == .staleFindings || scenario == .rewrittenWithFindings,
            hasStaleFindings: scenario == .staleFindings || scenario == .rewrittenWithFindings,
            movedHead: scenario == .none ? nil : "9c1de0212ab",
            rerun: scenario == .none ? nil : {},
            // Rozsah se nabízí jedině tam, kde se dnešní hlava dá s čím porovnat — po přepsané
            // historii ne (`Policy.incrementalDiff`), takže se to tak musí i vyrendrovat.
            showAdded: scenario == .commits || scenario == .staleFindings ? {} : nil,
            pullRequest: Self.pullRequest
        )
        .content
        .availableWidth(width)
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        .environment(\.colorScheme, dark ? .dark : .light)

        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                try capture(scene, width: width, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Scéna do okna, okno do bitmapy, bitmapa do souboru.
    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu vedle sebe
        // stojí víc instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        // Hierarchie se doskládá až po jednom kole smyčky, takže se výška bere znovu až za ní.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static let pullRequest = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let description = """
        ## Popis

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
        aby se v úzkém tabu zalomil na několik řádků.

        - první odrážka
        - [x] hotová položka

        > [!NOTE]
        > Poznámka od bota.

        ```swift
        let x = 1
        ```
        """

    private static let facts = PullRequestFacts(
        tiles: [
            .init(caption: "Commity", value: "12", note: "3 nové"),
            .init(caption: "Soubory", value: "8", note: "2 s nálezem"),
            .init(caption: "Hlava", value: "abc1234", isMonospaced: true),
            .init(caption: "Nálezy proti", value: "def5678", isMonospaced: true, isStale: true),
        ]
    )

    /// Co pruh v tom kterém stavu vypisuje. Force push je nejhustší odrážka — nese i to, která sha
    /// na větvi už není — kdežto commity nesou autora a poslední sha, tedy sazbu z návrhu celou.
    private static func changes(in scenario: Scenario) -> VisitChanges {
        switch scenario {
        case .none:
            .none
        case .commits, .staleFindings:
            VisitChanges(
                commits: (0..<3).map { index in
                    TimelineEvent(
                        id: "c\(index)",
                        kind: .commit(oid: "9c1de0212ab", headline: "fix: nevracet prázdný secret"),
                        actor: author,
                        at: Date(timeIntervalSince1970: 1_753_900_000)
                    )
                },
                forcePushes: [],
                events: [],
                reviews: [approval],
                comments: []
            )
        case .rewritten, .rewrittenWithFindings:
            VisitChanges(
                commits: [],
                forcePushes: [
                    TimelineEvent(
                        id: "1",
                        kind: .forcePushed(before: "4f2ac9188cd", after: "9c1de0212ab"),
                        actor: author,
                        at: Date(timeIntervalSince1970: 1_753_900_000)
                    )
                ],
                events: [],
                reviews: [approval],
                comments: []
            )
        }
    }

    private static let author = EventActor(login: "odinuv", avatarURL: nil, isBot: false)

    /// Třetí odrážka z návrhu — „vondrous **schválil** PR“.
    private static let approval = SubmittedReview(
        id: "r1",
        author: "vondrous",
        state: .approved,
        body: "",
        submittedAt: Date(timeIntervalSince1970: 1_753_950_000)
    )
}
