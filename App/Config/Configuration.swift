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
    var skills: [String]
    var blockingCategories: [String]
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
        blockingCategories: [String],
        pollIntervalSeconds: Int,
        maxConcurrentReviews: Int,
        cacheBudgetMegabytes: Int,
        model: String?
    ) {
        self.sources = sources
        self.skills = skills
        self.blockingCategories = blockingCategories
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
        blockingCategories = try container.decodeIfPresent([String].self, forKey: .blockingCategories)
            ?? standard.blockingCategories
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
    var mode: ReviewMode
    /// **Nahrazuje** globální sadu, neslučuje se s ní — smysl je vyhodit PHP skilly na Go
    /// repu. Prázdné pole je vlastní odpověď („tady nereviewuj nic“), `nil` znamená
    /// „ber globální“.
    var skills: [String]?
    var blockingCategories: [String]?

    init(mode: ReviewMode = .manual, skills: [String]? = nil, blockingCategories: [String]? = nil) {
        self.mode = mode
        self.skills = skills
        self.blockingCategories = blockingCategories
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
            pollIntervalSeconds: 60,
            maxConcurrentReviews: 3,
            cacheBudgetMegabytes: 10 * 1024,
            model: nil
        ),
        repositories: [:]
    )

    /// Nastavení pro konkrétní repo. Neznámé repo dostane globální hodnoty a **manuální
    /// režim**: když můžou přijít libovolná repa, neznámé nesmí bez dozoru spálit celý
    /// panel Claude sessions.
    func resolved(for repo: RepoID) -> ResolvedConfig {
        let overrides = repositories[repo]
        return ResolvedConfig(
            mode: overrides?.mode ?? .manual,
            skills: overrides?.skills ?? global.skills,
            blockingCategories: Set(overrides?.blockingCategories ?? global.blockingCategories)
        )
    }
}

/// Co z konfigurace vyjde pro jedno repo.
struct ResolvedConfig: Equatable, Sendable {
    let mode: ReviewMode
    let skills: [String]
    let blockingCategories: Set<String>
}
