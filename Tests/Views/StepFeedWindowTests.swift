import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Výška okna výpisu kroků proti tomu, co výpis doopravdy nakreslí (#325, připomínka z proklikání
/// #402).
///
/// Okno je **obsah do stropu**, a spočítat se to dá jedině tehdy, když je výška řádku známá dřív,
/// než se nakreslí (`Policy.stepFeedWindow` nad `StepFeedView.metrics`). Tím vzniká přesně ta třída
/// chyby, kterou popisuje #236 — **měřeno jinde, než se kreslí** —, jen o výšku: kdyby se rozměry
/// v `metrics` rozešly se sazbou, okno by obsah o řádek přerostlo (a bylo by v něm zase prázdno),
/// nebo by ho o řádek ořezalo (a poslední krok by nebyl vidět, aniž by šlo rolovat).
///
/// Referencí je proto **hostovaná hierarchie**, ne druhý výpočet. Rozměry se ověřují rozdíly:
/// `metrics.row` jako přírůstek na jeden řádek, `metrics.cut` jako přírůstek řezu a celý vzorec
/// tím, že u nerolovaného výpisu je **okno stejně vysoké jako obsah**. Vlastní kopie aritmetiky
/// v testu by hlídala sebe samu.
///
/// Kmitání na hranici stropu a schovaný přepínač `Sledovat konec` se testují jako čistá funkce
/// (`StepFeedTests`) — tady se ověřuje, že čísla, kterými ta funkce počítá, odpovídají kresbě.
@MainActor
@Suite("Výška okna výpisu kroků")
struct StepFeedWindowTests {
    private let worktree = URL(filePath: "/tmp/cache/worktrees/keboola/job-queue/725-c66a21")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Šířky, na kterých tab `Průběh` doopravdy stojí: přes celé okno a v úzkém panelu. **Pásmo,
    /// ne jedna** (#236) — výška řádku na šířce záležet nesmí, a rozejde se to jedině v pásmu.
    private let widths = [1000.0, 620.0, 420.0]

    // MARK: - Řádek

    /// Výška řádku je **jedno číslo pro všechny druhy**: kdyby odznak `ODMÍTNUTO` (pilulka
    /// s pozadím) nebo řádek se zadáním, které nedorazilo celé, vyrostl o bod, počítalo by se okno
    /// z čísla, které pro půlku výpisu neplatí.
    @Test("Řádek kroku má výšku z metrik, ve všech druzích a na každé šířce")
    func everyRowKindHasTheDeclaredHeight() throws {
        for entry in try allRowKinds() {
            for width in widths {
                let measured = height(
                    of: TimelineEntryRow(entry: entry, worktree: worktree, isNewest: false),
                    width: width
                )

                #expect(
                    measured == TimelineEntryRow.height,
                    "\(entry.kind) na šířce \(width) měří \(measured)"
                )
            }
        }
    }

    /// Nejnovější řádek se podbarvuje — podbarvení výšku měnit nesmí, jinak by okno poskočilo
    /// pokaždé, když se zvýraznění přesune o řádek dolů.
    @Test("Podbarvený nejnovější řádek je stejně vysoký")
    func theNewestRowIsNotTaller() throws {
        let entry = try #require(try allRowKinds().last)
        let plain = height(of: TimelineEntryRow(entry: entry, worktree: worktree, isNewest: false))
        let newest = height(of: TimelineEntryRow(entry: entry, worktree: worktree, isNewest: true))

        #expect(newest == plain)
        #expect(newest == TimelineEntryRow.height)
    }

    // MARK: - Okno

    /// **Připomínka z proklikání**: krátký běh nesmí nakreslit okno se dvěma třetinami prázdna.
    /// Tvrdí se to tím nejsilnějším způsobem, jaký na to je — okno je vysoké **přesně** jako obsah,
    /// takže v něm prázdno není vůbec a zároveň se tím ověřuje celý vzorec i s odsazením.
    @Test("Krátký běh: okno je vysoké jako obsah")
    func aShortFeedFitsItsContent() throws {
        for width in widths {
            let scene = try Scene(rows: 3, dropped: 0, width: width)
            let expected = Policy.stepFeedWindow(rows: 3, cut: false, metrics: StepFeedView.metrics)

            #expect(expected.height < StepFeedView.metrics.cap)
            #expect(scene.windowHeight == expected.height, "na šířce \(width)")
            #expect(scene.contentHeight == expected.height, "na šířce \(width)")
            // A doopravdy není kam rolovat — jinak by ten schovaný přepínač někdo potřeboval.
            #expect(!expected.scrolls)
            #expect(scene.contentHeight <= scene.visibleHeight)
        }
    }

    /// Přírůstek na jeden řádek — tím se ověřuje `metrics.row` proti sazbě, ne proti sobě.
    @Test("Řádek navíc zvedne obsah o výšku řádku")
    func oneMoreRowAddsOneRowHeight() throws {
        let three = try Scene(rows: 3, dropped: 0, width: 620)
        let four = try Scene(rows: 4, dropped: 0, width: 620)

        #expect(four.contentHeight - three.contentHeight == StepFeedView.metrics.row)
        #expect(four.windowHeight - three.windowHeight == StepFeedView.metrics.row)
    }

    /// Totéž pro řez na začátku ořezané osy. Kreslí se jen tehdy, když se něco nevešlo, takže se
    /// do výšky počítá podmíněně — a když se ta podmínka rozejde s kresbou, je okno o 21 bodů vedle.
    @Test("Řez na začátku zvedne obsah o svou výšku")
    func theCutRowAddsItsHeight() throws {
        let plain = try Scene(rows: 3, dropped: 0, width: 620)
        let cut = try Scene(rows: 3, dropped: 42, width: 620)

        #expect(cut.contentHeight - plain.contentHeight == StepFeedView.metrics.cut)
        #expect(cut.windowHeight - plain.windowHeight == StepFeedView.metrics.cut)
    }

    /// Dlouhý běh se chová jako do #402: strop a rolování. To je ta polovina, která se **nemá**
    /// změnit — rostoucí okno u tří stovek kroků by přerovnávalo tab několikrát za vteřinu.
    @Test("Dlouhý běh: okno stojí na stropu a roluje se")
    func aLongFeedStopsAtTheCap() throws {
        let scene = try Scene(rows: 120, dropped: 0, width: 620)

        #expect(scene.windowHeight == StepFeedView.metrics.cap)
        #expect(scene.contentHeight > scene.visibleHeight)
        #expect(Policy.stepFeedWindow(rows: 120, cut: false, metrics: StepFeedView.metrics).scrolls)
    }

    /// **Strop není celý počet řádků, a je to schválně** (návrh, sekce 20): hrana okna řádek
    /// usekne, takže je z výpisu poznat, že se scrolluje. Kdyby strop na řádky vyšel přesně,
    /// vypadal by rolovatelný výpis jako celý.
    @Test("Strop usekne řádek hranou")
    func theCapCutsARowInHalf() {
        let metrics = StepFeedView.metrics
        let rows = (metrics.cap - 2 * metrics.inset) / metrics.row

        #expect(rows > 8)
        #expect(rows < 9)
    }

    /// Výška hostovaného řádku, **přečtená jednou a do `Double`**.
    ///
    /// Obojí je podmínka, ne úklid: `fittingSize` přímo v `#expect` dalo tvrzení, které padalo nad
    /// dvěma stejnými patnáctkami (`bits` shodné na bit), protože se v makru čte dvakrát a `CGFloat`
    /// se u toho převádí. Hodnota se proto bere do proměnné, jako u #367 — tvrzení se pak porovnávají
    /// mezi sebou, ne každé proti jinému čtení měřidla.
    private func height(of row: TimelineEntryRow, width: Double = 620) -> Double {
        Double(NSHostingView(rootView: row.frame(width: width)).fittingSize.height)
    }

    // MARK: - Scéna

    /// Hostovaný výpis: okno mimo obrazovku, rozvržené, a z něj `NSScrollView`.
    ///
    /// **Drží si okno**, protože bez něj se hierarchie nerozvrhne — a poloha ani rozměry scrollu by
    /// pak byly nuly, tedy čísla, která projdou skoro čímkoli.
    @MainActor
    private final class Scene {
        private let window: NSWindow
        private let scroll: NSScrollView

        init(rows: Int, dropped: Int, width: Double) throws {
            // Styl scrollerů se nechává usadit napřed (#343): legacy scroller místo doopravdy
            // zabírá, takže by se okno mohlo přerovnat uprostřed měření.
            TestWait.awaitSettledScrollerStyle()
            let hosting = NSHostingView(
                rootView: StepFeedView(
                    lane: Scene.lane(rows: rows, dropped: dropped),
                    state: .expanded,
                    toggle: {}
                )
                .frame(width: width)
            )
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: 400)
            window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            // Mimo obrazovku, ať test nikomu neskočí před oči.
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontUnanimated()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            scroll = try #require(Scene.scrollView(in: hosting), "výpis nemá scroll")
        }

        deinit { window.orderOut(nil) }

        /// Výška okna výpisu — tedy to, co se z tabu ukrojí.
        var windowHeight: Double { Double(scroll.frame.height) }

        /// Výška obsahu, jak vyšla ze sazby.
        var contentHeight: Double { Double(scroll.documentView?.frame.height ?? 0) }

        /// Kolik z obsahu je vidět. U nerolovaného výpisu se musí vejít celý.
        var visibleHeight: Double { Double(scroll.contentView.bounds.height) }

        private static func lane(rows: Int, dropped: Int) -> ReviewerLane {
            var timeline = ReviewerTimeline(
                skill: "code-review",
                worktree: URL(filePath: "/tmp/cache/worktrees/keboola/job-queue/725-c66a21")
            )
            let start = Date(timeIntervalSince1970: 1_000_000)
            for index in 0..<rows {
                timeline.record(
                    .attemptedTool(ToolAttempt(name: "Read", detail: "src/Job\(index).php", id: "t\(index)")),
                    at: start + Double(index)
                )
            }
            let lane = Policy.lanes(of: [timeline], skills: ["code-review"], running: ["code-review"])[0]
            guard dropped > 0 else { return lane }
            // Ořezaná osa **bez tří stovek kroků**: zajímá nás řádek s řezem, ne strop. Skládá se
            // proto rovnou dráha — `droppedEntries` je pole modelu, ne odvozená hodnota.
            return ReviewerLane(
                skill: lane.skill,
                state: lane.state,
                phases: lane.phases,
                lastTool: lane.lastTool,
                finishedAt: lane.finishedAt,
                reportedFindings: lane.reportedFindings,
                usage: lane.usage,
                sessionID: lane.sessionID,
                worktree: lane.worktree,
                droppedEntries: dropped,
                loadedSkill: lane.loadedSkill,
                intentGap: lane.intentGap,
                entries: lane.entries,
                isConfigured: lane.isConfigured
            )
        }

        private static func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for subview in view.subviews {
                if let found = scrollView(in: subview) { return found }
            }
            return nil
        }
    }

    /// Řádek každého druhu, jaký výpis kreslí — a **se všemi symboly**, tedy včetně neznámého
    /// nástroje (`wrench…`, nejvyšší z nástrojových) a obou konců běhu. Skládá se z **osy**, ne
    /// ručně, aby to byly tytéž události, jaké chodí ze streamu.
    ///
    /// Symboly jsou tady to podstatné: výšku řádku určuje ten nejvyšší prvek, takže výčet, ve
    /// kterém by chyběl `doc.badge.ellipsis` (zadání není celé) nebo `wrench…`, by tvrzení o jedné
    /// výšce potvrdil i nad řádky, které měří o dva body víc.
    private func allRowKinds() throws -> [ReviewerTimeline.Entry] {
        // `Skill` zůstane bez odpovědi (`běží…`) a je to zároveň ten **neznámý** nástroj;
        // `Bash` se odmítne (pilulka `ODMÍTNUTO`), zbytek dostane trvání.
        let tools = ["Read", "Grep", "Glob", "ReportFindings", "Bash", "Skill"]
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        timeline.record(.queued, at: start)
        timeline.record(.started(sessionID: "8c1f2ab3"), at: start + 1)
        for (index, tool) in tools.enumerated() {
            let id = "t\(index)"
            let at = start + 2 + Double(index) * 2
            timeline.record(.attemptedTool(ToolAttempt(name: tool, detail: "src/Job.php", id: id)), at: at)
            guard tool != "Skill" else { continue }
            let kind: ToolAttempt.Outcome.Kind = tool == "Bash" ? .denied : .passed
            timeline.record(
                .resolvedTool(ToolResolution(id: id, outcome: .init(kind: kind, reason: "denied"))),
                at: at + 1
            )
        }
        timeline.record(.intentGap(.toolNotConfigured), at: start + 30)
        timeline.record(.findings(count: 2), at: start + 31)
        timeline.finish(.finished, usage: nil, at: start + 32)
        // Druhý konec běhu má vlastní symbol (`exclamationmark.triangle`), a osa smí skončit jen
        // jednou — proto druhá.
        var timedOut = ReviewerTimeline(skill: "code-review", worktree: worktree)
        timedOut.finish(.timedOut, usage: nil, at: start + 33)

        // Nástroje a k nim `queued`, `started`, `intentGap`, `findings` a **dva** konce běhu.
        let entries = timeline.entries + timedOut.entries
        #expect(
            entries.count == tools.count + 6,
            "osa nemá všechny druhy řádku: \(entries.map(\.kind))"
        )
        return entries
    }
}
