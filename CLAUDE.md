# CLAUDE.md

Pravidla pro práci Claude Code v tomto repu.

**Tady jsou pravidla, v `docs/` jsou důvody.** Když je u pravidla odkaz, je za ním měření,
zamítnutá varianta nebo historie změny — přečti si ho dřív, než pravidlo obejdeš, ne až potom.
Tady zůstává doslova to, co je potřeba znát **dřív, než se něco napíše**: věty pravidel, výčty
tvrdých podmínek a grepy, které se pouštějí před pushem.

## Údržba dokumentace — platí vždy

**Každá změna, kterou tady uděláme, se musí promítnout do dokumentace.** Není to úklid na
konec, dělá se to **ve stejném commitu** jako samotná změna. Cílem je, aby se aplikace dala
pochopit z dokumentace bez čtení kódu — a aby další session Claude Code měla po přečtení
tohohle souboru dost kontextu na to, aby věděla, kam sáhnout.

Co kam patří:

| Soubor | Obsah | Kdy aktualizovat |
|---|---|---|
| `README.md` | Co aplikace je, jak funguje, jak se buildí a spouští, požadavky, struktura repa | Změna chování, rozsahu, požadavků, build postupu nebo struktury |
| `CLAUDE.md` | **Pravidla**: jak se v repu pracuje, tvrdé podmínky, konvence, příkazy, prostředí, tabulka modulů | Změna pravidla, konvence, příkazu nebo hranic modulů |
| [`docs/architektura.md`](docs/architektura.md) | Podrobnosti po modulech — co který drží a co se u něj nemá rozbít | Změna uvnitř modulu: nový typ, nový invariant, jiné chování |
| [`docs/testovani.md`](docs/testovani.md) | Katalog toho, co se u které oblasti testuje a proč — **a jak se v tomhle repu měří** | Nová oblast testů, nový případ, který se dá pokazit potichu, nebo nový postup měření |
| [`docs/navrh.md`](docs/navrh.md) | Kde je vizuální návrh a jak se s ním pracuje — čtení CSS, aktualizace, render vedle screenshotu | Změna postupu při práci s mockupem (samo pravidlo je v `CLAUDE.md`) |
| [`docs/claude-cli.md`](docs/claude-cli.md), [`docs/github-cli.md`](docs/github-cli.md) | Ověřené chování cizích CLI: co dělá `claude -p` s povoleními, co v tomhle repu na `gh` padá a čím to nahradit | Nové zjištění o chování `claude` nebo `gh` |
| [`docs/stav.md`](docs/stav.md) | Co je hotové a co zbývá | Dokončené issue |
| [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) | Jak se vyřizuje **seznam** issues: co jde souběžně, jak vypadá milník na větší objem práce, co dostane subagent, co si nechává orchestrátor, kdo merguje | Změna postupu při dávce, podoby milníku, nebo toho, co si subagent ani orchestrátor nesmí dovolit |
| `docs/superpowers/specs/` | Proč jsou rozhodnutí taková, jaká jsou — včetně zamítnutých alternativ **a zdůvodnění pravidel z tohohle souboru** | Změna návrhového rozhodnutí; zapsat i **proč** se změnilo, staré nechat v záznamu rozhodnutí |

Když se změna nikam z toho nevejde, je to signál, že jsem si neujasnil, co vlastně měním
— vyřešit to, ne to přeskočit.

Konkrétně: přidání modulu → `docs/architektura.md` + tabulka modulů v `CLAUDE.md`
+ `README.md` (struktura, pokud se mění). Změna konfigurace → `README.md` (klíčová
rozhodnutí) + specifikace. Nový build příkaz → `README.md` + sekce Příkazy níž. Zahození
návrhového rozhodnutí → specifikace, včetně důvodu.

**`CLAUDE.md` se drží malý, a je to podmínka, ne estetika** (#162, znovu #447). Copilot si ho
bere jako custom instructions se stropem 110 tisíc tokenů — když ho přeroste, review na PR
**vůbec nedoběhne** a v okně po něm zbude jen nicneříkající chyba. Sem se píše jen to, co je
potřeba znát dřív, než se něco napíše; **podrobnost, měření a technika měření patří do `docs/`**.
Kontroluj to **měřením, ne odhadem** — nad ~100 kB je čas rozdělovat znovu:

```bash
wc -c < CLAUDE.md    # po #447 ~66 kB; nad ~100 kB je čas rozdělovat znovu
```

Co se stalo při 315 kB, jak se pád pozná z logu akce, proč nerozhodovala velikost diffu a co
dělat, když Copilot přesto nedoběhne, je v [specifikaci, *`CLAUDE.md` se drží
malý*](docs/superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447).

## Jazyk

- **Dokumentace, specifikace, komentáře a prózu piš česky.** Včetně tohoto souboru,
  README a všeho v `docs/`.
- **Identifikátory v kódu anglicky** — názvy typů, funkcí, polí, souborů, flagů:
  `blockingCategories`, `headSha`, `ReviewRunner`. Kód se česky nepíše.
- **Issues celé česky** — titulek i popis.
- **Commit messages, názvy branchí a titulky PR anglicky.** Formát
  [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- **Popisy PR česky.** Titulek zůstává anglicky (je z něj commit message při mergi),
  ale tělo PR je próza pro mě. Platí i pro komentáře na PR a odpovědi na review.
- **Release notes česky** (viz Pracovní postup).
- **Žádné AI atribuce** v commitech ani v PR — bez podpisů a bez „generated with“.

## Pracovní postup (git)

- **Víc issues naráz se dělá souběžně, ne za sebou** (#231). Když přijde seznam, posuď, co je
  na sobě nezávislé, přiděl slot a pusť na každé nezávislé issue **subagenta ve vlastním
  worktree**. Postup je v [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) a **přečti si ho
  dřív, než subagenta pustíš** — slot mu přiděluje orchestrátor a bez něj by subagent přepsal
  aplikaci, se kterou zrovna pracuju, i s její cache. U **jednoho** issue se nic nemění.

  **Subagent dotáhne issue až do konce** (#247): PR, Copilot, merge, zavření issue, release
  a **úklid své aplikace** (`./bin/slot-cleanup.sh` ve svém stromě, #398); nečeká na frontu
  u orchestrátora. **Odepřené povolení se neobchází, hlásí se** (#273) jako neověřená mezera.
  **Orchestrátor v dávce neimplementuje, deleguje** (#259) — ani u issue, které je „jen
  dokumentace“; zůstává mu rozvrh, sloty, tlumočení připomínek, úklid stromů a **restart hlavní
  aplikace** (sahá do hlavního stromu, což subagent nesmí). Proč je to takhle a co přesně
  dostane subagent do zadání, je v
  [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md#co-dělá-orchestrátor--a-co-ne), sekce
  [*3. Zadání subagenta*](docs/paralelni-vyvoj.md#3-zadání-subagenta).
- **Všechno jde přes PR.** Žádné přímé pushe do `main` — každá změna (kód i dokumentace)
  má vlastní branch a PR, i když je malá. PR odkazuje na issue, které řeší.
- **Branch:** anglicky, krátce, s číslem issue — např. `issue-4-github-gateway`.
- **Před prvním pushem mi appku spusť (`./bin/run.sh`) a dej mi prostor na připomínky — ale jen
  když je na změně co vidět.** Platí pro první push branche, ne pro opravy po review.

  Pak **zastav a čekej.** Ne „spustil jsem a jde to“ a hned commit — smysl je, že si to
  proklikám, dokud je změna ještě levná na přepsání. Zelené testy nejsou důkaz, že se to
  chová, jak jsem chtěl. Napiš, **na co se mám podívat** a co v příslušné obrazovce uvidím.
  **V dávce se pauza nezruší, jen se posune před merge** (#256, mění #247): subagent zastaví
  s hotovým PR a zavolá mě **přes orchestrátora** (`SendMessage` na `main`) — čekáním neblokuje
  slot ([podrobnosti](docs/paralelni-vyvoj.md#4-pauza-na-proklikání--změna-pravidla)).

  **Napřed se na to ale podívej sám — screenshotem.** `screencapture -x -R<x,y,w,h>` funguje
  a mockup se dá vyrendrovat headless Chromem a položit vedle ([`docs/testovani.md`, *Jak si
  zkontrolovat, jak view vypadá*](docs/testovani.md#jak-si-zkontrolovat-jak-view-vypadá)).
  Ukázat mi obrazovku, na které je něco zjevně rozbité, znamená použít mě jako první kolo
  kontroly. Platí to i pro komponentu, která se jen **přesunula do užšího místa**: jiná šířka
  je jiný design a plné popisky, počty a odznaky se do ní obvykle nevejdou. A **nezapomeň před
  tou pauzou rebuildnout**, ať nekoukám na starý build.

  **Když se změna v UI nijak neprojeví** (vrstva bez UI — modely, parser, protokol),
  **na pauzu mě netahej.** Napiš do shrnutí jednou větou, že vidět není nic a proč, dolož to
  zelenými testy a **pokračuj rovnou na commit a PR**. Rozhodující je, jestli se něco změnilo
  na obrazovce, ne jestli je změna malá: oprava textu v labelu se ukazuje, nový `Codable`
  model ne.
- **Vlastní revize diffu je podmínka pushnutí, ne doporučení.** `copilot-review.sh` se smí
  pustit teprve po ní, a revize se musí někde **projevit** — buď opravou, nebo větou v popisu
  PR o tom, co jsi hledal. Když po ní diff vypadá nedotčeně a Copilot pak najde něco, co grep
  z tabulky níž chytá, revize neproběhla. Subagent je fajn, ale **není podmínka**: projít
  `git diff main...HEAD` vlastníma očima plus grepy níž zabere minuty.

  **Tohle Copilot v tomhle repu nachází opakovaně**, takže to projdi dřív, než ho pustíš:

  | Vzor | Proč to bolí |
  |---|---|
  | `try?`, prázdný `catch`, `?? default` nad operací, která může selhat | Ztracená data vypadají v UI jako „nic tu nebylo“. U každého se ptej: pozná uživatel, že se to nepovedlo? Když ne, patří to do stavu, ne do `try?` |
  | Text v UI, který tvrdí víc, než data unesou | „Reviewer nenahlásil žádný nález“ zní jako čisto i tehdy, když se nálezy nemají kde vzít |
  | Stav, který se drží, ale nikdo ho nečte | Buď to zobraz, nebo nedrž — jinak je to mrtvá váha, která svádí k tomu spolehnout se na ni |
  | Kontrola, která jinde v repu je, a tady chybí | Typicky ochrana proti mazání mimo cache. Když už někde existuje, patří na jedno místo a použije se z obou |
  | Čtení nebo dekódování všeho, když stačí předfiltr | U operací, které běží při každém uložení nebo tiku, to není detail |

  **Když nález přijde, oprav třídu, ne výskyt.** Copilot vidí vždycky jen nový diff, takže na
  druhý výskyt téhož vzoru upozorní až v dalším kole. Po každém reálném nálezu proto projdi
  diff na tentýž vzor (`git diff main...HEAD | grep …`) a oprav všechny naráz.
- **Po vytvoření PR na něj pusť Copilota a počkej na výsledek** — `./bin/copilot-review.sh
  <číslo PR>`. **`gh pr edit --add-reviewer Copilot` nepoužívej**: bota to tiše zahodí. `gh pr
  edit` obecně a `gh issue view` na tomhle repu **padají** (deprecated Projects classic), takže
  se čte a edituje přes REST. Příkazy, dvě jména, pod kterými Copilot píše, a proč
  „generated no new comments“ neznamená, že nic nenašel, jsou
  v [`docs/github-cli.md`](docs/github-cli.md) — **přečti si to, než výsledek budeš číst.**
- **Copilot je kontrola, ne hledání — stačí jedno kolo.** Pusť ho jednou, nálezy projdi (řekni,
  co je reálné a co šum), reálné oprav a **mergni podle vlastního uvážení**. Další kolo si
  vyžádej jen tehdy, když ten první průchod odhalil něco **strukturálního** — vzor, který se
  opravou mohl objevit i jinde, ne překlep. ([Kolik kol to stálo, než z toho tohle pravidlo
  vzniklo.](docs/superpowers/specs/2026-07-31-prism-design.md#vlastní-revize-diffu-je-podmínka-pushnutí-ne-doporučení-46))

  **Nemusíš vyhovět všem komentářům.** Copilot navrhuje i věci, které v tomhle repu nedávají
  smysl. Rozhoduješ ty — u nálezu, který neopravíš, ale musí být odpověď s důvodem. Když si
  radou nejsi jistý, ověř ji (spusť to, změř to); zamítnutí podložené měřením je lepší než
  oprava naslepo. Když **nedoběhne vůbec** („Copilot encountered an error…“), jsou příčiny dvě
  a poznají se podle toho, jestli job běžel: spadlý job = velikost `CLAUDE.md` (viz *Údržba
  dokumentace* výš), **nespuštěný job = spotřebovaný request** (#452 — čtyři a půl hodiny ticha;
  vyžádat znovu tehdy **nepomůže**, postup je v [`docs/github-cli.md`](docs/github-cli.md)).
- **PR, který je v pořádku, mergni sám.** Nečekej na pokyn: zelené testy, vyřešené nálezy
  a hotové zadání issue stačí. Po mergi rovnou **zavři issue** a **vydej release**.
  Když si nejsi jistý, jestli je hotovo, tak hotovo není — dodělej to, neptej se.
- **Po mergi mi restartuj hlavní aplikaci z mainu** — `./bin/run.sh` v hlavním stromě, bez
  ptaní, **po každém mergi, i uprostřed dávky**. Co je mergnuté, mám mít i spuštěné; jinak se
  regrese pozná až za týden. `run.sh` ukončuje Apple eventem, takže při běžícím review se zeptá
  a bez odpovědi nespustí nic — to je záměr, nepřemlouvej to `killall`em. Když skript skončí
  nenulově, **řekni to** a nech starou instanci běžet.
- **Po mergnutí PR se vydá nový tag a GitHub release.** Release notes píšeme česky
  a popisují **jen to, co se v téhle verzi změnilo**: co přibylo, co se opravilo, co se
  rozhodlo jinak a proč, co se změřilo, co se zamítlo. Patří tam i to, co se změnou
  souvisí — počet testů, věta „na tomhle není co vidět“ u vrstvy bez UI, známé omezení.

  **Stav projektu do nich nepatří.** Žádná sekce `Kde jsme`, `Další krok`, `Stav proti
  milníkům` ani výčet toho, co zbývá do milníku. Kde projekt je, se pozná z issues a ze
  sekce *Stav* níž; release odpovídá jen na otázku „co je v téhle verzi jinak“. ([Proč se
  formát „deník projektu“
  zahodil.](docs/superpowers/specs/2026-07-31-prism-design.md#release-notes-jsou-záznam-jedné-změny-ne-deník-projektu-125))
- **Větší objem práce dostane vlastní milník** (#340) — orientačně **tři a víc issues, které
  patří k sobě**. Nenechává se nasypaný v `Průběžné` a nečeká se, až o milník někdo požádá:
  u tří issues je **rozvrh polovina zadání** a milník je jediné místo, kde ta informace přežije
  napříč sessions. Jak takový milník vypadá, je v [`docs/paralelni-vyvoj.md`, *Rozvrh se zapisuje
  do milníku*](docs/paralelni-vyvoj.md#rozvrh-se-zapisuje-do-milníku-ne-jen-do-kontextu) —
  **přečti si to, než milník založíš.**
- **Verzování:** `v0.<milník>.<pořadí PR v milníku>` — např. třetí mergnutý PR v milníku 1 je
  `v0.1.3`. Verze `v1.0.0` = dokončený rozsah v1 podle specifikace. **Milník `Průběžné` číslo
  nemá** a PR z něj **pokračuje v číslování běžící fáze**; stejně tak **nový milník novou řadu
  verzí nezakládá** — od `v1.0.0` běží jedna řada (`v1.1.x`) a číslo milníku v ní roli nehraje
  (M9 v ní vyšel celý: #184 jako `v1.1.87`, #245 jako `v1.1.89`). Důvod je u obojího týž: verze
  je **značka na časové ose, ne štítek původu**.
- Binárky se do release nepřikládají — buildujeme lokálně. Release slouží k záznamu
  změn, ne k distribuci.

## Co aplikace je

Nativní macOS aplikace (SwiftUI), která hlídá GitHub PR přiřazené mně k review, spouští
na ně review skilly Claude Code jako headless session a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Když se objeví
potřeba „chytřejšího“ review, patří to do skillu, ne do aplikace.

Plný návrh: [`docs/superpowers/specs/2026-07-31-prism-design.md`](docs/superpowers/specs/2026-07-31-prism-design.md)

## Návrh (mockup)

Jak má aplikace vypadat, drží **[`docs/navrh.html`](docs/navrh.html)** — od #332 je zdroj
v repu a artifact `PRism — návrh vizuální revize` je jeho publikovaná kopie:
<https://claude.ai/code/artifact/5206622c-19b2-4c4e-9041-849d5b6d4a51>. Čte se tedy grepem
nad souborem, ne `WebFetch`em. Tokeny v `:root` jsou `App/Views/Palette.swift` jedna ku jedné,
takže se z něj barvy i rozměry berou doslova, ne od oka. **Úprava návrhu je jeden commit
a jedno publikování** — jinak v repu leží jiný návrh než na odkazu.

**Issue, které mění vzhled nebo přidává něco nového na obrazovku, se na GitHubu
nezakládá, dokud ta změna není zakreslená v mockupu a odsouhlasená mnou.** Pořadí je:
překreslit mockup → poslat mi odkaz → počkat na souhlas → **teprve pak** `gh issue create`.
Je to **jediná schvalovací brána v tomhle repu** (výjimka z *Rozhodování* níž).

Brána sedí u **zakládání issue**, ne až u prvního commitu, a je to schválně: issue je
zadání, ne nápad — od chvíle, kdy je na GitHubu, popisuje cílový stav a podle něj se
programuje. Kreslit mockup až po něm znamená dohánět návrhem to, co už je napsané slovy,
a slova o vzhledu nesou vždycky míň než obrázek. Levná je změna jedině dokud je to CSS
v mockupu.

Co pod pravidlo **nespadá**: srovnat aplikaci s tím, co v mockupu **už nakreslené je**
(#283). Tam se návrh nemění, takže není co schvalovat — jde se rovnou. Naopak nová
obrazovka, sekce nastavení nebo tlačítko, které v mockupu není (#281), znamená napřed
mockup.

Jak se s artifactem pracuje — čtení CSS, aktualizace na tutéž adresu, render vedle
screenshotu — je v [`docs/navrh.md`](docs/navrh.md).

## Rozhodování

**Návrhová rozhodnutí děláš sám.** Neptej se na potvrzení u každého detailu — kde žije
kontrola, kam patří složka, jaký stav blokuje, jak se jmenuje typ. Rozhodni, implementuj
a **zapiš rozhodnutí i s důvodem** do specifikace. Záznam rozhodnutí je to, co dovoluje
pozdější korekci: je z něj vidět, proč je to tak, a proto se to dá vědomě změnit.

Je to osobní nástroj. Rychleji se posoudí na běžící aplikaci než v návrhu, takže se
rozhodnutí koriguje podle toho, jak se appka chová — ne debatou předem.

**Žádná schvalovací brána na návrh.** Nepředkládej návrh a nečekej na „ano“ — ani když si
to vynucuje skill (typicky `superpowers:brainstorming` se svým hard gate). V tomhle repu
to pravidlo neplatí: rozhodnutí zapiš do specifikace a rovnou implementuj. Tohle je
výslovná uživatelská instrukce, a ta má přednost před skillem. Průzkum a rozmyšlení
z brainstormingu si nech, schvalovací krok zahoď.

**Jedinou výjimkou je vzhled** (viz *Návrh (mockup)* výš): co mění obrazovku nebo na ni
něco přidává, se kreslí do mockupu a schvaluje **dřív, než na to vůbec vznikne issue**.
Neruší to pravidlo o řádek výš — schvaluje se **obrázek**, ne návrh implementace.

Když na něco narazíš, co návrh v issue mění (zjistíš, že to nejde, jak je napsané),
**není to důvod se ptát** — rozhodni, zapiš do specifikace **co se změnilo a proč**,
a napiš to do popisu PR. Posoudí se to nad diffem.

Ptát se dál na **tvrdé podmínky** níž. Merge PR ani zavření issue mezi ně **nepatří** —
to si od 2026-08-01 řídíš sám
([proč](docs/superpowers/specs/2026-07-31-prism-design.md#merge-pr-a-zavření-issue-si-claude-řídí-sám-od-2026-08-01)).

## Tvrdé podmínky

Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav se a zeptej se.

1. **Jediná cesta ven** (od #67; do té doby tu stálo „nikdy nic neposílat na GitHub“).
   Aplikace **umí** odeslat review, od #73 se **ozvat do vlákna**, od #216 **napsat komentář
   pod PR**, od #392 **přeštítkovat svůj PR a vyžádat na něm review**, od #413 **založit
   label, který repozitář ještě nezná** a od #465 **mergnout vlastní PR** — ale jedině přes
   `ReviewPublishing`, jedině na výslovný pokyn člověka a jedině tam, kde se to **v nastavení
   povolilo**. Pravidlo se skládá z šesti věcí a každá z nich je kontrolovatelná:

   1. **`GitHubGateway` zůstává bez zápisových metod.** Polling, diff, checkout ani reviewer
      tedy nemají čím něco odeslat — read-only je pořád vidět z typu.
   2. **`grep ReviewPublishing App/` vyjmenuje všechna místa, odkud to jde.** Mají to být
      **sedm souborů a pět volajících**: protokol, `GhReviewPublisher` (implementace),
      `ReviewSubmission.send()` (review), `ThreadSubmission` (odpověď a vyřešení vlákna),
      `CommentSubmission` (komentář pod PR), `MetadataSubmission` (labely a vyžádání
      reviewera) a `MergeSubmission` (merge). Všechny leží v `App/Publish/` — volající
      **mimo** tu složku by znamenal, že cesta ven vede odjinud než z jednoho místa.

      Protokol má **osm vyjmenovaných metod** — `submit`, `reply`, `setResolved`, `comment`,
      `setLabels`, `requestReviewers`, `createLabel`, `merge`. Do #73 měl jednu a stálo tu, že
      cokoli dalšího by byla druhá cesta ven; do #216 tři, do #392 čtyři, do #413 šest, do
      #465 sedm. Výčet je krátký, vyjmenovaný na jednom místě a **každá metoda si sama ověří
      bránu z bodu 6** — proto všechny berou adresu, ze které se pozná repo.

      **Zakázané zůstává**: approve mimo review, **zavření PR**, **milník**
      a **`deleteLabel`** — smazaný label zmizí ze **všech** issues a PR, na kterých leží,
      a aplikace tu ztrátu neumí ani ukázat; mazat i přebarvovat se chodí na GitHub.
      **`merge` z toho zákazu u #465 vypadl** a je to vědomá změna pravidla, ne díra: mergnout
      vlastní PR, když je zeleno, je poslední věc, kvůli které se od hotového review odskakuje
      do prohlížeče, a je to tatáž třída jako labely — práce s **vlastní** frontou. Platí se za
      to dvěma věcmi navíc, které ostatní metody nemají: **potvrzením s úplným výpisem** (jako
      u review, #68) a **hlavou v payloadu** (`sha`), na kterou GitHub odpoví `409`, když se
      větev mezitím pohnula.
      **Od #333 to hlídá test, ne jen tenhle grep** (`SingleWayOutTests` — sedm souborů, osm
      metod, jmenovitě i ty čtyři zakázané, a že soubory zadání pro agenta nezná publisher,
      payload, API ani podproces). **Měnit se smí jedině na vlastním PR**
      (`Policy.metadataEditing`, u merge `Policy.mergeOffer`); na cizím se akce **nekreslí
      vůbec**, ne zašedle — zašedlá
      s důvodem **napsaným v panelu** patří jedině tam, kde se stav **mění** (vypnutá brána,
      červený check, větev pozadu). Proč se ten výčet
      rozšiřoval, je v [`docs/architektura.md`](docs/architektura.md#reviewpublisher-apppublish)
      — [#392](docs/architektura.md#labely-a-vyžádání-reviewera-392--pátá-a-šestá-metoda),
      [#413](docs/architektura.md#založení-labelu-413--sedmá-metoda-a-první-která-píše-do-repozitáře),
      [#465](docs/architektura.md#merge-vlastního-pr-465--osmá-metoda-a-první-která-mění-main).
   3. **Publisher není pole `AppStore`.** Vzniká uvnitř té cesty, která odesílá, a zaniká
      s ní — drží ho `ReviewSubmission`, `ThreadSubmission`, `CommentSubmission`,
      `MetadataSubmission` a `MergeSubmission`. `AppStore` si kvůli odesílání drží **jen cestu
      ke `gh`**, ne publisher ani továrnu na něj (proto ho ten grep nevypíše); u vláken,
      komentářů a labelů drží **stav** (`ThreadActionState`, `CommentActionState`,
      `MetadataActionState`), ne cestu ven. **Merge stav ve store nemá vůbec**: sheet ho drží
      celý (`MergeSubmission` v `@State` okna, jako u review), protože je to jedno potvrzení,
      které vzniká kliknutím a zaniká zavřením.
   4. **Odeslání review si žádá hotový draft s `headSha`** a pre-flight ověří, že je to pořád
      hlava PR — approve na kód, který jsi neviděl, tak nejde poslat ani závodem s pushnutým
      commitem (GitHub proti tomu **nechrání**, změřeno u #62). **U odpovědi do vlákna,
      u komentáře pod PR a u labelů s reviewery se `headSha` neověřuje** (#73, #216, #392),
      protože se to všechno váže na PR nebo na diskuzi, ne na commit; ověřuje se **stav PR**,
      a to i **striktněji než GitHub** (změřeno u #73, že odpověď na zavřeném PR projde).
      **U merge se hlava ověřuje, a dvakrát** (#465): v pre-flightu jako u review, a k tomu se
      posílá **v payloadu** (`sha`) — pro GitHub je to podmínka, takže na commit pushnutý mezi
      pre-flightem a voláním odpoví `409` a nemergne nic (změřeno na
      `prism-review-sandbox#8`). Je to jediná cesta ven, která má proti závodu dvě pojistky,
      a je to schválně: merge se týká `main`u, ne jen pull requestu.
   5. **Jedno atomické volání.** Buď odejde všechno, nebo nic (změřeno u #62). U vláken
      a komentářů triviálně; **u labelů to drží tvar payloadu** (#392) — `PUT
      /issues/{n}/labels` sadu **nahrazuje**, takže se posílá celá a jedním voláním a skládá ji
      `Policy.toggledLabels`, ne publisher. **Pro `Založit a přidat` to neplatí, a je to vědomá
      výjimka** (#413): dvě volání, mezi nimi stav *label v repozitáři je, na PR není*. Platí se
      **viditelností** — `MetadataActionState.createdNotAdded(name:error:)` místo `failed`,
      zápis založeného labelu do nabídky ještě před druhým voláním, `dvě volání` v patce
      potvrzení a `isBusy` mezi nimi
      ([rozbor](docs/architektura.md#založení-labelu-413--sedmá-metoda-a-první-která-píše-do-repozitáře)).
   6. **Jen tam, kde se to povolilo** — `PublishScope`, složený z `Configuration`
      (`allowsPublishing` globálně i per repo). **Výchozí stav je vypnuto**, a právě to drží
      vlastnost „samo nic neodejde“. Sandbox v tom **není výjimka v kódu**. Do #107 tu stál
      zadrátovaný seznam s jediným sandboxem; proč se to změnilo, je v [záznamu
      rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí-1).

   **Otevřít session v uživatelově terminálu (#453) devátou cestou ven není**, a je to hranice, ne
   výjimka: terminál je **mimo aplikaci** — totéž, jako když si člověk `claude --resume` vlepí
   sám. Uvnitř okna žádný terminál nevzniká, `TerminalOpening` nemá čím na GitHub sáhnout
   a `grep ReviewPublishing App/` vypisuje týž seznam. **Od #460 to `▶` nepoužívá** (míří do
   zásuvky) a ta cesta se drží **bez volajícího, jako záloha**; kdy a s čím jde ven, je
   v [záznamu rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#osud-applescriptterminal-460).

   **Od #459 je terminál i uvnitř okna, a je to vědomá změna téhle podmínky** — ne její obejití.
   Do #459 tu stálo, že vestavěný terminál je **zamítnutý**, protože by nešel uhlídat testem.
   Uživatel si ho vyžádal jmenovitě a rozhodl, že se ta záruka vymění za to, že se od review
   nemusí odcházet z okna. Co z podmínky **zůstává** a co z ní **padá**, je potřeba číst spolu:

   - **Zůstává**, že aplikace **sama** nic neodesílá a `ReviewPublishing` je jediná cesta ven
     **v jejím kódu**. `grep ReviewPublishing App/` vypisuje **týž seznam** (od #465 sedm souborů
     a pět volajících) a `SingleWayOutTests` prochází **beze změny** — na ně se nesahalo.
     `TerminalHosting` nemá zápisovou metodu a nezná `gh`.
   - **Padá**, že se ta záruka dá **dokázat testem**. Ze shellu jde `gh pr merge` i `git push`
     a žádná stráž na to nedosáhne, protože ta cesta nevede přes kód aplikace. Plnou moc má odsud
     **člověk**, ne aplikace.
   - **Musí to být vidět na obrazovce, ne jen tady**: v hlavičce zásuvky stojí kapsle
     `plná práva`, protějšek `čte · neodesílá` z tabu `Zeptat se`.
   - **Tvrdá podmínka č. 3 platí beze změny**: shell startuje v cache aplikace (pracovní strom
     review, nebo bare klon), nikdy v uživatelově klonu.
   - **Od #460 do toho shellu píše i aplikace, a je to jedna řádka** (`TerminalHosting.run`,
     `▶` v tabu `Průběh`): `cd '<strom>' && claude --resume <id> --permission-mode auto`, skládaná
     `Policy.drawerResumeCommand(sessionID:)` a `ShellQuoting` — **tedy text, který kopíruje `⧉`,
     a k němu režim povolení** (zdůvodnění o kus níž), a jinou aplikace poslat neumí. Do běžícího jobu se přitom **nepíše vůbec**
     (`hasForegroundJob`), protože řádka je pro něj vstup; místo toho se na tu relaci **přepne**.
     Plnou moc má dál **člověk**: cokoli jiného než tuhle jednu řádku napíše jedině on.
   - **Od #478 posílá aplikace do pty ještě jednu věc, a druhá řádka to není: hlášení myši.**
     Kolečko, které `SwiftTerm` aplikaci v terminálu nepředá sám. Obsah je
     `ESC[<64;<sloupec>;<řádek>M` a skládá se **jen** z čísla tlačítka a buňky pod kurzorem, takže
     z něj text ani příkaz vzniknout nemůže. Odejde jedině tehdy, když si o hlášení myši řekla
     aplikace v terminálu (`mouseMode != .off`) **a** člověk otočil kolečkem.
   - **A relací je v zásuvce víc než jedna** (#460), takže úklid z bodů výš platí **pro každou**:
     `stopTerminals(for:)` při zavření záložky, `stopAllTerminals()` při ukončení aplikace
     a značka v `sessions.json` u každé zvlášť — jinak po zabité aplikaci osiří zrovna ta, která
     nebyla vidět. Počet je proto **omezený** (`Policy.maxTerminalSlots`, pět) a vytlačuje se
     jedině **neběžící** relace; když všechny běží, nová **nevznikne** a řekne se to.

   Podrobnosti — proč zásuvka a ne záložka, proč `SwiftTerm` a proč zrovna verze 1.11.2, jak se
   ten proces zabíjí a co je proti návrhu jinak — jsou
   v [`docs/architektura.md`](docs/architektura.md#vestavěný-terminál-459)
   a v [záznamu rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--vestavěný-terminál-jako-zásuvka-459).

   **Merge z panelu (#465) je proti tomu ta druhá, hlídaná strana**: jde přes protokol, přes bránu
   a s potvrzením, takže se o něm dá tvrdit test. Že aplikace umí mergnout, přitom **není argument
   pro to, aby uměla spustit `git push` sama** — to je #466 a řeší se vlastní cestou s guardem;
   a že to jde ze zásuvky, je moc **člověka**, ne aplikace.

   Co se **nezměnilo**: `ReviewVerdict` je pořád jen návrh a sám nic neodesílá (od #114 se jím
   **předvyplňuje** verdikt v panelu, ale odejít umí jedině touž cestou). „Výslovný pokyn
   člověka“ vypadá takhle: **potvrzovací sheet u review a u merge** (dvě kliknutí, celý payload
   vidět — #68, #465; u merge je v něm navíc napsané, co v tom výpisu **není**, protože tělo
   squash commitu skládá GitHub ze slévaných commitů); **odpověď do vlákna, komentář pod PR ani
   label se nepotvrzují** (#73, #216,
   #392 — jedno pojmenované tlačítko); **u vyžádání reviewera je potvrzení v nadpisu nabídky**
   (`Vyžádat review od`), protože request se odebráním nedá vzít zpět; **založení labelu
   potvrzení má** (#413) na **druhé obrazovce téhož popoveru, ne v sheetu**, a **bez výchozí
   akce**. **Uzavřený je `seznam`** — hledání **filtruje, nezakládá**; zakládání je **akce pod
   děličem** se zkratkou **`⌥↵`** na poli, barvu vybírá aplikace (`Policy.labelColor`)
   a **přebarvit ani smazat label odsud nejde**. A composer komentáře **nesmí splynout s tabem
   `Moje review`**. Proč zrovna takhle, je
   v [`docs/architektura.md`](docs/architektura.md#labely-a-reviewery-v-panelu-392).
   **U merge tlačítko výchozí akci nemá** (ani `Enter`), **metoda je jedna** (`squash`, z jedné
   konstanty, kterou čte payload i potvrzení) a **po úspěchu se zavře sheet i záložka toho PR**
   — jedině po úspěchu: po `409`, `405` nebo spadlé síti zůstává obojí i s hláškou, jinak by ji
   nebylo kde ukázat. Pravidlo, že **mergnutý PR jde ještě dočíst a zavřít ho má člověk, ne tik
   pollingu**, se tím **neruší** — mluví o pollingu, kdežto tady záložku zavírá klik na
   `Mergnout`.
2. **Reviewer je read-only.** V `--allowedTools` není `Write` ani `Edit`, u `Bash` se uvádí
   jen `git` — a v `--disallowedTools` jsou `Bash(gh:*)` a `Bash(git push:*)`. `Skill` mezi
   povolenými je (#78); sám o sobě nic nespouští, ale skill, který se přes něj načte, si
   o odeslání na GitHub umí říct — proto ten zákaz.

   Tři věci ověřené spuštěním (#12, **opraveno u #17**;
   [`docs/claude-cli.md`](docs/claude-cli.md)):

   - Co je **mimo** povolený vzor, se odmítne, pokud to není na vestavěném seznamu čtecích
     příkazů. `ls` a `cat` projdou, `gh` ne.
   - Co je **uvnitř** vzoru, projde celé — `Bash(git:*)` tedy pouští i `git push`. **Zavírá to
     až `--disallowedTools`**, který povolení přebíjí a zabere i na `git push` s vypsanou URL.
   - `Write`, `Edit` ani `Bash` z init eventu nezmizí, ať je v povoleních cokoli — seznam
     nástrojů není obraz oprávnění.

   Odmítnutý nástroj **není chyba běhu**: session pokračuje a skončí `success`, odmítnutí je
   vidět v `permission_denials`.

   **Session z `▶` v zásuvce pod tuhle podmínku nespadá, a je to hranice, ne výjimka** (#460).
   Podmínka mluví o session, které **pouští aplikace** — reviewer, kontrola nálezů, překlad,
   dotažení textu issue, `Zeptat se` —, a jejich vyjmenované sady se **nemění ani o položku**.
   `claude --resume` v zásuvce je proti tomu session, kterou **řídí člověk ve svém shellu**: běží
   s `--permission-mode auto`, aby nepřerušovala práci dotazem u každého kroku. **Nová práva to
   nedává** — zásuvka je plnohodnotný shell s kapslí `plná práva`, takže cokoli, co ta session
   udělá, si tam člověk může napsat sám; odpadají **dotazy**, ne hranice. Vybraný je `auto`
   schválně: z šesti režimů `--permission-mode` je jediný, který má **vyjmenovaná a čitelná
   pravidla** (`claude auto-mode defaults` vypíše `allow`, `soft_deny` i `hard_deny`).
   **`bypassPermissions` ani `--dangerously-skip-permissions` v tomhle repu nemají co dělat**
   a `⧉` režim povolení **nedostane** — kdo si příkaz kopíruje jinam, dostane ho tak, jak by ho
   psal. Rozhoduje `Policy.drawerResumeCommand(sessionID:)`
   ([záznam rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#auto-mode-v-zásuvce-460)).

   **A od #460 aplikace zapisuje do konfigurace cizího nástroje** (`~/.claude.json`,
   `WorkspaceTrusting`) — jedinou hodnotu, **důvěru ke složkám vlastní cache**, aby se interaktivní
   `claude` neptal na důvěru u každého nového pracovního stromu. Je to postup, na který odkazuje
   sám `claude` ve své binárce, a hranice u něj drží tři věci: **na soubor, kterému nerozumí,
   nesáhne** (rozbitá cizí konfigurace by byla ztráta cizí práce, kdežto neúspěch stojí jeden
   dialog navíc a **je vidět sám**), **zapisuje atomicky a zachová, co v souboru je**, a **zapisuje
   jen když je potřeba** — zapsané `true` se nepřepisuje, takže běžný případ je čisté čtení.

   **Od #479 to není jen kořen cache, ale i ta složka, ve které shell doopravdy stojí** (pracovní
   strom review, nebo bare klon; výčet vydá `Policy.workspacesToTrust`). Důvěra se z předka sice
   dědí, ale **ne do git pracovního stromu** — a strom review je přesně to, kam `▶` míří. Zapsané
   `false` **na naší cestě** se u toho přepsat **smí**: zakládá si ho `claude` sám, není to odpověď
   člověka. Zapisovaná cesta tím ale přestala být konstanta, takže **hranici cache drží od #479
   kontrola** (`CacheFile.isInsideCache`, tedy totéž místo jako zbytek repa) — tvrdá podmínka č. 3
   se tím nemění, jen se z konstrukce stala ověřená vlastnost. Podrobnosti a to, co se změřilo —
   včetně **vyvrácené** hypotézy, že `false` přebíjí zděděné `true` —, jsou
   v [`docs/claude-cli.md`](docs/claude-cli.md).

   Co na téhle podmínce **nic nemění**, a proč: **kontrola nálezů z minula** (#150) má vlastní
   prompt, ale bere **tytéž konstanty** `ClaudeCommand.allowedTools` a `disallowedTools`
   a předchozí nálezy dostane jako materiál v promptu, ne jako nástroj
   ([rozbor](docs/architektura.md#kontrola-nálezů-z-minula-150)); **zadání pro reviewera**
   (#120) jde do promptu jako **cesta k souboru**, takže stačí `Read`
   ([rozbor](docs/architektura.md#zadání-pro-reviewera-120)); **editovatelný prompt review**
   (#281) otevřel **prompt, ne povolení** — šablona skončí v jednom argumentu za `-p` a nic
   v ní nedokáže nástroj povolit (je na to test). A **dotažení textu issue** (#345) je
   **vlastní session**, ne rozšíření revieweera: má svou, taky vyjmenovanou sadu — `ToolSearch`
   a **jeden čtecí MCP nástroj**, jehož jméno je v konfiguraci (`issueTextTool`) —, tytéž
   zákazy z `ClaudeCommand.disallowedTools`, a v povoleních není `Write`, `Edit`, `Bash`,
   `ReportFindings` ani `Skill`. `ToolSearch` v ní být **musí**, bez něj se MCP nástroj nedá
   zavolat ([rozbor](docs/architektura.md#text-issue-a-komentáře-pod-pr-345)). A **rozhovor nad PR**
   (#452, tab `Zeptat se`) je **třetí vyjmenovaná session** se sadou **užší než reviewerova**:
   `Read,Grep,Glob,Bash(git:*)`, tedy **bez `ReportFindings`** (nemá co hlásit) a **bez `Skill`**
   (skill načtený za běhu si umí říct o odeslání na GitHub), se **stejnou** konstantou
   `ClaudeCommand.disallowedTools`. Obě hodnoty tvrdí test **literálem**, jako u #345. Kontext
   (nálezy, konverzace, checky) jde do promptu **cestou k souboru** vedle pracovního stromu, ne jako
   nástroj — precedens #120; diff si session přečte `git diff <base>...HEAD`
   ([rozbor](docs/architektura.md#rozhovor-nad-pr--tab-zeptat-se-452)).
3. **Nikdy nesahat na uživatelovy klony.** Aplikace pracuje výhradně ve své cache
   (`~/Library/Application Support/PRism/`). Mohou být rozdělané, na jiné branchi,
   mít vlastní worktrees.
4. **Aplikace nikdy nedrží GitHub token.** Autentizace je delegovaná na `gh`.
5. **Nálezy jsou klíčované `headSha`.** Nové commity nálezy zneplatní (stav
   „zastaralé“), nikdy se nesmí tiše zobrazovat proti kódu, který už neexistuje.

   **Rozhovor nad PR (#452) se tomuhle netýká, a je to zapsaná výjimka**: ukládá se **k PR, ne
   k `headSha`**, protože rozhovor není nález — otázka „proč se ten mutex bere“ pushem nezastará.
   Podmínka mluví o nálezech, tedy o tvrzení proti kódu.

   **Kontrola nálezů (#150) na tom stojí, ne obchází to**: nese `againstHeadSha` — hlavu, proti
   které běžela —, a jak se hlava posune, `Policy.recheck(of:head:)` odznaky nevydá. „Vyřešeno“
   přitom nikdy nález nesundá, to smí jedině odmítnutí (#113) — a od odmítnutí se musí poznat
   **i pohledem**: přeškrtne se jen text nálezu (ne celý řádek) a `blokuje` u něj zůstává
   ([rozbor](docs/architektura.md#kontrola-nálezů-z-minula-150)).

## Architektura

Devět modulů. Pět, které sahají do vnějšího světa, je za protokolem, aby byly v testech
nahraditelné fake implementací. Osmý (`ReviewPublisher`, #67) je jediný, který **zapisuje** —
viz tvrdá podmínka č. 1. Devátý (`TerminalHost`, #459) je jediný, ve kterém **plnou moc má
člověk**, ne aplikace — tamtéž.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a syrový diff — celý, nebo mezi dvěma commity (#284) —, login přihlášeného účtu (#330), labely s vyžádanými reviewery včetně týmů (#392), od #420 **hlavy víc PR jedním dotazem** a od #465 **slévatelnost větve** (líné pole, ptá se opakovaně). **Pořád bez zápisu** | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings` a odpovědi na pokusy o nástroje (#326). Od #150 dvě podoby běhu — review a kontrola nálezů z minula. Vedle nich tři session, které o review nic nevědí: překlad nálezů, dotažení textu issue (#345) a **rozhovor nad PR** (#452, vlastní užší sada nástrojů a `--resume`). Od #327 umí transcript session i **přepsat k přečtení** | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Každé rozhodnutí, které jde vyjádřit nad daty: stav řádku, blokující příznak, návrh verdiktu, řazení, filtr seznamu, hledání v paletě ⌘K, složení promptu i zadání pro agenta, obsah dashboardu a dění, geometrie, na kterou se ptá kresba, a **desítky dalších**. Úplný katalog s důvody je v [`docs/architektura.md`](docs/architektura.md#policy-apppolicy) — hledej tam podle jména funkce | — |
| `Config` | Globální default + override per repo, tolerantní čtení `config.json` | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu. **Stav v `AppStore.swift`, metody v `AppStore+*.swift`** (#154) | — |
| `ReviewPublisher` | **Jediná cesta ven**: odeslat review, odpovědět do vlákna, přepnout jeho vyřešení, napsat komentář pod PR, od #392 nastavit labely a vyžádat review na **vlastním** PR, od #413 **založit label v repozitáři** a od #465 **mergnout vlastní PR** | `gh` CLI |
| `TerminalHost` | Vestavěný terminál (#459) — od #460 **víc relací na pull request** (`TerminalSlot`: holý shell a jedna na dráhu), každá vlastní pty v checkoutu toho PR, VT emulace (`SwiftTerm`), fokus pro ustupující zkratky a `SIGKILL` na popředí pty **u každé z nich**. Umí do relace napsat **jednu řádku** (`▶`), a jen tehdy, když v ní nic neběží; od #478 **předá kolečko** aplikaci, která si o hlášení myši řekla. Na GitHub nesahá a `gh` nezná; plnou moc v něm má **člověk** | login shell přes pty |

Nad tím SwiftUI views: `PRList`, `DiffView`, `ReviewPanel`. Mimo tuhle devítku stojí
`App/Diff/` — překlad diffu na model a jeho řádky. Není to modul: v doméně review nemá
diff jinou roli než být vidět. Totéž platí o `App/Health/` (#31).

**Kam co psát:** rozhodovací logika patří do `Policy` jako čistá funkce — tam se testuje
bez mockování. Když se přistihneš, že píšeš `if` nad nálezy někde ve view nebo v runneru,
patří to do `Policy`.

Co který modul drží a co se u něj nemá rozbít, je v
[`docs/architektura.md`](docs/architektura.md) — sekce na modul, ve stejném pořadí jako
tabulka výš. **Tenhle soubor musí stačit k tomu, abys věděl, kam sáhnout**; tam se jde pro
podrobnosti. Zvlášť stojí za přečtení, než sáhneš na:

- **[modely](docs/architektura.md#doménové-modely-appmodels)** — tři různé „jazyky“ a tři různá
  „review“ se nesmí slít, `ReviewState` rozlišuje chybové stavy schválně;
- **[`AppStore` a okno](docs/architektura.md#appstore-appstore-a-okno-appviews)** — store je
  rozdělený na `extension` po zodpovědnostech (#154), takže se hledá podle souboru:
  `AppStore.swift` drží **stav, init a polling**, metody jsou v `AppStore+*.swift`. **Dělí se
  metody, ne data.** Patří sem i to, co patří do store a co do view (`@State` v detailu PR
  přetéká mezi pull requesty) a proč se stav checkoutu klíčuje repem;
- **`pullRequests` je plný seznam, `visiblePullRequests` je po filtru** (#117), a **rozdíl mezi
  těmi dvěma gettery je jediné, co dělí filtr od mazání cache**. Nad tím jsou od #332 dvě další
  zúžení podle autora: `queuePullRequests` (cizí, tedy fronta) a vlastní PR z #331. Fronta,
  karty `Čeká na mě` a `Blokuje`, souhrn, automat, hromadné spuštění a notifikace čtou **jen
  cizí**; úklid, eviction, nastavení, nabídka filtru a rozdělaná review **obojí**
  ([tabulka](docs/architektura.md#které-místo-chce-kterou-množinu-332));
- **[`Environment`](docs/architektura.md#vrstva-environment-appenvironment)** — podprocesy:
  blokující I/O nesmí na kooperativní pool, oba pipy se musí číst souběžně, **zrušení
  i ukončení aplikace musí proces zabít** (#264 — obě cesty, jedním `SIGKILL`em; zavírání se
  na něj musí **počkat**). **Ta záruka kryje jen normální ukončení** (#351): aplikaci zabitou
  zvenčí nemá kde spustit úklid a `claude -p` přejde pod `launchd`, takže se běžící session
  **zapisují do cache** (`sessions.json`) a osiřelé zabije **další start** — rozpoznání jedině
  přes zapsanou identitu `(pid, startedAt)` a **jen když vlastník už neběží**, nikdy hledáním
  v `ps` ([rozbor](docs/architektura.md#osiřelá-session-po-zabité-aplikaci-351)).

## Konvence

- **Krátké, jednoúčelové metody.** Čitelnost před chytrostí.
- **Nepoužívat `final`** u typů, které se v testech nahrazují.
- **Protokol + fake, ne mockovací framework**, u tří modulů se vnějším světem — a stejně
  u `Environment`, kde jsou za protokolem `ExecutableProbe`, `ProcessRunning`
  a `ShellPathReading`.
- **Nové soubory drž malé a soustředěné.** Když soubor roste, obvykle dělá víc věcí.
- **Do `project.pbxproj` nesahej.** `App/` a `Tests/` jsou buildable folders
  (`PBXFileSystemSynchronizedRootGroup`) — soubory i podsložky se do targetu berou
  z filesystému, nový zdroják = jen ho vytvořit. Editovat pbxproj je potřeba jen při změně
  targetů nebo build settings. **Tři výjimky**: `Signing.xcconfig` (xcconfig se dá napojit jen
  odkazem přes `baseConfigurationReference`), `ASSETCATALOG_COMPILER_APPICON_NAME` (#83 —
  build setting, leží na **app targetu**, ne na projektu) a od #459 **`SwiftTerm`** (balíček se
  jinak než přes `packageReferences` nepřipojí; `Package.resolved` je v repu, aby pin nikam
  neutekl); `App/Assets.xcassets` se v pbxproj **nevyjmenovává**. A **dva zdrojáky se stejným jménem build položí** (#184), i když leží
  v různých podsložkách — jméno souboru je v jednom targetu klíč (`Multiple commands produce …
  <Jméno>.stringsdata`), takže se pojmenovávají **jednoznačně napříč celým `App/`** (a `Tests/`).
- **Co se počítá při každém překreslení, se pamatuje — a cache si musí říct, co ji vyprazdňuje**
  (#224). Obarvení řádku se volalo z computed property, takže běželo i při přejezdu myší: 44 ms
  na soubor o 2400 řádcích, z cache 0,30 ms. Hranice musí být v tom typu vidět (`SyntaxRunCache`:
  strop na počet řádků i na jejich objem, po překročení se zahodí celá) — cache bez vyjmenované
  meze je únik paměti s odkladem. **A do cache smí jen to, co je funkcí jejího klíče** (#153):
  `SyntaxRunCache` je klíčovaná `(text řádku, jazyk)`, takže word-level zvýraznění, které závisí
  na **protějšku** dvojice, do ní nepatří — vracela by zvýraznění cizí dvojice, a potichu.
  Takové věci se kreslí jako **druhá vrstva nad** výsledkem z cache
  ([rozbor](docs/architektura.md#appsyntax)).
- **Zlevnění, které práci jen přesune jinam, není zlevnění — a pozná se to jedině změřením obou
  konců** (#275). **Měř tu cestu, kterou kód doopravdy jde**, a co se nepodařilo zlevnit, napiš
  i s důvodem: bez toho to příště někdo zkusí znovu
  ([měření](docs/testovani.md#jak-změřit-projíždění-diffu-když-se-ho-nedá-dotknout-252)).
- **Řádky dělí `TextLines`, nikdy `split(separator: "\n")` ani `components(separatedBy: .newlines)`**
  (#292, na jedno místo svedeno #295). `"\r\n"` je ve Swiftu **jeden `Character`**, takže
  `split(separator: "\n")` na `CRLF` **nerozdělí vůbec**; ta druhá cesta dělí po skalárech,
  takže `CRLF` jsou pro ni dva oddělovače a vloží mezi ně prázdný řádek. Platí to na
  **všechno, co zakončení řádků nevybírá aplikace**: hlavičky, logy z CI, diffy a obsah souborů
  z cizích repozitářů. Výjimka je `String.singleLine`, a to **schválně**: sráží cizí text do
  popisku, takže potřebuje širší `isNewline` (grep ji nechytá, dělí přes `whereSeparator`).
  A **kdo text dělí na dvě části, dělí obě na tomtéž znaku** (#339) — tohle grep nechytá vůbec.
  Zdůvodnění obojího je u `Character.isLineTerminator` a v
  [`docs/architektura.md`](docs/architektura.md#textlines--co-je-řádek-295).

  ```bash
  grep -rn 'split(separator: "\\n"\|separatedBy: .newlines' App | grep -vE ':[0-9]+: *//'
  ```

  A **fixture takového formátu musí být skutečný výstup** — ruční literál nese `LF` toho, kdo ho
  napsal, takže test zezelená i nad rozbitým rozborem; když na `CRLF` stojí, patří do
  `.gitattributes` jako `-text`. **Doklad je ale blob, ne řádek v `.gitattributes`** (#353):
  `-text` přidané *až po* zapsání souboru do indexu se na tu položku zpětně neuplatní. Ověřuje
  se `git cat-file -p <ref>:<cesta>` — před commitem nad `:<cesta>` a po pushi nad
  `origin/<branch>` ([postup](docs/testovani.md)).
- **V shell skriptech se proměnná v české próze píše `${VAR}`.** Uvozovka „ hned za
  `$VAR` shodí bash 3.2 (ten je v `/bin/bash`) v UTF-8 locale na `unbound variable`: její
  byty se počítají do jména proměnné. Chytí to `set -u`, ale až za běhu — `bash -n` ne.
  Grep na ten vzor: `grep -nP '\$\{?[A-Za-z_][A-Za-z_0-9]*[^\x00-\x7F]' bin/*.sh`.
- **`| grep -q` se ve skriptu s `pipefail` nesmí použít jako podmínka.** `grep -q` po první
  shodě zavře rouru, producent dostane SIGPIPE a `pipefail` z toho udělá návratový kód
  141 — takže podmínka vyjde **nepravdivě právě tehdy, když shoda je**. Výstup se čte do
  proměnné a porovná `case`em. Stálo to mrtvou kontrolu ad-hoc podpisu v `bin/run.sh` (#61).
  Kontrolu, která má něco hlásit jen výjimečně, je proto potřeba **spustit i v tom výjimečném
  stavu** — jinak je „nic nevypsala“ k nerozeznání od „funguje“.
- **Uživatelské texty jsou české a bundle to musí vědět.** `Info.plist` deklaruje
  `CFBundleDevelopmentRegion = cs` a `CFBundleLocalizations = [cs]`. Bez toho spadne
  `Locale.current` na vývojový jazyk a formátované hodnoty (relativní časy, čísla) vyjdou
  anglicky vedle českých popisků.
- **Do `App/` patří jen zdrojáky.** Buildable folder zkopíruje všechno, co neumí
  zkompilovat, do `.app` jako resource — `Info.plist` uvnitř `App/` skončil v bundlu
  dvakrát, podruhé s nerozexpandovanými `$(...)`. Konfigurace bundle (`Info.plist`,
  `PRism.entitlements`) proto leží v kořeni repa.
- **Jeden název všude: `PRism`.** Repo, projekt, target, scheme, produkt, Swiftový modul
  i to, co appka ukazuje v Docku. Když název měníš, projdi i `PRODUCT_MODULE_NAME`,
  `TEST_HOST`, `CODE_SIGN_ENTITLEMENTS` a `bin/run.sh` — jinak build projde, ale spadne
  až test nebo spuštění.
- **Ikona potřebuje `CFBundleIconName` v `Info.plist` napsané ručně.** Xcode ho generuje
  z `ASSETCATALOG_COMPILER_APPICON_NAME`, ale jen když si plist generuje sám — a tady je
  vlastní (`GENERATE_INFOPLIST_FILE = NO`). Bez toho klíče se ikona **zkompiluje** a v bundlu
  leží, jen ji systém nenajde a v Docku zůstane prázdný obdélník. A **po překreslení ikony se
  musí restartovat Dock** (`killall Dock`) — cache ikon je vázaná na cestu k `.app`, která se
  rebuildem nemění. **`CFBundleName` navíc nejde nastavit přes `INFOPLIST_KEY_*`** (Xcode ho
  generuje z `PRODUCT_NAME` a klíč tiše ignoruje), proto má projekt vlastní `Info.plist` místo
  `GENERATE_INFOPLIST_FILE`.
- **Moduly jsou složky, ne targety.** Všechen kód žije v jednom app targetu; `Policy`
  a spol. jsou podsložky `App/`. Framework by si vynutil `public` u všeho, co používá
  UI — daň, kterou osobní aplikace nepotřebuje. Vyčlenit se dá později.
- Chybové stavy jsou v návrhu vyjmenované ([specifikace, *Chování při
  chybách*](docs/superpowers/specs/2026-07-31-prism-design.md#chování-při-chybách))
  — každý z nich má mít v UI vlastní rozlišitelný stav. `čisté` (žádné nálezy) a
  `failed` (session spadla) se nesmí slít do jednoho — a od #383 je mezi nimi **třetí**:
  `inconclusive` (doběhlo, ale čisto z toho neplyne — reviewer nepřečetl kód, nenahlásil
  nálezy, nebo se část ztratila). Rozhoduje o něm `Policy.inconclusiveReason(of:)`, což je
  **jediné místo** — a když se ptáš, jestli běh kód doopravdy otevřel, tak
  `Policy.codeReading(of:)`, kde `unknown` je odpověď, ne slabší „nepřečetl“.

### Kresba, rozvržení a výkon v okně

Každé pravidlo níž vzniklo z **naměřeného** tuhnoucího okna nebo z rozbité kresby. Co přesně se
měřilo, co se zamítlo a co se ukázalo jako slepá ulička, je za odkazem — a **přečti si to dřív,
než pravidlo obejdeš**, protože většina z nich se v harnessu neprojeví.

- **Rozměr se nenechává vyjednávat, když se dá spočítat** (#220): `frame(maxWidth: .infinity)`
  stojí **~5,5× na úroveň** zanoření, takže se šířka **předává** (`availableWidth`,
  `narrowingWidth`, `filling` v `App/Views/AvailableWidth.swift`).
- **Pružná výška v řádku líného seznamu je zakázaná taky, ale z jiného měření** (#375): měřidlo
  na projíždění tuhle třídu **nevidí**, zato u buňky dvojice (#98) položila aplikaci v hit testu
  při pohybu myši. Cena se proto **neodhaduje z tabulky pro šířku**. Zakázaná je **v řádku**, ne
  plošně — ohraničené formy jsou
  [vyjmenované](docs/architektura.md#šířka-v-okně-appviewsavailablewidthswift).
- **Rozměr nevyjednává líný seznam** (#361) **ani obsah okna** (#472) — oba ho dostanou změřený
  (`fillingSlot()`). U líného seznamu proto, že na každý dotaz pružného rámce odpovídá `LazyVStack`
  **zápisem** do téže krabice, ze které kreslí `placeSubviews` (hlídá to `LazyIdealSizeTests`;
  [rozbor](docs/architektura.md#fillingslot--líný-seznam-rozměr-nevyjednává-vůbec-361)), a je to
  tam [zlevnění, ne oprava](docs/architektura.md#nezastavilo-to-nic-a-je-to-změřené-361-třinácté-kolo).
  U obsahu okna proto, že pružné dítě `HStack`u dostane průzkumné nabídky na pružnost a rámec je
  **předá dolů celým detailem**: naměřeno **89 → 8 ms** na průchod tělem detailu a **282 → 56 ms**
  na přepnutí tabu
  ([rozbor](docs/architektura.md#obsah-okna-dostane-změřenou-štěrbinu-472)). **Sousedé ani obsah
  v tom nejsou** — skutečný rail, hlavička a stavový řádek stojí proti slepým obdélníkům 7 ms
  a plný store proti prázdnému 14 %.
- **`LazyVStack` v diffu ani na ose konverzace nepatří, a je to změna proti #361** (#469). Do #469
  tu stálo, že líný seznam patří tam, kde je seznam neomezený — tedy do diffu. Kolo z #361 se ale
  po opravě osy **přestěhovalo právě tam** (dva `sample`y ze živého záchvatu, `LazySubviewPlacements`
  25 %, `FileDiff.diagnosedID` i `DiffRow.diagnosedID` v zásobníku), takže neomezenost není důvod
  ten vzor snést: je to vlastnost lazy layoutu, ne délky seznamu. Diff proto kreslí **pevný
  `VStack`** a laznost se přestěhovala z rozvržení do jednoho rozhodnutí — blok kódu má živý
  `NSTextView` jen v pásu kolem výřezu (`Policy.mountBand(visible:)`, `DiffBlockSlot`), ukotvenou
  hlavičku kreslí `DiffPinnedHeader` přes výřez a jediné místo, kam se scrollování zapisuje, je
  `DiffViewport`. **Bez toho okna by pevný stack diff položil** (6000 řádků: 21 s CPU proti 0,86 s
  s oknem), a **cena projíždění roste s počtem nasazených `NSTextView`, ne s délkou seznamu** —
  hlídá to `DiffMountingTests`, čísla i ablace jsou
  v [`docs/architektura.md`](docs/architektura.md#pevný-seznam-a-nasazování-bloků-469). `List` je
  změřený a zamítnutý — výška obsahu je u něj odhad, takže posuvník lže; hlídá to
  `ConversationAxisEagerTests` ([cena](docs/architektura.md#patnácté-kolo-osa-líný-seznam-nemá-361)).
- **Nevyjednává se ani počet prvků** (#252): overlay nad blokem kódu měl plochu, gesto a čtení
  geometrie u **každého** řádku a strany, spočítat se to dá jednou (`DiffGutterGeometry`,
  3,05 ms → 0,12 ms). Prvek v `ForEach`i s prázdným obsahem se pořád umisťuje a co se při
  scrollování mění, **nesmí být ve `@State`** ([rozbor](docs/architektura.md#appdiff)).
- **V líném seznamu se neiteruje pole tuplů** (#361): `ForEach(Array(x.enumerated()),
  id: \.element.id)` čte identitu **přes tuple**, takže se u enumu s asociovanými hodnotami při
  každém dotazu rozbalí a **zkopíruje** payload. Identita patří do **uloženého pole**
  (`ConversationRow`), index se dopočítá v `Policy`
  ([měření](docs/testovani.md#projíždění-kolečkem-a-co-z-něj-u-361-vyšlo-361)). Plošný grep
  prázdný vyjít **nemůže**: `id: \.offset` payload nekopíruje a u prvků, které se legitimně
  opakují (řádky textu, sha), je pořadí **jediná** správná identita.

```bash
grep -rn 'maxHeight: .infinity' App/Views/ConversationNodeView.swift | grep -vE ':[0-9]+: *//'
grep -rn 'maxHeight: .infinity' App | grep -vE ':[0-9]+: *//'    # výčet k posouzení, ne prázdný
grep -rn 'fillingSlot' App/Views | grep -vE ':[0-9]+: *//'       # osm míst + modifikátor sám
# Prázdný (#361, #469) — filtr zahazuje komentáře, ve kterých se to rozhodnutí vysvětluje.
grep -n 'LazyVStack' App/Views/ConversationView.swift App/Views/DiffView.swift |
    grep -vE ':[0-9]+: *//|:[0-9]+: *///'
grep -rn 'LazyVStack\|LazyVGrid' App | grep -vE ':[0-9]+: *//'   # výčet: má ten seznam strop?
grep -n 'ForEach(Array(' App/Views/ConversationView.swift App/Views/ThreadBubbleView.swift
grep -rn 'ForEach(Array(' App | grep -vE ':[0-9]+: *//'          # výčet k posouzení, ne prázdný
```

- **`@Observable` sleduje po vlastnostech, takže hrubá vlastnost je výkonová vada** (#469, znovu
  #472). Co se mění jinak často a čte jinde, patří do **vlastní** vlastnosti: `PollingService`
  držel do #472 všech pět hodnot v jednom `PollState`u, takže `isRefreshing = true` na začátku
  tiku probudilo i čtenáře seznamu PR — a ten čte `AppStore.author(of:)`, na kterém visí
  `ownership` a s ním celý detail. Tichý tik tím překresloval celé okno: **62 průchodů tělem
  `PullRequestDetailView` za dvacet tiků, po rozdělení 1**. Naopak **psát „jen změnu“ nemá smysl**
  — zápis téže hodnoty toolchain nehlásí (změřeno, pinuje to `PollObservationTests`), takže
  `if x != new { x = new }` je porovnání navíc, které nic nemění.
  Čísla i zamítnuté varianty jsou
  v [`docs/architektura.md`](docs/architektura.md#pět-vlastností-ne-jeden-pollstate-472).
- **Cenu přerovnání okna drží rozvržení, ne naše kód** (#472) — ve `sample`u je vlastní práce
  aplikace **~1,5 %** hlavního vlákna. Než začneš zlevňovat vedle rozvržení, přečti si
  [*Tři zlevnění, která se změřila a zahodila*](docs/testovani.md#tři-zlevnění-která-se-změřila-a-zahodila):
  zkratka na dotaz o minimum okna, zapamatované výšky bloků i skládání uzávěrů po souborech
  **mechanicky fungují a na ceně nezměnily nic** — včetně redesignu na úseky řádků, po kterém
  ubyla **půlka** dětí ve stacku a cena se nehnula. **Napřed změř, která část scénáře je drahá:**
  přepnutí tabu je jiný a dražší scénář než přerovnání (407–682 ms proti 95–116 ms), ale **tři
  čtvrtiny z něj s diffem nesouvisí** — je to přestavba detailu (309 ms i mezi dvěma taby, ve
  kterých žádný seznam není).
- **Animace, která nikdy nedoběhne, nesmí být ve SwiftUI** (#350): `repeatForever` si vyžádá
  průchod při **každém obtažení obrazovky** a ten rozvrhne celé okno — nečinné okno stálo kvůli
  jedenáctibodovému prstýnku **99 % CPU** hlavního vlákna. Nekonečné otáčení patří na `CALayer`
  (`SpinningRingView`), krátká animace na gesto ve SwiftUI zůstat může; `ProgressView` je na
  macOS AppKitový ([rozbor](docs/architektura.md#nekonečné-animace-v-okně-350)).
- **Zpětná vazba z každého snímku nesmí zapisovat do `@State` bezpodmínečně** (#358):
  `onContinuousHover` dostane polohu i tehdy, když se myš **nehnula**, takže bezpodmínečný zápis
  zavírá kolo přes runloop observer (**1630 z 1690** vzorků `Update.dispatchActions()` a 99 %
  CPU bez vnějšího pohonu). Rozhoduje **`Policy.hoverChange(from:to:)`**, na jednom místě
  schválně. Dvě věci, které nejsou zjevné: hodnota stavu **musí být `Equatable`** (tuple
  v Swiftu není) a předat ji **nejde přes `inout`** — `@State` je počítaná vlastnost, takže
  `&hovered` projde setterem i beze změny.
- **`onGeometryChange` do téhle třídy nepatří** (#361) — při nezměněné hodnotě se **nespustí**;
  u **`.onHover` to ověřené není**
  ([co zbývá doměřit](docs/testovani.md#proč-na-358-není-sonda-a-je-to-změřené-358)). **„Akce se
  nespustí“ ale neznamená „nestojí to nic“** (#438): hodnota se počítá i tak a `of:` closure běží
  **uvnitř aktualizace grafu**, takže modifikátor **nepřipojuj tam, kde výsledek nikdo
  nepřečte**, a podmínku dej **před** čtení, ne do akce.
- **`updateNSView` chodí i tehdy, když se hodnota nezměnila** (#393) — volá ho každý přepočet
  geometrie, ne změna dat (ve ztuhlém okně tisíckrát za sekundu a **bez jediného průchodu
  tělem**). Co je v něm lineární v délce obsahu, se musí schovat za **klíč uložený
  v `Coordinator`u** (`DiffBlockDrawing` = obsah + styl + **šířka**). **Netýká se to všech
  representable, a je to změřené**: dostane ho ten, který si **říká o vlastní velikost**
  (`sizeThatFits`), takže se stráž nedává plošně — kde ji nemá co vyvolat, nešla by ověřit
  vloženou regresí ([tři neintuitivní věci](docs/architektura.md#stráž-v-updatensview-393)).
- **V AppKitu není „bez barvy“ dědění, ale černá** (#393): `NSAttributedString` bez
  `.foregroundColor` se kreslí **černě** (ve SwiftUI přitom `foregroundColor = nil` doopravdy
  dědí), a stálo to kontrast **1,39** v tmavém režimu. Barva se nasazuje **jako základní atribut
  celého řetězce** a syntaxe ji přepisuje; hodnota je `Palette.ink`, ne poloprůhledný
  `labelColor`. A **kontrast paletového tokenu netvrdí nic o kresbě** — k měření barvy patří
  i tvrzení, že se ta barva **do textu dostane**.
- **Sémantická škála se kreslí z palety, nikdy ze systému** (#432): systémová
  `.green`/`.red`/`.orange`/`.yellow` je navržená jako **výplň** s bílým textem, kdežto tady je
  barva ze škály skoro vždycky **text nebo glyf na tlumeném washi** — stálo to čtyři kapsle
  s kontrastem 1,63 až 2,70. Ze systému **zůstávají tři věci**: `.secondary` (není barva ze
  škály, ale „nemám co říct“), `.purple` u `merged` a `.blue` u `renamed` — ta je zapsaná mezera,
  ne záměr ([záznam
  rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--sémantická-škála-z-palety-432)).
  **Kontrast se měří z nakreslené bitmapy, ne z tokenu.**

```bash
grep -rn 'repeatForever' App | grep -vE ':[0-9]+: *//'    # musí vyjít prázdný
grep -rn 'onContinuousHover' App | grep -vE ':[0-9]+: *//' | cut -d: -f1 | sort -u |
    while read f; do grep -v '^ *//' "$f" | grep -q 'Policy.hoverChange' || echo "$f"; done
grep -rn 'onGeometryChange' App | grep -vE ':[0-9]+: *//'   # výčet: kdo tu hodnotu čte?
grep -rln 'func updateNSView' App                           # výčet: rozhoduje `sizeThatFits`
grep -rnE '\.(green|red|yellow|orange)([^A-Za-z0-9_]|$)' App | grep -vE ':[0-9]+: *///?'
```

- **Kombinace kláves se v `App/` píše jen v katalogu zkratek** (#441), a **zkratka okna se v tabu,
  který si tutéž klávesu bere, zakáže** (#452: `⌘⏎` odesílá otázku v `Zeptat se`, rozhoduje
  `Policy.claimsReturnShortcut`). Dvě tlačítka se stejnou
  kombinací nejsou chyba ani pád — vyhraje to zaregistrované později (#151, #184) a druhá
  zkratka „nefunguje“. Rozhoduje `Policy.windowShortcut(_:)` a překládá to jediné místo
  (`WindowShortcutButtons`, `View.windowShortcut(_:)`); popiska se **odvozuje**, nikdy neopisuje
  vedle klávesy. Dvě tlačítka se **stejnou akcí a jinou klávesou** jsou naopak v pořádku — česká
  klávesnice má pod `1`–`5` znaky `+ ě š č ř`. Hlídá to `WindowShortcutsTests` a **dvě** stráže
  nad zdrojáky: kde se zkratka **registruje** (`grep -rn 'keyboardShortcut(' App`) a kde se
  **kreslí** (`⌘`/`⌥` v řetězcovém literálu) — obojí **výčet, ne prázdný**. Že klávesa zabere, se
  v harnessu ověřit nedá; zkouší to člověk, a u zkratek s číslicí **na obou mapách**
  ([katalog](docs/architektura.md#katalog-klávesových-zkratek-441)).
- **Fokus a posun scrollu se nastavují o průchod později, ne časovačem** (#184, potřetí #392;
  scroll #325). Přiřazení fokusu ve **stejném průchodu**, ve kterém pole vzniká, SwiftUI zahodí
  (`onAppear`, `task` bez yieldu i `defaultFocus($x, true)` daly `AXFocused = false`
  **navždycky**) — dělá se `.task` s jedním `Task.yield()`, a totéž u posunu na konec narostlého
  obsahu (`Task`). Rozhoduje **počet průchodů, ne čas**, takže odklad časovačem nepomůže a je to
  navíc zakázaná třída (#350). Posun navěšený na **data** naopak doběhne moc brzo (řádek ještě
  není rozvržený), takže se sleduje **geometrie**; a sledování konce se nesmí opřít o „jsem na
  posledním bodu obsahu“ — rozhoduje `Policy.stepFeedReaction`
  ([rozbor](docs/architektura.md#živý-výpis-kroků-v-tabu-průběh-325)). **Fokus jde ověřit jedině
  na běžící aplikaci** (testovací host nedostane aktivaci), takže **do popisu PR patří, že tuhle
  věc ověří člověk** ([jak se měří](docs/testovani.md#jak-změřit-fokus-a-klávesy-184)).
- **Kdo si říká o velikost, musí ji měřit na tom, na čem kreslí** (#236). Blok kódu si
  v `LazyVStack`u navrhuje výšku sám, takže spočítaná na jiné šířce, než na jaké se zalamuje,
  přeteče do řádku pod sebou. Měření patří **do toho typu, který drží šířku kreslení**; dvě místa
  znamenají dvě pravdy o jedné šířce. Testuje se proti **layout manageru** a **přes pásmo
  šířek** — rozejde se to jen v pásmu, takže u jedné šířky test projde
  ([rozbor](docs/architektura.md#appdiff)). Do téhle třídy patří i **„je tam vodorovný pruh?“**
  (#422 — výška bloku dvojic závisí na šířce, takže rezervovat jeho 17 bodů musí totéž místo,
  které o pruhu rozhoduje), **šířka dokumentu u textu kresleného jinde než na `x: 0`**
  (`DiffTextView.naturalWidth`, počítaná **po řádcích**, ne z `usedRect(for:)`, který umí zahrnout
  extra line fragment o šířce 10 000 000 bodů) a **pruh, který jede s výřezem** (#428 — mění se
  **jen `frame.origin.y` scrolleru**, nikdy výška bloku; poloha je jedno minimum v `Policy`,
  pozorovatel jeden na blok a do observable stavu se nesahá)
  ([#422](docs/architektura.md#trvalý-vodorovný-pruh-ve-split-pohledu-422),
  [#428](docs/architektura.md#pruh-který-jede-s-výřezem-428)).

  **A rozměr, ze kterého se počítá, se měří — nenasazuje se rámcem** (#325): `frame(height:)` by
  srovnal výšku s kresbou **na sílu** a rozejití by nebylo jak poznat. U výšky řádku navíc nesmí
  rozhodovat **ikona** — SF Symboly jednu výšku nemají (15 / 14 / 12 bodů), takže je srovná
  `imageScale(.small)`; rámcem to nejde.
- **Sheet dostane `idealWidth` jedině s `presentationSizing(.fitted)`** (#327) — bez toho
  modifikátoru je široký jako `minWidth`, a nerozhoduje o tom okno za ním. S `.fitted` a pružným
  rámcem navíc dostane `.resizable` do `styleMask`u, takže se dá **roztáhnout myší**. Kdo si
  velikost pamatuje, musí vědět, že se **sheet rozvrhuje dvakrát a v prvním průchodu má
  podlahu** — zápis bez odmlky uloží podlahu
  ([rozbor](docs/architektura.md#sheet-se-dá-roztáhnout-a-velikost-si-pamatuje)).

  ```bash
  grep -rln 'idealWidth' App/Views    # výčet k posouzení, ne prázdný
  ```
## Testování

Katalog toho, co se u které oblasti testuje a proč zrovna to, je v
[`docs/testovani.md`](docs/testovani.md) — i s návodem, **jak si zkontrolovat, jak view
vypadá** (offscreen render, accessibility).

Zásady, které platí všude:

- **Protokol + fake, ne mockovací framework.** U modulů se vnějším světem i u `Environment`.
  Fake je obyčejná třída v `Tests/`, která si pamatuje, co po ní kdo chtěl.
- **`Policy` se testuje vyčerpávajícím výčtem**, bez mockování — je to čistá funkce a je to
  jediné místo, kde se rozhoduje.
- **Fixtures jsou skutečné výstupy**, ne vymyšlené: `gh`, `stream-json`, status pages. Berou
  se z **veřejných** repozitářů, protože titulky firemních PR sem nepatří. Co se ze skutečných
  dat nesehná, se testuje inline JSONem přímo v testu — a je u toho napsané proč.
- **Nejcennější test je ten, který tvrdí, že se něco NEstalo**: že se nic neodeslalo, že se
  nespustil druhý reviewer, že se značka nesmazala. Ty se totiž rozbijí potichu.
- **Regrese se ověřuje vložením regrese.** Zelený běh nedokazuje, že test chytá to, co má —
  u pravidel, na kterých něco stojí, se ta chyba dočasně vrátí a kouká se, jestli test spadne.
- **Test netvrdí nic o globálním stavu procesu a nezapisuje do něj** (#367). `NSApp.appearance`
  je jedna hodnota na celý testovací host a **píše ji i sám hostitel**, takže tvrzení „nesáhlo
  se“ vycházelo podle toho, kdo běžel vedle, a `main` byl **falešně červený**. Kdo potřebuje
  vynucený režim, nastaví ho na **svém** okně (`AppearanceSwitchProbe`) nebo obalí kreslení
  `performAsCurrentDrawingAppearance`; „kdo smí sáhnout na globál“ se tvrdí nad **zdrojáky**
  (`GlobalAppearanceTests`,
  [proč](docs/testovani.md#globální-stav-procesu-se-v-testech-neměří-367)).

  **`UserDefaults` je tentýž případ, a přežije běh** (#411). Od #411 je výchozí `PRISM_SLOT`
  v projektu `.testhost`, takže host běží jako `com.ondrajodas.prism.testhost` a `@AppStorage`
  ani `UserDefaults.standard` už nepíšou do nastavení, které se používá. Kdo potřebuje
  `UserDefaults`, bere si **`ScratchDefaults`** — jméno s `UUID`, protože pojmenovaná doména je
  sdílená **napříč procesy**, a úklid po sobě; sada, která tvrdí něco o úklidu, si hlavní
  instanci **vyrábí** v podstrčeném `HOME`. Hlídají to `ProcessPreferencesTests`
  ([podrobnosti](docs/testovani.md#userdefaults-je-tentýž-případ-a-měl-tři-projevy-411)).

  **A metrika písma se čte na jednom místě** (#407): `NSFont` v testovacím hostu pod zátěží
  vydá **přechodně nepoužitelnou metriku** (všechny cesty 0,0, o zlomek sekundy později 8,036)
  a sazba tím písmem navíc **položí proces** výjimkou z CoreTextu. Vydává ji proto `FontMetric`
  — jedno měření na proces, tři cesty **opakované s odmlkou**, **nula se nepamatuje**
  a náhradní měření **nesází text**; hlídají to dvě tvrzení nad zdrojáky ve `FontMetricTests`
  ([rozbor](docs/testovani.md#metrika-písma-je-tentýž-kořen-v-jiné-podobě-407)).

  Tři grepy, které **musí vyjít prázdné** (guard soubory se odečítají, hledané řetězce v nich
  stojí jako literály), a jeden, který v `App/` **musí vypsat jen `FontMetric.swift`**:

  ```bash
  grep -rn 'NSApp.appearance\|NSApplication.shared.appearance' Tests |
      grep -vE ':[0-9]+: *//' | grep -v GlobalAppearanceTests
  # `--include`, protože stráž čte zdrojáky: v `Tests/Fixtures/` leží skutečný diff, ve kterém
  # to jméno stojí legitimně (je to náš `project.pbxproj` z doby přejmenování).
  grep -rn --include='*.swift' 'UserDefaults.standard\|UserDefaults(suiteName: "' Tests |
      grep -vE ':[0-9]+: *//' | grep -v ProcessPreferencesTests
  grep -rn --include='*.swift' '"com.ondrajodas.prism"\|/Applications/PRism.app' Tests |
      grep -vE ':[0-9]+: *//' | grep -v ProcessPreferencesTests
  grep -rn 'maximumAdvancement\|defaultLineHeight\|boundingRectForFont' App | grep -vE ':[0-9]+: *//'
  ```
- **Okno se v testu ukazuje bez animace** (#462). `orderFront` na okně s výchozí
  `animationBehavior` spustí `NSAnimation` v **threaded** režimu, tedy `-[NSAnimation _runBlocking]`
  na **vlákně z globálního dispatch poolu**, které si drží po celou dobu animace. Rozhoduje ukázání
  okna, ne SwiftUI a ne obsah (změřeno i na `borderless` okně bez view). Jedno okno nic neznamená,
  **48 ukázaných oken v paralelním běhu ano**: pool má strop **75 vláken** a `SubprocessRunner` z něj
  bere vlákna na blokující čtení pip — při 80 obsazených se práce na téže frontě dostane na procesor
  až za **28 s** místo 0,0001 s, což je nad timeoutem `gh`. Odtud `PublishError.timedOut` **i**
  zaseknutý plný běh na těch třech suitách, které `gh` spouštějí; je to **jedna příčina**.
  Ukazuje se proto přes `orderFrontUnanimated()` z `Tests/Support/UnanimatedWindow.swift` a hlídá to
  `UnanimatedWindowTests` ([rozbor i jak se zaseknutý běh pozná od `Early unexpected
  exit`](docs/testovani.md#zaseknutý-plný-běh-okno-které-se-objeví-s-animací-462)). Grep, který
  **musí vyjít prázdný** (helper i stráž se odečítají — v obou ta volání stojí legitimně):

  ```bash
  # Prefix `UnanimatedWindow` odečítá dva soubory: helper a stráž nad ním.
  grep -rn 'orderFront(\|orderFrontRegardless(\|makeKeyAndOrderFront(' Tests |
      grep -vE ':[0-9]+: *//' | grep -v UnanimatedWindow
  ```
- **Jak se v tomhle repu měří, je v [`docs/testovani.md`](docs/testovani.md)** — a než začneš
  měřit, přečti si to, protože každá z těch věcí už jednou vyrobila falešný výsledek: test, který
  čeká na jev, se **neváže na pevný okamžik** (#269,
  [*Čekání na jev*](docs/testovani.md#čekání-na-jev-296)); měřidlo **nesmí počítat přípravu**
  a číslo z okna se bere **střídavě** A/B/A/B, protože drift sezení je větší než hledaný rozdíl
  (#274, [*Kolik stojí otevřená
  záložka*](docs/testovani.md#kolik-stojí-otevřená-záložka-274)); ve `sample`u se čte **podíl
  největšího nezanořeného uzlu**, nikdy `grep -c`, a u víc vzorků ztuhlé aplikace se čte **kořen
  u každého zvlášť** (#350, #361, [*Ve `sample`u se čte
  podíl*](docs/testovani.md#ve-sampleu-se-čte-podíl-ne-jen-vrcholy-zásobníku-350),
  [*`sample` je strom*](docs/testovani.md#sample-je-strom-takže-součet-řádků-není-podíl));
  nástroj na **živý** záchvat nesmí měřit z runloopu hlavního vlákna, protože ten se do stavu
  čekání nedostane (#391, [rozbor](docs/architektura.md#diagnostika-kreslení-361)); a u cizího
  privátního API rozhoduje **pád v testu v hostu**, ne odhad z footprintu (#361 —
  `AGGraphDescription` je autoreleased).
- **Měřidlo, které vydá tutéž hodnotu pro „funguje“ i „nefunguje“, netvrdí nic** (#478) — a vypadá
  u toho zeleně. Sonda z #460 měřila u kolečka nad `claude` **výřez emulátoru**, jenže nula je tam
  správná odpověď v obou světech; rozdíl byl vidět jedině na tom, **co odešlo do procesu**. Když
  měření končí větou „neopravovalo se nic“, patří k němu druhá otázka: **naměřilo by rozdíl, kdyby
  ta chyba byla?** ([rozbor](docs/testovani.md#kolečko-v-zásuvce-478--co-jde-tvrdit-bez-pty))
- **Testy se nespouštějí rourou do `grepu`** — viz *Příkazy* níž, umí to zaseknout na neurčito.

## Příkazy

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex build
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test
```

**`-derivedDataPath build.noindex` patří i k testům** (#139). `xcodebuild test` **spouští**
testovacího hosta, a spuštění bundle ho zaregistruje v LaunchServices — bez toho přepínače
skončí v `~/Library/Developer/Xcode/DerivedData/PRism-<hash>/…` a ve Spotlightu je PRism
navždycky dvakrát. Do `build.noindex/` míří i `bin/run.sh`, takže tenhle záznam uklidí
příští spuštění skriptu: je to **tatáž cesta**, kterou odregistrovává.

```bash
./bin/run.sh                           # build v Debug, instalace do /Applications, spuštění
./bin/run.sh --diagnose                # totéž + diagnostika kreslení (#361, #412)
./bin/worktree.sh a issue-231-neco     # strom pro paralelní vývoj ve slotu „a“ (#228)
./bin/slot-config.sh                   # očištěná konfigurace do cache slotu (#262)
./bin/slot-cleanup.sh                  # ukliď po slotu: bundle, cache, UserDefaults, LS (#398)
./bin/setup-signing.sh                 # jednorázově: certifikát + Signing.local.xcconfig
swift bin/make-icon.swift [split] [/tmp/x]    # překreslí ikonu do App/Assets.xcassets
```

Co každý z nich dělá a jaké má návratové kódy, je v jeho hlavičce a v README (sekce
[*Build*](README.md#build), [*Paralelní vývoj — sloty*](README.md#paralelní-vývoj--sloty),
[*Diagnostika kreslení*](README.md#diagnostika-kreslení-361),
[*Podpis*](README.md#podpis)). Čtyři věci se ale hodí vědět dřív, než je pustíš:

- **`run.sh` instaluje do `/Applications` schválně** — odjinud nefungují notifikace (#88).
  Předchozí instanci ukončuje **Apple eventem, ne `killall`em**, takže se při běžícím review
  zeptá a bez odpovědi nespustí nic; **cizí bundle nepřepíše** a při selhání instalace radši
  nespustí nic, ať se nekoukáš na starý build.
- **Diagnostika kreslení vypnutá nestojí nic a vypne se sama** dalším spuštěním bez toho
  přepínače — nedá se v ní tedy „zapomenout“.
- **`slot-config.sh` je jediné místo, kde ta očista je** (odesílání, notifikace, automat) —
  nepiš vlastní `jq` filtr.
- **`slot-cleanup.sh` bez slotu odmítne** (cílem by byla hlavní instance) a **cizí bundle
  v `/Applications` nesmaže**.

**Slot je jediné, co dělí paralelní okna od sebe** — bundle ID, jméno v `/Applications`
i kořen cache (ten si aplikace bere z `CFBundleName`, ne z konstanty). Bez `.prism-slot` se
nemění nic, takže hlavní strom zůstává tou aplikací, která se používá.

`xcodebuild` na tomhle stroji plive na začátku výstupu chyby o `CoreSimulator` — jsou
neškodné, týkají se iOS simulátorů, ne macOS buildu. Rozhoduje `** BUILD SUCCEEDED **`,
resp. `** TEST SUCCEEDED **` na konci.

**Výstup `xcodebuild` piš do souboru a grepuj až ten soubor.**

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test > /tmp/tests.log 2>&1
grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)" /tmp/tests.log | tail -5
```

Roura `xcodebuild … | grep … | head -N` se umí zaseknout na neurčito a vypadá to jako
zaseknuté testy — přitom testy doběhnou za sekundu. Stálo to jednou přes půl hodiny
hledání neexistující chyby v testech. Když se zdá, že test run visí, první věc je pustit
ho do souboru.

**Čekání v testech má jedno místo: `Tests/Support/TestWaiting.swift`** (#296). `waitUntil`,
`settle()`, `TestWait.pause()` — nic vlastního nepiš. Nové čekání **nikdy** přes `Task.yield()`
ani přes rozpočet kol (`for _ in 0..<N`): pod souběžným buildem tří slotů se odmlka o 100 ms
probouzí i za 8,6 s, takže jakýkoli strop odvozený od volného stroje je falešně červený `main`
([čísla](docs/testovani.md#čekání-na-jev-296)).

**Když běh umře před prvním testem** — `Early unexpected exit, operation never finished
bootstrapping` bez chyby kompilace a bez jediného `✘` — je to **zátěž, ne rozbitý build**.
Pusť ho znovu, viz tatáž sekce.

## Prostředí

- macOS 26, Xcode 26, Swift 6.3
- Vyžaduje na stroji `gh` (přihlášený), `claude` a `git`
- **App Sandbox vypnutý** — aplikace spouští podprocesy a zapisuje do vlastní cache
- **Jedna závislost třetí strany: `SwiftTerm`, připnutý na `1.11.2`** (#459). Verze je vybraná
  měřením, ne opatrností: od `1.17` má balíček build tool plugin, který `xcodebuild` bez
  `-skipPackagePluginValidation` odmítne, a od `1.12` metalový shader v resources, na který je
  potřeba Metal Toolchain (na tomhle stroji není). **Připnutí drží všechny příkazy v repu beze
  změny** — kdo půjde nahoru, mění tři z nich a instaluje komponentu Xcode; zdůvodnění je
  v [záznamu rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#swiftterm--první-závislost-třetí-strany-v-tomhle-repu).
  Rozpouští se při prvním buildu, takže je **potřeba síť** — `Package.resolved` je v repu
- **Podpis je stálý, ne ad-hoc** (#61). `Signing.xcconfig` drží ad-hoc default a přes
  `#include?` si tahá gitignorovaný `Signing.local.xcconfig` s jménem certifikátu, který
  vyrobí `bin/setup-signing.sh`. Ad-hoc podpis nemá stálou identitu, takže po každém buildu
  je to pro macOS jiná aplikace a **udělená TCC povolení propadnou** (podrobnosti v README,
  sekce *Podpis*). Dvě věci, na které se u toho naráží: **identita se nesmí zadrátovat do
  `project.pbxproj`** (build s certifikátem, který na stroji není, končí `No certificate
  matching 'PRism Local' found` — proto je fallback v checkovaném xcconfigu a jméno v tom
  lokálním), a **`CODE_SIGN_IDENTITY` je jen na úrovni projektu** (v buildSettings targetů by
  přebilo xcconfig a lokální soubor by neměl žádný efekt).
- **Binárky hledej absolutní cestou.** GUI aplikace spuštěná z Finderu nedědí `PATH` ze
  shellu, takže `gh` se podle jména nenajde. Řeší `BinaryLocator` při startu; cesty se
  berou z `ToolPaths`, nikdy z názvu binárky.
- **Aplikace se provozuje z `/Applications`** (#88). Odjinud macOS nepovolí notifikace —
  změřeno ([`docs/architektura.md`](docs/architektura.md#vrstva-environment-appenvironment)).
  `bin/run.sh` tam bundle instaluje sám; `build.noindex/` zůstává jen místem, kde se buildí.
- **Buildí se do `build.noindex/`, ne do `build/`** (#139). Bez té přípony si LaunchServices
  kopii **samo zaregistruje** — změřeno, po odregistrování je do 25 vteřin zpátky — a ve
  Spotlightu pak stojí dva PRismy se stejným jménem, ze kterých se nedá vybrat; záznam navíc
  přežije i smazání bundlu. **Samotná přípona nestačí:** Xcode bundle na konci buildu
  registruje výslovně (`lsregister -f -R -trusted`) a `xcodebuild test` ho navíc **spouští**,
  takže `bin/run.sh` po instalaci tu jednu cestu odregistruje — a protože do `build.noindex/`
  míří i testy, uklidí tím i po nich. Selhání se **hlásí, ale nepokládá skript**.

  **Od #398 to je jedno volání, které navíc zametá záznamy o cestách, na kterých na disku nic
  není** — zaniklé worktree, staré slotové bundly, testovací hosty (`prism_sweep_registrations`
  v `bin/lib/bundles.sh`, sdílené s `bin/slot-cleanup.sh`). Cizí ani sousedovu aplikaci to vzít
  nemůže: co na disku je, se nedotkne. Dvě věci na tom nejsou zjevné a jsou změřené —
  `lsregister -u` vrací **nenulu i nad cestou, která v databázi vůbec není**, takže rozhoduje
  zpětné čtení výpisu; a `PlistBuddy` píše chyby **jednou na stdout, jednou na stderr**, takže
  identifikátor bundlu se bere jedině při nulovém návratovém kódu ([záznam
  rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--co-po-sobě-slot-nechává-398-399)).

## Stav

Co je hotové a co zbývá, je v [`docs/stav.md`](docs/stav.md) — souvislý záznam včetně toho,
co se cestou rozhodlo jinak, než bylo v zadání. **Aktualizuje se, jak fáze ubývají.**

Rozsah v1 podle specifikace je hotový; hotové jsou i milníky M6 (odesílání review), M7
(konverzace) a M8 (notifikace), tedy poslední naplánované. Co přijde teď, jde přes issues.
