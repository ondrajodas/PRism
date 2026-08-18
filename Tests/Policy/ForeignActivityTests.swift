import Foundation
import Testing

@testable import PRism

/// Cizí aktivita na vlastním PR (#335) — co z konverzace je novinka **od někoho jiného**.
///
/// Nejcennější tvrzení jsou tady dvě, a obě říkají, že se něco **nestalo**: vlastní komentář není
/// cizí aktivita (jinak by aplikace hlásila, že jsem něco napsal) a bez značky se nepočítá nic
/// (jinak by při prvním spuštění přišla lavina o měsíc starých komentářích).
@Suite("Policy.foreignActivity — cizí aktivita na vlastním PR (#335)")
struct ForeignActivityTests {
    private let baseline = Date(timeIntervalSince1970: 1000)

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func comment(
        id: String = "c1",
        by author: String = "kolega",
        body: String = "text",
        at seconds: TimeInterval = 2000
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: at(seconds),
            url: URL(string: "https://github.com/cli/cli/pull/42#issuecomment-\(id)")!
        )
    }

    private func review(
        id: String = "r1",
        by author: String = "kolega",
        state: SubmittedReview.State? = .changesRequested,
        at seconds: TimeInterval? = 2000
    ) -> SubmittedReview {
        SubmittedReview(id: id, author: author, state: state, body: "", submittedAt: seconds.map(at))
    }

    private func thread(id: String = "t1", comments: [ThreadComment]) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "Cart.swift",
            line: 27,
            originalLine: 27,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func conversation(
        reviews: [SubmittedReview] = [],
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = []
    ) -> Conversation {
        Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    /// **Tvrzení, že se nic nestalo.** Bez značky (PR jsem nikdy neviděl a nikdy se o něm
    /// nehlásilo) by „od minule“ znamenalo „od začátku věků“ — a při prvním spuštění by z toho byla
    /// notifikace o všech komentářích, které kdy na mých PR byly.
    @Test("Bez značky se nepočítá nic")
    func withoutABaselineNothingIsNew() {
        let conversation = conversation(comments: [comment()])

        #expect(Policy.foreignActivity(in: conversation, since: nil).isEmpty)
        #expect(Policy.foreignActivity(in: nil, since: baseline).isEmpty)
        #expect(Policy.foreignActivity(in: nil, since: nil) == .none)
    }

    /// **Tvrzení, že se nic nestalo**, a to nejdůležitější z celého issue po tom prvním: můj
    /// vlastní komentář ani moje vlastní review není cizí aktivita. Bez toho by mi aplikace
    /// oznamovala, že jsem něco napsal — a to je hláška, po které si člověk notifikace vypne.
    @Test("Vlastní komentář ani vlastní review se nepočítá")
    func myOwnVoiceIsNotActivity() {
        let conversation = conversation(
            reviews: [review(by: "ja", state: .commented)],
            threads: [thread(comments: [comment(id: "mine", by: "ja")])],
            comments: [comment(id: "under", by: "ja")]
        )

        #expect(Policy.foreignActivity(in: conversation, since: baseline).isEmpty)
    }

    @Test("Cizí komentáře pod PR i ve vláknech se sčítají")
    func countsCommentsFromBothPlaces() {
        let conversation = conversation(
            threads: [thread(comments: [comment(id: "in-thread", at: 2100)])],
            comments: [comment(id: "under-pr", at: 2000)]
        )

        let activity = Policy.foreignActivity(in: conversation, since: baseline)

        #expect(activity.comments.map(\.id) == ["under-pr", "in-thread"])
        #expect(activity.count == 2)
        #expect(activity.latest == at(2100))
    }

    @Test("Starší položky zůstávají mimo")
    func olderItemsStayOut() {
        let conversation = conversation(
            reviews: [review(id: "old", at: 500)],
            comments: [comment(id: "old", at: 500), comment(id: "new", at: 2000)]
        )

        let activity = Policy.foreignActivity(in: conversation, since: baseline)

        #expect(activity.comments.map(\.id) == ["new"])
        #expect(activity.reviews.isEmpty)
    }

    /// Rozdělané review (`submittedAt == nil`) na GitHubu odeslané není, takže se o něm nemá co
    /// hlásit — tatáž podmínka jako u „od tvé poslední návštěvy“ (#173).
    @Test("Rozdělané review se nepočítá")
    func aPendingReviewIsNotActivity() {
        let conversation = conversation(reviews: [review(state: .pending, at: nil)])

        #expect(Policy.foreignActivity(in: conversation, since: baseline).isEmpty)
    }

    /// **Commity v tom nejsou schválně**: na vlastním PR je push obvykle můj a datum commitu není
    /// datum pushnutí, takže by z toho byl banner o vlastní práci.
    @Test("Commity a události osy se nepočítají")
    func commitsAndTimelineEventsAreNotActivity() {
        let conversation = Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false),
            events: ConversationPage(
                items: [
                    TimelineEvent(
                        id: "e1",
                        kind: .commit(oid: "abc1234", headline: "fix"),
                        actor: EventActor(login: "kolega", avatarURL: nil, isBot: false),
                        at: at(2000)
                    )
                ],
                hasNextPage: false
            )
        )

        #expect(Policy.foreignActivity(in: conversation, since: baseline).isEmpty)
        // A pro srovnání: pruh „od minule“ v detailu PR ten commit **vidí dál** — mění se jen to,
        // o čem se hlásí notifikací.
        #expect(Policy.changes(in: conversation, since: baseline).commits.count == 1)
    }

    @Test("Razítko oznámení je datum té nejnovější položky")
    func theStampIsTheNewestItem() {
        // Zapisuje se datum položky, ne „teď“: kdyby se zapisoval čas doručení, propadl by
        // komentář, který přišel mezi dotazem na konverzaci a zápisem razítka.
        let conversation = conversation(
            reviews: [review(at: 2500)],
            comments: [comment(at: 2000)]
        )

        #expect(Policy.foreignActivity(in: conversation, since: baseline).latest == at(2500))
        #expect(ForeignActivity.none.latest == nil)
    }

    @Test("Značka je pozdější z návštěvy a oznámení")
    func theBaselineIsTheLaterOfTheTwo() {
        // Dvě různé věci: `VisitLedger` drží návštěvu, `ActivityNoticeLedger` oznámení. Novinka je
        // to, co je novější než obojí — jinak by hláška chodila pořád dokola (kdyby rozhodovala
        // jen návštěva), nebo by se hlásilo i to, co jsem v okně přečetl (kdyby jen oznámení).
        #expect(Policy.activityBaseline(lastVisit: at(1000), lastNotice: at(2000)) == at(2000))
        #expect(Policy.activityBaseline(lastVisit: at(3000), lastNotice: at(2000)) == at(3000))
        #expect(Policy.activityBaseline(lastVisit: nil, lastNotice: at(2000)) == at(2000))
        #expect(Policy.activityBaseline(lastVisit: at(1000), lastNotice: nil) == at(1000))
        #expect(Policy.activityBaseline(lastVisit: nil, lastNotice: nil) == nil)
    }
}
