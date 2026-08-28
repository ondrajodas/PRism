import Foundation
import Testing

@testable import PRism

/// `▶` pouští session v **zásuvce**, a zásuvka jich drží víc naráz (#460).
///
/// Nejcennější jsou tady tři tvrzení o tom, co se **ne**stane: druhá session tu první
/// **nepřebije** (kvůli tomu se celé #460 měnilo — aplikace pouští review paralelně), po `busy`
/// se **nepřepíše cesta v hlavičce** (shell dál stojí tam, kde stál) a strop **nevytlačí běžící
/// relaci** (zahodit rozdělaný `claude --resume` kvůli kliknutí jinde by byl nevratný omyl).
@Suite("AppStore — relace v zásuvce (#460)")
@MainActor
struct AppStoreResumeInDrawerTests {
    private let pullRequest = PRIdentifier("cli/cli#42")!
    private let worktree = URL(filePath: "/Users/o/Library/Application Support/PRism/w/6-abc")

    private func session(_ skill: String, id: String = "8c1f-42") -> TerminalSession {
        TerminalSession(
            directory: worktree,
            command: Policy.drawerResumeCommand(sessionID: id),
            skill: skill
        )
    }

    private func slot(_ skill: String) -> TerminalSlot {
        TerminalSlot(pullRequest: pullRequest, role: .session(skill))
    }

    private var shell: TerminalSlot { TerminalSlot(pullRequest: pullRequest, role: .shell) }

    private func store(_ host: FakeTerminalHost, trust: FakeWorkspaceTrust? = nil) -> AppStore {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource(),
            terminals: host,
            workspaceTrust: trust
        )
        store.openTabs = [pullRequest]
        store.activeTab = .pullRequest(pullRequest)
        return store
    }

    // MARK: - Co se pustí

    /// Celý slib #460: `▶` **vytáhne zásuvku** místo cizího okna a session v ní naváže.
    @Test("▶ vytáhne zásuvku a pustí v ní session")
    func theDrawerOpensAndTheSessionResumes() async throws {
        let host = FakeTerminalHost()
        let store = store(host)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(store.isTerminalOpen)
        let run = try #require(host.ran.first)
        #expect(host.ran.count == 1)
        #expect(run.slot == slot("php-review"))
        #expect(run.directory == worktree)
        #expect(store.activeTerminalSlot(for: pullRequest) == slot("php-review"))
        #expect(store.terminalFailure == nil)
    }

    /// **Tatáž řádka, jakou od #453 dostával `Terminal.app`** — s `cd` do pracovního stromu
    /// a s uzávorkovanou cestou.
    @Test("Do relace jde cd do stromu a teprve pak resume")
    func theWorktreeComesFirst() async {
        let host = FakeTerminalHost()

        await store(host).resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(
            host.ran.first?.line
                == "cd '/Users/o/Library/Application Support/PRism/w/6-abc' "
                + "&& claude --resume 8c1f-42 --permission-mode auto"
        )
        #expect(host.ran.first?.line == session("php-review").shellLine)
    }

    // MARK: - Víc relací naráz

    /// **Tohle je ta věc, kvůli které se #460 měnilo.** Aplikace pouští review paralelně, takže
    /// druhá session nesmí tu první přebít — obě mají vlastní relaci a přepíná se mezi nimi.
    @Test("Druhá session první nepřebije")
    func theSecondSessionKeepsTheFirst() async {
        let host = FakeTerminalHost()
        let store = store(host)

        await store.resumeInDrawer(session("php-review", id: "aaa"), for: pullRequest)
        await store.resumeInDrawer(session("security-review", id: "bbb"), for: pullRequest)

        #expect(store.terminalSlots[pullRequest] == [slot("php-review"), slot("security-review")])
        #expect(store.activeTerminalSlot(for: pullRequest) == slot("security-review"))
        // Dvě relace = dvě pty, tedy dvě různá volání hostitele.
        #expect(host.ran.map(\.slot) == [slot("php-review"), slot("security-review")])
    }

    /// Klik na záložku přepínače **nic nespouští ani nezabíjí** — je to pohled.
    @Test("Klik na záložku jen přepne")
    func selectingATabOnlySwitches() async {
        let host = FakeTerminalHost()
        let store = store(host)
        await store.resumeInDrawer(session("php-review"), for: pullRequest)
        await store.resumeInDrawer(session("security-review"), for: pullRequest)

        store.selectTerminalSlot(slot("php-review"))

        #expect(store.activeTerminalSlot(for: pullRequest) == slot("php-review"))
        #expect(host.ran.count == 2)
        #expect(host.stopped.isEmpty)
    }

    /// Relace, kterou zásuvka nemá, se vybrat nedá — jinak by hlavička ukazovala prázdno.
    @Test("Neexistující relace se nevybere")
    func anUnknownSlotIsIgnored() async {
        let store = store(FakeTerminalHost())
        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        store.selectTerminalSlot(slot("docs-review"))

        #expect(store.activeTerminalSlot(for: pullRequest) == slot("php-review"))
    }

    /// `` ⌃` `` dává relaci `shell` — tedy jednu z relací, ne něco vedle nich.
    ///
    /// Sekvence je ta skutečná: `▶` zásuvku vytáhne, první `` ⌃` `` ji schová a druhé zase
    /// vytáhne. Teprve to druhé je „vytáhni mi terminál“, a **nesmí přepnout** na `shell`:
    /// dostat místo běžícího `claude --resume` prázdný prompt je to jediné, co na téhle klávese
    /// může překvapit.
    @Test("⌃` dá relaci shell a běžící session nepřebije")
    func theShellIsOneOfTheSlots() async {
        let store = store(FakeTerminalHost())
        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        await store.toggleTerminal()
        #expect(!store.isTerminalOpen)
        await store.toggleTerminal()

        #expect(store.isTerminalOpen)
        #expect(store.terminalSlots[pullRequest] == [slot("php-review"), shell])
        #expect(store.activeTerminalSlot(for: pullRequest) == slot("php-review"))
    }

    /// Nad pull requestem, který v zásuvce ještě nic neměl, `` ⌃` `` relaci `shell` **ukáže** —
    /// jinak by se vytáhla prázdná zásuvka bez jediné záložky.
    @Test("Na prázdné zásuvce se ⌃` na shell přepne")
    func theShellIsShownWhenTheDrawerIsEmpty() async {
        let store = store(FakeTerminalHost())

        await store.toggleTerminal()

        #expect(store.terminalSlots[pullRequest] == [shell])
        #expect(store.activeTerminalSlot(for: pullRequest) == shell)
    }

    /// **Hotové relaci se cesta v hlavičce nepřepisuje** (nález Copilota). Hostitel vrací
    /// existující plochu a nový adresář si nevezme, takže by popiska ukazovala jinam, než kde
    /// shell doopravdy stojí — a to je text, který tvrdí víc, než data unesou.
    @Test("Znovuotevření zásuvky nepřepíše cestu běžící relaci")
    func reopeningKeepsTheDirectoryOfALiveSlot() async {
        let store = store(FakeTerminalHost())
        let standing = URL(filePath: "/tmp/kde-shell-stoji")
        store.terminalSlots[pullRequest] = [shell]
        store.terminalDirectories[shell] = standing
        store.terminalStates[shell] = .running

        await store.toggleTerminal()

        #expect(store.terminalDirectory(of: shell) == standing)
    }

    /// Záložky přepínače nesou puntík podle stavu **té** relace, ne jednoho stavu na zásuvku.
    @Test("Přepínač nese stav každé relace zvlášť")
    func everyTabCarriesItsOwnState() async throws {
        let store = store(FakeTerminalHost())
        await store.resumeInDrawer(session("php-review"), for: pullRequest)
        await store.resumeInDrawer(session("security-review"), for: pullRequest)
        store.terminalStates[slot("php-review")] = .running
        store.terminalStates[slot("security-review")] = .exited(code: 130)

        let rows = store.terminalRows(for: pullRequest)

        #expect(rows.map(\.title) == ["php-review", "security-review"])
        #expect(rows.map(\.mark) == [.running, .failed])
        #expect(rows.map(\.isActive) == [false, true])
        #expect(try #require(rows.last).help.contains("130"))
    }

    // MARK: - Strop

    /// **Běžící relace se nevytlačuje.** Když je plno a všechny běží, nová nevznikne a řekne se to
    /// — mlčky nevzniklá záložka vypadá jako rozbité tlačítko.
    @Test("Plný strop s běžícími relacemi novou nepustí")
    func afullDrawerRefusesAndSaysSo() async throws {
        let host = FakeTerminalHost()
        let store = store(host)
        let taken = (0..<Policy.maxTerminalSlots).map { slot("reviewer-\($0)") }
        store.terminalSlots[pullRequest] = taken
        for slot in taken { store.terminalStates[slot] = .running }

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(store.terminalSlots[pullRequest] == taken)
        #expect(host.ran.isEmpty)
        #expect(host.stopped.isEmpty)
        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("php-review"))
        #expect(failure.contains("\(Policy.maxTerminalSlots)"))
    }

    /// Vytlačí se **nejstarší neběžící**: zahodí se jen výpis, který je z definice minulost.
    @Test("Plný strop vytlačí nejstarší doběhlou relaci")
    func afullDrawerEvictsTheOldestIdleSlot() async {
        let host = FakeTerminalHost()
        let store = store(host)
        let taken = (0..<Policy.maxTerminalSlots).map { slot("reviewer-\($0)") }
        store.terminalSlots[pullRequest] = taken
        for slot in taken.dropFirst() { store.terminalStates[slot] = .running }
        store.terminalStates[taken[0]] = .exited(code: 0)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(host.stopped == [taken[0]])
        #expect(store.terminalSlots[pullRequest]?.contains(taken[0]) == false)
        #expect(store.terminalSlots[pullRequest]?.last == slot("php-review"))
        #expect(host.ran.count == 1)
    }

    // MARK: - Když se nic neposlalo

    /// **Přepne se na tu relaci, i když se nic neposlalo**: běžící příkaz je přesně to, na co se
    /// má člověk podívat — a od #460 to není slepá ulička.
    @Test("Zaneprázdněná relace se řekne a stejně se ukáže")
    func abusySlotIsReportedAndShown() async throws {
        let host = FakeTerminalHost()
        host.outcome = .busy
        let store = store(host)
        store.terminalSlots[pullRequest] = [slot("php-review")]
        store.terminalDirectories[slot("php-review")] = URL(filePath: "/tmp/jinde")

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(store.isTerminalOpen)
        #expect(store.activeTerminalSlot(for: pullRequest) == slot("php-review"))
        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("php-review"))
        #expect(failure.contains("něco běží"))
        // Cesta zůstává stará: shell se nikam nepřesunul, takže by nová popiska lhala.
        #expect(store.terminalDirectory(of: slot("php-review")) == URL(filePath: "/tmp/jinde"))
    }

    /// Prázdná plocha bez věty vypadá k nerozeznání od toho, že se nekliklo.
    ///
    /// **Cesta se u toho přesto zapíše**, a je to rozhodnutí, ne nedůslednost (nález Copilota):
    /// bez ní kreslí zásuvka větu „Tenhle pull request nemá v cache pracovní kopii“, a ta by
    /// lhala — strom na disku je, nepovedl se shell.
    @Test("Nespuštěný shell se řekne, ale cesta v hlavičce zůstane pravdivá")
    func aShellThatNeverStartedIsReported() async throws {
        let host = FakeTerminalHost()
        host.outcome = .noShell

        let store = store(host)
        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        let failure = try #require(store.terminalFailure)
        #expect(failure.contains("nepodařilo spustit"))
        #expect(store.terminalDirectory(of: slot("php-review")) == worktree)
    }

    /// Hláška zmizí teprve tehdy, když se to **doopravdy povede**.
    @Test("Povedený pokus po nepovedeném hlášku zahodí")
    func aSuccessfulRetryClearsTheNotice() async {
        let host = FakeTerminalHost()
        host.outcome = .busy
        let store = store(host)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)
        #expect(store.terminalFailure != nil)

        host.outcome = .sent
        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(store.terminalFailure == nil)
        #expect(host.ran.count == 2)
    }

    // MARK: - Bez zásuvky

    /// **Tlačítko se nekreslí**, místo aby tiše spadlo zpátky na `Terminal.app`.
    @Test("Bez hostitele se ▶ nenabízí a nic se nestane")
    func withoutAHostThereIsNoButton() async {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource()
        )
        store.openTabs = [pullRequest]
        store.activeTab = .pullRequest(pullRequest)

        #expect(!store.hasTerminalDrawer)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(!store.isTerminalOpen)
        #expect(store.terminalFailure == nil)
        #expect(store.terminalSlots[pullRequest] == nil)
    }

    @Test("S hostitelem se ▶ nabízí")
    func withAHostTheButtonIsOffered() {
        #expect(store(FakeTerminalHost()).hasTerminalDrawer)
    }

    // MARK: - Důvěra ke složce (#460)

    /// **Zapisuje se dřív, než se řádka pošle** — jinak by `claude` stihl vyskočit s dotazem.
    /// A zapisuje se **kořen cache**, ne strom toho PR: důvěra se dědí, takže jeden záznam
    /// pokryje všechny pull requesty.
    @Test("▶ napřed zapíše důvěru ke kořeni cache, pak pustí session")
    func trustIsRegisteredBeforeTheCommandGoesOut() async {
        let host = FakeTerminalHost()
        let trust = FakeWorkspaceTrust()
        let store = store(host, trust: trust)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(trust.trusted == [CacheLayout.applicationSupport.root])
        #expect(host.ran.count == 1)
    }

    /// **Konfigurace se nečte při každém otevření zásuvky**: `~/.claude.json` má přes 200 kB
    /// a hodnota se mění jednou za život složky.
    @Test("Důvěra se zapisuje jednou, ne při každém otevření")
    func trustIsRegisteredOnlyOnce() async {
        let host = FakeTerminalHost()
        let trust = FakeWorkspaceTrust()
        let store = store(host, trust: trust)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)
        await store.resumeInDrawer(session("security-review"), for: pullRequest)
        await store.toggleTerminal()

        #expect(trust.trusted.count == 1)
    }

    /// **Po neúspěchu se to zkusí znovu.** Dokud se to nepovede, chodí ten dotaz na důvěru —
    /// a vzdát to po prvním pokusu by znamenalo, že se z něj nikdy nevyhrabeme.
    @Test("Nepovedený zápis se zkusí při dalším otevření znovu")
    func afailedRegistrationIsRetried() async {
        let host = FakeTerminalHost()
        let trust = FakeWorkspaceTrust()
        trust.failure = WorkspaceTrustError.configurationUnreadable
        let store = store(host, trust: trust)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)
        #expect(trust.trusted.count == 1)
        // **A session se pustí i tak** — dialog navíc je pořád lepší než tlačítko, které nic neudělá.
        #expect(host.ran.count == 1)
        #expect(store.terminalFailure == nil)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(trust.trusted.count == 2)
    }

    /// Store bez té závislosti nesmí spadnout ani si nic vymyslet — tak jsou na tom testy, které
    /// o konfiguraci Claude Code nestojí.
    @Test("Bez závislosti se nic nezapisuje")
    func withoutTheDependencyNothingIsWritten() async {
        let host = FakeTerminalHost()
        let store = store(host)

        await store.resumeInDrawer(session("php-review"), for: pullRequest)

        #expect(host.ran.count == 1)
    }
}

/// Zápis důvěry, který nic nezapisuje — jen si pamatuje, na co se ho kdo ptal.
///
/// `@MainActor` schválně: volá se z `AppStore`, který na hlavním aktoru je, takže si fake vystačí
/// s jeho izolací a nepotřebuje zámek (a zámky se v `async` kontextu brát nesmí).
@MainActor
final class FakeWorkspaceTrust: WorkspaceTrusting {
    private(set) var trusted: [URL] = []

    /// Když je nastavená, `trust(_:)` ji vyhodí — pokus se ale **zaznamená**, takže se dá tvrdit,
    /// že se opakuje.
    var failure: (any Error)?

    func trust(_ directory: URL) async throws {
        trusted.append(directory)
        if let failure { throw failure }
    }
}
