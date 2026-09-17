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
    /// Další loginy, které se počítají za **moje** (#330). Viewer z `gh api user` se přidává sám,
    /// tady se vypisuje jen to, co se od něj liší — typicky agent s vlastním účtem
    /// (`github-actions[bot]`, Copilot), který pushuje pod sebou.
    ///
    /// **Prázdné pole je běžný stav, ne nedodělek**: agenti v tomhle repu pushují přes moje `gh`,
    /// takže mají autora `ondrajodas` a viewer sám stačí (ověřeno na živých datech). Pole je tu
    /// proto, že rozřazení má odpovídat na „čí je tah“, a den, kdy se to rozejde, se pozná jedině
    /// tím, že PR agenta spadne do cizí fronty.
    ///
    /// **Globálně, ne per repo**, jako prompt nebo vzhled: kdo jsem já, z repozitáře neplyne.
    ///
    /// **Od #389 je pole i v okně** — na stránce `Zdroje PR`, v sekci `Moje loginy`, protože je to
    /// otázka identity, tedy tatáž, na kterou odpovídají zdroje. Do #389 se dalo napsat jedině do
    /// souboru a rozřazení fronty tak bylo bez editoru textu nedostupné. Nad seznamem stojí
    /// **přihlášený účet ke čtení** (`Policy.viewerAccount(login:)`): bez něj by prázdný seznam
    /// (běžný stav) vypadal stejně jako nenačtený viewer, a to je stav, ve kterém je **každý** PR
    /// cizí.
    var ownLogins: [String]
    /// Organizace, ve kterých paleta ⌘K hledá repozitáře podle jména (#532).
    ///
    /// **Není to zdroj fronty, a je to celý rozdíl proti `sources`.** Zdroje říkají, co se má
    /// pravidelně tahat, co se počítá do karet, odznaku a automatu; tohle je jen seznam míst, ve
    /// kterých se **hledá**, když chci otevřít nějaký PR ke čtení. Prázdné pole je běžný stav
    /// a znamená, že se v paletě žádná repa nabízet nebudou — nic dalšího z něj neplyne.
    ///
    /// **Globálně, ne per repo**: „kde hledám repa“ z repozitáře neplyne, stejně jako `ownLogins`
    /// nebo prompt.
    ///
    /// Seznam rep každé organizace se drží v cache (`RepositoryCatalog`), protože dotažení je
    /// drahé — nad `keboola` změřeno 46,8 s. Konfigurace tedy nese jen jména organizací, ne data.
    var searchOrganizations: [String]
    /// Sada, která platí, dokud ji nepřebije jazyk nebo repo. Je to ta „hvězdička“
    /// z rozpisu v #24 — druhý zápis téhož by byla past pro toho, kdo soubor čte.
    ///
    /// **Jsou to id nástroje `Skill`, ne slash commandy.** Do #78 tu stálo `code-review`,
    /// což skill vůbec není (je to plugin **command**), takže se nemělo co načíst a model
    /// si domýšlel. Plugin se adresuje `plugin:skill`, uživatelský skill svým jménem.
    var skills: [String]
    /// Výchozí sada podle rozpoznaného jazyka projektu. Prázdná mapa = detekce nic nemění.
    var skillsByLanguage: [ProjectLanguage: [String]]
    /// Kde na disku leží složka kterého skillu (#514). Klíč je id skillu, hodnota cesta.
    ///
    /// **Jediné, k čemu to je, je `Otevřít skill ↗`** v tabulce `Jak si reviewery vedou`. Skill
    /// se pouští jménem (nástroj `Skill` si ho najde sám), takže aplikace jeho složku odjinud
    /// nezná a znát ji nepotřebuje — tohle je zkratka do Finderu, ne cesta k spouštění. Skill,
    /// který tu není, tlačítko **nedostane** (ne zašedlé), viz `Policy.skillFolder(of:in:)`.
    ///
    /// **Editor v okně to nemá schválně.** Zákres (sekce 61) kreslí v Nastavení tabulku
    /// s tlačítkem, ne políčka na cesty — a co v mockupu nakreslené není, se do okna nepřidává.
    /// Píše se to tedy do `config.json`; je to hodnota, kterou člověk nastaví jednou.
    ///
    /// **Globálně, ne per repo**: kde leží složka skillu, je fakt o tomhle stroji, ne o repozitáři.
    var skillFolders: [String: String]
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
    /// Za jak dlouho se běh revieweera zabije (#320), **v minutách**.
    ///
    /// V minutách ze stejného důvodu, z jakého je interval v sekundách a rozpočet
    /// v megabajtech: soubor se edituje ručně a `Duration` se do JSONu kóduje jako dvojice
    /// čísel, kterou nikdo nenapíše. Jméno nese jednotku, aby se nedalo splést s `Duration`.
    ///
    /// **Per repo se přebít dá** (na rozdíl od promptu): velké repo potřebuje víc a je to
    /// vlastnost repa, ne člověka.
    ///
    /// Meze a jejich důvod drží `ReviewTimeout`; hodnota mimo ně se sráží dovnitř
    /// (`Policy.reviewTimeout(minutes:)`) a pojmenuje se pod polem v nastavení.
    var reviewTimeoutMinutes: Int
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
    /// Jakou metodou se merguje vlastní PR (#556). Ve výchozím stavu **squash**.
    ///
    /// Do #556 to byla konstanta v `MergeRequest`; proč se to změnilo, je u `MergeMethod`.
    /// **Výchozí squash proto, že tak se aplikace chovala do #556** — po zavedení pole se nesmí
    /// začít chovat jinak. Je to tatáž úmluva jako u `reviewPrompt` a `reviewTimeoutMinutes`.
    ///
    /// **Není to brána, jen výchozí hodnota.** Bránu drží `allowsPublishing`: s vypnutým
    /// odesíláním se nemergne nic, ať je tady cokoli. Proto to v okně leží na stránce `Odesílání`
    /// **pod** ní, ne vedle — obráceně by to vypadalo, že se metodou odesílání zapíná.
    ///
    /// **Metodu, kterou konkrétní repozitář nepovoluje, jde tady vybrat** — globální hodnota platí
    /// pro všechna repa a o kterémkoli z nich se odsud nedá nic tvrdit. Že ji tenhle konkrétní
    /// repozitář nepustí, se pozná v potvrzení, tedy dřív, než se cokoli mergne
    /// (`Policy.mergeMethodWarning`).
    var mergeMethod: MergeMethod
    /// Smí se na **vlastním** PR pustit agent sám, po cizí aktivitě (#510)? Ve výchozím stavu
    /// **ne**.
    ///
    /// **Je to brána, ne pohodlí**, a je to tatáž třída jako `allowsPublishing`: od #510 startuje
    /// zapisující session (#467) poprvé **bez kliknutí**, takže vlastnost „samo nic nezačne“ drží
    /// jedině **výchozí vypnuto**. Dokud si o to někdo výslovně neřekne, nespustí se nic — a ani
    /// potom nic neodejde: commit zůstane v kopii repa a do remote se sáhne jedině přes potvrzení
    /// force pushe (#466).
    ///
    /// **Globálně i per repo**, ze stejného důvodu jako odesílání: je to vlastnost **repa** (v tomhle
    /// repu chci po Copilotovi opravit samo, ve firemním ne), ne toho, kdo se dívá.
    var autoAgent: Bool
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
    /// Jméno MCP nástroje, kterým se čte **text issue** do zadání pro reviewera (#345) — na tomhle
    /// stroji `mcp__claude_ai_Linear__get_issue`.
    ///
    /// **`nil` (i prázdno) znamená „netahat“**, ne prázdný pokus: session, která nemá co zavolat,
    /// stojí boot (~$0,2) a nevrátí nic. Vyhodnocuje to `Policy.issueTextTool(from:)`.
    ///
    /// **Do konfigurace to patří proto, že je to fakt o prostředí, ne volba chování.** Jméno
    /// závisí na tom, jak si uživatel pojmenoval MCP server, takže konstanta v kódu by byla
    /// tvrzení o cizím stroji. Přepínač „tahat / netahat“ tady naopak **není** — o ceně se
    /// rozhodlo jednou (tahá se vždycky, i v automatu) a knoflík, který si nikdo nenastaví, je
    /// jen řádek v okně.
    ///
    /// **Od #389 je pole i v okně** — na stránce `Review a skilly`, v sekci `Text issue z trackeru`,
    /// hned pod promptem: je to materiál zadání, tedy tatáž otázka jako prompt. Do #389 se dalo
    /// napsat jedině do souboru, takže celé #345 bylo bez editoru textu nedostupné. Že prázdno
    /// znamená `netahat` a že jméno bez prefixu `mcp__` session nezavolá, říká **věta pod polem**
    /// (`Policy.issueTextToolNote(for:)`) — jinak by se prázdno čtlo jako porucha.
    ///
    /// **Globálně, ne per repo**: který nástroj čte issues, z repozitáře neplyne.
    var issueTextTool: String?
    /// Po pushi se reviewer ptá **jen na přírůstek** a staré nálezy dostane jako materiál (#517).
    ///
    /// **Výchozí zapnuto**, a je to jedna ze **dvou** výchozích hodnot v tomhle souboru, které
    /// přidávají chování (druhá je `dockBadge` z #529) — proto k ní patří důvod: přírůstek nic
    /// neztrácí. Nálezy z minula se přenášejí na novou hlavu s odznakem
    /// `trvá / vyřešeno / nejasné`, a co běh neposoudil, zůstane v okně
    /// jako `bez odpovědi`. Vypnuto by proti tomu znamenalo platit za druhé přečtení celého diffu
    /// a k tomu **přijít** o odpověď na „co ze starých nálezů trvá“ — dnes ji dává až kontrola
    /// (#150), tedy další session.
    ///
    /// Že je to pravda i v provozu, drží dvě pojistky v `Policy.reviewScope`: bez doběhlého běhu
    /// z minula a bez společné historie se jde na celé review, a v `Průběhu` je vidět proč.
    ///
    /// **Per repo se přebít dá** (jako režim nebo limit): velké repo s dlouhými PR z toho těží
    /// nejvíc, malé se v prvním kole přečte celé tak jako tak.
    var incrementalAfterPush: Bool
    /// V čem se otevírají soubory z kopie v cache (#530). **Výchozí `nil` = tlačítko se nekreslí.**
    ///
    /// Je to jediná hodnota v tomhle souboru, jejíž prázdno znamená **„tahle akce v okně není“**,
    /// a je to schválně: který editor člověk používá, se z ničeho odvodit nedá. Podstrčit Xcode
    /// jen proto, že je to macOS, by znamenalo tlačítko, které spustí cizí aplikaci, o kterou nikdo
    /// nežádal — a zašedlé tlačítko sem nepatří, protože se ten stav nemění ničím, co je na téhle
    /// obrazovce (viz `CLAUDE.md`, tvrdá podmínka č. 1 bod 2).
    ///
    /// **Globálně, ne per repo**, jako `diffLayout` a `appearance`: v čem čtu kód, je vlastnost
    /// toho, kdo se dívá, ne repozitáře, na který se dívá.
    var externalEditor: ExternalEditor?
    /// Co se počítá do odznaku v Docku (#529).
    ///
    /// **Výchozí `waiting`**, tedy druhá výchozí hodnota v tomhle souboru, která přidává chování
    /// (první je `incrementalAfterPush` výš) — a důvod je celé zadání #529: o frontě se dneska
    /// dozvím jen z otevřeného okna nebo z notifikace, která přijde jednou a zmizí. Vypnuté by to
    /// znamenalo přidat přepínač, o kterém se nikdo nedozví.
    ///
    /// **Do konfigurace to patří, protože je to preference, ne stav systému** — na rozdíl od
    /// přihlašovací položky ze stejného issue, kterou `config.json` **nedrží** a čte se zpátky ze
    /// systému (`Policy.loginItem`). Druhá kopie systémového stavu by po ručním vypnutí v Nastavení
    /// systému ukazovala v okně opak toho, co platí.
    ///
    /// **Globálně, ne per repo**: dlaždice je jedna a mluví o celé frontě.
    var dockBadge: DockBadgeMode
    /// Kdy se skládá brief na domově (#516). **Výchozí vypnuto** — proč, je u `BriefMode`.
    ///
    /// **Globálně, ne per repo**, jako `quietHours` a `dockBadge`: brief mluví o **celé desce**,
    /// tedy o všech repozitářích naráz, takže hodnota na repo by neměla co znamenat. Je to rozdíl
    /// proti `autoAgent`, který se rozhoduje nad jedním pull requestem.
    var brief: BriefMode

    /// Velké PR odložit do tichých hodin (#519). **Výchozí vypnuto** — proč, je u `QuietHours`.
    ///
    /// **Globálně, ne per repo**, jako `appearance` a `diffLayout`: kdy chci mít na stroji ticho,
    /// z repozitáře neplyne. Je to jediná hodnota o **automatu**, kterou si repo přebít nesmí —
    /// režim, sada skillů i přírůstek jsou o tom, *co* se pouští, tohle o mém dni.
    var quietHours: QuietHours
    /// Co se má hlásit notifikací (#86). Jen globálně — viz `NotificationSettings`.
    var notifications: NotificationSettings

    init(
        sources: [Source],
        ownLogins: [String] = [],
        searchOrganizations: [String] = [],
        skills: [String],
        skillsByLanguage: [ProjectLanguage: [String]] = [:],
        skillFolders: [String: String] = [:],
        blockingCategories: [String],
        reviewPrompt: String = ReviewPromptTemplate.standard,
        reviewTimeoutMinutes: Int = ReviewTimeout.standardMinutes,
        mode: ReviewMode,
        allowsPublishing: Bool = false,
        mergeMethod: MergeMethod = .squash,
        autoAgent: Bool = false,
        findingsLanguage: FindingsLanguage = .czech,
        diffLayout: DiffLayout = .unified,
        appearance: AppearanceMode = .system,
        pollIntervalSeconds: Int,
        maxConcurrentReviews: Int,
        autoRunsPerDay: Int = 20,
        cacheBudgetMegabytes: Int,
        model: String?,
        issueTextTool: String? = nil,
        incrementalAfterPush: Bool = true,
        externalEditor: ExternalEditor? = nil,
        dockBadge: DockBadgeMode = .waiting,
        brief: BriefMode = .off,
        quietHours: QuietHours = QuietHours(),
        notifications: NotificationSettings = NotificationSettings()
    ) {
        self.sources = sources
        self.ownLogins = ownLogins
        self.searchOrganizations = searchOrganizations
        self.skills = skills
        self.skillsByLanguage = skillsByLanguage
        self.skillFolders = skillFolders
        self.blockingCategories = blockingCategories
        self.reviewPrompt = reviewPrompt
        self.reviewTimeoutMinutes = reviewTimeoutMinutes
        self.mode = mode
        self.allowsPublishing = allowsPublishing
        self.mergeMethod = mergeMethod
        self.autoAgent = autoAgent
        self.findingsLanguage = findingsLanguage
        self.diffLayout = diffLayout
        self.appearance = appearance
        self.pollIntervalSeconds = pollIntervalSeconds
        self.maxConcurrentReviews = maxConcurrentReviews
        self.autoRunsPerDay = autoRunsPerDay
        self.cacheBudgetMegabytes = cacheBudgetMegabytes
        self.model = model
        self.issueTextTool = issueTextTool
        self.incrementalAfterPush = incrementalAfterPush
        self.externalEditor = externalEditor
        self.dockBadge = dockBadge
        self.brief = brief
        self.quietHours = quietHours
        self.notifications = notifications
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Configuration.standard.global
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? standard.sources
        // Chybějící klíč = prázdné pole, tedy „jsem to jen já“. **Hodnota jiného typu položí
        // čtení** (`try`, ne `try?`), stejně jako u `sources` a `skills`: tiše podstrčené prázdno
        // by z PR mého agenta udělalo cizí PR, tedy řádek ve frontě k review, o které nikdo
        // nepožádal — a to je zrovna to rozřazení, kvůli kterému pole existuje.
        ownLogins = try container.decodeIfPresent([String].self, forKey: .ownLogins) ?? standard.ownLogins
        // Chybějící klíč = prázdné pole, tedy „v paletě se repa nehledají“ — chování před #532.
        // **Hodnota jiného typu položí čtení** (`try`, ne `try?`), jako u `sources`, `skills`
        // a `ownLogins`: tiše podstrčené prázdno by vypadalo jako organizace, ve které nejsou
        // žádná repa, a člověk by hledal chybu v `gh` místo v čárce v souboru.
        searchOrganizations = try container.decodeIfPresent([String].self, forKey: .searchOrganizations)
            ?? standard.searchOrganizations
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? standard.skills
        // Rozbitá mapa se hlásí ze stejného důvodu jako rozbité `skills`: tiše podstrčený
        // výchozí (prázdný) obsah by na jazykových repech pustil jiné reviewery, než jaké
        // tam měly běžet.
        skillsByLanguage = try container.decodeIfPresent([ProjectLanguage: [String]].self, forKey: .skillsByLanguage)
            ?? standard.skillsByLanguage
        // Rozbitá mapa se hlásí ze stejného důvodu jako rozbité `skillsByLanguage`: tiše
        // podstrčené prázdno by znamenalo, že u skillu, ke kterému je cesta zapsaná, tlačítko
        // `Otevřít skill ↗` prostě není — a to vypadá jako vlastnost aplikace, ne jako překlep
        // v souboru.
        skillFolders = try container.decodeIfPresent([String: String].self, forKey: .skillFolders)
            ?? standard.skillFolders
        blockingCategories = try container.decodeIfPresent([String].self, forKey: .blockingCategories)
            ?? standard.blockingCategories
        // Chybějící klíč = výchozí text. **Hodnota jiného typu položí celé čtení** — `try`, ne
        // `try?`, a je to schválně: kdyby se místo čísla, pole nebo objektu tiše dosadil výchozí
        // prompt, běželo by review s jiným zadáním, než jaké si někdo napsal, a nic by na to
        // neupozornilo. Takhle se v okně ukáže „Konfiguraci se nepodařilo přečíst“ a soubor
        // se nepřepíše. Tolerantní čtení tím neporušuje: tolerantní je vůči **chybějícímu**
        // klíči, ne vůči hodnotě, které se nedá rozumět.
        //
        // **`null` se přitom počítá jako chybějící klíč** (`decodeIfPresent` ho tak bere) a je to
        // tak správně, ne opomenutí: `null` není hodnota, které by se nedalo rozumět — je to
        // výslovné „nic tu není“, tedy totéž, co u téhle šablony znamená prázdný řetězec
        // („ber výchozí“). Rozlišovat je přes `container.contains(_:)` by tady vyrobilo třetí
        // odpověď na tutéž otázku a odchýlilo se od `sources` a `skills`, tedy zbylých dvou klíčů,
        // u kterých se rozbitá hodnota hlásí. Je na to test, aby se ta úvaha nemusela dělat znovu.
        reviewPrompt = try container.decodeIfPresent(String.self, forKey: .reviewPrompt)
            ?? standard.reviewPrompt
        // Chybějící klíč = patnáct minut, tedy chování před #320. Číslo **mimo meze se
        // nezahazuje ani nepoloží čtení** — sráží ho `Policy.reviewTimeout(minutes:)` až tam, kde
        // se používá, a nastavení u pole napíše, kolik je v souboru a s čím se poběží. Držet
        // v konfiguraci syrovou hodnotu je podmínka toho, aby se to dalo napsat: sražená při čtení
        // by z „napsal jsem 120“ udělala „vždycky tam bylo 60“.
        //
        // Hodnota **jiného typu** čtení položí (`try`, ne `try?`), stejně jako u ostatních čísel:
        // `"patnáct"` není hodnota, které by se dalo rozumět, a tiše podstrčený default by znamenal
        // limit, o který nikdo neřekl.
        reviewTimeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .reviewTimeoutMinutes)
            ?? standard.reviewTimeoutMinutes
        // Neznámý režim se bere jako `manual` ze stejného důvodu jako u repa: samo od sebe
        // se nemá spouštět nic, a překlep v souboru není důvod pustit reviewery na všechno.
        mode = (try? container.decode(ReviewMode.self, forKey: .mode)) ?? standard.mode
        // Rozbitá hodnota se srazí na výchozí, a ta je `false`: překlep v souboru nesmí
        // otevřít cestu ven. Je to tatáž přísnost jako u režimu a opačná než u jazyka
        // nálezů, kde je nejhorším následkem próza v jiném jazyce.
        allowsPublishing = (try? container.decode(Bool.self, forKey: .allowsPublishing))
            ?? standard.allowsPublishing
        // **Rozbitá hodnota se srazí na výchozí, a ta je `squash`** (#556) — tedy na chování
        // aplikace do #556. Přísnost jako u odesílání by tady nechránila nic (metodou se cesta ven
        // neotevírá), ale ani mírnost jako u vzhledu nestačí: metoda je součást payloadu nevratné
        // akce, takže překlep nesmí vyrobit jinou. Squash je ta jediná hodnota, o které se dá
        // tvrdit, že se s ní aplikace chová jako dřív — a v potvrzení je pořád vidět, co odejde.
        mergeMethod = (try? container.decode(MergeMethod.self, forKey: .mergeMethod))
            ?? standard.mergeMethod
        // **Rozbitá hodnota se srazí na výchozí, a ta je `false`** (#510) — tatáž přísnost jako
        // u odesílání a ze stejného důvodu: překlep v souboru nesmí pustit session, která píše do
        // souborů, a to bez jediného kliknutí.
        autoAgent = (try? container.decode(Bool.self, forKey: .autoAgent)) ?? standard.autoAgent
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
        // Jako `model`, a se stejným odůvodněním: chybějící klíč je „netahat“, kdežto hodnota
        // **jiného typu položí čtení** (`try`, ne `try?`). Tiše zahozený překlep by znamenal, že
        // se text issue nikdy nedotáhne a v okně bude stát „nástroj není nastavený“ nad souborem,
        // ve kterém nastavený je.
        issueTextTool = try container.decodeIfPresent(String.self, forKey: .issueTextTool)
        // Chybějící klíč = výchozí, tedy **zapnuto** (#517). Rozbitá hodnota se ale nesráží na
        // výchozí, jako u režimu a odesílání, nýbrž na **`false`** — a je to tentýž princip, ne
        // výjimka z něj: sráží se na **bezpečnou stranu**, a ta je tady opačná než default. Celé
        // review přečte víc kódu, takže překlep v souboru nesmí skončit tím, že se přírůstkově
        // přeskočí něco, co nikdo nečetl.
        incrementalAfterPush = container.contains(.incrementalAfterPush)
            ? ((try? container.decode(Bool.self, forKey: .incrementalAfterPush)) ?? false)
            : standard.incrementalAfterPush
        // Chybějící klíč **i rozbitá hodnota** znamenají `nil`, tedy „tlačítko se nekreslí“ (#530)
        // — a je to tentýž princip jako všude jinde, tedy srazit se na **bezpečnou stranu**. Ta je
        // tady shodou okolností i výchozí: neznámé jméno editoru nesmí podstrčit jiný, protože
        // tlačítko spouští cizí aplikaci. Chybějící akce je proti tomu stav, o kterém se dá
        // rozhodnout jedním pohledem do nastavení.
        externalEditor = try? container.decodeIfPresent(ExternalEditor.self, forKey: .externalEditor)
        // Tolerantně jako vzhled a pohled na diff, ne přísně jako režim nebo odesílání (#529):
        // nejhorší následek překlepu je **jiné číslo v Docku**, které se přepne jedním kliknutím
        // v nastavení — nespustí review, neodešle nic a nedá se z něj nic ztratit. Přísnost jako
        // u `incrementalAfterPush` by tady nechránila nic: tam se sráží na `false`, protože
        // bezpečná strana je „přečti víc kódu“, kdežto u odznaku žádná bezpečná strana není.
        dockBadge = (try? container.decode(DockBadgeMode.self, forKey: .dockBadge)) ?? standard.dockBadge
        // **Rozbitá hodnota se srazí na výchozí, a ta je `off`** (#516) — tatáž přísnost jako
        // u odesílání a u agenta (#510) a opačná než u odznaku v Docku o řádek výš: překlep
        // v souboru nesmí pustit session, která stojí peníze, a `firstTickOfDay` ji pouští **bez
        // kliknutí**. Bezpečná strana tady je, a je to „nezačne se nic“.
        brief = (try? container.decode(BriefMode.self, forKey: .brief)) ?? standard.brief
        // Tolerantně, jako odznak v Docku (#519): `QuietHours` si rozbité klíče srazí sám po
        // jednotlivých polích, takže se celé okno nezahodí kvůli jedné hodině. Bezpečná strana je
        // tady navíc v samotném pravidle — nesmyslné okno odklad **vypne**
        // (`Policy.quietHoursAreUsable`), takže se překlepem nedá review zastavit, jen neodložit.
        quietHours = try container.decodeIfPresent(QuietHours.self, forKey: .quietHours)
            ?? standard.quietHours
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
    /// `nil` = ber globální (#556). Vyplněná hodnota znamená „řekl jsem si o tohle“.
    ///
    /// **Metoda merge je zvyk repozitáře, ne člověka**, a proto to override má: tenhle repo
    /// squashuje, firemní repo s prořezanou historií chce merge commit. Je to tatáž třída jako
    /// `mode` nebo `incrementalAfterPush` — a **ne** jako `diffLayout` a `appearance`, které
    /// override schválně nemají, protože jsou vlastností toho, kdo se kouká. Tohle je vlastnost
    /// toho, **do čeho se merguje**.
    ///
    /// Na rozdíl od globální úrovně tady nabídka **nepovolenou metodu vybrat nedovolí**: repo je
    /// jedno a jeho příznaky se dají přečíst, takže se do souboru nedá uložit hodnota, se kterou
    /// by merge skončil chybou z API. Když se povolení na GitHubu změní **až potom**, uložená
    /// hodnota v souboru zůstane — a pozná se to v potvrzení, ne z chyby.
    var mergeMethod: MergeMethod?
    /// `nil` = ber globální (#510). Vyplněná hodnota znamená „řekl jsem si o tohle“ — a `false`
    /// u repa se proto **nesmaže** jako „shodné s globálním“, přesně jako u odesílání: repo, ve
    /// kterém agenta spouštět nechci, si to má podržet i po přepnutí globálního defaultu.
    var autoAgent: Bool?
    /// `nil` = ber globální. U firemního repa s mezinárodním týmem dává smysl angličtina,
    /// i když je zbytek fronty český.
    var findingsLanguage: FindingsLanguage?
    /// **Nahrazuje** globální sadu, neslučuje se s ní — smysl je vyhodit PHP skilly na Go
    /// repu. Prázdné pole je vlastní odpověď („tady nereviewuj nic“), `nil` znamená
    /// „ber globální“.
    var skills: [String]?
    var blockingCategories: [String]?
    /// `nil` = ber globální. Velké repo potřebuje delší limit a je to vlastnost **repa**, ne
    /// člověka — proto to má override, na rozdíl od promptu, pohledu na diff a vzhledu okna.
    var reviewTimeoutMinutes: Int?
    /// `nil` = ber globální (#517). Vyplněná hodnota znamená „řekl jsem si o tohle“ — a `false`
    /// u repa se proto **nesmaže** jako „shodné s globálním“, stejně jako u odesílání: repo, u
    /// kterého chci po pushi vždycky celé review, si to má podržet i po přepnutí globálního
    /// defaultu.
    var incrementalAfterPush: Bool?
    /// Na kterých cestách se který reviewer pouští (#518). Klíčem je skill, hodnotou vzory cest
    /// (`src/Auth/**`, `*.env*`, `composer.lock`) — jejich význam je u `Policy.pathMatches`.
    ///
    /// **Jediný klíč, který globální dvojče nemá, a je to rozhodnutí.** Ostatní override odpovídají
    /// na otázku, na kterou má smysl odpovědět i globálně („jak dlouho smí běh běžet“), kdežto
    /// cesty popisují **rozvržení tohohle repa**: `src/Auth/**` v jednom repu neznamená nic
    /// v druhém. Globální mapa by tedy byla pravidlo, které je skoro všude vedle — a přeskočený
    /// reviewer je ta nejtišší podoba chybějícího review.
    ///
    /// Chybějící klíč a **prázdná mapa** jsou tady totéž („žádné pravidlo“), na rozdíl od `skills`,
    /// kde je prázdný seznam vlastní odpověď. Důvod je u `ReviewerRouting`: pravidlo, ve kterém
    /// nezůstal vzor, se pouští, protože prázdná tabulka nastavení je mezistav, ne pokyn.
    var reviewerPaths: [String: [String]]?

    init(
        mode: ReviewMode? = nil,
        allowsPublishing: Bool? = nil,
        mergeMethod: MergeMethod? = nil,
        autoAgent: Bool? = nil,
        findingsLanguage: FindingsLanguage? = nil,
        skills: [String]? = nil,
        blockingCategories: [String]? = nil,
        reviewTimeoutMinutes: Int? = nil,
        incrementalAfterPush: Bool? = nil,
        reviewerPaths: [String: [String]]? = nil
    ) {
        self.mode = mode
        self.allowsPublishing = allowsPublishing
        self.mergeMethod = mergeMethod
        self.autoAgent = autoAgent
        self.findingsLanguage = findingsLanguage
        self.skills = skills
        self.blockingCategories = blockingCategories
        self.reviewTimeoutMinutes = reviewTimeoutMinutes
        self.incrementalAfterPush = incrementalAfterPush
        self.reviewerPaths = reviewerPaths
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
        // Jako na globální úrovni (#556): chybějící klíč je „ber globální“, kdežto **rozbitá
        // hodnota se srazí na `squash`**, tedy na chování aplikace do #556. Vzít u ní globální
        // hodnotu by znamenalo, že překlep v repu, u kterého jsem si squash řekl výslovně, ho
        // přepne na globální merge commit — a to je metoda nevratné akce, ne popisek.
        if container.contains(.mergeMethod) {
            mergeMethod = (try? container.decode(MergeMethod.self, forKey: .mergeMethod)) ?? .squash
        } else {
            mergeMethod = nil
        }
        // Jako u odesílání (#510): chybějící klíč je „ber globální“, ale **rozbitá hodnota se srazí
        // na `false`**. Vzít u ní globální hodnotu by znamenalo, že překlep v repu, ve kterém se
        // agent někdo pokoušel zakázat, ho při globálním povolení nechá zapnutého — a spouští se
        // bez kliknutí.
        if container.contains(.autoAgent) {
            autoAgent = (try? container.decode(Bool.self, forKey: .autoAgent)) ?? false
        } else {
            autoAgent = nil
        }
        // Na rozdíl od režimu se rozbitá hodnota bere jako „nic jsem neřekl“: špatný jazyk
        // znamená prózu v jiném jazyce, ne spuštěné review, o které nikdo nežádal.
        findingsLanguage = try? container.decodeIfPresent(FindingsLanguage.self, forKey: .findingsLanguage)
        skills = try container.decodeIfPresent([String].self, forKey: .skills)
        blockingCategories = try container.decodeIfPresent([String].self, forKey: .blockingCategories)
        // Jako globální úroveň: chybějící klíč je „ber globální“, hodnota jiného typu položí čtení
        // a číslo mimo meze se drží syrové a srazí se až při použití. Přísnost jako u režimu tu
        // nemá co chránit — delší limit nic nespustí a nic neodešle, jen dovolí běhu doběhnout.
        reviewTimeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .reviewTimeoutMinutes)
        // Jako na globální úrovni (#517): chybějící klíč je „ber globální“, kdežto **rozbitá
        // hodnota se srazí na `false`**, tedy na celé review. Vzít u ní globální hodnotu by
        // znamenalo, že překlep v repu, u kterého jsem si přírůstek zakázal, ho zapne.
        if container.contains(.incrementalAfterPush) {
            incrementalAfterPush = (try? container.decode(Bool.self, forKey: .incrementalAfterPush))
                ?? false
        } else {
            incrementalAfterPush = nil
        }
        // Routing (#518) — **rozbitá hodnota se bere jako „nic jsem neřekl“**, tedy jako u jazyka
        // nálezů a na opačnou stranu než u režimu. Tady je totiž bezpečná strana ta druhá: chybný
        // zápis vzorů srazit na „mám pravidlo“ by znamenalo reviewera, který se nikdy nepustí,
        // a chybějící review je tišší ztráta než review, o které nikdo nežádal.
        reviewerPaths = try? container.decodeIfPresent([String: [String]].self, forKey: .reviewerPaths)
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
    ///
    /// **Výjimka je `sources`** (#330): od té doby je v nich vedle `reviewRequested` i `mine`,
    /// takže se aplikace se **prázdnou cache** chová jinak než dřív — v seznamu jsou i vlastní PR.
    /// Je to vědomé a je to podmínka toho, aby sekce `Moje PR` (#331) měla odkud brát data: kdo si
    /// ten řádek nedopíše ručně, měl by ji navždycky prázdnou. **Existující `config.json` to
    /// nespraví** a nemigruje se — `decodeIfPresent` vezme uložené `sources` a nový zdroj se
    /// nedoplní; že chybí, pozná `Policy.tracksOwnPullRequests` a řekne to prázdný stav sekce.
    static let standard = Configuration(
        global: GlobalConfig(
            sources: [.reviewRequested, .mine],
            skills: ["code-review:code-review"],
            blockingCategories: Policy.defaultBlockingCategories.sorted(),
            // Doslova ten text, co byl do #281 v kódu — po zavedení pole se aplikace nesmí
            // začít chovat jinak. Hlídá to test, který složený prompt porovnává znak po znaku.
            reviewPrompt: ReviewPromptTemplate.standard,
            // Patnáct minut — doslova ta hodnota, co byla do #320 v `ClaudeReviewRunner`.
            // Hlídá to test, který ji porovnává s číslem, ne s konstantou.
            reviewTimeoutMinutes: ReviewTimeout.standardMinutes,
            mode: .manual,
            allowsPublishing: false,
            // Doslova to, co bylo do #556 v konstantě `MergeRequest.method` — po zavedení pole se
            // aplikace nesmí začít chovat jinak. Hlídá to test, který ji porovnává s literálem.
            mergeMethod: .squash,
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
            mergeMethod: overrides?.mergeMethod ?? global.mergeMethod,
            autoAgent: overrides?.autoAgent ?? global.autoAgent,
            findingsLanguage: overrides?.findingsLanguage ?? global.findingsLanguage,
            skills: Self.nonBlank(overrides?.skills ?? global.skills),
            blockingCategories: Set(Self.nonBlank(overrides?.blockingCategories ?? global.blockingCategories)),
            // Sráží se **až tady**, na jednom místě a pro obě úrovně naráz: kdyby se sráželo při
            // čtení souboru, přišlo by se o rozdíl mezi „napsal jsem 120“ a „mám 60“, a nastavení
            // by neměl kdo pojmenovat.
            reviewTimeout: Policy.reviewTimeout(
                minutes: overrides?.reviewTimeoutMinutes ?? global.reviewTimeoutMinutes
            ),
            incrementalAfterPush: overrides?.incrementalAfterPush ?? global.incrementalAfterPush,
            // Routing (#518) nemá globální úroveň, takže se nic nepřebíjí — prázdná mapa je
            // „žádné pravidlo“, tedy stav, ve kterém se pouští celá sada jako do #518. Proč
            // globální mapa nevznikla, je u `RepositoryConfig.reviewerPaths`.
            reviewerPaths: overrides?.reviewerPaths ?? [:]
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
    /// Jakou metodou se merguje vlastní PR (#556) — **výchozí hodnota, ne rozkaz**: potvrzení ji
    /// vypisuje a dovolí přebít pro jeden merge, a jestli ji repozitář vůbec pustí, rozhoduje
    /// `Policy.initialMergeMethod` z příznaků přečtených z GitHubu.
    let mergeMethod: MergeMethod
    /// Smí se na vlastním PR v tomhle repu pustit agent sám (#510)? **Výchozí `false`** — je to
    /// brána, tedy tatáž třída jako `allowsPublishing`, ne předvolba.
    let autoAgent: Bool
    let findingsLanguage: FindingsLanguage
    let skills: [String]
    let blockingCategories: Set<String>
    /// Limit jednoho běhu (#320), **už sražený do mezí** — kdo si ho odsud vezme, nemá co dál
    /// kontrolovat. Předává se do `ReviewRequest`, ne čte v runneru.
    let reviewTimeout: Duration
    /// Smí se po pushi ptát jen na přírůstek (#517)? Rozhodnutí z toho skládá
    /// `Policy.reviewScope` — tady je jen brána, kterou si repo přebít smí.
    let incrementalAfterPush: Bool
    /// Na kterých cestách se který reviewer pouští (#518). Prázdná mapa = žádné pravidlo, tedy
    /// celá sada jako do #518. Rozhodnutí z toho skládá `Policy.reviewersToRun(files:rules:)`
    /// — tady je jen surová konfigurace, i s prázdnými řádky z tabulky nastavení.
    let reviewerPaths: [String: [String]]
}
