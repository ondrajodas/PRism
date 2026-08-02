# PRism — návrh

**Datum:** 2026-07-31
**Stav:** návrh odsouhlasen, neimplementováno
**Repo:** `ondrajodas/PRism` (privátní)

## Účel

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje v nativním UI vedle
diffu.

Aplikace je **orchestrátor a prohlížeč**. Nemá vlastní review logiku — veškerá analýza
žije ve skillech. Aplikace rozhoduje, *kdy* spustit *který* skill a *kde*, odchytí
strukturovaný výstup a vykreslí ho.

## Co aplikace dělat nebude

- **Nikdy nic neposílá na GitHub.** Žádné komentáře, žádná review, žádné approve.
  Verdikt je návrh vykreslený v aplikaci. Tohle je tvrdá podmínka, ne zjednodušení pro
  v1.
- **Žádný vestavěný terminál v v1.** Odloženo (viz Co přijde později).
- **Žádný GitLab ani Bitbucket.** Jen GitHub, natvrdo. Předstírat opak by byla zbytečná
  abstrakce.
- **Není to náhrada CI.** Aplikace reviewuje kód, nespouští testy projektu.

## Rozsah v1

| Oblast | Rozhodnutí |
|---|---|
| Zdroj PR | `review-requested:@me` |
| Repozitáře | libovolné, ne pevný seznam |
| Spuštění review | tlačítkem (manuálně) jako default; auto režim se zapíná per repo |
| Reviewery | více skillů, běží nezávisle a paralelně |
| Model výsledku | paralelní názory — texty nálezů se mezi reviewery neslučují |
| Checkout | vlastní cache, partial clone, jeden git worktree na review |
| Oprávnění revieweru | read-only (bez nástrojů `Write` / `Edit`) |
| Sběr výstupu | `ReportFindings` tool cally ze `stream-json` event streamu |

## Architektura

Sedm modulů s jasnými hranicemi. Každý je samostatně testovatelný; tři, které sahají do
vnějšího světa, jsou za protokolem, aby se daly v testech nahradit fake implementací.

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI views  (PRList, DiffView, FindingsPanel)       │
└───────────────────────┬─────────────────────────────────┘
                        │ observuje
┌───────────────────────▼─────────────────────────────────┐
│  AppStore — drží stav, koordinuje, vynucuje limity      │
└──┬──────────┬──────────────┬───────────────┬────────────┘
   │          │              │               │
┌──▼───────┐┌─▼───────────┐┌─▼───────────┐┌──▼──────────┐
│GitHub    ││RepoCheckout ││ReviewRunner ││ReviewStore  │
│Gateway   ││             ││             ││             │
│(gh CLI)  ││(git)        ││(claude CLI) ││(disk)       │
└──────────┘└─────────────┘└─────────────┘└─────────────┘
                                  │ používá
                        ┌─────────▼──────────┐
                        │ Policy (čisté fce) │
                        │ Config (globální + │
                        │        per-repo)   │
                        └────────────────────┘
```

### 1. GitHubGateway

Obaluje `gh` CLI. **Aplikace nikdy nesahá na GitHub token** — autentizace je plně
delegovaná na `gh`, který credential už drží v keychainu. Tím z aplikace vypadne
ukládání tokenu, jeho obnova i revokace.

Zodpovědnosti:

- Vypsat PR ze konfigurovaného seznamu **zdrojů** (sources). Zdroj je jeden search
  dotaz. V1 má jediný zdroj (`review-requested:@me`); přidání týmových review requestů
  později je nová položka v konfiguraci, ne zásah do kódu.
- Sloučit a deduplikovat výsledky přes zdroje podle `owner/repo#number`.
- Načíst metadata PR: název, autor, `headSha`, `baseSha`, URL, `updatedAt`, stav.
  **Ve dvou krocích:** vyhledávání dá jen povrch (`PullRequestSummary`), protože
  `gh search prs` SHA neumí; `headSha` a `baseSha` přijdou až z `gh pr view` na konkrétní
  PR. Kdy se detail dotáhne, rozhoduje polling — ne gateway.
- Načíst diff pro zobrazení (`gh pr diff`) — jen k zobrazení, reviewery čtou skutečné
  soubory. Gateway vrací **syrový text**: unified diff není tvar, který by `gh` definoval
  (na rozdíl od `--json` polí), takže mu rozumí až parser v `App/Diff/`.

Polling v intervalu (default 60 s). Jeden search dotaz na zdroj a poll je hluboko pod
rate limitem GitHub search API pro autentizovaného uživatele.

### 2. RepoCheckout

Vlastní všechny pracovní kopie. **Nikdy nesahá na uživatelovy klony** — mohou být
rozdělané, na jiné branchi, nebo už mít vlastní worktrees.

```
~/Library/Application Support/PRism/
  repos/<owner>/<repo>.git          # bare, partial clone s --filter=blob:none
  worktrees/<owner>-<repo>-<pr>-<sha>/   # detached worktree na review
```

- První setkání s repem: `git clone --bare --filter=blob:none`. Bloby se stahují až na
  vyžádání, takže i velký monorepo se naklonuje v sekundách, ne v minutách.
- Na review: `git worktree add --detach <cesta> <headSha>`. Paralelní reviewery mají
  každý svůj worktree, takže si nemohou lézt do cesty.
- Uklízení: worktree se maže po dokončení jeho review; cache repa se zahodí, když se
  zavře jeho poslední PR, nebo podle LRU při překročení konfigurovaného limitu
  velikosti.

Klonování je v UI vidět jako vlastní stav `cloning` — u neznámého repa je reálně
citelné a je lepší to přiznat než se tvářit, že PR ještě není připravený.

### 3. ReviewRunner

Spouští jednu Claude Code session na skill a mění její výstup na nálezy.

```
claude -p "<prompt>"
  --output-format stream-json --verbose
  --allowedTools Read,Grep,Glob,Bash(git:*),ReportFindings
  --model <z konfigurace>
  cwd: <cesta k worktree>
```

- **Read-only z principu.** `--allowedTools` neobsahuje `Write` ani `Edit` a u `Bash`
  uvádí jen `git`. Ověřeno u #12, že záruka drží — ale stojí na něčem jiném, než návrh
  předpokládal: scope `Bash(git:*)` `Bash` **nezúží** (projdou i `ls` nebo `cat`)
  a v seznamu nástrojů session se objevují i nepovolené (`Write` a `Edit` tam jsou vždy). Neprojdou **měnící** operace: `touch`, `rm` i `Write` skončily
  odmítnutím a nic po nich nezůstalo. Read-only tedy drží nepovolením mutací.

  Hodnota `--allowedTools` je v ukázce **bez uvozovek** schválně: aplikace shell nepoužívá
  a `Process` dostává argumenty polem. Kdo si to zkouší v terminálu, uvozovky potřebuje —
  `*` by prošlo glob expansion a závorky jsou syntaktická chyba.

  Je to bezpečnostní vlastnost: reviewer nemůže změnit kód ani nikam nic poslat.
  Původní zdůvodnění „jinak by session visela na permission promptu do timeoutu“ **neplatí**
  — ověřeno u #12, že v headless režimu se nepovolený nástroj rovnou odmítne, běh pokračuje
  a skončí `success`; odmítnutí se objeví v `tool_result` a v `permission_denials`. Úzká
  sada nástrojů tedy nešetří timeout, ale tahy: reviewer neztrácí čas voláními, která
  stejně neprojdou.
- **`CLAUDE.md` daného repa se aplikuje zdarma**, protože cwd session je skutečný
  checkout. Konvence projektu tím platí, aniž bychom cokoli přenášeli.
- **`session_id` se ukládá** z init eventu streamu, i když v1 terminál nemá. Stojí to
  jeden string a drží to otevřené dvě cesty: budoucí vestavěný terminál, nebo tlačítko
  *zkopírovat `claude --resume <id>`*.
- Nálezy pocházejí z **`ReportFindings` tool callů** odchycených v event streamu —
  strukturovaný JSON, ne parsování prózy. **Fallback na parsování textu v1 není** (viz
  záznam rozhodnutí): nezavolaný nástroj je vlastní stav, ne důvod hádat nálezy z prózy.
- Každý běh má timeout podle hodin a jde zrušit. Paralelismus je globálně omezený
  (default 3 session), aby dávka PR nezahltila stroj ani účet.

  **Doplněno u #14:** timeout je 15 minut a hlídá ho `ProcessStreaming`, ne runner —
  vlastní proces je jediný, kdo umí eskalovat `SIGTERM` → `SIGKILL`, a runner by časovač
  duplikoval. Vytimeoutovaný běh si **nechává nálezy**, které do té doby dorazily, což je
  celý důvod, proč se stream čte průběžně. Limit souběhu drží `ReviewSlots` s frontou
  v pořadí příchodu; slučování stejného klíče leží nad ním, aby připojený požadavek
  nezabral druhý slot.

Běhy jsou klíčované `(repo, prNumber, headSha, skillId)`. Když přijdou nové commity,
změní se `headSha` a předchozí nálezy se označí jako **zastaralé** — nezobrazují se
tiše proti kódu, který už neexistuje.

### 4. ReviewStore

Persistence. `Codable` modely v JSON souborech pod Application Support, jeden soubor na
`(repo, pr, headSha)`. Zvoleno místo SwiftData proto, že dat je málo, přístupový vzor je
triviálně souborový a čistý `Codable` drží store nahraditelný v testech bez databáze.

**Doplněno u #15:** soubory leží pod `reviews/<owner>/<repo>/<pr>-<sha>.json` a zapisují se
atomicky. Store je **aktor** — dva skilly nad jedním commitem zapisují do téhož souboru
a bez serializace by si výsledky přepsaly. Nový head commit označí starší záznamy
`isStale`, ale **nemaže je**: jsou to historie a UI je ukazuje jako zastaralé. Záznamy PR,
který zmizel ze sledovaného seznamu, se uklidí po třiceti dnech — lhůta běží od zavření
(`closedAt`), ne od stáří záznamu.

### 5. Policy — čisté funkce, žádné I/O

Tady skončila otázka severity, a návrh **záměrně nevymýšlí vlastní škálu závažnosti**.
`ReportFindings` pole pro severitu nemá; má `category` (volný kebab-case slug
pojmenovávající *druh* problému) a `verdict` (`CONFIRMED` / `PLAUSIBLE`). Obojí jsou
skutečná data, která reviewer vyprodukoval.

- **Skupiny v UI jsou podle `category`** — pojmenování od reviewera, ne interpretace
  aplikace. Uvnitř skupiny se `CONFIRMED` řadí nad `PLAUSIBLE`.
- **Blokující příznak je jediný odvozený boolean:** nález blokuje, když
  `verdict == CONFIRMED` **a** `category ∈ blockingCategories`
  (default `correctness`, `security`, `data-loss`; konfigurovatelné).
- **Návrh verdiktu je mechanický:** existuje-li blokující nález → *Request changes*,
  jinak → *Approve*. Žádná agregační session, žádná další cena, nic k ladění v
  promptech.
- **Shoda je taky mechanická:** dva reviewery, kteří nezávisle nahlásí stejné
  `file:line`, se zobrazí jako jedna bublina s odznakem `2×`. Jejich texty se nikdy
  neslučují.

Důsledek, který je dobré říct nahlas: **žádný skill se nemusí přepisovat.** Sada
`blockingCategories` je jediný knoflík, kterým se doladí, co se považuje za vážné.

**Doplněno u #16:** návrh verdiktu má **tři** výsledky, ne dva — `approve`,
`requestChanges` a *žádný*. Ten třetí je celý smysl toho, že `clean` a `failed` jsou
rozlišené: z běhu se dá vyvodit „je čisto“, jen když doběhl, zavolal `ReportFindings`
a nic nezahodil. Nález z vytimeoutovaného běhu přitom pořád blokuje — session se
nedopočítala, ale co stihla nahlásit, je pravda. Zastaralý záznam nedá verdikt vůbec.
Shoda se počítá po **reviewerech**, ne po nálezech, a kategorie se porovnávají bez ohledu
na velikost písmen.

### 6. Config

Dvě úrovně, vyhodnocené globální → per-repo:

```
Globální: sources[], skills[], blockingCategories[], pollInterval,
          maxConcurrentReviews, model, cacheBudget
Per-repo: mode: auto | manual        # default: manual
          skills[]                   # override, např. vyhodit PHP skilly na Go repu
          blockingCategories[]       # override
```

**Nové repozitáře mají default `manual`.** Když jsou v rozsahu libovolná repa, neznámé
repo nesmí bez dozoru spálit celý panel Claude sessions; objeví se v seznamu a čeká na
tlačítko. `auto` se zapíná per repo tam, kde ho chci.

Skilly jsou per-repo z konkrétního důvodu: `oj-php-quality-check` na Go nebo TypeScript
repu nepřinese nic a session stejně zaplatíš. Autodetekce jazyka nastaví výchozí sadu
při prvním setkání s repem.

## UI

Tři oblasti. Zvolený tvar: diff v plné šířce s nálezy u kódu a tabbed panel pod ním.

```
┌────────────┬──────────────────────────────────────────────┐
│ seznam PR  │ chipy reviewerů (stav + filtr) │ verdikt     │
│ (míchá     ├──────────────────────────────────────────────┤
│  repa,     │ diff, plná šířka                             │
│  stav      │   bublina: blokující, code-review + security 2× │
│  review)   │ diff pokračuje                               │
│            ├──────────────────────────────────────────────┤
│            │ [ Nálezy · 9 ] [ Průběh ]                    │
│            │ tabulka: category │ reviewer │ file:line │ …  │
└────────────┴──────────────────────────────────────────────┘
```

- **Hlavní okno je seznam PR**, míchá repozitáře, každý řádek ukazuje stav review
  (`3 blokující`, `běží 2/3`, `čisté`, `ve frontě · clone`, `zastaralé`).
- **Diff dostane plnou šířku.** PHP na 120 znaků se vejde.
- **Nálezy jsou bubliny na svém `file:line`**, defaultně zapnuté, přepínatelné.
- **Nálezy bez řádku** (chybějící testy, architektonické poznámky) žijí v tabulce.
  Přesně proto tabulka existuje a nestačí samotné bubliny.
- **Chipy reviewerů dělají dvě věci:** stav (`✓ hotovo · 5`, `◐ běží`,
  `✕ vypnuto pro tento repo`) a filtr.
- **Verdikt je označený jako návrh** a není na něj navěšená žádná GitHub akce.
- **Tab Průběh** vykresluje živý `stream-json` event stream nativně — který soubor
  reviewer čte, jaký nástroj zavolal. Strukturované vykreslení, ne přeposílání ANSI.

### Diff (#18)

Diff je jediné, co z GitHubu přichází jako text a ne jako JSON, takže z něj někdo musí
udělat model. Dělá to `App/Diff/`: `DiffParser` a typy, na které překládá (`Diff`,
`FileDiff`, `DiffHunk`, `DiffLine`). **Není to osmý modul** — je to zobrazovací cesta,
protože diff nemá v doméně review jinou roli než být vidět.

- **Parser nikdy nevyhodí výjimku a nerozpoznaný řádek počítá.** Stejné pravidlo jako
  u `StreamParseru` a `droppedFindings`: diff, ze kterého kus tiše vypadl, vypadá jako
  úplný — a review se dělá právě nad tím, co je vidět.
- **Řádek se čte podle stavu (hlavička / hunk), ne podle prvního znaku.** Odebraný řádek
  začínající `---` je jinak k nerozeznání od hlavičky souboru, a `--` na začátku řádku se
  v kódu i v textu vyskytuje běžně.
- **Cesty se berou z `rename from`/`rename to` a `---`/`+++`.** Hlavička
  `diff --git a/… b/…` je u cest s mezerou nejednoznačná; slouží jen jako záchrana tam,
  kde ostatní řádky chybí — u binárních souborů a u přejmenování beze změny obsahu.
- **U binárního souboru se ukáže jen hlavička.** `gh pr diff` u něj místo hunků pošle
  `Binary files … differ`, takže není co vykreslovat.
- **Diff drží `AppStore`, cachuje se podle `updatedAt`** a zahodí se s PR, který zmizel
  ze seznamu.
- **Dlouhé řádky se zalamují, diff nescrolluje vodorovně.**
- **Navigace mezi soubory je skokové menu** v hlavičce diffu; soubory jdou pod sebou
  s ukotvenou hlavičkou, ne v odděleném seznamu vedle.
- **Jedna buňka líného seznamu = jeden řádek**, ne hunk. Viz záznam rozhodnutí.
- **Nálezy jsou spodní lišta**, rozbalená, se šipkou na sbalení. Diff je to, kvůli čemu
  je okno otevřené, takže o místo si říká seznam nálezů, ne obráceně.
- **Z nálezu se dá skočit do diffu** na jeho `file:line`.

Co v #18 **není** a má vlastní issue: rozbalení kontextu mimo hunk (#47, potřebuje obsah
souboru, ne jen diff) a obarvení kódu podle jazyka (#48).

### Rozbalení kontextu (#47)

Mezi hunky je skrytý kód a občas je potřeba vidět, co je o pár řádků vedle. Řeší to
rozbalovací řádky jako na GitHubu.

- **Obsah souboru se tahá `gh api repos/…/contents/<cesta>?ref=refs/pull/<n>/head`**
  s `Accept: application/vnd.github.raw`. Ověřeno na živém API: ref pull requestu projde,
  takže kvůli SHA není potřeba `gh pr view`. Pracovní kopie se použít nedá — diff se
  ukazuje dřív, než se cokoli klonuje.
- **Načítá se až na kliknutí** a drží se po souborech. Rozbalení je řídká akce.
- **Skryté úseky se počítají z hunků**, v číslech nového souboru. Staré číslo se dopočítá
  z posunu, který předchozí hunk nadělal (`old = new − shift`), takže rozbalený řádek má
  obě čísla stejně jako každý jiný kontext.
- **Úsek za posledním hunkem má neznámý konec**, dokud obsah nedorazí — kde soubor končí,
  z diffu vyčíst nejde. Rozbalovací řádek se proto ukáže i bez počtu a po načtení buď
  počet dostane, nebo zmizí.
- **Rozbalené rozsahy drží `AppStore`**, ne view: stejná past jako u diffu, view by je
  přelilo mezi pull requesty.
- **Smazaný a binární soubor rozbalovat nejde** — nový obsah neexistuje.
- **Ovládání jsou šipky vlevo**, v místě čísel řádků. `⌄` posune o krok dolů od hunku nad
  mezerou, `⌃` o krok nahoru od hunku pod ní; u úseku kratšího než krok je jedna šipka,
  která ho dorazí celý. Počet skrytých řádků je zároveň zkratka na celý úsek.
- **Rozbalená mezera slije hunky a hlavička `@@` mezi nimi zmizí.** Řádky pak jdou
  nepřetržitě za sebou a hlavička uprostřed nemá co oddělovat. Hlavička, pod kterou mezera
  nikdy nebyla, zůstává — u prvního hunku je jediné, z čeho se pozná, kde v souboru jsme.
- **`Zobrazit jen diff`** sbalí všechno zpátky. Ukazuje se jen tehdy, když je co sbalit.

### Bubliny nálezů (#19)

Nález visí u řádku, kterého se týká, jako review komentář u kódu.

- **Bublina pod svým řádkem**: pill kategorie, verdict, jméno revieweru, `summary`
  a rozbalitelný `failure_scenario`. Blokující nález má červený pruh po straně.
- **Shoda patří bublině, ne nálezu.** Odznak `2×` je jednou nahoře i se jmény; texty
  reviewerů jdou pod sebou a **neslučují se**.
- **Nález, jehož řádek v diffu není, nezmizí** — visí u hlavičky souboru a nabídne svůj
  řádek dotáhnout. Viz záznam rozhodnutí, je to **změna proti zadání #19**.
- **Přepínač `Bubliny`** v liště nad diffem; stav se pamatuje mezi spuštěními
  (`UserDefaults`, ne store — je to předvolba pohledu napříč pull requesty).
- **Skok z panelu nálezů míří doprostřed okna**, ne na horní hranu.

### Spodní panel (#20)

Domov přehledu nálezů a **jediné místo pro nálezy bez `file:line`** — chybějící testy,
poznámky k architektuře. Právě kvůli nim nestačí bubliny.

- **Taby `Nálezy · N` a `Průběh`** (druhý je zatím placeholder, #22). Panel je sbalitelný
  a výška se mění tažením za horní hranu; obojí přežije restart.
- **Tabulka**: kategorie · reviewer · místo · nález. Řadí se klikem na hlavičku, bez něj
  platí pořadí z `Policy` — tabulka nemá vlastní představu o tom, co patří nahoru.
- **Nález bez místa má v sloupci `—`.**
- **Klik na řádek** odscrolluje diff na místo nálezu a jeho bublina se na chvíli zvýrazní.

### Obarvení kódu (#48)

Vlastní pravidla v `App/Syntax/`, žádná závislost. Komentáře, řetězce, čísla, klíčová
slova a proměnné — tolik, aby se v diffu chytlo oko.

- **Jazyk se pozná z cesty**, neznámý soubor se nebarví. Obarvit něco podle cizích
  pravidel vypadá jako náhodné skvrny.
- **Barví se řádek po řádku, bez paměti.** Blokový komentář nebo řetězec přes víc řádků
  se obarví jen tam, kde začíná. Diff je útržek — mezi hunky chybí řádky, ze kterých by
  se stav dopočítal, takže držet ho napříč by barvilo podle textu, který v okně není.
  Po rozbalení kontextu by se navíc barvy měnily pod rukama.
- **Paleta je Darcula** (tmavý režim) a **IntelliJ Light** (světlý). Dvě nesourodá témata
  by při přepnutí režimu vypadala jako dvě různé aplikace.
- **Proměnné jen tam, kde je poznat syntaxe** (`$` v PHP a shellu). Ve Swiftu nebo Go by
  se musel rozumět kód, ne řádek.
- **Obyčejný text vlastní barvu nemá** — dědí ji z okolí, takže soubor bez rozpoznaného
  jazyka nevypadá jinak než ten s ním.

## Platformová rozhodnutí

- **SwiftUI**, target macOS 26, Xcode projekt v repu. Bundle id
  `com.ondrajodas.prism`.
- **App Sandbox je vypnutý.** Aplikace spouští `git`, `gh` a `claude` a zapisuje do své
  cache mimo sandbox kontejner. Je to osobní nástroj, ne submission do App Store. Pro
  lokální použití stačí ad-hoc podpis (`codesign -s -`); Developer ID podpis a
  notarizace by byly potřeba až pro distribuci.
- **Jeden app target, moduly jako složky.** Sedm modulů z architektury nejsou samostatné
  targety — žijí jako podsložky `App/`. Framework `PRismCore` by dal testům přístup
  bez launche aplikace, ale vynutil by `public` u každého typu, který se dotkne UI. To je
  daň za hranici, kterou u osobní aplikace nikdo nevymáhá. Testy vidí dovnitř přes
  `@testable import PRism` proti app targetu (`TEST_HOST`). Vyčlenit framework jde
  kdykoli později; opačný směr by byl dražší.
- **`project.pbxproj` je psaný ručně, zdroje jsou buildable folders.** Žádný XcodeGen ani
  Tuist — byla by to instalovaná závislost navíc kvůli souboru, který se po scaffoldu
  skoro nemění. `App/` a `Tests/` jsou v projektu `PBXFileSystemSynchronizedRootGroup`,
  takže obsah targetu vychází z filesystému: nový zdroják se nikam nezapisuje a v pbxproj
  nevznikají merge konflikty.
- **Jeden název `PRism` napříč vším** — repo, projekt, target, scheme, produkt
  (`PRism.app`), Swiftový modul i to, co vidí uživatel v Docku. Krátce existovala
  dvojice „technický `pr-review` + uživatelský `GitHub PR Review`“; sjednocení ji
  zrušilo, protože dvě jména pro jednu věc si musí každý pamatovat a nic tím nezískal.
  Název bez mezer navíc drží `bin/run.sh`, `TEST_HOST` a `killall` jednoduché.
- **Vlastní `Info.plist` místo `GENERATE_INFOPLIST_FILE`.** `CFBundleName` jde nastavit
  jen přes `PRODUCT_NAME` — `INFOPLIST_KEY_CFBundleName` Xcode tiše ignoruje. Po
  sjednocení názvů ten důvod odpadl a plist by šlo zrušit; zatím zůstává kvůli explicitní
  kontrole nad metadaty bundlu.
- **Swift 6 language mode od prvního commitu.** Aplikace bude žonglovat s podprocesy a
  souběžnými review běhy; strict concurrency zapnutá dodatečně by znamenala refaktoring
  hotového kódu.
- **Ad-hoc podpis** (`CODE_SIGN_IDENTITY = "-"`, styl Manual). Build nepotřebuje Apple
  účet ani tým, což drží `xcodebuild` reprodukovatelný na čistém stroji.
- **Binárky se musí hledat absolutní cestou.** GUI aplikace spuštěná z Finderu nedědí
  `PATH` z shellu, takže `gh`, `git` ani `claude` se podle jména nenajdou. Aplikace je
  vyhledá při startu (zkoušením známých míst — `/opt/homebrew/bin`, `~/.local/bin` —
  případně přečtením `PATH` z login shellu) a když některá chybí, ohlásí to jasnou
  chybou. Je to častý a matoucí způsob selhání; řeší se předem, ne dodatečnou
  diagnostikou.

## Chování při chybách

| Selhání | Chování |
|---|---|
| `gh` / `git` / `claude` nenalezen | Blokující chyba při startu s názvem chybějící binárky a jak ji nainstalovat |
| `gh` není přihlášený | Blokující chyba odkazující na `gh auth login` |
| Stav přihlášení `gh` se nepodařilo zjistit | Blokující chyba **odlišená** od nepřihlášení, se stderrem z `gh` — `gh auth login` by nepomohl |
| Clone nebo fetch selže | Řádek PR ukáže `checkout failed` se stderr z gitu, tlačítko na opakování |
| Session skončí nenulovým kódem | Běh označen `failed`, stderr uchován a zobrazitelný; ostatní reviewery to neovlivní |
| Session nevrátí žádné nálezy | Odlišeno od selhání: `čisté`, ne `failed` |
| Session překročí timeout | Zabita, označena `timed out`, částečné nálezy se zachovají |
| Chybný nebo chybějící `ReportFindings` | Rozlišený stav: `calledReportFindings == false` znamená, že se nálezy nemají kde vzít; nečitelné nálezy se počítají v `droppedFindings` |
| Rate limit | Backoff, zobrazit, kdy se polling obnoví |
| Offline | Dál se zobrazují cachované PR a nálezy, označené jako neaktuální |
| Nové commity během review | Běh dokončí proti svému `headSha`; výsledek se uloží a označí `zastaralé` |

## Testování

Tři moduly, které sahají do vnějšího světa, jsou za protokolem, takže většina systému je
testovatelná bez sítě, gitu i Claude.

- **Policy** — čisté funkce, vyčerpávající unit testy: odvození blokujícího příznaku,
  návrh verdiktu, detekce shody, řazení. Nic se nemusí mockovat.
- **Parsování streamu** — klíčový spoj. Nahrát skutečný `stream-json` výstup z reálných
  review běhů jako fixtures a testovat parser proti nim. Pokrývá init eventy,
  `ReportFindings` cally, chybný vstup, zkrácený stream.
- **Vyhodnocení konfigurace** — merge globální + per-repo, defaulty pro neznámé repo,
  autodetekce.
- **Slučování a dedup zdrojů** — stejný PR přicházející ze dvou zdrojů se objeví jednou.
- **GitHubGateway / RepoCheckout / ReviewRunner** — fake implementace v testech na
  úrovni aplikace; malý počet integračních testů ověří skutečné binárky proti
  scratch repu.

## Co přijde později

Záměrně mimo v1, a návrh drží každou z těch věcí levnou na přidání:

- **Týmové review requesty** — jedna další položka v `sources[]`.
- **Vestavěný terminál** (SwiftTerm + PTY) — `session_id` se už ukládá.
- **Sloučený verdikt přes reviewery** — dedup podle `file:line`, s nezávislým opětovným
  nalezením jako signálem důvěry. Dá se postavit nad týmiž uloženými nálezy; obráceně by
  to nešlo.
- **Škála `must fix / recommended / nit`** — pokud se seskupení podle `category` ukáže
  jako příliš hrubé, dá se explicitní severita přidat promptem vynucenou JSON obálkou
  nad tímto modelem, ne místo něj.
- **Notifikace** při dokončení review.

## Záznam rozhodnutí

| Rozhodnutí | Zamítnutá alternativa | Proč |
|---|---|---|
| Aplikace orchestruje, skilly analyzují | Review logika v aplikaci | Skilly to už umí a vyvíjejí se nezávisle |
| Konzumovat `ReportFindings` | Parsovat prózu review | Strukturovaná data se souborem, řádkem a verdiktem už existují |
| Manuální trigger, `auto` per repo | Auto na všem | Libovolná repa; cena a překvapení bez dozoru |
| Vlastní cache + partial clone | Použít uživatelovy klony; review jen z diffu | Nikdy nesahat na rozdělaný pracovní strom; reviewery potřebují skutečné soubory a `CLAUDE.md` |
| Read-only `--allowedTools` | Plná oprávnění | Bezpečnost, a headless session neumí odpovědět na permission prompt |
| Seskupit podle `category`, odvodit jeden blokující boolean | Vymyslet třístupňovou škálu severity | Používá skutečná data; nevyžaduje přepis skillů; škála se dá přidat později |
| Paralelní reviewery, mechanický odznak `2×` | Agregační session slučující nálezy | Nesouhlas mezi reviewery je informace; slučování stojí session a tu informaci zahodí |
| Nálezy klíčované `headSha` | Klíčované podle PR | Nové commity musí zneplatnit, ne tiše mást |
| Bez terminálu v v1 | SwiftTerm od začátku | `stream-json` vykreslený nativně je pro sledování lepší; zásah je vzácný |
| Jeden app target, moduly jako složky | Framework `PRismCore` + app | Framework si vynutí `public` u všeho, co vidí UI; hranici jde vyčlenit později |
| Název `PRism` všude | `pr-review`, `gh-pr-review`, dvojice technický + uživatelský název | Hranol rozkládá světlo na spektrum, appka rozkládá PR na nezávislé pohledy — pojmenovává to, čím se liší. `gh-` prefix je konvence pro rozšíření `gh` CLI a u nativní aplikace by mátl. Dvě jména pro jednu věc si musí každý pamatovat a nic nevynesla |
| Ručně psaný `project.pbxproj` + buildable folders | XcodeGen / Tuist | Nechceme instalovanou závislost kvůli souboru, který se skoro nemění; synchronizované složky odstraní důvod pbxproj vůbec editovat |
| `Preflight` nad `BinaryLocator`em, ne v něm | Locator dělá lokaci i `gh auth status` | Locator má umět jedno; „locator“ navíc nehledá přihlášení. `GitHubGateway` může `GhAuthCheck` znovu použít pro průběžný re-check, aniž by tahal lokaci binárek |
| `ToolPaths` s neoptional poli, které vzniknou jen po úspěšném preflightu | Optional cesty všude, kontrola u každého volání | Typ nese důkaz, že preflight prošel. Zbytek aplikace pak nemá kód pro stav „binárka chybí“, který nemůže nastat |
| Offline `gh` blokuje start | Pustit aplikaci dál a spolehnout se na offline režim | Spec offline režim slibuje, ale zatím neexistuje cache, ze které by se dalo něco zobrazit — `PollingService` drží poslední známá data jen v paměti, takže po studeném startu bez sítě je okno stejně prázdné. **Přehodnoceno u #6 a odloženo na #15** (persistence), kde teprve bude co ukazovat. Zjištění z #6, které to komplikuje: `gh auth status` bez dosažitelného GitHubu skončí **jedničkou**, tedy stejně jako nepřihlášený uživatel — gate pak radí `gh auth login`, které nepomůže. Než se to opraví, chce to pozorovat skutečný výpadek sítě; nedosažitelný `GH_HOST` je jen náhražka a hlásí „token je neplatný“ |
| „Nepřihlášený“ a „stav se nepodařilo zjistit“ jsou dva stavy | Jeden stav „gh nefunguje“ | První se spraví `gh auth login`, druhý ne — slití by uživatele poslalo špatným směrem. Stejný důvod jako u `čisté` vs. `failed` u review |
| Gate vypíše všechny problémy naráz + `Zkusit znovu` | První problém a restart po opravě | Tři chybějící binárky se vyřeší jedním průchodem, ne třemi spuštěními |
| Známá místa první, login shell jen pro zbytek a jen jednou | Vždycky přečíst `PATH` z login shellu | Známá místa pokryjí skoro všechny instalace bez spuštění procesu. Login shell umí být pomalý nebo zaseknutý na cizím `.zshrc`, takže je to fallback s timeoutem, ne první krok |
| `Environment` jako podpůrná vrstva | Osmý modul v tabulce architektury | Není to zodpovědnost v doméně review, je to přístup ke stroji, který si tři moduly sdílejí. Rovný seznam osmi položek by smíchal dvě různé úrovně |
| Blokující I/O podprocesu na vlastní `DispatchQueue`, navázané přes `async let` | `Task.detached`; child tasky v task groupě | Pool kooperativní konkurence má jen tolik vláken, kolik jader, a `readToEnd()` neumí čekat kooperativně — paralelní review by si vlákna vzájemně vyhladovělo. `Task.detached` navíc odvazuje práci od životního cyklu volání; child tasky strukturu drží, ale běží na tomtéž poolu, takže samotný problém neřeší |
| Doménové modely ve vlastní složce `App/Models/` | Nechat je uvnitř `GitHubGateway`, který je vyrábí | Staví na nich všech sedm modulů i views; příslušnost k jednomu z nich by byla libovolná a vynutila by import „gateway“ tam, kde se jen zobrazuje stav |
| `RepoID` a `PRIdentifier` se kódují na **jediný řetězec** | Objekt s poli `owner` / `name` / `number` | Jeden kanonický zápis pro disk, klíč slovníku i UI. Parsování a formátování je jedna dvojice (`LosslessStringConvertible`), kterou `Codable` jen používá — nemůžou se rozejít. `CodingKeyRepresentable` navíc udělá z `[PRIdentifier: ReviewState]` v JSONu objekt místo pole střídavých klíčů a hodnot |
| Parsování identifikátorů je přísné (neprázdné části, bez bílých znaků, číslo PR kladné) | Přijmout, co projde, a řešit to až u volání | Identifikátor jde rovnou do cesty na disku a do argumentů `gh`. Chyba se má chytit tam, kde vzniká, ne o tři vrstvy dál |
| `PullRequestState` je plochý výčet `open` / `draft` / `merged` / `closed` | `state` + `isDraft` bool, jak to vrací GitHub | V UI je z toho jeden odznak. Dvě pole by dovolila kombinace, které reálně nevzniknou (mergnutý draft), a každé místo, co stav zobrazuje, by je muselo skládat. Mapování ze `gh` je jednořádkové: otevřený a `isDraft` → `draft` |
| `ReviewState.checkoutFailed` odděleně od `failed` | Jeden `failed` pro všechno, co se nepovedlo | Selhaný clone se spraví tlačítkem opakovat, spadlá session ne. Stejný důvod jako `čisté` vs. `failed`: slití pošle uživatele špatným směrem. Vyplývá to i z tabulky *Chování při chybách*, kde jsou to dva řádky |
| `clean` je vlastní případ, vzniká jen přes `ReviewState.finished(findingCount:)` | `completed(findings: 0)` znamená čisté | Bez továrničky typ dovoluje dva zápisy téhož stavu a každé porovnání by muselo řešit oba. Továrnička je jedno místo, kde se to rozhoduje — a je čistá, takže se testuje bez čehokoli okolo |
| Fallback na parsování prózy v1 není | Když `ReportFindings` nedorazí, vytáhnout nálezy z textu | Původní návrh ho sliboval, ale spike u #12 ukázal, že nezavolaný nástroj má **jednu** pravděpodobnou příčinu: chybí v `--allowedTools`. To je chyba konfigurace, kterou má aplikace přiznat, ne obcházet hádáním z prózy — a hádání by navíc vyrobilo nálezy bez `category` a `verdict`, na kterých stojí `Policy`. Stav `unparseable` proto v `ReviewState` není |
| Zahozený nález se počítá (`droppedFindings`) | Tiše ho přeskočit | Bez čítače je „nález bez povinného pole“ k nerozeznání od „nic jsem nenašel“ — tedy od schváleného PR s neohlášenou chybou. Povinné je proto jen `summary`; scénář selhání smí chybět, ať se zahazuje co nejmíň |
| Stejný nález ze dvou volání se nezdvojí | Slučovat všechna volání appendem | Reviewer, který hlásí průběžně a na konci pošle kompletní seznam, je běžný vzorec — a duplicitní nález v tabulce vypadá jako dva různé problémy |
| `ReportedFinding` a `FindingVerdict` leží v `App/Models/` | Nechat je u parseru, který je vyrábí | Staví na nich `Policy` i `ReviewStore`; modul, který data vyrábí, si je nemá vlastnit — stejný důvod jako u ostatních doménových modelů. `FindingVerdict` se navíc jmenuje takhle schválně: slovo „verdikt“ potřebuje `Policy` pro návrh approve / request changes |
| Stream se čte defenzivně (`JSONSerialization`), ne přes `Codable` | Typované DTO jako u `gh` | U `gh` si `--json` polem říkáme, co má přijít, takže DTO popisuje kontrakt, který držíme. Stream `claude` je cizí formát, který se vyvíjí, a drtivá většina eventů aplikaci nezajímá — typované dekódování by padalo na věcech, které jsou jí lhostejné, a každá nová verze CLI by rozbila parser |
| Rozbitý řádek se spočítá, ne vyhodí | Nechat parser házet a řešit to výš | Proces se dá zabít uprostřed řádku. Jedna useknutá řádka nesmí zahodit nálezy, které už dorazily — a právě u zabitého běhu jsou částečné nálezy to jediné, co zbylo |
| „Nic jsem nenašel“ a „nereportoval jsem“ jsou dva různé stavy | Prázdný seznam pro obojí | Čistý běh `ReportFindings` **zavolá** s prázdným polem (ověřeno fixturou). Nezavolaný nástroj naopak znamená, že se nálezy nemají kde vzít — třeba proto, že `ReportFindings` chybí v `--allowedTools`. Slití by z chyby konfigurace udělalo „čisté review“ |
| `Finding` odděluje, co poslal reviewer, od toho, co doplnila aplikace | Jeden plochý typ | `reviewer` a `headSha` ve streamu nejsou a vědět je může jen aplikace. Oddělení drží zřejmé, co je cizí data a co naše — a `headSha` je tvrdá podmínka, takže nesmí být jen dalším volitelným polem vedle ostatních |
| Stav pracovní kopie je **jeden**, klíčovaný repem (`CheckoutState`) | Držet cestu ke kopii a stav řádku odděleně, každé s jiným klíčem | Bare klon je jeden pro celý repozitář. Dvě mapy — cesta podle repa, stav podle PR — si dokázaly odporovat: jedno PR hlásilo `clone selhal` nad klonem, který mezitím pro druhé PR téhož repa v pořádku vznikl, a selhání jednoho PR mazalo cestu i tomu, kterému se povedlo. `ReviewState` pro řádek i `busy` pro eviction se teď odvozují z jednoho stavu, překlad je čistá funkce v `Policy` |
| Při výběru řádku se stav srovnává podle disku | Doplnit cestu jen když chybí | Klon mohla mezitím sebrat eviction — ta maže podle LRU napříč cache, tedy i repo s otevřeným PR. Zapsaná cesta by pak ukazovala na složku, která neexistuje. Ověření je jeden `fileExists`, takže se dělá při každém výběru |
| `busy` se eviction předává jako **dotaz**, ne jako snímek | Odečíst množinu na začátku úklidu | Úklid je dlouhá disková operace (prochází celou cache). Příprava, která začne uprostřed něj, by o ochranu přišla a `git` by klonoval do složky, kterou mu eviction pod rukama maže |
| Hotová kopie se v řádku ukazuje jako `notStarted` | Přidat do `ReviewState` případ „kopie připravená“ | `ReviewState` popisuje **review**, a to se checkoutem nespustilo. Nový případ by odznak v řádku nutil hlásit něco, co o review nevypovídá; že je kopie hotová, patří do detailu. Souvisí s rozhodnutím, že `clean` vzniká jen přes továrničku — stavy tam nejsou od toho, aby se do nich vešlo všechno |
| Chyba checkoutu je vidět jako věta **i** jako výstup `gitu` | Ukázat jen jedno z toho | Věta řekne, co se stalo („Repozitář neexistuje, nebo na něj nevidíš“), výstup `gitu` řekne proč — a bez něj se u poloviny případů nedá rozhodnout, co dělat dál. Text je k vybrání, aby šel zkopírovat |
| Výběr řádku drží `AppStore`, ne view | `@State` ve view seznamu | Přestavění seznamu (nový poll, změna filtru) by výběr zahodilo. Stav, který má přežít překreslení, patří do store |
| Důvod prázdného seznamu je `PollState.emptyReason`, ne `if` ve view | Nechat view rozhodovat podle `pullRequests.isEmpty` a `status` | „Nejsou žádné PR“ a „nepovedlo se je načíst“ vypadají v okně stejně, ale znamenají opak. Bez pojmenovaného rozhodnutí se u červeného banneru svítilo zelené „Žádné PR k review“ se zaškrtnutím — nahlásil to Copilot na #7. Jako čistá vlastnost stavu se to dá vyčerpávajícím způsobem otestovat, ve view ne |
| Banner o čerstvosti dat se kreslí jen když něco nesedí | Trvalý pruh se stavem, i když je vše v pořádku | Pruh „vše OK“ ubírá místo seznamu a oko se ho naučí přehlížet — pak přehlédne i ten, který něco říká |
| Obsah okna zajíždí pod poloprůhlednou lištu | Zprůhlednění zrušit (`toolbarBackgroundVisibility`), nebo vypnout oknu `fullSizeContentView` přes `NSWindow` | Obojí vyzkoušeno a zahozeno. První nefunguje, protože nejde o barvu lišty, ale o to, že obsah sahá pod ni. Druhé funguje, ale odsune toolbar do vlastního pruhu a rozejde se s tím, jak se chová Mail i Finder — vlastní chování by na macOS působilo cize |
| Bundle deklaruje lokalizaci `cs` | Nechat `$(DEVELOPMENT_LANGUAGE)` a formátovat s explicitní `Locale` | Bez deklarované lokalizace spadne `Locale.current` na vývojový jazyk a relativní časy vyjdou anglicky vedle českých popisků. Předávat locale u každého formátování je stejná věc řešená na dvaceti místech místo jednoho |
| Odznak stavu review umí všech deset stavů hned | Placeholder, dokud nejsou reálná data | Texty (`běží 2/3`, `čisté`, `zastaralé`) určuje tahle specifikace, takže to není odhad. `completed` zatím ukazuje počet nálezů; kolik z nich blokuje, řekne až `Policy` |
| Selhání jednoho zdroje zahodí celý tik | Publikovat, co prošlo, a chybějící zdroj jen označit | Částečný seznam znamená, že PR ze selhaného zdroje z okna **zmizí** — a zmizelý PR vypadá jako vyřízený, ne jako nenačtený. Držet poslední úplný stav je jediná varianta, která uživatele neuvede v omyl |
| Backoff jen na rate limit, ne na síťové chyby | Exponenciální backoff na jakékoli selhání | Rate limit si aplikace způsobila sama tím, že se ptá moc — tam je zpomalení lék. Za výpadek sítě nemůže a delší čekání by jen oddálilo zotavení; jeden dotaz za 60 s offline nikomu neuškodí |
| `TimeSource` jako vlastní protokol, ne `Swift.Clock` | Konformovat testovací hodiny na `Clock` | Potřebujeme dvě věci: razítko pro UI (`Date`) a uspání, které jde v testu přeskočit. `Clock` k tomu přidává vlastní typ okamžiku a monotónní čas, které nikdo nepoužije, a konformance testovacích hodin je znatelně víc kódu než ty tři řádky, co ušetří |
| Stav pollingu je `PollStatus` + `lastSuccess`, ne case pro každou kombinaci | Vlastní případ pro „nedaří se a data máme“ vs. „nedaří se a nemáme nic“ | Kombinace „proč se nedaří“ × „je co ukázat“ by výčet zdvojnásobila. `lastSuccess: Date?` odpovídá na druhou otázku sám a `isStale` z toho dělá jedno pojmenované místo, takže view nic neskládá |
| Polling publikuje jen summaries, detail se netahá | Po každém tiku dotáhnout `gh pr view` na změněné PR | Seznam SHA nepotřebuje — potřebuje je až checkout a review. Dotahovat je předem znamená N podprocesů navíc za každý poll kvůli údaji, který se možná nepoužije. Zpřesňuje to rozhodnutí z #4: „kdy se detail dotáhne, rozhoduje polling“ zůstává, odpověď zní „až u spuštění review“ |
| Slučování zdrojů bere výsledky **po zdrojích** (`[[PullRequestSummary]]`) | Jeden plochý seznam, který si volající poskládá sám | Dedup by fungoval stejně, ale plochý vstup zahodí informaci, že šlo o několik nezávislých dotazů, a přenese spojování na každého volajícího. Typ tím říká, co se po něm chce |
| Při kolizi vyhrávají novější `updatedAt`, ne pořadí zdrojů | První zdroj v seznamu vyhrává | Zdroje se dotazují postupně, takže dřívější odpověď může nést stav, který mezitím zastaral. Pořadí zdrojů je konfigurační preference, ne informace o čerstvosti dat |
| Řazení má druhé kritérium (identifikátor) | Řadit jen podle `updatedAt` | Slovník, ve kterém dedup probíhá, nemá pořadí — při shodných časech by se seznam mezi pollingy sám přeskládával a řádky by uživateli poskakovaly pod rukou. Není to kosmetika, je to podmínka použitelnosti seznamu |
| `Source` je v `App/Models/`, slučování v `App/Policy/` | Obojí v `Config`; obojí v `GitHubGateway` | `Source` používá `Config` (odkud se bere), `GitHubGateway` (co se ptá) i UI (co se zobrazuje) — patří tedy mezi sdílené modely. Slučování je rozhodovací logika bez I/O, což je přesně definice `Policy` |
| Výchozí zdroj má v dotazu `is:open` | Jen `review-requested:@me`, jak to psala specifikace | Ověřeno: bez `is:open` vrací `gh search prs` i zavřené a mergnuté PR. Fronta k review by se plnila věcmi, se kterými se nedá nic dělat |
| Vyhledávání vrací `PullRequestSummary`, plný `PullRequest` až z detailu | Gateway po searchu sama dotáhne `gh pr view` na každý výsledek; prázdné SHA v modelu | Ověřeno proti `gh`: `gh search prs` `headRefOid`/`baseRefOid` neumí, jsou jen v `gh pr view`. Ze searchu tedy `PullRequest` postavit nejde. Dotahovat detail uvnitř gateway by z každého pollu udělalo N+1 podprocesů; kdy se detail dotáhne (typicky jen u PR se změněným `updatedAt`) je rozhodnutí pollingu, ne gateway. Prázdné SHA by rozbila tvrdou podmínku, že se nálezy klíčují `headSha` |
| Search dotaz se `gh` předává rozdělený na argumenty, ale s respektem k uvozovkám | Celý dotaz jako jeden argument; dělení jen podle bílých znaků | Ověřeno: `gh search prs "review-requested:@me is:open"` skončí `Invalid search query "review-requested:\"@me is:open\""` — `gh` bere každý argument jako jeden výraz a hodnotu s mezerou si uzávorkuje sám. Dělení naslepo je horší chyba než ta první, protože **nespadne**: z `label:"help wanted"` udělá `label:help` plus fulltextové `wanted` a vrátí úplně jiné PR (ověřeno na živém `gh`). Proto je z toho vlastní čistá funkce `GhSearchQuery` s vlastními testy, ne jednořádkový `split` uvnitř gateway |
| Chyby `gh` se klasifikují čistou funkcí nad `ProcessResult` | Předat volajícímu stderr jako řetězec; klasifikovat až v UI | Každý stav vede jinam: `notAuthenticated` chce `gh auth login`, `network` se spraví sám, `rateLimited` chce počkat. Rozpoznávání z textu je křehké, a právě proto patří na jedno místo bez I/O, kde se dá projet tabulkou skutečných hlášek. Exit kód rozliší jen chybějící přihlášení — `gh` na ně má vlastní `4` |
| Klasifikace chyb `gh` není v `Policy` | Přesunout ji tam jako čistou funkci | `Policy` je o verdiktech review. Parsování výstupu `gh` je znalost o `gh`, a ta má zůstat v `App/GitHub/` — jinak `Policy` postupně nasaje vokabulář všech tří CLI |
| Výstup `gh` se dekóduje do DTO a teprve mapuje | `Codable` doménových modelů čte rovnou `gh` JSON | `PullRequest` se kóduje na disk (`ReviewStore`), takže jeho `Codable` popisuje **uložený** tvar. Sloučení by znamenalo, že změna formátu `gh` mění formát dat na disku — a naopak, že `author.login` a velikost písmen ve `state` z `gh` prosáknou do persistence |
| `fetchDetail` ověří, že `gh` vrátil PR s číslem, na které se ptal | Věřit odpovědi; brát číslo z odpovědi | Identifikátor se bere z dotazu, protože `gh pr view` repo nevrací. Tichý rozchod čísla by naklíčoval nálezy cizímu PR — přesně tomu má klíčování `headSha` bránit |
| Fixtures jen z veřejných repozitářů | Nahrát skutečný výstup `review-requested:@me` | Ten obsahuje titulky firemních PR a jména kolegů. `cli/cli`, `cli/go-gh` a `ondrajodas/PRism` dají stejný tvar dat bez toho. Stav, na který se veřejná fixture nedá sehnat (zavřený nemergnutý PR), se testuje inline JSONem |
| `ProcessRunning` zůstává bez `cwd` a `env` | Rozšířit ho hned, jak žádá issue #4 | `gh` cílové repo předává přes `--repo`, cwd nepotřebuje. Parametr, který nikdo nenastavuje, by narostl do všech fake implementací dřív, než by k něčemu byl. Přidá se s `RepoCheckout` (#8), který ho použije. **Doplněno u #8: `environment` přibylo, `cwd` ne.** `git` potřebuje `GIT_TERMINAL_PROMPT=0`, jinak by podproces bez terminálu visel na dotazu na heslo do timeoutu; cílovou složku ale bere přes `-C`, takže pracovní složka procesu se pořád nemění a paralelní běhy se nemají jak přebít |
| Na konec podprocesu se čeká přes `terminationHandler` | `waitUntilExit()` na `ioQueue`, jak to bylo od #2 | Blokující čekání drží vlákno, takže na každý podproces připadala tři (dvě čtení a čekání). Když jich běží dost naráz — třeba při paralelních testech s reálným `gitem` — nemá si nové čekání kde spustit a volání uvízne. Projevovalo se to jako náhodně visící běh testů, ve kterém **všechny testy prošly**. Po změně jde sada pětkrát za sebou zeleně, před tím padal každý druhý až třetí běh. Týká se to i provozu: paralelní review spouštějí podprocesů víc než testy |
| Integrační test klonuje přes `file://` | Holá cesta k repozitáři | U holé cesty `git` vypíše `--filter is ignored in local clones`, udělá klon s hardlinky a přenosový protokol vůbec nepoužije — test by nejel tou cestou kódu, kterou pojede aplikace. Krátce se to zkoušelo obráceně, protože `file://` vypadalo jako příčina náhodně visící testovací sady; skutečné příčiny byly dvě jiné (viz řádek o `terminationHandler`u a `TemporaryDirectory` uvolněný ARC uprostřed testu). Po jejich opravě jde sada s `file://` pětkrát za sebou zeleně |
| Souběžná volání nad stejným klíčem spojuje `CheckoutCoordinator` | Nechat to na volajícím; zámek v souboru | Dvě review nad různými PR téhož repa spustí přípravu naráz a druhé volání by mohlo smazat složku rozběhnutého klonu prvního. Souběžný požadavek se proto k běžící práci **připojí** — výsledek je pro oba stejný, takže je to i to, co volající chce. Zámek v souboru by řešil i běh dvou instancí aplikace, což není případ, který má osobní nástroj řešit. **Tím se uzavírá mezera zapsaná u #8** |
| Worktree je klíčovaný `(PR, headSha)` | Klíčovat jen podle PR | Nálezy visí na `headSha`. Jeden strom na PR by znamenal, že nové commity přepíšou checkout pod běžícím review — a ten by dokončil analýzu proti jinému kódu, než pro který hlásí nálezy. Dva skilly nad stejným commitem strom naopak sdílejí |
| Chybějící commit se dotahuje přes `refs/pull/<n>/head` | `git fetch origin <sha>`, jak psalo issue | Ten ref má na GitHubu **každý** PR včetně těch z forků, takže stačí jedna cesta místo dvou (`sha` pro vlastní větve, ref pro forky). Fetch samotného sha navíc potřebuje na serveru povolené `allowAnySHA1InWant`, na což spoleh není |
| Po `worktree remove` následuje `worktree prune` | Spolehnout se jen na `remove` | Ověřeno, že `remove` administrativu po stromu uklidí sám — původní zdůvodnění („jinak by `add` na stejné jméno odmítl“) bylo **nepravdivé** a je opravené. `prune` tam zůstává kvůli stromům, které zmizely **bez** `remove`: pád aplikace nebo ruční smazání složky. `remove` navíc dostal `--force` dvakrát, protože zabitý `add` nechává zámek `initializing` a s jedním se na něm `remove` zasekne |
| `cat-file` běží s `GIT_NO_LAZY_FETCH=1` | Nechat `cat-file` být lokální kontrola, jak vypadá | Ověřeno: na partial klonu si `cat-file` chybějící commit **sám dotáhne z promisor remote**. Kontrola by tedy chodila na síť, s naším timeoutem a bez credential helperu, a dokumentovaná cesta přes `refs/pull/<n>/head` by se nikdy nespustila — commit by v klonu ležel bez refu, který ho drží |
| Credential helper dostane **každé** volání, které může sáhnout na promisor remote | Přidávat ho jen ke `clone` a `fetch` | Na partial klonu si bloby dotahuje i `worktree add`. Bez helperu skončí u privátního repa hláškou, kterou klasifikace zařadí jako `notAuthenticated` — uživatel se dozví „přihlas se“, i když přihlášený je |
| Použitelnost worktree se ověřuje `rev-parse HEAD` | Stačí existence složky | Stejná chyba jako u klonu, o patro níž: zabitý `worktree add` nechá rozkopírovanou složku se zámkem, kterou `fileExists` od hotové nerozezná. Reviewer by pak analyzoval uříznutý strom a nálezy by se naklíčovaly na `headSha` proti kódu, který v něm není — přesně to, čemu má klíčování bránit. Porovnání s `headSha` zároveň ošetří kolizi zkráceného sha v názvu složky |
| Nezdařený zápis značky dokončeného klonu je **chyba** | Polykat ho, jak bylo rozhodnuto u #8 | **Změna proti #8.** Tehdy chybějící značka znamenala jen klonování navíc. Od chvíle, kdy nad klonem visí worktrees, by ale příští `prepare` klon bez značky smazal a stromy pod ním by zůstaly bez repozitáře. Selhat hned je levnější |
| Zrušení posledního čekajícího zruší i sdílenou práci | Nechat práci doběhnout vždycky | `Task {}` v koordinátoru je neustrukturovaný, takže se sám nezruší, a `await task.value` na zrušení nereaguje — bez tohohle by zavření okna během klonu monorepa nechalo `git` běžet do timeoutu a `withTaskCancellationHandler` v `SubprocessRunner`u by byl mrtvý kód. Dokud čeká někdo další, práce pokračuje: rozdělaný klon je horší než klon navíc |
| `refs/prism/pr/<n>` maže eviction, když PR zmizí ze seznamu | Mazat ref hned při úklidu worktree | Ref kotví objekty commitu, na kterém strom stojí — smazat ho při úklidu jednoho stromu by odkotvilo objekty druhému stromu téhož PR, který ještě běží. Eviction naopak ví, které PR jsou pořád otevřené, takže maže jen refy, o které už není zájem. **Uzavírá mezeru zapsanou u #9** |
| Eviction se testuje proti skutečné dočasné složce, ne proti fake filesystému | Fake filesystém, jak psalo issue #10 | Rozpočet je injektovatelný, takže testům stačí soubory o stovkách kilobajtů — a zároveň se ověřuje skutečné chování `FileManageru` při počítání velikostí a mazání, což je přesně to, na čem eviction stojí. Fake by byl kus kódu navíc, který by ověřoval sám sebe. Daň: velikost se počítá **alokovaná** (po blocích), takže testovací rozpočty musí být řádově nad velikostí bloku |
| Repo s běžícím review je pro eviction nedotknutelné, i za cenu překročeného rozpočtu | Uvolnit místo za každou cenu | Smazat klon pod běžícím review by mu vzalo pracovní strom pod rukama a běh by skončil chybou uprostřed. Rozpočet je strop na místo na disku, ne důvod rozbít rozdělanou práci |
| Úklid běží po **každém** tiku pollingu, i po prázdném | Uklízet jen po tiku, který něco vrátil | Zavřené PR se poznají právě tím, že v odpovědi chybí. Tik, který nevrátil nic, tedy nese nejvíc informace o tom, co se dá zahodit |
| `lastUsed` leží **vedle** klonu | Uvnitř klonu, ať se smaže spolu s ním | Nejdřív bylo uvnitř, ale razítko se musí zapsat **před** klonováním — jinak rozklonované repo razítko nemá, v LRU vyjde jako nejstarší a eviction ho odstřelí uprostřed práce. `git clone` ovšem odmítne klonovat do složky, ve které už něco leží. Eviction razítko maže spolu s klonem |
| Úklid běží po každém **úspěšném** tiku, ne po každém | Uklízet po každém tiku | Prázdná odpověď je informace (PR zmizel ze seznamu), ale selhaná není. Po výpadku sítě zůstane seznam beze změny a při prvním tiku po startu je prázdný — uklidit po něm znamená smazat celou cache kvůli chvíli bez sítě |
| Na úklid se v tiku čeká, nespouští se odděleně | `Task.detached`, ať tik neblokuje | Ověřeno měřením: `CacheEviction.run` je nonisolated `async`, takže se podle SE-0338 nespouští na volajícím aktoru — práce s `FileManagerem` na hlavním vlákně neběží a čekání drží jen tik, ne UI. Deterministické čekání je navíc testovatelné. **Přehodnotit, až se zapne `NonisolatedNonsendingByDefault`** (Swift 6.2+), který nonisolated async funkce naopak nechá běžet na volajícím aktoru |
| Stromy jsou zanořené `worktrees/<owner>/<repo>/<pr>-<sha>` | Ploché `owner-repo-pr-sha` v jedné složce | Ploché jméno se nedá filtrovat podle prefixu: `keboola-kbc-` sedí i na `keboola-kbc-stacks-…`, takže úklid jednoho repa by sahal na stromy jiného — včetně repa, ve kterém běží review. A protože smazaný strom bez `worktree remove` nechá v klonu záznam, `worktree add` na té cestě by padal už napořád |
| Refy se vypisují `git for-each-ref`, ne čtením složky `refs/` | `FileManager` nad `refs/prism/pr` | Ověřeno: `git gc` (i `gc --auto`, které si `fetch` spouští sám) volné refy zabalí do `packed-refs` a složku smaže. Výpis přes `FileManager` by od té chvíle tiše nenašel nic — a to zrovna v dlouho žijící cache, tedy tam, kde na úklidu záleží nejvíc |
| Do rozpočtu se počítají klony **i stromy** | Jen bare klony | Klon je `--filter=blob:none`, takže materializované soubory leží ve stromech a bývají větší než klon sám. Měřit jen klony znamená hlásit rozpočet, který nemá vztah ke skutečné spotřebě disku |
| Stromy po starším commitu téhož PR se zatím neuklízejí | Porovnávat sha stromu s aktuálním `headSha` | Seznam z pollingu nese `PullRequestSummary`, a ten `headSha` **nemá** — `gh search prs` ho neumí (viz rozhodnutí u #4). Eviction tedy aktuální commit nezná. Uklidí se, až PR ze seznamu odejde; adresně to zvládne až ten, kdo review spouští (#17), protože ten sha zná |
| Dokončený klon se pozná podle **vlastní značky** v jeho složce | Odvodit to z obsahu klonu (`HEAD`, `config`, `refs/`) | Ověřeno: `git` zakládá `HEAD` i `config` **hned na začátku** klonování, takže po zabitém klonu složka vypadá jako hotový repozitář. Fetch nad ní dokonce projde — jenže `HEAD` zůstane `ref: refs/heads/.invalid` a chybí `remote.origin.promisor`, takže klon tiše přestane být partial a od té chvíle tahá všechny bloby. Nezdařený zápis značky přípravu neshodí: klon je použitelný a chybějící značka znamená jen klonování navíc |
| Bare klon a fetch se dělají přes `-C`, ne přes pracovní složku procesu | Nastavit podprocesu `cwd` | Pracovní složka je stav procesu; `-C` je parametr volání. U paralelních review nad různými repy je druhé bezpečné a první ne |
| Přihlášení ke `gitu` jde přes `gh` jako credential helper předaný v `-c` | `gh auth setup-git`; klonovat URL s vloženým tokenem | `gh auth setup-git` zapisuje do **globálního** git configu uživatele — do toho aplikace sahat nemá. Token v URL by znamenal, že ho aplikace drží, což je tvrdá podmínka proti. **Ověřeno proti skutečnému privátnímu repu:** s vynulovanými helpery (`-c credential.helper=`) a jen naším `!gh auth git-credential` klon prošel, bez `gh auth setup-git`. `gh` se volá absolutní cestou, protože helper spouští shell, který `PATH` z GUI aplikace nezdědil |
| Náš helper se **přidává**, existující se neruší | Vynulovat helpery a nechat jen `gh` | Na testovacím stroji sedí `credential.helper=osxkeychain` v systémovém configu a funguje. Zrušit ho by znamenalo vypnout uživateli fungující přihlášení a nahradit ho spouštěním `gh` u každého volání. Náš helper je záchranná síť pro případ, kdy je přihlášený jen `gh` |
| Fetch v bare klonu se dělá s explicitním refspecem | Spolehnout se na `remote.origin.fetch` z klonu | `git clone --bare` `remote.origin.fetch` **nenastavuje** (na rozdíl od běžného klonu i od `--mirror`), takže `git fetch origin` jen zapíše `FETCH_HEAD` a větve zůstanou tam, kde byly. Odhalil to integrační test proti skutečnému `gitu` — unit test s fake runnerem to odhalit nemohl, protože argumenty vypadaly rozumně |
| Cache je `~/Library/Application Support/PRism/` | `~/Library/Application Support/pr-review/`, jak stálo v issue #8 | Zbytek po starém názvu. Jeden název napříč vším platí i pro složku na disku |
| Prompt **není slash command** | `-p "/code-review …"`, tedy vyvolat skill lomítkem, jak počítal #14 | Ověřeno spuštěním: vestavěný `/code-review` doběhne `success`, ale `num_turns: 0`, žádný `tool_use` a nálezy jsou v `result` jako próza — `ReportFindings` nezavolá ani když se o něj prompt výslovně řekne. Sběr nálezů by tiše nefungoval, což je nejhorší možné selhání téhle aplikace. Prostý prompt, který si kontrakt řekne sám, nálezy vrací (13 tahů, 3 nálezy); totéž dělal spike u #12, jen to nebylo zapsané |
| `--disallowedTools` s `Bash(git push:*)` a `Bash(gh:*)` | Spolehnout se na `--allowedTools`, jak to bylo od #14 | **Oprava tvrdé podmínky.** `Bash(git:*)` povoluje **všechny** git příkazy včetně `push` — ověřeno, že se `git push` spustí. `origin` v cache přitom míří na skutečné repo a session dostává credential helper, takže reviewer uměl pushnout do uživatelova repozitáře. Zákaz povolení přebíjí a zabere i na `git push` s vypsanou URL; ověřeno proti skutečnému remote, na který nedorazil žádný ref |
| Repo s **běžícím review** je pro eviction nedotknutelné | `busyRepositories` jen ze stavu `preparing`, jak to bylo od #11 | Ochrana končila ve chvíli, kdy checkout doběhl — tedy přesně tehdy, kdy začalo review, které ten strom potřebuje. Odvozuje se to ze stejného místa jako doteď, jen se přidávají repa s běžící úlohou |
| Chyba checkoutu je stav **repa**, chyba GitHubu stav **PR** | Všechno do `CheckoutState` | Na selhaný klon narazí i druhé PR téhož repa a řeší se stejným tlačítkem. Nedotažený detail nebo zápis na disk je naopak problém jednoho PR — proto má `ReviewPhase` vlastní `failed` |
| Zrušené review **neuloží nic** | Uložit, co doběhlo | Rozdělané review je horší než žádné: v řádku by vypadalo jako hotové a návrh verdiktu by se počítal z poloviny reviewerů. Fáze se vrací tam, kde byla, ne do chyby |
| Zabití procesu se **zapamatuje, když ještě neběží** | `signal(SIGKILL)`, jak to bylo od #14 | Zrušení umí dorazit v okně mezi nastavením handleru a `process.run()`. `SIGKILL` tam nemá koho zabít, takže proces naběhl osiřelý a doběhl do konce. Projevilo se to jako padající test pod zátěží — v provozu by to byla session běžící po zavření okna |
| Návrh verdiktu umí **nic nenavrhnout** | Vždycky vrátit `approve` nebo `requestChanges`, jak psalo issue | Bez třetího výsledku by PR, u kterého reviewer spadl, vyšel jako schválený — a to je nejdražší chyba, jakou tahle aplikace umí udělat. `nil` je vlastní odpověď, ne opatrné `approve`; UI z něj udělá „není z čeho soudit“ |
| Nálezy se berou ze **všech** běhů, i ze spadlých | Nezapočítávat nálezy ze spadlých běhů, jak se dá číst issue („failed běhy se nezapočítávají“) | Selhal *běh*, ne nález: ten dorazil jako celý `ReportFindings` call a rozbité parser dovnitř nepustí. Rozhodl mixovaný případ — spadlý reviewer s nahlášenou ztrátou dat **vedle** jednoho čistého běhu by po filtrování vyšel jako `approve`. „Nezapočítávají se“ tedy platí pro důkaz **čistoty**, ne pro nálezy |
| Za důkaz čistoty se bere jen běh, který **doběhl, reportoval a nic nezahodil** | Stačí, že běh doběhl | Každá z těch tří podmínek pokrývá jiný způsob, jak se „nic jsem nenašel“ splete s „nemám co říct“: zabitá session, nezavolaný `ReportFindings` (nástroj chyběl v `--allowedTools`) a nález, který se nepodařilo přečíst. Teprve tímhle dostávají `calledReportFindings` a `droppedFindings` konzumenta, kvůli kterému se ukládají |
| Kategorie se porovnávají bez ohledu na velikost písmen | Porovnávat přesně, jak přišly | Je to volný slug od reviewera, ne výčet. `Data-Loss` proti `data-loss` by znamenalo PR s hlášenou ztrátou dat, který nic neblokuje — a v UI dvě sekce téhož |
| Řadí se podle toho, jestli je **kategorie** blokující, ne jestli blokuje **nález** | První kritérium `isBlocking(finding)` | Kategorie, ve které je `CONFIRMED` i `PLAUSIBLE`, by se rozpadla na dvě sekce se stejným názvem. Blokující kategorie nahoře je přitom to, co se hledá první — a žádná nová škála z toho nevzniká |
| Shoda se počítá po reviewerech | Počítat nálezy ve skupině | Jeden reviewer, který na jednom řádku najde dvě různé věci, si nepřikyvuje — odznak `2×` má znamenat dva nezávislé názory |
| `ReviewVerdict` **není `Codable`** | Nechat ho jako ostatní modely | Neukládá se; odvozuje se z uložených nálezů, takže by `Codable` popisoval tvar, který na disku nikdy není — a byla by to netestovaná plocha |
| `isStale` se **ukládá**, neodvozuje z aktuálního `headSha` | Porovnat záznam s hlavičkou PR až při zobrazení | Odvození je bezpečnější jen zdánlivě: aktuální `headSha` aplikace z vyhledávání **nedostane** (`gh search prs` ho neumí, viz rozhodnutí u #4), takže v okamžiku zobrazení ho zpravidla nezná. Zná ho ve chvíli, kdy si dotáhne detail — a právě tam se příznak nastaví. Aby se na to nedalo zapomenout, stárnutí spouští `save` i `markCurrent` |
| Lhůta na úklid běží od **zavření**, ne od stáří záznamu | Mazat záznamy starší než 30 dní | PR otevřený půl roku by o historii přišel v okamžiku, kdy se zavře — tedy přesně tehdy, kdy se k nálezům člověk vrací. Stojí to jedno pole (`closedAt`) a jeden zápis, když PR poprvé zmizí ze seznamu |
| `ReviewStore` **není za protokolem** | Protokol + fake, jako `GitHubGateway`/`RepoCheckout`/`ReviewRunner` | Ty tři jsou za protokolem proto, že mluví s cizími binárkami a sítí. Store mluví s vlastním souborem ve vlastní složce, jejíž kořen je injektovatelný — fake by tedy ověřoval sám sebe místo `Codable` cesty na disk. Stejná úvaha jako u `CacheEviction`, kde se osvědčila |
| Uložené výsledky leží pod `CacheLayout`, ne pod vlastním kořenem | Vlastní typ s vlastní cestou v `ReviewStore` | `CacheLayout` je to jedno místo, které ví, co kde leží; druhý typ s vlastním kořenem by se s ním mohl v kořeni rozejít. Eviction se přitom `reviews/` nedotkne — chodí adresně po `repos/` a `worktrees/` |
| Ukládá se **jedno** razítko (`finishedAt`) | Začátek i konec běhu, jak psalo issue („časy") | `ReviewRun` začátek nenese a protahovat čas přes celý runner jen kvůli razítku by znamenalo závislost na hodinách v každé vrstvě. Co UI potřebuje, je „jak staré je tohle review"; délku běhu má `result` event, takže se dá doplnit, až o ni bude zájem |
| Do souboru se neukládají pokusy o nástroje | Uložit `attemptedTools` a `deniedTools` pro tab Průběh | Tab Průběh je o **běžící** session; po restartu se k ní stejně nedá vrátit. Soubory by rostly o data bez konzumenta. `droppedFindings` a `calledReportFindings` se naopak ukládají — na nich stojí rozdíl mezi „čisté" a „nálezy se nemají kde vzít" |
| Streamování výstupu je **vlastní protokol** `ProcessStreaming` | Další metoda na `ProcessRunning`, jak psalo rozhodnutí u #2 | **Změna proti #2.** Fake implementace `ProcessRunning` jsou u `gh` i `git` v každém druhém testu; metodu, kterou nikdy nezavolají, by musely dopsat všechny. Volající je přitom jediný — `ReviewRunner`. Vedlejší efekt, který rozhodl: `workingDirectory` (které `claude` potřebuje a `git` ne) tak zůstalo mimo bufferovanou cestu, místo aby se do ní přidal parametr, který nikdo nenastavuje |
| Selhání session je **výsledek**, ne vyhozená chyba | `ReviewRunner` vyhodí typovanou chybu, jako to dělá `RepoCheckout` | `čisté` a `failed` se nesmí slít, a chyba vyhozená z volání se do stavu překládá až u volajícího — tam, kde se to dá zapomenout. Vrácený `ReviewRun` s `outcome` nese navíc to, co se u chyby ztrácí: částečné nálezy z vytimeoutovaného běhu. Vyhozený zůstal jen `CancellationError`, protože zrušení není výsledek |
| Slučování stejného klíče je **nad** frontou slotů | Nejdřív slot, pak slučování | Připojený požadavek by jinak zabral druhý slot pro běh, na který sám čeká — při limitu 3 by tři takové dvojice frontu zablokovaly úplně |
| `CheckoutCoordinator` se přejmenoval na `WorkCoordinator` a přesunul do `App/Support/` | Napsat slučování běhů znovu uvnitř `ReviewRunneru` | Logika kolem rušení posledního čekajícího je jemná a už jednou draze odladěná; druhá kopie by se rozešla. Název podle prvního uživatele přestal platit ve chvíli, kdy má uživatele dva |
| Průběh dostává **ten, kdo běh spustil** | Rozeslat průběh všem, kdo se ke klíči připojili | Registr posluchačů na aktoru by hlásil události přes hopy, takže by o jejich pořadí rozhodovalo plánování, ne stream — a v tabu Průběh je pořadí to hlavní. Připojený požadavek dostane výsledek; průběh sleduje ten, kdo o běh požádal, a v aplikaci je to vždycky tentýž `AppStore` |
| Credential helper se session předává přes `GIT_CONFIG_*` | Nechat nested `git` bez přihlášení | Pracovní strom stojí nad partial klonem, takže `git diff` proti base commitu si dotahuje bloby ze sítě. `-c` z `RepoCheckoutu` sem nedosáhne — `git` spouští sám reviewer, a proměnné prostředí jsou jediná cesta, jak mu config podstrčit. Přidává se, existující helpery se neruší. **Ověřené to zatím není**; potvrdí to až první běh nad privátním repem |
| Diff se tahá `gh pr diff` | Vygenerovat ho `git diff` v pracovní kopii, která stejně vzniká kvůli review | Zobrazuje se **PR**, ne stav lokální kopie. Worktree v tu chvíli zpravidla neexistuje — diff se čte dřív, než se cokoli klonuje, a klonovat repo kvůli prohlédnutí diffu je nepoměr. `git diff base...head` by navíc proti GitHubu mohl dát jiný rozsah, protože base commit se pod PR mění |
| `App/Diff/` je vlastní složka, ne součást `Policy` | Přidat parser k ostatním čistým funkcím do `Policy` | `Policy` je **rozhodování** nad daty (co blokuje, co navrhnout, jak řadit) a testuje se jako pravidla. Parser je překlad cizího formátu na model — stejná kategorie jako `StreamParser`, který taky žije u svého konzumenta. Kdyby se do `Policy` slilo všechno čisté, přestane být poznat, co se v ní hledá |
| Nerozpoznaný řádek se **počítá a je vidět** | Přeskočit, co parser nezná | Diff s vynechaným kusem vypadá jako úplný a nic v okně neřekne, že se kouká na neúplný podklad. Stejné pravidlo jako u `droppedFindings`: ztráta, kterou nikdo nevidí, je horší než hlášená ztráta |
| Řádek se zařazuje podle **stavu** (hlavička / hunk) | Rozhodovat podle prvního znaku, jak to dělá většina jednoduchých parserů | Odebraný řádek `--- a tady něco` je pak k nerozeznání od hlavičky `--- a/soubor` a diff se rozpadne přesně tam, kde se mluví o diffech. Uvnitř hunku znamená `-` vždycky odebráno; hlavičky se čtou jen mezi soubory |
| Cesty z `rename from`/`---`/`+++`, hlavička `diff --git` jen jako záchrana | Parsovat cesty z hlavičky `diff --git a/… b/…` | Hlavička je u cest s mezerou nejednoznačná (`a/x y b/z` jde rozdělit víc způsoby), kdežto `rename from`, `rename to`, `---` a `+++` nesou vždycky právě jednu cestu. Hlavička zůstává jen tam, kde ostatní chybí — u binárek a přejmenování beze změny obsahu |
| Diff se cachuje v paměti podle `updatedAt` | Načíst při každém výběru řádku | Přepínání mezi PR je nejčastější pohyb v okně a každé by jinak stálo podproces a kolo po síti. `updatedAt` je jediné, co seznam o čerstvosti ví — mění se i po komentáři, takže občas načte zbytečně. Opačná chyba (ukázat starý diff k novému commitu) je dražší |
| Diff drží `AppStore`, ne view | `@State` v `PullRequestDetailView` | Stejná past jako u checkoutu: SwiftUI si detail mezi PR ponechá (stejná pozice ve stromu), takže by diff přetekl z jednoho PR na druhý. Ve store se navíc zahodí spolu s ostatním stavem, když PR vypadne ze seznamu |
| Dlouhé řádky se zalamují | Vnořený vodorovný `ScrollView` | 120 znaků se do plné šířky vejde — kvůli tomu diff plnou šířku dostal — takže zalomení potká výjimku, ne pravidlo. Vodorovný scroll uvnitř `LazyVStack`u navíc nutí měřit nejširší řádek, aby podbarvení nekončilo u každého řádku jinde; to je cena za případ, který skoro nenastává |
| Buňka líného seznamu je **řádek**, ne hunk | Vykreslit hunk jako celek (hlavička + jeho řádky v jedné buňce) | Ukázalo se to při zvětšení okna: buňka vytvořená při jiné šířce se sama nepřeměří, takže se překreslila jen zčásti a mezi hlavičkami hunků zůstala prázdná místa. Řádek jako vlastní buňka to nemá kde udělat. Vedlejší přínos: skok z nálezu má na co ukázat |
| Diff **nejde označit myší** | `.textSelection(.enabled)` nad obsahem diffu | Zkoušeno a zahodeno spolu s předchozím: výběr textu nad tisíci `Text`y v líném seznamu je druhý známý zdroj nevykreslených řádků na macOS. Kopírování kódu z diffu si nikdo nevyžádal, prázdná místa v diffu vadila hned |
| Nálezy jsou **sbalitelná spodní lišta**, ne polovina okna | Posuvné dělítko (`VSplitView`) mezi diffem a nálezy | Rozdělené okno dalo diffu čtyři řádky a zbytek seznamu nálezů, kterých bývá pár. Lišta ukazuje pořád to podstatné (návrh verdiktu, počet nálezů, stáří) a seznam si o místo řekne kliknutím. Rozbalená je defaultně — po doběhlém review se nálezy mají nabídnout, ne schovat |
| Proklik z nálezu do diffu je už v #18 | Nechat ho na #20 podle rozpisu milníku | Panel nálezů bez odskoku znamená hledat `file:line` očima ve dvou tisících řádcích. Je to jedna čistá funkce (`DiffRow.anchor`) nad řádky, které stejně vznikají — odkládat to znamenalo dvakrát otevírat totéž místo |
| Nález mimo hunky skočí **na soubor** | Nedělat nic, když se řádek v diffu nenajde | Reviewer čte celý pracovní strom, ne jen diff, takže umí nahlásit řádek, který se nezměnil. Hlavička souboru je nejbližší pravdivé místo; skákat na jiný řádek by lhalo |
| Cesta ke klonu je **nápověda**, ne řádek v hlavičce | Vypisovat ji pod stavem pracovní kopie | Je to údaj, který se hodí jednou za měsíc, a zabíral pruh přes celou šířku okna. U **selhání** zůstává výpis celý a rozbalený — tam je text od `gitu` to jediné, z čeho se pozná, co dělat |
| Obsah souboru přes **ref pull requestu** (`refs/pull/<n>/head`) | Dotáhnout `headSha` přes `gh pr view` a číst soubor podle něj | Ověřeno na živém API, že ten ref projde — ušetří to jedno volání `gh` u každého rozbalení a hlavně odpadá stav navíc (SHA, který by se musel držet a invalidovat). Ten ref má na GitHubu každý PR včetně forků, stejně jako u fetche v `RepoCheckoutu` |
| Rozsah se zapíše jako odkrytý **až po** načtení obsahu | Zapsat ho hned a obsah doplnit, až dorazí | Jinak zmizí rozbalovací řádek i se spinnerem a zůstane po něm prázdné místo — vypadá to, že se nic nestalo. Ze stejného důvodu `rows(of:)` ignoruje odkryté rozsahy, dokud obsah není: bez něj není co ukázat |
| Rozbalená mezera **sundá hlavičku hunku** | Nechat hlavičky vždycky | Když se dvě části slijí do jednoho souvislého bloku, hlavička `@@` uprostřed neodděluje nic a mate — přišlo to jako první připomínka při zkoušení. Mezera, která nikdy nebyla, hlavičku nechává |
| Sbalení si **nechá načtený obsah** | Zahodit ho spolu s rozsahy | Druhé rozbalení by jinak chodilo po síti pro něco, co už jednou dorazilo. Paměť to nestojí nic proti diffu samotnému |
| Výběr v tabulce se po skoku **zahazuje** | Nechat vybraný řádek podbarvený, jak to tabulka dělá sama | Druhé kliknutí na už vybraný řádek by neudělalo nic — a to je přesně situace „odscrolloval jsem jinam a chci se vrátit“. Zpětnou vazbu dává zvýrazněná bublina v diffu, ne podbarvení v tabulce |
| Zvýraznění bubliny po skoku **zhasne** | Nechat rámeček, dokud se neklikne jinam | Trvalý rámeček se plete s červeným pruhem u blokujícího nálezu — dvě různé věci by říkaly „dívej se sem“. Dvě a půl vteřiny stačí na to, aby oko skok dohnalo |
| Výška panelu se **táhne a pamatuje** | Měřit ji podle obsahu, jak to dělal seznam před #20 | Měření dávalo smysl u seznamu, který měl přirozenou výšku. Tabulka ji nemá — kolik místa má dostat, ví jen uživatel, a u každého PR jinak |
| Řádek tabulky je **vlastní typ** (`FindingRow`) | Dát `Finding` identitu a strčit ho do `Table` přímo | `Table` potřebuje `Identifiable`, ale doménový model se kvůli zobrazení měnit nemá — `Finding` je to, co uložil reviewer. Vedlejší přínos: skládání textů (`—` u nálezu bez místa, `file:line` bez locale) je čistá funkce a testuje se bez UI |
| Nález mimo diff visí **u hlavičky souboru** a nabídne řádek dotáhnout | Nezobrazovat ho v diffu vůbec a nechat ho jen v tabulce, jak psalo issue #19 | **Změna proti zadání.** Zadání vzniklo dřív než rozbalení kontextu (#47) — a hlavně: reviewer čte celý pracovní strom, takže mimo diff hlásí běžně. Nález, který není vidět, je k ničemu; schovat ho do tabulky znamená spolehnout se, že tam uživatel půjde. Tlačítko dotáhne řádek i tři nad a pod (samotný řádek bez okolí se čte špatně) a bublina se pak přesune ke svému kódu sama, protože se váže na vykreslené řádky |
| Bubliny se zavěšují **nad hotovým seznamem řádků** | Vkládat je při skládání, uvnitř každé větve | Skládání má čtyři cesty (hunk, mezera, rozbalený kontext, poznámka) a nálezy by musely protéct všemi. Nad hotovým seznamem to je jeden průchod — a bublina díky tomu sedne i na rozbalený kontext, aniž by o ní ta větev věděla |
| Skok z nálezu míří **doprostřed** okna | Na horní hranu, jako skok na soubor | Bublina visí **pod** svým řádkem, takže u horní hrany by bylo vidět jen ji a kód nad ní ne. Ukotvená hlavička souboru navíc vršek překrývá, takže by řádek scrollnutý na vrch skončil pod ní. Skok na **soubor** na vrchu zůstává — tam je hlavička přesně to, co má být nahoře |
| Přepínač bublin je v `UserDefaults`, ne ve store | Držet ho v `AppStore` vedle ostatního stavu | Je to předvolba pohledu napříč pull requesty, ne údaj o konkrétním PR — a má přežít restart. Stav ve store se naopak zahazuje s PR, které zmizí ze seznamu |
| Obarvení kódu **bez externí závislosti** | highlight.js ve `WKWebView` nebo tree-sitter přes SPM | Repozitář zatím žádnou závislost nemá a obojí je velké kladivo na „obarvi mi komentáře a řetězce“. Vlastní pravidla dají osmdesát procent výsledku, nikomu se neupdatují a vejdou se do jednoho souboru s testy. Kdyby to nestačilo, je to místo, kde se závislost dá dodat později |
| Barví se **řádek po řádku, bez paměti** | Držet stav (otevřený blokový komentář, řetězec) napříč souborem | Diff je útržek: mezi hunky chybí řádky, ze kterých by se stav dopočítal, takže by se barvilo podle textu, který v okně vůbec není. Po rozbalení kontextu (#47) by se navíc barvy měnily pod rukama. Cena je neobarvený vnitřek víceřádkového komentáře — vidět je pořád, jen šedě není |
| Paleta **Darcula + IntelliJ Light** | Systémové barvy (`.purple`, `.teal`), které se samy přizpůsobí režimu | Systémové barvy byly první verze a fungovaly, ale je to paleta bez původu. Darcula je to, v čem se kód reálně čte, a IntelliJ Light je její **oficiální** protějšek — vlastní „světlá Darcula“ by byla vymyšlená. Daň: Darcula má zelené řetězce, takže na zeleném podbarvení přidaného řádku je zelená na zelené; v provozu čitelné, ale je to nejslabší místo palety |
| Proměnné se barví **jen podle sigilu** (`$`) | Poznat proměnnou i ve Swiftu nebo Go | Bez sigilu je proměnná obyčejné jméno a od volání funkce ji na jednom řádku nerozliší nic než porozumění kódu. Půlka jazyků obarvená a půlka ne je horší než jasná hranice |
| Obarvení se **necachuje**, počítá se při vykreslení řádku | Sdílená cache klíčovaná jazykem a textem řádku, jak psalo issue | **Změna proti zadání #48.** Změřeno na skutečném kódu: 8,2 µs na řádek s optimalizací (48 µs v Debug buildu), tedy 0,33 ms na celou obrazovku o 40 řádcích — a to jen když se přestaví všechny naráz; při scrollování se skládají jednotky řádků. Cache by za to přinesla globální měnitelný stav, invalidaci a strop paměti. Je to místo, kam se dá sáhnout, kdyby se to někdy projevilo |
| Proměnná uvnitř řetězce zůstává **řetězcem** | Obarvit `$name` i uvnitř `"…"`, jak to dělá PhpStorm | Dvě barvy uvnitř jedné uvozovkované hodnoty rozbíjejí to, co má řetězec říct — že tohle všechno je jeden literál. Je to výměna jedné podmínky v tokenizeru, kdyby se rozhodnutí mělo otočit |
| `zsh -lc`, `.zshrc` se nepřečte | `zsh -ilc`, aby fallback viděl i `.zshrc` | Zkoušeno a zahozeno: interaktivní shell se ze spuštěné aplikace zasekl (z terminálu běží pod 0,5 s) a **ignoruje `SIGTERM`** — vytáhla ho až eskalace na `SIGKILL`, tedy 7 s do prázdného výsledku. Zaseknutý start je horší selhání než nenalezená binárka, kterou gate umí vysvětlit. Zůstává jako známé omezení |

## Ověřeno proti CLI (2026-08-01)

Flagy Claude Code CLI byly psané z pracovní znalosti. Spike (#12) je ověřil proti verzi
`2.1.220`; podrobnosti a surové streamy jsou v [`docs/claude-cli.md`](../../claude-cli.md)
a `Tests/Fixtures/stream-json/`. Co z toho plyne pro návrh:

- **`--verbose` je v print režimu povinný** — bez něj `claude` odmítne `stream-json`.
- **`ReportFindings` musí být v `--allowedTools`.** Sada navržená výš
  (`Read,Grep,Glob,Bash(git:*)`) ho neobsahovala, takže by reviewer nálezy **napsal jako
  text** a sběr přes tool cally by tiše nefungoval. Opraveno v popisu `ReviewRunner`.
- **`--allowedTools` není totéž co seznam dostupných nástrojů.** V init eventu se objevují
  i nepovolené — `Write` a `Edit` tam jsou vždycky — a `Bash(git:*)` nezúží `Bash` jen na
  git, projdou i `ls` nebo `cat`. Read-only
  garance drží, ale z jiného důvodu, než návrh předpokládal: neprojdou **měnící** operace
  (`touch`, `rm`, `Write` skončily chybou a nic nevzniklo).
- **`session_id` je na každém eventu**, nejen v `init`.
- **Zabitý běh nemá `result` event** — rozlišení „doběhlo“ vs. „zabito“ stojí na jeho
  přítomnosti.
- **`stdin` musí být zavřený**, jinak `claude` čeká tři sekundy. `SubprocessRunner` to
  splňuje.
- **Pracovní složku nelze předat flagem** — je to `cwd` procesu. **Doplněno u #14:**
  `cwd` nepřibylo do `ProcessRunning`, ale do nového `ProcessStreaming` (viz záznam
  rozhodnutí), takže bufferovaná cesta zůstala beze změny.
