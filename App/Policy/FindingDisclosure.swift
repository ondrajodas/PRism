import Foundation

/// Jak je nález u kódu rozbalený (#185).
///
/// **Blokující je rozbalený rovnou pod svým řádkem** — je to ten jediný, kvůli kterému se PR
/// nemerguje, takže dotahovat se k němu kliknutím by bylo o jedno kliknutí víc právě tam, kde
/// ho nikdo ušetřit nechce. **Ostatní zůstávají značkou na hraně řádku**: rozbalit všechny by
/// z diffu udělalo seznam nálezů proložený kódem, a to je pravý opak toho, proč bubliny visí
/// u kódu.
enum FindingDisclosure: Hashable, Sendable {
    /// Celá bublina: texty, „Kdy to selže“ a akce.
    case expanded
    /// Jen značka — pruh s odznaky a náhledem, kliknutím se rozbalí.
    case collapsed
    /// Odmítnutá skupina (#113) — **nerozbaluje se nikdy**, právě proto, že se nepočítá.
    ///
    /// Není to sbalený stav bez šipky: odmítnutý nález **je** jeden řádek s důvodem a s
    /// `Vrátit`, takže rozbalovat není co — a kdyby se sbalil pod značku, nešel by vrátit.
    case dismissed
}

extension Policy {
    /// Jak se skupina nálezů kreslí v diffu (#185).
    ///
    /// Rozhoduje se **za skupinu, ne za nález**: bublina slévá nálezy na jednom řádku do jedné
    /// (odznak `2×`), takže rozbalení po nálezech by znamenalo místo napůl otevřené — a odznak
    /// shody by tvrdil něco o dvou nálezech, ze kterých je vidět jeden.
    ///
    /// Drží se **odchylka**, ne seznam rozbalených: výchozí stav se odvozuje z nálezů
    /// (blokující rozbalený, ostatní sbalené), takže seznam rozbalených by se musel plnit při
    /// každém načtení záznamu — a nový běh review by uživateli zahodil, co si otevřel. Tatáž
    /// úvaha jako u `isThreadExpanded(_:toggled:)`.
    ///
    /// **Shoda dvou reviewerů nerozbaluje.** Je to odznak ve značce: přišpendlení je o tom, co
    /// zastavuje merge, kdežto shoda je o tom, jak moc nálezu věřit. Dva reviewery, kteří se
    /// shodli na pojmenování proměnné, PR nezastaví.
    static func disclosure(
        of group: FindingGroup,
        categories: Set<String> = defaultBlockingCategories,
        toggled: Set<String> = []
    ) -> FindingDisclosure {
        // Skupina, ze které nezbyl žádný platný nález, se nerozbaluje ani po kliknutí — takže
        // se `toggled` ani neptáme. Filtr se drží v proměnné: `activeFindings` je computed
        // a tohle běží při každém překreslení diffu.
        let active = group.activeFindings
        guard !active.isEmpty else { return .dismissed }
        let blocks = active.contains { isBlocking($0, categories: categories) }
        // Výchozí stav ⊕ odchylka. `!=` je tady xor: blokující se kliknutím sbalí, sbalený
        // rozbalí, a obojí jednou hodnotou v množině.
        return blocks != toggled.contains(disclosureKey(of: group)) ? .expanded : .collapsed
    }

    /// Identita skupiny pro stav rozbalení (#185) — **místo**, když ho skupina má.
    ///
    /// Místo (`file:line`) se přeskládáním nálezů nemění a odmítnutí jednoho z nich s ním
    /// nehne, kdežto klíč nálezu nese `summary`, které si reviewer v dalším běhu přeformuluje
    /// (ověřeno u #17) — rozbalení by se tím tiše vrátilo do výchozího stavu.
    ///
    /// Nález **bez řádku** místo nemá a k jednomu souboru jich může být víc, takže tam
    /// rozhoduje klíč nálezu. Ta dvě pravidla se nemají kde potkat: skupiny bez řádku drží
    /// právě jeden nález, protože `Policy.groups(of:)` je neslévá.
    static func disclosureKey(of group: FindingGroup) -> String {
        if let file = group.file, let line = group.line { return "\(file)|\(line)" }
        // Skupina bez nálezů neexistuje (invariant typu) a nemá co kreslit, takže se sem
        // nedostane — prázdný klíč je tvar odpovědi, ne ztracená hodnota.
        return group.findings.first.map { key(of: $0).rawValue } ?? ""
    }
}
