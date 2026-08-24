import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Pruh jede s výřezem** (#428) — a hlavně to, co se u toho má NEstát.
///
/// Scéna je ta, která je v okně: SwiftUI `ScrollView` s `LazyVStack`em bloků dvojic v okně mimo
/// obrazovku. Rolování se dělá **posunem vnějšího clip view** (`scroll(to:)` +
/// `reflectScrolledClipView`), protože přesně to je jev, na který aplikace poslouchá; syntetické
/// scroll eventy se do aplikace nedostanou vůbec (#422, #325) a událost s fází se zasekne
/// v `nextEventMatchingMask:`.
///
/// **Ověřují se čísla, ne kresba**, a je to měřením podložené rozhodnutí: legacy scroller se do
/// bitmapy z `cacheDisplay(in:to:)` nekreslí (změřeno u #428 nad červeným dokumentem — pod pruhem
/// vyjde tatáž barva jako vedle něj) a `CGWindowListCreateImage` na macOS 26 není. Kresba tedy patří
/// člověku; sem patří poloha, výška a počty průchodů.
@MainActor
@Suite("Pruh jede s výřezem (#428)")
struct DiffScrollerRideTests {
    /// Výřez z měření v zadání (`.work` při okně 723,8 b) — na něm se počítalo, kolik bloků přeteče.
    private static let viewport = 448.0
    private static let width = 700.0
    /// Tolerance na porovnání souřadnic po dvou převodech mezi soustavami.
    private static let epsilon = 0.5

    // MARK: - Kde pruh stojí

    /// **Tohle je celé #428**: dokud blok přesahuje dolní hranu výřezu, dolní hrana jeho pruhu na té
    /// hraně **stojí** — v souřadnicích okna, tedy tam, kde ji vidí člověk.
    ///
    /// Reference není `Policy.pinnedScrollerY` (tou se poloha počítá, takže by test opisoval sám
    /// sebe), ale **hranice vnějšího clip view a dolní hrana bloku**, obojí převedené do okna. Okno
    /// je nepřevrácené, takže `min(vlastní pás, hrana výřezu)` je v něm `max`:
    ///
    /// ```
    /// dolní hrana pruhu = max(hrana výřezu, dolní hrana bloku)
    /// ```
    ///
    /// Pod třemi viditelnými řádky se nešpendlí a pruh je na dolní hraně bloku, ať je kdekoli.
    @Test("Pruh stojí na hraně výřezu, dokud ho blok přesahuje")
    func theBarStandsAtTheViewportEdge() throws {
        let scene = try scene(blocks: 4, chars: 200)
        defer { scene.window.orderOut(nil) }
        var riding = 0
        var inOwnBand = 0
        var underThreeRows = 0

        for offset in stride(from: 0.0, through: 900.0, by: 30.0) {
            scroll(scene, to: offset)
            let edge = try viewportEdgeInWindow(of: scene)
            for block in try blocks(in: scene) {
                guard block.visibleHeight > 0 else { continue }
                let hangsBelow = block.blockBottomInWindow < edge - Self.epsilon
                let pins = block.visibleHeight >= 3 * block.rowHeight
                let expected = pins ? max(edge, block.blockBottomInWindow) : block.blockBottomInWindow

                #expect(
                    abs(block.barBottomInWindow - expected) < Self.epsilon,
                    """
                    posun \(offset): pruh na \(block.barBottomInWindow), čekáno \(expected) \
                    (hrana \(edge), dolní hrana bloku \(block.blockBottomInWindow), \
                    vidět \(block.visibleHeight))
                    """
                )
                // A **nikdy neopustí svůj blok** — ani nahoru, ani dolů.
                #expect(block.barInBlock, "posun \(offset): pruh vyjel z bloku (\(block.barY))")

                if !pins {
                    underThreeRows += 1
                } else if hangsBelow {
                    riding += 1
                } else {
                    inOwnBand += 1
                }
            }
        }

        // Z druhé strany: všechny tři situace se musely projet, jinak by tvrzení výš nebyla o ničem.
        // `riding` je ta, kvůli které #428 vzniklo — pruh stojí na hraně okna a blok pod ní pokračuje.
        #expect(riding > 10, "na hraně výřezu \(riding)×")
        #expect(inOwnBand > 0, "ve vlastním pásu \(inOwnBand)×")
        #expect(underThreeRows > 0, "pod třemi řádky \(underThreeRows)×")
    }

    /// Blok, který se **do šířky vejde**, pruh nemá — a nepřišpendluje se tedy nic. Autohide z #422
    /// zůstává beze změny: kdyby se skrytý scroller špendlil, sedl by v bloku bez rezervace na
    /// poslední řádek kódu a při zapnutí pruhu by to byl vlas uprostřed textu.
    @Test("Blok bez přetečení do strany pruh nemá")
    func aBlockWithoutOverflowHasNoBar() throws {
        let scene = try scene(blocks: 4, chars: 6)
        defer { scene.window.orderOut(nil) }

        for offset in stride(from: 0.0, through: 600.0, by: 60.0) {
            scroll(scene, to: offset)
            for block in try blocks(in: scene) {
                #expect(block.container.showsScroller(forWidth: Double(block.container.bounds.width)) == false)
                #expect(block.scrollers.allSatisfy { $0.pinnedScrollerY == nil }, "posun \(offset)")
                #expect(block.scrollers.allSatisfy { $0.horizontalScroller?.isHidden == true }, "posun \(offset)")
            }
        }
    }

    // MARK: - Co se nemá stát

    /// **Výška bloku se posunem nemění** — to je to, co se má NEstát: měnit ji znamená přerovnat
    /// líný seznam při každém snímku.
    ///
    /// Tvrdí se to trojmo, a jedno z těch tvrzení je ta rezervace z #422: řádky plus svislý inset
    /// plus pás **dají** výšku bloku, takže odebraná rezervace tenhle test položí (ověřeno vloženou
    /// regresí). Bez toho by „výška se nemění“ platila i o bloku, ve kterém pruh leží na kódu.
    @Test("Výška bloku se posunem nemění")
    func theBlockHeightDoesNotMoveWithTheScroll() throws {
        let scene = try scene(blocks: 4, chars: 200)
        defer { scene.window.orderOut(nil) }
        var heights: Set<Double> = []

        for offset in stride(from: 0.0, through: 900.0, by: 30.0) {
            scroll(scene, to: offset)
            for block in try blocks(in: scene) {
                let container = block.container
                let height = Double(container.frame.height)
                heights.insert(height)
                // Výška je pořád ta, o kterou si blok řekl — posun s ní nehýbe.
                #expect(height == container.height(forWidth: Double(container.bounds.width)), "posun \(offset)")
                // A pás pořád leží **pod** posledním řádkem: rezervace zůstala tam, kde ji #422
                // nechalo, a pruh si ji nevzal z kódu.
                let rows = Double(try #require(container.lineFrames().last).rect.maxY)
                #expect(rows + 2 + DiffPairScrollView.scrollerHeight == height, "posun \(offset)")
                #expect(rows <= height - DiffPairScrollView.scrollerHeight, "posun \(offset)")
            }
        }

        // Všechny bloky jsou stejné, takže přes celý průjezd smí být výška **jedna jediná**.
        #expect(heights.count == 1, "výšky bloku za průjezd: \(heights.sorted())")
    }

    /// **Rolování nepřekládá tělo** — ani tělo řádku se blokem, ani `updateNSView`, ani sazbu.
    ///
    /// Je to teď zvlášť ostré: od #421 se tělo diffu špiní i tak a 6 767 dotazů na `DiffRow.id` za
    /// sezení jde přesně touhle cestou. Připíchnutí proto nesmí přidat žádný pohon — pozorovatel je
    /// jeden na blok, obsluha je aritmetika a dva zápisy rámců, a **do observable stavu nesahá**.
    ///
    /// Rolování je krátké schválně: v tomhle pásmu do výřezu žádný další blok nevjede, takže by
    /// každé nové nasazení bylo naše.
    @Test("Rolování nepřekládá tělo, nenasazuje blok a nesází text")
    func scrollingTranslatesNoBody() throws {
        let scene = try scene(blocks: 4, chars: 200)
        defer { scene.window.orderOut(nil) }
        let containers = try blocks(in: scene).map(\.container)
        let bodies = scene.counter.bodies
        let updates = containers.map(\.updates)
        let mounts = containers.map(\.mounts)
        let typesettings = containers.map(\.typesettings)
        let before = try #require(try blocks(in: scene).first).barY

        for offset in stride(from: 10.0, through: 200.0, by: 10.0) {
            scroll(scene, to: offset)
        }

        // Měřidlo funguje: pruh se v bloku doopravdy posunul, a to o tolik, o kolik se rolovalo —
        // tedy zůstal stát na hraně okna. V bloku jde **dolů**, protože blok jde nahoru.
        let after = try #require(try blocks(in: scene).first).barY
        #expect(after - before == 200, "pruh se posunul o \(after - before), rolovalo se o 200")

        #expect(scene.counter.bodies == bodies, "průchodů tělem \(scene.counter.bodies - bodies) navíc")
        #expect(containers.map(\.updates) == updates, "aktualizace: \(containers.map(\.updates)) proti \(updates)")
        #expect(containers.map(\.mounts) == mounts, "nasazení: \(containers.map(\.mounts)) proti \(mounts)")
        #expect(containers.map(\.typesettings) == typesettings, "sazba: \(containers.map(\.typesettings))")
    }

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let hosting: NSHostingView<RidingProbe>
        let counter: DiffBlockProbeCounter
    }

    /// Jeden blok ve scéně i s tím, co se o něm dá spočítat. Souřadnice **v okně**, protože právě
    /// v nich se porovnává s hranou výřezu — z bloku samotného se „hrana okna“ poznat nedá.
    private struct BlockUnderTest {
        let container: DiffPairBlockContainer
        let scrollers: [DiffPairScrollView]
        /// Kde v bloku pruh leží (`frame.origin.y` scrolleru v ploše sloupce).
        let barY: Double
        /// Dolní hrana pruhu v souřadnicích okna.
        let barBottomInWindow: Double
        /// Dolní hrana **bloku** v souřadnicích okna — tedy tam, kde má pruh vlastní pás.
        let blockBottomInWindow: Double
        /// Kolik z bloku je vidět ve výřezu.
        let visibleHeight: Double
        let rowHeight: Double
        /// Leží pruh celý ve svém bloku?
        let barInBlock: Bool
    }

    private func scene(blocks: Int, chars: Int) throws -> Scene {
        let counter = DiffBlockProbeCounter()
        let hosting = NSHostingView(
            rootView: RidingProbe(blocks: Self.pairBlocks(blocks, chars: chars), counter: counter)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.viewport)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        let scene = Scene(window: window, hosting: hosting, counter: counter)
        try settle(scene)
        return scene
    }

    /// Nechá scénu doskládat. **Jev se stropem, ne pevný okamžik** (#269): čeká se, dokud se
    /// nepřestanou přidávat bloky a průchody tělem.
    private func settle(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        var quiet = 0
        var previous = -1
        while ContinuousClock.now < limit, quiet < 3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            scene.hosting.layoutSubtreeIfNeeded()
            let state = Self.containers(in: scene.hosting).count * 1_000 + scene.counter.bodies
            quiet = state == previous ? quiet + 1 : 0
            previous = state
        }
        if quiet < 3 {
            Issue.record(
                "Nedočkalo se: scéna se neusadila (strop \(TestWait.deadline)).",
                sourceLocation: sourceLocation
            )
        }
        guard !Self.containers(in: scene.hosting).isEmpty else {
            Issue.record("Ve scéně není ani jeden blok dvojic — tvrzení níž by byla o prázdnu.",
                         sourceLocation: sourceLocation)
            throw SceneError.empty
        }
    }

    private enum SceneError: Error { case empty }

    /// Posun vnějšího výřezu. Omezuje se **tak, jak ho omezuje AppKit** při tažení za knob
    /// (`constrainBoundsRect`), jinak by šlo odrolovat za dokument a test by tvrdil něco o poloze,
    /// do které se okno nedostane.
    private func scroll(_ scene: Scene, to offset: Double) {
        guard let outer = Self.outerScrollView(in: scene.hosting) else { return }
        let clip = outer.contentView
        let target = NSRect(origin: NSPoint(x: 0, y: offset), size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(target).origin)
        outer.reflectScrolledClipView(clip)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    /// Dolní hrana výřezu v souřadnicích okna. Okno je **nepřevrácené**, takže dolní hrana je
    /// `minY` — a to je ta souřadnice, na které má stát pruh.
    private func viewportEdgeInWindow(of scene: Scene) throws -> Double {
        let outer = try #require(Self.outerScrollView(in: scene.hosting))
        let clip = outer.contentView
        return Double(clip.convert(clip.bounds, to: nil).minY)
    }

    private func blocks(in scene: Scene) throws -> [BlockUnderTest] {
        let outer = try #require(Self.outerScrollView(in: scene.hosting))
        let clip = outer.contentView
        return try Self.containers(in: scene.hosting).map { container in
            let scrollers = container.subviews.compactMap { $0 as? DiffPairScrollView }
                .sorted { $0.frame.minX < $1.frame.minX }
            let left = try #require(scrollers.first, "blok bez rolovací plochy")
            let scroller = try #require(left.horizontalScroller, "plocha bez scrolleru")
            let visible = clip.bounds.intersection(container.convert(container.bounds, to: clip))
            let bar = left.convert(scroller.frame, to: nil)
            return BlockUnderTest(
                container: container,
                scrollers: scrollers,
                barY: Double(scroller.frame.origin.y),
                barBottomInWindow: Double(bar.minY),
                blockBottomInWindow: Double(container.convert(container.bounds, to: nil).minY),
                visibleHeight: Double(visible.isNull ? 0 : visible.height),
                rowHeight: Double(try #require(container.lineFrames().first).rect.height),
                barInBlock: scroller.frame.minY >= 0 && scroller.frame.maxY <= container.bounds.height
            )
        }
    }

    private static func pairBlocks(_ count: Int, chars: Int) -> [DiffPairBlock] {
        let side: [DiffLine?] = (0..<40).map {
            DiffLine(
                kind: .context,
                oldNumber: $0 + 1,
                newNumber: $0 + 1,
                text: String(repeating: "x", count: chars)
            )
        }
        return (0..<count).map { _ in DiffPairBlock(left: side, right: side) }
    }

    /// Rolovací plocha **ze SwiftUI** (`HostingScrollView`), ne plochy sloupců uvnitř bloku.
    private static func outerScrollView(in view: NSView) -> NSScrollView? {
        if view is DiffPairScrollView { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { outerScrollView(in: $0) }.first
    }

    private static func containers(in view: NSView) -> [DiffPairBlockContainer] {
        if let container = view as? DiffPairBlockContainer { return [container] }
        return view.subviews.flatMap { containers(in: $0) }
    }
}

/// Bloky dvojic v rolovací ploše — tak, jak jsou v okně (`DiffPairBlockRowView` v `LazyVStack`u
/// uvnitř `ScrollView`u). S nahým `DiffPairBlockView` by scéna neměla vnější clip view, tedy zrovna
/// to, na čem celé #428 stojí.
struct RidingProbe: View {
    let blocks: [DiffPairBlock]
    let counter: DiffBlockProbeCounter

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(blocks.indices, id: \.self) { index in
                    RidingRow(block: blocks[index], counter: counter)
                }
            }
        }
        .frame(width: 700, height: 448)
    }
}

/// Jeden řádek scény. Průchody tělem se počítají **tady**, ne u celé plochy: kdyby se rolováním
/// překládalo tělo bloku, počítadlo je právě to, co se zvedne.
struct RidingRow: View {
    let block: DiffPairBlock
    let counter: DiffBlockProbeCounter

    var body: some View {
        let _ = counter.note()
        DiffPairBlockRowView(block: block, language: Language(path: "Cart.swift"))
    }
}
