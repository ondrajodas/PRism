# CLAUDE.md

Pravidla pro práci Claude Code v tomto repu.

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
| [`docs/testovani.md`](docs/testovani.md) | Katalog toho, co se u které oblasti testuje a proč zrovna to | Nová oblast testů, nebo nový případ, který se dá pokazit potichu |
| [`docs/navrh.md`](docs/navrh.md) | Kde je vizuální návrh a jak se s ním pracuje — čtení CSS, aktualizace, render vedle screenshotu | Změna postupu při práci s mockupem (samo pravidlo je v `CLAUDE.md`) |
| [`docs/stav.md`](docs/stav.md) | Co je hotové a co zbývá | Dokončené issue |
| [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) | Jak se vyřizuje **seznam** issues: co jde souběžně, co dostane subagent, co si nechává orchestrátor, kdo merguje | Změna postupu při dávce, nebo toho, co si subagent ani orchestrátor nesmí dovolit |
| `docs/superpowers/specs/` | Proč jsou rozhodnutí taková, jaká jsou — včetně zamítnutých alternativ | Změna návrhového rozhodnutí; zapsat i **proč** se změnilo, staré nechat v záznamu rozhodnutí |

Když se změna nikam z toho nevejde, je to signál, že jsem si neujasnil, co vlastně měním
— vyřešit to, ne to přeskočit.

Konkrétně: přidání modulu → `docs/architektura.md` + tabulka modulů v `CLAUDE.md`
+ `README.md` (struktura, pokud se mění). Změna konfigurace → `README.md` (klíčová
rozhodnutí) + specifikace. Nový build příkaz → `README.md` + sekce Příkazy níž. Zahození
návrhového rozhodnutí → specifikace, včetně důvodu.

**`CLAUDE.md` se drží malý, a je to podmínka, ne estetika** (#162). Copilot si ho bere jako
custom instructions se stropem 110 tisíc tokenů — když ho přeroste, review na PR **vůbec
nedoběhne** a v okně po něm zbude jen nicneříkající chyba. Podrobnosti proto patří do `docs/`;
sem se píše jen to, co je potřeba znát dřív, než se něco napíše.

## Jazyk

- **Dokumentace, specifikace, komentáře a prózu piš česky.** Včetně tohoto souboru,
  README a všeho v `docs/`.
- **Identifikátory v kódu anglicky** — názvy typů, funkcí, polí, souborů, flagů:
  `blockingCategories`, `headSha`, `ReviewRunner`. Kód se česky nepíše.
- **Issues celé česky** — titulek i popis.
- **Commit messages, názvy branchí a titulky PR anglicky.** Formát
  [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- **Popisy PR česky.** Titulek zůstává anglicky (je z něj commit message při mergi),
  ale tělo PR je próza pro mě — a próza se v tomhle repu píše česky. Platí i pro
  komentáře na PR a odpovědi na review.
- **Release notes česky** (viz Pracovní postup).
- **Žádné AI atribuce** v commitech ani v PR — bez podpisů a bez „generated with“.

## Pracovní postup (git)

- **Víc issues naráz se dělá souběžně, ne za sebou** (#231). Když přijde seznam, posuď, co je
  na sobě nezávislé, přiděl slot a pusť na každé nezávislé issue **subagenta ve vlastním
  worktree**. Postup je v [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) a **přečti si ho
  dřív, než subagenta pustíš** — slot mu přiděluje orchestrátor a bez něj by subagent přepsal
  aplikaci, se kterou zrovna pracuju, i s její cache.

  **Subagent dotáhne issue až do konce** (#247): PR, Copilot, merge, zavření issue, release
  a **úklid své aplikace** — ukončit, odregistrovat z LaunchServices a smazat i s cache (#250),
  jinak se mi v `/Applications` hromadí PRismy, ze kterých se nedá vybrat.
  Nečeká na frontu u orchestrátora — hotová práce, která leží, je to zdržení, kvůli kterému se
  paralelně pracuje. Orchestrátorovi zůstává rozvrh, sloty, tlumočení připomínek, úklid stromů
  a **restart hlavní aplikace** (sahá do hlavního stromu, což subagent nesmí).

  **Odepřené povolení se neobchází, hlásí se** (#273): když permission brána subagentovi něco
  zakáže, napíše to do hlášení jako neověřenou mezeru a nechá to na orchestrátorovi — neověřená věc
  přitom není důvod nemergovat, protože poslední kolo kontroly dělá člověk v pauze.

  **Orchestrátor v dávce neimplementuje, deleguje** (#259) — ani u issue, které je „jen
  dokumentace“. Jeho kontext drží rozvrh a stav všech větví, což za něj nikdo neudrží, kdežto
  implementace se dá rozdat; a strom po skončené session je důvod poslat do něj **nového
  subagenta**, ne psát v něm sám. Výčet toho, co orchestrátor dělá, i postup pro předání
  rozdělané práce jsou v [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md). U **jednoho**
  issue se nic nemění, udělá se sériově.
- **Všechno jde přes PR.** Žádné přímé pushe do `main` — každá změna (kód i dokumentace)
  má vlastní branch a PR, i když je malá. PR odkazuje na issue, které řeší.
- **Branch:** anglicky, krátce, s číslem issue — např. `issue-4-github-gateway`.
- **Před prvním pushem mi appku spusť a dej mi prostor na připomínky — ale jen když je
  na změně co vidět.** Platí pro první push branche, ne pro opravy po review — tam už je
  co komentovat na PR.

  ```bash
  ./bin/run.sh
  ```

  Pak **zastav a čekej.** Ne „spustil jsem a jde to“ a hned commit — smysl je, že si to
  proklikám, dokud je změna ještě levná na přepsání. Zelené testy nejsou důkaz, že se to
  chová, jak jsem chtěl.

  **V dávce se pauza nezruší, jen se posune před merge** (#256, mění #247): subagent zastaví
  s hotovým PR a nechá mě proklikat **svou slotovou aplikaci**, protože to je jediná chvíle, kdy
  je změna ještě ve větvi a připomínka k ní je jedna změna, ne nové issue. Zavolá mě **přes
  orchestrátora** (`SendMessage` na `main`) — čekáním neblokuje slot. Podrobnosti v
  [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md). Co se **nemění**: podívat se na
  obrazovku sám a napřed platí i tam, a o to víc — mergnout rozbitou obrazovku je horší než ji
  ukázat. A **neviditelná změna pauzu nedostane** ani v dávce, viz odstavec níž.

  Napiš, **na co se mám podívat** a co v příslušné obrazovce uvidím.

  **Napřed se na to ale podívej sám — screenshotem.** `screencapture -x -R<x,y,w,h>` funguje
  a mockup se dá vyrendrovat headless Chromem a položit vedle (postup v
  [`docs/testovani.md`](docs/testovani.md)). Ukázat mi obrazovku, na které je něco zjevně
  rozbité, znamená použít mě jako první kolo kontroly — a to je kolo navíc, stejně jako
  u Copilota. Platí to i pro komponentu, která se jen **přesunula do užšího místa**: jiná
  šířka je jiný design a plné popisky, počty a odznaky se do ní obvykle nevejdou.

  **Když se změna v UI nijak neprojeví** (vrstva bez UI — modely, parser, protokol),
  **na pauzu mě netahej.** Neviditelnou změnu nemám jak proklikat, takže by pauza jen
  brzdila. Napiš do shrnutí jednou větou, že vidět není nic a proč, dolož to zelenými
  testy a **pokračuj rovnou na commit a PR** — kontrola proběhne nad diffem na PR.
  Rozhodující je, jestli se něco změnilo na obrazovce, ne jestli je změna malá: oprava
  jednoho textu v labelu se ukazuje, nový `Codable` model ne.

  Když ke stavu, který chceš ukázat, nejde přijít normálním používáním (chybějící binárka,
  chyba sítě), viz *Jak si zkontrolovat, jak view vypadá* v
  [`docs/testovani.md`](docs/testovani.md) — a hlavně
  **nezapomeň před tou pauzou rebuildnout**, ať nekoukám na starý build.
- **Po vytvoření PR na něj pusť Copilota a počkej na výsledek.**

  ```bash
  ./bin/copilot-review.sh <číslo PR>
  ```

  `gh pr edit --add-reviewer Copilot` **nepoužívej** — na tomhle repu padá na deprecated
  Projects classic a reviewer se nepřidá; REST `/requested_reviewers` vrátí 200 a bota
  tiše zahodí. Skript proto jde přes GraphQL mutaci `requestReviews` s `botIds`.

  Totéž platí pro `gh pr edit` obecně a pro `gh issue view` — obojí si tahá
  `projectCards` a spadne dřív, než něco udělá. Číst a upravovat jde přes REST:

  ```bash
  gh api repos/{owner}/{repo}/issues/3 --jq .body
  jq -Rs '{body: .}' telo.md > payload.json
  gh api repos/{owner}/{repo}/pulls/32 -X PATCH --input payload.json
  ```

  `gh pr create`, `gh pr list` a `gh api` fungují normálně — zlobí jen ty dva příkazy.
  Pozor jen na jednu REST cestu: `pulls/comments/{id}/replies` vrací **404** — odpověď na
  inline komentář se posílá jako `POST pulls/{n}/comments` s `in_reply_to`.

  Když Copilot nálezy má, projdi je, řekni, co je reálné a co šum, a co je reálné oprav.

- **Vlastní revize diffu je podmínka pushnutí, ne doporučení.** `copilot-review.sh` se smí
  pustit teprve po ní. Není to úspora práce, je to úspora **času**: Copilot má latenci
  v minutách, takže každý nález, který bys našel sám, stojí kolo navíc. U #46 z toho byla
  čtyři kola a dvě z nich byla zbytečná.

  Revize se musí někde **projevit** — buď opravou, nebo větou v popisu PR o tom, co jsi
  hledal. Když po ní diff vypadá nedotčeně a Copilot pak najde něco, co grep z tabulky níž
  chytá, revize neproběhla.

  Subagent je fajn, ale **není podmínka** a není výmluva, když zrovna není po ruce: projít
  `git diff main...HEAD` vlastníma očima plus grepy níž zabere minuty a nic dalšího
  nepotřebuje.

  **Tohle Copilot v tomhle repu nachází opakovaně**, takže to projdi dřív, než ho pustíš:

  | Vzor | Proč to bolí |
  |---|---|
  | `try?`, prázdný `catch`, `?? default` nad operací, která může selhat | Ztracená data vypadají v UI jako „nic tu nebylo“. U každého se ptej: pozná uživatel, že se to nepovedlo? Když ne, patří to do stavu, ne do `try?` |
  | Text v UI, který tvrdí víc, než data unesou | „Reviewer nenahlásil žádný nález“ zní jako čisto i tehdy, když se nálezy nemají kde vzít |
  | Stav, který se drží, ale nikdo ho nečte | Buď to zobraz, nebo nedrž — jinak je to mrtvá váha, která svádí k tomu spolehnout se na ni |
  | Kontrola, která jinde v repu je, a tady chybí | Typicky ochrana proti mazání mimo cache. Když už někde existuje, patří na jedno místo a použije se z obou |
  | Čtení nebo dekódování všeho, když stačí předfiltr | U operací, které běží při každém uložení nebo tiku, to není detail |

- **Když nález přijde, oprav třídu, ne výskyt.** Copilot vidí vždycky jen nový diff, takže
  na druhý výskyt téhož vzoru upozorní až v dalším kole — a to je zase pár minut. Po každém
  reálném nálezu proto projdi diff na tentýž vzor (`git diff main...HEAD | grep …`) a oprav
  všechny naráz. U #46 by to ušetřilo dvě kola ze čtyř.
- **Copilot je kontrola, ne hledání — stačí jedno kolo.** Když vlastní revize proběhla
  pořádně, druhé kolo obvykle jen potvrdí, co první našlo. Pusť ho jednou, nálezy oprav
  a **mergni podle vlastního uvážení**.

  Další kolo si vyžádej jen tehdy, když ten první průchod odhalil něco **strukturálního** —
  tedy vzor, který se opravou mohl objevit i jinde, ne překlep. Točit to na jistotu je
  přesně to zdržení, kvůli kterému se tohle pravidlo změnilo.

  **Nemusíš vyhovět všem komentářům.** Copilot navrhuje i věci, které v tomhle repu
  nedávají smysl nebo jsou horší než to, co tam je. Rozhoduješ ty — u nálezu, který
  neopravíš, ale musí být odpověď s důvodem, ať je z PR vidět, že se to zvážilo. Když si
  radou nejsi jistý, ověř ji (spusť to, změř to); zamítnutí podložené měřením je lepší
  než oprava naslepo.

  Dvě pasti při čtení výsledku:

  ```bash
  # Pozor na dvě různá jména: review píše `copilot-pull-request-reviewer[bot]`,
  # ale inline komentáře `Copilot`. Filtr `startswith("copilot")` je navíc citlivý
  # na velikost písmen, takže na komentáře nesedí — a vypadá to, že žádné nejsou.
  gh api repos/{owner}/{repo}/pulls/37/reviews \
      --jq '.[] | select(.user.login | startswith("copilot")) | .body'
  gh api repos/{owner}/{repo}/pulls/37/comments \
      --jq '.[] | select(.user.login | ascii_downcase | startswith("copilot")) |
            "\(.id) \(.path):\(.line)\n\(.body)"'
  ```

  A hlavně: **„generated no new comments“ neznamená, že nic nenašel.** Část nálezů se
  schová do sekce *Suppressed comments* uvnitř **těla review** a v inline komentářích
  nejsou vůbec. Tělo se proto musí přečíst celé — u #8 tam takhle ležely dva reálné
  nálezy pod hlavičkou, že nové komentáře nejsou.

  **Copilot si tenhle soubor bere jako custom instructions — a tím si sám ucpává kontext.**
  Když spadne, do review napíše jen „Copilot encountered an error and was unable to review
  this pull request“; příčina je vidět **jen v logu akce**:

  ```
  [customInstructions] Built 1 custom instruction(s) for ondrajodas/PRism; names=["CLAUDE.md"]
  Running detector: ccr[…;MaxPromptTokens=110000;…]
  Error: Prompt too big after adding PR context
  ```

  Tehdy měl `CLAUDE.md` 315 kB, takže sám o sobě sežral většinu ze 110 tisíc tokenů rozpočtu
  a na „PR context“ nezbylo. **Nerozhodovala proto velikost diffu**: #159 (12 kB) prošel, #160
  (70 kB) i #161 (30 kB) spadly. Napřed to vypadalo na `AppStore.swift` (128 kB, byl v obou
  spadlých) — log ukázal, že to bylo jinak; byl to tenhle soubor, ne ten review.

  **Vyřešeno rozdělením do `docs/` (873bc29):** ze 316 kB zbylo 37 a Copilot od té doby běhá
  normálně (naposledy ověřeno na #230). Zůstává z toho **pravidlo, ne výjimka**: tenhle soubor
  se drží malý a podrobnosti patří do `docs/`. Kontroluj to měřením (`wc -c < CLAUDE.md`), ne
  odhadem — nad ~100 kB je čas rozdělovat znovu.

  Kdyby přesto spadl: **nepřepisuj kvůli tomu zadání ani nedělej umělé PR navíc** —
  dokumentace musí jít se změnou v jednom commitu, to je pravidlo o řádek výš. Zbývá vlastní
  revize, a ta je stejně podmínkou pushnutí; napiš do popisu PR, že Copilot nedoběhl a proč,
  ať je z PR vidět, že kontrola nechyběla omylem.
- **PR, který je v pořádku, mergni sám.** Nečekej na pokyn: zelené testy, vyřešené nálezy
  a hotové zadání issue stačí. Po mergi rovnou **zavři issue** a **vydej release**.
  Když si nejsi jistý, jestli je hotovo, tak hotovo není — dodělej to, neptej se.
- **Po mergi mi restartuj hlavní aplikaci z mainu** — `./bin/run.sh` v hlavním stromě, bez
  ptaní. Je to nástroj, který používám každý den, takže co je mergnuté, mám mít i spuštěné;
  jinak se regrese pozná až za týden a proti mergnutému kódu se pak hledá v buildu, který ho
  nemá. **Po každém mergi, i uprostřed dávky** — stejně jako release. Odkládat to na konec
  série znamená, že ten mezitím mergnutý kód nikdo nespustí.

  `run.sh` ukončuje Apple eventem, takže při běžícím review se zeptá a bez odpovědi nespustí
  nic. To je záměr, ne chyba — nepřemlouvej to `killall`em. Když skript skončí nenulově,
  **řekni to** a nech starou instanci běžet.
- **Po mergnutí PR se vydá nový tag a GitHub release.** Release notes píšeme česky
  a popisují **jen to, co se v téhle verzi změnilo**: co přibylo, co se opravilo, co se
  rozhodlo jinak a proč, co se změřilo, co se zamítlo. Patří tam i to, co se změnou
  souvisí — počet testů, věta „na tomhle není co vidět“ u vrstvy bez UI, známé omezení
  toho, co se vydalo.

  **Stav projektu do nich nepatří.** Žádná sekce `Kde jsme`, `Další krok`, `Stav proti
  milníkům` ani výčet toho, co zbývá do milníku. Kde projekt je, se pozná z issues a ze
  sekce *Stav* níž; release odpovídá jen na otázku „co je v téhle verzi jinak“.

  **Změna proti původnímu pravidlu** (do #125 tu stálo, že release je deník projektu
  a má popisovat progress). Deník nefungoval ze dvou důvodů: stav **zastará vydáním
  dalšího releasu** a nikdo ho zpětně neopraví — ve `v1.1.12` stálo, že zbývá #69 a #110,
  což o dvě verze později nebyla pravda — a v delších releasech **utopil samotnou změnu**,
  které patřila půlka místa. Release je značka na časové ose, takže hodnotu má právě to,
  co je v ní neměnné. Stávající releasy jsou podle toho pravidla přepsané zpětně.
- **Verzování:** `v0.<milník>.<pořadí PR v milníku>` — např. třetí mergnutý PR
  v milníku 1 je `v0.1.3`. Verze `v1.0.0` = dokončený rozsah v1 podle specifikace.

  **Milník `Průběžné` číslo nemá** — je to koš na věci mimo fáze (provoz aplikace,
  drobnosti, opravy). PR z něj **pokračuje v číslování běžící fáze**, protože verze je
  značka na časové ose, ne štítek původu. Vlastní řada by znamenala, že se čísla vracejí
  zpátky: `v0.0.x` po `v0.5.7` nikomu neřekne, kdy to vzniklo.
- Binárky se do release nepřikládají — buildujeme lokálně. Release slouží k záznamu
  změn, ne k distribuci.

## Co aplikace je

Nativní macOS aplikace (SwiftUI), která hlídá GitHub PR přiřazené mně k review, spouští
na ně review skilly Claude Code jako headless session a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Když se objeví
potřeba „chytřejšího“ review, patří to do skillu, ne do aplikace.

Plný návrh: [`docs/superpowers/specs/2026-07-31-prism-design.md`](docs/superpowers/specs/2026-07-31-prism-design.md)

## Návrh (mockup)

Jak má aplikace vypadat, drží **artifact `PRism — návrh vizuální revize`**:
<https://claude.ai/code/artifact/5206622c-19b2-4c4e-9041-849d5b6d4a51>. Je to HTML —
tokeny v `:root` jsou `App/Views/Palette.swift` jedna ku jedné, takže se z něj barvy
i rozměry berou doslova, ne od oka.

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
Neruší to pravidlo o řádek výš — schvaluje se **obrázek**, ne návrh implementace; kam patří
typ, kde žije kontrola a jak se to poskládá uvnitř, si pořád rozhoduješ sám.

Když na něco narazíš, co návrh v issue mění (zjistíš, že to nejde, jak je napsané),
**není to důvod se ptát** — rozhodni, zapiš do specifikace **co se změnilo a proč**,
a napiš to do popisu PR. Posoudí se to nad diffem.

Ptát se dál na **tvrdé podmínky** níž. Merge PR ani zavření issue mezi ně **nepatří** —
to si od 2026-08-01 řídíš sám, viz pracovní postup.

## Tvrdé podmínky

Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav se a zeptej se.

1. **Jediná cesta ven** (od #67; do té doby tu stálo „nikdy nic neposílat na GitHub“).
   Aplikace **umí** odeslat review, od #73 se **ozvat do vlákna** a od #216 **napsat komentář
   pod PR** — ale jedině přes `ReviewPublishing`, jedině na výslovný pokyn člověka a jedině tam,
   kde se to **v nastavení povolilo**. Pravidlo se skládá z šesti věcí a každá z nich je
   kontrolovatelná:

   1. **`GitHubGateway` zůstává bez zápisových metod.** Polling, diff, checkout ani reviewer
      tedy nemají čím něco odeslat — read-only je pořád vidět z typu.
   2. **`grep ReviewPublishing App/` vyjmenuje všechna místa, odkud to jde.** Mají to být
      **pět souborů a tři volající**: protokol, `GhReviewPublisher` (implementace),
      `ReviewSubmission.send()` (review), `ThreadSubmission` (odpověď a vyřešení vlákna)
      a `CommentSubmission` (komentář pod PR).

      Protokol má **čtyři vyjmenované metody** — `submit`, `reply`, `setResolved`, `comment`.
      Do #73 měl jednu a stálo tu, že cokoli dalšího by byla druhá cesta ven; do #216 tři.
      Rozšířilo se to pokaždé ze stejného důvodu: ozvat se kolegovi je půlka toho, kvůli čemu
      se u review přepíná do prohlížeče, a přes `GitHubGateway` to jít nesmí (bod 1). Co
      **zůstává**: výčet je krátký, vyjmenovaný na jednom místě a **každá metoda si sama ověří
      bránu z bodu 6** — proto všechny berou adresu, ze které se pozná repo. Roste-li ten výčet,
      roste to, co aplikace umí odeslat, a to má být vidět v jednom souboru. Approve mimo
      review, label ani zavření PR tam pořád nepatří.
   3. **Publisher není pole `AppStore`.** Vzniká uvnitř té cesty, která odesílá, a zaniká
      s ní — nemá ho kde uložit nikdo, kdo ho nemá mít. Drží to `ReviewSubmission` (skládá se
      až v `send()`, zaniká zavřením sheetu), `ThreadSubmission` (skládá se v `reply(_:)`
      a `setResolved(_:)`) a `CommentSubmission` (skládá se v `send(_:)`). `AppStore` si kvůli
      odesílání drží **jen cestu ke `gh`**, ne publisher ani továrnu na něj — proto ho ten grep
      nevypíše. Platí to i pro vlákna a komentáře, kde `AppStore` odesílání spouští: drží
      **stav** (`ThreadActionState`, `CommentActionState`), ne cestu ven.
   4. **Odeslání review si žádá hotový draft s `headSha`** a pre-flight ověří, že je to pořád
      hlava PR. Approve na kód, který jsi neviděl, tak nejde poslat ani závodem s pushnutým
      commitem. GitHub proti tomu **nechrání** — změřeno u #62, že review se zastaralým
      `commit_id` přijme.

      **U odpovědi do vlákna a u komentáře pod PR se `headSha` neověřuje** (#73, #216) a je to
      schválně: obojí se váže na diskuzi, ne na commit, takže kontrola hlavy by zakázala zrovna
      tu situaci, kvůli které se píše („opraveno v abc123“). Ověřuje se **stav PR**, a to i tam
      **striktněji než GitHub** — změřeno u #73, že odpověď na zavřeném PR projde. Aplikace
      ukazuje PR z `review-requested`, takže mergnutý PR ze seznamu vypadne a k jeho diskuzi se
      z okna nedostaneš; psát do uzavřené diskuze patří do prohlížeče.
   5. **Jedno atomické volání.** Buď odejde všechno, nebo nic; žádný částečně odeslaný stav
      po pádu uprostřed. Změřeno u #62. U vláken a komentářů je to triviálně splněné — odpověď,
      vyřešení i komentář jsou jedno volání.
   6. **Jen tam, kde se to povolilo** — `PublishScope`, složený z `Configuration`
      (`allowsPublishing` globálně i per repo). **Výchozí stav je vypnuto**, a právě to drží
      vlastnost „samo nic neodejde“: dokud si někdo výslovně neřekne o konkrétní repo nebo
      neotočí globální default, nejde odeslat nikam. Sandbox v tom **není výjimka v kódu** —
      zapíná se stejným přepínačem jako cokoli jiného.

      **Změna proti #67** (do #107 tu stál zadrátovaný seznam s jediným sandboxem
      a odůvodnění, že brána v `config.json` už není brána, ale nastavení). Změnilo se to
      proto, že „kam smím odesílat“ je rozhodnutí **per repo**, které se mění často — a jako
      konstanta stálo každé takové rozhodnutí commit, review a release, tedy cenu, kterou má
      platit změna *pravidla*, ne změna *jednoho repa*. Proti omylem odeslanému review
      nechrání seznam, ale body 4 a 5 výš a potvrzení s úplným výpisem payloadu (#68).

   Co se **nezměnilo**: návrh verdiktu z nálezů (`ReviewVerdict`) je pořád jen návrh a sám nic
   neodesílá. Od #114 se jím **předvyplňuje** verdikt v panelu, takže odejít umí — ale jedině
   tou samou cestou jako cokoli jiného: dvěma kliknutími člověka v potvrzení, ve kterém je celý
   payload vidět a je u něj napsané, že hodnota je z návrhu. Odesílá tedy pořád jen člověk. **Potvrzovací sheet je jen
   u review** — odpověď do vlákna (#73) ani komentář pod PR (#216) se nepotvrzují, protože je to
   jedna věta v diskuzi, dá se smazat a potvrzování každé by z okna udělalo klikačku. „Výslovný
   pokyn člověka“ tedy u review znamená dvě kliknutí na dvou různých tlačítkech, u diskuze jedno
   pojmenované. Composer komentáře přitom **nesmí splynout s tabem `Moje review`** — proto sedí
   pod osou konverzace, ne v pravém panelu, kde ho kreslí návrh.
2. **Reviewer je read-only.** V `--allowedTools` není `Write` ani `Edit`, u `Bash` se uvádí
   jen `git` — a v `--disallowedTools` jsou `Bash(gh:*)` a `Bash(git push:*)`. `Skill` mezi
   povolenými je (#78); sám o sobě nic nespouští, ale skill, který se přes něj načte, si
   o odeslání na GitHub umí říct — proto ten zákaz.

   **Platí to i pro kontrolu nálezů z minula** (#150), která má vlastní prompt: bere **tytéž
   konstanty** `ClaudeCommand.allowedTools` a `disallowedTools`, žádné vlastní povolení si
   neskládá. Předchozí nálezy dostane jako **materiál v promptu**, ne jako nástroj — druhá sada
   povolení by znamenala druhé místo, kde se ta podmínka dá porušit.

   **Editovatelný prompt review (#281) na tom nemění nic.** Otevřel se **prompt, ne povolení**:
   šablona z nastavení se dosadí do textu a skončí v **jednom argumentu za `-p`**, kdežto sada
   nástrojů se pořád skládá z těch dvou konstant v kódu — ze šablony se do nich nedá sáhnout a nic
   v ní nedokáže nástroj povolit (je na to test s šablonou, která si o `Write,Edit,Bash` říká).
   Věta o zákazu zápisu v promptu je vedle toho **pojistka, ne brána**, a proto se **připojuje
   vždycky** mimo šablonu: skill načtený přes `Skill` si o odeslání říct umí, ale zavírá to
   `--disallowedTools`. Co jádro drží doopravdy, je **sběr nálezů** — bez `ReportFindings` by
   nálezy přišly textem a v okně by stálo „čisté review“.

   Ověřeno spuštěním (#12, **opraveno u #17**; podrobnosti v `docs/claude-cli.md`):
   - Co je **mimo** povolený vzor, se odmítne, pokud to není na vestavěném seznamu čtecích
     příkazů. `ls` a `cat` projdou, `gh` ne.
   - Co je **uvnitř** vzoru, projde celé — `Bash(git:*)` tedy pouští i `git push`. To je
     jediná cesta, kterou by session z naší cache něco odeslala, protože `origin` míří na
     skutečné repo a má credential helper. **Zavírá to až `--disallowedTools`**, který
     povolení přebíjí a zabere i na `git push` s vypsanou URL.
   - `Write`, `Edit` ani `Bash` z init eventu nezmizí, ať je v povoleních cokoli — seznam
     nástrojů není obraz oprávnění.

   Odmítnutý nástroj **není chyba běhu**: session pokračuje a skončí `success`, odmítnutí je
   vidět v `permission_denials`.
3. **Nikdy nesahat na uživatelovy klony.** Aplikace pracuje výhradně ve své cache
   (`~/Library/Application Support/PRism/`). Mohou být rozdělané, na jiné branchi,
   mít vlastní worktrees.
4. **Aplikace nikdy nedrží GitHub token.** Autentizace je delegovaná na `gh`.
5. **Nálezy jsou klíčované `headSha`.** Nové commity nálezy zneplatní (stav
   „zastaralé“), nikdy se nesmí tiše zobrazovat proti kódu, který už neexistuje.

   **Kontrola nálezů (#150) na tom stojí, ne obchází to**: nese `againstHeadSha` — hlavu, proti
   které běžela —, a jak se hlava posune, `Policy.recheck(of:head:)` odznaky nevydá a v hlavičce
   zbyde věta, že se dá pustit znovu. Ukládá se navíc k záznamu **těch nálezů**, na které se
   ptala, takže starší commit zůstane starší; „vyřešeno“ přitom nikdy nález nesundá, to smí
   jedině odmítnutí (#113) — a od odmítnutí se musí poznat **i pohledem**: přeškrtne se jen text
   nálezu (ne celý řádek) a `blokuje` u něj zůstává.

## Architektura

Osm modulů. Čtyři, které sahají do vnějšího světa, jsou za protokolem, aby byly v testech
nahraditelné fake implementací. Osmý (`ReviewPublisher`, #67) je jediný, který **zapisuje** —
viz tvrdá podmínka č. 1.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a syrový diff — celý, nebo mezi dvěma commity (#284) | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings`. Od #150 dvě podoby běhu — review a kontrola nálezů z minula (vlastní prompt, odpověď z posledního sdělení) | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Stav řádku podle checkoutu, blokující příznak, návrh verdiktu, detekce shody `2×`, řazení, filtr seznamu (#117), hledání v paletě ⌘K (#184), rozbalení bubliny nálezu (#185), odznak závažnosti u nálezu (#150), které záložky PR se kreslí a odznak `Kontrol` (#215), složení promptu review ze šablony (#281), jestli je co porovnat u „co přibylo“ (#284) | — |
| `Config` | Globální default + override per repo, tolerantní čtení `config.json` | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu. **Stav v `AppStore.swift`, metody v `AppStore+*.swift`** (#154) | — |
| `ReviewPublisher` | **Jediná cesta ven**: odeslat review, odpovědět do vlákna, přepnout jeho vyřešení a napsat komentář pod PR; volající jsou `ReviewSubmission`, `ThreadSubmission` a `CommentSubmission` | `gh` CLI |

Nad tím SwiftUI views: `PRList`, `DiffView`, `ReviewPanel`. Mimo tuhle sedmičku stojí
`App/Diff/` — překlad diffu na model a jeho řádky. Není to modul: v doméně review nemá
diff jinou roli než být vidět. Totéž platí o `App/Health/` (#31): dostupnost služeb je
o tom, jestli jde review vůbec spustit, ne o review samotném.

**Kam co psát:** rozhodovací logika patří do `Policy` jako čistá funkce — tam se testuje
bez mockování. Když se přistihneš, že píšeš `if` nad nálezy někde ve view nebo v runneru,
patří to do `Policy`.

Co který modul drží a co se u něj nemá rozbít, je v
[`docs/architektura.md`](docs/architektura.md) — sekce na modul, ve stejném pořadí jako
tabulka výš. Jde tam pro podrobnosti k tomu, na čem zrovna pracuješ; **tenhle soubor musí
stačit k tomu, abys věděl, kam sáhnout.**

Zvlášť stojí za přečtení, než sáhneš na:

- **modely** — tři různé „jazyky“ a tři různá „review“ se nesmí slít, `ReviewState` rozlišuje
  chybové stavy schválně;
- **`AppStore` je rozdělený na `extension` po zodpovědnostech** (#154), takže se hledá podle
  souboru, ne v jednom dvoutisícovém: `AppStore.swift` drží **stav, init a polling**,
  `+Diff`, `+IncrementalDiff`, `+DiffExpansion`, `+Detail`, `+Commits`, `+Conversation`, `+Draft`,
  `+DraftTransfer`, `+Submission`, `+Review`, `+Recheck`, `+Findings`, `+Notifications`
  a `+Automatic` metody. **Dělí se
  metody, ne data** — uložený stav zůstává na jednom místě. Cena je, že `private` členy, na
  které extensiony sahají, musely být `internal`; nic se tím neotevírá ven z aplikace (jeden
  modul) a tvrdou podmínku č. 1 to nemění, protože publisher polem storu není.
- **`AppStore` a okno** — co patří do store a co do view (`@State` v detailu PR přetéká mezi
  pull requesty), a proč se stav checkoutu klíčuje repem;
- **`pullRequests` je plný seznam, `visiblePullRequests` je po filtru** (#117), a **rozdíl mezi
  těmi dvěma gettery je jediné, co dělí filtr od mazání cache**. Zúžený čte jedině seznam a detail
  vybraného řádku; plný čte okno nastavení, souhrn fronty, automat a úklid. Kdyby na zúženém
  viselo cokoli z úklidu, zapnutí filtru by zahodilo diffy a konverzace, smazalo cache a zrušilo
  běžící review;
- **`Environment`** — podprocesy: blokující I/O nesmí na kooperativní pool, oba pipy se musí
  číst souběžně, **zrušení i ukončení aplikace musí proces zabít** (#264 — obě cesty, jedním
  `SIGKILL`em z `LaunchedProcess`; zavírání se na něj navíc musí **počkat**, jinak `claude`
  osiří na `launchd` a běží dál).

## Konvence

- **Krátké, jednoúčelové metody.** Čitelnost před chytrostí.
- **Nepoužívat `final`** u typů, které se v testech nahrazují.
- **Protokol + fake, ne mockovací framework**, u tří modulů se vnějším světem — a stejně
  u `Environment`, kde jsou za protokolem `ExecutableProbe`, `ProcessRunning`
  a `ShellPathReading`.
- **Nové soubory drž malé a soustředěné.** Když soubor roste, obvykle dělá víc věcí.
- **Do `project.pbxproj` nesahej.** `App/` a `Tests/` jsou buildable folders
  (`PBXFileSystemSynchronizedRootGroup`) — soubory i podsložky se do targetu berou
  z filesystému. Nový zdroják = jen ho vytvořit. Editovat pbxproj je potřeba jen při
  změně targetů nebo build settings. Jediný soubor, který v něm vyjmenovaný **je**, je
  `Signing.xcconfig` — xcconfig se dá napojit jen odkazem (`baseConfigurationReference`
  u obou konfigurací projektu), z filesystému se nevezme.

  **Dva zdrojáky se stejným jménem build položí** (#184), i když leží v různých podsložkách:
  model palety a hledání k ní se u #184 obojí jmenovaly `CommandPalette.swift` (v `App/Models/`
  a v `App/Policy/`) a build skončil na `Multiple commands produce … CommandPalette.stringsdata`.
  Jméno souboru je v jednom targetu klíč, takže se soubory pojmenovávají **jednoznačně napříč
  celým `App/`** (a `Tests/`) — proto je z toho druhého `App/Policy/CommandPaletteSearch.swift`.

  Druhá výjimka je `ASSETCATALOG_COMPILER_APPICON_NAME` (#83): je to **build setting**, takže
  jinudy než pbxprojem nastavit nejde. Leží na **app targetu**, ne na projektu — testovací
  target ikonu mít nemá; je to tatáž úvaha jako u `CODE_SIGN_IDENTITY`, jen obráceně.
  Samotný `App/Assets.xcassets` se ale v pbxproj **nevyjmenovává** — buildable folder ho
  vezme z filesystému a `actool` ho zkompiluje do `Assets.car` a `AppIcon.icns`. Ověřeno
  obsahem `.app`.
- **V zanořeném stromu se rozměr nenechává vyjednávat, když se dá spočítat** (#220).
  `frame(maxWidth: .infinity)` na každé úrovni zanoření stojí **~5,5× na úroveň** — okno na PR
  s 2000 řádky tuhlo 20 minut na 100 % CPU. Šířka se předává (`availableWidth`, `narrowingWidth`,
  `filling` v `App/Views/AvailableWidth.swift`); pružná výška v líném seznamu je tatáž chyba.
  Tuhnoucí okno se diagnostikuje `sample`m běžícího procesu, ne odhadem — viz
  [`docs/testovani.md`](docs/testovani.md).

  **Nevyjednává se ani počet prvků** (#252). Overlay nad blokem kódu měl plochu, gesto a čtení
  geometrie u **každého** řádku a strany — u šedesátiřádkového bloku přes čtyři stovky prvků,
  které líný seznam umisťuje znovu při každém přerovnání obsahu. Polohy přitom hlásí textové view,
  takže se dají spočítat (`DiffGutterGeometry`): zbyly dvě plochy a jedna pilulka na blok,
  **3,05 ms → 0,12 ms**. Platí u toho dvě věci: prvek v `ForEach`i s prázdným obsahem se pořád
  umisťuje („nekreslí se“ ≠ „nestojí nic“), a co se při scrollování mění, **nesmí být ve `@State`**
  — poloha bloku v prostoru obsahu se drží mimo observable stav (`DiffBlockPlacement`).
- **Kdo si říká o velikost, musí ji měřit na tom, na čem kreslí** (#236). Blok kódu si v `LazyVStack`u
  navrhuje výšku sám, takže když ji spočítá na jiné šířce, než na jaké se pak zalamuje, nakreslí víc
  řádků, než na kolik si řekl — a přeteče do řádku pod sebou (AppKitové view je nad SwiftUI obsahem,
  takže je vidět kód přes bublinu nálezu). Měření proto patří **do toho typu, který drží šířku
  kreslení**, ne do volajícího; dvě místa znamenají dvě pravdy o jedné šířce. Testuje se proti
  **layout manageru** a **přes pásmo šířek** — rozejde se to jen v pásmu, takže u jedné šířky test
  projde. Podrobnosti v [`docs/architektura.md`](docs/architektura.md).
- **Co se počítá při každém překreslení, se pamatuje — a cache si musí říct, co ji vyprazdňuje**
  (#224). Obarvení řádku se volalo z computed property, takže běželo i při přejezdu myší: 44 ms
  na soubor o 2400 řádcích, pokaždé znovu; z cache 0,30 ms. Hranice musí být v tom typu vidět
  (`SyntaxRunCache`: strop na počet řádků i na jejich objem, po překročení se zahodí celá) —
  cache bez vyjmenované meze je únik paměti s odkladem.

  **A do cache smí jen to, co je funkcí jejího klíče** (#153). `SyntaxRunCache` je klíčovaná
  `(text řádku, jazyk)`, takže word-level zvýraznění, které závisí na **protějšku** dvojice, do ní
  nepatří — vracela by zvýraznění cizí dvojice, a potichu. Takové věci se kreslí jako **druhá
  vrstva nad** výsledkem z cache; podrobnosti v [`docs/architektura.md`](docs/architektura.md).
- **Zlevnění, které práci jen přesune jinam, není zlevnění — a pozná se to jedině změřením obou
  konců** (#275). U sazby bloku si rozvržení vynucuje `sizeToFit()` (35 ms ze 79), takže ho vyhodit
  vypadá jako polovina ceny pryč. Jenže `super.draw` rozvržení potřebuje taky a blok, který vjel do
  okna, se kreslí — číslo by spadlo v harnessu a v okně ne. **Měř tu cestu, kterou kód doopravdy
  jde**, a co se nepodařilo zlevnit, napiš i s důvodem: bez toho to příště někdo zkusí znovu.
- **Řádky dělí `TextLines`, nikdy `split(separator: "\n")` ani `components(separatedBy: .newlines)`**
  (#292, na jedno místo svedeno #295). `"\r\n"` je ve Swiftu **jeden `Character`**, takže
  `split(separator: "\n")` na `CRLF` **nerozdělí vůbec** — z celého vstupu zbyde jeden „řádek“. Ta
  druhá cesta dělí po skalárech, takže `CRLF` jsou pro ni dva oddělovače a vloží mezi ně prázdný
  řádek. Stálo to dvě funkce: `Content-Length` se nenašel u žádného checku (#292) a každý řádek
  cizího komentáře se sázel jako vlastní odstavec.

  Platí to na **všechno, co zakončení řádků nevybírá aplikace**: hlavičky, logy z CI, diffy
  a obsah souborů z cizích repozitářů (`gh pr diff` na `microsoft/terminal` má `CRLF` na 70 řádcích
  ze 76). Grep na ten vzor — **musí vyjít prázdný**, filtr zahazuje ty vzory v komentářích, které
  vysvětlují proč:

  ```bash
  grep -rn 'split(separator: "\\n"\|separatedBy: .newlines' App | grep -vE ':[0-9]+: *//'
  ```

  Výjimka je `String.singleLine`, a to **schválně**: sráží cizí text do popisku, takže potřebuje
  širší `isNewline` (grep ji nechytá, dělí přes `whereSeparator`). Zdůvodnění obojího je
  u `Character.isLineTerminator` a v [`docs/architektura.md`](docs/architektura.md).

  A **fixture takového formátu musí být skutečný výstup** — ruční literál nese `LF` toho, kdo ho
  napsal, takže test zezelená i nad rozbitým rozborem; když na `CRLF` stojí, patří do
  `.gitattributes` jako `-text`, jinak ho `core.autocrlf` zahodí při commitu.
- **V shell skriptech se proměnná v české próze píše `${VAR}`.** Uvozovka „ hned za
  `$VAR` shodí bash 3.2 (ten je v `/bin/bash`) v UTF-8 locale na `unbound variable`: její
  byty se počítají do jména proměnné. Chytí to `set -u`, ale až za běhu — `bash -n` ne.
  Grep na ten vzor: `grep -nP '\$\{?[A-Za-z_][A-Za-z_0-9]*[^\x00-\x7F]' bin/*.sh`.
- **`| grep -q` se ve skriptu s `pipefail` nesmí použít jako podmínka.** `grep -q` po první
  shodě zavře rouru, producent dostane SIGPIPE a `pipefail` z toho udělá návratový kód
  141 — takže podmínka vyjde **nepravdivě právě tehdy, když shoda je**. Výstup se čte do
  proměnné a porovná `case`em. Stálo to mrtvou kontrolu ad-hoc podpisu v `bin/run.sh`,
  která nevypsala nic ani nad ad-hoc podepsanou aplikací (#61). Kontrolu, která má něco
  hlásit jen výjimečně, je proto potřeba **spustit i v tom výjimečném stavu** — jinak je
  „nic nevypsala“ k nerozeznání od „funguje“.
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
  vlastní (`GENERATE_INFOPLIST_FILE = NO`). Bez toho klíče se ikona **zkompiluje**
  a v bundlu leží, jen ji systém nenajde a v Docku zůstane prázdný obdélník.
- **Po překreslení ikony se musí restartovat Dock** (`killall Dock`). Cache ikon je vázaná
  na cestu k `.app`, která se rebuildem nemění, takže Dock dál ukazuje tu starou — a vypadá
  to, že se nic nezměnilo. Stálo to jedno kolo hledání neexistující chyby v buildu.
- **`CFBundleName` nejde nastavit přes `INFOPLIST_KEY_*`.** Xcode ho generuje
  z `PRODUCT_NAME` a klíč tiše ignoruje. Projekt má proto vlastní `Info.plist` místo
  `GENERATE_INFOPLIST_FILE`. Původní důvod (produkt a uživatelský název se lišily) po
  přejmenování na `PRism` odpadl — plist se teď dá zjednodušit, ale zatím zůstává.
- **Moduly jsou složky, ne targety.** Všechen kód žije v jednom app targetu; `Policy`
  a spol. budou podsložky `App/`. Framework by si vynutil `public` u všeho, co používá
  UI — daň, kterou osobní aplikace nepotřebuje. Vyčlenit se dá později.
- Chybové stavy jsou v návrhu vyjmenované (viz specifikace, sekce *Chování při chybách*)
  — každý z nich má mít v UI vlastní rozlišitelný stav. `čisté` (žádné nálezy) a
  `failed` (session spadla) se nesmí slít do jednoho.

## Testování

Katalog toho, co se u které oblasti testuje a proč zrovna to, je v
[`docs/testovani.md`](docs/testovani.md) — i s návodem, **jak si zkontrolovat, jak view
vypadá** (offscreen render, accessibility; `screencapture` na tomhle stroji nefunguje).

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
- **Test, který čeká na jev, se neváže na pevný okamžik** (#269). Sonda odpočtu brala dva snímky
  1,5 s od sebe a tvrdila, že se liší — přitom první změna kresby přijde ve 2,01 s, takže zeleně
  vycházela jedině tehdy, když spánek přetáhl, a `main` skončil červený. Čeká se **na jev se
  stropem** (snímek po 100 ms, dokud jich není dost) a strop musí být z čeho spočítat. A když sonda
  padne, **napřed se podívej, co v ní doopravdy je** — u kresby uložený PNG, ne počet bytů; z toho
  se pozná, jestli je rozbitá aplikace, nebo sonda. Podrobnosti v
  [`docs/testovani.md`](docs/testovani.md).
- **Testy se nespouštějí rourou do `grepu`** — viz *Příkazy* níž, umí to zaseknout na neurčito.

## Příkazy

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test
```

**`-derivedDataPath build.noindex` patří i k testům** (#139). `xcodebuild test` **spouští**
testovacího hosta, a spuštění bundle ho zaregistruje v LaunchServices — bez toho přepínače
skončí v `~/Library/Developer/Xcode/DerivedData/PRism-<hash>/…` a ve Spotlightu je PRism
navždycky dvakrát. Do `build.noindex/` míří i `bin/run.sh`, takže tenhle záznam uklidí
příští spuštění skriptu: je to **tatáž cesta**, kterou odregistrovává.

```bash
./bin/run.sh    # build v Debug + instalace do /Applications + otevření aplikace
                # z /Applications schválně: jinde nefungují notifikace (#88)
                # předchozí instanci ukončí Apple eventem, ne `killall` —
                # při běžícím review se tedy zeptá a bez odpovědi nic nespustí
                # a upozorní, když je build podepsaný ad-hoc
                # cizí bundle v /Applications nepřepíše a při selhání instalace
                # radši nespustí nic, ať se nekouká na starý build
                # a po instalaci odregistruje kopii v build.noindex/ (#139)
                # slot z .prism-slot mění bundle ID, jméno i cache (#228)
```

```bash
./bin/worktree.sh a issue-231-neco    # strom pro paralelní vývoj ve slotu „a“ (#228)
                                      # branch z origin/main, .prism-slot do stromu,
                                      # konfigurace očištěná o odesílání, notifikace a automat
```

```bash
./bin/slot-config.sh    # očištěná konfigurace do cache slotu; slot z .prism-slot (#262)
                        # jediné místo, kde ta očista je — nepiš vlastní `jq` filtr
                        # subagent v dávce ji volá takhle: strom má od harnessu
```

**Slot je jediné, co dělí paralelní okna od sebe** — bundle ID, jméno v `/Applications`
i kořen cache (ten si aplikace bere z `CFBundleName`, ne z konstanty). Bez `.prism-slot` se
nemění nic, takže hlavní strom zůstává tou aplikací, která se používá. Podrobnosti v README,
sekce *Paralelní vývoj — sloty*.

```bash
./bin/setup-signing.sh    # jednorázově: self-signed certifikát do login keychainu
                          # + Signing.local.xcconfig, ze kterého ho vezme build
```

```bash
swift bin/make-icon.swift              # překreslí ikonu do App/Assets.xcassets
swift bin/make-icon.swift split        # druhá barevná varianta
swift bin/make-icon.swift split /tmp/x # jen vykreslit, bez zásahu do repa
```

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
probouzí i za 8,6 s, takže jakýkoli strop odvozený od volného stroje je falešně červený `main`.
Za jednu dávku jich bylo pět. Podrobnosti i naměřená čísla v
[`docs/testovani.md`](docs/testovani.md), sekce *Čekání na jev*.

**Když běh umře před prvním testem** — `Early unexpected exit, operation never finished
bootstrapping` bez chyby kompilace a bez jediného `✘` — je to **zátěž, ne rozbitý build**.
Pusť ho znovu, viz tatáž sekce.

## Prostředí

- macOS 26, Xcode 26, Swift 6.3
- Vyžaduje na stroji `gh` (přihlášený), `claude` a `git`
- **App Sandbox vypnutý** — aplikace spouští podprocesy a zapisuje do vlastní cache
- **Podpis je stálý, ne ad-hoc** (#61). `Signing.xcconfig` drží ad-hoc default a přes
  `#include?` si tahá gitignorovaný `Signing.local.xcconfig` s jménem certifikátu, který
  vyrobí `bin/setup-signing.sh`. Ad-hoc podpis nemá stálou identitu, takže po každém buildu
  je to pro macOS jiná aplikace a **udělená TCC povolení propadnou** — dotaz na Stažené
  soubory (kam leze `claude` přes `~/.zshrc`) se pak vrací pořád dokola. Podrobnosti
  v README, sekce *Podpis*. Dvě věci, na které se u toho naráží:
  - **Identita se nesmí zadrátovat do `project.pbxproj`.** Build s certifikátem, který na
    stroji není, končí `No certificate matching 'PRism Local' found` — ověřeno. Proto je
    fallback v checkovaném xcconfigu a jméno v tom lokálním, ne naopak.
  - **`CODE_SIGN_IDENTITY` je jen na úrovni projektu.** Kdyby zůstalo v buildSettings
    targetů, přebilo by xcconfig a lokální soubor by neměl žádný efekt.
- **Binárky hledej absolutní cestou.** GUI aplikace spuštěná z Finderu nedědí `PATH` ze
  shellu, takže `gh` se podle jména nenajde. Řeší `BinaryLocator` při startu; cesty se
  berou z `ToolPaths`, nikdy z názvu binárky.
- **Aplikace se provozuje z `/Applications`** (#88). Odjinud macOS nepovolí notifikace —
  změřeno, podrobnosti v sekci `App/Environment/`. `bin/run.sh` tam bundle instaluje sám,
  takže ručně se nic dělat nemusí; `build.noindex/` zůstává jen místem, kde se buildí.
- **Buildí se do `build.noindex/`, ne do `build/`** (#139). Bez té přípony si LaunchServices
  kopii **samo zaregistruje** — změřeno, po odregistrování je do 25 vteřin zpátky
  (`.metadata_never_index` uvnitř složky s tím nehne, taky změřeno) — a ve Spotlightu pak
  stojí dva PRismy se stejným jménem, ze kterých se nedá vybrat. Záznam navíc přežije
  i smazání bundlu, takže se jich časem nasbíralo devět. Příponu `.noindex` používá na totéž
  sám Xcode (`Intermediates.noindex`).

  **Samotná přípona nestačí:** Xcode bundle na konci buildu registruje výslovně
  (`lsregister -f -R -trusted`) a `xcodebuild test` ho navíc **spouští**, což ho zaregistruje
  taky. `bin/run.sh` proto po instalaci tu jednu cestu odregistruje — a protože do
  `build.noindex/` míří i testy, uklidí tím i po nich. Selhání se **hlásí, ale nepokládá
  skript**: kvůli záznamu v databázi se nemá nespustit aplikace. Obě chybové větve jsou
  vyzkoušené spuštěním, ne jen přečtené.

## Stav

Co je hotové a co zbývá, je v [`docs/stav.md`](docs/stav.md) — souvislý záznam včetně toho,
co se cestou rozhodlo jinak, než bylo v zadání. **Aktualizuje se, jak fáze ubývají.**

Rozsah v1 podle specifikace je hotový; hotové jsou i milníky M6 (odesílání review), M7
(konverzace) a M8 (notifikace), tedy poslední naplánované. Co přijde teď, jde přes issues.
