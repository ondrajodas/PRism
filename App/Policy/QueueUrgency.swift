import Foundation

/// Jeden řádek fronty na dashboardu (#181) — PR i s tím, co se o něm ví.
///
/// Vlastní typ, aby se dalo řadit v `Policy`: pořadí se rozhoduje ze stavu review a z počtu
/// blokujících, a obojí drží store zvlášť od shrnutí PR. Bez téhle trojice by se řadilo ve view,
/// tedy tam, kde se to netestuje.
struct QueueEntry: Hashable, Sendable, Identifiable {
    let pullRequest: PullRequestSummary
    let state: ReviewState
    let row: QueueRow
    /// Leží tu rozdělané review? Řádek si to kreslí tužkou; na pořadí to vliv nemá — rozdělaná
    /// práce je moje věc, kdežto fronta se řadí podle toho, co přišlo zvenčí.
    let hasDraft: Bool

    var id: PRIdentifier { pullRequest.id }
}

extension Policy {
    /// Fronta seřazená podle závažnosti, ne podle času (#181).
    ///
    /// Seznam v záložce `Fronta` je od nejnovějšího — tam se hledá „co přišlo“. Dashboard
    /// odpovídá na jinou otázku (`co dneska hoří`), takže nahoru patří to, co si žádá pozornost:
    /// blokující nález, pak obyčejné nálezy, pak běhy, které nedopadly.
    ///
    /// **Pořadí ze vzorku v návrhu se nepřebírá doslova.** Mockup ukazuje běžící review hned pod
    /// blokujícím a čisté nad zastaralým; to je ukázka odznaků, ne škála závažnosti — běžící
    /// review po mně nechce nic a čisté už vůbec ne.
    ///
    /// **Série řazení nerozbije** (#513): skupina drží pohromadě na místě toho člena, který vyšel
    /// nejvýš, a uvnitř jde od základu nahoru (`Policy.grouped(_:by:keeping:)`). Bez toho by je
    /// závažnost rozházela po celé desce, a přečíst horní PR dřív než spodní je práce, která se
    /// stejně bude dělat znovu. Výchozí prázdné `series` nedělají nic.
    ///
    /// **Pruhy desky to nedrží** (#513) — rozřazení podle mého tahu (`Policy.lane`) je druhá osa
    /// a běží až nad tímhle pořadím, takže spodní PR může skončit v `Rozhodnout` a horní
    /// v `Přečíst`. Je to záměr: pruh odpovídá na „co udělám teď“ a série na „v jakém pořadí“.
    /// Uvnitř pruhu zůstávají členové vedle sebe a ve správném pořadí.
    static func byUrgency(_ entries: [QueueEntry], keeping series: [PullRequestSeries] = []) -> [QueueEntry] {
        grouped(sortedByUrgency(entries), by: \.id, keeping: series)
    }

    private static func sortedByUrgency(_ entries: [QueueEntry]) -> [QueueEntry] {
        entries.sorted { left, right in
            let ranks = (urgency(of: left), urgency(of: right))
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            // Uvnitř patra od naposledy změněného, při shodě podle identifikátoru — jinak by
            // řádky mezi tiky poskakovaly pod rukama (tatáž úvaha jako v `PullRequestList`).
            if left.pullRequest.updatedAt != right.pullRequest.updatedAt {
                return left.pullRequest.updatedAt > right.pullRequest.updatedAt
            }
            return left.id < right.id
        }
    }

    /// Čím menší číslo, tím dřív na řadu.
    ///
    /// **Zastaralé se neposouvá nahoru, ani když blokující nález má.** Nálezy patří k jinému
    /// `headSha`, takže o dnešním kódu netvrdí nic (tvrdá podmínka č. 5) — pořadí by na nich
    /// stavět nemělo.
    static func urgency(of entry: QueueEntry) -> Int {
        let blocking = entry.row.blocking > 0
        return switch entry.state {
        case .completed: blocking ? 0 : 1
        // Nedoběhlý běh je zpráva o běhu, ne výsledek — ale blokující nález platí i z půlky
        // session, takže si první patro zaslouží stejně jako u doběhlého.
        case .timedOut, .interrupted: blocking ? 0 : 2
        // Neprůkazné review patří do stejného patra jako selhání (#383) — nálezy se z něj
        // nemají kde vzít, takže se s ním dělá totéž: pustit znovu. Vlastní patro by bylo
        // rozhodnutí o pořadí bez opory; závažnost je stejná, jen text a odznak jsou jiné.
        case .checkoutFailed, .failed, .inconclusive: 2
        case .stale: 3
        case .notStarted: 4
        // Běžící review po mně nechce nic, dokud nedoběhne.
        case .queued, .cloning, .running: 5
        // Odmítnuté nálezy jsou vyřízená práce, čisté review nemá co řešit — obojí patří dolů.
        case .dismissed: 6
        case .clean: 7
        }
    }
}
