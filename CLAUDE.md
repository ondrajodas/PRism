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

**`CLAUDE.md` se drží malý, a je to podmínka, ne estetika** (#162, znovu #447, potřetí #496).
Copilot si ho bere jako custom instructions se stropem 110 tisíc tokenů — když ho přeroste,
review na PR **vůbec nedoběhne** a v okně po něm zbude jen nicneříkající chyba. Sem se píše jen
to, co je potřeba znát dřív, než se něco napíše; **podrobnost, měření a technika měření patří do
`docs/`**. Kontroluj to **měřením, ne odhadem** — nad ~100 kB je čas rozdělovat znovu:

```bash
wc -c < CLAUDE.md    # po #496 ~82 kB; nad ~100 kB je čas rozdělovat znovu
```

Co se stalo při 315 kB, jak se pád pozná z logu akce, proč nerozhodovala velikost diffu, proč se
cíl 40 kB dvakrát nesplnil a co dělat, když Copilot přesto nedoběhne, je v [specifikaci,
*`CLAUDE.md` se drží
malý*](docs/superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447-potřetí-496).

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
  aplikace** (sahá do hlavního stromu, což subagent nesmí). Co přesně dostane subagent do
  zadání, je v [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md#co-dělá-orchestrátor--a-co-ne),
  sekce [*3. Zadání subagenta*](docs/paralelni-vyvoj.md#3-zadání-subagenta).
- **Všechno jde přes PR.** Žádné přímé pushe do `main` — každá změna (kód i dokumentace)
  má vlastní branch a PR, i když je malá. PR odkazuje na issue, které řeší.
- **Branch:** anglicky, krátce, s číslem issue — např. `issue-4-github-gateway`.
- **Před prvním pushem mi appku spusť (`./bin/run.sh`) a dej mi prostor na připomínky — ale jen
  když je na změně co vidět.** Platí pro první push branche, ne pro opravy po review.

  Pak **zastav a čekej.** Ne „spustil jsem a jde to“ a hned commit — smysl je, že si to
  proklikám, dokud je změna ještě levná na přepsání; zelené testy nejsou důkaz, že se to
  chová, jak jsem chtěl. Napiš, **na co se mám podívat** a co v příslušné obrazovce uvidím.
  **V dávce se pauza nezruší, jen se posune před merge** (#256, mění #247): subagent zastaví
  s hotovým PR a zavolá mě **přes orchestrátora** — hlášením, které ten předá dál (`SendMessage`
  subagent mít nemusí, #545) — a čekáním neblokuje
  slot ([podrobnosti](docs/paralelni-vyvoj.md#4-pauza-na-proklikání--změna-pravidla)).

  **Napřed se na to ale podívej sám — screenshotem.** `screencapture -x -R<x,y,w,h>` funguje
  a mockup se dá vyrendrovat headless Chromem a položit vedle ([`docs/testovani.md`, *Jak si
  zkontrolovat, jak view vypadá*](docs/testovani.md#jak-si-zkontrolovat-jak-view-vypadá)).
  Platí to i pro komponentu, která se jen **přesunula do užšího místa**: jiná šířka je jiný
  design a plné popisky, počty a odznaky se do ní obvykle nevejdou. A **nezapomeň před tou
  pauzou rebuildnout**, ať nekoukám na starý build.

  **Když se změna v UI nijak neprojeví** (vrstva bez UI — modely, parser, protokol),
  **na pauzu mě netahej.** Napiš do shrnutí jednou větou, že vidět není nic a proč, dolož to
  zelenými testy a **pokračuj rovnou na commit a PR**. Rozhodující je, jestli se něco změnilo
  na obrazovce, ne jestli je změna malá: oprava textu v labelu se ukazuje, nový `Codable`
  model ne.
- **Vlastní revize diffu je podmínka pushnutí, ne doporučení.** `copilot-review.sh` se smí
  pustit teprve po ní, a revize se musí někde **projevit** — buď opravou, nebo větou v popisu
  PR o tom, co jsi hledal. Když po ní diff vypadá nedotčeně a Copilot pak najde něco, co grep
  z tabulky níž chytá, **revize neproběhla**. Subagent je fajn, ale **není podmínka**: projít
  `git diff main...HEAD` vlastníma očima plus grepy níž zabere minuty.

  **Tohle Copilot v tomhle repu nachází opakovaně**, takže to projdi dřív, než ho pustíš:

  | Vzor | Proč to bolí |
  |---|---|
  | `try?`, prázdný `catch`, `?? default` nad operací, která může selhat | Ztracená data vypadají v UI jako „nic tu nebylo“. Ptej se: pozná uživatel, že se to nepovedlo? Když ne, patří to do stavu |
  | Text v UI, který tvrdí víc, než data unesou | „Reviewer nenahlásil žádný nález“ zní jako čisto i tehdy, když se nálezy nemají kde vzít |
  | Stav, který se drží, ale nikdo ho nečte | Buď to zobraz, nebo nedrž — jinak je to mrtvá váha, která svádí spolehnout se na ni |
  | Kontrola, která jinde v repu je, a tady chybí | Typicky ochrana proti mazání mimo cache. Když už někde existuje, patří na jedno místo |
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

  **Nemusíš vyhovět všem komentářům.** Rozhoduješ ty — u nálezu, který neopravíš, ale musí být
  odpověď s důvodem. Když si radou nejsi jistý, ověř ji (spusť to, změř to); zamítnutí podložené
  měřením je lepší než oprava naslepo. Když **nedoběhne vůbec** („Copilot encountered an
  error…“), jsou příčiny dvě a poznají se podle toho, jestli job běžel: spadlý job = velikost
  `CLAUDE.md` (viz *Údržba dokumentace* výš), **nespuštěný job = spotřebovaný request** (#452 —
  vyžádat znovu **nepomůže**, postup je v [`docs/github-cli.md`](docs/github-cli.md)).
- **PR, který je v pořádku, mergni sám.** Nečekej na pokyn: zelené testy, vyřešené nálezy
  a hotové zadání issue stačí. Po mergi rovnou **zavři issue** a **vydej release**.
  Když si nejsi jistý, jestli je hotovo, tak hotovo není — dodělej to, neptej se.
- **Po mergi mi restartuj hlavní aplikaci z mainu** — `./bin/run.sh` v hlavním stromě, bez
  ptaní, **po každém mergi, i uprostřed dávky**. `run.sh` ukončuje Apple eventem, takže při
  běžícím review se zeptá a bez odpovědi nespustí nic — to je záměr, nepřemlouvej to
  `killall`em. Když skript skončí nenulově, **řekni to** a nech starou instanci běžet.
- **Po mergnutí PR se vydá nový tag a GitHub release.** Release notes píšeme česky
  a popisují **jen to, co se v téhle verzi změnilo**: co přibylo, co se opravilo, co se
  rozhodlo jinak a proč, co se změřilo, co se zamítlo. Patří tam i to, co se změnou
  souvisí — počet testů, věta „na tomhle není co vidět“ u vrstvy bez UI, známé omezení.
  **Stav projektu do nich nepatří** — žádná sekce `Kde jsme`, `Další krok` ani výčet toho, co
  zbývá do milníku; release odpovídá jen na otázku „co je v téhle verzi jinak“. ([Proč se
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
  verzí nezakládá** — od `v1.0.0` běží jedna řada (`v1.1.x`) a číslo milníku v ní roli nehraje.
  Důvod je u obojího týž: verze je **značka na časové ose, ne štítek původu**.
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
a jedno publikování** — jinak v repu leží jiný návrh než na odkazu. **V dávce k tomu patří třetí
věc: číslo sekce přiděluje orchestrátor v zadání a po každém mergi se publikuje znovu ze slitého
stavu** (#537) — „další volné číslo“ si dvě větve vezmou obě, git to nenahlásí a pozdější
publikování to dřívější smete ([postup](docs/paralelni-vyvoj.md#číslo-sekce-v-mockupu-přiděluje-orchestrátor)).

**Issue, které mění vzhled nebo přidává něco nového na obrazovku, se na GitHubu
nezakládá, dokud ta změna není zakreslená v mockupu a odsouhlasená mnou.** Pořadí je:
překreslit mockup → poslat mi odkaz → počkat na souhlas → **teprve pak** `gh issue create`.
Je to **jediná schvalovací brána v tomhle repu** (výjimka z *Rozhodování* níž).

Co pod pravidlo **nespadá**: srovnat aplikaci s tím, co v mockupu **už nakreslené je**
(#283). Tam se návrh nemění, takže není co schvalovat — jde se rovnou. Naopak nová
obrazovka, sekce nastavení nebo tlačítko, které v mockupu není (#281), znamená napřed
mockup.

Jak se s artifactem pracuje — čtení CSS, aktualizace na tutéž adresu, render vedle
screenshotu — a **proč brána sedí zrovna u zakládání issue** je
v [`docs/navrh.md`](docs/navrh.md#proč-brána-sedí-u-zakládání-issue-ne-až-u-prvního-commitu).

## Rozhodování

**Návrhová rozhodnutí děláš sám.** Neptej se na potvrzení u každého detailu — kde žije
kontrola, kam patří složka, jaký stav blokuje, jak se jmenuje typ. Rozhodni, implementuj
a **zapiš rozhodnutí i s důvodem** do specifikace: záznam rozhodnutí je to, co dovoluje
pozdější korekci. Je to osobní nástroj a rychleji se posoudí na běžící aplikaci než
v návrhu.

**Žádná schvalovací brána na návrh.** Nepředkládej návrh a nečekej na „ano“ — ani když si
to vynucuje skill (typicky `superpowers:brainstorming` se svým hard gate). V tomhle repu
to pravidlo neplatí: rozhodnutí zapiš do specifikace a rovnou implementuj. Tohle je
výslovná uživatelská instrukce, a ta má přednost před skillem. Průzkum a rozmyšlení
z brainstormingu si nech, schvalovací krok zahoď.

**Jedinou výjimkou je vzhled** (viz *Návrh (mockup)* výš): co mění obrazovku nebo na ni
něco přidává, se kreslí do mockupu a schvaluje **dřív, než na to vůbec vznikne issue**.
Schvaluje se **obrázek**, ne návrh implementace.

Když na něco narazíš, co návrh v issue mění (zjistíš, že to nejde, jak je napsané),
**není to důvod se ptát** — rozhodni, zapiš do specifikace **co se změnilo a proč**,
a napiš to do popisu PR. Posoudí se to nad diffem.

Ptát se dál na **tvrdé podmínky** níž. Merge PR ani zavření issue mezi ně **nepatří** —
to si od 2026-08-01 řídíš sám
([proč](docs/superpowers/specs/2026-07-31-prism-design.md#merge-pr-a-zavření-issue-si-claude-řídí-sám-od-2026-08-01)).

## Tvrdé podmínky

Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav se a zeptej se.
**Zdůvodnění, naměřená čísla a historie změn těchto podmínek jsou v `docs/`** — u každé je
odkaz a čte se **dřív**, než se podmínka obchází, ne až potom.

1. **Jediná cesta ven** (od #67). Aplikace **umí** odeslat review, **ozvat se do vlákna**,
   **napsat komentář pod PR**, **přeštítkovat svůj PR a vyžádat na něm review**, **založit
   label, který repozitář ještě nezná**, **mergnout vlastní PR** a **přepnout vlastní draft na
   *ready for review*** — ale jedině přes `ReviewPublishing`, jedině na výslovný pokyn člověka
   a jedině tam, kde se to **v nastavení povolilo**. **Od #466 k tomu umí přetlačit vlastní
   větev** (`git push`), a to je **druhý** protokol, ne **další** metoda toho prvního — viz
   *Zápis do remote* níž. Pravidlo se skládá z šesti věcí a každá z nich je kontrolovatelná:

   1. **`GitHubGateway` zůstává bez zápisových metod.** Polling, diff, checkout ani reviewer
      tedy nemají čím něco odeslat — read-only je pořád vidět z typu.
   2. **Grep vyjmenuje všechna místa, odkud to jde.** Mají to být **sedm souborů a pět
      volajících**, všechny v `App/Publish/`: protokol, `GhReviewPublisher`,
      `ReviewSubmission.send()`, `ThreadSubmission`, `CommentSubmission`, `MetadataSubmission`
      a `MergeSubmission`. Volající **mimo** tu složku by znamenal, že cesta ven vede odjinud
      než z jednoho místa.
   3. **Publisher není pole `AppStore`.** Vzniká uvnitř té cesty, která odesílá, a zaniká s ní;
      store si drží **jen cestu ke `gh`** a stav, ne cestu ven. **Merge stav ve store nemá
      vůbec.**
   4. **Odeslání review si žádá hotový draft s `headSha`** a pre-flight ověří, že je to pořád
      hlava PR. **U odpovědi do vlákna, u komentáře pod PR a u labelů s reviewery se `headSha`
      neověřuje** (#73, #216, #392) — ověřuje se **stav PR**, a to **striktněji než GitHub**.
      **U merge se hlava ověřuje dvakrát** (#465): v pre-flightu a **v payloadu** (`sha`).
   5. **Jedno atomické volání.** Buď odejde všechno, nebo nic; sadu labelů skládá
      `Policy.toggledLabels`, ne publisher. **Pro `Založit a přidat` to neplatí, a je to vědomá
      výjimka** (#413).
   6. **Jen tam, kde se to povolilo** — `PublishScope` z `Configuration` (`allowsPublishing`
      globálně i per repo). **Výchozí stav je vypnuto**, a právě to drží vlastnost „samo nic
      neodejde“. Sandbox v tom **není výjimka v kódu**.

   **Komentáře se musí odečíst, jinak ten grep tvrdí něco jiného, než co hlídá test** (#496)
   — až s tím filtrem vydá těch sedm, respektive tři:

   ```bash
   grep -rn 'ReviewPublishing' App | grep -vE ':[0-9]+: *///?' | cut -d: -f1 | sort -u
   grep -rn 'BranchPushing' App | grep -vE ':[0-9]+: *///?' | cut -d: -f1 | sort -u
   ```

   Protokol má **devět vyjmenovaných metod** — `submit`, `reply`, `setResolved`, `comment`,
   `setLabels`, `requestReviewers`, `createLabel`, `merge`, `markReadyForReview`. **Každá si
   sama ověří bránu z bodu 6**, proto všechny berou adresu, ze které se pozná repo.

   **Zakázané zůstává**: approve mimo review, **zavření PR**, **milník**, **`deleteLabel`**
   a **návrat do draftu** (`convertPullRequestToDraft`) — devátá metoda je jednosměrná schválně.

   **Od #333 to hlídá test, ne jen tenhle grep** (`SingleWayOutTests` — sedm souborů, devět
   metod a jmenovitě i to zakázané). **Měnit se smí jedině na vlastním PR**
   (`Policy.metadataEditing`, u merge `Policy.mergeOffer`); na cizím se akce **nekreslí vůbec**,
   ne zašedle. Proč se výčet rozšiřoval a čím se která metoda měřila, je
   v [`docs/architektura.md`](docs/architektura.md#reviewpublisher-apppublish) —
   [#392](docs/architektura.md#labely-a-vyžádání-reviewera-392--pátá-a-šestá-metoda),
   [#413](docs/architektura.md#založení-labelu-413--sedmá-metoda-a-první-která-píše-do-repozitáře),
   [#465](docs/architektura.md#merge-vlastního-pr-465--osmá-metoda-a-první-která-mění-main),
   [#482](docs/architektura.md#ready-for-review-482--devátá-metoda-a-nejmenší-z-nich); brána
   z bodu 6 je v [záznamu
   rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí-1).

   **„Výslovný pokyn člověka“ vypadá takhle** — a je to výčet, ne příklady:

   - **potvrzovací sheet u review a u merge**: dvě kliknutí, celý payload vidět (#68, #465);
   - **odpověď do vlákna, komentář pod PR, label ani přepnutí draftu na *ready for review* se
     nepotvrzují** (#73, #216, #392, #482) — jedno pojmenované tlačítko, a u #482 k tomu **věta
     pod ním** (`Policy.readyForReviewNote`);
   - **u vyžádání reviewera je potvrzení v nadpisu nabídky** (`Vyžádat review od`);
   - **založení labelu potvrzení má** (#413) na **druhé obrazovce téhož popoveru, ne v sheetu**;
   - **žádná z těchhle akcí nemá výchozí akci**, takže se nic z toho nespustí `Enterem` —
     a **po úspěchu se zavře sheet i záložka toho PR**, jedině po
     úspěchu ([proč](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--po-mergi-se-zavírá-záložka-465));
   - **u merge je metoda od #556 volba, ne konstanta** — výchozí hodnota je v nastavení,
     potvrzení ji **vypisuje a dovolí přebít pro jeden merge**, a protokol se tím nemění ani
     o položku. Co repozitář pustí, je **čtení** (`GitHubGateway.mergeSettings(repo:)`),
     a chybějící příznak je **„nevím“, ne „nepovoluje“**
     ([rozbor](docs/architektura.md#metoda-merge-je-volba-ne-konstanta-556), [záznam
     rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--metoda-merge-je-volba-ne-konstanta-556)).

   **Uzavřený je `seznam`** — hledání **filtruje, nezakládá**; zakládání je **akce pod děličem**
   se zkratkou **`⌥↵`** na poli, barvu vybírá aplikace (`Policy.labelColor`) a **přebarvit ani
   smazat label odsud nejde**. A composer komentáře **nesmí splynout s tabem `Moje review`**
   ([proč zrovna takhle](docs/architektura.md#labely-a-reviewery-v-panelu-392)).
   **`ReviewVerdict` je pořád jen návrh a sám nic neodesílá** (od #114 se jím **předvyplňuje**
   verdikt v panelu). A pravidlo, že **mergnutý PR jde ještě dočíst a zavřít ho má člověk, ne tik
   pollingu**, se **neruší** — mluví o pollingu, kdežto záložku zavírá klik na `Mergnout`.

   **Terminál pod tuhle podmínku nespadá, a je to hranice, ne výjimka** (#453, #459, #460).
   Zásuvka je plnohodnotný shell, takže **plnou moc v něm má člověk**, ne aplikace; **padá tedy
   jen to, že se ta záruka dá dokázat testem**. Zbytek platí:

   - aplikace **sama** nic neodesílá — grep z bodu 2 vypisuje **týž seznam sedmi souborů**,
     `SingleWayOutTests` prochází **beze změny** a `TerminalHosting` nezná `gh`;
   - **musí to být vidět na obrazovce, ne jen tady**: kapsle `plná práva` v hlavičce zásuvky;
   - **tvrdá podmínka č. 3 platí beze změny**: shell startuje v cache, ne v uživatelově klonu;
   - **aplikace do toho shellu píše dvě věci a nic jiného poslat neumí**: **jednu řádku**
     (`Policy.drawerResumeCommand(sessionID:)`, `▶`; do běžícího jobu se nepíše vůbec) a
     **hlášení myši** (#478, jen když si o ně terminálová aplikace řekla);
   - **relací je v zásuvce víc než jedna** (#460), takže úklid platí **pro každou**, počet je
     **omezený** (`Policy.maxTerminalSlots`, pět) a vytlačuje se jedině **neběžící** relace.

   Co se u #459 vyměnilo za jakou záruku a jak se ten proces zabíjí, je
   v [`docs/architektura.md`](docs/architektura.md#vestavěný-terminál-459) a v záznamech
   rozhodnutí o
   [zásuvce](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--vestavěný-terminál-jako-zásuvka-459),
   o [`▶`](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí---pouští-session-v-zásuvce-460)
   a o [osudu
   `TerminalOpening`](docs/superpowers/specs/2026-07-31-prism-design.md#osud-applescriptterminal-460).
   **Merge z panelu (#465) je proti tomu ta druhá, hlídaná strana**: jde přes protokol, přes
   bránu a s potvrzením, takže se o něm dá tvrdit test.

   **Zápis do remote (#466) je druhý protokol, ne další metoda toho prvního.** `BranchPushing` má
   **jedinou metodu `push`** a přetlačí jedině větev **vlastního** PR. Grep z bodu 2 má u něj
   vypsat **tři soubory** z `App/Publish/`: protokol, `GitBranchPush` a `BranchPushSubmission`.
   **Zakázané je** `commit`, `deleteBranch`, `pushTag`, `createBranch` — a **push do základní
   větve**. Brána je **tatáž** (`PublishScope`, `allowsPublishing`), **pusher není pole
   `AppStore`**, `GitHubGateway` je dál bez zápisu a **`RepoCheckout` do remote nezapisuje**.
   **Podmínky č. 2 a 3 platí beze změny**: `Bash(git push:*)` zůstává
   v `ClaudeCommand.disallowedTools` a rebase běží ve **vlastním** stromě v cache
   (`CacheLayout.syncWorktree`) za `CacheFile.refusal`. Zbytek jsou tři výčty:

   - **Dva guardy, oba povinné a nezávislé.** (1) Cílem smí být jedině **hlava vlastního PR**,
     posuzováno proti **datům pull requestu**; `isCrossRepository == nil` je **zákaz, ne
     povolení**. (2) **`--force-with-lease` s vypsanou hodnotou, nikdy holé `--force`** — a
     **holý lease taky ne**.
   - **Dva kroky, dělené podle vratnosti, ne podle složitosti.** **Rebase** jde vzít zpět, takže
     stojí na jedno kliknutí; **force push je nevratný**, takže má **potvrzovací sheet s úplným
     výpisem** (`BranchPushSheet`) **bez výchozí akce**. Mezi kroky je stav *přerovnáno,
     nepřetlačeno* (`BranchSyncState.rebased`) — **normální stav, ne porucha**. **Lease se
     skládá z hlavy, ze které se rebasovalo** (`RebasedBranch.rebasedFrom`).
   - **Hlídá to test, ne jen grep** (`SingleWayOutTests` — tři soubory, jedna metoda, jmenovitě
     zakázané čtyři, `"push"` **jen** v `GitBranchPush`, holé `--force` nikde a čistý `Checkout/`
     i `GitHub/`).

   Rozbor je v [`docs/architektura.md`](docs/architektura.md#zápis-do-remote--branchpushing-466),
   měření obou guardů v [`docs/testovani.md`](docs/testovani.md#jak-se-změřil---force-with-lease-466)
   a zdůvodnění v [záznamu
   rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--zápis-do-remote-466).

   **Konflikty slévá session, která smí měnit soubory** (#467) — a je to změna **tvrdé podmínky
   č. 2**, ne téhle: do remote se pořád píše jedině přes `BranchPushing`, a **session na to
   nesahá**. Nerozřešený konflikt se **přiznává**: rebase zůstane rozdělaný, je to vidět
   v panelu a nabídne se zahodit i **terminál**.
2. **Reviewer je read-only.** V `--allowedTools` není `Write` ani `Edit`, u `Bash` se uvádí
   jen `git` — a v `--disallowedTools` jsou `Bash(gh:*)` a `Bash(git push:*)`. `Skill` mezi
   povolenými je (#78); sám o sobě nic nespouští, ale skill, který se přes něj načte, si
   o odeslání na GitHub umí říct — proto ten zákaz.

   Tři věci, na kterých to stojí, jsou **ověřené spuštěním** (#12, opraveno u #17): co je
   **mimo** povolený vzor, se odmítne, pokud to není na vestavěném seznamu čtecích příkazů; co
   je **uvnitř** vzoru, projde celé — `Bash(git:*)` tedy pouští i `git push` a **zavírá to až
   `--disallowedTools`**; a **seznam nástrojů z init eventu není obraz oprávnění**. Odmítnutý
   nástroj **není chyba běhu**. Čísla jsou
   v [`docs/claude-cli.md`](docs/claude-cli.md#--allowedtools-co-doopravdy-dělá).

   **Aplikace pouští čtyři vyjmenované sady a jednu prázdnou. Všechny čtyři tvrdí test literálem
   na jednom místě** (`SessionToolSetsTests`, od #467) — rozdíly mezi nimi se ze čtyř souborů
   nedají přečíst:

   | Session | `--allowedTools` |
   |---|---|
   | reviewer a **kontrola nálezů z minula** (#150), která bere **tytéž konstanty** | `Read,Grep,Glob,Bash(git:*),ReportFindings,Skill` |
   | **dotažení textu issue** (#345) — `ToolSearch` být **musí**, bez něj se MCP nástroj nedá zavolat | `ToolSearch` + **jeden čtecí MCP nástroj** (jméno v konfiguraci, `issueTextTool`) |
   | **rozhovor nad PR** (#452, tab `Zeptat se`) — **užší než reviewerova**: bez `ReportFindings` (nemá co hlásit) a bez `Skill` | `Read,Grep,Glob,Bash(git:*)` |
   | **slévání konfliktů** (#467) — **jediná, která smí měnit soubory**, a **jediná bez `Bash`e** | `Read,Grep,Glob,Write(//<strom>/**),Edit(//<strom>/**)` |
   | překlad nálezů | prázdná |

   `--disallowedTools` je u **všech** tatáž konstanta `ClaudeCommand.disallowedTools`, takže `gh`
   ani `git push` nemá **žádná**. **Materiál jde do promptu cestou k souboru, ne jako nástroj**
   (precedens #120) — diff si session přečte `git diff <base>...HEAD`. A **editovatelný prompt
   review** (#281) otevřel **prompt, ne povolení** (je na to test). Rozbory: [kontrola
   nálezů](docs/architektura.md#kontrola-nálezů-z-minula-150), [zadání pro
   reviewera](docs/architektura.md#zadání-pro-reviewera-120), [text
   issue](docs/architektura.md#text-issue-a-komentáře-pod-pr-345), [rozhovor nad
   PR](docs/architektura.md#rozhovor-nad-pr--tab-zeptat-se-452).

   **Sada, která smí psát (#467), drží čtyři meze a každá je kontrolovatelná:**

   - **`Write` a `Edit` jen ve svém stromě v cache, a je to změřená brána, ne prompt** —
     **s vypsaným rozsahem**, protože holé `Write` píše **kamkoli** a `cwd` povolený implicitně
     **není** ([čísla](docs/claude-cli.md#write-a-edit-jen-ve-svém-stromě-467)). Že strom leží
     v cache, ověřuje **tatáž kontrola jako jinde v repu** (`CacheFile.refusal`, podmínka č. 3).
   - **`Bash` v té sadě není vůbec.** Session **necommituje** (to dělá aplikace: `git add`
     a `git rebase --continue`), a bez `Bash`e je to **vlastnost sady**, ne délka seznamu zákazů.
   - **Žádné `gh` a `git push` dál v zákazu.**
   - **Druhá vrstva: co session zkusila zapsat mimo strom, se čte ze streamu** — a když se něco
     najde, výsledek se **nepřijme** (`git add` ani `--continue` neproběhnou) a řekne se to.
     I odmítnutý pokus: otázka není „povedlo se to“, ale „mířila session mimo strom“.

   `SingleWayOutTests` k tomu hlídá, že `ConflictResolving` znají **tři soubory**, volá ho
   **jedno místo** a rozsah zápisu skládá jedině `ConflictCommand`. **Sady ostatních session se
   nezměnily ani o položku**
   ([rozbor](docs/architektura.md#slévání-konfliktů--čtvrtá-session-467), [záznam
   rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--session-která-smí-psát-467)).

   ```bash
   # Výčet k posouzení: pět míst, z toho čtyři sady a jedna prázdná (překlad nálezů).
   grep -rn 'allowedTools' App/Review | grep -vE ':[0-9]+: *///?'
   # Pozor: grep na `Write(` **vyjde prázdný** — rozsah se skládá interpolací, takže ten řetězec
   # v kódu nestojí. Kdo chce ověřit, že je scoped, musí se zeptat funkce (`SessionToolSetsTests`).
   # Komentáře se odečítají u všech tří výčtů, viz podmínka č. 1 bod 2 — test hlídá kód, ne text.
   grep -rn 'ConflictResolving' App | grep -vE ':[0-9]+: *///?' |
       cut -d: -f1 | sort -u                                        # tři soubory
   grep -rn 'writingTools' App | grep -vE ':[0-9]+: *///?'          # jen ConflictCommand
   ```

   **Session z `▶` v zásuvce pod tuhle podmínku nespadá, a je to hranice, ne výjimka** (#460).
   Podmínka mluví o session, které **pouští aplikace** — o těch pěti z tabulky výš. `claude
   --resume` v zásuvce **řídí člověk ve svém shellu** a běží s `--permission-mode auto`;
   **nová práva to nedává**, odpadají **dotazy**, ne hranice.
   **`bypassPermissions` ani `--dangerously-skip-permissions` v tomhle repu nemají co dělat**
   a `⧉` režim povolení **nedostane**. Rozhoduje `Policy.drawerResumeCommand(sessionID:)`; proč
   zrovna `auto`, je v [záznamu
   rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#auto-mode-v-zásuvce-460).

   **A aplikace zapisuje do konfigurace cizího nástroje** (`~/.claude.json`,
   `WorkspaceTrusting`) — jedinou hodnotu, **důvěru ke složkám vlastní cache**. Hranici u toho
   drží čtyři věci: **na soubor, kterému nerozumí, nesáhne**; **zapisuje atomicky a zachová, co
   v souboru je**; **zapisuje jen když je potřeba**; a **hranici cache drží od #479 kontrola, ne
   konstanta** (`CacheFile.isInsideCache`; výčet vydá `Policy.workspacesToTrust`). Zapsané
   `false` **na naší cestě** se přepsat **smí**: zakládá si ho `claude` sám, není to odpověď
   člověka. Změřeno je to v [`docs/claude-cli.md`](docs/claude-cli.md#důvěra-ke-složce-a-režimy-povolení-460)
   a v [`docs/architektura.md`](docs/architektura.md#důvěra-ke-složce-a-auto-mode-460-oprava-479).
3. **Nikdy nesahat na uživatelovy klony.** Aplikace pracuje výhradně ve své cache
   (`~/Library/Application Support/PRism/`). Mohou být rozdělané, na jiné branchi,
   mít vlastní worktrees.

   **Mimo cache aplikace zapisuje na dvě místa a obojí je vyjmenované** — `~/.claude.json`
   (`WorkspaceTrusting`, viz podmínka č. 2) a od #529 **systémovou přihlašovací položku**
   (`LoginItemControlling` nad `SMAppService`). Ta druhá je jediný zápis, který přežije smazání
   bundlu, takže má tři meze: jde **jedině z přepínače na stránce `Systém`**, brána je
   `Policy.loginItemAvailability` **ve storu, ne zašedlý přepínač ve view** a **stav se čte
   zpátky ze systému**, ne z `config.json`. Hlídá to `DockBadgeWiringTests` spolu s odznakem
   v Docku: `App/Store/` nesmí znát `SMAppService` ani `dockTile`
   ([rozbor](docs/architektura.md#systém-kolem-okna--odznak-v-docku-a-spuštění-po-přihlášení-529)).

   ```bash
   grep -rn 'SMAppService\|dockTile' App | grep -vE ':[0-9]+: *///?' |
       cut -d: -f1 | sort -u    # dva soubory: Environment/LoginItemControl, Views/DockBadgeTile
   ```
4. **Aplikace nikdy nedrží GitHub token.** Autentizace je delegovaná na `gh`.
5. **Nálezy jsou klíčované `headSha`.** Nové commity nálezy zneplatní (stav
   „zastaralé“), nikdy se nesmí tiše zobrazovat proti kódu, který už neexistuje.

   **Rozhovor nad PR (#452) se tomuhle netýká, a je to zapsaná výjimka**: ukládá se **k PR, ne
   k `headSha`**, protože rozhovor není nález.

   **Značka `Prošlo` u souboru (#500) je ta podmínka nad souborem, ne výjimka z ní.** Ukládá se
   **k PR** (jako rozhovor), ale nese **otisk obsahu** — sha z `index` řádky diffu, celou
   dvojici `<základ>..<hlava>`. Tři stavy, ne dva, rozhoduje o nich
   `Policy.fileReviewState(mark:blobs:)` a **`nil == nil` je `prošlo`**; sbalení se z toho
   **odvozuje** ([proč](docs/architektura.md#značka-prošlo-u-souboru-500)).

   **Přírůstkové review (#517) tu podmínku drží nad dvěma sha, ne obchází ji.** Nález přenesený
   z minulého kola se na dnešní hlavu **přepíše** (`Finding.headSha`) a nese **odkud přišel**
   (`Finding.carriedFrom`); **do klíče nálezu původ nepatří** (`Policy.key(of:)`). Přenášejí se
   **všechny** staré nálezy včetně vyřešených a nezodpovězených; odmítnutý se **neposílá ani
   nepřenáší**. Kdy se jde na celé review, rozhoduje `Policy.reviewScope` — a **force push bez
   společné historie i nezjištěná příbuznost jsou dvě různé věty**
   ([rozbor](docs/architektura.md#review-jen-přírůstku-517)).

   **Kontrola nálezů (#150) na tom stojí, ne obchází to**: nese `againstHeadSha`, a jak se hlava
   posune, `Policy.recheck(of:head:)` odznaky nevydá. „Vyřešeno“ přitom nikdy nález nesundá, to
   smí jedině odmítnutí (#113) — a od odmítnutí se musí poznat **i pohledem**: přeškrtne se jen
   text nálezu (ne celý řádek) a `blokuje` u něj zůstává
   ([rozbor](docs/architektura.md#kontrola-nálezů-z-minula-150)).

## Architektura

Deset modulů. Pět, které sahají do vnějšího světa, je za protokolem, aby byly v testech
nahraditelné fake implementací. **`ReviewPublisher`** (#67) je jediný, který **zapisuje na GitHub
API**, a **`BranchPushing`** (#466) jediný, který **zapisuje do remote** — viz tvrdá podmínka
č. 1. **`TerminalHost`** (#459) je jediný, ve kterém **plnou moc má člověk**, ne aplikace —
tamtéž.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a syrový diff (celý, nebo mezi dvěma commity), login přihlášeného účtu, labely s vyžádanými reviewery včetně týmů, hlavy víc PR jedním dotazem, slévatelnost větve (líné pole, ptá se opakovaně), **repozitáře organizace** (#532 — nejdražší čtení v aplikaci, 46,8 s nad `keboola`, proto vlastní limit a cache), **otevřené PR jednoho repa** (#533 — 1,1 s, řadí `Policy`, protože `gh pr list` řadí podle čísla) a **co repozitář o mergi říká** (#556 — povolené metody a zdroje těla commitu, jedno volání za repo, 0,62 s, chybějící příznak = „nevím“). **Pořád bez zápisu** | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction, **rebase větve nad základem** ve vlastním stromě (`<pr>-sync`) i zahození rozdělaného rebase, **zápis slitých souborů do indexu a dokončení rebase** (`git add`, `rebase --continue` — commituje aplikace, ne session) a **je předchozí hlava předkem té dnešní** (#517 — `merge-base --is-ancestor`, odpovídá `ancestor`/`rewritten`/`unknown`) a **cesty, které PR mění** (#518 — `diff --name-only --no-renames`, podklad routingu; `gh pr view --json files` vydá jen prvních sto, změřeno). **Pořád bez zápisu do remote** | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings` a odpovědi na pokusy o nástroje. Dvě podoby běhu — review (od #517 nad celým diffem, nebo **jen nad přírůstkem** s nálezy z minula jako materiálem) a kontrola nálezů z minula — a k tomu čtyři session, které o review nic nevědí: překlad nálezů, dotažení textu issue (#345), **rozhovor nad PR** (#452, vlastní užší sada a `--resume`) a **slévání konfliktů** (#467) — **jediná, která smí měnit soubory**. Umí transcript session i **přepsat k přečtení** | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Každé rozhodnutí, které jde vyjádřit nad daty: stav řádku, blokující příznak, návrh verdiktu, řazení, filtr seznamu, hledání v paletě ⌘K, složení promptu i zadání pro agenta, obsah dashboardu a dění, geometrie, na kterou se ptá kresba, a **desítky dalších**. Úplný katalog s důvody je v [`docs/architektura.md`](docs/architektura.md#policy-apppolicy) — hledej tam podle jména funkce | — |
| `Config` | Globální default + override per repo, tolerantní čtení `config.json` | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu. **Stav v `AppStore.swift`, metody v `AppStore+*.swift`** (#154) | — |
| `ReviewPublisher` | **Jediná cesta na GitHub API**, devět metod — viz tvrdá podmínka č. 1 | `gh` CLI |
| `BranchPushing` | **Jediná cesta do remote** (#466): přetlačit větev **vlastního** PR přes `--force-with-lease`, **jedině z potvrzení**. Jedna metoda, dva guardy, tatáž brána. Rebase v tom **není** — ten je lokální práce `RepoCheckoutu` | `git` |
| `TerminalHost` | Vestavěný terminál (#459) — **víc relací na pull request** (`TerminalSlot`: holý shell a jedna na dráhu), každá vlastní pty v checkoutu toho PR, VT emulace (`SwiftTerm`), fokus pro ustupující zkratky a `SIGKILL` na popředí pty **u každé z nich**. Do relace umí napsat **jednu řádku** (`▶`), a jen když v ní nic neběží; **předá kolečko** aplikaci, která si o hlášení myši řekla. Na GitHub nesahá a `gh` nezná | login shell přes pty |

Nad tím SwiftUI views: `PRList`, `DiffView`, `ReviewPanel`. Mimo tuhle desítku stojí
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
  `AppStore.swift` drží **stav, init a polling**, metody jsou v `AppStore+*.swift`; **dělí se
  metody, ne data**;
- **`pullRequests` je plný seznam, `visiblePullRequests` je po filtru** (#117), a **rozdíl mezi
  těmi dvěma gettery je jediné, co dělí filtr od mazání cache**. Nad tím jsou dvě další zúžení
  podle autora: `queuePullRequests` (cizí, tedy fronta) a vlastní PR (#331, #332). Fronta,
  karty `Čeká na mě` a `Blokuje`, souhrn, automat, hromadné spuštění a notifikace čtou **jen
  cizí**; úklid, eviction, nastavení, nabídka filtru a rozdělaná review **obojí**
  ([tabulka](docs/architektura.md#které-místo-chce-kterou-množinu-332)). **Od #531 k tomu stojí
  přijaté záložky** (`adoptedTabs`) — PR otevřený odkazem nebo `prism://` a **od #527 i záložka
  obnovená po restartu** (`TabAdoption`) **do fronty nepatří**, ale úklid po tiku ho zahodit
  nesmí, jinak se otevřená záložka vyprázdní; obojí bere `pullRequestsInPlay(besides:)`
  a `summary(for:)`. **Obnovení nic nespouští** (#527) — jen dotáhne detail, a to čtením
  ([#531](docs/architektura.md#otevřít-pr-mimo-zdroje-531),
  [#527](docs/architektura.md#záložky-přežijí-restart-527));
- **[`Environment`](docs/architektura.md#vrstva-environment-appenvironment)** — podprocesy:
  blokující I/O nesmí na kooperativní pool, oba pipy se musí číst souběžně, **zrušení
  i ukončení aplikace musí proces zabít** (#264 — obě cesty, jedním `SIGKILL`em; zavírání se
  na něj musí **počkat**). **Ta záruka kryje jen normální ukončení** (#351): běžící session se
  proto **zapisují do cache** (`sessions.json`) a osiřelé zabije **další start** — rozpoznání
  jedině přes zapsanou identitu `(pid, startedAt)` a **jen když vlastník už neběží**, nikdy
  hledáním v `ps` ([rozbor](docs/architektura.md#osiřelá-session-po-zabité-aplikaci-351)).

## Konvence

Naměřená čísla, zamítnuté varianty a slepé uličky u každého pravidla níž jsou **za odkazem**;
čte se to **dřív**, než se pravidlo obchází, ne až potom.

- **Krátké, jednoúčelové metody.** Čitelnost před chytrostí.
- **Nepoužívat `final`** u typů, které se v testech nahrazují.
- **Protokol + fake, ne mockovací framework**, u tří modulů se vnějším světem — a stejně
  u `Environment`, kde jsou za protokolem `ExecutableProbe`, `ProcessRunning`
  a `ShellPathReading`.
- **Nové soubory drž malé a soustředěné.** Když soubor roste, obvykle dělá víc věcí.
- **Do `project.pbxproj` nesahej.** `App/` a `Tests/` jsou buildable folders
  (`PBXFileSystemSynchronizedRootGroup`) — nový zdroják = jen ho vytvořit. Editovat pbxproj je
  potřeba jen při změně targetů nebo build settings. **Tři výjimky**: `Signing.xcconfig`,
  `ASSETCATALOG_COMPILER_APPICON_NAME` (#83 — leží na **app targetu**, ne na projektu) a od #459
  **`SwiftTerm`** (`Package.resolved` je v repu); `App/Assets.xcassets` se v pbxproj
  **nevyjmenovává**. A **dva zdrojáky se stejným jménem build položí** (#184), i když leží
  v různých podsložkách — jméno souboru je v jednom targetu klíč (`Multiple commands produce …
  <Jméno>.stringsdata`), takže se pojmenovávají **jednoznačně napříč celým `App/`** (a `Tests/`).
- **Co se počítá při každém překreslení, se pamatuje — a cache si musí říct, co ji vyprazdňuje**
  (#224). Hranice musí být v tom typu vidět (`SyntaxRunCache`: strop na počet řádků i na jejich
  objem) — cache bez vyjmenované meze je únik paměti s odkladem. **A do cache smí jen to, co je
  funkcí jejího klíče** (#153): word-level zvýraznění závisí na **protějšku** dvojice, takže do
  cache klíčované `(text řádku, jazyk)` nepatří a kreslí se jako **druhá vrstva nad** ní
  ([čísla i rozbor](docs/architektura.md#appsyntax)).
- **Zlevnění, které práci jen přesune jinam, není zlevnění — a pozná se to jedině změřením obou
  konců** (#275). **Měř tu cestu, kterou kód doopravdy jde**, a co se nepodařilo zlevnit, napiš
  i s důvodem: bez toho to příště někdo zkusí znovu
  ([měření](docs/testovani.md#jak-změřit-projíždění-diffu-když-se-ho-nedá-dotknout-252)).
- **Řádky dělí `TextLines`, nikdy `split(separator: "\n")` ani `components(separatedBy: .newlines)`**
  (#292, na jedno místo svedeno #295). `"\r\n"` je ve Swiftu **jeden `Character`**, takže ta
  první cesta na `CRLF` **nerozdělí vůbec** a ta druhá vloží mezi ně prázdný řádek. Platí to na
  **všechno, co zakončení řádků nevybírá aplikace**: hlavičky, logy z CI, diffy a obsah souborů
  z cizích repozitářů. Výjimka je `String.singleLine`, a to **schválně**. A **kdo text dělí na
  dvě části, dělí obě na tomtéž znaku** (#339) — tohle grep nechytá vůbec. Zdůvodnění obojího je
  u `Character.isLineTerminator` a v
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
  zkompilovat, do `.app` jako resource. Konfigurace bundle (`Info.plist`,
  `PRism.entitlements`) proto leží v kořeni repa.
- **Jeden název všude: `PRism`.** Repo, projekt, target, scheme, produkt, Swiftový modul
  i to, co appka ukazuje v Docku. Když název měníš, projdi i `PRODUCT_MODULE_NAME`,
  `TEST_HOST`, `CODE_SIGN_ENTITLEMENTS` a `bin/run.sh` — jinak build projde, ale spadne
  až test nebo spuštění.
- **Ikona potřebuje `CFBundleIconName` v `Info.plist` napsané ručně.** Bez toho klíče se ikona
  **zkompiluje** a v bundlu leží, jen ji systém nenajde a v Docku zůstane prázdný obdélník.
  A **po překreslení ikony se musí restartovat Dock** (`killall Dock`) — cache ikon je vázaná na
  cestu k `.app`, která se rebuildem nemění. **`CFBundleName` navíc nejde nastavit přes
  `INFOPLIST_KEY_*`** (Xcode ho generuje z `PRODUCT_NAME` a klíč tiše ignoruje), proto má
  projekt vlastní `Info.plist` místo `GENERATE_INFOPLIST_FILE`.
- **Moduly jsou složky, ne targety.** Všechen kód žije v jednom app targetu; `Policy`
  a spol. jsou podsložky `App/`. Framework by si vynutil `public` u všeho, co používá
  UI — daň, kterou osobní aplikace nepotřebuje. Vyčlenit se dá později.
- Chybové stavy jsou v návrhu vyjmenované ([specifikace, *Chování při
  chybách*](docs/superpowers/specs/2026-07-31-prism-design.md#chování-při-chybách))
  — každý z nich má mít v UI vlastní rozlišitelný stav. `čisté` (žádné nálezy) a
  `failed` (session spadla) se nesmí slít do jednoho — a od #383 je mezi nimi **třetí**:
  `inconclusive` (doběhlo, ale čisto z toho neplyne). Rozhoduje o něm
  `Policy.inconclusiveReason(of:)`, což je **jediné místo** — a když se ptáš, jestli běh kód
  doopravdy otevřel, tak `Policy.codeReading(of:)`, kde `unknown` je odpověď, ne slabší
  „nepřečetl“. **Od #518 je totéž o dráze**: `přeskočeno` (routing) není ani `nespuštěno`, ani
  `čisto` ([rozbor](docs/architektura.md#routing-reviewerů-podle-změněných-cest-518)).

### Kresba, rozvržení a výkon v okně

Každé pravidlo níž vzniklo z **naměřeného** tuhnoucího okna nebo z rozbité kresby. Tady stojí jen
věty pravidel, jména míst, kde se rozhoduje, a grepy; **co se měřilo, jaká vyšla čísla, co se
zamítlo a co byla slepá ulička, je za odkazem** — a přečti si to **dřív, než pravidlo obejdeš**,
protože většina z nich se v harnessu neprojeví.

- **Rozměr se nenechává vyjednávat, když se dá spočítat** (#220) — šířka se **předává**
  (`availableWidth`, `narrowingWidth`, `filling` v `App/Views/AvailableWidth.swift`), protože
  `frame(maxWidth: .infinity)` stojí **~5,5× na úroveň** zanoření.
- **Kdo si šířku rozdělí na kolony, musí ji předat i zúženou** (#546) — a **kdo paduje kolem
  `filling()`, o to zúží prostředí** (`narrowingWidth(by:)`, **jedna** konstanta na `padding`
  i zúžení). `filling()` je přibití na hodnotu z prostředí, ne pružnost
  ([rozbor](docs/architektura.md#kdo-paduje-kolem-filling-musí-o-to-zúžit-prostředí-546),
  [měření](docs/testovani.md#neověřená-mezera-71-znaků-na-stranu-v-živém-okně--vyřešeno-546)).
- **Pružná výška v řádku líného seznamu je zakázaná taky, ale z jiného měření** (#375) — zakázaná
  je **v řádku**, ne plošně, a cena se **neodhaduje z tabulky pro šířku**; ohraničené formy jsou
  [vyjmenované](docs/architektura.md#šířka-v-okně-appviewsavailablewidthswift).
- **Rozměr nevyjednává líný seznam** (#361) **ani obsah okna** (#472) — oba ho dostanou změřený
  (`fillingSlot()`); hlídá to `LazyIdealSizeTests`
  ([líný seznam](docs/architektura.md#fillingslot--líný-seznam-rozměr-nevyjednává-vůbec-361),
  [obsah okna](docs/architektura.md#obsah-okna-dostane-změřenou-štěrbinu-472)).
- **`LazyVStack` v diffu ani na ose konverzace nepatří, a je to změna proti #361** (#469) —
  neomezenost seznamu není důvod ten vzor snést. Diff kreslí **pevný `VStack`** a laznost je
  jedno rozhodnutí: blok kódu má živý `NSTextView` jen v pásu kolem výřezu
  (`Policy.mountBand(visible:)`, `DiffBlockSlot`), scrollování se zapisuje jedině do
  `DiffViewport`; hlídá to `DiffMountingTests`. `List` je změřený a **zamítnutý** (posuvník lže),
  hlídá to `ConversationAxisEagerTests`
  ([čísla i ablace](docs/architektura.md#pevný-seznam-a-nasazování-bloků-469),
  [cena `Listu`](docs/architektura.md#patnácté-kolo-osa-líný-seznam-nemá-361)).
- **Nevyjednává se ani počet prvků** (#252) — plochu, gesto a čtení geometrie nad blokem kódu
  počítá **jednou** `DiffGutterGeometry`. A co se při scrollování mění, **nesmí být ve `@State`**
  ([rozbor](docs/architektura.md#appdiff)).
- **Kdo čte posun výřezu, je vyjmenovaný — a čte ho v modifikátoru, ne v těle** (#503). Kdo
  potřebuje rozhodnout **co kreslit**, bere **pás** (`DiffViewport.band`), ne `top` — karty
  v okraji se proto nasazují jako bloky (`Policy.isBlockMounted`). Hlídá to
  `DiffMarginScrollReadTests` nad zdrojáky ([rozbor](docs/architektura.md#nálezy-v-okraji-503),
  [měření](docs/testovani.md#co-stojí-okraj-s-kartami-nálezů-503)).
- **Krabice, ze které se kreslí, hlásí předfiltr a jedině při změně** (#503). `DiffRowFrames`,
  `DiffFileExtents` a `DiffBlockPlacement` sledované **nejsou**; `DiffMarginAnchors` sledovaná
  **je**, a zápis do ní má stráž na rovnost. **Nezměřený blok nehlásí ani prázdno.** A **rámečky
  řádků se předávají argumentem, ne přes `@State`**.
- **Stráž proti opakovanému uplatnění musí žít aspoň tak dlouho jako stav, který mění** (#506) —
  stav i stráž chodí **parametrem** od toho, kdo je kreslí (`DiffColumnActions`,
  `panelExpanded`), a jejich `nil` znamená **„nic nepřepisuj“**. V harnessu se to neprojeví
  ([rozbor](docs/architektura.md#stráž-automatiky-patří-ke-stavu-ne-k-diffu-506-třetí-kolo),
  [měření](docs/testovani.md#jak-se-našlo-někdy-se-ten-levý-panel-zavře-506)).
- **To pravidlo se dá splnit napůl, a pak se ptej „kde stav končí“, ne „kdo je nejbližší rodič“**
  (#506, čtvrté kolo) — stav sloupce žije v `UserDefaults`, takže stráž bydlí ve store
  (`AppStore.appliedSideColumns`), jako `isReviewPanelExpanded`.
- **A uplatnit se smí jen to pole, o kterém se rozhodlo jinak než minule** (#506, čtvrté kolo) —
  rozhoduje `Policy.sideColumnsToApply`, kde `nil` u pole je **„nechat být“**, ne „složit“.
  **A když připomínka přijde podruhé, měřidlo z prvního kola tu druhou příčinu nevidělo**
  ([rozbor](docs/architektura.md#dvě-cesty-kterými-se-volba-přepisovala-dál-506-čtvrté-kolo),
  [měření](docs/testovani.md#pořád-se-ten-itinerář-zavírá--čtvrté-kolo-506)).
- **V líném seznamu se neiteruje pole tuplů** (#361): `ForEach(Array(x.enumerated()),
  id: \.element.id)` čte identitu **přes tuple**, takže u enumu s asociovanými hodnotami
  **kopíruje** payload při každém dotazu. Identita patří do **uloženého pole**
  (`ConversationRow`), index se dopočítá v `Policy`
  ([měření](docs/testovani.md#projíždění-kolečkem-a-co-z-něj-u-361-vyšlo-361)). Plošný grep
  prázdný vyjít **nemůže**: `id: \.offset` payload nekopíruje a u prvků, které se legitimně
  opakují, je pořadí **jediná** správná identita.

```bash
grep -rn 'maxHeight: .infinity' App/Views/ConversationNodeView.swift | grep -vE ':[0-9]+: *//'
grep -rn 'maxHeight: .infinity' App | grep -vE ':[0-9]+: *//'    # výčet k posouzení, ne prázdný
grep -rn 'fillingSlot' App/Views | grep -vE ':[0-9]+: *//'       # osm míst + modifikátor sám
# Výčet k posouzení (#546), ne prázdný: `padding` **před** `filling()` je odsazení uvnitř přibité
# šířky a je v pořádku; vadný tvar je `filling()` **před** odsazením — a to grep nepozná.
grep -rln 'filling(' App | while read -r f; do grep -q 'padding(' "$f" && echo "$f"; done
# Prázdný (#361, #469) — filtr zahazuje komentáře, ve kterých se to rozhodnutí vysvětluje.
grep -n 'LazyVStack' App/Views/ConversationView.swift App/Views/DiffView.swift |
    grep -vE ':[0-9]+: *//|:[0-9]+: *///'
grep -rn 'LazyVStack\|LazyVGrid' App | grep -vE ':[0-9]+: *//'   # výčet: má ten seznam strop?
grep -n 'ForEach(Array(' App/Views/ConversationView.swift App/Views/ThreadBubbleView.swift
grep -rn 'ForEach(Array(' App | grep -vE ':[0-9]+: *//'          # výčet k posouzení, ne prázdný
```

- **`@Observable` sleduje po vlastnostech, takže hrubá vlastnost je výkonová vada** (#469, znovu
  #472). Naopak **psát „jen změnu“ nemá smysl**: zápis téže hodnoty toolchain nehlásí (pinuje to
  `PollObservationTests`). **Neplatí to ale u hodnoty, kterou nejde porovnat** (#421) — mapa
  s hodnotou, která `Equatable` není, se neporovnává, takže ji bezpodmínečný zápis hlásí **i když
  je prázdná**; z čtyřiačtyřiceti map, které prořezává `forget(whatIsNotIn:)`, má tuhle podmínku
  jedině `diffSearches`. **„Hrubé místo čtení“ z toho pravidlo NENÍ, je to zamítnutá varianta**
  (#421) — kdo to zkusí znovu, ať měří **čas**, ne počty průchodů ([*Co zašpiní tělo
  `DiffView`u*](docs/testovani.md#co-zašpiní-tělo-diffviewu-nad-nečinným-diffem-421),
  [čísla u #472](docs/architektura.md#pět-vlastností-ne-jeden-pollstate-472)).
- **Cenu přerovnání okna drží rozvržení, ne naše kód** (#472) — vlastní práce aplikace je ve
  `sample`u **~1,5 %** hlavního vlákna, takže **napřed změř, která část scénáře je drahá**
  ([čísla](docs/testovani.md#kolik-stojí-přerovnání-okna-472), [*Čtyři zlevnění, která se změřila
  a zahodila*](docs/testovani.md#čtyři-zlevnění-která-se-změřila-a-zahodila)).
- **Animace, která nikdy nedoběhne, nesmí být ve SwiftUI** (#350) — `repeatForever` si vyžádá
  průchod při **každém obtažení obrazovky**. Nekonečné otáčení patří na `CALayer`
  (`SpinningRingView`), krátká animace na gesto ve SwiftUI zůstat může
  ([čísla](docs/architektura.md#nekonečné-animace-v-okně-350)).
- **Zpětná vazba z každého snímku nesmí zapisovat do `@State` bezpodmínečně** (#358):
  `onContinuousHover` dostane polohu i tehdy, když se myš **nehnula**. Rozhoduje
  **`Policy.hoverChange(from:to:)`**, na jednom místě schválně. Dvě neintuitivní věci: hodnota
  stavu **musí být `Equatable`** (tuple ve Swiftu není) a předat ji **nejde přes `inout`**.
- **`onGeometryChange` do téhle třídy nepatří** (#361) — při nezměněné hodnotě se **nespustí**;
  u **`.onHover` to ověřené není**
  ([co zbývá doměřit](docs/testovani.md#proč-na-358-není-sonda-a-je-to-změřené-358)). **„Akce se
  nespustí“ ale neznamená „nestojí to nic“** (#438): `of:` closure běží **uvnitř aktualizace
  grafu**, takže modifikátor **nepřipojuj tam, kde výsledek nikdo nepřečte**, a podmínku dej
  **před** čtení, ne do akce.
- **`updateNSView` chodí i tehdy, když se hodnota nezměnila** (#393) — volá ho každý přepočet
  geometrie, ne změna dat. Co je v něm lineární v délce obsahu, se musí schovat za **klíč uložený
  v `Coordinator`u** (`DiffBlockDrawing` = obsah + styl + **šířka**). **Netýká se to všech
  representable, a je to změřené**: dostane ho ten, který si **říká o vlastní velikost**
  (`sizeThatFits`) ([tři neintuitivní věci](docs/architektura.md#stráž-v-updatensview-393)).
- **V AppKitu není „bez barvy“ dědění, ale černá** (#393) — barva se nasazuje **jako základní
  atribut celého řetězce** a syntaxe ji přepisuje; hodnota je `Palette.ink`, ne poloprůhledný
  `labelColor`. A **kontrast paletového tokenu netvrdí nic o kresbě**.
- **Odznak v Docku si aplikace kreslí sama, `badgeLabel` je změřená slepá ulička** (#529) — Dock
  ho u aplikace, která si o `.badge` neřekla, **potichu zahodí**. Kreslí to `DockBadgeTileView`
  do `dockTile.contentView`, geometrii vydává `Policy.dockBadgeLayout`, hlídají to
  `DockBadgeTileRenderTests` a `DockBadgeWiringTests`. **Je to nejdražší případ pravidla z #478
  v tomhle repu** ([postup měření](docs/testovani.md#šest-zelených-sad-a-v-docku-nic--jak-se-to-našlo-529),
  [zamítnutá varianta](docs/architektura.md#odznak-si-aplikace-kreslí-sama--badgelabel-je-změřená-slepá-ulička)).
- **Sémantická škála se kreslí z palety, nikdy ze systému** (#432). Ze systému **zůstávají tři
  věci**: `.secondary`, `.purple` u `merged` a `.blue` u `renamed` — ta je zapsaná mezera, ne
  záměr ([záznam
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
  který si tutéž klávesu bere, zakáže** (#452, `Policy.claimsReturnShortcut`). Dvě tlačítka se
  stejnou kombinací nejsou chyba ani pád — vyhraje to zaregistrované později; rozhoduje
  `Policy.windowShortcut(_:)` a překládá to jediné místo (`WindowShortcutButtons`,
  `View.windowShortcut(_:)`), popiska se **odvozuje**. Dvě tlačítka se **stejnou akcí a jinou
  klávesou** jsou naopak v pořádku — česká klávesnice má pod `1`–`5` znaky `+ ě š č ř`. Hlídá to
  `WindowShortcutsTests` a **dvě** stráže nad zdrojáky: kde se zkratka **registruje**
  (`grep -rn 'keyboardShortcut(' App`) a kde se **kreslí** (`⌘`/`⌥` v řetězcovém literálu) —
  obojí **výčet, ne prázdný**. Že klávesa zabere, se v harnessu ověřit nedá; zkouší to člověk,
  a u zkratek s číslicí **na obou mapách** ([katalog](docs/architektura.md#katalog-klávesových-zkratek-441)).
- **Fokus a posun scrollu se nastavují o průchod později, ne časovačem** (#184, potřetí #392;
  scroll #325) — dělá se `.task` s jedním `Task.yield()`, protože rozhoduje **počet průchodů, ne
  čas**. Posun navěšený na **data** doběhne moc brzo, takže se sleduje **geometrie**; konec
  vydává `Policy.stepFeedReaction` ([rozbor](docs/architektura.md#živý-výpis-kroků-v-tabu-průběh-325)).
  **Fokus jde ověřit jedině na běžící aplikaci**, takže **do popisu PR patří, že tuhle věc ověří
  člověk** ([jak se měří](docs/testovani.md#jak-změřit-fokus-a-klávesy-184)).
- **`scrollTo(id, anchor:)` umisťuje cíl, ne řádek v něm** (#152) — cílem je od #157 **blok**,
  takže podíl výšky počítá `Policy.jumpAnchorY` z `DiffJumpSpot`, a **podíl mimo `0…1` je správná
  odpověď, ne chyba**. **Rozměry se berou změřené** (`DiffRowFrames`), ne dopočítané z počtu
  řádků, a **skok se neanimuje**. Kde cíl přistane, se měří **v souřadnicích okna**
  ([čísla i dvě zamítnuté varianty](docs/architektura.md#kam-skok-posadí-cílový-řádek-152)).
- **Kdo si říká o velikost, musí ji měřit na tom, na čem kreslí** (#236) — dvě místa znamenají
  dvě pravdy o jedné šířce. Testuje se proti **layout manageru** a **přes pásmo šířek**, protože
  u jedné šířky test projde ([rozbor](docs/architektura.md#appdiff)). Do téhle třídy patří
  i **„je tam vodorovný pruh?“** ([#422](docs/architektura.md#trvalý-vodorovný-pruh-ve-split-pohledu-422)),
  **šířka dokumentu u textu kresleného jinde než na `x: 0`** (`DiffTextView.naturalWidth`,
  počítaná **po řádcích**) a **pruh, který jede s výřezem**
  ([#428](docs/architektura.md#pruh-který-jede-s-výřezem-428)). **A rozměr, ze kterého se počítá,
  se měří — nenasazuje se rámcem** (#325). U výšky řádku navíc nesmí rozhodovat **ikona** — SF
  Symboly jednu výšku nemají, takže je srovná `imageScale(.small)`.
- **`overlay`, který přesahuje plochu rodiče, ořízne každý ořezávající předek** (#483), a v tomhle
  okně jsou dva: `ScrollView` a `clipShape`. Co má viset nad polem, se proto kotví na tom
  předkovi, který **neořezává** — u emotikonů `EmojiSuggestionBox`, jeden na majitele. `popover`
  to neřeší: bere fokus ([rozbor](docs/architektura.md#našeptávání-emotikonů-483), [jak se zjistí,
  co ořezává](docs/testovani.md#jak-zjistit-co-ořezává-483)).
- **Sheet dostane `idealWidth` jedině s `presentationSizing(.fitted)`; `idealHeight` si vezme i bez
  něj** (#327, ta asymetrie změřená u #491). **V okně `Settings` scény je mrtvé obojí** a oživit
  to nejde. S `.fitted` a pružným rámcem sheet navíc dostane `.resizable` do `styleMask`u, takže
  se dá **roztáhnout myší**. Kdo si velikost pamatuje, musí vědět, že se **sheet rozvrhuje
  dvakrát a v prvním průchodu má podlahu**
  ([rozbor](docs/architektura.md#sheet-se-dá-roztáhnout-a-velikost-si-pamatuje),
  [čísla](docs/testovani.md#co-dělá-ideal-u-sheetu-a-v-okně-settings-491)).

  ```bash
  # Sheety hlídá `SheetSizingTests`, tomuhle grepu zbývá zbytek — výčet k posouzení, ne prázdný.
  grep -rln 'idealWidth' App/Views
  ```

## Testování

Katalog toho, co se u které oblasti testuje a proč zrovna to, je v
[`docs/testovani.md`](docs/testovani.md) — i s návodem, **jak si zkontrolovat, jak view
vypadá** (offscreen render, accessibility). **Naměřená čísla i technika měření jsou tam**, ne
tady; u každého pravidla níž je odkaz.

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
- **Test netvrdí nic o globálním stavu procesu a nezapisuje do něj** (#367). Kdo potřebuje
  vynucený vzhled, nastaví ho na **svém** okně (`AppearanceSwitchProbe`) nebo obalí kreslení
  `performAsCurrentDrawingAppearance`; „kdo smí sáhnout na globál“ se tvrdí nad **zdrojáky**
  (`GlobalAppearanceTests`,
  [proč](docs/testovani.md#globální-stav-procesu-se-v-testech-neměří-367)). Tentýž kořen má
  **pět podob** a každá už jednou udělala `main` falešně červený, nebo **vyrobila falešné měření**;
  u každé je helper nebo jedna hodnota v projektu, která se místo globálu bere:

  - **`UserDefaults`, a ten přežije běh** (#411) — výchozí `PRISM_SLOT` v projektu je
    `.testhost`, takže `@AppStorage` ani `UserDefaults.standard` nepíšou do nastavení, které se
    používá. Kdo potřebuje `UserDefaults`, bere si **`ScratchDefaults`** (jméno s `UUID`, protože
    pojmenovaná doména je sdílená **napříč procesy**, a úklid po sobě); hlídají to
    `ProcessPreferencesTests`
    ([podrobnosti](docs/testovani.md#userdefaults-je-tentýž-případ-a-měl-tři-projevy-411)).
  - **Cache hostitele, a #411 to nechalo otevřené** (#421) — identita hostitele stojí na **dvou**
    hodnotách a #411 dalo výchozí jen jedné: `PRISM_SLOT` (bundle ID) měl `.testhost`, kdežto
    `PRISM_SLOT_LABEL` (`CFBundleName`, tedy **kořen cache**) zůstal prázdný, takže `xcodebuild
    test` pouštěl aplikaci nad cache hlavní instance. Od #527 to i **měřilo**: host si obnovil
    záložky uživatele, dotáhl k nim diff skutečnými dotazy na `gh` a jeho průchody tělem se
    přičetly k sondě #421 (`DiffView` 26 proti 14, a nereprodukovatelně). Hlídá to
    `ProcessPreferencesTests` **dvěma** tvrzeními — kořen cache za běhu a `PRISM_SLOT_LABEL`
    v `project.pbxproj` ([rozbor](docs/testovani.md#cache-hostitele-je-čtvrtý-projev-téhož-421)).
  - **Metrika písma se čte na jednom místě** (#407) — `NSFont` v testovacím hostu pod zátěží
    vydá **přechodně nepoužitelnou metriku** a sazba tím písmem navíc **položí proces**. Vydává
    ji proto **`FontMetric`**; hlídají to dvě tvrzení nad zdrojáky ve `FontMetricTests`
    ([rozbor](docs/testovani.md#metrika-písma-je-tentýž-kořen-v-jiné-podobě-407)).
    **A od #550 je nepovedené měření `nil`, ne nula**: nulu vydávají `characterWidth` a spol.,
    protože z nich kreslí okno a to čekat nesmí — kdo se potřebuje **dočkat**, bere
    `TestWait.settledFontMetric(_:of:)`, a v `Tests/` je to podmínka, ne nabídka
    ([proč](docs/testovani.md#páté-kolo-stráž-nad-surovým-textem-a-nula-z-měřidla-550)).
  - **Událost skládaná pro test nesmí dědit živý stav procesu** (#490) —
    `CGEvent(scrollWheelEvent2Source: nil, …)` nese **modifikátory, které měl člověk zrovna
    zmáčknuté**. Skládá se proto **jedině v `Tests/Support/WheelEvent.swift`** (privátní stav
    zdroje **a** `flags` z argumentu) a **`waitUntil` ani `.disabled` to neřeší** — není na co
    čekat. **Stráž nad zdrojáky porovnává text bez mezer** (`Source.condensed`), protože ve Swiftu
    je mezera uvnitř volání volná — **od #550 to dělají všechny čtyři**, a mezerou se obejde jedině
    vzor, ve kterém je hranice (tečka, závorka, operátor); jeden identifikátor rozdělit nejde.
    Seznamy výjimek jsou přitom **cesty, ne text**, takže se nezhušťují. Explicitní továrny
    AppKitu (`NSEvent.keyEvent(with:…)`) v zákazu nejsou — modifikátory berou z argumentu
    ([měření](docs/testovani.md#událost-skládaná-pro-test-nesmí-dědit-živý-stav-procesu-490),
    [páté kolo](docs/testovani.md#páté-kolo-stráž-nad-surovým-textem-a-nula-z-měřidla-550)).
  - **Okno se v testu ukazuje bez animace** (#462) — `orderFront` na okně s výchozí
    `animationBehavior` si drží **vlákno z globálního dispatch poolu** po celou dobu animace, a
    `SubprocessRunner` z téhož poolu bere vlákna na blokující čtení pip. Ukazuje se proto přes
    **`orderFrontUnanimated()`** z `Tests/Support/UnanimatedWindow.swift`; hlídá to
    `UnanimatedWindowTests` ([rozbor i jak se zaseknutý běh pozná od `Early unexpected
    exit`](docs/testovani.md#zaseknutý-plný-běh-okno-které-se-objeví-s-animací-462)).

  Osm grepů. Pět **musí vyjít prázdných** (guard soubory se odečítají — hledané řetězce v nich
  stojí jako literály), šestý v `App/` **musí vypsat jen `FontMetric.swift`**, sedmý je **výčet
  k posouzení: tři soubory** (stráž, sonda a `CodeTextSheetSizingTests`, která schválně čte touž
  nečekající cestou jako aplikace) a osmý je **výčet, ve kterém žádná hodnota nesmí být prázdná**.
  **Pozor, tyhle grepy hledají v surovém textu, kdežto stráže v kódu bez mezer** — prázdný grep
  tedy sám nestačí, rozhoduje běh testů:

  ```bash
  grep -rn 'NSApp.appearance\|NSApplication.shared.appearance' Tests |
      grep -vE ':[0-9]+: *//' | grep -v GlobalAppearanceTests
  # `--include`, protože stráž čte zdrojáky: v `Tests/Fixtures/` leží skutečný diff, ve kterém
  # to jméno stojí legitimně (je to náš `project.pbxproj` z doby přejmenování).
  grep -rn --include='*.swift' 'UserDefaults.standard\|UserDefaults(suiteName: "' Tests |
      grep -vE ':[0-9]+: *//' | grep -v ProcessPreferencesTests
  grep -rn --include='*.swift' '"com.ondrajodas.prism"\|/Applications/PRism.app' Tests |
      grep -vE ':[0-9]+: *//' | grep -v ProcessPreferencesTests
  # `--exclude` odečítá dva soubory (helper a stráž nad ním) **cestou**, ne obsahem řádku:
  # `grep -v WheelEvent` by minul volání na řádce, kde to jméno stojí taky.
  grep -rn --exclude='WheelEvent*.swift' 'CGEvent(' Tests | grep -vE ':[0-9]+: *//'
  # Prefix `UnanimatedWindow` odečítá dva soubory: helper a stráž nad ním.
  grep -rn 'orderFront(\|orderFrontRegardless(\|makeKeyAndOrderFront(' Tests |
      grep -vE ':[0-9]+: *//' | grep -v UnanimatedWindow
  grep -rn 'maximumAdvancement\|defaultLineHeight\|boundingRectForFont' App | grep -vE ':[0-9]+: *//'
  grep -rn 'FontMetric.shared.characterWidth(\|FontMetric.shared.lineHeight(\|FontMetric.shared.boundingHeight(' \
      Tests | grep -vE ':[0-9]+: *//'
  # Výčet k posouzení (#421): prázdná hodnota znamená, že hostitel testů pracuje v cache aplikace.
  grep -n 'PRISM_SLOT\b\|PRISM_SLOT_LABEL' PRism.xcodeproj/project.pbxproj
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
  privátního API rozhoduje **pád v testu v hostu**, ne odhad z footprintu (#361).
- **Usazení scény se pozná měřením, ne uplynulým časem** (#421, mění postup z #489) —
  `spinMainRunLoop` je **synchronní smyčka držící hlavní actor**, takže rozvrhne okno, ale
  rozdělanou práci scény (`.task`, dotažení, hodiny pollingu) k ní nepustí; ta se rozběhne teprve
  v úseku, ve kterém sonda poprvé `await`ne, a **připíše se tomu úseku**. Čeká se proto na dvě tichá
  kola počitadel (`settleUntilQuiet`), hodiny sondy musí **doopravdy spát** a k číslům patří **počet
  dotazů na fake gateway**, aby se poznaly tiky, které si nikdo nevyžádal
  ([rozbor](docs/testovani.md#dvě-věci-které-to-měřidlo-lhaly)).
- **Měřidlo, které vydá tutéž hodnotu pro „funguje“ i „nefunguje“, netvrdí nic** (#478) — a vypadá
  u toho zeleně. Když měření končí větou „neopravovalo se nic“, patří k němu druhá otázka:
  **naměřilo by rozdíl, kdyby ta chyba byla?**
  ([rozbor](docs/testovani.md#kolečko-v-zásuvce-478--co-jde-tvrdit-bez-pty))
- **Testy se nespouštějí rourou do `grepu`** — viz *Příkazy* níž, umí to zaseknout na neurčito.

## Příkazy

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex build
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test
```

**`-derivedDataPath build.noindex` patří i k testům** (#139). `xcodebuild test` **spouští**
testovacího hosta, a spuštění bundle ho zaregistruje v LaunchServices — bez toho přepínače je
PRism ve Spotlightu navždycky dvakrát. Do `build.noindex/` míří i `bin/run.sh`, takže tenhle
záznam uklidí příští spuštění skriptu: je to **tatáž cesta**, kterou odregistrovává.

```bash
./bin/run.sh                           # build v Debug, instalace do /Applications, spuštění
./bin/run.sh --diagnose                # totéž + diagnostika kreslení (#361, #412)
./bin/worktree.sh a issue-231-neco     # strom pro paralelní vývoj ve slotu „a“ (#228)
./bin/slot-config.sh                   # očištěná konfigurace do cache slotu (#262)
./bin/slot-cleanup.sh                  # ukliď po slotu: bundle, cache, ~/.claude.json, UserDefaults, LS
./bin/setup-signing.sh                 # jednorázově: certifikát + Signing.local.xcconfig
swift bin/make-icon.swift [split] [/tmp/x]    # překreslí ikonu do App/Assets.xcassets
swift bin/make-emoji.swift                    # přegeneruje katalog emotikonů (#483)
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
zaseknuté testy — přitom testy doběhnou za sekundu. Když se zdá, že test run visí, první
věc je pustit ho do souboru.

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
  měřením, ne opatrností, a **připnutí drží všechny příkazy v repu beze změny** — kdo půjde
  nahoru, mění tři z nich a instaluje komponentu Xcode ([čím se to
  změřilo](docs/superpowers/specs/2026-07-31-prism-design.md#swiftterm--první-závislost-třetí-strany-v-tomhle-repu)).
  Rozpouští se při prvním buildu, takže je **potřeba síť** — `Package.resolved` je v repu
- **Podpis je stálý, ne ad-hoc** (#61). `Signing.xcconfig` drží ad-hoc default a přes
  `#include?` si tahá gitignorovaný `Signing.local.xcconfig` s jménem certifikátu, který
  vyrobí `bin/setup-signing.sh`. Ad-hoc podpis nemá stálou identitu, takže po každém buildu
  je to pro macOS jiná aplikace a **udělená TCC povolení propadnou** (podrobnosti v README,
  sekce [*Podpis*](README.md#podpis)). Dvě věci, na které se u toho naráží: **identita se nesmí
  zadrátovat do `project.pbxproj`** (build s certifikátem, který na stroji není, skončí chybou
  — proto je fallback v checkovaném xcconfigu a jméno v tom lokálním), a
  **`CODE_SIGN_IDENTITY` je jen na úrovni projektu** (v buildSettings targetů by přebilo
  xcconfig a lokální soubor by neměl žádný efekt).
- **Binárky hledej absolutní cestou.** GUI aplikace spuštěná z Finderu nedědí `PATH` ze
  shellu, takže `gh` se podle jména nenajde. Řeší `BinaryLocator` při startu; cesty se
  berou z `ToolPaths`, nikdy z názvu binárky.
- **Aplikace se provozuje z `/Applications`** (#88). Odjinud macOS nepovolí notifikace —
  změřeno ([`docs/architektura.md`](docs/architektura.md#vrstva-environment-appenvironment)).
  `bin/run.sh` tam bundle instaluje sám; `build.noindex/` zůstává jen místem, kde se buildí.
- **Buildí se do `build.noindex/`, ne do `build/`** (#139). Bez té přípony si LaunchServices
  kopii **samo zaregistruje** a ve Spotlightu pak stojí dva PRismy se stejným jménem, ze
  kterých se nedá vybrat. **Samotná přípona nestačí:** Xcode bundle na konci buildu registruje
  výslovně a `xcodebuild test` ho navíc **spouští**, takže `bin/run.sh` po instalaci tu jednu
  cestu odregistruje — a protože do `build.noindex/` míří i testy, uklidí tím i po nich.
  Selhání se **hlásí, ale nepokládá skript**. Od #398 je to **jedno volání, které navíc zametá
  záznamy o cestách, na kterých na disku nic není** — zaniklé worktree, staré slotové bundly,
  testovací hosty (`prism_sweep_registrations` v `bin/lib/bundles.sh`, sdílené
  s `bin/slot-cleanup.sh`); co na disku je, se nedotkne, takže cizí ani sousedovu aplikaci to
  vzít nemůže. Dvě neintuitivní věci u toho jsou **změřené** ([záznam
  rozhodnutí](docs/superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--co-po-sobě-slot-nechává-398-399)).

## Stav

Co je hotové a co zbývá, je v [`docs/stav.md`](docs/stav.md) — souvislý záznam včetně toho,
co se cestou rozhodlo jinak, než bylo v zadání. **Aktualizuje se, jak fáze ubývají.**

Rozsah v1 podle specifikace je hotový; hotové jsou i milníky M6 (odesílání review), M7
(konverzace) a M8 (notifikace), tedy poslední naplánované. Co přijde teď, jde přes issues.
