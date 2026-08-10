# Paralelní vývoj

Jak se vyřizuje **seznam** issues. Prostředí na to dalo #228 (sloty), tohle je postup: co se
posoudí, co dostane subagent a co si nechává orchestrátor.

Pravidla z [`CLAUDE.md`](../CLAUDE.md) platí beze změny — tenhle dokument je nemění, jen říká,
**kdo je plní**. Jediná výjimka je pauza na proklikání, viz níž; ta je zapsaná jako vědomá
změna.

## Kdy se to použije

Když přijde **víc než jedno issue naráz**. U jednoho se nic nemění: udělá se sériově, jak to
popisuje `CLAUDE.md`.

Postup je: **posoudit nezávislost → přidělit sloty → pustit subagenty → mergovat v pořadí →
vydat release.**

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
- **kde končí jeho práce**: PR je otevřený a Copilot vyřízený.

Co subagent dělá: implementaci, testy, vlastní revizi diffu, dokumentaci, commit, push, PR
a reakci na Copilota.

Co subagent **nedělá**:

- **nemerguje** — pořadí mergů ovlivňuje ostatní běžící větve, takže je to rozhodnutí, které
  musí dělat jeden, kdo vidí na všechny;
- **nezavírá issue a nevydává release** — release je jeden na dávku, ne na větev;
- **nesahá mimo svůj worktree** — cizí strom, `/Applications` hlavní instance ani její cache;
- **nevolá další subagenty.**

## 4. Pauza na proklikání — změna pravidla

`CLAUDE.md` chce pauzu **před prvním pushem**. V paralelním režimu se posouvá **před merge**
a sbírá se za celou dávku naráz.

Důvod: subagent nemá jak zavolat člověka, a kdyby na odpověď čekal, blokuje slot i sebe.
Smysl pauzy je „ať si to proklikám, dokud je změna levná na přepsání“ — a **PR před mergem
levný pořád je**. Co se nemění: subagent se na obrazovku musí podívat **sám a napřed**
(screenshotem, viz [`testovani.md`](testovani.md)), a to i tady. Ukázat rozbitou obrazovku je
kolo navíc bez ohledu na to, kdo ji ukazuje.

Orchestrátor pak řekne jednou větou, **co je u které větve k vidění** a co si má člověk
proklikat. Větve, na kterých není co vidět, se mergují bez pauzy.

## 5. Mergovat v pořadí

Nejdřív ta větev, **na které ostatní stojí** — když jedna mění `Policy` nebo `AppStore` stav,
jde první, protože ostatní se pak srovnají proti ní.

Po každém mergi platí pravidlo z `CLAUDE.md`: **main se do zbylých větví nezvedá preventivně.**
Jen když to GitHub hlásí jako konflikt, nebo když větev na mergnuté změně stojí. Rebase ne —
main je squashnutý, takže `git merge main` stačí a nerozbije Copilotovi komentáře.

Release se vydá **jeden za celou dávku**, ne na každou větev. Pořadí čísel by jinak říkalo
něco, co není pravda — verze je značka na časové ose.

**Po posledním mergi dávky se restartuje hlavní aplikace** (`./bin/run.sh` v hlavním stromě,
tom bez slotu). Po každém jednotlivém mergi ne: v dávce jich jde několik za sebou a každý
restart zavírá okno, ve kterém se zrovna něco čte. Pravidlo samotné je v `CLAUDE.md`, tady je
jen ta odchylka pro dávku.

**Sloty se restartem netknou** — mají vlastní bundle ID a `run.sh` v hlavním stromě ukončuje
instanci podle cesty. Ověřeno v provozu: `PRism-a`, `-b`, `-c` běžely dál, hlavní instanci se
změnil PID. Čtyři instance vedle sebe, čtyři cache.

Po mergi větve subagenta zbyde jeho **pracovní strom** — harness ho sám neuklidí, jakmile na
něm doběhl. Odklidit ho patří k mergi:

```bash
git worktree list                       # zamčené stromy patří běžícím agentům, ty nech být
git worktree remove <cesta> && git branch -d <větev>
```

Aplikace slotu (`/Applications/PRism-a.app`) a jeho cache se ruší **až když slot doopravdy
skončil**, ne po každém mergi — další subagent dostane totéž písmeno a je levnější mu nechat
udělená povolení k notifikacím než si o ně říkat znovu.

## 6. Kde je strop

Ne ve stroji. Změřeno u #228: clean build 23 s, test run s 1864 testy 25 s, medián zátěže
611 % z 1500 % dostupných (5 výkonných jader z 15 logických). Proti třicetiminutové iteraci
jsou to necelá 3 %.

Strop je v tom, **kolik je po ruce nezávislých issues**, a v merge kaskádě. Praktické meze:

- **Každý slot je pro macOS jiná aplikace**, takže si vyžádá vlastní povolení k notifikacím.
- **Disk**: `build.noindex` je ~734 MB na strom.
- **Tři a víc větví** znamená, že se po každém mergi řeší, jestli zbylé zvedat — při dvou je
  to zanedbatelné, při pěti je to deset dvojic, které se můžou potkat.
