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

    /// **Snímek záložek odchází z každého ukončení**, ne jen z toho, kde na něco běží (#527) —
    /// a je to jediné místo, ze kterého se dá zachytit scroll, kterým člověk v diffu skončil.
    /// Ukládá se **před** dotazem, takže o něj nepřijde ani ten, kdo se zavření rozmyslí: `Zpět`
    /// je legitimní odpověď a snímek popisuje tentýž stav, jaký zapíše příští změna záložky.
    @Test("Snímek záložek se uloží při každém ukončení, i po Zpět v dialogu", arguments: [0, 2])
    func theTabSnapshotIsAlwaysSaved(running: Int) {
        let saved = Recorder()
        let delegate = delegate(running: running, answer: false)
        delegate.saveOpenTabs = { saved.record() }

        _ = delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(saved.count == 1)
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

        await waitUntil("systém dostane odpověď") { allowed.count > 0 }
        #expect(stopped.count == 1)
        #expect(allowed.count == 1)
    }

    @Test("Druhý pokus o ukončení se nezeptá ani neodpoví dvakrát")
    func aSecondAttemptChangesNothing() async {
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

        await waitUntil("systém dostane odpověď") { allowed.count > 0 }
        #expect(asked.count == 1)
        #expect(stopped.count == 1)
        #expect(allowed.count == 1)
    }

    /// Shell v zásuvce (#459) je tentýž závazek jako běžící review: co aplikace spustila, to i
    /// ukončí. Bez dotazu by se dal `claude --resume` v terminálu zabít omylem jedním `⌘Q`.
    @Test("Na běžící shell v zásuvce se aplikace zeptá")
    func aRunningShellIsAlsoWorthAsking() {
        let asked = Recorder()
        let killed = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 0 }
        delegate.runningTerminals = { 1 }
        delegate.confirmQuit = { _ in
            asked.record()
            return true
        }
        delegate.stopTerminals = { killed.record() }
        delegate.allowTermination = {}

        // Nic se neodkládá: signál shellu odchází přímo z téhle cesty, takže není na co čekat.
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(asked.count == 1)
        #expect(killed.count == 1)
    }

    /// **Tvrzení o tom, co se nestane**: kdo se zavření rozmyslel, nesmí přijít o rozdělaný shell.
    @Test("Zpět v dialogu shell nezabije")
    func goingBackKeepsTheShellAlive() {
        let killed = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 0 }
        delegate.runningTerminals = { 1 }
        delegate.confirmQuit = { _ in false }
        delegate.stopTerminals = { killed.record() }
        delegate.allowTermination = {}

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(killed.count == 0)
    }

    /// Když běží obojí, zabijí se shelly hned a na review se počká — jsou to dvě různé cesty,
    /// protože shell se zabíjí signálem odsud, kdežto review přes zrušení tasku (#264).
    @Test("Když běží review i shell, zabije se obojí")
    func bothKindsOfWorkAreStopped() async {
        let killed = Recorder()
        let stopped = Recorder()
        let allowed = Recorder()
        let delegate = AppDelegate()
        delegate.runningReviews = { 1 }
        delegate.runningTerminals = { 2 }
        delegate.confirmQuit = { _ in true }
        delegate.stopTerminals = { killed.record() }
        delegate.stopReviews = { stopped.record() }
        delegate.allowTermination = { allowed.record() }

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(killed.count == 1)

        await waitUntil("systém dostane odpověď") { allowed.count > 0 }
        #expect(stopped.count == 1)
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
        await waitUntil("systém dostane odpověď") { allowed.count > 0 }
        #expect(allowed.count == 1)
    }
}

/// Počítadlo volání. Třída, ne `inout`: uzávěry v delegátovi si ji drží.
@MainActor
private final class Recorder {
    private(set) var count = 0

    func record() { count += 1 }
}
