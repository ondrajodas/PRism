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
