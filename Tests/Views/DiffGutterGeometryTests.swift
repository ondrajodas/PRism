import CoreGraphics
import Testing

@testable import PRism

/// Aritmetika gutteru — plochy, ve kterých se komentuje a táhne rozsah (#252).
///
/// Testuje se to proto, že se tím **nahradily views**: do #252 měl každý řádek vlastní
/// `Color.clear` s `onGeometryChange`, takže polohu plochy hlásil SwiftUI. Teď se počítá, a jediné,
/// co drží, že se počítá **na tomtéž místě, kde plocha byla**, je tenhle výčet — rozejít by se to
/// mohlo potichu: pilulka o pár bodů vedle je vidět jen tomu, kdo si ji zkusí trefit.
@Suite("Aritmetika gutteru diffu")
struct DiffGutterGeometryTests {
    /// Rámečky řádků tak, jak je hlásí sloupec dvojice: stejně vysoké, začínající na svislém
    /// insetu (`textContainerOrigin.y`), přes celou šířku bloku (#236).
    private func frames(count: Int, height: Double = 16, top: Double = 2, width: Double = 800) -> [DiffBlockLineFrame] {
        (0..<count).map { index in
            DiffBlockLineFrame(
                index: index,
                line: DiffLine(kind: .context, oldNumber: index + 1, newNumber: index + 1, text: "kód"),
                rect: CGRect(x: 0, y: top + Double(index) * height, width: width, height: height)
            )
        }
    }

    private func geometry(_ frames: [DiffBlockLineFrame], gutter: Double = 84, width: Double = 800) -> DiffGutterGeometry {
        DiffGutterGeometry(frames: frames, gutterWidth: gutter, blockWidth: width)
    }

    // MARK: - Sloupce

    /// Pravý sloupec začíná **o dělicí čáru za půlkou**, ne přesně v půlce — tak ho umisťuje
    /// kontejner (`(šířka − 1) / 2 + 1`) a odsud si tu hranici bere. Kdyby to byla rovná půlka,
    /// leží plocha na tažení o půl bodu vlevo od sloupce, ve kterém se kreslí čísla.
    @Test("Levá strana i pohled pod sebou začínají na levé hraně, pravá za dělicí čárou")
    func columnsStartWhereTheySit() {
        let geometry = geometry(frames(count: 3))

        #expect(geometry.x(of: nil) == 0)
        #expect(geometry.x(of: .left) == 0)
        #expect(geometry.x(of: .right) == 400.5)
        #expect(DiffGutterGeometry.rightColumnX(inBlockOfWidth: 800) == 400.5)
    }

    /// **Hranice stran a začátek pravého sloupce musí být tentýž bod.** Kdyby se rozešly, svítila
    /// by pilulka v jedné polovině a táhlo by se ve druhé — přesně ta třída chyby, kvůli které
    /// #157 omezovalo hledání na sloupec.
    @Test("Hranice stran sedí na začátek pravého sloupce")
    func theSideBoundaryMatchesTheColumn() {
        let geometry = geometry(frames(count: 3))

        #expect(geometry.side(atX: geometry.x(of: .right)) == .right)
        #expect(geometry.side(atX: geometry.x(of: .right) - 0.5) == .left)
        #expect(geometry.side(atX: 0) == .left)
        #expect(geometry.side(atX: 799) == .right)
    }

    // MARK: - Svislý rozsah

    /// Plocha na tažení začíná **na prvním řádku, ne na nule**: svislý inset patří bloku, ne
    /// řádkům (#236). Kdyby začínala na nule, byla by o ten inset delší a poslední řádek by měl
    /// citlivou plochu posunutou pod sebe.
    @Test("Svislý rozsah jde od prvního řádku po poslední")
    func spanCoversTheLines() throws {
        let rows = frames(count: 4, height: 16, top: 2)
        let span = try #require(geometry(rows).span)

        #expect(span.top == 2)
        #expect(span.height == 64)
    }

    @Test("Blok bez rozložených řádků žádný rozsah nemá")
    func spanIsNilWithoutFrames() {
        #expect(geometry([]).span == nil)
    }

    /// V pohledu pod sebou se dlouhý řádek zalomí, takže řádky mají různou výšku — rozsah se pak
    /// nesmí počítat jako `počet × výška`.
    @Test("Rozsah unese řádky různé výšky")
    func spanHandlesWrappedLines() throws {
        let rows = [
            DiffBlockLineFrame(index: 0, line: .blank, rect: CGRect(x: 0, y: 2, width: 800, height: 16)),
            DiffBlockLineFrame(index: 1, line: .blank, rect: CGRect(x: 0, y: 18, width: 800, height: 48)),
            DiffBlockLineFrame(index: 2, line: .blank, rect: CGRect(x: 0, y: 66, width: 800, height: 16))
        ]
        let span = try #require(geometry(rows).span)

        #expect(span.top == 2)
        #expect(span.height == 80)
    }

    /// Plocha na tažení nahradila šedesát ploch po řádcích, takže musí pokrývat **přesně** je —
    /// ani o řádek méně (poslední by se nedal táhnout), ani víc (táhlo by se pod blokem).
    @Test("Plocha na tažení pokrývá právě všechny řádky")
    func theDragAreaCoversEveryLine() throws {
        let rows = frames(count: 60)
        let span = try #require(geometry(rows).span)

        // Přetypování je schválně: `#expect` nad `Double` a `CGFloat` naráz vyhodnotí nepravdu
        // i pro dvě dvojky (vyzkoušeno), takže se srovnává jeden typ.
        #expect(span.top == Double(rows[0].rect.minY))
        #expect(span.top + span.height == Double(rows[59].rect.maxY))
    }

    // MARK: - Řádek pod bodem

    /// Interval je **zleva uzavřený a zprava otevřený**: na hranici dvou řádků patří bod tomu
    /// dolnímu. S uzavřeným koncem by na každé hranici vyhrály dva řádky a rozhodovalo by pořadí.
    @Test("Řádek pod bodem se hledá na půlotevřeném intervalu")
    func findsTheLineAtY() throws {
        let rows = frames(count: 3, height: 16, top: 2)
        let geometry = geometry(rows)

        #expect(geometry.line(atY: 2)?.index == 0)
        #expect(geometry.line(atY: 17.9)?.index == 0)
        #expect(geometry.line(atY: 18)?.index == 1)
        #expect(geometry.line(atY: 49.9)?.index == 2)
    }

    @Test("Nad prvním a pod posledním řádkem není nic")
    func findsNothingOutsideTheLines() {
        let geometry = geometry(frames(count: 3, height: 16, top: 2))

        #expect(geometry.line(atY: 1.5) == nil)
        #expect(geometry.line(atY: 50) == nil)
        #expect(geometry.line(atY: -10) == nil)
    }

    // MARK: - Rámečky ploch

    /// Rámeček plochy je **sloupec s čísly na výšku řádku** — tedy tolik, kolik měl `Color.clear`
    /// u řádku do #252. Šířka je gutter, ne šířka bloku: přes celý řádek se netáhne, aby to nebralo
    /// vybírání textu.
    @Test("Rámeček plochy je sloupec s čísly na výšku svého řádku")
    func rectOfALine() throws {
        let rows = frames(count: 3, height: 16, top: 2)
        let geometry = geometry(rows, gutter: 84, width: 800)

        #expect(geometry.rect(of: rows[1], on: .left) == CGRect(x: 0, y: 18, width: 84, height: 16))
        #expect(geometry.rect(of: rows[1], on: .right) == CGRect(x: 400.5, y: 18, width: 84, height: 16))
        #expect(geometry.rect(of: rows[1], on: nil) == CGRect(x: 0, y: 18, width: 84, height: 16))
    }

    /// Rámečky se hlásí do `DiffRowFrames` v souřadnicích **obsahu** diffu, tedy posunuté o polohu
    /// bloku. Tady se drží, že posun je jediný rozdíl — po přičtení polohy musí bod uvnitř řádku
    /// najít svou kotvu.
    @Test("Po posunu o polohu bloku sedí rámečky na souřadnice obsahu")
    func rectsTranslateIntoContentSpace() throws {
        let rows = frames(count: 3, height: 16, top: 2)
        let geometry = geometry(rows)
        let origin = CGPoint(x: 12, y: 1000)

        let rect = geometry.rect(of: rows[2], on: .right).offsetBy(dx: origin.x, dy: origin.y)

        #expect(rect == CGRect(x: 412.5, y: 1034, width: 84, height: 16))
        #expect(rect.contains(CGPoint(x: 420, y: 1040)))
    }

    // MARK: - Buňka pod myší (#358)

    /// Buňka se skládá **jednou operací**, a to je celý důvod, proč `hoveredCell(at:)` existuje:
    /// dva kroky u volajícího končily v tuplu, který se nedal porovnat.
    @Test("Buňka pod myší nese řádek podle `y` a stranu podle `x`")
    func hoveredCellCombinesLineAndSide() {
        let geometry = geometry(frames(count: 3, height: 16, top: 2), width: 800)

        #expect(geometry.hoveredCell(at: CGPoint(x: 10, y: 20)) == HoveredCell(index: 1, side: .left))
        #expect(geometry.hoveredCell(at: CGPoint(x: 600, y: 20)) == HoveredCell(index: 1, side: .right))
        // Nad sloupcem s čísly a nad pilulkou hover drží — rozhoduje jen `y` (#98, #157).
        #expect(geometry.hoveredCell(at: CGPoint(x: 0, y: 36)) == HoveredCell(index: 2, side: .left))
    }

    /// Mimo řádky není nic — ani nad prázdným blokem, který se ještě nerozložil.
    @Test("Mimo řádky buňka není")
    func hoveredCellIsEmptyOutsideRows() {
        #expect(geometry(frames(count: 3, height: 16, top: 2)).hoveredCell(at: CGPoint(x: 10, y: 999)) == nil)
        #expect(geometry([]).hoveredCell(at: CGPoint(x: 10, y: 10)) == nil)
    }

    /// **Na tomhle stojí oprava #358.** `Policy.hoverChange(from:to:)` umí zápis potlačit jedině
    /// tehdy, když tentýž bod nad tímtéž blokem vydá **rovnou** hodnotu. Kdyby si buňka nesla cokoli
    /// nestálého (identitu, čas, referenci), porovnání by nikdy nesedlo, zápis by proběhl každé kolo
    /// a smyčka by se vrátila — přitom by všechny ostatní testy zůstaly zelené.
    @Test("Tentýž bod dá tutéž hodnotu, takže se zápis dá potlačit")
    func hoveredCellIsStableForTheSamePoint() {
        let geometry = geometry(frames(count: 4, height: 16, top: 2), width: 800)
        let point = CGPoint(x: 600, y: 36)

        let first = geometry.hoveredCell(at: point)
        let second = geometry.hoveredCell(at: point)

        #expect(first != nil)
        #expect(first == second)
        #expect(Policy.hoverChange(from: first, to: second) == .unchanged)
    }
}
