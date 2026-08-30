import Foundation
import Testing

@testable import PRism

/// Zápis důvěry ke složce do konfigurace Claude Code (#460).
///
/// **Nejcennější jsou tady tvrzení o tom, co se nestane**: rozbitá konfigurace se **nepřepíše**,
/// cizí klíče se **neztratí** a hotová důvěra se **nezapisuje znovu**. Píše se do souboru, který
/// aplikace nevlastní, takže chyba tady nestojí funkci, ale cizí práci.
@Suite("Důvěra ke složce v konfiguraci Claude Code (#460)")
struct WorkspaceTrustTests {
    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "prism-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let workspace = URL(filePath: "/Users/o/Library/Application Support/PRism")

    // MARK: - Co se zapíše

    @Test("Nová složka dostane důvěru")
    func afreshWorkspaceIsTrusted() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        try write(#"{"projects":{}}"#, to: config)

        try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)

        let projects = try #require(try read(config)["projects"] as? [String: Any])
        let entry = try #require(projects[workspace.path(percentEncoded: false)] as? [String: Any])
        #expect(entry["hasTrustDialogAccepted"] as? Bool == true)
    }

    /// **Klíčem je rozvinutá cesta** — změřeno, že nad `/tmp/x` hlásí `claude` workspace
    /// `/private/tmp/x`, takže záznam pod nerozvinutou cestou by se nikdy netrefil.
    @Test("Klíč je rozvinutá cesta, ne ta, kterou dostaneme")
    func thekeyIsTheResolvedPath() {
        #expect(ClaudeWorkspaceTrust.key(for: URL(filePath: "/tmp")) == "/private/tmp")
    }

    /// **Cizí klíče se nesmí ztratit** — je to konfigurace, kterou aplikace nevlastní, a všechno
    /// ostatní v ní patří někomu jinému.
    @Test("Zbytek konfigurace zůstane, jak byl")
    func everythingElseSurvives() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        try write(
            """
            {"hasCompletedOnboarding":true,"anonymousId":"abc",
             "projects":{"/Users/o/jine":{"allowedTools":["Read"],"hasTrustDialogAccepted":false}}}
            """,
            to: config
        )

        try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)

        let root = try read(config)
        #expect(root["hasCompletedOnboarding"] as? Bool == true)
        #expect(root["anonymousId"] as? String == "abc")
        let projects = try #require(root["projects"] as? [String: Any])
        let other = try #require(projects["/Users/o/jine"] as? [String: Any])
        #expect(other["allowedTools"] as? [String] == ["Read"])
        // Cizí projekt si drží svoji odpověď — nezapisujeme důvěru za uživatele nikde jinde.
        #expect(other["hasTrustDialogAccepted"] as? Bool == false)
        #expect(projects.count == 2)
    }

    /// Hotová důvěra se **nepřepisuje**: běžný případ je tím pádem čisté čtení, a to je jediná
    /// ochrana proti souběžnému zápisu `claude` samotného, kterou máme.
    @Test("Zapsaná důvěra se nezapisuje znovu")
    func analreadyTrustedWorkspaceIsNotRewritten() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        let key = workspace.path(percentEncoded: false)
        try write(#"{"projects":{"\#(key)":{"hasTrustDialogAccepted":true,"neco":1}}}"#, to: config)
        let before = try #require(
            try FileManager.default.attributesOfItem(atPath: config.path())[.modificationDate] as? Date
        )

        try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)

        let after = try #require(
            try FileManager.default.attributesOfItem(atPath: config.path())[.modificationDate] as? Date
        )
        #expect(before == after, "soubor se přepsal, i když se nic měnit nemělo")
    }

    /// **Zapsané `false` na naší cestě se přepsat smí** (#479), a je to rozhodnutí, ne nedopatření:
    /// `claude` si tu hodnotu zapisuje **sám** při každém běhu nad složkou, kterou v konfiguraci
    /// ještě nemá (změřeno) — není to tedy odpověď člověka „nevěřím“, ale výchozí hodnota záznamu.
    /// A je to složka v naší cache, kterou aplikace vyrobila.
    ///
    /// **Zbytek toho záznamu přitom zůstane**: přepisuje se jedna hodnota, ne celý projekt.
    @Test("Zapsané false na naší cestě se přepíše, zbytek záznamu zůstane")
    func anexplicitFalseOnOurOwnPathIsOverwritten() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        let key = workspace.path(percentEncoded: false)
        try write(
            #"{"projects":{"\#(key)":{"hasTrustDialogAccepted":false,"allowedTools":["Read"]}}}"#,
            to: config
        )

        try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)

        let projects = try #require(try read(config)["projects"] as? [String: Any])
        let entry = try #require(projects[key] as? [String: Any])
        #expect(entry["hasTrustDialogAccepted"] as? Bool == true)
        #expect(entry["allowedTools"] as? [String] == ["Read"])
    }

    /// **Práva `0600` se zápisem neztratí** — je to soubor s přihlašovacími údaji cizího nástroje
    /// a rozšířit k němu přístup by bylo horší než ten dialog, který se tím spoří. Drží to
    /// `replaceItemAt`, které atributy původního souboru přenese; jde tedy o tvrzení o **atomickém
    /// zápisu**, ne o zvlášť nastavovaná práva.
    ///
    /// **A dočasný soubor po sobě nezůstane**: leží v domovské složce vedle konfigurace, takže
    /// zapomenutý by se tam hromadil jeden na každý zápis. Při úspěchu ho `replaceItemAt`
    /// spotřebuje — ověřuje se to proto, že je to jediná cesta, kterou se pozná, že se spotřeboval.
    @Test("Práva 0600 přežijí zápis a dočasný soubor po sobě nezůstane")
    func thefilePermissionsAndTemporaryFileSurviveTheWrite() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        try write(#"{"projects":{}}"#, to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)

        try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)

        let attributes = try FileManager.default.attributesOfItem(atPath: config.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let left = try FileManager.default.contentsOfDirectory(atPath: home.path)
        #expect(left == [".claude.json"], "v domovské složce zbylo \(left)")
    }

    // MARK: - Co se nepřepíše

    /// **Rozbitá konfigurace se nepřepisuje.** Ztráta je jeden dialog navíc; přepsaný soubor by
    /// byla ztráta cizí práce.
    @Test("Konfigurace, které nerozumíme, se nedotkneme")
    func abrokenConfigurationIsLeftAlone() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        let original = "{ tohle není JSON"
        try write(original, to: config)

        await #expect(throws: WorkspaceTrustError.configurationUnreadable) {
            try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)
        }
        #expect(try String(contentsOf: config, encoding: .utf8) == original)
    }

    /// Pole JSON je platný JSON, ale ne konfigurace — a přepsat ho objektem by ji **zahodilo**.
    @Test("Konfigurace, která není objekt, se taky nedotkneme")
    func anonObjectConfigurationIsLeftAlone() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")
        try write("[1, 2, 3]", to: config)

        await #expect(throws: WorkspaceTrustError.configurationUnreadable) {
            try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)
        }
        #expect(try String(contentsOf: config, encoding: .utf8) == "[1, 2, 3]")
    }

    /// **Chybějící soubor se nezakládá.** `claude` na tomhle stroji ještě neběžel, takže si ho
    /// založí sám a při té příležitosti se zeptá — jeden dialog je levnější než konfigurace,
    /// kterou jsme vymysleli za něj.
    @Test("Chybějící konfigurace se nezakládá")
    func amissingConfigurationIsNotCreated() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appending(path: ".claude.json")

        await #expect(throws: WorkspaceTrustError.configurationMissing) {
            try await ClaudeWorkspaceTrust(configuration: config).trust(workspace)
        }
        #expect(!FileManager.default.fileExists(atPath: config.path()))
    }
}
