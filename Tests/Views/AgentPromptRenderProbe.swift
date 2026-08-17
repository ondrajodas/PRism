import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#333): vyrendruje **panel se zadáním pro agenta a sheet s promptem**.
///
/// Proč sonda: „vejdou se popisky sedmi voleb do 300 bodů“ a „nesplývá náhled s ovládáním“ jsou
/// otázky na obrázek, ne na číslo. Co se **dá** tvrdit číslem, je v `AgentPromptTests` (text
/// a rozdělení po souborech) a v `ReviewPanelTabsTests` (které segmenty se kreslí).
///
/// Rendruje se **v obou mezních šířkách panelu** (240 a 520 bodů, viz `ReviewPanel`), protože jiná
/// šířka je jiný design — plné popisky a počty se do užší obvykle nevejdou.
///
/// `NSHostingView`, ne `ImageRenderer`: obsah `ScrollView`u se offscreen nerasterizuje, a panel je
/// celý ve `ScrollView`u. Tatáž cesta jako u ostatních sond, viz `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`
/// — `xcodebuild` posílá do testovacího procesu jen proměnné s tou předponou a **bez ní se sonda
/// tiše přeskočí** (vypadá to jako zelený běh, ve kterém nic nevzniklo).
@MainActor
@Suite(
    "Sonda zadání pro agenta (#333)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AgentPromptRenderProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 324)

    @Test("Vyrendrovat panel se zadáním a sheet s promptem")
    func rendersThePanelAndTheSheet() async throws {
        let directory = Self.outputDirectory
        let (store, cache) = try await prepared()
        defer { _ = cache }

        // Šířku panelu si drží uživatel (`@AppStorage`), takže se rendruje i **v obou mezích**:
        // sedm popisků s počty se do 240 bodů vejít musí, jinak se `lineLimit(1)` postará o to,
        // že se rozdíl mezi „Vyřešená vlákna“ a „Odmítnuté nálezy“ pozná až po rozšíření panelu.
        for panelWidth in [300.0, 240.0, 520.0] {
            UserDefaults.standard.set(panelWidth, forKey: "findingsPanelWidth")
            let url = directory.appending(path: "zadani-panel-sirka-\(Int(panelWidth)).png")
            let scene = PullRequestDetailView(
                store: store,
                pullRequest: Self.summary,
                submission: .constant(nil)
            )
            .frame(width: 1400, height: Self.height)
            .background(Palette.background)
            try render(scene, width: 1400, height: Self.height, to: url)
            print("SONDA \(url.path) — panel \(Int(panelWidth)) b")
        }
        UserDefaults.standard.removeObject(forKey: "findingsPanelWidth")

        for width in [1400.0, 900.0] as [CGFloat] {
            let url = directory.appending(path: "zadani-panel-\(Int(width)).png")
            let scene = PullRequestDetailView(
                store: store,
                pullRequest: Self.summary,
                submission: .constant(nil)
            )
            .frame(width: width, height: Self.height)
            .background(Palette.background)
            try render(scene, width: width, height: Self.height, to: url)
            print("SONDA \(url.path) — panel, \(Int(width)) b, tab \(store.reviewPanelTab)")
        }

        // Sheet zvlášť, ne přes `.sheet`: offscreen se modální okno nevykreslí, takže se rendruje
        // to, co je v něm — tedy tentýž `View`, jaký uvidí člověk.
        //
        // **V obou mezích šířky**, ne v jedné: sheet se otevře na `idealWidth` (1080 b), ale dá se
        // stáhnout na `minWidth` (840 b) — a odznaky „co je v textu“ i zalomení markdownu jsou na
        // šířce závislé, takže jedno číslo by o druhém stavu netvrdilo nic. Rozsah se posunul u #333
        // po proklikání (720 → 1080), protože na 720 zalamoval skoro každý řádek fenced diffu.
        let prompt = store.agentPrompt(for: pr)
        for width in [1080.0, 840.0] as [CGFloat] {
            let sheet = directory.appending(path: "zadani-sheet-\(Int(width)).png")
            // Pozadí i režim se sondě musí nasadit: sheet si plochu nemaluje (v aplikaci ji dává okno
            // sheetu), takže by v borderless okně vyšel titulek světle na světlém.
            try render(
                AgentPromptSheet(prompt: prompt)
                    .frame(width: width, height: 620)
                    .background(Palette.surface),
                width: width,
                height: 620,
                to: sheet
            )
            print("SONDA \(sheet.path) — sheet \(Int(width)) b, \(prompt.included.total) položek, \(prompt.sizeText)")
        }
        print("SONDA text:\n\(prompt.text)")
    }

    // MARK: - Scéna

    /// Vlastní PR s nálezy i konverzací a s panelem přepnutým na zadání.
    private func prepared() async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        let store = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([Self.summary]),
                detail: .success(Self.detail),
                diffs: [.success(Self.diffText)],
                conversations: [.success(Self.conversation)]
            ),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: Self.findings),
            reviews: ReviewStore(layout: CacheLayout(root: directory.url), time: FakeTimeSource()),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        await store.loadConversation(for: Self.summary)
        store.openTab(pr)
        store.setDetailTab(.filesChanged, for: pr)
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
        store.revealAgentPrompt(in: pr)
        return (store, directory)
    }

    private func render(_ scene: some View, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        // Tmavý režim, ve kterém aplikace běží — jinak systémové barvy (titulek sheetu, popisky
        // tlačítek) vyjdou pro světlé pozadí a proti tmavé ploše z palety nebudou vidět.
        hosting.appearance = NSAppearance(named: .darkAqua)
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
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    private static let height: CGFloat = 820

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 324),
        title: "feat: put the reviewer run timeout into settings",
        author: "ondrajodas",
        url: URL(string: "https://github.com/ondrajodas/PRism/pull/324")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "9c1de02aaaa",
        baseSha: "bbbb2222",
        headRef: "issue-320-timeout",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "## Popis\n\nTimeout revieweera se bere z nastavení."
    )

    private static let findings: [ReportedFinding] = [
        ReportedFinding(
            file: "App/Config/Configuration.swift",
            line: 41,
            category: "correctness",
            verdict: .confirmed,
            shortSummary: nil,
            summary: "Sražení do mezí se děje při čtení, takže z „napsal jsem 120“ zbyde „vždycky tam bylo 60“.",
            failureScenario: "Uživatel napíše 120, v poli uvidí 60 a nepozná, že se hodnota srazila."
        ),
        ReportedFinding(
            file: "App/Config/ReviewTimeout.swift",
            line: 12,
            category: "robustness",
            verdict: .plausible,
            shortSummary: nil,
            summary: "Horní mez 240 minut znamená, že jeden zaseknutý běh drží slot čtyři hodiny.",
            failureScenario: nil
        ),
    ]

    private static let conversation = Conversation(
        viewer: "ondrajodas",
        reviews: ConversationPage(
            items: [
                SubmittedReview(
                    id: "r1",
                    author: "odinuv",
                    state: .changesRequested,
                    body: "Celkově dobrý, ale než to mergneme: ta mez by měla být pojmenovaná na jednom místě, ne dvakrát.",
                    submittedAt: Date(timeIntervalSince1970: 1_753_000_000)
                ),
            ],
            total: 1,
            hasNextPage: false
        ),
        threads: ConversationPage(
            items: [
                ReviewThread(
                    id: "t1",
                    path: "App/Review/ClaudeReviewRunner.swift",
                    line: 88,
                    originalLine: 88,
                    side: .right,
                    isResolved: false,
                    isOutdated: false,
                    diffHunk: "@@ -85,3 +85,4 @@\n     let timeout = configuration.reviewTimeout",
                    comments: ConversationPage(
                        items: [
                            ThreadComment(
                                id: "t1c1",
                                author: "Copilot",
                                body: "The timeout is read from config on every run — consider caching it.",
                                createdAt: Date(timeIntervalSince1970: 1_753_100_000),
                                url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#discussion_r1")!
                            ),
                            ThreadComment(
                                id: "t1c2",
                                author: "ondrajodas",
                                body: "Změřím to, než to přepíšu.",
                                createdAt: Date(timeIntervalSince1970: 1_753_200_000),
                                url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#discussion_r2")!,
                                replyToID: "t1c1"
                            ),
                        ],
                        total: 2,
                        hasNextPage: false
                    )
                ),
                ReviewThread(
                    id: "t2",
                    path: "README.md",
                    line: 140,
                    originalLine: 140,
                    side: .right,
                    isResolved: true,
                    isOutdated: false,
                    comments: ConversationPage(
                        items: [
                            ThreadComment(
                                id: "t2c1",
                                author: "Copilot",
                                body: "Typo in the settings table header.",
                                createdAt: Date(timeIntervalSince1970: 1_753_300_000),
                                url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#discussion_r3")!
                            ),
                        ],
                        total: 1,
                        hasNextPage: false
                    )
                ),
            ],
            total: 2,
            hasNextPage: false
        ),
        comments: ConversationPage(
            items: [
                ThreadComment(
                    id: "c1",
                    author: "ErikZigo",
                    body: "Pozor, tohle se potká s #318 — tam se stejná hodnota čte při startu.",
                    createdAt: Date(timeIntervalSince1970: 1_753_400_000),
                    url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#issuecomment-1")!
                ),
            ],
            total: 1,
            hasNextPage: false
        )
    )

    private static let diffText = """
        diff --git a/App/Config/Configuration.swift b/App/Config/Configuration.swift
        --- a/App/Config/Configuration.swift
        +++ b/App/Config/Configuration.swift
        @@ -38,7 +38,7 @@ struct GlobalConfig: Codable {
             var pollIntervalSeconds: Int
             var skills: [String]
        -    var reviewTimeoutMinutes = 25
        +    var reviewTimeoutMinutes = Policy.reviewTimeout(minutes: 25)
             var blockingCategories: [String]
        """
}
