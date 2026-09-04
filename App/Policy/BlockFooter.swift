import Foundation

/// Patka bloku na domácí záložce — `Zobrazit celé dění +122 →`.
///
/// **Text i počet skládá `Policy`, ne view.** „+122“ musí vyjít z týchž řádků, které blok
/// nakreslil — jinak se patka rozejde s kresbou a nikdo si toho nevšimne, protože obě čísla
/// vypadají platně.
///
/// **Patka není řádek**: nepočítá se do řádků bloku, takže se nedostane ani do klávesové
/// navigace, ani do toho, kolik řádků blok hlásí.
///
/// **Vlastní typ od #515**, do té doby to byla `DashboardBlock.Footer`. `DashboardBlock` odešel
/// s kartami a s oběma bloky front (deska je od #515 skládá jako pruhy), takže by z něj zbyl
/// prázdný obal kolem jedné vnořené struktury. **Pruhy desky patku nemají** — rozbalují se na
/// místě, protože pruh míchá cizí a vlastní PR a žádná sekce railu nemá tutéž množinu
/// (`Policy.laneSlice`).
struct BlockFooter: Hashable, Sendable {
    /// `Zobrazit celé dění`
    let title: String
    /// `+122` — kolik řádků se nevešlo.
    let rest: String
    /// Kam vede klik.
    let section: RailSection
}

extension Policy {
    /// Kolik řádků se z bloku `Dění` na domácí záložce kreslí (#443, zvednuto #515).
    ///
    /// **Osm, do #515 pět.** Pravý sloupec držel do #515 tři bloky (legenda reviewerů, `Co teď`,
    /// dění), kdežto od #515 jsou v něm **dva** — a levý sloupec má naopak šest pruhů místo dvou
    /// bloků. Pět řádků by v tom sloupci nechalo prázdno o výšce, na kterou #443 přišlo z opačné
    /// strany (blok tam dával, aby díru zaplnil). Změřeno renderem sekce 45: s osmi řádky je
    /// pravý sloupec o třetinu kratší než levý, s pěti o dvě třetiny.
    ///
    /// Strop zůstává **strop**, ne množina: nadpis bloku dál počítá nepřečtené v celém záznamu
    /// a patka říká, kolik se nevešlo.
    static let activityRowLimit = 8
}
