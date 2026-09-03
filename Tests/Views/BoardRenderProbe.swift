import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#291): vykreslí **desku** (#515) s blokem `Dění` (#443), aby se dala
/// **vidět** a položit vedle sekce 45 návrhu.
///
/// Existuje proto, že `BoardSeparatorTests` odpovídá na „kolik je čar a jsou stejně silné“
/// a `ActivityRowShapeTests` na „vejde se úzký řádek na jednu řádku a co v něm není“, kdežto
/// otázka *jak to vedle sebe vypadá* se z čísla nepozná. Od #515 je ta otázka ostřejší: vpravo
/// v hlavičce pruhu stojí **akce s počtem a kapslí klávesy**, a to je první věc, která se do
/// zúženého pruhu nevejde.
///
/// **`NSHostingView` a `cacheDisplay`, ne `ImageRenderer`**: deska je `ScrollView` a ten se
/// offscreen nerasterizuje (změřeno u #237).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda desky podle mého tahu (#515)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct BoardRenderProbe {
    /// Šířka okna z návrhu (deska má v mockupu 1134 bodů obsahu), k ní užší okno, ve kterém
    /// pravý sloupec spadne pod 456 bodů — právě tam se pozná, jestli se ořezává titulek, nebo
    /// souřadnice — a od #515 **nejužší povolené okno**: podlaha je 700 bodů (`RootView`)
    /// a rail z ní ubere 64, takže na desku zbývá kolem 636. Akce v hlavičce pruhu
    /// (`Pustit review na 6 ⌘⇧R`) je nejdelší prvek desky, takže se právě tady pozná, jestli
    /// z ní ustoupí nadpis, počet, nebo ona sama.
    private let widths: [CGFloat] = [1240, 900, 636]

    /// Prázdný blok se posuzuje taky: je to jediné místo, kde z celé sekce zbude jedna věta, a věta
    /// pod hlavičkou vypadá jinak než nakreslený seznam.
    private enum Scenario: String, CaseIterable {
        case filled = "s-radky"
        case empty = "prazdny"
    }

    @Test("Vyrendrovat desku do PNG")
    func rendersTheBoard() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in widths {
            for dark in [false, true] {
                for scenario in Scenario.allCases {
                    let store = await store(scenario)
                    let url = directory.appending(
                        path: "deska-\(Int(width))-\(dark ? "tmavy" : "svetly")-\(scenario.rawValue).png"
                    )
                    try write(store: store, width: width, dark: dark, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG.
    ///
    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(store: AppStore, width: CGFloat, dark: Bool, to url: URL) throws {
        let scene = BoardView(store: store, open: { _ in })
            .frame(width: width, height: Self.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .tint(Palette.accent)
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

    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle sebe běží víc instancí aplikace.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        defer { window.orderOut(nil) }
        // Hierarchie se doskládá až za pár koly smyčky; sonda nic netvrdí, takže stačí odmlka.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// Store s frontou a se záznamem dění, jak ho kreslí sekce 31 — pět řádků a patka `+37`.
    ///
    /// Fronta má sedm PR schválně: levý sloupec je pak vysoký jako v mockupu, takže je na obrázku
    /// vidět i to, kvůli čemu se blok stěhoval — kolik prázdna pod `Co teď` zbývalo.
    private func store(_ scenario: Scenario) async -> AppStore {
        let queue = (1...7).map { number in
            PullRequestSummary(
                id: PRIdentifier(repo: RepoID("keboola/vault")!, number: number),
                title: "chore: modernize dependencies (Symfony 8-ready)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/\(number)")!,
                updatedAt: Date(timeIntervalSince1970: Double(number) * 100),
                state: .open
            )
        }
        // **Hodiny musí jít teď**, i když jsou falešné: `Text(_:format: .relative)` se počítá proti
        // skutečnému kalendáři, kdežto `Policy.activityTime` proti `store.time.now`. S výchozím
        // rokem 1970 by ty dvě odpovědi mířily každá jinam a `včera v 7:58` by se v renderu
        // ukázalo jako `včera` — tedy zrovna to, kvůli čemu sonda vznikla.
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success(queue)),
            time: FakeTimeSource(start: Date())
        )
        await store.refresh()
        guard scenario == .filled else { return store }
        store.activityEvents = Self.events
        return store
    }

    /// Položky ze sekce 31 doslova — a pátá **ze včerejška**, protože právě na ní je vidět den
    /// u času (`včera v 7:58`). Podrobnost, sha, chip `bez banneru` i autor v nich zůstávají
    /// schválně, i když je úzký tvar nekreslí: sonda tím ukazuje, že se **vynechávají při kresbě**,
    /// ne že by v záznamu nebyly.
    private static var events: [ActivityEvent] {
        let now = Date()
        var events = [
            ActivityEvent(
                id: "staleFindings|keboola/vault#85|9c1f0ab",
                kind: .staleFindings,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-120),
                headline: "Nálezy zastaraly",
                detail: "přišly 3 commity, hlava je teď",
                head: "9c1f0ab2d4e5f60718293a4b5c6d7e8f90a1b2c3"
            ),
            ActivityEvent(
                id: "foreignActivity|keboola/app-project-restore#91|1",
                kind: .foreignActivity,
                pullRequest: PRIdentifier("keboola/app-project-restore#91")!,
                at: now.addingTimeInterval(-900),
                headline: "odinuv: opravdu to potřebuje ten mutex?",
                detail: "a 1 review od Copilota",
                wasAnnounced: true
            ),
            ActivityEvent(
                id: "findings|keboola/vault#85|2",
                kind: .findings,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-1200),
                headline: "3 nálezy · 1 blokuje",
                detail: "php-review, security-review",
                wasAnnounced: true
            ),
            ActivityEvent(
                id: "newPullRequest|keboola/vault#85|3",
                kind: .newPullRequest,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-3600),
                headline: "Nový PR k review",
                detail: "chore: modernize dependencies (Symfony 8-ready)",
                wasAnnounced: true,
                author: "odinuv"
            ),
            ActivityEvent(
                id: "clean|keboola/job-queue-api#402|4",
                kind: .clean,
                pullRequest: PRIdentifier("keboola/job-queue-api#402")!,
                at: yesterdayMorning(before: now),
                headline: "Čisté review",
                detail: "3 skilly · 1,04 $",
                wasAnnounced: false
            )
        ]
        // Zbytek záznamu, ať patka hlásí `+37` jako mockup.
        events += (0..<37).map { index in
            ActivityEvent(
                id: "reReview|keboola/connection#\(200 + index)|old",
                kind: .reReview,
                pullRequest: PRIdentifier("keboola/connection#\(200 + index)")!,
                at: now.addingTimeInterval(-2 * 86_400 - Double(index) * 60),
                headline: "Znovu k review",
                detail: "fix: rate limiting on the storage API",
                wasAnnounced: true,
                author: "odinuv"
            )
        }
        return events
    }

    /// Včera v 7:58 — ten okamžik z mockupu, ne „o den zpátky“: den se dopisuje podle kalendáře,
    /// takže odečtení 24 hodin by v době kolem půlnoci padlo na dnešek.
    private static func yesterdayMorning(before now: Date) -> Date {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return calendar.date(bySettingHour: 7, minute: 58, second: 0, of: yesterday) ?? yesterday
    }

    private static let height = 1100.0
}
