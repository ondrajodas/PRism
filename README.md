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

**Aplikace dělá to, kvůli čemu vznikla: pustí review na moje skutečné PR a ukáže nálezy.**

Po startu si ověří, že má `gh`, `git` i `claude` a že je `gh` přihlášený — jinak řekne, co
chybí a čím se to spraví. Pak se otevře seznam pull requestů napříč repozitáři, který se
sám obnovuje: každý řádek nese repo, číslo, titulek, autora a čas poslední změny. Při
výpadku sítě zůstanou poslední známá data a nad seznamem se objeví pruh, že nejsou
aktuální; při rate limitu pruh říká, kdy to zkusí znovu.

U vybraného PR je tlačítko **Spustit review**. Za ním se stane tohle: dotáhne se head
commit, připraví se odpojený pracovní strom a v něm se spustí headless session Claude Code
omezená na čtení. Řádek mezitím ukazuje `ve frontě · clone` → `běží 0/1` → `čisté` nebo
`N nálezů`; běh jde kdykoli zrušit. Nálezy se uloží na disk, takže přežijí restart, a
v detailu je dole lišta s **návrhem verdiktu** (`approve` / `request changes` / *není
z čeho soudit*) a rozbaleným seznamem nálezů po kategoriích, s odznakem u těch blokujících.
Kliknutím na nález diff odskočí na jeho `file:line`.

Detail PR ukazuje **diff v plné šířce**: soubory pod sebou s hlavičkou, která při scrollu
zůstává nahoře, souhrn `N souborů · +X −Y` a menu na skok mezi soubory. Přejmenování, nové,
smazané i binární soubory jsou označené; dlouhé řádky se zalamují, protože 120 znaků se do
plné šířky vejde.

V mezerách mezi hunky jsou **šipky na rozbalení kontextu** — dotáhnou kód, který v diffu
není, po dvaceti řádcích nebo celý úsek naráz. Obsah souboru se čte z GitHubu až na
kliknutí; když se mezera rozbalí celá, hunky se slijí a hlavička mezi nimi zmizí.
`Zobrazit jen diff` sbalí všechno zpátky. **Kód kolem nálezu, jehož řádek v diffu není,
se dotáhne sám** — nález bez svého kódu se nedá posoudit. Nahoře v liště je **strom
souborů** pro skok kamkoli v diffu.

Kód je **obarvený podle jazyka** — vlastní pravidla, žádná externí závislost, paleta
Darcula v tmavém režimu a IntelliJ Light ve světlém. Barví se řádek po řádku bez paměti,
protože diff je útržek: víceřádkový komentář se obarví jen tam, kde začíná. Soubor
v neznámém jazyce zůstane jednobarevný.

**Nálezy visí jako bubliny u řádků, kterých se týkají** — pill kategorie, verdict, jméno
revieweru a rozbalitelný scénář selhání; blokující nález má červený pruh. Shodu dvou
reviewerů na jednom místě označí `2×`, ale jejich texty se neslučují. Nález na řádek, který
v diffu není, se neztratí: visí u hlavičky souboru a nabídne ten řádek dotáhnout. Bubliny
jdou vypnout přepínačem nad diffem.

Pod diffem je **panel s taby**: řaditelná tabulka nálezů (kategorie, reviewer, místo,
shrnutí) a zatím prázdný Průběh. Panel je jediné místo, kde jsou vidět nálezy **bez místa
v kódu** — chybějící testy nebo poznámky k architektuře; kvůli nim samotné bubliny
nestačí. Klik na řádek odscrolluje diff a bublinu na chvíli zvýrazní. Výška panelu se
táhne za horní hranu a pamatuje se.

Nad diffem jsou **chipy reviewerů**: u každého je vidět, co udělal (`3 nálezy`, `čisté`,
`běží`, `selhalo`, `nejisté`) a kliknutím se jeho nálezy schovají z bublin i z tabulky.
Vpravo je **návrh verdiktu** — je to doporučení, ne akce; aplikace na GitHub nic neposílá.
Filtr návrhem nehýbe, aby se schováním revieweera nedal „vyrobit“ approve.

V tabu **Průběh** běží časová osa toho, co reviewer právě dělá — který soubor čte, co
hledá, jaký příkaz spustil. Skládá se nativně z eventů, ne přeposíláním textu, takže
aplikace nepotřebuje vestavěný terminál; když je potřeba se do session vrátit, zkopíruje
se `claude --resume <id>` jedním tlačítkem. Osa zůstane i po doběhnutí běhu.

Chování se řídí souborem `config.json` v `~/Library/Application Support/PRism/`: zdroje
PR, sada skillů, blokující kategorie, výchozí režim review, interval pollingu, kolik
session smí běžet naráz, rozpočet cache a model. Repozitář si může přebít režim
(`manual`/`automatic`), skilly i kategorie.

Sada skillů se dá navázat na **programovací jazyk**: při review se z obsahu repa pozná,
čím je psané (`composer.json` a `.php` → PHP, `go.mod` → Go), a odpovídající sada se
použije. Smysl je nepouštět PHP skilly na Go repu — každý skill je jedna session.
Repu se sada **zapíše, jen když se od globální liší** — jinak by v konfiguraci vznikl
override, o který nikdo nežádal, a pozdější změna globální sady by takové repo minula.
Odhad se opakuje při každém review, dokud si repo neřekne o vlastní sadu; ručně nastavená
sada má vždycky přednost a detekci navždycky umlčí. Mapa jazyk → skilly je ve výchozím
stavu prázdná, takže dokud se nevyplní, detekce na nic nesahá. Soubor se zakládá sám s dosavadními výchozími
hodnotami, načítá se při startu i při návratu do aplikace, a když je rozbitý, běží se na
defaultech a je to vidět.

Editovat ho jde ručně, nebo **oknem nastavení** (⌘, nebo ozubené kolo v toolbaru). Okno
má dvě záložky: globální hodnoty a per repo, kde se u každého repa z posledního seznamu PR
nastavuje režim a případný override skillů a kategorií. Ukládá se samo do téhož souboru,
pár set milisekund po posledním úhozu, a změna se projeví bez restartu. Rozbitý soubor
editor **nepřepíše** — místo formuláře ukáže chybu a nabídne soubor otevřít. Dokud je
nastavení vepředu, hlavní okno se lehce rozostří.

Pod tím vším je vlastní cache repozitářů: bare partial clone do
`~/Library/Application Support/PRism/`, přihlášení delegované na `gh`, odpojený
`git worktree` pro každé review a úklid, který po každém pollingu zahodí repa bez
otevřeného PR a při překročení rozpočtu (10 GB) i ta nejdéle nepoužitá. Platí u ní, že
**vlastních klonů na disku se aplikace nikdy nedotkne** — pracuje výhradně ve své cache.
Uložené nálezy jsou klíčované head commitem: nové commity je označí jako zastaralé
a záznamy PR, který ze seznamu zmizel, se po třiceti dnech uklidí.

Z pěti fází (viz [CLAUDE.md](CLAUDE.md)) jsou hotové první čtyři; z páté zbývá automatický
režim (#25) a jazyk nálezů (#52).

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
   partial clone a přidá se detached `git worktree` na head commitu daného PR.
   **Vlastních** klonů na disku se aplikace nikdy nedotkne.
3. **Review** — nakonfigurované skilly se spustí jako paralelní headless session
   Claude Code v tom worktree, omezené na read-only nástroje. Které to jsou, může záviset
   na programovacím jazyce repa; ten se odhaduje z `git ls-files`. Spouští se **tlačítkem**;
   automatický režim se dá zapnout globálně i zvlášť pro každé repo (výchozí je manuální,
   aby neznámé repo nespálilo panel session bez dozoru).
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
| **Závažnost** | Aplikace nevymýšlí vlastní škálu. Seskupuje podle `category` z výstupu reviewera a odvozuje jediný blokující boolean (`verdict == CONFIRMED` a `category` v blokující sadě). Z toho vypadne návrh verdiktu. |
| **Oprávnění** | Reviewer je read-only: `Write` ani `Edit` nemá povolené a `git push` s `gh` jsou výslovně zakázané. Ověřeno spuštěním, včetně toho, že zákaz platí i na `git push` s vypsanou URL — bez něj by session uměla pushnout do mého repozitáře, protože `origin` v cache míří na skutečné repo. |
| **Token** | Aplikace na GitHub token nikdy nesahá. Autentizace je delegovaná na `gh`, který credential drží v keychainu. |
| **Konfigurace** | Tři úrovně: globální default, sada podle programovacího jazyka repa a override per repo (režim auto/manual, sada skillů, blokující kategorie). Co si repo neřekne, bere globálně — proto je override `nil`, ne prázdná hodnota. Edituje se ručně v `config.json` i oknem nastavení; obojí píše do téhož souboru. |

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
  Checkout/               vlastní cache repozitářů: klony, worktrees, úklid
  Config/                 config.json: globální default, override per repo, čtení a zápis
  Diff/                   parsování unified diffu na soubory, hunky a řádky
  Policy/                 čisté funkce: slučování zdrojů, řazení, stav řádku, odhad jazyka
  Review/                 spuštění session claude a překlad stream-json na nálezy
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno; ReviewStore — nálezy na disku
  Syntax/                 obarvení kódu: jazyky, tokenizace, paleta
  Support/                sdílené drobnosti bez příslušnosti k modulu
  Views/                  SwiftUI obrazovky
    Settings/             okno nastavení (⌘,) — globální hodnoty a nastavení per repo
Tests/                    unit testy — target PRismTests
  Models/                 testy modelů + pomocníci na Codable round-trip
  Environment/            testy Environment vrstvy + fakes
  Checkout/               testy klonování — proti fake runneru i skutečnému gitu
  Config/                 testy čtení, zápisu a slučování konfigurace
  Diff/                   testy parseru diffu proti skutečným výstupům gh pr diff
  GitHub/                 testy gateway a klasifikace chyb gh
  Policy/                 testy čistých funkcí
  Review/                 testy parseru a runneru proti skutečným streamům
  Polling/                testy pollingu proti fake gateway a fake času
  Store/                  testy AppStore a persistence nálezů
  Views/                  testy řádků tabulky a modelu okna nastavení
  Syntax/                 testy detekce jazyka a obarvení kódu
  Support/                testy sdílených drobností
  Fixtures/gh/            skutečné výstupy gh z veřejných repozitářů (JSON i diffy)
  Fixtures/stream-json/   skutečné stream-json výstupy claude z reálných běhů
bin/run.sh                build + spuštění jedním příkazem
bin/copilot-review.sh     vyžádání Copilot review na PR
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
docs/claude-cli.md        ověřené chování claude CLI (flagy, tvar eventů)
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
