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
  soubory.

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
  a nástroje zůstávají v session všechny, protože `--allowedTools` je seznam povolení,
  ne dostupnosti. Neprojdou **měnící** operace: `touch`, `rm` i `Write` skončily
  odmítnutím a nic po nich nezůstalo. Read-only tedy drží nepovolením mutací.

  Hodnota `--allowedTools` je v ukázce **bez uvozovek** schválně: aplikace shell nepoužívá
  a `Process` dostává argumenty polem. Kdo si to zkouší v terminálu, uvozovky potřebuje —
  `*` by prošlo glob expansion a závorky jsou syntaktická chyba.

  Je to bezpečnostní vlastnost (reviewer nemůže změnit kód ani nikam nic poslat)
  i praktická věc: odpadne tím téměř každý důvod, proč by se Claude zastavil a chtěl
  povolení. Headless session nemá jak na permission prompt odpovědět, takže by jinak
  visela do timeoutu.
- **`CLAUDE.md` daného repa se aplikuje zdarma**, protože cwd session je skutečný
  checkout. Konvence projektu tím platí, aniž bychom cokoli přenášeli.
- **`session_id` se ukládá** z init eventu streamu, i když v1 terminál nemá. Stojí to
  jeden string a drží to otevřené dvě cesty: budoucí vestavěný terminál, nebo tlačítko
  *zkopírovat `claude --resume <id>`*.
- Nálezy pocházejí z **`ReportFindings` tool callů** odchycených v event streamu —
  strukturovaný JSON, ne parsování prózy. Fallback na parsování textu pokrývá skilly,
  které ten nástroj nepoužívají.
- Každý běh má timeout podle hodin a jde zrušit. Paralelismus je globálně omezený
  (default 3 session), aby dávka PR nezahltila stroj ani účet.

Běhy jsou klíčované `(repo, prNumber, headSha, skillId)`. Když přijdou nové commity,
změní se `headSha` a předchozí nálezy se označí jako **zastaralé** — nezobrazují se
tiše proti kódu, který už neexistuje.

### 4. ReviewStore

Persistence. `Codable` modely v JSON souborech pod Application Support, jeden soubor na
`(repo, pr, headSha)`. Zvoleno místo SwiftData proto, že dat je málo, přístupový vzor je
triviálně souborový a čistý `Codable` drží store nahraditelný v testech bez databáze.

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
| Chybný nebo chybějící `ReportFindings` | Fallback na parsování textu; když ani to nic nedá, `unparseable` s uchovaným raw výstupem |
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
| `zsh -lc`, `.zshrc` se nepřečte | `zsh -ilc`, aby fallback viděl i `.zshrc` | Zkoušeno a zahozeno: interaktivní shell se ze spuštěné aplikace zasekl (z terminálu běží pod 0,5 s) a **ignoruje `SIGTERM`** — vytáhla ho až eskalace na `SIGKILL`, tedy 7 s do prázdného výsledku. Zaseknutý start je horší selhání než nenalezená binárka, kterou gate umí vysvětlit. Zůstává jako známé omezení |

## Ověřeno proti CLI (2026-08-01)

Flagy Claude Code CLI byly psané z pracovní znalosti. Spike (#12) je ověřil proti verzi
`2.1.220`; podrobnosti a surové streamy jsou v [`docs/claude-cli.md`](../../claude-cli.md)
a `Tests/Fixtures/stream-json/`. Co z toho plyne pro návrh:

- **`--verbose` je v print režimu povinný** — bez něj `claude` odmítne `stream-json`.
- **`ReportFindings` musí být v `--allowedTools`.** Sada navržená výš
  (`Read,Grep,Glob,Bash(git:*)`) ho neobsahovala, takže by reviewer nálezy **napsal jako
  text** a sběr přes tool cally by tiše nefungoval. Opraveno v popisu `ReviewRunner`.
- **`--allowedTools` je seznam povolení, ne dostupnosti.** Nástroje zůstávají v session
  všechny a `Bash(git:*)` nezúží `Bash` jen na git — projdou i `ls` nebo `cat`. Read-only
  garance drží, ale z jiného důvodu, než návrh předpokládal: neprojdou **měnící** operace
  (`touch`, `rm`, `Write` skončily chybou a nic nevzniklo).
- **`session_id` je na každém eventu**, nejen v `init`.
- **Zabitý běh nemá `result` event** — rozlišení „doběhlo“ vs. „zabito“ stojí na jeho
  přítomnosti.
- **`stdin` musí být zavřený**, jinak `claude` čeká tři sekundy. `SubprocessRunner` to
  splňuje.
- **Pracovní složku nelze předat flagem** — je to `cwd` procesu, takže `ReviewRunner` si
  vyžádá `cwd` v `ProcessRunning` (u `git` stačilo `-C`, viz rozhodnutí u #8).
