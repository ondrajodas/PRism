import Foundation

extension Policy {
    /// Klíč nálezu — `(reviewer, file, line, summary)`.
    ///
    /// **Jediné místo, kde se klíč skládá.** Kdyby vznikal na dvou, po druhém běhu by se
    /// odmítnutí přestalo párovat a tiše zmizelo — a to je horší než nespárovat vůbec,
    /// protože zmizelý bit vypadá jako nekliknutý.
    ///
    /// Je to táž identita, na které stojí dedup ve `StreamParseru`: **místo a `summary`**, ne
    /// celá hodnota. Reviewer, který hlásí průběžně a na konci pošle kompletní seznam, si
    /// umí `short_summary` přeformulovat (ověřeno na skutečném běhu u #17), takže cokoli
    /// bohatšího by tentýž nález rozdvojilo. K tomu **reviewer**, protože dva reviewery na
    /// jednom řádku jsou běžné a odmítnutí jednoho z nich nesmí odmítnout druhého.
    ///
    /// Bere se **`reported.summary`, ne `summary`**, tedy věta revieweera, ne její překlad.
    /// Překlad je zobrazení: ukládá se druhým zápisem po běhu a při dalším běhu ho model
    /// napíše jinak, takže klíč z něj by se rozešel sám se sebou.
    static func key(of finding: Finding) -> FindingKey {
        // Svislítko je čitelné v souboru, do kterého se člověk podívá očima — na rozdíl od
        // ASCII oddělovačů, které jsou v JSONu nevidět. Skill ani cesta ho běžně nemají
        // a k záměně by musely obě části vyjít slepené jinak; `summary` je poslední, takže
        // se do dalšího pole přetéct nemá kde.
        FindingKey(
            [
                finding.reviewer,
                finding.reported.file ?? "",
                finding.reported.line.map(String.init) ?? "",
                finding.reported.summary,
            ].joined(separator: "|")
        )
    }
}

extension ReviewRecord {
    /// Nálezy, které pořád platí. **Tohle je to jediné místo**, kterým se odmítnutí
    /// vyhodnocuje — jinak by řádek seznamu a panel řekly o tomtéž PR dvě různé věci.
    var activeFindings: [Finding] { findings.filter { dismissal(of: $0) == nil } }

    /// Kolik nálezů jsem odmítl. Musí to být vidět: `approve` postavené na tom, že jsem tři
    /// nálezy zamítl, se od „reviewer nic nenašel“ nesmí lišit jen tím, že si to pamatuju.
    var dismissedCount: Int { findings.count - activeFindings.count }

    /// Platí na nálezu odmítnutí? `nil` = platí.
    func dismissal(of finding: Finding) -> FindingDismissal? {
        dismissals[Policy.key(of: finding)]
    }

    /// Odmítne nález, nebo odmítnutí zruší (`nil`).
    ///
    /// Označení bydlí **na záznamu**, ne na nálezu, právě kvůli `replace(_:)`: opakované
    /// review týmž skillem celý `StoredReviewRun` přepíše, a to je zrovna chvíle, kdy se
    /// stejný falešný nález vrátí a označení ztratit nechci.
    ///
    /// Osiřelý klíč se **neuklízí**. Nález, který v tomhle běhu nepřišel, může přijít
    /// v dalším — a uklidit ho znamená přijít o označení právě tam, kde je nejdražší.
    /// Je to pár bajtů v souboru.
    mutating func setDismissal(_ dismissal: FindingDismissal?, of finding: Finding) {
        dismissals[Policy.key(of: finding)] = dismissal
    }
}
