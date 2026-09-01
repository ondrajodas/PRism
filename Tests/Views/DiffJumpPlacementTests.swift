import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Kde po skoku skončí cílový řádek** (#152, připomínka z proklikání).
///
/// Scéna je ta, která je v okně: skutečný `DiffView` v okně mimo obrazovku, kotva složená tou
/// samou cestou jako v aplikaci (`DiffSearch.hits` → `DiffRow.anchor(in:hit:)`) a posun nechaný
/// na `ScrollViewReader`u. Měří se **poloha řádku v souřadnicích okna**, protože právě v nich ho
/// vidí člověk — z `id`, na které se skočilo, se o tom nedozvíš nic.
///
/// **Čeká se odmlkami, ne točením runloopu** (#296, a tady to má druhý důvod): posun se nastavuje
/// o průchod později, tedy přes `await Task.yield()` v `DiffView`. `RunLoop.current.run(until:)`
/// hlavní aktor vyhladoví, takže se ten yield **nikdy nedočká pokračování** — první verze téhle
/// sondy tím pádem měřila neodscrollované okno a vypadala u toho hodnověrně (posun 0 u každého
/// cíle). Jev, na který se čeká, je **spotřebovaný cíl**: `DiffView` po druhém posunu nastaví
/// `scrollTarget` na `nil`.
@MainActor
@Suite("Kam skočí výskyt hledání (#152)", .serialized)
struct DiffJumpPlacementTests {
    private static let width = 1200.0
    private static let height = 800.0
    /// Kolik řádků má hunk. Přes tři stropy `DiffBlock.maxLines`, takže se měří i řádek hluboko
    /// v bloku — a to je ten případ, který se rozbíjí.
    private static let lines = 200

    // MARK: - Tvrzení

    /// **Tohle je celá připomínka**: skočí se, ale výskyt nemusí být vidět. Cíl je od #157 **blok**
    /// (nese `id` jen prvního řádku) a podíl výšky z `scrollTo(anchor:)` platí pro blok, ne pro
    /// řádek v něm — v bloku o šedesáti řádcích je to až tisíc bodů rozdílu.
    ///
    /// Naměřeno před opravou (okno 1 200 × 800, výřez 762 pt): řádek 52 skončil 889 pt pod hranou
    /// výřezu, řádek 195 dokonce 2 181 pt.
    @Test("Výskyt po skoku leží ve výřezu, ať je v bloku kdekoli")
    func theHitLandsInTheViewport() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        try await ready(scene)
        // Krok 13 je prvočíslo, takže se zkoušené pozice nesejdou s hranicemi bloků (60) —
        // jinak by test měřil pořád tentýž případ.
        for index in stride(from: 0, to: Self.lines, by: 13) {
            let spot = try await jump(scene, to: index)
            #expect(
                spot.isVisible,
                "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany výřezu, tedy mimo"
            )
        }
    }

    /// A leží **tam, kde to řekla `Policy`** — ne na hraně výřezu. Tvrzení je o tom, že se rozhodnutí
    /// o výšce do okna doopravdy dostane: `scrollTo` umí jen podíl výšky, takže mezi „devadesát bodů
    /// nad cílem“ a kresbou je přepočet, ve kterém se dá ztratit.
    ///
    /// **Měří se odstup pro `.bubble`, ne pro `.searchHit`**, a je to mez sondy, ne volba: cíl se sem
    /// nastavuje bindingem, tedy tou cestou, kterou jde panel nálezů, a `.searchHit` si `DiffView`
    /// nastavuje sám v `step(search:)` — z testu se ta cesta nedá vyvolat (spouští ji tlačítko
    /// v pruhu). Že je odstup u výskytu jiný, tvrdí `DiffJumpAnchorTests` nad čistou funkcí;
    /// že se přepne, ověří člověk na běžící aplikaci.
    @Test("Nad cílem zůstane kontext, ne hrana výřezu")
    func contextStaysAboveTheTarget() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        try await ready(scene)
        var measured = 0
        for index in stride(from: 26, to: Self.lines, by: 37) {
            let spot = try await jump(scene, to: index)
            // U kraje dokumentu se dál posunout nedá, takže tam odstup vyjít nemůže — a tvrdit ho
            // by znamenalo tvrdit něco o mezi dokumentu (viz `isFreeOfEdges`).
            guard spot.isFreeOfEdges else { continue }
            let wanted = try #require(Policy.jumpOffset(of: .bubble, viewport: spot.viewport))
            measured += 1
            #expect(
                abs(spot.fromViewportTop - wanted) <= Self.tolerance,
                "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany, čekáno \(Int(wanted))"
            )
        }
        // Bez tohohle by test prošel i tehdy, kdyby všechny skoky skončily u kraje a neměřilo se nic.
        #expect(measured >= 2, "změřily se jen \(measured) skoky mimo kraje dokumentu")
    }

    /// Tolerance na dva převody mezi soustavami a na výšku řádku, o kterou se cíl smí lišit —
    /// naměřený rozptyl je do dvou bodů, tolerance je proti zaokrouhlení sazby.
    private static let tolerance = 28.0

    // MARK: - Sonda

    /// **Jak to po skoku vypadá** — sonda, ne test: bez `PRISM_RENDER_DIR` nedělá nic.
    ///
    /// Čísla z tvrzení výš říkají, kolik bodů nad cílem zůstalo; obrázek říká, jestli to nad ním
    /// vypadá jako kontext. Kreslí se z okna mimo obrazovku (`cacheDisplay`), protože blok kódu je
    /// AppKitové view a `ImageRenderer` na něj nedosáhne — tatáž konstrukce jako
    /// `DiffWindowRenderProbe`.
    ///
    /// ```bash
    /// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
    ///     xcodebuild … test -only-testing:PRismTests/DiffJumpPlacementTests
    /// ```
    @Test("Sonda — jak okno po skoku vypadá",
          .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil))
    func drawTheLanding() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        try await ready(scene)
        // Blízký skok (druhý řádek prvního bloku) a dva daleké — hluboko v bloku a v posledním
        // bloku souboru. Právě ty dva daleké byly před opravou mimo obrazovku.
        for index in [1, 52, 137] {
            let spot = try await jump(scene, to: index)
            Self.write(
                scene.hosting,
                to: URL(filePath: directory).appending(path: "skok-radek-\(index).png")
            )
            print(String(
                format: "SONDA řádek %3d: %.0f pt od hrany výřezu, vidět: %@",
                index,
                spot.fromViewportTop,
                spot.isVisible ? "ano" : "NE"
            ))
        }
    }

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

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let hosting: NSHostingView<JumpProbe>
        let target: JumpTarget
        let diff: Diff
    }

    /// Kde cílový řádek po skoku leží. Souřadnice **v okně**, protože v nich se porovnává s hranou
    /// výřezu — z bloku samotného se „hrana okna“ poznat nedá.
    private struct Spot {
        /// Kolik bodů je horní hrana řádku pod horní hranou výřezu. Negativní = nad ní, tedy mimo.
        let fromViewportTop: Double
        let isVisible: Bool
        /// Výška výřezu, **změřená**, ne z výšky okna: nad diffem je lišta a případně pruh hledání.
        let viewport: Double
        /// Je posun **daleko od obou krajů dokumentu**? U kraje se dál odscrollovat nedá, takže cíl
        /// leží jinde, než kam se mířilo — a tvrdit o té poloze číslo by znamenalo tvrdit něco
        /// o mezi dokumentu, ne o kotvě.
        let isFreeOfEdges: Bool
    }

    private func scene() throws -> Scene {
        let diff = DiffParser.parse(Self.material())
        let target = JumpTarget()
        let hosting = NSHostingView(rootView: JumpProbe(diff: diff, target: target))
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        return Scene(window: window, hosting: hosting, target: target, diff: diff)
    }

    /// Nechá diff rozvrhnout. Jev je **obsah vyšší než výřez** — do té doby není kam skákat
    /// a měření by vyšlo „všechno je vidět“.
    private func ready(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        await waitUntil("diff se rozvrhne", sourceLocation: sourceLocation) {
            guard let scroller = Self.diffScroller(in: scene.hosting) else { return false }
            let content = scroller.documentView?.frame.height ?? 0
            return scroller.contentSize.height > 0 && content > scroller.contentSize.height
        }
    }

    /// Skočí na výskyt na daném řádku a vrátí, kde ten řádek v okně skončil.
    ///
    /// Kotva se skládá **tou samou cestou jako v aplikaci**, ať test neopisuje sám sebe: výskyty
    /// z `DiffSearch`, kotva z `DiffRow.anchor(in:hit:)`.
    private func jump(
        _ scene: Scene,
        to index: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Spot {
        let file = try #require(scene.diff.files.first, sourceLocation: sourceLocation)
        let hits = DiffSearch.hits(in: file, query: DiffSearchQuery(text: Self.needle))
        let hit = try #require(
            hits.first { $0.line.newNumber == index + 1 },
            "na řádku \(index) není výskyt",
            sourceLocation: sourceLocation
        )
        // **Před každým skokem se výřez vrátí na začátek** — posunem vnějšího clip view, tedy tím
        // jevem, na který aplikace poslouchá (tentýž postup jako `DiffScrollerRideTests`). Bez toho
        // by každý skok začínal tam, kde skončil ten předchozí, a měřilo by se pořád něco jiného;
        // navíc je skok „odjinud“ zrovna ten případ z připomínky.
        try await reset(scene, sourceLocation: sourceLocation)
        scene.target.anchor = DiffRow.anchor(in: scene.diff, hit: hit)
        // Cíl si `DiffView` po druhém posunu spotřebuje (`scrollTarget = nil`) — a je to jediný
        // jev, ze kterého se pozná, že skok doběhl celý, ne jen do prvního posunu.
        await waitUntil("skok se spotřebuje", sourceLocation: sourceLocation) {
            scene.target.anchor == nil
        }
        // **Nasazení bloku je vlastní jev** (#469): `NSTextView` má blok jen v pásu kolem výřezu,
        // takže po skoku se cílový blok nasadí až o průchod později — a bez čekání by se měřilo
        // „blok tu není“ i tehdy, když skok dopadl správně.
        await waitUntil("blok s cílovým řádkem se nasadí", sourceLocation: sourceLocation) {
            Self.textViews(in: scene.hosting).contains { $0.lines.contains(hit.line) }
        }
        await settled(scene, sourceLocation: sourceLocation)

        let scroller = try #require(Self.diffScroller(in: scene.hosting), sourceLocation: sourceLocation)
        let text = try #require(
            Self.textViews(in: scene.hosting).first { $0.lines.contains(hit.line) },
            "blok s cílovým řádkem není v okně nasazený",
            sourceLocation: sourceLocation
        )
        let row = try #require(text.lines.firstIndex(of: hit.line), sourceLocation: sourceLocation)
        let rect = try #require(text.frame(ofLine: row), sourceLocation: sourceLocation)

        let clip = scroller.contentView
        let inWindow = text.convert(rect, to: nil)
        let viewport = clip.convert(clip.bounds, to: nil)
        let offset = scroller.documentVisibleRect.origin.y
        let last = (scroller.documentView?.frame.height ?? 0) - scroller.contentSize.height
        // Okno je **nepřevrácené**, takže horní hrana je `maxY`.
        return Spot(
            fromViewportTop: Double(viewport.maxY - inWindow.maxY),
            isVisible: inWindow.minY >= viewport.minY && inWindow.maxY <= viewport.maxY,
            viewport: Double(viewport.height),
            isFreeOfEdges: offset > 1 && offset < last - 1
        )
    }

    /// Vrátí výřez na začátek dokumentu.
    private func reset(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let scroller = try #require(Self.diffScroller(in: scene.hosting), sourceLocation: sourceLocation)
        scroller.contentView.scroll(to: .zero)
        scroller.reflectScrolledClipView(scroller.contentView)
        await waitUntil("výřez se vrátí na začátek", sourceLocation: sourceLocation) {
            (Self.diffScroller(in: scene.hosting)?.documentVisibleRect.origin.y ?? -1) < 1
        }
    }

    /// Nechá posun dojet. **Animovaný posun se čte teprve, když stojí** — jinak by číslo záviselo
    /// na tom, kdy se test podíval.
    private func settled(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) async {
        var previous = -1.0
        await waitUntil("posun výřezu se ustálí", sourceLocation: sourceLocation) {
            let now = Self.diffScroller(in: scene.hosting)?.documentVisibleRect.origin.y ?? 0
            defer { previous = now }
            return abs(now - previous) < 0.5
        }
    }

    // MARK: - Materiál

    private static let needle = "NEEDLE"

    /// Diff o jednom souboru a jednom hunku, ve kterém má **každý řádek jeden výskyt**. Řádky jsou
    /// krátké schválně: na šířce 1 200 pt se nezalomí, takže je poloha řádku v bloku spočitatelná
    /// a měření se dá přečíst.
    private static func material() -> String {
        var out = "diff --git a/src/Handler.swift b/src/Handler.swift\n"
        out += "index 1111111..2222222 100644\n"
        out += "--- a/src/Handler.swift\n"
        out += "+++ b/src/Handler.swift\n"
        out += "@@ -1,\(lines) +1,\(lines) @@ func handle()\n"
        for line in 0..<lines {
            out += "     let value = compute(\(needle), \(line))\n"
        }
        return out
    }

    // MARK: - Hledání v hierarchii

    private static func textViews(in view: NSView) -> [DiffTextView] {
        (view as? DiffTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
    }

    /// Výřez diffu. **Ne první `NSScrollView` shora, ale ten s nejvyšším dokumentem**: první shora
    /// je lišta (dokument 46 pt) a měření proti ní vydá „nescrollovalo se“ u každého cíle — tedy
    /// tutéž hodnotu pro funguje i nefunguje (#478).
    private static func diffScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = diffScroller(in: child) else { continue }
            if (found.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) {
                best = found
            }
        }
        return best
    }
}

/// Kam se skáče. Třída, aby se z testu dal cíl přepsat, aniž by se scéna stavěla znovu.
@MainActor @Observable final class JumpTarget {
    var anchor: String?
}

/// Scéna: skutečný `DiffView`, jen s kotvou taženou z testu.
struct JumpProbe: View {
    let diff: Diff
    let target: JumpTarget

    var body: some View {
        // **Cíl se čte v těle, ne uvnitř closure bindingu.** Čtení observable vlastnosti v closure
        // se do závislostí těla nezapíše, takže se tělo po přepsání cíle nepřeloží a `task(id:)`
        // novou hodnotu nikdy neuvidí — sonda pak měří nescrollované okno a vypadá u toho zeleně.
        let anchor = target.anchor
        return DiffView(
            diff: diff,
            subject: "probe/jump#1",
            scrollTarget: Binding(get: { anchor }, set: { target.anchor = $0 }),
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
            layout: .constant(.unified)
        )
    }
}
