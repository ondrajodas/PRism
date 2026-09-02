import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Vejdou se kolony diffu do okna?** — sonda k vadě z proklikání #503: obsah diffu zalézal pod
/// složený proužek panelu vpravo.
///
/// Měří to, co se dá měřit: **rámec scrolleru diffu v souřadnicích okna**. Scroller je
/// `NSScrollView`, tedy skutečné AppKitové view — na rozdíl od kolon, které jsou SwiftUI a v okně
/// testovacího hostu se nedají přečíst z accessibility tree (změřeno u `DashboardCountdownRedrawTests`).
///
/// Ptá se přes **pásmo šířek**, ne u jedné (#236): vada se hlásila při varování `72 znaků na
/// stranu`, tedy u úzkého okna ve `Vedle sebe`, a u širokého se neprojeví.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, kresba do `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Vejdou se kolony diffu do okna? (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffColumnFitProbe {
    /// Šířky, na kterých se to zkouší. **700 je podlaha, ne odhad**: `RootView` má
    /// `frame(minWidth: 700)` a `PRismApp` `windowResizability(.contentMinSize)`, takže užší okno
    /// v aplikaci nevznikne. Zkoušet 509 **nemá smysl a je to zaplacená slepá ulička**: obsah se
    /// pod svým minimem rozvrhne na 700 a přeteče o 153 bodů, což je artefakt sondy, ne vada
    /// aplikace.
    ///
    /// **Horní konec je šířka obrazovky, ne dopočet z lišty.** Displej stroje má **1 512 × 982**
    /// bodů a je jediný, takže širší okno neexistuje — a řádky, které jsem si nad 1 512 vyrobil,
    /// vyšly nesmyslně (bitmapa z „1 792“ okna přišla 1 512bodová), takže jsou pryč.
    ///
    /// **Horní část pásma je ta zajímavá, a chyběla.** `72 znaků na stranu` z proklikání odpovídá
    /// koloně kódu ~**1 325 b** (`Policy.charactersPerSide` se zeptaná, ne invertovaná: znak
    /// 8,036 b, gutter 84 b, dvě strany) — a taková kolona se do 1 512 vejde **jedině tehdy, když
    /// se nekreslí okraj**: s ním zbývá 1 084 b, tedy 57 znaků. Scéna z proklikání tedy okraj
    /// **neměla**, ačkoli nálezy ano; to nastane, když žádný nález nesedí na kreslený řádek
    /// (`Policy.marginCards` je prázdná) — a přesně tuhle kombinaci pásmo do 1 400 netrefilo.
    private static let widths = [700.0, 1250.0, 1303.0, 1350.0]
    /// **Výška patří do scény, ne jako konstanta.** Živé okno má **860** bodů, ne 700, a karty
    /// v okraji se skládají podle výšky (odstrkování), takže se na jedné výšce dá minout stav,
    /// ve kterém se karty potkají. Změřená šířka i výška jsou z `CGWindowListCopyWindowInfo`
    /// nad běžící slotovou aplikací — funguje to i na okno na pozadí a bez asistenčního přístupu.
    private static let height = 860.0

    @Test("Rámec scrolleru diffu proti šířce okna")
    func columnsFit() async throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for width in Self.widths {
            for layout in [DiffLayout.split, .unified] {
                for findings in [true, false] {
                    for forced in Forced.allCases {
                        let scene = try await Scene.make(width: width, layout: layout, findings: findings)
                        defer { scene.window.orderOut(nil) }
                        await scene.letItSettle()
                        // **Ruční stav se nasazuje až po usazení**, ne před ním: `task(id: columns)`
                        // v `DiffView` při vzniku srovná strom i panel podle `Policy`, takže
                        // hodnota nastavená dřív by se přepsala. Po usazení se `columns` nemění,
                        // takže tenhle zápis už nikdo nesundá — a je to týž stav, do jakého se
                        // člověk dostane `⌘1` / `⌘2`.
                        await scene.force(forced)
                        let slug = String(format: "%.0f-%@-%@-%@", width,
                                          layout == .split ? "vedle" : "podsebou",
                                          findings ? "nalezy" : "bez", forced.rawValue)
                        print("SONDA \(slug): \(scene.report(findings: findings))")
                        if let directory {
                            scene.write(to: URL(filePath: directory).appending(path: "kolony-\(slug).png"))
                        }
                    }
                }
            }
        }
    }

    /// Co si člověk přebil ručně proti tomu, co `Policy.diffSideColumns` rozhodla.
    ///
    /// Je to podstatná část mřížky, ne úplnost: automatika sáhne na strom a panel **jednou na
    /// rozhodnutí** (`task(id: columns)` se stráží `appliedColumns`), takže stav *split a k tomu
    /// rozložený strom* je normální a **drží se**, dokud se pohled nezmění.
    enum Forced: String, CaseIterable {
        case none = "auto"
        case tree = "strom"
        case panel = "panel"
        case both = "strom+panel"
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let store: AppStore
        let defaults: ScratchDefaults
        let directory: TemporaryDirectory
        let width: Double

        static func make(width: Double, layout: DiffLayout, findings: Bool) async throws -> Scene {
            let defaults = try ScratchDefaults("diffColumnFit")
            let directory = try TemporaryDirectory()
            let gateway = FakeGitHubGateway(
                always: .success([summary]),
                detail: .success(detail),
                diffs: [.success(material())],
                conversations: [.success(ConversationFixture.conversation(comments: 8))]
            )
            let store = AppStore(
                gateway: gateway,
                time: FakeTimeSource(stopAfter: 1),
                drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
            )
            await store.refresh()
            await store.loadDetail(for: summary)
            await store.loadDiff(for: summary)
            await store.loadConversation(for: summary)
            if findings {
                store.reviewRecords[pr] = ReviewRecord(
                    pullRequest: summary.id,
                    headSha: "aaaa1111",
                    runs: [makeStoredRun(findings: reported, headSha: "aaaa1111")]
                )
            }
            store.openTab(pr)
            store.setDetailTab(.filesChanged, for: pr)
            store.setDiffLayout(layout)

            let clock = RelayoutClock()
            let host = NSHostingView(
                rootView: WindowRelayoutHost(store: store, summary: summary, scene: .window, clock: clock)
                    .background(Palette.background)
                    .defaultAppStorage(defaults.store)
            )
            host.sizingOptions = [.minSize]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: DiffColumnFitProbe.height),
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.setContentSize(NSSize(width: width, height: DiffColumnFitProbe.height))
            window.setFrameOrigin(NSPoint(x: 20, y: 20))
            window.level = .floating
            window.orderFrontRegardlessUnanimated()
            return Scene(window: window, store: store, defaults: defaults,
                         directory: directory, width: width)
        }

        /// Nechá scénu usadit. **Jméno není `settle()`** schválně: `settle()` je globální
        /// odmlka z `Tests/Support/TestWaiting.swift` (#296) a metoda téhož jména by ji uvnitř
        /// typu zastínila — volalo by se tady dokola samo sebe.
        func letItSettle() async {
            for _ in 0..<12 { await settle() }
        }

        /// Nasadí ruční stav (`⌘1` / `⌘2`) a nechá scénu znovu usadit.
        func force(_ forced: Forced) async {
            switch forced {
            case .none: return
            case .tree: defaults.store.set(true, forKey: "diffTreeExpanded")
            case .panel: store.isReviewPanelExpanded = true
            case .both:
                defaults.store.set(true, forKey: "diffTreeExpanded")
                store.isReviewPanelExpanded = true
            }
            await letItSettle()
        }

        /// Co se v okně naměřilo. **Scroller diffu je ta kolona s kódem**, takže jeho pravá hrana
        /// říká, kam obsah dosahuje — a šířka okna, kam dosahovat smí.
        ///
        /// K tomu se hlásí **rozdíl proti očekávanému pravému chromu**: obsah má končit tam, kde
        /// začíná okraj s kartami (300) nebo složený proužek panelu (38). Kladné `přetečení`
        /// znamená, že obsah zalézá pod ně.
        func report(findings: Bool) -> String {
            guard let root = window.contentView,
                  let scroller = Self.tallestScroller(in: root)
            else { return "scroller v okně není" }
            let frame = scroller.convert(scroller.bounds, to: nil)
            let right = width - frame.maxX
            // **Očekávání se skládá z `Policy`, ne z vlastních konstant**: sonda se jinak ptá na
            // jiné rozhodnutí, než jaké aplikace udělala, a její „přetečení“ pak měří rozdíl
            // dvou názorů místo vady. (Stalo se: první podoba sondy hlásila −306 tam, kde okno
            // sedělo na bod.)
            let columns = Policy.diffSideColumns(
                layout: store.configuration.global.diffLayout,
                hasMargin: findings,
                available: width - Self.railWidth - (store.isReviewPanelExpanded
                    ? Self.expandedPanelFloor : Self.collapsedPanelWidth)
            )
            let panelWidth = store.isReviewPanelExpanded ? Self.expandedPanelFloor : Self.collapsedPanelWidth
            let needed = Policy.marginColumnWidth(shown: columns.margin) + panelWidth
            // **Průnik, ne součet** — to je ta otázka, na kterou rámec scrolleru sám neodpoví.
            let edges = stripEdges()
            let overlapRight = edges.map { frame.maxX - $0.right } ?? .nan
            let overlapLeft = edges.map { $0.left - frame.minX } ?? .nan
            return String(
                format: "okno %.0f | scroller %.0f…%.0f | součet: zbývá %.0f, potřeba %.0f → %.0f"
                    + " | pruhy %@…%@ → PRŮNIK vlevo %@ vpravo %@ | okraj %@",
                width, frame.minX, frame.maxX, right, needed, needed - right,
                edges.map { String(format: "%.0f", $0.left) } ?? "?",
                edges.map { String(format: "%.0f", $0.right) } ?? "?",
                overlapLeft.isNaN ? "?" : String(format: "%.0f", overlapLeft),
                overlapRight.isNaN ? "?" : String(format: "%.0f", overlapRight),
                columns.margin ? "ano" : "ne"
            )
        }

        /// Šířka railu a mez panelu — **jen na skládání očekávání v sondě**. Rail je AppKitu
        /// neznámý (SwiftUI) a panel se dá táhnout, takže se bere jeho **podlaha**: kdyby obsah
        /// sahal dál než k ní, panel by se musel zmáčknout pod svoje minimum.
        static let railWidth = 56.0
        static let collapsedPanelWidth = 38.0
        static let expandedPanelFloor = 246.0

        static func tallestScroller(in view: NSView) -> NSScrollView? {
            var best = view as? NSScrollView
            for child in view.subviews {
                guard let found = tallestScroller(in: child) else { continue }
                let height = found.documentView?.frame.height ?? 0
                if height > (best?.documentView?.frame.height ?? 0) { best = found }
            }
            return best
        }

        /// **Kde jsou hrany pruhů, čtené z bitmapy** — a je to jiné měřidlo než rámec
        /// scrolleru, schválně (#478). Rámec může být správný a pruh na něm přesto malovat;
        /// z rámce se to nepozná ani náhodou, takže se hledá **průnik**, ne součet.
        ///
        /// Hrany se hledají **bez znalosti barev**, a je to opravená chyba: první podoba
        /// porovnávala `Palette.chrome` ve světlém režimu a v hostovaném okně, které se renderuje
        /// **tmavé**, nenašla nikdy nic — tedy „pruh nenalezen“ u všech 64 případů, což je tatáž
        /// hodnota pro funguje i nefunguje (#478). Místo barvy se proto bere **tvar**: pruh je
        /// souvislý svislý pás, který se dotýká hrany okna, takže se skenuje vodorovná řádka od
        /// hrany dovnitř a hlásí se, kde ten pás končí.
        ///
        /// **Co tohle měřidlo neumí, a proto se z něj nesmí dělat test** (#478): okraj s kartami
        /// a složený proužek panelu mají **tutéž plochu** (naměřeno `1E222D` u obou), takže
        /// souvislý pás od pravé hrany je **oba naráz** a hranici mezi nimi nenajde. K tomu ho
        /// **lámou karty**: na řádce, kde karta je, pás skončí na jejím okraji, ne na hraně
        /// kolony. Vrácená pravá hodnota je tedy „kde začíná pravý blok (okraj + proužek), nebo
        /// první karta v něm“ — na otázku *překrývá proužek obsah?* to odpovídá jedině tehdy,
        /// když vyjde uvnitř kolony kódu. Oddělit ty dvě kolony by chtělo hledat 1bodové dělící
        /// čárky (`Palette.lineSoft`), a to zatím udělané není.
        ///
        /// - Returns: pravá hrana levého pruhu a levá hrana pravého bloku, v bodech okna.
        func stripEdges() -> (left: Double, right: Double)? {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return nil }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = Double(bitmap.pixelsWide) / Double(view.bounds.width)
            // Řádka pod lištou diffu a nad stavovým řádkem — tedy tam, kde je kód i oba pruhy.
            let row = Int(Double(bitmap.pixelsHigh) * 0.6)
            func hex(_ column: Int) -> String? {
                guard let c = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { return nil }
                return String(format: "%02X%02X%02X", Int(c.redComponent * 255),
                              Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            }
            guard let leftColour = hex(0), let rightColour = hex(bitmap.pixelsWide - 1) else { return nil }
            var left = 0
            while left + 1 < bitmap.pixelsWide, hex(left + 1) == leftColour { left += 1 }
            var right = bitmap.pixelsWide - 1
            while right - 1 >= 0, hex(right - 1) == rightColour { right -= 1 }
            return (Double(left) / scale, Double(right) / scale)
        }

        func write(to url: URL) {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: url)
                print("SONDA kresba → \(url.lastPathComponent)")
            } catch {
                print("SONDA kresba \(url.lastPathComponent) se neuložila: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Materiál

    /// Nový soubor s dlouhými řádky — tedy ta scéna z proklikání: levá strana je celá šrafovaná
    /// a přesah je na ní vidět lépe než jinde.
    private static func material() -> String {
        var out = "diff --git a/App/Policy/PullRequestMap.swift b/App/Policy/PullRequestMap.swift\n"
        out += "new file mode 100644\n"
        out += "index 0000000..2222222\n"
        out += "--- /dev/null\n"
        out += "+++ b/App/Policy/PullRequestMap.swift\n"
        out += "@@ -0,0 +1,347 @@\n"
        for line in 0..<347 {
            // **Každý osmý řádek je dlouhý, a je to podmínka reprodukce, ne ozdoba.** Skutečné
            // diffy mají řádky, které se do kolony nevejdou — v `PRism#499` je nejdelší **557
            // znaků** —, takže blok kódu si říká o šířku dokumentu, kterou mu kolona nemůže dát.
            // S krátkými řádky (~80 znaků) se vodorovné přetečení nemá kde vzít a sonda měřila
            // scénu, ve které ta vada nastat nemůže.
            if line.isMultiple(of: 8) {
                out += "+    let segment\(line) = PullRequestMapSegment(file: file, rows: rows,"
                    + " kind: .added, anchor: DiffMarginAnchor(line: line, side: .right),"
                    + " severity: .blocking, summary: \"nález číslo \(line) na řádku, který se"
                    + " do kolony nevejde ani zdaleka\", reviewer: \"code-review\")\n"
            } else {
                out += "+    let segment\(line) = PullRequestMapSegment(file: file, rows: rows, kind: .added)\n"
            }
        }
        return out
    }

    private static let reported: [ReportedFinding] = (0..<4).map { index in
        makeReported(
            file: "App/Policy/PullRequestMap.swift",
            line: 12 + index * 40,
            category: index.isMultiple(of: 2) ? "correctness" : "style",
            summary: "Návratová hodnota se zahazuje, takže selhání zápisu vypadá jako „nic tu nebylo“."
        )
    }

    private static let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    private static let summary = PullRequestSummary(
        id: pr,
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
        body: "Popis pull requestu, nad kterým se měří, jestli se kolony vejdou."
    )
}


/// **Co doopravdy vydá `Policy.charactersPerSide`** — sonda, ne inverze.
///
/// Vznikla z chyby v úsudku: z Ondrova `72 znaků na stranu` jsem si šířku kolony **dopočítal
/// inverzí** (72 × 8,2 b + 84 b gutteru) a vyšlo mi okno ~1 780 b. Obrazovka stroje má ale
/// **1 512 × 982** bodů a je jediná, takže takové okno **fyzicky nemůže existovat** — jeden
/// z předpokladů inverze tedy neplatil. Ptát se funkce je levnější než hádat, který.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Kolik znaků na stranu Policy hlásí (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct CharactersPerSideProbe {
    @Test("Tabulka znaků na stranu přes pásmo šířek")
    func theTable() {
        let characterWidth = FontMetric.shared.characterWidth(
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
        print(String(format: "SONDA metrika: znak %.3f b, gutter split %.1f b, unified %.1f b, slib %d",
                     characterWidth,
                     DiffLineView.contentInset(for: .split),
                     DiffLineView.contentInset(for: .unified),
                     Policy.promisedCharactersPerSide))
        // Šířky **kolony kódu**, ne okna: to je ten vstup, který funkce dostane (`contentWidth`).
        // Pásmo jde od úzké kolony až po celou šířku obrazovky, aby bylo vidět, že 72 na stranu
        // ve `Vedle sebe` nemá kde vzniknout ani při kolonu přes celou obrazovku.
        for content in [200.0, 338.0, 500.0, 676.0, 800.0, 1000.0, 1088.0, 1174.0, 1300.0, 1440.0, 1512.0] {
            let split = Policy.charactersPerSide(
                contentWidth: content, characterWidth: characterWidth,
                layout: .split, gutter: DiffLineView.contentInset(for: .split)
            )
            let unified = Policy.charactersPerSide(
                contentWidth: content, characterWidth: characterWidth,
                layout: .unified, gutter: DiffLineView.contentInset(for: .unified)
            )
            print(String(format: "SONDA kolona %6.0f b → vedle sebe %3d znaků | pod sebou %3d znaků",
                         content, split, unified))
        }
    }
}

/// **Nezůstane ukazatel „znaků na stranu“ na čísle z předchozího pohledu?** (#503)
///
/// Vzniklo z rozporu, který se nedal vysvětlit šířkou: v okně **1 303 × 860** ve `Vedle sebe`
/// hlásí lišta `72 znaků na stranu`, jenže **tolik se tam nevejde**. `Policy.charactersPerSide`
/// se zeptaná (ne invertovaná) vydá při té šířce **44** znaků s okrajem a **62** bez něj — 72 by
/// si žádalo kolonu **1 325 b**, kdežto okno jich po odečtení railu a proužku dá nejvýš 1 179.
///
/// **72 ale odpovídá pohledu `Pod sebou`** při téže šířce: tam je jedna strana a gutter 136 b,
/// takže kolona ~714 b dá 70–72 znaků. Číslo z Ondrova snímku je tedy **číslo z toho druhého
/// pohledu** — a ukazatel je jediné vodítko, podle kterého člověk pozná, že má okno moc úzké.
///
/// Sonda proto scénu **přepne** (`Pod sebou` → `Vedle sebe`), nechá ji usadit a vypíše, jakou
/// šířku kolony kód doopravdy má; číslo v liště se přečte z přiloženého renderu.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, kresba do `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Znaků na stranu po přepnutí pohledu (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct CharacterGaugeAfterSwitchProbe {
    @Test("Kolona kódu a ukazatel po přepnutí Pod sebou → Vedle sebe")
    func afterSwitchingLayout() async throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        let characterWidth = FontMetric.shared.characterWidth(
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
        func expected(_ code: Double, _ layout: DiffLayout) -> Int {
            Policy.charactersPerSide(
                contentWidth: code, characterWidth: characterWidth,
                layout: layout, gutter: DiffLineView.contentInset(for: layout)
            )
        }

        for findings in [true, false] {
            // Scéna začíná **pod sebou**, tedy v tom pohledu, jehož číslo se v liště objevilo.
            let scene = try await DiffColumnFitProbe.Scene.make(
                width: 1303, layout: .unified, findings: findings
            )
            defer { scene.window.orderOut(nil) }
            await scene.letItSettle()
            let root = try #require(scene.window.contentView)
            let before = try #require(DiffColumnFitProbe.Scene.tallestScroller(in: root))
                .convert(DiffColumnFitProbe.Scene.tallestScroller(in: root)!.bounds, to: nil)
            print(String(format: "SONDA pod sebou, nálezy %@: kolona %.0f b → čekaný ukazatel %d znaků",
                         findings ? "ano" : "ne", before.width, expected(before.width, .unified)))

            scene.store.setDiffLayout(.split)
            await scene.letItSettle()
            let after = try #require(DiffColumnFitProbe.Scene.tallestScroller(in: root))
                .convert(DiffColumnFitProbe.Scene.tallestScroller(in: root)!.bounds, to: nil)
            print(String(format: "SONDA vedle sebe, nálezy %@: kolona %.0f b → čekaný ukazatel %d znaků"
                         + " (číslo z pod sebou by bylo %d)",
                         findings ? "ano" : "ne", after.width, expected(after.width, .split),
                         expected(before.width, .unified)))
            if let directory {
                scene.write(to: URL(filePath: directory)
                    .appending(path: "prepnuti-\(findings ? "nalezy" : "bez").png"))
            }
        }
    }
}
