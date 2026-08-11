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
  screenshot běžící aplikace nad skutečným PR. Teď je hodnota 50 % a je ověřená obojím.

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

    Sonda proto snímkuje po 100 ms, dokud nenajde **dvě** změny, se **stropem 4 s** — a strop je
    to, co z čekání dělá tvrzení o **vteřinovém** taktu, ne jen o tom, že se něco někdy překreslí:
    rozvrh po dvou vteřinách posune změny na 4,0 s a 6,0 s, tedy za strop (ověřeno vloženou regresí
    `by: 2` — sonda viděla jednu změnu místo dvou). Ověřeno i druhou stranou: opakované
    `cacheDisplay` samo přepočty nestojí ani takt neposouvá (tělo se přes šest vteřin snímkování
    přepočítalo jednou), a odpočet v těle kontroly měřidla je na **desetiny vteřiny**, protože
    s celými by se text za 1,5 s změnil nejvýš jednou. Uplynulý čas se u toho měří **monotónně**
    (`ContinuousClock`, jako v `DiffPerformanceMeasurement`): termín odpočtu `Date` být musí, jinak
    by rozvrh netikal podle týchž hodin jako aplikace, ale strop sondy na nástěnných hodinách stát
    nesmí — přestavení hodin nebo korekce z NTP by ho posunuly.

    Co z toho platí pro **příští sondu nad `TimelineView`em**: pevný okamžik měření je vždycky
    závod s fází mřížky tiků, kterou určuje ukotvení rozvrhu (u nás termín, ne `.now`) — čeká se
    tedy **na jev se stropem**, ne na hodiny. A strop musí být z čeho spočítat: perioda × 2 +
    rezerva. Sonda, která by se místo toho jen „nechala doběhnout“, tvrdí to, co zrovna stihla.

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
aktualizuje a co se do něj musí zapracovat dřív, než se začne programovat.

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

- **`List` se offscreen nevykreslí vůbec** — je to AppKit tabulka a `ImageRenderer` místo
  ní nakreslí žlutý placeholder přes celé plátno. Nevypovídá to o aplikaci. Řádky se dají
  zkontrolovat tak, že se poskládají ručně do `VStack`u mimo `List`.
- **`GroupBox` se offscreen nevykreslí taky** — a na rozdíl od `Listu` beze stopy, takže to
  vypadá, že se stav vůbec nezobrazil. Stejná kategorie jako `.borderless`. Kde na kontrole
  záleží, se hodí vlastní rámeček (`background(…, in: .rect(cornerRadius:))`), který
  SwiftUI kreslí sám.
- **`Link` vyjde jako žlutý placeholder.** V aplikaci je v pořádku, offscreen ne.
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
| podíl word-diffu na skládání bloku (#153) | odpovídá na „ztuhlo to kvůli #153?“ — `DiffPairBlockContainer.show` na 27 blocích samých dvojic **79,1 ms**, z toho `WordDiff` **14,2 ms**, tedy **18 %** v nejhorším případě; skládání bloku je přitom jen část ceny scrollování |
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
