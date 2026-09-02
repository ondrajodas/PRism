import CoreGraphics

/// Kde v pásu mapy PR leží který segment (#501).
///
/// **Proč to je čistý typ a ne views.** První podoba pásu kreslila segment jako `Button`
/// s nápovědou, dvěma `overlay`y a `contentShape` — u PR o 158 souborech je to **158 tlačítek
/// a přes tisíc views v hlavičce**, které se při každém přerovnání okna znovu umisťují. Změřeno
/// na ostrých datech (`cli/cli#14320`, 158 souborů): přerovnání okna stálo **70 ms** proti 14 ms
/// s ablovaným pásem a přepnutí tabu **bez diffu** 162 ms proti 57. Je to tatáž úvaha jako u
/// `DiffGutterGeometry` (#252) — *nevyjednává se ani počet prvků*: plochu, gesto a nápovědu
/// obstarává **jedna** kresba a poloha se **spočítá**.
///
/// Aritmetika žije tady, protože se tím dá **změřit a otestovat bez okna** — stejný důvod, proč je
/// `widths(in:count:)` u `ProportionalColumns` `internal`. Pravidlo o šířkách samotné zůstává
/// v `Policy.mapWidths(of:in:spacing:minimum:)`; tenhle typ z něj skládá souřadnice.
struct PullRequestMapGeometry {
    /// Šířky segmentů v bodech, jak je vydala `Policy`.
    let widths: [Double]
    /// Levé hrany segmentů. Předpočítané, ne dopočítávané při každém dotazu: kresba i trefení se
    /// ptají na každý segment, takže by ze součtu prefixů byl kvadrát.
    let starts: [Double]
    let spacing: Double

    init(segments: [PullRequestMapSegment], width: Double, spacing: Double) {
        // **Mezeru rozhoduje `Policy`, ne volající** — nad ~160 soubory padá na nulu, aby z pásu
        // nebyla tečkovaná linka. Kdyby si ji geometrie dosadila sama, kreslila by mezery, které
        // se do součtu šířek nevešly.
        self.init(
            widths: Policy.mapWidths(of: segments, in: width, spacing: spacing),
            spacing: Policy.mapSpacing(count: segments.count, in: width, spacing: spacing)
        )
    }

    /// Ze změřených šířek — pro testy a pro sondu, které si šířky skládají samy.
    init(widths: [Double], spacing: Double) {
        self.widths = widths
        self.spacing = spacing
        var x = 0.0
        var starts: [Double] = []
        starts.reserveCapacity(widths.count)
        for width in widths {
            starts.append(x)
            x += width + spacing
        }
        self.starts = starts
    }

    var count: Int { widths.count }

    /// Vodorovný rozsah segmentu. `nil` u indexu, který v pásu není.
    func span(of index: Int) -> ClosedRange<Double>? {
        guard widths.indices.contains(index) else { return nil }
        return starts[index]...(starts[index] + widths[index])
    }

    /// Konec pásu — pravá hrana posledního segmentu.
    var end: Double {
        guard let last = starts.indices.last else { return 0 }
        return starts[last] + widths[last]
    }

    /// Který segment leží pod danou souřadnicí — **jedno místo pro nápovědu i pro klik**.
    ///
    /// **Trefné plochy vykládají celý pás beze zbytku a mezera se dělí napůl mezi oba sousedy.**
    /// Dvoubodová mezera je dvě třetiny nejmenšího segmentu, takže „klik do mezery neudělá nic“
    /// by u úzkých segmentů znamenalo, že se na soubor nedá kliknout — a „celá mezera patří tomu
    /// vlevo“ (tak to bylo napsané do #501) je zase nesymetrické: u tří bodů šířky je půl mezery
    /// znatelný kus plochy. Trefná plocha proto **obsahuje celý nakreslený segment** a k němu
    /// polovinu mezery na každou stranu; na krajích pásu jde až k hraně.
    ///
    /// Nalevo od pásu a napravo za jeho koncem je odpověď `nil` — tam už žádný soubor není.
    ///
    /// Že se **každý** segment dá trefit, tvrdí `PullRequestMapGeometryTests` přes pásmo počtů
    /// souborů. Není to samozřejmost: chyba o půl mezery se **kumuluje zleva doprava**, takže by
    /// se u jednoho počtu vůbec neprojevila a u vyššího by vyšla mimo — a kresba by přitom byla
    /// v pořádku, protože kreslí z týchž čísel. Proto je to jedna funkce, ne dva výpočty.
    func index(at x: Double) -> Int? {
        guard !starts.isEmpty, x >= 0, x <= end else { return nil }
        // Od konce: trefné plochy se dotýkají, takže rozhoduje ten poslední, který začal dřív.
        return starts.indices.last { hitStart(of: $0) <= x }
    }

    /// Levá hrana **trefné** plochy segmentu — o půl mezery vlevo od nakreslené, na kraji pásu
    /// od nuly.
    private func hitStart(of index: Int) -> Double {
        index == 0 ? 0 : starts[index] - spacing / 2
    }
}
