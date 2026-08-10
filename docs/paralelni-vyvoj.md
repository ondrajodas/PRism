# Paralelní vývoj

Jak se vyřizuje **seznam** issues. Prostředí na to dalo #228 (sloty), tohle je postup: co se
posoudí, co dostane subagent a co si nechává orchestrátor.

Pravidla z [`CLAUDE.md`](../CLAUDE.md) platí beze změny — tenhle dokument je nemění, jen říká,
**kdo je plní**. Jediná výjimka je pauza na proklikání: **nepadá, ale posouvá se před merge**
a jde přes orchestrátora (§4). Je to zapsané jako vědomá změna.

Postup je: **posoudit nezávislost → přidělit sloty → pustit subagenty**, a každý z nich si svoje
issue dotáhne až do mergnutého PR a releasu — s jedinou zastávkou na proklikání těsně před mergem.
Orchestrátorovi zbývá rozvrh, sloty, tlumočení připomínek, restart hlavní aplikace a úklid —
**ne implementace** (sekce *Co dělá orchestrátor — a co ne*).

## Kdy se to použije

Když přijde **víc než jedno issue naráz**. U jednoho se nic nemění: udělá se sériově, jak to
popisuje `CLAUDE.md`.

## Co dělá orchestrátor — a co ne

**Orchestrátor v dávce neimplementuje, deleguje.** Jeho práce je celá dávka, ne jedna větev
v ní. Jmenovitě:

- **posoudí nezávislost** issues a rozhodne, co jde souběžně a co za sebou (§1);
- **přiděluje sloty** — na běžícího subagenta, ne na issue (§2);
- **píše zadání**, včetně slotu, čísla issue a pauzy před mergem (§3);
- **tlumočí připomínky** — pauza vede přes něj (`SendMessage` na `main`), takže drží, kdo na co
  čeká a komu co předat (§4);
- **pošle nového subagenta do stromu po skončené session** (viz níž);
- **domergne cizí větev jen v krajním případě** — když už nezbývá nic než merge, release a úklid
  (PR zelený, Copilot vyřízený, člověk proklikal) a subagent už neběží. Kde ve stromě zbyla
  rozdělaná práce, patří nový subagent, ne orchestrátorův merge;
- **restartuje hlavní aplikaci po každém mergi** a **uklízí pracovní stromy** (§5). Obojí sahá do
  hlavního stromu, a to je právě to jediné místo, kam subagent nesmí.

Co orchestrátor **nedělá**: **implementaci zadání** — tedy kód, testy ani dokumentaci, které patří
k nějakému issue. Není to zákaz psát cokoli — zakládat issues (definovat práci je jeho),
odpovídat na PR, mergovat, uklízet a restartovat aplikaci smí. Hranice je **implementace
zadaného issue**, ne psaní jako takové.

Důvod je **kontext**, ne rozdělení rolí na papíře. Orchestrátorův kontext drží rozvrh, stav
všech běžících větví a připomínky, které má komu předat — a to za něj nikdo neudrží, protože
subagent vidí jen své issue. Implementace je proti tomu to, co se dá rozdat: je uzavřená v jednom
stromě a subagent u ní může spálit 300 tisíc tokenů, aniž by to někoho dalšího zajímalo. Když si
ji orchestrátor vezme, stane se dvojí:

1. **Utopí kontext v jedné větvi** a přestane stíhat to, co za něj nikdo neudělá. Hlášení
   ostatních agentů pak leží a čeká — tedy přesně to zdržení, kvůli kterému #247 posunul merge
   na subagenty.
2. **Nemá kde tu práci nechat.** Subagentův strom a slot jsou jeho, hlavní strom je uživatelův.
   Orchestrátor tedy implementuje v cizím stromě, nebo v tom jednom, do kterého se sahat nemá.

**„Jen dokumentace“ výjimka není.** Právě u takového issue je pokušení největší, a přitom se od
kódu neliší ničím, co by tu hranici posouvalo: taky má branch, PR, Copilota a release — a taky
sní kontext.

Zapsané je to proto, že se to na M9 stalo dvakrát (#259): pravidlo #256 napsal orchestrátor sám
a u opravy `Průběhu` (#242) začal implementovat v odumřelém stromě po předchozím agentovi, dokud
to člověk nezastavil větou „nechceš spíš pustit nového sub-agenta?“. Do té doby byl jmenovitý
výčet jen na straně subagenta (§3) a o orchestrátorovi tu stálo jen to, co mu *zbývá* — z toho
zákaz nevyplýval, takže chybějící věta vypadala jako volba.

### Strom po skončené session

Odumřelý strom je důvod subagenta **pustit**, ne implementovat: strom stojí, rozdělanou práci
i větev v sobě má a dá se do něj poslat nový agent. Když tedy subagentova session skončí a jeho
strom zůstane rozdělaný, **pustí se do toho stromu nový subagent** — ne nový worktree z mainu
(přišel by o větev i o otevřený PR a začal by od nuly) a ne orchestrátor sám, viz výš.

Zadání takového agenta se od běžného (§3) liší ve třech věcech:

- **bez `isolation: "worktree"`**, protože ten by mu založil nový strom. Do existujícího vstoupí
  `EnterWorktree` s `path` — strom musí být v `git worktree list`, což ten po skončeném agentovi
  je, harness ho sám neuklidí (§5);
- **cesta k tomu stromu, číslo existujícího PR a stav Copilota na něm.** Slot se **nepřepisuje** —
  strom ho má v `.prism-slot` z minula a je to tentýž, na kterém se pak bude klikat;
- **zákaz zakládat novou větev a nový PR.** Dotahuje se ten, který stojí, a to celý: vyřízení
  Copilota, pauza, merge, zavření issue, release a úklid slotu (§4, §5).

Strom se **uklidí až po mergi**, jako každý jiný (§5). Odklizený dřív by vzal nově puštěnému
agentovi to, kvůli čemu tam jde.

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

Subagent dostane worktree (`isolation: "worktree"`) — **výjimka je strom po skončené session**,
kde se nový nezakládá a zadání se liší ve třech věcech (viz *Co dělá orchestrátor — a co ne*) —
a v zadání tohle:

- **slot** jako první příkaz (viz výš),
- **číslo issue** a pokyn, ať si ho přečte přes `gh api` (`gh issue view` v tomhle repu padá),
- pokyn, že platí `CLAUDE.md` — včetně dokumentace ve stejném commitu a vlastní revize diffu
  před pushem,
- **pauzu na proklikání před mergem** i s tím, co má v hlášení stát (§4). Patří to do zadání ze
  stejného důvodu jako slot: všechno ostatní subagenta tlačí k dotažení, takže pauza doháněná
  zprávou během běhu **přijde pozdě** — na M9 tak dva ze čtyř agentů domergovali dřív, než jim
  zpráva došla,
- **kde končí jeho práce**: issue je hotové, PR mergnutý, release vydaný a **jeho aplikace
  uklizená** (viz krok 5).

Co subagent dělá: implementaci, testy, vlastní revizi diffu, dokumentaci, commit, push, PR,
reakci na Copilota — pak **pauzu na proklikání** a po ní **merge, zavření issue a release**. Na
pokyn čeká **jedině u té pauzy**; na nic jiného, protože zelené testy, vyřešené nálezy a hotové
zadání stačí, přesně jak to `CLAUDE.md` říká o mergování obecně.

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

`CLAUDE.md` chce pauzu **před prvním pushem**. V dávce se **nezruší, jen se posune před merge**:
subagent má hotový PR i vyřízeného Copilota, zastaví a nechá člověka proklikat **svou slotovou
aplikaci**. Merge čeká na odpověď; všechno před ním si subagent řídí sám.

Jak to technicky drží: subagent **zavolá člověka přes orchestrátora** — `SendMessage` na `main`
— a **skončí svůj turn**. Čekáním tedy neblokuje ani slot, ani sebe: leží pasivně a zpráva
s odpovědí ho probudí z transkriptu se zachovaným kontextem.

Co má v hlášení stát, aby pauza k něčemu byla:

- **číslo PR** a jak je vyřízený Copilot,
- **jméno aplikace, kterou má člověk otevřít** (`/Applications/PRism-<slot>.app`) — a čerstvě
  nainstalované, `./bin/run.sh` ve svém stromě těsně předtím, ať se nekouká na starý build,
- **na co se má podívat**: obrazovka, cesta k ní a co v ní uvidí. Když se ke stavu nedá dojít
  běžným používáním (šířka okna, spadlá session), tak i **jak se k němu dostat**,
- **co si měřil sám** a co mu na tom nesedělo.

Co se z pravidla ztratit **nesmí**: subagent se na obrazovku musí podívat **sám a napřed**
(screenshotem nebo offscreen renderem, viz [`testovani.md`](testovani.md)). Pauza to nenahrazuje —
ukázat obrazovku, na které je něco zjevně rozbité, je kolo navíc, stejně jako u Copilota.

**Neviditelná změna pauzu nedostane** (vrstva bez UI — modely, parser, protokol). Subagent napíše
do hlášení jednou větou, že vidět není nic a proč, doloží to zelenými testy a merguje. Rozhoduje,
jestli se něco změnilo na obrazovce, ne jak je změna velká — je to tentýž rozdíl, jaký má
`CLAUDE.md` mimo dávku.

**Slot se uklízí až po mergi**, nikdy před pauzou (§5). Uklizená aplikace znamená, že není na čem
klikat — a přesně to se na M9 stalo u #237.

**Změna proti #247**, kde stálo, že pauza v dávce odpadá a kontrola se přesouvá na hlavní aplikaci
po mergi, protože „subagent nemá jak zavolat člověka". Změnilo se to ze dvou důvodů:

1. **Ta premisa byla nepravdivá.** Subagent má cestu k člověku přes orchestrátora a čekání ho nic
   nestojí. Argument o blokovaném slotu tedy neplatil — platí jen o tom, kdyby čekal aktivně.
2. **Směna byla nevýhodná.** Připomínka k větvi, která ještě stojí, je jedna změna v ní.
   Tatáž připomínka po mergi je nové issue, tedy branch, PR, Copilot, merge a release znovu.
   Pauza před mergem je proti tomu skoro zdarma, protože se vejde do okna, ve kterém stejně
   čekáme na Copilota (latence v minutách).

**Zastavuje se před mergem, ne před prvním pushem** — proti pravidlu mimo dávku je to vědomý
posun. Mimo dávku sedí pauza před pushem, protože tam je změna nejlevnější na přepsání; v dávce by
to ale znamenalo dvě čekání za sebou (na člověka a pak na Copilota), kdežto před mergem se obojí
překryje. Cena je, že připomínka přijde nad kódem, který už prošel review; to je přijatelné,
protože se řeší vzhled a chování, ne struktura.

Co po mergi nesedí přesto, **je nové issue**, ne vracení mergnuté větve — to zůstává z #247
v platnosti. Pauza počet takových issues zmenšuje, nenuluje ho.

## 5. Merge, release, restart

**Merguje si každý subagent sám**, jakmile je jeho PR zelený, Copilot vyřízený (#247) a člověk
změnu proklikal (#256, §4) — čeká se tedy na práci a na jedno slovo, ne na frontu. Pořadí se
**neurčuje předem**: kdo je dřív hotov, jde dřív.

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

**Strom s rozdělanou prací se nemaže**, i když jeho agent skončil — dotáhne ho nový subagent
puštěný do něj (viz *Co dělá orchestrátor — a co ne*). Odklízí se až po mergi jeho PR.

**Svou aplikaci uklidí subagent sám** (#250), jakmile domergoval — ukončí ji, odregistruje
z LaunchServices a smaže i s cache:

```bash
SLOT=a   # svůj, nikdy cizí
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

osascript -e "tell application id \"com.ondrajodas.prism.${SLOT}\" to quit"
"${LSREGISTER}" -u "/Applications/PRism-${SLOT}.app"
rm -rf "/Applications/PRism-${SLOT}.app" ~/Library/"Application Support"/PRism-${SLOT}
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
