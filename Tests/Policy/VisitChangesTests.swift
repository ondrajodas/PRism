import Foundation
import Testing

@testable import PRism

@Suite("Policy.changes — co přibylo od minule")
struct VisitChangesTests {
    private let visit = Date(timeIntervalSince1970: 1000)

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func event(
        id: String = "e1",
        _ kind: TimelineEvent.Kind,
        by login: String = "kolega",
        at seconds: TimeInterval? = 2000
    ) -> TimelineEvent {
        TimelineEvent(
            id: id,
            kind: kind,
            actor: EventActor(login: login, avatarURL: nil, isBot: false),
            at: seconds.map(at)
        )
    }

    private func comment(
        id: String = "c1",
        by author: String = "kolega",
        at seconds: TimeInterval = 2000
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "text",
            createdAt: at(seconds),
            url: URL(string: "https://github.com/cli/cli/pull/42#issuecomment-\(id)")!
        )
    }

    private func review(
        id: String = "r1",
        by author: String = "kolega",
        state: SubmittedReview.State? = .approved,
        at seconds: TimeInterval? = 2000
    ) -> SubmittedReview {
        SubmittedReview(
            id: id,
            author: author,
            state: state,
            body: "",
            submittedAt: seconds.map(at)
        )
    }

    private func conversation(
        reviews: [SubmittedReview] = [],
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = [],
        events: [TimelineEvent] = []
    ) -> Conversation {
        Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false),
            events: ConversationPage(items: events, hasNextPage: false)
        )
    }

    @Test("Bez značky se neukáže nic")
    func withoutAMarkNothingIsNew() {
        // PR, který vidím poprvé, nemá „od minule" — jinak by se vypsala celá jeho historie
        // a banner by tvrdil, že to všechno přibylo teď.
        let conversation = conversation(events: [event(.commit(oid: "abc", headline: "fix"))])

        #expect(Policy.changes(in: conversation, since: nil) == .none)
        #expect(Policy.changes(in: nil, since: visit) == .none)
        #expect(Policy.changes(in: conversation, since: nil).isEmpty)
    }

    @Test("Počítá se jen to, co přišlo po návštěvě")
    func onlyWhatArrivedAfterTheVisitCounts() {
        let conversation = conversation(events: [
            event(id: "old", .commit(oid: "aaa", headline: "staré"), at: 500),
            event(id: "new", .commit(oid: "bbb", headline: "nové"), at: 2000),
        ])

        #expect(Policy.changes(in: conversation, since: visit).commits.map(\.id) == ["new"])
    }

    @Test("Událost v tutéž sekundu se nepočítá dvakrát")
    func anEventAtTheVisitInstantIsNotNew() {
        // Ostré porovnání: návštěva zapsaná ve stejnou sekundu, kdy něco přišlo, tu položku
        // příště zopakovat nemá.
        let conversation = conversation(events: [event(.commit(oid: "aaa", headline: "x"), at: 1000)])

        #expect(Policy.changes(in: conversation, since: visit).isEmpty)
    }

    @Test("Událost bez data se zahodí")
    func anEventWithoutADateIsDropped() {
        // `nil` znamená „nevíme kdy" — zařadit ji mezi novinky by tvrdilo „přišlo to teď",
        // což z dat neplyne. Opatrný směr je vynechat.
        let conversation = conversation(events: [event(.commit(oid: "aaa", headline: "x"), at: nil)])

        #expect(Policy.changes(in: conversation, since: visit).isEmpty)
    }

    @Test("Přepsaná historie má vlastní pole")
    func aForcePushIsKeptApart() {
        // Jako jediná událost má důsledek pro naše data: po ní zastarají nálezy i draft.
        let conversation = conversation(events: [
            event(id: "push", .forcePushed(before: "aaa", after: "bbb")),
            event(id: "commit", .commit(oid: "bbb", headline: "fix")),
            event(id: "ready", .readyForReview),
        ])

        let changes = Policy.changes(in: conversation, since: visit)

        #expect(changes.forcePushes.map(\.id) == ["push"])
        #expect(changes.commits.map(\.id) == ["commit"])
        #expect(changes.events.map(\.id) == ["ready"])
    }

    /// Force push se **nesmí přimíchat k obyčejným událostem** — na tom stojí věta o tom, že
    /// nálezy na obrazovce platí proti commitu, který na větvi už není.
    @Test("Bez force-pushe zůstane přihrádka prázdná")
    func withoutAForcePushNothingWasRewritten() {
        let conversation = conversation(events: [event(.commit(oid: "bbb", headline: "fix"))])

        #expect(Policy.changes(in: conversation, since: visit).forcePushes.isEmpty)
    }

    @Test("Moje komentáře nejsou novinka")
    func myOwnCommentsAreNotNews() {
        // Že jsem něco napsal já, nemá cenu hlásit — banner odpovídá na „co se stalo, když
        // jsem se nedíval".
        let conversation = conversation(comments: [
            comment(id: "mine", by: "ja"),
            comment(id: "theirs", by: "kolega"),
        ])

        #expect(Policy.changes(in: conversation, since: visit).comments.map(\.id) == ["theirs"])
    }

    @Test("Komentáře ve vláknech se počítají taky")
    func commentsInsideThreadsCountAsWell() {
        // Odpověď ve vlákně je „někdo mi něco napsal" úplně stejně jako komentář pod PR.
        let thread = ReviewThread(
            id: "t1",
            path: "Cart.php",
            line: 27,
            originalLine: 27,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [comment(id: "reply")], total: 1, hasNextPage: false)
        )

        #expect(
            Policy.changes(in: conversation(threads: [thread]), since: visit).comments.map(\.id)
                == ["reply"]
        )
    }

    @Test("Neodeslané cizí review se nepočítá")
    func aPendingReviewIsNotCounted() {
        // Na GitHubu ještě odeslané není, takže se o něm nemá co říkat.
        let conversation = conversation(reviews: [
            review(id: "pending", state: .pending, at: nil),
            review(id: "sent"),
        ])

        #expect(Policy.changes(in: conversation, since: visit).reviews.map(\.id) == ["sent"])
    }

    @Test("Všechno je chronologicky")
    func everythingIsChronological() {
        // Banner se čte jako věty za sebou, takže pořadí musí odpovídat tomu, jak se to stalo.
        let conversation = conversation(events: [
            event(id: "third", .commit(oid: "c", headline: "c"), at: 3000),
            event(id: "first", .commit(oid: "a", headline: "a"), at: 1500),
            event(id: "second", .commit(oid: "b", headline: "b"), at: 2000),
        ])

        #expect(
            Policy.changes(in: conversation, since: visit).commits.map(\.id)
                == ["first", "second", "third"]
        )
    }

    @Test("Zavření po mergi se nepočítá")
    func closingAfterAMergeIsNotShown() {
        // Stejné pravidlo jako v `Přehledu` (#171): GitHub posílá `closed` i k mergnutému PR
        // a dvě věty o téže věci jsou o jednu víc.
        let conversation = conversation(events: [
            event(id: "merged", .merged(into: "main"), at: 2000),
            event(id: "closed", .closed, at: 2001),
        ])

        #expect(Policy.changes(in: conversation, since: visit).events.map(\.id) == ["merged"])
    }

    // MARK: - Odznak u záložky Přehled (#218)

    /// Odznak musí slíbit **přesně to číslo**, které po rozkliknutí vypíše blok „od tvé
    /// poslední návštěvy“ — tedy všech pět kategorií, ne jen commity.
    @Test("Počet sečte všech pět kategorií")
    func countsEveryCategory() {
        let conversation = conversation(
            reviews: [review(id: "r", by: "vondrous")],
            comments: [comment(id: "c", by: "odinuv")],
            events: [
                event(id: "push", .forcePushed(before: "aaa", after: "bbb")),
                event(id: "commit", .commit(oid: "bbb", headline: "fix")),
                event(id: "ready", .readyForReview),
            ]
        )

        #expect(Policy.changes(in: conversation, since: visit).count == 5)
    }

    /// `0` by u odznaku znamenalo „spočítalo se a vyšlo prázdno“, což je pravda — a proto se
    /// odznak nekreslí. Test drží dohodu, že prázdno je nula, ne něco jiného.
    @Test("Bez novinek je počet nula")
    func countsNothingWhenNothingIsNew() {
        #expect(VisitChanges.none.count == 0)
        #expect(Policy.changes(in: conversation(), since: visit).count == 0)
    }
}
