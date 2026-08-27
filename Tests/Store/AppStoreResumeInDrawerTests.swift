import Foundation
import Testing

@testable import PRism

/// `▶` v hlavičce dráhy pouští session v **zásuvce**, ne v `Terminal.app` (#460).
///
/// Nejcennější jsou tady dvě tvrzení o tom, co se **ne**stane: po `busy` se nepřepíše cesta
/// v hlavičce zásuvky (shell dál stojí tam, kde stál, takže popiska, která by tvrdila jinak, je
/// horší než stará pravda), a store bez hostitele si nevymyslí hlášku o něčem, o co se nikdo
/// nepokusil.
@Suite("AppStore — session v zásuvce (#460)")
@MainActor
struct AppStoreResumeInDrawerTests {
    private let pullRequest = PRIdentifier("cli/cli#42")!
    private let worktree = URL(filePath: "/Users/o/Library/Application Support/PRism/w/6-abc")

    private var session: TerminalSession {
        TerminalSession(directory: worktree, command: Policy.resumeCommand(sessionID: "8c1f-42"))
    }

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

    // MARK: - Co se pustí

    /// Celý slib #460: `▶` **vytáhne zásuvku** místo cizího okna a session v ní naváže.
    @Test("▶ vytáhne zásuvku a pustí v ní session")
    func theDrawerOpensAndTheSessionResumes() throws {
        let host = FakeTerminalHost()
        let store = store(host)

        store.resumeInDrawer(session, for: pullRequest)

        #expect(store.isTerminalOpen)
        let run = try #require(host.ran.first)
        #expect(host.ran.count == 1)
        #expect(run.pr == pullRequest)
        #expect(run.directory == worktree)
        #expect(store.terminalFailure == nil)
    }

    /// **Tatáž řádka, jakou od #453 dostával `Terminal.app`** — s `cd` do pracovního stromu
    /// a s uzávorkovanou cestou. `cd` není nadbytečné: zásuvka smí mít shell puštěný `` ⌃` ``
    /// nad klonem, a `claude --resume` hledá vlákno podle adresáře.
    @Test("Do zásuvky jde cd do stromu a teprve pak resume")
    func theWorktreeComesFirst() {
        let host = FakeTerminalHost()

        store(host).resumeInDrawer(session, for: pullRequest)

        #expect(
            host.ran.first?.line
                == "cd '/Users/o/Library/Application Support/PRism/w/6-abc' && claude --resume 8c1f-42"
        )
        #expect(host.ran.first?.line == session.shellLine)
    }

    /// Hlavička zásuvky ukazuje cestu, ve které shell stojí — a po `▶` je to strom té session,
    /// ať už tam shell startoval, nebo ho tam poslalo `cd`.
    @Test("Cesta v hlavičce se přepíše na strom té session")
    func theHeaderPathFollowsTheSession() {
        let host = FakeTerminalHost()
        let store = store(host)
        store.terminalDirectories[pullRequest] = URL(filePath: "/tmp/jinde")

        store.resumeInDrawer(session, for: pullRequest)

        #expect(store.terminalDirectory(for: pullRequest) == worktree)
    }

    // MARK: - Když se nic neposlalo

    /// **Zásuvka se otevře i tehdy, když se nic neposlalo**: běžící příkaz je přesně to, na co se
    /// má člověk podívat, než se rozhodne, co s ním.
    @Test("Zaneprázdněná zásuvka se řekne a stejně se vytáhne")
    func aBusyDrawerIsReportedAndShown() throws {
        let host = FakeTerminalHost()
        host.outcome = .busy
        let store = store(host)
        store.terminalDirectories[pullRequest] = URL(filePath: "/tmp/jinde")

        store.resumeInDrawer(session, for: pullRequest)

        #expect(store.isTerminalOpen)
        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("něco běží"))
        // Cesta zůstává stará: shell se nikam nepřesunul, takže by nová popiska lhala.
        #expect(store.terminalDirectory(for: pullRequest) == URL(filePath: "/tmp/jinde"))
    }

    /// Prázdná plocha bez věty vypadá k nerozeznání od toho, že se nekliklo.
    @Test("Nespuštěný shell se řekne")
    func aShellThatNeverStartedIsReported() throws {
        let host = FakeTerminalHost()
        host.outcome = .noShell

        let store = store(host)
        store.resumeInDrawer(session, for: pullRequest)

        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("nepodařilo spustit"))
    }

    /// Hláška zmizí teprve tehdy, když se to **doopravdy povede**. Jedna instance se dvěma
    /// odpověďmi schválně: dvě by o zahození netvrdily nic.
    @Test("Povedený pokus po nepovedeném hlášku zahodí")
    func aSuccessfulRetryClearsTheNotice() {
        let host = FakeTerminalHost()
        host.outcome = .busy
        let store = store(host)

        store.resumeInDrawer(session, for: pullRequest)
        #expect(store.terminalFailure != nil)

        host.outcome = .sent
        store.resumeInDrawer(session, for: pullRequest)

        #expect(store.terminalFailure == nil)
        #expect(host.ran.count == 2)
    }

    // MARK: - Bez zásuvky

    /// **Tlačítko se nekreslí**, místo aby tiše spadlo zpátky na `Terminal.app` — dvě různá
    /// chování pod jednou ikonou znamenají, že se nedá spolehnout ani na jedno.
    @Test("Bez hostitele se ▶ nenabízí a nic se nestane")
    func withoutAHostThereIsNoButton() {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource()
        )
        store.openTabs = [pullRequest]
        store.activeTab = .pullRequest(pullRequest)

        #expect(!store.hasTerminalDrawer)

        store.resumeInDrawer(session, for: pullRequest)

        #expect(!store.isTerminalOpen)
        #expect(store.terminalFailure == nil)
    }

    @Test("S hostitelem se ▶ nabízí")
    func withAHostTheButtonIsOffered() {
        #expect(store(FakeTerminalHost()).hasTerminalDrawer)
    }
}
