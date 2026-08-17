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
| `Source` | Zdroj PR: jméno pro UI + search dotaz. Default `Source.reviewRequested` |
| `ReportedFinding` | Nález přesně jak ho poslal reviewer; `FindingVerdict` je `CONFIRMED`/`PLAUSIBLE` |
| `Finding` | `ReportedFinding` + **kdo** ho našel (skill) a **proti čemu** (`headSha`) |
| `FindingKey` | Identita nálezu napříč běhy. Skládá ji **jen** `Policy.key(of:)` |
| `FindingDismissal` | „Tenhle nález neplatí“ — důvod (`invalid`/`irrelevant`) a čas. **Bez volného textu** |
| `RecheckStatus` | Co o nálezu řekla kontrola nových commitů (#150): verdikt (`resolved`/`still-applies`/`unclear`) a věta k němu. **Není nález** a nesmí se za něj vydávat — je to tvrzení *o* nálezu |
| `PullRequestState` | `open` / `draft` / `merged` / `closed` |
| `ReviewState` | Stav review v řádku seznamu — deset případů, viz níž |
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
| `PullRequestFilter`, `PullRequestFilterOptions`, `PullRequestFilterOption`, `ListEmptyReason` | Zúžení seznamu na repa a autory (#117), nabídka hodnot **s počtem PR u každé** (#199) a důvod prázdna. **Není `Codable`** — nepřežije restart |
| `DiffBlock`, `DiffPairBlock` | Souvislý úsek řádků jako jeden text (#157) — kvůli výběru přes víc řádků. **Není `Codable`**, je to věc vykreslení |
| `ReviewDraft` | Rozdělané review: PR, `headSha`, tělo, verdikt, komentáře. Verdikt je vnořený `ReviewDraft.Verdict` |
| `ReviewDraftComment` | Řádkový komentář draftu: kotva (`path` + `DraftAnchor`), tělo, `Origin`. Kotva nese **rozsah** (#110) a komentář **snímek kódu** (#69) |
| `DraftSnapshot` | Text řádků, ke kterým se komentář psal — konec rozsahu a jeho začátek. Prázdný = nevíme |
| `DetailState` | Stav dotažení detailu PR: `loading` / `loaded(PullRequest, updatedAt:)` / `failed`. Je z něj `headSha` pro draft a popis pro `Přehled` |
| `PullRequestTab` | Který tab PR je vidět: `overview` / `filesChanged` / `commits` / `conversation` / `checks` / `findings` / `progress` (#242, `checks` přidalo #215, `commits` #316). **Všech sedm se kreslí vždycky** (#306) — pruh nemá čím měnit počet položek podle dat. `isReviewerOutput` odděluje **výstup našich reviewerů** od toho, co je na PR — z něj se kreslí dělič v pruhu záložek, takže `Kontroly` (#215) i `Commity` (#316) můžou přijít doprostřed levé skupiny, aniž by se posunul. `showsReviewPanel` říká, jestli je v tabu vidět panel s nálezy (#294) — a **s tím prvním se to nesmí slít**: `Kontroly` i `Commity` mají `isReviewerOutput == false` a panel přesto nemají, takže jedna vlastnost pro dvě otázky by posunula dělič. Jako `ReviewVerdict` **není `Codable`** |
| `PullRequestTabBadge` | Odznak u záložky (#242): `count` / `blocking` (červeně) / `live` (puntík). Výčtem, ne strukturou s příznaky — „puntík s počtem“ ani „blokující bez počtu“ význam nemá, takže se nemá dát napsat |
| `ChecksTabState` | Co je v tabu `Kontroly` k vidění (#306): `loading` / `empty` / `list([PullRequestCheck], failure:)` / `failed`. Tab se kreslí i u PR bez CI, takže musí mít odpověď na **každý** stav dat — `empty` znamená „tenhle PR CI nemá“, kdežto `loading` o CI netvrdí nic. Skládá to `Policy.checksTab(checks:failure:)` ze **dvou** map ve store (`checks`, `checkFailures`), jinak by se prázdno slilo s poruchou. Není `Codable` — je to odvozený stav, ne data |
| `PullRequestCommit` | Jeden commit PR (#316): plné `sha`, celá `message`, `authorName` (z gitu, **vždycky je**), `authorLogin` a `avatarURL` (z účtu, **umí být `nil`**), `committedAt` a `isMerge`. `subject` je první řádka zprávy, `shortSha` sedm znaků. Klíčuje se **celým sha**, ne zkráceným — dvě sha se stejnými sedmi znaky by se v `ForEach`i slila potichu. Počet souborů ani `+X −Y` v něm **nejsou**: seznam z GitHubu je nenese a dotahovat je po commitu je N+1 |
| `CommitsTabState` | Co je v tabu `Commity` k vidění (#316): `loading` / `list([PullRequestCommit], failure:)` / `failed`. **Tři stavy, ne čtyři** — `empty` tu chybí schválně: pull request bez commitů neexistuje, takže prázdná odpověď je **porucha**, ne stav PR. Je to obrácená volba než u `ChecksTabState`, kde prázdno odpověď **je**. Skládá to `Policy.commitsTab(commits:failure:)` ze dvou map ve store. Není `Codable` |
| `CommitDiff` | Diff **jednoho commitu** (#317): `sha` a `content` (`loading` / `loaded(Diff)` / `failed`). Sha je **v hodnotě, ne v klíči** — mapa ve store je klíčovaná pull requestem, takže se v okně drží nejvýš jeden diff commitu na PR. Klíč `(PR, sha)` by u PR se stovkou commitů rostl o každý proklik a byly by to megabajty za obrazovky, které nikdo nemá vidět (tatáž úvaha jako u `expandedChecks`). Návratem do seznamu se **nezahazuje**: je to i paměť na to, kde v seznamu člověk byl |
| `CommitDiffTabState`, `CommitDiffEmpty`, `CommitDiffFacts` | Co je vidět po rozkliknutí commitu (#317): `loading` / `diff(Diff)` / `nothing(CommitDiffEmpty)` / `failed`. **Čtvrtý stav je ten podstatný** — diff, který se stáhl a nic v něm není, není porucha ani načítání, takže mu patří věta, ne prázdná plocha; a je to **měřený** případ, ne teoretický (commity z `git commit --allow-empty` vracejí nula bajtů). `CommitDiffEmpty` nese titulek i větu, protože sloučení a prázdný commit mají každý jiné znění. `CommitDiffFacts` je počet souborů (už vyskloňovaný) a `+X −Y` **ze staženého diffu**, tedy bez volání navíc |
| `ReviewPanelTab` | Co je vidět v panelu vpravo: `findings` / `draft` (#242). Jako `PullRequestTab` **není `Codable`** |
| `CommandPalette` | Jmenný prostor palety ⌘K (#184): `Item` (řádek), `Group` (skupina — **pořadí případů je pořadí v okně**), `Target` a `Action` (co se stane po `↵`), `Mark` (co ten řádek je), `Hit` a `Section` (výsledek hledání — `Hit` nese **dva** rozsahy
zvýraznění, jeden nad titulkem a jeden nad podtitulkem), `Jump` (žádost o odscrollování) a `Effect` (co zbývá na okno). **Není `Codable`** — je to obsah jednoho otevření palety. Jmenný prostor proto, že `Palette` v repu už znamená barvy okna |
| `DiffLayout` | Jak se kreslí diff: `unified` (pod sebou) / `split` (vedle sebe). Nastavení **člověka, ne repa** — proto jen v `GlobalConfig` |
| `NotificationEvent` | Co notifikaci vyvolalo: `newPullRequest` / `findings` / `clean` / `failure`. Nese si ji notifikace sama |
| `NotificationSettings` | Co se má hlásit (#86) — hlavní vypínač a čtyři události. Jako `DiffLayout` jen globálně |
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
  `dismissed(findings:)`, `failed(detail:)`, `timedOut(findings:)`, `interrupted(findings:)`,
  `stale`.
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
  je **36 ms** rozvržení v `NSLayoutManager`u a vynucuje si ho `layoutColumns()` přes `sizeToFit()`,
  protože z něj čte přirozenou šířku sloupce pro vodorovný posun. **Vyhodit `sizeToFit()` cenu
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

Osm pastí AppKitu a SwiftUI, které to stálo — všechny **změřené**, ne přečtené:

| Past | Jak se projevila |
|---|---|
| **Co se nakreslí po `super.draw`, není vidět** | Čísla a znaky se nekreslily vůbec, ačkoli se kód volal se správnými hodnotami. Doloženo plným obdélníkem, který taky nebyl. Všechno vlastní kreslení musí být **před** `super.draw` |
| `NSAttributedString.draw(at:)` ve **flipped** view kreslí **nad** bod | Text mimo řádek a mimo view. Musí to být `draw(in:)` s rámečkem a zarovnáním z odstavce |
| `setAttributedString` **ruší výběr** | `updateNSView` chodí i při přejezdu myší (mění se, u kterého řádku svítí pilulka), takže výběr zmizel při každém hnutí. Text se proto skládá jen při změně **podpisu** obsahu |
| SwiftUI `@ViewBuilder`, který podle stavu vybírá mezi `self` a modifikátorem, **mění strukturu** | `copyMenu` s prázdnou nabídkou zahodil podstrom a postavil nový `NSTextView` — s ním zmizel výběr, jak myš odjela z bloku. Menu se proto připojuje bezpodmínečně |
| `NSCursor.set()` ze SwiftUI ani `addCursorRect` si proti `NSTextView` **neporadí** | Ruka nad pilulkou blikla jen v rohu, kde se to potkalo, nebo vůbec. Jde to jen přes tracking area a `cursorUpdate` — a i tam se musí rozhodovat v `mouseMoved`, protože `cursorUpdate` chodí jen při vstupu do areay |
| `contentShape` **před** `frame` tvaruje nulovou velikost | Gesto tažení nemělo kde začít. Vypadá to jako drobnost v pořadí modifikátorů a je z toho nefunkční gesto |
| `NSTextView` s neomezenou šířkou si **nedopočítá rámec** | Po přesunu do `NSScrollView` zůstal nulový: nic vidět, nic vybrat |
| Nastavení `textContainer.size` si AppKit vyloží jako změnu geometrie a **sám zavolá `setFrameSize`** | Měření výšky je dotaz na **budoucí** šířku, takže mu ten zpětný hovor změřenou šířku hned přepsal tou současnou — a měřilo se o jednu šířku pozadu (blok o dvou dlouhých řádcích si při 300 pt řekl o 36 pt a nakreslil 162). Řeší to stráž `isMeasuring` a to, že se šířka kontejneru nastavuje jen při změně (#236) |

**TextKit 1, ne 2.** Geometrie řádků se čte z `NSLayoutManager` (`boundingRect(forGlyphRange:)`) —
podle ní se kreslí pozadí, čísla i pozice pilulek — a TextKit 2 layout manager nemá. Vynutí se tím,
že se textové view vyrobí s ručně složeným `NSTextStorage`/`NSLayoutManager`/`NSTextContainer`.

**V diffu se `DiffLineView` a `DiffPairView` už nekreslí** (bloky je nahradily), ale drží
konstanty a barvy, které si bloky berou (`numberColumn`, `iconColumn`, `signColumn`,
`contentInset(for:)`, `signColor(of:)`, `background(of:)`, `rangeTint`, `dragTint`). Zůstávají
proto jako **jediné místo, kde ty hodnoty jsou** — vyčlenit je do vlastního typu je úklid na potom,
ne součást #157.

Jeden čtenář `DiffLineView` ale přibyl: **úryvek kódu u vlákna** (`ThreadSnippetView`, #216) kreslí
řádky jím, takže barvy z něj jsou vidět i mimo diff. `DiffPairView` čtenáře nemá žádného — každou
dvojici slévá `DiffRow.blockedPairs(_:)` do `pairBlock`u, takže případ `.pair` do `DiffRowView`
nedojde. Drží se dál kvůli konstantám a proto, že je to jediný popis toho, jak dvojice vypadá bez
bloku; když se v něm něco mění (jako barvy u #277), mění se to **spolu s blokem**, aby se ty dvě
cesty nerozešly.

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
| `GlobalConfig` | `sources`, `skills`, `skillsByLanguage`, `reviewPrompt`, `reviewTimeoutMinutes`, `blockingCategories`, `mode`, `allowsPublishing`, `findingsLanguage`, `diffLayout`, `appearance`, `notifications`, interval, souběh, `autoRunsPerDay`, rozpočet, model |
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
| `StreamSummary` | Session id, nálezy, **pokusy** o nástroje a odmítnuté nástroje, konec běhu, **cena běhu**, počty nepřečteného |
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
- **Cena běhu je `nil`, ne nula** (#148). `total_cost_usd`, `duration_ms` a `num_turns` jsou
  v tomtéž `result` eventu jako `outcome`, takže je zabitý běh nemá — a nula by tvrdila, že byl
  zdarma. Čte se to stejně defenzivně jako číslo řádku: `true` je `NSNumber`, takže by bez
  kontroly vyšla cena 1 $, a **záporná hodnota se zahazuje**, protože by v denním součtu
  tvrdila, že mě běh vydělal.

## `ReviewRunner` (`App/Review/`)

Jeden běh = jedna headless session `claude` na jeden skill v jednom pracovním stromě.

| Typ | Co je |
|---|---|
| `ReviewRunning` | Protokol: `run(_:progress:)`. Schválně nemá nic, čím by šlo něco odeslat |
| `ClaudeReviewRunner` | Implementace nad `claude` přes `ProcessStreaming` |
| `ReviewRequest` | Zadání: klíč, pracovní strom, `baseSha` (proti čemu diffovat), `promptTemplate` z nastavení (#281), `timeout` z nastavení (#320); u kontroly nálezů (#150) navíc `recheck: RecheckMaterial?` |
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
záznamy zastaralými → worktree → skilly paralelně → každý doběhlý uložit do `ReviewStore`.
Limit souběžných session hlídá `ReviewRunner`, ne tenhle kód.

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
| `AppStore+DiffExpansion.swift` | Rozbalování kontextu mimo hunky (#47), od #317 i v diffu commitu | 139 |
| `AppStore+DraftTransfer.swift` | Přenesení draftu na nový commit (#69) | 103 |
| `AppStore+Diff.swift` | Načtení diffu, pohled a sbalování souborů | 95 |
| `AppStore+IncrementalDiff.swift` | Diff „co od minule přibylo“ (#284) — nabídnout, načíst, zavřít | 87 |
| `AppStore+Automatic.swift` | Automatický režim a denní rozpočet (#25) | 89 |
| `AppStore+Findings.swift` | Zahození záznamu (#81) a odmítnutí nálezu (#113) | 70 |
| `AppStore+Appearance.swift` | Přepnutí vzhledu okna z railu (#278) | 26 |
| `AppStore+Detail.swift` | Detail PR a jeho záložky | 59 |
| `AppStore+Commits.swift` | Commity PR do tabu `Commity` (#316) | 37 |
| `AppStore+CommitDiff.swift` | Rozkliknutý commit a jeho diff (#317) | 80 |

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
- **Zapsat filtr jde jedině `setFilter(_:)`**, protože se s ním musí srovnat výběr: vybraný PR mimo
  filtr výběr **ztrácí** (detail PR, který v seznamu není, se nedá zavřít ani znovu vybrat).
  Nic se tím neztrácí — draft leží na disku a běžící review běží dál. Ruší se to **jen tam**, ne
  pokaždé, když vybraný PR ze seznamu vypadne: PR, které z fronty odešlo tikem, si výběr drží
  (dnešní chování, mergnutý PR jde ještě dočíst).
- **Automat filtr neřeší.** Review na schovaném repu se dál plánuje; vypnout ho jde `mode: manual`
  per repo. Kdyby to filtr vypínal, slil by se pohled s nastavením a stav „schoval jsem si to, tak
  se to nereviewuje“ by nebyl kde ukázat.
- **Klik na notifikaci PR, které filtr schoval, filtr vymaže** — rozhodnuto u #117, v zadání to
  nebylo. Kliknutí je výslovná žádost ten PR vidět, takže mlčení by bylo nejhorší; a vybrat ho
  a filtr nechat je ještě horší, protože `ContentView` hledá detail ve **viditelném** seznamu, takže
  by se nenakreslil a vypadalo by to, že klik nic neudělal. Že filtr zmizel, je vidět v liště.
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
  negativní: výčet sekcí je pořád tříprvkový a v paletě není položka se slovem „vzhled“.

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
| `FullSizeContentWindow` | Roztažení obsahu pod titulkovou lištu, aby hlavička mohla být vlastní (#180) — a od #245 **vypnutí systémových záložek oken** (`tabbingMode = .disallowed`), aby se `⌃Tab` nepřetahoval s AppKitem |
| `AppAppearance`, `AppearanceApplying` | Přepnutí vzhledu celé aplikace (#278) — `NSApp.appearance`, a za protokolem, aby si na hostitele testů nesáhly testy |
| `Palette` | Barvy okna z návrhu, světlá i tmavá varianta — **jeden zdroj pro celou aplikaci** (#180). Krytí je u tichých podkladů (`accentWeak`) v každém režimu jiné, jak to má návrh. Stavové tóny `ok`, `find`, `crit` (#218) jsou pro odznaky a puntíky **a od #277 i pro diff**: `DiffLineView.signColor(of:)` zůstává jediným zdrojem zelené a červené v diffu (aby se `+` v řádku nerozešlo s `+12` nad ním, #156), jen si ji bere odsud, ne ze systému; pozadí řádků má vlastní vyčíslené tokeny (`diffAdded`, `diffRemoved`, `diffAddedWord`, `diffRemovedWord`, `diffMissingStripe`) — viz *Barvy diffu* v sekci `App/Diff/`. Od #279 k tomu tři tóny výstrah (`alertNote`, `alertWarning`, `alertCaution` — `[!TIP]` a `[!IMPORTANT]` si půjčují `ok` a `accent`) a `codeFill` pod kód; `alertWarning` a `alertCaution` jsou **vlastní hex schválně**, protože ty GitHubovy se na hex rovnají `stale` a `crit`. Od #309 `mint` — **dvojice k akcentu**: akcent je to, co se nabízí udělat nebo co běží, mint to, co se jen konstatuje (`2×`, `✓ v mém review`, `odmítnuto`). Světlá větev je **vědomá odchylka od návrhu** (`#0E8F80` → `#0C7E71`), protože hodnota z mockupu byla jediný stavový token pod AA — čísla u `Palette.mint` a v `MintTokenTests` |
| `ReviewTabsView` | Pruh záložek v hlavičce: domů, otevřená review s tečkou stavu a křížkem (#180). Nápověda u **domácí** záložky nese zkratky pruhu `⌃Tab` / `⌃⇧Tab` (#245) — na `ScrollView`u se `.help` neprojeví |
| `SidebarRail` | Svislý rail vlevo — `Přehled`, `Fronta` s odznakem, `Rozdělaná` (#180) a pod oddělovačem **cyklící přepínač vzhledu okna** (#278), který sekce railu není |
| `HomeView` | Obsah domácí záložky podle railu. Nad dashboardem **bez toolbaru** — hlavičku si kreslí sám (#181) |
| `DashboardView` | Startovní obrazovka (#181): pozdrav, čtyři karty, fronta podle závažnosti, legenda reviewerů a `Co teď` |
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
| `DiffBlockSignature` | Podpis bloku, podle kterého se text **znovu nesází** (#157) — a v němž je schválně barevný režim (#278), protože barvy jsou v tom textu zapečené |
| `DiffGutterGeometry`, `DiffBlockPlacement` | Aritmetika gutteru (#252) — kde leží plochy na tažení a pilulka, a poloha bloku v prostoru obsahu **mimo observable stav**. Čistý typ, aby se dal změřit i otestovat bez okna |
| `CodeText`, `CodeTextSheet`, `SelectableCodeView` | Hunk jako jeden text mimo diff (#157) — vybrat jde i přes bubliny |
| `PullRequestListView` | Seznam, prázdný stav, úvodní loading, tlačítko obnovit (⌘R) |
| `PullRequestFilterButton` | Filtr seznamu v toolbaru (#117) — ikona se stavem a počtem schovaných, popover s odškrtávátky a **počtem PR u každé položky** (#199) |
| `PullRequestTabBar` | Záložky PR (`Přehled` / `Změněné soubory` / `Commity` / `Konverzace` / `Kontroly` ‖ `Nálezy` / `Průběh`) — podtržené, s odznakem **u každé** (#218; typy od #242), děličem před výstupem reviewerů a vpravo `+X −Y` se čtverečky poměru. **Kreslí `PullRequestTab.allCases` a nedá se to zvenku nastavit** (#306): do #306 byl seznam parametrem, protože `Kontroly` u PR bez CI odpadly — a pruh se tím při každém otevření PR přeskládal z pěti na šest. Zmizení parametru je ta podstatná část opravy; dokud existoval, dal se počet záložek znovu udělat funkcí dat. Od #316 má **tři podoby** (`ViewThatFits`, `Layout`): s popisky a `+X −Y`, s popisky bez ní a od #318 **ikony s odznaky a popiskem jen u aktivní** — díky té třetí se pruh nezalomí ani v nejužším povoleném okně. Viz *Pruh záložek — tři podoby podle šířky* |
| `StaleNoticeView` | Okrová věta „tohle je poslední známý stav“ nad seznamem, který se nepovedlo načíst **znovu** — jedno místo pro `Kontroly` (#215) i `Commity` (#316). Sedí **nad `ScrollView`em**, aby neodscrollovala pryč od obsahu, o kterém mluví |
| `CommitListView` | Seznam commitů v tabu `Commity` (#316): pruh s počtem a hlavou, řádek na commit (obrázek autora, první řádka zprávy, jméno, relativní čas, sha) a pilulky `sloučení` a `hlava`. `content` je `internal` kvůli měření přesahu — `NSScrollView` by přesah ukrojil |
| `CommitDiffView` | Diff jednoho commitu (#317) — hlavička a pod ní `DiffView`. **Nedostane `AppStore` ani identifikátor PR**, takže nemá čím vyrobit bublinu nálezu ani rozdělaný komentář; `reading(_:)` je `internal` kvůli testu, který tvrdí právě to, co `DiffView` **nedostane** |
| `CommitHeaderView` | Hlavička rozkliknutého commitu (`.chead`, #317): cesta zpět s pozicí, zpráva i její tělo, kapsle se sha (kliknutím se kopíruje), odkaz na GitHub, autor, čas, počet souborů a `+X −Y`, a tichá věta „Jen ke čtení…“ s odkazem do `Změněných souborů`. Řádek meta se v úzkém okně zalomí přes `ViewThatFits` — `.chead .meta` má v CSS `flex-wrap`, který SwiftUI nemá |
| `OverviewView` | Tab `Přehled`, odshora **co se změnilo od minule → fakta → popis PR** (#280; kontroly mají od #215 vlastní tab). Obsah je v `content` **mimo `ScrollView`** a `internal` schválně — přes `body` se šířka změřit nedá, viz #291 |
| `SinceLastVisitView` | Pruh „co se změnilo od minule“ nahoře v `Přehledu` (#173, sazba #226 a #284) — odrážky po částech a pod nimi odznak `nálezy zastaraly` s tlačítky `Pustit review znovu` a `Ukázat, co přibylo` |
| `SinceLastVisitLine`, `SinceLastVisitLines` | Odrážka po typovaných částech a jejich skládání (#284). Mimo view a testovatelné, jako `TimelineEventRow` |
| `IncrementalDiffBar` | Lišta nad rozsahovým diffem (#284) — rozsah dvěma sha a cesta zpátky na celý diff. Podobu vybírá **spočítaná** šířka, ne `ViewThatFits` |
| `TextWidth` | Šířka popisku ve skutečném písmu (#284) — z ní se rozhoduje, jestli se řada vejde. Řez si bere z `MiniButtonStyle.labelFont`, aby se měření a kresba nemohly rozejít |
| `ConversationView` | Tab `Konverzace` (#183): lišta s filtrem, časová osa a **composer komentáře pod PR** na spodní hraně (#216) |
| `ConversationNodeView` | Jeden uzel osy — puntík 24 bodů, svislá linka a obsah vpravo; slévá za sebou jdoucí commity |
| `ConversationEntryView` | Položka osy: karta cizího review nebo komentáře, řádek události, vlákno bez kotvy |
| `ConversationComposerView`, `ConversationComposer` | Psaní komentáře pod PR (#216) a akce k němu |
| `TimelineEventRow` | Událost převedená na řádek — symbol, věta **s tučnými jmény**, barva uzlu (`tint: Color?`), sha po jednom (#171, sazba #216). Mimo view a testovatelné, jako `FindingRow` |
| `AvatarView`, `AvatarLoader` | Obrázek uživatele u události a jeho cache nad `HTTPGetting` (#171) |
| `PullRequestRow` | Repo + číslo + `draft` chip, titulek, autor a relativní čas, odznak stavu, ikona rozdělaného review |
| `PollStatusBanner` | Pruh nad seznamem — **jen když data nejsou čerstvá** |
| `PullRequestDetailView` | Pravý panel: hlavička ve třech řádcích (titulek s číslem, souřadnice PR, pruh běhu), pod ní záložky, diff a nálezy. **Bez pravého sloupce** (#218) — zbylo v něm jediné akcentové místo, `Spustit review` |
| `PullRequestHeaderView` | Souřadnice PR: kapsle stavu (plná, s puntíkem), autor, větev → base, repo, souhrn checků a odkaz na GitHub. `StaleHeadView` vedle něj mluví jen tehdy, když se hlava rozešla se sha nálezů |
| `ReviewRunbarView` | Pruh běhu (#218): chipy reviewerů, za nimi dráha průběhu a popisek `test-coverage · 2 z 3 hotovo · 1:12`. Bez běhu zbude jen řada chipů |
| `DiffView` | Diff v plné šířce: lišta, strom vlevo a soubory s ukotvenou hlavičkou, kterou jde sbalit |
| `DiffToolbar` | Lišta nad diffem (#219): pohled, procházení nálezů, varování a `Rozbalit vše` s nabídkou. **Bez přepínačů sloupců** — ty se skládají u sebe |
| `DiffLayoutPicker` | Přepínač pohledu — segment **s popisky** podle návrhu (`.segbtn`), ne `Picker(.segmented)` |
| `DiffFileHeaderView`, `FilePathText` | Hlavička souboru (`.fhead`): celá cesta se **složkou tlumeně a jménem tučně**, odznak změny, kapsle s počtem nálezů, `+X −Y` |
| `DiffRowView` | Jeden řádek diffu — hlavička hunku, řádek, dvojice, rozbalovací řádek nebo poznámka |
| `DiffPairView` | Dvojice vedle sebe: dvě buňky `DiffLineView` se `side`, pozadí za celou dvojici, prázdná protistrana |
| `RangeDragActions`, `DiffRowFrames` | Tažení rozsahu komentáře (#110) — akce a rámečky řádků **mimo observable stav** |
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
| `DraftTextEditor` | Textové pole draftu — odložený zápis a doručení při zmizení |
| `DraftPanel` | Tab `Moje review`: banner zastarání, verdikt **předvyplněný návrhem z nálezů** (obtažený, s popiskem), tělo, seznam komentářů, `Odeslat review…` (u zastaralého `Zkontrolovat a odeslat…`). Obsah scrolluje, jen když se nevejde |
| `ReviewSubmissionSheet` | Potvrzení odeslání: **kontrola kotev u zastaralého draftu** (#69), pak úplný výpis payloadu, průběh, typované chyby |
| `DraftTransferView` | První stránka toho potvrzení: stav každé kotvy (sedí / posunulo se / nevím / ztraceno) a volba, co s ní |
| `VerdictAppearance` | Ikona a barva verdiktu — jedno místo pro panel i pro potvrzení. `Komentář` bere od #309 `Palette.accent` (verdikt je volba, tedy akce); `.green`/`.red` zůstávají systémové vědomě — převod celé škály je jiná otázka a jinde v `App/` se zelená a červená berou ze systému na desítkách míst |
| `DraftActions`, `FileDraftActions` | Co se dá s draftem dělat; druhé svázané s jedním souborem diffu |
| `DiffLineView` | Řádek souboru: dvě čísla (v buňce dvojice jedno, podle `side`), znak změny, obsah obarvený podle jazyka, tlačítko na komentář (na hover) |
| `ReviewPanel` | Panel **napravo od diffu** (#182, do #242 `FindingsPanel`): segmenty `Nálezy`/`Moje review`, karty nálezů, prokliky do diffu — a složení na proužek s počtem nálezů a značkou rozdělaného review. `Průběh` a zahození nálezů se u #242 odstěhovaly do záložek PR. **Kreslí se jen ve třech tabech** (#294, `PullRequestTab.showsReviewPanel`) — sám o tom nerozhoduje, podmínku má detail |
| `DismissedRowStyle` | Buňka tabulky: ztlumení odmítnutého řádku a kontextové menu `Označit jako…` / `Vrátit` |
| `FindingRow` | Nález převedený na řádek tabulky — texty (včetně nápovědy k místu), identita, blokující příznak, odmítnutí |
| `FindingHighlight` | Místo, na které se právě skočilo; bublina na něm chvíli svítí |
| `ReviewProgressView`, `ReviewerLaneView` | Tab `Průběh` (#242, nahradily `ReviewTimelineView`): **dráha na revieweera** s fázemi vedle sebe, věta o tom, co se právě děje, u spadlé session důvod, `stderr` a `Pustit znovu` / `Zkopírovat příkaz`; podrobný výpis událostí pod rozbalením (`TimelineEntryRow`). Dráha po skillu **mimo nastavenou sadu** nese v hlavičce `mimo sadu`; prázdný stav mluví o **nastavení**, protože se do něj dá dojít jedině s prázdnou sadou skillů |
| `ReviewerLaneText` | České věty dráhy — stav, co se právě děje, čím to skončilo. Rozlišuje **tři** doběhlé stavy: nahlásilo nálezy / nahlásilo nulu / nenahlásilo nic — a `nespuštěno` od `ve frontě` |
| `FindingsTabView`, `FindingsEmptyView` | Tab `Nálezy` (#242): souhrn počtů, `Zahodit nálezy`, tabulka — a věta, **proč** je prázdno (`Policy.findingsEmptyReason`), společná s panelem |
| `FindingsTableView`, `FindingTableRowView`, `FindingTableRow` | Tabulka nálezů přes celou šířku: řazení kliknutím na hlavičku, řádek na **místo** (shoda dvou reviewerů je odznak `2×`), rozbalení kreslí tutéž `FindingBubbleView` jako diff. Akce (`Převzít`, `Vrátit`) jsou **barevný text z palety** (`AccentLinkButtonStyle`, #298), ne plocha jako v bublině a ne systémová modrá; krytí odmítnutého řádku drží `dismissedOpacity` (`.frow.done` z návrhu), ze kterého měří i sonda kontrastu |
| `ReviewerChipsView` | Chipy reviewerů: **puntík, zkrácené jméno a počet** (#218); stav a filtr naráz, v kontextovém menu opakování jednoho revieweera (#149) |
| `FileTreeView` | Strom souborů v levém sloupci u diffu; odsazení a sbalování si řídí sám |
| `ReviewStateBadge` | Odznak stavu review; texty podle specifikace |
| `hiddenShortcuts(_:)`, `KeyEquivalent.backTab` | Klávesové zkratky bez viditelného tlačítka (#151) — jedno místo pro detail PR, nastavení, okno novinek, paletu i přepínání záložek (#245). `backTab` je tam proto, že `⌃⇧⇥` doručí `U+0019`, tedy jinou klávesu než `⇥` |
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

### Command palette ⌘K (#184)

Jediná obrazovka aplikace, která nemá předobraz v ničem starším: jedno pole nad **nálezy,
soubory otevřeného PR, pull requesty a akcemi**. Rozdělená je na tři kusy a hranice mezi nimi je
to podstatné:

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
- **Kreslená zkratka musí být skutečná.** V paletě jsou dvě (`⌘2`, `⌘,`). Návrh má u „pustit
  review“ `⌘⇧R`, ale ta v aplikaci pouští review na **všechno, co neběželo** (dashboard) —
  nakreslit ji tady by byla lež o tom, co okno umí.
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

**Co zatím pružné zůstalo:** poloviny v `DiffPairView`. `maxWidth: .infinity` tam drží **stejně
široké sloupce**, takže `filling()` by každé polovině dalo plnou šířku a rozvržení by se rozsypalo.
Potřebuje to krok „poloviční šířka“ a je to samostatná práce.

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

### Pruh záložek — tři podoby podle šířky (#316, #318)

`PullRequestTabBar` je jediné místo v okně, kde se o podobě rozhoduje **`ViewThatFits`em**, a ne
spočítanou šířkou. Kandidáti jsou tři a jmenují se `Layout`; bere se **první, který se vejde**,
takže pořadí je to, co říká, co ustupuje dřív:

| Podoba | Co kreslí | Ideální šířka tabu | Okno (+ rail 53) |
|---|---|---|---|
| `full` | popisky u všech záložek a vpravo `+X −Y` | 996–998 b | 1049–1051 b |
| `labels` | popisky, bez `+X −Y` (#316) | 886–888 b | 939–941 b |
| `icons` | ikony s odznaky, popisek jen u aktivní (#318) | 498–564 b | 551–617 b |

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
- **Čtvrtá podoba (samotné ikony) tu není, a je to podložené měřením.** `icons` se s nejdelším
  popiskem vejde do tabu od 564 b (okno 617), a i s trojmístnými odznaky u všech záložek od 636 b
  (okno 689) — pod podlahu okna (700). Na čtvrtou podobu se tedy nedá přijít; kód, který nikdo
  neuvidí, je horší než měření, které to hlídá (`TabStripWidthTests`).
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
  (změřeno **22,6 ms → 1,40 ms**). Pořadí je **napřed úklid, potom zápis**: obráceně by blok vyklidil
  sám sebe, protože leží celý ve své ploše. Prázdná plocha se ignoruje — blok, který se ještě
  nerozložil, hlásí nulový rámeček a vyklidil by cizí záznamy na souřadnici nula.
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
    scroller objeví až po skoku, viewport se o jeho 13 bodů zmenší a okýnko zůstane o řádek nad
    koncem. Chyceno plným během testů pod zátěží (samostatně to vycházelo).

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
    a scrolluje uvnitř. Rezerva na vodorovný scroller je opsané číslo (13 bodů), protože
    `NSScroller.scrollerWidth` je vázaná na hlavní vlákno — **drží ji test**, který ji porovnává se
    systémem, ne odhad. Na `preferredScrollerStyle` se schválně neptáme: mění se připojením myši,
    a okýnko, kterému se tím mění výška, je horší než pár bodů rezervy.
  - **Strop výšky je 441 bodů, tedy přesně 30 řádků** (#303; do té doby 320 bodů = 21 řádků). Zvednuto
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

    Strop je vždycky **celý počet řádků** (`14N + 21`), protože okýnko se otevírá na konci logu —
    půlka řádku na spodní hraně by byla zrovna na tom řádku, kvůli kterému se log otevírá. Drží to
    test, ne komentář.
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
    7,9 ms. `.log` žádný jazyk nemá, takže tudy chodí každý log — a sheetu s kódem to pomůže
    u souborů, které `Language` nezná.
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
- **Na vlastním PR se návrh nenabídne** (`isOwnPullRequest`, autor z detailu proti
  `Conversation.viewer`). GitHub tam bere jedině `COMMENT` (změřeno u #62), takže by předvyplněný
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
  - **Uložená osa svůj konec neobsahuje, takže se doplňuje z běhu** (`ReviewerTimeline.completeTail(from:)`,
    #242). Snímek pro zápis se v `runSkills` bere dřív, než proud událostí dojede, takže v souboru
    chybí `hlásí nálezy` i `doběhlo` — **změřeno na skutečné cache: 7 ze 7 os po skutečném běhu**
    (osy vyrobené v testech konec mají, proto to testy nechytily). Bez doplnění tvrdil tab `Průběh`
    po restartu `nedoběhlo — běh někdo zrušil` nad doběhlým review a `nálezy vůbec nenahlásilo` nad
    tím, které nahlásilo prázdný seznam; chip vedle toho ukazoval `čisto`. Doplňuje se **jen to, co
    běh sám ví** (jeho výsledek a jeho počet nálezů včetně nepřečtených), jen když to v ose není,
    a **nikdy do prázdné osy** — jinak by z chybějícího průběhu vznikl vymyšlený. Běh, který
    `ReportFindings` nezavolal, doplněnou fázi hlášení nedostane: to je vlastní stav a slít se nesmí.
    Opravuje se to na **čtení**, ne v zápisu, protože stejně tak vypadají všechny už uložené
    soubory; zápis by se musel synchronizovat s proudem, a to je continuation navíc v cestě, která
    se ruší.
  - **Živá osa přebíjí uloženou.** Běžící review si ji drží v paměti, kdežto uložená patří
    předchozímu běhu; ověřeno vloženou regresí (spadne sedm testů).
  - **Ořezává se začátek, ne konec**, a strop je 300 událostí: kdo se do osy dívá po restartu,
    hledá, čím to skončilo. Kolik se ořízlo, se **sčítá mezi uloženími** a je to v hlavičce
    vidět — tiché zkrácení je tatáž past jako `droppedFindings`.
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
- **Klik na PR mimo seznam výběr nemění.** Notifikace přežije tik, který PR odklidil, a vybrat
  neexistující řádek nejde; skočit místo toho jinam by bylo horší než nechat na obrazovce to,
  co tam bylo. Okno je vepředu tak jako tak, takže kliknutí nezůstane bez odpovědi.
- **Dokud se seznam nenačetl (`status == .notStarted`), vybere se i tak.** Je to zrovna ten
  případ, kvůli kterému má proud kliknutí buffer: aplikaci spustilo právě to kliknutí, takže
  polling ještě neproběhl a **prázdný seznam neznamená „PR je zavřený“, ale „ještě nevím“**.
  Bez toho by se klik z notifikace, která aplikaci spustila, zahodil — tedy přesně ten scénář,
  pro který je celý buffer. Chytila to vlastní revize diffu u #88; detail se dokreslí, jakmile
  první tik dorazí.
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

**Kdy se zeptáme znovu, zapisuje smyčka** (`nextPoll`, #181), ne odhad ve view. Dashboard to
píše v hlavičce a `lastSuccess + interval` by po prvním rate limitu lhalo — o čekání rozhoduje
`waitBeforeNextPoll()`, tedy backoff. Ruční obnovení hodnotu **neposouvá**: tik mimo pořadí
smyčku nepřeplánuje, takže dokud poprvé neusne, je `nil`.

**Po dobu dotazu je `nextPoll` v minulosti** — zapisuje se až za `refresh()`. Od #237 je v tom
koutě odpočet (`za 43s znovu`), takže to přestala být kosmetika: odpočet by došel na nulu a šel
dál. Drží to `PollState.isRefreshing`, které `refresh()` zvedne na začátku a v `defer` zase
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
| `ReviewRecord.activeFindings`, `.dismissal(of:)`, `.setDismissal(_:of:)` | Odmítnuté nálezy (#113) — čtení i zápis na jednom místě |
| `Policy.suggestedVerdict(for:)` | Návrh verdiktu nad `ReviewRecord`. `nil` = není z čeho soudit |
| `Policy.effectiveVerdict(of:suggestion:)` | Který verdikt **platí** a odkud je — moje volba, jinak návrh (#114) |
| `Policy.prefillableSuggestion(_:author:viewer:)`, `Policy.isOwn(author:viewer:)` | Smí se návrhem předvyplnit? Na vlastním PR ne |
| `Policy.groups(of:)` | Shoda reviewerů na `file:line` → `FindingGroup` s odznakem `2×` |
| `Policy.disclosure(of:categories:toggled:)`, `Policy.disclosureKey(of:)` | Jak je nález u kódu rozbalený (#185): blokující rozbalený, ostatní značka, odmítnutý nikdy — a čím se místo klíčuje |
| `Policy.chips(for:skills:running:)` | Stav reviewerů pro horní lištu — `ReviewerChip` i s **cenou** z uloženého běhu |
| `Policy.projectLanguages(in:)` | Odhad jazyka projektu z výpisu verzovaných souborů |
| `Policy.reviewPromptTemplate(from:)`, `.reviewPromptProblems(in:)`, `.reviewPromptBody(template:skillID:baseSha:)`, `.reviewPrompt(template:skillID:baseSha:)` | Prompt review ze šablony v nastavení (#281, `ReviewPromptTemplate`): prázdná šablona → výchozí, chybějící zástupný text → `Problem`, dosazení hodnot a **vždycky připojené jádro**. Skládá to **jedno místo**, protože týž text potřebuje běh i `Zkopírovat příkaz` |
| `Policy.reviewTimeout(minutes:)`, `.reviewTimeoutMinutes(from:)`, `.reviewTimeoutProblem(in:)` | Časový limit běhu z nastavení (#320, `ReviewTimeout`): sražení do mezí 5–60 min a pojmenování hodnoty, která je mimo ně. **Jediné místo, kde se sráží** — pole v nastavení, globální hodnota i override per repo mluví o týchž mezích |
| `Policy.automaticallyReviewable(...)` | Které PR má automat spustit — bez rozpočtu, ten je stavový |
| `Policy.sorted(_:)`, `Policy.sections(_:)` | Pořadí nálezů pro UI a jejich rozdělení po kategoriích |
| `Policy.matches(_:_:)` | Patří vlákno (nebo můj rozdělaný komentář) k tomuhle řádku diffu — **jedno místo** pro výběr i umístění |
| `Policy.inserting(_:intoThread:of:)`, `Policy.applying(_:to:)` | Zápis odeslané odpovědi a vyřešení do načtené konverzace; `nil` = vlákno tam není |
| `Policy.linesWithSeveralComments(in:)` | Na kolika řádcích draftu je víc komentářů — z každého budou samostatná vlákna, ne odpověď |
| `Policy.overview(of:renderedIn:)` | Co patří do tabu `Přehled`: review, komentáře pod PR, vlákna bez kotvy a **události časové osy** (#171), chronologicky (`ConversationEntry`) |
| `Policy.displayableEvents(_:)` | Které události se kreslí — zavření po mergi zahodí, zbytek nechá (#171) |
| `Policy.filtered(_:by:)`, `Policy.filterOptions(in:filter:)`, `Policy.listEmptyReason(poll:visible:hidden:)` | Filtr seznamu PR (#117): zúžení, nabídka hodnot sjednocená s aktivním filtrem — **s počtem PR u každé položky** (#199), počítaným z plného seznamu, takže zapnutý filtr čísly nehne — a důvod prázdna, ve kterém **chyba načtení vyhrává nad filtrem** |
| `Policy.summary(of:records:drafts:categories:)` | Souhrn fronty (#155) — počítá **PR, ne nálezy**, a blokující bere z `blockingCount`, tedy bez odmítnutých |
| `Policy.blockingCount(in:categories:)` | Kolik **platných** nálezů záznamu blokuje. Bydlí u `isBlocking`, protože se na to ptají dvě místa — notifikace a řádek seznamu |
| `Policy.mostSevereFinding(in:categories:)` | Nález, kterým se začíná (#200) — první ze `sorted`, tedy ten nahoře v panelu. Vlastní škála závažnosti z toho nevzniká |
| `Policy.queueRow(for:categories:)` | Odvozená čísla pro řádek seznamu (#172): kolik blokuje a jak se nálezy rozdělily mezi reviewery (`QueueRow`, `ReviewerShare`) |
| `Policy.dashboard(pullRequests:records:drafts:categories:since:)` | Podklad startovní obrazovky (#181): čtyři karty a rozpad nálezů podle revieweera (`Dashboard`, `ReviewerShareOfFindings`) |
| `Policy.byUrgency(_:)`, `Policy.urgency(of:)` | Pořadí fronty na dashboardu (#181) — podle závažnosti, ne podle času (`QueueEntry`) |
| `Policy.shortReviewerNames(of:)` | Jméno revieweera do úzkého místa (#182) — zkrátí `plugin:skill`, ale jen když zůstane jednoznačné |
| `Policy.timelines(of:)` | Osy běhů z uloženého záznamu (#203); běh bez uložené osy se vynechá |
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
| `Policy.reviewNotification(for:state:blocking:topFinding:)` | Notifikace o doběhlém review z `ReviewState`; `nil` = není o čem dát vědět. Titulek nese počty (#200), tělo nález a pod ním PR |
| `Policy.newPullRequestNotification(for:title:isReReview:)` | Notifikace o novém PR ve frontě (#85); re-review se pozná textem (#137) |
| `Policy.newPullRequestsNotification(for:titles:reviewed:)` | **Souhrn** za všechna nová PR z jednoho tiku (#87); jedno PR dá plnou hlášku |
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
    a `inconclusive` (spadlo, vytimeoutovalo, nereportovalo, ztratilo nález) není `clean`
    proto, že zelený díl by tvrdil klid tam, kde se nálezy nemají kde vzít.
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
    prázdné plochy.
  - **Sheet odeslání zůstává na `ContentView`.** Detail zmizí, jakmile PR vypadne ze seznamu,
    a odeslané review `review-requested` ruší — sheet zavěšený na detailu by zmizel uprostřed
    odesílání.
  - **Rail má jen položky, které mají obsah.** Návrh jich kreslí šest; položka, po jejímž otevření
    je prázdno, je horší než položka, která ještě není. `Přehled` přijde s dashboardem (#181),
    `Historie` a `Zdraví` potřebují napřed obsah, který v aplikaci není.
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

## `GitHubGateway` (`App/GitHub/`)

Jediná cesta aplikace k GitHubu, celá přes `gh`. Protokol `GitHubGateway` má čtrnáct metod
a **schválně žádnou, kterou by šlo něco odeslat** — read-only je vidět z typu.

| Typ | Co dělá |
|---|---|
| `GitHubGateway` | Protokol: `checkAuth()`, `searchPullRequests(query:)`, `fetchDetail(id:)`, `fetchChecks(id:)`, `fetchDiff(id:)`, `fetchDiff(repo:from:to:)`, `fetchDiff(repo:commit:)`, `fetchFile(id:path:)`, `fetchFile(repo:path:at:)`, `fetchConversation(id:)`, `fetchReleases()`, `fetchAnnotations(repo:checkRunID:)`, `fetchJobLogSize(repo:jobID:)`, `fetchJobLog(repo:jobID:)`, `fetchCommits(id:)` |
| `GhGateway` | Implementace nad `gh`; `checkAuth()` deleguje na `GhAuthCheck` z `Environment` |
| `GitHubError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `GhResponseHeaders` | Rozbor hlaviček z `gh api -i` a `ContentLengthReading` — **čistá funkce** (#292) |
| `GhSearchQuery` | Rozdělení search dotazu na argumenty `gh` — čistá funkce |
| `ConversationQuery` | GraphQL dotaz na konverzaci a jeho argumenty — čisté funkce |
| `GhConversationResponse` | Tvar GraphQL odpovědi a mapování na `Conversation` |
| `GhSearchItem`, `GhPullRequestDetail` | Tvar JSONu z `gh` a převod na doménové modely |
| `GhRelease` | Tvar jedné položky `GET /repos/…/releases` a převod na `Release` |
| `GhCommit` | Tvar jedné položky `GET /repos/…/pulls/{n}/commits` a převod na `PullRequestCommit` (#316). **Skoro všechno optional**: odpověď má přes šedesát polí a bereme šest, takže chybějící pole nesmí položit seznam kvůli něčemu, co se nekreslí |
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

## `ReviewPublisher` (`App/Publish/`)

**Jediná cesta, kterou z aplikace něco odejde na GitHub.** Vznikl v #67 a nahradil tvrdou
podmínku „nikdy nic neposílat“ pravidlem, které je vidět z kódu — viz tvrdé podmínky výš.

| Typ | Co dělá |
|---|---|
| `ReviewPublishing` | Protokol se **čtyřmi** metodami: `submit(_:)`, `reply(to:body:)`, `setResolved(_:of:)`, `comment(on:body:)` |
| `GhReviewPublisher` | Implementace nad `gh`; pre-flight přes `GitHubGateway` |
| `PublishScope` | Brána: smí se z tohohle repa odeslat? Skládá se z `Configuration`, výchozí stav **vypnuto** |
| `PublishError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `PublishRequest` | Payload a argumenty review + `isSendable` (sdílená kontrola prázdného těla) — čisté funkce |
| `ThreadRequest` | GraphQL mutace pro vlákna a jejich argumenty — čisté funkce |
| `CommentRequest` | REST argumenty komentáře pod PR (#216) — čisté funkce |
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
- **A stejně tak ukončení aplikace** (#264). Je to tentýž invariant a **tentýž `SIGKILL`** —
  zavírání jde přes `AppStore.stopReviewsBeforeTermination()`, které běhy jen **zruší**; druhý
  `kill` v delegátovi by byl druhá pravda o tom, jak se běh zastavuje. Co zavírání přidává,
  je **čekání**: zrušení se přenáší přes `WorkCoordinator`, který práci drží ve vlastním tasku,
  takže mezi `cancel()` a odeslaným signálem je několik hopů mezi aktory. Do #264 se nečekalo
  vůbec (nezabíjelo se) a osamocený `claude` se přerodil na `launchd` — změřeno, dvě takové
  session běžely na stroji čtyři dny. Podrobnosti o té cestě jsou v sekci `AppStore`.
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
