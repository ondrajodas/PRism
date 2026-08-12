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

    /// Kdy se souboru naposled sáhlo — z toho se pozná, že se **nezapsalo**.
    private func modified(in workspace: TemporaryDirectory) throws -> Date {
        let url = CacheLayout(root: workspace.url).configFile
        return try #require(try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date)
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

    /// Restart nesmí volbu ztratit: přežívá v souboru, ne v paměti okna. **Přepíná se railem**,
    /// tedy tou cestou, kterou má člověk pod rukou.
    @Test("Volba z railu přežije restart aplikace")
    func survivesARestart() async throws {
        let workspace = try TemporaryDirectory()
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)
        await store.reloadConfiguration()
        await store.setAppearance(.light)

        let restartTarget = FakeAppearanceTarget()
        let restarted = self.store(in: workspace, appearance: restartTarget)
        await restarted.reloadConfiguration()

        #expect(restarted.configuration.global.appearance == .light)
        #expect(restartTarget.applied == [.light])
    }

    /// Přepnutí z railu se musí projevit **hned**, ne po restartu — celý smysl toho, že `Palette`
    /// jde přes dynamického poskytovatele.
    @Test("Přepnutí z railu přepne vzhled hned")
    func appliesASwitchFromTheRail() async throws {
        let workspace = try TemporaryDirectory()
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)
        await store.reloadConfiguration()

        await store.setAppearance(.dark)
        await store.setAppearance(.system)

        // První je z načtení prázdné konfigurace, tedy výchozí `system`.
        #expect(target.applied == [.system, .dark, .system])
        #expect(store.appearanceFailure == nil)
    }

    /// Nabídka v railu hlásí i výběr toho, co už platí — a to **nesmí** nic udělat: zápis beze
    /// změny by přepsal ručně editovaný soubor a `apply(_:)` by proběhl pro nic.
    @Test("Volba, která už platí, nic nepřepíše")
    func ignoresAChoiceThatAlreadyHolds() async throws {
        let workspace = try TemporaryDirectory()
        try await write(configuration(.dark), to: workspace)
        let target = FakeAppearanceTarget()
        let store = store(in: workspace, appearance: target)
        await store.reloadConfiguration()
        let stamp = try modified(in: workspace)

        await store.setAppearance(.dark)

        #expect(target.applied == [.dark])
        #expect(try modified(in: workspace) == stamp)
    }

    /// Neuložená volba **nesmí projít tiše**: vzhled se nepřepnul (uplatňuje se až po úspěšném
    /// zápisu), takže bez hlášky vypadá rail jako rozbitý — klik, a nic.
    @Test("Selhání zápisu je vidět a vzhled se nepřepne")
    func surfacesAFailedWrite() async throws {
        let target = FakeAppearanceTarget()
        // Store bez `ConfigStore` nemá kam zapsat — `updateConfiguration` na to má vlastní chybu.
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            time: FakeTimeSource(),
            appearance: target
        )

        await store.setAppearance(.dark)

        #expect(target.applied.isEmpty)
        #expect(store.appearanceFailure?.isEmpty == false)
        #expect(store.configuration.global.appearance == .system)
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
