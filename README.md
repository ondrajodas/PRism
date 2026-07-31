# pr-review

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

> **Nikdy nic neposílá na GitHub.** Žádné komentáře, žádná review, žádné approve.
> Verdikt *approve / request changes* je návrh zobrazený v aplikaci. Je to tvrdá
> podmínka návrhu, ne zjednodušení první verze.

## Stav

**Scaffold hotový, funkcionalita se teprve staví.** V repu je Xcode projekt, který se
buildí, testuje a spustí do prázdného okna. Žádná z pěti fází (viz
[CLAUDE.md](CLAUDE.md)) zatím není hotová.

Postup se dá sledovat přes [releases](https://github.com/ondrajodas/pr-review/releases) —
po každém mergnutém PR vzniká tag a release s popisem, co se změnilo a kde projekt
aktuálně je.

- [Návrh (specifikace)](docs/superpowers/specs/2026-07-31-pr-review-design.md) — plný
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
`PATH` z shellu. Když některá chybí, ohlásí to při startu jasnou chybou.

## Build

Spustit aplikaci — jeden příkaz, buildne v Debug a otevře okno:

```bash
./bin/run.sh
```

Samotný build a testy:

```bash
xcodebuild -project pr-review.xcodeproj -scheme pr-review build
```

```bash
xcodebuild -project pr-review.xcodeproj -scheme pr-review test
```

`bin/run.sh` buildí do `build/` v repu (`-derivedDataPath`), aby byla cesta k `.app`
předvídatelná; složka je gitignorovaná. Před spuštěním ukončí předchozí instanci.

Aplikace běží **bez App Sandboxu** — spouští `git`, `gh` a `claude` a zapisuje do vlastní
cache. Podpis je ad-hoc (`CODE_SIGN_IDENTITY = "-"`), takže build nepotřebuje Apple účet
ani tým. Developer ID podpis a notarizace by byly potřeba až pro distribuci.

## Struktura

```
pr-review.xcodeproj/      Xcode projekt (shared scheme je verzovaný)
App/                      zdrojáky aplikace — target pr-review
Tests/                    unit testy — target pr-reviewTests
bin/run.sh                build + spuštění jedním příkazem
Info.plist                název aplikace, verze, minimální systém
pr-review.entitlements    vypnutý App Sandbox
docs/superpowers/specs/   návrh a specifikace
CLAUDE.md                 pravidla pro práci v repu
README.md                 tento soubor
.gitignore                artefakty Xcode buildu, SPM, .DS_Store
```

`App/` a `Tests/` jsou v projektu napojené jako **buildable folders** — obsah se do
targetu bere z filesystému. Nový soubor stačí vytvořit, do `project.pbxproj` se nic
nezapisuje. `Info.plist` a entitlements proto leží v kořeni: cokoli uvnitř `App/`, co
není zdroják, by se zkopírovalo do `.app` jako resource.

Projekt, target i produkt se jmenují `pr-review`; uživateli se aplikace hlásí jako
**GitHub PR Review** (`CFBundleName` a `CFBundleDisplayName` v `Info.plist`).
