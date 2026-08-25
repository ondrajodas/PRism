import Foundation

extension Policy {
    /// Jde tuhle naměřenou hodnotu metriky písma použít? (#407)
    ///
    /// Rozhoduje o tom, jestli si ji `FontMetric` **zapamatuje na celý proces** — a právě proto je
    /// to čistá funkce a ne `if` uvnitř měřidla: zapamatovaná nula je horší než žádná, protože se
    /// tváří jako změřená hodnota a spadne z ní tvrzení, které nad aplikací platí (`pod sebou: 0,
    /// vedle sebe: 0` v `CommitPanelRoomTests`).
    ///
    /// **Hlídá se `isFinite`, ne jen kladnost.** Nula z metriky písma je ten příznak, který se
    /// naměřil, ale nekonečno a `NaN` jsou z téhož soudku a **shodí proces**, ne test:
    /// `Int(available / characterWidth)` na nekonečnu neprojde, kdežto na nule ho zavře `guard`
    /// v `Policy.charactersPerSide`. Kdo si tedy chce hodnotu zapamatovat, dostane ji jedině
    /// tehdy, když se s ní dá počítat.
    /// **Generická přes typ hodnoty schválně**: měřidlo pracuje v `CGFloat` (kreslí se z toho),
    /// kdežto `Policy.charactersPerSide` v `Double`. Převod mezi nimi by byl druhé místo, kde se
    /// dá číslo pokazit, a `BinaryFloatingPoint` obojí pokrývá bez něj.
    static func usableFontMetric<Value: BinaryFloatingPoint>(_ value: Value) -> Value? {
        guard value.isFinite, value > 0 else { return nil }
        return value
    }
}
