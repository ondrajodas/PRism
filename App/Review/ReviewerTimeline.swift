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
    private(set) var entries: [Entry] = []

    var id: String { skill }

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

    mutating func finish(_ outcome: ReviewRunOutcome, at time: Date) {
        append(.finished(outcome), at: time)
    }

    private mutating func append(_ kind: Entry.Kind, at time: Date) {
        entries.append(Entry(id: entries.count, at: time, kind: kind))
    }
}
