import Foundation
import Testing

@testable import PRism

/// Ruční obnovení, dokud běží to předchozí (#442).
///
/// **Je to tvrzení o tom, co se NEstalo**, tedy ten druh, který se rozbije potichu: druhý dotaz
/// navíc nic nerozbije viditelně — jen se GitHubu zbytečně dvakrát zaplatí a `isRefreshing` visí
/// o kolo dýl, než se aplikace doopravdy ptá. Zašedlé tlačítko proti tomu nestačí: tutéž akci
/// nabízí paleta ⌘K, prázdný stav seznamu (`Zkusit znovu`) a #441 k tomu přidá zkratku `⌘R`.
///
/// **Tady se to dá ověřit, ve view ne** — accessibility tree se v okně mimo obrazovku nenaplní,
/// takže na `AXEnabled` hostovaného tlačítka není kde se zeptat. Zkouší se proto ten konec, kde
/// druhý klik doopravdy něco stojí.
@Suite("Obnovení během obnovení (#442)")
@MainActor
struct AppStoreRefreshTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, configuration: configuration, time: FakeTimeSource())
    }

    /// Druhé obnovení se pouští **zevnitř** prvního (`duringSearch`), protože jindy stav „právě se
    /// ptáme“ neexistuje — `isRefreshing` je pravdivé jen po tu dobu, kdy dotaz běží.
    ///
    /// **Hook se pustí jen jednou, a je to podmínka, ne úklid.** Ověřeno vložením regrese: bez
    /// guardu v `AppStore.refresh()` by se druhé obnovení zeptalo znovu, spustilo hook znovu —
    /// a test by místo červené **zatuhl donekonečna**. Test, který nad regresí visí, je horší než
    /// žádný: nedá se z něj poznat, jestli je rozbitá aplikace, nebo harness. S pojistkou spadne
    /// na tom, na čem má: gateway dostane dva dotazy místo jednoho.
    @Test("Druhé obnovení se během prvního nepustí")
    func doesNotAskTwiceWhileTheFirstQueryRuns() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        let store = store(gateway)
        let once = OneShot()
        // `weak`, aby si fake a store nedržely navzájem — cyklus by test nepoložil, ale nechal
        // by po sobě živý `AppStore` s běžícími tasky.
        gateway.duringSearch = { [weak store] in
            guard once.claim(), let store else { return }
            await store.refresh()
        }

        await store.refresh()

        #expect(gateway.queries == sources.map(\.query))
    }

    /// **A příznak se nesmí zaseknout**: kdyby po odmítnutém obnovení zůstalo viset `isRefreshing`,
    /// bylo by tlačítko zakázané navždycky — tedy horší stav než ten, který se opravoval. Druhý
    /// dotaz po doběhnutí prvního proto projít **musí**.
    @Test("Po doběhnutí prvního dotazu se druhý pustí normálně")
    func asksAgainOnceTheFirstQueryFinished() async {
        let gateway = FakeGitHubGateway(always: .success([]))
        let store = store(gateway)

        await store.refresh()
        #expect(!store.isRefreshing)
        await store.refresh()

        #expect(gateway.queries.count == 2)
    }
}

/// Pustí se jednou a podruhé už ne. Zámek proto, že hook `FakeGitHubGateway`u je `@Sendable`
/// a běží mimo `MainActor`.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func claim() -> Bool {
        lock.withLock {
            defer { fired = true }
            return !fired
        }
    }
}
