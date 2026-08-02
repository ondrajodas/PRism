import Foundation

/// Jak se review pouští na konkrétním repu.
enum ReviewMode: String, Codable, Hashable, Sendable {
    /// Čeká na tlačítko.
    case manual
    /// Spustí se samo, jakmile se PR objeví v seznamu.
    case automatic
}

/// Nastavení, které platí, dokud ho repo nepřebije.
///
/// Dekóduje se **tolerantně**: co v souboru chybí, se doplní výchozí hodnotou. Soubor se
/// edituje ručně a málokdy obsahuje všechno — přísné dekódování by kvůli jednomu
/// chybějícímu klíči zahodilo celou konfiguraci a uživatel by hledal, proč mu nastavení
/// nefunguje.
struct GlobalConfig: Codable, Equatable, Sendable {
    var sources: [Source]
    /// Sada, která platí, dokud ji nepřebije jazyk nebo repo. Je to ta „hvězdička“
    /// z rozpisu v #24 — druhý zápis téhož by byla past pro toho, kdo soubor čte.
    var skills: [String]
    /// Výchozí sada podle rozpoznaného jazyka projektu. Prázdná mapa = detekce nic nemění.
    var skillsByLanguage: [ProjectLanguage: [String]]
    var blockingCategories: [String]
    /// Výchozí režim pro repo, které si neřeklo o jiný. Ve výchozím stavu `manual` —
    /// zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.
    var mode: ReviewMode
    /// Jazyk, ve kterém reviewer píše nálezy. Výchozí čeština — okno je české a nálezy
    /// vedle českých popisků působily jako dva slepené nástroje.
    var findingsLanguage: FindingsLanguage
    /// V sekundách, ne `Duration` — soubor se edituje ručně a `Duration` se do JSONu
    /// kóduje jako dvojice čísel, kterou nikdo nenapíše.
    var pollIntervalSeconds: Int
    var maxConcurrentReviews: Int
    /// V megabajtech ze stejného důvodu: `10737418240` se nečte.
    var cacheBudgetMegabytes: Int
    /// `nil` = model, který si `claude` zvolí sám.
    var model: String?

    init(
        sources: [Source],
        skills: [String],
        skillsByLanguage: [ProjectLanguage: [String]] = [:],
        blockingCategories: [String],
        mode: ReviewMode,
        findingsLanguage: FindingsLanguage = .czech,
        pollIntervalSeconds: Int,
        maxConcurrentReviews: Int,
        cacheBudgetMegabytes: Int,
        model: String?
    ) {
        self.sources = sources
        self.skills = skills
        self.skillsByLanguage = skillsByLanguage
        self.blockingCategories = blockingCategories
        self.mode = mode
        self.findingsLanguage = findingsLanguage
        self.pollIntervalSeconds = pollIntervalSeconds
        self.maxConcurrentReviews = maxConcurrentReviews
        self.cacheBudgetMegabytes = cacheBudgetMegabytes
        self.model = model
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Configuration.standard.global
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? standard.sources
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? standard.skills
        // Rozbitá mapa se hlásí ze stejného důvodu jako rozbité `skills`: tiše podstrčený
        // výchozí (prázdný) obsah by na jazykových repech pustil jiné reviewery, než jaké
        // tam měly běžet.
        skillsByLanguage = try container.decodeIfPresent([ProjectLanguage: [String]].self, forKey: .skillsByLanguage)
            ?? standard.skillsByLanguage
        blockingCategories = try container.decodeIfPresent([String].self, forKey: .blockingCategories)
            ?? standard.blockingCategories
        // Neznámý režim se bere jako `manual` ze stejného důvodu jako u repa: samo od sebe
        // se nemá spouštět nic, a překlep v souboru není důvod pustit reviewery na všechno.
        mode = (try? container.decode(ReviewMode.self, forKey: .mode)) ?? standard.mode
        findingsLanguage = (try? container.decode(FindingsLanguage.self, forKey: .findingsLanguage))
            ?? standard.findingsLanguage
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds)
            ?? standard.pollIntervalSeconds
        maxConcurrentReviews = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentReviews)
            ?? standard.maxConcurrentReviews
        cacheBudgetMegabytes = try container.decodeIfPresent(Int.self, forKey: .cacheBudgetMegabytes)
            ?? standard.cacheBudgetMegabytes
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }
}

/// Co si repo nastavuje jinak. Co je `nil`, se bere globálně.
struct RepositoryConfig: Codable, Equatable, Sendable {
    /// `nil` znamená „ber globální“, stejně jako u sad níž. Kdyby byl režim povinný,
    /// nešlo by odlišit repo, které si o `manual` **řeklo**, od toho, které o něm nic
    /// neříká — a při globálním automatu jsou to opačné odpovědi.
    var mode: ReviewMode?
    /// `nil` = ber globální. U firemního repa s mezinárodním týmem dává smysl angličtina,
    /// i když je zbytek fronty český.
    var findingsLanguage: FindingsLanguage?
    /// **Nahrazuje** globální sadu, neslučuje se s ní — smysl je vyhodit PHP skilly na Go
    /// repu. Prázdné pole je vlastní odpověď („tady nereviewuj nic“), `nil` znamená
    /// „ber globální“.
    var skills: [String]?
    var blockingCategories: [String]?

    init(
        mode: ReviewMode? = nil,
        findingsLanguage: FindingsLanguage? = nil,
        skills: [String]? = nil,
        blockingCategories: [String]? = nil
    ) {
        self.mode = mode
        self.findingsLanguage = findingsLanguage
        self.skills = skills
        self.blockingCategories = blockingCategories
    }

    /// Tolerantní ze stejného důvodu jako `GlobalConfig`, a tady na tom záleží nejvíc:
    /// override, který mění jen skilly, je to nejběžnější, co do souboru někdo napíše.
    /// Přísné dekódování by kvůli němu shodilo **celou** konfiguraci včetně toho, co je
    /// napsané správně.
    ///
    /// Chybějící klíč a **rozbitá hodnota** se ale rozlišují: chybějící znamená „ber
    /// globální“, kdežto překlep v hodnotě se srazí na `manual`. Vzít u něj globální
    /// hodnotu by při globálním automatu znamenalo, že překlep pustí reviewery na repo,
    /// u kterého se je někdo pokoušel vypnout.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.mode) {
            mode = (try? container.decode(ReviewMode.self, forKey: .mode)) ?? .manual
        } else {
            mode = nil
        }
        // Na rozdíl od režimu se rozbitá hodnota bere jako „nic jsem neřekl“: špatný jazyk
        // znamená prózu v jiném jazyce, ne spuštěné review, o které nikdo nežádal.
        findingsLanguage = try? container.decodeIfPresent(FindingsLanguage.self, forKey: .findingsLanguage)
        skills = try container.decodeIfPresent([String].self, forKey: .skills)
        blockingCategories = try container.decodeIfPresent([String].self, forKey: .blockingCategories)
    }
}

/// Celý obsah `config.json`.
struct Configuration: Codable, Equatable, Sendable {
    var global: GlobalConfig
    /// Klíčem je `owner/repo`. `RepoID` je `CodingKeyRepresentable`, takže v JSONu vyjde
    /// jako čitelný objekt, ne jako pole střídavých klíčů a hodnot.
    var repositories: [RepoID: RepositoryConfig]

    init(global: GlobalConfig, repositories: [RepoID: RepositoryConfig]) {
        self.global = global
        self.repositories = repositories
    }

    /// Tolerantní ze stejného důvodu jako `GlobalConfig`: samotné `{"repositories": …}`
    /// je platná konfigurace.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        global = try container.decodeIfPresent(GlobalConfig.self, forKey: .global)
            ?? Configuration.standard.global
        repositories = try container.decodeIfPresent([RepoID: RepositoryConfig].self, forKey: .repositories) ?? [:]
    }

    /// Hodnoty, se kterými aplikace běžela, než konfigurace existovala. Nesmí se rozejít —
    /// jinak by se po zavedení konfigurace začala chovat jinak.
    static let standard = Configuration(
        global: GlobalConfig(
            sources: [.reviewRequested],
            skills: ["code-review"],
            blockingCategories: Policy.defaultBlockingCategories.sorted(),
            mode: .manual,
            findingsLanguage: .czech,
            pollIntervalSeconds: 60,
            maxConcurrentReviews: 3,
            cacheBudgetMegabytes: 10 * 1024,
            model: nil
        ),
        repositories: [:]
    )

    /// Zapíše nastavení repa tak, jak se má objevit v souboru.
    ///
    /// Záznam, ve kterém nic není, klíč **smaže** — znamená totéž jako chybějící
    /// a `config.json` se čte ručně. Bez toho by v něm po každém proklikání okna
    /// nastavení zůstala hromada prázdných objektů.
    ///
    /// Rozhoduje o tom prázdnost, **ne shoda s globální hodnotou**: repo, které si
    /// o `manual` řeklo, si ho má podržet i potom, co se globální default přepne na
    /// automat. Smazat ho jako „stejně jako globální“ by ho tiše zapnulo.
    mutating func setRepository(_ repository: RepositoryConfig, for repo: RepoID) {
        repositories[repo] = repository == RepositoryConfig() ? nil : repository
    }

    /// Nastavení pro konkrétní repo — globální hodnoty přebité tím, co si repo řeklo.
    ///
    /// Neznámé repo dostane globální režim, a ten je ve výchozím stavu **manuální**: když
    /// můžou přijít libovolná repa, neznámé nesmí bez dozoru spálit celý panel Claude
    /// sessions. Přepnout globální default na automat je vědomé rozhodnutí uživatele.
    func resolved(for repo: RepoID) -> ResolvedConfig {
        let overrides = repositories[repo]
        return ResolvedConfig(
            mode: overrides?.mode ?? global.mode,
            findingsLanguage: overrides?.findingsLanguage ?? global.findingsLanguage,
            skills: Self.nonBlank(overrides?.skills ?? global.skills),
            blockingCategories: Set(Self.nonBlank(overrides?.blockingCategories ?? global.blockingCategories))
        )
    }

    /// Zdroje, na které se má aplikace ptát.
    ///
    /// Zdroj bez dotazu se přeskočí. V okně nastavení totiž **existuje mezistav**: řádek
    /// se přidá prázdný a mezi jeho vznikem a dopsáním dotazu se konfigurace uloží.
    /// `gh search prs` bez výrazu selže, a protože **selhání jednoho zdroje zahazuje celý
    /// tik**, zmizel by kvůli rozepsanému řádku celý seznam PR.
    var activeSources: [Source] {
        global.sources.filter { !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Výchozí sada skillů pro repo, ve kterém se rozpoznaly tyhle jazyky.
    ///
    /// Hodnota u jazyka je **celá sada**, ne příspěvek ke globální — stejně jako override
    /// per repo. Smysl je vyhodit PHP skilly na Go repu, ne k nim další přidat.
    ///
    /// Když žádný z rozpoznaných jazyků v mapě není, platí globální sada. Rozhoduje
    /// **existence záznamu**, ne jeho obsah: `php: []` je vlastní odpověď („PHP tady
    /// nereviewuj“) a nesmí spadnout zpátky na globální hodnoty.
    func defaultSkills(for languages: [ProjectLanguage]) -> [String] {
        let mapped = languages.compactMap { global.skillsByLanguage[$0] }
        guard !mapped.isEmpty else { return Self.nonBlank(global.skills) }

        // Pořadí jde od nejsilnějšího jazyka, duplicity vypadnou. `Set` by tu pořadí
        // rozhodil a s ním i pořadí chipů v liště.
        var skills: [String] = []
        for skill in Self.nonBlank(mapped.flatMap { $0 }) where !skills.contains(skill) {
            skills.append(skill)
        }
        return skills
    }

    /// Prázdné položky se zahazují ze stejného důvodu jako prázdný dotaz: nový řádek
    /// v editoru vzniká prázdný. Skill bez jména by se pustil jako session, která nemá co
    /// dělat, a kategorie bez jména neodpovídá žádnému nálezu.
    ///
    /// Prázdný **seznam** to nemění — ten je pořád vlastní odpověď („tady nic“).
    private static func nonBlank(_ items: [String]) -> [String] {
        items.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

/// Co z konfigurace vyjde pro jedno repo.
struct ResolvedConfig: Equatable, Sendable {
    let mode: ReviewMode
    let findingsLanguage: FindingsLanguage
    let skills: [String]
    let blockingCategories: Set<String>
}
