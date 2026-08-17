import Foundation
import Testing

@testable import PRism

/// Proti skutečným procesům, ne proti fake runneru.
///
/// Fake ověří, co se `claude` posílá; jestli tomu rozumí `Process` — že řádky přijdou
/// v pořadí, že EOF dorazí dřív než konec proudu a že zabitý proces skončí timeoutem —
/// se dá zjistit jen spuštěním. Přesně tohle unit testy `RepoCheckoutu` nechytly.
///
/// **Timeout, po kterém se čeká výsledek, je velkorysý a je to strop proti zátěži** (#296) — tatáž
/// úvaha jako v `RealEnvironmentTests`, kde se při souběžném buildu tří slotů nestihl do 10 s
/// spustit a posbírat `/bin/echo`. Krátké timeouty v téhle suitě jsou naopak **předmětem** testu:
/// tam se ověřuje, že se zaseknutý proces ukončí, takže se musí předávat vlastní.
@Suite("SubprocessStreamer")
struct SubprocessStreamerTests {
    private let shell = URL(filePath: "/bin/sh")
    private let streamer = SubprocessStreamer()

    /// Jak dlouho „spí“ proces, který v testu **nemá skončit sám** — ve vteřinách pro `sleep`.
    ///
    /// Je to ta rezerva, ve které se rozhoduje: testy níž tvrdí, že proud ukončil **timeout**, a to
    /// je vidět jedině tehdy, když proces svůj `sleep` nedoběhne dřív. Do #296 tu bylo 30 s proti
    /// timeoutu 200–300 ms, tedy stonásobek — a **nestačilo to**: při třech souběžných clean
    /// buildech se časovač probudil až po skončení `sleepu`, proud dojel normálně a suita hlásila
    /// „chyba se čekala, ale žádná nepřišla“ nad kódem, který funguje. Deset minut je proti tomu
    /// rezerva 2000×.
    ///
    /// **Nezdržuje to zelený běh** — testy končí timeoutem po 200 ms a proces se zabíjí. Zdržel by
    /// jedině běh, ve kterém se timeout nezapojí vůbec, a tam by test čekal na konec `sleepu`, tedy
    /// deset minut. Proto k tomu patří `.timeLimit`: rozbitý timeout **spadne**, nezasekne běh.
    ///
    /// **Tři minuty, ne dvě**, a je to podmínka, ne estetika: strop musí být **nad**
    /// `TestWait.deadline` (2 min). Když se rovnaly, vypršely naráz a v hlášce stály dva různé
    /// důvody pádu („nedočkalo se“ i „time limit exceeded“) — změřeno vloženou regresí. A jedna
    /// minuta by byl další strop odvozený od volného stroje: pod třemi souběžnými buildy trvaly
    /// tyhle testy 20 až 27 s.
    private static let longerThanTheTest = 600

    private func collect(
        _ script: String,
        workingDirectory: URL? = nil,
        timeout: Duration = .seconds(60)
    ) async throws -> [ProcessEvent] {
        var events: [ProcessEvent] = []
        for try await event in streamer.stream(
            shell,
            arguments: ["-c", script],
            environment: [:],
            workingDirectory: workingDirectory,
            timeout: timeout
        ) {
            events.append(event)
        }
        return events
    }

    @Test("Řádky přijdou v pořadí a konec nese kód i stderr")
    func linesArriveInOrder() async throws {
        let events = try await collect("echo prvni; echo druhy; echo chyba >&2; exit 3")

        #expect(events == [
            .line("prvni"),
            .line("druhy"),
            .finished(exitCode: 3, standardError: "chyba\n"),
        ])
    }

    @Test("Nedokončený poslední řádek se doručí, ne zahodí")
    func aTruncatedLastLineIsStillDelivered() async throws {
        // Zabitý proces umí stream useknout uprostřed řádku. Zahodit ho by znamenalo, že
        // se nález bez konce řádku nedá odlišit od nálezu, který nikdy nebyl.
        let events = try await collect("printf 'cely\\nusek'")

        #expect(events.first == .line("cely"))
        #expect(events.dropFirst().first == .line("usek"))
    }

    @Test("Proces běží v předané pracovní složce")
    func theProcessRunsInTheGivenDirectory() async throws {
        // `claude` pracovní složku flagem předat neumí — je to `cwd` procesu.
        // `/bin/pwd`, ne builtin: ten umí vypsat zděděné `PWD`, ne skutečnou složku.
        let directory = URL(filePath: "/usr/lib")
        let events = try await collect("/bin/pwd", workingDirectory: directory)

        #expect(events.first == .line("/usr/lib"))
    }

    @Test("Zaseknutý proces skončí timeoutem", .timeLimit(.minutes(3)))
    func aStuckProcessTimesOut() async throws {
        await #expect(throws: ProcessError.timedOut) {
            _ = try await collect("sleep \(Self.longerThanTheTest)", timeout: .milliseconds(200))
        }
    }

    @Test("Řádky vypsané před timeoutem zůstanou doručené", .timeLimit(.minutes(3)))
    func linesBeforeATimeoutSurvive() async throws {
        var events: [ProcessEvent] = []
        let stream = streamer.stream(
            shell,
            arguments: ["-c", "echo nalez; sleep \(Self.longerThanTheTest)"],
            environment: [:],
            workingDirectory: nil,
            timeout: .milliseconds(300)
        )

        await #expect(throws: ProcessError.timedOut) {
            for try await event in stream { events.append(event) }
        }
        #expect(events == [.line("nalez")])
    }

    /// Sleepy jsou **dva**, protože se testuje potomek na pozadí — délka je z `longerThanTheTest`
    /// a proč, stojí u ní. Do #296 tady bylo `sleep 5 & sleep 5`, tedy nejkratší rezerva v suitě,
    /// a padalo to jako první.
    @Test("Timeout ukončí proud, i když roura zůstane otevřená", .timeLimit(.minutes(3)))
    func aTimeoutEndsTheStreamEvenWithAnOpenPipe() async throws {
        // Potomek na pozadí zdědí stdout a zabitý shell ho nepřežije — EOF tedy nedorazí.
        // Bez posledního slova timeoutu by proud čekal navždy a review by viselo.
        let streamer = SubprocessStreamer(gracePeriod: .milliseconds(100))

        await #expect(throws: ProcessError.timedOut) {
            for try await _ in streamer.stream(
                shell,
                arguments: ["-c", "sleep \(Self.longerThanTheTest) & sleep \(Self.longerThanTheTest)"],
                environment: [:],
                workingDirectory: nil,
                timeout: .milliseconds(200)
            ) {}
        }
    }

    /// Bez toho by session běžela dál i poté, co uživatel zavřel okno.
    ///
    /// **Sleduje se PID, ne soubor po procesu** — a je to oprava #101, ne kosmetika. Původní
    /// verze spouštěla `sleep 1; touch <soubor>`, po 200 ms rušila a po dalších 1,5 s ověřovala,
    /// že soubor není. Rezerva proti zpoždění pod zátěží tam byla jen ~800 ms a **nedala se
    /// zvětšit zdarma**: delší `sleep` znamená, že se test musí stejně dlouho dočkat jeho konce.
    /// Padalo to tím spíš, čím víc procesů pouštěly ostatní suity (Swift Testing je pouští
    /// paralelně) — po #73 vycházel jeden pád ze čtyř běhů, na commitu před ním 0 ze 3.
    ///
    /// Na PID se zabití pozná **v okamžiku, kdy nastane**, takže deadline může být klidně
    /// pětisekundový a test přesto skončí v desítkách milisekund. Zároveň testuje víc než dřív:
    /// nepřítomnost souboru dokazovala jen to, že `touch` neproběhl, kdežto zmizelý PID je
    /// přímo to tvrzení, které od zrušení chceme.
    @Test("Zrušení proces zabije", .timeLimit(.minutes(3)))
    func cancellationKillsTheProcess() async throws {
        let pidFile = temporaryPIDFile("streamer-cancel")
        let path = pidFile.path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let task = Task {
            for try await _ in streamer.stream(
                shell,
                arguments: ["-c", "echo $$ > '\(path)'; sleep \(Self.longerThanTheTest)"],
                environment: [:],
                workingDirectory: nil,
                timeout: .seconds(60)
            ) {}
        }

        // Rušit se má proces, který **doopravdy běží** — jinak by test mohl projít i tehdy,
        // kdyby se nespustil vůbec.
        let pid = try await processID(writtenTo: pidFile)
        task.cancel()

        // **Na proces se kouká dřív, než se počká na konec proudu** (#296): to čekání skončí i
        // tím, že procesu doběhne `sleep`, takže „zmizel“ by platilo samo. V opačném pořadí
        // procházel i runner s vyndaným zabíjením (změřeno vloženou regresí).
        #expect(await processHasGone(pid), "proces \(pid) po zrušení pořád běží")

        _ = try? await task.value
    }

    /// Zapojení registru běžících session (#351).
    ///
    /// Sám registr se testuje v `RunningSessionsTests`; tady jde o to, že ho streamovaná cesta
    /// **doopravdy volá** — jinak by po zabité aplikaci nebylo co dohledat a úklid při startu by
    /// nad prázdným souborem hlásil, že sirotci nejsou. Zapojení je zrovna to, co se rozbije
    /// potichu: registr zůstane zelený a v cache nic nebude.
    ///
    /// Značka se zapisuje uvnitř `launch()`, tedy **dřív, než se spuštěný shell dostane ke slovu** —
    /// proto se na ni po přečtení PID kouká rovnou, bez čekání. Zapomenutí je proti tomu v
    /// `terminationHandler`u, tedy asynchronní vůči zrušení, a čeká se na něj jako na jev.
    @Test("Streamovaná session se zapíše do registru a koncem zmizí", .timeLimit(.minutes(3)))
    func aStreamedSessionIsRegisteredAndForgotten() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        let registered = SubprocessStreamer(sessions: RunningSessions(layout: layout))
        let pidFile = temporaryPIDFile("streamer-registry")
        let path = pidFile.path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let task = Task {
            for try await _ in registered.stream(
                shell,
                arguments: ["-c", "echo $$ > '\(path)'; sleep \(Self.longerThanTheTest)"],
                environment: [:],
                workingDirectory: nil,
                timeout: .seconds(60)
            ) {}
        }

        let pid = try await processID(writtenTo: pidFile)
        #expect(Self.marks(in: layout).map(\.process.pid) == [pid])

        task.cancel()
        _ = try? await task.value

        #expect(await waitUntil("značka doběhlé session zmizí z registru") {
            Self.marks(in: layout).isEmpty
        })
    }

    /// Co leží v registru na disku. Čte se soubor, ne getter na objektu: značka má cenu jedině
    /// tím, že přežije proces, který ji zapsal.
    private static func marks(in layout: CacheLayout) -> [RunningSession] {
        guard let data = try? Data(contentsOf: layout.sessionsFile) else { return [] }
        return (try? JSONDecoder().decode([RunningSession].self, from: data)) ?? []
    }

    // Sonda na PID i její důvod jsou v `Tests/Support/ProcessProbing.swift` (#296).
}
