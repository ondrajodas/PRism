import Foundation
import Testing

@testable import PRism

/// Druhé razítko (#335) — o čem už se hlásilo.
///
/// `VisitLedger` drží poslední **návštěvu**, tenhle poslední **oznámení**, a to jsou dvě různé věci:
/// oznámením PR nenavštívím. Bez tohohle razítka by „2 nové komentáře“ chodily při každé rozhlídce,
/// dokud PR neotevřu — a to je otrava, po které si člověk notifikace vypne.
@Suite("ActivityNoticeLedger — o čem už se hlásilo (#335)")
struct ActivityNoticeLedgerTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("PR, o kterém se nehlásilo, razítko nemá")
    func anUnannouncedPullRequestHasNoStamp() {
        let ledger = ActivityNoticeLedger(preferences: InMemoryPreferences())

        #expect(ledger.lastNotice(for: pr) == nil)
    }

    @Test("Zapsané razítko přežije restart")
    func aRecordedStampSurvivesARestart() {
        // Na disku (v předvolbách) schválně: kdyby bylo jen v paměti, po každém spuštění by přišla
        // hláška o komentářích, o kterých se už hlásilo — a `run.sh` po každém mergi je restart.
        let preferences = InMemoryPreferences()
        ActivityNoticeLedger(preferences: preferences).record(pr, announced: now, at: now)

        #expect(ActivityNoticeLedger(preferences: preferences).lastNotice(for: pr) == now)
    }

    @Test("Razítka různých PR se nepletou")
    func stampsOfDifferentPullRequestsStayApart() {
        let ledger = ActivityNoticeLedger(preferences: InMemoryPreferences())

        ledger.record(pr, announced: now, at: now)
        ledger.record(other, announced: now.addingTimeInterval(60), at: now)

        #expect(ledger.lastNotice(for: pr) == now)
        #expect(ledger.lastNotice(for: other) == now.addingTimeInterval(60))
    }

    /// **Tvrzení, že se něco nestalo**: razítko se neposouvá dozadu. Rozhlídka se ptá i na PR,
    /// o kterých se hlásilo dřív, a starší položka z toho nesmí udělat neohlášenou věc.
    @Test("Starší položka razítko neposune dozadu")
    func anOlderItemDoesNotMoveTheStampBack() {
        let ledger = ActivityNoticeLedger(preferences: InMemoryPreferences())
        ledger.record(pr, announced: now, at: now)

        ledger.record(pr, announced: now.addingTimeInterval(-600), at: now)

        #expect(ledger.lastNotice(for: pr) == now)
    }

    @Test("Zápis zahodí, co se přežilo")
    func writingCleansUpExpiredStamps() {
        // Zavřený PR se do seznamu nevrátí, takže by jeho razítko leželo v předvolbách napořád —
        // tatáž lhůta i důvod jako u návštěv (#173).
        let preferences = InMemoryPreferences()
        let ledger = ActivityNoticeLedger(preferences: preferences)
        ledger.record(other, announced: now, at: now)

        let later = now.addingTimeInterval(ActivityNoticeLedger.retention + 1)
        ledger.record(pr, announced: later, at: later)

        #expect(ledger.lastNotice(for: other) == nil)
        #expect(ledger.lastNotice(for: pr) == later)
    }

    @Test("Razítko těsně pod hranicí zůstává")
    func aStampJustUnderTheLimitStays() {
        let ledger = ActivityNoticeLedger(preferences: InMemoryPreferences())
        ledger.record(other, announced: now, at: now)

        let later = now.addingTimeInterval(ActivityNoticeLedger.retention - 1)
        ledger.record(pr, announced: later, at: later)

        #expect(ledger.lastNotice(for: other) == now)
    }

    /// Rozbitá hodnota znamená **prázdno**, ne pád — a je to bezpečný směr: nejhůř se zopakuje
    /// jedna hláška. Opačná volba (tvářit se, že se hlásilo) by ji spolkla, a to se pozná až tím,
    /// že něco nepřišlo.
    @Test("Rozbitá hodnota znamená prázdno")
    func abrokenValueMeansNothing() {
        let preferences = InMemoryPreferences(["pullRequests.lastActivityNotices": "{tohle není JSON"])

        #expect(ActivityNoticeLedger(preferences: preferences).lastNotice(for: pr) == nil)
        // A dá se přes to zapsat, takže se stav do jedné hlášky obnoví.
        ActivityNoticeLedger(preferences: preferences).record(pr, announced: now, at: now)
        #expect(ActivityNoticeLedger(preferences: preferences).lastNotice(for: pr) == now)
    }
}
