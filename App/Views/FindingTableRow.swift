import Foundation

/// Jeden řádek tabulky nálezů (#242).
///
/// **Řádek je místo, ne nález.** Když se dva reviewery potkají na jednom řádku kódu, je z toho
/// jeden řádek tabulky s odznakem `2×` — dva řádky by tvrdily, že jsou to dva různé nálezy, a
/// součet nad tabulkou by pak nesouhlasil s bublinami v diffu. Je to tatáž skupina
/// (`Policy.groups`), jakou kreslí diff, takže se ta dvě místa nemají čím rozejít.
///
/// Texty jednotlivých nálezů si nese jako `FindingRow` — formátování místa a nápověd tím zůstává
/// na jednom místě, společném s kartami v panelu.
struct FindingTableRow: Identifiable, Hashable {
    /// Identita řádku — **z místa, ne z pořadí**.
    ///
    /// Index po setřídění by znamenal, že kliknutí do hlavičky sloupce přepíše identitu každému
    /// řádku: SwiftUI by pak tabulku vzal jako úplně nový seznam, zahodil rozbalení a překreslil
    /// všechno. Nález bez místa `FindingPlace` nemá, takže tam nastupuje jeho identita napříč
    /// běhy (`Policy.key`) — tatáž, kterou se klíčují odmítnutí. Nálezem Copilota na #258.
    let id: String
    let group: FindingGroup
    /// Nálezy skupiny, **nikdy prázdné** — `FindingGroup` to garantuje.
    let findings: [FindingRow]

    /// Nález, kterým se řádek popisuje: první v pořadí podle závažnosti.
    var representative: FindingRow { findings[0] }

    /// Kolik nezávislých reviewerů to nahlásilo. `1` = odznak `2×` se nekreslí.
    var agreement: Int { group.agreement }

    /// Blokuje **kterýkoli platný** nález skupiny? Odmítnutý se nepočítá — tatáž úvaha jako
    /// u proužku bubliny, která právě proto přestane křičet, když ten jeden nález zamítnu.
    let isBlocking: Bool

    /// Odmítnutí, které platí na **celý** řádek. `nil`, dokud v něm zbývá jediný platný nález:
    /// ztlumit řádek, ve kterém pořád něco platí, by ten platný nález schovalo.
    let dismissal: FindingDismissal?

    /// Je co rozbalit? Rozbalená část ukazuje celé nálezy — s „Kdy to selže“, převzetím
    /// a odmítnutím — takže má smysl vždycky, když nález nějaký text nese.
    var isExpandable: Bool { true }

    /// Řádky z **setříděných** nálezů.
    ///
    /// Seskupuje se **až po setřídění**, ne obráceně: `Policy.groups` drží pořadí prvního výskytu
    /// místa, takže setříděný vstup dá setříděné skupiny — a `Policy` tím nemá dvě různá řazení.
    static func rows(
        of findings: [Finding],
        sort: FindingTableSort?,
        blocking categories: Set<String> = Policy.defaultBlockingCategories,
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> [FindingTableRow] {
        let sorted = Policy.sorted(findings, by: sort, categories: categories, dismissals: dismissals)
        return Policy.groups(of: sorted, dismissals: dismissals)
            .map { group in
                FindingTableRow(
                    id: identity(of: group),
                    group: group,
                    findings: FindingRow.preserving(
                        group.findings,
                        blocking: categories,
                        dismissals: group.dismissals
                    ),
                    isBlocking: group.activeFindings.contains {
                        Policy.isBlocking($0, categories: categories)
                    },
                    dismissal: group.activeFindings.isEmpty
                        ? group.dismissal(of: group.findings[0])
                        : nil
                )
            }
    }

    /// Identita skupiny: `file:line`, a u nálezu bez místa identita toho nálezu.
    ///
    /// Prefix `place`/`finding` proto, aby se ty dva prostory nemohly potkat — cesta, která by se
    /// jmenovala jako klíč nálezu, je nepravděpodobná, ale identita nemá stát na nepravděpodobnosti.
    private static func identity(of group: FindingGroup) -> String {
        guard let place = FindingPlace(group) else {
            return "finding:\(Policy.key(of: group.findings[0]).rawValue)"
        }
        return "place:\(place.file):\(place.line.map(String.init) ?? "")"
    }
}
