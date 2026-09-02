import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#336): vyrendruje paletu ⌘K se **dvěma** skupinami pull requestů.
///
/// Proč sonda a ne měření: „vejdou se dvě skupiny s nadpisy do karty?“ je otázka na obrázek.
/// Co se **dá** tvrdit číslem, je v `CommandPaletteTests` (pořadí skupin, strop na skupinu, prázdná
/// skupina vypadne) a v `AppStorePaletteTests` (co kam katalog zařadí).
///
/// **Ke stavu se v aplikaci nedostaneš bez klávesnice** — paletu otevírá ⌘K a v paralelním běhu se
/// klikat ani psát do cizí instance nemá; tohle je cesta, jak si kartu prohlédnout vedle sekce 09
/// mockupu.
///
/// **Dotaz se do renderu dosadit nedá** a je to schválně: `query` je `@State` uvnitř
/// `CommandPaletteView`, protože má zaniknout se zavřením palety (#184). Sonda proto kreslí stav
/// **prázdného dotazu** — tedy zrovna ten, o kterém návrh tvrdí, že v něm je vidět začátek obou
/// skupin — a scénář `navrh` k tomu katalog zúží na tolik řádků, kolik jich má mockup. Zvýraznění
/// shody v renderu tedy není; na to je `CommandPaletteRowView` a sada nad `Hit`.
///
/// `NSHostingView` a `cacheDisplay`, ne `ImageRenderer`: v kartě je `ScrollView`, jehož obsah se
/// offscreen nerasterizuje — tatáž cesta jako u sekce `Moje PR` (#331).
///
/// **Pouští se ručně**, a proměnné se předávají **s prefixem `TEST_RUNNER_`** — jen ty `xcodebuild`
/// do testovacího procesu pustí; bez něj se suita **tiše přeskočí** a nevyrenderuje se nic:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     -only-testing:PRismTests/CommandPaletteRenderProbe
/// ```
@MainActor
@Suite(
    "Sonda palety ⌘K se dvěma skupinami PR (#336)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CommandPaletteRenderProbe {
    private enum Scenario: String, CaseIterable {
        /// Tolik řádků, kolik jich má sekce 09 návrhu — na srovnání vedle sebe.
        case design = "navrh"
        /// Celý katalog: pět skupin po stropu, takže se karta scrolluje a je vidět, čím začíná.
        case full = "plno"
        /// Jen skupina `Akce` (#441): v plném katalogu je až za nálezy, soubory a dvěma skupinami
        /// PR, tedy pod hranou karty — a přitom je to jediná skupina, ve které se **kreslí
        /// zkratky**. Bez tohohle scénáře se na ně nedá podívat jinak než na klávesnici.
        case actions = "akce"
        /// Vložený odkaz (#531): skupina `Odkaz` nad zúženým katalogem. Dotaz se do renderu
        /// dosadit nedá (je to `@State` uvnitř karty), ale **řádek odkazu se předává uzávěrem**,
        /// takže se na něj podívat jde — a to je jediná cesta, jak ho vidět bez klávesnice.
        case link = "odkaz"
        /// Skupina `Repozitáře` v první úrovni (#533) — nadpis s organizacemi, počty otevřených
        /// PR a stáří posledního pushe. Katalog se do sondy dosazuje **napřímo z `Policy`**, ne
        /// přes `RepositoryCatalog`: ten by chtěl snímky na disku, a sonda kreslí kartu.
        case repositories = "repa"
        /// Druhá úroveň (#533) — chip v poli, odznaky `ve frontě` a `moje`, patka s `esc
        /// o úroveň zpět`. Jediná cesta, jak se na to podívat bez klávesnice.
        case repository = "repo-pr"
        /// Druhá úroveň, dokud odpověď nedorazila (#533): puntík načítání místo řádků.
        case repositoryLoading = "repo-tahani"
    }

    @Test("Vyrendrovat paletu se skupinami Pull requesty k review a Moje PR")
    func rendersBothPullRequestGroups() async throws {
        let directory = Self.outputDirectory
        for scenario in Scenario.allCases {
            let store = try await prepared()
            let items = Self.items(for: scenario, from: store.paletteItems)
            let url = directory.appending(path: "paleta-\(scenario.rawValue).png")
            let sections = Self.sections(for: scenario, items: items)
            try render(
                CommandPaletteView(
                    sections: sections,
                    stage: Self.stage(for: scenario),
                    run: { _ in },
                    close: {}
                )
                .frame(width: Self.width, height: Self.height)
                .background(Palette.background)
                .tint(Palette.accent),
                to: url
            )
            let groups = sections("").map { "\($0.group.title) \($0.hits.count)" }
            print("SONDA \(url.path) — \(scenario.rawValue), skupiny: \(groups.joined(separator: " | "))")
        }
    }

    /// Výsledky, jak by je složil store — ve scénáři druhé úrovně tou druhou cestou.
    private static func sections(
        for scenario: Scenario,
        items: [CommandPalette.Item]
    ) -> (String) -> [CommandPalette.Section] {
        switch scenario {
        case .repository:
            let rows = Policy.paletteRepositoryPullRequests(
                repositoryPullRequests,
                mine: ["ondrajodas"],
                sources: [theirs[0].id],
                now: now
            )
            return { query in
                Policy.paletteRepositoryResults(
                    of: rows,
                    query: query,
                    total: repositoryPullRequests.count
                )
            }
        // Dokud se tahá, nejsou řádky žádné — kartu vyplní věta ze `Stage`.
        case .repositoryLoading:
            return { _ in [] }
        default:
            let catalog = scenario == .repositories
                ? Policy.paletteRepositories(repositoryCatalog, query: "", now: now)
                : []
            return { query in
                Policy.paletteResults(
                    of: items + catalog,
                    query: query,
                    link: link(for: scenario)(query),
                    organizations: scenario == .repositories ? ["keboola", "ondrajodas"] : []
                )
            }
        }
    }

    private static func stage(for scenario: Scenario) -> CommandPalette.Stage {
        switch scenario {
        case .repository:
            Policy.paletteStage(
                level: .repository(vault),
                repository: .loaded(repositoryPullRequests)
            )
        case .repositoryLoading:
            Policy.paletteStage(level: .repository(vault), repository: .loading)
        default:
            Policy.paletteStage(level: .top)
        }
    }

    /// Store s cizími i vlastními PR, načteným diffem otevřeného PR a nálezy na něm.
    ///
    /// Diff je **skutečný výstup `gh`** (fixture), takže řádky souborů v paletě mají tvar, jaký
    /// mají v okně — vymyšlené cesty by v kartě zabraly jinak.
    private func prepared() async throws -> AppStore {
        let gateway = FakeGitHubGateway(
            always: .success(Self.theirs + Self.own),
            diffs: [.success(try Fixture.text("gh/pr-diff-ordinary.diff"))]
        )
        gateway.viewer = "ondrajodas"
        let store = AppStore(
            gateway: gateway,
            configuration: Configuration.standard,
            time: FakeTimeSource(stopAfter: 1)
        )
        await store.keepFresh()
        let open = Self.theirs[0]
        await store.loadDiff(for: open)
        store.openTab(open.id)
        store.reviewRecords[open.id] = makeRecord(
            runs: [
                makeStoredRun(findings: [
                    makeReported(
                        file: "src/Vault/SecretClient.php",
                        line: 81,
                        summary: "`?? ''` schová chybějící secret"
                    ),
                    makeReported(
                        file: "src/Vault/Encryptor.php",
                        line: 41,
                        category: "style",
                        summary: "Šifrovací klíč se vypíše do logu"
                    ),
                ]),
            ]
        )
        return store
    }

    /// Katalog zúžený na počty řádků ze sekce 09 návrhu. Strop `Policy.paletteResults` zůstává
    /// nedotčený — zužuje se **vstup**, ne rozhodování.
    ///
    /// Skupina, která ve výčtu není, se **nechá celá**, ne zahodí: nová skupina má být na snímku
    /// vidět, ne tiše chybět — a přebývající řádky se poznají, kdežto chybějící ne.
    private static func items(
        for scenario: Scenario,
        from items: [CommandPalette.Item]
    ) -> [CommandPalette.Item] {
        switch scenario {
        case .design, .link, .repositories: trimmed(items)
        case .full: items
        case .actions: items.filter { $0.group == .actions }
        // Druhá úroveň katalog z první vůbec nevidí — skládá si vlastní seznam.
        case .repository, .repositoryLoading: []
        }
    }

    /// Řádek skupiny `Odkaz` (#531) — jen ve scénáři, který o něj stojí.
    ///
    /// **Uzávěr ignoruje dotaz schválně**: `query` je `@State` uvnitř karty a dosadit se nedá,
    /// takže by se řádek nad prázdným dotazem nikdy neobjevil. Skládá ho `Policy` z identifikátoru
    /// PR, který **ve zdrojích není** — tedy s podtitulkem `není ve zdrojích`, jak ho má sekce 09.
    private static func link(for scenario: Scenario) -> (String) -> CommandPalette.Item? {
        guard scenario == .link else { return { _ in nil } }
        let outside = PRIdentifier("keboola/vault#85")!
        return { _ in Policy.paletteLink(to: outside, origin: .outsideSources) }
    }

    private static func trimmed(_ items: [CommandPalette.Item]) -> [CommandPalette.Item] {
        let limits: [CommandPalette.Group: Int] = [
            .findings: 2, .files: 2, .pullRequests: 1, .myPullRequests: 1, .actions: 2,
        ]
        var used: [CommandPalette.Group: Int] = [:]
        return items.filter { item in
            guard let limit = limits[item.group] else { return true }
            let count = used[item.group, default: 0]
            guard count < limit else { return false }
            used[item.group] = count + 1
            return true
        }
    }

    private func render(_ scene: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
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

    /// Karta má 560 bodů, kolem ní zbývá kus plochy okna — jako `.pal-stage` v návrhu.
    private static let width: CGFloat = 700
    /// Vyšší než strop seznamu (400) plus pole a pruh s klávesami, ať je vidět, kde karta končí.
    private static let height: CGFloat = 560

    private static let theirs = [
        summary(
            "keboola/vault#85",
            title: "chore: modernize dependencies (Symfony 8-ready)",
            author: "odinuv",
            ago: 3_600
        ),
        summary(
            "keboola/connection#21663",
            title: "fix: nezahazovat token při souběžném refreshi",
            author: "mzdrahal",
            ago: 7_200
        ),
    ]

    private static let own = [
        summary(
            "ondrajodas/PRism#324",
            title: "feat: put the reviewer run timeout into secrets store",
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

    // MARK: - Druhá úroveň (#533)

    private static let vault = RepoID("keboola/vault")!

    /// Okamžik, proti kterému se počítá `naposledy před hodinou` a `před 2 hodinami`. Pevný, aby
    /// se dva snímky z jednoho běhu nelišily o sekundy.
    private static let now = Date()

    /// Katalog rep, jak ho má zákres: `vault` se sedmi PR, `vault-cli` se dvěma a klient bez PR.
    private static let repositoryCatalog = [
        OrganizationRepository(
            repo: vault,
            openPullRequests: 7,
            lastPushedAt: now.addingTimeInterval(-3_600)
        ),
        OrganizationRepository(
            repo: RepoID("keboola/vault-cli")!,
            openPullRequests: 2,
            lastPushedAt: now.addingTimeInterval(-86_400 * 3)
        ),
        OrganizationRepository(
            repo: RepoID("keboola/php-vault-client")!,
            openPullRequests: 0,
            lastPushedAt: now.addingTimeInterval(-86_400 * 40)
        ),
    ]

    /// Otevřené PR `keboola/vault` ze zákresu — jeden je ve frontě (`theirs[0]`), jeden můj,
    /// jeden draft. Pořadí je schválně **jiné než podle razítka**, aby bylo na snímku vidět, že
    /// se řadí v `Policy`.
    private static let repositoryPullRequests = [
        pullRequest(91, "feat: configurable secret TTL with tenant ceiling", "odinuv", 7_200),
        pullRequest(85, "chore: modernize dependencies (Symfony 8-ready)", "odinuv", 3_600),
        pullRequest(88, "WIP: rotate keys without downtime", "mzdrahal", 86_400 * 3, state: .draft),
        pullRequest(84, "fix: retry on transient KMS errors", "ondrajodas", 86_400 * 4),
    ]

    private static func pullRequest(
        _ number: Int,
        _ title: String,
        _ author: String,
        _ ago: TimeInterval,
        state: PullRequestState = .open
    ) -> PullRequestSummary {
        let id = PRIdentifier(repo: vault, number: number)
        return PullRequestSummary(
            id: id,
            title: title,
            author: author,
            url: Policy.githubURL(of: id),
            updatedAt: now.addingTimeInterval(-ago),
            state: state
        )
    }

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
