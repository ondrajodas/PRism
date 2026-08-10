import Foundation
import Testing

@testable import PRism

/// Co se píše v pravém horním koutu dashboardu (#237) — čistá funkce nad třemi hodnotami, takže
/// se dá vyčerpat výčtem bez kreslení.
@Suite("Odpočet příštího tiku")
struct DashboardTickTests {
    private let last = Date(timeIntervalSince1970: 1_000_000)
    private var now: Date { last.addingTimeInterval(17) }

    private func tick(lastSuccess: Date?, nextPoll: Date?, isRefreshing: Bool = false) -> DashboardTick {
        DashboardTick(
            lastSuccess: lastSuccess,
            nextPoll: nextPoll,
            isRefreshing: isRefreshing,
            now: now
        )
    }

    // MARK: - Odpočet

    /// Nese **termín**, ne spočítané vteřiny: odpočet si je ve view odtiká sám a přepočítat je
    /// tady by znamenalo přepočítávat celý dashboard každou vteřinu.
    @Test("Příští tik v budoucnosti je odpočet k termínu")
    func futureNextPollCountsDown() {
        let deadline = now.addingTimeInterval(43)

        #expect(tick(lastSuccess: last, nextPoll: deadline) == .countdown(last: last, deadline: deadline))
    }

    // MARK: - Nula a to, co je za ní

    /// **Tohle je ten případ, který se rozbije potichu.** `nextPoll` zůstává v minulosti po
    /// celou dobu dotazu, protože ho smyčka zapisuje až po `refresh()` — takže odpočet dojde na
    /// nulu a šel by dál. `-3 s` na tom místě nemá co dělat, a `Text(_:style: .relative)` by
    /// nad uplynulým termínem začal počítat nahoru, což je totéž tvrzení naruby.
    @Test("Uplynulý termín se neukáže jako odpočet")
    func pastNextPollNeverCountsDown() {
        let tick = tick(lastSuccess: last, nextPoll: now.addingTimeInterval(-3))

        #expect(tick == .polling(last: last))
        if case .countdown = tick { Issue.record("Odpočet přes nulu.") }
    }

    /// Rovnost patří k uplynulým: v nule už dotaz běží, takže nula na displeji by byla vteřina
    /// zpoždění navíc.
    @Test("Termín právě teď je taky dotaz, ne nula na displeji")
    func nextPollExactlyNowIsPolling() {
        #expect(tick(lastSuccess: last, nextPoll: now) == .polling(last: last))
    }

    /// Po probuzení stroje je termín dávno za námi (smyčka nabíhá se zpožděním) — a to je ta
    /// situace, ve které by z „za 43 s“ bylo „za 8 hodin“ počítaných nahoru.
    @Test("Termín dávno za námi taky neodpočítává")
    func longPastNextPollIsPolling() {
        #expect(tick(lastSuccess: last, nextPoll: now.addingTimeInterval(-28_800)) == .polling(last: last))
    }

    // MARK: - Probíhající dotaz

    /// Příznak přebíjí i termín v budoucnosti: ruční obnovení `nextPoll` neposouvá, takže by se
    /// vedle běžícího dotazu odpočítávalo k tiku, na který se nečeká.
    @Test("Probíhající dotaz přebije odpočet")
    func refreshingBeatsTheCountdown() {
        let tick = tick(lastSuccess: last, nextPoll: now.addingTimeInterval(43), isRefreshing: true)

        #expect(tick == .polling(last: last))
    }

    /// První dotaz po startu — poslední tik ještě není, ale „ptám se…“ platí.
    @Test("První dotaz po startu je dotaz bez posledního tiku")
    func refreshingWithoutHistory() {
        #expect(tick(lastSuccess: nil, nextPoll: nil, isRefreshing: true) == .polling(last: nil))
    }

    // MARK: - Nenačteno a nenaplánováno

    @Test("Dokud se nic nenačetlo, není co odpočítávat")
    func withoutSuccessThereIsNothing() {
        #expect(tick(lastSuccess: nil, nextPoll: nil) == .never)
    }

    /// Nenaplánovaný tik po úspěchu je jen chvilka, než smyčka usne — ale „za 0 s znovu“ by
    /// o příštím tiku tvrdilo něco, co se ještě nerozhodlo.
    @Test("Bez naplánovaného tiku zůstane jen poslední tik")
    func withoutScheduleOnlyTheLastTick() {
        #expect(tick(lastSuccess: last, nextPoll: nil) == .idle(last: last))
    }
}
