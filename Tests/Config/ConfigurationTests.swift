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

    /// Globální default se dá přepnout na automat — je to vědomé rozhodnutí uživatele,
    /// takže neznámé repo pak jede automaticky.
    @Test("Repo bez vlastního režimu bere globální")
    func takesTheGlobalMode() {
        var configuration = configuration()
        configuration.global.mode = .automatic

        #expect(configuration.resolved(for: cli).mode == .automatic)
    }

    /// Nejdražší chyba téhle dvojice: repo, u kterého jsem automat **vypnul**, se nesmí
    /// samo zapnout tím, že se přepne globální default.
    @Test("Vlastní manuální režim přebije globální automat")
    func repositoryModeWinsOverTheGlobalDefault() {
        var configuration = configuration([cli: RepositoryConfig(mode: .manual)])
        configuration.global.mode = .automatic

        #expect(configuration.resolved(for: cli).mode == .manual)
        #expect(configuration.resolved(for: vault).mode == .automatic)
    }

    // MARK: - Rozepsané hodnoty z editoru

    /// Řádek v editoru vzniká prázdný a konfigurace se ukládá dřív, než se dopíše. Skill
    /// bez jména by se pustil jako session, která nemá co dělat.
    @Test("Prázdný skill se přeskočí")
    func skipsABlankSkill() {
        var configuration = configuration()
        configuration.global.skills = ["code-review", "  ", ""]

        #expect(configuration.resolved(for: cli).skills == ["code-review"])
    }

    /// Prázdný **seznam** to nemění — ten je pořád vlastní odpověď „tady nereviewuj nic“.
    @Test("Prázdný seznam skillů zůstává prázdný, ne globální")
    func keepsAnEmptyListEmpty() {
        let resolved = configuration([cli: RepositoryConfig(skills: ["  "])]).resolved(for: cli)

        #expect(resolved.skills.isEmpty)
    }

    @Test("Prázdná kategorie se přeskočí")
    func skipsABlankCategory() {
        var configuration = configuration()
        configuration.global.blockingCategories = ["security", ""]

        #expect(configuration.resolved(for: cli).blockingCategories == ["security"])
    }

    /// Nejdražší z téhle trojice: `gh search prs` bez výrazu selže a **selhání jednoho
    /// zdroje zahazuje celý tik**, takže by kvůli rozepsanému řádku zmizel celý seznam PR.
    @Test("Zdroj bez dotazu se nepoužije")
    func skipsASourceWithoutAQuery() {
        var configuration = configuration()
        configuration.global.sources = [.reviewRequested, Source(name: "Rozepsaný", query: "  ")]

        #expect(configuration.activeSources == [.reviewRequested])
    }

    // MARK: - Zápis z okna nastavení

    @Test("Zápis nastavení repa se projeví")
    func writesARepositorySetting() {
        var configuration = configuration()

        configuration.setRepository(RepositoryConfig(mode: .automatic), for: cli)

        #expect(configuration.resolved(for: cli).mode == .automatic)
    }

    /// Prázdný a chybějící záznam znamenají totéž. Nechat prázdný v souboru znamená, že po
    /// proklikání okna nastavení zůstane v ručně čteném `config.json` hromada nul.
    @Test("Záznam, ze kterého nic nezbylo, se smaže")
    func dropsARepositorySettingThatSaysNothing() {
        var configuration = configuration([cli: RepositoryConfig(mode: .automatic, skills: ["go-review"])])

        configuration.setRepository(RepositoryConfig(), for: cli)

        #expect(configuration.repositories[cli] == nil)
        #expect(configuration.resolved(for: cli).mode == .manual)
    }

    /// Prázdná sada je vlastní odpověď („tady nereviewuj nic“), takže záznam přežít musí —
    /// i když je v něm jinak výchozí režim.
    @Test("Prázdný override se za prázdný záznam nepovažuje")
    func keepsAnEmptyOverride() {
        var configuration = configuration()

        configuration.setRepository(RepositoryConfig(skills: []), for: cli)

        #expect(configuration.repositories[cli] != nil)
        #expect(configuration.resolved(for: cli).skills.isEmpty)
    }

    /// Mazat záznam podle shody s globální hodnotou by při přepnutí globálního defaultu
    /// tiše zapnulo automat na repu, u kterého jsem ho vypnul.
    @Test("Vlastní manuální režim se nesmaže jako shodný s globálním")
    func keepsAnExplicitModeThatMatchesTheGlobalOne() {
        var configuration = configuration()

        configuration.setRepository(RepositoryConfig(mode: .manual), for: cli)
        configuration.global.mode = .automatic

        #expect(configuration.resolved(for: cli).mode == .manual)
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
        // Zapnout automat plošně musí být vědomé rozhodnutí, ne to, do čeho aplikace
        // spadne sama.
        #expect(standard.mode == .manual)
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

/// Tolerance musí platit i na úrovni repa, ne jen globálně. Override, který mění jen
/// skilly, je ta nejběžnější věc, kterou do souboru někdo napíše — a `keyNotFound`
/// na `mode` by kvůli němu zahodil **celou** konfiguraci včetně toho, co je správně.
@Suite("Configuration — tolerantní čtení repa")
struct RepositoryConfigDecodingTests {
    private func configuration(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    @Test("Override bez režimu projde a režim se bere globálně")
    func acceptsAnOverrideWithoutAMode() throws {
        var configuration = try self.configuration(#"{"repositories": {"cli/cli": {"skills": ["go-review"]}}}"#)
        configuration.global.mode = .automatic

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.resolved(for: repo).skills == ["go-review"])
        // Chybějící klíč znamená „ber globální“, ne „vnuť manual“.
        #expect(configuration.resolved(for: repo).mode == .automatic)
    }

    @Test("Prázdný override projde")
    func acceptsAnEmptyOverride() throws {
        let configuration = try self.configuration(#"{"repositories": {"cli/cli": {}}}"#)

        #expect(configuration.repositories.count == 1)
    }

    /// Rozbitá hodnota se srazí na `manual`, ne na globální default. Překlep v hodnotě,
    /// kterou se někdo pokoušel automat **vypnout**, ho nesmí nechat zapnutý.
    @Test("Neznámý režim nezahodí zbytek konfigurace a skončí na manuálním")
    func survivesAnUnknownMode() throws {
        var configuration = try self.configuration(#"{"repositories": {"cli/cli": {"mode": "poloautomat"}}}"#)
        configuration.global.mode = .automatic

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.resolved(for: repo).mode == .manual)
    }

    /// Totéž globálně: překlep nemá pustit reviewery na všechno.
    @Test("Neznámý globální režim skončí na manuálním")
    func survivesAnUnknownGlobalMode() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "poloautomat"}}"#)

        #expect(configuration.global.mode == .manual)
    }

    @Test("Globální režim ze souboru se přečte")
    func readsTheGlobalMode() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.mode == .automatic)
    }
}
