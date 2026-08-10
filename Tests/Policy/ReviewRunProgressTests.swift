import Foundation
import Testing

@testable import PRism

/// Průběh běžícího review do pruhu v hlavičce (#218).
@Suite("Průběh běhu do hlavičky")
struct ReviewRunProgressTests {
    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    /// Nejcennější tvrzení tady: **nad neběžícím PR se pruh nekreslí**. `reviewPhases` si po
    /// skončení běhu drží i `failed`, takže kdyby rozhodovala fáze, visel by proužek nad
    /// review, které dávno neběží.
    @Test("Bez běhu není průběh")
    func nothingWithoutARun() {
        #expect(Policy.progress(startedAt: nil, phase: nil, running: []) == nil)
        #expect(Policy.progress(startedAt: nil, phase: .running(finished: 1, total: 3), running: ["a"]) == nil)
        #expect(Policy.progress(startedAt: nil, phase: .failed(detail: "spadlo"), running: []) == nil)
    }

    @Test("Rozjetý běh nese počty i jména běžících")
    func carriesCountsAndNames() {
        let progress = Policy.progress(
            startedAt: started,
            phase: .running(finished: 2, total: 3),
            running: ["test-coverage"]
        )

        #expect(progress?.stage == .running(finished: 2, total: 3))
        #expect(progress?.running == ["test-coverage"])
        #expect(progress?.startedAt == started)
        #expect(progress?.fraction == 2.0 / 3.0)
    }

    /// Jména se řadí, aby pruh nepřeskládával pořadí při každém překreslení — `Set` ho nemá.
    @Test("Běžící reviewery jsou v abecedním pořadí")
    func sortsRunningReviewers() {
        let progress = Policy.progress(
            startedAt: started,
            phase: .running(finished: 0, total: 3),
            running: ["php-review", "docs", "security"]
        )

        #expect(progress?.running == ["docs", "php-review", "security"])
    }

    /// Příprava pracovní kopie je běh, jen se z něj nedá počítat podíl — a nula by tvrdila
    /// „hotovo nic“, což je jiné tvrzení než „ještě nevím kolik“.
    @Test("Během přípravy se podíl nedá spočítat")
    func hasNoFractionWhilePreparing() {
        let progress = Policy.progress(startedAt: started, phase: .preparing, running: [])

        #expect(progress?.stage == .preparing)
        #expect(progress?.fraction == nil)
    }

    /// `failed` s běžícím tasekm nastane mezi pádem plánovače a úklidem. Fáze se na `preparing`
    /// **schválně** srovnává: pruh nesmí tvrdit počty, které nemá odkud vzít.
    @Test("Fáze, ze které se nedá počítat, se bere jako příprava")
    func treatsAnythingElseAsPreparing() {
        #expect(Policy.progress(startedAt: started, phase: .failed(detail: "x"), running: [])?.stage == .preparing)
        #expect(Policy.progress(startedAt: started, phase: nil, running: [])?.stage == .preparing)
    }

    /// Nulový součet by dělil nulou. Nastane u repa s prázdnou sadou skillů.
    @Test("Nulový součet nedá podíl")
    func survivesAZeroTotal() {
        let progress = Policy.progress(
            startedAt: started,
            phase: .running(finished: 0, total: 0),
            running: []
        )

        #expect(progress?.fraction == nil)
    }

    /// `finished > total` by natáhlo proužek za dráhu. Nemá nastat, ale ořezat se to musí
    /// tady, ne kreslením.
    @Test("Podíl se nepřeteče přes jedničku")
    func clampsTheFraction() {
        let progress = Policy.progress(
            startedAt: started,
            phase: .running(finished: 5, total: 3),
            running: []
        )

        #expect(progress?.fraction == 1)
    }
}
