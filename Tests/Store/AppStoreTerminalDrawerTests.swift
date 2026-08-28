import AppKit
import Foundation
import Testing

@testable import PRism

/// Zásuvka s terminálem ve storu (#459).
///
/// Nejcennější jsou tady dvě tvrzení o tom, co se **ne**stane: schování zásuvky shell nezabije
/// (jinak by `⌃\`` uprostřed běžícího `claude --resume` byl nevratný omyl) a zavření záložky ho
/// zabije (jinak by běžel dál bez okna, ve kterém by šel vidět — tedy sirotek z #264 a #351).
@Suite("AppStore — zásuvka s terminálem (#459)")
@MainActor
struct AppStoreTerminalDrawerTests {
    private let pullRequest = PRIdentifier("cli/cli#42")!
    private var shell: TerminalSlot { TerminalSlot(pullRequest: pullRequest, role: .shell) }

    private func store(_ host: FakeTerminalHost) -> AppStore {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource(),
            terminals: host
        )
        store.openTabs = [pullRequest]
        store.activeTab = .pullRequest(pullRequest)
        return store
    }

    // MARK: - Vytažení a schování

    @Test("⌃` zásuvku vytáhne a schová")
    func togglingOpensAndCloses() async {
        let store = store(FakeTerminalHost())

        #expect(!store.isTerminalOpen)
        await store.toggleTerminal()
        #expect(store.isTerminalOpen)
        await store.toggleTerminal()
        #expect(!store.isTerminalOpen)
    }

    /// **Schování nic nezabíjí.** Je to tentýž vztah jako mezi sbaleným panelem nálezů a nálezy:
    /// zásuvka je pohled, shell je proces.
    @Test("Schování zásuvky shell nezabije")
    func hidingTheDrawerKillsNothing() async {
        let host = FakeTerminalHost()
        let store = store(host)

        await store.toggleTerminal()
        await store.toggleTerminal()

        #expect(host.stopped.isEmpty)
        #expect(host.stoppedPullRequests.isEmpty)
        #expect(host.stoppedAll == 0)
    }

    /// Fokus musí spadnout se zásuvkou — příznak, který zůstane viset, znamená okno s vypnutými
    /// zkratkami nad terminálem, který není vidět.
    @Test("Schovaná zásuvka fokus nedrží")
    func hidingTheDrawerDropsFocus() async {
        let host = FakeTerminalHost()
        let store = store(host)

        await store.toggleTerminal()
        host.focusChanged?(true)
        #expect(store.isTerminalFocused)

        await store.toggleTerminal()
        #expect(!store.isTerminalFocused)
    }

    // MARK: - Konec kontextu

    /// Zavřená záložka je jediné místo, kde kontext PR doopravdy končí.
    @Test("Zavření záložky zabije všechny relace toho PR")
    func closingTheTabKillsEveryShell() {
        let host = FakeTerminalHost()
        let store = store(host)
        let lane = TerminalSlot(pullRequest: pullRequest, role: .session("php-review"))
        store.terminalSlots[pullRequest] = [shell, lane]
        store.activeTerminalSlots[pullRequest] = lane
        store.terminalStates[shell] = .running
        store.terminalStates[lane] = .running

        store.closeTab(pullRequest)

        // **Přes pull request, ne přes aktivní relaci** (#460): kdyby se zabíjela jen ta, která
        // je vidět, osiřela by zrovna ta, na kterou se člověk zrovna nedíval.
        #expect(host.stoppedPullRequests == [pullRequest])
        #expect(store.terminalStates[shell] == nil)
        #expect(store.terminalStates[lane] == nil)
        #expect(store.terminalSlots[pullRequest] == nil)
        #expect(store.activeTerminalSlots[pullRequest] == nil)
    }

    /// Ukončení aplikace (#264): co aplikace spustila, to i ukončí.
    @Test("Ukončení aplikace zabije všechny shelly")
    func terminationKillsEveryShell() {
        let host = FakeTerminalHost()
        let store = store(host)

        store.stopTerminalsBeforeTermination()

        #expect(host.stoppedAll == 1)
    }

    @Test("Počet běžících shellů se čte z hostitele")
    func theRunningCountComesFromTheHost() {
        let host = FakeTerminalHost()
        host.running = 2

        #expect(store(host).runningTerminals == 2)
    }

    /// Bez hostitele se zásuvka nekreslí a nic se nepočítá — tak jsou na tom testy, které o terminál
    /// nestojí, i každé volání, které by jinak muselo řešit `nil`.
    @Test("Bez hostitele se nic nepočítá a nic nepadá")
    func noHostMeansNoTerminals() {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())

        #expect(store.runningTerminals == 0)
        store.stopTerminal(for: pullRequest)
        store.stopTerminalsBeforeTermination()
    }

    // MARK: - Kde shell startuje

    /// Klon v cache stačí — `git log` i `gh pr view` v něm fungují a je to pořád víc než zásuvka,
    /// která se nemá kde otevřít.
    @Test("Bez pracovního stromu se startuje v klonu")
    func theCloneIsUsedWhenThereIsNoWorktree() async throws {
        let clone = FileManager.default.temporaryDirectory
            .appending(path: "prism-terminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clone) }

        let store = store(FakeTerminalHost())
        store.checkoutStates[pullRequest.repo] = .ready(clone)

        await store.prepareTerminalDrawer(for: pullRequest)

        #expect(store.terminalDirectory(of: shell) == clone)
    }

    /// **Tvrzení o tom, co se nestane**: cesta, která na disku není, se nesmí nabídnout. Shell
    /// spuštěný ve smazané složce je horší než zásuvka, která řekne, že není kde začít — eviction
    /// klony maže, takže tenhle stav není teoretický.
    @Test("Smazaný klon se nenabídne")
    func aVanishedCloneIsNotOffered() async {
        let store = store(FakeTerminalHost())
        store.checkoutStates[pullRequest.repo] = .ready(
            URL(filePath: "/tmp/prism-terminal-\(UUID().uuidString)")
        )

        await store.prepareTerminalDrawer(for: pullRequest)

        #expect(store.terminalDirectory(of: shell) == nil)
    }
}

/// Hostitel terminálů, který nespouští žádný shell — jen si pamatuje, co po něm kdo chtěl.
///
/// Obyčejná třída, ne mockovací framework, jako všechny fake implementace v tomhle repu.
@MainActor
final class FakeTerminalHost: TerminalHosting {
    var running = 0

    /// Jak dopadne příští `run(_:for:in:)` (#460). Rozhodnutí, jestli je v relaci obsazené popředí,
    /// dělá živý hostitel z jádra (`tcgetpgrp`), takže se sem v testu podstrčí hotový výsledek.
    var outcome: TerminalCommandOutcome = .started

    private(set) var stopped: [TerminalSlot] = []
    private(set) var stoppedPullRequests: [PRIdentifier] = []
    private(set) var stoppedAll = 0
    private(set) var handed: [TerminalSlot: URL] = [:]

    /// Co po sobě `▶` nechalo: řádka, relace a adresář.
    private(set) var ran: [(line: String, slot: TerminalSlot, directory: URL)] = []

    var report: (@MainActor (TerminalSlot, TerminalRunState) -> Void)?
    var focusChanged: (@MainActor (Bool) -> Void)?

    var runningTerminals: Int { running }

    func terminal(for slot: TerminalSlot, in directory: URL) -> NSView {
        handed[slot] = directory
        return NSView()
    }

    @discardableResult
    func run(
        _ commandLine: String,
        for slot: TerminalSlot,
        in directory: URL
    ) -> TerminalCommandOutcome {
        ran.append((commandLine, slot, directory))
        return outcome
    }

    @discardableResult
    func stopTerminal(for slot: TerminalSlot) -> Bool {
        stopped.append(slot)
        return true
    }

    @discardableResult
    func stopTerminals(for pr: PRIdentifier) -> Bool {
        stoppedPullRequests.append(pr)
        return true
    }

    func stopAllTerminals() { stoppedAll += 1 }
}
