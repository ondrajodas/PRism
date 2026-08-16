import Foundation

/** Dvě hlavy, mezi kterými se ptáme „co přibylo“ (#284).

 Vlastní typ, ne dva `String`y: obojí je sha a záměna by znamenala diff naruby, což z podpisu
 `(String, String)` nikdo nepozná.
 */
struct IncrementalDiffRange: Hashable, Sendable {
    /// Hlava, kterou jsem naposledy viděl.
    let seen: String
    /// Hlava, na které PR stojí teď.
    let head: String
}

/// Diff **jen toho, co od minule přibylo** (#284) — rozsah a jak dopadlo jeho načtení.
///
/// Drží se **vedle** celého diffu PR, ne místo něj: celý diff je to, proti čemu se píše review,
/// a jeden pohled navíc ho nesmí zahodit. Přítomnost záznamu je zároveň to, co přepíná tab
/// `Změněné soubory` do rozsahového pohledu — dokud v mapě není, kreslí se celý diff.
struct IncrementalDiff: Equatable, Sendable {
    let range: IncrementalDiffRange
    var content: Content

    /// **Vlastní stav, ne `DiffState`.** Ten nese `updatedAt`, podle kterého se pozná, jestli
    /// se celý diff nemá načíst znovu; rozsah se klíčuje dvěma sha, takže by to bylo razítko,
    /// které nikdo nečte — a držený stav, který nikdo nečte, svádí k tomu se na něj spolehnout.
    enum Content: Equatable, Sendable {
        case loading
        case loaded(Diff)
        case failed(String)
    }

    var loaded: Diff? {
        guard case .loaded(let diff) = content else { return nil }
        return diff
    }
}
