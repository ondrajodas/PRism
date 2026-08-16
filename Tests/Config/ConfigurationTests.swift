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

    // MARK: - Jazyk nálezů

    /// Okno je české, takže nálezy vedle českých popisků nemají chodit anglicky.
    @Test("Výchozí jazyk nálezů je čeština")
    func defaultsToCzechFindings() {
        #expect(configuration().resolved(for: cli).findingsLanguage == .czech)
    }

    /// U firemního repa s mezinárodním týmem dává smysl angličtina, i když je zbytek
    /// fronty český.
    @Test("Jazyk nálezů jde přebít per repo")
    func overridesTheFindingsLanguagePerRepository() {
        let configuration = configuration([cli: RepositoryConfig(findingsLanguage: .english)])

        #expect(configuration.resolved(for: cli).findingsLanguage == .english)
        #expect(configuration.resolved(for: vault).findingsLanguage == .czech)
    }

    @Test("Globální jazyk platí pro repo, které si o jiný neřeklo")
    func takesTheGlobalFindingsLanguage() {
        var configuration = configuration()
        configuration.global.findingsLanguage = .english

        #expect(configuration.resolved(for: cli).findingsLanguage == .english)
    }

    /// Stejná past jako u režimu: mazat záznam podle shody s globální hodnotou by repo,
    /// u kterého jsem si o češtinu **řekl**, přepnulo přepnutím globálního defaultu.
    @Test("Vlastní jazyk se nesmaže jako shodný s globálním")
    func keepsAnExplicitLanguageThatMatchesTheGlobalOne() {
        var configuration = configuration()

        configuration.setRepository(RepositoryConfig(findingsLanguage: .czech), for: cli)
        configuration.global.findingsLanguage = .english

        #expect(configuration.resolved(for: cli).findingsLanguage == .czech)
    }

    // MARK: - Sada podle jazyka

    private func withLanguages(_ map: [ProjectLanguage: [String]]) -> Configuration {
        var configuration = configuration()
        configuration.global.skillsByLanguage = map
        return configuration
    }

    @Test("Rozpoznaný jazyk určí sadu skillů")
    func picksSkillsForADetectedLanguage() {
        let configuration = withLanguages([.php: ["code-review", "php-quality"]])

        #expect(configuration.defaultSkills(for: [.php]) == ["code-review", "php-quality"])
    }

    /// Mapa **nahrazuje**, neslučuje — stejně jako override per repo. Smysl je vyhodit PHP
    /// skilly na Go repu, ne k nim další přidat.
    @Test("Sada podle jazyka globální nahrazuje, nedoplňuje")
    func replacesTheGlobalSet() {
        let configuration = withLanguages([.go: ["go-review"]])

        #expect(configuration.defaultSkills(for: [.go]) == ["go-review"])
    }

    /// Pořadí jde od nejsilnějšího jazyka a duplicity vypadnou — jinak by se `code-review`
    /// spustil dvakrát.
    @Test("Dva jazyky dají sjednocení bez duplicit")
    func mergesTwoLanguagesWithoutDuplicates() {
        let configuration = withLanguages([
            .php: ["code-review", "php-quality"],
            .typescript: ["code-review", "ts-review"],
        ])

        #expect(configuration.defaultSkills(for: [.php, .typescript])
            == ["code-review", "php-quality", "ts-review"])
    }

    @Test("Jazyk mimo mapu bere globální sadu")
    func fallsBackToTheGlobalSet() {
        let configuration = withLanguages([.php: ["php-quality"]])

        #expect(configuration.defaultSkills(for: [.go]) == ["code-review", "security"])
    }

    @Test("Bez rozpoznaného jazyka platí globální sada")
    func fallsBackWhenNothingWasDetected() {
        #expect(withLanguages([.php: ["php-quality"]]).defaultSkills(for: []) == ["code-review", "security"])
    }

    /// Prázdná sada u jazyka je vlastní odpověď („tenhle jazyk tu nereviewuj“) a nesmí
    /// spadnout zpátky na globální hodnoty. Rozhoduje **existence** záznamu, ne obsah.
    @Test("Prázdná sada u jazyka nespadne na globální")
    func treatsAnEmptyLanguageSetAsDeliberate() {
        #expect(withLanguages([.php: []]).defaultSkills(for: [.php]).isEmpty)
    }

    @Test("Prázdná sada u jednoho jazyka nezruší druhý")
    func keepsTheOtherLanguagesSet() {
        let configuration = withLanguages([.php: [], .go: ["go-review"]])

        #expect(configuration.defaultSkills(for: [.php, .go]) == ["go-review"])
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

    // MARK: - Povolení odesílání

    /// Neznámé repo nesmí dostat otevřenou cestu ven ani omylem.
    @Test("Neznámé repo odesílat nesmí")
    func publishingIsOffForAnUnknownRepository() {
        #expect(!configuration().resolved(for: cli).allowsPublishing)
    }

    @Test("Repo si odesílání zapne i při globálně vypnutém")
    func aRepositoryCanOptIn() {
        let configuration = configuration([cli: RepositoryConfig(allowsPublishing: true)])

        #expect(configuration.resolved(for: cli).allowsPublishing)
        // Povolení je per repo, takže sousední repo zůstává zavřené.
        #expect(!configuration.resolved(for: vault).allowsPublishing)
    }

    @Test("Repo si odesílání zakáže i při globálně zapnutém")
    func aRepositoryCanOptOut() {
        var configuration = configuration([cli: RepositoryConfig(allowsPublishing: false)])
        configuration.global.allowsPublishing = true

        #expect(!configuration.resolved(for: cli).allowsPublishing)
        #expect(configuration.resolved(for: vault).allowsPublishing)
    }

    /// Tatáž past jako u režimu: `false` u repa je **vlastní odpověď**, ne shoda s globální
    /// hodnotou. Smazat ho jako „stejné jako globální“ by ho po přepnutí defaultu tiše
    /// otevřelo — a tady je následek odeslané review na repo, kam se posílat nemělo.
    @Test("Zakázané odesílání u repa se nesmaže jako shodné s globálním")
    func keepsAnExplicitOptOut() {
        var configuration = configuration()
        configuration.setRepository(RepositoryConfig(allowsPublishing: false), for: cli)
        configuration.global.allowsPublishing = true

        #expect(configuration.repositories[cli] != nil)
        #expect(!configuration.resolved(for: cli).allowsPublishing)
    }

    // MARK: - Výchozí hodnoty

    /// Výchozí konfigurace musí odpovídat tomu, co bylo do teď zadrátované v kódu — jinak
    /// by se aplikace po zavedení konfigurace začala chovat jinak.
    @Test("Výchozí hodnoty odpovídají dosavadním konstantám")
    func matchesTheConstantsItReplaces() {
        let standard = Configuration.standard.global

        #expect(standard.sources == [.reviewRequested])
        // **Změna proti #23:** dřív tu stálo `code-review`, jenže to není skill (je to
        // plugin command), takže se nemělo co načíst a model si domýšlel — viz #78.
        #expect(standard.skills == ["code-review:code-review"])
        // Prázdná mapa jazyků je součást „nic se nezměnilo“: dokud si uživatel nenastaví
        // vlastní, detekce jazyka na sadu skillů nesahá.
        #expect(standard.skillsByLanguage.isEmpty)
        #expect(Set(standard.blockingCategories) == Policy.defaultBlockingCategories)
        // Zapnout automat plošně musí být vědomé rozhodnutí, ne to, do čeho aplikace
        // spadne sama.
        #expect(standard.mode == .manual)
        // Výchozí stav odesílání je **vypnuto**, a je to vlastnost, na které stojí tvrdá
        // podmínka č. 1: dokud si o to někdo výslovně neřekne, neodejde na GitHub nic.
        #expect(!standard.allowsPublishing)
        #expect(standard.findingsLanguage == .czech)
        // Výchozí pohled na diff je ten, který aplikace kreslila před #98 — nový pohled se
        // nemá zapnout sám.
        #expect(standard.diffLayout == .unified)
        // Vzhled se řídí systémem, dokud si někdo neřekne jinak (#278) — vynutit režim sama od
        // sebe aplikace nemá proč.
        #expect(standard.appearance == .system)
        // Doslova ten text, co byl do #281 v kódu. Že složí týž prompt jako předtím, hlídá
        // `ReviewPromptTemplateTests` porovnáním znak po znaku.
        #expect(standard.reviewPrompt == ReviewPromptTemplate.standard)
        // Patnáct minut je doslova ta hodnota, co byla do #320 v `ClaudeReviewRunner` —
        // porovnává se s číslem, ne s konstantou, aby to nebylo tvrzení sebe o sobě.
        #expect(standard.reviewTimeoutMinutes == 15)
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

    /// Ze stejného důvodu jako u repozitářů: bez `CodingKeyRepresentable` by se slovník
    /// zakódoval jako pole střídavých klíčů a hodnot, které se ručně needituje.
    @Test("Mapa jazyků je v JSONu objekt klíčovaný jménem jazyka")
    func keysLanguagesByTheirName() throws {
        let data = try JSONEncoder().encode(withLanguages([.php: ["php-quality"]]))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let global = try #require(json["global"] as? [String: Any])
        let byLanguage = try #require(global["skillsByLanguage"] as? [String: Any])
        #expect(Array(byLanguage.keys) == ["php"])
    }

    // MARK: - Vzhled (#278)

    /// Vzhled je vlastnost **člověka**, ne repozitáře — a tohle je to tvrzení, které se dá
    /// pokazit potichu: stačilo by přidat klíč do `RepositoryConfig` a jedno repo by si
    /// přebarvilo celé okno. Měří se na zapsaném JSONu, protože právě ten je tím, co se pak
    /// nabízí k ruční editaci.
    @Test("Vzhled se nezapisuje do overridu per repo")
    func neverWritesTheAppearanceIntoARepositoryOverride() throws {
        var original = configuration([cli: RepositoryConfig(mode: .automatic, allowsPublishing: true)])
        original.global.appearance = .dark

        let data = try JSONEncoder().encode(original)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let global = try #require(json["global"] as? [String: Any])
        #expect(global["appearance"] as? String == "dark")
        let repositories = try #require(json["repositories"] as? [String: Any])
        let repository = try #require(repositories["cli/cli"] as? [String: Any])
        #expect(repository["appearance"] == nil)
        // A z druhé strany: v celém souboru je ten klíč právě jednou, takže se nedá přidat
        // druhá úroveň, aniž by to tady spadlo.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.components(separatedBy: "\"appearance\"").count - 1 == 1)
    }

    /// Klíč v souboru repa **nic neudělá** — ani nezahodí zbytek override, ani nepřebije
    /// globální volbu.
    @Test("Vzhled napsaný u repa se nepromítne nikam")
    func ignoresAnAppearanceWrittenUnderARepository() throws {
        let configuration = try JSONDecoder().decode(
            Configuration.self,
            from: Data(#"{"repositories": {"cli/cli": {"appearance": "dark", "skills": ["go-review"]}}}"#.utf8)
        )

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.global.appearance == .system)
        #expect(configuration.resolved(for: repo).skills == ["go-review"])
    }
}

/// Tolerance musí platit i na úrovni repa, ne jen globálně. Override, který mění jen
/// skilly, je ta nejběžnější věc, kterou do souboru někdo napíše — a `keyNotFound`
/// na `mode` by kvůli němu zahodil **celou** konfiguraci včetně toho, co je správně.
@Suite("Configuration — tolerantní čtení repa")
struct RepositoryConfigDecodingTests {
    private let cli = RepoID(owner: "cli", name: "cli")

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

    /// Špatný jazyk znamená prózu v jiném jazyce, ne spuštěné review, o které nikdo
    /// nežádal — na rozdíl od režimu se proto bere jako „nic jsem neřekl“.
    @Test("Neznámý jazyk u repa spadne na globální")
    func fallsBackOnAnUnknownFindingsLanguage() throws {
        var configuration = try self.configuration(
            #"{"repositories": {"cli/cli": {"findingsLanguage": "klingon"}}}"#
        )
        configuration.global.findingsLanguage = .english

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.resolved(for: repo).findingsLanguage == .english)
    }

    /// Rozbitá hodnota se srazí na `false`, ne na globální. Překlep v repu, u kterého se
    /// odesílání někdo pokoušel **zakázat**, ho nesmí nechat otevřené — je to tatáž přísnost
    /// jako u režimu a opačná než u jazyka nálezů.
    @Test("Rozbité povolení u repa skončí na zakázaném")
    func survivesABrokenPublishingFlag() throws {
        var configuration = try self.configuration(
            #"{"repositories": {"cli/cli": {"allowsPublishing": "ano"}}}"#
        )
        configuration.global.allowsPublishing = true

        let repo = try #require(RepoID("cli/cli"))
        #expect(!configuration.resolved(for: repo).allowsPublishing)
    }

    /// Chybějící klíč je naopak „ber globální“ — jinak by override, který mění jen skilly,
    /// repu tiše zakázal odesílání.
    @Test("Chybějící povolení u repa bere globální hodnotu")
    func fallsBackOnAMissingPublishingFlag() throws {
        var configuration = try self.configuration(#"{"repositories": {"cli/cli": {"skills": ["go-review"]}}}"#)
        configuration.global.allowsPublishing = true

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.resolved(for: repo).allowsPublishing)
    }

    @Test("Rozbité globální povolení skončí na zakázaném")
    func survivesABrokenGlobalPublishingFlag() throws {
        let configuration = try self.configuration(#"{"global": {"allowsPublishing": "ano"}}"#)

        #expect(!configuration.global.allowsPublishing)
    }

    @Test("Povolení ze souboru se přečte na obou úrovních")
    func readsThePublishingFlag() throws {
        let configuration = try self.configuration(
            #"{"global": {"allowsPublishing": true}, "repositories": {"cli/cli": {"allowsPublishing": false}}}"#
        )

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.global.allowsPublishing)
        #expect(!configuration.resolved(for: repo).allowsPublishing)
    }

    @Test("Globální režim ze souboru se přečte")
    func readsTheGlobalMode() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.mode == .automatic)
    }

    // MARK: - Pohled na diff

    @Test("Pohled na diff ze souboru se přečte")
    func readsTheDiffLayout() throws {
        let configuration = try self.configuration(#"{"global": {"diffLayout": "split"}}"#)

        #expect(configuration.global.diffLayout == .split)
    }

    /// Chybějící klíč znamená dnešní chování — konfigurace bez `diffLayout` je ta, kterou má
    /// na disku každý, kdo aplikaci používal před #98.
    @Test("Chybějící pohled na diff bere výchozí")
    func fallsBackOnAMissingDiffLayout() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.diffLayout == .unified)
    }

    /// Tolerantně jako jazyk nálezů, ne přísně jako režim: nejhorší následek překlepu je jiný
    /// pohled na diff, který se otočí jedním kliknutím v liště. A celý soubor kvůli němu
    /// zmizet nesmí.
    @Test("Rozbitý pohled na diff nezahodí zbytek konfigurace")
    func survivesABrokenDiffLayout() throws {
        let configuration = try self.configuration(
            #"{"global": {"diffLayout": "vedle-sebe", "mode": "automatic"}}"#
        )

        #expect(configuration.global.diffLayout == .unified)
        #expect(configuration.global.mode == .automatic)
    }

    // MARK: - Vzhled (#278)

    @Test("Vzhled ze souboru se přečte", arguments: [("light", AppearanceMode.light), ("dark", .dark)])
    func readsTheAppearance(json: String, expected: AppearanceMode) throws {
        let configuration = try self.configuration(#"{"global": {"appearance": "\#(json)"}}"#)

        #expect(configuration.global.appearance == expected)
    }

    /// Chybějící klíč znamená dnešní chování — konfigurace bez `appearance` je ta, kterou má na
    /// disku každý, kdo aplikaci používal před #278.
    @Test("Chybějící vzhled bere podle systému")
    func fallsBackOnAMissingAppearance() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.appearance == .system)
    }

    /// Tolerantně jako pohled na diff: neznámá hodnota znamená „podle systému“, ne pád — a celý
    /// soubor kvůli ní zmizet nesmí. Přísnost jako u režimu nebo odesílání by tady nechránila nic,
    /// protože vzhledem nic neodejde a nic se nespustí.
    @Test("Rozbitý vzhled nezahodí zbytek konfigurace")
    func survivesABrokenAppearance() throws {
        let configuration = try self.configuration(
            #"{"global": {"appearance": "tmavy", "mode": "automatic"}}"#
        )

        #expect(configuration.global.appearance == .system)
        #expect(configuration.global.mode == .automatic)
    }

    // MARK: - Prompt review (#281)

    @Test("Šablona promptu ze souboru se přečte")
    func readsTheReviewPrompt() throws {
        let configuration = try self.configuration(
            #"{"global": {"reviewPrompt": "Look at {{skill}} over {{baseSha}}."}}"#
        )

        #expect(configuration.global.reviewPrompt == "Look at {{skill}} over {{baseSha}}.")
    }

    /// Chybějící klíč znamená dnešní chování — konfigurace bez `reviewPrompt` je ta, kterou má
    /// na disku každý, kdo aplikaci používal před #281.
    @Test("Chybějící šablona bere výchozí text")
    func fallsBackOnAMissingReviewPrompt() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.reviewPrompt == ReviewPromptTemplate.standard)
    }

    /// **Přísně, ne tolerantně** — tiše podstrčený výchozí prompt by znamenal, že se reviewer ptá
    /// na něco jiného, než co má někdo napsané v souboru, a nic by na to neupozornilo. Takhle se
    /// okno zamkne s hláškou „Konfiguraci se nepodařilo přečíst“ a soubor se **nepřepíše**.
    ///
    /// Vyjmenované schválně: číslo, pole i objekt. Jeden případ by prošel i implementaci, která
    /// hlídá zrovna ten jeden typ.
    @Test(
        "Šablona, která není text, čtení položí",
        arguments: ["5", "[\"a\"]", "{\"text\": \"a\"}"]
    )
    func refusesAReviewPromptThatIsNotAString(_ json: String) {
        #expect(throws: (any Error).self) {
            try self.configuration(#"{"global": {"reviewPrompt": \#(json)}}"#)
        }
    }

    /// **`null` je proti tomu chybějící klíč**, ne rozbitá hodnota — a bere se z něj výchozí text.
    ///
    /// Je to vědomé: `null` není hodnota, které by se nedalo rozumět, ale výslovné „nic tu není“,
    /// tedy totéž, co u téhle šablony znamená prázdný řetězec. Chová se tak i `sources` a `skills`,
    /// zbylé dva klíče, u kterých se rozbitá hodnota hlásí, takže třetí odpověď na tutéž otázku
    /// tady nevzniká. Test je tu proto, aby se ta úvaha nemusela dělat znovu — a aby se změna
    /// v jednu nebo druhou stranu musela udělat vědomě.
    @Test("Šablona zapsaná jako null se bere jako chybějící")
    func treatsANullReviewPromptAsMissing() throws {
        let configuration = try self.configuration(#"{"global": {"reviewPrompt": null}}"#)

        #expect(configuration.global.reviewPrompt == ReviewPromptTemplate.standard)
    }

    /// Prázdný řetězec je platná hodnota a znamená „ber výchozí“ — ne prompt bez zadání.
    @Test("Prázdná šablona v souboru projde a bere výchozí")
    func acceptsAnEmptyReviewPrompt() throws {
        let configuration = try self.configuration(#"{"global": {"reviewPrompt": ""}}"#)

        #expect(configuration.global.reviewPrompt.isEmpty)
        #expect(Policy.reviewPromptTemplate(from: configuration.global.reviewPrompt)
            == ReviewPromptTemplate.standard)
    }

    /// Prompt je „jak vypadá review u mě“, ne vlastnost repozitáře — tatáž úvaha jako u vzhledu
    /// a pohledu na diff. Klíč u repa proto nic neudělá.
    @Test("Šablona napsaná u repa se nepromítne nikam")
    func ignoresAReviewPromptWrittenUnderARepository() throws {
        let configuration = try self.configuration(
            #"{"repositories": {"cli/cli": {"reviewPrompt": "cokoli", "skills": ["go-review"]}}}"#
        )

        let repo = try #require(RepoID("cli/cli"))
        #expect(configuration.global.reviewPrompt == ReviewPromptTemplate.standard)
        #expect(configuration.resolved(for: repo).skills == ["go-review"])
    }

    // MARK: - Časový limit běhu (#320)

    /// Chybějící klíč znamená dnešní chování — konfigurace bez `reviewTimeoutMinutes` je ta,
    /// kterou má na disku každý, kdo aplikaci používal před #320.
    @Test("Chybějící limit bere patnáct minut")
    func fallsBackOnAMissingReviewTimeout() throws {
        let configuration = try self.configuration(#"{"global": {"mode": "automatic"}}"#)

        #expect(configuration.global.reviewTimeoutMinutes == 15)
        #expect(configuration.resolved(for: cli).reviewTimeout == .seconds(900))
    }

    @Test("Limit ze souboru se přečte a projeví se ve `resolved`")
    func readsTheReviewTimeout() throws {
        let configuration = try self.configuration(#"{"global": {"reviewTimeoutMinutes": 40}}"#)

        #expect(configuration.global.reviewTimeoutMinutes == 40)
        #expect(configuration.resolved(for: cli).reviewTimeout == .seconds(2400))
    }

    /// **Syrová hodnota v konfiguraci zůstane, sráží se až `resolved(for:)`.** Kdyby se sráželo
    /// při čtení, přišlo by se o rozdíl mezi „napsal jsem 120“ a „mám 60“ — a nastavení by neměl
    /// kdo pojmenovat.
    @Test(
        "Hodnota mimo meze soubor nepoloží, ale běží se s mezí",
        arguments: [(1, Duration.seconds(300)), (0, .seconds(300)), (600, .seconds(3600))]
    )
    func clampsAnOutOfRangeReviewTimeout(configured: Int, expected: Duration) throws {
        let configuration = try self.configuration(
            #"{"global": {"reviewTimeoutMinutes": \#(configured)}}"#
        )

        #expect(configuration.global.reviewTimeoutMinutes == configured)
        #expect(configuration.resolved(for: cli).reviewTimeout == expected)
        #expect(Policy.reviewTimeoutProblem(in: configuration.global.reviewTimeoutMinutes) != nil)
    }

    /// **Přísně, ne tolerantně** — stejně jako u ostatních čísel. Tiše podstrčených patnáct minut
    /// by znamenalo limit, o který nikdo neřekl.
    @Test(
        "Limit, který není číslo, čtení položí",
        arguments: ["\"patnáct\"", "[15]", "{\"minutes\": 15}"]
    )
    func refusesAReviewTimeoutThatIsNotANumber(_ json: String) {
        #expect(throws: (any Error).self) {
            try self.configuration(#"{"global": {"reviewTimeoutMinutes": \#(json)}}"#)
        }
    }

    /// Na rozdíl od promptu, vzhledu a pohledu na diff **override per repo má** — velké repo
    /// potřebuje víc a je to vlastnost repa, ne člověka.
    @Test("Repo si limit přebít smí")
    func aRepositoryMayOverrideTheReviewTimeout() throws {
        let configuration = try self.configuration(
            #"{"global": {"reviewTimeoutMinutes": 20},"#
                + #""repositories": {"cli/cli": {"reviewTimeoutMinutes": 45}}}"#
        )

        let other = try #require(RepoID("keboola/vault"))
        #expect(configuration.resolved(for: cli).reviewTimeout == .seconds(2700))
        // A zbytku fronty se to netýká.
        #expect(configuration.resolved(for: other).reviewTimeout == .seconds(1200))
    }

    /// `nil` u repa je „ber globální“, ne „ber výchozí“ — tatáž úmluva jako u režimu a sad.
    @Test("Repo bez vlastního limitu bere globální")
    func aRepositoryWithoutAnOverrideTakesTheGlobalTimeout() throws {
        let configuration = try self.configuration(
            #"{"global": {"reviewTimeoutMinutes": 30},"#
                + #""repositories": {"cli/cli": {"skills": ["go-review"]}}}"#
        )

        #expect(configuration.repositories[cli]?.reviewTimeoutMinutes == nil)
        #expect(configuration.resolved(for: cli).reviewTimeout == .seconds(1800))
    }

    /// Meze platí i na override, a sráží je totéž místo — jinak by se dala horní mez obejít
    /// zápisem pod repem, tedy zrovna tou cestou, kterou se do souboru píše ručně.
    @Test("Override mimo meze se srazí stejně jako globální")
    func clampsAnOutOfRangeOverride() throws {
        let configuration = try self.configuration(
            #"{"repositories": {"cli/cli": {"reviewTimeoutMinutes": 999}}}"#
        )

        #expect(configuration.repositories[cli]?.reviewTimeoutMinutes == 999)
        #expect(configuration.resolved(for: cli).reviewTimeout == .seconds(3600))
    }
}
