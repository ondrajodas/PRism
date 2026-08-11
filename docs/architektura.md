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
| `PullRequestState` | `open` / `draft` / `merged` / `closed` |
| `ReviewState` | Stav review v řádku seznamu — deset případů, viz níž |
| `ReviewVerdict` | Návrh, co s PR udělat: `approve` / `requestChanges`. Jako jediný **není `Codable`** — neukládá se, odvozuje se z uložených nálezů |
| `EffectiveVerdict` | Verdikt, který na draftu **platí**, a jeho původ (`suggested`/`chosen`). Taky **není `Codable`** — počítá se, viz níž |
| `ProjectLanguage` | Čím je repo psané — klíč mapy „jazyk → sada skillů“. **Není to `Syntax.Language`**, viz níž |
| `FindingsLanguage` | Jazyk prózy v nálezech (`cs`/`en`). Ani tohle **není `ProjectLanguage`** |
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
| `PullRequestTab` | Který tab PR je vidět: `overview` / `filesChanged` / `conversation` / `findings` / `progress` (#242). `isReviewerOutput` odděluje **výstup našich reviewerů** od toho, co je na PR — z něj se kreslí dělič v pruhu záložek, takže `Kontroly` (#215) můžou přijít doprostřed levé skupiny, aniž by se posunul. Jako `ReviewVerdict` **není `Codable`** |
| `PullRequestTabBadge` | Odznak u záložky (#242): `count` / `blocking` (červeně) / `live` (puntík). Výčtem, ne strukturou s příznaky — „puntík s počtem“ ani „blokující bez počtu“ význam nemá, takže se nemá dát napsat |
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
  ale vedou jinam: timeout říká, že je review pomalé (dá se zvednout limit), přerušení že spadla
  aplikace (nedá se dělat nic než pustit znovu). A odznak by u přerušeného běhu tvrdil
  `timeout`, což je nepravda.
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

**`DiffLineView` a `DiffPairView` se v aplikaci už nekreslí** (bloky je nahradily), ale drží
konstanty a barvy, které si bloky berou (`numberColumn`, `iconColumn`, `signColumn`,
`contentInset(for:)`, `signColor(of:)`, `background(of:)`, `rangeTint`, `dragTint`). Zůstávají
proto jako **jediné místo, kde ty hodnoty jsou** — vyčlenit je do vlastního typu je úklid na potom,
ne součást #157.

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
| `GlobalConfig` | `sources`, `skills`, `skillsByLanguage`, `blockingCategories`, `mode`, `allowsPublishing`, `findingsLanguage`, `diffLayout`, `notifications`, interval, souběh, `autoRunsPerDay`, rozpočet, model |
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
- **Rozbitá hodnota režimu se sráží na `manual`, ne na globální default.** Chybějící klíč
  je „ber globální“, ale překlep v hodnotě, kterou se někdo pokoušel automat **vypnout**,
  ho nesmí nechat zapnutý. Platí i globálně.
- **Výchozí hodnoty musí odpovídat konstantám, které nahradily** — je na to test, jinak by
  se aplikace po zavedení konfigurace začala chovat jinak. Výchozí `mode` je `manual`:
  zapnout automat plošně je vědomé rozhodnutí, ne to, do čeho aplikace spadne sama.
- **Nový klíč v `RepositoryConfig` má druhého čtenáře mimo aplikaci: očistu konfigurace slotu**
  (#262, `bin/slot-config.sh`). Klíčů, které mají obě úrovně, je pět — `mode`,
  `allowsPublishing`, `findingsLanguage`, `skills`, `blockingCategories` — a u každého z nich je
  ve skriptu napsané, jestli se čistí a proč. Očistit jen globální úroveň **nestačí**: per-repo
  override je přednější, takže `mode: automatic` u jednoho repa přebije globální `manual` —
  a slotová aplikace si na M9 takhle sama pustila review za 2,80 $ a 1,16 $, dvakrát nezávisle
  na sobě. Když klíč přibude, patří do toho výčtu, i kdyby se nakonec nečistil; nevyplněné
  místo v něm je celá ta chyba.

## `App/Markdown/`

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
  nezneplatňuje; paletu si bere view až při kreslení.
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
| `ReviewRequest` | Zadání: klíč, pracovní strom, `baseSha` (proti čemu diffovat), jazyk nálezů |
| `ReviewRunKey` | `(PR, headSha, skillID)` — identita běhu |
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

Společné je jim to, proč tady jsou: **kopie jednoho pravidla se rozejdou.** `WorkCoordinator`
používá `RepoCheckout` (klony, stromy) i `ReviewRunner` (běhy) a dvě kopie by znamenaly dvakrát
tu jemnou logiku kolem rušení. `Plural` vznikl ze tří `switch`ů, které se lišily; `singleLine`
z pěti kopií téhož `split(whereSeparator: \.isNewline)` — hlavička bubliny, přehled draftu,
jeho přenos, syntetická hlavička diffu a od #200 tělo notifikace. Stačilo by, aby jedna z nich
řešila `\r\n` a ostatní ne.

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
| `ReviewRecord` | Obsah jednoho souboru: PR, `headSha`, běhy, `isStale`, `closedAt` |
| `StoredReviewRun` | Jeden běh: skill, `outcome`, session id, nálezy, `droppedFindings`, čas, **cena** (#148, volitelná) |

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
| `AppStore+DiffExpansion.swift` | Rozbalování kontextu mimo hunky (#47) | 112 |
| `AppStore+DraftTransfer.swift` | Přenesení draftu na nový commit (#69) | 103 |
| `AppStore+Diff.swift` | Načtení diffu, pohled a sbalování souborů | 95 |
| `AppStore+Automatic.swift` | Automatický režim a denní rozpočet (#25) | 89 |
| `AppStore+Findings.swift` | Zahození záznamu (#81) a odmítnutí nálezu (#113) | 70 |
| `AppStore+Detail.swift` | Detail PR a jeho záložky | 59 |

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
| `FullSizeContentWindow` | Roztažení obsahu pod titulkovou lištu, aby hlavička mohla být vlastní (#180) |
| `Palette` | Barvy okna z návrhu, světlá i tmavá varianta — **jeden zdroj pro celou aplikaci** (#180). Krytí je u tichých podkladů (`accentWeak`) v každém režimu jiné, jak to má návrh. Stavové tóny `ok`, `find`, `crit` (#218) jsou pro odznaky a puntíky; **zelená a červená diffu jdou dál z `DiffLineView.signColor(of:)`**, aby se `+` v řádku nerozešlo s `+12` nad ním (#156) |
| `ReviewTabsView` | Pruh záložek v hlavičce: domů, otevřená review s tečkou stavu a křížkem (#180) |
| `SidebarRail` | Svislý rail vlevo — `Přehled`, `Fronta` s odznakem, `Rozdělaná` (#180) |
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
| `QueueSummaryView` | Souhrn fronty (#155) — kolik PR čeká, kolik má blokující nález a kolik rozdělané review |
| `RunUsageText` | Cena, trvání a počet kol jako text — jedno místo pro osu i stavový řádek |
| `AppNoticesView` | Hlášky ve stavovém řádku: rozbitá konfigurace, pozastavený automat, nečitelné soubory, zakázané notifikace |
| `WindowCentering`, `WindowReader`, `ScreenBounds` | Vystředění pomocného okna **v hlavním okně**, ne na obrazovce (#164) — z jednoho místa pro nastavení i novinky |
| `AuxiliaryWindowLevel`, `keptInFrontOfApp()` | Pomocné okno zůstává **před ostatními okny aplikace, a jedině před nimi** (#243) — `.floating` dokud je aplikace vpředu, jinak `.normal` |
| `DiffCopyActions`, `copyMenu(_:selectText:)` | Kopírování kódu z diffu (#157) — co nabídne kontextové menu řádku a hunku |
| `DiffTextView` | `NSTextView`, který kreslí blok řádků: text, obarvení, pozadí, pruh rozsahu, čísla a znaky změny (#157). Drží **šířku kontejneru i měření výšky** (`height(forWidth:)`, `height(ofRows:)`), aby se šířka pro měření nemohla rozejít s tou pro kreslení (#236) |
| `DiffCodeBlockView`, `DiffBlockRowView` | Blok v pohledu pod sebou a k němu pilulka na komentář a tažení rozsahu |
| `DiffPairBlockView`, `DiffPairBlockContainer`, `DiffPairBlockRowView` | Totéž vedle sebe: dva zarovnané sloupce v clip view |
| `CodeText`, `CodeTextSheet`, `SelectableCodeView` | Hunk jako jeden text mimo diff (#157) — vybrat jde i přes bubliny |
| `PullRequestListView` | Seznam, prázdný stav, úvodní loading, tlačítko obnovit (⌘R) |
| `PullRequestFilterButton` | Filtr seznamu v toolbaru (#117) — ikona se stavem a počtem schovaných, popover s odškrtávátky a **počtem PR u každé položky** (#199) |
| `PullRequestTabBar` | Záložky PR (`Přehled` / `Změněné soubory` / `Konverzace` ‖ `Nálezy` / `Průběh`) — podtržené, s odznakem **u každé** (#218; typy od #242), děličem před výstupem reviewerů a vpravo `+X −Y` se čtverečky poměru |
| `OverviewView` | Tab `Přehled`: popis PR, fakta, kontroly a co se změnilo od minule |
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
| `FindingBubbleView` | Nálezy k jednomu řádku; u nálezu mimo diff nabídne jeho řádek dotáhnout, odmítnutý sbalí na jeden řádek s odznakem důvodu a `Vrátit`. Od #185 má **značku** (pruh s odznaky a náhledem) a rozbalený obsah pod ní — blokující je rozbalený rovnou |
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
| `VerdictAppearance` | Ikona a barva verdiktu — jedno místo pro panel i pro potvrzení |
| `DraftActions`, `FileDraftActions` | Co se dá s draftem dělat; druhé svázané s jedním souborem diffu |
| `DiffLineView` | Řádek souboru: dvě čísla (v buňce dvojice jedno, podle `side`), znak změny, obsah obarvený podle jazyka, tlačítko na komentář (na hover) |
| `ReviewPanel` | Panel **napravo od diffu** (#182, do #242 `FindingsPanel`): segmenty `Nálezy`/`Moje review`, karty nálezů, prokliky do diffu — a složení na proužek s počtem nálezů a značkou rozdělaného review. `Průběh` a zahození nálezů se u #242 odstěhovaly do záložek PR |
| `DismissedRowStyle` | Buňka tabulky: ztlumení odmítnutého řádku a kontextové menu `Označit jako…` / `Vrátit` |
| `FindingRow` | Nález převedený na řádek tabulky — texty (včetně nápovědy k místu), identita, blokující příznak, odmítnutí |
| `FindingHighlight` | Místo, na které se právě skočilo; bublina na něm chvíli svítí |
| `ReviewProgressView`, `ReviewerLaneView` | Tab `Průběh` (#242, nahradily `ReviewTimelineView`): **dráha na revieweera** s fázemi vedle sebe, věta o tom, co se právě děje, u spadlé session důvod, `stderr` a `Pustit znovu` / `Zkopírovat příkaz`; podrobný výpis událostí pod rozbalením (`TimelineEntryRow`). Dráha po skillu **mimo nastavenou sadu** nese v hlavičce `mimo sadu`; prázdný stav mluví o **nastavení**, protože se do něj dá dojít jedině s prázdnou sadou skillů |
| `ReviewerLaneText` | České věty dráhy — stav, co se právě děje, čím to skončilo. Rozlišuje **tři** doběhlé stavy: nahlásilo nálezy / nahlásilo nulu / nenahlásilo nic — a `nespuštěno` od `ve frontě` |
| `FindingsTabView`, `FindingsEmptyView` | Tab `Nálezy` (#242): souhrn počtů, `Zahodit nálezy`, tabulka — a věta, **proč** je prázdno (`Policy.findingsEmptyReason`), společná s panelem |
| `FindingsTableView`, `FindingTableRowView`, `FindingTableRow` | Tabulka nálezů přes celou šířku: řazení kliknutím na hlavičku, řádek na **místo** (shoda dvou reviewerů je odznak `2×`), rozbalení kreslí tutéž `FindingBubbleView` jako diff |
| `ReviewerChipsView` | Chipy reviewerů: **puntík, zkrácené jméno a počet** (#218); stav a filtr naráz, v kontextovém menu opakování jednoho revieweera (#149) |
| `FileTreeView` | Strom souborů v levém sloupci u diffu; odsazení a sbalování si řídí sám |
| `ReviewStateBadge` | Odznak stavu review; texty podle specifikace |
| `hiddenShortcuts(_:)` | Klávesové zkratky bez viditelného tlačítka (#151) — jedno místo pro detail PR, nastavení, okno novinek i paletu |
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
- **Počítá se z `reviewTasks`**, ze stejného zdroje jako `isReviewing`. Vlastní počitadlo je
  druhé místo, které se s prvním může rozejít — a rozejít se v tomhle znamená zavřít bez
  zeptání.
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
| `ReviewSettingsView` | Výchozí režim a jazyk nálezů, skilly, sady podle jazyka, blokující kategorie |
| `DiffSettingsView` | **Pohled na diff** — nastavení člověka, ne repa, proto jen globálně |
| `PublishingSettingsView` | **Odesílání na GitHub** — vlastní stránka, viz níž |
| `RuntimeSettingsView` | Interval pollingu, rozpočet cache, souběžné session, denní limit, model |
| `NotificationSettingsView` | Stránka `Notifikace` (#86): hlavní vypínač a čtyři události |
| `LanguageSkillsEditor` | Mapa „programovací jazyk → sada skillů“; ukazuje jen nastavené jazyky |
| `RepositorySettingsView` | Seznam rep vlevo, režim, povolení odesílání a override vpravo |
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
- **Panel je ve všech tabech**, včetně `Nálezů` (#242). Nálezy bez místa v kódu i moje rozdělané
  review se vážou k celému PR — schovat je za přepnutí tabu by znamenalo, že se rozepsané review
  „ztratí“ přepnutím na `Přehled`. U tabu `Nálezy` je to o důvod víc: smyčka nález → `Převzít` →
  text v mém review je ta hlavní práce, takže se obojí musí stát naráz.
- **Složení panelu a jeho tab drží store, ne view** (#242): `isReviewPanelExpanded`
  a `reviewPanelTab`, globálně (ne per PR) jako `diffLayout`. Není to úklid, je to podmínka —
  poznámka do těla review přidaná z diffu spadne do panelu, takže se panel musí umět
  **rozložit sám** (`revealDraft()`), a dokud to bydlelo v `@State` detailu, nešlo to otestovat.
  Tudy chodí `appendDraftNote` i `adoptFinding` s cílem `.body`; **řádkový komentář panel
  nerozloží** — ten je vidět hned pod řádkem v diffu.
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
- **`Přehled` ukazuje checky z GitHub Actions** (#209) — druhou půlku otázky „dá se to
  mergnout“; tu první (nálezy) okno umělo, takže se nad zeleným review stejně chodilo do
  prohlížeče. Čtyři pravidla:
  - **Nejhorší stav vyhrává, ne většina.** Dvanáct zelených a jeden červený je červený stav.
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
- **`Přehled` má dlaždice s fakty** (#198): commity (a kolik z nich je nových od minule),
  soubory (a kolik má nález), hlava PR a sha, proti které platí nálezy. **Nic se pro ně
  nedotahuje** — jsou to údaje, které v okně už jsou, jen roztroušené. Tři pravidla:
  - **Dlaždice, o které se nedá nic říct, se nekreslí.** Řádek plný nul je řádek, ve kterém se
    ztratí to jedno číslo, na kterém záleží — a nula u souborů navíc tvrdí, že PR nic nemění,
    i když se diff jen ještě nenačetl.
  - **Neúplný počet se nekreslí.** Utnutá stránka událostí znamená, že commity přesně neznáme,
    a číslo „aspoň tolik“ vydávané za úplné je horší než prázdné místo.
  - **Sha nálezů jen při rozchodu s hlavou** — a jedině když je hlava načtená. Shodná je údaj, který nikoho nezajímá; rozešlá je
    důvod, proč nálezy neplatí (tvrdá podmínka č. 5), a je žlutá jako stav `zastaralé`.
  - **Mřížka čtyř sloupců, ne `HStack`.** V `HStacku` se dvě dlaždice roztáhnou přes celou šířku
    a číslo v nich plave uprostřed prázdna; v mřížce si drží čtvrtinu bez ohledu na počet.
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
| `Policy.sortedReleases(_:)` | Vydání od nejnovějšího (#127) — podle **data**, ne podle tagu |
| `Policy.newReleases(in:since:)` | Co vyšlo od poslední viděné verze; neznámá značka = **nic** |

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

  **Sázen je podle návrhu (`.since`, #226) a má jen jeden tón** — okrový `--stale`. Do #226 bral
  systémový akcent (modrou) a při přepsané historii systémovou žlutou; obojí bylo mimo paletu okna,
  protože okno stojí na fialové z návrhu (#180) a systémová žlutá je **výstraha**, kdežto tenhle
  blok říká „platilo to, dneska už ne“ — přesně význam, na který #216 zavedlo `Palette.stale`.
  Že se přepsala historie, proto nese `staleRow` větou a tlačítkem, ne odstínem pozadí; barvou to
  rozlišovat nešlo, aniž by jedna z těch dvou byla mimo paletu. Graficky přibyl **obrys** (bez něj
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

Jediná cesta aplikace k GitHubu, celá přes `gh`. Protokol `GitHubGateway` má sedm metod
a **schválně žádnou, kterou by šlo něco odeslat** — read-only je vidět z typu.

| Typ | Co dělá |
|---|---|
| `GitHubGateway` | Protokol: `checkAuth()`, `searchPullRequests(query:)`, `fetchDetail(id:)`, `fetchDiff(id:)`, `fetchFile(id:path:)`, `fetchConversation(id:)`, `fetchReleases()` |
| `GhGateway` | Implementace nad `gh`; `checkAuth()` deleguje na `GhAuthCheck` z `Environment` |
| `GitHubError` | Typované chyby + klasifikace výstupu `gh` jako **čistá funkce** |
| `GhSearchQuery` | Rozdělení search dotazu na argumenty `gh` — čistá funkce |
| `ConversationQuery` | GraphQL dotaz na konverzaci a jeho argumenty — čisté funkce |
| `GhConversationResponse` | Tvar GraphQL odpovědi a mapování na `Conversation` |
| `GhSearchItem`, `GhPullRequestDetail` | Tvar JSONu z `gh` a převod na doménové modely |
| `GhRelease` | Tvar jedné položky `GET /repos/…/releases` a převod na `Release` |
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
