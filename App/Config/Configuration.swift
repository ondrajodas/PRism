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
    ///
    /// **Jsou to id nástroje `Skill`, ne slash commandy.** Do #78 tu stálo `code-review`,
    /// což skill vůbec není (je to plugin **command**), takže se nemělo co načíst a model
    /// si domýšlel. Plugin se adresuje `plugin:skill`, uživatelský skill svým jménem.
    var skills: [String]
    /// Výchozí sada podle rozpoznaného jazyka projektu. Prázdná mapa = detekce nic nemění.
    var skillsByLanguage: [ProjectLanguage: [String]]
    var blockingCategories: [String]
    /// Psaná půlka zadání pro reviewera (#281) se zástupnými texty `{{skill}}` a `{{baseSha}}`.
    ///
    /// **Globálně, ne per repo**, a je to vědomé rozhodnutí: per repo se řídí *co* se pouští
    /// (skilly, blokující kategorie), kdežto prompt je „jak vypadá review u mě“. Další override
    /// na místě, kde by se skoro nikdy nelišil, jen zdražuje čtení `config.json` —
    /// `RepositoryConfig` ho proto nemá a je na to test.
    ///
    /// **Prázdná hodnota znamená „ber výchozí“**, ne „pusť reviewera bez zadání“; jádro
    /// kontraktu se připojuje mimo šablonu, viz `ReviewPromptTemplate`.
    var reviewPrompt: String
    /// Výchozí režim pro repo, které si neřeklo o jiný. Ve výchozím stavu `manual` —
    /// zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.
    var mode: ReviewMode
    /// Smí se z aplikace odeslat review? Ve výchozím stavu **ne**.
    ///
    /// Je to brána, ne pohodlí — viz tvrdá podmínka č. 1 v `CLAUDE.md`. Do #107 to byl
    /// zadrátovaný seznam rep s jediným sandboxem; teď je to nastavení, ale vlastnost „samo
    /// nic neodejde“ drží **výchozí vypnuto**: dokud si o to někdo výslovně neřekne, nejde
    /// odeslat nikam. Odesílá pořád jedině člověk potvrzením (#68), to se nemění.
    var allowsPublishing: Bool
    /// Jazyk, do kterého se nálezy překládají, než se ukážou. **Ne** jazyk, ve kterém je
    /// reviewer píše — jeho prompt o jazyku mlčí. Výchozí čeština, protože okno je české
    /// a anglické nálezy vedle českých popisků působily jako dva slepené nástroje.
    var findingsLanguage: FindingsLanguage
    /// S jakým pohledem se diff otevírá. Výchozí `unified`, tedy dnešní chování.
    ///
    /// Per repo se to **nenastavuje**: `mode` nebo `skills` jsou vlastnost repa, kdežto jak
    /// se čte diff, je vlastnost člověka, který ho čte. Přepínač v liště nad diffem je proti
    /// tomuhle jen odchylka do zavření aplikace — do souboru nezapisuje, jinak by hodnota
    /// tady přestala být tou, které se říká výchozí.
    var diffLayout: DiffLayout
    /// Jaký vzhled má mít okno (#278). Výchozí `system`, tedy chování před #278.
    ///
    /// Per repo se to **nenastavuje**, ze stejného důvodu jako `diffLayout` a notifikace:
    /// vzhled je vlastnost člověka, který se kouká, ne repozitáře, na který se kouká.
    /// `RepositoryConfig` ho proto nemá a je na to test.
    var appearance: AppearanceMode
    /// V sekundách, ne `Duration` — soubor se edituje ručně a `Duration` se do JSONu
    /// kóduje jako dvojice čísel, kterou nikdo nenapíše.
    var pollIntervalSeconds: Int
    var maxConcurrentReviews: Int
    /// Kolik review smí za den spustit **automat**. Pojistka proti překvapení na účtu:
    /// ruční spouštění limit nezná, protože za tím vždycky někdo stojí.
    var autoRunsPerDay: Int
    /// V megabajtech ze stejného důvodu: `10737418240` se nečte.
    var cacheBudgetMegabytes: Int
    /// `nil` = model, který si `claude` zvolí sám.
    var model: String?
    /// Co se má hlásit notifikací (#86). Jen globálně — viz `NotificationSettings`.
    var notifications: NotificationSettings

    init(
        sources: [Source],
        skills: [String],
        skillsByLanguage: [ProjectLanguage: [String]] = [:],
        blockingCategories: [String],
        reviewPrompt: String = ReviewPromptTemplate.standard,
        mode: ReviewMode,
        allowsPublishing: Bool = false,
        findingsLanguage: FindingsLanguage = .czech,
        diffLayout: DiffLayout = .unified,
        appearance: AppearanceMode = .system,
        pollIntervalSeconds: Int,
        maxConcurrentReviews: Int,
        autoRunsPerDay: Int = 20,
        cacheBudgetMegabytes: Int,
        model: String?,
        notifications: NotificationSettings = NotificationSettings()
    ) {
        self.sources = sources
        self.skills = skills
        self.skillsByLanguage = skillsByLanguage
        self.blockingCategories = blockingCategories
        self.reviewPrompt = reviewPrompt
        self.mode = mode
        self.allowsPublishing = allowsPublishing
        self.findingsLanguage = findingsLanguage
        self.diffLayout = diffLayout
        self.appearance = appearance
        self.pollIntervalSeconds = pollIntervalSeconds
        self.maxConcurrentReviews = maxConcurrentReviews
        self.autoRunsPerDay = autoRunsPerDay
        self.cacheBudgetMegabytes = cacheBudgetMegabytes
        self.model = model
        self.notifications = notifications
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
        // Chybějící klíč = výchozí text. **Rozbitá hodnota položí celé čtení** — `try`, ne
        // `try?`, a je to schválně: kdyby se místo čísla nebo objektu tiše dosadil výchozí
        // prompt, běželo by review s jiným zadáním, než jaké si někdo napsal, a nic by na to
        // neupozornilo. Takhle se v okně ukáže „Konfiguraci se nepodařilo přečíst“ a soubor
        // se nepřepíše. Tolerantní čtení tím neporušuje: tolerantní je vůči **chybějícímu**
        // klíči, ne vůči hodnotě, které se nedá rozumět.
        reviewPrompt = try container.decodeIfPresent(String.self, forKey: .reviewPrompt)
            ?? standard.reviewPrompt
        // Neznámý režim se bere jako `manual` ze stejného důvodu jako u repa: samo od sebe
        // se nemá spouštět nic, a překlep v souboru není důvod pustit reviewery na všechno.
        mode = (try? container.decode(ReviewMode.self, forKey: .mode)) ?? standard.mode
        // Rozbitá hodnota se srazí na výchozí, a ta je `false`: překlep v souboru nesmí
        // otevřít cestu ven. Je to tatáž přísnost jako u režimu a opačná než u jazyka
        // nálezů, kde je nejhorším následkem próza v jiném jazyce.
        allowsPublishing = (try? container.decode(Bool.self, forKey: .allowsPublishing))
            ?? standard.allowsPublishing
        findingsLanguage = (try? container.decode(FindingsLanguage.self, forKey: .findingsLanguage))
            ?? standard.findingsLanguage
        // Tolerantně jako jazyk nálezů, ne přísně jako režim nebo odesílání: nejhorší
        // následek překlepu je jiný pohled na diff, který se otočí jedním kliknutím
        // v liště — nespustí review ani neotevře cestu ven.
        diffLayout = (try? container.decode(DiffLayout.self, forKey: .diffLayout)) ?? standard.diffLayout
        // Tolerantně jako pohled na diff, a se stejným odůvodněním: neznámá hodnota znamená
        // **podle systému**, tedy stav, ve kterém aplikace běžela před #278. Není to spolknutá
        // chyba — je to vědomě ta nejmírnější odpověď, protože nejhorší následek překlepu je
        // světlé okno, které se přepne jedním kliknutím v liště. Přísnost jako u režimu
        // nebo odesílání by tady nechránila nic: vzhledem nic neodejde a nic se nespustí.
        appearance = (try? container.decode(AppearanceMode.self, forKey: .appearance)) ?? standard.appearance
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds)
            ?? standard.pollIntervalSeconds
        maxConcurrentReviews = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentReviews)
            ?? standard.maxConcurrentReviews
        autoRunsPerDay = try container.decodeIfPresent(Int.self, forKey: .autoRunsPerDay)
            ?? standard.autoRunsPerDay
        cacheBudgetMegabytes = try container.decodeIfPresent(Int.self, forKey: .cacheBudgetMegabytes)
            ?? standard.cacheBudgetMegabytes
        model = try container.decodeIfPresent(String.self, forKey: .model)
        // Chybějící klíč = výchozí (všechno zapnuté). Rozbitý obsah řeší `NotificationSettings`
        // sám, po jednotlivých přepínačích — celá sekce se kvůli jednomu překlepu zahazovat
        // nemá, jinak by se s ním vypnulo i to, co je napsané správně.
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications)
            ?? standard.notifications
    }
}

/// Co si repo nastavuje jinak. Co je `nil`, se bere globálně.
struct RepositoryConfig: Codable, Equatable, Sendable {
    /// `nil` znamená „ber globální“, stejně jako u sad níž. Kdyby byl režim povinný,
    /// nešlo by odlišit repo, které si o `manual` **řeklo**, od toho, které o něm nic
    /// neříká — a při globálním automatu jsou to opačné odpovědi.
    var mode: ReviewMode?
    /// `nil` = ber globální, stejně jako režim. Vyplněná hodnota znamená „řekl jsem si
    /// o tohle“ — a `false` u repa se proto **nesmaže** jako „shodné s globálním“, jinak by
    /// ho přepnutí globálního defaultu tiše otevřelo.
    var allowsPublishing: Bool?
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
        allowsPublishing: Bool? = nil,
        findingsLanguage: FindingsLanguage? = nil,
        skills: [String]? = nil,
        blockingCategories: [String]? = nil
    ) {
        self.mode = mode
        self.allowsPublishing = allowsPublishing
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
        // Stejně jako u režimu: chybějící klíč je „ber globální“, ale **rozbitá hodnota se
        // srazí na `false`**. Vzít u ní globální hodnotu by znamenalo, že překlep v repu,
        // u kterého se odesílání někdo pokoušel zakázat, ho při globálním povolení nechá
        // otevřené.
        if container.contains(.allowsPublishing) {
            allowsPublishing = (try? container.decode(Bool.self, forKey: .allowsPublishing)) ?? false
        } else {
            allowsPublishing = nil
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
            skills: ["code-review:code-review"],
            blockingCategories: Policy.defaultBlockingCategories.sorted(),
            // Doslova ten text, co byl do #281 v kódu — po zavedení pole se aplikace nesmí
            // začít chovat jinak. Hlídá to test, který složený prompt porovnává znak po znaku.
            reviewPrompt: ReviewPromptTemplate.standard,
            mode: .manual,
            allowsPublishing: false,
            findingsLanguage: .czech,
            diffLayout: .unified,
            appearance: .system,
            pollIntervalSeconds: 60,
            maxConcurrentReviews: 3,
            autoRunsPerDay: 20,
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
            allowsPublishing: overrides?.allowsPublishing ?? global.allowsPublishing,
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
    /// Smí se z tohohle repa odeslat review? Odpovídá na to `PublishScope`, ne volající —
    /// dvě místa, kde se ta otázka vyhodnocuje, by se rozešla.
    let allowsPublishing: Bool
    let findingsLanguage: FindingsLanguage
    let skills: [String]
    let blockingCategories: Set<String>
}
