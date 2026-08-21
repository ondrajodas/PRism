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
        /// Session skončila s aplikací; nálezy jsou z transcriptu (#97).
        case interrupted(findings: Int)
    }

    let skill: String
    let state: State
    /// Co na výsledku chybí, i když nálezy dorazily — typicky nález, který se nepodařilo
    /// přečíst. Stav zůstává `findings`, aby byl vidět počet; tohle říká, že úplný není.
    let warning: String?
    /// Co běh stál (#148). Bere se z **uloženého** záznamu, takže na rozdíl od osy v tabu
    /// `Průběh` (ta je jen v paměti) přežije restart — a je to jediné místo, které uloženou
    /// cenu čte. `nil` u běhu, který ji nenahlásil, a u skillu, který ještě neběžel.
    let usage: RunUsage?

    var id: String { skill }

    init(skill: String, state: State, warning: String? = nil, usage: RunUsage? = nil) {
        self.skill = skill
        self.state = state
        self.warning = warning
        self.usage = usage
    }
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
            let run = runs.first { $0.skillID == skill }
            return ReviewerChip(
                skill: skill,
                state: state(of: skill, in: runs, running: running),
                warning: run.flatMap(warning(of:)),
                usage: run?.usage
            )
        }
    }

    /// Ztracený nález se hlásí i tehdy, když nějaké nálezy dorazily. Bez toho vypadá
    /// neúplný výsledek jako úplný — a `suggestedVerdict` pak mlčí bez vysvětlení.
    private static func warning(of run: StoredReviewRun) -> String? {
        guard run.droppedFindings > 0, !run.findings.isEmpty else { return nil }
        return droppedText(run.droppedFindings)
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
        case .interrupted: return .interrupted(findings: run.findings.count)
        case .finished: return finishedState(of: run)
        }
    }

    /// Stav doběhlého běhu.
    ///
    /// Nálezy přebíjejí všechno — počet je to, kvůli čemu se chip čte. Zbytek rozhoduje
    /// `Policy.inconclusiveReason(of:)`, tedy **tatáž funkce, jakou se řídí návrh verdiktu
    /// a proužek u řádku** (#383): do té doby tady stály vlastní `if`y v jiném pořadí a čtení
    /// kódu neznaly, takže chip tvrdil `čisté` nad během, který kód neotevřel.
    private static func finishedState(of run: StoredReviewRun) -> ReviewerChip.State {
        if !run.findings.isEmpty { return .findings(run.findings.count) }
        guard let reason = inconclusiveReason(of: run) else { return .clean }
        return .inconclusive(chipText(reason, in: run))
    }

    /// Důvod chipu větou. Kratší a s malým písmenem — visí za pomlčkou v nápovědě, ne jako
    /// samostatné sdělení; delší text má `Policy.inconclusiveDetail(_:)` pro tab a notifikaci.
    private static func chipText(_ reason: InconclusiveReason, in run: StoredReviewRun) -> String {
        switch reason {
        // Počet zůstává: „nálezy se nepodařilo přečíst“ bez čísla neřekne, kolik toho chybí.
        case .droppedFindings: droppedText(run.droppedFindings)
        case .noReport: "reviewer nálezy nenahlásil"
        case .unreadCode: "reviewer neotevřel ani jeden soubor z pracovní kopie"
        }
    }

    private static func droppedText(_ count: Int) -> String {
        Plural.czech(
            count,
            one: "nález se nepodařilo přečíst",
            few: "nálezy se nepodařilo přečíst",
            many: "nálezů se nepodařilo přečíst"
        )
    }
}
