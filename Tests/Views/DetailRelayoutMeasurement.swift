import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #472: **co stojí jedno přerovnání okna** — a kdo se v něm přeloží.
///
/// `DiffShapeProbe.relayoutCost` měří **tvar seznamu** nad předpočítanými řádky. Tahle sonda měří
/// **cestu, kterou kód doopravdy jde** (#275): skutečný `ContentView` nad skutečným `AppStore`,
/// tedy i se skládáním řádků, uzávěrů a parametrů panelu.
///
/// Měří se čtyři osy, protože #472 se ptá na víc věcí naráz a bez ablace se od sebe neodliší:
///
/// | Osa | Krajnosti | Na co odpovídá |
/// |---|---|---|
/// | scéna | okno / samotný detail | kolik z ceny patří tomu, co je vedle detailu |
/// | pohon | hostitel / zápis do store / tik / přepnutí tabu | co detail vůbec zneplatní — a co z toho je nejdražší |
/// | tab | soubory / přehled / kontroly | patří cena dlouhému seznamu, nebo panelu? |
/// | store | plný / prázdný | patří cena datům, nad kterými okno v provozu stojí? |
///
/// Výčet `cases` níž je **průnik**, ne všechny kombinace: každá série staví okno znovu a nechává
/// ho usadit, takže úplná mřížka by běžela desítky minut a odpověď navíc by nedala.
///
/// Vedle času se vypisuje **snímek počitadel** (`RenderDiagnostics`), protože „stálo to 300 ms“
/// a „přeložilo se 90 řádků diffu“ jsou dvě různá tvrzení a rozhodnutí visí na obojím.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Přerovnání okna nad PR (#472)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DetailRelayoutMeasurement {
    /// Kolik přerovnání v sérii. Jedno je pod rozlišením měřidla; dvacet je řádově to, co
    /// v aplikaci přijde za dvacet sekund práce s oknem.
    private static let relayouts = 20

    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    @Test("Kolik stojí přerovnání okna nad otevřeným PR")
    func relayoutCost() async throws {
        for lines in [500, 2000] {
            var costs: [Case: [Double]] = [:]
            var passes: [Case: [String]] = [:]
            // Série se střídají A/B/A/B — drift sezení je větší než hledaný rozdíl (#274).
            for _ in 0..<2 {
                for scenario in Self.cases {
                    // **Store i okno na každou sérii nové.** Odložené okno drží svůj strom dál
                    // a ten dál poslouchá store, takže by se do dalšího měření počítaly průchody
                    // tělem předchozích scén — v první podobě sondy z toho byl růst 0,57 → 2,26 s
                    // u téhož případu a osminásobný počet průchodů tělem.
                    let (store, directory) = try await prepared(lines: lines, payload: scenario.payload)
                    defer { _ = directory }
                    store.setDetailTab(scenario.tab, for: pr)
                    let (cost, snapshot) = try await measure(store: store, scenario: scenario)
                    costs[scenario, default: []].append(cost)
                    passes[scenario, default: []].append(snapshot)
                }
            }
            for scenario in Self.cases {
                let values = costs[scenario] ?? []
                let average = values.reduce(0, +) / Double(max(values.count, 1))
                print("MĚŘENÍ \(lines) řádků, \(scenario.label): "
                    + values.map { String(format: "%.2f", $0) }.joined(separator: " / ")
                    + String(format: " s CPU za %d přerovnání (%.0f ms na jedno)", Self.relayouts,
                             average / Double(Self.relayouts) * 1000)
                    + " — \((passes[scenario] ?? []).joined(separator: " | "))")
            }
        }
    }

    /// Co se hostuje. **Celé okno je ta poctivá krajnost**: v aplikaci se s detailem překresluje
    /// i rail, pruh záložek a stavový řádek, a samotný detail by z ceny vynechal právě je.
    ///
    enum Scene: String {
        case window = "okno"
        case detail = "jen detail"
        /// **Detail ve stejné kostře jako v okně, ale se slepými sousedy** — místo railu,
        /// hlavičky a stavového řádku stojí obarvené obdélníky téže velikosti.
        ///
        /// Je to ablace, která dělí dvě věci, co se jinak nedají odlišit: **stavbu sousedů**
        /// (jejich těla, jejich obsah) od **vyjednávání ve stacku**, do kterého je detail
        /// zasazený. Když vyjde blízko okna, cenu dělá kostra; když blízko samotného detailu,
        /// dělají ji sousedé.
        case chrome = "detail ve slepé kostře"
        /// Totéž, ale detail dostane **změřenou štěrbinu** (`fillingSlot()`) místo pružného
        /// rámce — tedy ta oprava, kterou repo na tuhle třídu má (#220, #361).
        case chromeMeasured = "slepá kostra, měřená štěrbina"
    }

    /// Čím se přerovnání vyvolá. **Dvě cesty, protože nejsou totéž** a rozdíl mezi nimi je
    /// polovina odpovědi na #472:
    ///
    /// - `hostitel` je průchod tělem nad scénou. Detail se poskládá znovu — a když se `store`,
    ///   shrnutí ani binding nezměnily, SwiftUI ho prohlásí za nezměněný a **tělo nepřeloží**.
    /// - `store` je zápis **jiné** hodnoty do sledované vlastnosti, kterou tělo detailu čte. Ten
    ///   tělo přeloží; zápis téže hodnoty naopak ne (viz `PollObservationTests`).
    enum Driver: String {
        case host = "hostitel"
        case store = "zápis do store"
        /// **Tichý tik pollingu** — `refresh()` nad fake gatewayí, která vrací pořád tentýž
        /// seznam. Je to ten scénář ze záznamu diagnostiky, kvůli kterému #472 vzniklo: okno,
        /// ve kterém se nic nezměnilo, spálilo za tik 1,0–1,5 s CPU.
        case poll = "tichý tik pollingu"
        /// **Přepnutí tabu tam a zpět** — `Přehled` ↔ `Soubory`. To je ta půlka #472, kterou
        /// uživatel popsal jako „chvíli to čeká a pak se to začne škubaně přepínat“: obsah tabu
        /// se přepnutím **zahodí a postaví znovu**, takže se platí **první rozvržení**, ne
        /// přerovnání. A první rozvržení je u pevného diffu (#469) vědomě drahé.
        case tab = "přepnutí tabu tam a zpět"
        /// **Přepnutí mezi dvěma taby bez diffu** (`Přehled` ↔ `Kontroly`) — ablace k tomu výš.
        /// Bez ní se nedá říct, kolik z ceny přepnutí patří diffu a kolik tomu, že se přestaví
        /// detail: obojí se přepnutím zahodí a staví znovu.
        case tabWithoutDiff = "přepnutí tabu bez diffu"
    }

    /// Co v store leží. **Ablace**: prázdný store je harness, plný je to, nad čím okno v provozu
    /// stojí — nálezy z proběhlého review, rozdělané review a **vlastní PR**, na kterém panel
    /// skládá zadání pro agenta (#333) při každém překreslení.
    enum Payload: String {
        case bare = "prázdný store"
        case loaded = "plný store"
    }

    /// Jeden měřený případ.
    struct Case: Hashable {
        let scene: Scene
        let tab: PullRequestTab
        let driver: Driver
        var payload: Payload = .loaded

        var label: String {
            "\(scene.rawValue), \(tab.czechLabel), \(driver.rawValue), \(payload.rawValue)"
        }
    }

    /// Taby jsou vybrané jako ablace: `Soubory` mají od #469 pevný diff, `Přehled` nemá dlouhý
    /// seznam vůbec a `Kontroly` k tomu nemají ani panel vpravo
    /// (`PullRequestTab.showsReviewPanel`) — bez těch dvou by z čísel nebylo poznat, kolik z ceny
    /// patří seznamu a kolik panelu.
    private static let cases: [Case] = [
        // Scénář, na který si člověk stěžuje, je **první**: přepnutí tabu nad diffem.
        Case(scene: .window, tab: .filesChanged, driver: .tab),
        Case(scene: .window, tab: .checks, driver: .tabWithoutDiff),
        Case(scene: .window, tab: .filesChanged, driver: .store),
        Case(scene: .window, tab: .filesChanged, driver: .poll),
        Case(scene: .window, tab: .filesChanged, driver: .host),
        // Ablace na to, **kde ta cena byla** (#472): kostra proti měřené štěrbině proti detailu
        // samotnému. Drží se v sondě, protože je to jediné místo, kde je ten rozdíl vidět jako
        // číslo — v aplikaci už měřená štěrbina je.
        Case(scene: .chrome, tab: .checks, driver: .store),
        Case(scene: .chromeMeasured, tab: .checks, driver: .store),
        Case(scene: .chrome, tab: .checks, driver: .tabWithoutDiff),
        Case(scene: .chromeMeasured, tab: .checks, driver: .tabWithoutDiff),
        Case(scene: .detail, tab: .checks, driver: .store),
    ]

    /// Jedna série: okno se nechá usadit (**příprava se neměří**, #274) a teprve pak se dvacetkrát
    /// přerovná.
    private func measure(store: AppStore, scenario: Case) async throws -> (Double, String) {
        let clock = RelayoutClock()
        // **Okno se staví jako `WindowGroup`, ne přes předepsaný `frame` na obsahu** — a je to
        // podmínka toho, aby ablace na zkratku minima vůbec něco měřila. `frame(width:height:)`
        // na scéně dotaz na minimum **zmrazí** (odpoví konstantou dřív, než se zanoří), takže by
        // obě podoby vyšly stejně; rozměr proto předepisuje okno. Tatáž konstrukce i tentýž důvod
        // jako v `IdleDiffSpinProbe.show(scene:minSizeFromContent:)`.
        let host = NSHostingView(
            rootView: WindowRelayoutHost(store: store, summary: Self.summary, scene: scenario.scene, clock: clock)
                .background(Palette.background)
        )
        // **Bez tohohle se `.contentMinSize` nemodeluje** a ablace by měřila dvakrát totéž:
        // druhé rozvržení okna si vynucuje právě dotaz na minimum, a ten hostující vrstva pošle
        // jedině s tímhle příznakem (změřeno `WindowMinimumProbe`).
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 874),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1512, height: 874))
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        // Zakryté okno nedostane takt překreslování, takže by se měřilo prázdno; fokus si sonda
        // nebere — tatáž konstrukce jako v `IdleDiffSpinProbe`.
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        // Okno se jen odloží. **Rozebrat ho zevnitř `defer`u nejde** — `contentView = nil`
        // a `close()` uprostřed měření položily testovacího hosta —, takže se cross-talk řeší
        // jinde: každá série má **vlastní store**, a odložená scéna tedy poslouchá store, do
        // kterého už nikdo nezapisuje.
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2.5)
        // **Nad čím se doopravdy měří.** Bez tohohle řádku vypadá měření nad oknem, ve kterém PR
        // vůbec není, stejně jako měření nad plným oknem — jen vyjde nula (stalo se: prázdný
        // seznam znamená prázdný stav místo detailu). Je to tentýž důvod, proč `DiffShapeProbe`
        // vypisuje `dojelo na …`.
        print("SONDA scéna \(scenario.scene.rawValue): \(store.pullRequests.count) PR v seznamu,"
            + " aktivní \(store.activeTab), tab \(store.detailTab(for: pr).czechLabel),"
            + " okno \(window.frame.size)")

        // **Snímek okna**, když si o něj někdo řekne (`PRISM_RENDER_DIR`). Měřená štěrbina je
        // změna rozvržení, takže se musí dát porovnat i očima, ne jen číslem.
        if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"], scenario.scene == .window {
            Self.write(host, to: URL(filePath: directory).appending(path: "okno-\(scenario.tab.czechLabel).png"))
        }

        // Počitadla se zapínají **až po usazení**, aby v snímku nebyla příprava.
        let diagnostics = try Self.counters()
        RenderDiagnostics.current = diagnostics
        defer { RenderDiagnostics.current = nil }
        let tab = store.detailTab(for: pr)
        let started = mainThreadCPUSeconds()
        for _ in 0..<Self.relayouts {
            switch scenario.driver {
            case .host: clock.tick += 1
            // Tatáž hodnota, jaká tam je: měří se **přerovnání**, ne přepnutí tabu.
            case .store: store.setDetailTab(tab, for: pr)
            case .poll: await store.refresh()
            case .tab:
                // Tam a zpět, ať se měří obojí a scéna skončí tam, kde začala.
                store.setDetailTab(.overview, for: pr)
                _ = spinMainRunLoop(seconds: 0.016)
                store.setDetailTab(.filesChanged, for: pr)
            case .tabWithoutDiff:
                store.setDetailTab(.overview, for: pr)
                _ = spinMainRunLoop(seconds: 0.016)
                store.setDetailTab(.checks, for: pr)
            }
            _ = spinMainRunLoop(seconds: 0.016)
        }
        let cost = mainThreadCPUSeconds() - started
        let mounted = window.contentView.map { Self.mounts(in: $0) } ?? (blocks: 0, mounts: 0)
        let snapshot = diagnostics.snapshot()
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let bodies = snapshot.isEmpty ? "žádná těla" : snapshot
        return (cost, "\(bodies), bloků \(mounted.blocks), nasazení \(mounted.mounts)")
    }

    /// Kolik bloků kódu v okně visí a kolikrát se **nasadily**. Bez toho čísla by se nedalo
    /// poznat, jestli se za přepnutí tabu platí znovunasazením všech `NSTextView`, nebo něčím
    /// jiným — a přesně to je otázka #469 proti #472.
    private static func mounts(in view: NSView) -> (blocks: Int, mounts: Int) {
        if let container = view as? DiffPairBlockContainer { return (1, container.mounts) }
        if let text = view as? DiffTextView { return (1, text.mounts) }
        return view.subviews.reduce((blocks: 0, mounts: 0)) { total, child in
            let found = mounts(in: child)
            return (total.blocks + found.blocks, total.mounts + found.mounts)
        }
    }

    /// Snímek okna do PNG — z okna na obrazovce přes `cacheDisplay`, protože blok kódu je
    /// AppKitové view a `ImageRenderer` na něj nedosáhne (tatáž cesta jako `DiffWindowRenderProbe`).
    private static func write(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("SONDA kresba \(url.lastPathComponent): view nevydalo bitmapu")
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("SONDA kresba \(url.lastPathComponent): bitmapa se nedala zapsat")
            return
        }
        // Selhání zápisu sondu nepokládá, ale mlčet se nesmí: „render se neuložil“ nesmí být
        // k nerozeznání od „nespustil jsem ho“.
        do {
            try data.write(to: url)
            print("SONDA kresba → \(url.lastPathComponent)")
        } catch {
            print("SONDA kresba \(url.lastPathComponent) se neuložila: \(error.localizedDescription)")
        }
    }

    /// Počitadla průchodů tělem. Zapisují do složky, která se hned zahodí — sondu zajímá
    /// `snapshot()`, ne soubor.
    private static func counters() throws -> RenderDiagnostics {
        let directory = try TemporaryDirectory()
        return RenderDiagnostics(
            log: DiagnosticsLog(url: directory.url.appending(path: "diagnostics.log"), zone: .gmt),
            zone: .gmt,
            interval: 3600
        )
    }

    /// Store s načteným detailem, diffem i konverzací — tedy se všemi měřenými taby.
    ///
    /// Diff je **skutečná fixture doplněná na požadovaný počet řádků** (`DiffMaterial`, sdílené
    /// s `DiffShapeProbe`): měří se cena, o které je otázka, jestli roste s délkou seznamu.
    private func prepared(
        lines: Int,
        payload: Payload = .loaded
    ) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        let gateway = FakeGitHubGateway(
            always: .success([Self.summary]),
            detail: .success(Self.detail),
            diffs: [.success(DiffMaterial.text(lines: lines))],
            conversations: [.success(Self.conversation())]
        )
        // **Viewer je autor PR**, takže je to `Moje PR` — a právě na vlastním PR skládá panel
        // zadání pro agenta při každém překreslení (#333). Prázdný store to nemá, a proto je
        // v tabulce obojí.
        if payload == .loaded { gateway.viewer = Self.summary.author }
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            // `stopAfter: 1`: `ContentView` si v `.task` pouští polling a fake hodiny nespí,
            // takže by se smyčka točila naplno a měřila by se ona, ne přerovnání.
            time: FakeTimeSource(stopAfter: 1),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        // **Seznam se musí naplnit**, jinak `ContentView` na `store.summary(for:)` nesáhne
        // a místo detailu nakreslí prázdný stav — sonda pak měří okno, ve kterém PR není
        // (naměřeno: 0,00 s CPU a nula průchodů tělem).
        await store.refresh()
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        await store.loadConversation(for: Self.summary)
        if payload == .loaded {
            await store.loadViewer()
            store.reviewRecords[pr] = Self.record
            store.setDraftBody("Zbytek vypadá dobře, jen ta jedna kontrola.", for: pr)
            // **Checky a commity taky** — pruh záložek si na ně sahá kvůli odznakům při **každém**
            // průchodu tělem detailu, takže prázdné mapy měřily spodní hranici scénáře.
            store.checks[pr] = Self.checks
            store.commits[pr] = Self.commits
        }
        store.openTab(pr)
        return (store, directory)
    }

    /// Záznam review s **dvaceti čtyřmi nálezy**. Není to horní odhad: na PR, kvůli kterým #472
    /// vzniklo, jich reviewer hlásí desítky, a panel, pruh záložek i tabulka je při každém
    /// překreslení procházejí.
    private static var record: ReviewRecord {
        let reported = (0..<48).map { index in
            makeReported(
                file: "src/Module\(index % 8)/Handler\(index % 8).swift",
                line: 12 + index * 3,
                category: index % 3 == 0 ? "correctness" : "tests",
                summary: "Nález číslo \(index): návratová hodnota se zahazuje, takže selhání "
                    + "zápisu vypadá v UI jako „nic tu nebylo“."
            )
        }
        return ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(findings: reported, headSha: "aaaa1111")]
        )
    }

    /// Konverzace o **dvou stech uzlech** (`ConversationFixture`, tatáž jako u dlouhé osy v #361).
    ///
    /// **Ne čtyřicetipoložková fixture z `gh`** (#472, druhé kolo měření): detail si konverzaci
    /// sahá i mimo tab `Konverzace` — bere z ní `viewer`, počet nevyřízených vláken a materiál pro
    /// zadání agentovi —, takže s krátkou konverzací měřila sonda **spodní hranici** toho, co má
    /// uživatel na obrazovce.
    private static func conversation() -> Conversation {
        ConversationFixture.conversation(comments: 200)
    }

    /// Checky, které mají v pruhu záložek odznak. Skutečné tvary, ne prázdný seznam.
    private static let checks: [PullRequestCheck] = (0..<12).map { index in
        PullRequestCheck(
            name: "kontrola \(index) / job",
            outcome: index % 4 == 0 ? .failed : .passed,
            link: URL(string: "https://github.com/cli/cli/actions/runs/\(index)"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 100 + Double(index))
        )
    }

    private static let commits: [PullRequestCommit] = (0..<24).map { index in
        let sha = String(format: "%040x", index + 1)
        let when = Date(timeIntervalSince1970: 1_753_000_000 + Double(index) * 3600)
        return PullRequestCommit(
            sha: sha,
            message: "commit \(index): oprava, která se v ose pozná podle titulku",
            authorName: index % 2 == 0 ? "Octo Cat" : "Hub Ot",
            authorLogin: index % 2 == 0 ? "octocat" : "hubot",
            avatarURL: nil,
            committedAt: when,
            isMerge: false
        )
    }

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "aaaa1111",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Popis pull requestu, na kterém se měří přerovnání detailu."
    )
}

/// Hostitel scény — model toho, co v aplikaci drží okno.
///
/// `@State` na `submission` je tu schválně, ne `.constant(nil)`: binding z `@State` má **stálou**
/// identitu úložiště, takže se sonda neptá na jiný stav než aplikace.
struct WindowRelayoutHost: View {
    let store: AppStore
    let summary: PullRequestSummary
    let scene: DetailRelayoutMeasurement.Scene
    let clock: RelayoutClock

    @State private var submission: ReviewSubmission?
    /// Rozdělaný merge (#465) — v aplikaci ho drží `ContentView` ze stejného důvodu jako
    /// `submission`, takže ho i sonda musí držet stejně: binding z `@State` má stálou identitu
    /// úložiště, a na tom stojí, že se detail poznává jako nezměněný.
    @State private var merge: MergeSubmission?

    /// Kostra z `ContentView`: hlavička nahoře, rail vlevo, stavový řádek dole. Rozměry jsou
    /// z aplikace, obsah slepý — měří se **tvar**, ne sousedé.
    private func skeleton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.gray.opacity(0.2).frame(height: 92)
            HStack(spacing: 0) {
                Color.gray.opacity(0.2).frame(width: 56)
                content()
            }
            Color.gray.opacity(0.2).frame(height: 28)
        }
    }

    private var detailView: some View {
        PullRequestDetailView(
            store: store,
            pullRequest: summary,
            submission: $submission,
            merge: $merge
        )
    }

    var body: some View {
        let _ = clock.tick
        switch scene {
        // Kořen okna má tvar z `RootView`, včetně jeho podlahy — na ní stojí dotaz na minimum.
        case .window: ContentView(store: store).frame(minWidth: 700, minHeight: 400)
        // Kostra z `ContentView`: hlavička nahoře, rail vlevo, stavový řádek dole. Rozměry jsou
        // z aplikace, obsah slepý — měří se **tvar**, ne sousedé.
        case .chrome:
            skeleton { detailView }
        case .chromeMeasured:
            skeleton { detailView.fillingSlot(alignment: .topLeading) }
        case .detail:
            PullRequestDetailView(
                store: store,
                pullRequest: summary,
                submission: $submission,
                merge: $merge
            )
        }
    }
}
