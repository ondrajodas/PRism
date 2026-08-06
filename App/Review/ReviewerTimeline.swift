import Foundation

/// Co reviewer dělal, v pořadí, v jakém se to dělo.
///
/// Drží se v paměti, ne na disku: k průběhu se člověk vrací hned po běhu („co to vlastně
/// četlo?“), ne po restartu — a po restartu už by se k session stejně nedalo připojit.
struct ReviewerTimeline: Identifiable, Equatable, Sendable {
    let skill: String
    /// Pracovní strom, ve kterém běh běžel. Podle něj se v ose zkracují cesty — bez toho
    /// začíná každý řádek stejnými sedmdesáti znaky cache.
    let worktree: URL?
    /// Cesta k `claude --resume`. Přijde s prvním eventem session.
    var sessionID: String?
    /// Co běh stál (#148). Přijde s koncem běhu, protože ji nese `result` event — takže
    /// běžící reviewer ji nemá a zabitý ji mít nebude. `nil` je odpověď „nevíme“, ne nula.
    var usage: RunUsage?
    private(set) var entries: [Entry] = []

    var id: String { skill }

    /// Doběhl už tenhle běh? Pozná se podle toho, že v ose je jeho konec.
    var isFinished: Bool {
        entries.contains { if case .finished = $0.kind { true } else { false } }
    }

    struct Entry: Identifiable, Equatable, Sendable {
        /// Pořadí v ose. `Date` na identitu nestačí — dva eventy můžou padnout do stejné
        /// milisekundy.
        let id: Int
        let at: Date
        let kind: Kind

        enum Kind: Equatable, Sendable {
            case queued
            case started
            case tool(ToolAttempt)
            case findings(count: Int)
            case finished(ReviewRunOutcome)
        }
    }

    init(skill: String, worktree: URL? = nil) {
        self.skill = skill
        self.worktree = worktree
    }

    /// Který skill si session doopravdy načetla. `nil` = žádný.
    var loadedSkill: String? {
        entries.lazy.compactMap { entry -> String? in
            guard case .tool(let tool) = entry.kind, tool.name == "Skill" else { return nil }
            return tool.detail
        }.first
    }

    /// Načetl se **jiný** skill, než jaký byl nastavený?
    ///
    /// Stává se to, když nakonfigurované id na nic nemapuje: model si domyslí nejbližší,
    /// co jde oslovit — ověřeno u #78, kde se z `code-review` stalo `code-review:code-review`.
    /// Bez upozornění by osa i chip tvrdily, že běžel nastavený skill, a běžel by jiný.
    ///
    /// Běh **bez** načteného skillu se sem nepočítá: reviewer, který si žádný nevzal, udělal
    /// obecné review, a to je jiná situace než záměna.
    var loadedADifferentSkill: Bool {
        guard let loadedSkill else { return false }
        return loadedSkill != skill
    }

    /// Nejnovější událost napříč reviewery — podle ní se osa posouvá na konec.
    ///
    /// Napříč, ne z poslední osy v poli: reviewery běží paralelně, takže nová událost
    /// klidně přibude do té dřívější a osa by se přestala posouvat.
    static func newestEntry(in timelines: [ReviewerTimeline]) -> (skill: String, entry: Int)? {
        timelines
            .compactMap { timeline in timeline.entries.last.map { (timeline.skill, $0.id, $0.at) } }
            .max { $0.2 < $1.2 }
            .map { (skill: $0.0, entry: $0.1) }
    }

    mutating func record(_ progress: ReviewProgress, at time: Date) {
        switch progress {
        case .queued:
            append(.queued, at: time)
        case .started(let sessionID):
            self.sessionID = sessionID
            append(.started, at: time)
        case .attemptedTool(let tool):
            append(.tool(tool), at: time)
        case .findings(let count):
            append(.findings(count: count), at: time)
        }
    }

    mutating func finish(_ outcome: ReviewRunOutcome, usage: RunUsage? = nil, at time: Date) {
        self.usage = usage
        append(.finished(outcome), at: time)
    }

    private mutating func append(_ kind: Entry.Kind, at time: Date) {
        entries.append(Entry(id: entries.count, at: time, kind: kind))
    }
}
