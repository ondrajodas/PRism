import Foundation
import Testing

@testable import PRism

/// Otevření session v Terminálu ze storu (#453).
///
/// Proti **fake** `TerminalOpening`, protože tady se testuje to, co store dělá s odpovědí — a to
/// hlavní je, že neúspěch **skončí ve stavovém řádku**. Okno se otevírá mimo aplikaci, takže
/// spolknutá chyba vypadá k nerozeznání od toho, že se nekliklo.
@Suite("AppStore — terminál (#453)")
@MainActor
struct AppStoreTerminalTests {
    private let session = TerminalSession(
        directory: URL(filePath: "/Users/o/cache/worktrees/o/r/6-abc"),
        command: "claude --resume abc-123",
        skill: "php-review"
    )

    private func store(_ terminal: FakeTerminal) -> AppStore {
        AppStore(gateway: FakeGitHubGateway(always: .success([])), terminal: terminal)
    }

    @Test("Do terminálu jde řádka, která napřed přejde do pracovního stromu")
    func theWorktreeComesFirst() async {
        let terminal = FakeTerminal()
        let store = store(terminal)

        await store.openInTerminal(session)

        #expect(
            terminal.openedLines == ["cd '/Users/o/cache/worktrees/o/r/6-abc' && claude --resume abc-123"]
        )
        #expect(store.terminalFailure == nil)
    }

    /// **Nejcennější tvrzení téhle suity.** Neotevřené okno se z aplikace nedá poznat jinak než
    /// tímhle textem — `try?` nad tou cestou by z tlačítka udělal něco, co občas nedělá nic.
    @Test("Neotevřené okno skončí hláškou, ne tichem")
    func aFailureIsReported() async throws {
        let terminal = FakeTerminal(failing: .failed("Not authorized to send Apple events to Terminal."))
        let store = store(terminal)

        await store.openInTerminal(session)

        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("Not authorized to send Apple events to Terminal."))
        #expect(failure.contains("Terminálu"))
    }

    /// Hláška zmizí teprve tehdy, když se to **doopravdy povede** — ne při dalším kliknutí.
    /// Jedna instance se dvěma odpověďmi schválně: dvě by o zahození netvrdily nic.
    @Test("Povedený pokus po nepovedeném hlášku zahodí")
    func aSuccessfulRetryClearsTheNotice() async {
        let terminal = FakeTerminal(failing: .failed("nešlo to"))
        let store = store(terminal)

        await store.openInTerminal(session)
        #expect(store.terminalFailure != nil)

        terminal.willSucceed()
        await store.openInTerminal(session)

        #expect(store.terminalFailure == nil)
        #expect(terminal.openedLines.count == 2)
    }

    /// Store bez terminálu je testovací store — a nesmí si vymyslet hlášku o něčem, o co se
    /// nikdo nepokusil.
    @Test("Store bez terminálu neotevře nic a nic nehlásí")
    func aStoreWithoutATerminalDoesNothing() async {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])))

        await store.openInTerminal(session)

        #expect(store.terminalFailure == nil)
    }
}
