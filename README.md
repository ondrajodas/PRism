# PRism

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

Hranol rozloží jeden paprsek na spektrum. Tahle aplikace dělá totéž s pull requestem —
pustí na něj několik nezávislých reviewerů a jejich nálezy schválně neslévá do jednoho
názoru.

> **Na GitHub vede jediná cesta a otevírá ji jen člověk.** Aplikace umí odeslat review,
> ale výhradně přes jeden modul, na výslovné potvrzení a proti commitu, který jsi opravdu
> viděl. Nic se neodesílá samo — ani návrh verdiktu, ani reviewer.
>
> **Zatím navíc jen do testovacího sandboxu** (viz [#107](https://github.com/ondrajodas/PRism/issues/107)):
> pravidlo je nové a než se pustí na PR kolegů, projde si provozem tam, kde omyl nikoho
> nestojí čas.

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

Detail PR má **záložky jako GitHub**: `Přehled` a `Změněné soubory`, podtržené, s odznakem
kolik je v přehledu k přečtení. Volba se pamatuje **u každého PR zvlášť** a otevírá se
`Přehled` — popis a diskuze se čtou dřív než kód, kterého se týkají.

**`Přehled`** nese to, co se neváže k žádnému řádku: popis PR od autora a pod ním konverzaci
chronologicky — review ostatních s odznakem (`schválil`, `vyžádal změny`), komentáře pod PR
a vlákna, jejichž řádek v aktuálním diffu není (typicky zastaralá po novém commitu). Ta se
kreslí **tou samou bublinou jako u kódu**, jen s cestou a řádkem nad ní, protože bez kódu
vedle není z čeho poznat, o co jde. Moje komentáře mají odznak `já`, text jde označit
a zkopírovat a konverzaci lze obnovit tlačítkem, aniž by se čekalo na tik pollingu.

**Texty se renderují jako Markdown** — nadpisy, seznamy včetně zaškrtávacích, bloky kódu,
citace, odkazy. Vlastní blokový parser bez závislosti (jako obarvení kódu): systémový umí
formátování uvnitř řádku dobře, ale bloky tiše spolkne. Zvládá i **HTML, které do komentářů
posílají boti** — `<!-- … -->` se nekreslí (jako na GitHubu), `<details>` je rozbalovátko
a odkazy zůstávají klikatelné. Tabulky zůstávají jako monospace řádky a kód v blocích se
neobarvuje: jazyk z fence je volný řetězec, takže mapovat ho na obarvovací pravidla znamená
hádat, a špatně obarvený cizí kód je horší než neobarvený.

**`Změněné soubory`** ukazují **diff v plné šířce**: soubory pod sebou s hlavičkou, která při scrollu
zůstává nahoře, souhrn `N souborů · +X −Y` a menu na skok mezi soubory. Přejmenování, nové,
smazané i binární soubory jsou označené; dlouhé řádky se zalamují, protože 120 znaků se do
plné šířky vejde.

**Klik na hlavičku souboru jeho diff sbalí a rozbalí**, jako na GitHubu — u PR přes deset
souborů je to hlavní způsob, jak se v něm pohybovat. Hlavička zůstává vidět i se `+N −M`
a s odznakem, kolik je v souboru nálezů (červeným, když je mezi nimi blokující). V horní
liště je `Sbalit vše` / `Rozbalit vše` a skok na soubor nebo na nález sbalený soubor sám
otevře.

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
shrnutí), Průběh a Moje review. Panel je jediné místo, kde jsou vidět nálezy **bez místa
v kódu** — chybějící testy nebo poznámky k architektuře; kvůli nim samotné bubliny
nestačí. Je vidět v **obou** záložkách, protože nálezy, průběh i rozdělané review patří
k celému PR, ne k diffu. Klik na řádek odscrolluje diff (a přepne na něj, když jsi
v `Přehledu`) tak, aby nad nálezem zůstalo pár řádků kontextu, a bublinu na chvíli
zvýrazní. Výška panelu se táhne za horní hranu a pamatuje se.

**Většinu šířky tabulky dostane text nálezu**, protože to je to, co se čte; kategorie
a reviewer si berou jen tolik, kolik potřebují. Co se přesto nevejde, řekne **nápověda po
najetí myší** — má ji každý sloupec, protože každým se dá přetáhnout až na jeho minimum.
`Místo` se ořezává **zepředu**, ať zůstane vidět jméno souboru a číslo řádku; text nálezu
odzadu. U nálezu, který ke konkrétnímu místu v kódu nepatří, vysvětluje nápověda pomlčku
ve sloupci.

V liště panelu je **koš**, kterým se uložené nálezy zahodí — hodí se, když se změnila sada
skillů a v záznamu leží nálezy od revieweera, který už neběží. Maže se jen viditelný commit,
historie zůstává, a na repu v automatickém režimu se review vzápětí pustí samo.

**Zavřít aplikaci během review se musí potvrdit.** Ukončení session zabije a nálezy, které
už reviewer nahlásil, se ztratí — z řádku pak vyjde `neběželo`, tedy totéž jako u PR, který
nikdo nekontroloval. Dialog nabídne `Zpět` (výchozí) a `Ukončit`; co doběhlo, zůstává
uložené. Pád aplikace ani zabití zvenčí takhle odchytit nejde, proto to `bin/run.sh` při
rebuildu neobchází a aplikaci ukončuje tou samou cestou jako ⌘Q.

Nad diffem jsou **chipy reviewerů**: u každého je vidět, co udělal (`3 nálezy`, `čisté`,
`běží`, `selhalo`, `nejisté`) a kliknutím se jeho nálezy schovají z bublin i z tabulky.
Vpravo je **návrh verdiktu** — je to doporučení, ne akce. Sám nic neodešle; odeslat review
umí jedině člověk, a jedinou cestou (viz úvod).
Filtr návrhem nehýbe, aby se schováním revieweera nedal „vyrobit“ approve.

V tabu **Průběh** běží časová osa toho, co reviewer právě dělá — který soubor čte, co
hledá, jaký příkaz spustil. Skládá se nativně z eventů, ne přeposíláním textu, takže
aplikace nepotřebuje vestavěný terminál; když je potřeba se do session vrátit, zkopíruje
se `claude --resume <id>` jedním tlačítkem. Osa zůstane i po doběhnutí běhu.

Chování se řídí souborem `config.json` v `~/Library/Application Support/PRism/`: zdroje
PR, sada skillů, blokující kategorie, výchozí režim review, interval pollingu, kolik
session smí běžet naráz, rozpočet cache a model. Repozitář si může přebít režim
(`manual`/`automatic`), jazyk nálezů, skilly i kategorie.

**Nálezy chodí česky**, protože okno je české — u firemního repa s mezinárodním týmem se
dá přepnout na angličtinu, globálně i jen pro to jedno repo. Překládají se **až po
doběhnutí review**, jednou krátkou session na celý běh; reviewer sám dostane pořád tentýž
anglický prompt. Je to schválně: instrukce v promptu by kvalitu review ovlivnit mohla,
překlad po něm nemůže. Originál zůstává uložený vedle překladu a když se překlad nepovede,
ukáže se prostě anglicky.

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

**Rozsah v1 podle specifikace je hotový** — všech pět fází (viz [CLAUDE.md](CLAUDE.md)).
Co přijde po něm, je v milnících M6 až M8.

Z nich už je hotové čtení konverzace: **vlákna od kolegů visí jako bubliny u svých řádků**,
vedle nálezů. Vyřešená jsou sbalená na jeden pruh s odznakem `vyřešeno` (nemažou se — je to
historie), moje komentáře mají odznak `já` a z každého se dá odskočit na GitHub. Konverzace
se načte při výběru PR a drží se, dokud se nezmění `updatedAt`; pollingem se netahá, aby
z jednoho tiku nebylo N podprocesů.

**Rozdělané review se skládá v okně** a přežije restart: tělo, verdikt a řádkové komentáře
leží v `drafts/` vedle uložených nálezů, mimo dosah úklidu cache. Nový commit ho nesmaže,
jen zablokuje odeslání — vlastní próza nezastarává tak rychle jako strojové nálezy.

Hlavní smyčka je **nález → komentář mými slovy**: v bublině nálezu je `Převzít do review`,
které z jeho textu udělá můj komentář u toho řádku — a ten se dá přepsat. Převzatý nález
nese odznak `v mém review`, takže se nedá vzít dvakrát; rozeznává se podle revieweera, aby
u shody `2×` nesvítil odznak i u toho druhého. Vlastní poznámku přidá tlačítko, které se
objeví po najetí na řádek diffu.

**Co GitHub jako řádkový komentář nepřijme, jde do těla review jako odkaz na kód** —
permalink na commit, který se vyrenderuje jako obarvený úryvek. Týká se to nálezů mimo diff
a řádků, které v diffu nejsou (rozbalený kontext). Tlačítko to říká dopředu, včetně důvodu,
a po kliknutí se panel přepne na tab, kam text spadl.

V tabu **Moje review** je tělo, seznam všech řádkových komentářů a **výběr verdiktu bez
předvyplnění** — návrh z nálezů se do něj nepřepisuje, aby se odhad aplikace nedal splést
s mým rozhodnutím. Seznam komentářů je jediné úplné místo: komentář na řádku, který
z diffu zmizel, se nemá kde ukázat jako bublina, ale tady je i s možností ho vyjmout.
Prázdný komentář se neuloží a odeslání zablokuje, protože GitHub takový payload odmítne —
a odmítne s ním celé review.

Že je něco rozděláno, je vidět **v řádku seznamu i v detailu** (ikona pera). Draft psaný
proti staršímu commitu má v tabu **banner** a odeslat se nedá; text zůstává.

### Odeslání review

**Dvě kliknutí, dvě různá tlačítka.** `Odeslat review…` v tabu `Moje review` nic neodesílá —
otevře potvrzení, ve kterém je vidět **celý payload**: verdikt, tělo tak, jak je napsané,
a každý řádkový komentář i s tím, ke kterému řádku a ke které straně diffu patří. Teprve
tlačítko tam zavolá GitHub. Zavřít se dá kdykoli a draft tím zůstane netknutý.

Ochrana stojí právě na tom výpisu, ne na obřadu: **žádné opisování názvu repa** a **žádný
druhý dialog nad sheetem**. Obojí se za týden odklikává poslepu a oslabí to i to první
potvrzení. Co zůstává, je pojmenování akce — tlačítko se jmenuje
`Odeslat APPROVE pro owner/repo#123` — a to, že **není výchozí**: Enterem se nic neodešle.

Návrh verdiktu z nálezů stojí v potvrzení **vedle** toho zvoleného. Nepředvyplňuje nic, ale
když se rozchází (schvaluju PR, u kterého reviewer hlásí blokující nález), řekne to nahlas.

Proč odeslat nejde, je vidět **předem** — vedle zakázaného tlačítka, ne až po pokusu:
chybějící verdikt, prázdný řádkový komentář, draft proti staršímu commitu, nebo repo mimo
sandbox. Zatím se totiž odesílá **jen do sandboxu** (`ondrajodas/prism-review-sandbox`);
je to vědomé omezení první verze, ne technická překážka.

Po úspěchu se potvrzení **zavře samo**, draft zmizí (i z disku) a konverzace se načte znovu,
takže je moje review hned vidět v `Přehledu`. Otevřené zůstane jen tehdy, když GitHub vrátí
stav, kterému aplikace nerozumí — tam je jediná zpráva ta, že se to má zkontrolovat ručně.
**Selhání draft nemaže**: chyba je vypsaná i s tím, co se s ní dá dělat, a dá se zkusit znovu.

Vlákna, jejichž řádek v aktuálním diffu **není** (typicky zastaralá po novém commitu), se
do kódu nekotví — jejich čísla platila pro starý head, takže by bublina sedla na cizí řádky.
Domov mají v záložce `Přehled` spolu s review ostatních a komentáři pod PR.

Postup se dá sledovat přes [releases](https://github.com/ondrajodas/PRism/releases) —
po každém mergnutém PR vzniká tag a release s popisem, co se změnilo a kde projekt
aktuálně je.

- [Návrh (specifikace)](docs/superpowers/specs/2026-07-31-prism-design.md) — plný
  návrh včetně záznamu rozhodnutí a zamítnutých alternativ
- [`docs/claude-cli.md`](docs/claude-cli.md) — ověřené chování `claude` CLI
- [`docs/github-review-api.md`](docs/github-review-api.md) — ověřené chování zápisového
  review API GitHubu; podklad pro odesílání review (M6)
- [CLAUDE.md](CLAUDE.md) — pravidla pro práci v tomto repu

## Jak to funguje

1. **Polling GitHubu** přes `gh` — hledají se PR, u kterých je po mně požadované review
   (`review-requested:@me`). Repozitáře nejsou pevný seznam, může přijít cokoli.
2. **Checkout na vyžádání** — repo se naklonuje do vlastní cache aplikace jako bare
   partial clone a přidá se detached `git worktree` na head commitu daného PR.
   **Vlastních** klonů na disku se aplikace nikdy nedotkne.
3. **Review** — nakonfigurované skilly se spustí jako paralelní headless session
   Claude Code v tom worktree, omezené na read-only nástroje. Prompt si o skill říká
   nástrojem `Skill` výslovně, takže v konfiguraci jsou jeho id (`plugin:skill`), ne
   slash commandy. Které to jsou, může záviset
   na programovacím jazyce repa; ten se odhaduje z `git ls-files`. Spouští se **tlačítkem**,
   nebo samo, když je repo v automatickém režimu — ten se zapíná globálně i zvlášť pro každé
   repo a výchozí je manuální, aby neznámé repo nespálilo panel session bez dozoru.
   **Automat utratí session, teprve když se změnil head commit**, takže komentář na PR ho
   nespustí, a hlídá ho denní limit.
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
| **Jazyk nálezů** | Volba v nastavení, ne natvrdo. Řeší se **překladem po doběhnutí**, ne instrukcí v promptu: psát rovnou česky měřitelně ubírá nálezy. Reviewer píše v jazyce, ve kterém je nejsilnější; jazyk je věc zobrazení. |
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
cache.

### Podpis

Výchozí podpis je ad-hoc (`CODE_SIGN_IDENTITY = -` v `Signing.xcconfig`), takže build
nepotřebuje Apple účet ani tým a projde na jakémkoli stroji bez přípravy. Developer ID
podpis a notarizace by byly potřeba až pro distribuci.

Ad-hoc podpis ale **nemá stálou identitu**: každý build dá jiný otisk, takže macOS považuje
aplikaci pokaždé za jinou a povolení udělená přes TCC se na novou verzi nevztahují. Prakticky
to znamená dotaz na přístup do **Stažených souborů** po každém rebuildu. Aplikace tam
nesahá — vyvolává ho `claude`, který si při startu bere prostředí z uživatelova shellu, a ten
načte `~/.zshrc` sourcující Google Cloud SDK rozbalený v `~/Downloads`. Dotaz se proto objeví
až při spuštění review, ne po startu aplikace.

Stálou identitu dá vlastní certifikát. Vyrobí ho jednorázově:

```bash
./bin/setup-signing.sh
```

Skript vytvoří self-signed certifikát typu *Code Signing* s názvem `PRism Local` v login
keychainu a napíše `Signing.local.xcconfig` s jeho jménem; odtud si ho přes `#include?`
vezme `Signing.xcconfig`, takže se podepisuje stejně ve `bin/run.sh`, v `xcodebuild` i v
Xcode. Ten soubor se **necommituje** — jméno certifikátu je vlastnost stroje, ne repa, a
bez něj se spadne zpátky na ad-hoc. Systém si přitom může říct o přihlašovací heslo —
jednou při zápisu do nastavení důvěry (bez něj se self-signed certifikát mezi platné
identity nezapočítá) a při prvním buildu ještě o přístup ke klíči, kde stačí kliknout na
*Vždy povolit*. Ten druhý dotaz odbourá předem heslo zadané na řádku, který skript nabízí;
přeskočit ho jde Enterem.

Že je podpis stálý, se ověří takhle:

```bash
codesign -dv --verbose=4 build/Build/Products/Debug/PRism.app
```

Ad-hoc build hlásí `Signature=adhoc`, podepsaný `Authority=PRism Local`. Na ad-hoc podpis
upozorní i `bin/run.sh`, protože jinak je příčina vracejících se dotazů neviditelná.
Certifikát se odstraní přes `security delete-identity -c "PRism Local"`.

## Struktura

```
PRism.xcodeproj/          Xcode projekt (shared scheme je verzovaný)
App/                      zdrojáky aplikace — target PRism
  Models/                 doménové modely: PR, identifikátory, stav review
  Environment/            přístup ke stroji: hledání binárek, podprocesy, preflight
  GitHub/                 čtení PR a konverzace přes gh CLI: gateway, typované chyby, tvar výstupu
  Checkout/               vlastní cache repozitářů: klony, worktrees, úklid
  Config/                 config.json: globální default, override per repo, čtení a zápis
  Diff/                   parsování unified diffu na soubory, hunky a řádky
  Markdown/               vykreslení Markdownu z GitHubu: bloky, inline HTML od botů
  Policy/                 čisté funkce: slučování zdrojů, řazení, stav řádku, odhad jazyka
  Publish/                jediná cesta ven: odeslání review na GitHub, brána na sandbox, model potvrzení
  Review/                 spuštění session claude a překlad stream-json na nálezy
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno; ReviewStore a ReviewDraftStore — nálezy a rozdělaná review na disku
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
  Markdown/               testy parseru Markdownu (invariant: nic se neztratí) a HTML od botů
  GitHub/                 testy gateway a klasifikace chyb gh
  Policy/                 testy čistých funkcí
  Review/                 testy parseru a runneru proti skutečným streamům
  Polling/                testy pollingu proti fake gateway a fake času
  Publish/                testy odesílání — hlavně že se při neshodě neodešle nic
  Store/                  testy AppStore a persistence nálezů
  Views/                  testy řádků tabulky a modelu okna nastavení
  Syntax/                 testy detekce jazyka a obarvení kódu
  Support/                testy sdílených drobností
  Fixtures/gh/            skutečné výstupy gh z veřejných repozitářů (JSON i diffy)
  Fixtures/stream-json/   skutečné stream-json výstupy claude z reálných běhů
bin/run.sh                build + spuštění jedním příkazem
bin/copilot-review.sh     vyžádání Copilot review na PR
bin/setup-signing.sh      jednorázová příprava stálého podpisu (self-signed certifikát)
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
Signing.xcconfig          podpis: ad-hoc default + volitelný Signing.local.xcconfig
docs/claude-cli.md        ověřené chování claude CLI (flagy, tvar eventů)
docs/github-review-api.md ověřené chování zápisového review API GitHubu (spike k M6)
docs/superpowers/specs/   návrh a specifikace
CLAUDE.md                 pravidla pro práci v repu
README.md                 tento soubor
.gitignore                artefakty Xcode buildu, SPM, .DS_Store, Signing.local.xcconfig
```

`App/` a `Tests/` jsou v projektu napojené jako **buildable folders** — obsah se do
targetu bere z filesystému. Nový soubor stačí vytvořit, do `project.pbxproj` se nic
nezapisuje. `Info.plist` a entitlements proto leží v kořeni: cokoli uvnitř `App/`, co
není zdroják, by se zkopírovalo do `.app` jako resource.

Repo, Xcode projekt, target, produkt i to, co appka ukazuje v Docku, se jmenují stejně —
`PRism`. Swiftový modul taky (`PRODUCT_MODULE_NAME`), takže testy dělají
`@testable import PRism`.
