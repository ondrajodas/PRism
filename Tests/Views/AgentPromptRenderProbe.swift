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
        //
        // Šířka se dosazuje do **vlastní domény** nasazené na to, co se rendruje (#411). Do #411
        // se psala do `UserDefaults.standard`, a to byla doména hlavní instance: sonda tím
        // přepisovala šířku panelu, kterou si nastavil člověk — a `removeObject` po ní ji smazal
        // úplně, takže po jednom ručním spuštění sondy byl panel v aplikaci zpátky na výchozí.
        let scratch = try ScratchDefaults("agentPromptPanelWidth")
        for panelWidth in [300.0, 240.0, 520.0] {
            scratch.store.set(panelWidth, forKey: "findingsPanelWidth")
            let url = directory.appending(path: "zadani-panel-sirka-\(Int(panelWidth)).png")
            let scene = PullRequestDetailView(
                store: store,
                pullRequest: Self.summary,
                submission: .constant(nil)
            )
            .frame(width: 1400, height: Self.height)
            .background(Palette.background)
            .defaultAppStorage(scratch.store)
            try render(scene, width: 1400, height: Self.height, to: url)
            print("SONDA \(url.path) — panel \(Int(panelWidth)) b")
        }

        // Tady už panel nemá mít vynucenou šířku — kreslí se ve **výchozí**. Proto se klíč odebere
        // a doména se nasazuje dál: bez ní by se vzala hodnota z domény hostitele, kterou v souběžném
        // běhu tří slotů může mít napsanou kdokoli.
        scratch.store.removeObject(forKey: "findingsPanelWidth")
        for width in [1400.0, 900.0] as [CGFloat] {
            let url = directory.appending(path: "zadani-panel-\(Int(width)).png")
            let scene = PullRequestDetailView(
                store: store,
                pullRequest: Self.summary,
                submission: .constant(nil)
            )
            .frame(width: width, height: Self.height)
            .background(Palette.background)
            .defaultAppStorage(scratch.store)
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
        let selection = store.agentPromptSelection(for: pr)
        for width in [1080.0, 840.0] as [CGFloat] {
            let sheet = directory.appending(path: "zadani-sheet-\(Int(width)).png")
            // Pozadí i režim se sondě musí nasadit: sheet si plochu nemaluje (v aplikaci ji dává okno
            // sheetu), takže by v borderless okně vyšel titulek světle na světlém.
            try render(
                AgentPromptSheet(selection: selection, rebuild: { store.agentPromptSelection(for: pr, toggled: $0) })
                    .frame(width: width, height: 1100)
                    .background(Palette.surface),
                width: width,
                height: 1100,
                to: sheet
            )
            print("SONDA \(sheet.path) — sheet \(Int(width)) b, vybráno \(selection.selected) "
                + "z \(selection.available), \(selection.prompt.sizeText)")
        }
        print("SONDA text:\n\(selection.prompt.text)")
    }

    /// Seznam položek (#377) — **v obou mezích šířky a s rozbalenou položkou**.
    ///
    /// Proč zvlášť a ne přes sheet: co je rozbalené, drží `@State` sheetu, takže offscreen se
    /// v něm rozbalit nedá. A rozbalený řádek je zrovna to, co je potřeba vidět — hlavička
    /// `druh · autor · čas · velikost` a **dlouhý text, který se roluje** (strop 168 bodů z návrhu,
    /// sekce 23). Rozbalí se nejdelší položka, tedy ta, u které se strop pozná.
    ///
    /// Šířka je vnitřek sheetu (840 a 1080 minus `padding(16)` po obou stranách), protože seznam
    /// tam doopravdy leží — jiná šířka je jiný design.
    @Test("Vyrendrovat seznam položek s rozbalenou položkou")
    func rendersThePickListWithAnExpandedItem() async throws {
        let directory = Self.outputDirectory
        let (store, cache) = try await prepared()
        defer { _ = cache }

        let selection = store.agentPromptSelection(for: pr)
        let picks = selection.groups.flatMap(\.picks)
        let longest = try #require(picks.max { $0.text.utf8.count < $1.text.utf8.count })

        for width in [1080.0, 840.0] as [CGFloat] {
            let url = directory.appending(path: "zadani-seznam-\(Int(width)).png")
            try render(
                AgentPromptPickList(groups: selection.groups, expanded: [longest.id])
                    .padding(16)
                    .frame(width: width, alignment: .topLeading)
                    .background(Palette.surface),
                width: width,
                height: 720,
                to: url
            )
            print("SONDA \(url.path) — seznam \(Int(width)) b, \(picks.count) položek, "
                + "rozbalená \(longest.id) (\(longest.text.utf8.count) B)")
        }
        for group in selection.groups {
            print("SONDA grupa \(group.kind.title): \(group.countLabel)")
        }
        for pick in picks where !pick.isIncluded {
            print("SONDA vypnuto \(pick.id): \(pick.exclusion?.label ?? "rukou") — \(pick.title)")
        }
    }

    /// Panel ve **všech třech stavech předání** (#334): nepředáno, předáno, po pushi.
    ///
    /// Proč sonda: ke stavu „zadání zastaralo po pushi“ se v aplikaci klikáním nedostaneš —
    /// musel by mezitím někdo pushnout do PR, který mám na obrazovce. A „předáno“ vypadá jinak než
    /// „předáno, ale něco zbývá“ jedinou větou, takže je to otázka na obrázek. Co se **dá** tvrdit
    /// číslem, je v `HandoffTests` (co je nové) a v `HandoffTextTests` (věty a skloňování).
    @Test("Vyrendrovat panel v každém stavu předání")
    func rendersEveryHandoffStage() async throws {
        let directory = Self.outputDirectory
        let (store, cache) = try await prepared()
        defer { _ = cache }
        // Šířku panelu drží `@AppStorage`, takže i tady se rendruje do **vlastní domény** — viz
        // `rendersThePanelAndTheSheet` a #411. Bez ní by se kreslila šířka, kterou má nastavený
        // člověk u stroje, a poslední snímek by ji přepsal.
        let scratch = try ScratchDefaults("agentPromptPanelWidth")

        try renderPanel(store: store, named: "nepredano", in: directory, storage: scratch.store)

        // Předáno celé: razítko a věta, že se nové věci objeví tady.
        store.noteHandoff(of: store.agentPrompt(for: pr))
        try renderPanel(store: store, named: "predano", in: directory, storage: scratch.store)

        // Předáno a **pak přišlo nové vlákno** — stav, ve kterém razítko zůstává a volby se kreslí.
        // Vlákno se dosazuje do stavu store, protože fake gateway drží konverzaci na `updatedAt`
        // shrnutí a sonda pracuje s jedním PR; jinak by se muselo předstírat druhé tiknutí.
        store.conversationStates[pr] = .loaded(try Self.conversationWithNewThread(), updatedAt: Self.summary.updatedAt)
        try renderPanel(store: store, named: "predano-zbyva", in: directory, storage: scratch.store)
        store.conversationStates[pr] = .loaded(try Self.conversation(), updatedAt: Self.summary.updatedAt)

        // Po pushi: agent opravil a poslal dva commity, takže zadání zastaralo.
        store.noteHandoff(of: store.agentPrompt(for: pr))
        store.commits[pr] = Self.commits
        store.detailStates[pr] = .loaded(Self.pushedDetail, updatedAt: Self.summary.updatedAt)
        try renderPanel(store: store, named: "po-pushi", in: directory, storage: scratch.store)
        print("SONDA report po pushi: \(store.handoffReport(for: pr))")

        // Tentýž stav, ale s **nepředaným vláknem** — přesně to, co kreslí návrh (sekce 22.2):
        // pod hlavním tlačítkem druhá cesta, která předá jen novou diskuzi. Razítko musí vzniknout
        // **před** pushem, jinak by nesl novou hlavu a zadání by nezastaralo.
        store.detailStates[pr] = .loaded(Self.detail, updatedAt: Self.summary.updatedAt)
        store.toggleAgentPromptOption(.unresolvedThreads)
        store.noteHandoff(of: store.agentPrompt(for: pr))
        store.toggleAgentPromptOption(.unresolvedThreads)
        store.detailStates[pr] = .loaded(Self.pushedDetail, updatedAt: Self.summary.updatedAt)
        try renderPanel(store: store, named: "po-pushi-nove-vlakno", in: directory, storage: scratch.store)

        // **A ještě v užší mezi panelu** (240 b, viz `ReviewPanel`): jiná šířka je jiný design —
        // varování, razítko i dva řádky s počty se do ní musí vejít, jinak `lineLimit(1)` schová
        // zrovna to, kvůli čemu tam jsou.
        scratch.store.set(240.0, forKey: "findingsPanelWidth")
        try renderPanel(store: store, named: "po-pushi-uzky", in: directory, storage: scratch.store)
    }

    private func renderPanel(
        store: AppStore,
        named name: String,
        in directory: URL,
        storage: UserDefaults
    ) throws {
        let url = directory.appending(path: "zadani-\(name).png")
        let scene = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil)
        )
        .frame(width: 1400, height: Self.height)
        .background(Palette.background)
        .defaultAppStorage(storage)
        try render(scene, width: 1400, height: Self.height, to: url)
        print("SONDA \(url.path) — \(name), stav \(store.handoffReport(for: pr).stage), "
            + "zbývá \(store.handoffReport(for: pr).pending)")
    }

    // MARK: - Scéna

    /// Vlastní PR s nálezy i konverzací a s panelem přepnutým na zadání.
    private func prepared() async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        var configuration = Configuration.standard
        configuration.global.ownLogins = ["ondrajodas"]
        // Hodiny **za** daty konverzace (#334): razítko předání se porovnává s časy komentářů,
        // takže výchozí rok 1970 by z každého vlákna udělal „přišlo po předání“ a stav `předáno`
        // by na obrázku nikdy nevyšel. Je to vlastnost fixture, ne logiky — v aplikaci jsou
        // komentáře starší než předání.
        let clock = FakeTimeSource(start: Date(timeIntervalSince1970: 1_754_100_000))
        let store = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([Self.summary]),
                detail: .success(Self.detail),
                diffs: [.success(Self.diffText)],
                conversations: [.success(try Self.conversation())]
            ),
            configuration: configuration,
            time: clock,
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(findings: Self.findings),
            reviews: ReviewStore(layout: CacheLayout(root: directory.url), time: clock),
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

    /// Tatáž konverzace a v ní **jedno nové vlákno od kolegy** — z toho se kreslí stav „předáno,
    /// ale něco zbývá“.
    private static func conversationWithNewThread() throws -> Conversation {
        let base = try conversation()
        return Conversation(
            viewer: base.viewer,
            reviews: base.reviews,
            threads: ConversationPage(
                items: base.threads.items + [
                    ReviewThread(
                        id: "t9",
                        path: "App/Config/ReviewTimeout.swift",
                        line: 12,
                        originalLine: 12,
                        side: .right,
                        isResolved: false,
                        isOutdated: false,
                        comments: ConversationPage(
                            items: [
                                ThreadComment(
                                    id: "t9c1",
                                    author: "odinuv",
                                    body: "Ta horní mez by chtěla test na hodnotu mimo rozsah.",
                                    createdAt: Date(timeIntervalSince1970: 1_754_200_000),
                                    url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#discussion_r9")!
                                ),
                            ],
                            total: 1,
                            hasNextPage: false
                        )
                    ),
                ],
                total: base.threads.total + 1,
                hasNextPage: false
            ),
            comments: base.comments
        )
    }

    /// Tentýž PR po pushi — hlava se posunula o dva commity.
    private static let pushedDetail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "ff11223cccc",
        baseSha: "bbbb2222",
        headRef: "issue-320-timeout",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: detail.body
    )

    /// Commity od nejstaršího, jak je vydává gateway — předaná hlava je uprostřed, takže se počet
    /// pushnutých dá spočítat.
    private static let commits: [PullRequestCommit] = [
        "aaa0001", "9c1de02aaaa", "dddd0003", "ff11223cccc",
    ].map {
        PullRequestCommit(
            sha: $0,
            message: "chore: \($0)",
            authorName: "Ondra Jodas",
            authorLogin: "ondrajodas",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_754_000_000),
            isMerge: false
        )
    }

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

    /// Konverzace pro sondu — a od #377 v ní **každý důvod předvybrání**, který se dá nakreslit:
    /// souhrn, který shrnuje diff, souhrn bez obsahu, vlastní komentář a vyřešené vlákno.
    ///
    /// Souhrn od Copilota je **skutečný výstup** (`gh/review-copilot-overview.md`, review na
    /// `ondrajodas/PRism#378`), takže na obrázku je vidět i to, jak se sází text s `CRLF`. Vlastní
    /// komentář je z téhož důvodu popis skutečného PR (`gh/pr-body-linear.md`) — je to nejdelší
    /// položka, tedy zrovna ta, u které se pozná strop rolování v rozkliku.
    private static func conversation() throws -> Conversation {
        Conversation(
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
                SubmittedReview(
                    id: "r2",
                    author: "copilot-pull-request-reviewer[bot]",
                    state: .commented,
                    body: try Fixture.text("gh/review-copilot-overview.md"),
                    submittedAt: Date(timeIntervalSince1970: 1_753_010_000)
                ),
                SubmittedReview(
                    id: "r3",
                    author: "coderabbitai[bot]",
                    state: .commented,
                    body: "## Review\n\n### Walkthrough\n",
                    submittedAt: Date(timeIntervalSince1970: 1_753_020_000)
                ),
            ],
            total: 3,
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
                ThreadComment(
                    id: "c2",
                    author: "ondrajodas",
                    body: try Fixture.text("gh/pr-body-linear.md"),
                    createdAt: Date(timeIntervalSince1970: 1_753_500_000),
                    url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#issuecomment-2")!
                ),
            ],
            total: 2,
            hasNextPage: false
        )
        )
    }

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
