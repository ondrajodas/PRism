import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Zkoušené řádky — **každý ve vlastní scéně, jeden skok na scénu**, a není to plýtvání:
/// při skocích vypálených hned po sobě jeden z desítky **neudělá nic** (změřeno u #152, různé
/// cíle v různých bězích; poloha po skoku, který proběhl, přitom sedí na dva body). Jestli se to
/// projeví i v lidském tempu, řekne jedině proklikání — v harnessu se to obejít **nedá**, ale
/// zamlčet taky ne, takže je to zapsaná mezera v `docs/testovani.md`.
///
/// Pozice jsou vybrané tak, aby v bloku o šedesáti řádcích ležely různě (těsně za hranicí,
/// uprostřed, u konce) — právě o polohu v bloku tady jde.
private let diffJumpSweep: [Int] = [5, 25, 45, 58, 70, 110, 135, 155, 175, 190]

/// **Kde po skoku skončí cílový řádek** (#152, dvě kola proklikání).
///
/// Scéna je ta, která je v okně: skutečný `DiffView` v okně mimo obrazovku, kotva složená tou
/// samou cestou jako v aplikaci (`DiffSearch.hits` → `DiffRow.anchor(in:hit:)`) a posun nechaný
/// na `ScrollViewReader`u. Měří se **poloha řádku v souřadnicích okna**, protože právě v nich ho
/// vidí člověk — z `id`, na které se skočilo, se o tom nedozvíš nic. Odsud jsou čísla, kterými je
/// #152 podložené: řádek 52 skončil **889 pt** pod hranou výřezu, řádek 195 **2 181 pt**, v souboru
/// se zalomenými řádky dokonce **6 017 pt nad** výřezem — a ve split pohledu ležel výskyt na x 2 708,
/// zatímco sloupec ukazoval 0–582. Po opravě sedí svislá poloha **na dva body** a výskyt je vidět.
///
/// **Jedno kolo byla tahle suita sonda**, protože jeden skok z desítky nezabral vůbec a jako test by
/// dělal falešně červený `main`. Příčina se pak našla — **animovaný posun, který o průchod později
/// uťal ten druhý** — a od té doby je měření deterministické; postup a čísla jsou
/// v `docs/testovani.md`.
///
/// **Čeká se odmlkami, ne točením runloopu** (#296, a tady to má druhý důvod): posun se nastavuje
/// o průchod později, tedy přes `await Task.yield()` v `DiffView`. `RunLoop.current.run(until:)`
/// hlavní aktor vyhladoví, takže se ten yield **nikdy nedočká pokračování** — první verze téhle
/// scény tím pádem měřila neodscrollované okno a vypadala u toho hodnověrně (posun 0 u každého
/// cíle). Jev, na který se čeká, je **spotřebovaný cíl**: `DiffView` po skoku nastaví `scrollTarget`
/// na `nil`.
@MainActor
@Suite("Kam skočí cíl v diffu (#152)", .serialized)
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
    @Test("Výskyt po skoku leží ve výřezu, ať je v bloku kdekoli", arguments: diffJumpSweep)
    func theHitLandsInTheViewport(index: Int) async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        await ready(scene)
        let spot = try await jump(scene, to: index)
        #expect(
            spot.isVisible,
            "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany výřezu, tedy mimo"
        )
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
    @Test("Nad cílem zůstane kontext, ne hrana výřezu", arguments: [26, 45, 100, 137])
    func contextStaysAboveTheTarget(index: Int) async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        await ready(scene)
        let spot = try await jump(scene, to: index)
        // U kraje dokumentu se dál posunout nedá, takže tam odstup vyjít nemůže — proto jsou
        // zkoušené řádky vybrané tak, aby u kraje neležely; kdyby se to změnilo, řekne to tohle
        // tvrzení, ne tichý průchod (viz `isFreeOfEdges`).
        #expect(spot.isFreeOfEdges, "řádek \(index) skončil u kraje dokumentu, odstup tam neplatí")
        let wanted = try #require(Policy.jumpOffset(of: .bubble, viewport: spot.viewport))
        #expect(
            abs(spot.fromViewportTop - wanted) <= Self.tolerance,
            "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany, čekáno \(Int(wanted))"
        )
    }


    /// Tolerance na dva převody mezi soustavami a na výšku řádku, o kterou se cíl smí lišit —
    /// naměřený rozptyl je do dvou bodů, tolerance je proti zaokrouhlení sazby.
    private static let tolerance = 28.0

    // MARK: - Zalomené řádky

    /// **Kam skočí cíl v souboru s dlouhými řádky** — v pohledu pod sebou se totiž **zalamuje**
    /// (`DiffTextView.wrappingBlock`), takže řádek je vysoký víc než jeden řádek sazby a odhad výšky
    /// bloku z `rows × výška řádku` je podstřelený.
    /// **Zalomené řádky jsou to, co u #152 mělo druhé kolo** (proklikání: „někdy se špatně scrolluje
    /// na výšku"). V pohledu pod sebou se zalamuje, takže blok o dlouhých řádcích je násobně vyšší,
    /// než kolik má řádků — a dokud se výška **odhadovala**, skončil cíl daleko mimo obrazovku.
    ///
    /// Naměřeno před opravou: řádky 25, 45 a 58 skončily **2 054, 4 456 a 6 017 pt nad** výřezem
    /// (tedy o obrazovku až osm výš); po ní **90 pt** u všech, tedy přesně tam, kam se mířilo.
    @Test("Cíl se trefí i v souboru s dlouhými (zalomenými) řádky", arguments: [5, 25, 45, 58])
    func theWrappedHitLandsAtTheOffset(index: Int) async throws {
        let scene = try scene(material: Self.wrappedMaterial())
        defer { scene.window.orderOut(nil) }
        await ready(scene)
        let spot = try await jump(scene, to: index)
        #expect(spot.isVisible, "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany, tedy mimo")
        guard spot.isFreeOfEdges else { return }
        let wanted = try #require(Policy.jumpOffset(of: .bubble, viewport: spot.viewport))
        #expect(
            abs(spot.fromViewportTop - wanted) <= Self.tolerance,
            "řádek \(index) skončil \(Int(spot.fromViewportTop)) pt od hrany, čekáno \(Int(wanted))"
        )
    }

    /// Diff, jehož každý řádek je **delší, než se vejde do šířky** — v pohledu pod sebou se tedy
    /// zalomí na dva až tři vizuální řádky.
    private static func wrappedMaterial() -> String {
        var out = "diff --git a/src/Wide.swift b/src/Wide.swift\n"
        out += "index 1111111..2222222 100644\n"
        out += "--- a/src/Wide.swift\n"
        out += "+++ b/src/Wide.swift\n"
        out += "@@ -1,\(lines) +1,\(lines) @@ func handle()\n"
        for line in 0..<lines {
            let padding = String(repeating: " uzavreneho(kontextu, dlouheho, radku)", count: 5)
            out += "     let value = compute(\(needle), \(line))\(padding)\n"
        }
        return out
    }

    // MARK: - Vodorovná osa (split)

    /// **Je výskyt na dlouhém řádku vidět i do šířky?** (#152, druhé kolo proklikání.)
    ///
    /// Ve split pohledu se **nezalamuje**, takže výskyt za pravou hranou sloupce je mimo obrazovku
    /// a pruh přitom hlásí `4 z 17`. Měří se poloha výskytu proti viditelné části **sloupce**, ne
    /// okna: vodorovný posun je vlastnost sloupce (`DiffPairScrollView`), ne výřezu diffu.
    /// **Výskyt daleko vpravo musí být vidět i do šířky** (#152, druhé kolo proklikání: „vůbec
    /// nescrolluje do šířky, tak to není vidět").
    ///
    /// Ve split pohledu se **nezalamuje**, takže výskyt za třístým znakem leží mimo sloupec —
    /// a pruh přitom hlásí `4 z 17`. Měří se proti viditelné části **sloupce**
    /// (`DiffPairScrollView`), ne proti oknu: vodorovný posun je vlastnost sloupce.
    @Test("Výskyt daleko vpravo je vidět i do šířky (split)", arguments: [3, 21, 44])
    func theWideHitIsRevealedHorizontally(index: Int) async throws {
        let scene = try scene(material: Self.wideMaterial(), layout: .split)
        defer { scene.window.orderOut(nil) }
        await ready(scene)
        let spot = try await jump(scene, to: index)
        #expect(spot.isVisible, "řádek \(index) není vidět svisle (\(Int(spot.fromViewportTop)) pt od hrany)")
        let seen = try #require(Self.matchInColumn(scene, line: index), "výskyt se ve sloupci nenašel")
        #expect(
            seen.visible,
            "výskyt na x \(Int(seen.x)) je mimo výřez sloupce \(Int(seen.left))–\(Int(seen.right))"
        )
        // A sloupec se **doopravdy posunul** — bez toho by tvrzení výš mohlo platit jen proto, že se
        // výskyt náhodou vešel, a odhalení by se dalo smazat, aniž by to test poznal.
        #expect(seen.left > 0, "sloupec zůstal na začátku, k odhalení nedošlo")
    }

    /// Kde v okně leží výskyt na daném řádku a jestli je ve viditelné části svého sloupce.
    private static func matchInColumn(
        _ scene: Scene,
        line: Int
    ) -> (x: Double, left: Double, right: Double, visible: Bool)? {
        for container in containers(in: scene.hosting) {
            for (scroll, column) in container.probeColumns {
                guard let index = column.lines.firstIndex(where: { $0.newNumber == line + 1 }),
                      let span = column.span(
                          ofMatch: 0,
                          inLine: index,
                          query: DiffSearchQuery(text: needle)
                      )
                else { continue }
                let visible = scroll.documentVisibleRect
                return (
                    span.lowerBound,
                    Double(visible.minX),
                    Double(visible.maxX),
                    span.lowerBound >= Double(visible.minX) && span.upperBound <= Double(visible.maxX)
                )
            }
        }
        return nil
    }

    private static func containers(in view: NSView) -> [DiffPairBlockContainer] {
        (view as? DiffPairBlockContainer).map { [$0] } ?? view.subviews.flatMap { containers(in: $0) }
    }

    /// Diff, jehož řádky jsou **široké**: výskyt leží až za třístým znakem, tedy hluboko za pravou
    /// hranou sloupce.
    private static func wideMaterial() -> String {
        var out = "diff --git a/src/Wide.swift b/src/Wide.swift\n"
        out += "index 1111111..2222222 100644\n"
        out += "--- a/src/Wide.swift\n"
        out += "+++ b/src/Wide.swift\n"
        out += "@@ -1,50 +1,50 @@ func handle()\n"
        for line in 0..<50 {
            let padding = String(repeating: "x", count: 300)
            out += "     let value = compute(\(padding), \(needle), \(line))\n"
        }
        return out
    }

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
        await ready(scene)
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

        // A totéž pro **širokou** scénu ve split pohledu, protože právě tam se pozná to, co čísla
        // říct neumí: jestli je zvýrazněný výskyt v okně doopravdy vidět.
        let wide = try self.scene(material: Self.wideMaterial(), layout: .split)
        defer { wide.window.orderOut(nil) }
        await ready(wide)
        let spot = try await jump(wide, to: 21)
        Self.write(wide.hosting, to: URL(filePath: directory).appending(path: "skok-sirka-split.png"))
        print(String(
            format: "SONDA split, řádek 21: %.0f pt od hrany, výskyt %@",
            spot.fromViewportTop,
            Self.matchInColumn(wide, line: 21).map { $0.visible ? "vidět" : "MIMO" } ?? "nenalezen"
        ))
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
        let search: DiffSearchState
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
        /// Posun výřezu a výška obsahu — jen do zprávy u tvrzení, ať se z padlého běhu pozná, jestli
        /// skok neproběhl (posun stojí tam, kde byl) nebo jestli se pod cílem posunul obsah.
        let offset: Double
        let content: Double
    }

    private func scene(material: String? = nil, layout: DiffLayout = .unified) throws -> Scene {
        let diff = DiffParser.parse(material ?? Self.material())
        let target = JumpTarget()
        let search = DiffSearchState()
        search.isOpen = true
        search.query = Self.needle
        let hosting = NSHostingView(
            rootView: JumpProbe(diff: diff, target: target, search: search, layout: layout)
        )
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
        return Scene(window: window, hosting: hosting, target: target, diff: diff, search: search)
    }

    /// Nechá diff **doskládat**, ne jen rozvrhnout. Jev je *obsah vyšší než výřez* a k tomu
    /// **ustálená scéna**: výška obsahu i počet nasazených bloků se pět kol nemění.
    ///
    /// Bez toho druhého se skok vypálený do rozdělaného rozvržení **neudělá vůbec** (změřeno:
    /// posun 0 u prvního skoku ve scéně, cíl přitom v seznamu je). Sedí to k tomu, jak se diff
    /// skládá: na první rozvržení se nasadí i bloky mimo pás a hned nato se odpojí (#469), takže se
    /// scéna chvíli hýbe pod rukama.
    private func ready(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("diff se rozvrhne", sourceLocation: sourceLocation) {
            guard let scroller = Self.diffScroller(in: scene.hosting) else { return false }
            let content = scroller.documentView?.frame.height ?? 0
            return scroller.contentSize.height > 0 && content > scroller.contentSize.height
        }
        var quiet = 0
        var previous = -1
        await waitUntil("scéna se ustálí", sourceLocation: sourceLocation) {
            let scroller = Self.diffScroller(in: scene.hosting)
            let height = Int(scroller?.documentView?.frame.height ?? -1)
            let state = height * 1_000 + Self.textViews(in: scene.hosting).count
            quiet = state == previous ? quiet + 1 : 0
            previous = state
            return quiet >= 5
        }
        // A ještě odmlka navíc: ustálená **geometrie** neznamená, že je hotové i to, co si SwiftUI
        // vede o svých položkách. Je to jediné čekání tady, které nemá jev — proto krátké a proto
        // se o něj žádné tvrzení neopírá.
        await settle()
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
        // Aktuální výskyt do stavu hledání — z něj se počítá **vodorovné** odhalení (#152), které
        // dělá blok sám. Bez toho by se měřila jen svislá osa.
        scene.search.hits = hits
        scene.search.current = hits.firstIndex(of: hit)
        // **Jeden skok, ne dva.** Dokud byl skok animovaný, jeden z desítky nedojel a scéna si
        // musela pomáhat druhým pokusem na tentýž cíl; od chvíle, kdy animace není, je jeden skok
        // tím, co se měří — a kdyby zase přestal dojíždět, tvrzení to **pozná**.
        scene.target.anchor = DiffRow.anchor(in: scene.diff, hit: hit)
        // Cíl si `DiffView` po skoku spotřebuje (`scrollTarget = nil`) — a je to jediný jev, ze
        // kterého se pozná, že skok doběhl celý.
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
            isFreeOfEdges: offset > 1 && offset < last - 1,
            offset: Double(offset),
            content: Double(scroller.documentView?.frame.height ?? 0)
        )
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
    let search: DiffSearchState
    var layout: DiffLayout = .unified

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
            layout: .constant(layout),
            search: DiffSearchActions(state: search, open: {}, step: { _ in nil })
        )
    }
}
