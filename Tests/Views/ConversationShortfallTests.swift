import Foundation
import Testing

@testable import PRism

/// Hláška o tom, co se z konverzace nevešlo.
@Suite("ConversationShortfall")
struct ConversationShortfallTests {
    private func conversation(
        comments: [ThreadComment] = [],
        commentsTotal: Int? = nil,
        events: [TimelineEvent] = [],
        eventsHaveNextPage: Bool = false
    ) -> Conversation {
        Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(
                items: comments,
                total: commentsTotal ?? comments.count,
                hasNextPage: false
            ),
            events: ConversationPage(items: events, hasNextPage: eventsHaveNextPage)
        )
    }

    private func comment(id: String) -> ThreadComment {
        ThreadComment(
            id: id,
            author: "kolega",
            body: "text",
            createdAt: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/cli/cli/pull/1#issuecomment-\(id)")!
        )
    }

    @Test("Nic nechybí, nic se nehlásí")
    func staysQuietWhenNothingIsMissing() {
        #expect(!ConversationShortfall(conversation()).any)
    }

    @Test("Chybějící komentáře se počítají")
    func countsMissingComments() {
        let value = ConversationShortfall(conversation(comments: [comment(id: "a")], commentsTotal: 4))

        #expect(value.any)
        #expect(value.summary.contains("3 komentáře"))
    }

    /// **Useknutá časová osa nemá počet.** `timelineItems` s `itemTypes` vrací `totalCount`
    /// bez filtru, takže z něj nejde spočítat, kolik událostí chybí — zbývá `hasNextPage`.
    /// Mlčet o tom nejde: chybějící push se od „nic se nestalo“ nepozná.
    @Test("Useknutá časová osa se hlásí i bez počtu")
    func reportsATruncatedTimelineWithoutACount() {
        let value = ConversationShortfall(conversation(eventsHaveNextPage: true))

        #expect(value.any)
        #expect(value.summary.contains("historie"))
        #expect(!value.summary.contains("0"), "počet neznáme, takže se nemá čím chlubit")
    }

    @Test("Chybějící komentáře a osa se hlásí naráz")
    func combinesBothShortfalls() {
        let value = ConversationShortfall(conversation(
            comments: [comment(id: "a")],
            commentsTotal: 3,
            eventsHaveNextPage: true
        ))

        #expect(value.summary.contains("2 komentáře"))
        #expect(value.summary.contains("historie"))
    }

    /// Celá osa, která dorazila, se hlásit nesmí — jinak by hláška svítila na každém PR
    /// (a to je přesně to, kvůli čemu se `totalCount` nepoužívá).
    @Test("Celá osa se nehlásí")
    func staysQuietWhenTheTimelineIsComplete() {
        let event = TimelineEvent(id: "e1", kind: .closed, actor: nil, at: nil)

        #expect(!ConversationShortfall(conversation(events: [event])).any)
    }
}
