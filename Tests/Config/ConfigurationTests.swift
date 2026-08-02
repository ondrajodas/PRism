import Foundation
import Testing

@testable import PRism

/// Konfigurace ve dvou úrovních: globální default a override per repo.
@Suite("Configuration")
struct ConfigurationTests {
    private let cli = RepoID(owner: "cli", name: "cli")
    private let vault = RepoID(owner: "keboola", name: "vault")

    private func configuration(_ repositories: [RepoID: RepositoryConfig] = [:]) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.skills = ["code-review", "security"]
        configuration.global.blockingCategories = ["correctness", "data-loss"]
        configuration.repositories = repositories
        return configuration
    }

    // MARK: - Resolver

    /// Repo, o kterém konfigurace nic neví, musí dostat rozumné hodnoty — a hlavně
    /// **manuální režim**: neznámé repo nesmí bez dozoru spálit panel Claude sessions.
    @Test("Neznámé repo dostane globální hodnoty a manuální režim")
    func fallsBackToGlobalForAnUnknownRepository() {
        let resolved = configuration().resolved(for: cli)

        #expect(resolved.mode == .manual)
        #expect(resolved.skills == ["code-review", "security"])
        #expect(resolved.blockingCategories == ["correctness", "data-loss"])
    }

    @Test("Automatický režim se zapíná per repo")
    func turnsOnAutomaticModePerRepository() {
        let resolved = configuration([cli: RepositoryConfig(mode: .automatic)]).resolved(for: cli)

        #expect(resolved.mode == .automatic)
    }

    /// Override **nahrazuje**, neslučuje: smysl je vyhodit PHP skilly na Go repu, ne k nim
    /// další přidat.
    @Test("Skilly per repo nahrazují globální sadu")
    func replacesSkillsPerRepository() {
        let resolved = configuration([cli: RepositoryConfig(skills: ["go-review"])]).resolved(for: cli)

        #expect(resolved.skills == ["go-review"])
        #expect(resolved.blockingCategories == ["correctness", "data-loss"])
    }

    /// Prázdný seznam je vlastní odpověď — „na tomhle repu nechci reviewovat nic“ se musí
    /// dát říct jinak než smazáním klíče, které znamená „ber globální“.
    @Test("Prázdná sada skillů vypne review, nezdědí globální")
    func treatsAnEmptySkillListAsDeliberate() {
        let resolved = configuration([cli: RepositoryConfig(skills: [])]).resolved(for: cli)

        #expect(resolved.skills.isEmpty)
    }

    @Test("Blokující kategorie jdou přebít taky")
    func replacesBlockingCategoriesPerRepository() {
        let resolved = configuration([cli: RepositoryConfig(blockingCategories: ["security"])]).resolved(for: cli)

        #expect(resolved.blockingCategories == ["security"])
    }

    @Test("Nastavení jednoho repa nesahá na jiné")
    func keepsRepositoriesApart() {
        let configuration = configuration([cli: RepositoryConfig(mode: .automatic, skills: ["go-review"])])

        #expect(configuration.resolved(for: vault).mode == .manual)
        #expect(configuration.resolved(for: vault).skills == ["code-review", "security"])
    }

    // MARK: - Výchozí hodnoty

    /// Výchozí konfigurace musí odpovídat tomu, co bylo do teď zadrátované v kódu — jinak
    /// by se aplikace po zavedení konfigurace začala chovat jinak.
    @Test("Výchozí hodnoty odpovídají dosavadním konstantám")
    func matchesTheConstantsItReplaces() {
        let standard = Configuration.standard.global

        #expect(standard.sources == [.reviewRequested])
        #expect(standard.skills == ["code-review"])
        #expect(Set(standard.blockingCategories) == Policy.defaultBlockingCategories)
        #expect(standard.pollIntervalSeconds == 60)
        #expect(standard.maxConcurrentReviews == 3)
        #expect(standard.cacheBudgetMegabytes == 10 * 1024)
        #expect(standard.model == nil)
    }

    // MARK: - Tvar na disku

    @Test("Konfigurace přežije cestu na disk a zpátky")
    func survivesARoundTrip() throws {
        let original = configuration([cli: RepositoryConfig(mode: .automatic, skills: ["go-review"])])

        #expect(try roundTrip(original) == original)
    }

    /// Soubor se edituje ručně, takže klíč repozitáře musí být čitelný `owner/repo`,
    /// ne objekt s poli.
    @Test("Repozitáře jsou v JSONu klíčované owner/repo")
    func keysRepositoriesByTheirName() throws {
        let data = try JSONEncoder().encode(configuration([cli: RepositoryConfig(mode: .automatic)]))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let repositories = try #require(json["repositories"] as? [String: Any])
        #expect(repositories.keys.contains("cli/cli"))
    }
}
