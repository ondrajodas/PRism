import Foundation
import Testing

@testable import PRism

/// Round-trip rozdělaného review. Ukládá se na disk, takže `Codable` popisuje uložený tvar
/// — a optional verdikt je zrovna to, co se z JSONu ztrácí nejtišeji.
@Suite("ReviewDraft — Codable")
struct ReviewDraftCodableTests {
    private let pr = PRIdentifier("cli/cli#42")!

    private func comment(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
        side: DiffSide = .right,
        start: DraftAnchor.Endpoint? = nil,
        origin: ReviewDraftComment.Origin = .own
    ) -> ReviewDraftComment {
        ReviewDraftComment(
            id: id,
            path: "src/Cart.php",
            anchor: DraftAnchor(line: 28, side: side, start: start),
            body: "tady se ignoruje množství",
            origin: origin
        )
    }

    @Test("Draft přežije round-trip")
    func roundTripsADraft() throws {
        let draft = ReviewDraft(
            pullRequest: pr,
            headSha: "abc123",
            body: "celkem dobré",
            verdict: .requestChanges,
            comments: [comment()]
        )

        #expect(try roundTrip(draft) == draft)
    }

    /// `nil` verdikt není totéž jako `.comment` — první znamená „ještě nevybráno“. Kdyby se
    /// z JSONu ztratil, otevřel by se draft s verdiktem, o který nikdo neřekl.
    @Test("Draft bez verdiktu přežije round-trip")
    func roundTripsADraftWithoutAVerdict() throws {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "rozepsané")

        let decoded = try roundTrip(draft)

        #expect(decoded == draft)
        #expect(decoded.verdict == nil)
    }

    @Test("Každý verdikt přežije round-trip", arguments: [
        ReviewDraft.Verdict.approve,
        .requestChanges,
        .comment,
    ])
    func roundTripsEveryVerdict(verdict: ReviewDraft.Verdict) throws {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", verdict: verdict)

        #expect(try roundTrip(draft).verdict == verdict)
    }

    @Test("Každý původ komentáře přežije round-trip", arguments: [
        ReviewDraftComment.Origin.own,
        .finding(reviewer: "code-review:code-review"),
    ])
    func roundTripsEveryOrigin(origin: ReviewDraftComment.Origin) throws {
        let value = comment(origin: origin)

        #expect(try roundTrip(value) == value)
    }

    /// Jméno revieweera je to, čím se pozná, který nález už v draftu je. Kdyby se z JSONu
    /// ztratilo, po restartu by odznak „v mém review“ zmizel z převzatého nálezu — a ten by
    /// se dal převzít podruhé.
    @Test("Reviewer u převzatého nálezu přežije round-trip")
    func roundTripsTheAdoptedReviewer() throws {
        let value = comment(origin: .finding(reviewer: "oj-php-quality-check"))

        #expect(try roundTrip(value).origin.reviewer == "oj-php-quality-check")
    }

    /// Strana je to, bez čeho komentář odejde na jiný řádek — u odebraného řádku zvlášť.
    @Test("Strana komentáře přežije round-trip", arguments: [DiffSide.left, .right])
    func roundTripsTheSide(side: DiffSide) throws {
        let value = comment(side: side)

        #expect(try roundTrip(value) == value)
    }

    @Test("Identita komentáře se round-tripem nemění")
    func keepsTheCommentIdentity() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        #expect(try roundTrip(comment(id: id)).id == id)
    }

    // MARK: - Rozsah (#110)

    @Test("Rozsah komentáře přežije round-trip")
    func roundTripsARange() throws {
        let start = DraftAnchor.Endpoint(line: 20, side: .right)

        let restored = try roundTrip(comment(start: start))

        #expect(restored.anchor.start == start)
        #expect(restored.anchor.line == 28)
        #expect(restored.anchor.isRange)
    }

    @Test("Rozsah přes obě strany přežije round-trip")
    func roundTripsAMixedRange() throws {
        let start = DraftAnchor.Endpoint(line: 20, side: .left)

        #expect(try roundTrip(comment(start: start)).anchor.start == start)
    }

    /// **Draft z disku vznikl u #65 bez rozsahu.** Chybějící klíč proto musí znamenat jeden
    /// řádek, ne nečitelný soubor — jinak by aktualizace aplikace zahodila rozdělaná review,
    /// tedy ručně psanou práci, kterou nedostane zpátky žádný další běh.
    @Test("Starší draft bez rozsahu se přečte jako jednořádkový komentář")
    func readsAnOlderDraftWithoutARange() throws {
        let json = """
            {
              "pullRequest": "cli/cli#42",
              "headSha": "abc123",
              "body": "",
              "comments": [
                {
                  "id": "00000000-0000-0000-0000-0000000000AA",
                  "path": "src/Cart.php",
                  "line": 28,
                  "side": "RIGHT",
                  "body": "tady se ignoruje množství",
                  "origin": {"own": {}}
                }
              ]
            }
            """

        let draft = try JSONDecoder().decode(ReviewDraft.self, from: Data(json.utf8))

        let comment = try #require(draft.comments.first)
        #expect(comment.anchor.start == nil)
        #expect(!comment.anchor.isRange)
        #expect(comment.line == 28)
    }

    /// Půl kotvy je horší než žádná: číslo bez strany by znamenalo hádat, ke které verzi souboru
    /// rozsah patří, a komentář by odešel jinam.
    @Test("Rozsah bez strany se nebere jako rozsah")
    func ignoresAHalfWrittenRange() throws {
        let json = """
            {
              "id": "00000000-0000-0000-0000-0000000000AA",
              "path": "src/Cart.php",
              "line": 28,
              "side": "RIGHT",
              "startLine": 20,
              "body": "půl kotvy",
              "origin": {"own": {}}
            }
            """

        let comment = try JSONDecoder().decode(ReviewDraftComment.self, from: Data(json.utf8))

        #expect(comment.anchor.start == nil)
    }

    /// Verdikt jde do `event` při odeslání, takže se na jeho zápis spoléhá API GitHubu.
    @Test("Verdikt se kóduje jako hodnota, kterou bere GitHub")
    func encodesTheVerdictAsTheGitHubEvent() throws {
        let json = try encodedJSON(
            ReviewDraft(pullRequest: pr, headSha: "abc", verdict: .requestChanges)
        )

        #expect(json.contains("REQUEST_CHANGES"))
    }

    /// Identifikátor PR se kóduje na řetězec, ne na objekt — jeden kanonický zápis pro disk
    /// i pro UI.
    @Test("Identifikátor PR je v JSONu řetězec, ne objekt")
    func encodesTheIdentifierAsAString() throws {
        let json = try encodedJSON(ReviewDraft(pullRequest: pr, headSha: "abc", body: "x"))

        // Lomítko `JSONEncoder` escapuje na `\/`, takže se hledá začátek hodnoty: za
        // dvojtečkou musí být uvozovka, ne `{`.
        #expect(json.contains("\"pullRequest\":\""))
        #expect(!json.contains("\"pullRequest\":{"))
    }

    /// Dva komentáře na jednom řádku jsou legitimní — jiná věc ke stejnému kódu.
    @Test("Dva komentáře na jednom řádku se nesloučí")
    func keepsTwoCommentsOnOneLine() throws {
        let first = comment(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let second = comment(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let draft = ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [first, second]
        )

        #expect(try roundTrip(draft).comments.count == 2)
    }
}
