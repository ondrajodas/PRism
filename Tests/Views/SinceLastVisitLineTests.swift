import Foundation
import Testing

@testable import PRism

/// Odrážky pruhu „od tvé poslední návštěvy“ **po částech** (#284).
///
/// Testuje se model, ne kresba: části nesou význam (co se stalo / kdo / sha), a barvu a řez jim
/// dává až view. Do #284 to byl jeden řetězec, takže se nedalo tvrdit nic o tom, **co** je v řádku
/// zdůrazněné — a přesně to zadání vyžaduje.
@Suite("Odrážky „od minule“ (#284)")
struct SinceLastVisitLineTests {
    private let actor = EventActor(login: "odinuv", avatarURL: nil, isBot: false)
    private let other = EventActor(login: "vondrous", avatarURL: nil, isBot: false)

    // MARK: - Commity

    @Test("Počet commitů je tučný, autor ztlumený a sha jako kód")
    func setsTheCommitLine() {
        let lines = SinceLastVisitLines(changes: changes(commits: [commit("9c1de0212ab")])).lines

        #expect(lines.count == 1)
        #expect(lines[0].parts == [
            .strong("1 nový commit"),
            .plain(" od odinuv"),
            .plain(" — poslední "),
            .sha("9c1de02"),
        ])
    }

    @Test("Sha se krátí na sedm znaků")
    func shortensTheSha() {
        let lines = SinceLastVisitLines(changes: changes(commits: [commit("9c1de0212abcdef")])).lines

        #expect(lines[0].parts.contains(.sha("9c1de02")))
    }

    /// „od odinuv“ nad commity dvou lidí by tvrdilo něco, co v datech není. Jméno proto vypadne
    /// celé — počet a sha zůstávají, protože ty pravdivé jsou.
    @Test("Commity od víc lidí jméno neuvádějí")
    func omitsTheAuthorWhenItIsNotOne() {
        let lines = SinceLastVisitLines(
            changes: changes(commits: [commit("aaa1111", by: actor), commit("bbb2222", by: other)])
        ).lines

        #expect(lines[0].parts == [
            .strong("2 nové commity"),
            .plain(" — poslední "),
            .sha("bbb2222"),
        ])
    }

    @Test("Commit bez sha nekreslí prázdnou kapsli")
    func skipsAnEmptySha() {
        let lines = SinceLastVisitLines(changes: changes(commits: [commit("")])).lines

        #expect(lines[0].parts == [.strong("1 nový commit"), .plain(" od odinuv")])
    }

    // MARK: - Přepsaná historie

    @Test("Přepsaná historie má tučný začátek a zmizelou sha v kapsli")
    func setsTheRewriteLine() {
        let lines = SinceLastVisitLines(changes: changes(forcePushes: [forcePush("4f2ac9188cd")])).lines

        #expect(lines[0].parts == [
            .strong("Přepsaná historie větve"),
            .plain(" — "),
            .sha("4f2ac91"),
            .plain(" už na větvi není"),
        ])
    }

    /// GitHub `beforeCommit` občas nepošle. Věta pak zůstává, jen bez toho, co zmizelo — půlka
    /// odrážky končící pomlčkou by vypadala jako uřezaný text.
    @Test("Přepsaná historie bez staré sha je jen věta")
    func rewriteWithoutASha() {
        let lines = SinceLastVisitLines(changes: changes(forcePushes: [forcePush(nil)])).lines

        #expect(lines[0].parts == [.strong("Přepsaná historie větve")])
    }

    // MARK: - Posunutá hlava

    /// Po rebase jsou commity starší než moje návštěva, takže se do „od minule“ nedostanou —
    /// ale kód je jiný a říct se to musí.
    @Test("Posunutá hlava bez commitů má vlastní odrážku")
    func setsTheMovedHeadLine() {
        let lines = SinceLastVisitLines(changes: .none, movedHead: "9c1de0212ab").lines

        #expect(lines == [
            SinceLastVisitLine([.strong("Hlava se posunula"), .plain(" na "), .sha("9c1de02")])
        ])
    }

    @Test("S commity se posunutá hlava neopakuje")
    func prefersCommitsOverTheMovedHead() {
        let lines = SinceLastVisitLines(
            changes: changes(commits: [commit("9c1de0212ab")]),
            movedHead: "9c1de0212ab"
        ).lines

        #expect(lines.count == 1)
        #expect(lines[0].text.hasPrefix("1 nový commit"))
    }

    // MARK: - Review a komentáře

    @Test("U review je autor ztlumený a verdikt tučný")
    func setsTheReviewLine() {
        let lines = SinceLastVisitLines(changes: changes(reviews: [review(.approved)])).lines

        #expect(lines[0].parts == [.plain("vondrous "), .strong("schválil"), .plain(" PR")])
    }

    @Test("Každý verdikt má vlastní znění")
    func coversEveryVerdict() {
        #expect(text(of: .changesRequested) == "vondrous vyžádal změny")
        #expect(text(of: .dismissed) == "vondrous má zamítnuté review")
        #expect(text(of: .commented) == "vondrous napsal review")
        #expect(text(of: .pending) == "vondrous napsal review")
        #expect(text(of: nil) == "vondrous napsal review")
    }

    @Test("Komentáře jsou jeden tučný počet")
    func setsTheCommentLine() {
        let lines = SinceLastVisitLines(changes: changes(comments: [comment(), comment()])).lines

        #expect(lines[0].parts == [.strong("2 nové komentáře")])
    }

    // MARK: - Události časové osy

    /// Věta se **nepíše podruhé** — bere se z `TimelineEventRow`, včetně jeho zvýraznění.
    @Test("Událost bere větu i zvýraznění z časové osy")
    func reusesTheTimelineSentence() {
        let event = TimelineEvent(id: "9", kind: .readyForReview, actor: actor, at: Date())
        let lines = SinceLastVisitLines(changes: changes(events: [event])).lines

        #expect(lines[0].text == TimelineEventRow(event: event).title)
        #expect(lines[0].parts.contains(.strong("odinuv")))
    }

    // MARK: - Pořadí a prázdno

    /// Pořadí je podle dopadu: co mění kód, pak co mění diskuzi. Kdyby se rozhodilo, přečte se
    /// pruh jako výpis událostí, ne jako odpověď na „co je tu nového“.
    @Test("Pořadí je historie, commity, review, komentáře, události")
    func keepsTheOrder() {
        let lines = SinceLastVisitLines(
            changes: VisitChanges(
                commits: [commit("aaa1111")],
                forcePushes: [forcePush("bbb2222")],
                events: [TimelineEvent(id: "9", kind: .readyForReview, actor: actor, at: Date())],
                reviews: [review(.approved)],
                comments: [comment()]
            )
        ).lines

        #expect(lines.map(\.text) == [
            "Přepsaná historie větve — bbb2222 už na větvi není",
            "1 nový commit od odinuv — poslední aaa1111",
            "vondrous schválil PR",
            "1 nový komentář",
            "odinuv označil PR za hotový k review",
        ])
    }

    /// **Pruh se nesmí ukázat prázdný.** Bez změn a bez posunuté hlavy nemá co vypsat — a volající
    /// (`OverviewView`) ho v tom případě nekreslí vůbec.
    @Test("Bez změn nevznikne žádná odrážka")
    func staysEmpty() {
        #expect(SinceLastVisitLines(changes: .none).lines.isEmpty)
    }

    // MARK: - Materiál

    private func text(of state: SubmittedReview.State?) -> String {
        SinceLastVisitLines(changes: changes(reviews: [review(state)])).lines[0].text
    }

    private func changes(
        commits: [TimelineEvent] = [],
        forcePushes: [TimelineEvent] = [],
        events: [TimelineEvent] = [],
        reviews: [SubmittedReview] = [],
        comments: [ThreadComment] = []
    ) -> VisitChanges {
        VisitChanges(
            commits: commits,
            forcePushes: forcePushes,
            events: events,
            reviews: reviews,
            comments: comments
        )
    }

    private func commit(_ oid: String, by author: EventActor? = nil) -> TimelineEvent {
        TimelineEvent(
            id: oid.isEmpty ? "empty" : oid,
            kind: .commit(oid: oid, headline: "fix: něco"),
            actor: author ?? actor,
            at: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func forcePush(_ before: String?) -> TimelineEvent {
        TimelineEvent(
            id: "force",
            kind: .forcePushed(before: before, after: "9c1de0212ab"),
            actor: actor,
            at: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func review(_ state: SubmittedReview.State?) -> SubmittedReview {
        SubmittedReview(
            id: "r1",
            author: "vondrous",
            state: state,
            body: "",
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func comment() -> ThreadComment {
        ThreadComment(
            id: UUID().uuidString,
            author: "vondrous",
            body: "něco",
            createdAt: Date(timeIntervalSince1970: 1_000),
            url: URL(string: "https://github.com/cli/cli/pull/1#issuecomment-1")!
        )
    }
}
