import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Co udělá `updateNSView` nad blokem, který se nezměnil** (#393).
///
/// Tohle je ten nejcennější druh testu — tvrdí, že se něco **nestalo**, a přesně tahle vada se
/// rozbije potichu: přesázený blok vypadá stejně jako ten, co tam byl, jen zahodí rozdělaný výběr
/// a stojí desítky milisekund. Ve ztuhlém okně z #393 na to padlo **1 172 z 21 240** vzorků
/// hlavního vlákna, a to bez jediného průchodu tělem — SwiftUI si `updateNSView` volá při každém
/// přepočtu geometrie.
///
/// **Počítá se, nehádá se.** Blok drží tři čísla a každé odpovídá na jinou otázku:
///
/// - `updates` — kolikrát SwiftUI o aktualizaci **požádalo**;
/// - `mounts` — kolikrát se blok doopravdy **nasadil** (tedy kolikrát průchod prošel stráží a
///   zaplatil práci lineární v délce bloku). **Tohle je to číslo, o které u #393 šlo.**
/// - `typesettings` — kolikrát se doopravdy **sázel text**. To se neopakovalo ani před #393 (držel
///   to podpis obsahu, #157), takže se tady hlídá jako **nezměněná vlastnost**: šířka ho hýbat
///   nesmí, jazyk a režim musí.
///
/// Bez `updates` by ostatní dvě nic netvrdila: nula u nasazení znamená stejně dobře drženou stráž
/// jako test, ve kterém se nic nedělo. Proto se u každého scénáře nejdřív tvrdí, že aktualizace
/// **přišly**.
///
/// Graf se špiní **pohybem bloku**, ne jeho obsahem — odsazením o bod nahoru. Je to ta situace ze
/// ztuhlého okna: geometrie se přepočítává, blok je pořád tentýž.
@MainActor
@Suite("Aktualizace bloku kódu (#393)")
struct DiffBlockUpdateTests {
    private func lines(_ count: Int, from: Int = 0) -> [DiffLine] {
        (0..<count).map {
            DiffLine(kind: .context, oldNumber: $0 + 1, newNumber: $0 + 1, text: "let x\($0 + from) = \($0 + from)")
        }
    }

    // MARK: - Pohled vedle sebe

    /// Nezměněný blok dvojice: aktualizace chodí, nasazení ani sazba se nehnou.
    @Test("Nezměněná dvojice se znovu nenasazuje ani nesází")
    func unchangedPairIsNotRemounted() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(PairBlockProbe(state: state, block: pairBlock()), warming: state)
        defer { scene.window.orderOut(nil) }
        let container = try #require(Self.container(in: scene.hosting))
        let mounts = container.mounts
        #expect(container.typesettings == 2, "sloupce se mají složit jednou každý")

        pump(state, until: { container.updates }, in: scene)

        #expect(container.mounts == mounts)
        #expect(container.typesettings == 2)
    }

    /// **Kontrola měřidla**: po změně jazyka se nasadit i sázet **musí**. Bez tohohle řádku by nula
    /// výš mohla stejně dobře znamenat, že se stráž zúžila natolik, že už nepustí nic.
    @Test("Po změně jazyka se dvojice nasadí a přesází")
    func pairIsRemountedAfterLanguageChange() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(PairBlockProbe(state: state, block: pairBlock()), warming: state)
        defer { scene.window.orderOut(nil) }
        let container = try #require(Self.container(in: scene.hosting))
        let typesettings = container.typesettings
        let mounts = container.mounts

        state.language = Language(path: "app.php")
        pumpUntilQuiet(state, in: scene)

        #expect(container.mounts > mounts)
        #expect(container.typesettings > typesettings)
    }

    /// Totéž pro barevný režim: barvy jsou ve vysázeném textu zapečené, takže by se po přepnutí
    /// vzhledu (#278) jinak koukalo na kód obarvený podle toho druhého režimu.
    @Test("Po přepnutí režimu se dvojice nasadí a přesází")
    func pairIsRemountedAfterSchemeChange() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(PairBlockProbe(state: state, block: pairBlock()), warming: state)
        defer { scene.window.orderOut(nil) }
        let container = try #require(Self.container(in: scene.hosting))
        let typesettings = container.typesettings
        let mounts = container.mounts

        state.colorScheme = .dark
        pumpUntilQuiet(state, in: scene)

        #expect(container.mounts > mounts)
        #expect(container.typesettings > typesettings)
    }

    /// **Šířka sazbu nemění, ale rámečky řádků ano** — a na nich visí hranice pravé poloviny bloku
    /// (`DiffGutterGeometry.split`), tedy to, jestli pilulka svítí tam, kde se táhne rozsah. Proto
    /// se po změně šířky musí `updateNSView` protlačit stráží, i když se text nesází.
    @Test("Po změně šířky se přepočítají rámečky, ale nesází se")
    func widthChangeRefreshesFramesWithoutTypesetting() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(PairBlockProbe(state: state, block: pairBlock()), warming: state)
        defer { scene.window.orderOut(nil) }
        let container = try #require(Self.container(in: scene.hosting))
        let mounts = container.mounts
        let width = try #require(container.lineFrames().first).rect.width

        state.width = 620
        pumpUntilQuiet(state, in: scene)

        // Že se blok doopravdy zúžil — bez toho by řádek níž netvrdil nic, protože stráž nemá jak
        // pustit změnu, která nenastala.
        let narrowed = try #require(container.lineFrames().first).rect.width
        #expect(narrowed < width, "blok se měl zúžit, rámečky nesou \(narrowed)")
        // **Tohle je to tvrzení**: bez nasazení se nové rámečky do SwiftUI neohlásí, takže by
        // plochy na tažení a pilulka zůstaly na staré šířce bloku.
        #expect(container.mounts > mounts, "jiná šířka musí projít stráží")
        #expect(container.typesettings == 2, "šířka se sazby netýká — přesázení by sebralo výběr")
    }

    /// Jiný obsah je jiný blok — a to je ta polovina stráže, která **musí** pustit.
    @Test("Po změně obsahu se dvojice nasadí a přesází")
    func pairIsRemountedAfterContentChange() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(PairBlockProbe(state: state, block: pairBlock()), warming: state)
        defer { scene.window.orderOut(nil) }
        let container = try #require(Self.container(in: scene.hosting))
        let typesettings = container.typesettings
        let mounts = container.mounts

        state.block = pairBlock(from: 100)
        pumpUntilQuiet(state, in: scene)

        #expect(container.mounts > mounts)
        #expect(container.typesettings > typesettings)
    }

    // MARK: - Pohled pod sebou

    /// Tentýž invariant v pohledu pod sebou. Je to jiná cesta (`DiffCodeBlockView` nad jedním
    /// `DiffTextView`) a bez tohohle řádku by o ní test netvrdil nic — přitom `lineFrames()` se
    /// tam ptá layout manageru na **každý** řádek, takže je průchod ještě dražší.
    @Test("Nezměněný blok pod sebou se znovu nenasazuje ani nesází")
    func unchangedUnifiedBlockIsNotRemounted() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(UnifiedBlockProbe(state: state, block: DiffBlock(lines: lines(20))), warming: state)
        defer { scene.window.orderOut(nil) }
        let view = try #require(Self.textView(in: scene.hosting))
        let mounts = view.mounts
        #expect(view.typesettings == 1)

        pump(state, until: { view.updates }, in: scene)

        #expect(view.mounts == mounts)
        #expect(view.typesettings == 1)
    }

    @Test("Po přepnutí režimu se blok pod sebou nasadí a přesází")
    func unifiedBlockIsRemountedAfterSchemeChange() throws {
        let state = DiffBlockProbeState()
        let scene = try hosted(UnifiedBlockProbe(state: state, block: DiffBlock(lines: lines(20))), warming: state)
        defer { scene.window.orderOut(nil) }
        let view = try #require(Self.textView(in: scene.hosting))
        let typesettings = view.typesettings
        let mounts = view.mounts

        state.colorScheme = .dark
        pumpUntilQuiet(state, in: scene)

        #expect(view.mounts > mounts)
        #expect(view.typesettings > typesettings)
    }

    // MARK: - Ostatní representable v okně

    /// **Kolik aktualizací dostane representable, který si nepočítá vlastní velikost** — a proč se
    /// stráž z #393 nedává plošně do všech.
    ///
    /// `SelectableCodeView` (hunk v sheetu) skládá text `setAttributedString`em bezpodmínečně, což
    /// je na první pohled tentýž vzor: přesázení ruší výběr a sheet existuje jedině kvůli vybírání.
    /// Změřeno ale, že se ho to **netýká** — nad tímtéž špiněním grafu, po kterém blok dvojic dostane
    /// jedenáct aktualizací, dostane tenhle **jednu** (tu úvodní). Rozdíl je v tom, že blok si říká
    /// o vlastní velikost (`sizeThatFits`), takže visí na rozvržení; tady se hodnota representable
    /// nemění a SwiftUI aktualizaci nepošle.
    ///
    /// Zůstává tedy bez stráže, a je to rozhodnutí, ne opomenutí: stráž, kterou nemá co vyvolat, je
    /// stav, který nikdo nečte — a **nešla by ověřit vloženou regresí** (zkoušeno: bez ní test
    /// o výběru dál prochází, protože se sazba nespustí).
    @Test("Hunk v sheetu drží výběr, i když se graf špiní")
    func codeSheetIsNotUpdatedByGeometry() throws {
        let state = DiffBlockProbeState()
        let counter = DiffBlockProbeCounter()
        let scene = try hosted(
            CodeSheetProbe(state: state, counter: counter, code: Self.hunk),
            warming: state
        )
        defer { scene.window.orderOut(nil) }
        let textView = try #require(Self.plainTextView(in: scene.hosting))
        textView.setSelectedRange(NSRange(location: 4, length: 12))
        let selected = textView.selectedRange()
        #expect(selected.length == 12, "výběr se nepovedlo nastavit, test by netvrdil nic")

        // **Měřidlem je tady průchod tělem, ne počitadlo v bloku**: `SelectableCodeView` kreslí
        // obyčejný `NSTextView`, do kterého počitadla nepatří — a co se ověřit musí, je to, že se
        // scéna doopravdy přerovnávala.
        pump(state, until: { counter.bodies }, in: scene)

        // Výběr přežije, protože se text nepřesázel. Kdyby se sázel při každém průchodu (jako se to
        // dělo v bloku diffu), zmizel by hned při prvním.
        #expect(textView.selectedRange() == selected)
    }

    /// **Od #417 je sheet s hunkem roztahovatelný, takže tažení za okraj je nová cesta, kterou by se
    /// výběr mohl ztratit** — a tenhle test tvrdí, že se neztrácí.
    ///
    /// Drží to **vlastnost SwiftUI, ne stráž v kódu**, a je to změřené: `updateNSView` se za patnáct
    /// kroků tažení skutečného okna sheetu nezavolal ani jednou, protože se hodnota representable
    /// nemění (`code`, `language`, `colorScheme` jsou tažením netknuté). Stráž s klíčem
    /// v `Coordinator`u se proto **vědomě nepřidala** — nešla by ověřit vloženou regresí, což je
    /// pravidlo z `CLAUDE.md` u #393; zdůvodnění je u `SelectableCodeView.updateNSView`.
    ///
    /// Test tedy hlídá tu vlastnost: kdyby si `SelectableCodeView` začal říkat o vlastní velikost
    /// (`sizeThatFits`), aktualizace by chodit začaly, text by se přesázel a tady by to spadlo.
    @Test("Hunk v sheetu drží výběr i po změně šířky")
    func codeSheetKeepsTheSelectionWhileResizing() throws {
        let state = DiffBlockProbeState()
        let counter = DiffBlockProbeCounter()
        let scene = try hosted(
            CodeSheetProbe(state: state, counter: counter, code: Self.hunk),
            warming: state
        )
        defer { scene.window.orderOut(nil) }
        let textView = try #require(Self.plainTextView(in: scene.hosting))
        textView.setSelectedRange(NSRange(location: 4, length: 12))
        let selected = textView.selectedRange()
        #expect(selected.length == 12, "výběr se nepovedlo nastavit, test by netvrdil nic")

        // Tažení okrajem, krok po kroku — ne jeden skok: cena i riziko jsou v tom, co se děje
        // v každém kroku.
        for width in stride(from: 560.0, through: 900.0, by: 20.0) {
            state.width = width
            pumpUntilQuiet(state, in: scene)
        }

        // Že se to doopravdy přerovnávalo — bez toho by řádek níž netvrdil nic.
        #expect(counter.bodies > 1, "sonda se nepřerovnala, průchodů \(counter.bodies)")
        #expect(textView.selectedRange() == selected, "výběr zmizel, text se při tažení přesázel")
    }

    private static let hunk = (0..<40).map { "let value\($0) = compute(\($0))" }.joined(separator: "\n")

    /// Textové view, které **není** blok diffu — tedy to ze sheetu s hunkem.
    private static func plainTextView(in view: NSView) -> NSTextView? {
        if view is DiffTextView || view is DiffPairBlockContainer { return nil }
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { plainTextView(in: $0) }.first
    }

    // MARK: - Scéna

    private func pairBlock(from: Int = 0) -> DiffPairBlock {
        let side = lines(20, from: from)
        return DiffPairBlock(left: side, right: side)
    }

    private struct Scene<Content: View> {
        let window: NSWindow
        let hosting: NSHostingView<Content>
    }

    /// Scéna v okně **mimo obrazovku** — tatáž cesta jako u ostatních sond (#291): bez okna se
    /// hierarchie nedoskládá a `updateNSView` by nepřišel vůbec, a před oči nikomu skákat nemá.
    private func hosted<Content: View>(_ content: Content, warming state: DiffBlockProbeState) throws -> Scene<Content> {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        let scene = Scene(window: window, hosting: hosting)
        settle(scene)
        pumpUntilQuiet(state, in: scene)
        return scene
    }

    /// Špiní graf, dokud **nasazení nepřestanou přibývat** — a je to potřeba proto, že
    /// **`updateNSView` dostane `bounds.width` o jeden průchod pozadu**. Změřeno, ne odhadnuto:
    /// SwiftUI nastaví rámec view **až po** něm, takže klíč prvního průchodu nese šířku **nula**
    /// a ten druhý tu skutečnou; po změně šířky je to stejné o jeden krok dál.
    ///
    /// **Chování se tím nemění proti stavu před #393**: rámečky se i tehdy počítaly z `bounds`, tedy
    /// v tom prvním průchodu z nuly, a správné vyšly až v tom dalším. Jen to nebylo z čeho poznat.
    ///
    /// Bez tohohle dojetí by baseline nesla stav se šířkou nula a druhé (správné) nasazení by
    /// vypadalo jako porušená stráž.
    private func pumpUntilQuiet(
        _ state: DiffBlockProbeState,
        in scene: Scene<some View>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let started = Self.mounts(in: scene.hosting)
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        var quiet = 0
        var previous = -1
        var mounts = started
        // **Strop na počet nasazení, ne na počet kol** (jinak by tohle byl rozpočet kol, který
        // pod zátěží zčervená falešně, #296): tolik jich nastane jedině tehdy, když stráž nedrží,
        // a bez toho stropu se čeká celý `TestWait.deadline` u **každého** scénáře — na rozbité
        // stráži z toho bylo přes dvacet minut.
        while ContinuousClock.now < limit, quiet < 3, mounts - started <= 10 {
            state.tick += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            scene.hosting.layoutSubtreeIfNeeded()
            mounts = Self.mounts(in: scene.hosting)
            quiet = mounts == previous ? quiet + 1 : 0
            previous = mounts
        }
        // **Nedočkání se hlásí, ne přechází**: bez téhle věty by rozbitá stráž spadla o pár řádků
        // níž na čísle, ze kterého není poznat, že se scéna vůbec neusadila.
        if quiet < 3 {
            Issue.record(
                """
                Nasazení bloku se neusadila: \(mounts - started) nasazení za sebou \
                (\(Self.updates(in: scene.hosting)) aktualizací, strop \(TestWait.deadline)). \
                Stráž z DiffBlockDrawing nedrží.
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    /// Nechá SwiftUI doběhnout. **Jev se stropem, ne pevný okamžik** (#269): čeká se, dokud blok
    /// nedostane aktualizaci, kterou si scéna vyžádala.
    private func settle<Content: View>(_ scene: Scene<Content>) {
        let hosting = scene.hosting
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        var quiet = 0
        var previous = -1
        while ContinuousClock.now < limit, quiet < 3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
            let updates = Self.updates(in: hosting)
            quiet = updates == previous ? quiet + 1 : 0
            previous = updates
        }
    }

    /// Špiní graf, dokud bloku nepřijde aspoň desetkrát aktualizace — a **hlásí, když nepřijde**.
    /// Bez toho by tvrzení „nesází se“ platilo i o testu, ve kterém se nic nedělo.
    private func pump<Content: View>(
        _ state: DiffBlockProbeState,
        until updates: () -> Int,
        in scene: Scene<Content>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let target = updates() + 10
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        while ContinuousClock.now < limit, updates() < target {
            state.tick += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            scene.hosting.layoutSubtreeIfNeeded()
        }
        if updates() < target {
            Issue.record(
                """
                Nedočkalo se: blok nedostal 10 aktualizací (má \(updates()), \
                strop \(TestWait.deadline)). Tvrzení o nasazení tím ztrácí platnost — \
                měřidlo nic nepočítá.
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    private static func mounts(in view: NSView) -> Int {
        if let container = view as? DiffPairBlockContainer { return container.mounts }
        if let text = view as? DiffTextView { return text.mounts }
        return view.subviews.reduce(0) { $0 + mounts(in: $1) }
    }

    private static func updates(in view: NSView) -> Int {
        if let container = view as? DiffPairBlockContainer { return container.updates }
        if let text = view as? DiffTextView { return text.updates }
        return view.subviews.reduce(0) { $0 + updates(in: $1) }
    }

    private static func container(in view: NSView) -> DiffPairBlockContainer? {
        if let container = view as? DiffPairBlockContainer { return container }
        return view.subviews.lazy.compactMap { container(in: $0) }.first
    }

    /// Textové view **z pohledu pod sebou**, tedy to, které kreslí celý blok. Sloupce dvojice jsou
    /// taky `DiffTextView`, takže se hledá jen tam, kde kontejner dvojice není.
    private static func textView(in view: NSView) -> DiffTextView? {
        if view is DiffPairBlockContainer { return nil }
        if let text = view as? DiffTextView { return text }
        return view.subviews.lazy.compactMap { textView(in: $0) }.first
    }
}

/// Co se ve scéně mění. **Mimo blok schválně**: `tick` hýbe jeho polohou, ne obsahem — a právě to
/// je situace ze ztuhlého okna u #393.
@Observable
@MainActor
final class DiffBlockProbeState {
    var tick = 0
    var language: Language? = Language(path: "Cart.swift")
    var colorScheme: ColorScheme = .light
    var width: Double = 900
    var block: DiffPairBlock?
}

/// Blok dvojic v té podobě, v jaké je v okně — přes `DiffPairBlockRowView`, aby scéna nesla
/// i overlay gutteru a hlášení rámečků. S nahým `DiffPairBlockView` by test měřil něco, co
/// v aplikaci není.
private struct PairBlockProbe: View {
    let state: DiffBlockProbeState
    let block: DiffPairBlock

    var body: some View {
        DiffPairBlockRowView(block: state.block ?? block, language: state.language)
            .frame(width: state.width)
            // Špinění, které se **bloku nedotkne**: posune ho o bod, obsah i šířka zůstanou.
            .padding(.top, Double(state.tick % 2))
            .environment(\.colorScheme, state.colorScheme)
    }
}

/// Totéž pro pohled pod sebou.
private struct UnifiedBlockProbe: View {
    let state: DiffBlockProbeState
    let block: DiffBlock

    var body: some View {
        DiffBlockRowView(block: block, language: state.language)
            .frame(width: state.width)
            .padding(.top, Double(state.tick % 2))
            .environment(\.colorScheme, state.colorScheme)
    }
}

/// Průchody tělem — **mimo observable stav**, jinak by počitadlo špinilo graf samo a sonda by
/// měřila sebe (tatáž úvaha jako u `LayoutCallbackProbe.Counter`).
@MainActor
final class DiffBlockProbeCounter {
    private(set) var bodies = 0

    func note() {
        bodies += 1
    }
}

/// Hunk v sheetu (`SelectableCodeView`) — tatáž pumpa, jiný representable.
private struct CodeSheetProbe: View {
    let state: DiffBlockProbeState
    let counter: DiffBlockProbeCounter
    let code: String

    var body: some View {
        let _ = counter.note()
        SelectableCodeView(code: code, language: Language(path: "Cart.swift"), colorScheme: state.colorScheme)
            .frame(width: state.width, height: 300)
            .padding(.top, Double(state.tick % 2))
    }
}
