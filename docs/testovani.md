# Testování — co se čím pokrývá

Referenční část [`CLAUDE.md`](../CLAUDE.md): katalog toho, co se u které oblasti testuje a proč
zrovna to. Zásady (protokol + fake místo mockovacího frameworku, fixtures ze skutečných běhů,
jak se testy pouštějí) zůstávají v `CLAUDE.md`.

Seznam není výčet souborů, ale **výčet toho, co se nesmí rozbít potichu** — u každé oblasti
stojí i důvod, proč je zrovna tenhle případ v testu.

**Čistá funkce nesmí bydlet na `View` typu, když nad něčím iteruje** (#219). Konformance k `View`
udělá z celého typu `@MainActor` — a protože je to `@preconcurrency`, **překlad projde** a spadne
se až za běhu: uvnitř closure předané do `filter`/`contains` se ověří aktuální executor a testovací
proces umře na `dispatch_assert_queue`. Navenek to vypadá jako náhodné testy — Swift Testing pouští
suity paralelně, takže se jako `Failing tests` nahlásí to, co zrovna běželo, a **při každém běhu
něco jiného**. Metoda bez closures (dělení cesty na složku a jméno) projde, takže to nezavání
systematicky. Léčba je pravidlo z `CLAUDE.md`: rozhodování nad nálezy patří do `Policy`, na view
zůstane jen skládání věty z hotových čísel. Příčinu řekne **až crash report**
(`~/Library/Logs/DiagnosticReports/PRism-*.ips`, `closure #1 in …`); v logu z `xcodebuild` je jen
`Restarting after unexpected exit`.

**Druhá léčba je `nonisolated`** (#218), a u skládání textu je levnější než stěhování do `Policy`:
`nonisolated static func` na `View` typu z izolace vystoupí, takže se uvnitř closure žádný executor
neověřuje. Sáhne se po ní tehdy, když funkce **nerozhoduje**, jen skládá větu z hotových hodnot
(`ReviewRunbarView.label` spojuje jména běžících reviewerů) — rozhodování patří dál do `Policy`,
protože tam se testuje bez kreslení. Naražené znovu u #218 a příznak byl přesně ten popsaný výš:
`Failing tests` plné suit, které s tou změnou nesouvisejí, a crash report ukazující na `map`.

**`#expect` nad `Double` a `CGFloat` naráz vyjde nepravdivě** (#252) — i pro dvě dvojky. Ve výpisu
je pak `Expectation failed: (span.top → 2.0) == (rows[0].rect.minY → 2.0)`, tedy tvrzení, které
o sobě říká, že neplatí. Mimo makro tatáž podmínka projde (vyzkoušeno), takže je to jeho
přepisování výrazu, ne aritmetika. Léčba je srovnávat **jeden typ** (`Double(rect.minY)`).


- **Modely** — round-trip přes `Codable` u každého typu i každého případu `ReviewState`,
  parsování a formátování identifikátorů včetně neplatných vstupů, a kontrola skutečného
  tvaru JSONu (identifikátor musí být řetězec, slovník klíčovaný jím musí být objekt).
  Pomocníci na round-trip jsou v `Tests/Models/CodableRoundTrip.swift`; balí hodnotu do
  pole, protože holý řetězec by na nejvyšší úrovni byl JSON fragment.
- **`Policy`** — vyčerpávající unit testy, nic se nemockuje. U slučování zdrojů včetně
  toho, co se snadno přehlédne: kolize s různým `updatedAt` v obou pořadích zdrojů,
  prázdný zdroj, žádný zdroj a **shodné časy** (na kterých se pozná nedeterministické
  řazení). U nálezů hranice blokující sady, každý způsob, jak návrh verdiktu **nevznikne**,
  shoda 1×/2×/3× a řazení ověřené i z obráceného vstupu. Data staví `Tests/Policy/
  FindingFactory.swift` — není to fake, jen zkratka; uložený běh se skládá přes `ReviewRun`,
  tedy tou cestou, kterou vzniká doopravdy.
- **`Environment`** — `BinaryLocator`, `GhAuthCheck`, `LoginShellPathReader` a `Preflight`
  proti fakes (`Tests/Environment/EnvironmentFakes.swift`). `FakeShellPathReader` počítá
  volání: že se login shell spustí nejvýš jednou a jen když je co dohledávat, je součást
  kontraktu, ne detail. Plus malý počet testů proti skutečnému systému
  (`RealEnvironmentTests`) na to, co fake ověřit neumí — složka se spustitelným bitem,
  symlink, skutečný timeout, skutečný `zsh -lc`.
- **`GitHub`** — `GhGateway` proti `FakeProcessRunner` (z `Tests/Environment/`) a fixtures;
  klasifikace chyb tabulkou nad `ProcessResult`, mapování stavu vyčerpávajícím výčtem.
  Testuje se i **tvar argumentů** předaných `gh` — rozdělení dotazu na tokeny a seznam
  `--json` polí je kontrakt s `gh`, ne detail.
- **Rozřazení PR podle autora (#330)** — tři vrstvy a v každé je nejcennější to, co tvrdí, že se
  něco **NEstalo**:

  `Policy` výčtem (`PullRequestOwnershipTests`): prázdný i nenačtený (`nil`) viewer znamená, že je
  **všechno cizí** — tohle je ta věta, na které issue stojí, a rozbije se potichu, protože obrácené
  výchozí chování nic neshodí, jen na okamžik po spuštění zmizí fronta cizích PR a vypadá to jako
  „ještě se to nenačetlo“. Dál: bílé znaky loginem nejsou, velikost písmen nerozhoduje, loginy
  z konfigurace se k viewerovi **přidávají** (na tom stojí PR agenta s vlastním účtem), a dva PR
  z **téhož** seznamu vyjdou různě — z toho je vidět, že rozhoduje autor, ne zdroj.

  `AppStore` proti fake gateway (`AppStoreOwnershipTests`): dokud `keepFresh()` neproběhl, je
  `viewer` prázdný a nic není moje; **selhání dotazu z cizích PR moje nedělá**; login se tahá
  **jednou za spuštění** (tři tiky, jeden dotaz — je to údaj o účtu, ne o PR). Fake má `viewer`
  ve výchozím stavu `nil`, tedy „gateway ho nezná“, takže ostatní sady zůstávají v tom stavu, ve
  kterém aplikace startuje.

  `GhGateway` proti `FakeProcessRunner`: argumenty (`api user`), skutečná odpověď GitHubu ve
  fixture `gh/user.json` (z **veřejného** `gh api users/octocat` — `/user` má tentýž tvar plus
  privátní pole, která se nečtou, a osobní údaje do repa nepatří), a dvě podoby toho, že se prázdný
  login **nevrátí**: odpověď bez `login` a odpověď s prázdným řetězcem obojí skončí chybou. Přesně
  to je důvod, proč se nepoužívá `--jq .login` — ten by na chybějící pole vypsal prázdný řádek
  s nulovým kódem, tedy „nevím, kdo jsem“ vydávané za odpověď.

  **Ověřeno vložením regrese, dvakrát.** `mine.isEmpty → .mine` (tedy „nevím“ = „to jsem já“)
  shodí **11 testů / 18 tvrzení** — mezi nimi i tři z #114 (`prefillableSuggestion`), což je
  zároveň doklad, že porovnání je doopravdy na jednom místě. Vypnutí normalizace na malá písmena
  plus vyhození `.mine` z výchozích zdrojů shodí dalších 6 testů, každý na svou příčinu.

  **Sada, která na tom nečekaně stála:** `AppStoreAutomaticTests` si musela zdroj pinovat na jeden
  (`[.reviewRequested]`), protože `FakeGitHubGateway` spotřebovává předepsané odpovědi **po
  dotazech, ne po tikech** — s druhým výchozím zdrojem by tik, který má vidět `updatedAt: 100`,
  dostal rovnou `200`. Ostatní sady store si zdroje pinují už dneska; tahle jediná brala
  `Configuration.standard`.
- **Sekce `Moje PR` (#331)** — tři vrstvy nad rozřazením z #330, a to nejcennější je zase to, co
  tvrdí, že se něco **NEstalo**:

  `Policy` výčtem (`OwnPullRequestsTests`): **pořadí důvodů prázdna** je celý obsah issue, takže se
  testuje po dvojicích, ne jen jednotlivě — chybějící zdroj vyhrává nad nenačteným loginem i nad
  filtrem, login nad filtrem, a polling nad všemi. K tomu dvě věty, které se rozbijí potichu:
  `poll(.noPullRequests)` odsud **nesmí vypadnout** (jinak by nad vlastní sekcí stálo „Žádné PR
  k review“, což o vlastních PR nemluví) a prázdná sekce **s vlastními PR v seznamu** žádný důvod
  nedá (kdo si dopsal jiný dotaz, má sekci plnou). Odznak se testuje na tom, co se **nepočítá**:
  odmítnutý nález, vyřešené vlákno, vlákno jen s mými komentáři a **PR, jehož konverzace není
  načtená** — poslední z nich je vědomá spodní hranice, ne chyba.

  `AppStore` proti fake gateway (`AppStoreOwnershipTests`): rozřazení **nezmenší plný ani zúžený
  seznam** (na plném visí úklid a nastavení), filtr se s rozřazením **skládá**
  a schované vlastní PR se počítají zvlášť od schovaných cizích, odznak je `nil` do prvního tiku,
  a blok na dashboardu se filtrem **neschová** (dashboard tvrdí o tom, co venku mám).

  `PullRequestRow` (`PullRequestRowPromptTests`): `Prompt →` se u cizího PR **nekreslí** a výchozí
  hodnota je `theirs`, takže řádek bez informace o autorovi tlačítko nemá. Že se doopravdy nakreslí,
  se pozná na **výšce řádku** rozvržené mimo obrazovku (`fittingSize`) — samotné `if` může projít,
  aniž by se prvek do řádku vešel.

  **Od #333 je tam třetí tvrzení: bez akce se tlačítko nekreslí.** Vlastní řádek bez `openPrompt` má
  výšku cizího, tedy měřenou, ne odhadnutou — kdyby se kreslilo dál, byl by z něj potichu zase ten
  zakázaný prvek z #331, jen vyrobený volajícím, který zapomněl uzávěr předat. Že tlačítko volá **tu**
  akci, se tvrdí na uzávěru: `Button` se v testu stisknout nedá (klik do okna mimo obrazovku se
  nedoručí), takže se ověřuje jediná věc mezi řádkem a storem.

  **Ověřeno vložením regrese, třemi.** Vyhození větve o chybějícím zdroji shodí 4 tvrzení ve třech
  testech, `activeFindings → findings` (tedy „odmítnutý nález pořád čeká na tah“) jeden a
  `showsPromptAction → true` tři včetně toho na výšku řádku.

  Vedle toho je `Tests/Views/OwnPullRequestsRenderProbe.swift` — **sonda, ne test**: dashboard se
  dvěma frontami a čtyři podoby sekce, protože „nevypadá prázdno jako hotová práce?“ je otázka na
  obrázek. Ke dvěma z těch stavů se v aplikaci klikáním nedostaneš (musel by spadnout `gh api user`,
  resp. chybět zdroj v konfiguraci) a dashboard se **screenshotem běžícího okna nevyfotí celý**:
  je to jeden `ScrollView`, takže s třiceti PR ve frontě spadne blok `Moje PR` pod dolní hranu.
- **Fronta jsou cizí PR (#332)** — celá oblast je o tvrzeních, že se něco **nestalo**, protože
  všechno tady se rozbije potichu: čísla by jen ukázala jinou hodnotu a úklid by tiše přestal
  uklízet.

  `Policy` výčtem (`OwnPullRequestsTests`, `AutomaticReviewTests`, `ReviewNotificationTests`,
  `PullRequestFilterTests`): karta `Čeká na mě` počítá **jen cizí** PR a **repozitáře taky z fronty**
  (jinak by u jediného cizího PR stálo „napříč 2 repozitáři“); karta `Blokuje` vlastní PR nepočítá
  **ani v detailu pod číslem**; karta `Rozdělaná review` se naopak **nezmenšuje**. Automat nevydá
  vlastní PR **ani při globálním `mode: automatic`, ani když si o automat řekne repo** — a k tomu
  dvě věty, bez kterých by ta tvrzení platila i nad vypnutým automatem: cizí PR v témže seznamu
  **projde dál** a bez známého loginu se **nevyřazuje nic**. Notifikace o doběhlém review se
  u `.mine` nepošle **v žádném ze sedmi koncových stavů**, a u `.theirs` se v každém z nich pošle.
  A `listEmptyReason` vydá `poll(.noPullRequests)` i tehdy, když je prázdná jen fronta.

  `AppStore` proti fake gateway a **skutečnému** `ReviewStore` (`AppStoreQueueScopeTests`,
  `AppStoreAutomaticTests`, `AppStoreReviewNotificationTests`, `AppStoreNewPullRequestTests`):
  odznak fronty **se nezvedne**, když do seznamu přibude vlastní PR (a plný seznam zůstane plný);
  souhrn ve stavovém řádku sčítá jen frontu a **nad samotnými vlastními PR se neukáže vůbec**;
  hromadné spuštění nabídne jen cizí; a to nejdražší: **úklid nálezů vlastní PR za zmizelý
  nepovažuje** — kontroluje se `closedAt` na záznamu po tiku, protože právě tím razítkem by se
  cache začala mazat. K tomu druhá strana: nastavení vidí i repo, ve kterém mám jen svoje PR,
  nabídka filtru zná vlastní autory a sekce `Rozdělaná` drží draft na vlastním PR.
  V automatu se ověřuje i to, že **ruční spuštění na vlastním PR jde dál** (jinak by z něj nešlo
  dostat nálezy pro zadání agentovi) a že se **nesáhne ani na rozpočet** (`automaticRunsToday`).

  **Ověřeno vložením regrese, jedenácti.** Ve dvou dávkách: vyhozený filtr v
  `automaticallyReviewable`, vrácený `listEmptyReason`, sundaná brána v `reviewNotification`,
  `railQueueCount` zpátky na celý pohled, souhrn a nová PR zpátky na celý seznam, úklid navázaný na
  frontu — a v druhé dávce `Policy.dashboard`, `dashboardQueue`, `hiddenQueuePullRequestCount`
  a `pullRequestsNotReviewed`. Každá z nich shodila právě ten test, který ji má chytat; **u notifikace
  o vlastním PR přitom potřebuje test tik pollingu**, protože čí je PR se bere ze seznamu — bez něj
  vyjde `.theirs` a test by byl zeleně z jiného důvodu, než tvrdí.

- **Zadání pro agenta na vlastním PR (#333)** — tři sady a v každé je to nejcennější negativní.

  `Policy` výčtem (`AgentPromptTests`): že se **vyřešená vlákna a odmítnuté nálezy do textu
  nedostanou, ale spočítají se** (bez počtu by se nedalo napsat „vynecháno“ a tiché zahození vypadá
  jako „tohle je všechno“); že komentář pod PR a souhrn review skončí v sekci **bez souboru**, ne
  přišpendlené k náhodnému; že zastaralé vlákno **řekne, že jeho číslo platí pro starší commit**;
  že hlava PR je v hlavičce textu, a když ji neznáme, je tam **věta o tom**; že nenačtená konverzace
  je přiznaná i v textu; že vypnutý hunk zmizí **u nálezu i u vlákna**; a že odmítnutý nález
  neblokuje. K tomu pořadí sekcí a souborů (blokující první, pak abecedně, uvnitř podle řádku
  s položkou bez řádku nahoře) a název souboru bez lomítka.

  `AppStore` proti fake gateway a **skutečnému** `ReviewDraftStore` (`AppStoreAgentPromptTests`):
  že se na vlastním PR **draft nedá založit, ani když je hlava známá** — to je celé issue —, že se
  brána nezavře, dokud není znám login (bezpečná strana z #330), a že **draft z dřívějška zůstane
  čitelný a smazatelný**. Draft se v tom testu zakládá jako cizí PR, tedy tou cestou, kterou
  doopravdy vznikl, a až potom se z PR stane vlastní: přesně stav, do kterého se dostane, kdo si
  dopsal `author:@me`. Předfiltr pro zkratku `⌘⇧P` se ověřuje proti hotovému zadání, aby zkratka
  nebyla zakázaná nad neprázdným panelem.

  **Akce `Prompt →` z řádku má dvě tvrzení** (`openAgentPrompt(in:)`): že otevře **záložku i panel**
  — včetně přepnutí z tabu `Commity`, ve kterém panel není, protože rozložit něco, co není vidět, je
  k nerozeznání od němé akce —, a že **nezakazuje sama sebe nad prázdným zadáním**. To druhé je to
  cennější: je to navigace, takže `hasAgentPromptItems` v seznamu měří stav před otevřením PR a jako
  brána by schoval cestu k panelu zrovna u PR, jehož materiál leží v diskuzi.

  **Tvrdá podmínka č. 1 má od #333 test, ne jen grep** (`SingleWayOutTests`). Čte zdrojáky v `App/`
  (komentáře zahazuje stejně jako grep v `CLAUDE.md`) a tvrdí čtyři věci: `ReviewPublishing` zná
  **právě pět souborů**, protokol má **čtyři metody**, **žádný** ze souborů zadání (jejich počet je
  v tvrzení, ať novým souborem téhle vrstvy neprojde výjimka) nezná publisher, payload, API ani
  `Process(`, a mimo úložiště zapisuje soubor **jen** `TextFileExport` přes `NSSavePanel`. Je to test
  o struktuře kódu, protože „odkud se dá odeslat“ se za běhu zjistit nedá. **Počty jsou jen v testu**
  — opsané v dokumentaci by se rozešly hned prvním přidaným souborem (chytil to Copilot na #333).

  **Ověřeno vložením regrese, dvakrát:** vyhození `.mine` z `canComposeDraft` shodí tři testy store
  (mezi nimi ten o velikosti písmen, takže je vidět, že brána chodí přes `Policy.ownership`)
  a jediné `(any ReviewPublishing)?` v `AppStore+AgentPrompt.swift` shodí obě poloviny
  `SingleWayOutTests` — výčet pěti souborů i zákaz publisheru v zadání.

  **Vzhled má sondu, ne tvrzení** (`AgentPromptRenderProbe`, `TEST_RUNNER_PRISM_MEASURE=1`): panel se
  rendruje v **obou mezích šířky** (240 a 520 bodů), protože sedm popisků s počty se do užší vejít
  musí — `lineLimit(1)` by rozdíl mezi `Vyřešená vlákna` a `Odmítnuté nálezy` schoval do „…“. Sheet
  se rendruje zvlášť a **s pozadím a tmavým režimem nasazeným sondou**: sám si plochu nemaluje
  (v okně ji dává sheet), takže bez toho vyjde titulek světle na světlém a vypadá to jako chybějící
  prvek — na to se u #333 spálilo jedno kolo. Sonda tiskne i celý text zadání, takže se dá přečíst
  vedle mockupu.

  **Sheet se od #333 rendruje taky v obou mezích** (840 a 1080 b), a je to k něčemu: na tom rozšíření
  o polovinu je vidět, co se **zalomením** mění. Na 720 b spadl odznak `vynecháno: 1 vyřešené vlákno`
  do druhé řady `FlowRow`u a úvodní odstavec zabral pět řádek; na 1080 se odznaky vejdou do jedné řady
  a odstavec do tří; na 840 taky do jedné řady, jen odstavec do čtyř. Jedno číslo by o druhém stavu
  netvrdilo nic — a **`minWidth` je to zajímavější z těch dvou**, protože do něj se sheet dá stáhnout.

- **Výběr položek do zadání (#377)** — jedna sada `Policy` (`AgentPromptSelectionTests`) a tři
  tvrzení, na kterých celé issue stojí. Všechna říkají, že se něco **nestalo**:

  **Odškrtnutá položka není v textu** (to je smysl issue) — **a přesto zůstává v seznamu**.
  Tiše zmizelá položka vypadá jako „tohle je všechno“, takže se ověřuje obojí: text ji nemá,
  `groups` ano, s `isIncluded == false` a **bez důvodu** (ruční odškrtnutí důvod nemá, znám ho).

  **Počet vybraných se rovná počtu položek v textu** — a počítá se z **nadpisů `###` v textu**, ne
  z čísla, které o sobě zadání tvrdí. Tvrdí se to přes tři stavy výběru (nic, jedna, obojí), protože
  na jednom by rozchod nemusel být vidět. K tomu součet přes grupy, aby se `2 z 3` v hlavičce grupy
  nerozešlo s hlavičkou sheetu.

  **Heuristika `shrnuje diff` nevypne souhrn, který diff nepřevypráví** — fixture je skutečné
  `CHANGES_REQUESTED` review z `cli/cli#13084` (próza s odrážkami). Ze druhé strany ji drží fixture
  `gh/review-copilot-overview.md` (skutečné review na `ondrajodas/PRism#378`, `CRLF` na 9 řádcích —
  test se ptá `contains("\r\n")`, aby normalizovaný soubor nezezelenal s rozbitým dělením řádků) a dvě
  hranice: **zmínka v próze nadpis není** a **starší přehled bez tabulky souborů heuristice sedí**
  (změřeno na `cli/cli#11451`, proto tabulka není druhá podmínka).

  Dál výčtem: že se **vlastní pozná podle `viewer`u, ne podle autora PR** (agentský PR má autora
  `ondrajodas`, změřeno u #330 — a tentýž materiál očima kolegy má „vlastní“ na druhém komentáři);
  že se **vlastní vlákno u řádku nepředvybírá** (na vlastním PR je to práce, #333); `bez obsahu`
  výčtem čtyř těl (prázdné, jen nadpis, jen nadpisy, HTML komentář a nadpis); že se heuristika
  **nepouští na vlákna**; a že rozbalení dá `.none` u položky bez textu, takže se u ní nekreslí šipka.

  **Po předání části položek odznak `Moje PR` nezhasne** (`HandoffTests`) — razítko nese identity,
  takže odškrtnuté vlákno zůstane nepředané. Vedle toho stojí tvrzení opačným směrem: **co aplikace
  předvybrala jako vypnuté, materiál k předání není**, jinak by odznak nad vlastním PR nezhasl nikdy
  (release notes v komentáři pod PR jsou tam na každém mém PR).

  **Ověřeno vložením regrese, čtyřikrát:** ignorování `toggled` v `agentPromptIncludes` shodí čtyři
  testy (mezi nimi `handed`, tedy razítko); vyhození vypnutých položek ze `agentPromptGroups` shodí
  „zůstává v seznamu“, `available` i důvody; heuristika, která vrací `true` na cokoli, shodí ten test
  s fixture, co jí nesedí; a vyhození filtru předvybraných z `Policy.handoff` shodí „materiál
  k předání“ (`pending` 1 → 3, `.delivered` → `.changed`).

  **Vzhled má sondu** (`AgentPromptRenderProbe`): seznam se rendruje **zvlášť od sheetu** a v obou
  mezích šířky (840 a 1080 b), protože co je rozbalené, drží `@State` sheetu — offscreen se v něm
  rozbalit nedá. Rozbaluje se **nejdelší** položka, tedy ta, u které se pozná strop rolování
  (168 b z návrhu). Konverzace sondy nese od #377 **každý důvod předvybrání** (souhrn, který shrnuje
  diff, souhrn bez obsahu, vlastní komentář, vyřešené vlákno), takže je na obrázku vidět celý sloupec
  důvodů naráz.

- **Předání zadání (#334)** — čtyři sady a všechny to nejcennější mají v negativním tvrzení.

  `Policy` výčtem (`HandoffTests`): že po předání odznak **zhasne, i když nálezy dál existují**;
  že ho rozsvítí **nová položka, ne opakovaný nález** (týž klíč = nic nového, nový klíč = práce);
  že se počítá **cizí odpověď v už předaném vlákně**, ale **ne moje vlastní**; že po pushi vyjde
  `.outdated` a `staleFindings` je nenulové (**zastaralý nález z počtu nezmizí**); že se počet
  commitů netvrdí ani po force pushi, ani bez načteného seznamu; a že **neznámá dnešní hlava se bere
  jako „neposunula se“**, protože jinak by odznak po předání nikdy nezhasl. Razítko si testy skládají
  **produkční funkcí** (`agentPromptItems` + `AgentPromptItem.id`), ne ručně psanými identitami —
  jinak by ověřovaly svoji kopii pravidla.

  `AppStore` proti **skutečnému** `HandoffLedger`u (`AppStoreHandoffTests`): že razítko nese hlavu
  i položky, že po předání je `pending == 0` a **nález nezmizel**, že razítko **přežije nový store**
  (druhá instance nad tímtéž souborem), že po pushi vyjde `.outdated` a **review se nespustí samo**
  (`reviewTasks` i `automaticReviews` prázdné — automat se vlastních PR netýká vůbec, #332), že se
  počet commitů bere ze seznamu, a že zúžené zadání **nese jen novou diskuzi**, ne nálezy proti staré
  hlavě. Konverzace se v tom testu dotahuje podruhé se **novějším `updatedAt`** — načtená se drží
  právě podle něj.

  `HandoffLedger` proti skutečné složce (`HandoffLedgerTests`): restart, přepsání předchozího
  razítka, že se zápisem **neztratí razítka ostatních PR**, lhůta, rozbitý i chybějící soubor jako
  **prázdno** (tedy „nepředáno“ — bezpečný směr) a že se identity ukládají **řazené**, ať se soubor
  nemění bez důvodu.

  Texty panelu bez kreslení (`HandoffTextTests`): že se `dnes 14:20` pozná od staršího data, že
  chybějící hlava **je v textu napsaná**, a že se skloňuje česky (`1 commit` / `2 commity` /
  `5 commitů`, `přibyla 1 položka` / `přibyly 2 položky`). A hlavně: že se **počet commitů
  nevymýšlí**, když ho není z čeho spočítat — nula se čte stejně jako `nil`.

  **Dvě opravy po Copilotovi (#373) mají vlastní tvrzení**: že `.outdated` **skončí**, jak se pustí
  review proti dnešní hlavě (jinak by v tom režimu panel zůstal navždycky a volby by v něm nešly
  zapnout), a že zúžené předání **nechá razítko u staré hlavy** a předané položky **přičte**, ne
  přepíše. U toho druhého musí mít test hodiny **za** komentáři, které předává — razítko se
  porovnává s časy komentářů, takže s výchozím `FakeTimeSource` (rok 1970) by předané vlákno vyšlo
  jako „přišlo po předání“; v aplikaci to platí samo, protože čas je skutečný.

  **Třetí opravu našel Copilot v sekci *Suppressed comments*** (druhé kolo na #373), takže je vidět,
  proč se tělo review čte celé: věta o posunuté hlavě tvrdila „nálezy už platí pro dnešní kód“ i na PR,
  které žádné nálezy nemá. Test na to je negativní — `Věta o novém commitu o nálezech nic netvrdí`.

  **Vzhled má sondu** (`AgentPromptRenderProbe` má od #334 druhý test): panel se rendruje v **pěti
  stavech** — nepředáno, předáno, předáno-ale-něco-zbývá, po pushi a po pushi s nepředaným vláknem.
  Ke třem z nich se v aplikaci klikáním nedostaneš (musel by mezitím někdo pushnout do PR, který mám
  na obrazovce), takže je to jediná cesta, jak si je prohlédnout vedle mockupu. **Hodiny sondy musí
  být za daty konverzace**: výchozí `FakeTimeSource` je v roce 1970, takže by z každého vlákna udělal
  „přišlo po předání“ a stav `předáno` by na obrázku nikdy nevyšel — je to vlastnost fixture, ne
  logiky. Sonda tiskne i celý `HandoffReport`, takže je z výstupu vidět, který stav se kreslil.

  **Ověřeno vložením regrese, dvakrát:** vypnutí porovnání hlav (tedy „po pushi se nic neděje“)
  shodilo **čtyři** testy `Policy` a **tři** ve store — mezi nimi i ten o počtu commitů a o tom, že
  se review nespustí samo —, a smazání kontroly cizí odpovědi ve vlákně shodilo právě ten jeden
  test, který ji má chytat (a nic víc, což je taky informace: kontrola nepřebíjí ostatní pravidla).
- **Cizí aktivita na vlastních PR (#335)** — pět sad a **skoro celá oblast jsou negativní
  tvrzení**, protože se to rozbije potichu: notifikace, která přijde dvakrát, i dotaz, který se
  posílá zbytečně, vypadají na první pohled jako fungující aplikace.

  `Policy` výčtem (`ForeignActivityTests`): že **bez značky se nepočítá nic** (PR viděný poprvé —
  jinak by při prvním spuštění přišla lavina o měsíc starých komentářích), že se **můj vlastní
  komentář ani moje vlastní review nepočítá**, že rozdělané review (`submittedAt == nil`) není
  aktivita, že se komentáře pod PR i ve vláknech sčítají, a že **commity v tom nejsou** — u toho
  posledního test vedle sebe tvrdí obojí: `foreignActivity` commit nevidí, `changes` (pruh „od
  minule“) ano. Značka je **pozdější** z návštěvy a oznámení, vyčerpávající tabulkou pěti kombinací.

  **Cena** (`ActivitySweepTests`): že se **cizí PR neptá vůbec**, že se **beze změny `updatedAt`
  neptá nikdo**, že se druhá rozhlídka do intervalu nevejde, že strop uřízne to **nejstarší** (ne
  náhodné) a že **prázdná množina loginů znamená ticho**. Plus jedno tvrzení, které je záznamem
  rozhodnutí: interval 300 s a strop 3, tedy 0,6 dotazu na minutový tik proti `1 + N` každou minutu.

  **Text hlášky** (`ActivityNotificationTests`): skloňování obou druhů (`1 nový komentář` /
  `2 nové komentáře` / `5 nových komentářů`, `1 nové review` / `2 nová review`) a jejich složení do
  jedné věty; že do detailu jde **ta novější položka**, ne komentář vždycky; že se `CRLF` z komentáře
  slije na jeden řádek (#292) a dlouhý text zkrátí tak, aby v banneru **zbylo PR**; a že událost má
  **vlastní `replacementGroup`**, takže nepřebije výsledek review na tomtéž PR.

  `AppStore` proti skutečnému `ActivityNoticeLedger`u (`AppStoreActivityTests`): **že o témže
  komentáři nedorazí hláška dvakrát**, ani když se rozhlídka na PR podívá znovu (protože se
  `updatedAt` mezitím pohnul něčím jiným) — to je to nejcennější tvrzení celého issue; že **novější**
  komentář se ohlásí znovu; že se o vlastním komentáři nehlásí; že se u cizího PR konverzace netahá
  vůbec; že dva tiky v intervalu dají **jednu** rozhlídku; že **rate limit rozhlídku nepustí**
  (běží uvnitř úspěšného tiku); že se po selhaném doručení zkusí znovu; že vypnutý přepínač hlášku
  nepustí, ale **konverzaci načte** (text v řádku na ní stojí); a že **rozhlídka nezapíše návštěvu** —
  značka v paměti vzniknout musí, zápis do ledgeru ne.

  `ActivityNoticeLedger` proti předvolbám v paměti: restart, oddělenost PR, lhůta, rozbitá hodnota
  jako prázdno a že se razítko **neposouvá dozadu**.

  Řádek seznamu (`PullRequestRowActivityTests`): že text nese počet a druh, že u cizího PR **nikdy**
  není (ani když aktivitu omylem dostane) a že řádek s novinkami **nevyroste** — text nahrazuje
  autora a čas, takže by zalomení udělalo z dvouřádkové buňky trojřádkovou.

  **Vzhled má sondu** (`OwnPullRequestsRenderProbe` má od #335 dva scénáře navíc — `cizi-aktivita`
  v seznamu a `cizi-aktivita-dashboard` v bloku). Ke tomu stavu se v aplikaci **klikáním nedostaneš**:
  musel by mezitím někdo napsat komentář na PR, který mám v seznamu, a značka „od minule“ musí být
  starší než ten komentář. Konverzace i značka se proto do storu píšou **až po tiku** — rozhlídka si
  o konverzaci řekne sama, ale fake gateway ji nezná, takže by zbyl stav `failed`.

  **Obrácený test #331** (`AppStoreOwnershipTests`): odznak v railu teď vlákno počítá **bez kliknutí
  do PR**, protože konverzaci dotáhne rozhlídka v prvním tiku. Do #335 tvrdil opak a je u něj
  napsané, proč se změnil — spodní hranice z #331 se posunula, nezmizela.

  **Ověřeno vložením regrese:** vypnutí druhého razítka (značka jen z návštěvy) shodí právě ten
  jeden test, který ho má chytat — `O témže komentáři se nehlásí dvakrát`, s hláškou
  `(center.delivered.count → 2) == 1`.
- **Dění (#414)** — tři sady a **to nejcennější jsou tři negativní tvrzení**: že vypnuté notifikace
  zápis nezastaví, že se značka návštěvy neposune vstupem do sekce a že se vlastní PR do dění
  nedostane. Všechna tři se rozbijí potichu — na obrazovce po nich zůstane prázdno, nebo přečtený
  záznam.

  `Policy` výčtem (`ActivityFeedTests`, 42 testů). **Brána se testuje nad `allCases`**, ne nad
  vybranými druhy: devátý druh by jinak propadl bez povšimnutí. Dvě tabulky — cizí PR (hlásí se
  všechno kromě cizí aktivity) a vlastní (jedině cizí aktivita) —, a k nim čtyři konstruktory, které
  nad vlastním PR vrací `nil`. Dál: že **každý druh někam vede** a jediný vede na GitHub, že se dva
  druhy neslijí barvou ani glyfem (počet unikátních glyfů = počet druhů), a že chip **bez banneru**
  dostanou **jen ty druhy, které banner umí** — u dopočítaných by tvrdil, že něco nedorazilo, přitom
  za ně banner nechodí nikdy.

  Text: že headline je **titulek banneru** (`3 nálezy · 1 blokuje`), že u čistého review detail
  **není** (opakoval by titulek) a u selhání **je**, že se stavy mimo konec běhu nezapisují vůbec,
  že u cizí aktivity je věta headline a počet detail (obráceně než v banneru) a že se u **jediné**
  položky počet vynechá. U zastaralých nálezů skloňování commitů **i slovesa** (`přišel 1 commit` /
  `přišly 3 commity` / `přišlo 5 commitů`) a to, že neznámý počet o commitech **nemluví** — tatáž
  třída chyby jako u blokujících nálezů (#131).

  Záznam: pořadí od nejnovějšího, strop **odřízne nejstarší** (ne nejnovější), výchozí strop je
  200 zapsaných literálem, duplicita podle identity se slije a **zůstane ta první** (čas se nepřepíše
  na „všiml jsem si znovu“), nulový strop nechá prázdno. Identita zastaralých nálezů je klíčovaná
  **hlavou, ne časem** — dvě všimnutí téhož rozchodu dají jeden řádek.

  Nepřečtené a bloky: **bez značky je nepřečtené všechno** (opačně než u konverzace — je u toho
  napsané proč), pruh `Tady jsem skončil` se kreslí před **první už viděnou** položkou a bez novinek
  se nekreslí vůbec, den se jmenuje `Dnes` / `Včera` / datem a počet v nadpisu je **za ten den**, ne
  za celý záznam. Odznak sekce mlčí nad nulou **i na aktivní sekci**.

  `AppStore` proti skutečnému `ActivityLog`u a `AnnouncedPullRequests` nad dočasnou složkou
  (`AppStoreFeedTests`, 18 testů): že **vypnuté notifikace zápis nezastaví** (banner nedorazí, řádek
  je a přiznává to), že doručený banner nechá řádek bez chipu, že záznam **přežije restart** (druhá
  instance nad tímtéž souborem), že odchod z fronty dostane řádek a **žádný banner**, že **první tik
  po startu dění neplní** (jinak lavina), že se vlastní PR nedostane dovnitř, a že se **bez
  konzumenta nespotřebuje snímek fronty** — tohle poslední je starší tvrzení z #85, jen se v něm
  `notifications != nil` změnilo na `watchesPullRequestActivity`.

  Značka návštěvy: **vstup ji neposune** (ani v paměti, ani v předvolbách), odchod ano a zapíše se,
  otevření záložky PR je taky odchod, klik na tutéž sekci s ní nehýbe a při startu se přečte ta
  z minulého spuštění. Klik na řádek jde **jediným vstupním bodem** (#409) a **jmenuje tab**; řádek
  o odchodu z fronty záložku **neotevře** (otevřel by ji nad PR, které v seznamu není).

  `ActivityLog` proti skutečné složce (`ActivityLogTests`, 7 testů): restart, strop, srovnání pořadí
  a stropu **při čtení** (soubor mohl vzniknout s jinou konstantou), prázdný zápis se souboru
  **nedotkne** (tik bez novinek se děje pořád) a zápis vrací **celý** záznam, aby se strop nepočítal
  podruhé v paměti. A hlavně **rozbitý soubor se pozná od prázdného**: obojí dá prázdný seznam, ale
  klidné „nic se nestalo“ by nad ztracenou historií lhalo — tvrdí se to na obou stranách (chybějící
  soubor **není** porucha, nečitelný je) a store ten příznak musí donést až do prázdného stavu
  (`AppStoreFeedTests`), protože jinak by zůstal ležet ve storu a nikdo by ho nečetl.

  **Blok na dashboardu (#443)** — `DashboardActivityTests` výčtem a tři tvrzení ve store
  (`AppStoreFeedTests`). To nejcennější je zase negativní: **dashboard značku poslední návštěvy
  neposune**. Čte se u toho i klik na řádek, protože ten jde přes store (`show(_ event:)`) a je to
  jediné místo v tom bloku, které se storu dotýká; kdyby značku posunul, vynulovalo by se nepřečtené
  pohledem na domácí záložku a odznak v railu by zmizel, aniž bych něco přečetl — proto se v tomtéž
  testu tvrdí i to, že odznak dál svítí.

  V `Policy`: strop pěti řádků, patka `+37` a to, že se **nekreslí ani při přesně pěti** (tam se
  pozná `>=` proti `>`), že se **rozházené pořadí srovná před řezem** (jinak by řez ukázal pět jiných
  položek a pět řádků vypadá platně, ať v nich stojí cokoli) a že duplicita nezabere řádek ani se
  nepočítá do patky. Nadpis počítá **nepřečtené z celého záznamu**, ne z nakreslených řádků (dvacet
  položek, jedenáct nových, pět řádků), nula se nepíše a počet se skloňuje. **Den u času** se ověřuje
  z obou stran: na dashboardu `včera v 7:58`, v sekci `v 7:58`, dnešek den nedostane ani na
  dashboardu, starší dostane datum a čerstvá událost zůstane relativní **na obou obrazovkách** —
  a hranice okna se porovnává přímo se `showsRelativeTime`, aby se ty dvě obrazovky nemohly rozejít
  v tom, odkdy se píše hodinami. **Čtyři prázdna, čtyři různé věty** (tvrdí se, že je jich tolik,
  kolik je případů `allCases`), ztracená historie o klidu nemluví a zakázané se pozná od vypnutého.

  Ve store: strop je **o kresbě, ne o množině** (sedm položek → pět řádků, patka `+2`, nadpis
  i odznak sedm) a blok kreslí **tytéž položky** jako sekce, jen useknuté.

  **Úzký tvar řádku** (`ActivityRowShapeTests`) se měří **dvěma různými měřidly, a to schválně** —
  jedno bez druhého by prošlo i nad rozbitou verzí:

  - **výškou** to, kvůli čemu úzký tvar vůbec je: v 456 bodech pravého sloupce se řádek vejde na
    jednu řádku (24 b, strop v testu 28) a **plný řádek ze sekce ne** — u všech pěti položek ze
    sekce 31 návrhu;
  - **přirozenou šířkou** (`fittingSize.width` bez vnějšího rámce) to, co v něm **není**: podrobnost,
    sha, chip `bez banneru`, autor ani cíl. Výška na tuhle otázku odpovědět neumí — úzký řádek se
    nezalamuje, takže vrácený chip by ji nezvedl ani o bod, jen by ukousl kus titulku. Každé z těch
    tvrzení má **druhou stranu v sekci**, kde se ta věc kreslit má, jinak by prošla verze, která ji
    nekreslí nikde; a nad tím vším stojí jedno tvrzení opačné (titulek a `repo#číslo` šířku **mění**),
    aby bylo vidět, že měřidlo není slepé.

  Dvě věci, na které se u toho naráží. `Spacer(minLength: 0)` na konci řádku přirozenou šířku
  nerozbíjí: `fittingSize` se ptá nespecifikovaným návrhem a spacer na něj odpoví nulou (kdyby ne,
  spadlo by právě to opačné tvrzení). A **`fittingSize` vrací celé body**, takže se dvojice pro
  „cíl se nekreslí“ vybírá podle délky popisku, ne podle druhu: `→ Nálezy` proti `GitHub ↗` vyšlo
  v sekci **371 : 371**, kdežto `→ Konverzace` je o pět znaků delší a rozdíl přežije zaokrouhlení.

  **Ověřeno vložením regrese, dvakrát:** s podrobností a cílem vrácenými do úzkého řádku spadla tři
  tvrzení z pěti (výška 32 až 80 bodů místo 24), a se zahozeným `lineLimit(1)` u titulku spadla
  výška u nejdelší položky (45 b) — tedy přesně ten stav, kdy se řádek místo ořezu zalomí.

  Čar v levém sloupci dashboardu zůstává **jedenáct** (`DashboardFooterSeparatorTests`) a je to
  tvrzení, ne opomenutí: blok `Dění` stojí v **pravém** sloupci, kdežto vzorek jde přes levý. Kdyby
  se do počtu promítl, znamenalo by to, že se kreslí jinam, než kam ho návrh dal.

  **Ověřeno vložením regrese, dvakrát:** posun značky při vstupu (`guard visible || wasActivityVisible`)
  shodil dva testy — `Vstup do sekce značku neposune` i `Klik na tutéž sekci značku nehýbe` —,
  a vrácení notifikační brány do `announceNewPullRequests` shodilo právě ten jeden, který ji má
  chytat, s hláškou `(store.activityEvents.map(\.kind) → []) == [.newPullRequest]`.

  **Do plné sekce se klikáním nedostaneš** — čerstvá cache dění nemá a událost přijde až tikem —,
  takže se pro screenshot zapíše `activity.json` do cache slotu a značka do jeho domény
  v `UserDefaults` (`defaults write com.ondrajodas.prism.<slot> activity.lastVisit <ISO>`). Sekce je
  ve `ScrollView`, takže offscreen render nestačí (viz *Jak si zkontrolovat, jak view vypadá*)
  a fotí se **skutečné okno podle ID**.
- **Zastaralé nálezy z tiku (#420)** — tři sady, a **cenná polovina jsou tvrzení o počtu volání**.
  Rozbije se to potichu: v okně vypadá stejně, jestli se aplikace zeptala jednou, nebo dvanáctkrát,
  jen se ten rozdíl platí každou minutu.

  `Policy` výčtem (`StaleHeadProbeTests`): koho se tik zeptá — PR s uloženými nálezy, kterému se
  pohnul `updatedAt`, a **nikoho jiného**. Negativní tvrzení jsou tři: **klidný tik se neptá**
  (nepohnuté `updatedAt`), **PR bez nálezů se neptá** (není co zastarat) a **vlastní PR se neptá
  nikdy** — u toho se rovnou tvrdí i `Policy.isReported(.staleFindings, on: .mine) == false`, aby
  bylo vidět, že je to brána #332, ne úspora. Dál že se po startu (prázdná razítka) zeptá na
  všechny naráz, že strop **uřízne konec** seznamu (ne začátek — vstup je od naposledy změněného)
  a že je zapsaný literálem. K tomu porovnání sha výčtem: rozchod s nálezy, čisté review (rozchod
  **je**, `hasFindings` není), shodná sha, chybějící záznam a **chybějící hlava** — „nevím“ se nesmí
  kreslit jako „zastaralo“.

  Dotaz a odpověď (`PullRequestHeadsQueryTests`): že tři PR z tří repozitářů jsou **jeden** argument
  `query=` se třemi aliasy a **žádný `pr3`**, že hodnoty jdou přes `-F` (devět kusů) a jméno repa
  **v dokumentu není** (jinak by se do něj vlepovalo z konfigurace), že si dotaz říká o datum hlavy
  i o `oid` k jeho ověření, a že alias je **pozice**, ne `owner/name#číslo` (pomlčky a tečky ve
  jménech repozitářů nejsou platné GraphQL jméno).

  Fixtures jsou **skutečné odpovědi z veřejných repozitářů** (`cli/cli`, `microsoft/terminal`,
  `vercel/next.js`), sebrané tím dotazem, který posílá aplikace. Ta druhá (`pr-heads-partial.json`)
  je **partial failure z živého API**: dotaz na tři PR, ze kterých dvě neexistují, vrátil data
  prvního, `errors` ke zbytku a `gh` skončil kódem 1 — přesně ten stav, kvůli kterému gateway
  nenulový kód nebere jako selhání volání. Vymyslet by se nedal, protože z něj je podstatné právě
  to, co `gh` udělá se stdoutem. Neshoda `oid` s `headRefOid` se naopak testuje **inline JSONem**
  a je u toho napsané proč: na živém API se nestává (změřeno na dvanácti PR).

  `GhGateway` proti fake runneru (`GhGatewayTests`): **jedno spuštění `gh` na tři PR**, prázdný
  seznam **nespustí nic**, částečná odpověď s nenulovým kódem se **nezahodí**, nenulový kód **bez
  dat** je chyba a rozbitá odpověď je `malformedOutput`, ne prázdná mapa.

  `AppStore` proti skutečnému `ActivityLog`u (`AppStoreStaleHeadTests`): že posunutá hlava dá řádek
  **už z tiku** (a s detailem `hlava je teď`, protože o commitech se z tiku nemluví), že řádek nese
  **datum commitu, ne okamžik zjištění** (fixture má hlavu dva dny starou, takže rozdíl je vidět) a
  že se bez data hlavy datuje zjištěním. A pět negativních: **jeden dotaz na celou frontu** (tři PR
  = jedno volání se třemi identifikátory, `detailRequests` prázdné), **klidný druhý a třetí tik se
  neptá**, **bez záznamu dění se neptá vůbec**, **selhaný dotaz razítko neposune** (příští tik
  zkusí znovu) a **chybějící odpověď razítko nedostane** (`headProbes` zůstane prázdné). Restart
  se hraje druhým storem nad tímtéž souborem: zeptá se znovu, ale řádek **nezdvojí ani
  nepředatuje** — identita nese hlavu.

  **Vnořené pole ve fake gateway je součást kontraktu.** `headRequests` je `[[PRIdentifier]]`, ne
  plochý seznam, protože právě to dovolí odlišit jedno volání na tři PR od tří volání — a plochý
  seznam by ten rozdíl neuměl vyjádřit.
- **Konverzace** — proti fixtures, které jsou surové odpovědi z veřejných PR `cli/cli`
  sebrané **tím dotazem, který posílá aplikace** (`ConversationQuery.document`). Kdyby se
  sbíraly jinak, testovaly by tvar, který v provozu nikdy nepřijde; ověřené je to i tak, že
  volání složené aplikací (`-f query=<víceřádkový text>`) dá bajt po bajtu tutéž odpověď.
  Pokrývá: vyřešené vlákno, 24 zastaralých vláken bez `line`, odpověď ukazující na svého
  předchůdce, schválení s prázdným tělem, useknutou stránku (1 ze 38) a to, že se
  `hasNextPage` s počty **nerozchází** — bez toho by `or` v `isTruncated` schoval, že jednomu
  ze signálů nerozumíme. Syntetickým JSONem se testuje, co se ze skutečného PR nesehná:
  chybějící `pullRequest`, `nodes: null`, komentář bez autora a neznámý stav review.
  U dotazu se hlídá **seznam polí** — kdyby z něj vypadlo `isResolved`, ukazovala by se
  vyřešená vlákna jako otevřená.

  **Práva viewera (#73)** mají vlastní fixture z `cli/cli` (`conversation-thread-rights.json`,
  `first: 2`), protože na cizím repu jsou obě `false` — tedy zrovna ten případ, kvůli kterému se
  ta pole tahají. Starší fixtures je nemají, a to je **taky test**: ověřují, že se chybějící
  právo bere jako povolení. Rozdíl mezi `canResolve` a `canUnresolve` se na skutečné odpovědi
  nesehná (na cizím repu obě `false`, na vlastním obě `true`), takže na něj je syntetický JSON.

  **Úryvek kódu k vláknu (#158)** má vlastní fixture z téhož PR (`conversation-diff-hunks.json`,
  `first: 3`) — vybraná velikostí stránky, ne ručním výřezem, aby zůstala tím, co pošle aplikace.
  První tři vlákna dávají zrovna to, co je potřeba: **krátký hunk** (2 řádky, u kterého se
  zkrácení hlásit **nesmí**, jinak by test prošel i s příznakem zadrátovaným na `true`) a **dva
  dlouhé zastaralé** (106 a 129 řádků). To hlavní tvrzení je o **datech GitHubu**, ne o našem
  kódu — že `diffHunk` končí na komentovaném řádku — takže se ověřuje proti fixture u každého
  vlákna a číslo se bere podle `side`, stejně jako u kotvení bublin. Vymyšlený hunk by to
  nedoložil. Ověřené vložením regrese: `prefix` místo `suffix`, `isTruncated` zadrátovaný na
  `false` a zahozená syntetická hlavička — každé z toho testy shodí.

  Zvlášť stojí **doklad, proč je syntetická hlavička potřeba**: samotný `@@` blok skončí celý
  v `unrecognizedLines` a `files` je prázdné. Bez toho testu by se hlavička časem odstranila jako
  zbytečná. Levá strana diffu ve vzorku není (všechna vlákna jsou `RIGHT`, jako u #63), takže
  komentář k **odebranému** řádku má ručně sestavený hunk — a je u něj napsané proč.

- **Události časové osy (#171)** — dvě fixtures a inline JSON na zbytek, protože jeden PR
  všechny druhy událostí nemá:

  - `conversation-timeline.json` je **`ondrajodas/PRism#167`**, tedy vlastní repo — jediné
    místo, kde se sehná **bot jako vyžádaný reviewer** (`copilot-pull-request-reviewer`, o který
    si říká `bin/copilot-review.sh`). Na cizím PR takový případ není.
  - `conversation-force-push.json` je `cli/cli#13084` s `page=3`. Malá stránka schválně, jako
    u #158: celá odpověď je kvůli hunkům 280 kB, kdežto **force push** je v prvních třech
    uzlech. Nese navíc `hasNextPage: true`, takže se na skutečných datech ověří i to, že se
    zkrácení hlásí.

  Nejdůležitější test celé oblasti je, že **nefiltrovaný `totalCount` nehlásí ztracené
  události**: ta fixture má `totalCount: 49` proti třem uzlům, takže bez vlastního konstruktoru
  `ConversationPage(items:hasNextPage:)` by z ní vyšlo „chybí 46“. Vedle toho se hlídá, že
  **starší odpověď bez `timelineItems`** (`conversation-small.json`) projde a zbytek konverzace
  se tím nerozbije.

  Inline JSONem to, co se ze skutečného PR nesehná: převedení na draft, otevření znovu, změna
  base, **bot jako aktér**, tým jako cíl, vyžádané review **bez cíle** (na `cli/cli#13084`
  reálné, ale mimo první tři uzly), commit **bez napojeného účtu** a — to hlavní — **uzel,
  kterému nerozumíme**, který se nesmí nakreslit jako prázdný řádek.

  U dotazu se hlídá **seznam typů i fragmentů** (typ bez fragmentu dorazí prázdný), to, že
  `PULL_REQUEST_REVIEW` ani `ISSUE_COMMENT` mezi typy **nejsou** (jinak by se komentáře
  vykreslily dvakrát), a že fragment aktéra nese `__typename` — bez něj by se bot nepoznal.

  `TimelineEventRow` má vlastní sadu na **texty**: každý druh musí mít neprázdný symbol i větu,
  vyžádání review od sebe sama má vlastní znění, chybějící cíl nesmí nechat větu končit na „od“
  a monospace patří jen titulku commitu. `AvatarLoader` proti `FakeHTTPGetter`: že se obrázek
  **netahá dvakrát**, že se **selhání nezkouší znovu**, že data, která nejsou obrázek, se
  zahodí — a že **dva souběžné požadavky dají jeden dotaz** (souběžně, protože sekvenční test
  by prošel i bez ochrany před prvním `await`). Zvlášť stojí, že **zrušené** stahování se dá
  zkusit znovu, kdežto selhané ne: na to je vlastní getter v testu, protože `FakeHTTPGetter` umí
  vrátit jen `HTTPError` a `CancellationError` se jím nasimulovat nedá.
- **Odpovídání do vláken (#73)** — čisté funkce plus publisher proti `FakeProcessRunner`.
  Nejdůležitější testy netvrdí, co se odeslalo, ale že se **nic neodeslalo**
  (`runner.invocations.isEmpty`): bez povolení v nastavení, s prázdným tělem a na zavřený PR.
  Vedle toho to, co je u odpovědi **jinak než u review** — nový commit odpověď ani vyřešení
  neblokuje. Klasifikace se hlídá tabulkou nad **skutečnými** hláškami z živého API, včetně toho,
  že se chybějící vlákno nesmí splést s výpadkem sítě; a `comment: null` musí skončit chybou, ne
  úspěchem. `Policy.inserting` má vlastní sadu, ve které je to hlavní, že vložení **nesníží**
  `missing` u useknutého vlákna.
- **`AppStore` — odpovídání (#73)** — `gh` je **podstrčený shell skript** v dočasné složce, který
  vypíše připravenou odpověď a zapisuje, kolikrát byl spuštěn. Fake publisher se sem podstrčit
  nedá (store si ho podle tvrdé podmínky nesmí držet ani jako továrnu), takže se projde celá cesta
  včetně čtení výstupu — a nula spuštění je jediný způsob, jak dokázat, že se **nevolalo nic**.
  Pokrývá: odpověď ve vlákně **bez druhého dotazu** na konverzaci, selhání, které **nechá text**,
  prázdnou odpověď bez volání sítě, a dvojklik pouštěný **souběžně** (sekvenční test by prošel
  i bez ochrany, proto má skript krátkou odmlku).
- **Komentář pod PR (#216)** — čtvrtá cesta ven, takže se u ní hlídá **totéž co u vláken**:
  že se bez povolení, s prázdným tělem a na zavřeném PR **nevolá nic**, a že nový commit
  komentář naopak neblokuje. Navíc dvě věci, které se dají pokazit tiše:
  - **Tělo jde přes `-f`, ne `-F`.** `--field` čte hodnotu začínající `@` jako jméno souboru,
    takže by komentář otevřený zmínkou skončil pokusem o čtení disku. Test se dívá na argument
    **před** tělem, jinak by regrese prošla nepovšimnutě u všech komentářů kromě těch se zmínkou.
  - **Hláška o prázdném komentáři musí být jiná než u odpovědi.** Věta, která pojmenuje něco
    jiného, než na co se člověk dívá, vypadá jako chyba v jiné části okna.

  Fixture je **skutečný** issue comment změřený na `ondrajodas/prism-review-sandbox#1`
  (`gh api …/issues/1/comments`); `POST` vrací tentýž tvar, takže se dá vzít odsud. Inline, ne
  soubor — je to jeden objekt.
- **`AppStore` — komentář pod PR (#216)** — stejné uspořádání jako u vláken (podstrčený `gh`
  skript, počítání spuštění). Pokrývá připsání do konverzace **bez druhého dotazu**, smazání
  textu po úspěchu, **zachovaný text** po selhání, nulu volání bez povolení, souběžný dvojklik
  a úklid rozepsaného textu, když PR vypadne ze seznamu.

  A hlavně: **osa nesmí po odeslání zmizet.** `Conversation.init` má `events` s výchozí prázdnou
  hodnotou, takže je při přeskládání lze vynechat bez chyby překladu — což se u #73 stalo
  a do #216 se to neprojevilo nikde jinde než na obrazovce. Hlídají to dva testy: jeden nad
  `Policy.inserting`/`applying` (obě cesty), druhý nad storem. **Ověřeno vložením regrese** —
  po vrácení původního kódu test spadne na `events.items == []`.
- **Labely a vyžádaní reviewery (#392)** — pátá a šestá cesta ven, takže se u nich hlídá **totéž
  co u vláken a komentářů**, a k tomu tři věci, které se dají pokazit tiše. Rozdělené je to na pět
  suit schválně: každá odpovídá na jinou otázku, takže se z červeného testu pozná, **co** se rozbilo.
  - **`MetadataPublishingTests`** — publisher proti `FakeProcessRunner`. Nejdůležitější tvrzení
    netvrdí, co se odeslalo: bez povolení (globálně i s povoleným **jiným** repem), bez jediného
    loginu a na mergnutý či zavřený PR **`runner.invocations.isEmpty`**. Vedle toho, co je jinak než
    u review: **nová hlava labely neblokuje**. A k tomu tvar payloadu na hotových bajtech
    (`{"labels":["bug","go"]}` a `{"labels":[]}` — prázdná sada je **platná akce**, ne `nil`), `-f`
    proti `-F` u loginu a **úklid dočasného souboru** po úspěchu i po pádu. Cesta se u toho bere
    **z argumentů, které publisher poslal**, ne výpisem `/tmp`: výpis by v paralelním běhu chytal
    cizí soubory a tvrdil úklid, který se nestal.
  - **`AppStoreMetadataTests`** — podstrčený `gh` skript s počítadlem spuštění, stejně jako
    u vláken. Nula volání: **na cizím PR**, **bez povolené brány**, u labelu, který **repo nezná**,
    bez načtené nabídky, nad nenačteným snímkem, u reviewera **mimo nabídku** a bez `gh`. K tomu
    tři stavy nabídky (nenačteno / prázdné repo / porucha), protože nabídka, která po výpadku sítě
    vypadá jako repo bez labelů, posílá člověka hledat labely, které tam jsou. Vedle toho cache (druhý příchod na PR se
    neptá), že se **nabídky s detailem netahají** (volání navíc, které se má platit až na otevření),
    a že se po úspěchu snímek přepíše **bez dalšího dotazu**. A ten nejcennější zápis: **vyžádání
    reviewera nesmaže schválení, které v panelu bylo** — GitHub ho v odpovědi neposílá.
  - **Týmy jsou vlastní sada tvrzení**, protože to byla **tichá ztráta**: do opravy se `requested_teams`
    zahazovaly a sekce byla u PR s týmovou žádostí prázdná (čtyři PR ze čtrnácti v jedné frontě).
    Testuje se, že tým jde do vlastního pole a **ne mezi lidi**, že PR s žádostí jen pro tým není
    prázdný, že se slug zbavuje předpony organizace (a že z `keboola/` **nevyjde `keboola`** — to je
    ta past, kterou chytil test na prázdný slug), že tým odejde **týmž voláním** v `team_reviewers`,
    že chybějící `requested_teams` v odpovědi nepoloží akci, která prošla, a že vyžádaný tým se
    v nabídce neopakuje.
  - **`PanelMetadataEditingTests`** a **`PanelReviewersTests`** — čisté funkce vyčerpávajícím
    výčtem. Že se z výběru nedá vyrobit label, který repo nezná; že sundání **posledního** labelu je
    prázdná sada, ne „nic neposílat“; že se přidáním jednoho labelu **nesmaže ten, který repo
    přestalo znát** (sada se posílá celá); a u reviewerů všech pět hodnot `SubmittedReview.State`
    plus `nil` — komentář bez verdiktu se do sekce **nedostane**, jinak by v ní u každého PR svítil
    review bot jako `čeká`.
  - **`LabelChipsTests`** (pravidlo) a **`PanelMetadataWidthTests`** (rozměr) — rozdělené schválně:
    první počítá nad **umělými, rovnými** šířkami, takže se výsledek dá spočítat v hlavě, druhý měří
    **skutečným písmem přes pásmo 240–520**. Kdyby to byl jeden test, nešlo by po spadnutí poznat,
    jestli se rozbilo rozhodování, nebo sazba. Hlídané pasti: dvouřádkový strop, `+N` právě tehdy,
    když se něco nevešlo, **ořez, který nechá místo na `+N`** (jinak jsou řádky tři), `+ label`,
    který neustoupí nikdy, a **`chce změny`, které se neořezává** — u reviewerů ustupuje jméno.
    Jedno tvrzení stojí zvlášť: **spočítaná šířka chipu se srovnává s nakreslenou**
    (`ImageRenderer` nad `LabelChipView`). Je to jediné, co chytá `box-sizing` — ostatní si berou
    tutéž míru, takže by prošla i tehdy, kdyby se z ní vypustil rám a odsazení. **Ověřeno vložením
    regrese**: s `frameWidth == 0` je rozdíl 14 bodů a test spadne, kdežto zbytek suity projde.
  - **`PickerSearchTests`** — hledání v nabídkách. Kromě váhy shody (začátek, hranice slova,
    vnitřek), diakritiky a „všechna slova musí sednout“ tam stojí tři tvrzení, která se dají pokazit
    potichu: že se **pravidlo dělí s paletou ⌘K** (tytéž primitivy i dělení dotazu na slova — kdyby
    se rozešlo, chová se jedno okno na dvě strany), že **shodné váhy nepřeskakují mezi průchody**
    (Swiftové `sorted` není stabilní, takže se pořadí drží druhým kritériem), a že **filtr nikdy
    nevrátí něco, co v nabídce nebylo** — tedy že se ani hledáním nedá vyrobit label, který repo
    nezná. K tomu kurzor: **ořezává, necyklí**, a ořezává i bez pohybu, protože index z předchozího
    dotazu může být za koncem.

    Od #434 je v téže sadě i **patka s nápovědou kláves**, a to nejcennější tvrzení je zase to
    o tom, co se **nestane**: `pickerShowsKeyHints(rowCount:)` a `pickerSelection(from:step:count:)`
    se musí shodnout, tedy nad prázdným seznamem se nesmí nakreslit nápověda ke klávesám, po kterých
    se nic nestane. Rozejít se to umí potichu — patka je stav okna, kdežto tohle jsou dvě čísla.
  - **`PickerKeyHintsTests`** (#434) — **rozměr patky, ne pravidlo**, a měří se **dvěma měřidly,
    protože každé odpovídá na jinou otázku**. `fittingSize` řekne, kolik místa si patka řekne (194 b
    pro `přepne`, 195 b pro `vyžádá` z 300, které má `.pkr`), tedy **kolik zbývá** — a to je jediné,
    z čeho se pozná, jestli se tam vejde ještě delší sloveso. `OverflowProbe` řekne, jestli něco
    přeteklo **za hranu**, což je u nabídky labelů jediná možná otázka: má pevný rámec 300 bodů,
    takže obsah za ním přeteče vizuálně, aniž by se velikost změnila. Prohání se i stavem, ve kterém
    je pod seznamem akce `Založit „…“` — tam je patka poslední prvek a nemá pod sebou nic, co by
    přesah ukrojilo.

    Jedno tvrzení je zapsané **podle toho, co se změřilo, ne podle toho, co bylo v úmyslu**: patka
    nabídku reviewerů (která šířku nemá danou rámcem) **rozšířila** ze 145 na 195 bodů, protože je
    v ní od #434 nejširší prvek. Tvrdí se proto, že nepřeteče **za** 300 ze zákresu, ne že nabídkou
    nehne — druhé by bylo nepravdivé.

    **Co se v harnessu ověřit nedá:** že ty klávesy doopravdy fungují. Testovací host nedostane
    aktivaci (změřeno u #392), takže nemá key okno a stisk nemá kam sednout — zvlášť u `⌥↵`, které
    je na poli, ne na okně. Ověřuje to člověk na běžící aplikaci; patka smí tvrdit jen to, co takhle
    ověřené je.
  - **`PanelHeadNoticeTests`** — že panel u staršího commitu **nekreslí nálezy jako platné**. Věta se
    testuje jako text z `Policy` (jmenuje obě sha a u neshody říká, že o kódu na obrazovce nemluví),
    a k tomu se **tři stavy notice musí nakreslit různě**. Porovnávají se **surové bajty bitmapy, ne
    `tiffRepresentation`**: TIFF ze dvou renderů se liší i u shodného obrázku (obálka nese metadata),
    takže na něm test procházel i s panelem, který notici ignoruje. **Ověřeno vložením regrese** —
    se zadrátovaným `.none` v panelu na bajtech spadne, na TIFFu prošel.
- **Založení nového labelu z nabídky (#413)** — **sedmá cesta ven, a první, která zapisuje do
  repozitáře**, takže se u ní hlídá totéž co u těch šesti a k tomu dvě věci, které jinde neexistují:
  **výčet důvodů, proč se akce nenabídne**, a **mezistav mezi dvěma voláními**.
  - **`NewLabelOfferTests`** — čistá funkce vyčerpávajícím výčtem. Nejcennější jsou tvrzení, ve
    kterých akce **není**: prázdné jméno (i samá mezera), existující jméno **bez ohledu na velikost
    písmen a diakritiku** (`bug` / `Bug` / `BUG` / `nález` / `nalez`), **cizí PR**, **vypnutá brána**
    a **nenačtená nabídka** — bez seznamu z repa není proti čemu hledat duplikát, takže by `Bug`
    prošlo vedle `bug` jen kvůli nedotažené odpovědi. Naproti tomu se nabídnout **musí** u prázdného
    **načteného** repa a u `bug-ui` v repu, které zná `bug-ui-legacy`: podřetězec není tentýž label,
    a kdyby o existenci rozhodoval, taková jména by nešla založit vůbec.

    Barva se tvrdí **literálem** (`design-debt` → `d4c5f9`), ne tou samou funkcí: jinak by test říkal
    jen „funkce se rovná sama sobě“ a přesazení hashe by nechytil. K tomu tvar palety (šestnáct
    šestimístných hexů malými písmeny, **bez bílé**) a že do ní padne každé jméno včetně emoji
    a pětisetznakového.
  - **`MetadataPublishingTests`** (rozšířené) — bez povolení, s prázdným jménem a na zavřeném PR
    **`runner.invocations.isEmpty`**. Dvě tvrzení jsou zvlášť pro tuhle metodu: **v adrese není číslo
    PR** (`repos/{repo}/labels`, ne `/pulls/` ani `/issues/`) a **payload nese jméno i barvu** na
    hotových bajtech, protože barva se posílá vždycky — bez ní by ji GitHub vybral sám a náhled
    v potvrzení by lhal. Jméno se u toho prohání JSONem s uvozovkami, zalomením a emoji (proto jde
    souborem, ne přes `-f name=…`). Duplikát (422 `already_exists`, **skutečné tělo odpovědi API**) má
    vlastní chybu a **nepočítá se za „možná to prošlo“** — druhý pokus dopadne stejně.
  - **`AppStoreMetadataTests`** (rozšířené) — tady bydlí ten mezistav a je k němu vlastní fake `gh`,
    který odpovídá **podle pořadí volání**. Jeden výstup pro obě volání by stav „label v repu je, na
    PR není“ nedokázal vyrobit vůbec. Tvrdí se: obě volání proběhnou a label je v nabídce **i** na PR;
    po pádu **druhého** je stav `createdNotAdded`, `failure` je `nil` (není to `failed` — půlka se
    stala), řádek v nabídce **je** a na PR label **není**; po pádu **prvního** mezistav nevzniká a
    v nabídce po tom nezůstane řádek, který neexistuje; a mezistav se **dorovná jedním kliknutím** na
    ten řádek, tedy tou samou cestou jako u každého jiného labelu. K tomu nula volání na cizím PR,
    bez brány, u existujícího jména, bez načtené nabídky a s **barvou vymyšlenou mimo `Policy`**.

    **Ověřeno vložením regrese**: bez zápisu do nabídky (`remember(_:in:)`) spadnou tři tvrzení —
    včetně toho o dorovnání, protože `toggleLabel` label, který repo nezná, odmítne.
  - **`SingleWayOutTests`** — **sedm** metod jmenovitě a `deleteLabel` v zákazu vedle `merge`,
    `close`, approve mimo review a milníku. Souborů zůstává **šest**: zakládání je sedmá **metoda**,
    ne pátý volající, a i to je tvrzení.
  - **`NewLabelPickerWidthTests`** — že se to do popoveru vejde. Měří se **pixely za hranou**
    (`OverflowProbe`), ne `fittingSize`: popover má pevný rámec 300 bodů, takže obsah, který se do něj
    nevejde, přeteče **vizuálně**, aniž by se rámec změnil. Prohání se tím tři jména včetně **39
    znaků**, na kterých se měřil zákres (akce jméno zalomí, neořeže), a k tomu spočítaný nejdelší
    řádek potvrzení — barva s hexem, v návrhu 265 b z 278. **Ověřeno vložením regrese**: s
    `fixedSize()` místo `fixedSize(horizontal: false, vertical: true)` na jménu v akci test spadne na
    tom nejdelším jménu.
  - **Sonda, ne tvrzení** (`PanelMetadataRenderProbe`, `TEST_RUNNER_PRISM_MEASURE=1`): dotaz bez
    shody, dotaz, který něco našel, shoda jen v casingu (tam se akce nekreslí), druhá obrazovka a
    panel s větou o nepovedeném přidání. Druhá obrazovka se sondě předává **počáteční hodnotou stavu**
    (`query`, `confirming`) — sonda nemá klávesnici, takže se k ní jinak nedostane; label do ní jde
    z `Policy`, aby se fotila ta barva, která doopravdy odejde.

    Potvrzení má navíc snímek **v obou režimech**, a ten jde `ImageRenderer`em s nasazeným
    `NSAppearance` (ne oknem): barvy z palety jsou dynamické `NSColor`y, takže o nich rozhoduje
    **kreslicí** appearance, ne `colorScheme` v prostředí — a `ScrollView` na téhle obrazovce není,
    takže se offscreen nakreslí celá. Stojí to za to u dvou věcí, které se v každém motivu chovají
    z jiné strany: výstraha (`Palette.stale.opacity(0.11)`) a bledý puntík labelu, který drží
    obtažení `--line`.

  **Co testy neověří:** že `⌥↵` v popoveru doopravdy dojde do pole. Mechanismus je tentýž jako
  u šipek z #392, ale klávesa v harnessu nemá kam přijít — testovací host **nedostane aktivaci**
  (změřeno u #392), takže pole nemá key okno. Ověří to člověk v pauze; totéž platí o `POST /labels`
  proti živému API, protože brána je ve slotové konfiguraci vypnutá schválně.
- **Merge vlastního PR z panelu (#465)** — **osmá cesta ven a první, která mění `main`**, takže se
  u ní hlídá totéž co u těch sedmi a k tomu dvě věci, které jinde neexistují: **výčet důvodů, proč
  se akce nenabídne**, a **hlava jako podmínka volání**.
  - **`BranchMergeTests`** — čistá funkce vyčerpávajícím výčtem. Nejcennější jsou tvrzení, ve kterých
    se merge **nenabídne**: cizí PR (tam se nekreslí ani nadpis sekce), vypnutá brána, **nenačtený
    stav větve** (`nil` i `.loading` i `.failed` — u nevratné akce je „nevím“ vlastní odpověď, ne
    slabší „nejde to“), chybějící hlavička nebo commity, konflikt, větev pozadu, chráněná větev,
    **červený check** a **vlastní blokující nález**. K tomu dvě rozhodnutí, která se dají potichu
    obrátit: **běžící a přeskočený check merge nezakazují** a `UNKNOWN` se **nepřebíjí konfliktem**
    (nad větou „je konflikt“ by věta „nevím“ nedávala smysl).

    Řádky stavu se tvrdí **textem, ne strukturou**: `3 commity · 2 checky` / `zeleno` proti
    `1 commit · 2 checky` / `1 neprošel` — skloňování je v nich to, co se rozbije nejtišeji. A
    **„bez checků“ a „checky se načítají“ jsou dvě různé odpovědi**: PR bez CI je běžný stav, kdežto
    nenačtené checky o PR netvrdí nic.
  - **`MergePublishingTests`** — bez povolení, na zavřeném a mergnutém PR, na **posunuté hlavě**
    a s prázdnou hlavou je **`runner.invocations.isEmpty`**. Tři tvrzení jsou zvlášť pro tuhle metodu:
    **payload nese přesně tři pole** (`commit_title`, `merge_method`, `sha`) na hotových bajtech —
    `commit_message` v něm schválně **není**, protože tělo squash commitu skládá GitHub ze zpráv
    slévaných commitů; **metoda se čte z konstanty**, kterou používá i potvrzení; a **`merged: false`
    se nebere jako úspěch**, i když návratový kód byl nula.

    Fixtures jsou **skutečné odpovědi**, změřené na `ondrajodas/prism-review-sandbox#8` — sonda tam
    byla pro tenhle účel založená, třikrát pushnutá a nakonec mergnutá. `409` (`Head branch was
    modified…`) je skutečné tělo z pokusu s cizí `sha`, `pr-merged.json` skutečná odpověď mergu. Text
    `405` (`Pull Request is not mergeable`) je proti tomu **z dokumentace, ne změřený**, a je u něj
    napsáno proč: vyrobit ho by chtělo PR v konfliktu nebo draft, a převedení sondy na draft zakázala
    permission brána. Je proto inline JSONem, aby se nepletl se skutečnými fixtures.
  - **`AppStoreMergeTests`** — tady se hlídá, **kdy se aplikace vůbec ptá**: na cizí PR a na mergnutý
    se na slévatelnost **neptá vůbec** (`branchStatusRequests.isEmpty`), druhý příchod na PR se neptá
    znovu a selhání se nezahodí do prázdna. K tomu nula spuštění `gh` bez brány, na cizím PR a nad
    červeným checkem — `mergeSubmission(for:)` vrátí `nil`, takže se sheet nad neproveditelným mergem
    neotevře ani tehdy, kdyby se na zakázané tlačítko nějak kliknout dalo. A po úspěchu **jedno**
    volání `gh` a **dvě čtení detailu navíc** (pre-flight a načtení stavu po mergi) — to druhé je to,
    na čem stojí, že panel merge nenabídne podruhé.

    Podstrčit mergnutý detail **dopředu** tady nejde: pre-flight publisheru se ptá tou samou gateway,
    takže by merge odmítl ještě před voláním. Že se z mergnutého stavu stane `notOpen(.merged)`, proto
    tvrdí `BranchMergeTests` nad čistou funkcí a store se ptá jen na to, že se pro ten stav došlo.
  - **`GhGatewayTests`** (rozšířené) — **líné pole**. Usazená odpověď se ptá **jednou**, `UNKNOWN`
    se doptá, po **třech** pokusech se vrátí `UNKNOWN` jako **odpověď, ne chyba** (z chyby by panel
    napsal „nepodařilo se zjistit“, což je něco jiného), neznámý stav se **nepřekládá na čistý**
    a chybějící `mergeStateStatus` odpověď **nepoloží** — GitHub ho vydá jen tomu, kdo má na
    repozitář zápis. Čeká se v testu **nula sekund** (`branchStatusDelay: .zero`), protože se měří
    počet dotazů, ne trpělivost.
  - **`SingleWayOutTests`** — **sedm souborů, pět volajících, osm metod** jmenovitě, a `merge` z
    výčtu zakázaných **zmizel**; zůstává approve mimo review, `close`, milník a `deleteLabel`.
    Je to jediné místo v repu, kde se ta změna pravidla dá přečíst jako změna, ne jako díra.
  - **`WindowShortcutsTests`** — `Views/MergeSheet.swift` přibyl do jmenovitého výčtu souborů, které
    si klávesu berou samy (`⎋` na `Zrušit`). Tlačítko, které merguje, zkratku **nemá**.

  **Co testy neověří:** že `PUT /pulls/{n}/merge` projde z běžící aplikace — brána je ve slotové
  konfiguraci vypnutá schválně, takže se akce v proklikávané instanci nenabídne, dokud si ji člověk
  nezapne. Ověřené je to **mimo aplikaci**, tímtéž voláním na sondě.
- **Srovnání větve s `main` (#466)** — **druhá cesta ven a první zápis do remote**, takže se u ní
  hlídá jiná trojice než u těch osmi: **že se nepushlo**, **že guard nejde obejít** a **že rebase
  v cache dělá to, co si o něm myslíme**.
  - **`BranchSyncOfferTests`** — čistá funkce vyčerpávajícím výčtem. Nejcennější jsou tvrzení, ve
    kterých se akce **nenabídne**: cizí PR (nekreslí se ani nadpis), vypnutá brána, **fork**,
    **neznámý původ větve**, zavřený a mergnutý PR (tam se výčet **ukončí**), srovnaná větev,
    konflikt, nenačtený i nepovedený stav větve, **rozdělaný rebase v cache** a běžící srovnání. Dvě
    rozhodnutí, která se dají potichu obrátit, jsou tvrzená zvlášť: **draft se srovnat smí**
    a **nezelené checky srovnání nebrání** — obojí je opak toho, co platí u merge.
  - **`GitBranchPushTests`** — devět z třinácti testů tvrdí, že **`runner.invocations` je prázdný**:
    cizí PR, fork, neznámý původ, zavřený PR, posunutá hlava, přejmenovaná větev, vypnutá brána
    a **strom mimo cache**. K tomu tvrzení o tom, co se posílá, když se poslat má: **lease s vypsanou
    hodnotou** a **holé `--force` v argumentech není**, a zdrojová strana je `sha` z rebase, **ne
    `HEAD`** (mezi rebasem a pushem si člověk mohl ve stromě něco zkusit z terminálu).
  - **`AppStoreBranchSyncTests`** — nula spuštění `git`u bez brány, na cizím PR, na PR z forku, bez
    odpovědi o původu větve, nad konfliktem, nad rozdělaným rebasem a **při nezměněné hlavě**. Měří
    se to **zápisem argumentů podstrčeného `gitu`** do souboru; fake pusher se sem podstrčit nedá,
    protože `AppStore` si podle tvrdé podmínky č. 1 nesmí držet ani továrnu na cestu ven — tatáž
    scéna jako u labelů a merge. Cesta ke `gitu` se přitom předává **i těm testům, které tvrdí, že
    se nepushlo**: bez ní by akci zakázala už brána a tvrzení by měřilo chybějící nástroj, ne guard.
  - **`RealBranchRebaseTests`** — integrace proti **skutečnému `gitu`**, remote je `file://`. Tuhle
    půlku se namockovat nedá: **jak se pozná konflikt** (`git` skončí nenulově i u neznámého základu,
    takže se rozhoduje podle toho, jestli po pádu rebase **běží dál**) a **kde leží rozdělaný rebase**
    (u pracovního stromu **uvnitř klonu**, ne ve stromě) jsou obojí věci, na kterých něco stojí,
    a platí jen tehdy, když to `git` doopravdy tak dělá. Rozdělaný rebase se přitom **rozjede
    naostro**, ne vyrobením složky `rebase-merge` — jinak by se testovala vlastní domněnka o tom, jak
    to `git` dělá. A jedno tvrzení je o tvrdé podmínce č. 5: **strom review se nepohne**.
  - **`SingleWayOutTests`** (rozšířené) — **čtyři nová tvrzení, protože jedno by nestačilo**: tři
    soubory s `BranchPushing`, jedna metoda protokolu (a jmenovitě zakázané `commit`,
    `deleteBranch`, `pushTag`, `createBranch`), **argument `"push"` jen v `GitBranchPush`** a **holé
    `--force` nikde v cestě do remote**. Třetí z nich je ten, který se dá nejsnáz přehlédnout: bez
    něj by se push dal poskládat ve store a tvrzení o třech souborech by prošlo. Pátým tvrzením je,
    že `Checkout/` ani `GitHub/` do remote nezapisují — půlka podmínky, která se nezměnila; šestým,
    že `Bash(git push:*)` zůstává v `ClaudeCommand.disallowedTools`, tvrzeno **literálem**.

  **Ověřeno vložením regrese, třikrát** (a je to u téhle změny podmínka, ne pečlivost): holé
  `--force` místo leasu položí `SingleWayOutTests` **i** `GitBranchPushTests`; vyndaný guard na
  autorství položí „Na cizí pull request se nepushuje“ a pusher pak doopravdy pushne; a
  `["push", "--force"]` složené ve `AppStore+BranchSync` položí tvrzení o jednom místě.

  **Co testy neověří:** že `git push` projde z běžící aplikace — brána je ve slotové konfiguraci
  vypnutá schválně. Ověřené je to **mimo aplikaci**, na sandboxu; postup je níž
  (*Jak se změřil `--force-with-lease`*).

  **A jak sekce vypadá, ověřil render, ne review** — `BranchSyncRenderProbe` (sonda, vypnutá
  `.disabled`, pouští se ručně). Vyrenderuje **dvanáct scén ve světlém i tmavém režimu** do PNG na
  skutečné šířce panelu (278 bodů), takže se dá srovnat s návrhem po řádcích. Našly se tím dvě věci,
  které z diffu vidět nebyly: na PR **z forku** bylo tlačítko zašedlé a v panelu o tom nestálo nic
  (odtud `Policy.syncWarnings`), a hláška pod akcemi sázela `.font(.caption)`, tedy systémovou
  hodnotu v sekci, která jinak sází explicitními body. **Sonda nezastupuje tvrzení** — co má platit,
  tvrdí `BranchSyncOfferTests`.
- **Místo na diff commitu vedle panelu (#392)** — `CommitPanelRoomTests` je **měření zapsané jako
  test**, ne mez v aplikaci. Počítá produkční funkcí (`Policy.charactersPerSide`) a skutečnými
  rozměry (šířka znaku mono písma, `DiffLineView.contentInset(for:)`), takže čísla nezastarají
  s doladěním sazby. Naměřeno na výchozím okně (1100, plocha tabu 1047):

  | Co je rozložené | Zbývá na diff | Vedle sebe | Pod sebou |
  |---|---|---|---|
  | strom (210) + panel (306) | 531 b | **22 znaků** | 49 znaků |
  | strom + proužek (38) | 799 b | 39 znaků | — |
  | jen proužek | 1009 b | 52 znaků | — |

  **Počty znaků jsou v dokumentaci, ne v tvrzeních** — a je to poučení z prvního běhu: `split`
  zapsaný jako `>= 20 && <= 24` v **plném paralelním běhu** jednou spadl, protože se v procesu, kde
  zároveň vzniká několik `NSHostingView`ů, vyřešila šířka znaku jinak. Číslo, které se v harnessu
  pod zátěží mění, nesmí být tvrzením: mění se **měřidlo, ne aplikace**. Testy proto tvrdí
  **nerovnosti a poměry** (split pod slibem, unified nad dvojnásobkem splitu, proužek nad panelem)
  a šířku znaku pinuje **jeden** test — když se písmo v systému změní, spadne on a řekne proč, místo
  aby se rozsypaly počty v půlce suity.

  **Nerovnost ale nestačí, když se měřidlo mění uprostřed tvrzení** (#367). V plném běhu spadlo
  `Složení stromu i panelu dá nejvíc místa` na `(both → 0) > (treeOnly → 35)`, tedy na **víc místa
  a méně znaků** — z monotónní funkce to vyjít nemůže, takže se šířka znaku vyřešila mezi těmi dvěma
  voláními jinak. Byla to computed property, tedy čtení metriky při každém použití; #367 z ní udělalo
  `private let` (jedno čtení za test) a #327 `static let` s náhradním měřením (jedno na proces).

  **Ani to nestačilo a od #407 se metrika čte odjinud** — z `FontMetric`, tedy z jednoho měřidla pro
  aplikaci i testy. Sada o metrice nemusí vědět nic; co ta nula doopravdy je a čím je to změřené, je
  v sekci *Metrika písma je tentýž kořen v jiné podobě (#407)*. Ve zprávě u tvrzení o šířce znaku
  je proto od #407 i `FontMetric.shared.tally` — bez počtu měření je „šířka znaku: 0“ příznak
  bez příčiny.

  Slib z `CLAUDE.md` je **120 znaků na stranu** a ten by se stromem i panelem chtěl okno
  **~2665 bodů**. Z toho plyne rozhodnutí: **nevynucuje se nic** — strom se složí ⌘1, panel ⌘2 —,
  protože složený proužek přidá ve splitu skoro dvojnásobek znaků, takže u commitu je čím zaplatit.
  Nejužší stav, do kterého se aplikace dostane (okno 700, panel na podlaze 246), dá na diff **402
  bodů**; v tom pásmu se proto měří i přetečení seznamu commitů a hlavičky (`PanelFreeTabWidthTests`
  má pro `Commity` **vlastní, širší pásmo** od 402).
- **Dostupnost služeb (#31)** — tři vrstvy, každá jinak. `Policy.health` vyčerpávajícím
  výčtem stavů (nic se nemockuje), včetně toho, co se dá pokazit tiše: že **incident mimo
  sledované komponenty puntík nerozsvítí** (skutečná fixture s výpadkem v `Actions`), že
  **status page sama na zelenou nestačí**, že se **offline nevydává za výpadek služby**, že
  selhaná kontrola nic nezablokuje a že **každý stav má neprázdný důvod** — puntík, který po
  hoveru nic neřekne, je dekorace. `StatusPageClient` proti `FakeHTTPGetter` na operational,
  incident, rozbitý JSON, `503`, `304` a na to, že se **`ETag` neukládá po odpovědi, které
  jsme nerozuměli** a že se **nepletou mezi službami**. `HealthMonitor` na to, že se na pozadí
  nekontroluje nic, že skryté okno interval neposouvá, že výchozí interval je deset minut
  a po selhaném volání minuta, že `304` a selhaná kontrola nechávají poslední známý stav a že
  zrušení není selhání. `AppStore` na to, odkud se berou skutečná volání — z pollingu (včetně
  rate limitu) a z výsledků session (včetně toho, že `timedOut` nezapisuje nic).

  Fake čas u smyčky **neuspává**, takže dojede celá při prvním `yield`u; přepínat jí stav
  uprostřed je závod a testy proto pouštějí dvě smyčky za sebou.
- **`URLSessionHTTP`** — proti **skutečnému systému**, ne fake runneru, a přitom **bez sítě**:
  chodí se na `127.0.0.1:1`, kde nikdo neposlouchá. Fake ověří, co si s odpovědí počne
  klient, ale ne to, jestli `URLSession` odmítnuté spojení a zrušení hlásí tak, jak si
  myslíme. Zrušení je deterministické — tělo tasku se rozjede teprve na `task.value`, tedy
  po `cancel()`.
- **Fixtures** — `Tests/Fixtures/`, načítané přes `Fixture.text(_:)` a `Fixture.data(_:)`.
  Cesta se odvozuje
  z `#filePath`, ne z bundlu: Swift Testing nemá `XCTestCase`, od kterého by šel
  `Bundle(for:)` odpíchnout. V `Fixtures/gh/` leží **skutečné** výstupy `gh`, jen
  přeformátované `jq`; berou se z **veřejných** repozitářů (`cli/cli`, `cli/go-gh`,
  `ondrajodas/PRism`), protože titulky firemních PR sem nepatří. Stav, na který se
  skutečná fixture nedá sehnat, se testuje inline JSONem přímo v testu.

  Výjimka jsou `review-error-*.json` ze spike #62: chybové odpovědi zápisového review API
  se z veřejného repa sehnat nedají (musel by se do něj poslat rozbitý payload), takže
  pocházejí ze soukromého sandboxu `ondrajodas/prism-review-sandbox`. Neobsahují nic než
  hlášku GitHubu. Konzumenta zatím **nemají** — klasifikaci chyb odesílání píše #67; leží
  tady proto, že bez zápisu na GitHub se nedají vyrobit znovu.

  `releases.json` (#127) jsou **první tři** z 69 vydání vlastního repa, jak je vrátilo
  `gh api` — jen zkrácené na prefix a přeformátované `jq`. Celá odpověď má stovky kilobajtů
  a tvar je u všech položek stejný, takže tři stačí.

  `Fixtures/statuspage/` jsou **skutečné** `components.json` z obou status pages, sebrané
  tou adresou, na kterou se ptá aplikace. `github-incident.json` je z nich jediný upravený:
  incident se na přání nevyrobí, takže je do skutečného tvaru dopsaný — `major_outage`
  a `degraded_performance` na sledovaných komponentách a `partial_outage` v `Actions`, aby
  bylo na čem ověřit, že se cizí výpadek nepočítá.

  **U fixture, která stojí na zakončení řádků, je doklad blob — ne řádek v `.gitattributes`**
  (#353). Atributy se na položku, která už v indexu leží, **zpětně neuplatní**: u
  `gh/pr-body-linear.md` se `-text` přidalo v tomtéž PR (#120), ale až *po* prvním `git add`,
  takže tu položku už nechalo být. V repu tím ležela fixture bez jediného `CR`, přesto že si ji
  `ReviewIntentTests` výslovně kontroluje (`body.contains("\r\n")`) — sada padala a `main` byl
  červený, zatímco řádek v `.gitattributes` vypadal jako pojistka a nedělal nic. Pracovní kopie to
  zamlčí: `core.autocrlf=input` normalizuje **při zápisu do indexu**, ne při checkoutu, takže
  soubor na disku `CR` mít může a commit ne.

  Kontrolují se proto **dva bloby** — index před commitem a `origin/<branch>` po pushi:

  ```bash
  git cat-file -p :Tests/Fixtures/gh/pr-body-linear.md | LC_ALL=C grep -c $'\r'
  git cat-file -p origin/<branch>:Tests/Fixtures/gh/pr-body-linear.md | LC_ALL=C grep -c $'\r'
  ```

  **Ten druhý je podstatný**: bez něj se to může ztratit znovu tou samou cestou a pozná se to až
  na červeném `main`. Levnější náhled na obojí dá `git ls-files --eol <cesta>` — vypíše `i/…`
  (index), `w/…` (pracovní kopii) i `attr/…`, takže rozejití je vidět na jednom řádku; správný
  stav téhle fixture je `i/mixed w/mixed attr/-text`, rozbitý byl `i/lf w/lf attr/-text`.

  **Opravit to jde jedině novými bajty**, a co zabralo, je změřené: **znovu stáhnout tělo z API**
  (`gh api repos/metalbear-co/mirrord/pulls/4702 --jq .body`, 13 `CRLF` ze 14 řádků) a pak už
  stačí obyčejný `git add` — `-text` konverzi vypíná, takže se bajty uloží, jak jsou.
  `git add --renormalize` dá týž blob (změřeno), ale **sám o sobě by nepomohl**, stejně jako
  `git rm --cached`: normalizovaná pracovní kopie `CR` neobsahuje, takže re-add bez nových bajtů
  uloží zase `LF`.
- **`StreamParser`** — proti **všem** fixtures ze skutečných běhů, plus syntetické rozbité
  vstupy: nevalidní JSON, useknutý řádek, neznámý event, nález bez povinných polí, prázdný
  vstup. Fixtures ze skutečných běhů už v repu jsou
  (`Tests/Fixtures/stream-json/`, viz [`docs/claude-cli.md`](claude-cli.md)): běh
  s nálezy, čistý běh, zabitý běh a odmítnutý zápis. Parser se testuje proti nim.
- **Odpověď na pokus o nástroj (#326)** — čtyři vrstvy, protože se to dá pokazit v každé z nich:
  `ToolStepOutcomeTests` na čisté funkce (`Policy.toolOutcome`, `Policy.toolStepMark`) výčtem,
  `StreamParserTests` na rozbor streamu, `ToolResultPairingTests` na párování v ose
  a `ClaudeReviewRunnerTests` na to, že odmítnutí odejde do průběhu **za běhu**, ne až s koncem.

  Nejcennější jsou tři tvrzení o tom, co se **nestalo**:

  - **Krok, jehož odpověď nedorazila, nezůstane hotový.** Vstupem je `review-killed.jsonl`
    **řezaný na posledním `tool_use` řádku** — tak vypadá stream zabité session. K tomu druhá
    podmínka v témže testu, že kroky **před** ním zavřené jsou: bez ní by test procházel i tehdy,
    kdyby se `user` eventy nečetly vůbec (past z #296 — tvrzení, které platí i s vyndanou opravou).
  - **Chyba nástroje se nestane odmítnutím.** `grep` bez shody vrací `is_error` při každém běhu,
    takže by z odznaku `ODMÍTNUTO` byl poplach nad běžným krokem. Inline JSONem, a je u toho napsané
    proč: ve všech osmi fixtures přišel `is_error` **vždycky** s `tool_result_meta`.
  - **Osa uložená před #326 se nekreslí jako běžící.** Literál v testu je tvar, který zapisoval
    encoder před změnou (`{"tool":{"_0":{"detail":…,"name":…}}}`, bez `id` a `outcome`) — vytištěný
    dnešním encoderem, protože nová pole jsou volitelná, takže se u nespárovaného pokusu neukládají
    vůbec. Že to tak zůstane, hlídá druhý test; bez něj by ten literál mohl tiše přestat být tvarem,
    jaký na disku doopravdy leží.

  **Ověřeno vloženou regresí, dvakrát** (čísla jsou z běhu):

  | Vložená regrese | Co spadne |
  |---|---|
  | `user` eventy se nečtou (stav před #326) | 7 testů ve třech suitách — mezi nimi „krok, jehož odpověď nedorazila, zůstane pokusem“ a „odmítnutí dorazí do průběhu ještě před koncem běhu“ |
  | osa páruje odpověď bez ohledu na `id` | 2 testy: odpověď na neznámý krok a krok bez `id` |

  Dva zádrhely, na které se u toho naráží: **trvání se nesmí porovnávat na rovnost** (osa měří
  rozdílem dvou `Date`, takže 0,7 s vyjde jako 0,7000000476837158 — testuje se pásmem)
  a **`Duration.milliseconds` je v testovacím targetu `String`** (`Tests/DurationText.swift`
  přebíjí to číslo z `RunUsage`), takže se do `#expect` píše srovnání `Duration` s `Duration`.

  Jak řádek kroku vypadá, je otázka na obrázek: `ToolStepRenderProbe` (sonda, pouští se ručně
  `TEST_RUNNER_PRISM_MEASURE=1`) vyrendruje všech pět podob vedle sebe — prošlý s trváním,
  odmítnutý s odznakem, chybu nástroje, běžící pokus a krok z osy před #326 bez značky — ve dvou
  šířkách, aby bylo vidět i to, že se v úzkém místě ořezává cesta, ne značka.
- **Slévání nálezů z opakovaného `ReportFindings` (#381)** — dvě sady vedle sebe:
  `FindingMergeTests` na čistou funkci (`Policy.mergedFindings`) vyčerpávajícím výčtem
  a `StreamParserTests` na tu samou věc přes parser, ať se neověřuje jen pravidlo bez cesty k němu.
  Vstupem je fixture `report-findings-corrected.jsonl` — poskládaná z **uloženého záznamu
  z provozu** (dva nálezy jednoho běhu, texty doslova včetně cyrilice `веийлорсту`, kterou
  reviewerovi prosákla do češtiny). Provenience je v první řádce fixture jako
  `_prism_fixture_note`, protože v JSONL komentář být nemůže; parser ho přeskočí jako každý
  neznámý event a **jeden test se ptá, jestli cyrilice v souboru pořád je** — kdyby se cestou do
  repa ztratila, tvrzení „vyhrálo pozdější hlášení“ by procházelo naprázdno. Tatáž pojistka jako
  u fixtures s `CRLF`, jen tady nejde o zakončení řádků, takže do `.gitattributes` nepatří
  (v souboru je **nula** `CR`, ověřeno na bajtech i na blobu).

  Fixtury `stream-json` se ve **všech čtyřech** čtečkách dělí `TextLines.content(_:)`, ne
  `split(separator: "\n")` — pravidlo z #292/#295 platí i v testech (`StreamParserTests`,
  `RunUsageTests`, `ClaudeReviewRunnerTests`, `FindingDuplicateProbe`). Nad fixturou s `CRLF` by
  `split` nerozdělil vůbec, takže by z celého streamu zbyl jeden „řádek“ a sada by zezelenala nad
  prázdným výsledkem.

  Nejcennější jsou tři tvrzení o tom, co se **nestalo**: dva různé problémy na jednom řádku
  z **jednoho** volání se neslijí, nález, o kterém pozdější volání mlčí, nezmizí (a `droppedFindings`
  se nehýbe), a prázdné ani nečitelné pozdější volání nálezy nesmaže. **Ověřeno vloženou regresí ve
  třech variantách** (čísla jsou z běhu, ne odhad):

  | Vložená regrese | Co spadne |
  |---|---|
  | identita z #17 (`file, line, summary`) | **5 testů, 7 tvrzení**; v nálezu zůstane `условиевторой` |
  | slití podle `(file, line, category)` uvnitř sady | **2 testy** — a **reálná fixture to nechytí**, protože ta dvojice na `Cart.swift:17` má různou `category`; chytá to až inline test |
  | poslední sada vyhrává celá | **7 testů**, a když vyhrává i prázdná sada, **9** |
- **Sonda `FindingDuplicateProbe` (#381)** — bublina **před opravou a po ní na jednom plátně**, nad
  tou samou fixturou. Stav „před“ se skládá tím, že se každé volání sečte zvlášť (přesně to dělal
  parser do #381), takže obě bubliny stojí na týchž datech. Je to sonda, ne test: „je v bublině
  nález jednou?“ je otázka na obrázek a v aplikaci ve slotu se ten stav vyrobit nedá — záznam
  s duplikátem leží v cache hlavní instance a do té se nesahá.
- **Kontrola nálezů z minula (#150)** — čtyři oblasti, každá na jinou tichou poruchu:
  - **`RecheckCommand`** — prompt a **čtení odpovědi**. Odpověď je volný text od modelu, takže
    se testuje každý způsob, jak může přijít jinak, než se o ni prompt řekl: `id` číslem
    i řetězcem, mimo rozsah, `still_applies` i `Still Applies`, prázdná věta, JSON v ```-bloku,
    věta okolo, chybějící `result` event (zabitá session). **Neznámý stav se nesmí domyslet** —
    z „fixed“ se `resolved` nedělá, protože „vyřešeno“ u nálezu, na který se nikdo nekoukal, je
    ta dražší polovina té chyby. A vlastní test drží, že **prompt review se nezměnil**: požadavek
    bez materiálu dostane přesně tentýž text jako do #150. Pojistka o jazyku platí pro **oba**
    prompty.
  - **`Policy`** — párování odpovědí na nálezy **produkční** funkcí (`Policy.key(of:)`, ne kopií
    pravidla v testu), včetně nálezu, který se mezitím přeložil. A kdy se odznaky **nesmí**
    ukázat: kontrola proti jiné hlavě, nenačtený detail (hlava neznámá). Počty se ověřují i na
    odmítnutém nálezu (nepočítá se) a na nálezu bez odpovědi (`unanswered`).
  - **Odznak závažnosti** (`Policy.severityBadge`) — vyčerpávajícím výčtem, a to nejcennější
    tvrzení sady je, že **`vyřešeno` nesundá `blokuje`**: obojí vypadá na obrazovce správně, takže
    kdyby to `vyřešeno` spolklo, poznalo by se to až u PR, který se nemergoval bez důvodu.
    Ověřeno vložením regrese (`blocking: false` v produkční funkci) — spadnou z toho čtyři testy,
    včetně toho o kartě. Dál: odmítnutí přebíjí kontrolu a **nepřeškrtává** (dva různé „nepočítá
    se“ se nesmí slít do jednoho obrázku), `pořád platí` a `nejasné` závažnost nemění, a skupinová
    varianta vydá `vyřešeno` jedině tehdy, když ho kontrola dala **všem platným** nálezům místa —
    jinak by se přeškrtlo shrnutí nálezu, který pořád platí. A že se karta v panelu a řádek
    tabulky ptají **téže** funkce, tedy že se ta dvě místa nemají čím rozejít.
  - **`ReviewStore`** — kontrola se ukládá k záznamu nálezů, přežije restart, **nesrovná
    `isStale`**, chybějící soubor a symlink jsou chyba. A ten nejcennější: `save` kontrolu
    do `runs` nepustí a záznam po tom pokusu zůstane **bit po bitu stejný**.
  - **`AppStore`** — kdy se **nenabízí** (bez záznamu, nad hlavou PR, se samými odmítnutými
    nálezy), že se bez materiálu nespustí ani přímým voláním, a že ji zastaví i **hlava vrácená
    zpátky** na commit nálezů (force push mezi nakreslením tlačítka a kliknutím) — tam se
    rozhoduje podle čerstvě dotažené hlavy, ne podle té v cache detailu, jinak by session
    porovnávala commit sama se sebou za peníze. Ověřeno vloženou regresí. Dál: že session dostane nálezy
    jako materiál a klíč druhu `recheck`, že se verdikty uloží k nálezům z minula, že
    **vyřešený nález nemizí** (`activeFindings` a `dismissals` se nezmění), že kontrola
    nepřidá chip ani nález, že zrušená neuloží nic, že se zabitá session nedopočítává, a že
    běžící kontrola drží `runningReviews`, chrání repo před eviction a zavírání ji zabije.
  - **Sazba** — věty o počtech, nápověda u odznaku a u tlačítka (`nonisolated static` funkce,
    takže bez kreslení). Hlídá se hlavně to, aby text netvrdil víc, než data unesou: nálezy bez
    odpovědi jsou ve větě, spadlý běh to řekne v nápovědě a odznak nese v sobě `kontrola:`.
- **`DiffParser`** — proti **skutečným** výstupům `gh pr diff` z veřejných repozitářů
  (`Tests/Fixtures/gh/pr-diff-*.diff`: běžný diff, přejmenování včetně `similarity index
  100%` bez hunků, 44 binárek vedle textových souborů, smazaný soubor). U každé fixture se
  kontroluje `unrecognizedLines == 0` — to je ta věta „rozumím celému formátu“. Syntetické
  vstupy pokrývají, co se z reálného PR nedá sehnat: odebraný řádek začínající `---`,
  hunk bez počtu řádků, `\ No newline at end of file`, prázdný kontextový řádek, změna
  jen práv a nesmysl mezi soubory.

  **Diff s `CRLF` má vlastní fixture, a je to skutečné `gh pr diff`** (#295):
  `gh/pr-diff-crlf.diff` je veřejný `microsoft/terminal#20524`, kde je `CRLF` na **70 řádcích ze
  76** — struktura (`diff --git`, `---`, `+++`, `@@`) má `LF`, obsah `CRLF`, takže tatáž fixture
  ověřuje i míchaná zakončení v jednom textu. Do #295 by se z celého toho diffu stal **jeden**
  řádek. Fixture si test **kontroluje** (`text.contains("\r\n")`) a `.gitattributes` jí drží
  `-text`, jinak by ji `core.autocrlf=input` při commitu normalizoval a test by zezelenal nad
  vrácenou chybou — tatáž pojistka jako u `gh/job-log-head.txt`.

  **`-text` se ale řídí surovými bajty, ne obsahem** (#339): u fixture v **JSONu**
  (`gh/pr-commits-crlf.json`) je `CR` escapovaný jako dvojice `\` + `r`, takže surové `CR` v souboru
  nejsou a normalizovat není co — ta proto v `.gitattributes` **není** a je u ní napsané proč.
  Kontrola v testu zůstává v obou případech, protože platí bez ohledu na nastavení gitu. A že
  `-text` doopravdy zabral, se pozná **jedině na blobu** — viz *Fixtures* výš (#353).

  Nejcennější tvrzení té sady je **„tentýž diff se `CRLF` a s `LF` dá stejný model“**: je to
  zároveň odpověď na „nezměnilo se něco na `LF` vstupech?“, protože z rovnosti modelů plyne i to,
  že texty řádků — a s nimi klíče do `SyntaxRunCache` (#153, #224) a vstup do word-level
  rozdílu — jsou stejné. Vedle toho výčtem: počty řádků obou hunků, čísla řádků, nadpis sekce za
  druhým `@@` a že **v textu řádku `CR` nezůstal**.
- **`TextLines` (#295)** — vyčerpávající výčet nad jediným místem, kde se rozhoduje, co je řádek.
  `LF`, `CRLF` i samotné `CR`, míchaná zakončení, prázdné řádky (`all` / `content` / `nonEmpty`),
  prázdný vstup, `Substring` místo `String` — a hlavně **dva testy, které tvrdí, že se něco
  NEstane**: že `U+2028`, `U+2029`, `NEL`, `VT` a `FF` řádek **nedělí** (pro `git` je to obsah,
  takže rozdělit se na nich znamená posunout čísla všech řádků pod tím), a že `String.singleLine`
  je přesto **srazí** — ta dvě pravidla se schválně liší a bez testu by je někdo srovnal.

  Volající mají svoje: `FileExpansionTests` (obsah souboru s `CRLF`, `CRLF` = `LF`, koncové
  zakončení nedělá řádek navíc), `SelectableCodeTextTests` (text v sheetu se sází po řádcích,
  `CRLF` = `LF`, a že **bez známého jazyka se text nedělí vůbec** — tou cestou chodí log),
  `CopyPolicyTests` (počet v popisku `Kopírovat rozsah` nad souborem s `CRLF` a že do schránky jde
  text bez `CR`) a `MarkdownParserTests` (`CRLF` dá tytéž bloky jako `LF` — do #295 dělalo
  `components(separatedBy: .newlines)` z každého řádku cizího komentáře vlastní odstavec).

  **Regrese ověřená vložením regrese, dvakrát.** Vrácené `split(separator: "\n")` v `TextLines`
  položí **41 testů v 8 suitách** — a mezi nimi i `GhResponseHeadersTests` (14 tvrzení)
  a `Příprava logu checku` (5), tedy sady z #292; tím je zároveň doložené, že jejich převedení na
  `TextLines` neztratilo, co hlídaly. Druhá regrese: rozšíření `isLineTerminator` na `isNewline`
  položí přesně ty dva testy o unicode oddělovačích, a nic jiného.
- **`DiffRow`** — skok z nálezu: na změněný řádek, na soubor u nálezu bez čísla i mimo
  hunky, `nil` u souboru mimo diff, a přejmenovaný soubor nalezený pod starou cestou.
  Rozbalení kontextu má vlastní sadu: kde skryté úseky jsou (nad prvním hunkem, mezi
  hunky s posunem starých čísel, za posledním s neznámým koncem), že se rozbalený řádek
  chová jako kontext s oběma čísly, že se hlavička po slití hunků sundá a že kotva na
  řádek platí i po rozbalení.
- **Pohled vedle sebe (#98)** — párování nad syntetickými diffy (stejně dlouhé bloky,
  nestejně dlouhé na obě strany, samostatný blok odebraných i přidaných, kontext, `meta`, nový
  a smazaný soubor, odebraný řádek **po** přidaném) a nad tím dva **invarianty** proti
  skutečným fixtures: že se z dvojic poskládají přesně původní řádky (počty, tedy ztráta
  i zdvojení) a že pořadí na každé straně kopíruje původní diff. Ověřené dočasně vloženou
  regresí, ne jen zeleným během: vypuštěný přebytek odebraných shodí obojí.

  Vedle toho `SplitBubbleTests` na to, co se dá pokazit tiše: bublina nálezu pod dvojicí,
  nález mimo diff, který u hlavičky souboru **zůstane**, vlákno na **odebrané** straně, vlákno
  a komentář na kontextovém řádku, které **nesmí vzniknout dvakrát**, a kotvy — nálezová platí
  v obou pohledech (i po rozbalení kontextu), kdežto ta na komentář k odebranému řádku míří ve
  split pohledu na dvojici.
- **`FileTreeNode`** — slévání složek s jediným potomkem, větvení, pořadí podle diffu,
  součty na složkách a unikátní identity (`a/x.swift` vs `b/x.swift`).
- **`AppStore` — dotažení kódu k nálezům** — že se tahá jen u nálezu mimo hunky, že se
  nesahá na soubor mimo diff ani na nález bez řádku, a že se druhý rozsah vyžádaný během
  načítání neztratí.
- **`RevealedLines`** — slučování překrývajících se i **sousedících** rozsahů a dělení
  mezery na skryté a odkryté kusy, včetně odkrytí, které mezeru přesahuje.
- **`Policy.chips`** — každý stav zvlášť, včetně toho, že nereportující běh ani běh se
  ztraceným nálezem nesmí vyjít jako `čisté`, že běžící reviewer přebije starší výsledek
  a že reviewer mimo nastavenou sadu o chip nepřijde.
- **`Policy.queueRow` a `ReviewStateAppearance` (#172)** — dvě vrstvy téhož řádku. `Policy`
  vyčerpávajícím výčtem: PR bez záznamu nedá **prázdno, ne nulu**; každý běh má v proužku svůj
  díl v pořadí běhů; čistý reviewer má váhu 1, aby z proužku nezmizel; a čtyři výsledky se
  neslijí (`clean` × `dismissed` × `inconclusive` × `blocking`). Nejcennější je test, že
  **odmítnutý nález řádek neblokuje** — odmítnutí se dělá právě kvůli tomu účinku, takže by se
  jeho ztráta jinak neprojevila nikde jinde než tím, že řádek svítí červeně napořád. Vedle toho
  test, že nález jednoho revieweera **nezčervená cizí díl**: odmítnutí i nálezy visí na záznamu,
  takže se musí protnout se skillem běhu. `ReviewStateAppearance` na text i barvu naráz, protože
  se od #172 čtou na dvou místech (odznak a hrana řádku) — včetně toho, že blokující mění obojí,
  že bez blokujících odznak nenaroste o „0 blokuje“ a že zastaralé zůstane žluté i s blokujícím.
  Past v testu: `Policy.key(of:)` skládá identitu z revieweera, místa a **shrnutí**, takže tři
  nálezy se stejným shrnutím jsou pro odmítnutí jeden a týž — vstup musí být rozlišitelný.
- **Záložky okna (#180)** — otevření, žádný duplikát při druhém kliknutí, přechod na sousední
  záložku po zavření aktivní, propadnutí domů u poslední a to, že **zavření neaktivní záložky
  nepřepne obsah**. Nejcennější je test, že **zavření nezahodí rozdělané review** — jinak by okno
  umělo zahodit rozepsanou práci jedním kliknutím na křížek. Past při jeho psaní: draft nevznikne
  bez známé hlavy PR, takže se musí napřed dotáhnout detail; první verze testu selhala už na
  přípravě a vypadalo to jako chyba v zavírání.
- **Prstýnek běžícího review (#350)** — `SpinningRingTests`. Ptá se na jedinou věc, a je to
  ta nejcennější podoba testu: **že se prstýnek točí v CoreAnimation, a ne ve SwiftUI.** Kontroluje
  se to dvěma tvrzeními naráz — v hostované hierarchii **je** `SpinningRingView` (tedy AppKitová
  vrstva, ne SwiftUI kresba) a na jeho oblouku **visí** animace pod známým klíčem. Kdyby se ptalo jen
  na to druhé, prošla by i verze, která si vedle CoreAnimation nechá `repeatForever`. Měřit místo
  toho CPU nejde: strojově závislé číslo by z toho udělalo test padající bez chyby v kódu — na to je
  gated sonda `IdleWindowSpinProbe`. Vypnutý pohyb v systému se zkouší na `SpinningRingView`
  napřímo, protože `accessibilityReduceMotion` je v `EnvironmentValues` jen ke čtení a v testu se
  nedá nastavit. Ověřeno **vložením regrese**: po návratu k `withAnimation(.repeatForever)` test
  spadl na tom, že v hierarchii žádné `SpinningRingView` není.

  Druhé dva testy hlídají to, co ve SwiftUI bylo zdarma a s přepisem do AppKitu se musí obsloužit
  ručně: **změna systémového akcentu** (posílá se notifikace, tvrdí se na barvě oblouku — příznaky
  překreslení bez okna na obrazovce nedrží, takže by z nich byl test padající nad správným kódem)
  a **jiná šířka tahu** (musí si vyžádat rozvržení, protože cesta je o půl tahu zúžená dovnitř).
  Obojí ověřeno vložením regrese — bez pozorovatele, resp. bez `needsLayout`, padnou.
- **Tlačítko obnovení (#442)** — tři sady, protože jedno tvrzení tuhle změnu nepokryje.
  `RefreshControlTests` je vyčerpávající výčet nad jedním `Bool`em a hlídá hlavně to, co se nesmí
  slít: **prstýnek a zákaz kliku jdou vždycky spolu** (točící se tlačítko, které pustí druhý dotaz,
  i mrtvé tlačítko bez vysvětlení jsou obojí horší než původní stav) a **popisek pro čtečku
  obrazovky se v obou stavech liší** — jinak je to pro VoiceOver pořád stejné tlačítko `Obnovit`
  a celá změna se pro něj nestala.

  `RefreshButtonTests` hostuje `RefreshButton` a ptá se na `SpinningRingView` v hierarchii —
  tedy na **ten** prstýnek z pruhu záložek, ne na „něco, co se točí“; nový prstýnek nakreslený
  ve SwiftUI by tím propadl. K tomu obě půlky: v klidu tam prstýnek **není** (bez toho tvrzení
  by prošla verze, která ho nakreslí a nechá tam navždycky) a `fittingSize` je v obou stavech
  totožná a rovna 27 × 25 — hlavička nemá poskočit tím, že se aplikace ptá.

  **Zákaz kliku se z hostovaného view přečíst nedá** a je to mez harnessu, ne opomenutí:
  accessibility tree se v okně mimo obrazovku nenaplní (změřeno u odpočtu i u railu), takže na
  `AXEnabled` není kde se zeptat, a `.disabled(true)` se u tlačítka s vlastními barvami
  neprojeví ani v bitmapě. Tvrdí se proto na vrstvě, kde by druhý klik doopravdy něco stál —
  `AppStoreRefreshTests`: druhé obnovení se pouští **zevnitř** prvního (`FakeGitHubGateway
  .duringSearch`, protože jindy stav „právě se ptáme“ neexistuje) a gateway smí dostat jen jeden
  dotaz. Vedle toho tvrzení opačným směrem — **po doběhnutí prvního dotazu druhý projít musí**;
  zaseknutý příznak by znamenal tlačítko zakázané navždycky, tedy horší stav než ten, který se
  opravoval.
- **Cyklení pruhem `⌃Tab` (#245)** — dvě sady. V `Policy` **vyčerpávající výčet** nad `openTabs`:
  oba směry z každé záložky pruhu, obě obtočení (za poslední je domácí, před domácí poslední),
  jediná záložka nevede nikam a aktivní záložka mimo pruh taky ne. K nim invariant „krok tam
  a zpátky se vrátí na tutéž záložku“, který jde přes celý pruh, protože se to nejsnáz pokazí na
  okrajích. Ve store pak to, co z čisté funkce vidět není: že zkratka **nastaví jedině
  `activeTab`** — test srovnává výsledný stav se stavem po kliknutí na záložku (`activeTab`
  i `selection`), takže se `selection` nemůže rozejít s tím, co dělá klik. Vloženou regresí
  ověřeno obojí: `selection = next.pullRequest` v `selectTab` shodí ten srovnávací test,
  `-1` místo `count - 1` v `Policy` shodí obtočení dozadu (index mimo pole).
- **Detail PR — větve (#174)** — fixture `pr-view-open.json` dostal `headRefName`/`baseRefName`
  ze skutečného volání téhož PR (mergem se větve nemění), takže testy dál stojí na reálném
  výstupu. Vedle toho test, že **detail bez těch polí se pořád přečte**: přibyla až s #174
  a chybějící pole nesmí položit detail, na kterém stojí `headSha` pro review.
- **Karty nálezů (#175)** — `FindingRow` si testy nechává i po zahození tabulky: skládání textů
  a pořadí z `Policy` platí pro karty stejně. Nově k nim invariant, že **nález a jeho skupina
  dají totéž místo** (`FindingPlace`) — bez něj by lišta skákala jinam, než co je v panelu
  označené jako aktuální, a nebylo by z čeho poznat proč.
- **Tabulka nálezů a její součty (#242)** — nejcennější je test, že **odznak na záložce, tabulka
  a bubliny v diffu počítají totéž**: rozejdou se potichu, protože každé z těch tří míst si počet
  umí spočítat samo, a pak odznak tvrdí pět nad čtyřmi řádky. Hlídá se to na nálezech, ne na
  řádcích — řádek je **místo**, takže shoda dvou reviewerů je jeden řádek a dva nálezy; ověřeno
  vložením regrese (řádek na nález místo na místo shodí obě tvrzení naráz). K tomu řazení podle
  každého sloupce v obou směrech, invariant **odmítnuté naspod ať se klikne na cokoli**, a to, že
  setřídění nemění počty. Šířky sloupců výčtem: co odpadne v úzkém okně, že se sloupce vejdou do
  dané šířky a že nulová šířka nedá nulové shrnutí. K tomu **identita řádku přes všechna řazení**
  (nález Copilota): index po setřídění by při kliknutí do hlavičky přepsal identitu každému řádku,
  takže by SwiftUI vzal tabulku jako nový seznam a zahodil rozbalení.
- **Proč je prázdno v nálezech (#242)** — `Policy.findingsEmptyReason` výčtem. Testy tvrdí hlavně
  to, co se **nesmí** stát: schované filtrem se nesmí slít s `clean` a spadlá session zůstane
  spadlá i tehdy, když jiný reviewer ještě běží (jednořádková záměna pořadí podmínek by z ní
  udělala „review běží“).
- **Reviewer, který nepřečetl kód (#383)** — dvě sady a jsou postavené tak, aby padly na **obě**
  strany téže chyby. Bez druhé poloviny by se stav přestal čítat stejně spolehlivě jako s falešným
  čistem, jen by se to poznalo později.

  - **`CodeReadingTests`** — `Policy.codeReading(of:)` výčtem. Osy jsou **opsané ze skutečných
    uložených běhů** z cache (`security-review` z 18.–20. 8.), jen s cestami převedenými na veřejné
    repo: záznamy firemních PR do repa nepatří, takže se z nich bere **tvar**, ne obsah. Ten tvar je
    to zajímavé — jedenáct pokusů, z toho `Read` zadání (`<strom>.md`), `Read` v cizím transkriptu
    a sedm `Bash` s `git diff` uvnitř stromu, a **ani jeden otevřený soubor z kódu**. Nejcennější
    test je právě ten (`Běh, který si přečetl jen zadání a diff, kód neotevřel`) a hned za ním ten
    na **oddělovač v předponě cesty**: zadání leží jako `<strom>.md`, tedy soubor **vedle** stromu
    se stejnou předponou, takže bez `/` by ho `hasPrefix` spolkl jako soubor v kódu — a přečte si
    ho i ten běh, který se do kódu vůbec nepodíval. Dál: odmítnutý ani chybou skončený `Read` se za
    čtení nepočítá, `outcome == nil` **ano** (odpovědi na nástroje se čtou od #326, takže starší osy
    by jinak vyšly nepřečtené naráz), a `Grep` s `Agent` posílají odpověď na `unknown`, protože
    v ose nesou vzor, resp. nic.
  - **`UnreadCodeStateTests`** — celá cesta od záznamu k obrazovce, a je rozdělená přesně na ty dva
    směry. **Falešné čisto:** stav není `clean`, návrh verdiktu nevznikne, chip řekne co chybí, díl
    proužku není zelený, prázdný tab má větu a odznaky tří důvodů se neslijí ani mezi sebou, ani
    s `čisté`/`selhalo`/`zastaralé`. **Falešný poplach:** běh, který kód otevřel a nic nenašel, je
    `clean`; **levný a krátký** běh nad malým diffem se neoznačí (rozhoduje jediný pokus v ose, ne
    částka); starší záznam **bez osy** zůstává čistý; běh s nálezy se na čtení kódu vůbec neptá;
    a **jeden průkazný běh stačí**, i když druhý reviewer kód neotevřel — pozná se to na jeho chipu,
    ne na řádku. Plus přednosti důvodů a tvrzení, že je `byPrecedence` vyjmenovává **všechny**
    (čtvrtý zapomenutý důvod by tiše spadl na nejslabší tvrzení).

  K tomu jedno tvrzení v `DashboardTests`: **nula v legendě reviewerů není čisto**. Reviewer, který
  v okně sedmi dnů neotevřel jediný soubor, má nulu stejně jako ten čistý, takže se u něj hlídá
  `isConclusive` **i barva puntíku** (`DashboardView.legendOutcome`) — a v témže testu vedle něj
  stojí reviewer, který kód přečetl, aby bylo vidět, že šedá není plošná.

  **Ověřeno vloženou regresí v obou směrech**, ne jen zeleným během. Bez podmínky na čtení kódu
  padne **8 tvrzení v 6 testech** (falešné čisto). Když se naopak z `unknown` udělá `unread`
  — tedy „chybějící záznam je obvinění“ —, padne **12 tvrzení v 8 sadách** napříč celým repem
  (`ReviewStateFromRecordTests`, `VerdictSuggestionTests`, `QueueRowTests`, `ReviewerChipTests`,
  `FindingsEmptyReasonTests`, `AppStoreRecoveryTests` a obě nové), protože `makeStoredRun` osu
  ve výchozím stavu nemá — a přesně to je ta situace, ve které se okno nesmí rozkřičet.
- **Rozhovor nad PR (#452)** — šest sad a v každé jedno tvrzení, které se rozbije potichu.
  `AskCommandTests` tvrdí **obě konstanty sady literálem** (tvrdá podmínka č. 2) a k tomu, že je
  **vlastní podmnožina** reviewerovy s rozdílem právě `ReportFindings` a `Skill`; porovnat povolení
  proti `AskCommand.allowedTools` by neznamenalo nic, protože rozšířenou konstantu by test poslušně
  přečetl. Dál že se `--resume` **posílá jen s neprázdným id** a že do dokladu „přečetl X“ jde jen
  `Read`, který **prošel** — odmítnutý nic nepřečetl a řádek nad bublinou je doklad.
  `AskStoreTests` mají od #458 vlastní suitu *Rozhovor mimo cache*, která tvrdí, že se něco
  **NEstalo**: za odkazovanou rodičovskou složkou se cizí soubor **nepřečte, nepřepíše ani
  nesmaže**. Odkaz je na **složce**, ne na souboru — to je ten případ, který `isSymbolicLink`
  nezachytí a chytá ho jedině `contains`. **Ověřeno vloženou regresí**: bez té kontroly padnou
  všechny tři a `save` cizí soubor doopravdy přepíše. Tatáž suita je u `ReviewDraftStore`, protože
  je to store, ze kterého se opisovalo.
  `AppStoreAskTests` hlídají tři věci, které mizí tiše: **druhá otázka navazuje** (`resuming` je id
  z první odpovědi a materiál se do promptu nedává znovu), **odpověď bez textu dostane bublinu
  s důvodem** (zaplacená session, o které se mlčí, vypadá jako by nebyla) a **rozhovor přežije
  restart i nový commit** — to poslední je celý rozdíl proti nálezům (tvrdá podmínka č. 5), takže se
  druhý store staví nad **jinou hlavou** PR. Vedle toho **tvrzení, že se něco NEstalo**: prázdná
  otázka session nespustí a otevřený tab bez otázky na disk nic nenapíše. `AskStoreTests` jedou proti
  skutečnému disku (cizí rozhovor v souboru, symlink, rozbitý JSON — všechno **vyhodí**, nevrátí
  `nil`), `AskPromptTests` že **žádná sekce materiálu nezmizí mlčky** a `AskReferencesTests` že se
  odkaz nevyrobí z URL (dvojtečka s číslem je v ní port).

  Čekání na disk je tam, kde se z disku doopravdy čte: zápis si store rozjede vlastním taskem, o
  kterém si nedrží handle (`persistAsk`, tentýž vzor jako u draftu), takže jediný jev, na který se
  dá čekat, je **soubor**. Ten task navíc čte hodnotu **až v sobě** — se snímkem v parametru by
  starší zápis mohl přebít novější a v souboru by po restartu chyběla odpověď.

  **Zrušený běh se vyrábí chybou, ne `CancellationError`**, a bez toho se ta chyba nedá napsat:
  `FakeAskRunner(failingOnCancellation:)` dělá to, co dělá skutečný zabitý podproces — `git` ani
  `claude` o zrušení nevědí, takže vyhodí svou vlastní chybu a `CancellationError` se ven nedostane.
  Tvrdí se z toho dvě věci, obě **že se něco NEstalo**: po `Zastavit` nesmí u zastavené otázky
  přibýt bublina „Nepovedlo se…“, a po `Nový rozhovor` nesmí přibýt **ani v cache** — tam je to
  horší, protože zápis té bubliny vrátí na disk soubor, který se před chvílí smazal. Ověřeno
  vloženou regresí: bez `Task.isCancelled` padnou obě a `42.json` se v cache objeví znovu.

  **Composer se testuje přes skutečné okno a skutečnou klávesu** (`AskComposerTests`), a je to
  jediný způsob, jak se o té chybě dalo něco tvrdit: store obě poloviny výměny dělal správně od
  začátku (`AppStoreAskTests` tvrdí, že otázka doletí do rozhovoru) a otázka **přesto** po odeslání
  zůstala v poli. Rozbité to bylo **okružní cestou** — pole drželo text u sebe a dolů ho posílalo po
  odmlce 400 ms, takže klik trefený do té mezery odeslal starší otázku a rozepsanou dostal zpátky.
  Nad storem se to napsat nedá, protože store o tom poli nic neví.

  Čtyři věci, na které se u toho narazilo a stojí za zapamatování:

  - **`Button` je v tomhle okně kreslený SwiftUI**, takže v hostované hierarchii **žádný `NSButton`
    není** (ověřeno výpisem stromu — jsou tam jen views textového pole) a `accessibilityChildren()`
    vrací prázdno. `performClick` tedy nemá na čem. Zabírá
    **`window.performKeyEquivalent(with:)`** se syntetickým `⌘⏎`, a to i **bez aktivace aplikace**,
    kterou testovací host nedostane (#392) — jako vedlejší efekt to tvrdí i to, že si `⌘⏎` v tomhle
    tabu doopravdy bere `Zeptat se`.
  - **Do pole se píše přes `didChangeText()`**, ne přiřazením do `string`: binding se v SwiftUI plní
    z delegáta, takže samotné přiřazení by se do view nikdy nedostalo a test by tvrdil, že se nic
    neztratilo, i kdyby se ztrácelo všechno.
  - **Textové pole se hledá pokaždé znovu.** Prázdný tab a tab s rozhovorem jsou dvě různé větve,
    takže si SwiftUI umí composer přestavět — uložená reference pak ukazuje na `NSTextView`, který na
    obrazovce dávno není, a test nad ním tvrdí „pole se nevyprázdnilo“, i když se vyprázdnilo. Stálo
    to jedno kolo hledání chyby, která tam nebyla.
  - **Čeká se na jev, ne na okamžik** (#269), a hned dvakrát: mezi zápisem do pole a překreslením
    tlačítka je jeden průchod SwiftUI (mačká se proto z `waitUntil`, dokud si klávesu někdo
    nevezme — zašedlé tlačítko nic neodešle, takže opakování nevadí) a vyprázdnění pole je zase
    průchod po akci tlačítka.

  **Ověřeno vloženou regresí, ne zeleným během.** Když `submit()` posílá zálohu ze storu místo toho,
  co je v poli, padnou dvě sady (odeslaná otázka do rozhovoru vůbec nedoletí a v poli zůstane);
  když pole vyprazdňuje **bezpodmínečně**, padne `Otázka, která neodešla, v poli zůstane`.

  **Vzhled má sondu, ne tvrzení** (`AskTabRenderProbe`, `TEST_RUNNER_PRISM_MEASURE=1`
  + `TEST_RUNNER_PRISM_RENDER_DIR`): tři stavy tabu ve dvou šířkách, aby se daly položit vedle
  sekce 33 návrhu. Je to obrázková otázka — *sedí bublina na akcentu, je prstýnek na místě příští
  bubliny* —, na kterou měření neodpoví. A **rozhodnutí „pevný stack, ne líný seznam“ má vlastní
  měření** (`AskLogMeasurement`, ruční, obě podoby A/B/A/B): první rozvržení stojí **18 ms
  u dvaceti bublin, 87 ms u stovky a 242 ms u tří set**, proti plochým **4,6 ms** u líného seznamu
  a proti **413 ms**, které #361 naměřilo u tří set uzlů osy — a **s těmi 413 ms se u osy pevný
  stack přijal**. Bez čísla by to bylo opsané z jedné nebo druhé strany; osa i diff mají každý jinou
  odpověď a rozhoduje strop.

  **To měření jelo do #458 bez `NSWindow`u, a stojí za to vědět, jak to dopadlo.** Copilot na to
  upozornil právem — `ScrollView` bez okna obsah **nerozvrhne** a tenhle repos to má popsané
  u `AskTabRenderProbe` i `DetailTabRenderProbe`. Mechanismus se **potvrdil**: bez okna vyjde
  `obsah 0 pt`, takže scroller o výšce dokumentu neví nic.

  **Závěr „čísla jsou podhodnocená“ se ale nepotvrdil, a je to změřené, ne odhadnuté.** Bez okna
  vyšel pevný stack **dražší** (300 bublin: 283 / 301 / 308 ms proti 242 / 238 / 257 ms v okně)
  a **počet vyrobených prvků byl totožný** (907). Neúplné bylo tedy to, co scroller ví o svém
  dokumentu, ne to, kolik práce si stack vyžádal — takže rozhodnutí zůstalo. Plyne z toho pravidlo,
  ne jen oprava: **měřidlo vedle času vypisuje výšku obsahu a počet prvků** (jako
  `ConversationAxisShapeProbe`), protože zrovna tuhle chybu nejde poznat z časů. A obráceně:
  **„harness je nastavený špatně“ není totéž co „výsledek je špatně“** — obojí se musí změřit
  zvlášť, jinak se kvůli správné námitce otočí správné rozhodnutí.

  **Jednu věc harness neověří: co ta session doopravdy stojí.** Změřilo se to spuštěním `claude`
  s týmiž argumenty nad tímhle repem — první otázka **$1,56 / 125 s**, navazující přes `--resume`
  **$0,96 / 6,8 s** (čísla a co z nich plyne jsou v [`docs/claude-cli.md`](claude-cli.md)). Ten běh
  zároveň **našel dvě věci, které testy nechytaly**: materiál skládaný jen k první otázce (pruh
  `ví o tomhle PR:` se počítá živě) a nezahozené mrtvé `session_id`. Obojí je dneska opravené a má
  vlastní tvrzení.
- **Dráhy v tabu `Průběh` (#242)** — osy se skládají `record(_:at:)`/`finish(_:at:)`, tedy tou
  cestou, kterou vznikají doopravdy. Pokrývá: doběhlá session má hotové fáze, kterými prošla;
  **doběhlá bez nahlášených nálezů nemá fázi hlášení za hotovou** (reviewer, který
  `ReportFindings` nezavolal, nálezy nenahlásil, a to není nula); prázdný seznam **je** nahlášená
  nula; timeout, přerušení a zrušený běh mají každý vlastní stav, ne selhání; a běžící reviewer bez
  osy dostane dráhu ve frontě, aby běžící review neukazovalo prázdný tab. Jeden reálný nález přišel
  z testu: **session spadlá při startu** neznačila selhání v žádné fázi, takže dráha vypadala
  k nerozeznání od té, co ještě nezačala.
- **Dráha na každý nastavený reviewer (#242)** — tyhle testy hlídají tři různá „prázdno“, která se
  nesmí slít: **nespuštěno** (v sadě, na tomhle PR nic), **ve frontě** (review běží, čeká na slot)
  a **bez průběhu** (běh v záznamu je, jeho osa ne). To poslední je nejcennější a **ověřilo se
  vložením regrese**: bez něj tab o doběhlém běhu tvrdí, že se nespustil — změřeno na skutečné
  cache, 25 z 31 uložených běhů osu nemá. Dál se testuje, že **počet drah je sada plus záznamy**
  (přejmenovaný skill osu doběhlého běhu nezahodí, jen ji označí `mimo sadu`), že **dráhy vypisují
  tytéž reviewery jako chipy** v pruhu běhu (dvě odpovědi na „koho se to na tomhle PR týká“ by se
  rozešly potichu), že **pořadí je stabilní** i pro `running`, které je `Set` bez pořadí, a že
  **zdvojený skill v sadě dá jednu dráhu** — dvě by `ForEach`i daly jednu identitu dvakrát.
- **Doplněný konec uložené osy (#242)** — od #308 platí **jen pro soubory uložené dřív**, protože
  nová osa se ukládá celá; sada zůstává, protože staré záznamy na disku leží dál. Vznikla
  z **měření, ne z návrhu**: uložená osa
  svůj konec neobsahovala (7 ze 7 os po skutečném běhu), takže tab po restartu tvrdil `nedoběhlo`
  nad doběhlým review. Testuje se, že se konec doplní z běhu, pod kterým leží, a hlavně to, co se
  doplnit **nesmí**: prázdná osa (z chybějícího průběhu by vznikl vymyšlený), fáze hlášení u běhu,
  který `ReportFindings` nezavolal, a druhý konec u osy, která ho má. Plus že identita událostí
  zůstane rostoucí a jednoznačná — zkrácená osa si nechává původní čísla, takže by doplněný konec
  podle počtu dostal číslo menší než jeho předchůdce. **Osy vyrobené v testech konec mají**, a proto
  to nechytil žádný z původních testů; nová sada proto skládá osu přes `stored()`, jak vzniká
  doopravdy. Ověřeno vložením regrese (9 padlých tvrzení).
- **Živý výpis kroků (#325)** — rozhodnutí jsou čisté funkce, takže **výčtem**
  (`StepFeedTests`): co se u dráhy kreslí (prázdná osa výpis nedostane vůbec — `0 kroků session`
  by nabízel rozbalení prázdného okna), automatické rozbalení přes **všech devět** stavů dráhy
  (rozbalí se jedině `running`) a osmiřádková tabulka reakce na geometrii scrollu. Tři nejcennější
  tvrzení jsou ta, že se něco **NE**stalo: **doběhnutí výpis nezavře** (obrazovka by zmizela
  zrovna ve chvíli, kdy je na ni nejvíc důvodů koukat), **zavřený výpis běžící dráhy se sám
  neotevře** (bez množiny `opened` by ho automat otevřel příští událostí, tedy do vteřiny)
  a **narostlý obsah není odrolování** — narostlý obsah je o řádek „mimo konec“, takže by se
  sledování konce vypnulo samo první událostí.
- **Výška okna výpisu (#325, oprava po proklikání)** — okno je **obsah do stropu**, takže se výška
  počítá z rozměrů, které drží view (`StepFeedView.metrics`). Tím vzniká třída chyby z #236,
  jen o výšku: **měřeno jinde, než se kreslí**. Dělí se to na dvě sady.

  `StepFeedTests` berou tu čistou funkci (`Policy.stepFeedWindow`) výčtem, a to nad **kulatými
  rozměry, které nejsou z návrhu** — funkce nesmí na konkrétních číslech záležet a z literálů se
  dá přečíst aritmetika. Nejcennější tvrzení je, že **okno na hranici stropu nekmitá**: řady
  výšek přes 40 počtů řádků je neklesající, strop nepřeroste, a co jednou na stropu stojí, tam
  zůstane. Zvlášť se tvrdí, že obsah **přesně** na strop se ještě neroluje (proto `>`, ne `>=`)
  a že se pilulka `↓ N nových` nekreslí, když není co rolovat.

  `StepFeedWindowTests` proti tomu měří na **hostovaném okně**, aby ta čísla nebyla druhá pravda
  o kresbě. Rozměry se ověřují **rozdíly**, ne přepsanou aritmetikou: přírůstek na jeden řádek,
  přírůstek řezu na začátku ořezané osy a celý vzorec tím, že u nerolovaného výpisu je **okno
  stejně vysoké jako obsah**. Dvě věci, které se u toho našly a jinak by prošly:

  - **výšku řádku určovala ikona** — SF Symboly jednu výšku nemají, takže řádek se zadáním, které
    nedorazilo celé, měřil 17 bodů proti 15 u ostatních (a neznámý nástroj 16). Test proto jde
    přes **všechny druhy řádku a všechny symboly**, které výpis kreslí, a přes **pásmo šířek**
    (#236);
  - **nasazený rámec (`frame(height:)`) tvrzení vypnul** — měřidlo pak vrací to, co se nasadilo,
    takže rozejití s typografií není jak poznat (text se místo toho potichu ořízne). Výšku proto
    určuje sazba a konstanta o ní jen tvrdí, kolik měří.

  Ověřeno vloženou regresí z obou stran: pevná výška okna položí tři testy, výška řádku o bod
  vedle další dva.

  **Že `fittingSize` nesmí být přímo v `#expect`** je u toho vlastní past (#367 potřetí): v makru
  se čte dvakrát a `CGFloat` se u toho převádí, takže tvrzení padalo nad dvěma **na bit shodnými**
  patnáctkami. Hodnota se bere jednou do proměnné a tvrzení se porovnávají mezi sebou.
- **Že výpis doopravdy dojede na konec (#325)** — `StepFeedTailTests` hostuje `StepFeedView`
  v okně a čte polohu z `NSScrollView`, protože jinde není: do observable stavu se offset
  **nezapisuje** (#252). Ptá se u toho **tou samou funkcí, jakou se rozhoduje okno**
  (`Policy.stepFeedAtEnd` nad `StepFeedView.rowsInset`) — vlastní vzorec v testu by hlídal jiné
  číslo, než na kterém aplikace stojí. Test je tam proto, že to implementace **napoprvé neměla**:
  posun ve stejném průchodu, ve kterém řádek přibyl, SwiftUI zahodí (výpis zůstal 20 bodů od konce
  a nedojel ani po pěti kolech smyčky), takže se posouvá o průchod později. Čeká se **na jev se
  stropem** (#269), ne na pevný okamžik — posun přijde o kolo smyčky po sazbě řádku.

  **Druhou polovinu harness neuveze, a je to změřené, ne odhad**: „odrolovaný výpis se nesmí sám
  vrátit na konec“ se odzkoušet nedá, protože `WheelGesture` nad tímhle scrollem **neposune vůbec
  nic** (skončil na 1687, tedy tam, kde začal — offscreen okno bez aktivace) a
  `contentView.scroll(to:)` si SwiftUI přerovná zpátky. Je to tatáž mez jako u `onContinuousHover`
  v #358: testuje se proto **rozhodnutí** (`Policy.stepFeedReaction`, výčtem) a zbytek ověří člověk
  v pauze — patří to do popisu PR.
- **Strop živé osy a souhrn (#325)** — `TimelineLimitTests` a `TimelineDigestTests`. U stropu se
  hlídá, že se ořezává **začátek** (kdo se dívá do běžícího výpisu, kouká na konec), že
  `droppedEntries` roste průběžně a že se u uložení nesečte dvakrát, a hlavně to nejcennější:
  **ořez nezapomene, čím běh prošel** — kdyby se fáze počítaly průchodem přeživších událostí, dráha
  po třech stech krocích tvrdí, že session nenaběhla a že nálezy nenahlásila. Souhrn se u toho
  porovnává s **průchodem polem** (ta druhá pravda, kterou by mohl potichu opustit) nad osou, ve
  které je od každého druhu události jedna, a zvlášť se tvrdí, že načtená osa má stejný souhrn jako
  živá — jinak by tab po restartu kreslil jinou dráhu než před ním. K tomu dvě věci o posledním
  kroku: odpověď na něj se do souhrnu **propíše** (jinak by výpis tvrdil `běží…` nad krokem, který
  dávno odpověděl) a odpověď na **starší** krok posledním nehýbe.
- **Kolik výpis stojí (#325)** — `StepFeedMeasurement`, ruční (`TEST_RUNNER_PRISM_MEASURE=1`).
  Měří obojí, co se u #325 změnilo: složení dráhy z osy o 300 událostech (0,328 → **0,004 ms**;
  kontrolní strana je těch osm průchodů polem, přepsaných do měření, aby bylo poznat, že se ubralo
  a ne přepsalo — poučení z #275) a **cenu jedné události v otevřeném výpisu** v hostovaném okně
  (40,29 / 41,48 → **9,25 / 8,91 ms**). Série se u toho **střídají** (#274), protože drift sezení
  je větší než hledaný rozdíl, a příprava je mimo hodinky.
- **Surová session — přepis transcriptu (#327)** — pět suit, protože se to rozhoduje na pěti různých
  vrstvách a slít je do jedné by znamenalo mockovat disk kvůli čisté funkci:

  - `RawSessionWindowTests` a `RawSessionBodyTests` — **čisté funkce výčtem**: kde začíná okno
    (soubor pod stropem, přesně na stropu, 53 MB, prázdný i nesmyslně velký), co se zahodí ze
    začátku a **co se nezahodí** (okno bez jediného zakončení řádku, rozpůlený znak, nejvýš tři
    pokračovací bajty) a jak se ořeže jedna událost. V tom druhém je i ten změřený patologický případ
    **řádku delšího než celé okno**, `CRLF` počítaný **dvěma bajty** (jinak by ořez lezl nad strop)
    a tvrzení, že se řezem uprostřed řádku **neroztrhne znak** — rozpůlený kódový bod je v kopii
    vadné UTF-8.
  - `RawSessionStateTests` — který stav co nabídne, a hlavně **co nenabídne**: chybějící přepis
    nabízí **jedině `Zavřít`**, `Zkopírovat přepis` ani cestu nenabízí žádný chybový stav (odpověď je
    v hlášce, ne v tom, co se dá odsud vzít pryč) a `Zavřít` nabízí každý stav. Tři různá „přepis tu
    není“ se nesmí slít **ani nabídkou akcí**, takže je na to test a ne úvaha.
  - `TranscriptTranscriberTests` — proti **skutečnému** transcriptu z veřejného
    `ondrajodas/prism-review-sandbox` (`transcript/review-session.jsonl`, 18 řádků vybraných z běhu
    bajt po bajtu). Ty typy řádků ve `stream-json` **nejsou** — `queue-operation`, `attachment`,
    `last-prompt`, `toolUseResult` místo `tool_result_meta` —, takže vyrobená fixture by popisovala
    formát, který CLI nepíše. Tvrdí se, že vyleze próza, `thinking` i výstupy nástrojů (tedy to, co
    výpis kroků zahazuje), že **ani jeden** řádek se neztratí jako nečitelný, že odpověď nástroje
    doplní **tělo kroku** místo druhé události a že base64 obrázku se nevypíše ani v poznámce.

    **Odmítnutý nástroj má vlastní fixture, a je to ten nejcennější test celého issue**
    (`transcript/denied-tool.jsonl`). Původně tu stálo, že se odmítnutí ze skutečných dat sehnat
    nedá — „v žádném transcriptu není `non_execution_kind`“ —, jenže to se `grep`lo nad transcripty
    **z review, ve kterých žádné odmítnutí nebylo**, tedy nad soubory, ve kterých nebylo co psát.
    Copilot na #408 upozornil, že odznak `ODMÍTNUTO` pak nad skutečnými daty nevznikne nikdy; fixture
    se proto **vyrobila** (`claude -p` s `--disallowedTools 'Bash(wc:*)'`) a ukázala, že transcript
    nese `toolDenialKind` na **řádku**. Poučení, které přežije tenhle test: **nepřítomnost klíče
    v souborech, které tu situaci nemají, není doklad o formátu.**

    Vedle toho stojí dvě tvrzení, která ten odznak drží pochopitelný: tvar ze **streamu** se čte dál
    (inline JSONem — v souborech na disku není), a **`is_error` sám o sobě odmítnutí neznamená** —
    `grep` bez shody nesmí dostat odznak, jinak by znamenal „něco se nepovedlo“ místo „read-only režim
    zabral“ (#326).
  - `RawTranscriptSnapshotTests` — **skutečné soubory** v dočasné složce, protože právě o disk tu jde.
    Tři chybové stavy vzniknou tady (chybí / vadné UTF-8 / prázdný), okno se ověřuje na souboru přes
    strop (nula nečitelných řádků, tedy zarovnání zabralo) a zvlášť na tom **jednom řádku delším než
    okno**: musí z něj zbyt jedna nečitelná událost, ne prázdno. A od #408 na **okně zarovnaném
    přesně na hranici řádku** — ten stav se dá spočítat (řádky po 128 bajtech padnou na hranici 4 MB
    vždycky) a bez sondy v podobě bajtu před oknem se v něm ztrácela první událost.
  - `AppStoreRawSessionTests` — fake `TranscriptReading`. Nejcennější jsou tvrzení o tom, co se
    **nestalo**: nečitelný přepis se neslije s chybějícím (`do`/`catch`, ne `try?` — ten by obě
    odpovědi zplošťoval na `nil`), tik přírůstku **okno nečte znovu**, `Načíst znovu` po zavření
    sheetu nečte nic, přepis cizí session se neukáže pod jiným titulkem a **pomalejší čtení
    nepřepíše novější snímek téže session** (od #408, kde se ukázalo, že na to cíl sám nestačí — dvě
    čtení téhož cíle rozliší jedině generace). Plus že zavření snímek zahodí — jsou to megabajty.

  K tomu dvě věci mimo tu pětici. `RawSessionScriptTests` tvrdí, že vysázený a zkopírovaný přepis
  jsou **jedna pravda** (`attributed(…).string == plain(…)`) — chyba, kterou zelené testy neukázaly
  a render ano: první podoba měla mezery mezi kusy hlavičky jen v kopii, takže se vysázená slepila do
  `23:13:36Bashgh pr view 412`. A **že se barva do textu doopravdy dostane**, ne jen že je v paletě
  (#393): u každého kusu je `.foregroundColor`, tělo má paletový `ink2` a odsazení je `headIndent`
  odstavce. Stráž sazby se testuje **vlastní funkcí** (`TranscriptTextView.needsTypesetting`), protože
  `NSViewRepresentableContext` se v testu nepostaví — tik přírůstku přesazení nevyvolá, nový snímek
  a přepnutí režimu ano.

  A `SingleWayOutTests` má nový výčet: **surová session umí jen číst.** Deset souborů, ani jeden
  z nich nezná publisher, payload, API, podproces — a nezapisuje do souboru, protože transcript leží
  mimo cache (tvrdá podmínka č. 3). Je to tatáž konstrukce jako u zadání pro agenta a ze stejného
  důvodu: nová obrazovka nad daty běhu je zrovna to místo, kde by druhá cesta ven vznikla, aniž by
  o ní kdo mluvil.
- **Velikost sheetu s přepisem (#327 follow-up)** — dvě suity, protože se to rozhoduje na dvou
  vrstvách a jedna z nich není naše.

  `RawSessionSheetSizeTests` je `Policy` výčtem: co se vezme bez uložené hodnoty, co s ní, co
  s nesmyslem (nula, záporné, `NaN`, `∞`), ořez o podlahu a o okraje obrazovky (i na displeji, kam se
  podlaha nevejde, a na širokém a nízkém, kde se ořezává jen výška) a **kdy se ukládá**: velikost, se
  kterou se sheet otevřel, se neukládá, natažená ano, a stažení až **na podlahu** taky (podlaha sama
  nesmysl není).

  `RawSessionSheetSizingTests` měří **skutečné okno sheetu** v hostovaném okně — tady se totiž
  rozhoduje SwiftUI a z dokumentace se to přečíst nedalo. Tvrdí tři věci a **všechny tři jsou ověřené
  vloženou regresí**:

  1. sheet má `.resizable` a `contentMinSize` z `Policy` — bez `presentationSizing(.fitted)` má
     `styleMask` 65 a `contentMinSize` nulový;
  2. otevře se v **ideální** šířce — bez `.fitted` je široký jako `minWidth`, tedy 720 místo 1 180
     (a nerozhoduje o tom okno za ním, změřeno i nad oknem 2 000 bodů);
  3. **otevření bez tažení neuloží nic** — to je ten test, který tvrdí, že se něco nestalo. Sheet se
     rozvrhuje **dvakrát** a v prvním průchodu má podlahu, takže bez odmlky (`resizeSettle`) by se
     uložilo 720 × 420 a od druhého otevření by se sheet otevíral nejmenší možný. S vrácenou regresí
     padne přesně na tom.

  Dvě věci, na které se u toho naráží. Tažení se napodobuje `setFrame`em na okně sheetu — přesně to
  dělá AppKit při tahání okrajem, a **syntetické myší události se k tomu nedostanou** (tatáž
  zkušenost jako u hoveru, #358). A `@AppStorage` dostane **vlastní suitu** přes
  `defaultAppStorage(_:)` — nasazuje se **na obsah sheetu**, ne na hostitele, protože sheet je vlastní
  prezentace; suitu přitom nesmí mazat ta instance, která ji obsluhuje (odebrala by si ji
  z prohledávaného seznamu a hodnoty by nedržela).

  **Vlastní suita je u `@AppStorage` v testu tvrdá podmínka, a stálo to jeden červený běh**:
  testovací host má bundle ID **hlavní instance** — slotová přípona vzniká až v `bin/run.sh`, ne při
  buildu —, takže zápis z testu jde do nastavení, které uživatel doopravdy používá. Poznalo se to
  dvěma způsoby naráz: velikost uložená v jednom běhu shodila v tom příštím test „otevře se v ideální
  šířce“ (v nastavení ležela ta menší), a `SlotCleanupTests` nahlásily, že se změnil **plist hlavní
  instance** — to je přesně to tvrzení, na které jsou (#398). Je to obecnější než tenhle sheet: každý
  test, který se dotkne `@AppStorage`, píše do domény hlavní instance, dokud si o vlastní suitu
  neřekne.

  **Čeká se na hodnotu, ne na „něco se zapsalo“** (#269): mezi průchody rozvržení může v nastavení
  chvíli ležet jiné číslo, takže „> 0“ test uzavře dřív, než se tažení usadí — a padá pak na hodnotě,
  která se o chvíli později srovná. Stálo to jedno kolo.
- **Jak surová session vypadá (#327)** — `RawSessionRenderProbe`, ruční
  (`TEST_RUNNER_PRISM_MEASURE=1` + `TEST_RUNNER_PRISM_RENDER_DIR`). Existuje proto, že **k tabu
  `Průběh` v běžícím okně vede jedině klik** a aplikaci sonda ovládat nesmí; tohle je jediná cesta
  podívat se na tu obrazovku bez skutečné session na disku. Rendruje přepis v obou režimech (a je
  v něm od každého druhu události jedna, i obě další přiznání zkrácení) a **všech pět** podob bez
  přepisu, aby se dalo porovnat, že se od sebe poznají. Přírůstek se u chybových stavů schválně
  nepředává — v aplikaci o něm rozhoduje store, takže sonda, která by ho dodala, by kreslila
  obrazovku, jaká nevznikne.
- **Kolik surová session stojí (#327)** — `RawSessionMeasurement`, ruční. Měří **otevření**
  (84 / 331 / **312 ms** na 1 / 8 / 53 MB, tedy konstantní ve velikosti souboru — to je to hlavní
  tvrzení) a **sazbu** zvlášť, aby se nezaměnilo jedno za druhé (#274). Třetí test je **rozpad té
  ceny**, a ten je poučnější než čísla: rozbor JSONu stojí 6,9 ms, dělení textu na řádky 216 ms.
  Bez rozpadu se optimalizovalo naslepo — ořez těla po znacích vypadal jako ta drahá věc a jeho
  odstranění nezměnilo **nic** (627 → 627 ms).

  Od roztahovatelného sheetu měří ještě dvě věci. **Cenu jednoho tažení** (`resizeCost`) po té cestě,
  kterou to doopravdy jde (#275) — změna šířky → rozvržení → `updateNSView` se stráží → přelámání
  textu → kresba výřezu —, a vyjde **2,61 ms na krok** nad 1,55 milionu znaků; kdyby stráž šířku
  v klíči měla, byl by v každém kroku `attributed` + `setAttributedString`, tedy 18,5 ms.
  A **zalamování podle šířky** (`wrappingByWidth`), ze kterého je výchozí šířka sheetu: nad skutečným
  transcriptem ubude ze 720 na 1 180 bodů 15 % řádků sazby, dál jednotky procent. Počítá se
  aritmeticky ze šířky znaku mono písma, ne layout managerem — nad 1,5 milionu znaků by sazba přes
  pásmo šířek byla desítky sekund a rozhodují dlouhé řádky výstupu, které jsou v mono.
- **Věty dráhy (#242)** — `ReviewerLaneText` rozlišuje **tři** doběhlé konce (nahlásilo nálezy /
  nahlásilo nulu / nenahlásilo nic) a test hlídá, že se u toho třetího **nikde neslíbí čisto**.
  Plus že slova stavů jsou různá (`spadlo` ≠ `nedoběhlo`, `nespuštěno` ≠ `ve frontě`, u fází
  `neví se` ≠ `nedošlo na ni`) a že se v běžícím kroku zkracuje cesta
  o pracovní strom. A že **stav fáze má jiné slovo než stav dráhy** (nález Copilota): čtečka
  obrazovky u chipu vidí jen popisek, takže se stavem dráhy by u všech fází přečetla „doběhlo“ —
  i nad tou, na kterou nedošlo.
- **Panel s mým review se rozloží sám (#242)** — a je to ten druh věci, který se rozbije potichu:
  poznámka do těla review přidaná z diffu spadne do panelu, takže se složený panel musí rozložit,
  jinak text zmizí za proužek na hraně okna. Testuje se ve store (proto se tam ta dvě pole
  přestěhovala z `@State`) a spolu s tím to, co se stát **nesmí** — převzetí nálezu na řádku
  v diffu panel nerozloží, protože komentář je vidět hned pod řádkem. Ověřeno vložením regrese.

  **Od #294 k tomu patří tři testy o tabech bez panelu**, a dva z nich tvrdí, že se něco
  **NE**stalo: rozbalený panel **přežije** průchod `Nálezy` a `Průběhem` (skrytí je věc pohledu, ne
  uložený stav) a složený se přepnutím tabu **nerozloží**. Třetí je ta viditelná půlka: poznámka
  z tabu bez panelu si **přepne tab** na `Přehled`, kdežto z `Změněných souborů` tab nemění —
  jinak by převzetí v diffu vyhodilo člověka z kódu. K tomu jeden test na paletu: v tabu bez panelu
  položku `Složit panel` **nenabízí**, ale pohled na diff nabízí dál, takže nevypadla celá skupina.
- **Skok na nález — cíl existuje v seznamu (#187)** — dvojice testů, která hlídá chybu z #157:
  kotva na řádek uprostřed bloku se musí přeložit na **něco, co v seznamu je**, a to v obou
  pohledech; druhý test naopak tvrdí, že **bez** překladu se netrefí. Z té dvojice je pak poznat,
  jestli spadlo zadání, nebo kód. Plus že se řádek mimo blok mapuje sám na sebe (jinak by přestal
  fungovat skok na soubor) a že blok nezapomene ani jeden řádek, který spolkl.

  **Od #446 k tomu patří soubor s poznámkou `git`u.** Ta ve split pohledu zůstane samostatným
  `.line` a **rozděluje** kolem sebe bloky, takže je to jediné místo v diffu, kde slití není úplné
  — a kdyby ho překlad nepokrýval, skok na řádek za ní by mířil na id, které v seznamu není.
- **Co z diffu doopravdy dojde ke kreslení (#446)** — `DiffRenderedRowsTests`. Tvrdí se to
  **nad daty i nad zdrojáky**, protože každá polovina sama o sobě jde obejít.

  Nad daty: seznam se skládá **týmž výrazem, jakým se plní `ForEach`**
  (`rows(of:layout:)` + `blocked(_:)`/`blockedPairs(_:)`) nad **pěti skutečnými diffy** z fixtures
  v obou pohledech. `.pair` se ke kreslení nedostane **nikdy** — ani mezi bublinami, které blok
  rozetnou, tedy zrovna tam, kde by osamocená dvojice mohla zbýt. `.line` **jednou**: poznámka
  `git`u (`\ No newline at end of file`) ve split pohledu, protože ji `paired(_:)` nepáruje
  a `blockedPairs(_:)` slévá jen dvojice. Ve stažených diffech poznámka není, takže je na ni
  vlastní soubor **a vlastní test o tom, že ta nula výš je vlastnost fixtures, ne kódu**.

  **Kontrola měřidla** je tam dvakrát: v mezikroku (`rows(of:layout: .split)`) dvojice **být
  musí**, jinak by nula neznamenala nic, a test s bublinou tvrdí, že se blok doopravdy rozťal.

  Nad zdrojáky (tatáž konstrukce jako `SingleWayOutTests`): že `DiffRowView` plní **jediný
  volající jediným výrazem** — bez toho by tvrzení nad daty platila o funkci, kterou si testy
  zavolaly samy —, že `DiffPairView` v aplikaci **není** a že nedosažitelná větev `.pair` kreslí
  **týž blok**, ne prázdno. **Ověřeno vloženou regresí** (`EmptyView()` do té větve spadne)
  a renderem: obě větve daly bajt po bajtu tentýž PNG.
- **`Policy` — procházení nálezů (#187)** — vyčerpávajícím výčtem: bez kurzoru se jde jen
  dopředu, šipky drží pořadí diffu, na kraji není kam, odmítnutý nález se přeskočí a skupina
  bez platného nálezu vypadne celá. Tři případy, kvůli kterým to celé vzniklo: **nález bez místa
  se počítá zvlášť** (jinak „1 z 1“ tvrdí hotovo nad PR se dvěma nálezy v panelu), **hotovo
  znamená projitá všechna místa**, ne konec seznamu, a **ztracené místo pod kurzorem shodí jen
  pozici** — po změně seznamu se nesmí ukázat „4 ze 3“.
- **`Policy.changes` a `VisitLedger` (#173)** — „co přibylo od minule“ ve dvou vrstvách.
  `Policy` vyčerpávajícím výčtem: **bez značky se neukáže nic** (jinak by se u prvního otevření
  vypsala celá historie), položka v tutéž sekundu se nepočítá (ostré porovnání), událost bez
  data se zahodí, force-push má vlastní pole, moje komentáře nejsou novinka, odpověď ve vlákně
  ano, neodeslané cizí review ne — a všechno chronologicky. `VisitLedger` na to, že návštěva
  přežije novou instanci nad týmiž předvolbami, že se návštěvy různých PR nepletou, že zápis
  **zahodí, co se přežilo** (a co je těsně pod hranicí, nechá), a že **rozbitá hodnota se čte
  jako prázdno, ne jako pád** — včetně toho, že se přes ni dá zapsat, jinak by se takový stav
  nedal opravit. A `AppStore` na **posunutou hlavu**: že se pozná i tehdy, když časová osa nic
  nedá (rebase), že se nezměněná hlava za posun nevydává a že se bez znalosti té minulé netvrdí
  nic — poslední z nich odhalil past s dvojitým optionalem, kterou čtení kódu minulo.
- **Odrážky a řada ovládání „od minule“ (#284)** — tři sady, každá na něco jiného.

  `SinceLastVisitLineTests` na **sazbu odrážek po částech**: že je tučný počet commitů a verdikt
  review, že je autor ztlumený a sha zkrácená na sedm znaků v kapsli, a hlavně dvě věci, které se
  dají pokazit potichu — **commity od víc lidí jméno neuvádějí** (jinak by „od odinuv“ tvrdilo něco,
  co v datech není) a **věta události se bere z `TimelineEventRow`**, ne píše podruhé. Plus pořadí
  odrážek a prázdno bez změn, protože pruh se nesmí ukázat prázdný.

  `SinceLastVisitActionsTests` na **to, jestli se řada vejde**, výčtem přes pásmo šířek × všech osm
  kombinací toho, co v ní může stát. Vzniklo z měření: `ViewThatFits` na tuhle řadu **nestačí**,
  protože odznak i popisky tlačítek jsou vodorovně pružné a ve zúžené řadě se radši zkrátí, než by
  nahlásily, že se nevejdou. A co je horší, **`OverflowProbe` tu chybu nechytá** — ověřeno vloženou
  regresí: s pevnou řadou zůstala `OverviewWidthTests` zelená, protože zkrácený popisek nikam
  nepřeteče, jen v pruhu stojí `Pust…`. Proto je vedle měření přetečení ještě tenhle výčet nad
  `SinceLastVisitView.fits(_:in:)`; obojí je potřeba, jsou to dvě různé chyby.

  `IncrementalDiffBarLayoutTests` na totéž u lišty nad rozsahovým diffem — a k tomu na to, že
  **cesta ven přežije i nejužší tab**: lišta je jediné místo, odkud se z rozsahu vrátí na celý
  diff, takže tlačítko musí ustupovat poslední.

  **Obě sady mají navíc jeden test, který sahá na kresbu** (`NSHostingView.fittingSize`): spočítaná
  šířka nesmí být menší než nakreslená. Je to jediné tvrzení, které nestojí na dvou stranách téhož
  výpočtu — zbytek porovnává `fits` proti `width(of:)`, takže **špatně změřený font by v něm
  prošel**. A přesně to se stalo: `TextWidth.miniButton` měřil regularem, kdežto plné tlačítko se
  kreslí mediumem, takže `Pustit review znovu` vycházelo o tři body užší (126 proti 129). Našel to
  Copilot na #284; od té doby si řez bere obojí z `MiniButtonStyle.labelFont`. Regrese ověřena
  vložením — po návratu k regularu ten jeden test spadne a ostatní zůstanou zelené.
- **`Policy.incrementalDiff` (#284)** — kdy se `Ukázat, co přibylo` nabídne. Vyčerpávajícím
  výčtem, protože každý z důvodů, proč tlačítko nemá být, se dá zrušit jedním znakem v podmínce.
  **Nejcennější jsou záporné**: bez viděné hlavy, bez dnešní hlavy, při shodě obou a **po přepsané
  historii** se nenabízí nic — a `rewroteHistory: nil` (nenačtená časová osa) se chová jako
  „přepsala“. Poslední dva mají číslo: po force pushi vrátí trojtečkový `compare` **víc než celý
  diff PR** (změřeno na `cli/cli#14062`: 102 kB ve 22 souborech proti 15 kB ve třech), tedy přesně
  to, co tlačítko slíbit nesmí.
- **Rozsahový diff ve store (#284)** — `AppStoreIncrementalDiffTests`: že se ptáme na **viděnou
  hlavu proti dnešní** (obráceně by `compare` vrátil, co z větve zmizelo), že se načtený rozsah
  drží a nestahuje podruhé, že **po selhání se zkusit znovu smí** (jinak tlačítko `Zkusit znovu`
  nic neudělá) a že **celý diff zůstane netknutý** — je to to, proti čemu se píše review. Dva testy
  tvrdí, že se něco NEstalo: bez načtené konverzace a bez viděné hlavy se **nestáhne nic**.
- **Zastaralé nálezy z jednoho zdroje (#284)** — `AppStoreStaleFindingsTests`: hlavička nad taby
  a odznak `nálezy zastaraly` v pruhu čtou tentýž `AppStore.staleFindings(for:)`. Hranice mezi nimi
  je `hasFindings`: **čisté review proti staršímu commitu je pořád zastaralé** (hlavička o něm mluvit
  má), ale odznak se u něj nerozsvítí, protože žádné nálezy nejsou. A bez záznamu review ani bez
  načteného detailu se netvrdí nic.
- **`ToolAttempt`** — zkrácení proti pracovnímu stromu: relativní cesta, zahozené
  `cd <strom> &&`, cesta uvnitř příkazu, a že se bez stromu nic nemění. Pozor na past
  v testu: skutečný nástroj dostane cestu **nekódovanou**, takže `URL.path()` v přípravě
  vstupu ověřuje něco, co nikdy nevznikne.
- **`AppStore` — průběh** — pořadí událostí včetně konce běhu, že osa přežije doběhnutí, že nový
  běh začíná načisto a **že se na disk uloží tatáž osa, jakou má store** (#308; do té doby o obsahu
  souboru rozhodoval závod, takže tam končilo `[ve frontě]` nebo nic). Plus detekce záměny skillu:
  načtený jiný, načtený správný a běh bez skillu (ten záměna není).

  Nad úklidem po tiku (`keepFresh()` bez toho PR) stojí dvě tvrzení a **obojí je ověřené vloženou
  regresí**, u které je vidět, že padá **na tvrzení, ne na timeoutu**:
  - **pustí se živá kopie, ne osa** — `reviewTimelines[pr]` je pryč, ale `timelines(for:)` odpoví
    z uloženého záznamu a jsou to **tytéž události**. To porovnání celé osy je to hlavní: chytá
    zkrácený rozjezd i konec dopočítaný z jiných hodin, tedy přesně tvar pádu z #308. Do #308 tady
    stálo, že po tiku není osa žádná;
  - **běžícímu review tik osu nesebere a další události do ní pokračují** — tohle je to tvrzení,
    že se něco NEstalo: nevznikla druhá osa ani nová. Krok nad kódem dorazí **až po tiku**
    (`FakeReviewRunner(progressAfterRelease:)`, přidané u #308 — bez toho fake hlásí všechen
    průběh dřív, než se běh dá pozdržet), takže je to zrovna ta „pozdní událost“ z #308. Bez
    ochrany `reviewTasks[$0.key] != nil` v `forget` spadne na třech `#expect`ech a v ose zbyde
    `[tool(Read), finished]`, tedy **osa začínající uprostřed běhu** — přesně to tiché zkrácení,
    kvůli kterému se ta otázka řešila.

  `sessionID` se v tom porovnání **vynechává**, a je to vlastnost fake: `FakeReviewRunner` hlásí
  jednu hodnotu v události průběhu a jinou v souhrnu session, takže by se porovnávala fake, ne
  aplikace. Ve skutečném běhu je to jedna hodnota z jedné session.
- **`FindingRow`** — skládání textů (`—` u nálezu bez místa, samotný soubor bez řádku,
  `file:line` bez locale u velkých čísel), blokující příznak, výchozí pořadí z `Policy`
  a unikátní identita řádků. Plus **nápověda k místu**: celá cesta u nálezu s řádkem
  i bez něj a vysvětlující věta tam, kde je ve sloupci `—`. Šířky sloupců se
  neunit-testují — `Table` je AppKit tabulka, takže offscreen render z ní udělá žlutý
  placeholder stejně jako z `Listu`; kontroluje se na běžící aplikaci.
- **Bubliny nálezů** — že bublina visí pod svým řádkem, že nález mimo diff a nález bez
  řádku skončí u hlavičky souboru (a v pořadí podle čísla řádku), že se po rozbalení
  kontextu bublina k řádku přesune, že dva reviewery na jednom řádku dají jednu bublinu
  s `agreement == 2` a že se nálezy cizích souborů nepřipletou.
- **`SyntaxHighlighter`** — každý test ověřuje i **invariant**, že spojení run dá zpátky
  původní řádek. Pokrývá komentáře (i mřížku jen tam, kde ji jazyk má), řetězce
  s escapovanou uvozovkou i neuzavřené, komentář v řetězci a naopak, klíčová slova jen
  jako celá slova, čísla mimo jména, proměnné se sigilem i ve složených závorkách
  a diakritiku. `Language` má tabulkové testy na detekci z přípony i ze jména souboru.
- **`SyntaxRunCache` (#224)** — zapamatované obarvení se dá pokazit dvěma způsoby a oba jsou
  potichu. **Cizí obarvení**: `# poznámka` je v shellu komentář a ve Swiftu obyčejný text, takže
  klíč bez jazyka by obarvil jeden soubor podle pravidel druhého — test se ptá na oba jazyky
  a pak zpátky na první. **Růst bez hranice**: obě meze (počet řádků i rozpočet na jejich délku)
  se přesypou stovkou řádků a hlídá se, že `count` strop nepřekročí a že po vyprázdnění vyjde
  týž řádek stejně. K tomu **řádek delší než celý rozpočet**: musí se obarvit, ale **nezapamatovat**
  — jinak by cache po jeho vložení stála nad mezí a při dalším zápisu by kvůli němu zahodila
  všechno ostatní. K tomu je tam rovnost s `SyntaxHighlighter.scan` (cache nesmí nic změnit)
  a souběžný běh padesáti úloh nad jednou cachí — zámek se tvrdit nedá, ale rozsypaný souběh
  je vidět. **Obojí ověřeno vloženou regresí**: klíč bez jazyka shodí test na jazyky, vyndaná
  kontrola meze shodí test na strop (`count` vyjde 200 místo 10).
- **`AppStore` — diff** — proti fake gateway: načtení, cache podle `updatedAt`, opakování
  po selhání a zahození diffu PR, které zmizelo ze seznamu.
- **`AppStore` — zahození nálezů** — proti **skutečnému** `ReviewStore`: že to zmizí
  z panelu, z řádku i z disku a přežije restart, že další běh začíná načisto, že druhé
  zmáčknutí nic nerozbije, že starší záznamy zůstanou a že se na automatickém repu review
  pustí samo, kdežto na manuálním ne.
- **Odmítnutí nálezů (#113)** — čtyři vrstvy. **Klíč** na to, co se nesmí rozejít: tentýž nález
  z druhého běhu se spáruje i po **přeformulovaném `short_summary`** a po překladu, kdežto nález
  druhého revieweera na tomtéž řádku ne. **`Policy`** na to, že odmítnutý blokující nález pustí
  `approve`, kdežto `droppedFindings > 0` dál dává `nil` (odmítnutí mluví o nálezu, který znám),
  že odmítnutí u jednoho revieweera nesundá nález druhého, že odznak `2×` spadne na `1×` a že
  odmítnuté jdou v řazení **naspod, i když blokují**. **`ReviewState`** na to, že odmítnutí všeho
  **není `clean`**, ale `dismissed`, a že zastaralost i timeout to přebíjejí.

  Round-trip `ReviewRecord` s odmítnutími i bez nich — **starší soubor bez toho klíče se musí
  načíst** (inline JSON, ne jen `roundTrip`), a mapa musí v JSONu vyjít jako **objekt**.

  `ReviewStore` a `AppStore` proti **skutečné** dočasné složce, protože rozhoduje disk: odmítnutí
  přežije restart, `Vrátit` ho zruší, sedne na commit, ke kterému nález patří, a bez uloženého
  záznamu je to **chyba**, ne prázdný záznam. Nejdůležitější test celého issue je, že **opakované
  review týmž skillem odmítnutí nezahodí** — `replace(_:)` je přesně to místo, kde by se ztratilo;
  ověřeno dočasně vloženou regresí, po které spadly tři testy na třech vrstvách. K tomu, že
  odmítnutí **nevyjme převzatý komentář** z draftu a že selhání zápisu je vidět.
- **Rozbalení bublin nálezů (#185)** — dvě vrstvy. `Policy` výčtem: blokující rozbalený, ostatní
  sbalené (včetně `PLAUSIBLE` v blokující kategorii), sada z konfigurace, jeden blokující ve
  skupině rozbalí celou. K tomu tři testy na to, co se stát **nemá**: shoda `2×` sama nerozbaluje,
  odmítnutá skupina se nerozbalí **ani po překliknutí** a odmítnutí blokujícího nálezu bublinu
  odpřišpendlí. A klíč: je to **místo**, takže se nemění s textem nálezů na něm ani s odmítnutím
  jednoho z nich, kdežto dva nálezy **bez řádku** mají klíč každý svůj (jinak by se rozbalením
  jednoho otevřely oba) a s klíčem místa se nesejdou.

  `AppStore` na to, že se drží **odchylka** (tatáž hodnota v množině sbalí blokující i rozbalí
  ostatní), že prázdná množina z mapy zmizí a že překliknutí zmizelého PR se uklidí. Nejcennější
  je test, že **skok bublinu nikdy nesbalí**: `revealFinding` implementovaný jako obyčejné
  překliknutí by u blokujícího nálezu zavřel právě to, na co se kliklo. Ověřeno vloženou regresí —
  po vyndané stráži spadlo devět testů na obou vrstvách.

  Jak to **vypadá**, se ověřilo offscreen renderem přes `NSHostingView` (blok kódu je
  `NSViewRepresentable`, takže `ImageRenderer` nestačí) přes pásmo šířek 460–1200 v obou
  pohledech. Našlo to dvě věci, které se z kódu nepoznaly: ořezaný odznak (`mi…` místo
  `mimo diff`) a náhled textu ustupující verdiktu — odsud `layoutPriority` na odznacích
  a na náhledu.
- **Akce u nálezu jako tlačítka (#283)** — `FindingActionButtonTests`. Vzhled se dá otestovat jen
  přes čísla a texty, takže se testuje **to, co se dá zjednodušit potichu**: rozměry `.mini` proti
  CSS návrhu (font 11,5, padding 3 × 9, poloměr 6, mezera 7, obtažení 1), že se obtažení
  **připočítává k odsazení** (CSS ho má vně paddingu, SwiftUI ho kreslí dovnitř) a že tlačítko vyjde
  na **25 bodů** — tedy na výšku, kterou návrh dává i vstupu do palety v hlavičce.

  K tomu barvy z palety a jeden test proti záměně, která se ve světlém režimu **neprojeví**: text
  plného tlačítka je `Palette.surface` (`--panel`), takže se rozsvítí v obou vzhledech
  (`performAsCurrentDrawingAppearance`) a ověří se, že ve světlém je bílý a v tmavém ne. Zadrátovaná
  `.white` by ve světlém režimu vypadala správně.
- **Barva akcí v tabulce nálezů (#298)** — `AccentLinkButtonTests`. Že akce **není systémová modrá**,
  se dojmem neuhlídá, takže se měří dvojím tvrzením: barva se rovná `Palette.accent` a zároveň se
  **nerovná `NSColor.linkColor`**. Samotná rovnost s tokenem by po posunu palety k modré pořád
  platila a rozpor by zmizel z dohledu; ověřeno vloženou regresí — po dosazení `.linkColor` zpátky
  padnou obě tvrzení v obou režimech.

  Kontrast se měří na **všech třech podkladech, na které akce může padnout** (práh WCAG AA 4,5,
  protože akce je `.caption`): plocha řádku 6,14 / 5,64, **podbarvený živý řádek** procházení
  (`accentWeak` složený nad plochou, tedy akcent na akcentu) 5,30 / 4,70 a stavový řádek
  5,82 / 5,33 — světlý / tmavý. Systémová modrá tam měla 5,26 / 4,54 / 4,99 a 6,51 / 5,43 / 6,16,
  takže **v tmavém režimu je to výměna**, ne zlepšení; zapsaná, protože rezerva nad AA zůstává.

  Zvlášť stojí `Vrátit` na **odmítnutém** řádku: ten se celý ztlumí na `dismissedOpacity` (0,52,
  `.frow.done` z návrhu), takže kontrast klesá na 2,35 / 2,40. Práh je proto 2,2 a je to hlídání
  **zhoršení**, ne čitelnosti — akci ze ztlumení vyjmout nelze (#113), a kdyby se akcent posunul
  blíž k ploše, `Vrátit` by zmizel právě tam a nikde jinde. Krytí si test bere **z view**
  (`FindingTableRowView.dismissedOpacity`), ne z vlastní konstanty — jinak by po první změně měřil
  jiný řádek, než jaký se kreslí.

  Dvě pasti měřidla, obě chycené za běhu: **dynamické `NSColor` se rozsvítí až při čtení**, takže
  `Palette.accent` přečtený mimo `performAsCurrentDrawingAppearance` vyjde v režimu **stroje** —
  sada kvůli tomu nejdřív tvrdila, že akce nemá barvu akcentu (vlevo světlá `#5B47E0`, vpravo tmavá
  `#8B7CFF` z nastavení systému). A `Color.accentColor` **za `.tint()` nejde**, takže odznak `2×`
  zůstával systémově modrý i pod `.tint(Palette.accent)` z kořene okna; `.foregroundStyle(.tint)`
  naopak jde. Doloženo renderem, kde v jednom obrázku stálo obojí vedle sebe — a je to celý důvod,
  proč #309 sáhlo rovnou na token, ne na tint.
- **Barva stavů u nálezu (#309)** — `MintTokenTests`. Ptá se na dvě různé věci a měří je dvěma
  mírami: **ΔE2000** na „nesplynul mint s něčím, co v okně už něco znamená“ (proti `ok` 16,6 světlá
  / 21,1 tmavá, proti `stale` 37,9 / 39,4, proti akcentu 39,7 / 43,9) a **WCAG** na „dá se to
  přečíst“ (na ploše řádku 4,95 / 9,90, na `chrome` 4,70 / 9,35, na podbarveném živém řádku 4,29 /
  8,23; na vlastní kapsli odznaku 4,06 / 7,42).

  **Prahy nejsou všude 4,5, a je to zapsané u každé výjimky.** Živý řádek (4,0) stahuje pod AA
  celou rodinu — `ok` tam má 4,40, `find` 4,25 —, takže vyjmout z toho mint by znamenalo jeden
  odznak, který svítí jinak než ostatní. Kapsle (3,4) je tatáž úvaha: `color-mix(… 15 %,
  transparent)` z návrhu ztmavuje text u **všech** odznaků. Hlídá se tam **zhoršení**, ne AA.

  Tři věci, které sada tvrdí a bez kterých by šlo #309 potichu zrušit: že odznak u nálezu je mint
  a **není** akcent (ověřeno vloženou regresí — s `Palette.accent` v `FindingBadgeAppearance` padá
  v obou režimech), že `běží` **zůstalo** akcentem (mint je pro konstatování, ne pro každý stav)
  a že pruh rozsahu v diffu drží akcent i po `.opacity()` **a po převodu na `NSColor`**, kterým si
  ho bere `DiffTextView` — kdyby se na té cestě ztratila dynamika, pruh by v jednom režimu zůstal
  z toho druhého a poznalo by se to jedině tažením myší přes diff.

  **Porovnává se přes `Measured`, ne syrové `NSColor`**: `NSColor(dynamickáBarva)` vrací katalogovou
  barvu, která se sobě samé nerovná ani po vyhodnocení v témže režimu, takže bez převodu do sRGB
  padá sada na typu obálky, ne na barvě.
- **Sonda barvy akcí a stavů (#298, rozšířeno #309)** — `FindingActionColourProbe`, gated
  `PRISM_MEASURE`. Nic netvrdí, vyrendruje **tabulku, dvě bubliny, stavový řádek a odznaky stavu na
  jedno plátno** v obou režimech, protože „pozná se stav od akce“ je otázka na vzhled a dva snímky
  pod sebou se porovnávají po paměti. `NSHostingView`, ne `ImageRenderer`: tabulka je ve `ScrollView`u
  (ten se offscreen nevykreslí) a odkaz by vyšel jako žlutý placeholder.

  Sonda musí nést **`.tint(Palette.accent)`**, protože ho skutečné okno má na kořeni (`ContentView`).
  A převzatý nález musí mít **jediného revieweera**: u shody `2×` se `adoption(of:)` nekreslí vůbec,
  takže odznak by v renderu chyběl. Obojí se ukázalo až na prvním obrázku.

  **Druhá bublina je od #309 a musí mít `toggle`**: `2×` sedí ve značce nad obsahem a ta se kreslí
  jen tam, kde se bublina dá sbalit (`showsMark`) — bez uzávěru vyjde bublina bez odznaku a sonda
  mlčky neukáže zrovna to místo, na které se ptá. Skupina je proto dvojice se shodou a **obě její
  položky jsou převzaté**, aby v jednom obrázku stálo `2×`, `✓ v mém review` i akcentové tlačítko.

  Popisky odmítnutí mají **dvě podoby** a nesmí splynout: `actionLabel` na tlačítko (velké písmeno,
  každý důvod jiný) a `label` do odznaku (malé písmeno, přídavné jméno). Test tvrdí obojí i to, že
  se ty dvě hodnoty u žádného důvodu nerovnají — kdyby se `label` přejmenoval na popisek z návrhu,
  odznak odmítnutého nálezu by řekl akci. Ověřeno **vloženou regresí** ve dvou podobách: `.white`
  místo palety (spadly dva testy) a `label` na místě `actionLabel` (spadly dva).

  Jak to **vypadá**, se ověřilo renderem vedle vyrenderovaného návrhu, ne kódem — a našlo to dvě
  věci: tlačítko **20 bodů proti 25** v návrhu (chybějící `line-height` a obtažení) a to, že věta
  „GitHub tady řádkový komentář nepřijme“ jako ocas za tlačítkem shodí celou řadu do sloupce i na
  širokém okně. Pásmo šířek 300–482 pak ukázalo všechny tři varianty zalomení.
- **Notifikace (#88)** — proti `FakeNotificationCenter`, takže se **nic nedoručuje**. To hlavní
  není text notifikace, ale dvě věci, které se dají pokazit tiše: že se **odmítnuté oprávnění
  dá poznat** (a úspěch tu hlášku smaže) a že se **kliknutí neztratí, když dorazí dřív**, než
  si ho má kdo vyzvednout — na tom stojí klik na notifikaci, která aplikaci teprve spustila.
  K tomu klik na PR mimo seznam, který neotevře nic, a doručení bez centra, které si nic
  nezapíše. Čeká se přes `Tests/Support/TestWaiting.swift` (#296), ne neomezeným `Task.yield()`
  spinem: ten by běžel na `MainActoru` bez horní hranice, což položilo suitu u #68.

  **Tvrzení o kliku jsou od #409 o `activeTab` a `openTabs`, ne o `selection`** — a je to
  zajímavější polovina toho issue než samotná oprava. Čtyři testy tady totiž tvrdily
  `store.selection == pr`, tedy **přesně to jediné, co obsluha dělala**: byly zelené právem
  a o tom, co uživatel vidí, neříkaly nic. Poučení není „testuj víc“, ale **testuj ten stav,
  který se kreslí** — `selection` je od záložek (#180) v domácí záložce neviditelný, takže test
  nad ním nedokáže rozlišit funkční okno od okna, ve kterém se po kliknutí nestane nic.

  Ověřeno **vloženou regresí ve dvou podobách**: `selection = pr` místo `openTab(pr)` složilo
  šest testů ze třinácti (staré čtyři by prošly), a `Policy.notificationClick`, která vrací
  `open` vždycky, složila test „klik na PR mimo seznam neotevře nic“ i čtyři případy v `Policy`.
  K tomu tři nové případy, které dřív nebyly vůbec: že klik **nepřepíše uložený tab** (proud nese
  identitu, ne událost), že **filtr, který PR schoval, se zruší** (do #409 to byl kód bez testu)
  a že klik na **vlastní PR** (#331) záložku otevře taky — notifikace o cizí aktivitě (#335) na
  něj chodí a rozřazení podle autora se téhle cesty nesmí týkat.

  Samotné rozhodování je vyčerpané výčtem v `NotificationClickTests` (`Tests/Policy/`): PR
  v seznamu / mimo × vidět po filtru / schovaný × `notStarted` / načteno, včetně toho, že
  **chybující polling z chybějícího PR otevření nedělá** (seznam už jednou dorazil).

  Skutečné doručení fakem ověřit nejde, takže se ověřilo **spuštěním** — notifikace dorazila,
  delegát dostal `willPresent` i `didReceive` (`UNNotificationDefaultActionIdentifier`) a klik
  vybral ten PR, na který notifikace ukazovala. Klikalo se fyzickým `CGEvent`em na souřadnice
  z accessibility, protože `click` ani `click at` v System Events skutečný klik na notifikaci
  nepošlou. Podrobnosti v sekci `App/Environment/`.
- **Notifikace o doběhlém review (#82)** — dvě vrstvy. `Policy` vyčerpávajícím výčtem stavů,
  včetně skloňování (notifikace je krátký text, kde je špatný tvar to jediné, co v ní je vidět)
  a toho, co se nesmí slít: **nereportující běh se nesmí ohlásit jako čistý**, odmítnuté nálezy
  nejsou čisto a selhaný checkout není spadlá session. Plus že se stavy, které nejsou konec
  běhu (`running`, `cloning`, …) a `stale` **neoznamují vůbec**.

  `AppStore` na **kdy**: že dva skilly nad jedním PR dají **jednu** notifikaci, že selhání
  checkoutu i GitHubu dá vědět, a hlavně že se **zrušené review neoznamuje** — ten test je
  z celého issue nejdůležitější, protože bez něj by stačilo dát notifikaci do `defer`.
- **Rozvržení notifikace (#200)** — od #200 se ověřuje **titulek i tělo zvlášť**, protože každý
  odpovídá na něco jiného: titulek na „jdu k tomu hned?“, tělo na „co to je“. Čtyři věci, které
  se dají pokazit potichu:
  - **Sloveso u blokujících se skloňuje** — `1 blokuje`, `3 blokují`, ale `5 blokuje`. Tabulka,
    ne jeden případ: shodné jsou `one` a **`many`**, což je tatáž past jako u „blokujících“
    na #131, jen z druhé strany. Ověřeno **vloženou regresí** (`many: "blokují"`), po které
    spadly dva případy z pěti.
  - **PR zůstane na svém řádku.** Zlom v souhrnu od reviewera i víceřádkový detail selhání
    (`CheckoutError.userDescription` lepí výstup `gitu` za prázdný řádek) by ho odsunuly mimo
    banner — testuje se počtem řádků těla, ne obsahem. Ten druhý případ **našel test**, ne
    úvaha.
  - **Dlouhý souhrn se zkrátí**, a to na hranici slova; jediné dlouhé slovo (cesta, hash) se
    ořízne natvrdo, ať nezbude prázdno. Třetí případ přibyl z Copilot review na #248: když řez
    padne přesně na mezeru, **poslední slovo se vešlo celé** a nesmí se zahodit. Ověřeno
    vloženou regresí — text se zkrátil o pět znaků, na které bylo místo.
  - **`AppStore` posílá nález i počet blokujících z téhož záznamu** — test se dvěma nálezy
    (`style` a `correctness`) hlídá, že titulek nemluví o blokujícím a řádek pod ním o kosmetice.

  Co se z testů poznat nedá, je **kolik se toho do banneru vejde** — na to je jedině spuštění.
  Změřeno v `PRism-d`: titulek a pod ním **čtyři řádky těla**, a co se nevejde, macOS uřízne
  i s tím, co je pod tím. Odtud sto znaků v `Policy.notificationFindingLimit`. Zadání #200
  přitom počítalo s dvouřádkovým bannerem — je to zrovna ten případ, kdy odhad délky vyjde
  jinak než měření.
- **Diagnostika kreslení (#361)** — dvě vrstvy, a **cennější jsou ty negativní případy**.
  Skládání řádku je čistá funkce (`Policy.diagnosticLine`), takže se testuje literálem: že
  **nečinnost nezapíše nic** (bez kola a bez průchodů `nil`), že kolo bez jediného průchodu tělem
  řádek **dostane** (runloop se probouzí a nic se nekreslí — to je informace), řazení podle počtu
  a při shodě podle jména (bez toho by se dva soubory nedaly srovnat) a hlavička s jménem bundlu
  a PIDem. Pásmo času se do funkce **předává**, aby šel stamp napsat literálem, ne aby test
  závisel na tom, jak je stroj nastavený.

  Od #391 k tomu patří **zaseknuté kolo**: že se úsek s nulou kol a nulou průchodů zapíše, když
  hoří CPU, a dostane větu `HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU`; že s kolama runloopu tu větu **nedostane** (hoření při
  práci je jiný stav); že nečinnost se stopou CPU pořád mlčí; a že je ta hranice **podíl
  z uplynulého času**, ne absolutní sekundy — jinak by u kratší cadence zapisovacího vlákna hlásila
  zaseknutí nad prací, která hoří chvilku.

  Nad tím sběr sám: že **vypnutá diagnostika nezakládá ani prázdný soubor** (jinak by se z cache
  nedalo poznat, jestli sezení běželo se zapnutou), že se jméno typu skládá reflexí **jen u prvního
  průchodu** (v hořícím okně jsou to tisíce volání za sekundu, takže by měřidlo přispívalo do toho,
  co měří — ověřeno počitadlem v `@autoclosure`), že řádek **uzavře úsek** a počitadla se tím
  vynulují, že se **vyčerpaný strop napíše do souboru** a další řádky se zahodí, a že druhé
  sezení **přípisuje**.

  **A od #391 to nejcennější: že se zapisuje i v kole, ze kterého se runloop nevrátí.** Kolo se
  v testu **vyrábí** — observer na `beforeWaiting` s nižším pořadím (0) než to naše počitadlo
  (2 000 000), který se `Self.burn` (1 s) nevrátí a přitom hoří (zaměstnané vlákno, ne `sleep`;
  spící by CPU nespálilo a řádek by pak tvrdil, že se nic nedělo). Runloop je tedy uvnitř
  callbacku, přesně jako v tom záchvatu. **Čte se snímek souboru z chvíle, kdy záchvat ještě
  trval** — bere ho ten blokující observer, než se vrátí; po záchvatu by to nic nedokazovalo,
  protože tehdy už runloop běží a řádek by mohl napsat kdokoli. Naměřeno: **šest řádků za tu
  sekundu**, všechny `0 kol runloopu` a všechny s větou o zaseknutí.

  **Vložená regrese je u toho druhý test, ne poznámka**: tentýž záchvat, ale řádky vypisuje
  observer runloopu, jak to bylo do #391 — ze záchvatu nezůstane **nic** (`file` neexistuje). Bez
  toho tvrzení by první test nedokazoval, že ty řádky přineslo zapisovací vlákno. **A ověřeno i
  obráceně**, na kopii bez opravy: s vypnutým `startWriting()` padne první test na
  `(duringFit.count → 0) >= 2`, tedy na tom, že ze záchvatu nezůstalo nic.

  **Strop je hned u toho, jak se to píše** (pravidlo z #379): hoří se `Self.burn` a ani
  o milisekundu víc.

  Třetí případ z té trojice: **druhé volání `startWriting()` nepustí druhé vlákno.** Dva
  zapisovatelé si přebírají počitadla po sobě (každý flush je nuluje), takže by se hořící sekunda
  rozpadla na úseky, ve kterých není vidět nic — tedy zrovna ta věta, kvůli které se záznam bere.
  Testuje se na počtu řádků ze záchvatu: při cadenci 0,1 s jich za sekundu smí být nejvýš deset.

  Sedmý případ přibyl z Copilot review na #386 a je z nejcennější třídy: **nové sezení nad plným
  souborem nezapíše nic** — ani hlavičku, ani druhý limitní řádek —, protože strop platí na
  **soubor**, ne na sezení. Ověřeno **vloženou regresí**: s počitadlem od nuly (`written` bez seedu
  z velikosti souboru) spadnou dvě expectations ze tří, na tom, že druhé sezení hlavičku zapsalo
  a soubor se změnil. Od #412 se to tvrdí **o logu bez rotace** (sondy, testy) a hned pod ním stojí
  obrácené tvrzení pro aplikaci, viz níž. Co se z testů poznat nedá, je chování diagnostiky
  **zapnuté z prostředí** — `start()` se pouští jedině s `PRISM_DIAGNOSE=1` a v testovacím hostu by
  psal do **skutečné** cache, protože host má `CFBundleName` hlavní instance. Testy si proto
  instanci staví samy, se souborem v dočasné složce.
- **Rotace záznamu a srážení klidu (#412)** — tři vrstvy a to nejcennější je zase obrácené tvrzení
  proti #386: **sezení s rotací zapisuje i nad plným souborem.** Skládá se to ze čtyř věcí:

  Čisté funkce (`DiagnosticsArchivingTests`, 11 případů): jméno z **času posledního zápisu** a ne
  z času rotace (jinak by soubor ze pátku měl v názvu pondělí), přípona `-2` na kolizi, výčet toho,
  co se za uložený záznam **nepočítá** (`diagnostics.log`, `activity.json`, `sessions.json`,
  `…log.bak` — v kořeni cache leží i nálezy a drafty, takže úklid podle přípony nebo času by sáhl na
  ně), mazání od nejstaršího podle **obou** mezí, tie-break jménem a řádky do záznamu včetně toho,
  že **bez rotace se nepíše nic** a že se nepovedená rotace **přizná**.

  **Nejnovější záznam přežije i nad bajtovou mezí** — ověřeno **vloženou regresí**: bez pravidla
  „první se počítá vždycky“ vyjde ke smazání ten 9 MB soubor, který rotace právě uložila, tedy zrovna
  ta historie, kvůli které se u #361 čte zpětně.

  Nad souborem (`RenderDiagnosticsTests`): že sezení s rotací **zapíše** i tam, kde plný předchůdce
  do #412 zapisovat nedovolil, že **starý soubor leží vedle a je celý** (obsah se porovnává, ne jen
  existence), že se nad prázdnou cache **nerotuje** (prázdný soubor není historie) a že úklid smaže
  nejstarší a jméno napíše do `rotation.deleted`. Ověřeno **vloženou regresí**: s rotací vypnutou
  (`if false, let archive`) spadnou oba testy — první na tom, že `append` vrátí `false`, druhý na tom,
  že se nic nesmazalo. Časy zápisu se v testu **nastavují** (`setAttributes`), protože jméno i pořadí
  mazání se berou z nich; jinak by test tvrdil něco o hodinách stroje. A na pole archivů se sahá
  přes `#require`, ne indexem — test, který s vloženou regresí složí celý běh, sebere výsledky
  i všem ostatním.

  Ochrana mazání se tvrdí ze dvou stran a **obojí je změřené, ne odvozené**: složka pojmenovaná jako
  záznam se nesmaže (`removeItem` nad ní smaže celý podstrom) a **symlink taky ne** — nález Copilota
  na #423 plus sonda, ze které vyšlo, že `resourceValues(forKeys: [.isRegularFileKey])` odkaz
  **nerozbaluje** (u odkazu na obyčejný soubor `isRegularFile == false`, `isSymbolicLink == true`).
  Komentář v repu tvrdil původně opak („odkaz se smaže, ale je to neškodné“), takže je to zároveň
  příklad toho, proč se tvrzení o `FileManager` měří.

  Srážení klidu: že **klid do minuty nezaloží ani soubor** a po minutě je z 60 úseků jeden souhrn,
  že souhrn jde **před** řádkem, který klid přerušil (časy v souboru musí jít vzestupně), a že
  **hořící úseky se nesráží** — tři za sebou jsou tři řádky. To poslední je ta podmínka, na které
  #412 stojí: zajímavý je náběh záchvatu.

  **Ověřeno i spuštěním** (`PRism-c`, `./bin/run.sh --diagnose` dvakrát za sebou), protože `start()`
  žádný test nejde: v prvním sezení nejsou řádky o rotaci (prázdná cache), po restartu leží
  předchozích 848 B jako `diagnostics-do-2026-08-24T10-02-02.log` a nový soubor začíná hlavičkou,
  řádkem `předchozí záznam (848 B) uložen jako …` a řádkem o grafu. Za 70 s sezení má záznam
  **11 řádků a 1 055 B** — v tom jeden souhrn `za 61.00 s klid: 57 úseků, 235 kol runloopu, 0.366 s
  CPU, 1 bez kola runloopu`, který by do #412 byl 57 řádků. Blok v `bin/run.sh` je vyzkoušený i **ve
  výjimečném stavu** (pravidlo z #61): nad souborem nafouknutým na 8 388 608 B vypíše, že mu chybí
  konec, a skončí nulou — do #412 tady bylo `exit 1`.

  **Nad skutečnou scénou je na to sonda** (`IdleDiffSpinProbe.diagnosticsUnderLoad`,
  `PRISM_MEASURE`): kontrolní seznam se zpětnou vazbou z rozvržení do stavu (`FeedbackLoopList`)
  a hned za ním projetí osy kolečkem, se zapnutou diagnostikou do dočasného souboru. Naměřeno:
  **31,72 % CPU** v prvním úseku, 29 řádků v záznamu — a mezi nimi dva takové, které do #391
  nemohly vzniknout:

  ```
  za 0.51 s: 0 kol runloopu, 0.492 s CPU — HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU
  za 0.57 s: 6 kol runloopu, 0.153 s CPU
  ```

  Kontrolní scéna tedy vyrábí i **půlsekundové úseky, ve kterých hlavní vlákno runloop vůbec
  nepustí ke slovu**, a diagnostika je zapsala. Sonda u toho vypisuje CPU vedle počtu řádků: bez
  toho čísla by nebylo poznat, jestli se měřilo nad zátěží, nebo nad prázdnem.
- **Evaluační zásobník AttributeGraphu (#361, osmé kolo)** — tři vrstvy, a to nejcennější je zase
  negativní: **z cizího vlákna a mimo aktualizaci grafu se nesmí vrátit nic** (`GraphProbeTests`).

  **Dvířka (`GraphProbe`) se testují spuštěním, protože jinak to nejde.** Je to privátní
  `AGGraphDescription`, takže jediné, co drží tvrzení v jeho dokumentaci, je scéna
  (`ScrollView` + `LazyVStack` v okně mimo obrazovku) a čtyři testy nad ní: že zásobník přijde
  **z těla, z `of:` closure u `onGeometryChange` i z getteru identity**, že je v něm rámec líného
  seznamu pojmenovaný (`Lazy…` — jinak by ten nástroj u #361 neměřil to, o čem issue je), že mimo
  aktualizaci grafu vyjde `nil` a že z **cizího vlákna** taky. Až systém tu funkci přejmenuje,
  spadne to tady — diagnostika, která tiše přestane odpovídat, je horší než žádná.

  **Vlastnictví návratové hodnoty se zjistilo pádem, ne měřením.** Footprint tvrdil +1 (100 000
  volání bez `release`: 13,8 → 122,3 MB), takže první verze brala `takeRetainedValue()` — a test
  složil proces `SIGSEGV`em v `objc_release` uvnitř `AutoreleasePoolPage::releaseUntil`. Hodnota je
  **autoreleased**; ten footprint rostl proto, že se v tom měření pool ani jednou nevyprázdnil.
  Plyne z toho pravidlo pro příště: **u privátního API rozhoduje pád v testu, ne úvaha nad
  RSS** — a to je zároveň důvod, proč tenhle test v repu zůstává.

  **Rozbor výpisu je čistá funkce nad skutečnou fixture** (`Policy.graphStack`,
  `GraphStackDigestTests`, `Tests/Fixtures/attributegraph/stack-text.txt` — skutečný výstup, ne
  ruční literál). Testuje se vrchol, kořen a `changed` vstupy; že z **cizího textu nevznikne jméno
  atributu** (`nil`, ne půlka řádku — formát je privátní a může se změnit); že prázdný úsek nedá
  **žádný** řádek; a dvě meze, obě z měření: do souboru jdou jen **rámce a vstupy s `changed`**
  (jeden řádek vstupu měl nad skutečným diffem 1,5 kB a blok jich měl desítky, takže by hořící okno
  vyčerpalo strop 8 MB za pár minut) a dlouhé jméno typu se **zkrátí** na 200 znaků.

  Z Copilot review na #397 k tomu přibyly dva případy, oba z třídy „mez musí být vyjmenovaná“:
  **histogram ukáže šest položek a zbytek přizná** (`+N dalších` — osm vzorků s osmi různými kořeny
  by jinak dalo jednu řádku s osmi jmény po 200 znacích) a **řádek bez šipky se do výpisu neopíše**
  (do té doby stačilo, že začíná `#`, takže by se po změně formátu opisoval syrový text jako rámec).

  **Nad sběrem to samé, co u počitadel průchodů**: že vypnutá diagnostika nesáhne ani na graf
  (hák sedí na cestě identity, tedy tam, kde se v hořícím kole volá tisíckrát za sekundu), že
  `diagnosedID` vrací **tutéž** identitu jako `id` (jinak by zapnutá diagnostika přerovnala líný
  seznam a měřilo by se něco jiného), že **ticho nedostane přílohu** (řádky o grafu jen s hlavním
  řádkem úseku, ale nasbírané se zahodí tak i tak) a že vzorků je za úsek **nejvýš osm** a v jedné
  smyčce **jeden** (rozpočet a odstup, `interval: 0` v testu vypne odstup, aby test nezávisel na
  hodinách).

  **A že je každé vyjmenované místo doopravdy zapojené, tvrdí test nad zdrojáky**
  (`GraphSiteWiringTests`, tatáž konstrukce jako `SingleWayOutTests` včetně zahazování komentářů):
  vyjmenované místo, které nikdo nevolá, je v záznamu nula, která lže — nedá se odlišit od „tímhle
  místem kolo neprochází“, což je zrovna ta věta, kterou se u #361 hledá příčina.

  **Nad skutečným oknem aplikace je na to měření**
  (`IdleDiffSpinProbe.graphInstrumentationOverRealWindow`, `PRISM_MEASURE`). Není to pokus kolo
  vyrobit — to se v harnessu za osm kol nepovedlo ani jednou —, odpovídá to na jinou otázku: **ozvou
  se háky nad skutečným stromem a přijde z nich zásobník?** Naměřeno při projíždění kolečkem: diff
  `DiffRow.id=857 FileDiff.id=453 DiffPairBlockRow.geometry=172`, osa `ConversationRow.id=2113`,
  vzorky 6/6 a 5/5. Kořen je v obou `LazySubviewPrefetcher<LazyVStackLayout>`, vrchol
  `LazySubviewPlacements` a jediný `changed` vstup je **transformace**
  (`CoordinateSpaceNameTransform` v diffu, `ScrollViewChildTransform` v ose). Nad projížděním je to
  očekávané, takže **příčinu #361 to netvrdí** — cenné je to jako srovnávací tvar pro záchvat.

  **Odkud se berou dotazy na geometrii řádku diffu** (#438) měří tatáž sonda scénářem
  `lineGeometryOrigin`: projede kolečkem dvě záložky nad toutéž scénou a vypíše počty. Zadání #438
  vinilo diff pod jiným tabem, měření to vyvrátilo — s **diffem vepředu** se `DiffLine.geometry`
  neozve ani jednou (`DiffView` slévá řádky do bloků, takže tam `DiffLineView` nekreslí nic),
  kdežto **osa konverzace** s 60 vlákny dá **242** zásahů, po opravě **0**. Osa proto musí mít
  vlákna s `diffHunk`em (`Self.threaded(count:)` ze `conversation-diff-hunks.json`): syntetická osa
  ze `synthetic(comments:)` je jen komentáře, takže by úryvek nevznikl a sonda by hlásila nulu před
  i po — zelenou zprávu o tom, že se nic neměřilo.

  **Co se z toho nedá udělat test:** práce, jejíž výsledek nikdo nepřevezme, po sobě nenechá nic
  pozorovatelného. Jediná stopa je počitadlo v `RenderDiagnostics.current`, a to je **globál
  procesu** — test, který do něj zapíše, umí položit `RenderDiagnosticsTests` (tvrdí `current == nil`)
  a `main` je pak falešně červený (#367, #411). Strukturu proto drží `DiffLineGeometryTests` nad
  zdrojáky: `onGeometryChange` je v `DiffLineView` **jednou** a jen ve větvi `reportsFrame`, ta
  podmínka se ptá na identitu řádku **i** na krabici, úryvek na ose nepředává ani jedno a diff
  předává obojí (to je kontrola měřidla — bez ní by nula znamenala i „rámeček nehlásí nikdo“).
  **Ověřeno vloženou regresí v obou podobách**: s `reportsFrame` na `true` spadne tvrzení
  o podmínce a sonda vydá zase 242, s `onGeometryChange` vráceným do řetězce `row` spadne tvrzení
  o větvi.

  Co se z testů poznat nedá: jak to vypadá v **záznamu skutečné instance**. Ověřeno spuštěním
  (`PRism-a`, `./bin/run.sh --diagnose`): za hlavičkou sezení je řádek
  `evaluační zásobník AttributeGraphu k dispozici`, tedy `dlopen` privátního frameworku prochází
  i v nainstalované podepsané aplikaci; nad nečinným oknem bez otevřeného PR se žádný řádek o grafu
  nepíše, protože se háky nemají kde ozvat.
- **`AppStore` — pohled na diff** — že se bez odchylky bere hodnota z nastavení, že ji přepnutí
  v liště přebije, že se změna nastavení projeví **bez restartu** a že odchylka **shodná**
  s nastavením přežije jeho změnu. Poslední dva potřebují skutečný `ConfigStore` nad dočasnou
  složkou: bez něj `updateConfiguration` skončí chybou `noStore` a nepropíše se nic.
- **`AppStore` — sbalení souborů** — výchozí rozbaleno, přepínání tam a zpět, že sbalení
  jednoho souboru nesahá na jiné ani na jiné PR, idempotentní rozbalení (na tom stojí skok)
  a `Rozbalit vše`, které nechá cizí PR být.
- **`AppStore` — rozbalení kontextu** — že se obsah souboru dotáhne jednou, že selhání
  nenechá po sobě točící se kolečko ani úsek označený za odkrytý, a že sbalení zahodí
  rozsahy, ale načtený obsah nechá.
- **`PollingService`** — proti `FakeGitHubGateway` (odpovědi v pořadí, poslední se opakuje)
  a `FakeTimeSource`. Ten místo čekání zapisuje **požadované délky uspání** — na nich se
  ověřuje backoff — a po zadaném počtu uspání smyčku ukončí `CancellationError`em. Testy
  tak běží v nulovém reálném čase a bez závodů. Pozor na počítání odpovědí: selhávající
  tik spotřebuje jen jednu, protože se u prvního zdroje přeruší.
- **`AppStore`** — proti fake gateway: obnovení se ptá zdrojů, seznam se čte z pollingu,
  výběr se drží. Views se neunit-testují; kontroluje se běžící aplikace (viz níž).
- **`AppStore` — review** — fake gateway, fake checkout, fake reviewer a **skutečný**
  `ReviewStore` nad dočasnou složkou: on rozhoduje, co se objeví po restartu, takže fake by
  ověřoval sám sebe. `FakeReviewRunner` umí běh pozdržet, na čemž stojí testy průběhu,
  zrušení a toho, že druhé zmáčknutí nespustí nic dalšího. Čeká se točením přes
  `Task.yield()`, ne na continuation — zrušený běh musí z čekání vypadnout sám, jinak by
  test visel místo aby spadl. Součástí je `runningReviews` **napříč PR**: na tom čísle visí,
  jestli se aplikace před zavřením zeptá. Samotný dialog se unit-testovat nedá (modální
  `NSAlert`), ověřil se na běžící aplikaci — viz níž.
- **`ReviewPublisher`** — proti `FakeProcessRunner` a fake gateway. Úklid dočasného souboru
  se ověřuje **cestou z konkrétní invokace**, ne obsahem systémové dočasné složky: Swift
  Testing pouští testy paralelně, takže porovnání „před a po“ nad `/tmp` je flaky (chytilo se
  to v review #67). Nejdůležitější testy
  netvrdí, co se odeslalo, ale že se **nic neodeslalo**: výchozí (vypnuté) nastavení, neshoda `headSha`,
  zavřený PR a draft bez verdiktu musí skončit dřív, než se sáhne na `gh` (kontroluje se
  `runner.invocations.isEmpty`). Klasifikace chyb jde tabulkou nad **skutečnými** hláškami
  z fixtures (`review-error-*.json`), úspěch nad skutečnou odpovědí (`review-submitted.json`)
  — obojí z živého API. Tvar payloadu je ověřený tím, že týž payload API u #67 přijalo.
  `FakeReviewPublisher` v `Tests/Publish/` nic neodesílá a počítá, co po něm kdo chtěl.
- **`ReviewDraftStore`** — proti skutečné dočasné složce, jako `ReviewStore`. To hlavní je
  „draft přežije restart“, tedy načtení **novým** storem nad tou samou složkou. Plus prázdný
  draft, který se maže; nečitelný soubor, který se ve výpisu počítá a u konkrétního PR vyhodí
  chybu; draft cizího PR uvnitř souboru; a že cesta leží mimo složky, po kterých chodí
  eviction. Pozor na past v testu: `ReviewDraftComment` si generuje `UUID`, takže dvě volání
  továrničky nedají shodné hodnoty — draft se musí uložit do proměnné.
- **Přenesení draftu (#69)** — `Policy` vyčerpávajícím výčtem stavů: nezměněný řádek sedí,
  posunutý se najde na novém čísle (rozhoduje **text**, ne číslo), přepsaný se ztratí, změna
  odsazení kotvu neztratí, chybějící snímek dá `uncertain` a ne `fits`, a rozsah s jedním zmizelým
  koncem je `lost`. U přenesení to hlavní není, co se přenese, ale **co se nepřenese tiše**:
  ztracený komentář jde do těla s odkazem na nový commit, rozhodnutí člověka přebije výchozí volbu
  a rozepsané tělo zůstane.

  `AppStore` proti **skutečnému** `ReviewDraftStore`: komentář si uloží snímek, bez diffu zůstane
  prázdný, a celý řetěz od staršího draftu po odeslání — kotva se posune na nový řádek, zastarání
  přestane blokovat a **přežije to restart**. Plus draft, ze kterého přenesení vyjme všechno, se
  smaže.

  `ReviewSubmission` na to, že se **v kontrole nedá odeslat** (`runner`/publisher nedostane nic),
  že prázdné kotvy z kontroly nedělají hotový stav, že po přenesení odejde **nový** snímek a že
  nepovedené přenesení nechá okno v kontrole.
- **`Policy` — draft** — komentovatelnost vyčerpávajícím výčtem: přidaný řádek (`right`),
  kontextový (`right`), odebraný (`left`), `meta` (nikdy), řádek mimo hunky a **rozbalený
  kontext**. Ten poslední se staví přes `DiffRow.rows(revealed:content:)`, ne ručně —
  rozbalený řádek se skládá jako obyčejný kontext s oběma čísly, takže test, který si ho
  vyrobí sám, by netestoval to, co v aplikaci vzniká.

  U kotev navíc to, že **mapa dává totéž co dotaz po jednom řádku** — je to jen zrychlení,
  takže rozchod by nabízel komentáře na řádcích, které GitHub odmítne. U rozřazení nálezu
  každá varianta zvlášť (řádek v hunku, mimo hunky, bez řádku, bez souboru, bez diffu)
  a **stará cesta přejmenovaného souboru**, která se musí přeložit na dnešní. U odznaku
  „už je v draftu“ to hlavní: nález **druhého** revieweera na tomtéž řádku převzatý není.
  U permalinku zakódovaná mezera v cestě a odkaz na vlastním řádku — bez obojího GitHub
  úryvek kódu nevyrenderuje.

  U **odesílatelnosti** (#68) každý důvod zvlášť a **v pořadí**, ve kterém se hlásí: že repo
  bez povolení přebije i hotový draft, že neznámá hlava není zastarání a že prázdný komentář
  blokuje. Brána se od #107 **předává**, takže si test o povolení řekne (`PublishScope.allowing(_:)`)
  místo toho, aby musel běžet nad sandboxovým identifikátorem; že výchozí konfigurace nepovolí
  nic, drží vlastní test. Plus to, že **každý důvod má
  vlastní neprázdnou větu** — prázdná by v okně vypadala jako mlčky zakázané tlačítko.

  U **otevření potvrzení** (`canOpenSubmission`, #151) vyčerpávajícím výčtem: **každý** důvod,
  proč se odeslat nedá, zavírá i potvrzení, a to i s možností přenést — přenesení spraví
  zastarání, ne chybějící verdikt. Zastarání je jediná výjimka a jen tehdy, když je proti čemu
  kotvy zkontrolovat. Je na to vlastní sada proto, že se od #151 na tutéž otázku ptají **dvě**
  místa (tlačítko v panelu a zkratka `⌘⏎`); rozchod by znamenal zkratku, která otevře okno nad
  zakázaným tlačítkem.

  U **předvyplněného verdiktu** (#114) to hlavní není, že s návrhem `noVerdict` zmizí, ale že
  návrh **nepřeskočí ostatní důvody** — prázdný komentář, zastarání ani bránu — a že z prázdného
  ani neexistujícího draftu nedělá „je co poslat“. `effectiveVerdict` má vlastní sadu na každý
  stav: bez návrhu, s návrhem, volba přebíjející návrh, `comment` proti návrhu a **zrušená volba
  padající zpátky na návrh**. K tomu vlastní PR: shodný autor a `viewer` nepředvyplní, neznámý
  `viewer` předvyplňuje dál.
- **`ReviewSubmission` (#68)** — proti `FakeReviewPublisher`, takže se **nic neodesílá**.
  To hlavní není, co se odeslalo, ale kdy se **neodešle nebo neuklidí**: selhání nesmí spustit
  úklid draftu (a musí jít zkusit znovu), po úspěchu se nesmí odeslat podruhé a zrušení se
  nesmí hlásit jako chyba. Plus zavírání sheetu — u odpovědi, jejímuž stavu nerozumíme,
  zůstává otevřený — a rozchod s návrhem z nálezů, u kterého se hlídá i to, že `jen komentář`
  rozchod **není** a že jím **předvyplněný návrh** není (#114), zatímco vědomé přepnutí pořád
  varuje. Plus to, že přenesení na nový commit předvyplněný verdikt **nezahodí** — přenesený
  draft přichází ze storu bez verdiktu, takže by review odešlo bez `event`u. Pozor na past:
  `ReviewDraftComment` si generuje `UUID`, takže se draft musí uložit do proměnné, ne vyrobit
  dvakrát.

  Dvě věci se testují tabulkou chyb, protože jsou to celé **třídy**, ne jednotlivé případy:
  po které chybě se smí zkusit znovu a po které ne (`mightHaveReachedGitHub`).

  Čeká se u nich **odmlkami, ne `Task.yield()`**, na rozdíl od zbytku repa. Ten spin by běžel
  na `MainActoru` (`ReviewSubmission` je `@MainActor`) a **bez horní hranice** — dokud závoru
  někdo nepustí. Swift Testing pouští suity paralelně, takže z toho začaly padat
  `SubprocessStreamerTests`: zabíjený proces se nestihl zabít dřív, než mu doběhl `sleep 1`.
  Změřeno, ne odhadnuto — na `main` procházely, na branchi padaly dvakrát za sebou a po
  záměně za `Task.sleep(for: .milliseconds(1))` je sada třikrát po sobě zelená.

  A **dvojklik se pouští naráz** (`async let` dvakrát), ne s čekáním na to, až první odeslání
  poběží. Zákaz druhého odeslání drží jen na tom, že `state = .sending` leží před prvním
  `await`; test, který na první odeslání počká, ten závod zavře a přesunutí toho řádku by mu
  prošlo. Ověřeno tím, že se ta regrese do kódu dočasně vložila — sekvenční test zůstal
  zelený, souběžný spadl na `2 == 1`. `FakeReviewPublisher` umí odeslání **pozdržet**
  (`hold(until:)`) ze stejného důvodu jako `FakeReviewRunner`.
- **`AppStore` — odeslání (#68)** — proti **skutečnému** `ReviewDraftStore` nad dočasnou
  složkou: po úspěchu má draft zmizet i z disku, tedy i pro restart. Vedle toho každý stav,
  ve kterém `submission(for:)` nesmí vzniknout (zastaralý draft, chybějící verdikt, žádný
  draft), a to, že se konverzace načte znovu — bez toho by v `Přehledu` chybělo moje vlastní
  review až do přepnutí PR.

  Od #151 k tomu test, že **otevření potvrzení nic neodešle** — tedy že po `submission(for:)`
  zůstal draft v paměti i na disku a konverzace se nenačetla znovu. Jsou to obě stopy, které by
  úspěšné odeslání zanechalo (`draftWasSubmitted`), takže se tvrdí „nestalo se“, ne „vrátilo to
  objekt“. Je to podklad pod zkratku `⌘⏎`, která nedělá nic jiného než tohle. Ověřeno vložením
  regrese: `discardDraft` uvnitř `submission(for:)` test shodí.
- **`Policy` — přehled (#72)** — chronologické slití review, komentářů a vláken; že se vlákno
  **s kotvou** do přehledu nedostane (jinak se tentýž komentář čte na dvou místech); že review
  bez verdiktu a bez prózy vypadne (je to jen obálka řádkových komentářů), kdežto schválení
  s prázdným tělem zůstane; že položka bez data jde naspod, ne pryč; a že shodné `id` u review
  a komentáře dá dvě položky, ne jednu.
- **`MarkdownParser`** — každý test ověřuje i **invariant**, že se žádný obsah neztratil
  (písmena a číslice ze všech bloků složené zpátky). Pokrývá nadpisy včetně falešných (`#tag`),
  odstavce se zalomením, odrážky/čísla/zaškrtávátka, zanoření, fence (i neuzavřený a s cizími
  značkami uvnitř), citace, oddělovače, tabulky — a HTML od botů: `<!-- … -->`, `<details>`
  včetně **zanořeného** a neuzavřeného. Plus skutečný popis PR z fixture, tedy cizí text, který
  nikdo nepsal pro test. `MarkdownHTML` má vlastní sadu: odkaz na Markdown se všemi druhy
  uvozovek, `<br>`, entity a to, že `&amp;` se dekóduje naposled.

  **Citace a výstrahy (#279)** mají vyčerpávající výčet, protože je to čistá funkce: nadpis,
  odrážka a zaškrtávátko **uvnitř** citace, vnořená citace, `<details>` v citaci, zachované
  odsazení zanořeného seznamu, všech pět druhů výstrahy, výstraha **uvnitř** citace, bloky uvnitř
  výstrahy a obsah **za stropem zanoření** — a to zvlášť pro citace i pro `<details>` (nevysází se,
  ale zůstane). Ten druhý přišel až po review: počítadlo otevřených tagů se jmenovalo `depth`
  a **zastínilo** parametr s hloubkou rekurze, takže strop nezabíral vůbec a rozbalovátko hloubku
  ještě resetovalo. Chytil to Copilot, ne testy — proto ten test existuje. Nejcennější jsou tři, které
  tvrdí, že se něco **NEstalo**: **neznámý druh** `[!FOO]` výstrahu nedá a ten řádek v citaci
  zůstane, **značka s textem na témže řádku** taky ne, a nad **skutečným** komentářem od
  `coderabbitai` (fixture `gh/comment-coderabbit.md`, veřejné `coderabbitai/ast-grep-essentials#200`)
  se ověřuje, že v žádném odstavci nezůstal řádek začínající `>` nebo `#` — tedy že v okně nestojí
  zdroj. Ověřeno vložením regrese: bez rekurze v citaci padnou čtyři testy, po spolknutí neznámého
  druhu na `.note` padne i invariant (nahlásí ztracené `FOO`).
- **`MarkdownTypography` (#279)** — že úrovní nadpisů je **šest různých a monotónně klesajících**
  (to je celá ta vada, kterou #279 opravuje), že linka je jen pod `#`/`##`, tlumená jen šestka,
  že úroveň mimo rozsah se přiklopí a že škála roste se základní velikostí. U rytmu: nadpis má nad
  sebou nejvíc místa a pod sebou nejméně, první blok **nemá** mezeru, a **žádný přechod mezi dvěma
  bloky nevyjde nula** — to je výčet přes všechny druhy bloků obojím směrem.
- **`MarkdownAlertStyle` (#279)** — barvy se porovnávají **vyřešené na hex, v obou režimech**
  (`NSAppearance.performAsCurrentDrawingAppearance`), protože token je dynamický a shoda může být
  jen v jednom z nich: každý druh má vlastní barvu, `[!CAUTION]` se nerovná `crit` a `[!WARNING]`
  se nerovná `stale`. Plus že každý druh má neprázdný titulek a **existující** SF Symbol.
- **`MarkdownInlineText` (#279)** — že inline sází systém (tučné zůstane, odkaz zůstane klikatelný),
  že inline `kód` dostane podklad a monospace, a hlavně že ho **nedostane nic jiného** — podklad
  nad celým odstavcem by z prózy udělal blok kódu. Plus že rozbitý Markdown vrátí holý text.
- **`MarkdownRenderCache` (#279)** — že vrací totéž co parser, že **dva různé texty se nepotkají
  v jednom záznamu** (klíčem je celý text; ověřeno regresí — s klíčem podle délky test padá na
  vysázeném cizím komentáři) a že se cache nedostane přes ani jednu ze dvou mezí. Text delší než
  celý rozpočet se **nezapamatuje**, ale rozloží.
- **Měření sazby (#279)** — `MarkdownPerformanceMeasurement`, gated `PRISM_MEASURE`. Nic netvrdí;
  existuje proto, že rekurze v citacích se počítá v `body` a to rozhodnutí má být podložené číslem:
  zpráva od bota o 12 kB 1,91 ms, z cache 0,037 ms; konverzace o 40 zprávách 74,7 ms proti 1,48 ms.
  Čtvrté číslo rozhodlo o rozsahu cache: **inline sazba** 44 bloků té zprávy je 1,81 ms, tedy
  stejně drahá jako rozklad — takže se pamatuje taky.
- **Sonda sazby (#279)** — `MarkdownRenderProbe`, taky gated, vyrendruje ukázku i skutečnou zprávu
  od bota do PNG **v obou režimech**. Barvy palety se řídí `NSAppearance`, kdežto `.primary`
  a `.secondary` prostředím SwiftUI, takže se musí nastavit **obojí**; s jedním z toho vyjde tmavý
  text na tmavém podkladu a vypadá to jako chyba v sazbě. Našla dvě věci, které z kódu vidět
  nebyly: nerozeznatelné úrovně nadpisů 3–5 a pruh citace, který sahal do poloviny obsahu.

  ```bash
  TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
      xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
      -only-testing:PRismTests/MarkdownRenderProbe > /tmp/probe.log 2>&1
  ```

  Pozor na dvě pasti: `PRISM_MEASURE=1` **před** `xcodebuild` nestačí (do testovacího procesu jde
  jen to, co má prefix `TEST_RUNNER_`), a **tabulka vyjde v renderu prázdná** — je ve vodorovném
  `ScrollView`, který se offscreen nevykreslí. Není to chyba sazby, jen mez sondy.

  **Od #295 má sonda i vzorek s `CRLF`** — skutečné tělo komentáře z `cli/cli`, ve kterém je jedno
  `CRLF` uvnitř odstavce a `CRLF CRLF` mezi odstavci. Je to jediný způsob, jak tu opravu **vidět**:
  do #295 vyšly tři odstavce se stejnými mezerami, od #295 jsou to dva a to zalomení uvnitř prvního
  zůstalo zalomením. Rozdíl se dá reprodukovat bez sahání do parseru — stačí do sondy přidat druhý
  vzorek s `\r\n` nahrazeným `\n\n`, což je přesně to, co `components(separatedBy: .newlines)`
  vyráběla.
- **`AppStore` — taby** — výchozí `Přehled` (proti `PullRequestTab.standard`, ať se to nerozejde),
  volba per PR, přepnutí zpátky mažící klíč a úklid s PR, které zmizelo ze seznamu.
- **`Policy` — hledání v paletě (#184)** — vyčerpávající výčet nad hotovým katalogem, bez kreslení.
  To hlavní jsou tři tvrzení: **pořadí skupin je pevné** (nálezy první), **strop je na skupinu**
  (dvacet nálezů nesmí vytlačit soubory, PR ani akce) a **prázdný dotaz vrací všechno**, protože
  paleta je nabídka toho, co je po ruce. K tomu váhy (titulek > podtitulek > klíčové slovo, začátek
  titulku > hranice slova > vnitřek), diakritika a velikost písmen (`nalez` najde `nález`), víc slov
  jako **a zároveň** a to, že se zvýrazňuje **v tom textu, ve kterém se to potkalo** — u shody
  v podtitulku je `titleHighlight` `nil` a naopak, protože zvýraznit něco jinde by bylo tvrzení, že
  se to potkalo tam.

  Hledání podle **autora a repozitáře** má vlastní výčet: shoda jen v autorovi, jen v repu, v obojím
  naráz (platí jako **a zároveň**, takže `vault sykora` nesmí vytáhnout PR téhož autora z jiného
  repa) a kolize titulek × autor — ta musí skončit titulkem první, jinak by dotaz na slovo z titulku
  vytáhl nahoru PR, ve kterém to slovo není nikde vidět.

  U **akcí** se testuje, co se nenabízí: bez otevřeného PR nic, co na PR visí; za běhu review
  `Zrušit` **místo** `Pustit`; sekce railu, která je zrovna vidět v domácí záložce. A že kreslené
  zkratky jsou jen ty dvě skutečné (`⌘2`, `⌘,`) — `⌘⇧R` z návrhu dělá v aplikaci něco jiného.

  Test na **pořadí při shodných váhách** je zapsané pravidlo, ne důkaz: vložená regrese (zahozený
  druhý klíč řazení) ho neshodí, protože dnešní `sorted` v Swiftu stabilní je, i když to nemá
  v kontraktu.

  **Dvě skupiny pull requestů (#336)** mají tři tvrzení, a to nejcennější je to, kvůli kterému se
  dělily: **dvacet cizích PR nevytlačí ani jedno moje** (ve společné skupině by vytlačilo, protože
  šestý řádek je strop). K tomu pořadí skupin s vlastními **za** cizími, nadpisy (`Pull requesty
  k review` a `Moje PR` — se dvěma skupinami musí první říct, čeho se týká) a to, že **bez vlastních
  PR se nadpis nekreslí**; prázdný nadpis vypadá jako rozbité hledání.

  **Ověřeno vloženou regresí** (katalog zařadí všechno do `.pullRequests` a nadpis se vrátí na „Pull
  requesty“): padne **pět testů** — čtyři nad storem a jeden nad nadpisem, dohromady osm tvrzení.

  Poprvé z toho vyšlo „0 tests passed“, a to je poučení, které z toho zůstává: **`try! #require`
  položí celý běh**, takže sečtený řádek na konci hlásí, že neproběhlo nic, a kdo čte jen poslední
  řádek, přečte si opak toho, co se stalo. Test proto musí být `throws` a `#require` se volá `try`
  (upozornil na to Copilot na #368; v `Tests/` byly dva výskyty a padly oba).
- **`AppStore` — command palette (#184)** — proti fake gateway. **Nejcennější test celé palety
  tvrdí, že se nic nestalo**: po sestavení katalogu, prohledání a vykonání každého druhu cíle musí
  mít gateway pořád tentýž počet volání (search, diff, detail, konverzace). Bez toho by stačilo,
  aby si katalog někdy dotáhl diff druhého PR, a z každého stisku klávesy by byl podproces.

  Vedle toho: autor je v **podtitulku** PR řádku (a v klíčových slovech zůstává jen vlastník repa,
  který v podtitulku není), dotaz na jméno autora najde **jen pull request** a dotaz na jméno repa
  nálezy i PR, ale **ne soubory** — ty jsou všechny z jednoho otevřeného PR, takže by se vytáhly
  všechny naráz a v řádku by nebylo poznat proč. Dál: nálezy ze **všech** PR s otevřeným prvním,
  odmítnuté nálezy se nenabízejí, soubory
  jen z otevřeného PR, **filtr seznamu paletu nezužuje** (ověřeno vložením regrese — se
  `visiblePullRequests` test padá), `id` katalogu jsou jednoznačná i tehdy, když týž reviewer
  nahlásí totéž dvakrát (taky ověřeno regresí: s `Policy.key(of:)` místo indexu test padá), skok se
  dá vyžádat **dvakrát**, nález bez místa v kódu otevře tab `Nálezy` a **o skok nežádá**,
  nevyzvednutá žádost se uklidí s PR mimo seznam a `openSettings` se vrací **volajícímu**, aniž by
  se ve storu cokoli změnilo.

  **Rozřazení do dvou skupin (#336)** je nad storem, protože katalog ho dělá: vlastní PR do skupiny
  `Moje PR`, cizí do té první, PR agenta z `ownLogins` taky do mých, a **dokud login nedorazí, je
  všechno cizí** — to je ten test, který tvrdí, že se něco nestalo, jinak by paleta na okamžik po
  spuštění přehodila celý seznam a zpátky. K tomu, že vlastní řádek nese **týž cíl** (`.pullRequest`,
  po `↵` otevře záložku) i **týž podtitulek** jako cizí, a že dotaz najde obojí naráz.
- **Sonda palety se dvěma skupinami (#336)** — `CommandPaletteRenderProbe`, gated `PRISM_MEASURE`,
  cesta ven `PRISM_RENDER_DIR`. Vyrendruje kartu nad katalogem ze **storu** (diff z fixture, takže
  cesty souborů mají skutečný tvar) ve dvou podobách: zúžené na počty řádků ze sekce 09 návrhu
  (na srovnání vedle sebe) a nad celým katalogem, kde je vidět, že se pět skupin scrolluje.
  **Dotaz se do renderu dosadit nedá** — `query` je `@State` uvnitř `CommandPaletteView`, protože má
  zaniknout se zavřením palety —, takže sonda kreslí stav prázdného dotazu; zvýraznění shody v ní
  proto není. Paletu v běžící aplikaci navíc otevírá jedině ⌘K, a psát do cizí instance se
  v paralelním běhu nemá.
- **Měření hledání (#184)** — `CommandPaletteMeasurement`, gated `PRISM_MEASURE` jako měření
  layoutu. Nic netvrdí; existuje proto, že se katalog skládá **při každém stisku klávesy** a to
  rozhodnutí má být podložené číslem: 200 řádků 1,5 ms, 2000 řádků 17,6 ms.
- **`AppStore` — rozdělané review** — proti **skutečnému** `ReviewDraftStore` nad dočasnou
  složkou: on rozhoduje, co je po restartu, takže fake by ověřoval sám sebe. Pokrývá cestu
  od kliknutí po disk (komentář, verdikt, tělo, převzetí nálezu do těla i na řádek), a hlavně
  to, co se dá pokazit tiše: draft, který se **nezakládá** bez známé hlavy PR; prázdný
  komentář, který se zahodí a s ním i prázdný draft; zastarání po novém commitu, které text
  **nechá**; a že „nevím, jaká je hlava“ se za zastaralé nevydává. Čeká se točením přes
  `Task.yield()`, protože zápis běží v tasku.
- **`AppStore` — předvyplněný verdikt (#114)** — proti **skutečnému** `ReviewStore`
  i `ReviewDraftStore` nad dočasnou složkou, protože obsah disku je to, co rozhoduje.
  **Nejdůležitější test celého issue** je, že po doběhlém review a nule úprav je verdikt navržený,
  ale draft **neexistuje** — ani v paměti, ani v cache, ani po restartu. Vedle toho: blokující
  nález navrhne `requestChanges`, bez doběhlého review se nepředvyplní nic (a `sendBlock` dál
  hlásí `noVerdict`), moje volba přebije návrh a zrušení ho vrátí (přičemž draft, ve kterém nic
  nezůstalo, se maže), a na vlastním PR se návrh nenabídne, kdežto bez načtené konverzace ano.
  Nakonec to, co odejde: snímek z `submission(for:)` nese návrh s `verdictOrigin == .suggested`,
  **na disku pořád leží draft bez verdiktu**, a vybraná hodnota se návrhem nepřepíše.
- **Bubliny rozdělaných komentářů** — že komentář visí pod svým řádkem, že `left` sedne na
  **odebraný** řádek (tatáž past jako u vláken v #64), že se komentář na řádku mimo diff
  nekreslí, že se dva na jednom řádku neslijí a že pořadí je nález → vlákno → můj komentář.
  Plus kotva pro skok z panelu, včetně `left` a fallbacku na soubor.
- **Dotažení po pádu (#97)** — tři vrstvy. `TranscriptLocation` na **změřená** pravidla
  manglingu cesty: nejen `/` a mezery, ale všechno mimo `[A-Za-z0-9-]` (včetně podtržítka
  a diakritiky), pomlčky se neslučují a velikost písmen zůstává. `TranscriptStore` proti
  **skutečnému** transcriptu z veřejného sandboxu, zkrácenému na pět řádků — jsou v něm typy
  eventů, které ve `stream-json` nejsou (`queue-operation`, `last-prompt`, `attachment`), takže
  fixture zároveň ověřuje, že je parser přejde. A že v něm **není `result`**, tedy že se
  z transcriptu nikdy nedá vyčíst „doběhlo“.

  `AppStore` proti skutečnému `InterruptedRuns` i `ReviewStore` nad dočasnou složkou, protože
  celé issue je o tom, co přežije restart. To hlavní: nálezy jsou po startu zpátky, uloží se jako
  `interrupted` (ne `clean`), značka se zahodí, značka **bez** transcriptu se zahodí taky
  a značka **nad uloženým během výsledek nepřepíše**. Plus že neuložený běh si značku nechá
  a že se po doběhlém review značka nedrží — ten poslední chytil reálný závod mezi proudem
  událostí a ukládáním.
- **Symlinky v cache (#106)** — u `ReviewStore` totéž co u draftů od #65, protože je to táž
  hranice: odkaz na **složku** se nesleduje (to je ověření tvrzení, ne domněnka), odkaz na
  **soubor** se do výpisu nedostane a **spočítá se** do `unreadable`. Vedle výpisu i obě
  cílená čtení podle cesty: úklid odkaz nepřečte ani nesmaže, uložení běhu z něj neudělá
  záznam (a cíl mimo cache nechá být) a odmítnutí nálezu skončí chybou. Ověřeno **dočasně
  vrácenou regresí** — bez toho `load` cizí soubor přečte jako záznam a odmítnutí projde nad
  cizími daty.
- **`ReviewStore`** — proti skutečné dočasné složce, ne proti fake filesystému: kořen je
  injektovatelný, takže jde o pár kilobajtů, a ověřuje se to, na čem store stojí — `Codable`
  cesta na disk a zpět a chování `FileManageru`. Hodiny jsou `FakeTimeSource`, který se
  posouvá uspáním, takže třicetidenní lhůta se testuje v nulovém reálném čase. Round-trip
  `ReviewRecord` má vlastní testy včetně **každého případu** `ReviewRunOutcome` — `failed`
  nese asociovanou hodnotu a ta se z JSONu ztratí nejtišeji.
- **`Config`** — merge globální + per-repo, defaulty pro neznámé repo. U režimu navíc to,
  co se dá rozbít tiše: že vlastní `manual` přebije globální automat, že se takový záznam
  nesmaže jako „shodný s globálním“ a že se rozbitá hodnota srazí na `manual`, kdežto
  chybějící klíč vezme globální.
- **Jazyk nálezů** — u konfigurace výchozí čeština, override per repo a to, že se vlastní
  hodnota nesmaže jako shodná s globální (stejná past jako u režimu). U promptu naopak to,
  že o jazyku **mlčí** — kdyby se to vrátilo, stálo by to nálezy.
- **Prompt review ze šablony (#281)** — tři sady a **nejcennější tvrzení jsou o tom, že se nic
  nezměnilo a nedá se nic odebrat**.

  `ReviewPromptTemplateTests` (`Policy`, vyčerpávajícím výčtem):
  - **Výchozí šablona složí znak po znaku ten prompt, který aplikace posílala do #281.** Text je
    v testu **literálem opsaným z minulé verze**, ne odkazem na `ReviewPromptTemplate.standard` —
    porovnávat konstantu se sebou samou by prošlo i po přepsání textu. K tomu druhá strana téhož:
    `Configuration.standard` tu šablonu doopravdy nese (prázdná hodnota by se chovala stejně jen do
    chvíle, než se `standard` změní).
  - **Jádro je v poskládaném promptu i u šablony, ve které po něm není ani stopa** — a z druhé
    strany **výchozí šablona jádro sama nenese**. Bez toho druhého by se dalo jádro přesunout do
    šablony, kde by se dalo smazat, a první test by to nepoznal.
  - Prázdná šablona (i samá mezera) bere výchozí a **není to chyba**; dosazení na každém výskytu;
    oříznutí, aby v jednořádkovém promptu nevznikly dvě mezery; chybějící zástupný text
    pojmenovaný jednotlivě i oba naráz v pevném pořadí; hláška, která nese **který** zástupný text
    chybí **a proč**.

  `ClaudeCommandTests` — že běh bere prompt **ze šablony v požadavku** (ne z konstanty), že
  `Zkopírovat příkaz` skládá tentýž text toutéž cestou, a **že šablona nemá jak sáhnout na
  povolení**: nepřátelský text s `--allowedTools Write,Edit,Bash` skončí v jednom argumentu za
  `-p` a seznam přepínačů zůstane přesně ten z konstant (tvrdá podmínka č. 2). `RecheckCommandTests`
  k tomu drží, že požadavek kontroly šablonu nemá kam propašovat a její prompt z ní nevzniká.

  `AppStorePromptTests` — šablona z konfigurace dojede až k běhu (`FakeReviewRunner.requests`),
  prázdná proběhne s výchozím textem, a **s neplatnou se nespustí nic**: fake reviewer nedostane
  žádný požadavek a fáze je `failed` s tou samou větou, jaká stojí u pole v nastavení.

  V `ConfigurationTests` k tomu chybějící klíč (výchozí text), prázdný řetězec (platná hodnota),
  **hodnota jiného typu, která čtení položí** (číslo, pole i objekt — jeden případ by prošel
  i implementaci hlídající zrovna ten jeden typ), **`null` jako chybějící klíč** (vědomě: je to
  výslovné „nic tu není“, ne nesrozumitelná hodnota — a test je tu, aby se ta úvaha nemusela dělat
  znovu) a že klíč napsaný pod repem nedělá nic.

  Ověřeno **vloženou regresí** — znak navíc ve výchozí šabloně, nepřipojené jádro a vyhozený
  `guard` v `AppStore` naráz: padne **22 tvrzení v 15 testech** napříč všemi třemi sadami.

  **Jak to vypadá, se ověřilo renderem** — `ReviewPromptRenderProbe` (gated `PRISM_MEASURE`)
  vykreslí stránku `Review a skilly` ve čtyřech stavech promptu (výchozí, vlastní, chybějící
  zástupný text, prázdná), ve dvou šířkách obsahové části okna (669 a 509 bodů) a v obou režimech.
  Tři z těch stavů se klikáním vyrábějí těžko a **chybějící zástupný text** je zrovna ten, kvůli
  kterému sonda vznikla. Chytila jednu reálnou chybu: náhled i jádro se ve `Form`u srazily na tři
  řádky a zbytek promptu uřízly třemi tečkami — tedy náhled, který zamlčí zrovna to, kvůli čemu se
  do něj kouká. Léčba je `fixedSize(horizontal: false, vertical: true)`.
- **Zadání pro reviewera (#120)** — čtyři sady a **nejcennější tvrzení jsou o tom, co se
  nestane**: že se věta o zadání nepřipojí, dokud soubor není, že se reviewerovi nepřidalo ani
  jedno povolení, a že review **doběhne**, i když se zadání nepodaří připravit.

  `ReviewIntentTests` (`Policy`, vyčerpávajícím výčtem) — odkazy se testují **na skutečných
  linkbacích**, ne na vymyšlených řetězcích, a jsou k tomu dvě nové gh fixtures:
  - `gh/pr-body-linear.md` — popis skutečného PR (`metalbear-co/mirrord#4702`): markdownový
    odkaz **se slugem**, vedle něj odkazy na GitHub, Slack a PostHog. Vyjít má **jeden**.
  - `gh/comment-linear-linkback.md` — skutečný linkback od `linear[bot]`
    (`zcash/zcash-swift-wallet-sdk#1893`): HTML, sedm odkazů, adresy **bez slugu** a identifikátor
    v adrese **i** v textu odkazu — takže naivní hledání by je vrátilo čtrnáctkrát. Je to zároveň
    doklad, že Linear adresu bez slugu sám používá, tedy že normalizovat na ni je v pořádku.

  Ty dva tvary jsou schválně oba: liší se přesně v tom, co je snadné pokazit, a ruční literál by
  je zjednodušil na jeden. K tomu vyčerpávající výčet tvarů, ve kterých odkaz může v textu stát,
  výčet toho, co se **nesmí** vytáhnout (cizí tracker, Linear mimo issue, chybějící číslo nebo
  klíč, sousední doména `notlinear.app`), dedup přes tři různé zápisy téhož issue, a že `AJDA-892`
  a `AJDA-8920` **nejsou totéž** (tatáž past jako u prefixu `42-` proti `421-`).

  U složeného souboru: že se **nic nezakládá**, když se nic nesehnalo (tři podoby prázdna), že
  všechny tři sekce zůstávají i prázdné, že soubor sám o sobě říká, že jeho obsah nic nepřebíjí,
  a že věta o chybějícím popisu **nerozhoduje** mezi „autor nenapsal nic“ a „nedotáhlo se“.

  `ReviewIntentStoreTests` — že soubor leží **vedle** stromu a ne uvnitř (kontroluje se cesta obou),
  že se zakládá chybějící složka, že se nezakládá nic bez obsahu, že nový zápis starý přepíše
  **celý** (kratší obsah by jinak nechal zbytek starého zadání), a že **zápis přes symlink ven
  z cache neprojde** (tvrdá podmínka č. 3 — a cizí složka po pokusu zůstane prázdná). K tomu
  `existingFile` pro `Zkopírovat příkaz`: nevydá zadání jiné hlavy ani jiného PR.

  **Symlink se testuje ve dvou podobách, a ta druhá je cennější.** Odkaz na *složce* v cestě
  (`worktrees/<owner>/<repo>`) chytá `contains`; odkaz na **samotném souboru** ne, protože `contains`
  rozbaluje symlinky na obou stranách a cíl vyjde rovný cíli. Nejcennější tvrzení je proto to, že
  `existingFile` odkaz **nevydá** — vrácená cesta jde do promptu a reviewer ji otevře `Read`em, takže
  by ho poslala čtením mimo cache. Nález Copilota na #352; do té doby to hlídal jen `contains`.

  U zápisu se to doměřilo, ať se nezakazuje naslepo: `write(to:options: .atomic)` odkaz **nahradí**
  souborem a cíl nechá být, kdežto **bez** `.atomic` ho přepíše. Zápis tedy díra nebyl — ale visel na
  příznaku, ne na vyjmenované kontrole, takže `isSymbolicLink` je i tam a test to tvrdí obsahem cíle
  (`"PŮVODNÍ"` po pokusu o zápis).

  `ClaudeCommandTests` — že se argumenty se zadáním a bez něj liší **jen** textem za `-p`, že do
  promptu jde **cesta a ne obsah**, a že kontrola nálezů (#150) zadání nenese. Obě konstanty
  povolení jsou v testu zapsané **literálem**, takže přidaný MCP nástroj spadne tady.
  `ReviewPromptTemplateTests` k tomu drží složený prompt se zadáním **znak po znaku proti
  literálu** — a proti druhému literálu bez zadání; cesta se zadáním se **nepřidala do `compose`**,
  protože tím by se hlídal nový prompt proti sobě samému.

  `AppStoreIntentTests` — že popis dojede k session jako soubor, že odkaz z popisu se do souboru
  zapíše, že **všechny skilly jednoho běhu dostanou tentýž soubor**, že PR bez popisu zadání
  nedostane a **není to porucha** (hláška se neobjeví), a hlavně že **nepovedený zápis review
  nepoloží**: session se spustí, záznam se uloží, `intentFile` je `nil` a v okně stojí hláška.
  Selhání zápisu se vyrábí tím, že na místě souboru už leží **složka**.

  Ověřeno **vloženou regresí** — `ClaudeCommand.prompt(for:)` zapomene `request.intentFile`,
  selhání zápisu se spolkne `try?` a `allWorktrees()` odfiltruje `.md`: padne **5 tvrzení
  v 5 testech** napříč `ClaudeCommandTests`, `AppStoreIntentTests` a `CacheEvictionTests`.
- **Text issue a komentáře pod PR (#345)** — pět sad, a to nejcennější je tady jedno tvrzení:
  **„issue nic neříká“ a „text se nedotáhl“ nesmí vypadat stejně**. Dva ze tří tvarů selhání
  vypadají jako úspěch (`exit 0`, `result` se `success`), takže test nad vymyšleným JSONem by se
  dal napsat tak, aby prošel nad rozborem, který se v reálu mýlí.

  **Tři tvary selhání se proto testují na skutečných streamech** z průzkumu — nové fixtures
  `stream-json/intent-server-missing.jsonl`, `intent-server-failed.jsonl`
  a `intent-tool-denied.jsonl`; redakce `hook_response` je tatáž jako u fixtures z #12 a jinak jsou
  bajt po bajtu, jak je CLI vypsalo. Testy u nich netvrdí jen výsledek, ale i **že je to doopravdy
  ten zrádný tvar**: že ve streamu stojí `"subtype":"success"`, že v `result` eventu **není klíč
  `result`**, a že próza modelu („žádný Linear MCP server není připojen“) se **nikam neuložila**.

  **Úspěšné dotažení fixture nemá a je to napsané v testu i v `docs/claude-cli.md`**: odpověď nese
  celý text firemního issue a ten do fixtures nepatří. Tvar eventů kolem něj drží ty tři selhané
  streamy, takže inline zbývá jen **náš vlastní formát** — značky. Rozbor nad skutečnou úspěšnou
  odpovědí se ověřil **spuštěním**: jeden běh `claude -p` s argumenty, které skládá
  `IntentTextCommand`, a dočasný test nad jeho streamem ve scratchpadu (`gap == nil`, 2 359 znaků
  textu, `num_turns: 3`, $0,3099, 21,4 s). Ten test se po ověření smazal — ukazoval na scratchpad.

  `IntentTextCommandTests` — vedle těch tří tvarů ještě: že povolení jsou **dva nástroje**
  a neobsahují `Write`, `Edit`, `Bash`, `ReportFindings` ani `Skill`, že `--disallowedTools` je
  tatáž konstanta (a **literál**, aby o její změně byla řeč), že `--max-turns` je 6, že se model
  nevynucuje; a u čtení odpovědi, že se próza před první značkou zahodí, že se **neznámé id zahodí
  i s textem** (jinak by se nalepil na cizí sekci), že značka se páruje bez ohledu na velikost
  písmen, že prázdná značka není dotažené issue, a že odpověď s `CRLF` se rozdělí.

  `ClaudeIntentTextFetcherTests` — že se **bez odkazů session nepustí** (boot je reálné peníze), že
  nespuštěná binárka a timeout nesou důvod dál (`.sessionFailed`, ne prázdný výsledek), že
  **nenulový exit kód rozbor streamu nepřeskočí**, a že argumenty jdou do procesu z `IntentTextCommand`.

  `ReviewIntentTests` — že každý ze šesti důvodů má v souboru **vlastní větu** a že se ty věty
  doopravdy liší (`Set(texts).count == texts.count`); že se text páruje **podle `id`, ne podle
  pořadí** (test to čte podle poloh v souboru: věta o chybějícím textu patří prvnímu, text druhému);
  že částečné dotažení se pozná **po issue**, ne za celek; a že selhané komentáře jsou v souboru
  napsané, ale **samy soubor nezakládají**.

  `AppStoreIntentTests` — že **odkaz z komentáře pod PR** se do zadání dostane (to je ten častý
  případ, kvůli kterému #120 vzniklo), že se **bez jména nástroje v konfiguraci nic nepustí**
  a je to vidět na ose, že **bez odkazů se neptá nikdo a nic se nehlásí**, že příznak nese **každá**
  dráha běhu (dvě sady skillů) a že doběhlou dráhu **nezhorší**, a že selhaný dotaz na komentáře
  review nepoloží. Od nálezu Copilota na #388 k tomu i to, že **nepovedený zápis na osu nic
  nepošle**, i když by gap jinak byl — reviewer nedostal soubor vůbec, takže věta „dostal jen
  odkazy“ by tvrdila víc, než data unesou; hlásí to stavový řádek.

  `ReviewerLaneTests` a `StoredTimelineTests` — že příznak **osu neposouvá** (dráha jen s ním
  zůstane `queued` s jedinou fází), že **u syntetických drah je `nil`**, že **přežije restart**
  (round trip `StoredTimeline`) a že osa, ve které je jen on, se **nedoplní na doběhlý běh**.
  `ReviewerLaneTextTests` k tomu drží českou prózu: šest různých vět, krátký odznak a stav serveru
  ve větě vidět.

  Ověřeno **vloženou regresí**, dvakrát:
  - `parse` přeskočí kontrolu serveru a jde rovnou na odpověď → padnou **4 testy** nad skutečnými
    streamy (`serverUnavailable` vyjde `noAnswer`, a u nepřihlášeného serveru se navíc **vezme text**,
    který v odpovědi je);
  - `result?["result"] as? String ?? ""` místo `guard let` → **nepadne nic**, a to je zapsané
    i v kódu: prázdný text nevydá ani jednu značku, takže skončí stejným `.noAnswer`. Explicitní
    `guard` tam zůstal jako čtení, které se dá bezpečně rozšířit, ne jako mechanismus, na kterém
    dnes něco stojí.
- **Časový limit běhu (#320)** — tři sady a **nejcennější tvrzení je zase o tom, že se nic
  nezměnilo**: patnáct minut je hodnota, se kterou aplikace běžela do #320, a zavedení nastavení ji
  nesmí posunout.

  `ReviewTimeoutTests` (`Policy`, vyčerpávajícím výčtem):
  - **Výchozí limit se porovnává s číslem, ne s `ReviewTimeout.standardMinutes`** — konstanta sama
    se sebou projde i po přepsání. K tomu druhá strana téhož: `Configuration.standard` tu hodnotu
    doopravdy nese a `resolved(for:)` z ní vydá 900 sekund.
  - **Výchozí hodnota leží uvnitř mezí.** Kdyby ne, srazila by se — a aplikace by po zavedení pole
    běžela s jiným limitem než před ním, aniž by to kdokoli napsal.
  - **„Bez limitu“ nejde nastavit ničím**: nula, záporné číslo, `Int.min` i `Int.max` skončí uvnitř
    rozsahu. Vypsané jsou i obě hranice a hodnoty těsně vedle nich.
  - **Co hláška slibuje, to se použije** — `problem.applied` se pro každou hodnotu mimo meze
    porovnává s tím, co vrátí sráření. Dvě místa, kde se sráží, by se rozešla a v okně by stálo
    jedno, běželo by druhé.

  `ClaudeReviewRunnerTests` — že limit **dojede z požadavku až k procesu** (`FakeProcessStreamer`
  si ho kvůli tomu od #320 pamatuje) a že požadavek bez vyplněného limitu běží s patnácti minutami.
  Runner vlastní pole nemá, takže je to jediné místo, kde se to dá zkontrolovat.

  `AppStoreTimeoutTests` — limit z konfigurace dojede k běhu, override repa přebije globální,
  hodnota mimo meze dojde **sražená** (jinak by se strop dal obejít zápisem pod repem), **rozjeté
  review doběhne s limitem, se kterým začalo** (soubor se přepíše uprostřed běhu a `resolved` už
  hlásí novou hodnotu, ale požadavek drží tu starou) a **kontrola nálezů běží s tímtéž limitem**.

  V `ConfigurationTests` k tomu chybějící klíč (patnáct minut), přečtení hodnoty, **hodnota jiného
  typu, která čtení položí** (řetězec, pole i objekt), **číslo mimo meze, které soubor nepoloží
  a v konfiguraci zůstane syrové** (sráží se až `resolved`), override per repo, `nil` jako „ber
  globální“ a override mimo meze sražený týmž místem jako globální.

  Ověřeno **vloženou regresí** — posunutá výchozí hodnota, runner beroucí vlastní konstantu místo
  `request.timeout` a `resolved(for:)` bez sráření naráz: padne **18 tvrzení v 10 testech** napříč
  všemi třemi sadami.

  **Jak to vypadá, se ověřilo renderem** — `ReviewTimeoutRenderProbe` (gated `PRISM_MEASURE`)
  vykreslí obě místa, kde se limit nastavuje, v osmi stavech (globálně výchozí, zvednutý, pod mezí,
  nad mezí; repo bez override, bez override nad sraženou globální hodnotou, s vlastním limitem
  a s override mimo meze), ve dvou šířkách obsahové části okna a v obou režimech. **Stavy mimo meze
  se klikáním nevyrobí vůbec** — pole je ořezává —, a přitom je to zrovna to, kvůli čemu stížnost
  existuje. Šestý stav přibyl po nálezu Copilota: „Bere globální: 240 min“ nad během, který poběží
  60, je text, který tvrdí víc, než data unesou.
- **Vzhled okna (#278)** — přečtení obou vynucených hodnot, chybějící klíč i překlep (obojí znamená
  `system`, ne pád), a že překlep nezahodí zbytek souboru. K tomu dvě tvrzení, že se něco
  **nestalo**, protože vzhled je vlastnost člověka, ne repa: v zapsaném JSONu je klíč `appearance`
  právě jednou a v záznamu repa není, a klíč napsaný pod repem se nepromítne nikam. Kdyby přibyl do
  `RepositoryConfig`, jedno repo by přebarvilo celé okno — a poznalo by se to až v provozu.
- **Cesta vzhledu do aplikace (#278)** — `AppStoreAppearanceTests` na tu jedinou cestu
  (`AppStore.apply(_:)`): volba ze souboru při načtení, přepnutí z railu, přežití restartu a překlep,
  který skončí na `system`. K tomu dvě věci, které se **nesmí stát**: volba, která už platí, nesmí nic
  zapsat (hlídá se datum souboru — nabídka hlásí i výběr toho, co platí, a zápis beze změny by
  přepsal ručně editovaný soubor), a **selhaný zápis nesmí projít tiše** (`appearanceFailure` je
  vidět a vzhled se nepřepnul). Cíl je **fake**, ne `NSApp`: živý cíl je hostitel testů, takže
  vynucený režim by přetekl do render sond, které si režim nastavují samy.

  **Že store bez cíle na `NSApp` nesáhne, se od #367 netvrdí nad globálem, ale nad zdrojáky**
  (`GlobalAppearanceTests`) — původní podoba porovnávala `NSApp.appearance` před a po a byla to
  jediná nedeterministická věc v téhle oblasti; podrobnosti a naměřená čísla v sekci *Globální stav
  procesu se v testech neměří*. V `AppStoreAppearanceTests` po ní zůstalo to, co je vlastnost storu:
  volba se přečte i bez cíle a chybějící cíl **není chybový stav** (nic se nehlásí). Vedle toho
  `AppAppearanceTests` na mapování — `.light` → `aqua`, `.dark` → `darkAqua` a hlavně, že `nil`
  (tedy „nevynucuj nic“) vyjde **jedině** u `.system`; jinak by volba tiše nezabrala a byla by
  k nerozeznání od výchozího stavu.
- **Rail a přepínač v něm (#278)** — `SidebarRailTests`. Dvě tvrzení jsou negativní: vzhled **není**
  `RailSection` (výčet sekcí zůstává tříprvkový) a v paletě ⌘K se **nenabízí jako sekce** — kdyby byl
  jeho případem, přišel by tam sám, protože položky sekcí se staví z `allCases`. Zbytek je **poloha
  z bitmapy**: oddělovač 20 × 1 bod vystředěný, jak ho má návrh, ikona pod ním ve stejné svislici
  jako ikony sekcí (střed 26 na railu o 52 bodech) a v témž rámu 34 × 30. K tomu **srovnatelná
  velikost všech tří ikon** (16 × 16, 15 × 16, 16 × 16, práh 2 body): klik je vyměňuje na tomtéž
  místě, takže větší rozdíl znamená tlačítko, které při cyklení poskakuje. Rámečky by na tyhle chyby
  neodpověděly — `fittingSize` railu je pevných 52 bodů a accessibility tree se v okně mimo obrazovku
  nenaplní. Vyzkoušené vložením regrese: se stylem `.borderlessButton` vyjde střed 25 a test spadne.
- **Odznak v railu (#366)** — `RailBadgeTests`, tři třídy tvrzení nad **bitmapou**: kde odznak leží
  (nesmí opustit rám ikony 9–43 ani vyčnívat nad jeho horní hranu), jakou má barvu (`crit`, **žádný
  akcent**, a číslo v barvě plochy okna) a že se u nuly a u `nil` **nekreslí** — s protějškem, že
  s počtem 1 se nakreslit musí, jinak by sada vycházela zeleně nad odznakem, který zmizel celý.
  K tomu rozměr červené plochy (20 × 14, tolerance bod na stranu kvůli vyhlazeným krajům) a kontrast
  **tokenů** v obou režimech (5,36 a 5,50 při hranici 4,5), včetně tvrzení, že bílá by v tmavém
  režimu byla **horší** — to je záznam rozhodnutí, ne kontrola.

  **Barva se porovnává s nakreslenou, ne s tokenem, a je to změřené**: bitmapa
  z `bitmapImageRepForCachingDisplay` je v profilu displeje (`Barevný LCD`), takže `crit` v ní vyjde
  `0.799/0.292/0.272` proti `0.812/0.133/0.180` v sRGB — tedy 0,18 daleko. Tolerance, která by tohle
  přijala, by přijala i akcent, takže se tokeny vykreslí **týmž harnessem** jako vzorník čtyř ploch
  a srovnává se kresba s kresbou. Vzorník se drží mezi testy (`drawnTokens`), aby renderů nebylo
  dvakrát tolik — pod paralelní zátěží je každý render navíc práce v procesu, ve kterém se o písmo
  přetahují stovky suit (viz *Metrika písma je tentýž kořen v jiné podobě (#407)*).

  **Vyzkoušené vložením regrese ze dvou stran.** Se starým odznakem (akcent + `offset(x: 6, y: -2)`)
  padne 5 testů ze 6 — barevná tvrzení na tom, že v railu není ani jeden červený pixel. Se **samotným**
  `offset(x: 6, y: -2)` a ponechanou červenou padne právě tvrzení o poloze (`46 > 43`), takže je
  vidět, že poloha se měří nezávisle na barvě.
- **Kapsle stavu z návrhu (#348)** — `DesignPillTests`. Že je to **mono**, se pozná na tom, že
  `TextWidth.pill("iii") == TextWidth.pill("WWW")` — a měřidlo to umí rozlišit, protože v UI fontu
  téže velikosti se ta dvě slova liší. Metrika se měří na `fittingSize` hostované kapsle proti sazbě
  (text + 2 × 7 a řádek + 2 × 2), ne proti konstantám v testu. Dvě tvrzení jsou o **ceně mono**:
  kapsle nesmí být vyšší než ta před #348 (řádek 12 proti 13, takže je o bod **nižší**) a nesmí
  vyrůst o víc než 10 bodů na šířku (naměřeno 4 až 9,4 na čtyřech stavech PR) — kdyby se sazba
  omylem zvedla na 12, spadne to dřív, než se začne hledat v přetečení hlavičky.

  **Že tu kapsli kreslí hlavička karty popisu, se tvrdí nad zdrojáky**, ne za běhu: barvy chipu
  (`raised` na `chrome`) jsou od sebe devět dvěstěpětapadesátin, takže se v bitmapě nedají rozlišit.
  Tatáž konstrukce jako `GlobalAppearanceTests` a `SingleWayOutTests`, včetně zahazování řádkových
  komentářů. Druhý guard téže třídy tvrdí, že sazbu **nikdo nepíše mimo `DesignPill.swift`** — do
  #348 stála na sedmi místech a šest kopií je přesně ten stav, ve kterém se sedmá rozejde potichu.
  Vyzkoušené vložením regrese: s vrácenou sazbou `11 bez mono` v `OverviewView` padne.

  **Guard hlídá obě podoby zápisu řezu** (nález Copilota na #406): SwiftUI
  `size: 10.5, weight: .semibold` a AppKitovou `ofSize: 10.5, weight: .semibold`. První verze znala
  jen tu první — a minula tím zrovna tvar, který `SinceLastVisitView` do #348 doopravdy mělo, tedy
  hlídala něco jiného, než co o sobě tvrdila. Velikost se u toho čte z `DesignPill.fontSize`, ne
  jako zapsaná desetina. Ověřeno vložením regrese v **obou** podobách, každá zvlášť.

  Že se hlavička v úzkém tabu nerozsype, tady **není** — na to je `OverviewWidthTests` (pásmo
  128–1180 bodů). Obojí je potřeba: přetečení je jiná chyba než jiná sazba.

  **Výška řádku je z `FontMetric`** (`pillLine`, `previousLine`), ne z vlastního `NSLayoutManager`u.
  Do #407 se tady čítala **jednou za test** (#348) a bylo to léčení příznaku v nové sadě: každá další
  sada by to musela vědět taky. Poznat se to dá jedině plným během — v jedné dávce takhle spadly
  `CommitPanelRoomTests` a `LogTailHeightTests` (o 36 bodů, tedy o tři řádky po 12), obojí zeleně
  v samostatném běhu. Proč to je jedno měřidlo a co ta nula je, viz *Metrika písma je tentýž kořen
  v jiné podobě (#407)*.

  **Od #404 je v téže sadě guard na zbylých pět míst** — že berou `designPill` **a** že v tom
  souboru nezbyla druhá kapsle. Obojí je potřeba: samotné „bere“ by zůstalo pravdivé i tehdy, kdyby
  vedle nové kapsle zůstala jedna se starým odsazením, a přesně takhle v `FindingCardView` ležel
  odznak kontroly, který se u #348 přehlédl.

  Hlídá se **`in: .capsule` mimo `designPill`**, ne zapsaná stará sazba, a to schválně: `.caption2`
  i `10,5` v těch souborech zůstávají (nesou prózu vedle odznaku), kdežto kapsli tam po #404 kreslí
  jedině `designPill`. Guard na `padding(.horizontal, 5)` by naopak spadl na první nesouvisející
  odsazení, tedy hlídal by něco jiného, než co o sobě tvrdí. Povolená je **jedna** kapsle
  v `ConversationEntryView` — `Bot` je `.botchip` z návrhu, tedy schválně nemono, a má na to vlastní
  tvrzení, protože „sjednotit kapsle“ je zadání, při kterém se převede omylem. Ověřeno vložením
  regrese (vrácená ruční sazba `vyřešeno` v `ThreadBubbleView`).
- **Rozměry a kontrast kapslí po #404** — `PillTypesettingTests`. Dělí se od `DesignPillTests`
  schválně: tam se tvrdí **kdo** kapsli bere, tady se měří, co se tou změnou pohnulo v okně.

  **Šířka** se měří tam, kde je místo spočítané, ne odhadem: kapsle ve sloupci závažnosti tabulky
  (`Policy.findingTableLayout(availableWidth: 648).severity`, tedy 92 bodů — `irelevantní` má 86)
  a odznak fronty **v řádku, ne sám za sebe**. To druhé je podstatné: `fittingSize` na tu otázku
  neodpoví, protože rámec nasazený zvenčí je tvrdý a hostující view pak hlásí tu šířku, kterou
  dostalo. Měří se proto `onGeometryChange` uvnitř hostovaného okna nad řádkem, který má vedle
  odznaku pružný titulek s `lineLimit(1)` — tedy tu trojici, ve které se o místo pere.

  **Vložená regrese vyloučila i první podobu toho testu**, a je to ta poučnější polovina:
  `lineLimit(1)` sám o sobě zalomení opravdu zabrání, takže test, který měřil jen **výšku**,
  procházel i s odebraným `fixedSize()`. Zkrácení je jiná vada než zalomení a měří se šířkou — bez
  `fixedSize` se dva nejdelší stavy srazily o **20 a 33 bodů**.

  **Výška bubliny** se hlídá stropem, ne rovností: měří se dvě bubliny nad týmiž daty (kategorie
  `correctness` a `style`, tedy s kapslí `blokuje` a bez ní) a kapsle smí bublinu zvednout nejvýš
  o ten jeden bod, kterým se liší od prózy vedle sebe. Číslo se u toho nevymýšlí — kapsle je 16
  bodů, `.caption2` 13.

  **Kontrast se měří z bitmapy, ne z tokenů** (#393, #366): podklad je **nejčastější barva** ve
  středním pásu nakreslené kapsle (tedy wash složený nad plátem přesně tak, jak se nakreslil),
  odstín má vlastní kresbu v témž vzhledu. Odečítat podklad z polohy by znamenalo tvrdit, kde
  v bitmapě co leží, a to se rozbije při první změně odsazení. Vedle kontrastu je druhé tvrzení,
  že se **odstín dostane do textu**: nejsytější pixel v kapsli musí být blíž nakreslenému odstínu
  než podkladu. Bez toho by kontrast mohl projít i u kapsle, které se `foregroundStyle` vynechalo —
  a zrovna to je u odznaku `já` nová věc (do #404 barvu textu neměl).

  **Nejsytější pixel je dolní odhad**, ne barva glyfu: při 10,5 semibold nepokryje stopa pera celý
  pixel, takže se z něj kontrast počítat nedá (naměřeno 1,63 až 2,91 tam, kde nakreslené barvy dají
  3,65 až 4,08). Proto se dvě otázky rozdělily — legibilitu měří **plné plochy**, přítomnost
  odstínu v textu ten pixel.

  Prahy jsou **per kapsle a naměřené**, ne kulaté. Do #432 byly čtyři z nich pod třemi, protože ty
  kapsle brala systémová škála (`vyřešeno` 1,63, `schválil` 1,70, `vyžádal změny` 2,52,
  `3 nálezy · 1 blokuje` 2,70); #404 to neměnilo, jen změřilo a zapsalo. **#432 ten převod udělalo**
  a tabulka u testu má od té doby dva sloupce — před a po (1,63 → 3,05, 1,70 → 3,19, 2,52 → 3,49,
  2,70 → 3,77) —, takže se hlídá výsledek, ne jen to, že se nic nezhoršilo. Přibyly u toho dvě
  kapsle, které #404 neměřilo: `3 nálezy` (systémová oranžová byla z celé škály nejhorší, **1,85**
  → 3,36) a `čisté` (1,80 → 3,44). `já` má vlastní tvrzení s prahem 8,0 (naměřeno 12,27 / 8,40),
  protože společný práh z tabulky by výměnu `ink` za `ink3` nechytil.

  **V tmavém režimu je to u tří kapslí výměna dolů** (nejvíc `čisté`, 6,26 → 5,55) a je zapsaná
  jako naměřená, ne zamlčená: tmavá větev palety je tmavší než systémová škála, takže se platí
  rezervou tam, kde jí bylo dost. Nejnižší hodnota po převodu je 3,05 proti 1,63 před ním.

  **Vzhled se vynucuje na vlastním okně** (#367), ne na `NSApp`.
- **Sémantická škála je z palety, ne ze systému (#432)** — `StatusScaleTests`. Dvě různá tvrzení
  vedle sebe, protože ani jedno nestačí samo: **nad zdrojáky** (`App/` neobsahuje `.green`, `.red`,
  `.yellow` ani `.orange` — kolikrát je něco zapsané, se za běhu zjistit nedá; tatáž konstrukce
  jako `GlobalAppearanceTests` a `SingleWayOutTests`, včetně zahazování řádkových komentářů) a **na
  hodnotách** (`ReviewStateAppearance`, `VerdictAppearance` a `PullRequestStateAppearance` vracejí
  doopravdy token, ne „něco, co není systémové“).

  Tři věci na tom nejsou zjevné:

  - **Hledá se s koncem identifikátoru za jehlou** (ne písmeno, číslice ani podtržítko), jinak
    `color.redComponent` a `.redacted` vyjdou jako
    porušení pravidla. Na to, že to hledání doopravdy hledá, je vlastní tvrzení — „nikde nic
    nenašel“ projde i tehdy, když je sonda rozbitá.
  - **Číslo řádku musí být z původního souboru.** První podoba hlásila číslo v textu bez komentářů,
    tedy o desítky řádků mimo (vložená regrese poslala na řádek 118 místo 186) — hláška, která míří
    špatně, je horší než hláška bez čísla.
  - **Hlídá se `App/`, ne `Tests/`.** Testy o systémových barvách tvrdit **musí**
    (`color != .green` je to, co spadne, když se převod vrátí), takže by je stejný zákaz zakázal.

  **Ověřeno vloženou regresí z obou stran**: s vrácenou `.green` v `ThreadBubbleView` spadne guard
  nad zdrojáky, a s vrácenou systémovou barvou ve vzorku `PillTypesettingTests` spadne práh (1,63
  proti 3,0). Jedno bez druhého by nestačilo — guard nad zdrojáky o čitelnosti neříká nic a práh
  ve vzorku nevidí, co kreslí okno.
- **Sonda sazby kapslí (#404)** — `PillRenderProbe`: všech pět míst na **jednom plátně** v obou
  režimech, aby se dalo vidět, že to je jedna rodina prvků. **U #432 posloužila i na barvy**:
  tentýž běh před převodem a po něm dá dva snímky, ze kterých je rozdíl vidět bez čtení čísel —
  a hlavně je z nich vidět, že se nezměnilo nic dalšího. Na plátně je i dvojice, která se
  sjednotit **nemá** (`Bot` a `.state-chip` v hlavičce PR) — bez ní by z obrázku nešlo poznat, jestli
  je nemono chip vada, nebo záměr. Karta nálezu se kreslí v **300 bodech** (šířka panelu), ne v šířce
  plátna: v širokém místě se o nic nepere. Pouští se ručně (`TEST_RUNNER_PRISM_MEASURE=1`).
- **Cyklus a ikony režimů (#278)** — `AppAppearanceTests`: pořadí `světlý → tmavý → podle systému`
  a hlavně to, že je **uzavřené a projde všechny tři** (jinak by se do jednoho režimu klikáním nešlo
  dostat), tři **různé** ikony a to, že všechny tři symboly v systému existují — chybějící SF Symbol
  se v okně kreslí jako prázdno, tedy tlačítko, ze kterého zmizel stav.
- **Podpis bloku kódu (#157, #278)** — `DiffBlockSignatureTests`: světlý a tmavý režim, jiný obsah,
  jiný jazyk a blok bez jazyka musí mít **různý** podpis, tentýž stav ten **samý**. Kdyby se dva
  stavy sešly, blok by se přeskočil jako nezměněný a v okně by po přepnutí vzhledu zbyly barvy
  z předchozího režimu — potichu, protože text ani jazyk se nezměnily.
- **Překlad** — `TranslationCommand` na každou podobu nesmyslu, kterou model umí vrátit:
  prohozená `id`, `id` mimo rozsah, chybějící položka, code fence, prázdno, položka bez
  `summary`. `ClaudeFindingTranslator` proti fake procesu na to, že nenulový exit ani
  rozbitá odpověď nevyhodí chybu. `AppStore` na celou cestu: přeložené nálezy na disku
  i po restartu, angličtina bez volání, čisté review bez volání, selhaný překlad
  s originály a — to hlavní — **nepřeložený nález, který nesmí zmizet vedle přeložených**.
- **`Policy.automaticallyReviewable`** — automat vs. manuál, už zvážený PR, změněný
  `updatedAt`, běžící PR, draft a prázdný seznam.
- **`AutoRunLedger`** — proti skutečné dočasné složce, protože jde právě o to, že
  počitadlo **přežije restart**. Plus nový den, nulový limit (vypnuto, ne „bez omezení“)
  a rozbitý soubor, který automat umlčet nesmí.
- **Opakování jednoho revieweera (#149)** — proti `FakeReviewRunner`u, který si pamatuje
  **každé** zadání: to hlavní není, že se pustil ten správný, ale že se ostatní **nespustily**
  (`requests.map(\.key.skillID) == ["reviewer-b"]`). K tomu, že uložené nálezy ostatních
  zůstanou (skutečný `ReviewStore` a druhý store nad toutéž složkou), že jim zůstane osa
  — ověřeno **dočasně vloženou regresí**, po které ten test spadl — že za běžícího se
  považuje jen opakovaný reviewer, že se do běžícího review nedá vklínit další běh a že
  prázdná podmnožina nespustí nic.
- **Cena a útrata (#148)** — tři vrstvy. `StreamParser` proti **všem** fixtures ze skutečných
  běhů (cena, trvání i počet kol se ověřují číslem, protože jen tak je vidět, že se čte
  `duration_ms` a ne `duration_api_ms` vedle něj), a hlavně že **zabitý běh cenu nemá a nemá
  ani nulu**. K tomu boolean místo čísla a záporná hodnota, tedy dva způsoby, jak by se do
  součtu dostal nesmysl.

  `SpendLedger` proti skutečné dočasné složce jako `AutoRunLedger`: sčítání, **přežití
  restartu**, nový den od nuly, rozbitý soubor a to, že se běh bez ceny počítá jako
  **neznámý**, ne jako nula.

  `AppStore` na celý řetěz — cena z běhu se propíše do útraty i do uloženého záznamu, přežije
  restart, dostane ji osa revieweera, a bez účetní knihy se **netvrdí nic**. `ReviewRecord` má
  vlastní test na to, že se **starší běh bez ceny načte** (inline JSON): kdyby se na klíč sahalo
  povinně, přišel by celý záznam o nálezy kvůli poli, které v něm být nemůže.
- **`AppStore` — automatický režim** — celý řetěz od tiku po session: automat spustí,
  manuál ne, druhý tik nad stejným commitem session **neutratí**, komentář (jiné
  `updatedAt`, stejný `headSha`) taky ne, nový commit ano, a denní limit pozastaví.
- **`Policy.projectLanguages`** — jednojazyčné projekty (PHP, Go, TS, Swift), smíšený
  s pořadím podle váhy, zatoulaný soubor pod prahem, marker bez souborů, prázdný repozitář
  a repozitář bez zdrojáků. Plus to, co se snadno rozbije: že samotný `package.json`
  JavaScript nezpůsobí a že při shodě počtů rozhoduje jméno.
- **`AppStore` — jazyk repa** — fake checkout dodá výpis souborů, **skutečný** `ConfigStore`
  nad dočasnou složkou rozhoduje, co v souboru zůstane. Pokrývá zápis odvozené sady i to,
  kdy se **nezapisuje**: shoda s globální, ruční hodnota, prázdná ruční hodnota. A že
  reviewer dostane odvozenou sadu **hned při prvním běhu**, ne až podruhé.
- **`Policy.knownRepositories`** — union seznamu PR a konfigurace, dedup, řazení bez ohledu
  na velikost písmen a repo bez otevřeného PR, které ze seznamu zmizet nesmí.
- **Novinky (#127)** — tři vrstvy. `Policy` vyčerpávajícím výčtem, včetně toho, co se dá
  pokazit tiše: **značka, která v seznamu není, nesmí prohlásit za novou celou historii**
  a řazení musí být úplné (druhé kritérium se ověřuje i z obráceného vstupu).
  `GhRelease` proti **skutečnému** výstupu `gh api` (`Fixtures/gh/releases.json`, první tři
  z 69 vydání) plus adresu volání — repo je konstanta a `per_page` drží historii na jedné
  stránce, takže obojí je kontrakt s `gh`. Syntetickým JSONem to, co se ze skutečné odpovědi
  nesehná: **rozdělané (`draft`) vydání**, které se do seznamu nesmí dostat, a vydání bez
  názvu i bez popisu.

  `ReleaseNotesModel` proti fake gateway a **předvolbám v paměti** (`InMemoryPreferences`).
  Skutečné `UserDefaults` sem nepatří ani jako vlastní suite: po `removePersistentDomain`
  zůstává soubor v `~/Library/Preferences` (změřeno — z jedenácti jich zbylo šest, a ani
  `synchronize()` s tím nehnul). To hlavní není, co se v okně ukáže, ale kdy se **neukáže**: první
  spuštění mlčí, po selhání se **značka neposune** (jinak by se ta vydání už nikdy neohlásila)
  a v jednom běhu se okno nabídne **jen jednou** — hlavní okno jde zavřít a otevřít znovu.
  K tomu, že se historie tahá **jednou za běh**, že `Zkusit znovu` načte i po selhání a že
  posunutí značky **nezhasne odznaky**.

  `ReleaseRow` na skládání textů: tag na začátku názvu se zahodí i s oddělovačem, název, který
  tagem nezačíná, zůstane celý, a vydání pojmenované jen tagem nemá druhý text.
- **Poslední ohlášení (#138)** — proti `FakeNotificationCenter` a `FakeTimeSource`, takže se
  nic nedoručuje a čas je daný. To hlavní není, že se zapíše, ale že se **nezapíše**: odmítnuté
  oprávnění, selhání systému ani událost vypnutá v nastavení čas posunout nesmí — jinak by
  stavový řádek tvrdil, že notifikace fungují, zrovna když nefungují. Plus že pozdější selhání
  poslední úspěch nesmaže a že se před prvním doručením nemá co ukazovat.
- **`SettingsModel`** — odložený zápis přes `FakeTimeSource` (tedy v nulovém reálném čase):
  že se rychlé změny slijí do jednoho zápisu, že `flush()` uloží bez čekání, že změna
  zvenčí formulář srovná, ale vlastní uložení ne, a že je selhání zápisu vidět. Na testech
  `flush()` je vlastní `BlockingTime`, jehož uspání samo neskončí — s okamžitým fake časem
  by odložený zápis závodil s tím okamžitým a nešlo by poznat, který zapsal.
- **Sazba lišty diffu (#219)** — dvě čisté funkce, tedy výčtem a bez kreslení. `counter(_:)`
  hlídá **dvě různé sady českých tvarů**: za předložkou druhý pád (`1 z 1 nálezu`), samotný počet
  první (`3 nálezy`) — a že se před prvním skokem píše počet, ne `0 z 3`. `FilePathText.parts(of:)`
  dělí cestu na složku a jméno; nejcennější případ je ten okrajový (cesta končící lomítkem), kde by
  prázdné jméno nechalo hlavičku bez popisku. Obojí ověřeno **vloženou regresí**: sjednocení tvarů
  i vypuštěná stráž nad koncem cesty testy shodí.

  Sazba sama (rozměry, barvy) se ověřuje **obrázkem, ne testem** — screenshotem běžící aplikace
  vedle vyrenderované sekce 02 návrhu a offscreen renderem ve světlém i tmavém režimu. U #219 to
  ukázalo, že `Menu` s primární akcí si kreslí **vlastní šipku** vedle té z návrhu, takže
  `⌃ Sbalit vše ⌄` mělo dvě proti sobě.
- **Sazba hlavičky PR (#218)** — čtyři čisté funkce, tedy výčtem a bez kreslení.
  `Policy.diffstatBlocks` hlídá tři věci, které se dají pokazit potichu: že **zaokrouhlení jde
  dolů** (jeden odebraný řádek proti dvěma stům si vlastní čtvereček nezaslouží), že se součet
  drží na pěti nad celou mřížkou 21 × 21 vstupů, a že prázdný diff nedá **žádný** čtvereček —
  pět šedých je pruh, který vypadá pořád stejně, tedy nic neříká. `Policy.progress` má nejcennější
  test v tom, co se **nestane**: bez běhu se pruh nekreslí, ani když `reviewPhases` drží
  `running` nebo `failed` po skončení. `ReviewRunbarView.label` a `ReviewerChipsView.label`
  ověřují, že počet je jen tam, kde běh doběhl a dopočítal se — `0` nad nedoběhlým během je
  tvrzení, které data neunesou — a `spokenState` to, že se stav dá **přečíst**, když ho v kapsli
  nese jen barva puntíku. `WorkingCopyStatusView.text` tvrdí, že selhaný checkout se do stavového
  řádku nedostane; zůstává bannerem v hlavičce, kde je místo na výstup `gitu`.

  Sazba sama (rozměry, barvy, poměry) se ověřuje **obrázkem**: screenshot běžící aplikace nad
  skutečným PR vedle vyrenderované sekce 02 návrhu, plus offscreen render pruhu v běžícím stavu
  ve světlém i tmavém režimu a v úzkém okně. Našlo to dvě věci, které z kódu vidět nebyly —
  `GeometryReader` v dráze průběhu si vzal veškerou šířku a jména reviewerů se zalomila **uvnitř
  kapslí**, a popisek s hodinami se v užším okně ořezal na `1:…`. Obojí je otázka priority
  layoutu, ne rozměru.
- **Kopírování kódu z diffu (#157)** — `Policy` vyčerpávajícím výčtem. Dvě věci se tu dají pokazit
  potichu: **pořadí řádků** (rozsah se zvýrazňuje množinou, která pořadí nemá — ověřeno vloženou
  regresí, `Set` místo pořadí testy shodí) a **která verze se kopíruje** u rozsahu přes obě strany
  diffu. Vedle toho každý případ zvlášť: rozsah vpravo, vlevo, přes obě strany, mimo diff, kotva bez
  začátku, hunk, poznámka `git`u, komentář jiného souboru, jednořádkový komentář (rozsah **nedělá**)
  a české tvary v popisku menu. **Nejcennější test tvrdí, že kopírování draft nezmění** — celé
  zadání #157 stojí na tom, že po kopírování nezůstane rozdělaný komentář.

  Dva testy nejdřív **spadly** a obojí byla chyba v testu, ne v kódu: `contains("+ ")` je nesmysl
  (`$a + $b` je legitimní kód, rozhoduje **začátek** řádku) a počet řádků rozsahu jsem odhadl místo
  přepočítání proti diffu. Obojí je v testu poznamenané, ať to někdo nezkusí znovu.

  **`CodeTextSheet` (#157)** se testuje jen tím, čím jde: `Policy.hunk(containing:in:)` na tom, že
  řádek najde **svůj** hunk (u souboru s dvěma hunky by cizí ukázal jiný kód) a že řádek z cizího
  souboru nenajde žádný.

  **Od #417 má vlastní čtyři sady**, protože se z něj stal roztahovatelný sheet se dvěma profily
  velikosti (podrobnosti o samotném sheetu v [`architektura.md`](architektura.md)):

  - `CodeSheetTests` — čisté funkce výčtem: oba profily, malá i velká obrazovka, strop 2 700,
    podlahy, uložená velikost ořezaná o obrazovku, nesmysl v `UserDefaults` a rozhodnutí, jestli se
    má vůbec zapisovat. A **kapacita řádku proti tabulce ze sekce 28 návrhu** (66 znaků při 560
    bodech, 143 při 1 180, 332 při 2 700) — šířka znaku se u toho **měří na písmu**, ne opisuje.
  - `CodeTextSheetSizingTests` — nad **skutečným oknem sheetu**, jako u #327: `.resizable`
    v `styleMask`u, `contentMinSize` podle profilu, otevření v ideální šířce, natažená velikost se
    uloží a příště se vezme, **hunk nezdědí velikost natažená u logu** a **otevření bez tažení
    neuloží nic**.
  - `CodeSheetTextTests` — věty hlavičky a patičky. To hlavní: **doběhlému jobu se log neříká
    snímek** a **věta o zalomených řádcích u textu, který se celý vejde, nevznikne**. Na konkrétní
    oddělovač tisíců se netestuje (tatáž úmluva jako v `PluralTests`).
  - `CodeSheetWrappingTests` — spočítaná zalomení **proti skutečnému layout manageru**, přes pásmo
    šířek a s řádky přesně o kapacitě a o znak delšími. U jedné šířky projde i výpočet, kterému
    chybí odsazení; pásmo ho chytí.

  A `CodeSheetRenderProbe` (sonda, `TEST_RUNNER_PRISM_MEASURE=1`) vyrendruje **oba druhy v obou
  režimech** a k tomu hunk v podlaze — je to jediná cesta, jak si sheet s logem prohlédnout, aniž by
  člověk musel mít po ruce PR se spadlým checkem.

  **Čtyři vložené regrese, kterými je to ověřené** (a všechny vyšly na dnešní vadu, ne na teorii):

  | Vložená chyba | Co spadne |
  |---|---|
  | `presentationSizing(.fitted)` zahozené | `Bez uložené velikosti se sheet otevře v ideální šířce` — hunk **560 b**, log **820 b**, tedy obojí v podlaze; to je stav před #417 |
  | jeden `@AppStorage` klíč místo dvou | `Hunk nezdědí velikost natažená u logu` — hunk se otevře **2 460 b** široký |
  | odmlka 400 ms zahozená | `Otevření bez tažení neuloží nic` — uloží se **560 × 320** u hunku a **820 × 420** u logu, tedy podlaha z prvního průchodu rozvržení |
  | stráž v `SelectableCodeView` **přidaná** | nic — a proto v repu není, viz *Stráž v `updateNSView`* |

  Past u toho druhého: sdílet **jen šířku** nestačí, test projde. `Policy.codeSheetSize` bere
  uloženou velikost jen tehdy, když jsou **oba** rozměry nad nulou, takže se regrese musí vložit do
  obou getterů — jinak vypadá jako neškodná.

  **A jedna past harnessu, která vypadala jako vada aplikace** (změřeno): sheet se kreslí na
  obrazovce **hostitelského okna** a AppKit ho na ni ořízne, kdežto `CodeTextSheet` si ideál počítá
  z `NSScreen.main`, tedy z obrazovky s klávesovým oknem. Na stroji s dvěma displeji skončilo okno
  s origin `(-10 000, -10 000)` na notebooku (1 512 b), zatímco `NSScreen.main` byl externí monitor
  (3 440 b) — sheet tedy požádal o 2 700 a dostal 1 512. Test pak měřil ořez, ne aplikaci, a rozdíl
  proti požadované velikosti vypadal jako tažení, takže se uložil. Řeší se to **umístěním okna podle
  `NSScreen.main`** (za jeho dolní hranu), ne v aplikaci: tam ta situace nenastane, protože sheet
  vyjede nad klávesovým oknem.

  **Bloky řádků (#157)** mají vlastní sadu (`DiffBlockTests`): že se bez bublin slije všechno do
  jednoho bloku a **žádný samostatný `.line` v seznamu nezůstane** (kreslil by se dvakrát), že
  bublina blok **rozdělí**, že hlavička hunku a expander zůstanou mimo, že split slévá **dvojice**
  a obě strany mají po sloučení stejný počet řádků (na tom stojí zarovnání), a že se slučování obou
  pohledů **nesmí zaměnit** — záměna dá prázdný diff. Dva testy nejdřív spadly: bublina rozdělila
  blok jinde, než jsem čekal (přepočítáno proti diffu), a před hlavičkou hunku stojí ještě expander.

  **Word-level rozdíl (#153)** má dvě sady, a každou z jiného důvodu.

  `WordDiffTests` je čistá funkce výčtem, a **zvýrazněné kusy se v nich píšou v hranatých
  závorkách** (`let total = price * [amount]`) — jde přece o to, kde na řádku to svítí, a to se
  z pole rozsahů nepřečte. Každé takové porovnání zároveň ověřuje invariant **„zvýraznění nemění
  text“**: bez závorek musí vyjít původní řádek, stejně jako u obarvení platí, že spojení run dá
  původní řádek. Případy: přepsané slovo, vložení a smazání (svítí **jen jedna** strana), dvě místa
  na řádku, celé jméno místo písmen, změna odsazení, operátor jako celek (`==` proti `!=`), shodné
  řádky a prázdná strana, nepodobná dvojice, krátké přepsání těsně nad prahem, práh počítaný bez
  odsazení a obří dvojice, u které se přes strop nejde po tokenech.

  Dva testy jsou tam kvůli tomu, co se rozbije **potichu**:

  - **„V obou pohledech svítí totéž“** — na skutečném diffu z fixtures. Vedle sebe páruje
    `DiffRow.paired(_:)`, pod sebou si dvojice hledá `WordDiff` sám, a kdyby se ta pravidla
    rozešla, svítilo by v každém pohledu něco jiného.
  - **„Přidaný řádek skupinu uzavírá“** — a skupiny v něm musí být **nestejně velké**. První
    verze měla dvě stejné a **vloženou regresí se ukázalo, že nechytá nic**: zip po pořadí vyjde
    u dvou stejných skupin stejně jako u jedné dlouhé. S přebytkem na jedné straně test padá.

  `DiffWordHighlightTests` kreslí do `DiffTextView` a čte atributy z `textStorage`. Tady je ten
  **nejcennější test celého issue**: *„tentýž řádek proti jinému protějšku svítí jinde“*. Zvýraznění
  závisí na dvojici, kdežto `SyntaxRunCache` je klíčovaná textem řádku — kdyby se přimíchalo mezi
  runy, vracela by cache zvýraznění cizí dvojice a **obojí zvlášť by dál procházelo**. Ověřeno
  vložením regrese (memo podle textu řádku): padne přesně ten jeden test, ostatní čtyři projdou.
  K tomu, že zvýraznění nemění text, že obarvení syntaxe zůstává pod ním (písmo × pozadí) a že
  kontextový řádek nesvítí, ani když se mu rozsahy podstrčí.

  **Skládání textu bloku (#275)** má vlastní sadu (`DiffBlockCompositionTests`), a je v ní jediná
  otázka: **trefí se obarvení na tytéž znaky jako předtím?** Do #275 se rozsahy nepočítaly — atribut
  jel s kusem textu, protože se text slepoval z `NSAttributedString`u za každý run. Od #275 je text
  jeden řetězec a barvy se do něj dopisují na spočítané rozsahy, a spočítaný rozsah se dá spočítat
  špatně.

  **Znaky mimo ASCII jsou v té sadě jádro věci**, ne ozdoba: `NSAttributedString` měří v UTF-16,
  takže emoji je **dva** kódy. Ověřeno vloženou regresí (`count` místo `utf16.count`
  v `lineRanges(of:)`): padnou tři testy — rozsah řádku, obarvený řetězec za emoji a zvýrazněný kus
  za emoji —, kdežto tytéž případy v ASCII projdou, tedy přesně tak, jak by se ta chyba projevila
  v okně. K tomu meta řádek ztlumený celý a **jen on**, a soubor bez rozpoznaného jazyka, ve kterém
  se nesmí obarvit nic.

  **Že se kresba přepisem nezměnila, se ověřilo rovností, ne pohledem**: dočasným testem, který
  složil týž blok starým i novým způsobem a porovnal `isEqual(to:)` — 400 řádků s emoji, diakritikou,
  komentáři, řetězci, čísly a meta řádky, ve dvou paletách a na obou stranách dvojice. V repu
  nezůstal (staré skládání by se muselo držet naživo jen kvůli němu), ale je to ten důvod, proč
  u #275 pauza na proklikání nebyla.

  **Výška bloku (#236)** má vlastní sadu (`DiffBlockHeightTests`) a referencí je v ní vždycky
  **layout manager**, ne druhý výpočet téhož — jinak by test jen opsal chybu, kterou má chytat.

  To hlavní je *„blok si řekne o tu výšku, kterou nakreslí“*, a jde **přes pásmo šířek** (300–800
  po 17 pt × sedm délek řádku), protože se to rozejde jedině tehdy, když délka nejdelšího řádku padne
  mezi změřenou a kreslenou šířku — u „hezké“ šířky by test prošel. Tvrdí se obojí: že se nakreslený
  text do změřené výšky **vejde** (jinak přeteče do bubliny pod blokem) a že pod poslední řádek
  nezbude víc než svislý inset (jinak by prošel i blok, který si o výšku řekne s rezervou a nechá pod
  sebou mezeru). K tomu, že se kód zalomí **až** tehdy, když se nevejde za gutter — s kontrolou
  z druhé strany, ať test neprojde bloku, který nezalamuje vůbec.

  Ověřeno **vloženou regresí**: měření o gutter širší (tedy původní stav) položí 130 případů,
  a je z nich vidět to pásmo. Prázdný řádek je zvlášť a schválně slabší tvrzení — `usedRect`
  u prázdného textu vrací o 2 pt méně než u řádku s textem (18 proti 20), takže se u něj tvrdí jen
  to, že výška není nulová a nakreslený řádek se do ní vejde.

  **Split má sadu taky** (`DiffPairBlockHeightTests`) a je v ní ten cennější test: *„rámečky dvojic
  sedí na text sloupce“* — porovnává, co hlásí `lineFrames()`, s tím, kde má řádek podle
  `frame(ofLine:)` **skutečně** být, a to pro 1, 8 a 60 řádků. Vloženou regresí (svislý inset zpátky
  do výšky řádku) padne 136 tvrzení a je v nich vidět celý rozsah: na řádku 60 je rámeček o 116 pt
  níž než kód, ke kterému patří.

  **Trvalý vodorovný pruh (#422)** má vlastní sadu (`DiffPairScrollerTests`) a je to **pokračování
  téže třídy chyby**: od #422 závisí výška bloku dvojic na šířce, protože na šířce záleží, jestli se
  pruh kreslí. Referencí je proto zase někdo jiný než náš druhý výpočet — tady `NSScrollView` sám:
  kontejner se laid outne na tu výšku, o kterou si řekl, a z plochy se přečte, jestli scroller ukázal
  (`horizontalScroller.isHidden`) a **kolik výšky si vzal** (`frame.height − contentSize.height`).

  Pásmo šířek je i tady podmínka (260–1000 po 19 pt × šest délek řádku): hranice „vejde se do
  sloupce / nevejde“ se s šířkou okna posouvá, takže u jedné šířky by test prošel. Přesně to pásmo
  taky odhalilo, že první verze předpovědi byla vedle — souhlasila u širokých bloků a lhala kolem
  hranice.

  **`isHidden` samo o kresbě nevypovídá** a to je u téhle oblasti ta hlavní past: overlay scroller
  hlásí `isHidden = false`, `alphaValue = 1.0` i `knobProportion`, a v nečinném okně nenakreslí nic.
  Proto se všechno podstatné tvrdí **na pásu výšky**, který si plocha vezme: legacy 17 bodů, overlay
  nula. Tentýž test drží i to, že styl `.legacy` z plochy **nejde vzít** přiřazením `.overlay` ani
  notifikací o změně systémového nastavení posuvníků.

  Sada tvrdí i dvě věci, které se dají pokazit potichu: **prázdná strana dvojice nesmí zkolabovat**
  (rámečky obou půlek jsou na bod stejné jako u plné dvojice) a **pás se rezervuje jednou**, i když
  pruh potřebuje jen jedna strana — jinak by se půlky rozešly o řádek, tedy přesně to, čemu má split
  zabránit. A zvlášť stojí *„na konec dlouhého řádku se dá dorolovat“*: nejdelší řádek je v bloku
  **poslední** a hledá se maximum přes všechny rámečky, protože šířka dokumentu vychází z vysázených
  fragmentů a ty jsou pravdivé jedině nad vysázeným celým blokem.

  **Že unified pořád zalamuje, je vlastní sada** (`UnifiedBlockWrappingTests`) — test na to, co se má
  **NEstát**. Výška zalamovacího bloku se porovnává s **počtem vizuálních řádků z layout manageru**
  (`enumerateLineFragments`), ne s `usedRect`, ze kterého sama vychází: kdyby si unified začal
  rezervovat pás pruhu nebo přestal zalamovat, rovnost padne. K tomu tvrzení, že si každý blok drží
  svůj kontejner (zalamovací na šířku plochy, sloupec dvojice neomezený).

  Ověřeno **třemi vloženými regresemi** a každá padá jinde, což je na tom to podstatné: bez
  rezervace výšky **108 tvrzení** (mezi nimi `rows 98 <= 83`, tedy text pod pruhem); se vráceným
  `sizeToFit()`/self-sizingem **348 tvrzení**, z toho 182 na tom, že konec řádku je nedosažitelný
  (`129,5 >= 1696,2`); s overlay stylem **58 tvrzení** — a `predictionMatchesAppKit` z nich
  neselže ani jedním, protože overlay se hlásí jako viditelný.

  **Kam se v půlce dá odrolovat, je druhá sada** (`DiffPairScrollWidthTests`) a přibyla po prvním
  kole #422 na hlášení „moc velký posuvník, který jede do prázdného místa, kde nic není“. Je to jiná
  otázka než ta výš: tam se ptáme, **jestli** je pruh, tady **kolik** obsahu tvrdí. Reference je
  proto taky jiná — `frame(ofLine:)`, tedy `boundingRect(forGlyphRange:)`, podle kterého se kreslí
  čísla a pozadí; je to jiná cesta v layout manageru než výčet fragmentů, ze kterého vychází
  `naturalWidth`, takže to není opsaný výpočet.

  Šířka se připíchne **dvěma tvrzeními naráz**: na nejdelší řádku se musí dát dorolovat a **za ní už
  nesmí být nic** než jedno `lineFragmentPadding`. Jde se přes tabulku šesti tvarů bloku, ve kterých
  se půlky liší (včetně toho ze screenshotu: třináct řádků, vlevo převážně šrafování), a přes pásmo
  šířek — u jedné šířky by prošlo i sdílení šířky mezi půlkami.

  Zvlášť je **šrafovaná půlka**: půlka, ve které jsou jen chybějící řádky, nesmí mít pruh **vůbec**,
  protože nemá co skrývat. A rolování se tvrdí na `NSScrollView`u, ne na naší předpovědi — jenže
  `NSClipView.scroll(to:)` **neomezuje** na dokument (je to zápis počátku, takže se plocha posune i za
  obsah a test by zezelenal nad jakoukoli šířkou), takže se posun vede přes `constrainBoundsRect(_:)`,
  tedy to, co AppKit sám používá při tažení za knob.

  Dvě vložené regrese: se `usedRect(for:)` zpátky padne **244 tvrzení** ve všech čtyřech testech
  (u šrafované půlky `10000084.0 <= 94.0`), bez zahození zapamatované šířky v `DiffTextView.show(…)`
  padne **7 tvrzení** a jsou přesně na recyklaci — krátký blok zdědí po dlouhém 1701,2 místo 102,0.

  **A na to, jak to vypadá, je sonda** (`DiffPairScrollerRenderProbe`, cesta ven
  `TEST_RUNNER_PRISM_RENDER_DIR`). Tvrzení říkají, že šířka je správná; sonda ukáže **tři bloky
  z hlášení** (třináct řádků se šrafováním vlevo, půlka bez protějšku, krátký blok) a vypíše
  u každé půlky dokument, okýnko a **`knobProportion`** — tedy to jedno číslo, které odpovídá na
  „nelže knob o tom, kolik obsahu je?“. Změřeno na tom bloku z hlášení: **4,49 × 10⁻⁵** před opravou
  (vlas u levého okraje) a **0,0** po ní, protože šrafovaná půlka pruh nedostane vůbec; na půlce
  s dlouhými řádky vychází 0,471 před i po.

  Dvě věci, bez kterých je bitmapa průhledná, a odsud ta poznámka o neúspěšném renderu níž: blok
  musí být v **okně** (mimo obrazovku) a plochám se musí pro render **zapnout pozadí** — v aplikaci
  ho kreslí obal ve SwiftUI. **Samotný pruh v obrázku ani tak nebude**: legacy scroller nevydá
  `cacheDisplay` nad plochou ani nad `NSScroller`em samotným (obojí změřeno), a
  `CGWindowListCreateImage` je na macOS 26 nedostupné. Vidět je jedině na okně na obrazovce
  (`screencapture -l`, tak se u #422 měřily jeho body); z obrázku se posuzuje šrafování, zarovnání
  řádků, ořez na hraně okýnka a rezervovaný pás.

  **Offscreen render na pruh nedosáhne.** `cacheDisplay(in:to:)` nad `DiffPairBlockContainer`em vrací
  průhlednou bitmapu — nejen bez scrolleru, ale i bez textu, protože sloupce jsou v clip view
  a nekreslí pozadí. **Text se dostat dá** (okno mimo obrazovku a zapnuté pozadí ploch, viz sonda
  výš), **pruh ne**. Že je pruh doopravdy vidět, je proto změřené na **běžícím okně**
  (`screencapture -l`, viz *Jak si zkontrolovat, jak view vypadá*), a v harnessu se místo toho
  tvrdí ten pás výšky a `knobProportion`.

  **`#expect` umí spadnout na `17.0 == 17.0`** a stálo to hodinu (#422). `CGFloat` je vlastní typ
  a implicitní převod na `Double` se v **rozkladu** makra ztratí, takže se porovnají dvě identická
  čísla různých typů — a v hlášení jsou obě vypsaná stejně, tedy vypadá to jako chyba v aritmetice.
  Projeví se to jen u jednoduchého `a == b` (uvnitř `||` už makro výraz nerozkládá, takže tam
  totéž tvrzení prochází). Poznávací znak: `print` vedle toho tvrdí `equal true`. Geometrie v `App/`
  je proto `Double`, včetně `DiffPairScrollView.scrollerHeight`.

  A druhá past téhož druhu: **`#require` uvnitř argumentu jiného `#require` se nepřeloží** —
  `try #require(pole.map { try #require($0) }.max())` skončí na
  `recursive expansion of macro 'require'`, což vypadá jako chyba v makru, ne v našem zápisu.
  Rozdělit to na dva příkazy stačí.

  **Pruh, který jede s výřezem (#428), se testuje ze dvou stran.** Rozhodnutí je čistá funkce
  (`DiffScrollerPinTests` nad `Policy.pinnedScrollerY`) a vyjmenovává se **vyčerpávajícím výčtem**:
  blok celý vidět, přesahující dolů, přesahující nahoru i dolů, se třemi viditelnými řádky (a o bod
  méně), mimo výřez a bez známé výšky řádku. K tomu **průjezd celým posunem** po jednom bodu, který
  tvrdí tři věci, jež se u jedné polohy tvrdit nedají: pruh **nikdy neopustí blok**, v připíchnutém
  pásmu se hýbe **o krok** (spojitá funkce, ne skoky) a hranice obou pásem jsou spočitatelné — první
  připíchnutí na třech řádcích, poslední o bod dřív, než pás bloku vjede do výřezu.

  Druhá strana je **scéna, jaká je v okně** (`DiffScrollerRideTests`): SwiftUI `ScrollView`
  s `LazyVStack`em bloků v okně mimo obrazovku. Rolování se dělá **posunem vnějšího clip view**
  (`scroll(to:)` s `constrainBoundsRect` + `reflectScrolledClipView`), protože přesně to je jev, na
  který aplikace poslouchá — syntetické scroll eventy se do aplikace nedostanou vůbec a událost
  s fází se zasekne v `nextEventMatchingMask:` (#422, #325).

  Reference **není** `Policy.pinnedScrollerY` (tou se poloha počítá, takže by test opisoval sám sebe),
  ale hrana vnějšího clip view a dolní hrana bloku, **obojí převedené do okna**. Okno je
  nepřevrácené, takže `min` z pravidla je v něm `max`: `pruh = max(hrana výřezu, dolní hrana bloku)`.
  Test si u toho počítá, kolikrát projel kterou situaci, a **vyžaduje všechny tři** — na hraně
  výřezu, ve vlastním pásu a pod třemi řádky; jinak by tvrzení platila o průjezdu, ve kterém se nic
  nedělo.

  Dva testy jsou na to, co se má **NEstát**. *„Výška bloku se posunem nemění“* tvrdí přes celý
  průjezd jedinou výšku a k tomu, že řádky plus svislý inset plus pás **dají** výšku bloku — tím se
  do něj skládá i rezervace z #422, takže ji nejde odebrat, aniž by spadl. A *„rolování nepřekládá
  tělo“* měří průchody tělem řádku, `updateNSView`, nasazení bloku i sazbu: dvacet posunů po deseti
  bodech (v pásmu, kde do výřezu žádný další blok nevjede) nepřidalo **ani jeden** průchod z žádného
  z těch čtyř počitadel. Že měřidlo počítá, drží tvrzení, že se pruh v bloku posunul přesně o těch
  200 bodů.

  Ověřeno **třemi vloženými regresemi** a každá padá jinde: bez `min(…)` v pravidle padne 400 tvrzení
  v průjezdu, 28 v okenní scéně a *„blok celý vidět“* (pruh vyjede pod blok, `1073 <= 683`); bez
  rezervace pásu ve `height(forWidth:)` padne 114 tvrzení o výšce; a bez uplatnění polohy v
  `DiffPairScrollView.tile()` padne 29 tvrzení o hraně výřezu — tedy přesně to rozvržení, po kterém
  AppKit scroller vrací na dolní hranu.

  **Kresba pruhu do harnessu nepatří a je to změřené**: legacy scroller se do `cacheDisplay(in:to:)`
  nekreslí — nad červeným dokumentem vyjde pod připíchnutým pruhem tatáž barva jako vedle něj —
  a `CGWindowListCreateImage` na macOS 26 není. Testům proto zůstávají **čísla** (poloha scrolleru,
  výška bloku, počty průchodů) a to, jak pruh při rolování vypadá, se posuzuje na běžícím okně.

  **Jak to vypadá, se ověřilo renderem** — `NSView` do bitmapy, viz *Jak si zkontrolovat, jak view
  vypadá*. U #236 na to `NSView` nestačilo: přetečení vzniká teprve tím, jak SwiftUI poskládá blok
  a bublinu pod sebe, takže scéna musela do `NSHostingView` — viz tamtéž.

  **Sytost 30 % z toho renderu ale byla špatně a opravilo ji až okno** (viz
  `DiffLineView.wordBackground(of:)`). Render jednoho bloku odpovídá na otázku „liší se ten kus od
  zbytku řádku?“, jenže v okně se zvýraznění **hledá v celém diffu** a obvyklá změna je jedno
  slovo, často jediný znak. Nahlášené nad `job-queue-daemon#858` jako „zvýraznění nevidím“, ačkoli
  na řádku 1908 (`count: 7` → `8`) tam bylo. Je to obecnější poučení než jedna barva: **render
  jednoho prvku neodpovídá na to, jestli se ten prvek dá v okně najít** — na to je potřeba
  screenshot běžící aplikace nad skutečným PR. Padesát procent pak platilo do #277, kdy se z krytí
  stala vyčíslená barva a **hodnota se u toho změnila**, protože nad novým pozadím řádku brala pod
  sebou obarvení syntaxe; čísla obou stavů jsou u `Palette.diffAddedWord` a hlídá je sada níž.

  **Barvy diffu (#277)** mají dvě sady a měří se v nich **dvě míry naráz** — to je u nich to hlavní,
  co se dá pokazit potichu: WCAG kontrast nad dvěma plochami podobné světlosti neřekne nic (zelený
  a červený řádek se liší hlavně barvou), kdežto ΔE2000 zas nic neřekne o čitelnosti textu nad
  plochou. Do #277 to bylo vidět na word-level vrstvě: ΔE 29,5 (plocha jak vyšitá) a kontrast
  zeleného řetězce Darculy **1,27**, tedy nepřečtitelné slovo — a zrovna to, které se změnilo.

  `DiffPaletteTests` počítá obojí nad **skutečnými tokeny** vyhodnocenými v obou režimech
  (`performAsCurrentDrawingAppearance` kolem `NSColor` funguje, na rozdíl od `ImageRenderer`u —
  viz *Jak si zkontrolovat, jak view vypadá*). Nejcennější je tvrzení o **alfě**: všech pět tokenů
  musí být neprůhledných, protože právě krytí z barvy dělá výsledek závislý na podkladu — kdo se sem
  vrátí s `.opacity(…)`, spadne tady, ne až na obrazovce. K tomu ΔE ploch proti sobě i proti
  podkladu, kontrast syntaxe (řetězec, klíčové slovo, komentář, `ink`) na obou druzích řádku, znak
  `+`/`−` na svém řádku **i na ploše hlavičky** (jedna barva, dvě místa, #156), obrys bubliny nad
  všemi podklady, a **rozestup šrafy** (pruh 5, perioda 10, vodorovný krok √2× a směr úsečky) —
  protože to je hodnota z návrhu, kterou barva nehlídá. Prahy jsou svázané s dnešními hodnotami, ne
  s ideálem, takže sada padá na zhoršení, ne na zaokrouhlení. Jeden test navíc tvrdí, že se **světlá
  a tmavá větev liší** — bez něj by celou sadu splnila i paleta, která na režim nereaguje, a je to
  zároveň důkaz, že měřidlo režim opravdu přepíná.

  `DiffMissingRowTests` čte **bitmapu sloupce**, protože v modelu prázdný protějšek poznat nejde: do
  textu se skládá jako prázdný kontextový řádek, aby si strany odpovídaly. Vzorkuje se řádka pixelů
  uprostřed řádku a za gutterem (čísla a kód by do vzorku vnesly barvy písma) a odstíny se počítají
  — jednolitá plocha znamená kontext, dva odstíny šrafu. Tvrdí se u toho i **kolik plochy pruhy
  zaberou** (kolem poloviny): jeden tenký pruh by prošel tvrzením o dvou odstínech, ale v okně by se
  ztratil. Cennější je druhý test: **bez `missingLines` se nešrafuje žádný řádek**, jinak by stačila
  jedna záměna podmínky v `drawRows`. Třetí drží, že šrafa leží **nad** plochou řádku a nenahrazuje
  ji — a ten chytil reálnou chybu: v první verzi se šrafa kreslila **před** pozadím řádku, takže ji
  pozadí přemazalo.

  Ověřeno **vloženou regresí** (barvy zpátky na krytí, `drawMissing` vypnuté): padne **32 tvrzení**
  z obou sad a je z nich vidět přesně to, na co si #277 stěžovalo — alfa 0,12, znak `+` s kontrastem
  1,02 nad svým řádkem a prázdný protějšek s jediným odstínem.

  **Vzhled se u #277 srovnával s návrhem, ne jen sám se sebou.** Sekce split diffu z mockupu se
  vyřízne do samostatného HTML, vyrenderuje headless Chromem v obou tématech (`data-theme`) a položí
  vedle offscreen renderu bloku z aplikace. Rozhodlo to dvě věci, na které čísla nestačí: **směr
  pruhů šrafy** (z `45deg` se dá odvodit obojí — v návrhu jdou z levého dolního koutu do pravého
  horního) a to, že plocha díry zůstává **plochou obsahu**, protože pod gradientem je `transparent`.

  **Co se unit testem ověřit nedá:** vybírání textu, kontextové menu a tažení rozsahu. Kliky
  a pohyb myši se syntetizovat dají (`CGEvent` s `cgSessionEventTap` a `mouseEventClickState` —
  s `cghidEventTap` se **nedoručí**), ale **tažení ani pravý klik ne**: kontextové menu se
  neotevřelo ani u tabulky nálezů, která ho má od #113. Ověřuje se to tedy na běžící aplikaci rukou.
  Pozor u toho na dvě věci, které stály čas: okno může být **na druhém monitoru** (souřadnice pak
  začínají u 2450, ne u nuly) a po restartu **není vybrané žádné PR**, takže měření nad „diffem“
  měří prázdnou obrazovku.

  **Pozici pilulky s ikonkou** se offscreen renderem ověřit **dá** — a je to jediná cesta, jak
  rozhodnout spor „posunul jsi ikonku“: stačí vykreslit `DiffLineView` s `dragEnd` nastaveným na
  vlastní kotvu (hover v renderu není) a porovnat s tímtéž renderem nad `git stash`nutou verzí.
  U #157 to ukázalo, že ikonka byla na čísle řádku **už předtím** — a teprve pak se posunula do
  vlastního sloupce.

  **Aritmetika gutteru (#252)** má vlastní sadu (`DiffGutterGeometryTests`) a testuje se proto, že
  **nahradila views**: polohu ploch a pilulky hlásil do #252 SwiftUI u každého řádku, teď se počítá.
  Rozejít se to může potichu — pilulka o pár bodů vedle je vidět jen tomu, kdo si ji zkusí trefit.
  Ve výčtu je: sloupce (levý na hraně, pravý v půlce, pohled pod sebou jediný) a hlavně **že hranice
  stran a začátek pravého sloupce jsou tentýž bod** (jinak svítí pilulka v jedné polovině a táhne se
  ve druhé); svislý rozsah od **prvního řádku**, ne od nuly (svislý inset patří bloku, #236), i pro
  řádky různé výšky; půlotevřený interval při hledání řádku pod bodem (s uzavřeným koncem vyhrají na
  hranici dva); a že plocha na tažení pokrývá **právě** všechny řádky — ani o řádek méně, ani víc.

  **`DiffRowFrames` má sadu z #110** a #252 do ní přidal dvě věci, které se dají pokazit naráz:
  že blok **nevyklidí sám sebe** (vyzkoušeno regresí — se zápisem před úklidem z něj zbude poslední
  řádek) a že **nulová plocha nevyklidí nic** (blok, který se ještě nerozložil, jinak sebere záznamy
  na souřadnici nula, tedy první řádky diffu).

  **#274 přidal tři testy na to, že v krabici je nejvýš jeden diff.** Nejcennější je ten první,
  protože tvrdí, že se něco **nestalo** — po hlášení z jiného diffu v krabici cizí plochy
  nezůstanou (vyzkoušeno vložením regrese: bez klíče podle diffu vyjde počet 2000 místo 1).
  K němu patří dva, které hlídají opačnou chybu, tedy že se nezahazuje víc, než se má: hlášení
  z **téhož** diffu ostatní plochy nechá být (jinak by tažení našlo nejvýš ten blok, ve kterém
  začalo) a po přepnutí je v krabici **hned** to nové (zahazuje se z hlášení, ne zvenčí — kdyby
  se vyprazdňovalo při přepnutí záložky, byla by zpátky chyba z #110, kde krabice zůstala
  prázdná a rozsah se nedal roztáhnout).
- **Filtr seznamu PR (#117)** — dvě vrstvy, a **ta druhá je z celého issue nejdůležitější**.

  `Policy` vyčerpávajícím výčtem: prázdný filtr propustí **všechno** (ne nic), dvě repa dají
  sjednocení, repo + autor průsečík, filtr na hodnotu, která v seznamu není, dá **prázdno** (ne
  všechno), pořadí se nemění. U nabídky to hlavní je, že **drží hodnoty aktivního filtru, i když
  jejich PR ze seznamu zmizel** — bez toho zmizí odškrtávátko a filtr zůstane zapnutý bez cesty
  zpátky. U důvodu prázdna to, že **nad selhaným tikem vyhrává chyba načtení, ne filtr**.

  **Počty u položek (#199)** patří do téhož výčtu a to nejcennější u nich je test, že se **zapnutím
  filtru nezmění** — ze zúženého seznamu by čísla klesala podle právě odškrtaného a z nabídky by
  nešlo poznat, co zapnutí položky udělá. Ověřuje se dvakrát, protože se to dá pokazit na dvou
  místech: v `Policy` (nabídka nad týmž seznamem vyjde s filtrem i bez něj stejně) a v `AppStore`
  (`filterOptions` sahá na `pullRequests`, ne na `visiblePullRequests` — tentýž rozdíl getterů
  jako všude jinde). K tomu položka, která v nabídce zbyla jen po aktivním filtru, má počet **nula**,
  a pořadí je podle jména i tehdy, když by počty seřadily jinak — jinak by nabídka přeskakovala
  s každým tikem.

  **Osa „jen blokující“ (#371)** patří do téhož výčtu a nejcennější dvě tvrzení jsou o tom, na co se
  **neptá**: nad vypnutou osou se na blokující nález neptá vůbec (jinak by zapnutý filtr repa
  procházel nálezy u každého PR pro nic — a tuhle funkci čte SwiftUI při každém překreslení seznamu)
  a nad prázdným filtrem se nevrací dřív, než se na cokoli zeptá. K tomu, že se osa s repem
  **průsečíkuje** (karta `Blokuje` zapíná jednu osu, ostatní volby zůstávají) a že se počítá do
  `isActive` — bez toho by ikona filtru nad zapnutou osou vypadala jako vypnutý filtr a `Vymazat
  filtr` by bylo zakázané.

  **`AppStore` proti fakes na to, že filtr je pohled, ne mazání:** zapnutí filtru nezahodí diff
  schovaného PR (a po vypnutí se GitHubu neptá znovu), nezahodí draft, nezruší běžící review,
  nechá plný seznam plný, nechá `knownRepositories` (okno nastavení) i `queueSummary` beze změny.
  Ověřeno **vložením regrese**: když `pullRequests` filtruje sám, spadne osm testů — mezi nimi ty
  o nastavení, automatu a souhrnu fronty. Úvaha o tom, kdo dnes co čte, by tuhle záruku nedala.

  K tomu výběr: vybraný PR mimo filtr výběr **ztrácí**, uvnitř filtru ho **drží**, a **tik, ve
  kterém PR není, ho nesráží** (dnešní chování, které se nemá změnit).
- **Souhrn fronty (#155)** — `Policy` vyčerpávajícím výčtem. Dvě věci se dají pokazit potichu
  a obojí je ověřené **vložením regrese**: **počítat nálezy místo PR** (souhrn by tvrdil víc práce,
  než kolik jí je — tři nálezy na jednom PR jsou jedna položka) a **počítat prázdný draft** za
  rozdělané review. Vedle toho každý případ zvlášť: bez záznamů, blokující u každého PR jiné,
  odmítnutý nález (nejcennější — kdyby se počítal, souhrn by se rozešel s řádkem seznamu),
  přenastavené kategorie, PR s blokujícím nálezem **i** draftem, fronta přes víc rep a **záznam
  nebo draft PR, které ve frontě už není** (mezitím se zavřelo, ale na disku zůstalo).

  Vzhled je doložený offscreen renderem ve světlém i tmavém režimu — včetně toho, že se **nulové
  položky nekreslí**, že velká čísla nejdou přes locale (žádné „1 234“) a že se **slovo skloňuje**
  (`21 blokujících`, `3 blokující`). Samotné ikony s čísly se ukázaly jako nečitelné (vyžádané při
  zkoušení: „nevím, co co znamená“), takže u každého čísla stojí slovo; tvar slova bez počtu dává
  `Plural.word(_:one:few:many:)`, protože číslo se v pruhu píše `verbatim`.

  **Sloveso patří do tvarů, ne za ně** — „2 pull requesty čeká“ je špatně česky. Nález Copilota
  na #168; při opravě se tentýž vzor našel ještě na **dvou starších místech** (useknuté vlákno
  a nevešlá konverzace nad diffem). Neosobní konstrukce („2 řádky diffu se nepodařilo přečíst“)
  je naopak správná a zůstává.
- **Dashboard (#181)** — `Policy` výčtem, protože je to čistá funkce nad tím, co store drží
  v paměti. Tři věci se dají pokazit potichu:
  - **Počítat drafty jinak než stavový řádek.** První verze počítala všechny drafty na disku
    a karta ukazovala trojku vedle jedničky ve stavovém řádku; test proto sype dohromady prázdný
    draft, draft PR mimo frontu a jeden platný.
  - **Vymyslet stáří draftu, který razítko nemá** (z doby před #181). Karta o něm musí mlčet,
    ale **cíl akce `Dopsat review` zůstává vyplněný** — pokračovat se v něm dá.
  - **Počítat nálezy z běhů mimo sedmidenní okno.** Reviewer, který v okně neběžel, v legendě
    nemá co dělat; ten, který běžel a nic nenašel, v ní naopak **zůstává s nulou**.

  **Pořadí fronty** (`Policy.byUrgency`) má vlastní sadu: celá škála naráz z obráceného vstupu,
  blokující nad pěti kosmetickými nálezy, nedoběhlý běh nahoru **jen** s blokujícím nálezem,
  determinismus při shodě času — a hlavně, že **zastaralé nahoru nejde ani s blokujícím nálezem**
  (nálezy patří ke staršímu `headSha`).

  Ve store: fronta dashboardu je seřazená **jinak než `pullRequests`** (obojí v jednom tvrzení,
  jinak by se dalo splést getter), **filtr seznamu ji nezúží** a hromadné spuštění bez revieweera
  **nespustí nic**. Sedmidenní historie útraty se ověřuje proti skutečné dočasné složce: přesun
  včerejška po půlnoci, prázdný den, který v řadě zůstává, a ořez na sedm dní.

  **Strop pěti řádků a klikatelné karty (#371)** — `DashboardBlockTests` výčtem a `AppStoreDashboardTests`
  proti fakes. Čtyři tvrzení nesou celé issue a všechna říkají, že se něco **ne**stalo:
  - **Strop nezmění čísla na kartách.** Nad třinácti PR kreslí blok pět řádků a patka hlásí `+8`,
    kdežto `dashboard.queue.pullRequests`, `dashboardQueue.count` i odznak v railu zůstávají na
    třinácti. Kdyby strop sestoupil do počítání, dashboard by začal lhát a poznalo by se to až za
    týden.
  - **Patka se u bloku pod stropem nekreslí** — a **ani při přesně pěti řádcích**, což je ten případ,
    na kterém se `>=` proti `>` pozná. Šestý řádek ji vyvolá s `+1`.
  - **Karta `Dneska stálo` nevede nikam.** Vedle přímého tvrzení je test přes `allCases`: cíl nemá
    **právě jedna** karta, takže nová karta se musí rozhodnout, a žádná nevede na `Přehled` (dashboard
    je `Přehled` sám). Že to view dodržuje, je vidět v renderu — karta bez cíle nedostane tlačítko,
    šipku ani hover.
  - **Karta `Blokuje` nezapne filtr dvakrát a ostatní osy nechá být.** Klik nastaví `onlyBlocking`,
    nechá odškrtnutá repa i autory a druhý klik už filtr nezmění. K tomu tvrzení, že **co karta
    napočítá, to filtr ukáže** (`visibleQueuePullRequests.count == dashboard.blocking.pullRequests`) —
    tam se pozná, kdyby se sada blokujících kategorií rozešla mezi kartou a filtrem.

  A počet nakreslených řádků ověřuje `Policy.dashboardBlock` **přes pásmo** (1 až 20 PR): nakreslené
  plus shrnuté musí dát celou frontu. Rozejít se to umí jen v pásmu, takže u jednoho počtu by test
  prošel.

  **Dělící čára nad patkou** má vlastní sadu z bitmapy (`DashboardFooterSeparatorTests`) — z kódu to
  vidět není, dvě jednobodové čáry pod sebou vypadají v obou souborech správně. Měří se **všechny**
  vodorovné čáry v levém sloupci naráz (v tomhle návrhu je každá jednobodová), takže tvrzení „všechny
  stejně silné“ chytí dvojitou čáru bez ohledu na to, kolikátá zhora patka je; k němu jde počet čar,
  bez kterého by prošla i nenakreslená patka. Dvě věci, které to stálo:
  - **Barvy se neporovnávají s paletou**, a je to změřené: `Palette.lineSoft` (`#E9ECF4`) vyjde
    v bitmapě jako `0.934 0.941 0.963` místo nominálních `0.914 0.925 0.957`, protože okno kreslí do
    širšího barevného prostoru. Čára se proto pozná **tvarem** — tenký jednolitý pás, který se barvou
    liší od pásů nad ním i pod ním. Ta podmínka na okolí je tam kvůli mezerám v textu: mezi titulkem
    a souřadnicemi řádku je taky tenký jednolitý pás, jen v barvě plochy kolem.
  - **Vyzkoušené vložením regrese**: s `overlay(alignment: .top)` navíc nad patkou vyjde jedna čára
    4 px vedle deseti dvoupixelových a test spadne (`Set(thickness).count → 2`).

  Do renderu se u toho **nesmí věřit `ImageRenderer`u** (dashboard je `ScrollView`, ten se offscreen
  nerasterizuje) a na hotovou kresbu se **čeká se stropem**, ne pevnou odmlkou: kolik kol smyčky
  hierarchie potřebuje, rozhoduje zátěž stroje.

  **Šipka na kartě si drží místo odsazením** (`arrowRoom`), takže se popisek zkrátí, místo aby se
  zalomil pod ni. Ověřeno renderem na šířkách 640, 760 a 900 bodů: v tom nejužším vyjde
  `ČEKÁ N…  →` a výška řady karet zůstane stejná. Je to tatáž past jako u věty pod číslem (#331),
  jen o jednu úroveň výš.

  Kdy se polling zeptá znovu (`PollState.nextPoll`) je u `PollingService`: hodnotu zapisuje
  smyčka, ruční obnovení ji **neposouvá**, a po rate limitu ctí backoff, ne nastavený interval.

  **Odpočet příštího tiku (#237, #260)** má tři sady a každá kryje něco, co se rozbije potichu:
  - **`DashboardTick` výčtem** — co se v tom koutě píše, je čistá funkce nad `lastSuccess`,
    `nextPoll`, příznakem dotazu a hodinami. Nejcennější tvrzení je, že **uplynulý termín se
    neukáže jako odpočet**: v minulosti je `nextPoll` po celou dobu dotazu, takže se testuje
    termín před chvílí, termín **právě teď** (rovnost patří k uplynulým) i termín osm hodin za
    námi, tedy stav po probuzení stroje. Ověřeno vloženou regresí — bezpodmínečný `.countdown`
    shodí tři testy.
  - **Text odpočtu** (`DashboardCountdownTests`, #260) — `DashboardCountdown.label(until:at:)` je
    čistá funkce, takže se vyčerpá výčtem: vteřiny, celá minuta bez nul, dvě jednotky nad minutu,
    backoff těsně pod stropem (`za 14min 59s znovu`), strop intervalu v hodinách, nula a termín osm
    hodin za námi. Nejcennější je ale **tvrzení o tom, co se nestane**: přes celý rozsah odpočtu
    (od −5 s do dvou hodin) nesmí za číslem stát mezera. Kvůli té mezeře issue vzniklo a bez
    rozsahového tvrzení by se dala vrátit v jedné větvi formátu, kterou zvlášť vyjmenovaný případ
    nekryje. Ověřeno vloženými regresemi: mezera ve vteřinové větvi shodí 19 tvrzení, v minutové
    a hodinové 1028; krácení místo zaokrouhlení shodí vteřinu, o kterou se odpočet přeskočí, a
    chybějící sražení nuly ukáže záporný čas.
  - **Cena odpočtu** (`DashboardCountdownRedrawTests`) — sonda v hostovaném okně kolem
    **skutečného** `DashboardCountdown`u, která si počítá přepočty svého těla, a k tomu bitmapa
    téhož view snímkovaná po 100 ms. Obě poloviny musí platit naráz: kresba se **dvakrát změní**
    (odpočet se tedy přetiká, ne jen jednou překreslí) a tělo se u toho přepočítá **jednou**. Jedna
    bez druhé se dá splnit omylem — zamrzlý odpočet tělo taky nepřepočítává, a to je zrovna ta
    regrese, kterou samotný počet přepočtů nechytá (ověřeno vyndáním `TimelineView`: bez bitmapy
    zůstala sada zelená). Text se z okna **přečíst nedá**, accessibility tree se v něm nenaplní
    (změřeno: `accessibilityChildren` vrací prázdno), takže se porovnávají pixely. Měří se na sondě,
    ne na `DashboardView`, protože počítat přepočty jde jedině tak, že si je view samo počítá, a to
    do aplikace nepatří. **Druhý test je kontrola měřidla**: tentýž postup nad odpočtem, který se
    v těle přepočítává (hodiny ve stavu), musí přepočty spočítat **a vidět u nich měnící se
    kresbu** — bez něj by zelený první test mohl znamenat jen to, že sonda vůbec nežije. Okno je
    **bez rámu a mimo obrazovku**, ale skutečné: bez okna SwiftUI přepočty neplánuje a oba testy by
    vyšly zeleně z nesprávného důvodu.

    **Na kresbu se čeká, neměří se v pevném okamžiku** (#269, mění #260). Do #269 sonda vzala dva
    snímky **1,5 s** od sebe a tvrdila, že se liší — a `main` na tom byl červený, protože se lišit
    **nemohly**: `TimelineView` vykreslí při nasazení hodnotu **prvního** tiku rozvrhu, který je
    v budoucnosti, a další překreslení naplánuje až na tik po něm, takže první změna kresby přijde
    za **1 až 2 periody**. Změřeno s termínem 600,0 s daleko (mřížka tiků padne na celé vteřiny od
    nasazení): kresba se změní ve **2,01 s**, pak 3,00 s, 4,00 s a dál po vteřině — tedy nikdy
    v tom 1,5 s okně; s termínem 600,4 s daleko v 1,41 s, tedy 90 ms před koncem okna. Zeleně
    vycházela jedině tehdy, když spánek přetáhl o půl vteřiny, což je na vytíženém stroji běžné —
    a to je celé vysvětlení, jak mohla u #260 projít a na čistém `mainu` padat. **Aplikace v tom
    byla celou dobu v pořádku**: odpočet tiká po 1,00 s (změřeno na časech tiků 2,01 → 3,00 → 4,00
    → 5,00 → 6,00) a věta v obou snímcích je čitelná — `za 9min 59s znovu` v 1,5 s, `za 9min 58s
    znovu` ve 2,0 s.

    Sonda proto snímkuje po 100 ms, dokud nenajde **dvě** změny, se stropem `TestWait.deadline`.
    Uplynulý čas se u toho měří **monotónně** (`ContinuousClock`, jako v `DiffPerformanceMeasurement`):
    termín odpočtu `Date` být musí, jinak by rozvrh netikal podle týchž hodin jako aplikace, ale strop
    sondy na nástěnných hodinách stát nesmí — přestavení hodin nebo korekce z NTP by ho posunuly.
    Ověřeno i druhou stranou: opakované `cacheDisplay` samo přepočty nestojí ani takt neposouvá (tělo
    se přes šest vteřin snímkování přepočítalo jednou), a odpočet v těle kontroly měřidla je na
    **desetiny vteřiny**, protože s celými by se text stihl změnit nejvýš jednou.

    **Strop netvrdí vteřinový takt a tvrdit nemá** (#296, mění #269). Do #296 tu stálo, že právě
    strop 4 s z čekání dělá tvrzení o vteřinovém taktu, protože rozvrh po dvou vteřinách posune změny
    na 4,0 s a 6,0 s. Znělo to dobře a **nefungovalo to**: sonda potřebuje **tři kola na
    `MainActoru`** (první snímek a dva různé) a pod třemi souběžnými clean buildy trvalo jedno kolo
    8,6 s, takže za celý strop vzala **jediný snímek** a tvrdila „odpočet se nepřetikal“ o aplikaci,
    která byla v pořádku. Za jednu dávku z toho bylo **pět** falešně červených `mainů`. Takt se
    přitom dá ověřit **deterministicky a bez hodin**: `DashboardCountdownTests` čtou
    `entries(from:mode:)` a rozvrh `by: 2` jim vyjde `[42, 40, 38]` místo `[43, 42, 41]` — ověřeno
    vloženou regresí, dva pády za 0,001 s. Držet kvůli tomu strop těsně u naměřených 3 s znamenalo
    postavit deterministicky ověřitelnou věc na tom, kolik zbylo procesoru.

    Sonda proto od #296 **počítá i snímky** a píše je do hlášky, protože právě z toho čísla se pozná,
    jestli je rozbitá aplikace, nebo nebyl procesor. Nad zamrzlým odpočtem (vyndaný `TimelineView`)
    vyjde `přetikal 0× místo dvakrát (kresba se nezměnila ani jednou; snímků 1157)` — zdravá sonda
    nad rozbitou aplikací. Pod zátěží by na tomtéž místě stálo `snímků 1`. Bez toho čísla je „změn 0“
    k nerozeznání od zamrzlého odpočtu a rozhodování mezi „flake, nebo regrese?“ stojí kolo navíc.

    Co z toho platí pro **příští sondu nad `TimelineView`em**: pevný okamžik měření je vždycky
    závod s fází mřížky tiků, kterou určuje ukotvení rozvrhu (u nás termín, ne `.now`) — čeká se
    tedy **na jev se stropem**. Strop ale patří k zátěži, ne k periodě: co se dá tvrdit o rozvrhu,
    se tvrdí na `entries`, a na kreslení zbyde jen „přetiká se to“. Sonda, která by se místo toho
    jen „nechala doběhnout“, tvrdí to, co zrovna stihla.

    U hostovaného view je jeden zádrhel, který stojí za zapamatování: **rozměr se nesmí propsat do
    okna** (`NSHostingView.sizingOptions = []` a pevný `frame`). Text sondy se s každou vteřinou
    mění, takže hostující view tlačí novou vnitřní velikost do mezí okna a AppKit po několika
    kolech hodí `NSGenericException` („more Update Constraints in Window passes than there are
    views“) — což **nepoloží test, ale celý běh**: testovací host spadne a `xcodebuild` doreportuje
    `0 tests`. Chytilo se to tím, že jeden běh spadl a druhý ne.

  U `PollingService` k tomu patří `isRefreshing`: platí **po dobu dotazu** (pozoruje se zvenčí
  přes `afterSuccessfulTick`, který se volá uvnitř `refresh()`) a **nezůstane** ani po selhání,
  ani po zrušení, ani mezi tiky. Ta druhá polovina je ta cennější — zaseknutý příznak znamená
  `ptám se…` navždycky, tedy obrazovku k nerozeznání od zaseknuté aplikace.

  **`ProportionalColumns`** se testuje po částech: `Layout` se bez hostitelského okna vykreslit
  nedá, ale výpočet šířek ano — a tam se dá pokazit potichu, že se **mezery odečtou až po dělení
  poměrem** (sloupce pak přetečou a poslední se ořízne). K tomu sloupec navíc bez poměru a šířka
  menší než mezery, ze které nesmí vyjít záporný rozměr.

  **Značku `≥` u neúplné útraty** (`RunUsageText.spent`) čtou od #181 dvě místa, takže má vlastní
  test — formát částky se netestuje, ten závisí na locale.
- **Checky z GitHub Actions (#209)** — `Policy` výčtem. Dvě věci se dají pokazit potichu:
  **počítat přeskočený jako prošlý** (hlavička by svítila zeleně nad přeskočeným testem)
  a **počítat většinu místo nejhoršího**. Test s dvanácti zelenými a jedním červeným je proto
  v sadě schválně. K tomu překlad kbelíků včetně neznámého (bere se jako běžící — jediný stav,
  který o výsledku netvrdí nic) a pořadí, ve kterém jdou spadlé nahoru a přeskočené dolů.
- **Tab `Kontroly` a jeho odznak (#215, přepnuto #306)** — `Policy` výčtem (`ChecksTabStateTests`,
  do #306 `PullRequestTabListTests`), volba tabu ve store (`AppStoreTabTests`) a sazba
  (`ChecksTextTests`). Co se dá pokazit potichu:
  - **říct, že PR nemá CI, dokud se čeká na odpověď** (#306) — to je nejcennější test téhle sady.
    Tab se od #306 kreslí vždycky, takže musí mít odpověď na každý stav dat, a nenačteno je zvenku
    k nerozeznání od prázdna: rozhoduje **chybějící klíč**, ne počet prvků. Testuje se **celou
    mřížkou** vstupů — `checks` nenačtené / prázdné / neprázdné krát `failure` je / není, tedy šest
    kombinací a čtyři odpovědi — a k tomu dvě pravidla o pořadí: neprázdný seznam přebíjí poruchu,
    porucha přebíjí obě prázdna (i `checks == []`, jinak by z chyby sítě vyšlo „nemá CI“);
  - **nakreslit odznak nad tabem, ve kterém není seznam** (#306) — druhý test, který tvrdí, že se
    něco NEstalo: `checksBadge` je `nil` u `loading`, `empty` **i** `failed`. Do #306 to platilo jen
    shodou okolností (tab se u prázdných checků nekreslil, takže se odznak neměl kde nakreslit), teď
    to drží `guard case .list` — a zastaralý seznam odznak naopak **má**, protože mluví o tom, co je
    pod ním vidět;
  - **zúžit pruh záložek podle dat** (#306) — `PullRequestTabBar` kreslí `PullRequestTab.allCases`
    a **nemá parametr**, kterým by se dal seznam podat, takže membership se z dat nedá ovlivnit ani
    omylem; testem se hlídá druhá polovina toho tvrzení, tedy že se výčet nezmenšil (počet 6
    a jmenovitě `.checks`). Že se pruh nepřeskládá, je vidět na renderu ze všech čtyř stavů —
    `ChecksTabRenderProbe`, viz níž;
  - **rozejít dělič v pruhu** — počet přechodů `isReviewerOutput` musí být přesně jeden, jinak by
    v pruhu byly dva děliče nebo žádný. Do #306 se to hlídalo i nad zúženým pruhem bez `Kontrol`;
    ten stav už neexistuje, takže test odpadl s ním. Od #316 se k tomu tvrdí i to, **kde** ten
    jediný dělič stojí (před `Nálezy`) a že na indexu 4 je `Kontroly` — sedmá záložka vložená
    doprostřed je zrovna ta změna, po které by zadrátovaný index posunul dělič o místo vedle;
  - **slít `showsReviewPanel` s `isReviewerOutput`** (#294) — vlastnosti se rozcházejí ve dvou
    tabech: `Kontroly` a od #316 `Commity` (obojí fakt o PR, takže nalevo od děliče, a panel přesto
    nemají). Test to tvrdí
    **negativně**: hledá tab, ve kterém se ty dva příznaky neshodují, takže sloučení do jedné
    vlastnosti spadne — a spadlo by na děliči, tedy jinde, než by vzniklo. K tomu vyčerpávající
    výčet („panel je v `Přehledu`, `Změněných souborech` a `Konverzaci`“) a pojistka na počet
    (tři ze sedmi), aby výčet nešlo „opravit“ na všechny nebo na žádný. Od #316 se to hlídá
    **nad dvěma taby**, ne nad jedním: `Kontroly` i `Commity` mají `isReviewerOutput == false`
    a panel přesto nemají;
  - **zarovnat volbu tabu na data** (#306) — volba `Kontroly` musí přežít **všechny čtyři** stavy
    checků, protože zarovnání by se dalo vrátit u kteréhokoli z nich. Do #306 se tu testoval opak
    (volba na nekreslený tab spadne na `Přehled`) a k tomu, že se přitom **nemaže**, aby byl člověk
    po dotažení checků zpátky tam, kde byl — obojí odpadlo se zarovnáním, protože tab nemizí. Druhý
    test hlídá, že volba dál nepřetéká na jiné PR;
  - **spočítat odznak podle většiny** — tentýž test s dvanácti zelenými a jedním červeným jako
    u chipu, plus že zelené a přeskočené CI odznak **nedostanou** (šum by přebil ty dva, které
    něco říkají) a že spadlé přebijí běžící;
  - **rozejít poměr mezi tabem a chipem v hlavičce** — obojí bere text z týchž částí
    (`ChecksText.parts`) a chip z nich ukazuje **tu první**, takže se hlídá i to, že části jdou
    od nejhoršího stavu. Barvy se hlídají proti `Palette`, protože do #215 kreslil seznam
    `.green`/`.red` ze SwiftUI, kdežto chip barvy z palety návrhu;
  - **zapsat selhané načtení jako prázdno** — z toho tiše vyjde tvrzení „tenhle PR nemá CI“.
    Hlídá se z šesti stran: porucha se zapíše do `checkFailures` a `checks` zůstane nenačtené
    (a v tabu je `failed`, ne `empty`); PR bez CI naopak **žádnou poruchu nehlásí**; selhaný pokus
    **nezahodí** to, co už bylo (seznam zůstane vidět, jen s větou nad ním); povedený pokus starou
    poruchu smaže; `Zkusit znovu` poruchu **opravdu přepíše** (#306 — `loadDetail` má cache podle
    `updatedAt`, takže bez vlastní cesty k `loadChecks` by se po chybě sítě nedotáhlo nic až do
    dalšího commitu); a **spadlý detail načtení checků nezastaví** (#306), protože jinak by v tabu
    svítilo `Načítám kontroly…` navždycky;
  - **nechat zrušené načtení checků nedotažené** (#306) — `loadChecks` běží až po detailu, takže
    přepnutí PR uprostřed toho volání ho zruší a zrušení se schválně nezapisuje; po návratu je ale
    detail z cache, takže se checky bez dotažení v `guardu` nedotáhnou už nikdy. Testuje se přes
    `checksFailure = CancellationError()` a **druhý test hlídá opačnou chybu**: hotová odpověď
    (prázdno i porucha) se návratem na PR **nepřepisuje**, jinak by z checků byl polling.

    U obou platí, že fake gateway musí vracet **úspěšný detail** — bez něj `hasCurrentDetail`
    zůstane `false`, cesta z cache se nikdy neprojde a test měří něco jiného, než co má v titulku.
    Chyceno tím, že druhý z těch testů kvůli tomu spadl.

  Fake gateway má na selhání checků **vlastní přepínač** (`checksFailure`) vedle `checks` — kdyby to
  byl jeden `Result`, nešlo by nastavit „prázdno bez chyby“, tedy zrovna ten stav, který se s chybou
  nesmí slít.

  **Trvání se porovnává proti `RunUsageText`, ne proti napsanému číslu.** Naivní `"prošlo · 41 s"`
  je červené, protože formátovač v českém locale sází `41,0 s` a mezery jsou nezlomitelné — test
  by tvrdil něco o formátování čísel, ne o téhle sazbě.

  Jak to **vypadá**, se ověřilo offscreen renderem přes `NSHostingView` (`ScrollView` ani `Link`
  se v `ImageRenderer`u nevykreslí) ve světlém i tmavém režimu: tři podoby odznaku, tab se seznamem
  a pruh záložek přes pásmo šířek 620–1020. Šest záložek se vešlo na jeden řádek od ~920 bodů, pět
  od ~820 — pod tím se popisky **zalamovaly**, neřezaly. Od #318 se pruh v úzkém okně přepne na
  ikony a nezalomí se nikdy; přesná čísla jsou v `TabStripWidthTests`.

  **Od #306 je z toho renderu trvalá sonda** — `ChecksTabRenderProbe`, gatovaná `PRISM_MEASURE`
  jako `DetailTabRenderProbe` (do test hosta se pouští `TEST_RUNNER_PRISM_MEASURE=1`
  a `TEST_RUNNER_PRISM_RENDER_DIR`, jinak se proměnná k testu nedostane a suita se tiše přeskočí).
  Vyrendruje **detail PR v tabu `Kontroly` ve všech pěti podobách stavu** (nenačteno, bez CI,
  seznam, porucha, zastaralý seznam) ve dvou šířkách. Na jednom snímku je vidět obojí, na čem #306
  stojí: že pruh má sedm záložek pokaždé a že odznak je jedině nad seznamem. Pořadí ve scéně je
  podmínka: `loadDetail` si checky dotahuje sám, takže se **nastavují až po něm** — jinak by je
  přepsal. Během renderu už se nespustí (cache podle `updatedAt`), a právě proto se tudy dá vyrobit
  i stav „nenačteno“, ke kterému se v aplikaci normálním používáním vrátit nedá.

  **Pruh záložek sonda od #318 nerendruje** — přestěhoval se do `TabStripRenderProbe`, kde je na
  jednom pásmu šířek a se všemi aktivními záložkami. Z toho, co o něm stálo tady, zůstávají dvě
  opravy, protože obě mluví o číslech, která se v repu opakovala:

  - **popisky se nezkracují** (`Změněné soub…`), jak tu stálo do návrhu tabu `Commity` —
    `PullRequestTabBar` nikde nemá `lineLimit`, takže se popisek do #318 lámal **uvnitř záložky**
    a pruh povyrostl. Od #318 se místo toho přepne na ikony;
  - **hranice „~780“ a „~920“ výš byly z repliky pruhu** a z měření po stovkách. Skutečný
    `PullRequestTabBar` se šesti záložkami a všemi odznaky se vešel na jeden řádek od tabu **884 b**
    (okno 937), tedy o 17 bodů výš, než replika tvrdila. Dnešní čísla drží `TabStripWidthTests` níž.

  **`Přehled` se po odebrání souhrnu vyrendroval znovu, před a po** — je to jediný způsob, jak se
  pozná, že po odebrání bloku zbyla úplná obrazovka a ne děravá. Kontrolovaly se u toho **prázdné
  stavy**, protože právě ty se odebráním bloku dají potichu rozbít: `Načítám popis…` (detail
  nedorazil) a `Autor k PR nic nenapsal.` (autor nic nenapsal) musí zůstat **dva různé stavy**,
  a k tomu nejchudší možný `Přehled` — bez dlaždic i bez checků — nesmí být prázdná plocha.
- **Šířka `Přehledu` (#291)** — `OverviewWidthTests`, přes pásmo šířek 128–1180. Tvrdí jedinou věc:
  **za pravou hranou tabu se nekreslí nic**. Vzniklo z regrese po #279, kdy sazba Markdownu přešla
  na `filling()`, `Přehled` si nezúžil předávanou šířku o svá odsazení a karta s popisem vyšla
  o 42 bodů širší než tab.

  Tři věci, na kterých ten test stojí a bez kterých je slepý:

  - **Měří se pixely, ne rámečky.** `frame(width:)` z `filling()` je tvrdý rámec, takže dítě, které
    se do něj nevejde, přeteče **vizuálně** a rodičova velikost se nezmění — ptát se rodiče na
    `fittingSize` znamená ptát se toho, kdo o chybě neví. Obsah se proto kreslí na plátno **širší**
    než tab a v tom přesahu se hledají pixely.
  - **Bez `ScrollView`u** (`OverviewView.content`, ne `body`). `NSScrollView` obsah na svou šířku
    ukrojí, takže rozbitý stav vyjde na renderu skoro jako opravený — jen bez pravé hrany karty.
    Přesně tím je tahle regrese v aplikaci tak nenápadná; `content` je `internal` kvůli tomu.
  - **Podklad se porovnává proti druhému renderu**, ne proti zapsané purpurové: bitmapa z
    `ImageRenderer`u je v systémovém barevném prostoru, takže literál `1,0,1` v ní přesně nesedí.
    První verze sondy na tom stála a hlásila přetečení přes celé plátno i tam, kde se nic
    nenakreslilo — vypadalo to jako chyba v aplikaci, a byla v sondě.
  - **Čtou se surové bajty (`bitmapData`), ne `NSColor` na pixel** (nález Copilota na #291).
    Plocha k prohledání je `přesah × výška` u každého případu a každé šířky, tedy ~5,4 milionu
    bodů; `colorAt(x:y:)` s `usingColorSpace(.sRGB)` z toho udělá ~21 milionů objektů. Změřeno
    **13,2 s → 2,5 s** za suitu (a celý běh 17,5 s → 7,5 s, protože tyhle tři testy byly úzké
    hrdlo). Převod barevného prostoru přitom nebyl na nic potřeba: oba rendery jdou stejnou cestou
    a porovnávají se navzájem. Cenou je, že se musí ověřit i **rozvržení bajtů** (`bytesPerRow`,
    `bitsPerPixel`, `isPlanar`) — bez shody v něm by se porovnávaly různé pixely.

  **Vyzkoušené vložením regrese** (obě poloviny opravy zvlášť): bez `narrowingWidth(by: 32)` u tabu
  16 bodů přesahu, bez `narrowingWidth(by: 26)` u karty 10 bodů. A z toho vyšlo i jedno pravidlo
  do kódu: rámec, ve kterém se má přetečení dát změřit, **musí zůstat pružný** — s `filling()` na
  odsazeném těle popisu zůstal test zelený i po smazání toho zúžení.

  **Prázdné a nedoručené stavy se měří zvlášť** (`nil` proti `""`), protože jsou to jiné podstromy
  než sazba a nesmí se slít. Že přetečení bylo doopravdy v sazbě, se poznalo právě po nich: zeleně
  vycházely i před opravou.

  **Od #294 to měření nebydlí v téhle suitě, ale v `OverflowProbe`** — plátno, podklad, předaná
  šířka i hledání nakreslených bajtů na jednom místě. Druhá kopie by se rozešla zrovna v tom, na
  čem to stojí (viz odrážky výš), a měřila by pak jiný tab než ta první.
- **Šířka tabů bez panelu (#294)** — `PanelFreeTabWidthTests`, přes pásmo **648–1800**. Tvrdí totéž
  co suita `Přehledu` (za pravou hranou tabu se nekreslí nic), jen o `Kontrolách`, `Nálezech`
  a `Průběhu`, kterým #294 sebrala postranní lištu — takže se v nich najednou sází v širším místě.

  **Jiné pásmo než u `Přehledu`, a je spočítané**: spodní kraj je 648 bodů (okno má podlahu 700,
  rail bere 52) a panel se z něj neodečítá, protože v těch třech tabech není. Suita `Přehledu`
  začíná dál na 128, protože tam vytažený panel 520 bodů ukrojit umí.

  Co se u toho ukázalo:

  - **Riskantní je jediný z těch tří tabů.** `Kontroly` a `Průběh` sázejí pružně, takže přetéct
    nemají čím; `Nálezy` si šířky sloupců **počítají** (`Policy.findingTableLayout`), a to je jediné
    místo, kde se dá spočítat špatně. Změřené jsou přesto všechny — „pružné nemůže přetéct“ je
    úvaha, ne měření.
  - **Vytažený podstrom měří něco jiného než tab.** `FindingsTabView` bere šířku z prostředí
    (`@Environment(\.availableWidth)`), a to dorazí jedině do view, které SwiftUI doopravdy skládá.
    První verze testu proto sázela na výchozích 1000 bodů a hlásila **120 bodů přesahu ve třech
    šířkách, ve kterých je v okně nula** — bylo to přetečení sondy, ne tabu. Odtud parametr
    `FindingsTabView.scrolls`: tab se rendruje celý, jen bez `ScrollView`u. `OverviewView.content`
    zvenčí vytáhnout jde právě proto, že si z prostředí nebere nic.
  - **Podlaha shrnutí v tabulce je vědomé přetečení a je potřeba vědět, od kdy.** Hlídá to
    `FindingTableTests` (pásmo po 8 bodech): pod 590 se shrnutí opře o podlahu 120 a tabulka
    přeteče, nad ní se sloupce vejdou přesně. Po #294 je 590 **mimo dosah**, protože nejužší tab má
    648; s vytaženým panelem se tam dostával (~122 bodů, přesah ~468).

  **Vyzkoušené vložením regrese**: po smazání `inset * 2` z rozpočtu sloupců hlásí měření **32 bodů
  přesahu ve všech šesti šířkách** a `FindingTableTests` 145 porušení. Sonda tedy měří.
- **Sonda tabů detailu (#294)** — `DetailTabRenderProbe`, gated `PRISM_MEASURE`. Vyrendruje **celý
  detail PR ve všech sedmi tabech** (`NSHostingView`), v širokém i v nejužším okně a v tom úzkém
  i se **složeným** panelem. Nic netvrdí; je to způsob, jak vidět, kde lišta je a kde není.

  Rendruje se **celý detail, ne jednotlivé taby**, a to je u téhle změny podstatné: co se schovává,
  není obsah tabu, ale jeho **sourozenec** v `HStack`u — render samotného tabu by o tom neřekl nic.
  Složený proužek má vlastní scénář proto, že je úzký: z jednoho renderu se nepozná od hrany okna,
  takže „schoval se“ a „je tam pořád“ vypadají stejně.
- **Tab `Commity` (#316)** — čtyři sady, každá o něčem jiném.

  - **Tři stavy tabu, vyčerpávajícím výčtem** (`CommitsTabStateTests`). Šest kombinací vstupů
    (`commits` nenačtené / prázdné / neprázdné krát `failure` je / není) dává **tři** odpovědi, ne
    čtyři. Jediný řádek, ve kterém se to liší od `checksTab`, je **prázdné pole bez poruchy**: tam
    vyjde `failed`, protože pull request bez commitů neexistuje a klidná hláška o prázdnu by
    tvrdila nemožný stav. Vedle výčtu stojí test, který tvrdí, že se něco **NEstalo**: prázdné pole
    se nikdy nedostane do `list`, ať je `failure` jakékoli. Kdyby `CommitsTabState` dostal `empty`,
    spadne to tam, ne až v okně.
  - **Pořadí: nejnovější nahoře** (`Policy.commitsNewestFirst` a `commitsTab`). Tři případy, protože
    otočení se dá pokazit třemi způsoby. Že **co přišlo z API poslední, je v tabu první** — a totéž
    nad zastaralým seznamem, jinak by se otáčel jen ten čerstvý a věta nad ním by mluvila o tom
    druhém. Že se **otáčí, neřadí**: nad seznamem, kde má prostřední commit nejnovější datum
    (cherry-pick), musí zůstat topologické pořadí pozpátku — `sorted(by: committedAt)` ten test
    položí. A ve store, že **mapa drží pořadí z API** a otáčí až tab; kdyby se otáčelo při ukládání,
    stalo by se z pořadí kresby uložená vlastnost dat.

    **Vyzkoušené vložením regrese, obojí zvlášť**: `commits.reversed()` vyměněné za `commits` položí
    pět testů (včetně toho na pilulku `hlava`), a stará věta `od nejstaršího` v pruhu položí dva
    další. Jsou to dvě různé regrese schválně — pořadí a věta o pořadí se dají rozejít každé na svou
    stranu a jedna sada by tu druhou nechytila.
  - **Která pilulka `hlava`** (`Policy.headCommit(in:head:)`) — druhý nejcennější test sady, protože
    to je **tvrzení**, ne dekorace: nálezy jsou klíčované `headSha`. Po otočení seznamu je ta past
    horší, ne menší: hlava obvykle **je** nahoře, takže by se prohlédnutí `first` místo hledání sha
    nepoznalo. Test proto hledá hlavu **všude jinde než nahoře** — uprostřed seznamu i na jeho
    konci —, hlava **mimo seznam** se neoznačí vůbec (po pushnutém commitu je seznam o krok pozadu,
    nad stropem API v něm hlava chybí) a bez známé hlavy se vezme **první**, jak to plyne z definice
    endpointu a otočení.
  - **Skloňování** — `1 commit` / `2 commity` / `7 commitů`, k tomu `21 commitů` (v češtině nikoli
    `commit`) a nula. „PR má jeden commit“ je jeden ze tří stavů, které se podle zadání nesmí slít,
    a `1 commitů` by z něj udělalo chybu sazby. K tomu **strop API**: nad 250 commitů věta řekne,
    že seznam nemusí být celý — text, který by jinak tvrdil víc, než data unesou. A k tomu jeden
    test, který tvrdí, že se něco **NEstalo**: v žádné podobě té věty nesmí zbýt „nejstarší“. Pruh
    je jediné místo, které pořadí pojmenovává, takže rozejít se s ním umí potichu — pozná se to
    jedině přečtením obrazovky, ne z testu na pořadí.
  - **Dekódování odpovědi** (`GhCommitTests`) nad **skutečnou** fixture `gh/pr-commits.json`
    (`cli/cli#13899` — sedm commitů, z toho tři sloučení; veřejné repo schválně). Tvrdí se čtyři
    věci: seznam se přeloží na řádky včetně `parents` → `isMerge`, **pořadí se nemění**, chybějící
    pole seznam nepoloží (zbývá jediná tvrdá podmínka — `sha`) a `avatar_url` se čte ze
    `snake_case` klíče, protože REST píše jinak než `gh … --json` a převod klíčů se na sdíleném
    dekodéru zapnout nesmí.

    **`author: null` se testuje inline JSONem**, ne fixture, a je u toho napsané proč: veřejné
    repo tenhle tvar nemá a titulky firemních PR do fixture nepatří. Změřeno na
    `keboola/job-queue-daemon#858`, kde je `null` u **všech sedmi** commitů — takže to není
    kuriozita, ale běžný stav, ve kterém musí zbýt jméno z gitu a monogram místo obrázku.
  - **Načítání ve store** (`AppStoreCommitsTests`) — pět stejných pastí jako u checků a jedna
    navíc: porucha se nesmí zapsat jako prázdno (u commitů o to hůř, prázdno je tam nemožný stav),
    zrušení se nezapisuje jako chyba, selhaný pokus **nezahodí** starou sadu, `Zkusit znovu`
    poruchu přepíše, spadlý detail načtení nezastaví a **zrušené načtení se dotáhne po návratu na
    PR**. Šestý je ten, který tvrdí, že se něco NEstalo: `loadDetail` třikrát za sebou = **jedno**
    volání `fetchCommits`, jinak by z commitů byl polling. Sedmý hlídá **hranici mezi daty
    a kresbou**: mapa nese pořadí z API, stav tabu je otočený.
  - **Šířka tabu** — `Commity` jsou čtvrtý tab bez panelu, takže mají vlastní případ
    v `PanelFreeTabWidthTests` (pásmo 648–1800). Perou se o šířku dvě věci naráz: dlouhá první
    řádka zprávy (`Merge branch 'trunk' into fix/13804-…`) a pilulka se sha u pravé hrany. Zpráva
    se řeže, sha ne — takže kdyby se řez ztratil, přeteče to vpravo. **Vyzkoušené vložením
    regrese**: `lineLimit(1)` vyměněné za `fixedSize()` dá v nejužší šířce (648) přesah 14 bodů.
    Chytá to jen tam, a je to tak správně — v širokém tabu se ta zpráva vejde, takže přetečení
    v něm neexistuje.
- **Diff jednoho commitu (#317)** — tři sady, a ta první je celý důvod, proč se tab nedotýká
  tvrdých podmínek.

  - **Že se v tabu nedá nic napsat** (`CommitDiffReadOnlyTests`) — nejcennější sada #317, protože
    tvrdí, že se něco **NEstalo**, a zrušit to jde jedním přidaným parametrem. Testuje se ve **třech
    vrstvách**, protože každá sama by prošla naprázdno:

    1. **Co tab předá `DiffView`u** — nálezy, akce nad nálezy, vlákna, rozdělané komentáře, panel
       i procházení musí být prázdné/`nil`. Čte se to z `CommitDiffView.reading(_:)`, které je
       `internal` právě kvůli tomuhle.
    2. **Co z toho vyjde v řádcích** — z týchž hodnot se poskládá `DiffRow.rows` a mezi nimi nesmí
       být `.finding` ani `.draftComments`.
    3. **Že žádný řádek nenabídne akci** (`FileDraftActions.action(for:)` je `nil` na **všech**
       řádcích souboru). Bubliny se dají odebrat i tak, že tlačítko u řádku zůstane — a tiše
       založený komentář je horší než bublina, protože se odesílá.

    U druhé a třetí vrstvy stojí **protipól se stejnými daty v režimu review**, který bublinu
    (resp. akci) vyrobit **musí**; bez něj by sada procházela i tehdy, kdyby se bubliny přestaly
    kreslit úplně. **Vyzkoušené vložením regrese**: `findings:` a `draft: DraftActions(canCompose:
    true)` dosazené do `reading(_:)` položí **tři testy z pěti a 50 tvrzení**.
  - **Stav tabu, vyčerpávajícím výčtem** (`CommitDiffTabStateTests`). Čtyři stavy, a dva z nich se
    dají snadno splést: **cizí sha je `loading`**, ne prázdno (v okně leží nejvýš jeden diff commitu
    na PR, takže hned po kliknutí na jiný commit tam ještě je ten předchozí), a **prázdný diff je
    `nothing` s větou**, ne porucha. Sloučení a obyčejný commit dostanou **různé** věty a obě říkají
    „není to porucha“ — testuje se, že se liší, ne jen že nejsou prázdné. K tomu commit, který
    ze seznamu zmizel (force push) → tab spadne na seznam, skloňování počtu souborů, pozice
    `2 ze 7` v pořadí kresby a adresa commitu na GitHubu. K tomu **tělo zprávy a jeho sbalování**:
    že tělo je všechno pod první řádkou (titulek nad ním je ta první), že jednořádková zpráva tělo
    **nemá** — a tedy že se nekreslí ani přepínač —, a že počet řádků je **jen ve sbaleném**
    popisku, i s prázdnými řádky mezi odstavci a se skloňováním.

    A od #339 **zakončení řádků**, pět případů, protože zprávy commitů chodí z `gh` z cizích
    repozitářů. Jádro je počet řádků nad **skutečnou** odpovědí (`gh/pr-commits-crlf.json` —
    `git-for-windows/git#6293`, commit `415ab35` s míchanými zakončeními: titulek `LF`, tělo `CRLF`):
    popisek musí říct `3 řádky`, do #339 říkal `1 řádek`, protože `"\r\n"` je jeden `Character`.
    Vedle toho **`CRLF` dá tentýž popisek jako `LF`** (odpověď na „nezměnilo se něco na `LF`
    vstupech?“), počet **nezávisí na zakončení** (`LF` / `CRLF` / samotné `CR` / míchané v jedné
    zprávě dají všechny `3 řádky`) a dvě tvrzení o `U+2028`: uvnitř **titulku** ho neusekne ani
    nepřelije do těla, v **těle** se za řádek nepočítá. Ta dvě jsou to hlavní, co se dá pokazit
    potichu — titulek a tělo jsou půlky jednoho rozdělení, takže rozpojený pojem „konec řádky“ by
    tentýž text ukázal v hlavičce dvakrát. Dekódovací strana je v `GhCommitTests`: že zpráva `CRLF`
    **nenormalizuje** a že se `CR` nepřilepí na konec titulku.

    **Fixture dekóduje jedno místo** — `Tests/Support/CommitFixture.swift`. Čtou ji tři na sobě
    nezávislá místa (dekódování, počet řádků, sonda) a tři kopie téhož `decode` by se rozešly zrovna
    v tom, na čem #339 stojí: stačilo by, aby si jedna z nich zakončení „pro pořádek“ znormalizovala,
    a sada by pak zeleně tvrdila něco o `CRLF`, které v datech není. `GhCommitTests.decode(_:)`
    zůstává, ale už jen na **inline JSON** (tvary, co se z veřejných rep nesehnaly).

    **Regrese ověřená vložením regrese, dvakrát zvlášť.** Vrácený `split(separator: "\n")` v počtu
    položí **3 testy a 5 tvrzení** (parametrizovaný spadne na 3 případech ze 4 — `LF` projde, což je
    přesně ten důvod, proč se to nechytilo dřív); `isNewline` zpátky v obou půlkách rozdělení položí
    test o `U+2028` **třemi** tvrzeními naráz: titulek `feat: cache` místo `feat: cache\u{2028}secrets`,
    `secrets` přelité do těla a počet `3 řádky` místo `1 řádek`.

    **Fixture v `.gitattributes` schválně není** a je to odchylka od zadání #339, které s `-text`
    počítalo: `CR` je v JSONu **escapovaný** (`\` + `r`), takže surových `CR` bajtů je v souboru nula
    (změřeno; `git cat-file -s` na staženém blobu vrací tytéž 3 664 B jako soubor na disku, přitom
    `core.autocrlf=input`). Řádek `-text` by byl kontrola, která nic nedělá, a ve výčtu by tvrdil, že
    zakončení té fixture drží on. Že přežilo, si hlídají obě sady samy (`#expect(…contains("\r\n"))`),
    a to platí bez ohledu na nastavení gitu. Zdůvodnění je i v `.gitattributes` jako komentář, aby to
    příště nikdo „neopravil“.
  - **Načítání ve store** (`AppStoreCommitDiffTests`) — sedm pastí. Že se **stažený diff drží**
    (druhé otevření téhož commitu se neptá znovu, jinak by z jednoho kliknutí byl polling), že se
    po selhání **ptá znovu** (jinak by `Zkusit znovu` nic neudělalo), že doběhlé volání **nepřepíše
    mezitím otevřený commit** (jinak by pod hlavičkou ležel cizí diff), že si návrat pamatuje
    **otevřený řádek**, že PR mimo seznam si diff nenechá — a dvě o klíči: rozbalení kontextu čte
    soubor **v tom commitu** (`fetchFile(repo:path:at:)`, a `fetchFile(id:path:)` se nesmí volat
    vůbec) a sbalení souboru se **nepropíše** do `Změněných souborů`.

    **Vyzkoušené vložením regrese, obojí zvlášť**: obsah tažený z hlavy PR položí test na ref, a
    `unfoldAll` bez filtru na commit položí test na sbalení.

    Devátý a desátý jsou o **sbaleném těle zprávy**: že je ve výchozím stavu vidět, a — to je ten
    o tom, že se něco **NEstalo** — že volbu nezahodí úklid, který PR i s jeho diffem vyhodí ze
    store. Sbalení je předvolba pohledu, ne vlastnost pull requestu; kdyby bydlelo v `@State`
    detailu, chovalo by se správně jen náhodou (SwiftUI si view mezi pull requesty ponechá) a tenhle
    rozdíl by se z okna nedal poznat.
  - **Šířka hlavičky** — tři další případy v `PanelFreeTabWidthTests` (pásmo 648–1800): hlavička
    s počty, **prázdný diff s vysvětlením** (jiný podstrom, hlavička v něm stojí bez počtů) a od
    sbalovacího těla i **obě podoby hlavičky se zprávou**, sbalená a rozbalená. Řádek meta se
    v úzkém okně musí zalomit přes `ViewThatFits`; kdyby se zvolila podoba na jeden řádek, přeteče
    tichá věta „Jen ke čtení…“ vpravo.

    **Sbalená hlavička není „ta samá o kus nižší“** — místo odstavců v ní stojí přepínač s počtem
    řádků, tedy jiný řádek s jiným zalomením, takže se měří obě. Fixture nese to, co tělo umí do
    hlavičky přinést a co se nikde jinde neměří: odstavce, odrážky a **dlouhý nezlomitelný token**
    (odkaz na issue). Tělo se zalamuje, netrunkuje, takže ztracená šířka přeteče vpravo.
- **Podoby pruhu záložek podle šířky (#316, #318)** — `TabStripWidthTests`. Měří se, neodhaduje:
  `NSHostingView.fittingSize` nad **skutečným** `PullRequestTabBar`em, po jednom bodu šířky.

  | Podoba | Ideální šířka tabu | Okno (+ rail 53) |
  |---|---|---|
  | `full` — popisky a `+X −Y` | 996–998 b | 1049–1051 b |
  | `labels` — popisky, bez `+X −Y` | 886–888 b | 939–941 b |
  | **`icons` — ikony, popisek u aktivní** (#318) | **498–564 b** | **551–617 b** |

  Čísla jsou pásma, protože šířka závisí na tom, **která záložka je aktivní**: v `icons` je aktivní
  popisek jediný, co se kreslí, a je polotučný. Horní konec drží `Změněné soubory`, dolní `Nálezy`.
  S trojmístnými odznaky u **všech** záložek vyjde `icons` na 636 b, tedy okno 689 — pořád pod
  podlahou okna (700), a **právě proto pruh nemá čtvrtou podobu** bez popisku i u aktivní.

  Z #316 platí dál cena pilulky a sedmé záložky: `+X −Y` stojí **110 bodů** (na `origin/main` před
  #316 se pruh vešel od 774 b bez ní a od 884 b s ní), sedmá záložka s odznakem **112** — na té
  shodě stojí první stupeň. Sada tvrdí šest věcí:

  - **pruh se nezalomí v žádném povoleném okně** (700–1400, přes **všech sedm** aktivních záložek).
    Do #318 to platilo od 939 nahoru a v okně 700 byl pruh 90 bodů místo 30 — se šesti záložkami
    75, takže to nebyla cena sedmé, ale stav rozbitý i bez ní;
  - **nezalomí se ani s trojmístnými odznaky**, tedy nad tím, co v okně kdy nastane. Je to strop,
    a zároveň to jediné, co drží tvrzení „čtvrtá podoba je nedosažitelná“;
  - **nezalomí se ani bez odznaků** — PR, na kterém ještě nic nedorazilo, je nejběžnější stav;
  - **v jaké šířce se kreslí která podoba** — porovnáním renderu celého pruhu proti té jedné podobě
    vykreslené napřímo (`bar(_:)`), pixel po pixelu, v šesti šířkách. Test tím nezávisí na tom,
    **čím** se podoby liší, jen na tom, že se vybrala ta správná;
  - **v úzkém pruhu se `+X −Y` nekreslí, v širokém ano.** Vlastní test vedle žebříku výš, protože
    ten by prošel i tehdy, kdyby `full` přestala rozsah změny kreslit úplně — porovnává obě strany
    proti témuž kódu. Tenhle porovnává render s počty proti renderu bez nich;
  - **popisky mizí, nekrátí se, a aktivní zůstává.** Zkrácený popisek nikam nepřeteče a pruh po něm
    zůstane nízký, takže na to nestačí ani měření přesahu, ani výška (poučení z #284). Hlídá se to
    porovnáním **ideální šířky vybrané podoby** s dostupnou šířkou: když se podoba vejde celá, nemá
    se co smršťovat. K tomu dvě tvrzení o `icons` — s aktivními `Změněnými soubory` je o víc než
    50 b širší než s aktivními `Nálezy` (tedy aktivní popisek se kreslí) a o víc než 250 b užší než
    `labels` (tedy těch šest ostatních se nekreslí).

  **`ViewThatFits` tady na rozdíl od #284 stačí, a je to změřené, ne předpokládané.** V #284 byly
  popisky v řadě se `lineLimit`em, takže se **zkracovaly** a `ViewThatFits` vybíral pořád nejširší
  variantu; rozhodovat proto musela spočítaná šířka (`TextWidth`). Pruh záložek `lineLimit` nikde
  nemá, takže se **zalamuje** — ideální šířka zůstává šířkou celého popisku a je to přesně to, co
  `ViewThatFits` porovnává. Tvrdí to ten žebřík výš: kdyby vybíral nejširší variantu, v tabu 647 b
  by nakreslil `full` a render by se s `bar(.icons)` nerovnal.

  **Měří se na `NSHostingView`, ne `ImageRenderer`u**: ten `ViewThatFits` vyhodnocuje jinak než
  skutečné okno, takže by test měřil něco jiného, než co je vidět.

  **Vyzkoušené vložením regrese**, dvakrát:
  - **smazání `bar(.icons)` z `ViewThatFits`** položí čtyři testy: pruh vyjde v okně 700 na 90–105
    bodů (podle aktivní záložky), zalomí se i bez odznaků a žebřík přestane sedět ve dvou šířkách;
  - **`showsLabel = layout != .icons`**, tedy zahození popisku i u aktivní záložky, položí `Aktivní
    záložka si popisek nechá` (451 b proti 501 b) — chyba, kterou by výška pruhu nechytla, protože
    kratší pruh se nezalomí tím spíš.

  **Absolutní čísla ze specifikace se nepoužila** — měřila je replika pruhu a vyšla o 17 bodů níž
  (867/920 a 872/925 u #316; 602/655 pro `icons` u #318 proti naměřeným 564/617). Rozdíl, o který
  u #316 šlo, replika odhadla dobře (+5 bodů okna proti skutečným +2), ale hranice se z ní brát
  nedají.
- **Sonda pruhu záložek (#318)** — `TabStripRenderProbe`, gated `PRISM_MEASURE`. Nic netvrdí;
  vyrendruje pruh přes **pásmo šířek tabu** (647–1347) s odznaky i bez, **ikonový stupeň s každou
  ze sedmi aktivních záložek** a tři šířky v **tmavém režimu**. „Pozná se záložka bez popisku?“ je
  otázka na obrázek, ne na číslo.

  **Je to jedno místo pro celý pruh.** Do #318 se tentýž pruh rendroval ve dvou sondách tabů
  (`ChecksTabRenderProbe` v pásmu 620–1020 s aktivními `Kontrolami`, `CommitsTabRenderProbe`
  v 647–1047 s aktivními `Commity`), takže se obrázky nedaly položit vedle sebe — a obě sondy měly
  u sebe text o tom, jak se pruh zalomí, což od #318 neplatí. Pruh není součást žádného z těch
  tabů; stojí nad všemi sedmi.
- **Sonda tabu `Commity` (#316, rozšířeno #317 a #339)** — `CommitsTabRenderProbe`, gated
  `PRISM_MEASURE`.
  Nic netvrdí; vyrendruje **detail PR v tabu `Commity` ve všech podobách stavu** (nenačteno, seznam,
  porucha, zastaralý seznam, **PR s jedním commitem**, a od #317 **rozkliknutý commit** v pěti
  stavech — diff, **týž diff se sbalenou hlavičkou**, prázdný diff sloučení, nenačteno, porucha) ve
  dvou šířkách; seznam a diff commitu obojí navíc v **tmavém režimu**. Sbalená hlavička dostane
  **týž commit** jako rozbalená, jinak by se snímky nedaly položit vedle sebe a nebylo by z nich
  vidět, kolik místa se sbalením získá. Scénář drží commity v pořadí z API, takže je na snímcích vidět i to, že
  je tab **otáčí sám** — nejnovější nahoře, a mátová pilulka `hlava` s ním. Pruh záložek se od #318
  rendruje jinde, v `TabStripRenderProbe`.

  Podob je pět, i když `CommitsTabState` má tři případy: `list` se kreslí dvakrát (se zastaralostí
  a bez ní) a `jeden-commit` je tentýž stav s jinými daty — je to ale zrovna to, co se z čísel
  nepozná, protože skloňování je vidět až v sazbě. **Prázdný stav mezi nimi není schválně**; na
  snímku `porucha` je vidět, že se prázdná odpověď hlásí jako porucha.

  **Stav diffu commitu se staví přímo do `commitDiffs`, ne přes `openCommit`** (#317): ten spouští
  `Task`, na který by render čekal, a rozdělaný stav (`nenacteno`) by se tudy nedal vyrobit vůbec.
  Rozkliknutý commit je ten **s tělem zprávy**, protože na jeho hlavičce je co posuzovat — u
  prázdného diffu naopak **sloučení**, protože právě u něj má věta jiné znění.

  **Šestý scénář rozkliknutého commitu přidalo #339: sbalená hlavička nad zprávou s `CRLF`**
  (`diff-commitu-sbalena-hlavicka-crlf`). Je tam proto, že ke stavu se **normálním používáním nedá
  dojít** — musel by v tabu ležet PR s `CRLF` ve zprávě commitu —, takže sonda je jediná cesta, jak
  se na ten popisek podívat. Zpráva se bere **z fixture** `gh/pr-commits-crlf.json`, ne z literálu
  v sondě: ručně napsaná by nesla `LF` toho, kdo ji napsal, a sonda by kreslila stav, který `gh`
  nevrací. Ostatní commity zůstávají, aby se snímek dal položit vedle
  `diff-commitu-sbalena-hlavicka`. Změřeno: v popisku stojí `Tělo zprávy · 3 řádky`, do #339 tam bylo
  `1 řádek`. **Rozbalená podoba se nerendruje** — počet je jen ve sbaleném popisku, takže by na ní
  nebylo co posoudit; že se `CRLF` tělo sází jako tři řádky bez zbylých glyfů, je ověřené jednorázově
  při #339 (přepnutý příznak, snímek, vráceno).

  Pořadí ve scéně je podmínka, tatáž jako u `ChecksTabRenderProbe`: `loadDetail` si commity
  dotahuje sám, takže se **nastavují až po něm**, jinak by je přepsal. Tmavý režim se nastavuje
  **dvakrát** (`NSAppearance` kvůli paletě a `colorScheme` kvůli `.primary`/`.secondary`) —
  s jedním z toho vyjde tmavý text na tmavém, poučení z #278.

- **Sonda `Přehledu` (#291)** — `OverviewRenderProbe`, gated `PRISM_MEASURE`. Nic netvrdí, jen
  vyrendruje tab přes `NSHostingView` ve třech šířkách a obou režimech, aby se dal **vidět**.
  Existuje vedle měření proto, že „vejde se hlavička do zúženého tabu“ je otázka na vzhled —
  a `ImageRenderer` na ni odpovědět neumí: `Link` v něm vyjde jako **žlutý placeholder**, takže se
  z něj šířka popisku `Otevřít na GitHubu` nepozná. A byl to zrovna ten popisek, který v #291
  chyběl. `NSHostingView` kreslí skutečnou hierarchii, takže odkaz v něm stojí ve své šířce —
  ověřeno, čitelný celý.

  **Od #280 má každá šířka i variantu s pruhem „od minule“.** Důvod je sousedství, ne úplnost:
  řada faktů se přesunula nad popis, takže jejím novým sousedem shora je ten pruh — a ten je okrový
  (`Palette.stale`) zrovna tak jako zastaralá sha v posledním boxíku. Dvě okrové plochy nad sebou
  se posuzují okem, ne z kódu.

  **Od #284 je těch variant pět** (`Scenario`), protože se liší **řadou pod odrážkami** a ta se
  z kódu nepozná: `bez-pruhu`, `nove-commity` (jen `Ukázat, co přibylo`), `zastarale-nalezy`
  (odznak a obě tlačítka, tedy nejširší řada), `prepsana-historie` (jen `Pustit review znovu`,
  odznak ne — nálezy nejsou) a `prepsana-se-zastaralymi` (odznak a `Pustit review znovu`, rozsah
  ne). Že se `Ukázat, co přibylo` po přepsané historii nenabízí, je rozhodnutí — a rozhodnutí se
  ukazují, ne popisují.
- **Sonda rozsahového diffu (#284)** — `DetailTabRenderProbe.rendersTheIncrementalDiff`, dvě šířky.
  Návrh tuhle obrazovku nekreslí (sekce 02 má tlačítko, ne stav po jeho stisknutí), takže je to
  jediné místo, kde se dá posoudit: rozsahový diff vypadá jako celý diff, jen kratší, a jestli je
  z lišty poznat proč, se z kódu nezjistí. **Pozor u obou sond**: `-only-testing` se u swift-testing
  musí zadat **na suitu**, ne na jeden test — se jménem metody proběhne „0 tests“ a v adresáři
  zůstanou staré PNG, takže to vypadá, že se změna neprojevila.
- **Pořadí v `Přehledu` (#280)** — `OverviewOrderTests`: **řada faktů stojí nad kartou s popisem.**
  Je to jediné, co #280 mění, a rozbije se to potichu — přehozený `VStack` build nepoloží
  a `OverviewWidthTests` projdou v obou pořadích, protože přesah je v obou nulový.

  Měří se **z pixelů, ne z hierarchie**, a využívá se k tomu tvar obou částí: řada faktů je mřížka
  čtyř dlaždic s mezerami 9 bodů, takže ve svislém pruhu **mezi** dlaždicemi nekreslí nic, kdežto
  karta s popisem je jedna plocha přes celou šířku a kreslí tam. Stačí tedy porovnat, kde obsah
  začíná uprostřed první dlaždice (= vrchol řady faktů) s tím, kde začíná v mezeře za ní
  (= vrchol karty). Fakta jsou nad popisem právě tehdy, když je první číslo menší.

  **Měří to `OverflowProbe`, ne vlastní scéna.** Je to druhá otázka nad **týmž plátnem** — ne
  „přeteklo něco vpravo“, ale „co je výš“ — takže tam přibyla metoda, ne nová sonda vedle:
  plátno, purpurový podklad, porovnání proti druhému renderu i tolerance 5 z 255 mají zůstat jedny.
  Dvě sondy nad stejnou scénou znamenají dvě měřítka toho, co se počítá za nakreslené, a ta se
  rozejdou potichu. Sloupce se přitom předávají **najednou**: jeden dotaz stojí dva rendery (obsah
  a podklad), takže ptát se dvakrát na totéž plátno je čtyřnásobek práce za tutéž odpověď —
  změřeno, 5,8 s proti 1,3 s přes osm šířek.

  Banner „od minule“ se v téhle suitě **schválně nekreslí**: je to další plocha přes celou šířku,
  takže by v mezeře mezi dlaždicemi začínal dřív než popis a měřil by se místo popisu on.

  **Ověřeno vloženou regresí**: po prohození obou prvků ve `VStacku` vyjdou obě čísla na 16
  (plná plocha karty kreslí v obou sloupcích) a suita spadne ve **všech osmi šířkách**. Druhý
  test je pojistka proti tomu, že by měření vracelo „nic se nenakreslilo“ a suita byla zelená
  omylem.

  Že se u toho **nezměnila sazba ani šířka**, se dokázalo jinak než testem: render `Přehledu`
  před změnou a po ní má při každé ze tří šířek, obou tématech i obou stavech banneru **shodnou
  velikost plátna a shodnou multimnožinu otisků vodorovných řádků**. Řádky se tedy jen přesunuly
  (~580 z nich při 900 bodech), žádný se nepřekreslil — což je přesně to tvrzení, které diff
  s přehozeným pořadím musí unést.

- **Detail spadlého checku (#214)** — `Policy` výčtem (`CheckLogTextTests`) a store
  (`AppStoreCheckDetailTests`). Nejcennější testy tvrdí, že se něco **NEstalo**:
  - **bez kliknutí se pro log ani anotace nejde** — jinak je to N+1 past o tři řády dražší
    než u detailu PR;
  - **nad známým stropem se pro log vůbec nejde** — hlídá se, že se zjistila velikost
    a **nestahovalo**;
  - **dokud se stahuje, drží se velikost z `HEAD`u** (#292), aby se dala napsat do hlášky — testuje
    se to na **mezistavu** přes `AsyncGate`, ne na výsledku, protože jinak by se dalo zkontrolovat
    jen to, co zbylo na konci. Věta sama je čistá funkce (`Policy.logDownloadNotice`) a testuje se
    výčtem: se známou velikostí ji nese, bez ní **neslibuje nic** — ani nulu;
  - **bez známé velikosti se log naopak stáhne** (#292) a strop se uplatní na tom, co přišlo. Do
    #292 tady stálo pravidlo obrácené („bez velikosti se nestahuje“) a bylo to zeleně otestované —
    jenže rozbor hlaviček velikost nikdy nevydal, takže tenhle test **popisoval vypnutou funkci**.
    Poučení pro katalog: test, který tvrdí „tohle se nestane“, si musí ověřit, že ten stav je
    **výjimka**, ne obvyklý běh. Testy k tomu jsou čtyři — velikost nepřišla, dotaz na ni spadl,
    stažené bajty jsou nad stropem, a když spadne obojí, je vidět chyba **stažení**, ne chyba
    `HEAD`u;
  - **sbalení stažený text zahodí a běžící stahování zruší**;
  - **selhání se nesmí tvářit jako prázdno** — ani u logu („nepodařilo se stáhnout“ ≠ „log je
    prázdný“), ani u anotací, kde prázdno je navíc **běžný** stav, protože je workflow emitovat
    nemusí. K tomu, že spadlé anotace **nepoloží log** — jsou to dvě samostatné cesty;
  - **číslo běhu se nevydává za číslo jobu** (`…/runs/<id>` bez `/job/`) — log běhu je log všech
    jeho jobů. Ověřeno na skutečných odkazech CodeQL a borsu.

  **Regrese ověřená vložením regrese**: strop, který se ignoruje, položí dva testy; selhání
  zapsané jako prázdný log jeden.

- **Rozbor hlaviček `gh api -i` (#292)** — `GhResponseHeadersTests`, výčtem, a je to **oprava chyby,
  kterou našel až člověk v běžící aplikaci**. Stojí za to vědět proč: fixture byla vymyšlená.

  Test si hlavičky psal jako Swiftový víceřádkový literál, tedy s `LF` — a `gh` je zakončuje `CRLF`.
  `"\r\n"` je přitom ve Swiftu **jeden `Character`**, takže `split(separator: "\n")` na něm
  nerozdělí a z celého bloku hlaviček zbyde jeden „řádek“, ve kterém se `Content-Length` nenajde.
  Test byl zelený, v aplikaci konec logu nefungoval u **žádného** checku. V shellu to přitom šlo,
  protože tam hlavičky čtou oči.

  Odtud dvě věci do katalogu:
  - **Fixture textového protokolu musí být skutečný výstup, bajt za bajtem** —
    `gh/job-log-head.txt` je `gh api -X HEAD -i` na veřejný job `home-assistant/core`. Ruční
    literál nese zakončení řádků toho, kdo ho napsal, ne toho, kdo výstup vyrábí.
  - **Fixture, která stojí na `CRLF`, potřebuje `.gitattributes` `-text`.** `core.autocrlf=input`
    (nastavení na tomhle stroji) by `CR` při commitu zahodilo a test by přestal testovat, kvůli čemu
    vznikl — potichu a zeleně. Test si proto **kontroluje i tu fixture** (`output.contains("\r\n")`).

  Výčet pokrývá `LF`, `CRLF` a samotné `CR`, lowercase jména (`HTTP/2`) i Title-Case, víc bloků za
  sebou (rozhoduje **poslední**, protože ten před redirectem má `Content-Length: 0`), hodnotu
  s dvojtečkou, rozbitý stavový řádek a všechna čtyři „velikost nevyšla“ zvlášť. Past navíc, kterou
  ta odpověď doopravdy má: `Content-Length` je i **v hodnotě** `Access-Control-Expose-Headers`, a to
  na řádku **před** tou skutečnou hlavičkou — hledání podřetězce by tedy vrátilo výčet jmen.

  **Regrese ověřená vložením regrese**: vrácené `split(separator: "\n")` položí v téhle sadě 25
  tvrzení, a v `CheckLogTextTests` tři (`Policy.logLines`, kde je to tatáž past nad logem
  z Windows runneru).

  **Ořez logu se testuje i na koncovém `\n`** — kdyby se počítal jako řádek, tvrdil by ořez log,
  který se do stropu vešel přesně. A hláška o vynechaných řádcích se u čtyřciferného počtu
  porovnává **po částech**: `Plural.czech` dělí tisíce nezlomitelnou mezerou, takže napsaná
  `3 812` je červená a test by tvrdil něco o formátování čísel.

  Vzhled je doložený offscreen renderem ve světlém i tmavém režimu přes všech pět stavů detailu
  (načítá se, bez anotací, nad stropem, selhalo, „nevešlo se“). Chytil dvě věci, které z kódu
  vidět nejsou: **konec logu se vystředil** místo zarovnání doleva (`ScrollView` centruje obsah
  užší než viewport a `Spacer` ani `frame(maxWidth:)` to uvnitř dvouosého scrollu nespraví) a
  **tři stovky řádků odtlačily zbytek seznamu** mimo obrazovku.

  **Cena sazby logu má vlastní měření** (`CheckLogPerformanceMeasurement`, `PRISM_MEASURE=1`) —
  není to test, netvrdí časy. Log v něm je syntetický podle skutečných rozměrů, a když je po ruce
  ten skutečný, vezme se on (`PRISM_LOG_FILE`); osmimegový soubor se do repa nepřikládá.

  Od #303 je v něm i **cena skoku na konec logu** — do té doby se v aplikaci nedělal vůbec (skákalo se
  do okýnka bez výšky a posun se zahodil), takže se za něj neplatilo, ale taky se nikam neskočilo.
  Naměřeno 11 / 47 / **128 ms** pro 300 / 2 000 / 6 000 řádků: `scrollToEndOfDocument` vynutí sazbu až
  na konec dokumentu, tedy tu jedinou drahou věc, kterou aplikace jinak nedělá. Je to jednorázově, při
  rozbalení checku, po vteřinách čekání na stažení.

  **Tři pasti u toho měření.**

  - **Prefix `TEST_RUNNER_` je podmínka, ne ozdoba** — `PRISM_MEASURE=1 xcodebuild` do testovacího
    procesu nedojde, `TEST_RUNNER_PRISM_MEASURE=1` ano (a `TEST_RUNNER_PRISM_LOG_FILE` taky). Suita
    bez proměnné se tiše **přeskočí** a vypadá to, že proběhla, takže se to nepozná z výsledku.

    **Opraveno u #303**: do té doby tu (a v komentáři té suity) stálo, že to `xcodebuild` nepředá ani
    s prefixem a že se měření pouští jedině z Xcode. Není to pravda — vyzkoušeno; a stejně to má
    popsané sonda sazby o pár odstavců výš, takže tu dvě místa tvrdila dvě různé věci. Cena té
    domněnky: měření se po #292 nepustilo znovu, protože to vypadalo, že to z příkazové řádky nejde.

    Že ochrana sama zbytečná není, se taky ověřilo: bez ní běželo měření SwiftUI `Text`u na hlavním
    vlákně **199 s** a vyhladovělo celou sadu — čtyři nesouvisející testy spadly na timeout a vypadalo
    to jako regrese v nich.
  - **Měřit se má jen to, co aplikace umí** (#303). Skok na konec logu se měřil i na celých 25 000
    řádcích a vynucená sazba **položila testovacího hosta** (595 ms a pak pád) — přitom ocas je vždycky
    nejvýš `Policy.logTailLines`, takže se tou cestou nikdy nejde. Výčet je proto z mezí, které
    aplikace doopravdy měla: 300, 2 000 a dnešních 6 000.
  - **Měření musí měřit tu cestu, kterou kód jde.** #214 měřilo sazbu logu přes
    `ensureLayout(for:)` + `usedRect(for:)`, tedy **vynucenou sazbu celého dokumentu** — jedinou věc,
    kterou aplikace nedělá. Vyšlo 850 ms tam, kde skutečná cesta stojí 6,57 ms, a z toho vzešel
    strop o řád nižší, než bylo potřeba. Tatáž chyba byla v měření obarvování: srovnávalo `job.log`
    se `job.log`, tedy dvě jednolité cesty, a tvrdilo „0,04 proti 0,02 ms“; po řádcích se teď měří
    pod `job.swift`, kde `Language` jazyk najde.

- **Závora `AsyncGate` čeká na jev se stropem v čase, ne v `yield`ech** (#292). Rozpočet yieldů
  (`for _ in 0..<100_000`) je pevný okamžik v přestrojení: pod zátěží druhého paralelního buildu se
  vyčerpal dřív, než se čekaná práce dostala na procesor, a závora položila **tři suity naráz**
  („práce se k závoře nedostala“) — přitom samostatně proběhly za 0,094 s. Je to tatáž chyba, kterou
  #269 vyndalo ze sondy odpočtu; spánek navíc na rozdíl od `yield`ování pustí procesor jinam. Strop
  zůstává, aby se test při skutečné chybě **položil, ne zasekl**.

  **Od #296 to není závora, ale pravidlo pro celé `Tests/`** — a bydlí v `Tests/Support/TestWaiting.swift`.
  Viz sekce *Čekání na jev* níž; `AsyncGate` z ní jen volá `waitUntil`, aby v repu nebyly dvě
  implementace jedné věci.

- **Šířka sheetu s kódem (#292)** — `DiffWidthTests`, výčtem nad `Policy.codeSheetWidth`. Hlídá čtyři
  meze, z nichž každá se dá porušit zvlášť: **na běžné obrazovce je širší než dřív**, **nikdy užší než
  dřívějších 820** (zúžení by byla regrese, ne kompromis), **na malý displej se vejde** (tam rozhoduje
  displej, ne konstanta z většího) a **na ultrawide se zastropuje**. K tomu monotonie přes pásmo
  600–3 400 bodů, protože jednotlivé případy minou aritmetickou chybu uprostřed.

- **Výška okýnka konce logu (#292, strop zvednutý u #303)** — `LogTailHeightTests`, výčtem. Počítá se
  z metriky **toho** fontu, kterým se kreslí (#236), takže se dá tvrdit přesná hodnota — a od #407
  proti **témuž měřidlu**, ze kterého ji bere aplikace (`FontMetric`), ne proti vlastnímu
  `NSLayoutManager`u. Dvě čtení metriky v jednom procesu se totiž pod souběžným buildem tří slotů umí
  rozejít a výška vyšla o **tři řádky** vedle; podrobnosti v *Metrika písma je tentýž kořen v jiné
  podobě (#407)*. Co se dá pokazit potichu: **zastropovat i krátký log** (pod třířádkovým by zbylo
  445 bodů prázdna) a **nezastropovat dlouhý** (šest tisíc řádků naplno odtlačí seznam checků mimo
  obrazovku, tedy zrovna to, kvůli čemu se detail stěhoval z `Přehledu`). Regrese ověřená vložením
  regrese: vyndaný `min(limit, …)` položí sedm tvrzení.

  **Strop se v sadě bere z aplikace, ne opisuje** (#303) — jinak by se s ním test rozešel potichu.
  Tvrdí se u něj to jediné, co tvrdit jde: že padne na **celý počet řádků** (`14N + 25`) a že jich je
  30. Strop, který slibuje 30 řádků a ukáže 29, je horší než o 4 body vyšší okýnko.

  **Tvrzení o rezervě na scroller je odsud pryč** (#347) — je to sada níž. Tady zůstává jen aritmetika
  **nad** tou konstantou, a je to hranice, která má důvod: aritmetika neumí poznat, že je konstanta
  sama špatná. Doloženo vloženou regresí — s rezervou 13 a stropem 441 projde celá tahle sada zeleně.

- **Rezerva na vodorovný scroller u konce logu (#347)** — `LogTailScrollerReserveTests`, `@MainActor`.
  **Nedopočítává, měří na kresbě**, a to je celý důvod, proč je to sada zvlášť.

  Co se stalo: do #347 držel rezervu jeden test, který ji porovnával s
  `NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy)`. Byl zelený — a hlídal přitom
  **jinou velikost scrolleru, než jakou okýnko kreslí**. `LogTailTextView.makeScrollView()` nechává
  `NSScrollView`u výchozí `.regular`, a ten bere **17 bodů**, ne 13. Test tedy zopakoval tu samou
  úvahu jako kód a byl zelený nad rozbitou hodnotou; je to čítankový příklad toho, proč se u #236
  měří na tom, na čem se kreslí. **Vacuous test, který vypadá jako pojistka** — tatáž třída omylu jako
  `-text` v `.gitattributes`, které se ověří až na blobu (#353).

  Proto se tady nic neodvozuje: postaví se `makeScrollView()`, dostane dokument s řádkem o 2 258
  znacích (bez něj se scroller kvůli `autohidesScrollers` neobjeví a nebylo by co měřit)
  a **odečte se, kolik z výšky ubylo**. Pět tvrzení:

  | Co | Změřeno |
  |---|---|
  | Zábor **legacy** scrolleru je to, co se rezervuje | okýnko 445 → `clip.h` 428, tedy **17** |
  | **Overlay** z výšky nebere nic, a proto se rezervuje legacy | okýnko 445 → `clip.h` 445, tedy **0** |
  | Rezerva odpovídá API pro tu velikost, která se **kreslí** (vyčtenou ze scrolleru, ne napsanou) | `.regular` → 17 |
  | Nezastropované okýnko unese celý svůj dokument, a nemusí kvůli tomu scrollovat | 5 řádků: 95 bodů okýnka, 78 na text, dokument 78, `origin.y` 0 |
  | Zastropované okýnko nechá na text celý počet řádků | 445 → 428 − 8 = 420 = **30 × 14** |

  **Styl se vynucuje na instanci** (`scroll.scrollerStyle`), ne přes `preferredScrollerStyle`: ten je
  systémový stav, který se mění připojením myši, takže by z něj byl test na náladu stroje místo na oba
  případy. Změřeno, že instanční nastavení zabere i tehdy, když je systémový styl druhý. Styl se
  přesto nechává **usadit napřed** (`TestWait.awaitSettledScrollerStyle()`, #343) — jinak se okýnko
  může přerovnat uprostřed měření.

  **Regrese ověřená vložením regrese**, a rozhodovalo u toho, že padne **na těch bodech, ne na
  timeoutu**: s vrácenou rezervou 13 a stropem 441 padnou 4 testy a 13 tvrzení za 3,3 s —
  `abs(legacy − rezerva) → 4.0`, `13.0 == 17.0`, `visible → 74.0 >= 75.5`, `origin.y → 2.0 == 0.0`
  a `abs(lines − lines.rounded()) → 0.2857` (tedy 4 body ze 14). `LogTailHeightTests` u toho projde
  celá, což je zrovna ta hranice mezi oběma sadami.

  **Ta chyba není vidět v renderu celého tabu** (`CheckLogRoomProbe`), a stojí to za zapsání: scrollery
  se v testovacím procesu usadí obvykle na `overlay`, a tam je rezerva čisté odsazení, takže se nikdy
  nic neuřízne. V renderu tabu je proto vidět jen to, že okýnko je o 4 body vyšší. Kdo se chce na ty
  body podívat, má v téhle sadě dump okýnka pod `PRISM_RENDER_DIR` (`logtail-<N>-radku-<styl>.png`) —
  ten kreslí vynucený `legacy`, takže je na něm vidět i ořezaný horní řádek:

  ```bash
  PRISM_RENDER_DIR=/tmp/render xcodebuild … test -only-testing:PRismTests/LogTailScrollerReserveTests
  ```

  Před opravou: `výška 63, na text zbylo 46, origin.y 2` u třířádkového logu. Po ní: `67 / 50 / 0`.

- **Otevření konce logu (#303)** — `LogTailOpeningTests`. Tvrdí dvě věci, které se dají pokazit
  potichu: okýnko se otevře **na konci logu** a **vodorovně na nule**. Testuje se to přes
  `NSHostingView`, a to je celý smysl té sady: na `NSScrollView`u, kterému se rozměr dá **předem**,
  skok fungoval i **před** opravou — rozbité to bylo jedině tou cestou, kterou jde aplikace (SwiftUI
  okýnko postaví, teprve když log dorazí, a výšku mu dá až při rozložení).

  Tvrdí se, že je **vidět poslední řádek**, ne konkrétní `origin.y`: přesnou hodnotu určuje odsazení
  textu a vodorovný scroller, takže by z toho byl test na aritmetiku AppKitu. Čeká se **na jev se
  stropem** (#269), protože okýnko v hierarchii vznikne až po kole smyčky.

  Regrese ověřená vložením regrese: vrácený `DispatchQueue.main.async` z #292 položí dvě tvrzení
  („zůstalo na začátku ocasu“ a „poslední řádek není vidět“). Tvrzení o vodorovné nule s tou regresí
  **projde**, a je to tak správně — hlídá jinou chybu (`x` u konce nejdelšího řádku).

  **Styl scrollerů se musí nechat usadit dřív, než se okýnko postaví** (#343,
  `TestWait.awaitSettledScrollerStyle()` — od #347 ve `Tests/Support/TestWaiting.swift`, protože
  ji potřebuje i sada nad rezervou na scroller a čekání má jedno místo) — bez toho je z téhle sady
  **flake**, a je to změřené:
  `NSScroller.preferredScrollerStyle` je po startu procesu chvíli `overlay` (`1`) a teprve za pár kol
  smyčky se doresolvuje na `legacy` (`0`), který **místo doopravdy zabírá**. Když ta změna přijde až
  *po* dosazení cíle skoku, viewport se zmenší (`clip.h` **441 → 424**, tedy 17 bodů) a `origin.y` už
  nikdo nepřerovná: okýnko zůstane **o jednu řádku** nad koncem (`maxY` 84 006 → 83 989 proti
  poslednímu řádku na 84 002). Když se styl nechá usadit předem, je poloha správná **od nultého kola**
  (`origin.y = 83 582`) — a **beze změny v aplikaci**.

  Proč to takhle: rozhodovalo, kdo tu chybu má. **Je to artefakt harnessu, ne vada aplikace** — v
  aplikaci je styl scrollerů usazený dávno předtím, než se dá otevřít detail checku, takže se
  `jumpToEnd` nikdy nepočítá z výšky, která se mu pod rukama změní. Zadání #343 to popisovalo jako
  vadu aplikace a chtělo **dosadit cíl dvakrát**; zamítnuto po měření: obě kola běží v témže průchodu,
  tedy pořád před doresolvováním stylu, takže na měřeném stavu nemění nic — tři zelené běhy, na
  kterých ten návrh stál, byly shoda daná tím, které suity zrovna běžely v tom startovacím okně.
  Zamítnuto i **čekat na „konec je vidět“** místo na `origin.y > 0`: bez změny v aplikaci to dojede
  na 120s strop a celý běh má **184 issues**, protože pumpování smyčky vyhladoví `MainActor`.

  Jak se to poznalo, ať se to nemusí hledat znovu: pády byly **pokaždé na týchž číslech**, což je
  známka skutečného stavu, ne zátěže — a zátěž se vylučovala měřením proti `main` (6× ze 6 zeleně
  proti 4× ze 7 na větvi #339, kde ten diff jen posunul, které suity běží v tom okně). Příčinu pak dal
  **výpis `clip.h`, `origin.y` a `preferredScrollerStyle` po kolech smyčky**; z pádu samotného se
  vyčíst nedala.

  Regrese po #343 ověřená znovu, a **deterministicky**: cíl spočítaný ze zastaralé výšky viewportu
  (`- 17`) položí tvrzení o posledním řádku na téže signatuře jako původní flake (`83 989` proti
  `84 001`), tedy sada dál chytá to, kvůli čemu #303 vznikl.

  A **když se styl neusadí do stropu, sada to řekne** — `Issue.record` s poslední přečtenou hodnotou,
  ne tiché pokračování (nález Copilota na #344). Bez toho by se návrat toho flaku projevil jako pád
  tvrzení o posledním řádku, tedy přesně tou nevysvětlitelnou podobou, kterou #343 rozmotávalo.
  **Vyzkoušeno spuštěním v tom výjimečném stavu** (strop stažený na 1 ms) — hlásí
  `Nedočkalo se: styl scrollerů se neusadil (…, poslední hodnota 0)` a padne na místě volání, ne
  o třicet řádků níž; jinak by „nic nevypsalo“ bylo k nerozeznání od „funguje“.

- **Sonda místa pro konec logu (#303)** — `CheckLogRoomProbe`, gated `PRISM_MEASURE`. Nic netvrdí;
  odpovídá na otázku „kolik po vyšším okýnku zbude na seznam checků“, a to **měřením v hierarchii**,
  ne odhadem: v rendrovaném tabu najde `NSScrollView` viewportu i okýnko logu (pozná se podle
  `documentView is NSTextView`) a vypíše, kolik bodů zbylo pod ním — a kolik je to řádků seznamu
  (výška řádku se bere **rozdílem dvou sazeb**, ne z konstant ve view).

  Dvě věci, které se u ní zaplatily. **Kandidáti na výšku se nerendrují jeden po druhém**: vše kromě
  okýnka je ve výšce pevné, takže z jednoho renderu vyjde konstanta a zbytek je odčítání. A **log musí
  dorazit až po prvním rozložení**, jako v aplikaci — když se text podá hned při stavbě hierarchie,
  okýnko zůstane na začátku ocasu, a to je vlastnost sondy, ne aplikace.

  **Kandidáti jsou `14N + 25`** (#347, do té doby `14N + 21`) — řádek 14, `2 × inset` 8 a rezerva na
  scroller 17. Je to tentýž výčet řádků, jen posazený na správnou rezervu; každá hodnota vyrostla
  o 4 body. Přeměřeno u toho, co ta změna stojí seznam checků: **řádek seznamu je 28 bodů**, takže na
  skutečném okně 172 → 168 bodů = pořád 6 řádků, kdežto v okně 810 ze 30 zbyde 26, tedy z jednoho
  řádku žádný.

  **Od #347 je u ní render krátkého logu ve dvou podobách** — bez dlouhého řádku a s ním (2 258 znaků).
  Má to důvod: rezerva se z výšky ukusuje jedině tehdy, když vodorovný scroller doopravdy je, a
  `autohidesScrollers` ho u samých krátkých řádků neukáže. Bez té druhé podoby by z renderu vypadlo
  zrovna to, kde rezerva rozhoduje. **Ani jedna z nich ale ty ořezané body neukáže**, protože scrollery
  se v testovacím procesu usadí obvykle na `overlay` — na to je dump ve
  `LogTailScrollerReserveTests`, který si `legacy` vynutí.

  **Jak konec logu doopravdy vypadá, `ImageRenderer` neukáže** — obsah `NSScrollView`u nerasterizuje
  (prázdná plocha v renderu je omezení sondy, ne aplikace, a ověřilo se to i na třířádkovém logu).
  Kreslí se proto přes `bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)`. Právě tak se u #292
  chytilo, že okýnko po skoku na konec dokumentu začínalo **uprostřed slova**, a u #303, že se v okně
  o výšce 700 bodů odscrolluje seznam checků celý.

- **Fakta o PR (#198)** — `Policy` výčtem. Pokazit se dá potichu **nakreslení dlaždice s nulou**
  (řádek plný nul utopí to jedno číslo, na kterém záleží) a **ukázání shodné sha nálezů**, ze které
  neplyne nic. Nejcennější test je právě ten druhý: shodná se nekreslí, rozešlá ano a je označená
  jako zastaralá.
- **Osa konverzace (#183)** — `Policy` výčtem. Dvě věci se dají pokazit potichu: **slít commity,
  které za sebou nejdou** (mezi nimi je komentář, takže do jedné skupiny nepatří) a **zahodit prózu
  review** při zúžení na komentáře. K tomu datum skupiny (bere se z **posledního** commitu — to je
  okamžik, ve kterém větev vypadá tak, jak vypadá teď) a počty, které se počítají z plné osy.
- **Šířka diffu ve znacích (#188)** — `Policy` výčtem. Pokazit se dá potichu jedno: **zapomenout,
  že se vedle sebe dělí šířka na dvě strany**. Číslo by pak tvrdilo, že se slib drží, zrovna
  v režimu, ve kterém se nedrží. K tomu nezměřené okno (nula je pravda o měření, ne o okně)
  a nulová šířka znaku, na které by dělení spadlo.
- **Značky souborů ve stromu (#197)** — `Policy` výčtem. Pokazit se dá potichu jedno: **nechat
  blokující přebít obyčejným nálezem**. Značka by pak záležela na pořadí, ve kterém nálezy
  dorazily, takže se testuje v **obou pořadích**. K tomu nález bez cesty (patří celému PR, ne
  souboru) a přenastavené kategorie.
- **Zkrácená jména reviewerů (#182)** — `Policy` výčtem. To hlavní, co se dá pokazit potichu, je
  **zkrátit dvě různá id na totéž**: dva pluginy se stejně pojmenovaným skillem by v okně vypadaly
  jako jeden reviewer a nález by patřil neznámo komu. Testuje se proto kolize (obě jména zůstanou
  celá), že kolize **nezastaví zkracování ostatních**, jméno bez dvojtečky a id končící dvojtečkou,
  ze kterého by jinak vyšel prázdný popisek.

  Samotné rozvržení panelu se neunit-testuje (je to view) — kontroluje se na běžící aplikaci proti
  vyrenderované sekci 02 návrhu, viz níž.
- **Uložená osa běhu (#203)** — tři věci, které se dají pokazit potichu: **oříznout konec místo
  začátku** (po restartu se do osy kouká proto, aby se vidělo, čím to skončilo), **zapomenout, že
  se ořízlo** (sčítá se to mezi uloženími) a **přebít živou osu tou z disku** — to poslední je
  ověřené **vloženou regresí**: bez té podmínky spadne sedm testů. K tomu kolečko přes `Codable`,
  protože události nesou přiřazené hodnoty a chyba v kódování by se projevila až po restartu.
- **`WindowCentering` (#164)** — **geometrie, ne `NSWindow`**. `centered(_:in:on:)` si obrazovky
  bere parametrem (`ScreenBounds`), takže je to čistá funkce; jinak by zůstalo neotestované zrovna
  zarovnávání zpátky na viditelnou plochu, protože `NSScreen` se vyrobit nedá. Do #164 to byla
  `private` funkce ve `SettingsView` a držel ji **jen komentář**.

  To hlavní je **pořadí ořezu `max(min(…))`**: u okna širšího (nebo vyššího) než obrazovka by
  obrácené pořadí rámec poslalo za levý okraj, kde po něm není ani křížek. Vedle toho každý kraj
  zvlášť, menu bar (ořezává se podle `visible`, ne `frame`), chybějící hostitel (rámec se nechá,
  jak byl), prázdný seznam obrazovek a **výběr obrazovky podle plochy průniku** — včetně toho, že
  na pořadí v seznamu nezáleží a že `NSRect.null` musí mít nulovou plochu, ne nekonečnou.

  Že se okno **nerozpůlí mezi monitory**, vyšlo z testu, který nejdřív čekal opak a spadl:
  hostitel přes hranu dvou monitorů posune okno celé na ten s větším průnikem. Zapsané jako
  chování, ne jako překlep v testu.
- **`AuxiliaryWindowLevel` (#243)** — na rozdíl od středění se tady testuje i **`NSWindow`**,
  protože hladina je jeho vlastnost; okno se v testu jen vyrobí, nikdo ho neukazuje. Nejcennější
  jsou dvě tvrzení o tom, co se stát **nesmí**: že v neaktivní aplikaci hladina padá zpátky na
  `.normal` (jinak by okno plavalo i nad cizími aplikacemi — to je ta naivní oprava) a že se okno
  **neskrývá** (`hidesOnDeactivate` zůstává `false`). To druhé je zapsané chování, ne detail:
  skryté okno se s SwiftUI umí rozejít a zůstat mimo obrazovku, ačkoli je scéna otevřená. K tomu
  ještě, že hladina **oknem nehýbe** — středění (#164) a hladina jsou dvě věci udělané témuž oknu
  a nemají si do sebe mluvit.

  Zbytek téhle změny je chování oken, které unit test nepokryje — pořadí oken, hladina za běhu
  a to, že se zavřené okno nevrací. Ověřuje se **spuštěním**, viz *Jak změřit pořadí a hladinu
  oken* níž.
- **`CacheEviction`** — proti skutečné dočasné složce, ne proti fake filesystému: rozpočet
  je injektovatelný, takže stačí malé soubory. Pozor, počítá se **alokovaná** velikost, tedy
  po blocích — stobajtový soubor zabere 4 KB a testovací rozpočty musí být řádově výš.

  Od #120 v ní leží i **zadání pro reviewera** (`<pr>-<sha>.md` vedle stromu) a jsou na to dva
  testy: že zadání zavřeného PR odejde a zadání otevřeného zůstane, a že s evikovaným repem jde
  taky. Nejsou nadbytečné vůči testům na stromy — soubor se od složky liší tím, že by ho
  `allWorktrees()` mohl přeskočit, a bez těch dvou testů by ho odfiltrování nikdo nechytil.
- **`CacheLayout` a sloty** (#228) — nejcennější test je ten, který tvrdí, že se něco
  **nestalo**: `CacheLayout(named: "PRism")` a `CacheLayout(named: "PRism-a")` se ptají
  `contains` na obě strany a ani jedna nesmí vidět do té druhé. Chytá to i past, do které by
  se spadlo připojením slotu bez oddělovače — `"PRism"` + `""` je pořád `"PRism"`.

  Ověřeno **vložením regrese**: když `init(named:)` jméno ignoruje a vždycky složí `PRism`,
  spadnou dva testy se čtyřmi issues. Bez toho by zelený běh nedokazoval nic, protože obě
  cesty vedou do `Application Support` a liší se jediným řetězcem.

  Zbytek slotů leží v shellu (`bin/run.sh`, `bin/worktree.sh`, `bin/slot-config.sh`) a **od #398
  je jeho část v testech** — viz *Skripty v `bin/`* níž. Co testy nepokryjí, se
  ověřuje spuštěním: build se slotem musí vyrobit `com.ondrajodas.prism.a`
  a `PRism-a`, instance běží **vedle** té hlavní a hlavní cache zůstane bez jediného čerstvého
  souboru. Že se `pgrep` patterny nepletou, se pozná jen s oběma běžícími naráz — pattern hlavní
  instance nesmí najít slot a naopak.

  **Očista konfigurace slotu se ověřuje nad konfigurací, která per-repo override má** (#262).
  Filtr přečtený očima projde — přesně tak v něm deset dnů leželo chybějící `mode` u rep, které
  stálo 2,80 $ a 1,16 $ ve dvou slotech. Pouští se proto `bin/slot-config.sh` nad skutečnou
  konfigurací (`ondrajodas/prism-review-sandbox` v ní `mode: automatic` má) a ve výsledku se
  hledá, co v něm **nesmí být**: žádný automat na žádné úrovni, žádné povolené odesílání.
  Do uživatelovy konfigurace se přitom nezapisuje — je to jen vstup, cílem je cache slotu.

  Ověřovat se musí i to, co skript hlásí **jen výjimečně**, jinak je „nic nevypsal“
  k nerozeznání od „funguje“: prázdný slot (cílem by byla konfigurace hlavní instance) a slot
  se zakázaným znakem musí odmítnout dřív, než složí cestu; chybějící `jq` nesmí zkopírovat
  nic; a **kontrola nad výsledkem se ověřuje vložením regrese** — když se z filtru vyndá
  `mode` u rep, musí skript skončit nenulově a nezapsat nic. Zapsaná očista, která spadne
  na půl cesty, je horší než žádná: vypadá jako hotová.
- **Skripty v `bin/` — úklid slotu a databáze LaunchServices (#398, #399)** — dvě sady
  v `Tests/Scripts/`, a je to **první místo, kde se shell v tomhle repu testuje harnessem**.
  Důvod je v tom, o čem ty skripty rozhodují: co se smaže. Přečtený `case` nedokazuje nic — u #61
  tady ležela kontrola podpisu, která nevypsala nic ani v tom stavu, na který se ptala.

  `SlotCleanupTests` pouští `bin/slot-cleanup.sh` jako proces. Nejcennější tvrzení je **negativní
  a je o hlavní instanci**: prázdný slot (tedy hlavní aplikace, cache a doména, se kterými se
  pracuje) musí být odmítnutý **dřív, než se složí jakákoli cesta** — proto se tvrdí nejen
  návratový kód, ale i to, že skript nevypsal ani hlavičku „Uklízím slot“, a k tomu se bere
  **odražený obraz hlavní instance** (existence a velikost `/Applications/PRism.app`, její cache
  a jejího plistu) před úklidem a po něm. Že se maže **jedině cesta složená ze slotu**, se tvrdí
  nad zdrojákem skriptu (tatáž konstrukce jako `SingleWayOutTests`), protože za běhu se ta cesta
  pustit nedá — pustit se musí přesně to, co se nikdy nemá stát.

  **Záznamy v `~/.claude.json` (#484) mají tvrzení dvě, a to cenné je zase to negativní.** Test
  si v podstrčeném `HOME` vyrobí konfiguraci, ve které leží vedle sebe kořen cache slotu, jeho
  pracovní strom review, **sousední slot, jehož jméno tím naším začíná** (`PRism-<slot>b`), hlavní
  instance a cizí projekt. Po úklidu musí být pryč jen ty první dva a zbytek nedotčený — ubraný
  cizí klíč by byl potichu, protože na ten soubor se nikdo nedívá, dokud se `claude` nezeptá na
  důvěru ke složce, kterou už znal. Klíče se skládají **`ClaudeWorkspaceTrust.key(for:)`**, tedy
  toutéž funkcí, kterou je do souboru zapisuje aplikace: je to rozvinutá cesta (`realpath`)
  a `${TMPDIR}` testovacího hosta leží za symlinkem, takže klíč složený od oka by se s obsahem
  souboru minul. K tomu dva testy o tom, kdy se **nepíše vůbec**: konfigurace bez záznamů slotu
  musí zůstat **bajt po bajtu** stejná (přeskládané klíče by test položily) a nečitelný soubor se
  jen ohlásí — úklid pokračuje a skončí `3`.

  **Ověřeno vložením regrese, dvakrát.** (1) Z porovnání se vyndá lomítko
  (`startswith($root + "/")` → `startswith($root)`) — padne tvrzení, že sousední slot zůstal,
  i strukturní tvrzení nad zdrojákem. (2) Zahodí se kontrola, že je soubor čitelný objekt JSON —
  skript umře na parse erroru `jq` s kódem `5` a **neuklidí ani doménu a databázi**, takže padnou
  čtyři tvrzení najednou. Ta druhá regrese ukazuje víc, než na co se test ptal: pojistka „nesahej
  na soubor, kterému nerozumíš“ drží i zbytek úklidu.

  Doména v `UserDefaults` (#399) se testuje **na vyrobeném slotu s UUID** v názvu: test si domenu
  sám vypíše (`defaults write com.ondrajodas.prism.zztest-…`) a po úklidu ověří **zpětným čtením**,
  že `defaults read` selže a že plist v `~/Library/Preferences/` neexistuje. Obojí je potřeba:
  `defaults delete` po sobě nechá **prázdný plist** (42 B, změřeno), na kterém `defaults read` už
  hlásí, že doména neexistuje — návratový kód by tedy tvrdil hotovo nad souborem, který tam leží.

  `BundleLibraryTests` sourcují `bin/lib/bundles.sh` bashem a volají její funkce. Vyrábí si vlastní
  bundly (`PRism-….app` v `TemporaryDirectory`) a registrují je do **skutečné** databáze
  LaunchServices — jinak není co odregistrovávat. Tři bundly v jednom běhu zastupují tři skutečné
  případy: zaniklé worktree (registrace přežije smazání bundlu), **existující bundle, který se nesmí
  dotknout** (to je hlavní aplikace a soused v jiném slotu), a výsledek buildu, který na disku
  zůstává a předává se jmenovitě. Cesty se přitom musí rozřešit `realpath(3)`, ne
  `resolvingSymlinksInPath()` — ten jde záměrně druhou stranou a `/private` odřezává, takže
  tvrzení o vypsané cestě neplatilo, i když úklid proběhl správně.

  **Obě chybové větve se pouštějí, ne čtou**, a je na to `PRISM_LSREGISTER`: `/nekde/neni` je
  chybějící binárka, `/usr/bin/false` neúspěšný výpis databáze. Vedlejší užitek je, že testy, které
  o LaunchServices nejsou (cache, doména), si databázi nechají projít `/usr/bin/true`, takže stojí
  desetiny sekundy místo pěti.

  Ověřeno **vložením regrese** a u dvou věcí to bylo potřeba dvakrát:
  - bez odmítnutí prázdného slotu spadnou tři tvrzení a skript vypíše „Uklízím slot „““;
  - bez `rm` prázdného plistu spadnou tři tvrzení v testu domény;
  - bez filtru na hlášky `PlistBuddy` **spadne test na hlášku, ne na rozhodnutí** — a přesně tím se
    našlo, že `PlistBuddy` píše chyby jednou na stdout (`Will Create`, `Error Reading File`)
    a jednou na stderr (`Does Not Exist`), takže filtrovat podle textu je slepá cesta a rozhoduje
    návratový kód;
  - u přeskakování existujících cest se regrese **nesmí pustit na skutečnou databázi** — bez toho
    `if`u by úklid odregistroval hlavní `/Applications/PRism.app`. Ověřuje se proto proti
    **záznamníku** místo `lsregister` (`PRISM_LSREGISTER` na skript, který si `-u` jen zapíše
    a na `-dump` vypíše dvě cesty, jednu existující a jednu ne): s `if`em dostane `-u` jednu cestu,
    bez něj obě.
- **`RepoCheckout`** — dvě vrstvy, a **obě jsou potřeba**. Fake runner ověří, co se `gitu`
  posílá za argumenty (na tocích s víc příkazy `ScriptedProcessRunner`, který odpovídá
  jinak na každé volání); integrační test (`RealRepoCheckoutTests`) klonuje z `file://`
  scratch repa a ověří, že jim `git` rozumí a vznikne z toho použitelný klon i worktree.
  Chybějící refspec u fetche prošel unit testy bez povšimnutí a chytil ho až ten druhý.
  Pozor na `contains` nad polem argumentů — porovnává **celé prvky**, ne podřetězce,
  takže refspec (`+refs/pull/85/head:refs/prism/pr/85`) se musí hledat vnořeným `contains`.
- **`ReviewRunner`** — proti `FakeProcessStreamer`, který přehraje fixtures ze skutečných
  běhů: úspěch, čisté review, nenulový exit, nespuštěná binárka, timeout. Fake umí běh
  **pozdržet**, a na tom stojí testy limitu souběhu (4 běhy, naráz nejvýš 3), slučování
  stejného klíče a zrušení. Čekání jde přes `Task.yield()` v smyčce, ne přes `sleep` —
  test, který se nedočká, uvízne, což je srozumitelnější než náhodné padání.
- **`SubprocessStreamer`** — proti **skutečným procesům** (`/bin/sh`), ne proti fake
  runneru. Že řádky přijdou v pořadí, že se doručí i useknutý poslední řádek, že proces
  běží v předané složce a že zaseknutý skončí timeoutem, se dá zjistit jen spuštěním —
  přesně tohle unit testy `RepoCheckoutu` nechytly. Odkladná doba mezi `SIGTERM`,
  `SIGKILL`em a vzdáním se čekání na EOF je proto injektovatelná (`gracePeriod`): jinak by
  test na potomka, který drží rouru po zabitém procesu, trval čtyři sekundy.

  **Zrušení se ověřuje na PID, ne na souboru, který proces po sobě nechá** (#101). Sledovat
  soubor znamená dočkat se konce jeho `sleep` — takže rezerva proti zpoždění pod zátěží se dá
  zvětšit jen tím, že test poběží stejně dlouho, a při 800 ms padal jeden běh ze čtyř, jak
  ostatních suit ubývalo procesů. Na PID (`kill(pid, 0)`, který nic neposílá) se zabití pozná
  **v okamžiku, kdy nastane**: deadline může být pětisekundový a test přesto skončí v desítkách
  milisekund. Testuje to navíc přesnější tvrzení — zmizelý proces, ne neproběhlý `touch`.

  **Flaky test se opravuje mechanismem, ne konstantou.** Zvětšení konstanty se dá jen odhadnout
  a příště se posune zátěž; polling na výsledek s velkorysým deadlinem je odpověď, která se
  nemusí ladit. Ověřuje se to **opakováním**, ne jedním zeleným během: 20 běhů suity v řadě,
  protože u flaky s 25 % je pět zelených běhů ještě čtvrtina případů.
- **`ReviewSlots`** — limit, pořadí ve frontě a zrušený čekatel, který nesmí frontu ucpat.
- **Zavření aplikace** (#264) — tři suity, protože se to láme ve třech různých místech:
  - **`AppDelegateTerminationTests`** — rozhodnutí o ukončení. Že se bez běžícího review neptá
    a nic nezabíjí, že `Zpět` nezabije nic, a hlavně že se **ukončení povolí teprve po zabití**
    (`.terminateLater` a `reply` až po něm). Jde to jedině proto, že dotaz i odpověď systému jsou
    v delegátovi **vlastnosti**: `runModal()` by v testu čekal na kliknutí, které nikdo neudělá,
    a `reply(toApplicationShouldTerminate:)` mimo odložené ukončení by ukončil hosta testů.
    Poslední test suity tvrdí, že odpověď dorazí **i s nezapojeným zabíjením** — nezavíratelná
    aplikace je horší porucha než přežilá session.
  - **`AppStoreTerminationTests`** — co po zavírání zůstane: nic neběží, nic nového se nespustí
    (ruční tlačítko **i** tik automatu) a **značka rozdělaného běhu (#97) se nesmaže**. K tomu
    protějšek, že **zrušení člověkem ji smazat musí** — bez něj by šlo „nemazat při zavírání“
    splnit tím, že se nemaže nikdy, a příští start by vzkřísil nálezy, které si někdo zrušil.
    Store je proto v **automatickém** režimu i tam, kde se spouští ručně: s `autoRuns: nil` by
    plánovač vypadl na první závoře a test o něm netvrdil nic.
  - **`AppStoreTerminationProcessTests`** — celý produkční řetěz proti **skutečnému procesu**
    (`AppStore` → `ClaudeReviewRunner` → `SubprocessStreamer` → `Process`), kde za `claude` stojí
    skript, který vypíše svoje PID a čeká. `exec sleep`, ne `sleep`: PID pak patří tomu procesu,
    který má umřít, a nezůstane pod ním potomek, který by výsledek rozmazal.

    **Pořadí tvrzení je tu podstatná část testu.** `runningReviews == 0` musí být **první a bez
    jediného `await`u** — v provozu po téhle metodě následuje zavření aplikace, takže víc času
    než „nic“ běh nedostane. Když se to napsalo obráceně (napřed polling na PID), test prošel
    i nad verzí, která na zabití nečeká: polling sám tomu běhu dal čas, který v provozu nemá.
    Teprve po tom tvrzení se kouká na proces, a tam se čekat smí — mezi doručeným `SIGKILL`em
    a zmizením z tabulky je ještě sklizení, které s aplikací nesouvisí.

  Ověřeno **vložením regrese**, ve čtyřech podobách: bez čekání po `cancel()` (spadnou čtyři
  testy včetně toho nad skutečným procesem), bez brány na mazání značek (spadne ta o značce),
  bez brány v `startReview` a bez brány ve `startAutomaticReviews` (spadne ta o novém běhu)
  a s `terminateNow` místo odloženého ukončení (spadne celá delegátí suita).

  Co testy nepokryjí, je **osamocený proces po zmizelé aplikaci** — na to se nedá napsat test,
  který by nezabíjel vlastního hosta, takže se to ověřuje spuštěním: pustit review, ukončit
  aplikaci a podívat se, jestli po ní zbyl `claude` s `ppid 1`. Změřeno u #264 na slotu — session
  zmizela, značka v `interrupted.json` zůstala a po restartu vyšel řádek `přerušeno`.
- **Úklid osiřelé session po zabité aplikaci** (#351) — tři suity, protože se to láme na třech
  různých místech, a **cennější polovina všech tvrzení je negativní**: že se signál nikam
  neposlal. Ta se rozbije potichu, protože zabít cizí `claude` je horší než nechat běžet sirotka
  a na stroji jich běží víc (uživatelovy vlastní session, paralelní agenti ve slotech).
  - **`OrphanedSessionsTests`** — čistá funkce `Policy.orphanVerdict` **vyčerpávajícím výčtem**:
    vlastník a proces mohou být každý ve třech stavech (běží tentýž, běží pod tím PID někdo jiný,
    neběží nikdo), tedy devět kombinací. Osm z nich nesmí vydat `kill`.
  - **`RunningSessionsTests`** — registr proti **skutečné** dočasné složce (o to jde: značka má
    cenu jedině tím, že přežije proces, který ji zapsal) a proti **fake tabulce procesů**, protože
    recyklované PID se skutečnými procesy vyrobit nedá. Čte se **soubor**, ne getter na objektu.

    **Fake eviduje pokusy zvlášť od úspěchů, a je to podmínka.** `SystemProcessInspector` si
    identitu ověřuje ještě sám, takže fake, který by ji ověřoval a mlčel, by kryl rozhodnutí,
    které cizí proces zabít **chtělo** — negativní test by prošel i nad `Policy`, která identitu
    neporovnává. Změřeno vloženou regresí: přesně tak to proběhlo, dokud fake evidoval jen
    úspěchy. Negativní testy proto tvrdí `killRequests.isEmpty`, ne `killedProcesses.isEmpty`.
  - **`SystemProcessInspectorTests`** — proti **skutečné tabulce procesů**: že `sysctl` vrací
    identitu jen na živý proces, že nekladné PID identitu nemá (`sysctl` na `pid == 0` odpovídá
    a `kill(0, …)` by mířil na procesovou skupinu aplikace), že `SIGKILL` **neodejde** na živý
    proces se změněným `startedAt`, a celý řetěz: sirotek zapsaný s mrtvým vlastníkem se doopravdy
    zabije, session živého vlastníka doopravdy zůstane běžet. Zabíjí se jedině to, co si suita sama
    spustila — PID se nikde nehádá ani nehledá v `ps`.

  Zapojení hlídá **`SubprocessStreamerTests`**: streamovaný proces se do registru zapíše a koncem
  z něj zmizí. Bez toho testu by registr zůstal zelený a v cache by nebylo nic — a úklid při startu
  by nad prázdným souborem hlásil, že sirotci nejsou.

  **Že úklid naprázdno na soubor nesáhne, se testuje přes formát, ne přes obsah.** Zápis by uložil
  týž seznam, takže porovnání „stejný obsah“ by ho nechytlo — soubor se proto před úklidem
  přeformátuje na **kompaktní** JSON a test tvrdí, že kompaktní zůstal. Druhý test na to samé
  z jiné strany: nad prázdnou cache nesmí soubor vůbec vzniknout.

  Ověřeno **vložením regrese**, ve čtyřech podobách: bez porovnání identity procesu (spadne test
  o recyklovaném PID v `Policy` **i** ten o cizím procesu v registru — a proti skutečnému systému
  ten o změněném `startedAt`), bez kontroly vlastníka (spadnou tři testy včetně toho, ve kterém
  by se zabil skutečný běžící proces), bez zápisu značky v `LaunchedProcess` (spadne test
  zapojení) a bez podmínky na zápis v `reapOrphans` (spadnou oba testy o nedotčeném souboru).

  Co testy nepokryjí, je **prevence, protože žádná není** — změřeno na harnessu, který spouští
  potomka přes `Foundation.Process` stejně jako `LaunchedProcess`: po `kill -TERM` i `kill -KILL`
  na rodiče má potomek `ppid 1`. Podrobnosti i výpis `ps` jsou v
  [`architektura.md`](architektura.md), sekce *Osiřelá session po zabité aplikaci*.

## Čekání na jev (#296)

Sem patří všechno, co v testu znamená „počkej, až se něco stane“. Je to **jedno místo**
(`Tests/Support/TestWaiting.swift`) a jsou k tomu tři primitiva:

| Co | Kdy | Strop |
|---|---|---|
| `waitUntil("jev") { podmínka }` | čeká se na jev, který nastat **má** | `TestWait.deadline` = 2 min |
| `settle()` | není na co čekat — tvrdí se, že se **nic nestalo**, nebo se čeká na zápis bez handle | bez stropu, 100 ms |
| `TestWait.pause()` | smyčka, která práci **drží** rozběhnutou, dokud ji test nepustí | bez stropu (držení stropovat nejde) |
| `TestWait.awaitSettledScrollerStyle()` | usadit **prostředí** před stavbou AppKitové hierarchie (#343, sem svedeno #347) | `TestWait.deadline` |

**Čeká se odmlkami, ne `Task.yield()`.** Yield práci nepustí na procesor — přeřadí ji na konec
fronty téhož aktoru —, takže hot spin na `MainActoru` vyhladoví hlavní smyčku a s ní časovače.
Změřeno u #296 na sondě odpočtu v plném běhu: vyžádaná odmlka **100 ms** se probudila za **7,5 až
8,6 s**, přitom vlastní práce sondy (bitmapa) stála 1 ms. Nebyla to pomalá aplikace, byl to
vyhladovělý `MainActor` — a hladověl kvůli ostatním suitám, protože Swift Testing je pouští
paralelně. Do #296 mělo `Tests/` **56 takových míst**; tentýž problém našlo šest míst zvlášť
(`AsyncGate` #292, `ReviewSubmissionTests`, `HealthMonitorTests`, `AppStoreHealthTests`,
`AppStoreNotificationTests`, sonda odpočtu #269) a každé si psalo vlastní odmlku, takže se oprava
dělala pokaždé znovu a každý další test začal zase od `yield()`.

**Strop je čas, ne počet kol** (#292), a **je odvozený od zátěže, ne od volného stroje** (#296).
Rozpočet kol se pod zátěží vyčerpá dřív, než se čekaná práce dostane na procesor. Rozpočet odmlek
(`for _ in 0..<250` se spánkem) je proti tomu odolný, ale z kódu se nedá přečíst, jaký strop platí.

**Z čeho jsou ta dvě minuty:** patnáctijádrový stroj, tři souběžné clean buildy (load average
24–36, přeobsazení ~4×). Čekání, která se **dočkala**, trvala až **42,3 s**; se stropem 30 s padly
tři plné běhy ze tří. Cena za velkorysost se platí **jen když je něco rozbité** — co se dočká,
dočká se hned. Kdo ho bude chtít snížit jako „přebujelý“, ať si napřed pustí plný běh při souběžném
buildu tří slotů.

**Nedočkání se hlásí, nezasekává.** `waitUntil` zapíše `Issue` s větou „Nedočkalo se: …“, takže je
z hlášky poznat, **co** se nestalo. Do #296 tady byly dva horší tvary: neomezený `while` (test
visel, což je pod zátěží k nerozeznání od zaseknutého běhu) a odtikaný rozpočet, po kterém se šlo
dál a spadlo se o pár řádků níž na tvrzení, ze kterého nebylo poznat, že se jen nedočkalo.

**Kde jev existuje, nepatří tam `settle()`.** Drain naslepo platí za to, kolik zbylo procesoru:
u #296 na něm padl test draftu na disku, protože se zápis do 100 ms nestihl. Zápis draftu si store
rozjede `Task`em bez handle (`AppStore.persistDraft`), takže jediný jev je **soubor** — na to je
`waitForStoredDraft(of:in:exists:)`. `settle()` zůstává jen tam, kde se tvrdí, že se nic nestalo:
tam jev neexistuje, a je to zapsaná slabina, ne nedodělek — pod zátěží ověřuje méně, ale **červeně
obarvit nemůže**.

**Časové tvrzení se nahrazuje jevem, kde to jde.** `RealEnvironmentTests` tvrdily „zrušené volání se
vrátí do 5 s“; pod zátěží vycházelo 5,95 / 8,23 / 11,03 s a po zvětšení stropu na 15 s pak 17,7 až
26,7 s. Naměřený čas volání je pod zátěží nečitelný a zvětšování stropu je hra, ve které zátěž
pokaždé přesáhne poslední odhad. Teď se ptá na **zmizelý PID** (`processHasGone`), což je i silnější
tvrzení: naměřený čas říká jen „vrátilo se to brzo“, takže by prošla i implementace, která na proces
zapomene a nechá ho běžet.

**Pořadí tvrzení je u toho podstatná část testu**, a stálo to jedno kolo. `#expect(processHasGone)`
musí být **před** `await running.value`: to čekání skončí i tím, že procesu doběhne `sleep`, takže
„zmizel“ pak platí samo. Změřeno vloženou regresí — s vyndaným `requestKill()` test v opačném pořadí
**prošel** za 300 s. Je to tatáž past, která je u `AppStoreTerminationProcessTests` popsaná výš.

**Rezerva mezi timeoutem a životem procesu je taky strop proti zátěži.** `SubprocessStreamerTests`
tvrdí, že proud ukončil **timeout**, a to je vidět jedině tehdy, když proces nedoběhne dřív — do
#296 tam bylo `sleep 30` proti timeoutu 200 ms (stonásobek) a **nestačilo to**: časovač se probudil
až po skončení `sleepu`, proud dojel normálně a suita hlásila „chyba se čekala, ale žádná nepřišla“
nad kódem, který funguje. Teď je to `longerThanTheTest` = 600 s, tedy 2000×, a k tomu
`.timeLimit(.minutes(3))`, aby rozbitý timeout **spadl** a nezasekl běh. Ten strop musí být **nad**
`TestWait.deadline`; když se rovnaly, vypršely naráz a v hlášce stály dva různé důvody pádu.

**Produkční timeouty se do testů nepředávají jako výchozí.** `LoginShellPathReader` má default 5 s
a je to rozhodnutí o startu aplikace („zaseknutý shell nesmí položit start“) — jenže pod zátěží ho
skutečný login shell přetáhl a test o parsování `PATH` spadl na prázdném výsledku. Test si proto
předává vlastní velkorysý timeout: ptá se, jestli se `PATH` přečte a rozebere, ne jestli se to
stihne za produkční rozpočet. Totéž u `/bin/echo`, které se při třech souběžných buildech nestihlo
spustit a posbírat do 10 s.

**Pumpování smyčky je výjimka v mechanismu, ne ve stropu.** `LogTailOpeningTests` čeká na rozložení
okýnka tím, že doopravdy pustí `RunLoop` — `waitUntil` by tam nepomohl, protože okýnko se rozloží
jedině tak, že smyčka poběží. Strop si ale bere z `TestWait.deadline`: do #296 tam bylo 40 kol po
50 ms („o dva řády víc, než co se čeká“), a dva řády nestačí, když je změřené zpoždění stonásobné.

**A někdy se nečeká na vlastní jev, ale na to, aby se usadilo prostředí** (#343). Kdo staví AppKitovou
hierarchii, musí počítat s tím, že **proces po startu ještě není usazený**: `NSScroller.preferredScrollerStyle`
se doresolvuje z `overlay` na `legacy` až za pár kol smyčky, a legacy scroller mění výšku viewportu.
Test, který si hierarchii postaví dřív, měří jiné rozměry než test, který běží o dvě sekundy později —
a vyjde z toho flake, který se **pozná od zátěže tím, že padá pokaždé na týchž číslech**. Léčba je
nechat tu vlastnost usadit **před** stavbou hierarchie (`TestWait.awaitSettledScrollerStyle()`), ne
stropovat čekání na výsledek; podrobnosti u sady výš.

**Od #347 je i tahle smyčka v `TestWait`**, ne privátní metodou v jedné suitě — potřebuje ji druhá
sada (`LogTailScrollerReserveTests`) a druhá kopie by byla druhý strop, který se s tímhle rozejde.
Cena je `import AppKit` v souboru o čekání, a je to vědomá daň za to pravidlo: jedno místo je
přednější než čistota importů. Je to zároveň jediné čekání, které nečeká na **vlastní jev**, ale na
usazené **prostředí** — proto je v `TestWait` jmenované zvlášť, ne schované do `waitUntil`.

**Ověřeno vložením regrese, čtyřmi:** vyndaný `requestKill()` v `SubprocessRunneru` (spadne
`RealEnvironmentTests` — „proces po zrušení pořád běží“), vyndaný `requestKill()` v
`SubprocessStreameru` (spadne `cancellationKillsTheProcess`), zamrzlý odpočet bez `TimelineView`
(spadne sonda odpočtu, viz níž) a rozvrh `by: 2` (spadnou dva testy `DashboardCountdownTests`
za 0,001 s).

### Co tím opravené není

**`AppStoreProgressTests` bylo flaky i bez zátěže**, a byla to **jiná třída** — pořadí, ne čas,
takže na to strop neměl vliv a #296 to neopravovalo. Měřeno samostatně (`-only-testing`), osm běhů:
jeden pád, za **0,038 s**, na `forgetsTheTimelineOfAPullRequestThatLeftTheList`. Kolega u #295 to
samé viděl na čistém `mainu` (tři různé kombinace pádů ve třech bězích), takže to nebylo z převodu
na `waitUntil`. **Vyřešeno u #308** — a řešení bylo v `AppStore`, ne ve stropu, viz níž.

Mechanismus z hlášky (osa dropnutého PR obsahovala `[queued, findings(0), finished]` — tedy **bez**
`.started`, který fake hlásí jako první, a s razítky ze dvou různých hodin, `queued` v roce 1970
z `FakeTimeSource` a zbytek ve skutečném čase) vypadal na **pozdní událost**, která zahozenou osu
postavila znovu. Změřením se to ukázalo jinak a **stojí za to si to pamatovat**, protože ten omyl
byl pochopitelný:

- **Nic nedorazí pozdě.** Proud událostí se dojíždí uvnitř `review()` (`reporter.finish()`
  + `await drained`), takže po konci běhu už žádná událost nepřijde — a dokud běh žije, `forget`
  jeho osu z úklidu vyjímá.
- **„Vzkříšení“ byl fallback na disk.** `timelines(for:)` po úklidu odpoví z uloženého záznamu,
  který se schválně neuklízí. Osa tedy nebyla nová, ale **uložená** — a chybějící `.started`
  s druhými hodinami byl její obsah: uložila se zkrácená a `completeTail` jí dopočítala konec
  z `finishedAt`, tedy ze skutečných hodin vedle fake razítek.
- **Padal ten závod v ukládání.** Snímek osy pro zápis se bral mimo proud, takže si čtení
  s plněním závodilo o `MainActor`. Deterministicky se to pozná **zátěží**: samotný test
  (`-only-testing:…/forgetsTheTimelineOfAPullRequestThatLeftTheList()`) padl **3× ze 3** a se
  souběžnou druhou suitou prošel 4× ze 4 — proto to nad plným během vypadalo náhodně.

Poučení pro příště: **z hlášky se pozná obsah, ne cesta, kterou tam přišel.** Že v ose chybí
`.started`, říká, že se osa někde zkrátila, ne kdo ji zapsal; kdo, se pozná až tím, že se vytiskne,
co je v `reviewRecords` **před** úklidem a co po něm.

**Reportované trvání testu není doba čekání** (#360). U #358 padl `Průběh PR, které zmizelo ze
seznamu` a v hlášení stálo `20,4 s z 22 s` celého běhu, což vypadalo na vyčerpaný strop čekání
(`TestWait.deadline`). Není: Swift Testing pouští suity paralelně a u testu hlásí **uplynulý čas**,
takže test, který se odbaví za 20 ms na začátku a dokončí se na konci běhu, hlásí celou délku běhu.
Změřeno na plném běhu: **793 z 3383** hlášených položek hlásilo 20+ s v běhu, který trval **24 s** —
a tentýž test hlášený jako 23,6 s se sám o sobě odbyde za **0,02 s**. Strop se z toho tedy vyčíst
nedá; když ho test doopravdy vyčerpá, je v logu věta `Nedočkalo se: …`.

**Testovací host umře při startu** (`Early unexpected exit, operation never finished bootstrapping —
test runner exited with code 0 while preparing to run tests`). Zaznamenáno u #298 při třech
souběžných slotech; **v #296 se to nereprodukovalo** ani při třech clean buildech, takže o tom není
co tvrdit kromě toho, jak se to pozná: **žádná chyba kompilace, žádné `✘`, nespustil se ani jeden
test**, a druhý běh nad tímtéž commitem projde. Je to zátěž, ne rozbitý build — pustit znovu.
Odstranění spinů (#296 vyndalo 56 míst, která na `yield()` točila procesor) tomu podle všeho pomáhá,
ale **změřené to není**; kdyby se to vrátilo, tohle je záznam, u kterého se dá začít.

## Zaseknutý plný běh: okno, které se objeví s animací (#462)

Plný `xcodebuild test` se na tomhle stroji zasekával na **třech posledních suitách** — `komentář pod
PR`, `odpovídání do vláken` a `labely a reviewery` —, tedy přesně na těch, které spouštějí
podstrčený `gh` jako **podproces**. V hostu se u toho nasbíralo **76 vláken
v `-[NSAnimation _runBlocking]`** a dispatch pool narazil na svůj strop. Obcházelo se to během po
polovinách (`-only-testing` / `-skip-testing`).

**Od `Early unexpected exit` výš se to pozná na první pohled a jsou to jiné věci:**

| | zaseknutý běh (#462) | `Early unexpected exit` (#298) |
|---|---|---|
| kolik testů proběhlo | **tisíce**, výpis se zastaví uprostřed | **ani jeden** |
| co je v logu | poslední `✔` a pak ticho, žádné `Test run with …` | `operation never finished bootstrapping` |
| co dělá hostitel | **žije**, `ps -o %cpu` ~0 % (čeká) | už neběží |
| co s tím | vzorkovat, viz níž | **pustit znovu**, je to zátěž |

Když se běh zasekne, hostitel ještě žije — tak se z něj dá vytáhnout, na čem. Po zabití už ne:

```bash
PID=$(pgrep -f 'build.noindex/.*PRism.app/Contents/MacOS/PRism' | head -1)
ps -M -p "$PID" | wc -l                    # kolik má vláken; nad ~75 je pool na stropě
sample "$PID" 3 -file /tmp/host.txt
grep -c '_runBlocking' /tmp/host.txt       # kolik jich sedí v animaci
```

**Pozor na `pgrep` ve víc slotech**: ten vzor sedne i na hostitele souběžného stromu, takže se do
něj patří dopsat kus vlastní cesty. Jinak se změří cizí běh a vyjde z toho nesmysl.

### Kdo ta vlákna drží

Rozhoduje **ukázání okna**, ne SwiftUI a ne to, co je v okně. Samostatná sonda mimo repo (12 oken
naráz a pak `sample` sám na sebe, `/usr/bin/sample <vlastní pid> 1`):

| co sonda udělá | vláken procesu | z toho v `_runBlocking` |
|---|---|---|
| 12× `NSHostingView`, okno se **neukáže** | 5 | 0 |
| 12× `orderFront(nil)`, výchozí `animationBehavior` | 25 | **14** |
| 12× totéž na **borderless** okně **bez obsahu** | 25 | **14** |
| 12× `orderFront(nil)` s `animationBehavior = .none` | **5** | **0** |
| 12× `setFrame(_:display:animate: true)` | 8 | 1 |
| 12× `beginSheet(_:completionHandler:)` | 7 | 1 |

`NSAnimation` v threaded režimu je **`dispatch_async` na globální root frontu**, ze které si na celou
dobu animace drží vlákno a odpovídá z něj display linku. V `sample`u je to tahle řada:

```
Thread_… DispatchQueue_19: com.apple.root.user-interactive-qos  (concurrent)
  _dispatch_worker_thread2 → _dispatch_root_queue_drain → _dispatch_call_block_and_release
    -[NSAnimation _runBlocking] → -[NSRunLoop runMode:beforeDate:] → __CFRunLoopRun
      __CFMachPortPerform → CA::Display::DisplayLink::dispatch_items
        -[_NSDisplayLinkForwarder displayLinkDidFire:] → -[NSAnimation _advanceTimeWithDisplayLink:]
```

`setFrame(display:animate:)` a `beginSheet` do téže třídy patří, ale **blokují volajícího**, takže
z nich je vždycky jedna animace naráz. Nebezpečné je jen to, co se pouští po desítkách — a
`Tests/Views/` ukazovalo okno na **48 místech**, přičemž Swift Testing pouští suity paralelně.

### Kdo to zaplatí

Pool má na tomhle stroji strop **75 pracovních vláken** a `SubprocessRunner` z něj bere vlákna na
**blokující čtení pip** (`readToEnd()` na obou koncích, `SubprocessRunner.ioQueue`). Když je
obsazený, čtení `gh` se vůbec nedostane na procesor. Změřeno druhou sondou — obsadit pool blokující
prací a pak změřit, za jak dlouho se práce na téže privátní souběžné frontě **vůbec spustí**:

| obsazených vláken | vláken procesu | latence `ioQueue` |
|---|---|---|
| 0 | 1 | **0,0001 s** |
| 80 | **76** | **28,0 s** |

Těch 76 je **strop poolu, ne počet zadané práce** — tedy přesně to číslo z hlášení. A 28 s je doba,
po kterou si sonda vlákna držela; `gh` má v aplikaci timeout **30 s**, takže z toho v panelu vyjde
`PublishError.timedOut`. **Je to jedna příčina a dva projevy**, ne dvě různé věci: `timedOut` u těch
tří suit pod zátěží a zaseknutý plný běh mají tentýž kořen.

### Co se s tím udělalo a jak se to hlídá

Ukázat okno jde v `Tests/` **jedině přes `orderFrontUnanimated()`** (a
`orderFrontRegardlessUnanimated()`) z `Tests/Support/UnanimatedWindow.swift`, který napřed nastaví
`animationBehavior = .none`. Hlídá to `UnanimatedWindowTests` — stráž nad **zdrojáky**, ne nad
během, z téhož důvodu jako u #367: počet vláken procesu je vlastnost **celého paralelního běhu**,
takže tvrzení o něm padá podle toho, kdo běžel vedle. Grep z `CLAUDE.md` dělá totéž z příkazové
řádky.

Dvě věci na té stráži nejsou zjevné. Hledá se **bez tečky vpředu** (`orderFront(`, ne
`.orderFront(`), protože v podtřídě `NSWindow` jde totéž volání napsat bez příjemce — a jména
helperů tím netrpí, `orderFrontUnanimated(` na `orderFront(` nesedne. A **odečítají se dva
soubory**, ne jeden: helper i stráž. Že v obou ten vzor doopravdy **sedí**, je druhé tvrzení té
suity — bez něj by stráž zezelenala i tehdy, kdyby hledala řetězec, který v kódu není.

**Aplikace se nemění.** Animace objevení okna je v `App/` v pořádku — otevírá se jich pár, ne
padesát — a `grep -rn 'orderFront' App` je prázdný, takže na obrazovce není co vidět.

Naměřeno na plném běhu, střídavě **A/B/A/B/A/B** (špička vláken hostitele z `ps -M` po 2 s;
`_runBlocking` z opakovaných jednosekundových `sample`ů). Rozhodující je **poslední dvojice** — jen
u ní běžely oba měřiče po celou dobu, a `sample` si sám bere procesor, takže špičky vláken jsou v ní
vyšší než v prvních dvou:

| běh | špička vláken hostitele | max `_runBlocking` |
|---|---|---|
| A1 bez opravy | **88** | neměřeno (jednorázový vzorek: 8) |
| B1 s opravou | **42** | neměřeno |
| A2 bez opravy | **71** | 7 (měřeno jen v závěru běhu) |
| B2 s opravou | 57 | **0** |
| **A3 bez opravy** | **76** | **8** |
| **B3 s opravou** | **54** | **2** |

Ty dva zbylé v `B3` **nejsou z testů**, a je to změřené, ne odhad: `-only-testing` na `UnanimatedWindowTests`
(dva testy, žádné okno, 0,9 s) dá v hostiteli `_runBlocking = 1`. Je to okno **samotné aplikace**,
která je hostitelem testů, při jejím startu — a to je jedno okno, tedy přesně ta velikost, která
nikomu nevadí.

### Co tím prokázané není

**Samotné zaseknutí se u opravy nereprodukovalo.** Plný běh doběhl **ve všech** měřeních výš — i bez
opravy —, takže „po opravě už se to nezasekne“ je závěr z **mechanismu a z čísel**, ne z pozorovaného
rozdílu mezi zaseknutým a nezaseknutým během. Co je změřené: zdroj těch vláken (tabulka výš), cena
obsazeného poolu pro `gh` (28 s proti 0,0001 s) a to, že po opravě nezbylo v celém běhu z testů
**ani jedno** takové vlákno. Kdyby se zaseknutí vrátilo, je tohle první věc, kterou má smysl ve
vzorku hledat — a pak už to nebude tohle.

**`SubprocessRunner` zůstává na sdíleném poolu**, a je to zapsaná slabina, ne nedopatření. Blokující
čtení pipy si bere vlákno z globální fronty, takže kdokoli jiný, kdo pool obsadí, umí `gh` a `git`
zdržet až na timeout. V aplikaci to nehrozí ze stejného důvodu, proč se nemění `App/` (oken je pár
a paralelismus review drží `WorkCoordinator`), takže se produkční cesta kvůli tomuhle issue
nepřepisovala. Kdyby se to mělo řešit, cesta je **nedržet vlákno vůbec**: bufferovat výstup
z `readabilityHandler`u, jako to dělá `SubprocessStreamer`, místo `readToEnd()`.

## Globální stav procesu se v testech neměří (#367)

Do #367 měly `AppStoreAppearanceTests` tvrzení „store bez cíle na `NSApp` nesáhne“ postavené tak, že
si vzaly `NSApp.appearance` **před** a **po** a porovnaly je. V paralelním běhu z toho byl **falešně
červený `main`**: při práci na #331 to spadlo, ve třech čistých bězích po sobě bylo zeleno — tedy
přesně ten druh pádu, po kterém se přestane věřit celé sadě.

**Měřilo se na hodnotě, která nám nepatří, a to má dva pisatele.** Ten druhý je překvapivější a je
**změřený**: v běhu, ve kterém žádná jiná suita na vzhled nesahá, je `NSApp.appearance` po startu
`nil` a asi **300 ms** poté `NSAppearanceNameAqua` — sonda ho vypsala dvacetkrát po 100 ms a od
čtvrtého vzorku už drží vynucený režim. Je to **hostitel testů**, tedy naše aplikace: živý `AppStore`
uplatní volbu z konfigurace uživatele. Ta hodnota tedy záleží na tom, jak má člověk u stroje
nastavený vzhled, a mění se **uprostřed** našeho běhu.

Pravidlo, které z toho zbylo: **test netvrdí nic o globálním stavu procesu a nezapisuje do něj.**
Kdo potřebuje vynucený režim, nastaví ho na **svém** okně nebo view (`AppearanceSwitchProbe`), nebo
si obalí kreslení `performAsCurrentDrawingAppearance` (`DiffPaletteTests`, `SidebarRailTests`,
`MintTokenTests`) — obojí platí jen tam, kde se zrovna měří, a **z kódu je vidět, jaký režim se
měří**, ne jaký zdědil stroj (tatáž past jako u #393).

Hlídá to **`GlobalAppearanceTests`** třemi tvrzeními nad zdrojáky — je to tatáž konstrukce jako
`SingleWayOutTests` a `GraphSiteWiringTests`, protože „kdo smí sáhnout na globální vzhled“ je
vlastnost struktury kódu, na kterou se za běhu zeptat nedá:

| Tvrzení | Co drží |
|---|---|
| `App/Store/` nezná `NSApp` a importuje **jen** `Foundation` a `Observation` | Store **nemá čím** na globál sáhnout: nevidí AppKit, takže se v něm `NSApp` nedá ani napsat. Rozhoduje o vzhledu (dostal konfiguraci), ale kreslení není jeho práce. **Výčet povolených, ne zákaz AppKitu** — nález z review na #400: zákaz `import AppKit` obchází `import Cocoa`, a stejně tak kterýkoli další modul, který AppKit tahá s sebou |
| `AppAppearance.application` je v `App/` jmenováno **jednou**, vzhled se uplatňuje jedině `appearance?.applyAppearance(` a `?? AppAppearance` nikde není | Živý cíl se zapojuje jen při složení živého storu. Kdyby ho vzal za výchozí hodnotu init, kterým store staví testy, přebarvil by jeden test hostitele — a render sondy by měřily jiný režim, než o který si řekly |
| Žádný soubor v `Tests/` nepíše `NSApp.appearance` ani `NSApplication.shared.appearance` | Aby se ta třída nevrátila. Sám guard soubor se z výčtu odečítá, protože hledané řetězce v něm stojí jako literály. **Hlídá dvě zápisy toho jména, ne obchvat přes proměnnou** (`let app = NSApplication.shared`) — na to je pravidlo v `CLAUDE.md`; whitelist importů jako u `App/Store/` tady nejde, testy AppKit legitimně potřebují |

**Ověřeno vložením regrese, a to ze tří stran.** (1) Kolizní suita, která 4000× přepne
`NSApp.appearance` s odmlkou: nad původním kódem padne `Bez cíle se na NSApp nesáhne`
(`Expectation failed: (NSApp.appearance → …) === (untouched → …)`), po opravě projde celá sada
(8 testů ve 2 suitách, 82 s souběžného přepínání). (2) Výchozí hodnota `appearance:
AppAppearance.application` v init, kterým store staví testy: padne tvrzení o jednom jmenování
(`2 == 1`) — a nic jiného, což je zrovna ten důvod, proč to tvrzení existuje. (3) `import AppKit`
plus `NSApp.appearance = …` přímo v `AppStore.apply(_:)`: padne pět tvrzení ve všech třech testech.
A po nálezu z review ještě (4) `import Cocoa` v `App/Store/AppStore.swift`: padne výčet povolených importů,
kdežto původní zákaz `import AppKit` by tuhle cestu propustil.

**Zamítnuté cesty.** `.serialized` na sadu — serializuje jen tu jednu suitu, kdežto zápis dělá
hostitel, takže by to na příčinu nedosáhlo vůbec. Zámek nad globálem v testech — tentýž problém,
hostitel žádný zámek nedrží, a k tomu je to sdílený stav navíc. Test smazat — je to tvrzení
o tom, že se něco **nestalo**, tedy nejcennější druh testu v tomhle repu; přesunulo se, ne zahodilo.

### `UserDefaults` je tentýž případ, a měl tři projevy (#411)

Doména `UserDefaults` procesu patří do téže třídy jako `NSApp.appearance` — je to jedna hodnota na
celý testovací host a **testu nepatří**. Do #411 to bylo o řád horší než u vzhledu, protože ta
hodnota **přežije běh**: testovací host měl bundle ID hlavní instance (slotová přípona vznikala
teprve v `bin/run.sh`), takže `xcodebuild test` běžel jako `com.ondrajodas.prism` a všechno, co
v testu prošlo `@AppStorage` nebo `UserDefaults.standard`, zapisovalo **do nastavení, které se
doopravdy používá**.

Naměřené projevy byly tři a každý vypadal jako jiná vada:

| Projev | Jak se to poznalo |
|---|---|
| **Z testů do provozu.** Uložená hodnota z testu je ta, se kterou se aplikaci příště otevře okno | U #327 zůstala v `com.ondrajodas.prism` velikost sheetu z regresního experimentu; při opravě #411 tam vedle toho ležely **návštěvy u vymyšlených PR** (`cli/cli#1` s časem z roku 1970) a `releaseNotes.lastSeenTag`, tedy „poslední viděné vydání“ nastavené testem |
| **Z provozu do testů.** Sada tvrdí něco o souboru, do kterého píše **běžící aplikace** | `SlotCleanupTests` brala otisk `com.ondrajodas.prism.plist` před úklidem a po něm: 6 296 → 6 343, 6 563 → 6 566, 7 263 → 7 266 B, a velikost se pak **vrací**. Izolovaně 9/9 za 0,1 s, v plném běhu (40–67 s) **dvakrát falešně červený `main`**. Rozhodovala délka běhu, ne obsah změny |
| **Napříč procesy.** Vlastní suita s **pevným** jménem je globál stejně jako doména procesu | `cz.prism.tests.codeSheetSizing` a `cz.prism.tests.rawSessionSheetSizing` si při souběžném běhu tří slotů přepisovaly klíče: `store.object(forKey: "rawSessionSheetWidth") → 1180` tam, kde se tvrdí `nil`. Izolovaně obě sady procházely |

**Řeší to výchozí `PRISM_SLOT` v `project.pbxproj`, ne vrstva v kódu.** Identitu aplikace stanoví
`bin/run.sh` (předává `PRISM_SLOT` na příkazové řádce vždycky, i prázdný), takže výchozí hodnota
platí právě pro build, který si o identitu neřekl — a od #411 je to `.testhost`. Testovací host
tedy běží jako `com.ondrajodas.prism.testhost` a do nastavení uživatele odsud nevede cesta ani
omylem. Detaily jsou v README, sekce *Paralelní vývoj — sloty*.

**Proč zrovna takhle** — tři měření, která to rozhodla:

- **`PRODUCT_BUNDLE_IDENTIFIER` testovacího targetu je slepá cesta**, i když se to nabízí jako
  první. Bundle testů je **hostovaný**, takže `Bundle.main` je aplikace: `UserDefaults.standard`
  se řídí jejím identifikátorem a na tom, jak se jmenuje `.xctest`, nezáleží.
- **Podmíněné nastavení podle akce nejde** — `xcodebuild -showBuildSettings` hlásí `ACTION = build`
  u `build` i u `test`, takže se ta dvě od sebe v projektu odlišit nedají.
- **Vlastní konfigurace pro testovací akci schématu by fungovala, ale je moc drahá**: druhý strom
  produktů (`Build/Products/Test/`) znamená dvojí build v každém stromě, druhý hostitelský bundle
  v databázi LaunchServices (třída #139) a `Debug` zadrátovaný v `bin/*.sh`. Za to, co obstará
  jedna hodnota v projektu, se to nevyplatí.

**Vrstva v kódu (`UserDefaults.prism` s detekcí testů) je zamítnutá** ze dvou důvodů. Znamenala by
podmínku „běžím v testu?“ v produkčním kódu, jejíž **chyba se platí uživatelovým nastavením** (falešně
kladná detekce v nainstalované aplikaci = tichá ztráta všeho, co si proklikal). A neuzavřela by tu
třídu: leak z ledgerů (`pullRequests.lastVisits`) nejde z testovacího kódu, ale z **výchozích
argumentů** v aplikaci, takže by ho stráž nad `Tests/` nechytila a `@AppStorage` bez `store:` by
zůstalo mimo. Výchozí `PRISM_SLOT` naopak platí na všechno naráz, včetně toho, co se napíše příště.

**Vlastní doména se tím ale nestává zbytečnou.** Doména hosta je jedna pro souběžné běhy tří slotů,
takže kdo potřebuje `UserDefaults`, bere si **`ScratchDefaults`** (`Tests/Support/`): jméno
`cz.prism.tests.<k čemu>.<UUID>`, tedy unikátní na běh, a úklid po sobě. `@AppStorage` se do ní
nasadí přes `defaultAppStorage(_:)` na to view, které se měří.

**Úklid té domény má tři kroky a druhý z nich není zjevný.** `removePersistentDomain(forName:)`
nechá prázdný plist (42 B) — to je pas z #399 — ale hlavně: po smazání **zevnitř procesu** se ten
prázdný soubor **vrátí, jakmile proces skončí**. V prvním plném běhu po #411 takhle zůstalo **pět**
souborů, přesně těch, do kterých se zapisovalo, a `#expect` uvnitř testu přitom prošel: za živa
soubor po `rm` není ani po dvou sekundách, doflushuje ho `cfprefsd` až při zániku procesu. Sonda
(scratchpad, sedm variant) našla dvě, po kterých se nevrátí — pustit instanci suity z ruky **dřív**,
než se doména maže, a smazat doménu **z jiného procesu**. `ScratchDefaults` dělá to druhé
(`/usr/bin/defaults delete`), protože v `deinit` se odkaz na vlastní pole pustit nedá. Po druhém
plném běhu zbylo **nula** souborů.

**Co se hlídá čím.** Runtime tvrzení je jedno a je to to nejcennější: `Bundle.main.bundleIdentifier`
**není** `com.ondrajodas.prism` (`ProcessPreferencesTests`) — kdyby někdo `PRISM_SLOT` z projektu
smazal, spadne to hned, kdežto ušpiněné nastavení se pozná až za týden. Zbytek je nad zdrojáky,
tatáž konstrukce jako `GlobalAppearanceTests`:

| Tvrzení | Co drží |
|---|---|
| Žádný soubor v `Tests/` nepíše `UserDefaults.standard` | Doména hosta je pořád jedna pro tři souběžné běhy |
| Žádný soubor v `Tests/` nepojmenuje suitu literálem (`UserDefaults(suiteName: "…"`) | Třetí projev z tabulky výš; jméno skládá `ScratchDefaults` z `UUID` |
| Žádný soubor v `Tests/` nejmenuje `"com.ondrajodas.prism"` ani `/Applications/PRism.app` | Druhý projev: do obojího píše někdo jiný — do plistu běžící aplikace, do bundlu každé `bin/run.sh` po mergi. **Jméno plistu se nehlídá**, protože `com.ondrajodas.prism.plist` je zrovna to jméno, které si musí dát **vyrobená** hlavní instance |
| `bin/run.sh` má `SLOT_ARGS` a předává je | Druhá polovina té izolace. Bez toho by si hlavní instance vzala `.testhost`, tedy prázdné nastavení, propadlá TCC povolení a druhý PRism v LaunchServices |

**Hlavní instance se v `SlotCleanupTests` vyrábí, ne čte** — je to ta oprava druhého projevu.
Skript si cache i plist skládá z `${HOME}`, takže dostane **podstrčený `HOME`** a v něm cache
`PRism` a plist `com.ondrajodas.prism.plist`, které vyrobil test; porovnává se **obsah**, ne
velikost, což je silnější než původní otisk. Dvě věci u toho nejsou zjevné:

- **`defaults` `HOME` ignoruje** (změřeno: zápis pod podstrčeným domovem skončil v tom skutečném,
  cestu skládá `cfprefsd`, ne klient). Doména se proto testuje dál ve skutečném `HOME`, na slotu
  s `UUID` — a je to **jediný** test v té sadě, který tam běží.
- **Bez pozitivní kontroly by ta tvrzení byla prázdná**: nedotčené soubory znamenají i „skript se
  na ně nepodíval“. Kontrolou je `Cache slotu se smaže`, která v tomtéž podstrčeném domově maže
  cache slotu vedle vyrobené hlavní instance.

**Ověřeno vložením regrese, a to z pěti stran.** (1) Test, který si uloží do `UserDefaults.standard`
→ padne stráž nad zdrojáky. (2) Suita pojmenovaná literálem → padne. (3) `"com.ondrajodas.prism"`
a `/Applications/PRism.app` v testu → padnou dvě tvrzení. (4) `PRISM_SLOT` v projektu vrácený na
`""` → padne `Testovací host neběží v doméně aplikace` (`"com.ondrajodas.prism" != "com.ondrajodas.prism"`),
a nic jiného. (5) `rm -f "${HOME}/Library/Application Support/PRism/findings.json"` v
`bin/slot-cleanup.sh` → padnou **oba** testy s vyrobenou hlavní instancí i strukturní tvrzení
o mazání mimo slot. Vybraná cesta té regrese je schválně taková, která ve skutečném `HOME`
neexistuje — vložená regrese nesmí umět smazat data, kvůli kterým se testuje.

**Co se z toho testem hlídat nedá.** Že po plném běhu nezůstane na stroji žádná doména
`cz.prism.tests.*`, se ověřuje **rukou** (`ls ~/Library/Preferences | grep cz.prism`), ne testem:
souběžné běhy tří slotů mají svoje soubory rozdělané, takže by tvrzení „nic tu není“ bylo červené
podle toho, kdo běží vedle — a to je zrovna ta třída, kterou #411 opravuje. Platí u toho i to, že
zabitý běh (⌃C) úklid nespustí a jeden soubor po sobě nechat může.

### Metrika písma je tentýž kořen v jiné podobě (#407)

Metrika písma **není** globální stav procesu jako `NSApp.appearance` — nikdo do ní nezapisuje. Vada
je ale ze stejné rodiny a v plném běhu se projevovala stejně: **falešně červený `main`**, dvakrát
z deseti, na cizích sadách (`CommitPanelRoomTests`, `LogTailHeightTests`), a **zeleně, když se sada
pustila samostatně**. Rozdíl je v tom, kdo tu hodnotu mění: tam hostitel, tady **systém**.

**Co ta nula je — změřeno, ne odhadnuto.** Je to **objekt písma bez použitelné metriky**, ne
zastaralé číslo. Zachytilo se to při #407 na plném běhu v testovacím hostu:
`NSFont.monospacedSystemFont(ofSize:weight:)` vrátil instanci, u které `maximumAdvancement.width`
nedal použitelnou hodnotu — a **sazba tímtéž objektem spadla uvnitř CoreTextu**:

```
NSInvalidArgumentException: -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]:
    attempt to insert nil object from objects[0]
  3 -[NSDictionary initWithDictionary:copyItems:]
  5 TAttributes::ApplyFont(__CFDictionary const*, __CTFont const*, …)
  9 CTLineCreateWithAttributedString
 14 -[NSAttributedString(NSStringDrawing) size]
 15 PRism.FontMetric.Route.derived(_:of:)
```

Zachytila to **první podoba opravy**, která měla jako náhradní měření *vysázet `0`* — takže se
sazba pustila právě na tom písmu, u kterého hlavní čtení selhalo, a **položila celý běh** (proběhlo
169 testů ze 3 979, zbytek xcodebuild vypsal jako failing). Nebýt toho pádu, zbyla by z toho jen
tichá záskočná hodnota a příčina by se pořád jen odhadovala.

**A ta vada je přechodná — to je druhé měření a je konkrétnější než všechno předchozí.** V osmém
z deseti plných běhů pod zátěží spadlo `CommitPanelRoomTests` na `šířka znaku: 0` a `tally` u té
zprávy řekl proč:

```
šířka znaku: 8.0361328125, měření 2, náhradní cesta 0×, nepovedlo se 1×, zamítnuto 0.0
```

Čte se to takhle: **první měření vrátilo nulu na všech třech cestách** (`nepovedlo se 1×`,
`zamítnuto 0.0` — tedy nula, ne `NaN`; a nulu dala i cesta, která staví písmo znovu z deskriptoru),
nezapamatovalo se — a **totéž písmo o zlomek sekundy později**, při skládání té chybové zprávy, dalo
správných **8,0361328125** (`měření 2`). V tom okamžiku tedy nepomůže *žádná* jiná cesta; pomůže
jedině **zkusit to znovu později**. Odsud pochází poslední kus opravy: řetěz cest se opakuje až
čtyřikrát s **milisekundovou** odmlkou (bez ní je to tentýž stav přečtený čtyřikrát, celý řetěz je
pár mikrosekund), tedy nejvýš 3 ms jednou za písmo a proces, a jedině když měření selhává.

**Poučení o měřidle, které stojí za zapsání:** tuhle věc odhalilo to, že se v chybové zprávě
`#expect`u hodnota **čte znovu**. Zpráva se skládá až po pádu, takže vedle sebe stálo „co tvrzení
vidělo“ (0) a „co je vidět teď“ (8,036) — a z toho je rozdíl mezi *chybějící* a *přechodně
nedostupnou* hodnotou vidět na jeden pohled. Kdyby v té zprávě byla jen naměřená hodnota bez
`tally`, zbylo by z toho `šířka znaku: 0` a hledalo by se dál.

**Kde ta vada není** (obojí změřeno, obojí vylučuje „metrika se rozešla mezi dvěma čteními“):

| Sonda | Kolik čtení metriky | Anomálií |
|---|---|---|
| Samostatný proces, 16 vláken, teplé písmo | 96 000 | 0 |
| Samostatný proces, závod na **prvním** rozřešení — 500 čerstvých procesů po 24–32 vláknech | 57 600 | 0 |
| Samostatný proces, 8 čtenářů proti 8 churnerům ve font cache (tisíce velikostí), load 22 | 3 041 433 | 0 |
| **Testovací host**, plný běh, 6 vláken, 6 cest, 45 s (`FontMetricProbe`) | 3 242 670 | 0 |

Čtení teplého písma to tedy není a hammerováním se to chytit nedá — je to **rozřešení konkrétního
objektu**, a těch je za běh hrstka.

**Oprava je jedno měřidlo, ne třetí léčba.** Do #407 ležely tři: jedno čtení za test (#367), totéž
u `DesignPillTests` (#348), jedno čtení na proces s náhradním měřením (#327) — a čtvrtá sada by si to
musela pamatovat taky. Od #407 to je `FontMetric` (`App/Views/FontMetric.swift`): jedno měření na
proces, tři cesty (`measured` → `fresh` → `derived`), **opakování s odmlkou** a **nula se
nepamatuje**. Podrobnosti o cestách a naměřených mezích jsou v hlavičce toho souboru; sem patří to,
co z toho platí pro testy:

- **žádná sada si metriku nečte sama** — hlídá to `FontMetricTests` dvěma tvrzeními nad zdrojáky.
  První je **plošné**: `maximumAdvancement`, `defaultLineHeight` a `boundingRectForFont` smí v `App/`
  i v `Tests/` znát jedině `FontMetric.swift`, tahle sada (porovnává cesty mezi sebou) a
  `FontMetricProbe` (vypisuje je vedle sebe). Druhé tvrdí, že jmenované sady si metriku **berou
  z měřidla** — bez něj by šlo pravidlo splnit i tím, že se tvrzení o rozměru zahodí. Převedeno je
  **deset** míst: pět v `App/` a pět v `Tests/` (`CommitPanelRoomTests`, `LogTailHeightTests`,
  `DesignPillTests`, `LogTailScrollerReserveTests`, `CheckLogRoomProbe`, k nim `PillTypesettingTests`
  a `CodeTextSheetSizingTests` — ta druhá porovnávala `static let` konstantu se **svým** surovým
  čtením, tedy dvě čtení v jednom procesu, což je ta vada přesně);
- **`FontMetricTests` měří na vlastní instanci, ne na `shared`** — sdílené měřidlo plní i suity, které
  běží vedle, takže by se počty měření nedaly tvrdit, a vyprázdnit ho uprostřed plného běhu by
  znamenalo poslat ostatní sady měřit znovu;
- **vadné písmo se dá vyrobit maticí** a jedině tak: `scaleByX: 0` dá `maximumAdvancement` 0,0
  (a čerstvé písmo z téhož deskriptoru 0,618, tedy záskok funguje), `scaleByX: .infinity` dá `NaN`
  na všech třech cestách a **ve všech pokusech**, takže se na něm dá tvrdit i to, že se řetěz
  doopravdy opakuje (a že to stojí odmlku). Proto `Policy.usableFontMetric(_:)` hlídá `isFinite`, ne
  jen kladnost — `NaN` je hodnota, kterou skutečné `NSFont` vydá, a `Int(NaN)` shodí proces;
- **ve zprávě u tvrzení, která na metrice stojí, je `FontMetric.shared.tally`** — počet měření,
  kolikrát zaskočila náhradní cesta a **jaká hodnota se zamítla**. U #327 se z pádu nedalo poznat,
  jestli metrika vrátila nulu, nebo `NaN`; příště to bude v té zprávě;
- **sonda nesmí `NaN` minout, a to je vlastní past** (nález Copilota na #439). `FontMetricProbe`
  měla histogram klíčovaný `Double` a anomálii jako `value <= 0` — jenže `NaN` se nerovná sám sobě,
  takže by v takovém klíči zakládal **novou položku při každém čtení** (sonda jich udělá tři miliony),
  a `NaN <= 0` je **nepravda**, takže by sonda tiše minula zrovna ten druh vady, na kterou je.
  Přihrádka je proto **vypsaná hodnota** (`nan` je jedna položka) a o anomálii rozhoduje
  `Policy.usableFontMetric(_:)`, tedy tatáž funkce jako v aplikaci. Nástroj, který měří jiné pravidlo
  než to, které se drží, měří něco jiného, než o čem si myslíme.

**Ověřeno vložením regrese** (obě zvlášť, nad kopií):

1. **zapamatování pryč** (měřit v `FontMetric.value(_:of:)` pokaždé) → `Metrika se měří jednou`
   hlásí `měření 32 000` místo 1;
2. **vlastní čtení zpátky do sady** (`NSLayoutManager().defaultLineHeight` v `LogTailHeightTests`) →
   padne `Sady, které na tom padaly, metriku nečtou samy`, a to jmenovitě na tom souboru.

**Zátěž se vyrábí čtyřmi paralelními optimalizovanými kompilacemi** (load 10–22). Bundle se u nich
nebuildí schválně: build aplikace ji na konci registruje v LaunchServices, takže by z každé zátěže
zbyl záznam o cestě ve `/private/tmp` (#139).

A k tomu **dvakrát deset plných běhů** — jeden zelený běh o téhle třídě nedokazuje nic, protože se
projeví jednou z deseti. Výsledek je poučnější než „všechno zelené“:

| Série | Zelené | Červené |
|---|---|---|
| před opakováním | 7 | **`CommitPanelRoomTests` na `šířka znaku: 0`** (to měření výš), a k tomu `SlotCleanupTests` a `CodeTextSheetSizingTests` |
| s opakováním (výsledný kód) | 8 | `SlotCleanupTests` a `AppStoreCommentTests` |

**Na metrice písma tedy ve druhé sérii nespadlo nic** — a co v ní spadlo, je jiná třída a cizí sada:
`SlotCleanupTests` fingerprintují plist **běžící hlavní instance** (#411; naměřeno `7803` proti
`7806` bajtům, tedy hodnota, kterou nám nikdo neslíbil — tatáž třída jako `NSApp.appearance` výš)
a `AppStoreCommentTests` skončily na `PublishError.timedOut` po 65 s, tedy na stropu čekání pod
load 19. Všech sedm dotčených sad **projde izolovaně za 9,4 s**, což je ten způsob, jak se to od
skutečného nálezu pozná.


## Jak si zkontrolovat, jak view vypadá

**Screenshot běžící aplikace dostaneš** — od #181, kdy terminálu přibylo oprávnění Screen
Recording. Do té doby `screencapture` padal na `could not create image from display` a celá tahle
sekce se od toho odvíjela; **je to změna proti tomu, co tu stálo do #181**, ne nová možnost navíc.

```bash
osascript -e 'tell application "System Events" to tell process "PRism" to get {position, size} of window 1'
screencapture -x -R0,34,1512,874 /cesta/do/scratchpadu/okno.png
```

**Vlastní okno se dá vyfotit i zezadu, podle jeho ID** (#237), a v paralelním běhu je to ta
správná cesta: `screencapture -x -o -l<id>` vyfotí jedno okno, i když je za ostatními, takže
nemusí nic skákat dopředu a **do snímku se nedostane nic cizího** — ani okno druhého slotu, ani
to, co má člověk zrovna na obrazovce. Celoobrazovkový snímek u čtyř běžících instancí naopak
vyfotí hlavně cizí práci.

ID najde `CGWindowListCopyWindowInfo` podle PID (`pgrep -f /Applications/PRism-<slot>.app`);
pár řádků ve `swift` skriptu, `System Events` na to potřeba nejsou. Okno **nemusí být vpředu**,
takže se u toho nepřepíná fokus. Odpočet v hlavičce se takhle dal odečíst ze dvou snímků po
šesti sekundách (u #237 `za 9 s znovu` → `za 3 s znovu`, ještě se systémovým formátem) a burst po
0,35 s zachytil celý přechod přes nulu — tedy věc, na kterou offscreen render nestačí: dashboard je
ve `ScrollView`, který se offscreen **nevykreslí vůbec** (viz níž), takže render vyšel prázdný
a jediné, co zbývalo, bylo skutečné okno.

**Řada snímků se vyplatí složit do jednoho PNG** (#260): výřez pravého horního koutu z osmi snímků
po 1,1 s pod sebou dá filmstrip, ze kterého se celý přechod přečte naráz —
`za 4s` → `za 2s` → `za 1s` → `ptám se…` → `za 29s` → `za 28s` (interval snížený na 30 s, což si
slot dovolit smí). Výřez a skládání je pár řádků CoreGraphics (`CGImage.cropping`, `CGContext.draw`)
a stojí to jeden obrázek místo osmi.

**Na stav za kliknutím se dostaneš taky** — jen se musí aplikace napřed vytáhnout dopředu.
Okno terminálu leží na pixel přesně přes okno aplikace (obojí `0,33,1512,875`), takže klik
`System Events` skončí v tom, co je zrovna nahoře; sám o sobě to není překážka, ale je potřeba
pořadí ohlídat, jinak klik přistane v cizí aplikaci (jednou takhle skončil v Mailu):

```bash
osascript -e 'tell application "PRism" to activate' -e 'delay 1'
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
# … klik a screencapture …
osascript -e 'tell application "okena" to activate'     # POVINNÉ: vrátit okno zpátky
```

**Přepnout zpátky do terminálu je součást úklidu, ne zdvořilost.** Aplikace vytažená přes celou
obrazovku zakryje okno, ve kterém člověk zrovna čte, co se děje — a on ji musí odklikávat ručně.
`entire contents` na SwiftUI okně vrací prázdno, takže cesta přes `AXPress` místo myši nevede.

Oprávnění se uděluje **aplikaci, ze které session běží**, ne `claude` ani `screencapture`. Která
to je, řekne `ps` po rodičích — a **mění se to**: nejdřív to byla `Okena.app`, po přechodu na
`ClaudeCode.app` (`~/.local/share/claude/ClaudeCode.app`) spadlo `screencapture`
(`could not create image from display`) i `osascript` (`nemá povolen asistenční přístup`) naráz.

Když se to stane, není to rozbitý příkaz, ale **jiná identita volajícího**:

```bash
ps -o comm= -p $PPID                      # kdo mě spustil
ps -o ppid= -p $PPID | xargs ps -o comm= -p
```

Ta aplikace potřebuje **Nahrávání obrazovky** (screenshot) a **Zpřístupnění** (`osascript`,
System Events — měření okna a klikání).

**Návrh se ověřuje vedle sebe, ne po paměti** (#181). Mockup je HTML, takže se dá vyrenderovat
headless Chromem a položit vedle screenshotu aplikace — pak se pozná i to, co se z popisu vyčíst
nedá (poměr sloupců, výška karty, kde končí proužek).

**Mockup je [`docs/navrh.html`](navrh.html)** — od #332 soubor v repu; `docs/navrh.md` říká, jak
se aktualizuje a co se do něj musí zapracovat a nechat odsouhlasit dřív, než na to vznikne issue.

**Sekce se vyřízne do samostatného souboru** (i s `<style>`), protože `--screenshot` bere viewport
**od horní hrany dokumentu**: po odrolování na sekci vrací prázdný obrázek, i když je sekce
v okně. Změřeno u #332 — sonda ve stejném běhu hlásila sekci 18 bodů pod horní hranou a snímek
přesto vyšel jednobarevný. Stránkování dokumentu na tom nic nemění.

```bash
python3 - <<'PY'
import io, re
doc = io.open('docs/navrh.html', encoding='utf-8').read()
style = re.search(r'<style>.*?</style>', doc, re.S).group(0)
sec = re.search(r'<section class="section" id="s01">.*?</section>', doc, re.S).group(0)
io.open('/tmp/mockup-s01.html', 'w', encoding='utf-8').write(
    '<!doctype html><html data-theme="dark"><head><meta charset=utf8>'
    + style + '</head><body><div class="wrap">' + sec + '</div></body></html>')
PY
```

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
    --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,900 \
    --screenshot=mockup.png "file:///tmp/mockup-s01.html"
```

U #181 to našlo čtyři odchylky, kterých si předtím nikdo nevšiml: pevná šířka pravého sloupce
místo poměru `1.45fr 1fr`, chybějící popisky v hlavičkách bloků, chybějící blok `Co teď`
a proužek řádku odsazený od hrany.

**Rozvržení okna se dá změřit i přes accessibility** (#180), a je to pořád nejrychlejší způsob,
jak dokázat jedno konkrétní číslo: `System Events` vrátí `position` a `size` každého prvku.
U #180 to rozhodlo spor o hlavičku okna: semafor končil na `y=66`, záložky začínaly na `y=77`,
tedy nad nimi byl prázdný pruh. Po opravě začínala hlavička na `y=42` (horní hrana okna) a její
obsah na `y=50`, tedy **na stejné výšce jako semafor**.

```bash
osascript -e 'tell application "System Events" to tell process "PRism" to get position of window 1'
```

Vyžaduje to oprávnění Accessibility. `entire contents` u `AXScrollArea` občas selže na převodu
typu — hierarchii je pak potřeba projít po patrech (`UI elements of …`).

**Offscreen render celého detailu PR umí zhasnout stav, který mu sonda nastavila** (#150), a je to
past, která vypadá jako chyba v aplikaci. `PullRequestDetailView` má na sobě `.task(id: pullRequest)`,
který si dotahuje detail PR — `ImageRenderer` ho **spustí a hned zruší**, a `loadDetail` na zrušení
maže rozdělaný stav (`detailStates[id] = nil`). V renderu pak chybí všechno, co na hlavě PR visí:
`StaleHeadView` i tlačítko `Zkontrolovat nálezy`. Nespustí se to, když `hasCurrentDetail` vyjde
pravdivě — takže shrnutí PR musí být v sondě **`let`, ne computed property**: `Date(timeIntervalSinceNow:)`
uvnitř getteru dá jiné `updatedAt` při každém přístupu a cache detailu se tím rozejde. Poznat se to dá
jedině `print`em **z těla view** (`let _ = print(…)`), ne z hodnot ve store před renderem: ty jsou
v pořádku. Vedle toho zůstává platné, že AppKitem hostované části (avatar v hlavičce) vyjdou jako žlutý
placeholder — render se z nich nemá co dozvědět.

### Jak změřit pořadí a hladinu oken (#243)

Chování oken — co je před čím, co je vidět a co se vrací — se nedá otestovat unit testem a nedá
se přečíst z kódu. Měří se dvěma nástroji naráz, protože každý umí něco jiného:

```bash
# pořadí oken jedné instance zpředu dozadu (accessibility)
osascript -e 'tell application "System Events" to return name of windows of ¬
    (first application process whose bundle identifier is "com.ondrajodas.prism.d")'
```

```swift
// hladina okna a skutečné z-order z window serveru — `layer 0` je normální okno,
// `layer 3` plovoucí; CGWindowList vrací okna zpředu dozadu
CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
```

Hladina je to, co dokazuje „nedá se zaklopit“ **bez klikání**: okno na `layer 3` nemá čím zakrýt
žádné okno aplikace na `layer 0`, to je pravidlo window serveru. A protože se z `CGWindowList` čte
hladina i pořadí, pozná se z ní obojí naráz — že okno je vpředu, a taky že po odchodu aplikace do
pozadí **spadlo zpátky na `layer 0`**, tedy nad cizí aplikací nestojí. Pořadí z accessibility k tomu
řekne, které okno je uvnitř aplikace před kterým.

Čtyři pasti, každá stála kolo hledání:

- **Procesy se nesmí adresovat jménem.** Při paralelním vývoji běží víc PRismů a všechny mají
  `application process "PRism"` — takže `tell process "PRism"` sáhne do cizí instance. Cíl se
  adresuje `bundle identifier` nebo `unix id`.
- **Reference na prvek se nesmí vracet z `tell` bloku.** System Events do specifieru zapíše
  `application process "PRism"` **podle jména**, takže uložená reference se při dalším použití
  přeloží na cizí proces a spadne na „okno nelze načíst“ — u okna, které přitom je na obrazovce.
  Prvek se proto adresuje celou cestou v jednom výrazu
  (`text field 1 of group 1 of scroll area 2 of group 1 of window 1 of (first application process
  whose unix id is …)`). Vnořené `whose` (proces i okno) System Events neumí vůbec.
- **Hlavní okno se dopředu dostane bez klikání na souřadnice** — `Soubor → Nové okno scény`.
  Nové okno hlavní scény je normální okno aplikace otevřené vpředu, takže je to tatáž situace
  jako kliknutí do hlavního okna, a bez rizika, že klik na souřadnice skončí v okně jiné
  instance. `AXRaise` ani `AXMain`, položka v menu `Okno` a `⌘\`` **nestačí**: měřeno na verzi
  před #243, kde se pořadí neměnilo ani jedním z nich, takže by z nich vyšlo, že porucha
  neexistuje.

- **Zavírat se má křížkem přes accessibility** (`click button 1 of window 1 …`), ne klávesou.
  `⌘W` zavře okno, které má **fokus**, a to po předchozím kroku nemusí být to, co si měření myslí;
  `Esc` v textovém poli spolkne pole (ruší editaci), takže se nezavře nic. Obojí vypadá jako
  porucha okna, přitom je to porucha měření — jméno okna se proto **ověří** dřív, než se křížek
  zmáčkne, aby se omylem nezavřelo hlavní okno.

**Jestli okno „vypadá aktivně“, se pozná jedině screenshotem** (#243). Klíčové okno se od
neklíčového liší třemi věcmi a všechny tři kreslí systém, ne aplikace: barevný semafor, jasný
titulek a modré vybrání v seznamu. `screencapture` se musí pustit **z toho samého skriptu**, který
aplikaci vytáhl dopředu (`do shell script` uvnitř `osascript`) — jinak se mezitím dostane vpředu
terminál a vyfotí se on. Rám okna dá accessibility (`position`, `size` okna).

```applescript
tell application id bid to activate
delay 2
do shell script "screencapture -x -R" & x & "," & y & "," & w & ",34 /tmp/titulek.png"
```

Takhle se u #243 doložilo, že `.utilityWindow` v `styleMask` obyčejného okna nedělá nic a že
i skutečnému utility panelu titulek zešedne — tedy že „aspoň ať to nevypadá deaktivovaně“ nejde.
**Chování AppKitu se přitom nemusí zkoušet v aplikaci**: dvě okna a dva screenshoty se dají udělat
v samostatném programu na třicet řádků (`swiftc /tmp/…swift`), který si sám sáhne na `makeKey()`
a vyfotí se. Je to rychlejší než rebuild a odpověď je stejně platná.

A dvě věci o měření samotném: čekat se musí **velkoryse** (aktivace aplikace trvá i přes sekundu
a s krátkou pauzou vyjde „okno tam není“ tam, kde se jen ještě neukázalo), a měřit se má
**z čistého stavu** — okno nechané otevřené z předchozího běhu skriptu, nebo přebylé okno hlavní
scény, posune celou posloupnost o krok a výsledek pak nejde přečíst. Právě takhle vzniklo
podezření na poruchu aplikace, kde byla ve skutečnosti rozsypaná posloupnost kláves; rozhodlo až
opakování z čistého stavu.

### Jak změřit fokus a klávesy (#184)

**„Kde je fokus“ se z kódu nepřečte a offscreen renderem se nezměří** — je to stav skutečného okna.
Měří se dvěma věcmi naráz a obojí jde ze `swift` skriptu na třicet řádků, bez `System Events`:

- **kde fokus je** — `AXFocused` v accessibility stromu (`AXUIElementCopyAttributeValue`). U pole se
  vedle toho čte `AXValue`, takže je vidět i **co v něm je**;
- **klávesy** — `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `post(tap: .cghidEventTap)`.
  Adresuje se aktivní aplikací (`NSRunningApplication.activate()`), takže se nikam neklikne na
  souřadnice — což v paralelním běhu není detail, viz [`paralelni-vyvoj.md`](paralelni-vyvoj.md).

Tři věci, které z toho u #184 vyšly a bez měření by se neodhadly:

- **Fokus nastavený ve stejném průchodu, ve kterém pole vzniká, SwiftUI zahodí.** `onAppear`,
  `task` bez yieldu i `defaultFocus` daly `AXFocused = false` **navždycky**, ne později. Rozhoduje
  **počet průchodů, ne čas**: bez `Task.yield()` nepomůže žádná pauza.
- **Latence se měří dvojicí ⌘K + znaky s proměnnou pauzou mezi nimi**, ne pollováním fokusu:
  polling po zavřené paletě vrací fokus z předchozího stavu a vyjde z toho „0 ms“. Vyzkoušené
  hodnoty pauzy dají hranici — u palety fokus sedne ~40 ms po ⌘K (od 50 ms je v poli celý text,
  pod 30 ms znak vykreslení předběhne, což ale znamená psát rychleji, než se dá pustit ⌘K).
- **`esc` a `↑↓` nad textovým polem se musí vyzkoušet, ne odvodit.** Pole si `esc` umí vzít pro sebe
  (`cancelOperation`) — tady si ho vzalo tlačítko se zkratkou, protože key equivalent se vyhodnocuje
  dřív. Sled `⌘K → znaky → ↓ ↓ ↑ → esc → ⌘K` se dá projít v jednom skriptu a po každém stisku
  vypsat stav (paleta otevřená?, obsah pole, fokus, vybraný řádek). `AXSelected` se ale musí hledat
  **jen v tom podstromu, o který jde** — v okně ho nese i záložka detailu PR, takže bez zúžení
  vypadá vybraný řádek jako `Průběh`.

**A totéž znovu u nabídek panelu (#392), včetně toho, co se změřit nedá.** Hledací pole nabídky
labelů i reviewerů má mít fokus hned po otevření. Změřeno **samostatnou sondou** — jeden
`swiftc`em přeložený soubor s oknem, tlačítkem a popoverem, který si popover otevře sám (stavem
i **skutečným klikem** poslaným do okna), po dotažení nabídky do něj pošle znaky a šipky a vypíše
`firstResponder` s obsahem pole. Čtyři varianty, série A/B/A/B (drift sezení je větší než hledaný
rozdíl, #274):

| varianta | `firstResponder` popoveru | co se napsalo |
|---|---|---|
| bez fokusu | `_NSPopoverWindow` | nic |
| `defaultFocus($isFocused, true)` | `_NSPopoverWindow` | nic |
| `onAppear` | `_SystemTextFieldFieldEditor` | `xy` |
| `task` + `Task.yield()` | `_SystemTextFieldFieldEditor` | `xy` |

Tři věci, které z toho plynou:

- **`defaultFocus` nefunguje ani v popoveru**, tedy stejně jako u palety (#184). Vypadá jako
  určená cesta a není.
- **Samostatná sonda `onAppear` nechá projít, aplikace ne.** V ní tedy rozdíl mezi `onAppear`
  a yieldem **nevidět není** — a přesně proto se řídíme měřením z aplikace (#184: `onAppear`
  i `task` bez yieldu daly `AXFocused = false` **navždycky**), ne touhle sondou. Použije se yield:
  kde `onAppear` stačí, projde i yield (změřeno výš), kdežde nestačí, je yield ta jediná
  změřená oprava. Sonda mimo aplikaci je tedy dobrá na *vyloučení* varianty, ne na její potvrzení.
- **Fokus nabídku nepřežije**: po zavření popoveru jde znak do okna a v poli se neobjeví
  (`queryPredPsanim == queryPoPsani`), protože `@FocusState` sedí v tom view, které s popoverem
  zaniká.

**V harnessu se to změřit nedá a je to změřené, ne odhad.** Sonda uvnitř testů (`NSHostingView`
v okně, čekání na `firstResponder`, poslané znaky) skončila na tom, že **testovací host nedostane
aktivaci**: `NSApp.isActive == false`, `window.isKeyWindow == false` i po
`setActivationPolicy(.regular)`, `NSApp.activate(ignoringOtherApps: true)` a
`NSRunningApplication.current.activate(options: .activateAllWindows)`, se stropem 5 s a v obou
testech. Bez key okna nemá fokus kam sednout, takže by taková sonda měřila něco jiného, než tvrdí —
proto v repu **není** a zůstala jen jako samostatný soubor mimo strom. Co v testech **je**, je ta
část, která je číslo: `Policy.pickerShowsSearch(count:)` výčtem kolem hranice, protože jestli se
pole vůbec kreslí, se z okna ptát nemusí. Poslední slovo má proklikání v aplikaci.

**Na `⌥↵` z #413 to platí stejně, a je to tatáž mez.** Klávesa se bere **na poli**
(`onKeyPress(keys: [.return])`, modifikátor se čte z `KeyPress`), tedy tou samou cestou jako šipky —
takže bez key okna do ní nemá co přijít. V testech je proto ta část, která je číslo
(`Policy.newLabelOffer` rozhoduje, jestli se `⌥↵` vůbec na co naváže), a **do popisu PR patří, že
tuhle jednu věc ověří člověk**. Komentář v kódu, který by fokus nebo klávesu tvrdil bez měření, je
zrovna to, co u #392 stálo jedno kolo.

Co se **nedá naklikat** (chybějící binárka, chyba sítě, prázdný stav nad plnou frontou), se dá
vykreslit dočasným testem přes `ImageRenderer` do PNG ve scratchpadu. Před commitem se maže.

Dva zádrhely, které to má:

- **`.buttonStyle(.borderless)` se v `ImageRenderer`u nevykreslí** — místo ikony vyjde žlutý
  placeholder chybějícího symbolu, i u symbolu, který existuje. Není to chyba v aplikaci,
  je to omezení offscreen renderu u AppKit-backed styles. `.plain` SwiftUI kreslí sám
  a vykreslí se správně, takže se dá ověřit. Gate proto používá `.plain`.
- **`ImageRenderer` je `@MainActor`** — pomocná funkce v testu musí být taky, jinak Swift 6
  neprojde.
- **Tmavý režim se předává `.environment(\.colorScheme, .dark)`, ne `NSAppearance`** (#219).
  `performAsCurrentDrawingAppearance` kolem `ImageRenderer`u vypadá jako správná cesta a **tiše
  nefunguje**: barvy z `Palette` (dynamické `NSColor`) se v něm vyhodnotí světle, takže „tmavý“
  render vyjde k nerozeznání od světlého — a vypadá to, že paleta na režim nereaguje. Pozadí za
  renderem se musí nastavit ručně, obojí zvlášť.

- **Přepnutí režimu za běhu se dá změřit bez toho, aby se hýbalo systémem** (#278). Nad hierarchií
  v `NSHostingView` stačí přiřadit vzhled **jejímu oknu** a nechat proběhnout runloop:
  `@Environment(\.colorScheme)` **se pohne spolu s paletou** — změřeno `AppearanceSwitchProbe`, které
  hostuje skutečný blok diffu a bere bitmapu před a po. To je odpověď na jedinou otázku, kterou se
  z kódu přečíst nedá: `Palette` se ptá `appearance.bestMatch(from:)`, kdežto obarvení kódu jde přes
  prostředí, takže kdyby se ty dvě cesty rozešly, vznikne okno s tmavým chromem a světlým kódem.

  Tři věci, bez kterých to nedává odpověď. **Vynuť si oba režimy** (nejdřív `.aqua`, pak
  `.darkAqua`), ne jen ten druhý — na tmavém stroji by „změnilo se to“ vyšlo pravdivě i tehdy, kdyby
  se nepřepnulo nic. **Přepínej na svém okně, ne na `NSApp`** (#367): do té doby sonda sahala na
  globální vzhled a vracela ho `defer`em, což je zápis do stavu, který si hostitel testů **sám
  přepisuje** (změřeno, viz sekce *Globální stav procesu se v testech neměří*) a který mezitím platí
  pro všechno, co zrovna kreslí. Okno je vlastní, takže vynucený režim nikoho jiného nezastihne
  a odpověď se tím nemění — `NSApp.appearance` se k barvám dostane touž cestou, tedy skrz efektivní
  vzhled okna. A **hostuj to, na čem záleží**: pozadí okna
  se přebarví i tak, kdežto obarvená syntaxe jde přes cache vysázeného textu, takže tu je vidět
  jedině na skutečném `DiffBlockRowView`.

  Proto jsou obě sondy k #278 **za přepínačem** (`PRISM_MEASURE`), stejně jako sonda `Přehledu`:
  jedna kreslí **rail** ve všech třech stavech volby a v obou režimech, druhá dělá to přepnutí za
  běhu. Pouští se `TEST_RUNNER_PRISM_MEASURE=1`, protože `xcodebuild` posílá do testovacího procesu
  jen proměnné s tímhle prefixem — bez něj se suita **tiše přeskočí** a v logu to vypadá jako zelený
  běh.

  **Na render se u toho koukat musí, čísla nestačí.** Polohu i velikost ikony v railu změřit jde (a je
  na ně test), ale to, **jestli je v té velikosti poznat, co ikona je**, ne — slunce, měsíc a kolečko
  s „A“ mají v pruhu 16 bodů srovnatelnou plochu, a přesto se od sebe musí přečíst. A barvu čísla
  nechytila vůbec: `.menuStyle(.borderlessButton)` obarvil popisek **akcentem**, takže ikona vyšla
  fialová jako aktivní sekce a rail tvrdil, že je vzhled „zapnutý“. Z obrázku obojí vidět je.

- **`List` se offscreen nevykreslí vůbec** — je to AppKit tabulka a `ImageRenderer` místo
  ní nakreslí žlutý placeholder přes celé plátno. Nevypovídá to o aplikaci. Řádky se dají
  zkontrolovat tak, že se poskládají ručně do `VStack`u mimo `List`.
- **`GroupBox` se offscreen nevykreslí taky** — a na rozdíl od `Listu` beze stopy, takže to
  vypadá, že se stav vůbec nezobrazil. Stejná kategorie jako `.borderless`. Kde na kontrole
  záleží, se hodí vlastní rámeček (`background(…, in: .rect(cornerRadius:))`), který
  SwiftUI kreslí sám.
- **`Link` vyjde jako žlutý placeholder.** V aplikaci je v pořádku, offscreen ne. **V `NSHostingView`
  se ale vykreslí celý** (#291) — i s popiskem a v jeho skutečné šířce, protože tam vzniká pravá
  hierarchie, ne SwiftUI náhrada. Kde na šířce popisku v odkazu záleží, je to jediná cesta;
  z `ImageRenderer`u se jen pozná, **že** tam odkaz je.
- **Přetečení šířky se nezměří tam, kde je nad ním tvrdý rámec** (#291). `frame(width:)` — tedy
  i `filling()` s ustavenou šířkou — drží svůj rozměr i nad dítětem, které se do něj nevejde: dítě
  přeteče **vizuálně** a rodič o tom nic nehlásí. Sonda proto nesmí stát na `fittingSize` rodiče
  a nesmí mít mezi měřeným místem a plátnem konkrétní rámec; kreslí se na plátno **širší** než
  měřená šířka a v přesahu se počítají pixely. `ScrollView` na cestě má tentýž efekt, jen horší —
  ten přesah **ukrojí**, takže rozbitý stav vyjde jako opravený.
- **`NSViewRepresentable` se v `ImageRenderer`u nevykreslí** — vyjde žlutý placeholder přes celé
  plátno, jako `List`. Od #157 se tím kreslí bloky kódu v diffu, takže takhle se vzhled diffu
  zkontrolovat nedá.

  **A celá scéna se dá vykreslit přes `NSHostingView`** (#236), což je jediná cesta, jak se podívat
  na to, co vzniká **složením** SwiftUI a AppKitu — třeba na blok kódu a bublinu nálezu pod ním.
  Scéna se dá do `NSHostingView`, ten do okna mimo obrazovku (`.borderless`, nikdy se neukáže)
  a odtud `cacheDisplay(in:to:)` do PNG. Na rozdíl od `ImageRenderer`u se `NSViewRepresentable`
  vykreslí normálně, protože kreslí AppKit, ne SwiftUI náhrada. Dvě věci, bez kterých to vyjde
  prázdné nebo uříznuté: rámec se musí nastavit z `fittingSize` a mezi tím **nechat proběhnout
  runloop** (`RunLoop.current.run(until:)`), protože representable hlásí rámečky řádků odloženě —
  a pak si výšku vzít z `fittingSize` znovu. Takhle se u #236 doložilo přetečení i jeho oprava:
  ve verzi s chybou stála hlavička bubliny přesně přes dva řádky kódu, oba texty naráz.

  **Samotné `NSView` ale ano, a to je cesta**: `bitmapImageRepForCachingDisplay(in:)` +
  `cacheDisplay(in:to:)` vykreslí `DiffTextView` do bitmapy, kterou si jde přečíst. U #157 to
  rozhodlo tři kola dohadování o čísla řádků — a hlavně to ukázalo, že **co se nakreslí po
  `super.draw`, není vidět** (doloženo plným obdélníkem, který se taky nenakreslil). Pozor při tom
  na `drawsBackground`: s `true` a bílou barvou pruhy pozadí zmizí pod ní, protože je kreslí
  `super.draw` — v aplikaci je `false`, takže test musí být nastavený stejně.

  Zbývá accessibility: bloky jsou `AXTextArea`, takže se dá ověřit, kolik jich vzniklo, a přes
  ⌘A + ⌘C se dá **změřit samotná selekce** (kolik řádků skončí ve schránce).
- **`ScrollView` se nevykreslí taky** — a beze stopy, jako `GroupBox`: vyjde prázdná plocha, takže
  to vypadá, že obsah chybí. Zjištěno u #157 na `CodeTextSheet`u, kde se hlavička vykreslila
  a kód pod ní ne; po vytažení `Text`u ze `ScrollView` se vykreslil. **Než začneš hledat chybu
  v layoutu, zkus obsah vyjmout ze `ScrollView`** — u #157 to stálo dvě zbytečné opravy
  (vodorovný scroll, `textSelection`), než se ukázalo, že v aplikaci je všechno v pořádku.
- **`cacheDisplay` nad `NSHostingView` kreslí i obyčejný SwiftUI `Text`** (#269) — na rozdíl od
  `ImageRenderer`u nad `List`em nebo representablem tady prázdná bitmapa nevzniká: z 56320 pixelů
  se 1904 lišilo od pozadí a věta `za 9min 59s znovu` se z uloženého PNG dá přečíst okem. **Když
  se dva snímky neliší, nehledej chybu v kreslení, ale v čase snímkování** — u #269 to stálo celý
  červený `main`, protože sonda měřila 1,5 s od nasazení a `TimelineView` mění kresbu až na druhém
  tiku rozvrhu, tedy ve 2,0 s. **Ukládej si snímky do souboru a podívej se na ně** (`/tmp`, PNG
  z `representation(using: .png)`); počet bytů řekne jen to, že se něco liší, kdežto z obrázku je
  vidět, co v něm doopravdy stojí — a tím se rozhodne mezi „rozbitá aplikace“ a „rozbitá sonda“.

Stav běžící aplikace jde vyčíst i přes accessibility — a je to **spolehlivější než render**,
protože měří skutečné okno. Chodí se po `UI elements` po úrovních; `entire contents` na
SwiftUI okně vrátí nulu:

```bash
osascript <<'EOF'
tell application "System Events" to tell process "PRism"
    set out to {}
    repeat with e in (UI elements of window 1)
        set end of out to (role of e) & " pos=" & (position of e as string) ¬
            & " size=" & (size of e as string)
    end repeat
    return out
end tell
EOF
```

`value` vrátí texty, `description` popisky tlačítek (`Obnovit`, `Skrýt boční panel`).
Takhle se dá dokázat i rozvržení: že seznam začíná pod toolbarem se pozná porovnáním
`position` scroll areay s výškou `AXToolbar`. Je to **doplněk screenshotu**, ne náhrada:
obrázek ukáže, že je něco jinak, čísla řeknou o kolik.

**Po dočasném testovacím souboru zkontroluj `git status`.** Xcode si při jeho přidání
přepíše `project.pbxproj` — samé přeformátování (uvozovky, pořadí sekcí), žádná změna
významu, ale v diffu PR je to sto řádků šumu. Smazáním souboru se to nevrátí, musí se
`git restore PRism.xcodeproj/project.pbxproj`.

**Když si na chvíli upravíš `RootView`, ať vidíš jiný stav, nezapomeň rebuildnout, než
řekneš, že je hotovo.** Vrácený zdroják na běžící aplikaci nic nezmění a pak se ukazuje
falešná obrazovka.

### Jak ověřit otevření Terminálu (#453)

**Spuštěním, ne přečtením.** Chyba se u téhle cesty projeví tím, že se **okno neotevře a nikdo
se nic nedozví** — v harnessu se přitom ověřit nedá: `osascript` by si vyžádal povolení
automatizace pro testovacího hostitele a otevřená okna by po sobě nechal běh testů. Testuje se
proto **tvar volání** (`TerminalLauncherTests`) a Apple event se zkusí ručně, mimo aplikaci:

```bash
/usr/bin/osascript -e 'on run argv
    tell application "Terminal"
        do script (item 1 of argv)
        activate
    end tell
end run' "cd '/tmp' && echo prism-marker"
```

**Že se okno doopravdy otevřelo, se z výstupu nepozná** (rozhoduje návratový kód, a ten je nula):
`activate` je poslední příkaz skriptu a nevrací nic, takže `osascript` při úspěchu **mlčí**. Bez
`activate` na konci vypíše `tab 1 of window id 202861`. Zpátky se proto čte z okna, a stejnou
cestou se po sobě uklidí:

```bash
/usr/bin/osascript -e 'tell application "Terminal" to get contents of selected tab of front window'
/usr/bin/osascript -e 'tell application "Terminal" to close (every window whose id is 202861)'
```

Co z toho u #453 vyšlo a bez měření by se neodhadlo:

- **`osascript -e <skript> <argument>` argument doopravdy předá** do `on run argv`, takže se
  příkaz nemusí vlepovat do zdrojáku skriptu. Ověřeno i s **apostrofem v cestě**
  (`cd '/tmp/it'\''s here' && pwd` vypsalo `/tmp/it's here`), tedy že uzávorkování ze
  `ShellQuoting` sedí na to, co shell v Terminálu doopravdy dostane.
- **Zavření okna patří k úklidu.** Zkušební okna po sobě nechává i neúspěšný pokus, a v cizím
  Terminálu se pak nedá vybrat, které je čí — `id` vrátí `do script` bez `activate` (viz výš)
  nebo dohledání podle obsahu (`contents of selected tab of w contains "prism-marker"`).

**Co v harnessu ani odsud ověřit nejde, a proto to zkouší člověk**: že Apple event projde
**z aplikace**. TCC ho přisuzuje **odpovědnému procesu**, tedy PRismu, ne tomu `osascript`u —
takže povolení, které má shell, o aplikaci nevypovídá nic. Aplikace k tomu potřebuje
`NSAppleEventsUsageDescription` v `Info.plist` (bez něj macOS event odmítne kódem `-1743`
a **ani se nezeptá**) a napoprvé systémový dotaz, který se musí odkliknout. **Každý slot je pro
macOS jiná aplikace**, takže se ptá zvlášť — stejně jako u notifikací.

## Jak změřit, že okno netuhne (#220)

Měřicí harness je `Tests/Diff/DiffPerformanceMeasurement.swift` a **v běžném běhu se nepouští** —
je za přepínačem. Za tímtéž přepínačem stojí i `Tests/Views/DetailProgressMeasurement.swift` (co
stojí jedna událost průběhu review v otevřeném detailu, #350) a `Tests/Views/IdleWindowSpinProbe.swift`
(kolik CPU sežere okno, ve kterém se **nic nemění**, #350) — obojí se pouští stejně, jen s jiným
`-only-testing`:

```bash
TEST_RUNNER_PRISM_MEASURE=1 xcodebuild -project PRism.xcodeproj -scheme PRism \
    -derivedDataPath build.noindex test \
    -only-testing:PRismTests/DiffPerformanceMeasurement > /tmp/perf.log 2>&1
grep -E "^MĚŘENÍ" /tmp/perf.log
```

**Prefix `TEST_RUNNER_` tam musí být.** `xcodebuild` proměnné prostředí do testovacího procesu
nepředává, jen ty s tímhle prefixem — a bez něj se měření **tiše přeskočí**: běh projde zeleně
a `Test run with 5 tests … passed after 0.001 seconds` je jediné, z čeho se to pozná. Do #223 tu
stál příkaz bez prefixu, takže vypadalo, že měření běželo. Když výpis `MĚŘENÍ` chybí, je to tenhle
případ, ne že by se nic nenaměřilo.

**Jedno měření se vybírá se závorkami: `…/wordDiffCost()`.** Bez nich `-only-testing` na funkci
ze `swift-testing` nesedne na nic a běh skončí `Executed 0 tests` — zeleně, takže to vypadá jako
prázdný výpis měření, ne jako špatný filtr. U celé suite (`-only-testing:PRismTests/…Measurement`)
závorky nejsou.

**Proč za přepínačem:** jeden render v hloubce 8 stojí 15 sekund CPU a tím hladoví ostatní testy.
Bez toho přepínače z toho spadly dva časově citlivé testy v `RealEnvironmentTests`, které
v izolaci procházejí — tedy pád bez chyby v kódu, přesně to, co test dělat nemá. Celá suite
s vypnutým měřením běží 6 s, s ním 41 s.

**Nad hloubku 6 se v harnessu nechodí.** Cena roste ~5,5× na úroveň, takže hloubka 8 je 15 s
a hloubka 12 hodiny. Čísla z hloubky 8 jsou zapsaná v `docs/architektura.md`, protože je nemá smysl
platit při každém měření.

**Časy se netvrdí `#expect`em.** Jsou strojově závislé a byl by z toho test padající bez chyby
v kódu. Harness **vypisuje** a čte je člověk; co se hlídá strojově, je tvar (například kolik řádků
skončí v jednom bloku), ne milisekundy.

Co harness měří:

| Měření | K čemu je |
|---|---|
| cena layoutu podle hloubky zanoření | ta hlavní věc — ukáže, jestli se vrátilo vyjednávání šířky |
| která opatření exponent zabijí | dokládá, že `Spacer` ani hranice každou 4. úroveň nestačí |
| osa konverzace podle počtu uzlů | skutečná views, ne syntetický tvar — má být lineární |
| model diffu na 2400 řádcích | dokládá, že model **není** příčina (jednotky ms) |
| cena vykreslení podle délky bloku (#223) | z toho se vybral strop `DiffBlock.maxLines`; měří se **jeden blok** i celý soubor po blocích |
| cena word-level rozdílu (#153) | proč se počítá až při skládání bloku: **0,42 ms** na blok o 60 řádcích samých dvojic proti **19,6 ms** za celý soubor o 2400 řádcích, což by se platilo při každém překreslení |
| podíl word-diffu na skládání bloku (#153) | odpovídá na „ztuhlo to kvůli #153?“ — `DiffPairBlockContainer.show` na 27 blocích samých dvojic **61,5 ms**, z toho `WordDiff` **14,0 ms**, tedy **23 %** v nejhorším případě; skládání bloku je přitom jen část ceny scrollování. Podíl vzrostl u #275 z 18 %, a `WordDiff` se přitom nezměnil — zlevnilo se to, s čím se poměřuje |
| z čeho se skládá cena sazby bloku (#275) | rozpad `show` na fáze, aby se dalo poznat, co je co: `WordDiff` **14,0 ms**, složení atributovaného textu **4,5 ms** (do #275 **22,2 ms**), nasazení do `NSTextStorage` **3,8 ms**, nasazení + sazba **39,5 ms**. Fáze se měří **za sebou v pořadí, v jakém běží**, takže se dají odečítat. Měří i **čerstvý kontejner** (72,4 ms proti 61,5 ms), protože `LazyVStack` view nerecykluje — a to je, co platí projíždění. Celé `show` stálo do #275 **86,3 ms**; absolutní čísla se hýbou se zátěží stroje (na volnějším vyšla tatáž dvojice 79,2 → 60,0), takže se čte **poměr**, ne milisekundy |
| cena overlay gutteru podle tvaru (#252) | dvě čísla na bloku o 60 řádcích: `po řádcích` (do #252) **3,05 ms**, `po bloku` (od #252) **0,12 ms**, tedy 26× — a pro srovnání, samotný text téhož bloku stojí 2,8 ms, takže overlay býval dražší než kód, který zdobí |
| cena zápisu ploch pro tažení (#252, #274) | `DiffRowFrames` s 4000 záznamy (jeden velký PR) a blok o 120 plochách: **po řádcích 24,1 ms, naráz 0,25 ms**. Je to ta kvadratická část — úklid je lineární v počtu záznamů, takže po řádcích se platí za každý. Od #274 se měří i **jak to roste s prohlédnutými záložkami**: 4000 záznamů **0,25 ms**, 8000 **0,49 ms**, 16000 **0,93 ms** (tedy 3,7× za čtyři záložky), a po přepnutí diffu **0,063 ms**, protože krabice cizí plochy zahodí. **Čísla se u #274 přeměřila**, do té doby tu stálo 22,6 → 1,40 ms: měřidlo počítalo i **naplnění** krabice, tedy 4000 ploch k tíži bloku o 120 — příprava se od té doby dělá mimo hodinky (`measure(_:preparing:_:)`) |
| cena obarvení se cachí a bez ní (#224) | tři čísla na jednom souboru o 2400 řádcích: `scan` bez cache **44 ms**, totéž z plné cache **0,30 ms** (~145×), naplnění prázdné cache **44 ms** — uložení se v šumu ztratí |
| co v cache zůstane ležet (#224) | 68 kB textu run na 2400 řádků (~29 B na řádek), tedy z čeho se strop `capacity` překládá na kilobajty |

**Tuhnoucí okno se diagnostikuje `sample`m, ne odhadem.** Dokud proces visí, jde z něj vytáhnout
příčina; po zabití už ne:

```bash
PID=$(pgrep -x PRism)
ps -o %cpu,state -p "$PID"      # 100 % + R = točí se; ~0 % + S = čeká (deadlock, I/O)
sample "$PID" 5 -file /tmp/hang.txt
grep -A3 "Total number in stack" /tmp/hang.txt   # rekurzivní počty = hloubka
sed -n "$(grep -n 'Sort by top of stack' /tmp/hang.txt | cut -d: -f1),+30p" /tmp/hang.txt
```

Rozlišit „točí se“ od „čeká“ je první krok — u #220 to bylo 100 % CPU po dvaceti minutách ve
stejné rekurzi, což vylučuje deadlock i pomalé I/O a ukazuje na layout.

**Druhý krok je vyloučit, že za to může poslední změna — a to se dělá měřením obou verzí na
tomtéž vstupu.** Ztuhlé okno nad rozdělanou branchí svádí k tomu prohlásit tu branch za příčinu;
u #153 to vyšlo naopak a stálo to hodinu. Co se ukázalo a co z toho platí obecně:

- **Srovnání „main běží na 0 %, branch na 100 %“ nic neváží, dokud v obou nemáš tentýž PR
  v tomtéž pohledu.** Scrollování velkého diffu vedle sebe stojí sekundy CPU v **obou** verzích;
  aplikace, která zrovna nic nekreslí, stojí nula i tehdy, když je regrese uvnitř.
- **Klikání přes `System Events` je moc hlučné na to, aby se z něj vyvozovala regrese.** Tentýž
  scénář (fronta → `job-queue-daemon#858` → záložka s diffem ve splitu → rozbalit skrytý úsek →
  sjet a vyjet) vyšel na mainu **5,4 s** a podruhé **12,5 s** CPU, na branchi **13,7 s** a **11,0 s**.
  Rozptyl je větší než hledaný rozdíl, protože do toho mluví, kam scroll doopravdy dojel a co si
  zrovna berou ostatní instance. Číslo, na kterém se dá stavět, musí být **bez GUI** — proto to
  měření podílu v harnessu výš.
- **Co bylo v sample vidět, byl obraz příčiny, ne příčina.** V zásobníku (6538 řádků, 3 s živého
  procesu) byl náš kód **65×**, zbytek je `LazySubviewPlacements.placeSubviews` a
  `_LazyLayoutViewCache` — tedy rozvržení líného seznamu. `WordDiff` ani `SyntaxHighlighter`
  v něm **nebyly ani jednou**. `initializeWithCopy for DiffPairBlockView`, které tam vidět je, je
  kopie struktury view při umísťování prvku — a ta struktura se #153 vůbec nezměnila.

Vyloučené příčiny se zapisují stejně jako ta potvrzená (pravidlo z #220). Bez toho po nich sáhne
příští session znovu — u #153 to byly tyhle tři:

| Podezření | Čím padlo |
|---|---|
| Word-diff se počítá při každém umístění prvku | Počítá se za stráží na podpis obsahu v `DiffTextView.show(…)`; naměřeno **18 %** ceny skládání bloku v nejhorším případě (samé dvojice), na skutečném diffu méně |
| `WordDiff.Spans` se dostalo do hodnoty, kterou SwiftUI kopíruje | `DiffPairBlockView` nemá o pole víc než před #153; spany drží `DiffTextView`, což je `NSView`, ne struktura view |
| Nekonečná smyčka rozvržení, kterou #153 rozjelo | Tuhnutí se reprodukovalo **projížděním** velkého diffu vedle sebe a po zastavení scrollu se ustálí; na mainu se chová stejně |

### Ve `sample`u se čte podíl, ne jen vrcholy zásobníku (#350)

**Nejčastější list nemusí být nic — rozhoduje, kolik vzorků má celé vlákno a kam ta většina míří.**
U #350 stálo v zadání „`propagate_dirty` 280 vzorků, `UpdateStack::update()` 265“, a z toho to
vypadalo na drahou práci nad konkrétními daty. Celý soubor ale říkal něco jiného: hlavní vlákno mělo
**3709 vzorků** a **3599 z nich** (97 %) leželo pod `NSDisplayCycleFlush → NSHostingView.layout()`.
Ty vrcholy byly jen nejhrubší kamínky uvnitř té jedné cesty.

**A z kořene se pozná, jestli jsou vzorky o téže věci** — což je u víc vzorků ta první otázka, ne
poslední. #350 měl tři a listy měl každý jiné (osa konverzace, computed properties detailu, diff),
takže to vypadalo na jednu příčinu viděnou třemi pohledy. Kořeny ale byly dva, a vylučují se:

| Kořen 100 % vzorků hlavního vlákna | Co to je | Poznávací znak |
|---|---|---|
| `NSDisplayCycleFlush → NSHostingView.layout()` | takt překreslování obrazovky, tedy **animace** | v cestě je `+[NSAnimationContext runAnimationGroup:]` (1754 vzorků) a `render(interval:…)` |
| `NSRunLoop.flushObservers → NSHostingView.beginTransaction → GraphHost.flushTransactions` | vyprazdňování **čekajících transakcí** v každém kole smyčky, tedy něco, co graf pořád špiní | `runAnimationGroup` ani display cycle v cestě **nejsou vůbec** (nula vzorků). Tohle je #358; kdo to špiní, se dohledá pod `Update.dispatchActions()` — viz níž |

Rozlišit se to musí, protože z toho vyjdou dvě různé opravy — a **pozná se to jedině tehdy, když se
kořen přečte u každého vzorku zvlášť.** Sečtená tabulka vrcholů by obě signatury slila do jedné,
protože `AG::Graph::UpdateStack::update()` a `propagate_dirty` jsou v obou.

#### Kdo tu smyčku špiní: čte se `Update.dispatchActions()`, ne listy (#358)

U té druhé signatury je otázka „co graf pokaždé zašpiní“, a **v listech odpověď není** — tam je vidět
jen průchod celým `ForEach`em (`FileDiff.id`, `DiffRow.id`, `_StringGutsSlice._fastNFCCheck`), tedy
následek. Postup, kterým se to u #358 dohledalo, je ve třech krocích a každý z nich je negativní
tvrzení nebo jmenovitá cesta:

1. **Vylučte vnější pohon.** V hlavním vlákně grepněte `_dispatch_main_queue_callback_4CF`,
   `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__` a obsluhu událostí. Když jsou všechny
   **nula** (a u #358 byly), smyčku nekrmí nic zvenčí a pohon musí být uvnitř transakce. Dokud tam
   timer je, hledá se timer.
2. **Přečtěte podstrom `static Update.dispatchActions()`** pod `GraphHost.runTransaction`. Tam SwiftUI
   pouští akce, které si transakce naplánovala — a právě jimi se zavírá kolo. U #358 bylo 1630 z 1690
   vzorků v `EventBindingManager.enqueueHoverUpdateIfNeeded()` → `NSHostingView.didRequestHoverUpdate()`
   a přes `HoverResponder.updatePhase(_:)` se z něj volalo `.onContinuousHover` v našem view. Druhý
   re-arm ležel vedle: `LazyLayoutViewCache.signalPrefetch()` → `NSHostingView.requestUpdate(after:)`
   — a ten se opravou hlavního pohonu **ztratil sám** (po opravě nula vzorků), protože si o další kolo
   říkal jen kvůli tomu, že se rozvržení pořád přepočítávalo. Vedlejší re-arm tedy nemusí mít vlastní
   opravu; napřed se opraví ten, který drží většinu vzorků, a znovu se změří.
3. **Najděte v tom podstromu rámec aplikace a dohledejte, co zapisuje.** Naše closure je ve `sample`u
   číslovaná v pořadí literálů v `body` (`closure #5 in DiffPairBlockRowView.body.getter`), takže se
   podle pořadí dopočítá řádek. U #358 to byl bezpodmínečný zápis do `@State hovered` — a ten typ je
   `(index: Int, side: DiffSide)?`, tedy **tuple, který `Equatable` není**, takže na něm nemůže zabrat
   žádné porovnání ani výš.

`sample` tiskne strom s odsazením z `+!:|`, takže se podstrom nedá grepnout — čte se buď `sed`em podle
řádků, nebo krátkým skriptem, který odsazení převede na hloubku a vypíše **přímé potomky** daného uzlu.
Bez toho se v podstromu s desítkami tisíc řádků neorientuje.

Dvě věci, které se u toho **taky musí změřit**, protože obě vypadají jako příčina a nejsou:

- **Naše `NSViewRepresentable`.** Grepněte `updateNSView`, `lineFrames`, `height(forWidth:)`,
  `sizeToFit`, `layoutManager`. U #358 to bylo 2, 0, 0, 0, 0 — text se vůbec nepřeměřoval, takže
  zpětná vazba `noteFrames` → `@State frames` (kterou drží strážce v `Coordinator`u) je vyloučená.
- **Že to není animace.** `runAnimationGroup`, `NSDisplayCycleFlush` a `CABasicAnimation` musí být nula,
  jinak se čte ta první signatura z tabulky výš.

**Reprodukce si žádá kurzor ležící v okně nad blokem kódu.** Tohle je na tom nejdražší poznatek: #358
se nedařilo vyrobit na vyžádání (`%cpu` 0,0 při „nečinnosti“) právě proto, že hover responder se
nerozřeší, když myš nad diffem není — a „nečinnost“ znamená nechat myš tam, kde skončila. Kde je,
se zjistí bez zásahu do aplikace:

```bash
# NSEvent.mouseLocation + CGWindowListCopyWindowInfo, tedy jen čtení — aplikace se nijak neovládá
swift mouse.swift
```

Podmínkou je dál **split diff** (jen `DiffPairBlockRowView` měl ten tuple stav); velký diff kolo
zdraží, ale nezpůsobí. A **běžící review je zhoršovák, ne podmínka** — doloženo tím, že potomek
`claude` skončil a okno zůstalo minutu dál na 98,2–100,5 % CPU s nulou potomků.

#### Proč na #358 není sonda, a je to změřené (#358)

Nabízelo se postavit sondu jako u #350 — okno na obrazovce, kurzor nad blokem, změřit CPU. **Nejde
to a stálo to dvě zjištění, která se tady zapisují, aby to příště nikdo nezkoušel znovu:**

| Pokus | Co se stalo |
|---|---|
| Syntetická `.mouseMoved` do okna (`window.sendEvent`) | `onContinuousHover` se **nevyvolal ani jednou** (0 zásahů) |
| Totéž přes frontu aplikace (`NSApp.postEvent`) | Taky **0 zásahů** |
| Okno postavené pod skutečný kurzor | Kurzor patří člověku u stroje: mezi postavením okna a měřením se posunul o desítky bodů, a jeho pohyb **sám mění** hodnotu hoveru, takže by se neměřila smyčka |

SwiftUI si hover řeší z **tracking areas a skutečné polohy kurzoru**, ne z podstrčené události.
Zavřít to kolo v testu by tedy znamenalo warpovat kurzor (`CGWarpMouseCursorPosition`), tedy sebrat
myš člověku, který u stroje pracuje — to sonda dělat nemá, stejně jako si nebere klávesnici (#350).

Sonda, která tohle nedokáže, přitom **není neutrální, je škodlivá**: první podoba téhle sondy tvrdila
0 % CPU i nad buildem s **vrácenou regresí** — tedy přesně to, na co si tenhle dokument stěžuje
u kontrol, které se nespustily ve výjimečném stavu. Proto se zahodila, ne odložila. (Chytila u toho
jednu svou vlastní vadu, která se hodí znát: `contentViewController` **přebije** `contentRect`, takže
okno spadlo na 295×207 a žádný blok kódu v něm nebyl. Velikost se nastavuje **až za** kontrolérem.)

Testuje se místo toho **ta čistá funkce a hodnota, kterou dostane** — `Policy.hoverChange(from:to:)`
vyčerpaná výčtem (`HoverChangeTests`) a `DiffGutterGeometry.hoveredCell(at:)` s tvrzením, že tentýž
bod nad tímtéž blokem vydá **rovnou** hodnotu. To druhé je to podstatné: kdyby si buňka nesla cokoli
nestálého (identitu, čas, referenci), porovnání by nikdy nesedlo, zápis by proběhl každé kolo a smyčka
by se vrátila — a **všechny ostatní testy by zůstaly zelené**. Ověřeno vložením regrese: `hoverChange`,
která vrací vždycky `.write`, položí **6 tvrzení ve dvou sadách**. Poslední kolo dělá člověk na běžící
aplikaci, protože skutečnou myš má jedině on.

**Jak to poslední kolo vypadá, ať se příště nehádá o metodiku.** Aplikace **vpředu** (přepnutá přes
`activate` na bundle ID, ne klikáním na souřadnice), kurzor **zaparkovaný nad blokem kódu ve split
diffu**, ruce pryč — a měří se **rozdíl kumulativního CPU času**, ne `%cpu`:

```bash
P=$(pgrep -f 'PRism-c.app/Contents/MacOS/PRism')
A=$(ps -o time= -p $P); sleep 20; B=$(ps -o time= -p $P); echo "$A -> $B"
```

`%cpu` z `ps` je **klouzavý průměr**, takže po zaparkování myši chvíli ukazuje starou hodnotu a po
odjezdu myši ji naopak ještě drží — u jevu, který se zapíná a vypíná polohou kurzoru, je to zrovna ta
veličina, která lže v obou směrech. U #358 vyšlo `0:09.58 → 0:09.58`, tedy **0,00 s za 20 s**, a ve
`sample`u **4394 ze 4394** vzorků v `mach_msg2_trap`. Co se u toho **nepovedlo ověřit programově**, je
poloha kurzoru (systémový `python3` tu nemá `Quartz`) — takže „myš ležela nad kódem“ zůstává z lidského
slova; aplikace vpředu a ta nulová čísla ověřená jsou.

**A že jsou to doopravdy dvě věci, se ověří vložením regrese**, ne úsudkem: vrátit opravenou příčinu
zpátky a vzít `sample` **testovacího hosta** při běžící sondě (`sample <pid> 4`, PID se najde jako
`pgrep -f 'build.noindex/.*PRism.app/Contents/MacOS/PRism'`). U #350 z toho vyšla zase jen ta první
signatura, takže druhá zůstala nevysvětlená — což je závěr, ne mezera.

Čísla, ze kterých se to přečte, jsou v hlavičce grafu, ne v `Sort by top of stack`:

```bash
sample "$PID" 5 -file /tmp/hang.txt
grep -n "com.apple.main-thread" /tmp/hang.txt        # kolik vzorků má hlavní vlákno celkem
# a pak větve u kořene — kam z těch vzorků většina jde
python3 - <<'PY'
import re
pat = re.compile(r'^([ +!:|]*)(\d+) (.*)$')
for line in open('/tmp/hang.txt', errors='replace'):
    m = pat.match(line.rstrip())
    if m and len(m.group(1)) <= 60 and int(m.group(2)) >= 15:
        print(f"{len(m.group(1)):4d} {int(m.group(2)):6d} {m.group(3)[:100]}")
PY
```

Dvě věci, které z toho výpisu u #350 padly hned:

- **Ani jeden rámec aplikace.** Kdyby cenu drželo přepočítávání nad daty (nálezy, konverzace), byl by
  v té cestě vidět náš kód. Nebyl — celá cena je rozvržení, které se opakuje samo.
- **`NSHostingView.layout()` se dělí skoro půl na půl** mezi `render(interval:…)` (1378 vzorků)
  a `invalidateSizeConstraintsIfNecessary()` → `minSize()` → `ViewGraph.sizeThatFits(_:)`
  (1374 vzorků). Půlka ceny každého snímku je tedy jen dopočet velikosti do constraints hostujícího
  view — a to se dá zjistit jedině ze `sample`u, z API to vidět není.

**Nečinné okno se měří na obrazovce, jinak se smyčka neprojeví** (`Tests/Views/IdleWindowSpinProbe.swift`).
Okno mimo obrazovku ani zakryté okno **nedostává takt překreslování**, takže nekonečná animace v něm
nespotřebuje nic a sonda by tvrdila, že je čisto. Sonda proto dává oknu `level = .floating`
a `orderFrontRegardless()` — vidět být musí, fokus si brát nesmí (vedle běží terminál a cizí
instance PRismu). CPU se čte `clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)` na hlavním vlákně, ne
nástěnnými hodinami: smyčka většinu času spí, takže nástěnný čas by měřil délku spánku. Naměřená
čísla jsou v [`architektura.md`](architektura.md), sekce *Nekonečné animace v okně*.

**Nulové CPU není doklad, že se něco točí** — stejně dobře to je nehybný prstýnek. Sonda proto vedle
CPU vydá i **otočení z prezentační vrstvy** (`arc.presentation()`) ve třech okamžicích; má se hýbat
o ~1,4 rad za 0,2 s, což je ta jedna otáčka za 0,9 s. Model vrstvy o animaci nic neví, takže se to
z něj vyčíst nedá.

**Kolik kruhu zabírá oblouk, se počítá z alfy, ne z barvy.** Prstýnek se kreslí do průhledna, takže
barevné složky jsou premultiplikované a tichý kruh i prázdno mají červenou blízko nuly — první podoba
téhle sondy podle ní tvrdila „oblouk zabírá celý kruh“ i nad kresbou, která je v pořádku, a málem
z toho byla oprava neexistující chyby. Podle alfy vyjde **0,35** (0,30 z `strokeEnd` plus kulaté
zakončení tahu) a tichý kruh 0,65.

**`screencapture` z testovacího hosta nefunguje** a **nic neřekne**: oprávnění k nahrávání obrazovky
má terminál, ne testovací host, takže `screencapture -l<okno>` skončí nulovým kódem a bez souboru.
Kresba se proto bere `cacheDisplay(in:to:)` z toho view, o které jde (`ring.bounds`, ne kontejner —
jinak se fotí padding a měření radiusu ukazuje mimo prstýnek).

**Frekvence událostí průběhu se dá změřit z transcriptů skutečných běhů**, ne odhadnout. `claude` si
je vede v `~/.claude/projects/`, a běhy PRismu jsou poznat po cestě k pracovnímu stromu:

```bash
ls -d ~/.claude/projects/*PRism*worktrees*      # jedna složka na strom, v ní JSONL sessiony
```

Každý záznam nese `timestamp` a `message.content` s bloky `tool_use`; jedna událost `attemptedTool`
odpovídá jednomu takovému bloku (`ClaudeReviewRunner.consume`). Naměřeno na **145 sessionech**:
**0,07–0,37 události za sekundu** (medián 0,15), špička **2 za sekundu** a nejvýš **4 za pět
sekund**. Z toho vyšlo, že hypotéza „události průběhu tuhnou okno“ je o dva řády mimo — při
9–55 ms na událost (`DetailProgressMeasurement`) je to nejvýš dvě procenta procesoru.

**Fixtures `stream-json` na tohle nestačí** a je dobré vědět proč: jsou to výstupy z malých spiků,
takže v každé jsou **jedna až dvě** `tool_use`. Tvar události se z nich vzít dá, tempo ne.

Vyloučené příčiny #350, aby po nich příští session nesáhla znovu:

| Podezření | Čím padlo |
|---|---|
| Každá událost průběhu přepočítá pruh záložek (`tabs` → `Policy.tally` → `visibleFindings`) | Cena je změřená (9–55 ms na událost), ale frekvence je 0,07–0,37 ev/s → nejvýš 2 % CPU. A cena je **v zašpinění těla, ne v té práci**: zápis do `reviewPhases`, který s osou nedělá nic, stojí stejně (kontrolní série v `DetailProgressMeasurement`). Odznaky samotné jsou 0,006–0,15 ms |
| ~~Nekonečná smyčka rozvržení (zápis do stavu během `body`)~~ **potvrzená, je z ní #358** | Vylučovalo se to úvahou, že okno **reagovalo** (jen lagovalo), takže smyčka to být nemůže — **a ta úvaha je špatná.** Smyčka přes runloop observer (`flushObservers → beginTransaction`) pustí mezi koly události, takže okno odpovídá a jen lagne; procesor nepustí to ani ono. Signatura vzorků 1 a 3 je právě tohle a **oprava prstýnku ji nevysvětluje** (ověřeno vložením regrese). Doměřeno na živém ztuhlém okně: pohonem je **hover** (`.onContinuousHover` píše `@State` bez porovnání), postup je v sekci níž |
| Rozbor `stream-json` běží na hlavním vlákně | `ClaudeReviewRunner` je `struct` bez izolace a `SWIFT_VERSION = 6.0` (bez `NonisolatedNonsendingByDefault`), takže jeho `async` metody běží na globálním executoru; `readabilityHandler` čte rouru na vlastní frontě Foundationu. Ve `sample`u není ani jeden rámec parseru |
| Osa běhu roste a její kopírování zdražuje každou událost | `reviewTimelines` má strop 300 uložených položek a kopie pole struktur je v šumu — a hlavně: kontrolní série výš ukazuje, že na tom, **co** se do storu zapíše, nezáleží |

### Co je u #361 změřené a co z toho zbývá (#361)

#361 je **tatáž signatura jako #358** (`flushObservers → beginTransaction → flushTransactions`, nula
vzorků na animaci i na timeru), ale pohonem už není náš zápis: grep na `onContinuousHover` vychází
čistě a v hover podstromu obou vzorků není **ani jeden rámec aplikace**. Zbývala tedy otázka **co
rozvržení pořád špiní** — a ta se z těch dvou vzorků nedohledala. Co se k ní změřilo, ať to příští
session nezkouší znovu od nuly:

**Akce `onGeometryChange` se nespustí, když se hodnota nezměnila — a hodnota se přitom počítá
pokaždé.** Sonda `Tests/Views/LayoutCallbackProbe.swift` špiní graf zvenčí (`Timer` po 50 ms) a
počítá zvlášť **výpočet hodnoty** (closure za `for:`) a **akci** (zápis):

| Scénář | Zašpinění grafu | Výpočet hodnoty | Akce (zápis) |
|---|---|---|---|
| stálá geometrie (špiní se krytí, ne rozměr) | 80× | **80×** | **0×** |
| měnící se geometrie (rozměr o bod) | 80× | 80× | **80×** |

Druhý řádek je **kontrola měřidla**, ne informace: bez něj by nula v prvním řádku mohla znamenat
i rozbitou sondu. Z prvního řádku plyne, že těch šest míst s `onGeometryChange` v aplikaci **do
třídy chyb z #358 nepatří** — zápis je gatovaný frameworkem. A sedí to na vzorek: v obou profilech
je vidět **jen výpočet** hodnoty (`closure #3 in DiffPairBlockRowView.body.getter`,
`DiffPairBlockRowView.swift:50`, 14 z 1992 a 24 z 3593 vzorků) a **akce v nich není vůbec**, takže
`placement.rect` ani `noteRows()` v tom okně neběžely.

**Hover callbacky se v sondě změřit nedají, protože aplikace na pozadí je nedostává.** Táž sonda má
i hover část: okno se postaví **pod kurzor tam, kde právě je** (myš se nebere, viz #350), kurzor
v okně leží (ověřeno `window.frame.contains`) — a přes 80 zašpinění grafu se `onHover` ozval **0×**
a `onContinuousHover` taky **0×**. Vpředu je terminál, který test pustil, takže tracking areas nic
nedoručují. Číslo „nula“ tedy o gatování hover callbacků **netvrdí nic** a sonda to sama vypisuje.
Zůstává z toho: **`.onHover` je jediný z těch callbacků, u kterého se pořád jen předpokládá, že chodí
při změně** — a `PullRequestTabBar.swift:203` do něj píše bezpodmínečně
(`hovered = $0 ? tab : (hovered == tab ? nil : hovered)` zapíše i **tutéž** hodnotu, což podle #358
stačí). Je to vada k opravě, **ale #361 nevysvětluje**: ten pruh sedí **pod** hlavičkou, uvnitř
detailu, kdežto 28 bodů od horní hrany okna je `ContentView.header` (vysoká 40 pt) s `ReviewTabsView`
a tlačítky — a tam **žádný `onHover` není**, jen `.help()`, které si drží AppKit. Pod kurzorem tedy
u #361 **žádný náš zápis z hoveru nebyl**, a v hover podstromu obou vzorků není ani jeden rámec
aplikace. Kolo se tedy zavírá uvnitř SwiftUI a jediné, co z aplikace v transakci běží, je **výpočet
hodnoty geometrie v pojmenovaném prostoru** (`frame(in: .named(DiffView.contentSpace))`, tři místa
v seznamu řádků).

**Scéna sama kolo nezavírá** (`Tests/Views/IdleDiffSpinProbe.swift`). Sonda hostuje okno
**na obrazovce** ve stejném rozměru jako ta ztuhlá instance (1512×874) a čte CPU hlavního vlákna:

| Co je v okně | CPU hlavního vlákna v nečinnosti |
|---|---|
| přehled (bez diffu) | 0,01 % |
| diff pod sebou | 0,01 % |
| diff vedle sebe | 0,00 % |
| plné okno (`ContentView`, tři záložky, nálezy, konverzace, split) | 0,00 % |
| totéž odscrollované o 8000 pt | **3,26 %** v prvních 5 s, pak **0,00 %** po 35 s |

Ten poslední řádek je na tom podstatný: **z jednoho čísla za třicet sekund by vyšlo, že okno hoří.**
Proto se měří po úsecích — 3,26 % je usazení po posunu, ne kolo. A kurzor u toho v okně ležel
(sonda ho zabírá skoro celou), takže se to nedá odbýt tím, že myš byla jinde.

Tři pasti, kvůli kterým sonda **měřila prázdno a tvrdila, že je čisto**:

- **Velikost okna se nastavuje až za `contentViewController`em** (tatáž past jako u #350). Před ním
  se `contentRect` zahodí a v okně zbyl **jeden** blok kódu.
- **Rozměr se scéně musí předepsat** (`.frame(width:height:)`). Diff je uvnitř `GeometryReader`u
  pružný, takže ideální výška detailu je hlavička plus pruh záložek — okno se usadilo na **1512×265**
  a bloky kódu v něm nebyly. Sonda proto vypisuje **počet bloků kódu v okně**; bez toho čísla nula
  netvrdí nic. A ten scvrkávající se rozměr **není nevinný**: dokud si velikost okna určoval obsah,
  padal testovací host na `NSGenericException` z AppKitu („marked as needing another Update
  Constraints in Window pass, but it has already had more … than there are views“) uvnitř
  `NSHostingView.updateConstraints → updateWindowContentSizeExtremaIfNecessary → minSize`. Je to
  **oscilace sondy, ne aplikace** — okno `WindowGroup`u si rozměr od obsahu nebere —, ale vypadá to
  jako nález, takže se to tady zapisuje.
- **Do `ContentView` se PR dostane jen frontou.** Bez `await store.refresh()` záložka detail vůbec
  nekreslí (0 bloků), i když je diff ve storu načtený.

**Od #375 pokrývá sonda všechny záložky, ne jen diff**, protože „hoří jen konverzace“ je tvrzení
o všech, ne o jedné. Nečinné okno **nehoří na žádné** (plné okno, 1512×874):

| Záložka v nečinném okně | CPU hlavního vlákna |
|---|---|
| Přehled | 0,03 % |
| Konverzace | 0,00 % |
| Konverzace odscrollovaná o 1000 / 3000 | 0,01 / 0,00 % |
| Commity | 0,01 % |
| Kontroly | 0,01 % |

**Nečinnost o projíždění netvrdí nic** (#375), a scénář ze ztuhlé aplikace 2026-08-18 byl „projížděl
jsem konverzací“. Sonda proto má i `scrollingConversation` a `scrollingDiff`: scrolluje **po malých
krocích** (150 × 40 pt, kolo runloopu po každém), protože skok o půl obrazovky přerovná líný seznam
jednou a rozdíl se v něm utopí — tatáž past jako hustota kroků u #252. Naměřeno **1,27–1,30 s** CPU
u konverzace a **0,96–1,16 s** u diffu, a **na pružné výšce v uzlu osy to nezávisí** (1,30 s s ní,
1,28 s bez ní).

**A tady je to podstatné: měřidlo tuhle třídu nevidí, a pozná se to jedině vloženou regresí.**
Se **šesti** pružnými úrovněmi navíc v uzlu osy vyšlo projíždění na **1,08 s**, tedy **levněji** než
s jednou. Kdyby se kontrola nepustila, vyšlo by z dvojice 1,30 → 1,28 s, že oprava „nic nezhoršila“,
a mlčky by se z toho stalo „vzor je neškodný“. Platí tedy obojí:

- **pružná výška v řádku líného seznamu není ten multiplikátor, který má šířka** — v řádku se výška
  navrhuje jako `nil`, takže `frame(maxHeight: .infinity)` vrátí ideální rozměr dítěte, jeden
  průchod (rozvedeno v [`architektura.md`](architektura.md), sekce o šířce);
- **„bez rozdílu“ u tohohle měřidla neznamená „neškodné“** — u buňky dvojice (#98) tentýž vzor
  aplikaci položil, jen v hit testu při pohybu myši, což tenhle scénář nevytěžuje.

**Vzhled osy se kontroluje `DetailTabRenderProbe`, a ta do #375 rendrovala spinner.** Sonda neměla
načtenou konverzaci, takže záložka `Konverzace` byla na snímku `Načítám konverzaci…` — srovnání
„před/po“ tedy porovnávalo **dva spinnery** a vycházelo identické, ať se s osou stalo cokoli. Je to
tatáž past jako počet bloků kódu u sondy výš: **snímek, na kterém to, co se posuzuje, není, netvrdí
nic.** Po doplnění fixture je na ose 44 položek a byte-identické rendery v obou verzích už něco
znamenají. Pozor u toho na jednu drobnost: `conversation(id:)` si ověřuje, že GraphQL odpověděl na
totéž PR, na které se ptal, takže se fixture dekóduje na **číslo z fixture** (13084), ne na `pr`
sondy (14013).

**`-only-testing` na jeden test ze `swift-testing` potřebuje závorky** — a je to past, která spálí
čas každému, kdo sondu pouští poprvé. Bez nich filtr nesedne na nic a běh skončí
`Test run with 0 tests … passed`, tedy **zeleně**: vypadá to, že se suita přeskočila kvůli
`.enabled(if:)`, ne že je špatný filtr. (Totéž stojí u měřicího harnessu výš; u #361 na tom uvázlo
jedno kolo.)

```bash
TEST_RUNNER_PRISM_MEASURE=1 xcodebuild -project PRism.xcodeproj -scheme PRism     -derivedDataPath build.noindex test     -only-testing:'PRismTests/IdleDiffSpinProbe/idleConversation()' > /tmp/probe.log 2>&1
grep -aE "^MĚŘENÍ|^SONDA" /tmp/probe.log
```

Tři věci k tomu příkazu: prefix **`TEST_RUNNER_`** je podmínka (`xcodebuild` ostatní proměnné do
testovacího procesu nepředá), **celá suita se bere bez závorek**
(`-only-testing:PRismTests/IdleDiffSpinProbe`), a výstup se **grepuje ze souboru** — roura do
`grepu` se umí zaseknout. Log navíc obsahuje binární smetí z AppKitu, takže `grep` bez `-a`
odpoví `binary file matches` a nevypíše nic.

A tři věci k mechanice sond obecně:

- **Měřicí smyčka, která drží okno na obrazovce, musí mít strop od začátku** (#361) — ne dopsaný
  potom, co někomu sebere obrazovku. Sonda hostuje okno **na obrazovce** a nad hlavním vláknem drží
  runloop, takže scéna, která si sama říká o další kolo, aplikaci **zabije zvenčí nedosažitelně**:
  okno se nedá zavřít ani ukončit a zbývá ruční `kill` na stroji, na kterém se zrovna pracuje.
  Stalo se to u kontrolní scény `FeedbackLoopList` a je to o to nepříjemnější, že takovou smyčku
  sonda staví **schválně** — je to nástroj, ne nehoda. Pravidlo je proto tvrdé: každá zpětná vazba
  v měřicí scéně dostane **rozpočet kol** (nebo strop v čase) hned, jak se píše, a v komentáři u ní
  stojí, co tím zůstává neověřené — u rozpočtu je to kolo, které nikdy nedoběhne.
- **Pumpa, která špiní graf, musí být `Timer` na runloopu, ne `Task.sleep`.** Test drží hlavní actor
  po celou dobu (`RunLoop.run(until:)` v synchronní metodě), takže úloha se Swift concurrency se ke
  slovu nedostane — změřeno: s `Task.sleep` se graf zašpinil **nulakrát**.
- **Sonda píše do `UserDefaults` skutečné aplikace.** Testovací host **je** bundle aplikace
  (`com.ondrajodas.prism`), takže `@AppStorage` i `VisitLedger` z hostované scény míří do nastavení
  toho PRismu, který se používá. U #361 to byly návštěvy `cli/cli#13084` a `diffTreeExpanded`; nic
  z toho nevadí, ale vědět se to má.

### Dotazy na velikost líného seznamu (#361, desáté kolo)

Devátý záchvat u #361 dal poprvé zásobník hořícího kola a v něm dvojici zapisovatelů do stavu
líného seznamu (podrobnosti a čísla v [`docs/architektura.md`](architektura.md), sekce
`fillingSlot()`). Co se k tomu měří a čím:

- **`Tests/Views/LazyIdealSizeProbe.swift`** (ručně, `TEST_RUNNER_PRISM_MEASURE=1` — bez toho
  prefixu se proměnná do testovacího procesu z `xcodebuild` nedostane a suita se **tiše přeskočí**) — kolik dotazů na velikost dostane
  `ScrollView` s `LazyVStack`em na jedno rozvržení, rozepsané na `nil` (ideál), `0`/`∞` (průzkum
  pružnosti) a skutečnou velikost. Scéna je **tvaru osy konverzace** (lišta / seznam / composer
  v jednom `VStack`u), 300 řádků s hodně různými výškami a zalomeným textem. Počítá se v `Layout`u
  o jednom dítěti (`SizeQuestionReport`) — jiná cesta, jak se ze SwiftUI dozvědět „na tohle se
  někdo ptal jako na ideální rozměr“, nevede. Výsledek: **29–33 dotazů** u pružného rámce
  (přesný počet se mezi běhy o pár liší, druh dotazů ne), **4** se změřenou velikostí a **29**
  u vyplněného ideálu, což je ta zamítnutá varianta — sonda ji měří dál, aby to nebyl dohad.
- **`Tests/Views/LazyIdealSizeTests.swift`** (běží vždycky) — tvrdí to samé kvalitativně a **tím
  modifikátorem z aplikace**: s `fillingSlot()` nepřijde k línému seznamu ani `nil`, ani `∞`, ani
  jich nepřijde víc než pět. První test suity je **kontrola měřidla** (pružný rámec ty dotazy
  poslat musí) a třetí je **výčet míst** čtený ze zdrojáků, jako u `SingleWayOutTests`.
  Ověřeno **vložením regrese**: s `frame(maxWidth: .infinity, maxHeight: .infinity)` uvnitř
  `FillingSlot` spadne na `520×∞` a na počtu dotazů (6 proti 3).

Dvě věci na tom měření nejsou zjevné:

- **`nil×nil` v harnessu nepřijde ani u pružného rámce.** Scéna je rozvržená jednou a na konkrétní
  velikost, takže dotaz na ideál pošle jen okno (`fittingSize`) — sonda s oknem ho vidí 2×, test
  offscreen nikdy. Tvrdí se proto průzkum `0`/`∞`, a to je i ten důležitější z těch dvou: vyplněný
  ideál `nil` odstraní a průzkum ne.
- **Kolo samo se tím nereprodukovalo.** Nečinné okno má v obou podobách **0,000 s CPU ze 4 s**,
  a to i se 300 zalomenými řádky různých výšek. Je to tedy test **vazby**, ne test „už to netuhne“;
  to druhé se za devět záchvatů napsat nepodařilo (viz tabulky níž).

**Co se u desátého kola vylučovalo a vyšlo negativně:** `frame(in: .named(…))` nad prostorem, který
v předcích **není**. Vypadalo to na kandidáta, protože `DiffLineView` kreslí i `ThreadSnippetView`
na ose konverzace, kde `DiffView.contentSpace` nikdo nezakládá — a v hořícím kole má
`DiffLine.geometry` 711 018 zásahů při otevřené `Konverzaci`. Změřeno sondou (60 řádků, 80×
zašpiněný graf): **s prostorem i bez něj přesně 2000 výpočtů hodnoty, 0 akcí, 25 různých hodnot
a 0,072 s CPU** — tedy k nerozeznání. Chybějící prostor je proto v tom kole **následek** (rámeček
se počítá, protože se řádek přerovnává), ne jeho zdroj. Sonda se nezachovala, zůstává tenhle
odstavec.

### Odkud se ptá na velikost líného seznamu (#361, třinácté kolo)

Dvanáctý záchvat hořel na buildu **s** `fillingSlot()`, takže sekce výš popisuje **zlevnění, ne
opravu**. Co se u třináctého kola měřilo a čím:

- **`Tests/Views/LazySelfReferenceProbe.swift`** (ručně, `TEST_RUNNER_PRISM_MEASURE=1`) — čtyři
  testy, každý na jednu otázku. `stacksOnTheTimeline` bere **evaluační zásobník AttributeGraphu**
  (`GraphProbe`) z getteru identity řádku a rozdělí vzorky na to, jestli je dotaz na velikost
  seznamu vlastní **kořen** aktualizace, nebo je **vnořený** v cizí. `burnsAfterThePumpStops`
  a `burnsAfterTheDataStops` zkouší scénu tvaru **celého tabu** (hranice obsahu s `GeometryReader`em
  a předanou šířkou, uzly tvaru `ConversationNodeView` včetně linky v `background`) rozhořet a měří
  CPU **po zastavení pumpy** — první špiní rozvržení, druhý **přidává řádky**.
  `eagerLayoutCost` měří, co by stálo se líného seznamu vzdát (střídavě A/B/A/B, #274).
  Čísla jsou v [`docs/architektura.md`](architektura.md), sekce `fillingSlot()`.
- **`Tests/Views/ConversationAxisFeedbackTests.swift`** (běží vždycky) — drží **vyloučení**, ne
  opravu: v uzlu osy (`ConversationNodeView`, `ConversationEntryView`, `ThreadBubbleView`,
  `ConversationComposerView`) není `onGeometryChange`, `onContinuousHover`, `GeometryReader`,
  `ViewThatFits`, `ScrollViewReader` ani `scrollTo(`. Tvrdí se to nad zdrojáky, jako
  `SingleWayOutTests`. Smysl: to vyloučení platí jen tak dlouho, dokud v ose žádný z těch vzorů
  nepřibude — a přibýt může nevinně (odznak, který se v úzkém uzlu nevejde, si o `ViewThatFits`
  řekne sám). `ConversationView` sám `GeometryReader` **má** (je z něj `fillingSlot()`)
  a `ThreadSnippetView` kreslí `DiffLineView` s `onGeometryChange` (to je #438), takže ani jeden
  ve výčtu není.

**Pumpa musí špinit rozvržení, ne kresbu.** První podoba sondy měnila krytí a naměřila **0 dotazů
na identitu za 3 s** — líný seznam se po změně krytí nepřerovná vůbec, takže nebylo co vzorkovat.
Teprve odsazení lišty o bod dá 12 000 dotazů za 3 s.

**A třinácté kolo je třináctý a čtrnáctý neúspěšný pokus scénu rozhořet**: po zastavení pumpy
**0,000 s CPU ze 4 s** ve všech čtyřech podobách, i s 300 uzly tvaru osy a s hranicí obsahu jako
v aplikaci — a stejně tak, když pumpa místo rozvržení **přidávala řádky**.

**Ten druhý scénář je z předehry v záznamu, ne z nápadu.** Poslední tři sekundy před zdí
(`hang10-diag.log`) totiž **nejsou** zašpiněné rozvržení, ale průchod tělem **odshora**:

```
15:37:35  39 kol, 0,440 s CPU, body: ConversationNodeView=10 ConversationEntryView=8
                                     PullRequestDetailView=3 ContentView=2 ConversationView=2
                                     MarkdownText=2 ActivityFeedView=1
          graf: ConversationRow.id=60          ← ještě normální, a zásobník už má tvar kola
15:37:36  67 kol, 0,655 s CPU, body: ConversationNodeView=7 …
          graf: ConversationRow.id=66
15:37:37  33 kol, 0,573 s CPU, body: ConversationNodeView=4 ConversationEntryView=3 MarkdownText=1
          graf: ConversationRow.id=18069       ← a tady to ujede
15:37:38   0 kol, 1,054 s CPU — zeď
```

Dvě věci z toho pro čtrnácté kolo. **Ten osmirámcový zásobník je v kole i ve zdravé sekundě** (:35
a :36 ho mají a `ConversationRow.id` je 60 a 66), takže sám o sobě není příznak — patologická je
**frekvence**. A předehrou je **průchod tělem `ContentView` a `PullRequestDetailView`**, tedy změna
ve storu, ne pohyb myší: ve zdroji dění je vidět i `ActivityFeedView`, což ukazuje na tik pollingu.
Napodobit se to zatím **nepovedlo** (viz odstavec výš), ale hledat se má tam.

#### `sample` je strom, takže součet řádků není podíl

Tohle stálo celé jedno kolo, takže je to tady jako postup. `sample` vypisuje **strom volání**
a číslo na řádku je počet vzorků v tom podstromu. Z toho plynou dvě pasti:

- **`grep -c` nemluví o ceně.** „35 řádků z 21 834“ v zadání jedenáctého kola srovnávalo počet
  řádků se vzorem proti počtu **řádků souboru** a vyšlo z toho, že `measureEstimates` z hořícího
  kola zmizel. Ten jeden uzel přitom nese **1046 vzorků z 9330**, tedy 11 % — po opravě z #435
  úplně stejně jako před ní.
- **Sečíst všechny řádky se vzorem je taky špatně**: uzly se vnořují, takže se to dvojitě počítá.
  Bere se **největší nezanořený uzel** (a k němu součet sourozenců mimo jeho podstrom) proti
  **počtu vzorků hlavního vlákna** — ten je na řádku `com.apple.main-thread`.

Prakticky: najdi si řádek `Thread_… com.apple.main-thread` (to je jmenovatel), pak řádek s hledaným
jménem a jeho hloubku podle odsazení, a ověř, že nad ním v témže podstromu tentýž vzor není.

### Osa bez líného seznamu, a jak se měřila obě strany (#361, patnácté kolo)

Čtrnáctý záchvat rozhodl, **co se má udělat**; tahle sekce je o tom, čím se změřilo, **co to
stojí**. Sonda je `Tests/Views/ConversationAxisShapeProbe.swift` (ručně,
`TEST_RUNNER_PRISM_MEASURE=1`) a od `LazySelfReferenceProbe` se liší jednou věcí, na které tady
všechno stojí: **řádky jsou skutečné `ConversationNodeView`** nad skutečnými `ConversationRow`, ne
tvar uzlu. Bez markdownu, avatarů a bublin vláken vyjde cena pevného stacku **o řád níž** (32–35 ms
u syntetického `Text`u proti 413 ms u skutečné osy na 300 uzlech), takže by se rozhodovalo podle
podhodnoceného čísla.

Čtyři měření, každé na jinou otázku:

| Test | Otázka | Odpověď |
|---|---|---|
| `firstLayoutCost` | co se za to platí | 44 uzlů **55 ms** proti 5, 300 uzlů **413** proti 5, 400 uzlů **614** proti 6 |
| `scrollingCost` | co to udělá s projížděním | **0,86 / 0,85 s** CPU proti 0,31 / 0,29 s (150 × 40 pt, 300 uzlů) |
| `graphUnderTheAxis` | zmizel ten zápis do grafu | `LazySubview*` v zásobníku: `LazyVStack` **2 ze 2** vzorků, `VStack` **0** |
| `burnAfterScrolling` | nechová se pevný stack hůř | 0,00 % CPU po gestu u obou (a **nedokazuje to nic**, viz níž) |

**Vedle času se vypisuje výška obsahu a počet prvků**, a je to kontrola měřidla, ne ozdoba: pevný
stack má vyrobit **všechny** uzly (300 uzlů = 907 prvků, obsah 45 432 pt), líný jen viditelné
(22 prvků). Kdyby to vyšlo obráceně, měří se něco jiného, než co se hledá.

**Cena prvního rozvržení má strop, a ten je z dotazu.** `ConversationQuery` bere `first: 100` ze
čtyř seznamů a **nestránkuje**, takže osa má nejvýš čtyři stovky uzlů. Testuje se to
(`ConversationAxisEagerTests.theAxisIsBounded`) **z plných stránek**, ne z konstanty — kdyby
`Policy.overview` začal skládat víc položek, než kolik jich přišlo, číslo by se rozešlo potichu.

**`List` je v sondě schválně, i když v repu není.** Čísla má lákavá (první rozvržení 78–112 ms bez
ohledu na počet, `LazySubview*` nula), ale výška obsahu je u něj **odhad** — 44 uzlů 4 876 pt proti
6 745 u `VStack`u, 300 uzlů 11 020 proti 45 432 —, takže posuvník lže a poloha při projíždění skáče.
A **naše gesto s ním nepohne vůbec** (`dojelo na 0` z obsahu 10 845), takže se cena projíždění
změřit nedá; „je levnější“ se proto tvrdit nesmí. Zůstává jako měřená varianta pro případ, že by
cena prvního rozvržení začala vadit.

**Materiál je na jednom místě** (`Tests/Support/ConversationFixture.swift`): pět tvarů textu po
`index % 5` (věta, šest odstavců, blok kódu, odrážky, odstavce s odkazem). Měří z něj i
`IdleDiffSpinProbe`, takže se čísla obou sond dají číst vedle sebe; do patnáctého kola to byl
privátní helper uvnitř jedné z nich a druhá kopie by se rozešla první úpravou.

**Čeho se ta sonda nedotkne: záchvatu.** Kolo se nepovedlo vyrobit ani počtrnáct, takže „po opravě
nehořelo“ tady nikde nestojí a stát nesmí. Ověřitelné je jen to strukturální (řádek
`graphUnderTheAxis`) a **provozní**: používat aplikaci s `./bin/run.sh --diagnose` a koukat na řádek
`HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU` v `<cache>/diagnostics.log`. Kdyby přišel další záchvat
nad **Konverzací**, je to doklad, že se ta úvaha mýlila; nad **Soubory** ne — tam líný seznam
tehdy zůstal (řádků jsou tisíce) a tatáž třída kola se tam vrátit může.

**A vrátila se — přesně tam** (#469, záchvat 27. 8.). Věta o odstavec výš byla napsaná jako
výhrada a stala se z ní předpověď: dva `sample`y z hořící instance měly `LazySubviewPlacements`
na 25 % vzorků hlavního vlákna, `FileDiff.diagnosedID` i `DiffRow.diagnosedID` v zásobníku
a **nula** `ConversationRow`. Jak se to změřilo a co z toho vyšlo, je v sekci níž.

### Diff bez líného seznamu (#469)

Sonda je `Tests/Views/DiffShapeProbe.swift` (ručně, `TEST_RUNNER_PRISM_MEASURE=1`), sestra
`ConversationAxisShapeProbe` — a stejně jako ona kreslí **skutečné `DiffRowView`** nad
rozparsovaným diffem, tedy včetně `NSTextView` v každém bloku. Materiál je skutečná fixture
(`gh/pr-diff-ordinary.diff`) doplněná syntetickými soubory na požadovaný počet řádků
(`DiffMaterial`, sdílené s `DiffWindowRenderProbe`).

Poměřuje **pět podob**, a tři z nich jsou **ablace**, ne varianty k nasazení — bez nich by z čísel
nebylo poznat, za co se platí:

| Podoba | Co to je |
|---|---|
| `LazyVStack` | podoba do #469 (sekce a `pinnedViews`) |
| `VStack` s oknem | podoba od #469 — pás kolem výřezu se zapíná **jediným modifikátorem** (výřez v prostředí), takže se ablace liší od aplikace právě tím jedním rozhodnutím |
| `VStack` se všemi bloky | ablace: co by pevný stack stál bez okna |
| `VStack` bez bloků | ablace: co stojí sám seznam, když v něm nevisí `NSTextView` |
| `VStack` bez bloků a bez ukotvení | ablace: co z toho patří ukotvené hlavičce |

Čísla a to, co z nich plyne, jsou v [`docs/architektura.md`](architektura.md#pevný-seznam-a-nasazování-bloků-469).
Tady zůstává **to, na co se u toho měření naráží**:

- **Nejdřív se měřila cena, kterou v aplikaci nikdo neplatí** (#275 doslova). První podoba sondy
  neměla pojmenovaný souřadnicový prostor obsahu, takže `onGeometryChange` v blocích četlo rámečky
  v prostoru, který se scrollováním hýbe. Vyšlo z toho 6,4 s CPU u pevného stacku — a po doplnění
  prostoru **6,3 s**, takže to tentokrát nebyla ta příčina. Zůstává z toho pravidlo, ne nález:
  **sonda musí mít tvar aplikace, i když se to zrovna neprojeví**.
- **Hák sondy patří na řádek, ne na soubor.** `GraphStackCollector` bere vzorek každého dvoustého
  dotazu na identitu; souborů je pár desítek, takže s hákem na `FileDiff` vyšlo **0 vzorků** a sonda
  tvrdila „bez `LazySubview*`“ i o líném seznamu. S hákem na `DiffRow` je to 478 dotazů a 2 vzorky,
  **oba** s `LazySubviewPlacements`.
- **Zamčená obrazovka měření zabije, a pozná se to na jednom čísle.** Okno mimo obrazovku (a stejně
  tak okno pod zamčenou obrazovkou) nedostane takt překreslování, takže gesto kolečkem **nikam
  neposune**: ve výpisu je `dojelo na -32` místo `dojelo na 5968` a všechny podoby vyjdou shodně na
  0,03 s CPU. To číslo je v sondě právě proto — bez něj by z toho byla tabulka, ve které se všechno
  vyrovnalo. `caffeinate -u` obrazovku **probudí jen někdy** a `caffeinate -d` už uspanou
  neprobudí; spolehlivé je zkontrolovat `dojelo na …` a měření zahodit, když je záporné.
- **Sériím se pořád střídá A/B/A/B** (#274). Drift sezení je i tady větší než hledaný rozdíl:
  tatáž podoba vyšla v jednom sezení 3,08 s a v jiném 4,47 s.

Od #472 má sonda **pátou otázku** — `relayoutCost`, tedy co stojí **přerovnání shora**: tělo detailu
se překládá při každém průchodu tělem `ContentView`, ne jen při scrollování, a #469 to neměřilo.
Vyšlo, že pevný stack je i tady dražší, ale **málo**: 6000 řádků, 3 ms na přerovnání u líného
seznamu proti **9 ms** u pevného s oknem (500 řádků: 4 proti 4). Kvůli té páté otázce jde každá
scéna přes `DiffRelayoutHost`, tedy o jeden `View` víc — čísla z #469 se tím mohou o kousek posunout,
poměry mezi podobami ne.

**Jak diff vypadá**, se ověřuje `DiffWindowRenderProbe` (ručně, `TEST_RUNNER_PRISM_MEASURE=1`
a `TEST_RUNNER_PRISM_RENDER_DIR`): renderuje **skutečný `DiffView`** v obou pohledech na třech
polohách výřezu (vršek, prostředek, konec) do PNG — z okna mimo obrazovku přes `cacheDisplay`,
protože blok kódu je AppKitové view a `ImageRenderer` na něj nedosáhne. Odpovídá na čtyři otázky,
které se rozbijí potichu: zůstal diff **celý** (rezervovaná výška se nesmí lišit od skutečné),
drží se **hlavička souboru** nahoře, **vysune se** na konci svého souboru a platí obojí i v pohledu
**vedle sebe**. Vedle obrázků vypisuje výšku obsahu a **počet bloků kódu v okně** — bez toho čísla
by render nad prázdným oknem vypadal stejně jako render nad rozbitým.

### Projíždění kolečkem, a co z něj u #361 vyšlo (#361)

**`scroll(to:)` kolo z #361 nerozjede, a je to změřené** (1,28 s proti 1,30 s u #375, tedy nic).
Pro `NSScrollView` je programový posun obyčejná změna počátku: neproběhne **živé scrollování**,
nepošlou se `willStartLiveScroll`/`didLiveScroll`/`didEndLiveScroll`, nezapne se setrvačnost —
a zrovna na tom visí `LazyLayoutViewCache`, který si při scrollování říká o předběžné načtení
(`signalPrefetch` je jediný re-arm v obou vzorcích z 2026-08-18).

Gesto se proto skládá jako skutečné události a **je na to jedno místo**:
[`Tests/Support/WheelGesture.swift`](../Tests/Support/WheelGesture.swift). Tři věci, bez kterých
z toho nic není:

- **Událost se scroll view předává přímo** (`scrollWheel(with:)`). `CGEvent.post` ani `postToPid`
  se do procesu nedoručí (změřeno u #252, selže **potichu**) a skutečnou myš si sonda brát nesmí.
- **Musí to vypadat jako trackpad**, ne jako kolečko myši: `scrollWheelEventIsContinuous`, fáze
  (`began`/`changed`/`ended`) a po nich **setrvačnost** (`momentumPhase`). Bez fáze `NSScrollView`
  živé scrollování nezačne.
- **Kolo runloopu po každé události.** Bez něj se rozvržení odloží a naměří se jedno přerovnání
  místo všech (tatáž past jako hustota kroků u #252).

Rozhodující číslo z toho **není cena gesta, ale úseky po něm**: cena projíždění se dá utratit,
kolo ne — ztuhlá instance hořela šest hodin po tom, co od ní člověk odešel. Naměřeno na okně
1512×874:

| Scénář | Před gestem | Gesto (60 × 40 pt) | Po gestu, tři úseky po 3 s |
|---|---|---|---|
| konverzace (fixture, 44 položek, obsah 9 340) | 0,01 % | 0,35 s | 0,17 / 0,01 / 0,00 % |
| dlouhá osa (300 komentářů, obsah 49 550) | 0,00 % | 0,14 s | 0,23 / 0,00 / 0,00 % |
| diff (23 710) | 0,01 % | 0,27 s | 0,25 / 0,01 / 0,00 % |

**Kolo se tedy nechytlo ani kolečkem.** Vylučuje to spolu s tabulkami výš i hypotézu, se kterou se
do toho šlo — že ho zavírá `ForEach(Array(nodes.enumerated()), id: \.element.id)`: ten vzor byl
v `ConversationView` po celou dobu těch měření a osa se přesto usadila. Zbylé dvě věci, které se
u toho srovnaly, aby to nula netvrdila zbytečně:

- **Okno se staví jako `WindowGroup`**, ne přes `NSHostingController` s předepsaným rozměrem.
  Aplikace má `.windowResizability(.contentMinSize)`, takže si AppKit při každém průchodu
  `updateConstraints` říká o `minSize` a hostující vrstva na to spustí `_sizeThatFits` — **druhou
  aktualizaci grafu na jiné nabídce rozměru**. Předepsaný `frame` tu mašinerii zmrazí. Rozměr
  proto předepisuje **okno** (`NSHostingView` + `sizingOptions = [.minSize]`), ne obsah; obsah si
  ho určovat nesmí, jinak se okno scvrkne na hlavičku (past ze `show(store:full:)`).
- **Dlouhá osa s různě vysokými uzly.** Fixture z `cli/cli` má 44 položek; syntetická osa jich má
  300 a pět různých tvarů textu (věta, odstavce, blok kódu, odrážky), protože líný seznam odhaduje
  zbytek obsahu z už umístěných řádků — stejně vysoké řádky by mu odhadem nepohnuly. Razítko
  `updatedAt` u ní **musí být to z fixture PR**, jinak si detail konverzaci při zobrazení natáhne
  znovu a sonda měří prázdno.

**A nula z té sondy je od #361 ověřená z druhé strany** (`loopControl` + `FeedbackLoopList`):
kontrolní scéna, ve které řádek zapisuje do stavu výšku, kterou tím sám změní, dá **32,05 % CPU**
v prvním úseku a **0,00 %** v dalších, jak jí dojde rozpočet kol. Měřidlo tedy kolo rozvržení
**vidí**. Dvě věci k té kontrole, obojí zaplacené:

- **Zpětná vazba musí být ohraničená rozpočtem.** První verze rozpočet neměla a okno sondy se
  nedalo zavřít ani ukončit — musela ho zabít ruka u stroje, na kterém se zrovna pracovalo.
  Ověřené tím tedy **není** kolo, které nikdy nedoběhne, jen kolo jako jev.
- **Kontrolní scéna nesmí mít `sizingOptions = [.minSize]`.** Oscilace se celá vejde do dotazu na
  minimum okna a AppKit ji zabije výjimkou (`needing another Update Constraints in Window pass …
  more than there are views`) dřív, než se dá cokoli změřit. Kolo hledané v aplikaci se naproti
  tomu roztáhne přes kola runloopu a proces jen hoří.

**Cena identity řádků osy se měří zvlášť** (`ConversationIdentityMeasurement`), protože v okně ji
drift sezení přebije: 300 řádků, přečtení identity jednou za přerovnání obsahu vyšlo **0,141 ms**
přes tuple a keypath a **0,036 ms** z uloženého pole; složení řádků v průchodu tělem je naopak
o 0,086 ms dražší (0,179 → 0,265 ms). Obě strany měřidla přitom **musí obsahovat**
`Policy.conversation` — bez ní by z toho vyšlo, že řádky jsou pětkrát dražší, což je artefakt
měřidla, ne cena změny.

**Co zbývá:** dohledat, co graf špiní. Vylučovací práce hotová: animace, timer, vnější pohon, přeměření
textu, náš `onContinuousHover`, akce `onGeometryChange`, hover zápis pod kurzorem, scéna sama,
projíždění kolečkem se setrvačností a `ForEach` nad polem tuplů. **Úplný seznam po čtvrtém kole**
je níž, v sekci *Čtvrtý záchvat*.

Nejsilnější zbylá nitka je **re-arm `NSHostingView.requestUpdate(after:)`**, ke kterému se ve vzorcích
dostane `LazyLayoutViewCache.signalPrefetch()` — a při stavbě sondy se ukázal i druhý volající, ze
zásobníku té AppKitové výjimky: `ViewGraph.invalidateTransform()` → `graphDidChange()`. Ta druhá cesta
je zajímavá tím, že si o další kolo říká, když se **transformace během aktualizace grafu změnila** —
a jediné, co v aplikaci transformace vyžaduje, je čtení **pojmenovaného** souřadnicového prostoru
(`frame(in: .named(DiffView.contentSpace))` ve třech místech seznamu řádků). V sondě se to nechytlo,
takže je to hypotéza; ověřit ji jde jedině na živém okně — dočasně přepnout ta čtení na `.local`
a nechat okno stát hodiny.

**Čtyři vzorky ze tří záchvatů, a co z nich vypadlo natrvalo.** Třetí záchvat (2026-08-18
odpoledne) přišel při **projíždění konverzace** na buildu `ecf48a0`, tedy s opravou #375:

| | 2026-08-17 | 2026-08-18 dopoledne | 2026-08-18 odpoledne |
|---|---|---|---|
| transakční kolo z vzorků hlavního vlákna | 1818/1992, 3279/3593 | 1957/1968, 3912/3924 | **3944/3965 (99 %)** |
| `enqueueHoverUpdateIfNeeded` | 153 / 271 | **0** | **0** |
| poloha kurzoru | nad blokem kódu | **mimo okno** | **uvnitř okna** (751, 709 zhora, nad osou) |
| jediný re-arm v `dispatchActions` | hover + `signalPrefetch` | `signalPrefetch` | **`signalPrefetch`** (všech 15 vzorků podstromu) |

Dvě věci jsou tím **uzavřené**: **hover je vyloučený nadvakrát** (dopoledne kurzor mimo okno,
odpoledne uvnitř — a v obou nula, takže varianta z hlavičky #361 je jiná příčina se stejným kořenem)
a **oprava #375 na tom nezměnila nic**, protože odpolední vzorky jsou z buildu, který ji má.

**Číslo k té nitce z 2026-08-18**: v podstromu transakce drží `SecondaryLayerGeometryQuery.value` →
`ViewDimensions.subscript` → `LayoutEngineBox.explicitAlignment` **517 z 3 924** vzorků hlavního
vlákna, tedy 13 %. Explicitní zarovnání si v aplikaci vyžaduje `HStack(alignment: .firstTextBaseline)`
(devět míst, z toho odrážky markdownu), pojmenovaný prostor ta tři čtení v seznamu řádků. Je to
**cena uvnitř kola, ne doklad pohonu** — sama by se v nečinném okně nezaplatila.

Příští záchvat se proto vzorkuje **dřív, než se aplikace zavře** (`sample <pid> 5 -file …`), přečte se
u toho **kde ležel kurzor** (`swift mouse.swift`) a v podstromu `Update.dispatchActions()` se hledá
**jakýkoli rámec aplikace** — jeho přítomnost nebo nepřítomnost rozhoduje, jestli se hledá dál v našem
kódu, nebo v tom, co si SwiftUI plánuje samo.

### Ablace na `explicitAlignment` a životnost `DiffView` (#361)

Třetí kolo hledání u #361. Vyšlo **negativně** a je to zapsané proto, aby se to nezkoušelo znovu
od nuly.

**`DiffView` pod záložkou `Konverzace` v hierarchii nezůstává.** Byla to nejsilnější zbylá
hypotéza — kdyby zůstával, běžely by dál jeho `onGeometryChange` nad **pojmenovaným** prostorem
(`DiffView.contentSpace`, tři místa v seznamu řádků) a `DragGesture(coordinateSpace: .named(…))`,
což by vysvětlovalo, proč se kolo nad **čistou** konverzací nedaří vyrobit. Změřeno sondou
`diffLivenessUnderConversation` ze dvou stran, nad PR, které **má načtený diff** (tedy ve stavu, ve
kterém uživatel doopravdy je — prohlíží diff a pak přepne na osu):

| Vybraná záložka | AppKitová view z diffu v okně | Průchody `body` při projíždění osy |
|---|---|---|
| Změněné soubory | **9** bloků kódu, 185 prvků | — |
| Konverzace (diff pořád ve storu) | **0** bloků kódu, 162 prvků | `ConversationEntryView` 10, `ConversationNodeView` 10, `MarkdownText` 5, **`DiffView` 0, `DiffRowView` 0** |

Ta nula v pravém sloupci je to rozhodující: v úseku, kdy se osou projíždí a líný seznam přerovnává,
se tělo `DiffView` ani `DiffRowView` **nepřeloží ani jednou**. `switch tab` v `PullRequestDetailView.content`
tedy podstrom diffu doopravdy zahazuje a **pojmenovaný souřadnicový prostor je z podezřelých venku**.
Sedí to i na vzorky ze ztuhlé aplikace: řetězec `DiffView` ani `contentSpace` v nich není **ani
jednou** (`grep -c` nad všemi čtyřmi: 0/0/0/0).

**Ablace `explicitAlignment` číslo nesundala.** Postup je odebírání, ne přidávání: vzít osu se 300
komentáři, projet ji kolečkem a odebírat po jednom. Měří se **CPU hlavního vlákna za gesto** a série
se **střídají** (#274), protože drift sezení je větší než hledaný rozdíl:

| Varianta | kolo 2 | kolo 3 | po gestu |
|---|---|---|---|
| beze změny | 1,46 s | 1,44 s | 0,00 % |
| odrážky markdownu `.top` místo `.firstTextBaseline` (`MarkdownText.swift:133`) | 2,20 s¹ | **1,37 s** | 0,00 % |
| uzel osy bez `.background(alignment: .topLeading) { line }` | 1,92 s¹ | **1,42 s** | 0,00 % |
| markdown úplně (holý `Text` místo bloků) | 1,22 s | **1,18 s** | 0,00 % |

¹ Kolo 2 bylo u dvou variant zašpiněné cizí zátěží — sonda to sama hlásí řádkem „před gestem“, který
u té první vyšel **5,58 %** místo 0,01 %. Bez toho řádku by z čísel vyšlo, že baseline zarovnání
projíždění **prodražuje**, a hledalo by se dál v úplně opačném směru.

Co z toho plyne:

- **Baseline zarovnání v odrážkách markdownu to není** (1,37 proti 1,44 s, tedy v šumu), a **není to
  ani pozadí uzlu osy** (1,42 s) — přitom právě to pozadí je ten `SecondaryLayerGeometryQuery`
  z profilu: `background(alignment:)` si vyžádá `ViewDimensions[.top]` a `[.leading]` na primární
  vrstvě, což je `_HStackLayout`, a ten na to **umístí všechny své děti** (v profilu
  `StackLayout.UnmanagedImplementation.placeChildren` → `sizeChildrenGenerally…` → vnořené
  `_PaddingLayout`/`_FrameLayout`, 449 z 3 585 vzorků).
- **Markdown celý ubere 18 %**, ale to není nález: odebere se tím **veškerý obsah** každého uzlu
  a zmateralizuje se jiný počet řádků (256 proti 280), takže to není srovnání téhož.
- **Žádná varianta po gestu nehoří** (0,00 % ve všech třech úsecích). `explicitAlignment` je tedy
  **cena uvnitř cizího kola, ne to kolo** — potvrzuje to, co se o něm psalo u předchozího kola.

**`SinceLastVisitView` v ose vůbec není** — ta varianta se proto neměřila. Sedí v `OverviewView`
(záložka `Přehled`); značka „od minule“ **v ose** je `SinceMarker` uvnitř `ConversationView` a ta
baseline zarovnání nemá (`HStack(spacing: 8)`). Kdo tu variantu bude chtít zkusit znovu, ať napřed
`grep`ne, kde ten typ doopravdy žije.

**Šedesát kroků po čtyřiceti bodech je na ablaci málo, a je to změřené.** V prvním kole (60 × 40 pt,
2 400 z 43 000 bodů obsahu) vyšly všechny čtyři varianty **0,14 / 0,14 / 0,14 / 0,12 s** — tedy
nerozlišitelně, protože se zmaterializuje 17 řádků a rozdíl se v tom utopí. Scénář na ablaci proto
projíždí **celý** obsah (`wheelWholeConversation`, 300 × 140 pt, 280 řádků), takže se každý uzel
jednou umístí a rozdíl má z čeho vyjít.

**Nový výpis sondy: průchody `body` po typech.** `measureWheel` od #361 zapíná vlastní instanci
`RenderDiagnostics` (ne tu z aplikace — globální `shared` píše do **skutečné** cache, protože
testovací host má `CFBundleName` hlavní instance) a po každém úseku vypíše počitadla. Je to jediné
číslo, ze kterého se pozná rozdíl mezi „scéna se usadila“ a „scéna se překresluje, jen levně“ —
`0,00 % CPU` samo o sobě obojí neodliší.

### Čtvrtý záchvat: co říká třicetisekundový vzorek a dvě nové vyloučené věci (#361)

Čtvrté kolo. Přineslo **jednu opravu nástroje** (diagnostika psala jen do chvíle ztuhnutí, viz
`architektura.md`) a **dva negativní výsledky**; pohon se nenašel ani tentokrát.

**Vzorky:** dva třicetisekundové (24 050 a 24 195 vzorků hlavního vlákna) z ztuhlého hlavního okna
na buildu `3737c29`. Signatura je čtvrtá stejná: transakční kolo **23 967 z 24 050 (99,7 %)**,
`enqueueHoverUpdateIfNeeded` **0** (a myš přitom **uvnitř** okna), animace/timer/dispatch main queue
0, jediný re-arm `signalPrefetch`. Podíly z 20 476 vzorků `UpdateStack::update`:
`LazySubviewPlacements.updateValue` 3 284 + 3 048, **`SecondaryLayerGeometryQuery.value.getter`
3 974**, `UnaryChildGeometry.value.getter` 3 176, `DynamicBody.updateValue` 605,
`ViewListTransition.updateValue` 558.

**Čí je ten `SecondaryLayerGeometryQuery`: `.background(alignment: .topLeading) { line }` v uzlu
osy** (`ConversationNodeView.swift:34`, přišlo s opravou #375). Ze vzorku se to pozná bez hádání —
celý řetězec je v něm rozepsaný: `SecondaryLayerGeometryQuery.value` → `ViewDimensions.subscript`
→ `LayoutEngineBox.explicitAlignment` → `ViewLayoutEngine.explicitAlignment` → **`conformance
_HStackLayout`** → `StackLayout.UnmanagedImplementation.placeChildren` →
`sizeChildrenGenerallyWithConcreteMajorProposal` → `_PaddingLayout`/`_FrameLayout` a dál dolů. Je to
tedy **`HStack`**, ne `VStack`, takže z těch dvou míst s explicitním zarovnáním v ose sedí jen tohle;
druhé (`.overlay(alignment: .leading)` na kartě v `ConversationEntryView.swift:220`) je na `VStack`u
a ve vzorku není. **Mechanika:** aby SwiftUI zjistil, kde je u `HStack`u vodicí čára `.top`
a `.leading`, musí **umístit všechny jeho děti** — tedy druhé plné rozvržení řádku **na každý
dotaz**. V nečinném okně se zaplatí jednou a graf si to podrží; v tom kole se to počítá znovu
a znovu, odtud **16,5 %** celého hoření (u vzorku z 2026-08-18 to bylo 13 %).

**Zůstává to tam, a je to rozhodnutí, ne opomenutí.** Ablace u #386 tu variantu **změřila**
(1,42 s proti 1,44 s beze změny, tabulka výš), takže na projíždění se ta cena neprojeví vůbec —
a pravidlo z #275 říká, že zlevnění, které se nedá změřit na té cestě, kterou kód doopravdy jde, se
nevydává za zlevnění. Odebrat to navíc znamená odebrat **linku osy**, tedy vzhled; jiná forma
(pozadí bez explicitního zarovnání, `ZStack`) by se musela měřit v kole, které jede, a to zatím
není. Zapsáno proto jako **cena uvnitř cizího kola**, s mechanikou výš, ať se nehledá znovu.

**`FillingWidth` v ose šířku nevyjednává** — a taky to není odhad ze čtení kódu, je to ve vzorku
vidět: v řetězci explicitního zarovnání stojí **`_FrameLayout`** (to je `frame(width:)`), ne
`_FlexFrameLayout` (`frame(maxWidth:)`). Uzel osy tedy bere tu větev `FillingWidth`, ve které
`availableWidth` z environmentu **je** — nastavuje ho `GeometryReader` na hranici tabu
(`PullRequestDetailView.swift:401`) —, takže se šířka **předává, ne vyjednává** (#220 platí).
`_FlexFrameLayout` ve vzorku je jen výš, na ploše tabu (`timeline.frame(maxWidth:.infinity,
maxHeight:.infinity)`), což je jedna úroveň, ne řetěz. Ve kole se `FillingWidth` objevuje pouze jako
**přečtení jeho `@Environment`** (`DynamicBody.updateValue` → `_DynamicPropertyBuffer.update`):
`initializeWithCopy for FillingWidth` 14 + 9 vzorků, tedy 0,1 %.

**`ConversationRow` se v kole kopíruje, ale nic se z něj nepočítá.** Kopie visí pod
`ForEachState.item(at:offset:)` → `ForEach.IDGenerator.makeID` → `Array.subscript.read`, tedy pod
**přečtením identity** — líný seznam se na ni ptá při každém přerovnání a `Array.subscript.read`
z toho udělá kopii celé struktury včetně payloadu enumu. Je to **cena průchodu**, ne vstup rozvržení:
75 + 35 vzorků, **0,46 %**. Zlevnit by to šlo boxem (`final class` uvnitř řádku), ale ta cena se tím
jen přestěhuje — alokace na řádek při **každém** průchodu tělem `ConversationView` proti kopii při
každém dotazu na identitu —, takže se to nedělá bez čísla z kola, které jede.

**Nové vyloučené věci.** Obě mají scénář v `IdleDiffSpinProbe` a obě vyšly negativně:

| Hypotéza | Čím se zkoušela | Cena samotné změny | Po ní, tři úseky po 3 s |
|---|---|---|---|
| obsah se **zkrátí** pod odscrollovaným seznamem (prefetch chce pásmo, které neexistuje) | osa 300 → 40 komentářů u dna (obsah 48 417 → 6 515) | 4,48 % v prvním úseku | 0,01 / 0,00 % |
| totéž v prostředku osy | 300 → 40, dojeto na 8 400 | 4,27 % | 0,00 / 0,00 % |
| obsah se **prodlouží** | 300 → 600 u dna | 5,30 % | 0,01 / 0,00 % |
| **týž počet, jiné výšky** (rozejde se odhad zbytku obsahu) | 300 → 300 s posunutými tvary | 5,48 % | 0,01 / 0,00 % |
| **tažení za hranu okna** nad osou (`minSize` → `_sizeThatFits` → `invalidateTransform` z #363) | 20 kroků po 24 pt, kolo runloopu po každém | 1,82 s CPU za tažení | 0,00 / 0,01 / 0,00 % |
| totéž nad diffem (kontrola) | dtto | 2,10 s | 0,02 / 0,00 / 0,00 % |

První hypotéza měla proti sobě mechaniku, která je vidět až z čísel sondy: **`NSScrollView` počátek
sám usekne** (obsah 6 515, výřez 5 828), takže výřez za koncem obsahu nevydrží ani do dalšího kola
a prefetch nemá co chtít. Druhá vyřizuje tu nitku z #363: cesta `updateConstraints → minSize →
_sizeThatFits` se tažením za hranu doopravdy vytíží (1,82 s CPU), ale po tažení se okno usadí.

**Vylučovací seznam po čtvrtém kole:** animace, timer, vnější pohon, přeměření textu,
`onContinuousHover`, akce `onGeometryChange`, hover zápis pod kurzorem, scéna sama, projíždění
kolečkem se setrvačností, okno s minimem z obsahu, dlouhá osa s různě vysokými uzly, `ForEach` nad
polem tuplů, životnost `DiffView` pod osou, baseline zarovnání v markdownu, pozadí uzlu osy,
**přesázení osy pod odscrollovaným seznamem** a **tažení za hranu okna**.

**Co zbývá:** pořád totéž — proč `signalPrefetch` nekonverguje. Nově se k tomu ví, že se to celé
odehrává **uvnitř jednoho `flushTransactions`** (proto se runloop nevrátí a proto se diagnostika
musela přestěhovat na vlastní vlákno) a že se v tom kole **nepřeloží ani jedno tělo** aplikace
(`MarkdownText` a `DiffRowView` mají ve vzorku nulu), takže se ani nemateralizují nové řádky —
je to čistě přepočítávání geometrie nad **nezměněnou** sadou podviews. Příští záchvat proto konečně
dá i **záznam z průběhu**: řádky `0 kol runloopu … NEPUSTILO RUNLOOP KE SLOVU` s počty průchodů tělem, ze kterých se
pozná, jestli se v tom kole něco překresluje, nebo se jen počítá rozvržení.

### Pátý záchvat: práce uvnitř kola, a jak se ověří, že se přestala dělat (#393)

Pátý záchvat (2026-08-20, build `31bccbc`) má **stejný kořen** jako čtyři předchozí — transakční
kolo, **19 116 z 21 240** vzorků v `flushObservers → beginTransaction → flushTransactions` — ale
poprvé je v něm vidět **náš kód**, a to ve dvou vzorcích (30 s / 21 240 vzorků a 20 s / 15 339):

| Rámec | Vzorek 1 | Vzorek 2 |
|---|---|---|
| `updateNSView` → `DiffPairBlockView` | **1 172 (5,5 %)** | **849 (5,5 %)** |
| z toho `DiffPairBlockContainer.show(…)` | 724 | 545 |
| `LazySubviewPlacements.updateValue` | 6 759 | 4 933 |

**Dvě věci se u pátého záchvatu čtou jinak, než jak byly zapsané v zadání #393.**

1. **Hover re-arm je zpátky, a je to jediný re-arm, který v tomhle záchvatu něco váží.**
   `Update.dispatchActions()` má 2 119 vzorků a z toho **2 065** je
   `EventBindingManager.enqueueHoverUpdateIfNeeded()` (ve druhém vzorku 1 440 z 1 486);
   `signalPrefetch` má 54 a 45. Je to tedy **první** varianta z #361 (kolo layout ↔ hover re-arm),
   ne ta se `signalPrefetch`em. V zadání stálo, že je hover zanedbatelný — to číslo ale bylo
   **počet řádků grepu**, ne počet vzorků, a `grep -c` na tomhle vyjde 2, protože všechny vzorky
   sedí na jednom řádku výpisu. **Sample se čte po podílech, ne po řádcích** (pravidlo z #350).
2. **Náš kód je v tom kole pořád jen 5,5 %.** Zbytek je přepočet geometrie líného seznamu, takže
   oprava práce uvnitř kola je **zlevnění obsahu, ne zastavení kola** — z 5,5 % se 99 % neposkládá.
   Platí u toho i to, že hover podstrom naši closure **neobsahuje**: z 2 065 vzorků je 10 rámců
   aplikace (kopie hodnoty representable), zbytek hit-test responderů, tedy stejně jako u #361.

#### Barva obyčejného textu: co bylo změřené a proč render přestal být identický

Při pauze nad slotovou aplikací se v tmavém režimu ukázalo, že **identifikátory jsou skoro
nečitelné** — a je to vada stará, ne z #393: obyčejný text neměl v atributovaném řetězci
`.foregroundColor` vůbec, což TextKit kreslí **černě**. Klíčová slova, řetězce a čísla svoji barvu
měly, takže to vypadalo jako vlastnost tématu.

**Změřeno ze tří stran, ne odhadnuto:**

1. **Atribut**: `DiffTextView.compose` vydal na `return Version20260729;` dva úseky —
   `„return“ → sRGB 0.8/0.471/0.196` (oranžová Darculy) a `„ Version20260729;“ → BEZ BARVY`.
2. **Nakreslený pixel** (blok v `darkAqua`, vzorek přes prostřední řádku textu, `--add-bg` pozadí):
   před opravou nejtmavší pixel **0,000/0,000/0,000**, tedy černý glyf; po ní nejsvětlejší
   **0,905/0,919/0,950**, což je přesně `--ink` (`#E7EAF2`).
3. **WCAG kontrast** (spočítaný, obě větve palety, všechna pozadí, na kterých kód leží):

   | pozadí řádku | světlý: černá → `ink` | tmavý: černá → `ink` |
   |---|---|---|
   | kontext (`surface`) | 21,00 → 17,90 | **1,14 → 15,31** |
   | přidaný (`diffAdded`) | 19,23 → 16,39 | **1,39 → 12,55** |
   | odebraný (`diffRemoved`) | 18,31 → 15,61 | **1,26 → 13,89** |
   | word-level přidaný | 15,84 → 13,50 | **2,41 → 7,24** |
   | word-level odebraný | 14,42 → 12,29 | **1,99 → 8,77** |

**Co z toho platí pro testy.** `DiffPaletteTests` ten kontrast měřily celou dobu (`ink` nad oběma
druhy řádku, práh 10) a **procházely** — jenže měřily **token z palety**, ne to, co se kreslí. Že
se barva doopravdy nasadí, tvrdí od #393 `DiffBlockCompositionTests` („žádný znak nezůstane bez
barvy“, „obyčejný text má barvu textu z palety“) a totéž pro sheet s hunkem
(`SelectableCodeTextTests`). Vloženou regresí ověřeno: bez té barvy padnou **tři** tvrzení
(nezabarvené úseky, prázdná sada barev u souboru bez jazyka, chybějící inkoust na identifikátoru).

Tvrzení „bez jazyka se nic neobarví“ se tím **přepsalo** — bylo správné o obarvení a špatné
o kresbě; text bez barvy vyjde černý, takže soubor, kterému `Language` nerozumí, byl v tmavém
režimu celý černý na tmavém.

**Render tím přestal být identický, a to schválně.** Sonda proto od #393 kreslí **oba motivy** a motiv
si **předepisuje** (`window.appearance`, `hosting.appearance` a `performAsCurrentDrawingAppearance`
kolem kresby) — bez toho kreslí v tom, co má zrovna stroj, a dva běhy pár hodin od sebe se liší
motivem, ne kódem. Stalo se to u #393: snímek z 15:55 vyšel světlý a z 21:05 tmavý, takže první
srovnání po bytech netvrdilo nic. S předepsaným motivem se z osmi snímků liší **šest**; identické
zůstaly `pod-sebou-*-648`, protože v nejužší šířce se v pohledu pod sebou kód nevykreslí vůbec —
což je zároveň kontrola, že se změnilo právě to písmo.

#### Čím se ověřuje, že se ta práce přestala dělat

**Počítadly v blocích, ne dojmem.** Blok drží tři čísla (`DiffTextView.updates`, `mounts`,
`typesettings`; u dvojice `DiffPairBlockContainer.updates`, `mounts` a součet sazeb za sloupce)
a čtou je `DiffBlockUpdateTests` i sonda projíždění. Bez `updates` by ta ostatní netvrdila nic:
nula u nasazení znamená stejně dobře drženou stráž jako scénu, ve které se nic nedělo.

**Sazba není to, co se opakovalo.** `DiffTextView.show(…)` se za podpisem obsahu vracela už před
#393, takže „nesází se znovu“ platilo i tehdy. Co se opakovalo, bylo **nasazení** — a `typesettings`
se proto v testech hlídá jako **nezměněná vlastnost**: po změně šířky se sázet **nesmí** (přesázení
ruší rozdělaný výběr, #157), po změně jazyka a režimu **musí**.

**`bounds` v `updateNSView` je o průchod pozadu** — změřeno u #393, ne odhadnuto: první průchod
vidí šířku **nula** a ten druhý tu skutečnou (SwiftUI nastaví rámec view až po něm). Scéna se proto
v testu nechá **dojet**, dokud nasazení nepřestanou přibývat; bez toho by baseline nesla stav se
šířkou nula a druhé (správné) nasazení by vypadalo jako porušená stráž.

**Regrese vložená z obou stran** (pravidlo „regrese se ověřuje vložením regrese“):

| Vložená chyba | Co spadne |
|---|---|
| stráž vypnutá (`guard` zahozený v obou views) | `Nezměněná dvojice se znovu nenasazuje ani nesází` — 11 nasazení na 11 aktualizací proti jednomu, a totéž v pohledu pod sebou |
| šířka vyhozená z klíče | `Po změně šířky se přepočítají rámečky, ale nesází se` — rámečky zůstanou na staré šířce bloku |

**Render se porovnává po bytech.** `DetailTabRenderProbe.rendersBothDiffLayouts` vykreslí
`Změněné soubory` v obou pohledech a na dvou šířkách; snímky z `main`u a z větve vyšly
**bajt v bajt stejné** (334 721 / 179 118 / 283 840 / 206 205 B). Sonda je u toho nejdřív ověřená
sama proti sobě — dva běhy nad týmž kódem dají tytéž byty —, jinak by shoda netvrdila nic.

**Ostatní representable se prověřila taky, a měřením, ne čtením.** `SelectableCodeView` (hunk
v sheetu) sází text bezpodmínečně, takže vypadá jako tentýž vzor — nad tímtéž špiněním grafu ale
dostane **jednu** aktualizaci proti jedenácti u bloku dvojic, protože si neříká o vlastní velikost
a jeho hodnota se nemění. Stráž tam proto **není**: zkoušeno, že s ní i bez ní test o výběru
prochází, tedy že by ji nešlo ověřit vloženou regresí. `LogTailTextView` tentýž klíč
(`shownText`/`shownColor` v koordinátoru) má od #292.

**Přeměřeno u #417, když se ten sheet stal roztahovatelným** — tažení za okraj vypadalo jako ta
chybějící pohonná síla, protože se při něm přeměřuje plocha a `body` sheetu jde znovu. Změřeno na
**skutečném okně sheetu** (dočasná počitadla v `updateNSView` a v klíči, patnáct kroků tažení po
12 bodech): `updateNSView` **0×**, sazeb **0×**, výběr `{4, 12}` zůstal. Stráž se proto nepřidala ani
tehdy a ta dočasná počitadla v repu nezůstala — co drží výběr, je
`DiffBlockUpdateTests.codeSheetKeepsTheSelectionWhileResizing`, který spadne, jakmile si tohle view
začne říkat o vlastní velikost.

**Cena stráže se měří v harnessu** (`DiffPerformanceMeasurement.blockUpdateGuardCost`, 27 bloků po
60 řádcích, medián ze tří běhů): klíč nad **týmiž** poli **0,013 ms**, hash s podpisem (to, co tam
bylo do #393) **0,530 ms**, porovnání po řádcích u čerstvých polí **0,284 ms**. Past u toho měření:
**`Array(pole)` kopii nevyrobí** — jen podrží úložiště, takže se s ním měří zase identita
(0,013 proti 0,012 ms, nerozlišitelně). Čerstvé pole udělá `map`.

**A v kole, které jede** (`IdleDiffSpinProbe.wheelSplitDiff`, split diff, 60 kroků kolečkem po
40 pt, série **A/B/A/B** kvůli driftu sezení podle #274):

| | se stráží | bez stráže |
|---|---|---|
| práce bloků po usazení scény | 15 aktualizací → **3 nasazení** (3 bloky) | 15 aktualizací → **15 nasazení** |
| CPU hlavního vlákna za gesto | 0,55 / 0,52 s | 0,50 / 0,55 s |
| CPU po gestu, tři úseky po 3 s | 0,00–0,01 % | 0,00–0,01 % |

**Na projíždění se to neprojeví, a je to tak správně**: blok, který vjede do okna, dostane jednu
aktualizaci a nasadí se jednou — není co ušetřit. Šetří se tam, kde se geometrie přepočítává nad
**týmž** blokem pořád dokola, tedy v tom kole z #361; v harnessu se takové kolo nerozjede (čtyři
kola měření u #361), takže se to číslo bere ze **vzorku ztuhlé aplikace**: 5,5 % vzorků hlavního
vlákna, které se po opravě zredukují na porovnání klíče.

### Jak změřit projíždění diffu, když se ho nedá dotknout (#252)

Scénář z #252 (velký split, sjet a vyjet) se musel řídit **nastavením posuvníku přes
accessibility** — `set value of scroll bar …`. Ostatní cesty se vyzkoušely a nefungují:

- **Syntetické scroll eventy nedoručí nic.** `CGEvent(scrollWheelEvent2Source:)` +
  `postToPid` (i s dosazenou `location` nad diffem) posuvníkem nehnul — proces, který je posílá,
  na to nemá oprávnění a `CGEventPost` selže **potichu**.
- **`Page Down` a `Page Up` `ScrollView` neobsluhuje.** Přes `System Events` dojdou (aplikace je
  vpředu, žádná chyba), ale posuvník zůstane na nule.
- **Myš nad diffem na tom nic nemění.** Kurzor se dá bez oprávnění přenést
  (`CGWarpMouseCursorPosition`) a vrátit, ale při programovém scrollování se žádné `mouseMoved`
  negeneruje, takže `onContinuousHover` (a s ním přestavění bloku) se nespustí. Naměřeno **3,54 s
  proti 3,55 s** — tedy nic.

Tři věci, bez kterých z toho vyjde nesmysl:

- **Řízení přes accessibility je samo většina naměřeného času.** V `sample`u zabírá
  `mshMIGPerform → _XCopyAttributeNames` (AppKit odpovídá na dotazy AX) **58 %** vzorků hlavního
  vlákna. Změřit se to dá zvlášť: tolikrát zapsat posuvníku hodnotu, **na které už je** — 601
  zápisů stálo 9,3 s CPU. Číslo z GUI se proto bere jako **rozdíl** proti téhle režii, a ta se
  musí změřit v obou verzích (v té s méně prvky je AX taky levnější).
- **Rozhoduje hustota kroků.** 60 kroků tam a zpět skáče o půl obrazovky, takže líný seznam
  přerovnává obsah málokdy a rozdíl mezi verzemi se utopí (3,6 s proti 3,4 s). S 300 kroky je
  vidět: **15,6 s proti 13,5 s** celkem, tedy po odečtení režie AX **6,4 s proti 4,2 s**.
- **Stav aplikace to mění násobně.** Tentýž build a tentýž scénář vyšel na 10,8 s v okně se
  **čtyřmi otevřenými záložkami PR** a na 3,6 s po čerstvém spuštění s jednou. Měření se proto
  pouští ze **stejného výchozího stavu** (spustit, otevřít jeden PR, rozbalit úsek) a čísla ze
  dvou různých sezení se nesrovnávají.

  **Ten trojnásobek se ale #274 nepovedlo zreprodukovat** a je to tím prvním bodem výš, ne
  záložkami — postup i čísla jsou v *Kolik stojí otevřená záložka* níž. Zůstává z toho **pravidlo
  o výchozím stavu**, protože rozdíl mezi dvěma sezeními vyšel větší než rozdíl, který se hledal.

**`window 1 of (first application process whose unix id is …)` sáhne do cizí instance.** System
Events si proces přepíše podle **jména**, a to mají všechny sloty stejné, takže `window 1` vrátí
okno prvního PRismu v seznamu — změřeno na poloze okna (32,33 místo 1593,130). Funguje
`item 1 of (every window of (first application process whose unix id is …))`, a **potomci se
nesmí iterovat přes vrácené reference**: ty jsou taky podle jména a čtení jejich vlastností spadne
na „nelze načíst“. Každý potomek se adresuje znovu celou cestou (`UI element i of …`).

**Když se appka řídí přes `System Events`, ověř, že je vpředu, a klikej relativně k oknu.**
`screencapture -R` bere **oblast obrazovky**, ne okno, takže pevné souřadnice míří po restartu
jinam — u #220 z toho byly dva snímky cizí aplikace a klikání mimo PRism. Poloha se zjistí takhle:

```bash
osascript -e 'tell application "System Events" to tell process "PRism" to return {position, size} of window 1'
```

**Paměť cache se `task_info`em měřit nedá** (#224). Přírůstek rezidentní velikosti po naplnění
cache 2400 řádky vyšel **0 kB** — alokátor sáhne po stránkách, které proces už má, takže by to
tvrdilo, že cache nic nestojí. Harness proto sčítá **text run**, který v ní zůstane ležet; klíč se
nepočítá, protože je to tentýž řetězec, jaký drží model diffu (kopíruje se jen hlavička).

**Klávesová zkratka se dá vyzkoušet jedině spuštěním** — a u #151 to bylo jediné, co odhalilo, že
`⌥↓` po prvním skoku nikam nejde. Pět věcí, na kterých to stálo, a všech pět stálo kolo navíc:

- **Když běží víc slotů, `process "PRism"` je nejednoznačné.** Všechny instance mají tentýž
  název procesu (binárka se jmenuje `PRism` i ve slotu), takže se hledá podle **bundle ID** —
  jinak se měří, klikají a zavírají cizí okna. Stalo se to: skript přesunul okno hlavní instance.
- **`whose` nad procesy se v `System Events` láme** (`nelze načíst … -1728/-1719`). Spolehlivý je
  obyčejný `repeat with p in (every application process whose name is "PRism")` a uvnitř
  `if bundle identifier of p is "com.ondrajodas.prism.<slot>"`.
- **Kliknutí do okna, které není vpředu, ho jen aktivuje** a k prvku se nedostane. Klikat se
  proto musí dvakrát, nebo se okno napřed vytáhne — a `activate` patří do **každého** skriptu,
  ne jednou na začátek relace: mezi dvěma `osascript` se terminál vrátí dopředu.
- **Snímek se pořizuje uvnitř téhož skriptu** (`do shell script "screencapture …"`), jinak se
  fotí to, co je vpředu **potom**.
- **`NSEvent.modifierFlags` synthetickou klávesu nevidí.** Stav klávesnice se posláním události
  ze `System Events` nemění, takže se modifikátory musí číst z `NSApp.currentEvent`. Se stavem
  klávesnice vycházelo `⌥⇧↓` jako obyčejné `⌥↓` a vypadalo to jako chyba v aplikaci.

Co se z běžící aplikace u #151 vyčetlo a jinak by se nevědělo: **SwiftUI páruje u šipek zkratku
bez ohledu na `.shift`**, takže dvě tlačítka lišící se jen jím jsou jedna klávesa. Ověřeno oběma
směry — po dočasném odebrání varianty se shiftem začalo `⌥↓` procházet nálezy a `⌥⇧↓` skákalo po
tom samém. Je to platformní chování, takže na něj **test není** a drží ho jen ten zápis; kdyby se
zkratky zase rozdělily na dvě tlačítka, projde build i testy a rozbije se to potichu.

### Kolik stojí přerovnání okna (#472)

Dvě sondy, obě ruční (`TEST_RUNNER_PRISM_MEASURE=1`), a **je podstatné, že jsou dvě**: měří dvě
různé věci a odpověď na #472 je v jejich rozdílu.

| Sonda | Co měří | Co z ní vyšlo |
|---|---|---|
| `DiffShapeProbe.relayoutCost` | **tvar seznamu** — přerovnání shora nad předpočítanými řádky, líný proti pevnému. Neměří scénář z aplikace, měří tvar | pevný stack je dražší **3×**, ale absolutně málo (6000 řádků: **3 ms** proti **9 ms** na přerovnání) |
| `DetailRelayoutMeasurement.relayoutCost` | **cesta, kterou kód doopravdy jde** (#275) — skutečný `ContentView` nad skutečným `AppStore` | jedno zneplatnění detailu stojí **95–116 ms** a **nezávisí ani na délce diffu, ani na tabu** |

#### Čtyři osy, protože bez ablace se to neodliší

`DetailRelayoutMeasurement` míchá **scénu** (celé okno / samotný detail), **pohon** (průchod tělem
hostitele / zápis do sledované vlastnosti / tichý tik pollingu), **tab** (`Soubory` s pevným
diffem, `Přehled` bez dlouhého seznamu, `Kontroly` navíc bez panelu vpravo) a **náplň store**
(prázdný / vlastní PR s nálezy a draftem). Čísla z jednoho sezení (okno 1512×874, Debug):

Čísla jsou z **opravené** podoby sondy (rozměr předepisuje okno, ne obsah — viz odstavec pod
tabulkou); starší běhy vycházely třikrát nižší a **neměřily to, co dělá aplikace**:

| Případ | ms na přerovnání |
|---|---|
| okno, `Soubory`, **hostitel** (tělo `ContentView`) | **4–6**, a **nula průchodů tělem** |
| okno, `Soubory`, zápis do store | **94–116** |
| okno, `Přehled`, zápis do store | **114–117** |
| okno, `Kontroly` (bez panelu), zápis do store | **90–102** |
| jen detail, `Soubory`, zápis do store | **22–27** |
| jen detail, `Soubory`, prázdný store | 7–9 |

Čtyři věci z toho plynou a všechny jsou pro #472 rozhodující:

1. **Průchod tělem `ContentView` detail nezneplatní.** `PullRequestDetailView` se poskládá znovu,
   ale SwiftUI ho prohlásí za nezměněný a tělo nepřeloží — v snímku počitadel není **žádné tělo**.
   Co detail překresluje, je tedy **zápis do sledované vlastnosti**, ne přestavba shora.
2. **Délka diffu na ceně nic nemění** (500 proti 2000 řádkům: 38 proti 43 ms) a `DiffView.body` se
   při přerovnání detailu **vůbec nepřeloží**. Hypotéza z hlavičky #472 — že cenu násobí eager diff
   z #469 — tím padla; `Přehled`, kde žádný dlouhý seznam není, je dokonce ten nejdražší tab.
3. **Panel vpravo je z toho ~15 ms** (rozdíl `Přehled` proti `Kontrolám`), takže ani on to není.
4. **Tři čtvrtiny ceny jsou mimo detail** (~100 ms v okně proti ~10 ms nad samotným detailem)
   a jsou v **rozvržení**, ne v tělech. Ve `sample`u z toho běhu drží `NSHostingView.layout()` →
   `render` hlavní podíl a **`updateWindowContentSizeExtremaIfNecessary` je z toho 15–50 %** podle
   fáze — druhá aktualizace grafu, kterou si vynucuje `.windowResizability(.contentMinSize)`
   (tentýž jev jako u #350). **Zlevnit ji se zkusilo a nešlo to**, viz *Tři zlevnění* níž.

**Pozor na to, čím se okno v sondě hostuje.** Předepsaný `frame(width:height:)` na scéně dotaz na
minimum **zmrazí** (odpoví konstantou dřív, než se zanoří), takže se s ním celá tahle mašinerie
neměří — a čísla vyjdou **třikrát nižší** (33–43 ms proti 95–116 ms). Rozměr proto předepisuje
**okno**, ne obsah, a hostující vrstva dostane `sizingOptions = [.minSize]`; tatáž konstrukce
i tentýž důvod jako v `IdleDiffSpinProbe.show(scene:minSizeFromContent:)`.

#### Přepnutí tabu je jiný scénář než přerovnání, a je to ten dražší

Uživatel popsal #472 jako „chvíli to čeká a pak se to začne škubaně přepínat“ — a to **není**
přerovnání, je to **první rozvržení**: obsah tabu se přepnutím zahodí a postaví znovu. Pohon
`přepnutí tabu tam a zpět` (`Přehled` ↔ `Soubory`) to měří:

| Diff | přerovnání (zápis do store) | **přepnutí tabu** | tichý tik |
|---|---|---|---|
| 500 řádků | 99–107 ms | **407–428 ms** | 496–556 ms |
| 2000 řádků | 95–116 ms | **576–682 ms** | 512–591 ms |

Na jedno přepnutí se přeloží **294 těl `DiffRowView`** (2000řádkový diff) a **nasadí se všechny
bloky** — `bloků 50, nasazení 50` proti `bloků 5` v ustáleném stavu, protože změřená výška bloku
zaniká s podstromem. **Roste to s velikostí diffu**, na rozdíl od přerovnání.

#### Ablace „slepá kostra“ — jak se pozná, jestli cenu dělá obsah, nebo tvar

Tohle je **postup, ne jednorázové měření**, a je to ten, kterým se #472 nakonec vyřešilo. Otázka
zní: **stojí to, co je uvnitř, nebo to, kam je to zasazené?** Bez ní se optimalizuje uvnitř
podstromu, který je levný — a přesně to se u #472 stalo čtyřikrát po sobě.

Dělá se to tak, že se měřený view nechá **beze změny** a vymění se jeho **sousedé** za obarvené
obdélníky téže velikosti (`Color.gray.frame(height:)`, `frame(width:)`). Vzniknou tři scény, které
se od sebe liší jedním krokem:

| Scéna | Co je v ní | Na co odpovídá |
|---|---|---|
| `jen detail` | měřený view sám v okně | co stojí on |
| `detail ve slepé kostře` | tentýž view v **kostře** z aplikace, sousedé slepí | co stojí **zasazení** |
| `okno` | skutečný `ContentView` | co stojí **sousedé** (rozdíl proti kostře) |

Čísla z #472 (realistická data — konverzace 200 uzlů, 48 nálezů, 12 checků, 24 commitů):

| Scéna | průchod tělem detailu | přepnutí tabu (bez diffu) |
|---|---|---|
| jen detail | 18 ms | 88 ms |
| slepá kostra, **pružný rámec** | **81–89 ms** | **282–295 ms** |
| slepá kostra, pružný rámec, **prázdný store** | 70 ms | — |
| slepá kostra, **měřená štěrbina** | **7–8 ms** | **56 ms** |
| skutečné okno (po opravě) | 10–11 ms | 62 ms |

Čte se z toho, že **sousedé stáli 7 ms** a **zasazení 71 ms** — tedy že cenu dělal tvar, ne obsah.
Čtvrtá scéna (`slepá kostra, měřená štěrbina`) je pak ta samá kostra s opravou, takže se rozdíl dá
přečíst na jednom řádku a **nezávisí na tom, co je zrovna v aplikaci**.

Tři věci, bez kterých z toho nic není:

- **Slepí sousedé musí mít rozměry z aplikace.** Rail 56, hlavička 92, stavový řádek 28 bodů —
  jinak se měří jiný tvar.
- **Data musí být realistická, i když se měří tvar** — a porovnat se musí **uvnitř jednoho běhu**
  (drift sezení je větší než hledaný rozdíl, #274). Táž kostra vyšla **81 ms s plným storem
  a 70 ms s prázdným**, tedy obsah dělá **14 %**. Malý rozdíl je tady **výsledek**, ne důvod
  fixture nedoplnit: bez něj by se nedalo tvrdit, že cenu nedělá obsah.
- **Rozměr předepisuje okno, ne scéna.** `frame(width:height:)` na obsahu zmrazí dotaz na minimum
  a čísla vyjdou třikrát nižší — viz odstavec o hostování výš.

#### Tři čtvrtiny přepnutí nemá s diffem co dělat

Pohon `přepnutí tabu bez diffu` (`Přehled` ↔ `Kontroly`, tedy dva taby, ve kterých žádný dlouhý
seznam není) je ablace k tomu výš — a odpovídá na otázku, kterou se čtyři pokusy z #472 o zlevnění diffu
marně snažily obejít:

| Přepnutí | 500 řádků |
|---|---|
| `Přehled` ↔ `Soubory` | **410 ms** |
| `Přehled` ↔ `Kontroly` (bez diffu) | **309 ms** |

**Diff je z toho ~100 ms, zbytek je přestavba detailu samotného** — hlavička, pruh záložek, panel
a `.task` kaskáda, které se přepnutím zahodí a staví znovu (`PullRequestDetailView=2`
a `MarkdownText=1` na přepnutí i v tabu bez diffu). U 2000řádkového diffu je diffová část větší
(~230 ms z 638), ale ta fixní zůstává.

#### Čtyři zlevnění, která se změřila a zahodila

Všechna tři **mechanicky fungují** a **na ceně nezměnila nic**. Jsou tady proto, aby je nikdo
nezkoušel podruhé:

| Co se zkusilo | Že to funguje, je ověřeno | Co to udělalo s cenou |
|---|---|---|
| `Layout` v kořeni okna, který na dotaz na **minimum** (`0×0`) odpoví konstantou místo zanoření — cílem bylo `updateWindowContentSizeExtremaIfNecessary`, které ve `sample`u drží 15–50 % rozvržení | `WindowMinimumProbe`: pod kořenem zbyla **jedna** nabídka místo dvou | 94 ms proti **98 ms** — cena té druhé aktualizace grafu **není v tom sestupu** |
| **Zapamatované výšky bloků**, které přežijí přepnutí tabu (aby se nemusely nasazovat všechny) | počitadlo v cache: **5 778 použití z 6 924 dotazů** | 422 / 576 ms proti **428 / 602 ms** — mount `NSTextView` není to, co přepnutí stojí |
| Skládat uzávěry tažení a kopírování **jednou za soubor** místo za řádek (8 místo 2 352 alokací) | — | 407 / 682 ms proti **428 / 602 ms**, tedy uvnitř rozptylu; **zůstalo jako kratší kód**, ne jako zlevnění |
| **Úseky řádků** (#472, redesign): řádky po šestnácti, úsek mimo pás nahrazený jedním prázdným místem známé výšky — aby měl pevný stack desítky dětí místo tisíců | průchodů tělem `DiffRowView` na jedno přepnutí **294 → 147**, tedy polovina pryč | 389 / 638 ms proti **407 / 602 ms**. **Půlka dětí zmizela a cena se nehnula** — což je zároveň ten nejsilnější doklad, že cena není v počtu řádků |

**Co z toho plyne:** cenu **nedrží počet řádků** — půlka jich zmizela a nezměnilo to nic —
a u přepnutí tabu jsou **tři čtvrtiny ceny mimo diff**. Zbývalo rozvržení detailu a okna jako
celku, a **tam ta cena taky byla**: obsah okna byl pružné dítě `HStack`u, takže mu stack posílal
průzkumné nabídky na pružnost a rámec je předával dolů celým detailem. Našla to ablace *slepá
kostra* výš; oprava je `fillingSlot()` na obsahu v `ContentView`. **Všechny čtyři zamítnuté pokusy
tím dávají smysl zpětně** — zlevňovaly věci **uvnitř** detailu, kdežto platilo se za to, kolikrát
se do detailu vůbec sestoupí. Ve `sample`u té fáze je naše vlastní práce **~1,5 %** hlavního vlákna (`AppStore` 21,
`Policy` 15, `PullRequestDetailView` 36 vzorků ze 14 726); zbytek je `GraphHost.flushTransactions`
(1 947), `NSHostingView.layout` (1 630) a `LayoutEngineBox.sizeThatFits` (1 222).

#### Pět pokusů o zlevnění přepnutí tabu s diffem — jeden nasazený, čtyři zamítnuté (#476)

Po #472 stálo přepnutí tabu **s diffem** 243 ms u 500řádkového a 466 ms u 2000řádkového diffu proti
**62 ms** bez diffu. Rozklad (tři velikosti, aby se dalo ověřit, že je to přímka) ukázal, že je to
**lineární v počtu řádků** — a vzorek ukázal, že to **není v jejich skládání**:

| | vzorků z 16 539 | podíl |
|---|---|---|
| rozvržení (`NSHostingView.layout` → `render`) | 9 283 | 56 % |
| ├─ stavba **display listu** | 3 391 | 20 % |
| ├─ `updateNSView` bloku | 1 519 | 9 % |
| │   └─ z toho `DiffTextView.lineFrames()` | 697 | 4 % |
| ├─ `LayoutEngineBox.sizeThatFits` | 1 215 | 7 % |
| **stavba těl `DiffRowView`** | **170** | **1 %** |

Vyšlo z toho **jedno zlevnění a čtyři zamítnutí**:

| Pokus | Že mechanicky funguje | Cena (2000 řádků) |
|---|---|---|
| **`lineFrames()` jedním průchodem** místo dotazu na každý řádek | `DiffLineFramesTests` — rámečky se shodují s `frame(ofLine:)` | **462 → 433 ms**, **nasazeno** |
| zapamatované **výšky bloků** přes přepnutí tabu | 5 778 použití z 6 924 dotazů | 465 proti 462 ms |
| **úseky řádků** po šestnácti, úsek mimo pás jako prázdné místo známé výšky | průchodů tělem `DiffRowView` **7 080 → 3 540** | 433 → **400 ms** (7,6 %) |
| **nezahazovat obsah tabu** při přepnutí (držet diff naživu) | přepnutí s diffem **433 → 132 ms** | **zabilo výhru z #472** — viz níž |
| vrátit `LazyVStack` | — | zamítnuto beze změny (#469): zaseknuté okno je horší vada než pomalé |

**Třikrát nezávisle vyšlo totéž: cena není v počtu řádků.** Ubrat polovinu vykreslených řádků
pohnulo cenou o 7,6 %, protože řádky jsou 1 % vzorku.

**Držet tab naživu je ta nejzajímavější prohra a stojí za zapamatování**, protože vypadá jako výhra,
dokud se člověk nepodívá vedle. Skrytý obsah se totiž **pořád účastní rozvržení**:

| Scénář (2000 řádků) | dnes | s živým tabem |
|---|---|---|
| přepnutí tabu **s diffem** | 433 ms | **132 ms** |
| přepnutí tabu **bez diffu** | 60 ms | **252 ms** |
| **zápis do store** (přerovnání okna) | **11 ms** | **52 ms** |

Přepnutí na diff by zlevnilo třikrát, ale **přerovnání okna by zdražilo pětkrát** — a to je ta věc
z #472, kterou člověk potká při každém kliknutí, kdežto diff jen při přepnutí na něj. V diagnostice
je to vidět i bez čísel: na **zápis do store** se najednou přeloží 3 540 těl `DiffRowView` (dnes
nula) a bloky se nasazují dokola (135–155 nasazení proti 10). **Kdo to bude zkoušet znovu, ať měří
tohle jako první.**

#### Pohon „tichý tik pollingu“ je ten, kvůli kterému #472 vzniklo

`await store.refresh()` nad fake gatewayí, která vrací pořád tentýž seznam — tedy přesně to, co
v záznamu diagnostiky z 27. 8. stálo 1,0–1,5 s CPU každou minutu. Před/po opravou (#472, tatáž
sezení, série A/B/A/B):

| Diff | | průchody tělem `PullRequestDetailView` | `DiffView` | `DiffRowView` | CPU na tik |
|---|---|---|---|---|---|
| 500 řádků | do #472 | 62 | 68 | 4 352 | 451 ms |
| | od #472 | **1** | **7** | **448** | 427 ms |
| 2000 řádků | do #472 | 62 | 69 | 10 143 | 551 ms |
| | od #472 | **1** | **7** | **1 029** | 343 ms |

**Průchodů tělem ubylo šedesátkrát, ceny jen o třetinu** (a u malého diffu skoro vůbec) — a to je
poctivý závěr, ne měření navíc: zbytek tiku není v tělech. Kde je, je bod 4 výš.

#### Na co se u téhle sondy naráží

- **Odložené okno drží svůj strom a ten dál poslouchá store.** První podoba sondy měřila v jedné
  scéně a okna jen odkládala — do dalšího měření se pak počítaly průchody tělem předchozích scén
  (0,57 → 2,26 s u téhož případu a osminásobný počet průchodů). Řeší to **vlastní store na každou
  sérii**; rozebrat okno zevnitř `defer`u nejde (`contentView = nil` a `close()` uprostřed měření
  položily testovacího hosta `SIGSEGV`em).
- **Seznam PR se musí naplnit** (`await store.refresh()` v přípravě), jinak `ContentView` na
  `store.summary(for:)` nesáhne a místo detailu nakreslí prázdný stav — naměřeno **0,00 s CPU
  a nula průchodů tělem**, tedy měření nad oknem, ve kterém PR není.
- **Rozměr se předepisuje scéně**, ne oknu (past ze `IdleDiffSpinProbe.show(store:full:)`).
- **`FakeTimeSource` nespí**, takže `ContentView` se svým `.task { keepFresh() }` roztočí polling
  naplno; sonda ho zastaví `stopAfter: 1`.

### Kolik stojí otevřená záložka (#274)

**Posuvník se řídí přímo přes `AXUIElementSetAttributeValue`, ne přes `System Events`** — a je to
ten hlavní rozdíl proti postupu u #252 výš. Režie řízení spadla z **9,3 s na 0,02 s** za 601 zápisů
(tedy ~450×), protože do toho nemluví druhý proces, který si cestu k prvku dohledává podle jména
a přitom se vyptává na atributy. Číslo z GUI tím **přestává být rozdíl dvou velkých čísel**: 2,4 s
naměřených za projetí diffu je práce aplikace, ne odpověď na dotazy AX.

Prvek se hledá **podle PID** (`AXUIElementCreateApplication`) a v okně, které se jmenuje `PRism` —
vedle sebe běží víc slotů a **okno novinek si po vydání releasu stoupne dopředu**, takže „první
okno“ vrátí ono. Svislý posuvník diffu je ten **nejvyšší** v okně; seznam i panel mají svoje.

```swift
let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.ondrajodas.prism.b" }!
let root = AXUIElementCreateApplication(app.processIdentifier)
// … najít okno s titulkem "PRism" a v něm nejvyšší AXScrollBar s AXVerticalOrientation …
for step in 1...steps { set(Double(step) / Double(steps)) }    // sjet
for step in 1...steps { set(1 - Double(step) / Double(steps)) }    // a vyjet
```

**CPU se čte z `ps -o time=` a čeká se, než se aplikace usadí — před měřením i po něm.** Bez toho
prvního spadne do čísla dokreslení po aktivaci okna (0,27 s), bez toho druhého z něj vypadne chvost
rozvržení, který běží po posledním zápisu do posuvníku. „Usadit se“ znamená, že se `time` přestane
hýbat; `ps` má rozlišení na stovky sekundy, což u čísel v sekundách stačí.

**Střídá se A/B/A/B, protože drift sezení je větší než hledaný rozdíl.** Tentýž scénář vyšel
v jednom sezení na 2,15 s a o půl hodiny později na 4,39 s — dvě série za sebou by tedy měřily
stárnutí sezení a zátěž stroje (souběžně buildí ostatní sloty), ne to, co se srovnává. Záložky se
zavírají tlačítkem `Zavřít <repo>#<číslo>` a otevírají z fronty: **`AXPress` na záložku v pruhu
nedělá nic**, protože je to `onTapGesture` s `.isButton`, ne `Button` — přepnout se dá jedině
kliknutím na řádek ve frontě (už otevřený PR se tím jen vybere).

Co z toho u #274 vyšlo na scénáři z #252 (`job-queue-daemon#858`, split, rozbalený úsek o 1 904
řádcích, 300 kroků tam a zpět):

| Stav | CPU (tři kola, střídaně) |
|---|---|
| jedna záložka | 2,77 s / 3,50 s / 3,28 s |
| čtyři otevřené záložky | 4,39 s / 3,68 s / 3,37 s |
| jedna záložka, po #274 | 2,79 s / 2,60 s / 2,39 s |
| čtyři záložky, po #274 | 2,26 s / 2,33 s / 2,56 s |

Tedy **rozdíl mezi jednou a čtyřmi záložkami se v okně neukázal** — leží pod rozptylem téhož
měření (±25 %). Trojnásobek z #252 (3,6 s proti 10,8 s) se zreprodukovat nepovedlo ani na
**buildu před #252** (`3a49f0a~1`, tamtéž: 4,92/4,57/4,96 s proti 4,30/4,30/4,45 s), takže to
nebylo tak, že by #252 tu příčinu cestou spravil.

Čím se vylučovalo (a co z toho vylezlo za čísla):

| Podezření | Čím padlo |
|---|---|
| Per-PR slovníky (`DiffRowFrames`) drží cenu projíždění | `sample` běžícího procesu během projíždění: `DiffRowFrames.note` má **17 vzorků ze 4104** na hlavním vlákně, tedy **0,4 %**. Roste to sice s prohlédnutými záložkami (viz harness, 0,25 → 0,93 ms na blok), ale ze 0,4 % se trojnásobek celku nedá poskládat |
| Neaktivní záložka se přepočítává na pozadí | Nečinné okno se čtyřmi záložkami stojí **0,00 s CPU za 15 s**. Detail neaktivní záložky se nekreslí — `ContentView` má v `switch`i jen aktivní tab, takže z něj nezůstane nic než data ve store |
| Cache obarvení se s víc soubory zahazuje (`SyntaxRunCache`, strop 4000 řádků) | V sampleu není `SyntaxHighlighter` ani `SyntaxRunCache` **ani jednou**; kdyby se cache při projíždění vyprazdňovala, `scan` by v něm být musel |
| Paměť: čtyři záložky tlačí stroj do komprese | RSS **36 → 74 MB** po otevření tří dalších záložek a při nečinnosti zpátky na 44 MB. Na tomhle stroji to není tlak, který by se projevil v CPU |
| Cenu drží to, že aplikace odpovídá na dotazy AX (u #252 58 % vzorků) | Průchod stromem okna stojí se čtyřmi záložkami **0,11 s** proti **0,08 s** s jednou (20 průchodů), tedy 1,4× — a to je jediné, co s počtem záložek doopravdy roste. Vysvětlilo by to nejvýš pár desítek procent na měření, které si režii AX odečítá špatně, ne trojnásobek |

**Vlastní práce aplikace při projíždění** (z téhož sampleu, 4104 vzorků hlavního vlákna) leží
v rozvržení líného seznamu a v sazbě textu: `DiffTextView.draw` a spol. **~16 %**, zbytek
`AttributeGraph` a `NSLayoutManager`. To je ten směr, kterým se dá projíždění zlevnit — a je to
**samostatná věc**, ne tohle issue.

### Katalog zkratek okna (#441)

Testuje se **katalog, ne stisk**. Že klávesa doopravdy zabere, se v harnessu ověřit nedá:
testovací host nedostane aktivaci (`NSApp.isActive == false` i po `activate(ignoringOtherApps:)`,
změřeno u #392 a potvrzeno u #434), takže nemá key okno a stisk nemá kam sednout. `WindowShortcutsTests`
proto tvrdí sedmnáct věcí o datech a poslední kolo dělá člověk na běžící aplikaci — **na české
i anglické mapě**, protože právě to je jádro #441.

Co z toho stojí za zapamatování:

- **Nejcennější je tvrzení, že se nic neopakuje.** Dvě tlačítka s jednou kombinací nejsou chyba
  ani pád — vyhraje to zaregistrované později a druhá zkratka „nefunguje“. Ověřeno **vloženou
  regresí**: `⌘.` přepsané na `⌘K` shodí `Žádné dvě tlačítka v okně nemají tutéž kombinaci`,
  `Kreslené zkratky jsou ty skutečné` i `Paleta kreslí u akcí zkratku z katalogu`.
- **Počet akcí je vyjmenovaný** (od #459 jednadvacet), ne „aspoň tolik“ — tatáž konstrukce jako
  u `SingleWayOutTests`. Nová zkratka v okně je rozhodnutí, ne přírůstek.
- **Stráž nad zdrojáky** tvrdí, že `keyboardShortcut(` je v `App/` **jen v deseti jmenovitých
  souborech**: v překladu katalogu (`WindowShortcutButtons`) a v sheetech, scénách, uvítací bráně
  a paletě, které si klávesu berou samy. Komentáře se zahazují stejně jako v grepech z `CLAUDE.md`.
  Ověřeno vloženou regresí: literální `.keyboardShortcut("j", modifiers: .command)` v `ContentView`
  ji shodí.
- **Stráže jsou dvě a chytají různé věci.** Ta první `keyboardShortcut(`, ta druhá `⌘` nebo `⌥`
  v **řetězcovém literálu**. Druhá přibyla až po Copilotovi: tooltip panelu se převedl na katalog,
  ale kapsle vedle něj kreslila `⌘2` natvrdo — a to první stráž nechytá, protože kapsle žádnou
  klávesu neregistruje. Ověřeno vloženou regresí (vrácené `Text(verbatim: "⌘2")` v `ReviewPanel`
  ji shodí).
- **Systémové kombinace zůstávají volné** (`⌘W`, `⌘Q`, `⌘M`, `⌘H`, `⌘,`). Je to jediné místo, kde je
  z testu vidět, proč se záložka zavírá `⌃W`.
- **Zakázané stavy se testují jako čisté funkce**: `Policy.closableTab(in:)` výčtem (domácí záložka
  → `nil`) a `⌘R` proti `Policy.refreshControl(isRefreshing:)`, tedy proti **téže** podmínce, ze
  které si podobu bere tlačítko `⟳` (#442). Dvě kopie by se rozešly potichu — povolená zkratka nad
  zakázaným tlačítkem vypadá jako nefunkční tlačítko.
- **Modifikátory u `.cancelAction` se zahodí potichu**, takže na to je vlastní tvrzení. Kdyby je
  katalog napsal, nikde by se to neprojevilo.
- **Kapsli sází monospace systémové písmo a dva glyfy v něm nejsou.** Změřeno samostatným
  `swift` skriptem nad `.AppleSystemUIFontMonospaced-Regular`: `⇥` (U+21E5) a `⎋` (U+238B) vrátí
  `CTFontGetGlyphsForCharacters` **`false`**, kdežto `⌘`, `⌃`, `⌥`, `⇧`, `⏎`, `↑` a `↓` `true`.
  Proto se `Tab` a `esc` píšou slovem. Test to tvrdí nad **výčtem znaků**, ne měřením písma za
  běhu — `NSFont` v hostu pod zátěží vydá přechodně nepoužitelnou metriku (#407) a sáhnout si sem
  na písmo znamená koupit si falešně červený `main`. Přeměřit se to dá takhle:

  ```swift
  let ct = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular) as CTFont
  var chars = Array("⇥".utf16); var glyphs = [CGGlyph](repeating: 0, count: chars.count)
  print(CTFontGetGlyphsForCharacters(ct, &chars, &glyphs, chars.count))   // false
  ```

**Na kapsle v paletě se dá podívat offscreen** — `CommandPaletteRenderProbe` má od #441 scénář
`akce`, který katalog zúží na skupinu `Akce`. V plném katalogu je až za nálezy, soubory a dvěma
skupinami PR, tedy pod hranou karty; a je to jediná skupina, ve které se zkratky kreslí. Právě
tenhle render ukázal, že kapsle `⌃1` je v pořádku (`⌃` je U+2303 UP ARROWHEAD, který **vypadá**
jako stříška) — a při té příležitosti i to, že `⇥` a `⎋` písmo nemá.

```bash
TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/prism xcodebuild \
    -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
    -only-testing:PRismTests/CommandPaletteRenderProbe > /tmp/probe.log 2>&1
```

**Prefix `TEST_RUNNER_` je povinný**: bez něj se proměnná do testovacího hosta nedostane a sonda
se **přeskočí** — `xcodebuild` skončí `TEST SUCCEEDED` a v cílové složce nic není, což vypadá jako
rozbitá sonda.

### Zásuvka s terminálem (#459, `▶` do ní #460)

Testuje se **rozhodnutí a stav, ne emulátor**: `TerminalDrawerTests` (čisté funkce),
`AppStoreTerminalTests` (co store udělá s otevřením, zavřením záložky a ukončením — proti
`FakeTerminalHost`, který žádný shell nespouští), `AppStoreResumeInDrawerTests` (`▶`, #460)
a `AppDelegateTerminationTests` (dotaz při zavírání). Co se **v harnessu ověřit nedá a proto to
zkouší člověk**, je vypsané níž.

Co z toho stojí za zapamatování:

- **Nejcennější jsou tři tvrzení o tom, co se nestane**: schování zásuvky shell **nezabije**
  (jinak by `` ⌃` `` uprostřed běžícího `claude --resume` byl nevratný omyl), zavření záložky ho
  **zabije** (jinak sirotek z #264 a #351) a `PATH` aplikace se do shellu **nepředá** (jinak
  zásuvka bez Homebrew).
- **Ustupování zkratek se tvrdí výčtem nad celým katalogem**, ne nad jednou vybranou kombinací —
  a přes **všechny** kombinace, protože `⌃1` má na české mapě alternativu `⌃+`, která by se
  uplatnila stejně. Výjimka `` ⌃` `` je v tom tvrzení **vypsaná**, takže druhá výjimka spadne
  v testu, ne až v okně.
- **Adresář, který na disku není, se nesmí nabídnout.** Eviction klony maže, takže shell spuštěný
  ve smazané složce není teoretický stav; test to zkouší nad cestou, která nikdy neexistovala.
- **Emulátor se netestuje** a je to vědomé: `SwiftTerm` má vlastní sadu testů. Rozhraní mezi ním
  a naším kódem je úzké — start, kill, fokus, barvy —, a to podstatné z něj měří sonda níž.
- **U `▶` (#460) se tvrdí, co se do zásuvky poslalo, ne co se v ní stalo.** Rozhodnutí „běží tam
  něco?“ dělá živý hostitel z jádra (`tcgetpgrp`), takže fake dostane výsledek podstrčený
  (`FakeTerminalHost.outcome`) a testuje se, co s ním store udělá. Nejcennější jsou tři tvrzení
  o tom, co se **ne**stane: **druhá session nepřebije první** (kvůli tomu se #460 měnilo), po
  `busy` se **nepřepíše cesta v hlavičce** zásuvky a store **bez** hostitele si nevymyslí hlášku
  o něčem, o co se nikdo nepokusil.
- **U relací (#460) je nejcennější, že se běžící nikdy nevytlačí** (`TerminalSlotsTests`). Zahodit
  rozdělaný `claude --resume` kvůli kliknutí, které o něm nic neví, je nevratný omyl — a rozbije se
  to potichu, protože zásuvka po tom vypadá, jako by se nic nestalo. Vedle toho se výčtem tvrdí, že
  relace **bez hlášeného stavu** se za běžící nepovažuje (jinak by zásuvka po restartu byla plná
  něčím, co v ní nikdy nebylo) a že **kód, který nedorazil**, se kreslí jako klid, ne jako chyba.
- **Že zavření záložky zabije i tu relaci, která nebyla vidět**, se tvrdí přes seznam, ne přes
  aktivní relaci: `stopTerminals(for:)` dostane pull request, ne slot. Je to tvrzení o sirotkovi
  z #264 a #351, jen o jednu úroveň dál.
- **U důvěry ke složce (#460) jsou nejcennější tvrzení o tom, co se NEpřepíše**
  (`WorkspaceTrustTests`): rozbitá konfigurace, konfigurace, která není objekt, a chybějící soubor
  se **nezakládá**. Píše se do souboru, který aplikace nevlastní, takže chyba tady nestojí funkci,
  ale cizí práci — a ztráta při nezapsání je **jeden dialog navíc**. K tomu se tvrdí, že cizí klíče
  přežijí a že se hotová důvěra **nezapisuje znovu** (přes čas změny souboru, ne přes obsah).
- **A od #479 se tvrdí i to, co se přepsat SMÍ**: zapsané `false` **na naší cestě** se přepíše na
  `true` a zbytek toho záznamu (`allowedTools`) zůstane. Je to protipól řádku výš, takže obě
  tvrzení musí stát vedle sebe — jinak se dá „nepřepisujeme“ zpřísnit tak, že to zavře i tenhle
  případ. Vedle toho stojí `TerminalDrawerTests` nad `Policy.workspacesToTrust` (pořadí *nejprve
  strom, pak kořen*, žádný kořen dvakrát) a čtyři tvrzení ve `AppStoreResumeInDrawerTests`: že se
  zapisuje **strom té session**, že **druhý strom dostane vlastní zápis** (kvůli tomu se #479
  dělalo — příznak by po prvním PR zavřel cestu všem dalším), že `` ⌃` `` zapisuje **složku
  shellu** a že neúspěch **nezastaví druhou složku ani další pokus**.
- **Práva `0600` se u #479 doplnila taky**, protože to byla jediná ze čtyř pojistek #460, na kterou
  se dokumentace odvolávala a test na ni nebyl. Tvrdí se, že práva zápis přežijí a že po sobě
  **nezůstane dočasný soubor** — obojí je vlastnost `replaceItemAt`, takže je to tvrzení
  o atomickém zápisu, ne o zvlášť nastavovaných právech. **Vloženou regresí ověřené pásmem**:
  „zjednodušení“ na `Data.write(to:options: .atomic)` test **nechytá** (Foundation atributy
  původního souboru přenese taky, změřeno), kdežto `removeItem` + `moveItem` ano — vyjde `0644`.
  Hlídá tedy tu cestu, kterou se to doopravdy dá rozbít.
- **A nejcennější tvrzení celé téhle oblasti je, že se složce mimo cache důvěra NEzapíše** (#479).
  Rozbije se potichu — zapsané `true` v cizí konfiguraci nikdo neuvidí —, a proto k němu patří
  druhá půlka: **fixtury se přestěhovaly pod skutečný kořen cache**. Cesta `/Users/o/…` od téhle
  změny tvrdí něco, co v provozu nenastane, takže by test procházel a hranici by neověřoval nic.
  Cenou je, že řádka do zásuvky se porovnává s **interpolovanou** cestou; uzávorkování a zbytek
  řádky zůstávají literál, tedy to, na čem to tvrzení stojí.
- **A `CacheFileVerdictTests` hlídá, že si zápis bere ten přísnější ze dvou verdiktů** (#479, nález
  Copilota). `CacheFile` nabízí `isInsideCache` pro **mazání** a `refusal` pro **čtení a zápis**;
  liší se odkazem na **samotné složce**, protože `contains` rozbaluje jen rodiče. Suita to tvrdí
  dvakrát: nad **skutečným odkazem** ve scratch layoutu (mazací verdikt ho pustí, zápisový ne)
  a **nad zdrojákem** volajícího, protože `AppStore` si layout bere staticky — odkaz by tedy musel
  vzniknout ve **skutečné** cache aplikace, kam test sahat nemá. Je to tentýž postup jako
  u `GlobalAppearanceTests` a `FontMetricTests`. Do #479 na `CacheFile` přímý test **nebyl vůbec**,
  přestože je to jediné místo, kde tvrdá podmínka č. 3 bydlí.
- **Že do zásuvky jde `session.shellLine`, se tvrdí i literálem.** Text se porovnává s celou
  řádkou `cd '…' && claude --resume …` **a** s `session.shellLine`: první podoba chytí změnu
  uzávorkování, druhá to, že se `⧉` a `▶` rozešly.

#### Sonda `TerminalScrollProbe` — tři různá „nejde scrollovat“ (#460)

Vznikla na hlášení „nejde mi scrollovat v tom terminálu“ a **měří tři věci, protože každá znamená
jinou opravu**: kdo dostane kolečko (`hitTest` nad zásuvkou), jestli má emulátor čím rolovat
(scrollback a `yDisp` po kolečku) a co dělá kolečko **nad alternativním bufferem**.

Dvě věci, které z ní plynou a bez ní by se hádaly:

- **Hit test se musí měřit v okně** (`orderFrontUnanimated()`, #462). Bez okna vrátí `hitTest`
  kořenový `NSHostingView` a plochu emulátoru vůbec nenajde, **přestože v hierarchii je** —
  změřeno. Sonda bez okna by tedy hlásila chybu, která není, a poslala by opravu do vrstvy, kde
  žádná není potřeba.
- **Nad alternativním bufferem je „nejde rolovat“ správná odpověď.** Kolečko se tam nemá o co
  opřít (scrollback z definice není) a `claude` si navíc zapíná plné hlášení myši, takže událost
  dostane on. Tvrdí se to tedy jako **tvrzení o tom, co se nestane**: `yDisp` se nesmí pohnout.

  > **Druhá půlka toho odstavce byla nepravdivá a opravilo ji #478** — a je to poučení o sondě, ne
  > jen o terminálu. `claude` si o hlášení myši doopravdy řekl, jenže `SwiftTerm` kolečko aplikaci
  > **nikdy nepředá**, takže „událost dostane on“ neplatilo a rolovat nešlo vůbec. **Sonda to
  > nechytla proto, že se ptala na špatnou stranu**: měřila `yDisp`, tedy stav **emulátoru**,
  > a nad alternativním bufferem je nula správná odpověď **v obou** světech. Rozdíl je vidět jedině
  > na tom, **co odešlo do procesu**, a na to se neptal nikdo.
  >
  > Zapsané je to jako pravidlo, ne jako historka: **měřidlo, které vydá tutéž hodnotu pro
  > „funguje“ i „nefunguje“, netvrdí nic** — a vypadá u toho zeleně. Když měření končí větou
  > „neopravovalo se nic“, patří k němu druhá otázka: **naměřilo by rozdíl, kdyby ta chyba byla?**

#### Kolečko v zásuvce (#478) — co jde tvrdit bez pty

`TerminalWheelTests` (plocha) a `TerminalWheelPolicyTests` (rozhodnutí). Obojí běží **v běžném
běhu**, žádné `PRISM_MEASURE`: nespouští se shell, jen se krmí emulátor.

Dvě věci to obchází, a stojí za to je znát, protože se hodí i jinde:

- **Hlášení myši se zapne toutéž sekvencí, jakou pošle `claude`** — `ESC[?1000h` (hlášení
  tlačítek) a `ESC[?1006h` (kódování `SGR`, aby to, co odejde, byl čitelný text `ESC[<64;1;1M`
  místo netisknutelných bajtů). `Terminal.mouseMode` je `public private(set)`, takže se jinak
  nastavit ani nedá.
- **Co odešlo do procesu, se čte z podtřídy plochy.** `EmbeddedTerminalView` **není `final`**
  právě proto: testovací podtřída si přepíše `send(source: TerminalView, data:)` a bajty si
  zapamatuje. Je to jediná cesta z emulátoru ven — `Terminal.sendEvent` přes `sendResponse`
  skončí právě tam —, takže tímhle se přečte hlášení myši bez pty. **Bez `super`**, protože
  knihovní implementace píše do `process`, který v testu neběží.

Čtyři tvrzení a každé je jiná půlka #478:

- **Zapnuté hlášení → událost odejde** (a začíná `ESC[<64;` nahoru, `ESC[<65;` dolů).
- **Vypnuté → neodejde nic** a místo toho se pohne historie. Tohle je to tvrzení, které se rozbije
  potichu: kdyby se hlásilo i do `zsh`, objevily by se na promptu znaky místo rolování.
- **Počet hlášení = počet řádků** (`Policy.terminalWheelLines`), protože hlášení nese jen
  „cvaklo“. A **křivka se porovnává s knihovnou chováním**, ne opisem: `calcScrollingVelocity` je
  `private`, takže se pustí knihovní `scrollWheel(with:)` napřímo a změří se, o kolik se posunul
  `yDisp`. Před měřením se výřez srovná na dno (`scrollDown(lines: 1000)`), jinak by se místo
  křivky měřila mez bufferu.
- **Odrolovaný pohled přežije přiteklý výstup.** K tomu patří test, který schválně tvrdí **chybu
  cizího kódu** (`theLibrarySnapsTheViewportBack`): `Terminal.userScrolling` se v `1.11.2` nikdy
  nenastaví, takže knihovna sama srovná výřez na dno. Naměřeno na ploše 800×300 (**21 řádků**)
  se 400 nakrmenými řádky: `scrollUp(lines: 20)` dá `yDisp` **360**, jediný další řádek **381**.
  Přes `dataReceived` s naší kompenzací **377 → 377**. Až knihovna svůj příznak opraví, tenhle
  test **spadne** — a to je zpráva, že naše kompenzace může jít pryč.

**Rozdíl mezi `feed(text:)` a `dataReceived(slice:)` je v těch testech nosný, ne kosmetický.**
`feed` jde do emulátoru přímo, tedy **mimo** naši kompenzaci, a měří se jím knihovna;
`dataReceived` je cesta, kterou chodí bajty z pty, a měří se jí náš kód. Zaměnit je znamená měřit
něco jiného, než co je v hlášce.

**Co se tady ověřit nedá a dělá to člověk**: že se událost k `handle(wheel:)` doopravdy dostane.
Kolečko chodí lokálním odběrem (`NSEvent.addLocalMonitorForEvents`) a **doručování událostí
testovací host nerozpohybuje** — je to tatáž hranice jako u fokusu (#184). Patří to proto do popisu
PR jako věc na proklikání: rolování nad běžícím `claude` v zásuvce, rolování v holém shellu a to,
že se odrolovaný pohled nevrátí dolů, když přiteče výstup.

#### Sonda `TerminalResizeProbe` — kam až dojede rozměr (#460)

Vznikla na hlášení „resize ne úplně funguje, asi se přeskládává text“. **Měří přes
`NSHostingView`, ne nad holým `EmbeddedTerminalView`**, a je to celý smysl: mezi oknem a emulátorem
stojí `TerminalSurface` (`NSViewRepresentable`) a rámec od SwiftUI, takže sonda nad holým view by
ztrátu rozměru v té vrstvě neviděla a hlásila by, že je čisto.

Tři tvrzení, tři různé konce cesty:

- **Emulátor** (`terminal.cols`) — stav, který `SwiftTerm` mění **synchronně** v `setFrameSize`,
  takže na něj hladová hlavní fronta nedosáhne. Naměřeno 1 200 b → 163 sloupců, 700 b → 92,
  zpátky 1 000 b → 134; **řádky se se šířkou nehnuly**.
- **Jádro** (`TIOCGWINSZ` na master deskriptoru) — tohle je ta půlka, kvůli které se `claude`
  překreslí, protože `SIGWINCH` posílá jádro, ne emulátor. Naměřeno 138×21 buněk a 1 000×300 px,
  po zúžení 82×21. Pixely se tvrdí schválně: nula v nich je stav, který se z okna nepozná, a stojí
  na nich sixel i `kitty` protokol. **Se skutečným shellem**, tedy jen pod `PRISM_MEASURE`.
- **Kolikrát** se to do jádra pošle — 61 průchodů rozvržení přes 60 bodů dalo **8** změn (buňka je
  široká ~7 b). Kdyby se posílalo na každý průchod, dostal by `claude` desítky `SIGWINCH` se
  stejnou velikostí a přesázel by se pokaždé.

**Sonda tedy neodhalila chybu, a to je její výsledek** — přeskládání je reflow scrollbacku, který
`SwiftTerm` dělá podle správné úmluvy (`isReflowEnabled == hasScrollback`, takže alternativní
buffer se nereflowuje). Zapsané je to proto, aby to příště nikdo neměřil znovu od nuly.

#### Sonda `EmbeddedTerminalProbe` — skutečný shell, ale bez emulátoru

`TEST_RUNNER_PRISM_MEASURE=1` a `-only-testing:PRismTests/EmbeddedTerminalProbe`; **v běžném běhu
se nepouští**, protože spuštěný shell je proces, který umí běh testů přežít.

Co změřila a co by se bez ní neodhadlo:

- **Login shell se spustí a má řídicí terminál.** `ps -o state=` vrací `Ss+`, tedy *session leader
  v popředí* — takže `login_tty` proběhlo a job control uvnitř funguje. Kdyby chybělo, `⌃C`
  v zásuvce by nepřerušilo nic.
- **Pracovní adresář sedí** — čte se z jádra (`lsof -d cwd`), ne z výpisu v terminálu. Obě cesty se
  musí prohnat `resolvingSymlinksInPath`: `TMPDIR` je na macOS symlink, takže jádro hlásí
  `/private/var/folders/…` a `FileManager` `/var/folders/…`.
- **`kill()` zabíjí doopravdy** — po něm je stav `Z`. **Zombie se počítá jako mrtvý**: nesklizený
  potomek zabírá řádek v tabulce procesů, ale neběží, a `kill(pid, 0)` na něm pořád vrací nulu —
  takže tvrzení postavené na návratovém kódu by hlásilo, že shell přežil.

**Psaní do pty se odsud neověřuje, a je to změřené.** Pokus tam byl: poslat `exit` a čekat, až
shell skončí. Vycházel **náhodně** (z pěti běhů dva zeleně) a opakované posílání to nespravilo —
`LocalProcess.send` jde přes **druhý** `DispatchIO` kanál nad týmž deskriptorem, jehož první kanál
visí na hladové hlavní frontě (viz níž). Sonda postavená na tom je falešně červený `main`; napsat
do terminálu zkouší člověk.

**A co sonda ověřit nemůže vůbec, taky změřeně: obsah emulátoru.** `LocalProcess` doručuje
přečtené bajty přes `DispatchQueue.main`, a **hlavní dispatch fronta se v testovacím hostu nedrání
vůbec**. Naměřeno tak, že se z pozadí zavolalo `DispatchQueue.main.async` i `.sync` a za pět sekund
neproběhlo **ani jedno** (`hits == 0`) — přestože sonda běží na hlavním vlákně
(`Thread.isMainThread == true`) a točí `RunLoop.main.run(until:)`. Buffer emulátoru proto zůstane
prázdný, ať shell vypíše cokoli; první podoba sondy na tom stála a měřila vlastní zaseknutí.

Plyne z toho pravidlo širší než #459: **co v aplikaci chodí přes `DispatchQueue.main`, se v hostu
pozorovat nedá.** Kde to jde, hledá se jiný pozorovatelný konec (tady jádro); kde ne, ověřuje se to
rukama.

#### Sonda na dotaz o důvěru ke složce (#479)

Není to test v `Tests/` a schválně: pouští **skutečný interaktivní `claude`** v pty, takže by
z běhu testů dělala minuty čekání. Je to postup, který se pustí rukou, když je potřeba znovu
posoudit, kdy se dialog *„Is this a project you created or one you trust?“* objeví. Naměřené
odpovědi jsou v [`docs/claude-cli.md`](claude-cli.md).

Kostra je krátká — **`expect`, ne `script`**: `script` bere stdin z volajícího, takže mimo terminál
dostane hned EOF a pošle `claude` ^D.

```tcl
log_file -noappend $logfile
set timeout $secs
set env(HOME) $home          ;# podstrčený domov — na skutečnou konfiguraci se nesahá
set env(TERM) "xterm-256color"
cd $dir
spawn -noecho /Users/ondra/.local/bin/claude
expect timeout { }           ;# nic se neposílá, jen se kouká, co vypíše
exec kill -9 [exp_pid]
```

Scénář se zadává **jako obsah `projects`** a fixture se skládá z opravdové konfigurace:
`jq --argjson p "$scenar" 'del(.projects) | .projects = $p' ~/.claude.json > $H/.claude.json`.

**Pět pastí, o které se ta první sonda (#460) rozbila. Každá je změřená a každá umí vyrobit
falešné „dialog není“:**

1. **Název složky nesmí obsahovat hledané slovo.** Dialog vypisuje **pracovní adresář**, takže
   sonda ve složce `…/trustprobe/` najde svoje vlastní jméno a hlásí dialog i tam, kde není.
   Pískoviště se proto jmenuje neutrálně (`/private/tmp/p479run/w/a/b/c`).
2. **`claude` si při každém spuštění zapíše záznam do konfigurace.** Nad složkou, která je
   důvěryhodná (i přes předka), si ji **založí** s `hasTrustDialogAccepted: false`. Druhý běh nad
   toutéž cestou proto dialog nemá — konfigurace se musí obnovit **před každým během**, jinak
   sonda měří svoji vlastní stopu.
3. **Prázdný podstrčený `HOME` se zasekne na prvním spuštění** (výběr motivu) a k dialogu se vůbec
   nedostane. Do fixture patří **dokončený onboarding** — tedy všechny klíče z opravdové
   konfigurace kromě `projects`.
4. **Znění dialogu se mění.** V `claude 2.1.250` zní *„Quick safety check: Is this a project you
   created or one you trust?“* s volbami `No, exit` / `Yes, I trust this folder`. Hledaný řetězec
   **ověř na běhu, o kterém víš, že dialog mít má** (scénář „nic zapsaného“), ne z paměti.
5. **Hledá se jedno slovo, nikdy dvě.** TUI sází mezi slova sekvence pro posun kurzoru
   (`Quick^[[8Gsafety^[[15Gcheck:`), takže `grep` na `you trust` **nikdy** nenajde nic, i když
   dialog na obrazovce je. Použitelný je `safety`; a musí to být slovo, které není v cestě
   k pískovišti (past č. 1 z druhé strany).

**A šestá, kterou zaplatila tahle sonda:** pískoviště nesmí ležet uvnitř složky se sondou.
`/tmp` je na macOS symlink na `/private/tmp`, takže `rm -rf /private/tmp/p479` smaže i skripty
v `/tmp/p479` — sonda si tím smaže sama sebe a vypadá to jako selhání `expect`u.

Dvě věci, které se tímhle postupem daly změřit a bez něj by se hádaly:

- **Reprodukce na skutečné konfiguraci a skutečných cestách.** Do podstrčeného `HOME` se **zkopíruje**
  `~/.claude.json` (nikdy se do něj nepíše) a `claude` se pustí ve **skutečném** stromu review
  v cache. Tak se rozdíl „strom, jehož klon je `true`“ proti „strom, jehož klon je `false`“ ukázal
  na datech, která ten problém vyrobila, ne na vymyšlených.
- **Že cizí zápis nepřežije se dá vyloučit taky.** Do podstrčené konfigurace se během běhu zapsal
  značkový klíč (v `t = 1`, `6` a `15` s) — přežil ve všech třech případech, takže `claude`
  konfiguraci nepřepisuje ze snímku, který si vzal při startu.

**Co ověří jedině člověk na běžící aplikaci** (v harnessu ne, protože testovací host nedostane
aktivaci, takže nemá key okno — #392, #434 — a stisk nemá kam sednout):

1. `` ⌃` `` zásuvku vytáhne a schová; na domácí záložce se nestane nic.
2. V zásuvce běží login shell v checkoutu toho PR (`pwd`), s uživatelovým `PATH` (`which claude`).
3. `claude --resume <id>` v ní vypadá jako v Terminálu — kurzor, barvy, překreslení při **změně
   velikosti okna** i při tažení za horní hranu zásuvky (`TIOCSWINSZ`).
4. `⌃W` a `⌃C` uvnitř terminálu **nesáhnou na záložky** — `⌃W` maže slovo, `⌃C` přeruší běh.
   Tohle je ten test, kvůli kterému #459 mohlo dopadnout špatně.
5. Zavření okna s běžícím procesem se **zeptá**, a po `Ukončit` po sobě nic nenechá:
   `ps -o pid,ppid,command -p <pid shellu>` a `pgrep -f claude` nemají co vrátit.
6. Na české klávesnici funguje `⌃;`.
7. **`▶` v hlavičce dráhy v tabu `Průběh`** (#460): vytáhne zásuvku, **přepne na relaci té dráhy**
   a session v ní **naváže** — `claude` se rozjede a nabídne pokračování toho vlákna, ne nové.
   Po `exit` v relaci `▶` shell **pustí znovu** a starý výpis nad ním zůstane.
8. **Dvě session naráz** (#460 — tohle je ten stav, kvůli kterému se zadání měnilo): pusť review se
   dvěma reviewery, klikni `▶` u obou. V hlavičce mají být **dvě záložky** a přepínání mezi nimi
   nesmí ani jednu ukončit; puntík u běžící svítí, u doběhlé zhasne a u nenulového konce je
   **červený**. `` ⌃` `` k tomu přidá třetí relaci `shell` a **nepřepne** na ni.
9. **Do relace, ve které něco běží, se nesmí nic napsat**: pusť v ní `sleep 30`, klikni na `▶`
   a v terminálu nesmí přibýt ani znak; místo toho se zásuvka na tu relaci přepne a dole je věta.
10. **Zavření záložky PR zabije všechny relace, i tu, která nebyla vidět** — po zavření nesmí
    `pgrep -f claude` ani `ps` na PID těch shellů nic vrátit. Totéž při ukončení aplikace.
11. **Změna velikosti** (#460): rozměr do jádra dojede správně (změřeno, viz sonda níž), ale jak
    obsah po přesázení **vypadá**, se z harnessu přečíst nedá. Roztáhni okno i zásuvku nad běžícím
    `claude` a posuď, jestli se překreslí čitelně.
12. **Dotaz na důvěru ke složce se nesmí objevit** (#460, upraveno #479): klikni `▶` na PR, na
    kterém zásuvka ještě nikdy nebyla — `claude` se **nesmí** zeptat *„Is this a project you created
    or one you trust?“*. Od #479 k tomu patří i druhá půlka: `` ⌃` `` na PR, na kterém **review
    ještě neběželo** (zásuvka tedy startuje v bare klonu), a v shellu ručně napsané `claude` —
    dialog se nesmí objevit ani tam. Ověřit se to dá jedině spuštěním: dialog je interaktivní a do
    pty se v harnessu psát nedá.
13. **Session z `▶` se neptá na povolení u každého kroku** (`--permission-mode auto`) — a `⧉`
    kopíruje příkaz **bez** toho přepínače.
14. **Rolování** (#460): v holém shellu (`ls -R /usr/share | head -500`) kolečko roluje; **nad
    běžícím `claude` ne, a je to správně** — alternativní buffer scrollback nemá a `claude` si
    hlášení myši zapíná sám, takže se roluje uvnitř něj.

### `⌃Tab` a shift, který mění klávesu (#245)

**Shift u `⇥` nedělá modifikátor, dělá jinou klávesu.** `⌃⇥` doručí `characters == U+0009`, kdežto
`⌃⇧⇥` **`U+0019`** (backTab) — takže zkratka zapsaná jako `.tab` s `[.control, .shift]` nezabere
**vůbec**: žádná událost se s ní nepotká a v okně to vypadá, jako by tam nebyla. Zpětná zkratka
proto potřebuje `KeyEquivalent("\u{19}")`. **Není to past z #151**: tam byl problém v párování,
tady se klávesy doopravdy liší znakem a modifikátory se porovnávají přesně (`U+0019` s maskou bez
shiftu v pokusu taky nezabralo).

Změřeno dvakrát, protože jedno bez druhého nestačí:

- **v aplikaci** — `⌃⇧Tab` neudělal nic, `⌃Tab` přepnul; to řekne, **že** je něco špatně,
  ne co;
- **samostatným pokusem na 40 řádků** (`swiftc /tmp/…swift`) — okno se čtyřmi `NSButton`y
  (`⇥`/backTab × s shiftem/bez) a lokálním monitorem `keyDown`. Ten vypsal znaky obou událostí
  a které tlačítko zabralo. Tohle je ta odpověď, kterou z aplikace nevytáhneš.

**Zkratka nad textovým editorem se musí vyzkoušet nad skutečným editorem, ne odvodit.** V PRismu
jsou všechna čtyři místa tentýž `DraftTextEditor` (`TextEditor`, tedy `NSTextView`), takže stačí
změřit jedno a doložit, že jsou to tytéž komponenty. Postup bez klikání na souřadnice:

```bash
# fokus se dá nastavit přes accessibility — AXTextArea má AXFocused zapisovatelné
swift /tmp/prism-a-ax.swift focus AXTextArea 0
swift /tmp/prism-a-keys.swift "type:abc" "ctrl+tab" "wait:1.5" "shot:/tmp/f-01.png"
swift /tmp/prism-a-ax.swift textareas    # `\t` se vypisuje jako «TAB», takže je vidět i vložený tabulátor
```

Vyšlo z toho: `⌃Tab` přepne záložku i s kurzorem v editoru, **do textu nevloží tabulátor**
a nepřehodí fokus na jiný prvek — key equivalent tlačítka se vyhodnocuje dřív, než se klávesa
dostane k `NSTextView`. Kdyby to editor spolkl, byl by fallback `⌘⇧]` / `⌘⇧[`; nebyl potřeba.

**Že se stav pruhu doopravdy změnil, ukáže filmstrip.** Výřez pruhu záložek z několika snímků
složený pod sebe se přečte naráz a je z něj vidět celý okruh — z poslední záložky domů, dál na
první, a zpátky přes domů na poslední. Snímky se pořizují **uvnitř téhož skriptu**, který slot
vytáhl dopředu; snímek okna, které není vpředu, umí být z předchozího stavu (stalo se: snímek
tvrdil prázdný pruh nad oknem, které už dvě záložky mělo).

**Že je slot vpředu, se ověřuje před každým stiskem, ne jednou na začátku skriptu** (#245).
Aktivace se umí vrátit zpátky uprostřed posloupnosti a klávesy pak jdou do cizí aplikace: ze
čtyř snímků vyšel pruh nedotčený (a semafor na nich šedý, což je ta jediná stopa) a z předchozího
běhu vypadalo přepnutí, jako by šlo **opačným směrem**. Obojí byla porucha měření, ne aplikace —
po přidání kontroly `NSWorkspace.frontmostApplication` do každého stisku vyšla posloupnost napoprvé
a znovu. Šedý semafor na snímku proto znamená **zahodit celé měření**, ne hledat chybu v okně.

**Systémové záložky oken se nedají otestovat, jen změřit** — a měří se to na položkách nabídky
`Okno` z accessibility (`kAXMenuBarAttribute`), ne kliknutím do menu. Nad **dvěma** otevřenými
okny je `Sloučit všechna okna` i `Zobrazit další panel` zakázané, a to **i bez**
`tabbingMode = .disallowed`: schovaná titulková lišta dělá okno netabovatelným (`tabGroup == nil`
hned po vzniku, u obyčejného titulkového okna ho okno má). Obojí je změřené, protože z toho plyne
opačná věc, než by se čekalo — `.disallowed` je vyslovený záměr, ne to, co dnes dveře zavírá.
Zkoušet to nad **jedním** oknem nemá cenu: tam je ta položka zakázaná vždycky.

**Cena bloku se měří dvěma způsoby a je to schválně** (#223). Jeden blok podle délky je ten údaj,
ze kterého se vybírá strop — to je práce, kterou appka zaplatí i za blok, jehož je vidět kousek.
Celý soubor rozdělený na bloky je kontrola, **co rozdělení stojí**; v `ImageRenderer`u vyjde plochý
(150–280 ms bez trendu), protože offscreen render nic nelení. Přínos stropu proto z druhé série
vidět **není** a nesmí se z ní vyvozovat — plyne z lenosti `LazyVStack`u, kterou harness nemá jak
napodobit.

### Jak se změřil `--force-with-lease` (#466)

Zadání #466 říká výslovně: **ověř to spuštěním proti větvi, která se mezitím posunula, ne přečtením
dokumentace `gitu`.** Je to na tom celé podstatné — dokumentace popisuje, co lease dělá, ale
neodpoví na otázku, která tady rozhoduje: **chová se tak i v klonu, jaký si dělá tahle aplikace?**
Odpověď je *ne úplně*, a proto se ta hodnota posílá vypsaná.

Sandbox je `ondrajodas/prism-review-sandbox`, tentýž jako u #465. Postup má **čtyři pokusy** a klon,
který je naklonovaný **přesně jako ten aplikace** — bez toho by se ta odchylka neprojevila:

```bash
GH=$(which gh); export GIT_TERMINAL_PROMPT=0
BR=prism-lease-probe-466

# 1. „Autorský“ klon: odsud vznikne větev a později do ní strčí cizí commit.
git clone https://github.com/ondrajodas/prism-review-sandbox.git author
cd author && git checkout -b "${BR}" origin/master
echo probe > lease-probe.txt && git add . && git commit -m "probe: base"
git push origin "${BR}" && BASE=$(git rev-parse HEAD) && cd ..

# 2. Klon aplikace: bare, partial, refspec RUČNĚ (`clone --bare` ho nenastaví).
git clone --bare --filter=blob:none https://github.com/ondrajodas/prism-review-sandbox.git app-clone
git -C app-clone -c "credential.helper=!'${GH}' auth git-credential" \
    fetch --prune origin '+refs/heads/*:refs/heads/*'
git -C app-clone config --get-all remote.origin.fetch   # nevypíše NIC
git -C app-clone for-each-ref refs/remotes/             # je PRÁZDNÉ

# 3. Pracovní strom a commit, který „vypadl z rebase“.
git -C app-clone worktree add --detach "${PWD}/app-worktree" "${BASE}"
cd app-worktree && echo moje > mine.txt && git add . && git commit -m "probe: po rebase"
MINE=$(git rev-parse HEAD) && cd ..

# 4. Cizí ruka posune remote.
cd author && echo cizi > theirs.txt && git add . && git commit -m "probe: cizi" \
    && git push origin "${BR}" && cd ..
```

A teď ty čtyři pokusy — **v `zsh` musí být `${MINE}` ve složených závorkách**: `"$MINE:refs/heads/…"`
si `zsh` přečte jako modifikátor `:r` a z refspecu udělá `2bf096a…efs/heads/…`, což skončí `src
refspec … does not match any`. Stálo to jeden falešný „lease selhal“ hned v prvním kole.

```bash
push() {   # $1 = argument force
  git -C app-worktree -c "credential.helper=!'${GH}' auth git-credential" \
      push "$1" origin "${MINE}:refs/heads/${BR}"; echo "exit=$?"
  gh api "repos/ondrajodas/prism-review-sandbox/git/ref/heads/${BR}" --jq .object.sha
}
push "--force-with-lease=refs/heads/${BR}:${BASE}"     # zastaralá znalost
push --force-with-lease                                # HOLÝ lease
push "--force-with-lease=refs/heads/${BR}:${FOREIGN}"  # znalost, která sedí
push --force                                           # KONTRAST
```

| Pokus | Výstup `gitu` | Kód | Hlava na remote po pokusu |
|---|---|---|---|
| lease čeká `65aff25`, na remote leží cizí `9bb4352` | `! [rejected] … (stale info)` | **1** | zůstala cizí `9bb4352` |
| **holý** `--force-with-lease` | `! [rejected] … (stale info)` | **1** | nezměněna |
| lease čeká `9bb4352`, tedy to, co tam je | `+ 9bb4352…2bf096a (forced update)` | 0 | přetlačeno |
| **holé `--force`** s toutéž zastaralou znalostí | `+ f3e243e…2bf096a (forced update)` | 0 | **cizí commit zahozen** |

**Ten čtvrtý pokus je celý smysl měření.** Bez něj by první tři řádky říkaly jen „lease umí
odmítnout“; s ním je vidět, že v **téže** situaci holé `--force` cizí commit **zahodí**. To je ten
rozdíl, kvůli kterému je guard guardem a ne dekorací — a je to zrovna to, co by z dokumentace
`gitu` vyšlo jako věta, kterou se dá přeskočit.

**Druhý pokus je ten, který se nedal odhadnout.** Holý lease selhal i tehdy, když by hodnota sedla:
`git clone --bare` `remote.origin.fetch` nenastavuje, takže v tom klonu **žádný remote-tracking ref
neexistuje** a lease nemá odkud vzít očekávanou hodnotu. Kdyby se v aplikaci poslal holý, akce by
**nešla nikdy** — a v panelu by pro to nebyl důvod.

**Úklid**: probe větev se maže hned (`gh api -X DELETE …/git/refs/heads/${BR}`); v sandboxu zůstává
jedině `prism-sync-probe-466` (PR #9), na kterém je změřená
[poloha větve proti základu](architektura.md#poloha-větve-proti-základu-466--mergestatestatus-na-to-neodpovídá)
— je to doklad k tvrzení v dokumentaci, takže se nemaže.

**Poloha větve se měří dvěma dotazy vedle sebe**, a musí to být tytéž hodnoty:

```bash
gh pr view 9 --repo ondrajodas/prism-review-sandbox --json mergeable,mergeStateStatus,headRefOid
gh api graphql -f query='query($o:String!,$n:String!,$b:String!,$h:String!){
    repository(owner:$o,name:$n){ref(qualifiedName:$b){compare(headRef:$h){aheadBy behindBy status}}}}' \
  -F o=ondrajodas -F n=prism-review-sandbox -F b=refs/heads/master -F h=<headRefOid>
```

Naměřeno: `{"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE"}` proti
`{"aheadBy":1,"behindBy":1,"status":"DIVERGED"}`. **Jeden dotaz na tuhle otázku neodpovídá** —
a kdyby se měřil jen ten první, vyšlo by z něj, že větev srovnaná je.
