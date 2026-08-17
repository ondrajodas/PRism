import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Kde se okýnko s koncem logu otevře (#303).
///
/// **Na konci logu a vodorovně na nule.** To, kvůli čemu se log otevírá (selhaná assertace, exit
/// code), je na posledních řádcích — a se šesti tisíci řádků je začátek ocasu dvě stě obrazovek
/// daleko, takže okýnko otevřené na začátku je k nepoužití.
///
/// **Testuje se to přes `NSHostingView`, ne na samotném `NSScrollView`u**, a je to celý smysl téhle
/// sady: na scroll view, kterému se rozměr dá předem, skok fungoval i před opravou. Rozbité to bylo
/// jedině tou cestou, kterou jde aplikace — SwiftUI okýnko postaví ve chvíli, kdy log dorazí, a výšku
/// mu dá teprve při rozložení. Změřeno vedle sebe: s framem předem `origin.y = 71 680`, s framem až
/// po skoku `0`.
///
/// **Styl scrollerů se musí nechat usadit dřív, než se okýnko postaví** (#343) — jinak je z téhle
/// sady flake, a je to změřené: `main` 6× ze 6 zeleně, větev #339 jen 4× ze 7, pokaždé na týchž
/// číslech. Rozbor je u `awaitSettledScrollerStyle()`.
@MainActor
@Suite("Otevření konce logu")
struct LogTailOpeningTests {
    /// Log s **jedním velmi dlouhým řádkem**, ať je dokument širší než okýnko. Bez toho by se
    /// tvrzení o vodorovné nule nedalo pokazit.
    private var text: String {
        var lines = (0..<Policy.logTailLines).map { "PHPUnit \($0): assertion failed in JobRunnerTest.php" }
        lines[lines.count - 12] = String(repeating: "x", count: 2_258)
        return lines.joined(separator: "\n")
    }

    @Test("Okýnko se otevře na konci logu")
    func opensAtTheEndOfTheLog() throws {
        let (window, hosting) = hosted()
        defer { window.orderOut(nil) }

        let scroll = try settled(in: hosting)
        #expect(scroll.contentView.bounds.origin.y > 0, "okýnko zůstalo na začátku ocasu")
        // **Tvrdí se, že je vidět poslední řádek**, ne konkrétní `origin.y`: přesnou hodnotu určuje
        // odsazení textu a vodorovný scroller, takže by z ní byl test na aritmetiku AppKitu.
        // Poslední řádek je to, kvůli čemu se log otevírá.
        let visible = scroll.documentVisibleRect
        let last = try lastLineRect(in: scroll)
        #expect(
            visible.maxY >= last.maxY - 1,
            "poslední řádek logu není vidět: končí na \(last.maxY), vidět je po \(visible.maxY)"
        )
    }

    /// Vodorovně na nule: skok na konec dokumentu jinak zůstane u konce **nejdelšího** řádku, takže
    /// okýnko začíná uprostřed slova.
    @Test("Vodorovně začíná na nule")
    func startsAtTheLeftEdge() throws {
        let (window, hosting) = hosted()
        defer { window.orderOut(nil) }

        let scroll = try settled(in: hosting)
        let origin = scroll.contentView.bounds.origin
        #expect(origin.x == 0, "okýnko začíná uprostřed nejdelšího řádku (x = \(origin.x))")
        #expect(
            try #require(scroll.documentView?.frame.width) > scroll.contentView.bounds.width,
            "dokument se má do strany nevejít, jinak tvrzení o nule nic nedrží"
        )
    }

    // MARK: - Pomůcky

    /// Počká, až se v procesu **usadí styl scrollerů**, a teprve pak se smí okýnko postavit (#343).
    ///
    /// **Bez tohohle je z celé sady flake** a je to změřené, ne odhad. `NSScroller.preferredScrollerStyle`
    /// je po startu procesu chvíli `overlay` (`1`) a teprve za pár kol smyčky se doresolvuje na
    /// `legacy` (`0`) — a legacy scroller **místo doopravdy zabírá**. Když ta změna přijde *až po*
    /// dosazení cíle skoku, viewport se zmenší (`clip.h` 441 → 424) a `origin.y` **už nikdo
    /// nepřerovná**, protože další `layout()` přijít nemusí: okýnko zůstane 17 bodů nad koncem
    /// dokumentu, tedy o jednu řádku (`maxY` 84 006 → 83 989 proti poslednímu řádku na 84 002).
    ///
    /// **Je to artefakt harnessu, ne vada aplikace** — a právě tím se to liší od toho, jak zadání
    /// #343 tu chybu popisovalo. V aplikaci je styl scrollerů usazený dávno předtím, než se vůbec
    /// dá otevřít detail checku, takže se `jumpToEnd` nikdy nepočítá z výšky, která se mu pod rukama
    /// změní. Změřeno: když se styl nechá usadit předem, je poloha správná **od nultého kola**
    /// (`origin.y = 83 582`, `maxY = 84 006`) a **beze změny v aplikaci**.
    ///
    /// Proto se tady nesahá do `jumpToEnd`. Zamítnuto **dosadit cíl dvakrát** (to zadání #343 chtělo):
    /// obě kola by běžela v témže průchodu, tedy pořád před doresolvováním stylu, takže by na měřeném
    /// stavu nezměnila nic — a tři zelené běhy, na kterých ten návrh stál, byly shoda daná tím, které
    /// suity zrovna běžely v tom startovacím okně. Zamítnuto i **čekat na „konec je vidět“**: bez
    /// změny v aplikaci to dojede na 120s strop a celý běh má 184 issues (taky měřeno, #339).
    ///
    /// Čeká se pumpováním smyčky, protože styl se doresolvuje jejím během — strop je `TestWait.deadline`
    /// jako všude jinde (#296) a je to **jev se stropem**, ne pevný okamžik (#269).
    private func awaitSettledScrollerStyle() {
        let step: TimeInterval = 0.05
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        var previous: NSScroller.Style?
        var stableRounds = 0
        // Pět shodných kol: jedno by „usazeno“ tvrdilo i o hodnotě, kterou smyčka ještě nezměnila.
        while ContinuousClock.now < limit, stableRounds < 5 {
            RunLoop.current.run(until: Date().addingTimeInterval(step))
            let style = NSScroller.preferredScrollerStyle
            stableRounds = style == previous ? stableRounds + 1 : 0
            previous = style
        }
    }

    /// Okýnko v hierarchii SwiftUI, v okně mimo obrazovku — jako v aplikaci.
    ///
    /// **Styl scrollerů se usadí napřed** (#343), viz `awaitSettledScrollerStyle()`.
    private func hosted() -> (NSWindow, NSHostingView<some View>) {
        awaitSettledScrollerStyle()
        let scene = LogTailTextView(
            text: text,
            fontSize: CheckDetailView.logFontSize,
            lineSpacing: CheckDetailView.logLineSpacing,
            color: Palette.ink2
        )
        .frame(width: 900, height: CheckDetailView.logMaxHeight)

        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: CheckDetailView.logMaxHeight)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať test nikomu neskočí před oči — v paralelním vývoji stojí vedle sebe víc
        // instancí a cizí okno je poslední, co má test rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        return (window, hosting)
    }

    /// Čeká **na jev se stropem, ne na pevný okamžik** (#269): okýnko v hierarchii vznikne až po kole
    /// smyčky a skok přijde s jeho rozložením, což je pod zátěží jinak daleko než naprázdno.
    ///
    /// **Strop je `TestWait.deadline`** (#296; do té doby 40 kol po 50 ms, tedy 2 s — „o dva řády víc,
    /// než co se čeká“). Dva řády nestačí: u #296 se změřilo, že vyžádaná odmlka o 100 ms se pod třemi
    /// souběžnými buildy probouzí i za 8,6 s, tedy že zpoždění umí být **stonásobné**. Čeká se tady
    /// pumpováním smyčky, ne `waitUntil` — okýnko se rozloží jedině tak, že smyčka doopravdy poběží —,
    /// ale strop je tentýž a je na jednom místě. Cena je, že **skutečná** regrese spadne pomaleji;
    /// zelený běh se nezdrží, protože se vrací hned, jak skok přijde.
    private func settled(in hosting: NSView) throws -> LogTailScrollView {
        let step: TimeInterval = 0.05
        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        while ContinuousClock.now < limit {
            RunLoop.current.run(until: Date().addingTimeInterval(step))
            if let scroll = Self.scrollView(in: hosting), scroll.contentView.bounds.origin.y > 0 {
                return scroll
            }
        }
        // Sem se dojde, jen když se skok nepovedl — a to je právě ta chyba, kterou má sada chytat.
        // Okýnko se proto vrátí i tak, ať tvrzení výš řeknou **čím** se to pokazilo, ne jen že se
        // čekalo marně.
        return try #require(Self.scrollView(in: hosting), "okýnko se v hierarchii vůbec nenašlo")
    }

    /// Kde v dokumentu leží **poslední řádek** textu, v souřadnicích dokumentu.
    private func lastLineRect(in scroll: LogTailScrollView) throws -> NSRect {
        let textView = try #require(scroll.documentView as? NSTextView)
        let manager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        let length = textView.string.utf16.count
        let glyphs = manager.glyphRange(
            forCharacterRange: NSRange(location: max(0, length - 1), length: min(1, length)),
            actualCharacterRange: nil
        )
        var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    private static func scrollView(in view: NSView) -> LogTailScrollView? {
        if let scroll = view as? LogTailScrollView { return scroll }
        for child in view.subviews {
            if let found = scrollView(in: child) { return found }
        }
        return nil
    }
}
