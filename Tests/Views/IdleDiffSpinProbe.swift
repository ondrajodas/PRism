import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361: **kolik CPU sežere okno s otevřeným diffem, ve kterém se nic nemění.**
///
/// Sestra `IdleWindowSpinProbe` (#350) pro druhou signaturu z tabulky u #350 — pro tu, ve které
/// v cestě není `NSDisplayCycleFlush` ani `runAnimationGroup`, ale
/// `flushObservers → beginTransaction → flushTransactions`. Ta se od animace liší tím, že ji
/// nepohání takt obrazovky: pohonem je něco, co si po každém kole nechá naplánovat další.
///
/// **Kurzor k tomu není potřeba a je to celý rozdíl proti #358.** Tam se smyčka zavírala přes
/// `onContinuousHover`, takže bez skutečné myši nad blokem kódu nenastala (změřeno, viz
/// `docs/testovani.md`). Tady se měří scéna sama.
///
/// Měří se **CPU hlavního vlákna**, ne nástěnný čas — smyčka většinu času spí. A **na obrazovce**,
/// ze stejného důvodu jako u #350: zakryté okno nedostává takt překreslování.
///
/// **Co sonda ukázala** (čísla v `docs/testovani.md`): nad žádným ze scénářů se smyčka nechytla,
/// tedy scéna sama ji nezavírá. Dvě věci se u toho **musely** srovnat, jinak sonda měří prázdno:
/// rozměr okna a to, že v něm doopravdy jsou bloky kódu — proto ta dvě čísla ve výpisu.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Nečinné okno s diffem (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct IdleDiffSpinProbe {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)

    /// Kolik CPU stojí nečinné okno podle toho, co je v něm. Rozhoduje **rozdíl mezi řádky
    /// tabulky**, ne absolutní číslo: kolo smyčky samo něco stojí, takže se scénáře poměřují
    /// mezi sebou.
    @Test("Kolik CPU sežere nečinné okno s diffem")
    func idleDiffBurnsNoCPU() async throws {
        let scenarios: [(name: String, tab: PullRequestTab, layout: DiffLayout, big: Bool)] = [
            ("přehled (bez diffu)", .overview, .unified, true),
            ("diff pod sebou", .filesChanged, .unified, true),
            ("diff vedle sebe", .filesChanged, .split, true),
            ("diff vedle sebe, malý", .filesChanged, .split, false),
        ]
        for scenario in scenarios {
            try await measure(scenario.name, tab: scenario.tab, layout: scenario.layout, big: scenario.big)
        }
    }

    /// Celé okno, ne jen detail: rail, hlavička, pruh záložek se **třemi otevřenými PR**, nálezy
    /// v diffu a vlákna konverzace — tedy scéna, ve které se #361 chytila.
    @Test("Plné okno se třemi záložkami a bublinami")
    func idleFullWindow() async throws {
        try await measure(
            "plné okno, tři záložky, nálezy",
            tab: .filesChanged,
            layout: .split,
            big: true,
            seconds: 8,
            full: true
        )
    }

    /// Totéž, ale s diffem **odscrollovaným do prostředka**. Líný seznam si v tom stavu odhaduje
    /// polohy do obou stran a `LazyLayoutViewCache` si říká o předběžné načtení
    /// (`signalPrefetch` ve vzorku u #361), takže je to jiná situace než seznam na svém vršku.
    @Test("Plné okno s odscrollovaným diffem")
    func idleScrolledWindow() async throws {
        for offset in [2000.0, 8000.0] {
            try await measure(
                "plné okno, odscrollováno o \(Int(offset))",
                tab: .filesChanged,
                layout: .split,
                big: true,
                seconds: 6,
                full: true,
                scrollBy: offset
            )
        }
    }

    /// Nečinné okno s **otevřenou konverzací** — scénář ze ztuhlé aplikace 2026-08-18, kdy
    /// v okně stál jediný PR a člověk projížděl osou. `sample` z ní měl **99 %** vzorků
    /// hlavního vlákna v transakčním kole, hover nula a jediný re-arm v `signalPrefetch`;
    /// naše rámce byly `ConversationNode.id`.
    ///
    /// **Nechytlo se to** (0,00–0,01 %), stejně jako u diffu: scéna sama kolo nezavírá ani tady.
    /// Cena projíždění se proto měří zvlášť (`scrollingConversation`) — čísla a co z toho plyne
    /// jsou v `docs/testovani.md`.
    @Test("Nečinné okno s otevřenou konverzací")
    func idleConversation() async throws {
        try await measure("konverzace", tab: .conversation, layout: .unified, big: false, full: true)
        for offset in [1000.0, 3000.0] {
            try await measure(
                "konverzace, odscrollováno o \(Int(offset))",
                tab: .conversation,
                layout: .unified,
                big: false,
                seconds: 6,
                full: true,
                scrollBy: offset
            )
        }
    }

    /// Ostatní záložky detailu nad **plným** oknem. Do #375 měřila sonda jen diff, takže o zbytku
    /// okna netvrdila nic — a věta „nečinné okno nehoří“ je tvrzení **o všech** záložkách, ne
    /// o jedné. Bez těchhle řádků by se u dalšího záchvatu nedalo vyloučit, že hoří zrovna ta,
    /// na kterou se nikdo nepodíval.
    @Test("Nečinné okno na ostatních záložkách")
    func idleOtherTabs() async throws {
        for tab in [PullRequestTab.overview, .commits, .checks] {
            try await measure("\(Self.slug(of: tab)), plné okno", tab: tab, layout: .unified, big: false, full: true)
        }
    }

    private static func slug(of tab: PullRequestTab) -> String {
        switch tab {
        case .overview: "přehled"
        case .commits: "commity"
        case .checks: "kontroly"
        default: "\(tab)"
        }
    }

    /// **Zůstává `DiffView` v hierarchii, když je vybraná Konverzace?** (#361)
    ///
    /// Ptá se to proto, že kdyby zůstával, běžely by dál jeho `onGeometryChange` nad **pojmenovaným**
    /// souřadnicovým prostorem (`DiffView.contentSpace`) a `DragGesture` v něm — a to byla nejsilnější
    /// hypotéza o pohonu kola. Odpověď se **nedá odbýt dojmem z kódu** (`switch tab` v `content`
    /// vypadá jako výběr jedné větve, ale to o životnosti nic netvrdí), takže se měří ze dvou stran:
    ///
    /// - **AppKitové view** z diffu (`DiffTextView`, `DiffPairBlockContainer`) v okně, tedy jestli
    ///   se representable vůbec vyrobil;
    /// - **průchody tělem** `DiffView` a `DiffRowView` v úseku, kdy se konverzací projíždí — kdyby
    ///   podstrom diffu žil, přerovnávání by ho zašpinilo s sebou.
    ///
    /// Scéna je **konverzace nad PR, které má načtený diff**, protože to je stav, v jakém uživatel
    /// doopravdy je: prohlíží si diff a pak přepne na osu.
    @Test("Zůstává DiffView v hierarchii pod Konverzací")
    func diffLivenessUnderConversation() async throws {
        let (store, cache) = try await prepared(big: true, full: true)
        defer { _ = cache }
        store.setDiffLayout(.split)
        store.setDetailTab(.filesChanged, for: pr)
        let window = show(scene: ContentView(store: store))
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        print("SONDA diff vybraný: \(Self.blocks(in: root)) bloků kódu, \(Self.descendants(of: root)) prvků")

        // Přepnutí na osu — a diff **zůstává načtený ve storu**, takže kdyby si ho SwiftUI držel
        // živý, měl by z čeho.
        store.setDetailTab(.conversation, for: pr)
        _ = spinMainRunLoop(seconds: 2)
        print("SONDA konverzace vybraná: \(Self.blocks(in: root)) bloků kódu, \(Self.descendants(of: root)) prvků")
        #expect(store.diffState(for: pr) != nil)

        let diagnostics = RenderDiagnostics(log: DiagnosticsLog(url: cache.url.appending(path: "d.log")))
        RenderDiagnostics.current = diagnostics
        defer { RenderDiagnostics.current = nil }
        let scroller = try #require(Self.tallestScroller(in: root))
        _ = WheelGesture.scroll(over: scroller, in: window, steps: 30, step: 40)
        print("MĚŘENÍ průchody tělem při projíždění osy nad načteným diffem: \(Self.passes(diagnostics))")
    }

    /// **Projíždění kolečkem** — a rozhodující číslo jsou ty úseky **po** gestu (#361).
    ///
    /// Cena projíždění se dá utratit, kolo ne: ztuhlá instance hořela šest hodin po tom, co od
    /// ní člověk odešel. `scroll(to:)` v `scrollingConversation` níž kolo nerozjede vůbec (proč,
    /// je u `WheelGesture`), takže tohle je ta cesta, kterou se hledá pohon.
    @Test("Projíždění konverzace kolečkem")
    func wheelConversation() async throws {
        try await measureWheel("konverzace", tab: .conversation)
    }

    /// Dlouhá osa nad PR, které má **načtený diff** — tedy scénář ze ztuhlé aplikace. Bez tohohle
    /// řádku by se z `wheelLongConversation` nedalo poznat, jestli na tom, že si člověk předtím
    /// prohlížel diff, něco závisí.
    @Test("Projíždění dlouhé osy nad načteným diffem")
    func wheelLongConversationOverDiff() async throws {
        try await measureWheel("dlouhá osa nad diffem", tab: .conversation, comments: 300, big: true)
    }

    /// **Scénář na ablaci** (#361): projet osu celou, ne dva a půl tisíce bodů z čtyřiceti tisíc.
    ///
    /// Existuje proto, že šedesát kroků po čtyřiceti bodech je na porovnávání variant **málo**:
    /// zmateralizuje se 17 řádků a celé gesto stojí 0,14 s, takže se v tom rozdíl mezi „s baseline
    /// zarovnáním“ a „bez něj“ utopí. Změřeno — čtyři varianty (včetně té úplně bez markdownu) vyšly
    /// 0,14 / 0,14 / 0,14 / 0,12 s, tedy na hranici šumu. Tady se projede **celý** obsah, takže se
    /// každý uzel osy jednou umístí a rozdíl má z čeho vyjít.
    @Test("Projíždění celé osy kolečkem (na ablaci)")
    func wheelWholeConversation() async throws {
        try await measureWheel(
            "celá osa",
            tab: .conversation,
            comments: 300,
            steps: 300,
            step: 140
        )
    }

    /// Totéž nad **dlouhou osou s různě vysokými uzly** — tedy nad tím, co v okně doopravdy je.
    /// Fixture z `cli/cli` má 44 položek a 5 500 bodů obsahu, kdežto PR z tohohle repa jich má
    /// stovky a výšky uzlů se liší násobně (krátká věta proti bloku kódu). Na odhadu zbytku
    /// obsahu z už umístěných řádků visí právě to, kolik toho líný seznam přerovnává.
    @Test("Projíždění dlouhé osy kolečkem")
    func wheelLongConversation() async throws {
        try await measureWheel("dlouhá osa", tab: .conversation, comments: 300)
    }

    /// Kontrola: tentýž seznam, jiný obsah řádku. Bez tohohle řádku by z čísla u konverzace
    /// nešlo poznat, jestli je to o ose, nebo o líném seznamu.
    @Test("Projíždění diffu kolečkem")
    func wheelDiff() async throws {
        try await measureWheel("diff", tab: .filesChanged)
    }

    /// **Diff vedle sebe** — a je to ta scéna, ve které ztuhlo okno u #393: bloky dvojic, na kterých
    /// se v `updateNSView` platil hash všech řádků, dvě pole `DiffLine` navíc, dvě množiny,
    /// `sizeToFit()` na oba sloupce a rámečky řádků, a to při **každém** přepočtu geometrie.
    ///
    /// Číslo, které o té stráži rozhoduje, je `práce bloků` ve výpisu — a čte se **poměr**, ne
    /// absolutní počty: nad usazenou scénou vyjde **15 aktualizací na 3 nasazení** (tři bloky, jedno
    /// nasazení každý; bez stráže 15 na 15), sazeb jsou dvě na blok, jedna za sloupec. **Na samotném
    /// gestu se stráž neprojeví** a je to tak správně: blok, který vjede do okna, dostane jednu
    /// aktualizaci, takže tam není co ušetřit (změřeno 0,55 / 0,52 s se stráží proti 0,50 / 0,55 s
    /// bez ní). Série se u toho **střídají** (A/B/A/B), protože drift sezení je větší než hledaný
    /// rozdíl (#274).
    @Test("Projíždění diffu vedle sebe kolečkem")
    func wheelSplitDiff() async throws {
        try await measureWheel("diff vedle sebe", tab: .filesChanged, layout: .split)
    }

    /// **Kontrola měřidla** (#361): scéna, která se chvíli neusazuje. Bez ní číslo „0,00 % po
    /// gestu“ netvrdí nic — může to být stejně dobře čisté okno jako sonda, která smyčku nevidí.
    ///
    /// Čte se **první úsek proti poslednímu**: dokud se zpětná vazba krmí, hoří, a jak jí dojde
    /// rozpočet kol, spadne na nulu. Rozpočet je pojistka proti zaseknutému oknu (proč, je
    /// u `FeedbackLoopList`) a plyne z něj, že **nekonečné** kolo tím ověřené není. Měří se
    /// proto **od prvního snímku**, bez usazení — usazení by celý rozpočet spolklo a sonda by
    /// hlásila nulu nad scénou, která zrovna hořela.
    @Test("Kontrola měřidla: scéna, která se chvíli neusazuje")
    func loopControl() async throws {
        // Bez `.minSize`: oscilace se vejde celá do dotazu na minimum okna a AppKit ji zabije
        // výjimkou dřív, než se dá cokoli změřit (viz `show(scene:minSizeFromContent:)`).
        let window = show(scene: FeedbackLoopList(), minSizeFromContent: false)
        defer { window.orderOut(nil) }
        for slice in 1...4 {
            let cpu = spinMainRunLoop(seconds: 2)
            print(String(format: "MĚŘENÍ kontrola měřidla, úsek %d: %.2f %% CPU hlavního vlákna", slice, cpu / 2 * 100))
        }
    }

    /// **Osa, která se zkrátí pod odscrollovaným seznamem** (#361, čtvrté kolo).
    ///
    /// Hypotéza k tomu, proč `signalPrefetch` nekonverguje: líný seznam si o předběžné načtení
    /// říká podle **viditelného výřezu**, a ten po zkrácení obsahu leží za jeho koncem. Prefetch
    /// pak chce řádky z pásma, které neexistuje, a po každém průchodu si řekne znovu. V aplikaci
    /// se to stane samo — polling natáhne konverzaci znovu, takže obsah se přesází pod rukama
    /// někoho, kdo je odscrollovaný dole; a záznam z diagnostiky říká, že záchvat začal **skokem**,
    /// ne postupným nárůstem.
    ///
    /// Čtou se **úseky po** té změně: cena přesázení se dá utratit, kolo ne.
    @Test("Osa se zkrátí pod odscrollovaným seznamem")
    func shrinkingConversationUnderScroll() async throws {
        try await measureResize("zkrácení u dna", from: 300, to: 40, scrollSteps: 300)
        try await measureResize("zkrácení v prostředku", from: 300, to: 40, scrollSteps: 60)
        try await measureResize("prodloužení u dna", from: 300, to: 600, scrollSteps: 300)
        // Stejný počet, jiné výšky: odhad zbytku obsahu se rozejde, i když se konec nehne.
        try await measureResize("jiné výšky u dna", from: 300, to: 300, scrollSteps: 300, shift: 2)
    }

    /// Jeden scénář přesázení: projet osu kolečkem, změřit nečinnost, vyměnit obsah a **nechat
    /// okno stát**.
    private func measureResize(
        _ name: String,
        from: Int,
        to: Int,
        scrollSteps: Int,
        shift: Int = 0
    ) async throws {
        let (store, cache) = try await prepared(big: false, full: true)
        defer { _ = cache }
        store.conversationStates[pr] = .loaded(
            Self.synthetic(comments: from),
            updatedAt: Self.summary.updatedAt
        )
        store.setDetailTab(.conversation, for: pr)
        let window = show(scene: ContentView(store: store))
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        let landed = WheelGesture.scroll(over: scroller, in: window, steps: scrollSteps, step: 140)
        let idle = spinMainRunLoop(seconds: 3)
        print(String(
            format: "MĚŘENÍ %@: obsah %.0f, dojelo na %.0f, před výměnou %.2f %% CPU",
            name,
            scroller.documentView?.frame.height ?? 0,
            landed,
            idle / 3 * 100
        ))

        store.conversationStates[pr] = .loaded(
            Self.synthetic(comments: to, shift: shift),
            updatedAt: Self.summary.updatedAt
        )
        for slice in 1...3 {
            let cpu = spinMainRunLoop(seconds: 3)
            print(String(
                format: "MĚŘENÍ %@ po výměně (%d → %d), úsek %d: %.2f %% CPU, obsah %.0f, výřez %.0f",
                name,
                from,
                to,
                slice,
                cpu / 3 * 100,
                scroller.documentView?.frame.height ?? 0,
                scroller.documentVisibleRect.origin.y
            ))
        }
    }

    /// **Změna velikosti okna nad otevřenou osou** (#361, čtvrté kolo).
    ///
    /// Druhá nitka z #363: scéna má `.windowResizability(.contentMinSize)`, takže si AppKit při
    /// každém průchodu `updateConstraints` říká o `minSize`, hostující vrstva na to pustí
    /// `_sizeThatFits` — **druhou aktualizaci grafu na jiné nabídce rozměru** — a ze zásobníku jedné
    /// AppKitové výjimky se tam ukázalo `invalidateTransform → graphDidChange →
    /// requestUpdate(after:) → setNeedsUpdateConstraints`. Tahle cesta se dosud nezkoušela: sonda
    /// měla velikost okna pevnou, takže se `minSize` nikdy nepřepočítávalo za pochodu.
    ///
    /// Rozhodují **úseky po** změně rozměru, jako všude u #361.
    @Test("Osa při změně velikosti okna")
    func resizingWindowOverConversation() async throws {
        try await measureWindowResize("osa", tab: .conversation, comments: 300)
        try await measureWindowResize("diff", tab: .filesChanged, comments: 0)
    }

    private func measureWindowResize(
        _ name: String,
        tab: PullRequestTab,
        comments: Int
    ) async throws {
        let (store, cache) = try await prepared(big: tab == .filesChanged, full: true)
        defer { _ = cache }
        if comments > 0 {
            store.conversationStates[pr] = .loaded(
                Self.synthetic(comments: comments),
                updatedAt: Self.summary.updatedAt
            )
        }
        store.setDetailTab(tab, for: pr)
        let window = show(scene: ContentView(store: store))
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        _ = WheelGesture.scroll(over: scroller, in: window, steps: 60, step: 140)
        _ = spinMainRunLoop(seconds: 2)

        // Dvacet kroků tam a zpátky po 24 bodech, s kolem runloopu po každém — jako když se
        // táhne za hranu okna. **Strop je v tom výčtu**, žádná smyčka „dokud“.
        let started = mainThreadCPUSeconds()
        for step in 0..<20 {
            let width = 1512 - Double(min(step, 19 - step) * 24)
            window.setContentSize(NSSize(width: width, height: 874))
            _ = spinMainRunLoop(seconds: 0.03)
        }
        print(String(
            format: "MĚŘENÍ %@ tažení za hranu: %.2f s CPU, minimum obsahu %.0f×%.0f, okno %.0f×%.0f",
            name,
            mainThreadCPUSeconds() - started,
            window.contentMinSize.width,
            window.contentMinSize.height,
            window.frame.width,
            window.frame.height
        ))
        for slice in 1...3 {
            let cpu = spinMainRunLoop(seconds: 3)
            print(String(
                format: "MĚŘENÍ %@ po tažení, úsek %d: %.2f %% CPU hlavního vlákna",
                name,
                slice,
                cpu / 3 * 100
            ))
        }
    }

    /// **Píše diagnostika i nad scénou, která hlavní vlákno vytíží?** (#391)
    ///
    /// Unit test na to je (`RenderDiagnosticsTests.writesWhileMainThreadNeverReturns`), ale ten si
    /// kolo vyrábí blokujícím observerem. Tady je to nad **skutečnou scénou**: kontrolní seznam se
    /// zpětnou vazbou z rozvržení do stavu (`FeedbackLoopList`, 32 % CPU) a hned za ním projetí osy
    /// kolečkem. Vypisuje se, co v souboru přibylo — a co u toho stálo hlavní vlákno, aby se dalo
    /// poznat, jestli se měřilo nad zátěží, nebo nad prázdnem.
    @Test("Diagnostika píše i pod zátěží")
    func diagnosticsUnderLoad() async throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appending(path: "diagnostics.log")
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: file, zone: .current),
            interval: 0.5
        )
        RenderDiagnostics.current = diagnostics
        defer {
            RenderDiagnostics.current = nil
            diagnostics.stop()
        }
        diagnostics.observeRunLoop()
        diagnostics.startWriting()

        let loop = show(scene: FeedbackLoopList(), minSizeFromContent: false)
        for slice in 1...2 {
            let cpu = spinMainRunLoop(seconds: 2)
            print(String(
                format: "MĚŘENÍ kontrolní scéna, úsek %d: %.2f %% CPU, řádků v logu %d",
                slice,
                cpu / 2 * 100,
                Self.lines(of: file).count
            ))
        }
        loop.orderOut(nil)

        let (store, cache) = try await prepared(big: false, full: true)
        defer { _ = cache }
        store.conversationStates[pr] = .loaded(Self.synthetic(comments: 300), updatedAt: Self.summary.updatedAt)
        store.setDetailTab(.conversation, for: pr)
        let window = show(scene: ContentView(store: store))
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        let before = Self.lines(of: file).count
        let started = mainThreadCPUSeconds()
        _ = WheelGesture.scroll(over: scroller, in: window, steps: 60, step: 40)
        print(String(
            format: "MĚŘENÍ gesto nad osou: %.2f s CPU, řádků v logu %d → %d",
            mainThreadCPUSeconds() - started,
            before,
            Self.lines(of: file).count
        ))
        let lines = Self.lines(of: file)
        print("SONDA celý záznam:\n" + lines.joined(separator: "\n"))
        // Bez řádků netvrdí ta čísla výš nic: sonda by měřila zátěž a mlčení o ní.
        #expect(lines.count >= 4)
    }

    /// Řádky záznamu. Chybějící soubor znamená **„ještě se nic nezapsalo“**, což je platný stav
    /// (diagnostika ho zakládá až u prvního řádku) — a kdyby čtení selhalo jinak, spadne na tom
    /// `#expect` na počtu řádků, takže se to nemá kde schovat.
    private static func lines(of file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return TextLines.content(text).map(String.init)
    }

    /// Jeden scénář kolečkem: usadit, změřit nečinnost, projet gestem a **nechat okno stát**.
    ///
    /// Měří se tři věci, protože jedna bez druhých nic neznamená: nečinnost před gestem (okno
    /// nehořelo už předtím), cena gesta (gesto se doopravdy odehrálo) a nečinnost po něm
    /// (zůstalo po gestu kolo). Usazení po posunu odezní za jeden úsek, kolo ne — proto úseky.
    private func measureWheel(
        _ name: String,
        tab: PullRequestTab,
        comments: Int = 0,
        big: Bool? = nil,
        steps: Int = 60,
        step: Double = 40,
        layout: DiffLayout = .unified
    ) async throws {
        let (store, cache) = try await prepared(big: big ?? (tab == .filesChanged), full: true)
        defer { _ = cache }
        if comments > 0 {
            // **Razítko musí být to z fixture PR**: detail si při zobrazení konverzaci natáhne
            // znovu, když `updatedAt` nesedí (`hasCurrentConversation`), a syntetická osa by se
            // zahodila — sonda by pak měřila prázdno a tvrdila, že je čisto.
            store.conversationStates[pr] = .loaded(
                Self.synthetic(comments: comments),
                updatedAt: Self.summary.updatedAt
            )
            // **Složení fixture se vypisuje**, protože na něm celý ablační scénář stojí: bez
            // odrážek a bez víc odstavců by `MarkdownText` baseline `HStack` (`item(marker:…)`)
            // vůbec nevyrobil a měřilo by se něco jiného, než co se hledá (#361).
            print("SONDA \(name): osa má \(comments) komentářů, \(Self.shapes(of: comments))")
        }
        store.setDetailTab(tab, for: pr)
        store.setDiffLayout(layout)
        let window = show(scene: ContentView(store: store))
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        print(String(
            format: "SONDA %@: okno %.0f×%.0f, minimum obsahu %.0f×%.0f, %d prvků,"
                + " %d položek osy, obsah scrolleru %.0f",
            name,
            window.frame.width,
            window.frame.height,
            window.contentMinSize.width,
            window.contentMinSize.height,
            Self.descendants(of: root),
            store.overview(for: pr).count,
            scroller.documentView?.frame.height ?? 0
        ))
        print("SONDA \(name): bloků kódu v okně \(Self.blocks(in: root))")
        let idle = spinMainRunLoop(seconds: 3)
        print(String(format: "MĚŘENÍ %@ před gestem: %.2f %% CPU hlavního vlákna", name, idle / 3 * 100))
        // **Průchody tělem se počítají jen v tomhle úseku** a do vlastní instance diagnostiky, ne
        // do té z aplikace (#361): globální `shared` píše do skutečné cache a testovací host má
        // `CFBundleName` hlavní instance, takže by sonda zapisovala do souboru toho PRismu, který
        // se používá.
        let diagnostics = RenderDiagnostics(log: DiagnosticsLog(url: cache.url.appending(path: "d.log")))
        RenderDiagnostics.current = diagnostics
        defer { RenderDiagnostics.current = nil }
        print("MĚŘENÍ \(name) práce bloků před gestem: \(Self.blockWork(in: root))")
        let started = mainThreadCPUSeconds()
        let landed = WheelGesture.scroll(over: scroller, in: window, steps: steps, step: step)
        let during = mainThreadCPUSeconds() - started
        print(String(
            format: "MĚŘENÍ %@ kolečkem: %.2f s CPU hlavního vlákna, %d kroků po %.0f pt (dojelo na %.0f)",
            name,
            during,
            steps,
            step,
            landed
        ))
        print("MĚŘENÍ \(name) průchody tělem při gestu: \(Self.passes(diagnostics))")
        print("MĚŘENÍ \(name) práce bloků po gestu: \(Self.blockWork(in: root))")
        for slice in 1...3 {
            let cpu = spinMainRunLoop(seconds: 3)
            print(String(format: "MĚŘENÍ %@ po gestu, úsek %d: %.2f %% CPU hlavního vlákna", name, slice, cpu / 3 * 100))
            print("MĚŘENÍ \(name) průchody tělem po gestu, úsek \(slice): \(Self.passes(diagnostics))")
            print("MĚŘENÍ \(name) práce bloků po gestu, úsek \(slice): \(Self.blockWork(in: root))")
        }
    }

    /// **Kolik práce ve viditelných blocích kódu doopravdy proběhlo** (#393): kolikrát jim SwiftUI
    /// poslalo aktualizaci a kolikrát z toho vysázely text.
    ///
    /// Čte se to jako **absolutní počty za bloky, které v okně právě jsou**, ne jako rozdíl proti
    /// minulému čtení: `LazyVStack` view nezachovává, takže blok, který vyjel z okna, si svá čísla
    /// odnese a rozdíl by vyšel negativní (změřeno: `-11× updateNSView` po projetí). Rozhoduje
    /// **poměr** — kolik aktualizací na jedno nasazení.
    private static func blockWork(in view: NSView) -> BlockWork {
        if let container = view as? DiffPairBlockContainer {
            return BlockWork(
                updates: container.updates,
                mounts: container.mounts,
                typesettings: container.typesettings,
                blocks: 1
            )
        }
        if let text = view as? DiffTextView {
            return BlockWork(
                updates: text.updates,
                mounts: text.mounts,
                typesettings: text.typesettings,
                blocks: 1
            )
        }
        return view.subviews.reduce(BlockWork()) { $0 + blockWork(in: $1) }
    }

    private struct BlockWork: CustomStringConvertible {
        var updates = 0
        var mounts = 0
        var typesettings = 0
        var blocks = 0

        static func + (lhs: Self, rhs: Self) -> Self {
            Self(
                updates: lhs.updates + rhs.updates,
                mounts: lhs.mounts + rhs.mounts,
                typesettings: lhs.typesettings + rhs.typesettings,
                blocks: lhs.blocks + rhs.blocks
            )
        }

        var description: String {
            "\(blocks) bloků v okně, \(updates)× updateNSView, \(mounts)× nasazení, \(typesettings)× sazba"
        }
    }

    /// Kolik čeho v syntetické ose je. Pět tvarů po `index % 5`, viz `ConversationFixture`.
    private static func shapes(of comments: Int) -> String {
        ConversationFixture.shapes(of: comments)
    }

    /// Průchody tělem od nejčastějšího, jako je píše diagnostika do souboru — a **nuluje** je,
    /// aby další úsek popisoval jen sebe.
    private static func passes(_ diagnostics: RenderDiagnostics) -> String {
        let counts = diagnostics.snapshot()
        diagnostics.reset()
        guard !counts.isEmpty else { return "žádné" }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    /// Cena **projíždění**, ne nečinnosti — a je to ten scénář, na kterém aplikace ztuhla
    /// (`hang361`, „projížděl jsem konverzací“). Nečinná konverzace je čistá (tabulka
    /// v `docs/testovani.md`), takže se ta cena musí hledat v pohybu.
    ///
    /// **Scrolluje se po malých krocích**, jako kolečkem: skok o půl obrazovky přerovná líný
    /// seznam jednou a rozdíl mezi verzemi se v něm utopí — tatáž past jako hustota kroků u #252
    /// (60 kroků 3,6 vs 3,4 s, 300 kroků 15,6 vs 13,5 s).
    @Test("Cena projíždění konverzace")
    func scrollingConversation() async throws {
        try await measureScrolling("konverzace", tab: .conversation, steps: 150, step: 40)
    }

    /// Totéž nad diffem, jako kontrola: diff má stejný líný seznam, ale výšku řádku pevnou.
    /// Bez tohohle řádku by z čísla u konverzace nešlo poznat, jestli je drahé projíždění, nebo
    /// jen tenhle seznam.
    @Test("Cena projíždění diffu")
    func scrollingDiff() async throws {
        try await measureScrolling("diff", tab: .filesChanged, steps: 150, step: 40)
    }

    /// Jeden scénář projíždění: usadit, pak scrollovat po krocích a vypsat, kolik to stálo.
    ///
    /// **Hodinky se zapínají až po usazení** (#274) — postavení hierarchie do měření nepatří.
    private func measureScrolling(
        _ name: String,
        tab: PullRequestTab,
        steps: Int,
        step: Double
    ) async throws {
        let (store, cache) = try await prepared(big: tab == .filesChanged, full: true)
        defer { _ = cache }
        store.setDetailTab(tab, for: pr)
        store.setDiffLayout(.unified)
        let window = show(store: store, full: true)
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        let content = scroller.documentView?.frame.height ?? 0
        let reach = max(content - scroller.contentSize.height, 0)
        let cpuStart = mainThreadCPUSeconds()
        for stride in 0..<steps {
            // Trojúhelníkový průběh: sjíždí se dolů a **za koncem obsahu se otáčí zpátky**, aby
            // se seznam přerovnával do obou stran. Při dnešních 150 × 40 pt se do obratu nedojde
            // (6000 pt proti dosahu ~8800), takže je to pojistka pro delší série, ne popis běhu.
            let raw = Double(stride) * step
            let cycle = max(reach, 1)
            let phase = raw.truncatingRemainder(dividingBy: cycle * 2)
            scroller.contentView.scroll(to: NSPoint(x: 0, y: phase <= cycle ? phase : cycle * 2 - phase))
            scroller.reflectScrolledClipView(scroller.contentView)
            // Kolo runloopu po každém kroku: bez něj se rozvržení odloží a naměřila by se cena
            // jednoho přerovnání místo všech.
            _ = spinMainRunLoop(seconds: 0.02)
        }
        let cpu = mainThreadCPUSeconds() - cpuStart
        print(String(
            format: "MĚŘENÍ projíždění %@: %.2f s CPU hlavního vlákna, %d kroků po %.0f pt"
                + " (obsah %.0f, dosah %.0f, %d prvků, okno %.0f×%.0f)",
            name,
            cpu,
            steps,
            step,
            content,
            reach,
            Self.descendants(of: root),
            window.frame.width,
            window.frame.height
        ))
    }

    /// Dlouhý běh nad plným oknem, aby se dal vzít `sample` testovacího hosta a porovnat
    /// signatura s tou ze ztuhlé aplikace (postup v `docs/testovani.md`).
    @Test("Dlouhé nečinné okno k odvzorkování")
    func longIdleWindow() async throws {
        let (store, cache) = try await prepared(big: true, full: true)
        defer { _ = cache }
        store.setDetailTab(.filesChanged, for: pr)
        store.setDiffLayout(.split)
        let window = show(store: store, full: true)
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)
        print("SONDA odscrollováno na \(Self.scroll(window.contentView, by: 8000))")
        _ = spinMainRunLoop(seconds: 2)
        print("SONDA PID \(ProcessInfo.processInfo.processIdentifier), 8× 5 s")
        // Po pěti sekundách se vypisuje průběžně: z jednoho čísla za třicet sekund se nepozná,
        // jestli se něco doúčtovalo na začátku, nebo to hoří pořád.
        for slice in 1...8 {
            let cpu = spinMainRunLoop(seconds: 5)
            print(String(format: "MĚŘENÍ úsek %d: %.2f %% CPU hlavního vlákna", slice, cpu / 5 * 100))
        }
    }

    /// **Co instrumentace grafu (#361) hlásí nad skutečným oknem aplikace.**
    ///
    /// Kolo z #361 se v harnessu za sedm kol nerozjelo, takže tohle **není** pokus ho vyrobit.
    /// Odpovídá na jinou otázku, bez které by ta instrumentace byla tvrzení bez důkazu: **ozvou se
    /// háky nad skutečným stromem aplikace a přijde z nich zásobník?** Vypisují se proto počty
    /// (`GraphSite`) a řádky, které by v tu sekundu šly do záznamu — tedy přesně to, co uživatel
    /// uvidí v `diagnostics.log`, až okno začne hořet.
    ///
    /// Diagnostika se tady podstrkuje **ručně** (`RenderDiagnostics.current`), protože
    /// `PRISM_DIAGNOSE` se v testech nezapíná; `defer` ji uklidí, jinak by ji viděly další testy
    /// v tomtéž procesu.
    @Test("Co hlásí instrumentace grafu nad skutečným oknem")
    func graphInstrumentationOverRealWindow() async throws {
        for tab in [PullRequestTab.filesChanged, .conversation] {
            try await measureGraphSites(tab == .filesChanged ? "diff" : "osa", tab: tab)
        }
    }

    /// **Odkud se v okně berou dotazy na geometrii řádku diffu** (#438).
    ///
    /// Zadání #438 stálo na tom, že `DiffLine.geometry` (369 546 zásahů v jednom záchvatu, vepředu
    /// Konverzace) počítá **diff pod jiným tabem**. Odpovědět se na to dá jedině měřením, protože
    /// z kódu to není vidět ani z jedné strany: `DiffView` slévá řádky do bloků
    /// (`DiffRow.blocked(_:)`), takže `DiffLineView` v diffu nekreslí ani jeden řádek — kdežto
    /// úryvek u vlákna na ose (`ThreadSnippetView`) ho kreslí pro **každý** řádek hunku.
    ///
    /// Měří se proto obě záložky nad toutéž scénou: diff vepředu a osa s vlákny, která mají
    /// `diffHunk`. Rozhoduje řádek `DiffLine.geometry` ve výpisu `MĚŘENÍ instrumentace …`.
    @Test("Odkud se berou dotazy na geometrii řádku diffu")
    func lineGeometryOrigin() async throws {
        try await measureGraphSites("diff vepředu", tab: .filesChanged)
        try await measureGraphSites(
            "osa s vlákny",
            tab: .conversation,
            conversation: try Self.threaded(count: 60)
        )
    }

    private func measureGraphSites(
        _ name: String,
        tab: PullRequestTab,
        conversation: Conversation? = nil
    ) async throws {
        let (store, cache) = try await prepared(big: true, full: true)
        defer { _ = cache }
        if tab == .conversation {
            store.conversationStates[pr] = .loaded(
                conversation ?? Self.synthetic(comments: 300),
                updatedAt: Self.summary.updatedAt
            )
        }
        store.setDetailTab(tab, for: pr)
        store.setDiffLayout(.split)
        let window = show(store: store, full: true)
        defer { window.orderOut(nil) }
        _ = spinMainRunLoop(seconds: 2)

        let directory = try TemporaryDirectory()
        let diagnostics = RenderDiagnostics(
            log: DiagnosticsLog(url: directory.url.appending(path: "diagnostics.log")),
            interval: 1
        )
        RenderDiagnostics.current = diagnostics
        #expect(GraphProbe.prepare())
        defer {
            RenderDiagnostics.current = nil
            _ = directory
        }

        // Projet kolečkem: háky se ozvou při **přerovnání** obsahu, ne nad stojícím seznamem.
        let root = try #require(window.contentView)
        let scroller = try #require(Self.tallestScroller(in: root))
        _ = WheelGesture.scroll(over: scroller, in: window, steps: 40, step: 120)
        _ = spinMainRunLoop(seconds: 1)

        let sites = diagnostics.graphSnapshot()
        print("MĚŘENÍ instrumentace \(name): \(sites.sorted { $0.value > $1.value })")
        // **Aspoň jedno místo se ozvat musí**, jinak by v hořícím kole nebylo z čeho brát vzorek.
        #expect(!sites.isEmpty, "nad oknem se neozvalo ani jedno místo v grafu")
        // **Dotazy se čtou z instance, neodvozují z pole úspěchů** (nález Copilota na #397):
        // `graphStacks().count` je počet vzorků, které přišly, kdežto `samples` je počet dotazů —
        // a rozdíl mezi nimi je zrovna to, co má řádek říct.
        for line in Policy.graphDiagnosticLines(
            sites: sites,
            stacks: diagnostics.graphStacks(),
            samples: diagnostics.graphSampleAttempts()
        ) {
            print("ZÁZNAM \(name):\(line)")
        }
    }

    /// Jeden scénář: postavit okno, nechat ho stát a vypsat, co v něm je a kolik to stálo.
    ///
    /// Vypisuje se i **velikost okna**: `NSHostingController` cpe velikost scény do okna, takže
    /// okno, které si samo mění rozměr, je vidět — a nad takovým oknem měření nic neváží.
    private func measure(
        _ name: String,
        tab: PullRequestTab,
        layout: DiffLayout,
        big: Bool,
        seconds: TimeInterval = 4,
        full: Bool = false,
        scrollBy offset: Double = 0
    ) async throws {
        let (store, cache) = try await prepared(big: big, full: full)
        defer { _ = cache }
        store.setDetailTab(tab, for: pr)
        store.setDiffLayout(layout)
        let window = show(store: store, full: full)
        defer { window.orderOut(nil) }
        // Usadit: po prvním zobrazení se hierarchie skládá a to do měření nepatří.
        _ = spinMainRunLoop(seconds: 2)
        if offset > 0 {
            let scrolled = Self.scroll(window.contentView, by: offset)
            print("SONDA \(name): odscrollováno na \(scrolled)")
            // Po posunu se seznam přerovnává; usazení do měření nepatří.
            _ = spinMainRunLoop(seconds: 2)
        }

        let cpu = spinMainRunLoop(seconds: seconds)
        // Obsah okna se **vyžaduje**, ne dosazuje prázdným view: bez něj by počty prvků a bloků
        // vyšly nula a sonda by tvrdila „čisto“ nad oknem, do kterého se nepodívala.
        let root = try #require(window.contentView)
        print(String(
            format: "MĚŘENÍ %@: %.2f %% CPU hlavního vlákna v nečinném okně"
                + " (%d prvků, %d bloků kódu, %d souborů diffu, okno %.0f×%.0f)",
            name,
            cpu / seconds * 100,
            Self.descendants(of: root),
            Self.blocks(in: root),
            Self.files(in: store.diffState(for: pr)),
            window.frame.width,
            window.frame.height
        ))
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
    }

    private static func files(in state: DiffState?) -> Int {
        guard case .loaded(let diff, _) = state else { return 0 }
        return diff.files.count
    }

    /// Odscrolluje **ten nejvyšší** scroll view v okně, tedy seznam řádků diffu: sloupce dvojice
    /// jsou taky ve scroll view (kvůli ořezu, viz `DiffPairBlockContainer`), ale nízké.
    private static func scroll(_ root: NSView?, by offset: Double) -> String {
        guard let root, let scroller = tallestScroller(in: root) else { return "nenašel jsem scroller" }
        scroller.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scroller.reflectScrolledClipView(scroller.contentView)
        return "\(scroller.documentVisibleRect.origin) z obsahu \(scroller.documentView?.frame.height ?? 0)"
    }

    private static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }

    /// Kolik bloků kódu v okně doopravdy je. Bez toho čísla sonda netvrdí nic: nulové CPU nad
    /// oknem, ve kterém diff není, je stejně dobře prázdné okno — a přesně to se stalo, dokud
    /// se velikost okna nastavovala před kontrolérem (viz `show`).
    private static func blocks(in view: NSView) -> Int {
        view.subviews.reduce(view is DiffPairBlockContainer || view is DiffTextView ? 1 : 0) {
            $0 + blocks(in: $1)
        }
    }

    /// Okno postavené **jako `WindowGroup`**, ne přes `NSHostingController` s předepsaným
    /// rozměrem — a je to rozdíl, který se u #361 musel srovnat.
    ///
    /// Aplikace má na scéně `.windowResizability(.contentMinSize)`, takže si AppKit při **každém**
    /// průchodu `updateConstraints` říká hostující vrstvě o `minSize` a ta na to spustí
    /// `_sizeThatFits`, tedy **druhou aktualizaci grafu na jiné nabídce rozměru**. Předepsaný
    /// `frame(width:height:)` v `show(store:full:)` tuhle mašinerii zmrazí (minimum je konstanta),
    /// takže scéna, která by v okně hořela, může v sondě mlčet. Rozměr okna přitom předepisuje
    /// **okno**, ne obsah — tím se obchází ta past, kvůli které se `frame` do sondy dostal: obsah
    /// si rozměr určovat nesmí, jinak se okno scvrkne na hlavičku.
    private func show<Scene: View>(scene: Scene, minSizeFromContent: Bool = true) -> NSWindow {
        let host = NSHostingView(rootView: scene.background(Palette.background))
        // Kontrolní scéna to mít nesmí: její oscilace se do dotazu na minimum vejde celá
        // a AppKit ji zabije výjimkou („needing another Update Constraints … more than there
        // are views“) dřív, než se dá cokoli změřit. Kolo, které se hledá v aplikaci, se
        // naproti tomu roztáhne přes kola runloopu a proces jen hoří.
        host.sizingOptions = minSizeFromContent ? [.minSize] : []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 874),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1512, height: 874))
        window.setFrameOrigin(NSPoint(x: 0, y: 20))
        // Nad ostatními okny, ale bez aktivace — fokus si sonda brát nesmí (#350).
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return window
    }

    /// Syntetická osa: komentáře s **různě vysokým** obsahem. Materiál je od patnáctého kola
    /// #361 v `ConversationFixture`, protože z něj měří i `ConversationAxisShapeProbe` — dvě kopie
    /// téhož by se rozešly první úpravou a čísla ze dvou sond by pak nešla číst vedle sebe.
    private static func synthetic(comments: Int, shift: Int = 0) -> Conversation {
        ConversationFixture.conversation(comments: comments, shift: shift)
    }

    /// Osa složená z **vláken s úryvkem kódu** (#438) — dnes jediné místo v aplikaci, kde se
    /// `DiffLineView` doopravdy kreslí: v diffu se řádky slévají do bloků (`DiffRow.blocked(_:)`),
    /// kdežto úryvek na ose kreslí řádek po řádku.
    ///
    /// Hunky i komentáře jsou **skutečné** (`conversation-diff-hunks.json`), jen se opakují s novou
    /// identitou — měří se počet řádků v seznamu, ne jejich různost.
    private static func threaded(count: Int) throws -> Conversation {
        let text = try Fixture.text("gh/conversation-diff-hunks.json")
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(text.utf8))
        let source = try response.conversation(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)
        ).threads.items
        // Bez vláken s hunkem by se sonda dívala na osu bez jediného úryvku a nula by netvrdila nic
        // — tatáž past jako počet bloků kódu v okně.
        let origin = try #require(source.first { $0.diffHunk?.isEmpty == false })
        let threads = (0..<count).map { index in
            ReviewThread(
                id: "t\(index)",
                path: origin.path,
                line: origin.line,
                originalLine: origin.originalLine,
                side: origin.side,
                isResolved: origin.isResolved,
                isOutdated: origin.isOutdated,
                canResolve: origin.canResolve,
                canUnresolve: origin.canUnresolve,
                diffHunk: origin.diffHunk,
                comments: origin.comments
            )
        }
        return Conversation(
            viewer: "octocat",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false),
            events: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Okno se scénou **na obrazovce** — rozměr z té instance, na které se #361 chytila
    /// (1512×874).
    private func show(store: AppStore, full: Bool) -> NSWindow {
        let detail = PullRequestDetailView(
            store: store,
            pullRequest: Self.summary,
            submission: .constant(nil),
                merge: .constant(nil)
        )
        let controller = NSHostingController(
            rootView: Group {
                if full { ContentView(store: store) } else { detail }
            }
            // **Rozměr se scéně předepisuje**, jinak okno spadne na ideální výšku obsahu: diff
            // uvnitř `GeometryReader`u je pružný, takže ideální výška je hlavička plus pruh
            // záložek a v okně nezbyde ani jeden blok kódu. Měřeno: bez tohohle se okno usadilo
            // na 1512×265 a sonda hlásila nulu nad prázdnem.
            .frame(width: 1512, height: 874)
            .background(Palette.background)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 874),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        // Velikost se nastavuje **až za kontrolérem** — `contentViewController` přebije
        // `contentRect` (tatáž past jako u #350).
        window.setContentSize(NSSize(width: 1512, height: 874))
        window.setFrameOrigin(NSPoint(x: 0, y: 20))
        // Nad ostatními okny, ale bez aktivace — fokus si sonda brát nesmí (#350).
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return window
    }

    /// Store s načteným diffem. `big` přidá k fixture syntetické soubory, aby se seznam dostal na
    /// tisíce řádků; `full` přidá to, co v okně u #361 bylo — tři otevřené záložky, nálezy
    /// v diffu a konverzaci.
    private func prepared(big: Bool, full: Bool) async throws -> (store: AppStore, directory: TemporaryDirectory) {
        var text = try Fixture.text("gh/pr-diff-ordinary.diff")
        if big { text += Self.synthetic(files: 12, hunks: 4, lines: 40) }
        let gateway = FakeGitHubGateway(
            always: .success(Self.summaries),
            detail: .success(Self.detail),
            diffs: [.success(text)],
            conversations: [.success(try Self.conversation())]
        )
        let directory = try TemporaryDirectory()
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.loadDetail(for: Self.summary)
        await store.loadDiff(for: Self.summary)
        store.noteVisit(to: pr)
        guard full else {
            store.openTab(pr)
            return (store, directory)
        }
        await store.loadConversation(for: Self.summary)
        // Commity a kontroly patří do storu **taky**, jinak by se na těch záložkách měřilo
        // prázdno a nula by netvrdila nic — tatáž past jako u počtu bloků kódu.
        gateway.commits = Self.commits
        gateway.checks = Self.checks
        await store.loadCommits(for: pr)
        store.checks[pr] = Self.checks
        store.reviewRecords[pr] = Self.record
        // **Seznam se musí načíst tikem**, jinak `ContentView` detail vůbec nekreslí: záložka umí
        // jen PR, který je ve frontě. Bez tohohle sonda měřila okno bez jediného bloku kódu.
        await store.refresh()
        for summary in Self.summaries { store.openTab(summary.id) }
        store.activeTab = .pullRequest(pr)
        store.selection = pr
        return (store, directory)
    }

    /// Syntetický diff k fixture. Skutečný diff z veřejného repa je malý; cena rozvržení roste
    /// s počtem řádků v seznamu, takže se počet dorovnává tímhle.
    private static func synthetic(files: Int, hunks: Int, lines: Int) -> String {
        var out = ""
        for file in 0..<files {
            let path = "src/Module\(file)/Handler\(file).swift"
            out += "diff --git a/\(path) b/\(path)\n"
            out += "index 1111111..2222222 100644\n"
            out += "--- a/\(path)\n"
            out += "+++ b/\(path)\n"
            for hunk in 0..<hunks {
                let start = 1 + hunk * (lines + 20)
                out += "@@ -\(start),\(lines) +\(start),\(lines) @@ func handle()\n"
                for line in 0..<lines {
                    switch line % 5 {
                    case 3: out += "-    return legacy(value, \(line))\n"
                    case 4: out += "+    return modern(value, \(line))\n"
                    default: out += "     let value = compute(\(line))\n"
                    }
                }
            }
        }
        return out
    }

    private static func conversation() throws -> Conversation {
        let text = try Fixture.text("gh/conversation-threads.json")
        let response = try GhOutput.decoder.decode(GhConversationResponse.self, from: Data(text.utf8))
        return try response.conversation(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084)
        )
    }

    /// Nálezy **v tom diffu**, který se kreslí: cesta i řádek jsou z fixture, jinak by se bublina
    /// nezavěsila na žádný řádek a scénář „s bublinami“ by byl scénář bez nich.
    private static var record: ReviewRecord {
        ReviewRecord(
            pullRequest: summary.id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(
                findings: [
                    makeReported(file: "CLAUDE.md", line: 174, summary: "Nález na prvním souboru."),
                    makeReported(file: "README.md", line: 68, summary: "Nález na druhém souboru."),
                    makeReported(
                        file: "src/Module3/Handler3.swift",
                        line: 5,
                        summary: "Nález v syntetické části diffu."
                    ),
                ],
                headSha: "aaaa1111"
            )]
        )
    }

    /// Tři commity a tři kontroly — dost na to, aby na obou záložkách stál seznam, ne prázdný stav.
    private static let commits: [PullRequestCommit] = [
        PullRequestCommit(
            sha: "c82266c2dcc3285033605501837434af1faeddfe",
            message: "Warn instead of failing when issue fields can't be set",
            authorName: "imkp1",
            authorLogin: "imkp1",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_900_000),
            isMerge: false
        ),
        PullRequestCommit(
            sha: "96a469b6bd159d4cff137d5eab4d13ceee4c9807",
            message: "Merge branch 'trunk' into fix/13804",
            authorName: "Kumar Prateek",
            authorLogin: "imkp1",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_950_000),
            isMerge: true
        ),
        PullRequestCommit(
            sha: "aaaa1111",
            message: "Resolve deferred issue fields before creating the issue",
            authorName: "Jiří Novák",
            authorLogin: nil,
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_753_990_000),
            isMerge: false
        ),
    ]

    private static let checks: [PullRequestCheck] = [
        PullRequestCheck(
            name: "phpstan (level 8) / analyse",
            outcome: .failed,
            link: URL(string: "https://github.com/cli/cli/actions/runs/1/job/2"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 134)
        ),
        PullRequestCheck(
            name: "phpunit / 8.4",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 41)
        ),
        PullRequestCheck(name: "deploy", outcome: .skipped, link: nil, startedAt: nil, completedAt: nil),
    ]

    private static let summary = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13084),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/13084")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    /// Tři PR, tedy tři otevřené záložky jako v tom okně.
    private static let summaries: [PullRequestSummary] = [
        summary,
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13085),
            title: "Add --json to pr checks",
            author: "octocat",
            url: URL(string: "https://github.com/cli/cli/pull/13085")!,
            updatedAt: Date(timeIntervalSince1970: 1_754_001_000),
            state: .open
        ),
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 13086),
            title: "Fix pager handling on Windows",
            author: "hubot",
            url: URL(string: "https://github.com/cli/cli/pull/13086")!,
            updatedAt: Date(timeIntervalSince1970: 1_754_002_000),
            state: .open
        ),
    ]

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "aaaa1111",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "## Popis\n\nOdstavec s **tučným** a `inline kódem`."
    )
}
