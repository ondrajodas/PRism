import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Volba u itineráře přežije i odchod na `Přehled`** (#506, čtvrté kolo).
///
/// Připomínka z proklikání přišla **podruhé**: *„pořád se ten itinerář zavírá.“* Třetí kolo
/// přestěhovalo stráž proti druhému uplatnění rozhodnutí #188 z `DiffView`u do `@State`
/// `PullRequestDetailView`u, takže volba přežila přepnutí tabu **uvnitř** pull requestu. Zůstala
/// ale cesta o úroveň výš.
///
/// ## Čím to bylo
///
/// `ContentView` vybírá obsah okna `switch store.activeTab` — a to je `@ViewBuilder`, tedy
/// **jiná větev je jiná identita**. Kliknutí na `Přehled` proto celý `PullRequestDetailView`
/// i s jeho `@State` zahodí a návrat na záložku PR je **nová instance s prázdnou stráží**, která
/// rozhodnutí uplatní jako první průchod — tedy přes `⌘1`.
///
/// Je to tatáž třída jako třetí kolo, jen o jednu úroveň výš: *stráž musí žít aspoň tak dlouho
/// jako stav, který mění*. Stav sloupce žije v `UserDefaults`, takže stráž patří tam, kde přežije
/// celé okno — do store (`AppStore.appliedSideColumns`), vedle `isReviewPanelExpanded` (#242).
///
/// ## Proč se to měří nad `ContentView`, ne nad detailem
///
/// **Protože ta vada je v `ContentView`.** Scéna, která hostuje jen detail, ji nemá kde vyrobit:
/// záložku `Přehled` kreslí `ContentView` a právě jeho `switch` detail zahazuje. Sada `#506/3`
/// (`ItineraryChoiceTests`) proto tuhle cestu nevidí a musí být obojí.
///
/// Okno je **1 512 × 882**, tedy uživatelovo — změřené `CGWindowListCopyWindowInfo` nad běžící
/// aplikací. `ContentView` si z toho vezme rail, takže detail dostane 1 460 bodů; na téhle šířce
/// se **nepřekračuje žádná mez** `Policy.diffSideColumns`, takže se sloupec z nedostatku místa
/// skládat nemá vůbec.
@MainActor
@Suite("Volba u itineráře přežije odchod na Přehled (#506)", .serialized)
struct ItineraryHomeReturnTests {
    static let key = "diffTreeExpanded"
    static let width = 1_512.0
    static let height = 882.0

    /// **`⌘1` ve `Vedle sebe` přežije odchod na `Přehled` a návrat.**
    ///
    /// Čtyři tvrzení po sobě a každé jiná otázka: uplatní se #188 → `⌘1` ho přebije → odchod
    /// volbu nezmění → **návrat ji nezmění taky**. To poslední je ta vada.
    @Test("Sloupec otevřený ⌘1 zůstane otevřený i po návratu z Přehledu")
    func theManualOpenSurvivesLeavingToHomeAndBack() async throws {
        let scene = try await Scene.make(layout: .split)
        defer { scene.close() }

        #expect(scene.stored == false, """
            Ve `Vedle sebe` se sloupec nesložil, takže #188 se neuplatnilo — dál už se neměří to, \
            o čem tahle sada je.
            """)

        scene.write(true)
        await scene.letItSettle()
        #expect(scene.stored == true, "`⌘1` sloupec neotevřelo, nebo ho hned něco zavřelo zpátky.")

        scene.store.activeTab = .home
        await scene.letItSettle()
        #expect(scene.stored == true, "Odchod na `Přehled` sloupec zavřel.")

        scene.store.activeTab = .pullRequest(Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == true, """
            Návrat na záložku PR sloupec zavřel — `switch store.activeTab` v `ContentView` zahodil \
            detail i se stráží, takže nová instance uplatnila #188 podruhé.
            """)
    }

    /// **A z druhé strany: složený sloupec se po návratu sám neotevře.**
    ///
    /// Tatáž vada s obrácenými znaménky, a je horší v tom, že si ji člověk vysvětlí jako
    /// „nezabralo to“. Bez tohohle tvrzení by oprava mohla znít „nikdy nezavírej“ a #188 by padlo.
    @Test("Sloupec složený ⌘1 zůstane složený i po návratu z Přehledu")
    func theManualCollapseSurvivesLeavingToHomeAndBack() async throws {
        let scene = try await Scene.make(layout: .unified)
        defer { scene.close() }

        #expect(scene.stored == true, "V `Pod sebou` sloupec rozložený není.")
        scene.write(false)
        await scene.letItSettle()
        #expect(scene.stored == false, "`⌘1` sloupec nesložilo.")

        scene.store.activeTab = .home
        await scene.letItSettle()
        #expect(scene.stored == false, "Odchod na `Přehled` sloupec otevřel.")

        scene.store.activeTab = .pullRequest(Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == false, "Návrat na záložku PR sloupec otevřel.")
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let store: AppStore
        /// **Drží se, i když z něj nikdo nečte** (#411): scéna čte `@AppStorage`, a jakmile
        /// poslední reference zmizí, `ScratchDefaults` po sobě doménu uklidí.
        let defaults: ScratchDefaults
        let directory: TemporaryDirectory

        var stored: Bool? { defaults.store.object(forKey: ItineraryHomeReturnTests.key) as? Bool }

        /// Ruční `⌘1` — tou cestou, jakou ho mačká člověk.
        func write(_ expanded: Bool) {
            defaults.store.set(expanded, forKey: ItineraryHomeReturnTests.key)
        }

        /// **Jméno není `settle()`** schválně: `settle()` je globální odmlka
        /// z `Tests/Support/TestWaiting.swift` (#296) a metoda téhož jména by ji zastínila.
        func letItSettle() async {
            for _ in 0..<12 { await settle() }
        }

        func close() { window.orderOut(nil) }

        static func make(layout: DiffLayout) async throws -> Scene {
            let defaults = try ScratchDefaults("itineraryHomeReturn")
            // **Výchozí hodnota se zapisuje, ne nechává chybět**: `object(forKey:)` nad nezapsaným
            // klíčem vydá `nil` a „nikdo nic nezapsal“ by se spletlo se „zapsalo se zavřeno“.
            defaults.store.set(true, forKey: ItineraryHomeReturnTests.key)
            let directory = try TemporaryDirectory()
            let gateway = FakeGitHubGateway(
                always: .success([summary]),
                detail: .success(detail),
                diffs: [.success(try Fixture.text("gh/pr-diff-ordinary.diff"))]
            )
            let store = AppStore(
                gateway: gateway,
                time: FakeTimeSource(stopAfter: 1),
                drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
            )
            await store.refresh()
            await store.loadDetail(for: summary)
            await store.loadDiff(for: summary)
            store.openTab(pr)
            store.setDetailTab(.filesChanged, for: pr)
            store.setDiffLayout(layout)

            // **Celé okno, ne jen detail**: vada je v `switch store.activeTab`, takže scéna, která
            // hostuje jen detail, ji nemá kde vyrobit.
            let hosting = NSHostingView(
                rootView: AnyView(
                    ContentView(store: store)
                        .frame(width: width, height: height, alignment: .topLeading)
                        .defaultAppStorage(defaults.store)
                )
            )
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
            let scene = Scene(window: window, store: store, defaults: defaults, directory: directory)
            await scene.letItSettle()
            return scene
        }
    }

    // MARK: - Materiál

    static let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    static let summary = PullRequestSummary(
        id: pr,
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    static let detail = PullRequest(
        id: pr,
        title: summary.title,
        author: summary.author,
        headSha: "aaaa1111",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Popis pull requestu, nad kterým se měří, jestli volba u sloupce vydrží."
    )
}
