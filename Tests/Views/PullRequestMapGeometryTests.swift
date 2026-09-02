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

    /// **Vyčerpávající výčet přes celý pás i za jeho hranami.** Mezera padá segmentu vlevo.
    @Test("Kurzor se trefí do segmentu", arguments: [
        (-1.0, Int?.none),
        (0.0, .some(0)),
        (5.0, .some(0)),
        (10.0, .some(0)),
        // Mezera 10…12 patří segmentu vlevo.
        (11.0, .some(0)),
        (12.0, .some(1)),
        (22.0, .some(1)),
        (23.0, .some(1)),
        (24.0, .some(2)),
        (34.0, .some(2)),
        // Za koncem pásu už soubor není.
        (34.5, nil),
        (100.0, nil),
    ])
    func theCursorHitsASegment(x: Double, expected: Int?) {
        #expect(geometry.index(at: x) == expected)
    }

    @Test("Nad prázdným pásem se nic netrefí")
    func anEmptyStripHitsNothing() {
        let empty = PullRequestMapGeometry(widths: [], spacing: 2)
        #expect(empty.index(at: 0) == nil)
        #expect(empty.count == 0)
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
