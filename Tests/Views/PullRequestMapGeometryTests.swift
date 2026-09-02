import Testing

@testable import PRism

/// Geometrie pásu mapy PR (#501) — souřadnice segmentů a trefení kurzoru.
///
/// Existuje proto, že od opravy laggu je pás **jedna kresba**, ne řada tlačítek: plochu, na kterou
/// se dá kliknout, tedy nedělá SwiftUI, ale tenhle výpočet. Je to tatáž konstrukce jako
/// `DiffGutterGeometry` (#252) a testuje se ze stejného důvodu — **bez okna**.
///
/// Tři věci, které se tu dají pokazit potichu:
///
/// - **posun o mezeru.** Levá hrana segmentu se skládá ze součtu šířek **a mezer**; zapomenutá
///   mezera posune trefení o dva body na segment, takže u padesátého souboru míří klik o sto bodů
///   vedle — a na obrázku není nic vidět, protože kresba by se posunula stejně;
/// - **mezera, do které se nedá kliknout.** Dvoubodová mezera je čtvrtina nejmenšího segmentu;
///   kdyby padala „nikomu“, u úzkých segmentů by se na soubor kliklo jen občas;
/// - **trefení za koncem pásu.** Napravo od posledního segmentu už žádný soubor není, takže tam
///   musí vyjít `nil` — jinak by klik do prázdna skočil na poslední soubor.
@Suite("Geometrie pásu mapy PR (#501)")
struct PullRequestMapGeometryTests {
    /// Tři segmenty po deseti bodech s dvoubodovými mezerami: `0…10`, `12…22`, `24…34`.
    private let geometry = PullRequestMapGeometry(widths: [10, 10, 10], spacing: 2)

    @Test("Levé hrany se skládají ze šířek a mezer")
    func theStartsIncludeTheSpacing() {
        #expect(geometry.starts == [0, 12, 24])
        #expect(geometry.span(of: 0) == 0...10)
        #expect(geometry.span(of: 1) == 12...22)
        #expect(geometry.span(of: 2) == 24...34)
    }

    @Test("Index mimo pás nemá rozsah")
    func anIndexOutsideTheStripHasNoSpan() {
        #expect(geometry.span(of: -1) == nil)
        #expect(geometry.span(of: 3) == nil)
        #expect(PullRequestMapGeometry(widths: [], spacing: 2).span(of: 0) == nil)
    }

    /// **Vyčerpávající výčet přes celý pás i za jeho hranami.** Mezera se dělí **napůl** mezi
    /// oba sousedy, na krajích pásu jde trefná plocha až k hraně.
    @Test("Kurzor se trefí do segmentu", arguments: [
        (-1.0, Int?.none),
        (0.0, .some(0)),
        (5.0, .some(0)),
        (10.0, .some(0)),
        // Mezera 10…12 se dělí na 11: levá polovina prvnímu, pravá druhému.
        (10.5, .some(0)),
        (11.0, .some(1)),
        (12.0, .some(1)),
        (22.0, .some(1)),
        (23.0, .some(2)),
        (24.0, .some(2)),
        (34.0, .some(2)),
        // Za koncem pásu už soubor není.
        (34.5, nil),
        (100.0, nil),
    ])
    func theCursorHitsASegment(x: Double, expected: Int?) {
        #expect(geometry.index(at: x) == expected)
    }

    /// **Každý segment se dá trefit, a tvrdí se to přes pásmo počtů souborů** — u jednoho počtu
    /// to projde vždycky.
    ///
    /// Tohle je ten test, který v první podobě geometrie chyběl (#501, po druhém proklikání):
    /// tvrdilo se, **kde** segmenty leží, ne že **na každý** z nich jde kliknout. Chyba o půl
    /// mezery se přitom **kumuluje zleva doprava**, takže se u sedmi souborů neprojeví a u čtyřiceti
    /// pěti vyjde mimo — a **kresba by u toho byla v pořádku**, protože kreslí z týchž čísel.
    /// Proto se ověřuje **nakreslená** plocha: střed a **obě hrany**, protože na hranách se rozdíl
    /// o mezeru projeví první.
    ///
    /// Pásmo je vybrané podle skutečných PR: 1 a 2 jsou krajnosti (u jednoho se mezera
    /// nerozhoduje), 10 je ten počet, na kterém se to ohlásilo, 45 je `PRism#499` a 158
    /// `cli/cli#14320` — tedy počet, u kterého už mezera padá na nulu.
    @Test("Každý segment je trefitelný", arguments: [1, 2, 10, 45, 158])
    func everySegmentIsHittable(count: Int) throws {
        // Šířky schválně různé, ať se do dělení zapojí i minimum a vytlačování z podílu.
        let files = (1...count).map { file("src/File\($0).swift", lines: $0 * 7 % 400 + 1) }
        let segments = Policy.pullRequestMap(files: files).segments
        let width = 900.0
        let geometry = PullRequestMapGeometry(segments: segments, width: width, spacing: 2)

        #expect(geometry.count == count)
        for index in segments.indices {
            let span = try #require(geometry.span(of: index), "segment \(index) nemá rozsah")
            let middle = (span.lowerBound + span.upperBound) / 2
            #expect(geometry.index(at: middle) == index,
                    "střed segmentu \(index) z \(count) trefil \(String(describing: geometry.index(at: middle)))")
            #expect(geometry.index(at: span.lowerBound) == index,
                    "levá hrana segmentu \(index) z \(count) trefila \(String(describing: geometry.index(at: span.lowerBound)))")
            #expect(geometry.index(at: span.upperBound) == index,
                    "pravá hrana segmentu \(index) z \(count) trefila \(String(describing: geometry.index(at: span.upperBound)))")
        }
    }

    /// A **trefné plochy vykládají celý pás beze zbytku** — žádné mrtvé místo mezi nimi.
    /// Bez tohohle tvrzení by „každý segment je trefitelný“ mohlo platit a přitom by mezi
    /// segmenty zbývaly body, na kterých klik nedělá nic.
    @Test("Pás nemá mrtvá místa", arguments: [2, 10, 45])
    func theStripHasNoDeadSpots(count: Int) {
        let files = (1...count).map { file("src/File\($0).swift", lines: $0 * 13 % 300 + 1) }
        let segments = Policy.pullRequestMap(files: files).segments
        let geometry = PullRequestMapGeometry(segments: segments, width: 900, spacing: 2)

        // Krok po půl bodu přes celý pás: všude musí padnout nějaký segment.
        var x = 0.0
        while x <= geometry.end {
            #expect(geometry.index(at: x) != nil, "mrtvé místo na x = \(x) při \(count) souborech")
            x += 0.5
        }
    }

    @Test("Nad prázdným pásem se nic netrefí")
    func anEmptyStripHitsNothing() {
        let empty = PullRequestMapGeometry(widths: [], spacing: 2)
        #expect(empty.index(at: 0) == nil)
        #expect(empty.count == 0)
    }

    /// Soubor o daném počtu přidaných řádků. **Různé velikosti jsou podmínka**, ne kosmetika:
    /// se stejnými by se do dělení nezapojilo minimum ani vytlačování z podílu, tedy zrovna ty
    /// dvě větve, po kterých šířky přestávají být pravidelné.
    private func file(_ path: String, lines: Int) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: [DiffHunk(
                oldStart: 1,
                oldCount: 0,
                newStart: 1,
                newCount: lines,
                heading: "",
                lines: (0..<lines).map {
                    DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "řádek \($0 + 1)")
                }
            )],
            blobs: "aaa..bbb"
        )
    }

    /// Šířky si geometrie bere z `Policy`, ne z vlastního počítání — jinak by se pás kreslil podle
    /// jednoho pravidla a trefoval podle druhého.
    @Test("Šířky jsou ty z Policy")
    func theWidthsComeFromThePolicy() {
        let segments = Policy.pullRequestMap(files: MapScene.files).segments
        let expected = Policy.mapWidths(of: segments, in: 900, spacing: 2)
        let geometry = PullRequestMapGeometry(segments: segments, width: 900, spacing: 2)

        #expect(geometry.widths == expected)
        // A poslední segment končí přesně na dostupné šířce: součet šířek i mezer je celý pás.
        let last = try? #require(geometry.span(of: segments.count - 1))
        #expect(abs((last?.upperBound ?? 0) - 900) < 0.001, "pás končí na \(last?.upperBound ?? 0)")
    }
}
