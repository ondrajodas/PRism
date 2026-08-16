import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Podoba lišty nad rozsahovým diffem podle šířky tabu (#284).
///
/// **Počítá se, nevyjednává** (#220) — a proto se to dá otestovat výčtem místo renderu. Vzniklo to
/// z měření: `ViewThatFits` tady vybíral pokaždé nejširší variantu, protože `Text` je vodorovně
/// pružný, takže i s `lineLimit(1)` a `fixedSize` „se vešel“ — v tabu 648 bodů s rozloženým panelem
/// pak v liště stálo `Jen t…`.
@MainActor
@Suite("Lišta rozsahového diffu (#284)")
struct IncrementalDiffBarLayoutTests {
    /// Pásmo, ve kterém tab `Změněné soubory` doopravdy stojí: okno má podlahu 700, rail bere 52
    /// a panel se dá vytáhnout na 520.
    private let widths: [CGFloat] = [128, 200, 320, 420, 560, 720, 900, 1180, 1400]

    /// **Nejcennější tvrzení téhle sady**: ať je tab jakkoli úzký, vybraná podoba se do něj vejde.
    /// Kdyby se nevešla, lišta by se ořezala u pravé hrany — a ořízlo by se to poslední, tedy cesta
    /// zpátky na celý diff.
    @Test("Vybraná podoba se vejde do své šířky")
    func fitsEveryWidth() {
        for width in widths {
            let layout = IncrementalDiffBar.layout(in: width)
            let needed = IncrementalDiffBar.width(of: layout) + 28
            #expect(
                needed <= width || layout == .wayOut,
                "šířka \(Int(width)): podoba \(layout) potřebuje \(Int(needed))"
            )
        }
    }

    /// Podoby se **nesmí přeskakovat**: jak se tab zužuje, ubírá se po jednom kusu. Přeskočení by
    /// znamenalo, že se z lišty ztratí rozsah dřív, než je to nutné.
    @Test("Zužování ubírá po jednom kusu")
    func degradesInOrder() {
        let chosen = widths.map { IncrementalDiffBar.layout(in: $0) }
        let ranks = chosen.map { layout in
            IncrementalDiffBar.Layout.allCases.firstIndex(of: layout) ?? 0
        }
        #expect(ranks == ranks.sorted(by: >), "podoby nejdou od nejužší k nejširší: \(chosen)")
    }

    @Test("Nejširší tab dostane celou lištu")
    func showsEverythingWhenThereIsRoom() {
        #expect(IncrementalDiffBar.layout(in: 1400) == .full)
    }

    /// V nejužším tabu zbyde cesta ven. Je to jediné místo, odkud se z rozsahu vrátí na celý diff —
    /// bez tlačítka by se v něm dalo uvíznout do přepnutí PR.
    @Test("Nejužší tab má aspoň cestu ven")
    func keepsTheWayOut() {
        #expect(IncrementalDiffBar.layout(in: 128) == .wayOut)
    }

    /// Bez předané šířky (náhled, sonda) se kreslí celá — `nil` znamená „nikdo ji nenastavil“, ne
    /// „není místo“. Kdyby se z toho stala nejužší podoba, zmizel by rozsah všude, kde se šířka
    /// nepředává.
    @Test("Bez předané šířky se kreslí celá")
    func defaultsToFull() {
        #expect(IncrementalDiffBar.layout(in: nil) == .full)
    }

    /// Šířky se měří **skutečným písmem**, ne odhadem: česká věta má jinou šířku než anglická.
    /// Kdyby jedna z nich vyšla nulová (překlep v konstantě, jiné písmo), rozhodování by se sesypalo
    /// na jednu podobu a nikdo by si toho nevšiml.
    @Test("Každá podoba má nenulovou a rostoucí šířku")
    func measuresEveryLayout() {
        let widths = IncrementalDiffBar.Layout.allCases.map(IncrementalDiffBar.width(of:))
        #expect(widths.allSatisfy { $0 > 0 })
        #expect(widths == widths.sorted(by: >), "podoby nejsou seřazené od nejširší: \(widths)")
    }

    /// **Spočítaná šířka nesmí být menší než nakreslená** — tatáž pojistka jako u řady ovládání
    /// v pruhu, a ze stejného důvodu: zbytek téhle sady porovnává dvě strany **téhož** výpočtu,
    /// takže špatně změřený font by v něm prošel. Nález Copilota na #284 byl přesně tenhle druh
    /// chyby (plné tlačítko se měřilo regularem a kreslilo mediumem).
    @Test("Spočítaná šířka není menší než nakreslená")
    func measuresWhatItDraws() {
        let drawn = NSHostingView(
            rootView: Button(IncrementalDiffBar.wayOutLabel) {}.buttonStyle(.mini)
        ).fittingSize.width

        #expect(IncrementalDiffBar.width(of: .wayOut) >= drawn)
    }
}
