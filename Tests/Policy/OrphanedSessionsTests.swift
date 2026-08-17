import Testing

@testable import PRism

/// Rozhodnutí o zapsané session při startu aplikace (#351).
///
/// Vyčerpávající výčet, protože vstup je malý a uzavřený: vlastník a proces mohou být každý ve
/// třech stavech (běží tentýž, běží někdo jiný pod tím PID, neběží nikdo), tedy devět kombinací.
/// Osm z nich je **negativní** — nesmí z nich vyjít signál —, a to je ta polovina, která se
/// rozbije potichu: zabít cizí `claude` je horší než nechat běžet sirotka.
@Suite("Úklid osiřelých session")
struct OrphanedSessionsTests {
    private let owner = ProcessIdentity(pid: 100, startedAt: 1_000)
    private let process = ProcessIdentity(pid: 200, startedAt: 2_000)

    /// Tentýž PID, ale jiný proces — takhle vypadá recyklované číslo.
    private func recycled(_ identity: ProcessIdentity) -> ProcessIdentity {
        ProcessIdentity(pid: identity.pid, startedAt: identity.startedAt + 1)
    }

    private var session: RunningSession { RunningSession(owner: owner, process: process) }

    private func verdict(
        ownerNow: ProcessIdentity?,
        processNow: ProcessIdentity?
    ) -> OrphanVerdict {
        Policy.orphanVerdict(for: session, ownerNow: ownerNow, processNow: processNow)
    }

    @Test("Vlastník je pryč a proces pořád běží — jediný případ, kdy se zabíjí")
    func killsWhenTheOwnerIsGoneAndTheProcessIsOurs() {
        #expect(verdict(ownerNow: nil, processNow: process) == .kill)
    }

    @Test("Vlastníkovo PID mezitím dostal někdo jiný — vlastník je tedy pryč a zabíjí se")
    func killsWhenTheOwnersPIDWasRecycled() {
        // Recyklované PID vlastníka není živý vlastník: identita se neshoduje, takže se ta
        // session počítá jako osiřelá. Bez téhle větve by sirotka udržel naživu cizí proces,
        // který zrovna dostal číslo po mrtvé aplikaci.
        #expect(verdict(ownerNow: recycled(owner), processNow: process) == .kill)
    }

    @Test("Živý vlastník znamená, že to není náš úklid — ať je proces v jakémkoli stavu")
    func keepsEverythingOfALivingOwner() {
        // Tohle je ta věta, kvůli které je v záznamu vlastník: `xcodebuild test` spouští
        // testovacího hosta, který má stejné `CFBundleName`, tedy **tutéž cache** jako aplikace
        // v `/Applications`. Bez kontroly vlastníka by běh testů zabil review, které zrovna běží.
        #expect(verdict(ownerNow: owner, processNow: process) == .keep)
        #expect(verdict(ownerNow: owner, processNow: nil) == .keep)
        #expect(verdict(ownerNow: owner, processNow: recycled(process)) == .keep)
    }

    @Test("Recyklované PID procesu se nezabíjí, jen se zahodí značka")
    func discardsWhenTheProcessPIDWasRecycled() {
        // Nejcennější tvrzení celého #351. Pod zapsaným PID běží někdo jiný — na stroji běží
        // `claude` i mimo aplikaci (uživatelovy vlastní session, paralelní agenti) — a signál
        // tam nesmí odejít.
        #expect(verdict(ownerNow: nil, processNow: recycled(process)) == .discard)
        #expect(verdict(ownerNow: recycled(owner), processNow: recycled(process)) == .discard)
    }

    @Test("Doběhlý proces se jen zapomene")
    func discardsWhenTheProcessIsGone() {
        #expect(verdict(ownerNow: nil, processNow: nil) == .discard)
        #expect(verdict(ownerNow: recycled(owner), processNow: nil) == .discard)
    }
}
