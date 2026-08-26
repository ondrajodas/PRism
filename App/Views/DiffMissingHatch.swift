import CoreGraphics

/// Šrafa prázdného protějšku v pohledu vedle sebe (#277) — tam, kde na téhle straně dvojice
/// řádek **není**.
///
/// **Z návrhu doslova.** Mockup má u `tr.empty-side`
/// `repeating-linear-gradient(45deg, transparent 0 5px, color-mix(in srgb, var(--ink) 5%, transparent) 5px 10px)`,
/// tedy pruh 5 bodů, mezeru 5 bodů a sklon 45°. Barva je `Palette.diffMissingStripe`.
///
/// **Odlišuje texturou, ne světlostí**, a proto to takhle návrh kreslí: pod plochou obsahu už
/// v tmavém režimu není kam ztmavovat (ΔE 3,3 na pruhu) a zesvětlit plochu by znamenalo, že díra
/// křičí hlasitěji než změna vedle ní. Rozestup nese, co kontrast neunese — polovina plochy
/// v pruzích je vidět i na jediném řádku.
///
/// **Plocha díry se nekreslí**, jen šrafa. V návrhu je pod gradientem `transparent`, takže tam, kde
/// řádek není, prosvítá plocha obsahu — a je to tak správně: díra je prázdné místo, ne stav.
///
/// **Kreslí ji blok kódu v AppKitu** (`DiffTextView.drawRows`), a je to od #446 jediná cesta.
/// Do té doby byla druhá — samostatná dvojice (`DiffPairView`) ji brala jako SwiftUI `Shape` —,
/// jenže do split pohledu se od #157 dostane jedině blok, takže se ta cesta nekreslila. Proto tady
/// zbyla **jen geometrie** (`segments(in:)`) a ne `Shape`: úsečky jsou to, co se sdílet mělo, aby
/// dvě kopie rozestupů nedělaly dvě různé šrafy v jednom okně.
///
/// `y` je v obou plochách **dolů**, takže se úsečky daly sdílet bez přepočtu: `NSTextView` je
/// flipped (kvůli tomu se v `DiffTextView` kreslí `draw(in:)` a ne `draw(at:)`) a SwiftUI taky.
struct DiffMissingHatch {
    /// Šířka pruhu — `5px` z návrhu. Kreslí se tahem, takže je to přímo šířka tahu: ta se měří
    /// **napříč** úsečkou, tedy tak, jak ji měří i CSS gradient.
    static let lineWidth = 5.0

    /// Vzdálenost pruhů **napříč** jejich směrem: pruh 5 a mezera 5 z návrhu, tedy perioda 10.
    static let period = 10.0

    /// Vodorovný krok mezi pruhy. Při sklonu 45° je vodorovná vzdálenost √2× větší než ta napříč —
    /// bez toho přepočtu by šrafa vyšla hustší, než jakou návrh kreslí.
    static let step = period * 2.0.squareRoot()

    /// Úsečky šrafy v daném rámečku, ve směru **z levého dolního koutu do pravého horního** — tedy
    /// tak, jak to vypadá v návrhu. Ověřeno na vyrenderované sekci, ne odvozeno z `45deg`: gradient
    /// míří k pravému hornímu koutu a pruhy leží **napříč** jeho osou, takže se směr snadno otočí.
    ///
    /// Sklon 45° znamená, že se pruh po výšce rámečku posune o tutéž výšku i vodorovně; začínají
    /// proto o ni vlevo, aby byl prošrafovaný i levý kout.
    static func segments(in rect: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        var result: [(from: CGPoint, to: CGPoint)] = []
        var x = rect.minX - rect.height
        while x <= rect.maxX {
            result.append((
                from: CGPoint(x: x, y: rect.maxY),
                to: CGPoint(x: x + rect.height, y: rect.minY)
            ))
            x += step
        }
        return result
    }
}
