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
    var reviewPanelTab: ReviewPanelTab = .findings

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

    let checkout: (any RepoCheckout)?

    let reviewer: (any ReviewRunning)?

    let reviews: ReviewStore?

    let draftStore: ReviewDraftStore?

    let translator: (any FindingTranslating)?

    private let configStore: ConfigStore?

    /// Doručování notifikací (#88). `nil` = odsud se neposílají (testy), takže se nic
    /// nedoručí a proud kliknutí se ani nezačne konzumovat.
    ///
    /// Nepovinné schválně, jako `health` nebo `reviews`: `keepFresh()` volají i testy a živé
    /// centrum by z nich udělalo testy sahající na systémové notifikace.
    let notifications: (any UserNotifying)?

    /// Které PR už se ohlásily jako nové (#85). `nil` = odsud se nehlásí (testy).
    let announced: AnnouncedPullRequests?

    /// Rozdělané běhy (#97). `nil` = odsud se nedotahuje (testy).
    let interrupted: InterruptedRuns?

    /// Čtení transcriptů zabitých session (#97). `nil` = odsud se nečte (testy).
    private let transcripts: (any TranscriptReading)?

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

    /// PR, jehož detail je zrovna na obrazovce (#173). Drží se kvůli tomu, aby se poznalo
    /// **odejití** — přepnutí jinam a návrat je nová návštěva, takže se banner podruhé
    /// neukazuje. Uvnitř jednoho PR se tím nemění nic, takže odskok mezi taby o něj nepřipraví.
    var openedPullRequest: PRIdentifier?

    init(
        gateway: any GitHubGateway,
        configuration: Configuration = .standard,
        configStore: ConfigStore? = nil,
        time: any TimeSource = SystemTimeSource(),
        eviction: CacheEviction? = nil,
        checkout: (any RepoCheckout)? = nil,
        reviewer: (any ReviewRunning)? = nil,
        reviews: ReviewStore? = nil,
        drafts: ReviewDraftStore? = nil,
        translator: (any FindingTranslating)? = nil,
        autoRuns: AutoRunLedger? = nil,
        spend: SpendLedger? = nil,
        gh: URL? = nil,
        health: HealthMonitor? = nil,
        notifications: (any UserNotifying)? = nil,
        announced: AnnouncedPullRequests? = nil,
        interrupted: InterruptedRuns? = nil,
        transcripts: (any TranscriptReading)? = nil,
        visits: VisitLedger = VisitLedger(preferences: UserDefaults.standard)
    ) {
        self.visits = visits
        self.time = time
        self.gh = gh
        self.health = health
        self.notifications = notifications
        self.announced = announced
        self.interrupted = interrupted
        self.transcripts = transcripts
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
        self.reviewer = reviewer
        self.reviews = reviews
        draftStore = drafts
        self.translator = translator
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
            reviewer: ClaudeReviewRunner(
                claude: toolPaths.claude,
                gh: toolPaths.gh,
                runner: SubprocessStreamer(),
                maxConcurrent: { box.value.global.maxConcurrentReviews },
                model: { box.value.global.model }
            ),
            reviews: ReviewStore(),
            drafts: ReviewDraftStore(),
            translator: ClaudeFindingTranslator(claude: toolPaths.claude, runner: runner),
            autoRuns: AutoRunLedger(),
            spend: SpendLedger(),
            gh: toolPaths.gh,
            health: HealthMonitor(),
            notifications: SystemNotificationCenter.shared,
            announced: AnnouncedPullRequests(),
            interrupted: InterruptedRuns(),
            transcripts: TranscriptStore()
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
        polling.sources = configuration.activeSources
        polling.interval = .seconds(configuration.global.pollIntervalSeconds)
        // Limit souběhu se čte při každém pokusu o slot, ale kdo už čeká ve frontě, spí.
        await reviewer?.configurationChanged()
    }

    /// **Plný** seznam z pollingu, nefiltrovaný — a musí to tak zůstat.
    ///
    /// Čte ho pět míst, kterých se filtr **nesmí týkat**: `knownRepositories` (okno nastavení),
    /// `queueSummary` (souhrn je o obsahu fronty, ne o pohledu — #155), `handleNotificationClicks`,
    /// `startAutomaticReviews` po zahození nálezů (#81) a úklid, který bere `summaries` z tiku.
    ///
    /// Kdyby na zúženém seznamu viselo cokoli z úklidu (`forget(whatIsNotIn:)`, `CacheEviction`,
    /// `ReviewStore.cleanUp`, rušení automatických review), **zapnutí filtru by zahodilo diffy
    /// a konverzace, smazalo cache a zrušilo běžící review**. Rozdíl mezi tímhle getterem
    /// a `visiblePullRequests` je jediné, co dělí filtr od mazání cache — a je na to test.
    var pullRequests: [PullRequestSummary] { polling.state.pullRequests }

    /// Seznam **po filtru** (#117). Čte ho jedině seznam PR a detail vybraného řádku.
    var visiblePullRequests: [PullRequestSummary] {
        Policy.filtered(pullRequests, by: filter)
    }

    /// Kolik PR filtr schoval. Musí být vidět v liště: skrytý filtr je způsob, jak přijít o review.
    ///
    /// Počítá se **bez druhého filtrování** — jen se spočítá, co filtrem neprojde. `visiblePullRequests`
    /// tady bylo dřív a znamenalo to, že se seznam filtruje dvakrát; SwiftUI ho přitom čte při každém
    /// překreslení lišty (nález Copilota na #170).
    var hiddenPullRequestCount: Int {
        guard filter.isActive else { return 0 }
        return pullRequests.count { !filter.matches($0) }
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

    // MARK: - Záložky (#180)

    /// Otevře PR jako záložku a přepne se na ni. Otevřený PR se **neotevírá podruhé** — kliknutí
    /// na něj v seznamu ho jen vytáhne dopředu, jako v prohlížeči.
    func openTab(_ pullRequest: PRIdentifier) {
        if !openTabs.contains(pullRequest) { openTabs.append(pullRequest) }
        if let summary = summary(for: pullRequest) { openTabSnapshots[pullRequest] = summary }
        activeTab = .pullRequest(pullRequest)
        selection = pullRequest
    }

    /// Zavře záložku. **Nic se tím nezahazuje** — draft, nálezy i běžící review zůstávají, protože
    /// nic z toho na záložce nevisí.
    ///
    /// Po zavření se jde na **sousední** záložku, ne domů: zavírá se typicky doprojité review
    /// a další v řadě je to, co člověk chce vidět. Domů se propadne, až když nezbyde žádná.
    func closeTab(_ pullRequest: PRIdentifier) {
        guard let index = openTabs.firstIndex(of: pullRequest) else { return }
        openTabs.remove(at: index)
        openTabSnapshots[pullRequest] = nil

        guard activeTab == .pullRequest(pullRequest) else { return }
        let neighbour = openTabs.indices.contains(index) ? openTabs[index] : openTabs.last
        activeTab = neighbour.map(WindowTab.pullRequest) ?? .home
        selection = neighbour
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
    var railQueueCount: Int? {
        lastSuccess == nil ? nil : visiblePullRequests.count
    }

    /// Podklad pro dashboard (#181). Počítá se **z paměti store**, žádné nové čtení z disku.
    var dashboard: Dashboard {
        Policy.dashboard(
            pullRequests: pullRequests,
            records: reviewRecords,
            drafts: drafts,
            categories: Set(configuration.global.blockingCategories),
            since: Calendar.current.date(byAdding: .day, value: -7, to: time.now)
        )
    }

    /// Fronta na dashboardu (#181) — **plný** seznam seřazený podle závažnosti.
    ///
    /// Ne zúžený filtrem, ze stejného důvodu jako `dashboard` výš: dashboard je tvrzení o tom,
    /// co ve frontě je, ne o tom, co je zrovna vidět.
    var dashboardQueue: [QueueEntry] {
        Policy.byUrgency(
            pullRequests.map {
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
    var checks: [PRIdentifier: [PullRequestCheck]] = [:]

    /// Kdy se polling zeptá znovu. `nil`, dokud smyčka poprvé neusne.
    var nextPoll: Date? { polling.state.nextPoll }

    /// Ptá se polling právě teď? Čte to odpočet v hlavičce dashboardu (#237) — po dobu dotazu
    /// je `nextPoll` v minulosti, takže se místo něj píše, co se děje.
    var isRefreshing: Bool { polling.state.isRefreshing }

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

    var status: PollStatus { polling.state.status }

    var lastSuccess: Date? { polling.state.lastSuccess }

    var isStale: Bool { polling.state.isStale }

    var emptyReason: PollEmptyReason? { polling.state.emptyReason }

    /// Proč je **viditelný** seznam prázdný — včetně toho, že ho schoval filtr (#117).
    ///
    /// Skládá to store, ne polling: ten o stavu okna neví a vědět nemá. Pořadí důvodů rozhoduje
    /// `Policy.listEmptyReason` a nad selhaným tikem vyhrává chyba načtení, ne filtr.
    var listEmptyReason: ListEmptyReason? {
        // Jedním průchodem: `visiblePullRequests` i `hiddenPullRequestCount` by seznam filtrovaly
        // každý zvlášť, a tenhle getter čte SwiftUI při každém překreslení seznamu.
        let hidden = hiddenPullRequestCount
        return Policy.listEmptyReason(
            poll: emptyReason,
            visible: pullRequests.count - hidden,
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
        switch polling.state.status {
        case .notStarted:
            nil
        case .upToDate:
            polling.state.lastSuccess.map { ServiceCall(since: $0) }
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
        await loadDailySpend()
        // Všechno běží, dokud žije okno; zrušení tasku ukončí skupinu i se všemi smyčkami.
        await withTaskGroup(of: Void.self) { group in
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
    func refresh() async {
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
    var queueSummary: QueueSummary? {
        guard polling.state.lastSuccess != nil else { return nil }
        let summary = Policy.summary(
            of: pullRequests,
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
    var runningReviews: Int { reviewTasks.count + recheckTasks.count }

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
        /// Konec běhu i s tím, co stál (#148) — `usage` je `nil` u běhu, který cenu nenahlásil.
        case finished(skill: String, ReviewRunOutcome, usage: RunUsage?)
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
        expansions = expansions.filter {
            wantedPullRequests.contains($0.key.pullRequest) || $0.value.isLoading
        }
        // Sbalení je jen příznak, ale drží klíč s celým identifikátorem PR — bez úklidu by
        // množina rostla donekonečna.
        foldedFiles = foldedFiles.filter { wantedPullRequests.contains($0.pullRequest) }
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

        // Zavřený nebo mergnutý PR nemá co blokovat slot. Ruší se **jen automatická**
        // review: to ruční si vyžádal člověk a zrušit mu ho pod rukama proto, že PR mezitím
        // někdo mergnul, je horší než session navíc.
        for pr in automaticReviews where !wantedPullRequests.contains(pr) {
            reviewTasks[pr]?.task.cancel()
        }
        consideredForAutomation = consideredForAutomation.filter { wantedPullRequests.contains($0.key) }
    }
}
