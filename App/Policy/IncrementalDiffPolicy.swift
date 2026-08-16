import Foundation

extension Policy {
    /// Dá se ukázat **jen to, co od minule přibylo** (#284)? `nil` = nedá, tlačítko se nenabídne.
    ///
    /// Tlačítko nesmí slibovat víc, než umí. Diff „co přibylo“ se tahá jako
    /// `compare/<viděná>...<dnešní>`, a to je **trojtečkový** rozsah: začíná na společném předku
    /// obou hlav. Dokud je dnešní hlava potomkem té viděné, je společný předek ta viděná —
    /// rozsah tedy vyjde přesně na to, co se pushnulo. Jakmile se historie přepíše, společný
    /// předek spadne k místu, kde větev vznikla, a z „co přibylo“ se stane **víc než celý diff
    /// PR**: změřeno na `cli/cli#14062`, kde po force pushi vyšlo 102 kB ve 22 souborech, kdežto
    /// celý PR má 15 kB ve třech. Přesně to je „otevře celý diff, který už člověk viděl“.
    ///
    /// Po přepsané historii se proto nenabízí nic — a je to i to, co pruh nabízí místo toho:
    /// `Pustit review znovu`.
    ///
    /// - Parameters:
    ///   - seen: hlava, kterou jsem u PR naposledy viděl. `nil` = neviděl jsem žádnou, takže
    ///     není proti čemu porovnávat.
    ///   - head: hlava, na které PR stojí teď. `nil` = detail se ještě nenačetl.
    ///   - rewroteHistory: přepsala se od minule historie větve? **`nil` znamená „nevíme“**
    ///     (nenačtená časová osa) a chová se jako „ano“: nabídnout rozsah, o kterém nevíme,
    ///     jestli dává smysl, je horší než ho nenabídnout.
    static func incrementalDiff(
        from seen: String?,
        to head: String?,
        rewroteHistory: Bool?
    ) -> IncrementalDiffRange? {
        guard
            let seen, !seen.isEmpty,
            let head, !head.isEmpty,
            // Stejná hlava znamená prázdný rozsah — tlačítko by otevřelo prázdno.
            seen != head,
            rewroteHistory == false
        else { return nil }
        return IncrementalDiffRange(seen: seen, head: head)
    }
}
