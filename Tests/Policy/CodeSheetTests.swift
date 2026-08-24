import AppKit
import Testing

@testable import PRism

/// Velikost sheetu s kódem a s logem (#417) — **dva profily, jedna čistá funkce**.
///
/// Čisté funkce, takže vyčerpávajícím výčtem: oba druhy, malá i velká obrazovka, strop 2 700,
/// podlahy, uložená hodnota a rozhodnutí, jestli se má vůbec zapisovat.
///
/// Co se dá pokazit potichu a proč tu ty testy jsou:
///
/// - **jeden profil pro obojí** — roztažený log by pak otevíral takhle i hunk o devíti řádcích;
/// - **ideál bez ořezu o obrazovku** — na notebooku by sheet vyjel přes hrany;
/// - **zápis velikosti, se kterou se sheet sám otevřel** — nula („nic uloženého“) by se přepsala
///   konkrétním číslem a výchozí velikost by přestala vycházet z obrazovky;
/// - **kapacita řádku spočítaná bez odsazení** — patička by tvrdila jiný počet zalomených řádků,
///   než kolik jich je vidět.
@Suite("Velikost sheetu s kódem")
struct CodeSheetTests {
    /// Obrazovka, na které se to měřilo (`visibleFrame` 1512 × 883).
    private let screen = CGSize(width: 1_512, height: 883)

    // MARK: - Dva profily

    @Test("Hunk se otevře na 1 180 × 520 s podlahou 560 × 320")
    func opensAHunkAtTheMeasuredSize() {
        let sizing = Policy.codeSheetSizing(kind: .hunk, screen: screen)

        #expect(sizing.ideal == CGSize(width: 1_180, height: 520))
        #expect(sizing.floor == CGSize(width: 560, height: 320))
    }

    /// Šířku logu drží `Policy.codeSheetWidth` z #292 — obrazovka bez 152 bodů. Do #417 se
    /// neuplatnila, protože ji SwiftUI u sheetu zahazovalo.
    @Test("Log se otevře na šířku obrazovky bez okrajů, s podlahou 820 × 420")
    func opensALogAsWideAsTheScreenAllows() {
        let sizing = Policy.codeSheetSizing(kind: .log, screen: screen)

        #expect(sizing.ideal == CGSize(width: 1_360, height: 760))
        #expect(sizing.floor == CGSize(width: 820, height: 420))
    }

    /// **To hlavní tvrzení téhle sady**: log je na téhle obrazovce širší než hunk, a je to schválně —
    /// u hunku je šířka nad 1 180 prázdno nad diffem, u logu ubývá zalomených řádků až ke 1 360.
    @Test("Profily se od sebe liší, ne jen jménem")
    func theTwoProfilesDiffer() {
        let hunk = Policy.codeSheetSizing(kind: .hunk, screen: screen)
        let log = Policy.codeSheetSizing(kind: .log, screen: screen)

        #expect(log.ideal.width > hunk.ideal.width)
        #expect(log.ideal.height > hunk.ideal.height)
        #expect(log.floor.width > hunk.floor.width)
    }

    @Test("Na širokoúhlém monitoru se šířka logu zastropuje")
    func capsTheLogOnUltrawideScreens() {
        let sizing = Policy.codeSheetSizing(kind: .log, screen: CGSize(width: 3_440, height: 1_440))

        #expect(sizing.ideal.width == Policy.codeSheetWidthCap)
    }

    /// Sheet, který se nevejde, je horší než užší sheet — na malém displeji tedy rozhoduje displej,
    /// ne konstanta z většího.
    ///
    /// 1 200 × 800, ne ještě menší: pod tím se dostane ke slovu **podlaha**, a ta okraj přebíjí
    /// schválně (viz test níž). Na 900 bodech se tedy log otevře 820 široký, tedy o 40 bodů přes
    /// okraj — je to pořád lepší než sheet užší, než v jakém se dá log čít.
    @Test("Na malou obrazovku se vejde obojí")
    func fitsSmallScreens() {
        let small = CGSize(width: 1_200, height: 800)
        for kind in [CodeText.Kind.hunk, .log] {
            let sizing = Policy.codeSheetSizing(kind: kind, screen: small)
            #expect(sizing.ideal.width <= small.width - Policy.codeSheetScreenMargin)
            #expect(sizing.ideal.height <= small.height - Policy.codeSheetScreenMargin)
        }
    }

    /// **Podlaha přebíjí okraj.** Na displeji, kam se podlaha nevejde, je pořád lepší otevřít sheet
    /// v podlaze než v nule.
    @Test("Pod podlahu ideál nespadne ani na malinké obrazovce")
    func neverGoesBelowTheFloor() {
        for kind in [CodeText.Kind.hunk, .log] {
            let sizing = Policy.codeSheetSizing(kind: kind, screen: CGSize(width: 400, height: 300))
            #expect(sizing.ideal.width >= sizing.floor.width)
            #expect(sizing.ideal.height >= sizing.floor.height)
        }
    }

    /// Náhledy a testy obrazovku nemají — **žádná nula**, jinak by sheet neměl co kreslit.
    @Test("Bez známé obrazovky zůstane rozumná velikost")
    func worksWithoutAScreen() {
        #expect(Policy.codeSheetSizing(kind: .hunk, screen: nil).ideal == Policy.codeSheetHunkIdeal)
        #expect(Policy.codeSheetSizing(kind: .log, screen: nil).ideal.width == Policy.previousCodeSheetWidth)
        #expect(Policy.codeSheetSizing(kind: .log, screen: .zero).ideal.height == Policy.codeSheetLogIdealHeight)
    }

    // MARK: - Uložená velikost

    @Test("Uložená velikost přebije ideální")
    func prefersTheStoredSize() {
        let size = Policy.codeSheetSize(kind: .hunk, storedWidth: 900, storedHeight: 600, screen: screen)

        #expect(size == CGSize(width: 900, height: 600))
    }

    /// Natáhne se na ultrawide, otevírá na notebooku — a AppKit sám clampuje jen výšku.
    @Test("Uložená velikost se ořeže o okraje obrazovky")
    func clampsTheStoredSizeToTheScreen() {
        let size = Policy.codeSheetSize(kind: .log, storedWidth: 3_000, storedHeight: 1_800, screen: screen)

        #expect(size.width == screen.width - Policy.codeSheetScreenMargin)
        #expect(size.height == screen.height - Policy.codeSheetScreenMargin)
    }

    /// V `UserDefaults` může být cokoli — ruční editace, hodnota ze starší verze. Ořez je proto
    /// **při použití**, ne při zápisu.
    @Test("Nesmysl v nastavení se ignoruje", arguments: [0.0, -50.0, Double.nan, Double.infinity])
    func ignoresNonsenseInDefaults(value: Double) {
        let size = Policy.codeSheetSize(kind: .hunk, storedWidth: value, storedHeight: value, screen: screen)

        #expect(size == Policy.codeSheetHunkIdeal)
    }

    @Test("Uložená velikost pod podlahou se zvedne na podlahu")
    func liftsTinyStoredSizesToTheFloor() {
        let size = Policy.codeSheetSize(kind: .log, storedWidth: 200, storedHeight: 100, screen: screen)

        #expect(size == Policy.codeSheetLogFloor)
    }

    // MARK: - Kdy se zapisuje

    /// **Nejcennější test téhle sady** — tvrdí, že se něco *nestalo*. Velikost, o kterou si aplikace
    /// řekla sama, není volba uživatele.
    @Test("Velikost, se kterou se sheet otevřel, se nezapisuje")
    func doesNotStoreWhatTheAppAskedFor() {
        let opened = CGSize(width: 1_180, height: 520)

        #expect(Policy.codeSheetResize(kind: .hunk, opened: opened, measured: opened) == nil)
    }

    @Test("Natažená velikost se zapíše zaokrouhlená")
    func storesTheDraggedSize() {
        let resize = Policy.codeSheetResize(
            kind: .hunk,
            opened: CGSize(width: 1_180, height: 520),
            measured: CGSize(width: 1_000.4, height: 640.6)
        )

        #expect(resize == CGSize(width: 1_000, height: 641))
    }

    /// Podlaha se u každého profilu jiná — takže tatáž naměřená velikost je u hunku volba uživatele
    /// a u logu mezistav rozvržení.
    @Test("Pod podlahou svého profilu se nezapisuje")
    func rejectsSizesBelowTheirOwnFloor() {
        let measured = CGSize(width: 600, height: 350)
        let opened = CGSize(width: 1_180, height: 520)

        #expect(Policy.codeSheetResize(kind: .hunk, opened: opened, measured: measured) == measured)
        #expect(Policy.codeSheetResize(kind: .log, opened: opened, measured: measured) == nil)
    }

    @Test("Nesmyslná naměřená velikost se nezapisuje")
    func rejectsNonsenseMeasurements() {
        let opened = CGSize(width: 1_180, height: 520)

        #expect(Policy.codeSheetResize(
            kind: .hunk,
            opened: opened,
            measured: CGSize(width: Double.nan, height: 600)
        ) == nil)
    }

    // MARK: - Co se do šířky vejde

    /// **Tabulka ze sekce 28 návrhu, dopočítaná stejnou aritmetikou** — a `characterWidth` se měří
    /// na tom písmu, kterým se sází (mono 13 b = 8,036 bodu na znak na tomhle systému).
    @Test(
        "Kapacita řádku sedí s tabulkou v návrhu",
        arguments: [
            (560.0, 66), (820.0, 98), (1_080.0, 131), (1_180.0, 143),
            (1_360.0, 166), (1_600.0, 195), (2_000.0, 245), (2_700.0, 332),
        ] as [(CGFloat, Int)]
    )
    func matchesTheDesignTable(width: CGFloat, characters: Int) {
        #expect(Policy.codeSheetCharacters(
            width: width,
            characterWidth: SelectableCodeView.characterWidth
        ) == characters)
    }

    @Test("Bez písma a bez šířky je kapacita nula, ne záporné číslo")
    func handlesDegenerateWidths() {
        #expect(Policy.codeSheetCharacters(width: 1_180, characterWidth: 0) == 0)
        #expect(Policy.codeSheetCharacters(width: 0, characterWidth: 8) == 0)
        #expect(Policy.codeSheetCharacters(width: 10, characterWidth: 8) == 0)
    }

    // MARK: - Kolik řádků se nevešlo

    /// Kód se `CRLF` je běžný (`gh pr diff` na `microsoft/terminal` má `CRLF` na 70 řádcích ze 76),
    /// takže se dělí `TextLines` — s `split(separator: "\n")` by z hunku byl **jeden** řádek a věta
    /// v patičce by tvrdila, že se nevešel jediný.
    @Test("Zalomené řádky se počítají na jakémkoli zakončení", arguments: ["\n", "\r\n", "\r"])
    func countsWrappedLinesOnEveryLineEnding(ending: String) {
        let short = String(repeating: "a", count: 40)
        let long = String(repeating: "b", count: 200)
        let code = [short, long, short, long].joined(separator: ending)

        let overflow = Policy.codeSheetOverflow(
            code: code,
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        )

        #expect(overflow == CodeSheetOverflow(wrapped: 2, total: 4))
    }

    /// `nil`, ne nula: věta o zalomení u textu, který se celý vejde, je horší než žádná.
    @Test("Text, který se vejde, žádnou větu nedostane")
    func staysQuietWhenEverythingFits() {
        let code = "let a = 1\nlet b = 2"

        #expect(Policy.codeSheetOverflow(
            code: code,
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        ) == nil)
    }

    /// Řádek přesně o kapacitě se **vejde** — mez je „delší než“, ne „stejně dlouhý jako“.
    @Test("Řádek přesně o kapacitě se nepočítá jako zalomený")
    func treatsExactFitAsFitting() {
        let capacity = Policy.codeSheetCharacters(
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        )
        let exact = String(repeating: "x", count: capacity)
        let one = String(repeating: "x", count: capacity + 1)

        #expect(Policy.codeSheetOverflow(
            code: exact,
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        ) == nil)
        #expect(Policy.codeSheetOverflow(
            code: one,
            width: 1_180,
            characterWidth: SelectableCodeView.characterWidth
        ) == CodeSheetOverflow(wrapped: 1, total: 1))
    }

    @Test("Bez šířky se nepočítá nic")
    func staysQuietWithoutAWidth() {
        #expect(Policy.codeSheetOverflow(
            code: String(repeating: "x", count: 500),
            width: 0,
            characterWidth: SelectableCodeView.characterWidth
        ) == nil)
    }
}
