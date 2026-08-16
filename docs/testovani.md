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
- **`StreamParser`** — proti **všem** fixtures ze skutečných běhů, plus syntetické rozbité
  vstupy: nevalidní JSON, useknutý řádek, neznámý event, nález bez povinných polí, prázdný
  vstup. Fixtures ze skutečných běhů už v repu jsou
  (`Tests/Fixtures/stream-json/`, viz [`docs/claude-cli.md`](claude-cli.md)): běh
  s nálezy, čistý běh, zabitý běh a odmítnutý zápis. Parser se testuje proti nim.
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
- **Doplněný konec uložené osy (#242)** — sada, která vznikla z **měření, ne z návrhu**: uložená osa
  svůj konec neobsahuje (7 ze 7 os po skutečném běhu), takže tab po restartu tvrdil `nedoběhlo` nad
  doběhlým review. Testuje se, že se konec doplní z běhu, pod kterým leží, a hlavně to, co se
  doplnit **nesmí**: prázdná osa (z chybějícího průběhu by vznikl vymyšlený), fáze hlášení u běhu,
  který `ReportFindings` nezavolal, a druhý konec u osy, která ho má. Plus že identita událostí
  zůstane rostoucí a jednoznačná — zkrácená osa si nechává původní čísla, takže by doplněný konec
  podle počtu dostal číslo menší než jeho předchůdce. **Osy vyrobené v testech konec mají**, a proto
  to nechytil žádný z původních testů; nová sada proto skládá osu přes `stored()`, jak vzniká
  doopravdy. Ověřeno vložením regrese (9 padlých tvrzení).
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
- **`AppStore` — průběh** — pořadí událostí včetně konce běhu, že osa přežije doběhnutí,
  že nový běh začíná načisto a že se s PR mimo seznam zahodí. Plus detekce záměny skillu:
  načtený jiný, načtený správný a běh bez skillu (ten záměna není).
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
  K tomu klik na PR mimo seznam, který výběr nemění, a doručení bez centra, které si nic
  nezapíše. Čeká se **ohraničeně** (200 × 1 ms), ne neomezeným `Task.yield()` spinem: ten by
  běžel na `MainActoru` bez horní hranice, což položilo suitu u #68.

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
  vynucený režim by přetekl do render sond, které si režim nastavují samy. Vedle toho
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
  souboru nenajde žádný. Samotný sheet je `ScrollView` nad jedním `Text`em, takže se offscreen
  nevykreslí — viz past výš.

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
  a pruh záložek přes pásmo šířek 620–1020. Šest záložek se vejde na jeden řádek od ~920 bodů, pět
  od ~820 — pod tím se popisky **zalamují**, neřežou, a bylo to tak i před #215.

  **Od #306 je z toho renderu trvalá sonda** — `ChecksTabRenderProbe`, gatovaná `PRISM_MEASURE`
  jako `DetailTabRenderProbe` (do test hosta se pouští `TEST_RUNNER_PRISM_MEASURE=1`
  a `TEST_RUNNER_PRISM_RENDER_DIR`, jinak se proměnná k testu nedostane a suita se tiše přeskočí).
  Dělá dvě věci:

  - **detail PR v tabu `Kontroly` ve všech pěti podobách stavu** (nenačteno, bez CI, seznam, porucha,
    zastaralý seznam) ve dvou šířkách. Na jednom snímku je vidět obojí, na čem #306 stojí: že pruh
    má šest záložek pokaždé a že odznak je jedině nad seznamem. Pořadí ve scéně je podmínka:
    `loadDetail` si checky dotahuje sám, takže se **nastavují až po něm** — jinak by je přepsal.
    Během renderu už se nespustí (cache podle `updatedAt`), a právě proto se tudy dá vyrobit i stav
    „nenačteno“, ke kterému se v aplikaci normálním používáním vrátit nedá;
  - **pruh záložek přes pásmo šířek 620–1020, bez odznaků i se všemi**. Změřeno: bez odznaků se pruh
    vejde na jeden řádek od ~780 bodů, se všemi od ~920; pod tím se popisky **zalamují**
    a `+X −Y` se zalomí. Detail má šířku okna minus rail (53), takže ve výchozím
    okně 1100 je to bez dopadu a projeví se to u okna stáhnutého k podlaze (700). Tuhle cenu platila
    do #306 jen PR s CI, od #306 všechna — proto je to změřené, ne odhadnuté.

    **Oprava (návrh tabu `Commity`):** stálo tu, že se popisky *zkracují* (`Změněné soub…`).
    Nezkracují — `PullRequestTabBar` nikde nemá `lineLimit`, takže se popisek láme **uvnitř
    záložky** a pruh povyroste. Pásmo, od kterého se pruh vejde na jeden řádek, ta oprava nemění;
    mění to, co se stane pod ním.

    **Druhá oprava (#316), a tentokrát i těch čísel.** Hranice „~920“ výš je z repliky pruhu
    a z měření po stovkách; skutečný `PullRequestTabBar` se šesti záložkami a všemi odznaky se
    vejde na jeden řádek od tabu **884 b**, tedy od okna **937 b**. Naměřeno po jednom bodu šířky
    na `NSHostingView.fittingSize` — proti replice o 17 bodů výš. Sedm záložek a co je stálo drží
    `TabStripWidthTests` níž.

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
    `2 ze 7` v pořadí kresby a adresa commitu na GitHubu.
  - **Načítání ve store** (`AppStoreCommitDiffTests`) — sedm pastí. Že se **stažený diff drží**
    (druhé otevření téhož commitu se neptá znovu, jinak by z jednoho kliknutí byl polling), že se
    po selhání **ptá znovu** (jinak by `Zkusit znovu` nic neudělalo), že doběhlé volání **nepřepíše
    mezitím otevřený commit** (jinak by pod hlavičkou ležel cizí diff), že si návrat pamatuje
    **otevřený řádek**, že PR mimo seznam si diff nenechá — a dvě o klíči: rozbalení kontextu čte
    soubor **v tom commitu** (`fetchFile(repo:path:at:)`, a `fetchFile(id:path:)` se nesmí volat
    vůbec) a sbalení souboru se **nepropíše** do `Změněných souborů`.

    **Vyzkoušené vložením regrese, obojí zvlášť**: obsah tažený z hlavy PR položí test na ref, a
    `unfoldAll` bez filtru na commit položí test na sbalení.
  - **Šířka hlavičky** — dva další případy v `PanelFreeTabWidthTests` (pásmo 648–1800): hlavička
    s počty a **prázdný diff s vysvětlením**, protože to je jiný podstrom a hlavička v něm stojí
    bez počtů. Řádek meta se v úzkém okně musí zalomit přes `ViewThatFits`; kdyby se zvolila podoba
    na jeden řádek, přeteče tichá věta „Jen ke čtení…“ vpravo.
- **Šířka pruhu se sedmou záložkou (#316)** — `TabStripWidthTests`. Jediná věc, kterou tab
  `Commity` doopravdy stojí, a proto se měří, ne odhaduje: `NSHostingView.fittingSize` nad
  **skutečným** `PullRequestTabBar`em, po jednom bodu šířky.

  | Pruh | Šířka tabu, od které je jeden řádek | Okno (+ rail 53) |
  |---|---|---|
  | 6 záložek se všemi odznaky a `+X −Y` — `origin/main` před #316 | 884 b | 937 b |
  | **7 záložek se všemi odznaky, `+X −Y` ustupuje** | **886 b** | **939 b** |
  | 7 záložek bez odznaků | 729 b | 782 b |
  | 7 záložek se všemi odznaky a `+X −Y` (dopočet) | ~996 b | ~1049 b |

  Pilulka `+X −Y` stojí **110 bodů** (na `origin/main` 774 b bez ní, 884 b s ní) a sedmá záložka
  s odznakem **112** (886 − 774) — na té shodě stojí celý ten obchod. Sada tvrdí čtyři věci:

  - **od okna 940 zůstává pruh na jednom řádku** (pásmo 940–1400, mezi tím 1035, tedy hranice,
    kterou předpovídala specifikace **bez** té výměny);
  - **bez odznaků se vejde už od 785**, měřeno zvlášť — kdyby se odznaky počítaly vždycky,
    přehlédlo by se, že se pruh rozbil zrovna v tom nejběžnějším stavu;
  - **v okně 700 se pruh zalomí**, a je to tvrzeno schválně: kdyby někdo přidal `lineLimit(1)`,
    popisky by se začaly řezat, pruh by zůstal nízký a tenhle test zčervená. To je správně — je to
    jiná obrazovka, než jakou má návrh;
  - **v úzkém pruhu se `+X −Y` nekreslí, v širokém ano.** Obojí porovnáním dvou renderů (s počty
    a bez nich): shodné bitmapy znamenají, že tam pilulka není. Druhá půlka je stejně důležitá —
    bez ní by `ViewThatFits` mohl vybírat užší podobu pořád a #174 by tiše zmizela.

  **Měří se na `NSHostingView`, ne `ImageRenderer`u**: ten `ViewThatFits` vyhodnocuje jinak než
  skutečné okno, takže by test měřil něco jiného, než co je vidět.

  **Vyzkoušené vložením regrese**: po smazání druhé podoby z `ViewThatFits` (tedy toho, čím se
  sedmá záložka platí) padne pásmo **ve třech šířkách** — 940, 1000 i 1035 dá pruh o řádek nebo
  dva vyšší — a k tomu test na nekreslený `+X −Y`. Sada tedy měří přesně tu vlastnost, kvůli které
  vznikla.

  **Absolutní čísla ze specifikace se nepoužila** — měřila je replika pruhu a vyšla o 17 bodů níž
  (867/920 a 872/925). Rozdíl, o který jde, replika odhadla dobře (+5 bodů okna proti skutečným
  +2), ale hranice se z ní brát nedají.
- **Sonda tabu `Commity` (#316, rozšířeno #317)** — `CommitsTabRenderProbe`, gated `PRISM_MEASURE`.
  Nic netvrdí; vyrendruje **detail PR v tabu `Commity` ve všech podobách stavu** (nenačteno, seznam,
  porucha, zastaralý seznam, **PR s jedním commitem**, a od #317 **rozkliknutý commit** ve čtyřech
  stavech — diff, prázdný diff sloučení, nenačteno, porucha) ve dvou šířkách, seznam a diff commitu
  navíc v **tmavém režimu**, a k tomu **pruh se sedmi záložkami přes pásmo šířek** 647–1047 bodů
  tabu. Scénář drží commity
  v pořadí z API, takže je na snímcích vidět i to, že je tab **otáčí sám** — nejnovější nahoře,
  a mátová pilulka `hlava` s ním.

  Podob je pět, i když `CommitsTabState` má tři případy: `list` se kreslí dvakrát (se zastaralostí
  a bez ní) a `jeden-commit` je tentýž stav s jinými daty — je to ale zrovna to, co se z čísel
  nepozná, protože skloňování je vidět až v sazbě. **Prázdný stav mezi nimi není schválně**; na
  snímku `porucha` je vidět, že se prázdná odpověď hlásí jako porucha.

  **Stav diffu commitu se staví přímo do `commitDiffs`, ne přes `openCommit`** (#317): ten spouští
  `Task`, na který by render čekal, a rozdělaný stav (`nenacteno`) by se tudy nedal vyrobit vůbec.
  Rozkliknutý commit je ten **s tělem zprávy**, protože na jeho hlavičce je co posuzovat — u
  prázdného diffu naopak **sloučení**, protože právě u něj má věta jiné znění.

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
  z metriky **toho** fontu, kterým se kreslí (#236), takže se dá tvrdit přesná hodnota proti
  `NSLayoutManager`u. Co se dá pokazit potichu: **zastropovat i krátký log** (pod třířádkovým by zbylo
  441 bodů prázdna) a **nezastropovat dlouhý** (šest tisíc řádků naplno odtlačí seznam checků mimo
  obrazovku, tedy zrovna to, kvůli čemu se detail stěhoval z `Přehledu`). Regrese ověřená vložením
  regrese: vyndaný `min(limit, …)` položí sedm tvrzení.

  **Strop se v sadě bere z aplikace, ne opisuje** (#303) — jinak by se s ním test rozešel potichu.
  Tvrdí se u něj to jediné, co tvrdit jde: že padne na **celý počet řádků** (`14N + 21`) a že jich je
  30. Půlka řádku na spodní hraně by byla zrovna na tom řádku, kvůli kterému se log otevírá — okýnko
  se otevírá na konci.

  Je u toho **kontrola měřidla**: rezerva na vodorovný scroller je v kódu opsané číslo, protože
  `NSScroller.scrollerWidth` je vázaná na hlavní vlákno — test ji porovnává se systémem, aby se
  okýnko nemohlo potichu rozejít se scrollerem.

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

- **Sonda místa pro konec logu (#303)** — `CheckLogRoomProbe`, gated `PRISM_MEASURE`. Nic netvrdí;
  odpovídá na otázku „kolik po vyšším okýnku zbude na seznam checků“, a to **měřením v hierarchii**,
  ne odhadem: v rendrovaném tabu najde `NSScrollView` viewportu i okýnko logu (pozná se podle
  `documentView is NSTextView`) a vypíše, kolik bodů zbylo pod ním — a kolik je to řádků seznamu
  (výška řádku se bere **rozdílem dvou sazeb**, ne z konstant ve view).

  Dvě věci, které se u ní zaplatily. **Kandidáti na výšku se nerendrují jeden po druhém**: vše kromě
  okýnka je ve výšce pevné, takže z jednoho renderu vyjde konstanta a zbytek je odčítání. A **log musí
  dorazit až po prvním rozložení**, jako v aplikaci — když se text podá hned při stavbě hierarchie,
  okýnko zůstane na začátku ocasu, a to je vlastnost sondy, ne aplikace.

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
- **`CacheLayout` a sloty** (#228) — nejcennější test je ten, který tvrdí, že se něco
  **nestalo**: `CacheLayout(named: "PRism")` a `CacheLayout(named: "PRism-a")` se ptají
  `contains` na obě strany a ani jedna nesmí vidět do té druhé. Chytá to i past, do které by
  se spadlo připojením slotu bez oddělovače — `"PRism"` + `""` je pořád `"PRism"`.

  Ověřeno **vložením regrese**: když `init(named:)` jméno ignoruje a vždycky složí `PRism`,
  spadnou dva testy se čtyřmi issues. Bez toho by zelený běh nedokazoval nic, protože obě
  cesty vedou do `Application Support` a liší se jediným řetězcem.

  Zbytek slotů leží v shellu (`bin/run.sh`, `bin/worktree.sh`, `bin/slot-config.sh`) a testy ho
  nepokryjí, takže se ověřuje spuštěním: build se slotem musí vyrobit `com.ondrajodas.prism.a`
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

## Čekání na jev (#296)

Sem patří všechno, co v testu znamená „počkej, až se něco stane“. Je to **jedno místo**
(`Tests/Support/TestWaiting.swift`) a jsou k tomu tři primitiva:

| Co | Kdy | Strop |
|---|---|---|
| `waitUntil("jev") { podmínka }` | čeká se na jev, který nastat **má** | `TestWait.deadline` = 2 min |
| `settle()` | není na co čekat — tvrdí se, že se **nic nestalo**, nebo se čeká na zápis bez handle | bez stropu, 100 ms |
| `TestWait.pause()` | smyčka, která práci **drží** rozběhnutou, dokud ji test nepustí | bez stropu (držení stropovat nejde) |

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

**Ověřeno vložením regrese, čtyřmi:** vyndaný `requestKill()` v `SubprocessRunneru` (spadne
`RealEnvironmentTests` — „proces po zrušení pořád běží“), vyndaný `requestKill()` v
`SubprocessStreameru` (spadne `cancellationKillsTheProcess`), zamrzlý odpočet bez `TimelineView`
(spadne sonda odpočtu, viz níž) a rozvrh `by: 2` (spadnou dva testy `DashboardCountdownTests`
za 0,001 s).

### Co tím opravené není

**`AppStoreProgressTests` je flaky i bez zátěže**, a je to **jiná třída** — pořadí, ne čas, takže na
to strop nemá vliv a #296 to neopravuje. Měřeno samostatně (`-only-testing`), osm běhů: jeden pád,
za **0,038 s**, na `forgetsTheTimelineOfAPullRequestThatLeftTheList`. Kolega u #295 to samé viděl na
čistém `mainu` (tři různé kombinace pádů ve třech bězích, mimo jiné `Časová osa zůstane i po
doběhnutí`), takže to není z převodu na `waitUntil`.

Z hlášky je vidět mechanismus: osa dropnutého PR obsahovala `[queued, findings(0), finished]` —
tedy **bez** `.started`, který fake hlásí jako první, a s razítky ze dvou různých hodin (`queued`
v roce 1970 z `FakeTimeSource`, zbytek ve skutečném čase). To není přežilá osa, ale **nová**: události
průběhu dorazily až po konci běhu, `keepFresh()` mezitím osu zahodil (PR ze seznamu zmizel) a pozdní
události ji **postavily znovu**. Test pak vidí neprázdnou osu tam, kde má být prázdno.

Čekat na `!isReviewing(pr)` proti tomu nepomůže: `reviewTasks[pr] = nil` je v `defer`u `review()`,
takže „už neběží“ nastane dřív, než dojdou poslední události průběhu. Opravit se to dá jedině
rozhodnutím o tom, jestli **smí pozdní událost průběhu vzkřísit zahozenou osu** — a to je otázka na
`AppStore`, ne na strop v testu. Patří to do vlastního issue.

**Testovací host umře při startu** (`Early unexpected exit, operation never finished bootstrapping —
test runner exited with code 0 while preparing to run tests`). Zaznamenáno u #298 při třech
souběžných slotech; **v #296 se to nereprodukovalo** ani při třech clean buildech, takže o tom není
co tvrdit kromě toho, jak se to pozná: **žádná chyba kompilace, žádné `✘`, nespustil se ani jeden
test**, a druhý běh nad tímtéž commitem projde. Je to zátěž, ne rozbitý build — pustit znovu.
Odstranění spinů (#296 vyndalo 56 míst, která na `yield()` točila procesor) tomu podle všeho pomáhá,
ale **změřené to není**; kdyby se to vrátilo, tohle je záznam, u kterého se dá začít.

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
nedá (poměr sloupců, výška karty, kde končí proužek). Sekce se vyřízne do samostatného souboru,
protože stránka je dlouhá a `--screenshot` bere jen viewport.

**Kde ten mockup vzít, říká [`docs/navrh.md`](navrh.md)** — je to artifact, ne soubor v repu, takže
se stahuje `WebFetch`em (`curl` na něm dostane skořápku aplikace nebo 403). Tam je i to, jak se
aktualizuje a co se do něj musí zapracovat a nechat odsouhlasit dřív, než na to vznikne issue.

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
    --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,900 \
    --screenshot=mockup.png "file://$PWD/mockup-s01.html"
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
  v `NSHostingView` stačí přiřadit `NSApp.appearance` a nechat proběhnout runloop:
  `@Environment(\.colorScheme)` **se pohne spolu s paletou** — změřeno `AppearanceSwitchProbe`, které
  hostuje skutečný blok diffu a bere bitmapu před a po. To je odpověď na jedinou otázku, kterou se
  z kódu přečíst nedá: `Palette` se ptá `appearance.bestMatch(from:)`, kdežto obarvení kódu jde přes
  prostředí, takže kdyby se ty dvě cesty rozešly, vznikne okno s tmavým chromem a světlým kódem.

  Tři věci, bez kterých to nedává odpověď. **Vynuť si oba režimy** (nejdřív `.aqua`, pak
  `.darkAqua`), ne jen ten druhý — na tmavém stroji by „změnilo se to“ vyšlo pravdivě i tehdy, kdyby
  se nepřepnulo nic. **Vrať `NSApp.appearance` zpátky** (`defer`), protože v testech je to hostitel
  testů a vynucený režim by přetekl do ostatních sond. A **hostuj to, na čem záleží**: pozadí okna
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

## Jak změřit, že okno netuhne (#220)

Měřicí harness je `Tests/Diff/DiffPerformanceMeasurement.swift` a **v běžném běhu se nepouští** —
je za přepínačem:

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
| cena zápisu ploch pro tažení (#252) | `DiffRowFrames` s 4000 záznamy a blok o 120 plochách: **po řádcích 22,6 ms, naráz 1,40 ms** (16×). Je to ta kvadratická část — úklid je lineární v počtu záznamů, takže po řádcích se platí za každý |
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
  dvou různých sezení se nesrovnávají. Že cena projíždění roste s počtem otevřených záložek, je
  samostatné zjištění — #252 ho neřeší.

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
