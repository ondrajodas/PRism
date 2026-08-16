import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Co sedmá záložka (#316) stojí v šířce pruhu — **změřeno na skutečném `PullRequestTabBar`u**.
///
/// Pruh nikde nemá `lineLimit`, takže se popisek pod hranicí **zalomí uvnitř záložky** a pruh
/// povyroste (v nejužším okně na 90 bodů místo 30). Sedmá záložka by tu hranici odsunula o dobrých
/// sto bodů, a tím by rozbila pásmo, ve kterém se pruh dneska ještě vejde. Zaplatila to pilulka
/// `+X −Y`: v úzkém pruhu se nekreslí (`ViewThatFits`), a protože stojí skoro přesně tolik co ta
/// záložka, zůstává hranice tam, kde byla.
///
/// Naměřeno tady, po jednom bodu šířky, na `NSHostingView.fittingSize`:
///
/// | Pruh | Šířka tabu, od které je jeden řádek | Okno (+ rail 53) |
/// |---|---|---|
/// | 6 záložek se všemi odznaky a `+X −Y` — dnešek (`origin/main`) | 884 b | 937 b |
/// | **7 záložek se všemi odznaky, `+X −Y` ustupuje** | **886 b** | **939 b** |
/// | 7 záložek bez odznaků | 729 b | 782 b |
/// | 7 záložek se všemi odznaky a `+X −Y` (odvozeno) | ~996 b | ~1049 b |
///
/// Poslední řádek je dopočet: pilulka `+X −Y` stojí **110 bodů** (změřeno na `origin/main`, kde se
/// pruh se všemi odznaky vejde od 774 b bez ní a od 884 b s ní). Sedmá záložka s odznakem stojí
/// **112 bodů** (886 − 774), tedy skoro přesně tolik — a přesně na tom ta výměna stojí.
///
/// **Specifikace měla o 17 bodů nižší absolutní čísla** (867/920 pro dnešek, 872/925 se sedmou
/// záložkou), protože je měřila na replice pruhu, ne na něm samotném. Rozdíl, o který jde, replika
/// odhadla dobře: předpovídala +5 bodů okna, ve skutečnosti jsou to **+2**.
///
/// Tři věci, které se tu dají pokazit potichu:
///
/// - **posunout hranici, od které se pruh vejde na jeden řádek.** Uživatel to pozná jedině tím, že
///   se mu při stažení okna pruh ztrojnásobí;
/// - **nezahodit `+X −Y`**, tedy nechat `ViewThatFits` vybrat pořád tu širší podobu;
/// - **zahodit ji i tam, kde je místo** — to by byl regres proti #174, a nikdo by si nevšiml,
///   protože chybějící údaj nekřičí.
///
/// **Měří se přes pásmo šířek, ne na jedné**: sazba se láme jen v pásmu, takže jediná šířka umí
/// projít náhodou. A na `NSHostingView`, ne `ImageRenderer`u — ten `ViewThatFits` vyhodnocuje jinak
/// než skutečné okno.
@MainActor
@Suite("Šířka pruhu záložek se sedmou záložkou (#316)")
struct TabStripWidthTests {
    /// Nejužší okno, ve kterém pruh se všemi odznaky ještě drží jeden řádek. Změřeno (939) a o bod
    /// zaokrouhleno nahoru, ať test nestojí přesně na hraně jednoho bodu sazby.
    private let singleRowWindow: CGFloat = 940

    /// Šířka tabu je okno minus rail. Panel s nálezy se do toho nepočítá — v `Commitech` ani
    /// v `Kontrolách` se nekreslí a nad pruhem záložek nestojí nikdy.
    private func tabWidth(ofWindow window: CGFloat) -> CGFloat { window - 53 }

    /// Výška pruhu na jednom řádku: odsazení 7 nahoře a 8 dole plus řádek textu. Měří se **na
    /// široké šířce**, tedy tam, kde se zalomit nemá — ať se nepíše zadrátované číslo, které se
    /// rozejde s první změnou sazby.
    private func singleRowHeight() -> CGFloat {
        height(at: 1600, badges: true, counts: (additions: 248, deletions: 96))
    }

    private func height(at width: CGFloat, badges: Bool, counts: (additions: Int, deletions: Int)?) -> CGFloat {
        let bar = PullRequestTabBar(
            selection: .constant(.commits),
            badge: badges ? Self.badge(of:) : { _ in nil }
        )
        .diffCounts(counts)
        .frame(width: width)

        let hosting = NSHostingView(rootView: bar)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    // MARK: - Kde se pruh vejde na jeden řádek

    /// **Hlavní tvrzení tohohle issue**: hranice se sedmou záložkou nesmí utéct nad to, kde byla se
    /// šesti. Dnešek je okno 937, tady se měří od 940 nahoru — tedy dva body ceny, ne sto dvanáct.
    ///
    /// Pásmo, ne jedna šířka: 1035 je hranice, kterou předpovídala specifikace **bez** té výměny,
    /// a 1100 je výchozí okno.
    @Test("Od okna 940 zůstává pruh na jednom řádku")
    func staysOnOneRowFromTheMeasuredFloor() {
        let single = singleRowHeight()

        for window in [singleRowWindow, 1000, 1035, 1100, 1400] as [CGFloat] {
            let width = tabWidth(ofWindow: window)
            let measured = height(at: width, badges: true, counts: (additions: 248, deletions: 96))
            #expect(measured == single,
                    "okno \(Int(window)) (tab \(Int(width)) b): pruh je \(measured) b místo \(single)")
        }
    }

    /// A totéž bez odznaků — PR, na kterém ještě nic nedorazilo. Tam se pruh vejde mnohem dřív
    /// (od tabu 729 b, tedy okna 782), takže se hranice měří zvlášť: kdyby se odznaky do měření
    /// vždycky počítaly, přehlédlo by se, že se pruh rozbil zrovna v tom nejběžnějším stavu.
    @Test("Bez odznaků se pruh vejde už od okna 785")
    func staysOnOneRowWithoutBadges() {
        let single = singleRowHeight()

        for window in [785.0, 900.0, 1100.0] as [CGFloat] {
            let measured = height(at: tabWidth(ofWindow: window), badges: false, counts: nil)
            #expect(measured == single, "okno \(Int(window)) bez odznaků: pruh je \(measured) b")
        }
    }

    /// Pod tou hranicí se pruh **zalomí, ne zkrátí** — a je to tak i dneska se šesti záložkami.
    /// Spravuje to až druhý stupeň (#318, ikony a popisek jen u aktivní), který sedmé záložce
    /// nepředchází: je to obrazovka rozbitá i bez ní.
    ///
    /// Test to tvrdí schválně. Kdyby někdo přidal `lineLimit(1)`, popisky by se začaly řezat
    /// (`Změněné soub…`), pruh by zůstal nízký a tenhle test by zčervenal — a to je správně, je to
    /// jiná obrazovka, než jakou má návrh.
    @Test("V nejužším okně se pruh zalomí, protože se popisky neřežou")
    func wrapsBelowTheFloor() {
        let single = singleRowHeight()
        let measured = height(at: tabWidth(ofWindow: 700), badges: true, counts: (additions: 248, deletions: 96))

        #expect(measured > single,
                "pruh se v okně 700 nezalomil — buď se popisky řežou, nebo se pruh přestal sázet")
    }

    // MARK: - Co se zahazuje a kde

    /// **Tvrdí, že se něco NEstalo**: v úzkém pruhu se `+X −Y` nenakreslí. Porovnává se render
    /// s počty proti renderu bez nich — když jsou pixel po pixelu stejné, pilulka tam není.
    ///
    /// Šířka je z pásma, ve kterém se ta výměna doopravdy odehrává: okno 1000 je nad hranicí
    /// jednoho řádku (939) a pod tím, co by pruh potřeboval i s pilulkou (~1049).
    @Test("V úzkém pruhu se rozsah změny nekreslí")
    func dropsTheDiffstatWhenItDoesNotFit() throws {
        let narrow = tabWidth(ofWindow: 1000)

        let withCounts = try render(width: narrow, counts: (additions: 248, deletions: 96))
        let without = try render(width: narrow, counts: nil)

        #expect(withCounts == without,
                "v šířce \(Int(narrow)) b se `+X −Y` nakreslilo — sedmá záložka pak stojí celých 112 bodů")
    }

    /// A druhá polovina téhož: **tam, kde je místo, se kreslit musí**. Bez toho by `ViewThatFits`
    /// mohl vybírat užší podobu pořád a #174 by tiše zmizela.
    @Test("V širokém pruhu se rozsah změny kreslí")
    func keepsTheDiffstatWhenItFits() throws {
        let wide = tabWidth(ofWindow: 1400)

        let withCounts = try render(width: wide, counts: (additions: 248, deletions: 96))
        let without = try render(width: wide, counts: nil)

        #expect(withCounts != without, "v šířce \(Int(wide)) b se `+X −Y` nenakreslilo")
    }

    // MARK: - Kreslení

    /// Pruh do bitmapy. `NSHostingView` a `cacheDisplay`, jako u ostatních sond — `ImageRenderer`
    /// vyhodnocuje `ViewThatFits` jinak než skutečné okno, takže by se měřilo něco jiného, než co
    /// je vidět.
    private func render(width: CGFloat, counts: (additions: Int, deletions: Int)?) throws -> Data {
        let bar = PullRequestTabBar(selection: .constant(.commits), badge: Self.badge(of:))
            .diffCounts(counts)
            .frame(width: width)
            .background(Palette.surface)

        let hosting = NSHostingView(rootView: bar)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Nejširší možná sada odznaků — tedy ten případ, na kterém se hranice měří. Vyčerpávající
    /// `switch` schválně: osmá záložka bez odznaku by měření tiše zlevnila.
    private static func badge(of tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        case .overview: .count(4)
        case .filesChanged: .count(7)
        case .commits: .count(7)
        case .conversation: .count(2)
        case .checks: .blocking(1)
        case .findings: .blocking(3)
        case .progress: .live
        }
    }
}
