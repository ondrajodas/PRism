import Foundation

/// Průběh běžícího review do pruhu v hlavičce PR (#218, `.runbar`).
///
/// Do #218 se v hlavičce o běhu nedozvěděl nikdo nic — bylo tam jen tlačítko `Spustit review`
/// a to, že něco běží, se poznalo až v panelu `Průběh`. Návrh proto vedle chipů kreslí proužek
/// a k němu jednu větu: **kdo běží, kolik je hotovo a jak dlouho to trvá**.
struct ReviewRunProgress: Equatable, Sendable {
    /// Kde běh je. `preparing` má proužek bez konce — dokud se neví, kolik reviewerů poběží,
    /// nemá se z čeho počítat podíl a nula by tvrdila „hotovo nic“, což je jiné tvrzení než
    /// „ještě nevím kolik“.
    enum Stage: Equatable, Sendable {
        case preparing
        case running(finished: Int, total: Int)
    }

    let stage: Stage
    /// Reviewery, které právě běží, v abecedním pořadí. Prázdné během přípravy.
    let running: [String]
    /// Kdy se spustil **tenhle** běh. Bere se ze `RunningReview`, ne z časové osy: osa se při
    /// opakování jednoho revieweera (#149) míchá s tou z minulého běhu a reviewer, který mezitím
    /// doběhl, z ní vypadne — hodiny by se tím vracely zpátky.
    let startedAt: Date

    /// Podíl hotového. `nil` u přípravy a u nulového součtu, viz `Stage`.
    var fraction: Double? {
        guard case .running(let finished, let total) = stage, total > 0 else { return nil }
        return min(Double(finished) / Double(total), 1)
    }
}

extension Policy {
    /// Průběh do hlavičky. `nil` = neběží nic, takže se z pruhu stane samotná řada chipů.
    ///
    /// Rozhoduje **`startedAt`, ne fáze**: `reviewPhases` si po skončení běhu drží i `failed`,
    /// takže by se z něj proužek kreslil nad review, které dávno neběží. Běžící běh se pozná
    /// tím, že má kdy začal.
    static func progress(
        startedAt: Date?,
        phase: ReviewPhase?,
        running: Set<String>
    ) -> ReviewRunProgress? {
        guard let startedAt else { return nil }

        let stage: ReviewRunProgress.Stage = if case .running(let finished, let total) = phase {
            .running(finished: finished, total: total)
        } else {
            .preparing
        }

        return ReviewRunProgress(stage: stage, running: running.sorted(), startedAt: startedAt)
    }
}
