# pr-review — návrh

**Datum:** 2026-07-31
**Stav:** návrh odsouhlasen, neimplementováno
**Repo:** `ondrajodas/pr-review` (privátní)

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
- Načíst diff pro zobrazení (`gh pr diff`) — jen k zobrazení, reviewery čtou skutečné
  soubory.

Polling v intervalu (default 60 s). Jeden search dotaz na zdroj a poll je hluboko pod
rate limitem GitHub search API pro autentizovaného uživatele.

### 2. RepoCheckout

Vlastní všechny pracovní kopie. **Nikdy nesahá na uživatelovy klony** — mohou být
rozdělané, na jiné branchi, nebo už mít vlastní worktrees.

```
~/Library/Application Support/pr-review/
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
  --allowedTools Read,Grep,Glob,Bash(git:*)
  --model <z konfigurace>
  cwd: <cesta k worktree>
```

- **Read-only z principu.** `--allowedTools` neobsahuje `Write`, `Edit` ani obecný
  `Bash`. Je to bezpečnostní vlastnost (reviewer strukturálně nemůže změnit kód ani
  nikam nic poslat) i praktická věc: odpadne tím téměř každý důvod, proč by se Claude
  zastavil a chtěl povolení. Headless session nemá jak na permission prompt odpovědět,
  takže by jinak visela do timeoutu.
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

- **Skupiny v UI jsou podle `category`** — pojmenování od revieweera, ne interpretace
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
  `com.ondrajodas.pr-review`.
- **App Sandbox je vypnutý.** Aplikace spouští `git`, `gh` a `claude` a zapisuje do své
  cache mimo sandbox kontejner. Je to osobní nástroj, ne submission do App Store. Pro
  lokální použití stačí ad-hoc podpis (`codesign -s -`); Developer ID podpis a
  notarizace by byly potřeba až pro distribuci.
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

## K ověření před implementací

Flagy Claude Code CLI jsou psané z pracovní znalosti a před tím, než se na ně budeme
spoléhat, se musí potvrdit proti `claude --help` na nainstalované verzi (2.1.220):
přesný zápis `--output-format stream-json`, jestli je `--verbose` v print režimu
povinný, syntaxe `--allowedTools` pro scoped Bash patterny a tvar init eventu, který
nese `session_id`.
