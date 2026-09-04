import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Ruční složení a rozložení itineráře přežije přepnutí tabu** (#506, třetí kolo).
///
/// Nález z proklikání: *„někdy se ten levý panel zavře když na něco kliknu…ale jen někdy.“*
/// „Jen někdy“ je ta podstatná část — něco to podmiňuje, a je to **vznik `DiffView`u**.
///
/// ## Čím to bylo
///
/// Rozhodnutí #188 (*pohled vedle sebe složí postranní kolony*) uplatňoval `DiffView`
/// v `task(id: columns)` a stráž proti druhému uplatnění držel `@State appliedColumns`. Do #506
/// stál sloupec **uvnitř** diffu, takže ta stráž žila přesně tak dlouho jako on: zanikl diff,
/// zanikl sloupec, a rozhodnutí se při novém vzniku uplatnilo na čistou plochu.
///
/// Od #506 stojí sloupec **vedle všech osmi tabů** a jeho stav je v `UserDefaults`
/// (`diffTreeExpanded`), tedy přežívá. Stráž ale zůstala v `@State` diffu — a `switch tab`
/// v `PullRequestDetailView` diff při odchodu z `Změněných souborů` **zahodí**. Každý příchod
/// zpátky byl tedy nový `DiffView` s prázdnou stráží, který uloženou hodnotu **přepsal** tou
/// z `Policy`. Volba člověka tím zmizela, a přepsala se i pro příště.
///
/// ## Proč „jen někdy“
///
/// Přepisuje se jedině na hodnotu, která se od uložené liší — jinak si toho nikdo nevšimne:
///
/// | Stav | Co `Policy` vydá | Co se stalo |
/// |---|---|---|
/// | *Vedle sebe* (`⌘2`), sloupec otevřený `⌘1` | `tree == false` | **zavřel se** |
/// | *Pod sebou*, sloupec složený `⌘1` | `tree == true` | **otevřel se sám** |
/// | Sloupec ve stavu, jaký `Policy` chce | totéž | nic |
///
/// Reprodukce je tedy: `⌘2`, `⌘1` (sloupec se otevře), klik na `Kontroly`, klik na `Změněné
/// soubory` — a sloupec je zavřený. Stejně tak klik na **zastávku** nebo na **soubor**
/// v itineráři, protože obojí přepíná tab (`jump(toFile:)` míří do `Změněných souborů`).
///
/// ## Co je vada a co záměr
///
/// **Záměr**: první uplatnění rozhodnutí. Sloupec se ve `split`u skládá od #188 a je to změřené
/// (34 bodů místo 260), takže PR otevřený *Vedle sebe* má sloupec složený — a `⌘1` to přebije
/// „až do další změny pohledu“.
///
/// **Vada**: že „další změna pohledu“ nastala i tehdy, když se pohled nezměnil a jen zanikl
/// a znovu vznikl diff. Stráž musí žít tak dlouho jako to, co hlídá — tedy u sloupce, ne u diffu.
///
/// ## Co se tady dá měřit
///
/// **Stav sloupce, ne jeho kresba.** Kolony jsou SwiftUI a v hostovaném okně se z accessibility
/// tree přečíst nedají (změřeno u #546), ale uložená hodnota je obyčejný klíč v `UserDefaults` —
/// a právě ta je předmětem vady: přepisovala se **volba**, ne jen to, co je vidět. Čte se
/// `object(forKey:)`, ne `bool(forKey:)`, aby „nikdo nezapsal nic“ vyšlo `nil` a nespletlo se
/// se „zapsalo se zavřeno“.
@MainActor
@Suite("Volba u itineráře přežije přepnutí tabu (#506)", .serialized)
struct ItineraryChoiceTests {
    /// Klíč, ve kterém je stav sloupce. **Jméno z #197 a nepřejmenovává se** — význam hodnoty
    /// zůstal (rozložený sloupec), takže by se přejmenováním zahodila volba člověka.
    static let key = "diffTreeExpanded"

    /// Šířka hostovaného detailu — okno 1 100 bez railu (52). Tatáž hodnota, ze které počítá
    /// `ItineraryEveryTabTests` a `ItineraryColumnRoomTests`.
    static let width = 1_048.0
    static let height = 860.0

    /// **`⌘1` ve `Vedle sebe` přežije odchod do jiného tabu a zpátky.**
    ///
    /// Tvrzení jsou čtyři po sobě a každé z nich je jiná otázka; kdyby chybělo některé z prvních
    /// tří, poslední by netvrdilo nic:
    ///
    /// 1. rozhodnutí #188 se uplatní (sloupec se ve `split`u složí) — jinak by se dál neměřilo,
    ///    jestli ho něco přepisuje, ale jestli vůbec je;
    /// 2. `⌘1` ho přebije a **udrží** — to platilo i před opravou, protože stráž ve `@State`
    ///    diffu v tu chvíli ještě platila;
    /// 3. odchod do tabu bez diffu volbu nezmění;
    /// 4. **návrat do diffu ji nezmění taky** — a tohle je ta vada.
    @Test("Sloupec otevřený ⌘1 ve Vedle sebe zůstane otevřený i po návratu do diffu")
    func theManualOpenSurvivesLeavingAndReturningToTheDiff() async throws {
        let scene = try await Scene.make(layout: .split)
        defer { scene.close() }

        #expect(scene.stored == false, """
            Ve `Vedle sebe` se sloupec nesložil, takže #188 se neuplatnilo — dál už se neměří to, \
            o čem tahle sada je.
            """)

        scene.write(true)
        await scene.letItSettle()
        #expect(scene.stored == true, "`⌘1` sloupec neotevřelo, nebo ho hned něco zavřelo zpátky.")

        scene.store.setDetailTab(.checks, for: Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == true, "Odchod do `Kontrol` sloupec zavřel.")

        scene.store.setDetailTab(.filesChanged, for: Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == true, """
            Návrat do `Změněných souborů` sloupec zavřel — nový `DiffView` uplatnil rozhodnutí \
            #188 podruhé a přepsal tím volbu člověka.
            """)
    }

    /// **A totéž z druhé strany: složený sloupec se sám neotevře.**
    ///
    /// Je to tatáž vada s obrácenými znaménky, a je horší v tom, že si ji člověk vysvětlí jako
    /// „nezabralo to“. Bez tohohle tvrzení by oprava mohla znít „nikdy nezavírej“, a to by
    /// #188 zrušilo.
    @Test("Sloupec složený ⌘1 v Pod sebou zůstane složený i po návratu do diffu")
    func theManualCollapseSurvivesLeavingAndReturningToTheDiff() async throws {
        let scene = try await Scene.make(layout: .unified)
        defer { scene.close() }

        #expect(scene.stored == true, """
            V `Pod sebou` sloupec rozložený není — pak se dál neměří, jestli se sám otevírá.
            """)

        scene.write(false)
        await scene.letItSettle()
        #expect(scene.stored == false, "`⌘1` sloupec nesložilo.")

        scene.store.setDetailTab(.overview, for: Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == false, "Odchod do `Přehledu` sloupec otevřel.")

        scene.store.setDetailTab(.filesChanged, for: Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == false, """
            Návrat do `Změněných souborů` sloupec otevřel — volba člověka se přepsala i tímhle \
            směrem.
            """)
    }

    /// **Změna pohledu volbu přebít smí, a musí** (#188).
    ///
    /// Tohle je ta druhá polovina: bez ní by se dala vada „opravit“ tím, že se rozhodnutí
    /// neuplatní nikdy — a `⌘2` by pak nechalo sloupec 260 bodů široký v pohledu, ve kterém na
    /// řádek zbývá polovina.
    @Test("Přepnutí pohledu sloupec přerovná")
    func changingTheLayoutStillAppliesTheDecision() async throws {
        let scene = try await Scene.make(layout: .unified)
        defer { scene.close() }
        #expect(scene.stored == true)

        scene.store.setDiffLayout(.split)
        await scene.letItSettle()
        #expect(scene.stored == false, "Přepnutí na `Vedle sebe` sloupec nesložilo (#188).")

        scene.store.setDiffLayout(.unified)
        await scene.letItSettle()
        #expect(scene.stored == true, "Přepnutí zpátky na `Pod sebou` sloupec nerozložilo.")
    }

    /// **V tabu bez diffu se volba nepřepíše vůbec** — a je to ta zapsaná mezera z druhého kola
    /// #506, jen otočená do tvrzení.
    ///
    /// Rozhodnutí zůstává u diffu schválně: podlaha, kvůli které se sloupec skládá, je podlaha
    /// **kolony kódu** (`Policy.minimumCodeWidth`), a v `Kontrolách` není co chránit. Tvrdí se
    /// tady proto to, co z toho plyne — nad tabem bez diffu se stavem sloupce nehýbe **nic**, ani
    /// když se pohled změní. Složí ho první průchod diffem, tedy tehdy, kdy na tom začne záležet.
    ///
    /// **V aplikaci se do té mezery ani nedá dostat**: pohled přepíná lišta nad diffem, která je
    /// vidět jedině v tabu s diffem. Scéna to obchází přes store, aby se to dalo změřit.
    @Test("V tabu bez diffu se stavem sloupce nehýbe nic")
    func nothingTouchesTheChoiceInATabWithoutADiff() async throws {
        let scene = try await Scene.make(layout: .unified, tab: .checks)
        defer { scene.close() }
        #expect(scene.stored == true)

        scene.store.setDiffLayout(.split)
        await scene.letItSettle()
        #expect(scene.stored == true, """
            Nad `Kontrolami` se sloupec při přepnutí pohledu složil — rozhodnutí se tedy uplatňuje \
            i tam, kde není kolona kódu, kterou by chránilo.
            """)

        // A jakmile se do diffu přijde, uplatní se — jinak by tvrzení výš znamenalo, že se
        // rozhodnutí neuplatní nikdy.
        scene.store.setDetailTab(.filesChanged, for: Self.pr)
        await scene.letItSettle()
        #expect(scene.stored == false, "První průchod diffem sloupec nesložil (#188).")
    }

    // MARK: - Klik, který na šířku nesáhne (#506, čtvrté kolo)

    /// **Klik na `Nálezy pod řádky` sloupec nezavře** — čtvrté kolo #506, připomínka
    /// *„pořád se ten itinerář zavírá“*.
    ///
    /// ## Čím to bylo
    ///
    /// Třetí kolo přesunulo stráž k tomu, kdo stav drží, takže volba přežila přepnutí tabu.
    /// Zůstalo ale, že se rozhodnutí uplatňovalo **celé**, jakmile se změnilo v čemkoli —
    /// a `DiffSideColumns` má tři pole. `margin` závisí na `showInlineFindingBubbles`, na
    /// sbalení souboru i na odkrytém kontextu, tedy na věcech, které se překlikávají běžně;
    /// každá taková změna přepsala i `tree`, tedy uloženou volbu u itineráře.
    ///
    /// ## Proč se to měří na 1 460 bodech
    ///
    /// **Aby se nepřekročila žádná šířková mez.** V uživatelově okně (1 512 b, tedy 1 460 b
    /// na detail) je `available` 1 154 nebo 1 422 podle panelu, a obě čísla jsou nad mezí
    /// 920 — sloupec se tedy z nedostatku místa skládat nemá **vůbec**. Kdyby se scéna
    /// postavila na 1 048 b jako testy výš, vada by nenastala a bylo by to zeleně: proto je tady
    /// jiná šířka, ne z pohodlí.
    @Test("Vypnutí bublin nezavře sloupec otevřený ⌘1 (Vedle sebe)")
    func togglingBubblesKeepsTheManualOpen() async throws {
        let scene = try await Scene.make(layout: .split, width: Self.userWidth, findings: true)
        defer { scene.close() }

        #expect(scene.stored == false, "Ve `Vedle sebe` se sloupec nesložil, #188 se neuplatnilo.")
        scene.write(true)
        await scene.letItSettle()
        #expect(scene.stored == true, "`⌘1` sloupec neotevřelo.")

        scene.bubbles(false)
        await scene.letItSettle()
        #expect(scene.stored == true, """
            Klik na `Nálezy pod řádky` sloupec zavřel — rozhodnutí o kolonách se uplatnilo celé,             i když se o sloupci rozhodlo úplně stejně jako minule.
            """)

        scene.bubbles(true)
        await scene.letItSettle()
        #expect(scene.stored == true, "Zapnutí bublin sloupec zavřelo.")
    }

    /// **A totéž z druhé strany: složený sloupec se po tom kliku sám neotevře.**
    ///
    /// Naměřeno v `Pod sebou`, kde `Policy` sloupec rozložený chce — takže tam ta vada zněla
    /// „nezabralo mi to složení“, což si člověk vysvětlí jako svoji chybu.
    @Test("Vypnutí bublin neotevře sloupec složený ⌘1 (Pod sebou)")
    func togglingBubblesKeepsTheManualCollapse() async throws {
        let scene = try await Scene.make(layout: .unified, width: Self.userWidth, findings: true)
        defer { scene.close() }

        #expect(scene.stored == true, "V `Pod sebou` sloupec rozložený není.")
        scene.write(false)
        await scene.letItSettle()
        #expect(scene.stored == false, "`⌘1` sloupec nesložilo.")

        scene.bubbles(false)
        await scene.letItSettle()
        #expect(scene.stored == false, """
            Klik na `Nálezy pod řádky` sloupec otevřel — volba člověka se přepsala i tímhle směrem.
            """)
    }

    /// **Panel se za kartami dál srovná** (#503) — bez tohohle tvrzení by se dala vada „opravit“
    /// tím, že automatika nezapíše nikdy, a nález v okně užším než okraj by zmizel.
    ///
    /// Karty existují jedině s vypnutými bublinami, takže tenhle přepínač je zároveň tou
    /// jedinou cestou, jak `hasMargin` v usazené scéně přehodit.
    @Test("Panel se za kartami dál srovná")
    func thePanelStillFollowsTheCards() async throws {
        let scene = try await Scene.make(layout: .unified, width: Self.userWidth, findings: true)
        defer { scene.close() }
        #expect(scene.store.isReviewPanelExpanded, """
            Bez karet má být panel rozložený — dál se neměří, jestli ho karty složí.
            """)

        scene.bubbles(false)
        await scene.letItSettle()
        #expect(!scene.store.isReviewPanelExpanded, """
            Karty se objevily a panel zůstal rozložený — #503 se přestalo uplatňovat, tedy             oprava zašla dál, než měla.
            """)

        scene.bubbles(true)
        await scene.letItSettle()
        #expect(scene.store.isReviewPanelExpanded, "Karty zmizely a panel se nevrátil.")
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let store: AppStore
        /// **Drží se, i když z něj nikdo nečte** (#411): scéna čte `@AppStorage`, a jakmile
        /// poslední reference zmizí, `ScratchDefaults` po sobě doménu uklidí — tedy dřív, než se
        /// hodnota přečte.
        let defaults: ScratchDefaults
        /// Kořen cache pro drafty. Drží se ze stejného důvodu jako `defaults`: se zánikem se maže.
        let directory: TemporaryDirectory

        /// Co je v uloženém stavu **teď**.
        var stored: Bool? { defaults.store.object(forKey: ItineraryChoiceTests.key) as? Bool }

        /// Ruční `⌘1` — tou cestou, jakou ho mačká člověk: `@AppStorage` sleduje doménu, takže se
        /// zápis propíše do už postavené scény.
        func write(_ expanded: Bool) {
            defaults.store.set(expanded, forKey: ItineraryChoiceTests.key)
        }

        /// **Jméno není `settle()`** schválně: `settle()` je globální odmlka z `TestWaiting.swift`
        /// (#296) a metoda téhož jména by ji uvnitř typu zastínila.
        func letItSettle() async {
            for _ in 0..<12 { await settle() }
        }

        func close() { window.orderOut(nil) }

        /// Klik na `Nálezy pod řádky` v liště diffu. Vypnuté bubliny jsou podmínka toho, aby
        /// v okraji vznikly karty (`DiffView.marginCards`), takže tenhle jediný přepínač mění
        /// `hasMargin` — a tím i rozhodnutí `Policy.diffSideColumns`.
        func bubbles(_ shown: Bool) {
            defaults.store.set(shown, forKey: "showInlineFindingBubbles")
        }

        static func make(
            layout: DiffLayout,
            tab: PullRequestTab = .filesChanged,
            width: Double = ItineraryChoiceTests.width,
            findings: Bool = false
        ) async throws -> Scene {
            let defaults = try ScratchDefaults("itineraryChoice")
            // **Výchozí hodnota se zapisuje, ne nechává chybět**: `@AppStorage` má default `true`,
            // ale `object(forKey:)` by nad nezapsaným klíčem vydal `nil` — a testy níž potřebují
            // rozeznat „uplatnilo se rozhodnutí“ od „nikdo nic nezapsal“.
            defaults.store.set(true, forKey: ItineraryChoiceTests.key)
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
            if findings {
                // **Nálezy musí sedět na řádky, které fixture doopravdy kreslí** — karta v okraji
                // vznikne jedině tam, kde má co k čemu zarovnat (`Policy.marginCards`), takže
                // nález na cizí cestě by scénu postavil bez okraje a měřilo by se něco jiného.
                store.reviewRecords[pr] = ReviewRecord(
                    pullRequest: pr,
                    headSha: detail.headSha,
                    runs: [makeStoredRun(findings: reported, headSha: detail.headSha)]
                )
            }
            store.openTab(pr)
            store.setDetailTab(tab, for: pr)
            store.setDiffLayout(layout)

            let hosting = NSHostingView(
                rootView: AnyView(
                    ItineraryChoiceHost(store: store, summary: summary)
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

    /// Šířka detailu v **uživatelově** okně: 1 512 bodů displeje minus rail (52). Změřeno
    /// `CGWindowListCopyWindowInfo` nad běžící aplikací, ne odhadnuto — a je to ta šířka, na
    /// které se **nepřekračuje žádná mez** `Policy.diffSideColumns`.
    static let userWidth = 1_460.0

    /// Nálezy na řádcích, které `gh/pr-diff-ordinary.diff` doopravdy kreslí (`CLAUDE.md` hunk
    /// od 171, `README.md` od 66) — bez toho by karta v okraji neměla co k čemu zarovnat.
    static let reported: [ReportedFinding] = [
        makeReported(
            file: "CLAUDE.md",
            line: 174,
            category: "correctness",
            summary: "Nález, kvůli kterému v okraji vznikne karta."
        ),
        makeReported(
            file: "README.md",
            line: 69,
            category: "style",
            summary: "Druhý nález, aby karta byla i v druhém souboru."
        ),
    ]

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

/// Hostitel detailu — sheety drží v aplikaci `ContentView`, takže je i tady musí držet něco
/// **nad** detailem: binding z `@State` má stálou identitu úložiště, a na tom stojí, že se detail
/// poznává jako nezměněný.
private struct ItineraryChoiceHost: View {
    let store: AppStore
    let summary: PullRequestSummary

    @State private var submission: ReviewSubmission?
    @State private var merge: MergeSubmission?
    @State private var branchPush: BranchPushSubmission?

    var body: some View {
        PullRequestDetailView(
            store: store,
            pullRequest: summary,
            submission: $submission,
            merge: $merge,
            branchPush: $branchPush
        )
    }
}
