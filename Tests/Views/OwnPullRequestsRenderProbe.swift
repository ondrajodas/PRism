import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#331): vyrendruje sekci `Moje PR` **ve všech čtyřech podobách**, jaké umí.
///
/// Proč sonda a ne měření: „nevypadá prázdná sekce jako hotová práce?“ je otázka na obrázek —
/// a tři ze čtyř podob jsou prázdné stavy, které se od sebe liší jen ikonou, větou a tlačítkem.
/// Co se **dá** tvrdit číslem, je v `OwnPullRequestsTests` (pořadí důvodů) a v `AppStoreOwnershipTests`
/// (co který stav znamená ve storu).
///
/// **Ke stavu „nevím, kdo jsi“ se v aplikaci klikáním nedostaneš** (musel by spadnout `gh api user`)
/// a k „zdroj chybí“ jedině přepsáním konfigurace — tohle je jediná cesta, jak si je prohlédnout
/// vedle sebe.
///
/// `NSHostingView` a `cacheDisplay`, ne `ImageRenderer`: v sekci je `List`, jehož obsah se
/// offscreen nerasterizuje — tatáž cesta jako u tabů (#294) a `Kontrol` (#306).
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, cesta ven přes `PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda sekce Moje PR (#331)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct OwnPullRequestsRenderProbe {
    private enum Scenario: String, CaseIterable {
        /// Dashboard: pět karet a dva bloky pod sebou.
        ///
        /// **Rendruje se tady, ne screenshotem běžící aplikace**, a je to jediná cesta: dashboard je
        /// jeden `ScrollView`, takže v okně s třiceti PR ve frontě spadne blok `Moje PR` pod dolní
        /// hranu a na snímek se nedostane. Nad krátkým seznamem jsou oba bloky vedle karet vidět
        /// naráz.
        case dashboard
        /// Vlastní PR v seznamu — řádek s `Prompt →`.
        case list = "seznam"
        /// Mezi zdroji chybí `author:@me is:open`.
        case sourceMissing = "bez-zdroje"
        /// Login se nedotáhl, takže je podle autora všechno cizí.
        case unknownViewer = "bez-loginu"
        /// Zdroj i login jsou, jen nic otevřeného není.
        case empty = "prazdno"
        /// Cizí aktivita od minule (#335) — řádek s `2 nové komentáře od minule`.
        ///
        /// **Ke tomuhle stavu se v aplikaci klikáním nedostaneš**: musel by mezitím někdo napsat
        /// komentář na PR, který mám v seznamu, a značka „od minule“ musí být starší než ten
        /// komentář. Tohle je jediná cesta, jak si ho prohlédnout vedle mockupu (sekce 21).
        case activity = "cizi-aktivita"
        /// Totéž v bloku `Moje PR` na dashboardu, kde to návrh kreslí.
        case activityDashboard = "cizi-aktivita-dashboard"

        /// Kreslí se dashboard, nebo seznam? Rozhoduje o výšce i o vybrané sekci railu.
        var isDashboard: Bool { self == .dashboard || self == .activityDashboard }
    }

    @Test("Vyrendrovat sekci Moje PR ve všech stavech")
    func rendersEveryState() async throws {
        let directory = Self.outputDirectory
        for scenario in Scenario.allCases {
            let store = await prepared(scenario)
            let url = directory.appending(path: "moje-pr-\(scenario.rawValue).png")
            let height = scenario.isDashboard ? Self.dashboardHeight : Self.height
            try render(
                HStack(spacing: 0) {
                    SidebarRail(
                        section: .constant(store.railSection),
                        queueCount: store.railQueueCount,
                        mineCount: store.railMineCount,
                        draftCount: store.pullRequestsWithDraft.count
                    )
                    HomeView(store: store)
                }
                .frame(width: Self.width, height: height)
                .background(Palette.background)
                .tint(Palette.accent),
                width: Self.width,
                height: height,
                to: url
            )
            print("SONDA \(url.path) — \(scenario.rawValue), odznak \(String(describing: store.railMineCount)), "
                + "důvod \(String(describing: store.ownListEmptyReason))")
        }
    }

    private func prepared(_ scenario: Scenario) async -> AppStore {
        let list: [PullRequestSummary] = switch scenario {
        case .dashboard, .list, .activity, .activityDashboard: Self.own + [Self.theirs]
        // Bez zdroje vlastní PR nedorazí — proto v seznamu žádné nejsou. Kdyby tam byly (třeba
        // z jinak napsaného dotazu), sekce žádný prázdný stav nemá a je to tak správně.
        case .sourceMissing, .empty: [Self.theirs]
        // Login chybí, takže vlastní PR v seznamu **jsou**, jen se o nich neví, že jsou moje.
        case .unknownViewer: Self.own
        }
        let gateway = FakeGitHubGateway(always: .success(list))
        gateway.viewer = scenario == .unknownViewer ? "" : "ondrajodas"
        var configuration = Configuration.standard
        if scenario == .sourceMissing { configuration.global.sources = [.reviewRequested] }
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()
        store.railSection = scenario.isDashboard ? .overview : .mine
        // Nálezy na prvním vlastním PR, ať je v řádku vidět odznak i odznak na railu.
        store.reviewRecords[Self.own[0].id] = makeRecord(
            runs: [makeStoredRun(findings: [makeReported(), makeReported(category: "style")])]
        )
        if scenario == .activity || scenario == .activityDashboard { seedActivity(in: store) }
        return store
    }

    /// Cizí komentáře na **druhém** vlastním PR a značka „od minule“ před nimi (#335).
    ///
    /// Píše se to do storu **až po tiku**: rozhlídka po cizí aktivitě si o konverzaci řekne sama,
    /// jenže fake gateway ji nezná, takže by zbyl stav `failed`. Značka se nastavuje ručně ze
    /// stejného důvodu, z jakého se k tomuhle stavu nedá dojít klikáním — musí být **starší** než
    /// komentáře, jinak z definice nic nového není.
    private func seedActivity(in store: AppStore) {
        let pullRequest = Self.own[1]
        let mine = pullRequest.id
        store.visitSnapshots[mine] = Date(timeIntervalSinceNow: -86_400)
        store.conversationStates[mine] = .loaded(
            Conversation(
                viewer: "ondrajodas",
                reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
                threads: ConversationPage(items: [], total: 0, hasNextPage: false),
                comments: ConversationPage(
                    items: (1...2).map { index in
                        ThreadComment(
                            id: "c\(index)",
                            author: "odinuv",
                            body: "opravdu to potřebuje ten mutex?",
                            createdAt: Date(timeIntervalSinceNow: -1_800),
                            url: URL(string: "https://github.com/\(mine.repo)/pull/\(mine.number)#c\(index)")!
                        )
                    },
                    total: 2,
                    hasNextPage: false
                )
            ),
            updatedAt: pullRequest.updatedAt
        )
    }

    private func render(_ scene: some View, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe
        // víc instancí a cizí okno je poslední, co má sonda rušit.
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

    private static let width: CGFloat = 900
    private static let height: CGFloat = 520
    /// Dashboard je vyšší: pod pěti kartami stojí dva bloky pod sebou a smysl snímku je vidět je
    /// oba, ne jeden a půl.
    private static let dashboardHeight: CGFloat = 760

    private static let own = [
        summary(
            "ondrajodas/PRism#324",
            title: "feat: put the reviewer run timeout into settings",
            author: "ondrajodas",
            ago: 720
        ),
        summary(
            "keboola/app-project-restore#91",
            title: "[AJDA-1215] Update specific tables/configurations",
            author: "ondrajodas",
            ago: 8_400
        ),
    ]

    private static let theirs = summary(
        "keboola/vault#85",
        title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
        author: "odinuv",
        ago: 3_600
    )

    private static func summary(
        _ identifier: String,
        title: String,
        author: String,
        ago: TimeInterval
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: title,
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSinceNow: -ago),
            state: .open
        )
    }
}
