# PRism

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

Hranol rozloží jeden paprsek na spektrum. Tahle aplikace dělá totéž s pull requestem —
pustí na něj několik nezávislých reviewerů a jejich nálezy schválně neslévá do jednoho
názoru.

> **Nikdy nic neposílá na GitHub.** Žádné komentáře, žádná review, žádné approve.
> Verdikt *approve / request changes* je návrh zobrazený v aplikaci. Je to tvrdá
> podmínka návrhu, ne zjednodušení první verze.

## Stav

**První použitelná verze: aplikace ukazuje moje skutečné PR.** Po startu si ověří, že má
`gh`, `git` i `claude` a že je `gh` přihlášený — jinak řekne, co chybí a čím se to spraví.
Pak se otevře seznam pull requestů napříč repozitáři, který se sám obnovuje: každý řádek
nese repo, číslo, titulek, autora a čas poslední změny. Při výpadku sítě zůstanou
poslední známá data a nad seznamem se objeví pruh, že nejsou aktuální; při rate limitu
pruh říká, kdy to zkusí znovu.

Review se zatím nespouští — stav u všech PR je `neběželo`. Z pěti fází
(viz [CLAUDE.md](CLAUDE.md)) je hotová první.

Postup se dá sledovat přes [releases](https://github.com/ondrajodas/PRism/releases) —
po každém mergnutém PR vzniká tag a release s popisem, co se změnilo a kde projekt
aktuálně je.

- [Návrh (specifikace)](docs/superpowers/specs/2026-07-31-prism-design.md) — plný
  návrh včetně záznamu rozhodnutí a zamítnutých alternativ
- [CLAUDE.md](CLAUDE.md) — pravidla pro práci v tomto repu

## Jak to funguje

1. **Polling GitHubu** přes `gh` — hledají se PR, u kterých je po mně požadované review
   (`review-requested:@me`). Repozitáře nejsou pevný seznam, může přijít cokoli.
2. **Checkout na vyžádání** — repo se naklonuje do vlastní cache aplikace jako bare
   partial clone a přidá se detached `git worktree` na head commitu daného PR. Vlastních
   klonů na disku se aplikace nikdy nedotkne.
3. **Review** — nakonfigurované skilly se spustí jako paralelní headless session
   Claude Code v tom worktree, omezené na read-only nástroje. Spouští se **tlačítkem**;
   automatický režim se zapíná zvlášť pro každé repo (nová repa mají default manuální).
4. **Sběr nálezů** — z `ReportFindings` tool callů ve `stream-json` event streamu.
   Strukturovaná data, ne parsování textu.
5. **Zobrazení** — diff v plné šířce s nálezy jako bubliny na svém `file:line`, plus
   řaditelná tabulka pro nálezy, které ke konkrétnímu řádku nepatří (chybějící testy,
   architektonické poznámky).

Nálezy jsou klíčované head commitem PR. Když přijdou nové commity, předchozí nálezy se
označí jako zastaralé — nezobrazují se proti kódu, který už neexistuje.

## Klíčová rozhodnutí

| | |
|---|---|
| **Reviewery** | Běží nezávisle a paralelně. Texty nálezů se mezi nimi neslučují — nesouhlas dvou reviewerů je informace. Shoda na stejném `file:line` se označí odznakem `2×`. |
| **Závažnost** | Aplikace nevymýšlí vlastní škálu. Seskupuje podle `category` z výstupu revieweera a odvozuje jediný blokující boolean (`verdict == CONFIRMED` a `category` v blokující sadě). Z toho vypadne návrh verdiktu. |
| **Oprávnění** | Reviewer je read-only — bez `Write` a `Edit`. Bezpečnostní vlastnost i praktická: headless session neumí odpovědět na permission prompt. |
| **Token** | Aplikace na GitHub token nikdy nesahá. Autentizace je delegovaná na `gh`, který credential drží v keychainu. |
| **Konfigurace** | Dvě úrovně: globální default a override per repo (režim auto/manual, sada skillů, blokující kategorie). |

## Požadavky

- macOS 26, Xcode 26
- [`gh`](https://cli.github.com) — přihlášený (`gh auth login`)
- `claude` — Claude Code CLI
- `git`

Aplikace binárky hledá absolutní cestou, protože GUI aplikace spuštěná z Finderu nedědí
`PATH` z shellu. Nejdřív zkusí známá místa (`/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin`, `~/.local/bin`), a co v nich není, dohledá v `PATH` login shellu. Ten čte
`.zshenv`, `.zprofile` a `.zlogin`, ale **ne `.zshrc`** — kdo má nástroj mimo známá místa
a `PATH` doplněný jen v `.zshrc`, musí cestu přidat do `.zprofile`.

Když něco chybí, aplikace se nespustí do prázdna — ukáže blokující obrazovku se **všemi**
problémy naráz: u každého nástroje cestu, kde se našel, nebo k čemu je a čím se instaluje.
U `gh` navíc kontroluje přihlášení. Po instalaci stačí `Zkusit znovu`, restart není
potřeba.

## Build

Spustit aplikaci — jeden příkaz, buildne v Debug a otevře okno:

```bash
./bin/run.sh
```

Samotný build a testy:

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism test
```

`bin/run.sh` buildí do `build/` v repu (`-derivedDataPath`), aby byla cesta k `.app`
předvídatelná; složka je gitignorovaná. Před spuštěním ukončí předchozí instanci.

Aplikace běží **bez App Sandboxu** — spouští `git`, `gh` a `claude` a zapisuje do vlastní
cache. Podpis je ad-hoc (`CODE_SIGN_IDENTITY = "-"`), takže build nepotřebuje Apple účet
ani tým. Developer ID podpis a notarizace by byly potřeba až pro distribuci.

## Struktura

```
PRism.xcodeproj/          Xcode projekt (shared scheme je verzovaný)
App/                      zdrojáky aplikace — target PRism
  Models/                 doménové modely: PR, identifikátory, stav review
  Environment/            přístup ke stroji: hledání binárek, podprocesy, preflight
  GitHub/                 čtení PR přes gh CLI: gateway, typované chyby, tvar výstupu
  Policy/                 čisté funkce: slučování zdrojů, řazení
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno
  Views/                  SwiftUI obrazovky
Tests/                    unit testy — target PRismTests
  Models/                 testy modelů + pomocníci na Codable round-trip
  Environment/            testy Environment vrstvy + fakes
  GitHub/                 testy gateway a klasifikace chyb gh
  Policy/                 testy čistých funkcí
  Polling/                testy pollingu proti fake gateway a fake času
  Store/                  testy AppStore
  Fixtures/gh/            skutečné JSON výstupy gh z veřejných repozitářů
bin/run.sh                build + spuštění jedním příkazem
bin/copilot-review.sh     vyžádání Copilot review na PR
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
docs/superpowers/specs/   návrh a specifikace
CLAUDE.md                 pravidla pro práci v repu
README.md                 tento soubor
.gitignore                artefakty Xcode buildu, SPM, .DS_Store
```

`App/` a `Tests/` jsou v projektu napojené jako **buildable folders** — obsah se do
targetu bere z filesystému. Nový soubor stačí vytvořit, do `project.pbxproj` se nic
nezapisuje. `Info.plist` a entitlements proto leží v kořeni: cokoli uvnitř `App/`, co
není zdroják, by se zkopírovalo do `.app` jako resource.

Repo, Xcode projekt, target, produkt i to, co appka ukazuje v Docku, se jmenují stejně —
`PRism`. Swiftový modul taky (`PRODUCT_MODULE_NAME`), takže testy dělají
`@testable import PRism`.
