import Foundation
import Testing

@testable import PRism

/// Identita procesu a úklid sirotků proti **skutečné** tabulce procesů (#351).
///
/// Fake tabulka umí vyjmenovat stavy, které se nasimulovat nedají; tady se naopak ověřuje to, co
/// se bez skutečného jádra ověřit nedá — že `sysctl(KERN_PROC_PID)` vrací to, co si o něm myslíme,
/// a že `SIGKILL` neodejde na proces, který se pod tím PID vyměnil.
///
/// **Zabíjí se jedině to, co si tenhle test sám spustil.** Na stroji běží `claude` mimo aplikaci
/// (uživatelovy vlastní session, paralelní agenti), takže PID se nikde nehádá ani nehledá v `ps`.
@Suite("Identita procesu proti skutečnému systému")
struct SystemProcessInspectorTests {
    private let inspector = SystemProcessInspector()

    /// Proces, který nedoběhne sám, dokud ho test nezabije. Deset minut je tatáž rezerva jako
    /// v `SubprocessStreamerTests`: kdyby si `sleep` doběhl, „zmizel“ by platilo samo a test by
    /// netvrdil nic.
    private func startSleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "exec sleep 600"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    @Test("Běžící proces má identitu, doběhlý žádnou")
    func readsTheIdentityOfARealProcess() async throws {
        let sleeper = try startSleeper()
        let pid = sleeper.processIdentifier

        let identity = inspector.identity(of: pid)
        #expect(identity?.pid == pid)
        // Nula by znamenala, že se čte z nevyplněné struktury — `sysctl` totiž vrátí `0`
        // i pro PID, které neexistuje, a rozhoduje až velikost zapsaných dat.
        #expect((identity?.startedAt ?? 0) > 0)

        sleeper.terminate()
        #expect(await processHasGone(pid))
        #expect(inspector.identity(of: pid) == nil)
    }

    @Test("Nekladné PID nemá identitu, i když na něj jádro odpovídá")
    func rejectsNonPositivePIDs() {
        // `sysctl` na `pid == 0` **odpoví** (jádro), takže bez téhle pojistky by z nuly vylezla
        // platná identita — a `kill(0, …)` míří na celou procesovou skupinu volajícího, tedy na
        // aplikaci samotnou. Je to tatáž past, na kterou u #121 upozornil Copilot v sondě.
        #expect(inspector.identity(of: 0) == nil)
        #expect(inspector.identity(of: -1) == nil)
    }

    @Test("Signál neodejde na proces, který se pod tím PID vyměnil")
    func neverKillsAProcessWithAMismatchedIdentity() async throws {
        // Skutečný proces, skutečné PID — jen zapsaný okamžik vzniku je jiný, tedy přesně to, co
        // po restartu znamená „tenhle PID mezitím dostal někdo jiný“. Tady se to dá vyzkoušet na
        // živém procesu, protože kontrola je uvnitř `kill`, ne u volajícího.
        let stranger = try startSleeper()
        defer { stranger.terminate() }
        let pid = stranger.processIdentifier
        let real = try #require(inspector.identity(of: pid))
        let mismatched = ProcessIdentity(pid: pid, startedAt: real.startedAt + 1)

        #expect(inspector.kill(mismatched) == false)

        // Že proces pořád běží, je celé tvrzení testu. Krátká odmlka mu dává čas umřít, kdyby
        // signál přece jen odešel — bez ní by test prošel i tehdy, kdyby `SIGKILL` byl na cestě.
        await settle()
        #expect(inspector.identity(of: pid) == real)
    }

    @Test("Se správnou identitou signál odejde")
    func killsWhenTheIdentityMatches() async throws {
        let sleeper = try startSleeper()
        let pid = sleeper.processIdentifier
        let identity = try #require(inspector.identity(of: pid))

        #expect(inspector.kill(identity))

        #expect(await processHasGone(pid))
    }

    @Test("Sirotek po zabité aplikaci se doopravdy zabije")
    func reapsARealOrphan() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        let orphan = try startSleeper()
        let pid = orphan.processIdentifier

        // Vlastník, který **doopravdy** neběží: skutečný proces, který se nechá umřít. Vymyšlené
        // PID by prošlo taky, ale takhle je v testu tentýž stav, jaký nastane po zabité aplikaci.
        let deadOwner = try startSleeper()
        let ownerIdentity = try #require(inspector.identity(of: deadOwner.processIdentifier))
        deadOwner.terminate()
        #expect(await processHasGone(deadOwner.processIdentifier))

        let registry = RunningSessions(layout: layout, inspector: inspector, owner: ownerIdentity)
        registry.remember(pid: pid)

        #expect(registry.reapOrphans() == 1)

        #expect(await processHasGone(pid))
    }

    @Test("Session živé aplikace zůstane běžet")
    func leavesTheSessionOfALivingOwnerAlone() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        let sleeper = try startSleeper()
        defer { sleeper.terminate() }
        let pid = sleeper.processIdentifier

        // Vlastníkem je tenhle běh testů, tedy proces, který nesporně běží.
        let registry = RunningSessions(layout: layout, inspector: inspector)
        registry.remember(pid: pid)

        #expect(registry.reapOrphans() == 0)

        await settle()
        #expect(inspector.identity(of: pid) != nil)
    }
}
