import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Obsah diffu se sází na svou kolonu, ne na štěrbinu celého tabu** (#546).
///
/// Vada, kvůli které to vzniklo: `\.availableWidth` v podstromu diffu byla šířka **celého tabu**,
/// takže se všechno, co si šířku bere z prostředí (`filling()` — v diffu bublina vlákna), přibilo
/// na okno bez railu a panelu, tedy o strom, okraj a mezeru **širší**, než jaké místo dostalo.
/// K tomu `ThreadBubbleView` o své odsazení nezúžila šířku pro děti, takže si přidala dalších
/// `indent + 16`. `ScrollView` se v nescrollované ose řídí velikostí obsahu, takže z toho byla
/// plocha širší než kolona — a `frame(width:)` ji **vystředil**, tedy vylil doleva přes rail.
/// Naměřeno na živém okně 1100 × 700: kolona 970 b, obsah **1110 b**.
///
/// ## Proč to jde postavit v hostovaném okně, když sonda #503 tu vadu neviděla
///
/// `DiffColumnFitProbe` staví scénu s dlouhými řádky kódu a s nálezy — a ani jedno tu vadu
/// nevyrobí: blok kódu si šířku bere z **návrhu** (`sizeThatFits`) a nález je od #503 v okraji,
/// tedy ne v řádku. Chybějící přísada je **vlákno s kotvou v tom diffu**: jedině `ThreadBubbleView`
/// se v řádku diffu přibíjí na `\.availableWidth`. Bez něj se scéna chová správně a měřidlo vydá
/// tutéž hodnotu pro „funguje“ i „nefunguje“ (#478), takže tady je vlákno **podmínka scény**, ne
/// ozdoba — a druhá polovina každého tvrzení to kontroluje.
///
/// ## Co se měří
///
/// **Šířka plochy obsahu diffu a šířka jejího dokumentu**, obojí z AppKitu: SwiftUI `ScrollView`
/// je na macOS `NSScrollView`, takže se dá přečíst z hierarchie okna (kolony samotné jsou SwiftUI
/// a v hostovaném okně se z accessibility tree nedají přečíst). `documentView` je ta hodnota, do
/// které se přeteklý obsah propíše — právě ona vyšla 1110 nad kolonou 970.
///
/// Ptá se to **přes pásmo šířek**, ne u jedné (#236), v obou pohledech a s okrajem i bez něj.
@MainActor
@Suite("Obsah diffu se sází na svou kolonu (#546)", .serialized)
struct DiffCodeColumnWidthTests {
    /// Šířky **štěrbiny diffu**, tedy toho, co dostane `DiffView` (`\.availableWidth`) — okno bez
    /// railu (52) a bez složeného proužku panelu (38). Odpovídají oknům 700 (podlaha `RootView`u),
    /// 1100, 1303 a 1512 (šířka displeje), tedy těm, ve kterých se to měřilo živě.
    ///
    /// **Konstanty se sem neopisují**, protože by z nich byla druhá pravda o šířce railu: pásmo
    /// jsou přímo štěrbiny a odkud se vzaly, je tady napsané.
    nonisolated static let slots: [Double] = [610, 1010, 1213, 1422]

    /// Výška scény. Diff je vždycky vyšší, takže plocha obsahu rovnou dostane svislý posuvník —
    /// a právě ten je na tomhle měření to jediné neintuitivní (viz `scrollerReserve`).
    private static let height = 700.0

    /// Kolik si smí plocha obsahu vzít nad kolonu, aby to ještě nebyla vada.
    ///
    /// **Není to tolerance na nepřesnost, je to změřená rezerva na posuvník**: `NSScrollView`
    /// s legacy posuvníky (systémové *Zobrazovat posuvníky: vždy*) hlásí v nescrollované ose
    /// šířku obsahu **plus pás posuvníku**, takže plocha vyjde o těch pár bodů širší než kolona,
    /// kterou dostala. Bere se z AppKitu, ne jako konstanta 17 — tentýž důvod jako u
    /// `DiffPairScrollView.scrollerHeight` (#422).
    ///
    /// **Vadu to nezakrývá**: #546 přetékalo o **140** bodů (a s okrajem o 440), tedy o řád víc.
    private static var scrollerReserve: Double {
        Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
    }

    // MARK: - Tvrzení

    @Test(
        "Plocha obsahu diffu není širší než kolona kódu",
        arguments: slots, [DiffLayout.split, .unified]
    )
    func theContentAreaFitsTheCodeColumn(slot: Double, layout: DiffLayout) throws {
        for hasFindings in [false, true] {
            let scene = try Scene.make(slot: slot, layout: layout, hasFindings: hasFindings)
            defer { scene.close() }
            let measured = try scene.measureContentArea()
            let column = try #require(scene.codeColumn(hasFindings: hasFindings))

            // **Druhá polovina tvrzení je nad měřidlem**, ne nad aplikací: bez bubliny vlákna
            // v seznamu by scéna tu vadu nevyrobila a zelená by neznamenala nic (#478).
            #expect(scene.bubbleCount > 0, """
                Ve scéně není ani jedna bublina vlákna — nad takovou scénou #546 nenastane, \
                takže tvrzení níž netvrdí nic.
                """)

            #expect(
                measured.document <= column + 0.5,
                """
                Obsah diffu se sází na \(measured.document) b, ačkoli kolona kódu je \(column) b \
                (štěrbina \(slot), \(layout), nálezy \(hasFindings)). To je #546: přesah odchází \
                doleva přes rail, takže levé polovině splitu chybí čísla řádků.
                """
            )
            #expect(
                measured.area <= column + Self.scrollerReserve + 0.5,
                """
                Plocha obsahu diffu je \(measured.area) b nad kolonou \(column) b \
                (štěrbina \(slot), \(layout), nálezy \(hasFindings)) — víc než rezerva na \
                posuvník (\(Self.scrollerReserve)).
                """
            )
        }
    }

    /// **Ukazatel `N znaků na stranu` mluví o koloně, ne o ploše** (#546).
    ///
    /// Do #546 bral `contentWidth` změřený na ploše obsahu, tedy tu přeteklou hodnotu — v okně
    /// 1512 hlásil `84 znaků na stranu` nad kolonou, do které se jich vejde 62. Tvrdí se to nad
    /// **týmiž** čísly, ze kterých se ta věta v liště skládá.
    @Test("Ukazatel znaků počítá z kolony, ne z přeteklé plochy", arguments: slots)
    func theGaugeCountsFromTheColumn(slot: Double) throws {
        let scene = try Scene.make(slot: slot, layout: .split, hasFindings: false)
        defer { scene.close() }
        let measured = try scene.measureContentArea()
        let column = try #require(scene.codeColumn(hasFindings: false))
        let gauge = Policy.charactersPerSide(
            contentWidth: column,
            characterWidth: FontMetric.shared.characterWidth(
                of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ),
            layout: .split,
            gutter: DiffLineView.contentInset(for: .split)
        )
        // Kolik by hlásil, kdyby se počítalo z plochy — tedy to, co dělal do #546.
        let fromTheArea = Policy.charactersPerSide(
            contentWidth: measured.area,
            characterWidth: FontMetric.shared.characterWidth(
                of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ),
            layout: .split,
            gutter: DiffLineView.contentInset(for: .split)
        )
        #expect(gauge <= fromTheArea, "Kolona je širší než plocha — pásmo měří něco jiného")
        #expect(gauge > 0, "Štěrbina \(slot): ukazatel nemá co hlásit")
    }

    /// **Kresba k okoukání**, ne tvrzení — pouští se ručně (`TEST_RUNNER_PRISM_MEASURE=1`,
    /// `TEST_RUNNER_PRISM_RENDER_DIR=…`). Čísla výš říkají, že se obsah do kolony vejde; jak
    /// v ní **vypadá** bublina vlákna (končí 16 b před hranou kolony, ne ořezaná o ni), se
    /// z čísel přečíst nedá.
    @Test(
        "Kresba kolony s bublinou vlákna",
        .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
    )
    func drawTheColumn() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for slot in Self.slots {
            for layout in [DiffLayout.split, .unified] {
                let scene = try Scene.make(slot: slot, layout: layout, hasFindings: false)
                defer { scene.close() }
                let measured = try scene.measureContentArea()
                let column = scene.codeColumn(hasFindings: false) ?? 0
                print(String(
                    format: "SONDA #546 štěrbina %.0f %@: kolona %.0f | plocha %.0f | dokument %.0f",
                    slot, layout == .split ? "vedle" : "podsebou",
                    column, measured.area, measured.document
                ))
                if let directory {
                    let name = String(format: "kolona-%.0f-%@.png", slot,
                                      layout == .split ? "vedle" : "podsebou")
                    scene.write(to: URL(filePath: directory).appending(path: name))
                }
            }
        }
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        /// **Drží se, i když z něj nikdo nečte** (#411): scéna čte `@AppStorage`, a jakmile poslední
        /// reference zmizí, `ScratchDefaults` po sobě doménu uklidí — tedy dřív, než se okno změří.
        let defaults: ScratchDefaults
        let slot: Double
        let layout: DiffLayout
        /// Kolik bublin vlákna v seznamu doopravdy je — druhá polovina tvrzení (#478).
        let bubbleCount: Int

        static func make(slot: Double, layout: DiffLayout, hasFindings: Bool) throws -> Scene {
            let defaults = try ScratchDefaults("diffCodeColumnWidth")
            // **Bubliny nálezů v řádku zůstávají vypnuté** (výchozí stav od #503): nález patří do
            // okraje, takže scénu s okrajem staví `hasFindings`, ne přepínač.
            defaults.store.set(false, forKey: "showInlineFindingBubbles")
            let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
            let threads = try Self.threads(in: diff)
            let findings = hasFindings ? Self.findings(in: diff) : []
            let rows = Self.bubbleRows(in: diff, layout: layout, threads: threads)

            let hosting = NSHostingView(
                rootView: AnyView(
                    DiffView(
                        diff: diff,
                        subject: "cli/cli#42",
                        scrollTarget: .constant(nil),
                        expansion: DiffExpansionActions(
                            state: { _ in FileExpansion() },
                            reveal: { _, _ in },
                            collapse: nil
                        ),
                        folding: DiffFoldingActions(
                            isFolded: { _ in false },
                            toggle: { _ in },
                            foldAll: { _ in },
                            unfoldAll: {}
                        ),
                        findings: findings,
                        threads: threads,
                        layout: .constant(layout)
                    )
                    // **Takhle to dělá detail PR** (#220): šířku tabu změří jednou a pošle ji
                    // dolů prostředím i rámcem. Bez obojího by scéna neměla tu vlastnost, na
                    // které #546 stojí.
                    .availableWidth(slot)
                    .frame(width: slot, height: height, alignment: .topLeading)
                    .defaultAppStorage(defaults.store)
                )
            )
            hosting.frame = NSRect(x: 0, y: 0, width: slot, height: height)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontUnanimated()
            let scene = Scene(
                window: window,
                hosting: hosting,
                defaults: defaults,
                slot: slot,
                layout: layout,
                bubbleCount: rows
            )
            scene.letItSettle()
            return scene
        }

        func close() {
            window.orderOut(nil)
        }

        /// Bitmapa okna do souboru — pro `drawTheColumn()`. `cacheDisplay(in:to:)`, protože
        /// `CGWindowListCreateImage` na macOS 26 není a hostované okno stojí mimo obrazovku.
        func write(to url: URL) {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            do {
                try data.write(to: url)
                print("SONDA #546 kresba → \(url.lastPathComponent)")
            } catch {
                print("SONDA #546 kresba \(url.lastPathComponent) se neuložila: \(error)")
            }
        }

        /// Nechá scénu doskládat. **Jev, ne pevný okamžik** (#269): čeká se, dokud se přestane
        /// měnit šířka plochy obsahu.
        func letItSettle(sourceLocation: SourceLocation = #_sourceLocation) {
            let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
            var quiet = 0
            var previous = -1.0
            while ContinuousClock.now < limit, quiet < 3 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                hosting.layoutSubtreeIfNeeded()
                let width = Self.contentArea(in: hosting)?.frame.width ?? -1
                quiet = width == previous ? quiet + 1 : 0
                previous = width
            }
            // **Nedočkání se hlásí, nepolyká** (nález Copilota): měřit polorozloženou scénu znamená
            // buď náhodně zelený běh, nebo pád o pár kroků dál, ze kterého se příčina nepozná.
            // Tentýž vzorec jako v `DiffScrollerRideTests`.
            if quiet < 3 {
                Issue.record(
                    """
                    Nedočkalo se: šířka plochy obsahu se do \(TestWait.deadline) neustálila \
                    (naposled \(previous) b, štěrbina \(slot), \(layout)).
                    """,
                    sourceLocation: sourceLocation
                )
            }
        }

        /// Šířka plochy obsahu a jejího dokumentu.
        func measureContentArea() throws -> (area: Double, document: Double) {
            let scroller = try #require(
                Self.contentArea(in: hosting),
                "V okně není plocha obsahu diffu — tvrzení by bylo o prázdnu."
            )
            // **Dokument se nedopočítává z plochy** (`?? scroller.frame.width`): chybějící
            // dokument znamená prázdný `ScrollView`, tedy scénu, nad kterou tvrzení níž nic
            // neříká — a to se nesmí schovat za hodnotu, která náhodou projde.
            let document = try #require(
                scroller.documentView,
                "Plocha obsahu diffu nemá dokument — v okně není co měřit."
            )
            return (Double(scroller.frame.width), Double(document.frame.width))
        }

        /// Kolona kódu, jak ji spočítá `Policy` — tedy **totéž číslo, jaké si předává aplikace**.
        /// Skládat ji tady z konstant by znamenalo druhou pravdu o jedné šířce (#236).
        func codeColumn(hasFindings: Bool) -> Double? {
            let columns = Policy.diffSideColumns(
                layout: layout,
                hasMargin: hasFindings,
                available: slot
            )
            return Policy.diffCodeColumnWidth(available: slot, columns: columns)
        }

        /// Plocha obsahu diffu. Hledá ji **jedno místo** (`NSView.diffContentArea()`, od #548):
        /// tutéž procházku potřebuje i sada nad výchozím stavem přepínače, a dvě kopie by se při
        /// první opravě rozešly.
        static func contentArea(in view: NSView) -> NSScrollView? {
            view.diffContentArea()
        }

        // MARK: - Materiál

        /// Vlákna **s kotvou v tom diffu** — bez nich se #546 nemá kde vzít.
        ///
        /// Řádek se hledá v samotném diffu, ne opisuje z fixture: kdyby se fixture změnila,
        /// vymyšlené číslo by kotvu minulo a bublina by se nenakreslila — a to je zrovna ten stav,
        /// ve kterém test zezelená nad prázdnou scénou.
        static func threads(in diff: Diff) throws -> [ReviewThread] {
            var found: [ReviewThread] = []
            for file in diff.files {
                guard let line = file.hunks
                    .flatMap(\.lines)
                    .compactMap({ Policy.number(of: $0, on: .right) })
                    .first
                else { continue }
                found.append(ReviewThread(
                    id: "t\(found.count)",
                    path: file.displayPath,
                    line: line,
                    originalLine: line,
                    side: .right,
                    isResolved: false,
                    isOutdated: false,
                    comments: ConversationPage(
                        items: [ThreadComment(
                            id: "c\(found.count)",
                            author: "kolega",
                            body: "Tady chybí test na prázdný vstup.",
                            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
                            url: URL(string: "https://github.com/cli/cli/pull/42#discussion_r\(found.count)")!
                        )],
                        total: 1,
                        hasNextPage: false
                    )
                ))
            }
            guard !found.isEmpty else { throw SceneError.noAnchors }
            return found
        }

        /// Nálezy s kotvou v diffu — z nich se skládá okraj (#503), tedy ta užší kolona kódu.
        static func findings(in diff: Diff) -> [FindingGroup] {
            diff.files.prefix(2).compactMap { file in
                guard let line = file.hunks
                    .flatMap(\.lines)
                    .compactMap({ Policy.number(of: $0, on: .right) })
                    .last
                else { return nil }
                return FindingGroup(
                    file: file.displayPath,
                    line: line,
                    findings: [makeFinding(
                        file: file.displayPath,
                        line: line,
                        summary: "Návratová hodnota se zahazuje, takže selhání vypadá jako prázdno."
                    )]
                )
            }
        }

        /// Kolik řádků seznamu je bublina vlákna — spočítané **tou cestou, kterou seznam skládá
        /// `DiffView`** (`DiffRow.rows` a slití do bloků), takže se to nedá rozejít s tím, co se
        /// doopravdy kreslí.
        static func bubbleRows(in diff: Diff, layout: DiffLayout, threads: [ReviewThread]) -> Int {
            diff.files.reduce(into: 0) { total, file in
                let rows = DiffRow.rows(of: file, layout: layout, threads: threads)
                total += rows.filter { row in
                    if case .thread = row { true } else { false }
                }.count
            }
        }

        enum SceneError: Error {
            /// V diffu není řádek, na který by se dalo zakotvit vlákno.
            case noAnchors
        }
    }
}
