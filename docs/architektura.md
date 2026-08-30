# Architektura — podrobnosti

Referenční část `CLAUDE.md`: co který modul drží a co se u něj nemá rozbít. Přehled modulů
a pravidlo „kam co psát“ zůstávají v [`CLAUDE.md`](../CLAUDE.md) — ty je potřeba znát dřív, než
se něco napíše. Sem se chodí pro podrobnosti k tomu, na čem zrovna pracuješ.

**Proč** jsou rozhodnutí taková, jaká jsou — včetně zamítnutých alternativ — stojí ve
specifikaci: [`docs/superpowers/specs/2026-07-31-prism-design.md`](superpowers/specs/2026-07-31-prism-design.md).

Když tady něco měníš, platí totéž pravidlo jako pro `CLAUDE.md`: **ve stejném commitu jako
změna, které se to týká**.

## Doménové modely (`App/Models/`)

Typy, na kterých staví všechny moduly — proto vlastní složka, ne příslušnost k jednomu
z nich. Žádné I/O, jen data. Všechny jsou `Codable`, `Hashable` a `Sendable`.

| Typ | Co je |
|---|---|
| `RepoID` | `owner/repo` |
| `PRIdentifier` | `owner/repo#číslo` — klíč všeho, co se váže k PR: dedup zdrojů, review stav, uložené nálezy |
| `PullRequest` | Metadata z `gh`: `id`, titulek, autor, `headSha`, `baseSha`, url, `updatedAt`, stav, **popis** (`body`) |
| `PullRequestSummary` | Totéž **bez SHA** — co dá vyhledávání. Viz `App/GitHub/` níž |
| `PullRequestHead` | Hlava PR a **kdy vznikla** (#420) — odpověď dávkového dotazu na `headRefOid`. **Vlastní model vedle `PullRequest`**, ne jeho zúžení: detail je odpověď na „všechno o tomhle PR“ pro jeden pull request, tohle je jedna otázka pro celou frontu naráz. `committedAt == nil` znamená „datum nevíme“, ne dnešek |
| `Source` | Zdroj PR: jméno pro UI + search dotaz. Výchozí dvojice je `Source.reviewRequested` a `Source.mine` (#330) |
| `ReportedFinding` | Nález přesně jak ho poslal reviewer; `FindingVerdict` je `CONFIRMED`/`PLAUSIBLE` |
| `Finding` | `ReportedFinding` + **kdo** ho našel (skill) a **proti čemu** (`headSha`) |
| `FindingKey` | Identita nálezu napříč běhy. Skládá ji **jen** `Policy.key(of:)` |
| `FindingDismissal` | „Tenhle nález neplatí“ — důvod (`invalid`/`irrelevant`) a čas. **Bez volného textu** |
| `RecheckStatus` | Co o nálezu řekla kontrola nových commitů (#150): verdikt (`resolved`/`still-applies`/`unclear`) a věta k němu. **Není nález** a nesmí se za něj vydávat — je to tvrzení *o* nálezu |
| `Handoff` | Razítko předání zadání agentovi (#334): **kdy, proti jaké hlavě a identity předaných položek**. Bydlí u PR, ne u nálezů — předat se dá i zadání bez jediného nálezu |
| `PullRequestState` | `open` / `draft` / `merged` / `closed` |
| `PullRequestLabel` | Štítek na PR: jméno a **šestimístný hex bez `#`** (#392). Barva je **data z repozitáře, ne token palety** — může být libovolná, takže se nedá odvodit z `Palette` ani z kategorie |
| `ReviewerAnswer` | Jak vyžádaný reviewer odpověděl: `approved` / `changesRequested` / `waiting` (#392). **Tři hodnoty, ne dvě** — prostřední je jediná, která něco blokuje |
| `RequestedReviewer` | Kdo na PR stojí a jak odpověděl. Je to **stav, ne událost**: konverzace zná `reviewRequested`/`reviewRequestRemoved`, tedy „to se stalo“ |
| `PullRequestMetadata` | Snímek labelů a reviewerů (#392). **Vlastní vedle `PullRequest`**, protože `fetchDetail` volá i pre-flight publisheru a `latestReviews` nese celá těla review |
| `MetadataState` | `loading` / `loaded` / `failed` u toho snímku. Existuje kvůli jedné věci: **„labely tu nejsou“ se nesmí splést s „labely jsem nezjistil“** — podle prvního se sekce nekreslí, podle druhého se nesmí dát měnit sada, kterou aplikace nezná |
| `ReviewState` | Stav review v řádku seznamu — jedenáct případů, viz níž |
| `InconclusiveReason` | Proč se z doběhlého review **čisto tvrdit nedá** (#383): `droppedFindings`, `noReport`, `unreadCode`. Nese i pořadí přednosti (`byPrecedence`) — v jednom záznamu se ty důvody umí sejít |
| `ReviewVerdict` | Návrh, co s PR udělat: `approve` / `requestChanges`. Jako jediný **není `Codable`** — neukládá se, odvozuje se z uložených nálezů |
| `EffectiveVerdict` | Verdikt, který na draftu **platí**, a jeho původ (`suggested`/`chosen`). Taky **není `Codable`** — počítá se, viz níž |
| `ProjectLanguage` | Čím je repo psané — klíč mapy „jazyk → sada skillů“. **Není to `Syntax.Language`**, viz níž |
| `FindingsLanguage` | Jazyk prózy v nálezech (`cs`/`en`). Ani tohle **není `ProjectLanguage`** |
| `AppearanceMode` | Jaký vzhled má okno mít (#278): `light`, `dark`, `system`. **Volí režim, ne barvy** — ty zůstávají v `Palette`. Nese i ikonu do railu (`railSymbol`) a pořadí cyklu (`next`) |
| `FindingTranslation` | Přeložená próza nálezu. Visí vedle originálu, nepřepisuje ho |
| `Conversation` | Cizí konverzace pod PR: review ostatních, vlákna, komentáře, **události časové osy** (#171) + `viewer` |
| `ConversationPage` | Kus seznamu a kolik ho je celkem — nese **zkrácení** |
| `TimelineEvent` | Co se na PR **stalo** (#171): commit, vyžádané a odebrané review, force push, draft, merge, close, reopen, změna base |
| `EventActor` | Kdo za událostí stojí — jméno, adresa avataru a jestli je to bot |
| `ReviewThread` | Vlákno u řádku diffu: cesta, `line`/`originalLine`, `isResolved`, `isOutdated`, **práva viewera** (`canResolve`/`canUnresolve`), `diffHunk` (#158) |
| `ThreadSnippet` | Úryvek kódu k vláknu: řádky diffu a příznak zkrácení (#158). **Není `Codable`** — počítá se z `diffHunk` |
| `ThreadComment` | Jeden komentář — ve vlákně i pod PR; `replyToID` místo vnořování |
| `SubmittedReview` | Hotové review od někoho jiného; stav je vnořený `SubmittedReview.State` |
| `DiffSide` | `left`/`right` — ke které straně diffu se vlákno nebo komentář váže |
| `QueueSummary` | Souhrn fronty: počet PR, PR s blokujícím nálezem a PR s rozdělaným review (#155) |
| `PullRequestFilter`, `PullRequestFilterOptions`, `PullRequestFilterOption`, `ListEmptyReason` | Zúžení seznamu na repa a autory (#117), od #371 i na **PR s blokujícím nálezem** (`onlyBlocking`, třetí osa — zapíná ji karta `Blokuje` na dashboardu), nabídka hodnot **s počtem PR u každé** (#199) a důvod prázdna — od #331 **jeden typ pro obě sekce se seznamem**, tedy i tři prázdna, která umí jen `Moje PR`. **Není `Codable`** — nepřežije restart |
| `DiffBlock`, `DiffPairBlock` | Souvislý úsek řádků jako jeden text (#157) — kvůli výběru přes víc řádků. **Není `Codable`**, je to věc vykreslení |
| `ReviewDraft` | Rozdělané review: PR, `headSha`, tělo, verdikt, komentáře. Verdikt je vnořený `ReviewDraft.Verdict` |
| `ReviewDraftComment` | Řádkový komentář draftu: kotva (`path` + `DraftAnchor`), tělo, `Origin`. Kotva nese **rozsah** (#110) a komentář **snímek kódu** (#69) |
| `DraftSnapshot` | Text řádků, ke kterým se komentář psal — konec rozsahu a jeho začátek. Prázdný = nevíme |
| `DetailState` | Stav dotažení detailu PR: `loading` / `loaded(PullRequest, updatedAt:)` / `failed`. Je z něj `headSha` pro draft a popis pro `Přehled` |
| `PullRequestTab` | Který tab PR je vidět: `overview` / `filesChanged` / `commits` / `conversation` / `checks` / `findings` / `progress` (#242, `checks` přidalo #215, `commits` #316). **Všech sedm se kreslí vždycky** (#306) — pruh nemá čím měnit počet položek podle dat. `isReviewerOutput` odděluje **výstup našich reviewerů** od toho, co je na PR — z něj se kreslí dělič v pruhu záložek, takže `Kontroly` (#215) i `Commity` (#316) můžou přijít doprostřed levé skupiny, aniž by se posunul. `showsReviewPanel` říká, jestli je v tabu vidět panel s nálezy (#294) — a **s tím prvním se to nesmí slít**: `Kontroly` i `Commity` mají `isReviewerOutput == false` a panel přesto nemají, takže jedna vlastnost pro dvě otázky by posunula dělič. Jako `ReviewVerdict` **není `Codable`** |
| `PullRequestTabBadge` | Odznak u záložky (#242): `count` / `blocking` (červeně) / `live` (puntík). Výčtem, ne strukturou s příznaky — „puntík s počtem“ ani „blokující bez počtu“ význam nemá, takže se nemá dát napsat |
| `ChecksTabState` | Co je v tabu `Kontroly` k vidění (#306): `loading` / `empty` / `list([PullRequestCheck], failure:)` / `failed`. Tab se kreslí i u PR bez CI, takže musí mít odpověď na **každý** stav dat — `empty` znamená „tenhle PR CI nemá“, kdežto `loading` o CI netvrdí nic. Skládá to `Policy.checksTab(checks:failure:)` ze **dvou** map ve store (`checks`, `checkFailures`), jinak by se prázdno slilo s poruchou. Není `Codable` — je to odvozený stav, ne data |
| `CodeText` | Text, který se otevírá v `CodeTextSheet`u (#157, druh od #417): `kind` (`hunk`/`log`) — **nese profil velikosti**, `title`/`slug`/`note` (hlavička složená volajícím), `path` (jazyk na obarvení; **`nil` u logu = jednou barvou**), `code` a `link` na novější text. Není `Codable` — je to obsah jednoho otevření sheetu |
| `JobLog` | Celý log jobu připravený k zobrazení (#417): text **bez ANSI, s timestampy**, plus `lineCount`, `byteCount` a `fetchedAt` — vše **z chvíle stažení**. Počty se nesou s textem schválně (hlavička sheetu je vypisuje, takže by se scan megabajtů dělal při každém překreslení, #224) a `fetchedAt` proto, že `Snímek z HH:MM:SS` u běžícího jobu mluví o chvíli **stažení**, ne o chvíli otevření sheetu |
| `PullRequestCommit` | Jeden commit PR (#316): plné `sha`, celá `message`, `authorName` (z gitu, **vždycky je**), `authorLogin` a `avatarURL` (z účtu, **umí být `nil`**), `committedAt` a `isMerge`. `subject` je první řádka zprávy, `shortSha` sedm znaků. Klíčuje se **celým sha**, ne zkráceným — dvě sha se stejnými sedmi znaky by se v `ForEach`i slila potichu. Počet souborů ani `+X −Y` v něm **nejsou**: seznam z GitHubu je nenese a dotahovat je po commitu je N+1 |
| `CommitsTabState` | Co je v tabu `Commity` k vidění (#316): `loading` / `list([PullRequestCommit], failure:)` / `failed`. **Tři stavy, ne čtyři** — `empty` tu chybí schválně: pull request bez commitů neexistuje, takže prázdná odpověď je **porucha**, ne stav PR. Je to obrácená volba než u `ChecksTabState`, kde prázdno odpověď **je**. Skládá to `Policy.commitsTab(commits:failure:)` ze dvou map ve store. Není `Codable` |
| `CommitDiff` | Diff **jednoho commitu** (#317): `sha` a `content` (`loading` / `loaded(Diff)` / `failed`). Sha je **v hodnotě, ne v klíči** — mapa ve store je klíčovaná pull requestem, takže se v okně drží nejvýš jeden diff commitu na PR. Klíč `(PR, sha)` by u PR se stovkou commitů rostl o každý proklik a byly by to megabajty za obrazovky, které nikdo nemá vidět (tatáž úvaha jako u `expandedChecks`). Návratem do seznamu se **nezahazuje**: je to i paměť na to, kde v seznamu člověk byl |
| `CommitDiffTabState`, `CommitDiffEmpty`, `CommitDiffFacts` | Co je vidět po rozkliknutí commitu (#317): `loading` / `diff(Diff)` / `nothing(CommitDiffEmpty)` / `failed`. **Čtvrtý stav je ten podstatný** — diff, který se stáhl a nic v něm není, není porucha ani načítání, takže mu patří věta, ne prázdná plocha; a je to **měřený** případ, ne teoretický (commity z `git commit --allow-empty` vracejí nula bajtů). `CommitDiffEmpty` nese titulek i větu, protože sloučení a prázdný commit mají každý jiné znění. `CommitDiffFacts` je počet souborů (už vyskloňovaný) a `+X −Y` **ze staženého diffu**, tedy bez volání navíc |
| `ReviewPanelTab` | Co je vidět v panelu vpravo: `findings` / `draft` (#242). Jako `PullRequestTab` **není `Codable`** |
| `CommandPalette` | Jmenný prostor palety ⌘K (#184): `Item` (řádek), `Group` (skupina — **pořadí případů je pořadí v okně**; od #336 pět případů, protože vlastní PR mají svou skupinu **za** cizími), `Target` a `Action` (co se stane po `↵`), `Mark` (co ten řádek je), `Hit` a `Section` (výsledek hledání — `Hit` nese **dva** rozsahy
zvýraznění, jeden nad titulkem a jeden nad podtitulkem), `Jump` (žádost o odscrollování) a `Effect` (co zbývá na okno). **Není `Codable`** — je to obsah jednoho otevření palety. Jmenný prostor proto, že `Palette` v repu už znamená barvy okna |
| `DiffLayout` | Jak se kreslí diff: `unified` (pod sebou) / `split` (vedle sebe). Nastavení **člověka, ne repa** — proto jen v `GlobalConfig` |
| `NotificationEvent` | Co notifikaci vyvolalo: `newPullRequest` / `findings` / `clean` / `failure` / `activity` (#335 — na **mém** PR se ozval někdo jiný). Nese si ji notifikace sama |
| `NotificationSettings` | Co se má hlásit (#86) — hlavní vypínač a pět událostí. Jako `DiffLayout` jen globálně |
| `Release` | Jedno vydání aplikace na GitHubu (#127): tag, název, datum, release notes, odkaz. Jako `ReviewVerdict` **není `Codable`** — na disk nejde |
| `DeliveredNotification` | Poslední **doručená** notifikace (#138) — čas a titulek. Taky **není `Codable`**, drží se v paměti |
| `InterruptedRun` | Značka rozdělaného běhu (#97): klíč běhu, `sessionID` a pracovní strom — z těch dvou se najde transcript |
| `RunUsage` | Co jeden běh stál (#148): cena, trvání a počet kol. Všechno **volitelné** — `nil` je „nevíme“, ne nula |
| `DailySpend` | Součet za dnešek: cena, počet započítaných běhů a **počet těch bez ceny** |

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
  `dismissed(findings:)`, `inconclusive(reason:)`, `failed(detail:)`, `timedOut(findings:)`,
  `interrupted(findings:)`, `stale`.
- **`inconclusive` je třetí stav vedle `clean` a `failed`** (#383) a vznikl proto, že se do té
  doby slíval s **oběma**. Reviewer, který nepřečetl kód a nahlásil prázdný seznam, se kreslil
  jako `čisté`; reviewer, který `ReportFindings` nezavolal vůbec, jako `selhalo` — přitom jeho
  session skončila `success`. Obojí je nepravda o téže věci: **nevíme**. Odznak proto říká, co
  chybí (`kód nepřečten`, `bez hlášení`, `ztracené nálezy`), je **okrový** jako `stale` (výsledek,
  který se nedá použít, ne porucha) a v prázdném tabu nálezů stojí věta i s tím, čím to pustit
  znovu.

  **Okrová jde z palety, ne ze systému** — do #432 to byla výjimka z pravidla
  v `ReviewStateAppearance` („akcent a mint z palety, zbytek škály ze systému“), od #432 je to to
  pravidlo a výjimku má naopak `.secondary`. Opírá se o dvě věci: návrh má
  `.pill.stale { color: var(--stale) }`, takže systémová žlutá byla **odchylka od schváleného
  mockupu**, a odznak je text na vlastní kapsli — systémová `#FFCC00` na ní má ve světlém režimu
  kontrast **1,41** (na ploše 1,51), kdežto token **4,00** a 4,87; v tmavém je to výměna 9,28 →
  6,38. Přebarvilo se s ním i `zastaralé`, kde ta tichá vada ležela od #172. Tatáž úvaha i tentýž
  způsob rozhodnutí jako u `dismissed` v #309 — čitelnost, ne „mají to i tokeny“. Že řádek a chip
  revieweera kreslí **jednu** barvu, drží od #383 tvrzení v `ReviewStateAppearanceTests`, ne
  komentář (nález Copilota na #403).

  Co se tím **nezměnilo**: `failed` zůstává session, která spadla, a nese svůj stderr. Rozdíl
  mezi těmi dvěma je `run.outcome` — ne to, jak prázdný je výsledek.
- **`interrupted` není `timedOut`** (#97). Oba znamenají „nedoběhlo, částečné nálezy zůstaly“,
  ale vedou jinam: timeout říká, že je review pomalé — a limit **jde zvednout v nastavení** na
  stránce `Review a skilly`, globálně i per repo (#320) —, přerušení že spadla aplikace (nedá se
  dělat nic než pustit znovu). A odznak by u přerušeného běhu tvrdil `timeout`, což je nepravda.

  Do #320 byl limit zadrátovaný v kódu, takže ta věta v závorce slibovala něco, co uživatel neměl
  jak udělat. **Konkrétní číslo v UI u výsledku běhu ale nestojí** a je to schválně — viz
  `ReviewRunner` níž.
- **`clean` vzniká jen přes `ReviewState.finished(findingCount:)`.** Jinak se dřív nebo
  později objeví `completed(findings: 0)`, což je totéž vyjádřené hůř.
- **`dismissed` není `clean`** (#113). „Reviewer nic nenašel“ a „našel a já to všechno
  zamítl“ jsou dvě různá tvrzení a v řádku se musí poznat — a `completed(findings: 0)`
  zakazuje pravidlo o řádek výš. Nese proto počet odmítnutých a má vlastní barvu.

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

Nad verdiktem (#114) platí:

- **`EffectiveVerdict` nese hodnotu i původ, protože samotná hodnota nestačí.** `APPROVE`
  z návrhu aplikace a `APPROVE`, který jsem vybral, odejdou na GitHub stejně, ale v okně se
  **musí** dát odlišit — tatáž úvaha jako u `ReviewDraftComment.Origin`. Do #114 stačila hodnota,
  protože jiný původ neexistoval.
- **Návrh se neukládá.** Draft zůstává `verdict == nil`, dokud na verdikt někdo neklikne, a co
  platí, se **počítá** (`Policy.effectiveVerdict`). Kdyby se předvyplněná hodnota zapsala, vznikl
  by draft ze samotného otevření PR — a „draft existuje“ musí znamenat „je co poslat“, protože
  na tom stojí indikátor v řádku i mazání prázdného draftu.
- **`ReviewVerdict` neumí `comment` a nemá.** `jen komentář` je vědomé „nerozhoduju“, tedy pravý
  opak návrhu z nálezů; proto má `ReviewDraft.Verdict` tři případy a návrh dva, a proto se mapuje
  jen jedním směrem (`ReviewVerdict.choice`).

Nad odmítnutím nálezu (#113) platí:

- **Označení bydlí na `ReviewRecord`u, ne na `Finding`u.** Důvod je `ReviewRecord.replace(_:)`:
  opakované review týmž skillem celý `StoredReviewRun` **přepíše**, takže označení uvnitř nálezu
  by zmizelo přesně v okamžiku, kdy se ten samý falešný nález vrátí. Ověřeno dočasně vloženou
  regresí. Vedle toho je `Finding.reported` věta revieweera — můj názor na ni je jiná vrstva.
- **V `Codable` je to volitelné.** Starší soubory klíč nemají a `ReviewRecord` má proto ruční
  `init(from:)`: syntetizovaný sahá na neoptional klíč bez ohledu na výchozí hodnotu, takže by
  celý záznam skončil `keyNotFound` — tedy ztracenými nálezy kvůli poli, které v něm být nemůže.
  Tatáž úvaha jako u `Finding.translation`, jen tam to obstará optional.
- **Klíč skládá jedna funkce**, `Policy.key(of:)`, z `(reviewer, file, line, reported.summary)`.
  Kdyby vznikal na dvou místech, po druhém běhu by se označení přestalo párovat a **tiše
  zmizelo**. Bere se `reported.summary`, ne `summary`: překlad se ukládá druhým zápisem a při
  dalším běhu ho model napíše jinak. Že se `short_summary` přeformuluje, je změřené u #17 —
  proto ne celá hodnota.

  **Od #381 to už není táž identita, jakou se slévají nálezy uvnitř běhu** (do #381 byla).
  `Policy.mergedFindings` se drží **místa**, protože v jednom běhu je z pořadí volání
  `ReportFindings` vidět, co je korekce; klíč odmítnutí páruje **napříč běhy**, kde ta informace
  není, takže by místo samo odmítlo i nález, který jsem nikdy neviděl. Ceny omylů jsou obrácené:
  špatné slití = duplikát v okně (vidět), špatně spárované odmítnutí = schovaný nález (nevidět).
- **Nepřenáší se na nový commit.** Vychází to samo z toho, že mapa leží v souboru daného
  `headSha` (tvrdá podmínka č. 5): nález falešný nad starým kódem nemusí být falešný nad novým.
  Opačné rozhodnutí než u draftu (#69), a schválně — draft je próza, tohle je jeden bit.
- **Dva důvody, ne jeden ani pět, a bez volného textu.** „Reviewer se mýlí“ (`invalid`) a „má
  pravdu, ale sem to nepatří“ (`irrelevant`) vedou jinam: první je vstup pro doladění skillu nebo
  blokující sady, druhý ne. Poznámka, kterou nikdo nečte a nikam se neodesílá, je mrtvá váha,
  která svádí spolehnout se na ni jako na zpětnou vazbu pro skill.
- **Osiřelé označení se neuklízí.** Nález, který v tomhle běhu nepřišel, může přijít v dalším —
  uklidit jeho označení znamená přijít o něj právě tam, kde je nejdražší. Je to pár bajtů.

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

Nad událostmi časové osy (#171) platí:

- **Událost je třetí druh cizího obsahu, ne komentář bez těla.** Review je něčí názor,
  komentář něčí věta, `TimelineEvent` záznam děje („pushnul“, „vyžádal review“, „mergnul“).
  Slít je do `ThreadComment` by znamenalo vymýšlet tělo tomu, kdo nic nenapsal.
- **`totalCount` u `timelineItems` ignoruje `itemTypes`, takže se nesmí použít.** Změřeno na
  `cli/cli#13084`: s filtrem vrací **49** a uzlů dorazí **29** — a stejných 49 vyjde i bez
  filtru. Kdyby se z toho rozdílu počítalo „chybí“, hlásila by aplikace ztrátu dvaceti
  událostí, které nikdy neexistovaly, a hláška o zkrácení by svítila na každém PR. Zbývá
  proto jediný signál, `hasNextPage`, a je na to vlastní konstruktor
  `ConversationPage(items:hasNextPage:)`: dosadí `total` z počtu položek, takže `missing`
  vyjde nula. Je to o polovinu méně, než na čem stojí ostatní stránky, ale pořád ten signál,
  který se v nebezpečném směru („máš všechno“) splést nemůže — a v hlášce „nevešlo se“ je
  proto **„část historie“ bez počtu**.
- **Identita je `id` uzlu z GraphQL, ne obsah.** Bere se jedním fragmentem `... on Node { id }`
  místo deseti polí (ověřeno: 29 z 29 položek ho má a jsou unikátní). Skládat ji z druhu
  a času nejde — na PR běžně stojí za sebou několik shodných párů „vyžádal review / odebral“
  a při shodě na sekundu by je `ForEach` slil do jedné.
- **U commitu je `at` datum commitu, ne pushnutí, a je to vědomé omezení.**
  `PullRequestCommit` nic jiného nenabízí: `pushedDate` GitHub už neplní (změřeno — `null`
  u všech 21 commitů `cli/cli#13084`). Po rebase nebo merge cizí větve proto umí commit sedět
  jinde, než kde ho ukazuje GitHub, kterému pořadí dává samo API.
- **Typ v `itemTypes` bez inline fragmentu dorazí prázdný.** Změřeno: `ClosedEvent` bez
  fragmentu přišel jako `{"__typename": "ClosedEvent"}` a nic víc. Takový uzel a stejně tak
  uzel neznámého druhu se **nekreslí** — prázdný řádek by byl událost, o které nejde říct ani
  co to bylo, ani kdo za ní stojí. Nepočítá se, protože se nemá o co odečítat (bod výš).
- **Chybějící cíl vyžádaného review událost nezahodí.** Změřeno na `cli/cli#13084`, že
  `requestedReviewer` umí přijít `null`; „někdo si vyžádal review“ je pořád informace.
  `User`, `Bot` a `Mannequin` nesou jméno v `login`, `Team` v `name` — slévá se to už při
  mapování, protože v okně je to jedna a tatáž věta.
- **Vyžádání review od sebe sama je vlastnost události, ne textu.** `isSelfDirected` porovnává
  aktéra s cílem, takže z toho ve view nevznikne „ondrajodas vyžádal review od ondrajodas“.
  GitHub to píše jinou větou a bez modelu by se to muselo rozhodovat při vykreslení.
- **Commit bez napojeného účtu má aspoň jméno z commitu.** `commit.author.user` je `null`
  u commitu s e-mailem, který nesedí na účet — pak zbývá `author.name`, bez avataru. Řádek
  bez autora z toho vyjít nesmí.
- **Bot se pozná i jako aktér**, ne jen jako cíl: `github-actions` vyžádá review stejně jako
  člověk, takže `actor { __typename }` je v dotazu kvůli odznaku v okně.

## `App/Diff/`

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
| `WordDiff` | Co se uvnitř přepsané dvojice změnilo (#153): rozsahy na staré a nové straně, práh podobnosti, párování pro oba pohledy. Čistá funkce |
| `DiffState` | Stav načtení per PR: `loading` / `loaded(Diff, updatedAt:)` / `failed` |
| `FileTreeNode` | Soubory diffu jako strom pro navigaci; slévá složky s jediným potomkem |
| `DiffExpander` | Skrytý úsek mimo hunky a kroky, kterými se dá odkrýt |
| `RevealedLines` | Které skryté řádky jsou odkryté; slučuje rozsahy a dělí jimi mezeru |
| `FileExpansion`, `FileExpansionKey` | Rozbalování jednoho souboru: odkryté rozsahy, obsah, načítání, chyba. Klíč je `(PR, cesta, commit)` — `commit: nil` je hlava PR, jinak konkrétní commit (#317). **Ze které verze souboru obsah je, říká klíč, ne hodnota**: týž soubor má v `Změněných souborech` a v diffu commitu jiná čísla řádků, takže sdílený záznam by u staršího commitu odkryl řádky z dnešní hlavy. Tentýž klíč drží **sbalené soubory** (`AppStore.foldedFiles`), takže se ani sbalení mezi těmi dvěma diffy nesdílí |

Věci, které se u toho nemají rozbít:

- **Řádek se zařazuje podle stavu (hlavička / hunk), ne podle prvního znaku.** Odebraný
  řádek začínající `---` je jinak k nerozeznání od hlavičky souboru — a `--` na začátku
  řádku se v kódu i v textu vyskytuje běžně.
- **Nerozpoznaný řádek se počítá** (`unrecognizedLines`) a UI to hlásí. Diff, ze kterého
  kus tiše vypadl, vypadá jako úplný.
- **Zakončení řádků si vybírá cizí repo, ne my** (#295). Diff se proto dělí `TextLines`, ne
  `split(separator: "\n")` — na `CRLF` by z celého diffu byl **jeden** řádek. `CR` se do textu
  řádku nedostane, takže tentýž diff se `CRLF` a s `LF` dá **stejný model**; hlídá to test proti
  skutečné fixture (`gh/pr-diff-crlf.diff`). Podrobnosti u `TextLines` v `App/Support/`.
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

Rozbalení bubliny (#185) — **blokující nález je rozbalený rovnou pod svým řádkem, ostatní jsou
značka na hraně řádku**. Rozhoduje `Policy.disclosure(of:categories:toggled:)`, kreslí
`FindingBubbleView` a stav drží `AppStore.toggledFindings`. Co se u toho nemá rozbít:

- **Rozhoduje se za skupinu, ne za nález.** Bublina slévá nálezy na jednom řádku do jedné
  (odznak `2×`), takže rozbalení po nálezech by znamenalo místo napůl otevřené — a odznak shody
  by mluvil o dvou nálezech, ze kterých je vidět jeden. Stačí proto **jeden** blokující ve
  skupině a rozbalí se celá.
- **Odmítnutá skupina se nerozbaluje nikdy** (`FindingDisclosure.dismissed`), a není to sbalený
  stav bez šipky: odmítnutý nález **je** jeden řádek s důvodem a s `Vrátit`, takže rozbalovat není
  co — a pod značkou by se `Vrátit` schovalo, tedy jediná akce, která u něj zbývá. Odmítnutí
  blokujícího nálezu bublinu naopak **odpřišpendlí**: nález, kterému nevěřím, nemá zabírat řádky.
  Hlídá si to i view (`state`), ať to platí i tam, kde rozbalení řídí volající (tabulka nálezů).
- **Shoda `2×` sama nerozbaluje.** Přišpendlení je o tom, co zastaví merge; shoda o tom, jak moc
  nálezu věřit. Odznak `2×` je proto ve **značce**, aby byl vidět i sbalený.
- **Značka musí říct, co je pod ní.** Kategorie, verdikt, reviewer a náhled textu
  (`shortSummary ?? summary`) — bez toho by se rozbalovala naslepo. A **odznak `mimo diff`**
  u nezakotvené bubliny: věta „řádek v diffu není“ je až v obsahu, takže bez odznaku vypadá
  sbalená bublina u hlavičky souboru jako nález na prvním řádku hunku. Tatáž úvaha jako u odznaku
  zkráceného vlákna.
- **Skok na nález ho rozbalí** (`AppStore.revealFinding`), z panelu, z lišty nad diffem **i z palety
  ⌘K** (#184) — jinak by cíl skoku byl pruh, na kterém není co přečíst. `reveal` přitom **nikdy
  nesbalí**: kdyby jen překlikl, skok na blokující nález by ho zavřel. Skupinu hledá
  `PullRequestDetailView.reveal(bubbleOf:)` podle **nálezu**, kdežto z palety
  `reveal(bubbleAt:line:)` podle **místa** — žádost z palety nese `file:line`, ne nález, a to je
  jednoznačné právě s řádkem (nálezů bez řádku může být v jednom souboru víc). Bez řádku se proto
  nerozbaluje nic a nemusí: kotva pak míří na hlavičku souboru, takže na značce se skok nezastaví.
- **Bublina a karta vlákna leží na téže ploše, a rozlišuje je hrana.** Do #185 měl blokující
  nález červené pozadí; návrh (`.inline-find`) má neutrální plochu a závažnost nese **proužek,
  obrys a puntík** — v diffu to má důvod, protože bublina visí nad zeleným i červeným řádkem
  a třetí barevná plocha vedle nich je kaše. Invariant „nález a cizí komentář nesmí splynout“
  (viz `ThreadBubbleView`) tím **neodpadá**: karta vlákna proužek schválně nemá a její obrys je
  neutrální, kdežto nález má vždycky barevný proužek podle závažnosti (`crit` / `find` /
  tlumený) a u blokujícího i barevný obrys (`Palette.critLine`). Tak je to i v návrhu.
- **Hlavičku nálezu říká buď značka, nebo řádek uvnitř — nikdy obojí a nikdy nic.** U jednoho
  nálezu je kategorie, verdikt a reviewer vlastností celé bubliny, takže je nese značka; jenže
  značka se kreslí jen tam, kde se dá sbalit, a v tabulce nálezů žádná není. Podmínka je proto
  „buď značka, nebo hlavičky“ (`showsEntryHeaders`), ne „jeden nález“ — jinak by v tabulce
  z rozbaleného nálezu zmizel verdikt.
- **Sbalená bublina blok kódu pořád dělí.** Je to řádek seznamu (`DiffRow.finding`) jako dřív,
  jen nižší — takže se struktura bloků #185 nemění a s ní ani výška, o kterou si blok říká.
  Kreslit značku jako **vrstvu** nad blokem (a blok nedělit) by selekci přes celý hunk vrátilo,
  ale znamenalo by to další sloupec v gutteru, který si `DiffTextView` kreslí ručně — a ten jediný
  úzký sloupec už zabírá pilulka komentáře. Zamítnuto, viz specifikace.

Řada akcí pod nálezem (#283) — **malá tlačítka vlevo pod textem, ne modré odkazy přes celou
šířku**. Vzhled drží `MiniButtonStyle` (`.mini` a `.mini.pri` z návrhu), rozvržení `footer(of:)`.
Co se u toho nemá rozbít:

- **Hlavní akci odlišuje plocha, ne vzdálenost.** Do #283 stál mezi převzetím a odmítnutím
  `Spacer`, aby se omylem nekliklo na to druhé. Rozhodnutí je otočené (důvody ve specifikaci) a to
  podstatné z něj zbývá: **plné akcentové tlačítko je v řadě právě jedno** a je první zleva, takže
  cesta myší k převzetí nevede přes odmítnutí.
- **`Spacer` u odmítnutého nálezu zůstává.** `dismissed(_:_:)` není tentýž footer: je to jeden
  řádek se zkráceným textem, takže `Spacer` je to místo, do kterého se text ořezává, a `Vrátit` je
  na řádku jediná akce.
- **Popisek má dvě podoby a nesmí splynout.** `FindingDismissal.Reason.label` je přídavné jméno do
  odznaku a do menu tabulky (`neplatný`), `actionLabel` je tvrzení na tlačítko (`Neplatí`). Jedna
  hodnota pro obojí by v jednom z těch dvou míst mluvila špatně — odznak stavu by řekl akci.
- **Když se řada nevejde, zlomí se, neořeže se.** `ViewThatFits` má tři varianty (řada → dvě řady
  → sloupec). Návrh zalomení nemá, ale nemá ani odpověď na šířku, ve které řada nemůže existovat:
  změřeno renderem, že v úzkém panelu zbývá na řadu 128 bodů a ze tří tlačítek jsou pahýly o jednom
  znaku. Cena je trojnásobek layoutu footeru — u tří tlačítek zanedbatelná, protože bublina není
  na každém řádku diffu.
- **Cíl převzetí a `isAdopted` se počítají jednou za bublinu**, v `footer(of:)`, ne uvnitř tlačítka:
  obojí hledá řádek v hunkách (`isAdopted` si `draftTarget` počítá samo) a `ViewThatFits` staví
  všechny varianty, takže uvnitř by to byl průchod na každou z nich.
- **Prázdný footer se nekreslí, ani jako mezera.** Bublina ke čtení (náhledy, testy skládání řádků,
  `canCompose == false`) by jinak měla pod textem devět bodů prázdna — a prázdno na místě, kde jinde
  něco je, se čte jako chybějící obsah, ne jako „tady nic není“.
- **Věta „GitHub tady řádkový komentář nepřijme“ stojí pod řadou, ne za tlačítkem.** Je to nejdelší
  prvek, takže jako ocas za tlačítkem rozhodovala o zalomení celé řady místo tlačítek — změřeno
  renderem, kde kvůli ní řada padala do sloupce i na širokém okně.
- **Výška tlačítka se skládá z `line-height` a obtažení, ne z toho, co dá font sám.** CSS řádek je
  16,7 bodu, SwiftUI dá pro `size: 11.5` dvanáct, a obtažení v CSS leží **vně** paddingu, kdežto
  SwiftUI ho kreslí `overlay`em dovnitř. Bez obojího vycházelo tlačítko 20 bodů proti 25 v návrhu.
  Změřeno renderem vedle sebe — z kódu se to nepozná.
- **Plochu má bublina, barvu má celé okno** (#298). #283 převedlo na tlačítka jen bublinu, takže
  v tabulce nálezů zbyly `.buttonStyle(.link)`, tedy **systémová modrá** — a v okně dvě různá „klikni
  sem“ naráz. Barvu drží od #298 `AccentLinkButtonStyle` (`Palette.accent`, jako plné `.mini`), tvar
  zůstává různý: plocha v bublině, holý text v tabulce. `.tint(Palette.accent)` z kořene okna na to
  **nestačilo** — `.link` si tint nebere.
- **Akce má akcent, konstatování mint** (#309). V řadě akcí stojí dvě věci, na které se **neklikne**:
  odznak shody `2×` a značka `✓ v mém review`. Do #309 měly barvu akcí (odznak dokonce systémově
  modrou, protože `.tint()` na `Color.accentColor` nezabírá), takže se na ně dalo zkoušet klikat.
  Barvu drží `FindingBadgeAppearance.stateTint`, ať se nedá přebarvit jen na jednom ze čtyř
  vykreslení — tabulka a bublina kreslí obě značky každá po svém.

  **Mint není barva stavů obecně.** Návrh ho má na celé stránce dvakrát, a obojí je právě tady
  (`.pill.mint`, `.frow .acts .in`); běžící review je v něm `.pill.run`, tedy akcent. Dělí to stav
  od akce **tam, kde stojí vedle sebe** — proto ho z okna dostal ještě souhrn fronty ve stavovém
  řádku (sedí pár desítek bodů od akcentového `Připravit`) a odznak `odmítnuto`, ne ale osa
  `Průběhu`, kde žádná akce není.

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
- **Pozadí kreslí dvojice, ne buňka.** Buňka se roztáhne jen na svůj obsah, takže u kratší
  (a hlavně u chybějící) strany by pod ní prosvítalo okno a chybějící řádek by vypadal jako
  mezera. Barvy si přitom bere z `DiffLineView.background(of:)`, aby se přidaný řádek nekreslil
  v jednom pohledu jinak než v druhém. **Od #157 to kreslí blok** (`DiffPairBlockView`), do té
  doby `DiffPairView` — a ten je od #446 smazaný, protože se k němu od #157 nedostala ani jedna
  dvojice (viz *Co z diffu doopravdy dojde ke kreslení*).
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
- **Rozdělení šířky musí být stejné jako v bloku dvojic**
  (`DiffGutterGeometry.rightColumnX(inBlockOfWidth:)` — dvě poloviny plus 1 pt na čáru),
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

Vybírání a kopírování kódu (#157) — z diffu se do #157 nedalo dostat nic, protože tažení přes řádky
vybírá rozsah komentáře a vybírání textu bylo nad diffem vypnuté. Skončilo to **přepisem vykreslení
kódu na `NSTextView`**, protože SwiftUI `Text` selekci přes víc řádků nedá:

- **Řádky se před vykreslením slévají do bloků** (`DiffRow.blocked(_:)`, ve split `blockedPairs(_:)`)
  a blok kreslí jeden `NSTextView`. Blok **končí tam, kde do diffu něco vstoupí** — hlavička hunku,
  rozbalovací řádek, bublina nálezu, cizí vlákno, můj rozdělaný komentář — takže vybírat jde přes
  celý úsek kódu mezi nimi; u většiny řádků je to celý hunk.
- **Blok má strop `DiffBlock.maxLines = 60`** (#223), takže dlouhý úsek se rozdělí i tam, kde do
  diffu nic nevstoupí. Blok je totiž **nejmenší jednotka, kterou umí `LazyVStack` přeskočit** —
  a soubor bez stropu je jeden blok, takže se nepřeskočí nikdy a rozloží se text, který není vidět.
  Číslo je z měření: cena vykreslení bloku je **lineární v jeho délce** (~0,085 ms na řádek), tedy
  60 řádků 7 ms a 2400 řádků 201 ms. Šedesát je zhruba obrazovka kódu a se dvěma viditelnými bloky
  se vejde do rozpočtu na snímek; dvěstě (24 ms na blok) už ne.

  **Rozdělení nešetří celkovou práci** — celý soubor po blocích stojí stejně jako v jednom
  (150–280 ms bez trendu). Šetří ji jedině tou leností, takže z měření celého souboru se přínos
  vyčíst nedá; offscreen render nic nelení.

  **Co to bere:** výběr tažením přes víc než šedesát řádků. Vědomá cena — celý hunk se dá
  zkopírovat z kontextového menu (`Kopírovat hunk`) i vybrat v sheetu s textem, takže na tahu myší
  nezávisí.
- **Slučování je věc vykreslení, ne modelu.** `DiffRow.rows(of:)` vrací řádky jako dosud a slévá je
  `DiffView`. Kdyby se slévalo v modelu, musela by o blocích vědět i kotva skoku na nález a výběr
  vláken — a testy `DiffRow` mluví o řádcích (85 z nich na tom prvním pokusu spadlo).
- **Čísla řádků a znak změny se kreslí mimo text**, do gutteru vlevo. Kdyby byly součástí textu,
  kopírovaly by se s ním — do schránky má jít kód, ne diff.
- **Gutter posouvá původ textu, nezužuje kontejner z obou stran** (#236). Do #236 to byl symetrický
  `textContainerInset`, jenže ten AppKit uplatní na **obě** strany: změřeno, že při šířce view 600
  a gutteru 136 pt vyjde kontejner 328 pt (600 − 2×136) a původ textu na 136. Vpravo se to nepoznalo,
  protože tam nic nekreslíme — jen se kód zalamoval o šířku gutteru dřív (při šířce 600 na 41 znaků
  místo 57) a u pravého okraje zbývalo mrtvé místo. Teď je `textContainerInset.width` nula, odsazení
  drží `textContainerOrigin` (přepsaný) a šířku kontejneru si view nastavuje samo na
  `šířka − gutter`. Změřeno, že to platí pro kreslení i pro klikání; ve split pohledu se nic
  neposunulo, protože tam AppKit dával původ na `inset.width` taky.
- **Šířka pro měření musí být šířka pro kreslení** (#236) — tohle je invariant, ne detail. Blok si
  v `LazyVStack`u říká o výšku sám (`sizeThatFits`), takže když si řekne o menší, než jakou nakreslí,
  položí SwiftUI další řádek (bublinu nálezu, vlákno, hlavičku hunku) do plochy, kterou textové view
  ještě kreslí — a AppKitové view je nad SwiftUI obsahem, takže je vidět **kód přes bublinu**.
  Proto výšku počítá `DiffTextView.height(forWidth:)`, tedy tentýž typ, který drží šířku kontejneru
  při kreslení; složit ji jinde znamená mít dvě pravdy o jedné šířce. Že si všimne až u bubliny, je
  vlastnost slévání do bloků: souvislé řádky jsou jeden blok, takže se přetečení projeví jedině tam,
  kde blok končí.
- **Rámečky řádků ve split pohledu se počítají aritmetikou, ale musí začínat tam, kde začíná text**
  (#236). Sloupec dvojice se nezalamuje, takže je řádek vždycky jeden vizuální a
  `index × výška řádku` je přesné — svislý inset do té výšky ale **nepatří**, patří bloku (nahoře
  a dole, jednou). Dokud ho nesla výška řádku, utíkal každý další řádek o 2 pt: na osmi řádcích 12 pt,
  na šedesátiřádkovém bloku 116 pt — tedy pilulka komentáře sedm řádků pod svým kódem — a pod blokem
  zbývalo tolik prázdna, kolik měl řádků. Že aritmetika sedí na to, co hlásí layout manager, drží
  test; kdyby přestala, patří rámečky vzít z něj.
- **Text bloku vzniká jako jeden řetězec a barvy se do něj dopisují** (#275), ne slepením
  `NSAttributedString`u za každý run. Slepováním se u velkého diffu vyrobilo 16 000 objektů na jedno
  projetí a stálo to **22,2 ms z 86** na 27 blocích; jeden řetězec a `addAttribute` na rozsah dělá
  totéž za **4,5 ms** (celé `show` **86,3 → 61,5 ms**, tentýž stroj tentýž den — absolutní číslo se
  hýbe se zátěží, poměr ne). Ověřeno, že výsledek je `isEqual` se starým na 400 řádcích ve dvou
  paletách, takže se kresba nezměnila — zlevnila.

  **Rozsahy se počítají v UTF-16**, protože v nich měří `NSAttributedString`. Je to ta nová třída
  chyby, kterou přepis přinesl: emoji je jeden `Character`, ale **dva** kódy, takže `count` místo
  `utf16.count` posune obarvení i word-level vrstvu o kus doprava. Hlídají to
  `DiffBlockCompositionTests` a je to ověřené vloženou regresí.

  **Skládání je `static func compose(…)`, tedy čistá funkce nad řádky** — zvlášť od `show(…)`
  schválně: je to ta polovina, kterou jde změřit bez sazby, a bez toho seamu se nedá poznat, kolik
  z ceny projíždění je skládání textu a kolik už `NSLayoutManager`.
- **Sazbu textu se zlevnit nepodařilo a je to změřené, ne odhadnuté** (#275). Z 86 ms na 27 blocích
  je **36 ms** rozvržení v `NSLayoutManager`u a vynucuje si ho `layoutColumns()`, když se ptá na
  přirozenou šířku sloupce pro vodorovný posun (do #422 přes `sizeToFit()`, od #422 přes
  `usedRect` — změřeno v jednom sezení, že je to totéž: **40,1 proti 39,6 ms** na 54 stranách).
  **Vyhodit ten dotaz cenu
  nesmaže, jen ji přesune do kreslení**: `super.draw` rozvržení potřebuje taky a blok, který vjel
  do okna, se kreslí — samotné vykreslení sloupce do bitmapy stojí 108,7 ms na 54 stranách, tedy
  zhruba dvojnásobek toho, co sazba. **Zamítnuto** proto i počítání šířky z kroku monospace písma
  (`nejdelší řádek × advance`): ušetřilo by rozvržení jen u bloků, které se nedokreslí, a u tabulátorů,
  CJK a emoji by šířku podstřelilo, takže by konec dlouhého řádku nešel doscrollovat.
- **Fond kontejnerů by ubral desetinu, ne polovinu** (#275, zamítnuto). `LazyVStack` view nerecykluje,
  takže blok, který vjede do okna, dostane nový `DiffPairBlockContainer` — jenže postavit ho stojí
  0,34 ms (většinu z toho dva `NSScrollView`y), dohromady 11 ms ze 72 na 27 blocích. Znovupoužívat je
  přes `NSViewRepresentable` znamená statický fond a hlídání životního cyklu, což je na jednu sedminu
  ceny moc.
- **Rozvržení gutteru je jeden součet na jednom místě** (`DiffLineView.contentInset(for:)`):
  `[ikonka 18][číslo 52][číslo 52][znak 14]`, ve split jen jeden sloupec čísel. `DiffTextView`
  kreslí ručně na dané `x`, takže rozejít se to smí jen tehdy, když má být kód nakřivo — když
  v tom součtu chyběl `signColumn`, kreslil se znak přes číslo a čísla vycházela uříznutá.
- **Pilulka na komentář a tažení rozsahu zůstávají SwiftUI** — v overlay nad blokem, pozicované
  podle **skutečných rámečků řádků** z layout manageru, ne podle výšky × index: dlouhý řádek se
  zalomí na dva vizuální a čísla by se rozešla s kódem.
- **Ve split pohledu se nezalamuje** a dlouhý kód se posouvá vodorovně. **Ruší to rozhodnutí #98**,
  kde se zalamovalo: se zalamováním by jeden sloupec narostl o vizuální řádek a druhý ne, čímž
  přestane platit, že vlevo a vpravo je tentýž řádek souboru — a to je celý smysl toho pohledu.
  V pohledu pod sebou žádný protějšek není, takže se zalamuje dál.
- **Sloupce split pohledu jsou v clip view** (`NSScrollView`), jinak přetečou do druhé půlky: textové
  view s neomezenou šířkou containeru si roztáhne vlastní rámec podle nejdelšího řádku a `frame`
  z kontejneru ho nezastaví. Rámec se jim musí nastavit **explicitně** (nejdelší řádek, nejméně
  šířka sloupce) — bez toho zůstaly nulové a nešlo v nich ani vybírat, ani nic vidět.
- **Vodorovný pruh je vidět pořád, a proto výška bloku závisí na šířce** (#422). Podrobnosti níž,
  v *Trvalý vodorovný pruh ve split pohledu*: rozhodnutí „pruh je“ i rezervace jeho 17 bodů žije
  v `DiffPairBlockContainer` (jedno místo, pravidlo z #236), styl drží `DiffPairScrollView`
  a šířku dokumentu `DiffTextView.naturalWidth`.
- **A od #428 ten pruh jede s výřezem** — sedí na dolní hraně **viditelné části svého bloku**
  (`y = min(vlastní pás, hrana výřezu − 17)`). Výška bloku se tím nemění, mění se jen
  `frame.origin.y` scrolleru; podrobnosti níž, v *Pruh, který jede s výřezem*.
- **Výběr žije jen v jednom sloupci** a ruší se **při stisknutí**, ne až při puštění: dvě modré
  selekce vedle sebe po celou dobu tažení tvrdí, že je vybrané obojí. `textViewDidChangeSelection`
  na to nestačí (chodí s hotovým výběrem) a zůstává jen jako záloha pro výběr klávesnicí.
- **Kopírování nezakládá komentář.** Skládání textu je čistá funkce nad diffem (`Policy.code(of:)`)
  a menu je na pravém kliknutí, které nic nezakládá. Je na to test, protože „zjednodušit“ to na
  tutéž cestu, jakou jde komentování, je lákavé a tiché.
- **Ve schránce je kód, ne diff:** bez `+`/`-`, bez čísel řádků a bez hlavičky hunku; poznámky
  `git`u se vynechávají. U rozsahu přes obě strany se bere **nová** verze (o té je řeč a zůstane
  po mergi), u rozsahu čistě vlevo naopak odebrané řádky.
- **Rozsah se kopíruje v pořadí souboru.** Zvýraznění drží rozsah jako `Set`, takže hledání konců
  má jedno místo (`Policy.rangeLinesInOrder`) a `rangeLines` je jen jeho množinová podoba — jinak by
  kód přišel do schránky přeházený a nikdo by to nepoznal, dokud by ho někam nevložil.
- **Kopíruje se hunk, ne „celý soubor“** — mezi hunky chybí řádky, takže slepený soubor by tvrdil,
  že je kód souvislý.
- **`CodeTextSheet` zůstal i po zapnutí selekce v diffu.** Blok končí u bubliny, takže hunk
  s komentáři se v diffu naráz vybrat nedá; sheet ho ukáže jako **jeden** text mimo diff, kde jde
  vybrat všechno a ⌘A funguje. Kód se skládá tou samou funkcí jako pro schránku, aby se vybraný
  text nemohl rozejít s `Kopírovat hunk`.
- **Pilulka má vlastní úzký sloupec vlevo od čísel.** Třetí umístění a obě předchozí měla důvod: do
  #110 stála u pravé hrany a působila odděleně od diffu, od #110 sedla **na číslo řádku** a zpola ho
  překryla (doloženo offscreen renderem, že to tak bylo **už před** #157). Cena je 18 pt odsazení
  obsahu u každého řádku — to, co #110 zamítlo.
- **Ikonka není `Button`, ale obrázek s `onTapGesture`.** `Button` si tažení bere pro sebe, takže
  z pilulky nešlo roztáhnout rozsah. Klik a tažení se vylučují samy, protože drag má
  `minimumDistance`; kurzor, nápovědu a accessibility trait je proto potřeba doplnit ručně.
- **Overlay gutteru se skládá po blocích, ne po řádcích** (#252). Do #252 měl každý řádek vlastní
  `Color.clear` s `contentShape`, gestem, `onGeometryChange` a skrytou pilulkou — ve split pohledu
  dvakrát, plus `HStack` se dvěma `Spacer`y na řádek. U šedesátiřádkového bloku je to **120 ploch
  a přes čtyři stovky prvků k umístění**, a líný seznam je při každém přerovnání obsahu umisťuje
  znovu; projíždění splitu o 1 904 rozbalených řádcích proto drželo 100 % CPU
  (`LazySubviewPlacements.placeSubviews` v `sample`u, a z našeho kódu zrovna ty per-řádkové
  closures). Dnes jsou to **dvě plochy na tažení, jedna pilulka a jeden `onGeometryChange`** na
  celý blok; polohy řádků se z rámečků a z polohy bloku **dopočítají** (`DiffGutterGeometry`).
  Změřeno: overlay bloku **3,05 ms → 0,12 ms**. Je to tatáž úvaha jako u šířky (#220) — nevyjednává
  se ani počet prvků, když se dá spočítat.
- **Poloha bloku se drží mimo observable stav** (`DiffBlockPlacement`). Souřadnice v prostoru obsahu
  se při scrollování mění, protože si líný seznam obsah přeměřuje; ve `@State` by z toho byl layout
  bloku při každém posunu — tedy nová podoba téhož problému. Je to tentýž trik jako u `DiffRowFrames`.
- **Pilulka je jedna, ne šedesát prázdných.** Vidět je vždycky nejvýš jedna (řádek pod myší, nebo
  konec taženého rozsahu), a prvek v `ForEach`i vzniká a umisťuje se i s prázdným obsahem —
  „nekreslí se“ není totéž jako „nestojí nic“.
- **Gesto je jedno na sloupec** a řádek, na kterém tažení začalo, se hledá podle `startLocation`.
  Souřadnice jsou v prostoru obsahu, takže se od nich odečte poloha bloku.
- **Hranice polovin je jeden výpočet na jednom místě** (`DiffGutterGeometry.rightColumnX(inBlockOfWidth:)`).
  Pravý sloupec nezačíná v přesné půlce — mezi poloviny sází kontejner **1 pt dělicí čáru**, takže
  `(šířka − 1) / 2 + 1`. Bere si to odsud jak `DiffPairBlockContainer.layout()`, tak plochy na tažení,
  pilulka i rozpoznání strany pod myší; dva výpočty by znamenaly, že pilulka svítí v jedné polovině
  a táhne se ve druhé. Do #252 na tom stál `HStack` se dvěma `Spacer`y a plocha vycházela o půl bodu
  vlevo (nález Copilota na #272). Je to tatáž úvaha jako u šířky pro měření výšky (#236).

Devatenáct pastí AppKitu a SwiftUI, které to stálo — všechny **změřené**, ne přečtené (poslední tři
přidalo #428; číslo v téhle větě bylo do té doby o jedenáct pastí pozadu):

| Past | Jak se projevila |
|---|---|
| **Co se nakreslí po `super.draw`, není vidět** | Čísla a znaky se nekreslily vůbec, ačkoli se kód volal se správnými hodnotami. Doloženo plným obdélníkem, který taky nebyl. Všechno vlastní kreslení musí být **před** `super.draw` |
| `NSAttributedString.draw(at:)` ve **flipped** view kreslí **nad** bod | Text mimo řádek a mimo view. Musí to být `draw(in:)` s rámečkem a zarovnáním z odstavce |
| `setAttributedString` **ruší výběr** | `updateNSView` chodí i při přejezdu myší (mění se, u kterého řádku svítí pilulka), takže výběr zmizel při každém hnutí. Text se proto skládá jen při změně **řádků nebo stylu** (do #393 při změně podpisu s hashem) |
| `updateNSView` chodí i **beze změny hodnoty** | Volá ho každý přepočet geometrie, ne změna bloku — ve ztuhlém okně z #393 tisíckrát za sekundu, bez jediného průchodu tělem. Práci pod tím proto hlídá klíč `DiffBlockDrawing` |
| Chybějící `.foregroundColor` v atributovaném řetězci je **černá**, ne „dědí z okolí“ | Identifikátory a soubory bez rozpoznaného jazyka byly v tmavém režimu černé na tmavém pozadí — kontrast **1,39** na přidaném řádku (#393). Ve SwiftUI `foregroundColor = nil` doopravdy dědí (`DiffLineView` tak kreslí úryvek u vlákna), takže se ta úvaha do #157 přenesla z cesty, kde platila. Barva textu se proto nasazuje **na celý text** a obarvení syntaxe ji přepisuje |
| `bounds` v `updateNSView` je **o průchod pozadu** | SwiftUI nastaví rámec view až po něm, takže první průchod vidí šířku **nula** a ten druhý tu skutečnou (změřeno u #393). Platilo to i předtím — rámečky řádků se z nuly spočítaly stejně —, jen to nebylo z čeho poznat |
| SwiftUI `@ViewBuilder`, který podle stavu vybírá mezi `self` a modifikátorem, **mění strukturu** | `copyMenu` s prázdnou nabídkou zahodil podstrom a postavil nový `NSTextView` — s ním zmizel výběr, jak myš odjela z bloku. Menu se proto připojuje bezpodmínečně |
| `NSCursor.set()` ze SwiftUI ani `addCursorRect` si proti `NSTextView` **neporadí** | Ruka nad pilulkou blikla jen v rohu, kde se to potkalo, nebo vůbec. Jde to jen přes tracking area a `cursorUpdate` — a i tam se musí rozhodovat v `mouseMoved`, protože `cursorUpdate` chodí jen při vstupu do areay |
| `contentShape` **před** `frame` tvaruje nulovou velikost | Gesto tažení nemělo kde začít. Vypadá to jako drobnost v pořadí modifikátorů a je z toho nefunkční gesto |
| `NSTextView` s neomezenou šířkou si **nedopočítá rámec** | Po přesunu do `NSScrollView` zůstal nulový: nic vidět, nic vybrat |
| …ale se `isHorizontallyResizable` si ho **přepočítá sám** — z `usedRect`, který o gutteru neví | Rámec nastavený kontejnerem AppKit **srazil zpátky na šířku plochy** vždycky, když se do ní vešel samotný text: sloupec s dvanácti znaky v šířce 129,5 b kreslí text do 190,4 b a dokument z toho vyšel 129,5. Ve split pohledu tedy **nebylo co rolovat** a konec dlouhého řádku se z okna nedal dostat (#422). `sizeToFit()` je tatáž slepota, jen tišší: vrací nulovou šířku, dokud `maxSize` nikdo nenastaví |
| Legacy vodorovný scroller si bere **výšku plochy**, ne šířku | `contentSize` plochy o 200 b vyjde 183 a clip view zůstane nad pruhem (scroller na `y: 183`). Blok si proto musí o těch 17 b říct sám — a jen když se pruh kreslí (#422) |
| Overlay scroller **nakreslí 0 pixelů**, i když API tvrdí, že je vidět | `isHidden = false`, `alphaValue = 1.0` a `knobProportion = 0.333` má i s `autohidesScrollers = false` — a přesto v nečinném okně není. Z `isHidden` se proto o kresbě nedá usoudit nic; rozhoduje pás výšky, který si plocha vezme (#422) |
| `usedRect(for:)` umí zahrnout **extra line fragment**, a ten je široký jako celý kontejner | Text končící `\n` (tedy každá půlka s prázdným posledním řádkem, což je každá šrafovaná strana dvojice) dal v neomezeném kontejneru šířku **10 000 000** místo 10. Dokument 22 000× širší než okýnko (`knobProportion` 4,49 × 10⁻⁵): knob velikosti vlasu a rolování do prázdna (#422). Kdy se fragment započítá, se řídit nedá — šířka se proto počítá **výčtem fragmentů**, ten ho nevydá. Do výšky naopak patří, je to skutečný řádek |
| `NSClipView.scroll(to:)` **neomezuje** na dokument | Je to zápis počátku, takže se plocha poslušně posune i za obsah (`documentVisibleRect.maxX` 10 249 nad dokumentem 1 058) — v testu z toho vyjde zeleno nad jakoukoli šířkou. Omezení dělá `constrainBoundsRect(_:)`, tedy to, co AppKit sám používá při tažení za knob (#422) |
| `NSScrollView` **je flipped**, `NSClipView` sám o sobě ne | `y` v ploše roste **dolů** a vodorovný scroller stojí na `frame.height − 17` (změřeno: plocha 200 b vysoká má scroller na `y: 183`). Proto se poloha připíchnutého pruhu počítá v souřadnicích **plochy** a ne v okně (#428); `NSClipView.isFlipped` se řídí dokumentem, takže se na něj usuzovat nedá — u SwiftUI `HostingScrollView`u vyjde `true`, nad obyčejným `NSView`em `false` |
| `tile()` vrací scroller na dolní hranu — a zavolá se i z rozvržení nadřazeného view | Připíchnutá poloha se proto musí zapsat **znovu právě tam** (změřeno: z 183 zpátky na 283 po `tile()` i po `layoutSubtreeIfNeeded()` na hostu). Zápis z volajícího by po první změně šířky okna zmizel (#428) |
| Legacy scroller **se nekreslí do `cacheDisplay(in:to:)`** | Nad červeným dokumentem vyjde pod pruhem tatáž barva jako vedle něj, takže se offscreen renderem nedá ověřit ani jeho poloha, ani průhlednost jeho drážky (#428, potvrzuje pozorování z #422). `CGWindowListCreateImage` na macOS 26 není — kresba pruhu tedy patří člověku, testům zůstávají čísla |
| Nastavení `textContainer.size` si AppKit vyloží jako změnu geometrie a **sám zavolá `setFrameSize`** | Měření výšky je dotaz na **budoucí** šířku, takže mu ten zpětný hovor změřenou šířku hned přepsal tou současnou — a měřilo se o jednu šířku pozadu (blok o dvou dlouhých řádcích si při 300 pt řekl o 36 pt a nakreslil 162). Řeší to stráž `isMeasuring` a to, že se šířka kontejneru nastavuje jen při změně (#236) |

**TextKit 1, ne 2.** Geometrie řádků se čte z `NSLayoutManager` (`boundingRect(forGlyphRange:)`) —
podle ní se kreslí pozadí, čísla i pozice pilulek — a TextKit 2 layout manager nemá. Vynutí se tím,
že se textové view vyrobí s ručně složeným `NSTextStorage`/`NSLayoutManager`/`NSTextContainer`.

### Co z diffu doopravdy dojde ke kreslení (#446)

`DiffView` sype do `ForEach` **vždycky** výsledek `DiffRow.blocked(_:)`, resp. `blockedPairs(_:)`
(`DiffView.swift`, a totéž při hledání cíle skoku). Ty slévají **každý** `.line` do `.block`
a **každou** `.pair` do `.pairBlock` — jediné, co je nespojí, je strop `DiffBlock.maxLines`
(#223), a ten dělí blok na dva bloky, ne na řádky. Z toho plyne:

| Případ `DiffRow` | Dojde do `DiffRowView`? |
|---|---|
| `.block`, `.pairBlock` | Ano — takhle se kreslí **všechen kód** |
| `.pair` | **Ne, nikdy.** Je to mezikrok mezi `paired(_:)` a `blockedPairs(_:)` |
| `.line` | **Jen ve split pohledu a jen jako poznámka `git`u** (`\ No newline at end of file`) |

Ta poznámka je jediná výjimka a je to důsledek dvou rozhodnutí, která spolu nesouvisejí:
`DiffRow.paired(_:)` `meta` řádek **nepáruje** (není to obsah souboru, takže nemá stranu — viz
výš), a `blockedPairs(_:)` slévá **jen dvojice**. V pohledu pod sebou výjimka není: tam ji
`blocked(_:)` sebere do bloku jako každý jiný řádek a kreslí se ztlumeně uvnitř textu.

**`DiffPairView` proto u #446 zmizel.** Bylo to sto řádků paralelního kreslení dvojice, na které se
od #157 nedostala ani jedna — a mrtvá cesta svádí k tomu se na ni spolehnout: u #438 se kvůli ní
hledal výkonový problém na špatném místě. Případ `.pair` zůstává ve `switch`i (enum se nezúžil),
ale kreslí se **týmž blokem** jako každá jiná dvojice, ne prázdnem: tichá díra v diffu je horší než
řádek navíc. Ověřeno renderem — obě větve daly bajt po bajtu tentýž PNG.

Spadly s tím dvě věci, které bez `DiffPairView` neměly volajícího:

- **`DiffLineView.side`.** Byla to volba „jsem buňka dvojice“ (jedno číslo místo dvou, pozadí za
  sebe nechává kreslit dvojice). Zbyly z ní tři větve, které nikdo nevyplnil, takže je řádek od
  #446 **jednopodobový** — vždycky přes celou šířku a s oběma čísly.
- **`DiffMissingHatch` jako SwiftUI `Shape`.** Šrafu prázdné protistrany kreslí `DiffTextView`
  v AppKitu; `path(in:)` byl pro tu druhou cestu. Zůstala **jen geometrie** (`segments(in:)`),
  což je stejně to jediné, co se sdílet mělo.

**Konstanty a barvy v `DiffLineView` zůstávají** (`numberColumn`, `iconColumn`, `signColumn`,
`contentInset(for:)`, `signColor(of:)`, `background(of:)`, `rangeTint`, `dragTint`) — jsou to
hodnoty, které si berou bloky, a je to **jediné místo, kde jsou**. Vyčlenit je do vlastního typu je
úklid na potom. Živí čtenáři samotného view jsou dva: **úryvek kódu u vlákna**
(`ThreadSnippetView`, #216) a ta poznámka `git`u z tabulky výš.

Hlídá to `DiffRenderedRowsTests` — nad **skutečnými** diffy z fixtures v obou pohledech, plus
stráž nad zdrojáky, že `DiffRowView` plní jediné místo jediným výrazem.

### Pevný seznam a nasazování bloků (#469)

Diff od #469 **nekreslí `LazyVStack`**. Je to změna proti rozhodnutí z #361, které tehdy znělo
„líný seznam patří tam, kde je seznam neomezený“ — a důvodem je, že se kolo z #361 po opravě osy
konverzace **přestěhovalo do diffu**, ne že by zmizelo.

#### Co se změřilo, než se to rozhodlo

Sonda `DiffShapeProbe` (Debug, okno 1200×800, gesto kolečkem 150 × 40 pt, série se střídají
A/B/A/B podle #274) poměřuje **pět podob téhož místa**: `LazyVStack` se sekcemi (podoba do #469),
pevný `VStack` **s oknem** (podoba od #469), pevný `VStack` **se všemi bloky** (ablace), pevný
`VStack` **bez bloků** (druhá ablace) a totéž **bez ukotvených hlaviček** (třetí).

| řádků | `LazyVStack` | `VStack` **s oknem** | `VStack` se všemi bloky | `VStack` bez bloků | bez bloků a bez ukotvení |
|---|---|---|---|---|---|
| 500 | 0,58 s | **0,73** | 2,96 | 0,17 | 0,20 / 0,21 |
| 6000 | 0,57 / 0,51 | **0,86 / 0,85** | 21,19 / 20,25 | 0,19 | 0,19 |

Čtou se z toho tři věci a všechny tři jsou pro to rozhodnutí podstatné:

1. **Pevný stack sám o sobě je levný a v počtu řádků plochý** — `VStack` bez bloků stojí 0,17 až
   0,20 s bez ohledu na to, jestli je v něm 500 nebo 6000 řádků, tedy **třikrát míň než líný
   seznam**. Prvky v něm nejsou zadarmo, ale nejsou tím, co projíždění stojí.
2. **Cena projíždění roste s počtem nasazených `NSTextView`, ne s délkou seznamu.** Pevný stack se
   všemi bloky vyšel 2,96 s na 20 blocích a 21 s na 108 — a `updateNSView` se při tom gestu
   nevolalo ani jednou (počitadla z #393 zůstala na 20 a 108), takže ta cena **není v našem kódu**.
   Je v tom, že v dokumentu scroll view visí stovka textových views.
3. **Z 1 a 2 plyne řešení**: pevný stack **plus vlastní okno**. `Policy.mountBand(visible:)` řekne,
   ve kterém pásu obsahu má blok živý `NSTextView`; mimo pás zbyde `Color.clear` s naposledy
   změřenou výškou (`DiffBlockSlot`). Nasazených bloků je pak **6 bez ohledu na velikost diffu**
   (změřeno u 500, 6 000, 20 000 i 50 000 řádků), kdežto bez okna jich je 20 / 108 / 340 / 840.

#### Strukturální doklad, ne „po opravě to nehořelo“

Kolo se za čtrnáct kol #361 nepodařilo vyrobit na povel, takže „nehoří“ nedokazuje nic. Doloženo
je proto totéž, čím to doložilo #361 u osy: **co je v evaluačním zásobníku AttributeGraphu, když se
`ForEach` ptá na identitu řádku** (`DiffShapeProbe.graphUnderTheRow`, vzorky přes `GraphProbe`):

| podoba | dotazů na identitu | vzorků | z toho s `LazySubview*` | kořen | vrchol |
|---|---|---|---|---|---|
| `LazyVStack` | 478 | 2 | **2** | `LazySubviewPrefetcher<LazyVStackLayout>` | `LazySubviewPlacements<LazyVStackLayout>` |
| `VStack` s oknem | 371 | 1 | **0** | `ScrollGeometryProvider` | `DynamicContainerInfo<DynamicLayoutViewAdaptor>` |

`LazySubviewPlacements` je **jmenovitě ten atribut**, jehož `placeSubviews` drželo 25 % vzorků
hlavního vlákna v obou `sample`ech z hořícího okna 27. 8. Pod pevným stackem nemá jak vzniknout,
takže se ta vazba nemá kde utvořit. **Netvrdí to, že záchvat nepřijde** — tvrdí to, že tuhle jednu
cestu k němu už nikdo neujde.

#### Co to stojí: první rozvržení

| řádků | `LazyVStack` | `VStack` s oknem | `VStack` se všemi bloky |
|---|---|---|---|
| 500 | 3–5 ms | **10 ms** | 20 ms |
| 6000 | 3–4 | **50–59** | 144–160 |
| 20 000 | 6–10 | **206–304** | 623–933 |
| 50 000 | 16–28 | **983–1534** | 3098–5338 |

Je to **vědomá cena a je vidět**: u dvacetitisícového diffu čtvrt sekundy, u padesátitisícového
sekunda a půl (Debug). Platí se za to, že blok, který se ještě nikdy nekreslil, se **nasadí** —
`Policy.isBlockMounted(nil, band:)` je `true`, protože o jeho výšce se nedá nic tvrdit, a prázdné
místo je horší odpověď než blok navíc.

**Odhad výšky je zamítnutá varianta.** Vypadá lákavě (řádky × výška řádku), ale platil by se tím,
že by obsah pod prstem měnil výšku pokaždé, když se blok poprvé nasadí — a skok na nález by mířil
vedle. Přesná výška od začátku je to, co drží `⌥↓` i kotvy z `DiffRow.blockIDs`.

**Zbytek chyby je změřený a je malý**: výška obsahu u 2000řádkového diffu vyšla 46 065 pt na vršku
a 46 241 pt po projetí, tedy **0,4 % korekce**, která konverguje (blok změřený na provizorní šířce
se při dalším nasazení dorovná). Pro srovnání, `LazyVStack` u 6000řádkového diffu hlásil 99 687,
resp. 101 736 pt tam, kde pevný stack **změří** 112 507 — tedy **12 % vedle**, a to se nedorovná
nikdy, protože je to odhad ze své podstaty. Posuvník tedy od #469 nelže víc, ale míň.

Skok na nález má kvůli té zbývající korekci **druhý `scrollTo` o průchod později** (`DiffView`,
`task(id: scrollTarget)`): cíl mohl být do té chvíle jen rezervovanou výškou, a jak se nasadí,
posune se to pod ním. Je to **zmírnění, ne záruka** — kolik průchodů to sedne, se řídit nedá
a čekat časovačem je zakázaná třída (#350).

#### Kdo čte co: `DiffViewport`

Dvě vlastnosti, a je to **výkonové rozhodnutí**, ne členění pro pořádek. `@Observable` sleduje po
vlastnostech:

- **`band`** se mění **jednou za projetý výřez** (je kvantovaný) a čtou ho **všechny** sloty bloků.
  Kdyby se počítal z okamžité polohy, překládalo by se při každém snímku tělo každého bloku.
- **`top`** se mění při **každém** otočení kolečka a čte ho **jediné view** — `DiffPinnedHeader`.
  Cena je tím ohraničená na jednu malou hlavičku; kdyby to čtení bylo v těle `DiffView`, skládaly
  by se při každém snímku řádky všech souborů (`DiffRow.rows(of:)`).

**Rámečky bloků se čtou v souřadnicích obsahu, ne výřezu**, a je to tatáž úvaha: hodnota
v souřadnicích obsahu se scrollováním **nemění**, takže se za to čtení neplatí. První podoba se
ptala každého bloku a každé hlavičky na rámeček ve **výřezu** — tedy na hodnotu, která se mění — a
stálo to 3,5 s CPU na 6000 řádcích proti 0,19 s u seznamu bez těch dotazů. To je ta zamítnutá
varianta a je zamítnutá měřením.

#### Ukotvená hlavička souboru

`LazyVStack(pinnedViews: [.sectionHeaders])` byl jediný, kdo v SwiftUI ukotvené hlavičky umí.
**Zahodit je nešlo** — v návrhu je `.fhead { position: sticky; top: 0 }`, takže je to vzhled, ne
detail implementace. Kreslí se proto **jedna hlavička přes výřez** (`DiffPinnedHeader` v overlay nad
scroll view), o které rozhoduje `Policy.pinnedFileHeader(files:top:headerHeight:)`: který soubor
právě protíná horní hranu a o kolik se má hlavička vysunout, aby ji hlavička dalšího souboru
**vytlačila** místo aby ji překryla.

**Posouvat každou hlavičku podle jejího vlastního rámečku ve výřezu je zamítnutá varianta**, taky
měřením: stálo to 0,83 s CPU na 24 souborech (ablace `VStack bez bloků` se ukotvením a bez něj —
0,99 s proti 0,19 s), protože se při každém snímku počítal rámeček **každého** souboru.
`visualEffect` by ten posun udělal zadarmo, ale hit testing ho nesleduje, takže by se na ukotvenou
hlavičku nedalo kliknout — a ona je celá tlačítko (sbalení souboru).

Rozsahy souborů plní `DiffFileSection` do krabice **mimo observable stav** (`DiffFileExtents`,
tatáž konstrukce jako `DiffRowFrames`), v souřadnicích obsahu, takže se scrollováním nemění.
Krabice se **klíčuje `subject`em**: `@State` detailu přetéká mezi pull requesty, takže bez toho by
se v ní vrstvily rozsahy každého prohlédnutého PR. A `ordered(of:)` vydá rozsahy **jedině tehdy,
když jsou změřené všechny** — díra uprostřed by znamenala, že se u horní hrany drží hlavička
souboru, který je někde jinde.

#### Co zůstalo v aplikaci líné

`grep -rn 'LazyVStack\|LazyVGrid' App` vypíše po #469 osm míst: strom souborů, tabulka nálezů, fakta
o PR, průběh review, dění, seznam commitů, panel a živý výpis kroků. **Všechna mají strop** (dění
200 položek, výpis kroků taky, commity a soubory jsou z jednoho PR, nálezy z jednoho běhu), takže
u nich platí pravidlo z #361 nezměněné. Že by se kolo utvořilo tam, **vyloučené není** — je to
vlastnost vzoru, ne délky seznamu —, ale ani jednou se to nestalo a cena pevného stacku by tam byla
zbytečná.

### Trvalý vodorovný pruh ve split pohledu (#422)

Ve splitu se nezalamuje, takže dlouhý řádek odjede za okraj sloupce — a do #422 se to z okna
nedalo poznat: plochy měly `scrollerStyle = .overlay`, který se kreslí jen při rolování.
Zakresleno v **sekci 29** návrhu. Změna má **tři části** a každá je jinde:

| Kde | Co drží |
|---|---|
| `DiffPairScrollView` | Styl `.legacy`, který jde vzít jedině přiřazením — a setter ho vede zpátky, takže o pruh nepřijdeme ani přepnutím systémové volby *Zobrazovat posuvníky*. Drží i `scrollerHeight` (pás z AppKitu, 17 b) |
| `DiffPairBlockContainer` | **Jestli se pruh kreslí** (`showsScroller(forWidth:)`) a **rezervace jeho výšky** (`height(forWidth:)`) — tedy obojí na jednom místě |
| `DiffTextView.naturalWidth` | Jak široký musí být dokument sloupce, aby byl vidět celý nejdelší řádek: `gutterWidth` plus nejdelší **vysázený fragment téhle půlky** (ne `usedRect(for:)` na celý kontejner, viz níž) |

**Výška bloku od #422 závisí na šířce, a to je ta past.** Do té doby na ní nezáleželo (nezalamuje
se), takže `height(forWidth:)` parametr ignorovala. Jak se pruh objevuje podle toho, jestli je co
skrývat, začíná záležet — a rezervovat těch 17 bodů **musí totéž místo, které rozhoduje, že pruh
je** (pravidlo z #236). Dvě místa znamenají dvě pravdy o jedné výšce: buď poslední řádek zmizí pod
pruhem, nebo pod blokem zbyde 17 bodů prázdna. Ověřeno vloženou regresí — bez rezervace padne
**108 tvrzení** ze `DiffPairScrollerTests`, mezi nimi `rows 98 <= 83`, tedy přesně to přetečení.

**Kritérium je totéž, podle kterého se rozhoduje AppKit** (autohide): dokument je široký
`max(naturalWidth, plocha)`, takže se pruh objeví právě tehdy, když `naturalWidth > šířka
poloviny`. Netvrdí se to druhým výpočtem — testy laid out kontejner a čtou z `NSScrollView`, jestli
scroller ukázal a kolik výšky si vzal, a jde se **přes pásmo šířek**.

**Pruh je na blok, ne na soubor**, a je to dnešní architektura přiznaná: rolovací plocha **je**
blok. Sdílený posun na celý soubor by se mýlil o **44 znaků** (medián rozdílu nejdelšího řádku mezi
bloky téhož souboru, p90 132; měřeno na 352 souborech ze 48 PR) a stál by dva pozorovatele na blok
plus přerolování všech viditelných bloků — tedy to násobení prvků, které diff už dvakrát položilo
(#252). Typický soubor má **dva** bloky (medián; p99 22).

**Prázdný pás na druhé půlce vzniká sám.** Rezervace se počítá na blok, takže když pruh potřebuje
jen jedna strana, je druhá plocha o 17 bodů vyšší a řádky v obou začínají na stejném `y` —
`NSScrollView` si pás bere zespodu a clip view zůstává nad ním. Prázdná strana dvojice se přitom
nesmí propadnout: řádky drží `DiffLine.blank`, ne minimální výška, takže rámečky obou půlek vyjdou
na bod stejné (je to na to test).

**Rolování se u toho muselo spravit, ne jen zviditelnit** — a je to změna proti tomu, co stálo
v zadání issue (tam se předpokládalo, že se rolovat dá „odjakživa“). Změřeno, že nedalo:
`isHorizontallyResizable` nechal AppKit přepočítat šířku dokumentu z `usedRect` bez gutteru a srazit
ji na šířku plochy, takže **dokument nebyl nikdy širší než okýnko**. S autohide by z toho vyšel
pruh, který se nezobrazí nikdy. Šířku proto určuje sloupec (`naturalWidth`) a self-sizing je vypnuté;
je to tatáž úvaha jako u výšky v #236 — kdo kreslí, ten měří.

**Šířka je vlastní každé půlce, a musí se počítat po řádcích** (#422, oprava nahlášená po prvním
kole jako „moc velký posuvník, který jede do prázdného místa, kde nic není“). První verze brala
`usedRect(for: textContainer)`, tedy jedno číslo za celý kontejner — a to umí zahrnout **extra line
fragment**: řádek za posledním `\n`, který AppKit vysází vždycky, když text končí zalomením. Tak
končí každá půlka, jejíž **poslední řádek je prázdný**, a prázdná je každá šrafovaná (chybějící)
strana dvojice. Kontejner sloupce je přitom neomezeně široký, takže má ten fragment rámec
**10 000 000** bodů:

| půlka | `usedRect(for:)` | po řádcích |
|---|---|---|
| tři obyčejné řádky (`abc`, …) | 34,1 | 34,1 |
| **tři šrafované řádky** | **10 000 000** | 10,0 |
| šrafování a mezi ním jeden dlouhý řádek | **10 000 000** | 508,2 |

Z toho vycházel dokument 10 000 084 bodů široký proti okýnku 449,5 — tedy plocha, která tvrdí
22 000× víc obsahu, než kolik ho je: `knobProportion` **4,49 × 10⁻⁵** (po opravě 0,0, protože
šrafovaná půlka pruh nedostane vůbec; půlka s dlouhými řádky má 0,471 před i po). Odsud ten vlas
u levého okraje a rolování do prázdna.
**Kdy se ten fragment do `usedRect` započítá, se řídit nedá** (změřeno): nad samotným sloupcem
vyšla 34,1, nad tímtéž sloupcem uvnitř `DiffPairBlockContainer` 10 000 000, a minimální recept je
zneplatnit layout po jeho vysázení. Odsud to „někdy“ v hlášení.
`enumerateLineFragments(forGlyphRange:)` extra fragment **nevydá vůbec**, takže se nemá jak vloudit;
u půlky, kde nic není, vyjde nula a pruh se nekreslí. Nad blokem s neprázdným posledním řádkem
vychází **týž počet jako dřív**, takže geometrie odsouhlasená u #422 (pás 17 b, knob 11 b, odsazení
3 b) se nemění.

**Výška zůstává na `usedRect(for:)` schválně.** Tam je extra fragment **skutečný řádek** bloku
(prázdný řádek souboru se kreslí i s číslem), takže se do výšky započítat má; a je to navíc jen
zalamovací pohled — `DiffPairBlockContainer.height(forWidth:)` počítá z `height(ofRows:)`, kde se
layout manageru neptá vůbec. Změřeno u toho jedno **cizí** drobné rozejití, které s #422 nesouvisí
a **nechává se**: zalamovací blok, jehož poslední řádek je prázdný, vyjde o **2 body** nižší než
`height(ofRows:)`, protože extra fragment má výšku systémového písma (14), ne toho monospace (16).

**Cena:** výčet fragmentů je 0,005 ms na šedesátiřádkovém bloku proti 0,0001 ms za `usedRect`.
Pamatuje se (`rememberedTextWidth`), takže se platí jednou na obsah — a proti sazbě, kterou si
`ensureLayout` na tomtéž místě vynutí, je to nic.

**Zapamatovaná šířka musí padnout se změnou obsahu**, protože kontejnery dvojice recykluje líný
seznam: tentýž `DiffPairBlockContainer` dostane jiný blok. Zahazuje ji `DiffTextView.show(…)`, tedy
jediné místo, kde se text mění. Ověřeno vloženou regresí — bez toho zdědí krátký blok šířku dlouhého
(1701,2 místo 102,0) a pruh mu zůstane i tam, kde nemá co skrývat.

**Co se nemění:** čísla řádků odjedou s textem (kreslí je totéž view jako kód, na `x: 0` ve svých
souřadnicích) — nakreslené je to tak i v návrhu (poznámka 45) a přišpendlit gutter znamená vytáhnout
ho z rolovací plochy, tedy jiný zákres. A **pohled pod sebou zůstává zalamovací**: pruh by v něm byl
17 bodů na blok za nic, protože zalomený řádek se přečte celý bez rolování. Je na to test, protože
je to volba ze tří možností, ne opomenutí.

### Pruh, který jede s výřezem (#428)

U dlouhého bloku je jeho dolní hrana pod dolní hranou okna, takže pruh z #422 nebyl vidět zrovna
tam, kde je nejvíc potřeba — přeteče **9,6 %** bloků (33 ze 343 z 48 PR) a jejich pás leží pod hranou
okna o **229 b** (medián, p90 533). Zakresleno v **sekci 30** návrhu. Pravidlo je jedna věta:

```
y = min(vlastní pás, hrana výřezu − pás)
```

**Jedna spojitá funkce posunu, ne dva stavy.** Dokud blok hranu výřezu přesahuje, vyhrává druhý člen
a poloha pruhu **v okně** se rolováním nemění; jak se pás bloku do výřezu dostane, vyhraje první člen
a pruh jde dál rychlostí kódu. Přechod není animace — vyjde z toho minima sám. **Pruh přitom nikdy
neopustí svůj blok**, takže na hraně výřezu stojí nejvýš jeden (ten, který k ní dosahuje) a otázka
„komu patří“ se rozpouští, nerozhoduje.

| Kde | Co drží |
|---|---|
| `Policy.pinnedScrollerY(ofBlock:in:band:rowHeight:)` | **Celé rozhodnutí** jako čistá funkce: minimum, heuristika tří řádků a nic jiného. Vrací `y` **v souřadnicích bloku** (nula je horní hrana, `y` roste dolů) |
| `DiffPairBlockContainer.viewDidMoveToWindow()` | Pozorovatel — `boundsDidChange` **vnějšího** clip view, jeden na viditelný blok. Odhlašuje se bezpodmínečně, protože líný seznam kontejnery recykluje |
| `DiffPairBlockContainer.pinnedScrollerY()` | Převod souřadnic a `nil` ve dvou případech: blok **mimo rolovací plochu** a blok **bez pruhu** (`showsScroller(forWidth:)` je `false` — bez pruhu není pás rezervovaný, takže by skrytý scroller sedl na poslední řádek kódu) |
| `DiffPairScrollView.pinnedScrollerY` | **Jediné místo, které rámec scrolleru zapisuje** — a zapisuje ho jen při změně. Znovu se uplatní v `tile()` |

**Souřadnice se počítají v ploše sloupce, a to je celý trik.** `NSScrollView` **je flipped**
(změřeno) a plocha je vysoká jako celý blok, takže její `bounds` **je** rámec bloku s nulou na horní
hraně — přesně soustava, ve které se dá výsledek zapsat scrolleru do `frame.origin.y`. Výřez do ní
srovná `convert(_:from:)`, ať je vnější clip view flipped, nebo ne. Prostor obsahu diffu
(`DiffView.contentSpace`) by k témuž musel jít přes `DiffBlockPlacement`, tedy přes SwiftUI —
zbytečná druhá cesta k údaji, který AppKit má.

**Výška bloku se posunem nemění, a to je podmínka.** Rezervace 17 b zůstává tam, kde ji #422
nechalo (`height(forWidth:)`); připíchnutím se mění **jen** `frame.origin.y` scrolleru. Měnit výšku
znamená přerovnat líný seznam při každém snímku. Alternativa „ubrat výřezu 17 b, dokud dlouhý blok
sahá na hranu“ je zamítnutá v zákresu: inset, který přichází a odchází, hýbe veškerým kódem pod
kurzorem.

**Poloha nesmí do observable stavu** — tatáž past jako u polohy bloku (#252) a u hoveru (#358).
`pinnedScrollerY` je proto obyčejná vlastnost `NSView`u, kterou nikdo nesleduje, a obsluha
pozorovatele je **aritmetika a dva zápisy rámců**: nula zápisů do stavu, nula přerolování, nula
zneplatnění grafu. Změřeno na scéně s `ScrollView`em: dvacet posunů po deseti bodech nepřidalo ani
jeden průchod tělem, ani jednu aktualizaci `updateNSView` a ani jedno nasazení bloku.

**Jediná heuristika je pojmenovaná:** pod **třemi** viditelnými řádky bloku se pruh nepřišpendlí
a zůstane ve svém pásu (tedy mimo obrazovku) — jinak by zakryl polovinu toho mála, co z bloku vidět
je. Tři je odhad, ne měření, a je to jediné číslo v téhle změně bez měřidla. Padá do ní i blok, který
z výřezu vyjel celý (viditelná výška nula), takže se na to nemusí ptát druhá podmínka.

**Připíchnutý pruh zakrývá 17 b = 1,06 řádku** — prakticky ten řádek, který hrana okna stejně řeže.
Podklad má **neprůhledný být**, a kreslí si ho legacy scroller sám: vlastní vrstva pod pruhem by byl
prvek navíc, a těch je v diffu nula (#252). Ověřit to jde jedině okem — legacy scroller se do
bitmapy z `cacheDisplay(in:to:)` nekreslí vůbec (změřeno, viz tabulka pastí).

**Autohide zůstává beze změny** (#422): blok, který se do šířky vejde, pruh nemá. Poskakující prvek
z toho nevzniká právě proto, že pruh **nemění vlastníka** — při přejezdu z bloku s pruhem na blok bez
pruhu nic nezmizí na místě: pruh odjede nahoru se svým blokem a další přijede zdola takový, jaký je.
Na hraně okna proto někdy nic není a je to správná odpověď, ne chybějící prvek.

### Rámečky řádků jedním průchodem (#476)

`lineFrames()` vydává rámeček každého řádku bloku — z nich je geometrie gutteru (#252), poloha
pilulky na komentář a kotvy pro ⇧ klik (`DiffRowFrames`). Do #476 se pro **každý** řádek volalo
`boundingRect(forGlyphRange:in:)`, a to je u `NSLayoutManager` drahá cesta: ve vzorku z přepínání
tabů drželo `lineFrames()` **697 vzorků z 1 519**, které stál celý `updateNSView` bloku, a uvnitř
z toho `_rectArrayForRange` → `_insertionPointHelperForCharacterAtIndex` **653**.

Od #476 se fragmenty vyberou **naráz** (`enumerateLineFragments`) a přiřadí se řádkům podle pozice
znaku — řádky se dělí zalomením, takže každý fragment patří právě jednomu řádku a zalomený řádek si
své fragmenty sjednotí. Přepnutí tabu z toho vyšlo **462 → 433 ms** u 2000řádkového a
**225 → 196 ms** u 500řádkového diffu.

**Dvě věci, které se u toho musely trefit přesně, a obě chytil test** (`DiffLineFramesTests`):

- `usedRect` fragmentu **obsahuje `lineFragmentPadding`**, kdežto `boundingRect` vrací rámeček
  samotných glyfů — bez odečtení vyšly rámečky o **5 bodů** vedle;
- u **zalomeného** řádku vrací `boundingRect` šířku **celého kontejneru**, kdežto sjednocení
  použitých částí jen tu nejdelší — rozdíl 70–78 bodů. Řádek s víc fragmenty proto bere vodorovný
  rozměr ze sjednocení **fragmentů**, ne použitých částí.

Obojí by byla **tichá** vada: pilulka i kotva by seděly vedle a nic by se neohlásilo. Referencí
v testu je proto `frame(ofLine:)`, tedy ta stará cesta — v kódu zůstává pro jednotlivé dotazy
a jako záchrana pro řádek, na který se v průchodu nedostane.

### Stráž v `updateNSView` (#393)

**`updateNSView` se volá při každém přepočtu geometrie bloku, ne při jeho změně.** Ve ztuhlém okně
z #393 na něj padlo **1 172 z 21 240** vzorků hlavního vlákna — a v tom kole se nepřeložilo ani
jedno tělo, takže se ta práce dělala pořád znovu nad **týmž** blokem:

| co se v každém průchodu platilo | vzorků |
|---|---|
| `DiffPairBlockContainer.show(…)` (nasazení do sloupců) | 724 |
| z toho `layoutColumns()` včetně `sizeToFit()` na oba sloupce | 279 |
| z toho `left.singleLineHeight` (dotaz layout manageru) | 126 |
| z toho `missing(in:)` ×2 (dvě množiny navíc) | 176 |
| z toho `block.left/right.map { … }` (dvě pole `DiffLine` navíc) | 99 |
| `block.hashValue` a podpis do řetězce | 275 |
| `lineFrames()` a porovnání s minulými | 158 |

Rozhoduje o tom **jeden klíč** (`DiffBlockDrawing`: blok + `DiffBlockStyle` + šířka) uložený
v `Coordinator`u. Co u toho platí:

- **Klíč nese celý blok, ne jeho hash.** Hodnota representable leží v grafu, takže se při dalším
  průchodu porovnávají **tatáž** pole a `Array.==` se vrátí na identitě úložiště. Změřeno
  (`DiffPerformanceMeasurement.blockUpdateGuardCost`, 27 bloků po 60 řádcích): klíč **0,013 ms**,
  hash s podpisem **0,530 ms**; i porovnání po řádcích u čerstvých polí (**0,284 ms**) je levnější
  než hash. Stráž tedy nemá jak stát víc, než co ušetří.
- **Šířka v klíči být musí.** Rámečky řádků se z ní počítají a ve split pohledu z nich vychází
  hranice pravé poloviny (`DiffGutterGeometry.split`), takže bez ní by po zúžení okna svítila
  pilulka jinde, než kde se táhne rozsah.
- **Do klíče sazby ale šířka nepatří** (`DiffBlockStyle`): text se zalamuje jinak, ale sází se
  stejně, a přesázení **ruší rozdělaný výběr** (#157). Proto jsou to dva klíče, ne jeden.
- **Paleta se bere z klíče**, ne od volajícího: dvě hodnoty o jednom barevném režimu by dovolily
  nasadit paletu, která ke klíči nepatří, a sazba by se přeskočila s barvami z minula.
- **Sazba se neopakovala ani před #393** — držel ji podpis obsahu. Co se opakovalo, bylo
  **nasazení**; proto blok drží tři počitadla (`updates`, `mounts`, `typesettings`) a testy tvrdí
  poměr mezi nimi, ne jen nulu (viz [`testovani.md`](testovani.md)).
- **Kolo z #361 to nezastaví.** Naše práce byla 5,5 % vzorků toho kola; zbytek je přepočet
  geometrie líného seznamu (`LazySubviewPlacements`, `UnaryChildGeometry`) uvnitř jednoho
  `flushTransactions`. Je to **zlevnění obsahu kola, ne jeho oprava** — z 5,5 % se 99 % neposkládá.
- **`needsLayout = true` v `show(…)` do toho kola nemluví**: AppKitové rozvržení potřebuje kolo
  runloopu, a to se v záchvatu nekoná (ve vzorku má `DiffPairBlockContainer.layout()` **nulu**).
- **Stráž nemají všechna representable, a je to změřené.** Aktualizaci při každém přepočtu geometrie
  dostane ten, který si **říká o vlastní velikost** (`sizeThatFits`) — tedy oba bloky diffu. Nad
  tímtéž špiněním grafu dostane blok dvojic **11** aktualizací a `SelectableCodeView` (hunk v sheetu,
  taky sází text bezpodmínečně) **jednu**, protože se jeho hodnota nemění. Proto tam stráž není:
  nešla by ověřit vloženou regresí, a stráž, kterou nemá co vyvolat, je stav, který nikdo nečte.
  Drží to `DiffBlockUpdateTests.codeSheetIsNotUpdatedByGeometry`. `LogTailTextView` má vlastní stráž
  od #292 (`shownText`/`shownColor` v koordinátoru) — je to tentýž vzor, jen o tři issues starší.

  **Přeměřeno u #417, když se ten sheet stal roztahovatelným** — a vyšlo to nastejno: za patnáct
  kroků tažení skutečného okna sheetu (po 12 bodech) přišlo `updateNSView` **nula krát** a rozdělaný
  výběr zůstal. Tažení tedy hodnotu representable nemění, takže stráž se ani tehdy nepřidala; ověřeno
  i obráceně, že bez ní tentýž test projde. Podrobnosti v *Sheet s kódem a s logem*.

### Barvy diffu (#277)

Pozadí řádků, word-level vrstva, šrafa prázdného protějšku a znak `+`/`−` jdou z `Palette` —
vyčíslené dvojice světlá/tmavá, žádné krytí. Hodnoty jsou **z návrhu** (tokeny `--add-bg`,
`--add-hi`, `--del-bg`, `--del-hi` a `tr.empty-side`); čísla u každé jsou u tokenů
(`Palette.diffAdded` a dál). Tady je to, co se u nich nemá rozbít:

- **Barva plochy nesmí být krytí nad podkladem.** Tohle je celé #277 a je to tentýž argument, jaký
  #185 zapsalo u `critLine`: skrz krytí prosvítá to, na čem barva leží, takže **není hodnotou, ale
  výsledkem**. V tmavém režimu se systémová zelená na 12 % mísila směrem k černé a plocha přidaného
  bloku vycházela `#152B22`, tedy tmavý obdélník. Hlídá to test na **alfu** všech pěti tokenů.
- **Odlišení ploch se měří ΔE2000, čitelnost textu nad nimi WCAG.** Jedna míra nestačí a je to
  změřené: word-level vrstva měla do #277 v tmavém režimu ΔE 29,5 (plocha jak vyšitá) a kontrast
  zeleného řetězce Darculy **1,27**, tedy nepřečtitelný kód právě na tom slově, které se změnilo.
  Tvrzení jsou proto v testech vždycky dvě.
- **Světlá větev je z návrhu doslova, tmavá je vědomá odchylka** — a ta odchylka je celé jádro #277:
  návrh má v tmavém režimu `rgba(63, 185, 80, 0.13)`, což nad `panel` složí `#172922` a ΔE 14,6, tedy
  **reprodukuje přesně tu stížnost** (systémová zelená měla 16,0). Vyčíslené `#0F2C13` má ΔE 21,8.
- **Sytost je levnější než světlost.** WCAG kontrast textu závisí jen na světlosti, kdežto ΔE plochy
  roste i se sytostí — tmavé tóny proto vznikly mixem `ok`/`crit` **do černé**, ne do plochy.
  Odlišení tím vyrostlo (16,0 → 21,8 u přidaného) a syntaxe zůstala na svém (3,73 → 3,76). Kdo bude
  hodnoty ladit, má tímhle směrem rezervu; zesvětlením ji nemá.
- **Zelená a červená mají v diffu jeden zdroj**, `DiffLineView.signColor(of:)` (#156) — bere ji
  `+`/`−` v řádku, souhrn `+X −Y` v hlavičce i čtverečky poměru (#218). Od #277 vrací
  `Palette.ok`/`crit`, tak jak to má návrh (`tr.add td.sg { color: var(--ok) }`), takže systémová
  zelená z diffu zmizela úplně; **plochy** řádků jsou ten tón zamíchaný do podkladu.
- **Word-level vrstva drží pravidlo návrhu, ne jeho hodnotu.** `--add-hi` je `ok` na 30 % nad pozadím
  řádku — a to pozadí se u #277 změnilo, takže se vrstva přepočítala (`#1D5625`). Je to vědomá výměna:
  méně hlasitá než dřív (ΔE 13,9 proti 29,5), zato se pod ní dá číst (řetězec 2,17 proti 1,27).
  Rozhodnutí z #153 tím drží v tom, na čem stálo: vrstva musí být na první pohled jiná plocha než
  zbytek řádku, a práh je ΔE 10.
- **Obyčejný text má barvu z návrhu, a nasazuje se vždycky** (#393). Token je `--ink`
  (`Palette.ink`), protože `td.code` v mockupu dědí barvu textu stránky; v `SyntaxColors` je to
  `plain` a v textu bloku sedí jako **základní atribut celého řetězce**, který obarvení syntaxe
  přepisuje přes svoje rozsahy. Nasadit se **musí**: chybějící `.foregroundColor` znamená
  v atributovaném řetězci **černou**, ne dědění, takže do #393 byly identifikátory v tmavém režimu
  černé na tmavém — a soubor bez rozpoznaného jazyka celý. Změřené kontrasty (WCAG, obě větve):

  | pozadí řádku | světlý: černá → `ink` | tmavý: černá → `ink` |
  |---|---|---|
  | kontext (`surface`) | 21,00 → 17,90 | **1,14 → 15,31** |
  | přidaný (`diffAdded`) | 19,23 → 16,39 | **1,39 → 12,55** |
  | odebraný (`diffRemoved`) | 18,31 → 15,61 | **1,26 → 13,89** |
  | word-level přidaný | 15,84 → 13,50 | **2,41 → 7,24** |
  | word-level odebraný | 14,42 → 12,29 | **1,99 → 8,77** |

  Ve světlém režimu je to nepatrné zhoršení (černá je kontrastnější než inkoust), ale všude nad AAA
  a **shodné s návrhem**, který černou nemá nikde. **Ne `labelColor`**: ten je poloprůhledný
  (bílá na 85 %), takže by se přes barevné pozadí řádku složil jinak než v mockupu.

  Zůstává z toho jedna věc k zapamatování: `DiffPaletteTests` ten kontrast (`ink` nad oběma druhy
  řádku, práh 10) měřily **odjakživa** a procházely — jenže měřily **token**, ne to, co se kreslí.
  Že se ta barva doopravdy nasadí, tvrdí od #393 `DiffBlockCompositionTests`.
- **Pruh rozsahu komentáře zůstává průhledný schválně** (`rangeTint`, `dragTint`): musí se s barvou
  druhu řádku **smíchat**, aby pod ním zůstalo vidět, co je přidané. Je to tedy jediné krytí, které
  v diffu zbylo, a je to jiný případ než plocha — hodnota se tu měnit *má*. Změřeno nad novým
  pozadím: pruh je od neoznačeného řádku ΔE 9,5 a označený přidaný řádek je od označeného kontextu
  ΔE 21,7, takže se ani jedna informace neztratí.
- **Pruh se kreslí nad pozadím, ne pod ním.** Do #277 to bylo ve SwiftUI cestě obráceně
  (`.background(barva).background(pruh)`) a fungovalo to jen proto, že pozadí bylo průhledné —
  s vyčíslenou barvou by pruh zmizel. Blok kódu (`DiffTextView.drawRows`) měl správné pořadí
  odjakživa, takže se tím obě cesty srovnaly.
- **Prázdný protějšek odlišuje textura, ne plocha** (`DiffMissingHatch`). Návrh na to má šrafu
  u `tr.empty-side` (`repeating-linear-gradient(45deg, transparent 0 5px, ink 5 % 5px 10px)`)
  a v tmavém režimu to jinak ani nejde: pod plochou obsahu není kam ztmavovat (pruh je od ní ΔE 3,4)
  a zesvětlením by díra křičela hlasitěji než změna vedle ní. **Plocha se proto nekreslí vůbec** —
  v návrhu je pod gradientem `transparent`. Nese to **rozestup** (pruh 5 bodů, mezera 5), ne kontrast.
- **Šrafa leží nad plochami řádků, ne pod nimi.** Kreslená před nimi zmizí pod pozadím řádku —
  vyzkoušeno, byla to první verze #277 a chytil to test nad bitmapou.
- **Vodorovný krok pruhů je √2× perioda.** Sklon 45° znamená, že vzdálenost napříč pruhy (kterou měří
  CSS gradient) není ta vodorovná; bez toho přepočtu vyjde šrafa hustší, než jakou návrh kreslí.
  A **směr pruhů je z vyrenderované sekce návrhu**, ne odvozený z `45deg`: gradient míří k pravému
  hornímu koutu, ale pruhy leží napříč jeho osou, takže se to snadno otočí — první verze #277 je
  měla zrcadlově.
- **Které řádky jsou prázdné, řekne sloupci dvojice** (`DiffTextView.missingLines`), protože
  v textu je prázdná strana složená jako prázdný **kontextový** řádek (`DiffLine.blank`) — jinak by
  se sloupce nezarovnaly. Do #277 se ten stav nekreslil vůbec, takže „tady řádek není“ a „řádek se
  nezměnil“ byla tatáž plocha (ΔE 0,0). **Rozšířit `DiffLine.Kind` o `missing` se zamítlo**: je to
  vlastnost jednoho rozvržení, ne řádku souboru, a protáhla by se parserem, `Policy` i kotvami
  komentářů.
- **Obrys bubliny nálezu je pořád jedna barva pro všechny podklady** (`critLine`, #185), takže se po
  každé změně pozadí musí přeměřit nad všemi: vychází 1,69 na přidaném a 1,87 na odebraném řádku
  v tmavém režimu (do #277 to bylo 1,68 a 1,83), tedy nezměněno.

Word-level rozdíl (#153) — u přepsaného řádku svítí jen ta část, která se změnila. `WordDiff` je
čistá funkce v `App/Diff/`, obarvení dělá `DiffTextView`. Co se u toho nemá rozbít:

- **Zvýraznění nesmí do `SyntaxRunCache`.** Tohle je celé jádro věci: cache je klíčovaná
  `(text řádku, jméno jazyka)`, ale word-level zvýraznění závisí na **protějšku** dvojice —
  tentýž řádek proti jinému protějšku svítí jinde. Kdyby se přimíchalo do `SyntaxRun`u, vracela by
  cache zvýraznění patřící cizí dvojici, a **potichu**: testy obojího zvlášť projdou. Je to proto
  **druhá vrstva nad** výsledkem z cache — atribut `.backgroundColor` přes hotové runy. Kdyby se
  někdy cachovat mělo, klíč musí nést **obě** strany dvojice, a je to pak jiná cache než tahle.
  Hlídá to test „tentýž řádek proti jinému protějšku svítí jinde“.
- **Dvě vrstvy si nesmí sáhnout na totéž:** syntaxe je **barva písma**, word-diff **pozadí**.
  Ověřeno renderem, ne úvahou. **Sytost je 50 %, opravená z 30 % při zkoušení** — třicet vyšlo
  z renderu jednoho bloku, ale v okně se zvýraznění hledá v celém diffu a na jednoznakové změně se
  přehlédlo. Skládané hodnoty i důvod jsou u `DiffLineView.wordBackground(of:)`.
- **Word-diff **není** místo, kam sáhnout u tuhnoucího okna** (zkoušeno u #153). Počítá se za
  stráží na podpis obsahu, takže se za něj platí jednou na obsah bloku — naměřeno **18 %** ceny
  `DiffPairBlockContainer.show` v nejhorším případě (blok samých dvojic), a `show` je jen část
  toho, co stojí projíždění diffu. Co v tom případě stojí za pozornost, je rozvržení líného
  seznamu; postup a vyloučené příčiny jsou v [`testovani.md`](testovani.md).
- **Zvýraznění nemění text.** Tentýž invariant jako „spojení run dá původní řádek“ a „z dvojic se
  poskládají přesně původní řádky“. V testech se řádek skládá zpátky z toho, co je uvnitř rozsahů
  a mimo ně.
- **Párování má dvě vstupní branky, ale jedno pravidlo.** Ve split pohledu dvojice existuje
  (`DiffRow.paired(_:)`), takže se porovnává vlevo proti vpravo podle pozice; pod sebou dvojice
  není, takže si ji `WordDiff.spans(in:)` skládá **týmž pravidlem** — blok `-` se s následujícím
  blokem `+` páruje jeden na jednoho, `+` po `-` je přepsání a `-` po `+` už nová skupina.
  Že se ta dvě pravidla nerozejdou, hlídá test, který obojí porovnává na skutečném diffu.
  **Zamítnuto:** počítat dvojice i pro unified přes `paired(_:)` — to slévá řádky do jiné podoby
  seznamu a v pohledu pod sebou se kreslí ty původní.
- **Počítá se až při skládání textu bloku** (`DiffTextView.show(…)`), ne v modelu vedle
  `DiffRow.rows(_:)`. Rozhodlo měření: blok o 60 řádcích samých dvojic stojí **0,42 ms**, celý
  soubor o 2400 řádcích **19,6 ms** — a model se přepočítává při **každém** překreslení diffu
  (i při tažení rozsahu), takže v něm by to byl rozpočet na snímek pryč. V `show(…)` se to spočítá
  jednou na obsah bloku a jen pro to, co je vidět; proto se předává **closure**, ne hodnota — za
  stráží na podpis se jinak počítalo i při přejezdu myší.
- **Cena je z toho důvodu ohraničená i shora**: nad `pairBudget` (součin počtu tokenů) se
  nejdelší společná podposloupnost nehledá vůbec a zvýrazní se celý rozdílný střed.
- **Po tokenech, ne po znacích** — rozhodnuto měřením na skutečném diffu, ne úvahou. Na 332
  dvojicích z historie tohohle repa: po tokenech svítí 26,5 % znaků v **1,62** úsecích na řádek,
  po znacích 28,9 % ve **3,46** úsecích. Po znacích se navíc přes práh podobnosti dostane o 34
  dvojic víc — společná písmena dvou nesouvisejících řádků vypadají jako podobnost.
  **Operátor drží pohromadě** (`==` proti `!=` je jedna změna), závorky a čárky ne — jsou to
  hranice, ne slovo.
- **Nepodobná dvojice se nezvýrazňuje.** Smazání a přidání vedle sebe není přepsání; práh je 0,30
  ze společných **neprázdných** znaků (odsazení mají společné skoro všechny řádky). Z ručně
  projitého vzorku: nad 0,30 bylo všechno opravdové přepsání (`.font(.caption2)` →
  `.font(.system(size: 10.5))` má 0,32), pod 0,27 už ne (`folding.toggle(file)` proti
  `file: file,` má 0,20).
- **SwiftUI cesta (`DiffLineView`) zvýraznění nemá, a nic tím nechybí.** Kreslí se jí už jen
  úryvek u vlákna na ose konverzace, kde je řádek **jeden** — protějšek, proti kterému by se
  porovnávalo, tam neexistuje.
- **Známé omezení:** dvojici, kterou rozdělí **hranice bloku** (strop 60 řádků nebo bublina mezi
  `-` a `+`), pohled pod sebou nezvýrazní — protějšek je v jiném `NSTextView`u. Ve split pohledu
  se to nestane, protože dvojice je jeden řádek seznamu. Cena za to, že se počítá lazy nad blokem;
  opravit to znamená počítat nad celým souborem, tedy zaplatit těch 19,6 ms při každém překreslení.

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

Úryvek kódu u vlákna v `Přehledu` (#158) k tomu přidává:

- **Kód se bere z `diffHunk` od GitHubu, nikdy se nedopočítává.** Je to snímek proti commitu,
  na kterém komentář vznikl, takže se nic nehádá — kdežto výřez z dnešního souboru by
  u zastaralého vlákna ukázal **jiný kód**, a to je přesně ten druh tichého rozchodu, kterému
  se aplikace vyhýbá jinde u nálezů (`headSha`).
- **Kontext je jen před komentovaným řádkem, protože `diffHunk` končí právě na něm.** Změřeno
  na `cli/cli#13084` u všech 38 vláken, na obou stranách diffu. Pět řádků *za* ním, jak chtělo
  zadání #158, by si vyžádalo novou čtecí metodu gateway na obsah souboru v daném commitu —
  dnešní `fetchFile(id:path:)` čte **dnešní** hlavu PR. Vlastní cena, vlastní rozhodnutí;
  kontext před řádkem je zdarma a je to totéž, co ukazuje GitHub ve svém zabaleném vlákně.
- **Hunk se nevykresluje celý.** Medián je 190 řádků (min 2, max 311), takže se ukazuje
  posledních `Policy.threadSnippetContext + 1`, tedy šest — a **zkrácení je vidět** značkou nad
  úryvkem. Přesný počet zahozených řádků ne: nedává důvod nic udělat, kdežto „začíná to dřív“ ano.
- **Vykresluje to `DiffLineView`, ne vlastní renderer.** `diffHunk` *je* unified diff, takže ho
  `DiffParser` přeloží na `DiffLine`y a dál platí totéž obarvení jako v diffu. Druhý renderer by
  se rozešel a barvy by na dvou místech okna znamenaly něco jiného.
- **Hunk se obaluje syntetickou hlavičkou `diff --git`.** `DiffParser` zařazuje řádky podle
  stavu a před první hlavičkou souboru nemá řádek kam patřit — samotný `@@` blok by celý spadl
  do `unrecognizedLines` (je na to test). **Parser se kvůli tomu neupravil**: na jeho invariantu
  „nerozpoznaný řádek se počítá“ visí důvěra v celý diff. `---`/`+++` se nepřidávají, cesty
  z hlavičky nikdo nečte — jazyk na obarvení se bere z `ReviewThread.path`.
- **Z cesty se do hlavičky nesmí dostat řádkový zlom** (nález z review #165). Cestu určuje autor
  PR a git jméno souboru s `\n` unese, takže bez zahození zlomů jde do syntetické hlavičky
  propašovat další řádky diffu — třeba vlastní `@@` blok — a v `Přehledu` se pak ukáže kód, který
  v souboru **není**. Ověřeno vložením regrese, není to hypotéza. Placeholder místo cesty by
  hrozbu zavřel taky, ale nechal by v `FileDiff` nesmyslnou cestu jako past pro toho, kdo by ji
  jednou chtěl číst.
- **Kontext se clampuje na aspoň jeden řádek** (`max(1, context + 1)`), taky nález z #165:
  `suffix(_:)` má na zápornou délku precondition, takže by to **položilo aplikaci** — ověřeno.
  A `ThreadSnippet.lines` má být podle typu neprázdné, což tím clamp drží i pro nesmyslný vstup.
- **Úryvek je jen v `Přehledu`, ne v bublině.** Vlákno **s kotvou** visí u kódu, kde je ten kód
  nad ním vidět, takže úryvek v `ThreadBubbleView` by ho kreslil dvakrát.
- **Nerozpoznaný řádek se počítá jako zkrácení.** Úryvek pak není spojitý kus souboru, a tvrdit
  u něj „tohle je celý kontext“ by bylo nepravdivé. Bezpečný směr je jediný.
- **Vlákno bez hunku se kreslí jako dřív, ne prázdné.** Starší odpovědi (fixtures z #63) pole
  nemají; `nil` znamená „nevíme“, kdežto prázdný rámeček by tvrdil, že kontext žádný není.
- **Úryvek se počítá při vykreslení, ne dopředu a bez cache** — a je to **změřené, ne odhad**:
  38 vláken s tím nejdelším hunkem z fixture (129 řádků) stojí **4,6 ms** na jedno „překreslení“
  celého `Přehledu`, proti 0,15 ms, které tam už dneska stojí `Policy.overview` (výběr vláken
  proti diffu). Není to na úhoz: rozepsaná odpověď jde do storu **odloženě po 400 ms**
  (`DraftTextEditor`), takže se to spustí při načtení konverzace, při rozbalení vlákna a po
  pauze v psaní. Předfiltr — parsovat jen konec hunku — by si vyžádal **vlastní počítání čísel
  řádků**, tedy druhé místo, které dělá to, co `HunkBuilder`, a přesně tomu se tady vyhýbáme.
- **Vybírat text v úryvku nejde**, i když `Přehled` má selekci jinak zapnutou (`OverviewView`).
  Není to konzistence s diffem: `DiffLineView` nese gesto tažení pro rozsahy komentářů, takže
  by tažení přes kód selekci spolklo a vypadalo by to jako rozbité okno. Kopírování z diffu
  řeší #157 — na jednom místě pro obojí.

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

## `Config` (`App/Config/`)

Nastavení ve dvou úrovních. Nahrazuje konstanty, které byly do #23 roztroušené po celé
aplikaci (skilly, blokující kategorie, interval pollingu, limit souběhu, rozpočet cache).

| Typ | Co je |
|---|---|
| `Configuration` | Celý `config.json`: globální část + `[RepoID: RepositoryConfig]`; `resolved(for:)` a `activeSources` říkají, co doopravdy platí |
| `GlobalConfig` | `sources`, `ownLogins`, `skills`, `skillsByLanguage`, `reviewPrompt`, `reviewTimeoutMinutes`, `blockingCategories`, `mode`, `allowsPublishing`, `findingsLanguage`, `diffLayout`, `appearance`, `notifications`, interval, souběh, `autoRunsPerDay`, rozpočet, model |
| `RepositoryConfig` | Override pro jedno repo: `mode`, `allowsPublishing`, `findingsLanguage`, skilly, kategorie, `reviewTimeoutMinutes` — **všechno volitelné** |
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
- **Výchozí zdroje jsou od #330 dva** — `reviewRequested` a `mine` (`author:@me is:open`) — a je to
  **jediná výjimka z pravidla „výchozí hodnoty se nesmí rozejít s tím, jak aplikace běžela dřív“**.
  Bez toho zdroje by sekce `Moje PR` (#331) neměla odkud brát data a každému, kdo si ten řádek
  nedopíše ručně, by zůstala navždycky prázdná. Projeví se to **jedině na prázdné cache**: uložené
  `sources` se **nemigrují** (`decodeIfPresent` vezme, co je v souboru), protože dopsat uživateli do
  ručně editovaného souboru dotaz, o který neřekl, je zásah do jeho věci — a zdroj navíc je dotaz
  navíc při každém tiku. Že zdroj chybí, pozná `Policy.tracksOwnPullRequests` a řekne to prázdný
  stav sekce, ne migrace.
- **`ownLogins` je seznam dalších „mých“ loginů** (#330) — typicky agent s vlastním účtem
  (`github-actions[bot]`, Copilot), který pushuje pod sebou. Viewer z `gh api user` se přidává sám,
  takže **prázdné pole je běžný stav**, ne nedodělek: agenti v tomhle repu pushují přes moje `gh`
  a mají autora `ondrajodas` (ověřeno na živých datech). Čte se **přísně jako `sources` a `skills`**
  — hodnota jiného typu položí čtení —, protože tiše podstrčené prázdno by z PR agenta udělalo cizí
  PR, tedy řádek ve frontě k review, o kterou nikdo nepožádal. **Globálně, ne per repo** (kdo jsem
  já, z repozitáře neplyne) a **v okně nastavení pole není**: je to jednorázová věc pro toho, kdo si
  pouští agenta pod vlastním účtem, a nová sekce nastavení by znamenala změnu vzhledu, tedy mockup
  a schválení. Round-trip na disk to proto drží testem — soubor je jediná cesta, kterou se hodnota
  do aplikace dostane.
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
- **Notifikace (#86) se čtou tolerantně a per repo se nenastavují.** Chybějící sekce i chybějící
  přepínač znamenají **zapnuto**, a rozbitá hodnota se sráží na **výchozí (zapnuto)** — opačná
  volba než u `allowsPublishing`, kde překlep nesmí otevřít cestu ven. Tady je nejhorším
  následkem notifikace, o kterou si nikdo neřekl, kdežto umlčená aplikace se pozná až tím, že
  nic nepřišlo. **Rozbitý jeden přepínač nezahodí ostatní**: sekce se dekóduje po polích, jinak
  by se s jedním překlepem vypnulo i to, co je napsané správně. Per repo to není ze stejného
  důvodu jako `diffLayout` — „nechci být vyrušován“ je vlastnost člověka, ne repa.
- **Pohled na diff (#98) se čte tolerantně jako jazyk nálezů a per repo se nenastavuje.**
  Rozbitá hodnota spadne na výchozí (`unified`) a celý soubor kvůli ní nezmizí — nejhorší
  následek je jiný pohled na diff, který se otočí jedním kliknutím v liště. `RepositoryConfig`
  ho nemá schválně: `mode` nebo `skills` jsou vlastnost repa, kdežto jak se čte diff, je
  vlastnost člověka, který ho čte. **Přepínač v liště do souboru nezapisuje** — odchylka žije
  v `AppStore` (viz níž), jinak by hodnota tady přestala být tou, které se říká výchozí.
- **Vzhled okna (#278) se čte tolerantně jako pohled na diff a per repo se nenastavuje.** Neznámá
  hodnota znamená `system`, tedy stav, ve kterém aplikace běžela před #278 — a celý soubor kvůli ní
  nezmizí. Přísnost jako u režimu nebo odesílání by tady nechránila nic: vzhledem nic neodejde a nic
  se nespustí, nejhorší následek překlepu je světlé okno, které se přepne jedním kliknutím.
  `RepositoryConfig` ho nemá schválně — vzhled je vlastnost člověka, který se kouká, ne repozitáře,
  na který se kouká. **Je na to test, který tvrdí, že se nic nestalo**: v zapsaném JSONu smí klíč
  `appearance` být právě jednou, a napsaný pod repem nesmí udělat nic. Do výčtu
  v `bin/slot-config.sh` patří přesto — ten vyjmenovává i klíče s jedinou úrovní — a je u něj
  napsané, že se **nečistí**: vzhledem se nic neutratí a nic neodejde, a vynutit slotu vzhled,
  o který nikdo neřekl, je změna, ne očista. **Stránku v nastavení volba nemá** — ovládá se z railu,
  viz `AppStore` a `App/Views/` níž. Kde se uplatní, je taky tam.
- **Šablona promptu (#281) se čte přísně**, jako `sources` a `skills`. Chybějící klíč znamená
  výchozí text — tedy dnešní chování u každého, kdo aplikaci používal před #281. **Hodnota jiného typu
  (číslo, pole, objekt) čtení položí** (`try`, ne `try?`): tiše podstrčený výchozí prompt by
  znamenal, že se reviewer ptá na něco jiného, než co má někdo v souboru, a nic by na to
  neupozornilo. **`null` se počítá jako chybějící klíč** a je to vědomé — není to hodnota, které by
  se nedalo rozumět, ale výslovné „nic tu není“, tedy totéž, co znamená prázdný řetězec; chová se
  tak i `sources` a `skills`, zbylé dva klíče s hlášenou rozbitou hodnotou.
  Takhle se okno zamkne s „Konfiguraci se nepodařilo přečíst“ a soubor se nepřepíše. Tolerance se
  tím neporušuje: tolerantní je čtení vůči **chybějícímu** klíči, ne vůči hodnotě, které se nedá
  rozumět. **Prázdný řetězec je platná hodnota** a znamená „ber výchozí“, ne prompt bez zadání —
  opačně než u seznamů, kde prázdno je vlastní odpověď; seznam se prázdný nechává, kdežto text se
  prázdný jen prochází. `RepositoryConfig` prompt nemá, ze stejného důvodu jako vzhled: je to
  vlastnost člověka, ne repozitáře, a je na to test.
- **Časový limit běhu (#320) se čte jako ostatní čísla a per repo se nastavuje.** Chybějící klíč
  znamená patnáct minut, tedy chování před #320; hodnota jiného typu čtení **položí** (`try`, ne
  `try?`), stejně jako u intervalu nebo rozpočtu. Dvě věci navíc:
  - **Číslo mimo meze soubor nepoloží a v konfiguraci zůstane syrové.** Sráží se až
    `resolved(for:)` přes `Policy.reviewTimeout(minutes:)` — a je to jediné místo, kde se sráží,
    takže i override pod repem dostane tentýž strop. Kdyby se sráželo při čtení, přišlo by se
    o rozdíl mezi „napsal jsem 120“ a „mám 60“ a nastavení by neměl kdo pojmenovat.
  - **Override per repo tady je** (na rozdíl od promptu, vzhledu a pohledu na diff): velké repo
    potřebuje delší limit a je to vlastnost **repa**, ne člověka, který se kouká. `nil` znamená
    „ber globální“, jako u režimu a sad. Přísnost jako u režimu se nehodí — delší limit nic
    nespustí a nic neodešle, jen dovolí běhu doběhnout.
- **Rozbitá hodnota režimu se sráží na `manual`, ne na globální default.** Chybějící klíč
  je „ber globální“, ale překlep v hodnotě, kterou se někdo pokoušel automat **vypnout**,
  ho nesmí nechat zapnutý. Platí i globálně.
- **Výchozí hodnoty musí odpovídat konstantám, které nahradily** — je na to test, jinak by
  se aplikace po zavedení konfigurace začala chovat jinak. Výchozí `mode` je `manual`:
  zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.
- **Nový klíč v `RepositoryConfig` má druhého čtenáře mimo aplikaci: očistu konfigurace slotu**
  (#262, `bin/slot-config.sh`). Klíčů, které mají obě úrovně, je šest — `mode`,
  `allowsPublishing`, `findingsLanguage`, `skills`, `blockingCategories`
  a `reviewTimeoutMinutes` (#320) — a u každého z nich je ve skriptu napsané, jestli se čistí
  a proč. Očistit jen globální úroveň **nestačí**: per-repo
  override je přednější, takže `mode: automatic` u jednoho repa přebije globální `manual` —
  a slotová aplikace si na M9 takhle sama pustila review za 2,80 $ a 1,16 $, dvakrát nezávisle
  na sobě. Když klíč přibude, patří do toho výčtu, i kdyby se nakonec nečistil; nevyplněné
  místo v něm je celá ta chyba.

## `App/Markdown/`

Vykreslení Markdownu z GitHubu — popis PR, komentáře, těla review. Čisté funkce plus tři
malá view, **žádná externí závislost**: stejná úvaha jako u `App/Syntax/`.

| Typ | Co je |
|---|---|
| `MarkdownBlock` | Blok: nadpis, odstavec, položka seznamu (odrážka/číslo/zaškrtávátko), kód, **citace (vnořené bloky)**, **výstraha** (`Alert`: pět druhů), oddělovač, tabulka, `<details>`, HTML komentář |
| `MarkdownParser` | Text → `[MarkdownBlock]`. **Nikdy nevyhodí výjimku**. Rekurze u citací a `<details>` má strop `nestingLimit` |
| `MarkdownHTML` | Inline HTML na text: `<a href>` na Markdown odkaz, ostatní tagy pryč, entity dekódované |
| `MarkdownInlineText` | Inline sazba: systémový `AttributedString` plus podložený inline `kód` |
| `MarkdownTypography` | Sazba v číslech: šest velikostí nadpisů, velikost kódu, mezera mezi dvěma bloky |
| `MarkdownAlertStyle` | Jak se kreslí výstraha: český titulek, SF Symbol, barva z palety |
| `MarkdownRenderCache` | Zapamatovaná sazba: rozklad na bloky i inline `AttributedString` — klíčem je celý text (u inline i velikost) |
| `MarkdownText`, `MarkdownBlocksView`, `MarkdownBlockView` | Vykreslení; tři typy kvůli rekurzi v citaci, výstraze a `<details>` |

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

### Citace, výstrahy a sazba (#279)

- **Citace nese bloky, ne řádky.** `case quote([MarkdownBlock])`, tedy tentýž tvar, jaký má
  `details`. Do #279 to byly surové řádky slepené ve view do jednoho `Text`u, takže `## nadpis`,
  odrážka i `- [ ]` **uvnitř** `> …` zůstaly v okně jako zdroj — a boti do citací píšou celé
  zprávy (CodeRabbit posílá v jedné výstraze nadpis, odstavce a dvě rozbalovátka).
- **Za `>` se zahazuje jedna mezera, ne všechna.** Na odsazení uvnitř citace stojí úroveň
  zanořeného seznamu. Do #279 se trimovalo všechno, což při slepení nebylo vidět; po rozdělení na
  bloky by to každý zanořený seznam zarovnalo na nulu.
- **Výstraha je vlastní druh bloku, ne příznak citace.** `> [!NOTE]` a čtyři další; značka musí
  být **sama na prvním řádku** citace (jako na GitHubu) a druh se poznává bez ohledu na velikost
  písmen. **Neznámý druh výstrahou není** — z `[!FOO]` je obyčejná citace, ve které ten řádek
  zůstane textem. Je to tentýž princip jako u tabulky: neumět něco vysázet je lepší než to
  zahodit.
- **Titulek výstrahy je český, barva z palety.** Ve zdroji je jen `[!NOTE]`, takže titulek i ikona
  jsou tvrzení aplikace, ne text z GitHubu. `[!WARNING]` a `[!CAUTION]` mají **vlastní tón**:
  GitHub jim dává `0x9A6700` a `0xCF222E`, což je na hex `Palette.stale` a `Palette.crit` — tedy
  zastarání a blokující nález. Hlídá to test, který porovnává **vyřešené** barvy v obou režimech.
- **Šest úrovní nadpisů, šest velikostí** (`MarkdownTypography`), pod `#` a `##` linka. Do #279
  z toho byly dvě velikosti (`level <= 2 ? .headline : .subheadline`), takže `Description`
  a `Release Notes` v popisu PR vypadaly jako tučný odstavec. Škála je **poměrová k základní
  velikosti**, protože tentýž Markdown se sází v komentáři (12,5) i v okně s novinkami (13);
  krok mezi třetí a pátou úrovní je celý bod, protože v první verzi (0,06 bodu) byly ty úrovně na
  vyrendrované ukázce nerozeznatelné.
- **`MarkdownText` bere velikost číslem, ne `Font`em.** Ze `Font`u se velikost nedá přečíst, takže
  by z něj škála nadpisů neměla z čeho vyjít — a přesně proto tam ty dvě velikosti byly.
- **Mezera mezi bloky se řídí přechodem**, ne blokem: nadpis má nad sebou 12 bodů a pod sebou 4
  (to, co následuje, k němu patří), dvě položky seznamu 2, zbytek 7. Jedna mezera pro všechno
  dělá z dlouhého popisu PR jednolitou plochu. **Žádný přechod není nulový** — na to je test.
- **Pruh citace i výstrahy je `overlay`, ne první prvek `HStack`u.** V `HStack`u se výška pruhu
  řídila návrhem rodiče, kdežto obsah si spočítal svou vlastní: u citace s nadpisem
  a zaškrtávátkem sahal pruh do poloviny a zbytek citace stál bez značky. Vidět to bylo až na
  vyrendrované ukázce, ne v kódu.
- **Zanoření má strop** (`MarkdownParser.nestingLimit`, šest úrovní). Je proti dvěma věcem naráz:
  proti hloubce stromu view (#220 — 5,5× na úroveň) a proti rekurzi nad `>>>>>>…` z mailového
  vlákna. Za stropem zůstane obsah **jedním odstavcem** — nevysází se, ale neztratí.
- **Sazba se pamatuje** (`MarkdownRenderCache`), protože se počítá v `body`, tedy při každém
  vykreslení — pravidlo #224. Změřeno (Debug, `TEST_RUNNER_PRISM_MEASURE=1`): u zprávy od bota
  o 12 kB **1,91 ms** rozklad na bloky (z cache 0,037 ms) a **1,81 ms** inline sazba jejích 44
  bloků; konverzace o 40 zprávách **74,7 ms** proti **1,48 ms**. Obojí je v **jedné** cache
  schválně: meze a jejich vyprazdňování jsou to, co se dá pokazit, takže mají být na jednom místě.
  Klíčem je **celý text**, ne hash ani `(id, délka)`: klíč, ze kterého vyjdou dva různé texty
  stejně, znamená vysázet cizí komentář, a potichu — u inline je v klíči **i velikost**, protože
  z ní vychází písmo inline kódu. Barvy v tom zapečené nejsou (`codeFill` je dynamický `NSColor`),
  takže přepnutí režimu cache nezneplatňuje. Meze jsou dvě (počet záznamů, objem vstupů) a při
  překročení kterékoli se cache zahodí celá — tatáž úvaha jako u `SyntaxRunCache`.
- **Inline `kód` má jemný podklad** (`Palette.codeFill`, tentýž jako blok kódu). Je to **plocha za
  písmem**, ne kapsle s odsazením: `AttributedString` umí barvu pozadí běhu, ne jeho výplň
  a rádius, a kapsle by znamenala kreslit každý běh jako vlastní view, tedy rozpadlé zalomení
  uprostřed věty.

## `App/Syntax/`

Obarvení kódu v diffu. **Žádná externí závislost** — vlastní pravidla místo highlight.js nebo
tree-sitteru. Rozhodování je čistá funkce; jediný stav je cache výsledků (#224), a ta na tom, co
z řádku vyjde, nic nemění.

| Typ | Co je |
|---|---|
| `Language` | Pravidla jednoho jazyka: komentáře, uvozovky, sigily proměnných, klíčová slova. `init?(path:)` pozná jazyk z cesty |
| `SyntaxHighlighter` | Řádek → `[SyntaxRun]`. `runs(of:in:)` jde přes cache, `scan(_:in:)` je vlastní průchod po znacích |
| `SyntaxRunCache` | Zapamatované obarvení klíčované `(text řádku, jméno jazyka)`, se dvěma mezemi (#224) |
| `SyntaxRun`, `SyntaxKind` | Kus řádku a jeho význam: `plain`, `comment`, `string`, `number`, `keyword`, `variable` |
| `SyntaxPalette` | Barvy — Darcula pro tmavý režim, IntelliJ Light pro světlý |
| `SyntaxColors` | Tatáž paleta v `NSColor`ech (#275) — převádí se **jednou na blok**, ne na run |

Věci, které se u toho nemají rozbít:

- **Spojení run musí dát původní řádek.** Je to invariant ve všech testech: obarvení
  nesmí text změnit, jinak by se v diffu tiše ztratil znak.
- **Obarvení se pamatuje** (#224). `runs(of:in:)` se volá z computed property `content`
  v `DiffLineView` a při složení textu bloku v `DiffTextView`, tedy **při každém překreslení** —
  a to se děje i při pouhém přejezdu myší. Naměřeno 44 ms na 2400 řádků; z cache 0,30 ms.
  Kdo barví řádek kvůli zobrazení, jde přes `runs`; `scan` je pro cache a pro měření.
- **V klíči musí být jazyk.** `# poznámka` je v shellu komentář a ve Swiftu obyčejný text.
  Klíčem je **jméno** jazyka, ne celá hodnota — `Language` se podle jména i porovnává a hashovat
  jeho sadu klíčových slov při každém nahlédnutí by stálo víc než samotné obarvení.
- **V cache nejsou barvy, jen druhy.** Přepnutí světlého a tmavého režimu ji proto
  nezneplatňuje; paletu si bere view až při kreslení. Co režim v klíči **mít musí**, je podpis
  vysázeného bloku (`DiffBlockSignature`) — tam už barvy zapečené jsou, viz `App/Views/` níž.
- **Co závisí na protějšku řádku, do téhle cache nepatří** (#153). Word-level zvýraznění je
  funkce **dvojice**, ne řádku, takže pod klíčem `(text řádku, jazyk)` by se tentýž řádek proti
  jinému protějšku obarvil podle té cizí dvojice — a nikdo by se to nedozvěděl, protože obojí
  zvlášť dál funguje. Kreslí se proto jako druhá vrstva nad hotovými runy, viz `App/Diff/`.
- **Cache se nezneplatňuje, jen vyprazdňuje.** Klíčem je text, takže záznam nemůže zastarat —
  jediná otázka je růst. Hlídají ho dvě meze a při překročení kterékoli se zahodí **celá**:
  `capacity` (4000 řádků) a `budget` (4 MB součtu jejich délek). Dvě proto, že každá chytá jiný
  způsob, jak přetéct: tisíce krátkých řádků z dlouhého sezení, nebo pár obřích řádků
  z generovaného souboru. Zahodit všechno je O(1) a stojí přepočet toho, co je zrovna vidět
  (blok o 60 řádcích ≈ 1,1 ms); LRU by pořadí zapisovala **při každém nahlédnutí**, tedy zdražila
  přesně tu operaci, kvůli které cache vznikla.
- **Mez se počítá včetně toho, co se právě vkládá** (z review #233). Kdyby se rozhodovalo jen
  podle stavu před vložením, cache by po zápisu stála **nad** rozpočtem až do dalšího zápisu —
  a to zrovna u toho jednoho obřího řádku, kvůli kterému rozpočet je. Ze stejného důvodu se řádek
  delší než celý rozpočet **nepamatuje vůbec** (obarví se, ale neuloží): jinak by se při každém
  dalším zápisu zahodilo všechno ostatní kvůli němu. A vyprazdňování se rozhoduje **jen při
  vložení nového klíče** — dvě vlákna, která spočítala tentýž řádek, jinak zahodí plnou cache
  kvůli záznamu, který v ní už je.
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
- **`NSColor(Color)` je most, ne přístup k hodnotě** (#275). `SyntaxPalette` drží SwiftUI barvy,
  ale text bloku se skládá v AppKitu — a do #275 se převádělo **na každý run**, tedy u velkého
  diffu 16 000× na jedno projetí (3,59 ms na 27 blocích). Barev je přitom pět a na runu nezávisí
  vůbec, takže `SyntaxColors` je převede jednou na blok. **Není to cache**: je to hodnota složená
  z palety, kterou volající zrovna drží, takže po přepnutí vzhledu (#278) nemá jak vrátit barvy
  z předchozího režimu — kdežto zapamatovaná podle klíče by to udělala potichu.

## `StreamParser` (`App/Review/`)

Klíčový spoj: ze `stream-json` výstupu `claude` udělá to, co aplikaci zajímá.

| Typ | Co je |
|---|---|
| `StreamParser` | JSONL řádky → `StreamSummary`. **Nikdy nevyhodí výjimku** |
| `StreamSummary` | Session id, nálezy, **pokusy** o nástroje i odpovědi na ně (#326), konec běhu, **cena běhu**, počty nepřečteného |
| `ToolAttempt` | Co si reviewer vyžádal, nad čím, pod jakým `tool_use.id` a jak to dopadlo (`Outcome`, #326) |
| `ToolResolution` | Odpověď na jeden pokus, jak ji vydá parser: `(tool_use_id, outcome)` |
| `ReviewOutcome` | Konec běhu podle `result` eventu |

Co se u toho nemá rozbít:

- **Stream se čte defenzivně (`JSONSerialization`), ne přes `Codable`.** Je to opačně než
  u `gh` — tam si `--json` polem říkáme, co má přijít, takže DTO dává smysl. Tady přichází
  cizí formát, který se vyvíjí, a většina eventů nás nezajímá; typované dekódování by
  padalo na věcech, které jsou aplikaci lhostejné.
- **Nálezy se slévají po sadách, ne po položkách** (#381). Každé volání `ReportFindings` je celá
  sada a rozhoduje **struktura volání, ne text**: pozdější sada na daném místě (`file` + `line`)
  přepíše, co tam bylo, a slévání drží jedna čistá funkce `Policy.mergedFindings(_:reporting:)` —
  parser jen složí sadu a předá ji. Do #381 se porovnávalo místo **a celé `summary`**, což mělo
  zabránit slití dvou různých problémů na jednom řádku; jenže reviewer, který si nález opraví,
  přepíše i `summary` (u #381 stačilo `fáze` → `fázi`), takže korekce prošla jako nový nález
  a v bublině ležel týž nález dvakrát. Podrobnosti i zamítnuté cesty jsou v `Policy` níž a v
  záznamu rozhodnutí ve specifikaci.

  Uvnitř jedné sady se **neslévá nic** (dva nálezy vedle sebe = dva problémy, viz
  `Cart.swift:17` v `review-with-findings`) a nález z dřívější sady, o kterém pozdější sada mlčí,
  **zůstane** — včetně přebytku na tomtéž místě. Ztracený nález se totiž v okně nedá odlišit od
  „reviewer nic nenašel“. Vychází z toho i to, že **prázdná ani nečitelná** pozdější sada nálezy
  nesmaže; nečitelná navíc není sada, ale `droppedFindings`.
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
- **Cena běhu je `nil`, ne nula** (#148). `total_cost_usd`, `duration_ms` a `num_turns` jsou
  v tomtéž `result` eventu jako `outcome`, takže je zabitý běh nemá — a nula by tvrdila, že byl
  zdarma. Čte se to stejně defenzivně jako číslo řádku: `true` je `NSNumber`, takže by bez
  kontroly vyšla cena 1 $, a **záporná hodnota se zahazuje**, protože by v denním součtu
  tvrdila, že mě běh vydělal.

### Krok je pokus, dokud nedorazí `tool_result` (#326)

Parser čte od #326 i **`user` eventy**: `message.content[]` v nich nese bloky `tool_result`, tedy
odpovědi na to, o co si model řekl. Do té doby se zahazovaly, takže krok v ose byl hotová věc od
chvíle, kdy ho model ohlásil — a odmítnutý nástroj vypadal jako provedený až do konce běhu.
Zdůvodnění celé změny včetně zamítnutých cest je v záznamu rozhodnutí ve specifikaci.

Co se u toho nemá rozbít:

- **Páruje se `id`, nikdy pořadí ani jméno.** `tool_use.id` nese `ToolAttempt.id`,
  `tool_result.tool_use_id` se hledá proti němu. Jeden `assistant` event umí nést víc `tool_use`
  bloků naráz a odpovědi chodí každá ve svém eventu, takže pořadí neplatí; `Bash` je v běhu
  i padesátkrát, takže jméno neplatí taky.
- **`outcome == nil` znamená „běží“, ne „prošel“.** Zabitá session poslední odpověď nedostane, takže
  poslední krok zůstane pokusem — ne hotový a ne selhaný. Je na to test nad **řezaným** skutečným
  streamem (`review-killed.jsonl` po poslední `tool_use` řádku).
- **Odmítnutí ≠ chyba nástroje.** Rozhoduje `tool_result_meta[].non_execution_kind`
  (`user-rejected` v obou fixtures s odmítnutím), ne text hlášky. `is_error` samo o sobě je běžná
  věc: `grep` bez shody, `Read` neexistujícího souboru. Kdyby z nich byl odznak `ODMÍTNUTO`, znamenal
  by „něco se nepovedlo“ místo „read-only režim zabral“ — a tvrdá podmínka č. 2 by vypadala jako
  porucha. Rozhodnutí drží `Policy.toolOutcome(isError:nonExecutionKind:text:)`.
- **`permission_denials` z `result` zůstává jako záchrana**, ne jako druhá pravda: dopisuje odmítnutí
  jen tam, kde odpověď nedorazila (useknutý event, rozbitý řádek) nebo vyšla jako `failed`. Krok
  zavřený ze streamu se z něj podruhé nezavírá — jinak by osa dostala na jeden krok dvě události.
  Páruje se **jen po `tool_use_id`**; bez něj se nepáruje nic.
- **Kdo koho smí přepsat, rozhoduje `Policy.replacesToolOutcome` — jedna funkce pro tři místa**
  (odpověď ze streamu, záchrana z `permission_denials`, zápis do osy). Nezavřený krok bere cokoli,
  `failed` smí přepsat jedině `denied`, a `passed` ani `denied` se nepřepíšou nikdy. Tři kopie
  téhož pravidla se rozešly hned v prvním kole: osa měla vlastní podmínku „jen nezavřený krok“,
  takže záchrana `failed` → `denied` doputovala do souhrnu, ale do kroku, který se kreslí, ne —
  nálezem Copilota na #394.
- **`deniedTools` #326 zrušilo.** Bylo to pole jmen plněné z `permission_denials`, které v UI
  **nikdo nečetl** (ukázat se dalo jen u kroku, a krok o svém odmítnutí nevěděl) a zabitý běh ho
  neměl vůbec. Odmítnutí nese `ToolAttempt.outcome`, tedy tam, kde se kreslí; druhý seznam by byl
  druhá pravda o tomtéž.
- **Hláška z odpovědi se sráží na řádek a stříhá na `Policy.toolReasonLimit`** (200 znaků). Osa se
  ukládá na disk a čte při každém startu; obsahem odpovědi `Read`u je celý soubor.
- **Trvání kroku počítá osa, ne parser** (`ReviewerTimeline.resolve`) — z rozdílu časů událostí, se
  kterými se osa kreslí. Parser hodiny nemá a `timestamp` ze streamu by byl druhý zdroj času.
  Odmítnutý krok trvání **nedostane**: nástroj neběžel.
- **Odpověď osu neprodlužuje.** `ReviewerTimeline` mění krok, který v ose už je, včetně jeho `id`
  a času — takže se sledování konce ve výpisu (#325) nehne na něco, co krok není.
- **Krok bez `id` nemá značku žádnou** (`Policy.toolStepMark`). Tak vypadají osy uložené před #326:
  `běží…` u každého kroku doběhlého review by tvrdilo víc, než data unesou. Nová pole jsou v souboru
  volitelná, takže starší osy se čtou dál — je na to test nad literálem v tom tvaru, jaký zapisoval
  encoder před #326, a k němu druhý, který hlídá, že se ten tvar pro nespárovaný pokus nezměnil.

### Živý výpis kroků v tabu Průběh (#325)

Druhá vrstva dráhy: pod fázemi visí **okno se stropem a s vlastním scrollem**, u běžícího
revieweera rozbalené. Do #325 byly tytéž řádky pod **zavřeným** rozbalením bez stropu a bez
scrollu, takže se za běhu na to, co reviewer dělá, nedalo koukat — a `Sledovat konec` z #22 zrušilo
#242 s tím, že „s dráhami není co následovat“. Se scrollujícím výpisem je co následovat zase.

Kreslí to `StepFeedView` (`App/Views/`), řádek `TimelineEntryRow` (vlastní soubor od #325),
rozhoduje `Policy` v `App/Policy/StepFeed.swift`. Co se u toho nemá rozbít:

- **Výška okna je obsah do stropu (138 bodů), ne strop od začátku** (`Policy.stepFeedWindow`).
  Strop je tam proto, že rostoucí blok posune všechno pod sebou, a to je přerovnání celého tabu
  několikrát za vteřinu; nad stropem tedy hýbe přibývající řádek jen oknem a dráha nad ním se
  nehne vůbec. **Pod stropem se ale roste** — pevná výška od začátku znamenala u běhu o třech
  krocích okno se dvěma třetinami prázdna, a to je stav, ve kterém každé review začíná (opraveno
  po proklikání #325). Cena je přerovnání pod **prvními osmi** událostmi běhu, ne pod každou
  z tří stovek.

  Tři věci, které u toho nejsou zjevné:

  - **Výška se počítá z dat, ne z přeměřeného obsahu.** Výška obsahu hlášená scrollem se při
    rozvržení mění i naplano (změřeno `1825 → 3505 → 1825` na jedné scéně), takže okno navěšené
    na ni by u nezměněného obsahu poskakovalo o řádek tam a zpět. Počítá se proto z počtu řádků
    a rozměry dodává view (`StepFeedView.metrics`), protože se kreslí tam (#236); hodnota je
    monotónní v počtu řádků, tedy na hranici stropu se zastaví a už se nemění.
  - **O výšce řádku nesmí rozhodovat ikona.** SF Symboly jednu výšku nemají —
    `doc.badge.ellipsis` 15 bodů, `wrench.and.screwdriver` 14, `clock` 12 (změřeno) —, takže
    řádek se zadáním, které nedorazilo celé, byl o dva body vyšší než ostatní a neznámý nástroj
    o jeden. Řeší to `imageScale(.small)` (každý symbol nejvýš 12 bodů, tedy pod výškou řádku
    textu), ne `frame(height:)`: rámec se v `firstTextBaseline` účtuje od dolní hrany, takže
    s ním řádek naopak vyrostl na 16 bodů. Návrh má ikonu menší než text taky
    (`.step .ic { font-size: 10.5px }` proti 11.5px).
  - **`Sledovat konec` ani pilulka `↓ N nových` se nekreslí, dokud není co rolovat**
    (`StepFeedWindow.scrolls`). Nad obsahem, který se vejde celý, obojí slibuje posun tam, kde
    výpis už je — a `Policy.stepFeedAtEnd` u krátkého obsahu vrací `true`, takže by přepínač
    nemohl ani nic přepnout. Zašedle to nejde: zašedlé tlačítko tvrdí „tady se to dělá, jen teď
    ne“, kdežto tady není co následovat. A když se rolovat **přestane** (osa se zkrátila novým
    během), vrací se sledování na zapnuté — jinak by zůstalo vypnuté z minula a po přerostení
    stropu by výpis konec nesledoval, aniž by na to bylo kde přijít.
- **Rozbalení drží tab, ne dráha** (`StepFeedExpansion` v `@State` `ReviewProgressView`). Dráhy jsou
  v `LazyVStack`u, takže `@State` uvnitř `ReviewerLaneView` se odrolováním zahodil a výpis se sám
  zavřel — u běžícího revieweera tedy zrovna tam, kam se člověk díval. Klíčem je jméno skillu, takže
  to **smí** přetéct mezi pull requesty (tatáž úvaha jako u `mutedReviewers`); přepnutím tabu se to
  zapomene a je to v pořádku, protože běžící dráha se rozbalí sama.
- **Automat rozbaluje jen `running`, a jen jednou za běh.** `StepFeedExpansion` má dvě množiny:
  `expanded` (co je rozbalené) a `opened` (u koho už automat proběhl, drží se **jen dokud běží**).
  Bez té druhé by se zavřený výpis běžícího revieweera při každé události otevřel znovu; bez toho
  ořezávání by nový běh téhož skillu (`Pustit znovu`) rozbalení nedostal. **Doběhnutí výpis
  nezavírá** — to by sebralo obrazovku zrovna ve chvíli, kdy je na ni nejvíc důvodů koukat.
- **Sledování konce je `Bool`, ne poloha scrollu** (#252). Offset se nikam nezapisuje; do stavu se
  píše jedině tehdy, když se **změní odpověď** na otázku „je výpis na konci?“ —
  `onScrollGeometryChange` akci při nezměněné hodnotě nespustí (#361), takže je to zápis na přechodu,
  ne z každého snímku (#358). Neukládá se: je to gesto v jednom běhu, ne nastavení, a klíč
  `progressFollowsTail` zrušený u #242 se **nevrací**.
- **Rozhodnutí „obsah narostl“ proti „člověk odscrolloval“ je čistá funkce**
  (`Policy.stepFeedReaction(grew:isAtEnd:isCatchingUp:)`) a je to jediné netriviální místo celého
  sledování. Narostlý obsah shodí „jsem na konci“ na `false` o ten jeden řádek, který se ještě
  nedoscrolloval (změřeno 20 bodů), takže kdyby se z toho vyvozovalo odscrollování, sledování by se
  vypnulo samo první událostí. U narostlého obsahu se proto **jen dohání**; o vypnutí rozhoduje jedině
  změna polohy nad nezměněnou výškou obsahu, a ještě mimo dohánění — výška obsahu se totiž při
  rozvržení mění i naplano (změřeno `1825 → 3505 → 1825` na jedné scéně).
- **Posun se dělá o průchod později (`Task`), a je to změřené.** Posun ve stejném průchodu, ve kterém
  se obsah přerovnal, SwiftUI zahodí: výpis zůstal 20 bodů od konce a nedojel tam ani po pěti kolech
  smyčky. Je to tatáž past jako u fokusu do textového pole (#184) — rozhoduje **počet průchodů, ne
  čas**, takže se nečeká časovačem (a ten je navíc zakázaná třída, #350). Naopak posun navěšený na
  **data** (`id` posledního kroku) doběhl moc brzo, protože řádek ještě nebyl rozvržený.
- **Kolo „posun → přeměření → posun“ zastavují dvě věci:** posun výšku obsahu **nemění** (takže druhé
  kolo skončí u čtení polohy, ne u dalšího posunu) a `scrollTo` se volá jedině se zapnutým
  sledováním.
- **`Sledovat konec` znamená „nejnovější krok je celý vidět“**, ne „scroll dojel na poslední bod
  obsahu“: pod posledním řádkem je `StepFeedView.rowsInset` bodů vzduchu, takže se od dolní hrany
  odečítá — bez toho by se konec nesledoval nikdy.
- **Pilulka `↓ N nových` se počítá z `id`, ne z počtu událostí.** Se stropem počet přestane růst,
  jakmile se osa začne ořezávat, takže by pilulka u dlouhého běhu tvrdila, že nepřibylo nic — a to
  je zrovna ten běh, u kterého se odrolovalo nahoru.
- **Okno má líný seznam**, i když je vysoké nejvýš 138 bodů: prvek, který se nekreslí, se pořád umisťuje
  (#252), a při třech stech krocích je to tři sta umístění při každém přerovnání obsahu.
- **Próza modelu se nekreslí.** Otázka, kvůli které se do `Průběhu` chodí, je „koukal se tam, kam
  měl“, a odpověď na ni jsou nástroje, ne úvahy; v okně se stropem by kroky vytlačila z dohledu.
  Zamítnuté cesty jsou v záznamu rozhodnutí ve specifikaci.
- **Vestavěný terminál to není a nemá být**: řeší **zásah** do běžící session, výpis **sledování**.
  Do výpisu se nedá psát a cesta zpátky do session zůstává `Zkopírovat resume` v hlavičce dráhy.

Změřeno (offscreen render výpisu o 300 řádcích, série střídavě podle #274):

| Co | Do #325 | Od #325 |
|---|---|---|
| složení dráhy z osy o 300 událostech | 0,328 ms | **0,004 ms** |
| jedna událost v otevřeném výpisu | 40,29 / 41,48 ms | **9,25 / 8,91 ms** |

### Souhrn osy a strop na živou osu (#325)

Dvě změny ve `ReviewerTimeline`, obě kvůli tomu, že výpis roste za běhu:

- **Strop 300 platí i na živou osu** (`ReviewerTimeline.entryLimit`, do #325
  `storedEntryLimit`). Do té doby ho měla jen uložená, takže se za běhu držely stovky událostí,
  které po restartu zmizely — a nikde to nebylo napsané. **Vyšší strop pro živou osu by sliboval,
  že se ke krokům dá vrátit; nižší by zahodil kroky, které v souboru zůstanou.** Ořezává se
  začátek, `droppedEntries` roste průběžně (ne až při ukládání) a zkrácení se přiznává **dvakrát**:
  v hlavičce výpisu (vidět i sbalená) a řezem na jeho začátku, tedy na místě, kde ta useknutá část
  byla — tatáž úmluva jako `Policy.logTail` a `ConversationShortfall`.
- **Odvozené údaje se počítají při zápisu** (`ReviewerTimeline.Digest`). `Policy.lanes` skládá dráhy
  při každém překreslení tabu a do #325 u toho prošel osu **osmkrát** (kam se běh dostal, konec,
  poslední nástroj, počet kroků, počet nálezů, čekání na slot, načtený skill, příznak zadání). Je to
  tatáž třída úlohy jako #224.

Tři věci, které u souhrnu nejsou zjevné:

- **Není to druhá kopie osy, je to její souhrn** — a aby se od ní nerozešel, drží ho jediné místo:
  mutující metody `ReviewerTimeline`. Že souhlasí s průchodem polem, tvrdí `TimelineDigestTests`;
  z uložené osy se počítá **jedním** průchodem při načtení a vyjde z něj totéž.
- **Ořezáním se nesmí zapomenout, čím běh prošel.** Strop zahazuje začátek, takže by průchod
  přeživšími událostmi u dlouhého běhu tvrdil, že session nenaběhla a že nálezy nenahlásila — fáze
  dráhy by po třech stech krocích spadly zpátky na `nedošlo na ni`. Souhrn je proto u `reached`,
  `hadQueued`, `reportedFindings`, `finish`, `loadedSkill` a `intentGap` **monotónní**. Naopak
  `toolSteps` a `lastTool` popisují, co je v ose **vidět**, takže se ořezáním zmenšují (`prochází
  kód · 300 kroků` u osy s 218 zahozenými).
- **Odpověď na krok se do souhrnu musí propsat.** Odpověď osu neprodlužuje (#326), takže se souhrn
  nemá čím aktualizovat sám; pozná se podle `id` (unikátní na `tool_use`). Bez toho by věta pod
  dráhou držela krok bez odpovědi a výpis by tvrdil `běží…` nad krokem, který dávno odpověděl.

**`ReviewerTimeline.newestEntry(in:)` #325 smazalo, i s testy.** Bylo to hledání nejnovější události
napříč reviewery pro jeden společný auto-scroll; s výpisem **na revieweera** se každé okno drží svého
konce, takže by to byl stav, který nikdo nečte — a #325 mělo v zadání ho buď použít, nebo smazat.

### Surová session — přepis transcriptu (#327)

Záchranná brzda pod výpisem kroků: sheet, ve kterém je **celý transcript session** přepsaný
k přečtení. Výpis o patro výš odpovídá na „koukal se tam, kam měl“ (jen nástroje); tohle na „proč to
dopadlo takhle“, a odpověď na ni je v tom, co výpis **schválně zahazuje** — próza, `thinking`,
výstupy nástrojů a systémové události.

**Nová datová cesta z toho nevznikla**: `TranscriptLocation` cestu k souboru odvodí z pracovního
stromu a `session_id`, `TranscriptStore` ho umí otevřít (od #97 z něj po pádu čte `ReportFindings`).
Přibyly dvě metody protokolu `TranscriptReading` — `snapshot(ofSession:in:at:)` a
`size(ofSession:in:)` — a k nim přepis (`TranscriptTranscriber`).

| Typ | Co drží |
|---|---|
| `RawTranscript`, `TranscriptEvent` (`App/Models/`) | Snímek okna: události, kolik bajtů se nevešlo, velikost souboru, čas snímku, počet nečitelných řádků |
| `RawTranscriptState` | `loading` / `shown` / `missing` / `unreadable` / `empty(bytes:)` — **tři různá „přepis tu není“** |
| `Policy` (`App/Policy/RawSession.swift`) | Okno, zarovnání na začátek řádku, ořez události a jeho přiznání, nabídka akcí, cíl dráhy, přírůstek |
| `TranscriptTranscriber` (`App/Review/`) | JSONL → události. Používá `ToolAttempt` na detail volání a `Policy.toolOutcome` na odmítnutí |
| `RawSessionScript` (`App/Views/`) | Řádky s **rolemi** → `NSAttributedString` i čistý text pro `Zkopírovat přepis` |
| `TranscriptTextView` (`App/Views/`) | Jeden `NSTextView` se stráží v `Coordinator`u |
| `AppStore+RawSession` | Otevření, `Načíst znovu`, zavření, přeměření velikosti |

#### Proč je jednotkou bajt, ne řádek

Změřeno na 922 transcriptech pod `~/.claude/projects`: medián 271 kB, nad 1 MB 123 souborů, nad
10 MB čtrnáct, největší **53,3 MB při 2 348 řádcích**, nejdelší řádek **7,5 MB**, medián řádku
1 604 B. Z toho plynou oba stropy:

- **Okno je posledních 4 MB** (`Policy.rawSessionWindowBytes`). Ocas o 6 000 řádcích, kterým se
  ořezává log jobu (`Policy.logTailLines`), by na 2 348 řádcích nezabral vůbec — „ocas“ by byl celých
  53 MB. A protože je soubor **lokální**, čte se `seek`em od konce, takže **stav „moc velký“ nevzniká
  vůbec**; u logu checku ho vynutila síť (`Range` přes `gh` se na redirect nepřenese, změřeno u #214).
- **8 kB na jednu událost** (`Policy.rawSessionEventBytes`). Jeden `tool_result` umí mít 7,5 MB, takže
  by bez druhého stropu sežral celé okno a z ocasu session by byl výpis jednoho souboru.

**Počet událostí celého souboru se netvrdí**, a je to vědomá odchylka od mockupu (`2 913 událostí ze
4 117`): zjistit ten druhý počet znamená přečíst celý soubor, tedy zaplatit tu cenu, kvůli které okno
existuje. Hlavička proto říká, kolik událostí je **v okně** a jak velké okno je.

#### Zkrácení se přiznává třikrát

V hlavičce (`konec souboru, N událostí z posledních 4 MB`), **řezem na začátku textu** a u ořezané
události **na místě řezu**. Tiše zkrácený přepis tvrdí, že session začala uprostřed — tatáž úmluva
jako u `Policy.logTail`, `ConversationShortfall` a osy běhu.

Ořez události se hlásí **v řádcích pod megabajt a v bajtech nad ním**: nad megabajtem počet řádků
přestává být míra toho, kolik toho chybí (7,5MB `tool_result` je jeden řádek). Po řezu **uprostřed**
řádku se hlásí vždycky bajty — zbytek začíná půlkou řádku, takže by se počítal jako celý.

#### Odmítnutí se v transcriptu pozná jinak než ve streamu

**A bylo to potřeba změřit, ne odvodit.** První podoba hledala `non_execution_kind` (tvar ze
`stream-json`), takže `Policy.toolOutcome` dostala `nil`, z odmítnutého `Bash`e byl obyčejný `failed`
a odznak `ODMÍTNUTO` by se nad skutečnými daty **neobjevil nikdy** — nálezem Copilota na #408.

Co v transcriptu doopravdy je (ověřeno na souboru se **skutečným** odmítnutím, vyrobeným spuštěním
`claude -p` s `--disallowedTools 'Bash(wc:*)'`):

| Klíč | Kde | Hodnota |
|---|---|---|
| `non_execution_kind` | nikde | 0 výskytů |
| `toolDenialKind` | na **řádku** `user` (v bloku `tool_result` je `null`) | `user-rejected` |
| hláška | v `content` bloku | `Permission to use Bash with command … has been denied.` |

Ta hláška je navíc **jiná** než ve streamu (`Claude requested permissions … yet.`), což je druhý
důvod, proč se odmítnutí nesmí poznávat podle textu — a přesně to říká #326.

**Rozhodnutí zůstává v `Policy.toolOutcome`**: transcriber jen dodá, z čeho se pozná. Dvě různá
pravidla pro jeden odznak by znamenala, že se pod ním v ose a v přepisu skrývá něco jiného.
`tool_result_meta` se přitom čte dál — je to tvar, který CLI píše do streamu, takže kdyby ho přidalo
i do souboru, rozhodne se stejně.

**Jak se to poznalo, ať to příště nikoho nestojí kolo:** dřívější tvrzení „CLI to do souboru nepíše“
se opíralo o `grep` nad transcripty z review, ve kterých ale **žádné odmítnutí nebylo** — tedy o
soubory, ve kterých nebylo co psát. Doklad je až soubor, ve kterém odmítnutí je.

#### Čtyři věci, které nejsou zjevné

- **Okno se zarovnává na začátek řádku, ale ne za každou cenu.** První řádek ocasu je obvykle zbytek
  řádku, jehož začátek leží před oknem, takže se zahodí. **Když ale za prvním zakončením už nic není**
  (řádek delší než celé okno — ten změřený případ 7,5 MB), nezahodí se nic: zbyde jedna **nečitelná
  událost**, a ta aspoň ukáže, co v souboru stojí. Prázdný sheet nad souborem, ve kterém něco je, by
  byl horší. Hledá se `LF` **i `CR`** a `CRLF` se spotřebuje celé — dělení řádků drží `TextLines`
  a to zná všechna tři zakončení (#295); s jedním `LF` by transcript s `CR` začínal uprostřed záznamu.
- **Čte se o jeden bajt víc — ten před oknem.** Je to sonda na hranici řádku: když `fileBytes − 4 MB`
  padne přesně na začátek řádku, není co zahazovat, a „první zakončení v okně“ by sebralo celou
  **první událost** a `omittedBytes` by tvrdil větší zkrácení, než nastalo (nálezem Copilota na #408).
  S tím bajtem je odpověď v datech, ne v úvaze, a `omittedBytes` zůstává `offset + zahozeno`.
- **Dvě čtení téhož cíle se od sebe poznají generací, ne cílem.** Dvě kliknutí na `Načíst znovu`
  znamenají dvě čtení, a to pomalejší z nich by po `await`u přepsalo novější — brána „je to pořád
  tenhle cíl?“ by přitom byla pravda (taky nálezem Copilota na #408). Generace je číslo, které se
  zvýší s každým čtením a kontroluje se i u tiku velikosti.
- **`String(data:encoding:)`, ne `String(decoding:as:)`.** Ten druhý nikdy neselže — vadné bajty
  nahradí `U+FFFD` —, takže by se ze stavu „soubor nemá platné UTF-8“ stal přepis s otazníky
  a `Ukázat v Finderu` by v okně nebylo. Rozpůlený znak na začátku okna se přitom **nesmí** za vadné
  UTF-8 vydávat, proto se z něj zahazují pokračovací bajty (`Policy.rawSessionPrefixDrop`).
- **Nečitelný řádek se nezahazuje, stane se z něj událost.** Poslední řádek rostoucího souboru je
  běžně rozepsaný; tiše spolknutý řádek vypadá jako řádek, který v transcriptu nebyl. Souhrnný počet
  je vedle toho v hlavičce, protože „ze čtyř set jich je nečitelných dvě stě“ je tvrzení o tom, jak
  moc se dá přepisu věřit.
- **Snímek drží store a je jeden**, ne slovník: sheet je v okně nejvýš jeden a snímek má megabajty.
  Zavření sheetu i přepnutí PR ho zahodí — jinak by to byla paměť, kterou nikdo nečte.

#### Sazba: třetí AppKitové view, a proč

`RawSessionScript` skládá **řádky s rolemi** a z nich obojí — `NSAttributedString` do
`TranscriptTextView`u i čistý text pod `Zkopírovat přepis`. Jedna pravda schválně: dvě samostatná
skládání téhož se rozešla hned první podobou, kde vysázená hlavička neměla mezery a v kopii je měla
(`23:13:36Bashgh pr view 412`), a chytil to **render, ne test** — proto je `RawSessionScript.gap`
jedna konstanta a testuje se, že `attributed(…).string == plain(…)`.

Proti dvěma AppKitovým views, které v repu už byly, se to liší takhle:

| | `LogTailTextView` | `SelectableCodeView` | `TranscriptTextView` |
|---|---|---|---|
| zalamuje | ne (dvě osy scrollu) | ano | **ano** |
| otevírá se na | konci dokumentu | začátku | **začátku okna** (okno *je* konec) |
| atributy | jedna barva na celý text | obarvení podle jazyka | **role hlavičky události** |
| stráž v `updateNSView` | ano (#292) | ne — **změřeno** (#417) | **ano** |

**Zalamování je vědomá odchylka od návrhu**, který má u těla události `white-space: pre`. V jednom
textovém kontejneru nejde mít zalamované odstavce vedle nezalamovaných (`lineBreakMode` v odstavci
text neuzalomí, ale **usekne**), takže se vybírá mezi „próza uteče doprava“ a „dlouhý řádek výstupu
zabere víc řádků sazby“. Próza je to, kvůli čemu se sem chodí, a strop 8 kB drží zalomený výstup
v mezích.

**Stráž tady být musí, a je to konkrétní pohon, ne pojistka** (#393): patička se každé dvě vteřiny
ptá na velikost souboru, takže se `body` sheetu přepočítá i nad nezměněným přepisem — bez stráže by
se při každém tiknutí sázely znovu megabajty. Klíčem je **celý snímek**, ne jeho hash (hodnota leží
v grafu, takže `Array.==` skončí na identitě úložiště), plus barevný režim. **Šířka v klíči není**, na
rozdíl od `DiffBlockDrawing`: přepis si o vlastní velikost neříká (`sizeThatFits` nemá) a zalamuje ho
`widthTracksTextView`, takže se při změně šířky nesází znovu — a přesázení by zrušilo rozdělaný výběr.

#### Sheet se dá roztáhnout a velikost si pamatuje

Otevírá se na **1 180 × 760** (podlaha 720 × 420, obojí `Policy.rawSessionSheet*`), dá se **táhnout
za okraj** a natažená velikost přežívá restart (`@AppStorage`, tatáž konvence jako u šířky panelu
nálezů). Tři věci na tom stojí a všechny jsou **změřené na skutečném okně sheetu**
(`RawSessionSheetSizingTests`, ověřené i vloženou regresí):

- **Roztahovatelný sheet na macOS 26 jde** — potřebuje `presentationSizing(.fitted)` a pružný rámec
  (`maxWidth`/`maxHeight` `.infinity`). Teprve pak dostane okno sheetu `.resizable` do `styleMask`u
  a `minWidth`/`minHeight` se v něm objeví jako `contentMinSize`. Padla s tím i domněnka, kterou měl
  v komentáři `CodeTextSheet` („sheet není roztažitelný myší“).
- **Bez `.fitted` se `idealWidth` zahodí a sheet je široký jako `minWidth`.** Do téhle změny byl tedy
  přepis 720 bodů široký, ne nakreslených 940 — a nerozhodovalo o tom okno za ním (změřeno i nad
  oknem 2 000 bodů). Je to **třída, ne výskyt**: `CodeTextSheet` (log a hunk) měl min 560 a ideál
  spočítaný z obrazovky až 2 700, takže se v něm celé měření #292 neuplatnilo. **Druhý výskyt je
  opravený u #417** (sekce 28 návrhu) — tady se tehdy neopravoval proto, že je to jiná obrazovka,
  a ta spadá pod schvalovací bránu na vzhled.
- **Sheet se rozvrhuje dvakrát a v prvním průchodu má podlahu.** Zápis naměřené velikosti bez odmlky
  by proto při každém otevření uložil 720 × 420 a od druhého otevření by se sheet otevíral nejmenší
  možný. Zahazuje ten mezistav `RawSessionSheet.resizeSettle` (400 ms) — je na to test, který tvrdí,
  že otevřením a zavřením se **neuloží nic**.

Ukládá se **jen to, co se liší od velikosti, se kterou se sheet otevřel** (`Policy.rawSessionSheetResize`,
tentýž tvar jako `Policy.hoverChange`): velikost, o kterou si aplikace řekla sama, není volba
uživatele, takže by jejím uložením přestala výchozí velikost vycházet z obrazovky. Uložená hodnota se
ořezává **při použití** o okraje obrazovky — natáhne se na ultrawide a otevírá na notebooku, a SwiftUI
sám neclampuje nic (AppKit jen výšku ke hraně obrazovky: 1 040 požadovaných → 917 daných, změřeno).

Výchozí šířka **není od oka**: přepis zalamuje, takže ze 720 na 1 180 bodů ubude nad skutečným
transcriptem (2,8 MB, 432 189 znaků, 5 236 logických řádků) **15 % řádků sazby**, tedy 2,4 řádku na
každý bod šířky; dál je to 0,8 (do 1 600) a 0,37 (do 2 400). Celá tabulka je u
`Policy.rawSessionSheetIdealWidth`, měřidlo v `RawSessionMeasurement.wrappingByWidth`.

#### Cena, změřená (`RawSessionMeasurement`)

Debug build, syntetický transcript podle skutečného rozdělení. **Otevření je konstantní ve velikosti
souboru**, což je to hlavní tvrzení:

| Soubor | Snímek (čtení + přepis) |
|---|---|
| 1 MB (celý) | 84 ms |
| 8 MB (okno 4 MB) | 331 ms |
| 53 MB (okno 4 MB) | **312 ms** |

Rozpad té ceny je ale poučnější než čísla sama: **rozbor JSONu stojí 6,9 ms**, kdežto dělení textu na
řádky **216 ms** — tedy ta jediná věc, která jde nad megabajty po `Character`ech (`TextLines`, kvůli
`CRLF`, #295). Bez rozpadu se optimalizovalo naslepo: ořez těla po znacích vypadal jako ta drahá věc
(osm tisíc alokací `String`u na událost) a jeho odstranění nezměnilo **nic** (627 → 627 ms). Ubralo se
proto tam, kde cena doopravdy byla — dělit se přestalo celé tělo a celý zbytek, jen `limit` bajtů:
**428 → 108 ms** za `transcribe`, a s tím 655 → 312 ms za celý snímek.

Sazba přes celé okno stojí `lines` 1,6 ms, `attributed` 12,6 ms a `setAttributedString` 5,9 ms
(1,54 milionu znaků), takže hlavní vlákno zdrží jednotky milisekund. Čtení běží mimo něj
(`TranscriptStore` je `nonisolated`), sheet se otevírá hned se stavem `loading`.

**Jedno tažení za okraj stojí 2,61 ms na krok** (12 bodů, 1,55 milionu znaků přepisu, včetně kresby
viditelného výřezu; celé tažení o dvaceti krocích 52 ms). Drží to stráž se šířkou **mimo klíč**: kdyby
se přesázelo, byl by v každém kroku ten `attributed` + `setAttributedString`, tedy 18,5 ms — a jednou
za tažení se navíc zapisuje velikost do `UserDefaults`, ne pokaždé (odmlka výš).

Co se **nepodařilo zlevnit**, ať to příště nikdo nezkouší znovu: dělení okna na řádky. Šlo by to jen
druhou cestou dělení textu — a jedno místo, kde se rozhoduje, co je řádek, je pravidlo, které stojí
za víc než dvě desetiny sekundy v Debug buildu.

### Živá session v terminálu (#453, přepojeno na zásuvku #460)

Vedle `⧉` (`Zkopírovat resume`) stojí v hlavičce dráhy `▶` — **`Pustit session v terminálu`**,
které vytáhne **zásuvku** (#459), **přepne na relaci té dráhy**, přejde v ní do **pracovního
stromu** té session a pustí tam tentýž příkaz — od #460 i s režimem povolení (`--permission-mode
auto`, viz níž). Návrh je sekce 35, poznámka 112; sekce 34 zůstává záznamem toho, co
bylo dřív. Kopírování zůstává, protože kdo si session pouští jinde (iTerm, tmux, jiný stroj),
potřebuje text, ne cizí plochu.

**Do #460 se tím otevíralo okno `Terminal.app`** a tvrdá podmínka č. 1 se u toho nehnula, protože
terminál byl mimo aplikaci. Od #459 je terminál **v okně** a ta záruka je vyměněná za funkci
(viz *Vestavěný terminál (#459)* níž), takže odcházet do cizí aplikace kvůli session, která se dá
pustit o kus níž, přestalo mít důvod. `grep ReviewPublishing App/` vypisuje pořád **týž seznam**
a `SingleWayOutTests` procházejí beze změny — cesta ven ze shellu nevede přes kód aplikace, což
říká kapsle `plná práva` v hlavičce zásuvky.

Sedm věcí, které na tom nejsou zjevné:

- **Pracovní strom je podmínka stejně jako `session_id`**, i když zadání mluví jen o `id`.
  `claude --resume` hledá vlákno podle adresáře, ve kterém se spustí
  (`~/.claude/projects/<zakódovaná cesta>/`), takže **tentýž příkaz jinde session nenajde** —
  otevřelo by se okno, ve kterém `claude` řekne, že takové vlákno nezná. „Nabízí se to jen tam,
  kde je co obnovit“ tedy platí doslova, a je to tatáž dvojice podmínek jako u `Ukázat session`
  (`Policy.rawSessionTarget`). Rozdíl není teoretický: dráha z uloženého běhu **bez osy** zná
  `session_id` a strom ne (soubory z doby před #203). Rozhoduje `Policy.terminalSession(of:)`,
  ne `if` ve view, a **zašedlé tlačítko to není** — u dráhy, která teprve čeká na slot, by
  slibovalo něco, co přijde samo.
- **Příkaz skládá jedno místo** (`Policy.resumeCommand(sessionID:)`) — kopíruje ho `⧉` a pouští
  `▶`. Dvě kopie by se rozešly první úpravou a rozdíl mezi „co mám ve schránce“ a „co se mi
  otevřelo“ se nedá poznat jinak než tím, že jedno z toho nefunguje.
- **`&&`, ne `;`** (`TerminalSession.shellLine`): pracovní strom umí zmizet (úklid cache,
  eviction), a `claude --resume` spuštěný místo něj v domovském adresáři by odpověděl větou
  **o session**, ne o adresáři. S `&&` zůstane v okně `cd: no such file or directory`, což je
  pravda a dá se podle ní jednat. Uzávorkování cesty dělá `ShellQuoting` — od #453 **jedno
  místo**, protože totéž potřebuje `ClaudeCommand.shellCommand` pro `Zkopírovat příkaz`.
- **Selhání se hlásí ve stavovém řádku** (`AppStore.terminalFailure` → `AppNoticesView`).
  Je to tentýž případ jako notifikace (#88): výsledek téhle akce v okně **není vidět** — do #460
  proto, že se okno otevíralo mimo aplikaci, od #460 proto, že v zásuvce zůstalo všechno tak, jak
  bylo —, takže neúspěch vypadá k nerozeznání od toho, že se nekliklo; `try?` nad tou cestou by
  z tlačítka udělal něco, co občas nedělá nic. U `Terminal.app` se důvod **opisoval doslova** z toho,
  co řekl systém (`Not authorized to send Apple events to Terminal.`), protože se to spravuje
  v Nastavení systému, kam aplikace nedosáhne. Hláška se zahodí teprve tehdy, když se to
  **doopravdy** povede, ne při dalším kliknutí.
- **Do běžícího jobu se nepíše** (#460). Řádka poslaná do shellu je pro program, který v něm běží,
  **vstup** — v rozdělaném `claude` by z `claude --resume …` byla odeslaná zpráva a ve `vi`
  posbírané příkazy. `EmbeddedTerminalView.hasForegroundJob` se proto **jedním** voláním zeptá
  jádra na popředí pty (`tcgetpgrp`, tedy totéž, co dělá `kill()`), a když tam někdo je, `▶` vrátí
  `busy` a **nepošle nic**. Není to ten pravidelný takt, kvůli kterému kapsle v hlavičce neukazuje
  běžící příkaz: ptá se to ve chvíli kliknutí, ne v časovači. **Slepá ulička z toho ale není**:
  zásuvka se na tu relaci **přepne**, takže je vidět, co v ní běží.
- **Posílá se celá `shellLine`, i do zásuvky** (#460), tedy `cd '<strom>' && claude --resume <id>
  --permission-mode auto`.
  `cd` není nadbytečné ani u vlastní relace: `▶` umí přijít i na relaci, která už existuje a stojí
  jinde (starší strom téže dráhy), a `claude --resume` hledá vlákno **podle adresáře**. Cesta v hlavičce zásuvky se proto po `▶` přepisuje na strom té
  session — a to **i po `noShell`**, i když řádka neodešla: bez cesty kreslí zásuvka větu
  *Tenhle pull request nemá v cache pracovní kopii*, a ta by po nepovedeném startu **lhala**
  (strom na disku je, nepovedl se shell). S cestou je v hlavičce pravda o tom, odkud se startovalo,
  a kapsle řekne `skončil` — tentýž stav, jaký v zásuvce zbyde po `exit`. Po `busy` se naopak
  **nepřepisuje**: tam se plocha nestavěla a shell dál stojí tam, kde stál.
- **`▶` si nebere fokus** (#460). Sebrat ho znamená sáhnout na první responder v tomtéž průchodu,
  ve kterém se plocha teprve staví — past z #184, kterou jde ověřit jedině na běžící aplikaci.
  Kliknout do zásuvky je proti tomu jeden klik.

## `ReviewRunner` (`App/Review/`)

Jeden běh = jedna headless session `claude` na jeden skill v jednom pracovním stromě.

| Typ | Co je |
|---|---|
| `ReviewRunning` | Protokol: `run(_:progress:)`. Schválně nemá nic, čím by šlo něco odeslat |
| `ClaudeReviewRunner` | Implementace nad `claude` přes `ProcessStreaming` |
| `ReviewRequest` | Zadání: klíč, pracovní strom, `baseSha` (proti čemu diffovat), `promptTemplate` z nastavení (#281), `timeout` z nastavení (#320), `intentFile` se zadáním PR (#120); u kontroly nálezů (#150) navíc `recheck: RecheckMaterial?` |
| `ReviewIntentStore` | Zadání PR uložené **vedle** pracovního stromu (#120). Bez protokolu, jako `ReviewStore` — v testech se nahrazuje kořenem cache, ne fakem |
| `ReviewRunKey` | `(PR, headSha, skillID, kind)` — identita běhu; `kind` je `review` / `recheck` (#150) |
| `RecheckMaterial` | Vstup kontroly (#150): commit, na kterém nálezy vznikly, a nálezy v pořadí, ve kterém se na ně ptáme |
| `RecheckCommand` | **Čisté funkce**: prompt kontroly a defenzivní čtení její odpovědi (#150) |
| `ReviewRun` | Výsledek: klíč, `StreamSummary`, `ReviewRunOutcome`; `findings` doplní reviewera a `headSha` |
| `ReviewRunOutcome` | `finished` / `timedOut` / `failed(detail:)` |
| `ReviewProgress` | `queued`, `started(sessionID:)`, `attemptedTool(ToolAttempt)`, `findings(count:)` |
| `ToolAttempt` | Pokus o nástroj: jméno a to, nad čím běžel; umí se zkrátit proti pracovnímu stromu |
| `ReviewerTimeline` | Časová osa jednoho revieweera pro tab Průběh — události s časem, `sessionID`, pracovní strom |
| `ReviewSlots` | Aktor: limit souběžných session (3), fronta v pořadí příchodu |
| `ClaudeCommand` | Čisté funkce: argumenty, prompt, prostředí session |
| `TranscriptLocation` | **Čistá funkce**: kde `claude` vede transcript session (#97) |
| `TranscriptReading`, `TranscriptStore` | Přečte transcript zabité session a udělá z něj `StreamSummary` |

Věci, které se u toho nemají rozbít:

- **Selhání session není chyba volání.** Spadlá i vytimeoutovaná session se vrací jako
  `ReviewRun` s příslušným `outcome`, protože obojí je výsledek, který se zobrazuje.
  Vyhodí se jen `CancellationError`. Kdyby selhání létalo jako chyba, `clean` a `failed`
  by se v UI slily do jednoho „nepovedlo se“.
- **Timeout si nechá, co stihl.** Proto se stream čte průběžně a `StreamSummary` se plní
  po řádcích: u zabitého běhu jsou částečné nálezy jediné, co je. Nastavitelný limit (#320) na
  tom nemění nic — mění se jen číslo, po kterém se zabíjí.
- **Časový limit je v nastavení a putuje s požadavkem** (#320, `ReviewTimeout` v `App/Policy/`).
  Do #320 to byla konstanta `ClaudeReviewRunner.defaultTimeout`; teď je to
  `GlobalConfig.reviewTimeoutMinutes` s override per repo, a runner **žádné vlastní pole nemá** —
  bere `request.timeout`. Pět věcí, které se u toho nemají rozbít:
  - **Běh doběhne s limitem, se kterým začal.** Skládá se v `AppStore` jednou pro celý běh
    (`resolved(for: pr.repo).reviewTimeout`), takže uložené nastavení uprostřed review session
    nezkrátí. Je to tatáž úvaha i tentýž mechanismus jako u šablony promptu.
  - **Meze jsou bezpečnostní, ne kosmetické.** 5–60 minut, „bez limitu“ **není volba**. Timeout je
    jediná pojistka proti session, která se zacyklí — `autoRunsPerDay` a `maxConcurrentReviews`
    omezují **počet** běhů, ne délku jednoho. Čísla i jejich odůvodnění (naměřená doba běhů, cena
    za minutu, vazba stropu na denní limit) jsou v dokumentačním komentáři `ReviewTimeout`.
  - **Sráží se na jednom místě, a až při použití.** `Configuration.resolved(for:)` přes
    `Policy.reviewTimeout(minutes:)`. V konfiguraci zůstane **syrová hodnota**, protože jen tak jde
    rozlišit „napsal jsem 120“ od „mám 60“ — a nastavení to pod polem pojmenuje
    (`Policy.reviewTimeoutProblem(in:)`).
  - **Kontrola nálezů (#150) má tentýž limit.** Je to tatáž session, tentýž pracovní strom a tytéž
    peníze; kdo limit zvedá u pomalého repa, zvedá ho kvůli tomu repu, ne kvůli jednomu ze dvou
    druhů běhu. Že kontrola v praxi trvá kratší dobu, nic nemění: nevyčerpaný strop nestojí nic,
    kdežto vlastní kratší strop by z pomalé kontroly udělal `timedOut`.
  - **Překladač nálezů (`ClaudeFindingTranslator`, 120 s) zůstává natvrdo.** Není to opomenutí:
    uvažuje se o tom, že se jazyk nálezů přesune do promptu review a překladač **zanikne**, takže
    nastavení pro něj by se za chvíli zahazovalo. A je to jiný druh běhu — krátké volání bez
    pracovního stromu, kde delší limit nic nezachrání.
- **Číslo limitu v UI u výsledku běhu nestojí** (#320) — ani u `timedOut`. Uložený běh limit
  **nenese**, takže by se dalo napsat jedině to, co je nastavené *teď*, a to je o starším běhu
  nepravda. Přidat ho do `StoredReviewRun` by znamenalo, že u všech dosavadních záznamů je `nil`
  a stejně by se muselo psát „neznámý limit“; hodnota za to nestojí. Kde se limit **říct dá**, je
  nastavení, protože tam je to tvrzení o příštím běhu.
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
- **Prompt se skládá ze šablony a jádra** (#281, `ReviewPromptTemplate` v `App/Policy/`).
  Psaná půlka je v konfiguraci (`GlobalConfig.reviewPrompt`) a **putuje s požadavkem**, ne se
  čte v runneru: běh má doběhnout s tou šablonou, se kterou začal, i kdyby se během něj uložilo
  nastavení. Jádro (`ReportFindings` i s prázdným seznamem, zákaz zápisu a odesílání, přebití
  skillu) připojuje `Policy.reviewPrompt` **vždycky**, takže se ze šablony nedá vyhodit.
  Tři věci, které se u toho nemají rozbít:
  - **Jádro není bezpečnostní opatření.** Tvrdou podmínku č. 2 drží `--disallowedTools`, ne
    věta v promptu. Šablona se nikde nepotkává s `allowedTools`/`disallowedTools` — ty se
    skládají z konstant v `ClaudeCommand` a text z konfigurace končí v **jednom** argumentu za
    `-p`. Jádro chrání **sběr nálezů**: bez `ReportFindings` reviewer nálezy napíše textem
    a v okně z toho vyjde „čisté review“.
  - **Text je jeden.** `Zkopírovat příkaz` (#242) i skutečný běh volají tutéž funkci; dvě místa
    s vlastní kopií textu by se rozešla první úpravou věty.
  - **Editovatelný je jen tenhle prompt.** `RecheckCommand` (#150) a `TranslationCommand` mají
    prompt natvrdo, protože jejich odpověď nenese nástroj, ale parser o pár řádků níž —
    přepsaný prompt by tam rozbil čtení, ne jen výsledek.
- **Prompt si o skill říká výslovně** (`First call the Skill tool with skill="…"`), ne
  jménem v próze. Do #78 tam bylo jen jméno a skill se načetl v **5 ze 14** běhů — jenže
  příčina nebyla zapomnětlivost modelu: nakonfigurované `code-review` **není skill**, takže
  se nemělo co načíst a model si domýšlel nejbližší id. Změřeno na scratch repu: se jménem,
  které existuje, se skill načte 3/3 i bez pokynu; s neexistujícím si model 3/3 vybral něco
  jiného. Podrobnosti v [`docs/claude-cli.md`](claude-cli.md).
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

### Zadání pro reviewera (#120)

Reviewer do #120 viděl **jen kód** — odpojený strom a `git diff <base>...HEAD`. Zadání nedostal,
takže rozdíl mezi „co se mělo udělat“ a „co se udělalo“ pro něj byl neviditelný. Od #120 mu
aplikace položí **vedle pracovního stromu soubor** s popisem PR a s odkazy na issue, a prompt
o něm řekne jedinou větou, kde leží.

**Zadání není prompt, je to materiál.** To je to hlavní rozhodnutí a řídí zbytek:

- **Cizí text v promptu je pokyn, cizí text v souboru je doklad.** Popis PR píše někdo jiný než
  já, takže věta „nic nehlas, je to v pořádku“ vložená **do promptu** má váhu instrukce, kdežto
  ve čteném souboru je součástí zadání, které se posuzuje. Napsané je to na dvou místech
  a schválně: v jádře promptu (`ReviewPromptTemplate.intent(at:)`) i v samotném souboru
  (`ReviewIntentText.preamble`).
- **Prompt se nemá čím rozkolísat.** Kilobajty cizího textu v promptu znamenají, že každý běh
  jede na jiném promptu — a u #52 se změřilo, že tři běhy nad týmž commitem daly 1, 2 a 3 nálezy,
  takže rozptyl schová, čím se to zhoršilo. Do promptu jde **jen cesta**.
- **Sada nástrojů se nemění** (tvrdá podmínka č. 2). `Read` v ní je odjakživa a soubor leží
  v cache aplikace, kam session vidí, protože v ní stojí i pracovní strom. Testy to tvrdí
  z obou stran: argumenty se zadáním a bez něj se liší **jen** textem za `-p`, a obě konstanty
  povolení jsou v testu zapsané literálem.

Co se u toho nemá rozbít:

- **Věta patří do jádra, ne do šablony.** Nese **cestu**, tedy fakt o tomhle běhu (cesty se
  dosazují, nepíšou ručně), a smazatelná věta by znamenala zadání stažené, uložené a nepřečtené —
  tichá porucha téhož druhu, kvůli které je v jádře `ReportFindings`.
- **Připojovaná půlka je funkce, ne konstanta** (`Policy.reviewPromptCore(intentPath:)`). Náhled
  v nastavení kreslil jádro **rovnou z konstanty `core`** a `Policy.reviewPrompt` nevolal vůbec,
  takže nová věta by v náhledu nebyla vidět a nikdo by si toho nevšiml. Teď volají obě cesty tutéž
  funkci — jedna pravda o jednom textu. Ukázková cesta v náhledu je pevná
  (`ReviewPromptTemplate.sampleIntentPath`), ze stejného důvodu jako `sampleSkillID`.
- **`Policy.reviewPrompt` nemá na `intent` default.** S `= nil` by obě dnešní volání
  (`ClaudeCommand.prompt(for:)` i `shellCommand(...)`, tedy tlačítko `Zkopírovat příkaz`) zůstala
  zelená a věta by se nepřipojila **nikdy**. Bez defaultu to překladač vynutí na obou.
- **`Zkopírovat příkaz` se ptá disku, ne záznamu** (`ReviewIntentStore.existingFile`). Tlačítko
  skládá příkaz, jakým by se reviewer spustil *teď*, takže věta o zadání do něj patří právě tehdy,
  když by ten soubor dostal i skutečný běh — jinak by zkopírovaný příkaz posílal reviewera na
  smazaný soubor.
- **Prompt nikdy neukazuje na soubor, který neexistuje.** `Policy.intentBrief` vrátí `nil`, když
  se nesehnalo nic (prázdný popis bez jediného odkazu), a tehdy se nezakládá nic a věta se
  nepřipojí. Ověřuje to test na obou koncích — `intentFile == nil` v požadavku a chybějící soubor
  na disku.
- **Prázdný popis a nedotažený popis jsou tatáž hodnota** (`PullRequest.body` je neoptional
  `String` s defaultem `""`), takže se do souboru **nepíše, které z toho to je**. V cestě review
  se nedotažený vyskytnout nemůže — `fetchDetail` by vyhodil a review by se nespustilo —, ale
  jistota to je jen tam, ne v modelu; věta v souboru (`ReviewIntentText.noDescription`) proto
  přiznává, že to rozlišit neumí. Rozlišení přijde s #345, kde se zadání skládá z víc zdrojů
  a každý si nese svůj výsledek.
- **Chybějící sekce se nevynechává mlčky.** Soubor má tři pojmenované sekce (popis PR, odkazy,
  text issue) a do #345 byla ta poslední prázdná **vždycky** — s větou, že se text netahá
  a identifikátory jsou jen ukazatele. Bez ní by reviewer nepoznal rozdíl mezi „issue nic neříká“
  a „text issue se sem nedostal“.
- **Odkazy se normalizují na kanonickou adresu bez slugu**, a dedup je podle **identifikátoru**.
  Tentýž issue přijde v popisu jako markdownový odkaz se slugem a v linkbacku od Linearu bez něj
  (ověřeno na `zcash/zcash-swift-wallet-sdk#1893`), takže dedup nad doslovným textem by
  z jednoho issue udělal dva. Vytahuje se **jen Linear**, protože jen u něj je z adresy vidět
  identifikátor issue — GitHubové `#123` ukazuje na sousední PR téhož repa, který reviewer
  v pracovní kopii má.
- **Nepovedené zadání review nepoloží, ale mlčí se o něm ne.** Zápis se vyhazuje z
  `ReviewIntentStore.save`, `AppStore.prepareIntent` z toho udělá `intentFailure` a review běží
  dál bez zadání. `try?` by znamenal běh, který zadání nedostal, a v okně nic — přitom takový běh
  vypadá **úplně stejně** jako ten, který ho dostal.

**Příznak na ose (tab `Průběh`) tohle issue vědomě nedostalo** a přinesl ho #345. Důvod byl, že
v téhle části může selhat **jedině zápis do vlastní cache** — a to ve chvíli, kdy o pár řádků výš
prošlo vytvoření pracovního stromu, tedy nesrovnatelně větší zápis do téže složky. Odznak, který se
rozsvítí jen nad rozbitým diskem, je UI pro stav, který nenastává; kdežto #345 přináší tři tvary
selhání, které nastávají běžně (chybějící MCP server, server, který nejde spustit, nepovolený
nástroj), a **tam se ten odznak vyplatí**. Druhý důvod byl návrhový: `loadedADifferentSkill` je fakt
**o jedné session**, kdežto zadání je jedno pro celý běh, takže „jak jeden fakt vypadá na N
dráhách“ je rozhodnutí, které patřilo k případu, kde si ho něco vynutí. Zápis do cache hlásí
`AppNoticesView` ve stavovém řádku dál (`intentFailure`), jako `draftFailure` nebo
`dismissalFailure` — příznak na ose ho **nenahrazuje**, protože je to jiná porucha.

### Text issue a komentáře pod PR (#345)

Druhá polovina #120. Odkazy na zadání se od #345 hledají **i v komentářích pod PR** a jejich text se
**dotáhne krátkou `claude -p` session**. Rozhodnutí o ceně (uživatel, 2026-08-17): **tahá se
vždycky, i v automatickém režimu** — $0,18 (sonnet) až $0,31 (opus-5) a ~20 s na review. Zvažovalo
se omezit to na ručně spuštěné review nebo u automatu vynutit `sonnet`; zamítnuto, protože zadání
vedle diffu je důvod, proč funkce existuje, a automat je zrovna ten režim, u kterého se člověk dívá
až na hotový výsledek.

**Rozlišit „issue nic neříká“ od „nestáhlo se“ je jádro, ne detail** — a je to jediná věc, kvůli
které je ta session postavená jinak než překlad nálezů. Průzkum naměřil **tři tvary selhání a dva
z nich vypadají jako úspěch**; jediný strojově čitelný signál je `init.mcp_servers[].status`, který
se dá přečíst **jedině ze streamu**. Tabulka tvarů, fixtures i ceny jsou
v [`docs/claude-cli.md`](claude-cli.md), sekce *Dotažení textu issue*.

Kudy to teče:

| Vrstva | Co drží |
|---|---|
| `IntentTextFetching` + `IntentTextResult` | Protokol se **jednou** metodou, která bere odkazy a vrací texty. Z typu je vidět, že to umí jen přečíst text — není tam nic, čím by se dalo zapsat |
| `ClaudeIntentTextFetcher` | Jedna session na review. Selhání procesu **nese důvod dál** (`.sessionFailed`), nespolkne se |
| `IntentTextCommand` | Čisté funkce: argumenty, prompt, rozbor streamu. Rozhodování o gapu je celé tady |
| `IntentGap` | Šest důvodů, proč zadání není celé. `Codable`, protože jde do osy |
| `IntentMaterial` + `Policy.intentBrief` | Složení souboru. Nese `textGap` **a** `commentsUnavailable` zvlášť — nastat můžou oba |
| `Policy.intentGap(text:commentsUnavailable:)` | Který příznak jde na osu, když nastanou oba |
| `Policy.issueTextTool(from:)` | Jméno nástroje z konfigurace; prázdno = **netahat** |

Co se u toho nemá rozbít:

- **Sada nástrojů revieweera se nemění** (tvrdá podmínka č. 2). Text tahá **zvlášť běžící session**,
  ne review, a ta má vlastní, taky vyjmenovanou sadu: `ToolSearch` a ten jeden čtecí MCP nástroj.
  `--disallowedTools` je **tatáž konstanta** `ClaudeCommand.disallowedTools` — druhá sada zákazů by
  byla druhé místo, kde se ta podmínka dá porušit. Je na to test, který v povoleních hledá `Write`,
  `Edit`, `Bash`, `ReportFindings` i `Skill` a tvrdí, že tam nejsou.
- **`--allowedTools ""` z překladu se opsat nedá.** Na stroji je v session **165 nástrojů**, takže
  CLI odkládá schémata: model musí napřed zavolat `ToolSearch` a **teprve pak** MCP nástroj (ověřeno
  ve všech bězích). Z toho plyne i `--max-turns`: **ne 1–2**, protože dotažení je ≥ 3 turny.
- **Jméno nástroje je v konfiguraci, ne v konstantě** (`GlobalConfig.issueTextTool`).
  `mcp__claude_ai_Linear__get_issue` je dnešní jméno serveru **u tohohle uživatele**, ne kontrakt —
  konstanta v kódu by byla tvrzení o cizím prostředí. **Chybějící hodnota znamená „netahat“**, ne
  prázdný pokus: session bez nástroje, který by zavolala, stojí boot (~$0,2) a nevrátí nic. Je to
  vlastní stav (`.toolNotConfigured`) a **na ose je vidět**, protože reviewer dostal jen odkazy.
- **Rozhodovat podle prózy modelu je hádání a nesmí se to tak psát.** Pořadí, ve kterém `parse`
  hledá důvod, je pořadí **příčin**: server → odmítnutí → odpověď. Kdyby se napřed koukalo na text,
  uložila by se do zadání věta modelu („nemám povolení k použití nástroje…“) jako by to bylo zadání.
  Ověřeno vložením regrese — s vypnutou kontrolou serveru padnou čtyři testy nad skutečnými streamy.
- **Exit kód se nečte.** Změřeno, že sám nerozhoduje: chybějící server skončí **nulou** a `success`,
  server, který se nespustil, **jedničkou**. Rozbor streamu se proto pouští v obou případech.
- **Nepřihlášený server je k nerozeznání od chybějícího** a je to jeden případ
  (`.serverUnavailable(status:)` s `nil` pro „v seznamu nebyl“). Servery se `needs-auth` nemají
  v `tools` ani jednu položku, takže se to odlišit nedá — a pro toho, kdo se dívá do okna, je to
  tentýž stav „zadání se nedotáhlo“.
- **Odpověď se čte podle značek, ne jako JSON.** Hodnota je cizí markdown libovolné délky
  (4 439 znaků u jednoho issue z průzkumu, s uvozovkami i zpětnými apostrofy) a překódovat ho na
  JSONový řetězec je krok, ve kterém model utne nebo zkazí escapování — selhání by pak zahodilo
  **všechny** texty naráz. Řádková značka (`IntentTextCommand.marked(_:)`) se obsahem rozbít nedá
  a skládá ji **jedna funkce** pro obě strany, takže se příklad v promptu a rozbor odpovědi nemají
  čím rozejít. Dělí se `TextLines` — odpověď může přijít s `CRLF` a `split(separator: "\n")` by na
  něm nerozdělil vůbec.
- **Text se páruje podle `id`, ne podle pořadí.** Model, který jedno issue vynechá, by u pozičního
  párování posunul texty o jedno a přiřadil je cizím issues — tichá záměna zadání. Neznámé id se
  zahazuje **i s textem**, ne přilepí k předchozímu.
- **Částečné dotažení není selhání celku.** Dvě issues a jeden text znamená, že session neselhala,
  takže na osu nejde nic — a chybějící issue se pojmenuje **ve své podsekci** v souboru. Věta u něj
  je přitom **bez příčiny** (`ReviewIntentText.notRead`), protože žádná zaznamenaná není; hádat mezi
  „nezkoušelo se“ a „nepovedlo se“ je zrovna ta záměna, kterou tohle issue odstraňuje.
- **Komentáře se v cestě review tahají vždycky znovu**, ne z uložené konverzace. Ta je klíčovaná
  `updatedAt` z posledního seznamu, takže může být starší než hlava, na kterou se pouští review —
  a komentář s linkbackem mohl přijít mezitím. Je to 1 bod GraphQL a jeden podproces na review.
  **Selhání review nepoloží**, ale zapíše se do souboru (`ReviewIntentText.commentsUnavailable`)
  i na osu: „no issue links found“ nad selhaným dotazem by tvrdilo, že PR na žádném zadání nestojí.
- **Zadání se připravuje až za rozpočtem a za checkoutem.** Od #345 to něco stojí, takže platit za
  text u běhu, který se pak nerozjede, je tatáž chyba, kvůli které se rozpočet strhává v `runSkills`.
- **Na osu jde jeden příznak, i když nastanou dva důvody.** Rozhoduje o tom `Policy`, ne view:
  přednost má **text**, protože je to ten obsah, kvůli kterému se zadání tahá. V souboru je
  zapsané obojí — tam se místem šetřit nemusí.
- **A když se soubor nepodařilo uložit, nejde na osu nic** (nález Copilota na #388). Věty
  u příznaku mluví o tom, co v zadání **chybí** („reviewer dostal jen odkazy“), takže nad během,
  který nedostal soubor vůbec, by tvrdily víc, než data unesou. Nepovedený zápis do vlastní cache
  je jiná porucha a zůstává tam, kam ho dalo #120 — ve stavovém řádku (`intentFailure`).
- **Příznak jde do osy jako první událost každé dráhy, ne po konci běhu.** Odpověď je v tu chvíli
  hotová (zadání se připravilo před `runSkills`), takže s ní není na co čekat — a událost, která by
  přišla po doběhnutí, může dorazit do osy, kterou už nikdo nečte. Za **každého** revieweera zvlášť,
  protože příznak žije na dráze: dráha bez události by o sobě tvrdila, že zadání dostala celé.
- **Příznak osu neposouvá.** `ReviewerLane.reachedStage` ho ignoruje a `completeTail` ho nepočítá za
  průběh, takže osa, ve které je **jen** on, zůstane osou bez průběhu. Bez toho by dráha ve frontě
  tvrdila, že už něco dělá, a dráha po nespuštěném běhu `doběhlo` nad prázdnými fázemi.
- **U syntetických drah je `nil`.** Dráha bez osy (`notStarted`, `queued`, `missingProgress`)
  o zadání nic neví, takže o něm nic netvrdí.

### Kontrola nálezů z minula (#150)

Druhá podoba běhu: session dostane **uložené nálezy z předchozího commitu** a řekne u každého,
jestli to nové commity spravily. Jde to **tou samou cestou** jako review (`ReviewRunning`,
pracovní strom na hlavě PR, slot, timeout, zrušení), protože kontrola musí **číst kód** — bez
stromu by odpovídala z hlavy. Řídí to `AppStore+Recheck`.

- **Vlastní druh běhu, ne review s jiným promptem.** `ReviewRunKey.kind` je součást identity,
  takže se kontrola nad tímtéž `(PR, headSha)` neslije s běžným během ve `WorkCoordinatoru`
  (klíčem je `description`, které u kontroly končí `!recheck`) a neuloží se na jeho místo.
  Vyhrazený `skillID` by udělal totéž, ale dal by se potkat se skutečným skillem toho jména;
  `skillID` proto u kontroly nikdo nečte.
- **Sada nástrojů se nemění** (tvrdá podmínka č. 2). `RecheckCommand` skládá jen prompt; povolení
  i prostředí zůstávají v `ClaudeCommand` a jsou to tytéž konstanty.
- **Prompt zakazuje `ReportFindings` a hledání nových nálezů.** Kontrola odpovídá na vyjmenovaný
  seznam a nálezy z ní vzniknout nemají — `ReviewStore.save` je z téhle větve nepustí, takže by
  se stejně neměly kam uložit.
- **Odpověď je v posledním sdělení session** (`result` event), ne v tool callu. Verdikt o nálezu
  není nález, takže `ReportFindings` na něj nemá pole; obalit stav do jeho polí by znamenalo
  tvrdit něco jiného, než jak se ta pole jmenují. Čte se defenzivně jako u překladu
  (`RecheckCommand.parse`): první `[` po poslední `]`, `id` číslem i řetězcem, stav se srovná na
  velikost písmen a oddělovač. **Neznámý stav se nehádá** — z „fixed“ se `resolved` nedělá.
- **Páruje se přes index, ne přes text.** Prompt nese `id` a odpověď ho vrací; klíč nálezu z toho
  skládá `Policy.recheckStatuses(_:of:)` přes `Policy.key(of:)`. Hledat nález podle věty, kterou
  model opíše, by stačilo jedno přeformulování a verdikt by spadl mimo.
- **Kontrola se nespouští bez materiálu.** `AppStore.recheckMaterial(for:)` chce uložený záznam
  s platnými nálezy, známou hlavu PR a to, aby se záznam a hlava lišily. Chybějící vstup by
  skončil session, která hádá — a brána nesmí ležet jen v tom, že se tlačítko nenakreslilo.
- **Materiál se skládá znovu po dotažení detailu — a proti němu.** Mezi nakreslením tlačítka
  a kliknutím mohl přijít commit; kontrola proti hlavě, která už není, by tvrdila „vyřešeno“
  o kódu, na který se nikdo nekoukal. Rozhoduje u toho **čerstvě dotažená hlava**
  (`recheckMaterial(for:head:)`), ne ta z cache detailu, kterou `fetchDetail` uvnitř běhu
  nepřepisuje: jinak by **force push zpátky na commit nálezů** kontrolu pustil (hlava z cache se
  od záznamu pořád liší, čerstvá už ne) a session by porovnávala commit sama se sebou. Nálezem
  Copilota na #271; je na to test i s vloženou regresí.
- **Přerušený běh se nedotahuje z transcriptu** (na rozdíl od review, #97). Odpověď leží
  v posledním sdělení, které v transcriptu nemá kde vzniknout — po pádu aplikace se kontrola pustí
  znovu. Nic se tím neztrácí: kontrola nemá částečný výsledek, který by se dal zachránit.
- **Běžící kontrola je běh jako každý jiný**: chrání repo před eviction (`busyRepositories`),
  počítá se do `runningReviews` (dialog při zavření aplikace) a zavírání ji zabíjí (#264).
  Vlastní mapa (`recheckTasks`) je proto, že na `reviewTasks` visí chipy reviewerů, pruh průběhu
  i podmnožina k opakování (#149) — kontrola žádný skill nepouští.

### Rozhovor nad PR — tab `Zeptat se` (#452)

**Třetí vyjmenovaná session** vedle revieweera a dotažení textu issue. Odpovídá na otázku, na
kterou reviewer nebyl puštěný — *proč tohle vůbec dělá*, *co z těch nálezů je doopravdy problém* —
a dneska se odnáší do prohlížeče nebo do terminálu. Řídí to `AppStore+Ask`, session pouští
`ClaudeAskSession` za protokolem `AskRunning`.

- **Sada nástrojů je užší než reviewerova** (tvrdá podmínka č. 2): `Read,Grep,Glob,Bash(git:*)`,
  bez `ReportFindings` (nemá co hlásit — nálezy sbírá reviewer a ukládají se klíčované `headSha`)
  a bez `Skill` (skill načtený za běhu si umí říct o odeslání na GitHub). `--disallowedTools` je
  **tatáž konstanta** `ClaudeCommand.disallowedTools`. Obě hodnoty tvrdí `AskCommandTests`
  **literálem**, jako u #345, a k tomu, že sada je **vlastní podmnožina** reviewerovy s rozdílem
  právě těch dvou položek.
- **Jedna session na pull request, držená přes `--resume`.** Ověřeno spuštěním, že si session
  předchozí odpověď pamatuje (viz [`docs/claude-cli.md`](claude-cli.md), *Rozhovor nad PR*).
  `session_id` se **přepisuje po každé odpovědi**. V tom naměřeném běhu vrátilo `--resume`
  **totéž** id, ale že jiné být nemůže, změřené **není** — a kdyby přišlo jiné, držení toho prvního
  by znamenalo, že se ztratí a třetí otázka naváže na první. Přepsat to, co dorazilo, je levnější
  než na to spoléhat. A **když
  nedorazí žádné, staré se zahodí**: rozhovor s mrtvým identifikátorem (session vypršela, cache se
  uklidila) by jinak selhával **navždycky** a v okně není nic, čím ho začít znovu. Příští otázka se
  tím stane první — založí novou session; zprávy zůstávají.
- **Materiál se přepisuje před každou otázkou, ne jen před první**, a je to oprava první podoby
  #452. Zápis do cache je zdarma, kdežto zastaralý snímek stál pravdivost pruhu `ví o tomhle PR:`:
  ten se počítá **živě** z toho, co má okno teď, takže by nad navazující otázkou tvrdil `3 nálezy`
  o session, která o nich nikdy neslyšela — tedy *text v UI, který tvrdí víc, než data unesou*.
  Prompt navazující otázky proto říká, že je soubor **čerstvý**, a stojí to nejvýš jeden `Read`.
- **Odpověď není levná, a je to změřené**: první otázka nad tímhle repem stála **$1,56 a 125 s**,
  navazující jednovětá **$0,96 a 6,8 s**. Cenu určuje **kontext, ne délka otázky** — session s sebou
  nese celý rozhovor včetně přečteného diffu, takže „krátká doplňující otázka je levná“ neplatí.
- **Ukládá se k PR, ne k `headSha`** (`ask/<owner>/<repo>/<pr>.json`, `AskStore`) — vědomá výjimka
  z toho, jak se klíčuje všechno ostatní kolem review. Tvrdá podmínka č. 5 mluví o **nálezech**:
  ty nesmí platit pro kód, který už neexistuje. Otázka „proč se ten mutex bere“ ale pushem
  nezastará; klíčovat ji commitem by znamenalo, že rozhovor zmizí zrovna ve chvíli, kdy se k němu
  člověk vrací.
- **Hranici cache si ověřují všechny tři cesty, ne jen mazání** (nález Copilota na #458). První
  podoba `AskStore` opsala kontroly z `ReviewDraftStore` i s jeho mezerou: `contains` měl jen
  `delete` a `isSymbolicLink` jen `load`, takže **`save` zapisoval a `load` četl** po cestě, kterou
  symlink v rodičovské složce vyvede ven — a to je tvrdá podmínka č. 3. Ověřeno **vloženou
  regresí**, ne úvahou: bez té kontroly `save` přepsal cizí soubor mimo cache a `delete` ho smazal
  (`AskStoreTests`, suita *Rozhovor mimo cache*). Pravidlo bydlí v `CacheFile` — viz *Hranice
  cache* níž.
- **Čte se až při otevření PR, ne při startu.** Na rozdíl od draftů, které se čtou celé při startu
  kvůli indikátoru v seznamu: rozhovor v seznamu nic nemá, takže by se jinak při každém spuštění
  dekódovalo všechno, co si kdo kdy vyzkoušel. Chybějící klíč v mapě znamená „ještě jsme se
  nedívali“, prázdný rozhovor „na disku nic není“.
- **Zápis čte hodnotu až v tasku** (`persistAsk`, tentýž vzor jako `persistDraft`). Otázka
  a odpověď se zapisují každá zvlášť, takže dva tasky běží krátce po sobě a **pořadí jejich
  doběhnutí není zaručené** — se snímkem v parametru by starší zápis přebil novější a v souboru by
  po restartu chyběla odpověď, za kterou se zaplatilo.
- **Kontext je materiál, ne nástroj.** Nálezy, konverzace a checky si session nedotahuje sama —
  k tomu by potřebovala `gh`, a ten se nedá povolit jen na čtení. Skládá je `Policy.askBrief` do
  souboru **vedle** pracovního stromu (`worktrees/<owner>/<repo>/<pr>-ask.md`, `AskContextStore`)
  a do promptu jde **cesta**, ne obsah — tentýž precedens jako zadání pro reviewera (#120), i to
  proč: cizí text v promptu má váhu instrukce, ve čteném souboru je to materiál k posouzení.
  Soubor je **jeden na PR** (bez `headSha` v názvu), protože se přepisuje při každé otázce; verze
  na commit by po deseti pushnutích nechala v cache deset kopií téhož.
- **Diff v materiálu není.** Session stojí v pracovním stromě na hlavě PR a `Bash(git:*)` má, takže
  si změny přečte `git diff <base>...HEAD` — toutéž cestou jako reviewer. Nasypat diff do souboru
  by znamenalo stovky kilobajtů v souboru, který se zakládá při každé první otázce, a druhou pravdu
  o tom, co se v PR změnilo.
- **Žádná sekce materiálu nezmizí mlčky.** Prázdná sekce dostane větu (`nálezy nejsou`,
  `konverzace se nenačetla`, `konverzace je zkrácená`) — chybějící sekce je mezera, kterou si model
  doplní domněnkou, kdežto věta je informace. Je to tatáž úvaha jako u `ReviewIntentText`.
- **Pracovní strom je ten, jaký dostal reviewer** (tvrdá podmínka č. 3) — `checkout.worktree(for:at:)`
  na čerstvě dotažené hlavě. Hlava se bere **znovu**, ne z paměti: mezi nakreslením tlačítka
  a kliknutím mohl přijít commit.
- **Běžící odpověď je běh jako každý jiný**: chrání repo před eviction (`busyRepositories`), počítá
  se do `runningReviews` (dialog při zavření aplikace) a zavírání ji zabíjí (#264). Vlastní mapa
  (`askTasks`) je ze stejného důvodu jako u kontroly nálezů — na `reviewTasks` visí chipy
  reviewerů a rozhovor žádný skill nepouští. A protože jede přes `SubprocessStreamer(sessions:
  .shared)`, zabije osiřelou session i **další start** (#351).
- **Útrata jde do `SpendLedger`u**, tedy do téhož `Dneska stálo` jako review. Zapisuje se **před**
  kontrolou zrušení: session, která doběhla, peníze stála, ať se odpověď uloží, nebo ne. Strop se
  nedává — sazbu si člověk řídí tím, kolik se ptá; skrytá útrata je horší než drahá.
- **Odpověď, která nedoběhla, nezmizí.** `AskAnswer` nese text **i** důvod, ne jedno nebo druhé
  (tatáž úvaha jako `IntentTextResult`): vytimeoutovaná session, která něco stihla říct, řekla něco
  pravdivého. A odpověď **bez textu a bez důvodu** dostane vlastní větu — prázdná bublina by
  vypadala jako chyba vykreslení.
- **Odpověď smí odkázat na soubor a řádek.** Prompt si o tvar `path/to/file.swift:80` říká
  a `Policy.askReferences` ho v textu hledá; klik jde **toutéž cestou jako skok z nálezu**
  (`anchor(inFile:line:)` + `scroll(to:)`). Kapsle stojí **pod prózou, ne uvnitř věty**, a je to
  vědomá odchylka od návrhu: inline odkaz by znamenal obarvit `path:line` v `AttributedString`u,
  který skládá `MarkdownInlineText` — a ten sází i popis PR a cizí komentáře, takže by se `file:80`
  stalo klikatelným všude v okně.

Co je v okně a proč zrovna tak:

- **Osmá záložka za druhým děličem.** Pruh dělí, co je *na PR*, od toho, *co s ním udělaly
  reviewery*; rozhovor je třetí druh — *co s tím dělám já teď*. Rozhoduje o tom
  `PullRequestTab.group`, který u #452 nahradil `Bool` (`isReviewerOutput`): ten umí popsat jediný
  předěl, takže by osmá záložka za druhým děličem musela tvrdit, že je výstup reviewerů.
  `isReviewerOutput` se od #452 **odvozuje** ze `group`, aby se ty dvě odpovědi nemohly rozejít.
- **Záložka, ne pravý panel.** Odpověď je próza s úryvky kódu; panel má 300 bodů a už drží
  rozdělané review, labely a reviewery. `showsReviewPanel` je proto u `Zeptat se` `false` — pod
  sebou by jinak stála dvě textová pole s vlastním odesílacím tlačítkem, tedy ta záměna, kvůli které
  composer komentáře (#216) nesedí v panelu.
- **Bubliny, ne karty.** Kdo mluví, se pozná stranou a barvou (`AskBubbleView`), ne hlavičkou
  u každé zprávy — a bublina není přes celou šířku (78 %). Karty zůstávají v konverzaci na PR, která
  odpovídá na „kdo co kdy řekl“.
- **Že se odpovídá, nese prstýnek na místě příští bubliny**, ne pruh nad plochou: odpověď přijde
  sem. Řádek u něj říká, co session dělá (`Policy.askActivity` — sloveso podle nástroje, ne jeho
  jméno), a než něco řekne, stojí tam `přemýšlí…`; prázdno v té několikasekundové mezeře vypadá jako
  zaseknuté okno. Prstýnek je `SpinningRing`, tedy CoreAnimation (#350).
- **Pevný `VStack`, ne líný seznam** (`AskLogEagerTests`). Rozhovor má strop o řád níž než osa
  konverzace, která od #361 líný seznam nemá vůbec: osa jich má nejvýš čtyři stovky, kdežto tady je
  každá zpráva **zaplacená session**.
- **`ví o tomhle PR:` je výčet toho, co jde do promptu**, ne toho, co aplikace ví — chipy se skládají
  z týchž hodnot jako materiál (`AppStore.askContextChips`). Nula chip nedostane: „0 checků“ je
  pravdivé, ale v tom pruhu se čte jako selhání.
- **`čte · neodesílá` a věta u composeru jsou v okně**, ne jen v dokumentaci. Práva, o kterých ví
  jenom `CLAUDE.md`, uživateli neřeknou nic.
- **Prázdný tab nabízí otázky k odpíchnutí a klik je rovnou odešle** (změna proti první podobě
  #452, kde jen předvyplnily pole). Zahodilo se to při prvním proklikání: předvyplněná otázka chce
  po člověku **druhý klik na tomtéž místě**, kde měl stačit první. Přepsat se dá pořád — píše se do
  pole pod tím, a cena jednoho kliknutí je vidět, protože každá bublina nese svou útratu. Jde to
  **toutéž cestou jako pole** (`AppStore.askQuestion(_:about:)`), takže není druhé místo, kde se
  rozhoduje, co se pošle — a **na rozepsanou otázku vedle to nesahá**: klik na nabídku není důvod
  smazat větu, kterou má člověk v poli.
- **Nabídka se řídí tím, co na PR je** (`Policy.askTips(context:)`). Otázka na nálezy se nad PR bez
  nálezů **nenabízí**: ptala by se na nic a session by za dolar odpověděla „žádné tam nejsou“.
  Skládá se z **týchž chipů**, které kreslí pruh `ví o tomhle PR:` — jedno pole se v
  `PullRequestDetailView` spočítá jednou a jde do obojího, protože dvě různá čísla o jedné věci na
  jedné obrazovce jsou horší než jedna otázka míň (a je to přesně ta třída chyby, kterou u tohohle
  tabu jednou vyrobil materiál skládaný jinde než pruh). **Počet se píše číslicí**, i když ho návrh
  v próze sází slovem: v pruhu nad tím stojí `3 nálezy`, takže je shoda vidět a dá se o ní něco
  tvrdit testem. Jediný nález dostane vlastní větu — „Který z těch 1 nálezů“ je česky nesmysl.
- **Composer drží text u sebe, ne ve storu** (`AskComposer`), a je to **oprava naměřené chyby**, ne
  styl. Do té doby tam seděl `DraftTextEditor`, který text posílá dolů po **odmlce 400 ms** (rozdělané
  review čtou bubliny v diffu, takže se každý úhoz zapisovat nedá). Jenže tady je to, co se odesílá,
  **totéž pole**, do kterého se píše: klik trefený do té odmlky odeslal **starší** otázku a rozepsanou
  dostal zpátky přes `onChange(of: text)`, takže v bublině byla půlka věty a v composeru celá.
  Změřeno v `AskComposerTests` nad skutečným oknem, ne odvozeno.

  Rozdělení rolí je teď: **pole je pravda**, `askDrafts` je **záloha pro přepnutí tabu** (čte se při
  objevení, zapisuje se při zmizení a při odeslání) a `askQuestion(_:about:)` bere text **od
  volajícího**. Není to odchylka od vzoru u komentáře pod PR (#216) — smysl toho pravidla je
  „odejde to, co je vidět“, a právě ten okružní cesta porušovala. Podobu pole obě místa sdílejí přes
  `DraftTextField`, aby se rámeček a nápověda nerozešly.

  Tři věci, které z toho plynou a nejsou zjevné:

  - **Odeslání vrací `Bool`.** `false` znamená „neodešlo“ a composer podle toho otázku v poli
    **nechá** — přijít o napsanou otázku je horší než ji tam mít po odeslání. Vyprázdnění pole je
    proto součást odeslání, ne úklid navíc, a děje se **jen po `true`**.
  - **`askQuestion` `askDrafts` nemaže.** Kdyby ano, klik na nabízenou otázku by smazal rozepsanou
    větu vedle — a odsud se ta dvě použití nedají odlišit. Zálohu srovná composer.
  - **Tab má vlastní identitu podle PR** (`.id(pullRequest.id)` na `AskView`). Detail se mezi pull
    requesty **znovupoužívá**, takže bez toho by si composer nechal rozepsanou otázku z předchozího
    PR a při zmizení ji uložil do jeho zálohy.
- **Zrušení se nepozná jen podle `CancellationError`** (`AppStore+Ask.handle`), a je to **jedno
  místo pro obě cesty** — `Zastavit` i `Nový rozhovor`. Zabíjený `git` ani `claude` o zrušení
  nevědí, takže vyhodí **svou vlastní** chybu (`CheckoutError`, `GitHubError`) a `CancellationError`
  se ven nedostane; bez `Task.isCancelled` by se to vypsalo do rozhovoru jako porucha. U `Zastavit`
  by to bylo matoucí (tlačítko slibuje, že zůstane **otázka**, a nic víc), u `Nový rozhovor` **horší
  než matoucí**: bublina by přistála do rozhovoru, který se právě vyprázdnil, a protože se každá
  zpráva ukládá, **zapsala by zpátky na disk soubor, který se před chvílí smazal**. Ověřeno
  vloženou regresí — bez `Task.isCancelled` padnou dvě sady a `42.json` se v cache objeví znovu.
- **`Nový rozhovor` zahodí rozhovor i navázání** (`AppStore.resetAskConversation`) — a maže **i to,
  co není vidět**: soubor v cache a `sessionID`. Rozhovor, který zmizel z okna a zůstal na disku, se
  vrátí přepnutím tabu; ponechané `sessionID` by navázalo příští otázku na vlákno, se kterým člověk
  skončil. Do mapy se zapisuje **prázdný rozhovor, ne chybějící klíč** (chybějící znamená „z disku
  se ještě nečetlo“, takže by ho `loadAskConversation` načetl zpátky), běžící odpověď se **zabíjí**
  (jinak by doběhla do zahozeného rozhovoru a přidala do něj bublinu bez otázky) a **rozepsané
  otázky se to netýká** — „načisto“ mluví o rozhovoru, ne o větě, kterou má člověk v poli.

  Tlačítko je tiché (`.mini`) vedle kapsle `čte · neodesílá`, **v prázdném tabu se nekreslí vůbec**
  (`AskTabContent.offersReset` — není co zahodit, a zašedlé tlačítko by tvrdilo „tady se to dělá,
  jen teď ne“) a **ptá se jednou větou**, ačkoli se v tomhle okně skoro nic nepotvrzuje: odpověď
  stála kolem dolaru a smazaný rozhovor se nedá vrátit ani zopakovat za stejné peníze. Je to tatáž
  úvaha jako u zakládání labelu (#413) — potvrzuje se to, co je **nevratné**, ne to, co je důležité.
- **Během odpovědi se z tlačítka stane `Zastavit`.** Jedna odpověď stojí kolem dolaru a běží minuty,
  takže „rozmyslel jsem si to“ nesmí znamenat čekat na konec; zakázané `Zeptat se` vedle prstýnku je
  navíc tlačítko, které v tu chvíli nedělá nic. Je to **tentýž prvek v jiném stavu**, ne druhé
  tlačítko. Zkratku `⌘.` si to **nebere** — `WindowShortcut.cancelReview` má u sebe napsané, proč
  jedna klávesa nesmí podle stavu zastavit jednou review a jindy něco jiného.
- **`⌘⏎` v tomhle tabu odesílá otázku**, takže je zkratka **okna** (otevření potvrzení odeslání,
  #151, #441) nad ním **zakázaná** — rozhoduje `Policy.claimsReturnShortcut`. Dvě tlačítka s toutéž
  kombinací znamenají, že vyhraje zaregistrované později (#184); zakázané tlačítko klávesu nebere
  a propadne dál. Je to tentýž vzorec jako u `⌘2` a `⎋` nad otevřenou paletou.

**Co se tímhle nemění: tvrdá podmínka č. 1.** Session nic neodesílá, `grep ReviewPublishing App/`
vrací týž seznam a `SingleWayOutTests` procházejí beze změny. Kdo z odpovědi chce komentář na PR,
pošle ho composerem v `Konverzaci`.

## Překlad nálezů (`App/Review/`)

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

## `App/Support/`

Sdílené drobnosti, které nepatří žádnému modulu:

| Soubor | Co dělá |
|---|---|
| `WorkCoordinator` (dřív `CheckoutCoordinator`) | Souběžná volání nad stejným klíčem spojí do jedné práce a zrušení posledního čekajícího zruší i tu práci |
| `Plural` | Počet s podstatným jménem v českém tvaru (`1 nález`, `3 nálezy`, `5 nálezů`); `word(_:one:few:many:)` dá jen tvar slova |
| `String.singleLine` | Text bez řádkových zlomů, ty se nahradí mezerou |
| `Collection[safely:]` | Prvek na indexu, nebo `nil` mimo rozsah |
| `Clipboard` | Zápis do schránky |
| `TextLines` + `Character.isLineTerminator` | Dělení textu na řádky — **jedno místo pro celou aplikaci** (#295) |
| `threadCPUSeconds()` | Kolik CPU si vzalo vlákno, které se ptá — jedno místo pro aplikaci i pro sondy (#361) |
| `RenderDiagnostics` + `DiagnosticsLog` | Počitadla průchodů `body`, kol runloopu a CPU do řádkového souboru; **vypnuté, dokud není `PRISM_DIAGNOSE=1`** (#361) |

Společné je jim to, proč tady jsou: **kopie jednoho pravidla se rozejdou.** `WorkCoordinator`
používá `RepoCheckout` (klony, stromy) i `ReviewRunner` (běhy) a dvě kopie by znamenaly dvakrát
tu jemnou logiku kolem rušení. `Plural` vznikl ze tří `switch`ů, které se lišily; `singleLine`
z pěti kopií téhož `split(whereSeparator: \.isNewline)` — hlavička bubliny, přehled draftu,
jeho přenos, syntetická hlavička diffu a od #200 tělo notifikace. Stačilo by, aby jedna z nich
řešila `\r\n` a ostatní ne.

### `TextLines` — co je řádek (#295)

Přesně to „stačilo by, aby jedna z nich“ se stalo — u #292 a pak ještě na pěti dalších místech.
`"\r\n"` je ve Swiftu **jeden `Character`**, takže `split(separator: "\n")` na textu s `CRLF`
**nerozdělí vůbec**: z celého vstupu zbyde jediný „řádek“. Ne o jeden vedle, celý.

Kde to leželo, než to #295 svedlo na jedno místo:

| Kde | Co se dělo na `CRLF` vstupu |
|---|---|
| `DiffParser` | Diff souboru s `CRLF` = **jeden** řádek, tedy soubor s jedním nesmyslným kontextovým řádkem místo hunků |
| `FileExpansion` | Obsah souboru = jeden řádek, odkrytý rozsah se ořezal na první, z rozbaleného kontextu byla jedna nekonečná řádka |
| `SelectableCodeView` | Kód v sheetu se obarvil jako jeden řádek a celý jeho objem šel do `SyntaxRunCache` jako **jeden klíč** (#224) |
| `CopyPolicy` | Popisek `Kopírovat rozsah (1 řádek)` nad rozsahem o dvaceti |
| `MarkdownParser`, `TranscriptStore` | Jiná past, tentýž druh: `components(separatedBy: .newlines)` dělí po **skalárech**, takže `CRLF` jsou pro ni dva oddělovače a mezi ně vloží prázdný řádek. V markdownu je prázdný řádek konec odstavce — takže se každý řádek cizího komentáře vysázel jako vlastní odstavec. Těla komentářů z GitHubu `CRLF` mají, je ve třech fixtures konverzací |
| `Policy.commitMessageToggle` (#339) | Sedmé místo, které #295 minulo, protože vzniklo až s #317. Popisek přepínače hlásil `Tělo zprávy · 1 řádek` u zprávy jakékoli délky — tedy přesný opak toho, na co odpovídá („vyplatí se to rozbalit?“). Zprávy commitů chodí z `gh` z cizích repozitářů, takže zakončení řádků si nevybíráme |

Tři funkce, ne jedna s přepínačem — liší se tím, **co je řádek** pro volajícího, a to má být vidět
na místě volání: `all` (všechno včetně prázdného posledního), `content` (bez prázdného posledního za
koncovým zakončením — soubory a diffy) a `nonEmpty` (výpisy, kde je řádek jeden záznam).

Věci, které se u toho nemají rozbít:

- **Řádek končí `LF`, `CRLF` nebo samotným `CR` — a ničím jiným.** `Character.isNewline` je pravda
  i pro `VT`, `FF`, `NEL`, `U+2028` a `U+2029`, ale pro `git` jsou to **znaky obsahu**. Rozdělit se
  na nich znamená vyrobit řádek, který v souboru není — a protože se čísla řádků počítají tím, kolik
  jich hunk vydal, jeden `U+2028` v cizím zdrojáku by posunul všechna čísla pod sebou; druhá půlka
  řádku by navíc nezačínala `+`/`-`/mezerou, takže by se spočítala jako ztracená
  (`unrecognizedLines`).
- **`String.singleLine` si `isNewline` schválně nechává.** Jsou to dvě různé otázky: „kde končí
  řádek v bajtech, které mi někdo poslal“ a „co mi zalomí popisek“. `U+2028` popisek zalomí, takže
  se srazit musí. Hlídá to test, ať to někdo omylem nesrovná.
- **Kdo text dělí na dvě části, dělí obě na tomtéž znaku** (#339). Zpráva commitu se rozpadá na
  titulek (`PullRequestCommit.subject`, `prefix(while:)`) a tělo (`Policy.commitMessageBody`,
  `drop(while:)`) — jsou to dvě půlky **jednoho** rozdělení, takže obě jdou po `isLineTerminator`,
  a po tomtéž znaku počítá řádky i popisek přepínače. S `isNewline` v půlkách a `TextLines` v počtu
  by `U+2028` uvnitř titulku titulek usekl a jeho zbytek by se v hlavičce objevil **ještě jako první
  řádka těla** — tentýž text dvakrát, a přitom `git` (`%s`/`%b`) tam žádnou hranici nevidí. Sazbu to
  neohrozí: oba pohledy titulek zkracují (`lineLimit` 1 v `CommitListView`, 2 v `CommitHeaderView`).
  Grep z `CLAUDE.md` tenhle rozpor **nechytá** (nechytá `whereSeparator` ani `isNewline`), takže se
  na něj musí koukat u každého místa, které jeden text dělí na víc kusů.
- **`CR` se do textu řádku nedostane** — je součást zakončení, ne obsahu. Kdyby zůstal, nesly by
  neviditelný znak klíče do `SyntaxRunCache` (#153, #224), word-level rozdíl i sazba, a v sazbě by
  z něj byl prázdný řádek pod každým řádkem kódu. Cena rozhodnutí: **kopie do schránky nese `LF`,
  i když soubor měl `CRLF`** (zapsané u `Policy.code(of:)`). Unese to, protože ten text jde do
  terminálu nebo do komentáře jako **kód** a aplikace do souborů nezapisuje (tvrdá podmínka č. 1).
- **Není to na cestě překreslování**, takže rozhodovala čitelnost, ne rychlost — ale je to změřené.
  Na 2,26 MB / 25 000 řádcích: `split(separator: "\n")` **22,2 ms** (a na `CRLF` vydá **jeden**
  řádek), `isNewline` **24,4 ms**, `isLineTerminator` **27,1 ms**. Rychlejší varianta **existuje
  a je zamítnutá**: test prvního skaláru (`unicodeScalars.first`) dá **22,0 ms**, tedy rychleji než
  to, co tam bylo, ale za cenu komentáře vysvětlujícího, že `"\r\n"` má první skalár `\r`.
  `Policy.logTail` je jediné místo, kde jde o megabajty, a běží **jednou po stažení**
  v `Task.detached`, ne v `body` — takže ta 4 ms na největším logu nikdo nepozná. Kdyby se dělení
  jednou na cestu překreslování dostalo, je to změna na jednom místě.
- **`Policy.logLines(of:)` zůstává jako jméno pro volající**, ne jako druhé pravidlo — dělí
  `TextLines.all`. Smazat by šlo, ale znamenalo by to sáhnout do `logTail`
  a `strippingTimestamps`.

### Diagnostika kreslení (#361)

Kolo z #361 se v testu za tři pokusy nepodařilo vyrobit, kdežto na skutečném okně se stalo třikrát.
`sample` z ztuhlé instance přitom ukáže, **kde** hlavní vlákno je, ale ne **kolikrát** se co
přeložilo — a to je zrovna ta chybějící polovina: v `Update.dispatchActions()` je vidět jen re-arm,
ne invalidace. `RenderDiagnostics` je ta druhá polovina: **počitadlo průchodů `body` po typech**,
počet kol runloopu a CPU hlavního vlákna, jeden řádek za sekundu do
`~/Library/Application Support/PRism/diagnostics.log`.

**Zapíná se `PRISM_DIAGNOSE=1`, nejjednodušeji `./bin/run.sh --diagnose`.** Tři důvody, proč
proměnná prostředí a ne přepínač v nastavení:

1. **Přepínač v nastavení je něco nového na obrazovce**, takže by se musel nakreslit do mockupu
   a schválit dřív, než na to vznikne issue (`CLAUDE.md`, jediná schvalovací brána). Diagnostika
   jednoho konkrétního hledání do produktu nepatří — až se #361 zavře, má zmizet.
2. **Nedá se přepnout uprostřed sezení**, takže jeden soubor = jeden režim. Přepínač otočený
   v půlce by dal záznam, ze kterého není poznat, co v něm chybí.
3. **Zapomenout se nedá.** Příznak umře s procesem a `bin/run.sh` restartuje aplikaci po každém
   mergi, tedy několikrát denně — diagnostika se tím vypne sama. Ukazatel v okně by tuhle
   vlastnost neměl a stál by změnu vzhledu.

Že je zapnutá, je vidět na třech místech: banner z `bin/run.sh`, řádek na stderr při startu
a **hlavička sezení** v souboru (jméno bundlu kvůli slotům, PID kvůli `sample`u).

Čtyři věci, které to **nesmí** dělat, protože měřidlo nesmí měnit to, co měří:

- **Počitadlo není v observable stavu** (#252) — obyčejná třída se zámkem, ne `@Observable`. Zápis
  do stavu při každém průchodu tělem je právě ta chyba, kterou tohle hledá.
- **Nic si neplánuje kolo na hlavním vlákně** (#350). Žádný `Timer` na hlavním runloopu, žádná
  animace, žádný `requestUpdate`, žádný `DispatchQueue.main.async`. Observer runloopu na
  `beforeWaiting` zůstává, ale **jen jako počitadlo kol** — inkrement pod zámkem, bez hodin a bez
  disku. Pořadí je vysoké schválně: SwiftUI si transakce flushuje taky v `beforeWaiting` observeru
  (`NSRunLoop.flushObservers`), takže se počítá kolo, které už transakce proběhlo. Změřeno na
  běžící `PRism-a`: nečinné okno bez otevřeného PR dá **1–4 kola a 5–14 ms CPU** za sekundu, tedy
  ~70 B na řádek a strop řádově za den.
- **`pass(_:)` nečte hodiny ani nesahá na disk.** Je to inkrement pod zámkem a nic jiného; jméno
  typu se skládá reflexí **jen u prvního průchodu** (`@autoclosure`). Cena vypnuté diagnostiky je
  načtení jednoho statického `Optional`u (`RenderDiagnostics.current`).
- **Nula se nezapisuje.** Mezera v záznamu znamená „aplikace nic nedělala“, a to je informace;
  řádek každou sekundu by hořící okno utopil v tichých řádcích. **Do „nic“ ale nepatří hořící
  CPU** (#391): rozhoduje `Policy.diagnosticBurnFloor` (5 % uplynulého času), protože zaseknuté
  kolo nemá ani kola runloopu, ani průchody tělem — a právě takový úsek se má zapsat.

**Zapisuje vlastní vlákno, ne observer hlavního runloopu** (#391) — a je to ta jediná změna, která
z toho nástroje udělala nástroj na **živý** záchvat. Do té doby řádky vypisoval ten observer, tedy
hlavní vlákno samo, a ve čtvrtém záchvatu (#361, 2026-08-20) se ukázalo, co to znamená: poslední
řádek je `11:01:31`, ztuhnutí trvalo do `11:02:53` a mezi tím **nic**. Runloop se totiž do stavu
čekání vůbec nedostane — SwiftUI si flushuje transakce z `beforeWaiting` observeru a z toho se
v tom kole nevrátí, takže náš observer s vyšším pořadím nepřijde na řadu. Nástroj postavený na
živý záchvat se tak v záchvatu vypnul.

Řádek proto zapisuje `Thread` + `Thread.sleep` (`startWriting()`), ne `Timer` ani
`DispatchSourceTimer`: časovač potřebuje runloop nebo frontu, kdežto tady stačí vlákno, které se
probouzí samo a nikomu nic neplánuje. Reference na sebe je **slabá**, takže se vlákno ukončí i
tehdy, když se instance zahodí bez `stop()` (typicky v sondě). Hlavního vlákna se to dotýká jedině
**čtením jeho CPU**: `threadCPUSeconds(of:)` nad jeho mach portem, protože
`CLOCK_THREAD_CPUTIME_ID` umí jen vlákno samo o sobě a zaseknuté hlavní vlákno se nemá kdy zeptat.
Port se bere v `init` z volajícího vlákna (`currentThreadPort()`), takže se instance musí postavit
tam, kde se má měřit; `start()` je `@MainActor`, takže v aplikaci to vyjde samo. Vedlejší efekt,
který je taky ke prospěchu: **zápis na disk odešel z hlavního vlákna**.

Zaseknuté kolo se z řádku pozná slovy: `0 kol runloopu`, celá sekunda CPU a
`— HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU`. **Věta netvrdí „záchvat“**, jen to změřené — jeden
takový úsek může být i drahá práce na hlavním vlákně; záchvat se pozná z toho, že takových řádků
jde za sebou desítky. `qualityOfService` zapisovacího vlákna je `.utility` schválně — hlavní vlákno
má přednost, protože se měří ono —, takže se úsek pod plnou zátěží roztáhne (měřeno 0,13–0,18 s při
cadenci 0,1 s). Na řádku to nic nekazí: `elapsed` v něm je **skutečně** uplynulý čas, ne nastavená
perioda.

**Ověřeno spuštěním, ne jen testem** (`PRism-a`, Debug, `./bin/run.sh --diagnose`): po hlavičce
chodí řádek za sekundu se skutečnou cadencí **1,07 s**, nečinné okno bez otevřeného PR dá 2–15 kol
a 0,000–0,018 s CPU. Bez toho by se nevědělo, že se `start()` po přestěhování na vlastní vlákno
vůbec rozjede — `PRISM_DIAGNOSE` se v testech nezapíná, takže tu cestu žádný test nejde.

**Strop je vyjmenovaný, platí na soubor a jeho dosažení se zapisuje** (8 MB,
`DiagnosticsLog.byteLimit`). Cache bez vyjmenované meze je únik místa s odkladem (#224) — a soubor,
který prostě přestane růst, se nedá odlišit od aplikace, která přestala hořet, takže se poslední
řádek napíše. Chyba zápisu jde na stderr a sezení **zavře**; `try?` by udělal soubor, který mlčí ze
dvou různých důvodů.

**Strop platí na soubor, ne na sezení** (nález Copilota na #386) — a od #412 z toho neplyne, že by
sezení mělo míň místa než jeho předchůdce: soubor se při startu **rotuje**, takže je prázdný a strop
je celý pro tohle sezení. `written` se pořád **seedne velikostí souboru** (`offset()` po
`seekToEnd()` na tomtéž deskriptoru, do kterého se zapisuje), protože bez rotace — v sondách,
v testech a v případě, že se rotace nepovede — je to ta jediná mez, která drží. Sezení nad už plným
souborem **bez rotace** nezapíše nic a `append` vrátí `false` hned u hlavičky; je na to test ověřený
**vloženou regresí** (s počitadlem od nuly spadne na tom, že druhé sezení hlavičku zapsalo).

**Rotace při startu je oprava #412 a byla to podmínka, ne pohodlí.** Naměřeno v provozu: záznam
narazil na strop v `2026-08-22T04:01:36` a dalších **42 hodin** aplikace běžela bez záznamu — tedy
zrovna tu dobu, kvůli které se nástroj bere (záchvat z #361 přijde nepředvídatelně). Kořen nebyla
velikost stropu, ale to, že se počítal **napříč sezeními**: při restartu ve 12:34 hlásil `bin/run.sh`
4 859 815 B, takže tomu sezení zbývalo 3,5 MB, což je při jednom řádku za sekundu necelých sedm hodin
— a restartuje se po každém mergi, tedy šestkrát denně.

Drží to `DiagnosticsArchive`, a rotace sedí **uvnitř otevírání souboru** (`DiagnosticsLog`), ne
u volajícího: kdyby ji spouštěl volající, dalo by se pořadí pokazit a log s otevřeným deskriptorem by
po přesunu zapisoval **do archivu**, tedy do souboru, na který se nikdo nedívá. Co udělala, si
`start()` vyzvedne z `log.rotation` a zapíše **do záznamu** hned za hlavičku sezení
(`Policy.diagnosticsRotationLines`) — soubor, který začíná od nuly, se jinak nedá odlišit od
aplikace, která o předchozím sezení neví.

Čtyři věci na tom nejsou zjevné:

- **Jméno nese čas posledního zápisu, ne čas rotace** (`diagnostics-do-2026-08-22T04-01-36.log`).
  Sezení, které skončilo v pátek, má mít v názvu pátek i tehdy, když se aplikace spustí v pondělí.
  Bez dvojtečky (Finder ji kreslí jako `/`) a bez posunu pásma — ten je na každém řádku uvnitř.
- **Meze jsou dvě a každá na jinou poruchu**: 20 souborů (jinak by v cache ležely stovky skoro
  prázdných záznamů, protože jedno spuštění se `--diagnose` je jeden) a 64 MB (jinak by dvacet plných
  bylo 160 MB). Dvacet je ze měření: šest restartů denně, takže přes tři dny historie — a u #361 se
  čte zpětně.
- **Nejnovější se nemaže nikdy**, ani když sám přeteče bajtovou mez. Rotace, která zahodí to, co
  právě uložila, je horší než strop; ten aspoň nechá v souboru napsáno, co se stalo. Ověřeno
  vloženou regresí.
- **Maže se jedině podle vzoru jména** (`Policy.isDiagnosticsArchive`). V kořeni cache leží nálezy,
  drafty, `sessions.json` i `activity.json`, takže úklid podle času nebo přípony by sáhl na ně; a co
  se nepodařilo ani přečíst (`resourceValues`), se do výčtu nedostane, tedy se ani nesmaže.

**Z #386 plyne druhá polovina: `start()` se láme na hlavičce.** Když se nezapsala, `current` zůstane
`nil`, vrátí se `false` a důvod jde na stderr — jinak by „diagnostika je zapnutá“ a „nic se
nezapisuje“ splynuly, což je zrovna to, co banner v `bin/run.sh` slibuje, že nenastane. Totéž platí
pro řádky o rotaci a o grafu. Skript **velikost hlásí dřív, než aplikaci spustí** (`stat -f%z` nad
logem, plus počet uložených záznamů), protože na stderr se při spuštění přes `open` nikdo nedívá; od
#412 už kvůli plnému souboru **nekončí `exit 1`** — soubor se odloží sám, takže by odmítnutí startu
znamenalo mazat rukou to, co má dělat aplikace.

**Klid se sráží do minutového souhrnu** (#412), místo řádku za sekundu. Změřeno nad skutečným
záznamem z provozu (985 754 B, 11,5 h, tři sezení): úseků bez průchodu tělem a bez hoření bylo
**9 279 z 10 077**, tedy 89 % hlavních řádků a 60 % objemu — a **ani k jednomu** z nich nestála
příloha o grafu (0 z 2 601), takže se folding nemá čím dotknout toho, na co je záznam. Do #412
rozhodovalo i „aspoň jedno kolo runloopu“, jenže nečinné okno má 1–4 kola za sekundu, takže to
neodlišovalo práci od spánku; odlišuje ji **průchod tělem nebo hoření**. Co z toho plyne:

- **Záchvat se pořád zapisuje po sekundách** i s náběhem — hoření klid není. Souhrn se navíc
  zapisuje **před** tím řádkem, který klid přerušil, takže časy v souboru jdou vzestupně.
- **Mezera v záznamu už neznamená „nic se nedělo“, protože žádná není.** Souhrn je puls: dokud
  přichází, záznam žije. Do #412 se mezera nedala odlišit od nástroje, který se vypnul — a přesně to
  se u #412 stalo.
- Souhrn říká jednu věc navíc proti sečtení řádků: **kolik úseků bylo bez jediného kola runloopu**.
  To je hlavní vlákno zaseknuté bez spalování CPU (blokující I/O) a takové úseky v záznamu do #412
  nebyly vůbec. Nad skutečným záznamem vyšlo 0 z 9 279, takže to není mez, která se plní sama.

**Omezení, které zbylo:** záznam končí s procesem, takže poslední rozepsaný úsek se nezapíše —
soubor se plní po celých úsecích. A zaseknutou aplikaci nemá kdo zavřít jinak než rukou
(`bin/run.sh` na Apple event nedostane odpověď, `-1712`), takže z posledního záchvatu chybí ta
poslední sekunda. Od #412 k tomu patří i nasbíraný klid: z konce chybí až minuta, ve které se nic
nedělo.

Skládání řádku je čistá funkce v `Policy` (`diagnosticLine`, `diagnosticQuietLine`,
`diagnosticHeaderLine`, `diagnosticLimitLine` a rozhodnutí o rotaci v `DiagnosticsArchiving.swift`)
— soubor se posílá dál a je jediné, co z hořícího okna zbyde, takže na něm musí být pořád totéž a ve
stejném pořadí. Řadí se **podle počtu**, ne podle jména: hledá se ten typ, který se překresluje
nejvíc. Pásmo času se předává, aby se dal stamp napsat v testu literálem.

Instrumentované jsou zatím `ContentView`, `PullRequestDetailView`, `ConversationView`,
`ConversationNodeView`, `ConversationEntryView`, `MarkdownText`, `DiffView` a `DiffRowView` —
řádkem `let _ = RenderDiagnostics.pass(Self.self)` na začátku `body`.

#### Co se v tom kole přepočítává a kdo si o to řekl (#361, osmé kolo)

Počitadlo průchodů `body` má u #361 jednu vadu, a je zásadní: **v hořícím kole se nepřeloží ani
jedno tělo** (doloženo ve čtvrtém i sedmém záchvatu — `MarkdownText` a `DiffRowView` mají ve vzorku
nulu), takže v tu nejdůležitější sekundu neřekne nic než „0 kol runloopu, sekunda CPU“. Osmé kolo
proto přidalo dvě věci: **počitadla míst, která v tom kole doopravdy běží** (`GraphSite`),
a **evaluační zásobník AttributeGraphu** (`GraphProbe`).

**`GraphProbe` je jedna čtecí funkce privátního frameworku.**
`AGGraphDescription(nil, ["format": "stack/text", "max-frames": 16])` vrátí zásobník toho grafu,
který se právě aktualizuje **na volajícím vlákně**: rámce od toho, co se počítá teď (`#0`),
k tomu, kdo si o celou tu řadu řekl (poslední rámec), a u vstupů příznak `changed`. Ověřeno
spuštěním na macOS 26, ne přečteno z dokumentace:

| Co | Zjištěno |
|---|---|
| cena volání | **0,0063 ms** při `max-frames: 64` (500 volání v jednom průchodu tělem; s osmi rámci 0,0047 ms, takže rozhoduje volání, ne délka) |
| odkud je zásobník vidět | `View.body`, `Layout.sizeThatFits` i `placeSubviews`, `of:` closure u `onGeometryChange`, getter identity čtený `ForEach`em |
| odkud **ne** | `action:` u `onGeometryChange` (běží mimo aktualizaci — z druhé strany totéž zjištění jako „framework ji gatuje“ z #363) a **cizí vlákno** (vrátí `nil`, ne nesmysl) |
| vlastnictví | hodnota je **autoreleased**, ne +1 — `takeRetainedValue()` složil test `SIGSEGV`em v `objc_release` uvnitř `AutoreleasePoolPage::releaseUntil`. Footprint tvrdil opak (100 000 volání bez `release`: 13,8 → 122,3 MB), protože se v tom měření pool ani jednou nevyprázdnil. Volání má proto **vlastní `autoreleasepool`** — bez něj by se vzorky držely do konce kola runloopu, což je u zaseknutého kola „nikdy“ |
| co nejde | `AGGraphGetCounter` chce `AGGraphRef`, a ten se zevnitř `body` nedá vzít (`AGSubgraphGetCurrent()` je `nil`, `AGGraphGetAttributeGraph` nad `AGGraphGetCurrentAttribute()` skončil `SIGABRT`em). Pojmenované counters (`updates`, `changes`, `transactions`) dá `["format": "graph/dict", "all_graphs": true]`, ale ten prochází **všechny uzly a hrany** (jsou v jeho výstupu vypsané), takže to není nástroj na vzorek každou sekundu |

Čím to **není**: `AGGraphSetTrace` ani `AGGraphSetInvalidationCallback` se nepoužívají, i když by
dávaly přímo události invalidace — obojí si nastavuje sám SwiftUICore (vidět
v `dyld_info -imports`), takže je přepsat znamená sáhnout do toho, co se měří. Privátní framework
se navíc **otevírá jedině se zapnutou diagnostikou** (`GraphProbe.prepare()` z `start()`) a jak to
dopadlo, se píše **do souboru** (`Policy.diagnosticGraphLine`) — „graf nic neřekl“ a „graf nejde
otevřít“ nemají kde splynout.

**Háky sedí tam, kde v kole doopravdy jsme** (`GraphSite`, `RenderDiagnostics.inGraph(_:)`): dotazy
na identitu líných seznamů (`DiffRow.id`, `FileDiff.id`, `ConversationRow.id` — u osy konverzace je
to **jediná** přítomnost aplikace v kole) a čtení geometrie v diffu (`of:` closury v
`DiffPairBlockRowView`, `DiffBlockRowView`, `DiffLineView`, `DiffView`). U `DiffLineView` se ten hák
od #438 ozývá **jen z té větve, která rámeček někomu předá** (viz sekce níž) — v ose konverzace, kde
se ta čísla nasbírala, tedy z aplikace nevede vůbec. Identita jde přes
`diagnosedID` v extension u diagnostiky, ne přes úpravu `id` v modelu, a **vrací tutéž hodnotu** —
jinak by líný seznam se zapnutou diagnostikou přerovnal obsah a měřilo by se něco jiného než bez
ní. Že je každé vyjmenované místo doopravdy zapojené, tvrdí test nad zdrojáky
(`GraphSiteWiringTests`): nezapojené místo by v záznamu chybělo, a to se nedá odlišit od „tímhle
místem kolo neprochází“ — tedy od té věty, kterou se u #361 hledá příčina.

**Vzorky mají dvě meze a obě jsou vyjmenované.** `RenderDiagnostics.stackBudget` = 8 na úsek
a odstup `interval / stackBudget` mezi nimi. Rozpočet proto, že hořící kolo by jinak vyrobilo
tisíce dotazů za sekundu; odstup proto, aby těch osm bylo **histogram** přes sekundu, a ne osmkrát
tentýž bod. Hodiny se čtou až za rozpočtem (`DispatchTime`, ne `Date` — posun systémového času
nesmí odstup poslat do minusu), takže po vyčerpání je z celého háku inkrement pod zámkem.

Do záznamu jde za hlavní řádek úseku (`Policy.graphDiagnosticLines`) tohle:

```
2026-08-21T11:22:14+0200 za 1.01 s: 0 kol runloopu, 1.007 s CPU — HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU
    graf: DiffRow.id=857 FileDiff.id=453 DiffPairBlockRow.geometry=172
    zásobník: 6 dotazů, 6 vzorků, kořen LazySubviewPrefetcher<LazyVStackLayout>=3 …, vrchol LazySubviewPlacements<LazyVStackLayout>=3 …, změněné vstupy CoordinateSpaceNameTransform=5
    #0: 2254672 LazySubviewPlacements<LazyVStackLayout> -> Array<_LazyLayout_PlacedSubview>
    2254192 CoordinateSpaceNameTransform -> ViewTransform, changed
    #1: 2255208 LazySubviewPrefetcher<LazyVStackLayout> -> ()
```

Tři rozhodnutí, která na tom výpisu stojí:

- **Ticho nedostane přílohu.** Řádky o grafu se píšou jen tehdy, když je hlavní řádek úseku;
  nasbírané se ale zahodí tak i tak, jinak by čísla nesl úsek, ve kterém se nic z toho nestalo.
- **Dotazy i vzorky, ne jedno číslo.** Dotaz, ze kterého nic nepřišlo, znamená „tady se graf
  neaktualizoval“ — a to je informace, ne nula k zamlčení.
- **Do souboru jdou rámce a vstupy s `changed`, ne celý výpis.** AttributeGraph u rámce `#0`
  vypíše i **všechny jeho vstupy** a jména typů jsou generická jména celého podstromu: jeden
  takový řádek měl nad skutečným diffem v okně **1,5 kB** a blok jich měl desítky, takže by hořící
  okno vyčerpalo strop 8 MB za pár minut — zrovna tehdy, když je záznam potřeba. Meze jsou proto
  tři a všechny vyjmenované: délka řádku (`Policy.graphLineLimit`, 200 znaků), **počet položek
  v jednom histogramu** (`graphHistogramLimit`, 6 — a co se nevejde, se přizná jako `+N dalších`,
  protože zkrácení jedné hodnoty nebrání tomu, aby jich osm vzorků nasypalo desítky) a to, že se
  **propustí jen řádek, ze kterého jde vytáhnout typ** — jinak by se po změně privátního formátu
  do záznamu opisoval syrový text vydávaný za rámec, přitom o tomhle výpisu je slíbeno, že
  u cizího formátu zmlkne. Cena zkrácení je, že dva různé dlouhé typy mohou v souhrnu spadnout do
  jednoho řádku; je to vědomé — informace je v hlavě jména.
- **Vzorek, který přeteče přes hranici úseku, se zahodí.** Mezi odebráním (`armSample`) a zapsáním
  se zapisovací vlákno může dostat ke `flush()`u; bez toho by zásobník spadl do **nového** úseku,
  kde pro něj není započítaný dotaz, a v řádku by stálo „0 dotazů, 1 vzorků“. Rozhoduje o tom
  `generation`: dotaz zůstává v tom úseku, ve kterém začal, a do dalšího se vzorek nepřenáší,
  protože do už zapsaného řádku nemá kudy.
- **Na řádku o dostupnosti grafu se `start()` láme stejně jako na hlavičce.** Strop platí na
  bajty, takže hlavička projít může a tenhle řádek už narazit — a diagnostika, která se zapnula
  a nic nezapisuje, je zrovna to splynutí, kterému se tady vyhýbáme dvakrát.

**Co z toho vyšlo nad skutečným oknem** (měření `IdleDiffSpinProbe.graphInstrumentationOverRealWindow`,
projíždění kolečkem, tedy **ne** záchvat): v diffu `DiffRow.id=857 FileDiff.id=453
DiffPairBlockRow.geometry=172` za sekundu, v ose `ConversationRow.id=2113`. Kořenem je v obou
`LazySubviewPrefetcher<LazyVStackLayout>` (tedy ten `signalPrefetch`, který je ve vzorcích ze
záchvatů jediný re-arm), vrcholem `LazySubviewPlacements` a **jediný `changed` vstup je
transformace** — `CoordinateSpaceNameTransform` v diffu, `ScrollViewChildTransform` v ose. Nad
projížděním je to očekávané (obsah se posouvá), takže **to samo o sobě příčinu #361 netvrdí**; cenné
je to jako srovnávací tvar: v záchvatu se z týchž řádků pozná, jestli se transformace mění i tehdy,
když se nikam neroluje.

#### Řádek diffu se ptá na geometrii jen tam, kde ji má kdo přečíst (#438)

`DiffLineView` měl `onGeometryChange` **bezpodmínečně**, přitom ten rámeček slouží jedině tažení
rozsahu (#110): píše se do `DiffRowFrames`, a to jen tehdy, když má řádek identitu (`dragID`)
a krabici (`rangeDrag.box`). Podmínka v kódu byla odjakživa — v `guard` uvnitř **akce**, tedy až
**po** čtení. `of:` closure přitom běží uvnitř aktualizace grafu (tabulka `GraphProbe` výš), takže
se počítala i v tom kole, ve kterém se nepřeloží ani jedno tělo: ve dvou záchvatech #361
**369 546** a **711 018** zásahů `DiffLine.geometry`, v obou druhá nejčastější položka v celém kole.

**Zadání #438 to připisovalo diffu pod jiným tabem; měření to vyvrátilo.**
`IdleDiffSpinProbe.lineGeometryOrigin` projede kolečkem tutéž scénu ve dvou záložkách:

| Vepředu | `DiffLine.geometry` před | po |
|---|---|---|
| diff (split, 13 souborů) | **0** | 0 |
| osa konverzace (60 vláken s `diffHunk`em) | **242** | **0** |

Diff se neptá **ani když je vepředu**, a je to vlastnost kreslení, ne viditelnosti: `DiffView` slévá
řádky do bloků (`DiffRow.blocked(_:)`, `blockedPairs(_:)`), takže `DiffLineView` v diffu nekreslí
ani jeden řádek — text bloku sází `NSTextView` a rámečky hlásí **blok** (#252). Zásahy jsou z osy:
úryvek u vlákna (`ThreadSnippetView`, #158) kreslí `DiffLineView` řádek po řádku a rámeček z něj
nemá kdo převzít — na ose se netáhne. Sedí to i poměrem: v sondě 242 proti 461 dotazům na
`ConversationRow.id`, v záchvatu 369 546 proti milionům.

Řádek proto od #438 vydá `onGeometryChange` **jen ve větvi `reportsFrame`** (obojí: identita
i krabice). Tři věci, které na tom stojí:

- **Podmínka není nad měnícím se stavem.** Obojí dává volající a je to konstantní po celý život
  řádku — v diffu vždycky (`DiffRowView`), na ose nikdy (`ThreadSnippetView`), takže se větev
  nepřepíná za běhu a `@State` v řádku nemá jak propadnout. (Do #446 to platilo i o `DiffPairView`;
  ten je smazaný, takže tu podmínku vyplňuje jediný volající — viz *Co z diffu doopravdy dojde
  ke kreslení*.)
- **`dragAnchor` v podmínce být nesmí.** Řádek, který komentář neunese, se hlásí s **prázdným
  seznamem** — a právě tím vyklízí zastaralé plochy pod sebou (`DiffRowFrames.note(_:covering:of:)`).
  Bez toho hlášení by v krabici zůstaly plochy z minulého rozvržení a tažení by chytalo řádky vedle.
- **Kolo z #361 to nezavírá.** Doložené je zlevnění a jedna věc navíc:
  `GeometryActionBinder<_GeometryActionModifier<CGRect>>` byl na ose **kořenem 3 ze 6** odebraných
  zásobníků a po opravě je **0 ze 6**, tedy z osy zmizel jeden kořen aktualizace grafu. Že tím kolo přestane vznikat, se
  tvrdit nedá — v harnessu se za třináct kol nevyrobilo ani jednou.

**Na obrazovce není vidět nic** a plyne to z toho, proč je v repu `onGeometryChange` místo
`GeometryReader`u: měří, do rozvržení nezasahuje. Tažení rozsahu v diffu obsluhují bloky
(`DiffBlockRowView`, `DiffPairBlockRowView`), kterých se změna netýká.

## `RepoCheckout` (`App/Checkout/`)

Vlastní pracovní kopie aplikace. Tvrdá podmínka: **nikdy nesahat na uživatelovy klony.**

| Typ | Co dělá |
|---|---|
| `RepoCheckout` | Protokol: `prepare` (bare klon), `worktree`, `trackedFiles`, `removeWorktree`, `forgetPullRequest` a `trackedPullRequests`. Vše idempotentní |
| `GitRepoCheckout` | Implementace nad `git`: první volání klonuje, další fetchuje |
| `CacheLayout` | Kde co leží — klony, stromy **i uložené nálezy**. `root` je injektovatelný, aby testy nesáhly do skutečné cache, a u běžící instance se odvozuje z `CFBundleName` (#228) |
| `CheckoutCoordinator` | Aktor: souběžná volání nad stejným klíčem se spojí do jedné práce |
| `CacheEviction` | Úklid cache: repa bez otevřeného PR, pak LRU do rozpočtu (10 GB) |
| `CheckoutError` | Typované chyby + klasifikace stderru `gitu` jako čistá funkce |

Věci, které se u toho nemají rozbít:

- **Kořen cache je `CFBundleName`, ne konstanta `"PRism"`** (#228). Na tom stojí sloty: build
  ve slotu `a` se jmenuje `PRism-a`, takže má vlastní konfiguraci, klony i uložené nálezy
  a **nesáhne na data instance, se kterou se pracuje**. Bez toho by rozestavěný build
  s rozbitou persistencí smazal rozdělaný draft, tedy ručně psanou práci.

  Chybějící `CFBundleName` **shodí aplikaci** a nespadne na `?? "PRism"`. Tichý default by
  znamenal, že se slot potichu vrátí do cache hlavní instance — tedy přesně to, čemu se
  vyhýbáme. Klíč je v `Info.plist` napevno, takže jeho absence není provozní stav, ale
  rozbitý bundle.

  Hlídá to test „Slot na cache hlavní instance nesáhne, ani jedním směrem“, který se ptá
  `contains` na obě strany. Chytá i past, do které by se spadlo připojením slotu bez
  oddělovače — `"PRism"` + `""` je pořád `"PRism"`.
- **Soubory se vypisují `gitem` (`ls-files`), ne `FileManagerem`.** Ignorované složky
  (`vendor/`, `node_modules/`, buildy) jsou zrovna ty, kterých je nejvíc — procházení
  disku by jimi odhad jazyka převážilo. Ověřené je to integračním testem, protože
  z argumentů poznat nejde, jestli `ls-files` v odpojeném stromu nad partial klonem vůbec
  něco vrátí.
- **Worktree je klíčovaný `(PR, headSha)`**, ne jen PR. Nálezy visí na `headSha`, takže dva
  běhy nad různými commity téhož PR si nesmí sáhnout na stejný strom. Naopak dva skilly
  nad **stejným** commitem strom sdílejí — proto je vytvoření idempotentní.
- **Zadání pro reviewera leží vedle stromu, ne v něm** (#120,
  `CacheLayout.intentFile(for:at:)` → `worktrees/<owner>/<repo>/<pr>-<sha>.md`). Uvnitř pracovní
  kopie by ho `git status` i `git diff` vypsaly jako součást změny, kterou má reviewer posoudit —
  tedy tatáž úvaha, kvůli které leží `lastUsedMarker` vedle klonu a ne v něm. Klíč je stejný jako
  u stromu, takže zadání sdílejí všechny skilly jednoho review a po novém commitu zestárne
  společně se stromem i s nálezy.

  **Úklid nedostal vlastní cestu a je to schválně.** `CacheEviction.evict` maže celé
  `worktrees(of:)`, takže zadání jde s klonem, a `discardUnwantedWorktrees` čte číslo PR z názvu
  (`42-<sha>.md` → 42), takže odejde s tím, jak PR vypadne ze sledovaného seznamu. Vlastní mazací
  cesta by byla další místo, na které se dá zapomenout — a `RepoCheckout.removeWorktree` z aplikace
  dneska **nikdo nevolá** (jen testy), takže by se na ni ani nespoléhalo.

  Cena je, že **`CacheEviction.allWorktrees()` bere zadání jako „worktree“** — vypisuje každé dítě
  té složky, ne jen složky. Filtr tam vědomě **není**: kdyby se soubory odfiltrovaly, zadání
  zavřeného PR by nesmazal nikdo. Nepřesné jméno metody je menší cena než neuklizený soubor;
  hlídají to dva testy v `CacheEvictionTests`.
- **Hranice cache bydlí v `CacheFile`, ne v jednotlivých storech** (#458). Do té doby si ji každý
  opsal sám — a pokaždé jinak: `ReviewStore` a `ReviewDraftStore` měly `contains` jen u mazání
  a `isSymbolicLink` jen u čtení, `CacheTextFile` obojí, `AskStore` jen u mazání. Přesně ten vzor,
  na který si `CLAUDE.md` stěžuje: *kontrola, která jinde v repu je, a tady chybí*. `CacheFile`
  vydává **verdikt** (`Refusal.outsideCache` / `.symbolicLink`), ne hotovou chybu, takže si každý
  store umí říct, o **který rozhovor nebo draft** jde — obecné „cesta vede mimo cache“ v panelu
  nikomu neřekne, co se stalo. `CacheFile.checked` je throwing podoba pro volající, kteří vlastní
  chybu nemají (`CacheTextFile`).

  **Mazání chce jen `contains`, a je to rozdíl, ne nedůslednost.** `removeItem` nad odkazem smaže
  **odkaz**, ne jeho cíl, takže je neškodné — a hlavně je to jediná cesta, jak takovou anomálii
  z cache dostat pryč. Kdyby ji mazání odmítalo taky, zůstal by odkaz v cache navždycky
  a `Nový rozhovor` by ho neuklidil.

  **Co se u #458 vědomě nezměnilo:** `ReviewStore.save` dál bere odkaz na **samotném souboru** jako
  prázdné místo a přepíše ho atomicky (zapsané rozhodnutí z #106, viz níž) — doplnila se u něj jen
  ta chybějící polovina, tedy hranice. A **ledgery pod kořenem cache** (`SpendLedger`, `ActivityLog`,
  `AnnouncedPullRequests`, `RunningSessions`, `HandoffLedger`, `AutoRunLedger`, `InterruptedRuns`,
  `ConfigStore`) stráž nedostaly: jejich soubory jsou **přímé děti kořene**, takže mezi kořenem
  a souborem není složka, která by mohla být odkazem, a `contains` by u nich byl vždycky pravdivý.
  Zůstává u nich odkaz na samotném souboru — **zapsaná mezera**, ne záměr; všechny zapisují
  `.atomic` (odkaz se nahradí, cíl zůstane) a čtou přes `try?`, takže by kontrola neměla kde být
  vidět. Až se u některého objeví cesta, která na tom stojí, patří sem `CacheFile.refusal`.
- **Zápis vedle klonu i vedle stromu jde přes `CacheEviction.insideCache`.** Je to jediná
  kontrolovaná cesta — používá ji razítko použití repa i `ReviewIntentStore` (#120). Symlink
  v rodičovské komponentě umí zápis vyvést mimo cache, a „pracuje výhradně ve své cache“ je tvrdá
  podmínka; vlastní kopie té kontroly v každém storu by se dřív nebo později rozešla.

  **`contains` ale nestačí a `isSymbolicLink` musí přijít vedle něj** (nález Copilota na #352).
  `contains` rozbaluje symlinky na **obou** stranách, takže odkaz na samotném souboru přes něj
  projde — cíl vyjde rovný cíli. U zadání to bolí ve dvou směrech a v jednom z nich to bolelo
  doopravdy:
  - **Čtení** (`existingFile`) vrací cestu, která jde do promptu a kterou reviewer otevře `Read`em,
    takže odkaz by session poslal čtením **mimo cache aplikace**. To byla skutečná díra.
  - **Zápis** (`save`) na tom nestál — **změřeno**: `write(to:options: .atomic)` odkaz **nahradí**
    souborem a cíl nechá být, kdežto tentýž zápis **bez** `.atomic` cíl přepíše. Bezpečnost tedy
    visela na jednom příznaku u zápisu, což je slabší záruka než vyjmenovaná kontrola, takže
    `isSymbolicLink` je i tam.

  Je to tatáž kontrola, jakou u čtení z cache mají `ReviewStore` i `ReviewDraftStore` (#106) —
  a přesně ten druh nálezu, který `CLAUDE.md` popisuje jako „kontrola, která jinde v repu je,
  a tady chybí“.
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
  *soubor* se ale vylistuje a přečetl by se **mimo cache**. Odmítají ho proto **oba story**
  (#106) a odpovídá na to **jedno místo**, `CacheLayout.isSymbolicLink` — potřebují to dva
  a je to totéž pravidlo o hranici cache jako `contains`.

  Pozor na past: kontrola „leží soubor tam, kam patří“ postavená na rozbalení symlinků na
  **obou** stranách takový odkaz nezachytí, protože cíl vyjde rovný cíli. Symlink se musí
  odmítnout výslovně (`.isSymbolicLinkKey`).

  **Nestačí to ve výpisu**, i cílená čtení podle cesty se k odkazu dostanou: `save` ho bere
  jako **prázdné místo** (zápis je atomický, takže odkaz nahradí náš soubor a cíl zůstane
  netknutý) a `dismiss`/`restore` jako `recordNotFound` — **náš** záznam tam není a číst
  cizí kvůli tomu, abychom do něj zapsali odmítnutí, je to poslední, co chceme.
  Ověřeno dočasně vrácenou regresí, po které `load` cizí soubor přečetl jako záznam
  a odmítnutí nálezu prošlo nad cizími daty.
- **Maže se jen uvnitř cache.** Kdo maže podle toho, co našel na disku, si před smazáním
  ověří, že cesta po rozbalení symlinků pořád leží pod kořenem — `removeItem` přes odkaz
  v rodičovské komponentě smaže **cíl**, ne odkaz. Odpovídá na to `CacheLayout.contains`,
  jedno místo pro eviction i `ReviewStore`. Je to **jiná otázka než `isSymbolicLink`**:
  `contains` rozbaluje **rodiče** a řeší mazání, `isSymbolicLink` řeší **čtení** listu.
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

## `ReviewStore` (`App/Store/`)

Výsledky review na disku: jeden JSON soubor na `(repo, PR, headSha)` pod
`reviews/<owner>/<repo>/<pr>-<sha>.json`.

| Typ | Co je |
|---|---|
| `ReviewStore` | Aktor: `save`, `dismiss`, `restore`, `markCurrent`, `load`, `delete`, `cleanUp`. Atomický zápis |
| `ReviewStoreError` | Jediná vlastní chyba: záznam, do kterého se má zapsat, na disku není |
| `AutoRunLedger` | Aktor: kolik review dnes spustil automat. **Na disku**, aby limit nešel obejít restartem |
| `AnnouncedPullRequests` | Aktor: které PR se už ohlásily jako nové (#85). **Snímek** poslední fronty na disku, ne rostoucí log |
| `SpendLedger` | Aktor: co dneska stálo review (#148). **Na disku**, aby součet nevynuloval restart |
| `InterruptedRuns` | Aktor: běhy, které začaly a neví se, jestli doběhly (#97). Co v souboru po startu zbylo, aplikaci nepřežilo |
| `HandoffLedger` | Aktor: která zadání jsem už předal agentovi (#334) — `handoffs.json`, razítko na PR, lhůta 90 dní. **V cache, ne v předvolbách**: nese identity nálezů, tedy materiál review |
| `ReviewRecord` | Obsah jednoho souboru: PR, `headSha`, běhy, `isStale`, `closedAt`, odmítnutí, **kontrola nálezů** (#150, volitelná) |
| `StoredReviewRun` | Jeden běh: skill, `outcome`, session id, nálezy, `droppedFindings`, čas, **cena** (#148, volitelná) |
| `StoredRecheck` | Kontrola nálezů (#150): `againstHeadSha`, `outcome`, session id, stavy klíčované `Policy.key(of:)`, čas, cena |

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
- **Kontrola nálezů se ukládá k záznamu těch nálezů** (#150, `saveRecheck(_:for:at:)`), tedy
  k commitu, na kterém vznikly — ne k hlavě, proti které se kontrolovalo (tu nese
  `againstHeadSha`). Záznam pro novou hlavu by musel vzniknout **bez jediného běhu**, a takový
  vyhrává v `Policy.currentRecords` (není zastaralý), takže by nálezy z minula z okna zmizely
  právě ve chvíli, kdy se na ně ptám.
- **`save` kontrolu do `runs` nepustí** (`ReviewStoreError.notAReviewRun`). Kdyby se to povedlo,
  přepsala by běh téhož skillu (`replace(_:)`), přidala si chip a její „nálezy“ by se počítaly do
  návrhu verdiktu — reviewer, který nikdy nic nenahlásil. Je na to test, který tvrdí, že se
  záznam **nezměnil**.
- **`saveRecheck` nesrovnává `isStale`**, na rozdíl od `save`: nálezy dál patří staršímu commitu
  a to, že se na ně někdo ptal, na tom nic nemění. Chybějící soubor je přitom **chyba**, ne nový
  záznam — tatáž úvaha jako u odmítnutí.
- **Počet nezodpovězených nálezů se neukládá.** Spočítá se proti záznamu
  (`Policy.recheck(of:head:)`), protože jen tak odpovídá tomu, co je vidět: uložené číslo by po
  odmítnutí nálezu (#113) přestalo platit.
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
- **Odmítnutí nálezu (#113) je mutace na storu, ne přepis záznamu zvenčí.** Uložení je čtení,
  změna a zápis téhož souboru, takže dva doběhlé skilly a kliknutí v okně by si ho přepsaly —
  tentýž důvod, proč je store aktor. Soubor si najde podle **`finding.headSha`**, ne podle
  viditelného záznamu: nález si commit nese sám a druhá cesta k témuž údaji je druhé místo,
  kde se dá minout. Chybějící soubor je **chyba** (`recordNotFound`), ne založení prázdného
  záznamu — tím by z okna zmizely všechny ostatní nálezy.
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

## `AppStore` (`App/Store/`) a okno (`App/Views/`)

`AppStore` drží to, co kreslí okno: polling seznamu, **výběr řádku**, **stav pracovních
kopií** a **review**. Výběr žije tady, ne ve view — jinak by ho každé přestavění seznamu
zahodilo.

Review orchestruje takhle: `gh pr view` (kvůli `headSha` a `baseSha`) → označit starší
záznamy zastaralými → worktree → **zadání pro reviewera vedle stromu** (#120) → skilly paralelně
→ každý doběhlý uložit do `ReviewStore`. Limit souběžných session hlídá `ReviewRunner`, ne
tenhle kód.

Zadání se připravuje **po checkoutu a před spuštěním skillů** (`prepareIntent(for:of:)`), a to je
jediné možné místo: leží vedle pracovního stromu a session ho musí mít v ruce dřív, než se poskládá
prompt. Nestojí to ani jedno volání navíc — popis PR je v `detail`, který se dotahuje kvůli
`headSha`. Podrobnosti a rozhodnutí jsou u `ReviewRunner` v sekci *Zadání pro reviewera (#120)*.

**Od #154 je to rozdělené na `extension` po zodpovědnostech** — do té doby jeden soubor
o 2508 řádcích a patnácti `MARK` sekcích, tedy tomtéž rozdělení, jen zapsaném na jednom místě:

| Soubor | Co drží | Řádků |
|---|---|---|
| `AppStore.swift` | **Stav, `init`, polling, načítání z disku a úklid** (`forget`) | 871 |
| `AppStore+Review.swift` | Spuštění a průběh review: session, osa, uložení výsledku | 450 |
| `AppStore+Conversation.swift` | Cizí konverzace (#63) a odpovídání do vláken (#73) | 203 |
| `AppStore+Draft.swift` | Rozdělané review (#65, #66) a tažení rozsahu (#110) | 190 |
| `AppStore+Submission.swift` | Odeslání review na GitHub (#67, #68) | 172 |
| `AppStore+Notifications.swift` | Co se ohlásí, když se do okna nikdo nedívá (#82, #85, #87) | 166 |
| `AppStore+Activity.swift` | Cizí aktivita na vlastních PR (#335) — rozhlídka na pozadí (`refreshOwnActivity(in:)` z úspěšného tiku), `notifyAboutForeignActivity(on:)` a `conversationUpdatedAt(for:)` jako předfiltr. Text v řádku si bere `handoffReport(for:).activity`, tedy **žádný druhý getter**. **Nic neodesílá**, je to `fetchConversation` | 91 |
| `AppStore+Feed.swift` | Dění (#414) — načtení záznamu a značky při startu (`loadStoredActivity()`), zápis položek (`recordActivity(_:)`), co je na obrazovce (`activityFeed`, `railActivityCount`, `activityEmptyState`), posun značky při **odchodu** ze sekce (`syncActivityVisit()`), klik na řádek (`show(_ event:)` přes `openTab(_:in:)`) a dopočítaný řádek o zastaralých nálezech. Drží tu i `watchesPullRequestActivity` — brána na spotřebování snímku fronty a razítka oznámení | 152 |
| `AppStore+DiffExpansion.swift` | Rozbalování kontextu mimo hunky (#47), od #317 i v diffu commitu | 139 |
| `AppStore+DraftTransfer.swift` | Přenesení draftu na nový commit (#69) | 103 |
| `AppStore+Diff.swift` | Načtení diffu, pohled a sbalování souborů | 95 |
| `AppStore+IncrementalDiff.swift` | Diff „co od minule přibylo“ (#284) — nabídnout, načíst, zavřít | 87 |
| `AppStore+Automatic.swift` | Automatický režim a denní rozpočet (#25) | 89 |
| `AppStore+Findings.swift` | Zahození záznamu (#81) a odmítnutí nálezu (#113) | 70 |
| `AppStore+Appearance.swift` | Přepnutí vzhledu okna z railu (#278) | 26 |
| `AppStore+Ownership.swift` | Čí jsou PR v seznamu (#330) — `ownLogins`, `ownership(of:)`, `tracksOwnPullRequests` —, od #331 celá sekce `Moje PR`: `visibleOwnPullRequests`, `hiddenOwnPullRequestCount`, `railMineCount`, `ownListEmptyReason`, `dashboardOwnPullRequests`, a od #333 i `ownership(of pr:)` s `author(of:)`. Od #332 tu leží i druhá strana rozřazení — `queuePullRequests`, `visibleQueuePullRequests`, `hiddenQueuePullRequestCount`. **Dotažení loginu je v `AppStore.swift`**, u ostatních věcí, které se načítají při startu, a taky proto, že `viewer` je `private(set)` | 132 |
| `AppStore+AgentPrompt.swift` | Zadání pro agenta na vlastním PR (#333) — `agentPrompt(for:only:)`, od #377 `agentPromptSelection(for:only:toggled:)` (zadání **i seznam položek** pro sheet; výběr si store **nedrží**, bere ho parametrem), předfiltr `hasAgentPromptItems(for:)` bez sazby textu (ptá se tou samou funkcí jako text, tedy i s předvybráním), přepnutí volby, `revealAgentPrompt(in:)` a `openAgentPrompt(in:)` (akce `Prompt →` z řádku: otevřít PR **a** panel). **Nedrží cestu ven**: prompt končí ve schránce nebo v souboru | 116 |
| `AppStore+Handoff.swift` | Razítko předání (#334) — `loadStoredHandoffs()` při startu, `handoff(for:)`, `handoffReport(for:)` (od #335 si volající bere **celý report**, ne jedno číslo — pilulka i text novinek se ptají téže funkce), `noteHandoff(of:)` (zapisuje **zkopírování a uložení**, ne otevření sheetu) a `freshAgentPromptSelection(for:)` pro `Sestavit i tak` (od #377 vrací i seznam, protože sheet z něj kreslí zaškrtávátka). Do paměti hned, na disk asynchronně | 78 |
| `AppStore+Detail.swift` | Detail PR a jeho záložky | 59 |
| `AppStore+Commits.swift` | Commity PR do tabu `Commity` (#316) | 37 |
| `AppStore+Metadata.swift` | Labely a vyžádaní reviewery (#392) — `loadMetadata(for:)` s detailem (cache podle `updatedAt`), nabídky `loadRepositoryLabels(for:)` a `loadAssignableUsers(for:)` **až na otevření** (volání `gh` navíc, které se má platit jen tehdy, kdy se nabídka otevře), a dvě akce (`toggleLabel(_:on:)`, `requestReview(from:on:)`), které si publisher **nedrží** — skládá se uvnitř `MetadataSubmission`. Po úspěchu se snímek přepíše z odpovědi GitHubu, ne dalším čtením | 191 |
| `AppStore+CommitDiff.swift` | Rozkliknutý commit a jeho diff (#317) | 80 |
| `AppStore+Terminal.swift` | `openInTerminal(_:)` do `Terminal.app` (#453) — od #460 **bez volajícího**, drží se jako záloha (viz specifikace) | 47 |
| `AppStore+TerminalDrawer.swift` | Zásuvka (#459) a **relace v ní** (#460): `toggleTerminal()`, `prepareTerminalDrawer(for:)` (hledání adresáře **mimo hlavní vlákno**, protože eviction klony maže), `resumeInDrawer(_:for:)` za `▶`, `selectTerminalSlot(_:)`, `terminalRows(for:)` a úklid — `stopTerminal(for:)` maže **celý seznam relací** toho PR, `stopTerminalsBeforeTermination()` všechny. **Nedrží plochu ani proces** — ty jsou v `TerminalHost` za protokolem | 222 |

Čtyři věci, na kterých to rozdělení stojí:

- **Dělí se metody, ne data.** Uložený stav zůstal v `AppStore.swift`, protože jeho invarianty
  se drží tím, že jsou na jednom místě — mapa, do které zapisují tři soubory a každý si o ní
  myslí něco jiného, je horší než dlouhý soubor.
- **Řezalo se podle `MARK` sekcí, které tam už byly.** Nebylo to nové rozdělení, jen se přepsalo
  do souborů; proto se nemusel měnit **ani jeden test** (`Tests/` je v tom PR nedotčené).
- **`private` členy, na které extensiony sahají, musely být `internal`** — 59 z nich. Je to cena,
  a je vidět: dnes je `store.gateway` dostupný z celé aplikace. Nic se tím **neotevírá ven**
  (jeden modul) a **tvrdou podmínku č. 1 to nemění**, protože publisher polem storu není a
  `GitHubGateway` je pořád bez zápisových metod. Zabalit závislosti do jednoho typu, aby stačilo
  otevřít jedno pole, by znamenalo přepsat `init` — a s ním testy, které store staví parametry.
- **`AppStore+Review.swift` je pořád velký a schválně jeden.** Běh review je jedna cesta od
  `startReview` přes `runSkills` a `drain` po `finish`; rozříznout ji uprostřed znamená hledat,
  kde pokračuje.

Věci, které se u toho nemají rozbít:

- **`pullRequests` je plný seznam, `visiblePullRequests` je po filtru** (#117) — a **rozdíl mezi
  těmi dvěma gettery je jediné, co dělí filtr od mazání cache**. Zúžený čte jedině seznam PR
  a detail vybraného řádku; plný čte `knownRepositories` (okno nastavení musí vidět i repo, které
  jsem si schoval — je to zrovna to, u kterého chci něco přenastavit), `queueSummary` (souhrn je
  o obsahu fronty, ne o pohledu — #155), `filterOptions` (nabídka filtru i **počty u jejích
  položek** — #199; ze zúženého seznamu by čísla klesala podle právě odškrtaného a nabídka by
  přestala odpovídat na otázku „co se stane, když tohle zapnu“), `handleNotificationClicks`,
  `startAutomaticReviews` po zahození nálezů (#81) a úklid, který bere `summaries` z tiku.
  Kdyby na zúženém seznamu viselo cokoli z úklidu (`forget(whatIsNotIn:)`, `CacheEviction`,
  `ReviewStore.cleanUp`, rušení automatických review), **zapnutí filtru by zahodilo diffy a konverzace, smazalo cache a zrušilo
  běžící review**. Je na to sada testů proti fakes, ne úvaha o tom, kdo dnes co čte — ověřená
  vloženou regresí (když `pullRequests` filtruje sám, spadne osm testů).
- **Filtr nepřežije restart** a je to jediný stav v okně, který umí PR **schovat úplně** — restart
  je proto pojistka proti zapomenutému filtru, protože zmizelý PR vypadá jako vyřízený. Na trvalé
  schování je `sources` v konfiguraci (dotaz umí i `-author:`): to je změna toho, **co se stahuje**,
  a patří do nastavení, ne do lišty.
- **`viewer` je prázdný, dokud login nedorazí — a prázdný znamená „nevím“, ne „to jsem já“** (#330).
  Dotahuje se **jednou při startu** (`loadViewer()`, `gh api user`) a **souběžně s pollingem**, ne
  před ním: seznam PR nemá proč čekat půl sekundy na údaj, který se nemění. Dokud tam není,
  `Policy.ownership` vrací u všeho `.theirs`; opačné výchozí chování by na okamžik po spuštění
  přehodilo celý seznam do „moje“ a fronta cizích PR by zmizela. Je na to test v `Policy` i ve
  storu a **vložená regrese** (`mine.isEmpty → .mine`) shodí jedenáct testů, mezi nimi i ty
  z #114 — což je zároveň doklad, že porovnání je doopravdy na jednom místě.

  **Ne z `Conversation.viewer`**, který týž login taky nese: ten je až z načtené konverzace
  vybraného PR, takže v seznamu k dispozici není. `AppStore.isOwnPullRequest(_:)` (#114) na něm
  zůstává schválně — přepnout ho na `viewer` ze storu by změnilo, kdy se v panelu předvyplňuje
  verdikt, a to je viditelná změna a věc panelu vlastního PR (#333), ne téhle součástky. Sdílené je
  proto jen **porovnání** (`Policy.ownership(ofAuthor:mine:)`), ne zdroj loginu.

  **Selhání dotazu se nedrží jako vlastní stav a mlčí se o něm vědomě**: `gh api user` sahá na týž
  `gh` a token jako polling, takže co položí jedno, položí i druhé — a to už v okně vidět je
  (červený puntík GitHubu i s větou). Druhý, tišší opis téhož signálu by musel někde být nakreslený,
  tedy nová věc na obrazovce. Co zbude, je „nevím“, tedy všechno cizí; vysvětlit prázdnou sekci
  `Moje PR` je věc jejího prázdného stavu (#331).
- **K filtru se blokující nález dopočítává na jednom místě** (`passesFilter(_:)`, #371). Osa „jen
  blokující“ nestojí na `PullRequestSummary`, ale na uloženém záznamu, takže si ji `filter.matches`
  nemá kde vzít sám — a tři místa, která počítají schované PR (`hiddenQueuePullRequestCount`,
  `hiddenOwnPullRequestCount`, `ownListEmptyReason`), by si tu odpověď složila každé po svém. Sada
  blokujících kategorií je u toho **globální, ne per repo** (`hasBlockingFinding(_:)`), tedy tatáž,
  s jakou počítá kartu `Blokuje` getter `dashboard`: filtr, který ta karta zapíná, musí ukázat právě
  ta PR, která napočítala — s per-repo sadou by šlo kliknout na `Blokuje 1` a dostat prázdný seznam.
  Řádek seznamu si dál bere tu svoji (`queueRow(for:)`), protože mluví o jednom repu, ne o frontě.
- **Na sekci railu se přepíná `show(_:)`**, ne dvěma přiřazeními u volajícího (#371). Sekce je obsah
  **domácí** záložky, takže bez `activeTab = .home` by se nad otevřeným PR nestalo nic viditelného —
  a od #371 tam chodí dvě věci (paleta ⌘K a karty i patky dashboardu), takže by se to zapomnělo
  v jedné z nich. Druhé přetížení bere `DashboardDestination`, tedy i `blockingQueue`: filtr se u něj
  nastavuje **tou samou cestou jako filtrovací tlačítko** (`setFilter`, #117), protože ta srovnává
  i výběr, a **ostatní osy zůstávají, jak si je člověk nastavil** — karta zapíná jednu osu, ne nový
  filtr.
- **Zapsat filtr jde jedině `setFilter(_:)`**, protože se s ním musí srovnat výběr: vybraný PR mimo
  filtr výběr **ztrácí** (detail PR, který v seznamu není, se nedá zavřít ani znovu vybrat).
  Nic se tím neztrácí — draft leží na disku a běžící review běží dál. Ruší se to **jen tam**, ne
  pokaždé, když vybraný PR ze seznamu vypadne: PR, které z fronty odešlo tikem, si výběr drží
  (dnešní chování, mergnutý PR jde ještě dočíst).
- **Automat filtr neřeší.** Review na schovaném repu se dál plánuje; vypnout ho jde `mode: manual`
  per repo. Kdyby to filtr vypínal, slil by se pohled s nastavením a stav „schoval jsem si to, tak
  se to nereviewuje“ by nebyl kde ukázat.
- **Klik na notifikaci PR, které filtr schoval, filtr vymaže** — rozhodnuto u #117, v zadání to
  nebylo. Kliknutí je výslovná žádost ten PR vidět, takže mlčení by bylo nejhorší. Původní druhý
  důvod (že `ContentView` hledá detail ve **viditelném** seznamu, takže by se nenakreslil) od
  záložek (#180) **neplatí** — obsah záložky se hledá v plném seznamu (`summary(for:)`), takže se
  nakreslí i pod filtrem. Zůstává ten první a k němu důsledek: PR by byl otevřený v okně a v seznamu
  pod ním by nebyl, tedy dvě různá tvrzení o tomtéž. Že filtr zmizel, je vidět v liště. Rozhoduje
  o tom `Policy.notificationClick` (#409), ne obsluha proudu.
- **Důvod prázdna skládá store, ne polling** (`listEmptyReason`): polling o stavu okna neví a vědět
  nemá. Pořadí rozhoduje `Policy.listEmptyReason` a **nad selhaným tikem vyhrává chyba načtení, ne
  filtr** — „schoval jsem ti to filtrem“ nad daty, která nedorazila, je nepravda.
- **Konfigurace vchází do běžící aplikace jednou cestou** (`apply(_:)`), ať přišla z disku, nebo
  z okna nastavení. Kdyby byly dvě, jedna z nich by časem zapomněla něco přepsat. Proto se tam
  nastavuje i **vzhled okna** (#278): `NSApp.appearance` platí naráz pro všechna okna, tedy i pro
  to, které v době přepnutí není vpředu, a nastavení se dá otevřít i se zavřeným hlavním oknem —
  ve view by se změna minula obojí. Cíl je za protokolem (`AppearanceApplying`) a v testech
  **chybí**: živý cíl je `NSApp`, tedy hostitel testů, a vynucený režim by přetekl do render sond,
  které si režim nastavují samy. Ta cesta je celá v `AppAppearance.swift`, takže `App/Store/`
  nemusí znát AppKit.
- **Přepínač vzhledu v railu je volba, ne sekce** (#278). Rail kreslí sekce z `RailSection.allCases`
  a přepínač stojí **pod oddělovačem**, mimo ten výčet — kdyby byl jeho případem, šlo by na vzhled
  „přepnout jako na obrazovku“, nabídl by se v ⌘K mezi sekcemi (`Policy.paletteActions` staví
  položky sekcí z týchž `allCases`) a v okně by zbyla prázdná plocha. Drží to dva testy, oba
  negativní: výčet sekcí je pořád úplný (od #331 čtyřprvkový) a v paletě není položka se slovem
  „vzhled“.

  **Z `allCases` ale plyne i to, co se udělat musí** (#331): nová sekce se v railu i v paletě objeví
  sama, takže se na ni snadno zapomene **jméno ve čtvrtém pádě** (`Policy.paletteTitle(of:)`) — bez
  něj by v paletě stálo „Otevřít Moje PR“, tedy nadpis nalepený do věty. A `RailSection` je zároveň
  jediné místo, kde je vidět **pořadí položek v railu**; `mine` leží mezi `queue` a `drafts` schválně.
  Vlastní PR jsou od #336 v paletě **druhá skupina** (`CommandPalette.Group.myPullRequests`), takže
  je výčet sekcí railu a výčet skupin palety dvě různé věci — obě ale rozřazuje týž
  `Policy.ownership`.

  **Rail nedrží vlastní stav** — čte `configuration.global.appearance` a zapisuje
  `AppStore.setAppearance(_:)`, takže v okně není druhá pravda o tom, jaký režim platí. Zápis jde do
  souboru (ne jen do paměti jako odchylka pohledu na diff v liště), protože volba má přežít restart;
  shodná hodnota se zahazuje, aby výběr toho, co už platí, nepřepsal ručně editovaný soubor.
  **Selhání zápisu se hlásí** (`appearanceFailure` v `AppNoticesView`): vzhled se totiž uplatňuje až
  po úspěšném uložení, takže bez hlášky by klik do railu nic neudělal a nic neřekl.

  **Ovládací prvek je tlačítko, které klikem cykluje** (`světlý → tmavý → podle systému → …`), ne
  nabídka: nabídka byla první verze a uživatel ji zamítl. Stav proto nese **ikona** — slunce, měsíc,
  kolečko s „A“ pro automat (`AppearanceMode.railSymbol`) —, což byla do #299 **vědomá odchylka od
  návrhu**, který kreslil jedno půlkolečko bez ohledu na stav; #299 to do mockupu dokreslilo
  (automat, tedy výchozí režim).
  Tři ikony si u toho hlídají **srovnatelnou velikost** (naměřeno 16 × 16, 15 × 16, 16 × 16),
  jinak by tlačítko při cyklení poskakovalo.

  Cyklící tlačítko říká **kde jsem, ne kam se dostanu**, takže to nese nápověda (`Vzhled: tmavý ·
  kliknutím podle systému`) a pro VoiceOver `accessibilityValue` se stavem plus `accessibilityHint`
  s tím, co klik udělá. Bez toho je z tlačítka hádanka.
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

Opakování jednoho revieweera (#149) k tomu přidává:

- **Jedna úloha na PR, ne na `(PR, skill)`.** Na `reviewTasks` visí `isReviewing`,
  `runningReviews` (podle kterého se aplikace ptá před zavřením, #94), rušení automatických
  běhů i ochrana rep před eviction — klíčovat je dvojicí by znamenalo přepsat všechna čtyři.
  Úloha si proto nese **podmnožinu** (`RunningReview.skills`). Cena je, že se opakování nedá
  spustit, dokud nad PR běží jiné review; ten stav sám za chvíli skončí a chip u něj mezitím
  ukazuje spinner.
- **Podmnožina je `nil`, ne snímek celé sady.** Sadu ještě může změnit odhad jazyka repa, který
  běží až nad pracovní kopií — a platit má ta, se kterou běh doopravdy jede. Proto se čte až
  v `runSkills`, ne při spuštění.
- **Osa se maže jen tomu revieweerovi, který se opakuje.** Nový běh ji jinak nuluje celou;
  u opakování by tím zmizel průběh ostatních, tedy to, kvůli čemu se do tabu chodí.
- **Za běžící se považují jen skilly, které běh pouští** (`runningReviewers`). Celá sada by
  chipy ostatních přepnula na spinner a přestaly by ukazovat výsledek, který mají uložený.
- **Značky přerušených běhů (#97) se mažou jen za spuštěné reviewery.** Značka po skillu, který
  tenhle běh nepouštěl, pořád platí — smazat ji znamená přijít o nálezy, které po něm zbyly
  v transcriptu. A **při zavírání aplikace se nemažou vůbec** (#264, viz sekce o okně).
- **Prázdná podmnožina nespustí nic.** Byl by to běh, který utratí checkout a nic nezjistí.
- **Denní rozpočet se opakování netýká**, jako každého jiného ručního spuštění.

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
- **Co nedoběhlo, se dotáhne z transcriptu** (#97). Dialog při zavření (#94) pokrývá jen to, co
  způsobí uživatel; pád aplikace, `kill` ani restart Macu odchytit nejdou — a nálezy se tam
  ztrácely stejně. Značka (`InterruptedRuns`) se zapíše, jakmile dorazí `session_id`, a co
  v souboru po startu zbylo, se přečte z transcriptu a uloží jako `interrupted`.
  **Od #264 tudy chodí i zavření aplikace**: zabitá session je nedoběhlý běh jako každý jiný,
  takže se její značka nemaže. Ověřeno spuštěním — po zabití vyšel řádek `přerušeno`, ne
  `neběželo`.
  - **Značka se zapisuje v proudu událostí a s `await`**, ne ve vlastním tasku. Odložený zápis
    se umí propsat až po tom, co běh doběhl a značku smazal — pak zůstane ležet nad hotovým
    během. Chytil to test, ne úvaha.
  - **Maže se až po vyprázdnění proudu, a to celá sada** — ne jen uložené běhy. Zápis jde přes
    proud, uložení výsledku ne, takže by se smazání umělo předběhnout. Celá sada proto, že sem
    se dojde jedině po skončeném review: pokrývá to i **zrušený** běh, který se schválně
    neukládá, takže by mu značka zbyla a příští start by z transcriptu vzkřísil nálezy, které si
    člověk zrušil. Po pádu se sem naopak nedojde vůbec, a o to jde. **Výjimka je zavírání
    aplikace** (#264): tam se sem dojde, ale mazat se nesmí — proto `isTerminating`.
  - **Značka nad uloženým během nic nepřepíše.** Pád mezi zápisem výsledku a smazáním značky
    jinak z hotového review udělá nedodělek (`interrupted` přes `finished`). Je to důležitější
    pojistka než pořadí mazání, protože to okno zavřít nejde.
  - **Značka bez transcriptu se zahodí.** Strom mohla sebrat eviction a bez něj se to nikdy
    nedotáhne — ležela by tam navždycky.
  - **Transcript bez jediného `ReportFindings` se neuloží.** Běh, který nálezy nikdy nenahlásil,
    by v řádku vypadal jako „reviewer nic nenašel“ — přesně to tvrzení, kterému se #97 vyhýbá.
  - **Nečitelný transcript není totéž co chybějící.** Chybějící už nebude (strom sebrala
    eviction), takže se značka zahodí; nečitelný tam pořád leží i s nálezy, takže se značka
    **nechá**. Rozlišuje to `do`/`catch`, ne `try?` — ten obě odpovědi slije do `nil`, protože
    Swift výsledek `try?` nad funkcí vracející optional zplošťuje. Chytil to test.
  - **Dotažený běh si nese `sessionID` ze značky.** Transcript má `sessionId`, `stream-json`
    `session_id`, takže parser id nevytáhne — a bez něj by osa neuměla nabídnout
    `claude --resume` a brána proti přepsání uloženého běhu by neměla co porovnávat.
  - **Dotažení běh nepoloží.** Je to záchranná síť nad daty, která už jednou spadla pod stůl:
    jedno selhání nesmí zastavit ostatní ani položit start; značka zůstane a příští start to
    zkusí znovu.
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
- **Odmítnutí nálezu (#113) další review nespouští**, na rozdíl od zahození celého záznamu.
  Zahození znamená „pusť to znovu, tenhle výsledek je k ničemu“; odmítnutí je opak — nic nového
  se nezjistilo, jen jsem jeden nález posoudil a ostatní nechal platit. Paměť se přitom srovnává
  **až podle zapsaného záznamu** (`applyDismissal`): kdyby se mapa měnila před zápisem, bylo by
  odmítnutí vidět a po restartu zmizelo. Selhání zápisu je vidět (`dismissalFailure`) — tichý
  `try?` je tady přesně ten vzor z tabulky výš.
- **Nezapsaný nález review položí.** Selhání zápisu se nespolkne: ztracený nález by v řádku
  vypadal jako „neběželo“, tedy jako schválený PR s neohlášenou chybou. Ostatní skilly
  přitom doběhnou, ať se nezahodí i to, co se uložit povedlo.

Vzniká z `ToolPaths` po preflightu (`AppStore(toolPaths:)`); **vlastní ho `PreflightModel`
nad scénami**, ne `ContentView`. Okno nastavení je vlastní scéna (`Settings`) a k `@State`
uvnitř hlavního okna by se nedostalo. Testy si podstrčí fake gateway. Smyčka pollingu visí
na `.task` okna, takže zavření okna ji zruší.

| View | Co dělá |
|---|---|
| `ContentView` | Okno: vlastní hlavička se záložkami, pod ní rail a obsah, dole stavový řádek (#180) |
| `HeaderButton`, `HeaderButtonMetrics`, `RefreshButton` | Tlačítka v pravém koutu hlavičky (`.tbtn` z návrhu, 27 × 25). `RefreshButton` je jediné, které mění podobu podle stavu aplikace — viz *Obnovování je vidět na tlačítku* |
| `FullSizeContentWindow` | Roztažení obsahu pod titulkovou lištu, aby hlavička mohla být vlastní (#180) — a od #245 **vypnutí systémových záložek oken** (`tabbingMode = .disallowed`), aby se `⌃Tab` nepřetahoval s AppKitem |
| `AppAppearance`, `AppearanceApplying` | Přepnutí vzhledu celé aplikace (#278) — `NSApp.appearance`, a za protokolem, aby si na hostitele testů nesáhly testy |
| `Palette` | Barvy okna z návrhu, světlá i tmavá varianta — **jeden zdroj pro celou aplikaci** (#180). Krytí je u tichých podkladů (`accentWeak`) v každém režimu jiné, jak to má návrh. Stavové tóny `ok`, `find`, `crit` (#218) jsou pro odznaky a puntíky **a od #277 i pro diff**: `DiffLineView.signColor(of:)` zůstává jediným zdrojem zelené a červené v diffu (aby se `+` v řádku nerozešlo s `+12` nad ním, #156), jen si ji bere odsud, ne ze systému; pozadí řádků má vlastní vyčíslené tokeny (`diffAdded`, `diffRemoved`, `diffAddedWord`, `diffRemovedWord`, `diffMissingStripe`) — viz *Barvy diffu* v sekci `App/Diff/`. Od #279 k tomu tři tóny výstrah (`alertNote`, `alertWarning`, `alertCaution` — `[!TIP]` a `[!IMPORTANT]` si půjčují `ok` a `accent`) a `codeFill` pod kód; `alertWarning` a `alertCaution` jsou **vlastní hex schválně**, protože ty GitHubovy se na hex rovnají `stale` a `crit`. Od #309 `mint` — **dvojice k akcentu**: akcent je to, co se nabízí udělat nebo co běží, mint to, co se jen konstatuje (`2×`, `✓ v mém review`, `odmítnuto`). Světlá větev je **vědomá odchylka od návrhu** (`#0E8F80` → `#0C7E71`), protože hodnota z mockupu byla jediný stavový token pod AA — čísla u `Palette.mint` a v `MintTokenTests` |
| `ReviewTabsView` | Pruh záložek v hlavičce: domů, otevřená review s tečkou stavu a křížkem (#180). Nápověda u **domácí** záložky nese zkratky pruhu `⌃Tab` / `⌃⇧Tab` (#245) — na `ScrollView`u se `.help` neprojeví |
| `SidebarRail` | Svislý rail vlevo — `Přehled`, `Fronta` s odznakem, **`Moje PR` s odznakem** (#331), `Rozdělaná` (#180) a pod oddělovačem **cyklící přepínač vzhledu okna** (#278), který sekce railu není. Šířka zůstává 52 bodů a pátá položka se do ní vejde; odznak u `Moje PR` počítá **práci, ne PR**. Od #366 je odznak **červený (`--crit`) a uvnitř rámu ikony**, jak ho kreslí návrh — viz *Odznak v railu* |
| `HomeView` | Obsah domácí záložky podle railu. Nad dashboardem **bez toolbaru** — hlavičku si kreslí sám (#181). Od #331 dostává `openSettings` jako **uzávěr z těla okna**, protože prázdná sekce `Moje PR` bez zdroje nabízí nastavení otevřít |
| `DashboardView` | Startovní obrazovka (#181): pozdrav, **pět karet** (#331), **dvě fronty pod sebou** (`Čeká na moje review` a `Moje PR`), legenda reviewerů a `Co teď`. Věta pod pozdravem je od #332 **dvojitá** (fronta + „na kolika vlastních je co předat agentovi“), jak ji kreslí návrh; nenačtená fronta druhou větu nedostane a číslo se píše **číslicí**, ne slovem jako v mockupu — zbytek okna to dělá stejně. Akcentový proužek nese od #331 karta `Moje PR`, ne `Rozdělaná review` — dva proužky vedle sebe by přestaly znamenat, která karta je ta o mně. Od #371 kreslí blok **nejvýš pět řádků** a pod nimi patku se zbytkem (`Policy.dashboardBlock`), a **čtyři karty z pěti vedou do své sekce** — šipka vpravo nahoře, rámeček v akcentu na hover, ukazováček; `Dneska stálo` nedostane nic z toho, protože nemá kam vést. Popisek karty se šipce **uhýbá odsazením** (`arrowRoom`) a je na jeden řádek: v úzkém okně by se pod ni zalomil a s ním by narostla výška celé řady karet. Od #443 stojí v **pravém sloupci pod `Co teď`** blok `Dění` (`DashboardActivity`) — pět nejnovějších řádků, `celé dění →` v hlavičce a patka `Zobrazit celé dění +N →`; řádek je **týž `ActivityRowView`** jako v sekci, jen v úzkém tvaru (`ActivityRowPlace.dashboard`) |
| `DashboardTick` | Co je v pravém horním koutu hlavičky: `poslední tik 09:41 · za 43s znovu`, nebo `ptám se…` (#237). Výčet, ne `String` — odpočet musí zůstat samostatné view |
| `DashboardCountdown` | Samotný odpočet — `za 43s znovu`, **bez mezery mezi číslem a jednotkou** (#260). Formát je náš (systémový mezeru má a nejde vyndat), takt dává `TimelineView`, takže se přepočítává jen tenhle `Text`. Text i rozvrh jsou statické funkce, aby se daly otestovat |
| `SpendSparkline` | Sloupcový graf útraty za posledních sedm dní; dnešek zvýrazněný, prázdný den zůstává v řadě (#181) |
| `ProportionalColumns` | `Layout` pro sloupce v poměru z návrhu (`1.45fr 1fr`) — `HStack` umí jen rovným dílem (#181) |
| `StatusBarView` | Stavový řádek na spodku **okna**: vlevo hlášky a stav pracovní kopie, vpravo puntíky služeb |
| `WorkingCopyStatusView` | `Pracovní kopie připravená · HEAD 4f2ac91` ve stavovém řádku (#218) — přestěhováno z hlavičky PR, protože je to **stav prostředí**, ne údaj o PR. Selhaný checkout se sem nekreslí |
| `ServiceHealthDot` | Puntík jedné služby; po hoveru důvod a čas poslední kontroly |
| `NotificationStatusView` | Kdy se naposledy něco ohlásilo (#138) — zvonek s časem, `zatím nic`, nebo `vypnuto` |
| `DailySpendView` | Co dneska stálo review (#148) — cena za dnešek, u neúplného součtu s `≥` |
| `QueueSummaryView` | Souhrn fronty (#155) — kolik PR čeká, kolik má blokující nález a kolik rozdělané review. Počet rozdělaných je od #309 **mint**, ne akcent: je to číslo, na které se neklikne, a ve stejném pruhu sedí akcentové `Připravit` |
| `RunUsageText` | Cena, trvání a počet kol jako text — jedno místo pro osu i stavový řádek |
| `AppNoticesView` | Hlášky ve stavovém řádku: rozbitá konfigurace, pozastavený automat, nečitelné soubory, zakázané notifikace |
| `WindowCentering`, `WindowReader`, `ScreenBounds` | Vystředění pomocného okna **v hlavním okně**, ne na obrazovce (#164) — z jednoho místa pro nastavení i novinky |
| `AuxiliaryWindowLevel`, `keptInFrontOfApp()` | Pomocné okno zůstává **před ostatními okny aplikace, a jedině před nimi** (#243) — `.floating` dokud je aplikace vpředu, jinak `.normal` |
| `DiffCopyActions`, `copyMenu(_:selectText:)` | Kopírování kódu z diffu (#157) — co nabídne kontextové menu řádku a hunku |
| `DiffTextView` | `NSTextView`, který kreslí blok řádků: text, obarvení, pozadí, pruh rozsahu, čísla a znaky změny (#157). Drží **šířku kontejneru i měření výšky** (`height(forWidth:)`, `height(ofRows:)`), aby se šířka pro měření nemohla rozejít s tou pro kreslení (#236). Text skládá `compose(…)` — **čistá funkce nad řádky** (#275), aby šla změřit bez sazby |
| `DiffCodeBlockView`, `DiffBlockRowView` | Blok v pohledu pod sebou a k němu pilulka na komentář a tažení rozsahu |
| `DiffPairBlockView`, `DiffPairBlockContainer`, `DiffPairBlockRowView` | Totéž vedle sebe: dva zarovnané sloupce v clip view |
| `DiffBlockStyle`, `DiffBlockDrawing` | Dva klíče bloku. `DiffBlockStyle` (jazyk + barevný režim, a z něj paleta) rozhoduje spolu s řádky o tom, jestli se text **znovu sází** (#157; režim v něm je schválně kvůli #278, barvy jsou v tom textu zapečené). `DiffBlockDrawing` (blok + styl + **šířka**) rozhoduje o tom, jestli má `updateNSView` vůbec co dělat (#393) — viz *Stráž v `updateNSView`* |
| `DiffGutterGeometry`, `DiffBlockPlacement` | Aritmetika gutteru (#252) — kde leží plochy na tažení a pilulka, a poloha bloku v prostoru obsahu **mimo observable stav**. Čistý typ, aby se dal změřit i otestovat bez okna |
| `CodeText`, `CodeTextSheet`, `CodeSheetText`, `SelectableCodeView` | Hunk jako jeden text mimo diff (#157) — vybrat jde i přes bubliny — a od #417 týmž sheetem i **celý log jobu**: druh nese `CodeText.Kind`, velikost `Policy.codeSheetSizing`, věty hlavičky a patičky `CodeSheetText`. Viz *Sheet s kódem a s logem* |
| `PullRequestListView` | Seznam, prázdný stav, úvodní loading, tlačítko obnovit (⌘R). Od #331 kreslí **obě sekce se seznamem** (`PullRequestListScope`: `queue` / `mine`) — jeden řádek, jeden filtr, jedno řazení; liší se jen množina a věty nad prázdnem. Od #332 stojí **obě** na zúžených getterech (`visibleQueuePullRequests` / `visibleOwnPullRequests`); `PullRequestListScope` zůstává vyjmenovaný typ, ne `PullRequestOwnership`, protože nese i to, mezi kolika prázdny se rozhoduje a jak se mluví o schovaných řádcích |
| `PullRequestFilterButton` | Filtr seznamu v toolbaru (#117) — ikona se stavem a počtem schovaných, popover s odškrtávátky a **počtem PR u každé položky** (#199). Od #371 je nad nabídkou os odškrtávátko `Jen s blokujícím nálezem`: tu osu zapíná karta `Blokuje` na dashboardu, takže musí být **vidět a vypnutelná tam, kde se filtr nastavuje** — jinak by nabídka nad zapnutým filtrem ukazovala samá neodškrtnutá repa vedle ikony, která hlásí dvanáct schovaných PR. Kreslí se **i nad prázdnou nabídkou**, protože právě tam umí být zapnutá jako jediná |
| `PullRequestTabBar` | Záložky PR (`Přehled` / `Změněné soubory` / `Commity` / `Konverzace` / `Kontroly` ‖ `Nálezy` / `Průběh`) — podtržené, s odznakem **u každé** (#218; typy od #242), děličem před výstupem reviewerů a vpravo `+X −Y` se čtverečky poměru. **Kreslí `PullRequestTab.allCases` a nedá se to zvenku nastavit** (#306): do #306 byl seznam parametrem, protože `Kontroly` u PR bez CI odpadly — a pruh se tím při každém otevření PR přeskládal z pěti na šest. Zmizení parametru je ta podstatná část opravy; dokud existoval, dal se počet záložek znovu udělat funkcí dat. Od #316 má **tři podoby** (`ViewThatFits`, `Layout`): s popisky a `+X −Y`, s popisky bez ní a od #318 **ikony s odznaky a popiskem jen u aktivní** — díky té třetí se pruh nezalomí ani v nejužším povoleném okně. Viz *Pruh záložek — tři podoby podle šířky* |
| `StaleNoticeView` | Okrová věta „tohle je poslední známý stav“ nad seznamem, který se nepovedlo načíst **znovu** — jedno místo pro `Kontroly` (#215) i `Commity` (#316). Sedí **nad `ScrollView`em**, aby neodscrollovala pryč od obsahu, o kterém mluví |
| `CommitListView` | Seznam commitů v tabu `Commity` (#316): pruh s počtem a hlavou, řádek na commit (obrázek autora, první řádka zprávy, jméno, relativní čas, sha) a pilulky `sloučení` a `hlava`. `content` je `internal` kvůli měření přesahu — `NSScrollView` by přesah ukrojil |
| `CommitDiffView` | Diff jednoho commitu (#317) — hlavička a pod ní `DiffView`. **Nedostane `AppStore` ani identifikátor PR**, takže nemá čím vyrobit bublinu nálezu ani rozdělaný komentář; `reading(_:)` je `internal` kvůli testu, který tvrdí právě to, co `DiffView` **nedostane** |
| `CommitHeaderView` | Hlavička rozkliknutého commitu (`.chead`, #317): cesta zpět s pozicí, zpráva i její tělo, kapsle se sha (kliknutím se kopíruje), odkaz na GitHub, autor, čas, počet souborů a `+X −Y`, a tichá věta „Jen ke čtení…“ s odkazem do `Změněných souborů`. Řádek meta se v úzkém okně zalomí přes `ViewThatFits` — `.chead .meta` má v CSS `flex-wrap`, který SwiftUI nemá |
| `OverviewView` | Tab `Přehled`, odshora **co se změnilo od minule → fakta → popis PR** (#280; kontroly mají od #215 vlastní tab). Obsah je v `content` **mimo `ScrollView`** a `internal` schválně — přes `body` se šířka změřit nedá, viz #291. Kapsle stavu v hlavičce karty je od #348 `designPill` (mono 10,5), ne vlastní sazba |
| `SinceLastVisitView` | Pruh „co se změnilo od minule“ nahoře v `Přehledu` (#173, sazba #226 a #284) — odrážky po částech a pod nimi odznak `nálezy zastaraly` s tlačítky `Pustit review znovu` a `Ukázat, co přibylo` |
| `SinceLastVisitLine`, `SinceLastVisitLines` | Odrážka po typovaných částech a jejich skládání (#284). Mimo view a testovatelné, jako `TimelineEventRow` |
| `IncrementalDiffBar` | Lišta nad rozsahovým diffem (#284) — rozsah dvěma sha a cesta zpátky na celý diff. Podobu vybírá **spočítaná** šířka, ne `ViewThatFits` |
| `TextWidth` | Šířka popisku ve skutečném písmu (#284) — z ní se rozhoduje, jestli se řada vejde. Řez si bere z `MiniButtonStyle.labelFont`, u kapsle z `DesignPill` (#348), aby se měření a kresba nemohly rozejít. **Šířka jednoho popisku, ne metrika písma** — ta má vlastní měřidlo (`FontMetric`), protože se dá zapamatovat na proces; klíčem je tady text, takže by z cache byla přihrádka na každý popisek |
| `FontMetric` | **Jediné místo, kde se čte metrika písma** (#407): šířka znaku, výška řádku a obalový rámec. Jedno měření na proces (`shared`, mez 64 hodnot, klíč `(jméno, velikost, druh)`), tři cesty (`measured` → `fresh` → `derived`) **opakované až čtyřikrát s milisekundovou odmlkou**, a **nula se nepamatuje** — vada je přechodná a vadný je *objekt* písma. Náhradní měření **nesmí sázet text**: sazba tím písmem položí proces uvnitř CoreTextu. `tally` (počty měření, opakování a zamítnutá hodnota) čte sonda a zprávy u tvrzení. Viz *Metrika písma na jednom místě* |
| `DesignPill` | Kapsle stavu z návrhu (`.pill`) — **jedno místo pro její sazbu** (#348): mono 10,5 / 600, odsazení 7 a 2, `.capsule`. Volá se `designPill(tint:background:)` a od #404 si ji bere **třináct souborů** (17 volání); řez je `DesignPill.font` (AppKit) a **kreslí se i měří tímtéž** (`Font(_:)`, `TextWidth.pill(_:)`). `lineLimit` v ní **není** (rozhoduje o něm volající). Bere `Color`, ne `ShapeStyle` — kdo dědil `.tint`, musí barvu pojmenovat. Viz *Kapsle stavu na jednom místě* |
| `ConversationView` | Tab `Konverzace` (#183): lišta s filtrem, časová osa a **composer komentáře pod PR** na spodní hraně (#216) |
| `ConversationNodeView` | Jeden uzel osy — puntík 24 bodů, svislá linka **jako pozadí** (#375, ne pružná výška v řádku) a obsah vpravo; slévá za sebou jdoucí commity |
| `ConversationEntryView` | Položka osy: karta cizího review nebo komentáře, řádek události, vlákno bez kotvy |
| `ConversationComposerView`, `ConversationComposer` | Psaní komentáře pod PR (#216) a akce k němu |
| `TimelineEventRow` | Událost převedená na řádek — symbol, věta **s tučnými jmény**, barva uzlu (`tint: Color?`), sha po jednom (#171, sazba #216). Mimo view a testovatelné, jako `FindingRow` |
| `AvatarView`, `AvatarLoader` | Obrázek uživatele u události a jeho cache nad `HTTPGetting` (#171) |
| `PullRequestRow` | Repo + číslo + `draft` chip, titulek, autor a relativní čas, odznak stavu, ikona rozdělaného review — a u **vlastního PR** `Prompt →` (#331, `showsPromptAction`) a od #334 pilulka `N k předání` **místo odznaku stavu** (obě čísla mluví o týchž nálezech, takže by se vedle sebe pralo „3 nálezy“ s „6 k předání“; když nezbývá nic, odznak zůstává). Od #333 nese tlačítko akci (`openPrompt`) a **není zakázané**: otevře PR a v něm panel `Zadání`. **Bez akce se nekreslí** — `showsPromptAction` se ptá i na uzávěr, takže řádek bez storu (náhled, test) tlačítko nemá; nakreslit ho naprázdno je zrovna ta lež, kvůli které se do #333 kreslilo ztlumené |
| `PollStatusBanner` | Pruh nad seznamem — **jen když data nejsou čerstvá** |
| `PullRequestDetailView` | Pravý panel: hlavička ve třech řádcích (titulek s číslem, souřadnice PR, pruh běhu), pod ní záložky, diff a nálezy. **Bez pravého sloupce** (#218) — zbylo v něm jediné akcentové místo, `Spustit review` |
| `PullRequestHeaderView` | Souřadnice PR: kapsle stavu (plná, s puntíkem), od #334 za ní pilulka `moje PR` (mint, jen na vlastním), autor, větev → base, repo, souhrn checků a odkaz na GitHub. `StaleHeadView` vedle něj mluví jen tehdy, když se hlava rozešla se sha nálezů |
| `ReviewRunbarView` | Pruh běhu (#218): chipy reviewerů, za nimi dráha průběhu a popisek `test-coverage · 2 z 3 hotovo · 1:12`. Bez běhu zbude jen řada chipů |
| `DiffView` | Diff v plné šířce: lišta, strom vlevo a soubory s ukotvenou hlavičkou, kterou jde sbalit |
| `DiffToolbar` | Lišta nad diffem (#219): pohled, procházení nálezů, varování a `Rozbalit vše` s nabídkou. **Bez přepínačů sloupců** — ty se skládají u sebe |
| `DiffLayoutPicker` | Přepínač pohledu — segment **s popisky** podle návrhu (`.segbtn`), ne `Picker(.segmented)` |
| `DiffFileHeaderView`, `FilePathText` | Hlavička souboru (`.fhead`): celá cesta se **složkou tlumeně a jménem tučně**, odznak změny, kapsle s počtem nálezů, `+X −Y` |
| `DiffRowView` | Jeden řádek diffu — hlavička hunku, blok kódu, dvojice, rozbalovací řádek nebo poznámka. **Kód kreslí vždycky blok** (#446): `.pair` sem nedojde a `.line` jen jako poznámka `git`u ve splitu |
| `DiffLineView` | Jeden řádek přes celou šířku — dvě čísla, znak změny, obsah. V diffu jen ta poznámka `git`u, jinak **úryvek u vlákna** (`ThreadSnippetView`). Drží konstanty a barvy, které si berou bloky |
| `RangeDragActions`, `DiffRowFrames` | Tažení rozsahu komentáře (#110) — akce a rámečky řádků **mimo observable stav**; od #274 nese hlášení i klíč diffu, takže v krabici není víc než jeden |
| `DiffExpanderView` | Rozbalovací řádek: šipky vlevo v místě čísel a počet skrytých řádků |
| `FindingBubbleView` | Nálezy k jednomu řádku; u nálezu mimo diff nabídne jeho řádek dotáhnout, odmítnutý sbalí na jeden řádek s odznakem důvodu a `Vrátit`. Od #185 má **značku** (pruh s odznaky a náhledem) a rozbalený obsah pod ní — blokující je rozbalený rovnou. Od #283 jsou akce **řada malých tlačítek vlevo pod textem** |
| `MiniButtonStyle` | Malé tlačítko z návrhu (`.mini`, `.mini.pri`) — plné akcentové a obtažené. Rozměry v `Metrics`, aby se daly změřit testem; text plného je `Palette.surface` (`--panel`), ne bílá |
| `AccentLinkButtonStyle` | Textová akce v barvě akcentu (`.go` z návrhu) — **místo systémového `.link`** (#298). Barva z `Palette.accent`, ztlumení při zmáčknutí jako u `.mini`, kurzor `pointerStyle(.link)`. Font si drží volající. Tři výskyty ve dvou souborech: `Převzít` a `Vrátit` v tabulce nálezů, `Připravit` ve stavovém řádku — `grep -rn "buttonStyle(.link)" App/` po #298 vrací jen komentáře |
| `FindingBadgeAppearance` | Barva **konstatování** u nálezu (#309) — jedno místo pro `2×` a `✓ v mém review` v tabulce i v bublině. Vlastní jméno proto, aby šlo testem tvrdit, že se odznak nepřebarvil zpátky na akcent; uvnitř `body` se to tvrdit nedá |
| `FindingActions` | Co se dá dělat s nálezem — odmítnout a vrátit; jedno místo pro bublinu i tabulku |
| `FindingDisclosureActions` | Rozbalení bubliny nálezu (#185) — stav ze store a jeho překliknutí. **Nepatří do `FindingActions`**, kterou bere i tabulka: ta rozbalení řídí sama |
| `ThreadBubbleView` | Vlákno konverzace — u kódu i na ose (`Placement`); karta z pruhů, vyřešené sbalené s odznakem, moje komentáře odlišené, pole na odpověď a `Vyřešit` (#73, sazba #216) |
| `ThreadSnippetView` | Úryvek kódu k vláknu na ose (#158) — pás uvnitř bubliny, řádky kreslí `DiffLineView`, nad nimi značka zkrácení |
| `ThreadActions` | Co se dá dělat s vláknem — rozbalení, odpověď, vyřešení a důvod, proč odesílat nejde |
| `MarkdownText` | Vykreslený Markdown z GitHubu — viz `App/Markdown/` |
| `DraftCommentBubbleView` | Můj rozdělaný komentář u řádku: editor, odznak původu, vyjmutí. Ve split pohledu visí jen v půlce, které se týká |
| `DraftTextField` | **Podoba** textového pole — rámeček, nápověda na prvním znaku, strop výšky. Drží jen vzhled; kam se text ukládá, rozhoduje ten, kdo ho použije (#452) |
| `DraftTextEditor` | Textové pole draftu — odložený zápis (400 ms) a doručení při zmizení. Pro composer, ze kterého se odesílá jedním klikem, se **nehodí**: mezi „co je vidět“ a „co store ví“ je celá ta odmlka (#452) |
| `DraftPanel` | Tab `Moje review`: banner zastarání, verdikt **předvyplněný návrhem z nálezů** (obtažený, s popiskem), tělo, seznam komentářů, `Odeslat review…` (u zastaralého `Zkontrolovat a odeslat…`). Obsah scrolluje, jen když se nevejde |
| `ReviewSubmissionSheet` | Potvrzení odeslání: **kontrola kotev u zastaralého draftu** (#69), pak úplný výpis payloadu, průběh, typované chyby |
| `DraftTransferView` | První stránka toho potvrzení: stav každé kotvy (sedí / posunulo se / nevím / ztraceno) a volba, co s ní |
| `VerdictAppearance` | Ikona a barva verdiktu — jedno místo pro panel i pro potvrzení. `Komentář` bere od #309 `Palette.accent` (verdikt je volba, tedy akce), schválení a vyžádání změn od #432 `Palette.ok` a `Palette.crit` — do té doby to byla systémová škála a stálo tady, že převod celé škály je jiná otázka |
| `DraftActions`, `FileDraftActions` | Co se dá s draftem dělat; druhé svázané s jedním souborem diffu |
| `DiffLineView` | Řádek souboru: dvě čísla (v buňce dvojice jedno, podle `side`), znak změny, obsah obarvený podle jazyka, tlačítko na komentář (na hover) |
| `ReviewPanel` | Panel **napravo od diffu** (#182, do #242 `FindingsPanel`): segmenty `Nálezy`/`Moje review` — a na vlastním PR `Nálezy`/`Zadání` (#333, rozhoduje `Policy.reviewPanelTabs`) —, karty nálezů, prokliky do diffu a složení na proužek s počtem nálezů a značkou rozdělaného review. `Průběh` a zahození nálezů se u #242 odstěhovaly do záložek PR. **Kreslí se jen ve třech tabech** (#294, `PullRequestTab.showsReviewPanel`) — sám o tom nerozhoduje, podmínku má detail |
| `AgentPromptPanel` | Tab `Zadání` na vlastním PR (#333): sedm zaškrtávacích voleb s počty (od #377 **vybraných z celku**, `1 z 3` — plný počet by nad textem se dvěma položkami lhal; nápověda u nich pošle do sheetu, kde se položky přepínají), náhled začátku textu, `Sestavit prompt →` na hraně panelu — a věta o tom, že konverzace **není** načtená (načítání se rozlišuje od selhání). Verdikt ani `Odeslat` tam **nejsou**, ne zašedlé. Draft z dřívějška se v něm kreslí jako blok s výpisem a `Zahodit review`, protože zmizet nesmí. Od #334 má **tři podoby podle stavu předání**: razítko `✓ N položek · dnes 14:20 · proti 9c1de02` (volby se schovají, zbyde `Sestavit znovu`), razítko s větou „od předání přibyla 1 položka“ nad běžnými volbami, a po pushi varování se dvěma řádky (`Nové v diskuzi`, `Nálezy proti staré hlavě`) a dvěma cestami dál. Texty jsou `nonisolated static`, takže se testují bez kreslení |
| `OwnPullRequestStatusView` | `Vlastní PR — review se odsud neodesílá` ve stavovém řádku (#334, návrh sekce 22). Tichá mint věta bez kapsle, jen nad otevřeným **vlastním** PR — odpovídá na otázku „proč tady nejsou tlačítka, na která jsem zvyklý“ |
| `AgentPromptSheet` | Sheet s celým textem (#333): hlavička s hlavou PR a velikostí, odznaky „co je v textu“ i „vynecháno“ (sází je `FlowRow`), text tak, jak se zkopíruje, a v patičce `Zkopírovat` / `Uložit do souboru…` s větou `nikam se to neodesílá`. **Bez druhého potvrzení** — brána proti odeslání se týká GitHubu, tady se neodesílá nic. **Nejširší sheet v okně** (840 / 1080 b proti 560 / 720 u ostatních), protože obsah je markdown s fenced diffy. Od #377 v něm bydlí i **výběr položek** (`Co zahrnout`): hlavička říká `vybráno 6 z 11`, odznaky „vynecháno“ nesou **důvod** (`1 vlastní vynechán`), pod nadpisem `Text` stojí věta, že je náhled funkcí výběru, a `Zkopírovat` je nad prázdným výběrem zakázané **s důvodem**. Výběr ani rozbalení nepřežijí zavření — `@State` sheetu, viz *Výběr položek do zadání* |
| `AgentPromptPickList` | Seznam položek se zaškrtávátkem u každé (#377): grupy po druzích s počtem `2 z 3`, u položky autor a `soubor:řádek`, u vypnuté **důvod**, a rozklik s hlavičkou `druh · autor · čas · velikost`. Dlouhý text se **roluje** (strop 168 b z návrhu, výška se měří `onGeometryChange` — `ScrollView` je ve svém směru hltavý, takže bez měření by jednořádkový komentář zabral tolik jako čtyřkilobajtové release notes). Zaškrtávátko je **vlastní tlačítko**, řádek rozbaluje; jedno kliknutí nesmí znamenat obojí |
| `FlowRow` | `Layout`, který řadu **zalomí** místo zkracování popisků (`flex-wrap: wrap` z návrhu, #333). Polohy se počítají, nevyjednávají (#220) |
| `AgentPromptActions` | Co se dá se zadáním dělat (přepnout volbu, sestavit) — jeden parametr místo tří closures, jako `DraftActions`. **Nic, co by odesílalo** |
| `DismissedRowStyle` | Buňka tabulky: ztlumení odmítnutého řádku a kontextové menu `Označit jako…` / `Vrátit` |
| `FindingRow` | Nález převedený na řádek tabulky — texty (včetně nápovědy k místu), identita, blokující příznak, odmítnutí |
| `FindingHighlight` | Místo, na které se právě skočilo; bublina na něm chvíli svítí |
| `ReviewProgressView`, `ReviewerLaneView` | Tab `Průběh` (#242, nahradily `ReviewTimelineView`): **dráha na revieweera** s fázemi vedle sebe, věta o tom, co se právě děje, u spadlé session důvod, `stderr` a `Pustit znovu` / `Zkopírovat příkaz`; pod fázemi **živý výpis kroků** v okně se stropem (#325, `StepFeedView` + `TimelineEntryRow`). Dráha po skillu **mimo nastavenou sadu** nese v hlavičce `mimo sadu`; prázdný stav mluví o **nastavení**, protože se do něj dá dojít jedině s prázdnou sadou skillů |
| `ReviewerLaneText` | České věty dráhy — stav, co se právě děje, čím to skončilo. Rozlišuje **tři** doběhlé stavy: nahlásilo nálezy / nahlásilo nulu / nenahlásilo nic — a `nespuštěno` od `ve frontě` |
| `FindingsTabView`, `FindingsEmptyView` | Tab `Nálezy` (#242): souhrn počtů, `Zahodit nálezy`, tabulka — a věta, **proč** je prázdno (`Policy.findingsEmptyReason`), společná s panelem |
| `FindingsTableView`, `FindingTableRowView`, `FindingTableRow` | Tabulka nálezů přes celou šířku: řazení kliknutím na hlavičku, řádek na **místo** (shoda dvou reviewerů je odznak `2×`), rozbalení kreslí tutéž `FindingBubbleView` jako diff. Akce (`Převzít`, `Vrátit`) jsou **barevný text z palety** (`AccentLinkButtonStyle`, #298), ne plocha jako v bublině a ne systémová modrá; krytí odmítnutého řádku drží `dismissedOpacity` (`.frow.done` z návrhu), ze kterého měří i sonda kontrastu |
| `ReviewerChipsView` | Chipy reviewerů: **puntík, zkrácené jméno a počet** (#218); stav a filtr naráz, v kontextovém menu opakování jednoho revieweera (#149) |
| `FileTreeView` | Strom souborů v levém sloupci u diffu; odsazení a sbalování si řídí sám |
| `ReviewStateBadge` | Odznak stavu review; texty podle specifikace. Sazba je od #404 `designPill` (mono 10,5) a k ní `lineLimit(1)` **i** `fixedSize()` — v řádku fronty se odznak pere o místo s titulkem PR a mono je tam o 10 až 48 bodů širší |
| `hiddenShortcuts(_:)`, `KeyEquivalent.backTab` | Klávesové zkratky bez viditelného tlačítka (#151) — jedno místo pro detail PR, nastavení, okno novinek, paletu i přepínání záložek (#245). `backTab` je tam proto, že `⌃⇧⇥` doručí `U+0019`, tedy jinou klávesu než `⇥` |
| `WindowShortcutButtons`, `View.windowShortcut(_:)` | Překlad katalogu zkratek (#441) do SwiftUI — **jediné místo v `App/`, kde se `keyboardShortcut` píše nad kombinací**. Kombinací může být víc, každá dostane vlastní tlačítko (česká klávesnice); viditelné tlačítko bere jen tu primární |
| `CommandPaletteView`, `CommandPaletteRowView` | Command palette ⌘K (#184): pole, skupiny výsledků, zvýrazněná shoda v titulku, pruh s klávesami. Karta 560 bodů jako **překryv okna**, ne sheet |
| `PullRequestStateAppearance` | Ikona a barva stavu **pull requestu** (ne review) — jedno místo pro řádek seznamu i pro paletu |
| `AppDelegate` | Ukončení aplikace: dokud běží review, ptá se |

### Hlavička PR (#218)

Hlavička rostla po kusech — stav u #174, chipy u #21, počet u #183 — a každý kus se posuzoval
sám za sebe, ne celý pruh dohromady. U #218 se přesázela podle návrhu (sekce 02) najednou.
Co se u ní nemá rozbít:

- **Tři řádky a žádný pravý sloupec.** Titulek s číslem, souřadnice PR, pruh běhu. Do #218 stály
  vpravo pod sebou `Spustit review` (fialové), `kopie připravená` (zelená) a `Návrh: request
  changes` (oranžová) — tři hlasité barvy, které z pravé strany dělaly semafor a přebíjely
  titulek. Zbylo **jediné akcentové místo**, a tím je `Spustit review`.
- **Stav pracovní kopie se přestěhoval do stavového řádku**, ne zmizel: je to stav prostředí,
  takže patří vedle dostupnosti `gh` a `claude` (`WorkingCopyStatusView`). **Selhaný checkout
  ale zůstává bannerem v hlavičce** — u něj se musí vypsat celý výstup `gitu` a z něj se teprve
  pozná, co dělat dál; do pruhu se to nevejde a porucha není běžný stav.
- **Návrh verdiktu v hlavičce není vůbec** a `VerdictView` se smazal. Od #114 se jím
  předvyplňuje verdikt v panelu `Moje review`, takže v hlavičce to byla druhá kopie téhož —
  a ta hlasitější z nich. Sám návrh (`Policy.suggestedVerdict`) se nemění.
- **Číslo PR je u titulku**, ne uvnitř `owner/repo#4`. V té větě ho nikdo nehledá; řada
  souřadnic proto nese jen `owner/repo`.
- **Kapsle stavu je plná** (`.state-chip`): puntík, slovo, barva z palety návrhu a text v barvě
  plochy (`Palette.surface`), ne bílý. Systémové `.green`/`.red` jsou na plnou kapsli příliš
  světlé a bílá by na nich v tmavém režimu oslňovala.
- **Chip revieweera je puntík a počet** (`.rchip`). Slovo `nález` a ikona bubliny padly; barvu
  stavu nese puntík a celou větu nápověda i `accessibilityValue` — **to je jediné místo, kde se
  `čisté` pozná od `selhalo`**, takže se nesmí vypustit. Počet je jen tam, kde běh doběhl
  a dopočítal se; `0` nad nedoběhlým během by tvrdilo „nic nenašel“. Zkracování jména podle
  kolizí (#182) platí i tady — v užší kapsli tím spíš.
- **Odznak počtu je u všech záložek**, každý ale počítá něco jiného: `Přehled` novinky od
  minule, `Změněné soubory` počet souborů, `Konverzace` položky k přečtení. **Odchylka od
  návrhu**: v mockupu je u `Přehledu` čtyřka, která odpovídá počtu dlaždic s fakty — to je ale
  konstanta, tedy odznak, který nikdy nic neřekne.
- **Pruh běhu si o šířku říká v pořadí chipy → popisek → dráha.** `GeometryReader` uvnitř dráhy
  je jinak nenasytný a jména reviewerů se zalomí uvnitř kapslí; dráha se smí stáhnout, ale ne
  pod 44 bodů. Během přípravy pracovní kopie se dráha **nekreslí vůbec** — podíl se nemá z čeho
  spočítat a prázdná dráha vypadá jako zaseknutý běh. Že se něco děje, drží tikající hodiny.
- **Hodiny berou začátek z `RunningReview.startedAt`, ne z časové osy.** Osa se při opakování
  jednoho revieweera (#149) míchá s tou z minulého běhu a reviewer, který mezitím doběhl,
  z „běžících“ vypadne — nejstarší událost běžících os by se tím posouvala dopředu a čas by šel
  zpátky.
- **`Zkontrolovat nálezy` (#150) stojí vlevo od `Spustit review` a je tlumené.** Akcentová barva
  v hlavičce zbyla jedné věci, takže dvě fialová tlačítka vedle sebe by z ní udělala dvě.
  Nenabízí se, dokud není co kontrolovat (`AppStore.recheckMaterial(for:)`), a za běhu je z něj
  `Zrušit kontrolu` s hodinami — vlastní pruh průběhu kontrola nemá, protože nepouští žádného
  revieweera a pruh mluví o chipech.
- **Výsledek kontroly visí v `StaleHeadView`**, tedy u řádku, který říká, že nálezy patří
  staršímu commitu — je to o týchž nálezech a hlavička je vidět ve **všech** tabech PR. Souhrn
  vyjmenuje i nálezy **bez odpovědi**; bez nich by „3 vyřešené“ nad pěti nálezy vypadalo, že
  o zbytku kontrola něco řekla. Zastaralá kontrola **nemlčí**: odznaky u nálezů zmizí, ale věta
  řekne, proti čemu běžela a že se dá pustit znovu.
- **Odznak u nálezu nálezy nemaže ani nepřeskupuje.** Kreslí se v bublině u kódu (ve značce
  i u položek), na kartě v panelu a v rozbaleném řádku tabulky — a všude nese v sobě, **odkud
  to je** (`kontrola: vyřešeno`). Samotné „vyřešeno“ vedle nálezu by se čtlo jako fakt, a schovat
  nález smí jedině odmítnutí (#113). **Ve sbaleném řádku tabulky odznak není**: sloupce mají
  spočítanou šířku (#220) a odznak by si vzal místo shrnutí. **Na kartě je pod textem, ne
  v hlavičce** — změřeno offscreen renderem, že se ve 300 bodech vedle `blokuje`, kategorie
  a revieweera zkrátí na `kontrola…` a `blokuje` se zalomí na dva řádky.
- **Vyřešený nález má přeškrtnuté shrnutí a `vyřešeno` v odznaku závažnosti.** Rozhoduje o tom
  `Policy.severityBadge(…)`, protože ten odznak kreslí **čtyři** místa: hlavička karty v panelu,
  sloupec `závažnost` v tabulce, značka bubliny a hlavička nálezu uvnitř bubliny. Platí u toho
  čtyři věci a každá z nich má důvod:
  - **`blokuje` zůstává vedle `vyřešeno`**, nikdy se nenahrazuje: první je fakt o tom, co drží
    merge, druhé tvrzení modelu — a vyřešený nález se dál počítá i dál blokuje. Ve sloupci tabulky
    jsou obě kapsle **pod sebou** (92 bodů na šířku nestačí, na výšku ano), jinde vedle sebe.
  - **Přeškrtává se jen text nálezu** (shrnutí a jeho náhled ve sbalené značce), ne celý řádek:
    ztlumení celé plochy má `DismissedRowStyle`, tedy odmítnutí, za kterým stojí člověk. Odmítnutý
    nález se proto **nepřeškrtává** a odznak `vyřešeno` nedostane — o něm je rozhodnuto.
  - **`pořád platí` a `nejasné` závažnost nemění.** Dobrá zpráva je jen jedna a jen ta smí
    z odznaku ubrat pozornost.
  - **V odznaku závažnosti stojí krátké `vyřešeno`, ne `kontrola: vyřešeno`** (~110 bodů, tedy
    `kontrola…` ve sloupci i v hlavičce karty). Odkud to je, nese zelená a nápověda; plný odznak
    zůstává na kartě pod textem a v obsahu bubliny. **Ze sbalené značky bubliny plný odznak ubyl**
    — stál by pár bodů od `vyřešeno`, takže se kreslí až v rozbaleném obsahu.

  **Paleta ⌘K (#184) v tom není** a je to záměr: řádek nálezu v ní není odznak závažnosti, ale
  jednořádkový cíl skoku, kde je blokující příznak jen barevný puntík. Odmítnuté nálezy do ní
  nejdou vůbec (nechci na ně skákat), kdežto vyřešené ano — „vyřešeno“ je tvrzení modelu, takže
  nález zůstává místem, kam se dá jít podívat.

**Zavření aplikace se ptá, dokud běží review** (`AppDelegate`, #94), a **session u toho zabije**
(#264). Do #264 dělalo jen to první: dialog tvrdil, že se session zabije, ale nikdo ji nezabíjel —
osamocený `claude` se přerodil na `launchd` a běžel dál, počítal tokeny za review, které už nemá
komu doručit, a držel pracovní strom, který se proto nesměl uklidit. Změřeno: dvě takové session
běžely na stroji čtyři dny.

- **`NSAlert` a `runModal()`, ne SwiftUI.** `applicationShouldTerminate` musí odpovědět
  **synchronně**; asynchronní cesta by aplikaci zavřela dřív, než se kdokoli zeptá.
- **Odloží se jen zabíjení, ne dotaz** (#264). Dotaz zůstává synchronní, ale po kliknutí na
  `Ukončit` se vrací `.terminateLater` a odpověď (`reply(toApplicationShouldTerminate:)`) přijde
  teprve po `AppStore.stopReviewsBeforeTermination()`. `terminateNow` hned po zrušení běhů
  nestačí: signál k procesu se nese přes `WorkCoordinator` a několik hopů mezi aktory, takže by
  aplikace zmizela dřív, než odejde.
- **Zabíjí se tou samou cestou jako u zrušení** — `task.cancel()`, ze kterého se přes
  `continuation.onTermination` dojde na `SIGKILL`. Druhý `kill` v delegátovi by byl druhá pravda
  o tom, jak se běh zastavuje, a `SIGTERM` volba proti té, která u zrušení už padla.
- **Ze zaseknuté session nesmí vzniknout nezavíratelná aplikace.** Čekání má strop
  (`terminationChecks × terminationStep`, tedy dvě sekundy) a odpověď systému odejde i tehdy,
  když po něm něco zůstalo. V praxi se to vrací po prvním kole.
- **Druhý pokus o ukončení během těch dvou sekund jen zopakuje odpověď.** Jinak by nad
  ukončením, které už běží, otevřel druhý dialog a systému by se odpovědělo dvakrát — a
  `reply(toApplicationShouldTerminate:)` je na jedno odložené ukončení.
- **Výchozí tlačítko je `Zpět`**, ne `Ukončit`. Ztracený nález je dražší než jedno kliknutí
  navíc, takže omylem odklepnutý `Enter` nemá nic zahodit.
- **Text říká, co se stane — a nic víc.** „Běží review“ samo o sobě nedává důvod kliknout na
  Zpět; od #264 v něm ale nestojí, že se nálezy **ztratí**, protože se z transcriptu dotáhnou
  (viz níž a #97). Slibuje proto jen to, co reviewer nahlásil do zabití.
- **Počítá se z `reviewTasks`** (a od #150 i z `recheckTasks`), ze stejného zdroje jako
  `isReviewing`. Vlastní počitadlo je druhé místo, které se s prvním může rozejít — a rozejít se
  v tomhle znamená zavřít bez zeptání. Kontrola nálezů se počítá proto, že dialog se ptá kvůli
  zabíjení session, a kontrola je session jako každá jiná.
- **Dotaz i odpověď systému jsou v delegátovi vlastnosti, ne přímá volání AppKitu** (#264).
  Jinak by se to nedalo testovat: `runModal()` v testu čeká na kliknutí, které nikdo neudělá,
  a `reply(toApplicationShouldTerminate:)` mimo odložené ukončení by ukončil hosta testů.
- **`bin/run.sh` proto nepoužívá `killall`.** SIGTERM `applicationShouldTerminate`
  **neprochází**, takže rebuild při vývoji zabíjel review i s nálezy — dvakrát za jedno
  dopoledne. Skript posílá Apple event `quit`, tedy tou samou cestou jako ⌘Q, čeká na
  odpověď a když aplikace zůstane běžet, novou verzi nespustí.
- **Nezachytí to všechno**, a je to tak zamýšlené: pád aplikace ani zabití zvenčí takhle
  odchytit nejde. Dotažení nálezů z transcriptu (#97) je pro ně ta drahá varianta — a od #264
  slouží **oběma** cestám, protože zavření aplikace je pro běh totéž jako pád.
- **Session, která zabitou aplikaci přežila, se uklidí až při dalším startu** (#351). Nálezy dotahuje
  transcript (#97), ale sám `claude -p` běží dál pod `launchd` a počítá tokeny — tomu se
  z běžícího procesu, který zmizel, zabránit nedá (prevence na macOS neexistuje, změřeno).
  `AppDelegate.applicationDidFinishLaunching` proto sirotky dohledá a zabije; jak, je v sekci
  `Environment`.

**Zavírání se přitom nesmí lišit od pádu v tom, co po sobě nechá** (#264). Zabité běhy se
schválně chovají jako přerušené, ne jako zrušené:

- **Značky rozdělaných běhů (#97) se při zavírání nemažou.** Úklid, který zrušení dělá, by
  z „přerušeno se dvěma nálezy“ udělal „neběželo“ — tedy zahodil nálezy, které leží
  v transcriptu. Zrušení člověkem je jiná otázka a maže dál: ty nálezy si nikdo nevyžádal.
  Drží to `AppStore.isTerminating`, které je právě proto stav, ne lokální proměnná.
- **Během zavírání se nic nespouští.** Tik pollingu dorazí i uprostřed a jeho automatický běh
  by aplikaci přežil, protože zabíjení už proběhlo. Brána je proto v `startReview` i ve
  `startAutomaticReviews`.
- **Nic se neukládá jako doběhlé.** To platí i u zrušení (`Task.isCancelled` před zápisem) —
  zabitý běh není doběhlý běh a `čisté` by nad ním lhalo.

### Obnovování je vidět na tlačítku (#442)

Do #442 se o probíhajícím dotazu dozvěděl **jenom dashboard** — `DashboardTick.polling` napsal
v pravém horním koutu `ptám se…` místo odpočtu. Ten kout je vidět jedině na domácí záložce
v sekci `Přehled`, takže kdo byl v záložce pull requestu, neměl to kde poznat; klik na `⟳`,
po kterém se vteřinu neděje nic, se přitom čte jako klik, který nezabral.

Od #442 se místo šipky točí **`SpinningRing`** — týž prstýnek, jaký na záložce znamená běžící
review. Čtyři věci, které z toho plynou a nejsou zjevné:

- **Není to nový prstýnek, je to tentýž kus kódu.** Nekonečná animace ve SwiftUI je zakázaná
  třída (#350: `repeatForever` si vyžádá průchod při každém obtažení obrazovky a přes
  `NSHostingView.layout()` rozvrhne celé okno — 99 % CPU hlavního vlákna na nečinném okně).
  Druhá kresba téhož by tu past otevřela znovu **a** znamenala by, že se „pracuje se“ čte
  v jednom okně dvěma tvary. Výchozí `SpinningRing` je navíc `.spin` z návrhu 1 : 1 (11 bodů,
  2 body obtažení), takže si tlačítko o vlastní rozměr říkat nemusí.
- **Rozhoduje `AppStore.isRefreshing`, ne to, kdo dotaz spustil.** Prstýnek se točí i při
  automatickém tiku; kdyby se točil jen po kliknutí, znamenal by „tohle jsi spustil ty“, což by
  většinu času neplatilo.
- **Podmínka je na jednom místě** (`Policy.refreshControl`) a čte ji **trojice**: tlačítko
  (podoba, `disabled`, popisek pro čtečku), `AppStore.refresh()` (pojistka proti druhému dotazu)
  a od #441 **zkratka `⌘R`**. Samotné zašedlé tlačítko by nestačilo — tutéž akci nabízí paleta ⌘K
  i `Zkusit znovu` v prázdném stavu seznamu, takže guard patří tam, kam všechny tři cesty ústí.
  `PollingService.refresh()` guard **nemá**: smyčka si ho volá sama a je sekvenční, kdežto
  „ruční obnovení“ je `AppStore.refresh()`.
- **Rozměr se nesmí hnout.** Prstýnek má jiný tvar i jinou vnitřní velikost než šipka, takže bez
  pevného rámce by hlavička poskočila při každém tiku. Číslo je jedno (`HeaderButtonMetrics`,
  27 × 25 z `.tbtn`) a hlídá ho tvrzení nad `fittingSize` obou stavů.

**Zašedlé tlačítko tady nemá vedle sebe větu s důvodem**, na rozdíl od vypnuté brány odesílání
(#392). Je to vědomý rozdíl: důvod je vidět **v tom samém tlačítku** (točí se, tedy se ptáme)
a trvá vteřiny, ne dokud si někdo nezmění nastavení.

**Nápověda nese zkratku** (`Obnovit seznam (⌘R)`, jak ji kreslí návrh) — od #441, kdy `⌘R` v okně
doopravdy je. Skládá ji `Policy.shortcutHelp`, takže závorka není opsaná vedle klávesy. Za běhu
dotazu je nápověda jiná (`Ptám se GitHubu…`) a zkratku **nemá**: je zakázaná, a tvrdit u zakázané
klávesy, že něco udělá, je totéž jako ji nakreslit tam, kde není.

### Katalog klávesových zkratek (#441)

Do #441 se kombinace psaly tam, kde bydlelo tlačítko — `ContentView`, `PullRequestDetailView`,
`DiffView`, `DashboardView` —, a nakreslená popiska stála **vedle** klávesy (`shortcut: "⌘⇧R"`
v témže volání jako `key: KeyEquivalent("r")`). Obojí se dá rozejít potichu a obojí se pozná
jedině používáním. Od #441 je to katalog v `Policy` (`Policy.windowShortcut(_:)`) a k němu jeden
překlad do SwiftUI (`WindowShortcutButtons`, `View.windowShortcut(_:)`).

Co katalog drží a co se u něj nemá rozbít:

- **Kolize se nedá poznat za běhu.** Dvě tlačítka s jednou kombinací nejsou chyba ani pád —
  vyhraje to zaregistrované později (#151 u `⌥⇧↓`, #184 u `⌘↵`) a druhá zkratka „nefunguje“.
  Katalog na jednom místě proto **je** ta kontrola: `WindowShortcutsTests` ho projdou
  vyčerpávajícím výčtem a tvrdí, že se žádná kombinace neopakuje. Ověřeno vloženou regresí.
- **Popiska je odvozená, ne opsaná.** `Combination.display` skládá glyfy z modifikátorů a klávesy,
  takže paleta ⌘K, chip v panelu zadání, řádky dashboardu i nápovědy tlačítek kreslí vždycky to,
  co je pod klávesou. Pořadí glyfů je `⌘⌃⌥⇧` — **z návrhu** (`⌘⇧P`, `⌘⌥S` v `docs/navrh.html`),
  ne z menu macOS, které píše `⌃⌥⇧⌘`.
- **Nápovědu skládá `Policy.shortcutHelp`** (`Obnovit seznam (⌘R)`), a je to jedno místo z téhož
  důvodu: do #441 leželo v repu devět takových závorek jako literál.
- **Jedna akce, víc kombinací.** `keyboardShortcut` páruje na **znak**, takže `⌃1` na české mapě
  nezabere vůbec — pod tou klávesou je `+`. Sekce railu proto mají `primary` (`⌃1`) a `alternates`
  (`⌃+`), a `WindowShortcutButtons` z toho udělá **dvě tlačítka s jednou akcí**. To je v pořádku;
  co se rozbíjí, jsou dvě tlačítka s jednou **kombinací**. Alternativa musí mít stejné modifikátory
  jako primární — je to tentýž hmat na jiné mapě, ne druhá zkratka.
- **`View.windowShortcut(_:)` bere jen primární kombinaci**, protože na jedno tlačítko se
  `keyboardShortcut` pověsí jednou. Akce, které visí na **viditelném** tlačítku (`⌘1` strom
  souborů, `⌘⇧R` a `⌘⇧D` na dashboardu), proto alternativu mít nesmí — je na to tvrzení.
- **`.cancelAction` je role, ne klávesa s maskou.** Modifikátory u ní `Combination.keyboardShortcut`
  zahodí, takže je katalog nesmí psát; hlídá to test. Zapisuje se takhle schválně (#317) — `⎋`
  v tomhle okně berou i sheety a paleta, a míchat `.escape` s `.cancelAction` znamená hádat, který
  z nich AppKit spáruje dřív.
- **Katalog je jen o hlavním okně.** Sheety, okno nastavení, okno novinek, uvítací brána a překryv
  palety v něm nejsou: berou si klávesu samy a s oknem se nepotkají. Tam, kde by se překryly
  (`⌘⏎` a `⎋` nad otevřenou paletou), je zkratka okna **zakázaná** — zakázané tlačítko klávesu
  nebere a propadne dál.
- **Stráž nad zdrojáky je dvojí, a je to schválně.** Jedna hlídá, kde se zkratka **registruje**
  (`keyboardShortcut(`), druhá, kde se **kreslí** (`⌘` nebo `⌥` v řetězcovém literálu). Ta druhá
  přibyla proto, že první nechytá kapsli: nakreslené `⌘2` žádnou klávesu neregistruje, jen o ní
  tvrdí — a přesně tohle u #441 zůstalo v hlavičce panelu a našel to až Copilot. Obojí má
  **jmenovitý** výčet výjimek (tatáž konstrukce jako `SingleWayOutTests`) a obojí je ověřené
  vloženou regresí. `⌃` a `⇧` se v té druhé stráži nehledají: `⌃` je v `AgentPromptPickList`
  šipka rozbalení a `⇧` stojí v próze o `⇧ kliku` v diffu.

Co v okně je (dvacet akcí):

| Zkratka | Akce | Kde je zakázaná |
|---|---|---|
| `⌘K` | paleta ⌘K (#184) | — |
| `⌃⇥` / `⌃⇧⇥` | sousední záložka (#245) | — |
| `⌃W` | zavřít záložku pull requestu | na domácí záložce (`Policy.closableTab`) |
| `⌘R` | obnovit seznam | dokud běží dotaz (`Policy.refreshControl`, #442) |
| `⌃1`–`⌃5` (+ `⌃+ ě š č ř`) | sekce railu | — |
| `⌥↓` / `⌥↑` | další / předchozí nález (#151) | — |
| `⌘1` | strom souborů u diffu | — |
| `⌘2` | panel s mým review (#182) | v tabech bez panelu (#294) |
| `⎋` | zpět na seznam commitů (#317) | mimo tab `Commity`, nad paletou a nad potvrzením |
| `⌘⏎` / `⌃⏎` | **potvrzení** odeslání review (#151) | `Policy.canOpenSubmission`, otevřený sheet, otevřená paleta |
| `⌘⇧P` | zadání pro agenta (#333) | cizí PR, prázdné zadání, otevřený sheet, otevřená paleta |
| `⌘.` | zastavit běžící review | když na tom PR nic neběží |
| `⌘⇧R` / `⌘⇧D` | dashboard: pustit vše, dopsat rozdělané (#181) | — |

**`⌃W`, ne `⌘W`**, a sekce railu na `Control`u: `⌘W` patří systému (zavře okno) a `⌘1`/`⌘2` jsou
uvnitř PR strom a panel. Zavírá se **aktivní záložka**, ne vybraný řádek v seznamu — `selection`
je „na co se v seznamu kouká“, kdežto zavřít se má to, co je v okně.

**`⌃⏎` je druhá klávesa k `⌘⏎`, ne náhrada, a tvrdou podmínku č. 1 nemění**: otevírá **potvrzení**,
neodesílá. Přibylo proto, že `⌘⏎` si v tomhle okně bere i paleta (otevřít výsledek na GitHubu),
takže nad otevřenou paletou je zkratka detailu zakázaná; `⌃⏎` se s ní nepotká. Zakázané jsou přitom
**obě naráz a za týchž podmínek** — jsou to dvě tlačítka s jednou akcí, ne dvě akce. V samotném
potvrzovacím sheetu zkratka na odeslání **není a nebude**.

**`⌘.` nezastavuje kontrolu nálezů** (#150), i když běží ve stejném okně. Je to druhá session
s vlastním tlačítkem a jedna klávesa, která by podle stavu zastavila jednou tohle a jindy tamto,
by nikdy neřekla, co udělá.

**Co se v harnessu ověřit nedá:** že ty klávesy fungují. Testovací host nedostane aktivaci
(změřeno u #392, potvrzeno u #434), takže nemá key okno a stisk nemá kam sednout. Testuje se proto
katalog a jeho zakázané stavy; **na české i anglické klávesnici to zkouší člověk.**

Dvě věci, které se tím ověřují a z kódu je vidět nejsou, protože o nich rozhoduje systém:

- **`⌃1`–`⌃5` může sebrat Mission Control.** `Přepnout na plochu N` je systémová zkratka na
  `⌃`+číslici a událost se k aplikaci nedostane vůbec — nezáleží na tom, co má okno
  zaregistrované. Kdo má víc ploch a tu zkratku zapnutou, musí ji vypnout v Nastavení systému,
  nebo použít českou variantu (`⌃+`, `⌃ě`, …), na kterou Mission Control nesahá.
- **`⌘.` je v Cocoa druhé jméno pro `cancelOperation:`**, tedy pro `⎋`. Klávesové ekvivalenty
  tlačítek se vyhodnocují **dřív** než key bindings, takže nad běžícím review vyhraje naše
  zastavení; ale tam, kde je naše tlačítko **zakázané**, událost propadne dál a `⌘.` se zachová
  jako Escape (zavře sheet, vrátí ze commitu). Je to standardní chování systému, ne chyba —
  a je to zapsané proto, že to z katalogu ani z testu vidět není.

### Odznak v railu (#366)

Odznak s počtem u sekce railu měl do #366 **dvě odchylky od návrhu naráz** a obě z kódu vypadaly
jako záměr: barvu (`.tint`, tedy fialový akcent) a polohu (`offset(x: 6, y: -2)`, tedy 6 bodů za
rámem ikony). Návrh (`.rail .ri .badge`) má červený odznak zarovnaný **s pravou hranou rámu**.

- **`--crit`, ne akcent.** Akcent v tomhle okně znamená „tady jsi“ — `.ri.on` je z něj celý —,
  takže odznak v téže barvě neříkal nic navíc; červená je „je co dělat“, což počet ve frontě je.
- **Rozměr se změřil na vyrenderované sekci 02, ne odhadl z CSS.** `min-width: 14px; height: 14px`
  je v návrhu **obsah**: dokument `box-sizing` nikde nepřepisuje (viz komentář u `.lchip`), takže
  se odsazení 3 a obtah 2 přičítají a odznak vychází **24 × 18** na jednu i dvě cifry (na tři
  26,7). V bitmapě je z toho červená plocha **20 × 14** — obtah je barvou railu (`--panel-2`),
  takže se do ní neplete.
- **Poloměr má dvě hodnoty.** CSS `border-radius: 7px` platí na vnější box a vnitřní se o šířku
  obtahu zmenšuje, takže se kreslí `rect(cornerRadius: 5)` uvnitř `rect(cornerRadius: 7)`.
  `.capsule` by na 18 bodech výšky dala 9, tedy jiný tvar než návrh.
- **Výška je `minHeight`, ne `frame(height:)`.** Řádek mono 9 bold je 11 bodů, takže se čtrnáctka
  chová jako podlaha; nasazený rámec by číslo uřízl, kdyby se písmo systému změnilo (#325).
- **Text v barvě plochy okna** (`--panel`), ne bíle. Kontrast **5,36** ve světlém a **5,50**
  v tmavém režimu; bílá na světlé červené dá 3,35 a dosavadní bílá na akcentu měla v tmavém režimu
  **3,27**, tedy pod hranicí pro malé písmo.
- **Nula se nekreslí a `nil` se od nuly liší** — to platí od #331 dál a `RailBadgeTests` to tvrdí
  i s protějškem (s počtem 1 se odznak nakreslit **musí**), aby sada nevycházela zeleně nad
  odznakem, který zmizel celý.

Co se **nezměnilo**: rám ikony zůstává 34 × 30 (návrh má 32 × 30), protože to je metrika položky
railu z #278, ne odznaku.

### Kapsle stavu na jednom místě (#348)

`.pill` je v návrhu kapsle pro **stavy a počty**: `nálezy zastaraly`, `sloučení`, `hlava`, `+248`,
`otevřený`. Sází se mono, a to není ozdoba — je to odlišení od `.lchip`, tedy od labelu
z repozitáře, který je slovo a sází se v UI fontu.

Metrika (`mono 10,5 / 600`, odsazení 7 a 2, kapsle) žila v **sedmi kopiích**: `CommitListView`,
`SinceLastVisitView`, `DiffFileHeaderView`, `AgentPromptSheet`, `AgentPromptPanel`,
`PullRequestRow` — a `OverviewView`, kde se rozešla (`11` bez mono). Šest shodných kopií je přesně
ten stav, ve kterém se sedmá může rozejít potichu, takže metrika dostala jméno
(`designPill(tint:background:)`) a hlídá to test nad zdrojáky
(`DesignPillTests.keepsTheTypesettingInOnePlace`).

Tři věci, které z toho plynou:

- **Šířku bere měření odtud taky** (`TextWidth.pill(_:)`), stejně jako `TextWidth.miniButton`
  bere řez z `MiniButtonStyle`. Vlastní `systemFont` v měření znamená počítat jinou šířku, než
  jaká se nakreslí.

  A **kreslí se tím samým `NSFont`em, který se měří** (`Font(DesignPill.font)`) — nález Copilota
  na #406. První podoba měla AppKit řez na měření a SwiftUI `.system(size:weight:design:)` na
  kresbu; metrikou to bylo totéž (`.AppleSystemUIFontMonospaced-Semibold`, `otevřený` 51,926
  v obou), ale dvě specifikace jednoho řezu jsou přesně ta třída chyby, kvůli které `TextWidth`
  vznikl (#284).
- **`lineLimit` do kapsle nepatří.** V hlavičce karty se zalomit nesmí (`otevře/ný` nejsou dva
  odznaky pod sebou), v podtitulku commitu to omezení nikdy nemělo — je to rozhodnutí volajícího
  o jeho místě v okně.
- **`monospacedDigit()` odešlo z `DiffFileHeaderView`** jako nadbytečné: mono řez má cifry stejně
  široké sám a nastavené písmo by ho stejně přebilo.

Cena mono je **šířka**: 4 až 9,4 bodu na čtyřech stavech PR (`zavřený` +6,75, `otevřený` +8,37,
`rozpracovaný` +9,41, `mergnutý` +4,02). Výška naopak **klesla o bod** (řádek 12 proti 13
u systémových 11), takže hlavička karty nemůže povyrůst. V nejužším tabu (320 bodů) se kapsle
ořezává na `ote…` — je to **stav z doby před #348** (tam bylo `otev…`), tedy důsledek #291, ne
téhle změny; rozhoduje o něm `ViewThatFits`, který v té šířce zahazuje relativní čas.

**Zbytek třídy dotáhlo #404**: pět dalších kapslí (`ReviewStateBadge`, pilulky nálezů ve
`FindingCardView`, `FindingTableRowView` a `FindingBubbleView`, odznaky v `ThreadBubbleView`
a `ConversationEntryView`) mělo v návrhu `.pill` a v aplikaci nemono sazbu — tři jiné metriky
(`.caption` 6/2, `.caption2` 5/1, `10,5 bez mono` 6/1) na pěti obrazovkách. Od #404 berou všechny
`designPill`, takže volá **třináct souborů** (17 míst) a metrika zůstává na jednom.
`PullRequestHeaderView` do té třídy **nepatří** — `.state-chip` je nemono i v návrhu.

Co u #404 vyšlo z měření a není zjevné:

- **Odznak fronty potřebuje `lineLimit(1)` i `fixedSize()`, a každý na něco jiného.** `lineLimit(1)`
  brání zalomení, ale místo něj **zkracuje**, takže sám by z odznaku udělal `3 nález…`; neustoupit
  vůbec umí až `fixedSize`. Změřeno vloženou regresí: bez `fixedSize` se dva nejdelší stavy
  v řádku o 320 bodech srazily o **20 a 33 bodů**. Cena mono je tady 10 až 48 bodů
  (`timeout · 2 · 1 blokuje` 116 → 164), tedy víc než u kapsle v hlavičce karty — proto se to
  měří zvlášť (`PillTypesettingTests`).
- **Kapsle v tabulce nálezů `fixedSize` naopak nedostala**: sedí ve sloupci se **spočítanou**
  šířkou (`Policy.findingTableLayout`), takže o jejím místě rozhoduje `Policy`, ne vyjednávání
  v řádku. Nejdelší popisek v tom sloupci je `irelevantní` (86 bodů mono ve sloupci 92).
- **Výška kapsle o bod vyrostla, ne klesla** — na rozdíl od #348. Tam se srovnávalo se
  systémovými 11 (řádek 13, odsazení 2 → 17), tady s `.caption2` (řádek 13, odsazení **1** → 15),
  takže mono 10,5 s odsazením 2 dá 16. V pruhu se značkou u bubliny nálezu je kapsle to nejvyšší,
  takže výška pruhu je z ní; hlídá se **stropem** (kapsle smí bublinu zvednout nejvýš o ten jeden
  bod, kterým se liší od prózy vedle sebe).
- **Barvy #404 nemění**, a je to vědomé: škálu odznaku fronty drží `ReviewStateAppearance`, jehož
  vlastní zdůvodnění říkalo, že převod zbytku škály na tokeny je *jiná otázka, která se zodpovídá
  měřením*. Měření z #404 je v `PillTypesettingTests` a **našlo mezeru**: čtyři kapsle na
  systémové zelené a červené měly ve světlém režimu kontrast pod 3 (`vyřešeno` **1,63**,
  `schválil` **1,70**, `vyžádal změny` 2,52, `3 nálezy · 1 blokuje` 2,70).
  **Vyřídilo to #432** převodem celé škály na tokeny (1,63 → 3,05 až 2,70 → 3,77); prahy v téže
  sadě od té doby hlídají výsledek, ne jen to, že se nic nezhorší.
- **Dvě věci se pojmenovaly tokenem, aniž by se změnil vzhled**, protože `designPill` bere `Color`,
  ne `ShapeStyle`: odznak `já` dostal barvu textu `Palette.ink` (do #404 dědil `primary`, a
  `labelColor` je poloprůhledná — tatáž past jako u textu diffu, #393) a jeho wash se změnil
  z `.tint.opacity(0.18)` na `Palette.accent.opacity(0.18)`. V okně je to **tatáž barva** (`.tint`
  se na kořeni nasazuje jako `Palette.accent`), ale mimo okno padalo dědění na systémovou modrou —
  což je zrovna ta záměna, kterou řešila #309 u odznaku `2×`. Kontrast `já` je **12,27 / 8,40**.
- **`Bot` v konverzaci mono nedostal**, i když ho tabulka v #404 vyjmenovala: návrh ho kreslí jako
  `.tl-line .botchip` (`font-size: 10px; padding: 0 5px`, **žádná `font-family`**), tedy schválně
  nemono — je to vlastnost účtu vedle avataru, ne stav ani počet. Hlídá to vlastní tvrzení
  (`DesignPillTests.leavesTheBotChipInTheUIFont`), protože „sjednotit kapsle“ je přesně to zadání,
  při kterém se příště převede omylem.
- **`FindingCardView.blockingWarning` zůstává `Label` s ikonou** (`⚠ blokuje`, `.caption2`
  semibold), takže v kartě stojí nemono varování vedle mono kapsle `vyřešeno`. Kapsle to není —
  nemá plochu —, takže do zadání #404 nespadá; převést by znamenalo zahodit tu ikonu, a to je
  změna obrazovky, ne sazby.

### Metrika písma na jednom místě (#407)

`FontMetric` je jediné místo v `App/`, kde se čte metrika písma — `maximumAdvancement`,
`defaultLineHeight` a `boundingRectForFont`. Do #407 to bylo **pět míst**: `LogTailTextView`
(výška řádku okýnka), `SelectableCodeView` a `DiffToolbar` (šířka znaku, obojí `static let`)
a v `DiffTextView` dvakrát — z toho jednou jako **dvojice** (`defaultLineHeight` z layout manageru
view, a když ho view ještě nemělo, výška obalového rámce), tedy dvě různá čísla na jednu výšku řádku
podle toho, jak daleko bylo view v sestavování.

**Proč to má jedno místo.** V testovacím hostu pod zátěží se metrika písma umí **rozejít mezi dvěma
čteními v jednom procesu** a jedno z nich vyjde nulové: `CommitPanelRoomTests` z toho měly
`both → 0` proti `treeOnly → 35` (víc místa a méně znaků) a `LogTailHeightTests` výšku o tři řádky
vedle. Léčby byly tři a každá v jiné sadě (#367, #348, #327) — čtvrtá by o tom musela vědět taky.
Čím se to prokázalo a co ta nula doopravdy je, je v
[`docs/testovani.md`](testovani.md), sekce *Metrika písma je tentýž kořen v jiné podobě (#407)*.

Co na tom typu není zjevné:

- **Měří se pod zámkem, ne vedle něj.** Dvě vlákna, která minou zapamatovanou hodnotu naráz, by
  změřila dvakrát — a „jedno měření na proces“ je zrovna to, co se má držet. Zámek je držený
  mikrosekundy a nic uvnitř se na `FontMetric` nevolá zpátky.
- **Nezdařené měření se nepamatuje.** Zapamatovaná nula je horší než vrácená, protože
  `SelectableCodeView.characterWidth` i `DiffToolbar.characterWidth` jsou `static let`, tedy jedno
  měření **navždycky**.
- **Pořadí cest je součást opravy.** `fresh` (písmo postavené znovu z deskriptoru) je druhá, protože
  naměřená příčina je vadný **objekt** písma; `derived` je poslední, protože její čísla jsou jen meze
  (u šířky znaku horní, u obalového rámce dolní).
- **Celý řetěz se opakuje, a to je ta věc, kterou tam dalo měření.** V osmém z deseti plných běhů
  vyšly u mono 13 **všechny tři cesty nulové** a **totéž písmo dalo o zlomek sekundy později 8,036**.
  Vada tedy netrvá: v tom okamžiku nepomůže jiná cesta, pomůže zkusit to **později**. Čtyři pokusy
  s **milisekundovou** odmlkou — bez ní je to tentýž stav přečtený čtyřikrát, protože celý řetěz je
  pár mikrosekund. Cena je nejvýš 3 ms jednou za písmo a proces, a jedině když měření selhává; odmlka
  je **pod zámkem** schválně, aby druhé vlákno nezměřilo mezitím podruhé.
- **Náhradní měření nesmí sázet text.** První podoba měla u šířky znaku vysázet `0` — a sazba tím
  písmem, u kterého selhalo přímé čtení, **položila celý běh** výjimkou z CoreTextu. Poslední cesta
  se proto ptá jedině na čísla, která má `NSFont` sám u sebe.
- **Klíč je `(jméno písma, velikost, druh metriky)`**, ne objekt písma: jméno nese i řez, takže se dvě
  různá písma nemají jak potkat. Písma lišící se **jen maticí** by se slila — aplikace žádné takové
  nestaví.
- **Mez 64 hodnot, při překročení se zahodí celá sada** — tatáž úvaha jako u `SyntaxRunCache`
  (#224): cache bez vyjmenované meze je únik paměti s odkladem. Aplikace měří jednotky písem.
- **Rozhodnutí „jde to použít?“ je v `Policy.usableFontMetric(_:)`**, čistá funkce. Hlídá `isFinite`,
  ne jen kladnost: `NaN` je hodnota, kterou skutečné `NSFont` vydá (změřeno na písmu s nekonečnou
  maticí), a `Int(NaN)` shodí proces, kdežto nulu zavře `guard` v `Policy.charactersPerSide`.

### Command palette ⌘K (#184)

Jediná obrazovka aplikace, která nemá předobraz v ničem starším: jedno pole nad **nálezy,
soubory otevřeného PR, cizími PR, vlastními PR (#336) a akcemi**. Rozdělená je na tři kusy
a hranice mezi nimi je to podstatné:

| Kde | Co tam patří |
|---|---|
| `CommandPalette` (`App/Models/`) | Tvary: `Item`, `Group`, `Target`, `Action`, `Mark`, `Hit`, `Section`, `Jump`, `Effect`. Žádné rozhodování, žádné barvy |
| `Policy.paletteResults`, `Policy.paletteActions` (`App/Policy/CommandPaletteSearch.swift`) | **Rozhodování**: co na dotaz sedne, jak se to váží, kolik se toho ukáže, a které akce mají teď co dělat |
| `AppStore+Palette` | Katalog z paměti store a vykonání cíle |
| `CommandPaletteView`, `CommandPaletteRowView` | Sazba a klávesy. Ve view **není žádné `if` nad výsledky** |

Co se u ní nemá rozbít:

- **Pořadí skupin je pevné a je to tvrzení, ne kreslení.** Nálezy první, protože je to jediná
  věc, kterou tahle aplikace má a prohlížeč ne. Nese ho **pořadí případů** v `CommandPalette.Group`,
  takže se nedá přehodit ve view.
- **Strop je na skupinu** (`Policy.paletteGroupLimit`, šest). Celkový strop by znamenal, že dvacet
  nálezů vytlačí soubory, PR i akce — tedy zrovna to, kvůli čemu je paleta jedno pole na všechno.
- **Vlastní PR jsou vlastní skupina, ne odznak u řádku** (#336), a stojí to na tom stropu o řádek
  výš: ve **společné** skupině by při dvaceti cizích PR to moje nemuselo vyjít vůbec, protože se
  řadí podle váhy shody a šestý řádek je konec. Dvě skupiny mají každá svých šest a při prázdném
  dotazu je vidět začátek obou. Odznak `moje` u řádku ten problém neřeší, jen ho schová.

  Tři věci k tomu, které se dají pokazit potichu:

  - **Rozřazuje `Policy.ownership`**, tedy tatáž funkce jako rail a dashboard (#330) — podle
    **autora**, ne podle zdroje. Dokud není znám `viewer`, je všechno cizí, takže se paleta při
    startu nepřehodí do druhé skupiny a zpátky.
  - **Cíl zůstává `Target.pullRequest`.** Skupina je zařazení; druhý případ v `Target` by byl
    druhá cesta k témuž a rozešel by se.
  - **Nadpis první skupiny je `Pull requesty k review`**, ne `Pull requesty`: se dvěma skupinami
    musí říct, čeho se týká, jinak vypadá `Moje PR` jako řádky, které do té první nepatří omylem.
- **Prázdný dotaz vrací všechno, ne nic.** Paleta se otevírá jako nabídka toho, co je po ruce;
  pořadí je pořadí katalogu (nálezy od nejvážnějšího přes `Policy.sorted`, soubory v pořadí diffu,
  PR od naposledy změněného, akce v pevném pořadí).
- **Řazení nese pořadí katalogu v klíči výslovně.** `sorted` v Swiftu nemá stabilitu v kontraktu,
  takže bez druhého kritéria by řádky se stejnou váhou mezi stisky klávesy poskakovaly.
- **Hledá se bez ohledu na velikost písmen a diakritiku** (`range(of:options:)`); aplikace je
  česká, takže `nalez` musí najít `nález`. Víc slov je **a zároveň** — jinak by se nedalo napsat
  `vault secret`.
- **Hledá se i podle autora a repozitáře, a obojí je v podtitulku.** Autor u pull requestů
  (`connection#21663 · sykora-ji`), repo u nálezů i u pull requestů. **Ne** v klíčových slovech,
  kde autor do připomínky k #184 byl: klíčové slovo se nikde nekreslí, takže dotaz na jméno
  vytáhl PR, ve kterém to jméno nebylo vidět — a výsledek, u kterého není poznat proč, vypadá jako
  chyba hledání. **Soubory podle repa nejdou**: jsou všechny z jednoho otevřeného PR, takže by se
  vytáhly všechny naráz a v podtitulku mají diffstat. Autor u nálezu taky ne — jméno, které k němu
  patří, je jméno **revieweera**.
- **Zvýrazňuje se v tom textu, ve kterém se to potkalo.** `Hit` nese dva rozsahy
  (`titleHighlight`, `subtitleHighlight`), každý nad svým řetězcem; v jednom textu se zvýrazní
  **první** slovo dotazu, které v něm sedlo. Shoda v **klíčovém slově** se nezvýrazňuje, protože
  se klíčová slova nekreslí — a právě proto váží nejmíň a patří do nich jen nadmnožina něčeho
  viditelného (celá cesta vs. jméno souboru, `owner/repo` vs. `repo#85`) nebo synonymum titulku.
- **Váhy: titulek (0–2) > podtitulek (3) > klíčové slovo (4).** Shoda v titulku musí zůstat před
  shodou v autorovi nebo v repu, jinak dotaz na slovo z titulku vytáhne nahoru cizí PR od stejně
  pojmenovaného autora. Podtitulek má **jednu** váhu, ne tři jako titulek: je to výčet dvou
  souřadnic, takže „začátek“ v něm znamená repo a „vnitřek“ autora, a mezi těmi dvěma se nemá
  rozhodovat podle pozice v řetězci.
- **Podtitulek se o šířku hlásí první a nezkracuje se.** Změřeno: karta má 560 bodů, na oba texty
  z nich zbývá ~489 a nejdelší podtitulek ve skutečných datech
  (`prism-review-sandbox#4 · github-actions[bot]`) měří 254. Ustupuje tedy titulek — a to je
  správné pořadí, protože shoda v autorovi je na **konci** podtitulku, takže by ji zkrácení uřízlo
  jako první.
- **Katalog se skládá při každém stisku klávesy, ne jednou při otevření.** Snímek by za pár sekund
  ukazoval nálezy z review, které mezitím doběhlo. Změřeno (`CommandPaletteMeasurement`):
  200 řádků 1,5 ms, 2000 řádků 17,6 ms na stisk — reálný katalog (dvacet PR, desítky nálezů,
  padesát souborů) je řádově ten první případ.
- **Paleta se nikoho nedoptává.** Nálezy jsou z `reviewRecords`, soubory z **načteného** diffu
  otevřeného PR, PR z posledního tiku. Diff jiného PR by byl nový dotaz na GitHub — a ten zadání
  #184 zakazuje. Je na to test, který po vykonání každého druhu cíle porovnává počty volání
  gateway.
- **Čte se plný seznam `pullRequests`, ne `visiblePullRequests`.** Filtr je zúžení *seznamu*,
  kdežto paleta je způsob, jak něco najít; hledání, ze kterého vypadne schovaný PR, je
  k nepotřebě právě tehdy, když je filtr zapnutý. Nic se tím neriskuje — paleta jen čte, úklid
  cache na zúženém getteru nevisí (viz `AppStore`).
- **Nálezy jsou ze všech PR, a `id` řádku se skládá z indexu.** `Policy.key(of:)` se umí zopakovat
  (týž reviewer nahlásí totéž dvakrát) a dva řádky s jedním `id` by SwiftUI slil — zmizel by
  nález, který se zrovna hledá. Pořadí PR: otevřený první, pak seznam z pollingu; iterace přes
  `reviewRecords` (slovník) by pořadí měnila mezi stisky klávesy.
- **Odmítnuté nálezy se nenabízejí** — nálezu, kterému nevěřím, není kam skákat.
- **Nabízí se jen akce, které by něco udělaly.** Bez otevřeného PR tedy nic, co na PR visí
  (review, pohled na diff, panel); sekce railu, která je zrovna vidět v domácí záložce, taky ne.
  Tatáž zásada jako u bloku `Co teď` na dashboardu.
- **Kreslená zkratka musí být skutečná.** Od #441 se **nekreslí opsaná, ale odvozená** z katalogu
  (`Policy.windowShortcut(…).display`), takže se s klávesou nedá rozejít: řádky nesou `⌘2`,
  `⌃1`–`⌃5`, `⌘R` a nad běžícím review `⌘.`. Jediná výjimka je `⌘,` — to registruje scéna
  `Settings`, ne okno. Návrh má u „pustit review“ `⌘⇧R`, ale ta v aplikaci pouští review na
  **všechno, co neběželo** (dashboard) — nakreslit ji tady by byla lež o tom, co okno umí.
- **Kreslí se číslicová varianta sekce** (`⌃1`), ne česká (`⌃+`). V řádku je na kombinaci jedna
  kapsle a `⌃1 / ⌃+` by z ní udělalo dvě kvůli údaji, který se člověk naučí jednou.
- **Řádek vlastního PR se od cizího neliší ničím kromě skupiny** (#336) — dvě vědomé odchylky od
  sekce 09 návrhu, obě zapsané ve specifikaci: podtitulek je `PRism#324 · ondrajodas`, ne
  `· 6 k předání` (ten počet se dá napsat teprve s razítkem předání, #334 — tak jak to u řádku
  seznamu rozhodlo #331), a puntík zůstává v barvě **stavu PR** (`PullRequestStateAppearance`),
  ne v mintu. Mint by v paletě znamenal „moje“ podruhé — jednou už to říká nadpis skupiny — a přebil
  by jedinou věc, kterou ten puntík nese: u vlastního draftu (`author:@me is:open` je vrací) by
  zmizel rozdíl mezi rozdělaným a otevřeným PR, protože slovo `draft` má jen řádek seznamu.
- **Odsud nic neodchází** (tvrdá podmínka č. 1). Ve `CommandPalette.Action` není nic, co by sahalo
  na `ReviewPublishing`; jediná věc, kterou paleta pouští, je read-only reviewer.

Klávesy a stav:

- **`isPaletteOpen` je ve storu, ne v `@State` okna**, protože si o něj musí říct dvě různá místa:
  paleta a **detail PR**, který nad otevřenou paletou zakáže svoje `⌘⏎` (potvrzení odeslání). Dvě
  tlačítka se stejnou zkratkou v jednom okně znamenají, že vyhraje to zaregistrované později —
  a spletená zkratka by z palety otevřela potvrzení odeslání review.
- **Dotaz a kurzor jsou naopak `@State`** a mají zaniknout se zavřením: paleta je „začínám hledat“,
  ne „vracím se k rozdělané práci“, takže text z minula by po ⌘K vypadal jako výsledky k něčemu, na
  co se nikdo neptal. Není to úklid, který by někdo musel dělat — `CommandPaletteView` vzniká až
  s otevřenou paletou.
- **Fokus do pole se nastavuje až po jednom průchodu smyčky** — `task { await Task.yield(); … }`.
  Přiřazení ve stejném průchodu, ve kterém pole vzniká, SwiftUI **zahodí**, takže `onAppear`
  (a `task` bez yieldu) fokus nedá **nikdy**; `defaultFocus` taky ne, protože je na počáteční fokus
  scény a překryv v už otevřeném okně žádná nová scéna není. Všechny tři varianty jsou změřené na
  běžící aplikaci (`AXFocused` + znaky poslané hned po ⌘K) — s yieldem je fokus v poli ~40 ms po
  ⌘K, a rozhoduje **počet průchodů, ne čas**.
- **Zkratky jsou tlačítka v `hiddenShortcuts`, ne `onKeyPress`.** To se váže na fokus a v tomhle
  okně ho spolkne pole nebo seznam pod paletou (viz `HiddenShortcuts`). Plné `↵` bere `TextField`
  přes `onSubmit` — `keyboardShortcut(.defaultAction)` se s polem o tutéž klávesu přetahuje.
  **Fokus v poli tomu nevadí**: změřeno, že `esc` paletu zavře i s kurzorem v poli a `↑↓` chodí dál
  po řádcích, protože key equivalent tlačítka se vyhodnocuje dřív, než se klávesa dostane k editoru
  textu.
- **Skok do diffu jde přes `AppStore.paletteJump`.** Rozhodnutí „skoč sem“ padá nad celým oknem,
  ale odscrollovat umí jedině detail PR (kotvy řádků, `ScrollViewProxy`). Žádost proto nese
  vlastní `id` (`UUID`), aby se dala vyžádat **dvakrát** — `task(id:)` se na shodné hodnotě
  podruhé nespustí. Klíčem té úlohy je **žádost i to, jestli je diff načtený**: paleta umí skočit
  do PR, jehož záložka právě vznikla, takže diff v tu chvíli ještě není. Nevyzvednutá žádost se
  uklízí s PR mimo seznam, jako rozdělané tažení komentáře.
- **Nález bez místa v kódu otevře tab `Nálezy`**, ne diff. Skákat naslepo je horší než skočit tam,
  kde ten nález doopravdy je.
- **Nastavení otevírá okno, takže ho vykoná view.** `AppStore.reveal(_:)` vrátí
  `CommandPalette.Effect.openSettings` a `ContentView` zavolá `openSettings` z environmentu; store
  scénu otevřít neumí a nemá si to ani pamatovat.
- **Karta je překryv okna, ne sheet.** Sheet si bere šířku okna a přijíždí jako dialog; návrh má
  kartu 560 bodů, která visí nad obsahem a zbytek jen ztmaví. Ztmavení **bere kliknutí** (klik
  mimo zavře) — tím se liší od ztmavení pod oknem nastavení, které klik schválně propouští.
- **Výška seznamu se měří, šířka se předává** (#220). `ScrollView` je v ose scrollování
  nenasytný, takže bez `onGeometryChange` by byla karta vysoká i nad dvěma výsledky; šířka jde
  dolů přes `availableWidth(560)` a řádky ji nevyjednávají.

## Šířka v okně (`App/Views/AvailableWidth.swift`)

**Pružná šířka na každé úrovni zanoření je výkonnostní chyba, ne otázka vkusu** (#220). Každá
úroveň, která řekne `frame(maxWidth: .infinity)`, znovu vyjednává šířku se svými dětmi, a cena
layoutu proto roste **~5,5× na úroveň zanoření**. Změřeno offscreen renderem na stromu, který
kopíruje tvar uzlu osy konverzace:

| Hloubka zanoření | Jeden layout |
|---|---|
| 4 | 11 ms |
| 6 | 350 ms |
| 8 | 15 700 ms |

Okno se na PR s ~2000 změněnými řádky zaseklo na **20 minut na 100 % CPU**, a `sample` běžícího
procesu ukázal, že čas nejde do našich funkcí: v jednom zásobníku bylo 3562× `LayoutEngineBox.
sizeThatFits` a k tomu `StackLayout…sizeChildrenGenerallyWithConcreteMajorProposal`
a `NSAttributedString.MetricsCache.findMetrics`. Tuhly **oba taby**, protože nešlo o obsah, ale
o tvar stromu, který mají společný přes detail PR.

**Je to tatáž třída chyby jako pružná výška v líném seznamu** (viz `App/Diff/`, buňka dvojice):
tam byl vinen `maxHeight: .infinity` v `LazyVStack`u, který výšku nenavrhuje, a našel se taky
`sample`m. Pravidlo je proto jedno: **v zanořeném stromu se rozměr nenechává vyjednávat, když se
dá spočítat.**

**Pružná výška v líném seznamu ale není *tentýž* multiplikátor jako šířka** (#375) — a je to
změřené, ne odvozené. Tabulka výš („5,5× na úroveň“) je o **šířce**: tu si každá úroveň vyjednává
s dětmi, takže se pásma násobí. Výška se v řádku `LazyVStack`u navrhuje jako `nil`, takže
`frame(maxHeight: .infinity)` nad ní vrátí **ideální** rozměr dítěte — jeden průchod, žádné pásmo.
Kontrolní měření na ose konverzace (sonda `IdleDiffSpinProbe.scrollingConversation`, 150 kroků
po 40 pt): jedna pružná úroveň **1,28 s** CPU, **šest** pružných úrovní **1,08 s**, tedy o nic
dražší — a šířku má osa v tu chvíli konkrétní z `availableWidth`.

Z toho **neplyne, že je pružná výška nevinná**: u buňky dvojice (#98) položila aplikaci na 99 %
v `StackLayout.explicitAlignment` a `ViewResponder.hitTest`, tedy v **hit testu při pohybu myši**,
ne v pásmu šířek. Plyne z toho jen tohle: **cena pružné výšky se nedá odhadnout z tabulky pro
šířku** a hledá se `sample`m nad tou cestou, která se doopravdy jde. Proto se `maxHeight: .infinity`
nezakazuje plošně — zakazuje se **v řádku líného seznamu**, a ohraničené formy jsou vyjmenované
níž.

**Ohraničené formy `maxHeight: .infinity`, které jsou v pořádku** (sweep u #375 nad celým `App/`,
tehdy 25 výskytů; dneska 28 — čísla se s každou obrazovkou mění, rozhoduje ta tabulka, ne počet):

| Forma | Proč je ohraničená |
|---|---|
| `background`/`overlay` uvnitř řádku | Rozvrhuje se **až nad hotovou velikostí** rodiče, takže si o ni nevyjednává. Takhle žije pilulka v `DiffLineView` a od #375 i linka osy v `ConversationNodeView` |
| plocha tabu, panelu, sheetu, prázdného stavu | Není to řádek seznamu — je to jeden blok, který má vyplnit okno. `PullRequestDetailView`, `DraftPanel`, `EmptyStateView`, nastavení, novinky |
| **rámec roztahovatelného sheetu** | `RawSessionSheet`: pružnost je tady **podmínka roztahovatelnosti** — bez ní SwiftUI sheet resizable neudělá (změřeno, #327). Je to jeden blok na okno, ne položka seznamu |
| `SidebarRail`, `CommitDiffView` | Totéž: jeden prvek na okno, ne položka v `ForEach`i |

**V řádku líného seznamu po #375 nezůstal ani jeden.** Kontrola je grep na ten jeden soubor, který
se opravoval — **musí vyjít prázdný** (filtr zahazuje komentáře, které vysvětlují proč):

```bash
grep -rn 'maxHeight: .infinity' App/Views/ConversationNodeView.swift | grep -vE ':[0-9]+: *//'
```

Plošný grep prázdný vyjít **nemůže** a nemá se o to snažit — ty ohraničené výskyty jsou
v pořádku. Sweep se proto dělá tak, že se vypíšou všechny a u každého se řekne, do které řádky
tabulky výš patří:

```bash
grep -rn 'maxHeight: .infinity' App | grep -vE ':[0-9]+: *//'
```

### `fillingSlot()` — líný seznam rozměr nevyjednává vůbec (#361)

Devátý záchvat u #361 dal poprvé **celý zásobník hořícího kola**, a v něm tuhle řadu:

```
StackLayout.UnmanagedImplementation.prioritize(_:proposedSize:)
  _FlexFrameLayout.sizeThatFits(in:context:child:)
    ScrollViewLayoutComputer.Engine.sizeThatFits(_:)
      _PaddingLayout.sizeThatFits(in:context:child:)
        LazyVStackLayout.sizeThatFits(proposedSize:subviews:context:cache:)
          LazyStack<>.measureEstimates(updatingPosition:index:minor:subviews:cache:)
            _LazyLayout_Subviews.apply(from:style:to:) → ForEachList.applyNodes → ConversationRow.id
```

Přeloženo do kódu je to jedna cesta v `ConversationView`: `VStack` rozděluje výšku, takže se ptá
pružného rámce nad osou na velikost, ten se zeptá `ScrollView`u a ten `LazyVStack`u. **A neptá se
jednou** — stack zjišťuje pružnost dítěte tím, že se ho ptá s `nil`, `0` a `∞`. Naměřeno sondou
`LazyIdealSizeProbe` nad scénou tvaru osy konverzace (300 řádků, okno 520×380):

| Podoba místa | Dotazů na velikost celkem | Z toho `nil` (ideál) | Z toho `0`/`∞` (průzkum) | Se skutečnou velikostí |
|---|---|---|---|---|
| `frame(maxWidth: .infinity, maxHeight: .infinity)` | **29–33** | 2–4 | ~21 | 4 |
| `frame(idealWidth: 0, maxWidth: .infinity, idealHeight: 0, maxHeight: .infinity)` | 29 | **0** | ~21 | 4 |
| `fillingSlot()` (`GeometryReader` + `frame(width:height:)`) | **4** | **0** | **0** | 3 (+1 nulový) |

Přesný počet se mezi běhy o pár liší (kolik dotazů `nil` pošle okno), **druh dotazů ne** — a právě
na druhu ta věc stojí, takže se v testu tvrdí on, ne číslo.

**Podstatná není cena, ale kdo do čeho zapisuje.** Poslední jméno v té řadě je
`measureEstimates(**updatingPosition**:…)`: dotaz na velikost líného seznamu **mění jeho stav**.
Sahá na tutéž měnitelnou krabici (`_LazyLayoutViewCache.withMutableCacheState`, ve vzorku v obou
cestách) jako `placeSubviews`, a změněné fáze položek z ní jdou do grafu **zvenčí** — druhá
transakce ve stejném kole:

```
GraphHost.runTransaction
  GraphMutation.apply() … LazyLayoutCacheItem.AllItemsPhaseMutation
    LazyLayoutViewCache.updateItemPhases()
      LazyLayoutViewCache.updateItemPhase(_:)
        AG::Graph::value_set(…)          ← jediný externí zápis v celém vzorku
          AG::Graph::propagate_dirty(…)
```

To je přesně ten `_External -> State, changed`, který devátý záchvat vypsal jako změněný vstup
`LazySubviewPlacements` (a k němu `ScrollViewChildTransform` a `UnaryChildGeometry<_PaddingLayout>`,
tedy **posunutý scroll** — v sedmém záchvatu je vidět i
`LazySubviewPlacements.makeAnchorTranslationIfNeeded`). Dva zapisovatelé jedné krabice se v jednom
kole nemusí shodnout, a pak se to kolo nemá kde zastavit.

Kolik toho v hořícím kole je: **1524 z 13 479** vzorků hlavního vlákna v devátém záchvatu (tab
`Konverzace`), **4274 z 19 930** v sedmém (tab `Soubory`) — v obou tedy ta řada je, a to je jediná
věc, kterou mají všechny záchvaty společnou kromě samotného `LazySubviewPlacements`.

**Zamítnutá varianta: vyplněný ideál.** Nabízelo se nechat pružný rámec a jen mu vyplnit
`idealWidth`/`idealHeight`, aby na „jak velký bys chtěl být“ odpověděl sám. Podle tabulky výš to
**nestačí**: `nil` dotaz zmizí, průzkum `0`/`∞` zůstane celý, takže zápis do líného seznamu zůstane
taky — jen s jinými argumenty. Do repa se to proto nedostalo a v `FillingSlot.swift` je to zapsané;
sonda ten scénář **měří dál** (`TimelineShape.declaredIdeal`), aby to nebyl dohad.

**Kde `fillingSlot()` je** (výčet hlídá `LazyIdealSizeTests`):

| Místo | Který stack se ptal |
|---|---|
| `ConversationView.timeline` | `VStack` osy (lišta / osa / composer) |
| `DiffView.files` | `HStack` (strom souborů / diff) |
| `FileTreeView` | `VStack` sloupce se stromem |
| `ActivityFeedView` | `VStack` okna v `HomeView` |
| `ReviewPanel.cards` | `VStack` (věta o hlavě / karty) |
| `FindingsTableView` | `VStack` tabu `Nálezy` |

**Kde naopak nepatří:** `CommitListView`, `ReviewProgressView` a `StepFeedView`. Jejich `ScrollView`
je korunou svého view a rozměr dostává rámcem (`frame(width:height:)` z obsahu záložky,
`frame(height:)` u živého výpisu kroků z #325), takže se na ideál nikdo neptá — ověřeno tou samou
sondou: `frame(width:height:)` průzkumné dotazy neposílá. Kdyby nad ně někdo vložil stack, patří
tam modifikátor taky.

**Co to nedokazuje.** Že kolo z #361 přestane vznikat, se v harnessu ověřit nedá — za devět záchvatů
se ho nepodařilo vyrobit ani jednou (viz [`docs/testovani.md`](docs/testovani.md)). Ověřená je
**vazba**: že se ten druhý zapisovatel v aplikaci nemá kde vzít.

#### Nezastavilo to nic, a je to změřené (#361, třinácté kolo)

Dvanáctý záchvat běžel na buildu s `fillingSlot()` a hořel stejně, takže odstavce výš se musí číst
jako **zlevnění, ne oprava**. Naměřeno na třech záchvatech, vždy jako **největší nezanořený uzel**
proti počtu vzorků hlavního vlákna:

| | 9. (`v1.1.166`, pružný rámec) | 11. (`v1.1.170`, `fillingSlot`) | 12. (`v1.1.170`) |
|---|---|---|---|
| vzorky hlavního vlákna | 13 479 | 9 330 | 16 486 |
| `measureEstimates` | 1 524 (**11,3 %**) | 1 046 (**11,2 %**) | 2 173 (**13,2 %**) |
| `updateItemPhases` → `value_set` | 1 617 (12,0 %) | 738 (7,9 %) | 919 (5,6 %) |
| `ConversationRow.id` za záchvat | 7,1 M | 3,6 M | 2,3 M |

Takže dolů šla **cena** (dotazy na identitu na třetinu), ne ten zápis. Do třináctého kola stálo
v zadání i v komentáři na issue, že `measureEstimates` z kola zmizel („35 z 21 834“); byla to
**chyba čtení** `sample`u — 35 je počet **řádků se vzorem** ve stromu volání a 21 834 počet
**řádků souboru**. Ten jeden uzel nese 1046 vzorků. Postup, jak se to čte správně, je
v [`docs/testovani.md`](docs/testovani.md).

**Ten dotaz na velikost neodstraní žádný tvar té štěrbiny.** O velikost si totiž říká `ScrollView`
sám — `ScrollViewUtilities.sizeThatFits(in:contentComputer:axes:)` se ptá svého obsahu, aby zjistil
**svou** šířku —, takže mezi ním a `LazyVStack`em není co vypnout. Změřeno sondou
`LazySelfReferenceProbe` na scéně tvaru osy (300 řádků, pumpa špinící rozvržení, 60 vzorků
evaluačního zásobníku):

| Podoba místa | Dotaz na velikost seznamu jako **kořen** | …**vnořeně** v cizí aktualizaci | `LazySubview*` v grafu |
|---|---|---|---|
| `frame(maxWidth: .infinity, maxHeight: .infinity)` | **30** | 0 | 30 |
| `fillingSlot()` | 0 | **18** | 31 |
| `GeometryReader` **bez** vnitřního rámce | 0 | **18** | 31 |
| `VStack` místo `LazyVStack`u | 0 | 0 | **0** |

Dvě věci z té tabulky. **Zarovnání v tom nehraje roli** — třetí řádek nemá co centrovat, a dotaz
tam přesto je, takže „`_FrameLayout` se ptá kvůli `alignment`“ je vyloučené. A **mění se jedině
odkud se ptá**: pružný rámec si ho odpovídá jako vlastní kořen aktualizace, měřená štěrbina vnořeně.
Kdo přesně je ten vnější kořen, **není stabilní** (naměřeno `LazySubviewPrefetcher`,
`AnimatableAttribute<EdgeInsets>` i `ScrollViewChildSafeArea`, a mění se i s tvarem scény), takže se
tvrdit dá jen to slabší.

**Co je `_External -> State`: fáze položky, ne náš zápis.** Zadání třináctého kola ho vedlo jako
kandidáta na „třetí pohon“, protože roste ve všech třech záchvatech (182 → 313 → 382) spolu
s `DynamicLayoutComputer<_HStackLayout>` (180 → 312 → 365). Je to ale **downstream toho zápisu
z `LazyLayoutViewCache`**, a stojí na tom trojí: v každém zásobníku je jich **pět a každý má
u sebe layout computer** té položky v konstantním odstupu čísel uzlů (1288 B v aplikaci, 676 B
v harnessu); pětka je řádově počet **viditelných** uzlů osy; a `AG::Graph::value_set` je v celém
vzorku **jediný** a leží pod `updateItemPhases()`. `DynamicLayoutComputer<_HStackLayout>` je pak
prostě `HStack` v `ConversationNodeView` — v harnessu, kde je řádkem pružný rámec, stojí na tom
místě `UnaryLayoutComputer<_FlexFrameLayout>`. **Třetí pohon z aplikace tedy nikdo nenašel, protože
tam není**; ten, co kolo krmí, je pořád ten uvnitř SwiftUI.

**Třetí největší kus toho kola je naše linka osy, a doteď ho nikdo nepojmenoval.** Za
`LazySubviewPlacements` a `measureEstimates` stojí

```
SecondaryLayerGeometryQuery.value.getter
  ViewDimensions.subscript.getter
    LayoutEngineBox.explicitAlignment(_:at:)
      ViewLayoutEngine.explicitAlignment(_:at:)
```

tedy **2 149 z 16 486** vzorků (13,0 %) ve dvanáctém záchvatu, 1 033 z 9 330 (11,1 %)
v jedenáctém — a **409 z 13 479 (3,0 %)** v devátém, takže na rozdíl od `measureEstimates` to
napříč záchvaty **konstantní není**. To je i důvod, proč to není pohon: v devátém záchvatu kolo
hořelo stejně a tenhle dotaz byl na třetině. `SecondaryLayerGeometryQuery` je geometrie druhé vrstvy, tedy
`ConversationNodeView`: `.background(alignment: .topLeading) { line }`. Zarovnání pozadí si žádá
`ViewDimensions[.leading]` a `[.top]` na hlavní vrstvě, a ta je `HStack`, takže se dotaz propadne
do jeho layout engine — u **každého** viditelného uzlu a v **každém** kole.

Nechává se to tak, a je to rozhodnutí, ne opomenutí. Je to **práce v kole, ne jeho pohon**, a je to
úvaha ze struktury, ne z měření: dotaz na zarovnání jen **čte** geometrii, nemá akci a nezapisuje do
grafu nic — v `changed` vstupech hořícího kola není ani v jednom ze tří záchvatů. A alternativa je
vrátit linku do `ZStack`u, což je pružná výška v řádku líného seznamu, tedy zakázaná třída, kvůli
které se to u #375 z `ZStack`u zrovna stěhovalo. Zapsané je to proto, aby se u čtrnáctého kola
nehledalo odznova, co je těch 13 % vzorků pod `explicitAlignment`.

**Zbývající možnost, i s cenou: přestat na ose používat líný seznam.** Je to jediná podoba, u které
se ta vazba nemá kde utvořit (poslední řádek tabulky: v grafu ani jeden `LazySubview*` atribut).
Cena změřená na téže scéně: **první rozvržení 300 uzlů 2,2–3,4 ms proti 32–35 ms** a dotazů na
identitu 7,6× — a to s obyčejným `Text`em, ne s markdownem, takže na skutečné konverzaci (strop
je 100 položek na kategorii, viz `ConversationQuery.pageSize`) by to bylo horší. Ve třináctém kole
se to proto do repa **nedostalo**; **v patnáctém ano** — viz sekce níž.

#### Patnácté kolo: osa líný seznam nemá (#361)

Čtrnáctý záchvat je první, ze kterého se dá kruh přečíst celý, a rozhodl tím tu otevřenou otázku.
Dva `sample`y ze **živého** hoření (100 % CPU, stav `R`) mají **shodnou signaturu**, takže se na
rozdíl od tří vzorků u #350 nevylučují:

| | vzorek A (5294) | vzorek B (7848) |
|---|---|---|
| `LazySubviewPlacements.placeSubviews` | 3192 · **60,3 %** | 4751 · **60,5 %** |
| `ForEachState.forEachItem` | 1609 · 30,4 % | 2334 · 29,7 % |
| `LazyLayoutViewCache.updateItemPhases()` | 377 · 7,1 % | 533 · 6,8 % |
| `AG::Graph::value_set(` | 360 · 6,8 % | 522 · 6,7 % |

**Kolo se zavírá samo uvnitř SwiftUI a my v něm nejsme**: umístění položek zapíše fázi do grafu
(`updateItemPhases` → `value_set` → `propagate_dirty`), zašpiněný graf si vyžádá další update
a umisťuje se znovu. Pohon zvenčí je nula (žádný `CFRunLoopTimer`, `CVDisplayLink` ani hover) a ze
101, resp. 158 rámců `PRism.debug.dylib` jsou všechny kromě dvou vstupních bodů jen value-witness
kopie `ConversationRow`. Zlevňovat obsah kola (#375, #379, #386, #393, #435, #438) tedy nemělo co
zastavit — a čtrnáct kol to potvrdilo.

Osa proto kreslí **`VStack`**, ne `LazyVStack`. Cena i výnos jsou změřené na **skutečných**
`ConversationNodeView` (`ConversationAxisShapeProbe`, Debug, okno 1000×800):

| Uzlů | `LazyVStack` | `VStack` | `List` |
|---|---|---|---|
| 44 | 5,4 ms | **55 ms** | 78 ms |
| 150 | 5,0 | **187** | 78 |
| 300 | 5,4 | **413** | 95 |
| 400 | 5,8 | **614** | 112 |
| projíždění 150 × 40 pt (300 uzlů) | 0,31 / 0,29 s | **0,86 / 0,85 s** | neměřitelné |
| `LazySubview*` v evaluačním zásobníku | 2 vzorky ze 2 | **0** | 0 |

**Na čem to stojí: osa je shora omezená.** `ConversationQuery` se ptá `first: 100` na každý ze
čtyř seznamů a **nestránkuje**, takže uzlů nemůže být víc než čtyři stovky — cena prvního rozvržení
má strop. Diff takovou mez nemá (tisíce řádků), a proto v něm `LazyVStack` **zůstává**; hlídá to
`ConversationAxisEagerTests` (líný seznam v `ConversationView` + ta mez, spočítaná z plných
stránek, ne opsaná z konstanty).

**`List` je zamítnutý, i když čísla vypadají líp**, a jsou k tomu tři měřené důvody: výška obsahu
je u něj **odhad** (44 uzlů 4 876 pt proti 6 745 u `VStack`u, 300 uzlů 11 020 proti 45 432), takže
posuvník lže a poloha při projíždění skáče; **syntetické gesto s ním nepohne vůbec**, takže se cena
projíždění naší sondou změřit nedá; a řádek `List`u nese vlastní chrome (výběr, oddělovače,
pozadí), tedy změnu vzhledu, která patří napřed do mockupu. Zůstává jako měřená varianta pro
případ, že by cena prvního rozvržení začala vadit.

**Co to nedokazuje.** Že záchvat nepřijde. Kolo se v harnessu nepovedlo vyrobit ani počtrnáct,
takže „po opravě nehořelo“ by bylo tvrzení bez zkoušky. Doložené je **strukturálně**: ten zápis do
grafu nemá na ose kdo udělat, protože `LazySubview*` atributy tam nevzniknou. A **netýká se to
diffu** — sedmý záchvat hořel nad tabem `Soubory` a tam líný seznam zůstává, takže se ta třída kola
může vrátit tam.

Jak to drží pohromadě:

- `availableWidth(_:)` ustaví konkrétní šířku pro podstrom. Je **jediné místo**, kde se měří —
  `GeometryReader` na hranici obsahu tabu v `PullRequestDetailView`. Dovnitř osy ani diffu
  nepatří: tam by byl na každé položce.
- `narrowingWidth(by:)` zúží šířku pro děti o vlastní odsazení nebo o pevného sourozence.
- `filling(alignment:)` se roztáhne na dostupnou šířku — konkrétně, když ji zná, jinak pružně jako
  dřív. `nil` znamená „nikdo ji nenastavil“, takže se views dají použít i mimo měřenou cestu.

**Na pořadí modifikátorů záleží a plete se** (chyceno vlastní revizí u #220):
`narrowingWidth` mění environment tomu, co obaluje, takže

- `filling()` → `narrowingWidth(32)` dá rámec `šířka − 32`. To chce obsah **vedle pevného
  sourozence** (osa 24 + mezera 8).
- `narrowingWidth(22)` → `padding(11)` → `filling()` dá rámec plné šířky a dětem `šířka − 22`.
  To chce **blok s vnitřním odsazením** — v obráceném pořadí nedosáhne hlavička karty na její
  pravou hranu.

**Co zatím pružné zůstalo:** poloviny s mými rozdělanými komentáři ve splitu
(`DiffRowView.column(_:)`). `maxWidth: .infinity` tam drží **stejně široké sloupce**, takže
`filling()` by každé polovině dalo plnou šířku a rozvržení by se rozsypalo. Potřebuje to krok
„poloviční šířka“ a je to samostatná práce. (Do #446 tu stály i poloviny `DiffPairView`; ten je
smazaný jako mrtvá cesta, úvaha ale platí dál — je to tentýž tvar.)

**Když se vedle tabu něco přestane kreslit, šířka se nepřepočítává** (#294). Panel vpravo je
**sourozenec** `GeometryReader`u v tom samém `HStack`u, takže jeho zmizení změní to, co se změří —
a tab dostane správnou šířku bez jediného odečtení. Vlastní aritmetika („odeber šířku panelu“) je
zrovna ta cesta, kterou vzniklo #291. Platí to i naopak: **čísla o šířce v komentářích zastarají**,
protože se počítají z toho, co v okně vedle sebe stojí. Po #294 je nejužší `Nálezy`, `Kontroly`
a `Průběh` **648 bodů** (okno 700 − rail 52), kdežto `Přehled`, `Změněné soubory` a `Konverzace`
mají pořád 128 (okno 700 − rail 52 − vytažený panel 520). Testy proto měří **každé pásmo zvlášť**
(`OverviewWidthTests` proti `PanelFreeTabWidthTests`).

### Kdo přejde na `filling()`, musí přejít i na `narrowingWidth()` (#291)

**`filling()` je konkrétní rámec, takže si `availableWidth` bere doslova** — a to je oprava proti
tomu, co dělal `frame(maxWidth: .infinity)`. Pružný rámec **přijme návrh**, takže se sám přizpůsobí
tomu, kolik místa rodič dává; konkrétní rámec si vezme šířku z prostředí a **rodičovo odsazení ho
nezajímá**. Kdo tedy vymění jedno za druhé někde uvnitř odsazeného bloku, přidá k němu tolik bodů,
kolik má ten blok odsazení.

Takhle vznikla #291: #279 nahradila v sazbě Markdownu (`MarkdownText`) šest pružných rámců za
`filling()`. V konverzaci to prošlo, protože `ConversationEntryView` a `ThreadBubbleView` mají
`narrowingWidth(by: 22)` z #220. `OverviewView` ho ale nemá **ani na svém `padding(16)`, ani na
`padding(.horizontal, 13)` karty s popisem**, takže popis PR dostal šířku celého tabu a karta kolem
něj vyšla o 42 bodů širší, než jaké je místo. V okně to nebylo vidět jako přetečení, ale jako
**neukončený boxík**: `ScrollView` je `NSScrollView`, takže těch 42 bodů uřízl — a s nimi pravou
hranu karty a popisek `Otevřít na GitHubu`.

Dvě věci, které z toho platí dál:

- **Zúžení se přidává na každé odsazení na cestě**, ne jen na tom vnějším. `Přehled` má dvě
  (`narrowingWidth(by: 32)` u tabu, `narrowingWidth(by: 26)` u karty) a chyběla obě.
- **Rámec, ve kterém se má přetečení dát změřit, musí zůstat pružný.** `Přehled` proto **schválně**
  drží `frame(maxWidth: .infinity)` na hranici `ScrollView`u a na obou rámcích karty: konkrétní
  rámec si drží svůj rozměr i nad dítětem, které se do něj nevejde, takže by chybějící zúžení
  **schoval** — sazba by ležela na pravém obrysu a karta by zvenčí vypadala v pořádku. Vyzkoušené
  vložením regrese: s `filling()` na odsazeném těle popisu zůstaly `OverviewWidthTests` zelené
  i po smazání `narrowingWidth(by: 26)`. Cena je jedna úroveň vyjednávání na tab, což proti
  ~5,5× na úroveň v zanořeném seznamu není nic — tady jde o jeden blok, ne o tisíc řádků.

### Pruh záložek — čtyři podoby podle šířky (#316, #318, #452)

`PullRequestTabBar` je jediné místo v okně, kde se o podobě rozhoduje **`ViewThatFits`em**, a ne
spočítanou šířkou. Kandidáti jsou čtyři a jmenují se `Layout`; bere se **první, který se vejde**,
takže pořadí je to, co říká, co ustupuje dřív. Čísla jsou **po osmé záložce** (`Zeptat se`, #452):

| Podoba | Co kreslí | Ideální šířka tabu | Okno (+ rail 53) | S odznaky `888` |
|---|---|---|---|---|
| `full` | popisky u všech záložek a vpravo `+X −Y` | 1131–1133 b | 1184–1186 b | 1216–1218 b |
| `labels` | popisky, bez `+X −Y` (#316) | 1021–1023 b | 1074–1076 b | 1093–1095 b |
| `icons` | ikony s odznaky, popisek jen u aktivní (#318) | 573–639 b | 626–692 b | 645–711 b |
| `compact` | jen ikony s odznaky (#452) | 526 b | 579 b | 598 b |

Pásma jsou tam proto, že šířka závisí na tom, **která záložka je aktivní** — její popisek je
polotučný a v `icons` je jediný, co se kreslí. Horní konec drží `Změněné soubory`, dolní `Nálezy`.

Co se u toho nemá rozbít:

- **`+X −Y` ustupuje první, a je to ten správný kus** (#316). Mluví o rozsahu **celého PR**, což je
  odpověď na otázku `Změněných souborů`; v `Commitech`, `Kontrolách` ani `Průběhu` není o čem.
  Záložka je proti tomu cesta k obsahu, který jinudy vidět není. Ta výměna vyšla skoro na nulu:
  pilulka stojí 110 bodů a sedmá záložka s odznakem 112, takže hranice povyrostla o **dva body
  okna**, ne o sto dvanáct.
- **Popisky ustupují druhé, a všechny naráz** (#318). Ustupovat po jednom (nejdřív `Změněné
  soubory`, pak `Konverzace`…) by znamenalo pruh, ve kterém část záložek text má a část ne — tedy
  sedm podob podle šířky místo tří, a v každé jinak dlouhý skok mezi sousedy.
- **Popisek u aktivní záložky zůstává.** Odpovídá na jinou otázku než ostatní: ne „kam se dá jít“,
  ale „kde jsem“. Podtržení to říká taky, jenže samo o sobě mezi sedmi ikonami — a je to zrovna ten
  údaj, kvůli kterému se do pruhu kouká nejčastěji.
- **Odznaky zůstávají ve všech třech podobách.** Počet nálezů, červený počet u `Kontrol`, puntík
  u běžícího `Průběhu` a počet commitů jsou ta informace, kvůli které se do pruhu kouká; kdyby
  padly s popisky, byla by z ikonového stupně řada ozdob.
- **Bez popisku musí záložku pojmenovat něco jiného.** Ikona přebírá `accessibilityLabel`
  a tlačítko dostane nápovědu (`help`) — obojí **jen tehdy, když se popisek nekreslí**, ať se jméno
  nečte a neukazuje dvakrát. Prázdný řetězec by nechal prázdný tooltip, takže je to `ViewModifier`
  s `if let`, ne `help("")`.
- **Čtvrtá podoba přibyla u #452, a je to změna měření, ne názoru.** Do té doby tady stálo, že
  samotné ikony bez popisku i u aktivní záložky **nevzniknou**, protože se na ně nedá přijít: se
  sedmi záložkami se `icons` vešly do tabu od 564 b (okno 617) a i s trojmístnými odznaky u všech
  od 636 b (okno 689), tedy pod podlahu okna 700. Osmá záložka to posunula na **645 až 711 b**
  (podle toho, která je aktivní) proti tabu 647 b v nejužším okně — šest z osmi podob se nevejde
  a pruh by se v tom krajním stavu **zalomil**, tedy přesně ta porucha, kterou #318 opravovalo.
  `compact` se s 598 b vejde. **Na běžná data se na ni nepřijde** (`icons` chtějí 573–639 b) a je
  to samo tvrzení v `TabStripWidthTests`: `compact` se ukazuje jedině s trojmístnými odznaky.
- **Osmá záložka posunula i to, co je vidět ve výchozím okně** (#452). Okno 1100 dávalo do té doby
  `full`; dneska je to `labels`, takže ve výchozí šířce **není `+X −Y`** a vrací se od ~1184 bodů.
  Je to ta výměna, kterou pořadí podob předepisuje, a tatáž, jakou zaplatila sedmá záložka (#316).
- **Kandidáti se vypisují, nedělají se `ForEach`em.** `ViewThatFits` vybírá mezi **svými dětmi**
  a jedna `ForEach` je jedno dítě.
- **`bar(_:)` je `internal` a nese i okraj a linku pod pruhem.** Okraj je šířka, která se taky musí
  vejít, takže patří dovnitř kandidáta; a `internal` proto, aby si test mohl vyrendrovat **jednu
  podobu** bez skládání vlastní chromě — dvě místa s toutéž chromí znamenají, že měření kontroluje
  něco jiného, než co se kreslí (#236).

**Proč tady `ViewThatFits` stačí, když u #284 nestačil.** V #284 byly popisky v řadě se
`lineLimit`em, takže se **zkracovaly**: `Text` přijal menší šířku místo toho, aby nahlásil, že se
nevejde, `ViewThatFits` vybíral pořád nejširší variantu a rozhodovat musela spočítaná šířka
(`TextWidth`, `IncrementalDiffBar.layout(in:)`). Pruh záložek `lineLimit` nikde nemá, takže se
**zalamuje** — ideální šířka zůstává šířkou nezalomeného popisku, a to je přesně ta hodnota, kterou
`ViewThatFits` porovnává. **Není to úvaha, je to změřené**: `TabStripWidthTests` porovnávají render
celého pruhu proti jedné podobě vykreslené napřímo, v šesti šířkách, pixel po pixelu.

Do #318 se pruh pod 939 body okna **zalamoval** — v nejužším povoleném okně (700) byl vysoký
90 bodů místo 30, se šesti záložkami 75. Nebyla to tedy cena sedmé záložky, ale stav rozbitý
i bez ní, a proto se to opravovalo zvlášť.

## Nekonečné animace v okně (#350)

**Animace, která nikdy nedoběhne, nesmí být ve SwiftUI.** Je to tatáž třída chyby jako pružná šířka
výš — jen cenu neplatí jeden layout, ale **každý snímek**.

Proč: SwiftUI si na animovaný atribut vyžádá nový průchod při každém obtažení obrazovky, a ten
průchod jde na macOS přes `NSHostingView.layout()`. To rozvrhne **celý obsah okna, a dvakrát** —
jednou `render(interval:…)` pro kresbu a jednou `invalidateSizeConstraintsIfNecessary()` →
`minSize()` → `ViewGraph.sizeThatFits(_:)` kvůli constraints hostujícího view. Jeden snímek proto
stojí tolik, kolik stojí rozvržení celého okna, a při 120 Hz je z toho **plné hlavní vlákno** bez
ohledu na to, jak malý je ten animovaný prvek.

Změřeno u #350 na `SpinningRing` (prstýnek „review běží“ v pruhu záložek, #180). Sonda
`IdleWindowSpinProbe` hostuje detail PR v okně **na obrazovce**, nechá smyčku běžet a čte CPU
hlavního vlákna:

| Stav nečinného okna | CPU hlavního vlákna |
|---|---|
| review neběží | 0 % |
| review běží, jen kapsle reviewerů (`ProgressView`) | 2–3 % |
| review běží + prstýnek **ve SwiftUI** (`repeatForever`) | **99 %** |
| review běží + prstýnek **v CoreAnimation** | 2–3 % |
| prstýnek sám, bez detailu v okně, **ve SwiftUI** | 3 % |

(Rozsah je rozptyl mezi dvěma běhy sondy. Rozhoduje pořadí velikosti, ne jednotky procent — a to,
že jsou druhý a čtvrtý řádek **stejné**.)

Dva řádky nesou celý závěr. Po opravě stojí okno s prstýnkem **stejně jako okno bez něj** (2–3 %),
takže z ceny nezbylo nic — a poslední řádek říká, proč: **cena není v prstýnku, je v tom, co je vedle
něj v okně.** Prstýnek v prázdném okně stojí 3 % i s tou SwiftUI animací, protože rozvrhnout prázdné
okno je zdarma; s otevřeným PR je to celý strom hlavičky, pruhu záložek, tabu a panelu, a totéž
otáčení stojí 99 %. Proto se to v provozu projevilo jako „okno tuhne, když pustím review“ a proč to
**nezáviselo na počtu běžících session** (jeden prstýnek stačí) ani na tom, který tab je otevřený.

Léčba je `SpinningRingView` — `NSView` se dvěma `CAShapeLayer`y a `CABasicAnimation` na
`transform.rotation.z`. Otáčení obslouží render server, hlavní vlákno o něm neví a SwiftUI nedostane
ani jeden snímek. Tři věci, které u toho drží kresbu:

- **`isRemovedOnCompletion = false`** — jinak se prstýnek po první otáčce vrátí do výchozí polohy
  a stojí.
- **Otáčení se přidává jen tehdy, když tam ještě není.** `layout()` běží vícekrát a druhé přidání by
  animaci restartovalo, takže by prstýnek poskakoval.
- **Barvy se resolvují znovu, ne jednou v initu** (`resolveColours()`): `CGColor` ve vrstvě se sám
  podle vzhledu nepřebarví, takže by prstýnek zůstal v barvě z doby svého vzniku. Volá se ze **tří**
  míst, protože každé je jiná příležitost — první kresba (`updateLayer()`), přepnutí světlý/tmavý
  (`viewDidChangeEffectiveAppearance()`) a **změna systémového akcentu**
  (`NSColor.systemColorsDidChangeNotification`). To třetí je práce, která přišla s přepisem do
  AppKitu: ve SwiftUI se `.tint` resolvovala sama, kdežto tady by bez pozorovatele prstýnek po změně
  akcentu v Nastavení systému držel starou barvu, dokud se nepřepne režim. Testuje se to na
  **barvě oblouku** po poslané notifikaci, ne na příznaku překreslení — příznaky bez okna na
  obrazovce nedrží (vyzkoušené obojí, `NSView.needsDisplay` i `CALayer.needsDisplay()`), takže by
  z nich byl test, který padá nad správným kódem.
- **Šířka tahu si musí vyžádat rozvržení.** Cesta je o půl tahu zúžená dovnitř, aby se kruh vešel do
  rámu celý, takže se se šířkou mění — a počítá se v `layout()`. Bez `needsLayout = true`
  v `apply(lineWidth:isSpinning:)` by silnější tah kreslil starou cestu.

**`ProgressView` do téhle pasti nepadá** (2–3 % výš), protože je na macOS AppKitový — animuje ho
`NSProgressIndicator`, tedy taky CoreAnimation. Zůstává proto v kapslích reviewerů i ve stavovém
řádku beze změny.

**Tohle není jediná příčina tuhnutí a nesmí se za ni vydávat.** Ze tří vzorků ztuhlé aplikace ji
vysvětluje **jeden**; druhá signatura (vzorky nad osou konverzace a nad diffem) má **100 % vzorků
hlavního vlákna** pod `NSRunLoop.flushObservers → NSHostingView.beginTransaction →
GraphHost.flushTransactions`, tedy pod **vyprazdňováním čekajících transakcí v každém kole smyčky**,
a `NSDisplayCycleFlush` ani `runAnimationGroup` v ní nejsou vůbec. Že jsou to dvě věci, je ověřené
vložením regrese: build s vrácenou SwiftUI animací vyrobí zase jen tu **první** signaturu
(`NSDisplayCycleFlush` 144 z 976 vzorků, `flushObservers` nula). A u toho vzorku nad diffem
neběželo žádné review, takže tam prstýnek na obrazovce **ani nebyl** — pruh ho kreslí jedině při
`isRunning`, což je `reviewTasks[pr] != nil`.

O té druhé je zapsané, co se změřilo: cena je v tom, že `ScrollView` počítá **ideální velikost**,
což donutí líný seznam projít `_LazyLayout_Subviews.apply` přes **celý** `ForEach` (proto v listech
`FileDiff.id`, `DiffRow.id`, `ConversationNode.id` a `_StringGutsSlice._fastNFCCheck` — porovnávání
řetězcových identifikátorů). Je to **#358** a **co graf špiní, se od té doby ví**: smyčku pohání
hover. Ve vzorku ztuhlého okna je 92,8 % vzorků hlavního vlákna v jedné transakci a **žádný jiný
callout tam není** (nula na timeru, nula na hlavní dispatch frontě), takže ji nekrmí nic zvenčí;
uvnitř je 1630 z 1690 vzorků `Update.dispatchActions()` v `EventBindingManager
.enqueueHoverUpdateIfNeeded()` → `NSHostingView.didRequestHoverUpdate()`, a z něj se přes
`HoverResponder.updatePhase(_:)` volá `.onContinuousHover` v `DiffPairBlockRowView`. Ta akce píše
`@State hovered` **bezpodmínečně** (a je to `(index: Int, side: DiffSide)?`, tedy tuple, který
`Equatable` není), takže se tělo bloku zašpiní, přestaví se rozvržení líného seznamu, změní se
geometrie responderů — a hover update se naplánuje znovu. Reprodukce si žádá **split diff a kurzor
ležící v okně**; to poslední je důvod, proč se to na vyžádání nedařilo (nečinnost s myší mimo blok
kódu smyčku nezavře).

**Opraveno v #358**: hover se do `@State` zapisuje jedině při změně, rozhodnutí drží
`Policy.hoverChange(from:to:)` a stav split pohledu je `HoveredCell` (`Equatable`), ne tuple.
Podrobnosti u toho typu a v sekci `Policy` níž.

**Co se tím taky neopravilo:** každá **událost průběhu review** (`ReviewProgress`) pořád zašpiní tělo
`PullRequestDetailView` (čte `store.reviewProgress(for:)` a `runningReviewers(for:)` v hlavičce),
takže se přepočítá pruh záložek se všemi osmi odznaky a přestaví se obsah tabu. Změřeno
`DetailProgressMeasurement`: **9–55 ms na událost** podle otevřeného tabu a podle toho, kolik je
v okně vidět. Na tuhnutí to nestačí — skutečná session dělá **0,07 až 0,37** události za sekundu
(změřeno na 145 transcriptech běhů PRismu, viz [`testovani.md`](testovani.md)), tedy nejvýš dvě
procenta procesoru —, ale je to práce, která tam být nemusí. Vlastní issue na to zatím není; oprava je
vytáhnout pruh běhu do vlastního view, aby událost špinila jeho, ne celý detail.

## Okno nastavení (`App/Views/Settings/`)

Scéna `Settings` (⌘, i ozubené kolo v toolbaru přes `openSettings`). Zapisuje do téhož
`config.json`, který jde editovat ručně.

| Typ | Co dělá |
|---|---|
| `SettingsScene` | Obsah scény; dokud neprošel preflight, není store a okno to řekne |
| `SettingsView` | Boční navigace (#177), patička s cestou a stavem uložení, zámek na rozbitý soubor |
| `SettingsSection` | Sedm stránek ve třech skupinách — `Co se hlídá`, `Co jde ven`, `Prostředí` |
| `SettingsModel` | Rozepsané nastavení: odložený zápis, rozpoznání změny zvenčí |
| `SourcesSettingsView` | Zdroje PR (search dotazy) |
| `ReviewSettingsView` | Výchozí režim, jazyk nálezů a **časový limit běhu** (#320), skilly, sady podle jazyka, **prompt review** (#281), blokující kategorie |
| `ReviewPromptEditor` | Psaná šablona, legenda zástupných textů, `Obnovit výchozí`, náhled složeného promptu a zamčené jádro (#281) |
| `ReviewTimeoutField` | Číslo v minutách a stížnost, když je hodnota v souboru mimo meze (#320). **Jedno view pro obě místa**, kde se limit nastavuje |
| `DiffSettingsView` | **Pohled na diff** — nastavení člověka, ne repa, proto jen globálně |
| `PublishingSettingsView` | **Odesílání na GitHub** — vlastní stránka, viz níž |
| `RuntimeSettingsView` | Interval pollingu, rozpočet cache, souběžné session, denní limit, model |
| `NotificationSettingsView` | Stránka `Notifikace` (#86): hlavní vypínač a čtyři události |
| `LanguageSkillsEditor` | Mapa „programovací jazyk → sada skillů“; ukazuje jen nastavené jazyky |
| `RepositorySettingsView` | Seznam rep vlevo, režim, povolení odesílání, override sad a **vlastní časový limit** (#320) vpravo |
| `StringListEditor`, `SourceListEditor` | Editory seznamů — řetězců a zdrojů |
| `SettingsNumberField` | Číslo se šipkami **i** přepsáním; ořezává na povolený rozsah |

Věci, které se u toho nemají rozbít:

- **Sedm stránek, ne devět** (#177). Návrh kreslí i `Cache a úklid` a `Zdraví služeb`; obojí
  je vynechané, protože pro ně v aplikaci **není obsah** — cache se dnes uklízí sama podle
  rozpočtu a zdraví služeb žije ve stavovém řádku. Prázdná stránka je horší než chybějící,
  a tahle úvaha platí i pro rail (#180).
- **Dělí se podle otázky, na kterou se odpovídá** (#177), ne podle typu ovládacího prvku.
  `Odesílání` je proto vlastní stránka, i když je to jeden přepínač a jeden seznam: je to jediné
  místo, kde se rozhoduje, jestli z aplikace **může něco odejít** (tvrdá podmínka č. 1), a text
  je tam důležitější než přepínač. Do #177 to byly tři záložky, ze kterých `Obecné` nesla osm
  sekcí a hledalo se v ní scrollováním.
- **Neplatná šablona promptu se neuloží** (#281, `ReviewPromptEditor`). Je to jediné pole v okně,
  které si drží vlastní `@State` místo `Binding`u do konfigurace — a je to schválně: šablona bez
  `{{baseSha}}` by běhu sebrala to, proti čemu diffuje, takže se zapíše teprve platná hodnota
  a v souboru zatím zůstává poslední, se kterou se dá běžet. Neznamená to mlčet: u pole stojí,
  **který** zástupný text chybí a proč to vadí, plus věta, že se to neukládá — „nic se nestalo“
  je jinak k nerozeznání od „funguje“. Tři věci, na kterých to stojí:
  - **Prázdná šablona chyba není.** Znamená „ber výchozí“, takže se u ní vypisuje poznámka, ne
    stížnost, a validuje se to, s čím se doopravdy poběží (`Policy.reviewPromptTemplate(from:)`).
  - **Změna zvenčí pole srovná.** Soubor jde editovat ručně, takže `onChange` na uložené hodnotě
    přepíše `@State`; vlastní zápis se vrátí se shodnou hodnotou, takže nic nepřepíše.
  - **Ručně napsaná neplatná šablona se hlídá jinde.** Okno ji nezapíše, ale do souboru se dostat
    může — proto s ní `AppStore.review(_:skills:)` review **nespustí** a fáze zůstane
    `failed(detail:)` s tou samou větou. Text hlášky je jeden (`ReviewPromptTemplate.Problem`),
    aby se okno a hlava PR nerozešly.
- **Časový limit běhu sedí na `Review a skilly`, ne na `Běh`** (#320). Stránka `Běh` je hrst čísel
  o **stroji a prostředí** (interval, souběh, rozpočet cache) a žádné z nich nemá override; limit
  je proti tomu třetí věc o **spuštěném review**, kterou si repo smí přebít — vedle režimu a jazyka
  nálezů, a proto stojí v téže sekci jako ony, ne ve vlastní. Tři věci, na kterých to stojí:
  - **Z okna se hodnota mimo meze zapsat nedá** (`SettingsNumberField` ořezává), ale ze souboru
    přijít může. Pod polem se proto vypíše, **kolik je v konfiguraci** a **s čím se doopravdy
    poběží** — spolknout to by znamenalo, že si někdo napíše 120 minut, poběží mu 60 a nic to
    neřekne. Text skládá `Policy.reviewTimeoutProblem(in:)`, aby byl jeden pro obě místa.
  - **Obě místa kreslí `ReviewTimeoutField`.** Věta o mezích má být jedna; dvě formulace téhož by
    se rozešly a z okna by nebylo poznat, že jde o totéž pravidlo.
  - **Per repo je to přepínač a číslo, ne tříhodnotový picker** jako u režimu. Hodnot je 56, takže
    „ber globální“ mezi ně nepatří jako další položka; zapnutí přepínače začíná od globální
    hodnoty, ze stejného důvodu jako u sad — override se obvykle dělá posunutím, ne psaním od nuly.
  - **„Bere globální: X min“ vypisuje sraženou hodnotu, ne tu ze souboru** (nálezem Copilota na
    #324). Když je globální číslo mimo meze, poběží se s mezí — a věta o tom, co repo dostane, by
    jinak tvrdila víc, než data unesou. Ze stejného důvodu se sraženou hodnotou **začíná i zapnutý
    přepínač**: seed z globálního nesmyslu by ten nesmysl zkopíroval do repa a hned si na sebe
    stěžoval. Obojí počítá `Policy.reviewTimeoutMinutes(from:)`, tedy totéž místo, kterým hodnota
    projde na cestě do běhu.
- **Vybraná stránka se nepamatuje mezi spuštěními.** Nastavení se otevírá kvůli konkrétní věci;
  vrátit se do něj tam, kde jsem skončil minule, není, co člověk čeká — na rozdíl od výšky
  panelu, kterou si vytáhne jednou a chce ji mít.
- **`HStack` s `Listem`, ne `NavigationSplitView`.** Uvnitř `Settings` scény si okno řídí velikost
  samo a split view se s tím pere; tenhle vzor je v okně navíc už jednou ověřený stránkou
  `Repozitáře`. Patička dál jde přes `safeAreaInset`, jinak si formulář vyhradí místo od horní
  hrany a první řádek zůstane uříznutý.
- **Esc okno zavře a rozepsanou hodnotu přitom doručí** (#151). Je to **změna proti #127**, kde
  stálo, že to nastavení schválně nemá, protože je to `Settings` a byla by to odchylka od
  zvyklosti systému; zvyklost to není (Esc zavírá i systémové nastavení) a chodí se sem přepnout
  jednu věc a zpátky k review, takže cesta ven má být pod rukou. Tři věci, na kterých to stojí:
  - **Schované tlačítko s `.cancelAction`**, ne `onExitCommand` — tentýž důvod jako u okna novinek,
    viz `hiddenShortcuts`.
  - **`flush()` je v akci výslovně, ne odkázaný na `onDisappear`.** Escem se zavírá jedním hmatem
    uprostřed psaní, takže mezi posledním úhozem a zavřením nemusí uběhnout ani těch 600 ms, po
    kterých se ukládá samo. `onDisappear` zůstává kvůli křížku a ⌘W, kde se o zavření dozvíme až
    z konce view.
  - **Zkratka je v každém stavu právě jedna.** Ve formuláři si ji drží `SettingsView` (kvůli tomu
    doručení), nad obrazovkou „nastavení zatím není k dispozici“ `SettingsScene`. Obojí naráz by
    byly dvě registrace téže klávesy a která vyhraje, není dané — přesně ta past, na které se
    u #151 rozbilo `⌥↓`.
- **Souhrn fronty (#155) sčítá, nezužuje.** Filtr reviewerů (#117) seznam zužuje a je to *pohled*;
  souhrn je tvrzení o tom, co ve frontě **je**. Kdyby se počítal z toho, co je po filtru vidět,
  tvrdil by, že práce ubyla, jen protože jsem si schoval jednoho revieweera — tatáž úvaha jako
  u tlačítka na zahození nálezů. Čtyři věci, na kterých to stojí:
  - **Počítají se PR, ne nálezy.** Tři blokující nálezy na jednom PR jsou jedna položka práce;
    souhrn odpovídá na „na kolik věcí se musím podívat“ a musí počítat totéž, co řádek seznamu.
  - **Blokující se bere z `Policy.blockingCount(in:categories:)`**, tedy z **platných** nálezů:
    odmítnutý (#113) strašit nemá a druhý výpočet by se s řádkem seznamu rozešel.
  - **Rozhodnutí „ukázat, nebo ne“ je v `AppStore.queueSummary`**, ne v `Policy` ani ve view: jediné,
    co ho rozhoduje, je stav pollingu, a ten zná jen store. Souhrn se **neukáže** dokud se seznam
    nenačetl (`lastSuccess == nil`) — nula blokujících nad nenačtenými daty vypadá jako „čisto“ —
    a nad prázdnou frontou, kde o tom mluví prázdný stav seznamu i s důvodem. **Po selhaném tiku se
    naopak ukáže**, jen nad zastaralými daty, což už hlásí banner; schovat ho při každém výpadku by
    znamenalo přestat vědět o rozdělaném review kvůli chvilkové chybě sítě.
  - **Kategorie se berou globální, ne per repo.** Souhrn je jedno číslo přes celou frontu, takže se
    nemá čím rozhodnout, které repo má přednost; řádek seznamu si dál bere ty svoje.
  - **U každého čísla stojí slovo**, ne jen ikona (`12 PR`, `3 blokující`, `2 review`) — ikona sama
    se nedá přečíst a nápověda po hoveru je až druhá šance. Konvence toho pruhu je ikona plus text,
    jako u puntíků služeb. Tvar slova bez počtu dává `Plural.word(_:one:few:many:)`; číslo se píše
    `verbatim`, protože počet položek v seznamu není množství k formátování.
  - **Prázdný draft se nepočítá** a **nulové položky se nekreslí**. Draft vzniká i tím, že se otevře
    panel a napíše se znak, který se pak smaže; a řádek plný nul je řádek, ve kterém se to jedno
    číslo, na kterém záleží, ztratí.

- **Obě pomocná okna se středí v hlavním okně, ne na obrazovce** — `WindowCentering`
  a `centeredInMainWindow()`. Do #164 to bylo `private` ve `SettingsView`, takže okno s novinkami
  z toho nemělo nic a vyskakovalo doprostřed obrazovky; je to přesně ten vzor „kontrola, která
  jinde v repu je, a tady chybí“ z `CLAUDE.md`. Sedm věcí, na kterých to stojí:
  - **SwiftUI to samo neumí.** `.defaultPosition(_:)` bere `UnitPoint` vztažený k **obrazovce**,
    takže „vystředit v jiném okně“ se jím nedá vyjádřit — proto cesta přes `NSWindow`.
  - **Okno se hlásí samo** (`WindowReader`), nebere se z `NSApp.keyWindow`: to je v `onAppear`
    klidně ještě hlavní okno a posunout omylem **jeho** je horší než nevystředit.
  - **Středí se při vzniku obsahu, ne při každém vytažení dopředu.** `openWindow(id:)` nad už
    otevřeným oknem ho jen aktivuje, a okno, které pod rukama uskočí, je horší než okno mimo
    střed. Drží to `makeNSView`.
  - **Hlavní okno se poznává podle titulku** (`MainWindow.title`) — jediný stabilní znak, kterým
    se odliší od pomocných oken a panelů. Konstanta, ne druhý literál `"PRism"`: platí pravidlo
    „jeden název všude“.
  - **Bez hlavního okna se nedělá nic.** `host(besides:)` vrátí `nil` (zavřené, skryté) a rozhodne
    systém, tedy střed obrazovky. Ne pád, ne dohad.
  - **Uložená pozice se zahazuje** (`setFrameAutosaveName("")`), takže okno odsunuté na stranu se
    **po restartu** vrátí do středu. Je to proti zvyklosti systému, ale schválně a u obou oken
    stejně: jsou to okna na přečtení a na kliknutí, ne pracovní plocha, a dvě různá pravidla pro
    dvě podobná okna se nedají vysvětlit.
  - **V rámci jednoho běhu se ta dvě okna liší, a je to vlastnost scény, ne rozhodnutí.** Změřeno
    na běžící aplikaci přes accessibility: `Settings` se zavřením **zničí**, takže se středí při
    každém otevření (s hlavním oknem přesahujícím vpravo vyšlo `x = 612`, tedy přesně ořez
    `maxX − width`). `Window` s novinkami obsah zavřením nezahodí, takže `makeNSView` podruhé
    nepřijde a okno si drží, kam ho člověk odsunul; po restartu je zpátky ve středu (změřeno
    odsunutím do kouta a restartem). Vyhnat ho do středu i tam by znamenalo středit na aktivaci
    nebo na `onAppear` — a to je zrovna ta cesta, po které okno **uskakuje pod rukama**: u novinek
    by ho posunulo i dotažení historie, protože se tím mění obsah scény.
  - **Ořez zpátky na viditelnou plochu je `max(min(…))`, ne naopak.** U okna širšího než obrazovka
    vyjde `maxX - width` menší než `minX`, takže obrácené pořadí by rámec poslalo **za levý
    okraj**. Od #164 to drží test, ne jen komentář — `centered(_:in:on:)` si obrazovky bere
    parametrem (`ScreenBounds`), protože `NSScreen` se v testu vyrobit nedá. Doložené je i to, že
    se okno **nerozpůlí mezi monitory**: ořez ho posune celé na tu obrazovku, na které hlavní okno
    převážně leží (podle plochy průniku — `NSRect.null` má nekonečné rozměry, takže „žádný průnik“
    musí dát nulu, jinak by vyhrála obrazovka, na které hostitel není).

- **Obě pomocná okna zůstávají před ostatními okny aplikace, a jedině před nimi** (#243) —
  `AuxiliaryWindowLevel` a `keptInFrontOfApp()`. Vzniklo to z toho, že středění (#164) samo
  vyrobilo horší poruchu: vystředěné okno je menší než hlavní okno, takže se za ním schová
  **beze zbytku** a vypadá jako zavřené — změřeno, hlavní okno 1296×1032 proti nastavení
  900×452 — přitom je pořád otevřené a `⌘,` ho jen znovu vytáhne. Šest věcí, na kterých to stojí:
  - **Hladina je funkce toho, jestli je aplikace vpředu**, ne jednorázové nastavení. `.floating`
    dokud je vpředu, `.normal` jak přestane být. Samo `.floating` je naivní oprava, po které okno
    plave i nad **cizími** aplikacemi — z „v popředí aplikace“ by bylo „v popředí všeho“ —
    a proto je na pád hladiny zpátky **vlastní test**; zelený test jen na `.floating` by o té
    naivní opravě mlčel.
  - **Uvnitř aplikace nerozhoduje, které okno je klíčové.** Bere se aktivace **aplikace**
    (`NSApp.isActive` a jeho notifikace), takže kliknutí do hlavního okna pomocné okno dozadu
    nepošle — to je právě ta porucha, kterou tohle issue opravuje.
  - **Okno se nikdy neschovává, a je to změna proti zadání**, které doporučovalo
    `hidesOnDeactivate`. Skrytí je stav, který se s SwiftUI umí rozejít: při zkoušení se okno
    **třikrát** ocitlo mimo obrazovku, ačkoli scéna dál žila — aktivace aplikace ho nevrátila,
    `⌘,` s ním nepohnulo (pro SwiftUI bylo otevřené) a vrátilo se až dalším přepnutím aplikace.
    To je tatáž porucha o vrstvu vedle. Hladina proti tomu **žádný stav nedrží**: co je zavřené,
    zůstane zavřené, a co je otevřené, je vidět. Cena je, že nad cizí aplikací okno **zůstane na
    obrazovce** (leží pod ní), místo aby zmizelo.
  - **Zavřené okno se nevrací** — není co vracet, nic se neschovává. Změřeno třikrát v řadě
    u nastavení i u novinek: zavřít křížkem a přepnout tam a zpátky nechá aplikaci s hlavním
    oknem. Je to ta polovina zadání, kterou naivní oprava rozbije.
  - **Hladina se nastavuje v `viewDidMoveToWindow`**, ne odloženě přes `DispatchQueue.main.async`
    jako u středění. Změřeno: s odložením se okno nastavení otevřelo na `layer 0` a hladina se
    zvedla teprve při dalším překreslení scény, tedy okno bylo vpředu až po chvíli.
  - **Nastavení hladinu dostává na scéně** (`SettingsScene`), ne u formuláře, takže platí i pro
    stav před preflightem, kde není store a formulář se nemá čím naplnit. Středění zůstává
    u `SettingsView`, protože má vlastní pravidlo (**při vzniku obsahu**), do kterého hladina
    nemá co mluvit. U novinek jsou obě věci nad obsahem scény — je tam jen jeden.

    S tím souvisí, proč zdrojem pravdy **není `controlActiveState`** z prostředí, jak to zkoušela
    první verze: nad obsahem scény zůstalo `.inactive`, i když byla aplikace vpředu a okno klíčové,
    takže se hladina nezvedla vůbec (změřeno — okno na `layer 0` a nové okno hlavní scény ho
    zaklopilo). Hlouběji ve `SettingsView` ta hodnota chodí, ale mechanismus, který funguje jen
    v jednom místě hierarchie, je past.
  - **Změna proti #127**, kde stálo, že se hladina nechává normální a `.floating` je vyzkoušené
    a zamítnuté, protože kliknutí mimo okno ho má odklidit. Odklidit ale znamená zavřít, a to se
    neděje: `willClose` nepřijde nikdy. Zamítnutí tedy stálo na chování, které aplikace neměla.
  - **Fokus hladina nedrží, a držet nejde** — to je změřená hranice, ne opomenutí. Kliknutí do
    hlavního okna z něj udělá klíčové okno, takže pomocnému oknu zešedne titulek se semaforem
    a v seznamu vlevo zbledne modré vybrání; klávesy jdou do hlavního okna. Co se u toho změřilo:
    - **Klíčové okno je v aplikaci právě jedno.** Vyzkoušeno v samostatném pokusu s plovoucím
      utility panelem: po `main.makeKey()` je `panel.isKeyWindow == false`. Vrátit klíč zpátky jde
      (`panel.makeKey()`), takže „neztratit fokus“ neznamená udržet ho, ale **vzít ho zpátky**.
    - **Utility panel s tím nepomůže.** Titulek i semafor mu zešednou úplně stejně jako obyčejnému
      oknu (doloženo screenshotem titulku panelu ve dvou stavech), takže ani „aspoň nevypadat
      deaktivovaně“ tou cestou nejde. `styleMask.insert(.utilityWindow)` na okně, které `NSPanel`
      není (a scény `Settings` i `Window` si svoje `NSWindow` vyrábějí samy), **nedělá vůbec nic** —
      taky změřeno screenshotem.
    - **Brát klíč zpátky se zamítlo.** Šlo by to (pozorovat `didBecomeKeyNotification` cizího okna
      a zavolat `makeKey()` na svém), ale znamená to, že do hlavního okna nejde psát, dokud je
      pomocné okno otevřené — a co je horší, kliknutí do rozepsaného komentáře v hlavním okně by
      poslalo text **do pole v nastavení**. To je zápis do jiného místa, než kam se člověk kouká,
      tedy horší vada než zešedlý titulek.
    - **Po přepnutí aplikace zůstává klíč tam, kde byl.** Změřeno: když bylo klíčové hlavní okno,
      je klíčové i po návratu do aplikace, ačkoli je pomocné okno vidět před ním. `⌘,`
      (resp. položka v menu) klíč vrátí.
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
- **Notifikace mají vlastní záložku, ne sekci v `Obecné`** (#86). `Obecné` je dlouhá záložka
  (zdroje, režim, jazyk, diff, odesílání, tři editory seznamů, běh) a notifikace by v ní byly
  šestý pruh přepínačů, který se hledá scrollováním. Jsou navíc jediná část aplikace, která si
  sahá na **systémové oprávnění**, takže mají o čem mluvit samy za sebe. Nejdřív to sekce byla
  a přesunulo se to na přání při zkoušení.
- **Jednotlivé události se schovají, když je hlavní vypínač vypnutý.** Čtyři zakázané přepínače
  pod vypnutým vypínačem jsou čtyři řádky, které nic neříkají — u tlačítek v okně review je to
  obráceně (zakázané zůstávají a řeknou důvod), ale tam ten důvod není o řádek výš.
- **Pohled na diff má vlastní sekci, ne řádek v `Režimu review`.** S review nesouvisí a je to
  nastavení člověka, ne repa — proto ho nemá ani záložka rep. A z patičky musí být vidět, že
  **přepínač v liště tuhle hodnotu nepřepisuje**: jinak by nastavení vypadalo jako něco, co se
  samo mění.
- **Žádný text u odesílání se nesmí dát přečíst jako „zapnout automatické odesílání“.**
  Přepínač rozhoduje **jen** o tom, jestli se tlačítko `Odeslat review…` vůbec nabídne;
  odesílá pořád člověk potvrzením, ve kterém je vidět celý payload. Patička to proto říká
  výslovně — a je to tatáž úvaha jako u předvyplněného verdiktu v panelu, který je taky jen návrh.
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

Přenesení draftu na nový commit (#69) `AppStore` orchestruje takhle:

- **Snímek kódu se bere při zakládání komentáře, ze načteného diffu** — jedno místo, které ví, že
  vlevo je staré číslo a vpravo nové. Bez diffu zůstane prázdný a revalidace to pak řekne jako
  „nevím“, ne že kotva sedí.
- **Roztažení rozsahu snímek bere znovu.** Mění se oba konce, takže starý snímek by po dalším
  commitu hledal řádek, který v rozsahu už není.
- **Přenést se dá jen zastaralý draft a jen s načteným diffem** (`canTransferDraft`). Bez něj by se
  rozhodovalo naslepo.
- **Draft, ze kterého přenesením nic nezůstane, se maže** — „draft existuje“ musí znamenat „je co
  poslat“, tatáž zásada jako u prázdného komentáře.
- **Přenesený draft se vrací volajícímu**, i když v mapě nezůstal: potvrzení odeslání si z něj dělá
  nový snímek.

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
- **Lišta nad diffem je `DiffToolbar`** (#219), ne kus `DiffView`. Rostla po kusech — pohled
  vedle sebe (#98), procházení (#187), strom (#197), šířka (#188) — a nikdy se neposadila podle
  návrhu jako celek: sedm prvků, ve kterých se přepínač pohledu ztrácel mezi dvěma checkboxy,
  a v užším okně se nevešla. Pět věcí, které se u ní nemají rozbít:
  - **Vlevo pohled a procházení, vpravo `Rozbalit vše`.** Procházení je jediná věc v liště,
    která se používá při každém review; zbytek se nastaví a nechá být.
  - **Přepínač pohledu je segment s popisky** (`DiffLayoutPicker`), ne `Picker(.segmented)`.
    Dvě ikony bez popisků neřeknou, co která dělá — pozná se to až najetím myší, tedy až po tom,
    co si člověk vybral, na co najet. Tentýž důvod jako u segmentů panelu (#182).
  - **Procházení je jeden prvek v rámečku** (`FindingNavigationView`, `.findnav`): puntík,
    `1 z 3 nálezů`, šipky a `jen blokující` uvnitř. Do #219 to bylo pět samostatných věcí vedle
    sebe, takže nebylo poznat, že patří k sobě — a `jen blokující` vypadalo jako přepínač celé
    lišty, ne jako zúžení téhle jedné cesty.
  - **Přepínače sloupců v liště nejsou**, i když je návrh kreslí (`◧ Strom ⌘1`, `◨ Nálezy ⌘2`).
    Strom i panel se skládají **u sebe** — tlačítkem v hlavičce sloupce a proužkem, kterým se zase
    otevřou — takže v liště by to byly třetí dveře k témuž a v úzkém okně by se o místo praly
    s procházením. Zkratky zůstávají a jsou napsané v nápovědě u těch tlačítek, tedy tam, kde se
    na sloupec sahá; `⌘1` proto **visí mimo lištu** (nemá na čem viset), stejně jako `⌘2`
    v detailu PR.
  - **Souhrn `1 soubor · +4 −2` v liště není.** Počet souborů je v hlavičce stromu vedle a rozsah
    změny v řadě záložek nad ním, takže lišta o něj přišla, aniž by ten údaj z okna zmizel.
    Varování (nepřečtené řádky, nevešlá vlákna, znaky na stranu) zůstávají — jsou vidět jen
    tehdy, když nesedí, a to je celý jejich smysl.
- **Kapsle s nálezy v hlavičce souboru počítá `Policy.fileFindings(in:)`** (#219), hlavička z čísel
  jen skládá větu. Počítá se **po místech, ne po nálezech** — tři reviewery shodnutí na témž řádku
  jsou jedna věc k rozhodnutí — a odmítnuté (#113) se vynechají. **Blokující má vlastní slovo**
  (`1 blokuje`), ne jen červenou: kapsle je tvarem k nerozeznání od odznaku změny vedle ní.
  Že rozhodování nesmí zůstat na view, není estetika: statická metoda na `View` typu je
  `@MainActor` a v testu mimo hlavní vlákno **padá až za běhu** — viz
  [`docs/testovani.md`](testovani.md).
- **Hlavička souboru nese celou cestu** (`FilePathText`, #219): složka v `--ink-3`, jméno tučně.
  Do #219 byla cesta jedním řezem a ořezávala se jako celek, takže u dvou souborů téhož jména
  nešlo poznat, který je který. Jméno má proto **přednost v rozvržení** a ustupuje složka —
  ořezaná zepředu, protože význam nese její poslední část. Strom vedle na to odpovídat nemá:
  dá se složit a v pohledu vedle sebe se skládá sám (#188).
- **Počty `+X −Y` skládá `DiffCounts.text`** (#156) a barvu si berou z `DiffLineView.signColor(of:)`,
  tedy odtud, odkud ji má znak změny v samotném řádku. Míst, kde se ty počty píšou, jsou **dvě**
  a nesousedí spolu: řada záložek PR a hlavička souboru v diffu. Kdyby si to každé skládalo samo,
  zůstalo by po první změně jedno z nich šedé — chytila to vlastní revize diffu. Do #219 byla
  místa tři (souhrn nad diffem a strom souborů); souhrn z lišty odešel a ve stromu se počty
  nekreslí od #197.
  **Ne `background(of:)`**: to je
  dvanáctiprocentní výplň a jako barva písma je nečitelná; sytá barva znaku je naopak text, který
  v diffu stojí od #18. Čitelnost v obou režimech je ověřená offscreen renderem, ne odhadem.
  Červená kapsle s počtem nálezů se s tím neplete: má jiný tvar i podklad, a zelené `+X` za ní
  vstupuje jako předěl.
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
  s rámečky nehýbe — **ale docela klidné to není**: líný seznam si obsah průběžně přeměřuje, takže
  se poloha bloků v tom prostoru při scrollování posouvá a rámečky se hlásí znovu (změřeno u #252,
  kde `DiffRowFrames.note` v sampleu ležel pod rozvržením líného seznamu).
- **Hlásí se naráz za celý blok** (#252), ne po jednom rámečku. Úklid zastaralých záznamů je
  lineární v jejich počtu, takže po řádcích to bylo kvadratické — 120 ploch bloku dvojic proti
  tisícům záznamů velkého souboru je stovky tisíc porovnání na jeden blok, který vjede do okna
  (změřeno **24,1 ms → 0,25 ms**; do #274 tu stálo 22,6 → 1,40 ms, protože měřidlo počítalo
  i naplnění krabice). Pořadí je **napřed úklid, potom zápis**: obráceně by blok vyklidil
  sám sebe, protože leží celý ve své ploše. Prázdná plocha se ignoruje — blok, který se ještě
  nerozložil, hlásí nulový rámeček a vyklidil by cizí záznamy na souřadnici nula.
- **V krabici je nejvýš jeden diff** (#274), a hlídá to klíč, který každé hlášení nese s sebou
  (`RangeDragActions.FrameBox.subject` — `owner/repo#číslo`, u diffu commitu jeho sha; krabice a klíč
  jsou **jedna hodnota**, aby se nedalo předat jedno bez druhého a zahazování tiše vypnout). Je to
  potřeba proto,
  že `@State` detailu **přetéká mezi pull requesty**: jeden `DiffView` obslouží všechny otevřené
  záložky, takže se v krabici vrstvily plochy každého PR, na který se člověk podíval. Vyklizení
  plochy je sundá jedině tam, kam nový blok dosáhl — u krátkého diffu po dlouhém tedy zbyde ležet
  všechno pod ním. Zápis je lineární v počtu záznamů, takže každá prohlédnutá záložka ho zdražovala:
  **0,25 ms** na blok s jedním PR v krabici, **0,49 ms** se dvěma, **0,93 ms** se čtyřmi.

  **Zahazuje se z hlášení, ne zvenčí**, a na tom to celé stojí: vyprázdnit krabici při přepnutí
  záložky by znamenalo, že bloky, které stojí a geometrii nemění, už nic nenahlásí — a tažení nemá
  co najít (je to ta chyba z #110, popsaná o dva odstavce výš). Takhle je v krabici hned s prvním
  hlášením nového diffu jeho vlastní plocha a nic cizího.

  **V okně se to na projíždění nepozná** (změřeno, viz [`testovani.md`](testovani.md), *Kolik stojí
  otevřená záložka*): zápis ploch je 0,4 % vzorků hlavního vlákna, takže rozdíl mezi jednou a čtyřmi
  záložkami leží pod rozptylem měření. Co se tím spraví, je růst — a to, že se v krabici přestaly
  vrstvit plochy diffu, který na obrazovce není.
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
- **A uložení běhu taky** (#308). `.finished` proto nese celý `ReviewRun` a `drain` ho hned za
  zápisem konce osy uloží (`store(_:for:saving:)`). Do #308 se ukládalo mimo proud, takže si
  čtení osy a její zápis závodily o `MainActor` a **do souboru šla osa, kterou zbyl závod**:
  celá, zkrácená na `[ve frontě]`, nebo vůbec žádná — a `dropped` u toho zůstalo nulové, tedy
  o zkrácení mlčelo. Změřeno na `AppStoreProgressTests`: nad volným strojem vycházelo `[ve
  frontě]`, se souběžnou suitou nic. Zamítnutá varianta bylo uložit všechny běhy až po
  `await drained` — to ruší pravidlo „ukládá se po každém doběhlém skillu“ (#97), takže by
  zavření aplikace uprostřed sady zahodilo i to, co doběhlo.
- **Osa se drží i po doběhnutí** — právě tehdy se k ní člověk vrací. Nový běh ji vynuluje;
  běžící review si ji přes tik podrží.
- **Tik pustí živou kopii osy, ne osu** (#308). PR mimo seznam vypadne z `reviewTimelines`, ale
  `timelines(for:)` pak odpovídá z uloženého záznamu — a ten se schválně neuklízí (#137 z něj
  pozná re-review od novinky), takže je to tatáž odpověď jako po restartu (#203). Zahodit osu
  doopravdy by znamenalo zahodit i záznam, tedy rozbít #137. Do #308 tady stálo, že se osa
  „ztratí“, a test to tvrdil taky — jenže netvrdil, což byl jediný důvod, proč padal.
- **Pozdní událost zahozeného běhu nastat nemůže, a je to strukturou, ne kontrolou** (#308):
  proud se dojíždí uvnitř `review()` (`reporter.finish()` + `await drained`), takže po konci
  běhu už žádná událost nepřijde, a dokud běh žije, `forget(whatIsNotIn:)` jeho osu z úklidu
  vyjímá (`reviewTasks[$0.key] != nil`). `record(_:of:for:in:)` proto **žádnou bránu nemá** a mít
  ji nemá: je to obyčejný zapisovatel, který používá i měření ceny události (#350) — brána „jen
  když PR běží“ by harnessu neuložila nic a měřila by prázdno.

Taby PR (#72) drží `AppStore` v `detailTabs` (per PR) a platí u nich:

- **Volba tabu je ve store, ne ve view.** `PullRequestDetailView` si SwiftUI mezi pull requesty
  ponechá (stejná pozice ve stromu), takže `@State` by přetekl z jednoho PR na druhý — tatáž
  past jako u sbalených souborů a příznaku „připravuji“.
- **Drží se odchylka od výchozího stavu**, ne volba u každého PR. Výchozí je `Přehled`
  (`PullRequestTab.standard`, **změna proti zadání #72** — popis a diskuze se čte dřív než kód
  a stejně to má GitHub), takže se `filesChanged` z mapy maže a úklid podle seznamu PR ji
  nenechá růst.
- **Volba se nezarovnává na data** (#306). Do #306 ji `detailTab(for:)` prohánělo
  `Policy.tabs(hasChecks:)`, protože `Kontroly` u PR bez CI v pruhu nebyly a volba na ně nesměla
  ukazovat. Se trvale přítomnou záložkou to ztratilo předmět — a s ním odpadl i vedlejší účinek,
  kvůli kterému se volba schválně **nemazala**: z tabu `Kontroly` se vypadávalo při **každém**
  příchodu na PR, dokud checky nedorazily (tahají se s detailem, takže chvíli nejsou). Zůstává
  z toho pravidlo: volba je odpověď na „kam se koukám“ a nesmí se měnit tím, co dorazilo ze sítě.
- **Panel je ve třech tabech ze sedmi** — `Přehled`, `Změněné soubory`, `Konverzace` (#294, #316,
  `PullRequestTab.showsReviewPanel`). Nálezy bez místa v kódu i moje rozdělané review se vážou
  k celému PR, takže se za přepnutí tabu schovat nesmí; panel ale odpovídá na „co k tomu, co právě
  čtu, nahlásily reviewery“, a to má smysl jen tam, kde se vedle něj čte **něco jiného**.
  V `Kontrolách`, `Nálezech` a `Průběhu` je vedle něj buď duplikát týchž dat, nebo obsah, který
  šířku potřebuje (konec logu spadlého checku, #214) — schovává se proto **celý, i složený
  proužek**. **`Commity` (#316) mají k tomu důvod navíc, a tvrdší než šířka**: nálezy jsou
  klíčované `headSha` (tvrdá podmínka č. 5), takže by panel u staršího commitu ukazoval nálezy
  k **jinému kódu**. Není to duplikát, je to tvrzení, které by neplatilo. Tři věci, které z toho
  platí:
  - **Šířka se nepřepočítává.** `GeometryReader` v detailu měří to, co po panelu zbylo, takže se
    tab roztáhne sám; vlastní odečítání šířky panelu je zrovna ta chyba, ze které vzniklo #291.
  - **Uložený stav panelu se přepnutím tabu nemění** — složení ani vybraný segment. Skrytí je věc
    *pohledu*, takže kdo si panel vytáhl, najde ho po návratu tak, jak ho nechal.
  - **`⌘2` a položka v ⌘K jsou tam vypnuté.** Klávesa by potichu přestavěla tab, do kterého se
    člověk vrátí, a v okně by po tom nezůstala stopa. Paleta proto rozlišuje `nil` (panel v tabu
    není) od `false` (je, jen složený).

  **Změna proti #242**, kde panel byl ve všech tabech s odůvodněním, že smyčka nález → `Převzít` →
  text v mém review se musí stát naráz. Ta smyčka platí dál, jen jí přibyl třetí krok, viz níž.
- **Složení panelu a jeho tab drží store, ne view** (#242): `isReviewPanelExpanded`
  a `reviewPanelTab`, globálně (ne per PR) jako `diffLayout`. Není to úklid, je to podmínka —
  poznámka do těla review přidaná z diffu spadne do panelu, takže se panel musí umět
  **rozložit sám** (`revealDraft(in:)`), a dokud to bydlelo v `@State` detailu, nešlo to
  otestovat. Tudy chodí `appendDraftNote` i `adoptFinding` s cílem `.body`; **řádkový komentář
  panel nerozloží** — ten je vidět hned pod řádkem v diffu.

  Od #294 má `revealDraft(in:)` **třetí krok**: z tabu, ve kterém panel není, si **přepne tab**
  (na `PullRequestTab.standard`). Bez něj by `Převzít` v tabu `Nálezy` neudělalo nic viditelného,
  což je tatáž tichá ztráta rozepsané věty, jakou #242 řešil u složeného panelu — jen o stupeň
  horší, protože složený panel je aspoň vidět jako proužek. Z tabu, kde panel je, se
  **nepřepíná nikam**: převzetí nálezu v diffu nesmí vyhodit člověka z kódu, který čte.

  Od #333 si `revealDraft(in:)` **tab přeloží** (`Policy.reviewPanelTab(.draft, for:)`): na vlastním
  PR segment `Moje review` neexistuje, takže by se přepínalo na něco, co se nekreslí — a rozdělané
  review z dřívějška bydlí v tabu `Zadání`, tedy tam, kam ten odkaz vede. Zkratka `⌘⇧P` má vlastní
  cestu (`revealAgentPrompt(in:)`) se stejnými třemi kroky.
- **Na vlastním PR panel nesbírá verdikt, ale zadání pro agenta** (#333). Rozhoduje o tom
  `ownership(of pr:)`, tedy autor PR proti `ownLogins` — ne `isOwnPullRequest(_:)`, který se ptá
  načtené konverzace, protože ta odpověď musí platit **od první obtažené obrazovky**. Tři věci,
  na kterých to stojí:
  - **`APPROVE` ani `REQUEST_CHANGES` na vlastní PR GitHub nepustí** (422, změřeno u #62), takže
    verdikt a `Odeslat` **zmizí celé**, ne zašedlé: zakázané tlačítko svádí na něj kliknout
    a přečíst si chybu od GitHubu.
  - **Draft tam nesmí ani vzniknout.** Zakládá se čtyřmi cestami (`adoptFinding`, `appendDraftNote`,
    `addDraftComment`, `dragCommentRange`) a všechny vedou přes diff, ne přes panel — zavírá je
    jedna brána, `canComposeDraft(for:)`, se dvěma volajícími v `PullRequestDetailView`. Tlačítka
    se tím **nekreslí**, ne že by nic nedělala. `pullRequestsWithDraft` (sekce `Rozdělaná`) tím
    u vlastních PR zůstane prázdná sama, bez druhé podmínky jinde.
  - **Existující draft se nezahazuje.** Bubliny v diffu ho kreslí z `draft.comments` (ne z brány),
    takže se v nich dá pořád číst i mazat, a panel `Zadání` k němu nabízí `Zahodit review`. Tiše
    zmizelá data jsou horší než data, která nejdou odeslat.

  A dvě věci k **cestě do panelu**, protože vstupy jsou tři a chovají se různě:

  - **`Prompt →` v řádku (#331) jen naviguje, neskládá text** — `openAgentPrompt(in:)` = `openTab`
    + `revealAgentPrompt`. Otevřít PR je **součást** akce: `Conversation` se nepersistuje a tahá se
    při zobrazení, takže sazba přímo ze seznamu by dala zadání bez vláken, komentářů pod PR
    a souhrnů review — a jen by o té mezeře poctivě napsala. Tlačítko proto **není zakázané**;
    `hasAgentPromptItems(for:)` hlídá zkratku `⌘⇧P` a `Sestavit prompt →`, tedy sazbu. V seznamu by
    měřilo stav *před* otevřením PR a schovalo by cestu k panelu zrovna u PR, jehož materiál je
    v diskuzi.
  - **Sheet má jen jednoho presentera** (`PullRequestDetailView`), a to je druhý důvod navigace: dva
    `.sheet(item:)` nad jedním `AgentPrompt`em by znamenaly dvě místa, ve kterých se to okno kreslí,
    a hlavně dvě různá zadání složená z různě úplného stavu.
- **Pohled vedle sebe složí postranní sloupce** (#188). Řádek se v něm dělí na dvě strany, takže
  na 14" nezbude ani 100 znaků ani se složenými sloupci; pod sebou se zase rozbalí. Tři pravidla:
  - **`task(id: layout)`, ne `onChange`.** Pohled se drží napříč pull requesty a výchozí je
    z nastavení, takže s `onChange` by se na PR otevřeném rovnou ve splitu nesložilo nic — změna
    nepřišla. Ověřeno na běžící aplikaci: ukazatel skočil ze 67 na 78 znaků, jak se strom složil.
  - **Ruční `⌘1`/`⌘2` automatiku přebijí** — a jednoduše tím, že platí až do další změny pohledu.
    Žádný další příznak; stav sloupce je jediná pravda.
  - **Kolik znaků zbývá, se měří, ne bere z tabulky.** Tabulka v zadání #188 platí pro jeden
    displej a jedno nastavení; číslo v liště platí pro okno, které mám otevřené. Ukazuje se
    **jen pod slibem** (120 znaků z `CLAUDE.md`) — nad ním je to údaj, který nikoho nezajímá.
- **Checky z GitHub Actions mají vlastní tab `Kontroly`** (#215; do #215 to byl blok
  v `Přehledu` — #209) — druhou půlku otázky „dá se to mergnout“; tu první (nálezy) okno umělo,
  takže se nad zeleným review stejně chodilo do prohlížeče. Čtyři pravidla:
  - **Nejhorší stav vyhrává, ne většina.** Dvanáct zelených a jeden červený je červený stav.
    Platí to pro chip v hlavičce i pro **odznak tabu** (`Policy.checksBadge`).
  - **Tři stavy, ne dva**, a `skipped` je vlastní. Běžící check není prošlý ani spadlý a
    přeskočený není úspěch — jinak by hlavička svítila zeleně nad přeskočeným testem. Neznámý
    kbelík se bere jako běžící: je to jediný stav, který o výsledku netvrdí nic.
  - **Přeskočené se sbalí za číslo.** Na skutečném PR jich bývá většina — změřeno na
    `keboola/platform-libraries#557`: 28 checků, 22 přeskočených — a rozepsané by utopily ten
    jeden, na kterém záleží. Ze stejného důvodu jdou spadlé nahoru.
  - **Log zůstává na GitHubu.** Odkaz je jen u toho, co se nepovedlo; stahovat megabajty kvůli
    jednomu přečtení nedává smysl a čtení logu není doména review.

  Tahá se **s detailem PR**, ne pollingem přes všechna (tatáž N+1 past), a `fetchChecks` je
  **čtení** — restart workflow do aplikace nepatří (tvrdá podmínka č. 1).

  **Co k tomu přidalo stěhování do tabu** (#215):
  - **V `Přehledu` nezbylo nic.** Zadání #215 tam chtělo nechat **souhrn** (hlavičku s poměrem
    a jeden řádek s nejhorším checkem) a chvíli tam byl; při zkoušení se ale ukázalo, že je to
    **třetí místo o téže věci** — tab odpovídá na celou otázku a „je to zelené“ nese chip
    v hlavičce. Souhrn proto odešel celý, i s tou hlavičkou. `Přehled` tak o checcích nemluví
    vůbec.
  - **Chip v hlavičce zůstává** a je od #215 **jediným** místem o checcích mimo tab: „je to
    zelené“ se musí dát přečíst i při čtení diffu, tedy z hlavičky, která je vidět ve všech
    tabech. Je to rozhodnutí z #209 a odebrání souhrnu se ho netýká.
  - **Tab se kreslí vždycky** (#306, otáčí #215). Do #306 se u PR bez CI nekreslil
    (`Policy.tabs(hasChecks:)`) s odůvodněním, že prázdný tab s nadpisem by o něm tvrdil, že se
    něco nepovedlo. Cena za to byla horší než ten prázdný tab: pruh záložek **problikl při každém
    otevření PR** — pět záložek, pak šest — protože checky se tahají s detailem, a obsah se pod tím
    přeskládal. Prázdný tab s **vysvětlující hláškou** ten původní argument ruší: neříká „něco se
    nepovedlo“, ale „není co ověřovat, a není to porucha“. Co v tabu je, rozhoduje
    `Policy.checksTab(checks:failure:)` — čtyři stavy, viz níž.
  - **Uložená volba se nezarovnává** (`AppStore.detailTab(for:)`, #306). Zarovnání existovalo jen
    kvůli mizející záložce a mělo vedlejší účinek, se kterým se u #215 smířilo: z tabu `Kontroly`
    se vypadávalo při každém příchodu na PR, dokud checky nedorazily. Podrobnosti v sekci
    `AppStore` výš.
  - **Dělič v pruhu se počítá z vlastnosti tabu, ne z indexu** (`isReviewerOutput`). `Kontroly`
    sedí nalevo doprostřed — a od #316 i `Commity`, které tu předpověď vyzkoušely doslova. Do #306
    se index navíc měnil **podle dat** (záložka někdy nebyla); to už neplatí, ale první důvod stačí
    — vlastnost přežije i sedmou záložku vloženou doprostřed.
  - **Odznak má tři podoby, ne jednu**: spadlé → červená kapsle s počtem (blokuje merge, takže
    tichá kapsle by se čtla jako údaj o množství), běžící → puntík jako u `Průběhu` („běží“ je
    stav, ne množství), zelené i přeskočené → **nic**. Zelené CI je výchozí stav a číslo u něj
    by byl šum, kvůli kterému by se přestaly čít i ty ostatní dva.
  - **Texty a barvy checků jsou na jednom místě** (`ChecksText`) — tab i chip. Do #215 měl každý
    kus okna vlastní kopii a **už tehdy se rozešly**: blok kreslil `.green`/`.red` ze SwiftUI, chip
    `Palette.ok`/`Palette.crit` z palety návrhu, takže dvě zelené v jednom okně znamenaly jednu věc.

    Poměr se skládá **po částech** (`ChecksText.parts`) kvůli chipu, který ukazuje jen tu první,
    tedy nejhorší stav. Příznak `isFailure` u částí **zmizel s odebraným souhrnem**: existoval
    jen proto, aby `Přehled` obarvil spadlou část, a bez souhrnu ho nikdo nečetl.
  - **Selhané načtení checků má vlastní stav** (`checkFailures`), ne prázdné pole. Do #215 to bylo
    `(try? await gateway.fetchChecks(id:)) ?? []` a dalo se to obhájit tím, že checky jsou doplněk
    k PR; od #215 je ale prázdno **tvrzení** („tenhle PR nemá CI“), takže by z chyby sítě tiše vyšlo
    zrovna ono. `GhGateway.fetchChecks` ten rozdíl drží schválně (prázdný výstup s nulovým kódem =
    bez CI, nenulový s prázdným výstupem = chyba), takže by ho zahazoval až store. Dvě pravidla
    k tomu: po selhání se **stará sada nechává být** (zastaralý seznam s větou nad ním je lepší než
    plocha s chybou místo checků, které se před chvílí načetly) a **zrušení se nezapisuje** — `.task`
    se ruší při přepnutí PR, což není porucha.
  - **Tab má čtyři stavy, ne dva** (`Policy.checksTab(checks:failure:)`, #306). Trvale přítomný tab
    musí mít odpověď na každý stav dat, a šest kombinací vstupů (`checks` nenačtené / prázdné /
    neprázdné krát `failure` je / není) dává čtvero — v tabu je z toho **pět podob**, protože
    `list` se kreslí se zastaralostí i bez ní:

    | Stav | Kdy | Co je v tabu |
    |---|---|---|
    | `loading` | `checks` nenačtené, bez poruchy | `Načítám kontroly…` — **o CI netvrdí nic** |
    | `empty` | `checks == []` | klidný prázdný stav: `Tenhle PR nemá kontroly` a věta, že to není porucha |
    | `list(_, failure: nil)` | neprázdné `checks` | seznam checků, jak ho zavedlo #215 |
    | `list(_, failure: reason)` | neprázdné `checks` + porucha | seznam a **nad `ScrollView`em** okrová věta, že je to poslední známý stav |
    | `failed(reason)` | porucha a není co ukázat | červený prázdný stav s textem od `gh` a `Zkusit znovu` |

    Dvě rozhodnutí o pořadí: **neprázdný seznam přebíjí poruchu** (zastaralá sada je lepší než plocha
    s chybou) a **porucha přebíjí obě prázdna**, tedy i `checks == []` — prázdno je z předchozího
    načtení, kdežto porucha je to, co víme teď, takže z chyby sítě nikdy nevyjde „nemá CI“.

    **Věta o poruše je v tabu, ne v hlavičce PR** (#306, mění #215). Do #306 stála v hlavičce
    a jediný důvod byl ten, že tab mizel: „bez ní je zmizelý tab k nerozeznání od PR bez CI“. Jakmile
    tab nemizí, musí poruchu umět říct sám — jinak by nad ní tvrdil „nemá CI“ — a tím se z věty
    v hlavičce stává druhé místo o téže věci. Je to tentýž vzor, jaký má diff i konverzace: co se
    nepovedlo načíst, hlásí ten tab, ve kterém to mělo být vidět. Cena je zapsaná: při čtení diffu
    už není z hlavičky vidět, že se checky nenačetly — hlavička o nich mluví jedině chipem, a ten
    (jako odznak tabu) mlčí, dokud není seznam.
  - **Selhaný pokus se dá zopakovat** (#306). `Zkusit znovu` v tabu volá `AppStore.loadChecks(for:)`
    přímo, protože `loadDetail` má cache podle `updatedAt` — po chybě sítě by se checky samy
    nedotáhly až do dalšího commitu. Tatáž cesta jako u diffu a konverzace.
  - **Checky se tahají i tehdy, když detail spadl** (#306). Do #306 bylo `loadChecks` uvnitř `do`
    bloku po úspěšném `fetchDetail`, což nevadilo, dokud se tab u nenačtených checků nekreslil. Teď
    by v něm nad spadlým detailem svítilo `Načítám kontroly…` navždycky, a to je text, který tvrdí
    víc, než data unesou. `gh pr checks` na `gh pr view` nestojí, takže není důvod jedno vázat na
    druhé; zrušení (`CancellationError`) je proti tomu odchod z obrazovky a checky se po něm netahají.

  **Detail jednoho checku** (#214) — anotace a konec logu, `AppStore+Checks` a `CheckDetailView`:
  - **Až na kliknutí a jen na ten jeden check.** Log celého běhu je log všech jeho jobů (u změřeného
    PR 23), takže tahat ho pro seznam je N+1 past o tři řády dražší než u detailu PR. Rozbalený je
    **jeden na PR** — dvě sady megabajtů v paměti nemají důvod.
  - **Nabídka detailu visí na `jobID`, ne na `outcome`.** Číslo se rozborem vytáhne z `link`u
    (`…/runs/<runId>/job/<jobId>`) a **totéž číslo funguje jako check-run ID** pro anotace, takže se
    pro něj nechodí zvlášť. Že ho odkaz mít nemusí, je ověřené (CodeQL má `/runs/<id>` bez `/job/`,
    bors odkazuje mimo GitHub) — u takového checku se detail nenabízí, protože tlačítko, které
    skončí chybou, je horší než žádné. Pozor na past: `…/runs/<runId>` končí taky číslem, ale je to
    **běh**, ne job.
  - **Nad 10 MB se log nestahuje vůbec** a na jeho místě je věta s konkrétní velikostí. Rozhoduje
    `Content-Length` z `HEAD`, který je levný a **konstantně** levný (~1,2 s u 33 kB i u 8,78 MB),
    takže věta není odhad. Cena rozhodnutí: nad stropem odpadá i **konec** logu — obejít to částečným
    stažením nejde, `Range` přes `gh` se na redirect do Azure blobu nepřenese a vrátí celých 8,78 MB
    (změřeno).
  - **`HEAD` je ochrana, ne podmínka** (#292, mění #214). Když velikost **nepřijde**, log se přesto
    stáhne a strop se uplatní na tom, co doopravdy přišlo (`raw.utf8.count`). Do #292 se v tom
    případě nestahovalo — a protože rozbor hlaviček velikost nikdy nevydal, byl konec logu vypnutý
    u **každého** checku, ne v krajním případě. Pravidlo z toho: co je jen ochrana proti drahé
    operaci, nesmí být tím, na čem stojí, jestli se ta operace vůbec pokusí.

    Nezjištěná velikost je proto `Int?`, ne chyba — a **selhání `HEAD`u se nepropisuje do stavu**.
    Není to zapomenutá chyba: hned za ním jde stažení, tedy ta operace, o kterou uživateli jde.
    Povede-li se, není o čem informovat; nepovede-li se, dostane **chybu stažení**, která nese kód
    i výstup `gh` — tedy víc, než by řekla chyba dotazu na velikost.
  - **Stropy jsou 10 MB a 6 000 řádků, a obojí je změřené** (#292 a #303; do té doby 2 MB a 300,
    pak 4 000 řádků). Rozhodly dvě věci, které #214 neměřilo:

    | Co | 2 MB | 8,78 MB (největší log na našich repech) |
    |---|---|---|
    | otevření sheetu (`setAttributedString` + kresba) | 3,92 ms | **6,57 ms** |
    | projíždění, medián snímku | 0,00 ms | **0,00 ms** |
    | projíždění, nejhorší snímek | 0,01 ms | **0,01 ms** |
    | *vynucená* sazba celého dokumentu | 145,84 ms | 631,91 ms |

    **Poslední řádek té tabulky je to, co #214 měřilo** (`ensureLayout` + `usedRect`) — a je to
    jediná věc, kterou aplikace nedělá: `SelectableCodeView` text jen předá a TextKit sází **líně po
    viewportu**. Odtud tehdy vyšel strop o řád nižší, než je potřeba. Poučení, které přežije tenhle
    strop: **měřit se musí ta cesta, kterou kód doopravdy jde.**

    Strop tedy nedrží kreslení, ale **stahování**: 8,78 MB stahuje `gh` ve třech měřeních za sebou
    **5,75 / 27,44 / 10,67 s** (síť, ne CPU) a celý text zůstává v paměti okna. Proto se dokud se
    stahuje, píše velikost do hlášky (`Policy.logDownloadNotice`) — mlčící spinner je po půl minutě
    k nerozeznání od zamrznutí — a proto **sbalení checku `gh` zabije** (změřeno: procesů 0 → 1 → 0).
  - **Příprava textu běží mimo hlavní vlákno** (#292). `Policy.logTail` na 8,78MB logu stojí
    **814 ms** (ANSI 198 ms, timestampy 372 ms, zbytek dělení a slepení řádků) a `AppStore` je
    `@MainActor`, takže by okno tu dobu stálo. Je to čistá funkce nad `String`em, takže `Task.detached`
    nic nedrží; zrušení se po návratu kontroluje jako všude jinde. Cena **nezávisí na počtu řádků
    ocasu** (300 i 25 000 řádků → 814 ms), protože rozhoduje velikost vstupu, ne výřezu.
  - **Log se ořezává od konce a řekne se, kolik se nevešlo** (`LogTail`) — tiše zkrácený log tvrdí,
    že job začal uprostřed. Ořez je věc **zobrazení, ne úspory stahování**: API vrací celý log
    jedním requestem, takže celý text zůstává pro `Ukázat celý log`.

    **Mez ocasu se proto poměřuje skutečnými logy, ne odhadem** (#303). Devět změřených logů z našich
    repů (`keboola/job-queue-daemon#858`, `keboola/sandboxes-service#650` a největší, jaký na repech
    je): 2 / 1 515 / 2 174 / 5 899 / 5 920 / 5 933 / 16 013 / 16 270 / 25 533 řádků. Z toho plynou dvě
    věci naráz: `Tests` joby sedí v pásmu **5 899–5 933**, takže se se 6 000 ukážou **celé** (se 4 000
    se ořezávaly), a nad mezí zůstávají **tři** největší, takže `Ukázat celý log` i hlavička „starších
    N řádků se nevešlo“ mají u nich co dodat. Kdyby mez přelezla i je, sheet a okýnko by ukazovaly
    totéž — a to je ta chvíle, kdy se mez zvedat nemá.
  - **Konec logu kreslí `LogTailTextView` (`NSTextView`), ne SwiftUI `Text`** (#292) — a je to to
    jediné, co dovoluje ukázat tisíce řádků:

    | Řádků konce logu | SwiftUI `Text` se `.fixedSize()` | `NSTextView` |
    |---|---|---|
    | 300 | 121,75 ms | **2,58 ms** |
    | 2 000 | 6 392,79 ms | **2,02 ms** |
    | 6 000 (dnešní `logTailLines`) | 57 554,33 ms | **5,45 ms** |
    | 10 000 | 202 533,12 ms | **14,34 ms** |

    Dvě a půl minuty na deseti tisících řádcích není opomenutí, které by šlo doladit: `Text` musí znát
    velikost celku dopředu (a u řádků o 2 258 znacích je ta velikost 13 930 bodů na šířku), kdežto
    TextKit sází líně po viewportu. Odtud plyne i to, co v tom view **zmizelo**: dvouosý `ScrollView`,
    `fixedSize()` a dolní mez šířky z `availableWidth` (#220) — zarovnání doleva ani scrollování už
    není co vyjednávat.

    Dvě věci, které to view musí dělat a z kódu nejsou zjevné. **Otevírá se na konci logu**
    (vodorovně na nule): to, kvůli čemu se log otevírá, je na posledních řádcích a se šesti tisíci
    řádků je začátek ocasu dvě stě obrazovek daleko; skok na konec dokumentu přitom sám zůstane
    u konce nejdelšího řádku, tedy uprostřed slova. A **text se přepisuje jen při změně**
    (`Coordinator`), protože přepsání zahodí výběr i polohu scrollu.

    **Skok se dělá z `layout()`, ne z `DispatchQueue.main.async` — a do #303 se v aplikaci nedělal
    vůbec.** `LogTailTextView` vzniká teprve ve chvíli, kdy log dorazí, takže při `updateNSView` mu
    SwiftUI ještě nedalo výšku: `scrollToEndOfDocument` do nulového `clipView`u dokument nasází
    (výška vyjde přesně), ale **posun zahodí** a okýnko zůstane na začátku ocasu. Změřeno vedle sebe,
    obě cesty: s framem předem `origin.y = 71 680`, s framem až po skoku `0`. Proto má okýnko vlastní
    `LogTailScrollView`, který hlásí rozložení, a `Coordinator` nese **nevyřízenou žádost o skok**.

    Žádost se přitom zahodí **teprve tehdy, když je konec doopravdy vidět**: když se vodorovný
    scroller objeví až po skoku, viewport se o jeho body zmenší a okýnko zůstane o řádek nad koncem.
    Chyceno plným během testů, kdežto samostatně to vycházelo — což se do #343 čtlo jako zátěž;
    **byla to ale pořadová věc, ne časová**, viz odstavec níž.

    **Ta pojistka se ale v testech umí spustit z důvodu, který v aplikaci neexistuje** (#343), a stálo
    to jedno vyšetřování, tak ať je zapsané, na co se u toho koukat. `NSScroller.preferredScrollerStyle`
    je **po startu procesu chvíli `overlay`** a teprve za pár kol smyčky se doresolvuje na `legacy` —
    a legacy scroller místo doopravdy zabírá. Když ta změna přijde *až po* dosazení cíle, viewport se
    zmenší (změřeno `clip.h` **441 → 424**, tedy **17 bodů**), `origin.y` zůstane a okýnko je o řádku
    nad koncem (`maxY` 84 006 → 83 989 proti poslednímu řádku na 84 002) — a **nikdo to nepřerovná**,
    protože další `layout()` přijít nemusí.

    Těch 17 bodů si u #343 nesedělo s rezervou ve `height` (13) a **zůstal z toho zapsaný rozpor**,
    který #347 vyřešilo: měření bylo správné, rezerva ne — viz odrážka o rezervě níž.

    V aplikaci je to nedosažitelné: styl scrollerů je usazený dávno předtím, než se dá otevřít detail
    checku. **Je to tedy vlastnost harnessu**, a proto se to opravilo v testu (nechat styl usadit dřív,
    než se okýnko postaví), ne tady — podrobnosti i zamítnuté varianty v
    [`testovani.md`](testovani.md). Kdo sem přijde s tím, že se okýnko otevírá o řádek vedle, ať
    napřed změří `preferredScrollerStyle` v prvních kolech smyčky.

    Cena, ať je zapsaná: skok **vynutí sazbu až na konec dokumentu**, což je na šesti tisících řádcích
    **128 ms** (2 000 řádků 47 ms, 300 řádků 11 ms) — jednorázově, při rozbalení checku, po vteřinách
    čekání na stažení. Do #303 se neplatila, ale taky se nikam neskočilo.

    **Proč to #292 nechytilo**, ať je zapsané: jeho sonda skládala `NSScrollView` ručně a **rozměr mu
    dala předem**, tedy měřila cestu, kterou aplikace nejde — tatáž chyba jako u vynucené sazby celého
    dokumentu, jen o vrstvu vedle.

    Vedlejší zisk, který se nehledal: konec logu je **vybíratelný**, takže se z něj kopíruje bez
    otevírání sheetu.
  - **Sheet `Ukázat celý log` je široký podle obrazovky** (`Policy.codeSheetWidth`, #292), ne 820 bodů
    jako od #157. Sheet **zalamuje**, takže úzké okno znamená víc řádků sazby na jeden řádek logu:
    změřeno 3,89× při 820 bodech, 2,63× při 1 360 a **1,54× na stropu 2 700** (o 60 % méně
    scrollování). Strop je zrovna tam, kde přestane zalamovat **mediánový řádek** Actions logu
    (333 znaků na řádek proti mediánu 327) — a zvedl se z původních 1 600 po měření na té obrazovce,
    na které se aplikace používá (3 440 bodů). Dolní mez je dřívějších 820, protože užší by byla
    regrese; přes obrazovku sheet nejde nikdy. Zamítnuto měřit nejdelší řádek obsahu: scan megabajtů
    na hlavním vlákně při otevření, a prospělo by to jen hunkům kódu.
  - **Výška okýnka se počítá z metriky fontu, kterým se kreslí** (#236, `LogTailTextView.height`):
    krátký log si vezme jen tolik, kolik má řádků, dlouhý se zastropuje na `CheckDetailView.logMaxHeight`
    a scrolluje uvnitř.
  - **Rezerva na vodorovný scroller je 17 bodů, a je odměřená na tom, na čem se kreslí** (#347; do té
    doby 13). Je to opsané číslo, protože `NSScroller.scrollerWidth` je `@MainActor` (dědí to z
    `NSControl`), kdežto výška se počítá `nonisolated`.

    **Čím to bylo špatně, je to podstatné na téhle odrážce.** Třináct bodů je `scrollerWidth` pro
    velikost **`.small`** — tedy pro scroller, který okýnko nikdy nekreslí: `makeScrollView()` nechává
    `NSScrollView`u výchozí **`.regular`**, a ten bere 17. Konstanta tedy nebyla odhad, byla to
    **skutečně odměřená hodnota jiného ovládacího prvku**, což je zrovna ta chyba z #236 — a hůř se
    hledá než odhad, protože vypadá odměřeně. Vypadala odměřeně i tomu testu, který ji držel: ptal se
    API na `.small`, tedy zopakoval tu samou úvahu, a byl proto zelený i nad rozbitou hodnotou.

    Změřeno **u obou stylů**, protože jeden je půlka problému: okýnko o výšce 441 má s **legacy**
    stylem `contentView.bounds.height` 424 (zábor **17**), s **overlay** 441 (zábor **0** — overlay
    scroller plave nad obsahem, i když je 17 bodů vysoký). Rezervuje se **legacy jako horší případ**:
    při overlay zbyde 17 bodů prázdna, kdežto naopak by se z obsahu ukusovalo.

    Co ty 4 body dělaly, a **na každém konci jinak**: nezastropované okýnko bylo o **2 body** nižší než
    jeho vlastní dokument (dva z těch čtyř spolkl slack na prokládání, viz níž), takže log, který se měl
    vejít celý, dostal svislý scroller a odscrolloval se o 2 body — horní řádek se ořezal. Zastropované
    okýnko ukazovalo **29,71 řádku** místo třiceti. Co se u stropu **nezměnilo**: u horní hrany je
    necelý řádek vidět i po opravě, protože `2 × inset` leží uvnitř dokumentu a skáče se na jeho úplný
    konec. Rezerva rozhoduje o výšce, ne o zarovnání mřížky řádků.

    Na `preferredScrollerStyle` se schválně neptáme: **mění se za běhu** podle připojené myši (u #347
    se dva běhy sondy za sebou usadily jednou na `legacy`, jednou na `overlay`), a okýnko, kterému se
    výška mění připojením myši, je horší než 17 bodů prázdna u krátkého logu.

    **Drží to test, ale jiný než dřív** — `LogTailScrollerReserveTests` se ptá **kresby**: postaví
    `makeScrollView()`, vynutí styl na instanci, položí do něj dokument širší než okýnko a odečte,
    kolik z výšky ubylo. Test, který se ptá API s ručně vybranou velikostí, se dá splést stejnou
    úvahou dvakrát; tenhle ne.
  - **Obsah se počítá o `lineSpacing` velkoryseji, než co text potřebuje**, a je to schválně:
    posledního řádku se prokládání netýká, takže vysázený dokument je `N × lineHeight − lineSpacing
    + 2 × inset` vysoký, kdežto `height` počítá `N × lineHeight + 2 × inset`. Dva body slacku znamenají,
    že okýnko je na obsah vždycky o chlup **větší**, nikdy menší. Kdo to bude chtít zpřesnit, musí
    s tím posunout i `logMaxHeight` — strop na tom stojí.
  - **Strop výšky je 445 bodů, tedy přesně 30 řádků** (#303; do té doby 320 bodů = 21 řádků, a do #347
    441 — viz konec téhle odrážky). Zvednuto
    na výslovné přání po proklikání, ale **kolik přesně, rozhodlo měření** (`CheckLogRoomProbe`): sonda
    vyrendruje tab `Kontroly` s rozbaleným spadlým checkem a z hierarchie vyčte, kolik bodů viewportu
    zbylo **pod** okýnkem. Nad okýnkem je vždycky 173 bodů (hlavička karty, řádek checku, anotace, akce
    a hlavička „nevešlo se“) a spadlý check stojí v seznamu první, takže je to nejhorší případ:

    | Okno | Viewport tabu | Zbylo při 320 | Zbylo při 441 |
    |---|---|---|---|
    | 952 (okno na tomhle stroji) | 786 | 293 b = 10 řádků | **172 b = 6 řádků** |
    | 810 | 644 | 151 b = 5 řádků | 30 b = 1 řádek |
    | 700 (`defaultSize`) | 534 | 41 b = 1 řádek | −80 b |
    | 400 (podlaha `RootView`) | 234 | −259 b | −380 b |

    Rozhodlo první řádek tabulky: na okně, ve kterém se aplikace používá, zbývá **6 řádků seznamu**,
    takže důvod, kvůli kterému se detail stěhoval do vlastního tabu (#215), platí dál. Cena je zapsaná:
    ve výchozím okně 700 se seznam odscrolluje (při 320 tam byl jeden řádek) — ale není to ztráta logu,
    z okýnka je i tam vidět 24 řádků bez dotčení vnějšího scrollu, pořád víc než dřívějších 21.
    Zamítnuto **525 bodů** (36 řádků: na skutečném okně zbydou 3 řádky, v okně 810 nic — z okýnka by byl
    celý tab) a **357 bodů** (24 řádků, největší hodnota, u které se okýnko celé vejde i do výchozího
    okna: +3 řádky nejsou změna, o kterou se prosilo).

    Strop je vždycky **celý počet řádků** (`14N + 25`), protože okýnko se otevírá na konci logu —
    strop, který slibuje 30 řádků a ukáže 29, je horší než o 4 body nižší okno. Drží to test, ne
    komentář.

    **Ze 441 na 445 u #347**, a je to důsledek opravené rezervy, ne nové rozhodnutí o výšce: hodnoty
    jsou `14N + 2 × inset + rezerva`, takže s rezervou 17 místo 13 se celý řádek trefí na 445, ne 441.
    Rezerva a strop jsou **pár** — jeden se bez druhého posunout nedá, jinak strop spadne mezi řádky.
    Rozhodnutí „30 řádků“ zůstává; **přeměřeno**, co to stojí seznam checků (`CheckLogRoomProbe`,
    řádek seznamu 28 bodů): každé „zbylo“ v tabulce výš se zmenší o 4 body, na skutečném okně
    172 → 168, tedy **pořád 6 řádků** — rozhodující řádek tabulky se nemění. Zaplatí to okno 810, kde
    ze 30 bodů zbyde 26, tedy z jednoho řádku seznamu žádný.
  - **ANSI se strhává a timestampy se schovávají.** ANSI je v obou změřených logách (116 řádků
    v 8,78MB) a bez toho se v okně objeví `^[[36;1m` uprostřed věty. Timestamp má skoro každý řádek
    (25 528 z 25 534) a zabírá 28 znaků, tedy ukrajuje šířku zrovna tam, kde je potřeba přečíst konec
    assertace; zadání nabízelo schovat nebo zešednout, schovává se — zešednutí by šířku nevrátilo.
  - **Nic z toho se neukládá** a nepřežije ani sbalení checku, ani restart. Sbalení navíc stahování
    **zruší**: čtyři vteřiny jsou za hranicí, kdy stačí přebarvit tlačítko, a nezrušený běh by dopsal
    text, který se má zapomenout.

    Platí to **i pro sheet s celým logem**, a to je snazší přehlédnout: drží celý text ve `@State`
    detailu, takže se musí nulovat při přepnutí checku **i při přepnutí PR**. Bez toho pravidlo platí
    jen ve store — sbalení zahodí `checkDetail`, ale otevřený sheet dál drží megabajty a nad novým PR
    by ukazoval log z předchozího. Nález Copilota na #214, a byl schovaný v `Suppressed comments`.
  - **Anotace z CI není nález z review.** Plochý řádek se štítkem (`error`/`warning`/`notice`), ne
    bublina s obrysem a levým pruhem — nález má revieweera a dá se odmítnout, anotace je cizí fakt.
    A **nepočítá se nikde**: ani v řádku fronty, ani v panelu, ani v odznaku tabu.
  - **Dvě různá „chybí“ u anotací**, protože se o nich ví různě moc: přesný počet stažených, které
    se nekreslí, a `mayHaveMore` bez počtu, když přišla plná stránka. Je to tentýž případ jako
    `ConversationShortfall.events` (#171) — mlčet nejde, ale číslo si vymyslet nesmíme.
  - **Konec logu má omezenou výšku a scrolluje se v něm.** Tři stovky řádků nasazených naplno odtlačí
    zbytek seznamu checků mimo obrazovku, tedy zrovna to, kvůli čemu se detail z `Přehledu` stěhoval.
    Zarovnání doleva u toho **potřebuje spočítanou šířku** (`availableWidth`, #220): `ScrollView`
    obsah užší než viewport vystředí a uvnitž dvouosého scrollu se šířka vyjednat nedá, protože
    obsah dostane neomezenou nabídku. `Spacer` ani `frame(maxWidth:)` to nespraví — chyceno
    offscreen renderem.
  - **Log nejde přes obarvování po řádcích.** `SelectableCodeView` bez známého jazyka sází text
    jednolitě: změřeno **38 ms proti 2,2 ms** na dvoumegovém logu (17×), na 8,78 MB 155 ms proti
    7,9 ms. Od #417 o tom **rozhoduje `CodeText.path`** (`nil` = jednou barvou), ne shoda: do té doby
    to drželo jen tím, že `path` bylo jméno checku a `Language(path:)` v něm nic nepoznal — což by
    rozbil check jmenující se `build.rs`.
  - **Log se pro sheet připraví při stažení, ne při kliknutí** (#417, `Policy.jobLog` → `JobLog`):
    sundá se z něj ANSI, **timestampy zůstanou** a spolu s textem se nese počet řádků a velikost,
    které vypisuje hlavička. Sundání ANSI je průchod celým logem (192 ms na 8,78 MB), takže by na
    hlavním vlákně při kliknutí bylo vidět; platí se **jednou** v témže odloženém úkolu jako ocas
    (`Policy.logTail(withoutANSI:)`). Scan megabajtů při každém překreslení hlavičky by byl přesně
    to, co zakazuje #224.

  - **Sheet `Ukázat celý log` a sheet s hunkem jsou jeden sheet se dvěma profily velikosti** (#417)
    — podrobnosti v *Sheet s kódem a s logem* na konci téhle kapitoly.

- **Tab `Commity`** (#316) — seznam commitů PR, `AppStore+Commits` a `CommitListView`.

  **Prohlížeč, ne review.** `Změněné soubory` odpovídají na „co je na PR jinak proti základu“; slitý
  diff ukazuje výsledek, ne cestu. Otázka „proč tenhle řádek zmizel“ má odpověď v jednotlivých
  commitech, a ta se do #316 hledala v prohlížeči — tentýž pohyb jako u `Konverzace` (#183)
  a `Kontrol` (#215). V pruhu sedí **vedle `Změněných souborů`**: obojí odpovídá na „co se v kódu
  změnilo“, jen jednou naráz a jednou po krocích, takže se to čte jako pár.

  - **Tab má tři stavy, ne čtyři** (`Policy.commitsTab(commits:failure:)`). Prázdný mezi nimi
    **není schválně**: pull request bez commitů neexistuje, takže klidná hláška o prázdnu by
    tvrdila nemožný stav — prázdná odpověď je proto hlášená jako **porucha** s vlastní větou. Je to
    obrácená volba než u `Kontrol`, kde prázdno **je** odpověď (PR bez CI), a rozdíl je právě
    v tom, jestli ten prázdný stav umí v realitě nastat.

    | Stav | Kdy | Co je v tabu |
    |---|---|---|
    | `loading` | `commits` nenačtené, bez poruchy | `Načítám commity…` — o commitech netvrdí nic |
    | `list(_, failure: nil)` | neprázdné `commits` | seznam od nejnovějšího |
    | `list(_, failure: reason)` | neprázdné `commits` + porucha | seznam a **nad ním** okrová věta, že je to poslední známý stav |
    | `failed(reason)` | porucha, nebo prázdná odpověď | červený prázdný stav s textem od `gh` a `Zkusit znovu` |

  - **Odznak je prostý počet, a jen nad seznamem.** Tichá kapsle: kolik je commitů, je množství, ne
    upozornění. Nad nenačteným ani spadlým stavem nic — tatáž lekce jako u `Kontrol` (#306).
  - **Tahá se s detailem, ne pollingem ani na kliknutí.** Pollingem přes všechna PR by to byla
    N+1 past; na kliknutí by se odznak s počtem objevil až v tabu, který má člověk zrovna otevřený,
    tedy zrovna tehdy, kdy ho nepotřebuje. Je to jedno volání (1,20 s pro sedm commitů) a jde
    **za** checky, ne souběžně: paralelně by na jeden výběr řádku běžely dva `gh` podprocesy místo
    jednoho, za úsporu jedné vteřiny.
  - **I když detail spadne** — tab je v pruhu vždycky, takže by nad nenačtenou hlavičkou svítilo
    `Načítám commity…` navždycky. A **zrušené načtení se dotáhne po návratu na PR**, protože detail
    je pak z cache a sám by `loadCommits` už nespustil. Obojí je doslova tatáž past jako u checků
    (#306), jen o jedno volání vedle.
  - **Seznam je od nejnovějšího, a otáčí se na jednom místě** (`Policy.commitsNewestFirst`, volané
    z `commitsTab`). Gateway vydá, co přišlo z API (od nejstaršího), store to tak i uloží — pořadí
    kresby je rozhodnutí, ne vlastnost dat, takže se dá změnit jednou funkcí a nedá se rozejít mezi
    odznakem a plochou tabu. **Otáčí se, neřadí**: pořadí z API je topologické, takže po rebase nebo
    cherry-picku je datum staršího commitu novější než datum toho za ním a `sorted(by: committedAt)`
    by postup rozházel.

    **Nepamatuje se to, a je to změřené.** `commitsTab` běží při každém překreslení (odznak i plocha),
    takže otočení je práce na redraw — **18,7 µs** pro 250 commitů (strop API, Debug) proti **54 ms**,
    co stojí sazba téhož seznamu. Cache by tady stála víc pozornosti, než kolik ušetří.

    **Je to otočení proti návrhu** (sekce 19 mockupu i specifikace měly „od nejstaršího, jako na
    GitHubu, protože PR se čte jako postup“). Neobstálo to na hotové obrazovce: v okně se PR nečte
    od začátku, ale od toho, co přibylo naposled — tentýž pohyb, jaký dělá pruh
    „Od tvé poslední návštěvy“, a tentýž důvod, proč jsou fakta v `Přehledu` nahoře (#280). Postup
    se z otočeného seznamu přečte pořád, jen odspodu. **Mockup to od #299 kreslí stejně** — sekce 19
    má seznam od nejnovějšího i pruh `7 commitů · od nejnovějšího`, a původní důvod v ní zůstal
    zapsaný i s tím, proč neobstál.
  - **Pilulka `hlava` se bere z `headSha`, ne z pozice v seznamu** (`Policy.headCommit(in:head:)`),
    a po otočení je to o to snazší přehlédnout: hlava **bývá** nahoře, ale je to důsledek toho, jak
    seznam přišel, ne pravidlo. Rozejdou se ve dvou běžných situacích — po pushnutém commitu je
    seznam o krok pozadu, a nad stropem API (250) chybí zrovna ta novější část. V obou → **neoznačí
    se nic**; mlčet je správnější než ukázat na commit, o kterém to neplatí. Bere se z pořadí jedině
    tehdy, když hlava ještě není známá (detail nedorazil): tehdy je jí první řádek, protože GitHub
    vrací od nejstaršího a otočením je nejnovější první.
  - **Pruh nad seznamem o pořadí mluví, takže se s ním mění** (`Policy.commitsHeadline`). Věta
    `7 commitů · od nejnovějšího` je jediné místo, které pořadí pojmenovává — „od nejstaršího“ nad
    otočeným seznamem by bylo tvrzení, které se dá vyvrátit pohledem pod něj. Na stropu API zůstává
    `prvních 250 commitů`: GitHub vydá **prvních** 250 commitů PR a pořadí kresby s tím nehýbe, takže
    nahoře je pak nejnovější **z nich**, ne hlava PR.
  - **Pilulka `sloučení` musí být dopředu.** Diff sloučení se počítá proti prvnímu rodiči a umí
    vyjít prázdný — bez upozornění by se prázdný diff četl jako porucha. Je to tentýž rozdíl jako
    mezi `čisté` a `spadlo` u review.
  - **Monogram v kolečku se bere ze jména, ne z přezdívky.** Dokud obrázek nedorazí — a u commitu
    bez účtu (`author: null`) nedorazí nikdy — je monogram tím, co v kolečku stojí, takže `IM`
    vedle jména `Kumar Prateek` vypadá jako řádek o dvou různých lidech. Není to kuriozita:
    sloučení commituje GitHub pod celým jménem, kdežto `author.login` je přezdívka téhož člověka.
  - **Panel s nálezy se nekreslí** (`PullRequestTab.showsReviewPanel`) — čtvrtý takový tab po #294,
    s vlastním důvodem: nálezy platí proti `headSha`, takže by u staršího commitu ukazoval nálezy
    k jinému kódu.
  - **Řádek se od #317 dá rozkliknout, a teprve tím dostal šipku `›`.** Do té doby žádná nebyla
    schválně: šipka, za kterou se nic nestane, slibuje interakci, která tam není — tatáž úvaha jako
    u checku bez čísla jobu (#214). Co se rozkliknutím stane, je v odstavci níž.
  - **Rozkliknutý commit přepne obsah tabu** (#317) — seznam zmizí a diff jednoho commitu dostane
    celou plochu, jako to má GitHub. Kreslí to `CommitDiffView` (hlavička `CommitHeaderView` a pod
    ní `DiffView`), stav drží `AppStore+CommitDiff`, rozhoduje `Policy.commitDiffTab`.

    - **Je to prohlížeč, a je to vidět z typu.** `CommitDiffView` nedostane `AppStore` ani
      identifikátor PR, takže **nemá čím** vyrobit bublinu nálezu ani rozdělaný komentář; `DiffView`
      od něj dostane jen čtecí parametry a prázdné hodnoty se **nevypisují** (mají default), aby
      nebylo druhé místo, kde se dá `findings:` omylem naplnit. Drží to `CommitDiffReadOnlyTests`
      ve třech vrstvách — co se předá, co z toho vyjde v řádcích, a že žádný řádek nenabídne akci.
      Důvody jsou dva a oba jsou tvrdé: komentář ke commitu by potřeboval **jiný klíč draftu**
      a **pátou metodu v `ReviewPublishing`** (podmínka č. 1), a nálezy jsou klíčované `headSha`
      (podmínka č. 5). Tím, že je tab celý čtecí, se podmínky č. 1 **nedotýká vůbec**.
    - **Co zůstává**: oba pohledy, word-level zvýraznění, sbalování souborů, rozbalování kontextu,
      kopírování i strom souborů vlevo (`⌘1`) — commit s třiceti soubory ho potřebuje. Všechno
      z `DiffView`, tedy jedna cesta pro obě obrazovky.
    - **Rozbalený kontext se čte z toho commitu**, ne z hlavy PR: `FileExpansionKey` nese
      `commit: String?` a `AppStore.reveal(_:of:in:commit:)` podle něj vybere
      `fetchFile(repo:path:at:)`. Bez toho by odkryté řádky byly z dnešní hlavy, tedy posunuté
      o všechno, co mezitím přibylo — a vypadaly by věrohodně. **Tentýž klíč drží sbalené soubory**,
      takže se sbalení mezi diffem PR a diffem commitu nesdílí (a `Zobrazit jen diff` se nabízí jen
      v tom diffu, kde je co sbalit).
    - **Hlavička nese to, co v seznamu není**: tělo zprávy, kapsli se sha (kliknutím se kopíruje),
      odkaz na GitHub, autora, čas, počet souborů a `+X −Y`. **Čísla jsou ze staženého diffu**,
      takže nestojí volání navíc. Vlevo je cesta zpět `‹ Commity` s pozicí (`2 ze 7`), vpravo tichá
      věta „Jen ke čtení…“ s odkazem do `Změněných souborů` — kdo přijde odtamtud, bude do řádku
      chtít kliknout.
    - **Sbaluje se tělo zprávy, ne celá hlavička.** Je to jediná část, která roste bez omezení —
      zbytek jsou tři řádky pevné výšky —, a hlavička sbalená celá by se smrskla na pruh
      s tlačítkem zpět, tedy přestala odpovídat na „na co se to koukám“. Přepínač je **vlastní
      řádek s popiskem** (`⌄ Tělo zprávy` / `› Tělo zprávy · 6 řádků`, `Policy.commitMessageToggle`),
      protože po sbalení musí zbýt něco, na co se dá kliknout; počet řádků nese jen sbalený stav.
      Volba je **globální ve store** (`AppStore.isCommitMessageExpanded`) — předvolba pohledu jako
      `isReviewPanelExpanded`, tedy ne mapa per PR a hlavně ne `@State`, který mezi pull requesty
      přetéká. **Výchozí stav je rozbaleno** a u jednořádkové zprávy se nekreslí ani přepínač
      (`Policy.commitMessageBody` vrátí prázdno).

      **Řádky se počítají `TextLines`, ne `split(separator: "\n")`** (#339) — a titulek i tělo se
      dělí na `isLineTerminator`. Do #339 tam bylo obojí jinak a popisek u zprávy s `CRLF` tvrdil
      `1 řádek` bez ohledu na délku; podrobnosti u `TextLines` výš. Ke stavu se **normálním
      používáním nedá dojít** (musel by v tabu ležet PR s `CRLF` ve zprávě), takže je na něj sonda —
      `CommitsTabRenderProbe`, scénář `diff-commitu-sbalena-hlavicka-crlf`.
    - **Prázdný diff dostane větu, ne prázdnou plochu** (`CommitDiffTabState.nothing`), a jinou
      podle toho, jestli je to sloučení. Změřeno: prázdno vracejí hlavně **prázdné commity**
      (`--allow-empty`), ne sloučení — podrobnosti u gateway a ve specifikaci.
    - **Návrat nezapomene, kde jsi byl.** Podbarvený řádek i cíl scrollu je sha posledního
      staženého diffu (`lastOpenedCommit(in:)`), tedy táž hodnota, ze které se diff kreslí — druhá
      paměť by uměla tvrdit něco jiného. Zpátky vede tlačítko i `⎋`; zkratka bydlí na detailu PR
      a je **zakázaná** mimo tab, nad seznamem, nad paletou a nad potvrzením odeslání.
    - **Commit, který ze seznamu zmizel** (force push), se nekreslí — `Policy.openCommit(_:in:)`
      vrátí `nil` a tab spadne na seznam.
    - **V okně se drží nejvýš jeden diff commitu na PR** (klíč `commitDiffs` je pull request, sha je
      v hodnotě). Přeskakování mezi dvěma commity tedy stahuje pokaždé znovu; návrat do seznamu
      naopak diff **nezahodí**, takže zpátky do téhož commitu je zadarmo.

  - **Sedmá záložka stojí jedinou věc: šířku pruhu záložek — a ta se zaplatila.** Pilulka `+X −Y`
    stojí 110 bodů a `Commity` s odznakem 112, takže se jedna zaplatila druhou a hranice povyrostla
    o **dva body okna** (937 → 939), ne o sto dvanáct. Podrobnosti i s tím, co přidal druhý stupeň
    (#318), jsou v *Pruh záložek — tři podoby podle šířky* níž; naměřená čísla drží
    `TabStripWidthTests`, viz [`docs/testovani.md`](testovani.md).

    **Specifikace měla o 17 bodů nižší absolutní čísla**, protože je měřila na **replice** pruhu
    (867/920 pro stav před #316, 872/925 se sedmou záložkou). Rozdíl, o který jde, replika odhadla
    dobře — předpovídala +5 bodů okna, ve skutečnosti jsou to +2 —, ale absolutní hranice se z ní
    brát nedají.

- **`Přehled` má dlaždice s fakty** (#198): commity (a kolik z nich je nových od minule),
  soubory (a kolik má nález), hlava PR a sha, proti které platí nálezy. **Nic se pro ně
  nedotahuje** — jsou to údaje, které v okně už jsou, jen roztroušené. Pořadí v tabu je
  **banner „od minule“ → řada dlaždic → karta s popisem** (#280). Pravidla:
  - **Dlaždice jsou nad popisem, ne pod ním** (#280, návrh sekce 18). Do #280 to bylo obráceně;
    rozhodla **nesouměrnost délek**, ne důležitost obsahu: dlaždice jsou vždycky tři čísla a dvě
    sha, kdežto popis je libovolně dlouhý — u pracovních PR běžně padesát řádků — takže cenu za
    odrolování platil vždycky ten kratší obsah. `Nálezy proti` navíc odpovídá na otázku „platí
    to, co v okně vidím?“ a ta odpověď nepatří za odrolování.

    Co se u toho **nesmí rozbít**: mění se pořadí, ne sazba. Popis se nezúžil ani neosekal
    (`MarkdownText` a písmo 12,5 zůstávají, sazbu řeší #279), řada nedostala pružné rozměry,
    které v ní nebyly (#220 — a je to zrovna to, na čem se `Přehled` rozbil u #291), a **prázdný
    popis se nesmí slít s nenačteným** — pod řadou faktů o důvod víc, protože prázdná plocha se
    tam čte jako „nic tu není“ ještě snáz. Doloženo tím, že render **před** a **po** má při každé
    šířce i tématu **shodnou velikost plátna a shodnou multimnožinu vodorovných řádků**: řádky se
    přesunuly, ale žádný se nepřekreslil.
  - **Úzké okno se tím neřeší** — návrh (sekce 18) ho nechává `odloženo`. Čtyři dlaždice se
    v úzkém tabu drtí (popisky se lámou na `COMMIT/Y`, hodnoty se utínají na `abc12…`), jenže
    **stejně jako předtím**: řada je po přehození stejně široká, jen stojí jinde, takže se tím
    nic nezhoršilo. Kdyby se to řešilo, ve hře je mřížka 2×2 (nic nezmizí, řada je dvakrát vyšší,
    takže popis začíná níž) nebo tři dlaždice s tím, že `Commity` odpadnou první — a rozhodnout
    se to musí **dopředu**, protože šířka se předává, ne vyjednává.
  - **Dlaždice, o které se nedá nic říct, se nekreslí.** Řádek plný nul je řádek, ve kterém se
    ztratí to jedno číslo, na kterém záleží — a nula u souborů navíc tvrdí, že PR nic nemění,
    i když se diff jen ještě nenačetl.
  - **Neúplný počet se nekreslí.** Utnutá stránka událostí znamená, že commity přesně neznáme,
    a číslo „aspoň tolik“ vydávané za úplné je horší než prázdné místo.
  - **Sha nálezů jen při rozchodu s hlavou** — a jedině když je hlava načtená. Shodná je údaj, který nikoho nezajímá; rozešlá je
    důvod, proč nálezy neplatí (tvrdá podmínka č. 5), a je žlutá jako stav `zastaralé`.
  - **Mřížka čtyř sloupců, ne `HStack`.** V `HStacku` se dvě dlaždice roztáhnou přes celou šířku
    a číslo v nich plave uprostřed prázdna; v mřížce si drží čtvrtinu bez ohledu na počet.
- **Karta s popisem musí skončit uvnitř tabu** (#291) — obojí odsazení na cestě k sazbě se
  odečítá z předávané šířky, viz *Kdo přejde na `filling()`* v sekci o šířce. Co k tomu drží
  hlavička karty:
  - **Prázdné a nedoručené se nesmí slít.** `nil` je `Načítám popis…` se spinnerem, prázdný řetězec
    `Autor k PR nic nenapsal.` — PR bez popisu je běžný stav, kdežto nenačtený detail je stav, ve
    kterém se ještě čeká.
  - **Hlavička je jeden řádek, ať je tab jak chce úzký** (`ViewThatFits`, dvě podoby). Se správnou
    šířkou se čtyři údaje do zúženého tabu nevejdou — a `HStack` je nakrájí **uvnitř slov**:
    `otevře/ný` v pilulce stavu a `Otevřít na / GitHub / u` v odkazu, tedy tři řádky navíc v kartě,
    která má být hlavička a linka. Druhá podoba je **bez relativního času**: ze čtyř údajů je
    nejméně potřebný a stejný nese i řádek ve frontě a hlavička PR nad tabem. Vypadnout celý je
    čitelnější než jeho zbytek — pokus nechat ho zkracovat skončil osamoceným `r` z `minulý rok`.
  - **Odkaz ustupuje poslední, ale pružný zůstává.** Je to jediná věc v hlavičce, na kterou se dá
    kliknout (`layoutPriority(1)`), takže popisek na půl slova je horší než zkrácené jméno autora.
    Rigidní být přesto nesmí: tab se dá stlačit až na ~128 bodů (okno na podlaze 700, rail 52,
    panel vytažený na 520) a nezkratitelný odkaz by kartu roztlačil, tedy vyrobil zpátky #291.
  - **`lineLimit` z řádku pod `Link` nedosáhne.** Změřeno renderem: odkaz se zalomil na tři řádky,
    i když ho `HStack` nad ním měl zakázaný. Musí být uvnitř, na `Label`u.
- **Sazba položek konverzace je z návrhu** (#216). U #183 se konverzace přestěhovala, ale
  položky zůstaly, jak vypadaly v `Přehledu` od #72 — a vedle sebe s návrhem to bylo zřetelné.
  Ověřovalo se to **vyrenderovaným mockupem vedle offscreen renderu** položek, ne po paměti;
  tři odchylky (přerušená osa, zmenšený uzel, odznak `Bot` u cizího jména) padly až na obrázku.
  Co se u toho rozhodlo:
  - **Karta je vodorovné pruhy, ne jeden blok.** Hlavička na `raised` a oddělená linkou
    `lineSoft`, pod ní tělo — jako karta popisu PR (#198) a blok kontrol (#209). Do #216 to byl
    jeden šedý blok, ve kterém se jméno nedalo odlišit od prózy pod ním.
  - **Čas je u pravé hrany** (`margin-left: auto` v návrhu). Nalepený na odznak verdiktu se s ním
    četl jako jeden údaj.
  - **Verdikt nese proužek na hraně**, zelený u schválení, červený u vyžádaných změn — tatáž
    škála jako řádek fronty a karta nálezu, takže se pozná periferně. Barva je **volitelná**
    (`Color?`), ne `.secondary`: „má tahle karta verdikt?“ se jinak musí ptát porovnáním barev.
  - **Próza 12,5** jako všude jinde v okně; do #216 byla o stupeň větší než sousední bloky.
  - **Uzel je 24 bodů s plnou barvou obrysu.** Neutrální má obrys `line` a symbol `ink2` — dvě
    různé barvy, takže je skládá `axis` a `marker` vrací `tint: Color?`. Ztlumený obrys
    (`opacity(0.5)`) dělal ze zeleného schválení nevýrazný šedozelený kroužek.
  - **Mezera mezi uzly patří obsahu, ne celému uzlu.** Kdyby odsazovala `HStack`, končila by
    linka dřív než uzel a osa by mezi položkami měla díry.
  - **Sha jsou odznaky vedle věty**, ne údaj u pravé hrany: u force-pushe patří ke slovesu.
    Řádek proto potřebuje `shas: [String]` po jednom, a `detail` je z toho odvozený.
  - **Jména v událostech jsou tučná** (`attributedTitle` s `inlinePresentationIntent`). Řádek
    říká, **co** je jméno; jakou barvu tučné dostane, rozhoduje view. `title` je odvozený
    (`String(characters)`), takže se věta a její sazba nemůžou rozejít.
  - **Odznak `Bot` je u avataru**, ne za větou: za ní se lepil na jméno toho, **komu** se review
    vyžádalo, tedy tvrdil něco jiného, než co je pravda.
  - **Zastarání má vlastní token `Palette.stale`**, ne systémovou oranžovou: vedle červené
    blokujícího nálezu se obojí slévalo do jedné škály naléhavosti, kterou zastarání nemá.
  - **Bublina vlákna je jeden celek** složený z pruhů: cesta a odznaky v hlavičce, úryvek,
    komentáře, pole na odpověď. Řádek s cestou **nad** rámečkem vypadal jako popisek k něčemu,
    co začíná až pod ním.
  - **`Placement` rozhoduje, co je v hlavičce.** Na ose cesta a řádek (nad bublinou žádný kód
    není), u kódu náhled prvního komentáře, když je vlákno sbalené — cesta je v hlavičce souboru
    o kus výš a v každé bublině by ji okno psalo podruhé. Do #216 to řídil `snippetContext: Int?`,
    tedy jedno pole se dvěma významy; a náhled u sbaleného vlákna se přitom ztratil.
  - **Odznak `zastaralé` zůstává na vlákně.** Při stěhování řádku s cestou dovnitř bubliny zmizel,
    a bez něj vypadá zastaralé vlákno jako připomínka k dnešnímu kódu.
  - **Úryvek u vlákna má na ose kratší kontext** (`Policy.timelineSnippetContext`, jeden řádek
    proti pěti u kódu). V diffu je úryvek náhradou za to, že řádek nejde ukázat v souboru; na
    ose stačí **ukázat místo**. S pěti zabralo jedno vlákno půl obrazovky.
  - **Barví se jen komentovaný řádek**, ostatní jdou jako kontext (`DiffLine.asContext`). Celý
    zelený blok se čte jako změna, o které vlákno není.
  - **Podklad z palety, ne systémová šeď**, a **bez proužku na hraně**: vyřešené vlákno hlásí
    odznak, takže proužek říkal totéž podruhé a v ose se pletl s proužkem verdiktu u review.
  - **Tlačítka bez ikon** a vpravo od nich počet odpovědí, jak to má návrh. Počet **ustoupí**
    tomu, co se právě děje — dva údaje na jednom místě by se přebíjely.
- **Komentář pod PR se dá napsat z okna** (`ConversationComposerView`, #216) — pruh na spodní
  hraně tabu `Konverzace`. Je to čtvrtá cesta ven a rozšíření tvrdé podmínky č. 1, viz `CLAUDE.md`.
  - **Pod osou, ne v pravém panelu**, kam ho kreslí návrh. Ten panel je vidět ve všech tabech
    a jeden z jeho tabů je `Moje review`, takže by pod sebou stála dvě pole a dvě odesílací
    tlačítka, z nichž každé dělá něco jiného — a zadání #216 výslovně říká, že s review splynout
    nesmí. Sazba návrhu (linka nahoře, avatar, pole, odesílací tlačítko) zůstává; mění se, ke
    kterému sloupci je pruh přilepený.
  - **Composer je `nil` bez `gh`**, protože pak nevede z aplikace ven žádná cesta a pole by
    slibovalo odeslání, které nikdy nepůjde. Zakázané odesílání (repo mimo `PublishScope`) je
    něco jiného: to se dá zapnout v nastavení, takže pole zůstává a tlačítko je **zakázané
    s důvodem** — tatáž úvaha jako u odpovědi do vlákna.
  - **Rozepsaný text žije ve store** (`pullRequestComments`), ne ve view: překliknutí tabu osu
    i composer odbourá. Na disk se neukládá — je to jedna věta v diskuzi, ne review.
  - **Po selhání text zůstává**, po úspěchu se maže. Odeslaný komentář se připíše do načtené
    konverzace (`Policy.appending`), takže je vidět bez kola po síti.
  - **Dvojklik odešle jednou.** Kontrola leží před prvním `await`, takže mezi nimi není mezera,
    do které by se závod vešel; druhé odeslání by nebylo oprava prvního, ale další věta.
  - **Zápis do konverzace nesmí ztratit osu.** `Conversation.init` má `events` s výchozí prázdnou
    hodnotou (kvůli odpovědím z doby před #171), takže je při přeskládání lze vynechat bez chyby
    překladu — a osa se pak po odeslané odpovědi tiše vyprázdnila o commity a pushe. Opraveno
    u #216 a hlídá to test, který ověřuje obě cesty (odpověď i vyřešení).
- **Konverzace je vlastní tab s časovou osou** (#183). `Přehled` a konverzace odpovídají na dvě
  různé otázky — „jak to teď stojí“ a „co se dělo“ — a v jednom scrollu se to druhé četlo tak, že
  se přes první přerolovalo. Čtyři pravidla:
  - **Uzel osy není položka konverzace.** `ConversationNode` slévá **za sebou jdoucí** commity do
    jednoho uzlu: jedenáct pushů utopí dva komentáře, kvůli kterým se do konverzace chodí. Commit
    před komentářem a po něm se **neslévá** — jsou to dvě různé věci, které se staly kolem něj.
  - **Symbol nese uzel na ose, ne řádek.** Dvě ikony vedle sebe vypadají jako dva různé údaje.
  - **Filtr je zúžení, ne čtyři seznamy** — a počty u popisků se počítají z **plné** osy, jinak by
    se číslo měnilo tím, na co se zrovna kouká. Review s prózou patří ke komentářům (je to něčí
    text), prázdný verdikt k událostem (je to děj).
  - **Položku kreslí sdílené view** (`ConversationEntryView`), takže se totéž vlákno nevykresluje
    dvakrát jinak. Vlákna **s kotvou** zůstávají bublinami u kódu; jediný domov konverzace se
    nedělí, jen stěhoval.
  - **Osu kreslí `ConversationRow`, ne uzel s indexem** (#361). Řádek nese **uloženou identitu**
    a příznak značky poslední návštěvy; skládá ho `Policy.conversationRows(of:filter:since:)`.
    Dva důvody, oba měřitelné:
    - `ForEach(Array(nodes.enumerated()), id: \.element.id)` čte identitu keypathem **přes tuple**,
      takže se při každém dotazu líného seznamu na identitu rozbalí a **zkopíruje** payload enumu
      (`ConversationEntry` nese pole komentářů). Ve vzorku ze ztuhlého okna je to ~5 % vzorků
      hlavního vlákna; v harnessu 0,141 ms proti 0,036 ms na přerovnání 300 řádků. Zaplatí se to
      jedním průchodem při složení řádků (0,179 → 0,265 ms na průchod tělem), takže se to vyplatí
      od druhého přerovnání na jeden průchod tělem — a přerovnání je řádově víc.
    - **Značka „odsud dolů je nové“ je rozhodnutí, ne kresba.** Do #361 ji počítalo view z indexu
      a sousedního uzlu a **neměla ani jeden test**. Zůstává u toho i to, co se snadno přehlédne:
      první uzel značku dostat smí (jinak by při „nové je všechno“ chyběla) a **prokládané datum
      dostane druhou značku** — dvě staré položky mezi novými jsou dvě různá místa, odkud dolů je
      něco nového.

    **Kolo z #361 to nevysvětluje** a nemá se to tak číst: pohon se nenašel, viz
    [`testovani.md`](testovani.md).

  Odznak s počtem se přesunul k `Konverzaci`: říká, kolik je toho **k přečtení**, a čte se
  odteď tam. Události se do něj dál nepočítají (#171).
- **Prázdné a chybové stavy mají jeden vzor** (`EmptyStateView`, #176). Bylo jich deset a každý
  vznikl zvlášť. Tři pravidla:
  - **Povaha není kosmetika**: `calm` (nic nechybí), `waiting` (něco je zapnuté nebo se čeká),
    `failure` (porucha). Zelené „vyřízeno“ nad zapnutým filtrem tvrdí opak pravdy, takže filtr má
    povahu `waiting` a **vlastní východ** — tlačítko, kterým se vypne.
  - **Syrový text zůstává, jak přišel** (`detail`). Hláška od `gh`, `gitu` nebo dekodéru je
    jediné, z čeho se pozná, co dělat dál; vlastní věta místo ní je hádání příčiny.
  - **Rate limit není porucha**: nic se nerozbilo, aplikace se jen ptala moc — proto `waiting`
    a věta o tom, že seznam zůstává takový, jaký dorazil naposled.

  Selhaný checkout zůstává **banner v hlavičce PR**, ne karta: je to porucha na obrazovce, která
  je jinak plná, kdežto tenhle vzor je pro prázdnou plochu.
- **Strom souborů je trvalý levý sloupec** (#197), ne jen popover. U PR o padesáti souborech
  nešlo poznat, kde v něm člověk je, aniž by ho otevřel. Šířka 210 z návrhu, složený je proužek
  34 bodů s počtem souborů. Skládá se **u sebe** — šipkou v hlavičce sloupce, otevírá se kliknutím
  na proužek — a `⌘1` dělá totéž; v liště nad diffem tlačítko **není** (do #219 bylo, viz výš).
  Tři věci:
  - **Sází se úsporně a jiná sazba není** (#219): jen jméno a značka. Počty `+/−` ani slovní
    odznak `nový` se do 210 bodů nevejdou — vyzkoušené vedle jména (zbyde `…S.md`) i pod ním
    (rozhodí řádkování); GitHub je ve stromu nemá taky, patří k hlavičce souboru v diffu.
    Do #219 měl `FileTreeView` i plnou sazbu pro popover `Přejít na soubor`; s popoverem odešla,
    protože po něm zbyl parametr s jediným volajícím a jedinou hodnotou. Odešly s ním
    i `FileTreeNode.additions` / `.deletions` — sečtené počty po složkách kreslil jedině on.
  - **Ikona druhu změny je obarvená**: zelená přidává, červená maže, modrá přejmenovává.
    Tvar sám se čte až po zaostření, barva periferně — a strom se přejíždí očima.
  - **Soubor se ořezává zezadu, složka zepředu.** U jména souboru nese význam začátek
    (`SecretClient.php` versus `SecretClientTest.php`), u cesty ke složce ta poslední část.
  - **Skok na soubor sbalený soubor rozbalí** — jinak by se ukázala jen jeho hlavička.
- **Panel je napravo od diffu, ne pod ním** (#182). Dole si bral výšku, které je v diffu
  nejmíň: kód je dlouhý a úzký, takže spodní pruh se pere právě o to, čeho je málo. Napravo
  bere šířku — spočítané v zadání #182 pro mono 12 px: v pohledu **pod sebou** zbývá i na 14"
  126 znaků na stranu, takže slib „PHP na 120 znaků se vejde“ platí dál. V pohledu **vedle
  sebe** ho neunese žádný displej pod 27"; složení sloupců v tom režimu je #188. Pět věcí,
  které se u toho nemají rozbít:
  - **Složený je proužek s počtem, ne zmizelý panel.** Schovaná práce, o které nikdo neví, je
    horší než úzký pruh; počet je červený, když mezi nálezy něco blokuje.
  - **Šířka má vlastní klíč v předvolbách**, ne přejmenovanou výšku: uložených 220 by jako
    šířka dalo panel užší, než v jakém se dá nález přečíst. Ořezává se **při použití**
    (240–520), protože v `UserDefaults` může být cokoli.
  - **Segmenty jsou vlastní, ne `Picker(.segmented)`.** Systémový přepínač se sází podle textu
    a `Nálezy · 12 / Moje review ●` se do 300 bodů nevejde.
  - **Od #242 jsou segmenty dva, ne tři**, a v proužku je vedle počtu nálezů i značka
    rozdělaného review (počet komentářů, jinak puntík; zastaralý okrový). `Průběh` se odstěhoval
    do vlastní záložky PR — je to záznam běhu, který se u kódu nečte, a u spadlé session se do
    300 bodů nevešel ani důvod, ani konec logu. `Zahodit nálezy` a stáří výsledku šly s tabem
    `Nálezy` ze stejného důvodu: platí pro uložený záznam, ne pro panel.
  - **Nálezy v panelu zůstávají**, i když mají od #242 vlastní záložku. Nejsou to dvě kopie
    jednoho pohledu, ale dvě různé otázky: u kódu „co je tady“, v tabulce „co všechno se našlo“.
    Karty proto **řazení podle sloupců nedostaly** — v 300 bodech se sloupce pořád nemají kam
    vejít a platí pořadí z `Policy.sorted`.
  - **Rozdělané review se sází pod sebe** (tělo, pak komentáře), **změna proti #66**: tam byly
    vedle sebe, protože panel byl nízký pruh přes celé okno. Komentáře měly napevno 320 bodů,
    což je víc, než je celý panel.
  - **Verdikt jsou tři stejně široká tlačítka s krátkými popisky** (`Schválit` / `Změny` /
    `Komentář`). Useknuté `Vyžád…` je u hodnoty, která rozhoduje, co GitHub s PR udělá,
    horší než kratší slovo; plný popisek zůstává v potvrzení odeslání, kde je místo.
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
- **Verdikt se předvyplňuje návrhem z nálezů (#114), ale draft o tom neví.** Co platí, počítá
  `effectiveVerdict(for:)` z uloženého draftu a z návrhu; `setDraftVerdict` je pořád **jen moje
  volba**, takže zrušená volba nepadá na „nevybráno“, ale zpátky na návrh. Kdyby se návrh
  zapisoval, existoval by draft po každém PR, které si někdo jen otevřel — tedy proti pravidlu
  o řádek výš. Je na to ten nejdůležitější test #114.
- **Předvyplněný návrh doplní až snímek pro odeslání** (`submission(for:)`), ne mapa `drafts`.
  Uložená hodnota tak zůstane bez verdiktu i pro restart, a přesto odejde to, co je v potvrzení
  vidět. Vybraný verdikt to nikdy nepřepíše: volba přebíjí návrh.
- **Na vlastním PR se návrh nenabídne** (`isOwnPullRequest`, autor ze seznamu — a když tam není,
  z detailu — proti `Conversation.viewer`; od #333 je autor pro obě otázky na jednom místě,
  `AppStore+Ownership.author(of:)`). GitHub tam bere jedině `COMMENT` (změřeno u #62), takže by předvyplněný
  `APPROVE` vedl k `422`. Dokud konverzace nedorazí, **předvyplňuje se dál** — kdo se dívá, se
  jinde nedozvíme a schovaný návrh u každého PR by byl horší než jedna měřená chyba, která si
  o `Jen komentář` řekne sama.
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
- **Přenesení na nový commit (#69) rozhoduje podle textu, ne podle čísla řádku.** Komentář si
  proto nese **snímek kódu** (`DraftSnapshot`) — bez něj se po novém commitu nedá poznat, jestli
  na tom řádku pořád stojí to, co člověk komentoval, a „stejné číslo“ o kódu neříká nic.
  Porovnává se **otrimovaný** text (změna odsazení je pořád tentýž řádek) a hledá se **nejblíž**
  původnímu číslu, protože stejný řádek (`}`, prázdno) je v souboru víckrát a první nález by kotvu
  odnesl na druhý konec.
- **Čtyři stavy kotvy, ne dva** (`DraftAnchorState`): `fits`, `moved`, `uncertain`, `lost`. Tatáž
  úvaha jako u `ReviewState` — „nevím, co tam bylo“ (draft z doby před #69, který snímek nemá) není
  „ztraceno“ a „posunulo se“ není „sedí“. Tvrdit „sedí“ bez snímku by byl přesně ten **tichý
  přenos**, kterému se #69 vyhýbá.
- **U rozsahu musí sednout oba konce.** Když jeden zmizel, je celý rozsah `lost` — přeanchorovat
  druhý by z něj udělalo něco jiného, než co člověk označil.
- **Výchozí volby drží text.** `lost` míří **do těla** review (s odkazem na kód), ne do koše:
  smazání ručně psané práce musí být rozhodnutí člověka. Odkaz míří na **nový** commit, protože
  proti němu se tělo odešle.
- **`headSha` se přepisuje až přenesením.** Dokud se draft nepřenesl, musí zůstat zastaralý —
  jinak by šel odeslat proti hlavě, na kterou nikdo nekoukal.
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
- **Návrhem z nálezů se verdikt předvyplňuje (#114) — a snímek to musí nést.** Uložený draft
  zůstává bez verdiktu (návrh se neukládá), takže odesílaná hodnota se do snímku doplňuje
  v `submission(for:)`; „co je v potvrzení vidět, to se odešle“ platí dál, jen ta hodnota
  nepochází z disku. Odkud přišla, říká `verdictOrigin` a sheet to napíše větou.
  **Změna proti #66 a #68**, kde tady stálo, že se nepředvyplňuje, protože se odhad aplikace
  nemá dát splést s mým rozhodnutím — odlišit se pořád musí, ale ochranu proti záměně nese sheet,
  ne to kliknutí. Důvod je ve specifikaci.
- **Přenesení na nový commit verdikt nesmí ztratit.** `applyTransfer` vrací **uložený** draft,
  tedy ten bez předvyplněného návrhu — takže si ho `ReviewSubmission.transfer` doplní zpátky.
  Bez toho by review po přenesení odešlo bez `event`u, tedy neodešlo vůbec.
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

Komentář pod PR (#216) drží `AppStore` ve dvou mapách klíčovaných rovnou `PRIdentifier`em
(`pullRequestComments` a `pullRequestCommentStates`) a platí u něj **totéž co u vláken** —
store odesílání spouští, ale cestu ven nedrží (`CommentSubmission`), text se zahazuje s PR mimo
seznam, dvojklik pošle jeden komentář a selhání drží stav i text. Dvě věci jsou jinak:

- **Klíč je PR sám**, ne složený `ThreadKey`: komentář pod PR žádnou jemnější adresu nemá.
- **`CommentActionState` je vlastní typ**, ne `ThreadActionState`. Ten má případy pro vyřešení
  vlákna, které tady nikdy nenastanou — a stav, jehož polovina se nedá dosáhnout, svádí psát nad
  ním větve, kterými nikdo neprojde.

Útratu za review (#148) drží `AppStore` v `dailySpend` nad `SpendLedger`em a platí u ní:

- **Vlastní počitadlo na disku, ne součet z uložených záznamů.** Vypadá to jako druhé místo,
  které se umí rozejít s pravdou, ale je to **jiná otázka**: `ReviewRecord` říká, co běh našel
  proti danému commitu, kdežto tohle říká, co mě stálo utracení session. Rozcházejí se proto
  zákonitě a správně — **zahozený záznam** (#81) i uklizený starý by ze součtu peníze odečetly,
  a číslo, které klesne tím, že zmáčknu koš, je o mém účtu lež. Navíc by se při každém vykreslení
  musel projít a dekódovat celý výpis `reviews/`, protože v paměti je jen `Policy.currentRecords`.
- **Zapisuje se před kontrolou zrušení.** Session, která doběhla, peníze stála, ať už se její
  výsledek uloží, nebo ne — číslo, které zrušením zmizí, by lhalo stejně jako to o řádek výš.
- **Běh bez ceny se počítá jako neznámý, ne jako nula.** Zabitý běh `result` event nemá, takže
  nula by tvrdila, že byl zdarma; drží se proto `unknown` a součet se v řádku označí `≥`.
  Tatáž úvaha jako u `droppedFindings` — utnutá data nesmí vypadat jako úplná.
- **Dotažené běhy z transcriptu (#97) se nezapisují.** Jejich cena nikdy nedorazila (transcript
  `result` event nemá) a den, ve kterém běžely, neznáme — přičíst je k dnešku by byl výmysl.
- **Součet se sráží po každém úspěšném tiku.** Počítá se od půlnoci, takže aplikace běžící přes
  noc by ráno ukazovala včerejšek. Účetní kniha si den pamatuje i pro prázdný den, takže se na
  disk sahá jednou za den, ne jednou za minutu.
- **Osa běhu se ukládá k běhu** (#203). Do té doby žila jen v paměti, takže ji restart smazal
  i se `sessionID`, tedy jedinou cestou zpátky do session (`claude --resume`) — a nálezy, ke
  kterým patří, na disku zůstávaly. Pět pravidel:
  - **Ukládá ji `StoredReviewRun`**, takže je klíčovaná `headSha` jako všechno ostatní a po novém
    commitu zestárne s nálezy. Volitelná, protože starší soubory ten klíč nemají; `nil` znamená
    „osa se neuložila“, ne „nic se nedělo“ — takový běh se v tabu `Průběh` kreslí jako **`bez
    průběhu`** (#242), ne jako nespuštěný: nespuštěno by o doběhlém běhu lhalo a vynechat ho úplně
    znamená, že tab vypíše zrovna ty reviewery, které neběžely.
  - **Osa se ukládá celá, protože se ukládá z proudu** (#308). Do #308 se snímek pro zápis bral
    mimo proud událostí, takže v souboru chybělo `hlásí nálezy` i `doběhlo` — **změřeno na
    skutečné cache: 7 ze 7 os po skutečném běhu** — a rozjezd osy podle toho, jak závod dopadl
    (osy vyrobené v testech konec měly, proto to testy nechytily). Zápis se proto přesunul na
    konec proudu, kde je osa hotová; podrobnosti a zamítnuté varianty jsou v sekci o průběhu
    review výš.
  - **Konec se ale doplňuje dál** (`ReviewerTimeline.completeTail(from:)`, #242), protože soubory
    uložené **před #308** ho pořád nemají — a bez doplnění tvrdil tab `Průběh` `nedoběhlo — běh
    někdo zrušil` nad doběhlým review a `nálezy vůbec nenahlásilo` nad tím, které nahlásilo
    prázdný seznam; chip vedle toho ukazoval `čisto`. Doplňuje se **jen to, co běh sám ví** (jeho
    výsledek a jeho počet nálezů včetně nepřečtených), jen když to v ose není, a **nikdy do
    prázdné osy** — jinak by z chybějícího průběhu vznikl vymyšlený. Běh, který `ReportFindings`
    nezavolal, doplněnou fázi hlášení nedostane: to je vlastní stav a slít se nesmí. Že to nad
    novými soubory nemá co dělat, není důvod to zahodit — staré na disku leží dál.

    **Změna proti #242**, které si tenhle konec doplnilo na čtení s odůvodněním, že „zápis by se
    musel synchronizovat s proudem, a to je continuation navíc v cestě, která se ruší“. Ta cena
    se ukázala jako zbytečná: uložení se **přesunulo do proudu**, takže žádná continuation ani
    synchronizace nevznikla. Doplňování na čtení tím neztratilo předmět (staré soubory), ale
    přestalo být jediným řešením.
  - **Živá osa přebíjí uloženou.** Běžící review si ji drží v paměti, kdežto uložená patří
    předchozímu běhu; ověřeno vloženou regresí (spadne sedm testů).
  - **Ořezává se začátek, ne konec**, a strop je 300 událostí: kdo se do osy dívá po restartu,
    hledá, čím to skončilo. Kolik se ořízlo, se **sčítá mezi uloženími** a je to v hlavičce
    vidět — tiché zkrácení je tatáž past jako `droppedFindings`. **Od #325 je to jeden strop pro
    živou i uloženou osu** (`ReviewerTimeline.entryLimit`), takže co bylo vidět za běhu, je vidět
    i po restartu; podrobnosti v sekci *Souhrn osy a strop na živou osu (#325)*.
  - **`skill`, `sessionID` a cena se neduplikují** — osa je bere z běhu, pod kterým leží.
    Dvě kopie téhož v jednom souboru se rozejdou.
- **Uložená cena má čtenáře — chip revieweera.** Osa v tabu `Průběh` je jen v paměti, takže po
  restartu je prázdná; kdyby cenu četla jenom ona, byl by `StoredReviewRun.usage` stav, který se
  drží a nikdo ho nečte. Chip se staví ze **záznamu**, takže ji v nápovědě ukáže i druhý den.
  Chytila to vlastní revize diffu.
- **V řádku je jen cena**, ne trvání ani počet kol. Součet trvání paralelních session neměří nic
  (tři desetiminutové běhy naráz by daly „30 minut“ za deset uplynulých) a počet kol je trivia.
  Peníze jsou to, co se jinde v aplikaci nedozvím vůbec.
- **Kniha si pamatuje sedm dní zpátky** (#181), ne jen dnešek: sloupcový graf v dashboardu se
  z jednoho čísla nakreslit nedá. Tři pravidla, která u historie platí:
  - **Včerejšek se po půlnoci přesune do historie**, jinak by graf osiřel při každém překlopení
    dne. Soubor bez historie (z doby před #181) se přečte taky, jen s prázdným polem.
  - **Den bez útraty v řadě zůstává.** Kdyby se vynechal, ukázal by graf dva sloupce vedle sebe
    jako dva po sobě jdoucí dny, i kdyby mezi nimi byl týden pauzy — a sloupec by přestal
    znamenat den.
  - **Historie je okno, ne archiv.** Ořezává se na sedm dní; delší by byla jiná otázka („kolik mě
    to stojí měsíčně“) a soubor by rostl o dny, které se nikde nekreslí. Dny se počítají přes
    `Calendar`, ne odečítáním 86 400 sekund — letní čas dělá dny kratší a delší.

Notifikace (#88) drží `AppStore` v `notificationFailure` a `lastDeliveredNotification` a platí
u nich:

- **Že notifikace fungují, musí být vidět** (#138). Hláška z #88 řekne jen to, že je zakázalo
  oprávnění — ale „nic nepřišlo, protože nic nebylo“ se od „nic nepřišlo, protože je něco
  rozbité“ jinak odlišit nedá. Narazilo se na to dvakrát při ověřování M8 a zesílilo to po
  #135, kde notifikace o re-review nepřicházela měsíce a nikdo to nemohl poznat. Řádek proto
  ukazuje **čas posledního doručení**.
- **Posouvá ho jedině `.delivered`.** Odmítnuté oprávnění, selhání systému ani vypnutá událost
  z toho „ohlášeno“ neudělají — jinak by řádek tvrdil, že notifikace fungují, zrovna když
  nefungují. Je to tatáž úvaha jako u snímku ohlášených PR (#85), který se taky přepisuje až po
  doručení; je na to test na každý ze tří případů.
- **Čas jde s titulkem jako jedna hodnota**, ne jako dvě vlastnosti storu: čas bez toho, čeho se
  týkal, se v nápovědě nedá vysvětlit, a dvě vlastnosti se dají rozejít.
- **Pozdější selhání poslední úspěch nesmaže.** Řádek odpovídá na „kdy naposledy něco odešlo“,
  ne na „jak dopadl poslední pokus“ — to říká hláška o nedoručení vedle.
- **Drží se v paměti, ne na disku.** Je to odpověď na „funguje mi to teď“ a k té je čas
  z minulého spuštění zavádějící — puntíky služeb se po restartu počítají znovu ze stejného
  důvodu. Že se počítá od spuštění, proto musí říct **nápověda**: bez toho vypadá `zatím nic`
  po restartu jako porucha, i když se včera ohlašovalo celý den.

- **Odmítnuté oprávnění musí být v okně vidět.** Aplikace kvůli němu nespadne, jen mlčí —
  takže bez hlášky je „nic mi nepřišlo“ k nerozeznání od „nic se nestalo“, a spravit se to dá
  jedině v Nastavení systému, kam aplikace nedosáhne. Tatáž kategorie jako rozbitá
  konfigurace: nesmí položit, nesmí projít tiše. Věta proto říká, **kde** se to povolí.
- **Úspěch hlášku maže.** Oprávnění se dá povolit a příští doručení projde; věta, která by po
  něm zůstala, by posílala hledat vyřešený problém.
- **Doručení bez nastaveného centra si nic nezapíše.** „Odsud se neposílá“ (testy) není
  porucha, o které by se mělo hlásit — jinak by každý test s notifikacemi měl v okně větu
  o tom, že něco nefunguje.
- **Klik otevře záložku, ne výběr řádku** (#409). Do #409 tady stálo jedno přiřazení do
  `selection` — tedy do stavu, který od záložek (#180) v domácí záložce nikdo nekreslí —, takže
  z kliknutí bylo „aplikace naskočila a nic“. Byla to **regrese od #180**: obsluha je z #82–#88,
  kdy výběr řádku otevření byl. Otevírá proto `openTab(_:in:)`, tedy tatáž cesta jako klik
  v seznamu; **tab se u ní nejmenuje**, protože proud kliknutí nese `PRIdentifier`, ne událost —
  člověk se vrátí tam, kde v tom PR skončil.
- **Klik na PR mimo seznam neotevře nic.** Notifikace přežije tik, který PR odklidil, a otevřít
  záložku naslepo by znamenalo prázdnou plochu s hláškou, že PR zmizel; skočit místo toho jinam
  by bylo horší než nechat na obrazovce to, co tam bylo. Okno je vepředu tak jako tak, takže
  kliknutí nezůstane bez odpovědi.
- **Dokud se seznam nenačetl (`status == .notStarted`), otevře se i tak.** Je to zrovna ten
  případ, kvůli kterému má proud kliknutí buffer: aplikaci spustilo právě to kliknutí, takže
  polling ještě neproběhl a **prázdný seznam neznamená „PR je zavřený“, ale „ještě nevím“**.
  Bez toho by se klik z notifikace, která aplikaci spustila, zahodil — tedy přesně ten scénář,
  pro který je celý buffer. Chytila to vlastní revize diffu u #88. Cena je, že do prvního tiku
  stojí v záložce hláška „Pull request zmizel ze seznamu“ (shrnutí ještě není), a je to **vědomě
  přijaté**: obsah se dokreslí, jakmile tik dorazí, a druhá varianta — čekat s otevřením na tik —
  je klik, po kterém se nic nestane, tedy zrovna to, co #409 opravovalo. Selhaný **první** tik
  z toho vyňatý není a je to schválně: rozhoduje `status`, ne `lastSuccess`, protože chybující
  polling je pořád „seznam jsme viděli“ jedině tehdy, když jednou dorazil — a měnit tuhle hranici
  by znamenalo měnit chování bez hlášení z provozu, které by o ní mluvilo.
- **Čí PR to je, se nerozlišuje** (#409). Notifikace se o vlastních PR hlásí jedině o **cizí
  aktivitě** na nich (#335), ale klik na starší notifikaci může přijít i na PR, který se mezitím
  do sekce `Moje PR` (#331) přesunul. Záložka je na sekci railu nezávislá — obsah si bere
  z **plného** seznamu (`summary(for:)`) —, takže zúžení podle autora by tady znamenalo zahozený klik
  za nic. Zúžené gettery (`queuePullRequests`) se tedy téhle cesty netýkají, viz *Které místo chce
  kterou množinu*.
- **Rozhodnutí drží `Policy.notificationClick(on:listed:visible:status:)`**, ne `if`y v obsluze
  proudu: jsou to tři vstupy (v seznamu / vidět po filtru / načteno) a dva z následků se ručně
  vracejí jen těžko (zrušený filtr, otevřená záložka). Store z toho provede, co vyšlo —
  a **filtr ruší dřív, než otevře**: `clearFilter()` jde přes `setFilter`, který výběr srovnává
  s filtrem, takže v opačném pořadí by srovnal i ten výběr, který otevření právě nastavilo.
- **Proud kliknutí se konzumuje ve `keepFresh()`**, tedy dokud žije okno — jako polling
  a monitor dostupnosti. Bez nastaveného centra se task ani nezakládá.

Notifikace o doběhlém review (#82) k tomu přidávají:

- **Posílá se tam, kde se review uzavírá**, ne u ukládání jednotlivého běhu. Reviewery jedou
  paralelně, takže po každém běhu by u tří skillů přišlo „čisté“ a za minutu „3 nálezy“ za
  totéž PR — tři vyrušení za jednu věc. Je na to test se dvěma skilly.
- **Rozhoduje `reviewState(for:)`**, tedy tentýž stav, jaký ukazuje řádek seznamu. Druhý
  výpočet nad běhy by se s prvním rozešel a **řádek a notifikace by řekly dvě různé věci**;
  navíc už ten stav rozlišuje všechno, co #82 chce poznat, včetně „nemám co říct“
  (nereportující běh, ztracený nález).
- **Zrušené review se neoznamuje.** Zrušil si ho člověk, takže o něm ví. Proto notifikace
  **není v `defer`**, ale u každé větve zvlášť — `defer` by ji poslal i po `CancellationError`
  a nikdo by si toho nevšiml. Je na to test.
- **Přeskočené review neoznamuje nic.** Když automat zjistí, že je commit už zreviewovaný,
  vrací se dřív, než se na notifikaci dojde — session se neutratila a nic nového se nezjistilo.
- **Selhaný checkout se hlásí jinými slovy než spadlá session.** Jsou to dvě různé věci
  a vedou jinam (jedna se řeší tlačítkem u repa, druhá u PR) — tatáž úvaha jako u `ReviewState`.
- **Blokující počet se bere z platných nálezů** (`activeFindings`), takže odmítnutý nález
  (#113) nevyrušuje. Text říká i to, když **nic** neblokuje — bez té půlky by „3 nálezy“
  vypadaly stejně vážně jako tři blokující.
- **Skloňuje `Plural.czech`**, ne vlastní `switch`. Byla by to čtvrtá kopie téhož pravidla
  (odznak stavu, chipy, osa) a kopie se rozešly hned: první podoba skloňovala „blokující“
  jedničkou proti ostatním, z čehož vycházelo „3 blokujících“ (nález Copilota na #131).
  Od #200 se skloňuje **sloveso** (`1 blokuje`, `3 blokují`, `5 blokuje`), takže shodné jsou
  `one` a **`many`** — je to tatáž past z druhé strany a je na to tabulka v testu.
- **Rozvržení je titulek → nález → PR** (#200):

  | Řádek | Co v něm je |
  |---|---|
  | titulek | `3 nálezy · 1 blokuje`, u ostatních stavů krátká věta (`Čisté review`, `Review se nepovedlo`) |
  | tělo, 1. řádek | nejzávažnější nález (`correctness: …`), u ostatních stavů detail |
  | tělo, 2. řádek | `owner/repo#123` |

  **Do #200 bylo v titulku `owner/repo#číslo`** a v těle věta o výsledku. Změnilo se to proto,
  že titulek je první, co je vidět, a rozhodnutí „jdu k tomu hned?“ se dělá podle počtu
  a blokujících, ne podle jména repa. Identifikace se z toho neztratila: PR **je v banneru
  vidět** (změřeno, viz níž), notifikace o témž PR systém řadí do jednoho vlákna a klik se
  stejně řídí `PullRequestNotification.pullRequest`, ne textem.

  Jméno PR se skládá přes `description` identifikátoru, takže se číslo nikde neformátuje přes
  locale — z `#21663` by jinak vyšlo `#21 663`. Je na to test.
- **Banner unese čtyři řádky těla, ne dva** (#200) — změřeno v `PRism-d`, ne odhadnuto: zadání
  vycházelo z dvouřádkového banneru, ale macOS 26 ukázal titulek a pod ním čtyři řádky.
  Rozhodující je z toho ale něco jiného: **co se nevejde, systém uřízne i s tím, co je pod tím**,
  takže 140znakový souhrn z banneru vymazal celý řádek s PR. Proto se nález krátí sám
  (`Policy.notificationFindingLimit`, sto znaků, řez na hranici slova) — vlastní tři tečky
  nechají identifikaci naživu, systémové ne.
- **Nejzávažnější nález je `sorted(…).first`** (`Policy.mostSevereFinding`), ne vlastní škála:
  notifikace tak ukáže přesně to, co je po otevření okna první na ráně. Bere se ze **stejného
  záznamu** jako počet blokujících, takže titulek a řádek pod ním nemají jak říct každý něco
  jiného; text je `shortSummary` (přesně na tohle je) se `summary` jako záložkou.
- **Cizí text jde do těla přes `String.singleLine`.** Souhrn nálezu i detail selhání můžou mít
  vlastní zlomy (`CheckoutError.userDescription` lepí výstup `gitu` za prázdný řádek) a jeden
  `\n` navíc odsune PR mimo banner. Chytil to test, ne úvaha.

Notifikace o novém PR (#85) drží stav na disku (`AnnouncedPullRequests`) a platí u nich:

- **Re-review se pozná textem, ne vlastní událostí** (#137). U PR, který jsem reviewoval
  minulý týden, není „Nový PR k review“ pravda — u nového PR jde o první přečtení, u re-review
  o to, co se od mého review změnilo. Vlastní `NotificationEvent` by šel vypnout zvlášť (#86),
  ale je to pátý přepínač za rozdíl, který zatím nikdo vypínat nechtěl; přidat se dá potom.
- **Že PR znám, se pozná z uložených nálezů** (`reviewRecords`), ne z rozdělaného draftu:
  draft může existovat u PR, které se nikdy nereviewovalo, kdežto záznam vzniká jedině
  doběhlým během. Čte se z paměti — plní se při startu z disku a `forget` ho na rozdíl od
  diffu nebo konverzace **neuklízí**, takže PR, který z fronty odešel po mém review, tam
  zůstane. To je zrovna ten případ, kvůli kterému #137 vzniklo.
- **Zahozený záznam (#81) z PR udělá zase novinku**, a je to schválně: zahození znamená
  „tenhle výsledek je k ničemu“, takže chovat se k tomu PR jako k nedotčenému je poctivé.
- **Souhrn se kvůli tomu nerozpadá na dvě notifikace.** Doručení je jedno, takže je jeden
  výsledek — a na tom stojí, že se při selhání zkusí celá dávka znovu jako celek (#87). Dvě
  notifikace by vrátily částečný zápis snímku, tedy tu past, kterou u #132 našel Copilot.
  Kolik z nich je re-review, proto říká **titulek souhrnu** (`3 PR k review (1 znovu)`),
  a jen když nějaké jsou. U jednoho PR se souhrn nedělá vůbec, takže tam se rozdíl pozná
  plným textem — a to je ten případ, kde na něm záleží nejvíc.

- **Hlásí se jen po úspěšném tiku.** Po výpadku sítě je seznam prázdný, takže by se snímek
  vyprázdnil a při zotavení by přišlo úplně všechno — tatáž past jako u `CacheEviction`
  a `ReviewStore.cleanUp`. Je na to test.
- **Snímek se zapisuje až po doručení.** Opačné pořadí znamená, že se PR zapíše jako ohlášené,
  notifikace se nepovede a **už nikdy nepřijde**. Chytil to test, který byl napsaný dřív než
  ta oprava: první podoba zapisovala vždycky.
- **Přechodná chyba snímek nepřepíše, odmítnuté oprávnění ano.** Rozhoduje
  `NotificationDelivery.isWorthRetrying` — opakovat každou minutu něco, co je systémově
  zakázané, je volání za nic, a ta PR se po povolení přečtou ve frontě v okně. Rozlišení bydlí
  na výčtu, ne u volajícího: druhá kopie by u nového případu odpověděla jinak.
- **Odebrání ze snímku smí být hned, přidání až po doručení** (#135). Odeslané review ruší
  `review-requested`, takže PR z fronty odejde — a kdyby ve snímku zůstal, po **re-review** by
  nebyl „nový“ a notifikace by nepřišla. Odebírá proto `newcomers(in:)` sám, kdežto přidává
  jen `remember(_:)`: **odebrání nikdy notifikaci neztratí** (jen umožní budoucí ohlášení),
  přidání před doručením ano. Zápis nemůže zůstat celý na volajícím, protože ten se u tiku bez
  novinek vrací dřív.

  Chytil to **provoz, ne test** — a test na to přitom existoval: ověřoval `AnnouncedPullRequests`
  přímo a prázdný snímek si zapsal ručně, tedy kontrakt, který `AppStore` neplní. Jednotkový test
  byl zelený a integrace rozbitá; proto je od #135 test na celý řetěz přes `AppStore`.
- **Zapisuje se celá fronta bez těch, u kterých doručení selhalo** — ne „všechno nebo nic“.
  Do snímku musí jít i PR, která tam byla už minule (jinak by se ohlásila podruhé), ale kdyby
  jedno selhání zdrželo zápis celý, příští tik by poslal znovu i to, co dorazilo — a při
  opakovaném selhání jedné notifikace by se ostatní posílaly každou minutu. Chytil to Copilot
  na #132; řeší se to snímkem, ne pamětí, takže to platí i přes restart.
- **`notify(_:)` vrací, jak to dopadlo.** Do #85 nevracela nic; bez toho se volající nemá jak
  rozhodnout, jestli zkusit znovu. `@discardableResult`, takže #82 se to netýká.
- **Bez notifikačního centra se snímek nezakládá.** Kdyby se plnil i tak, po zapnutí notifikací
  by první nová PR vypadala jako už ohlášená.

Brána z nastavení (#86) leží v `notify(_:)` a platí u ní:

- **Jedno místo, kterým jde všechno** — jako `PublishScope` u odesílání. Kdyby se ptal každý
  volající, jeden by to zapomněl.
- **Vrací se před `deliver(_:)`**, protože ten si říká o oprávnění: dialog za něco, co je
  vypnuté, je dialog za nic. Je to zadání #86 a pozná se jen tím, že se centra nikdo nezeptal —
  proto je na to test s nulou doručení.
- **Vypnutá událost není selhání doručení.** `notify` vrátí `nil`, takže `isWorthRetrying`
  neplatí a snímek ohlášených PR se **posune** — jinak by se vypnutá událost zkoušela při každém
  tiku dokola, jen tiše.
- **Událost si nese notifikace sama** (`PullRequestNotification.event`), skládá ji `Policy` z
  téhož `ReviewState` jako text. Odvozovat ji u odesílání by byla druhá cesta k témuž údaji.
  Odmítnuté nálezy patří ke `clean` (nezbylo nic k řešení) a **timeout se rozděluje**: s nálezy
  je to `findings` (jsou k přečtení), bez nich `failure` (běh nedoběhl a nic z toho není). Do
  #133 padal celý `timedOut` do `findings`, takže kdo si vypnul selhání, dostával hlášku
  o běhu, který nic nenahlásil — chytil to rozpor mezi textem v nastavení a mapováním.

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
- **Indikátor ohlášení stojí vlevo od puntíků, ale puntík to není** (#138). Odpovídá na tutéž
  otázku („funguje mi to?“), jenže notifikace nejsou služba, u které by se sledoval výpadek —
  proto zvonek, ne barevná tečka. **Vidět je vždycky**, i když se nic neohlásilo: indikátor,
  který se objeví teprve tehdy, když je co ukázat, je ten, o kterém nikdo neví, že existuje.
  V řádku je **jen čas**, celá věta v nápovědě; zadání #138 navrhovalo `naposledy ohlášeno
  v 21:35` rovnou v pruhu, ale ten je úzký a puntíky vedle drží tentýž vzor. Rozhodlo se to
  nad renderem všech tří stavů, ne v návrhu.
- **Vypnuté notifikace jsou vlastní stav** (`vypnuto`), ne `zatím nic`. Obojí by bylo pravda,
  ale druhé by posílalo hledat poruchu, která žádná není.
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
- **Obsah draft panelu scrolluje, ale jen když se nevejde**, a podlaha panelu je **změřená**
  (200 pt). Panel je pruh s výškou, kterou si uživatel vytáhne, kdežto draft má svoje minimum:
  se zastaralým draftem 198 pt, bez banneru 161 (offscreen render `DraftPanel`u u #69). Se starou
  podlahou 120 pt obsah **přetékal přes záložky nad sebou** a po přidání scrollu se scrolloval
  i u vytaženého panelu. Samotné `clipped()` by ho jen schovalo, což je horší polovina téhož
  problému; `minHeight` z měřené výšky drží obojí — dokud se obsah vejde, vyplní panel jako dřív.
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

### Sheet s kódem a s logem (#417)

Jeden sheet (`CodeTextSheet`) a dvě cesty, kterými se do něj přijde: `Ukázat celý log` v akcích nad
koncem logu a *hunk k vybrání* z diffu. Co sheet **dělá**, je u obojího totéž (jeden vybíratelný
text, zalamování, `Zkopírovat vše`, `Zavřít`); jak **velký** se otevře, je vlastnost obsahu —
a rozhoduje o tom čistá funkce `Policy.codeSheetSizing(kind:screen:)`, druh nese `CodeText.Kind`.

**Do #417 se otevíral 560 bodů široký**, tedy v podlaze: bez `presentationSizing(.fitted)` SwiftUI
`idealWidth` u sheetu **zahodí** (změřeno u #327 nad skutečným oknem sheetu, i s oknem 2 000 bodů za
ním). U textu, jehož jediné téma je šířka, to byla ta nejhorší možná odpověď — 66 znaků na řádek,
z nich 29 na timestamp, a **68 %** řádků logu zalomených. Čísla i zlom jsou v sekci 28 návrhu
a u konstant v `App/Policy/CodeSheet.swift`.

| | hunk | log |
|---|---|---|
| otevře se na | **1 180 × 520** | **obrazovka − 152, nejvýš 2 700 × 760** (na 1512b displeji 1 360) |
| podlaha | **560 × 320** — mediánový hunk celý | **820 × 420** — šířka do #292 a 21 řádků |
| kritérium | 91 % hunků bez jediného zalomení; nad 1 180 koupí sto bodů jen +2,8 pb | žádná šířka nestačí (p99 řádku 333 znaků), takže se bere, co obrazovka dovolí |
| obarvení | podle jazyka souboru | **jednou barvou** (155 ms proti 7,9 ms na 8,78MB logu) |
| patička | `Zavřít`, kolik řádků se nevešlo na šířku, `Zkopírovat vše` | `Zavřít`, `Otevřít celý log na GitHubu ↗`, `Zkopírovat vše` |

Čtyři věci, které se u toho dají pokazit potichu:

- **Dva klíče pro uloženou velikost jsou podmínka, ne pohodlí.** S jedním by roztažení logu přes celý
  monitor otevíralo takhle i hunk o devíti řádcích — je na to test, ověřený vloženou regresí (hunk se
  s jedním klíčem otevřel 2 460 bodů široký). Cena: čtyři `@AppStorage` klíče
  (`CodeTextSheet.StorageKey`) a `switch` nad druhem ve dvou getterech.
- **Sheet se rozvrhuje dvakrát a v prvním průchodu má podlahu** (#327). Zápis bez odmlky proto uloží
  podlahu a od druhého otevření se sheet otevírá nejmenší možný — tedy zpátky do té vady, kterou #417
  opravuje. Drží to `CodeTextSheet.resizeSettle` (400 ms); vloženou regresí ověřeno, že se bez ní
  uloží **560 × 320** u hunku a **820 × 420** u logu.
- **Podlaha je to, co sheet dostane, když se ideál pokazí** — proto není nejmenší číslo, které projde,
  ale velikost, ve které obsah ještě obstojí. A **ideál se nikdy nespočítá pod podlahu**: `idealWidth`
  menší než `minWidth` by SwiftUI přebilo podlahou, takže by v rámci stály dvě odpovědi na jednu
  otázku (nastane to u logu na malinké obrazovce, kde `codeSheetWidth` rozhoduje podle displeje).
- **Věta o zalomených řádcích je jen u hunku.** U logu by to byl scan megabajtů při každém přerovnání
  šířky (#224) a „dvě třetiny řádků se nevešly“ nikomu nepomůže. Kapacita řádku se počítá stejnou
  aritmetikou jako tabulka v návrhu (`Policy.codeSheetCharacters`: šířka bez 2× odsazení a 2×
  `lineFragmentPadding`, děleno šířkou znaku měřenou **na písmu**) a je proti skutečnému layout
  manageru ověřená přes pásmo šířek (`CodeSheetWrappingTests`).

**Stráž v `updateNSView` tady není, a je to změřené rozhodnutí** (potvrzuje #393). Roztahovatelný
sheet vypadal jako ten případ, kvůli kterému stráž u bloku diffu existuje — přeměření plochy při
každém kroku tažení znamená průchod tělem sheetu a přesázení by zrušilo rozdělaný výběr. Změřeno na
skutečném okně sheetu (patnáct kroků tažení po 12 bodech): `updateNSView` se **ani jednou nezavolal**
a výběr zůstal, protože SwiftUI aktualizaci nepošle, dokud se hodnota representable nezmění. Stráž by
tedy nešla ověřit vloženou regresí (vyzkoušeno — bez ní tentýž test projde), a to je v `CLAUDE.md`
důvod ji **nedávat**. Výběr při tažení hlídá `DiffBlockUpdateTests.codeSheetKeepsTheSelectionWhileResizing`:
kdyby si tohle view začalo říkat o vlastní velikost (`sizeThatFits`), aktualizace by přišly a ten test
spadne.

Hlavička má **tři řádky** a skládá je `CodeSheetText` (ne sheet sám — ten nemá znát `DiffHunk` ani
`PullRequestCheck`). Třetí řádka má u logu **dvě podoby**: u běžícího jobu snímek s časem, u doběhlého
`log je celý, nic už k němu nepřibude` — doběhlému jobu se log snímkem nazývat nemá, protože slovo
„snímek“ nese informaci jen tam, kde se text pod rukama mění. **Přírůstek se nepočítá** (na rozdíl od
přepisu session, což je lokální soubor): log je na síti, takže by živé číslo byl request na tik —
místo něj je v patičce odkaz na GitHub. Čas ve snímku je `JobLog.fetchedAt`, tedy z chvíle stažení
(hodiny bere store z `TimeSource`, `Policy` zůstává čistá) — čas kliknutí by tvrdil, že je text
novější, než jaký je: leží v paměti od rozbalení checku. Akce jsou v patičce, protože hlavička nese tři řádky a u logu
je jedna z nich věta, po které by tlačítka plavala.

## Okno s novinkami (`App/Views/ReleaseNotes/`)

Scéna `Window` s id `release-notes` (menu aplikace, hned pod `O aplikaci PRism`). Vlevo
historie vydání, vpravo release notes vybraného — **jedno okno nad jedněmi daty**, protože
dvě obrazovky („co je nového“ a „historie“) by se dřív nebo později rozešly.

| Typ | Co dělá |
|---|---|
| `ReleaseNotesWindow` | Id a titulek okna — jedno místo pro scénu i pro položku v menu |
| `ReleaseNotesScene` | Obsah scény; dokud neprošel preflight, není `gh` a okno to řekne |
| `ReleaseNotesMenuItem` | Položka v menu aplikace; `openWindow` se čte tam, kde se používá |
| `ReleaseNotesModel` | Historie, výběr, značka „tohle už jsem viděl“ a rozhodnutí, jestli se má okno po startu otevřít |
| `ReleaseNotesView`, `ReleaseRowView`, `ReleaseNotesDetailView` | Rozdělené okno, řádek seznamu a vykreslené release notes |
| `ReleaseRow` | Vydání převedené na řádek seznamu — texty a odznak `nové`, mimo view a testovatelné |

Věci, které se u toho nemají rozbít:

- **Okno se středí v hlavním okně, ne na obrazovce** (#164) — přes `centeredInMainWindow()`,
  tedy tou samou cestou jako nastavení. Otevírá se z toolbaru hlavního okna, z menu a po
  aktualizaci, takže na velkém (nebo druhém) monitoru by vyskočilo mimo to, kam se člověk kouká.
  Podrobnosti u `WindowCentering` níž.
- **A zůstává před hlavním oknem, dokud je otevřené** (#243) — `keptInFrontOfApp()`, tentýž
  mechanismus jako u nastavení. Bez toho platí u novinek tentýž následek středění: okno je menší
  než hlavní okno, takže za ním zaleze celé a vypadá jako zavřené. Nad cizí aplikací přitom
  neplave — jak aplikace přestane být vpředu, hladina padá zpátky na normální. Podrobnosti
  u `AuxiliaryWindowLevel` níž.
- **Aplikace neví, kolikátá je, a okno o tom mlčí.** `MARKETING_VERSION` je pořád `0.1`,
  zatímco tagy jsou na `v1.1.x` — verze v bundlu tagy nikdy nesledovala. Okno proto mluví
  o tom, **co vyšlo na GitHubu**, a číslo běžící verze nikde nevypisuje; u lokálního buildu
  se ty dvě věci rozcházejí v obou směrech. Druhá cesta (zvednout `MARKETING_VERSION`
  a udržovat ho) by přidala krok do rituálu vydávání, u kterého by stačilo jednou zapomenout
  a značka by lhala — dá se přidat kdykoli potom.
- **Značka je poslední viděný tag v předvolbách**, ne v `config.json`. Je to **stav
  aplikace**, ne nastavení, které si někdo edituje — stejně jako výška spodního panelu.
  Chodí se přes `PreferenceStoring` (`App/Environment/`), ne rovnou přes `UserDefaults`:
  testy by jinak psaly do skutečných předvoleb aplikace a vlastní suite po sobě **nechává
  soubor** v `~/Library/Preferences` — změřeno, `removePersistentDomain` ani `synchronize()`
  to nespraví.
- **Značka se posouvá až tím, že se okno opravdu ukázalo.** Posouvá ji `markAsSeen()`
  z `.task` okna; kontrola při startu ji posune **jen tehdy, když se okno otevírat nebude**
  (první spuštění, nebo není co nového). Je to tatáž past jako u snímku ohlášených PR (#85):
  kdo si zapíše „ohlásil jsem“ dřív, než se to povedlo, tu hlášku **už nikdy nepošle**.
  **Stalo se to v provozu** hned u prvního releasu, který se měl sám ohlásit — okno se
  neotevřelo, značka se posunula a `v1.1.24` se nedala ohlásit už nikdy. Takhle se to samo
  spraví při příštím spuštění.

  **Neposouvá se ani při druhém nabídnutí v témž běhu** (`hasOfferedAfterStart`). Je pořád
  co ukazovat, takže posunout ji tam znamená tutéž chybu o větev vedle: hlavní okno jde zavřít
  a otevřít, takže druhý průchod by vydání odbyl, aniž by ho kdo viděl. Nález Copilota na #142;
  je na to test ověřený dočasně vloženou regresí.
- **Odznaky `nové` se počítají proti značce *před* posunutím** a v rámci běhu se nemění.
  Jinak by zhasly v tomtéž okamžiku, kdy se okno objeví, a nebylo by podle čeho poznat, co je
  nového.
- **Okno se po startu nabídne jednou za běh** (`hasOfferedAfterStart`). Hlavní okno jde zavřít
  a otevřít znovu, čímž se kontrola pustí podruhé — a značka je už posunutá, takže bez pojistky
  by okno vyskočilo pokaždé. Chytila to vlastní revize diffu. Po **selhaném** startu se pojistka
  nespotřebuje: nenačtená historie není nabídnutá historie.
- **První spuštění mlčí** a značku jen založí. Bez toho vypadá po startu jako nová celá
  historie — tatáž úvaha jako u snímku ohlášených PR (#85).
- **Selhání je vidět, ne prázdný seznam.** `.failed(String)` má vlastní stav a v okně důvod
  s tlačítkem `Zkusit znovu`; prázdný seznam by z výpadku sítě udělal „nic tu není“. A okno se
  po selhaném startu **samo neotevře** — vyrušení chybovou hláškou po každém startu bez sítě si
  nikdo neobjednal.
- **Rozdělení se kreslí jen nad načtenou historií.** Prázdný boční panel vedle chyby by říkal
  totéž dvakrát a hůř; dokud není co vybírat, je stav odpovědí na celé okno.
- **Historie se drží v paměti do konce běhu, na disk nejde.** Disková cache by dala offline
  režim, ale je to další store s vlastním formátem a vlastním úklidem — a při startu se stejně
  musí zeptat, jestli nepřibylo vydání. Proto `Release` **není `Codable`**.
- **Na síť se sahá dvakrát za běh, oboje na vyžádání**: jednou při startu kvůli značce, jednou
  při otevření okna (a to už je z paměti). V pollingu ani na pozadí se neptá a do puntíku
  dostupnosti GitHubu to neteče — puntík stojí na tom, co běží pravidelně.
- **Tag se v řádku nečte dvakrát.** Release se v tomhle repu jmenují `v1.1.23 — notifikace
  o re-review`, takže by se tag opakoval a delší polovina by se ořezala dřív; `ReleaseRow` proto
  prefix zahodí. Když název tagem **nezačíná**, nesahá se na něj — hádat, co je oddělovač, se
  vyplatí jen tam, kde je jisté, co se odděluje.
- **Datum formátuje view, ne `ReleaseRow`.** Texty řádku tak nezávisí na locale a dají se
  testovat; tatáž úvaha jako u `FindingRow`. Je u něj **čas**: verze se vydávají po mergnutí
  PR, takže jich v jednom dni vyjde klidně šest a seznam se samotným `5. 8. 2026` šestkrát pod
  sebou o pořadí neříká nic. Nahlášené při zkoušení.
- **Řádky se skládají v těle seznamu**, ne uvnitř buňky. `List` staví řádky líně a mimo
  sledování závislostí rodiče, takže odznak `nové` by se po načtení nemusel překreslit — tatáž
  past jako u stavů v seznamu PR.
- **Menu si o okno říká samo.** `Window` scéna žádnou položku do menu nepřidá, takže bez
  `CommandGroup(after: .appInfo)` by se okno dalo otevřít jedině po aktualizaci — a to je
  ta menší polovina zadání #127. Vedle toho je **tlačítko v toolbaru** hlavního okna, hned
  u ozubeného kola: obojí je o aplikaci, ne o vybraném PR. `Obnovit` zůstává vpravo, protože
  je to jediné z těch tří, co se mačká často.
- **`openWindow` je v toolbaru bočního panelu němá akce.** Tlačítko projde, okno se
  neotevře — proto ho `ContentView` čte v těle okna a do `PullRequestListView` posílá jako
  uzávěr. Ověřeno na běžící aplikaci proti dvěma známým dobrým cestám: `openSettings` ze
  **stejného** toolbaru funguje a `openWindow` s tímtéž id funguje z menu i z `RootView`,
  takže to není chybné id ani chybějící scéna.
- **Esc okno zavře, a jde to schovaným tlačítkem** s `keyboardShortcut(.cancelAction)`, ne
  `onExitCommand`. Ten se váže na fokus a Esc spolkne `List` v bočním panelu dřív, než se
  k němu dostane — ověřeno na běžící aplikaci (okno bylo `AXFocused` a nezavřelo se), zkratka
  na okně zabrala. `opacity(0)` s nulovým rámcem, ne `hidden()`: schovanému view zkratka
  nechodí. Titulek okna nese **jméno okna** a vybraná verze jde do `navigationSubtitle`:
  `navigationTitle` v detailu přebije titulek scény, takže by v liště stálo jen `v1.1.23`
  a nešlo by poznat, o jaké okno jde (taky chyceno na běžící aplikaci).

## `PollingService` (`App/Polling/`)

Drží seznam PR aktuální: v intervalu (default 60 s) se zeptá všech zdrojů, sloučí je přes
`PullRequestList` a publikuje výsledek. `@MainActor` a `@Observable` — jeho stav je to,
co kreslí okno; síťová práce stejně probíhá v podprocesech `gh`.

### Obsah okna dostane změřenou štěrbinu (#472)

`ContentView` staví `VStack { hlavička; HStack { rail; obsah }; stavový řádek }` — a `obsah`
(detail PR, nebo dashboard) byl do #472 **pružné dítě**. Stack se pružného dítěte při každém
rozvržení ptá průzkumnými nabídkami na pružnost (`nil×nil`, `0×0`, `0×∞`, `∞×0`, `∞×∞`, …) a pružný
rámec je **předá dolů** — celým detailem, panelem, pruhem záložek i obsahem tabu. Je to tatáž třída
jako #220 a #361, jen o patro výš: neplatí se za seznam, ale za to, že detail vůbec visí ve stacku.

**Změřeno ablací „slepá kostra“** (`DetailRelayoutMeasurement`): rail, hlavička i stavový řádek
nahrazené obarvenými obdélníky, takže se měří **tvar**, ne sousedé. Data jsou realistická —
konverzace o 200 uzlech, 48 nálezů, 12 checků, 24 commitů, rozdělané review, vlastní PR.

| Scéna | průchod tělem detailu | přepnutí tabu (bez diffu) |
|---|---|---|
| slepá kostra, **pružný rámec** (stav do #472) | **81–89 ms** | **282–295 ms** |
| slepá kostra, **měřená štěrbina** | **7–8 ms** | **56 ms** |
| jen detail, bez kostry | 18 ms | 88 ms |
| skutečné okno **po opravě** | **10–11 ms** | **62 ms** |

Tři věci, které z toho plynou:

1. **Sousedé nejsou vinni.** Skutečný rail, hlavička a stavový řádek stojí proti slepým obdélníkům
   **7 ms** — cenu dělalo vyjednávání, ne jejich obsah.
2. **Nedělá ji ani obsah detailu.** Táž kostra vyšla **81 ms s plným storem a 70 ms s prázdným**
   (jeden běh, aby to nebylo srovnání napříč sezeními) — obsah tedy dělá **14 %** a zbylých 86 %
   struktura.
3. **Je to nejlevnější varianta ze všech tří** — 8 ms je míň než detail bez kostry (18 ms), protože
   se dotazy zastaví u `GeometryReader`u i směrem k hostující vrstvě.

Opravou je `fillingSlot()` na `obsah` v `ContentView` — týž modifikátor a týž důvod jako u líných
seznamů v #361, jen nad celým tabem. **Zpětně to vysvětluje, proč čtyři dřívější pokusy o zlevnění
nezměnily nic**: zkratka na minimum okna, výšky bloků, uzávěry po souborech i úseky řádků zlevňovaly
věci **uvnitř** detailu, kdežto cena byla v tom, kolikrát se do detailu vůbec sestoupí.

### Pět vlastností, ne jeden `PollState` (#472)

Do #472 držel `PollingService` **jednu** sledovanou vlastnost — `var state = PollState()` se všemi
pěti hodnotami uvnitř. `@Observable` sleduje **po vlastnostech**, takže to znamenalo, že se za
každou z těch pěti hodnot hlásí táž změna: `isRefreshing = true` na začátku tiku probudilo
i každého, kdo četl **jen seznam PR**.

A ten čte `AppStore.author(of:)` → `ownership(of:)`, tedy to, čím detail PR pozná, čí PR kreslí.
Tichý tik — takový, po kterém je fronta stejná jako před minutou, tedy skoro každý — proto
překresloval **celé okno včetně diffu**. Naměřeno (`DetailRelayoutMeasurement`, okno 1512×874 nad
vlastním PR s dvaceti čtyřmi nálezy, dvacet tichých tiků):

| | průchody tělem `PullRequestDetailView` | `DiffView` | `DiffRowView` | CPU na tik |
|---|---|---|---|---|
| do #472 (2000 řádků diffu) | **62** | 69 | 10 143 | 551 ms |
| od #472 | **1** | 7 | 1 029 | 343 ms |

Je to tatáž úvaha jako u `DiffViewport` (#469) a tentýž závěr: **co se mění jinak často a čte
jinde, patří do vlastní vlastnosti.** `PollState` zůstal jako **hodnota**, ze které se počítají
odvozené odpovědi (`isStale`, `emptyReason`) — ty na seznamu, stavu i razítku závisejí doopravdy,
takže se skládá jen z nich a `isRefreshing` ani `nextPoll` do něj nepatří.

**Zamítnutá varianta: psát jen změnu** (`if pullRequests != merged { … }`). Vypadá to jako druhá
polovina opravy a **není** — `@Observable` na tomhle toolchainu zápis téže hodnoty **nehlásí**
(změřeno vloženou regresí; pinuje to `PollObservationTests.writingTheSameValueDoesNotWake`). Ten
`if` by tedy byl porovnání navíc, které nic nemění. Z téhož důvodu se nesahalo ani na
`forget(whatIsNotIn:)`, který po tiku přepisuje přes třicet map výsledkem `filter`u: se stráží
i bez ní vychází tvrzení o nezneplatnění stejně.

**Co tím opravené není**: sedm průchodů tělem `DiffView` a tisíc řádků diffu za dvacet tichých
tiků zbývá, a cena tiku spadla jen o třetinu, přestože průchodů tělem ubylo šedesátkrát. Zbytek
leží v **rozvržení okna**, ne v tělech — vlastní práce aplikace je ve `sample`u té fáze **~1,5 %**
hlavního vlákna a **tři zlevnění vedle rozvržení se změřila a zahodila**; viz *Kolik stojí
přerovnání okna* v [`docs/testovani.md`](testovani.md#kolik-stojí-přerovnání-okna-472).

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

**Kdy se zeptáme znovu, zapisuje smyčka** (`nextPoll`, #181), ne odhad ve view. Dashboard to
píše v hlavičce a `lastSuccess + interval` by po prvním rate limitu lhalo — o čekání rozhoduje
`waitBeforeNextPoll()`, tedy backoff. Ruční obnovení hodnotu **neposouvá**: tik mimo pořadí
smyčku nepřeplánuje, takže dokud poprvé neusne, je `nil`.

**Po dobu dotazu je `nextPoll` v minulosti** — zapisuje se až za `refresh()`. Od #237 je v tom
koutě odpočet (`za 43s znovu`), takže to přestala být kosmetika: odpočet by došel na nulu a šel
dál. Drží to `PollingService.isRefreshing`, které `refresh()` zvedne na začátku a v `defer` zase
spustí. **Proč příznak, a ne srovnání s hodinami**: odpočet ve view tiká *bez přepočtu těla*
(`DashboardCountdown` a jeho `TimelineView`), takže `now` v těle platí jen k poslednímu přepočtu —
po probuzení stroje by to byl uplynulý termín, do #260 odpočítávaný nahoru a od #260 zamrzlý na
`0s`. Ani jedno se ukázat nemá. Změna příznaku je naopak observovatelná,
takže hlavička se překlopí na `ptám se…` ve chvíli, kdy dotaz začne. Ověřeno na běžícím okně, po
#260 znovu i s novým formátem: `za 1s` → `ptám se…` → `za 29s` (interval snížený na 30 s, snímky
okna po 1,1 s). U #237 to bylo `za 1 s` → `za 0 s` → `ptám se…` → `za 7 s`, tedy včetně nuly —
hustší burst ji zachytí, protože je vidět tu poslední vteřinu před dotazem.

`defer` je tam kvůli tomu, co se rozbije potichu: zaseknutý příznak znamená `ptám se…` navždycky
a odpočet, který se nikdy nevrátí — na obrazovce k nerozeznání od zaseknuté aplikace.

**Polling netahá detail PR.** Seznam SHA nepotřebuje — potřebuje je až checkout a review,
takže `gh pr view` se volá tam. Zpřesňuje to rozhodnutí z #4.

## `App/Health/` — dostupnost služeb (#31)

Puntíky ve stavovém řádku: jak se vede GitHubu a Claude. Není to modul (viz tabulka modulů
v [`CLAUDE.md`](../CLAUDE.md)) —
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

## `Policy` (`App/Policy/`)

Čisté funkce nad daty, žádné I/O. Testuje se bez mockování a bez binárek.

| Typ | Co dělá |
|---|---|
| `PullRequestList` | Sloučí výsledky zdrojů do jednoho seznamu: dedup podle `PRIdentifier`, řazení |
| `Policy.reviewState(for:)` | Překlad stavu pracovní kopie na stav v řádku PR |
| `Policy.isBlocking(_:categories:)` | Jediný odvozený boolean nad nálezem |
| `Policy.key(of:)` | Identita nálezu napříč běhy — **jediné místo**, kde se klíč skládá |
| `Policy.mergedFindings(_:reporting:)` | Slití **sady** nálezů z jednoho volání `ReportFindings` do toho, co dorazilo dřív (#381): pozdější sada přepíše dřívější **podle místa**, uvnitř sady se neslévá nic a nic se nezahodí potichu. Není to identita z `Policy.key(of:)` a nemá být — tam se páruje napříč běhy |
| `ReviewRecord.activeFindings`, `.dismissal(of:)`, `.setDismissal(_:of:)` | Odmítnuté nálezy (#113) — čtení i zápis na jednom místě |
| `Policy.suggestedVerdict(for:)` | Návrh verdiktu nad `ReviewRecord`. `nil` = není z čeho soudit |
| `Policy.isConclusive(_:)`, `Policy.inconclusiveReason(of:)`, `Policy.inconclusiveReason(for:)` | Dá se z běhu (resp. z celého záznamu) tvrdit čisto, a když ne, tak proč (#383). **Jediné místo**, kde se ta otázka rozhoduje — čte ji návrh verdiktu, chip revieweera i díl proužku |
| `Policy.codeReading(of:)` | Otevřel běh soubor z pracovní kopie? `read` / `unread` / **`unknown`** (#383). Rozhoduje uložená osa, ne cena; `unknown` je odpověď, ne slabší `unread` |
| `Policy.inconclusiveDetail(_:)` | Věta k důvodu — čte ji prázdný tab nálezů, notifikace i nápověda, takže je na jednom místě |
| `Policy.effectiveVerdict(of:suggestion:)` | Který verdikt **platí** a odkud je — moje volba, jinak návrh (#114) |
| `Policy.prefillableSuggestion(_:author:viewer:)`, `Policy.isOwn(author:viewer:)` | Smí se návrhem předvyplnit? Na vlastním PR ne. Samo porovnání dělá od #330 `ownership(ofAuthor:mine:)` — na „je to moje?“ nesmí být dvě odpovědi |
| `Policy.ownLogins(viewer:configured:)`, `Policy.ownership(of:mine:)`, `Policy.ownership(ofAuthor:mine:)` | Čí je PR (#330) → `PullRequestOwnership`. **Množina loginů**, ne jeden řetězec (viewer + volitelný seznam z konfigurace), porovnání bez ohledu na velikost písmen, **prázdná množina znamená všechno cizí** |
| `Policy.tracksOwnPullRequests(in:mine:)` | Je mezi zdroji ten, který vlastní PR přináší (#330)? Pozná `author:@me` i vypsaný login; `-author:` ani `involves:` ne |
| `Policy.pullRequests(_:ownedBy:mine:)` | Seznam zúžený na jednu stranu (#331) — sekce `Moje PR` a její blok, od #332 i **fronta** (`.theirs`) a všechno, co o ní něco tvrdí. **Nesahá na pořadí**, jako `filtered(_:by:)`; a **nesmí na něm viset úklid ani nastavení** |
| `Policy.ownListEmptyReason(poll:tracksOwnSource:knowsViewer:visible:hidden:)` | Proč je sekce `Moje PR` prázdná (#331) → `ListEmptyReason`. **Tři prázdna navíc** proti frontě: chybějící zdroj, nenačtený login, „nic vlastního otevřeného“. `poll(.noPullRequests)` odsud nevypadne nikdy |
| `Policy.ownPullRequestsAwaitingMove(_:records:conversation:handoff:head:)` | Kolik vlastních PR **čeká na tah** (#331) — obsah odznaku a věty na kartě. Od #334 se ptá „zbývá tu něco, co jsem nepředal?“ a rozhoduje `Policy.handoff`; **spodní hranice**, protože konverzace i hlavy jsou v paměti jen u PR, do kterých se kliklo. Konverzace, razítka a hlavy se berou **uzávěry, ne slovníky**: odznak čte SwiftUI při každém překreslení okna, takže mapa všech načtených diskuzí by byla kopie za odpověď o vlastních PR |
| `Policy.handoff(_:record:conversation:head:commits:activitySince:)` | Co zbývá předat (#334) → `HandoffReport` (stav, `pending`, identity nové diskuze, zastaralé nálezy, počet commitů) a od #335 i **cizí aktivita** od minule. **Jediné místo, kde se rozhoduje, co je nové** — čtou z něj odznak v railu, pilulka `N k předání` v řádku i panel |
| `Policy.foreignActivity(in:since:)`, `Policy.activityBaseline(lastVisit:lastNotice:)` | Co na vlastním PR udělal někdo jiný (#335) → `ForeignActivity` (cizí komentáře a review, **bez mých vlastních**) a proti čemu se to počítá — **pozdější** z návštěvy a oznámení. Staví na `changes(in:since:)`, tedy na téže funkci jako pruh „od minule“; commity v tom nejsou (na vlastním PR je push obvykle můj) |
| `Policy.activitySweep(of:mine:loadedAt:now:lastSweep:interval:limit:)`, `Policy.activitySweepInterval`, `Policy.activitySweepLimit` | Na které vlastní PR se v tomhle tiku zeptáme na konverzaci (#335) — **cena celého issue**: předfiltr podle `updatedAt` (klidný den = nula dotazů), vlastní pětiminutový interval a strop tři PR na průchod. `mine` **bez výchozí hodnoty**, jako u automatu |
| `Policy.isReported(_:on:)`, `Policy.activityKind(of:isReReview:)` | Brána dění (#414): o čem se **hlásí vůbec** — tatáž pravidla jako u notifikací (#332), lámaná podle druhu. **Jediné místo**, kde ta otázka je; bez ní by z dění byl obchvat pravidla „o vlastním PR se nehlásí“ |
| `Policy.newPullRequestActivity(…)`, `Policy.reviewActivity(…)`, `Policy.foreignActivityEvent(…)`, `Policy.staleFindingsActivity(…)`, `Policy.departureActivity(…)` | Řádek dění na druh (#414) → `ActivityEvent?`. Text si berou z **týchž** funkcí jako banner (`reviewNotification`, `notificationDetail`, `activityHeadline`), takže se nad tímtéž během nemají čím rozejít; identita je deterministická a u zastaralých nálezů klíčovaná **hlavou** |
| `Policy.activityLog(_:adding:limit:)`, `Policy.activityLimit` | Vložení do záznamu (#414): od nejnovějšího, bez duplicit, se stropem **200 položek**. **Jedno místo pro disk i paměť** — dvě implementace by znamenaly jiný záznam na obrazovce než v souboru |
| `Policy.activityFeed(_:since:now:calendar:)`, `Policy.unreadActivity(_:since:)`, `Policy.activityBadge(unread:isActive:)` | Řádky dění po dnech se značkou poslední návštěvy, počet nepřečtených a odznak sekce (#414). **Bez značky je nové všechno** (opačně než u konverzace); odznak na aktivní sekci mlčí, protože by v railu překryl ikonu |
| `Policy.destination(of:)`, `Policy.tone(of:)`, `Policy.symbol(of:)`, `Policy.showsSilentChip(_:announced:)`, `Policy.gitHubURL(of:)` | Co se u řádku dění kreslí a kam vede (#414). Chip **bez banneru** jen u druhů, které banner umí; jediný druh vede z aplikace **ven**, a adresa se skládá z identity, protože shrnutí v paměti být nemusí |
| `Policy.showsRelativeTime(of:now:)`, `Policy.activityTime(of:now:at:calendar:)` | Čas u řádku dění (#414, #443) — relativní do dvou hodin, pak hodinami, a **jestli si řádek nese den** (`ActivityTimeLabel`, `ActivityRowPlace`). V sekci ho nese hlavička dne, na dashboardu ho nemá kdo nést, takže by `v 7:58` u včerejší události tvrdilo dnešní ráno. Relativní podobu skládá **view**, protože se v okně přepočítává sama |
| `Policy.activityHeaderSentence(lastVisit:hasEvents:now:calendar:)`, `Policy.visitLabel(_:now:calendar:)`, `Policy.showsRelativeTime(of:now:)`, `Policy.commitsAfter(_:in:)`, `Policy.activityEmptyState(…)` | Věta v hlavičce dění, popisek návštěvy (jedno místo pro větu i pruh), kdy se čas píše relativně, počet commitů po hlavě nálezů a **čtyři prázdna, která se nesmí slít** (#414) |
| `Policy.activityNotification(for:activity:)`, `Policy.activityHeadline(_:)` | Text hlášky „ozval se někdo na mém PR“ (#335): titulek s počtem a druhem, pod ním **ta nejnovější věta** a na třetím řádku PR. Titulek skládá **totéž místo** jako text v řádku seznamu (`od minule`), aby se ty dvě věty nerozešly |
| `Policy.agentPromptItems(findings:dismissals:conversation:)` | Všechno, co se dá na vlastním PR předat agentovi (#333) → `[AgentPromptItem]`. **Nefiltruje podle voleb** — z téhož seznamu se počítají i čísla u vypnutých voleb. Vynechá jedině prázdnou obálku review (bez verdiktu i bez prózy), stejně jako `overview` |
| `Policy.agentPromptSelection(for:findings:dismissals:conversation:diff:blocking:options:toggled:only:)` | Hotové zadání **i seznam položek, ze kterého vzniklo** (#333, #377) → `AgentPromptSelection`: text, inventář (co všechno je), co je v textu, identity předaných položek (#334), kolik blokuje, jestli byla načtená konverzace — a grupy se zaškrtávátky. `only:` zúží text na vyjmenované položky (`Sestavit i tak (jen nové vlákno)` po pushi). **Jedno volání na obojí schválně**: počet vybraných v hlavičce sheetu se musí rovnat počtu položek v textu. Do #377 se to jmenovalo `agentPrompt(for:…)`; komu stačí text, bere `.prompt` |
| `Policy.agentPromptIncludes(_:options:conversation:toggled:)`, `Policy.agentPromptExclusion(of:options:conversation:)` | Je položka v textu, a když ne, **proč** (#377) → `AgentPromptExclusion`. Jediné místo, kde se to rozhoduje; `toggled` je **odchylka** od předvybraného, ne seznam vybraných (jako u #185) |
| `Policy.summarizesDiff(_:)`, `Policy.hasNoContent(_:)` | Převypráví souhrn jen diff (**jediná heuristika**, vlastní soubor, pozná se na nadpisu `Pull request overview`), a zbylo by z něj po odstranění nadpisů něco? (#377) |
| `Policy.agentPromptGroups(_:options:conversation:toggled:blocking:)`, `Policy.pickDisclosure(of:toggled:)` | Položky po druzích do seznamu v sheetu (#377) — čtyři grupy s počtem `2 z 3` —, a jak je položka rozbalená (`.none` = nenese text, takže bez šipky) |
| `Policy.agentPromptSections(_:blocking:)` | Rozdělení po souborech (#333): **sekce bez souboru první**, pak soubory (blokující první, zbytek abecedně), uvnitř podle řádku |
| `Policy.agentPromptText(for:sections:diff:withHunks:blocking:isConversationLoaded:)`, `.agentPromptHeading(of:inFileSection:blocking:)`, `.unifiedText(of:)` | Sazba markdownu (#333) — hlavička s hlavou PR, nadpisy s původem, diff hunk ve fenced bloku |
| `Policy.agentPromptFileName(for:)` | Navržený název souboru (#333): `PRism-324-zadani-9c1de02.md` — repo, číslo PR a hlava, bez lomítka |
| `Policy.reviewPanelTabs(for:)`, `Policy.reviewPanelTab(_:for:)` | Které segmenty panelu se kreslí a jak se přeloží vybraný tab, který na tomhle PR není (#333). **Nikdy `draft` a `agentPrompt` naráz** |
| `Policy.groups(of:)` | Shoda reviewerů na `file:line` → `FindingGroup` s odznakem `2×` |
| `Policy.disclosure(of:categories:toggled:)`, `Policy.disclosureKey(of:)` | Jak je nález u kódu rozbalený (#185): blokující rozbalený, ostatní značka, odmítnutý nikdy — a čím se místo klíčuje |
| `Policy.chips(for:skills:running:)` | Stav reviewerů pro horní lištu — `ReviewerChip` i s **cenou** z uloženého běhu |
| `Policy.projectLanguages(in:)` | Odhad jazyka projektu z výpisu verzovaných souborů |
| `Policy.mountBand(visible:)`, `Policy.isBlockMounted(_:band:)` | Ve kterém pásu obsahu má blok kódu živý `NSTextView` (#469) — laznost diffu, kterou do #469 dělal `LazyVStack`. Pás je **kvantovaný na násobky výřezu**, protože ho čte každý blok v seznamu, a je **nejmíň o výřez širší** na každou stranu. `nil` (blok se nikdy nekreslil) znamená **nasadit** |
| `Policy.pinnedFileHeader(files:top:headerHeight:)` | Která hlavička souboru se drží u horní hrany výřezu a o kolik je vysunutá (#469) — náhrada za `LazyVStack(pinnedViews:)`. **Jedna hlavička přes výřez**, ne posun u každé; na konci souboru se vysune, aby ji hlavička dalšího vytlačila |
| `Policy.hoverChange(from:to:)` | Jestli se hover má zapsat do `@State`, nebo se stav **nechá být** (#358). Generické nad `Equatable`, takže platí pro `HoveredCell?` (split) i `Int?` (pod sebou) — jedna podmínka, ne dvě kopie. Vrací hodnotu, **ne `inout`**: `@State` je počítaná vlastnost, takže `&hovered` by prošlo setterem i beze změny, a špiní právě setter |
| `Policy.reviewPromptTemplate(from:)`, `.reviewPromptProblems(in:)`, `.reviewPromptBody(template:skillID:baseSha:)`, `.reviewPromptCore(intentPath:)`, `.reviewPrompt(template:skillID:baseSha:intent:)` | Prompt review ze šablony v nastavení (#281, `ReviewPromptTemplate`): prázdná šablona → výchozí, chybějící zástupný text → `Problem`, dosazení hodnot a **vždycky připojené jádro** — od #120 i s větou o souboru se zadáním. Skládá to **jedno místo**, protože týž text potřebuje běh, `Zkopírovat příkaz` i náhled v nastavení |
| `Policy.intentLinks(in:)`, `.intentBrief(of:description:links:)` | Zadání pro reviewera (#120, `ReviewIntent`): odkazy na Linear issue z cizího textu (dedup podle identifikátoru, pořadí prvního výskytu) a soubor v Markdownu, který se z nich složí. `nil` = nebylo co uložit |
| `Policy.reviewTimeout(minutes:)`, `.reviewTimeoutMinutes(from:)`, `.reviewTimeoutProblem(in:)` | Časový limit běhu z nastavení (#320, `ReviewTimeout`): sražení do mezí 5–60 min a pojmenování hodnoty, která je mimo ně. **Jediné místo, kde se sráží** — pole v nastavení, globální hodnota i override per repo mluví o týchž mezích |
| `Policy.automaticallyReviewable(in:configuration:mine:considered:running:)` | Které PR má automat spustit — bez rozpočtu, ten je stavový. **Vlastní PR nevydá nikdy** (#332), a `mine` proto nemá výchozí hodnotu: zapomenutý parametr by to pravidlo tiše vypnul |
| `Policy.sorted(_:)`, `Policy.sections(_:)` | Pořadí nálezů pro UI a jejich rozdělení po kategoriích |
| `Policy.matches(_:_:)` | Patří vlákno (nebo můj rozdělaný komentář) k tomuhle řádku diffu — **jedno místo** pro výběr i umístění |
| `Policy.inserting(_:intoThread:of:)`, `Policy.applying(_:to:)` | Zápis odeslané odpovědi a vyřešení do načtené konverzace; `nil` = vlákno tam není |
| `Policy.linesWithSeveralComments(in:)` | Na kolika řádcích draftu je víc komentářů — z každého budou samostatná vlákna, ne odpověď |
| `Policy.overview(of:renderedIn:)` | Co patří do tabu `Přehled`: review, komentáře pod PR, vlákna bez kotvy a **události časové osy** (#171), chronologicky (`ConversationEntry`) |
| `Policy.displayableEvents(_:)` | Které události se kreslí — zavření po mergi zahodí, zbytek nechá (#171) |
| `Policy.filtered(_:by:isBlocking:)`, `Policy.filterOptions(in:filter:)`, `Policy.listEmptyReason(poll:visible:hidden:)` | Filtr seznamu PR (#117): zúžení, nabídka hodnot sjednocená s aktivním filtrem — **s počtem PR u každé položky** (#199), počítaným z plného seznamu, takže zapnutý filtr čísly nehne — a důvod prázdna, ve kterém **chyba načtení vyhrává nad filtrem**. Od #332 z něj vyjde `poll(.noPullRequests)` i tehdy, když je prázdná jen **fronta** (tik přinesl jen vlastní PR) — jinak by v okně zbyl prázdný seznam bez věty. **`isBlocking` je od #371 uzávěr bez výchozí hodnoty**: osa „jen blokující“ stojí na uloženém záznamu, který shrnutí PR nenese, a mlčky dosazené `false` by nad zapnutou osou vrátilo prázdný seznam — tedy nerozeznatelně od „nic tu není“. Ptá se na něj až tehdy, když osa běží |
| `Policy.summary(of:records:drafts:categories:)` | Souhrn fronty (#155) — počítá **PR, ne nálezy**, a blokující bere z `blockingCount`, tedy bez odmítnutých. Volající mu od #332 posílá **frontu** (`queuePullRequests`), ne celý seznam |
| `Policy.blockingCount(in:categories:)` | Kolik **platných** nálezů záznamu blokuje. Bydlí u `isBlocking`, protože se na to ptají dvě místa — notifikace a řádek seznamu |
| `Policy.mostSevereFinding(in:categories:)` | Nález, kterým se začíná (#200) — první ze `sorted`, tedy ten nahoře v panelu. Vlastní škála závažnosti z toho nevzniká |
| `Policy.queueRow(for:categories:)` | Odvozená čísla pro řádek seznamu (#172): kolik blokuje a jak se nálezy rozdělily mezi reviewery (`QueueRow`, `ReviewerShare`) |
| `Policy.dashboard(pullRequests:records:drafts:categories:since:mine:conversation:handoff:head:tracksOwnSource:activity:lastVisit:activityEmpty:)` | Podklad startovní obrazovky (#181): **pět** karet od #331 (`Dashboard.MineCard` nese počet, „čeká na tah“ a `isTracked`) a rozpad nálezů podle revieweera (`Dashboard`, `ReviewerShareOfFindings`). Karta `Moje PR` se počítá **tady, ne vedle** — dashboard je jeden snímek, který si view bere jednou za překreslení. `ReviewerShareOfFindings` nese od #383 i `isConclusive`: **nula v legendě není čisto**, takže puntík zezelená jedině tehdy, když měl reviewer v okně aspoň jeden průkazný běh — jinak je šedý jako díl proužku u řádku. Od #443 nese snímek i blok `Dění` (`Dashboard.activity`) — tentýž důvod: druhý getter na jednu buňku by znamenal druhý průchod záznamem při každém průchodu tělem |
| `Policy.byUrgency(_:)`, `Policy.urgency(of:)` | Pořadí obou front na dashboardu (#181, #331) — podle závažnosti, ne podle času (`QueueEntry`). Vlastní PR se řadí **tou samou funkcí**: blokující nález je i u nich to, co si žádá pozornost první |
| `Policy.dashboardBlock(_:of:)`, `Policy.destination(of:)`, `Policy.dashboardRowLimit` | Strop **pěti řádků** na blok dashboardu i text patky (`DashboardBlock`, #371) a kam vede která karta (`DashboardCard` → `DashboardDestination`). Strop je **řez, ne řazení** a **o kresbě, ne o množině** — karta nad blokem dál počítá celou frontu. Rozřazení bloku dělá `PullRequestOwnership`, tedy tentýž typ jako obě fronty; `destination(of: .spend)` je **`nil`**, protože útrata není seznam, na který by se dalo přepnout |
| `Policy.dashboardActivity(_:since:empty:)` | Blok `Dění` na dashboardu (#443, `DashboardActivity`): nadpis s počtem **nepřečtených z celého záznamu**, pět nejnovějších řádků, patka `Zobrazit celé dění +37 →` a jedna věta místo řádků, když je prázdno. Strop je tentýž `dashboardRowLimit` jako u front a patku nese **týž `DashboardBlock.Footer`** — druhá kresba patky by se s tou první rozešla. Značka poslední návštěvy jde dovnitř jako **vstup**, blok ji nikdy neposouvá |
| `Policy.shortReviewerNames(of:)` | Jméno revieweera do úzkého místa (#182) — zkrátí `plugin:skill`, ale jen když zůstane jednoznačné |
| `Policy.resumeCommand(sessionID:)`, `Policy.terminalSession(of:)` | Čím se session obnoví a jestli ji dráha umí pustit v Terminálu (#453) → `TerminalSession`. **Jeden příkaz pro obojí** — `⧉` ho kopíruje, `▶` pouští. `nil` = tlačítko se **nekreslí**, a podmínkou je `session_id` **i pracovní strom**: `claude --resume` hledá vlákno podle adresáře, takže bez něj by okno jen oznámilo, že takové vlákno nezná |
| `Policy.timelines(of:)` | Osy běhů z uloženého záznamu (#203); běh bez uložené osy se vynechá |
| `Policy.shortcutYieldsToTerminal(_:_:)` | Ustupuje zkratka okna terminálu v zásuvce (#459)? Pravidlo je jedno: **co nemá `⌘`, patří terminálu** — širší než poznámka 110 z návrhu, která mluví o `Control`u, protože hranice kolem jednoho modifikátoru by nechala venku `⎋` a `⌥↑`/`⌥↓`. Jedinou výjimkou je `` ⌃` `` sama a rozhoduje o ní **akce, ne kombinace** |
| `Policy.terminalDrawerHeight(stored:available:)`, `terminalDrawerResize(from:by:available:)`, `terminalDrawerStoredHeight(stored:measured:)` | Výška zásuvky (#459): otevření z uložené hodnoty s ořezem **při použití**, tažení počítané **z výšky na začátku tahu** (jinak se přetažení za strop nasčítá a zásuvka se přestane vracet) a rozhodnutí, jestli zapsat. Nad zásuvkou vždycky zůstane `terminalDrawerContentFloor` — jinak by z ní byla ta devátá záložka |
| `Policy.terminalWorkingDirectory(worktree:clone:)`, `terminalDirectoryLabel(_:home:)` | Kde shell startuje (#459) — **pracovní strom review** má přednost, protože `claude --resume` session najde jedině v adresáři, ve kterém běžela; jinak bare klon. Existenci na disku ověřuje volající (`Policy` nesahá na I/O). Zkrácení na `~` bere domov **argumentem**, ne z prostředí, a zkracuje jen celý prefix po hranici složky (`/Users/ondrej` se nesmí zkrátit kvůli domovu `/Users/ondra`) |
| `Policy.terminalShell(_:)`, `terminalEnvironment(_:)` | Co se v zásuvce spustí (#459): shell ze `SHELL` (relativní se zahazuje) s `argv[0]` **s pomlčkou**, tedy login shell — bez toho by v zásuvce nebylo nic mimo `/usr/bin`, protože **`PATH` se schválně nepředává**. K tomu `TERM=xterm-256color`, `COLORTERM=truecolor` a UTF-8 locale |
| `Policy.resumeNotice(_:in:)`, `slotsFullNotice(_:)` | Co se řekne po `▶` (#460) → `TerminalCommandOutcome`. `nil` = **mlčet**: co se povedlo, je vidět v zásuvce, která se zrovna otevřela. Zbylé konce vidět nejsou — `busy` je relace, ve které se nic nezměnilo, `noShell` prázdná plocha a plný strop **nevzniklá záložka** —, takže by `▶` bez věty vypadalo jako tlačítko, které nic nedělá. Věta **jmenuje relaci**, protože jich zásuvka drží víc |
| `Policy.terminalSlotAdmission(of:in:states:limit:)`, `terminalSlots(_:adding:evicting:)`, `terminalSlotAfterRemoval(of:from:)` | Kdo smí do zásuvky (#460) a co kvůli němu odejde. **Vytlačuje se jedině neběžící relace, a vždycky nejstarší**; když všechny běží, nová **nevznikne**. Pořadí je pořadí vzniku — přepínač se nemá přeskládat pod rukama |
| `Policy.terminalSlotTitle(_:)`, `terminalSlotMark(_:)`, `terminalSlotHelp(_:state:)`, `terminalSlotRows(_:active:states:)` | Co je na záložce přepínače vidět (#460) → `TerminalSlotRow`. Jméno dráhy, ne `session_id`; puntík má **tři** stavy, i když návrh kreslí dva, a **návratový kód žije v nápovědě** — do puntíku se nevejde a tři kódy do hlavičky taky ne |
| `Policy.terminalWheelReport(deltaY:reportsMouse:rows:)`, `terminalWheelLines(deltaY:rows:)` | Kolečko nad plochou terminálu (#478) → `TerminalWheelReport`, kde `nil` = **nehlásit a rolovat historii**. Nese i **počet**, protože hlášení myši umí jen „cvaklo“ a rychlost je tedy v tom, kolikrát se pošle. Křivka je **opsaná ze `SwiftTermu`** (`calcScrollingVelocity` je `private`) a stupeň se určuje z celé části, ne ze zaokrouhlení. **Nula se nehlásí** — trackpad umí poslat událost s nulovým posunem |
| `Policy.terminalViewportPin(row:atBottom:)`, `terminalViewportRewind(pinned:current:)` | Kde výřez zůstane, když pod ním přiteče výstup (#478). Existuje proto, že `Terminal.userScrolling` se v `SwiftTerm 1.11.2` **nikdy nenastaví**. **Dole se nezaklesává** (tam je „jet s výstupem“ správně) a vrací se jedině **dolů → nahoru**, aby rolování mezitím nikdy nepřebilo |
| `Policy.quitPrompt(reviews:terminals:)` | Na co se aplikace zeptá při ukončení (#94, #264, #459) → `QuitPrompt`. `nil` = **neptat se**. Věty se liší podle toho, co běží: „Běží 2 věci“ nedává důvod kliknout na Zpět. A **neslibují víc, než co data unesou** — z review se dá dotáhnout, co reviewer nahlásil, kdežto výpis shellu se nikam neukládá |
| `Policy.summary(of:)` (checky), `Policy.sorted(_:)` (checky) | Souhrn a pořadí kontrol z GitHub Actions (#209) — nejhorší stav vyhrává, spadlé nahoru |
| `Policy.checksTab(checks:failure:)` | Co je v tabu `Kontroly` k vidění (#306) — čtyři stavy z šesti kombinací vstupů (`ChecksTabState`). Neprázdný seznam přebíjí poruchu, porucha přebíjí obě prázdna. **Nahradila `Policy.tabs(hasChecks:)`** (#215), která vracela zúžený pruh záložek: od #306 se kreslí všech sedm vždycky, takže seznam záložek není funkcí dat a rozhodovat se má **obsah** tabu |
| `Policy.checksBadge(of:)` | Odznak u záložky `Kontroly` (#215) — spadlé červeně s počtem, běžící puntíkem, zelené a přeskočené bez odznaku. Bere **stav tabu**, ne `ChecksSummary` (#306): jeden `guard` na začátku drží prázdnou kapsli i nulu mimo pruh nad nenačteným, prázdným i spadlým stavem |
| `Policy.commitsTab(commits:failure:)` | Co je v tabu `Commity` k vidění (#316) — **tři** stavy z šesti kombinací vstupů (`CommitsTabState`). Neprázdný seznam přebíjí poruchu, porucha přebíjí nenačteno i prázdno, a **prázdné pole bez poruchy je samo porucha**: pull request bez commitů neexistuje, takže klidná hláška o prázdnu by tvrdila nemožný stav. Jediný řádek, ve kterém se liší od `checksTab`. Je to zároveň jediná cesta seznamu do okna, takže se v ní **otáčí pořadí** (`commitsNewestFirst`) |
| `Policy.commitsNewestFirst(_:)` | Pořadí, ve kterém se seznam commitů kreslí (#316) — **od nejnovějšího**, otočením proti návrhu, který měl „od nejstaršího, jako na GitHubu“. V okně se PR nečte od začátku, ale od toho, co přibylo naposled (tentýž pohyb jako pruh „Od tvé poslední návštěvy“ a fakta nahoře v `Přehledu`, #280). **Otáčí, neřadí**: pořadí z API je topologické, takže `sorted(by: committedAt)` by po rebase nebo cherry-picku postup rozházel |
| `Policy.commitsBadge(of:)` | Odznak u záložky `Commity` (#316) — prostý počet, a jen nad seznamem. Tichá kapsle: kolik je commitů, je množství, ne upozornění; nad nenačteným ani spadlým stavem **nic**, protože nula by tvrdila, že se spočítalo |
| `Policy.headCommit(in:head:)` | Který řádek nese pilulku `hlava` (#316). Rozhoduje **`headSha` z detailu, ne pozice v poli** — „nahoře“ a „hlava“ nejsou totéž, jen nad čerstvým seznamem vycházejí nastejno: po pushnutém commitu je seznam o krok pozadu a nad stropem API v něm hlava není vůbec. Nálezy jsou klíčované `headSha` (tvrdá podmínka č. 5), takže by to bylo tvrzení, ne dekorace; hlava mimo seznam → **nic se neoznačí**. Bez známé hlavy (detail ještě nedorazil) platí definice endpointu: GitHub vrací od nejstaršího a `commitsNewestFirst` to otáčí, takže **první** — jediný okamžik, kdy rozhoduje pozice |
| `Policy.commitsHeadline(count:)`, `Policy.commitNoun(_:)` | Věta nad seznamem commitů (#316) ve **dvou kusech** (`CommitsHeadline`), protože počet je tmavý a polotučný a zbytek tlumený. Skloňování má tři tvary (`1 commit` / `2 commity` / `7 commitů`) — `1 commitů` je jeden ze stavů, které se podle zadání nesmí slít. **Pojmenovává pořadí** (`· od nejnovějšího`), takže se s ním musí měnit — jinak okno lže o tom, co ukazuje. Na **stropu API** (250) věta řekne, že seznam nemusí být celý |
| `Policy.openCommit(_:in:)` | Který commit je rozkliknutý (#317) — hledá se **podle sha v čerstvém seznamu**, ne podle uložené pozice. Po force pushi umí commit z PR zmizet a tab pak spadne zpátky na seznam; kreslit dál jeho hlavičku by znamenalo obrazovku, ze které se nedá poznat, že už neplatí. Tatáž úvaha jako u `headCommit(in:head:)` |
| `Policy.commitDiffTab(_:of:)` | Co je vidět místo seznamu (#317) — čtyři stavy `CommitDiffTabState`. **Cizí sha je `loading`, ne prázdno**: v okně leží nejvýš jeden diff commitu na PR, takže hned po kliknutí na jiný commit tam ještě chvíli je ten předchozí, a nakreslit ho pod novou hlavičkou by byl diff, který k ní nepatří. Prázdný diff je **`nothing` s větou**, ne porucha |
| `Policy.emptyCommitDiff(isMerge:)` | Proč je diff prázdný (#317) — **dvě věty**, protože u sloučení je prázdno vlastnost toho, jak se diff počítá, a u obyčejného commitu vlastnost commitu. Obě říkají „není to porucha“. Změřeno na `keboola/job-queue#727`: prázdno vracejí **prázdné commity** (`--allow-empty`), sloučení tam prázdná nebyla — takže se rozhoduje z `isMerge`, ne z dohadu, co je běžnější |
| `Policy.commitDiffFacts(of:)`, `Policy.commitPosition(of:in:)`, `Policy.commitURL(of:in:)` | Čísla a adresy do hlavičky rozkliknutého commitu (#317): počet souborů se skloňováním a `+X −Y` **ze staženého diffu** (tedy zadarmo), `2 ze 7` v pořadí, ve kterém je seznam **nakreslený**, a adresa commitu na GitHubu přes `URLComponents` (jako `permalink`) |
| `Policy.jobID(from:)` | Číslo jobu z odkazu na check (#214). Funguje i jako check-run ID pro anotace; `…/runs/<id>` bez `/job/` je **běh**, ne job, takže `nil` |
| `Policy.strippingANSI(_:)`, `Policy.strippingTimestamps(_:)` | Čistka logu (#214) — bez nich je v okně `^[[36;1m` a 28 znaků timestampu na každém řádku |
| `Policy.logTail(_:lines:)` | Konec logu a **kolik se ho nevešlo** (`LogTail`, #214). Tiše zkrácený log tvrdí, že job začal uprostřed |
| `Policy.jobLog(_:)`, `Policy.logTail(withoutANSI:lines:)` | Celý log pro sheet (#417) — **bez ANSI, s timestampy**, i s počtem řádků a velikostí spočítanými při stažení (`JobLog`). Druhá funkce je zbytek `logTail`u, aby se průchod celým logem platil **jednou** |
| `Policy.codeSheetSizing(kind:screen:)`, `codeSheetSize(kind:storedWidth:storedHeight:screen:)`, `codeSheetResize(kind:opened:measured:)` | Velikost sheetu s kódem (#417) — **dva profily** (hunk 1 180 × 520 s podlahou 560 × 320, log obrazovka − 152 nejvýš 2 700 × 760 s podlahou 820 × 420), uložená velikost ořezaná o obrazovku a rozhodnutí, jestli se vůbec zapsat |
| `Policy.codeSheetCharacters(width:characterWidth:)`, `codeSheetOverflow(code:width:characterWidth:)`, `codeSheetLines(of:)` | Kolik znaků se vejde na řádek sheetu a kolik řádků se nevešlo (#417). Kapacita je tatáž aritmetika jako tabulka v sekci 28 návrhu; **řádky se počítají na jednom místě**, ať hlavička a patička nemluví každá o jiném počtu |
| `Policy.logAvailability(bytes:)` | Jde se pro log vůbec? (#214) Nad 2 MB ne — věta s konkrétní velikostí z `Content-Length`, změřený strop. Od #292 se ptá **dvakrát**: na velikost z `HEAD`, a když ta nepřijde, na skutečnou velikost stažených bajtů |
| `Policy.logLines(of:)` | Řádky logu **na jakémkoli zakončení** — `LF`, `CRLF` i samotné `CR` (#292). `split(separator: "\n")` na `CRLF` nerozdělí, protože `"\r\n"` je ve Swiftu jeden `Character` |
| `Policy.facts(commits:newCommits:files:filesWithFindings:headSha:findingsHeadSha:)` | Dlaždice s fakty o PR (#198); dlaždice, o které se nedá nic říct, se vynechá |
| `Policy.fileMarkers(of:categories:)` | Které soubory nesou nález a jak vážný (#197) — blokující přebíjí a nedá se přebít zpátky |
| `Policy.fileFindings(in:categories:)` | Co je v souboru k vyřízení pro kapsli v hlavičce diffu (#219) — počítá **místa**, ne nálezy, a odmítnuté vynechá |
| `Policy.charactersPerSide(contentWidth:characterWidth:layout:gutter:)` | Kolik znaků kódu se vejde na stranu (#188); vedle sebe se šířka dělí na dvě. Gutter odečítá **jednou** — což od #236 odpovídá i tomu, kde se kód opravdu zalomí; do té doby byl ukazatel v pohledu pod sebou o 17 znaků optimističtější než skutečnost |
| `Policy.navigation(over:cursor:)`, `Policy.step(_:over:cursor:)`, `Policy.navigablePlaces(in:)` | Procházení nálezů šipkami (#187) — stav lišty, kam skočit a po kterých místech |
| `Policy.changes(in:since:)`, `VisitChanges.count` | Co na PR přibylo od poslední návštěvy (#173) — commity, force-push, cizí review a komentáře (`VisitChanges`); počet sečte **všech pět kategorií**, protože ho nese odznak u záložky `Přehled` (#218) a musí slíbit totéž, co blok uvnitř vypíše |
| `Policy.tally(of:dismissals:categories:)`, `Policy.findingsBadge(of:)` | Kolik je nálezů a kolik blokuje (#242, `FindingsTally`) — **jeden zdroj pro tři místa**: odznak na záložce, souhrn nad tabulkou a bubliny v diffu. Počítá **nálezy**, ne řádky tabulky; odmítnutý blokující se do `blocking` nepočítá |
| `Policy.findingsEmptyReason(visible:record:isRunning:categories:)` | Proč je prázdno v nálezech (#242, `FindingsEmptyReason`) — `hiddenByReviewerFilter` se nesmí slít s `clean`, `failed` taky ne. Věta se z toho skládá ve `FindingsEmptyView`, společné pro tab i panel |
| `Policy.sorted(_:by:categories:dismissals:)`, `FindingTableSort.toggled(_:from:)` | Řazení tabulky nálezů podle sloupce (#242). Závažnost sestupně **je** výchozí `Policy.sorted`, takže druhá škála nevzniká; **odmítnuté zůstávají naspod v obou směrech** |
| `Policy.findingTableLayout(availableWidth:)` | Šířky sloupců tabulky (#242, `FindingTableLayout`) — spočítané, ne vyjednané (#220). Pod `findingTableReviewerBreakpoint` odpadá sloupec `reviewer · kategorie`; je to jediný, jehož obsah je i v bublině a v chipech |
| `Policy.lanes(of:skills:running:)` | Dráhy do tabu `Průběh` (#242, `ReviewerLane`) — fáze `čeká na slot` / `session` / `prochází kód` / `hlásí nálezy` **z toho, co v ose doopravdy je**. Fáze za tou, kam se běh dostal, zůstává nedotčená i u doběhlého běhu; špatný konec se značí aspoň u `session`, aby spadlý start nevypadal jako nezačatý běh. Běžící reviewer bez osy dostane dráhu ve frontě a **nastavený reviewer, který na PR neběžel, dráhu `nespuštěno`** — sada je ta z `AppStore.reviewSkills(for:)`, tedy tatáž, ze které se review pouští. Pořadí je nastavení → osy → běžící abecedně, aby dráhy mezi tiky nepřeskakovaly |
| `Policy.progress(startedAt:phase:running:)` | Průběh běžícího review do pruhu v hlavičce (#218, `ReviewRunProgress`). `nil` = neběží nic — rozhoduje **`startedAt` běhu**, ne fáze, protože `reviewPhases` si `failed` drží i po skončení |
| `Policy.diffstatBlocks(additions:deletions:)` | Pět čtverečků poměru změny za `+X −Y` (#218). Zaokrouhluje se **dolů**, každá strana zvlášť, zbytek zůstává šedý; prázdný diff nedá žádný čtvereček |
| `Policy.code(of:)` (řádky / rozsah / hunk), `Policy.copyTargets(for:in:comments:)`, `Policy.range(covering:in:of:)` | Kód z diffu pro schránku (#157): **bez `+`/`-` a bez čísel řádků**, u rozsahu v pořadí a ze strany, na které rozsah leží |
| `Policy.snippet(of:context:)` | `diffHunk` vlákna → `ThreadSnippet`: posledních pár řádků po komentovaný a příznak zkrácení (#158). `nil` = úryvek se nemá z čeho vzít. **Není to `Policy.snapshot`** — ten je z dnešního diffu a slouží kotvám draftu |
| `Policy.commentableSide(of:in:)` | Ke které **kanonické** straně by šel komentář; `nil` = nedá se komentovat |
| `Policy.commentAnchors(of:in:)`, `Policy.commentAnchors(in:)` | Kotvy na **obě strany** (`LineAnchors`) — kontextový řádek unese vlevo i vpravo; mapa pro celý soubor jedním průchodem |
| `Policy.commentAnchor(of:in:)` | Kanonická kotva (`DraftAnchor`: číslo + strana + volitelný začátek rozsahu) — tudy chodí převzatý nález, který stranu nemá |
| `Policy.commentRange(from:to:in:)` | Dva konce → rozsah seřazený podle pořadí v diffu; `nil` = konec v diffu není |
| `Policy.rangeCells(of:in:)`, `Policy.commentRangeCells(of:in:)` | Buňky `(řádek, strana)`, které rozsah pokrývá — pro zvýraznění v diffu |
| `Policy.location(of:)`, `Policy.lines(of:)` | Kde komentář je, jako text (`Cart.php:26–31`) — jedno místo pro panel i potvrzení |
| `Policy.snapshot(of:in:)`, `Policy.text(at:in:)` | Snímek kódu pod kotvou z diffu (#69) |
| `Policy.anchorState(of:in:)` | Jak kotva dopadla proti novému diffu: `fits` / `moved` / `uncertain` / `lost` |
| `Policy.transferring(_:to:head:in:choices:)`, `Policy.defaultChoice(for:)` | Přenesení draftu na nový commit podle potvrzených rozhodnutí |
| `Policy.draftTarget(for:in:)` | Kam převzatý nález patří — `DraftTarget.line` nebo `.body` |
| `Policy.adoptedText(of:)`, `Policy.isAdopted(_:target:in:repo:)` | Text převzatého nálezu a odznak „už je v draftu“ |
| `Policy.permalink(to:line:in:at:)`, `Policy.bodyItem(text:link:)`, `Policy.appendingBodyItem(_:to:)` | Odkaz na kód a skládání položek těla review |
| `Policy.isStale(_:head:)` | Je draft psaný proti staršímu commitu? |
| `Policy.sendBlock(for:head:)` | **Proč** se draft nedá odeslat (`DraftSendBlock`); `nil` = dá se |
| `Policy.canOpenSubmission(block:canTransfer:)`, `Policy.needsTransfer(block:canTransfer:)` | Dá se otevřít **potvrzení** odeslání (#151) a začne kontrolou kotev? Ptá se tlačítko v panelu i zkratka `⌘⏎` — dvě kopie by znamenaly, že zkratka otevře okno nad zakázaným tlačítkem |
| `Policy.health(of:from:)` | Puntík služby ve stavovém řádku ze tří signálů — viz `App/Health/` |
| `Policy.reviewNotification(for:ownership:state:blocking:topFinding:)` | Notifikace o doběhlém review z `ReviewState`; `nil` = není o čem dát vědět. Titulek nese počty (#200), tělo nález a pod ním PR. **O vlastním PR nehlásí nic** (#332) — všechny tři události jsou odpověď na review request; výchozí `.theirs` je tatáž bezpečná strana jako u `ownership(ofAuthor:mine:)` |
| `Policy.newPullRequestNotification(for:title:isReReview:)` | Notifikace o novém PR ve frontě (#85); re-review se pozná textem (#137) |
| `Policy.newPullRequestsNotification(for:titles:reviewed:)` | **Souhrn** za všechna nová PR z jednoho tiku (#87); jedno PR dá plnou hlášku |
| `Policy.notificationClick(on:listed:visible:status:)` | Co udělat s klikem na notifikaci (#409): `ignore`, nebo `open(clearsFilter:)`. PR mimo seznam se **neotevírá naslepo** — výjimka je nenačtený seznam (`notStarted`), kvůli kterému má proud kliknutí buffer. Filtr, který PR schoval (#117), se ruší; rozřazení podle autora (#331, #332) do rozhodnutí **nevchází** |
| `Policy.paletteResults(of:query:limit:)`, `Policy.paletteTokens(in:)` | Hledání v paletě ⌘K (#184): co na dotaz sedne, jak se to váží, kolik z každé skupiny je vidět. Prázdný dotaz vrací **všechno** v pořadí katalogu; pořadí skupin drží `CommandPalette.Group`. Váhy: titulek (začátek > hranice slova > vnitřek) **před** podtitulkem (repo, autor) a ten před klíčovým slovem; vrací i **dva rozsahy zvýraznění**, aby bylo z řádku vidět, proč vyšel |
| `Policy.paletteActions(open:isReviewing:hasRun:layout:isPanelExpanded:section:)`, `Policy.paletteLabel(of:)` | Které akce mají teď co dělat (#184) a jak se jmenují. Řádek, který by nic neudělal, se nenabízí |
| `Policy.tabStrip(open:)`, `Policy.tab(_:after:open:)` | Cyklení pruhem záložek `⌃Tab` / `⌃⇧Tab` (#245): pruh je `[.home] + openTabs` a soused se bere **dokola**. `nil` = nikam se nehýbe — jediná záložka, nebo aktivní záložka, která v pruhu není |
| `Policy.sortedReleases(_:)` | Vydání od nejnovějšího (#127) — podle **data**, ne podle tagu |
| `Policy.newReleases(in:since:)` | Co vyšlo od poslední viděné verze; neznámá značka = **nic** |
| `Policy.recheckStatuses(_:of:)` | Spáruje odpovědi kontroly (#150) s nálezy, na které se ptala — index z promptu → `Policy.key(of:)`. **Nepáruje se přes text**: model si věty přeformuluje |
| `Policy.severityBadge(isBlocking:recheck:dismissal:)`, `Policy.severityBadge(of:categories:)` | Co stojí v odznaku závažnosti u nálezu a jestli se jeho text přeškrtne (`FindingSeverityBadge`, #150): `dismissed` / `resolved(_, blocking:)` / `blocking` / `none`. **`blokuje` se k `vyřešeno` přidává, nenahrazuje** — první je fakt, druhé tvrzení modelu. Odmítnutí přebíjí kontrolu a **nepřeškrtává** (celořádkové „nepočítá se“ patří člověku). Skupinová varianta vydá `resolved` jedině tehdy, když ho kontrola dala **všem platným** nálezům místa |
| `Policy.incrementalDiff(from:to:rewroteHistory:)` | Dá se ukázat **jen to, co od minule přibylo** (#284)? `nil` = tlačítko se nenabídne. Chce viděnou hlavu, dnešní hlavu, rozdílné a **nepřepsanou historii**; `rewroteHistory: nil` (nenačtená osa) se chová jako „přepsala“ |
| `Policy.recheck(of:head:)` | Co o uložených nálezech říká poslední kontrola (`RecheckReport`, `RecheckTally`): `none` / `outdated(againstHeadSha:)` / `current`. **Platí jen pro hlavu, proti které běžela** — jinak se odznaky nevydají (tvrdá podmínka č. 5); počítá se z **platných** nálezů, takže odmítnutý (#113) se nepočítá, a nález bez odpovědi jde do `unanswered` |

- **Vstup jsou výsledky po zdrojích** (`[[PullRequestSummary]]`), ne jeden plochý seznam.
  Volající pak nic nespojuje a z typu je vidět, že jde o několik nezávislých dotazů.
- **Při kolizi vyhrávají novější data**, ne pořadí zdrojů. Zdroje se dotazují postupně,
  takže jeden z nich může nést stav, který mezitím zastaral.
- **Řadí se od naposledy změněného, při shodě podle identifikátoru.** Druhé kritérium není
  kosmetika: bez něj by pořadí mezi pollingy poskakovalo, protože slovník nemá pořadí.
- **Rozřazení podle autora se do slučování nemíchá** (#330). `PullRequestOwnership` (`.mine` /
  `.theirs`) se počítá **nad hotovým seznamem** (`Policy.ownership(of:mine:)`), protože slučování
  je o deduplikaci, ne o tom, čí co je — a jeden PR umí přijít z víc zdrojů naráz. Typ leží
  v `App/Policy/`, jako `QueueRow`: je to odpověď čisté funkce, ne data, na kterých staví moduly.
  Tři věci, na kterých to stojí:
  - **Prázdná množina „mých“ loginů znamená, že je všechno `.theirs`.** Dokud login nedorazí, je
    to „nevím, kdo jsem“ — a to nesmí znamenat „to je moje“, jinak by se při startu celý seznam
    na okamžik přehodil do vlastní sekce a fronta cizích PR by zmizela.
  - **Je to množina, ne jeden login** (viewer + `ownLogins` z konfigurace). Agent s vlastním
    účtem pushuje pod sebou, takže by do `.mine` nespadl; dolepovat to potom znamená projít
    všechna místa, která se ptají „je to moje“. Porovnává se bez ohledu na velikost písmen,
    protože `gh` vrací kanonický tvar a do konfigurace se login píše ručně.
  - **Porovnání je na jednom místě** (`ownership(ofAuthor:mine:)`) a chodí přes ně i
    `Policy.isOwn(author:viewer:)` z #114. `Conversation.isMine(_:)` odpovídá na jinou otázku
    (čí je komentář v načtené konverzaci) a v modelu zůstává.

Nad zadáním pro agenta (#333) platí:

- **`AgentPromptItem` je výčet se čtyřmi případy a nese původní modely** — nález (i s důvodem
  odmítnutí), vlákno, komentář pod PR, souhrn review. Tatáž úvaha jako u `ConversationEntry`:
  kdyby se položky při sběru zplošťovaly do jednoho tvaru, spadlo by rozhodnutí „co se z položky
  ukáže“ do sběru. Do které volby položka patří (`choice`), kde se řeší (`file`, `line`) a kdy
  vznikla (`date`) jsou **odvozené vlastnosti**, ne uložená pole.
- **Sběr nefiltruje podle voleb.** `agentPromptItems` vrací i vyřešená vlákna a odmítnuté nálezy,
  protože z téhož seznamu se počítají čísla u **vypnutých** voleb — bez nich by se nedalo napsat
  „vynecháno: 1 vyřešené vlákno“ a tiché zahození vypadá jako „tohle je všechno“.
- **Sekce bez souboru stojí první.** Souhrn review a komentář pod PR se k žádnému řádku nevážou,
  a nález bez `file` je tentýž případ; přišpendlit je k náhodnému souboru by agentovi lhalo o tom,
  kde se to řeší. Pořadí souborů je **blokující první, zbytek abecedně** — deterministické (dvě
  po sobě sestavená zadání se dají porovnat) a zároveň něco tvrdící.
- **Zastaralé vlákno se umístí podle `originalLine` a napíše se to.** `anchorLine` dá číslo, které
  platilo pro starší commit, takže se u něj v nadpisu píše `(zastaralé — číslo platí pro starší
  commit)`. Tvrdit dnešní řádek u kotvy, která platila pro starý head, je horší než nic.
- **Hlava PR je v hlavičce textu, a když ji neznáme, řekne se to.** Nálezy jsou jí klíčované
  (tvrdá podmínka č. 5) a zadání se předává dál. Nenačtená konverzace je z téhož důvodu **v textu**,
  ne jen v okně: je to mezera v tom, co text tvrdí, kdežto vypnutá volba je moje rozhodnutí.
- **Diff hunk má vlastní příznak vedle `diff`u.** U vlákna je hunk snímek z commitu, na kterém
  vzniklo (`ReviewThread.diffHunk`), u nálezu se hledá v dnešním diffu — takže samotné `diff == nil`
  nesmí hunky vypnout, jinak by u nenačteného diffu tiše zmizely i ty, které se mají kde vzít.
  `Policy.unifiedText(of:)` sází hunk **se znaky změny**, na rozdíl od `Policy.code(of:)`: tady jde
  o to, co se v tom místě změnilo, ne o kód do editoru.
- **Nic z toho neumí nic odeslat.** Prompt končí ve schránce (`Clipboard`) nebo v souboru, který
  vybere člověk (`TextFileExport`, `NSSavePanel`). Je na to test — `SingleWayOutTests` čte zdrojáky
  a tvrdí, že soubory zadání nezná `ReviewPublishing`, `PublishRequest`, API ani podproces.
- **`AgentPrompt` nese i identity toho, co je v textu** (`handed`, #334). Ne celé položky: sheet
  ukazuje text, ne recept na jeho složení, a razítko předání potřebuje jedině to, podle čeho se
  položka pozná. **Počet by nestačil** — zadání se dá sestavit s vypnutou volbou, takže „poslal jsem
  šest“ neodpovídá na otázku, **co** zbývá.
- **`only:` zužuje zadání na vyjmenované položky** (#334) a používá to jedině `Sestavit i tak (jen
  nové vlákno)` po pushi. Do `inventory` se to **nepromítá**: počty u voleb dál mluví o tom, co na
  PR je, jinak by zúžené zadání vypadalo jako celé. Do **seznamu položek** (#377) se promítá — zúžený
  sheet je o nové diskuzi, takže zaškrtávátko u nálezu, který zadání nepřijme, by lhalo; kolik položek
  tím zbylo mimo, je nad textem napsané větou.

### Výběr položek do zadání (#377)

Do #377 se vybíralo **po druzích** (sedm voleb v panelu) a na skutečném zadání to nestačilo: vypnutím
druhu `souhrny review` odešel i verdikt bota, ponecháním se agent v textu nevyznal. Od #377 má
zaškrtávátko **každá položka** a bydlí to v **sheetu**, ne v panelu (240–520 bodů proti 840–1080);
v panelu zůstávají volby po druzích jako hrubý filtr a přibyl u nich počet vybraných.

- **Jedna funkce rozhoduje, co je v textu** — `Policy.agentPromptIncludes(_:options:conversation:toggled:)`.
  Ptá se jí sazba textu i seznam v sheetu, protože **počet v hlavičce se musí rovnat počtu položek
  v textu**; dvě cesty by znamenaly obrazovku, která lže o tom, co se zkopíruje. Proto je i výsledek
  jedna hodnota: `Policy.agentPromptSelection(…)` → `AgentPromptSelection` (zadání **a** seznam),
  a `Policy.agentPrompt(…)` je jen její `prompt`.
- **Drží se odchylka, ne seznam vybraných** — `toggled: Set<String>`, `!=` jako xor, tatáž úvaha jako
  u `Policy.disclosure` u bublin (#185). Výchozí stav je funkce dat a voleb, takže seznam vybraných by
  se musel plnit při každém přeskládání zadání a nový běh review by zahodil, co si člověk naklikal.
- **Vypnuté se předvybírá a u každé položky je napsaný důvod** (`AgentPromptExclusion`). Šest případů
  v pořadí rozhodování: `odmítl jsi ho` a `vyřešeno` (volby z #333), `druh vypnutý` (hrubý filtr, tedy
  **moje** rozhodnutí — přebíjí to, co se pozná z dat), a pak tři z dat: `napsal jsi to ty`
  (`Conversation.isMine`), `bez obsahu` a `shrnuje diff`. Vlákna a nálezy se z dat nepředvybírají
  nikdy: vlákno na vlastním PR je práce (#333) a nález sundá jedině odmítnutí (#113).
- **`shrnuje diff` je jediná heuristika a stojí ve vlastním souboru**
  (`App/Policy/AgentPromptDiffSummary.swift`), aby šla vyhodit bez dotyku na zbytek — smazat soubor
  a jedno volání znamená, že se souhrny přestanou předvybírat, a nic dalšího se nerozbije. Pozná se
  na **nadpisu** `Pull request overview`, ne na zmínce v próze. **Tabulka souborů se jako druhá
  podmínka zamítla**: starší formát Copilotova přehledu ji nemá (změřeno na `cli/cli#11451`), takže by
  heuristika nedělala nic právě v tom případě, na který je.
- **`bez obsahu` je syntaktický test, ne druhá heuristika** (`Policy.hasNoContent`): po odstranění
  nadpisů a HTML komentářů nezůstane nic. Padá do něj i **schválení s prázdným tělem** — změna proti
  #333, kde šlo do textu. Pro agenta je to nulová informace, ze seznamu nemizí a jedním kliknutím se
  vrátí; tehdy „vynechat“ znamenalo ztratit celý druh, teď jednu položku.
- **Seznam se dělí na čtyři grupy po druzích** (`AgentPromptKind`), ne na sedm podle voleb: vyřešené
  vlákno je pořád vlákno, jen v jiném stavu, a leží mezi svými s důvodem. V hlavičce grupy je
  `2 z 3`, tedy **vybrané z celku**.
- **Rozbalení rozhoduje `Policy.pickDisclosure(of:toggled:)`**, ne `@State` view: `.none` znamená, že
  položka nic nenese (schválení s prázdným tělem) a šipka se u ní **nekreslí** — kliknutí, po kterém se
  nic nestane, je k nerozeznání od rozbité aplikace. Text v rozkliku je **tentýž**, jaký jde do zadání
  (`Policy.agentPromptItemText(of:)`), a dlouhý se **roluje, nekrátí**.
- **Výběr ani rozbalení nepřežijí zavření sheetu**, a je to rozhodnutí: sheet se otevírá k jednomu
  předání, předvybrání je levné (počítá se z dat) a uložený výběr by byl další stav u pull requestu
  vedle razítka v `handoffs.json`, který zastará pushem a nikdo o něm neví. Drží to proto `@State`
  sheetu; store si výběr **nedrží** a bere ho parametrem (`agentPromptSelection(for:only:toggled:)`).
- **Autor je jediná opsaná hodnota v `AgentPromptPick`** — u nálezu je to **zkrácené** jméno
  revieweera (#182), a zkrátit se smí jen to, co po zkrácení zůstane v celé sadě jednoznačné, takže to
  jedna položka o sobě nerozhodne.
- **Předvybrané položky nejsou materiál k předání** (`Policy.handoff`, filtr na
  `AgentPromptExclusion.isPreselected`). Bez toho by odznak `Moje PR` nad vlastním PR **nikdy
  nezhasl**: release notes v komentáři pod PR jsou na každém mém PR, takže by mezi nepředanými
  navždycky zůstala položka, kterou zadání ani nenabízí. Ruční odškrtnutí odznak naopak svítit
  **nechá** — leží na něm práce, kterou nikdo nikam nedal (zadání #377).

### Předání zadání (#334)

Otázka je **„zbývá tu ještě něco, co jsem nepředal?“** a odpovídá na ni jedna čistá funkce
(`Policy.handoff(_:record:conversation:head:commits:activitySince:)` → `HandoffReport`). Čtou z ní
tři místa: odznak sekce `Moje PR` v railu, pilulka `N k předání` v řádku seznamu i na dashboardu
a panel `Zadání`. Kdyby si na „co je nové“ odpovídalo každé z nich samo, rozešlo by se to — odznak by
svítil nad řádkem, který tvrdí, že je hotovo. **Od #335 nese tentýž report i cizí aktivitu**
(`HandoffReport.activity`), protože je to druhý druh téže otázky — viz *Cizí aktivita na vlastních
PR* níž.

- **Razítko drží pull request, ne prompt** (`Handoff`, `HandoffLedger`). `AgentPrompt` zaniká
  zavřením sheetu, kdežto „předáno v 14:20 proti 9c1de02“ musí přežít restart. Je to tatáž
  součástka jako `againstHeadSha` u kontroly nálezů (#150), jen se ptá na jiné („co jsem už
  poslal“ vs. „na co jsem se ptal“) — a **proto nebydlí u nálezů**: předat se dá i zadání, ve
  kterém není jediný nález, a takové PR nemá uložený záznam vůbec. Založit ho kvůli razítku by
  znamenalo záznam bez běhu, který v `Policy.currentRecords` vyhraje nad nálezy z minula.
- **Samotný čas nestačí.** Bez hlavy by panel tvrdil „předáno“ i po deseti pushích: nálezy jsou
  klíčované `headSha` (tvrdá podmínka č. 5), takže po pushi mluví předané zadání o kódu, který na
  PR není. Teprve dvojice `(kdy, proti čemu)` dovolí odpovědět, jestli ještě platí.
- **Razítko nese i identity předaných položek**, ne jen počet. S nimi je `pending` **přesné číslo**
  („kolik jsem neposlal“), a hlavně odpovídá i na částečné předání: zadání sestavené s vypnutou
  volbou nechá vlákno mimo text, a razítko s počtem by ho odepsalo jako předané. Nálezy se přitom
  poznají klíčem (`Policy.key(of:)`), takže opakované review s **týmž** nálezem odznak nerozsvítí,
  kdežto nový nález ano.
- **Cizí odpověď v už předaném vlákně se počítá znovu.** Identita vlákna se odpovědí nemění, takže
  samotné „už jsem ho poslal“ by novou větu od kolegy zahodilo. Vlastní odpovědi se nepočítají —
  že jsem něco napsal já, není novinka (tatáž úvaha jako u „od tvé poslední návštěvy“, #173).
- **Neznámá dnešní hlava se bere jako „neposunula se“**, a je to vědomá spodní hranice: hlavu zná
  aplikace jedině z dotaženého detailu, a ten se tahá při zobrazení PR (`gh search prs` ji nevrací,
  #4). Kdyby z toho vycházelo `.outdated`, odznak by po předání **nikdy nezhasl** — tedy přesně to,
  co #334 opravuje. Naopak **neznámá hlava v razítku** je vlastní stav (`.unverified`): platnost se
  nedá potvrdit ani vyvrátit, takže odznak svítí a panel to napíše.
- **Po pushi je pending všechno, co je k předání**, a `staleFindings` se počítá zvlášť. Zastaralé
  nálezy **nemizí** (#113): zůstávají v diffu, v tabu `Nálezy` i v segmentu vedle, jen se do zadání
  nepředvybírají — a druhá cesta `Sestavit i tak` předá to, co po předání přibylo v diskuzi.
- **`.outdated` platí jen dokud jsou nálezy proti starší hlavě** (nálezem Copilota na #373).
  Rozhoduje `headSha` **záznamu**, ne razítka: jak se proti dnešní hlavě pustí review znovu, je
  `Pustit review znovu` rada, která už proběhla — a panel by v tom režimu zůstal navždycky
  a nedovolil zapnout volby. Že se hlava posunula, nese vedle `stage` vlastní příznak
  (`hasMovedHead`), takže to věta v panelu řekne i tehdy, když nálezy platí. Ze stejného důvodu
  není `.outdated` ani PR **bez nálezů**: „nálezy platí pro starý kód“ by bylo tvrzení o nálezech,
  které neexistují.
- **Předání bez nálezů nehýbe hlavou razítka a identity se sčítají** (`AppStore.noteHandoff(of:)`,
  nálezem Copilota na #373). `Sestavit i tak (jen nové vlákno)` se skládá proti **dnešní** hlavě, ale
  nálezy v něm nejsou — takže kdyby posunulo hlavu, panel by přestal hlásit, že uložené nálezy platí
  pro starý commit, a kdyby razítko přepsalo identity, byly by dřív předané nálezy najednou
  „nepředané“ a odznak by se rozsvítil za práci, která odešla. Hlava proto říká, **proti jakému kódu
  platí předané nálezy**, a `Handoff.handed` je součet přes všechna předání.
- **Počet commitů se tvrdí jen tehdy, když se ví.** Bere se ze seznamu commitů (tahá se s detailem,
  #316) a `nil` znamená „nevím kolik“ — po force pushi tam předaná hlava není a dopočítat rozdíl
  z délky seznamu by dalo číslo, které s pushnutými commity nemá nic společného.
- **Review se po pushi nepustí samo.** Automat se vlastních PR netýká vůbec (#332) a tohle je přesně
  ten důvod: na vlastním PR se pushuje často, takže by každý commit spustil kolo, které nikdo nečte.
  Je z toho tlačítko `Pustit review znovu →`.
- **Razítko nic nemění na GitHubu.** Je to lokální stav v cache (`handoffs.json`), ne značka na PR —
  jinak by to byla druhá cesta ven (tvrdá podmínka č. 1). `HandoffLedger` je aktor jako
  `AnnouncedPullRequests`: čtení, změna a zápis jsou tři kroky nad jedním souborem. Zapisuje se
  **nejdřív do paměti, pak na disk** (jako `AutoRunLedger`) a rozbitý soubor se čte jako prázdno,
  tedy „nepředáno“ — odznak svítí a zadání se dá předat znovu.

Nad sekcí `Moje PR` (#331) platí čtyři věci:

- **Rozřazení je pohled, ne zdroj pravdy** (`Policy.pullRequests(_:ownedBy:mine:)`). Zúžený seznam
  smí číst jedině seznam a detail vybraného řádku, a rozřazení podle autora je **další zúžení nad
  tímtéž** — proto stojí na `visiblePullRequests`, ne na plném seznamu, a proto na něm nesmí viset
  nic z úklidu. Kdyby viselo, znamenalo by přihlášení jiným účtem smazanou cache; je to tatáž
  hranice jako u filtru (#117).
- **Prázdná sekce má tři různé věty, ne jednu.** Chybějící zdroj (`author:@me` mezi zdroji není),
  nenačtený login a „nic vlastního otevřeného“ jsou tři různá tvrzení a `Policy.ownListEmptyReason`
  je řadí od nejsilnějšího: **polling → zdroj → login → filtr → prázdno**. Věta „nic tu není“ nad
  aplikací, která vlastní PR vůbec nestahuje, vypadá jako hotová práce — a přesně proto se
  konfigurace nemigruje (viz `App/Config/`): rozpoznat to má prázdný stav, ne zápis do souboru,
  o který nikdo neřekl.
- **Odznak počítá práci, ne PR — a od #334 se ptá „zbývá tu něco, co jsem nepředal?“.**
  `ownPullRequestsAwaitingMove` volá `Policy.handoff` a počítá PR, kterým z něj vyjde `awaitsMove`.
  Do #334 to byl „nezpracovaný nález nebo nevyřešené **cizí** vlákno“; otázka se změnila, takže se
  změnil i materiál — je to to, co jde do zadání pro agenta (viz *Předání zadání* níž). Vlákna
  a hlava PR se počítají **jen z načtených konverzací a detailů**, takže je to spodní hranice;
  neúplnost je schválně v tomhle směru, protože odznak, který napočítá víc práce, než jí je, se
  přestane čítat. **Od #335 už konverzace vlastních PR dorazí sama** (rozhlídka na pozadí, nejvýš tři
  PR za pět minut), takže se ta hranice posunula: zbývá jen tam, kam jeden průchod nedosáhl. Hlava PR
  se pořád tahá jedině s detailem, tedy při výběru řádku.
- **Fronta jsou od #332 cizí PR** (`AppStore.queuePullRequests`, `visibleQueuePullRequests`), takže
  je vlastní PR na dashboardu v jednom bloku, ne ve dvou. Do #332 se počítal do obou a v provozu
  z toho bylo `Čeká na mě = 32` (13 cizích, 19 vlastních). Které místo chce kterou množinu, je
  v tabulce níž — a **je to rozhodnutí na místo, ne plošné zúžení**.

### Cizí aktivita na vlastních PR (#335)

Do #335 se konverzace tahala **jedině při zobrazení PR**, takže „od minule“ vznikalo teprve ve chvíli,
kdy se koukám — tedy přesně tehdy, kdy už notifikaci nepotřebuju. Chybělo jediné: **někdo se na to
musí zeptat dřív.** Sbírat je z čeho — `VisitChanges` (#173) události i komentáře sbírá,
`SinceLastVisitLine` je umí vykreslit a `Conversation.isMine` rozlišuje, co je moje.

**Cena je to podstatné rozhodnutí** a drží ji `Policy.activitySweep` třemi věcmi naráz:

1. **`updatedAt` ze searche je předfiltr a je zadarmo.** Tahá se jedině konverzace PR, jehož
   `updatedAt` se posunul za ten, se kterým konverzace leží v paměti — tedy jedině tam, kde se
   doopravdy něco stalo. **Na klidný den nula dotazů.** Samotné `updatedAt` na odznak nestačí: řekne,
   že se něco stalo, ne co a kolik — a hýbe se i po vlastním pushi.
2. **Vlastní interval, pětiminutový** (`Policy.activitySweepInterval`), nezávislý na
   `pollIntervalSeconds`. Seznam se obnovuje po minutách, protože z něj plyne nová práce; u diskuze
   na vlastním PR pět minut zpoždění nikomu nic nezkazí.
3. **Strop tři PR na jednu rozhlídku** (`Policy.activitySweepLimit`), takže i v bouři je cena shora
   omezená — **tři dotazy za pět minut**, tedy 0,6 na minutový tik proti `1 + N` každou minutu.
   Pořadí se bere ze vstupu (řazený od naposledy změněného), takže strop nechá čekat to nejstarší.

Rozhlídka běží **uvnitř `afterSuccessfulTick`**, a to je celý mechanismus, jak dědí backoff: při rate
limitu `PollingService` čeká a netiká, takže se ani nekouká. Vlastní časovač by tu ochranu obešel.
Razítko rozhlídky (`AppStore.lastActivitySweep`) se posouvá **jen když se doopravdy ptáme** — jinak by
se pět minut čekalo zrovna na komentář, který přišel vteřinu po tiku.

**Druhé razítko je podmínka, ne pohodlí.** `VisitLedger` drží poslední **návštěvu**,
`ActivityNoticeLedger` (#335) poslední **oznámení** — a oznámením PR nenavštívím, takže bez toho
druhého by „2 nové komentáře“ chodily každou rozhlídku, dokud PR neotevřu. Novinka je to, co je
novější než **obojí** (`Policy.activityBaseline`). Detaily, které nejsou zjevné:

- **Do razítka jde datum té nejnovější ohlášené položky, ne „teď“.** S časem doručení by propadl
  komentář, který přišel mezi dotazem na konverzaci a zápisem razítka.
- **Razítko se nikdy neposouvá dozadu**: rozhlídka se ptá i na PR, o kterých se hlásilo dřív, a starší
  položka z ohlášené věci nesmí udělat neohlášenou.
- **Zapisuje se až po doručení** (`isWorthRetrying`), jako snímek u nových PR (#85). Přechodná chyba
  razítko nechá být, kdežto odmítnuté oprávnění nebo **vypnutý přepínač** ho posunou: opakovat každou
  rozhlídku něco, co je zakázané, nemá cenu a v okně je ta aktivita vidět na řádku.
- **V předvolbách, ne v cache**, ze stejného důvodu jako návštěvy: je to jedno datum na PR, ne materiál
  review. Vlastní typ vedle `VisitLedger.Visit` proto, že zápis návštěvy se děje při **každém**
  zobrazení detailu, kdežto zápis oznámení jen po doručené hlášce — jeden slovník se dvěma významy
  znamená, že se ta dvě data dají posunout omylem naráz.
- **Značka „od minule“ se zakládá i při rozhlídce** (`AppStore.seedVisitBaseline(for:)`), ale
  **návštěva se nezapisuje**: dotažení konverzace na pozadí návštěva není. Kdyby se zapsala, značka by
  se posunula na teď a řádek by o komentáři kolegy mlčel. PR, o kterém aplikace ještě neslyšela, tím
  dostane značku „teď“, takže se o měsíc starých komentářích nehlásí — tatáž ochrana proti lavině jako
  první tik u `AnnouncedPullRequests`.

**Co je cizí aktivita** (`Policy.foreignActivity`): komentáře pod PR i ve vláknech a odeslaná review,
vždy **bez mých vlastních** (`Conversation.isMine`; na vlastní PR sice verdikt poslat nejde, ale
komentované review ano). Staví to na `Policy.changes(in:since:)`, tedy na téže funkci jako pruh „od
minule“ — druhá odpověď na „co přišlo po téhle chvíli“ by se s první rozešla.

- **Commity a události osy v tom nejsou**, a je to schválně: na vlastním PR je push obvykle můj
  a `TimelineEvent.at` je u commitu **datum commitu, ne pushnutí** (`pushedDate` GitHub neplní,
  změřeno u #171), takže by banner „někdo pushnul“ chodil o vlastní práci. Pruh v detailu PR commity
  ukazuje dál.
- **CI se nehlídá vůbec** (#335 to výslovně odkládá). `fetchChecks` je **druhý dotaz na PR**, tedy
  dvojnásobek ceny, a spadlé CI je jiná událost než komentář — patří k tomu vlastní text i vlastní
  přepínač, ne pátý odstín tohohle.
- **`NotificationEvent.activity` má vlastní `replacementGroup`.** Že mi kolega odpověděl, nemá přebít
  výsledek review na tomtéž PR (a naopak) — jsou to dvě různé věci a obě mají zůstat na obrazovce.
  Text skládá `Policy.activityNotification`: titulek `2 nové komentáře a 1 review`, pod ním **ta
  nejnovější věta** (rozhoduje datum, ne druh) a na třetím řádku PR, tedy rozvržení z #200. Krátí se
  tímtéž řezem jako nález (`Policy.shortenedForBanner`), protože v banneru musí na čtvrtém řádku zbýt
  identifikace.
- **Řádek seznamu nese `2 nové komentáře od minule` místo autora a času** (návrh, sekce 21 a poznámka
  66b). Počet a slovo skládá `Policy.activityHeadline`, tedy tatáž funkce jako titulek notifikace —
  dvě implementace téže věty by se rozešly. Text **nahrazuje** autora a čas: je to pořadí důležitosti,
  ne úspora místa (autorem vlastního PR jsem já nebo můj agent), a obojí zůstává v hlavičce detailu.
- **Volající si bere jeden report na řádek.** `pending` i `activity` jsou z téhož `HandoffReport`,
  takže dvě volání by byla tatáž práce dvakrát — a `List` staví řádky při každém překreslení.

### Dění — pátá sekce railu (#414)

Notifikace proletí a nikde nezůstane: banner zmizí, **stejná identita přepíše to, co ještě visí**
(#87), a v okně po tom zbude **jediný údaj** — čas posledního doručení u zvonku (#138). `Dění` je
místo, kde ty události zůstanou. Zakreslené v **sekci 27 návrhu**.

**Kdo co drží:**

| Kus | Kde | Co drží |
|---|---|---|
| `ActivityEvent` | `App/Models/` | jedna položka: druh, PR, čas, headline, detail, `wasAnnounced`, sha, autor |
| `Policy` (`ActivityFeed.swift`) | `App/Policy/` | **všechno rozhodování** — brána, skládání textu, vložení do záznamu, strop, co je nepřečtené, dny, prázdno |
| `ActivityLog` | `App/Store/` | soubor `activity.json` v kořeni cache, aktor, strop **200 položek** |
| `ActivityVisitLedger` | `App/Store/` | značka poslední návštěvy v předvolbách (`activity.lastVisit`) |
| `AppStore+Feed` | `App/Store/` | kdy se zapisuje, co je v paměti, kdy se posouvá značka, klik na řádek, dotaz na hlavy z tiku (#420) |
| `Policy` (`StaleHeadProbe.swift`) | `App/Policy/` | koho se tik zeptá na hlavu a co z odpovědi plyne (#420) — dvě čisté funkce |
| `ActivityFeedView` | `App/Views/` | obrazovka: bloky po dnech, pruh návštěvy, čtyři prázdna |
| `ActivityRowView`, `ActivityTimeline` | `App/Views/` | **jeden řádek a jedna osa pro obě obrazovky** (#443) — sekce i blok na dashboardu; liší se jediné, a to `place` (úzký tvar a den u času) |
| `Policy` (`DashboardActivity.swift`) | `App/Policy/` | blok `Dění` na dashboardu (#443): strop, nadpis s počtem, patka, věta místo řádků |

**Záznam je na disku a mez je vidět v typu.** `DeliveredNotification` je v paměti schválně (#138) —
odpovídá na „funguje mi to teď“ a čas z minulého spuštění je k té otázce zavádějící; dění je otázka
opačná, takže musí přežít restart. Strop je **na položky, ne na dny**: dění odpovídá na „co jsem
prošvihl“, a to je omezené pozorností, ne kalendářem — týdenní okno jako u `SpendLedger` by
usekávalo přesně tu dovolenou, kvůli které se sem chodí. Cache bez vyjmenované meze je únik paměti
s odkladem (#224), proto je `Policy.activityLimit` konstanta a **jedno místo** (`Policy.activityLog`)
řadí, odstraňuje duplicity i stropuje — disk i paměť se tím nemají čím rozejít. **Nic jiného ten
soubor nemaže**, ani úklid po PR, které vypadlo ze seznamu: zavřený pull request na tom, co se na
něm stalo, nemění nic.

**Zápis nezávisí na přepínačích notifikací** (#86), a je to celý důvod, proč ta obrazovka unese
věci, které banner ne. Přepínače rozhodují o **vyrušení**, ne o záznamu — takže se sekce plní
i tehdy, když je aplikace jinak mlčící, a řádek, u kterého banner nedorazil, to říká chipem
**bez banneru**. Guardy na notifikační centrum se proto z `notifyAboutFinishedReview`,
`announceNewPullRequests` a `notifyAboutForeignActivity` **přesunuly dolů**; co v nich zůstalo, je
`AppStore.watchesPullRequestActivity` (centrum **nebo** záznam): snímek fronty a razítko oznámení se
nesmí spotřebovat, když je nikdo nekonzumuje, jinak by po zapnutí notifikací vypadala první nová PR
jako už ohlášená.

**Osm druhů, šest podle zadání.** Čtyři aplikace zná (nové PR a re-review, tři výsledky review,
cizí aktivita) a **dva se dopočítávají bez jediného volání navíc**:

- **`leftQueue`** je doplněk k `newcomers(in:)` nad **tímtéž** snímkem. `AnnouncedPullRequests`
  proto od #414 vrací `QueueChanges` (příchody i odchody) jedním voláním: snímek se dotazem
  přepisuje, takže druhé volání by se ptalo už proti přepsanému stavu a vrátilo prázdno.
- **`staleFindings`** čte `Policy.staleFindings(of:head:)` — tedy to jedno místo, které porovnává
  sha (#284) — a počet commitů z už načteného seznamu (`Policy.commitsAfter`). Do #420 se zapisovalo
  **jedině z `loadDetail`**, protože `PullRequestSummary` ze searche `headSha` nenese; od #420 to
  pozná i **tik**, a to jedním dávkovým dotazem na celou frontu (viz níž). Cesta přes `loadDetail`
  zůstává — ví o rozchodu **s počtem commitů** a je to jediná cesta u PR, na které se dotaz
  nedostal.

**Zamítnuté s důvodem:** spadlé CI (checky se tahají až při zobrazení PR, `loadDetail` z #306, takže
by za tím musel stát vlastní polling — nový zdroj, ne zápis toho, co proteklo) a poruchy aplikace
(stav *teď*, na který odpovídá stavový řádek; v dění by z toho byl log).

**Brána je jedna a je v `Policy`** — `Policy.isReported(_:on:)`. Dění čte tytéž události jako
notifikace, takže bez ní by z něj byl obchvat pravidla #332: hláška, kterou banner vydat nesmí, by na
obrazovce zůstala navěky. Láme se **podle druhu**, jako u notifikací: výsledky review, příchod,
odchod a zastaralé nálezy jen o **cizím** PR, cizí aktivita jen o **vlastním**. Zastaralé nálezy
patří k cizím proto, že na vlastním je push obvykle můj — tatáž úvaha, kvůli které `ForeignActivity`
schválně nenese commity.

**Text se ukládá složený a skládají ho tytéž funkce jako banner.** Vypadá to jako uložené UI, ale je
to jediná poctivá volba: řádek mluví o tom, jak review dopadlo **tehdy**, a nálezy z té chvíle na
disku být nemusí (zahodily se, uklidila je lhůta, přepsal je další běh) — přepočítaný řádek by
tvrdil něco o dnešku pod datem z minulého týdne. Bere se `Policy.reviewNotification` (co je konec
běhu a jak se jmenuje), `Policy.notificationDetail` a `Policy.activityHeadline`/`activityDetail`.
Odchylky od zákresu, které z toho plynou, jsou vypsané v [`stav.md`](stav.md).

**Identita položky je deterministická**, ne `UUID`: skládá ji `Policy` z druhu, PR a toho, co tu
příhodu odlišuje v čase. U `staleFindings` je to **hlava** (téhož rozchodu si aplikace všimne při
každém dotažení detailu a druhý řádek o jedné věci je šum), u zbytku okamžik. U nových PR se proto
zapisuje **až za `isWorthRetrying`**, ve stejné chvíli jako snímek: dokud se snímek nepřepsal, vrátí
příští tik tatáž PR — a s časem v identitě by z jednoho příchodu byly dva řádky.

**Značka poslední návštěvy, ne příznak u položky.** Tentýž mechanismus, jaký drží konverzaci
(`VisitLedger`, `Policy.conversationRows`, #183 a #361), jen s vlastním klíčem; příznak u položky by
byl druhá odpověď na tutéž otázku a zápis na každý řádek. **Posouvá se při odchodu ze sekce, ne při
vstupu** — kdyby ji přepsal vstup, přestalo by být nové zrovna to, na co koukám (tatáž nesymetrie
jako `seedVisitBaseline(for:)` u #335). Drží to `AppStore.syncActivityVisit()`, který rozhoduje ze
**změny viditelnosti** (`wasActivityVisible` → `isActivityVisible`), ne z toho, které tlačítko ji
způsobilo: volá se ze všech čtyř míst, která umí sekci opustit (`show(_:)`, `openTab`, `closeTab`,
`selectTab`), takže na pořadí ani na počtu volání nezáleží. Rail proto zapisuje **přes `show(_:)`**
(binding v `ContentView` je `Binding(get:set:)`), ne rovnou do `railSection` — jinak by ta jedna
cesta neexistovala. **Snapshot se drží zvlášť** od zapsané značky, jako `visitSnapshots` u PR: kdyby
se číslo bralo z ledgeru, posunul by ho zápis při odchodu a při návratu by nebylo nové nic.

**Bez značky je nové všechno**, a je to opačná volba než u konverzace (#173), kde `nil` znamená
prázdno. Rozhoduje o tom, co ta data jsou: záznam dění vzniká teprve za běhu aplikace, takže „nikdy
jsem tu nebyl“ znamená, že jsem opravdu nic z toho neviděl — kdežto u PR by to znamenalo vypsat
celou jeho historii.

**Odznak sekce počítá nepřečtené a na aktivní sekci se nekreslí** (`Policy.activityBadge`). To druhé
je vada dnešního railu, ne rozhodnutí o dění: odznak v něm ikonu **překryje** (změřeno na
dvoumístných počtech fronty), takže by na položce, ve které zrovna stojím, zbyl červený puntík bez
identity. Počet je proto v **nadpisu bloku** (`Dnes · 4 nové`), a to za den, ne za celý záznam.

**Každý řádek někam vede a je to v něm napsané** (`→ Nálezy`, `→ Konverzace`, `→ Commity`,
`→ Přehled`, `→ Průběh`), ne šipka bez obsahu. Jde se **jediným vstupním bodem** `openTab(_:in:)`
(#409) a tab se **jmenuje**, na rozdíl od kliku na notifikaci: řádek dění ví, o čem je, takže poslat
člověka „tam, kde skončil“ by ho poslalo jinam, než na co klikl. Jediný řádek, který do okna nevede
(`leftQueue` — PR v seznamu není), vede **na GitHub** a pozná se to i barvou; adresu skládá
`Policy.gitHubURL(of:)` z identity, protože shrnutí s `url` v paměti být nemusí. Otevírá ji **view**
(`@Environment(\.openURL)`), jako v paletě ⌘K — store se o prohlížeči nemá co dozvědět.

**Čí PR to je, se u kliku nerozlišuje** — a nesmí se to plést s bránou o řádek výš: řádek o cizí
aktivitě je o **vlastním** PR a záložka si obsah bere z plného seznamu (`summary(for:)`), takže
zúžení podle autora by znamenalo zahozený klik za nic. Je to tatáž úvaha, jakou má u #409 klik na
notifikaci.

**Kreslení:** líný seznam je **po dnech**, ne po řádcích — blok je ohraničená karta, takže potřebuje
jeden kontejner, a řádků v něm je nejvýš tolik, kolik je strop celého záznamu, takže je nejhorší
případ ohraničený. V řádku **není pružná výška** (#220, #375), neiteruje se pole tuplů (#361 —
identitu nese `ActivityFeedRow`) a nic si neplánuje kolo (#350, #358). Svislá čára osy je
**na pozadí bloku**, ne prvek v každém řádku: prvek na řádek by znamenal jeden prvek navíc na
položku (#252). Zalomení řádku dělá `FlowRow` (`.tl-line` má v návrhu `flex-wrap: wrap`), cíl vpravo
stojí mimo něj, aby se nezalomil doprostřed textu.

**Čtyři prázdna, která se nesmí slít** (`Policy.activityEmptyState`): klid, **ztracený záznam**,
**zakázané oprávnění** (spraví se jedině v Nastavení systému — odskok drží
`SystemSettings.openNotifications()`) a **vypnutý přepínač** (spraví se v nastavení aplikace).
Zakázané má přednost před vypnutým: je to stav, ve kterém je aplikace úplně mlčící a člověk o tom
nemusí vědět. Návrh kreslil jen klid a zakázané oprávnění; ostatní dvě jsou rozhodnutá při
implementaci.

**Ztracený záznam přebíjí všechna ostatní prázdna, a je to to nejdůležitější z nich.** Rozbitý
soubor i prázdný záznam dají obojí prázdný seznam, takže by nad ztracenou historií stálo klidné
*Za poslední dny se nic nestalo* — tedy text, který tvrdí víc, než data unesou. Nese to
`ActivityLog.Stored.isUnreadable` a **chybějící soubor se od nečitelného odlišuje dřív než
dekódováním** (`Data(contentsOf:)` vyhodí u obojího): první spuštění je normální stav, ne porucha.
Kreslí to prázdný stav sekce, ne stavový řádek — je to odpověď na otázku, kterou si člověk klade
zrovna nad tou obrazovkou.

### Blok na dashboardu (#443)

**Do dění se musí jít, a to je to, co #443 opravuje.** Sekce je dobré místo, když už vím, že je do
čeho koukat — jenže odznak v railu říká **počet, ne co se stalo**, takže se člověk musí přepnout,
aby to zjistil. Dashboard je jediná obrazovka, na kterou se podívá, aniž by se ptal, takže na něm
stojí **pět nejnovějších řádků** a cesta do sekce (návrh, sekce 31).

**Sekci to neruší** (poznámka 98 v návrhu): rolovat, číst po dnech a dohledávat se chodí dál sem.
Blok je **ukázka a rozcestník** — bez vlastního prázdna, bez vlastního pruhu poslední návštěvy a bez
vlastního řádku. Kdyby si je pořídil, jsou to dvě dění. Do #443 stálo v hlavičce `ActivityFeedView`,
že dění blokem na dashboardu **není**; ukázalo se, že ta ukázka je právě to, co chybí, a ten komentář
je proto přepsaný i s důvodem.

Šest věcí, které se u něj nemají rozbít:

- **Značku poslední návštěvy blok neposouvá.** Posouvá ji jedině odchod ze sekce
  (`syncActivityVisit()`); kdyby ji posunul pohled na domácí záložku, vynulovalo by se nepřečtené
  a odznak v railu by zmizel, aniž bych něco přečetl. Drží to `isActivityVisible` (rail **a** domácí
  záložka), takže dashboard tou podmínkou neprojde — a je na to test (`AppStoreFeedTests`).
- **Třetí blok pravého sloupce, pod `Co teď`** (poznámka 97) — zaplňuje díru, kterou tam nikdo
  nevyužíval. Změřeno nad mockupem: levý sloupec s oběma frontami je **578 bodů** vysoký a pravý
  s legendou a akcemi **153**, takže pod ním zbývalo **425 bodů prázdna**. Blok má **266**, pravý
  sloupec s ním doroste na **419** a pořád zůstane o 159 kratší než levý. **Pás pod oběma sloupci
  byl první zákres a bylo to špatně**: začínal by *až pod* tou dírou, tedy dole na obrazovce, kam se
  nikdo nedívá — a poznalo se to teprve na běžící aplikaci, protože prázdné místo je vidět v okně,
  ne v poznámce. Pořadí obrazovky (*karty → fronty a Co teď → dění*) se tím nemění: dění je minulost
  a zůstává poslední.
- **Řádek je týž `ActivityRowView`.** Vyčleněný ze `ActivityFeedView` do vlastního souboru spolu
  s osou (`ActivityTimeline`): dvě podoby jedné události by se rozešly stejně, jako by se rozešly dvě
  podoby řádku fronty. Liší se **jediná věc** — `place` (`ActivityRowPlace`).
- **Cenou je úzký tvar řádku, a ta cena se platí obsahem, ne zalomením.** Pravý sloupec je `1fr`
  z `1.45fr 1fr`, tedy **456 bodů** z 1134, a celá událost se do nich nevejde: má **42 až 66 bodů**,
  tedy dvě až tři patra. V bloku proto zůstává **titulek, `repo#číslo` a čas** a podrobnost, sha,
  chip `bez banneru`, autor i cíl se vynechávají — řádek pak má **24 bodů**, jednu řádku jako
  v sekci. **Nezalamuje se**: co se nevejde, ořízne **titulek** (`lineLimit(1)` a `.tail`), protože
  `repo#číslo` a čas jsou souřadnice, podle kterých se pozná, čeho se to týká. Že ustoupí zrovna
  titulek, drží `layoutPriority` na slugu a času — je to `flex: none` z návrhu; bez něj by `HStack`
  krátil všechny tři naráz.
- **Den u času.** V sekci ho nese hlavička dne (`Dnes`, `Včera`, `čtvrtek 20. srpna`), tady ho
  nemá kdo nést, takže by `v 7:58` u včerejší události tvrdilo dnešní ráno. Rozhoduje o tom
  `Policy.activityTime(of:now:at:)` a je to **jedno místo**: dva výpočty téhož by se rozešly
  právě v tom, co je vidět jeden den v roce. **Jeden příznak, ne dva** — úzký tvar i den plynou
  z místa, ne z události, takže je nese `ActivityRowPlace`; dva booleany by šly nastavit křížem
  a vznikla by z toho třetí podoba, kterou návrh nekreslí.
- **Bez pruhu `Tady jsem skončil` a bez dělení po dnech.** Nad pěti řádky by pruh dělil pět řádků na
  dvě hromádky a hlavička dne by přidala šestý řádek textu. Nepřečtené nese **počet v nadpisu**
  (`Dění · 3 nové`, totéž číslo jako odznak v railu) a den čas u řádku. **`LazyVStack` sem taky
  nepatří** — pět řádků je strop z `Policy`, ne odhad.

Prázdný blok je **jedna věta**, ne díra a ne obrazovka ze sekce: `ActivityEmptyState` má u sebe
tlačítka (zapnout hlášení, otevřít Nastavení systému) a ta patří tam, kam jsem přišel schválně. Na
dashboardu z nich zbude důvod a cesta odkazem `celé dění →` v hlavičce. Věty jsou proto kratší, ale
**pořád čtyři** — klid, ztracená historie a dvě mlčení se nesmí slít ani tady.

### Zastaralé nálezy z tiku (#420)

Novinka *nálezy zastaraly* byla od #414 v dění nakreslená a fungovala, jenže se zapsala teprve
tehdy, když aplikace novou hlavu **poznala** — tedy při otevření PR nebo při běhu review. To je
zrovna ten okamžik, kdy je rozchod vidět i bez dění (hlavička nad taby o něm mluví), takže
**novinka, která přijde jedině tehdy, když se koukám, přináší nulu**. Od #420 to pozná tik.

**Jak to jde bez `N+1`:** `gh search prs` `headSha` nenese, ale to, co z detailu dělá `N+1` past,
není hlava — je to **volání na PR**. GraphQL bere víc aliasovaných kořenových polí v jednom
dokumentu, takže `headRefOid` pro celou frontu je **jedno** volání bez ohledu na to, z kolika
repozitářů fronta je (u téhle instalace devět až jedenáct). Skládá to `PullRequestHeadsQuery`,
posílá `GhGateway.fetchHeads(of:)`.

Cena se drží třemi věcmi naráz, a je to tatáž škola jako u rozhlídky po diskuzi (#335):

| Co drží cenu | Jak | Změřeno |
|---|---|---|
| **Jedno volání, ne jedno na PR ani na repozitář** | aliasovaný dokument, `cost` nezávisí na počtu | 12 aliasů z 10 repozitářů: **1 bod z 5000/h**, 1,25–2,59 s, 1,9 kB. 24 aliasů: **pořád 1 bod**, 1,25–1,96 s, 4,9 kB |
| **Předfiltr `updatedAt` je zadarmo** | ptáme se jen na PR, jehož `updatedAt` se posunul od posledního dotazu (`AppStore.headProbes`) | na klidný den **nula volání** — prázdný seznam se nespouští |
| **Jen PR s uloženými nálezy, a jen cizí** | `reviewRecords` v paměti; `Policy.pullRequests(_:ownedBy: .theirs)` | z fronty zbyde hrstka; vlastní PR se neptá **nikdy**, protože o nich se nehlásí (#332) |

**Strop 20 PR na dotaz** (`Policy.staleHeadProbeLimit`) ohraničuje **velikost dokumentu**, ne počet
volání — cena je podle měření na počtu aliasů nezávislá. Co se nevejde, dojde na příští tik, protože
razítko dostane jedině PR, na kterou se **doopravdy ptalo** a odpověď dorazila.

**Řádek nese čas události, ne čas zjištění.** Nálezy zastaraly ve chvíli, kdy vznikla nová hlava,
takže dotaz si říká i o `committedDate` toho commitu (`PullRequestHead.committedAt`) a
`Policy.staleFindingsActivity` datuje řádek jím. Bez toho by po každém spuštění aplikace vypadalo,
že práce z minulého týdne zastarala dneska — a restartuje se po každém mergi. Rozhoduje o tom
**`Policy`**, ne `??` na volajícím: obě cesty (dotažený detail přes `Policy.commitDate(of:in:)`,
dávkový dotaz přes `committedAt`) musí datovat stejně, jinak by měl tentýž rozchod dvě data podle
toho, kdo si ho všiml první.

Dvě věci, které z toho plynou a nejsou zjevné:

- **`commits(last: 1)` je jediná drahá část dotazu.** Bez ní přijde odpověď za ~0,94 s, s ní za
  1,25–2,15 s (měřeno střídavě A/B/A/B, `cost` je v obou případech 1). Platí se to jedině v tiku,
  ve kterém se doopravdy ptáme. `oid` je v ní kvůli **ověření**, že poslední commit spojení je
  opravdu ta hlava (změřeno na dvanácti PR, že se shoduje u všech); neshoda znamená **datum nevíme**,
  ne datum cizího commitu.
- **Řádek nalezený se zpožděním padne do svého dne**, tedy pod značku poslední návštěvy, a nepočítá
  se jako nepřečtený. Je to vědomá cena: druhé razítko (událost pro kresbu, zjištění pro nepřečtené)
  by rozbilo invariant, na kterém stojí pruh `Tady jsem skončil` — nové položky jsou **předpona**
  seznamu (`Policy.activityFeed`). V běžném provozu ta situace nevzniká, protože aplikace běží
  a rozdíl mezi událostí a zjištěním je nejvýš jeden tik.

**O commitech se z tiku nemluví.** Kolik jich po hlavě nálezů přišlo, se dopočítat dá
(`Policy.commitsAfter`), jenže ze seznamu commitů — a ten se tahá až s detailem, takže by to byla
zpátky ta `N+1` past. Řádek z tiku proto řekne jen `hlava je teď <sha>`; číslo, které by se nemělo
o co opřít, je horší než žádné. Řádek z `loadDetail` počet má, a protože identita je klíčovaná
hlavou, zapíše ho ten, kdo je první — datum je z obou cest stejné.

**Selhání a chybějící odpovědi:**

- **Celý dotaz selhal** → razítka se neposunou, takže příští tik zkusí znovu (tatáž nesymetrie jako
  u razítka rozhlídky, #335). Do okna se to **nehlásí**: nic v něm netvrdí, že hlavy zná, a stav
  GitHubu drží stavový řádek z pollingu (`gitHubCall`). Jediný následek je řádek o tik později.
- **Jedna PR neodpověděla** (přejmenované repo, smazaný pull request, chybějící právo) → `gh` skončí
  nenulově, ale data ostatních pošle, takže se odpověď **nezahazuje** (tentýž případ jako
  `gh pr checks`, #209). Ta jedna PR v mapě prostě není a razítko nedostane — „nevíme“ se nesmí
  zapsat jako „zjištěno“, jinak by se na ni nezeptalo, dokud se `updatedAt` nepohne.
- **Bez záznamu dění se neptá vůbec.** Za zastaralé nálezy banner nechodí, takže je záznam jediný
  konzument; podmínka je proto `activityLog != nil`, ne `watchesPullRequestActivity` (ta jmenuje
  i notifikační centrum právě proto, že u ostatních druhů je druhým konzumentem).

### Které místo chce kterou množinu (#332)

| Místo | Množina | Proč |
|---|---|---|
| `pullRequests` (plný seznam z tiku) | obojí | z něj se uklízí a čte nastavení; rozřazení je zúžení **nad** ním |
| `visiblePullRequests` (po filtru) | obojí | základ pro obě sekce, klik na notifikaci podle něj pozná, že PR schoval filtr |
| sekce `Fronta` a `railQueueCount` | `.theirs` | odznak znamená „tolik lidí čeká na moje review“ |
| `hiddenQueuePullRequestCount` (lišta nad frontou) | `.theirs` | společné číslo by hlásilo schovaný řádek, který ve frontě nikdy nebyl |
| `listEmptyReason` | `.theirs` | tik jen s vlastními PR nechá frontu prázdnou, kdežto polling mlčí → `poll(.noPullRequests)` |
| karty `Čeká na mě` a `Blokuje`, blok `Čeká na moje review` | `.theirs` | blokující nález na vlastním PR mě neblokuje, je to moje práce |
| karta a blok `Moje PR` | `.mine` | druhá fronta (#331) |
| karta `Rozdělaná review`, sekce `Rozdělaná` | obojí | draft je ručně psaná práce; od #333 na vlastním PR nevznikne, ten starší se nesmí ztratit |
| `queueSummary` (stavový řádek) | `.theirs` | jedna věta o frontě — „2 rozdělaná“ z pěti, mezi kterými jedno není, si odporuje |
| `pullRequestsNotReviewed` (hromadné spuštění) | `.theirs` | akce nad frontou; „fronta je vyřízená“ vedle ní mluví o téže množině |
| `Policy.automaticallyReviewable` | `.theirs` | **pravidlo, ne nastavení** — viz níž |
| `Policy.reviewNotification`, `announceNewPullRequests` | `.theirs` | notifikace je odpověď na review request |
| `handleNotificationClicks` | obojí | klik musí vybrat i vlastní PR |
| úklid: `forget(whatIsNotIn:)`, `CacheEviction`, `ReviewStore.cleanUp` | obojí | klon vlastního PR zabírá místo stejně jako cizí |
| `knownRepositories` (nastavení), `filterOptions` | obojí | přenastavit chci i repo, ve kterém mám jen svoje PR |
| paleta ⌘K | obojí, rozřazené do **dvou skupin** (#336) | katalog čte plný seznam a `Policy.ownership` z něj skládá `Pull requesty k review` a `Moje PR`; ⌘K jen hledá, nic neuklízí |

- **Automat vlastní PR nevydá nikdy, a přepínač se zamítl** (#332). Filtr je v
  `Policy.automaticallyReviewable` **první v řadě**, takže se PR dál nezvažuje, ať si repo řeklo
  cokoli. Tři důvody: automat existuje kvůli **čekání** (u vlastního PR není na co čekat), vlastní
  PR se **mění pod rukama** (každý push je nová hlava, tedy nálezy proti kódu, který za deset minut
  nebude) a přepínač by přinesl jedině **způsob, jak to pravidlo porušit omylem**. `mine` proto
  u téhle funkce **nemá výchozí hodnotu**, na rozdíl od `Policy.dashboard`: prázdná množina znamená
  „nikdo nejsem“, takže by zapomenutý parametr pravidlo tiše vypnul — a tady se za průchod platí
  session. `autoRunsPerDay` zůstává **jeden společný** limit; dvě poloviny jsou dohromady
  dvojnásobek. **Ruční spuštění** (`startReview`) pravidlem dotčené není.
- **Notifikace o vlastním PR nechodí ani o nálezu, ani o novém PR** (#332). Všechny tři události
  doběhlého review (`findings`, `clean`, `failure`) jsou odpověď na review request a „Nový PR
  k review“ o vlastním pull requestu je hláška o vlastním pushi. Zúžení u nových PR je **na
  vstupu**, takže se vlastní PR nedostane ani do snímku ohlášených (`AnnouncedPullRequests`) —
  vypadnou z něj samy, takže nic neroste. **Dokud login nedorazí** (`gh api user` běží souběžně
  s prvním tikem), je podle `Policy.ownership` všechno cizí, takže vlastní PR z prvního tiku se
  ohlásit může; druhá strana by byla mlčet, dokud login nedorazí, a při selhaném dotazu by to
  znamenalo ztracené notifikace o **cizích** PR. Vlastní text pro vlastní PR je #335.
- **Čí je PR se u notifikace bere ze seznamu** (`AppStore.author(of:)` → `pullRequests`, teprve pak
  dotažený detail). Review se pouští z řádku nebo ze záložky, takže tam autor je; review path si
  detail dotahuje sám a do `detailStates` ho nepíše, což je vidět v testu — bez tiku by z vlastního
  PR vyšlo `.theirs`.

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
- **Blokující se počítá jedinou funkcí** (`blockingCount(in:categories:)`) a **z platných
  nálezů**. Bydlí u `isBlocking`, ne u toho, kdo se ptá: od #172 se na to ptají dvě místa —
  notifikace a řádek seznamu — a druhá kopie by znamenala, že banner a seznam umí napočítat
  každý něco jiného. Odmítnutý nález (#113) se nepočítá nikde, protože přesně kvůli tomu
  účinku se odmítá.
- **`QueueRow` je odvozený, ne uložený** (#172). Kolik blokuje a jak se nálezy rozdělily mezi
  reviewery, se počítá ze záznamu při každém překreslení — do `ReviewState` to nepatří, ten
  odpovídá na otázku „v jaké fázi to je“ a porovnává se na rovnost na spoustě míst. Tři věci,
  na kterých ten proužek stojí:
  - **Díl na běh, ne na reviewera ze sady.** Kdo neběžel, v proužku není; kdyby tam byl,
    tvrdil by proužek něco o výsledku, který neexistuje.
  - **Váha je počet platných nálezů, minimálně 1.** Reviewer, který doběhl čistý, musí být
    vidět — s nulovou šířkou by z proužku zmizela právě ta informace, že vůbec běžel.
  - **Pět výsledků, které se nesmí slít**: `blocking`, `findings`, `clean`, `dismissed`
    a `inconclusive`. `dismissed` není `clean` ze stejného důvodu jako u `ReviewState` (#113),
    a `inconclusive` (spadlo, vytimeoutovalo, nereportovalo, ztratilo nález, **neotevřelo kód**)
    není `clean` proto, že zelený díl by tvrdil klid tam, kde se nálezy nemají kde vzít. Od #383
    o tom rozhoduje `Policy.inconclusiveReason(of:)`, ne vlastní dvojice `if`ů — do té doby svítil
    proužek zeleně nad během, u kterého chip vedle něj hlásil `nejisté`.
  - **Nejistota přebíjí odmítnutí.** Běh, kterému se ztratil nález, vyjde `inconclusive` i tehdy,
    když jsem všechno, co dorazilo, odmítl: ztracený nález jsem neviděl, takže „všechno
    odmítnuto“ by nad ním tvrdilo víc, než data unesou. Pořadí kontrol je proto **nálezy →
    nejistota → nedoběhlo → odmítnuto → čisto**, ne naopak.

  Barva stavu se řídí týmž pravidlem, jen o patro výš: `timedOut` a `interrupted` zůstávají
  **červené i bez nálezů**. Oranžová znamená „něco se našlo“, kdežto u nich je hlavní zpráva,
  že běh neskončil — `timeout · 0` oranžově by vypadalo jako výsledek.
- **Barvy drží `Palette`, ne systém** (#180). Šedá z macOS je neutrální, kdežto návrh stojí na
  neutrálech posunutých **do modrofialové**, tedy do stejné rodiny jako akcent; na jednom prvku je
  ten rozdíl nepatrný, na celém okně je vidět. Paleta je **jeden zdroj** — barva se nesmí skládat
  v každém view zvlášť, jinak má okno dvě „skoro stejné“ šedé.
  - Světlá i tmavá varianta jde přes `NSColor(name:dynamicProvider:)`, protože jen ten se přepne
    **za běhu**; dvě konstanty s `@Environment(\.colorScheme)` by znamenaly, že barvu řeší každé
    view samo.
  - **Akcent je fialový z návrhu, ne systémový.** Je to jediná barva, kterou si okno drží samo:
    stojí na ní identita aplikace (hranol, spektrum reviewerů), a spektrum by se systémovým
    akcentem měnilo význam podle nastavení systému. Nasazuje se `tint`em **na kořen okna**, takže
    ho dědí odznaky i tlačítka uvnitř a nikde jinde se fialová nezadrátovává.
  - **Sémantická škála jde celá z palety** (#432): `ok`, `find`, `crit`, `stale` — nikde v `App/`
    se nekreslí systémová `.green`, `.red`, `.orange` ani `.yellow`. Do #432 to bylo naopak
    (systém na desítkách míst, tokeny jako výjimka u `zastaralé` a `dismissed`) a stálo to
    **čtyři kapsle s kontrastem 1,63 až 2,70** ve světlém režimu, tedy pod hranicí čitelnosti.
    Důvod je v tom, na co je která barva navržená: systémová `.green`/`.red` je **výplň** ovládacího
    prvku s bílým textem, kdežto tady je to skoro vždycky **text nebo glyf na tlumeném washi**
    (`tint.opacity(0.15)`); tokeny jsou přesně na tohle ztmavené. Naměřené hodnoty před a po jsou
    v `PillTypesettingTests`, pravidlo hlídá `StatusScaleTests` nad zdrojáky.

    Ze systému **zůstávají tři věci a každá s důvodem**: `.secondary` (není barva ze škály, ale
    „nemám co říct“ — drží se kontrastem okolí), `.purple` u `merged` (3,42 ve světlém, tedy nad
    hranicí, a paleta purpurovou mimo vyhrazený akcent nemá) a `.blue` u `renamed` ve stromu
    a `moved` u přenosu draftu — ta je ve světlém režimu na **2,85**, tedy pod hranicí, ale mimo
    třídu #432 a mockup pro ni token nemá; je to zapsaná mezera, ne záměr.
  - Rozměry chrome jsou z návrhu doslova (hlavička 40 bodů, odsazení 13, mezera 14, záložka
    `5×11` s poloměrem 7) a **ověřené měřením**, ne odhadem — viz `docs/testovani.md`.
- **Okno je rail plus záložky** (#180), ne `NavigationSplitView`. Seznam PR byl do té doby
  **trvalý levý sloupec**, takže diff nikdy neměl celou šířku — a při čtení kódu se v seznamu
  nehrabe. Teď je obsahem domácí záložky a otevřená review jsou záložky vedle ní. Pět věcí,
  které se u toho nemají rozbít:
  - **Záložka nic nevlastní.** Stav je jen `[PRIdentifier]` a aktivní záložka; diff, konverzace,
    draft i běh visí ve store na `PRIdentifier` jako dosud. Zavření proto **nesmí nic zahodit** —
    má na to vlastní test.
  - **Po zavření se jde na sousední záložku**, ne domů: zavírá se doprojité review a další v řadě
    je to, co člověk chce vidět. Domů se propadne, až když nezbyde žádná.
  - **PR, který vypadl ze seznamu, si záložku drží.** Mergnutý pull request jde ještě dočíst
    a zavřít ho má člověk, ne tik pollingu. Když o něm nevíme ani titulek, řekne se to místo
    prázdné plochy. **Merge z panelu (#465) je druhá strana téhož pravidla, ne výjimka z něj**:
    záložku tam zavírá taky člověk, jen tím klikem, kterým PR dokončil — takže se po vlastním
    mergi do toho prázdného stavu vůbec nedojde.
  - **Sheet odeslání zůstává na `ContentView`.** Detail zmizí, jakmile PR vypadne ze seznamu,
    a odeslané review `review-requested` ruší — sheet zavěšený na detailu by zmizel uprostřed
    odesílání.
  - **Rail má jen položky, které mají obsah.** Návrh jich kreslí šest; položka, po jejímž otevření
    je prázdno, je horší než položka, která ještě není. `Přehled` přijde s dashboardem (#181),
    `Historie` a `Zdraví` potřebují napřed obsah, který v aplikaci není.
- **Otevřít PR umí jedna metoda** — `AppStore.openTab(_:in:)` (#409). Jsou to totiž **dva zápisy**
  (`openTabs` a `activeTab`, k tomu `selection` a snímek shrnutí), takže „otevřít PR“ se dá provést
  napůl — a přesně to bylo #409: obsluha kliknutí na notifikaci je z #82–#88, kdy otevření **byl**
  výběr řádku, takže po záložkách (#180) nastavovala jediné `selection`, tedy stav, který v domácí
  záložce nikdo nekreslí. `activeTab` zůstal na `.home` a z kliknutí bylo „aplikace naskočila
  a nic“. Chodí sem klik v seznamu, karty dashboardu, paleta ⌘K, klik na notifikaci a od #414 řádek
  dění. Tři věci k tomu:
  - **Volitelný `tab` otevře PR na konkrétní záložce**, protože skok na nález nebo na řádek dění by
    nad zavřenou záložkou neměl kde přistát. Do #409 to skládala paleta ⌘K vlastní privátní
    metodou (`show(_:in:)` = `openTab` + `setDetailTab`); jedna metoda znamená, že druhý volající
    nemá co opisovat.
  - **`tab: nil` uloženou volbu nepřepisuje.** Volba je odpověď na „kam se v tomhle PR koukám“
    a drží se per PR (`detailTab(for:)`), takže otevření bez upřesnění vrátí člověka tam, kde
    skončil — a klik na notifikaci tab **nejmenuje**, protože proud kliknutí nese `PRIdentifier`,
    ne událost; vybíral by ho naslepo.
  - **Odkaz na metodu se složit nedá** (`store.openTab(_:)`), protože má výchozí parametr — volající
    v `HomeView` proto předává uzávěr. Je to cena za jeden vstupní bod místo dvou přetížení.
- **Pruhem se přepíná `⌃Tab` a `⌃⇧Tab`** (#245), dokola a **včetně domácí záložky**. Pět věcí, na
  kterých to stojí:
  - **Cyklí se celý pruh, ne jen PR.** Pruh domácí záložku kreslí, chodí se na ni nejčastěji (je
    za ní fronta) a bez ní by `⌃Tab` nad jediným otevřeným PR nedělal nic. Pořadí je **pořadí
    pruhu** (`openTabs`, tedy pořadí otevření), ne pořadí použití: MRU je u dvou záložek
    nerozeznatelné a u pěti překvapivé.
  - **Zkratka nastavuje jedině `activeTab`, jako kliknutí na záložku** (`AppStore.selectTab(_:)`).
    Výběr řádku v seznamu (`selection`) je jiná věc a kliknutí s ním nehýbe — kdyby s ním hýbala
    zkratka, byly by dvě pravdy o tom, co je vybrané, a platila by ta, kterou se člověk zrovna
    přepnul. Je na to test, který srovnává stav store po zkratce se stavem po kliknutí.
  - **Rozhoduje `Policy.tab(_:after:open:)`**, ne `if` ve view: pruh je `[.home] + openTabs`
    a nad jedinou záložkou vrací `nil`, tedy „nestane se nic“ — ne pípnutí a ne propadnutí domů.
  - **`⌃⇧⇥` je pro AppKit jiná klávesa než `⌃⇥`** — doručí `U+0019` (backTab), ne `U+0009`.
    Zpětná zkratka proto visí na `KeyEquivalent.backTab`; zapsaná jako `.tab` s `[.control,
    .shift]` **nezabere vůbec**. Změřeno na běžící aplikaci i samostatným pokusem s `NSButton`em
    (podrobnosti a rozdíl proti pasti s `⌥⇧↓` z #151 jsou u `KeyEquivalent.backTab`).
  - **Fokus v textovém editoru tomu nevadí.** Změřeno v těle review i v composeru komentáře:
    `⌃Tab` přepne záložku, **do textu nevloží tabulátor** a nepřehodí fokus na jiný prvek —
    key equivalent tlačítka se vyhodnocuje dřív, než se klávesa dostane k `NSTextView`. Fallback
    `⌘⇧]` / `⌘⇧[` ze zadání issue proto **nebyl potřeba** a nepřidal se.

  Zkratky stojí v nápovědě u **domácí záložky** (`ReviewTabsView.homeTab`), protože `⌃Tab` po sobě
  v okně nenechává viditelnou stopu. Na pruhu samotném to nejde — `.help` nad `ScrollView`em se
  neprojeví ani v accessibility (`AXScrollArea` hlavičky zůstal bez `AXHelp`), kdežto tlačítka
  záložek svoje nápovědy nesou.
- **Dashboard je obsah `Přehledu`, ne druhý seznam** (#181). Po spuštění bylo do té doby vidět
  „Vyber pull request“, přestože čísla o frontě už v aplikaci byla — jen roztroušená po stavovém
  řádku a po řádcích. Šest věcí, které se u něj nemají rozbít:
  - **Počítá se z paměti store, nic se nedotahuje.** `Policy.dashboard` bere seznam z pollingu,
    `reviewRecords`, drafty a `SpendLedger`; žádné nové čtení z disku ani volání `gh`.
  - **Karty čtou plný seznam, ne zúžený filtrem** (#117) — tatáž úvaha jako u souhrnu ve
    stavovém řádku: dashboard je tvrzení o tom, co ve frontě **je**, ne o tom, co je vidět.
  - **Rozdělaná review se počítají stejným pravidlem jako v souhrnu** (#155): neprázdný draft na
    PR, který ve frontě je. První verze počítala všechny drafty na disku a karta pak ukazovala
    trojku vedle stavového řádku s jedničkou.
  - **Fronta se řadí podle závažnosti** (`Policy.byUrgency`), na rozdíl od seznamu, který je od
    naposledy změněného. **Zastaralé se nahoru nepouští, ani když nese blokující nález** — ten
    patří ke staršímu `headSha` (tvrdá podmínka č. 5), takže o dnešním kódu netvrdí nic.
  - **Řádek fronty je tentýž `PullRequestRow` jako v seznamu** (#172). Druhá podoba téhož řádku
    by se s ním dřív nebo později rozešla.
  - **Karta nemluví o tom, co neví.** Draft z doby před #181 razítko nemá, takže se u něj místo
    stáří píše „čeká na dopsání“; blokující nález bez kategorie nechá kartu u čísla.
  - **Blok kreslí nejvýš pět řádků, ale karta počítá dál celou frontu** (#371). Strop je **o kresbě,
    ne o množině**: `Čeká na mě` ukazuje 13, i když je pod ní pět řádků a patka `Zobrazit všech 13
    ve frontě +8 →`. Kdyby strop sestoupil do počítání, začal by dashboard tvrdit, že práce je méně,
    než jí je — a to je regrese, která se pozná až za týden. Bez stropu naopak blok roste s frontou
    a druhý blok skončí pod hranou okna (změřeno na živé aplikaci u #331: 32 PR, blok `Moje PR`
    o celou obrazovku níž). Skládá to `Policy.dashboardBlock`, takže se počet v patce nemůže rozejít
    s tím, kolik řádků se doopravdy nakreslilo, a **patka není řádek** — nepočítá se do `rows`, takže
    se nedostane ani do klávesové navigace, ani do toho, kolik řádků blok hlásí.
  - **Mezi posledním řádkem a patkou je jedna čára, ne dvě** (#371). Řádky kreslí oddělovač „mezi“,
    takže poslední ho nemá; s patkou za sebou by ho potřeboval — a kdyby si ho patka nakreslila sama,
    sečetly by se. Návrh to řeší tím, že patka **žádnou horní linku nemá** (v mockupu z toho bylo
    1 px + 1 px = 2 px, změřeno sondou nad `getComputedStyle`); v aplikaci kreslí tu jednu čáru
    `rows(_:emptyExplanation:)` před patkou. Je na to test z bitmapy (`DashboardFooterSeparatorTests`)
    — z kódu to vidět není, dvě jednobodové čáry pod sebou vypadají v obou souborech správně.
  - **Karta vede do své sekce, kromě `Dneska stálo`** (#371). Kam která vede, rozhoduje
    `Policy.destination(of:)` a cíl je **`RailSection`**, ne hotová akce — karta nemá vědět, že rail
    existuje. `Blokuje` vede do fronty **se zapnutým filtrem „jen blokující“**, protože bez něj by
    skákala na totéž místo jako `Čeká na mě`. `Dneska stálo` nevede nikam a nemá ani ukazováček, ani
    hover: karta, po které se nic nestane, je lež o tom, co okno umí (tatáž úvaha, kvůli které #331
    nekreslí `Prompt →` u řádku bez akce). **Patka bloku dělá totéž co karta nad ním.**
  - **Třetí blok pravého sloupce je od #443 `Dění`** — pět nejnovějších řádků a cesta do páté
    sekce railu. Je to **ukázka a rozcestník**, ne druhé místo, kde se dá v dění zůstat, a hlavně:
    **značku poslední návštěvy neposouvá.** Podrobnosti i změřená čísla jsou v sekci *Dění* níž.
  - **Příští tik je odpočet, poslední zůstává absolutní** (#237, otáčí #181) —
    `poslední tik 09:41 · za 43s znovu`. Odpočet **se nesmí platit přepočtem dashboardu**, takže se
    skládá ze dvou kusů a ten druhý (`DashboardCountdown`) si vteřiny odtiká sám ve svém
    `TimelineView`; kdyby se vpsal do interpolace, tikal by jen tak často, jak se dashboard
    překresluje. Co se v tom koutě píše, rozhoduje `DashboardTick`, tedy výčet nad třemi
    hodnotami — a **uplynulý termín je `ptám se…`, ne záporné číslo**: `nextPoll` zůstává po dobu
    dotazu v minulosti, takže odpočet dojde na nulu a šel by dál. Podrobnosti u `PollingService`,
    včetně toho, proč to drží observovatelný příznak a ne srovnání s hodinami.
  - **Mezi číslem a jednotkou není mezera** (#260) — `za 43s znovu`, nad minutu `za 12min 29s
    znovu`, nad hodinu `za 1h znovu`. Je to výslovné přání uživatele a **vědomá odchylka od české
    typografie i od mockupu**; kdo to „opraví“ zpátky, ruší rozhodnutí, ne překlep. Vynucuje si to
    **vlastní formát**, protože systémový (`Text(_:style: .relative)`, `Duration.UnitsFormatStyle`,
    `DateComponentsFormatter`) má mezeru v české locale ve všech variantách — a s vlastním formátem
    i **vlastní takt**. Ten drží `TimelineView` ukotvený v termínu, takže hranice tiků padnou na
    celé vteřiny odpočtu; zbývající čas se **zaokrouhluje** (časovač se probouzí později, krácení
    by přeskočilo vteřinu) a záporný se sráží na `0s`. Cena je změřená a rozhodnutí z #237 drží:
    tělo nad odpočtem se přepočítá jednou, formát stojí 0,12 µs na tik.

    **První změna hodnoty přijde až na druhém tiku rozvrhu** (změřeno u #269): `TimelineView`
    vykreslí při nasazení hodnotu **prvního** tiku, který leží v budoucnosti, a další překreslení
    naplánuje až na tik po něm — po otevření okna tedy první hodnota vydrží 1 až 2 vteřiny a teprve
    pak jde odpočet po vteřině. Od pravdy se přitom neodchýlí o víc než vteřinu, takže na obrazovce
    to není poznat; **poznat je to v testech**, kde na tu změnu musí sonda čekat, a stálo to jeden
    červený `main` (viz [`docs/testovani.md`](testovani.md)).

  **Co teď** jsou akce, které dávají smysl teď — řádek, který by nic neudělal, se nekreslí.
  Hromadné spuštění se **ptá na potvrzení**, protože je to jediné místo v aplikaci, kde jedno
  kliknutí utratí víc než jednu session; návrh potvrzení nemá a je to vědomá odchylka. Zkratky
  u akcí jsou opravdové (`keyboardShortcut`), ne nakreslené chipy.

  Sloupce jsou v poměru `1.45fr 1fr` z návrhu (`ProportionalColumns`) — `HStack` umí jen rovným
  dílem a pevná šířka pravého sloupce by se s oknem rozešla.
- **Potvrzení odeslání vypisuje payload, ne draft** (#178). Do té doby si sheet skládal místo
  komentáře `Policy.location(of:)`, tedy **druhý** popis téhož — a `side` ani `start_line` v něm
  nebyly vůbec, přestože právě ony rozhodují, ke kterému kódu komentář na GitHubu sedne. Teď se
  bere z `PublishRequest.payload(for:)`, takže se výpis s odeslaným tělem nemůže rozejít; jména
  polí zůstávají anglická ze stejného důvodu jako `APPROVE` u verdiktu. **Chování se tím
  nemění** — tvrdá podmínka č. 1 platí beze změny.
- **Hlavička PR ukazuje větve a dvě sha** (#174). `PullRequest` nese `headRef`/`baseRef`
  s **prázdnou výchozí hodnotou**, takže starší uložená data i odpověď bez těch polí projdou —
  tatáž úmluva jako u `body`. Hlava PR a sha, proti které platí nálezy, se kreslí **jen když se
  rozejdou**: do té doby je to řádek s údajem, který nikoho nezajímá.
- **Nálezy v panelu jsou karty, ne tabulka** (#175). `Table` se při šířkách z #60 nedala
  nasázet: kategorie, místo a shrnutí se perou o místo, odmítnutí (#113) muselo skončit jako
  odznak u kategorie a delší nález se vešel na dva řádky bez možnosti rozbalit. Karta nese
  závažnost **proužkem na hraně**, a to toutéž škálou jako řádek fronty (#172) — seznam a panel
  nesmí o téže věci říkat každý něco jiného. Karta pod kurzorem procházení (#187) má rámeček,
  takže je z lišty i z panelu poznat **totéž** místo; na tom stojí invariant, že
  `FindingPlace(finding) == FindingPlace(group)`.

  **Řazení podle sloupců se tím ztrácí a je to vědomé.** Nálezů je typicky pod dvacet,
  `Policy.sorted` je řadí podle závažnosti a zúžit je jde filtrem reviewerů i přepínačem
  `jen blokující`. `FindingRow` ale zůstává i se svými `Comparable` klíči — kdyby řazení
  chybělo, vrátí se tabulka jako **druhý pohled**, ne místo karet.
- **Skok míří na řádek, ale v seznamu je blok** (#187, oprava chyby z #157). Souvislé řádky se
  před vykreslením slévají do bloku kvůli výběru textu a blok nese `id` **jen toho prvního** —
  `scrollTo` na řádek uprostřed úseku tedy tiše neudělá nic. Blok si proto pamatuje `id` všech
  řádků, které do něj spadly, a `DiffView` si cíl přeloží (`DiffRow.blockIDs(in:)`) **týmiž
  vstupy, jakými ten soubor kreslí**: kde se blok přeruší, závisí na bublinách, vláknech,
  komentářích i odkrytých úsecích, takže index z jiných vstupů by ukazoval na blok, který
  v seznamu není.

  Byla to tichá chyba i pro skok z panelu, jen si jí nikdo nevšiml: nález na prvním řádku bloku
  (hned za hlavičkou hunku) fungoval. `DiffRow.anchor(in:comment:layout:)` má tutéž past
  zapsanou od split pohledu — u nálezů se nedotáhla.
- **Kurzor procházení drží místo, ne index** (#187). Seznam nálezů se pod rukama mění —
  doběhne další reviewer, nález se odmítne, zapne se zúžení — a index by po každé takové změně
  ukazoval jinam, aniž by se cokoli stalo. `FindingPlace` je `file:line`, tedy totéž, čím se
  skupina identifikuje v diffu. Čtyři pravidla:
  - **Odmítnuté se přeskakují.** Nález, kterému nevěřím, není práce k projití; kdyby v řadě
    zůstal, „prošel jsi všechno“ by znamenalo i „proklikal jsi to, co jsi zamítl“.
  - **Hotovo = projitá všechna místa**, ne „stojím na posledním“. Přeskákat je zprostředka
    a skončit na konci neznamená, že jsem viděl i ta před tím — a zelený puntík je jediné
    místo, kde okno tvrdí, že je práce hotová.
  - **Nálezy bez místa v kódu se počítají zvlášť** (`withoutPlace`). Skočit se na ně nedá, ale
    zamlčet je nejde: „1 z 1“ by nad PR se dvěma nálezy v panelu tvrdilo hotovo.
  - **Ztracené místo pod kurzorem shodí pozici, ne seznam.** Ukázat „4 ze 3“ je horší než
    přiznat, že nikde nestojím; z takového stavu se jde dopředu od začátku.

  Kurzor **nesmí přetéct mezi pull requesty** (na rozdíl od ztlumených reviewerů nebo pohledu
  na diff): `file:line` z cizího PR je náhodná shoda a „prošel jsi všechno“ se rozhoduje z toho,
  co je v tomhle diffu. Zúžení `jen blokující` přetéct **smí** — je to způsob čtení.

  Zvýraznění po skoku zůstává **dočasné**, jak bylo od #20: trvalý rámeček by se pletl
  s blokujícím nálezem. Kde stojím, drží lišta, ne barva v diffu.
- **`⌥⇧↓` je pro SwiftUI tatáž zkratka jako `⌥↓`** (#151, oprava chyby z #187). U šipek se
  `.shift` při párování **ignoruje**, takže dvě tlačítka lišící se jen jím jsou jedna klávesa
  a vyhrává to zaregistrované později. Do #151 tedy `⌥↓` dělalo „další blokující“ — a protože
  blokující nález bývá jeden, druhé zmáčknutí nikam neskočilo a vypadalo to, že zkratka je
  rozbitá. Změřeno na běžící aplikaci **oběma směry**: po odebrání varianty se shiftem začalo
  `⌥↓` procházet nálezy a `⌥⇧↓` skákalo po tom samém.

  Je proto **jedno tlačítko** a shift se čte z `NSApp.currentEvent`, tedy z události, která akci
  spustila. Ne `NSEvent.modifierFlags` (stav klávesnice): ten se u synthetických kláves ze
  `System Events` nemění, takže by se to nedalo vyzkoušet — a vyzkoušet se to musí, protože
  zkratka je jediné, čím se ta cesta spouští.

  **Zkratky bydlí na detailu PR, ne na tlačítkách v liště** (`hiddenShortcuts`): skočit na nález
  jde i z `Přehledu`, kde lišta v okně vůbec není, a tlačítko mimo okno svou zkratku nemá kde
  zaregistrovat.
- **„Od tvé poslední návštěvy“ stojí na dvou různých značkách** (#173). `VisitLedger` je to,
  co přežije restart; `AppStore.visitSnapshots` je to, **proti čemu se počítá v tomhle běhu**.
  Zapsat návštěvu se musí hned při zobrazení, jinak by o ní příští start nevěděl — jenže tím by
  se banner spotřeboval při prvním přepnutí tam a zpět. Snapshot se proto nastaví jednou za běh
  a dál se nemění; je to tentýž vzor jako odznaky `nové` u novinek (#127). Tři pravidla, která
  se u toho nemají rozbít:
  - **Bez značky se neukáže nic.** PR viděný poprvé nemá „od minule“ — vypsat celou jeho
    historii by tvrdilo, že to všechno přibylo teď.
  - **Porovnává se ostře** (`>`), takže položka, která přišla v tutéž sekundu jako návštěva,
    se příště nezopakuje. A **událost bez data se zahazuje**: `nil` znamená „nevíme kdy“
    (`TimelineEvent.at`), kdežto řádek v banneru tvrdí „přišlo to teď“.
  - **Moje vlastní komentáře nejsou novinka.** Banner odpovídá na to, co se stalo, když jsem se
    nedíval.

  **Od #335 zakládá značku i rozhlídka po cizí aktivitě** (`seedVisitBaseline(for:)`), ale
  **návštěvu nezapisuje**: dotažení konverzace na pozadí návštěva není — kdyby se zapsala, značka by
  se posunula na teď a řádek by o komentáři kolegy mlčel. Vedle toho stojí **druhé razítko**
  (`ActivityNoticeLedger`) na otázku „o čem už se hlásilo“; proč jsou to dva typy a ne dvě pole
  v jednom, je v *Cizí aktivita na vlastních PR* (#335) výš.

  Snapshot se posouvá **při odchodu na jiný PR**, ne při každém otevření a ne až s koncem
  aplikace. Odejít a vrátit se je nová návštěva — během té první byl banner na obrazovce, takže
  se podruhé neukazuje; uvnitř jednoho PR se ale nemění nic, aby o něj odskok do `Změněných
  souborů` a zpátky nepřipravil. Podmínkou je **načtená konverzace** toho opouštěného PR: bez ní
  se banner nemá z čeho vykreslit, takže na obrazovce nebyl, a projetí seznamu šipkami by jinak
  zahodilo novinky u všech PR, přes které jsem přejel.

  Vedle toho jde zavřít **ručně** (`markChangesAsSeen`) křížkem — to je pro „vím to hned teď, ať
  to nezabírá místo“. Zavření posune **obě** značky, jinak by se pruh po restartu vrátil.

  **Odrážky se od #284 sázejí po částech.** Do #284 to byl `[String]` a jeden `Text(verbatim:)`,
  takže v řádku nešlo nic zdůraznit. Návrh (sekce 02, `.since li`) přitom sází tři různé věci:
  **co se stalo** tučně a plnou barvou (`li b`), zbytek věty ztlumeně a sha jako kód. Řádek proto
  skládá `SinceLastVisitLines` do typovaných částí (`SinceLastVisitLine.Part`) — mimo view, jako
  `TimelineEventRow`, aby se text testoval bez kreslení. Čtyři věci, které se u toho nemají
  rozbít:
  - **Věty se pořád skládají ve view, ne v `Policy`.** Je to próza pro člověka, ne rozhodnutí;
    #284 rozdělil jedno skládání na části, nepřestěhoval ho.
  - **Tučné znamená „co se stalo“** u vět, které si pruh skládá sám (počet commitů, přepsaná
    historie, verdikt review), ale u **událostí časové osy** znamená **jméno** — ty berou větu
    i s jejím zvýrazněním z `TimelineEventRow.attributedTitle`. Dvě různá pravidla schválně:
    druhé znění téže věty by se s tím prvním rozešlo a testy by hlídaly to, které není vidět.
  - **Autor commitů se uvádí, jen když je jeden.** „od odinuv“ nad commity dvou lidí je tvrzení,
    které v datech není; jméno pak vypadne celé a počet se sha zůstanou.
  - **Sha je podklad za písmem, ne kapsle s odsazením** — vědomá odchylka od návrhu
    (`code { border-radius: 5px; padding: 1px 5px }`) a **tatáž volba, jakou už udělal inline kód
    v sazbě Markdownu** (`MarkdownInlineText.highlightCode`, #279): `AttributedString` umí u běhu
    nastavit barvu pozadí, ne jeho výplň a rádius, takže kapsle by znamenala kreslit každou sha
    jako vlastní view — a tím rozpadlé zalomení uprostřed věty. Odrážka je v úzkém `Přehledu`
    (128 bodů) zalomená vždycky, takže je to výměna „zaoblené rohy“ za „věta se dá přečíst“.
    Barva podkladu i písma je z návrhu (`--accent-weak`, `--ink`), velikost z jednoho zdroje se
    sazbou Markdownu (`MarkdownTypography.codeSize`).

  **Pod odrážkami stojí řada ovládání** (`.since .row`, #284) — do #284 to byla věta a tlačítko,
  které visely na jednom `isStale`. Tři kusy a každý má vlastní podmínku:
  - **odznak `nálezy zastaraly`** (`.pill.stale`) jedině tehdy, když nálezy proti staršímu commitu
    doopravdy jsou. Čte `AppStore.staleFindings(for:)`, tedy **tentýž zdroj** jako hlavička
    `StaleHeadView` nad taby — dvě porovnání sha by znamenala dvě pravdy o jedné věci. Nula nálezů
    je běžný stav (review doběhlo čistě) a odznak se u něj nerozsvítí, kdežto hlavička o rozchodu
    mluvit má: `StaleFindings.hasFindings` je právě ta hranice mezi nimi;
  - **`Pustit review znovu`** i tehdy, když **žádné nálezy zatím nejsou** — po přepsané historii
    je to ta rozumná další věc. Do #284 se v takovém případě nenabídlo nic, což byl bod 3 zadání;
  - **`Ukázat, co přibylo`** jedině tehdy, když je co s čím porovnat (`Policy.incrementalDiff`).

  **Řada se v úzkém tabu zlomí do sloupce a rozhoduje o tom spočítaná šířka** (`SinceLastVisitView
  .fits(_:in:)`), ne `ViewThatFits`. Ten se na to spolehnout nedá a je to změřené: odznak i popisky
  tlačítek jsou vodorovně pružné, takže se ve zúžené řadě radši zkrátí, než by nahlásily, že se
  nevejdou — v liště rozsahového diffu z toho u #284 vyšlo `Jen t…` a `lineLimit(1)` ani `fixedSize`
  s tím nehnuly. Popisky jsou konstanty, takže se dají změřit (`TextWidth`) a o podobě řady se dá
  rozhodnout z jednoho čísla, jak to má #220. **Přetečení tuhle chybu nechytá** — zkrácený popisek
  nikam nepřeteče —, takže na ni je vlastní výčet (`SinceLastVisitActionsTests`) vedle měření
  přetečení (`OverviewWidthTests`).

  **Časový údaj a `×` v návrhu nejsou, v aplikaci ano, a zůstávají** (#284): bez `×` by pruh visel,
  dokud je aplikace spuštěná, a bez času by „od tvé poslední návštěvy“ neřeklo od kdy. Obojí sedí
  v hlavičce vpravo, tedy tam, kde návrh kreslí `.when` — přibývá k němu křížek, ne druhé místo.
  Ikona je od #284 `⟲` z návrhu (`arrow.counterclockwise`), ne hodiny: pruh mluví o tom, co se
  s větví stalo, ne o čase.

  **Sázen je podle návrhu (`.since`, #226) a má jen jeden tón** — okrový `--stale`. Do #226 bral
  systémový akcent (modrou) a při přepsané historii systémovou žlutou; obojí bylo mimo paletu okna,
  protože okno stojí na fialové z návrhu (#180) a systémová žlutá je **výstraha**, kdežto tenhle
  blok říká „platilo to, dneska už ne“ — přesně význam, na který #216 zavedlo `Palette.stale`.
  Že se přepsala historie, proto nese **odrážka a řada ovládání** (do #284 věta s tlačítkem), ne
  odstín pozadí; barvou to rozlišovat nešlo, aniž by jedna z těch dvou byla mimo paletu. Graficky přibyl **obrys** (bez něj
  plavala plná barevná plocha vedle obrysových karet `Přehledu`) a levý pruh je **okraj rámečku**,
  ne `overlay` s obdélníkem — ten se v zaoblených rozích usekával místo aby s nimi zatočil.
  Poloměr je 7 jako u sousedních karet, ne 8.
- **Nové commity se nepoznají jen podle času** (#173). `TimelineEvent.at` je u commitu
  `committedDate`, ne čas pushnutí (`pushedDate` GitHub neplní, změřeno u #171), takže po rebase
  nebo cherry-picku je **starší než moje poslední návštěva** a commit z „od minule“ vypadne —
  banner by mlčel o změně kódu, což je ten nebezpečný směr. `VisitLedger` si proto vedle času
  pamatuje i **hlavu, kterou jsem viděl**, a `AppStore.movedHead(for:)` ji porovná s aktuální.
  Když se liší a časová osa nic nedala, řekne se aspoň „hlava se posunula na …“; kolik commitů
  to bylo, se z těch dat poctivě zjistit nedá. Hlava se zapisuje **až po načtení detailu**,
  protože při zaznamenání návštěvy ještě není známá — a `record` ji proto **nepřepisuje na
  `nil`**, jinak by ji každé mrknutí na PR zahodilo.

  `seenHeads` je `[PRIdentifier: String]`, ne `[PRIdentifier: String?]`: dvojitý optional dělá
  z „klíč tam je, ale hodnota je `nil`“ něco, co projde jako známá hlava, a první otevření PR se
  pak tváří jako posun. Chytil to test, ne čtení kódu.

  **Obě baseline se posouvají naráz** (`moveBaseline`), a je to podmínka, ne úklid: banner stojí
  na obou — `changes` na čase, „hlava se posunula“ na sha — takže po posunutí jen jedné zůstane
  viset kvůli té zapomenuté. „Přečteno“ i „návrat je nová návštěva“ by pak přestaly platit přesně
  v tom případě, kvůli kterému sha existuje: po rebase, kde časová osa mlčí.
- **`Ukázat, co přibylo` je diff mezi dvěma hlavami, ne výřez z toho celého** (#284). Aplikace
  uměla jedině `fetchDiff(id:)`, tedy `baseSha...HEAD`; rozsah z něj nijak nevyřízneme, takže
  přibyla čtecí metoda na `GitHubGateway` — proč zrovna přes `compare` a ne přes klon v cache, je
  u `GitHubGateway`.

  **Nabízí se jen tehdy, když je co s čím porovnat**, a rozhoduje o tom čistá funkce
  `Policy.incrementalDiff(from:to:rewroteHistory:)`. Potřebuje hlavu z minulé návštěvy
  (`seenHeads`), dnešní hlavu z detailu a to, že se **nepřepsala historie**; `rewroteHistory: nil`
  (nenačtená časová osa) se chová jako „přepsala“, protože nabídnout rozsah, o kterém nevíme,
  jestli dává smysl, je horší než ho nenabídnout. Tlačítko, které se nabídne a otevře celý diff,
  jaký člověk už viděl, je přesně to, co zadání #284 zakazuje.

  **Kreslí se v tabu `Změněné soubory`, ne ve vlastním tabu ani v sheetu.** Je to **pohled** na
  tentýž tab: `AppStore.incrementalDiffs` drží rozsah **vedle** `diffStates`, ne místo nich, takže
  celý diff — to, proti čemu se píše review — zůstává načtený a vrací se jedním tlačítkem v liště
  (`IncrementalDiffBar`). Nálezy, vlákna i rozdělané komentáře se předávají **beze změny**: kotví
  se na `soubor:řádek` **dnešní hlavy**, a čísla řádků na nové straně jsou v obou diffech tatáž,
  takže se pověsí na totéž místo; co v rozsahu není vidět, se chová jako soubor mimo diff.

  **Odznak u záložky a `+X −Y` v pruhu počítají to, co je vidět** (`shownDiff`), ne celý PR — pruh
  kousek nad diffem by jinak tvrdil sedm souborů nad dvěma. Dlaždice v `Přehledu` z toho **nečtou**:
  „Soubory: 7“ je fakt o PR a `Přehled` rozsah nikdy nekreslí.

  Rozsah se **drží** a druhé kliknutí ho nestahuje znovu (klíčem jsou dvě sha), **selhání se ale
  zkusit znovu smí** — jinak by tlačítko `Zkusit znovu` u chyby nic neudělalo. Doběhlé volání
  navíc zapisuje, jen když se mezitím rozsah nezměnil: jinak by v okně ležel diff, který k popisku
  nad ním nepatří.
- **`suggestedVerdict` vrací `nil`, když není z čeho soudit** — a je to vlastní odpověď, ne
  opatrné `approve`. Schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou
  aplikace umí udělat. Z běhu se dá vyvodit „je čisto“, jen když **doběhl**, **zavolal
  `ReportFindings`**, **nic nezahodil** a od #383 **otevřel aspoň jeden soubor z pracovní
  kopie**; zastaralý záznam nedá verdikt vůbec. Zahozený
  nález přitom bere `approve` **celému záznamu**, ne jen svému běhu — čistý výsledek jiného
  skillu o tom ztraceném nálezu nic neříká.
- **Ta čtveřice podmínek žije na jednom místě** (`Policy.inconclusiveReason(of:)`, #383) a je to
  změna proti stavu do #383, kdy si ji každý ze tří čtenářů skládal sám — a lišili se: `isConclusive`
  se ptal na hlášení a ztracené nálezy, chip revieweera na totéž v jiném pořadí, díl proužku u řádku
  taky, a **na čtení kódu se neptal nikdo**. Přesně ten druh „kontrola, která jinde v repu je, a tady
  chybí“.

  Dvě věci uvnitř té funkce nejsou zjevné: **běh, který něco našel, se na čtení kódu neptá**
  (nálezy mluví samy za sebe a odebrat kvůli tomu `approve` nad neblokujícími nálezy by byl
  poplach nad výsledkem, který je v okně celý vidět), a **pořadí důvodů je od nejkonkrétnějšího**
  (`droppedFindings` → `noReport` → `unreadCode`), protože „část nálezů se ztratila“ řekne, co
  dělat, kdežto „nepřečetl kód“ je nad tímtéž během pravda taky, jen řekne méně.
- **Čtení kódu se pozná z uložené osy, ne z ceny** (`Policy.codeReading(of:)`, #383). `CodeReading`
  má **tři** hodnoty a ta třetí je celý smysl toho typu: `read` (v ose je `Read` s cestou **uvnitř**
  stromu), `unread` (ani jeden, a přitom je u všech pokusů vidět, kam sáhly) a `unknown` — osa
  chybí (soubory z doby před #203, 15 ze 40 měřených běhů), nezná strom, je zkrácená (`dropped > 0`,
  ořezává se **začátek**, tedy ta část, ve které se čte nejvíc), nemá jediný pokus, nebo je v ní
  nástroj, u kterého cesta v záznamu **není**. Z chybějícího záznamu se nesmí stát obvinění — okno
  by se rozkřičelo nad každým starším review a hláška by se přestala čítat.

  Co do „nedá se soudit“ patří a proč, je vidět na uložených datech: **`Grep` nese vzor, ne cestu**
  (`ToolAttempt.detailKeys` má `pattern` před `path`), takže z `AJDA-3003` nejde poznat, jestli se
  hledalo ve stromě nebo v cizím transkriptu; **`Agent` a `Task` nemají detail vůbec**. Naopak
  **`Bash` mezi ně nepatří**, i když `cat` přes vestavěný seznam čtecích příkazů projde: kdyby
  patřil, pravidlo by se nespustilo nikdy — všechny čtyři doložené případy mají `git diff` uvnitř
  stromu. Tvrzení je proto úzké a přesně takové, jaké záznam unese: **neotevřel soubor**, ne
  „nedíval se do kódu“. A **`Glob` taky ne** — hledá jména, obsah nečte.

  Dvě čísla, na kterých to rozhodnutí stojí (změřeno na 40 uložených bězích z cache):
  pravidlo pojmenovalo **čtyři** běhy, všechny `security-review` s nulou nálezů z „levné“ éry, a
  u `db-extractor-adapter#39` našel `code-review` na tomtéž commitu **dva nálezy** — doložené
  falešné čisto. **Cena se do rozhodnutí nebere** a je to změřené, ne opatrnost: běh za 0,12 $
  otevřel tři soubory a běh za 0,44 $ osmnáct, kdežto jeden z těch čtyř podezřelých stál 0,74 $.
  Jako brána by cena vyrobila falešné poplachy a žádnou pravdu navíc.

  **Oddělovač v předponě cesty je podmínka, ne kosmetika:** zadání pro revieweera (#120) leží jako
  `<strom>.md`, tedy soubor **vedle** pracovní kopie se stejnou předponou, a přečte si ho i ten běh,
  který se do kódu vůbec nepodíval (má ho každý ze čtyř doložených).
- **Nálezy se berou ze všech běhů, i ze spadlých a vytimeoutovaných.** Selhal *běh*, ne
  nález — ten dorazil jako celý `ReportFindings` call. Filtrovat je podle stavu běhu by
  znamenalo, že spadlý reviewer s nahlášenou ztrátou dat vedle jednoho čistého běhu vyjde
  jako `approve`. Blokovat tedy umí i běh, který sám o sobě `approve` nedá.
- **Chip `nejisté` je vlastní stav.** Běh, který doběhl, ale nezavolal `ReportFindings`,
  ztratil se mu nález nebo **neotevřel žádný soubor z pracovní kopie** (#383), není ani čistý,
  ani spadlý — a ukázat u něj „čisté“ znamená schválený PR s neohlášenou chybou. Text v nápovědě
  se u chipu liší od věty v tabu nálezů schválně: visí za pomlčkou v hlavičce nápovědy, takže je
  kratší a s malým písmenem; **rozhodnutí ale sdílí** (`inconclusiveReason(of:)`).
- **Běžící reviewer přebíjí starší výsledek**, protože to, co je na obrazovce, se právě
  přepisuje.
- **Ztracený nález se hlásí i u chipu, který nálezy má** (`warning`). Stav zůstane
  `findings`, aby byl vidět počet; bez varování vypadá neúplný výsledek jako úplný a
  `suggestedVerdict` pak mlčí bez vysvětlení.
- **Shoda se počítá po reviewerech, ne po nálezech.** Jeden reviewer, který na jednom řádku
  najde dvě různé věci, si nepřikyvuje.
- **Odmítnuté nálezy (#113) se vyhodnocují nad záznamem, `isBlocking` se nemění.** Blokující
  je vlastnost nálezu a kategorie; „tomuhle nevěřím“ je můj názor nad celým záznamem. Filtruje
  proto jedno `activeFindings`, přes které jde `suggestedVerdict` **i** `reviewState` — dvě
  kopie by znamenaly, že řádek seznamu a panel řeknou o tomtéž PR dvě různé věci.
- **Ztracený nález se odmítnutím neschová.** `droppedFindings > 0` dál dává `nil`, ať je
  odmítnuto cokoli: odmítnutí mluví o nálezu, který znám, ne o tom, který se nepřečetl.
- **Odmítnutí jednoho revieweera neodmítá druhého**, a odznak `2×` proto počítá jen platné —
  když z dvojice zbyde jeden, zmizí, protože shoda dvou reviewerů, ze kterých jednomu nevěřím,
  není shoda. Tatáž lekce jako u odznaku „už je v draftu“ (#66). Skupina si nese **svoje**
  odmítnutí (filtrovanou mapu), aby se hodnota v `DiffRow` neměnila kvůli jinému souboru.
- **`Policy.sorted` řadí odmítnuté naspod**, a je to **první** kritérium: i odmítnutý blokující
  nález má ustoupit platnému stylistickému. Poslední zůstává `summary`, ať je pořadí úplné.
- **Řadí se podle vlastnosti kategorie, ne nálezu.** Kdyby první kritérium bylo
  `isBlocking`, rozpadla by se kategorie s `CONFIRMED` i `PLAUSIBLE` na dvě sekce se
  stejným názvem. Poslední kritérium je `summary`, aby bylo pořadí úplné a nepřeskakovalo
  mezi překresleními.

Nad událostmi časové osy v přehledu (#171) platí:

- **Události se prokládají s komentáři a review, ne aby stály zvlášť.** `Přehled` odpovídá na
  „co se od minula stalo“ a push mezi dvěma komentáři je půlka té odpovědi. Proto je to case
  `ConversationEntry`, ne druhý seznam vedle — řazení, identita i prázdný stav jsou pak jedno
  místo. Identita nese prefix `e`, ze stejného důvodu jako u review a komentáře: `id` z GitHubu
  se mezi typy může potkat.
- **Zavření se zahazuje, když je na PR i merge.** Mergnutím se pull request zavírá, takže
  GitHub kreslí jeden řádek — dva („mergnul“ a pár sekund po něm „zavřel“) by tvrdily, že se
  staly dvě různé věci. Zavření **bez** mergnutí zůstává: to je rozhodnutí PR nevzít.
- **Do odznaku u záložky `Přehled` se události nepočítají** (`ConversationEntry.isReadable`).
  Odznak říká, **kolik je toho k přečtení**, a commit ani „vyžádal review“ text k přečtení není
  — na PR s dvaceti commity by ukazoval třicet a přestal by o diskuzi něco říkat. Chyceno
  vlastní revizí diffu, ne až v provozu: `overview` počítalo všechno.
- **Nic dalšího se nefiltruje, a je to vědomé.** Několik párů „vyžádal review / odebral“ za
  sebou je šum, který v provozu vzniká (`bin/copilot-review.sh`), ale je to **pravda o tom
  PR**. Slévat je znamená rozhodovat, co je „tatáž“ událost — a to je rozhodnutí, které se
  posoudí líp nad běžící aplikací než dopředu.
- **Událost je jednořádková, ne karta.** Karta patří textu, který si člověk čte; „vyžádal
  review“ je pět slov a ve stejném rámečku jako odstavec prózy by mezi komentáři vypadala
  důležitěji, než je. Tímhle se `Přehled` čte jako časová osa na GitHubu: ikona, kdo, co, kdy.
- **U commitu je hlavní text jeho titulek**, ne věta „X pushnul commit“: kdo pushnul, říká
  avatar a ikona, kdežto titulek je to jediné, co o commitu něco vypovídá. Sází se monospace,
  protože je to zpráva commitu — a rozhoduje o tom `TimelineEventRow.isTitleCode`, ne view,
  aby ve view nestál `switch` nad druhem události.
- **Barvu má jen merge a zavření.** Kde svítí všechno, nesvítí nic; jsou to jediné dvě
  události, po kterých se s PR nedá dál pracovat.
- **Texty se skládají mimo view** (`TimelineEventRow`), jako u `FindingRow` a `ReleaseRow` —
  datum si formátuje view, takže na locale nezávisí nic, co se testuje. Každý druh musí mít
  neprázdný symbol i větu: řádek beze symbolu vypadá jako rozbité vykreslení a řádek bez textu
  jako prázdno.
- **Aktér bez jména je „někdo“.** Smazaný účet aktéra nevrátí a věta bez podmětu by u části
  druhů vyšla jako „zavřel PR“ bez toho kdo. Nastává to zřídka a je to levnější než dvě znění
  každé věty.
- **Avatary jdou přes `HTTPGetting`, ne přes `AsyncImage`.** Ten by si otevřel vlastní
  `URLSession` mimo jedinou cestu, kterou aplikace na síť chodí sama za sebe — nedal by se
  nahradit v testech ani spočítat mezi tím, co aplikace dělá. **Bez autentizace**: avatary jsou
  veřejné (změřeno — HTTP 200 bez tokenu, 991 B na 40×40) a `HTTPGetting` ani nemá čím token
  poslat, takže tvrdá podmínka č. 4 zůstává.
- **Značka „už jsem o obrázek žádal“ se zapisuje před prvním `await`.** Dva řádky se stejným
  autorem se vykreslí naráz, takže mezi kontrolou a zápisem nesmí být mezera — tatáž lekce jako
  u dvojkliku na odeslání odpovědi (#73), a testuje se souběžně, protože sekvenční test by
  prošel i bez té ochrany. Táž značka drží i to, že se **selhání v témže běhu nezkouší znovu**:
  řádky jsou v líném seznamu, takže by odscrollování znamenalo další dotaz na obrázek, který
  posledně nedorazil.
- **Zrušené stahování značku uvolní, selhané ne.** Řádky jsou v líném seznamu, takže se `.task`
  ruší při odscrollování uprostřed stahování — kdyby po sobě zrušení nechalo značku, ten avatar
  by se v celém běhu **nikdy** nenačetl, i když nic neselhalo. Je to tatáž zásada jako
  u `HealthMonitoru` („zrušení není zjištění“) a chytila to vlastní revize diffu, ne provoz.
- **Cache se neuklízí a je to v pořádku.** Je omezená počtem lidí, se kterými člověk reviewuje,
  a jeden obrázek je kilobajt; zaniká se oknem, protože `AvatarLoader` je `@State` na `RootView`.
- **Chybějící avatar kreslí iniciálu, ne prázdno ani spinner.** Prázdné místo by se od
  chybějícího řádku nepoznalo a kolečko s kolečkem uvnitř je u šestnácti pixelů nepokoj za nic.
  `AvatarLoader` je přitom **nepovinná závislost** z prostředí, jako `HealthMonitor` ve
  `StatusBarView`: bez něj (náhledy, offscreen render) zůstane iniciála.
- **Avatary jsou zatím jen u událostí**, ne na kartách komentářů a review. Tam by se musela
  rozšířit i ta část dotazu — je to samostatná změna, ne opomenutí.

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
- **Návrh z nálezů verdikt zastoupí, takže `noVerdict` odpadá** (#114) — a ptá se na to
  `effectiveVerdict(of:suggestion:)`, tedy tou samou funkcí, ze které kreslí panel. Dvě odpovědi
  na „platí nějaký verdikt?“ by se rozešly a okno by zakázalo tlačítko nad hodnotou, kterou má
  předvyplněnou. **Pořadí ostatních důvodů se nemění**, takže prázdný komentář, zastarání ani
  brána návrh nepřeskočí. Zbývá tedy na PR, kde review neproběhlo, spadlo, ztratilo nález nebo
  je jeho záznam zastaralý — tam se vybírá ručně.
- **Návrh sám rozdělané review nezakládá.** Neexistující i prázdný draft dá dál `nothingToSend`,
  protože se návrh neukládá a „draft existuje“ musí znamenat „je co poslat“. Návrh proto zastupuje
  **jen** chybějící verdikt draftu, který už nějaký obsah má — u čistého PR bez poznámek zůstává
  jedno kliknutí, kterým se návrh přijme za svůj, a panel to říká větou.
- **Návrh se do `sendBlock` předává s výchozím `nil`.** Default tam smí být, protože jeho
  zapomenutí odeslání **zablokuje**, ne otevře — u `scope` je to obráceně a proto tam žádný není.
- **`⌘⏎` otevírá potvrzení, ne odesílá** (#151). Zkratka volá **tutéž akci jako tlačítko v panelu**
  (`DraftActions.send`), tedy tu, která jen složí snímek a otevře sheet; druhé kliknutí uvnitř
  sheetu zůstává jediným místem, kde se volá `ReviewPublishing.submit`, a **žádnou zkratku nemá**.
  Dvě kliknutí na dvou různých tlačítkách (#68) tím platí dál. Kdy zkratka nedělá nic, rozhoduje
  `Policy.canOpenSubmission` — týž výraz, jakým se zakazuje to tlačítko — a navíc je zhasnutá nad
  už otevřeným sheetem: druhé stisknutí by složilo nový snímek a zahodilo stav rozdělaného
  odesílání, tedy i hlášku, kvůli které je okno otevřené.

  Ověřeno na běžící aplikaci: nad draftem v nepovoleném repu `⌘⏎` neudělá nic; po povolení otevře
  potvrzení s celým payloadem a **na PR nepřibylo review** (`gh api …/reviews` má 7 před i po).

### Labely a reviewery v panelu (#392)

Čtyři čisté funkce a každá odpovídá na jednu otázku, kterou by jinak view rozhodovalo samo:

- **`Policy.reviewers(requested:verdicts:)`** — kdo je v sekci a s jakou odpovědí. Tři pravidla:
  **vyžádání přebíjí starší verdikt** (po pushnutí opravy je `CHANGES_REQUESTED` odpověď na kód,
  který už tam není), **kdo jen komentoval a vyžádaný není, v sekci není** (`latestReviews` nese
  i review bez verdiktu a přijdou i od review bota — nakreslit je jako `čeká` by tvrdilo, že se na
  ně čeká) a **pořadí je podle odpovědi, ne podle toho, co přišlo první** (GitHub pořadí
  `latestReviews` nezaručuje, takže by se seznam přeskládal při každém načtení). Rozhoduje
  `SubmittedReview.isVerdict`, tedy tatáž funkce jako na ose konverzace.
- **`Policy.reviewers(requested:keeping:)`** — totéž po vyžádání, kdy GitHub odpovědi ostatních
  neposílá. Skládá se **tou samou funkcí**, jen se vstupem odjinud; druhé místo by se s prvním
  rozešlo zrovna v tom pravidle o přebíjení.
- **`Policy.labelChips(_:width:metrics:canAdd:)`** — zalomení do **nejvýš dvou řádků labelů**
  a `+N` na zbytek. Dvě pasti, obě změřené na zákresu (#390):

  1. **Ořez jménu musí nechat místo na `+N`.** Prostý „ořež na šířku řádku“ dá chip přes celý druhý
     řádek, `+N` spadne na třetí a řádky labelů jsou tři — tedy zrovna to, co má strop zakázat.
     Rezerva se počítá iterativně, protože šířka `+N` závisí na počtu, který se dozvíme až po
     zabalení; roste monotónně, takže se to po pár krocích zastaví.
  2. **Šířka chipu se počítá i s rámem a odsazením.** Mez uplatněná na obsah nechá chip přerůst;
     v zákresu z toho byl chip 230 bodů v řádku širokém 214. Měří to `LabelChipStyle`, tedy typ,
     který kreslí (pravidlo #236) — a hlídá to test, který srovnává **spočítanou šířku
     s nakreslenou**. Ostatní tvrzení to nechytí, protože si berou tutéž míru.

  `+ label` do stropu **nepočítá**: neustoupí nikdy, takže když na poslední řádek nevyjde, vezme si
  vlastní.
- **`Policy.metadataEditing(ownership:repo:scope:hasTool:)`** — tři stavy, ne boolean. Na cizím PR
  `.absent` (akce se nekreslí **vůbec**, ne zašedle: „tady se to dělá, jen teď ne“ by byla
  nepravda), bez povolené brány `.blocked` **s větou, na které skončí publisher** (to je stav, který
  se mění, takže zašedlá akce s důvodem je správná podoba), jinak `.allowed`.
- **`Policy.toggledLabels(_:on:known:)`** — nová sada po kliknutí, nebo `nil`. `nil` znamená
  **neposílat nic** a je to ta kontrola, která drží uzavřenost množiny i tehdy, kdyby ji nabídka
  ve view obešla. **Prázdná sada není `nil`**: sundání posledního štítku je platná akce. U reviewerů
  drží totéž `AppStore.requestReview(from:on:)`, které pustí **jen login z nabídky**
  (`reviewerCandidates`) — jediná kontrola ve view je kontrola, kterou příští obrazovka obejde.
- **Prázdný login se do sekce nedostane.** Autora review může GitHub vynechat (smazaný účet)
  a řádek bez jména se v panelu nedá odlišit od chyby kresby — a hlavně se nedá vyžádat.
- **`Policy.pickerRank(of:query:)`, `filteredPicker(_:query:text:)` a `pickerSelection(from:step:count:)`**
  — hledání v nabídkách `+ label` a `+ reviewer` (`App/Policy/PickerSearch.swift`). Vedle nich
  `pickerShowsSearch(count:canCreate:)` (odkdy je nad seznamem hledací pole) a od #434
  `pickerShowsKeyHints(rowCount:)` (jestli se pod ním kreslí patka s nápovědou kláves).

  **Pravidlo shody se dělí s paletou ⌘K** (#184): `searchRange` a `searchStartsWord` jsou tytéž
  funkce (kvůli tomu se z `CommandPaletteSearch` zvedly na `internal`) a dělení dotazu na slova taky
  (`paletteTokens`). Dvě jinak se chovající hledání v jednom okně je horší než sdílení — člověk si
  zvykne, že `nalez` najde `nález`, a je jedno, do kterého pole to píše.

  **Sdílí se pravidlo, ne `paletteResults`**, a je to rozhodnutí: paleta hledá nad
  `CommandPalette.Item` (titulek, podtitulek, klíčová slova, skupina, **akce**) a má strop **šest
  řádků na skupinu**. Nabídka reviewerů má třicet čtyři týmů a položku o jednom řetězci, takže
  prohnat ji paletou by znamenalo vyrobit položky s vymyšlenou skupinou a akcí, na kterou se nedá
  kliknout — víc kódu **a** dvě nová místa v paletě, která tam nemají co dělat.

  Tři věci, které se u toho nemají rozbít:

  - **Filtruje se podle toho, co je v řádku vidět** (`text:`). Kdyby filtr sedl na něco, co v řádku
    není, vypadal by výsledek jako chyba.
  - **Při shodné váze rozhoduje původní pořadí.** Swiftové `sorted` není stabilní, takže by dvě
    položky se stejnou váhou přeskakovaly mezi stisky klávesy — tatáž past jako v paletě.
  - **`searchStartsWord` je totální funkce.** Jako `private` funkce palety měla skrytou
    precondition (volající se na `startIndex` ptal dřív), a jako sdílená by na něm padala na
    `index(before:)`. Shoda na začátku textu **je** hranice slova, takže odpověď „ano“ je i věcně
    správná; ověřeno vloženou regresí — bez té stráže test run **spadne fatálem**, ne červeným
    tvrzením (nález Copilota).
  - **Kurzor ořezává, necyklí.** V nabídce, která se pod rukama filtruje, je přeskok z konce na
    začátek k nerozeznání od „šipka nic neudělala“; ořez se navíc uplatňuje i **bez pohybu**
    (`step: 0`), protože index z předchozího dotazu může být za koncem.
- **`Policy.newLabelOffer(query:known:isLoaded:editing:)`** — nabídne se z dotazu **založení nového
  labelu**, a jaký (#413, `App/Policy/NewLabelOffer.swift`). Vrací `PullRequestLabel?`, tedy hotový
  label i s barvou; `nil` znamená, že se akce **nekreslí vůbec**.

  Je to schválně **jedna** funkce s vyčerpávajícím výčtem důvodů, proč `nil`, protože zakládání
  nahrazuje tu ochranu, kterou byla uzavřená nabídka — a výčet rozesetý po `if`ech ve view se nedá
  otestovat. Pět důvodů: **nenačtená nabídka** (bez seznamu z repa není proti čemu hledat duplikát,
  takže by `Bug` prošlo vedle `bug` jen kvůli nedotažené odpovědi), **prázdné jméno**, **jméno, které
  už v repu je**, **cizí PR** a **vypnutá brána**. Prázdný **načtený** seznam je naopak odpověď: v repu
  bez labelů se dá založit cokoli.

  Dvě věci, které se u toho nemají rozbít:

  - **Shoda existujícího jména je celý řetězec, ne podřetězec** (`Policy.pickerSameName`), ale
    **pravidlo shody je tatáž `searchOptions`** jako u hledání. Z toho plyne obojí, co zákres chce:
    `Bug` nabídku nedostane (tentýž label), kdežto `bug-ui` v repu, který zná `bug-ui-legacy`, ji
    dostane — podřetězec není tentýž label, a kdyby o existenci rozhodoval, taková jména by nešla
    založit vůbec.
  - **Barva se počítá vlastním hashem, ne `hashValue`** (`Policy.labelColor(for:)` + `labelColors`).
    Swiftové hashování je zaseté náhodně **při každém spuštění procesu**, takže tentýž label by po
    restartu vyšel jinak a „podle jména“ by bylo „podle náhody“; FNV-1a je pár řádků a je stabilní.
    Paleta je šestnáct hexů, které GitHub nabízí ve svém dialogu nového labelu — bez bílé, protože
    puntík by na světlém podkladu splynul a obtažení `--line` je proti němu slabé. Hodnoty jsou
    v testu **literálem**: kdyby se počítaly tou samou funkcí, tvrdil by test jen „funkce se rovná
    sama sobě“.

  **Vzorník barev je zamítnutý**: v 300bodovém popoveru je to třetí prvek, který si říká o šířku,
  kvůli hodnotě, na kterou se člověk podívá jednou — a přebarvit label se chodí tam, kde se i maže.

  **`Policy.pickerShowsSearch` dostalo `canCreate`** (#413). U labelů je pole **vždycky**, protože
  jméno nového labelu se bere z dotazu: v repu se třemi labely by bez pole nešlo založit nic. Není to
  druhý prah, je to výjimka s důvodem viditelným z parametru; u reviewerů se pravidlo nemění, protože
  tam se nic nezakládá.
- **`Policy.findingsHeadNotice(tab:findingsHead:openCommit:hasFindings:)`** — proti kterému kódu
  nálezy platí. Je to **tvrdá podmínka č. 5 přepsaná do věty**: v `Commitech` může vedle nálezů stát
  jiný commit, než na kterém vznikly, takže nad seznamem je klidná věta a u rozkliknutého staršího
  commitu **výstraha** a ztlumené karty. Hlava se bere z **uloženého záznamu**, ne z detailu PR —
  hlava z detailu by mluvila o commitu, se kterým ty nálezy nemají nic společného. Text věty patří
  k tomu výčtu (`czechSentence`), aby se testoval tam, kde se rozhoduje, a ne odečítáním pixelů.

### Sekce `Větev` v panelu (#465)

Třetí sekce nad segmenty, pod labely a reviewery (návrh, sekce 36). Nese **stav** (kam se to slévá,
jestli je větev srovnaná, jak dopadly checky) a **akci, která z toho stavu plyne**; je to zároveň
základ pro `Srovnat s main` (#466), proto je to `stav + nabídka`, ne jedno tlačítko.

**Rozhoduje `Policy.branchSection`, ne view.** Řádek „srovnaná / za základem“ a zašednutí tlačítka
odpovídají na tutéž otázku, takže dvě skládání by uměla říct každé něco jiného — a u nevratné akce
je to ten nejdražší druh rozejití.

**Tři stavy nabídky, ne boolean** (`Policy.MergeOffer`), tatáž úvaha jako u `MetadataEditing`:

- **`absent` na cizím PR** — akce se nekreslí **vůbec**, ani nadpis sekce. Mergnout frontu někoho
  jiného se odsud nedělá nikdy, takže zašedlé tlačítko by tvrdilo „tady se to dělá, jen teď ne“.
- **`blocked([důvody])`** tam, kde se stav **mění**: vypnutá brána, červený check, větev pozadu,
  konflikt, chráněná větev, vlastní blokující nález, nenačtený stav. Důvody jsou **vyjmenované, ne
  jedna věta**, protože každý vede jinam — a jsou **v panelu**, ne jen v nápovědě pod kurzorem
  (zašedlé tlačítko bez věty je otázka, na kterou okno neodpoví; tatáž úvaha jako u #392).
- **`allowed`** jedině tehdy, když nesvítí žádný z nich.

Dvě rozhodnutí, která nejsou zjevná:

- **Spadlý check merge blokuje, i když by ho GitHub pustil.** `UNSTABLE` znamená „nepovinný check
  spadl“ a GitHub merge dovolí; aplikace je tady schválně **striktnější** — tatáž úvaha jako
  u odpovědi na zavřeném PR (#73). Zeleno je jediný stav, ve kterém se dá mergnout bez čtení.
  **Běžící check naopak nebrání**: mergnout rozběhnutou CI je legitimní rozhodnutí a povinný check
  zavře GitHub sám (`BLOCKED`).
- **`BLOCKED` se nepřekládá na „červený check“.** GitHub ho vrací i tehdy, když chybí schválení,
  a hlavně **i tomu, kdo do repozitáře nemá zápis** — změřeno na `cli/cli#14278`, kde vyšel
  u `MERGEABLE`. Věta proto jmenuje **všechny tři** možnosti; vybrat jednu by byla určitá nepravda.

**Počet commitů „o kolik je větev vzadu“ v #465 není**, ačkoli ho návrh kreslí. `mergeStateStatus`
ho nedává a `compare` API by za jedno číslo stáhlo celý seznam souborů. Přijde s #466, kde bude po
ruce klon v cache a spočítá se lokálně; do té doby stojí v řádku `za základem` bez čísla.

## `GitHubGateway` (`App/GitHub/`)

Jediná cesta aplikace k GitHubu, celá přes `gh`. Protokol `GitHubGateway` má **dvacet jedna** metod
a **schválně žádnou, kterou by šlo něco odeslat** — read-only je vidět z typu. (Do #330 tu stálo
„čtrnáct“, ačkoli výčet v tabulce měl patnáct položek; teď je s ním číslo srovnané. Tři přidala
#392: labely a reviewery PR a nabídky lidí a týmů k nim. Jednu #420: hlavy víc PR jedním dotazem.)

| Typ | Co dělá |
|---|---|
| `GitHubGateway` | Protokol (dvacet jedna metod): `checkAuth()`, `fetchViewer()`, `searchPullRequests(query:)`, `fetchDetail(id:)`, `fetchHeads(of:)`, `fetchChecks(id:)`, `fetchDiff(id:)`, `fetchDiff(repo:from:to:)`, `fetchDiff(repo:commit:)`, `fetchFile(id:path:)`, `fetchFile(repo:path:at:)`, `fetchConversation(id:)`, `fetchReleases()`, `fetchAnnotations(repo:checkRunID:)`, `fetchJobLogSize(repo:jobID:)`, `fetchJobLog(repo:jobID:)`, `fetchCommits(id:)`, `fetchMetadata(id:)`, `fetchRepositoryLabels(repo:)`, `fetchAssignableUsers(repo:)`, `fetchAssignableTeams(repo:)` |
| `GhGateway` | Implementace nad `gh`; `checkAuth()` deleguje na `GhAuthCheck` z `Environment` |
| `GitHubError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `GhResponseHeaders` | Rozbor hlaviček z `gh api -i` a `ContentLengthReading` — **čistá funkce** (#292) |
| `GhSearchQuery` | Rozdělení search dotazu na argumenty `gh` — čistá funkce |
| `ConversationQuery` | GraphQL dotaz na konverzaci a jeho argumenty — čisté funkce |
| `GhConversationResponse` | Tvar GraphQL odpovědi a mapování na `Conversation` |
| `GhSearchItem`, `GhPullRequestDetail` | Tvar JSONu z `gh` a převod na doménové modely |
| `GhUser` | Tvar odpovědi `gh api user` — jen `login` (#330). **Vlastní typ vedle `GhAuthor`**, i když má tentýž jeden field: je to jiná odpověď na jinou otázku a z podpisu volání má být poznat, čí login se dekóduje |
| `GhRelease` | Tvar jedné položky `GET /repos/…/releases` a převod na `Release` |
| `GhCommit` | Tvar jedné položky `GET /repos/…/pulls/{n}/commits` a převod na `PullRequestCommit` (#316). **Skoro všechno optional**: odpověď má přes šedesát polí a bereme šest, takže chybějící pole nesmí položit seznam kvůli něčemu, co se nekreslí |
| `PullRequestState(ghState:isDraft:)` | Mapování stavu — `gh` ho popisuje dvěma poli |
| `GhPullRequestMetadata`, `GhLabel`, `GhReviewRequest`, `GhLatestReview`, `GhTeam` | Tvar `gh pr view --json labels,reviewRequests,latestReviews` a převod na `PullRequestMetadata` (#392). `GhReviewRequest` rozlišuje člověka od týmu **podle toho, které pole má** (`login` proti `slug`), ne podle `__typename` — z chybějícího pole se to pozná stejně a nemusí se pamatovat jméno GraphQL typu |
| `AssignableUsersQuery`, `GhAssignableUsersResponse` | GraphQL dotaz na lidi, kteří na repo smí, a jeho odpověď (#392) |
| `PullRequestHeadsQuery` | GraphQL dokument na hlavy **víc PR naráz** a jeho argumenty — čisté funkce (#420). Aliasy jsou **pozice v dotazu** (`pr0`, `pr1`, …), protože ve jménech repozitářů jsou pomlčky a tečky, které v GraphQL jménu být nesmí |
| `GhPullRequestHeadsResponse` | Tvar té odpovědi a spárování se vstupním polem (#420). Aliasy nese **slovník**, ne pojmenovaná pole — kolik jich je, ví až volající |

Čtyři věci, které se u toho nemají rozbít:

- **Vyhledávání neumí SHA.** `gh search prs` nabízí jen `number, repository, title, author,
  url, updatedAt, state, isDraft`; `headRefOid` a `baseRefOid` jsou až v `gh pr view`.
  Proto search vrací `PullRequestSummary` a plný `PullRequest` vzniká teprve z detailu.
  Dotahovat detail rovnou v gateway pro každý nalezený PR by z jednoho pollu udělalo N+1
  podprocesů — **kdy se detail dotáhne, rozhoduje polling** (#6), typicky jen u PR se
  změněným `updatedAt`.

  **Samotnou hlavu ale jde vytáhnout dávkou** (#420, `fetchHeads(of:)`). To, co N+1 dělá z detailu,
  není hlava, ale **volání na PR** — a GraphQL bere víc aliasovaných kořenových polí v jednom
  dokumentu, takže se `headRefOid` (plus datum hlavy) pro celou frontu vejde do **jednoho** volání
  bez ohledu na počet repozitářů. Změřeno na živém API: 12 aliasů z 10 repozitářů **1 bod z 5000/h**,
  1,25–2,59 s, odpověď 1,9 kB; 24 aliasů **pořád 1 bod**, 1,25–1,96 s, 4,9 kB. Nesmí se z toho stát
  „tak se hlava tahá pořád“: na tik se ptá jedině `Policy.staleHeadProbe`, a to jen na to, co má
  uložené nálezy a pohnulo se.
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
- **Rozsah „co přibylo“ jde přes `compare`, ne přes klon v cache** (#284).
  `gh api repos/{o}/{r}/compare/<viděná>...<dnešní>` s hlavičkou `Accept: application/vnd.github.diff`
  — jedno volání, změřeno ~0,7 s. Klon v cache byl druhá schůdná cesta a **prohrál na měření**:
  `refs/prism/pr/<n>` v něm vzniká teprve při checkoutu kvůli review a `forgetPullRequest` ho maže,
  takže u většiny PR by se tlačítko nenabídlo; klon je navíc `--filter=blob:none`, takže by si
  `git diff` obsah stejně dotáhl ze sítě — jen oklikou přes cestu, která se lazy fetchi schválně
  brání (`GIT_NO_LAZY_FETCH`), a u PR z forku by v něm hlava nebyla vůbec (`prepare` tahá jen
  `refs/heads/*`).

  **Trojtečka schválně** — dvojtečkový rozsah `compare` nezná a vrací 404 (změřeno). Trojtečka
  začíná na společném předku obou hlav, takže proti hlavě, která je potomkem té viděné, dá přesně
  to, co se pushnulo; po přepsané historii by dala **víc než celý diff PR**, a proto se
  `Ukázat, co přibylo` v takovém případě nenabízí (`Policy.incrementalDiff`). Změřeno na
  `cli/cli#14062`: 102 kB ve 22 souborech proti 15 kB ve třech, které má celý PR. Osiřelá stará
  hlava přitom **problém není** — `compare` ji po force pushi zná (změřeno na témže PR).
- **Seznam commitů se stránkuje, i když se to skoro nikdy neprojeví** (#316).
  `gh api repos/…/pulls/<n>/commits?per_page=100 --paginate`: bez `per_page` by přišlo **prvních
  třicet** (výchozí stránka GitHubu) a odznak by nad stovkou commitů tvrdil třicet, tedy text
  přes to, co data unesou. U běžného PR je to pořád **jedno** volání — změřeno 1,20 s pro sedm
  commitů — a stránky `gh` slévá do jednoho pole, takže se dekóduje `[GhCommit]` (ověřeno na živém
  API). Nad **250 commitů** GitHub nevydá nic, ať se stránkuje jak chce; že se na strop narazilo,
  se pozná z počtu a **řekne se to v tabu** (`Policy.commitsHeadline`).

  **Neřadí se tady, a nikde jinde ani podle data.** GitHub vrací commity topologicky od nejstaršího
  a přerovnat je podle času by po rebase nebo cherry-picku ten postup rozházelo. Pořadí, ve kterém
  se kreslí, je rozhodnutí, ne tvar odpovědi: gateway vydá, co přišlo, a `Policy.commitsNewestFirst`
  to na jednom místě **otočí** (nejnovější nahoře) — topologické pořadí se tím zachová, jen se čte
  z druhé strany. Zahazují se jen položky **bez sha**, ze kterých se řádek udělat nedá.
- **Diff jednoho commitu jde na `commits/<sha>`, ne na `compare`** (#317).
  `gh api repos/{o}/{r}/commits/<sha>` s touž hlavičkou `Accept: application/vnd.github.diff` —
  změřeno 0,70–1,78 s na `keboola/job-queue#727`. Vypadá to jako totéž co rozsah o odstavec výš
  a **schválně to jedna metoda není**: `compare/<a>...<b>` počítá od společného předka, kdežto
  `commits/<sha>` je diff **proti prvnímu rodiči**, takže `<sha>^...<sha>` by u sloučení ukázalo
  i přisloučenou větev. Sdílené je jen složení příkazu (`GhGateway.diffText(at:)`).

  **Prázdná odpověď je platný výsledek.** Změřeno na témž PR: tři commity z
  `git commit --allow-empty` (přetočení CI) vrátily **nula bajtů** s nulovým návratovým kódem,
  kdežto tři sloučení vrátila 842 B, 514 kB a 760 kB. Prázdno je tedy stav odpovědi, ne vlastnost
  sloučení — vysvětluje ho `Policy.commitDiffTab`, ne prázdná plocha.
- **Obsah souboru se čte přes ref pull requestu**, ne přes `headSha`:
  `gh api repos/…/contents/<cesta>?ref=refs/pull/<n>/head` s hlavičkou
  `Accept: application/vnd.github.raw`. Ověřeno na živém API — ten ref má každý PR včetně
  forků, takže odpadá `gh pr view` jen kvůli SHA. Cesta se procentuje, jinak ji mezera
  v názvu rozbije.

  **Od #317 je vedle toho `fetchFile(repo:path:at:)`**, který čte soubor v konkrétním commitu
  (`?ref=<sha>`) — kvůli rozbalování kontextu v diffu commitu. **Ref není parametr jedné metody**,
  a je to rozhodnutí: „soubor na hlavě PR“ a „soubor v tomhle commitu“ mají jinou záruku (první se
  posune s každým pushnutím, druhý je zmrazený) a `ref: String` by dal syntaxi gitových referencí
  do `AppStore`. Sdílené je zase jen složení příkazu (`GhGateway.fileText(repo:path:ref:)`).
- **Tvar `gh` JSONu se nesmí propsat do modelů.** `PullRequest` a `PullRequestSummary` se
  kódují na disk, takže jejich `Codable` popisuje uložený tvar. Dekódují se proto DTO
  a teprve ta se mapují — jinak by změna `gh` měnila formát dat v `ReviewStore`.
- **Hlavičky z `gh api -i` rozebírá `GhResponseHeaders`** (#292), a je to vlastní typ schválně:
  tvar toho výstupu má tři vlastnosti, na kterých se rozbor rozbije **potichu**.
  1. **Řádky hlaviček končí `CRLF`**, jen stavový řádek `LF` (ověřeno `od -c`, fixture
     `gh/job-log-head.txt`). A `"\r\n"` je ve Swiftu **jeden `Character`**, takže
     `split(separator: "\n")` na něm nerozdělí — z celého bloku zbyde jeden „řádek“. Přesně tohle
     stálo #292: `Content-Length` nevyšel u žádného checku, přitom v shellu byl vidět, protože tam
     ho čtou oči, a ne Swift. Dělí se proto na `Character.isNewline`.
  2. **Jména hlaviček nemají zaručenou velikost písmen** — `HTTP/1.1` je nese Title-Case, `HTTP/2`
     lowercase. Citlivé porovnání by selhalo jen na části odpovědí, což se hledá horší než selhání
     vždycky. Jméno se proto normalizuje na malá písmena už při rozboru.
  3. **Bloků hlaviček může být víc za sebou** (`-i` u redirectu vypíše i odpověď před ním, a ta má
     `Content-Length: 0`). Rozhoduje **poslední blok**, ne první nalezená hlavička — jinak by každý
     log vyšel jako prázdný. Hlavička z bloku před redirectem se nepoužije vůbec: popisuje redirect,
     ne tělo.

  Velikost vrací `ContentLengthReading` s **vyjmenovanými** stavy (`bytes`, `noOutput`,
  `httpFailure`, `missingHeader`, `unreadableValue`), ne `Int?`. Čtyři různá „nevyšlo to“ sloučená
  do jednoho `nil` se nedají ani odlišit, ani přišpendlit testem — a v okně z nich zbyla jediná věta
  („Výstupu gh nerozumím“), se kterou se nedalo nic udělat.
- **`malformedOutput` nese fázi**, ne jen chybu dekodéru (#292). `Výstupu gh nerozumím.
  keyNotFound…` neříká, co se zkoušelo, takže z hlášky nejde poznat ani to, která obrazovka je
  poloprázdná; fáze (`Vyhledávání pull requestů`, `Anotace check-runu`, …) je jediné, co k tomu
  volající ví a chyba sama ne.
- **Login se bere z `gh api user`, ne z `gh auth status`** (#330), a **dekóduje se JSON, ne
  `--jq .login`**. Obojí je rozhodnutí proti levnější cestě:

  `auth status` se volá už dneska (`GhAuthCheck`), takže by login byl zadarmo — je to ale výstup
  **pro člověka** (`Logged in to github.com account ondrajodas`), ne kontrakt. Až se ta věta v nějaké
  verzi `gh` přeformuluje, přestane fungovat **rozřazení seznamu**, ne kontrola přihlášení; poznalo
  by se to tím, že vlastní PR zmizí z vlastní sekce. Změřeno na tomhle stroji: `gh api user` 0,55 s
  proti 0,42 s u `auth status`, a platí se to **jednou za spuštění** (`AppStore.loadViewer()`), takže
  cena nerozhoduje. `GhAuthState` se kvůli tomu **nerozšiřuje** — odpovídá na „jsem přihlášený“
  a druhá hodnota v něm by znamenala, že se týž údaj bere ze dvou míst.

  `--jq .login` by ušetřilo `GhUser`, jenže `--jq` na pole, které v odpovědi není, vypíše **prázdný
  řádek s nulovým návratovým kódem** — tedy prázdný login, a to je zrovna ta hodnota, která
  v aplikaci znamená „nevím, kdo jsem“ (`Policy.ownership` pak vrací všechno cizí). Takhle to skončí
  `malformedOutput` s fází `Přihlášený účet`. Prázdný ani bílý login se **nevrací** ani tehdy, když
  ho tak API pošle: je to poslední místo, kde se „nevím“ dá od loginu rozlišit.

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
- **A od #158 `diffHunk`, tímtéž dotazem — ne druhým až při rozbalení vlákna.** Odpověď z toho
  naroste ze 35 kB na 245 kB (změřeno na `cli/cli#13084`), ale **cena v bodech zůstává 1**
  a konverzace se nepersistuje, takže je to JSON, který se dekóduje a zahodí s PR. Druhý dotaz
  by byl druhá cesta ke konverzaci — vlastní stav načítání a vlastní chyba u každého vlákna,
  a latence zrovna v okamžiku kliknutí.
- **`diffHunk` se bere u komentáře, i když patří vláknu.** GraphQL ho na `PullRequestReviewThread`
  nemá; model ho proto zvedne z prvního komentáře, **který ho má** (ne z prvního — kdyby ho GitHub
  u některého vynechal, vlákno by o kontext přišlo kvůli pořadí). Zeptat se místo toho aliasem
  `comments(first: 1)` jen na jeden komentář navíc se **zamítlo měřením**: na tomtéž PR to
  neušetřilo nic (246 kB proti 245 kB, každé vlákno tam má jeden komentář) a **zvedlo cenu
  z 1 bodu na 2**, protože je to další connection.
- **A od #171 `timelineItems`, taky tímtéž dotazem.** Cena zůstává **1 bod** i s ním (změřeno
  na sloučeném dotazu) a odpověď naroste o 8,4 kB — na `cli/cli#13084` ze 245 na 254 kB, tedy
  o tři a půl procenta. Za druhý dotaz by nebylo co koupit.
- **`itemTypes` se vyjmenovávají a `PULL_REQUEST_REVIEW` ani `ISSUE_COMMENT` mezi nimi nejsou.**
  Přehled je má z `reviews` a `comments`, takže by z časové osy vyšly podruhé. Je na to test,
  protože z odpovědi samotné by se to poznalo až jako dvakrát vykreslený komentář.
- **Ke každému typu patří inline fragment.** Typ uvedený bez něj dorazí jako
  `{"__typename": "…"}` a nic víc (změřeno), tedy jako uzel, ze kterého se nedá nakreslit řádek.
- **`id` se bere jedním fragmentem `... on Node { id }`** místo deseti polí u deseti typů.
  Ověřeno, že ho mají všechny (29 z 29 uzlů) a jsou unikátní.
- **Aktér a vyžádaný reviewer jdou přes pojmenované fragmenty** (`actorFields`,
  `reviewerFields`), ne osmkrát opsané `actor { … }`. `reviewerFields` musí pokrýt `User`,
  `Bot`, `Mannequin` **i** `Team`: bot vyžádá review stejně jako člověk a bez jeho fragmentu
  z něj přijde jen `__typename`.

### Labely a vyžádaní reviewery (#392)

Tři **čtecí** metody; tvrdá podmínka č. 1 platí dál — gateway pořád nemá nic, čím by šlo něco
odeslat, a měnit label umí jedině `ReviewPublisher`.

- **`fetchMetadata(id:)` je vlastní volání, ne pole navíc v `fetchDetail`.** Detail si tahá
  i pre-flight publisheru před **každým** odesláním, a odpověď reviewera se skládá
  z `latestReviews`, tedy z pole, které nese celá **těla** review (změřeno na `cli/cli`: 1,5 kB za
  jedno review od bota). Platit tu velikost při každém odeslání za údaj, který odesílání nezajímá,
  nemá důvod.
- **Sekci reviewerů skládá `Policy`, ne DTO.** GitHub dává dvě různá pole — `reviewRequests`
  („komu to leží na stole teď“) a `latestReviews` („kdo se vyjádřil“) — a jejich slití do tří
  hodnot je rozhodnutí, ne tvar odpovědi. DTO jen převede tvar.
- **Týmy jdou do vlastního pole, ne mezi lidi** (`PullRequestMetadata.teams`). Do #392 se zahazovaly
  a byla to **tichá ztráta**: GitHub drží vyžádané reviewery ve **dvou** polích, takže u PR
  s týmovou žádostí byla sekce prázdná, i když review někdo vyžádal — změřeno na
  `keboola/platform-architecture-and-concepts#278` (`requested_reviewers: []`,
  `requested_teams: ["ajda-swimlane"]`), a v jedné frontě to byly **čtyři PR ze čtrnácti**. Fronta
  o ně nepřicházela (`review-requested:@me` týmové žádosti expanduje), chyběly jen ve výpisu.
- **Slug týmu se sjednocuje na podobu bez organizace** (`Policy.requestedTeams`): `gh pr view` dává
  `keboola/ajda-swimlane`, REST i `orgs/{org}/teams` `ajda-swimlane` — a tu druhou chce zápis. Dělí
  se s `omittingEmptySubsequences: false`, protože s výchozím `true` by z `keboola/` vyšlo
  `keboola`, tedy **jméno organizace vydávané za slug týmu** (chytil to test).
- **`fetchAssignableTeams` jde přes `orgs/{org}/teams`, ne `repos/{o}/{r}/teams`** — repozitářová
  varianta vrátila **404** i na repu, kam se dá číst i psát PR (chce admin práva). Organizační
  seznam prošel: 34 týmů, 0,63 s. **404 u účtu bez organizace je odpověď, ne porucha** — osobní repo
  týmy nemá, takže se vrací prázdno; ostatní chyby propadnou dál.
- **`fetchAssignableUsers` jde přes GraphQL, ne `GET /repos/{o}/{r}/collaborators`.** Seznam
  spolupracovníků chce **push právo**, takže by na repu, kam se dá jen číst, skončil 403 —
  a `assignableUsers` je navíc přesně ta množina, ze které GitHub sám dovolí review vyžádat, takže
  nabídka nemůže obsahovat volbu, kterou pak zápis odmítne.
- **`fetchRepositoryLabels` je uzavřená množina, na které stojí celé rozhodnutí, že `+ label` není
  volný text.** Z volného textu se dá omylem vyrobit nový label a ten už z repozitáře sám nezmizí.

  **Od #413 je uzavřený `seznam`, ne nabídka** — a ta množina je pořád k něčemu: je to to jediné,
  proti čemu se pozná duplikát, takže bez ní se **nezakládá** (`Policy.newLabelOffer` chce
  `isLoaded`). Řádky nesou dál jen labely repozitáře a `↵` na vybraném pořád jen přepíná; zakládání
  má **vlastní plochu pod děličem** a vlastní klávesu.
- **Prázdná odpověď je platný výsledek, ne porucha**: PR bez labelů i bez vyžádaných reviewerů je
  běžný. „Nepodařilo se to zjistit“ drží volající zvlášť (`MetadataState`) — u téhle sekce se ty dva
  stavy nesmí slít, protože podle prvního se sekce nekreslí a podle druhého se **nesmí dát měnit
  sada, kterou aplikace nezná**.
- **Sloveso je v nadpisu nabídky, položky nesou jen jména.** Do proklikání ho měla každá položka
  (`Vyžádat review od …`), takže u čtrnácti řádků opakovala totéž a předpona ořezala to jediné, čím
  se od sebe liší. Pojmenované kliknutí se neztrácí, jen se říká jednou — a **pro čtečku obrazovky
  zůstává celá věta u položky** (`accessibilityLabel`), protože nadpis se k ní nepřečte.
- **Klávesnice funguje, protože nabídka není `Menu`.** Popover je vlastní view, takže se v něm dá
  mít pole i obsluha šipek: psaní filtruje, `↑↓` vybírají, `↵` potvrdí. `esc` se **neobsluhuje** —
  popover ho umí sám a vlastní obsluha by ho jen vzala tomu, kdo to zvládne líp. Klávesy se berou
  **na poli**, ne na kontejneru (fokus je v něm), a vracejí `.handled`, jinak si šipku vezme pole na
  posun kurzoru v textu.
- **Hledání se kreslí teprve nad seznamem, který má co filtrovat** — **nad šesti položkami, tedy
  od sedmi**. Nad třemi jmény je to šum a nad prázdnem pole, ve kterém se nedá nic najít. Práh drží
  `Policy.pickerShowsSearch(count:)`, **jeden pro obě nabídky**: do #392 měla každá vlastní
  `searchFrom = 6`, takže se mohly rozejít potichu a bylo by z toho vidět jen to, že jedna nabídka
  pole má a druhá ne. Zároveň je to jediné, co se o tom poli dá tvrdit **číslem** — jestli v něm je
  fokus, je stav skutečného okna.

  **U labelů je pole od #413 vždycky** (`canCreate: true`): jméno nového labelu se bere z dotazu,
  takže bez pole by v repu se třemi labely nešlo založit nic. U reviewerů se práh nemění.
- **Fokus je v poli hned po otevření, a dělá se `.task` s jedním `Task.yield()`.** Bez toho je
  nabídka „otevři, klikni a piš“, tedy o krok delší než ta, kterou nahradila. Přiřazení ve **stejném
  průchodu**, ve kterém pole vzniká, SwiftUI zahodí — změřeno u palety ⌘K (#184) accessibilitou na
  běžící aplikaci: `onAppear`, `task` bez yieldu i `defaultFocus($isFocused, true)` daly
  `AXFocused = false` **navždycky**, ne později. Rozhoduje **počet průchodů, ne čas**, takže tady
  není žádná pauza ani nic, co by si plánovalo další kolo (#350): jeden yield, jeden zápis.

  Do #392 tu stálo `onAppear` a nabídka se musela kliknout, i když komentář u ní tvrdil opak — z toho
  plyne, že tohle je vlastnost, kterou **nedokládá kód, ale proklikání**. Samostatná sonda mimo
  aplikaci `onAppear` nechá projít, takže na potvrzení nestačí; podrobnosti a tabulka variant jsou
  v [`testovani.md`](testovani.md).
- **Fokus nabídku nepřežije.** `@FocusState` sedí v `PickerSearchField`, tedy ve view, které
  s popoverem zaniká — po zavření tak není co držet a psaní nemá kam mizet (změřeno sondou: znak po
  zavření jde do okna a v poli se neobjeví). Pod sedmi položkami pole není vůbec, takže tam není co
  fokusovat.
- **Prázdný výsledek filtru je čtvrtý stav nabídky**, ne první: vedle něj existuje nenačteno,
  prázdné repo a porucha, a každý má vlastní větu. Prázdná plocha by vypadala jako spadlé načítání.
- **Klávesy jsou od #434 napsané v patce** (`.pkr-foot`, sekce 24) — `↑↓ vybírá`, `↵ přepne`
  (u reviewerů `vyžádá`), `esc zavře`. Do #434 nebyla ani u jedné nabídky, přitom se v nich od #392
  a #413 nasbíralo dost kláves, aby se nedaly uhodnout. Plochu drží `PickerFooter` a je to **jedno
  místo pro obě náplně té třídy**: nápovědu i patku potvrzení nového labelu. Dvě kopie odsazení by
  se rozešly potichu a jediné, co by z toho bylo vidět, je jinak vysoká patka v jedné z nabídek.

  **Nad prázdným výsledkem se nekreslí** (`Policy.pickerShowsKeyHints(rowCount:)`) a je to jak
  v zákresu, tak věcně jediná možnost: `pickerSelection` nad prázdnem vrátí `nil`, takže by dvě ze
  tří položek slibovaly klávesu, po které se nic nestane. Hlídá to tvrzení, že se ty dvě funkce
  shodnou.

  **`⌥↵` v patce schválně není** — zakládání má zkratku napsanou **u akce samotné** (`.nl-add .keys`)
  a návrh to tak kreslí i v tom stavu, kde ta akce je (sekce 26): patka i tam nese tři položky.
  V patce by to byla čtvrtá položka, která ve třech ze čtyř stavů nabídky neplatí.

  **Pro čtečku obrazovky je patka jedna věta a položkám nic nebere**: `accessibilityElement(children:
  .ignore)` plus vlastní popisek, protože `↑↓` je pro čtečku dvojice znaků. Celá věta u položky
  (#392) platí dál — patka je zkratka pro oko, ne náhrada popisku.

  **Rozměr je změřený, ne odhadnutý**: patka chce **194 b** (`přepne`), resp. **195 b** (`vyžádá`)
  z 300, které má `.pkr`. U nabídky reviewerů, která si šířku neurčuje rámcem, je od #434 **nejširší
  prvek** — přirozená šířka se posunula ze 145 (nadpis) na 195. Není to regrese: `.pkr` má v zákresu
  300, takže užší nabídka je odchylka na druhou stranu a 195 je jí blíž. Měří to
  `PickerKeyHintsTests`.
- **Dokud snímek nedorazil, je `+ label` zakázaný.** Sada se posílá celá, takže bez snímku nemá
  z čeho vzniknout — a tlačítko, po kterém se nic nestane, je horší než zakázané. Vysvětlení u něj
  mluví o načítání, ne o bráně; jsou to dva různé důvody.
- **Totéž platí o nabídkách, a jsou to tři stavy, ne dva**: nenačteno, načteno prázdné („repo žádné
  labely nezná“) a porucha. Drží to `repositoryLabels` proti `repositoryLabelFailures` (a totéž
  u lidí), takže se nabídka po výpadku sítě netváří jako repo bez labelů. Seznam se u poruchy
  **nezapíše**, takže se další otevření nabídky ptá znovu — to je zároveň to „zkusit znovu“.

Co k nabídce labelů přidalo **zakládání nového** (#413):

- **Akce je pod děličem, ne řádek v seznamu.** Jako řádek by z ní byl nejpravděpodobnější omyl v celé
  obrazovce: přidržená šipka dolů na konci filtrovaného seznamu by mířila na nevratnou věc. Kreslí se
  **přerušovaně obtažená**, jako `+ label` a `čeká` u reviewera — přerušované je to, co se ještě
  nestalo — a jméno v ní je **doslova, v uvozovkách a `--ink`**, protože je to jediná hodnota na
  řádku, kterou má člověk zkontrolovat.
- **Jméno se v akci zalomí, neořeže** (změřeno na 39 znacích: dva řádky, nic za okrajem). Je to
  jediné místo před potvrzením, kde je jméno vidět celé, takže ořezat by znamenalo ořezat zrovna tu
  informaci, kvůli které ten krok existuje.
- **Zkratka je `⌥↵` a bere ji pole, ne okno.** `⌘↵` je v tomhle okně obsazená dvakrát (paleta ⌘K
  otevírá výsledek na GitHubu, detail PR potvrzení odeslání) a #184 už jednou popsalo, čím to končí:
  vyhraje ta, která se zaregistrovala později. `⌘N` patří `File > New Window` z `WindowGroup`.
  Obsluha je **jeden** `onKeyPress(keys: [.return])`, ne dva zápisy: `modifiers` je množina, ve které
  stisk **smí** ležet (výchozí `.all`), ne množina, která musí sednout přesně — dva zápisy by se
  přebíjely. Bez zakládání se `⌥↵` **propustí** (`.ignored`); spolknutá klávesa, po které se nic
  nestane, je k nerozeznání od zaseknuté nabídky.
- **Potvrzení je druhá obrazovka téhož popoveru, ne sheet.** Přepnutí existujícího labelu zůstává
  jedno kliknutí (#392 mu potvrzovací okno nedalo schválně) — potvrzuje se to, co vratné **není**,
  a modální okno kvůli jednomu slovu by z panelu udělalo klikačku. Jsou na ní **čtyři věci a každá
  odpovídá na jednu otázku**: chip s puntíkem a jménem (co se objeví), slug repozitáře (kam to jde),
  hex (jaká bude barva) a výstraha (co po tom zůstane).
- **Slug je pod chipem a v mono s pravým casingem**, ne v nadpisu: `PickerHeading` je
  `textCase(.uppercase)`, takže `ondrajodas/PRism` by se vysázelo `ONDRAJODAS/PRISM` — a velká
  písmena ve jméně repozitáře jsou data, ne dekorace.
- **Potvrzení nemá výchozí akci.** Poslední klik před něčím nevratným je klik, tak jako u potvrzení
  odeslání review (#68). V patce vedle tlačítek stojí `dvě volání` — je to jediné místo, kde je před
  kliknutím vidět, že pro tuhle akci neplatí tvrdá podmínka č. 5.
- **Nabídka má pevnou šířku 300 bodů** (`.pkr` z návrhu), ne `maxWidth`: obě obrazovky mají být
  stejně široké, jinak popover při přepnutí poskočí — a rezervy v zákresu jsou naměřené na 300.
  Nejdelší řádek potvrzení (barva s hexem) má 265 b z 278, které mezi okraji zbývají, takže se na
  odhad spoléhat nedá; měří to `NewLabelPickerWidthTests`.
- **Popover se po založení nezavírá.** Založený label se hned objeví v seznamu jako zaškrtnutý, takže
  zavřený popover by schoval zrovna tu odpověď na to, jak to dopadlo. Je to tatáž úvaha jako u
  přepínání (#392).
- **`query` a `confirming` jsou v `LabelPickerView` `@State` s parametrem v memberwise initu, a je to
  jen pro sondy.** Není to binding — sonda nemá klávesnici, takže druhou obrazovku jinak nevyfotí;
  v aplikaci se ani jedno nepředává.

### Slévatelnost větve je **líné pole** (#465)

`mergeable` i `mergeStateStatus` se u GitHubu počítají **až na vyžádání**: dotaz, který je nezastihne
hotové, dostane `UNKNOWN` (v RESTu `null`) a **sám ten výpočet spustí**. Kdo se zeptá jednou, dostane
zašedlé `Mergnout…` podle náhody, proto se `GhGateway.fetchBranchStatus` ptá opakovaně (tři pokusy,
vteřina mezi nimi).

**Co je z toho změřené a co ne**, aby se to příště nemuselo měřit znovu:

- Změřené: `UNKNOWN` je **trvalý stav mergnutého PR** (`PRism#470`, obě pole). Proto se
  `loadBranchStatus` na zavřeném a mergnutém PR neptá vůbec — vyčerpal by všechny pokusy včetně
  čekání mezi nimi, a `Policy.mergeOffer` tu odpověď stejně přebije stavem PR.
- Změřené: `UNKNOWN` se na malém repu **nepodařilo zastihnout**. Na `prism-review-sandbox#8` vyšlo
  `MERGEABLE`/`CLEAN` hned po založení PR i hned po každém ze tří pushů, přes GraphQL (`gh pr view`)
  i přes REST. Opakovaný dotaz je tedy pojistka proti **doloženému chování API**, ne proti stavu,
  který se povedlo vyrobit — a stojí nula, dokud odpověď chodí usazená.
- **Tři pokusy jsou volba, ne měření**: kolik jich GitHub potřebuje, se zvenku zjistit nedá. Dvě
  vteřiny čekání v nejhorším případě jsou pod hranicí, kdy by si člověk stihl všimnout, že panel na
  něco čeká.

**Ptá se jen na vlastním PR**, na rozdíl od labelů: na cizím se sekce nekreslí, takže by to bylo
volání za nic — a je to zrovna to volání, které si na straně GitHubu vyžádá výpočet. Čte se **jako
poslední** v řadě za detailem, checky, commity a labely, ze stejného důvodu jako ostatní: každé je
`gh` podproces a paralelní spouštění by jich na jeden výběr řádku zvedlo počet naráz běžících.

## `ReviewPublisher` (`App/Publish/`)

**Jediná cesta, kterou z aplikace něco odejde na GitHub.** Vznikl v #67 a nahradil tvrdou
podmínku „nikdy nic neposílat“ pravidlem, které je vidět z kódu — viz tvrdé podmínky výš.

| Typ | Co dělá |
|---|---|
| `ReviewPublishing` | Protokol se **sedmi** metodami: `submit(_:)`, `reply(to:body:)`, `setResolved(_:of:)`, `comment(on:body:)`, `setLabels(_:on:)`, `requestReviewers(_:teams:on:)`, `createLabel(_:for:)` |
| `GhReviewPublisher` | Implementace nad `gh`; pre-flight přes `GitHubGateway` |
| `PublishScope` | Brána: smí se z tohohle repa odeslat? Skládá se z `Configuration`, výchozí stav **vypnuto** |
| `PublishError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `PublishRequest` | Payload a argumenty review + `isSendable` (sdílená kontrola prázdného těla) — čisté funkce |
| `ThreadRequest` | GraphQL mutace pro vlákna a jejich argumenty — čisté funkce |
| `CommentRequest` | REST argumenty komentáře pod PR (#216) — čisté funkce |
| `MetadataRequest` | REST argumenty labelů a vyžádání reviewera (#392) + payload sady labelů a **nového labelu** (#413) — čisté funkce |
| `MetadataSubmission`, `MetadataActionState` | Čtvrtý volající publisheru a stav toho, co se právě odesílá (#392); od #413 i **zakládání labelu** a stav „založil se, nepřidal“ |
| `GhRequestedReviewersResponse` | Tvar odpovědi `POST /pulls/{n}/requested_reviewers` — čte se z ní **jen** `requested_reviewers` |
| `ThreadTarget`, `ThreadResolution` | Adresa vlákna (PR + `id`) a to, jak dopadlo přepnutí vyřešení |
| `ThreadActionState`, `ThreadKey` | Co se s vláknem právě děje a klíč, pod kterým to drží `AppStore` |
| `CommentActionState` | Co se právě děje s komentářem pod PR (#216) |
| `GhSubmittedReview`, `GhThreadReplyResponse`, `GhThreadResolutionResponse`, `GhIssueCommentResponse` | Tvary odpovědí — REST review, dvou GraphQL mutací a REST komentáře |
| `ReviewSubmission` | Jedno odeslání review od kliknutí po odpověď — **volající `submit(_:)`**. Od #69 začíná u zastaralého draftu kontrolou kotev (`.checking`) |
| `DraftAnchorCheck` | Jedna kotva ke kontrole při přenesení (#69) — komentář a jeho stav |
| `ThreadSubmission` | Jedna akce nad vláknem — **volající `reply` a `setResolved`** |
| `CommentSubmission` | Jeden komentář pod PR — **volající `comment(on:body:)`** (#216) |

Věci, které se u toho nemají rozbít:

- **Brána je první kontrola v cestě**, ještě před sítí. Na nepovolené repo se nemá ani ptát
  na detail — a `scope` je v `init` **bez výchozí hodnoty**, takže se publisher bez brány
  nedá složit.
- **Pre-flight ověřuje `headSha` a stav PR, a při neshodě se nevolá nic.** GitHub proti
  odeslání proti zastaralému commitu nechrání (změřeno u #62), takže je to naše práce.
  Draft PR se odeslat **smí** — je to otevřený stav a na GitHubu běžné.

  **Hlava je volitelný parametr** (`preflight(_:expecting:)`), protože každá cesta ven se váže
  na něco jiného: review na commit, odpověď do vlákna na vlákno, komentář pod PR na diskuzi.
  Jedna funkce s `nil` místo dvou podobných je tady schválně — dvě by se rozešly v tom, co
  dělají se stavem PR.
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

Nad `ReviewSubmission` platí od #69 ještě tohle:

- **Zastaralý draft okno otevře, ale neodešle.** Stav `.checking` znamená „nejdřív zkontroluj
  kotvy“; `canSend` je v něm `false`, takže se z UI nedá naběhnout na chybu, kterou by pre-flight
  publisheru vrátil (draft psaný proti jiné hlavě).
- **Kontrola je první stránka téhož okna, ne druhé okno.** Zkontrolovat kotvy se musí tak či tak,
  než review odejde — vlastní okno by byl mezikrok, ve kterém se kliká na totéž. Dvě kliknutí na
  dvě různá tlačítka (pravidlo z #68) zůstávají: to první je `Přenést na <sha>`.
- **Snímek draftu se smí přepsat jedině přenesením**, tedy výslovnou akcí člověka v tomtéž okně —
  „co je v potvrzení vidět, to se odešle“ platí dál. Nepovedené přenesení nechá okno **v kontrole**,
  protože tvářit se jako hotové by znamenalo odeslat proti starému commitu.
- **`.checking` se neodvozuje z prázdných kotev.** Zastaralý draft bez řádkových komentářů (jen
  tělo a verdikt) je zastaralý taky a přenesením se mu posune commit; odvozovat to z kotev by ho
  poslalo proti staré hlavě.

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
  Od #114 to platí jen pro **vědomé** přepnutí (`verdictOrigin == .chosen`): u předvyplněného
  návrhu by okno varovalo před hodnotou, kterou navrhla sama aplikace. Hodnotami by to vyšlo
  stejně, ale viselo by to na shodě, kterou nic nedrží.
- **Odesílaný verdikt může být návrh, a sheet to napíše** (#114). `verdictOrigin` nese, odkud
  hodnota je; bez toho by předvyplněný `APPROVE` v posledním okně před odesláním vypadal jako
  moje rozhodnutí. Výchozí `.chosen` v `init` odpovídá draftu, který si verdikt nese sám.
- **Přenesení na nový commit verdikt nezahodí.** `applyTransfer` vrací **uložený** draft, tedy
  ten bez předvyplněného návrhu, takže si ho `transfer` doplní zpátky. Bez toho by review po
  přenesení odešlo bez `event`u — tedy neodešlo vůbec.

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

Nad `CommentSubmission` (#216) platí:

- **REST, ne GraphQL — opačně než u vláken.** Tam rozhodlo, že mutace bere `id`, které v modelu
  už je; tady je to naopak: `addComment` chce `subjectId`, tedy node ID pull requestu, a to se
  netahá nikde — ani `PRIdentifier`, ani `PullRequest` ho nemá. Doplnit ho by znamenalo rozšířit
  dotaz, model i mapování kvůli jednomu volání, kdežto REST si vystačí s `repo` a číslem.
- **Endpoint je `issues`, ne `pulls`.** Komentář pod PR je z pohledu API issue comment: nepatří
  k řádku ani k review, takže pro něj v `/pulls/` nic není.
- **Tělo jde přes `-f`, ne `-F`.** `--field` čte hodnotu začínající `@` jako jméno souboru, takže
  komentář otevřený zmínkou (`@ondrajodas …`) by se `gh` pokusil načíst z disku. Regrese by byla
  tichá — prošlo by všechno kromě komentářů, které začínají zmínkou. Hlídá to vlastní test.
- **Prázdné tělo se nevolá** (`blankComment`), ze stejného důvodu jako u odpovědi: GitHub ho
  spolkne s nulovým exit kódem. Kontrola je sdílená (`PublishRequest.isSendable`) — dvě kopie
  téže otázky by se rozešly zrovna v tom, co považují za prázdné.
- **Vlastní chybový případ, ne `blankReply`.** Věta u odpovědi mluví o vlákně; hláška, která
  pojmenuje něco jiného, než na co se člověk dívá, vypadá jako chyba v jiné části okna.
- **`replyToID` zůstává `nil`.** Komentář pod PR není ve vlákně a `Conversation` ho drží ve
  vlastní stránce — s vyplněným `replyTo` by se v ose kreslil odsazený jako odpověď na něco,
  co neexistuje.

### Labely a vyžádání reviewera (#392) — pátá a šestá metoda

Vědomé rozšíření tvrdé podmínky č. 1, ne její obejití. **Proč**: u vlastního PR je štítek
a reviewer součástí toho, jak si člověk řídí svoji frontu, a je to poslední věc, kvůli které se od
hotového review přepíná do prohlížeče. Tentýž precedens jako #73 (odpověď do vlákna) a #216
(komentář pod PR). **Co v zákazu zůstává**: approve mimo review, merge, zavření PR a milník —
a `SingleWayOutTests` je hlídá jmenovitě, takže se sedmá metoda nedá přidat potichu.

Co na tom stojí:

- **Brána je tatáž** (`PublishScope`, `allowsPublishing` globálně i per repo). Druhý přepínač by
  byl druhé místo, kde se dá „samo nic neodejde“ porušit — a to je celý smysl toho, že je jedna.
- **Sada labelů se posílá celá, jedním `PUT /issues/{n}/labels`.** Endpoint sadu **nahrazuje**, ne
  doplňuje, takže dvě volání (přidat, sundat) by mezi sebou nechala stav s půlkou sady. Rozdíl
  skládá `Policy.toggledLabels`, ne publisher: dvě skládání téhož se rozejdou.
- **Payload jde souborem, ne přes `-f 'labels[]=…'`** — kvůli jediné hodnotě, která se jinak
  poslat nedá: **prázdné sadě**. Sundání posledního štítku je `{"labels": []}`, kdežto `gh api`
  bez jediného `-f` neposílá tělo vůbec. Jedna cesta pro obojí je lepší než dvě, z nichž se jedna
  použije jen při sundávání posledního štítku — tedy zrovna ta, kterou nikdo nezkouší.
- **`writePayload` bere hotová data, ne payload review.** Souborem se od #392 posílají dvě různé
  věci; dvě skoro shodné funkce na „napiš JSON s právy `0600` a ukliď ho“ by se rozešly zrovna
  v těch právech. Kódování zůstává **u volajícího a před tím voláním** — když selže, není co
  uklízet.
- **Endpoint labelů je `issues`, ne `pulls`**, ze stejného důvodu jako u komentáře: pull request je
  issue s diffem a pro labely v `/pulls/` není nic. Reviewer naopak `/pulls/` má, protože review na
  issue neexistuje.
- **Loginy jdou přes `-f`, ne `-F`.** `--field` hodnotu typuje, takže login z číslic by v payloadu
  skončil jako `123` místo `"123"`.
- **Vyžádat nikoho není akce** (`PublishError.noReviewer`): GitHub prázdné pole `reviewers` přijme
  a neudělá nic, takže by okno hlásilo vyžádané review, které nevzniklo. Tatáž past jako u prázdného
  komentáře, ale vlastní případ — věta „napiš text“ by u vyžádání nedávala smysl.
- **`headSha` se neověřuje**, stav PR ano. Štítek se váže na PR, ne na commit; kontrola hlavy by
  zakázala zrovna to, kvůli čemu se štítkuje.
- **Odebrat vyžádané review odsud nejde**, a to je rozhodnutí: request pošle člověku upozornění,
  které se odebráním **nedá vzít zpět**, takže odebrání není opravný krok, jen zametení. Proto na
  něj nevede `+`, ale pojmenované tlačítko se jménem toho člověka — a **u týmu je v něm slovo
  `týmu`**, protože upozornění odejde všem jeho členům.
- **Lidé a týmy jdou jedním voláním** (`reviewers` + `team_reviewers` v jednom payloadu). Druhá
  metoda by prodloužila výčet cest ven za nic a dvě žádosti by nechaly mezistav s půlkou vyžádaných.
  Vyžádat **nikoho** není akce ani tady: prázdné musí být obojí, jinak se volá.
- **Odpověď na vyžádání nenese odpovědi ostatních**, jen `requested_reviewers`. Slévá to
  `Policy.reviewers(requested:keeping:)`, tedy tatáž funkce jako při čtení — bez ní by z panelu po
  jednom kliknutí zmizelo schválení, které tam bylo, nebo by se muselo volat `fetchMetadata` znovu.

### Založení labelu (#413) — sedmá metoda, a první, která píše do repozitáře

Vědomá změna tvrdé podmínky č. 1 **a č. 5 naráz**, ne obejití ani jedné. **Proč**: nabídka labelů
byla do #413 uzavřená doopravdy, takže štítek, který v repozitáři ještě není, se musel založit
v prohlížeči — tedy tím odskokem, kvůli kterému #392 vzniklo. Precedens je tentýž jako u #73, #216
a #392: výčet cest ven se rozšířil, protože se ta věc dělá při review, a zapsal se důvod.

Co je na téhle metodě jiné než na těch šesti před ní:

- **Zapisuje do repozitáře, ne do PR**, takže omyl po sobě nechá **trvalý** následek: label vzniklý
  omylem z repozitáře sám nezmizí. Předchozích šest sahalo na PR nebo na diskuzi, tedy na věc vratnou
  jedním klikem nebo takovou, která se zavřením PR přestane týkat čehokoli dalšího.
- **`deleteLabel` se nepřidá.** Není to opomenutí, je to hranice: smazaný label zmizí ze **všech**
  issues a PR, na kterých leží, a aplikace tu ztrátu neumí ani ukázat. Nevratnost se proto vyvažuje
  **potvrzením**, ne opravnou akcí; mazat i přebarvovat se chodí na GitHub. `SingleWayOutTests` ho
  hlídají jmenovitě, vedle `merge`, `close`, approve mimo review a milníku.
- **Bere `PRIdentifier`, i když adresa volání je jen repozitář** — a je to pojistka, ne
  nekonzistence. Zakládá se **kvůli** tomu PR a hned za tím jde `setLabels`, takže na zavřeném PR by
  druhé volání neprošlo a v repozitáři by po tom zbyl label, který nikdo nechtěl. Pre-flight je proto
  stejně široký jako u labelů (scope a stav PR, ne `headSha`) a `pullRequest.repo` je zároveň ta
  adresa, ze které si metoda ověří bránu.
- **Bere `PullRequestLabel`, ne vlastní typ požadavku.** Druhý typ o dvou stejných polích by byl
  druhé místo, kde se dá barva složit jinak; takhle je to **jedna hodnota**, kterou nakreslí náhled
  v potvrzení a pošle publisher — náhled tedy nemůže lhát, protože je to tentýž label.
- **Barva se posílá vždycky.** Kdyby byla volitelná, přiřadil by ji GitHub sám a náhled by ukazoval
  barvu, která nevznikla. `description` se naopak neposílá — aplikace ho nemá kde nabrat a prázdný
  popis je totéž jako žádný.
- **Payload jde souborem**, jako sada labelů: jméno je text od člověka, takže projde JSONem
  s uvozovkami, zalomením i emoji stejně jako cokoli jiného — a kódování zůstává na jednom místě.
- **Prázdné jméno se nevolá** (`PublishError.blankLabelName`), tou samou sdílenou kontrolou
  (`PublishRequest.isSendable`) jako odpověď a komentář.
- **Duplikát má vlastní chybu** (`labelExists`), ne `unknown`: 422 `already_exists` je jediné selhání
  zakládání, po kterém **není co spravovat** — label existuje, takže stačí otevřít nabídku znovu.
  `Policy.newLabelOffer` na to nedosáhne, protože nabídka je snímek z chvíle otevření.

**Dvě volání a mezistav.** `POST /repos/{repo}/labels` a `PUT /issues/{n}/labels` se spojit nedají,
takže tvrdá podmínka č. 5 pro tuhle akci neplatí a existuje stav *label v repozitáři je, na PR není*.
Zamítnuté bylo **samotné `Založit`** bez přidání: atomické by bylo, ale v devíti z deseti případů by
po něm musel následovat klik na řádek v nabídce, tedy krok navíc za čistotu, kterou vidí jen
dokumentace. Výjimka se proto platí **viditelností** (`AppStore.createLabel(_:on:)`):

- **`MetadataActionState.createdNotAdded(name:error:)`, ne `failed`.** `failed` by tvrdilo, že se
  nestalo nic. Případ nese **jméno** (aby se dalo napsat, o který label jde) i **chybu** (aby se dalo
  napsat, proč druhé volání spadlo) — zákres kreslí jen tu první větu, ale je to jediné selhání
  v tomhle panelu, které by jinak neřeklo důvod, a další krok se od důvodu odvozuje.
- **Založený label se zapíše do nabídky ještě před druhým voláním** (`remember(_:in:)`).
  `loadRepositoryLabels` se podruhé neptá, takže bez toho zápisu by řádek v nabídce až do restartu
  nebyl — a věta „přidáš ho kliknutím“ by tvrdila víc, než data unesou. Zapisuje se **jen do už
  načtené** nabídky: z `nil` by tím vzniklo tvrzení „repo zná právě jeden label“.
- **Sada pro druhé volání se čte znovu**, ne z hodnoty před prvním voláním: mezi voláními se snímek
  mohl načíst znovu (nové `updatedAt` z pollingu), a sada se posílá celá, takže starší základ by
  sundal štítek, který mezitím někdo přidal. Skládá ji `Policy.toggledLabels`, ne tahle metoda.
- **Mezi voláními se nepustí nic dalšího** (`isBusy` u `.creatingLabel`), takže PR nemá jak dostat
  sadu, kterou první polovina ještě nedokončila.
- **Když spadne první volání, mezistav nevzniká**: je to obyčejné `failed` a v nabídce po tom
  nezůstane řádek, který neexistuje.

### Merge vlastního PR (#465) — osmá metoda, a první, která mění `main`

Vědomá změna tvrdé podmínky č. 1, a **největší, jaká v ní zatím byla**: do #465 stálo v `CLAUDE.md`
i v `SingleWayOutTests` jmenovitě, že `merge` sem nepatří. **Proč se to změnilo**: mergnout vlastní
PR, když je zeleno, je poslední věc, kvůli které se od hotového review odskakuje do prohlížeče — a je
to práce s **vlastní** frontou, tedy tatáž třída jako labely a reviewery z #392. Precedens i úvaha
jsou tytéž jako u #73, #216, #392 a #413: výčet se rozšířil, protože se ta věc dělá při review,
a zapsal se důvod.

Co je na téhle metodě jiné než na sedmi před ní:

- **Mění `main`, ne pull request.** Šest z předchozích sedmi sahalo na PR nebo na diskuzi, sedmá na
  labely repozitáře; tohle je jediná akce v okně, po které se změní cílová větev. Nevratnost se
  vyvažuje **dvěma** věcmi, ne jednou: potvrzením s úplným výpisem (jako u review, #68) **a hlavou
  v payloadu**.
- **Hlava je v payloadu jako podmínka, ne jako údaj.** `sha` v `PUT /pulls/{n}/merge` je pro GitHub
  pojistka: když se větev mezitím pohnula, odpoví `409` a **nemergne nic**. Změřeno na
  `ondrajodas/prism-review-sandbox#8` — pokus s cizí `sha` vrátil
  `{"message":"Head branch was modified. Review and try the merge again.","status":"409"}`. Je to
  ochrana, kterou review mít **nemůže**: `commit_id` u review je údaj a zastaralé review projde
  (změřeno u #62). Pre-flight se u merge dělá **navíc**, aby se z neshody dala napsat věta o starém
  a novém commitu, místo aby se člověk dozvěděl `409`.
- **Metoda není volba, ale konstanta.** `MergeRequest.method` je `squash` a čte ji payload
  **i potvrzení** — jedno místo, takže se kresba a to, co odejde, nemůžou rozejít. Plán proto pole
  `method` nemá vůbec: bylo by to pole s jedinou dosažitelnou hodnotou, tedy mrtvá váha a druhé
  místo k rozejití. Kdo chce jinou metodu, jde na GitHub.
- **`commit_title` se posílá, `commit_message` ne.** Bez `commit_title` si titulek skládá GitHub podle
  nastavení repozitáře (`Default to pull request title for squash merges`), do kterého aplikace
  nevidí — potvrzení by tedy ukazovalo titulek, který nemusí vzniknout. Skládá ho
  `Policy.squashTitle(of:number:)` jako `titulek PR (#číslo)`. Tělo se naopak **neposílá schválně**:
  bez něj složí GitHub tělo squash commitu ze zpráv slévaných commitů, a přesně tak vypadá celá
  historie `main`u v tomhle repu. Ověřeno mergem sondy — titulek byl přesně poslaný `commit_title`
  a pod ním odrážky se třemi zprávami z větve. Že to tak bude, **je napsané v potvrzení**, protože
  jinak by věta „vypsané je všechno, co se stane“ slibovala víc, než co je vidět.
- **Vlastní volající, ne metoda v `MetadataSubmission`.** Je to jediné místo, kde se #465 od #392
  liší: labely a reviewery jsou akce z panelu, které se dějí a mizí, kdežto merge má **potvrzovací
  obrazovku a životnost** — `MergeSubmission` vzniká kliknutím na `Mergnout…`, drží snímek toho, co
  se potvrzuje, a zaniká zavřením sheetu. Tvarem je to `ReviewSubmission`, ne `MetadataSubmission`.
- **`AppStore` o mergi nedrží žádný stav.** Sheet ho drží celý (`@State` v `ContentView`), takže po
  něm ve store nezůstane ani chyba k úklidu — na rozdíl od `MetadataActionState`, který existuje
  proto, že akce v panelu musí přežít překliknutí tabu.
- **Sheet nebydlí v detailu PR.** Je to tatáž past jako u `ReviewSubmission` a o stupeň horší:
  mergnutý PR ze zdroje `author:@me` na příštím tiku **vypadne**, takže by sheet zavěšený na detailu
  zmizel zrovna s hláškou, kvůli které je otevřený.
- **Po úspěchu se zavírá sheet i záložka toho PR** (`AppStore.pullRequestWasMerged`). Do #465 tu
  stálo, že se sheet nezavírá — s odůvodněním, že mergnutý PR ze seznamu vypadne, takže by zavřený
  sheet nechal člověka koukat na tab, který se přestal kreslit. **Tím, že odchází i ta záložka, ten
  důvod padl**: za sheetem není mrtvý tab, ale okno přepnuté na sousední záložku nebo domů.

  Čtyři věci, které to drží pohromadě:

  - **Zavírá se až po úspěchu, ne po kliknutí.** Po `409`, `405` i po spadlé síti zůstává záložka
    i sheet — je to jediné místo, kde je vidět, co GitHub odmítl a jestli se dá zkusit znovu. Sem
    se po selhání ani nedojde: `MergeSubmission` volá úklid jedině nad `.merged`.
  - **Pořadí drží `merge()`, ne view.** `closeTab` je první řádek úklidu a běží ještě v tom
    průchodu, ve kterém se přepnul stav; sheet zavírá až volající podle `closesItself`, tedy po
    návratu z `merge()`. Opačné pořadí by na okamžik odhalilo detail PR, který se za chvíli
    přestane kreslit.
  - **Pravidlo o zavírání záložek se tím neruší.** „Mergnutý PR jde ještě dočíst a zavřít ho má
    člověk, ne tik pollingu“ mluví o **pollingu** — o PR, který ze seznamu vypadl, aniž bych s tím
    cokoli udělal. Tady záložku zavírá klik na `Mergnout`, tedy tentýž člověk tímtéž gestem,
    kterým ten PR dokončil. Prázdný stav *Pull request zmizel ze seznamu* zůstává pro to, co se
    stalo jinde: cizí merge, odebraný request na review.
  - **Bez ptaní, i kdyby na PR leželo rozdělané review.** `closeTab` nic nezahazuje (má na to
    vlastní test už od #180) a draft leží v `ReviewDraftStore` na disku, takže je s otevřenou
    záložkou zpátky. Na vlastním PR se navíc draft ani nedá založit (#333). Dialog by tedy byl
    otázka na nic — a smazat draft by bylo to jediné nevratné na jinak vratném zavření.
- **Stav PR se přesto načte znovu.** Zavřená záložka není konec: PR zůstává v seznamu až do dalšího
  tiku, takže se dá otevřít znovu — a se zapamatovaným detailem by v panelu zase svítilo
  `Mergnout…` u něčeho, co je mergnuté. Že s detailem přijdou i checky a commity, je **cena za
  jednu cestu**: `loadDetail` je jediné místo, které umí detail načíst správně (razítko hlavy,
  zápis do dění), a duplikovat ho kvůli dvěma voláním navíc by znamenalo dvě skládání téhož. Merge
  je akce jednou za čas, ne tik pollingu.
- **Dvě nové chyby, obě s dalším krokem.** `branchMoved` (409) říká, že se **nic nestalo**
  a pojistka zabrala; `notMergeable` (405) říká, že se stav mezi načtením panelu a kliknutím změnil,
  a **neradí zkoušet znovu** — dokud se stav nezmění, dopadne druhý pokus stejně. `branchMoved`
  pokrývá i `Base branch was modified`, protože další krok je u obou tentýž.
- **Co v zákazu zůstává**: approve mimo review, **zavření PR**, **milník** a `deleteLabel`.
  `SingleWayOutTests` je hlídají jmenovitě dál — jen bez `merge`.

## Vestavěný terminál (#459)

`App/Terminal/` — shell v zásuvce pod diffem, návrh sekce 35. Jsou to tři soubory a každý drží
něco jiného:

| Typ | Co drží |
|---|---|
| `TerminalSlot` | **Jedna relace = jedno pty** (#460): `(pull request, role)`, kde role je holý `shell` nebo `session(skill)`. Klíčem je dvojice, ne jen skill — pracovní adresář je adresář *toho* PR |
| `TerminalHosting` | Protokol: kolik shellů běží, plocha pro **relaci**, **napsat do ní řádku** (#460), zabít jednu relaci, zabít **všechny relace jednoho PR**, zabít všechno, a dva uzávěry (stav, fokus). **Bez zápisové metody a bez `gh`** |
| `TerminalHost` | Živá implementace — **jeden `EmbeddedTerminalView` na relaci**, řez a barvy z palety; plochu vyrábí jedno místo (`surface(for:in:)`), aby `` ⌃` `` a `▶` nedaly dva různé shelly |
| `EmbeddedTerminalView` | `SwiftTerm.LocalProcessTerminalView` s pěti věcmi navíc: start login shellu v daném adresáři, hlášení fokusu, `kill()`, který zabije **popředí pty**, ne jen shell, a od #460 `hasForegroundJob` (běží tam něco?) se `send(line:)`. Od #478 k tomu **kolečko** — hlášení myši aplikaci, která si o něj řekla, a zaklesnutí výřezu proti chybě v knihovně |

Rozhodnutí, která k tomu patří, jsou v `Policy` — `App/Policy/TerminalDrawer.swift` (výška zásuvky
a její ořez, jestli zkratka ustupuje terminálu, kde shell startuje, jak se cesta zkrátí na `~`, co
se spustí a s jakým prostředím, na co se aplikace zeptá při ukončení a co se řekne po `▶`)
a `App/Policy/TerminalSlots.swift` (#460: kdo smí vzniknout, co se kvůli stropu vytlačí, co je na
záložce vidět) a `App/Policy/TerminalWheel.swift` (#478: hlásit kolečko, nebo rolovat historii,
kolikrát, a kde výřez zůstane, když pod ním přiteče výstup).

### Víc relací naráz (#460)

Do #460 platilo „jedna zásuvka = jeden shell na pull request“. Nefungovalo to v tom stavu, kvůli
kterému zásuvka vznikla: aplikace pouští review **paralelně** (`maxConcurrentReviews`, ve výchozí
konfiguraci tři), takže se člověk chce dívat na dvě session naráz — a jeden shell ho nutil jednu
z nich ukončit, aby viděl druhou. Návrh, sekce 35, poznámka 112.

Zásuvka proto drží **N relací** a přepíná se mezi nimi **záložkami** v hlavičce (`.term-tabs`
z návrhu; ne rozbalovací nabídkou — relace jsou dvě až tři, pořád jedna běží, a nabídka by po
každém pohledu na druhou stála dva kliky místo jednoho). **Holý shell je jedna z relací**, tedy to,
co dá `` ⌃` ``, ne něco vedle nich.

Šest věcí, které na tom nejsou zjevné:

- **Klíčem je `(PR, role)`, ne skill.** Pracovní adresář je adresář **toho** PR, takže relace
  stejného jména na dvou pull requestech jsou dvě různé věci a nesmí se potkat v mapě hostitele.
- **Adresář se drží per relace**, ne per PR: holý shell stojí v klonu nebo ve stromu posledního
  review, kdežto relace dráhy ve stromu **té** session — a `claude --resume` hledá vlákno podle
  adresáře.
- **Plocha se v SwiftUI klíčuje relací** (`.id(activeSlot)`), a je to podmínka, ne optimalizace:
  `makeNSView` se volá jen při vzniku representable, takže bez změněné identity by po přepnutí
  záložky zůstala v hierarchii plocha té předchozí. Plochy vlastní hostitel, takže odebraná relace
  běží dál.
- **Strop je pět** (`Policy.maxTerminalSlots`) a je složený ze dvou čísel: zdola z toho, že
  `maxConcurrentReviews` je tři a k paralelním reviewerům patří ještě holý shell (čtyři jsou tedy
  běžný stav, ne krajnost); shora z toho, že přepínač je **řádek v hlavičce** vedle cesty a kapsle
  `plná práva`. Neomezený počet by byl past ne kvůli paměti, ale proto, že každá relace je
  **skutečný proces**, který se musí uklidit — a co se nedá spočítat, to se špatně uklízí.
- **Vytlačuje se jedině neběžící relace, a vždycky ta nejstarší.** Zahodit běžící shell by
  znamenalo zabít rozdělanou práci kvůli kliknutí, které o ní nic neví; zahodit doběhlou stojí
  **jen její výpis**. Když neběžící žádná není, nová relace **nevznikne** a řekne se to
  (`Policy.slotsFullNotice`) — mlčky nevzniklá záložka vypadá jako rozbité tlačítko. Zavírací
  křížek u záložky návrh nekreslí, takže tohle a zavření záložky PR jsou **jediné** dvě cesty, jak
  relace ubývají.
- **Uzávěry se odpojí dřív, než se plocha zabije.** `kill()` končí `terminate()`, po kterém
  knihovna ohlásí konec procesu **asynchronně** — a ten hlas by zapsal stav relace, která už
  v seznamu není. Vznikl by záznam, který nikdo nekreslí a který by po vzniku stejnojmenné relace
  ukázal cizí minulost. **Značku v `sessions.json` to neohrozí**: tu maže `kill()` sám, ne callback.
- **Cesta v hlavičce se hotové relaci nepřepisuje.** `` ⌃` `` adresář hledá znovu, protože pracovní
  strom se posune s novým commitem a eviction ho umí sebrat — ale jen relaci, která ho ještě nemá.
  `TerminalHost` totiž vrací **existující** plochu a nový adresář si nevezme, takže by popiska
  ukazovala jinam, než kde shell doopravdy stojí.
- **Relace končí se záložkou pull requestu, ne dřív.** Je to tatáž hranice jako u jednoho shellu
  v #459 — zavřená záložka je konec kontextu —, jen se maže **celý seznam**: `stopTerminals(for:)`
  jde přes všechny relace toho PR, protože osiřela by zrovna ta, která nebyla vidět. Ukončení
  aplikace zabíjí všechny (`stopAllTerminals`) a značku v `sessions.json` má **každá relace
  vlastní**.

**Puntík u záložky má tři stavy, i když návrh kreslí dva** (`.term-tab .d` a `.term-tab.live .d`),
a je to vědomé rozšíření o jednu barvu na prvku, který nakreslený **je**: do #460 stála v hlavičce
kapsle `skončil (kód)` a odlišit `exit 1` od `exit 0` bylo zrovna to, kvůli čemu se na ni člověk
podíval. S víc relacemi se tři kódy do hlavičky nevejdou, takže z toho je puntík — ale úplně beze
stopy ta informace zmizet nesmí. `crit` proto znamená **nenulový** konec a celý kód zůstává
v nápovědě záložky (`Policy.terminalSlotHelp`). Kód, který **nedorazil**, se přitom kreslí jako
klid, ne jako chyba: je to odpověď „nevíme“, a červený puntík by tvrdil víc, než data unesou.

### Důvěra ke složce a auto-mode (#460)

`▶` pouští **interaktivní** `claude`, a to s sebou nese dvě věci, které se review sessions netýkají
(ty běží s `-p`):

- **Dotaz na důvěru ke složce.** Interaktivní `claude` se v neznámém adresáři ptá *„Is this
  a project you created or one you trust?“* — a protože **každý PR dostane vlastní pracovní
  strom**, přišel by ten dialog u každého PR znovu. Zapisuje se proto `hasTrustDialogAccepted`
  do `~/.claude.json`, a to **jednou, na kořen cache**: změřeno, že se důvěra dědí z libovolného
  předka. Je to postup, na který odkazuje sám `claude` ve své binárce, a je to zároveň **přesně ta
  hranice, kterou aplikace už má** (tvrdá podmínka č. 3). Měření a tvar záznamu jsou
  v [`docs/claude-cli.md`](claude-cli.md).
- **Režim povolení `auto`** (`Policy.drawerResumeCommand`). Session, kterou řídí člověk ve svém
  shellu, nemá přerušovat práci dotazem u každého kroku. **Nová práva to nedává** — zásuvka je
  plnohodnotný shell s kapslí `plná práva`, takže odpadají **dotazy**, ne hranice. `auto` je z těch
  šesti režimů jediný s vyjmenovanými a čitelnými pravidly; `bypassPermissions` je „bypass all
  permission checks“ a do repa nepatří.

Dvě věci na tom nejsou zjevné:

- **`⧉` a `▶` se od #460 rozcházejí, a je to vědomá změna proti #453.** Do té doby tu stálo, že je
  to týž příkaz. Zůstává z toho to podstatné — **skládá to jedna funkce**
  (`drawerResumeCommand` = `resumeCommand` + režim), takže se ty dva texty nemají čím rozejít, a
  liší se přesně o jednu vyjmenovanou věc. `⧉` ji nedostane schválně: kdo si příkaz kopíruje jinam,
  dostane ho tak, jak by ho psal.
- **Selhání zápisu důvěry se nehlásí ve stavovém řádku**, a je to zapsaná výjimka z pravidla
  o spolknutých chybách. Otázka, kterou to pravidlo klade, zní „pozná uživatel, že se to
  nepovedlo?“ — a tady zní odpověď **ano, sám od sebe**: objeví se ten dotaz na důvěru, tedy přesně
  to, co to mělo ušetřit.

### Rolování — co se u #460 naměřilo

Hlášení znělo „nejde mi scrollovat v tom terminálu“. Rozpadá se na tři otázky, každá znamená jinou
opravu, a **žádná z nich nevyšla jako chyba** (`TerminalScrollProbe`):

| Co se měřilo | Naměřeno |
|---|---|
| Dostane kolečko emulátor, nebo ho spolkne něco nad ním? | `hitTest` uprostřed zásuvky padne **do plochy emulátoru**. Měří se **v okně**: bez okna vrátí `hitTest` kořen a plochu vůbec nenajde, přestože v hierarchii je — sonda bez okna by tedy hlásila chybu, která není |
| Má čím rolovat? | Scrollback **500 řádků**; po kolečku se výřez posune (`yDisp` 380 → 377) |
| A nad běžícím TUI? | `yDisp` 0 → 0 — **správně**: alternativní buffer scrollback nemá |

**Rozhodující je ta třetí řádka.** `claude` posílá `ESC[?1049h` (alternativní buffer) **a k tomu
plné hlášení myši** (`?1000h`, `?1002h`, `?1003h`, `?1006h`) — změřeno pty sondou. Kolečko se mu
tedy **doručuje jako událost** a co s ním udělá, je jeho rozhodnutí; terminál nemá kam couvnout,
protože alternativní buffer je z definice bez historie. Tak se chová `Terminal.app` i `iTerm`.
**Neopravovalo se proto nic** — v holém shellu se roluje normálně a nad běžícím `claude` se roluje
uvnitř `claude`.

> **Druhá půlka téhle věty byla nepravdivá a opravilo ji #478.** `claude` si o hlášení myši
> **řekl** (to sedí), ale `SwiftTerm` kolečko aplikaci **nikdy nepředá** — `MacTerminalView`
> `scrollWheel` roluje jen vlastní historii, a ta v alternativním bufferu není. Kolečko se tedy
> nedoručovalo nikam a „rolovat se má uvnitř `claude`“ znamenalo, že se nedá rolovat vůbec.
> Sonda to nechytla proto, že se ptala na **výřez emulátoru** (`yDisp` 0 → 0), což je nad
> alternativním bufferem správná odpověď na obou stranách — pravdivou od nepravdivé ji dělí až
> otázka *co odešlo do procesu*, a ta v sondě nebyla. Co s tím dál, je v sekci níž.

### Kolečko aplikaci v terminálu (#478)

Dvě chyby vedle sebe, obě se projeví jako „v zásuvce nejde rolovat“, a **každá potřebuje jinou
opravu** — proto se drží zvlášť i v kódu.

#### 1. Knihovna kolečko aplikaci nepředá

`MacTerminalView.scrollWheel` roluje **jen scrollback** (`scrollUp`/`scrollDown`). Kliknutí a pohyb
myši knihovna aplikaci předává (`encodeMouseEvent`, `sendEvent`), kolečko ne — je to chybějící
půlka hlášení myši. `Terminal.app` i iTerm ho překládají na tlačítka **64 nahoru / 65 dolů**
a posílají; proto v nich rolování nad `claude` funguje.

Opravou je hlásit totéž, ale **musí se to vzít dřív než knihovna**:

- **`scrollWheel(with:)` se přebít nedá** (ověřeno překladačem: `overriding non-open instance
  method outside of its defining module`). `TerminalView` je `open`, jenže tuhle metodu deklaruje
  jako `public override` — a `public` člen se z cizího modulu přepsat nesmí. Kolečko se proto bere
  **lokálním odběrem** (`NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)`), který je
  volaný **před** doručením do okna; vrácené `nil` znamená, že se k `MacTerminalView` událost
  nedostane.
- **Zamítnutá varianta**: podhled přes plochu, který si o kolečko řekne v `hitTest`u. `hitTest`
  typ události nezná, takže se to dá říct jedině přes `NSApp.currentEvent` — a ten je za hit
  testem jen **naposledy doručená** událost, tedy domněnka. Pořadí odběru je proti tomu popsané
  v dokumentaci API.
- **Kdo si událost vezme, rozhoduje `claimsWheel`, a napřed obdélníkem.** Odběr je na celý proces,
  takže jím projde **každá** otočka kolečka v aplikaci — i ta nad diffem, kde je cena projíždění
  měřená věc (#469). Pořadí je proto `event.window === window` → `visibleRect.contains(…)` →
  teprve pak hit test celého okna. **`visibleRect`, ne `bounds`**: v zásuvce může být relací víc
  (#460) a ta neaktivní má prázdný výřez, takže si o kolečko neřekne. A **`hitTest` bere bod
  v souřadnicích nadřazeného view**, tedy `locationInWindow` beze změny — převádět ho do souřadnic
  `contentView` je tichá chyba, která v okně s titulkem sedne a s `fullSizeContentView` ne.
- **Rychlost je v počtu hlášení.** Jedno hlášení nese jen „cvaklo“, takže se posílá tolikrát,
  o kolik řádků by se posunula historie (`Policy.terminalWheelLines`, opsaná
  `calcScrollingVelocity` — v knihovně `private`). Bez toho by se v `claude` rolovalo o řádek na
  otočku, kdežto v shellu vedle po trojicích: dvě různé rychlosti v jedné ploše. Že se opsaná
  křivka s knihovnou nerozešla, hlídá test **chováním**
  (`TerminalWheelTests.theCurveStillMatchesTheLibrary`) — a stupeň se určuje z **celé části**
  (`Int(abs(deltaY))`), ne ze zaokrouhlení.
- **Historii roluje náš kód, i když se nehlásí nic.** Událost se spolkne vždycky — je to kvůli
  pořadí: zaklesnutí výřezu (níž) se musí zapsat **po** posunu, kdežto propuštěná událost by se
  rolovala až po návratu z odběru a zapsala by se poloha před ním.
- **Rozhoduje se při každé události**, ne jednou při vzniku plochy: `mouseMode` je stav emulátoru,
  který si mění aplikace pod ním — `claude` ho zapne při startu a při odchodu vypne. Bere se
  k tomu i `allowMouseReporting`, tedy vypínač knihovny kvůli výběru textu myší.
- **`isolated deinit`, ne `MainActor.assumeIsolated`.** Odběr sundává `viewDidMoveToWindow(nil)`;
  `deinit` je pojistka pro plochu, která zanikne i s oknem. Běžný `deinit` je nezaizolovaný, takže
  by na cizím vlákně `assumeIsolated` **spadl** a `NSEvent.removeMonitor` by k tomu byl voláním
  AppKitu mimo hlavní vlákno. A **návratová hodnota `assumeIsolated` musí být `Sendable`**, což
  `NSEvent` není (`conformance of 'NSEvent' to 'Sendable' is unavailable`) — dovnitř proto jde
  rozhodnutí, ven `Bool`, a událost se zahazuje až venku.

#### 2. `Terminal.userScrolling` se v `SwiftTerm 1.11.2` nikdy nenastaví

Druhá půlka, a bez ní by ta první k ničemu nebyla: **odrolovaný pohled se vrátil dolů dřív, než ho
stačil kdo přečíst.**

`Terminal` má na to vlastní příznak. Čte se **třikrát** (`Terminal.swift:5074`, `5084` a `5110`,
všechno uvnitř `scroll()`) a rozhoduje o tom, jestli nový řádek stáhne výřez dolů
(`buffer.yDisp = buffer.yBase`). **Nezapisuje se do něj z jediného místa.** Zápisy, které v balíčku
jsou (`AppleTerminalView.swift:1497` a `1514`, uvnitř `scroll(toPosition:)`), míří na
**stejnojmennou vlastnost plochy** (`MacTerminalView.swift:493`, `iOSTerminalView.swift:1142`) —
a tu zase nečte nikdo. Jsou to dvě mrtvé poloviny jednoho příznaku.

Změřeno chováním, ne jen čtením kódu (`TerminalWheelTests.theLibrarySnapsTheViewportBack`, plocha
800×300 = **21 řádků**, 400 nakrmených řádků): po `scrollUp(lines: 20)` je `yDisp` **360**, po
jediném dalším řádku **381**, tedy dno. Jeden řádek výstupu tedy zahodí celou stránku odrolování.

Kompenzují to čtyři místa v `EmbeddedTerminalView`:

- **`pinnedRow`** — kde výřez zůstal (`Policy.terminalViewportPin`). **Dole se nezaklesává**, tam
  je „jet s výstupem“ ta správná odpověď; zaklesnutí se proto ruší tím, že se člověk vrátí dolů.
- **`dataReceived(slice:)`** vrátí výřez zpátky **až po `super`** (teprve nakrmení s ním hne)
  a jedině **dolů → nahoru** (`Policy.terminalViewportRewind`), takže rolování mezitím tuhle cestu
  nikdy nepřebije. Měřeno na téže scéně: `yDisp` 377 → 377.
- **`bufferActivated(source:)` zaklesnutí zahodí.** Bez toho by poloha z doby před `claude` ožila
  ve chvíli, kdy se člověk vrátí do shellu, a výřez by se sám odrolil nahoru — v alternativním
  bufferu se `yDisp` drží na nule, takže se tam zapamatovaný řádek neuplatní a jen čeká.
- **`send(source:data:)` zaklesnutí přepočítá, ne zruší natvrdo.** `send(data:)` srovná výřez na
  kurzor (`ensureCaretIsVisible`) **ještě před** tím voláním, takže po vstupu od člověka jsme dole
  a zaklesnutí padá — napsat něco znamená chtít vidět, co to udělá. Odpověď emulátoru na dotaz
  aplikace (`DA`, `XTVERSION`) touhle cestou nejde, takže odrolovaný pohled nechá být.

**Až knihovna svůj příznak opraví, jde tahle půlka pryč** — a pozná se to podle toho, že
`theLibrarySnapsTheViewportBack` **spadne**. Je to test, který schválně tvrdí chybu cizího kódu.

### Změna velikosti — co se u #460 naměřilo

Hlášení z #459 znělo „resize ne úplně funguje, asi se přeskládává text“. Rozpadá se na tři otázky
a **všechny tři vyšly čistě** (`TerminalResizeProbe`, měřeno přes `NSHostingView`, aby v cestě stál
i `TerminalSurface` a rámec od SwiftUI):

| Co se měřilo | Naměřeno |
|---|---|
| Dojde šířka okna přes SwiftUI do emulátoru? | 1 200 b → **163** sloupců, 700 b → **92**, zpátky 1 000 b → **134**. Řádky se u toho **nehnuly** (14), takže šířka nepřesází nic, co s ní nesouvisí |
| Ví jádro totéž co emulátor? | Plocha 1 000×300: emulátor **138×21**, jádro **138×21** buněk a **1 000×300 px**. Po zúžení na 600 b: **82×21** na obou stranách. Pixelové rozměry nejsou nula (sixel a `kitty` protokol na nich stojí) |
| Neposílá se `TIOCSWINSZ` častěji, než se rozměr mění? | 61 průchodů rozvržení přes 60 bodů → **8** změn šířky v jádře (buňka je široká ~7 b). `claude` tedy nedostane desítky `SIGWINCH` se stejnou velikostí |

**Co z toho plyne**: přeskládání textu, které je vidět, je **reflow scrollbacku** — a `SwiftTerm`
ho dělá podle správné úmluvy. `Buffer.isReflowEnabled` je `hasScrollback`, takže se přesází
**jen normální buffer**; alternativní, do kterého kreslí celoobrazovkové TUI, se **nereflowuje**
vůbec, jen změní rozměr a aplikace si ho překreslí sama. Přesně tak se chová `Terminal.app`
i `iTerm`. **Neopravovalo se tedy nic** a je to zapsané schválně: bez toho to příště někdo zkusí
znovu.

Jedna věc zůstává **neověřená a je to poznamenané**: jak vypadá obsah po přesázení, se z harnessu
přečíst nedá (#459 — `LocalProcess` doručuje bajty přes hladovou hlavní frontu), takže „vypadá to
rozbitě, nebo jen jinak“ posoudí jedině člověk na běžící aplikaci.

**Proč je to devátý modul, a ne jen view.** Shell je cizí proces — tedy vnější svět jako `gh`,
`git` a `claude` —, takže patří za protokol se stejným zdůvodněním: nejcennější tvrzení kolem něj
je „něco se **ne**stalo“ (zavření záložky shell zabilo, ukončení aplikace po sobě nic nenechalo),
a to jde napsat jedině proti fake implementaci.

### Co na tom není zjevné

- **`SIGKILL` na popředí pty, ne `terminate()`.** Knihovní `terminate()` posílá `SIGTERM`
  **shellu**, a to na závazek z #264 nestačí: `claude` spuštěný v interaktivním shellu dostane
  vlastní process group (job control), takže by ho signál poslaný shellu **minul** a osiřel by na
  `launchd` úplně stejně jako v #351. Zabíjí se proto `tcgetpgrp(childfd)` a **až pak** shell —
  v tomhle pořadí, protože po smrti shellu se pty zavírá a `tcgetpgrp` nemá koho vrátit.
  `terminate()` se volá i tak: je to jediná cesta, jak knihovna zavře `DispatchIO` a deskriptor.
  `killpg` se u toho volá jen na `> 0` — `tcgetpgrp` vrací `-1` u deskriptoru, který není řídicí
  terminál, a `killpg(0, …)` by znamenalo **naši vlastní** skupinu, tedy zabít aplikaci.
- **Značka v `sessions.json`** (#351) toutéž cestou jako u review: zapisuje se po startu, maže se
  v `kill()` **i** v `processTerminated` (shell umí skončit sám přes `exit`). V `kill()` schválně
  hned, ne až v callbacku — při ukončení aplikace už žádné další kolo runloopu nemusí přijít.
- **Fokus se hlásí přes `hasFocus`, ne přes `becomeFirstResponder`.** Ty dvě metody má knihovna
  `public`, ne `open`, takže je z jiného modulu přepsat **nejde** (ověřeno překladačem);
  `hasFocus` je `open` a knihovna ho z obou nastavuje, takže je to tentýž okamžik. Hlásí se
  **jen změna** — setter chodí i tam, kde se hodnota nemění, a bezpodmínečný zápis do stavu okna
  je zrovna ta třída, kterou popisuje #358.
- **Barvy se musí dát nasadit znovu.** `SwiftTerm` si dynamickou `NSColor` převede na svoje hodnoty
  **ve chvíli přiřazení**, takže o pozdějším přepnutí režimu neví — a aplikace ho umí vynutit
  v railu (#278). Přenastavuje se proto z `viewDidChangeEffectiveAppearance`, a vyhodnocuje se
  uvnitř `performAsCurrentDrawingAppearance`: mimo kreslení není `NSAppearance.current` nutně
  vzhled tohohle view.
- **`TIOCSWINSZ` se nikde neopisuje** — dělá to `SwiftTerm` v `setFrameSize` → `processSizeChange`
  → `sizeChanged`. Proto ale **zavřená zásuvka nesmí zůstat v hierarchii**: plocha nulové výšky by
  běžícímu TUI ohlásila `0×0` a TUI by se překreslilo do nesmyslu.
- **`PATH` se do shellu nepředává** (`Policy.terminalEnvironment`). GUI aplikace ho má osekaný na
  systémové složky — právě proto v repu existuje `BinaryLocator` —, takže předat ho dál znamená
  zásuvku bez Homebrew. Login shell si ho složí sám (`argv[0]` s pomlčkou → `/etc/zprofile`
  a `path_helper`, pak `.zprofile` uživatele). Je to tatáž volba, jakou dělá `Terminal.app`.
- **Plochu vlastní hostitel, ne SwiftUI.** `makeNSView` se volá při každém složení stromu, takže
  plocha vlastněná representable by znamenala **nový shell po každém zavření a otevření zásuvky**.
  `updateNSView` je prázdný schválně: nic v té ploše nejde ze SwiftUI stavu, takže by tam byl zápis,
  který se při každém přepočtu geometrie zopakuje pro nic (#393).
- **Výška se ukládá na konci tažení**, ne z měření rozvržení. Vzor `Policy.rawSessionSheetSize`
  (#327) se převzal na **ořez** (uložená hodnota se clampuje při použití, protože v `UserDefaults`
  může být cokoli), ale past s prvním průchodem rozvržení tady **není** — výšku nikdo nenavrhuje,
  mění ji jedině tažení. Odmlka jako `RawSessionSheet.resizeSettle` proto potřeba není.
- **Kapsle v hlavičce ukazuje `běží` / `skončil (kód)`, ne běžící příkaz**, jak ho kreslí návrh.
  Zjistit příkaz znamená ptát se jádra na popředí pty v pravidelném taktu, tedy zavést v okně další
  časovač kvůli popisce. Je to méně, než slibuje mockup, ale nic z toho není nepravda — a `exit 1`
  se od `exit 0` odliší, což je to, kvůli čemu se na kapsli člověk podívá.
- **Do zásuvky se píše `CR`, ne `LF`, a posílá se rovnou** (#460, `send(line:)`). `↵` posílá přes
  terminál `CR`; v kanonickém režimu ho `ICRNL` převede na `NL`, v `ZLE` je navázaný na
  `accept-line`. Změřeno pty sondou, že obojí projde stejně (4 ze 4 u obou), takže se vybíralo
  podle pravidla, ne podle rozdílu. **Čeká se s tím na nic**: bajty zapsané dřív, než `ZLE`
  naběhne, počká linková disciplína ve vstupním bufferu a shell je zpracuje na prvním promptu
  (změřeno 5 z 5, i s `.zshrc`, který před promptem sekundu spí). Cena je jedna **ozvěna řádky
  navíc nad promptem** — echuje ji linková disciplína dřív, než si `ZLE` řádek překreslí; zamítnuté
  bylo počkat na první výstup shellu, protože by z toho byl stav navíc a nové selhání pro shell,
  který sám od sebe nic nevypíše.

  Dvě věci u toho **nejsou volitelné**. Píše se přes **`send(txt:)` knihovny, ne přímo do
  `process`**: ta cesta navíc srovná výřez na kurzor (`ensureCaretIsVisible`) a ohlásí terminálu
  vstup — bez toho by řádka odešla, ale zásuvka odrolovaná nahoru by zůstala stát a vypadalo by to,
  že se nic nestalo. A **deskriptor se kontroluje zvlášť od `running`**: `LocalProcess` na `EOF`
  z pty nastaví `childfd = -1` a `running` nechá na `true`, dokud nedorazí událost o konci procesu,
  takže zápis by tiše propadl a `run` by hlásil `sent`. Proto `send(line:)` vrací **`Bool`** a `run`
  z něj skládá odpověď, místo aby ji předpokládal.
- **`run(_:for:in:)` po skončeném shellu pustí nový** (#460), na téže ploše. `▶` je žádost o běžící
  session, takže tlačítko, které po jednom `exit` přestane fungovat, by nechalo jako jedinou cestu
  zpátky zavření záložky. Starý výpis v ploše přitom zůstane, což je pro čtení předchozí session
  spíš dobře. Výsledek se u toho **čte, ne předpokládá** (`isRunning`): `fork`/`exec` umí selhat,
  a `started` nad neběžícím shellem by tvrdilo, že se něco pustilo.

## Vrstva `Environment` (`App/Environment/`)

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
| `UserNotifying` | Protokol: doručit notifikaci a dát proud kliknutí. `PullRequestNotification` je vstup, `NotificationDelivery` výsledek |
| `PreferenceStoring` | Protokol nad trvalými předvolbami (stav aplikace, ne `config.json`); `UserDefaults` ho splňuje |
| `SystemNotificationCenter` | `UNUserNotificationCenter` za tím protokolem — **statická jediná instance** a delegát, který kliknutí převádí na hodnotu v proudu |
| `ProcessIdentity` | `(pid, startedAt)` — dvojice, kterou nejde splést s recyklovaným PID (#351) |
| `ProcessInspecting` | Protokol: co jádro ví o procesu a `SIGKILL` **na identitu, ne na PID**. `SystemProcessInspector` nad `sysctl(KERN_PROC_PID)` |
| `WorkspaceTrusting` | Protokol: zapiš důvěru ke složce do `~/.claude.json` (#460). `ClaudeWorkspaceTrust` — **jediné místo, kde aplikace píše mimo svoji cache**. Na soubor, kterému nerozumí, **nesáhne**; zapisuje **atomicky** (`replaceItemAt`, přenese `0600`) a **jen jednou** — hotová důvěra se nepřepisuje, takže běžný případ je čisté čtení |
| `TerminalOpening` | Protokol: pusť řádku v novém okně terminálu (#453). `AppleScriptTerminal` nad `/usr/bin/osascript` — **není to druhá cesta ven**, terminál je mimo aplikaci. Příkaz jde do skriptu jako `argv`, ne vlepený do jeho zdrojáku, a selhání se **vrací jako chyba** (`TerminalError`), ne mlčí. **Od #460 to nikdo nevolá** — drží se jako záloha i s `NSAppleEventsUsageDescription`, viz specifikace |

Nad notifikacemi (#88) platí:

- **Notifikace fungují jedině z `/Applications`.** Změřeno: z buildové složky v repu
  i z `~/Applications` vrací `requestAuthorization` chybu
  `Notifications are not allowed for this application`
  a `authorizationStatus` zůstane `denied` — **bez dialogu a bez záznamu v Nastavení
  systému**, takže se to nedá ani ručně povolit. Není to vlastnost PRismu: stejnou chybu
  dostala minimální cizí aplikace s jiným bundle identifikátorem. Postupně se vyloučil
  podpis (self-signed, ad-hoc, hardened runtime), `get-task-allow`, Debug proti Release,
  duplicitní záznamy v LaunchServices, restart `usernoted` i MDM profily. Proto `bin/run.sh`
  instaluje do `/Applications` a spouští odtud.
- **`deliver(_:)` si o oprávnění řekne sám**, zvláštní metoda na to není. Dialog má přijít
  až u první notifikace (ten hned po instalaci se odklikne pryč) a jedna cesta znamená, že
  se ta chvíle nedá minout. `requestAuthorization` je idempotentní — po prvním rozhodnutí
  systém dialog neukáže a jen vrátí stav, takže si „už jsem se ptal“ nikdo pamatovat nemusí.
- **Jedna statická instance, a schválně.** Delegát je vlastnost systémového singletonu
  (`UNUserNotificationCenter.current()`), takže druhá instance by první přebila delegáta
  a kliknutí by tiše přestala chodit. Singleton je tady obraz toho, že systémové centrum je
  jedno, ne kompromis kvůli protahování objektu. V testech se nepoužije: `AppStore` dostane
  fake parametrem.
- **Delegát se nastavuje při startu** (`AppDelegate.applicationDidFinishLaunching`), ne až
  u první notifikace. Když aplikaci spustilo právě kliknutí na notifikaci, systém ho doručí
  hned po startu — tedy dřív, než projde preflight a složí se `AppStore`. Proud kliknutí si
  je proto **drží**, dokud si je store nevyzvedne; je na to test.
- **Proud kliknutí má jednoho konzumenta.** Systém má delegáta jednoho, takže i proud je
  jeden — druhé volání `clicks()` by prvnímu kliknutí kradlo.
- **Okno dopředu dává vrstva prostředí, ne store.** Aktivace aplikace je přístup ke stroji
  stejně jako doručení notifikace, takže `AppStore` zůstává bez AppKitu a v testech se nic
  neaktivuje. Dopředu se jde i tehdy, když identifikátoru nerozumíme — kliknutí je pokyn
  otevřít aplikaci.
- **Doručuje se i s aplikací vepředu** (`willPresent`). Bez toho macOS notifikaci potlačí,
  jakmile je aplikace aktivní — jenže review trvá minuty a mezitím se v okně dělá něco
  jiného, takže „okno je vidět“ neznamená „dívám se na to, co doběhlo“.
- **Nový výsledek review přepíše ten starý** (#87). Identita je `PR|skupina události`
  (`NotificationEvent.replacementGroup`) a všechny tři výsledky review jsou **jedna skupina** —
  jinak by po opakovaném běhu zůstala vedle „3 nálezy“ viset stará hláška „nenašel žádný nález“,
  tedy tvrzení, které už neplatí. Chytil to test, který původně tvrdil opak. Hláška o novém PR
  má vlastní skupinu: že PR přišel a jak dopadlo jeho review, jsou dvě různé informace.
  **Změna proti #88**, kde byl identifikátor náhodné `UUID`.
- **Cizí aktivita na vlastním PR je vlastní skupina** (#335). Že mi kolega odpověděl a jak dopadl
  reviewer jsou dvě různé věci, takže jedna nemá druhou přebít — a v `NotificationSettings` má
  vlastní přepínač, protože kdo si vypne hlášky o review, o komentáři vědět chce.
- **Vlákno je podle PR** (`threadIdentifier`), ne podle repa: notifikace o témž pull requestu
  patří k sobě, kdežto seskupení po repu by u monorepa slilo věci, které spolu nesouvisí.
- **Souhrn místo N hlášek** (#87): víc nových PR z jednoho tiku dá **jednu** notifikaci
  („3 nové PR k review“), jedno PR dál plnou hlášku s titulkem — „1 nový PR k review“ říká
  **méně** než jeho název. Vypíšou se tři jménem a zbytek se spočítá („a 4 další“), protože
  banner má dva řádky a počet je ta informace, podle které se pozná, jestli jít hned.
- **Žádné čekací okno.** Tik pollingu dodá celý seznam naráz, takže se slévá právě to, co se
  stalo mezi dvěma tiky — a to je ten interval, o kterém má smysl mluvit. Vlastní okno by
  znamenalo stav, zdržení hlášky a druhé místo, kde se rozhoduje, co patří k čemu. Proto se
  slévání testuje **bez čekání v reálném čase**, jak chce zadání #87.
- **Nedoručený souhrn se zkusí znovu jako celek.** Doručení je jedno, takže i výsledek je jeden:
  všechna nová PR zůstanou mimo snímek. Do #87 se zapisovalo po jednotlivých PR, protože se i po
  jednotlivých posílalo.
- **Tři případy výsledku, ne boolean.** „Uživatel to zakázal“ (`notAuthorized`) a „systém to
  nevzal“ (`failed`) vedou jinam: první se dá spravit jedině v Nastavení systému, druhá je
  chyba, u které je co vypsat. Tatáž úvaha jako u `ReviewState`, kde se `clean` nesmí slít
  s `failed`.

`PreflightReport` je jediná pravda o prostředí; `problems` i `toolPaths` se z něj **jen
počítají** — čistě, bez I/O. Tady platí totéž pravidlo jako u `Policy`: když píšeš `if`
nad stavem prostředí ve view, patří to do reportu.

**Streamování je vlastní protokol, ne další metoda `ProcessRunning`.** Fake implementace
`ProcessRunning` jsou u `gh` i `git` v každém druhém testu a metodu, kterou nikdy
nezavolají, by musely dopsat všechny. `workingDirectory` je jen v `ProcessStreaming` —
`claude` pracovní složku flagem předat neumí, kdežto `git` si vystačí s `-C`.

Osm věcí o podprocesech, na které se naráží znovu:

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
- **A vyhladovět ten pool umí i někdo cizí** (#462). Bod výš popisuje případ, kdy si vlákna bere
  `ioQueue` sama; u #462 je vzala **AppKitová animace objevení okna** — `NSAnimation` v threaded
  režimu je `dispatch_async` na globální root frontu, ze které si vlákno drží po celou dobu animace,
  a `Tests/Views/` ukazovalo okno na 48 místech naráz. Projev je **tentýž**: náhodně visící běh
  testů, ve kterém všechny testy prošly, plus `PublishError.timedOut` u suit, které spouštějí `gh`.
  Změřeno: při 80 obsazených vláknech (pool se zastaví na **76**) se práce na privátní souběžné
  frontě dostane na procesor za **28 s** místo 0,0001 s, tedy nad timeoutem `gh`. Opraveno v testech
  (`orderFrontUnanimated`, viz
  [`testovani.md`](testovani.md#zaseknutý-plný-běh-okno-které-se-objeví-s-animací-462)), ne tady —
  aplikace oken tolik neotevírá a paralelismus review drží `WorkCoordinator`. **Zůstává to ale
  slabina**: dokud se výstup čte `readToEnd()`, drží každé volání dvě vlákna sdíleného poolu. Cesta
  ven, kdyby to bylo potřeba, je bufferovat z `readabilityHandler`u jako `SubprocessStreamer`.
- **Oba pipy se musí číst souběžně.** Sériově: než dojde EOF na prvním, druhý naplní buffer
  jádra a proces se zasekne na zápisu.
- **Zrušení musí proces zabít.** Bez toho čekání na EOF drží volání, dokud proces nedoběhne
  sám. Řeší `withTaskCancellationHandler`, u proudu `continuation.onTermination`.
- **A stejně tak ukončení aplikace** (#264). Je to tentýž invariant a **tentýž `SIGKILL`** —
  zavírání jde přes `AppStore.stopReviewsBeforeTermination()`, které běhy jen **zruší**; druhý
  `kill` v delegátovi by byl druhá pravda o tom, jak se běh zastavuje. Co zavírání přidává,
  je **čekání**: zrušení se přenáší přes `WorkCoordinator`, který práci drží ve vlastním tasku,
  takže mezi `cancel()` a odeslaným signálem je několik hopů mezi aktory. Do #264 se nečekalo
  vůbec (nezabíjelo se) a osamocený `claude` se přerodil na `launchd` — změřeno, dvě takové
  session běžely na stroji čtyři dny. Podrobnosti o té cestě jsou v sekci `AppStore`.
- **Co ta záruka nekryje: aplikaci zabitou zvenčí** (#351). Body výš popisují **normální**
  ukončení, tedy cestu, na které se má co spustit. Když aplikace ztuhne a někdo ji zabije
  (`kill -TERM`, Force Quit), nespustí se nic — hlavní vlákno je zaseknuté nebo proces prostě
  zmizí. Řeší to `RunningSessions` níž, tedy **úklid po**, ne prevence.
- **Proud smí skončit teprve po EOF na obou rourách, ne po exitu procesu.** Skončit hned po
  exitu by uřízlo řádky, které ještě leží v rouře — u review přesně ty poslední, ve kterých
  bývají nálezy.
- **Timeout má poslední slovo, i když EOF nedorazí.** Roury může držet něco, co po procesu
  zbylo, a proud by pak čekal navždy. Proto hlídání běží až do konce **proudu** (ruší ho
  `onTermination`, ne konec procesu) a po `SIGKILL`u proud ukončí samo. Data, která po
  konci proudu ještě přijdou, se zahodí a čtení se odpojí — ukecaný potomek by jinak plnil
  buffer, ze kterého už nikdo nečte.

### Osiřelá session po zabité aplikaci (#351)

`RunningSessions` (v `App/Store/`) drží na disku seznam podprocesů, které aplikace právě spustila,
a **při startu zabije ty, které jí nepřežily**. Je to jediná záruka pro případ, na který #264
nedosáhne: aplikace zabitá zvenčí.

**Co se změřilo.** Potomek spuštěný `Foundation.Process`em přežije rodiči `SIGTERM` **i**
`SIGKILL` a jádro ho přerodí na `launchd`:

```
$ ps -o pid,ppid,pgid,etime,comm -p 66365 -p 66367
  PID  PPID  PGID ELAPSED COMM
66365     1 66362   00:14 ./a-parent
66367 66365 66367   00:13 sleep
$ kill -KILL 66365
  PID  PPID  PGID ELAPSED COMM
66367     1 66367   00:22 sleep      # rodič pryč, potomek pod launchd
```

**Prevence na macOS není** a rozhodlo to tři věci, každou změřenou:

- **`PDEATHSIG` v Darwinu neexistuje.** V `sys/spawn.h` je jen `RESETIDS`, `SETPGROUP`,
  `SETSIGDEF`, `SETSIGMASK`, `SETSCHED*`, `SETEXEC`, `START_SUSPENDED`, `SETSID`,
  `CLOEXEC_DEFAULT` a `PCONTROL_*`. Nic o konci rodiče — tedy ani přes `posix_spawn` napřímo,
  natož přes `Foundation.Process`.
- **`PROC_SETPC_TERMINATE` je o něčem jiném.** `libproc.h` u `proc_setpcontrol` píše *„state on
  resource starvation“* a funkce nebere PID: nastavuje chování **volajícího** při hladovění po
  paměti. Se smrtí rodiče nesouvisí.
- **Procesová skupina nepomůže.** `Foundation.Process` dává potomkovi **vlastní** skupinu
  (změřeno výš: `PGID == PID` potomka, kdežto rodič má skupinu shellu), takže signál poslaný
  skupině aplikace na `claude` nedosáhne — a hlavně by ho musel poslat ten, kdo aplikaci zabíjí.

Zbývá tedy **úklid po**: session se zapisují do cache a osiřelé zabije další start. Cena je, že
sirotek žije do dalšího spuštění — což jsou v praxi vteřiny, protože zaseknutá aplikace se zabíjí
právě proto, aby se spustila znovu.

Jak to drží pohromadě:

- **Identita je `(pid, startedAt)`, nikdy jen PID.** Čísla se recyklují, takže PID zapsané před
  hodinou může dneska patřit cizímu procesu — a na stroji běží `claude` i mimo aplikaci
  (uživatelovy vlastní session, paralelní agenti ve slotech). Okamžik vzniku procesu čte
  `sysctl(KERN_PROC_PID)` v mikrosekundách; PID se recykluje, dvojice ne.
- **Hledání v `ps` podle jména nebo promptu je zakázané.** Zabít cizí `claude` je horší než nechat
  běžet sirotka, takže se pozná jedině to, co si aplikace **sama zapsala**.
- **`ProcessInspecting.kill` bere identitu, ne PID.** `SystemProcessInspector` si ji ověří **znovu,
  těsně před signálem**: mezi rozhodnutím a `kill(2)` je čas a v něm se PID může přesunout. Kdyby
  metoda brala PID, závisela by ta kontrola na tom, jestli si na ni volající vzpomněl.
- **Nekladné PID se odmítne dřív, než se na cokoli zeptáme.** `sysctl` na `pid == 0`
  **odpovídá** (jádro), takže bez té pojistky by z nuly vylezla platná identita — a `kill(0, …)`
  míří na celou **procesovou skupinu volajícího**, tedy na aplikaci samotnou.
- **Rozhoduje `size`, ne návratový kód `sysctl`.** Změřeno: pro neexistující PID vrátí `sysctl`
  taky `0`, jen nezapíše nic (`size == 0`) a `errno` nenastaví. Bez té kontroly by nulová
  `kinfo_proc` vypadala jako platná odpověď.
- **Záznam nese i vlastníka**, tedy identitu instance aplikace, která běh spustila — a **sirotek je
  jen ten, jehož vlastník už neběží.** Bez toho by úklid zabíjel session běžící aplikaci pod
  rukama, a naráží na to `xcodebuild test`: testovací host je tentýž bundle, takže má stejné
  `CFBundleName` a sahá do **téže cache** jako aplikace v `/Applications`. Kontrola vlastníka je
  zároveň to, co dovoluje nechat v souboru značky cizí instance a nemazat je.
- **Rozhodnutí je čistá funkce** `Policy.orphanVerdict(for:ownerNow:processNow:)` se třemi
  výsledky — `keep` (živý vlastník), `kill` (vlastník pryč a identita se shoduje), `discard`
  (proces doběhl nebo jeho PID dostal někdo jiný). `RunningSessions` dělá jen I/O.
- **Značku dostává jedině streamovací cesta.** `claude -p` běží minuty a platí se za něj tokeny;
  `gh` a `git` z bufferované cesty doběhnou samy za sekundy a pouštějí se při **každém tiku
  pollingu**, takže zápis do cache by u nich byl sáhnutí na disk za nic. Mechanismus přitom sedí
  v `LaunchedProcess` (jedno místo pro obě cesty) a předává se mu nepovinným parametrem.
- **Zapisuje se hned po `run()`, maže se koncem procesu.** Zápis odložený za `run()` by nechal
  mezeru, do které se vejde ukončení aplikace. Mazání v `terminationHandler`u drží soubor krátký;
  značka, kterou nikdo nemaže, by se úklidem zahodila taky (identita se neshoduje), ale byla by to
  mrtvá váha, která svádí spolehnout se na ni.
- **Bez paměťové cache**, na rozdíl od `InterruptedRuns`: soubor umí psát i druhá instance téhož
  bundlu (testovací host) a cache v paměti by jí značky přepsala. Čte se dvakrát za session, tedy
  ne v tiku ani při každém uložení.
- **Úklid, který nic nezahodil, na soubor vůbec nesáhne.** Je to běžný stav (aplikace se obvykle
  zavírá normálně) a start by za něj platil zápisem i zakládáním složky. Hlavní důvod je ale
  druhý: zápis naprázdno by uměl **přepsat značku, kterou mezi čtením a zápisem zapsala jiná
  instance** — a její sirotek by pak neodešel nikdy. Je na to test se souborem přeformátovaným
  na kompaktní JSON, protože porovnání obsahu by přepis týmž seznamem nechytlo.
- **Nečitelný soubor i selhaný zápis se berou jako prázdno**, stejně jako u `InterruptedRuns`:
  nejhorší následek je neuklizený sirotek, tedy stav před #351. Vyhozená chyba by proti tomu
  položila start aplikace, a tohle je záchranná síť.
- **Úklid běží v `AppDelegate.applicationDidFinishLaunching`**, synchronně a až za delegátem
  notifikací (ten má na pořadí podmínku, tenhle úklid žádnou). V `AppStore` být nemůže: značky
  nestojí na preflightu ani na konfiguraci, takže po pádu, kvůli kterému preflight neprojde, by
  se úklid nespustil vůbec.

**Co #351 nekryje** a je to vědomé: zabíjí se **zapsaný proces, ne jeho potomci.** `claude` si
spouští vlastní pomocné procesy (`bg-pty-host`, `bg-spare`) a ty tam po `SIGKILL`u zůstat mohou —
je to tatáž mezera, jakou má `SIGKILL` z #264, a platí o ní totéž: peníze počítá hlavní proces,
takže jeho zabití zastaví cenu. Rozšířit signál na celou skupinu by znamenalo druhou semantiku
zastavení běhu vedle té z #264.

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
