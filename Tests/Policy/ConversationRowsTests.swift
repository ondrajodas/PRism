import Foundation
import Testing

@testable import PRism

/// Řádky časové osy (#361) — identita a značka poslední návštěvy.
///
/// Do #361 se obojí počítalo ve `ConversationView` (`Array(nodes.enumerated())` a
/// `isFirstNew(_:at:in:)`) a **nebyl na to ani jeden test**: značka se dala posunout, zdvojit
/// nebo úplně zahodit a build i testy zůstaly zelené. Vyčerpávající výčet je proto tady.
@Suite("Řádky časové osy (#361)")
struct ConversationRowsTests {
    /// Identita řádku je tatáž jako identita uzlu — jinak by se `ForEach` po přechodu na řádky
    /// začal chovat jinak, protože identita rozhoduje o tom, co se považuje za týž řádek.
    @Test("Identita řádku je identita uzlu")
    func identityMatchesNode() {
        let rows = Policy.conversationRows(of: [comment(1, at: 100), event(2, at: 200)], since: nil)
        #expect(rows.map(\.id) == rows.map(\.node.id))
        #expect(rows.map(\.id) == ["c1", "e2"])
    }

    @Test("Bez poslední návštěvy se značka nekreslí")
    func noMarkerWithoutVisit() {
        let rows = Policy.conversationRows(of: [comment(1, at: 100), comment(2, at: 200)], since: nil)
        #expect(rows.map(\.isFirstNew) == [false, false])
    }

    /// Když je nové **všechno**, patří značka úplně nahoru. Původní podoba (`index > 0`) ji
    /// v tom případě zahodila — nález Copilota na #173, takže tenhle případ je regresní.
    @Test("Když je nové všechno, značka je u prvního řádku")
    func markerAtTopWhenEverythingIsNew() {
        let rows = Policy.conversationRows(
            of: [comment(1, at: 300), comment(2, at: 400)],
            since: Date(timeIntervalSince1970: 200)
        )
        #expect(rows.map(\.isFirstNew) == [true, false])
    }

    @Test("Značka se kreslí před první novou položkou")
    func markerBeforeFirstNew() {
        let rows = Policy.conversationRows(
            of: [comment(1, at: 100), comment(2, at: 300), comment(3, at: 400)],
            since: Date(timeIntervalSince1970: 200)
        )
        #expect(rows.map(\.isFirstNew) == [false, true, false])
    }

    /// **Prokládané datum dostane druhou značku, a je to schválně**: dvě staré položky mezi
    /// novými znamenají dvě různá místa, odkud dolů je něco nového. Kdyby se značka omezila na
    /// jednu, chovala by se osa po force-pushi jinak, než jak je popsaná.
    @Test("Staré položky mezi novými dají druhou značku")
    func markerRepeatsAfterOldNode() {
        let rows = Policy.conversationRows(
            of: [comment(1, at: 300), comment(2, at: 100), comment(3, at: 400)],
            since: Date(timeIntervalSince1970: 200)
        )
        #expect(rows.map(\.isFirstNew) == [true, false, true])
    }

    /// Položka bez data značku nedostane a **nesmí ji dát ani té za sebou**: `nil` znamená
    /// „nevíme kdy“, a z toho se nedá tvrdit, že to, co následuje, je nové.
    @Test("Položka bez data značku nezakládá")
    func undatedNodeCarriesNoMarker() {
        let rows = Policy.conversationRows(
            of: [pendingReview(), comment(2, at: 400)],
            since: Date(timeIntervalSince1970: 200)
        )
        #expect(rows.map(\.isFirstNew) == [false, false])
    }

    /// Zúžení mění, které řádky na ose jsou — takže i to, který z nich je první nový. Značka se
    /// proto počítá **po** filtru, ne před ním.
    @Test("Značka se počítá po zúžení osy")
    func markerFollowsFilter() {
        let entries = [comment(1, at: 100), event(2, at: 300), comment(3, at: 400)]
        let all = Policy.conversationRows(of: entries, filter: .all, since: Date(timeIntervalSince1970: 200))
        let comments = Policy.conversationRows(of: entries, filter: .comments, since: Date(timeIntervalSince1970: 200))
        #expect(all.map(\.id) == ["c1", "e2", "c3"])
        #expect(all.map(\.isFirstNew) == [false, true, false])
        #expect(comments.map(\.id) == ["c1", "c3"])
        #expect(comments.map(\.isFirstNew) == [false, true])
    }

    @Test("Prázdná osa nedá žádný řádek")
    func emptyTimeline() {
        #expect(Policy.conversationRows(of: [], since: Date(timeIntervalSince1970: 200)).isEmpty)
    }

    // MARK: - Materiál

    private func comment(_ id: Int, at seconds: TimeInterval) -> ConversationEntry {
        .comment(ThreadComment(
            id: "\(id)",
            author: "octocat",
            body: "text",
            createdAt: Date(timeIntervalSince1970: seconds),
            url: URL(string: "https://github.com/cli/cli/pull/1#issuecomment-\(id)")!
        ))
    }

    private func event(_ id: Int, at seconds: TimeInterval) -> ConversationEntry {
        .event(TimelineEvent(
            id: "\(id)",
            kind: .readyForReview,
            actor: nil,
            at: Date(timeIntervalSince1970: seconds)
        ))
    }

    /// Review bez data odeslání — rozdělané (`pending`) review datum nemá.
    private func pendingReview() -> ConversationEntry {
        .review(SubmittedReview(
            id: "9",
            author: "hubot",
            state: .commented,
            body: "próza",
            submittedAt: nil
        ))
    }
}
