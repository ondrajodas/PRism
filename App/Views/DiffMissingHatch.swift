import SwiftUI

/// Šrafa prázdného protějšku v pohledu vedle sebe (#277) — tam, kde na téhle straně dvojice
/// řádek **není**.
///
/// **Odlišuje texturou, ne světlostí**, a je to celý důvod, proč vzniká: v tmavém režimu už pod
/// `Palette.surface` není kam ztmavovat (plocha díry je od plochy obsahu vzdálená jen ΔE 3,3)
/// a zesvětlit ji by znamenalo, že díra křičí hlasitěji než přidaný řádek vedle ní. Pruhy
/// odlišení nesou, aniž by si na to musely brát světlost — samotný pruh je od plochy díry
/// vzdálený ΔE 11,3.
///
/// **Geometrie je na jednom místě pro obě cesty kreslení**: blok kódu si šrafu kreslí sám
/// v AppKitu (`DiffTextView.drawRows`), samostatná dvojice ji dostane jako SwiftUI `Shape`
/// (`DiffPairView`). Dvě kopie rozestupů by znamenaly dvě různé šrafy v jednom okně.
///
/// Sdílet se to dá bez přepočtu, protože **obě plochy mají `y` dolů**: `NSTextView` je flipped
/// (kvůli tomu se v `DiffTextView` kreslí `draw(in:)` a ne `draw(at:)`) a SwiftUI taky. Pruhy tedy
/// v obou cestách padají stejným směrem.
struct DiffMissingHatch: Shape {
    /// Vodorovná vzdálenost mezi pruhy. Šest bodů je zvolené proti výšce řádku (~15 pt): na jeden
    /// řádek díry padnou dva až tři pruhy, takže je textura vidět i u jediného prázdného řádku.
    static let spacing = 6.0
    /// Šířka pruhu. Jeden bod schválně — díra má být poznat, ne přebít kód vedle sebe.
    static let lineWidth = 1.0

    /// Úsečky šrafy v daném rámečku. Sklon je 45°, takže vodorovný posun pruhu je přes výšku
    /// rámečku — pruhy proto začínají o tu výšku vlevo, aby byl prošrafovaný i levý kout.
    static func segments(in rect: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        var result: [(from: CGPoint, to: CGPoint)] = []
        var x = rect.minX - rect.height
        while x <= rect.maxX {
            result.append((
                from: CGPoint(x: x, y: rect.maxY),
                to: CGPoint(x: x + rect.height, y: rect.minY)
            ))
            x += spacing
        }
        return result
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in Self.segments(in: rect) {
            path.move(to: segment.from)
            path.addLine(to: segment.to)
        }
        return path
    }
}
