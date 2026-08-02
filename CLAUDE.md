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

1. **Nikdy nic neposílat na GitHub.** Žádné komentáře, review, approve, labely. Verdikt
   je návrh zobrazený v aplikaci. Aplikace je vůči GitHubu **jen pro čtení**.
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

Sedm modulů. Tři, které sahají do vnějšího světa, jsou za protokolem, aby byly v testech
nahraditelné fake implementací.

| Modul | Zodpovědnost | Vnější svět |
|---|---|---|
| `GitHubGateway` | Vypsat PR ze zdrojů (search dotazů), sloučit a deduplikovat, načíst metadata a syrový diff | `gh` CLI |
| `RepoCheckout` | Bare partial clone do cache, detached worktree na review, uklízení a eviction | `git` |
| `ReviewRunner` | Spustit headless session na skill, parsovat `stream-json`, vytáhnout nálezy z `ReportFindings` | `claude` CLI |
| `ReviewStore` | Persistence — `Codable` v JSON, soubor na `(repo, pr, headSha)` | disk |
| `Policy` | **Čisté funkce, žádné I/O.** Stav řádku podle checkoutu, blokující příznak, návrh verdiktu, detekce shody `2×`, řazení | — |
| `Config` | Globální default + override per repo, tolerantní čtení `config.json` | disk |
| `AppStore` | Drží stav, koordinuje, vynucuje limity paralelismu | — |

Nad tím SwiftUI views: `PRList`, `DiffView`, `FindingsPanel`. Mimo tuhle sedmičku stojí
`App/Diff/` — překlad diffu na model a jeho řádky. Není to modul: v doméně review nemá
diff jinou roli než být vidět.

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
| `PullRequest` | Metadata z `gh`: `id`, titulek, autor, `headSha`, `baseSha`, url, `updatedAt`, stav |
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

Tři věci, které se u nich nemají rozbít:

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
| `DiffRow` | Diff rozbalený na řádky pro vykreslení, včetně bublin nálezů, + `anchor(in:file:line:)` pro skok z nálezu |
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

### `Config` (`App/Config/`)

Nastavení ve dvou úrovních. Nahrazuje konstanty, které byly do #23 roztroušené po celé
aplikaci (skilly, blokující kategorie, interval pollingu, limit souběhu, rozpočet cache).

| Typ | Co je |
|---|---|
| `Configuration` | Celý `config.json`: globální část + `[RepoID: RepositoryConfig]`; `resolved(for:)` a `activeSources` říkají, co doopravdy platí |
| `GlobalConfig` | `sources`, `skills`, `skillsByLanguage`, `blockingCategories`, `mode`, `findingsLanguage`, interval, souběh, rozpočet, model |
| `RepositoryConfig` | Override pro jedno repo: `mode`, `findingsLanguage`, skilly, kategorie — **všechno volitelné** |
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
- **Rozbitá hodnota režimu se sráží na `manual`, ne na globální default.** Chybějící klíč
  je „ber globální“, ale překlep v hodnotě, kterou se někdo pokoušel automat **vypnout**,
  ho nesmí nechat zapnutý. Platí i globálně.
- **Výchozí hodnoty musí odpovídat konstantám, které nahradily** — je na to test, jinak by
  se aplikace po zavedení konfigurace začala chovat jinak. Výchozí `mode` je `manual`:
  zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.

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
| `ReviewStore` | Aktor: `save`, `markCurrent`, `load`, `cleanUp`. Atomický zápis |
| `ReviewRecord` | Obsah jednoho souboru: PR, `headSha`, běhy, `isStale`, `closedAt` |
| `StoredReviewRun` | Jeden běh: skill, `outcome`, session id, nálezy, `droppedFindings`, čas |

Věci, které se u toho nemají rozbít:

- **Store je aktor.** Uložení je čtení, změna a zápis téhož souboru a dva skilly nad jedním
  commitem doběhnou klidně naráz — bez serializace by si výsledky přepsaly.
- **`isStale` je uložené, ne odvozené.** Odvodit by ho šlo jen porovnáním s aktuálním
  `headSha`, jenže ten aplikace z vyhledávání **nedostane** (`gh search prs` ho neumí, viz
  #4). Zjistí ho teprve při dotažení detailu — a to je právě chvíle, kdy se příznak nastaví.
- **Stárnutí umí `save` i `markCurrent`.** `save` ho dělá taky schválně: kdyby to viselo jen
  na `markCurrent`, stačilo by ho jednou zapomenout a nálezy proti neexistujícímu kódu by
  se tvářily jako platné.
- **Zastaralý záznam se nemaže.** Je to historie; UI ho ukazuje jako zastaralý.
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
- **Nezapsaný nález review položí.** Selhání zápisu se nespolkne: ztracený nález by v řádku
  vypadal jako „neběželo“, tedy jako schválený PR s neohlášenou chybou. Ostatní skilly
  přitom doběhnou, ať se nezahodí i to, co se uložit povedlo.

Vzniká z `ToolPaths` po preflightu (`AppStore(toolPaths:)`); **vlastní ho `PreflightModel`
nad scénami**, ne `ContentView`. Okno nastavení je vlastní scéna (`Settings`) a k `@State`
uvnitř hlavního okna by se nedostalo. Testy si podstrčí fake gateway. Smyčka pollingu visí
na `.task` okna, takže zavření okna ji zruší.

| View | Co dělá |
|---|---|
| `ContentView` | `NavigationSplitView`: vlevo seznam, vpravo detail vybraného PR |
| `PullRequestListView` | Seznam, prázdný stav, úvodní loading, tlačítko obnovit (⌘R) |
| `PullRequestRow` | Repo + číslo + `draft` chip, titulek, autor a relativní čas, odznak stavu |
| `PollStatusBanner` | Pruh nad seznamem — **jen když data nejsou čerstvá** |
| `PullRequestDetailView` | Pravý panel: dvouřádková lišta (titulek, review, stav kopie), pod ní diff a nálezy |
| `DiffView` | Diff v plné šířce: souhrn, skokové menu, soubory s ukotvenou hlavičkou, kterou jde sbalit |
| `DiffRowView` | Jeden řádek diffu — hlavička hunku, řádek, rozbalovací řádek nebo poznámka |
| `DiffExpanderView` | Rozbalovací řádek: šipky vlevo v místě čísel a počet skrytých řádků |
| `FindingBubbleView` | Nálezy k jednomu řádku; u nálezu mimo diff nabídne jeho řádek dotáhnout |
| `DiffLineView` | Řádek souboru: dvě čísla, znak změny, obsah obarvený podle jazyka |
| `FindingsPanel` | Spodní panel: taby `Nálezy`/`Průběh`, návrh verdiktu, tabulka s řazením a prokliky do diffu |
| `FindingRow` | Nález převedený na řádek tabulky — texty, identita, blokující příznak |
| `FindingHighlight` | Místo, na které se právě skočilo; bublina na něm chvíli svítí |
| `ReviewTimelineView` | Tab Průběh: sekce na revieweera, události s časem, kopírování `claude --resume`, upozornění na načtený jiný skill |
| `ReviewerChipsView` | Chipy reviewerů: stav a filtr naráz |
| `FileTreeView` | Popover se stromem souborů; odsazení a sbalování si řídí sám |
| `VerdictView` | Návrh verdiktu jako **doporučení**; žádná GitHub akce na něm nevisí |
| `ReviewStateBadge` | Odznak stavu review; texty podle specifikace |

### Okno nastavení (`App/Views/Settings/`)

Scéna `Settings` (⌘, i ozubené kolo v toolbaru přes `openSettings`). Zapisuje do téhož
`config.json`, který jde editovat ručně.

| Typ | Co dělá |
|---|---|
| `SettingsScene` | Obsah scény; dokud neprošel preflight, není store a okno to řekne |
| `SettingsView` | Dvě záložky, patička s cestou a stavem uložení, zámek na rozbitý soubor |
| `SettingsModel` | Rozepsané nastavení: odložený zápis, rozpoznání změny zvenčí |
| `GlobalSettingsView` | Zdroje, výchozí režim a jazyk nálezů, skilly, sady podle jazyka, kategorie, běh |
| `LanguageSkillsEditor` | Mapa „programovací jazyk → sada skillů“; ukazuje jen nastavené jazyky |
| `RepositorySettingsView` | Seznam rep vlevo, režim a override vpravo |
| `StringListEditor`, `SourceListEditor` | Editory seznamů — řetězců a zdrojů |

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
- **V textech se píše „programovací jazyk“, ne jen „jazyk“.** Samotné „jazyk“ se plete
  s jazykem, ve kterém reviewer píše nálezy (#52) — ověřeno tím, že se to spletlo hned
  při prvním zkoušení. Delší popisek je levnější než vysvětlování.
- **Hlavní okno se rozostří jen tehdy, když je nastavení opravdu vepředu.** Okno je
  nemodální, takže kliknutím zpátky do seznamu se v něm dá dál pracovat — a rozostřené
  okno, ve kterém zrovna píšu, je horší než žádný efekt. Rozhoduje `controlActiveState`,
  příznak `isSettingsOpen` žije v `AppStore` (dvě scény si to nemají kde říct jinudy).

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

- **Banner jde přes `safeAreaInset`, ne do `VStack` nad seznamem.** S `VStack`em přestane
  být `List` tím, co sidebar odsazuje od horní lišty, a řádky se schovají pod ni.
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
| `Policy.sorted(_:)`, `Policy.sections(_:)` | Pořadí nálezů pro UI a jejich rozdělení po kategoriích |

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

### `GitHubGateway` (`App/GitHub/`)

Jediná cesta aplikace k GitHubu, celá přes `gh`. Protokol `GitHubGateway` má tři metody
a **schválně žádnou, kterou by šlo něco odeslat** — read-only je vidět z typu.

| Typ | Co dělá |
|---|---|
| `GitHubGateway` | Protokol: `checkAuth()`, `searchPullRequests(query:)`, `fetchDetail(id:)`, `fetchDiff(id:)`, `fetchFile(id:path:)` |
| `GhGateway` | Implementace nad `gh`; `checkAuth()` deleguje na `GhAuthCheck` z `Environment` |
| `GitHubError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `GhSearchQuery` | Rozdělení search dotazu na argumenty `gh` — čistá funkce |
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
  změně targetů nebo build settings.
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
- **Fixtures** — `Tests/Fixtures/`, načítané přes `Fixture.text(_:)`. Cesta se odvozuje
  z `#filePath`, ne z bundlu: Swift Testing nemá `XCTestCase`, od kterého by šel
  `Bundle(for:)` odpíchnout. V `Fixtures/gh/` leží **skutečné** výstupy `gh`, jen
  přeformátované `jq`; berou se z **veřejných** repozitářů (`cli/cli`, `cli/go-gh`,
  `ondrajodas/PRism`), protože titulky firemních PR sem nepatří. Stav, na který se
  skutečná fixture nedá sehnat, se testuje inline JSONem přímo v testu.
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
  a unikátní identita řádků.
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
  test visel místo aby spadl.
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

Plánované fáze:

1. ~~Seznam PR z `gh` + polling~~ — **hotovo**
2. ~~Checkout cache + worktree~~ — **hotovo**
3. ~~`ReviewRunner` + parsování streamu~~ — **hotovo**
4. ~~UI diffu s bublinami~~ — **hotovo** (#18–#22, #47, #48, #51)
5. Konfigurace a auto režim — konfigurace (#23), okno nastavení (#70), odhad jazyka (#24)
   a jazyk nálezů (#52) hotové, zbývá **auto režim (#25)**

Tím končí rozsah v1 podle specifikace. Za ním:

6. **Review na GitHub** (M6) — odesílání review z okna. Tenhle milník **ruší tvrdou
   podmínku č. 1** a nahrazuje ji pravidlem „jediná cesta ven“ (#67). Dokud není hotový,
   podmínka platí beze změny.
7. **Konverzace, komentáře a taby** (M7) — cizí komentáře a vlákna v okně, odpovídání do
   nich a rozvržení jako na GitHubu (taby `Overview` / `Files changed`).

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
