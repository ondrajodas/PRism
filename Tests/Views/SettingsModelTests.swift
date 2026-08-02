import Foundation
import Testing

@testable import PRism

/// Rozepsané nastavení a jeho cesta na disk. Zpoždění před zápisem se testuje přes
/// `FakeTimeSource`, takže v reálném čase se nečeká vůbec.
@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {
    /// Sbírá, co se pokusilo uložit. `@MainActor` třída, protože model je taky.
    @MainActor
    final class Recorder {
        var written: [Configuration] = []
        var failure: (any Error)?

        func write(_ configuration: Configuration) throws {
            if let failure { throw failure }
            written.append(configuration)
        }
    }

    /// Uspání, které samo neskončí — probudí ho až zrušení. Bez něj by v testech na
    /// `flush()` závodilo odložené uložení s tím okamžitým a nešlo by poznat, které
    /// z nich zapsalo.
    struct BlockingTime: TimeSource {
        var now: Date { Date(timeIntervalSince1970: 1_000_000) }

        func sleep(for duration: Duration) async throws {
            try await Task.sleep(for: .seconds(3600))
        }
    }

    private func model(
        _ configuration: Configuration = .standard,
        time: any TimeSource,
        recorder: Recorder
    ) -> SettingsModel {
        SettingsModel(configuration: configuration, time: time, delay: .milliseconds(600)) { configuration in
            try recorder.write(configuration)
        }
    }

    /// Čeká, dokud se něco nezapíše. Točí se přes `Task.yield()`, ne přes continuation —
    /// test, který se nedočká, uvízne, a to je srozumitelnější než náhodné padání.
    private func waitForWrite(_ recorder: Recorder, count: Int) async {
        while recorder.written.count < count {
            await Task.yield()
        }
    }

    @Test("Změna se uloží")
    func savesAnEdit() async {
        let recorder = Recorder()
        let settings = model(time: FakeTimeSource(), recorder: recorder)

        settings.draft.global.skills = ["go-review"]
        await waitForWrite(recorder, count: 1)

        #expect(recorder.written.map(\.global.skills) == [["go-review"]])
        #expect(settings.saveFailure == nil)
        #expect(settings.lastSaved != nil)
    }

    /// Psaní v textovém poli je řada změn po znacích. Zápis na každou z nich znamená sáhnout
    /// na disk desetkrát za slovo — a uložit přitom mezistavy, které nikdo nechtěl.
    @Test("Rychlé změny za sebou uloží jen tu poslední")
    func collapsesRapidEdits() async {
        let recorder = Recorder()
        let settings = model(time: FakeTimeSource(), recorder: recorder)

        settings.draft.global.skills = ["c"]
        settings.draft.global.skills = ["co"]
        settings.draft.global.skills = ["code-review"]
        await waitForWrite(recorder, count: 1)

        #expect(recorder.written.map(\.global.skills) == [["code-review"]])
    }

    /// Soubor jde pořád editovat ručně. Když se změní jinde, formulář se musí srovnat.
    @Test("Změna zvenčí přepíše formulář")
    func adoptsAChangeFromOutside() async {
        let recorder = Recorder()
        let settings = model(time: FakeTimeSource(), recorder: recorder)
        var outside = Configuration.standard
        outside.global.pollIntervalSeconds = 30

        settings.sync(with: outside)

        #expect(settings.draft.global.pollIntervalSeconds == 30)
        // Srovnání není editace — nesmí se vracet na disk.
        #expect(recorder.written.isEmpty)
    }

    /// Vlastní zápis se do store propíše a odtud se vrátí zpátky do `sync`. Kdyby ho model
    /// nepoznal jako svůj, přepsal by formulář pokaždé, když uložení doběhne.
    @Test("Vlastní uložení formulář nepřepíše")
    func ignoresItsOwnSave() async {
        let recorder = Recorder()
        let settings = model(time: FakeTimeSource(), recorder: recorder)

        settings.draft.global.skills = ["go-review"]
        await waitForWrite(recorder, count: 1)
        settings.sync(with: recorder.written[0])
        settings.draft.global.pollIntervalSeconds = 15
        await waitForWrite(recorder, count: 2)

        #expect(recorder.written[1].global.skills == ["go-review"])
        #expect(recorder.written[1].global.pollIntervalSeconds == 15)
    }

    /// Zavřít okno jde dřív, než zpoždění doběhne.
    @Test("Zavření okna uloží rozepsanou změnu hned")
    func flushSavesWithoutWaiting() async {
        let recorder = Recorder()
        // Uspání, ze kterého se nikdo neprobudí — kdyby `flush` čekal na ně, test uvízne.
        let settings = model(time: BlockingTime(), recorder: recorder)

        settings.draft.global.skills = ["go-review"]
        await settings.flush()

        #expect(recorder.written.map(\.global.skills) == [["go-review"]])
    }

    @Test("Bez změny se při zavření nic nezapisuje")
    func flushWritesNothingWhenNothingChanged() async {
        let recorder = Recorder()
        let settings = model(time: FakeTimeSource(), recorder: recorder)

        await settings.flush()

        #expect(recorder.written.isEmpty)
    }

    /// Neuložená změna, o které se mlčí, vypadá jako uložená — a po restartu je pryč.
    @Test("Selhání zápisu je vidět")
    func surfacesAFailedWrite() async {
        let recorder = Recorder()
        recorder.failure = CocoaError(.fileWriteNoPermission)
        let settings = model(time: BlockingTime(), recorder: recorder)

        settings.draft.global.skills = ["go-review"]
        await settings.flush()

        #expect(settings.saveFailure?.isEmpty == false)
        #expect(settings.lastSaved == nil)
    }
}
