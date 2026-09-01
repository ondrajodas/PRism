import Foundation
import Observation

/// Stav aplikace, který kreslí okno.
///
/// Drží polling seznamu PR, výběr řádku a stav pracovních kopií. Výběr žije tady, ne ve
/// view — jinak by ho každé přestavění seznamu zahodilo. Postupně sem přibude stav
/// běžících review a limit souběžných session.
@MainActor
@Observable
final class AppStore {
    /// Který řádek je vybraný.
    var selection: PRIdentifier?

    /// Poslední známé shrnutí otevřeného PR (#180).
    ///
    /// Bez toho by záložka zmizela ve chvíli, kdy PR vypadne z pollingu — a to je přesně to, co
    /// se stane po odeslání review, protože tím padá `review-requested`. Zůstal by obsah, který
    /// říká „pull request zmizel“, a **nebylo by ho čím zavřít**. Nálezem Copilota na #201; do té
    /// doby se seznam záložek skládal jen z živých dat a dokumentace tvrdila opak.
    var openTabSnapshots: [PRIdentifier: PullRequestSummary] = [:]

    /// Otevřená review jako záložky (#180), v pořadí, ve kterém se otevřela.
    ///
    /// **Jen seznam identifikátorů.** Všechno ostatní — diff, konverzace, draft, běh — visí ve
    /// store na `PRIdentifier` už dneska, takže záložka nic nevlastní a zavřít ji nesmí nic
    /// zahodit: rozdělané review leží na disku a běžící review běží dál.
    var openTabs: [PRIdentifier] = []

    /// Která záložka je vidět.
    var activeTab: WindowTab = .home

    /// Co je vidět v domácí záložce. Startuje se na **přehledu** (#181) — je to obrazovka,
    /// která odpovídá na „co dneska hoří“, a to je první otázka po spuštění.
    var railSection: RailSection = .overview

    /// Zúžení seznamu na vybraná repa a autory (#117).
    ///
    /// **Drží ho store, ne view:** `PullRequestListView` se přestavuje při každém tiku, takže
    /// `@State` by filtr zahodil — tatáž past jako u výběru řádku a sbalených souborů.
    ///
    /// **Nepřežije restart** a je to jediný stav v okně, který umí PR **schovat úplně** — restart je
    /// proto pojistka proti zapomenutému filtru, protože zmizelý PR vypadá jako vyřízený. Na trvalé
    /// schování je `sources` v konfiguraci (dotaz umí i `-author:`); to je změna toho, co se
    /// stahuje, a patří do nastavení, ne do lišty.
    ///
    /// Zapsat ho jde jedině `setFilter(_:)`, protože se s ním musí srovnat výběr.
    private(set) var filter = PullRequestFilter()

    /// Stav pracovní kopie **per repo**. Co v mapě není, v cache není.
    ///
    /// Jediný zdroj pravdy o checkoutu: `ReviewState` pro řádek se z něj odvozuje
    /// (`Policy.reviewState(for:)`) a `busy` pro eviction taky. Dvě mapy s různými klíči
    /// si dokázaly odporovat — jedno PR hlásilo selhání nad klonem, který mezitím pro
    /// druhé PR téhož repa v pořádku vznikl.
    var checkoutStates: [RepoID: CheckoutState] = [:]

    /// Co se s review právě děje. Co v mapě není, neběží.
    var reviewPhases: [PRIdentifier: ReviewPhase] = [:]

    /// Poslední známý výsledek per PR — z disku při startu, pak z doběhlých běhů.
    ///
    /// Na disku je záznamů víc (historie po commitech), tady je vždycky jen ten platný;
    /// který to je, rozhoduje `Policy.currentRecords(from:)`.
    var reviewRecords: [PRIdentifier: ReviewRecord] = [:]

    /// Diff **per PR**. Co v mapě není, se ještě nenačítalo.
    var diffStates: [PRIdentifier: DiffState] = [:]

    /// Diff „co od minule přibylo“ **per PR** (#284). Co v mapě není, se nevyžádalo — a tab
    /// `Změněné soubory` pak kreslí celý diff.
    ///
    /// **Vedle `diffStates`, ne místo nich**: celý diff je to, proti čemu se píše review, takže
    /// ho pohled na rozsah nesmí zahodit. Zapíná se výhradně tlačítkem v pruhu „od tvé poslední
    /// návštěvy“ a vypíná se v liště nad rozsahem.
    var incrementalDiffs: [PRIdentifier: IncrementalDiff] = [:]

    /// Detail **per PR** — kvůli `headSha`, proti kterému se píše rozdělané review.
    ///
    /// Dotahuje se při výběru řádku, ne pollingem: pro všech N PR by to byla tatáž N+1 past,
    /// kvůli které se netahá konverzace. Cache podle `updatedAt` je stejná jako u diffu.
    var detailStates: [PRIdentifier: DetailState] = [:]

    /// Který tab PR je vidět, **per PR**. Co v mapě není, je na `PullRequestTab.standard`.
    ///
    /// Drží se odchylka od výchozího stavu, ne volba u každého PR — stejný vzor jako
    /// u překliknutých vláken. Ve view to být nemůže: `PullRequestDetailView` si SwiftUI mezi
    /// pull requesty ponechá, takže by volba přetekla z jednoho na druhý.
    var detailTabs: [PRIdentifier: PullRequestTab] = [:]

    /// Je panel vpravo od diffu rozložený?
    ///
    /// **Globálně, ne per PR** — je to předvolba pohledu, stejně jako `diffLayout`: kolik místa
    /// chci dát panelu, znamená u každého PR totéž.
    ///
    /// **Ve store, ne v `@State` detailu** (#242), a je to podmínka, ne úklid: poznámka do těla
    /// review přidaná z diffu spadne do panelu, takže se panel musí umět **rozložit sám** —
    /// a dokud ta rozhodnutí bydlela ve view, nešlo je otestovat. Tichá ztráta rozepsané věty je
    /// přitom to nejdražší, co tady umí zmizet.
    var isReviewPanelExpanded = true

    /// Co je v panelu vidět. Ze stejného důvodu tady, ne ve view: doručení poznámky panel
    /// **přepne** na rozdělané review, a to se musí dát otestovat.
    ///
    /// Který ze dvou tabů to na daném PR je, překládá `Policy.reviewPanelTab(_:for:)` (#333) —
    /// `draft` na vlastním PR není a `agentPrompt` na cizím.
    var reviewPanelTab: ReviewPanelTab = .findings

    /// Co jde do zadání pro agenta (#333).
    ///
    /// **Globálně, ne per PR** — je to předvolba, jak si zadání nechávám skládat, stejně jako
    /// `diffLayout`. A **neukládá se**: výchozí volba (všechno nevyřízené a diff hunk) je ta
    /// správná pro převažující případ, takže by uložený stav jen tiše přenášel „u toho jednoho PR
    /// jsem si přibral vyřešená vlákna“ na všechna další.
    var agentPromptOptions = AgentPromptOptions.standard

    /// Rozdělané review **per PR**. Co v mapě není, se nezačalo psát.
    ///
    /// Načte se celé při startu, ne až při výběru řádku: indikátor v seznamu má být vidět
    /// u všech PR naráz a jsou to kilobajty.
    var drafts: [PRIdentifier: ReviewDraft] = [:]

    /// Kolik souborů s rozdělaným review se nepodařilo přečíst.
    ///
    /// Musí být vidět, a o důvod víc než u nálezů: nález se dá dostat zpátky dalším během,
    /// ručně psané review ne.
    private(set) var unreadableDraftFiles = 0

    /// Proč se rozdělané review nepodařilo uložit.
    ///
    /// Ztracená ručně psaná práce je to nejdražší, co tady umí zmizet — takže se selhání
    /// zápisu nespolkne. Na rozdíl od nálezů se nedá zopakovat žádným během.
    var draftFailure: String?

    /// Proč se reviewerovi nepodařilo připravit zadání (#120).
    ///
    /// Review **doběhne** i bez zadání — zadání bez souboru je horší review, ne rozbité review,
    /// tatáž úvaha jako u nepovedeného překladu nálezů. Mlčet o tom ale nejde: běh, který zadání
    /// nedostal, vypadá v okně **úplně stejně** jako ten, který ho dostal, takže by se z okna
    /// nedalo poznat, proč reviewer o zadání nemluví.
    ///
    /// **Jeden řetězec pro celou aplikaci, jako `draftFailure` a `dismissalFailure`** — je to
    /// „poslední slovo“, ne historie: povedená příprava ho smaže, takže při dvou souběžných
    /// review může hláška prvního zmizet za úspěchem druhého. Proto v ní **stojí, o který PR
    /// jde**; kdyby se ukázalo, že to vadí, je řešením mapa klíčovaná PR a hláška u řádku,
    /// ne trvalá hláška ve stavovém řádku.
    var intentFailure: String?

    /// Proč se nepodařilo uložit odmítnutí nálezu (#113).
    ///
    /// Neuložené odmítnutí se po restartu vrátí a nikdo nebude vědět proč — takže se tady
    /// selhání zápisu nespolkne, stejně jako u draftu. Tichý `try?` by z toho udělal přesně
    /// ten vzor, na který si `CLAUDE.md` stěžuje.
    var dismissalFailure: String?

    /// Poslední **doručená** notifikace (#138). `nil` = od spuštění se nic neohlásilo.
    ///
    /// Posouvá ji jedině `.delivered`, ne pokus o doručení: jinak by stavový řádek tvrdil, že
    /// něco odešlo, i když to systém odmítl — tedy přesně to mlčení vydávané za funkčnost,
    /// kvůli kterému issue vzniklo.
    var lastDeliveredNotification: DeliveredNotification?

    /// Proč notifikace nechodí (#88). `nil` = chodí, nebo se ještě žádná neposílala.
    ///
    /// Odmítnuté oprávnění **není chyba běhu** — aplikace jede dál, jen mlčí. Právě proto to
    /// musí být v okně vidět: bez toho se hledá, proč nic nepřichází, a odpověď leží
    /// v Nastavení systému, kam aplikace nedosáhne. Tatáž kategorie jako rozbitá konfigurace:
    /// nesmí položit, nesmí projít tiše.
    var notificationFailure: String?

    /// Konverzace **per PR** — review ostatních, vlákna, komentáře. Co v mapě není, se
    /// ještě nenačítalo.
    var conversationStates: [PRIdentifier: ConversationState] = [:]

    /// Vlákna, u kterých si uživatel překlikl rozbalení proti výchozímu stavu, **per PR**.
    ///
    /// Drží se **odchylka**, ne seznam rozbalených: výchozí stav se odvozuje z vlákna
    /// (nevyřešené rozbalené, vyřešené sbalené), takže seznam rozbalených by se musel plnit
    /// při každém načtení konverzace — a ruční obnovení by uživateli zahodilo, co si zavřel.
    /// Rozhoduje `Policy.isThreadExpanded(_:toggled:)`.
    ///
    /// Klíčem je **PR**, i když `id` vlákna je globálně unikátní a samo by na rozlišení
    /// stačilo. Je to kvůli úklidu: zahazovat se má podle toho, jestli PR zmizel ze seznamu,
    /// a to z `id` vlákna poznat nejde. Plochá množina uklízená podle **načtených** konverzací
    /// se po výpadku sítě (`.failed`) vyprázdnila a uživateli naskočilo výchozí rozbalení.
    var toggledThreads: [PRIdentifier: Set<String>] = [:]

    /// Nálezy, u kterých si uživatel překlikl rozbalení proti výchozímu stavu, **per PR** (#185).
    ///
    /// Zase **odchylka**, ne seznam rozbalených, a ze stejného důvodu jako u vláken: výchozí
    /// stav se odvozuje z nálezů (blokující rozbalený, ostatní značka na hraně řádku), takže
    /// seznam rozbalených by se musel plnit při každém načtení záznamu — a nový běh review by
    /// uživateli zahodil, co si otevřel. Rozhoduje `Policy.disclosure(of:categories:toggled:)`.
    ///
    /// Klíčem je **místo v kódu** (`Policy.disclosureKey(of:)`), ne klíč nálezu: ten nese
    /// `summary`, které si reviewer v dalším běhu přeformuluje. A klíčem mapy je **PR**, aby
    /// se dalo uklízet podle toho, co zmizelo ze seznamu — tatáž úvaha jako u `toggledThreads`.
    var toggledFindings: [PRIdentifier: Set<String>] = [:]

    /// Rozepsané odpovědi do vláken (#73). Co v mapě není, nikdo nerozepsal.
    ///
    /// Žije tady, ne v bublině: ta je buňka líného seznamu nad diffem, takže `@State` v ní
    /// odscrollování nepřežije — tatáž past jako u `DraftTextEditor`. Na disk se to naopak
    /// **neukládá**: je to jedna věta v diskuzi, ne review, a další store by za ni platil
    /// souborem na každé vlákno.
    ///
    /// Zahazuje se s PR mimo seznam, stejně jako konverzace — bez vlákna se odpověď nemá kde
    /// ukázat. To je rozdíl proti rozdělanému review, které se drží: to je vlastní práce
    /// v řádu odstavců a má na disku své místo.
    var threadReplies: [ThreadKey: String] = [:]

    /// Co se právě děje s vláknem, nebo co u něj selhalo. Chybějící záznam = nic.
    var threadStates: [ThreadKey: ThreadActionState] = [:]

    /// Rozepsané komentáře do diskuze pod PR (#216). Co v mapě není, nikdo nerozepsal.
    ///
    /// Žije tady ze stejného důvodu jako rozepsané odpovědi: composer sedí pod osou konverzace,
    /// která se překliknutím tabu odbourá, takže `@State` v něm by rozepsanou větu zahodil.
    /// Na disk se to **neukládá** — je to jedna věta v diskuzi, ne review.
    var pullRequestComments: [PRIdentifier: String] = [:]

    /// Co se právě děje s komentářem pod PR, nebo co u něj selhalo. Chybějící záznam = nic.
    var pullRequestCommentStates: [PRIdentifier: CommentActionState] = [:]

    /// Rozbalený kontext **per soubor v PR**. Co v mapě není, nikdo nerozbaloval.
    var expansions: [FileExpansionKey: FileExpansion] = [:]

    /// Hledání v diffu **per diff** (#152). Co v mapě není, v tom se nikdy nehledalo.
    ///
    /// Hodnotou je **objekt**, ne struktura, a je to výkonové rozhodnutí (#472): dotaz se mění při
    /// každém písmenu, takže ve struktuře by to byl zápis do `diffSearches` — a ten probudí každého,
    /// kdo tuhle mapu čte, tedy i tělo detailu PR. Takhle se mění vlastnost objektu, jehož identita
    /// je stálá; podrobnosti u `DiffSearchState`.
    ///
    /// Žije tady, ne ve view, ze stejného důvodu jako sbalené soubory pod tímhle: pruh musí přežít
    /// přepnutí tabu i složení panelu, po kterém se `DiffView` staví znovu.
    var diffSearches: [DiffSearchKey: DiffSearchState] = [:]

    /// Sbalené soubory diffu. Co v množině **není**, je rozbalené — u PR o padesáti
    /// souborech je rozbaleno výchozí stav a sbalení je gesto, takže se pamatuje to druhé.
    ///
    /// Žije tady, ne ve view: `PullRequestDetailView` si SwiftUI mezi PR ponechá (stejná
    /// pozice ve stromu), takže by sbalení přeteklo z jednoho pull requestu na druhý.
    var foldedFiles: Set<FileExpansionKey> = []

    /// Odchylka od pohledu na diff, který je v nastavení. `nil` = ber ho z konfigurace.
    ///
    /// Drží se **globálně, ne per PR**: pohled je způsob čtení, takže přepnutím na jiný pull
    /// request nemá důvod se vracet. A ve storu, ne ve view — `PullRequestDetailView` si
    /// SwiftUI mezi PR ponechá (stejná pozice ve stromu), takže `@State` by odchylku zahodilo
    /// přestavění stromu; tatáž past jako u sbalených souborů.
    ///
    /// **Na disk se nezapisuje.** Nastavení říká „takhle to chci mít“, přepínač v liště „teď
    /// se na to podívám jinak“. Kdyby přepínač zapisoval do `config.json`, přestala by být
    /// hodnota v nastavení tím, čemu se říká výchozí — měnila by se sama tím, že si člověk
    /// u jednoho souboru otočí pohled.
    var diffLayoutOverride: DiffLayout?

    /// Komentář, který se dá ⇧ klikem roztáhnout na rozsah — ten naposledy přidaný v tomhle PR
    /// (#110). Chybějící záznam = není co roztahovat, takže ⇧ klik založí obyčejný komentář.
    ///
    /// Drží se **id komentáře**, ne kotva: druhý konec se z komentáře dopočítá a po roztažení
    /// zůstane platný, kdežto uložená kotva by se s ním rozešla. Uklízí se s PR mimo seznam,
    /// jako ostatní stav vázaný na PR.
    var rangeTargets: [PRIdentifier: UUID] = [:]

    /// Rozsah, který se právě táhne přes řádky diffu (#110). `nil` = netáhne se.
    ///
    /// Drží se **složený rozsah**, ne dvojice konců: složit ho umí jen `Policy` (potřebuje k tomu
    /// diff, protože pořadí konců rozhoduje podle kreslených řádků), takže by se to jinak počítalo
    /// dvakrát — při zvýrazňování i při vzniku komentáře. Zvýraznění tak ukazuje **přesně** ten
    /// rozsah, který z tažení vznikne.
    var commentDrag: CommentRangeDrag?

    /// Co reviewery dělaly, per PR. Drží se i po doběhnutí — právě tehdy se k tomu člověk
    /// vrací. Pořadí kopíruje pořadí, ve kterém běhy začaly.
    var reviewTimelines: [PRIdentifier: [ReviewerTimeline]] = [:]

    /// Je otevřená command palette ⌘K (#184)?
    ///
    /// **Ve store, ne v `@State` okna**, a je to podmínka, ne úklid: detail PR podle toho vypíná
    /// svoje `⌘⏎` (potvrzení odeslání), aby paletě zbylo `⌘↵` na „otevřít na GitHubu“ — a dvě
    /// okna, která si o téže klávese musí říct, si to jinudy nemají kde povědět. Zapisuje se
    /// jedině `openPalette()` / `closePalette()` / `togglePalette()`.
    ///
    /// **Dotaz ani vybraný řádek tady nejsou**: mají zaniknout se zavřením palety, takže bydlí
    /// v `@State` uvnitř `CommandPaletteView`. Text z minula by po ⌘K vypadal jako výsledky
    /// k něčemu, na co se nikdo neptal.
    var isPaletteOpen = false

    /// Kam se má odscrollovat po skoku z palety (#184). `nil` = nikam.
    ///
    /// Rozhodnutí padá v paletě nad celým oknem, ale odscrollovat umí jedině detail PR (má kotvy
    /// řádků a `ScrollViewProxy`) — proto se tady žádost jen **položí** a detail si ji vyzvedne
    /// a smaže. Uklízí se s PR mimo seznam, stejně jako rozdělané tažení komentáře.
    var paletteJump: CommandPalette.Jump?

    /// Má okno nastavení fokus? Hlavní okno se podle toho rozostří, aby netahalo oko.
    ///
    /// Žije tady, ne ve view: okno nastavení je **vlastní scéna**, takže si to dvě okna
    /// nemají kde říct jinudy.
    ///
    /// Hlásí ho **okno nastavení o sobě**, ne hlavní okno o něm. Hlavní okno umí přes
    /// `controlActiveState` říct jen „nemám fokus“, a to je pravda i tehdy, když je vepředu
    /// úplně jiná aplikace — pak by se rozostřovalo bez důvodu.
    var isSettingsFrontmost = false

    /// Login přihlášeného účtu (#330) — kdo se dívá. **Prázdný znamená „nevím“, ne „to jsem já“.**
    ///
    /// Dotahuje se **jednou při startu** (`gh api user`), ne na tik pollingu: není to údaj o PR
    /// a `gh` se mezi dvěma tiky nepřehlásí. Dokud nedorazí, je podle `Policy.ownership` všechno
    /// cizí — opačné výchozí chování by při startu na okamžik přehodilo celý seznam do „moje“
    /// a fronta by na ten okamžik zmizela.
    ///
    /// **Ne z `Conversation.viewer`**, který týž login taky nese: ten je až z načtené konverzace
    /// vybraného PR, takže v seznamu není. Dvě cesty k témuž údaji by se navíc umělo rozejít.
    private(set) var viewer = ""

    /// Nastavení, se kterým aplikace běží.
    private(set) var configuration: Configuration

    /// Proč se konfiguraci nepodařilo přečíst nebo uložit. Ani jedno nesmí aplikaci
    /// položit, ale ani projít tiše — jinak uživatel hledá, proč mu nastavení nefunguje.
    var configurationFailure: String?

    /// Kolik uložených souborů s nálezy se nepodařilo přečíst.
    ///
    /// Musí být vidět: rozbitý soubor znamená ztracené nálezy, a ty se nesmí tvářit jako
    /// „review neběželo“.
    private(set) var unreadableReviewFiles = 0

    let time: any TimeSource

    private let polling: PollingService

    /// Dostupnost služeb pro stavový řádek. `nil` = odsud se nesleduje (testy) a řádek pak
    /// žádné puntíky neukazuje.
    ///
    /// Nepovinné schválně, jako `checkout` nebo `reviews`: `keepFresh()` volají i testy
    /// a monitor s živým klientem by z nich udělal testy chodící na síť.
    private let health: HealthMonitor?

    let gateway: any GitHubGateway

    /// Cesta ke `gh` — jediné, co si store kvůli odesílání drží.
    ///
    /// **Ne publisher a ani továrna na něj** (tvrdá podmínka č. 1): cesta ven se skládá až
    /// v `ReviewSubmission.send()`, takže `AppStore` sám odeslat nic neumí — a grep, kterým
    /// se ta podmínka kontroluje, ho schválně nevypíše. `nil` v testech znamená „odsud se
    /// neposílá“ a `submission(for:)` pak nevrátí nic.
    let gh: URL?

    /// Cesta ke `gitu` — jediné, co si store kvůli přetlačení větve drží (#466).
    ///
    /// **Ne pusher a ani továrna na něj**, ze stejného důvodu jako u `gh`: cesta do remote se
    /// skládá až v `BranchPushSubmission.push`, takže `AppStore` sám pushnout nic neumí a grep
    /// `BranchPushing App/` ho schválně nevypíše. `nil` v testech znamená „odsud se nepushuje“
    /// a `branchPushSubmission(for:)` pak nevrátí nic.
    let git: URL?

    /// Cache, ve které se pracuje (#466) — **tatáž, ve které stojí checkout**.
    ///
    /// Drží se tady kvůli jedné věci: pusher si ověřuje, že strom, ze kterého pushuje, leží
    /// v cache (tvrdá podmínka č. 3), a ta kontrola má mluvit o **té** cache, ve které rebase
    /// doopravdy proběhl. Dvě výchozí hodnoty na dvou místech by v provozu vyšly stejně a v testu
    /// by se rozešly — a ta kontrola by se pak nedala ověřit odjinud než z pusheru samotného.
    let cacheLayout: CacheLayout

    let checkout: (any RepoCheckout)?

    /// Vestavěné terminály (#459). `nil` = **zásuvka se nekreslí** — tak jsou na tom testy, které
    /// o terminál nestojí, a je to tentýž vzorec jako u `checkout` nebo `reviewer`.
    let terminals: (any TerminalHosting)?

    let reviewer: (any ReviewRunning)?

    let reviews: ReviewStore?

    let draftStore: ReviewDraftStore?

    /// Zadání PR pro reviewera (#120). `nil` = **zadání se nepřipravuje** a review poběží
    /// s promptem bez věty o souboru, tedy tak, jak běželo do #120.
    ///
    /// Nepovinné ze stejného důvodu jako `reviews`: testy, které o zadání nestojí, ho nedostanou
    /// a nesahají tím do skutečné cache.
    let intents: ReviewIntentStore?

    let translator: (any FindingTranslating)?

    /// Dotažení textu issue do zadání pro reviewera (#345). `nil` = **netahá se** a review poběží
    /// se zadáním bez textu, tedy tak, jak běželo do #345.
    ///
    /// Nepovinné ze stejného důvodu jako `translator`: testy, které o zadání nestojí, ho nedostanou
    /// a nespouští tím `claude`.
    let intentText: (any IntentTextFetching)?

    /// Rozhovor nad PR (#452). `nil` = **tab se neptá** a composer zůstane zakázaný s důvodem.
    ///
    /// Nepovinné ze stejného důvodu jako `translator`: testy, které o rozhovor nestojí, ho
    /// nedostanou a nespouští tím `claude`.
    let asker: (any AskRunning)?

    /// Slévání konfliktů při srovnání větve (#467). `nil` = **konflikty se neslévají** a `Rebase`
    /// nad zkonfliktněnou větví zůstane zakázaný s důvodem, tedy tak, jak to bylo do #467.
    ///
    /// Nepovinné ze stejného důvodu jako `asker`: testy, které o slévání nestojí, ho nedostanou
    /// a nespouští tím `claude`.
    let conflicts: (any ConflictResolving)?

    /// Uložené rozhovory (#452). `nil` = neukládá se, tedy rozhovor zanikne se zavřením aplikace.
    let asks: AskStore?

    /// Materiál pro rozhovor vedle pracovního stromu (#452). `nil` = neukládá se a session
    /// dostane prompt bez odkazu na soubor, tedy bez nálezů, konverzace a checků.
    let askContexts: AskContextStore?

    private let configStore: ConfigStore?

    /// Doručování notifikací (#88). `nil` = odsud se neposílají (testy), takže se nic
    /// nedoručí a proud kliknutí se ani nezačne konzumovat.
    ///
    /// Nepovinné schválně, jako `health` nebo `reviews`: `keepFresh()` volají i testy a živé
    /// centrum by z nich udělalo testy sahající na systémové notifikace.
    let notifications: (any UserNotifying)?

    /// Které PR už se ohlásily jako nové (#85). `nil` = odsud se nehlásí (testy).
    let announced: AnnouncedPullRequests?

    /// Komu se nastaví vzhled okna (#278). `nil` = odsud se nenastavuje (testy).
    ///
    /// Nepovinné z **jiného** důvodu než `notifications`: živý cíl je `NSApp`, tedy v testech
    /// hostitel testů — vynucený režim by z jednoho testu přetekl do render sond, které si režim
    /// nastavují samy.
    private let appearance: (any AppearanceApplying)?

    /// Proč se nepodařilo uložit vzhled okna (#278).
    ///
    /// Musí být vidět: když zápis selže, vzhled se **nepřepne** (uplatňuje se až po úspěšném
    /// uložení), a klik do railu, po kterém se nic nestane a nic se neřekne, vypadá jako rozbitá
    /// aplikace. Kreslí to `AppNoticesView`.
    var appearanceFailure: String?

    /// Rozdělané běhy (#97). `nil` = odsud se nedotahuje (testy).
    let interrupted: InterruptedRuns?

    /// Čtení transcriptů zabitých session (#97) a přepisu surové session (#327). `nil` = odsud se
    /// nečte (testy).
    ///
    /// **`internal`, protože na něj sahá `AppStore+RawSession`** — je to tatáž cena, jakou zaplatilo
    /// rozdělení storu na extensiony (#154), a nic se tím neotevírá ven z aplikace (jeden modul).
    let transcripts: (any TranscriptReading)?

    /// Otevřený přepis surové session (#327). `nil` = sheet není otevřený.
    ///
    /// Drží se **v storu, ne ve view**, protože je to načtená věc z disku a view I/O nedělá; a je
    /// to **jeden** snímek, ne slovník — viz `RawSessionSnapshot`.
    var rawSession: RawSessionSnapshot?

    /// Otevření session v uživatelově terminálu (#453). `nil` = odsud se neotevírá (testy).
    ///
    /// Nepovinné ze stejného důvodu jako `notifications`: živá implementace posílá Apple event do
    /// `Terminal.app`, takže by z každého testu, který si složí store, byl test otevírající okna.
    ///
    /// **Od #460 to `▶` nepoužívá** — drží se jako záloha, viz `openInTerminal(_:)`.
    let terminal: (any TerminalOpening)?

    /// Důvěra ke složce v konfiguraci Claude Code (#460). `nil` = odsud se nezapisuje (testy).
    ///
    /// Nepovinné ze stejného důvodu jako `terminal`: živá implementace sahá na soubor **mimo naši
    /// cache**, takže by z každého testu, který si složí store, byl test píšící do `~/.claude.json`.
    let workspaceTrust: (any WorkspaceTrusting)?

    /// Co má terminál za novinu. `nil` = nic se nepokazilo.
    ///
    /// **Musí být vidět, a je to celý důvod, proč ten stav existuje**: výsledek téhle akce je
    /// buď mimo aplikaci (#453, okno `Terminal.app`), nebo v zásuvce, ve které se **nic
    /// nezměnilo** (#460, `busy` a `noShell`) — a obojí vypadá úplně stejně jako by se nekliklo.
    /// `try?` nad tou cestou je přesně ten vzor, který `CLAUDE.md` vypisuje jako opakovaný nález.
    /// Kreslí to `AppNoticesView`, tedy tam, kde stojí ostatní „co je špatně“.
    ///
    /// Jedno pole na obojí schválně: je to jedna věta o jedné akci a dvě pole by znamenala dvě
    /// místa, která se musí nezávisle zahazovat — z `▶` přitom vede pokaždé právě jedna cesta.
    var terminalFailure: String?

    /// Počitadlo načtení přepisu. Viz `RawSessionSnapshot.generation` — bez něj by dvě čtení téhož
    /// cíle nešlo od sebe poznat.
    var rawSessionGeneration = 0

    /// Běžící review podle PR — drží se kvůli zrušení.
    var reviewTasks: [PRIdentifier: RunningReview] = [:]

    /// Běžící kontrola nálezů z minula podle PR (#150). Co v mapě není, neběží.
    ///
    /// **Vlastní mapa, ne `reviewTasks`**, a je to rozhodnutí: na `reviewTasks` visí chipy
    /// reviewerů, pruh průběhu, `runningSkills` i podmnožina k opakování (#149) — kontrola žádný
    /// skill nepouští, takže by ve všech čtyřech tvrdila něco, co není. Co si naopak vzít musí, je
    /// všechno, co platí pro **běžící session**: ochrana repa před eviction, zabití při zavírání
    /// aplikace (#264) a počet běhů, na který se ptá dialog při ukončení.
    var recheckTasks: [PRIdentifier: RunningRecheck] = [:]

    /// Proč kontrola nálezů nedoběhla (#150). Chybějící záznam = nic se nepokazilo.
    ///
    /// Drží se, dokud si někdo neřekne o další kontrolu: spolknutá chyba by vypadala jako běh,
    /// který nic nenašel — tedy jako „nálezy pořád platí“, což je zrovna to tvrzení, které se
    /// z ničeho vyrábět nesmí.
    var recheckFailures: [PRIdentifier: String] = [:]

    /// Rozhovory z tabu `Zeptat se` (#452). Co v mapě není, se z disku ještě nenačetlo.
    ///
    /// **Načítá se až při otevření tabu**, ne při startu jako drafty — proč, je u `AskStore`.
    /// Prázdný rozhovor v mapě proto znamená „na disku nic není“, ne „ještě jsme se nedívali“;
    /// to druhé je chybějící klíč.
    var askConversations: [PRIdentifier: AskConversation] = [:]

    /// Rozepsaná otázka **per PR**. Co v mapě není, nikdo nerozepsal.
    ///
    /// Žije tady ze stejného důvodu jako rozepsaný komentář pod PR (#216): composer sedí pod
    /// rozhovorem, který se překliknutím tabu odbourá, takže `@State` v něm by rozepsanou otázku
    /// zahodil. Na disk se **neukládá** — je to otázka, kterou člověk zrovna formuluje, ne práce
    /// v řádu odstavců.
    var askDrafts: [PRIdentifier: String] = [:]

    /// Běžící odpověď podle PR (#452). Co v mapě není, neběží.
    ///
    /// **Vlastní mapa, ne `reviewTasks`**, ze stejného důvodu jako u kontroly nálezů: na
    /// `reviewTasks` visí chipy reviewerů, pruh průběhu i podmnožina k opakování, a rozhovor žádný
    /// skill nepouští. Co si naopak vzít musí, je všechno, co platí pro **běžící session**:
    /// ochrana repa před eviction, zabití při zavírání aplikace (#264) a počet běhů, na který se
    /// ptá dialog při ukončení.
    var askTasks: [PRIdentifier: Task<Void, Never>] = [:]

    /// Běžící srovnání větve podle PR (#467). Co v mapě není, neběží.
    ///
    /// **Existuje kvůli zrušení, ne kvůli počítání.** Do #467 byl rebase volání `gitu` v řádu
    /// sekund a rušit ho nebylo co; se session, která běží minuty a stojí peníze, musí být kde
    /// vzít `cancel()` — a stejně tak při zavírání aplikace (#264, #351), protože `claude -p`
    /// přežije rodiče a platí tokeny dál.
    var branchSyncTasks: [PRIdentifier: Task<Void, Never>] = [:]

    /// Co session nad konflikty zrovna dělá — druhý řádek u hlášky v panelu (#467). Chybějící
    /// záznam = zatím nic neřekla.
    ///
    /// **Vedle stavu, ne v něm**: mění se při každém tool cally, a přepisovat kvůli tomu
    /// `branchSyncStates` by špinilo i to, co se nemění (pravidlo o hrubé vlastnosti, #472).
    var branchSyncActivity: [PRIdentifier: String] = [:]

    /// Co session zrovna dělá — řádek u prstýnku na místě příští bubliny (#452). Chybějící
    /// záznam = zatím nic neřekla.
    var askActivity: [PRIdentifier: String] = [:]

    /// Proč se rozhovor nepodařilo přečíst nebo uložit (#452).
    ///
    /// Musí být vidět, a ze stejného důvodu jako u draftu: otázka i odpověď jsou zaplacená práce,
    /// takže neuložený rozhovor, o kterém se mlčí, vypadá po restartu jako rozhovor, který nikdy
    /// nebyl — a příští otázka za něj zaplatí kontext znovu.
    var askFailure: String?

    /// Běžící kontrola nálezů (#150) — úloha a kdy začala.
    struct RunningRecheck {
        let task: Task<Void, Never>
        /// Kdy se běh spustil — hodiny u tlačítka. Bez nich je patnáctiminutová session
        /// k nerozeznání od zaseknutého okna.
        let startedAt: Date

        init(task: Task<Void, Never>, startedAt: Date) {
            self.task = task
            self.startedAt = startedAt
        }
    }

    /// Aplikace se zavírá (#264). Čte se na dvou místech a obojí je podmínka, ne kosmetika:
    ///
    /// - **nic nového se nespustí** — tik pollingu uprostřed zavírání by pustil automatické
    ///   review, které by aplikaci přežilo, tedy zrovna to, co se tímhle zavírá;
    /// - **značky rozdělaných běhů (#97) se nemažou** — zavření je pro běh totéž jako pád, takže
    ///   se nálezy mají dotáhnout z transcriptu po dalším startu (viz `AppStore+Review`).
    var isTerminating = false

    /// Běžící review jednoho PR — úloha a to, které reviewery pouští.
    ///
    /// **Jedna úloha na PR, ne na `(PR, skill)`**, i když #149 pouští i podmnožinu. Na
    /// `reviewTasks` visí `isReviewing`, `runningReviews` (podle kterého se aplikace ptá před
    /// zavřením, #94), rušení automatických běhů i ochrana rep před eviction — klíčovat je
    /// dvojicí by znamenalo přepsat všechna čtyři. Cena je, že se opakování jednoho revieweera
    /// nedá spustit, dokud nad PR běží jiné review; to je ale stav, který sám za chvíli
    /// skončí, a chip u něj mezitím ukazuje spinner.
    struct RunningReview {
        let task: Task<Void, Never>
        /// Podmnožina, kterou běh pouští (#149). `nil` = celá nastavená sada — a schválně ne
        /// její snímek: sadu ještě může změnit odhad jazyka repa a platit má ta, se kterou běh
        /// doopravdy jede.
        let skills: [String]?
        /// Kdy se běh spustil — hodiny v pruhu průběhu (#218).
        ///
        /// **Tady, ne z časové osy.** Osa se při opakování jednoho revieweera míchá s tou
        /// z minulého běhu a reviewer, který mezitím doběhl, z „běžících“ vypadne; nejstarší
        /// událost běžících os by se tím posouvala dopředu a hodiny by šly zpátky.
        let startedAt: Date

        init(task: Task<Void, Never>, skills: [String]?, startedAt: Date = .now) {
            self.task = task
            self.skills = skills
            self.startedAt = startedAt
        }
    }

    /// Review, která spustil **automat**. Ruční se pozná tím, že tady není — a jen ta
    /// automatická se ruší, když PR zmizí ze seznamu.
    var automaticReviews: Set<PRIdentifier> = []

    /// `updatedAt`, se kterým se PR naposledy zvažoval pro automat.
    ///
    /// V paměti, ne na disku: po restartu se zváží znovu, což stojí jedno `gh pr view` na
    /// PR. Session se za to neutratí — o tu rozhoduje až porovnání `headSha`.
    var consideredForAutomation: [PRIdentifier: Date] = [:]

    let autoRuns: AutoRunLedger?

    /// Kolik dneska stálo review (#148). Nepovinná závislost jako ostatní story — testy, které
    /// o útratu nestojí, ji nedostanou a řádek pak žádnou útratu neukazuje.
    let spend: SpendLedger?

    /// Kdy jsem který PR naposled viděl (#173).
    let visits: VisitLedger

    /// O čem už se u kterého PR hlásilo (#335). **Druhé razítko vedle návštěv**, protože
    /// oznámením PR nenavštívím — bez něj by hláška o cizím komentáři chodila při každé rozhlídce.
    let activityNotices: ActivityNoticeLedger

    /// Kdy se aplikace naposled ptala na diskuzi vlastních PR (#335). `nil` = ještě nikdy.
    ///
    /// V paměti, ne na disku: po restartu se rozhlídka udělá hned, což je jeden až tři dotazy
    /// navíc při startu — a proti tomu stojí, že se po spuštění o cizí aktivitě dozvím rovnou.
    /// Posouvá se **jen když se doopravdy ptáme**, viz `Policy.activitySweep`.
    var lastActivitySweep: Date?

    /// S jakým `updatedAt` se aplikace naposled ptala na **hlavu** toho PR (#420). Chybějící
    /// klíč = nikdy.
    ///
    /// Je to celý předfiltr dávkového dotazu na hlavy (`Policy.staleHeadProbe`): dokud se
    /// `updatedAt` nepohne, hlava se změnit nemá čím, takže se neptáme — na klidný den je z toho
    /// **nula volání**. Razítko dostanou jedině PR, na které se doopravdy ptalo, takže selhaný
    /// dotaz zkusí příští tik znovu.
    ///
    /// **V paměti, ne na disku**, jako `lastActivitySweep`: po restartu je prázdné, takže první
    /// tik dohoní, co se stalo, když aplikace neběžela — a je to **jeden** dotaz, ne jeden na PR.
    var headProbes: [PRIdentifier: Date] = [:]

    /// Které zadání jsem už předal agentovi (#334). Nepovinná závislost jako ostatní story —
    /// testy, které o razítka nestojí, ji nedostanou a pak je všechno nepředané.
    let handoffs: HandoffLedger?

    /// Razítka předání, se kterými se pracuje (#334). Disk je **záloha**, ne jediná kopie:
    /// odznak v railu i pilulka v řádku se na ně ptají při každém překreslení okna, takže se
    /// čtou z paměti — z disku jednou při startu (`loadStoredHandoffs()`).
    var handoffStamps: [PRIdentifier: Handoff] = [:]

    /// Značka, proti které se **v tomhle běhu** počítá „od tvé poslední návštěvy“.
    ///
    /// Drží se zvlášť od zapsané návštěvy schválně, a je to tentýž vzor jako u odznaků `nové`
    /// v okně s novinkami (#127): zapsat se musí hned při otevření, jinak by o návštěvě
    /// nevěděl příští start — ale banner by se tím spotřeboval při prvním přepnutí tam a zpět.
    /// Snapshot se proto nastaví jednou za běh aplikace a dál se nemění.
    var visitSnapshots: [PRIdentifier: Date] = [:]

    /// Hlava, kterou jsem u PR viděl při minulé návštěvě (#173). Čte se z ledgeru jednou, spolu
    /// se snapshotem.
    ///
    /// **Chybějící klíč, ne `nil` uvnitř**: `[PRIdentifier: String?]` by dalo dvojitý optional
    /// a `seenHeads[pr]` by vyšlo jako „něco tam je“ i pro uloženou `nil` hodnotu — pak by se
    /// první otevření PR tvářilo jako posunutá hlava. Chytil to test, ne čtení kódu.
    var seenHeads: [PRIdentifier: String] = [:]

    /// Záznam dění (#414). `nil` = odsud se nezaznamenává (testy, které o dění nestojí, tím
    /// nesahají do skutečné cache).
    let activityLog: ActivityLog?

    /// Značka poslední návštěvy sekce `Dění` (#414) — posouvá se **při odchodu**, ne při vstupu.
    let activityVisits: ActivityVisitLedger

    /// Položky dění, se kterými se pracuje (#414). Disk je **záloha**, ne jediná kopie: sekce
    /// i odznak v railu se na ně ptají při každém překreslení okna, takže se čtou z paměti —
    /// z disku jednou při startu (`loadStoredActivity()`).
    ///
    /// Od nejnovějšího a se stropem, protože obojí rozhoduje `Policy.activityLog(_:adding:limit:)`
    /// — tatáž funkce, jakou se zapisuje soubor.
    var activityEvents: [ActivityEvent] = []

    /// Nepodařilo se přečíst soubor se záznamem dění (#414)?
    ///
    /// Musí být vidět, a ze stejného důvodu jako u nálezů: **prázdný záznam a ztracená historie
    /// dají obojí prázdný seznam**, takže klidné „za poslední dny se nic nestalo“ by nad rozbitým
    /// souborem tvrdilo víc, než data unesou. Kreslí to prázdný stav sekce, ne stavový řádek —
    /// je to odpověď na otázku, kterou si člověk klade zrovna nad tou obrazovkou.
    ///
    /// **`internal`, ne `private(set)`** — píše to `AppStore+Feed`; je to tatáž cena, jakou
    /// zaplatilo rozdělení storu na extensiony (#154).
    var isActivityLogUnreadable = false

    /// Značka, proti které se **v tomhle běhu** počítá, co je v dění nové.
    ///
    /// Drží se zvlášť od zapsané značky, přesně jako `visitSnapshots` u pull requestů: kdyby se
    /// číslo bralo z ledgeru, posunul by ho zápis při odchodu a při návratu do sekce by nebylo
    /// nové nic. `nil` = ještě se nečetla, nebo tu nikdy nikdo nebyl — a to znamená, že je nové
    /// **všechno** (viz `Policy.unreadActivity`).
    var activityVisitSnapshot: Date?

    /// Byla sekce `Dění` na obrazovce, když se naposledy něco přepínalo (#414)?
    ///
    /// Drží se kvůli tomu, aby se poznalo **odejití** — tatáž úvaha jako u `openedPullRequest`.
    /// Značka se posouvá jedině při odchodu, takže se ta dvě volání (vstup a odchod) musí od sebe
    /// odlišit, a jinak než porovnáním s předchozím stavem to nejde: rail zapisuje sekci
    /// i záložka a obojí umí sekci opustit.
    var wasActivityVisible = false

    /// PR, jehož detail je zrovna na obrazovce (#173). Drží se kvůli tomu, aby se poznalo
    /// **odejití** — přepnutí jinam a návrat je nová návštěva, takže se banner podruhé
    /// neukazuje. Uvnitř jednoho PR se tím nemění nic, takže odskok mezi taby o něj nepřipraví.
    var openedPullRequest: PRIdentifier?

    /// Je zásuvka s terminálem vytažená? (#459)
    ///
    /// **Jeden příznak na okno, ne na pull request.** `⌃\`` je hmat, kterým se terminál schová
    /// a vytáhne, a kdyby si ho každá záložka pamatovala zvlášť, znamenal by při přepnutí pokaždé
    /// něco jiného. Shell samotný je naproti tomu **per PR** (drží ho `TerminalHost`), takže
    /// schování zásuvky nic nezabíjí — přesně jako sbalení panelu nálezů.
    var isTerminalOpen = false

    /// Má zásuvka fokus?
    ///
    /// Na tomhle jediném příznaku stojí to, že se okenní zkratky bez `⌘` neuplatní
    /// (`Policy.shortcutYieldsToTerminal`) — jinak by `⌃W` uprostřed psaní zavřelo záložku.
    /// Hlásí ho `TerminalHost` ze setteru `hasFocus` na ploše emulátoru — `becomeFirstResponder`
    /// a `resignFirstResponder` má knihovna `public`, ne `open`, takže se z jiného modulu přepsat
    /// nedají (zdůvodnění je u `EmbeddedTerminalView.hasFocus`).
    var isTerminalFocused = false

    /// Jak si stojí shell té relace. Co v mapě není, nikdy neběželo.
    ///
    /// **Klíčem je od #460 relace, ne pull request**: zásuvka jich drží víc naráz a puntík
    /// u každé záložky se ptá právě téhle mapy.
    var terminalStates: [TerminalSlot: TerminalRunState] = [:]

    /// Ve kterém adresáři ta relace stojí — **zjištěné jednou, při jejím vzniku**.
    ///
    /// Drží se proto, že rozhodnutí („strom review, nebo klon?“) potřebuje sáhnout na disk, a to se
    /// v `body` dělat nesmí (#224). Klíč je **relace**, ne repo ani PR: holý shell stojí v klonu
    /// nebo ve stromu posledního review, kdežto relace dráhy ve stromu **té** session — a `claude
    /// --resume` hledá vlákno podle adresáře.
    var terminalDirectories: [TerminalSlot: URL] = [:]

    /// Ke kterým složkám už je v konfiguraci Claude Code zapsaná důvěra (#460, od #479 množina).
    ///
    /// **Drží se proto, aby se konfigurace Claude Code nečetla při každém otevření zásuvky**:
    /// `~/.claude.json` má na tomhle stroji přes 200 kB a rozebrat ho kvůli hodnotě, která se mění
    /// **jednou za život složky**, je zrovna to čtení všeho, kde stačí předfiltr.
    ///
    /// **Množina, ne příznak** (#479): od #479 se nezapisuje jen kořen cache, ale i ta složka, ve
    /// které shell doopravdy stojí — a těch je jedna na pull request. Příznak by po prvním zápisu
    /// zavřel cestu všem ostatním.
    ///
    /// Zapisuje se sem **jen po úspěchu**, takže se po neúspěšném zápisu zkusí příště znovu — a to
    /// je důležitější než ušetřené čtení: dokud se to nepovede, chodí ten dotaz na důvěru.
    ///
    /// **Mez tady vyjmenovaná není, a je to rozhodnutí**: přibývá jedna cesta na pull request, nad
    /// kterým se vytáhla zásuvka, takže strop je velikost fronty, ne délka běhu. Pravidlo o cache,
    /// která si musí říct, co ji vyprazdňuje (#224), mluví o tom, co roste s **daty** — tohle roste
    /// s tím, kolik PR člověk za odpoledne otevře.
    var trustedWorkspaces: Set<URL> = []

    /// Které relace zásuvka pro ten PR drží, **v pořadí vzniku** (#460).
    ///
    /// Pořadí je pořadí záložek v přepínači a nesmí se přeskládat pod rukama; strop hlídá
    /// `Policy.maxTerminalSlots`.
    var terminalSlots: [PRIdentifier: [TerminalSlot]] = [:]

    /// Která relace je zrovna vidět. Co v mapě není, ještě se nezobrazilo.
    var activeTerminalSlots: [PRIdentifier: TerminalSlot] = [:]

    init(
        gateway: any GitHubGateway,
        configuration: Configuration = .standard,
        configStore: ConfigStore? = nil,
        time: any TimeSource = SystemTimeSource(),
        eviction: CacheEviction? = nil,
        checkout: (any RepoCheckout)? = nil,
        terminals: (any TerminalHosting)? = nil,
        workspaceTrust: (any WorkspaceTrusting)? = nil,
        reviewer: (any ReviewRunning)? = nil,
        reviews: ReviewStore? = nil,
        drafts: ReviewDraftStore? = nil,
        intents: ReviewIntentStore? = nil,
        translator: (any FindingTranslating)? = nil,
        intentText: (any IntentTextFetching)? = nil,
        asker: (any AskRunning)? = nil,
        conflicts: (any ConflictResolving)? = nil,
        asks: AskStore? = nil,
        askContexts: AskContextStore? = nil,
        autoRuns: AutoRunLedger? = nil,
        spend: SpendLedger? = nil,
        gh: URL? = nil,
        git: URL? = nil,
        cacheLayout: CacheLayout = .applicationSupport,
        health: HealthMonitor? = nil,
        notifications: (any UserNotifying)? = nil,
        announced: AnnouncedPullRequests? = nil,
        interrupted: InterruptedRuns? = nil,
        transcripts: (any TranscriptReading)? = nil,
        terminal: (any TerminalOpening)? = nil,
        appearance: (any AppearanceApplying)? = nil,
        visits: VisitLedger = VisitLedger(preferences: UserDefaults.standard),
        activityNotices: ActivityNoticeLedger = ActivityNoticeLedger(preferences: UserDefaults.standard),
        handoffs: HandoffLedger? = nil,
        activityLog: ActivityLog? = nil,
        activityVisits: ActivityVisitLedger = ActivityVisitLedger(preferences: UserDefaults.standard)
    ) {
        self.visits = visits
        self.activityNotices = activityNotices
        self.handoffs = handoffs
        self.activityLog = activityLog
        self.activityVisits = activityVisits
        self.appearance = appearance
        self.time = time
        self.gh = gh
        self.git = git
        self.cacheLayout = cacheLayout
        self.health = health
        self.notifications = notifications
        self.announced = announced
        self.interrupted = interrupted
        self.transcripts = transcripts
        self.terminal = terminal
        self.configuration = configuration
        self.configStore = configStore
        polling = PollingService(
            gateway: gateway,
            sources: configuration.activeSources,
            interval: .seconds(configuration.global.pollIntervalSeconds),
            time: time
        )
        self.gateway = gateway
        self.checkout = checkout
        self.terminals = terminals
        self.workspaceTrust = workspaceTrust
        self.reviewer = reviewer
        self.reviews = reviews
        draftStore = drafts
        self.intents = intents
        self.translator = translator
        self.intentText = intentText
        self.asker = asker
        self.conflicts = conflicts
        self.asks = asks
        self.askContexts = askContexts
        self.autoRuns = autoRuns
        self.spend = spend
        polling.afterSuccessfulTick = { [weak self] summaries in
            await self?.forget(whatIsNotIn: summaries)
            // Až po `forget`: PR, který ze seznamu vypadl, se nemá čím spustit, a běžící
            // automat nad ním se má naopak zrušit.
            await self?.startAutomaticReviews(for: summaries)
            // `busy` se nepředává jako snímek, ale jako dotaz: eviction je dlouhá disková
            // operace a příprava, která začne uprostřed ní, by jinak přišla o ochranu.
            let busy: @Sendable () async -> Set<RepoID> = { [weak self] in
                await self?.busyRepositories ?? []
            }
            try? await eviction?.run(openPullRequests: summaries.map(\.id), busy: busy)
            // Stejné pravidlo jako u eviction: uklízet se smí jen po **úspěšném** tiku,
            // protože „PR chybí v seznamu“ znamená po výpadku sítě něco jiného. Selhání
            // úklidu se spolkne schválně — neuklizený soubor nikomu nevadí a příští tik to
            // zkusí znovu; hlásit to uživateli by byl šum bez akce.
            try? await reviews?.cleanUp(openPullRequests: summaries.map(\.id))
            // Nová PR se hlásí **jen po úspěšném tiku**, ze stejného důvodu jako všechno
            // ostatní tady: po výpadku sítě je seznam prázdný, takže by se snímek vyprázdnil
            // a při zotavení by přišlo úplně všechno.
            await self?.announceNewPullRequests(in: summaries)
            // Zastaralé nálezy (#420) — hlava se posunula pod uloženými nálezy. Uvnitř úspěšného
            // tiku ze stejného důvodu jako rozhlídka po diskuzi: vejde se to do backoffu pollingu
            // a nepotřebuje druhý časovač. Kolik dotazů z toho je, rozhoduje
            // `Policy.staleHeadProbe` — na klidný den nula, jinak **jeden na celou frontu**.
            await self?.refreshStaleHeads(in: summaries)
            // Cizí aktivita na **vlastních** PR (#335) — komentář kolegy, Copilotovo review.
            // Uvnitř úspěšného tiku schválně: rozhlídka se tím vejde do backoffu pollingu (při rate
            // limitu se netiká, takže se ani nekouká) a nepotřebuje druhý časovač. Kolik dotazů
            // z toho je, rozhoduje `Policy.activitySweep` — na klidný den nula.
            await self?.refreshOwnActivity(in: summaries)
            // Poloha větve proti základu (#466, z proklikání) — základ se může pohnout, aniž by se
            // na pull requestu změnilo cokoli, co jde vyčíst z `updatedAt`, takže bez tohohle by
            // otevřené okno tvrdilo `srovnaná` nad větví o commit pozadu až do restartu. Uvnitř
            // úspěšného tiku ze stejného důvodu jako rozhlídky výš: vejde se to do backoffu
            // pollingu a nepotřebuje druhý časovač. Kolik dotazů z toho je, rozhoduje
            // `Policy.divergenceProbe` — **nejvýš jeden**, a jedině když je otevřené vlastní PR.
            await self?.refreshOpenDivergence()
            // Útrata se počítá od půlnoci (#148), takže aplikace, která běží přes noc, by
            // ráno ukazovala včerejší součet. Tik je nejlevnější místo, kde se to dá srovnat
            // — účetní kniha si den pamatuje, takže se na disk sahá jednou za den, ne jednou
            // za minutu.
            await self?.loadDailySpend()
        }
        // Monitor si skutečná volání nedrží — bere si je odsud. Jinak by existovalo druhé
        // místo se stavem pollingu a rozejít se v tomhle znamená svítit červeně nad
        // funkčním GitHubem.
        health?.lastCall = { [weak self] service in
            switch service {
            case .github: self?.gitHubCall
            case .claude: self?.lastReviewCall
            }
        }
        // Terminál si stav nedrží sám (#459) — hlásí ho sem, protože okno kreslí stav ze store
        // a druhé místo se stavem by se s tímhle rozešlo. Je to tentýž tvar jako `lastCall` výš.
        self.terminals?.report = { [weak self] slot, state in self?.terminalStates[slot] = state }
        self.terminals?.focusChanged = { [weak self] hasFocus in
            self?.isTerminalFocused = hasFocus
        }
    }

    /// Sestavení z toho, co našel preflight. Absolutní cesta k `gh` je jediné, co gateway
    /// potřebuje — token si drží `gh` sám.
    convenience init(toolPaths: ToolPaths) {
        let runner = SubprocessRunner()
        let checkout = GitRepoCheckout(git: toolPaths.git, gh: toolPaths.gh, runner: runner)
        // Hodnoty se čtou **při použití**, ne teď: jinak by se reload konfigurace projevil
        // až po restartu. `weak` proto, aby si providery nedržely store.
        // Konfigurace se načte hned v `keepFresh()`; do té doby platí výchozí hodnoty,
        // takže se nikde nečeká na disk.
        let box = ConfigurationBox(.standard)
        self.init(
            gateway: GhGateway(gh: toolPaths.gh, runner: runner),
            configStore: ConfigStore(),
            eviction: CacheEviction(
                budget: { box.value.global.cacheBudgetMegabytes * 1024 * 1024 },
                checkout: checkout
            ),
            checkout: checkout,
            // Zásuvka s terminálem (#459). Živá jedině tady — testy shell nespouštějí.
            terminals: TerminalHost(),
            workspaceTrust: ClaudeWorkspaceTrust.inHomeDirectory,
            reviewer: ClaudeReviewRunner(
                claude: toolPaths.claude,
                gh: toolPaths.gh,
                // Značky běžících session (#351) — jedině tady, protože jedině `claude -p` běží
                // minuty a jako sirotek platí tokeny dál. Úklid při startu sahá na tentýž registr.
                runner: SubprocessStreamer(sessions: .shared),
                maxConcurrent: { box.value.global.maxConcurrentReviews },
                model: { box.value.global.model }
            ),
            reviews: ReviewStore(),
            drafts: ReviewDraftStore(),
            intents: ReviewIntentStore(),
            translator: ClaudeFindingTranslator(claude: toolPaths.claude, runner: runner),
            intentText: ClaudeIntentTextFetcher(claude: toolPaths.claude, runner: runner),
            // Rozhovor nad PR (#452). Streamem, ne bufferovaně — a přes tentýž registr běžících
            // session (#351): `claude -p` běží minuty a jako sirotek po zabité aplikaci platí
            // tokeny dál, takže ho musí umět zabít další start.
            asker: ClaudeAskSession(
                claude: toolPaths.claude,
                gh: toolPaths.gh,
                runner: SubprocessStreamer(sessions: .shared),
                model: { box.value.global.model }
            ),
            // Slévání konfliktů (#467) — **jediná session, která smí měnit soubory**. Streamem
            // a přes tentýž registr běžících session (#351) jako reviewer a rozhovor: `claude -p`
            // běží minuty a jako sirotek po zabité aplikaci platí tokeny dál.
            conflicts: ClaudeConflictResolver(
                claude: toolPaths.claude,
                gh: toolPaths.gh,
                runner: SubprocessStreamer(sessions: .shared),
                model: { box.value.global.model }
            ),
            asks: AskStore(),
            askContexts: AskContextStore(),
            autoRuns: AutoRunLedger(),
            spend: SpendLedger(),
            gh: toolPaths.gh,
            git: toolPaths.git,
            health: HealthMonitor(),
            notifications: SystemNotificationCenter.shared,
            announced: AnnouncedPullRequests(),
            interrupted: InterruptedRuns(),
            transcripts: TranscriptStore(),
            // Terminál (#453) — bufferovaný runner stačí: `osascript` doběhne, jakmile Terminal
            // okno založí, a to okno pak žije mimo aplikaci.
            terminal: AppleScriptTerminal(runner: runner),
            appearance: AppAppearance.application,
            handoffs: HandoffLedger(),
            // Záznam dění (#414). Živý jedině tady — testy ho nedostanou, takže nesahají do cache.
            activityLog: ActivityLog()
        )
        self.configurationBox = box
    }

    /// Sdílená schránka na aktuální konfiguraci pro věci, které běží mimo hlavní vlákno
    /// (limit souběhu, rozpočet cache, model). Store je `@MainActor`, takže sáhnout si
    /// na něj přímo nemůžou.
    private var configurationBox: ConfigurationBox?

    /// Nastavení pro konkrétní repo — globální hodnoty přebité tím, co si repo řeklo.
    func resolved(for repo: RepoID) -> ResolvedConfig {
        configuration.resolved(for: repo)
    }

    /// Repozitáře, které okno nastavení nabídne — z posledního seznamu PR i z konfigurace.
    var knownRepositories: [RepoID] {
        Policy.knownRepositories(in: pullRequests, configuration: configuration)
    }

    /// Znovu načte `config.json`. Co se čte při použití (skilly, kategorie, limit souběhu,
    /// rozpočet cache), se projeví hned; zdroje a interval se přepíšou pollingu tady.
    func reloadConfiguration() async {
        guard let configStore else { return }
        let loaded = await configStore.load()
        configurationFailure = loaded.failure
        await apply(loaded.configuration)
    }

    /// Uloží konfiguraci z okna nastavení a hned ji propíše dál.
    ///
    /// Chyba **letí ven**: neuložené nastavení, o kterém se mlčí, vypadá v okně jako
    /// uložené a po restartu je pryč. Do stavu se přitom propíše až po úspěšném zápisu,
    /// aby se okno a soubor nerozešly.
    func updateConfiguration(_ configuration: Configuration) async throws {
        // Optional chaining by bez tohohle tiše prošlo a okno by hlásilo „Uloženo“ nad
        // něčím, co nikam neodešlo. Store bez `ConfigStore` staví jen testy, ale
        // signatura říká `throws` a to musí platit.
        guard let configStore else { throw ConfigurationError.noStore }
        try await configStore.save(configuration)
        // Na disku teď leží to, co jsme zapsali — starší chyba čtení už neplatí. Uložit se
        // dá jen z odemčeného editoru, takže se tím nepřebíjí soubor, který se nepovedlo
        // přečíst.
        configurationFailure = nil
        await apply(configuration)
    }

    /// Jedna cesta, kterou se nová konfigurace dostane do běžící aplikace — ať přišla
    /// z disku, nebo z okna nastavení. Kdyby byly dvě, jedna z nich by časem zapomněla
    /// něco přepsat.
    private func apply(_ configuration: Configuration) async {
        self.configuration = configuration
        configurationBox?.value = configuration
        // Vzhled (#278) patří sem, a ne do view: `NSApp.appearance` platí pro **všechna** okna,
        // takže se to musí stát na tom jednom místě, kterým konfigurace do aplikace vchází.
        // Ve view by to znamenalo, že se změna neuplatní, když je hlavní okno zavřené a člověk
        // přepíná v nastavení.
        appearance?.applyAppearance(configuration.global.appearance)
        polling.sources = configuration.activeSources
        polling.interval = .seconds(configuration.global.pollIntervalSeconds)
        // Limit souběhu se čte při každém pokusu o slot, ale kdo už čeká ve frontě, spí.
        await reviewer?.configurationChanged()
    }

    /// **Plný** seznam z pollingu, nefiltrovaný a nerozřazený podle autora — a musí to tak zůstat.
    ///
    /// Čte ho to, čeho se **nesmí týkat filtr ani rozřazení podle autora** (#332):
    /// `knownRepositories` (okno nastavení), `filterOptions` (nabídka filtru), `summary(for:)`,
    /// `handleNotificationClicks`, `startAutomaticReviews` po zahození nálezů (#81) — plánovač si
    /// vlastní PR odřízne sám v `Policy.automaticallyReviewable` — a úklid, který bere `summaries`
    /// z tiku.
    ///
    /// Kdyby na zúženém seznamu viselo cokoli z úklidu (`forget(whatIsNotIn:)`, `CacheEviction`,
    /// `ReviewStore.cleanUp`, rušení automatických review), **zapnutí filtru by zahodilo diffy
    /// a konverzace, smazalo cache a zrušilo běžící review**; a na rozřazení podle autora by to
    /// samé udělalo přihlášení jiným účtem, jen navíc potichu. Rozdíl mezi tímhle getterem
    /// a `visiblePullRequests` je jediné, co dělí filtr od mazání cache — a je na to test.
    var pullRequests: [PullRequestSummary] { polling.pullRequests }

    /// Seznam **po filtru** (#117), ještě bez rozřazení podle autora. Čtou ho ty dva zúžené
    /// gettery (`visibleQueuePullRequests`, `visibleOwnPullRequests`), detail vybraného řádku
    /// a klik na notifikaci, který podle něj pozná, že PR schoval filtr.
    var visiblePullRequests: [PullRequestSummary] {
        Policy.filtered(pullRequests, by: filter, isBlocking: hasBlockingFinding(_:))
    }

    /// Projde tenhle PR filtrem? **Jediné místo, kde se k filtru dopočítává blokující nález** (#371).
    ///
    /// Osa „jen blokující“ nestojí na shrnutí PR, ale na uloženém záznamu, takže si ji `matches`
    /// nemá kde vzít sám. Počítání schovaných PR se proto ptá odsud, ne přes `filter.matches` — tři
    /// místa, která si tu odpověď skládají po svém, by znamenala tři různá tvrzení o jednom filtru.
    func passesFilter(_ summary: PullRequestSummary) -> Bool {
        filter.matches(summary) { hasBlockingFinding(summary.id) }
    }

    /// Blokuje na tomhle PR aspoň jeden platný nález? (#371)
    ///
    /// **Globální sada kategorií, ne per repo** — tatáž, s jakou počítá kartu `Blokuje` getter
    /// `dashboard` výš. Filtr, který ta karta zapíná, musí ukázat právě ta PR, která napočítala;
    /// s per-repo sadou by šlo kliknout na `Blokuje 1` a dostat prázdný seznam. Řádek seznamu si dál
    /// bere tu svoji (`queueRow(for:)`), protože mluví o jednom repu, ne o celé frontě.
    func hasBlockingFinding(_ pr: PRIdentifier) -> Bool {
        guard let record = reviewRecords[pr] else { return false }
        return Policy.blockingCount(
            in: record,
            categories: Set(configuration.global.blockingCategories)
        ) > 0
    }

    /// Co nabídnout ve filtru — z **plného** seznamu, sjednocené s aktivním filtrem.
    ///
    /// `pullRequests`, ne `visiblePullRequests`, a od #199 to platí i pro **počty** u položek:
    /// ze zúženého seznamu by odškrtnutí jednoho repa srazilo počty u všech ostatních na nulu,
    /// takže by z nabídky nešlo poznat, co zapnutí položky udělá.
    var filterOptions: PullRequestFilterOptions {
        Policy.filterOptions(in: pullRequests, filter: filter)
    }

    /// Nastaví filtr a **srovná s ním výběr**.
    ///
    /// Vybraný PR, který spadne mimo filtr, výběr **ztrácí**: detail PR, který v seznamu není, se
    /// nedá zavřít ani znovu vybrat kliknutím. Nic se tím neztrácí — draft leží na disku a běžící
    /// review běží dál.
    ///
    /// Ruší se to **jen tady**, ne pokaždé, když vybraný PR ze seznamu vypadne: PR, které z fronty
    /// odešlo tikem, si výběr drží (dnešní chování, které se nemá měnit — mergnutý PR jde ještě
    /// dočíst).
    func setFilter(_ filter: PullRequestFilter) {
        self.filter = filter
        if let selection, !visiblePullRequests.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func clearFilter() { setFilter(PullRequestFilter()) }

    // MARK: - Navigace v domácí záložce

    /// Přepne domácí záložku na sekci railu.
    ///
    /// **Včetně přepnutí na `home`**: sekce railu je obsah domácí záložky, takže nad otevřeným PR by
    /// se jinak nestalo nic viditelného. Chodí sem paleta ⌘K (#184) i karty a patky bloků na
    /// dashboardu (#371) — jedna cesta, ať se na to nezapomene jen v jedné z nich.
    func show(_ section: RailSection) {
        railSection = section
        activeTab = .home
        // Odchod ze sekce `Dění` posouvá značku poslední návštěvy (#414). Musí to být **za**
        // přepnutím: rozhoduje se z toho, co je na obrazovce teď, ne z toho, co se chystá.
        syncActivityVisit()
    }

    /// Klik na kartu nebo patku bloku na dashboardu (#371).
    ///
    /// Karta zná jen cíl (`DashboardDestination`), ne rail ani filtr — složit z toho přepnutí je
    /// práce storu.
    func show(_ destination: DashboardDestination) {
        switch destination {
        case .section(let section):
            show(section)
        case .blockingQueue:
            // Filtr se nastavuje **tou samou cestou jako filtrovací tlačítko** (#117): `setFilter`
            // srovnává s filtrem i výběr, takže druhá kopie by tuhle jednu věc zapomněla.
            //
            // **Ostatní osy zůstávají, jak si je člověk nastavil** — zapíná se jedna osa, ne nový
            // filtr. Že se ta jedna přepíše, je vědomé: bez ní by karta `Blokuje` skákala na totéž
            // místo jako `Čeká na mě`.
            var updated = filter
            updated.onlyBlocking = true
            setFilter(updated)
            show(.queue)
        }
    }

    // MARK: - Záložky (#180)

    /// Otevře PR jako záložku a přepne se na ni. Otevřený PR se **neotevírá podruhé** — kliknutí
    /// na něj v seznamu ho jen vytáhne dopředu, jako v prohlížeči.
    ///
    /// **Jediný vstupní bod pro „otevři tenhle PR“** (#409), a s `tab` i pro „otevři ho na tomhle
    /// tabu“. Chodí sem kliknutí v seznamu, karty dashboardu, paleta ⌘K, klik na notifikaci
    /// a od #414 řádek dění — protože nastavit `activeTab` a `openTabs` jsou dva zápisy, které se
    /// dají provést každý zvlášť, a přesně to bylo #409: obsluha notifikací nastavila `selection`,
    /// tedy stav, který v domácí záložce nikdo nekreslí, a klik na notifikaci **neudělal nic**.
    ///
    /// **`tab: nil` volbu tabu nepřepisuje.** Volba je odpověď na „kam se v tomhle PR koukám“
    /// a drží se per PR (`detailTab(for:)`), takže otevření bez upřesnění má vrátit člověka tam,
    /// kde skončil. Kdo tab **jmenuje**, ho přepíše — a jmenuje ho jedním voláním schválně: skok
    /// na nález (paleta ⌘K) ani na řádek dění (#414) nemá nad zavřenou záložkou kde přistát, takže
    /// dvě volání by znamenala dvě místa, kde se dá zapomenout jedno z nich.
    func openTab(_ pullRequest: PRIdentifier, in tab: PullRequestTab? = nil) {
        if !openTabs.contains(pullRequest) { openTabs.append(pullRequest) }
        if let summary = summary(for: pullRequest) { openTabSnapshots[pullRequest] = summary }
        activeTab = .pullRequest(pullRequest)
        selection = pullRequest
        if let tab { setDetailTab(tab, for: pullRequest) }
        // Otevření záložky je odchod z domácí záložky, takže i ze sekce `Dění` — a odchod posouvá
        // značku poslední návštěvy (#414).
        syncActivityVisit()
    }

    /// Zavře záložku. **Nic se tím nezahazuje** — draft, nálezy i běžící review zůstávají, protože
    /// nic z toho na záložce nevisí.
    ///
    /// **Jedinou výjimkou je shell v zásuvce** (#459), a je to vědomý rozdíl: všechno ostatní se
    /// dá otevřít znovu z disku, kdežto shell je proces, který by po zavřené záložce běžel dál bez
    /// okna, ve kterém by šel vidět — tedy přesně ten sirotek, kvůli kterému vzniklo #264 a #351.
    /// Zásuvka se schová **bez** zabíjení; zavřená záložka je jiná věc než schovaná zásuvka.
    ///
    /// Po zavření se jde na **sousední** záložku, ne domů: zavírá se typicky doprojité review
    /// a další v řadě je to, co člověk chce vidět. Domů se propadne, až když nezbyde žádná.
    func closeTab(_ pullRequest: PRIdentifier) {
        guard let index = openTabs.firstIndex(of: pullRequest) else { return }
        openTabs.remove(at: index)
        openTabSnapshots[pullRequest] = nil
        stopTerminal(for: pullRequest)

        guard activeTab == .pullRequest(pullRequest) else { return }
        let neighbour = openTabs.indices.contains(index) ? openTabs[index] : openTabs.last
        activeTab = neighbour.map(WindowTab.pullRequest) ?? .home
        selection = neighbour
        syncActivityVisit()
    }

    /// Přepne na sousední záložku v pruhu (#245) — `⌃Tab` dopředu, `⌃⇧Tab` zpátky.
    ///
    /// **Nastavuje jedině `activeTab`, jako kliknutí na záložku v pruhu.** Výběr řádku v seznamu je
    /// jiná věc a kliknutí s ním nehýbe; kdyby s ním hýbala zkratka, byly by dvě pravdy o tom, co je
    /// vybrané. Nic dalšího se dělat nemusí: záložka nic nevlastní a obsah si detail dotáhne sám,
    /// přesně jako po kliknutí.
    ///
    /// Kudy se cyklí, rozhoduje `Policy.tab(_:after:open:)` — včetně toho, že se nad jedinou
    /// záložkou nestane nic.
    func selectTab(_ step: NavigationStep) {
        guard let next = Policy.tab(step, after: activeTab, open: openTabs) else { return }
        activeTab = next
        syncActivityVisit()
    }

    /// Shrnutí otevřených záložek. PR, který ze seznamu vypadl, si záložku drží — proto se
    /// hledá i mezi tím, co je vidět, a nezmizí, jen protože ho tik přestal vracet.
    var openTabSummaries: [PullRequestSummary] {
        // Živá data mají přednost (titulek se může změnit), snapshot je záchrana pro PR, které
        // z pollingu vypadlo. `compactMap` sem nepatří: záložka bez shrnutí by z pruhu zmizela
        // i s křížkem, kterým se zavírá.
        openTabs.compactMap { summary(for: $0) ?? openTabSnapshots[$0] }
    }

    /// Shrnutí PR podle identifikátoru. `nil` = o tomhle PR nevíme nic ani z posledního tiku.
    func summary(for pullRequest: PRIdentifier) -> PullRequestSummary? {
        pullRequests.first { $0.id == pullRequest }
    }

    /// Odznak u fronty v railu. `nil`, dokud se seznam nenačetl — nula nad nenačtenými daty
    /// vypadá jako „hotovo“, a to je zrovna ten nebezpečný směr (tatáž úvaha jako u souhrnu).
    ///
    /// **Jen cizí PR** (#332): odznak znamená „tolik lidí čeká na moje review“, takže vlastní PR
    /// v něm tvrdil víc práce, než je. Vlastní má svůj odznak (`railMineCount`) a ten navíc počítá
    /// tahy, ne pull requesty.
    var railQueueCount: Int? {
        lastSuccess == nil ? nil : visibleQueuePullRequests.count
    }

    /// Podklad pro dashboard (#181). Počítá se **z paměti store**, žádné nové čtení z disku.
    ///
    /// Od #331 nese i kartu `Moje PR`, takže dovnitř jdou i moje loginy, cesta k načtené konverzaci
    /// a to, jestli se vlastní PR vůbec sledují — a od #443 i blok `Dění` se záznamem, značkou
    /// poslední návštěvy a důvodem prázdna. Všechno z paměti, jako zbytek.
    var dashboard: Dashboard {
        Policy.dashboard(
            pullRequests: pullRequests,
            records: reviewRecords,
            drafts: drafts,
            categories: Set(configuration.global.blockingCategories),
            since: Calendar.current.date(byAdding: .day, value: -7, to: time.now),
            mine: ownLogins,
            // Uzávěr, ne mapa všech načtených konverzací: dashboard se ptá jen na vlastní PR
            // a skládat pro něj kopii celé diskuze při každém překreslení je práce navíc.
            conversation: conversation(for:),
            // Razítka předání a hlavy PR (#334): karta `Moje PR` počítá totéž, co odznak v railu,
            // takže musí dostat tytéž vstupy — jinak by nad jedním seznamem stála dvě čísla.
            handoff: handoff(for:),
            head: head(of:),
            tracksOwnSource: tracksOwnPullRequests,
            // Dění (#443) — pět nejnovějších řádků do bloku v pravém sloupci. Z **paměti** a v témže
            // snímku: záznam i značka už v store leží kvůli sekci v railu, takže se pro dashboard
            // nic nedotahuje. Značka jde dovnitř jako vstup — posouvá ji jedině `syncActivityVisit()`.
            activity: activityEvents,
            lastVisit: activityVisitSnapshot,
            activityEmpty: activityEmptyState
        )
    }

    /// Fronta na dashboardu (#181) — **cizí PR** seřazené podle závažnosti (#332).
    ///
    /// Ne zúžené filtrem, ze stejného důvodu jako `dashboard` výš: dashboard je tvrzení o tom,
    /// co ve frontě je, ne o tom, co je zrovna vidět. Vlastní PR má vedle vlastní blok
    /// (`dashboardOwnPullRequests`) — do #332 byl v obou.
    var dashboardQueue: [QueueEntry] {
        Policy.byUrgency(
            queuePullRequests.map {
                QueueEntry(
                    pullRequest: $0,
                    state: reviewState(for: $0.id),
                    row: queueRow(for: $0.id),
                    hasDraft: hasDraft($0.id)
                )
            }
        )
    }

    /// Checky na PR (#209), klíčované PR. Prázdné pole = načetlo se a žádné nejsou; chybějící
    /// klíč = ještě se nenačetlo. Ty dva stavy se nesmí slít, jinak by blok nad nenačteným PR
    /// tvrdil „žádné kontroly“.
    ///
    /// Od #215 na prázdnu visí i to, jestli se nakreslí tab `Kontroly` — tím spíš se nesmí slít
    /// se **selháním**, které drží `checkFailures`.
    var checks: [PRIdentifier: [PullRequestCheck]] = [:]

    /// Proč se checky nepodařilo načíst (#215). Chybějící klíč = poslední pokus prošel.
    ///
    /// **Vlastní mapa, ne prázdné pole v `checks`.** Prázdno znamená „PR nemá CI“, což je běžný
    /// stav, kdežto tohle je porucha — a od #215 se ty dva rozcházejí i v tom, co je vidět: bez
    /// CI se tab nekreslí a je to správně, po chybě sítě by zmizel tab, který tam patří.
    var checkFailures: [PRIdentifier: String] = [:]

    /// Commity na PR (#316), klíčované PR. Chybějící klíč = ještě se nenačetlo.
    ///
    /// **Prázdné pole tady nemá význam „PR nemá commity“** — takový pull request neexistuje. Je to
    /// rozdíl proti `checks`, kde prázdno je odpověď; rozhoduje o něm `Policy.commitsTab`, ne tenhle
    /// stav. Mapa jen věrně nese to, co přišlo — **včetně pořadí**: drží se pořadí z API (od
    /// nejstaršího) a otáčí ho až `Policy.commitsNewestFirst` cestou do tabu. Kdyby se otočilo
    /// tady, byla by z pořadí kresby uložená vlastnost dat a nešlo by ho změnit na jednom místě.
    var commits: [PRIdentifier: [PullRequestCommit]] = [:]

    /// Proč se commity nepodařilo načíst (#316). Chybějící klíč = poslední pokus prošel.
    ///
    /// **Vlastní mapa, ne prázdné pole v `commits`**, ze stejného důvodu jako u checků: nenačteno,
    /// prázdno a porucha jsou tři různé odpovědi a nesmí se slít.
    var commitFailures: [PRIdentifier: String] = [:]

    /// Labely a vyžádaní reviewery na PR (#392), klíčované PR. Chybějící klíč = ještě se
    /// nenačetlo.
    ///
    /// **Stav, ne pole**, a ze stejného důvodu jako u `detailStates`: „nic tu není“, „ještě to
    /// nedorazilo“ a „nepodařilo se to zjistit“ jsou tři různé odpovědi. U labelů na tom navíc visí
    /// akce — sada se nastavuje **celá**, takže přeštítkovat PR, jehož štítky aplikace nezná,
    /// znamená ty neznámé smazat.
    var metadataStates: [PRIdentifier: MetadataState] = [:]

    /// Labely, které zná **repozitář** (#392). Chybějící klíč = nabídka se ještě neotvírala.
    ///
    /// Klíčem je repo, ne PR: je to vlastnost repozitáře a mezi dvěma PR z téhož repa se nemění.
    /// Na tom stojí uzavřenost nabídky — z volného textu by se dal vyrobit nový label.
    var repositoryLabels: [RepoID: [PullRequestLabel]] = [:]

    /// Proč se nabídka labelů nenačetla (#392). Chybějící klíč = poslední pokus prošel.
    ///
    /// **Vlastní mapa, ne prázdné pole v `repositoryLabels`**, ze stejného důvodu jako u checků:
    /// „repo žádné labely nemá“ je běžný stav, kdežto tohle je porucha — a nabídka, která po chybě
    /// sítě vypadá jako repo bez labelů, posílá člověka hledat labely, které tam jsou.
    var repositoryLabelFailures: [RepoID: String] = [:]

    /// Loginy lidí, kteří na repo smí (#392). Chybějící klíč = nabídka se ještě neotvírala.
    var assignableUsers: [RepoID: [String]] = [:]

    /// Proč se nabídka lidí nenačetla (#392). Chybějící klíč = poslední pokus prošel.
    var assignableUserFailures: [RepoID: String] = [:]

    /// Slugy týmů, které jde na repu vyžádat (#392). Chybějící klíč = nabídka se ještě neotvírala.
    ///
    /// **Prázdné pole je odpověď**: repo mimo organizaci týmy nemá. Porucha je vedle, v mapě
    /// `assignableUserFailures` — nabídka je jedna, takže i její porucha je jedna věta.
    var assignableTeams: [RepoID: [String]] = [:]

    /// Co se právě děje s labely nebo reviewery (#392). Chybějící klíč = nic.
    var metadataActionStates: [PRIdentifier: MetadataActionState] = [:]

    /// Jestli se dá větev mergnout (#465), klíčované PR. Chybějící klíč = ještě se neptalo.
    ///
    /// **Stav, ne hodnota**, a u nevratné akce je to podstatnější než kdekoli jinde: „nedá se
    /// mergnout“ a „nezjistil jsem, jestli to jde“ musí vést k jiné větě v panelu. Plní se **jen
    /// u vlastních otevřených PR** — jinde by se sekce `Větev` nekreslila a odpověď GitHubu by
    /// stejně byla `UNKNOWN`.
    var branchStatuses: [PRIdentifier: BranchStatusState] = [:]

    /// Co se právě děje se srovnáním větve (#466). Chybějící klíč = nic se neděje.
    ///
    /// **Stav, ne cesta ven** — tatáž konstrukce jako u `metadataActionStates`: akce se ovládá
    /// z panelu a musí přežít překliknutí tabu. Drží i **rozdělaný rebase v cache**, který se
    /// hledá při každém otevření vlastního PR: bez toho by o něm okno po restartu mlčelo.
    var branchSyncStates: [PRIdentifier: BranchSyncState] = [:]

    /// Který commit je v tabu `Commity` rozkliknutý (#317). Chybějící klíč = v tabu je seznam.
    ///
    /// **Jen žádost okna**, ne tvrzení o PR: že ten commit na PR pořád je, rozhoduje
    /// `Policy.openCommit(_:in:)` proti čerstvému seznamu.
    var openCommits: [PRIdentifier: String] = [:]

    /// Poslední stažený diff commitu, **nejvýš jeden na PR** (#317).
    ///
    /// Strop je v klíči schválně — proč, je u `CommitDiff`. Návratem do seznamu se nezahazuje:
    /// je to zároveň paměť na to, kde v seznamu člověk byl (`lastOpenedCommit(in:)`).
    var commitDiffs: [PRIdentifier: CommitDiff] = [:]

    /// Je v hlavičce rozkliknutého commitu vidět **tělo zprávy** (#317)?
    ///
    /// **Globálně, ne per PR ani per commit** — je to předvolba pohledu, stejně jako
    /// `isReviewPanelExpanded` a `diffLayout`: „kolik místa nechat zprávě a kolik diffu“ znamená
    /// u každého commitu totéž. Mapa by navíc byla další stav k uklízení ve `forgetPullRequest`,
    /// a to za odpověď na otázku, kterou si nikdo neklade zvlášť pro každý pull request.
    ///
    /// **Ve store, ne v `@State` detailu**, a je to podmínka: `PullRequestDetailView` si SwiftUI
    /// mezi pull requesty ponechá (stejná pozice ve stromu), takže by volba přetekla z jednoho PR
    /// na druhý — tatáž past jako u `detailTabs` a u rozbalení dráhy v #294. Tady by přetekla
    /// „náhodou správně“, protože je stejně globální, ale nešlo by to otestovat ani vypnout.
    ///
    /// **Výchozí stav je rozbaleno.** Tělo zprávy je odpověď na „proč“, tedy to, kvůli čemu se do
    /// commitu chodí; sbalí se jedním kliknutím a drží to celou session, takže výchozí sbaleno by
    /// jen schovalo obsah tomu, kdo si o to neřekl. **Neukládá se do `Configuration`** ze stejného
    /// důvodu jako `isReviewPanelExpanded`: je to okamžité „udělej teď místo“, ne standing
    /// předvolba, která by si zasloužila řádek v nastavení.
    var isCommitMessageExpanded = true

    /// Který check je v tabu `Kontroly` rozbalený (#214), na PR nejvýš jeden.
    ///
    /// Dva otevřené konce logu pod sebou znamenají scrollování přes to, co se zrovna nečte — a dvě
    /// sady megabajtů v paměti.
    var expandedChecks: [PRIdentifier: String] = [:]

    /// Anotace a log rozbaleného checku (#214).
    ///
    /// **Neukládá se na disk a nemá přežít sbalení checku ani restart.** Log není nález: neplatí
    /// proti `headSha`, nedá se odmítnout a příště se stáhne znovu, takže v cache vedle nálezů nemá
    /// co dělat. Drží ho tenhle stav a zaniká s oknem.
    var checkDetails: [CheckKey: CheckDetailState] = [:]

    /// Běžící stahování detailu checku — kvůli **zrušení** při sbalení a při úklidu.
    ///
    /// Bez něj by osmimegový log dobíhal do stavu, který už nikdo nečte, a zapsal by text, který se
    /// má zapomenout. Čtyři vteřiny jsou za hranicí, kdy stačí přebarvit tlačítko.
    var checkTasks: [CheckKey: Task<Void, Never>] = [:]

    /// Kdy se polling zeptá znovu. `nil`, dokud smyčka poprvé neusne.
    var nextPoll: Date? { polling.nextPoll }

    /// Ptá se polling právě teď? Čte to odpočet v hlavičce dashboardu (#237) — po dobu dotazu
    /// je `nextPoll` v minulosti, takže se místo něj píše, co se děje.
    var isRefreshing: Bool { polling.isRefreshing }

    /// Útrata po dnech pro graf. Prázdné, dokud se nenačte — sedm nul by vypadalo jako týden
    /// bez práce, ne jako chybějící data.
    ///
    /// Zapisuje se ze dvou míst — při startu a po doběhlém běhu — takže `internal`, jako
    /// ostatní stav, na který sahají extensiony `AppStore+*` (#154).
    var spendHistory: [DaySpend] = []

    /// PR, na kterých leží rozdělané review — obsah sekce `Rozdělaná`.
    ///
    /// Čte **plný** seznam, ne zúžený filtrem: rozdělané review je moje práce, a ta se nemá
    /// schovávat tím, že jsem si zúžil pohled na jiné repo. Tatáž úvaha jako u souhrnu fronty.
    var pullRequestsWithDraft: [PullRequestSummary] {
        pullRequests.filter { hasDraft($0.id) }
    }

    var status: PollStatus { polling.status }

    var lastSuccess: Date? { polling.lastSuccess }

    var isStale: Bool { polling.isStale }

    var emptyReason: PollEmptyReason? { polling.emptyReason }

    /// Proč je **fronta** prázdná — včetně toho, že ji schoval filtr (#117).
    ///
    /// Skládá to store, ne polling: ten o stavu okna neví a vědět nemá. Pořadí důvodů rozhoduje
    /// `Policy.listEmptyReason` a nad selhaným tikem vyhrává chyba načtení, ne filtr.
    ///
    /// **Počítá se z fronty, ne z celého seznamu** (#332). Tik, ve kterém přišla jen moje PR,
    /// nechá frontu prázdnou, kdežto `emptyReason` mlčí — a bez tohohle by v okně zbyl prázdný
    /// seznam bez věty. Vysvětlení pak vyjde `poll(.noPullRequests)`, tedy „až po tobě někdo
    /// bude chtít review, objeví se tady“.
    var listEmptyReason: ListEmptyReason? {
        // Jedním průchodem, jako u `ownListEmptyReason`: rozřazení podle autora i filtr by jinak
        // seznam prošly každý zvlášť, a tenhle getter čte SwiftUI při každém překreslení seznamu.
        let queue = queuePullRequests
        let hidden = filter.isActive ? queue.count { !passesFilter($0) } : 0
        return Policy.listEmptyReason(
            poll: emptyReason,
            visible: queue.count - hidden,
            hidden: hidden
        )
    }

    /// Puntíky pro stavový řádek. Prázdné, když se dostupnost odsud nesleduje.
    var healthReports: [ServiceHealthReport] { health?.reports ?? [] }

    /// Řekne monitoru, jestli je okno vidět — na pozadí se nekontroluje nic.
    ///
    /// Skryté okno interval **neposouvá**, takže po dlouhé nepřítomnosti se zkontroluje
    /// hned na prvním taktu a po krátké se nekontroluje zbytečně. Puntík se stavem z doby,
    /// kdy se nesledovalo, tak nevisí déle než takt.
    func windowVisibilityChanged(_ visible: Bool) {
        health?.isWindowVisible = visible
    }

    /// Jak dopadl poslední dotaz na GitHub — odvozeno z pollingu, ne vedeno zvlášť.
    ///
    /// Polling se ptá každou minutu a je to **totéž volání**, na kterém stojí zbytek
    /// aplikace, takže lepší zdravotní signál se nedá koupit. Ostatní volání gateway
    /// (detail, diff, konverzace) sem schválně nepřitékají: běží nepravidelně a jejich
    /// `notFound` není o dostupnosti, nýbrž o tom, že na PR nevidíme.
    private var gitHubCall: ServiceCall? {
        switch polling.status {
        case .notStarted:
            nil
        case .upToDate:
            polling.lastSuccess.map { ServiceCall(since: $0) }
        case .failing(let since, let reason):
            ServiceCall(since: since, failure: reason.userDescription)
        case .rateLimited(let since, let retryAt):
            // Rate limit **je** selhané volání, i když si ho aplikace způsobila sama tím,
            // že se ptá moc. Zelená znamená „funguje mi to“ a tady to nefunguje; že za to
            // GitHub nemůže, řekne věta.
            ServiceCall(
                since: since,
                failure: "GitHub omezuje dotazy — zkusím to v \(retryAt.formatted(date: .omitted, time: .shortened))."
            )
        }
    }

    /// Jak dopadla poslední headless session. `nil` = žádná ještě neběžela.
    ///
    /// Jde jen o **review**, ne o překlad nálezů: ten se smí nepovést tiše (nálezy zůstanou
    /// v originále), takže by se z něj červený puntík vyráběl nad něčím, co za chybu ani
    /// nepovažujeme.
    var lastReviewCall: ServiceCall?

    /// Drží seznam aktuální, dokud okno žije. Zrušení tasku smyčku ukončí.
    func keepFresh() async {
        await reloadConfiguration()
        // **Před** načtením záznamů: dotažené nálezy se mají objevit hned po startu, ne až
        // po dalším review. Kdyby se dotahovalo potom, `reviewRecords` by je neobsahovaly.
        await recoverInterruptedRuns()
        await loadStoredReviews()
        await loadStoredDrafts()
        // Razítka předání (#334) se čtou **jednou**: odznak a pilulka se pak ptají paměti. Před
        // pollingem, ať se PR nekreslí na okamžik jako nepředaný — to je zrovna to bliknutí,
        // kvůli kterému odznak přestává něco znamenat.
        await loadStoredHandoffs()
        // Dění (#414) taky **jednou** a ze stejného důvodu: sekce i odznak v railu se pak ptají
        // paměti. Značka poslední návštěvy se čte spolu s ním — kdyby se čekalo na první otevření
        // sekce, byl by první snímek značky až po tom, co se na obrazovku podívám, a nové by
        // nebylo nic.
        await loadStoredActivity()
        await loadDailySpend()
        // Všechno běží, dokud žije okno; zrušení tasku ukončí skupinu i se všemi smyčkami.
        await withTaskGroup(of: Void.self) { group in
            // Login se dotahuje **souběžně s pollingem, ne před ním** (#330): `gh api user` stojí
            // půl sekundy a seznam PR na něj nemá proč čekat. Dokud nedorazí, je `viewer` prázdný,
            // což znamená „nevím“ — tedy všechno cizí, ne všechno moje. Je to jednorázový task,
            // takže skupinu nedrží.
            group.addTask { await self.loadViewer() }
            group.addTask { await self.polling.run() }
            if let health {
                group.addTask { await health.run() }
            }
            if notifications != nil {
                group.addTask { await self.handleNotificationClicks() }
            }
        }
    }

    /// Dotáhne nálezy z běhů, které aplikaci nepřežily (#97).
    ///
    /// Potvrzovací dialog při zavření (#94) pokrývá jen to, co uživatel způsobí svým jednáním.
    /// Pád aplikace, `kill` ani restart Macu se odchytit nedají — a nálezy se tam ztrácely
    /// stejným způsobem: session se zabila, `ReviewStore` neměl záznam a řádek ukazoval
    /// `neběželo`, tedy totéž jako u PR, který nikdo nekontroloval. Za jeden den vývoje spadla
    /// aplikace dvakrát, takže to není teoretická situace.
    ///
    /// Běží **při startu, jednou**: značky, které v souboru zbyly, jsou přesně ty běhy, po
    /// kterých nikdo neuklidil. Uloží se jako `interrupted`, ne jako doběhlé — chybí `result`
    /// event, takže se neví, jestli reviewer skončil, a `clean` by nad tím lhalo.
    ///
    /// **Nezapsaný nález tady běh nepoloží**, na rozdíl od doběhlého review: tohle je záchranná
    /// síť nad daty, která už jednou spadla pod stůl. Selhání jednoho dotažení nesmí zastavit
    /// ostatní ani položit start aplikace; značka zůstane a příští start to zkusí znovu.
    func recoverInterruptedRuns() async {
        guard let interrupted, let transcripts, let reviews else { return }

        for run in await interrupted.pending() {
            // Značka nad **touž session**, která je uložená, znamená, že aplikace spadla mezi
            // zápisem výsledku a smazáním značky. Dotáhnout ji znovu by přepsalo doběhlý běh
            // přerušeným — tedy z hotového review udělalo nedodělek. Tohle okno zavřít nejde,
            // takže je ta brána důležitější než pořadí, ve kterém se maže.
            //
            // Porovnává se **`sessionID`, ne skill** (#97). Skill by byl moc hrubý: záznam pro
            // tentýž commit může být ze **staršího** review, a to je zrovna situace, kdy se
            // nálezy dotáhnout mají — jinak by nad novým během zůstalo viset staré „čisté“.
            // Vyšlo to najevo na živé zkoušce, ne z úvahy.
            if let existing = await reviews.record(for: run.pullRequest, at: run.headSha),
               existing.runs.contains(where: { $0.sessionID == run.sessionID }) {
                await interrupted.forget(run.key)
                continue
            }

            // **`do`/`catch`, ne `try?`.** Ten by obě odpovědi slil do `nil` — Swift výsledek
            // `try?` nad funkcí vracející optional zplošťuje, takže „vyhodilo“ a „vrátilo nic“
            // vyjde stejně. A rozdíl mezi nimi je tady celý smysl: transcript, který **není**,
            // už nebude (strom sebrala eviction), kdežto ten, který se nedá **přečíst**, tam
            // pořád leží i s nálezy. Chytil to test.
            let found: StreamSummary?
            do {
                found = try await transcripts.summary(ofSession: run.sessionID, in: run.worktree)
            } catch {
                // Značka zůstává, ať to příští start zkusí znovu.
                continue
            }

            guard let summary = found else {
                await interrupted.forget(run.key)
                continue
            }

            // Transcript má `sessionId`, kdežto `stream-json` `session_id` — parser proto z
            // transcriptu id nevytáhne. Doplní se ze značky, ve které je autoritativně:
            // bez něj by dotažený běh neuměl nabídnout `claude --resume` v ose a hlavně by
            // brána o kus výš neměla co porovnávat.
            var recoveredSummary = summary
            recoveredSummary.sessionID = summary.sessionID ?? run.sessionID
            let recovered = ReviewRun(key: run.key, summary: recoveredSummary, outcome: .interrupted)
            do {
                reviewRecords[run.pullRequest] = try await reviews.save(recovered)
                await interrupted.forget(run.key)
            } catch {
                // Značka zůstává, ať to příští start zkusí znovu — nálezy v transcriptu nikam
                // nezmizely.
                continue
            }
        }
    }

    /// Poznamená si, že běh začal (#97). Volá se, jakmile ze session dorazí `session_id`.
    func markInterrupted(
        _ sessionID: String,
        of skill: String,
        for pr: PRIdentifier,
        at headSha: String,
        in worktree: URL
    ) async {
        guard let interrupted else { return }
        let run = InterruptedRun(
            pullRequest: pr,
            headSha: headSha,
            skill: skill,
            sessionID: sessionID,
            worktree: worktree
        )
        await interrupted.remember(run)
    }

    /// Zjistí, kdo se dívá (#330). **Jednou za spuštění**, ne na tik pollingu.
    ///
    /// Je tady, a ne v `AppStore+Ownership.swift`, ze dvou důvodů: patří k ostatním věcem, které
    /// se načítají při startu, a `viewer` je `private(set)` — zapisovat ho smí jedině tenhle
    /// loader, ne kterýkoli extension nebo view.
    ///
    /// **Selhání se nedrží jako vlastní stav — a není to spolknutá chyba.** `gh api user` sahá na
    /// týž `gh` a týž token jako polling, takže co položí tohle, položí i seznam PR, a *to* v okně
    /// vidět je: červený puntík GitHubu ve stavovém řádku i s větou, co se nepovedlo. Druhý, tišší
    /// opis téhož signálu by k němu nepřidal nic a musel by se někde kreslit — tedy nová věc na
    /// obrazovce, na kterou tohle issue nemá mockup. Co po selhání zbude, je `viewer` prázdný, tedy
    /// „nevím“: podle `Policy.ownership` je pak všechno cizí, což je ta bezpečná strana. Že login
    /// chybí, se v okně projeví prázdnou sekcí `Moje PR`, a vysvětlit to je věc jejího prázdného
    /// stavu (#331).
    ///
    /// **Neopakuje se.** Kdo se přihlásí až po spuštění aplikace, se o svých PR dozví po restartu;
    /// dotaz na každý tik by byl podproces navíc každou minutu za údaj, který se nemění.
    func loadViewer() async {
        do {
            viewer = try await gateway.fetchViewer()
        } catch {
            // Prázdný `viewer` zůstává prázdný — viz doc výš. Mlčí se o tom vědomě, protože totéž
            // selhání hlásí puntík GitHubu ve stavovém řádku.
        }
    }

    /// Nálezy z minula. Bez toho by se po startu tvářil každý PR, že se nikdy nereviewoval.
    ///
    /// Selhání čtení se **smí** spolknout, na rozdíl od selhání zápisu: nepřečtený soubor
    /// nikam nezmizel a příští start ho zkusí znovu. Co se přečíst nepodařilo po souborech,
    /// se navíc počítá do `unreadableReviewFiles` a je to vidět pod seznamem.
    func loadStoredReviews() async {
        guard let reviews else { return }
        guard let loaded = try? await reviews.load() else { return }
        reviewRecords = Policy.currentRecords(from: loaded.records)
        unreadableReviewFiles = loaded.unreadable
    }

    /// Co dneska stálo review (#148). `nil` = nemáme kde vzít (bez `SpendLedger`u v testech).
    ///
    /// Drží se **spotřeba**, ne zbytek, jako u `automaticRunsToday`: rozpočet v penězích
    /// aplikace nemá (viz specifikace) a i kdyby ho měla, snímek „zbývá X“ by po změně limitu
    /// lhal až do dalšího běhu.
    var dailySpend: DailySpend?

    /// Načte útratu z disku. Volá se při startu, ať řádek po restartu neukazuje nulu nad
    /// dnem, ve kterém už se utrácelo.
    func loadDailySpend() async {
        guard let spend else { return }
        dailySpend = await spend.spentToday()
        // Historie kvůli grafu v dashboardu (#181). Čte se **jedním** dotazem spolu s dneškem,
        // ne při každém překreslení karty: je to soubor na disku, ne hodnota v paměti.
        spendHistory = await spend.recentDays()
    }

    /// Rozdělaná review z minula. Bez toho by po startu vypadalo každé PR jako nedotčené.
    ///
    /// **Selhání čtení se tady nespolkne**, na rozdíl od nálezů. Nepřečtený soubor sice nikam
    /// nezmizel a příští start ho zkusí znovu, ale u nálezů se nejhůř utratí session, kdežto
    /// tady by chybějící indikátor znamenal, že se ručně psané review napíše podruhé — a to
    /// se druhým pokusem nespraví. Co se nepodařilo přečíst po souborech, se **počítá**.
    func loadStoredDrafts() async {
        guard let draftStore else { return }
        do {
            let loaded = try await draftStore.load()
            drafts = Dictionary(uniqueKeysWithValues: loaded.drafts.map { ($0.pullRequest, $0) })
            unreadableDraftFiles = loaded.unreadable
            pruneBlankComments()
        } catch {
            draftFailure = "Rozdělaná review se nepodařilo načíst. \(error.localizedDescription)"
        }
    }

    /// Zahodí prázdné komentáře, které přežily do dalšího spuštění.
    ///
    /// Za normálního běhu je uklidí bublina, když se od ní odejde. Pád aplikace nebo zabití
    /// zvenčí ale k té chvíli nedojde — a prázdný komentář **blokuje odeslání celého review**,
    /// takže by po restartu zůstal ležet jako důvod, proč to nejde poslat. Nic se tím
    /// neztrácí: prázdný komentář nenese žádný text.
    private func pruneBlankComments() {
        for (pr, draft) in drafts {
            let kept = draft.comments.filter {
                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard kept.count != draft.comments.count else { continue }
            var pruned = draft
            pruned.comments = kept
            // Prázdný draft se maže — a soubor na disku se musí srovnat s tím, co je v paměti.
            drafts[pr] = pruned.isEmpty ? nil : pruned
            persistDraft(for: pr)
        }
    }

    /// Tlačítko „obnovit teď“ — tik mimo pořadí.
    ///
    /// **Druhý dotaz se během prvního nepustí** (#442), a rozhoduje o tom tatáž funkce, ze které
    /// si tlačítko bere podobu (`Policy.refreshControl`). Zašedlé tlačítko je totiž jen půlka:
    /// tutéž akci nabízí paleta ⌘K, prázdný stav seznamu (`Zkusit znovu`) a #441 k tomu přidá
    /// zkratku `⌘R` — a druhý souběžný dotaz by ten první nezrychlil, jen by po sobě přepsal
    /// stav pollingu a nechal `isRefreshing` viset o kolo dýl, než se aplikace doopravdy ptá.
    func refresh() async {
        guard Policy.refreshControl(isRefreshing: isRefreshing).isEnabled else { return }
        await polling.refresh()
    }

    /// Repa, se kterými se právě pracuje — odvozeno ze stavu, ne vedené zvlášť. Množina
    /// s ručním `insert`/`remove` by u dvou souběžných příprav téhož repa sundala ochranu
    /// při první, která doběhne.
    ///
    /// Patří sem i repa s **běžícím review**, ne jen ta, která se právě klonují: smazat klon
    /// pod běžící session by jí vzalo pracovní strom pod rukama. A od #150 stejně tak repa
    /// s běžící kontrolou nálezů — je to tatáž session nad tímtéž stromem.
    var busyRepositories: Set<RepoID> {
        Set(checkoutStates.filter { $0.value == .preparing }.keys)
            .union(reviewTasks.keys.map(\.repo))
            .union(recheckTasks.keys.map(\.repo))
            // A od #452 i repa s běžící odpovědí v tabu `Zeptat se` — je to zase tatáž session
            // nad tímtéž stromem.
            .union(askTasks.keys.map(\.repo))
            // Srovnání větve pracuje ve **vlastním** stromě v cache (#466), takže se ten klon
            // nesmí uklidit pod rukama — a od #467 v něm navíc běží session, která do něj píše.
            .union(branchSyncTasks.keys.map(\.repo))
    }

    func checkoutState(for repo: RepoID) -> CheckoutState {
        checkoutStates[repo] ?? .absent
    }

    func reviewState(for pr: PRIdentifier) -> ReviewState {
        Policy.reviewState(
            phase: reviewPhases[pr],
            record: reviewRecords[pr],
            checkout: checkoutState(for: pr.repo),
            categories: resolved(for: pr.repo).blockingCategories
        )
    }

    func reviewRecord(for pr: PRIdentifier) -> ReviewRecord? { reviewRecords[pr] }

    /// Odvozená čísla pro řádek seznamu (#172) — kolik nálezů blokuje a jak se rozdělily mezi
    /// reviewery. Blokující sada je **per repo**, takže se bere z konfigurace stejně jako
    /// u `reviewState(for:)`; jinak by řádek a odznak v detailu tvrdily každý něco jiného.
    func queueRow(for pr: PRIdentifier) -> QueueRow {
        Policy.queueRow(
            for: reviewRecords[pr],
            categories: resolved(for: pr.repo).blockingCategories
        )
    }

    /// Souhrn nad frontou pro stavový řádek (#155). `nil` = nemá se co sčítat.
    ///
    /// **Rozhodnutí „ukázat, nebo ne“ je tady, ne v `Policy` ani ve view**, protože jediné, co ho
    /// rozhoduje, je stav pollingu — a ten zná store. Souhrn se **neukáže**:
    ///
    /// - dokud se seznam nenačetl (`lastSuccess == nil`): nula blokujících by nad nenačtenými daty
    ///   vypadala jako „čisto“, a to je zrovna ten nebezpečný směr;
    /// - když je fronta prázdná: o tom mluví prázdný stav seznamu, a to i s důvodem.
    ///
    /// **Po selhaném tiku se naopak ukáže** — jen nad zastaralými daty, což už hlásí banner nad
    /// seznamem. Schovat souhrn při každém výpadku by znamenalo, že o rozdělaném review přestanu
    /// vědět kvůli chvilkové chybě sítě.
    ///
    /// Blokující kategorie se berou **globální**, ne per repo: souhrn je jedno číslo přes celou
    /// frontu, takže se nemá čím rozhodnout, které repo má přednost. Řádek seznamu si dál bere ty
    /// svoje (`reviewState(for:)`).
    ///
    /// **Sčítá jen frontu, tedy cizí PR** (#332). Souhrn stojí vedle zvonku a účtu a odpovídá na
    /// „kolik toho na mě čeká“; vlastní PR je druhá fronta a mluví o ní rail a dashboard. Kdyby se
    /// počítala obojí, byla by v jedné větě dvě různá tvrzení o jednom čísle.
    var queueSummary: QueueSummary? {
        guard polling.lastSuccess != nil else { return nil }
        let summary = Policy.summary(
            of: queuePullRequests,
            records: reviewRecords,
            drafts: drafts,
            categories: Set(configuration.global.blockingCategories)
        )
        return summary.isEmpty ? nil : summary
    }

    /// Běží nad PR review? Rozhoduje běžící úloha, ne fáze — ta zůstává i po selhání, aby
    /// bylo z čeho ukázat důvod.
    func isReviewing(_ pr: PRIdentifier) -> Bool { reviewTasks[pr] != nil }

    /// Kolik běhů běží napříč PR. Podle toho se ptá dialog při ukončení aplikace (#94).
    ///
    /// Ze stejného zdroje jako `isReviewing`, ne z vlastního počitadla: dvě místa, která se
    /// můžou rozejít, by v nejhorším nechala aplikaci zavřít bez zeptání.
    ///
    /// **Počítá i kontroly nálezů** (#150): dialog se ptá kvůli tomu, že se zavřením zabije
    /// session, a kontrola je session jako každá jiná. Vynechat ji by znamenalo zavřít aplikaci
    /// bez zeptání nad běžícím `claude`.
    ///
    /// **A od #452 i rozhovory**, ze stejného důvodu: odpověď v tabu `Zeptat se` je `claude -p`
    /// session, která po zavření aplikace přežije na `launchd` (#264).
    var runningReviews: Int { reviewTasks.count + recheckTasks.count + askTasks.count }

    /// Které reviewery běžící review pouští. Celá nastavená sada, když neběží nic — chipy pak
    /// ukazují to, co by se spustilo.
    func runningSkills(for pr: PRIdentifier) -> [String] {
        reviewTasks[pr]?.skills ?? reviewSkills(for: pr.repo)
    }

    /// Připraví pracovní kopii repa. Slouží i jako „zkusit znovu“ po selhání — příprava
    /// je idempotentní, takže opakování je totéž volání.
    ///
    /// Po úspěchu se stav vrací na `notStarted`: `ReviewState` popisuje **review**, a to
    /// se ještě nespustilo. Že je kopie připravená, ukazuje detail, ne odznak v řádku.
    func prepareCheckout(for pr: PRIdentifier) async {
        guard let checkout else { return }
        let previous = checkoutState(for: pr.repo)
        checkoutStates[pr.repo] = .preparing

        do {
            checkoutStates[pr.repo] = .ready(try await checkout.prepare(pr.repo))
        } catch is CancellationError {
            // Zrušení není selhání checkoutu — a `localizedDescription` by z něj udělalo
            // anglickou systémovou hlášku v české aplikaci.
            checkoutStates[pr.repo] = previous
        } catch let error as CheckoutError {
            checkoutStates[pr.repo] = .failed(error.userDescription)
        } catch {
            checkoutStates[pr.repo] = .failed(error.localizedDescription)
        }
    }

    func checkoutPath(for pr: PRIdentifier) -> URL? {
        guard case .ready(let url) = checkoutState(for: pr.repo) else { return nil }
        return url
    }

    /// Srovná stav podle toho, co je **teď** v cache. Volá se při výběru řádku, nic
    /// nestahuje.
    ///
    /// Nejde jen o doplnění chybějícího: klon mohla mezitím sebrat eviction, takže se
    /// zapsaná cesta musí ověřit znovu — jinak by detail ukazoval „připraveno“ na složku,
    /// která už neexistuje. Běžící přípravu to nepřepisuje.
    func noteExistingCheckout(for pr: PRIdentifier) async {
        guard checkoutState(for: pr.repo) != .preparing else { return }
        if let clone = await checkout?.existingClone(for: pr.repo) {
            checkoutStates[pr.repo] = .ready(clone)
        } else if case .failed = checkoutState(for: pr.repo) {
            return // Chybu drž, dokud si uživatel neřekne o opakování.
        } else {
            checkoutStates[pr.repo] = .absent
        }
    }

    /// Kolik řádků kolem nálezu se dotáhne. Samotný řádek bez okolí se čte špatně.
    static let findingContext = 3

    /// Kolik review dnes automat spustil. `nil` = automat není nastavený nikde, takže se
    /// o limitu nemá co mluvit.
    ///
    /// **Spotřeba, ne zbytek.** Porovnání s limitem patří tam, kde se kreslí, protože limit
    /// se dá změnit v nastavení kdykoli — snímek „zbývá 0“ by po zvednutí limitu tvrdil, že
    /// je pozastaveno, až do dalšího tiku.
    var automaticRunsToday: Int?

    /// Co se v běhu stalo. **Konec běhu jde stejným proudem jako průběh** — jinak by ho
    /// osa dostala dřív než události, které mu předcházely, a někdy vůbec.
    enum ReviewEvent: Sendable {
        case progress(skill: String, ReviewProgress)
        /// Doběhlý běh celý, ne jen jeho výsledek (#308). Skill, výsledek i cenu (#148) si osa
        /// vezme z něj — a hlavně: **z proudu se běh i ukládá**, takže se osa zapisuje na disk
        /// až po tom, co do ní dojedou události, které konci předcházely. Do #308 tady byla
        /// jen trojice `(skill, outcome, usage)` a uložení běželo mimo proud, což znamenalo, že
        /// se uloženou osou rozhodoval závod: hotová, `[ve frontě]`, nebo vůbec žádná.
        case finished(ReviewRun)
    }

    /// Zahodí stav rep, o která už není zájem. Bez toho by mapa rostla donekonečna a PR,
    /// které se po týdnu vrátí do seznamu, by přivítala chyba z minula.
    private func forget(whatIsNotIn summaries: [PullRequestSummary]) {
        let wanted = Set(summaries.map(\.id.repo))
        checkoutStates = checkoutStates.filter { wanted.contains($0.key) || $0.value == .preparing }

        // Diff velkého PR jsou megabajty, takže se drží jen pro to, co je v seznamu.
        // Rozdělané načítání přežije ze stejného důvodu jako běžící příprava: jinak by si
        // ho doběhlé volání zapsalo zpátky a v mapě by zůstalo tak jako tak.
        let wantedPullRequests = Set(summaries.map(\.id))
        diffStates = diffStates.filter { wantedPullRequests.contains($0.key) || $0.value == .loading }
        // Rozsahový diff (#284) jde tou samou cestou a ze stejného důvodu — jsou to tytéž
        // megabajty a rozdělané načítání by si sebe zapsalo zpátky.
        incrementalDiffs = incrementalDiffs.filter {
            wantedPullRequests.contains($0.key) || $0.value.content == .loading
        }
        expansions = expansions.filter {
            wantedPullRequests.contains($0.key.pullRequest) || $0.value.isLoading
        }
        // Sbalení je jen příznak, ale drží klíč s celým identifikátorem PR — bez úklidu by
        // množina rostla donekonečna.
        foldedFiles = foldedFiles.filter { wantedPullRequests.contains($0.pullRequest) }
        // Hledání v diffu (#152) drží **seznam výskytů**, tedy řádky kódu — u PR mimo seznam je to
        // paměť, kterou nikdo nepřečte. Rozdělané se tu čekat nedá: pruh je stav okna, ne volání.
        diffSearches = diffSearches.filter { wantedPullRequests.contains($0.key.pullRequest) }
        // Detail se drží jen pro to, co je v seznamu — je z něj `headSha` pro draft, a ten
        // se u PR mimo seznam nepíše. Rozdělané načítání přežije jako u diffu.
        //
        // **Rozdělané review se nezahazuje.** Je to ručně psaná práce, mapa je jeden malý
        // záznam na PR a PR, které ze seznamu vypadlo, se do něj umí vrátit (znovuotevření).
        detailStates = detailStates.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        // Konverzace se drží ze stejného důvodu jako diff — u PR s desítkami vláken to nejsou
        // kilobajty. Rozdělané načítání přežije, aby si ho doběhlé volání nezapsalo zpátky.
        conversationStates = conversationStates.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        // Překliknutá vlákna se uklízejí podle **PR**, ne podle vláken v načtených
        // konverzacích. Podle konverzací to nešlo: PR ve stavu `.failed` v mapě zůstane, ale
        // žádná vlákna nedá, takže by výpadek sítě uživateli zahodil, co si zavřel.
        toggledThreads = toggledThreads.filter { wantedPullRequests.contains($0.key) }
        // Překliknuté rozbalení nálezů (#185) jde tou samou cestou: je to stav okna k jednomu
        // PR, takže s PR mimo seznam nemá co držet.
        toggledFindings = toggledFindings.filter { wantedPullRequests.contains($0.key) }
        // Rozepsané odpovědi a stavy odesílání jdou s konverzací, ke které patří. Klíč nese PR
        // právě kvůli tomuhle — z `id` vlákna by se nepoznalo, ke kterému PR patří.
        threadReplies = threadReplies.filter { wantedPullRequests.contains($0.key.pullRequest) }
        threadStates = threadStates.filter { wantedPullRequests.contains($0.key.pullRequest) }
        // Totéž pro rozepsaný komentář pod PR: bez konverzace, do které patří, se nemá kde
        // ukázat ani odeslat.
        pullRequestComments = pullRequestComments.filter { wantedPullRequests.contains($0.key) }
        pullRequestCommentStates = pullRequestCommentStates.filter {
            wantedPullRequests.contains($0.key)
        }
        // Volba tabu je jen příznak, ale drží klíč s celým identifikátorem PR — bez úklidu by
        // mapa rostla donekonečna, stejně jako u sbalených souborů.
        detailTabs = detailTabs.filter { wantedPullRequests.contains($0.key) }
        // Cíl pro ⇧ klik (#110) je jen zkratka pro to, co je zrovna na obrazovce. Draft sám se
        // drží dál — kdyby se PR vrátilo, komentáře v něm jsou, jen se ⇧ klikem nedá roztáhnout
        // něco, na co se člověk mezitím přestal dívat.
        rangeTargets = rangeTargets.filter { wantedPullRequests.contains($0.key) }
        // Rozdělané tažení nemá s PR mimo seznam co dělat — a je to stav v řádu sekundy.
        if let drag = commentDrag, !wantedPullRequests.contains(drag.pullRequest) { commentDrag = nil }
        // Totéž pro nevyzvednutý skok z palety (#184): PR, který ze seznamu vypadl, se nemá kde
        // nakreslit, takže by žádost zůstala ležet a nikdo by ji nepřečetl.
        if let jump = paletteJump, !wantedPullRequests.contains(jump.pullRequest) { paletteJump = nil }
        // Běžící review si osu drží: `reviewTasks` je pravda o tom, co ještě běží, a jeho
        // události by se jinak zapisovaly do mapy, ze které je někdo právě vyhodil.
        reviewTimelines = reviewTimelines.filter {
            wantedPullRequests.contains($0.key) || reviewTasks[$0.key] != nil
        }

        // Proč kontrola nálezů selhala (#150), platí k jednomu PR — bez něj v okně není kde to
        // ukázat. Běžící kontrola se naopak **neruší**, stejně jako ruční review: vyžádal si ji
        // člověk a zrušit mu ji proto, že PR mezitím někdo mergnul, je horší než session navíc.
        recheckFailures = recheckFailures.filter { wantedPullRequests.contains($0.key) }

        // Checky a důvod, proč se nenačetly (#209, #215). Obojí platí k jednomu PR a drží klíč
        // s celým identifikátorem, takže by mapy bez úklidu rostly donekonečna — stejně jako
        // u volby tabu. Uklízí se **spolu**: kdyby zůstal jen důvod, hlásilo by okno poruchu
        // u PR, které v seznamu není.
        checks = checks.filter { wantedPullRequests.contains($0.key) }
        checkFailures = checkFailures.filter { wantedPullRequests.contains($0.key) }

        // Commity a důvod, proč se nenačetly (#316) — tatáž dvojice a tentýž důvod jako o řádek
        // výš. Uklízí se **spolu**, jinak by po vypadlém PR zbyl osamocený důvod poruchy.
        commits = commits.filter { wantedPullRequests.contains($0.key) }
        commitFailures = commitFailures.filter { wantedPullRequests.contains($0.key) }

        // Razítka dotazů na hlavu (#420) jsou jen datum, ale drží klíč s celým identifikátorem PR —
        // bez úklidu by mapa rostla po celé sezení, stejně jako u volby tabu. PR mimo seznam se
        // navíc neptáme, takže razítko po něm nemá co říct; kdyby se vrátil, zeptáme se znovu a
        // druhý řádek z toho nevznikne (identita nese hlavu).
        headProbes = headProbes.filter { wantedPullRequests.contains($0.key) }

        // Labely a reviewery (#392) — platí k jednomu PR a mapa drží celý identifikátor, takže by
        // bez úklidu rostla donekonečna. Rozdělané načítání přežije ze stejného důvodu jako
        // u detailu: doběhlé volání by si ho zapsalo zpátky. **Stav akce jde s tím**, jinak by po
        // vrácení PR do seznamu svítila chyba odesílání, o které nikdo neví, odkud je.
        metadataStates = metadataStates.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        metadataActionStates = metadataActionStates.filter { wantedPullRequests.contains($0.key) }
        // Slévatelnost větve (#465) — tatáž hranice i tentýž důvod jako u labelů: mapa drží celý
        // identifikátor PR, takže by bez úklidu rostla donekonečna, a rozdělané načtení přežije,
        // protože doběhlé volání by si ho zapsalo zpátky.
        branchStatuses = branchStatuses.filter {
            wantedPullRequests.contains($0.key) || $0.value == .loading
        }
        // Nabídky se klíčují **repem**, takže se uklízejí podle rep v seznamu — tatáž hranice jako
        // u `checkoutStates`.
        // Nabídky a jejich poruchy se uklízejí **spolu**: kdyby zůstal jen důvod, hlásila by
        // nabídka poruchu u repa, které v seznamu není.
        repositoryLabels = repositoryLabels.filter { wanted.contains($0.key) }
        repositoryLabelFailures = repositoryLabelFailures.filter { wanted.contains($0.key) }
        assignableUsers = assignableUsers.filter { wanted.contains($0.key) }
        assignableTeams = assignableTeams.filter { wanted.contains($0.key) }
        assignableUserFailures = assignableUserFailures.filter { wanted.contains($0.key) }

        // Rozkliknutý commit a jeho diff (#317). Diff jsou megabajty, takže jde stejnou cestou
        // jako diff PR — a rozdělané stahování přežije ze stejného důvodu: doběhlé volání by si
        // ho zapsalo zpátky. Otevřený commit se uklízí **spolu s ním**, jinak by po vrácení PR do
        // seznamu tab rovnou skočil do commitu, o který si nikdo neřekl.
        openCommits = openCommits.filter { wantedPullRequests.contains($0.key) }
        commitDiffs = commitDiffs.filter {
            wantedPullRequests.contains($0.key) || $0.value.content == .loading
        }

        // Rozbalený check a jeho detail (#214). Stahování se **ruší**, ne opouští: osmimegový log
        // by dojel do stavu, který už nikdo nečte. Text se u toho zahazuje schválně — nemá přežít
        // ani sbalení checku, natož vypadnutí PR ze seznamu.
        for (key, task) in checkTasks where !wantedPullRequests.contains(key.pullRequest) {
            task.cancel()
            checkTasks[key] = nil
        }
        expandedChecks = expandedChecks.filter { wantedPullRequests.contains($0.key) }
        checkDetails = checkDetails.filter { wantedPullRequests.contains($0.key.pullRequest) }

        // Zavřený nebo mergnutý PR nemá co blokovat slot. Ruší se **jen automatická**
        // review: to ruční si vyžádal člověk a zrušit mu ho pod rukama proto, že PR mezitím
        // někdo mergnul, je horší než session navíc.
        for pr in automaticReviews where !wantedPullRequests.contains(pr) {
            reviewTasks[pr]?.task.cancel()
        }
        consideredForAutomation = consideredForAutomation.filter { wantedPullRequests.contains($0.key) }
    }
}
