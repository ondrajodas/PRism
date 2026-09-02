import Foundation
import Testing

@testable import PRism

/// Značka u záložky v pruhu (#527) — pět pater, vyčerpávající výčet.
///
/// Nejcennější jsou tvrzení o **pořadí**: každé z nich se rozbije potichu, protože v okně je
/// vidět jen jedna značka a ta špatná vypadá stejně platně jako ta správná.
@Suite("Policy — značka záložky (#527)")
struct WindowTabMarkTests {
    /// Volání se všemi vstupy vypnutými, ať se v každém testu mění jen to jedno.
    private func mark(
        isRunning: Bool = false,
        isLoading: Bool = false,
        hasDraft: Bool = false,
        state: PullRequestState? = .open,
        review: ReviewState = .notStarted
    ) -> WindowTabMark {
        Policy.tabMark(
            isRunning: isRunning,
            isLoading: isLoading,
            hasDraft: hasDraft,
            state: state,
            review: review
        )
    }

    @Test("Bez ničeho zvláštního se kreslí stav review")
    func theReviewStateIsTheDefault() {
        #expect(mark(review: .clean) == .review(.clean))
        #expect(mark(review: .completed(findings: 3)) == .review(.completed(findings: 3)))
        #expect(mark(review: .notStarted) == .review(.notStarted))
    }

    /// Z #180 a platí dál: běh je jediný stav, který se mění sám, a prstýnek je jediná věc
    /// v pruhu, ze které je vidět, že aplikace pracuje, aniž by se na tu záložku přepnulo.
    @Test("Běh přebíjí všechno ostatní")
    func runningWinsOverEverything() {
        #expect(mark(isRunning: true, isLoading: true, hasDraft: true, state: .merged) == .running)
        #expect(mark(isRunning: true, review: .completed(findings: 9)) == .running)
    }

    /// **Tohle je ta věta, na které #527 stojí.** Bez ní by obnovená záložka chvíli kreslila
    /// puntík stavu review z minula — tedy tvrzení o kódu, o kterém aplikace ještě nic neví.
    @Test("Načítání přebíjí rozdělané review i stav PR")
    func loadingWinsOverDraftAndState() {
        #expect(mark(isLoading: true, hasDraft: true, state: .merged) == .loading)
        #expect(mark(isLoading: true, review: .clean) == .loading)
        // A **nepřebíjí běh**: po startu neběží nic (obnovení nespouští nic), takže je to pořadí
        // bez sporu — ale kdyby si někdo review na obnovené záložce pustil ručně dřív, než detail
        // dorazí, má vyhrát prstýnek.
        #expect(mark(isRunning: true, isLoading: true) == .running)
    }

    @Test("Rozdělané review přebíjí stav review i mergnutý PR")
    func draftWinsOverState() {
        #expect(mark(hasDraft: true, review: .clean) == .draft)
        // Nedopsaná věta je práce, která čeká na mě — a ta nezmizí tím, že se PR mergnul.
        #expect(mark(hasDraft: true, state: .merged) == .draft)
    }

    /// **Jen `merged` a `closed`.** U nich se od nálezů nic neodvíjí (dá se to jedině dočíst
    /// a zavřít), takže „jak to dopadlo“ přebíjí „co našel reviewer“. `open` a `draft` jsou
    /// normální práce a stav review na nich platí dál.
    @Test("Stav pull requestu přebíjí review jedině u mergnutého a zavřeného")
    func onlyFinishedPullRequestsWin() {
        #expect(mark(state: .merged, review: .clean) == .pullRequest(.merged))
        #expect(mark(state: .closed, review: .completed(findings: 2)) == .pullRequest(.closed))
        #expect(mark(state: .open, review: .clean) == .review(.clean))
        #expect(mark(state: .draft, review: .clean) == .review(.clean))
    }

    /// Neznámý stav PR je stav obnovené záložky **po** tom, co se `loading` zhasne jen proto, že
    /// dorazil snímek z pollingu — a „nevím, jak PR dopadl“ nesmí vyjít jako `merged`.
    @Test("Neznámý stav pull requestu kreslí review, ne fialovou")
    func anUnknownStateFallsBackToReview() {
        #expect(mark(state: nil, review: .clean) == .review(.clean))
        #expect(mark(state: nil, review: .notStarted) == .review(.notStarted))
    }

    /// Vyčerpání shora: pro každou kombinaci vstupů je odpověď jedna a je určená pořadím pater.
    @Test("Pořadí pater je úplné — pro každou kombinaci vyjde právě jedna značka")
    func theLadderIsExhaustive() {
        for running in [true, false] {
            for loading in [true, false] {
                for draft in [true, false] {
                    for state in [PullRequestState.open, .draft, .merged, .closed] {
                        let expected: WindowTabMark = if running {
                            .running
                        } else if loading {
                            .loading
                        } else if draft {
                            .draft
                        } else if state == .merged || state == .closed {
                            .pullRequest(state)
                        } else {
                            .review(.clean)
                        }
                        #expect(
                            mark(
                                isRunning: running,
                                isLoading: loading,
                                hasDraft: draft,
                                state: state,
                                review: .clean
                            ) == expected
                        )
                    }
                }
            }
        }
    }
}
