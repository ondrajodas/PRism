import Foundation
import Testing

@testable import PRism

/// Zalomení labelů v panelu (#392) — čistá funkce, takže **výčet, ne reprezentanti**.
///
/// Šířky se předávají **umělé a rovné** (chip 100, mezera 10, `+N` 30, akce 50), takže se v testu
/// dá spočítat, co se kam vejde. Skutečné písmo se měří jinde (`PanelMetadataWidthTests`), a je to
/// schválně rozdělené: tady se ověřuje **pravidlo**, tam **rozměr**. Kdyby to bylo v jednom testu,
/// nešlo by po jeho spadnutí poznat, jestli se rozbilo rozhodování, nebo sazba.
@Suite("Zalomení labelů v panelu")
struct LabelChipsTests {
    /// Rovná čísla, ať se dá výsledek spočítat v hlavě: chip 100, mezera 10, `+N` 30, `+ label` 50.
    private static let metrics = Policy.LabelChipMetrics(
        spacing: 10,
        chipWidth: { _ in 100 },
        moreWidth: { _ in 30 },
        addWidth: 50
    )

    private static func labels(_ count: Int) -> [PullRequestLabel] {
        (0..<count).map { PullRequestLabel(name: "l\($0)", color: "ffffff") }
    }

    @Test("Co se vejde na jeden řádek, se nezalomí")
    func fitsOnOneRow() {
        let layout = Policy.labelChips(Self.labels(2), width: 210, metrics: Self.metrics, canAdd: false)

        #expect(layout.rows.count == 1)
        #expect(layout.labelRows == 1)
        #expect(layout.hidden == 0)
    }

    @Test("Co se nevejde, spadne na druhý řádek")
    func wrapsToTheSecondRow()  {
        let layout = Policy.labelChips(Self.labels(3), width: 210, metrics: Self.metrics, canAdd: false)

        #expect(layout.rows.count == 2)
        #expect(layout.hidden == 0)
    }

    /// **Strop dvou řádků labelů.** Třetí řádek ukusuje místo nálezům, takže se zbytek počítá,
    /// neořezává — z prostě ořezaného seznamu se nepozná, že něco chybí.
    @Test("Labely se zastaví na dvou řádcích a zbytek je +N")
    func stopsAtTwoRows() {
        let layout = Policy.labelChips(Self.labels(9), width: 210, metrics: Self.metrics, canAdd: false)

        #expect(layout.labelRows == 2)
        #expect(layout.hidden > 0)
        #expect(layout.rows.last?.contains(.more(layout.hidden)) == true)
    }

    /// **Ta past ze zákresu**: `+N` si na posledním řádku bere místo, takže se na něj vejde o jeden
    /// chip méně — jinak by `+N` spadlo na třetí řádek a strop by neplatil.
    ///
    /// Bez rezervy by se na druhý řádek vešly dva chipy (100 + 10 + 100 = 210) a `+N` by nemělo kam;
    /// s rezervou (30 + 10) je na řádku 170, tedy jeden chip. Ze šesti labelů jsou proto vidět tři
    /// a `+3` je vedle třetího.
    @Test("Rezerva na +N ubere z posledního řádku jeden chip")
    func reservesRoomForTheMoreBadge() {
        let layout = Policy.labelChips(Self.labels(6), width: 210, metrics: Self.metrics, canAdd: false)

        #expect(layout.labelRows == 2)
        #expect(layout.rows[0].count == 2, "první řádek rezervu nedrží")
        // Druhý řádek: jeden chip a `+N` vedle něj.
        #expect(layout.rows[1] == [.label(Self.labels(6)[2], maxWidth: nil), .more(3)])
        #expect(layout.hidden == 3)
        // A všechno na tom řádku se doopravdy vejde: 100 + 10 + 30 = 140 ≤ 170.
        #expect(100 + 10 + 30 <= 210)
    }

    /// Chip **širší než celý řádek** se ořeže — a mez je ta, na kterou se pak sází text. Puntík
    /// v chipu zůstává, o tom rozhoduje kresba.
    @Test("Chip širší než řádek se ořeže na šířku řádku")
    func trimsAChipWiderThanTheRow() {
        let metrics = Policy.LabelChipMetrics(
            spacing: 10,
            chipWidth: { _ in 400 },
            moreWidth: { _ in 30 },
            addWidth: 50
        )
        let layout = Policy.labelChips(Self.labels(1), width: 210, metrics: metrics, canAdd: false)

        #expect(layout.rows == [[.label(Self.labels(1)[0], maxWidth: 210)]])
    }

    /// **A ořez musí nechat místo na `+N`.** Tohle je ta druhá past ze zákresu (#390): prostý „ořež
    /// na šířku řádku“ dá chip přes celý druhý řádek, `+N` spadne na třetí a řádky labelů jsou tři.
    ///
    /// Rezerva je 30 + 10, takže ořez je 210 − 40 = 170 — a `+N` zůstane vedle chipu na tomtéž řádku.
    @Test("Ořez nechá místo na +N, takže třetí řádek nevznikne")
    func theTrimLeavesRoomForTheMoreBadge() {
        let metrics = Policy.LabelChipMetrics(
            spacing: 10,
            // První chip úzký, ostatní přes celý řádek — přesně scéna z výřezu na 240 bodech.
            chipWidth: { $0.name == "l0" ? 90 : 400 },
            moreWidth: { _ in 30 },
            addWidth: 50
        )
        let all = Self.labels(4)
        let layout = Policy.labelChips(all, width: 210, metrics: metrics, canAdd: false)

        #expect(layout.labelRows == 2)
        #expect(layout.rows[1] == [.label(all[1], maxWidth: 170), .more(2)])
        // Součet toho, co je na druhém řádku, se **vejde**: 170 + 10 + 30 = 210.
        #expect(170 + 10 + 30 <= 210)
    }

    /// **`+ label` neustoupí nikdy.** Když na poslední řádek nevyjde, vezme si vlastní — a do stropu
    /// dvou řádků se ten akční řádek nepočítá.
    ///
    /// Akce je tady širší (80), aby se doopravdy nevešla: na druhém řádku je 100 + 10 + 30 + 10, tedy
    /// 150, a 150 + 80 přeteče 210.
    @Test("+ label si vezme vlastní řádek, když se nevejde")
    func theActionTakesItsOwnRow() {
        let metrics = Policy.LabelChipMetrics(
            spacing: 10,
            chipWidth: { _ in 100 },
            moreWidth: { _ in 30 },
            addWidth: 80
        )
        let layout = Policy.labelChips(Self.labels(6), width: 210, metrics: metrics, canAdd: true)

        #expect(layout.labelRows == 2, "akční řádek se do stropu nepočítá")
        #expect(layout.rows.count == 3)
        #expect(layout.rows.last == [.add])
    }

    /// A když se vejde, **zůstane na řádku s `+N`** — vlastní řádek si bere jen z nutnosti, ne na
    /// jistotu: prázdné místo pod chipy ukusuje výšku nálezům.
    @Test("+ label zůstane vedle +N, když se vejde")
    func theActionStaysNextToTheMoreBadge() {
        let layout = Policy.labelChips(Self.labels(6), width: 210, metrics: Self.metrics, canAdd: true)

        #expect(layout.rows.count == 2)
        #expect(layout.rows.last?.suffix(2) == [.more(3), .add])
    }

    @Test("+ label zůstane na poslední řádce, když se vejde")
    func theActionStaysOnTheLastRow() {
        let layout = Policy.labelChips(Self.labels(1), width: 210, metrics: Self.metrics, canAdd: true)

        #expect(layout.rows.count == 1)
        #expect(layout.rows[0] == [.label(Self.labels(1)[0], maxWidth: nil), .add])
    }

    /// Na vlastním PR bez jediného labelu zůstane **samotné `+ label`** — jediná cesta, jak první
    /// label přidat.
    @Test("Bez labelů zůstane na vlastním PR samotné + label")
    func withoutLabelsOnlyTheActionRemains() {
        let layout = Policy.labelChips([], width: 210, metrics: Self.metrics, canAdd: true)

        #expect(layout.rows == [[.add]])
        #expect(layout.labelRows == 0)
    }

    /// **Na cizím PR se nekreslí nic** — prázdná sekce se pak nekreslí vůbec, o tom rozhoduje view.
    @Test("Bez labelů a bez akce nezbyde ani řádek")
    func withoutLabelsAndActionNothingIsDrawn() {
        let layout = Policy.labelChips([], width: 210, metrics: Self.metrics, canAdd: false)

        #expect(layout.rows.isEmpty)
        #expect(layout.hidden == 0)
    }

    /// Absurdně úzký panel nesmí chip **vyřadit**: mez se sráží nejvýš na jeden bod, ne na nulu ani
    /// do minusu. `frame` se zápornou šířkou rozhodí celé okno — tatáž past jako u uložené šířky
    /// panelu.
    @Test("Rezerva širší než panel chip nevyřadí")
    func neverProducesANegativeWidth() {
        let metrics = Policy.LabelChipMetrics(
            spacing: 10,
            chipWidth: { _ in 100 },
            moreWidth: { _ in 500 },
            addWidth: 50
        )
        let layout = Policy.labelChips(Self.labels(5), width: 60, metrics: metrics, canAdd: false)

        #expect(!layout.rows.isEmpty)
        for row in layout.rows {
            for chip in row {
                if case .label(_, let maxWidth) = chip, let maxWidth {
                    #expect(maxWidth > 0)
                }
            }
        }
    }

    /// Kolik labelů se schová, se počítá **přesně** — `+2` nad čtyřmi schovanými by tvrdilo, že jich
    /// je méně.
    @Test("Počet ve +N souhlasí s tím, co se nevešlo")
    func theHiddenCountIsExact() {
        let all = Self.labels(6)
        let layout = Policy.labelChips(all, width: 210, metrics: Self.metrics, canAdd: false)
        let drawn = layout.rows.flatMap { $0 }.count { if case .label = $0 { true } else { false } }

        #expect(drawn + layout.hidden == all.count)
    }
}
