import Foundation

/// „Tenhle nález jsem posoudil a neplatí.“
///
/// Falešně pozitivní nález je normální provoz, ne chyba. Bez tohohle se s ním dalo dělat jen
/// dvojí: nechat ho ležet, nebo zahodit **celý** záznam (#81) — tedy i nálezy, které platí.
///
/// **Bez volného textu.** Poznámka, kterou nikdo nečte a nikam se neodesílá, je mrtvá váha —
/// a hlavně svádí spolehnout se na ni: vysvětlení, které nikam nejde, vypadá jako zpětná
/// vazba pro skill, kterou není.
struct FindingDismissal: Hashable, Codable, Sendable {
    /// Proč nález neplatí. **Dva důvody, ne jeden ani pět.**
    ///
    /// „Reviewer se mýlí“ a „má pravdu, ale sem to nepatří“ vedou jinam: první je vstup pro
    /// doladění skillu nebo blokující sady, druhý ne. Splést je do jednoho tu informaci
    /// zahodí. Víc hodnot ne — výčet, ve kterém se váhá mezi dvěma podobnými, se vyplňuje
    /// špatně, a pak neříká nic.
    enum Reason: String, Hashable, Codable, Sendable, CaseIterable {
        /// Reviewer se mýlí — to, co popisuje, v kódu není.
        case invalid
        /// Reviewer má pravdu, ale k tomuhle PR to nepatří.
        case irrelevant
    }

    let reason: Reason
    /// Kdy se to odmítlo. Bere se z hodin storu, ne z view — je to údaj o zápisu.
    let dismissedAt: Date

    init(reason: Reason, dismissedAt: Date) {
        self.reason = reason
        self.dismissedAt = dismissedAt
    }
}

extension FindingDismissal.Reason {
    /// Popisek do okna. Krátký — visí v odznaku na jednom řádku vedle textu nálezu.
    var label: String {
        switch self {
        case .invalid: "neplatný"
        case .irrelevant: "irelevantní"
        }
    }

    /// Co to znamená. Do nápovědy u tlačítka i u odznaku, aby se dvě podobné volby nepletly.
    var explanation: String {
        switch self {
        case .invalid: "Reviewer se mýlí — to, co popisuje, v kódu není."
        case .irrelevant: "Reviewer má pravdu, ale k tomuhle pull requestu to nepatří."
        }
    }
}
