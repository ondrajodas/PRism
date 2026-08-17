import Foundation
import Testing

@testable import PRism

/// Registr běžících podprocesů a úklid sirotků po zabité aplikaci (#351).
///
/// Proti **skutečné** dočasné složce, jako `AnnouncedPullRequests` — právě o to tady jde, že
/// značka přežije smrt aplikace. Tabulka procesů je naopak fake: stavy, o které jde nejvíc
/// (PID, které mezitím dostal někdo jiný), se skutečnými procesy vyrobit nedají.
///
/// Cennější polovina téhle suity jsou testy, které tvrdí, že se **nic nezabilo**. Ty se rozbijí
/// potichu: zabít cizí `claude` je horší než nechat běžet sirotka, a na stroji jich běží víc
/// (uživatelovy vlastní session, paralelní agenti).
@Suite("RunningSessions")
struct RunningSessionsTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    /// Instance aplikace, která běhy spustila, a její podproces. „Zabitá zvenčí“ se v testech
    /// vyrábí tím, že se do tabulky procesů po úklidu vlastník nedá.
    private let owner = ProcessIdentity(pid: 4_242, startedAt: 1_000)
    private let session = ProcessIdentity(pid: 8_484, startedAt: 2_000)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func sessions(
        owner: ProcessIdentity?,
        inspector: FakeProcessInspector
    ) -> RunningSessions {
        RunningSessions(layout: layout, inspector: inspector, owner: owner)
    }

    /// Co doopravdy leží v cache. Čte se **soubor**, ne getter na objektu: značka má cenu jedině
    /// tím, že přežije proces, který ji zapsal.
    private func stored() throws -> [RunningSession] {
        guard let data = try? Data(contentsOf: layout.sessionsFile) else { return [] }
        return try JSONDecoder().decode([RunningSession].self, from: data)
    }

    private func recycled(_ identity: ProcessIdentity) -> ProcessIdentity {
        ProcessIdentity(pid: identity.pid, startedAt: identity.startedAt + 1)
    }

    @Test("Značka běžícího procesu skončí v cache i s identitou z jádra")
    func remembersARunningProcess() throws {
        let inspector = FakeProcessInspector(running: [owner, session])

        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)

        #expect(try stored() == [RunningSession(owner: owner, process: session)])
    }

    @Test("Identita se bere z tabulky procesů, ne od volajícího")
    func doesNotRememberAProcessThatIsNotRunning() throws {
        // Volající předává jen PID. Kdyby se dala předat i identita, dala by se značka zapsat
        // s vymyšleným `startedAt` — a úklid při startu by pak poslal signál cizímu procesu.
        let inspector = FakeProcessInspector(running: [owner])

        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)

        #expect(try stored().isEmpty)
    }

    @Test("Bez vlastní identity se nezapisuje nic")
    func doesNotRememberWithoutAnOwner() throws {
        // Značka bez vlastníka by se při dalším startu tvářila jako sirotek, takže by si
        // aplikace zabila vlastní běh.
        let inspector = FakeProcessInspector(running: [session])

        sessions(owner: nil, inspector: inspector).remember(pid: session.pid)

        #expect(try stored().isEmpty)
    }

    @Test("Konec procesu značku smaže")
    func forgetsAFinishedProcess() throws {
        let inspector = FakeProcessInspector(running: [owner, session])
        let registry = sessions(owner: owner, inspector: inspector)
        registry.remember(pid: session.pid)

        registry.forget(pid: session.pid)

        #expect(try stored().isEmpty)
    }

    @Test("Cizí značku nikdo nemaže")
    func keepsTheMarkOfAnotherInstance() throws {
        // Testovací host má stejné `CFBundleName`, tedy tutéž cache jako aplikace
        // v `/Applications`. Smazat její značku by znamenalo, že o jejím běhu nikdo neví
        // a její sirotek nikdy neodejde.
        let foreignOwner = ProcessIdentity(pid: 5_555, startedAt: 3_000)
        let inspector = FakeProcessInspector(running: [foreignOwner, owner, session])
        sessions(owner: foreignOwner, inspector: inspector).remember(pid: session.pid)

        sessions(owner: owner, inspector: inspector).forget(pid: session.pid)

        #expect(try stored() == [RunningSession(owner: foreignOwner, process: session)])
    }

    @Test("Sirotek po zabité aplikaci se zabije a značka odejde")
    func killsAnOrphanOfADeadOwner() throws {
        let inspector = FakeProcessInspector(running: [owner, session])
        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)
        // Aplikace umřela zvenčí — v tabulce po ní nezůstalo nic, ale její `claude` běží dál.
        let afterTheKill = FakeProcessInspector(running: [session])

        let killed = sessions(owner: nil, inspector: afterTheKill).reapOrphans()

        #expect(killed == 1)
        #expect(afterTheKill.killedProcesses == [session])
        #expect(try stored().isEmpty)
    }

    @Test("Cizí proces na zapsaném PID se nezabije")
    func neverKillsAForeignProcessOnARecycledPID() throws {
        // Tvrzení, na kterém #351 stojí. Značka zůstala po mrtvé aplikaci, ale její PID mezitím
        // dostal někdo jiný — třeba `claude` z jiného slotu nebo uživatelova vlastní session.
        let inspector = FakeProcessInspector(running: [owner, session])
        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)
        let stranger = recycled(session)
        let afterTheKill = FakeProcessInspector(running: [stranger])

        let killed = sessions(owner: nil, inspector: afterTheKill).reapOrphans()

        #expect(killed == 0)
        // **Nikdo se o to ani nepokusil.** Slabší tvrzení („signál neodešel“) by prošlo i nad
        // rozhodnutím, které cizí proces zabít chtělo a zastavila ho až kontrola v `kill` —
        // změřeno vloženou regresí.
        #expect(afterTheKill.killRequests.isEmpty)
        #expect(afterTheKill.killedProcesses.isEmpty)
        // Značka odejde: proces, který se jí ohlásil, už neexistuje.
        #expect(try stored().isEmpty)
    }

    @Test("Session živé aplikace se nezabije ani nezapomene")
    func neverKillsASessionOfALivingOwner() throws {
        // Zrovna tohle by rozbil běh testů: `xcodebuild test` spouští testovacího hosta nad
        // stejnou cache jako aplikaci, se kterou se pracuje.
        let inspector = FakeProcessInspector(running: [owner, session])
        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)
        let secondInstance = ProcessIdentity(pid: 9_999, startedAt: 4_000)
        let table = FakeProcessInspector(running: [owner, session, secondInstance])

        let killed = sessions(owner: secondInstance, inspector: table).reapOrphans()

        #expect(killed == 0)
        #expect(table.killRequests.isEmpty)
        #expect(table.killedProcesses.isEmpty)
        #expect(try stored() == [RunningSession(owner: owner, process: session)])
    }

    @Test("Doběhlá session se jen zapomene, signál nikam nejde")
    func discardsAMarkOfAFinishedSession() throws {
        let inspector = FakeProcessInspector(running: [owner, session])
        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)
        let afterTheKill = FakeProcessInspector()

        let killed = sessions(owner: nil, inspector: afterTheKill).reapOrphans()

        #expect(killed == 0)
        #expect(afterTheKill.killRequests.isEmpty)
        #expect(afterTheKill.killedProcesses.isEmpty)
        #expect(try stored().isEmpty)
    }

    @Test("Když není co uklidit, úklid na soubor vůbec nesáhne")
    func doesNotWriteWhenThereIsNothingToReap() throws {
        // Start, po kterém není co dělat, je běžný stav — aplikace se obvykle zavírá normálně.
        // A hlavně: zápis „naprázdno“ by uměl přepsat značku, kterou mezitím zapsala jiná instance
        // téhož bundlu (testovací host nad tou samou cache), a její sirotek by neodešel nikdy.
        let inspector = FakeProcessInspector(running: [owner, session])
        sessions(owner: owner, inspector: inspector).remember(pid: session.pid)

        // **Soubor se přeformátuje na kompaktní JSON**, ať se pozná i zápis, který by uložil
        // totéž. Porovnání „stejný obsah“ by tichý přepis nechytlo — zapisuje se týž seznam.
        let compact = try JSONEncoder().encode(try stored())
        try compact.write(to: layout.sessionsFile)

        #expect(sessions(owner: owner, inspector: inspector).reapOrphans() == 0)

        #expect(try Data(contentsOf: layout.sessionsFile) == compact)
    }

    @Test("Prázdná cache po úklidu žádný soubor nezaloží")
    func doesNotCreateTheFileOutOfNothing() {
        let inspector = FakeProcessInspector(running: [session])

        #expect(sessions(owner: owner, inspector: inspector).reapOrphans() == 0)

        #expect(FileManager.default.fileExists(atPath: layout.sessionsFile.path(percentEncoded: false)) == false)
    }

    @Test("Nečitelný soubor se bere jako prázdný a nic nezabije")
    func treatsAnUnreadableFileAsEmpty() throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try Data("tohle není JSON".utf8).write(to: layout.sessionsFile)
        let inspector = FakeProcessInspector(running: [session])

        let killed = sessions(owner: owner, inspector: inspector).reapOrphans()

        #expect(killed == 0)
        #expect(inspector.killRequests.isEmpty)
    }

    @Test("Opakované spuštění téhož PID nenechá v souboru dvě značky")
    func replacesTheMarkOfTheSamePID() throws {
        let inspector = FakeProcessInspector(running: [owner, session])
        let registry = sessions(owner: owner, inspector: inspector)

        registry.remember(pid: session.pid)
        registry.remember(pid: session.pid)

        #expect(try stored().count == 1)
    }
}
