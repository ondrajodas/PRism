import Foundation
import Testing

@testable import PRism

/// Kdo je v sekci `Reviewery` a s jakou odpovědí (#392).
///
/// Čistá funkce, takže **vyčerpávající výčet**: `SubmittedReview.State` má pět hodnot a k nim
/// `nil`, a u každé se musí dát říct, co z ní v sekci vyjde.
@Suite("Reviewery v panelu")
struct PanelReviewersTests {
    @Test("Vyžádané review bez odpovědi je čeká")
    func pendingRequestWaits() {
        #expect(Policy.reviewers(requested: ["odinuv"], verdicts: []) == [
            RequestedReviewer(login: "odinuv", answer: .waiting),
        ])
    }

    /// Vyčerpávající tabulka: co který stav review v sekci znamená. `nil` je „stav, kterému
    /// nerozumíme“, a ten se do sekce nedostane ze stejného důvodu jako komentář — není to verdikt.
    @Test(
        "Do sekce jdou jen verdikty",
        arguments: [
            (SubmittedReview.State.approved, ReviewerAnswer.approved),
            (.changesRequested, .changesRequested),
        ]
    )
    func verdictsBecomeAnswers(state: SubmittedReview.State, answer: ReviewerAnswer) {
        #expect(Policy.reviewers(requested: [], verdicts: [.init(login: "odinuv", state: state)]) == [
            RequestedReviewer(login: "odinuv", answer: answer),
        ])
    }

    /// **Tvrdí, že se něco NEstalo**: kdo neřekl ani ano, ani ne, a nikdo ho nežádal, v sekci není.
    /// Bez toho by v ní u každého PR svítil review bot jako `čeká`.
    @Test(
        "Review bez verdiktu se nekreslí",
        arguments: [SubmittedReview.State.commented, .dismissed, .pending]
    )
    func nonVerdictsAreDropped(state: SubmittedReview.State) {
        #expect(Policy.reviewers(requested: [], verdicts: [.init(login: "bot", state: state)]).isEmpty)
    }

    @Test("Neznámý stav se do sekce nedostane")
    func unknownStateIsDropped() {
        #expect(Policy.reviewers(requested: [], verdicts: [.init(login: "bot", state: nil)]).isEmpty)
    }

    /// **Vyžádání přebíjí starší verdikt.** Po pushnutí opravy GitHub review znovu vyžádá a to staré
    /// `CHANGES_REQUESTED` je odpověď na kód, který už tam není — takže na otázku „na kom to stojí“
    /// je správná odpověď `čeká`.
    @Test("Znovu vyžádané review přebíjí starší verdikt")
    func requestBeatsAnOlderVerdict() {
        let reviewers = Policy.reviewers(
            requested: ["odinuv"],
            verdicts: [.init(login: "odinuv", state: .changesRequested)]
        )

        #expect(reviewers == [RequestedReviewer(login: "odinuv", answer: .waiting)])
    }

    /// Jeden člověk **jednou**, i když je v obou polích. Duplikát by v panelu vypadal jako dva lidé
    /// se stejným jménem.
    @Test("Reviewer se nekreslí dvakrát")
    func doesNotDuplicate() {
        let reviewers = Policy.reviewers(
            requested: ["odinuv", "odinuv"],
            verdicts: [.init(login: "odinuv", state: .approved)]
        )

        #expect(reviewers.count == 1)
    }

    /// Pořadí je **podle odpovědi**, ne podle toho, co přišlo první: GitHub pořadí `latestReviews`
    /// nezaručuje, takže bez toho by se seznam přeskládal při každém načtení.
    @Test("Řadí se schválil, chce změny, čeká — a při shodě podle loginu")
    func sortsByAnswerThenLogin() {
        let reviewers = Policy.reviewers(
            requested: ["zdena", "adam"],
            verdicts: [
                .init(login: "petra", state: .changesRequested),
                .init(login: "bara", state: .approved),
                .init(login: "cyril", state: .approved),
            ]
        )

        #expect(reviewers.map(\.login) == ["bara", "cyril", "petra", "adam", "zdena"])
        #expect(reviewers.map(\.answer) == [.approved, .approved, .changesRequested, .waiting, .waiting])
    }

    /// **Prázdný login se do sekce nedostane.** Autora review může GitHub vynechat (smazaný účet)
    /// a řádek bez jména se v panelu nedá odlišit od chyby kresby — a hlavně se nedá vyžádat.
    @Test("Prázdný login se zahodí z obou polí")
    func dropsEmptyLogins() {
        let reviewers = Policy.reviewers(
            requested: ["", "odinuv"],
            verdicts: [.init(login: "", state: .approved)]
        )

        #expect(reviewers == [RequestedReviewer(login: "odinuv", answer: .waiting)])
    }

    @Test("PR bez reviewerů dá prázdný seznam")
    func emptyIsEmpty() {
        #expect(Policy.reviewers(requested: [], verdicts: []).isEmpty)
    }

    // MARK: - Po vyžádání (#392)

    /// Po vyžádání review dá GitHub **jen** to, na koho se čeká — odpovědi ostatních v odpovědi
    /// nejsou. Musí zůstat, jinak by z panelu po jednom kliknutí zmizelo schválení, které tam bylo.
    @Test("Vyžádání nesmaže odpovědi ostatních")
    func keepsAnswersAfterARequest() {
        let known = [
            RequestedReviewer(login: "babakks", answer: .approved),
            RequestedReviewer(login: "petra", answer: .changesRequested),
            RequestedReviewer(login: "sergiou87", answer: .waiting),
        ]

        let merged = Policy.reviewers(requested: ["sergiou87", "odinuv"], keeping: known)

        #expect(merged == [
            RequestedReviewer(login: "babakks", answer: .approved),
            RequestedReviewer(login: "petra", answer: .changesRequested),
            RequestedReviewer(login: "odinuv", answer: .waiting),
            RequestedReviewer(login: "sergiou87", answer: .waiting),
        ])
    }

    /// **Kdo v odpovědi není a čekal, přestane čekat.** `waiting` není verdikt, takže se nepřenáší —
    /// jinak by v seznamu zůstal někdo, koho GitHub mezi vyžádanými nevyjmenoval.
    @Test("Čekající, kterého GitHub nevyjmenoval, ze seznamu vypadne")
    func dropsWaitingReviewersTheAnswerOmits() {
        let known = [RequestedReviewer(login: "sergiou87", answer: .waiting)]

        #expect(Policy.reviewers(requested: ["odinuv"], keeping: known)
            == [RequestedReviewer(login: "odinuv", answer: .waiting)])
    }

    /// Vyžádání od člověka, který **už schválil** (typicky po opravě): přepne se na `čeká`, ne že
    /// by tam zůstalo obojí.
    @Test("Vyžádání po schválení přepne odpověď na čeká")
    func requestAfterApprovalWaitsAgain() {
        let known = [RequestedReviewer(login: "babakks", answer: .approved)]

        #expect(Policy.reviewers(requested: ["babakks"], keeping: known)
            == [RequestedReviewer(login: "babakks", answer: .waiting)])
    }
}
