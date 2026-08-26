import Foundation
import Testing

@testable import PRism

/// Otevření session v `Terminal.app` (#453).
///
/// Skutečné okno se v testu neotevírá: `osascript` by si vyžádal povolení automatizace pro
/// testovacího hostitele a otevřená okna by po sobě nechal běh testů. Že Apple event doopravdy
/// projde, je **ověřené spuštěním** — postup i výsledek jsou v `docs/testovani.md`. Tady se tvrdí
/// to, co se spuštěním ověřit nedá: **tvar volání** a že se selhání nespolkne.
@Suite("Terminál — spuštění (#453)")
struct TerminalLauncherTests {
    private let line = "cd '/tmp/w' && claude --resume abc-123"

    // MARK: - Tvar volání

    @Test("Volá se systémový osascript, ne nic z PATH")
    func itCallsTheSystemOsascript() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        try await AppleScriptTerminal(runner: runner).open(line)

        #expect(runner.invocations.count == 1)
        #expect(runner.invocations.first?.executable == URL(filePath: "/usr/bin/osascript"))
    }

    /// **Příkaz jde jako argument (`argv`), ne vlepený do zdrojáku skriptu.** Je to jediné místo,
    /// kde se to dá pokazit nenápadně: uvozovka nebo zpětné lomítko v cestě k pracovnímu stromu
    /// by AppleScriptu rozbily řetězcový literál, takže by `do script` dostal něco jiného, než co
    /// se poskládalo — nebo by skript neprošel překladem a okno by se neotevřelo vůbec.
    @Test("Příkaz se do skriptu nevlepuje, předává se jako argument")
    func theCommandIsPassedAsAnArgument() async throws {
        let runner = FakeProcessRunner(exitCode: 0)

        try await AppleScriptTerminal(runner: runner).open(line)

        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments == ["-e", AppleScriptTerminal.script, line])
        #expect(!AppleScriptTerminal.script.contains(line))
        #expect(AppleScriptTerminal.script.contains("item 1 of argv"))
    }

    /// Příkaz s uvozovkami projde beze změny — právě proto je v `argv`.
    @Test("Uvozovky v příkazu se nikam neztratí")
    func quotesInTheCommandSurvive() async throws {
        let runner = FakeProcessRunner(exitCode: 0)
        let tricky = #"cd '/tmp/"a" \b' && claude --resume x"#

        try await AppleScriptTerminal(runner: runner).open(tricky)

        #expect(runner.invocations.first?.arguments.last == tricky)
    }

    // MARK: - Selhání se hlásí, nespolkne

    /// Neotevřené okno je vidět **jedině tím, že se nic nestane** — a to je k nerozeznání od toho,
    /// že se nekliklo. Tvrzení, že se z chyby stane hodnota, je proto to hlavní, co má tenhle typ
    /// držet.
    @Test("Nenulový kód je chyba i s tím, čím ji osascript vysvětlil")
    func aNonZeroExitBecomesAnError() async {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardError: "Not authorized to send Apple events to Terminal. (-1743)"
        )

        await #expect(throws: TerminalError.failed("Not authorized to send Apple events to Terminal. (-1743)")) {
            try await AppleScriptTerminal(runner: runner).open(line)
        }
    }

    /// Když `osascript` mlčí, zbývá aspoň kód: prázdná hláška ve stavovém řádku by vypadala, jako
    /// by se nic nestalo — a přitom se okno neotevřelo.
    @Test("Mlčící osascript nenechá prázdnou hlášku")
    func aSilentFailureStillSaysSomething() async throws {
        let runner = FakeProcessRunner(exitCode: 2)

        let error = await captured(runner)

        #expect(error == .failed("`osascript` skončil kódem 2."))
    }

    /// Vypršený limit je vlastní věta, protože má vlastní příčinu: nezodpovězený systémový dotaz
    /// na povolení automatizace.
    @Test("Vypršený limit řekne, na co se nejspíš čeká")
    func aTimeoutNamesTheLikelyCause() async throws {
        let runner = FakeProcessRunner(failing: .timedOut)

        let error = await captured(runner)

        #expect(error == .failed(
            "Terminal se v limitu neozval — zůstal nejspíš otevřený dotaz na povolení automatizace."
        ))
    }

    @Test("Nespuštěný osascript je taky chyba, ne ticho")
    func aFailedLaunchIsAnErrorToo() async throws {
        let runner = FakeProcessRunner(failing: .launchFailed("nejde"))

        let error = await captured(runner)

        guard case .failed(let text) = try #require(error) else { return }
        #expect(text.contains("osascript"))
    }

    /// Úspěch nevyhazuje nic — a je to tvrzení, ne samozřejmost: kdyby se kontrola kódu obrátila,
    /// hlásilo by okno chybu pokaždé, když se doopravdy otevřelo.
    @Test("Nulový kód je úspěch")
    func aZeroExitIsSuccess() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "tab 1 of window id 202861")

        try await AppleScriptTerminal(runner: runner).open(line)
    }

    private func captured(_ runner: FakeProcessRunner) async -> TerminalError? {
        do {
            try await AppleScriptTerminal(runner: runner).open(line)
            return nil
        } catch let error as TerminalError {
            return error
        } catch {
            return nil
        }
    }
}
