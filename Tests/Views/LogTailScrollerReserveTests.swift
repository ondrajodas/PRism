import AppKit
import Testing

@testable import PRism

/// Rezerva na vodorovný scroller u konce logu (#347).
///
/// **Měří se na tom, na čem se kreslí** (#236), a to je celý důvod, proč tahle sada existuje zvlášť
/// od `LogTailHeightTests`. Do #347 tu bylo jedno tvrzení, které rezervu porovnávalo s
/// `NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy)` — bylo zelené a hlídalo přitom
/// **jinou velikost scrolleru, než jakou okýnko kreslí**: `LogTailTextView.makeScrollView()` nechává
/// `NSScrollView`u výchozí `.regular`, a ten bere 17 bodů, ne 13. Konstanta tak vypadala odměřená
/// (měření skutečné bylo), jen odměřená vedle — a test, který se ptá API s ručně vybranou velikostí,
/// tu chybu zopakuje slovo za slovem.
///
/// Proto se tady nic nedopočítává. Postaví se `makeScrollView()`, dostane dokument širší než okýnko
/// a **odečte se, kolik z výšky ubylo**. Takový test se nedá splést stejnou úvahou dvakrát.
///
/// **Styl scrollerů se nechává usadit napřed** (`TestWait.awaitSettledScrollerStyle()`, #343): po
/// startu procesu je chvíli `overlay` a doresolvuje se na `legacy` až za pár kol smyčky. Zábor se
/// tady sice vynucuje **na instanci** (`scroll.scrollerStyle`), takže na okolním stavu nezávisí —
/// ale bez usazení by se okýnko mohlo přerovnat uprostřed měření, a to je zrovna ten flake, který
/// #343 rozmotávalo.
@MainActor
@Suite("Rezerva na vodorovný scroller u konce logu")
struct LogTailScrollerReserveTests {
    private let fontSize = CheckDetailView.logFontSize
    private let spacing = CheckDetailView.logLineSpacing

    /// Řádek, který se do okýnka nevejde na šířku — bez něj se vodorovný scroller neobjeví
    /// (`autohidesScrollers`) a nebylo by co měřit. Délka je z nejdelšího řádku ve změřeném Actions
    /// logu (`keboola/job-queue-daemon`, 2 258 znaků).
    private let longLine = String(repeating: "x", count: 2_258)

    /// Výška řádku z `FontMetric` (#407) — jedno měřidlo na proces, stejné jako v aplikaci
    /// a v `LogTailHeightTests`. Vlastní `NSLayoutManager` tu byl do #407 a je to tatáž třída, kvůli
    /// které padal plný běh: dvě čtení metriky písma v jednom procesu se pod zátěží umí rozejít.
    private var lineHeight: CGFloat {
        TestWait.settledFontMetric(.lineHeight, of: LogTailTextView.font(size: fontSize)) + spacing
    }

    /// **Tohle je to tvrzení, na kterém #347 stálo.** Zábor se nebere z API, ale z rozdílu výšky
    /// okýnka a jeho `contentView`u — tedy z toho, co scroller doopravdy sebral z místa na text.
    ///
    /// Měří se **oba styly**, protože měření jednoho je měření poloviny problému (#343): legacy
    /// zabírá, overlay plave nad obsahem. Rezervuje se ten horší z nich.
    @Test("Zábor legacy scrolleru je to, co si okýnko rezervuje")
    func legacyFootprintIsWhatWeReserve() throws {
        let legacy = try footprint(of: .legacy)
        #expect(
            abs(legacy - LogTailTextView.horizontalScrollerHeight) < 0.5,
            """
            legacy scroller bere \(legacy) bodů, rezervuje se \(LogTailTextView.horizontalScrollerHeight) \
            — o ty body je okýnko nižší, než kolik si spočítalo
            """
        )
    }

    /// **Overlay nebere nic**, a proto se rezervuje legacy: při overlay zbyde 17 bodů prázdna pod
    /// krátkým logem, kdežto naopak by se z obsahu ukusovalo. Zapsané je to jako tvrzení, ne jako
    /// komentář, protože na tom stojí volba „rezervuj horší případ“.
    @Test("Overlay scroller z výšky nebere nic")
    func overlayTakesNothing() throws {
        let overlay = try footprint(of: .overlay)
        #expect(overlay == 0, "overlay scroller ubral \(overlay) bodů, měl plavat nad obsahem")
        #expect(try overlay < footprint(of: .legacy), "rezervuje se horší z obou stylů")
    }

    /// Rezerva **odpovídá i API**, ale ptá se ho na tu velikost, kterou okýnko doopravdy kreslí —
    /// vyčtenou ze scrolleru, ne napsanou v testu. Kdyby někdo velikost scrolleru ve `makeScrollView()`
    /// změnil, spadne tohle i tvrzení výš; kdyby se změnila systémová metrika, spadne jen tohle,
    /// a z dvojice pádů se pozná, co se stalo.
    @Test("Rezerva odpovídá systému pro tu velikost scrolleru, která se kreslí")
    func reserveMatchesTheSystemForTheDrawnControlSize() throws {
        let scroll = LogTailTextView.makeScrollView()
        let size = try #require(scroll.horizontalScroller?.controlSize)
        #expect(size == .regular, "okýnko kreslí scroller ve velikosti \(size), ne .regular")
        #expect(LogTailTextView.horizontalScrollerHeight
            == NSScroller.scrollerWidth(for: size, scrollerStyle: .legacy))
    }

    /// **Okýnko se musí vejít do své vlastní výšky.** `height(forLines:…)` tvrdí, že si o tolik místa
    /// řekne, kolik text potřebuje **plus** scroller — takže když se od výšky odečte skutečný zábor
    /// scrolleru, musí zbyt aspoň celý dokument. S rezervou 13 zbývalo o 2 body méně (zbylé dva
    /// spolkl slack na prokládání posledního řádku), takže log, který se měl vejít celý, dostal
    /// svislý scroller a posunul se.
    @Test("Nezastropované okýnko unese celý svůj dokument", arguments: [1, 3, 5, 12, 29])
    func windowFitsItsOwnDocument(lines: Int) throws {
        let asked = LogTailTextView.height(
            forLines: lines,
            fontSize: fontSize,
            lineSpacing: spacing,
            limit: CheckDetailView.logMaxHeight
        )
        try #require(asked < CheckDetailView.logMaxHeight, "případ má být pod stropem, jinak netvrdí tohle")

        let (scroll, textView) = try drawn(lines: lines, height: asked, style: .legacy)
        let visible = scroll.contentView.bounds.height
        #expect(
            visible >= textView.frame.height - 0.5,
            """
            okýnko o \(asked) bodech ukáže \(visible) z dokumentu o \(textView.frame.height) \
            (\(lines) řádků) — chybí \(textView.frame.height - visible) bodů, takže se log, \
            na který si okýnko řeklo, do něj celý nevejde
            """
        )
        // Vejde-li se dokument celý, není proč scrollovat — a svislý scroller u logu, který se vejde,
        // je ta podoba, ve které se ty chybějící body ukážou uživateli.
        #expect(scroll.contentView.bounds.origin.y == 0, "okýnko odscrollovalo, i když se dokument vejde")
    }

    /// **Na stropu musí na text zbýt celý počet řádků** — jinak strop slibuje 30 řádků a ukáže 29.
    /// Tohle je tvrzení, které stojí na plných **4 bodech**: s rezervou 13 a stropem 441 vycházelo
    /// `(441 − 8 − 17) / 14` = 29,71 řádku.
    ///
    /// Počítá se z kresby, ne z konstant: `contentView` mínus odsazení textu, děleno výškou řádku.
    ///
    /// **Netvrdí se, že u horní hrany je vidět celý řádek** — to není pravda ani po opravě a nemá být:
    /// `2 × inset` leží uvnitř dokumentu a skáče se na jeho úplný konec, takže mřížka řádků na hranu
    /// viewportu nepadne. Změřeno u #347 na kresbě; rezerva rozhoduje o výšce, ne o zarovnání mřížky.
    @Test("Zastropované okýnko ukáže celý počet řádků")
    func cappedWindowShowsWholeLines() throws {
        let limit = CheckDetailView.logMaxHeight
        let (scroll, _) = try drawn(lines: 300, height: limit, style: .legacy)
        let usable = scroll.contentView.bounds.height - 2 * LogTailTextView.inset.height
        let lines = usable / lineHeight
        #expect(
            abs(lines - lines.rounded()) < 0.01,
            "na stropu \(limit) je vidět \(lines) řádku — necelý řádek je u horní hrany, tedy ten poslední"
        )
        #expect(lines.rounded() == 30, "na stropu \(limit) má být vidět 30 řádků, je \(lines)")
    }

    // MARK: - Měření

    /// Kolik scroller daného stylu ubere z výšky okýnka — **rozdílem**, ne dotazem.
    private func footprint(of style: NSScroller.Style) throws -> CGFloat {
        let height = CheckDetailView.logMaxHeight
        let (scroll, _) = try drawn(lines: 300, height: height, style: style)
        return height - scroll.contentView.bounds.height
    }

    /// Okýnko z `LogTailTextView.makeScrollView()`, vysázené a rozložené v okně mimo obrazovku.
    ///
    /// **Sazba jde přes `LogTailTextView.attributed(…)`** a okýnko přes `makeScrollView()`, tedy přes
    /// tytéž cesty, kterými to skládá aplikace. Kdyby si sonda view postavila vlastní kopií „nastavené
    /// stejně“, měřila by druhé místo, které se dá nastavit jinak — tatáž chyba, jakou #303 našlo
    /// u sondy z #292.
    ///
    /// **Styl se vynucuje na instanci** (`scroll.scrollerStyle`), ne přes `preferredScrollerStyle`:
    /// ten je systémový stav, který se mění připojením myši, takže by z něj byl test na náladu stroje
    /// místo na oba případy. Změřeno u #347, že instanční nastavení zabere i tehdy, když je systémový
    /// styl druhý — dva běhy sondy za sebou se usadily jednou na `legacy`, jednou na `overlay`, a zábor
    /// vyšel podle nastaveného stylu, ne podle systémového.
    ///
    /// Okno je **mimo obrazovku**: vedle sebe běží víc instancí PRismu a cizí okno je poslední, co má
    /// test rušit.
    private func drawn(
        lines: Int,
        height: CGFloat,
        style: NSScroller.Style
    ) throws -> (LogTailScrollView, NSTextView) {
        TestWait.awaitSettledScrollerStyle()

        let scroll = LogTailTextView.makeScrollView()
        scroll.scrollerStyle = style
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: height)

        let textView = try #require(scroll.documentView as? NSTextView)
        textView.textStorage?.setAttributedString(LogTailTextView.attributed(
            text(lines: lines),
            fontSize: fontSize,
            lineSpacing: spacing,
            color: Palette.ink2
        ))

        let window = NSWindow(
            contentRect: scroll.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scroll
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        defer { window.orderOut(nil) }

        // Skok na konec jako v aplikaci — kvůli němu se pozná, že necelý řádek zůstane u **horní**
        // hrany. Vynutí zároveň sazbu až na konec, takže `textView.frame.height` už není odhad
        // TextKitu.
        let coordinator = LogTailTextView.Coordinator()
        coordinator.needsJumpToEnd = true
        awaitLaidOut(scroll, coordinator: coordinator)
        dump(scroll, lines: lines, style: style)

        return (scroll, textView)
    }

    /// Uloží okýnko do PNG, když je nastavené `PRISM_RENDER_DIR` — jinak nedělá nic.
    ///
    /// **Je to tady proto, že v renderu celého tabu ta chyba vidět není** (`CheckLogRoomProbe`, #347):
    /// scrollery se v testovacím procesu usadí obvykle na `overlay`, a tam je rezerva čisté odsazení,
    /// takže se nikdy nic neuřízne. Vidět je to jedině u `legacy`, a ten se dá spolehlivě dostat jen
    /// vynucením **na instanci** — tedy přesně tak, jak to dělá tahle sada. Kdo si chce na ty body
    /// koukat, ať si sem pustí render; kdo chce čísla, má je v tvrzeních výš.
    private func dump(_ scroll: LogTailScrollView, lines: Int, style: NSScroller.Style) {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let label = style == .legacy ? "legacy" : "overlay"
        let name = "logtail-\(lines)-radku-\(label).png"
        // **Čísla se vypíšou vždycky, i když kresba selže**, a stojí to za pozornost: kdyby se název
        // souboru vypsal na jednom řádku s mírami, znělo by „selhalo uložení“ jako „změřilo se něco
        // jiného“. Míry jsou přitom platné bez ohledu na to, jestli se PNG povedlo napsat.
        print("""
            MĚŘENÍ okýnko \(lines) řádků, \(label): výška \(scroll.bounds.height), \
            na text zbylo \(scroll.contentView.bounds.height), \
            origin.y \(scroll.contentView.bounds.origin.y)
            """)
        do {
            try write(scroll, to: URL(filePath: directory).appending(path: name))
            print("MĚŘENÍ kresba → \(name)")
        } catch {
            // **Nepokládá to sadu, ale mlčet se nesmí.** Dump je diagnostika, takže jeho selhání není
            // pád tvrzení — jenže „render se neuložil“ nesmí být k nerozeznání od „nespustil jsem ho“.
            print("MĚŘENÍ kresba \(name) se neuložila: \(error.localizedDescription)")
        }
    }

    /// Vykreslí okýnko do PNG. **Pozadí se pro render zapne**, i když ho okýnko samo nekreslí: v aplikaci
    /// je pod ním `Palette.raised` z obalu ve SwiftUI, takže průhledný render by ukazoval jinou věc než
    /// okno — a hlavně by v něm nebylo poznat, kde má okýnko hranu, tedy zrovna to, co se měří.
    private func write(_ scroll: LogTailScrollView, to url: URL) throws {
        struct RenderFailed: LocalizedError {
            let errorDescription: String?
        }
        guard let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else {
            throw RenderFailed(errorDescription: "okýnko nevydalo bitmapu pro \(scroll.bounds)")
        }
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Palette.raised)
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        scroll.drawsBackground = false
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderFailed(errorDescription: "bitmapa se nedala zakódovat do PNG")
        }
        try png.write(to: url)
    }

    /// Nechá okýnko rozložit a skočit na konec — **pumpováním smyčky se stropem**, protože scrollery
    /// se dorovnávají jejím během a `waitUntil` by tady nepomohl (#296, #269). Vrací se hned, jak je
    /// zábor scrolleru vidět, takže zelený běh se nezdrží.
    private func awaitLaidOut(_ scroll: LogTailScrollView, coordinator: LogTailTextView.Coordinator) {
        let step: TimeInterval = 0.05
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        while ContinuousClock.now < limit {
            scroll.layoutSubtreeIfNeeded()
            LogTailTextView.jumpToEnd(in: scroll, coordinator: coordinator)
            // Rozložení je hotové, když `contentView` má výšku a scroller si o ni už řekl. Dokud je
            // `clipView` stejně vysoký jako okýnko, scroller se ještě neobjevil — a to je zrovna to,
            // co se tady měří.
            if scroll.contentView.bounds.height > 0,
               scroll.scrollerStyle == .overlay || scroll.contentView.bounds.height < scroll.bounds.height {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(step))
        }
        Issue.record("Nedočkalo se: okýnko se nerozložilo se scrollerem (strop \(TestWait.deadline)).")
    }

    /// Log o daném počtu řádků, s jedním, který se na šířku nevejde.
    private func text(lines: Int) -> String {
        var rows = (0..<max(lines, 1)).map { "PHPUnit \($0): assertion failed in JobRunnerTest.php" }
        rows[max(0, rows.count - 3)] = longLine
        return rows.joined(separator: "\n")
    }
}
