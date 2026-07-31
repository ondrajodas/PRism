# CLAUDE.md

Pravidla pro práci Claude Code v tomto repu.

## Údržba dokumentace — platí vždy

**Každá změna, kterou tady uděláme, se musí promítnout do `README.md` a `CLAUDE.md`.**
Není to úklid na konec, dělá se to **ve stejném commitu** jako samotná změna. Cílem je,
aby se aplikace dala pochopit z těchto dvou souborů bez čtení kódu — a aby další session
Claude Code měla po přečtení `CLAUDE.md` dost kontextu na to, aby mohla hned pracovat.

Co kam patří:

| Soubor | Obsah | Kdy aktualizovat |
|---|---|---|
| `README.md` | Co aplikace je, jak funguje, jak se buildí a spouští, požadavky, struktura repa | Změna chování, rozsahu, požadavků, build postupu nebo struktury |
| `CLAUDE.md` | Jak se v repu pracuje, aktuální architektura, konvence, tvrdé podmínky | Změna architektury, hranic modulů, konvencí, příkazů nebo pravidel |
| `docs/superpowers/specs/` | Proč jsou rozhodnutí taková, jaká jsou — včetně zamítnutých alternativ | Změna návrhového rozhodnutí; zapsat i **proč** se změnilo, staré nechat v záznamu rozhodnutí |

Když se změna nikam z toho nevejde, je to signál, že jsem si neujasnil, co vlastně měním
— vyřešit to, ne to přeskočit.

Konkrétně: přidání modulu → `CLAUDE.md` (architektura) + `README.md` (struktura, pokud se
mění). Změna konfigurace → `README.md` (klíčová rozhodnutí) + specifikace. Nový build
příkaz → `README.md` + sekce Příkazy níž. Zahození návrhového rozhodnutí → specifikace,
včetně důvodu.

## Jazyk

- **Dokumentace, specifikace, komentáře a prózu piš česky.** Včetně tohoto souboru,
  README a všeho v `docs/`.
- **Identifikátory v kódu anglicky** — názvy typů, funkcí, polí, souborů, flagů:
  `blockingCategories`, `headSha`, `ReviewRunner`. Kód se česky nepíše.
- **Issues celé česky** — titulek i popis.
- **Commit messages, názvy branchí, titulky a popisy PR anglicky.** Formát
  [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- **Release notes česky** (viz Pracovní postup).
- **Žádné AI atribuce** v commitech ani v PR — bez podpisů a bez „generated with".

## Pracovní postup (git)

- **Všechno jde přes PR.** Žádné přímé pushe do `main` — každá změna (kód i dokumentace)
  má vlastní branch a PR, i když je malá. PR odkazuje na issue, které řeší.
- **Branch:** anglicky, krátce, s číslem issue — např. `issue-4-github-gateway`.
- **Po vytvoření PR na něj pusť Copilota a počkej na výsledek.**

  ```bash
  ./bin/copilot-review.sh <číslo PR>
  ```

  `gh pr edit --add-reviewer Copilot` **nepoužívej** — na tomhle repu padá na deprecated
  Projects classic a reviewer se nepřidá; REST `/requested_reviewers` vrátí 200 a bota
  tiše zahodí. Skript proto jde přes GraphQL mutaci `requestReviews` s `botIds`.

  Když Copilot nálezy má, projdi je a řekni, co je reálné a co šum — teprve pak se
  rozhoduje dál. Když nemá žádné, **stejně čekej na můj pokyn.**
- **Merge PR a zavření issue jen na můj pokyn.** Nikdy to nedělej z vlastního
  rozhodnutí, že je práce hotová — ani když je zeleno a Copilot mlčí.
- **Po mergnutí PR se vydá nový tag a GitHub release.** Release notes píšeme česky a
  popisují progress: co se změnilo, jaký je aktuální stav proti milníkům a co je další
  krok. Release je deník projektu — kdo si přečte poslední release, ví, kde jsme.
- **Verzování:** `v0.<milník>.<pořadí PR v milníku>` — např. třetí mergnutý PR
  v milníku 1 je `v0.1.3`. Verze `v1.0.0` = dokončený rozsah v1 podle specifikace.
- Binárky se do release nepřikládají — buildujeme lokálně. Release slouží k záznamu
  postupu, ne k distribuci.

## Co aplikace je

Nativní macOS aplikace (SwiftUI), která hlídá GitHub PR přiřazené mně k review, spouští
na ně review skilly Claude Code jako headless session a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Když se objeví
potřeba „chytřejšího" review, patří to do skillu, ne do aplikace.

Plný návrh: [`docs/superpowers/specs/2026-07-31-prism-design.md`](docs/superpowers/specs/2026-07-31-prism-design.md)

## Tvrdé podmínky

Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav se a zeptej se.

1. **Nikdy nic neposílat na GitHub.** Žádné komentáře, review, approve, labely. Verdikt
   je návrh zobrazený v aplikaci. Aplikace je vůči GitHubu **jen pro čtení**.
2. **Reviewer je read-only.** `--allowedTools` bez `Write`, `Edit` a bez obecného `Bash`.
   Reviewer strukturálně nemůže změnit kód ani nic odeslat.
3. **Nikdy nesahat na uživatelovy klony.** Aplikace pracuje výhradně ve své cache
   (`~/Library/Application Support/PRism/`). Mohou být rozdělané, na jiné branchi,
   mít vlastní worktrees.
4. **Aplikace nikdy nedrží GitHub token.** Autentizace je delegovaná na `gh`.
5. **Nálezy jsou klíčované `headSha`.** Nové commity nálezy zneplatní (stav
   „zastaralé"), nikdy se nesmí tiše zobrazovat proti kódu, který už neexistuje.

## Architektura

Sedm modulů. Tři, které sahají do vnějšího světa, jsou za protokolem, aby byly v testech
nahraditelné fake implementací.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a diff | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings` | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Blokující příznak, návrh verdiktu, detekce shody `2×`, řazení | — |
| `Config` | Globální default + override per repo | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu | — |

Nad tím SwiftUI views: `PRList`, `DiffView`, `FindingsPanel`.

**Kam co psát:** rozhodovací logika patří do `Policy` jako čistá funkce — tam se testuje
bez mockování. Když se přistihneš, že píšeš `if` nad nálezy někde ve view nebo v runneru,
patří to do `Policy`.

## Konvence

- **Krátké, jednoúčelové metody.** Čitelnost před chytrostí.
- **Nepoužívat `final`** u typů, které se v testech nahrazují.
- **Protokol + fake, ne mockovací framework**, u tří modulů se vnějším světem.
- **Nové soubory drž malé a soustředěné.** Když soubor roste, obvykle dělá víc věcí.
- **Do `project.pbxproj` nesahej.** `App/` a `Tests/` jsou buildable folders
  (`PBXFileSystemSynchronizedRootGroup`) — soubory i podsložky se do targetu berou
  z filesystému. Nový zdroják = jen ho vytvořit. Editovat pbxproj je potřeba jen při
  změně targetů nebo build settings.
- **Do `App/` patří jen zdrojáky.** Buildable folder zkopíruje všechno, co neumí
  zkompilovat, do `.app` jako resource — `Info.plist` uvnitř `App/` skončil v bundlu
  dvakrát, podruhé s nerozexpandovanými `$(...)`. Konfigurace bundle (`Info.plist`,
  `PRism.entitlements`) proto leží v kořeni repa.
- **Název aplikace je jinde než název projektu.** Target, produkt i repo jsou
  `PRism`; uživateli se aplikace hlásí jako **GitHub PR Review**. `CFBundleName`
  nejde nastavit přes `INFOPLIST_KEY_*` — Xcode ho generuje z `PRODUCT_NAME` — proto má
  projekt vlastní `Info.plist` místo `GENERATE_INFOPLIST_FILE`. Swiftový modul drží
  `PRODUCT_MODULE_NAME = PRism`, takže testy importují `PRism`.
- **Moduly jsou složky, ne targety.** Všechen kód žije v jednom app targetu; `Policy`
  a spol. budou podsložky `App/`. Framework by si vynutil `public` u všeho, co používá
  UI — daň, kterou osobní aplikace nepotřebuje. Vyčlenit se dá později.
- Chybové stavy jsou v návrhu vyjmenované (viz specifikace, sekce *Chování při chybách*)
  — každý z nich má mít v UI vlastní rozlišitelný stav. `čisté` (žádné nálezy) a
  `failed` (session spadla) se nesmí slít do jednoho.

## Testování

- **`Policy`** — vyčerpávající unit testy, nic se nemockuje.
- **Parsování streamu** — klíčový spoj. Nahrát skutečný `stream-json` výstup z reálných
  běhů jako fixtures a testovat parser proti nim: init eventy, `ReportFindings` cally,
  chybný vstup, zkrácený stream.
- **`Config`** — merge globální + per-repo, defaulty pro neznámé repo.
- **`GitHubGateway` / `RepoCheckout` / `ReviewRunner`** — fake v testech na úrovni
  aplikace; malý počet integračních testů proti skutečným binárkám a scratch repu.

## Příkazy

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism test
```

```bash
./bin/run.sh    # build v Debug + otevření aplikace
```

`xcodebuild` na tomhle stroji plive na začátku výstupu chyby o `CoreSimulator` — jsou
neškodné, týkají se iOS simulátorů, ne macOS buildu. Rozhoduje `** BUILD SUCCEEDED **`,
resp. `** TEST SUCCEEDED **` na konci.

## Prostředí

- macOS 26, Xcode 26, Swift 6.3
- Vyžaduje na stroji `gh` (přihlášený), `claude` a `git`
- **App Sandbox vypnutý** — aplikace spouští podprocesy a zapisuje do vlastní cache
- **Binárky hledej absolutní cestou.** GUI aplikace spuštěná z Finderu nedědí `PATH` ze
  shellu, takže `gh` se podle jména nenajde. Řeší se při startu s jasnou chybou.

## Stav

Scaffold hotový (issue #1) — projekt se buildí, `xcodebuild test` běží, `./bin/run.sh`
otevře prázdné okno. Žádná fáze zatím není rozpracovaná.

Plánované fáze:

1. Seznam PR z `gh` + polling
2. Checkout cache + worktree
3. `ReviewRunner` + parsování streamu
4. UI diffu s bublinami
5. Konfigurace a auto režim

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
