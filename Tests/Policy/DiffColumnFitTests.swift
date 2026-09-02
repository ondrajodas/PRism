import Testing

@testable import PRism

/// **Vejdou se pevné kolony diffu do šířky, kterou dostal?** (#503, oprava z proklikání)
///
/// Vada, kvůli které to vzniklo: `Policy.diffSideColumns` rozhodovala jen podle pohledu, takže se
/// v úzkém okně sešly strom (210), kód a okraj (300) v jednom `HStack`u — a `HStack` rozdíl, který
/// se nevejde, **přesype doprava**, tedy pod složený proužek panelu. Naměřeno v okně 700 (podlaha
/// `RootView`u): 35 bodů s okrajem, 16 bez něj, v obou pohledech.
///
/// Testuje se **přes pásmo šířek**, ne u jedné (#236): u širokého okna vada není a test by prošel.
/// Pásmo začíná na podlaze okna a jde po skutečných velikostech, ve kterých se aplikace používá.
@Suite("Kolony diffu se vejdou do okna (#503)")
struct DiffColumnFitTests {
    /// Šířky **diffu**, ne okna: okno bez railu (56) a bez panelu (38 složený / 246 a víc
    /// rozložený). Podlaha okna je 700, takže nejužší diff je řádově 400 — a pod to se jde
    /// schválně, aby se pásmo nespoléhalo na to, že rail a panel mají navždycky dnešní šířku.
    static let widths: [Double] = [200, 300, 360, 406, 500, 606, 726, 1006, 1306, 1606]

    @Test("Pevné kolony se vejdou vždycky", arguments: widths, [DiffLayout.unified, .split])
    func fixedColumnsFit(width: Double, layout: DiffLayout) {
        for hasMargin in [true, false] {
            let columns = Policy.diffSideColumns(layout: layout, hasMargin: hasMargin, available: width)
            let fixed = Policy.treeColumnWidth(expanded: columns.tree)
                + Policy.marginColumnWidth(shown: columns.margin)
            // **Tvrzení je „nepřeteče“, ne „zbyde podlaha“**: v pohledu vedle sebe se okraj
            // nezahazuje ani tehdy, když na kód zbývá málo (nález bez domova je horší), takže
            // podlahu slíbit nejde. Přetečení slíbit jde — a přesně to se rozbilo.
            #expect(
                fixed <= width,
                """
                Pevné kolony přetekly: šířka \(width), \(layout), okraj \(hasMargin) → \
                strom \(columns.tree) + okraj \(columns.margin) = \(fixed)
                """
            )
        }
    }

    @Test("Nález nikdy nezůstane bez domova", arguments: widths, [DiffLayout.unified, .split])
    func findingsAlwaysHaveAHome(width: Double, layout: DiffLayout) {
        let columns = Policy.diffSideColumns(layout: layout, hasMargin: true, available: width)
        // Karty existují. Když se okraj nekreslí, **musí** být rozložený panel — jinak by nález
        // z obrazovky zmizel a nikdo by se o něm nedozvěděl. Je to tvrzení o tom, že se něco
        // **nestalo**, a přesně takové se rozbíjejí potichu.
        #expect(
            columns.margin || columns.panel,
            "Šířka \(width), \(layout): okraj se nekreslí a panel je složený — nález je nikde"
        )
    }

    /// **Ve `Vedle sebe` se okraj drží i pod podlahou kódu** — panel je v tom pohledu složený
    /// (#188), takže by zahozený okraj znamenal nález, který na obrazovce není. Zahodí se teprve
    /// tehdy, když se **fyzicky** nevejde, a to je pod šířku samotné kolony; takový diff
    /// v aplikaci nevznikne (podlaha okna 700 dává diffu ~606).
    @Test("Vedle sebe se okraj drží, dokud se vejde fyzicky")
    func splitKeepsTheMargin() {
        for width in Self.widths where width > Policy.marginColumnWidth(shown: true) {
            let columns = Policy.diffSideColumns(layout: .split, hasMargin: true, available: width)
            #expect(columns.margin, "Šířka \(width): ve Vedle sebe okraj zmizel")
            // A strom se v něm složí, protože ten dům pro nález není.
            #expect(!columns.tree)
        }
        // Pod šířkou kolony okraj padá — a panel ho **musí** převzít, i když je to split.
        let tiny = Policy.diffSideColumns(layout: .split, hasMargin: true, available: 200)
        #expect(!tiny.margin)
        #expect(tiny.panel, "Okraj padl a panel zůstal složený — nález je nikde")
    }

    @Test("Strom jde první, okraj až po něm")
    func theTreeGoesFirst() {
        // Šířka, na které se pod sebou vejde okraj i kód, ale ne k tomu strom:
        // 360 (podlaha kódu) + 300 (okraj) = 660, strom by chtěl dalších 210.
        let tight = Policy.diffSideColumns(layout: .unified, hasMargin: true, available: 700)
        #expect(!tight.tree)
        #expect(tight.margin)
        // A šířka, na které se nevejde ani okraj: panel ho převezme.
        let tiny = Policy.diffSideColumns(layout: .unified, hasMargin: true, available: 500)
        #expect(!tiny.tree)
        #expect(!tiny.margin)
        #expect(tiny.panel)
    }

    @Test("Bez změřené šířky se rozhoduje jako dřív")
    func withoutAWidthNothingCollapses() {
        // `nil` je „nikdo ji nezměřil“ — `DiffView` hostovaný mimo okno by jinak přišel o kolony.
        let unified = Policy.diffSideColumns(layout: .unified, hasMargin: true, available: nil)
        #expect(unified.tree)
        #expect(unified.margin)
        #expect(!unified.panel)
        let split = Policy.diffSideColumns(layout: .split, hasMargin: false, available: nil)
        #expect(!split.tree)
        #expect(!split.panel)
        #expect(!split.margin)
    }

    // MARK: - Šířka kolony kódu (#546)

    /// **Kolona kódu je štěrbina bez toho, co v ní stojí** — a je to tatáž aritmetika, jakou
    /// provádí `HStack` v `DiffView`. Kdyby se rozešly, předaná šířka by mluvila o jiné ploše než
    /// ta, na které se doopravdy sází, a byla by z toho #546 v jiné podobě.
    @Test("Kolona kódu je štěrbina bez stromu, okraje a mezery", arguments: widths,
          [DiffLayout.unified, .split])
    func theCodeColumnIsWhatTheStackLeaves(width: Double, layout: DiffLayout) throws {
        for hasMargin in [true, false] {
            let columns = Policy.diffSideColumns(layout: layout, hasMargin: hasMargin, available: width)
            let column = try #require(Policy.diffCodeColumnWidth(available: width, columns: columns))
            let sides = Policy.treeColumnWidth(expanded: columns.tree)
                + Policy.marginColumnWidth(shown: columns.margin)
                + Policy.codeColumnTrailingGap
            #expect(column == max(width - sides, 0), """
                Šířka \(width), \(layout), okraj \(hasMargin): kolona \(column), \
                ale po kolonách zbývá \(width - sides)
                """)
        }
    }

    /// **Mezera před pravou kolonou se odečítá** (#503) — je mimo `fillingSlot`, takže od štěrbiny
    /// ubírá. Bez toho by předaná šířka byla o šest bodů větší než plocha, kterou `HStack` dá.
    @Test("Mezera před pravou kolonou se od kolony odečte")
    func theTrailingGapIsSubtracted() throws {
        let columns = Policy.diffSideColumns(layout: .split, hasMargin: false, available: 1_010)
        let column = try #require(Policy.diffCodeColumnWidth(available: 1_010, columns: columns))
        // Štěrbina 1010, složený strom 34, žádný okraj → 1010 − 34 − 6 = 970. To je číslo
        // změřené na živém okně 1100 × 700 u #546.
        #expect(column == 970)
    }

    /// **Nikdy záporná, a nikdy `nil` u změřené štěrbiny.** `frame` se zápornou šířkou je
    /// nedefinovaný stav, takže odečítání má podlahu; `nil` znamená jedinou věc — štěrbinu nikdo
    /// nezměřil (náhledy, sondy), a tam se obsah chová jako do #546.
    @Test("Nikdy záporná, bez štěrbiny nic", arguments: [DiffLayout.unified, .split])
    func neverNegative(layout: DiffLayout) {
        for width in [0.0, 10, 40, 200, 340] {
            for hasMargin in [true, false] {
                let columns = Policy.diffSideColumns(
                    layout: layout,
                    hasMargin: hasMargin,
                    available: width
                )
                let column = Policy.diffCodeColumnWidth(available: width, columns: columns)
                #expect(column ?? 0 >= 0, "Šířka \(width), \(layout): kolona \(column ?? -1)")
            }
        }
        let unmeasured = Policy.diffSideColumns(layout: layout, hasMargin: true, available: nil)
        #expect(Policy.diffCodeColumnWidth(available: nil, columns: unmeasured) == nil)
    }

    @Test("Šířky kolon má na starost Policy, ne dvě konstanty ve views")
    func widthsComeFromPolicy() {
        // Rozhodnutí i kresba musí čísla brát z jednoho místa — dvě pravdy o jedné šířce se
        // rozejdou při první úpravě a přesně tím vada vznikla.
        #expect(DiffView.treeWidth == Policy.treeColumnWidth(expanded: true))
        #expect(DiffMarginView.width == Policy.marginColumnWidth(shown: true))
    }
}
