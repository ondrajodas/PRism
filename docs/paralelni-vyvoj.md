# Paralelní vývoj

Jak se vyřizuje **seznam** issues. Prostředí na to dalo #228 (sloty), tohle je postup: co se
posoudí, co dostane subagent a co si nechává orchestrátor.

Pravidla z [`CLAUDE.md`](../CLAUDE.md) platí beze změny — tenhle dokument je nemění, jen říká,
**kdo je plní**. Jediná výjimka je pauza na proklikání, viz níž; ta je zapsaná jako vědomá
změna.

Postup je: **posoudit nezávislost → přidělit sloty → pustit subagenty**, a každý z nich si svoje
issue dotáhne až do mergnutého PR a releasu. Orchestrátorovi zbývá restart hlavní aplikace
a úklid.

## Kdy se to použije

Když přijde **víc než jedno issue naráz**. U jednoho se nic nemění: udělá se sériově, jak to
popisuje `CLAUDE.md`.

## 1. Posoudit, co jde souběžně

Přečti issues a odhadni, kterých souborů se dotknou. Rozhoduje **překryv v kódu**, ne velikost
zadání.

| Co se v issue objeví | Co to znamená |
|---|---|
| `ReviewPublishing`, odesílání, brána v nastavení | **Jde vždycky sama.** Je to tvrdá podmínka č. 1 a její výčet metod je schválně na jednom místě; dvě větve v něm znamenají, že se hranice posuzuje dvakrát a slučuje naslepo |
| `AppStore` — nové pole ve stavu | Souběžně **jen s jednou** další takovou. Stav je schválně na jednom místě (dělí se metody, ne data), takže dvě větve se srazí v `AppStore.swift` |
| `Policy/` — změna chování čisté funkce | Souběžně **ne** s ničím, co na té funkci stojí. Konflikt je sémantický: obě větve projdou testy samostatně a rozbijí se až po sloučení |
| `Configuration.swift` — nové nastavení | Souběžně klidně; konflikt je mechanický (dva řádky vedle sebe) |
| Nový soubor, nový modul, nová obrazovka | Souběžně bez omezení. Buildable folders znamenají, že `project.pbxproj` konfliktovat nebude |
| Jen dokumentace | Souběžně bez omezení |

**`docs/stav.md` konfliktuje skoro vždycky** a není to důvod nedělat věci souběžně — je to
mechanický konflikt dvou odstavců. Počítej s ním při mergování, ne při rozvrhu.

Když si nejsi jistý, jestli se dvě issues potkají, **je to důvod je udělat za sebou.** Cena
sériového běhu je čas; cena sémantického konfliktu je pád, který se pozná až po mergi.

## 2. Přidělit slot

**Slot subagentovi přiděluje orchestrátor.** Tohle je jediné místo, kde se paralelní běh umí
rozbít destruktivně: subagent v izolovaném worktree `.prism-slot` nemá, takže by `bin/run.sh`
buildil hlavní instanci a **přepsal aplikaci, se kterou se pracuje** — i s její cache.

Slot proto patří do **prvního kroku zadání**, ne mezi věci, na které si subagent má vzpomenout.
`<slot>` níž je zástupný znak — **dosaď za něj písmeno a u každého subagenta jiné**:

```
Napřed, ještě před čímkoli jiným: printf '<slot>\n' > .prism-slot
```

Zástupný znak tu stojí schválně místo hotového `a`: zadání se pro druhého subagenta píše
zkopírováním toho prvního, takže konkrétní písmeno v ukázce je návod, jak dva běhy poslat do
jedné cache a na jednu aplikaci — tedy přesně to, čemu slot brání. Nedosazený `<slot>`
se proti tomu **zastaví hned**, protože `run.sh` znak `<` odmítne jako nepovolený v bundle ID.

Sloty jsou `a`, `b`, `c`, … a přidělují se **na běžícího subagenta**, ne na issue. Když jeden
skončí, jeho slot se dá použít znovu — povolení k notifikacím a TCC visí na bundle ID, takže
opakované použití téhož písmene je levnější než nové.

`bin/worktree.sh` je proti tomu na **ruční** práci: zakládá strom v `../PRism-<slot>` i s
očištěnou konfigurací. Subagent ho nepoužívá, protože strom už má od harnessu.

## 3. Zadání subagenta

Subagent dostane worktree (`isolation: "worktree"`) a v zadání tohle:

- **slot** jako první příkaz (viz výš),
- **číslo issue** a pokyn, ať si ho přečte přes `gh api` (`gh issue view` v tomhle repu padá),
- pokyn, že platí `CLAUDE.md` — včetně dokumentace ve stejném commitu a vlastní revize diffu
  před pushem,
- **kde končí jeho práce**: issue je hotové, PR mergnutý, release vydaný a **jeho aplikace
  uklizená** (viz krok 5).

Co subagent dělá: implementaci, testy, vlastní revizi diffu, dokumentaci, commit, push, PR,
reakci na Copilota — a pak **merge, zavření issue a release**. Nečeká na pokyn; zelené testy,
vyřešené nálezy a hotové zadání stačí, přesně jak to `CLAUDE.md` říká o mergování obecně.

**Změna proti první verzi tohohle dokumentu** (#247), kde stálo, že subagent nemerguje a merge
patří orchestrátorovi, protože jediný vidí na všechny větve. V provozu se ukázalo, že to je
špatná hranice: hotová práce ležela a čekala, až na ni orchestrátor přijde řadu — a ten mezitím
řešil jinou větev. Zdržení rostlo s počtem běžících agentů, tedy přesně tam, kde měl paralelní
běh pomoct. Souběžné mergování je proti tomu levné: **konflikt vyřeší git**, a když nastane
(typicky `docs/stav.md`), subagent si **zvedne main sám** a doběhne. Rebase ne — main je
squashnutý, takže stačí `git fetch origin && git merge origin/main`. Proti **`origin/main`**, ne
proti lokálnímu `main`: ten je v čerstvém worktree z doby jeho vzniku, takže by merge nepřitáhl
nic — a vypadalo by to, že konflikt zmizel.

Co subagent **nedělá**:

- **nerestartuje hlavní aplikaci** — to je jediný krok po mergi, který zůstává orchestrátorovi.
  Vyžaduje build v hlavním stromě a přepsání `/Applications/PRism.app`, tedy sáhnutí na aplikaci,
  se kterou uživatel právě pracuje. Zákaz sahat mimo vlastní worktree je přednější;
- **nesahá mimo svůj worktree** — cizí strom, `/Applications` hlavní instance ani její cache;
- **neovládá aplikaci přes `System Events`** (klikání na souřadnice, přesouvání oken). Vedle sebe
  běží víc instancí PRismu a slepý klik na souřadnice skončí v cizím okně — jednomu agentovi se
  takhle povedlo přesunout a zmenšit okno hlavní instance, jinému klik spadl do cizího běhu
  a správně toho nechal. Na obrazovku se kouká **offscreen renderem** (viz
  [`testovani.md`](testovani.md)), který nic nesdílí; ovládat se dá jedině vlastní slot, a i tam
  jen tehdy, když je jistota, že je vpředu;
- **nevolá další subagenty.**

## 4. Pauza na proklikání — změna pravidla

`CLAUDE.md` chce pauzu **před prvním pushem**. V dávce **odpadá** a kontrola se přesouvá na
**hlavní aplikaci po mergi**, kterou orchestrátor restartuje.

Důvod: subagent nemá jak zavolat člověka, a kdyby na odpověď čekal, blokuje slot i sebe. Když
navíc dotahuje issue až do mergnutého PR (#247), není kde pauzu udělat, aniž by se celý smysl
paralelního běhu ztratil. Co se z pravidla ztratit **nesmí**: subagent se na obrazovku musí
podívat **sám a napřed** (screenshotem nebo offscreen renderem, viz [`testovani.md`](testovani.md)).
To je jeho práce, ne uživatelova — mergnout rozbitou obrazovku je horší než ji ukázat.

Když po restartu něco nesedí, **je z toho nové issue**, ne blokovaná větev. Je to levnější, než
jak to vypadá: změna už je v mainu, takže se opravuje proti stavu, který si člověk může skutečně
proklikat — a ne proti větvi, kterou mezitím pět dalších mergů posunulo.

**Změna proti první verzi**, kde se pauza posouvala před merge a sbírala se za celou dávku.
Padla spolu s pravidlem, že subagent nemerguje (#247).

## 5. Merge, release, restart

**Merguje si každý subagent sám**, jakmile je jeho PR zelený a Copilot vyřízený (#247) — čeká se
tedy jen na práci, ne na frontu. Pořadí se **neurčuje předem**: kdo je dřív hotov, jde dřív.

Co z toho plyne pro toho, kdo přijde druhý: **main se do větve nezvedá preventivně**, jen když to
GitHub hlásí jako konflikt nebo když větev na mergnuté změně stojí. Rebase ne — main je squashnutý,
takže stačí `git fetch origin && git merge origin/main` — a nerozbije to Copilotovi komentáře.
Znovu: proti **`origin/main`**, ne proti lokálnímu `main`.

Když jedna větev mění `Policy` nebo stav v `AppStore` a druhá na tom staví, **neměly být puštěné
souběžně** (viz krok 1). Pořadí mergů to nezachrání: konflikt je tam sémantický, takže obě větve
projdou testy samostatně a rozbijí se až po sloučení.

**Release se vydá po každém mergnutém PR**, i uprostřed dávky — stejně jako mimo ni. Pravidlo
z `CLAUDE.md` se dávkou nemění.

**Změna proti první verzi tohohle dokumentu**, kde stálo „jeden release za celou dávku“. Bylo to
špatně a stálo to na záměně dvou věcí: release je záznam **jedné změny**, ne shrnutí odpoledne.
Sloučený release za čtyři issues nemá jak odpovědět na otázku „co je v téhle verzi jinak“, protože
odpovědi jsou čtyři — a přesně kvůli tomu se u #125 zahodil formát „deník projektu“. Že čísla
verzí přibývají rychleji, není argument: verze je značka na časové ose a značek má být tolik, co
změn.

**Po každém mergi se restartuje hlavní aplikace** — `./bin/run.sh` v hlavním stromě, tedy v tom
bez slotu. Dávka na tom nic nemění; pravidlo je v `CLAUDE.md`. Odkládat restart na konec série
by znamenalo, že mergnutý kód mezitím nikdo nespustí — a to je zrovna to, kvůli čemu pravidlo
vzniklo.

**Sloty se restartem netknou** — mají vlastní bundle ID a `run.sh` v hlavním stromě ukončuje
instanci podle cesty. Ověřeno v provozu: `PRism-a`, `-b`, `-c` běžely dál, hlavní instanci se
změnil PID. Čtyři instance vedle sebe, čtyři cache.

Po mergi větve subagenta zbyde jeho **pracovní strom** — harness ho sám neuklidí, jakmile na
něm doběhl. Odklidit ho patří k mergi:

```bash
git worktree list                       # zamčené stromy patří běžícím agentům, ty nech být
git worktree remove <cesta> && git branch -d <větev>
```

**Svou aplikaci uklidí subagent sám** (#250), jakmile domergoval — ukončí ji, odregistruje
z LaunchServices a smaže i s cache:

```bash
osascript -e 'tell application id "com.ondrajodas.prism.<slot>" to quit'
"$LSREGISTER" -u "/Applications/PRism-<slot>.app"     # cesta viz bin/run.sh
rm -rf "/Applications/PRism-<slot>.app" ~/Library/"Application Support"/PRism-<slot>
```

Bez toho se instance hromadí: po jednom odpoledni jich byly v `/Applications` čtyři vedle hlavní
a v Launchpadu ani Spotlightu se z nich nedá vybrat, protože se jmenují skoro stejně. Je to tentýž
problém, jaký #139 řešil u kopie v `build.noindex/` — jen ho tentokrát vyrábí paralelní běh.

**Cache se maže taky.** Není sice vidět v systému, ale zůstávají v ní data, kterými si agent
zkoušel UI — v jednom slotu takhle zbyl vyrobený záznam nálezů pro sandbox PR, který by příštího
agenta na tomtéž písmenu mátl. Cena je nulová: klony se dotáhnou znovu, jen když je někdo
potřebuje.

**Odregistrovat se musí před smazáním bundlu**, a jedině **vlastní** slot. Cizí instance se nesmí
ukončit ani odregistrovat — může na ní běžet jiný agent nebo ji může mít otevřenou člověk.

**Změna proti první verzi** (#250), kde stálo, že se aplikace i cache nechávají „až slot doopravdy
skončí“, protože další subagent dostane totéž písmeno a je levnější mu nechat udělená povolení
k notifikacím. Slot **skončil** ve chvíli, kdy agent domergoval — a nasbírané aplikace jsou horší
než jeden dotaz na notifikace navíc.

## 6. Kde je strop

Ne ve stroji. Změřeno u #228: clean build 23 s, test run s 1864 testy 25 s, medián zátěže
611 % z 1500 % dostupných (5 výkonných jader z 15 logických). Proti třicetiminutové iteraci
jsou to necelá 3 %.

Strop je v tom, **kolik je po ruce nezávislých issues**, a v merge kaskádě. Praktické meze:

- **Každý slot je pro macOS jiná aplikace**, takže si vyžádá vlastní povolení k notifikacím.
- **Disk**: `build.noindex` je ~734 MB na strom.
- **Tři a víc větví** znamená, že se po každém mergi řeší, jestli zbylé zvedat — při dvou je
  to zanedbatelné, při pěti je to deset dvojic, které se můžou potkat.
