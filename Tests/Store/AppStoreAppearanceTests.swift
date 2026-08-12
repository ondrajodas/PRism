import AppKit
import Foundation
import Testing

@testable import PRism

/// Cesta volby vzhledu z `config.json` do běžící aplikace (#278).
///
/// Jde **jedinou** cestou — `AppStore.apply(_:)` —, takže se tady měří obojí: načtení z disku
/// (start aplikace, ruční editace souboru) i uložení z okna nastavení. Kdyby to view dělalo samo,
/// nepřepnulo by se okno, které zrovna není otevřené.
@Suite("AppStore — vzhled")
@MainActor
struct AppStoreAppearanceTests {
    private func write(_ configuration: Configuration, to workspace: TemporaryDirectory) async throws {
        try await ConfigStore(layout: CacheLayout(root: workspace.url)).save(configuration)
    }

    private func store(in workspace: TemporaryDirectory, appearance: FakeAppearanceTarget) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource(),
            appearance: appearance
        )
    }

    private func configuration(_ mode: AppearanceMode) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.appearance = mode
        return configuration
    }

    @Test("Volba ze souboru se uplatní při načtení")
    func appliesTheStoredModeOnLoad() async throws {
        let workspace = try TemporaryDirectory()
        try await write(configuration(.dark), to: workspace)
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)

        await store.reloadConfiguration()

        #expect(store.configuration.global.appearance == .dark)
        #expect(target.applied == [.dark])
    }

    /// Restart nesmí volbu ztratit: přežívá v souboru, ne v paměti okna.
    @Test("Volba přežije restart aplikace")
    func survivesARestart() async throws {
        let workspace = try TemporaryDirectory()
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)
        await store.reloadConfiguration()
        try await store.updateConfiguration(configuration(.light))

        let restartTarget = FakeAppearanceTarget()
        let restarted = self.store(in: workspace, appearance: restartTarget)
        await restarted.reloadConfiguration()

        #expect(restarted.configuration.global.appearance == .light)
        #expect(restartTarget.applied == [.light])
    }

    /// Uložení z okna nastavení se musí projevit **hned**, ne po restartu — celý smysl toho, že
    /// `Palette` jde přes dynamického poskytovatele.
    @Test("Uložení z okna nastavení přepne vzhled hned")
    func appliesAnEditFromTheSettingsWindow() async throws {
        let workspace = try TemporaryDirectory()
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)
        await store.reloadConfiguration()

        try await store.updateConfiguration(configuration(.dark))
        try await store.updateConfiguration(configuration(.system))

        // První je z načtení prázdné konfigurace, tedy výchozí `system`.
        #expect(target.applied == [.system, .dark, .system])
    }

    /// Rozbitá hodnota v souboru znamená **podle systému**, ne pád a ne vynucený režim.
    @Test("Rozbitá hodnota v souboru skončí na podle systému")
    func fallsBackToTheSystemModeOnABrokenValue() async throws {
        let workspace = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.url, withIntermediateDirectories: true)
        try #"{"global": {"appearance": "kontrastní", "mode": "automatic"}}"#.write(
            to: CacheLayout(root: workspace.url).configFile,
            atomically: true,
            encoding: .utf8
        )
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)

        await store.reloadConfiguration()

        #expect(target.applied == [.system])
        // Zbytek souboru překlep nezahodil — je to tolerantní čtení, ne zámek.
        #expect(store.configuration.global.mode == .automatic)
        #expect(store.configurationFailure == nil)
    }

    /// Store bez cíle (tedy tak, jak ho staví testy) nesmí sahat na `NSApp` — jinak by jeden test
    /// přebarvil hostitele testů a render sondy by měřily jiný režim, než o který si řekly.
    ///
    /// Tvrdí se to na **skutečném `NSApp`**: konfigurace se čte s vynuceným tmavým a vzhled
    /// hostitele se u toho nesmí pohnout. Jen se čte, nic se nenastavuje.
    @Test("Bez cíle se na NSApp nesáhne")
    func leavesTheApplicationAloneWithoutATarget() async throws {
        let workspace = try TemporaryDirectory()
        try await write(configuration(.dark), to: workspace)
        let untouched = NSApp.appearance
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource()
        )

        await store.reloadConfiguration()

        // Volba se přečte, jen ji nemá kdo uplatnit.
        #expect(store.configuration.global.appearance == .dark)
        #expect(NSApp.appearance === untouched)
    }
}
