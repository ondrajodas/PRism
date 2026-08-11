import CoreGraphics

/// Kde v bloku leží plochy gutteru — sloupec, ve kterém se komentuje a táhne rozsah (#252).
///
/// **Proč to je čistý typ a ne views.** Do #252 měl každý řádek bloku vlastní `Color.clear`
/// s `onGeometryChange` a `DragGesture`em: u bloku o 60 řádcích to je 60 ploch v pohledu pod
/// sebou a 120 vedle sebe, a všechny se při scrollování líného seznamu **znovu umisťují**
/// a znovu čtou geometrii. Rámečky řádků přitom hlásí textové view samo, takže se poloha
/// každé plochy dá **spočítat** z rámečku a z polohy bloku — a to je tatáž úvaha jako u #220
/// („v zanořeném stromu se rozměr nenechává vyjednávat, když se dá spočítat“), jen o jednu
/// vrstvu níž: nevyjednává se ani počet prvků.
///
/// Aritmetika žije tady, protože se tím dá **změřit a otestovat bez okna** — stejný důvod, proč
/// je `widths(in:count:)` u `ProportionalColumns` `internal`.
struct DiffGutterGeometry {
    /// Rámečky řádků, jak je ohlásilo textové view. Prázdné = blok se ještě nerozložil.
    let frames: [DiffBlockLineFrame]
    /// Šířka sloupce s čísly a pilulkou (`DiffLineView.contentInset(for:)`).
    let gutterWidth: Double
    /// Šířka bloku. Ve split pohledu z ní vychází začátek pravé poloviny; v pohledu pod sebou je
    /// sloupec jediný, takže se nepoužije.
    let blockWidth: Double

    /// Gutter bloku v pohledu **pod sebou** — jeden sloupec na levé hraně.
    ///
    /// Šířka sloupce se bere z `DiffLineView.contentInset(for:)`, tedy z toho jednoho součtu, podle
    /// kterého ji kreslí i textové view. Kdyby ji dosazoval každý volající sám, je to druhé místo,
    /// které se s kreslením rozejde.
    @MainActor static func unified(frames: [DiffBlockLineFrame]) -> Self {
        Self(frames: frames, gutterWidth: DiffLineView.contentInset(for: .unified), blockWidth: 0)
    }

    /// Gutter bloku v pohledu **vedle sebe** — dva sloupce, pravý v půlce bloku.
    ///
    /// Šířku bloku hlásí kontejner v rámečcích řádků (jsou přes celou šířku), takže se neměří
    /// druhým způsobem.
    @MainActor static func split(frames: [DiffBlockLineFrame]) -> Self {
        Self(
            frames: frames,
            gutterWidth: DiffLineView.contentInset(for: .split),
            blockWidth: frames.first.map { Double($0.rect.width) } ?? 0
        )
    }

    /// Kde začíná sloupec dané strany. `nil` (pohled pod sebou) i `.left` začínají na levé hraně,
    /// `.right` v půlce bloku.
    ///
    /// Půlka je **tatáž hranice, podle které se pozná strana pod myší** (`side(atX:)`) — jinak by
    /// pilulka svítila v jedné polovině a táhlo se ve druhé. Kontejner kreslí pravý sloupec o půl
    /// bodu jinam (`(šířka − 1) / 2 + 1`, aby se mezi ně vešla dělicí čára); na trefování plochy
    /// široké 84 pt to nemá vliv a jedna hranice na jednom místě je víc než ten půlbod.
    func x(of side: DiffSide?) -> Double {
        side == .right ? blockWidth / 2 : 0
    }

    /// Která strana leží pod tímhle `x`.
    func side(atX x: Double) -> DiffSide {
        x < blockWidth / 2 ? .left : .right
    }

    /// Svislý rozsah gutteru — od horní hrany prvního řádku po dolní hranu posledního.
    ///
    /// Není to `0..<výška bloku`: text začíná na svislém insetu a ten do řádků nepatří (#236).
    /// Plocha na tažení tedy sedí přesně na řádcích, jako když ji měl každý řádek vlastní.
    var span: (top: Double, height: Double)? {
        guard let first = frames.first, let last = frames.last else { return nil }
        return (top: Double(first.rect.minY), height: Double(last.rect.maxY - first.rect.minY))
    }

    /// Rámeček plochy jednoho řádku na dané straně, v souřadnicích bloku.
    func rect(of frame: DiffBlockLineFrame, on side: DiffSide?) -> CGRect {
        CGRect(x: x(of: side), y: frame.rect.minY, width: gutterWidth, height: frame.rect.height)
    }

    /// Řádek na dané svislé pozici uvnitř bloku. Rozhoduje **jen `y`** — pilulka i čísla stojí
    /// vlevo od textu a musí na myš reagovat taky (viz #98 a #157).
    func line(atY y: Double) -> DiffBlockLineFrame? {
        frames.first { y >= $0.rect.minY && y < $0.rect.maxY }
    }
}

/// Poloha bloku v prostoru obsahu diffu, držená **mimo observable stav**.
///
/// Existuje ze stejného důvodu jako `DiffRowFrames` (#252): líný seznam si obsah přeměřuje
/// průběžně, takže se poloha bloku při scrollování mění — a kdyby byla ve `@State`, přestavěl by
/// se blok při každém posunu. Čte ji tažení rozsahu (převod bodu z obsahu do bloku) a zápis ploch
/// do `DiffRowFrames`; nic z toho se nekreslí, takže se na změnu nemá co překreslovat.
@MainActor final class DiffBlockPlacement {
    var rect: CGRect = .zero
}
