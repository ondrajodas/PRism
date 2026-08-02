import Foundation
import Testing

@testable import PRism

/// Konfigurace se edituje v souboru, takže se musí dát načíst bez restartu.
@Suite("AppStore — konfigurace")
@MainActor
struct AppStoreConfigurationTests {
    private func write(_ configuration: Configuration, to workspace: TemporaryDirectory) async throws {
        try await ConfigStore(layout: CacheLayout(root: workspace.url)).save(configuration)
    }

    private func store(_ gateway: FakeGitHubGateway, in workspace: TemporaryDirectory) -> AppStore {
        AppStore(
            gateway: gateway,
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource()
        )
    }

    @Test("Zdroje se berou z konfigurace")
    func asksTheSourcesFromConfiguration() async throws {
        let workspace = try TemporaryDirectory()
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me")]
        try await write(configuration, to: workspace)
        let gateway = FakeGitHubGateway(always: .success([]))
        let store = store(gateway, in: workspace)

        await store.reloadConfiguration()
        await store.refresh()

        #expect(gateway.queries == ["review-requested:@me"])
    }

    @Test("Změna souboru se projeví bez restartu")
    func picksUpChangesWithoutARestart() async throws {
        let workspace = try TemporaryDirectory()
        let cli = RepoID(owner: "cli", name: "cli")
        let store = store(FakeGitHubGateway(always: .success([])), in: workspace)
        #expect(store.resolved(for: cli).mode == .manual)

        var changed = Configuration.standard
        changed.repositories = [cli: RepositoryConfig(mode: .automatic, skills: ["go-review"])]
        try await write(changed, to: workspace)
        await store.reloadConfiguration()

        #expect(store.resolved(for: cli).mode == .automatic)
        #expect(store.reviewSkills(for: cli) == ["go-review"])
    }

    /// Okno nastavení zapisuje do téhož souboru, který jde editovat ručně — a změna se
    /// musí projevit bez restartu, stejně jako když soubor přepíše editor.
    @Test("Uložení z okna nastavení se projeví a přežije restart")
    func savesAndAppliesAnEditFromTheSettingsWindow() async throws {
        let workspace = try TemporaryDirectory()
        let cli = RepoID(owner: "cli", name: "cli")
        let gateway = FakeGitHubGateway(always: .success([]))
        let store = store(gateway, in: workspace)
        await store.reloadConfiguration()

        var edited = Configuration.standard
        edited.global.sources = [Source(name: "Moje", query: "author:@me")]
        edited.repositories = [cli: RepositoryConfig(mode: .automatic, skills: ["go-review"])]
        try await store.updateConfiguration(edited)

        #expect(store.resolved(for: cli).mode == .automatic)
        await store.refresh()
        #expect(gateway.queries == ["author:@me"])

        // Restart: nový store nad toutéž složkou musí najít totéž.
        let restarted = self.store(FakeGitHubGateway(always: .success([])), in: workspace)
        await restarted.reloadConfiguration()
        #expect(restarted.configuration == edited)
    }

    /// Neuložené nastavení, o kterém se mlčí, vypadá v okně jako uložené — a po restartu
    /// je pryč.
    @Test("Selhání zápisu letí ven")
    func propagatesAFailedWrite() async throws {
        let workspace = try TemporaryDirectory()
        // Soubor na místě kořene cache: `createDirectory` pod ním selže.
        try Data().write(to: workspace.url.appending(path: "obsazeno"))
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url.appending(path: "obsazeno"))),
            time: FakeTimeSource()
        )

        await #expect(throws: (any Error).self) {
            try await store.updateConfiguration(.standard)
        }
    }

    /// Store bez `ConfigStore` staví jen testy, ale okno nastavení nad ním postavit jde —
    /// a tiché „uložil jsem“ nad něčím, co nikam neodešlo, je horší než chyba.
    @Test("Store bez souboru nastavení uložení neschová")
    func refusesToSaveWithoutAStore() async throws {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())

        await #expect(throws: ConfigurationError.noStore) {
            try await store.updateConfiguration(.standard)
        }
    }

    /// Rozbitý soubor nesmí aplikaci položit ani projít tiše.
    @Test("Rozbitá konfigurace je vidět a běží se na výchozích")
    func surfacesABrokenConfiguration() async throws {
        let workspace = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: workspace.url, withIntermediateDirectories: true)
        try "{tohle není json".write(
            to: CacheLayout(root: workspace.url).configFile,
            atomically: true,
            encoding: .utf8
        )
        let store = store(FakeGitHubGateway(always: .success([])), in: workspace)

        await store.reloadConfiguration()

        #expect(store.configurationFailure?.isEmpty == false)
        #expect(store.configuration == .standard)
    }
}
