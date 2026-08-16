import AppKit
import Foundation
import Testing

@testable import PRism

/// Řada odznaku a tlačítek pod odrážkami „od minule“ (#284) — **vejde se, nebo se zlomí do sloupce**.
///
/// **Počítá se, nevyjednává** (#220), a je to změřené rozhodnutí: `ViewThatFits` na tuhle řadu
/// nestačí, protože odznak i popisky tlačítek jsou vodorovně pružné a ve zúžené řadě se radši
/// zkrátí, než by nahlásily, že se nevejdou. Ověřeno vložením regrese — s `ViewThatFits` (i s pevnou
/// řadou) zůstala `OverviewWidthTests` **zelená**, protože se nic nenakreslilo mimo tab; jen v pruhu
/// stálo `Pust…`. Přetečení tedy tuhle třídu chyb nechytá a musí ji chytat tenhle výčet.
@MainActor
@Suite("Řada ovládání „od minule“ (#284)")
struct SinceLastVisitActionsTests {
    /// Šířky, ve kterých `Přehled` doopravdy stojí — tytéž jako v `OverviewWidthTests`, jen zúžené
    /// o odsazení tabu (32), protože tolik pruh dostane z prostředí.
    private let widths: [CGFloat] = [128, 200, 320, 420, 560, 720, 900, 1180].map { $0 - 32 }

    /// Všechny kombinace toho, co v řadě může stát. Osm i s prázdnou — a prázdná se nekreslí vůbec.
    private var combinations: [[SinceLastVisitView.ActionPart]] {
        let all = SinceLastVisitView.ActionPart.allCases
        return (0..<(1 << all.count)).map { mask in
            all.enumerated().compactMap { index, part in mask & (1 << index) != 0 ? part : nil }
        }
    }

    /// **Nejcennější tvrzení téhle sady.** Když pruh řekne „vejde se“, musí se to doopravdy vejít —
    /// jinak se popisek tlačítka zkrátí na `Pust…` a řada se přestane dát použít.
    @Test("Co se prohlásí za vejde-se, se doopravdy vejde")
    func neverPromisesMoreThanFits() {
        for width in widths {
            for parts in combinations where SinceLastVisitView.fits(parts, in: width) {
                let needed = parts.map(SinceLastVisitView.width(of:)).reduce(0, +)
                    + MiniButtonStyle.Metrics.spacing * Double(max(parts.count - 1, 0))
                #expect(
                    needed <= width - 24,
                    "šířka \(Int(width)), \(parts): potřebuje \(Int(needed)), zbývá \(Int(width - 24))"
                )
            }
        }
    }

    /// Nejužší `Přehled` (tab 128 bodů, tedy 96 v pruhu) neunese ani jedno tlačítko — takže se
    /// všechno zlomí do sloupce. Kdyby ne, byla by tam řada pahýlů.
    @Test("V nejužším Přehledu se řada zlomí")
    func stacksInTheNarrowest() {
        let narrow = 128 - 32.0
        #expect(!SinceLastVisitView.fits([.rerun], in: narrow))
        #expect(!SinceLastVisitView.fits([.badge, .rerun, .showAdded], in: narrow))
    }

    /// V širokém okně stojí odznak a obě tlačítka vedle sebe, jak to má návrh (`.since .row`).
    @Test("V širokém Přehledu stojí všechno v řadě")
    func keepsTheRowWhenThereIsRoom() {
        #expect(SinceLastVisitView.fits([.badge, .rerun, .showAdded], in: 1180 - 32))
    }

    /// Prázdná řada se nekreslí, takže „vejde se“ je u ní jediná pravdivá odpověď — a `nil` šířka
    /// znamená „nikdo ji nepředal“ (náhled, sonda), ne „není místo“.
    @Test("Prázdná řada a neznámá šířka se kreslí v řadě")
    func handlesTheTrivialCases() {
        #expect(SinceLastVisitView.fits([], in: 96))
        #expect(SinceLastVisitView.fits([.badge, .rerun, .showAdded], in: nil))
    }

    /// Šířky se měří **skutečným písmem**. Kdyby některá vyšla nulová (překlep v popisku, jiné
    /// písmo), řada by se prohlásila za vejde-se všude a nikdo by si toho nevšiml.
    @Test("Každý kus řady má nenulovou šířku")
    func measuresEveryPart() {
        for part in SinceLastVisitView.ActionPart.allCases {
            #expect(SinceLastVisitView.width(of: part) > 0, "\(part) má nulovou šířku")
        }
    }
}
