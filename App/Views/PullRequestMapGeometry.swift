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

    /// Který segment leží pod danou souřadnicí — **jedno místo pro nápovědu i pro klik**.
    ///
    /// **Mezera mezi segmenty padne tomu vlevo.** Dvoubodová mezera je čtvrtina nejmenšího
    /// segmentu, takže „klik do mezery neudělá nic“ by u úzkých segmentů znamenalo, že se na
    /// soubor nedá kliknout; hledá se proto **poslední segment, který začal nalevo od kurzoru**.
    /// Nalevo od pásu a napravo za jeho koncem je odpověď `nil` — tam už žádný soubor není.
    func index(at x: Double) -> Int? {
        guard let last = starts.indices.last, x >= 0 else { return nil }
        guard x <= starts[last] + widths[last] else { return nil }
        // Od konce, tedy tatáž úvaha jako u `Policy.pinnedFileHeader`: hrany se dotýkají, takže
        // rozhoduje ten poslední, který začal dřív.
        return starts.lastIndex(where: { $0 <= x })
    }
}
