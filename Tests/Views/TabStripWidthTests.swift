import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Kde se pruh záložek přepíná mezi podobami — **změřeno na skutečném `PullRequestTabBar`u**.
///
/// Pruh nikde nemá `lineLimit`, takže se popisek pod hranicí **zalomí uvnitř záložky** a pruh
/// povyroste. Do #318 se to dělo v každém okně užším než 939 bodů (v nejužším povoleném okně 700 byl
/// pruh 90 bodů místo 30) a byl to stav rozbitý i před sedmou záložkou — se šesti vycházelo 75.
/// **#318 to spravuje třetím stupněm**: ikony s odznaky a popisek jen u aktivní záložky.
///
/// Naměřeno tady, na `NSHostingView.fittingSize`, s odsazením pruhu (2 × 12 b) uvnitř čísla:
///
/// | Podoba | Ideální šířka tabu | Okno (+ rail 53) | S odznaky `888` |
/// |---|---|---|---|
/// | `full` — popisky a `+X −Y` | 1131–1133 b | 1184–1186 b | 1216–1218 b |
/// | `labels` — popisky, bez `+X −Y` | 1021–1023 b | 1074–1076 b | 1093–1095 b |
/// | `icons` — ikony, popisek u aktivní | 573–639 b | 626–692 b | 645–711 b |
/// | `compact` — jen ikony (#452) | 526 b | 579 b | 598 b |
///
/// Pásma jsou tam proto, že šířka závisí na tom, **která záložka je aktivní**: aktivní popisek je
/// polotučný a v `icons` je jediný, co se kreslí. Horní konec drží `Změněné soubory`, dolní
/// `Nálezy`; `compact` pásmo nemá, protože v ní není žádný popisek.
///
/// **Čísla se u #452 posunula o osmou záložku** (`Zeptat se`) a s nimi jedno rozhodnutí: do té
/// doby čtvrtá podoba **nebyla**, protože se na ni nedalo přijít (`icons` s odznaky `888` chtěly
/// 636 b, tedy okno 689, pod podlahou 700). S osmi záložkami chtějí **645 až 711 b** a tab
/// v nejužším okně má 647 — takže by se pruh v tom krajním stavu zalomil. `compact` je proto
/// od #452 poslední kandidát a s 598 b se vejde i tam.
///
/// Pro srovnání, co bylo naměřené u #316 (a co z toho pořád platí): 6 záložek se všemi odznaky
/// a `+X −Y` potřebovalo tab 884 b / okno 937, sedmá záložka to posunula o dva body na 886 / 939
/// tím, že v úzkém pruhu ustoupila pilulka `+X −Y` (110 b za záložku o 112 b). Ta výměna zůstává
/// prvním stupněm; #318 přidává druhý pod ní.
///
/// Čtyři věci, které se tu dají pokazit potichu:
///
/// - **zalomit pruh v úzkém okně.** Uživatel to pozná jedině tím, že se mu při stažení okna pruh
///   ztrojnásobí — a přesně tohle #318 opravuje;
/// - **začít popisky řezat** (`Změ…`) místo toho, aby zmizely. Zkrácený popisek nikam nepřeteče,
///   takže to nechytá měření přesahu ani výška pruhu — hlídá se to porovnáním **ideální šířky
///   vybrané podoby** s tím, kolik místa je;
/// - **zahodit popisky i tam, kde je na ně místo** — to by byl regres proti tomu, jak pruh vypadá
///   ve výchozím okně, a nikdo by si nevšiml, protože ikony vypadají úmyslně;
/// - **zahodit popisek u aktivní záložky**, tedy jedinou odpověď na „kde jsem“, kterou v úzkém
///   pruhu kromě podtržení je.
///
/// **Měří se přes pásmo šířek, ne na jedné**: sazba se láme jen v pásmu, takže jediná šířka umí
/// projít náhodou. A na `NSHostingView`, ne `ImageRenderer`u — ten `ViewThatFits` vyhodnocuje jinak
/// než skutečné okno.
@MainActor
@Suite("Podoby pruhu záložek podle šířky (#316, #318)")
struct TabStripWidthTests {
    /// Šířka tabu je okno minus rail. Panel s nálezy se do toho nepočítá — v `Commitech` ani
    /// v `Kontrolách` se nekreslí a nad pruhem záložek nestojí nikdy.
    private func tabWidth(ofWindow window: CGFloat) -> CGFloat { window - 53 }

    /// Nejužší povolené okno (`RootView`: `minWidth: 700`) — tedy ta šířka, pod kterou se uživatel
    /// nedostane, a proto ta, ve které se pruh nesmí zalomit.
    private let narrowestWindow: CGFloat = 700

    /// Výška pruhu na jednom řádku: odsazení 7 nahoře a 8 dole plus řádek textu. Měří se **na
    /// široké šířce**, tedy tam, kde se zalomit nemá — ať se nepíše zadrátované číslo, které se
    /// rozejde s první změnou sazby.
    private func singleRowHeight() -> CGFloat {
        height(at: 1600, selection: .commits, badges: true, counts: (additions: 248, deletions: 96))
    }

    private func height(at width: CGFloat, selection: PullRequestTab, badges: Bool,
                        counts: (additions: Int, deletions: Int)?) -> CGFloat {
        measure(bar(selection: selection, badges: badges, counts: counts).frame(width: width),
                width: width).height
    }

    // MARK: - Pruh se nezalomí

    /// **Hlavní tvrzení tohohle issue**: přes celé povolené pásmo šířek zůstává pruh na jednom
    /// řádku. Do #318 to platilo od okna 939 nahoru, teď od podlahy.
    ///
    /// Šířky jsou z pásma, ne jedna: 700 je podlaha, 940 a 1050 jsou hranice, na kterých se
    /// přepínají podoby, 1100 je výchozí okno.
    @Test("Pruh se nezalomí v žádném povoleném okně")
    func staysOnOneRowAcrossTheWholeBand() {
        let single = singleRowHeight()

        for selection in PullRequestTab.allCases {
            for window in [narrowestWindow, 760, 860, 940, 1000, 1050, 1100, 1400] as [CGFloat] {
                let width = tabWidth(ofWindow: window)
                let measured = height(at: width, selection: selection, badges: true,
                                      counts: (additions: 248, deletions: 96))
                let where_ = "okno \(Int(window)), tab \(Int(width)) b, aktivní \(selection.czechLabel)"
                #expect(measured == single, "\(where_): pruh je \(measured) b místo \(single)")
            }
        }
    }

    /// A totéž s odznaky, které jsou širší, než jaké se v okně kdy objeví: **trojmístné u všech**
    /// šesti počítaných záložek. Je to strop, ne běžný stav — a od #452 je to zároveň důvod, proč
    /// pruh **čtvrtou podobu má**: s osmi záložkami se `icons` v tomhle stropu do nejužšího okna
    /// nevejdou (645–711 b proti 647 b), kdežto `compact` ano (598 b).
    @Test("Nezalomí se ani s trojmístnými odznaky u všech záložek")
    func staysOnOneRowWithThreeDigitBadges() {
        let single = singleRowHeight()

        for selection in PullRequestTab.allCases {
            let measured = measure(
                PullRequestTabBar(selection: .constant(selection), badge: Self.wideBadge(of:))
                    .diffCounts((additions: 2480, deletions: 960))
                    .frame(width: tabWidth(ofWindow: narrowestWindow)),
                width: tabWidth(ofWindow: narrowestWindow)
            ).height
            #expect(measured == single,
                    "okno 700 s aktivní \(selection.czechLabel) a odznaky 888: \(measured) b")
        }
    }

    /// A bez odznaků — PR, na kterém ještě nic nedorazilo. Kdyby se odznaky do měření vždycky
    /// počítaly, přehlédlo by se, že se pruh rozbil zrovna v tom nejběžnějším stavu.
    @Test("Nezalomí se ani bez odznaků")
    func staysOnOneRowWithoutBadges() {
        let single = singleRowHeight()

        for window in [narrowestWindow, 785, 900, 1100] as [CGFloat] {
            let measured = height(at: tabWidth(ofWindow: window), selection: .commits,
                                  badges: false, counts: nil)
            #expect(measured == single, "okno \(Int(window)) bez odznaků: pruh je \(measured) b")
        }
    }

    // MARK: - Která podoba se vybere

    /// Celý žebřík naráz: v jaké šířce se kreslí která podoba. Porovnává se **pixel po pixelu**
    /// proti té podobě vykreslené napřímo (`bar(_:)`), takže test nezávisí na tom, čím se podoby
    /// od sebe liší — jen na tom, že se vybrala ta správná.
    ///
    /// Hranice jsou z naměřených ideálních šířek: `full` od tabu ~1131, `labels` od ~1021, pod tím
    /// `icons` (a pod ním `compact`, na který se s běžnými odznaky nedá přijít — viz test níž).
    /// Šířky v testu jsou uvnitř pásem, ne na hranách — hrana se hlídá měřením výšky výš.
    ///
    /// **Posunuly se u #452 o osmou záložku**: co bylo `full` v okně 1100, je dneska `labels`.
    /// Ustupuje tedy `+X −Y`, přesně jak to pořadí podob předepisuje — je to tatáž výměna, jakou
    /// zaplatila sedmá záložka u #316.
    @Test("V jaké šířce se kreslí která podoba")
    func picksTheStageThatFits() throws {
        let cases: [(window: CGFloat, layout: PullRequestTabBar.Layout)] = [
            (1400, .full),
            (1250, .full),
            (1150, .labels),
            (1080, .labels),
            (1000, .icons),
            (narrowestWindow, .icons),
        ]

        for (window, layout) in cases {
            let width = tabWidth(ofWindow: window)
            let whole = try render(bar(selection: .commits, badges: true,
                                       counts: (additions: 248, deletions: 96)), width: width)
            let expected = try render(
                PullRequestTabBar(selection: .constant(.commits), badge: Self.badge(of:))
                    .diffCounts((additions: 248, deletions: 96))
                    .bar(layout),
                width: width
            )
            #expect(whole == expected, "okno \(Int(window)) (tab \(Int(width)) b) nekreslí \(layout)")
        }
    }

    /// **Na každou podobu se musí dát přijít.** Vyčerpávající výčet přes `Layout.allCases`, ne tři
    /// vypsané případy: kdo přidá další podobu, musí ukázat šířku a data, při kterých se kreslí —
    /// a to je zrovna to, co u #318 rozhodlo, že čtvrtá podoba **nevzniká**, a u #452 (po přibytí
    /// osmé záložky) obráceně, že vzniknout **musí**.
    ///
    /// Šířka se bere jako ideální šířka té podoby, ale nikdy užší než podlaha okna: pod ni se
    /// uživatel nedostane, takže „vejde se do 500 b“ ještě neznamená, že to někdo uvidí.
    ///
    /// **`compact` se nedá ukázat s běžnými odznaky** a je to samo tvrzení, ne obcházení testu:
    /// s nimi se v nejužším okně vejdou `icons` (639 b proti 647 b), takže `compact` je stav pro
    /// **krajní data**, ne pro úzké okno. Ukazuje se proto s trojmístnými odznaky u všech záložek,
    /// tedy přesně tím stropem, kvůli kterému vznikla.
    @Test("Na každou podobu se dá přijít")
    func everyStageIsReachable() throws {
        for layout in PullRequestTabBar.Layout.allCases {
            let wide = layout == .compact
            let badge = wide ? Self.wideBadge(of:) : Self.badge(of:)
            let counts = wide ? (additions: 2480, deletions: 960) : (additions: 248, deletions: 96)
            let width = max(idealWidth(of: layout, selection: .commits),
                            tabWidth(ofWindow: narrowestWindow))
            let whole = try render(
                PullRequestTabBar(selection: .constant(.commits), badge: badge)
                    .diffCounts(counts),
                width: width
            )
            let expected = try render(
                PullRequestTabBar(selection: .constant(.commits), badge: badge)
                    .diffCounts(counts)
                    .bar(layout),
                width: width
            )
            #expect(whole == expected, "na \(layout) se v tabu \(Int(width)) b nedá přijít")
        }
    }

    /// **Tvrdí, že se něco NEstalo**: v úzkém pruhu se `+X −Y` nenakreslí. Vlastní test vedle
    /// žebříku výš — ten by prošel i tehdy, kdyby `full` přestala rozsah změny kreslit úplně,
    /// protože porovnává obě strany proti témuž kódu.
    ///
    /// Šířka je z pásma, ve kterém se ta výměna doopravdy odehrává: okno 1100 je nad hranicí
    /// popisků (1076) a pod tím, co by pruh potřeboval i s pilulkou (~1186). **Posunuto u #452**
    /// z okna 1000, kde se od osmé záložky kreslí už `icons`.
    @Test("V úzkém pruhu se rozsah změny nekreslí")
    func dropsTheDiffstatWhenItDoesNotFit() throws {
        let narrow = tabWidth(ofWindow: 1100)

        let withCounts = try render(bar(selection: .commits, badges: true,
                                        counts: (additions: 248, deletions: 96)), width: narrow)
        let without = try render(bar(selection: .commits, badges: true, counts: nil), width: narrow)

        #expect(withCounts == without,
                "v šířce \(Int(narrow)) b se `+X −Y` nakreslilo — sedmá záložka pak stojí celých 112 bodů")
    }

    /// A druhá polovina téhož: **tam, kde je místo, se kreslit musí**. Bez toho by `ViewThatFits`
    /// mohl vybírat užší podobu pořád a #174 by tiše zmizela.
    @Test("V širokém pruhu se rozsah změny kreslí")
    func keepsTheDiffstatWhenItFits() throws {
        let wide = tabWidth(ofWindow: 1400)

        let withCounts = try render(bar(selection: .commits, badges: true,
                                        counts: (additions: 248, deletions: 96)), width: wide)
        let without = try render(bar(selection: .commits, badges: true, counts: nil), width: wide)

        #expect(withCounts != without, "v šířce \(Int(wide)) b se `+X −Y` nenakreslilo")
    }

    // MARK: - Co se v ikonovém stupni nesmí ztratit

    /// **Popisky mizí, nekrátí se.** Zkrácený popisek nikam nepřeteče a pruh po něm zůstane nízký,
    /// takže na tuhle chybu měření výšky ani přesahu nestačí (poučení z #284). Hlídá se to
    /// porovnáním **ideální šířky vybrané podoby** s tím, kolik místa v tabu doopravdy je: když se
    /// podoba vejde celá, nemá se co smršťovat.
    ///
    /// **S běžnými odznaky se pořád vejdou `icons`** (573–639 b proti 647 b), takže se popisek
    /// aktivní záložky v nejužším okně neztrácí — `compact` je až pro krajní data (viz výš).
    @Test("V nejužším okně se popisky neřežou, protože se tam nekreslí")
    func theNarrowStageFitsWithoutShrinking() {
        let available = tabWidth(ofWindow: narrowestWindow)

        for selection in PullRequestTab.allCases {
            let ideal = idealWidth(of: .icons, selection: selection)
            #expect(ideal <= available,
                    "ikonový pruh s aktivní \(selection.czechLabel) chce \(ideal) b, k dispozici \(available) b")
        }
    }

    /// **Popisek u aktivní záložky zůstává i v ikonovém stupni** — jinak by se z pruhu nedalo
    /// přečíst, kde jsem, a zbylo by jen podtržení.
    ///
    /// Tvrdí se to šířkou, ne pixely: jediné, čím se ty dvě podoby liší, je **který** popisek se
    /// kreslí, takže rozdíl ideálních šířek je rozdíl délky těch dvou popisků. Nula by znamenala,
    /// že se nekreslí ani jeden.
    @Test("Aktivní záložka si popisek nechá")
    func theActiveTabKeepsItsLabel() {
        let long = idealWidth(of: .icons, selection: .filesChanged)
        let short = idealWidth(of: .icons, selection: .findings)

        #expect(long > short + 50,
                "`Změněné soubory` aktivní: \(long) b, `Nálezy` aktivní: \(short) b — popisek chybí")
    }

    /// A druhá strana: **ostatní popisky se v ikonovém stupni nekreslí**. Bez toho by `icons` byla
    /// jen jinak pojmenovaná `labels` a pruh by se v úzkém okně zalomil pořád.
    @Test("Neaktivní záložky popisek nemají")
    func theInactiveTabsDropTheirLabels() {
        let icons = idealWidth(of: .icons, selection: .commits)
        let labels = idealWidth(of: .labels, selection: .commits)

        #expect(icons < labels - 250,
                "ikonový pruh chce \(icons) b proti \(labels) b s popisky — sedm popisků nezmizelo")
    }

    /// A `compact` shodí **i ten poslední** (#452) — jinak by to byla jen jinak pojmenovaná
    /// `icons` a v krajním stavu by se pruh zalomil pořád.
    ///
    /// Tvrdí se to dvakrát: že je užší než `icons` u **nejdelšího** popisku, a že je **stejně
    /// široká u každé aktivní záložky** — druhé samo o sobě znamená, že se žádný popisek nekreslí.
    @Test("V nejužší podobě nemá popisek ani aktivní záložka")
    func theCompactStageDropsEveryLabel() {
        let compact = PullRequestTab.allCases.map { idealWidth(of: .compact, selection: $0) }

        #expect(Set(compact).count == 1, "šířka `compact` se mění s aktivní záložkou: \(compact)")
        #expect(compact[0] < idealWidth(of: .icons, selection: .filesChanged))
    }

    // MARK: - Měření

    private func bar(selection: PullRequestTab, badges: Bool,
                     counts: (additions: Int, deletions: Int)?) -> PullRequestTabBar {
        PullRequestTabBar(
            selection: .constant(selection),
            badge: badges ? Self.badge(of:) : { _ in nil }
        )
        .diffCounts(counts)
    }

    /// Kolik ta která podoba potřebuje — tedy to, co `ViewThatFits` porovnává s dostupnou šířkou.
    /// Měří se **jedna podoba** (`bar(_:)`), ne celý pruh: ten by vrátil šířku té, kterou vybral.
    private func idealWidth(of layout: PullRequestTabBar.Layout, selection: PullRequestTab) -> CGFloat {
        measure(
            PullRequestTabBar(selection: .constant(selection), badge: Self.badge(of:))
                .diffCounts((additions: 248, deletions: 96))
                .bar(layout),
            width: 4000
        ).width
    }

    private func measure(_ view: some View, width: CGFloat) -> CGSize {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    /// Pruh do bitmapy. `NSHostingView` a `cacheDisplay`, jako u ostatních sond — `ImageRenderer`
    /// vyhodnocuje `ViewThatFits` jinak než skutečné okno, takže by se měřilo něco jiného, než co
    /// je vidět.
    private func render(_ view: some View, width: CGFloat) throws -> Data {
        let hosting = NSHostingView(rootView: view.frame(width: width).background(Palette.surface))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Nejširší běžná sada odznaků. Vyčerpávající `switch` schválně: osmá záložka bez odznaku by
    /// měření tiše zlevnila.
    private static func badge(of tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        case .overview: .count(4)
        case .filesChanged: .count(7)
        case .commits: .count(7)
        case .conversation: .count(2)
        case .checks: .blocking(1)
        case .findings: .blocking(3)
        case .progress: .live
        case .ask: .live
        }
    }

    /// Odznaky nad tím, co v okně kdy nastane — trojmístné u **všech** počítaných záložek naráz.
    /// PR se stovkami souborů, commitů i komentářů zároveň je krajnost, a právě proto je to strop.
    private static func wideBadge(of tab: PullRequestTab) -> PullRequestTabBadge? {
        switch tab {
        case .progress, .ask: .live
        case .checks, .findings: .blocking(888)
        case .overview, .filesChanged, .commits, .conversation: .count(888)
        }
    }
}
