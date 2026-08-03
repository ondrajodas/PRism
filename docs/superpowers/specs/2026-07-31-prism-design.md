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

**Hotovo (#25).** Automat plánuje po každém úspěšném tiku, session utratí teprve při změně
`headSha` a hlídá ho denní limit uložený na disku. Tím je **dokončený rozsah v1**.

**Nové repozitáře mají default `manual`.** Když jsou v rozsahu libovolná repa, neznámé
repo nesmí bez dozoru spálit celý panel Claude sessions; objeví se v seznamu a čeká na
tlačítko. `auto` se zapíná per repo tam, kde ho chci.

Skilly jsou per-repo z konkrétního důvodu: `oj-php-quality-check` na Go nebo TypeScript
repu nepřinese nic a session stejně zaplatíš. Autodetekce jazyka nastaví výchozí sadu
při prvním setkání s repem.

**Hotovo (#24).** `ProjectLanguage` + `Policy.projectLanguages(in:)` nad výpisem
`git ls-files`, mapa `skillsByLanguage` v globální části konfigurace. Rozhodovací pořadí
je tedy trojí: globální `skills` → sada podle jazyka → override per repo. Detekce běží při **každém** review,
dokud si repo o skilly neřekne, a zapisuje jen to, co se od globální sady liší; ruční
hodnota má přednost a detekci navždycky umlčí.

**Hotovo (#23).** `config.json` v kořeni cache, `Configuration` → `resolved(for:)` jako
čistá funkce. Hodnoty se čtou **při použití**, ne při startu, takže se změna projeví bez
restartu; soubor se načte při spuštění a pak pokaždé, když se okno vrátí do popředí.

**Vyvolání skillu opravené (#78).** Prompt si o skill říká nástrojem `Skill` výslovně
a konfigurace jmenuje jeho **id**, ne slash command. Rozhodnutí z #17 („skill se vyvolává
lomítkem“) tím padá úplně: lomítko rozbíjí `ReportFindings`, próza skill nevyvolá, zbývá
nástroj. Měření a ověřené chování jsou v [`docs/claude-cli.md`](../../claude-cli.md).

**Jazyk nálezů hotový (#52).** `FindingsLanguage` (`cs`/`en`) globálně i per repo.

**Rozhodnutí ze zadání se otočilo.** Issue chtělo říct jazyk reviewerovi v promptu
a překlad po doběhnutí výslovně zamítalo. Postavené to tak bylo a při zkoušení se zdálo, že
to stojí nálezy: česká varianta dala na skutečném PR jeden nález tam, kde anglická tři.

**To přiřazení příčiny ale neuneslo váhu, kterou jsem mu dal**, a je poctivé to tu nechat
zapsané. Byl to jeden běh na variantu. Když se prompt vrátil na původní znění, dal tentýž
commit dva nálezy — tedy 1, 2 a 3 přes tři běhy nad stejným kódem. Rozptyl mezi běhy je
stejně velký jako efekt, který se tomu připisoval, a rozhodnout to doopravdy by chtělo
několik běhů na variantu.

**Přesto se otočení nechává, protože obstojí i bez toho měření.** Překlad po doběhnutí
kvalitu review ovlivnit **nemůže konstrukcí** — reviewer dostává tentýž prompt jako
předtím. Instrukce v promptu ovlivnit může a vyvrátit se to levně nedá. Když je bezpečná
varianta zadarmo, nemá smysl platit za jistotu u té druhé.

Zamítnutí navíc stálo na přeceněném čísle: „další session na každý nález“ neplatí, překládá
se celý seznam jednou dávkou, tedy jedno krátké volání na běh.

**Okno nastavení hotové (#70).** Scéna `Settings` (⌘,) se dvěma záložkami píše do téhož
souboru. Rozpis výš se u toho změnil: **globální část dostala `mode`**, tedy výchozí režim
review, a per-repo `mode` je proto **volitelný** (`nil` = ber globální). Vynutil si to
požadavek na globální default — bez optionalu by nešlo odlišit repo, které si o `manual`
řeklo, od toho, které o režimu mlčí, a při globálním automatu jsou to opačné odpovědi.
Věta „nové repozitáře mají default `manual`“ tím platit nepřestala, jen se posunula: neznámé
repo bere **globální** režim a ten je ve výchozím stavu `manual`.

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
- **Načítá se na kliknutí** a drží se po souborech. **Výjimka:** kód kolem nálezu, jehož
  řádek v diffu není, se dotáhne sám — viz záznam rozhodnutí.
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
- **Přepínač `Nálezy`** v liště nad diffem; stav se pamatuje mezi spuštěními.
  Do #64 se jmenoval `Bubliny` — přejmenováno, protože od té doby jsou bubliny i vlákna
  konverzace a schovává se pořád jen nálezy
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

#### Šířky sloupců (#60)

- **`Nález` bere, co ostatní nechají.** `Kategorie` a `Reviewer` mají strop na tom, co
  potřebují, `Místo` něco mezi tím. Bez stropu roste pružný sloupec do nekonečna a přebytek
  se dělí mezi všechny — dvě krátká slova pak zabírala polovinu tabulky.
- **Co se nevejde, je v nápovědě — u každého sloupce.** U nálezu celý text, u místa celá
  cesta. U nálezu bez místa vysvětluje nápověda pomlčku, protože tooltip s pomlčkou neříká
  nic.
- **`Místo` se ořezává zepředu**, ať zůstane jméno souboru a číslo řádku; text nálezu odzadu.
- **Šířky zůstávají přetažitelné** — mění se jen výchozí poměr.

### Strom souborů (#51)

Navigace po souborech diffu. Plochý seznam cest se u PR přes víc adresářů čte špatně —
společné prefixy zaberou většinu šířky.

- **Popover se stromem** místo rozbalovacího menu; složky se dají sbalit, výchozí je
  rozbaleno.
- **Složky s jediným potomkem se slévají** do jednoho řádku (`App/Views/Diff`).
- **Pořadí kopíruje diff**, nesetřiďuje se znovu. Uvnitř složky jdou podsložky před soubory.
- Složka **sčítá `+N −M`** z toho, co je pod ní; u souboru zůstává odznak změny.

### Chipy reviewerů a verdikt (#21)

Horní lišta detailu: kdo co našel a co se s tím navrhuje.

- **Chip na reviewera** se stavem: `N nálezů`, `čisté`, `běží`, `selhalo`, `timeout · N`
  a `nejisté`. Ten poslední je běh, který doběhl, ale **nezavolal `ReportFindings`** nebo
  se mu ztratil nález — takový se nesmí tvářit jako čistý. Stejné pravidlo jako u návrhu
  verdiktu.
- **Klik na chip filtruje** nálezy toho reviewera z bublin i z tabulky; vypnutý je
  ztlumený. Podrobnost selhání (stderr) visí na nápovědě.
- **Reviewer mimo nastavenou sadu** se přidá na konec — jinak by nešlo poznat, odkud se
  jeho nálezy v tabulce vzaly.
- **Návrh verdiktu vpravo**, vizuálně jako doporučení. Aplikace na GitHub nic neposílá,
  takže na něm nevisí žádná akce; u zastaralého záznamu se říká, proč návrh není.

### Tab Průběh (#22)

Živý pohled na to, co reviewer právě dělá — **nativně z eventů**, ne přeposíláním textu.
Proto v1 nepotřebuje vestavěný terminál.

- **Sekce na reviewera**, v ní události pod sebou: čas, nástroj a to, nad čím běžel.
- **Hlavička nese `session_id` a tlačítko `Zkopírovat resume`** (`claude --resume <id>`) —
  levná náhrada terminálu, když je potřeba se do session vrátit.
- **Osa se drží i po doběhnutí**, v paměti. Po restartu by se k session stejně nedalo
  připojit, takže persistence nic nepřidá. Nový běh ji vynuluje.
- **Sledovat konec** posouvá osu na nejnovější událost; dá se vypnout.
- **Cesty se zkracují proti pracovnímu stromu** a `cd <strom> &&` z příkazů mizí. Bez toho
  začíná každý řádek stejnými sedmdesáti znaky cache.

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
- **Podpis vlastním certifikátem, ad-hoc jako fallback** (#61, styl Manual). Původně byl
  podpis ad-hoc (`CODE_SIGN_IDENTITY = "-"`) s odůvodněním, že build nepotřebuje Apple účet
  ani tým a `xcodebuild` zůstane reprodukovatelný na čistém stroji. To platí dál, ale
  ad-hoc podpis **nemá stálou identitu**: každý build dá jiný otisk, takže macOS považuje
  aplikaci pokaždé za jinou a povolení udělená přes TCC propadnou. V provozu se to
  projevovalo dotazem na přístup do Stažených souborů po každém rebuildu — vyvolával ho
  `claude`, kterému inicializace shellu přes `~/.zshrc` sáhla na Google Cloud SDK
  v `~/Downloads`; aplikace sama do chráněných složek nesahá.

  Řeší to self-signed certifikát *Code Signing* `PRism Local` v login keychainu, který
  jednorázově vyrobí `bin/setup-signing.sh`. Jméno certifikátu drží gitignorovaný
  `Signing.local.xcconfig`, který si přes `#include?` tahá checkovaný `Signing.xcconfig`
  s ad-hoc defaultem — na stroji bez certifikátu se tedy nic nemění. Zadrátovat jméno do
  `project.pbxproj` nešlo: build s chybějícím certifikátem končí `No certificate matching`
  (ověřeno), takže by projekt přestal jít zbuildit jinde.
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
| Kód kolem nálezu **mimo diff se dotáhne sám** | Čekat na kliknutí na „Zobrazit ho“, jak rozhodovalo #47 | **Změna proti #47.** Bublina, která mluví o řádku 10, a řádek 10 nikde — to je přesně případ, kdy čekání na kliknutí stojí nejvíc, protože nález bez svého kódu nejde posoudit. Týká se to jen souborů, kde nález opravdu je, takže jde o jednotky stažení i u velkého PR; smazaný soubor a binárka se přeskočí, nový obsah nemají |
| Strom je **popover**, ne vnořená podmenu | `Menu` s podmenu, jak nabízelo issue #51 | Rozhodnuto nad běžícím PR, jak issue chtělo: u 49 souborů je plochý seznam nepoužitelný a v podmenu se u hlubší struktury špatně míří. Popover unese scroll, sbalování i souhrny |
| Strom se vykresluje **ručně**, ne přes `OutlineGroup` | Nechat odsazení na `OutlineGroup` | `OutlineGroup` odsazuje jen uvnitř `List`u; v `LazyVStack`u vyjdou všechny úrovně na stejné x a z řádků není poznat, co je pod čím |
| Obsah souboru přes **ref pull requestu** (`refs/pull/<n>/head`) | Dotáhnout `headSha` přes `gh pr view` a číst soubor podle něj | Ověřeno na živém API, že ten ref projde — ušetří to jedno volání `gh` u každého rozbalení a hlavně odpadá stav navíc (SHA, který by se musel držet a invalidovat). Ten ref má na GitHubu každý PR včetně forků, stejně jako u fetche v `RepoCheckoutu` |
| Rozsah se zapíše jako odkrytý **až po** načtení obsahu | Zapsat ho hned a obsah doplnit, až dorazí | Jinak zmizí rozbalovací řádek i se spinnerem a zůstane po něm prázdné místo — vypadá to, že se nic nestalo. Ze stejného důvodu `rows(of:)` ignoruje odkryté rozsahy, dokud obsah není: bez něj není co ukázat |
| Rozbalená mezera **sundá hlavičku hunku** | Nechat hlavičky vždycky | Když se dvě části slijí do jednoho souvislého bloku, hlavička `@@` uprostřed neodděluje nic a mate — přišlo to jako první připomínka při zkoušení. Mezera, která nikdy nebyla, hlavičku nechává |
| Sbalení si **nechá načtený obsah** | Zahodit ho spolu s rozsahy | Druhé rozbalení by jinak chodilo po síti pro něco, co už jednou dorazilo. Paměť to nestojí nic proti diffu samotnému |
| Konfigurace se dekóduje **tolerantně** | Přísné `Codable` — chybějící klíč = chyba | Soubor se edituje ručně a málokdy obsahuje všechno. Přísné dekódování by kvůli jednomu chybějícímu klíči zahodilo celou konfiguraci včetně toho, co je napsané správně — a uživatel by hledal, proč mu nastavení nefunguje. Chybějící klíč znamená „ber výchozí“ |
| Rozbitý soubor se **nepřepíše** výchozími hodnotami | Přepsat ho, ať je zase platný | Uživatel ho psal; přijít o něj kvůli chybějící čárce je horší než ta chyba. Aplikace běží na defaultech a **říká to** — mlčky by to vypadalo, že nastavení nefunguje |
| Hodnoty se čtou **při použití** | Načíst je jednou při startu | Limit souběhu, rozpočet cache i model se ptají v okamžiku, kdy je potřeba (`ConfigurationBox` kvůli tomu, že běží mimo hlavní vlákno). Jinak by se změna projevila až po restartu — a to je u souboru, který se edituje ručně, past |
| Nula souběžných session se bere jako **jedna** | Věřit číslu ze souboru | Překlep v konfiguraci nemá aplikaci umlčet tak, že se nespustí nic a nikdo nepozná proč |
| Konfigurace se načte **při návratu do popředí** | Tlačítko „Znovu načíst“ nebo hlídání souboru | Tlačítko je krok navíc za něco, co se dá udělat samo. Hlídání souboru by znamenalo řešit atomický zápis, po kterém přestane platit sledovaný deskriptor. Návrat do aplikace je přesně ta chvíle, kdy člověk soubor dopsal |
| Prázdný seznam skillů u repa je **vlastní odpověď** | Brát prázdné pole jako „nic nenastaveno“ | „Tady nereviewuj nic“ se musí dát říct jinak než smazáním klíče, které znamená „ber globální“ |
| Filtr reviewerů **nemění návrh verdiktu** | Počítat verdikt jen z toho, co je vidět | Ztlumení revieweera je pohled, ne tvrzení o pull requestu. Kdyby filtr do verdiktu sahal, dalo by se schováním revieweera „vyrobit“ approve — a to je nejdražší chyba, jakou tahle aplikace umí udělat |
| Klik na chip **filtruje**, stderr je v nápovědě | Klik otevře stderr, jak psalo issue | Dvě různé akce na jedno kliknutí nejdou a filtr se používá mnohem častěji. Text selhání je jedno najetí myší daleko a u chipu, kde dává smysl, je i důvod nejistoty |
| Chip má stav **`nejisté`** | Vystačit si s `čisté`/`nálezy`/`selhalo`, jak psalo issue | Běh, který doběhl, ale nezavolal `ReportFindings` (nebo se mu ztratil nález), není ani čistý, ani spadlý. Ukázat u něj „čisté“ znamená schválený PR s neohlášenou chybou — stejná past, kvůli které umí návrh verdiktu odpovědět „není z čeho soudit“ |
| Konec běhu jde do osy **stejným proudem** jako průběh | Zapsat ho přímo, jakmile běh doběhne | Odhalily to testy: zápis mimo proud dorazil **dřív** než události, které mu předcházely, a někdy se ztratil úplně (osa pro ten skill ještě neexistovala). Jeden proud dělá pořadí věcí konstrukce, ne štěstí |
| Průběh teče do store **proudem**, ne přímým voláním | Hopnout na `@MainActor` u každé události | Události se hlásí ze session, která běží mimo hlavní vlákno, a **pořadí je to hlavní, co osa říká**. Task na každou událost nechá o pořadí rozhodovat plánovač; `AsyncStream` ho drží a `drain` je jediná smyčka, která do osy zapisuje |
| Pokus o nástroj nese i **to, nad čím běžel** | Nechat v ose jen jméno nástroje, jak to parser uměl | Deset řádků „Bash“ pod sebou neřekne nic. Detail se bere z `input` podle známých klíčů (`file_path`, `pattern`, `command`, …); neznámý nástroj detail prostě nemá, protože hádat by znamenalo ukázat cizí hodnotu jako cestu |
| Detail se zkracuje **proti pracovnímu stromu** | Ukázat, co přišlo | Každá cesta začíná stejnými sedmdesáti znaky cache a každý příkaz `cd <strom> &&`; po zkrácení je na řádku vidět soubor, ne kde ho aplikace má. Ořezává se navíc z jiné strany podle nástroje: u cesty je zajímavý konec, u příkazu začátek |
| Panel se ukáže i **bez uloženého záznamu** | Vázat ho na `ReviewRecord`, jak to bylo od #20 | Při **prvním** review žádný záznam ještě není — a to je přesně chvíle, kdy je průběh to jediné, co existuje. Čekat na uložený výsledek by ho schovalo |
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
| Nastavení je **scéna `Settings`** (⌘,), ne sheet nad oknem | Sheet, panel v detailu, nebo ponechat popover s cestou k souboru | Zadání chtělo ⌘, a je to macOS zvyklost. Daň je viditelná: store se musel přestěhovat z `ContentView` do `PreflightModel`, protože scéna je vlastní strom a k `@State` uvnitř okna nedosáhne. Sheet by tuhle přestavbu ušetřil, ale ⌘, by pak nefungovalo a seznam rep by tahal store stejně |
| Ukládá se **samo, odloženě** (600 ms), bez tlačítka `Uložit` | Explicitní tlačítko, nebo zápis na commit každého pole | Tlačítko je krok navíc u něčeho, co má být jeden klik (přepnout repo na automat), a stav „rozepsáno, neuloženo“ by musel být vidět. Zápis na každý úhoz znamená deset dotyků disku za slovo a uložené mezistavy. Zpoždění řeší obojí; zavření okna ho nečeká (`flush()`) |
| Zápis se **stejnou** hodnotou se zahazuje | Ukládat každý zápis do draftu | Nebylo to zamýšlené pravidlo, byla to oprava: pole si při zobrazení zapisují zpátky, co v nich je, takže **samotné otevření okna** přepsalo ručně editovaný soubor a patička hlásila „Uloženo“. Chytilo se to na běžící aplikaci, ne v testu |
| Globální `mode` a **volitelný** per-repo `mode` | Nechat režim jen per repo, jak psalo #23 | Vyžádané při zkoušení: přepínat desítky rep po jednom je práce, kterou má dělat default. Optional per repo je pak podmínka správnosti, ne kosmetika — explicitní `manual` musí přežít přepnutí globálního defaultu na automat, jinak by se repo, u kterého jsem automat vypnul, samo zapnulo |
| Prázdný záznam repa se **maže**, ale podle prázdnosti, ne podle shody s globálem | Nechat v souboru všechno, co se proklikalo, nebo mazat vše, co se rovná globální hodnotě | Soubor se čte ručně, takže hromada prázdných objektů po proklikání okna vadí. Mazat „stejné jako globální“ ale nejde: byl by to přesně ten tichý přepínač z řádku výš |
| Rozbitá hodnota režimu se sráží na `manual`, chybějící klíč bere globální | Brát obojí stejně | Chybějící klíč je „nic jsem neřekl“, kdežto překlep v hodnotě je pokus něco říct. Když se tím pokusem automat **vypínal**, nesmí ho překlep nechat zapnutý — stejná logika jako u nuly souběžných session |
| Rozostřuje se, jen když je nastavení **key window** | Rozostřit vždycky, když je okno otevřené, nebo udělat nastavení modální | Okno je nemodální, takže se kliknutím zpátky do seznamu dá dál pracovat — a rozostřené okno, ve kterém zrovna píšu, je horší než žádný efekt. Modální okno nastavení by zase zablokovalo sledování běžícího review. Poloměr 3 px doladěn na běžící aplikaci (6 bylo moc) |
| Odvozený `Binding` z optionalu se píše **ručně**, ne přes `Binding(_:)` | Nechat `if let list = Binding(items)`, jak to SwiftUI nabízí | **Shazovalo to aplikaci** při vypnutí vlastní sady skillů: `BindingOperations.ForceUnwrapping` čte základ znovu při každém update a editor nad ním jeden překreslovací cyklus přežije. Ruční binding s `?? []` nemá kde spadnout a zápis se navíc zahazuje, dokud je zdroj `nil` — jinak by doběhlá editace zrušený override vzkřísila |
| Rozepsaná hodnota z editoru se **přeskočí** | Nepouštět ji do konfigurace (validace v okně), nebo ji použít, jak je | Našlo se vlastní revizí diffu, ne Copilotem: `Přidat zdroj` vyrobí řádek, který se uloží dřív, než se dopíše dotaz — a `gh search prs` bez výrazu selže. Protože selhání jednoho zdroje zahazuje celý tik, zmizel by kvůli rozepsanému řádku celý seznam PR. Validace v okně by musela blokovat ukládání a vyrobit stav „rozepsáno, neuloženo“, který autosave nemá kde ukázat; přeskočení je jedna čistá funkce a prázdný **seznam** zůstává vlastní odpovědí |
| Jazyk projektu je **vlastní výčet**, ne `Syntax.Language` | Rozšířit typ z obarvování a použít ho na obojí | Odpovídají na jiné otázky: obarvování zná YAML, JSON a Markdown, které o projektu neříkají nic, a naopak by rozpoznat Python vyžadovalo umět ho obarvit. Se sdíleným výčtem by každý repozitář vyšel jako „YAML“. Cena jsou dvě tabulky přípon, ale každá je krátká a odpovídá na svoji otázku |
| Soubory se vypisují `git ls-files`, ne `FileManagerem` | Projít pracovní strom rekurzivně | Ignorované složky (`vendor/`, `node_modules/`, buildy) jsou zrovna ty, kterých je nejvíc — u PHP projektu se závislostmi by odhad určilo `vendor/`, ne `src/`. `git` navíc čte index, takže na partial klonu nepotřebuje obsah blobů |
| `package.json` **není** marker | Vzít ho jako marker JavaScriptu, jak psalo zadání #24 | **Změna proti zadání.** Má ho každý TypeScript projekt stejně jako JavaScriptový, takže by JavaScript přidával úplně všude a na každém TS repu by běžely obě sady. Čím je node projekt psaný, řeknou přípony; `tsconfig.json` je oproti tomu jednoznačný |
| Jazyk podle přípon až od **desetiny** rozpoznaných zdrojáků | Zařadit každý jazyk, jehož soubor se v repu vyskytne | „Převažující“ ze zadání znamená prominentní, ne „vyskytl se“. Jeden zatoulaný `.py` skript v PHP repu nemá pouštět Python reviewery — každá session stojí peníze. Do jmenovatele jdou jen rozpoznané zdrojáky, protože s Markdownem a YAMLem uvnitř by podíl neříkal nic o kódu |
| Odvozená sada se zapíše, **jen když se liší** od globální | Zapsat ji vždycky, ať je vidět, co detekce našla | Zápis „stejné jako globální“ je override, o který nikdo nežádal — a pozdější změna globální sady by takové repo tiše minula. Je to tentýž tichý přepínač, kvůli kterému se u režimu maže záznam podle prázdnosti, ne podle shody s globálem |
| Ruční sada detekci **navždycky umlčí**, i prázdná | Detekovat znovu, když je sada prázdná | Prázdná sada je vlastní odpověď („tady nereviewuj nic“) a přepsat ji odvozenou by znamenalo vracet uživateli jeho rozhodnutí zpátky. `nil` je jediný stav, který znamená „tohle tu nikdo nenastavoval“ |
| Výchozí mapa jazyků je **prázdná** | Nasadit rovnou `php: [code-review, oj-php-quality-check]`, jak psalo zadání | `oj-php-quality-check` je skill z uživatelovy globální konfigurace, ne z tohohle repa; zadrátovat ho do defaultů aplikace by pustil na repa něco, o co si nikdo neřekl, a rozešel by se s testem „výchozí hodnoty odpovídají konstantám, které nahradily“ |
| V UI se píše „**programovací** jazyk“, ne jen „jazyk“ | Kratší popisek „Skilly podle jazyka“ | Spletlo se to hned při prvním zkoušení s jazykem, ve kterém reviewer píše nálezy (#52) — a to je otázka, kterou repo řeší taky, takže záměna není hypotetická. Delší popisek je levnější než vysvětlování |
| Jazyk se řeší **překladem po doběhnutí**, ne instrukcí v promptu | Říct reviewerovi „piš česky“, jak to zadání #52 chtělo | **Změna proti zadání.** Spouštěčem bylo pozorování, že česká varianta dala jeden nález tam, kde anglická tři — ale to přiřazení nevydrželo: po návratu promptu na původní znění dal tentýž commit dva, takže rozptyl mezi běhy je stejně velký jako domnělý efekt. Rozhodnutí drží i tak, jen z jiného důvodu: překlad po doběhnutí kvalitu review ovlivnit **nemůže konstrukcí**, instrukce v promptu může a vyvrátit se to levně nedá. Bezpečná varianta je zadarmo |
| Jazyk nálezů je **uzavřený výčet** (`cs`/`en`) | Volný řetězec, jako u skillů, kategorií a modelu | Hodnota jde do **anglické věty v promptu** a do **českého popisku v okně**. U volného řetězce by první záviselo na tom, jak ho uživatel napíše (`Czeh` by tiše nefungovalo), a druhé by nešlo ukázat vůbec. Je to jediná volba v konfiguraci, kterou aplikace sama formuluje do věty — proto se u ní vyplatí uzavřít, co jinde zůstává otevřené. Přidat jazyk je jeden case a dva řetězce |
| Věta o jazyku se posílá **i pro angličtinu** | Poslat ji jen tehdy, když se chce něco jiného než výchozí chování modelu | Reviewer čte pracovní strom, a když je repo dokumentované česky (třeba tenhle), napsal by česky i nálezy na repu, kde se to nechce. Mlčení není volba jazyka, je to hádání — a cena za jistotu je jedna věta |
| Jazyk žije v sekci **Režim review**, ne mezi hodnotami běhu | Vlastní sekce, nebo přidat k intervalu a rozpočtu | Je to spolu s režimem to, co se u jednotlivých rep mění nejčastěji, a obojí má stejný tvar „globální default, který si repo přebije“. Sedmá sekce v už tak dlouhém formuláři je šum; interval a rozpočet se naopak nastaví jednou za život |
| Rozbitá hodnota jazyka spadne na **globální**, ne na výchozí | Srazit ji na češtinu, jako se režim sráží na `manual` | U režimu je přísnost kvůli tomu, že překlep by pustil review, o které nikdo nežádal. U jazyka je nejhorší následek próza v jiném jazyce, takže se hodnota, které se nedá rozumět, bere jako „nic jsem neřekl“ |
| Prompt si o skill říká **výslovně** nástrojem `Skill` | Nechat jméno v próze, jak to bylo od #17 | **Změna proti #17.** Jméno v próze skill nevyvolá — model si ho domyslí, a když se nakonfigurované id na nic nemapuje, sáhne po nejbližším. Změřeno: se jménem, které existuje, 3/3 načteno i bez pokynu; s neexistujícím si 3/3 vybral něco jiného, včetně pluginu, který umí psát na GitHub. Na skutečných bězích to dělalo 5 ze 14 |
| Výchozí skill je **`code-review:code-review`** | Nechat `code-review`, nebo nemít výchozí skill vůbec | `code-review` **není skill** — je to plugin *command*, žádný `SKILL.md` s tím jménem neexistuje. Ověřeno spuštěním, že pluginová varianta se pod omezeními aplikace chová správně: hlásí přes `ReportFindings`, `gh` ani `Task` nezkusí a diff si vezme z worktree. Nemít výchozí skill by znamenalo vzdát se toho, na čem stojí sada podle jazyka (#24) |
| Zákazy v promptu **přebíjejí skill**, a je to tam napsané | Spolehnout se jen na `--disallowedTools` | Skill je cizí instrukce, kterou aplikace dopředu nezná — `code-review:code-review` má `Bash(gh pr comment:*)` ve svých `allowed-tools`. Věta v promptu a zákaz v CLI se nezastupují: první říká, co se má dělat, druhý zavírá, co jde udělat |
| Skill z **kontrolovaného repa** se načíst smí | Vypnout projektová nastavení přes `--setting-sources user` | Ověřeno, že se to děje: reviewer načte `.claude/skills/` z worktree a řídí se jím. Je to injektážní plocha — PR si může přinést instrukce pro svého revieweera — ale taky žádoucí vlastnost, protože repo se skutečným review skillem ho má dostat. Rozhodnuto ponechat; kdyby se to mělo otočit, knoflík je zaznamenaný |
| `Skill` je v `--allowedTools`, i když projde i bez něj | Nechat ho venku, když na tom nezáleží | Nástroj je čtecí builtin, takže povolení jeho chování neřídí (ověřeno). Seznam ale má být čitelný jako „co reviewer smí“ — a co v něm chybí, se při příštím čtení bude jevit jako zakázané |
| Sbalené soubory jsou **množina sbalených**, ne příznak u každého | Vést stav u všech souborů diffu | Rozbaleno je výchozí stav, takže prázdná množina znamená „nikdo nic nesbalil“ a nemusí se nic plnit při načtení diffu. Vedlejší přínos: úklid po zmizelém PR je jeden `filter` |
| Odznak s počtem nálezů je v hlavičce **vždycky** | Jen u sbaleného souboru, kde jsou bubliny schované | **Změna oproti prvnímu návrhu**, vyžádaná při zkoušení. U sbaleného je to nutnost, ale u rozbaleného to není šum: dá se projet hlavičky a vidět, kde nálezy jsou, bez scrollování obsahem. Původní zdůvodnění („u rozbaleného je to šum“) neobstálo |
| `Sbalit vše` a `Rozbalit vše` je **jedno** tlačítko | Dvě vedle sebe | Který ze dvou stavů dává smysl, plyne z toho, co je na obrazovce — druhé tlačítko by bylo pořád k ničemu. `unfoldAll` přitom sahá jen na svoje PR, aby se tlačítko neprojevilo jinde |
| Celá hlavička je tlačítko, ne jen šipka | Klikat na šipku, jak to dělá `DisclosureGroup` | Na GitHubu se kliká kamkoli do řádku a trefovat se do šipky u padesáti souborů je práce navíc. Šipka zůstává jako **ukazatel stavu**, ne jako terč |
| Oddělovač pod hlavičkou je **`Rectangle`**, ne `Divider()` | Nechat `Divider()`, jak tam byl od #18 | `Divider` si orientaci bere z okolní osy a v `overlay` žádná není, takže se kreslil **svisle**. Pod hlavičkami tedy nikdy nebyla čára, kterou ten kód chtěl. Vyšlo to najevo až sbalením všech souborů, kdy se svislé čárky poskládaly do jedné — dobrá připomínka, že „ono se to nějak vykreslí“ není totéž co „vykreslí se to, co jsem napsal“ |
| Automat se rozhoduje na **dva kroky**: `updatedAt` po tiku, `headSha` po detailu | Dotáhnout detail každého PR při každém tiku a rozhodovat rovnou podle `headSha` | Vyhledávání SHA nedává (#4), takže by to znamenalo N podprocesů na jeden poll. Dvoukrokové rozhodování stojí u nezměněného PR **nula** volání a u PR s novým komentářem jedno `gh pr view` — a session, což je to jediné drahé, se utratí jen při skutečné změně kódu |
| Denní limit je **na disku**, ne v paměti | Počítat v paměti a po restartu začít od nuly | Je to pojistka proti překvapení na účtu, a pojistka, kterou obejde restart, není pojistka — restart je zrovna to, co se po nečekaném utrácení udělá jako první |
| Rozpočet se bere **před** spuštěním | Započítat běh, až doběhne | Session je utracená v okamžiku, kdy běh začne. Počítat doběhlé by pustilo dvacet běhů naráz a limit by se projevil až potom, co je pozdě |
| **Draft se sám nereviewuje** | Reviewovat všechno, co je v seznamu | **Doplněno proti zadání #25.** Autor na draftu ještě pracuje a každý push by stál session. Ruční spuštění zůstává, takže se o nic nepřichází |
| Ruší se **jen automatická** review PR, který zmizel ze seznamu | Rušit všechna, nebo nerušit nic | Mergnutý PR nemá blokovat slot — to je smysl toho pravidla. Ruční review si ale vyžádal člověk a zrušit mu ho pod rukama proto, že to někdo mezitím mergnul, je horší než jedna session navíc |
| Nulový `autoRunsPerDay` znamená **vypnuto** | Brát nulu jako „bez omezení“ | Stejná logika jako u nuly souběžných session, jen obráceně: tam překlep nesmí aplikaci umlčet, tady nesmí z překlepu vzniknout neomezené utrácení. Rozhoduje, co je horší následek |
| Zahození nálezů maže **viditelný commit**, ne historii PR | Nabídnout obojí, nebo mazat celou historii | Zastaralé záznamy jsou záznam toho, co kdy platilo. Nabídka „co přesně smazat“ je navíc u tlačítka, které se použije jednou za čas. Ukázalo se přitom, že se viditelný záznam **nemá** chránit ani když je zastaralý — kdo nad ním zmáčkne zahodit, chce se zbavit právě jeho; test to původně tvrdil obráceně |
| Maže se **celý záznam**, ne běh jednoho revieweera | Mazat po reviewerech, chipy pro výběr už existují | Přesnější nástroj, ale na „pusť to znovu jiným skillem“ je to zbytečná mezistanice: člověk chce čistý start, ne chirurgii. Kdyby se ukázalo, že je potřeba, chipy tam pro to jsou |
| Tlačítko je **vpravo v liště**, ne vedle tabů | Vedle tabů `Nálezy` / `Průběh`, jak psalo zadání #81 | **Změna proti zadání.** Mazací tlačítko těsně u přepínače, do kterého se kliká pořád, si o překlep říká. Za běhu je navíc zakázané, protože doběhlý skill by se zapsal do právě vyčištěného záznamu |
| Zahození **rovnou zváží automat**, nečeká na tik | Nechat to na příštím pollingu, nebo nespouštět vůbec | Vyžádané při zkoušení: kdo nálezy zahodí, čeká výsledek, ne příští minutu. Jde se ale stejnou cestou jako po tiku, takže platí denní rozpočet i limit souběhu — jinak by se klikáním na koš utrácely session mimo pojistku |
| Zavření aplikace během review se **potvrzuje dialogem** | Zavřít mlčky a nálezy dotáhnout z transcriptu po startu (#94, bod 3) | Dotažení z transcriptu je věcně lepší a jednou přijde, ale je řádově dražší: značka rozdělaného běhu na disku, čtení cizího formátu, vlastní stav pro přerušený výsledek. Dialog zachytí to, co uživatel způsobí svým jednáním — a to je většina případů — za pár desítek řádků. Bod 3 zůstává v #94 pro pád aplikace a zabití zvenčí |
| Dialog staví na `NSAlert` a `runModal()` | SwiftUI potvrzení, jako má koš u nálezů | `applicationShouldTerminate` musí odpovědět **synchronně**. Asynchronní cesta by aplikaci zavřela dřív, než se kdokoli zeptá — tedy přesně to, proti čemu dialog je |
| Výchozí tlačítko je **`Zpět`** | `Ukončit` jako výchozí, ať zavření nebrzdí | Ztracený nález je dražší než jedno kliknutí navíc. Omylem odklepnutý `Enter` nemá zahodit nálezy, o kterých ještě nikdo neví |
| Rozpočet automatu se strhává **těsně před `runSkills`** | Nechat ho tam, kam se přesunul v #91 (za bránu na `headSha`, před checkoutem) | Session je utracená v okamžiku, kdy běh začne, takže počítat až doběhlé by pustilo dvacet běhů naráz. Ale každý krok **před** `runSkills` se dá projít bez jediné session: selhaný klon i repo s prázdnou sadou skillů platily za běh, který nezačal. Je to třetí poloha téhož claimu — nejdřív plánovač, pak před checkoutem, teď před spuštěním |
| Jméno certifikátu drží **gitignorovaný `Signing.local.xcconfig`**, checkovaný `Signing.xcconfig` má ad-hoc default | Zadrátovat `CODE_SIGN_IDENTITY = "PRism Local"` do `project.pbxproj`, jak psalo zadání #61 | Build s certifikátem, který na stroji není, končí `No certificate matching 'PRism Local' found` (ověřeno spuštěním), takže by projekt přestal jít zbuildit kdekoli jinde. Fallback proto patří do verzované části a jméno do té lokální. `#include?` je optional include, takže chybějící soubor není chyba |
| Podpis řeší **build settings** přes xcconfig | Nechat v projektu ad-hoc a v `bin/run.sh` aplikaci po buildu přepodepsat `codesign --force` | Přepodepsání zahodí entitlements, které do podpisu vkládá Xcode — v Debugu i `com.apple.security.get-task-allow`, bez kterého nejde připojit debugger. A stálou identitu by dostal jen build z `run.sh`; z Xcode nebo z `xcodebuild` by vyšla jiná aplikace, takže by povolení záviselo na tom, jak se buildilo |
| `CODE_SIGN_IDENTITY` je **jen na úrovni projektu** | Nechat ho v buildSettings obou targetů a xcconfig napojit na ně | Nastavení v targetu přebíjí xcconfig, takže by lokální soubor neměl žádný efekt. Na úrovni projektu ho dědí app i testy, tedy i `TEST_HOST`, který testy spouštějí |
| Certifikát vyrábí **skript**, ne postup v README | Naklikat ho v Keychain Access → Certificate Assistant, jak nabízelo zadání | Deset kliknutí v průvodci proti jednomu příkazu, a hlavně: přes `openssl` je vidět, co v certifikátu je (`extendedKeyUsage = codeSigning`, platnost, jméno). Skript je zároveň idempotentní, takže po čerstvém klonu jen doplní `Signing.local.xcconfig` |
| `bin/run.sh` **upozorní na ad-hoc podpis** | Mlčet — build proběhl, aplikace jde spustit | Bez podpisu se vrátí dotazy na přístup k datům a příčina je jinak neviditelná. Je to tentýž důvod, proč `PollStatusBanner` hlásí neaktuální data: stav, který mění chování, nemá být potichu |
| `bin/run.sh` ukončuje aplikaci **Apple eventem**, ne `killall` | Nechat `killall` — je to jen vývojový skript | SIGTERM `applicationShouldTerminate` neprochází, takže rebuild zabíjel review i s nálezy: dvakrát za jedno dopoledne, obojí s osmi a devíti nahlášenými nálezy. Pojistka, kterou obchází nejčastější způsob restartu, je poloviční. Skript proto čeká na odpověď a bez ní novou verzi nespustí |

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


## Za hranicí v1 — milníky M6 až M8

Rozsah v1 končí konfigurací a auto režimem (M5). **M6 a M7** za ním mění jeden
z předpokladů návrhu: aplikace přestává být vůči GitHubu jen pro čtení. M8 ne — viz níž.

| Milník | Co v něm je |
|---|---|
| **M6 — Review na GitHub** | Draft review (#65), skládání z nálezů a komentářů k řádkům (#66), `ReviewPublisher` jako jediná cesta ven (#67), potvrzovací sheet (#68), přenesení draftu na nový commit (#69). Předchází mu spike proti vlastnímu repu (#62) |
| **M7 — Konverzace, komentáře a taby** | Čtení konverzace PR (#63), vlákna jako bubliny u kódu (#64), odpovídání do nich a jejich vyřešení (#73), taby `Overview` / `Files changed` (#72) |
| **M8 — Notifikace** | Základ s oprávněním a klikem (#88), doběhlé review (#82), nové PR (#85), vypínání po událostech (#86), seskupování (#87) |

**M8 na M6 ani M7 nestojí** a pořadí není závazné — je to jediný z těch tří milníků, který
tvrdé podmínky nemění. Aplikace v něm zůstává vůči GitHubu jen pro čtení; notifikace jsou
cesta ven **k uživateli**, ne na GitHub, takže se jich pravidlo „jediná cesta ven“ (#67)
netýká.

Dvě rozhodnutí, která z rozpisu M8 nejsou vidět a stála za rozdělení na pět issues:

- **Základ je vlastní issue** (#88), ne součást první notifikace. Oprávnění, doručení
  a hlavně **klik, který vybere PR**, jsou společné všem druhům — jinak by se to psalo
  v každém issue znovu. Stejný tvar jako `StreamParser` (#13) nebo `ReviewStore` (#15):
  vrstva bez UI, konzument přijde vzápětí.
- **Ohlášená PR jsou snímek, ne rostoucí seznam** (#85). Uloží se, co bylo v posledním
  **úspěšném** tiku, a příště se ohlásí to, co v něm není. Nic se nehromadí, nemusí se nic
  uklízet a vypadává z toho i odpověď na „co s PR, které se vrátí do fronty“ — ohlásí se
  znovu. Log ohlášených by potřeboval vlastní lhůtu a vlastní úklid, tedy další místo, kde
  se dá zapomenout mazat.

### Záznam rozhodnutí

| Rozhodnutí | Alternativa | Proč |
|---|---|---|
| Odesílání review a konverzace jsou **dva milníky**, ne jeden | Jeden milník „GitHub“, jak vznikl při brainstormingu | Byl by to největší milník v projektu a hranice mezi jeho polovinami je ostrá: odesílání review je verdikt nad celým PR a stojí na draftu, konverzace je čtení cizího obsahu plus odpověď do vlákna. Rozdělené se dá každý dokončit a vydat samostatně |
| Pořadí je **nejdřív review, pak konverzace** | Nejdřív konverzaci, protože je skoro celá jen pro čtení, a odesílání až po ní | Zkoušelo se to opačně a přehodilo zpátky: kvůli odeslání review aplikace vzniká, kdežto cizí komentáře jsou kontext k němu. Navíc `ReviewPublisher` (#67) zavádí jedinou cestu ven — a odpověď do vlákna (#73) po ní jde taky, takže dřív hotová konverzace by si buď musela postavit vlastní cestu, nebo na M6 stejně čekat |
| Odpověď do vlákna jde **přes `ReviewPublisher`** | Vlastní modul, protože to není review | Pravidlo, které nahrazuje tvrdou podmínku č. 1, stojí na tom, že `grep ReviewPublisher` vyjmenuje **všechna** místa, odkud aplikace píše. Druhá cesta ven by z něj udělala nepravdu — a to je přesně ta vlastnost, kvůli které se ta podmínka smí zrušit |
| Odpověď **nemá potvrzovací dialog**, review ano | Potvrzovat obojí, ať je to jednotné | Review je verdikt nad celým PR a odeslat ho omylem je drahé. Odpověď je jedna věta v diskuzi, jde smazat — a potvrzování každé z nich by z okna udělalo klikačku |
| Potvrzení odeslání je **jeden sheet s úplným výpisem payloadu** | Opsat název repa jako u nevratných akcí na GitHubu, nebo dát nad sheet ještě druhý dialog | Obojí je obřad, ne ochrana: opisování se za týden odklikává automaticky a dvě potvrzení za sebou učí ruku proklikávat obojí bez čtení — čímž oslabí i to první. Co doopravdy chrání, je vidět **co odejde**, a to, že verdikt není nikde předvyplněný. Zadání #68 to takhle chtělo a zkoušení na běžící aplikaci to potvrdilo |
| Tlačítko odeslání **není výchozí** a jmenuje se akcí (`Odeslat APPROVE pro owner/repo#123`) | `OK` / `Zrušit` s `defaultAction` na `OK`, jak je zvykem u dialogů | Enter na výchozím tlačítku je gesto, které ruka udělá dřív, než oko dočte — a tady by odeslalo approve. `.borderedProminent` je jen vzhled, klávesu neváže; Esc zůstává na `Zrušit`, protože zavřít sheet je bezpečná operace. V názvu stojí **anglický `event`** (`APPROVE`), protože přesně ten se zapíše na GitHub |
| Tělo review se v potvrzení ukazuje **jako napsaný text**, ne vyrenderované Markdownem | Použít `MarkdownText`, který od #72 v aplikaci je, a ukázat náhled jako na GitHubu | Je to potvrzení **payloadu**, ne náhled výsledku. Permalinky, ze kterých GitHub udělá obarvený úryvek, se musí dát zkontrolovat jako odkazy — ve vyrenderované podobě není poznat, kam míří, a přitom právě tudy se do review dostávají nálezy mimo diff. Náhled by navíc sliboval shodu s GitHubem, kterou vlastní parser neumí zaručit |
| Sheet se po úspěchu **zavírá sám**, kromě odpovědi s neznámým stavem | Nechat ho otevřený s potvrzením a tlačítkem `Zavřít`, nebo zavírat vždycky | Vyžádané při zkoušení. Že review odešlo, je za sheetem vidět líp než v něm: draft zmizel z panelu i z řádku a v `Přehledu` přibylo moje review — potvrzovací okno navíc je kliknutí za informaci, kterou má člověk před sebou. Výjimka je odpověď, jejímuž **stavu nerozumíme**: „zkontroluj to na GitHubu“ se jinde nedozví, protože review tam vypadá jako každé jiné. Zavírá se **až po** úklidu, který `send()` čeká, aby se okno neodhalilo ve starém stavu |
| Proč se nedá odeslat, odpovídá **`Policy.sendBlock` s důvodem**; `isSendable` bylo zahozeno | Nechat boolean `isSendable` a text důvodu skládat ve view | Boolean vedle funkce s důvodem je cesta, jak se zeptat a důvod nedostat — a mlčky zakázané tlačítko vypadá jako rozbitá aplikace. Pořadí důvodů kopíruje `GhReviewPublisher.submit` (sandbox → obsah → hlava PR), aby okno nehlásilo jiný důvod, než na kterém odeslání doopravdy skončí. Daň: `PublishScope` se vyhodnocuje i v `Policy`, takže testy odesílatelnosti musí běžet nad sandboxovým identifikátorem |
| `ReviewSubmission` drží **snímek draftu** a vzniká až kliknutím | Číst draft ze storu při každém překreslení sheetu | Co je v potvrzení vidět, to se odešle — snímek je jediné, čím se to dá tvrdit. Zároveň to drží tvrdou podmínku č. 1 bod 3: publisher se skládá až v `send()` a zaniká se zavřením sheetu, takže cesta ven není otevřená po celou dobu běhu aplikace. Proto je to i jediný stav, který si `PullRequestDetailView` drží ve `@State` místo ve storu |
| Po chybě, u které review **mohlo dojít**, se odeslání znovu nenabízí | Nechat tlačítko aktivní po každém selhání — draft zůstal, tak ať to jde zkusit | **Doplněno po vlastní revizi diffu u #68.** `malformedResponse` vzniká při **nulovém** exit kódu, tedy poté, co POST prošel; `timedOut` znamená, že jsme `gh` zabili sami po 30 s. Věta „nic se nemazalo, dá se zkusit znovu“ nad nimi odporovala jejich vlastnímu textu („zkontroluj na GitHubu, jestli review přesto nedošlo“) a druhý klik dělal **druhé review**, po kterém se draft smazal. Rozhoduje `PublishError.mightHaveReachedGitHub`, konzervativně: co se nedá s jistotou zařadit mezi odmítnutí, počítá se jako „možná odešlo“, protože falešné „zkontroluj GitHub“ stojí kliknutí a falešné „nic se nestalo“ approve navíc |
| Sheet drží **`ContentView`**, ne detail PR | Nechat ho v `PullRequestDetailView`, kde `ReviewSubmission` vzniká | **Doplněno po vlastní revizi diffu u #68.** Detail se kreslí jen tak dlouho, dokud je vybraný PR v seznamu z pollingu — a odeslané review ruší `review-requested`, takže ten PR na příštím tiku (≤60 s) vypadne. Sheet by zmizel bez stopy uprostřed odesílání, nebo zrovna nad hláškou o odpovědi, které nerozumíme, což je jediné místo, kde se to člověk dozví. Modalita chrání před uživatelem, ne před tikem pollingu |
| Konverzace bez kotvy patří do tabu **`Overview`**, ne do spodního panelu | Tab `Konverzace` vedle `Nálezů` a `Průběhu`, jak to měla původní podoba #64 | Spodní panel je úzký pruh pod diffem a existuje proto, aby se obsah četl **vedle kódu**, kterého se týká. Vlákno bez kotvy žádný takový kód nemá. Dva domovy pro konverzaci navíc znamenají hledat komentář na dvou místech |
| Krátké sloupce dostanou **`max`**, `Nález` zůstane bez stropu | Dát jim pevnou šířku (`.width(140)`), což poměr drží nejspolehlivěji | Pevná šířka zabíjí tažení, které zadání #60 výslovně chce zachovat. `max` je jediné, čím se v `Table` dá říct „dál už neroste“, a přebytek pak spadne tomu jednomu sloupci, který strop nemá. Rozmezí jsou schválně široká (`Kategorie` 100–190, `Místo` 120–420), aby tažení pořád k něčemu bylo; `Reviewer` je výjimka (185–260) a proč, je v řádku pod tímhle. `Nález` má naopak jen `min: 220`, ať v úzkém okně mizí ostatní a ne on |
| `Reviewer` má nejdelší běžné id v **`min`** (185 pt), ne v `ideal` | Nastavit `ideal` a nechat `min` malé, ať se dá sloupec přetáhnout úzko | Vyžádané při zkoušení, a napodruhé: `ideal: 175` sloupec **nedodržel** — vyšel na ~139 pt a text se ořezal, protože `ideal` je nápověda, kterou rozdělování šířky přebije. Podlaha je jediné, co ji zaručí. `code-review:code-review` je při 13pt systémovém fontu 154,7 pt a odsazení buňky bere dalších ~19 (obojí změřeno, ne odhadnuto), a je to výchozí id z konfigurace — takže sloupec, do kterého se nevejde, se ořezává **pořád**. Nápověda je záchrana pro výjimku, ne náhrada za čitelnost běžného případu. Cena je, že se `Reviewer` nedá přetáhnout pod 185; přesně to je ale ta záruka. Delší id se ořeže a to už nevadí |
| Nápověda u nálezu bez místa je **věta**, ne pomlčka | `String?` s podmíněným `.help`, nebo `.help("")` u nálezu bez cesty | Sloupec ukazuje `—` a tooltip s pomlčkou nevysvětluje nic; prázdný řetězec je navíc nedefinované chování AppKitu. Věta („Nález nepatří ke konkrétnímu místu v kódu.“) je jediné, co k tomu jde říct — a jako vedlejší efekt odpadne `if` ve view a text se testuje ve `FindingRow` bez UI |
| Nápovědu dostal **každý sloupec**, ne jen `Nález` a `Místo` | Držet se zadání #60 a dát tooltip jen těm dvěma, které se ořezávají ve výchozím poměru | **Doplněno proti zadání.** Zadání jmenuje ty dva, u kterých je ořez vidět hned, ale strop není to, co o ořezu rozhoduje — táhnout se dá každým sloupcem až na jeho `min`, a tam neuveze ani `Kategorie` „bez kategorie“ s výstražnou ikonou. Argument „tooltip všude znamená tooltip nikde“ platí na **ozdobné** nápovědy; tyhle zpřístupňují ořezaný údaj, a ten je jinak nedosažitelný. Dělá to tak i Finder |
| Spike #62 potvrdil **atomicitu** odesílání, takže `ReviewPublisher` nemá obrannou validaci nad rozřazením nálezů | Předpokládat částečné odeslání a před každým `POST`em ověřit každý komentář proti diffu podruhé | Změřeno (`docs/github-review-api.md`): payload s jedním komentářem mimo hunky vrátí 422 `Line could not be resolved` a na PR **nezůstane nic**, ani platné komentáře. Rozřadit nálezy na řádkové komentáře a permalinky v těle se musí tak jako tak — a `DiffRow.anchor` to od #19 umí. Co atomicita mění, je **cena omylu** v tom rozřazení: 422 bez následků místo půlky review na PR kolegy, kterou nelze vzít zpátky. Druhá validace nad tou první by se s ní rozešla a chránila by proti něčemu, co už nehrozí. Kdyby atomicita neplatila, mění to `#67` (pokračování nebo úklid), `#68` (proces místo jedné akce) i model draftu |
| Nález **mimo diff** se do review dostane jako **permalink v těle**, ne zahozením | Zahodit ho, nebo ho vypsat jako holou cestu s číslem řádku | Změřeno: GitHub permalink `blob/<sha>/<path>#L<n>` v těle review vyrenderuje jako obarvený úryvek kódu, a funguje i rozsah `#L40-L43`. Reviewer čte celý pracovní strom, takže hlásí mimo diff **běžně** — a řádkový komentář tam GitHub nepustí. Bez tohohle by se právě ty nálezy z odeslaného review tiše ztrácely, tedy nejdražší chyba, jakou aplikace umí udělat |
| `headSha` se ověřuje **v aplikaci** těsně před odesláním | Spolehnout se na to, že GitHub odmítne review proti zastaralému commitu | Změřeno: **nepomůže** — review se starým `commit_id` GitHub přijme a pinne ho na starý commit. Je to tentýž důvod jako u tvrdé podmínky č. 5: ochrana proti nálezům proti neexistujícímu kódu musí být naše, protože nikdo jiný ji neudělá |
| Zastaralý komentář se pozná na **`line == nil`**, ne na `position` | Použít `position == nil`, jak se to obvykle popisuje | Změřeno: po zmizení kotvy vyšlo `line: null`, ale `position` zůstalo **nenulové** (1) při `original_position: 5`. `original_line` se zachovává, takže se z něj dá přečíst, kde komentář býval. Zbývá doměřit mezistav „řádek se posunul, ale v diffu zůstal“ — vynucené zastarání vyšlo z prázdného diffu, což je krajní varianta. Rozhodne to `#69` |
| Na **vlastním PR** se verdikt neschovává za chybu, ale za nedostupné tlačítko | Nechat uživatele odeslat a zobrazit 422, které vrátí GitHub | Změřeno: zakázané je `APPROVE` **i** `REQUEST_CHANGES` (zadání #62 se ptalo jen na první), `COMMENT` projde. `Policy.suggestedVerdict` přitom umí právě ty dva zakázané, takže bez téhle brány by se návrh verdiktu na vlastním PR nabízel a spadl. Aplikace vlastní PR v seznamu mít může |
| Konverzace jde **jedním GraphQL dotazem**, ne třemi REST endpointy | `pulls/{n}/reviews`, `pulls/{n}/comments` a `issues/{n}/comments` — cesta, kterou už zbytek gateway umí | REST **`isResolved` u vláken nemá vůbec**, takže by otázka „co s vyřešenými vlákny“ neměla odpověď a vyřešená vlákna by se ukazovala jako otevřená. Navíc tři podprocesy proti jednomu; změřeno, že celý GraphQL dotaz stojí **1 bod z 5000/h** bez ohledu na velikost PR (2 vlákna i 38). Cena je vlastní DTO vrstva pro cizí schéma, ale tu by tři REST odpovědi potřebovaly taky |
| Zkrácení nese `ConversationPage` a `isTruncated` je **`or`** dvou signálů | Vybrat jeden zdroj pravdy — buď `hasNextPage`, nebo `items.count < total` | Nebezpečný směr je jediný: tvrdit „máš všechno“, když ne. `or` se v něm splést nemůže, kdežto vybraný signál ano, protože jeden z nich může přijít jinak, než čekáme, a druhý by to nezachytil. `total` se drží i tak, protože z něj vyjde „1 ze 38“ — samotný boolean řekne jen, že něco chybí, ne kolik. Že se ty dva na skutečných datech nerozcházejí, hlídá test proti třem fixtures; bez něj by `or` schoval, že jednomu z nich nerozumíme |
| `Conversation.isTruncated` se dívá **i do vláken** | Počítat jen tři horní seznamy | Useknutá odpověď **uvnitř** vlákna se na počtu vláken neprojeví — jejich počet vyjde správně a chybí až ta odpověď, kvůli které se člověk do vlákna dívá |
| Vlákno se kotví přes `anchorLine` = `line ?? originalLine` | Použít `line` a zastaralé vlákno nekreslit | Změřeno na `cli/cli#13084`: ze 38 vláken bylo 24 zastaralých a `line == nil` právě u nich, ani jedna výjimka. Zastaralých je tedy **většina** a schovat je znamená schovat většinu konverzace. `originalLine` zůstává vždycky, takže je čím kotvit — a komentář na starém řádku je lepší než zmizelý komentář kolegy |
| `ThreadComment` drží `replyToID`, ne vnořený komentář | Složit z vlákna strom odpovědí | GitHub vrací vlákno jako **plochý seznam**. Strom by si vynutil rozhodnutí, co s odpovědí na komentář, který v odpovědi není (useknutá stránka) — a to je otázka, kterou plochý seznam s odkazem zpátky neotevírá vůbec. Vlákna navíc bývají dvě položky, takže se strom nemá kde vyplatit |
| `viewer` se drží **jednou** na `Conversation`, ne jako `isMine` na komentáři | Spočítat příznak při mapování a mít odpověď u každého komentáře | „Je to moje“ je vztah mezi komentářem a tím, kdo se dívá, ne vlastnost komentáře. Uložený příznak by po přepnutí účtu tvrdil něco jiného, než je pravda, a v modelu by ležela odvozená hodnota vedle toho, z čeho se odvodila |
| Stav cizího review je **vnořený** `SubmittedReview.State` | Vlastní typ `GitHubReviewState` na stejné úrovni jako `ReviewState` | V repu už jsou dvě „review“ hodnoty (`ReviewState` pro náš běh, `ReviewVerdict` pro náš návrh) a tohle je třetí význam téhož slova. Vnoření je jediné, co je odliší i při doplňování v editoru — tatáž lekce jako u tří „jazyků“ (#52) |
| Neznámý stav review dá `nil`, neznámý stav PR **vyhodí chybu** | Sjednotit to a být přísný nebo tolerantní u obojího | Rozdíl je v následku. Ze stavu PR plyne chování (draft se sám nereviewuje), takže překlep tam nesmí projít. Cizí review je zobrazení názoru a kvůli jedné nové hodnotě ve schématu GitHubu nemají zmizet všechna vlákna a komentáře — to je ta „ztracená data vypadají jako nic tu nebylo“ past |
| `ReviewThread` nese i `side` (`DiffSide`), i když ho rozpis #63 nejmenuje | Držet se vyjmenovaných polí a stranu doplnit až v #64 | **Doplněno proti zadání.** Bez strany by vlákno na **smazaném** řádku (`LEFT`) vyšlo v #64 nad novým obsahem, tedy tiše u cizího kódu — chyba, kterou nikdo nepozná. Ve vzorku byly všechny `RIGHT`, což je přesně ten důvod, proč se na to nedá spolehnout mlčky |
| `ThreadComment` je sdílený tvar pro vlákna **i** komentáře pod PR | Vlastní `IssueComment` pro konverzaci bez kotvy | Rozpis #63 jmenuje čtyři modely a tenhle je jeden z nich; komentář pod PR je tentýž tvar bez vlákna, takže `replyToID` je u něj `nil`. Dva téměř shodné typy by znamenaly dvě cesty mapování a dvě místa, kde se dá zapomenout na `viewer`. Cena je jméno, které u komentáře pod PR není přesné — proto to má v dokumentaci napsané |
| Zkrácení vlákna je vidět i ve **sbalené** hlavičce (odznak `+N`) | Hlásit ho jen v rozbaleném vlákně, kde je na to místo | Vyřešené vlákno je sbalené **výchozím stavem**, takže useknuté by vypadalo úplné a nebyl by důvod ho otevřít — tedy přesně to, proti čemu je pravidlo „utnutá data nesmí vypadat jako úplná“. Odznak nese číslo, ne jen ikonu: „chybí něco“ nedává důvod jít na GitHub, „chybí 12“ ano |
| Vlákno **bez řádku v aktuálním diffu se nekreslí vůbec** | Ukázat ho u hlavičky souboru s číslem z `originalLine`, jako se to dělá u nálezů mimo diff | Vypadá to jako nekonzistence, ale je to opačný případ. Nález je hlášený proti **současnému** commitu (nálezy jsou klíčované `headSha`), takže jeho číslo platí a dá se k němu dotáhnout kód. Zastaralé vlákno má číslo ze **starého headu** — na tom řádku dnes stojí něco jiného, takže bublina by lhala o tom, čeho se komentář týká. Kotví se proto podle `line`, nikdy podle `anchorLine`; `originalLine` slouží k pojmenování v `Overview` (#72) |
| Vlákna se na jednom řádku **neslévají**, nálezy ano | Sloučit je do jedné bubliny s odznakem počtu, jak to dělá `FindingGroup` | Nález je tvrzení a dva reviewery na jednom řádku znamenají shodu, kterou je užitečné vidět jako `2×`. Vlákno je konverzace s vlastním stavem vyřešení — sloučit dvě znamená, že jedno vyřešené a jedno otevřené vlákno mají jeden odznak, který nemůže být pravdivý |
| Výchozí rozbalení se **odvozuje z vlákna**, drží se jen odchylka | Držet množinu rozbalených vláken a naplnit ji při načtení konverzace | Výchozí stav je per vlákno (nevyřešené rozbalené, vyřešené sbalené), takže seznam rozbalených by se musel plnit při každém načtení — a ruční obnovení konverzace by uživateli zahodilo, co si zavřel. Odchylka od výchozího stavu tenhle problém nemá a `Policy.isThreadExpanded` ji drží na jednom místě |
| Stav rozbalení žije v `AppStore`, ne v bublině | `@State` uvnitř `ThreadBubbleView` — je to lokální věc jednoho view | Bublina je buňka **líného** seznamu: odscrollováním se zahodí a při návratu se postaví znovu, takže by rozbalené vlákno samo zavřelo. Tatáž past jako u příznaku „připravuji“ v detailu PR |
| Překliknutá vlákna se drží **per PR** (`[PRIdentifier: Set<String>]`) | Plochá množina `id` vláken, uklízená podle vláken v načtených konverzacích | **Opraveno v průběhu #64 po nálezu z review.** Plochá množina vypadala levněji, protože `id` vlákna je globálně unikátní a svoje PR nenese — jenže úklid podle **načtených** konverzací selhal na stavu `.failed`: PR po výpadku sítě v mapě zůstane, ale žádná vlákna nedá, takže by se množina vyprázdnila a uživateli by naskočilo výchozí rozbalení. Klíč per PR dovolí uklízet podle toho, jestli PR zmizel ze seznamu, což je ta otázka, na kterou úklid opravdu odpovídá. Původní důvod („složený klíč jen kvůli úklidu“) tím padl |
| Konverzace se načítá **při výběru PR**, ne pollingem | Dotahovat ji v tiku pollingu, ať je vždycky svěží | Tatáž N+1 past, kvůli které polling netahá ani detail PR: jeden tik by byl N podprocesů. Cache podle `updatedAt` je stejná jako u diffu a ruční obnovení řeší to, že kolega odpoví za minutu, kdežto tik chodí po minutách |
| Přepínač se přejmenoval z `Bubliny` na **`Nálezy`** | Nechat obecný název a schovávat jím i vlákna | Vyžádané při zkoušení. Obecný název slibuje, že vypne obojí, ale schovává jen nálezy — a schovávat s nimi i vlákna by bylo horší: cizí komentář u kódu je důvod, proč se na PR člověk dívá. Klíč v `UserDefaults` zůstal (`showFindingBubbles`), aby se uživateli nezahodila předvolba |
| Kam vlákno patří, rozhoduje **jedna** funkce (`Policy.matches`) a řídí se `side` | Porovnávat číslo vlákna s `newNumber` řádku, jako to dělá kotva nálezu | **Opraveno v průběhu #64 po nálezu z review.** Komentář k **odebranému** řádku má číslo ze staré verze souboru, takže porovnání s novým číslem ho posadí na jiný kód — a nikdo to nepozná, protože bublina vypadá správně. Je to zvlášť trapné proto, že `side` se do modelu přidával **právě kvůli tomu** a kotvení ho pak ignorovalo. Funkce je jedna, aby se výběr (`threadsInTheDiff`) a umístění (`DiffRow`) nemohly rozejít — dvě kopie téhož pravidla jsou přesně to, co se rozešlo |
| Draft bydlí **lokálně**, ne jako serverové pending review | Zakládat na GitHubu pending review a přidávat do něj komentáře přes API | Pending review jsou **už odeslaná data**: jsou vidět v API a blokují další review (změřeno u #62 — 422 `User can only have one pending review per pull request`). Tím by padla zásada, že bez potvrzení nic neopustí stroj, a každá úprava komentáře by byla volání API. Cena je vlastní store, ale ten je tak jako tak potřeba pro rozdělanou práci, která má přežít restart |
| Jeden draft na **PR**, ne na `(PR, headSha)` jako uložené nálezy | Klíčovat i commitem, ať se draft nemíchá mezi verzemi kódu | Nálezy jsou strojový výsledek proti konkrétnímu commitu a novým commitem opravdu zastarají. Draft je ručně psaná práce, která se pushem kolegy nemá zahodit — `headSha` v něm proto jen říká, proti čemu je psaný, a nový commit **blokuje odeslání**, nemaže. Vlastní próza nezastarává tak rychle jako strojový nález |
| Prázdný draft se **maže**, ne ukládá | Ukládat, co přijde, a mazat až na výslovné zahození | Bez toho by v cache zůstal soubor po každém PR, které si někdo jen otevřel a rozklikl komentář — a „draft existuje“ by přestalo znamenat „je co poslat“, což je přesně to, na čem #66 a #68 stojí. Tentýž vzor jako `Configuration.setRepository`, které maže záznam podle prázdnosti |
| Draft, ve kterém je **jen verdikt**, prázdný není | Považovat za prázdné všechno bez prózy a bez komentářů | Schválení bez prózy je plnohodnotné review — v datech z #63 to byla **čtvrtina** vzorku (`cli/cli#11451`). Kdyby ho `isEmpty` bralo jako prázdné, nešlo by PR odklepnout, dokud k tomu člověk něco nenapíše. Odhalil to test, který původně tvrdil opak |
| `ReviewDraft.Verdict` je **vnořený** a má tři případy | Použít `ReviewVerdict`, který v repu už je | `ReviewVerdict` je náš *návrh* odvozený z nálezů a má dva případy; tohle je *volba člověka* a musí mít tři, protože `COMMENT` je na GitHubu plnohodnotná varianta — a na vlastním PR jediná povolená (změřeno u #62). Vnoření je totéž řešení jako u `SubmittedReview.State`: čtyři významy slova „review“ se nemají dát zaměnit ani při doplňování v editoru |
| Komentář drží `side`, i když má číslo řádku | Dopočítat stranu při odesílání z druhu řádku | Odebraný řádek má číslo ze **staré** verze souboru, takže bez uložené strany by komentář odešel na jiný řádek. Dopočítávat ji později znamená mít diff po ruce i v okamžiku odeslání — a diff se mezitím mohl načíst znovu. Je to tatáž lekce jako u kotvení vláken v #64, kde se `side` ignorovalo a komentář sedl na cizí kód |
| `Origin` má dva případy a **žádný odkaz na nález** | Držet u převzatého komentáře revieweera, ze kterého vznikl | `Finding` identitu nemá a text nálezu je už v `body`, takže by šlo o jméno navíc, které nikdo nečte — přesně ta mrtvá váha, kterou tenhle repozitář hlídá. Kdyby #66 chtělo popisek „z nálezu od code-review“, doplní se to tam, kde se to použije |
| Komentovatelnost je čistá funkce nad `(DiffLine, FileDiff)` | Rozhodovat ji při skládání řádků v `DiffRow`, kde se stejně ví, co je z hunku | Rozbalený kontext se skládá jako **obyčejný kontext s oběma čísly**, takže ze samotného `DiffLine` ho poznat nelze — příslušnost k hunku se musí ověřit proti souboru. Jako čistá funkce v `Policy` se to testuje bez UI a použije i v `#66` (nabídnout tlačítko) i v `#67` (poslední kontrola před odesláním); v `DiffRow` by to byla logika schovaná v skládání |
| `PRIdentifier` je **`Comparable`** a všechna řazení jdou přes něj | Řadit podle `description`, jak to dělaly tři místa v repu | **Opraveno v průběhu #65 po nálezu z review.** Řetězcově vyjde `#10` před `#2`. Determinismus to zachová, takže testy prošly a nikdo si toho nevšiml — ale seznam, ve kterém jde desítka před dvojkou, vypadá rozbitě, a to je jediné, co od pořadí chceme. Byla to tatáž chyba na třech místech (`ReviewStore`, `PullRequestList`, `ReviewDraftStore`), proto je pravidlo na identifikátoru a ne v každém volajícím |
| Draft mimo své místo se do výpisu **nedostane** a počítá se jako nečitelný | Vypsat ho podle obsahu, protože obsah je pravda | Obsah pravda je, ale výpis by pak nabídl draft pro PR X, který `load(for: X)` nenajde — a rozpor mezi „vidím ho“ a „nedá se otevřít“ je horší než počítadlo, které o anomálii aspoň řekne. Porovnávají se **kanonické** cesty: `FileManager.enumerator` vrací URL jinak než `CacheLayout` (`/private/var` proti `/var`), takže naivní `==` nad `URL` odmítne i soubor na svém místě — chytily to testy, které po té změně zhasly všechny |
| Symlinky se ve výpisu draftů **přeskakují a počítají** | Spolehnout se na to, že `enumerator` symlinky nesleduje, jak to tvrdila dokumentace | **Doplněno v průběhu #65 po nálezu z review, a měřením proti němu.** Tvrzení platilo jen z poloviny: odkaz na **složku** enumerace opravdu nesleduje, ale odkaz na **soubor** vylistuje — a ten by se přečetl mimo cache. Kontrola „leží soubor tam, kam patří“ to nezachytí, protože rozbaluje symlinky na obou stranách a cíl vyjde rovný cíli; test to odhalil tím, že spadl. Odmítá se tedy výslovně (`.isSymbolicLinkKey`) a počítá se, protože něco v cache leží a nedá se z toho draft udělat. `ReviewStore` má tentýž vzor a je na to #106 — pre-existující chování, které do tohohle diffu nepatří |
| Tvrdá podmínka „nikdy nic neposílat“ se nahrazuje **šesti kontrolovatelnými pravidly** | Nechat podmínku a odesílání neimplementovat; nebo ji zrušit a spolehnout se na to, že se odesílá jen z jednoho místa | Podmínku vynucoval **typ** (`GitHubGateway` bez zápisových metod) a to je vlastnost, o kterou nechceme přijít jen proto, že jedna cesta ven vznikla. Nová formulace proto drží ten typ nedotčený a přidává k němu pět dalších věcí, které jdou **zkontrolovat**, ne jen slíbit: jedna metoda v protokolu, `grep ReviewPublishing` s jediným výskytem, publisher mimo `AppStore`, pre-flight na `headSha` a atomicita. „Odesílá se jen z jednoho místa“ bez těch kontrol je slib, ne podmínka |
| Odesílání jde **zatím jen do sandboxu** (`PublishScope`) | Pustit ho na všechna repa hned, protože pre-flight a atomicita jsou hotové | Vyžádané. Pravidlo „jediná cesta ven“ je nové a review odeslané omylem na PR kolegy se nedá vzít zpátky — proto si to nejdřív projde provozem tam, kde omyl nikoho nestojí čas. Seznam je **zadrátovaný, ne v konfiguraci**: kdyby se dal změnit editací `config.json`, není to brána, ale nastavení, a omyl v ručně editovaném souboru by odeslal review na ostré repo. Rozšíření tak vyžaduje změnu kódu, review a release. Vyřazení je #107 |
| Pre-flight jde přes **`GitHubGateway.fetchDetail`**, ne přes vlastní `gh pr view` | Držet se zadání #67 („nad `ProcessRunning`“) a zavolat `gh pr view` v publisheru | **Odchylka od zadání.** Vlastní volání by byl druhý seznam `--json` polí a druhé mapování téhož DTO, které se s prvním mohou rozejít — a rozchod v `headSha` je zrovna to, co má pre-flight hlídat. Gateway je navíc **read-only**, takže se tím nic neotvírá; „nad `ProcessRunning`“ platí pro odesílání, tedy pro to, o co v modulu jde |
| Payload jde **dočasným souborem**, ne stdinem | Přidat `ProcessRunning` možnost poslat stdin | `ProcessRunning` má fake implementaci v každém druhém testu a metodu, kterou by nikdy nezavolaly, by musely dopsat všechny — tatáž úvaha, kvůli které je `ProcessStreaming` vlastní protokol. Soubor je navíc přesně ta cesta, kterou se payload ověřoval ve spike (`gh api --input`). Práva `0600`, protože je v něm nezveřejněný text review, a maže se v `defer` |
| `PublishError.pathOutsideDiff` je **vlastní případ**, ne varianta `lineOutsideDiff` | Sloučit obojí do „komentář míří mimo diff“ | Objeveno při ověřování #67 proti živému API: komentář na soubor, který v diffu není vůbec, vrací `Path could not be resolved`, ne `Line …`. Rada „přesuň komentář na řádek uvnitř diffu“ je u chybějícího souboru **nepravdivá** — správná je smazat ho nebo načíst diff znovu. Dvě chyby, dvě rady |
| Práva `0600` se nastavují na **prázdný** soubor a obsah se píše teprve pak | Zapsat obsah `.atomic` a práva nastavit po něm | **Opraveno v průběhu #67 po nálezu z review.** Původní pořadí mělo okno, ve kterém text review ležel v systémové dočasné složce se výchozími právy — a selhání kroku po zápisu ho tam navíc **nechalo**, protože `defer` s úklidem se registruje až u volajícího. Cena je, že zápis nesmí být `.atomic`: ten píše vedle a přejmenováním by práva zahodil. Atomicita tu nic neřeší, protože soubor čte podproces, který se spouští až po dokončení zápisu |
| Zrušení odesílání se propaguje jako **`CancellationError`** | Nechat ho spadnout do obecného `catch` a přemapovat na `toolUnavailable` | **Opraveno v průběhu #67 po nálezu z review.** Obecný `catch` zachytil i zrušení, takže by okno nad odesláním, které si člověk sám zrušil, ukázalo „gh se nepodařilo spustit“. `ReviewRunner` drží totéž pravidlo — vyhazuje jedině `CancellationError` — a je dobře, aby v tom byly oba moduly stejné |
| `PullRequestState` má **český popisek** u modelu | Přeložit stav v hlášce, která ho potřebuje | **Doplněno v průběhu #67 po nálezu z review.** `rawValue` je anglický a jde do JSONu na disk, takže interpolovat ho do české věty znamená ukázat uživateli `closed` uprostřed češtiny. U modelu proto, aby druhá hláška (#68 bude mít sheet se stavem PR) nezaváděla druhý překlad, který se s tímhle rozejde |
| `ReviewDraftComment.Origin` nese u převzatého nálezu **jméno revieweera** | Nechat `Origin` jako dva bezparametrové případy, jak ho zavedlo #65, a odznak „už je v draftu“ rozhodovat podle kotvy `(cesta, řádek, strana)` | **Změna rozhodnutí z #65**, které jméno revieweera odmítlo jako mrtvou váhu — a mělo pravdu, dokud nikdo nečetl. Čtenář se v #66 našel: odznak v bublině. Podle kotvy to nejde, protože dva reviewery na jednom řádku jsou běžné (kvůli tomu existuje odznak `2×`) — po převzetí prvního by odznak naskočil i u druhého a ten by z odeslaného review tiše vypadl. Odkaz na `Finding` to pořád není (`Finding` identitu nemá); zbytková nepřesnost je, že dva nálezy **téhož** revieweera na jednom řádku se nerozliší. Migrace nebyla potřeba: #65 byla vrstva bez UI, takže draft na disku nemohl vzniknout |
| Nález mimo diff se do těla přidá **rovnou při převzetí** a panel se přepne na tab s tělem | Nabídnout dialog „nejde to jako komentář, chceš to do těla?“, nebo tlačítko schovat | Dialog nad rozhodnutím, které má jedinou rozumnou odpověď, je klikačka; schované tlačítko by znamenalo, že nález mimo diff se do review nedá dostat vůbec — a reviewer hlásí mimo diff **běžně**, protože čte celý pracovní strom. Přepnutí tabu je tam proto, že jinak text spadne někam, kde ho nikdo nehledá. Že to jde do těla a proč, říká tlačítko **dopředu** (popisek plus věta vedle), ne až tooltip |
| Komentář se zakládá **prázdný** a při uložení prázdného se zahodí | Držet rozepsaný komentář ve stavu view a do draftu ho vložit až po potvrzení (jako `Add review comment` na GitHubu) | Bublina je buňka **líného** seznamu: odscrollováním se zahodí, takže nepotvrzený text ve `@State` by zmizel — a ztracená věta je tady to nejdražší. Draft jako jediný zdroj pravdy tenhle problém nemá. Cena je prázdný komentář v draftu, což řeší zahození při prázdném uložení plus `Policy.sendBlock` (do #68 `isSendable`), které prázdný komentář nepustí ven (GitHub by odmítl **celé** review, protože odeslání je atomické) |
| Text draftu se do store ukládá **odloženě** (400 ms) a vždycky při zmizení view | Zapisovat každý úhoz přímo do `AppStore` | Draft čtou bubliny v diffu, takže zápis na úhoz překresluje celý diff — u PR o tisících řádků je to psaní s prodlevou. Odklad je tentýž vzor jako v okně nastavení. Cena je okno ~400 ms, ve kterém rozepsaná věta není na disku; zavírá ho `onDisappear` (přepnutí PR, odscrollování bubliny) a `.id(pullRequest)` na editoru těla, bez kterého by přepnutí PR jen přepsalo obsah pole a text by se ztratil |
| Detail PR se dotahuje **při výběru řádku** | Dotáhnout ho líně až při první úpravě draftu; nebo `headRefOid` přidat do GraphQL dotazu na konverzaci, který se dělá tak jako tak | Banner „píšeš proti staršímu commitu“ musí být vidět **dřív**, než se začne psát, takže líné dotažení odpadá — a dvě spouštěcí místa pro tentýž fetch jsou dvě místa, kde se dá zapomenout. GraphQL varianta by byla zdarma, ale svázala by zakládání draftu s úspěchem dotazu na cizí konverzaci a `headSha` by se propsal do modelu `Conversation`, kde nemá co dělat. Cena je jeden `gh pr view` na výběr PR (cache podle `updatedAt`), tedy tolik jako diff a konverzace |
| Panel je vidět **vždycky**, i u PR bez review | Ukazovat ho jako dosud až se záznamem nebo běžícím review | Od #66 v panelu bydlí rozdělané review a to se zakládá od nuly — bez trvalého panelu by nebylo kde vybrat verdikt ani napsat tělo, dokud nedoběhne review, které s tím nemá nic společného. Cena je, že u PR bez review zabírá panel pruh se sdělením „nálezy nejsou“; sbalit se dá a volba přetéká mezi PR |
| Draft se v `AppStore` při úklidu **nezahazuje**, na rozdíl od diffu a konverzace | Uklízet ho podle seznamu PR jako všechno ostatní | Diff jsou megabajty, draft je jeden malý záznam na PR — a je to **ručně psaná práce**, kterou by zmizení PR ze seznamu (zavření, dočasný výpadek zdroje) zahodilo z paměti, ačkoli na disku zůstane. Nesymetrie je záměr, ne opomenutí |
| Výchozí záložka PR je **`Přehled`**, ne `Změněné soubory` | Držet se zadání #72, které předepisovalo `Files changed` s tím, že kvůli diffu je aplikace otevřená | **Vyžádané při zkoušení.** Popis PR a diskuze je to, co se čte **než** se člověk podívá na kód — a stejně to má GitHub, kde je `Overview` vstupní tab. Diff je jedno kliknutí daleko a volba se pamatuje per PR, takže kdo chce jít rovnou na kód, přijde o jedno kliknutí jednou. Výchozí hodnota žije na jednom místě (`PullRequestTab.standard`) a je na to test, aby se neroze­šla s dokumentací |
| Záložky jsou **podtržené, vlastní view**, ne `Picker(.segmented)` | Použít segmentovaný přepínač, jako se v okně přepínají taby panelu | Vyžádané při zkoušení („ať to vypadá jako záložky“). Segmentovaný přepínač znamená „vyber jednu hodnotu ze sady“ — tak se v tomhle okně filtrují reviewery a přepínají taby spodního panelu; tohle přepíná **celou obrazovku**. Podtržená záložka to říká na první pohled a je to zvyklost odjinud. Cena je vlastní view (~100 řádků) s hoverem a přejezdem podtržení |
| Spodní panel je vidět **v obou záložkách** | Držet se zadání, které `Změněné soubory` popisovalo jako dosavadní obrazovku beze změny | **Doplněno proti zadání**, protože se mezitím změnilo, co v panelu je: #66 do něj přidalo rozdělané review. Nálezy bez místa v kódu, průběh běhu i moje review se vážou k celému PR, ne k diffu — a schované za přepnutí tabu by znamenaly, že se rozepsané review přepnutím na `Přehled` „ztratí“ |
| Zastaralá vlákna v `Přehledu` kreslí **tatáž bublina jako u kódu** (`ThreadBubbleView` s nulovým odsazením) | Napsat pro přehled vlastní, jednodušší vykreslení vlákna | Vlákno je pořád vlákno: má stav vyřešení, odznak `já`, zkrácení a odpovědi. Druhé vykreslení by znamenalo dvě místa, která se musí držet stejně — a rozejít se umí tiše (odznak zkrácení chybí zrovna v tom, kde se na vlákno člověk dívá). Cena je parametr odsazení, protože u kódu bublina míří do sloupce s obsahem a v přehledu žádná čísla řádků nejsou. Nad bublinou je navíc `cesta:řádek`, bez kterého by zastaralé vlákno nešlo zařadit |
| Review **bez verdiktu a bez prózy** se v `Přehledu` zahazuje | Vypsat všechna review, která GraphQL vrátí | Každý řádkový komentář na GitHubu patří do nějakého review, takže u PR s pěti komentáři u kódu přijde pět review, která nejsou tvrzením — jsou to obálky. Jako „někdo napsal review: (nic)“ by z přehledu byl seznam prázdných položek. Schválení s prázdným tělem se **nezahazuje**: to je plnohodnotný verdikt (čtvrtina vzorku u #63) |
| Popis PR se bere z **`gh pr view --json body`**, ne z GraphQL dotazu na konverzaci | Přidat `body` do dotazu na konverzaci, který se stejně dělá, a mít to za jeden bod zdarma | Detail se od #66 dotahuje při výběru řádku kvůli `headSha`, takže popis nestojí ani jedno volání navíc — a patří k **metadatům PR**, ne do `Conversation`, která je snímek *cizí* diskuze. GraphQL varianta by navíc svázala zobrazení popisu s úspěchem dotazu na komentáře |
| Markdown se **renderuje vlastním blokovým parserem** | Nechat text holý (rozhodnutí z prvního průchodu #72); nebo pustit celý text do `AttributedString(markdown:)`; nebo přidat závislost (MarkdownUI, swift-markdown) | **Rozhodnutí z průběhu #72 zrušené na vyžádání** („naformátuj ty texty“). Holý text s `##` a `- [x]` se čte špatně. `AttributedString` nad celým textem umí inline výborně, ale bloky ve `Text`u **tiše spolkne** — přesně ta ztráta, kvůli které se to původně nedělalo. Vlastní parser struktury plus systémový parser inline dává obojí a drží invariant „žádný řádek se neztratí“. Závislost byla zvažovaná a zamítnutá: MarkdownUI by uměl i tabulky, ale je to třetí strana a SPM se do Xcode projektu přidává **editací `project.pbxproj`**, do kterého CLAUDE.md sahat zakazuje; swift-markdown je jen parser, takže by vykreslování zůstalo naše. Cena vlastního řešení: tabulky zůstávají monospace řádky a kód v blocích se neobarvuje |
| HTML v komentářích se **strhává až ve view**, ne v parseru | Odstranit tagy hned při parsování, ať model nese čistý text | Model tak drží to, co přišlo z GitHubu, a invariant „nic se neztratilo“ se dá porovnat proti vstupu. Rozhodnutí „`<p>` se v okně nemá čím projevit“ navíc patří tam, kde se kreslí. Výjimka jsou `<details>`, `<summary>` a `<!-- … -->`: ty nesou **strukturu** (rozbalovátko, text, který se nekreslí), a tu musí znát parser |
| Hlášky se přestěhovaly na **spodek okna, mimo `NavigationSplitView`** | Nechat je jako `safeAreaInset` pod seznamem PR | **Oprava dvou chyb naráz, vyžádaná při zkoušení.** Jako inset uvnitř sloupce split view způsobovaly, že obsah okna byl o výšku toho pruhu **vyšší než okno** a spodní hrana ho odřízla v obou sloupcích (změřeno accessibility: okno 874 pt, obsah 904; po skrytí bočního panelu rozdíl zmizel) — `List` si vezme celou dostupnou výšku a pruh pod ním ji pak překročí. A tatáž mašinerie (`invalidateSafeAreaInsets` uvnitř `updateConstraints` split view) stojí v crash reportu z 2026-08-03; reprodukovat ho na přání nejde, ale konstrukce, na kterou trace ukazuje, tam už není. Vedlejší efekt: je to směr, kterým měl stavový řádek jít (#31) |
| Skok na nález **přepne záložku** a `DiffView` na cíl reaguje `task(id:)` | Nechat skok bez efektu, když je vidět `Přehled` | Kliknutí, po kterém se nic nestane, vypadá jako rozbitá aplikace — a kdo klikne na nález, chce vidět ten kód. `onChange` přitom nestačí: při přepnutí z `Přehledu` diff **vzniká**, takže cíl už v něm je a žádná změna nepřijde. `task(id:)` se spustí i při vzniku |
| Cíl skoku se kotví **k vršku s odstupem** (90 pt), ne doprostřed | Nechat `anchor: .center`, jak to bylo od #20 | Vyžádané při zkoušení a doladěné na běžící aplikaci (140 → 96 → 90 pt). Doprostřed znamená půl obrazovky nad nálezem, ze které je vidět kód, co s ním nesouvisí; na vrch samotný zase cíl skončí pod ukotvenou hlavičkou souboru. `scrollTo` umí jen podíl výšky, takže se podíl počítá z **měřené** výšky diffu (`onGeometryChange`, jen měření — `GeometryReader` by sám zabral místo, což v tomhle okně už jednou uškodilo) |
| Okno má **`.windowResizability(.contentMinSize)`** a vlastní podlahu `700 × 400` | Nechat výchozí `.automatic`, které se o velikost okna stará samo | **Oprava mimo zadání #66, vyžádaná při zkoušení.** Okno se nedalo zmenšit na výšku vůbec — a nebylo to od #66, je to tak i na `main`. `.automatic` odvozuje minimum okna z toho, co si obsah **přeje**, a `List` v bočním panelu si přeje celou výšku svých řádků: při dvanácti PR vyšlo minimum 956 pt, tedy víc, než je vysoká obrazovka. Změřeno tím, že po skrytí bočního panelu se okno zmenšit dalo. `.contentMinSize` bere minimum, ne přání — cena je, že podlahu si musí říct aplikace sama, protože strop i dno jsou pak otevřené |
| Odznak rozdělaného review se nikde nejmenuje „draft“ | Použít slovo draft, jak se tomu říká v kódu i v issue | V řádku seznamu už `draft` znamená **rozpracovaný pull request** (GitHub draft PR), takže druhý význam vedle prvního je past. V UI se proto píše „rozdělané review“ a ikona je pero; v kódu zůstává `ReviewDraft`, protože tam je kontext jednoznačný |
