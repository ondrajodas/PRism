import Foundation
import Testing

@testable import PRism

/// Načítání `config.json`. Soubor se edituje ručně, takže musí unést i to, že v něm něco
/// chybí — a když je rozbitý, nesmí to aplikaci položit.
@Suite("ConfigStore")
struct ConfigStoreTests {
    private func store(_ workspace: TemporaryDirectory) -> ConfigStore {
        ConfigStore(layout: CacheLayout(root: workspace.url))
    }

    private func write(_ json: String, to workspace: TemporaryDirectory) throws {
        let layout = CacheLayout(root: workspace.url)
        try FileManager.default.createDirectory(at: workspace.url, withIntermediateDirectories: true)
        try json.write(to: layout.configFile, atomically: true, encoding: .utf8)
    }

    /// První spuštění: soubor není. Aplikace poběží na výchozích hodnotách a soubor se
    /// založí, aby bylo co editovat.
    @Test("Chybějící soubor dá výchozí hodnoty a založí se")
    func createsAMissingFile() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)

        let loaded = await store(workspace).load()

        #expect(loaded.configuration == .standard)
        #expect(loaded.failure == nil)
        #expect(FileManager.default.fileExists(atPath: layout.configFile.path(percentEncoded: false)))
    }

    @Test("Uložená konfigurace se přečte zpátky")
    func readsWhatItWrote() async throws {
        let workspace = try TemporaryDirectory()
        var configuration = Configuration.standard
        configuration.global.skills = ["code-review", "security"]
        configuration.repositories = [RepoID(owner: "cli", name: "cli"): RepositoryConfig(mode: .automatic)]

        try await store(workspace).save(configuration)
        let loaded = await store(workspace).load()

        #expect(loaded.configuration == configuration)
    }

    /// Rozbitý soubor **nesmí** aplikaci položit ani tiše přejít: běží se na defaultech
    /// a je vidět proč, jinak by uživatel hledal, proč mu nastavení nefunguje.
    @Test("Rozbitý JSON nechá aplikaci běžet, ale je vidět")
    func survivesBrokenJSON() async throws {
        let workspace = try TemporaryDirectory()
        try write("{tohle není json", to: workspace)

        let loaded = await store(workspace).load()

        #expect(loaded.configuration == .standard)
        #expect(loaded.failure?.isEmpty == false)
    }

    /// Rozbitý soubor se **nepřepisuje**. Uživatel ho psal a přijít o něj kvůli chybějící
    /// čárce by bylo horší než ta chyba sama.
    @Test("Rozbitý soubor se nepřepíše výchozími hodnotami")
    func neverOverwritesABrokenFile() async throws {
        let workspace = try TemporaryDirectory()
        try write("{tohle není json", to: workspace)

        _ = await store(workspace).load()

        let onDisk = try String(contentsOf: CacheLayout(root: workspace.url).configFile, encoding: .utf8)
        #expect(onDisk == "{tohle není json")
    }

    /// Soubor, který **existuje, ale nejde přečíst**, není totéž co chybějící. Brát ho
    /// jako první spuštění by znamenalo přepsat ho výchozími hodnotami — tedy zahodit
    /// nastavení kvůli chybě, o které se uživatel ani nedozví.
    @Test("Nečitelný soubor se nepovažuje za chybějící")
    func neverMistakesAnUnreadableFileForAMissingOne() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        // Složka na místě souboru: existuje, ale přečíst se nedá.
        try FileManager.default.createDirectory(at: layout.configFile, withIntermediateDirectories: true)

        let loaded = await store(workspace).load()

        #expect(loaded.configuration == .standard)
        #expect(loaded.failure?.isEmpty == false)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: layout.configFile.path(percentEncoded: false),
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
    }

    /// Ručně psaný soubor málokdy obsahuje všechno. Chybějící klíč znamená „ber výchozí“,
    /// ne „zahoď celou konfiguraci“.
    @Test("Chybějící klíče se doplní výchozími hodnotami")
    func fillsInMissingKeys() async throws {
        let workspace = try TemporaryDirectory()
        try write(#"{"repositories": {"cli/cli": {"mode": "automatic"}}}"#, to: workspace)

        let loaded = await store(workspace).load()

        #expect(loaded.failure == nil)
        #expect(loaded.configuration.global == Configuration.standard.global)
        #expect(loaded.configuration.resolved(for: RepoID(owner: "cli", name: "cli")).mode == .automatic)
    }

    @Test("Chybějící klíč uvnitř globální části se doplní taky")
    func fillsInMissingGlobalKeys() async throws {
        let workspace = try TemporaryDirectory()
        try write(#"{"global": {"skills": ["security"]}}"#, to: workspace)

        let loaded = await store(workspace).load()

        #expect(loaded.configuration.global.skills == ["security"])
        #expect(loaded.configuration.global.pollIntervalSeconds == 60)
        #expect(loaded.configuration.global.maxConcurrentReviews == 3)
    }
}
