import Foundation
import Testing

@testable import PRism

/// Pohled na diff: výchozí je z nastavení, přepínač v liště je odchylka do zavření aplikace.
///
/// Stav drží store, ne view — `PullRequestDetailView` si SwiftUI mezi pull requesty ponechá,
/// takže `@State` by odchylku zahodilo přestavěním stromu.
@Suite("AppStore — pohled na diff")
@MainActor
struct AppStoreDiffLayoutTests {
    private func store(_ layout: DiffLayout = .unified) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.diffLayout = layout
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource()
        )
    }

    /// Store, který umí uložit nastavení — na tom stojí testy „změna se projeví bez restartu“.
    /// Bez `ConfigStore` skončí `updateConfiguration` chybou `noStore` a nic by se nepropsalo.
    private func store(in workspace: TemporaryDirectory, layout: DiffLayout = .unified) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.diffLayout = layout
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource()
        )
    }

    private func configuration(_ layout: DiffLayout) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.diffLayout = layout
        return configuration
    }

    @Test("Bez odchylky platí hodnota z nastavení")
    func takesTheConfiguredLayout() {
        #expect(store().diffLayout == .unified)
        #expect(store(.split).diffLayout == .split)
    }

    @Test("Přepnutí v liště přebije nastavení")
    func overridesTheConfiguredLayout() {
        let store = store()

        store.setDiffLayout(.split)

        #expect(store.diffLayout == .split)
    }

    /// Pohled je způsob čtení, ne údaj o PR — přepnutím na jiný pull request se nemá vracet.
    /// Store ho proto drží jednou, ne per PR; kdyby to přestalo platit, tenhle test to
    /// nechytne (mapa žádná není), ale řekne aspoň to, že se odchylka drží dál.
    @Test("Odchylka drží, dokud se nepřepne zpátky")
    func keepsTheOverride() {
        let store = store()

        store.setDiffLayout(.split)
        store.setDiffLayout(.unified)

        #expect(store.diffLayout == .unified)
    }

    /// Tatáž úvaha jako u `Configuration.setRepository`, kde se maže podle prázdnosti a ne
    /// podle shody s globální hodnotou: kdo si pohled otočil sám, má ho podržet i po změně
    /// v nastavení.
    @Test("Odchylka shodná s nastavením přežije změnu nastavení")
    func keepsAnOverrideThatMatchesTheSetting() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(in: workspace, layout: .unified)

        store.setDiffLayout(.unified)
        try await store.updateConfiguration(configuration(.split))

        #expect(store.diffLayout == .unified)
    }

    /// Změna v nastavení se musí projevit **bez restartu** — a projeví se, dokud si pohled
    /// nikdo neotočil v liště.
    @Test("Změna nastavení se projeví bez odchylky")
    func followsTheSettingWithoutAnOverride() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(in: workspace, layout: .unified)

        try await store.updateConfiguration(configuration(.split))

        #expect(store.diffLayout == .split)
    }
}
