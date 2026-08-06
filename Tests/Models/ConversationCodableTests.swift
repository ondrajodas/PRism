import Foundation
import Testing

@testable import PRism

/// Round-trip modelů konverzace. Nepersistují se, ale konvence platí pro všechny modely —
/// a `ConversationPage` je generický typ, u kterého se syntéza `Codable` může rozejít
/// s tím, co čekáme.
@Suite("Conversation — Codable")
struct ConversationCodableTests {
    private func comment(
        id: String = "c1",
        author: String = "kdosi",
        replyTo: String? = nil
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "tělo",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            url: URL(string: "https://github.com/cli/cli/pull/1#discussion_r1")!,
            replyToID: replyTo
        )
    }

    private func thread(
        line: Int? = 42,
        side: DiffSide? = .right,
        hunk: String? = "@@ -40,3 +40,3 @@\n kontext\n-staré\n+nové"
    ) -> ReviewThread {
        ReviewThread(
            id: "t1",
            path: "pkg/cmd/main.go",
            line: line,
            originalLine: 42,
            side: side,
            isResolved: true,
            isOutdated: line == nil,
            diffHunk: hunk,
            comments: ConversationPage(
                items: [comment(), comment(id: "c2", replyTo: "c1")],
                total: 2,
                hasNextPage: false
            )
        )
    }

    @Test("ThreadComment přežije round-trip")
    func roundTripsAComment() throws {
        #expect(try roundTrip(comment()) == comment())
        #expect(try roundTrip(comment(replyTo: "c1")) == comment(replyTo: "c1"))
    }

    @Test("ReviewThread přežije round-trip včetně zastaralého")
    func roundTripsAThread() throws {
        #expect(try roundTrip(thread()) == thread())
        #expect(try roundTrip(thread(line: nil)) == thread(line: nil))
        #expect(try roundTrip(thread(side: nil)) == thread(side: nil))
        #expect(try roundTrip(thread(side: .left)) == thread(side: .left))
        // Víceřádkový text v JSONu je to, co se u `diffHunk` (#158) může pokazit potichu —
        // a chybějící hunk se musí odlišit od prázdného, jinak by z „nevíme“ vyšel prázdný
        // úryvek.
        #expect(try roundTrip(thread(hunk: nil)) == thread(hunk: nil))
        #expect(try roundTrip(thread(hunk: "")) == thread(hunk: ""))
    }

    /// `state` a `submittedAt` jsou optional a asociovaná hodnota `nil` se z JSONu ztrácí
    /// nejtišeji — proto každý případ zvlášť.
    @Test("SubmittedReview přežije round-trip v každém stavu", arguments: [
        SubmittedReview.State.approved,
        .changesRequested,
        .commented,
        .dismissed,
        .pending,
    ])
    func roundTripsAReview(state: SubmittedReview.State) throws {
        let review = SubmittedReview(
            id: "r1",
            author: "kdosi",
            state: state,
            body: "",
            submittedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )

        #expect(try roundTrip(review) == review)
    }

    @Test("Review bez stavu a bez času přežije round-trip")
    func roundTripsAStatelessReview() throws {
        let review = SubmittedReview(
            id: "r1",
            author: "kdosi",
            state: nil,
            body: "tělo",
            submittedAt: nil
        )

        #expect(try roundTrip(review) == review)
    }

    @Test("Celá konverzace přežije round-trip")
    func roundTripsTheWholeConversation() throws {
        let conversation = Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(
                items: [
                    SubmittedReview(
                        id: "r1",
                        author: "kdosi",
                        state: .approved,
                        body: "",
                        submittedAt: Date(timeIntervalSince1970: 1_760_000_000)
                    ),
                ],
                total: 3,
                hasNextPage: true
            ),
            threads: ConversationPage(items: [thread()], total: 1, hasNextPage: false),
            comments: ConversationPage(items: [comment()], total: 1, hasNextPage: false)
        )

        let decoded = try roundTrip(conversation)

        #expect(decoded == conversation)
        // Zkrácení musí přežít taky — jinak by po round-tripu vypadala utnutá data úplně.
        #expect(decoded.isTruncated)
        #expect(decoded.reviews.missing == 2)
    }

    // MARK: - Zkrácení

    @Test("Prázdná stránka není zkrácená")
    func doesNotCallAnEmptyPageTruncated() {
        let page = ConversationPage<ThreadComment>(items: [], total: 0, hasNextPage: false)

        #expect(!page.isTruncated)
        #expect(page.missing == 0)
    }

    /// `or` dvou signálů: stačí jeden.
    @Test("Zkrácení hlásí kterýkoli ze dvou signálů")
    func reportsTruncationFromEitherSignal() {
        let byFlag = ConversationPage(items: [comment()], total: 1, hasNextPage: true)
        let byCount = ConversationPage(items: [comment()], total: 5, hasNextPage: false)

        #expect(byFlag.isTruncated)
        #expect(byCount.isTruncated)
        #expect(byCount.missing == 4)
    }

    /// Kdyby `total` z API zůstal pozadu, je „nechybí nic“ lepší než záporný počet.
    @Test("Chybí nikdy není záporné")
    func neverReportsANegativeCount() {
        let page = ConversationPage(items: [comment(), comment(id: "c2")], total: 1, hasNextPage: false)

        #expect(page.missing == 0)
    }

    /// Useknutý komentář **uvnitř** vlákna se v počtu vláken neprojeví — a je to zrovna ta
    /// odpověď, kvůli které se člověk do vlákna dívá.
    @Test("Zkrácení uvnitř vlákna je vidět na celé konverzaci")
    func noticesTruncationInsideAThread() {
        let truncatedThread = ReviewThread(
            id: "t1",
            path: "a.go",
            line: 1,
            originalLine: 1,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [comment()], total: 9, hasNextPage: true)
        )
        let conversation = Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [truncatedThread], total: 1, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )

        #expect(!conversation.threads.isTruncated)
        #expect(conversation.isTruncated)
    }

    // MARK: - Kotva

    @Test("Vlákno s aktuálním řádkem se kotví na něj")
    func anchorsToTheCurrentLine() {
        #expect(thread(line: 7).anchorLine == 7)
    }

    @Test("Vlákno bez čísel kotvu nemá")
    func hasNoAnchorWithoutLines() {
        let nowhere = ReviewThread(
            id: "t",
            path: "a.go",
            line: nil,
            originalLine: nil,
            side: nil,
            isResolved: false,
            isOutdated: true,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )

        #expect(nowhere.anchorLine == nil)
    }
}
