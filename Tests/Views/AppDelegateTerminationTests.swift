import AppKit
import Testing

@testable import PRism

/// Co delegát udělá se zavřením aplikace (#94 dotaz, #264 zabití session).
///
/// Dotaz i odpověď systému jsou v delegátovi **vlastnosti**, ne přímá volání AppKitu, a právě
/// proto se to dá testovat: `NSAlert.runModal()` by čekal na kliknutí, které v testu nikdo
/// neudělá, a `reply(toApplicationShouldTerminate:)` mimo odložené ukončení by hosta testů
/// ukončil doopravdy.
@Suite("AppDelegate — zavření aplikace")
@MainActor
struct AppDelegateTerminationTests {
    /// Delegát, který se nikoho nedoptává a nikam neodpovídá.
    private func delegate(
        running: Int,
        answer: Bool = true,
        stopped: Recorder = Recorder(),
        allowed: Recorder = Recorder()
    ) -> AppDelegate {
        let delegate = AppDelegate()
        delegate.runningReviews = { running }
        delegate.confirmQuit = { _ in answer }
        delegate.stopReviews = { stopped.record() }
        delegate.allowTermination = { allowed.record() }
        return delegate
    }

    @Test("Bez běžícího review se aplikace zavře hned a nikdo se neptá")
    func nothingRunningQuitsRightAway() {
        let asked = Recorder()
        let stopped = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 0 }
        delegate.confirmQuit = { _ in
            asked.record()
            return true
        }
        delegate.stopReviews = { stopped.record() }
        delegate.allowTermination = {}

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        // Dialog za nic a zabíjení, když neběží nic, jsou obojí zdržení bez důvodu.
        #expect(asked.count == 0)
        #expect(stopped.count == 0)
    }

    @Test("Zpět v dialogu nechá aplikaci běžet a nic nezabije")
    func goingBackKillsNothing() {
        let stopped = Recorder()
        let delegate = delegate(running: 2, answer: false, stopped: stopped)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        // Tohle je to podstatné tvrzení: kdo se zavření rozmyslel, nesmí přijít o session.
        #expect(stopped.count == 0)
    }

    @Test("Ukončení se odloží, dokud běžící session nejsou zabité")
    func quittingWaitsForTheSessionsToDie() async {
        let stopped = Recorder()
        let allowed = Recorder()
        let delegate = delegate(running: 1, stopped: stopped, allowed: allowed)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        // Aplikace se nesmí zavřít dřív, než zabíjení proběhne — jinak `claude` osiří
        // a poběží dál pod `launchd` (#264).
        #expect(allowed.count == 0)

        for _ in 0..<100_000 where allowed.count == 0 { await Task.yield() }
        #expect(stopped.count == 1)
        #expect(allowed.count == 1)
    }

    @Test("Druhý pokus o ukončení se nezeptá ani neodpoví dvakrát")
    func asecondAttemptChangesNothing() async {
        let asked = Recorder()
        let stopped = Recorder()
        let allowed = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 1 }
        delegate.confirmQuit = { _ in
            asked.record()
            return true
        }
        delegate.stopReviews = { stopped.record() }
        delegate.allowTermination = { allowed.record() }

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        // ⌘Q podruhé, dokud se zabíjí. Druhý dialog nad ukončením, které už běží, by byl
        // klikačka a druhá odpověď systému je na jedno odložené ukončení navíc.
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

        for _ in 0..<100_000 where allowed.count == 0 { await Task.yield() }
        #expect(asked.count == 1)
        #expect(stopped.count == 1)
        #expect(allowed.count == 1)
    }

    @Test("Odpověď systému dorazí i tehdy, když zabíjení nikdo nedoplnil")
    func terminationIsAlwaysAllowedInTheEnd() async {
        // Ze zaseknuté nebo nezapojené cesty nesmí vzniknout aplikace, která se nedá zavřít.
        let allowed = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 1 }
        delegate.confirmQuit = { _ in true }
        delegate.allowTermination = { allowed.record() }

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        for _ in 0..<100_000 where allowed.count == 0 { await Task.yield() }
        #expect(allowed.count == 1)
    }
}

/// Počítadlo volání. Třída, ne `inout`: uzávěry v delegátovi si ji drží.
@MainActor
private final class Recorder {
    private(set) var count = 0

    func record() { count += 1 }
}
