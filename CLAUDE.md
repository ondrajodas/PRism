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
- **Commit messages, názvy branchí a titulky PR anglicky.** Formát
  [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- **Popisy PR česky.** Titulek zůstává anglicky (je z něj commit message při mergi),
  ale tělo PR je próza pro mě — a próza se v tomhle repu píše česky. Platí i pro
  komentáře na PR a odpovědi na review.
- **Release notes česky** (viz Pracovní postup).
- **Žádné AI atribuce** v commitech ani v PR — bez podpisů a bez „generated with“.

## Pracovní postup (git)

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

  Napiš, **na co se mám podívat** a co v příslušné obrazovce uvidím.

  **Když se změna v UI nijak neprojeví** (vrstva bez UI — modely, parser, protokol),
  **na pauzu mě netahej.** Neviditelnou změnu nemám jak proklikat, takže by pauza jen
  brzdila. Napiš do shrnutí jednou větou, že vidět není nic a proč, dolož to zelenými
  testy a **pokračuj rovnou na commit a PR** — kontrola proběhne nad diffem na PR.
  Rozhodující je, jestli se něco změnilo na obrazovce, ne jestli je změna malá: oprava
  jednoho textu v labelu se ukazuje, nový `Codable` model ne.

  Když ke stavu, který chceš ukázat, nejde přijít normálním používáním (chybějící binárka,
  chyba sítě), viz *Jak si zkontrolovat, jak view vypadá* v sekci Testování — a hlavně
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
- **PR, který je v pořádku, mergni sám.** Nečekej na pokyn: zelené testy, vyřešené nálezy
  a hotové zadání issue stačí. Po mergi rovnou **zavři issue** a **vydej release**.
  Když si nejsi jistý, jestli je hotovo, tak hotovo není — dodělej to, neptej se.
- **Po mergnutí PR se vydá nový tag a GitHub release.** Release notes píšeme česky a
  popisují progress: co se změnilo, jaký je aktuální stav proti milníkům a co je další
  krok. Release je deník projektu — kdo si přečte poslední release, ví, kde jsme.
- **Verzování:** `v0.<milník>.<pořadí PR v milníku>` — např. třetí mergnutý PR
  v milníku 1 je `v0.1.3`. Verze `v1.0.0` = dokončený rozsah v1 podle specifikace.

  **Milník `Průběžné` číslo nemá** — je to koš na věci mimo fáze (provoz aplikace,
  drobnosti, opravy). PR z něj **pokračuje v číslování běžící fáze**, protože verze je
  značka na časové ose, ne štítek původu. Vlastní řada by znamenala, že se čísla vracejí
  zpátky: `v0.0.x` po `v0.5.7` nikomu neřekne, kdy to vzniklo.
- Binárky se do release nepřikládají — buildujeme lokálně. Release slouží k záznamu
  postupu, ne k distribuci.

## Co aplikace je

Nativní macOS aplikace (SwiftUI), která hlídá GitHub PR přiřazené mně k review, spouští
na ně review skilly Claude Code jako headless session a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Když se objeví
potřeba „chytřejšího“ review, patří to do skillu, ne do aplikace.

Plný návrh: [`docs/superpowers/specs/2026-07-31-prism-design.md`](docs/superpowers/specs/2026-07-31-prism-design.md)

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

Když na něco narazíš, co návrh v issue mění (zjistíš, že to nejde, jak je napsané),
**není to důvod se ptát** — rozhodni, zapiš do specifikace **co se změnilo a proč**,
a napiš to do popisu PR. Posoudí se to nad diffem.

Ptát se dál na **tvrdé podmínky** níž. Merge PR ani zavření issue mezi ně **nepatří** —
to si od 2026-08-01 řídíš sám, viz pracovní postup.

## Tvrdé podmínky

Tohle nejsou zjednodušení první verze. Než něco z toho porušíš, zastav se a zeptej se.

1. **Jediná cesta ven** (od #67; do té doby tu stálo „nikdy nic neposílat na GitHub“).
   Aplikace **umí** odeslat review a od #73 se **ozvat do vlákna** — ale jedině přes
   `ReviewPublishing`, jedině na výslovný pokyn člověka a jedině tam, kde se to **v nastavení
   povolilo**. Pravidlo se skládá z šesti věcí a každá z nich je kontrolovatelná:

   1. **`GitHubGateway` zůstává bez zápisových metod.** Polling, diff, checkout ani reviewer
      tedy nemají čím něco odeslat — read-only je pořád vidět z typu.
   2. **`grep ReviewPublishing App/` vyjmenuje všechna místa, odkud to jde.** Mají to být
      **čtyři soubory a dva volající**: protokol, `GhReviewPublisher` (implementace),
      `ReviewSubmission.send()` (review) a `ThreadSubmission` (odpověď a vyřešení vlákna).

      Protokol má **tři vyjmenované metody** — `submit`, `reply`, `setResolved`. Do #73 měl
      jednu a stálo tu, že cokoli dalšího by byla druhá cesta ven; změnilo se to proto, že
      odpovědět kolegovi do vlákna je půlka toho, kvůli čeho se u review přepíná do
      prohlížeče, a přes `GitHubGateway` to jít nesmí (bod 1). Co **zůstává**: výčet je
      krátký, vyjmenovaný na jednom místě a **každá metoda si sama ověří bránu z bodu 6** —
      proto všechny berou adresu, ze které se pozná repo. Roste-li ten výčet, roste to, co
      aplikace umí odeslat, a to má být vidět v jednom souboru. Approve mimo review, label ani
      komentář pod PR tam pořád nepatří.
   3. **Publisher není pole `AppStore`.** Vzniká uvnitř té cesty, která odesílá, a zaniká
      s ní — nemá ho kde uložit nikdo, kdo ho nemá mít. Drží to `ReviewSubmission` (skládá se
      až v `send()`, zaniká zavřením sheetu) a `ThreadSubmission` (skládá se v `reply(_:)`
      a `setResolved(_:)`). `AppStore` si kvůli odesílání drží **jen cestu ke `gh`**, ne
      publisher ani továrnu na něj — proto ho ten grep nevypíše. Platí to i pro vlákna, kde
      `AppStore` odesílání spouští: drží **stav** (`ThreadActionState`), ne cestu ven.
   4. **Odeslání review si žádá hotový draft s `headSha`** a pre-flight ověří, že je to pořád
      hlava PR. Approve na kód, který jsi neviděl, tak nejde poslat ani závodem s pushnutým
      commitem. GitHub proti tomu **nechrání** — změřeno u #62, že review se zastaralým
      `commit_id` přijme.

      **U odpovědi do vlákna se `headSha` neověřuje** (#73) a je to schválně: odpověď se váže
      na vlákno, ne na commit, takže kontrola hlavy by zakázala zrovna tu situaci, kvůli které
      se do vlákna píše („opraveno v abc123“). Ověřuje se **stav PR**, a to i tam
      **striktněji než GitHub** — změřeno u #73, že odpověď na zavřeném PR projde. Aplikace
      ukazuje PR z `review-requested`, takže mergnutý PR ze seznamu vypadne a k jeho vláknům se
      z okna nedostaneš; psát do uzavřené diskuze patří do prohlížeče.
   5. **Jedno atomické volání.** Buď odejde všechno, nebo nic; žádný částečně odeslaný stav
      po pádu uprostřed. Změřeno u #62. U vláken je to triviálně splněné — odpověď i vyřešení
      jsou jedna mutace.
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

   Co se **nezměnilo**: návrh verdiktu z nálezů (`ReviewVerdict`) je pořád jen návrh
   zobrazený v aplikaci a sám nic neodesílá. Odesílá jen člověk. **Potvrzovací sheet je jen
   u review** — odpověď do vlákna se podle #73 nepotvrzuje, protože je to jedna věta v diskuzi,
   dá se smazat a potvrzování každé by z okna udělalo klikačku. „Výslovný pokyn člověka“ tedy
   u review znamená dvě kliknutí na dvou různých tlačítkech, u odpovědi jedno pojmenované.
2. **Reviewer je read-only.** V `--allowedTools` není `Write` ani `Edit`, u `Bash` se uvádí
   jen `git` — a v `--disallowedTools` jsou `Bash(gh:*)` a `Bash(git push:*)`. `Skill` mezi
   povolenými je (#78); sám o sobě nic nespouští, ale skill, který se přes něj načte, si
   o odeslání na GitHub umí říct — proto ten zákaz.

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

## Architektura

Osm modulů. Čtyři, které sahají do vnějšího světa, jsou za protokolem, aby byly v testech
nahraditelné fake implementací. Osmý (`ReviewPublisher`, #67) je jediný, který **zapisuje** —
viz tvrdá podmínka č. 1.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a syrový diff | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings` | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Stav řádku podle checkoutu, blokující příznak, návrh verdiktu, detekce shody `2×`, řazení | — |
| `Config` | Globální default + override per repo, tolerantní čtení `config.json` | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu | — |
| `ReviewPublisher` | **Jediná cesta ven**: odeslat rozdělané review na GitHub, a `ReviewSubmission` jako jediný volající | `gh` CLI |

Nad tím SwiftUI views: `PRList`, `DiffView`, `FindingsPanel`. Mimo tuhle sedmičku stojí
`App/Diff/` — překlad diffu na model a jeho řádky. Není to modul: v doméně review nemá
diff jinou roli než být vidět. Totéž platí o `App/Health/` (#31): dostupnost služeb je
o tom, jestli jde review vůbec spustit, ne o review samotném.

**Kam co psát:** rozhodovací logika patří do `Policy` jako čistá funkce — tam se testuje
bez mockování. Když se přistihneš, že píšeš `if` nad nálezy někde ve view nebo v runneru,
patří to do `Policy`.

### Doménové modely (`App/Models/`)

Typy, na kterých staví všechny moduly — proto vlastní složka, ne příslušnost k jednomu
z nich. Žádné I/O, jen data. Všechny jsou `Codable`, `Hashable` a `Sendable`.

| Typ | Co je |
|---|---|
| `RepoID` | `owner/repo` |
| `PRIdentifier` | `owner/repo#číslo` — klíč všeho, co se váže k PR: dedup zdrojů, review stav, uložené nálezy |
| `PullRequest` | Metadata z `gh`: `id`, titulek, autor, `headSha`, `baseSha`, url, `updatedAt`, stav, **popis** (`body`) |
| `PullRequestSummary` | Totéž **bez SHA** — co dá vyhledávání. Viz `App/GitHub/` níž |
| `Source` | Zdroj PR: jméno pro UI + search dotaz. Default `Source.reviewRequested` |
| `ReportedFinding` | Nález přesně jak ho poslal reviewer; `FindingVerdict` je `CONFIRMED`/`PLAUSIBLE` |
| `Finding` | `ReportedFinding` + **kdo** ho našel (skill) a **proti čemu** (`headSha`) |
| `PullRequestState` | `open` / `draft` / `merged` / `closed` |
| `ReviewState` | Stav review v řádku seznamu — deset případů, viz níž |
| `ReviewVerdict` | Návrh, co s PR udělat: `approve` / `requestChanges`. Jako jediný **není `Codable`** — neukládá se, odvozuje se z uložených nálezů |
| `ProjectLanguage` | Čím je repo psané — klíč mapy „jazyk → sada skillů“. **Není to `Syntax.Language`**, viz níž |
| `FindingsLanguage` | Jazyk prózy v nálezech (`cs`/`en`). Ani tohle **není `ProjectLanguage`** |
| `FindingTranslation` | Přeložená próza nálezu. Visí vedle originálu, nepřepisuje ho |
| `Conversation` | Cizí konverzace pod PR: review ostatních, vlákna, komentáře + `viewer` |
| `ConversationPage` | Kus seznamu a kolik ho je celkem — nese **zkrácení** |
| `ReviewThread` | Vlákno u řádku diffu: cesta, `line`/`originalLine`, `isResolved`, `isOutdated`, **práva viewera** (`canResolve`/`canUnresolve`) |
| `ThreadComment` | Jeden komentář — ve vlákně i pod PR; `replyToID` místo vnořování |
| `SubmittedReview` | Hotové review od někoho jiného; stav je vnořený `SubmittedReview.State` |
| `DiffSide` | `left`/`right` — ke které straně diffu se vlákno nebo komentář váže |
| `ReviewDraft` | Rozdělané review: PR, `headSha`, tělo, verdikt, komentáře. Verdikt je vnořený `ReviewDraft.Verdict` |
| `ReviewDraftComment` | Řádkový komentář draftu: kotva (`path` + `DraftAnchor`), tělo, `Origin`. Kotva nese **rozsah** (#110) |
| `DetailState` | Stav dotažení detailu PR: `loading` / `loaded(PullRequest, updatedAt:)` / `failed`. Je z něj `headSha` pro draft a popis pro `Přehled` |
| `PullRequestTab` | Který tab PR je vidět: `overview` / `filesChanged`. Jako `ReviewVerdict` **není `Codable`** |
| `DiffLayout` | Jak se kreslí diff: `unified` (pod sebou) / `split` (vedle sebe). Nastavení **člověka, ne repa** — proto jen v `GlobalConfig` |

Tři věci, které se u nich nemají rozbít:

- **`PRIdentifier` je `Comparable` a čísla se srovnávají číselně.** Řadit podle
  `description` je past, do které repozitář spadl **třikrát** (`ReviewStore`,
  `PullRequestList`, `ReviewDraftStore`): řetězcově vyjde `#10` před `#2`. Determinismus by
  to zachovalo, ale výpis, ve kterém jde desítka před dvojkou, vypadá rozbitě — a to je
  jediná věc, kterou od pořadí chceme. Všechna řazení proto jdou přes `<` na identifikátoru.
- **Identifikátory se kódují na jediný řetězec**, ne na objekt s poli. Existuje pak jeden
  kanonický zápis pro disk, klíč slovníku i UI. Parsování a formátování drží
  `LosslessStringConvertible` (`init?(_:)` + `description`) a `Codable` ho jen používá.
  `CodingKeyRepresentable` je tam proto, aby `[PRIdentifier: ReviewState]` v JSONu vyšlo
  jako objekt, ne jako pole střídavých klíčů a hodnot.
- **`ReviewState` rozlišuje chybové stavy**, protože každý vede jinam: `clean` (doběhlo,
  nic nenašlo) je opak `failed` (session spadla), `checkoutFailed` se spraví opakováním
  clonu a `timedOut` si drží částečné nálezy. Případy: `notStarted`, `queued`, `cloning`,
  `checkoutFailed(detail:)`, `running(finished:total:)`, `clean`, `completed(findings:)`,
  `failed(detail:)`, `timedOut(findings:)`, `stale`.
- **`clean` vzniká jen přes `ReviewState.finished(findingCount:)`.** Jinak se dřív nebo
  později objeví `completed(findings: 0)`, což je totéž vyjádřené hůř.

- **Tři různé „jazyky“ se nesmí slít.** `ProjectLanguage` říká, čím je repo psané (vybírá
  skilly), `FindingsLanguage` jazyk prózy v nálezech (jde do promptu), `Syntax.Language`
  pravidla obarvení. Odpovídají na tři různé otázky a jediné, co sdílejí, je slovo v názvu
  — proto se i v UI píše „programovací jazyk“ a „jazyk nálezů“, nikdy jen „jazyk“.
- **`FindingsLanguage` je uzavřený výčet**, i když skilly, kategorie i model jsou volné
  řetězce. Hodnota jde do **anglické věty v promptu** a do **českého popisku v okně**;
  u volného řetězce by první záviselo na tom, jak ho uživatel napíše, a druhé by nešlo
  ukázat vůbec. Přidat jazyk je jeden case a dva řetězce.
- **`ProjectLanguage` a `Syntax.Language` jsou dva různé výčty schválně.** První odpovídá
  na „co je tohle za projekt“, druhý na „jak tenhle řádek obarvit“ — a patří k němu YAML,
  JSON i Markdown, které o projektu neříkají nic. Spojit je by znamenalo, že rozpoznat
  Python vyžaduje umět ho obarvit, a že každý repozitář vyjde jako „YAML“.

Kolik nálezů blokuje, se z `ReviewState` **neodvozuje** — to je `Policy`.

Nad konverzací (#63) platí:

- **Cizí konverzace není náš nález.** `Finding` je to, co našel reviewer; `ThreadComment` je
  to, co napsal člověk na GitHubu. Mají stejné místo v diffu a nic víc, takže se nesmí slít
  ani v modelech, ani v UI.
- **Tři „review“ se nesmí splést.** `ReviewState` je stav našeho běhu v řádku,
  `ReviewVerdict` náš návrh, co s PR udělat, a `SubmittedReview.State` cizí hotové
  rozhodnutí z GitHubu. Třetí je proto **vnořený** — `SubmittedReview.State` se s těmi dvěma
  nedá zaměnit ani při doplňování v editoru. Tatáž past jako u tří „jazyků“ výš.
- **Zkrácení nese `ConversationPage`, ne volající.** `isTruncated` je `or` **dvou** signálů
  z GraphQL (`hasNextPage` a `items.count < total`), protože nebezpečný směr je jediný:
  tvrdit „máš všechno“, když ne. `or` se v něm splést nemůže. `total` se drží i tak, protože
  z něj vyjde „1 ze 38“ — samotný boolean řekne jen, že něco chybí, ne kolik.
- **`Conversation.isTruncated` se dívá i do vláken.** Useknutá odpověď **uvnitř** vlákna se
  na počtu vláken neprojeví — a je to zrovna ta odpověď, kvůli které se člověk do vlákna
  dívá.
- **Zastaralé vlákno nemá `line`, ale `originalLine` ano.** Ověřeno na `cli/cli#13084`: ze
  38 vláken bylo 24 `isOutdated` a `line == nil` právě u těch 24, ani jedna výjimka v žádném
  směru. Stejné chování má REST (#62). Kotvu proto dává `anchorLine` (`line ?? originalLine`)
  — vlákno bez čísla se nemá kde ukázat a zmizelý komentář kolegy je horší než komentář na
  starém řádku.
- **`replyToID`, ne vnořený komentář.** GitHub vrací vlákno jako plochý seznam; skládat
  z něj strom by znamenalo rozhodovat, co s odpovědí na komentář, který v odpovědi není
  (useknutá stránka). Plochý seznam s odkazem zpátky tu otázku neotevírá.
- **`viewer` se drží jednou na `Conversation`**, ne jako `isMine` na každém komentáři. „Je to
  moje“ je vztah mezi komentářem a tím, kdo se dívá, ne vlastnost komentáře — uložený příznak
  by po změně účtu tvrdil něco jiného, než je pravda.
- **Neznámý stav review konverzaci nepoloží** (`state == nil`), na rozdíl od neznámého stavu
  PR, který vyhodí chybu. Ze stavu PR plyne chování (draft se sám nereviewuje); tady jde
  o zobrazení cizího názoru a kvůli jedné nové hodnotě GitHubu nemají zmizet všechna vlákna.

### `App/Diff/`

Diff pull requestu od načtení po řádky, které se kreslí. Žádné I/O — text přijde
z `GitHubGateway`, tenhle kód mu jen rozumí.

| Typ | Co je |
|---|---|
| `DiffParser` | Unified diff → `Diff`. **Nikdy nevyhodí výjimku** |
| `Diff` | Soubory + `unrecognizedLines`; součty `additions`/`deletions` |
| `FileDiff` | Cesty, druh změny (`added`/`deleted`/`modified`/`renamed`), `isBinary`, hunky |
| `DiffHunk` | Rozsahy, nadpis sekce za druhým `@@`, řádky |
| `DiffLine` | Druh (`context`/`added`/`removed`/`meta`), stará a nová čísla, text |
| `DiffRow` | Diff rozbalený na řádky pro vykreslení, včetně bublin nálezů a **dvojic** pro pohled vedle sebe, + `anchor(in:file:line:)` pro skok z nálezu |
| `DiffRow.paired(_:)` | Slití hotových řádků do dvojic (`App/Diff/DiffPairing.swift`) — čistá funkce, celý pohled `split` stojí na ní |
| `DiffState` | Stav načtení per PR: `loading` / `loaded(Diff, updatedAt:)` / `failed` |
| `FileTreeNode` | Soubory diffu jako strom pro navigaci; slévá složky s jediným potomkem |
| `DiffExpander` | Skrytý úsek mimo hunky a kroky, kterými se dá odkrýt |
| `RevealedLines` | Které skryté řádky jsou odkryté; slučuje rozsahy a dělí jimi mezeru |
| `FileExpansion` | Rozbalování jednoho souboru: odkryté rozsahy, obsah, načítání, chyba |

Věci, které se u toho nemají rozbít:

- **Řádek se zařazuje podle stavu (hlavička / hunk), ne podle prvního znaku.** Odebraný
  řádek začínající `---` je jinak k nerozeznání od hlavičky souboru — a `--` na začátku
  řádku se v kódu i v textu vyskytuje běžně.
- **Nerozpoznaný řádek se počítá** (`unrecognizedLines`) a UI to hlásí. Diff, ze kterého
  kus tiše vypadl, vypadá jako úplný.
- **Cesty se berou z `rename from`/`rename to` a `---`/`+++`.** Hlavička
  `diff --git a/… b/…` je u cest s mezerou nejednoznačná a slouží jen jako záchrana tam,
  kde ostatní řádky chybí (binárky, přejmenování beze změny obsahu).
- **`/dev/null` je pravda o souboru, ne chybějící údaj.** Proto se u přidaného souboru
  stará cesta zahodí, i když ji hlavička nabízí — a `--- /dev/null` sám o sobě určí, že
  soubor vznikl.
- **`DiffRow` je jediné místo, které čísluje řádky pro UI.** Skok z nálezu (`anchor`)
  staví na `rows(of:)`, takže se číslování a hledání kotvy nemůžou rozejít.
- **Identita řádku nese cestu souboru** a **neodvozuje se z pořadí v seznamu**
  (`"<file.id>|h2l7"`, `"<file.id>|c184"`). Rozbalení kontextu řádky přidává, takže by se
  poziční identity posunuly a odkaz z nálezu by po rozbalení ukázal jinam.
- **Dokud obsah souboru nedorazí, nic není odkryté.** `rows(of:)` odkryté rozsahy bez
  obsahu ignoruje — jinak zmizí rozbalovací řádek i se spinnerem a zůstane po něm prázdno.
- **Rozbalená mezera sundá hlavičku hunku.** Slité části jdou nepřetržitě za sebou a `@@`
  uprostřed neodděluje nic. Mezera, která nikdy nebyla, hlavičku nechává.
- **Skryté úseky se počítají v číslech nového souboru**, staré se dopočítá posunem
  (`old = new − shift`), který nadělal předchozí hunk.
- **Bubliny se zavěšují nad hotovým seznamem řádků**, ne uvnitř skládání. Sednou proto
  i na rozbalený kontext, aniž by o nich ta větev věděla.
- **Nález, jehož řádek v diffu není, nezmizí** — vyjde jako bublina s `anchored: false`
  na začátku souboru. Schovat ho by znamenalo, že si ho nikdo nepřečte; reviewer čte celý
  pracovní strom, takže mimo diff hlásí běžně.
- **Nezakotvené bubliny se řadí podle čísla řádku.** Slovník pořadí nemá, takže by jinak
  mezi překresleními poskakovaly.

Pohled **vedle sebe** (#98) je `DiffRow.pair(_, left:, right:)` a platí u něj:

- **Jeden model, dva pohledy.** Dvojice je case `DiffRow`, ne vlastní typ vedle něj — se
  samostatným typem by se logika bublin, expanderů a kotev psala dvakrát, a to je zrovna ta
  část, na které visí „nález nesmí zmizet“. Cenou je `sourceLines`, přes které se ptají
  bubliny a kotvy místo `case .line`.
- **Slévá se před zavěšením bublin**, ne po něm. Bublina se vkládá za řádek s daným
  `newNumber`, takže by uprostřed bloku přidaných řádků párování rozťala a druhá polovina
  bloku by se spárovala s prázdnem.
- **Identita dvojice je identita pravého řádku** (levého, jen když pravý není). Kotvy
  z nálezů i vláken se hledají podle `newNumber` a ten je vždycky vpravo, takže
  `anchor(in:file:line:)` platí ve split pohledu **beze změny**. Levý řádek dvojice svoje id
  ztrácí — proto je `anchor(in:comment:layout:)` jediná kotva, která pohled zná: komentář
  k odebranému řádku by jinak mířil na id, které v seznamu není. **Hledá se proto nad
  hotovými řádky**, ne nad hunky — jedno místo, které rozhoduje o identitě, se s ní nemůže
  rozejít.
- **Z dvojic se poskládají přesně původní řádky**, žádný se neztratí ani nezdvojí. Je to
  invariant v testech, tatáž pojistka jako „spojení run dá původní řádek“ u obarvování:
  pohled je způsob zobrazení, takže nesmí měnit obsah diffu.
- **Kontextový řádek stojí na obou stranách jako tatáž hodnota.** Z rovnosti se pozná, že je
  to **jeden** řádek souboru — `sourceLines` ho proto vrátí jednou a vlákno ani nález u něj
  nevyjde jako dvě bubliny.
- **`+` po `-` je přepsání, `-` po `+` už nová skupina.** Přidané řádky blok uzavírají,
  jinak by se starý obsah spároval s novým, který s ním nesouvisí. Uzavírá ho i kontext,
  `meta` řádek, hlavička hunku a rozbalovací řádek.
- **Přes celou šířku jde všechno, co stranu nemá**: hlavička hunku, rozbalovací řádek,
  bublina, poznámka i `meta` řádek (`\ No newline at end of file`) — ten není obsah souboru.
- **Pozadí kreslí dvojice, ne buňka** (`DiffPairView`). Buňka se roztáhne jen na svůj obsah,
  takže u kratší (a hlavně u chybějící) strany by pod ní prosvítalo okno a chybějící řádek by
  vypadal jako mezera. Barvy si přitom obojí bere z `DiffLineView.background(of:)`, aby se
  přidaný řádek nekreslil v jednom pohledu jinak než v druhém.
- **Buňka se ptá za svou stranu, takže komentář vznikne tam, kam se kliklo**
  (`draft.action(for:on:)` a `LineAnchors`). Kontextový řádek unese **obě** strany — je v obou
  verzích souboru a `side: LEFT` na nezměněném řádku GitHub přijme (změřeno u #98 na živém API
  v sandboxu, zapíše se jako `side: LEFT`, `line == original_line`; dokumentace GitHubu `RIGHT`
  u nezměněných řádků jen doporučuje). Dvě kola omylů předtím: nejdřív se tlačítko filtrovalo
  podle kanonické strany, takže **vlevo u kontextového řádku nebylo vůbec** (a těch je v diffu
  většina); pak se nabízelo, ale zakládalo komentář vpravo, tedy „okno se otevře jinde, než kam
  jsem klikl“. Dvě tlačítka naráz nevzniknou, `isHovered` je per buňka.
- **Buňka je pružná jen na šířku, ne na výšku.** `maxHeight: .infinity` tam bylo (aby se dala
  najet myší i pod kratší text zalomené dvojice) a **položilo to aplikaci**: main thread se
  zasekl na 99 % v `StackLayout.explicitAlignment` a `ViewResponder.hitTest`, tedy v přepočtu
  layoutu při pohybu myši nad diffem (změřeno `sample`m). Pružná výška v líném seznamu, který
  výšku nenavrhuje, je pro layout engine práce bez konce — v `overlay` a `background` je totéž
  neškodné, protože těm se konkrétní velikost navrhuje. Cena: u dvojice se zalomenou stranou se
  pod kratším textem tlačítko na komentář nenabídne.
- **Moje rozdělané komentáře jsou jeden řádek modelu na řádek diffu**, rozdělený po stranách
  (`draftComments(_, left:, right:)`), a ve split pohledu stojí **vedle sebe ve svých
  polovinách**. Jeden řádek na komentář to neumí: dvě buňky líného seznamu se překrýt nedají,
  takže by komentáře k oběma stranám téhož řádku zůstaly pod sebou. Do které poloviny komentář
  patří, říká jeho `side`; že patří k tomuhle řádku, ověří `Policy.matches` — **obojí je
  potřeba**, protože v pohledu pod sebou (a u kontextové dvojice) je na obou stranách tatáž
  řádka a samotné `matches` by komentář vrátilo dvakrát.
- **Identitu řádku s komentáři dává místo, ne komentář** (`"<id řádku>|d"`). Kdyby vycházela
  z prvního komentáře, vyjmutí levého by ji změnilo a editor toho druhého by přišel o rozepsaný
  text. Identita **bublin** uvnitř je `id` komentáře (`ForEach`), a na tom to `@State` stojí —
  do #98 to bylo `d<uuid>` na celém řádku.
- **Komentáře se neslévají do jedné bubliny**, ani na jedné straně: dva komentáře na řádku jsou
  dvě věci ke stejnému kódu. Ve stejné polovině tedy stojí pod sebou.
- **Nález a cizí vlákno zůstávají přes celou šířku**: nález stranu nemá vůbec (hlásí se proti
  nové verzi) a obojí nese delší text, který by se v půlce mačkal.
- **Rozdělení šířky musí být stejné jako v `DiffPairView`** (dvě poloviny plus 1 pt na čáru),
  jinak komentář přeteče do sloupce, kterého se netýká. Prázdná polovina si šířku **bere** —
  bez toho by se ta plná rozlila přes celý řádek a přestala ukazovat, kam patří.
- **Odsazení bubliny se ve split pohledu krátí o sloupec s čísly** (104 → 52), aby nezačínala
  uvnitř kódu. **U komentáře v polovině se do sloupce s obsahem nezarovnává vůbec** (16): na
  půlce šířky je 52 pt odsazení pro parádu drahé a editor, do kterého se píše, potřebuje místo
  — kam patří, říká svislý pruh bubliny. `indent` mají všechny tři bubliny; do #98 ho měla jen
  `ThreadBubbleView` (kvůli `Přehledu`).
- **Dlouhý řádek se zalamuje, vodorovný scroll ne.** V líném seznamu je scroll na buňku druhý
  zdroj nevykreslených řádků (viz past s hunkem jako buňkou) a dva sloupce by se navíc musely
  scrollovat svázaně.
- **Při úzkém okně se nic nepřepíná samo.** Split v úzkém okně je nepoužitelný, ale pohled,
  který se mění sám, je horší než pohled, který si člověk zvolil špatně — přepínač je po ruce
  v liště.

Vlákna konverzace (#64) se vezou **stejnou cestou** jako nálezy (`DiffRow.thread`), ale
v pěti věcech se chovají jinak:

- **Vlákno bez řádku v aktuálním diffu se nekreslí vůbec.** Je to obráceně než u nálezu,
  který mimo diff visí u hlavičky souboru — a je to schválně: nález je hlášený proti
  **současnému** commitu, takže jeho číslo pořád platí, kdežto zastaralé vlákno má číslo ze
  **starého headu** a bublina by sedla na cizí kód. Domov má v `Overview` (#72), vybírá je
  `Policy.threadsOutsideTheDiff`. Kotví se proto podle `line`, **nikdy** podle `anchorLine`.
- **Vlákna se na jednom řádku neslévají.** Nálezy ano (dva reviewery na jednom řádku dají
  jednu bublinu s odznakem `2×`), vlákna ne: každé je vlastní konverzace s vlastním stavem
  vyřešení. Dvě vlákna na řádku jsou dvě bubliny.
- **Kam vlákno patří, rozhoduje `Policy.matches(_:_:)` — jedno místo pro výběr i umístění.**
  Řídí se `side`: u `right` se číslo porovnává s **novým**, u `left` se **starým**, protože
  komentář k odebranému řádku má číslo ze staré verze souboru. Porovnávat vždycky s novým
  znamená, že vlákno na smazaném řádku 26 sedne na **nový** řádek 26, tedy na jiný kód —
  přesně to, kvůli čemu je `side` v modelu, a přesně to, co se v #64 nejdřív stalo. Chybějící
  `side` se bere jako `right` (výchozí strana GitHubu).
- **Identita bubliny nese `id` vlákna z GitHubu**, ne pořadí. Po obnovení konverzace se
  pořadí může změnit a stav rozbalení by přeskočil na jiné vlákno.
- **Nález jde nad vlákno.** Nález je to, kvůli čemu je okno otevřené; konverzace je kontext.
- **Přepínač `Nálezy` vlákna neschovává.** Jmenuje se tak od #64 právě proto — do té doby
  `Bubliny`, což slibovalo, že vypne obojí (chytilo se to při zkoušení). Cizí komentář
  u kódu je důvod, proč se na PR člověk dívá, takže se s nálezy schovávat nemá.
- **Zkrácené vlákno to hlásí i ve sbalené hlavičce** (odznak `+N`). Vyřešené vlákno je
  sbalené výchozím stavem, takže hláška jen v rozbaleném těle by znamenala, že useknuté
  vlákno vypadá úplné a není důvod ho otevřít. **A o úroveň výš totéž:** když se nevešla
  celá vlákna (`conversation.threads.missing`), hlásí to lišta nad diffem stejně jako
  nepřečtené řádky — chybějící bublina se od „nikdo tam nic nenapsal“ nepozná.
- **Překliknutá vlákna se drží per PR**, ne v ploché množině `id`. `id` vlákna je unikátní
  a samo by na rozlišení stačilo, ale úklid odpovídá na otázku „zmizel PR ze seznamu?“ —
  a ta se z `id` nepozná. Plochá množina uklízená podle **načtených** konverzací se po
  výpadku sítě (`.failed`) vyprázdnila, protože takový stav v mapě zůstane, ale vlákna nedá.
- **Bublina vlákna nemá `.textSelection(.enabled)`**, i když je to text ke kopírování —
  platí tu totéž jako nad celým diffem. `FindingBubbleView` ho ze stejného důvodu nemá.

Odpovídání do vláken (#73) k tomu přidává:

- **Právo přepnout vyřešení říká GitHub, ne my.** Dotaz si bere `viewerCanResolve`
  a `viewerCanUnresolve` a `ReviewThread` drží **obě** — každé platí v jiném stavu vlákna (u
  vyřešeného je `canResolve` false a `canUnresolve` true), takže složit je do jednoho příznaku
  už při mapování by zahodilo, co API řeklo. Co potřebuje okno, dává `canToggleResolution`.
- **Chybějící právo v odpovědi znamená „smíš“**, obráceně než chybějící `isResolved`. Živé API
  obě pole vždycky vrátí, takže `nil` znamená starou odpověď (fixtures z #63), ne odepřené
  právo — a tlačítko schované kvůli údaji, který nedorazil, vypadá jako rozbitá aplikace.
- **Tlačítko `Vyřešit` se schovává, tlačítko `Odpovědět` ne.** Chybějící právo se nedá spravit
  ničím, co je v okně, takže by zakázané tlačítko slibovalo akci, která nikdy nepůjde. Prázdný
  text, běžící odeslání nebo zakázané odesílání jsou naopak stavy, které **mají vysvětlení** —
  tam tlačítko zůstane zakázané s důvodem v nápovědě, jako `DraftPanel.sendButton`.
- **Rozepsaná odpověď žije ve storu** (`AppStore.threadReplies`), ne v bublině: ta je buňka
  líného seznamu, takže `@State` v ní odscrollování nepřežije — tatáž past jako
  u `DraftTextEditor`. Na disk se **neukládá**, na rozdíl od draftu review: je to jedna věta
  v diskuzi a další store by za ni platil souborem na každé vlákno.
- **Selhání text nechává na místě** a hláška to říká větou. Je to zadání #73 a jediná pojistka
  proti tomu, aby se rozepsaná věta ztratila kvůli chvilkovému výpadku sítě.
- **Stav selhání nese, co selhalo** (`replyFailed` / `resolutionFailed`), ne jedno společné
  `failed`. Věta „text zůstal“ patří jen k odpovědi — u vyřešení není co zachraňovat a tvrdila by
  víc, než se stalo. Bez rozlišení v modelu to view nemá jak poznat; chytila to vlastní revize
  diffu u #73, kde se ta věta lepila k obojímu.
- **Prázdná odpověď se neodesílá.** Změřeno u #73, že GitHub prázdné tělo přijme, **nic
  nevytvoří** a vrátí exit 0 — takže bez té brány (`ThreadRequest.isSendable`) by okno hlásilo
  odeslanou odpověď, která nikdy nevznikla. Text se posílá netrimovaný (odsazení v ukázce kódu
  je součást zprávy), kontroluje se trimovaný.
- **Odeslaná odpověď se do vlákna vloží bez dalšího čtení** (`Policy.inserting`), protože ji
  mutace celou vrací. Kolo po síti kvůli komentáři, který už máme, by v okně vypadalo jako
  sekání. Když vlákno v konverzaci mezitím zmizí, konverzace se načte **znovu** — odeslaný
  komentář, který se nemá kde ukázat, vypadá jako neodeslaný.

Moje rozdělané komentáře (#66) jsou **třetí druh bubliny** (`DiffRow.draftComments`) a řídí
se z většiny pravidly vláken, protože jsou to taky komentáře ke kotvě:

- **Kotví se podle `side`** (`Policy.matches` nad `ReviewDraftComment`), takže komentář
  k odebranému řádku sedne na odebraný řádek. Je to tatáž funkce a tatáž lekce jako u vláken.
- **Komentář bez řádku v aktuálním diffu se nekreslí**, jako zastaralé vlákno. Neztrácí se:
  celý seznam je v tabu `Moje review`, odkud se dá vyjmout i ten, který se nemá kde ukázat.
  To je rozdíl proti vláknům, kde je náhradní domov až `Overview` (#72).
- **Neslévají se** — dva komentáře na řádku jsou dvě věci ke stejnému kódu. A **panel to říká
  dopředu** (`Policy.linesWithSeveralComments`), protože z nich na GitHubu vzniknou **dvě
  samostatná vlákna, ne odpověď pod prvním komentářem**. Změřeno u #73 v sandboxu: payload
  review se dvěma komentáři na `README.md:8` přidal dvě vlákna po jednom komentáři. Jinak to
  nejde — `comments[]` neumí `in_reply_to` a neodeslané vlákno ještě nemá `id`, na které by
  šlo odkázat; odpovědět jde teprve na vlákno, které z odeslaného komentáře vznikne.
- **Jdou naspod, pod nález i pod vlákno.** Nález a cizí komentář jsou to, co si mám přečíst;
  svoji rozepsanou větu znám.
- **Identita bubliny nese `id` komentáře**, ne pořadí — na tom stojí, že si `@State` editoru
  udrží rozepsaný text mezi překreslením. Od #98 je to `id` v `ForEach` **uvnitř** řádku, ne id
  celého řádku (`d<uuid>`): jeden řádek nese komentáře k oběma stranám, aby mohly ve split
  pohledu stát vedle sebe, a jeho identitu proto dává **místo**, ne komentář.
- **Přepínač `Nálezy` je neschovává**, o důvod víc než u vláken: tenhle text se odešle.

### `Config` (`App/Config/`)

Nastavení ve dvou úrovních. Nahrazuje konstanty, které byly do #23 roztroušené po celé
aplikaci (skilly, blokující kategorie, interval pollingu, limit souběhu, rozpočet cache).

| Typ | Co je |
|---|---|
| `Configuration` | Celý `config.json`: globální část + `[RepoID: RepositoryConfig]`; `resolved(for:)` a `activeSources` říkají, co doopravdy platí |
| `GlobalConfig` | `sources`, `skills`, `skillsByLanguage`, `blockingCategories`, `mode`, `allowsPublishing`, `findingsLanguage`, `diffLayout`, interval, souběh, `autoRunsPerDay`, rozpočet, model |
| `RepositoryConfig` | Override pro jedno repo: `mode`, `allowsPublishing`, `findingsLanguage`, skilly, kategorie — **všechno volitelné** |
| `ResolvedConfig` | Co z toho vyjde pro jedno repo — `resolved(for:)` je čistá funkce |
| `ConfigStore` | Aktor nad souborem: načtení, založení chybějícího, atomický zápis |
| `ConfigurationBox` | Aktuální konfigurace pro kód mimo hlavní vlákno (limit souběhu, rozpočet, model) |

Věci, které se u toho nemají rozbít:

- **Dekóduje se tolerantně, i uvnitř repa.** Chybějící klíč znamená „ber výchozí“, ne
  „zahoď celou konfiguraci“ — ručně psaný soubor málokdy obsahuje všechno. Platí to
  hlavně na `RepositoryConfig`: override, který mění jen skilly, je to nejběžnější, co
  do souboru někdo napíše, a povinný `mode` by kvůli němu shodil celý soubor.
  **Výjimka je `sources` a `skills`** — tam se rozbitá hodnota hlásí, protože tiše
  podstrčený výchozí seznam by ukazoval cizí PR nebo pustil jiné reviewery.
- **Rozbitý soubor se nepřepisuje** a chyba je vidět nad seznamem. Aplikace běží na
  defaultech, ale mlčet o tom nesmí.
- **Hodnoty se čtou při použití**, ne při startu: limit souběhu při každém pokusu o slot,
  rozpočet při každém úklidu, skilly při spuštění review. Proto stačí načíst a nemusí se
  restartovat.
- **Nula souběžných session se bere jako jedna.** Překlep nemá aplikaci umlčet.
- **Prázdný seznam skillů u repa je vlastní odpověď** („tady nereviewuj nic“), `nil`
  znamená „ber globální“.
- **`RepositoryConfig.mode` je volitelný ze stejného důvodu jako sady.** `nil` = „ber
  globální“, vyplněná hodnota = „řekl jsem si o tohle“. Kdyby byl povinný, nešlo by odlišit
  repo, které si o `manual` řeklo, od toho, které o režimu mlčí — a při globálním automatu
  jsou to opačné odpovědi. Proto taky `setRepository(_:for:)` maže záznam podle
  **prázdnosti**, ne podle shody s globální hodnotou: mazat „stejné jako globální“ by repo
  po přepnutí defaultu tiše zapnulo.
- **Sada podle jazyka je náhrada, ne příspěvek.** `skillsByLanguage[.php]` je celá sada,
  stejně jako override per repo — smysl je vyhodit PHP skilly na Go repu, ne k nim další
  přidat. Rozhoduje **existence** záznamu, ne obsah: `php: []` znamená „PHP tady
  nereviewuj“ a nesmí spadnout zpátky na globální. Když žádný rozpoznaný jazyk v mapě
  není, platí `skills` — ta je tou „hvězdičkou“ z rozpisu #24, druhý zápis téhož by byl
  jen past pro toho, kdo soubor čte.
- **Výchozí mapa je prázdná.** Zadrátovat do defaultů konkrétní skilly (`oj-php-quality-check`
  a spol.) by znamenalo pustit na repa něco, o co si nikdo neřekl — a jsou to skilly
  z uživatelovy konfigurace, ne z tohohle repa.
- **Rozepsaná hodnota z editoru se přeskočí, ne použije.** Řádek v okně nastavení vzniká
  prázdný a uloží se dřív, než se dopíše — takže `resolved(for:)` zahazuje prázdné skilly
  a kategorie a `activeSources` zdroje bez dotazu. U zdroje je to nejdražší: `gh search prs`
  bez výrazu selže a **selhání jednoho zdroje zahazuje celý tik**, takže by kvůli
  rozepsanému řádku zmizel celý seznam PR. Prázdný **seznam** to nemění, ten je pořád
  vlastní odpověď.
- **Jazyk nálezů se řídí stejnými pravidly jako režim** — `nil` u repa znamená „ber
  globální“ a záznam se maže podle prázdnosti, ne podle shody s globálem. Rozdíl je
  v tolerantním čtení: **rozbitá hodnota jazyka spadne na globální**, ne na výchozí.
  U režimu je přísnost kvůli tomu, že překlep by pustil review, o které nikdo nežádal;
  u jazyka je nejhorší následek próza v jiném jazyce.
- **Povolení odesílání (#107) se řídí pravidly režimu, s výchozím stavem vypnuto.**
  `nil` u repa znamená „ber globální“, vyplněná hodnota „řekl jsem si o tohle“ — a `false`
  se proto **nemaže** jako shodné s globálním, jinak by ho přepnutí defaultu tiše otevřelo.
  **Rozbitá hodnota se srazí na `false`** na obou úrovních: je to tatáž přísnost jako u režimu
  a opačná než u jazyka nálezů, protože překlep nesmí otevřít cestu ven. Že je výchozí stav
  vypnutý, drží řádek v testu výchozích hodnot.
- **Pohled na diff (#98) se čte tolerantně jako jazyk nálezů a per repo se nenastavuje.**
  Rozbitá hodnota spadne na výchozí (`unified`) a celý soubor kvůli ní nezmizí — nejhorší
  následek je jiný pohled na diff, který se otočí jedním kliknutím v liště. `RepositoryConfig`
  ho nemá schválně: `mode` nebo `skills` jsou vlastnost repa, kdežto jak se čte diff, je
  vlastnost člověka, který ho čte. **Přepínač v liště do souboru nezapisuje** — odchylka žije
  v `AppStore` (viz níž), jinak by hodnota tady přestala být tou, které se říká výchozí.
- **Rozbitá hodnota režimu se sráží na `manual`, ne na globální default.** Chybějící klíč
  je „ber globální“, ale překlep v hodnotě, kterou se někdo pokoušel automat **vypnout**,
  ho nesmí nechat zapnutý. Platí i globálně.
- **Výchozí hodnoty musí odpovídat konstantám, které nahradily** — je na to test, jinak by
  se aplikace po zavedení konfigurace začala chovat jinak. Výchozí `mode` je `manual`:
  zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.

### `App/Markdown/`

Vykreslení Markdownu z GitHubu — popis PR, komentáře, těla review. Čisté funkce plus tři
malá view, **žádná externí závislost**: stejná úvaha jako u `App/Syntax/`.

| Typ | Co je |
|---|---|
| `MarkdownBlock` | Blok: nadpis, odstavec, položka seznamu (odrážka/číslo/zaškrtávátko), kód, citace, oddělovač, tabulka, `<details>`, HTML komentář |
| `MarkdownParser` | Text → `[MarkdownBlock]`. **Nikdy nevyhodí výjimku** |
| `MarkdownHTML` | Inline HTML na text: `<a href>` na Markdown odkaz, ostatní tagy pryč, entity dekódované |
| `MarkdownText`, `MarkdownBlocksView`, `MarkdownBlockView` | Vykreslení; tři typy kvůli rekurzi v `<details>` |

Věci, které se u toho nemají rozbít:

- **Struktura je naše, inline systémový.** Bloky skládá parser, tučné/kurzívu/`kód`/odkazy
  dělá `AttributedString`. Dávat mu celý text nejde: bloky ve `Text`u **tiše spolkne** —
  z `## Popis` vyjde „Popis“ obyčejným písmem a odrážky ztratí odrážku.
- **Žádný řádek se neztratí.** Je to invariant v testech (obsah ze všech bloků složený zpátky
  dá vstup), tatáž pojistka jako „spojení run dá původní řádek“ u obarvování. Proto se
  v modelu drží i to, co se **nekreslí** (HTML komentář) — zahodit to už v parseru by
  znamenalo, že ztrátu textu nejde odlišit od chyby parsování.
- **Tagy strhává view, ne parser.** Model tak nese to, co přišlo z GitHubu, a rozhodnutí
  „`<p>` se v okně nemá čím projevit“ je vidět tam, kde se kreslí. Odstavec, ze kterého po
  strhnutí nic nezbylo, se **nekreslí** — jinak po každém `</p>` zůstane mezera.
- **`<!-- … -->` se nekreslí vůbec**, jako na GitHubu: je to značka pro stroje
  (`linear-linkback` a spol.), ne text pro člověka.
- **`<details>` je rozbalovátko s vnořenými bloky.** Uvnitř bývají odstavce a seznamy, takže
  jako jeden slitý text nedávají smysl — proto se vnitřek parsuje rekurzivně a proto jsou
  view tři: rekurze přes `some View` je typ definovaný sám sebou, což Swift odmítne.
- **Neuzavřený fence i `<details>` se uzavřou koncem textu.** Useknutý komentář se nesmí
  vykreslit jako prázdno.
- **Uvnitř bloku kódu se nic neinterpretuje** — ani Markdown, ani HTML. `# komentář` v kódu
  není nadpis a `<T>` je kód.
- **Zaškrtávátko je obrázek, ne přepínač.** Je to cizí text, ne můj formulář.
- **Tabulka a blok kódu se nevykreslují „správně“, ale úplně.** Tabulka jsou monospace řádky
  se svislítky (vodorovně scrollovatelné), kód se neobarvuje: jazyk z fence je volný řetězec
  (`sh`, `console`) a `Syntax.Language` se pozná z **cesty k souboru**, takže mapovat jedno
  na druhé znamená hádat — a špatně obarvený cizí kód je horší než neobarvený.
- **Inline kód se nestrhává.** `Array<T>` nebo `Result<OK, Err>` mezi zpětnými apostrofy není
  tag — a je to zrovna to, o čem kolega v komentáři píše nejčastěji. Řídí se to Markdownovým
  pravidlem (zavírá běh apostrofů **stejné délky**), takže ` ``x`` ` unese apostrof uvnitř;
  neuzavřený apostrof kódem není, protože v běžné větě se stane a spolknout kvůli němu půl
  komentáře je horší než neošetřený tag. **Doplněno po nálezu z review #72** — původně se
  strhávalo nad celým řádkem s tím, že HTML v inline kódu je vzácné. `<div>` možná, generický
  typ ne.

### `App/Syntax/`

Obarvení kódu v diffu. Čisté funkce, **žádná externí závislost** — vlastní pravidla místo
highlight.js nebo tree-sitteru.

| Typ | Co je |
|---|---|
| `Language` | Pravidla jednoho jazyka: komentáře, uvozovky, sigily proměnných, klíčová slova. `init?(path:)` pozná jazyk z cesty |
| `SyntaxHighlighter` | Řádek → `[SyntaxRun]`. Stavový průchod po znacích |
| `SyntaxRun`, `SyntaxKind` | Kus řádku a jeho význam: `plain`, `comment`, `string`, `number`, `keyword`, `variable` |
| `SyntaxPalette` | Barvy — Darcula pro tmavý režim, IntelliJ Light pro světlý |

Věci, které se u toho nemají rozbít:

- **Spojení run musí dát původní řádek.** Je to invariant ve všech testech: obarvení
  nesmí text změnit, jinak by se v diffu tiše ztratil znak.
- **Barví se řádek po řádku, bez paměti.** Blokový komentář přes víc řádků se obarví jen
  tam, kde začíná. Diff je útržek — mezi hunky chybí řádky, ze kterých by se stav
  dopočítal.
- **Neznámý jazyk se nebarví vůbec.** Cizí pravidla vypadají jako náhodné skvrny.
- **Řetězec je silnější než komentář i proměnná.** `"// tohle není komentář"` je řetězec
  a `"běží $name"` zůstane jednou hodnotou.
- **Klíčové slovo musí být celé slovo** (`functional` není `func`) a **číslice uvnitř
  jména není číslo** (`utf8`).
- **Proměnné jen tam, kde je poznat sigil** (`$` v PHP a shellu).
- **Obyčejný text vlastní barvu nemá** — dědí ji z okolí, takže soubor bez rozpoznaného
  jazyka nevypadá jinak než ten s ním.

### `StreamParser` (`App/Review/`)

Klíčový spoj: ze `stream-json` výstupu `claude` udělá to, co aplikaci zajímá.

| Typ | Co je |
|---|---|
| `StreamParser` | JSONL řádky → `StreamSummary`. **Nikdy nevyhodí výjimku** |
| `StreamSummary` | Session id, nálezy, **pokusy** o nástroje a odmítnuté nástroje, konec běhu, počty nepřečteného |
| `ReviewOutcome` | Konec běhu podle `result` eventu |

Čtyři věci, které se u toho nemají rozbít:

- **Stream se čte defenzivně (`JSONSerialization`), ne přes `Codable`.** Je to opačně než
  u `gh` — tam si `--json` polem říkáme, co má přijít, takže DTO dává smysl. Tady přichází
  cizí formát, který se vyvíjí, a většina eventů nás nezajímá; typované dekódování by
  padalo na věcech, které jsou aplikaci lhostejné.
- **Nález se deduplikuje podle místa a `summary`, ne podle celé hodnoty.** Reviewer, který
  hlásí průběžně a na konci pošle kompletní seznam, dodá tentýž nález dvakrát — a ověřeno na
  skutečném běhu (#17), že si při tom umí přeformulovat `short_summary`. Porovnání celé
  hodnoty ho proto propustilo. Dva různé problémy na jednom řádku se neslijí, protože se liší
  v `summary`, které je jediné povinné pole.
- **Rozbitý řádek se spočítá, ne vyhodí.** Proces se dá zabít uprostřed řádku a jedna
  useknutá řádka nesmí zahodit nálezy, které už dorazily.
- **`calledReportFindings` je oddělené od prázdného seznamu.** „Nic jsem nenašel“
  (zavolaný nástroj s prázdným polem) a „nereportoval jsem“ (nezavolaný nástroj) jsou
  různé věci — to druhé znamená, že se nálezy nemají kde vzít.
- **Chybějící `result` event znamená, že běh nedoběhl.** Zabitý stream ho nemá (ověřeno
  u #12, je na to fixture) — ale `nil` vyjde i z rozbitého posledního řádku, takže obrácená
  implikace „`nil` = zabito“ neplatí.
- **Zahozený nález se počítá.** `droppedFindings` musí být vidět: bez něj je „nález bez
  povinného pole“ k nerozeznání od „nic jsem nenašel“, tedy od schváleného PR
  s neohlášenou chybou.

### `ReviewRunner` (`App/Review/`)

Jeden běh = jedna headless session `claude` na jeden skill v jednom pracovním stromě.

| Typ | Co je |
|---|---|
| `ReviewRunning` | Protokol: `run(_:progress:)`. Schválně nemá nic, čím by šlo něco odeslat |
| `ClaudeReviewRunner` | Implementace nad `claude` přes `ProcessStreaming` |
| `ReviewRequest` | Zadání: klíč, pracovní strom, `baseSha` (proti čemu diffovat), jazyk nálezů |
| `ReviewRunKey` | `(PR, headSha, skillID)` — identita běhu |
| `ReviewRun` | Výsledek: klíč, `StreamSummary`, `ReviewRunOutcome`; `findings` doplní reviewera a `headSha` |
| `ReviewRunOutcome` | `finished` / `timedOut` / `failed(detail:)` |
| `ReviewProgress` | `queued`, `started(sessionID:)`, `attemptedTool(ToolAttempt)`, `findings(count:)` |
| `ToolAttempt` | Pokus o nástroj: jméno a to, nad čím běžel; umí se zkrátit proti pracovnímu stromu |
| `ReviewerTimeline` | Časová osa jednoho revieweera pro tab Průběh — události s časem, `sessionID`, pracovní strom |
| `ReviewSlots` | Aktor: limit souběžných session (3), fronta v pořadí příchodu |
| `ClaudeCommand` | Čisté funkce: argumenty, prompt, prostředí session |

Věci, které se u toho nemají rozbít:

- **Selhání session není chyba volání.** Spadlá i vytimeoutovaná session se vrací jako
  `ReviewRun` s příslušným `outcome`, protože obojí je výsledek, který se zobrazuje.
  Vyhodí se jen `CancellationError`. Kdyby selhání létalo jako chyba, `clean` a `failed`
  by se v UI slily do jednoho „nepovedlo se“.
- **Timeout si nechá, co stihl.** Proto se stream čte průběžně a `StreamSummary` se plní
  po řádcích: u zabitého běhu jsou částečné nálezy jediné, co je.
- **Zrušený proud skončí bez chyby**, takže po smyčce musí přijít `Task.checkCancellation()`
  — jinak by ze zrušeného review vypadl výsledek, jako by doběhlo.
- **Slučování stejného klíče je nad frontou**, ne pod ní. Připojený požadavek jinak zabere
  druhý slot pro běh, na který sám čeká.
- **Slot se předává, ne vrací.** Mezikrok, ve kterém je volný, by pustil dovnitř běh, který
  si o něj řekl později.
- **Změněný limit se musí projevit na obou stranách.** Čte se při každém pokusu o slot,
  ale to samo nestačí: po **zvýšení** spí čekatelé, které nemá kdo vzbudit (proto
  `admitWaiting()`, které volá `AppStore` po načtení konfigurace), a po **snížení** se
  slot nesmí předat dál, dokud se souběh nevyčerpá na nový strop.
- **`.queued` se hlásí vždycky**, i když je slot volný hned. Rozlišovat „čekal“ od
  „nečekal“ by znamenalo hádat, jestli se `acquire` opravdu uspalo.
- **Prostředí session nese credential helper přes `GIT_CONFIG_*`.** Strom stojí nad partial
  klonem, takže `git diff` proti base commitu si dotahuje bloby ze sítě — a `-c` z
  `RepoCheckoutu` sem nedosáhne, protože `git` spouští sám reviewer. Ověřené to zatím není;
  potvrdí to až první běh nad privátním repem.
- **Prompt o jazyku nálezů mlčí a mlčet musí.** Cokoli, co se do něj přidá, může ovlivnit
  to, co reviewer najde — a ověřit, že neovlivnilo, je drahé: tři běhy nad týmž commitem
  daly 1, 2 a 3 nálezy, takže rozptyl schová jakýkoli efekt menší než ten. Jazyk se proto
  řeší až za review, viz `FindingTranslating` níž. Je na to test, aby se to nevrátilo.
- **Prompt si o skill říká výslovně** (`First call the Skill tool with skill="…"`), ne
  jménem v próze. Do #78 tam bylo jen jméno a skill se načetl v **5 ze 14** běhů — jenže
  příčina nebyla zapomnětlivost modelu: nakonfigurované `code-review` **není skill**, takže
  se nemělo co načíst a model si domýšlel nejbližší id. Změřeno na scratch repu: se jménem,
  které existuje, se skill načte 3/3 i bez pokynu; s neexistujícím si model 3/3 vybral něco
  jiného. Podrobnosti v [`docs/claude-cli.md`](docs/claude-cli.md).
- **V konfiguraci jsou id nástroje `Skill`, ne slash commandy.** Uživatelský skill svým
  jménem, pluginový jako `plugin:skill`. Výchozí je `code-review:code-review`; `code-review`
  je plugin **command** a jako skill neexistuje.
- **Zákazy v promptu přebíjejí skill** a je to tam napsané. `code-review:code-review` má ve
  svých `allowed-tools` `Bash(gh pr comment:*)`, takže si o odeslání na GitHub umí říct sám
  — `--disallowedTools Bash(gh:*)` je nad tou větou pojistka, ne náhrada.
- **Výslovný pokyn zaručí, že se skill načte, ne že se načte ten správný.** Neexistující
  id si model nahradí nejbližším i tehdy, když ho prompt jmenuje — ověřeno na skutečném
  běhu. Osa proto porovnává, co si session vzala (`ReviewerTimeline.loadedADifferentSkill`),
  a záměnu hlásí; bez toho by hlavička tvrdila, že běžel nastavený skill.
- **Reviewer načte i skill ležící v kontrolovaném repu** a řídí se jím. Je to **záměr**:
  repo, které si přinese vlastní review skill, ho má dostat. Vypnout by to šlo
  `--setting-sources user`, neověřeno.

### Překlad nálezů (`App/Review/`)

Nálezy se do jazyka z nastavení překládají **až po doběhnutí review**, ne instrukcí
v promptu.

| Typ | Co je |
|---|---|
| `FindingTranslating` | Protokol: `translate(_:to:)`. Stejně jako `ReviewRunning` nemá nic, čím by šlo něco odeslat |
| `ClaudeFindingTranslator` | Jedna krátká `claude -p` session na celý běh |
| `TranslationCommand` | Čisté funkce: argumenty, prompt, defenzivní čtení odpovědi |
| `FindingTranslation` | Přeložená próza — `summary`, `shortSummary`, `failureScenario` |

Věci, které se u toho nemají rozbít:

- **Překlad nesmí ztratit nález.** Vrací se pole zarovnané se vstupem, `nil` na místě
  znamená nepřeloženo. Nepřeložený nález se ukáže v originále; chybějící by v UI vypadal
  jako neexistující, tedy jako schválený PR s neohlášenou chybou.
- **Páruje se podle `id`, ne podle pořadí.** Model, který jednu položku vynechá nebo
  prohodí, by u pozičního párování přiřadil překlady cizím nálezům. `id` mimo rozsah se
  zahazuje ze stejného důvodu.
- **Odpověď se čte defenzivně (`JSONSerialization`), ne přes `Codable`.** Je to volný text
  od modelu, ne dohodnutý formát: chodí obalený v ```-blocích, s větou navíc, nebo úplně
  jinak. Vykrojí se první `[` až poslední `]`.
- **Selhání překladu není selhání review.** Nálezy dorazily a jsou uložené; nenulový exit
  ani nesmyslná odpověď nesmí položit běh. Že jsou anglicky, je vidět na první pohled —
  mlčení tu nic neschovává.
- **Ukládá se dvakrát: originál hned, překlad po něm.** Kdyby se čekalo na překlad, zavření
  aplikace uprostřed by nálezy zahodilo — a „co doběhlo, zůstane“ je pravidlo, které je
  starší než překlad.
- **Angličtina se nepřekládá.** Reviewer v ní píše sám od sebe (ověřeno na skutečných
  bězích), takže by to byla session za nic.
- **Překladač nedostane jediný nástroj.** Je to transformace textu; session, která nemůže
  nic spustit, nemůže ani omylem sáhnout na repozitář. Zákazy zůstávají jako pojistka.
- **`category` se nepřekládá, protože se neposílá.** Do promptu jde jen próza — nabídnout
  modelu slug znamená riskovat, že ho změní, a na něm stojí blokující sada.
- **Překlad je zobrazení, ne tvrzení.** `Finding.reported` zůstává tím, co poslal reviewer;
  překlad visí vedle a texty se skládají **po polích** (`translation?.summary ?? reported.summary`).
  Kdyby překladateli jedno pole vypadlo, je jeden anglický řádek lepší než chybějící text.

### `App/Support/`

Sdílené drobnosti, které nepatří žádnému modulu. Zatím jedna: `WorkCoordinator` (dřív
`CheckoutCoordinator`) — souběžná volání nad stejným klíčem spojí do jedné práce a zrušení
posledního čekajícího zruší i tu práci. Používá ho `RepoCheckout` (klony, stromy)
i `ReviewRunner` (běhy). Kdyby si každý držel vlastní kopii, existovala by ta jemná logika
kolem rušení dvakrát.

### `RepoCheckout` (`App/Checkout/`)

Vlastní pracovní kopie aplikace. Tvrdá podmínka: **nikdy nesahat na uživatelovy klony.**

| Typ | Co dělá |
|---|---|
| `RepoCheckout` | Protokol: `prepare` (bare klon), `worktree`, `trackedFiles`, `removeWorktree`, `forgetPullRequest` a `trackedPullRequests`. Vše idempotentní |
| `GitRepoCheckout` | Implementace nad `git`: první volání klonuje, další fetchuje |
| `CacheLayout` | Kde co leží — klony, stromy **i uložené nálezy**. `root` je injektovatelný, aby testy nesáhly do skutečné cache |
| `CheckoutCoordinator` | Aktor: souběžná volání nad stejným klíčem se spojí do jedné práce |
| `CacheEviction` | Úklid cache: repa bez otevřeného PR, pak LRU do rozpočtu (10 GB) |
| `CheckoutError` | Typované chyby + klasifikace stderru `gitu` jako čistá funkce |

Věci, které se u toho nemají rozbít:

- **Soubory se vypisují `gitem` (`ls-files`), ne `FileManagerem`.** Ignorované složky
  (`vendor/`, `node_modules/`, buildy) jsou zrovna ty, kterých je nejvíc — procházení
  disku by jimi odhad jazyka převážilo. Ověřené je to integračním testem, protože
  z argumentů poznat nejde, jestli `ls-files` v odpojeném stromu nad partial klonem vůbec
  něco vrátí.
- **Worktree je klíčovaný `(PR, headSha)`**, ne jen PR. Nálezy visí na `headSha`, takže dva
  běhy nad různými commity téhož PR si nesmí sáhnout na stejný strom. Naopak dva skilly
  nad **stejným** commitem strom sdílejí — proto je vytvoření idempotentní.
- **Použitelnost stromu se ověřuje `rev-parse HEAD`, ne existencí složky.** Zabitý
  `worktree add` nechá rozkopírovanou složku se zámkem `initializing`, kterou `fileExists`
  od hotové nerozezná — reviewer by pak četl uříznutý strom. Porovnání s `headSha` navíc
  ošetří, že zkrácený sha v názvu složky může dvěma commitům vyjít stejně.
- **`cat-file` musí běžet s `GIT_NO_LAZY_FETCH=1`.** Na partial klonu si chybějící commit
  jinak **sám dotáhne z promisor remote** — takže „levná lokální kontrola“ chodí na síť,
  bez credential helperu, a fetch `refs/pull/<n>/head` pod ní se nikdy nespustí. Commit by
  pak v klonu ležel bez refu, který ho drží.
- **Každé volání `gitu`, které může sáhnout na promisor remote, potřebuje credential
  helper.** Netýká se to jen `clone` a `fetch`: na partial klonu si bloby dotahuje
  i `worktree add`. Bez helperu skončí u privátního repa hláškou, kterou klasifikace
  zařadí jako `notAuthenticated` — a uživatel se dozví „přihlas se“, i když přihlášený je.
- **Chybějící commit se dotahuje přes `refs/pull/<n>/head`, ne přes samotný sha.** Ten ref
  má na GitHubu **každý** PR včetně forků, kdežto `git fetch origin <sha>` potřebuje na
  serveru povolené `allowAnySHA1InWant`, na což spoleh není. Jedna cesta místo dvou.
- **`worktree remove` potřebuje `--force` dvakrát.** Jedno vynutí odstranění špinavého
  stromu, druhé odemkne zamčený — a zabitý `add` po sobě zámek `initializing` nechává.
  S jedním `--force` na něm `remove` skončí `cannot remove a locked working tree` a stav
  se nedá srovnat vůbec. `prune` za tím uklidí záznamy po stromech, které zmizely bez
  `remove` (pád aplikace, ruční smazání); sám `remove` administrativu uklidí.
- **Eviction nikdy nesmí sáhnout na repo s běžícím review.** Smazat klon pod běžícím
  review by mu vzalo pracovní strom pod rukama. Rozpočet je strop na místo na disku, ne
  důvod rozbít rozdělanou práci — když se pod ním nedá zůstat, zůstane se nad ním.
- **Úklid běží po každém úspěšném tiku, i po tom, který nic nevrátil** — prázdná odpověď
  je informace (PR zmizel ze seznamu). **Po selhaném tiku ne:** seznam po výpadku sítě
  zůstane beze změny a po startu je prázdný, takže by se celá cache smazala kvůli chvíli
  bez sítě.
- **Stromy jsou zanořené pod repem** (`worktrees/<owner>/<repo>/<pr>-<sha>`), ne slepené
  do jednoho jména. Ploché `owner-repo-…` se nedá filtrovat podle prefixu: `keboola-kbc-`
  sedí i na `keboola-kbc-stacks-…`, takže úklid jednoho repa by sahal na stromy jiného.
- **Refy se vypisují `gitem`, ne čtením `refs/`.** `git gc` volné refy zabalí do
  `packed-refs` a složku smaže, takže výpis přes `FileManager` by po prvním gc tiše
  přestal cokoli najít.
- **Do rozpočtu se počítají i stromy.** Klon je `--filter=blob:none`, takže materializované
  soubory leží právě v nich — měřit jen klon znamená měřit menšinu.
- **`FileManager.enumerator` nesestupuje do odkazovaných složek, ale odkaz na soubor vrátí.**
  Změřeno testem u #65, ne převzato — a je to **přesnější** než dřívější formulace „výpis
  z disku sem symlinkem ven nedostane“. Odkaz na složku se opravdu nesleduje; odkaz na
  *soubor* se ale vylistuje a přečetl by se **mimo cache**. `ReviewDraftStore` ho proto
  přeskakuje a počítá. **`ReviewStore` to zatím nedělá** — je na to #106.

  Pozor na past: kontrola „leží soubor tam, kam patří“ postavená na rozbalení symlinků na
  **obou** stranách takový odkaz nezachytí, protože cíl vyjde rovný cíli. Symlink se musí
  odmítnout výslovně (`.isSymbolicLinkKey`).
- **Maže se jen uvnitř cache.** Kdo maže podle toho, co našel na disku, si před smazáním
  ověří, že cesta po rozbalení symlinků pořád leží pod kořenem — `removeItem` přes odkaz
  v rodičovské komponentě smaže **cíl**, ne odkaz. Odpovídá na to `CacheLayout.contains`,
  jedno místo pro eviction i `ReviewStore`.
- **Souběžná volání nad stejným klíčem spojuje `CheckoutCoordinator`.** Dvě review nad
  různými PR téhož repa spustí přípravu naráz a druhé volání by mohlo smazat složku
  rozběhnutého klonu prvního. **Uvnitř koordinované práce se nesmí volat nic, co jde přes
  tentýž klíč** — čekalo by samo na sebe (proto `addWorktree` volá `discardWorktree`, ne
  `removeWorktree`).

- **Dokončený klon se pozná podle vlastní značky** (`prism-clone-complete`), ne podle
  toho, co je uvnitř. `git` zakládá `HEAD` i `config` **hned na začátku** klonování, takže
  po zabitém klonu složka vypadá jako hotový repozitář — a fetch nad ní dokonce projde,
  jen z klonu tiše zmizí `promisor` a partial clone přestane platit.
- **Fetch v bare klonu potřebuje explicitní refspec** (`+refs/heads/*:refs/heads/*`).
  `git clone --bare` `remote.origin.fetch` nenastavuje, takže samotné `git fetch origin`
  jen zapíše `FETCH_HEAD` a větve zůstanou, kde byly. Odhalil to až integrační test.
- **Přihlášení jde přes `gh` jako credential helper v `-c`**, ne přes `gh auth setup-git`
  — ten zapisuje do globálního git configu uživatele. Ověřeno, že helper sám stačí.
  `gh` se volá **absolutní cestou**: helper spouští shell, který `PATH` nezdědil.
- **`GIT_TERMINAL_PROMPT=0` je povinné.** Bez něj se `git` na chybějící heslo zeptá
  a podproces bez terminálu na tom visí až do timeoutu.
- **Cesty se předávají přes `-C`, ne pracovní složkou procesu.** Pracovní složka je stav
  procesu; `-C` je parametr volání a paralelní běhy se nemají jak přebít.

### `ReviewStore` (`App/Store/`)

Výsledky review na disku: jeden JSON soubor na `(repo, PR, headSha)` pod
`reviews/<owner>/<repo>/<pr>-<sha>.json`.

| Typ | Co je |
|---|---|
| `ReviewStore` | Aktor: `save`, `markCurrent`, `load`, `delete`, `cleanUp`. Atomický zápis |
| `AutoRunLedger` | Aktor: kolik review dnes spustil automat. **Na disku**, aby limit nešel obejít restartem |
| `ReviewRecord` | Obsah jednoho souboru: PR, `headSha`, běhy, `isStale`, `closedAt` |
| `StoredReviewRun` | Jeden běh: skill, `outcome`, session id, nálezy, `droppedFindings`, čas |

Vedle něj stojí **`ReviewDraftStore`** (#65) — rozdělaná review, jeden soubor na PR pod
`drafts/<owner>/<repo>/<pr>.json`:

| Typ | Co je |
|---|---|
| `ReviewDraftStore` | Aktor: `save`, `load(for:)`, `load()`, `delete`. Atomický zápis |
| `ReviewDraftStoreError` | Jediná vlastní chyba: v souboru jednoho PR leží draft jiného |

- **Draft bydlí lokálně, ne jako serverové pending review.** Pending review na GitHubu jsou
  **už odeslaná data**: jsou vidět v API, blokují další review (#62: 422 `User can only have
  one pending review`) a každá úprava komentáře by byla volání API. Tím by padla zásada, že
  bez potvrzení nic neopustí stroj.
- **Jeden draft na PR, ne na `(PR, headSha)`.** Nálezy jsou strojový výsledek proti commitu,
  draft je ručně psaná práce — a **nový commit ho nemaže**, jen zablokuje odeslání
  (`Policy.isStale`). Zahodit prózu je dražší než ji nechat s poctivým příznakem; přenesení
  na nový commit řeší #67.
- **Prázdný draft se maže, ne ukládá.** Jinak by v cache zůstal soubor po každém PR, které
  si někdo jen otevřel, a „draft existuje“ by přestalo znamenat „je co poslat“. Tentýž vzor
  jako `Configuration.setRepository`.
- **Draft se `verdict`em a ničím jiným prázdný není.** Schválení bez prózy je plnohodnotné
  review — v datech z #63 čtvrtina vzorku. Chytil to test, který původně tvrdil opak.
- **Draft, který neleží tam, kam podle svého `pullRequest` patří, se do výpisu nedostane**
  a spočítá se jako nečitelný. Jinak by výpis ukázal draft pro PR X, který `load(for: X)`
  nenajde — a rozpor mezi „vidím ho“ a „nedá se otevřít“ je horší než počítadlo. Porovnávají
  se přitom **kanonické cesty**, ne `URL` hodnoty: `FileManager.enumerator` vrací URL v jiné
  podobě než `CacheLayout` (`/private/var` proti `/var`), takže `==` nad `URL` odmítne
  i soubor, který na svém místě je. Chytily to testy, které po té změně zhasly všechny.
- **Nečitelný draft konkrétního PR vyhodí chybu, nevrátí `nil`.** Tichá nula by znamenala, že
  rozepsané review vypadá jako neexistující a člověk by ho psal znovu. Ve výpisu všech se
  nečitelné **počítají** (`Loaded.unreadable`), stejně jako u `ReviewStore`.
- **`drafts/` je mimo dosah eviction**, stejně jako `reviews/` — a tady o to víc, protože je
  to ručně psaná práce. Je na to test, který drží i to, kdyby někdo eviction rozšířil.

Věci, které se u toho nemají rozbít:

- **Store je aktor.** Uložení je čtení, změna a zápis téhož souboru a dva skilly nad jedním
  commitem doběhnou klidně naráz — bez serializace by si výsledky přepsaly.
- **`isStale` je uložené, ne odvozené.** Odvodit by ho šlo jen porovnáním s aktuálním
  `headSha`, jenže ten aplikace z vyhledávání **nedostane** (`gh search prs` ho neumí, viz
  #4). Zjistí ho teprve při dotažení detailu — a to je právě chvíle, kdy se příznak nastaví.
- **Stárnutí umí `save` i `markCurrent`.** `save` ho dělá taky schválně: kdyby to viselo jen
  na `markCurrent`, stačilo by ho jednou zapomenout a nálezy proti neexistujícímu kódu by
  se tvářily jako platné.
- **Zastaralý záznam se nemaže sám.** Je to historie; UI ho ukazuje jako zastaralý. Ručním
  zahozením (#81) ale zmizet **může**: „historie zůstává“ se vztahuje na **ostatní** záznamy,
  ne na ochranu toho viditelného — kdo zmáčkne zahodit nad zastaralými nálezy, chce se
  zbavit právě jich. Odhalil to test, který původně tvrdil opak.
- **`delete` je idempotentní a jen uvnitř cache.** Tlačítko se dá zmáčknout dvakrát;
  chybějící soubor tedy není chyba. Kontrola `layout.contains` je stejná jako u eviction —
  cesta se skládá z `CacheLayout` a ven vést nemůže, ale tvrdá podmínka nemá viset na tom,
  že si to někdo pamatuje.
- **Lhůta na úklid běží od zavření, ne od stáří záznamu.** Proto `closedAt`: PR otevřený půl
  roku by jinak o historii přišel v okamžiku, kdy se zavře. PR, který se do seznamu vrátí,
  lhůtu ruší.
- **`cleanUp` smí běžet jen po úspěšném tiku pollingu** — po výpadku sítě je seznam prázdný
  a úklid by z něj vyvodil, že zavřené je všechno. Stejná past jako u `CacheEviction`.
- **Nepřečtené soubory se počítají** (`Loaded.unreadable`). Rozbitý soubor znamená ztracené
  nálezy a ty se nesmí tvářit jako „review neběželo“.
- **`reviews/` je mimo dosah eviction.** Ta chodí jen po `repos/` a `worktrees/`: nálezy jsou
  kilobajty a řídí se vlastní lhůtou, ne rozpočtem na místo.
- **Záznamy jednoho PR se hledají podle prefixu jména souboru**, ne dekódováním celé
  historie repa — `save` i `markCurrent` běží často. Jméno ale není pravda: tou zůstává
  `pullRequest` uvnitř souboru, který se stejně ověří. Pomlčka je součást prefixu, takže
  `42-` nesedí na `421-`; je na to test.

### `AppStore` (`App/Store/`) a okno (`App/Views/`)

`AppStore` drží to, co kreslí okno: polling seznamu, **výběr řádku**, **stav pracovních
kopií** a **review**. Výběr žije tady, ne ve view — jinak by ho každé přestavění seznamu
zahodilo.

Review orchestruje takhle: `gh pr view` (kvůli `headSha` a `baseSha`) → označit starší
záznamy zastaralými → worktree → skilly paralelně → každý doběhlý uložit do `ReviewStore`.
Limit souběžných session hlídá `ReviewRunner`, ne tenhle kód.

Věci, které se u toho nemají rozbít:

- **Repo s běžícím review je pro eviction nedotknutelné.** `busyRepositories` proto nejsou
  jen repa ve stavu `preparing`, ale i všechna, nad kterými běží review — smazat klon pod
  běžící session by jí vzalo pracovní strom pod rukama.
- **Chyba checkoutu je stav repa, chyba GitHubu stav PR.** Na první narazí i druhé PR téhož
  repa a řeší se stejným tlačítkem; druhá se týká jen toho jednoho PR. Proto má
  `ReviewPhase` vlastní případ `failed`, místo aby se všechno cpalo do `CheckoutState`.
Automatický režim (#25):

- **`headSha` z pollingu není k dispozici**, takže se rozhoduje na dva kroky. Po tiku hrubý
  filtr podle `updatedAt` (levný, bez sítě), a **teprve po dotažení detailu** se porovná
  `headSha` a rozhodne, jestli se utratí session. Komentář na PR tedy stojí jedno
  `gh pr view` a nula sessions. Dotahovat detail všech PR při každém tiku by z jednoho
  pollu udělalo N podprocesů.
- **Ruční spuštění se `headSha` nezastavuje.** Kdo si o review řekl podruhé, chce ho pustit
  znovu; automat se ptá, jestli je to potřeba.
- **Plánuje se jen po úspěšném tiku.** Po výpadku sítě je seznam prázdný — stejná past jako
  u eviction a `ReviewStore.cleanUp`.
- **Počitadlo je v paměti, disk je záloha.** Kdyby se počítalo jen podle souboru, trvale
  selhávající zápis (plný disk, práva) by ho nikdy neposunul a limit by přestal platit
  **úplně** — tedy přesně to, proti čemu je. Nečitelný soubor se naopak bere jako prázdný
  den: umlčet automat kvůli počitadlu, které nejde přečíst, se nedá vysvětlit.
- **Nulový `autoRunsPerDay` znamená vypnuto**, ne „bez omezení“. Je to obrácená volba než
  u nuly souběžných session, a schválně: tam překlep nesmí aplikaci umlčet, tady nesmí
  z překlepu vzniknout neomezené utrácení.
- **Rozpočet se bere těsně před `runSkills`, ne dřív.** Session je utracená v okamžiku, kdy
  běh začne, takže počítat až doběhlé by pustilo dvacet běhů naráz — ale každý krok **před**
  `runSkills` se dá projít bez jediné session, a pak se platí za nic:
  - **v plánovači** se počítalo i za PR, které se po dotažení detailu zahodí. A protože se
    `consideredForAutomation` po restartu vynuluje, spálil každý restart rozpočet za všechna
    auto PR — **šest z dvaceti za jedno dopoledne**, než si toho někdo všiml;
  - **před checkoutem** se platilo i za selhaný klon, tedy za běh, který nezačal;
  - **bez kontroly skillů** se platilo i za repo s prázdnou sadou („tady nereviewuj nic“).

  Vyčerpaný rozpočet zastaví plánování ještě dřív, než se sáhne na síť; PR, který rozpočet
  odmítne, se odznačí, aby o review nepřišel zítra. Klonovat se nemá cenu pouštět kvůli
  zreviewovanému commitu, takže brána na `headSha` zůstává **před** checkoutem — jen už
  nestrhává rozpočet.
- **Pozastavení se počítá při vykreslení, ne při tiku.** Drží se **spotřeba**, ne zbytek:
  limit se dá v nastavení změnit kdykoli a snímek „zbývá 0“ by po jeho zvednutí tvrdil, že
  je pozastaveno, až do dalšího tiku. Chytilo se to na běžící aplikaci.
- **Draft se sám nereviewuje.** Autor na něm pracuje a každý push by stál session. Ruční
  spuštění zůstává. **Změna proti zadání #25**, které to neřešilo.
- **Ruší se jen automatická review.** PR, který zmizel ze seznamu (zavřený, mergnutý),
  nemá blokovat slot — ale ruční review si vyžádal člověk a zrušit mu ho pod rukama proto,
  že to někdo mezitím mergnul, je horší než session navíc.
- **Ruční spuštění maže příznak automatu**, jinak by se ruční běh dal zrušit tím, že PR
  vypadne ze seznamu.

- **Jazyk repa se odhaduje před `runSkills`, ne po nich.** Sada, kterou detekce zapíše, je
  ta, se kterou má **tenhle** běh jet; po skillech by se projevila až podruhé.
- **Detekce běží při každém review, dokud si repo o skilly neřekne.** Rozhoduje
  `repositories[repo]?.skills == nil`; vyplněná sada — **i prázdná** — znamená, že si to
  někdo nastavil, a přepsat mu to by bylo vracení jeho rozhodnutí zpátky. Opakování je
  schválně: mapa jazyků se dá vyplnit až potom, co se repo jednou zreviewovalo, a bez něj
  by se projevila teprve na dalším repu. Stojí to jedno lokální `git ls-files` navíc.
- **Zapisuje se jen to, co se od globální sady liší.** Zápis „stejné jako globální“ by byl
  override, o který nikdo nežádal, a pozdější změna globální sady by takové repo tiše
  minula — stejná past jako u režimu.
- **Nepovedený výpis souborů review nepoloží.** Sada se pak neodvodí a poběží globální,
  tedy přesně to, co běželo před #24; nic se neztrácí a příští review to zkusí znovu.
  Selhaný **zápis** už se ale hlásí (`configurationFailure`) — nastavení, které se
  neuložilo, je přesně to, kvůli čemu se pak hledá, proč něco nefunguje.
- **Ukládá se po každém doběhlém skillu**, ne až na konci — když se aplikace zavře uprostřed,
  co doběhlo, zůstane.
- **Nový head commit zneplatní i záznam v paměti**, ne jen ten na disku. Jinak by řádek celou
  dobu běhu ukazoval nálezy proti kódu, který v PR není.
- **Stav pracovní kopie se po každé fázi srovná podle disku.** Včetně zrušení: bez toho by
  v řádku zůstalo `ve frontě · clone` až do restartu.
- **Zrušení neuloží nic.** Rozdělané review je horší než žádné — a fáze se vrací tam, kde
  byla, ne do chyby.
- **Zahození nálezů odznačí PR pro automat a rovnou ho zváží.** Plánovač si pamatuje
  `updatedAt`, se kterým PR naposledy zvažoval, takže by ho po vyčištění považoval za
  vyřízený až do dalšího pushe — a přitom zahození je právě ta chvíle, kdy se má review
  pustit znovu. Nečeká se na tik, ale jde se **stejnou cestou jako po tiku**: jinak by se
  klikáním na koš utrácely session mimo denní rozpočet. U manuálního repa se nespustí nic.
- **Nezapsaný nález review položí.** Selhání zápisu se nespolkne: ztracený nález by v řádku
  vypadal jako „neběželo“, tedy jako schválený PR s neohlášenou chybou. Ostatní skilly
  přitom doběhnou, ať se nezahodí i to, co se uložit povedlo.

Vzniká z `ToolPaths` po preflightu (`AppStore(toolPaths:)`); **vlastní ho `PreflightModel`
nad scénami**, ne `ContentView`. Okno nastavení je vlastní scéna (`Settings`) a k `@State`
uvnitř hlavního okna by se nedostalo. Testy si podstrčí fake gateway. Smyčka pollingu visí
na `.task` okna, takže zavření okna ji zruší.

| View | Co dělá |
|---|---|
| `ContentView` | `NavigationSplitView`: vlevo seznam, vpravo detail vybraného PR; pod tím stavový řádek |
| `StatusBarView` | Stavový řádek na spodku **okna**: vlevo hlášky, vpravo puntíky služeb |
| `ServiceHealthDot` | Puntík jedné služby; po hoveru důvod a čas poslední kontroly |
| `AppNoticesView` | Hlášky ve stavovém řádku: rozbitá konfigurace, pozastavený automat, nečitelné soubory |
| `PullRequestListView` | Seznam, prázdný stav, úvodní loading, tlačítko obnovit (⌘R) |
| `PullRequestTabBar` | Záložky PR (`Přehled` / `Změněné soubory`) — podtržené, s odznakem počtu |
| `OverviewView` | Tab `Přehled`: popis PR a konverzace bez kotvy v diffu, chronologicky |
| `PullRequestRow` | Repo + číslo + `draft` chip, titulek, autor a relativní čas, odznak stavu, ikona rozdělaného review |
| `PollStatusBanner` | Pruh nad seznamem — **jen když data nejsou čerstvá** |
| `PullRequestDetailView` | Pravý panel: dvouřádková lišta (titulek, review, stav kopie), pod ní diff a nálezy |
| `DiffView` | Diff v plné šířce: souhrn, přepínač pohledu, skokové menu, soubory s ukotvenou hlavičkou, kterou jde sbalit |
| `DiffRowView` | Jeden řádek diffu — hlavička hunku, řádek, dvojice, rozbalovací řádek nebo poznámka |
| `DiffPairView` | Dvojice vedle sebe: dvě buňky `DiffLineView` se `side`, pozadí za celou dvojici, prázdná protistrana |
| `RangeDragActions`, `DiffRowFrames` | Tažení rozsahu komentáře (#110) — akce a rámečky řádků **mimo observable stav** |
| `DiffExpanderView` | Rozbalovací řádek: šipky vlevo v místě čísel a počet skrytých řádků |
| `FindingBubbleView` | Nálezy k jednomu řádku; u nálezu mimo diff nabídne jeho řádek dotáhnout |
| `ThreadBubbleView` | Vlákno konverzace u řádku; vyřešené sbalené s odznakem, moje komentáře odlišené, pole na odpověď a `Vyřešit` (#73) |
| `ThreadActions` | Co se dá dělat s vláknem — rozbalení, odpověď, vyřešení a důvod, proč odesílat nejde |
| `MarkdownText` | Vykreslený Markdown z GitHubu — viz `App/Markdown/` |
| `DraftCommentBubbleView` | Můj rozdělaný komentář u řádku: editor, odznak původu, vyjmutí. Ve split pohledu visí jen v půlce, které se týká |
| `DraftTextEditor` | Textové pole draftu — odložený zápis a doručení při zmizení |
| `DraftPanel` | Tab `Moje review`: banner zastarání, verdikt bez předvyplnění, tělo, seznam komentářů, `Odeslat review…` |
| `ReviewSubmissionSheet` | Potvrzení odeslání: úplný výpis payloadu, průběh, typované chyby |
| `VerdictAppearance` | Ikona a barva verdiktu — jedno místo pro panel i pro potvrzení |
| `DraftActions`, `FileDraftActions` | Co se dá s draftem dělat; druhé svázané s jedním souborem diffu |
| `DiffLineView` | Řádek souboru: dvě čísla (v buňce dvojice jedno, podle `side`), znak změny, obsah obarvený podle jazyka, tlačítko na komentář (na hover) |
| `FindingsPanel` | Spodní panel: taby `Nálezy`/`Průběh`/`Moje review`, návrh verdiktu, tabulka s řazením, prokliky do diffu a zahození nálezů |
| `FindingRow` | Nález převedený na řádek tabulky — texty (včetně nápovědy k místu), identita, blokující příznak |
| `FindingHighlight` | Místo, na které se právě skočilo; bublina na něm chvíli svítí |
| `ReviewTimelineView` | Tab Průběh: sekce na revieweera, události s časem, kopírování `claude --resume`, upozornění na načtený jiný skill |
| `ReviewerChipsView` | Chipy reviewerů: stav a filtr naráz |
| `FileTreeView` | Popover se stromem souborů; odsazení a sbalování si řídí sám |
| `VerdictView` | Návrh verdiktu jako **doporučení**; žádná GitHub akce na něm nevisí |
| `ReviewStateBadge` | Odznak stavu review; texty podle specifikace |
| `AppDelegate` | Ukončení aplikace: dokud běží review, ptá se |

**Zavření aplikace se ptá, dokud běží review** (`AppDelegate`, #94). Session se ukončením
zabije a nálezy, které reviewer už nahlásil, jsou pryč — v panelu i na disku, takže z řádku
vyjde `neběželo`, tedy totéž jako u PR, který nikdo nekontroloval. Nastalo to v provozu.

- **`NSAlert` a `runModal()`, ne SwiftUI.** `applicationShouldTerminate` musí odpovědět
  **synchronně**; asynchronní cesta by aplikaci zavřela dřív, než se kdokoli zeptá.
- **Výchozí tlačítko je `Zpět`**, ne `Ukončit`. Ztracený nález je dražší než jedno kliknutí
  navíc, takže omylem odklepnutý `Enter` nemá nic zahodit.
- **Text říká, co se ztratí.** „Běží review“ samo o sobě nedává důvod kliknout na Zpět.
- **Počítá se z `reviewTasks`**, ze stejného zdroje jako `isReviewing`. Vlastní počitadlo je
  druhé místo, které se s prvním může rozejít — a rozejít se v tomhle znamená zavřít bez
  zeptání.
- **`bin/run.sh` proto nepoužívá `killall`.** SIGTERM `applicationShouldTerminate`
  **neprochází**, takže rebuild při vývoji zabíjel review i s nálezy — dvakrát za jedno
  dopoledne. Skript posílá Apple event `quit`, tedy tou samou cestou jako ⌘Q, čeká na
  odpověď a když aplikace zůstane běžet, novou verzi nespustí.
- **Nezachytí to všechno**, a je to tak zamýšlené: pád aplikace ani zabití zvenčí takhle
  odchytit nejde. Dotažení nálezů z transcriptu zůstává v #94 jako ta drahá varianta pro
  zbytek.

### Okno nastavení (`App/Views/Settings/`)

Scéna `Settings` (⌘, i ozubené kolo v toolbaru přes `openSettings`). Zapisuje do téhož
`config.json`, který jde editovat ručně.

| Typ | Co dělá |
|---|---|
| `SettingsScene` | Obsah scény; dokud neprošel preflight, není store a okno to řekne |
| `SettingsView` | Dvě záložky, patička s cestou a stavem uložení, zámek na rozbitý soubor |
| `SettingsModel` | Rozepsané nastavení: odložený zápis, rozpoznání změny zvenčí |
| `GlobalSettingsView` | Zdroje, výchozí režim a jazyk nálezů, **pohled na diff**, **odesílání na GitHub**, skilly, sady podle jazyka, kategorie, běh |
| `LanguageSkillsEditor` | Mapa „programovací jazyk → sada skillů“; ukazuje jen nastavené jazyky |
| `RepositorySettingsView` | Seznam rep vlevo, režim, povolení odesílání a override vpravo |
| `StringListEditor`, `SourceListEditor` | Editory seznamů — řetězců a zdrojů |
| `SettingsNumberField` | Číslo se šipkami **i** přepsáním; ořezává na povolený rozsah |

Věci, které se u toho nemají rozbít:

- **Rozbitý soubor editor nepřepíše.** Když `configurationFailure` není `nil`, místo
  formuláře je chyba s nabídkou soubor otevřít nebo načíst znovu. Uložit přes něj výchozí
  hodnoty by zahodilo něco, co uživatel psal — kvůli chybějící čárce.
- **Zápis se stejnou hodnotou se zahazuje.** Pole si při zobrazení zapíšou zpátky, co
  v nich je (`TextField(value:format:)` normalizuje, `nil` model se vrací jako prázdný
  řetězec), takže bez té podmínky by **samotné otevření okna** přepsalo ručně editovaný
  soubor. Chytilo se to až na běžící aplikaci: patička hlásila „Uloženo“, aniž by se něco
  změnilo.
- **Ukládá se odloženě** (600 ms po posledním úhozu), jinak by psaní jednoho slova
  znamenalo deset zápisů na disk — a uložilo by mezistavy, které nikdo nechtěl. Zavření
  okna to nečeká a uloží hned (`flush()`).
- **Vlastní uložení se pozná od změny zvenčí.** Zápis se propíše do store a odtud se vrátí
  zpátky do `sync(with:)`; bez porovnání se `settled` by si formulář přepisoval rozepsaný
  text pokaždé, když uložení doběhne. **Po selhaném zápisu se `settled` vrací zpátky** —
  store se nezměnil, takže do `sync` přijde stará konfigurace a bez toho by vypadala jako
  změna zvenčí a přepsala rozepsanou práci. Zároveň by `flush()` viděl `storage == settled`
  a nezkusil to znovu.
- **Čísla se zadávají šipkami i přepsáním.** Samotný `Stepper` nutí doklikat se z 60 na
  600 po jedné, samotné pole nutí psát i tam, kde se mění o krok. A **rozsah musí hlídat
  pole, ne jen `Stepper`** — ten za hranici nepustí, kdežto přepsaný rozpočet na `-5` by se
  propsal do konfigurace a odtud do chování aplikace.
- **Placeholder se předává `prompt:`, ne prvním argumentem `TextField`u.** Ve `Form`u
  s `.formStyle(.grouped)` se první argument vykreslí jako **popisek vlevo od pole**, ne
  jako nápověda uvnitř — u vyplněného řádku to pak vypadá jako dvě hodnoty vedle sebe.
  Chytilo se to až na běžící aplikaci. Popisek přitom zůstává **vyplněný** a schová se
  `.labelsHidden()`: to skryje jen zobrazení, pro VoiceOver je pořád jediný popis pole.
- **`Binding(items)` nad optionalem je past.** Force-unwrapuje při každém čtení a editor
  nad ním jeden překreslovací cyklus přežije i vypnutí přepínače — takže `nil` shodí proces
  v `BindingOperations.ForceUnwrapping`. **Ověřeno pádem aplikace** při vypnutí vlastní sady
  skillů. Odvozený binding se proto píše ručně s `?? []` a zápis se zahazuje, dokud je zdroj
  `nil` — doběhlá editace už zrušeného override by ho jinak vzkřísila.
- **Index je identita řádku v seznamech**, takže mezi odebráním a překreslením se sahá na
  prvek, který v poli už není. `$items[index]` by na tom spadl; bindingy jsou proto psané
  ručně s kontrolou rozsahu.
- **Patička okna jde přes `safeAreaInset`, ne do `VStack`u pod `TabView`.** Se `VStack`em
  přestane být `TabView` tím, co si řídí bezpečnou oblast, formulář si vyhradí místo od
  horní hrany okna a obsah leze **pod lištu se záložkami**. Je to tatáž past jako u pruhu
  nad seznamem PR — a projeví se stejně nenápadně: uříznutým prvním řádkem.
- **Pohled na diff má vlastní sekci, ne řádek v `Režimu review`.** S review nesouvisí a je to
  nastavení člověka, ne repa — proto ho nemá ani záložka rep. A z patičky musí být vidět, že
  **přepínač v liště tuhle hodnotu nepřepisuje**: jinak by nastavení vypadalo jako něco, co se
  samo mění.
- **Žádný text u odesílání se nesmí dát přečíst jako „zapnout automatické odesílání“.**
  Přepínač rozhoduje **jen** o tom, jestli se tlačítko `Odeslat review…` vůbec nabídne;
  odesílá pořád člověk potvrzením, ve kterém je vidět celý payload. Patička to proto říká
  výslovně — a je to tatáž úvaha jako u `VerdictView`, který je taky jen doporučení.
- **V textech se píše „programovací jazyk“, ne jen „jazyk“.** Samotné „jazyk“ se plete
  s jazykem, ve kterém reviewer píše nálezy (#52) — ověřeno tím, že se to spletlo hned
  při prvním zkoušení. Delší popisek je levnější než vysvětlování.
- **Hlavní okno se za nastavením ztmaví, ne rozostří.** `.blur()` protlačí celý strom přes
  offscreen vykreslení **i s poloměrem 0**, takže text ztratí subpixelové vyhlazení a
  v seznamu, diffu i hlavičce vypadá rozmazaně. Ověřeno odebráním modifikátoru. Podmíněně
  ho aplikovat nejde — `if` kolem `NavigationSplitView` mu změní identitu a otevření
  nastavení by zahodilo pozici scrollu v diffu. Překryv s nulovou průhledností
  nerasterizuje nic.
- **Ztmavuje se jen tehdy, když je nastavení opravdu vepředu.** Okno je
  nemodální, takže kliknutím zpátky do seznamu se v něm dá dál pracovat — a rozostřené
  okno, ve kterém zrovna píšu, je horší než žádný efekt. Příznak `isSettingsFrontmost` žije
  v `AppStore` (dvě scény si to nemají kde říct jinudy).

  **`controlActiveState` nerozlišuje „vepředu je jiné okno mojí aplikace“ od „vepředu je
  jiná aplikace“** — obojí je `.inactive`. Proto se ptá okno nastavení na `.key` a ne hlavní
  okno na negaci; kdyby někdy bylo potřeba to rozlišit u aplikace jako celku, je na to
  `NSApp.isActive`.

  **Hlásí to okno nastavení o sobě** (`isSettingsFrontmost`), ne hlavní okno o něm. Hlavní
  okno umí přes `controlActiveState` říct jen „nemám fokus“ — a to je pravda i tehdy, když
  je vepředu úplně jiná aplikace, takže se rozostřovalo bez důvodu. Opačná podmínka
  (`== .active`) nefunguje taky: neaktivní okno hlásí `.inactive`, ne `.active`, takže se
  nerozostřilo nikdy. Zeptat se toho okna, které fokus má, je jediná varianta, co drží.

  **Šednutí textu v neaktivním okně s tímhle nesouvisí** — to kreslí macOS a chová se tak
  i Finder a Mail. Ověřeno tím, že text šedne i ve stavu, kdy se rozostření vůbec nespouští.

Diff drží taky `AppStore` (`diffStates`), klíčovaný PR:

- **Cachuje se podle `updatedAt`.** Přepínání mezi PR je nejčastější pohyb v okně a každé
  by jinak stálo podproces a kolo po síti. Načítá se z `.task(id: pullRequest)`, tedy nad
  celým shrnutím — nový commit změní `updatedAt` a diff se načte znovu i bez přepnutí PR.
- **Rozdělané načítání se za platný diff nepovažuje.** Dvě souběžná načtení jsou jen
  volání navíc; přeskočit to jediné, které běží, znamená prázdno v okně až do dalšího
  výběru.
- **Zrušení maže jen rozdělaný stav.** Mezitím spuštěné načtení už mohlo doběhnout a to se
  přepsat nesmí.
- **Diff PR, které zmizelo ze seznamu, se zahodí** — jsou to megabajty. Rozdělané načítání
  přežije ze stejného důvodu jako běžící příprava klonu. Totéž platí pro rozbalený
  kontext (`expansions`).
- **Rozsah se zapíše jako odkrytý až po načtení obsahu.** Zapsat ho hned by sundalo
  rozbalovací řádek i se spinnerem a zůstalo by po něm prázdno.
- **Kód kolem nálezu mimo diff se dotáhne sám** (`revealFindingsOutsideTheDiff`), hned po
  načtení diffu i po doběhnutí běhu. Je to **změna proti #47**: nález, jehož kód není
  vidět, se nedá posoudit. Smazaný soubor a binárka se přeskočí — nový obsah nemají.
- **Rozsahy vyžádané během načítání se schovají do `pending`** a použijí, až obsah dorazí.
  Dva nálezy v jednom souboru by jinak dotáhly kontext jen k prvnímu.
- **Sbalení kontextu si nechá načtený obsah.** Druhé rozbalení by jinak chodilo po síti
  pro něco, co už jednou dorazilo.

Rozsah komentáře (#110) drží `AppStore` ve dvou věcech — `commentDrag` (probíhající tažení)
a `rangeTargets` (per PR, cíl pro ⇧ klik):

- **Během tažení se drží složený rozsah, ne dvojice konců.** Složit ho umí jen `Policy` nad
  diffem, takže by se to jinak počítalo dvakrát — při zvýrazňování i při vzniku komentáře — a ty
  dva výsledky by se mohly rozejít. Takhle je vidět **přesně** to, co z tažení vznikne.
- **Když pod myší řádek není, rozsah se drží.** Prázdná protistrana ve split pohledu, mezera mezi
  soubory, hlavička hunku — nic z toho není zrušení výběru. Dosazený začátek (první podoba) rozsah
  srazil na jeden řádek pokaždé, když myš přejela prázdnou buňku, a po přejetí na další řádek se
  zase rozevřel; nahlášené při zkoušení. Dokud ale rozsah žádný není, platí samotný začátek, ať
  z tažení vznikne aspoň jednořádkový komentář.
- **Tažení bez načteného diffu nezaloží nic** — bez něj se pořadí konců nemá o co opřít.
- **Drží se `id` komentáře, ne kotva** (u ⇧ kliku). Druhý konec se z komentáře dopočítá a po
  roztažení zůstane platný; uložená kotva by se s ním rozešla.
- **⇧ klik bez cíle založí obyčejný komentář** — kliknutí, po kterém se nestane nic, vypadá jako
  rozbitá aplikace. Totéž když se cíl mezitím vyjmul nebo je v jiném souboru.
- **Roztahuje se od kotvy, ne od konce**, viz pravidla `Policy` — a identita komentáře se
  roztažením **nemění**: kotva je `let`, takže se komentář nahradí novým se **stejným `id`**,
  jinak by editor přišel o rozepsaný text a bublina by přeskočila jako nová.
- **Cíl i rozdělané tažení se uklízí s PR mimo seznam**, draft ne: rozsah v komentáři zůstane, jen
  se ⇧ klikem nedá roztáhnout něco, na co se člověk přestal dívat.

Pohled na diff (#98) drží `AppStore` v `diffLayoutOverride`:

- **Odchylka žije ve storu, ne ve view.** `PullRequestDetailView` si SwiftUI mezi PR ponechá
  (stejná pozice ve stromu), takže `@State` by přepnutí zahodilo přestavění stromu — tatáž
  past jako u sbalených souborů.
- **Drží se globálně, ne per PR.** Pohled je způsob čtení, takže přepnutím na jiný pull
  request nemá důvod se vracet.
- **Na disk se nezapisuje.** Nastavení říká „takhle to chci mít“, přepínač v liště „teď se na
  to podívám jinak“ — po restartu tedy platí zase nastavení. Kdyby přepínač zapisoval do
  `config.json`, měnila by se nastavená hodnota sama tím, že si člověk u jednoho souboru
  otočí pohled.
- **Odchylka se zapíše i tehdy, když se rovná nastavené hodnotě.** Totéž pravidlo jako
  u `Configuration.setRepository`, kde se maže podle prázdnosti a ne podle shody s globální
  hodnotou: kdo si pohled otočil sám, má ho podržet i po změně v nastavení. Bez odchylky se
  změna v nastavení projeví **bez restartu**, protože se čte při každém vykreslení.

Sbalení celých souborů (`foldedFiles`) je **jiná věc než rozbalení kontextu**, i když se
česky obojímu říká „sbalit“ — proto `DiffFoldingActions` vedle `DiffExpansionActions`:

- **Sbalené je to, co je v množině**, ne naopak. U PR o padesáti souborech je rozbaleno
  výchozí stav a sbalení je gesto, takže se pamatuje to druhé — prázdná množina znamená
  „nikdo nic nesbalil“ a nemusí se plnit při načtení diffu.
- **Stav drží store, ne view.** `PullRequestDetailView` si SwiftUI mezi PR ponechá (stejná
  pozice ve stromu), takže by sbalení přeteklo z jednoho pull requestu na druhý — stejná
  past jako u příznaku „připravuji“.
- **Skok sbalený soubor rozbalí, a to *před* nastavením cíle.** Sbalený soubor nemá řádky,
  takže `scrollTo` by mířilo na id, které v líném seznamu není. Platí pro skok ze stromu
  i z tabulky nálezů.
- **Hlavička zůstává vždycky**, včetně `+N −M` a odznaku změny — jinak by sbalený soubor
  zmizel a nešel otevřít zpátky.
- **Odznak s počtem nálezů je u souboru vždycky**, ne jen u sbaleného. U sbaleného je to
  nutnost (zavřený soubor s nevyřízeným nálezem se dá zapomenout), u rozbaleného zkratka:
  projedu hlavičky a vím, kde nálezy jsou, aniž bych scrolloval obsahem.
- **Tlačítko na komentář nesmí být vyšší než řádek diffu.** Řádek je vysoký ~15 pt (změřeno
  z renderu), takže pevná `height: 18` z něj vyčnívala **do toho následujícího** — jak na
  tlačítko myš zamířila, hover přešel na další řádek a ikonka zmizela. Komentovat pak nešlo
  vůbec a vypadalo to jako záhada v hoveru; nahlášené při zkoušení #98, ale je to od #66.
  Výška se proto bere z řádku (`maxHeight: .infinity` uvnitř `overlay`, kterému se navrhuje
  velikost řádku — ohraničené, na rozdíl od pružné výšky v líném seznamu), ne z konstanty:
  ta by byla druhé místo, které se s výškou řádku rozejde.
- **Cíl tlačítka je celý sloupec s číslem** (`DiffLineView.numberColumn`), i když je vidět
  pilulka o 18 pt. Na řádku vysokém 15 pt je to rozdíl mezi „jde to“ a „myš to mine“; číslo
  řádku samo o sobě na kliknutí nereaguje, takže se tím nic nepřebíjí.
- **Rozsah se vybírá tažením přes řádky** (#110), a v líném seznamu to jde jedině přes rámečky:
  gesto se doručuje **jen tomu řádku, ve kterém začalo**, takže řádek pod myší se musí dohledat
  ze souřadnic. Drží je `DiffRowFrames`, a to **mimo observable stav** — zápis při každém
  přeměření by jinak překresloval celý diff, tedy tatáž třída problému, která u #98 aplikaci
  zasekla. Souřadnice jsou v prostoru **obsahu** (`DiffView.contentSpace`), ne okna: scrollování
  s rámečky nehýbe, takže se přeměřování nespouští.
- **Táhne se přes celý řádek, ne jen přes sloupec s čísly.** GitHub má gesto v číslech, ale tady
  je nad diffem vypnuté vybírání textu, takže tažení přes kód nic nepřebíjí — a úzký sloupec se
  trefuje hůř. `minimumDistance` je nenulová, aby samotný klik zůstal kliknutím (jednořádkový
  komentář je od tlačítka).
- **Hledání řádku pod myší je omezené na sloupec, ve kterém tažení začalo.** Bez toho skočilo do
  druhého sloupce, kdykoli myš zajela vedle nebo protistrana chyběla — nahlášené při zkoušení.
  V pohledu pod sebou se neomezuje (`side == nil`): sloupec je jediný a rozsah přes odebrané
  i přidané řádky je legitimní, GitHub ho bere.
- **Přeměřené rámečky se zahazují při každé změně, která přerovná řádky** — přepnutí pohledu, jiný
  diff. Zůstat by znamenalo, že se pletou rámečky ze dvou rozvržení: unified řádek jde přes celou
  šířku, buňka dvojice po půlce, takže bod padne do obou a vyhraje ten, na který hledání narazí
  první. A protože párování řádky slévá, netrefí se to ani o pár míst vedle — projevilo se to jako
  „vybere se i další 2–3 pod kurzorem“.
- **Pokrytí rozsahu se klíčuje `(řádek, strana)`, ne řádkem** (`Policy.rangeCells`). Kontextový
  řádek stojí ve split pohledu na obou stranách jako **tatáž hodnota**, takže po řádcích se
  zvýrazňovaly oba sloupce; rozsah tažený vpravo do levého sloupce nepatří. Rozsah přes obě strany
  svítí v obou — tam to je pravda.
- **Zvýraznění při tažení kreslí složený rozsah ze storu**, ne dvojici konců: složit ho umí jen
  `Policy` nad diffem, takže se tím zaručí, že je vidět **přesně** to, co z tažení vznikne. Když
  se rozsah složit nedá (konec v jiném souboru, mimo diff), drží se **poslední platný** — rozsah,
  který při vyjetí z diffu poskočí zpátky na jeden řádek, by se nedal dotáhnout.
- **Tažený rozsah svítí výrazněji než hotový komentář** (0,16 proti 0,12): u hotového je vidět
  i bublina, kdežto při tažení je pruh jediná zpětná vazba. Ne o mnoho výrazněji — při 0,3 pruh
  přebil zelenou a červenou u změněných řádků, tedy to hlavní, co má diff říkat (vyladěné na
  offscreen renderu).
- **Při tažení je tlačítko vidět jen na konci rozsahu.** Hover během tažení zůstává na řádku, kde
  se stisklo, takže bez toho svítila ikona na dvou místech a poskakovala. A **sedí na čísle řádku**
  (zarovnaná doprava přes sloupec s čísly, jako na GitHubu) — u levé hrany působila odděleně od
  diffu; obojí nahlášené při zkoušení.
- **⇧ klik na tlačítko roztáhne už napsaný komentář** a zůstává vedle tažení: tažení rozsah
  **zakládá**, ⇧ klik ho **opravuje** („ono to patří k celému bloku“), což tažením nejde.
  Modifikátor se čte z `NSEvent.modifierFlags`, protože SwiftUI ho akci `Button`u nepředá; co ⇧
  znamená, rozhoduje store, takže ve view je jen ta jedna otázka.
- **Na myš musí reagovat celý obdélník řádku** (`contentShape(.rect)` nad `onHover`). Bez toho
  drží hover jen nad číslicemi a nad glyfy kódu: kontextový řádek má **průhledné pozadí**
  a `Text` uvnitř pružného rámce si hit-test nese jen na svou velikost, takže odsazení kódu
  a mezera za koncem řádku nereagují. Projevilo se to jako „ikonka se ukáže jen nad čísly“ —
  myš vyjela z citlivé plochy dřív, než k tlačítku došla. `contentShape` na rozvržení nesahá,
  takže s pružnou výškou a zaseknutím výš nemá nic společného.
- **`Divider()` v `overlay` se kreslí svisle.** Orientaci si bere z okolní osy a v overlay
  žádná není. Hlavička souboru tak od #18 kreslila svislou čárku uprostřed místo čáry pod
  sebou; všimlo se toho až po sbalení všech souborů, kdy se ty čárky poskládaly do jedné
  čáry. Kde na orientaci záleží, patří `Rectangle().fill(.separator).frame(height: 1)`.
- **`Sbalit vše` a `Rozbalit vše` je jedno tlačítko**, které se přepíná podle toho, jestli
  je všechno sbalené. Dvě tlačítka by znamenala, že je jedno z nich pořád k ničemu.
  `unfoldAll` sahá **jen na svoje PR**: sbalení v jiném je cizí stav.

Průběh review drží `AppStore` taky (`reviewTimelines`, per PR):

- **Události tečou proudem** (`AsyncStream`), ne přímým voláním. Hlásí se ze session mimo
  hlavní vlákno a **pořadí je to hlavní, co osa říká** — task na každou událost by o něm
  nechal rozhodovat plánovač.
- **Konec běhu jde stejným proudem.** Zápis mimo něj dorazil dřív než to, co mu
  předcházelo, a někdy se ztratil úplně; je na to test.
- **Osa se drží i po doběhnutí** — právě tehdy se k ní člověk vrací. Nový běh ji vynuluje
  a PR, které zmizí ze seznamu, ji ztratí (běžící review si ji podrží).

Taby PR (#72) drží `AppStore` v `detailTabs` (per PR) a platí u nich:

- **Volba tabu je ve store, ne ve view.** `PullRequestDetailView` si SwiftUI mezi pull requesty
  ponechá (stejná pozice ve stromu), takže `@State` by přetekl z jednoho PR na druhý — tatáž
  past jako u sbalených souborů a příznaku „připravuji“.
- **Drží se odchylka od výchozího stavu**, ne volba u každého PR. Výchozí je `Přehled`
  (`PullRequestTab.standard`, **změna proti zadání #72** — popis a diskuze se čte dřív než kód
  a stejně to má GitHub), takže se `filesChanged` z mapy maže a úklid podle seznamu PR ji
  nenechá růst.
- **Spodní panel je v obou tabech.** Nálezy bez místa v kódu, průběh i moje rozdělané review
  se vážou k celému PR — schovat je za přepnutí tabu by znamenalo, že se rozepsané review
  „ztratí“ přepnutím na `Přehled`.
- **Skok na nález tab přepne**, a `DiffView` na cíl reaguje `task(id:)`, ne `onChange`: při
  přepnutí z `Přehledu` diff **vzniká**, takže cíl už v něm je a žádná změna nepřijde.
- **Cíl skoku se kotví k vršku s odstupem** (`DiffView.jumpAnchor`, 90 pt = ukotvená hlavička
  plus tři řádky), ne doprostřed. `scrollTo` umí jen podíl výšky, takže se počítá z měřené
  výšky diffu (`onGeometryChange`, jen měření — `GeometryReader` by sám zabral místo).

Skládání rozdělaného review (#66) drží `AppStore` v `drafts` (per PR) a platí u něj:

- **Draft potřebuje `headSha`, takže se dotahuje detail PR** (`detailStates`, cache podle
  `updatedAt`, načítá se při výběru řádku jako diff a konverzace). Vyhledávání SHA nedá
  (#4) a pollingem se detail tahat nesmí (N+1 podprocesů na tik). Bez známé hlavy se draft
  **nezakládá** a UI to říká — mlčky zakázané tlačítko vypadá jako rozbitá aplikace.
  „Nevím“ přitom **není** „zastaralé“: banner o zablokovaném odeslání nad načítajícím se
  detailem by lhal.
- **Rozepsanému draftu se `headSha` nepřepisuje.** Nese commit, proti kterému se psal, i po
  novém pushi — odtud banner a zablokované odeslání. Přenesení na nový commit je #69.
- **Prázdný draft se maže**, včetně toho, ze kterého se vyjme poslední komentář. „Draft
  existuje“ musí znamenat „je co poslat“, protože na tom stojí indikátor v řádku.
- **Prázdný komentář se zahazuje**, jakmile se text uloží prázdný. Vzniká běžně (kliknu na
  komentovat a rozmyslím si to) a GitHub takový payload odmítne — a odmítne s ním celé
  review, protože odeslání je atomické. `Policy.sendBlock` to hlídá i tak.

  Uklidit ho musí **editor** (`DraftTextEditor.commitsEmpty`), a proto doručuje prázdno
  i tehdy, když se text **nezměnil**: komentář vzniká prázdný, takže „nic se nezměnilo“ je
  přesně jeho stav a bez toho by zůstal ležet v draftu i na disku. Nešlo to uklidit
  z bubliny (`onDisappear` nad komentářem): pořadí proti doručení textu z editoru není
  zaručené, takže by se dopsaný komentář smazal. Po pádu aplikace ta chvíle nikdy nepřijde,
  na to je druhá pojistka `pruneBlankComments()` při načtení z disku.

  A texty o tom musí říkat **„zahodí se“, ne „neuloží se“** — na disku prázdný komentář
  chvíli je. Je to na dvou místech (bublina, seznam v panelu) a musí říkat totéž.
- **Rozsah řádků (#110) je součást kotvy, ne druhý druh komentáře.** `DraftAnchor.start` je
  `nil` u jednořádkového; rozsah s oběma konci na jednom řádku se **srazí** na `nil`, ať
  neexistují dvě podoby téhož (GitHub `start_line == line` přijme, změřeno). Pravidla jsou
  změřená v sandboxu (`docs/github-review-api.md`, bod 8) a dvě z nich se nedají uhádnout:
  **rozsah smí přeskočit mezeru mezi hunky** (stačí, že každý konec sám leží v hunku)
  a **pořadí GitHub hlídá jen na téže straně** (`start_line > line` se stejným `side` je
  `422 Start position could not be resolved`, napříč stranami neřeší nic). Konce se proto řadí
  podle **pořadí v kresleném diffu**, ne podle čísel — na jedné straně z toho vyjde vzestupné
  číslo, napříč stranami legitimní `6 (starý) → 5 (nový)`.
- **Roztahuje se od kotvy, ne od konce.** ⇧ klik posílá do `Policy.commentRange` **začátek**
  existujícího rozsahu (u jednořádkového jeho řádek), takže druhý ⇧ klik konec posune, ale
  začátek nechá. Roztahování od konce zahazovalo první konec (z 25–26 vyšlo po kliku na 27
  jen 26–27) — chytil to test.
- **Kontextový řádek se dá komentovat na obě strany** (`LineAnchors`), změněný jen na svou:
  odebraný v nové verzi souboru neexistuje a přidaný ve staré. Změřeno u #98 na živém API, protože
  dokumentace GitHubu u nezměněných řádků `RIGHT` jen **doporučuje** — a hádat se to nesmí, `422`
  zahodí celé review. Stojí na tom, že ve split pohledu vznikne komentář v té polovině, do které
  se kliklo. **Kanonická zůstává pravá** (`preferred`): je to výchozí strana GitHubu, ukazuje na
  novou verzi souboru a platí tam, kde se strana nevybírá — v pohledu pod sebou a u převzatého
  nálezu, který stranu nemá.
- **Kam převzatý nález patří, rozhoduje `Policy.draftTarget`, ne view.** Je to pravidlo
  GitHubu (řádkový komentář bere jen řádek uvnitř hunku), takže patří k rozhodovací logice.
  Cesta se přitom překládá na dnešní (`displayPath`): nález umí přijít pod starou cestou
  přejmenovaného souboru, kdežto komentář i permalink míří na hlavu PR.
- **Uložení se čte až v tasku, ne při zavolání.** Dvě rychlé úpravy tak zapíšou tentýž
  konečný stav a nezáleží na pořadí, ve kterém se tasky provedou; zachycená hodnota by
  dovolila zapsat starší podobu jako poslední.
- **Selhání zápisu je vidět** (`draftFailure`) a nečitelné soubory se počítají
  (`unreadableDraftFiles`) — o důvod víc než u nálezů, protože ručně psaný text se nedá
  dostat zpátky žádným dalším během.
- **Draft se při úklidu nezahazuje**, na rozdíl od diffu, konverzace i detailu. Je to ručně
  psaná práce, mapa je jeden malý záznam na PR a PR se do seznamu umí vrátit.
- **Odesílání tady pořád není.** Store si od #68 drží **jen cestu ke `gh`** a `submission(for:)`
  z ní složí `ReviewSubmission`; publisher vzniká až uvnitř něj. `AppStore` sám odeslat neumí
  a grep z tvrdé podmínky č. 1 ho nevypíše.
- **Sheet se nad zastaralým draftem neotevře dvakrát.** Zakázané tlačítko je první pojistka,
  `submission(for:)` vracející `nil` druhá — spoléhat na to, že si to pohlídá view, je o jedno
  místo k zapomenutí víc.
- **Konverzace se po odeslání obnovuje ručně.** `updatedAt` se odesláním review měnit nemusí,
  takže cache podle něj by moje vlastní review v `Přehledu` neukázala až do přepnutí PR.
- **Návrh verdiktu se do potvrzení předává, ale nepředvyplňuje.** Je to totéž pravidlo jako
  u výběru v panelu: odhad aplikace se nemá dát splést s mým rozhodnutím.
- **`ReviewSubmission` drží `ContentView`, ne detail PR ani store.** Ve storu být nesmí: objekt
  má zaniknout se zavřením sheetu, protože v něm vzniká cesta ven. V detailu taky ne, i když
  se tam zakládá — detail se kreslí jen tak dlouho, dokud je vybraný PR v seznamu z pollingu,
  a **odeslané review ruší `review-requested`**, takže právě ten PR na příštím tiku vypadne.
  Sheet by tím zmizel uprostřed odesílání, nebo zrovna nad hláškou „odpovědi nerozumím,
  zkontroluj to na GitHubu“, která je jediným místem, kde se to člověk dozví. **Modalita proti
  tomu nechrání** — zastaví uživatele, ne tik pollingu. Je to opačný směr než obvyklá past
  s přetečením stavu mezi PR: tenhle stav nepřetéká, ale předčasně zaniká.

Odpovídání do vláken (#73) drží `AppStore` ve dvou mapách klíčovaných `ThreadKey`
(`threadReplies` a `threadStates`) a platí u něj:

- **Store odesílání spouští, ale cestu ven nedrží.** `sendThreadReply` a `setThreadResolved` si
  složí `ThreadSubmission` (jen z cesty ke `gh`, gateway a brány) a publisher vzniká až uvnitř
  něj — takže `grep ReviewPublishing App/` `AppStore.swift` dál nevypíše. Rozdíl proti review je
  jen v tom, kdo akci spouští: tam sheet, tady tlačítko v bublině.
- **Klíč nese PR, i když `id` vlákna je unikátní samo.** Úklid odpovídá na otázku „zmizel PR ze
  seznamu?“, a ta se z `id` nepozná — tatáž lekce jako u `toggledThreads` z #64.
- **Rozepsaný text se zahazuje s PR mimo seznam**, jako konverzace, ke které patří. Je to opačné
  rozhodnutí než u draftu review, který se drží: ten je vlastní práce v řádu odstavců a má na
  disku své místo, kdežto odpověď je jedna věta bez konverzace nezobrazitelná.
- **Dvojklik pošle jednu odpověď.** Kontrola `isBusy` leží **před** prvním `await`, takže mezi
  nimi není mezera, do které by se závod vešel. Je na to test se souběžnými voláními — sekvenční
  by prošel i bez té ochrany.
- **Selhání drží stav, dokud se nezkusí znovu.** Chyba, která zmizí sama, je chyba, kterou nikdo
  nepřečte; text u toho zůstává.
- **Prázdný text se z mapy maže**, ať v ní nezůstane záznam po každém vlákně, do kterého někdo
  klikl a rozmyslel si to. Tentýž vzor jako prázdný draft.

Signály pro stavový řádek (#31) do `AppStore` patří taky, protože jen on ví, jak dopadla
skutečná volání:

- **Stav GitHubu se z pollingu odvozuje, ne vede zvlášť.** `PollState` už drží, co je
  potřeba (`upToDate` + `lastSuccess`, `failing(since:reason:)`, `rateLimited`), takže
  vlastní kopie by byla druhé místo, které se s prvním rozejde.
- **Rate limit je selhané volání.** Zelená znamená „funguje mi to“ a při rate limitu to
  nefunguje; že za to GitHub nemůže, řekne věta v nápovědě.
- **Ostatní volání gateway do puntíku netečou** — detail, diff ani konverzace neběží
  pravidelně a `notFound` u nich není o dostupnosti, nýbrž o tom, že na PR nevidíme.
- **Claude jede na výsledcích session, a `timedOut` nezapisuje nic.** Session jsme po
  patnácti minutách zabili sami, takže z toho nejde vyvodit ani „funguje“, ani „nefunguje“ —
  a dlouhé review je běžná věc. `failed` signál je, i když příčina může být u nás (třeba
  neexistující skill); nápověda proto říká, co přišlo na stderr.
- **Překlad nálezů se nepočítá.** Smí se nepovést tiše (nálezy zůstanou v originále), takže
  by z něj vznikal červený puntík nad něčím, co za chybu ani nepovažujeme.
- **`HealthMonitor` je nepovinná závislost**, jako `checkout` nebo `reviews`. `keepFresh()`
  volají i testy a monitor s živým klientem by z nich udělal testy chodící na síť; bez
  monitoru řádek prostě žádné puntíky nemá.

Věci, na které se u okna naráží:

- **Stav checkoutu je jeden a klíčovaný repem** (`CheckoutState`). `ReviewState` pro řádek
  i `busy` pro eviction se z něj **odvozují** — dvě mapy s různými klíči si dokázaly
  odporovat: jedno PR hlásilo selhání nad klonem, který mezitím pro druhé PR téhož repa
  v pořádku vznikl. Překlad na `ReviewState` je čistá funkce v `Policy`.
- **`ready` se v řádku ukazuje jako `notStarted`.** `ReviewState` popisuje **review**, a to
  se checkoutem nespustilo; „hotová kopie“ v něm případ nemá a vymýšlet ho by znamenalo
  lhát odznakem. Že je kopie připravená, říká detail.
- **Při výběru řádku se stav srovnává podle disku**, ne jen doplňuje. Klon mohla mezitím
  sebrat eviction, takže zapsaná cesta se musí ověřit znovu — jinak detail hlásí
  „připraveno“ na složku, která neexistuje.

- **Okno má `.windowResizability(.contentMinSize)` a vlastní podlahu na `RootView`.** Výchozí
  `.automatic` u `WindowGroup` odvozuje minimum okna z toho, co si obsah **přeje** — a `List`
  v bočním panelu si přeje celou výšku svých řádků, takže při dvanácti PR vyšlo minimum vyšší
  než obrazovka a spodní hranou okna nešlo hýbat vůbec. Změřeno: po skrytí bočního panelu se
  okno zmenšit dalo, s panelem ne. `.contentMinSize` bere **minimum** obsahu a strop nechává
  otevřený, takže podlaha musí být vlastní (`700 × 400`) — jinak se okno dá stáhnout do
  nesmyslu.
- **Banner jde přes `safeAreaInset`, ne do `VStack` nad seznamem.** S `VStack`em přestane
  být `List` tím, co sidebar odsazuje od horní lišty, a řádky se schovají pod ni.
- **Hlášky pod seznamem jsou naopak `VStack` na spodku okna** (`AppNoticesView`, od #31 uvnitř
  `StatusBarView`), a to **mimo
  `NavigationSplitView`**. Jako `safeAreaInset` uvnitř bočního panelu dělaly dvě věci naráz:
  obsah okna vycházel o výšku toho pruhu **vyšší než okno** a spodní hrana ho odřízla v obou
  sloupcích (změřeno přes accessibility: okno 874 pt, obsah 904, po skrytí bočního panelu
  rozdíl zmizel) — a tatáž mašinerie (`invalidateSafeAreaInsets` uvnitř `updateConstraints`
  split view) stojí v crash reportu z 2026-08-03. `List` si totiž vezme celou dostupnou výšku
  a pruh pod ním ji pak překročí. Přes celé okno je to zároveň směr, kterým měl stavový řádek
  jít (#31).
- **Panel má strop, ne pevnou výšku** (`maxHeight: clampedHeight` + `layoutPriority(1)`).
  `frame(height:)` je nesmlouvavá: v nízkém okně panel nepustí místo, přeteče — a co se
  nevejde, odřízne spodní hrana okna.
- **Čísla PR se píšou `Text(verbatim:)`.** `Text("#\(number)")` interpoluje přes locale
  a udělá z PR #21663 „#21 663“ — číslo PR není množství.
- **Obsah zajíždí pod poloprůhlednou lištu a je to tak správně.** Zkoušelo se to zrušit
  (`toolbarBackgroundVisibility`, pak vypnutí `fullSizeContentView` přes `NSWindow`) a
  **zahodilo** — Mail i Finder se chovají stejně, takže vlastní chování by bylo cizí,
  a vypnutí `fullSizeContentView` navíc odsune toolbar do vlastního pruhu.
- **`busy` se eviction předává jako dotaz, ne jako snímek.** Úklid je dlouhá disková
  operace; příprava, která začne uprostřed ní, by jinak přišla o ochranu a `git` by
  klonoval do složky, kterou mu eviction pod rukama maže.
- **View si o checkoutu nedrží vlastní `@State`.** `PullRequestDetailView` si SwiftUI mezi
  PR ponechá (stejná pozice ve stromu), takže vlastní příznak „připravuji“ přetekl z jednoho
  PR na druhé. Všechno jde ze store.
- **Jedna buňka líného seznamu je jeden řádek diffu, ne hunk.** Buňka vytvořená při jiné
  šířce okna se sama nepřeměří, takže se hunk po zvětšení okna překreslil jen zčásti
  a mezi hlavičkami zůstala prázdná místa. Ze stejného důvodu nad diffem není
  `.textSelection(.enabled)` — nad tisíci `Text`y v líném seznamu je to druhý zdroj
  nevykreslených řádků.
- **Stavy se čtou v těle `list`, ne až uvnitř řádku.** `List` staví řádky líně a mimo
  sledování závislostí rodiče, takže změna stavu nemusí seznam překreslit.
- **`ideal` u sloupce `Table` je nápověda, ne šířka.** Rozdělování dostupné šířky ho
  přebije: `Reviewer` s `ideal: 175` vyšel na ~139 pt a `code-review:code-review` se v něm
  ořezal. Co se **musí** vejít, se proto zadává jako `min` — podlaha je jediné, co
  rozdělování respektuje. Ověřeno na běžící aplikaci; AX to nepotvrdí, protože do SwiftUI
  `Table` nepustí (stejná past jako `entire contents`), takže se šířka odečítá ze snímku
  okna a odsazení buňky (~19 pt) se dopočítá z ořezaného textu.
- **Sloupec `Table` bez `max` roste do nekonečna** a AppKit dělí přebytek šířky mezi
  **všechny** takové sloupce. `.width(min:ideal:)` tedy poměr nedrží: v tabulce nálezů
  zabírala `Kategorie` s jedním slovem stejně jako text nálezu, který je to hlavní (#60).
  Strop je jediné, čím se dá říct „dál už neroste“ — sloupec, který má přebytek posbírat,
  se pozná tím, že `max` **nemá**. `min` na něm ale být musí, ať v úzkém okně mizí ostatní
  a ne on.
- **Nápovědu má každý sloupec tabulky, ne jen ty ořezané.** Ořezaný text bez nápovědy je
  ztracený údaj a `Table` nemá kam rozbalit druhý řádek — a protože se každým sloupcem dá
  táhnout až na jeho `min`, umí se ořezat každý. Zadání #60 jmenovalo `Nález` a `Místo`,
  ale `Kategorie` na svém minimu neuveze „bez kategorie“ s výstražnou ikonou. `Místo` se
  přitom ořezává **zepředu** (`.truncationMode(.head)`, stejně jako cesty ve `FileTreeView`
  a v hlavičkách `DiffView`), aby zůstalo jméno souboru a číslo řádku; společný prefix
  `App/Views/…` o nálezu neříká nic.
- **Nápověda u nálezu bez místa je věta, ne pomlčka.** Sloupec ukazuje `—`, ale tooltip
  s pomlčkou nevysvětluje nic. Skládá se ve `FindingRow`, ne ve view — je to text a ten se
  tam testuje bez UI.
- **Prázdný `PollStatusBanner` se nekreslí vůbec.** Trvalý pruh „vše OK“ ubírá místo
  seznamu a oko se ho naučí přehlížet. A **dokud se nic nenačetlo, nekreslí se taky** —
  není co označit za neaktuální a chybu vysvětluje prázdný stav pod ním.
- **Proč je seznam prázdný, rozhoduje `PollState.emptyReason`, ne view.** „Prázdno,
  protože nic není“ a „prázdno, protože se to nepovedlo načíst“ vypadají v okně stejně,
  ale znamenají opak; bez toho se u chybové hlášky svítilo zelené „Žádné PR k review“.

### `PollingService` (`App/Polling/`)

Drží seznam PR aktuální: v intervalu (default 60 s) se zeptá všech zdrojů, sloučí je přes
`PullRequestList` a publikuje `PollState`. `@MainActor` a `@Observable` — jeho stav je to,
co kreslí okno; síťová práce stejně probíhá v podprocesech `gh`.

`run()` je smyčka (obnovit → počkat → opakovat), `refresh()` jeden cyklus. Tlačítko
„obnovit teď“ volá `refresh()` — ruční obnovení není nic jiného než tik mimo pořadí.

Čtyři věci, které se u toho nemají rozbít:

- **Selhání jednoho zdroje zahodí celý tik.** Publikovat, co prošlo, znamená, že PR ze
  selhaného zdroje z okna zmizí — a zmizelý PR vypadá jako vyřízený, ne jako nenačtený.
- **Backoff je jen pro rate limit.** Ten si aplikace způsobila sama tím, že se ptá moc.
  Za výpadek sítě nemůže a delší čekání by jen oddálilo zotavení. Zdvojnásobení za každý
  rate limit v řadě, strop 15 minut, úspěch ho vynuluje.
- **`since` se při opakovaném selhání drží.** Jinak by v UI pořád stálo „neaktuální od
  teď“ a nešlo by poznat, jak dlouho výpadek trvá.
- **Zrušení není chyba GitHubu.** `CancellationError` stav nepřepisuje — jinak by při
  zavření okna probliklo hlášení, že něco spadlo.

Stav je `PollStatus` (`notStarted` / `upToDate` / `failing` / `rateLimited`) plus
`lastSuccess: Date?`. Otázka „je vůbec co ukázat“ se neřeší dalšími případy výčtu, ale
tím optionalem; `PollState.isStale` z toho dělá jedno pojmenované místo, takže view nic
neskládá.

**Polling netahá detail PR.** Seznam SHA nepotřebuje — potřebuje je až checkout a review,
takže `gh pr view` se volá tam. Zpřesňuje to rozhodnutí z #4.

### `App/Health/` — dostupnost služeb (#31)

Puntíky ve stavovém řádku: jak se vede GitHubu a Claude. Není to modul (viz Architektura) —
odpovídá to na otázku, jestli jde review vůbec spustit, ne na nic z domény review.

| Typ | Co je |
|---|---|
| `MonitoredService` | Která služba a kde má status page — plus **jména komponent**, na kterých nám záleží |
| `StatusPage` | Stav sledovaných komponent; `missing` nese jména, která stránka nezná |
| `StatusPageComponent` | Jedna komponenta: jméno a **surový** stav (`operational`, `major_outage`, …) |
| `StatusPageResult` | `fetched` / `unchanged` (`304`) — „platí, co jsi měl“ není „nic tam není“ |
| `StatusPageReading`, `StatusPageClient` | Protokol a aktor nad `HTTPGetting`, který drží `ETagy` |
| `StatusPageError` | `unreachable` / `badStatus` / `malformed`, s větou pro nápovědu |
| `HealthSignals`, `ServiceCall` | Tři signály na vstup `Policy`: poslední skutečné volání, stav komponent, dostupnost sítě |
| `ServiceHealth` | Puntík: `unknown` / `operational` / `incident` / `failing` / `offline` |
| `ServiceHealthReport` | Co `Policy` složí — stav, věta a časy pro nápovědu |
| `HealthMonitor` | `@MainActor @Observable`: hlídá síť, v intervalu čte status pages, skládá reporty |

Věci, které se u toho nemají rozbít:

- **Zelenou a červenou určuje skutečný provoz, ne sonda.** Polling se ptá `gh` každou minutu
  a review pouští `claude` — každé takové volání je pravdivý signál a nestojí nic navíc.
  `gh auth status` na timeru by stál spawn procesu a přístup do keychainu, a přitom je *méně*
  pravdivý: projde i tehdy, když skutečné volání selže na rate limitu nebo chybějícím scope.
- **Sledují se komponenty, ne celostránkový indikátor.** Incident v `Actions` nebo `Packages`
  se téhle aplikace netýká, takže `status.json` by svítil na něco, co nepoužíváme. Komponenta
  se pozná **jménem**, takže přejmenovaná musí být vidět (`StatusPage.missing`) — kontrola,
  která tiše nehlídá nic, vypadá stejně jako „všechno v pořádku“.
- **Cokoli jiného než `operational` je incident.** Seznam hodnot je jejich a může se rozšířit;
  spolknout neznámou hodnotu jako „v pořádku“ by schovalo výpadek, kdežto žlutý puntík
  s vypsanou hodnotou je nanejvýš falešný poplach, ze kterého je vidět, co přišlo.
- **Puntíků je pět, ne tři.** „Nezjištěno“ není „nefunguje“ a **„stroj je bez sítě“ není
  „služba je mimo“** — to je zrovna ta otázka, na kterou řádek existuje. Proto vlastní signál
  z `NWPathMonitoru`, ne dohad ze dvou selhání: vypnutá Wi-Fi je vidět hned.
- **Pořadí signálů drží `Policy.health(of:from:)`** a záleží na něm: bez sítě přebíjí
  všechno, selhané volání přebíjí incident (a incident se přidá do věty jako vysvětlení),
  incident přebíjí „zatím nic neproběhlo“, a **zelenou dá i samotná čerstvě přečtená čistá
  status page**. Šedá znamená „nevíme nic“ — a tady víme, co o sobě říká provozovatel; Claude
  by jinak zůstal šedý, dokud neproběhne první review, tedy většinu času. Že vlastní volání
  ještě neproběhlo, řekne **věta**, ne barva: status page nemluví o rate limitu ani
  o chybějícím scope. **Stará stránka po selhané kontrole se nepočítá** ani pro zelenou, ani
  pro věty o tom, že je u nich čisto.
- **Selhaná kontrola status page nic nezablokuje.** Když volání procházejí, je zelená
  pravdivější než šedá; mlčet o tom ale nejde, jinak se „o incidentech nevíme“ nepozná od
  „žádný incident není“. Věta jde do nápovědy, puntík zůstává.
- **Selhaná kontrola nechává poslední známý stav.** Deset minut starý stav je lepší odpověď
  než žádná a `checkedAt` říká, jak starý je.
- **`ETag` se ukládá teprve po úspěšném dekódování.** Kdyby se zapsal hned, odpověď, které
  nerozumíme, by nám příště přišla jako `304` — tedy „platí, co jsi měl“ na stránku, kterou
  jsme nikdy nepřečetli, a puntík by zůstal nezjištěný navždycky.
- **Zrušení není zjištění.** Ani v klientovi (`CancellationError` místo výpadku), ani
  v monitoru (`check` se nezapíše) — jinak by po zavření okna zůstala v nápovědě hláška
  o nedostupné status page.
- **Na pozadí se nekontroluje nic.** Aplikace, kterou nikdo nevidí, nemá komu svítit
  puntíkem. Skryté okno přitom interval **neposouvá**, takže po dlouhé nepřítomnosti se
  zkontroluje hned na prvním taktu.
- **Monitor se budí v krátkém taktu (30 s) a kontroluje, až když je co kontrolovat.** Uspat
  se rovnou na deset minut nejde: interval se mění za běhu (po selhaném volání se zkracuje
  na minutu) a okno se mezitím může vrátit do popředí — uspání, které začalo, když bylo
  všechno v pořádku, by se o obojí nedozvědělo. Alternativy jsou horší: continuation držená
  mezi voláními, nebo nestrukturovaný `Task`, který přežije zavření okna.
- **Skutečná volání si monitor nedrží** — bere si je závěrkou `lastCall`, kterou plní
  `AppStore`. Vlastní kopie stavu pollingu je druhé místo, které se s prvním může rozejít,
  a rozejít se v tomhle znamená svítit červeně nad funkčním GitHubem.
- **Interval není v konfiguraci.** Neovlivňuje chování aplikace, jen čerstvost puntíku —
  knoflík v nastavení by byl další řádek, který si nikdo nenastaví.

### `Policy` (`App/Policy/`)

Čisté funkce nad daty, žádné I/O. Testuje se bez mockování a bez binárek.

| Typ | Co dělá |
|---|---|
| `PullRequestList` | Sloučí výsledky zdrojů do jednoho seznamu: dedup podle `PRIdentifier`, řazení |
| `Policy.reviewState(for:)` | Překlad stavu pracovní kopie na stav v řádku PR |
| `Policy.isBlocking(_:categories:)` | Jediný odvozený boolean nad nálezem |
| `Policy.suggestedVerdict(for:)` | Návrh verdiktu nad `ReviewRecord`. `nil` = není z čeho soudit |
| `Policy.groups(of:)` | Shoda reviewerů na `file:line` → `FindingGroup` s odznakem `2×` |
| `Policy.chips(for:skills:running:)` | Stav reviewerů pro horní lištu — `ReviewerChip` |
| `Policy.projectLanguages(in:)` | Odhad jazyka projektu z výpisu verzovaných souborů |
| `Policy.automaticallyReviewable(...)` | Které PR má automat spustit — bez rozpočtu, ten je stavový |
| `Policy.sorted(_:)`, `Policy.sections(_:)` | Pořadí nálezů pro UI a jejich rozdělení po kategoriích |
| `Policy.matches(_:_:)` | Patří vlákno (nebo můj rozdělaný komentář) k tomuhle řádku diffu — **jedno místo** pro výběr i umístění |
| `Policy.inserting(_:intoThread:of:)`, `Policy.applying(_:to:)` | Zápis odeslané odpovědi a vyřešení do načtené konverzace; `nil` = vlákno tam není |
| `Policy.linesWithSeveralComments(in:)` | Na kolika řádcích draftu je víc komentářů — z každého budou samostatná vlákna, ne odpověď |
| `Policy.overview(of:renderedIn:)` | Co patří do tabu `Přehled`: review, komentáře pod PR a vlákna bez kotvy, chronologicky (`ConversationEntry`) |
| `Policy.commentableSide(of:in:)` | Ke které **kanonické** straně by šel komentář; `nil` = nedá se komentovat |
| `Policy.commentAnchors(of:in:)`, `Policy.commentAnchors(in:)` | Kotvy na **obě strany** (`LineAnchors`) — kontextový řádek unese vlevo i vpravo; mapa pro celý soubor jedním průchodem |
| `Policy.commentAnchor(of:in:)` | Kanonická kotva (`DraftAnchor`: číslo + strana + volitelný začátek rozsahu) — tudy chodí převzatý nález, který stranu nemá |
| `Policy.commentRange(from:to:in:)` | Dva konce → rozsah seřazený podle pořadí v diffu; `nil` = konec v diffu není |
| `Policy.rangeCells(of:in:)`, `Policy.commentRangeCells(of:in:)` | Buňky `(řádek, strana)`, které rozsah pokrývá — pro zvýraznění v diffu |
| `Policy.location(of:)`, `Policy.lines(of:)` | Kde komentář je, jako text (`Cart.php:26–31`) — jedno místo pro panel i potvrzení |
| `Policy.draftTarget(for:in:)` | Kam převzatý nález patří — `DraftTarget.line` nebo `.body` |
| `Policy.adoptedText(of:)`, `Policy.isAdopted(_:target:in:repo:)` | Text převzatého nálezu a odznak „už je v draftu“ |
| `Policy.permalink(to:line:in:at:)`, `Policy.bodyItem(text:link:)`, `Policy.appendingBodyItem(_:to:)` | Odkaz na kód a skládání položek těla review |
| `Policy.isStale(_:head:)` | Je draft psaný proti staršímu commitu? |
| `Policy.sendBlock(for:head:)` | **Proč** se draft nedá odeslat (`DraftSendBlock`); `nil` = dá se |
| `Policy.health(of:from:)` | Puntík služby ve stavovém řádku ze tří signálů — viz `App/Health/` |

- **Vstup jsou výsledky po zdrojích** (`[[PullRequestSummary]]`), ne jeden plochý seznam.
  Volající pak nic nespojuje a z typu je vidět, že jde o několik nezávislých dotazů.
- **Při kolizi vyhrávají novější data**, ne pořadí zdrojů. Zdroje se dotazují postupně,
  takže jeden z nich může nést stav, který mezitím zastaral.
- **Řadí se od naposledy změněného, při shodě podle identifikátoru.** Druhé kritérium není
  kosmetika: bez něj by pořadí mezi pollingy poskakovalo, protože slovník nemá pořadí.

Nad odhadem jazyka platí:

- **Marker přebíjí počty.** Soubor, který o projektu prohlašuje, čím je (`composer.json`,
  `go.mod`, `tsconfig.json`), váží víc než statistika přípon. **`package.json` mezi nimi
  není**, i když ho zadání #24 jmenovalo: má ho každý TypeScript projekt stejně jako
  JavaScriptový, takže by JavaScript přidával úplně všude.
- **„Převažující“ znamená prominentní, ne „vyskytl se“.** Jazyk se podle přípon zařadí, až
  když má aspoň desetinu rozpoznaných zdrojáků — jeden zatoulaný `.py` skript v PHP repu
  nemá pouštět Python reviewery, protože každá session stojí peníze.
- **Do jmenovatele jdou jen rozpoznané zdrojáky.** S Markdownem a YAMLem uvnitř by podíl
  neříkal nic o kódu: konfigurace a dokumentace jsou v každém repu.
- **Pořadí je podle počtu, při shodě podle jména.** Není to kosmetika — z pořadí jazyků
  vychází pořadí skillů, a množina pořadí nemá.

Nad nálezy platí navíc:

- **Aplikace si nevymýšlí škálu závažnosti.** Blokující příznak je `verdict == CONFIRMED`
  **a** `category` v blokující sadě (default `correctness`, `security`, `data-loss`) —
  a ta sada je jediný knoflík, kterým se dolaďuje, co je vážné. Právě proto se kvůli tomu
  nemusí přepisovat skilly.
- **Kategorie se porovnávají bez ohledu na velikost písmen.** Je to volný slug od reviewera;
  kdyby `Data-Loss` neblokovalo, prošel by PR s hlášenou ztrátou dat.
- **`suggestedVerdict` vrací `nil`, když není z čeho soudit** — a je to vlastní odpověď, ne
  opatrné `approve`. Schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou
  aplikace umí udělat. Z běhu se dá vyvodit „je čisto“, jen když **doběhl**, **zavolal
  `ReportFindings`** a **nic nezahodil**; zastaralý záznam nedá verdikt vůbec. Zahozený
  nález přitom bere `approve` **celému záznamu**, ne jen svému běhu — čistý výsledek jiného
  skillu o tom ztraceném nálezu nic neříká.
- **Nálezy se berou ze všech běhů, i ze spadlých a vytimeoutovaných.** Selhal *běh*, ne
  nález — ten dorazil jako celý `ReportFindings` call. Filtrovat je podle stavu běhu by
  znamenalo, že spadlý reviewer s nahlášenou ztrátou dat vedle jednoho čistého běhu vyjde
  jako `approve`. Blokovat tedy umí i běh, který sám o sobě `approve` nedá.
- **Chip `nejisté` je vlastní stav.** Běh, který doběhl, ale nezavolal `ReportFindings`
  nebo se mu ztratil nález, není ani čistý, ani spadlý — a ukázat u něj „čisté“ znamená
  schválený PR s neohlášenou chybou.
- **Běžící reviewer přebíjí starší výsledek**, protože to, co je na obrazovce, se právě
  přepisuje.
- **Ztracený nález se hlásí i u chipu, který nálezy má** (`warning`). Stav zůstane
  `findings`, aby byl vidět počet; bez varování vypadá neúplný výsledek jako úplný a
  `suggestedVerdict` pak mlčí bez vysvětlení.
- **Shoda se počítá po reviewerech, ne po nálezech.** Jeden reviewer, který na jednom řádku
  najde dvě různé věci, si nepřikyvuje.
- **Řadí se podle vlastnosti kategorie, ne nálezu.** Kdyby první kritérium bylo
  `isBlocking`, rozpadla by se kategorie s `CONFIRMED` i `PLAUSIBLE` na dvě sekce se
  stejným názvem. Poslední kritérium je `summary`, aby bylo pořadí úplné a nepřeskakovalo
  mezi překresleními.

Nad odesílatelností draftu (#68) platí:

- **Odpovídá jedna funkce, a vrací důvod, ne boolean.** Do #68 tady stálo `isSendable`, které
  vracelo ano/ne; vedle `sendBlock` by to byla cesta, jak se zeptat a důvod nedostat — a mlčky
  zakázané tlačítko vypadá jako rozbitá aplikace. Proto bylo zahozené, ne ponechané jako
  zkratka. Ke každému případu `DraftSendBlock` patří **věta pro okno** s tím, co s ním jde
  udělat; je na to test, protože prázdná věta by se v UI projevila jako to mlčení.
- **Pořadí důvodů kopíruje `GhReviewPublisher.submit`:** brána na odesílání, pak všechno, co je
  vidět na samotném draftu, a teprve pak to, co potřebuje hlavu PR (v publisheru totéž dělení
  — `PublishRequest.payload(for:)` běží před `preflight(_:)`). Kdyby se rozešlo, hlásilo by
  okno jiný důvod, než na kterém odeslání doopravdy skončí.

  Není to kosmetika: hlásí se ten důvod, **se kterým se dá něco udělat**. Draft bez verdiktu
  má říct „vyber verdikt“, ne „zjišťuji, na kterém commitu PR stojí“ — čekání tu vadu
  nespraví, a nad selhaným detailem by okno ukazovalo donekonečna na síť místo na chybějící
  verdikt. Chytil to Copilot na #112, kde `headUnknown` stálo před `noVerdict`.
- **`PublishScope` je součástí odpovědi**, i když je to jinak věc publisheru. Na nepovolené
  repo se nemá ani nabízet tlačítko, natož sahat na síť, a druhé místo, kde se ta brána
  vyhodnocuje, by se s prvním rozešlo. Od #107 se **předává parametrem** (`sendBlock(for:head:scope:)`),
  protože `Policy` je bez I/O a ke konfiguraci se nedostane — testy si tak řeknou o povolení
  místo toho, aby musely běžet nad sandboxovým identifikátorem.
- **„Nevím, jaká je hlava“ je vlastní důvod** (`headUnknown`), ne zastarání. Dokud se detail
  načítá, nedá se říct ani jedno — a banner o zastaralém draftu by nad ním lhal. Stejné
  rozlišení jako u `AppStore.isDraftStale`.
- **A rozlišuje se „načítá se“ od „nepovedlo se to“** (`headUnknown(detail:)`). První se dořeší
  samo, druhá ne, takže věta „hned to bude“ nad selhaným detailem slibuje něco, co nepřijde.
  Důvod doplňuje `AppStore.draftSendBlock`, protože `Policy` dostane jen `String?` a stav
  načítání z něj nepozná. Tentýž rozdíl dělá i `PullRequestDetailView.draftUnavailable` —
  chytilo se to vlastní revizí jako „kontrola, která jinde v repu je, a tady chybí“.

### `GitHubGateway` (`App/GitHub/`)

Jediná cesta aplikace k GitHubu, celá přes `gh`. Protokol `GitHubGateway` má šest metod
a **schválně žádnou, kterou by šlo něco odeslat** — read-only je vidět z typu.

| Typ | Co dělá |
|---|---|
| `GitHubGateway` | Protokol: `checkAuth()`, `searchPullRequests(query:)`, `fetchDetail(id:)`, `fetchDiff(id:)`, `fetchFile(id:path:)`, `fetchConversation(id:)` |
| `GhGateway` | Implementace nad `gh`; `checkAuth()` deleguje na `GhAuthCheck` z `Environment` |
| `GitHubError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `GhSearchQuery` | Rozdělení search dotazu na argumenty `gh` — čistá funkce |
| `ConversationQuery` | GraphQL dotaz na konverzaci a jeho argumenty — čisté funkce |
| `GhConversationResponse` | Tvar GraphQL odpovědi a mapování na `Conversation` |
| `GhSearchItem`, `GhPullRequestDetail` | Tvar JSONu z `gh` a převod na doménové modely |
| `PullRequestState(ghState:isDraft:)` | Mapování stavu — `gh` ho popisuje dvěma poli |

Čtyři věci, které se u toho nemají rozbít:

- **Vyhledávání neumí SHA.** `gh search prs` nabízí jen `number, repository, title, author,
  url, updatedAt, state, isDraft`; `headRefOid` a `baseRefOid` jsou až v `gh pr view`.
  Proto search vrací `PullRequestSummary` a plný `PullRequest` vzniká teprve z detailu.
  Dotahovat detail rovnou v gateway pro každý nalezený PR by z jednoho pollu udělalo N+1
  podprocesů — **kdy se detail dotáhne, rozhoduje polling** (#6), typicky jen u PR se
  změněným `updatedAt`.
- **Dotaz se posílá po argumentech a uvozovky se respektují** (`GhSearchQuery`).
  `gh search prs` bere každý argument jako jeden výraz a hodnotu s mezerou si sám
  uzávorkuje. Celý dotaz v jednom argumentu proto GitHub odmítne
  (`review-requested:"@me is:open"`), zatímco dělení naslepo **nespadne a tiše hledá něco
  jiného**: z `label:"help wanted"` se stane `label:help` plus fulltextové `wanted`.
  Ověřeno na živém `gh` — obě podoby vracejí jiné PR.
- **Chyby se klasifikují z exit kódu a textu.** `gh` má vlastní exit kód `4` pro chybějící
  přihlášení, zbytek (`HTTP 401`, `rate limit`, `error connecting to`,
  `Could not resolve to`) se pozná z výstupu. Je to křehké, ale nic lepšího `gh` nenabízí —
  proto je to čistá funkce (`GitHubError(failure:)`) testovaná tabulkou skutečných hlášek.
- **Diff se vrací jako syrový text.** Unified diff není tvar, který by `gh` definoval —
  na rozdíl od `--json` polí, kde si říkáme, co má přijít. Rozumí mu až `DiffParser`.
  Volá se `gh pr diff <n> --repo … --color never`; to `never` je pojistka proti defaultu
  `auto`, který by při zápisu na terminál poslal ANSI escape sekvence.
- **Obsah souboru se čte přes ref pull requestu**, ne přes `headSha`:
  `gh api repos/…/contents/<cesta>?ref=refs/pull/<n>/head` s hlavičkou
  `Accept: application/vnd.github.raw`. Ověřeno na živém API — ten ref má každý PR včetně
  forků, takže odpadá `gh pr view` jen kvůli SHA. Cesta se procentuje, jinak ji mezera
  v názvu rozbije.
- **Tvar `gh` JSONu se nesmí propsat do modelů.** `PullRequest` a `PullRequestSummary` se
  kódují na disk, takže jejich `Codable` popisuje uložený tvar. Dekódují se proto DTO
  a teprve ta se mapují — jinak by změna `gh` měnila formát dat v `ReviewStore`.

Detail navíc ověří, že `gh` vrátil PR s číslem, na které jsme se ptali. Identifikátor se
bere z dotazu (`gh pr view` repo nevrací) a tichý rozchod by nálezy naklíčoval cizímu PR.

Konverzace (#63) jde **jedním GraphQL dotazem** přes `gh api graphql`:

- **GraphQL, ne tři REST endpointy.** REST `isResolved` u vláken **nemá vůbec**, takže by
  otázka „co s vyřešenými vlákny“ neměla odpověď — a byly by to tři podprocesy místo jednoho.
  Ověřeno na živém API: celý dotaz stojí **1 bod z 5000/h**, ať má PR dvě vlákna nebo 38.
- **Čísla se posílají `-F`, dotaz `-f`.** `number` a `page` jsou v GraphQL `Int!` a přes
  `-f` by dorazily jako řetězec, na kterém dotaz spadne na typu.
- **Repo se posílá rozdělené** na `owner` a `repo` — GraphQL má dva argumenty a slepené
  `owner/repo` by hledalo repozitář s lomítkem v názvu.
- **Chybějící `repository` nebo `pullRequest` je chyba**, kdežto chybějící `nodes` uvnitř
  ne. Na PR jsme se ptali, takže prázdná odpověď by v okně vypadala jako „kolegové nic
  nenapsali“; PR bez jediného komentáře je naopak normální stav.
- **Komentář bez autora se zahodí, ale je to vidět.** Smazaný účet vrací `author: null`
  a komentář „od nikoho“ v konverzaci nic neříká — jenže rozdíl proti `totalCount` pak hlásí
  `ConversationPage.missing`, takže ztracený komentář není k nerozeznání od nenapsaného.
- **Jedna velikost stránky na všechny seznamy**, ať se komentáře uvnitř vláken neutnou dřív
  než vlákna sama.
- **Dotaz si od #73 bere i `viewerCanResolve` a `viewerCanUnresolve`.** Bez nich by okno nabízelo
  `Vyřešit` i tam, kde na to reviewer právo nemá — a tlačítko, které vždycky selže, je horší než
  žádné. Starší fixtures ta pole nemají, takže se chybějící hodnota bere jako **povolení**; viz
  pravidla nad vlákny v modelech.

### `ReviewPublisher` (`App/Publish/`)

**Jediná cesta, kterou z aplikace něco odejde na GitHub.** Vznikl v #67 a nahradil tvrdou
podmínku „nikdy nic neposílat“ pravidlem, které je vidět z kódu — viz tvrdé podmínky výš.

| Typ | Co dělá |
|---|---|
| `ReviewPublishing` | Protokol se **třemi** metodami: `submit(_:)`, `reply(to:body:)`, `setResolved(_:of:)` |
| `GhReviewPublisher` | Implementace nad `gh`; pre-flight přes `GitHubGateway` |
| `PublishScope` | Brána: smí se z tohohle repa odeslat? Skládá se z `Configuration`, výchozí stav **vypnuto** |
| `PublishError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `PublishRequest` | Payload a argumenty review — čisté funkce |
| `ThreadRequest` | GraphQL mutace pro vlákna a jejich argumenty — čisté funkce |
| `ThreadTarget`, `ThreadResolution` | Adresa vlákna (PR + `id`) a to, jak dopadlo přepnutí vyřešení |
| `ThreadActionState`, `ThreadKey` | Co se s vláknem právě děje a klíč, pod kterým to drží `AppStore` |
| `GhSubmittedReview`, `GhThreadReplyResponse`, `GhThreadResolutionResponse` | Tvary odpovědí — REST review a dvou GraphQL mutací |
| `ReviewSubmission` | Jedno odeslání review od kliknutí po odpověď — **volající `submit(_:)`** |
| `ThreadSubmission` | Jedna akce nad vláknem — **volající `reply` a `setResolved`** |

Věci, které se u toho nemají rozbít:

- **Brána je první kontrola v cestě**, ještě před sítí. Na nepovolené repo se nemá ani ptát
  na detail — a `scope` je v `init` **bez výchozí hodnoty**, takže se publisher bez brány
  nedá složit.
- **Pre-flight ověřuje `headSha` a stav PR, a při neshodě se nevolá nic.** GitHub proti
  odeslání proti zastaralému commitu nechrání (změřeno u #62), takže je to naše práce.
  Draft PR se odeslat **smí** — je to otevřený stav a na GitHubu běžné.

  **Hlava je volitelný parametr** (`preflight(_:expecting:)`), protože každá cesta ven se váže
  na něco jiného: review na commit, odpověď do vlákna na vlákno. Jedna funkce s `nil` místo dvou
  podobných je tady schválně — dvě by se rozešly v tom, co dělají se stavem PR.
- **Volání `gh` a dekódování odpovědi má každá cesta ven společné** (`call(_:)`, `decoded(_:from:)`).
  Kdyby si každá třídila chyby sama, lišily by se v tom, co znamená timeout nebo zrušení — a na
  tom stojí `mightHaveReachedGitHub`, tedy jestli okno nabídne odeslat znovu.
- **Payload jde dočasným souborem**, protože `ProcessRunning` neumí stdin — a přidávat mu
  metodu jen kvůli tomuhle by ji musely dopsat všechny fake implementace v testech, tedy
  stejná úvaha, kvůli které je streamování vlastní protokol. Soubor má práva `0600` (je v něm
  nezveřejněný text review) a maže se v `defer`, ať odeslání dopadne jakkoli.

  Dvě věci, na kterých u toho záleží: **práva se nastavují na prázdný soubor a obsah se píše
  teprve pak**, takže text review na disku nikdy neexistuje se širšími právy — a zápis proto
  **není `.atomic`**, protože ten píše vedle a přejmenováním by práva zahodil. A **selhání
  zápisu soubor uklidí samo**, protože `defer` u volajícího se registruje až po návratu.
- **Zrušení se propaguje jako `CancellationError`**, ne jako `toolUnavailable`. Jinak by okno
  ukázalo „gh se nepodařilo spustit“ nad odesláním, které si člověk sám zrušil — a je to
  totéž pravidlo, jaké drží `ReviewRunner`.
- **Odpověď se čte typovaně a vlastním DTO.** REST používá `user` a `submitted_at`, kdežto
  GraphQL v #63 `author` a `submittedAt`; sdílet DTO by znamenalo, že změna jednoho API mění
  druhé. `id` je v RESTu číslo, v GraphQL řetězec — `SubmittedReview` drží řetězec.
- **Nečitelná odpověď je vlastní chyba** (`malformedResponse`), ne ticho: review mohlo odejít
  a z hlášky musí být vidět, že se to má zkontrolovat na GitHubu.
- **Klasifikace zná i `Path could not be resolved`**, ne jen `Line …`. Narazilo se na to při
  ověřování #67 proti živému API a je to vlastní případ, protože rada „přesuň komentář na
  řádek uvnitř diffu“ je u chybějícího souboru nepravdivá.
- **Ke každé chybě patří, co s ní jde udělat** (`userDescription`). Chyba, ze které nevyplývá
  další krok, je jen zpráva o smůle.

Nad `ReviewSubmission` (#68) platí navíc:

- **Publisher vzniká uvnitř `send()` a zaniká s objektem.** Objekt sám vzniká kliknutím na
  `Odeslat review…` a zaniká zavřením sheetu, takže cesta ven není otevřená po celou dobu
  běhu aplikace. Tím se drží tvrdá podmínka č. 1 bod 3.
- **Draft je snímek, ne odkaz do storu.** Co je v potvrzení vidět, to se odešle. Sheet je
  modální, takže se draft pod ním změnit nemá čím — snímek je pojistka proti tomu, aby na
  tom to tvrzení viselo.
- **Draft se maže až po potvrzené odpovědi.** Selhání ho nechává netknutý (a sheet to říká
  **větou**, ne nápovědou, jinak se rozepsaná práce začne psát znovu), takže se dá zkusit
  znovu bez psaní nanovo. Úklid je závislost storu, ne tohohle objektu: dostane ho jako
  closure, protože smazat draft a načíst konverzaci umí `AppStore`.
- **Po úspěchu už se odeslat nedá.** Druhé odeslání by nebylo opravou toho prvního, ale
  **druhým review**, které na PR leží jako samostatný záznam.
- **A po selhání jen tehdy, když je jisté, že nic neodešlo** (`PublishError.mightHaveReachedGitHub`).
  `malformedResponse` vzniká při **nulovém** exit kódu, tedy poté, co POST prošel; `timedOut`
  znamená, že jsme `gh` po třiceti vteřinách zabili sami. Nabídnout nad tím `Odeslat` je
  pozvánka poslat approve podruhé — takže je tlačítko zakázané a věta pod chybou říká, ať se
  PR zkontroluje, místo obvyklého „nic se nemazalo, zkus to znovu“. Rozhoduje se
  **konzervativně**: co se nedá s jistotou zařadit mezi odmítnutí, počítá se jako „možná
  odešlo“, protože cena omylu je nesymetrická. Zkusit to znovu jde pořád — jen se sheet musí
  vědomě otevřít znovu, draft zůstal. Chytila to revize diffu u #68.
- **Zrušení se nevydává za „nic se nestalo“** (`PublishError.interrupted`). Zrušit jde jedině
  *během* volání, takže POST mohl doběhnout — `.ready` by bylo totéž tvrzení jako výš, jen
  schovanější. Od #73 to má i druhého uživatele: `ThreadSubmission` převádí `CancellationError`
  na tentýž případ, aby se zrušené odeslání odpovědi nedalo splést s neodeslaným.
- **Sheet se po úspěchu zavírá sám, ale ne u odpovědi, jejímuž stavu nerozumíme.** Že review
  odešlo, je za sheetem vidět líp než v něm (draft zmizel z panelu i z řádku, v `Přehledu`
  přibylo moje review), takže potvrzovací okno navíc je jen kliknutí za nic. Neznámý stav je
  výjimka: „zkontroluj to na GitHubu“ se jinde v okně nedozví, protože review tam vypadá jako
  každé jiné. Rozhoduje `closesItself`, tedy model, ne view.
- **Rozchod s návrhem z nálezů se hlásí, ale nezakazuje.** Nálezy jsou návrh a přebít se smějí;
  schválit PR, u kterého reviewer hlásí blokující nález, je ale nejdražší záměna, jakou tohle
  okno umí. `jen komentář` rozchod **není** — je to vědomé „nerozhoduju“, ne opak schválení.

Nad `ThreadSubmission` (#73) platí:

- **Je to `struct` bez stavu**, na rozdíl od `ReviewSubmission`. Kdo čeká na odpověď a co
  selhalo, drží `AppStore` (`ThreadActionState`), protože to musí přežít odscrollování bubliny —
  a bez sheetu není co držet uvnitř objektu. Publisher se skládá až v `reply(_:)`
  a `setResolved(_:)`, takže bod 3 tvrdé podmínky platí dál.
- **Odpověď adresuje vlákno, ne komentář.** GraphQL mutace bere `pullRequestReviewThreadId`,
  tedy `ReviewThread.id`, které v modelu už je. **Změna proti zadání #73**, které jmenovalo
  `POST /pulls/{n}/comments/{id}/replies`: REST potřebuje `databaseId` komentáře (dnes se z
  konverzace netahá) a hlavně by se muselo rozhodovat, na **který** komentář ve vlákně se
  odpovídá — a to je rozhodnutí bez opory v datech, protože vlákno má jednu odpověď. Vyřešení
  GraphQL vyžaduje tak či tak (`isResolved` v RESTu není, viz #63), takže jedna cesta místo dvou.
- **Dvě mutace na vyřešení**, ne jedna s příznakem — `resolveReviewThread`
  a `unresolveReviewThread`. GitHub jinou možnost nedává.
- **Odpověď vrací celý komentář**, takže se do vlákna vloží bez dalšího čtení. Změřeno na živém
  API, že mutace dá `id`, `body`, `createdAt`, `url`, `author` i `replyTo` — přesně to, z čeho
  se skládá `ThreadComment`.
- **`comment: null` není úspěch.** Přijde s **nulovým** exit kódem (změřeno u prázdného těla),
  takže bez toho by se do vlákna vložil komentář, který na GitHubu není. Dělá se z toho
  `malformedResponse`, tedy „možná odešlo, zkontroluj to“.
- **Chybějící vlákno je vlastní chyba** (`threadNotFound`), ne `network`. Hláška
  `Could not resolve to a node with the global id` se od té o neexistujícím repozitáři liší jen
  koncem, takže na **pořadí** případů v klasifikaci záleží — a rada „zkus to znovu“ je u zmizelého
  vlákna nepravdivá, správná je „načti konverzaci znovu“.

### Vrstva `Environment` (`App/Environment/`)

Pod těmi sedmi moduly leží podpůrná vrstva — přístup ke stroji, který `GitHubGateway`,
`RepoCheckout` a `ReviewRunner` sdílejí. Není to osmý modul: nemá vlastní zodpovědnost
v domény review, jen drží to, čím se s systémem mluví.

| Typ | Co dělá |
|---|---|
| `Tool` | Výčet `gh` / `git` / `claude` + k čemu je a jak se instaluje (texty pro gate) |
| `ToolPaths` | Absolutní cesty ke všem třem. **Neoptional pole** — vznikne jen když preflight prošel, takže zbytek aplikace neřeší chybějící binárku |
| `ExecutableProbe` | Protokol: leží na cestě spustitelný soubor? Reálná implementace odmítá složky (`/usr/bin` má spustitelný bit taky) a následuje symlinky (`claude` je symlink) |
| `ProcessRunning` | Protokol: spusť, počkej, seber stdout/stderr/exit. `SubprocessRunner` nad `Foundation.Process`, s timeoutem, eskalací `SIGTERM` → `SIGKILL` a zabitím při zrušení. `environment` se k prostředí aplikace **přidává**, nepřepisuje ho — jinak by podproces přišel o `HOME` a nenašel konfiguraci |
| `ProcessStreaming` | Protokol: výstup **po řádcích, jak vzniká**, plus `workingDirectory`. `SubprocessStreamer` nad `Foundation.Process`. Chyby chodí v proudu, ne z volání |
| `LaunchedProcess` | Běžící proces a jeho pipy za `Sendable` fasádou. Staví na něm obojí — bufferovaná i streamovací cesta |
| `ShellPathReading` | Protokol: `PATH` z login shellu (`zsh -lc 'echo $PATH'`). Selhání = prázdný seznam, ne pád |
| `BinaryLocator` | Nejdřív známá místa, teprve pro zbytek login shell — a ten **jednou** pro všechny chybějící |
| `GhAuthCheck` | `gh auth status`: exit 0 přihlášen, 1 nepřihlášen, cokoli jiného `checkFailed` se stderrem |
| `Preflight` | Složí lokaci + auth do `PreflightReport` |
| `TimeSource` | Protokol: `now` a `sleep(for:)`. Hodiny jsou přístup ke stroji jako každý jiný — a bez nich by testy pollingu čekaly reálné minuty |
| `HTTPGetting` | Protokol: `GET` s `If-None-Match`. `URLSessionHTTP` nad `URLSession` — **jediné místo, kde aplikace chodí na síť sama**, bez podprocesu |
| `NetworkReachability` | Protokol: proud „má stroj cestu do sítě?“. `PathMonitorReachability` nad `NWPathMonitor` |

`PreflightReport` je jediná pravda o prostředí; `problems` i `toolPaths` se z něj **jen
počítají** — čistě, bez I/O. Tady platí totéž pravidlo jako u `Policy`: když píšeš `if`
nad stavem prostředí ve view, patří to do reportu.

**Streamování je vlastní protokol, ne další metoda `ProcessRunning`.** Fake implementace
`ProcessRunning` jsou u `gh` i `git` v každém druhém testu a metodu, kterou nikdy
nezavolají, by musely dopsat všechny. `workingDirectory` je jen v `ProcessStreaming` —
`claude` pracovní složku flagem předat neumí, kdežto `git` si vystačí s `-C`.

Šest věcí o podprocesech, na které se naráží znovu:

- **Blokující I/O nesmí na kooperativní pool.** `readToEnd()` neumí čekat kooperativně
  a pool má jen tolik vláken, kolik je jader — několik paralelních review by si je
  vzájemně vyhladovělo. `SubprocessRunner` ho proto odsouvá na vlastní `DispatchQueue`
  a volajícímu ho podává přes `async let`, takže zůstává navázané na životní cyklus
  volání. `Task.detached` by odvázalo strukturu **a** problém neřešilo.
- **Na konec procesu se čeká přes `terminationHandler`, ne `waitUntilExit()`.** To je taky
  blokující, takže by na každý podproces připadala **tři** vlákna z `ioQueue` (dvě čtení
  a čekání). Jakmile jich je v běhu dost, nemá si nové čekání kde spustit a volání uvízne
  — projeví se to jako **náhodně visící běh testů**, ve kterém všechny testy prošly.
  Stálo to půl dne hledání; s `terminationHandler`em jde sada pětkrát za sebou zeleně,
  před tím padal každý druhý až třetí běh.
- **Oba pipy se musí číst souběžně.** Sériově: než dojde EOF na prvním, druhý naplní buffer
  jádra a proces se zasekne na zápisu.
- **Zrušení musí proces zabít.** Bez toho čekání na EOF drží volání, dokud proces nedoběhne
  sám. Řeší `withTaskCancellationHandler`, u proudu `continuation.onTermination`.
- **Proud smí skončit teprve po EOF na obou rourách, ne po exitu procesu.** Skončit hned po
  exitu by uřízlo řádky, které ještě leží v rouře — u review přesně ty poslední, ve kterých
  bývají nálezy.
- **Timeout má poslední slovo, i když EOF nedorazí.** Roury může držet něco, co po procesu
  zbylo, a proud by pak čekal navždy. Proto hlídání běží až do konce **proudu** (ruší ho
  `onTermination`, ne konec procesu) a po `SIGKILL`u proud ukončí samo. Data, která po
  konci proudu ještě přijdou, se zahodí a čtení se odpojí — ukecaný potomek by jinak plnil
  buffer, ze kterého už nikdo nečte.

**`zsh -lc` nečte `.zshrc`** — neinteraktivní login shell čte `.zshenv`, `.zprofile`
a `.zlogin`. Přidat `-i` se zkoušelo a zahodilo (viz komentář v `LoginShellPathReader`
a specifikace): z aplikace se zaseklo a interaktivní shell navíc **ignoruje `SIGTERM`**.
Právě proto tam eskalace na `SIGKILL` je.

Nad `HTTPGetting` (#31) platí:

- **Stavový kód je data, ne chyba.** Chybou je jen to, že se na server nedostaneme
  (`transport`, `timedOut`); `304` a `503` zařadí až ten, kdo ví, na co se ptal — stejná
  úvaha jako u `ProcessResult`.
- **`ETag` řeší volající, ne `URLCache`.** Cache rozhoduje sama, kdy se zeptá znovu; smyslem
  je ptát se v pevném intervalu a **poznat**, že se nic nezměnilo. Sezení je proto
  `ephemeral`, bez cookies a bez cache.
- **Zrušení se překládá na `CancellationError`.** `URLSession` ho hlásí jako
  `URLError(.cancelled)`; vydávat ho za výpadek sítě by po zavření okna probleskovalo
  hláškou o nedostupné službě. Totéž pravidlo drží `ReviewRunner` i `GhReviewPublisher`.

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

  Druhá výjimka je `ASSETCATALOG_COMPILER_APPICON_NAME` (#83): je to **build setting**, takže
  jinudy než pbxprojem nastavit nejde. Leží na **app targetu**, ne na projektu — testovací
  target ikonu mít nemá; je to tatáž úvaha jako u `CODE_SIGN_IDENTITY`, jen obráceně.
  Samotný `App/Assets.xcassets` se ale v pbxproj **nevyjmenovává** — buildable folder ho
  vezme z filesystému a `actool` ho zkompiluje do `Assets.car` a `AppIcon.icns`. Ověřeno
  obsahem `.app`.
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

- **Modely** — round-trip přes `Codable` u každého typu i každého případu `ReviewState`,
  parsování a formátování identifikátorů včetně neplatných vstupů, a kontrola skutečného
  tvaru JSONu (identifikátor musí být řetězec, slovník klíčovaný jím musí být objekt).
  Pomocníci na round-trip jsou v `Tests/Models/CodableRoundTrip.swift`; balí hodnotu do
  pole, protože holý řetězec by na nejvyšší úrovni byl JSON fragment.
- **`Policy`** — vyčerpávající unit testy, nic se nemockuje. U slučování zdrojů včetně
  toho, co se snadno přehlédne: kolize s různým `updatedAt` v obou pořadích zdrojů,
  prázdný zdroj, žádný zdroj a **shodné časy** (na kterých se pozná nedeterministické
  řazení). U nálezů hranice blokující sady, každý způsob, jak návrh verdiktu **nevznikne**,
  shoda 1×/2×/3× a řazení ověřené i z obráceného vstupu. Data staví `Tests/Policy/
  FindingFactory.swift` — není to fake, jen zkratka; uložený běh se skládá přes `ReviewRun`,
  tedy tou cestou, kterou vzniká doopravdy.
- **`Environment`** — `BinaryLocator`, `GhAuthCheck`, `LoginShellPathReader` a `Preflight`
  proti fakes (`Tests/Environment/EnvironmentFakes.swift`). `FakeShellPathReader` počítá
  volání: že se login shell spustí nejvýš jednou a jen když je co dohledávat, je součást
  kontraktu, ne detail. Plus malý počet testů proti skutečnému systému
  (`RealEnvironmentTests`) na to, co fake ověřit neumí — složka se spustitelným bitem,
  symlink, skutečný timeout, skutečný `zsh -lc`.
- **`GitHub`** — `GhGateway` proti `FakeProcessRunner` (z `Tests/Environment/`) a fixtures;
  klasifikace chyb tabulkou nad `ProcessResult`, mapování stavu vyčerpávajícím výčtem.
  Testuje se i **tvar argumentů** předaných `gh` — rozdělení dotazu na tokeny a seznam
  `--json` polí je kontrakt s `gh`, ne detail.
- **Konverzace** — proti fixtures, které jsou surové odpovědi z veřejných PR `cli/cli`
  sebrané **tím dotazem, který posílá aplikace** (`ConversationQuery.document`). Kdyby se
  sbíraly jinak, testovaly by tvar, který v provozu nikdy nepřijde; ověřené je to i tak, že
  volání složené aplikací (`-f query=<víceřádkový text>`) dá bajt po bajtu tutéž odpověď.
  Pokrývá: vyřešené vlákno, 24 zastaralých vláken bez `line`, odpověď ukazující na svého
  předchůdce, schválení s prázdným tělem, useknutou stránku (1 ze 38) a to, že se
  `hasNextPage` s počty **nerozchází** — bez toho by `or` v `isTruncated` schoval, že jednomu
  ze signálů nerozumíme. Syntetickým JSONem se testuje, co se ze skutečného PR nesehná:
  chybějící `pullRequest`, `nodes: null`, komentář bez autora a neznámý stav review.
  U dotazu se hlídá **seznam polí** — kdyby z něj vypadlo `isResolved`, ukazovala by se
  vyřešená vlákna jako otevřená.

  **Práva viewera (#73)** mají vlastní fixture z `cli/cli` (`conversation-thread-rights.json`,
  `first: 2`), protože na cizím repu jsou obě `false` — tedy zrovna ten případ, kvůli kterému se
  ta pole tahají. Starší fixtures je nemají, a to je **taky test**: ověřují, že se chybějící
  právo bere jako povolení. Rozdíl mezi `canResolve` a `canUnresolve` se na skutečné odpovědi
  nesehná (na cizím repu obě `false`, na vlastním obě `true`), takže na něj je syntetický JSON.
- **Odpovídání do vláken (#73)** — čisté funkce plus publisher proti `FakeProcessRunner`.
  Nejdůležitější testy netvrdí, co se odeslalo, ale že se **nic neodeslalo**
  (`runner.invocations.isEmpty`): bez povolení v nastavení, s prázdným tělem a na zavřený PR.
  Vedle toho to, co je u odpovědi **jinak než u review** — nový commit odpověď ani vyřešení
  neblokuje. Klasifikace se hlídá tabulkou nad **skutečnými** hláškami z živého API, včetně toho,
  že se chybějící vlákno nesmí splést s výpadkem sítě; a `comment: null` musí skončit chybou, ne
  úspěchem. `Policy.inserting` má vlastní sadu, ve které je to hlavní, že vložení **nesníží**
  `missing` u useknutého vlákna.
- **`AppStore` — odpovídání (#73)** — `gh` je **podstrčený shell skript** v dočasné složce, který
  vypíše připravenou odpověď a zapisuje, kolikrát byl spuštěn. Fake publisher se sem podstrčit
  nedá (store si ho podle tvrdé podmínky nesmí držet ani jako továrnu), takže se projde celá cesta
  včetně čtení výstupu — a nula spuštění je jediný způsob, jak dokázat, že se **nevolalo nic**.
  Pokrývá: odpověď ve vlákně **bez druhého dotazu** na konverzaci, selhání, které **nechá text**,
  prázdnou odpověď bez volání sítě, a dvojklik pouštěný **souběžně** (sekvenční test by prošel
  i bez ochrany, proto má skript krátkou odmlku).
- **Dostupnost služeb (#31)** — tři vrstvy, každá jinak. `Policy.health` vyčerpávajícím
  výčtem stavů (nic se nemockuje), včetně toho, co se dá pokazit tiše: že **incident mimo
  sledované komponenty puntík nerozsvítí** (skutečná fixture s výpadkem v `Actions`), že
  **status page sama na zelenou nestačí**, že se **offline nevydává za výpadek služby**, že
  selhaná kontrola nic nezablokuje a že **každý stav má neprázdný důvod** — puntík, který po
  hoveru nic neřekne, je dekorace. `StatusPageClient` proti `FakeHTTPGetter` na operational,
  incident, rozbitý JSON, `503`, `304` a na to, že se **`ETag` neukládá po odpovědi, které
  jsme nerozuměli** a že se **nepletou mezi službami**. `HealthMonitor` na to, že se na pozadí
  nekontroluje nic, že skryté okno interval neposouvá, že výchozí interval je deset minut
  a po selhaném volání minuta, že `304` a selhaná kontrola nechávají poslední známý stav a že
  zrušení není selhání. `AppStore` na to, odkud se berou skutečná volání — z pollingu (včetně
  rate limitu) a z výsledků session (včetně toho, že `timedOut` nezapisuje nic).

  Fake čas u smyčky **neuspává**, takže dojede celá při prvním `yield`u; přepínat jí stav
  uprostřed je závod a testy proto pouštějí dvě smyčky za sebou.
- **`URLSessionHTTP`** — proti **skutečnému systému**, ne fake runneru, a přitom **bez sítě**:
  chodí se na `127.0.0.1:1`, kde nikdo neposlouchá. Fake ověří, co si s odpovědí počne
  klient, ale ne to, jestli `URLSession` odmítnuté spojení a zrušení hlásí tak, jak si
  myslíme. Zrušení je deterministické — tělo tasku se rozjede teprve na `task.value`, tedy
  po `cancel()`.
- **Fixtures** — `Tests/Fixtures/`, načítané přes `Fixture.text(_:)` a `Fixture.data(_:)`.
  Cesta se odvozuje
  z `#filePath`, ne z bundlu: Swift Testing nemá `XCTestCase`, od kterého by šel
  `Bundle(for:)` odpíchnout. V `Fixtures/gh/` leží **skutečné** výstupy `gh`, jen
  přeformátované `jq`; berou se z **veřejných** repozitářů (`cli/cli`, `cli/go-gh`,
  `ondrajodas/PRism`), protože titulky firemních PR sem nepatří. Stav, na který se
  skutečná fixture nedá sehnat, se testuje inline JSONem přímo v testu.

  Výjimka jsou `review-error-*.json` ze spike #62: chybové odpovědi zápisového review API
  se z veřejného repa sehnat nedají (musel by se do něj poslat rozbitý payload), takže
  pocházejí ze soukromého sandboxu `ondrajodas/prism-review-sandbox`. Neobsahují nic než
  hlášku GitHubu. Konzumenta zatím **nemají** — klasifikaci chyb odesílání píše #67; leží
  tady proto, že bez zápisu na GitHub se nedají vyrobit znovu.

  `Fixtures/statuspage/` jsou **skutečné** `components.json` z obou status pages, sebrané
  tou adresou, na kterou se ptá aplikace. `github-incident.json` je z nich jediný upravený:
  incident se na přání nevyrobí, takže je do skutečného tvaru dopsaný — `major_outage`
  a `degraded_performance` na sledovaných komponentách a `partial_outage` v `Actions`, aby
  bylo na čem ověřit, že se cizí výpadek nepočítá.
- **`StreamParser`** — proti **všem** fixtures ze skutečných běhů, plus syntetické rozbité
  vstupy: nevalidní JSON, useknutý řádek, neznámý event, nález bez povinných polí, prázdný
  vstup. Fixtures ze skutečných běhů už v repu jsou
  (`Tests/Fixtures/stream-json/`, viz [`docs/claude-cli.md`](docs/claude-cli.md)): běh
  s nálezy, čistý běh, zabitý běh a odmítnutý zápis. Parser se testuje proti nim.
- **`DiffParser`** — proti **skutečným** výstupům `gh pr diff` z veřejných repozitářů
  (`Tests/Fixtures/gh/pr-diff-*.diff`: běžný diff, přejmenování včetně `similarity index
  100%` bez hunků, 44 binárek vedle textových souborů, smazaný soubor). U každé fixture se
  kontroluje `unrecognizedLines == 0` — to je ta věta „rozumím celému formátu“. Syntetické
  vstupy pokrývají, co se z reálného PR nedá sehnat: odebraný řádek začínající `---`,
  hunk bez počtu řádků, `\ No newline at end of file`, prázdný kontextový řádek, změna
  jen práv a nesmysl mezi soubory.
- **`DiffRow`** — skok z nálezu: na změněný řádek, na soubor u nálezu bez čísla i mimo
  hunky, `nil` u souboru mimo diff, a přejmenovaný soubor nalezený pod starou cestou.
  Rozbalení kontextu má vlastní sadu: kde skryté úseky jsou (nad prvním hunkem, mezi
  hunky s posunem starých čísel, za posledním s neznámým koncem), že se rozbalený řádek
  chová jako kontext s oběma čísly, že se hlavička po slití hunků sundá a že kotva na
  řádek platí i po rozbalení.
- **Pohled vedle sebe (#98)** — párování nad syntetickými diffy (stejně dlouhé bloky,
  nestejně dlouhé na obě strany, samostatný blok odebraných i přidaných, kontext, `meta`, nový
  a smazaný soubor, odebraný řádek **po** přidaném) a nad tím dva **invarianty** proti
  skutečným fixtures: že se z dvojic poskládají přesně původní řádky (počty, tedy ztráta
  i zdvojení) a že pořadí na každé straně kopíruje původní diff. Ověřené dočasně vloženou
  regresí, ne jen zeleným během: vypuštěný přebytek odebraných shodí obojí.

  Vedle toho `SplitBubbleTests` na to, co se dá pokazit tiše: bublina nálezu pod dvojicí,
  nález mimo diff, který u hlavičky souboru **zůstane**, vlákno na **odebrané** straně, vlákno
  a komentář na kontextovém řádku, které **nesmí vzniknout dvakrát**, a kotvy — nálezová platí
  v obou pohledech (i po rozbalení kontextu), kdežto ta na komentář k odebranému řádku míří ve
  split pohledu na dvojici.
- **`FileTreeNode`** — slévání složek s jediným potomkem, větvení, pořadí podle diffu,
  součty na složkách a unikátní identity (`a/x.swift` vs `b/x.swift`).
- **`AppStore` — dotažení kódu k nálezům** — že se tahá jen u nálezu mimo hunky, že se
  nesahá na soubor mimo diff ani na nález bez řádku, a že se druhý rozsah vyžádaný během
  načítání neztratí.
- **`RevealedLines`** — slučování překrývajících se i **sousedících** rozsahů a dělení
  mezery na skryté a odkryté kusy, včetně odkrytí, které mezeru přesahuje.
- **`Policy.chips`** — každý stav zvlášť, včetně toho, že nereportující běh ani běh se
  ztraceným nálezem nesmí vyjít jako `čisté`, že běžící reviewer přebije starší výsledek
  a že reviewer mimo nastavenou sadu o chip nepřijde.
- **`ToolAttempt`** — zkrácení proti pracovnímu stromu: relativní cesta, zahozené
  `cd <strom> &&`, cesta uvnitř příkazu, a že se bez stromu nic nemění. Pozor na past
  v testu: skutečný nástroj dostane cestu **nekódovanou**, takže `URL.path()` v přípravě
  vstupu ověřuje něco, co nikdy nevznikne.
- **`AppStore` — průběh** — pořadí událostí včetně konce běhu, že osa přežije doběhnutí,
  že nový běh začíná načisto a že se s PR mimo seznam zahodí. Plus detekce záměny skillu:
  načtený jiný, načtený správný a běh bez skillu (ten záměna není).
- **`FindingRow`** — skládání textů (`—` u nálezu bez místa, samotný soubor bez řádku,
  `file:line` bez locale u velkých čísel), blokující příznak, výchozí pořadí z `Policy`
  a unikátní identita řádků. Plus **nápověda k místu**: celá cesta u nálezu s řádkem
  i bez něj a vysvětlující věta tam, kde je ve sloupci `—`. Šířky sloupců se
  neunit-testují — `Table` je AppKit tabulka, takže offscreen render z ní udělá žlutý
  placeholder stejně jako z `Listu`; kontroluje se na běžící aplikaci.
- **Bubliny nálezů** — že bublina visí pod svým řádkem, že nález mimo diff a nález bez
  řádku skončí u hlavičky souboru (a v pořadí podle čísla řádku), že se po rozbalení
  kontextu bublina k řádku přesune, že dva reviewery na jednom řádku dají jednu bublinu
  s `agreement == 2` a že se nálezy cizích souborů nepřipletou.
- **`SyntaxHighlighter`** — každý test ověřuje i **invariant**, že spojení run dá zpátky
  původní řádek. Pokrývá komentáře (i mřížku jen tam, kde ji jazyk má), řetězce
  s escapovanou uvozovkou i neuzavřené, komentář v řetězci a naopak, klíčová slova jen
  jako celá slova, čísla mimo jména, proměnné se sigilem i ve složených závorkách
  a diakritiku. `Language` má tabulkové testy na detekci z přípony i ze jména souboru.
- **`AppStore` — diff** — proti fake gateway: načtení, cache podle `updatedAt`, opakování
  po selhání a zahození diffu PR, které zmizelo ze seznamu.
- **`AppStore` — zahození nálezů** — proti **skutečnému** `ReviewStore`: že to zmizí
  z panelu, z řádku i z disku a přežije restart, že další běh začíná načisto, že druhé
  zmáčknutí nic nerozbije, že starší záznamy zůstanou a že se na automatickém repu review
  pustí samo, kdežto na manuálním ne.
- **`AppStore` — pohled na diff** — že se bez odchylky bere hodnota z nastavení, že ji přepnutí
  v liště přebije, že se změna nastavení projeví **bez restartu** a že odchylka **shodná**
  s nastavením přežije jeho změnu. Poslední dva potřebují skutečný `ConfigStore` nad dočasnou
  složkou: bez něj `updateConfiguration` skončí chybou `noStore` a nepropíše se nic.
- **`AppStore` — sbalení souborů** — výchozí rozbaleno, přepínání tam a zpět, že sbalení
  jednoho souboru nesahá na jiné ani na jiné PR, idempotentní rozbalení (na tom stojí skok)
  a `Rozbalit vše`, které nechá cizí PR být.
- **`AppStore` — rozbalení kontextu** — že se obsah souboru dotáhne jednou, že selhání
  nenechá po sobě točící se kolečko ani úsek označený za odkrytý, a že sbalení zahodí
  rozsahy, ale načtený obsah nechá.
- **`PollingService`** — proti `FakeGitHubGateway` (odpovědi v pořadí, poslední se opakuje)
  a `FakeTimeSource`. Ten místo čekání zapisuje **požadované délky uspání** — na nich se
  ověřuje backoff — a po zadaném počtu uspání smyčku ukončí `CancellationError`em. Testy
  tak běží v nulovém reálném čase a bez závodů. Pozor na počítání odpovědí: selhávající
  tik spotřebuje jen jednu, protože se u prvního zdroje přeruší.
- **`AppStore`** — proti fake gateway: obnovení se ptá zdrojů, seznam se čte z pollingu,
  výběr se drží. Views se neunit-testují; kontroluje se běžící aplikace (viz níž).
- **`AppStore` — review** — fake gateway, fake checkout, fake reviewer a **skutečný**
  `ReviewStore` nad dočasnou složkou: on rozhoduje, co se objeví po restartu, takže fake by
  ověřoval sám sebe. `FakeReviewRunner` umí běh pozdržet, na čemž stojí testy průběhu,
  zrušení a toho, že druhé zmáčknutí nespustí nic dalšího. Čeká se točením přes
  `Task.yield()`, ne na continuation — zrušený běh musí z čekání vypadnout sám, jinak by
  test visel místo aby spadl. Součástí je `runningReviews` **napříč PR**: na tom čísle visí,
  jestli se aplikace před zavřením zeptá. Samotný dialog se unit-testovat nedá (modální
  `NSAlert`), ověřil se na běžící aplikaci — viz níž.
- **`ReviewPublisher`** — proti `FakeProcessRunner` a fake gateway. Úklid dočasného souboru
  se ověřuje **cestou z konkrétní invokace**, ne obsahem systémové dočasné složky: Swift
  Testing pouští testy paralelně, takže porovnání „před a po“ nad `/tmp` je flaky (chytilo se
  to v review #67). Nejdůležitější testy
  netvrdí, co se odeslalo, ale že se **nic neodeslalo**: výchozí (vypnuté) nastavení, neshoda `headSha`,
  zavřený PR a draft bez verdiktu musí skončit dřív, než se sáhne na `gh` (kontroluje se
  `runner.invocations.isEmpty`). Klasifikace chyb jde tabulkou nad **skutečnými** hláškami
  z fixtures (`review-error-*.json`), úspěch nad skutečnou odpovědí (`review-submitted.json`)
  — obojí z živého API. Tvar payloadu je ověřený tím, že týž payload API u #67 přijalo.
  `FakeReviewPublisher` v `Tests/Publish/` nic neodesílá a počítá, co po něm kdo chtěl.
- **`ReviewDraftStore`** — proti skutečné dočasné složce, jako `ReviewStore`. To hlavní je
  „draft přežije restart“, tedy načtení **novým** storem nad tou samou složkou. Plus prázdný
  draft, který se maže; nečitelný soubor, který se ve výpisu počítá a u konkrétního PR vyhodí
  chybu; draft cizího PR uvnitř souboru; a že cesta leží mimo složky, po kterých chodí
  eviction. Pozor na past v testu: `ReviewDraftComment` si generuje `UUID`, takže dvě volání
  továrničky nedají shodné hodnoty — draft se musí uložit do proměnné.
- **`Policy` — draft** — komentovatelnost vyčerpávajícím výčtem: přidaný řádek (`right`),
  kontextový (`right`), odebraný (`left`), `meta` (nikdy), řádek mimo hunky a **rozbalený
  kontext**. Ten poslední se staví přes `DiffRow.rows(revealed:content:)`, ne ručně —
  rozbalený řádek se skládá jako obyčejný kontext s oběma čísly, takže test, který si ho
  vyrobí sám, by netestoval to, co v aplikaci vzniká.

  U kotev navíc to, že **mapa dává totéž co dotaz po jednom řádku** — je to jen zrychlení,
  takže rozchod by nabízel komentáře na řádcích, které GitHub odmítne. U rozřazení nálezu
  každá varianta zvlášť (řádek v hunku, mimo hunky, bez řádku, bez souboru, bez diffu)
  a **stará cesta přejmenovaného souboru**, která se musí přeložit na dnešní. U odznaku
  „už je v draftu“ to hlavní: nález **druhého** revieweera na tomtéž řádku převzatý není.
  U permalinku zakódovaná mezera v cestě a odkaz na vlastním řádku — bez obojího GitHub
  úryvek kódu nevyrenderuje.

  U **odesílatelnosti** (#68) každý důvod zvlášť a **v pořadí**, ve kterém se hlásí: že repo
  bez povolení přebije i hotový draft, že neznámá hlava není zastarání a že prázdný komentář
  blokuje. Brána se od #107 **předává**, takže si test o povolení řekne (`PublishScope.allowing(_:)`)
  místo toho, aby musel běžet nad sandboxovým identifikátorem; že výchozí konfigurace nepovolí
  nic, drží vlastní test. Plus to, že **každý důvod má
  vlastní neprázdnou větu** — prázdná by v okně vypadala jako mlčky zakázané tlačítko.
- **`ReviewSubmission` (#68)** — proti `FakeReviewPublisher`, takže se **nic neodesílá**.
  To hlavní není, co se odeslalo, ale kdy se **neodešle nebo neuklidí**: selhání nesmí spustit
  úklid draftu (a musí jít zkusit znovu), po úspěchu se nesmí odeslat podruhé a zrušení se
  nesmí hlásit jako chyba. Plus zavírání sheetu — u odpovědi, jejímuž stavu nerozumíme,
  zůstává otevřený — a rozchod s návrhem z nálezů, u kterého se hlídá i to, že `jen komentář`
  rozchod **není**. Pozor na past: `ReviewDraftComment` si generuje `UUID`, takže se draft
  musí uložit do proměnné, ne vyrobit dvakrát.

  Dvě věci se testují tabulkou chyb, protože jsou to celé **třídy**, ne jednotlivé případy:
  po které chybě se smí zkusit znovu a po které ne (`mightHaveReachedGitHub`).

  Čeká se u nich **odmlkami, ne `Task.yield()`**, na rozdíl od zbytku repa. Ten spin by běžel
  na `MainActoru` (`ReviewSubmission` je `@MainActor`) a **bez horní hranice** — dokud závoru
  někdo nepustí. Swift Testing pouští suity paralelně, takže z toho začaly padat
  `SubprocessStreamerTests`: zabíjený proces se nestihl zabít dřív, než mu doběhl `sleep 1`.
  Změřeno, ne odhadnuto — na `main` procházely, na branchi padaly dvakrát za sebou a po
  záměně za `Task.sleep(for: .milliseconds(1))` je sada třikrát po sobě zelená.

  A **dvojklik se pouští naráz** (`async let` dvakrát), ne s čekáním na to, až první odeslání
  poběží. Zákaz druhého odeslání drží jen na tom, že `state = .sending` leží před prvním
  `await`; test, který na první odeslání počká, ten závod zavře a přesunutí toho řádku by mu
  prošlo. Ověřeno tím, že se ta regrese do kódu dočasně vložila — sekvenční test zůstal
  zelený, souběžný spadl na `2 == 1`. `FakeReviewPublisher` umí odeslání **pozdržet**
  (`hold(until:)`) ze stejného důvodu jako `FakeReviewRunner`.
- **`AppStore` — odeslání (#68)** — proti **skutečnému** `ReviewDraftStore` nad dočasnou
  složkou: po úspěchu má draft zmizet i z disku, tedy i pro restart. Vedle toho každý stav,
  ve kterém `submission(for:)` nesmí vzniknout (zastaralý draft, chybějící verdikt, žádný
  draft), a to, že se konverzace načte znovu — bez toho by v `Přehledu` chybělo moje vlastní
  review až do přepnutí PR.
- **`Policy` — přehled (#72)** — chronologické slití review, komentářů a vláken; že se vlákno
  **s kotvou** do přehledu nedostane (jinak se tentýž komentář čte na dvou místech); že review
  bez verdiktu a bez prózy vypadne (je to jen obálka řádkových komentářů), kdežto schválení
  s prázdným tělem zůstane; že položka bez data jde naspod, ne pryč; a že shodné `id` u review
  a komentáře dá dvě položky, ne jednu.
- **`MarkdownParser`** — každý test ověřuje i **invariant**, že se žádný obsah neztratil
  (písmena a číslice ze všech bloků složené zpátky). Pokrývá nadpisy včetně falešných (`#tag`),
  odstavce se zalomením, odrážky/čísla/zaškrtávátka, zanoření, fence (i neuzavřený a s cizími
  značkami uvnitř), citace, oddělovače, tabulky — a HTML od botů: `<!-- … -->`, `<details>`
  včetně **zanořeného** a neuzavřeného. Plus skutečný popis PR z fixture, tedy cizí text, který
  nikdo nepsal pro test. `MarkdownHTML` má vlastní sadu: odkaz na Markdown se všemi druhy
  uvozovek, `<br>`, entity a to, že `&amp;` se dekóduje naposled.
- **`AppStore` — taby** — výchozí `Přehled` (proti `PullRequestTab.standard`, ať se to nerozejde),
  volba per PR, přepnutí zpátky mažící klíč a úklid s PR, které zmizelo ze seznamu.
- **`AppStore` — rozdělané review** — proti **skutečnému** `ReviewDraftStore` nad dočasnou
  složkou: on rozhoduje, co je po restartu, takže fake by ověřoval sám sebe. Pokrývá cestu
  od kliknutí po disk (komentář, verdikt, tělo, převzetí nálezu do těla i na řádek), a hlavně
  to, co se dá pokazit tiše: draft, který se **nezakládá** bez známé hlavy PR; prázdný
  komentář, který se zahodí a s ním i prázdný draft; zastarání po novém commitu, které text
  **nechá**; a že „nevím, jaká je hlava“ se za zastaralé nevydává. Čeká se točením přes
  `Task.yield()`, protože zápis běží v tasku.
- **Bubliny rozdělaných komentářů** — že komentář visí pod svým řádkem, že `left` sedne na
  **odebraný** řádek (tatáž past jako u vláken v #64), že se komentář na řádku mimo diff
  nekreslí, že se dva na jednom řádku neslijí a že pořadí je nález → vlákno → můj komentář.
  Plus kotva pro skok z panelu, včetně `left` a fallbacku na soubor.
- **`ReviewStore`** — proti skutečné dočasné složce, ne proti fake filesystému: kořen je
  injektovatelný, takže jde o pár kilobajtů, a ověřuje se to, na čem store stojí — `Codable`
  cesta na disk a zpět a chování `FileManageru`. Hodiny jsou `FakeTimeSource`, který se
  posouvá uspáním, takže třicetidenní lhůta se testuje v nulovém reálném čase. Round-trip
  `ReviewRecord` má vlastní testy včetně **každého případu** `ReviewRunOutcome` — `failed`
  nese asociovanou hodnotu a ta se z JSONu ztratí nejtišeji.
- **`Config`** — merge globální + per-repo, defaulty pro neznámé repo. U režimu navíc to,
  co se dá rozbít tiše: že vlastní `manual` přebije globální automat, že se takový záznam
  nesmaže jako „shodný s globálním“ a že se rozbitá hodnota srazí na `manual`, kdežto
  chybějící klíč vezme globální.
- **Jazyk nálezů** — u konfigurace výchozí čeština, override per repo a to, že se vlastní
  hodnota nesmaže jako shodná s globální (stejná past jako u režimu). U promptu naopak to,
  že o jazyku **mlčí** — kdyby se to vrátilo, stálo by to nálezy.
- **Překlad** — `TranslationCommand` na každou podobu nesmyslu, kterou model umí vrátit:
  prohozená `id`, `id` mimo rozsah, chybějící položka, code fence, prázdno, položka bez
  `summary`. `ClaudeFindingTranslator` proti fake procesu na to, že nenulový exit ani
  rozbitá odpověď nevyhodí chybu. `AppStore` na celou cestu: přeložené nálezy na disku
  i po restartu, angličtina bez volání, čisté review bez volání, selhaný překlad
  s originály a — to hlavní — **nepřeložený nález, který nesmí zmizet vedle přeložených**.
- **`Policy.automaticallyReviewable`** — automat vs. manuál, už zvážený PR, změněný
  `updatedAt`, běžící PR, draft a prázdný seznam.
- **`AutoRunLedger`** — proti skutečné dočasné složce, protože jde právě o to, že
  počitadlo **přežije restart**. Plus nový den, nulový limit (vypnuto, ne „bez omezení“)
  a rozbitý soubor, který automat umlčet nesmí.
- **`AppStore` — automatický režim** — celý řetěz od tiku po session: automat spustí,
  manuál ne, druhý tik nad stejným commitem session **neutratí**, komentář (jiné
  `updatedAt`, stejný `headSha`) taky ne, nový commit ano, a denní limit pozastaví.
- **`Policy.projectLanguages`** — jednojazyčné projekty (PHP, Go, TS, Swift), smíšený
  s pořadím podle váhy, zatoulaný soubor pod prahem, marker bez souborů, prázdný repozitář
  a repozitář bez zdrojáků. Plus to, co se snadno rozbije: že samotný `package.json`
  JavaScript nezpůsobí a že při shodě počtů rozhoduje jméno.
- **`AppStore` — jazyk repa** — fake checkout dodá výpis souborů, **skutečný** `ConfigStore`
  nad dočasnou složkou rozhoduje, co v souboru zůstane. Pokrývá zápis odvozené sady i to,
  kdy se **nezapisuje**: shoda s globální, ruční hodnota, prázdná ruční hodnota. A že
  reviewer dostane odvozenou sadu **hned při prvním běhu**, ne až podruhé.
- **`Policy.knownRepositories`** — union seznamu PR a konfigurace, dedup, řazení bez ohledu
  na velikost písmen a repo bez otevřeného PR, které ze seznamu zmizet nesmí.
- **`SettingsModel`** — odložený zápis přes `FakeTimeSource` (tedy v nulovém reálném čase):
  že se rychlé změny slijí do jednoho zápisu, že `flush()` uloží bez čekání, že změna
  zvenčí formulář srovná, ale vlastní uložení ne, a že je selhání zápisu vidět. Na testech
  `flush()` je vlastní `BlockingTime`, jehož uspání samo neskončí — s okamžitým fake časem
  by odložený zápis závodil s tím okamžitým a nešlo by poznat, který zapsal.
- **`CacheEviction`** — proti skutečné dočasné složce, ne proti fake filesystému: rozpočet
  je injektovatelný, takže stačí malé soubory. Pozor, počítá se **alokovaná** velikost, tedy
  po blocích — stobajtový soubor zabere 4 KB a testovací rozpočty musí být řádově výš.
- **`RepoCheckout`** — dvě vrstvy, a **obě jsou potřeba**. Fake runner ověří, co se `gitu`
  posílá za argumenty (na tocích s víc příkazy `ScriptedProcessRunner`, který odpovídá
  jinak na každé volání); integrační test (`RealRepoCheckoutTests`) klonuje z `file://`
  scratch repa a ověří, že jim `git` rozumí a vznikne z toho použitelný klon i worktree.
  Chybějící refspec u fetche prošel unit testy bez povšimnutí a chytil ho až ten druhý.
  Pozor na `contains` nad polem argumentů — porovnává **celé prvky**, ne podřetězce,
  takže refspec (`+refs/pull/85/head:refs/prism/pr/85`) se musí hledat vnořeným `contains`.
- **`ReviewRunner`** — proti `FakeProcessStreamer`, který přehraje fixtures ze skutečných
  běhů: úspěch, čisté review, nenulový exit, nespuštěná binárka, timeout. Fake umí běh
  **pozdržet**, a na tom stojí testy limitu souběhu (4 běhy, naráz nejvýš 3), slučování
  stejného klíče a zrušení. Čekání jde přes `Task.yield()` v smyčce, ne přes `sleep` —
  test, který se nedočká, uvízne, což je srozumitelnější než náhodné padání.
- **`SubprocessStreamer`** — proti **skutečným procesům** (`/bin/sh`), ne proti fake
  runneru. Že řádky přijdou v pořadí, že se doručí i useknutý poslední řádek, že proces
  běží v předané složce a že zaseknutý skončí timeoutem, se dá zjistit jen spuštěním —
  přesně tohle unit testy `RepoCheckoutu` nechytly. Odkladná doba mezi `SIGTERM`,
  `SIGKILL`em a vzdáním se čekání na EOF je proto injektovatelná (`gracePeriod`): jinak by
  test na potomka, který drží rouru po zabitém procesu, trval čtyři sekundy.

  **Zrušení se ověřuje na PID, ne na souboru, který proces po sobě nechá** (#101). Sledovat
  soubor znamená dočkat se konce jeho `sleep` — takže rezerva proti zpoždění pod zátěží se dá
  zvětšit jen tím, že test poběží stejně dlouho, a při 800 ms padal jeden běh ze čtyř, jak
  ostatních suit ubývalo procesů. Na PID (`kill(pid, 0)`, který nic neposílá) se zabití pozná
  **v okamžiku, kdy nastane**: deadline může být pětisekundový a test přesto skončí v desítkách
  milisekund. Testuje to navíc přesnější tvrzení — zmizelý proces, ne neproběhlý `touch`.

  **Flaky test se opravuje mechanismem, ne konstantou.** Zvětšení konstanty se dá jen odhadnout
  a příště se posune zátěž; polling na výsledek s velkorysým deadlinem je odpověď, která se
  nemusí ladit. Ověřuje se to **opakováním**, ne jedním zeleným během: 20 běhů suity v řadě,
  protože u flaky s 25 % je pět zelených běhů ještě čtvrtina případů.
- **`ReviewSlots`** — limit, pořadí ve frontě a zrušený čekatel, který nesmí frontu ucpat.

### Jak si zkontrolovat, jak view vypadá

`screencapture` na tomhle stroji nefunguje (chybí oprávnění Screen Recording), takže
screenshot běžící aplikace nedostaneš. Co funguje: dočasný test, který view vykreslí přes
`ImageRenderer` do PNG ve scratchpadu, a ten se pak přečte. Před commitem se maže.

Dva zádrhely, které to má:

- **`.buttonStyle(.borderless)` se v `ImageRenderer`u nevykreslí** — místo ikony vyjde žlutý
  placeholder chybějícího symbolu, i u symbolu, který existuje. Není to chyba v aplikaci,
  je to omezení offscreen renderu u AppKit-backed styles. `.plain` SwiftUI kreslí sám
  a vykreslí se správně, takže se dá ověřit. Gate proto používá `.plain`.
- **`ImageRenderer` je `@MainActor`** — pomocná funkce v testu musí být taky, jinak Swift 6
  neprojde.

- **`List` se offscreen nevykreslí vůbec** — je to AppKit tabulka a `ImageRenderer` místo
  ní nakreslí žlutý placeholder přes celé plátno. Nevypovídá to o aplikaci. Řádky se dají
  zkontrolovat tak, že se poskládají ručně do `VStack`u mimo `List`.
- **`GroupBox` se offscreen nevykreslí taky** — a na rozdíl od `Listu` beze stopy, takže to
  vypadá, že se stav vůbec nezobrazil. Stejná kategorie jako `.borderless`. Kde na kontrole
  záleží, se hodí vlastní rámeček (`background(…, in: .rect(cornerRadius:))`), který
  SwiftUI kreslí sám.
- **`Link` vyjde jako žlutý placeholder.** V aplikaci je v pořádku, offscreen ne.

Stav běžící aplikace jde vyčíst i přes accessibility — a je to **spolehlivější než render**,
protože měří skutečné okno. Chodí se po `UI elements` po úrovních; `entire contents` na
SwiftUI okně vrátí nulu:

```bash
osascript <<'EOF'
tell application "System Events" to tell process "PRism"
    set out to {}
    repeat with e in (UI elements of window 1)
        set end of out to (role of e) & " pos=" & (position of e as string) ¬
            & " size=" & (size of e as string)
    end repeat
    return out
end tell
EOF
```

`value` vrátí texty, `description` popisky tlačítek (`Obnovit`, `Skrýt boční panel`).
Takhle se dá dokázat i rozvržení: že seznam začíná pod toolbarem se pozná porovnáním
`position` scroll areay s výškou `AXToolbar`. Když se s uživatelem lišíte v tom, co je na
obrazovce, tohle to rozhodne — screenshot nedostaneš.

**Po dočasném testovacím souboru zkontroluj `git status`.** Xcode si při jeho přidání
přepíše `project.pbxproj` — samé přeformátování (uvozovky, pořadí sekcí), žádná změna
významu, ale v diffu PR je to sto řádků šumu. Smazáním souboru se to nevrátí, musí se
`git restore PRism.xcodeproj/project.pbxproj`.

**Když si na chvíli upravíš `RootView`, ať vidíš jiný stav, nezapomeň rebuildnout, než
řekneš, že je hotovo.** Vrácený zdroják na běžící aplikaci nic nezmění a pak se ukazuje
falešná obrazovka.

## Příkazy

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism test
```

```bash
./bin/run.sh    # build v Debug + otevření aplikace
                # předchozí instanci ukončí Apple eventem, ne `killall` —
                # při běžícím review se tedy zeptá a bez odpovědi nic nespustí
                # a upozorní, když je build podepsaný ad-hoc
```

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
xcodebuild -project PRism.xcodeproj -scheme PRism test > /tmp/tests.log 2>&1
grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)" /tmp/tests.log | tail -5
```

Roura `xcodebuild … | grep … | head -N` se umí zaseknout na neurčito a vypadá to jako
zaseknuté testy — přitom testy doběhnou za sekundu. Stálo to jednou přes půl hodiny
hledání neexistující chyby v testech. Když se zdá, že test run visí, první věc je pustit
ho do souboru.

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

## Stav

Scaffold hotový (issue #1) — projekt se buildí, `xcodebuild test` běží.

Kontrola prostředí hotová (issue #2) — `Environment` vrstva a `Preflight` běží při startu.
Když něco chybí, ukáže se blokující gate se všemi problémy naráz a tlačítkem `Zkusit znovu`;
když je všechno v pořádku, aplikace pokračuje do (zatím prázdného) `ContentView`.

Doménové modely hotové (issue #3) — `App/Models/`. Vrstva bez UI: aplikace se chová
stejně jako předtím, jen na ní má co stavět fáze 1.

`GitHubGateway` hotový (issue #4) — `App/GitHub/`. Umí `gh auth status`, vyhledat PR
a dotáhnout detail se SHA.

Zdroje a slučování hotové (issue #5) — `Source` v `App/Models/` a `PullRequestList`
v `App/Policy/`.

Polling hotový (issue #6) — `App/Polling/`.

**Fáze 1 hotová (issue #7).** Aplikace ukazuje skutečné PR: okno se seznamem napříč
repozitáři, prázdný stav, úvodní loading, banner při výpadku a rate limitu, výběr řádku.
Stav review je zatím u všech `neběželo` — spouštění přijde ve fázi 3.

`StreamParser` hotový (issue #13) — `App/Review/`. Ze streamu vytáhne nálezy, session id
i konec běhu, a rozbitý řádek ho nepoloží.

`ReviewRunner` hotový (issue #14) — `App/Review/` a `ProcessStreaming` v `App/Environment/`.
Umí spustit headless session v pracovním stromě, číst její výstup po řádcích, zabít ji po
patnácti minutách se zachovanými nálezy, nechat se zrušit a držet limit tří souběžných
session. Vrstva bez UI — zavolá ho `AppStore` v #17.

`ReviewStore` hotový (issue #15) — `App/Store/`. Výsledky přežijí restart, nový commit
starší záznamy označí jako zastaralé a záznamy PR, který zmizel ze seznamu, se po třiceti
dnech uklidí. Taky vrstva bez UI — načte je `AppStore` v #17.

Rozhodování nad nálezy hotové (issue #16) — `App/Policy/`. Blokující příznak, návrh
verdiktu, shoda reviewerů a pořadí pro UI, všechno čisté funkce.

**Fáze 3 hotová (issue #17).** Aplikace poprvé dělá to, kvůli čemu existuje: tlačítko
`Spustit review` u vybraného PR spustí headless session v pracovním stromě, řádek ukazuje
průběh, nálezy se ukládají a v detailu je návrh verdiktu se seznamem po kategoriích. Běh
jde zrušit. Sada skillů je zatím konstanta (`AppStore.defaultSkills`) — výběr v nastavení
je #23.

Dvě věci, které #17 odhalilo a opravilo:

- **Prompt nesmí být slash command.** `-p "/code-review …"` doběhne úspěšně, ale nálezy
  vrátí jako text a `ReportFindings` nezavolá — sběr by tiše nefungoval. Ověřeno spuštěním,
  podrobnosti v [`docs/claude-cli.md`](docs/claude-cli.md).
- **`Bash(git:*)` pouštělo i `git push`.** V cache míří `origin` na skutečné repo
  s credential helperem, takže reviewer uměl pushnout do uživatelova repozitáře. Zavírá to
  `--disallowedTools`, ověřeno i proti obcházení přes vypsanou URL.

Stavy checkoutu v seznamu hotové (issue #11) — `AppStore` umí připravit pracovní kopii,
řádek ukazuje `ve frontě · clone` nebo `clone selhal` a detail nese výstup `gitu`
i tlačítko `Zkusit znovu`. **Aplikace tím poprvé něco zapisuje na disk.**

Spike k `claude` CLI hotový (issue #12) — [`docs/claude-cli.md`](docs/claude-cli.md)
a fixtures v `Tests/Fixtures/stream-json/`. **Žádný appkový kód**, ale opravil dvě chyby
v návrhu: `--verbose` je povinný a `ReportFindings` musí být v `--allowedTools`, jinak
reviewer nálezy napíše textem a sběr tiše nefunguje.

Spike k **zápisovému review API** hotový (issue #62) —
[`docs/github-review-api.md`](docs/github-review-api.md) a fixtures
`Tests/Fixtures/gh/review-error-*.json`. **Žádný appkový kód** a tvrdá podmínka č. 1 pořád
platí; měřilo se ručně přes `gh api` nad soukromým `ondrajodas/prism-review-sandbox`. Šest
věcí, na kterých stojí zbytek M6:

- **Volání je atomické.** `POST /pulls/{n}/reviews` s verdiktem i `comments[]` odejde jedním
  voláním, a payload s jedním komentářem mimo diff skončí 422, po kterém na PR **nezůstane
  nic** — ani platné komentáře. `ReviewPublisher` (#67) proto nemusí umět částečné selhání
  ani mít obrannou validaci nad rozřazením nálezů. **Rozřadit** je ale musí — nález mimo
  hunky jde do těla jako permalink, ne jako řádkový komentář — a `DiffRow.anchor` to od #19
  umí. Atomicita mění cenu omylu v tom rozřazení, ne jeho potřebu.
- **Zastaralé `commit_id` GitHub přijme.** Review proti commitu, který už není head, projde.
  Kontrola `headSha` tedy musí být v aplikaci těsně před odesláním — tentýž důvod jako
  u tvrdé podmínky č. 5.
- **Zastarání komentáře se pozná na `line == nil`** při zachovaném `original_line`.
  `position` použít nelze, zůstává nenulové. Na tom postaví #69.
- **Kotvu určuje hunk, ne změna.** Kontextový (nezměněný) řádek uvnitř hunku komentovat jde,
  řádek mimo hunky ne.
- **Pending review blokuje odeslání** (422 `User can only have one pending review`).
  Smazat ho jde `DELETE`em, ale je to cizí rozdělaná práce — rozhodnutí pro #67.
- **Na vlastním PR jde jen `COMMENT`.** `APPROVE` i `REQUEST_CHANGES` vrátí 422, takže #68
  musí verdikt schovat, ne spadnout na chybě. A **permalink v těle review se renderuje jako
  obarvený úryvek kódu** (i rozsah `#L40-L43`) — tak se do review dostane nález mimo diff,
  místo aby se zahodil.

Čtení konverzace hotové (issue #63) — `fetchConversation(id:)`, `ConversationQuery`,
`GhConversationResponse` a modely `Conversation`, `ReviewThread`, `ThreadComment`,
`SubmittedReview`. Jeden GraphQL dotaz za 1 bod přinese review ostatních, vlákna u řádků
(s `isResolved` i `isOutdated`) a komentáře pod PR. Aplikace zůstává vůči GitHubu jen pro
čtení.

`ReviewPublisher` hotový (issue #67) — `App/Publish/`. **Aplikace umí odeslat review**, a tím
se změnila tvrdá podmínka č. 1 na pravidlo „jediná cesta ven“ (viz Tvrdé podmínky). Odesílá se
jedním atomickým voláním, po pre-flightu na `headSha` a stav PR, a jen tam, kde to `PublishScope`
povolí. Vrstva bez UI — tlačítko přišlo až s #68.

Odeslání z okna hotové (issue #68) — `ReviewSubmission` v `App/Publish/`,
`ReviewSubmissionSheet`, `Policy.sendBlock(for:head:)` a `submission(for:)` v `AppStore`.
**Review z aplikace doopravdy odejde na GitHub** — tlačítko `Odeslat review…` otevře potvrzení
s úplným výpisem payloadu a teprve tam se odesílá. Tlačítko je pojmenované akcí
(`Odeslat APPROVE pro owner/repo#123`) a **není výchozí**, takže Enterem se nic nepošle;
opisování názvu repa ani druhý dialog tam schválně nejsou (viz zadání). Po úspěchu se sheet
zavře, draft zmizí i z disku a konverzace se načte znovu; selhání draft **nechává**.

Model draftu hotový (issue #65) — `ReviewDraft`, `ReviewDraftComment`, `ReviewDraftStore`
a `App/Policy/DraftPolicy.swift`. Rozdělané review přežije restart, novým commitem
zastarává (ale nemaže se) a `Policy` umí říct, na které řádky diffu se vůbec dá komentovat.
**Vrstva bez UI** — skládání draftu je #66, odeslání #67 a #68. Aplikace pořád nic
neposílá: store zapisuje jen na disk.

Taby PR hotové (issue #72) — `PullRequestTab`, `PullRequestTabBar`, `OverviewView`,
`Policy.overview(of:renderedIn:)` a `detailTabs` v `AppStore`. Detail PR se dělí na `Přehled`
(popis PR a konverzace, která se neváže k řádku — review ostatních, komentáře pod PR
a zastaralá vlákna, chronologicky) a `Změněné soubory` (dosavadní obrazovka s diffem). Volba
se drží per PR, výchozí je **`Přehled`** (změna proti zadání). Popis PR se bere z detailu, který
se stejně dotahuje kvůli `headSha`.

Vedle zadání přibylo v témže PR:

- **Vykreslený Markdown** (`App/Markdown/`) — popis, komentáře i těla review se renderují včetně
  HTML od botů (`<details>`, `<!-- … -->`, odkazy). Ruší to rozhodnutí z prvního průchodu #72,
  které Markdown nechávalo jako holý text.
- **Hlášky se přestěhovaly na spodek okna** (`AppNoticesView`) — jako `safeAreaInset` uvnitř
  bočního panelu způsobovaly, že obsah přetekl okno a spodní hrana ho odřízla; tatáž konstrukce
  stojí v crash reportu z 2026-08-03. Viz sekce views výš.

Skládání draftu hotové (issue #66) — `DraftPanel`, `DraftCommentBubbleView`,
`DraftTextEditor`, `DraftActions` a sekce `drafts`/`detailStates` v `AppStore`. Review se dá
poskládat z nálezů (`Převzít do review` v bublině) i z vlastních poznámek (tlačítko na řádku
diffu), tělo a verdikt jsou v tabu `Moje review` a rozdělané review je vidět v řádku seznamu
i v detailu. Co GitHub jako řádkový komentář nepřijme, jde do těla jako permalink — a UI to
říká dopředu. **Nic se přitom neodesílá**: `AppStore` `ReviewPublishing` nezná, odeslání je
#68. Kvůli `headSha` se při výběru řádku dotahuje detail PR (`gh pr view`, cache podle
`updatedAt`) — bez něj by draft nešlo označit za zastaralý ani odeslat.

Vlákna u kódu hotová (issue #64) — `ThreadBubbleView`, `DiffRow.thread`,
`App/Policy/ConversationPolicy.swift` a `conversationStates` v `AppStore`. Vlákno s řádkem
v aktuálním diffu visí jako bublina pod svým řádkem, vyřešené je sbalené s odznakem
`vyřešeno` a moje komentáře mají odznak `já`. Konverzace se načítá **při výběru řádku**
(cache podle `updatedAt`, ruční obnovení), ne pollingem — pro všech N PR by to byla tatáž
N+1 past, kvůli které se netahá ani detail. Zastaralá vlákna a konverzace bez kotvy čekají
na `Overview` v #72.

Odpovídání do vláken hotové (issue #73) — `ThreadRequest`, `ThreadSubmission`, `ThreadOutbound`
a `GhThreadResponse` v `App/Publish/`, `App/Policy/ThreadUpdatePolicy.swift`, `ThreadActions`
a `threadReplies`/`threadStates` v `AppStore`. **Do vlákna se dá odpovědět a jde označit za
vyřešené** — z bubliny u kódu i z `Přehledu`, bez potvrzovacího sheetu (rozhodnutí #73: je to
jedna věta v diskuzi, ne verdikt nad PR). Odeslaná odpověď se ve vlákně objeví bez dalšího
načtení, selhání **nechá text na místě**.

Tím se změnila **tvrdá podmínka č. 1**: protokol má tři vyjmenované metody místo jedné a grep
vypíše čtyři soubory se dvěma volajícími (viz Tvrdé podmínky). Pre-flight u odpovědi `headSha`
neověřuje — odpověď se váže na vlákno, ne na commit.

Tři věci změřené na živém API v sandboxu, které měnily návrh:

- **Odpověď jde GraphQL mutací, ne RESTem ze zadání.** `addPullRequestReviewThreadReply` bere
  `id` vlákna, které v modelu už je; REST by potřeboval `databaseId` komentáře a muselo by se
  rozhodovat, na který komentář ve vlákně se odpovídá.
- **Prázdné tělo GitHub tiše spolkne** — `comment: null`, exit **0**, ve vlákně nic. Proto je
  brána `ThreadRequest.isSendable` a proto se `comment: null` hlásí jako chyba.
- **Odpověď na zavřeném PR GitHub pustí**, aplikace ji ale nepustí. Je to vědomě striktnější:
  mergnutý PR ze seznamu vypadne, takže se k jeho vláknům z okna nedostaneš.

Vedle zadání přibyla **práva viewera** (`viewerCanResolve`/`viewerCanUnresolve` v dotazu
a `ReviewThread.canToggleResolution`): bez nich by okno nabízelo `Vyřešit` i tam, kde na to
reviewer právo nemá, a tlačítko by vždycky selhalo.

**Fáze 2 hotová** — `App/Checkout/`, vrstva bez UI. Bare klon do cache (#8), worktree per
review i serializace souběžných příprav (#9) a eviction cache (#10). Aplikace si tedy umí
připravit pracovní kopii a uklidit po sobě; chybí jen ten, kdo ji použije.

Diff view hotový (issue #18) — `App/Diff/` a `DiffView`. Detail PR ukazuje diff v plné
šířce: soubory pod sebou s ukotvenou hlavičkou, skokové menu, souhrn `N souborů · +X −Y`.
Nálezy se přestěhovaly do spodní lišty, ze které se dá kliknutím odskočit na `file:line`
v diffu.

Rozbalení kontextu hotové (issue #47) — šipkami v mezerách mezi hunky se dotáhne kód,
který v diffu není. Obsah souboru se čte z GitHubu přes ref pull requestu, načítá se až
na kliknutí a `Zobrazit jen diff` sbalí všechno zpátky.

Obarvení kódu hotové (issue #48) — `App/Syntax/`. Vlastní pravidla bez externí závislosti,
paleta Darcula / IntelliJ Light podle režimu.

Bubliny nálezů hotové (issue #19) — nález visí u svého řádku, blokující má červený pruh,
shoda reviewerů odznak `2×`. Nález mimo diff visí u hlavičky souboru a nabídne svůj řádek
dotáhnout — **změna proti zadání**, viz specifikace.

Spodní panel hotový (issue #20) — taby `Nálezy`/`Průběh`, řaditelná tabulka, tažením
měnitelná výška a proklik do diffu se zvýrazněním bubliny.

Konfigurace hotová (issue #23) — `App/Config/`, `config.json` v kořeni cache. Načte se při
startu a při návratu okna do popředí.

Chipy reviewerů a verdikt hotové (issue #21) — horní lišta detailu ukazuje, co který
reviewer udělal, klikem se jeho nálezy schovají z bublin i z tabulky, a vpravo je návrh
verdiktu. **Filtr návrh nemění** — je to pohled, ne tvrzení o PR.

Tab Průběh hotový (issue #22) — časová osa toho, co reviewer dělá, se `session_id`
a kopírováním `claude --resume`. Osa zůstává i po doběhnutí běhu.

Okno nastavení hotové (issue #70) — `App/Views/Settings/`, scéna `Settings` (⌘,). Globální
hodnoty a nastavení per repo se klikají místo editace JSONu; ukládá se odloženě do téhož
souboru a projeví se bez restartu. **Změna proti #23:** `GlobalConfig` má `mode`, tedy
globální výchozí režim review, a `RepositoryConfig.mode` je proto volitelný — viz sekce
`Config` výš. Store se přestěhoval z `ContentView` do `PreflightModel`, protože jinak by
k němu druhá scéna nedosáhla.

Odhad jazyka projektu hotový (issue #24) — `ProjectLanguage` v `App/Models/`,
`Policy.projectLanguages(in:)` a mapa `skillsByLanguage` v konfiguraci. Před spuštěním
skillů se z `git ls-files` pozná, čím je repo psané, a odvozená sada se použije — a když se
od globální liší, taky mu zapíše. Mapa je ve výchozím stavu prázdná, takže dokud si ji
uživatel nevyplní, detekce na sadu nesahá.

Jazyk nálezů hotový (issue #52) — `FindingsLanguage` v `App/Models/`, volba v konfiguraci
globálně i per repo. **Překládá se až po doběhnutí běhu**, prompt o jazyku mlčí — ten se
nesmí měnit kvůli něčemu, co je jen na pohled. Změna neplatí zpětně, uložené nálezy
zůstanou, jak jsou.

Vyvolání skillu opravené (issue #78) — prompt si o skill říká nástrojem `Skill` výslovně
a výchozí id je `code-review:code-review`, protože `code-review` skill není. Do té doby se
skill načetl v 5 ze 14 běhů a model si při neexistujícím jménu domýšlel, co spustit.

Sbalování souborů hotové (issue #59) — klik na hlavičku sbalí a rozbalí diff souboru,
`Sbalit vše` / `Rozbalit vše` je v horní liště a skok ze stromu i z tabulky nálezů sbalený
soubor otevře. V hlavičce je odznak s počtem nálezů, červený u blokujících.

Víceřádkové komentáře hotové (issue #110) — rozsah v `DraftAnchor.start`, `Policy.commentRange`,
`start_line`/`start_side` v payloadu, tažení přes řádky (`RangeDragActions`, `DiffRowFrames`)
a ⇧ klik na roztažení už napsaného komentáře. **Komentovat jde blok řádků, ne jen jeden** —
pravidla jsou změřená proti sandboxu (`docs/github-review-api.md`, bod 8) a dvě z nich se nedají
uhádnout: rozsah smí přeskočit mezeru mezi hunky a pořadí konců GitHub hlídá jen na téže straně.

Pohled vedle sebe hotový (issue #98) — `DiffLayout` v `App/Models/`, `DiffRow.pair`
a `DiffRow.paired(_:)` v `App/Diff/DiffPairing.swift`, `DiffPairView`, přepínač v liště nad
diffem, `global.diffLayout` v konfiguraci a `diffLayoutOverride` v `AppStore`. **Starý a nový
obsah jde postavit proti sobě**, spárovaný po řádcích; všechno, co diff umí pod sebou, umí
i vedle sebe (bubliny, rozbalení kontextu, obarvení, sbalování, skoky). Výchozí pohled je
v nastavení a projeví se bez restartu, přepínač v liště je odchylka do zavření aplikace —
nastavení říká „takhle to chci mít“, přepínač „teď se na to podívám jinak“.

**Fáze 5 hotová (issue #25).** Repo v automatickém režimu se reviewuje samo: po každém
úspěšném tiku se naplánují PR, u kterých se od minula něco změnilo, a session se utratí
teprve tehdy, když se změnil `headSha`. Denní limit (`autoRunsPerDay`, výchozí 20) je
pojistka proti překvapení na účtu a drží se na disku, aby ho neobešel restart.

**Tím je hotový rozsah v1 podle specifikace.**

Zahození nálezů hotové (issue #81) — koš v liště panelu zahodí uložený záznam viditelného
commitu, takže se dá pustit review znovu s jinou sadou skillů. Na repu v automatickém režimu
se pustí samo.

Potvrzení při zavření hotové (issue #94, levná varianta) — dokud běží review, aplikace se
před ukončením zeptá, protože session se zavřením zabije a nahlášené nálezy jsou pryč.
`bin/run.sh` proto ukončuje aplikaci Apple eventem, ne `killall`. Dotažení nálezů
z transcriptu zůstává v #94 pro pád aplikace a zabití zvenčí.

Stálý podpis hotový (issue #61) — `Signing.xcconfig` a `bin/setup-signing.sh`. Aplikace už
není po každém buildu pro macOS jiná aplikace, takže udělená povolení rebuild přežijí.
Vrstva bez UI (build a podpis), viz *Prostředí* výš.

Ikona hotová (issue #83) — `bin/make-icon.swift` a `App/Assets.xcassets/`. Znaky obou
nástrojů rozpůlené diagonálou zleva zdola doprava nahoru: vlevo nahoře Claude, vpravo dole
GitHub. Generuje se **z kódu** z oficiálních značek v `bin/icon-sources/` (obě jsou jediná
SVG cesta, takže si skript vystačí s minimálním překladem `d` na `Path` — žádná závislost).
V repu jsou **dvě barevné varianty**, nasazená je krémový znak na oranžové. Malé velikosti se
kreslí hruběji, ne zmenšením.

Povolení odesílání v nastavení hotové (issue #107) — `allowsPublishing` v `Configuration`
(globálně i per repo), `PublishScope` složený z konfigurace a přepínač v okně nastavení.
**Mění tvrdou podmínku č. 1, bod 6**: zadrátovaný seznam s jediným sandboxem je pryč, brána
je nastavení s **výchozím stavem vypnuto** — dokud si o odesílání někdo výslovně neřekne,
neodejde nikam nic. Sandbox není výjimka v kódu, zapíná se stejným přepínačem. Rozbitá hodnota
v souboru se sráží na zakázané, na obou úrovních.

Stavový řádek hotový (issue #31) — `App/Health/`, `StatusBarView`, `Policy.health(of:from:)`
a `HTTPGetting` s `NetworkReachability` v `App/Environment/`. Na spodku okna je puntík
u GitHubu a u Claude: zelenou a červenou určuje **skutečný provoz** (tik pollingu, doběhlá
session), žlutou incident na komponentách, které aplikace používá, a bez sítě má vlastní
důvod. Hlášky z dosavadního pruhu se do řádku **přestěhovaly** — dvě místa na tytéž hlášky
znamenají, že se jedno z nich přestane plnit. Je to **první `URLSession` v projektu**: do té
doby šel všechen kontakt s vnějším světem přes podprocesy.

Plánované fáze:

1. ~~Seznam PR z `gh` + polling~~ — **hotovo**
2. ~~Checkout cache + worktree~~ — **hotovo**
3. ~~`ReviewRunner` + parsování streamu~~ — **hotovo**
4. ~~UI diffu s bublinami~~ — **hotovo** (#18–#22, #47, #48, #51)
5. ~~Konfigurace a auto režim~~ — **hotovo** (#23, #70, #24, #52, #25)

Tím **končí rozsah v1** podle specifikace. Za ním:

6. **Review na GitHub** (M6) — odesílání review z okna. Tvrdou podmínku č. 1 **už nahradil**
   pravidlem „jediná cesta ven“ (#67) a bránou v nastavení (#107). Hotové: spike #62
   (viz [`docs/github-review-api.md`](docs/github-review-api.md)), model draftu #65,
   publisher #67, skládání draftu #66, potvrzovací sheet #68 a povolení v nastavení #107.
   Zbývá přenesení draftu na nový commit (#69).
7. **Konverzace, komentáře a taby** (M7) — cizí komentáře a vlákna v okně, odpovídání do
   nich a rozvržení jako na GitHubu (taby `Overview` / `Files changed`). Hotové: čtení #63,
   vlákna u kódu #64, taby #72, odpovídání #73, side-by-side diff #98 a víceřádkové komentáře
   #110. **Milník je hotový.**

**M6 a M7 jsou do sebe zaklesnuté a nejdou udělat po sobě.** `#66` a `#68` z M6 čekaly na
`#64` z M7, kdežto `#73` z M7 čekalo na `#67` z M6 — takže se to plánovalo jako jeden blok
o jedenácti issues, ne dva milníky za sebou. Hotové z něj je `#62`, `#63`, `#65`, `#64`,
`#67`, `#66`, `#72`, `#68`, `#73`, `#98` a `#110`; ty dva poslední na konverzaci nestály vůbec.
Zbývá `#69` (přenesení draftu na nový commit).
8. **Notifikace** (M8) — aplikace dá vědět, i když se do ní nikdo nedívá: základ
   s oprávněním a klikem (#88), doběhlé review (#82), nové PR (#85), vypínání po
   událostech (#86) a seskupování (#87).

Pořadí M6–M8 není závazné. M8 na nich nestojí a dá se udělat kdykoli — je to jediný
z těch tří milníků, který **nemění tvrdé podmínky**.

Vedle fází stojí milník **Průběžné**: koš na to, co do žádné z nich nepatří (ikona,
podpis, stavový řádek). Nemá pořadí ani termín a verze se z něj neodvozuje — viz
Pracovní postup.

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
