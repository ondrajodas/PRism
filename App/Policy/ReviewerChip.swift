import Foundation

/// Stav jednoho revieweera v horní liště detailu.
///
/// Platí tu totéž pravidlo jako u návrhu verdiktu: **„nic jsem nenašel“ a „nemám co říct“
/// se nesmí slít.** Chip, který u nereportujícího nebo ztrácejícího běhu ukáže „čisté“,
/// je schválený PR s neohlášenou chybou.
struct ReviewerChip: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        /// Skill je v sadě, ale nikdy neběžel.
        case notStarted
        case running
        /// Doběhlo, reportovalo a nic nenašlo — jediný stav, ze kterého se dá říct „čisto“.
        case clean
        case findings(Int)
        /// Doběhlo, ale za čisté se to brát nedá: buď nereportovalo, nebo se nález
        /// nepodařilo přečíst. Text říká který z toho.
        case inconclusive(String)
        case failed(String)
        /// Vytimeoutovaný běh si nechává, co stihl — částečné nálezy jsou to jediné, co je.
        case timedOut(findings: Int)
    }

    let skill: String
    let state: State

    var id: String { skill }
}

extension Policy {
    /// Chipy v pořadí nastavené sady skillů; reviewer, který v sadě není, ale výsledek po
    /// sobě nechal, se přidá na konec — bez chipu by nešlo poznat, odkud se jeho nálezy
    /// v tabulce vzaly.
    static func chips(
        for record: ReviewRecord?,
        skills: [String],
        running: Set<String>
    ) -> [ReviewerChip] {
        let runs = record?.runs ?? []
        let extra = runs.map(\.skillID).filter { !skills.contains($0) }

        return (skills + extra).map { skill in
            ReviewerChip(
                skill: skill,
                state: state(of: skill, in: runs, running: running)
            )
        }
    }

    private static func state(
        of skill: String,
        in runs: [StoredReviewRun],
        running: Set<String>
    ) -> ReviewerChip.State {
        // Běžící reviewer přebíjí starší výsledek: to, co je na obrazovce, se právě
        // přepisuje.
        guard !running.contains(skill) else { return .running }
        guard let run = runs.first(where: { $0.skillID == skill }) else { return .notStarted }

        switch run.outcome {
        case .failed(let detail): return .failed(detail)
        case .timedOut: return .timedOut(findings: run.findings.count)
        case .finished: return finishedState(of: run)
        }
    }

    private static func finishedState(of run: StoredReviewRun) -> ReviewerChip.State {
        if !run.findings.isEmpty { return .findings(run.findings.count) }
        if !run.calledReportFindings { return .inconclusive("reviewer nálezy nenahlásil") }
        if run.droppedFindings > 0 {
            return .inconclusive(Plural.czech(
                run.droppedFindings,
                one: "nález se nepodařilo přečíst",
                few: "nálezy se nepodařilo přečíst",
                many: "nálezů se nepodařilo přečíst"
            ))
        }
        return .clean
    }
}
