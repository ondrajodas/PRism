import Testing

@testable import PRism

/// Rozhodnutí, jestli se hover má zapsat do stavu (#358).
///
/// **Je to test na to, že se něco NEstane** — že se při nezměněné poloze **nezapíše**. Právě tím se
/// #358 rozbilo a právě tohle se rozbije potichu: bezpodmínečný zápis nic nerozbije funkčně, jen
/// z okna udělá 99 % CPU, a to na obrazovce nevypadá jako chyba, jen jako „appka je pomalá“.
///
/// Vyčerpává se výčtem, protože je to čistá funkce: čtyři kombinace `nil`/hodnota krát shoda/rozdíl.
@Suite("Zápis hoveru jen při změně (#358)")
struct HoverChangeTests {
    private let left = HoveredCell(index: 3, side: .left)
    private let right = HoveredCell(index: 3, side: .right)
    private let other = HoveredCell(index: 4, side: .left)

    // MARK: - Nezapisuje se

    /// Tohle je ta věta, na které stojí celá oprava.
    @Test("Tatáž buňka se nezapisuje")
    func sameCellIsNotWritten() {
        #expect(Policy.hoverChange(from: left, to: left) == .unchanged)
        #expect(Policy.hoverChange(from: other, to: other) == .unchanged)
    }

    /// Druhá polovina téhož: myš mimo blok hlásí `.ended` opakovaně, takže „pořád nic“ se taky
    /// nesmí zapisovat. Bez toho by smyčka držela i s kurzorem vedle bloku.
    @Test("Pořád nic se nezapisuje")
    func stayingEmptyIsNotWritten() {
        #expect(Policy.hoverChange(from: HoveredCell?.none, to: nil) == .unchanged)
    }

    // MARK: - Zapisuje se

    @Test("Jiný řádek se zapíše")
    func differentLineIsWritten() {
        #expect(Policy.hoverChange(from: left, to: other) == .write(other))
    }

    /// **Strana je součást hodnoty, ne jen řádek.** Kdyby se porovnával jen index, přejezd myši
    /// z levé poloviny do pravé na tomtéž řádku by pilulku nechal svítit na špatné straně — tedy
    /// tichá chyba v tom, kam se komentář zakotví.
    @Test("Jiná strana téhož řádku se zapíše")
    func differentSideIsWritten() {
        #expect(Policy.hoverChange(from: left, to: right) == .write(right))
    }

    @Test("Vjezd na blok a odjezd z bloku se zapíšou")
    func enteringAndLeavingAreWritten() {
        #expect(Policy.hoverChange(from: HoveredCell?.none, to: left) == .write(left))
        #expect(Policy.hoverChange(from: left, to: nil) == .write(nil))
    }

    // MARK: - Platí to na jakýkoli porovnatelný stav

    /// Pohled pod sebou drží `Int?`, split `HoveredCell?` — podmínka je jedna a je generická, takže
    /// se nemůže rozejít. Kdyby ji měl každý pohled vlastní, druhá kopie by na to čekala.
    @Test("Tatáž podmínka platí i pro pohled pod sebou")
    func unifiedStateUsesTheSameRule() {
        #expect(Policy.hoverChange(from: 7, to: 7) == .unchanged)
        #expect(Policy.hoverChange(from: 7, to: 8) == .write(8))
        #expect(Policy.hoverChange(from: Int?.none, to: nil) == .unchanged)
        #expect(Policy.hoverChange(from: 7, to: nil) == .write(nil))
    }
}
