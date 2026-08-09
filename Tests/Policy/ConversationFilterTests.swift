import Foundation
import Testing

@testable import PRism

/// Časová osa konverzace: co se slévá a co zúží filtr (#183).
///
/// Dvě věci se dají pokazit potichu: **slít commity, které za sebou nejdou** (mezi nimi je
/// komentář, takže do jedné skupiny nepatří — stalo se to kolem něj) a **zahodit prózu review**
/// při zúžení na komentáře. Recenze s větou je něčí text stejně jako komentář pod PR.
@Suite("Osa konverzace")
struct ConversationFilterTests {
    private func commit(_ oid: String, at seconds: TimeInterval) -> ConversationEntry {
        .event(
            TimelineEvent(
                id: "E_\(oid)",
                kind: .commit(oid: oid, headline: "fix: \(oid)"),
                actor: nil,
                at: Date(timeIntervalSince1970: seconds)
            )
        )
    }

    private func comment(_ id: String, at seconds: TimeInterval) -> ConversationEntry {
        .comment(
            ThreadComment(
                id: id,
                author: "kdosi",
                body: "co to tady dělá",
                createdAt: Date(timeIntervalSince1970: seconds),
                url: URL(string: "https://github.com/o/r/pull/1#discussion_\(id)")!
            )
        )
    }

    // MARK: - Slévání commitů

    @Test("Commity za sebou dají jeden uzel")
    func groupsConsecutiveCommits() {
        let nodes = Policy.conversation(of: [commit("a", at: 10), commit("b", at: 20), commit("c", at: 30)])

        #expect(nodes.count == 1)
        if case .commits(let events) = nodes.first {
            #expect(events.count == 3)
        } else {
            Issue.record("uzel není skupina commitů")
        }
    }

    /// **Nejcennější test téhle sady.** Commit před komentářem a po něm jsou dvě různé věci,
    /// které se staly kolem něj — slít je do jedné skupiny by z osy udělalo nesmysl.
    @Test("Komentář mezi commity skupinu přeruší")
    func splitsAroundAComment() {
        let nodes = Policy.conversation(of: [
            commit("a", at: 10),
            comment("c1", at: 20),
            commit("b", at: 30),
        ])

        #expect(nodes.count == 3)
        #expect(nodes.map(\.id).first?.hasPrefix("commits-") == true)
        #expect(nodes.last?.id.hasPrefix("commits-") == true)
    }

    /// Skupina se datuje posledním commitem — to je okamžik, ve kterém větev vypadá tak,
    /// jak vypadá teď.
    @Test("Skupina nese čas posledního commitu")
    func datesTheGroupByItsLastCommit() {
        let nodes = Policy.conversation(of: [commit("a", at: 10), commit("b", at: 90)])

        #expect(nodes.first?.date == Date(timeIntervalSince1970: 90))
    }

    @Test("Prázdná osa dá prázdno")
    func handlesAnEmptyTimeline() {
        #expect(Policy.conversation(of: []).isEmpty)
    }

    // MARK: - Zúžení

    @Test("Komentáře nechají komentáře, události zahodí")
    func narrowsToComments() {
        let nodes = Policy.conversation(
            of: [commit("a", at: 10), comment("c1", at: 20)],
            filter: .comments
        )

        #expect(nodes.count == 1)
        #expect(nodes.first?.id.hasPrefix("c") == true)
    }

    @Test("Události nechají commity")
    func narrowsToEvents() {
        let nodes = Policy.conversation(
            of: [commit("a", at: 10), comment("c1", at: 20)],
            filter: .events
        )

        #expect(nodes.count == 1)
        #expect(nodes.first?.id.hasPrefix("commits-") == true)
    }

    @Test("Počty se berou z plné osy, ne ze zúžené")
    func countsTheWholeTimeline() {
        let counts = Policy.conversationCounts(of: [
            commit("a", at: 10),
            commit("b", at: 20),
            comment("c1", at: 30),
        ])

        #expect(counts[.all] == 3)
        #expect(counts[.events] == 2)
        #expect(counts[.comments] == 1)
        #expect(counts[.threads] == 0)
    }
}
