import Foundation

extension Policy {
    /// Jak se reviewer jmenuje **v úzkém místě** (#182).
    ///
    /// Skilly se identifikují `plugin:skill` a některá id jsou dlouhá (`code-review:code-review`,
    /// `superpowers:requesting-code-review`). V panelu 300 bodů širokém se takové jméno zalomí
    /// na tři řádky, takže hlavička revieweera zabere víc místa než jeho osa.
    ///
    /// Zkracuje se na část **za dvojtečkou**, a to jen tehdy, když tím zkrácené jméno zůstane
    /// v té sadě **jednoznačné**: dva různé pluginy se stejně pojmenovaným skillem by jinak
    /// v okně vypadaly jako jeden reviewer, a to je horší než dlouhé jméno. Id, které by se po
    /// zkrácení srazilo s jiným, proto zůstává celé.
    ///
    /// `code-review:code-review` → `code-review` (obě půlky jsou totéž),
    /// `superpowers:requesting-code-review` → `requesting-code-review`.
    ///
    /// Vrací **mapu z celého id**, ne pole: volající kreslí reviewery v pořadí, které si drží sám,
    /// a plné id potřebuje do nápovědy — zkrácené jméno nesmí být jediné, co je v okně k dispozici.
    static func shortReviewerNames(of identifiers: some Sequence<String>) -> [String: String] {
        let unique = Set(identifiers)
        // Kolize se počítají nad **návrhy**, ne nad celými id: zkrátit se smí jen to, co po
        // zkrácení nezačne znamenat dvě věci naráz.
        var counts: [String: Int] = [:]
        for identifier in unique { counts[shortened(identifier), default: 0] += 1 }

        var names: [String: String] = [:]
        for identifier in unique {
            let short = shortened(identifier)
            names[identifier] = counts[short] == 1 ? short : identifier
        }
        return names
    }

    /// Část za poslední dvojtečkou; `plugin:skill`, kde jsou obě půlky totéž, dá jednu z nich.
    /// Jméno bez dvojtečky se nechává, jak je.
    private static func shortened(_ identifier: String) -> String {
        guard let colon = identifier.lastIndex(of: ":") else { return identifier }
        let suffix = String(identifier[identifier.index(after: colon)...])
        return suffix.isEmpty ? identifier : suffix
    }
}
