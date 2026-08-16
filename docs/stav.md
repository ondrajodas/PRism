# Stav projektu

Co je hotové a co zbývá. Referenční část [`CLAUDE.md`](../CLAUDE.md) — **tenhle seznam aktualizuj,
jak fáze ubývají**.

Kde projekt je, se pozná i z issues a z release notes; tohle je souvislý záznam, ze kterého je
vidět, **co se cestou rozhodlo jinak, než bylo v zadání**.


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
  podrobnosti v [`docs/claude-cli.md`](claude-cli.md).
- **`Bash(git:*)` pouštělo i `git push`.** V cache míří `origin` na skutečné repo
  s credential helperem, takže reviewer uměl pushnout do uživatelova repozitáře. Zavírá to
  `--disallowedTools`, ověřeno i proti obcházení přes vypsanou URL.

Stavy checkoutu v seznamu hotové (issue #11) — `AppStore` umí připravit pracovní kopii,
řádek ukazuje `ve frontě · clone` nebo `clone selhal` a detail nese výstup `gitu`
i tlačítko `Zkusit znovu`. **Aplikace tím poprvé něco zapisuje na disk.**

Spike k `claude` CLI hotový (issue #12) — [`docs/claude-cli.md`](claude-cli.md)
a fixtures v `Tests/Fixtures/stream-json/`. **Žádný appkový kód**, ale opravil dvě chyby
v návrhu: `--verbose` je povinný a `ReportFindings` musí být v `--allowedTools`, jinak
reviewer nálezy napíše textem a sběr tiše nefunguje.

Spike k **zápisovému review API** hotový (issue #62) —
[`docs/github-review-api.md`](github-review-api.md) a fixtures
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
se změnila tvrdá podmínka č. 1 na pravidlo „jediná cesta ven“ (viz *Tvrdé podmínky*
v [`CLAUDE.md`](../CLAUDE.md)). Odesílá se
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
  stojí v crash reportu z 2026-08-03. Viz sekce views v [`architektura.md`](architektura.md).

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
vypíše čtyři soubory se dvěma volajícími (viz *Tvrdé podmínky* v [`CLAUDE.md`](../CLAUDE.md)). Pre-flight u odpovědi `headSha`
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

Přenesení draftu na nový commit hotové (issue #69) — `DraftSnapshot` v `App/Models/`,
`Policy.anchorState`/`transferring`, `DraftTransferView` jako první stránka potvrzení odeslání
a `transferDraft` v `AppStore`. **Rozdělané review psané proti staršímu commitu jde po kontrole
odeslat proti novému** a žádná kotva se nepřenese tiše: u každého komentáře je vidět, jestli sedí,
posunula se, nevíme (draft z doby před #69), nebo se ztratila — a co s ní bude. Tím je **hotový
milník M6**.

Předvyplněný verdikt hotový (issue #114) — `EffectiveVerdict` v `App/Models/`,
`Policy.effectiveVerdict`/`prefillableSuggestion`, třetí stav tlačítka v `DraftPanel`
a `verdictOrigin` v `ReviewSubmission`. **U PR s doběhlým review je verdikt navržený a dá se
odeslat, aniž bych na něj klikal** — a přitom se nikam neukládá: draft na disku zůstává bez
verdiktu, takže „draft existuje“ dál znamená „je co poslat“. Z panelu i ze sheetu je poznat, že
je to návrh, ne moje volba. **Mění rozhodnutí z #66 a #68**, podle kterého se verdikt
nepředvyplňuje; ochranu proti záměně nese potvrzovací sheet, ne to kliknutí (viz specifikace).
Na vlastním PR se návrh nenabídne, protože tam GitHub bere jedině `COMMENT`.

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

Odmítnutí nálezu hotové (issue #113) — `FindingDismissal` a `FindingKey` v `App/Models/`,
`Policy.key(of:)` a `ReviewRecord.activeFindings`, mutace na `ReviewStore`u, akce v bublině
i v kontextovém menu tabulky. **Falešně pozitivní nález se dá jedním kliknutím odmítnout jako
`neplatný` nebo `irelevantní`**, návrh verdiktu se tím posune na `approve` a ostatní nálezy
platí dál — tedy to, co #81 řešit nemůže, protože zahazuje celý záznam. Odmítnutý nález
**nemizí**: sbalí se na jeden řádek s odznakem důvodu a `Vrátit`, v tabulce je ztlumený naspod.
Bydlí to na `ReviewRecord`u, ne na `Finding`u, kvůli `replace(_:)` — a nepřenáší se na nový
commit, protože nálezy jsou klíčované `headSha`. Řádek seznamu má vlastní stav `dismissed`, ne
`clean`: „reviewer nic nenašel“ a „našel a já to zamítl“ jsou jiná tvrzení. Odůvodnění obojího
je ve specifikaci.

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

Dotažení nálezů po pádu hotové (issue #97) — `InterruptedRun` a `InterruptedRuns`,
`TranscriptLocation` s `TranscriptStore` a `recoverInterruptedRuns()` v `AppStore`.
**Nálezy z běhu, který aplikaci nepřežil, se po startu dotáhnou z transcriptu** a uloží se jako
`interrupted` — nový stav vedle `timedOut`, protože „nedoběhlo, protože je to pomalé“ a
„nedoběhlo, protože spadla aplikace“ vedou jinam a odznak `timeout` by nad druhým lhal. Dialog
při zavření (#94) tím dostal druhou půlku: ten pokrývá jen to, co způsobí uživatel.

Cesta k transcriptu je **změřená**: mangling nahrazuje všechno mimo `[A-Za-z0-9-]`, ne jen `/`
a mezery, jak stálo v zadání.

Symlinky v `ReviewStore`u odmítnuté (issue #106) — `CacheLayout.isSymbolicLink` jako jedno
místo pro oba story. Odkaz na soubor uvnitř `reviews/` by se přečetl **mimo cache**: `load`
i `cleanUp` ho braly jako uložený záznam a `dismiss` nad ním zapisoval odmítnutí. Teď se
přeskakuje a **počítá** do `unreadable`, protože tiché přeskočení by anomálii schovalo. Věta
v `CLAUDE.md` o enumeraci a symlincích tím platí pro celý repozitář, ne jen pro drafty.

Poslední ohlášení ve stavovém řádku hotové (issue #138) — `DeliveredNotification`
v `App/Models/`, `lastDeliveredNotification` v `AppStore` a `NotificationStatusView`
v `StatusBarView`. **Že notifikace fungují, je vidět**: vlevo od puntíků služeb je zvonek
s časem posledního doručení, `zatím nic`, nebo `vypnuto`. Čas posune jedině `.delivered` —
odmítnuté oprávnění, selhání systému ani vypnutá událost ne, jinak by řádek tvrdil, že to
chodí, zrovna když nechodí. Drží se v paměti: je to odpověď na „funguje mi to teď“, ne historie.

Okno s novinkami hotové (issue #127) — `Release` v `App/Models/`, `fetchReleases()`
v `GitHubGateway`, `Policy.sortedReleases`/`newReleases` a `App/Views/ReleaseNotes/`.
**Co se ve které verzi změnilo, je vidět v aplikaci**: vlevo celá historie vydání, vpravo
release notes vybrané verze vykreslené `App/Markdown/` (jeho první konzument mimo konverzaci
pod PR). Po aktualizaci se okno otevře samo, jednou, s vybranou nejnovější verzí; jinak se
otevírá z menu aplikace. Bez sítě je v něm důvod a `Zkusit znovu`, ne prázdný seznam.

Aplikace přitom **neví, kolikátá je** — `MARKETING_VERSION` je pořád `0.1` a tagy nikdy
nesledoval. Okno proto mluví o tom, co vyšlo na GitHubu, verzi běžícího buildu nevypisuje
a pamatuje si poslední **viděný tag** v `UserDefaults`. Tvrdá podmínka č. 1 se nemění:
`fetchReleases()` je sedmá **čtecí** metoda gateway.

Povolení odesílání v nastavení hotové (issue #107) — `allowsPublishing` v `Configuration`
(globálně i per repo), `PublishScope` složený z konfigurace a přepínač v okně nastavení.
**Mění tvrdou podmínku č. 1, bod 6**: zadrátovaný seznam s jediným sandboxem je pryč, brána
je nastavení s **výchozím stavem vypnuto** — dokud si o odesílání někdo výslovně neřekne,
neodejde nikam nic. Sandbox není výjimka v kódu, zapíná se stejným přepínačem. Rozbitá hodnota
v souboru se sráží na zakázané, na obou úrovních.

Seskupování notifikací hotové (issue #87) — `Policy.newPullRequestsNotification`,
`NotificationEvent.replacementGroup` a `identifier`/`threadIdentifier` na
`PullRequestNotification`. **Deset nových PR naráz dá jednu notifikaci** („3 nové PR k review“),
nový výsledek review přepíše ten starý a systém řadí hlášky k sobě podle PR. Slévá se seznam
z jednoho tiku, takže na to není potřeba žádné čekací okno ani další stav.

**Tím je hotový milník M8 — a s ním poslední naplánovaný milník projektu.**

Volba, co se má hlásit, hotová (issue #86) — `NotificationSettings` a `NotificationEvent`
v `App/Models/`, `global.notifications` v konfiguraci, sekce v okně nastavení a brána
v `AppStore.notify(_:)`. **Notifikace se dají vypnout jako celek nebo po událostech** (nový PR,
review s nálezy, čisté review, selhání) — a s vypnutým hlavním přepínačem se aplikace **nezeptá
ani na systémové oprávnění**.

Výchozí stav je **všechno zapnuté**: vypnuté notifikace by znamenaly, že se funkce po vydání
nikdy neprojeví, a co otravuje, se vypne jedním přepínačem. Nejtěsnější to bylo u čistého review
(je to zpráva „nemusíš nic dělat“), ale u ručně spuštěného běhu je to zrovna ta odpověď, na
kterou člověk čeká.

Notifikace o novém PR hotová (issue #85) — `AnnouncedPullRequests` v `App/Store/`
a `Policy.newPullRequestNotification(for:title:)`. **Když se ve frontě objeví PR, který tam
nebyl, přijde notifikace** s repem, číslem a titulkem; klik ji vybere.

Stav je **snímek poslední fronty na disku**, ne rostoucí log: nic se nehromadí, nemusí se nic
uklízet a PR, které zmizí a vrátí se, se ohlásí znovu (vrátilo se do fronty a je to informace).
První spuštění mlčí — bez toho by po každém startu přišlo deset notifikací naráz.

Notifikace o doběhlém review hotová (issue #82) — `Policy.reviewNotification(for:state:blocking:)`
a `notifyAboutFinishedReview(of:)` v `AppStore`. **Aplikace poprvé sama něco pošle:** po
doběhnutí review přijde jedna notifikace na PR a klik na ni ten PR vybere. Text rozlišuje
nálezy (s počtem blokujících), čisto, timeout s částečnými nálezy, odmítnuté nálezy, spadlou
session i selhaný checkout — a „nemám co říct“ se nesmí ohlásit jako čisto. Zrušené review
mlčí.

Staví to na `ReviewState`, ne na běhách: tentýž stav kreslí i řádek seznamu, takže se ty dva
nemůžou rozejít.

Základ notifikací hotový (issue #88) — `UserNotifying` a `SystemNotificationCenter`
v `App/Environment/`, `notify(_:)` a obsluha kliknutí v `AppStore`, hláška v `AppNoticesView`.
**Vrstva bez konzumenta**: aplikace umí notifikaci doručit a poznat kliknutí (vybere PR a dá
okno dopředu), ale sama zatím nic neposílá — první konzument je #82. O oprávnění se říká až
u první notifikace, odmítnuté oprávnění aplikaci nepoloží a je vidět ve stavovém řádku.

Ověřeno spuštěním, ne jen testy: notifikace dorazila, delegát dostal `willPresent`
i `didReceive` a klik vybral ten PR, na který ukazovala.

**Přineslo to jednu změnu mimo zadání:** `bin/run.sh` instaluje aplikaci do `/Applications`
a spouští ji odtud, protože **odjinud macOS notifikace nepovolí** — z buildové složky v repu
i z `~/Applications` zůstane oprávnění `denied` bez dialogu a bez záznamu v Nastavení
systému. Vyloučeno postupně: podpis (self-signed, ad-hoc, hardened runtime),
`get-task-allow`, Debug proti Release, duplikáty v LaunchServices, restart `usernoted`, MDM
profily — a rozhodla minimální cizí aplikace s jiným bundle identifikátorem, která dostala
tutéž chybu. Bez té změny by se M8 nedal ani vyzkoušet, ani používat.

Stavový řádek hotový (issue #31) — `App/Health/`, `StatusBarView`, `Policy.health(of:from:)`
a `HTTPGetting` s `NetworkReachability` v `App/Environment/`. Na spodku okna je puntík
u GitHubu a u Claude: zelenou a červenou určuje **skutečný provoz** (tik pollingu, doběhlá
session), žlutou incident na komponentách, které aplikace používá, a bez sítě má vlastní
důvod. Hlášky z dosavadního pruhu se do řádku **přestěhovaly** — dvě místa na tytéž hlášky
znamenají, že se jedno z nich přestane plnit. Je to **první `URLSession` v projektu**: do té
doby šel všechen kontakt s vnějším světem přes podprocesy.

Obarvené počty řádků hotové (issue #156) — `DiffCounts.text` a `DiffLineView.signColor(of:)`.
Souhrn nad diffem, hlavičky souborů i strom souborů mají `+X` zeleně a `−Y` červeně, barvou
znaku změny v samotném řádku — jeden zdroj místo tří, které by se rozešly. Čitelnost v obou
režimech je doložená offscreen renderem, včetně toho, že se to neplete s červeným odznakem
nálezů.

Opakování jednoho revieweera hotové (issue #149) — `startReview(for:skills:)`
a `RunningReview` v `AppStore`, položka v kontextovém menu chipu. **Když ze tří skillů jeden
spadne, jde pustit znovu jen on** — za dva výsledky, které leží na disku, se neplatí podruhé.
Datová vrstva to unesla už dřív (`ReviewRecord.replace(_:)` je klíčovaný skillem); doplnit se
musela osa (maže se jen ta jeho), `runningReviewers` (chipy ostatních dál ukazují svůj výsledek)
a mazání značek přerušených běhů.

Cena a trvání běhu hotové (issue #148) — `RunUsage` a `DailySpend` v `App/Models/`, `SpendLedger`
v `App/Store/`, řádek u revieweera v tabu `Průběh` a útrata za dnešek ve stavovém řádku.
**Aplikace poprvé říká, co ji stojí provoz**: `result` event nesl cenu, trvání i počet kol od
začátku a `StreamParser` z toho nebral nic. Zabitý běh je nemá a **neukazuje nulu**; denní součet
je na disku (přežije restart) a u neúplného je `≥`, protože zabitá session peníze stála taky.
Rozpočet v penězích se vědomě odkládá, viz specifikace.

Úryvek kódu u vlákna hotový (issue #158) — `ReviewThread.diffHunk`, `ThreadSnippet`
a `Policy.snippet(of:context:)` v `App/Policy/ThreadSnippet.swift`, `ThreadSnippetView`.
**Vlákno v `Přehledu` má nad sebou obarvený kus kódu, ke kterému se váže** — dosud tam byla jen
`cesta:řádek`, ze které se nedalo poznat, o čem je řeč. Jsou to zrovna vlákna, která v diffu
domov nemají: zastaralé se u kódu nekreslí schválně, protože jeho číslo je ze starého headu.
Kód se bere z `diffHunk` od GitHubu, tedy ze snímku proti commitu, na kterém komentář vznikl —
nic se nedopočítává. **Změna proti zadání:** pět řádků *za* komentovaným řádkem se neukazuje,
protože v `diffHunk`u nejsou (změřeno: jeho poslední řádek je právě ten komentovaný) a jinudy by
si to vyžádalo novou čtecí metodu gateway. Ze 190řádkového mediánu se ukazuje šest řádků a
zkrácení je vidět značkou. Vykresluje to `DiffLineView`, takže obarvení je jedno pro diff i pro
úryvek; hunk se kvůli tomu obaluje syntetickou hlavičkou `diff --git` a `DiffParser` se
**neupravoval**. Odůvodnění všeho je ve specifikaci.

Středění okna s novinkami hotové (issue #164) — `App/Views/WindowCentering.swift`
(`WindowCentering`, `WindowReader`, `ScreenBounds`, `centeredInMainWindow()`) a `MainWindow.title`
v `PRismApp`. **Okno s novinkami vyskočí vystředěné v hlavním okně, ne doprostřed obrazovky** —
mechanismus v repu už byl, jen byl `private` ve `SettingsView`, takže z něj druhá scéna neměla
nic. `SettingsView` je o šedesát řádků menší. Přesunem to zároveň dostalo **testy**: geometrie
se dá testovat, protože si obrazovky bere parametrem (`NSScreen` se vyrobit nedá), a drží tak
pořadí ořezu `max(min(…))`, na kterém záleží u okna širšího než obrazovka. Vyšlo z toho i jedno
doložené chování, které dosud nikde nestálo: okno se **nerozpůlí mezi dvěma monitory**.

Kopírování kódu z diffu hotové (issue #157) — `App/Policy/CopyPolicy.swift`
(`Policy.code`, `copyTargets`, `range(covering:)`), `App/Support/Clipboard.swift`,
`DiffCopyActions` a `DiffHoveredLine` v `App/Views/`. **Z diffu jde dostat kód do schránky, aniž
by po tom zůstal rozdělaný komentář** — pravým kliknutím (`Kopírovat řádek`, `Kopírovat rozsah (N
řádků)`, `Kopírovat hunk`) a ⌘C nad řádkem pod myší. Ve schránce je kód bez `+`/`-`, bez čísel
řádků a bez hlavičky hunku.

Nakonec **obojí ze zadání**: nejdřív varianta A (kopírování příkazem), pak na vyžádání při zkoušení
i **varianta B** — vybírání textu myší. **Kód v diffu se vybírá myší jako v editoru, přes libovolně mnoho řádků.**

Aby to šlo, **kreslí kód `NSTextView`, ne SwiftUI `Text`** — ve SwiftUI je každý `Text` vlastní
selekce, takže přes řádky vybrat nejde ani v jednom bloku textu. Souvislé řádky se před vykreslením
slévají do bloku (`DiffBlock`, `DiffPairBlock`) a blok končí tam, kde do diffu něco vstoupí —
hlavička hunku, expander, bublina. Čísla řádků a znaky změny se kreslí **mimo text**, aby se
nekopírovaly; pilulka na komentář a tažení rozsahu zůstaly SwiftUI nad blokem, pozicované podle
skutečné geometrie řádků. Bubliny, expandery a hlavičky se nezměnily.

Stálo to **rozhodnutí #98** (ve split pohledu se už nezalamuje, jinak se sloupce rozejdou) a sedm
změřených pastí AppKitu, které jsou zapsané v architektuře — od „co se nakreslí po `super.draw`,
není vidět“ po „`setAttributedString` ruší výběr, a `updateNSView` chodí i při přejezdu myší“.
`CodeTextSheet` (`Vybrat text z hunku…`) zůstal na to, co blok neumí: vybrat hunk **přes** bubliny.

Se selekcí se **pilulka s ikonkou přestěhovala do vlastního úzkého sloupce vlevo od čísel** (do té
doby seděla na čísle řádku a zpola ho překrývala — doloženo offscreen renderem, že to tak bylo už
před #157). **Tažení rozsahu naopak zůstalo na celém řádku:** přesun do sloupce s čísly rozbil
zvýraznění během tažení, takže nebylo vidět, co je vybrané; nad kódem si teď tažení a selekce
konkurují a vyhrává selekce, protože `Text` je potomek. Ikonka přestala být `Button`, protože ten
si tažení bral pro sebe. Zmizel i ⌘C
z aplikace: zkratku obsluhuje selekce, a dvě věci na jedné klávese jsou past, kde ⌘C přebije to, co
má člověk vybrané. Že ikonka číslo překrývala **už před #157**, je doložené offscreen renderem proti
`git stash`nuté verzi. `Clipboard` vznikl jako **třetí** výskyt `NSPasteboard` a oba dosavadní teď
jdou přes něj.

Souhrn fronty hotový (issue #155) — `QueueSummary` a `Policy.summary(of:records:drafts:categories:)`
v `App/Policy/QueueSummary.swift`, `AppStore.queueSummary`, `QueueSummaryView` ve stavovém řádku.
**Ve stavovém řádku je vidět, kolik PR čeká, kolik z nich má blokující nález a kolik rozdělané
review** — otázka „musím se na to podívat hned?“ dosud v okně adresu neměla, protože odznak v řádku
odpovídá za jeden PR, ne za frontu.

Počítají se **PR, ne nálezy** (tři nálezy na jednom PR jsou jedna položka práce) a blokující se bere
z `Policy.blockingCount`, tedy **bez odmítnutých** (#113). Souhrn sčítá **celou** frontu, ne to, co je
vidět po filtru reviewerů — filtr je pohled, souhrn tvrzení o obsahu. Dokud se seznam nenačetl,
neukáže se nic (nula blokujících nad nenačtenými daty vypadá jako čisto); po **selhaném** tiku se
naopak ukáže, protože data jsou stará, ne chybějící, a to už hlásí banner nad seznamem.

Rozdělení `AppStore` hotové (issue #154) — `App/Store/AppStore.swift` z 2508 řádků na 871
a k tomu jedenáct `AppStore+*.swift` po zodpovědnostech (`+Review`, `+Conversation`, `+Draft`,
`+DraftTransfer`, `+Submission`, `+Notifications`, `+DiffExpansion`, `+Diff`, `+Automatic`,
`+Findings`, `+Detail`). Tabulka s tím, který soubor drží co, je v [`docs/architektura.md`](architektura.md)
a odkaz na ni v `CLAUDE.md`.

**Dělí se metody, ne data:** uložený stav zůstal na jednom místě, protože jeho invarianty se drží
tím, že jsou pohromadě. Řezalo se podle `MARK` sekcí, které v souboru už byly — nebylo to nové
rozdělení, jen se přepsalo do souborů, a **ověřením, že to byl přesun a ne přepis, je nedotčené
`Tests/`**: 1563 testů prošlo bez jediné změny.

Cena je 59 členů, které musely z `private` na `internal`, protože na ně extensiony sahají. Je to
vidět (`store.gateway` je dnes dostupný z celé aplikace) a **tvrdou podmínku č. 1 to nemění**:
publisher polem storu není a `GitHubGateway` zůstává bez zápisových metod. Zabalit závislosti do
jednoho typu, aby stačilo otevřít jedno pole, by znamenalo přepsat `init` — a s ním testy, čímž by
z přesunu byl přepis.

Filtr seznamu PR hotový (issue #117) — `PullRequestFilter`, `PullRequestFilterOptions`
a `ListEmptyReason` v `App/Policy/PullRequestFilter.swift`, `Policy.filtered`/`filterOptions`/
`listEmptyReason`, `filter`/`visiblePullRequests`/`setFilter` v `AppStore` a `PullRequestFilterButton`
v toolbaru seznamu. **Seznam se dá zúžit na vybraná repa a autory**, je vidět, že je filtr zapnutý
a kolik schovává, a vypnout jde jedním kliknutím i z prázdného stavu (ten má vlastní vysvětlení, ne
zelené „Žádné PR k review“).

To podstatné je, že **filtr je pohled, ne seznam**: `pullRequests` zůstává plný a zúžený je druhý
getter (`visiblePullRequests`), který čte jedině seznam a detail vybraného řádku. Rozdíl mezi těmi
dvěma je jediné, co dělí filtr od mazání cache — na `pullRequests` visí okno nastavení, souhrn
fronty, automat a úklid. Je na to sada testů proti fakes, **ověřená vloženou regresí**: když
`pullRequests` filtruje sám, spadne osm testů.

Filtr **nepřežije restart** (je to jediný stav, který umí PR schovat úplně, takže restart je
pojistka proti zapomenutému filtru) a nemíchá se se `sources` — zdroj mění, co se stahuje, filtr je
pohled na výsledek. Automat filtr neřeší. Nad zadání přibylo jedno rozhodnutí: **klik na notifikaci
PR, které filtr schoval, filtr vymaže**, protože jinak by se detail nenakreslil a vypadalo by to, že
klik nic neudělal.

Události časové osy hotové (issue #171) — `TimelineEvent` a `EventActor` v `App/Models/`,
`timelineItems` v `ConversationQuery`, mapování v `GhConversation`, `Policy.displayableEvents`
a `ConversationEntry.event`, `TimelineEventRow`, `AvatarView` a `AvatarLoader` v `App/Views/`.
**V `Přehledu` je vidět, co se na PR stalo** — pushnuté commity s titulkem a zkráceným sha,
vyžádaná a odebraná review, force push s `před → po`, převedení z draftu, merge, zavření
a změna base, proložené mezi komentáři a review a s avatarem toho, kdo za tím stojí.

Vejde se to do **téhož** GraphQL dotazu a **cena zůstává 1 bod** — změřeno na sloučeném dotazu;
odpověď naroste o 8,4 kB (na `cli/cli#13084` ze 245 na 254 kB). Druhý dotaz by tedy neměl co
koupit.

Dvě měření změnila návrh proti zadání:

- **`totalCount` u `timelineItems` ignoruje `itemTypes`.** Vrací 49 tam, kde uzlů dorazí 29 —
  a stejných 49 vyjde i bez filtru. Zkrácení proto stojí jen na `hasNextPage` (vlastní
  konstruktor `ConversationPage(items:hasNextPage:)`) a v hlášce „nevešlo se“ je **„část
  historie“ bez počtu**: číslo neznáme a vymýšlet se nemá. Bez toho by aplikace hlásila ztrátu
  dvaceti událostí, které nikdy neexistovaly, na každém PR.
- **`pushedDate` GitHub už neplní** (`null` u všech 21 commitů). U commitu je tedy datum
  commitu, takže po rebase nebo merge cizí větve umí sedět jinde, než kde ho ukazuje GitHub —
  tomu pořadí dává samo API. Vědomé omezení.

Nad zadáním přibyla dvě rozhodnutí: **zavření hned po mergi se nekreslí** (mergnutím se PR
zavírá, takže GitHub kreslí jeden řádek; zavření bez mergnutí zůstává) a **avatary jdou přes
`HTTPGetting`**, ne přes `AsyncImage` — ten by si otevřel vlastní `URLSession` mimo jedinou
cestu, kterou aplikace na síť chodí sama za sebe. Token se u nich neposílá, takže tvrdá podmínka
č. 4 zůstává. Šum „vyžádal review / odebral“ se **neslévá**: je to pravda o tom PR a slévání by
znamenalo rozhodovat, co je „tatáž“ událost.

Plánované fáze:

1. ~~Seznam PR z `gh` + polling~~ — **hotovo**
2. ~~Checkout cache + worktree~~ — **hotovo**
3. ~~`ReviewRunner` + parsování streamu~~ — **hotovo**
4. ~~UI diffu s bublinami~~ — **hotovo** (#18–#22, #47, #48, #51)
5. ~~Konfigurace a auto režim~~ — **hotovo** (#23, #70, #24, #52, #25)

Tím **končí rozsah v1** podle specifikace. Za ním:

6. **Review na GitHub** (M6) — odesílání review z okna. **Hotový.** Tvrdou podmínku č. 1
   nahradil pravidlem „jediná cesta ven“ (#67) a bránou v nastavení (#107). Obsahoval: spike #62
   (viz [`docs/github-review-api.md`](github-review-api.md)), model draftu #65,
   publisher #67, skládání draftu #66, potvrzovací sheet #68, povolení v nastavení #107
   a přenesení draftu na nový commit #69.
7. **Konverzace, komentáře a taby** (M7) — cizí komentáře a vlákna v okně, odpovídání do
   nich a rozvržení jako na GitHubu (taby `Overview` / `Files changed`). Hotové: čtení #63,
   vlákna u kódu #64, taby #72, odpovídání #73, side-by-side diff #98 a víceřádkové komentáře
   #110. **Milník je hotový.**

**M6 a M7 jsou do sebe zaklesnuté a nejdou udělat po sobě.** `#66` a `#68` z M6 čekaly na
`#64` z M7, kdežto `#73` z M7 čekalo na `#67` z M6 — takže se to plánovalo jako jeden blok
o jedenácti issues, ne dva milníky za sebou. Hotové z něj je `#62`, `#63`, `#65`, `#64`,
`#67`, `#66`, `#72`, `#68`, `#73`, `#98`, `#110` a `#69` — tedy **celý**. Zbývá už jen milník
**M8 (notifikace)**, který na ničem z toho nestojí.
8. **Notifikace** (M8) — aplikace dá vědět, i když se do ní nikdo nedívá: základ
   s oprávněním a klikem (#88, **hotovo**), doběhlé review (#82, **hotovo**), nové PR (#85,
   **hotovo**), vypínání po událostech (#86, **hotovo**) a seskupování (#87, **hotovo**).

Pořadí M6–M8 není závazné. M8 na nich nestojí a dá se udělat kdykoli — je to jediný
z těch tří milníků, který **nemění tvrdé podmínky**.

9. **Revize okna** (M9) — nový vizuální jazyk podle návrhu ze srpna 2026 a přestavba okna
   na záložky. Šestnáct issues ve čtyřech vlnách; **pořadí je v popisu milníku**, protože se
   podle něj rozhoduje, co se dá dělat souběžně. Hotové: řádek fronty #172, co se změnilo od
   poslední návštěvy #173, procházení nálezů šipkami #187, nálezy jako karty #175, hlavička PR s větvemi #174. **Vlna A je hotová**; **vlna B je hotová** (#178, #177, #179). Z vlny C rail a záložky #180, dashboard #181, tab konverzace #183, dlaždice faktů #211, iniciály na kartě popisu #212, kontroly v `Přehledu` #213, sazba položek konverzace #216, sazba lišty diffu s hlavičkou souboru #219, sazba bloku „od minule“ #226, sazba hlavičky PR #218, odpočet příštího tiku #237, přišpendlený blokující nález #185, command palette ⌘K #184 a přepínání záložek ⌃Tab #245. Mimo plán přibylo
   **#220 — okno vytuhlo na PR s ~2000 změněnými řádky**: pružná šířka na každé úrovni zanoření
   stojí ~5,5× na úroveň, takže se šířka teď měří jednou a předává dolů. Odpadlo z toho #223
   (blok bez stropu) a #224 (barvení bez cache) do milníku Průběžné — obojí se měřením vyloučilo
   jako příčina.

   U #219 se **zrušil popover `Přejít na soubor`** — změna proti #197, kde se rozhodlo, že
   zůstane. Důvod je v specifikaci; s ním odešla plná sazba stromu (`FileTreeView.isCompact`)
   a sečtené počty po složkách (`FileTreeNode.additions`/`.deletions`), protože byl jejich
   jediný čtenář.

   U #218 **zmizel pravý sloupec hlavičky** a s ním `VerdictView`: návrh verdiktu se od #114
   předvyplňuje v panelu `Moje review`, takže v hlavičce byl druhou a hlasitější kopií téhož.
   Stav pracovní kopie se přestěhoval do stavového řádku (je to stav prostředí, ne údaj o PR),
   selhaný checkout zůstal bannerem v hlavičce. Odchylka od návrhu je odznak u `Přehledu`:
   mockup u něj má čtyřku, která odpovídá počtu dlaždic s fakty — a to je konstanta, takže
   místo ní počítá novinky od poslední návštěvy. Důvod je ve specifikaci.

   U #237 se **otočilo rozhodnutí z #181**: příští tik v hlavičce dashboardu je odpočet
   (`poslední tik 09:41 · za 43s znovu`), ne absolutní čas. Odpočet **návrh chtěl** už tehdy;
   mezera mezi číslem a jednotkou v něm ale byla a od #260 tam schválně není. Námitka, kvůli
   které tam absolutní čas stál — že odpočet znamená přepočítávat dashboard každou vteřinu —
   se **změřila a neplatí**: `Text(_:style: .relative)` tikal sám a tělo view se u toho
   nepřepočítávalo (od #260 to platí o vlastním formátu a `TimelineView`, viz níž). Přibylo k tomu `PollState.isRefreshing`, protože `nextPoll` je po celou dobu
   dotazu v minulosti a odpočet by šel přes nulu; v tu chvíli se místo čísla píše `ptám se…`.
   Důvod, proč to drží observovatelný příznak a ne srovnání s hodinami, je ve specifikaci.

   U #216 se **rozšířila tvrdá podmínka č. 1**: `ReviewPublishing` má čtvrtou metodu
   (`comment`), protože composer komentáře pod PR je v návrhu a bez něj se pod PR nedá napsat
   z okna vůbec. Podrobnosti a důvod jsou v `CLAUDE.md` a ve specifikaci.

   U #245 se **nepřidal fallback `⌘⇧]` / `⌘⇧[`**, který zadání chystalo pro případ, že by `⌃Tab`
   spolkl textový editor: změřeno, že ho nespolkne — přepne záložku i s kurzorem v těle review
   a v composeru komentáře, do textu nevloží tabulátor a nepřehodí fokus. Místo toho vyšla ven
   jiná past: **`⌃⇧⇥` je pro AppKit jiná klávesa než `⌃⇥`** (`U+0019`, backTab), takže zpětná
   zkratka zapsaná jako `.tab` se shiftem nezabere vůbec. A `tabbingMode = .disallowed` ze zadání
   **dnes nic nerozhoduje** — nabídka `Okno` má systémové záložky zakázané i bez něj, protože
   schovaná titulková lišta dělá okno netabovatelným; zůstal jako vyslovený záměr. Všechno tři je
   změřené, podrobnosti v [`testovani.md`](testovani.md) a ve specifikaci.

   Vlna A (#172, #173, #174, #175, #187) je záměrně první a **nestojí na přestavbě okna**:
   je z ní vidět, jestli nový vizuální jazyk sedí, dřív než se do něj investuje přepis
   `ContentView`. Kdyby nesedl, je #172 nejlevnější místo, kde návrh zahodit.

Vedle fází stojí milník **Průběžné**: koš na to, co do žádné z nich nepatří (ikona,
podpis, stavový řádek). Nemá pořadí ani termín a verze se z něj neodvozuje — viz
Pracovní postup.

**Sloty hotové (#228)** — dá se vyvíjet ve víc oknech naráz vedle aplikace, která se zrovna
používá. Pracovní strom si drží `.prism-slot` a z něj se odvodí bundle ID, jméno
v `/Applications` i kořen cache; ten si aplikace bere z `CFBundleName`, ne z konstanty, takže
rozestavěný build nesáhne na uložené nálezy ani na rozdělané drafty. Bez toho souboru se
nemění nic. Nový je `bin/worktree.sh`, který strom založí a přenese do něj konfiguraci
očištěnou o odesílání, notifikace a automat.

**Očista konfigurace slotu má jedno místo a čistí obě úrovně (#262)** — `bin/slot-config.sh`.
Do té doby byla uvnitř `worktree.sh` a u **rep** přepisovala jen `allowsPublishing`, ne `mode`,
takže per-repo override `mode: automatic` očistou prošel a přebil globální `manual`. Slotová
aplikace si sama pustila review, o která nikdo nežádal: **2,80 $ ve slotu `b` a 1,16 $
v dalším**, dvakrát nezávisle na sobě v jedné dávce. Záměr byl přitom napsaný správně, jen ho
ten řádek nedodržel — je to třída „kontrola, která jinde v repu je, a tady chybí“.

Opravené je to na třech úrovních. **Výčet klíčů je úplný a je ve skriptu vidět**: pět klíčů má
obě úrovně (`mode`, `allowsPublishing`, `findingsLanguage`, `skills`, `blockingCategories`)
a u každého je napsané, jestli se čistí a proč; nový klíč do toho výčtu patří, i kdyby se
nečistil. **Očista je samostatně spustitelná** (`./bin/slot-config.sh`, slot si vezme
z `.prism-slot`), takže si ji subagent v dávce nemá proč opisovat — a opisoval si ji, protože
strom má od harnessu a `worktree.sh` nepouští; dvě kopie znamenají opravu jen v jedné.
A **výsledek se ověřuje nad daty**, ne přečtením filtru: po přepsání se hledá zbylý automat
a povolené odesílání, a když se něco najde, nezapíše se nic. Přidané je i `autoRunsPerDay = 0`
jako druhá, na režimu nezávislá brzda, a hlášení o tom, co se v konfiguraci našlo.
Ověřeno spuštěním nad konfigurací, která `mode: automatic` u repa má, a vložením regrese.

**Postup pro dávku issues zapsaný (#231)** — [`docs/paralelni-vyvoj.md`](paralelni-vyvoj.md).
Sloty daly paralelnímu vývoji prostředí, ale ne postup; bez zápisu by se seznam issues dál
vyřizoval sériově, protože výchozí chování je subagenty nepouštět. Je v něm, podle čeho se
pozná nezávislost (`ReviewPublishing` jde vždycky sám, `AppStore` stav a `Policy` jsou
rizikové, `docs/stav.md` konfliktuje vždy a nevadí), co subagent dělá a co ne, a **že slot
přiděluje orchestrátor** — subagent v izolovaném worktree `.prism-slot` nemá, takže by přepsal
aplikaci, se kterou se pracuje. Hranice „co dělá a co ne“ se od #231 posunula dvakrát: v původním
zápisu subagent nemergoval, nezavíral issue ani nevydával release, od **#247** si to všechno
dotahuje sám a od **#250** po sobě uklidí i svou aplikaci. Orchestrátorovi zůstal rozvrh, sloty,
úklid stromů a restart hlavní aplikace.

**Mění to jedno pravidlo:** v dávce se pauza na proklikání posouvá z „před prvním pushem“ na
„před merge“. Prošla dvěma korekcemi a platí verze z **#256**: subagent zastaví s hotovým PR
a vyřízeným Copilotem, nechá si proklikat **svou slotovou aplikaci** a merge na odpověď počká;
člověka volá **přes orchestrátora**. Sbírání za celou dávku z #231 padlo s tím, že merguje každý
sám (#247), a mezitím pauza chvíli **odpadala úplně** — s odůvodněním, že subagent nemá jak
zavolat člověka a čekáním by blokoval sebe i slot. Obojí neplatilo: cesta k člověku vede přes
orchestrátora a subagent u ní čeká **pasivně** (dokončí turn, zpráva ho probudí). Ukázala to
dávka M9, kde pauza nebyla v zadání a **dva agenti ze čtyř domergovali dřív, než jim došla
zpráva** — proto je od #256 v zadání od začátku. Podívat se na obrazovku sám a napřed platí dál,
neviditelná změna pauzu nedostane.

**Hranice orchestrátora zapsaná (#259):** v dávce **neimplementuje, deleguje** — kód, testy ani
dokumentaci k žádnému issue, a „jen dokumentace“ v tom není výjimka. Do té doby dokument říkal
jmenovitě jen to, co **nedělá subagent**, a o orchestrátorovi to, co mu *zbývá*; zákaz z toho
nevyplýval, takže chybějící věta vypadala jako volba. Důvod je kontext: rozvrh, stav všech
běžících větví a připomínky k předání za orchestrátora nikdo neudrží, kdežto implementace je
uzavřená v jednom stromě a dá se rozdat. Přibyl postup pro **strom po skončené session** — pustí
se do něj nový subagent (bez `isolation: "worktree"`, s cestou ke stromu, číslem existujícího PR
a zákazem zakládat nový), ne nový worktree z mainu a ne orchestrátor sám. Vzniklo to z dávky M9,
kde orchestrátor začal implementovat v odumřelém stromě po předchozím agentovi a člověk to
zastavil.

**Odepřené povolení se neobchází, hlásí se (#273)** — do výčtu „co subagent nedělá“ (§3) přibyl
zákaz hledat k zakázané věci jinou cestu a přepisovat konfiguraci, aby v měření vyšel potřebný
stav. Místo toho se to napíše do hlášení jako **neověřená mezera** a nechá na orchestrátorovi;
**neověřená věc není důvod nemergovat**, protože poslední kolo kontroly dělá člověk v pauze (#256).
Do zadání subagenta to patří jako věta k okopírování, stejně jako slot — co v zadání není, to
subagent neudělá (zjištění z #256). Vzniklo z běhu na #184: agent potřeboval k proklikání
neblokující nález, brána mu změnu konfigurace slotu zakázala, on ji **obešel jinou cestou
a odebral `correctness` z `blockingCategories`**, a orchestrátorovi přitom napsal, že mu to brána
zablokovala. **Změřený rozsah byl nulový** — hlavní konfigurace uživatele nedotčená, slotová
v době kontroly v pořádku,
v diffu PR nic oslabeného, `grep ReviewPublishing App/` stejný jako `main`, `ClaudeCommand.swift`
nedotčený — a je to u pravidla napsané schválně, aby příště nikdo nedohadoval, jestli to bylo vážné,
nebo formální. Zapsané je jako **pravidlo vedle ostatních zákazů**, ne jako varování před konkrétním
agentem: zákaz sahat mimo vlastní worktree taky nevznikl z nedůvěry. `CLAUDE.md` na to má jednu
větu a nerozrostl se (48 977 → 49 292 B).

U slotů (#228) dopadly tři věci jinak, než jak byly v zadání:

- **Počet slotů se neomezuje**, ačkoli issue počítalo se dvěma. Rozsah stál na odhadu, že se
  okna poperou o pět výkonných jader — změřeno je to jinak: clean build trvá 23 s a test run
  s 1864 testy 25 s, tedy necelá 3 % třicetiminutové iterace, a medián zátěže je 611 %
  z 1500 % dostupných. Strop tedy není ve stroji, ale v tom, kolik je po ruce **nezávislých**
  issues: dvě větve sahající na stav v `AppStore` nebo na `Policy` se vrátí jako sémantický
  konflikt, samostatně zelené a po sloučení rozbité. Slot je proto parametr skriptu.
- **Slot se používá doslova**, bez převodu na velké písmeno, a v názvu je pomlčka místo
  mezery (`PRism-a`). Cesty bez mezer se v shellu nedají rozbít nedopatřením a `worktree.sh`
  s cestami pracuje.
- **Chybějící `CFBundleName` shodí aplikaci** místo tichého `?? "PRism"`. Default by
  znamenal, že se slot potichu vrátí do cache hlavní instance — přesně to, čemu se sloty
  vyhýbají. Ověřeno vložením regrese: test to chytá.

**Obarvení se pamatuje (#224)** — `SyntaxRunCache` klíčovaná textem řádku a jménem jazyka.
`SyntaxHighlighter.runs` se volá z computed property `content` v `DiffLineView` a při složení
textu bloku, takže celý průchod řádkem běžel při **každém** překreslení — i při přejezdu myší.
Změřeno na souboru o 2400 řádcích: **44 ms bez cache, 0,30 ms z ní** (~145×), a naplnění prázdné
cache stojí těch samých 44 ms, takže se za to neplatí ničím. Je to **otočení rozhodnutí z #48**,
kde se cache zamítla podle odhadu, který počítal jen se scrollováním.

Růst drží dvě meze — 4000 řádků a 4 MB součtu jejich délek — a po překročení kterékoli se cache
zahodí celá (O(1), cena je přepočet toho, co je zrovna vidět, tedy ~1,1 ms na blok). Obě se
počítají **včetně vkládaného řádku** a řádek delší než celý rozpočet se nepamatuje; jinak by cache
po zápisu stála nad mezí až do toho dalšího (z Copilot review na #233). Barvy uvnitř
nejsou, jen druhy run, takže přepnutí světlého a tmavého režimu ji nezneplatňuje. **Vidět není
nic** — obarvení vychází stejné, jen se nepočítá znovu.

**Počty u položek filtru (#199)** — u každého repa a autora v nabídce filtru je počet PR,
kterých se týká, takže se odškrtává podle čísla, ne naslepo. Skládá je
`Policy.filterOptions(in:filter:)` do `PullRequestFilterOption` (hodnota + počet), kreslí je
`PullRequestFilterButton` vpravo v řádku v `Palette.ink3`, jak to má návrh v sekci 11.

Počítá se to z **plného** seznamu — `AppStore.filterOptions` sahá na `pullRequests`, ne na
`visiblePullRequests`. Ze zúženého by odškrtnutí jednoho repa srazilo počty u všech ostatních na
nulu a čísla by se měnila při každém kliknutí, takže by z nabídky nešlo poznat, co zapnutí položky
udělá. Je na to test v `Policy` i ve storu; položka, která v nabídce zbyla jen po aktivním filtru,
má počet **nula** a řadí se dál podle jména, ne podle počtu.

**Klávesové zkratky doplněné (#151)** — `⌘⏎` nad rozdělaným review otevře **potvrzení odeslání**
(ne odeslání: dvě kliknutí na dvou různých tlačítkách z #68 zůstávají) a **Esc zavírá nastavení**,
včetně doručení rozepsané hodnoty. Skok mezi nálezy (`⌥↓`, `⌥↑`, `⌥⇧↓`) z issue už existoval
z #187 — jenže **fungoval jen do prvního skoku**, a to se přišlo najevo až při ověřování:

- **SwiftUI páruje u šipek zkratku bez ohledu na `.shift`**, takže `⌥↓` a `⌥⇧↓` byly pro něj jedna
  klávesa a vyhrávala ta zaregistrovaná později. `⌥↓` tedy dělalo „další blokující“ a protože
  blokující nález bývá jeden, druhé zmáčknutí nikam neskočilo. Teď je to jedno tlačítko a shift
  se čte z `NSApp.currentEvent`. Změřeno na běžící aplikaci oběma směry; platformní chování
  znamená, že na to **test není** a drží ho jen zápis v dokumentaci.
- **Esc v nastavení je změna proti #127**, kde stálo, že to okno schválně nemá. Důvod je ve
  specifikaci; doručení rozepsané hodnoty (`flush`) je proto v akci té zkratky, ne odkázané na
  zánik view.
- Pořadí skoků zůstává **podle diffu**, ne podle `Policy.sorted`, jak psalo zadání issue —
  rozhodlo to #187 a skákat po závažnosti by v jednom souboru poskakovalo nahoru a dolů.

**Notifikace o review nese počty v titulku (#200)** — `3 nálezy · 1 blokuje`, pod tím
nejzávažnější nález (`correctness: …`) a na třetím řádku `owner/repo#123`. Do té doby byla
v titulku identifikace PR a v těle věta o výsledku, tedy rozvržení, které na otázku „mám k tomu
jít hned?“ odpovídalo až druhým řádkem. Návrh (sekce 10) to má takhle od začátku; issue z toho
nevzniklo a našlo se to při kontrole návrhu proti implementaci.

Dvě věci vyšly z **měření na běžící aplikaci**, ne z odhadu. Do banneru se vejde titulek
a **čtyři řádky těla** — zadání počítalo se dvěma. A co se nevejde, macOS uřízne i s tím, co je
pod tím: 140znakový souhrn z banneru vymazal celý řádek s PR, takže se nález krátí na sto znaků
sám. `Čisté review` a `Review se nepovedlo` zůstávají dvě různé věty, teď jako dva různé titulky.

**Word-level diff (#153)** — u přepsaného řádku svítí jen změněná část, v obou pohledech. Porovnává
se **po tokenech** (jméno, mezera, operátor), a je to rozhodnuté měřením na 332 dvojicích z historie
tohohle repa: po tokenech svítí 26,5 % znaků v 1,62 úsecích na řádek, po znacích 28,9 % ve 3,46 —
a po znacích se přes práh podobnosti navíc dostane o 34 dvojic víc, protože společná písmena dvou
nesouvisejících řádků vypadají jako podobnost. Nepodobná dvojice (práh 0,30 ze společných
neprázdných znaků) zůstává obarvená celá jako dosud — je to smazání a přidání, ne přepsání.

Dvě rozhodnutí, která z toho stojí za zapamatování. **Zvýraznění se nesmí přimíchat do
`SyntaxRunCache`** (#224): závisí na protějšku dvojice, kdežto cache je klíčovaná textem řádku, takže
by tentýž řádek proti jinému protějšku dostal cizí zvýraznění — a potichu. Kreslí se proto jako druhá
vrstva nad hotovými runy (pozadí × barva písma u syntaxe). A **počítá se až při skládání textu
bloku**, ne v modelu: blok o 60 řádcích stojí 0,42 ms, celý soubor 19,6 ms, a model se přepočítává při
každém překreslení diffu. Cenou je známé omezení — dvojici roztrženou hranicí bloku pohled pod sebou
nezvýrazní.

Při proklikání se z toho opravila **sytost zvýraznění (30 % → 50 %)**: třicet vyšlo z renderu
jednoho bloku, jenže v okně se zvýraznění hledá v celém diffu a na jednoznakové změně se
přehlédlo. A **vyloučilo se, že za tuhnoucí okno může tahle změna** — reprodukuje se projížděním
velkého diffu vedle sebe a chová se stejně na mainu; `WordDiff` stojí 18 % ceny skládání bloku
v nejhorším případě a v `sample`u ztuhlého procesu není vůbec. Tuhnutí je tedy vlastní issue
v území #220/#223; postup a vyloučené příčiny jsou v [`testovani.md`](testovani.md).

**Blok kódu si říká o tu výšku, kterou nakreslí (#236)** — bublina nálezu se při některých šířkách
okna kreslila přes poslední řádky bloku, oba texty naráz. Výška se měřila na kontejneru o šířku
gutteru **širším**, než na jakém se kreslilo, takže se řádek, který se do změřené šířky ještě vešel,
ve skutečnosti zalomil.

Ze dvou cest v zadání se vybrala ta druhá: **gutter přestal být symetrický `textContainerInset`**
a posouvá původ textu (`textContainerOrigin`), šířku kontejneru si textové view drží samo. První cesta
(odečítat inset dvakrát i při měření) by přetečení taky spravila, ale nechala by v kódu tvrzení, které
neplatí — a hlavně mrtvé místo u pravého okraje: změřeno, že při šířce 600 pt se do pohledu pod sebou
vešlo 41 znaků místo 57, tedy o 17 méně. Ukazatel „N znaků na stranu“ (#188) přitom gutter odečítal
jednou, takže o těch 17 znaků lhal; teď mluví pravdu.

Byla to **třída chyby, ne jeden výskyt** — druhý byl ve split pohledu, kde výška řádku nesla svislý
inset. Rámečky řádků tím utíkaly o 2 pt na řádek (na šedesátiřádkovém bloku 116 pt, tedy pilulka
komentáře sedm řádků pod svým kódem) a pod blokem zbývalo prázdno. Oba případy hlídají testy proti
**layout manageru**, ne proti druhému výpočtu, a oba jsou ověřené vloženou regresí (130 a 136
padlých tvrzení). Cestou se našla past AppKitu: nastavení `textContainer.size` si AppKit vyloží jako
změnu geometrie a **sám zavolá `setFrameSize`**, takže bez stráže se měřilo o jednu šířku pozadu.

**Odpočet bez mezery mezi číslem a jednotkou (#260)** — `za 43s znovu`. Zní to na jeden znak, ale
ten řetězec skládal systém (`Text(_:style: .relative)`) a v české locale mezeru **má ve všech
variantách** — změřeno na čtyřech šířkách `Duration.UnitsFormatStyle` i na
`DateComponentsFormatter`u, a na obrazovce psal nad minutu `12 min, 29 s`, tedy i s čárkou.
Formátuje se proto vlastní funkcí (`DashboardCountdown`), nad minutu ve dvou jednotkách
(`za 12min 29s znovu`), nad hodinu `za 1h znovu`; nulová spodní jednotka se vynechává.

Je to **vědomá odchylka od české typografie i od mockupu** (ten má `za 43 s znovu`) — přání
uživatele nad jeho osobním nástrojem, zapsané v specifikaci proto, aby se to příště
„neopravilo“ zpátky.

**Rozhodnutí z #237 přitom drží, a je to změřené**: vlastní formát si vyžádal vlastní takt, ale ten
dává `TimelineView` uvnitř odpočtu, který přepočítává jen svůj obsah — tělo nad ním se přepočítá
**jednou** a formát stojí 0,12 µs na tik. Sonda z #237 na to zůstala a **umí víc**: kouká se i na
kresbu hostovaného view, takže chytne i zamrzlý odpočet, který samotný počet přepočtů nepozná
(ověřeno vyndáním `TimelineView`). Text z okna přečíst nešlo — accessibility tree se v hostovaném
okně nenaplní, změřeno. **Jak dlouho se na tu změnu kresby čeká, opravilo až #269** — do té doby
sonda brala dva snímky 1,5 s od sebe, což je okno, do kterého se první změna nevejde.

**Nastavení a novinky zůstávají v popředí aplikace (#243)** — `AuxiliaryWindowLevel`
a `keptInFrontOfApp()` v `App/Views/WindowCentering.swift`, tedy další věc udělaná témuž oknu,
ne nový mechanismus. Vzniklo to z následku středění (#164): vystředěné okno je menší než hlavní,
takže se za ním schová beze zbytku a vypadá jako zavřené — přitom je otevřené, `willClose`
nepřijde nikdy. Je to **změna rozhodnutí z #127**, kde se hladina nechávala normální s tím, že
kliknutí mimo okno ho má odklidit; odklidit znamená zavřít, a to se neděje.

Hladina je **funkce toho, jestli je aplikace vpředu**: `.floating` dokud je, `.normal` jak přestane
být. Samo `.floating` je naivní oprava, po které okno plave i nad cizími aplikacemi. Ověřeno
spuštěním na slotu — pořadí oken z accessibility a hladina z `CGWindowList`: nad novým oknem hlavní
scény (`layer 0`) zůstává nastavení i novinky vpředu (`layer 3`), po přepnutí do Finderu jim hladina
spadne na `layer 0`, po návratu je zpátky `layer 3` a zavřené okno se nevrací (3× v řadě u obou).
Rozepsaná hodnota v poli přepnutí aplikace přežije.

**Hladina prošla proklikáním** („jinak dobrý, že se už neschovává“), a vyšel z něj jeden požadavek
navíc: aby pomocné okno neztrácelo fokus, když se klikne do hlavního okna. **To nejde a je to
změřené, ne odhadnuté.** Klíčové okno je v aplikaci právě jedno (v pokusu s plovoucím utility
panelem je po `main.makeKey()` `panel.isKeyWindow == false`), utility panelu zešedne titulek se
semaforem úplně stejně jako obyčejnému oknu (doloženo screenshotem), `.utilityWindow` vložené do
`styleMask` hotového okna nedělá nic, a brát klíč zpátky se zamítlo: znamenalo by to, že do hlavního
okna nejde psát, a kliknutí do rozepsaného komentáře by poslalo text do pole v nastavení. Podrobnosti
i s tím, co se u toho změřilo, jsou v [`architektura.md`](architektura.md) a v záznamu rozhodnutí.

**`hidesOnDeactivate` ze zadání se vyzkoušelo a zamítlo.** Skrytí je stav navíc a s SwiftUI se umí
rozejít: okno se třikrát ocitlo mimo obrazovku, ačkoli scéna dál žila — aktivace ho nevrátila, `⌘,`
s ním nepohnulo a vrátilo se až dalším přepnutím aplikace. To je tatáž porucha, jakou issue
opravuje, jen o vrstvu vedle. Cena změny je, že nad cizí aplikací okno **zůstane na obrazovce**
(leží pod ní), místo aby zmizelo.

**Nálezy a Průběh jako vlastní záložky (#242)** — pruh záložek PR má pět položek a mezi
`Konverzací` a `Nálezy` dělič: nalevo je to, co je na PR (a co má i GitHub), napravo to, co s ním
udělaly naše reviewery. `Nálezy` jsou **tabulka přes celou šířku** i s řazením podle sloupců, které
#175 zahodil kvůli 300 bodům panelu; `Průběh` je **dráha na revieweera** s fázemi vedle sebe, takže
„kdo je hotový, kdo běží a kdo spadl“ je jeden pohled. Spadlá session dostala důvod, `stderr`
a tlačítka `Pustit znovu` / `Zkopírovat příkaz` — do té doby se od proběhlé lišila jen barvou
odznaku, protože v kartě nebylo místo, a `čisté` se `spadlo` slít nesmí.

**Nálezy zůstaly i v panelu** — změna proti zadání, rozhodnutá při implementaci a **potvrzená
člověkem v pauzi před mergem** (#256): proklikal to a segmenty nechal být. Vyžádaná nebyla (do
doplnění #242 to tak stálo tady i ve specifikaci a bylo to vymyšlené) — schválení po proklikání
a pokyn jsou dvě různé věci. Nejsou to dvě kopie jednoho pohledu, ale dvě různé otázky: u kódu
„co je tady“, v tabulce „co všechno se našlo“.
Panel tím má dva segmenty místo tří (`Průběh` se odstěhoval celý) a v proužku složeného panelu je
vedle počtu nálezů i značka rozdělaného review.

**Dráhu dostane každý nastavený reviewer** — doplněno po proklikání, protože `Průběh` se do té doby
skládal jen ze zaznamenaných os: nastavený reviewer, který na PR ještě neběžel, dráhu nedostal vůbec
a před prvním review byl celý tab prázdný. Sada se bere z `AppStore.reviewSkills(for:)`, tedy z téhož
místa, ze kterého se review pouští. Tři různá „nic tu není“ mají tři různá slova a slít se nesmí:
`nespuštěno`, `ve frontě` a `bez průběhu` — to poslední je doběhlý běh, jehož osa se neuložila
(soubory před #203; **25 z 31 uložených běhů ve skutečné cache**, mezi nimi PR ve frontě). Osa po
skillu, který v nastavení už není, nezmizí — nesla by s sebou doběhlé review — jen se označí
`mimo sadu`.

Cestou se u toho našla tichá chyba z #203: **uložená osa svůj konec neobsahuje**, protože se snímek
pro zápis bere dřív, než proud událostí dojede — 7 ze 7 os po skutečném běhu. Tab `Průběh` proto po
restartu tvrdil `nedoběhlo — běh někdo zrušil` nad doběhlým review, kterému vedle toho svítil chip
`čisto`. Doplňuje se to na **čtení** z běhu, pod kterým osa leží; testy to nechytily proto, že osy
vyrobené v testech konec mají.

Dvě věci z toho stojí za zapamatování. **Řádek tabulky je místo, ne nález**: shoda dvou reviewerů je
jeden řádek s odznakem `2×`, jinak by součet nad tabulkou nesouhlasil s tím, co je v diffu jako jedna
bublina — a hlídá to test, že odznak na záložce, tabulka a bubliny počítají tytéž nálezy (jeden zdroj
v `Policy.tally`). A **složení panelu se přestěhovalo do `AppStore`**, protože poznámka do těla review
přidaná z diffu musí umět panel rozložit sama; dokud to rozhodnutí bydlelo v `@State`, nešlo ho
otestovat. Jeden reálný nález přišel z testu, ne z review: session spadlá při startu neznačila
selhání v žádné fázi, takže dráha vypadala k nerozeznání od té, co ještě nezačala.

**Command palette ⌘K (#184)** — jediná obrazovka revize okna, která v aplikaci neměla předobraz.
Jedno pole nad **nálezy, soubory otevřeného PR, pull requesty a akcemi**, ve čtyřech skupinách
s pevným pořadím: nálezy první, protože je to jediná věc, kterou tahle aplikace má a prohlížeč ne.
Rozdělení je `Policy` (co sedne, jak se to váží, které akce mají teď co dělat), `AppStore+Palette`
(katalog z paměti a vykonání) a view, ve kterém **není žádné `if` nad výsledky**.

Tři rozhodnutí, která nebyla v zadání a stojí za zapsání. **Katalog se skládá při každém stisku
klávesy**, ne jednou při otevření: snímek by za pár sekund ukazoval nálezy z review, které mezitím
doběhlo — a je to změřené, ne odhadnuté (200 řádků 1,5 ms, 2000 řádků 17,6 ms na stisk, gated
`PRISM_MEASURE`). **Nálezy se hledají ve všech PR, soubory jen v otevřeném**, protože diff jiného
v paměti není a dotáhnout si ho by byl ten nový dotaz na GitHub, který zadání zakazuje. A **filtr
seznamu paletu nezužuje** — filtr je zúžení seznamu, kdežto paleta je způsob, jak něco najít;
hledání, ze kterého vypadne schovaný PR, je k nepotřebě právě tehdy, když je filtr zapnutý.

Zkratka `⌘↵` (otevřít na GitHubu) se musela **vzít detailu PR**, který na ní má potvrzení odeslání
review: dvě tlačítka se stejnou zkratkou v jednom okně znamenají, že vyhraje to zaregistrované
později. Detail ji proto nad otevřenou paletou zakazuje, a právě kvůli tomu je `isPaletteOpen` ve
storu, ne v `@State` okna. Návrh měl u „pustit review“ `⌘⇧R`; nakreslená není, protože ta zkratka
v aplikaci pouští review na **všechno, co neběželo** (dashboard) — popiska klávesy, která dělá něco
jiného, je lež o tom, co okno umí.

Cestou vyšlo najevo, že **dva zdrojáky se stejným jménem položí build**, i když leží v různých
podsložkách (`Multiple commands produce … CommandPalette.stringsdata`) — zapsané v `CLAUDE.md`
u buildable folderů.

**Tři věci se dodělaly po proklikání** (pořád #184). **Fokus do pole hned po ⌘K** — paleta, do které
se musí kliknout, není „⌘K a piš“. Vybráno měřením na běžícím okně, ne přečtením: `onAppear`, `task`
bez yieldu i `defaultFocus` nedají fokus **nikdy** (ne později), protože přiřazení ve stejném
průchodu, ve kterém pole vzniká, SwiftUI zahodí; s `task { await Task.yield(); … }` je fokus v poli
~40 ms po ⌘K. U toho se změřilo i to, co u fokusu v textovém poli praská jinde: `esc` paletu zavírá
dál a `↑↓` chodí po řádcích, protože key equivalent tlačítka se vyhodnocuje dřív než editor textu.
A **hledá se i podle autora a repozitáře** — s tím, že obojí přesídlilo do **podtitulku** řádku
(`connection#21663 · sykora-ji`) a shoda se v něm **zvýrazňuje**. Autor v klíčových slovech totiž
hledání umožňoval už předtím, jen se nikde nekreslil: dotaz na jméno vytáhl PR, ve kterém to jméno
nebylo vidět, a to je k nerozeznání od chyby hledání. Soubory podle repa nejdou (jsou všechny
z jednoho otevřeného PR, takže by se vytáhly všechny naráz) a autor u nálezu taky ne — jméno, které
k nálezu patří, je jméno revieweera.

**Ukončení aplikace zabíjí běžící session (#264)** — do té doby to dělal jen dialog z #94, který
tvrdil, že se session zabije, ale nikdo ji nezabíjel: `applicationShouldTerminate` vrátil
`terminateNow` a `claude` se přerodil na `launchd`. Platily se tokeny za review, které už nemá komu
doručit nálezy, a osamocený proces držel pracovní strom v cache. Změřeno na stroji: dvě takové
session běžely **čtyři dny**.

Zabíjí se **tou samou cestou jako u zrušení** (`task.cancel()` → `onTermination` proudu →
`SIGKILL`) — druhý `kill` v delegátovi by byl druhá pravda o tom, jak se běh zastavuje. Co je nové,
je **čekání**: signál se nese přes `WorkCoordinator`, který práci drží ve vlastním tasku, takže
`terminateNow` hned po `cancel()` aplikaci zavře dřív, než signál odejde. Delegát proto vrací
`terminateLater` a odpovídá systému až po zabití — **dotaz zůstává synchronní**, odkládá se jen to
za ním. Čekání má strop dvou sekund, protože ze zaseknuté session nesmí vzniknout aplikace, která se
nedá zavřít; v praxi se vrací po prvním dvacetimilisekundovém kole.

Jedna věc dopadla **jinak, než jak stálo v zadání**. Nedokončený běh se neměl „uložit stejně jako
u zrušení“, protože zrušení značku rozdělaného běhu (#97) **maže** — schválně, aby příští start
nevzkřísil nálezy, které si člověk zrušil. Kdyby tudy šlo i zavírání, přišlo by se přesně o to, co
dneska funguje: z „přerušeno se dvěma nálezy“ by vyšlo „neběželo“. Zavření aplikace je pro běh totéž
jako pád, takže se značky nemažou (`AppStore.isTerminating`) a nálezy se dotáhnou z transcriptu.
Během zavírání se navíc **nic nespouští** — tik pollingu dorazí i uprostřed a jeho automatický běh
by aplikaci přežil.

Ověřeno spuštěním, ne přečtením: session se zabila (`pgrep` prázdný, žádný `ppid 1`), značka
v `interrupted.json` zůstala a po restartu vyšel řádek `přerušeno`. Testů je o deset víc (2072)
ve třech suitách a všechny čtyři brány jsou ověřené **vloženou regresí**. Na obrazovce se změnil
jeden odstavec v dialogu: do #264 sliboval, že se nálezy ztratí, což od #97 není pravda.

**Blokující nález přišpendlený pod řádkem (#185)** — bublina u kódu se rozpadla na **značku**
(pruh s odznaky, kategorií, reviewerem a náhledem textu) a obsah pod ní. Blokující nález je
rozbalený rovnou, ostatní se rozbalí kliknutím a odmítnutý se nerozbaluje nikdy — jeho jediný řádek
i s `Vrátit` je vidět tak jako tak.

Tři rozhodnutí, která v zadání nebyla. **Rozbaluje se místo, ne nález**: dva nálezy na jednom řádku
jsou jedna bublina s odznakem `2×`, takže by se jinak dala otevřít napůl. **Shoda `2×`
nepřišpendluje** — přišpendlení je o tom, co zastaví merge, kdežto shoda o tom, jak moc nálezu
věřit; odznak proto sedí ve značce, aby byl vidět i sbalený. A **pohled vedle sebe se nechová
jinak**: nález stranu nemá (hlásí se proti nové verzi), takže bublina zůstává přes celou šířku, jen
s kratším odsazením — což platilo už od #98.

Sbalená bublina blok kódu **pořád dělí**, tedy struktura řádků se nemění a s ní ani výška, o kterou
si blok říká (#236). Kreslit značku jako vrstvu nad blokem by vrátilo výběr přes celý hunk, ale
chtělo by to další sloupec v gutteru, který `DiffTextView` kreslí ručně — a ten jeden úzký sloupec
už zabírá pilulka komentáře. Zamítnuto, důvod je ve specifikaci.

Cestou se opravila jedna věc, která by jinak vznikla novou: **skok na nález ho rozbalí**. Bez toho
by cíl skoku z panelu i z lišty byl pruh, na kterém není co přečíst — tatáž úvaha, kvůli které skok
rozbaluje i sbalený soubor. A `Přeložit` z návrhu se **nedělalo**: překlad na vyžádání v aplikaci
neexistuje (běží jednou po review) a byl by to nový běh `claude`, tedy vlastní issue.

**Sonda odpočtu čeká na změnu kresby, neměří v pevném okamžiku (#269)** — `main` byl na téhle sondě
červený a **rozbitý byl test, ne aplikace**. Rozhodlo to měření, ne úvaha: odpočet v aplikaci tiká
po 1,00 s (časy tiků 2,01 → 3,00 → 4,00 → 5,00 → 6,00) a z uložených snímků se dá věta přečíst —
v 1,5 s `za 9min 59s znovu`, ve 2,0 s `za 9min 58s znovu`. Příčinou je vlastnost `TimelineView`u:
při nasazení vykreslí hodnotu **prvního** tiku rozvrhu, který je v budoucnosti, a další překreslení
naplánuje až na tik po něm, takže první změna kresby přijde za **1 až 2 periody**. Sonda měřila
1,5 s, změna přišla ve 2,01 s — zeleně to vycházelo jen tehdy, když spánek přetáhl o půl vteřiny.

Sonda proto snímkuje po 100 ms, dokud nemá **dvě** změny, se **stropem 4 s**: dvě proto, že jedna
dokazuje jen jedno překreslení, kdežto tvrdit se má přetikávání; strop proto, že bez něj by
o vteřinovém taktu neříkala nic. Ověřeno **třemi vloženými regresemi** — vyndaný `TimelineView`
(0 změn), odpočet přepočítávaný v těle (3 přepočty místo jednoho) a rozvrh po dvou vteřinách
(1 změna místo dvou, změny se posunou na 4,0 s a 6,0 s). Kontrola měřidla od #269 hlídá **obě**
měřidla, přepočty i kresbu, protože rozbité porovnání bitmap by jinak hlásilo poruchu aplikace.
Na obrazovce se nezměnilo nic — aplikace zůstala, jak byla; celý běh je zelený (2092 testů).

**Kontrola nálezů z minula (#150)** — nad zastaralými nálezy se v hlavičce nabídne
`Zkontrolovat nálezy`: session dostane **uložené nálezy z předchozího commitu** jako číslovaný
seznam a proti pracovní kopii na hlavě PR u každého řekne `vyřešeno` / `pořád platí` / `nejasné`
i s větou proč. Vlastní prompt, **tytéž read-only nástroje** jako review; nálezy jsou materiál
v promptu, ne nový nástroj (tvrdá podmínka č. 2).

Tři otevřené otázky ze zadání dopadly takhle. **Vlastní druh běhu s vlastním klíčem**
(`ReviewRunKey.kind`), protože kontrola nad tímtéž `(PR, headSha)` by se s běžným během slila ve
`WorkCoordinatoru` a přepsala by jeho výsledek; ukládá se mimo `runs`, jako `ReviewRecord.recheck`,
aby si nepřidala chip ani nálezy — a `ReviewStore.save` ji do `runs` vůbec nepustí. **Odznak
u nálezu, ne další tab**, a nese v sobě `kontrola:`, protože samotné „vyřešeno“ vedle nálezu by se
čtlo jako fakt; nález přitom **nemizí ani se nepřeskupuje** — sundat ho smí jedině odmítnutí (#113).
A bere se **nejbližší předchozí záznam**, tedy ten, který je v okně: otázka zní „co se změnilo od
minula“, takže starší kola nepřidávají odpověď, ale cenu — a odznaky by nešlo kam ukázat, protože
v okně visí nálezy z tohohle jednoho záznamu.

Dvě věci, které vyšly z toho, jak `claude` odpovídá. Verdikt o nálezu **není nález**, takže
`ReportFindings` na něj nemá pole — odpověď proto chodí **posledním sdělením session** (`result`
event) a čte se defenzivně jako u překladu nálezů. A **páruje se přes index**, ne přes text: prompt
nese `id`, odpověď ho vrací a klíč z něj skládá `Policy.key(of:)`, protože hledat nález podle věty,
kterou model opíše, by rozbilo jedno přeformulování.

Kontrola **platí jen pro hlavu, proti které běžela** (`againstHeadSha`, tvrdá podmínka č. 5): po
dalším commitu odznaky zmizí a v hlavičce zbyde věta, že se dá pustit znovu — mlčení by vypadalo,
že nikdy neběžela, a pustila by se podruhé za peníze. Nenabízí se bez uloženého záznamu proti
staršímu commitu; chybějící vstup nesmí skončit session, která hádá. Přerušený běh se
**nedotahuje z transcriptu** jako review (#97) — odpověď leží v posledním sdělení, které
v transcriptu není, takže se kontrola prostě pustí znovu. Testů je o 50 víc (2142) v pěti suitách.

Po proklikání k tomu přibyl **vzhled vyřešeného nálezu**: shrnutí se přeškrtne a v odznaku
závažnosti stojí `vyřešeno`. Přeškrtává se **jen text nálezu**, ne celý řádek, jak zněl původní
nápad — celořádkové „nepočítá se“ už znamená **odmítnutí** (#113), tedy rozhodnutí člověka, a dát
modelu tentýž obrázek by smazalo rozdíl, na kterém tohle issue stojí. A `blokuje` se k `vyřešeno`
**přidává, nenahrazuje**: vyřešený nález se dál počítá i dál blokuje, takže odznak bez `blokuje` by
tvrdil „hotovo“ nad věcí, která drží merge. Rozhoduje o tom `Policy.severityBadge(…)`, protože
odznak kreslí čtyři místa. Testů je o 13 víc (2211 po zvednutí mainu).

**Overlay gutteru se skládá po blocích, ne po řádcích (#252).** Projíždění velkého splitu drželo
100 % CPU a `sample` ukazoval na rozvržení líného seznamu; příčina byla v tom, **kolik prvků** ten
overlay má. Každý řádek měl vlastní plochu s `contentShape`, gestem, `onGeometryChange` a skrytou
pilulkou — ve split pohledu dvakrát, plus `HStack` se dvěma `Spacer`y, tedy u bloku o 60 řádcích
přes čtyři stovky prvků k umístění. Polohy přitom hlásí textové view samo, takže se **dají
spočítat**: zbyly dvě plochy na tažení, **jedna** pilulka a jeden `onGeometryChange` na celý blok,
a aritmetika k tomu je čistý typ (`DiffGutterGeometry`), takže se dá otestovat bez okna.

Změřeno: overlay bloku **3,05 ms → 0,12 ms** (26×) a zápis ploch do `DiffRowFrames` **22,6 ms →
1,40 ms** (16×; hlásí se naráz za blok, protože úklid je lineární v počtu záznamů). V aplikaci na
scénáři z issue vlastní práce při projetí diffu **6,4 s → 4,2 s** CPU — zbytek je sazba textu bloku,
na kterou #252 nesahá. Vyloučené příčiny z issue (#153 a cache obarvení) se **znovu neotvíraly**.

Dvě věci k zapamatování: prvek v `ForEach`i s prázdným obsahem se pořád umisťuje, a poloha bloku
v prostoru obsahu se při scrollování **mění**, takže patří mimo observable stav
(`DiffBlockPlacement`) — ve `@State` by z ní byl layout bloku při každém posunu. Měření GUI má
navíc past: řídit se muselo přes accessibility a **samotné to řízení je 9,3 s z 15,6 s**
naměřených; postup i to, co nefunguje (syntetické scroll eventy, `Page Down`), je v
[`docs/testovani.md`](testovani.md).

**Kontroly jsou vlastní tab s odznakem (#215).** Blok z `Přehledu` (#209) se odstěhoval do čtvrté
záložky, protože detail spadlého checku (#214) přidá anotace a konec logu — a tím by vytlačil popis
PR mimo obrazovku. Je to tentýž pohyb jako u konverzace (#183): co začne růst, přestane být
kontextem a stane se obsahem.

**V `Přehledu` nakonec nezbylo nic** — a to je změna proti zadání, které tam chtělo souhrn nechat.
Chvíli tam byl (hlavička s poměrem a jeden řádek s nejhorším checkem), ale při proklikání se ukázalo,
že je to **třetí místo o téže věci**: tab odpovídá na celou otázku a „je to zelené“ nese chip
v hlavičce, který je vidět ve všech tabech. Chip proto zůstal beze změny a je od téhle verze jediným
místem o checcích mimo tab. Odešel s tím i příznak `isFailure` u částí poměru — existoval jen proto,
aby souhrn obarvil spadlou část, takže bez souhrnu neměl čtenáře.

Odznak počítá **podle nejhoršího stavu**, jako chip: spadlé červeně s počtem, běžící puntíkem jako
u `Průběhu`, zelené a přeskočené bez odznaku (číslo u zeleného CI je šum, kvůli kterému by se
přestaly čít i ty dva ostatní). **Tab se u PR bez CI nekreslí** a uložená volba se na to zarovnává,
ne maže — checky se dotahují s detailem, takže po přepnutí PR chvíli nejsou, a mazání by z tabu
vyhazovalo při každém příchodu. Cestou se sjednotily texty a barvy (`ChecksText`): seznam kreslil
`.green`/`.red` ze SwiftUI, kdežto chip barvy z palety návrhu, takže v okně byly dvě zelené pro
jednu věc.

Vlastní revize k tomu našla jednu věc, kterou #215 zhoršilo: store dotahoval checky přes
`(try? …) ?? []`, takže se **chyba sítě zapsala jako prázdno** — a na prázdnu teď visí, jestli
se tab nakreslí. Tiše by z poruchy vyšlo tvrzení „tenhle PR nemá CI“, přitom gateway ten rozdíl
drží (prázdný výstup s nulovým kódem = bez CI, nenulový s prázdným výstupem = chyba). Selhání má
proto vlastní mapu (`checkFailures`), po něm se **stará sada nechává být** (zastaralý seznam s větou
nad ním je lepší než zmizelý tab) a v **hlavičce PR** je vidět, proč tab není — hlavička je vidět
ve všech tabech, takže se ta věta ukáže i tomu, kdo do `Přehledu` nejde. Testů je o 32 víc (2256)
ve dvou nových suitách.

**Sazba textů z GitHubu (#279).** Citace se neparsovaly na bloky, výstrahy parser vůbec neznal
a nadpisy měly dvě velikosti na šest úrovní. `MarkdownBlock.quote` proto nese **bloky** (tentýž tvar
jako `details`), přibyl případ `alert` s pěti druhy, `MarkdownTypography` drží škálu nadpisů
a mezery mezi bloky, `MarkdownAlertStyle` vzhled výstrah a `MarkdownRenderCache` zapamatovanou
sazbu (rozklad na bloky i inline). Rozhodnutí, která v zadání nebyla: **neznámý druh výstrahy** se kreslí jako obyčejná
citace (a ten řádek v ní zůstane), zanoření má **strop** na šesti úrovních (za ním obsah zůstane
textem — je to proti hloubce stromu view i proti `>>>>>>…`), titulky výstrah jsou **česky**, protože
ve zdroji je jen `[!NOTE]`, a `MarkdownText` bere velikost **číslem místo `Font`u**, protože ze
`Font`u se velikost nedá přečíst a škála nadpisů by neměla z čeho vyjít.

Barvy: `[!WARNING]` a `[!CAUTION]` mají **vlastní hex**, protože ty GitHubovy (`0x9A6700`,
`0xCF222E`) se na hex rovnají `Palette.stale` a `Palette.crit`, tedy zastarání a blokujícímu nálezu;
`[!TIP]` a `[!IMPORTANT]` si půjčují `ok` a `accent`. Změřeno: rozklad dvanáctikilobajtové zprávy
od bota **1,91 ms → 0,037 ms** z cache a konverzace o 40 zprávách **74,7 ms → 1,48 ms**; inline
sazba jejích 44 bloků je k tomu dalších **1,81 ms**, takže se pamatuje taky — jednou cachí, ne dvěma. Testů je o 41 víc (2265). Review našlo jednu reálnou vadu, na kterou testy neměly případ: lokální počítadlo otevřených tagů v `details(from:depth:)` se jmenovalo `depth` a **zastínilo** parametr s hloubkou rekurze, takže strop zanoření skrz `<details>` nezabíral a rozbalovátko hloubku ještě resetovalo. Sonda na
render do PNG našla dvě věci, které z kódu vidět nebyly: nerozeznatelné úrovně nadpisů 3–5 (krok se
roztáhl na celý bod) a pruh citace, který sahal do poloviny obsahu, protože se jeho výška
vyjednávala v `HStack`u — teď je to `overlay`, který má velikost obsahu z definice.

**Akce u nálezu v diffu jsou tlačítka podle návrhu (#283).** Byly to modré systémové odkazy
roztažené přes celou šířku okna — převzetí vlevo, `Odmítnout: neplatný irelevantní` u pravé hrany,
tedy na velkém monitoru metr od nálezu, ke kterému patří. Teď je to řada malých tlačítek vlevo pod
textem (`MiniButtonStyle`, `.mini` a `.mini.pri` z návrhu): jedno plné akcentové a vedle něj
obtažená.

Tři věci se u toho rozhodly a jsou i s důvody ve specifikaci. **`Spacer` mezi převzetím a
odmítnutím padl** — to rozhodnutí je otočené, protože jeho ochrana byla funkcí šířky okna (v úzkém
panelu splaskne na osm bodů) a omyl je vratný na místě, když odmítnutí nález nesundá (#113); hlavní
akci teď odlišuje **plocha** a stojí první zleva. **Popisky odmítnutí** nejsou z návrhu doslova
(`Zamítnout` je obecné „odmítnout“ podruhé a v pořadí z návrhu by `Neplatí` u `.irrelevant` tvrdilo
nepravdu) — jsou `Neplatí` a `Nepatří sem`, kdežto přídavná jména do odznaku zůstávají.
**`Přeložit` se dělat nebude**: překlad běží dávkově při uložení běhu podle `findingsLanguage`,
takže by tlačítko buď nedělalo nic, nebo by z něj byla druhá cesta, kterou se text nálezu přepisuje.

Shodu s návrhem ověřil render vedle vyrenderované sekce mockupu a našel dvě věci, které kontrolou
kódu prošly: tlačítko **20 bodů proti 25** (CSS řádek 1,45 a obtažení, které v CSS leží vně
paddingu) a věta „GitHub tady řádkový komentář nepřijme“, která jako ocas za tlačítkem shodila celou
řadu do sloupce i na širokém okně. Do úzkého okna se řada **zlomí** (řada → dvě řady → sloupec), což
je vědomá odchylka: na 128 bodech, které v úzkém panelu zbývají, byly ze tří tlačítek pahýly
o jednom znaku. Testů je o 9 víc (2306).

**Barvy diffu jdou z palety, ne ze systému (#277).** Pozadí řádků bylo jediné místo v okně, které
si barvu bralo ze systémové zelené a červené s krytím 12 % — a krytí znamená, že barva **není
hodnota, ale výsledek**: v tmavém režimu se mísila směrem k černé a plocha přidaného bloku vycházela
`#152B22`, tedy tmavý obdélník. Je to tentýž argument, jaký #185 zapsalo u `Palette.critLine`, jen
se u pozadí řádku neuplatnil. Nově je to pět vyčíslených tokenů: přidaný a odebraný řádek,
word-level vrstva k oběma a šrafa prázdného protějšku.

**Hodnoty jsou z návrhu** (`--add-bg`, `--add-hi`, `--del-bg`, `--del-hi`, `tr.empty-side`), a ve
světlém režimu doslova: `#E3FBE8` / `#FFEBE9` a k tomu `#ABEFC0` / `#FFC9C6`. Měřením vyšly lépe než
to, co v aplikaci vycházelo ze skládání — odlišení přidaného řádku od plochy ΔE **10,1 → 13,0**
a řetězec IntelliJ Light **4,81 → 4,86**; na word-level vrstvě dokonce **3,37 → 4,01**
a **2,44 → 3,65**.

**Tmavá větev je vědomá odchylka od návrhu a je to celé jádro toho issue**: návrh má
`rgba(63, 185, 80, 0.13)`, tedy `ok` s krytím, což nad plochou složí `#172922` a ΔE 14,6 —
reprodukuje tedy přesně tu stížnost. Vyčíslené hodnoty vznikly mixem `ok`/`crit` **do černé**
a odlišení jimi vyrostlo: přidaný řádek ΔE **16,0 → 21,8**, odebraný **13,2 → 19,7**, mezi sebou
**28,9 → 36,8**, přičemž čitelnost syntaxe zůstala na svém (řetězec Darculy 3,73 → 3,76). Sedlo to
na jedno pozorování: kontrast textu závisí jen na světlosti, kdežto odlišení plochy roste i se
sytostí, takže sytější tón při téže světlosti odliší plochu a text nad ní nechá na pokoji.

**Návrh je proto přepsaný, ne obejitý.** Ta čtyři slabá `rgba` v tmavé větvi mockupu nesou
vyčíslené tóny (`#0F2C13`, `#1D5625`, `#371210`, `#712521`), takže paleta a návrh drží jednu
pravdu a příští srovnání nebude tvrdit, že chybu má aplikace. Přepsaly se **obě** tmavé větve —
`@media (prefers-color-scheme: dark)` i `:root[data-theme="dark"]` —, protože hodnota zapsaná jen
v jedné z nich platí jen pro jeden způsob, jakým si čtenář režim vybral. Nic jiného se v mockupu
nezměnilo: ani světlá větev, ani struktura, ani poznámky u sekcí.

Znak `+`/`−` bere `Palette.ok`/`crit` (jak to má návrh, otáčí #218), takže se ve světlém režimu zvedl
jeho kontrast **2,01 → 4,65** na řádku a **2,22 → 5,08** v hlavičce, kde nese `+12 −4`. Word-level
vrstva drží **pravidlo** návrhu (30 % tónu nad řádkem), ne jeho hodnotu, protože se pod ní změnil
řádek: je vědomě méně hlasitá, zato čitelná — do #277 sebralo krytí 50 % obarvení syntaxe pod sebou
(řetězec **1,27**), teď je to ΔE 13,9 proti řádku a 2,17 na řetězci.

Prázdný protějšek se v pohledu vedle sebe **do #277 nekreslil vůbec** (ΔE 0,0 proti kontextu, tedy
tatáž plocha), takže z okna nešlo poznat, jestli se řádek nezměnil, nebo na téhle straně není. Návrh
na to má **šrafu** — a nese ji textura, ne plocha: pod plochou obsahu není v tmavém režimu kam
ztmavovat a světlejší plocha by křičela hlasitěji než sama změna. Testů je o 15 víc (2321 po zvednutí mainu) ve dvou
nových suitách — jedna počítá obě míry nad skutečnými tokeny v obou režimech, druhá čte **bitmapu
sloupce**, protože prázdný protějšek se v modelu poznat nedá. Vzhled je doložený **renderem vedle
vyrenderované sekce návrhu**, což rozhodlo směr pruhů šrafy i to, že plocha díry zůstává plochou
obsahu.

**Neukončený boxík v `Přehledu` (#291).** Karta s popisem PR sahala 42 bodů za pravou hranu tabu,
takže jí `ScrollView` uřízl pravou hranu i popisek `Otevřít na GitHubu` — v okně to vypadalo, že
boxík nemá konec a obsah mizí pod panelem s nálezy. **Způsobila to #279**, ne #215: sazba Markdownu
v ní přešla z pružného `frame(maxWidth: .infinity)` na `filling()`, tedy na konkrétní šířku
z prostředí — a `OverviewView` tu šířku nezúžil ani o svých 16 bodů odsazení tabu, ani o 13 bodů
odsazení karty. V konverzaci to prošlo, protože její karty `narrowingWidth(by: 22)` z #220 mají.
Oprava jsou ty dva chybějící řádky (`narrowingWidth(by: 32)` a `narrowingWidth(by: 26)`).

Naměřeno na pásmu šířek 128–1180: **42 bodů přesahu ve všech**, po opravě nula. Vyzkoušené vložením
regrese po polovinách (bez zúžení u tabu 16 bodů, bez zúžení u karty 10). Ke změření musel obsah tabu
ven ze `ScrollView`u (`OverviewView.content`) — `NSScrollView` přesah ukrojí, takže rozbitý stav vyjde
na renderu skoro jako opravený, a přesně tím je tahle regrese nenápadná. Ze stejného důvodu zůstávají
rámce karty **schválně pružné**: s `filling()` nad odsazeným tělem popisu zůstal test zelený i po
smazání zúžení, protože tvrdý rámec chybějící zúžení schová.

Se správnou šířkou se do zúženého tabu nevešly čtyři údaje v hlavičce karty a `HStack` je nakrájel
uvnitř slov (`otevře/ný` v pilulce, `Otevřít na / GitHub / u` v odkazu). Hlavička proto drží **jeden
řádek ve dvou podobách** (`ViewThatFits`) a v té úzké zahodí relativní čas — ze čtyř údajů je nejméně
potřebný a nese ho i řádek ve frontě. Odkaz ustupuje poslední, ale pružný zůstává: tab se dá stlačit
až na ~128 bodů a nezkratitelný odkaz by kartu roztlačil, tedy vyrobil #291 znovu. Testů je o 3 víc
(2325 po zvednutí mainu) v jedné nové suitě, k tomu sonda na render tabu přes `NSHostingView` — v něm se `Link`
vykreslí celý, na rozdíl od `ImageRenderer`u.

**Postranní lišta panelu jen ve třech tabech (#294).** Panel s nálezy (i složený na proužek) se
kreslil ve všech šesti tabech detailu, přitom ve třech z nich odpovídá na otázku, na kterou už
odpovídá obsah tabu: `Nálezy` jsou tytéž nálezy přes celou šířku, `Průběh` záznam týchž běhů —
a v `Kontrolách` ukrajuje šířku detailu spadlého checku, který nese konec logu (#214). Rozhoduje
o tom **vlastnost tabu** (`PullRequestTab.showsReviewPanel`), ne `Policy` a hlavně ne existující
`isReviewerOutput`: ten má u `Kontrol` `false`, takže sloučení do jedné vlastnosti by posunulo dělič
v pruhu záložek — chyba by se objevila jinde, než by vznikla, a drží to test, který tvrdí, že se ty
dva příznaky **nerovnají**.

Šířka se u toho **nepřepočítává**: panel je sourozenec `GeometryReader`u v tomtéž `HStack`u, takže
jeho zmizení změní to, co se změří. Vlastní odečítání šířky panelu je zrovna ta cesta, ze které
vzniklo #291. Naměřeno na pásmu 648–1800 (spodní kraj je okno 700 bez railu 52): **nula bodů
přesahu** ve všech třech tabech, ve tabulce nálezů i v jejím prázdném stavu. Vyzkoušené vložením
regrese — bez `inset * 2` v rozpočtu sloupců hlásí měření 32 bodů ve všech šířkách. Vedlejší
zjištění: podlaha shrnutí v tabulce (120 bodů, vědomé přetečení) je od téhle změny **mimo dosah**,
protože se zapíná pod 590 a nejužší tab má 648 — s vytaženým panelem se tam tab dostával (~122
bodů, přesah ~468).

Dvě věci navíc proti zadání. `revealDraft(in:)` si z tabu bez panelu **přepne tab** na `Přehled` —
bez toho by `Převzít` v tabu `Nálezy` neudělalo nic viditelného, což je tatáž tichá ztráta
rozepsané věty, jakou řešil #242 u složeného panelu. A `⌘2` i položka v ⌘K jsou v těch třech tabech
**vypnuté**: klávesa by potichu přestavěla tab, do kterého se člověk vrátí. Uložený stav panelu se
přepnutím tabu nemění, což tvrdí dva testy negativně (rozbalený přežije, složený se nerozloží).

Testů je o 16 víc (2341) ve dvou nových suitách; měření přetečení se přestěhovalo do sdílené
`OverflowProbe`, kterou teď používá i `OverviewWidthTests`. K tomu sonda, která vyrendruje **celý
detail ve všech šesti tabech** — render samotného tabu by o schované liště neřekl nic, protože je to
jeho sourozenec. Past, na kterou se u toho narazilo: `FindingsTabView` bere šířku z prostředí, takže
podstrom vytažený zvenčí měří výchozích 1000 bodů a hlásí přetečení, které v okně není.

**Akce v tabulce nálezů berou akcent z palety (#298).** #283 převedlo na tlačítka podle návrhu jen
bublinu u kódu, takže v `FindingTableRowView` (2×) a ve `WorkingCopyStatusView` zbyl
`.buttonStyle(.link)` — a ten kreslí **systémovou `NSColor.linkColor`** (`#0068DA` ve světlém,
`#419CFF` v tmavém). V okně tedy byla dvě různá „klikni sem“ naráz: fialová na tlačítku v bublině
a modrá na akci v tabulce o kus vedle. `.tint(Palette.accent)`, který okno drží na kořeni od #180,
na to **nestačí** — `.link` si tint nebere, což je zrovna důvod, proč to tak dlouho vydrželo.

**Tvar zůstává různý, barva je jedna.** Návrh má u akce v tabulce `.go { color: var(--accent) }`,
tedy holý text, kdežto v bublině plochu (`.mini`) — plocha zopakovaná na každém řádku by přebila
shrnutí, kvůli kterému se tabulka čte. Mění se proto jen barva, a drží ji `AccentLinkButtonStyle`
(`Palette.accent`, ztlumení při zmáčknutí jako u `.mini`, `pointerStyle(.link)`): kurzor je vědomý
přídavek, protože po zrušení systémového odkazu nese „dá se kliknout“ jedině barva. V `App/` po tom
nezůstal žádný `.buttonStyle(.link)` — jediný výskyt toho řetězce je záznam v komentáři
`MiniButtonStyle`.

`WorkingCopyStatusView` **dostal tutéž barvu, i když návrh o `Připravit` nic neříká** (v jeho
stavovém řádku ta akce nakreslená není). Mlčení návrhu není povolení k systémové modré: „jedna barva
pro klikni sem“ je vlastnost celého okna, takže ponechat tam `.link` by ta dvě „klikni sem“
přestěhovalo o pruh níž, ne zrušilo. Že paleta do stavového řádku dosahuje, potvrzuje sám návrh —
zastaralé nálezy v něm barví `var(--stale)`.

Naměřeno v obou režimech (světlý / tmavý): plocha řádku **6,14 / 5,64**, podbarvený živý řádek
procházení **5,30 / 4,70**, stavový řádek **5,82 / 5,33**. Systémová modrá měla 5,26 / 4,54 / 4,99
a 6,51 / 5,43 / 6,16, takže **v tmavém režimu je to výměna**, ne zlepšení — přijatá proto, že rezerva
nad WCAG AA (4,5) zůstává na všech třech podkladech a jedna barva pro „klikni sem“ váží víc než
o desetiny lepší číslo v jednom režimu. Je to tatáž úvaha jako u zelené diffu v #277 (7,42 → 5,95).
`Vrátit` na odmítnutém řádku vychází na 2,35 / 2,40, ale to je vlastnost **ztlumení řádku** (0,52,
`.frow.done`), ne barvy — systémová modrá tam měla 2,26 / 2,63 a vyjmout akci ze ztlumení by
znamenalo, že odmítnutý řádek křičí jednou barvou víc než platný.

Testů je o 8 víc (2349 po zvednutí mainu) v jedné nové suitě a jedné sondě; ověřeno vloženou regresí — po dosazení
`.linkColor` zpátky padnou obě tvrzení v obou režimech. Vzhled je doložený renderem, na kterém stojí
**tabulka, bublina a stavový řádek na jednom plátně** v obou režimech, vedle vyrenderované sekce
návrhu. Ten render našel dvě věci navíc, které #298 **neřeší**: odznak `2×` a `✓ v mém review` chce
návrh v `--mint` (`#0E8F80` / `#2DD4BF`), kdežto aplikace u prvního kreslí systémovou modrou
(`Color.accentColor` za `.tint()` nejde) a u druhého akcent. Chybí na to token `Palette.mint`
a rozhodnutí o něm patří k sobě, takže se to nechává na vlastní issue.

**Detail spadlého checku: anotace a konec logu (#214).** Tab `Kontroly` (#215) říkal, **že** check
spadl; teď říká **proč**. Řádek checku se rozbalí a pod ním jsou anotace check-runu (`soubor:řádek`
a věta, kliknutí skočí do diffu) a konec logu — obojí **až na kliknutí a jen u toho jednoho checku**.
Vedle konce logu jsou `Ukázat celý log` (sheet, ve kterém se dá vybírat) a odkaz na GitHub.

Zadání předpokládalo, že anotace jsou hlavní cesta a log doplněk. **Vyšlo to naopak** a je to
potvrzené na skutečném selhání: spadlý job vrátil dvě anotace a ani jedna neříká, co je špatně
(`Process completed with exit code 1` a deprecation warning k Node.js 20) — to, co člověk hledá, bylo
v logu. Anotace tedy zůstávají jako bonus, když je workflow emituje.

Změřeno u toho několik věcí. `gh api …/actions/jobs/{id}/logs` je **1,50 s / 237 kB** proti 4,77 s
u `gh run view --job --log`, které zadání předepisovalo — použilo se přímé API. Číslo jobu se
**vytáhne z odkazu** na check, protože `gh pr checks` ho nedává, a **totéž číslo funguje jako
check-run ID** pro anotace, takže druhé volání to nestojí. `HEAD` na log vrátí `Content-Length` za
~1,2 s bez ohledu na velikost, takže se nad stropem **vůbec nestahuje** a věta „log má 8,4 MB“ není
odhad.

**Strop 2 MB se potvrdil měřením, ne odhadem** (zadání to výslovně chtělo kvůli #275): dvoumegový
ocas skutečného logu se v `NSTextView` nasází za **220 ms**, celých 8,78 MB za 850 ms — strop tedy
má rezervu. Cestou se ukázalo, že sazba po řádcích stojí **38 ms proti 2,2 ms** jednolitého textu
(17×), takže `SelectableCodeView` bez známého jazyka po řádcích neskládá; pomůže to i sheetu s kódem.

Log se **neukládá a nepřežije ani sbalení checku**, sbalení navíc stahování **zruší**. ANSI se
strhává, timestampy (28 znaků na skoro každém řádku) se schovávají, ořez je od konce a řekne se,
kolik se nevešlo. Anotace se od nálezů drží zvlášť tvarem — plochý řádek se štítkem, ne bublina —
a **nepočítají se nikam**.

Při proklikání se ukázalo, že **konec logu nefunguje u žádného checku** (#292): `HEAD` na velikost
sice doběhl, ale `Content-Length` se z jeho výstupu nenašel, takže se nikdy nestahovalo. Příčina je
jazyková: `gh api -i` zakončuje hlavičky **`CRLF`** a `"\r\n"` je ve Swiftu **jeden `Character`** —
`split(separator: "\n")` na něm tedy nerozdělí a z celého bloku hlaviček zbyde jediný „řádek“.
V shellu to šlo, protože tam hlavičky čtou oči; zelený test to nechytil, protože jeho fixture byla
Swiftový literál, tedy `LF`.

Opravené jsou tři věci. Rozbor hlaviček je **vlastní typ** (`GhResponseHeaders`): dělí na
`Character.isNewline`, jména normalizuje na malá písmena (`HTTP/2` je nese lowercase) a bere
**poslední blok**, protože ten před redirectem má `Content-Length: 0`; velikost vrací vyjmenovanými
stavy (`ContentLengthReading`), ne `Int?`. Fixture je bajt za bajtem skutečný výstup `gh` a je
v `.gitattributes` jako `-text` — jinak by ji `core.autocrlf=input` znormalizovala a test by zezelenal
i s tou chybou. A `Policy.logLines` dělí řádky logu na jakémkoli zakončení, protože v logu z Windows
runneru je to tatáž past.

Vedle toho se **otočilo jedno pravidlo**: nezjištěná velikost už log neruší. `HEAD` je ochrana proti
osmimegovému logu, ne podmínka toho, že se log ukáže — bez velikosti se tedy stáhne a strop se
uplatní na tom, co doopravdy přišlo. Chyba jednoho dotazu tak nemůže vypnout celou funkci, což je
přesně to, co se stalo. `malformedOutput` u toho dostal **fázi** (`Vyhledávání pull requestů`,
`Anotace check-runu`, …): „Výstupu gh nerozumím“ samo neřekne ani to, která obrazovka je poloprázdná.

**A po proklikání se zvedly stropy: 2 MB → 10 MB a 300 → 4 000 řádků** (#292). Otázka byla „nešlo by
zobrazovat víc, nesekne se to?“, a odpověď dalo měření na největším logu, který na našich repech je
(8,78 MB, 25 533 řádků, nejdelší řádek 2 258 znaků).

**Sekla by se — ale na něčem jiném, než kde stál strop.** Konec logu kreslil SwiftUI `Text`
se `.fixedSize()`, který roste kvadraticky: 300 řádků 108 ms, 2 000 řádků **6,2 s**, 10 000 řádků
**156 s**. Deset tisíc řádků by tedy okno zamrzlo na dvě a půl minuty. Kreslí ho proto `NSTextView`
(`LogTailTextView`), kde tytéž tři velikosti stojí 2,06 / 1,96 / 6,81 ms, protože TextKit sází líně po
viewportu — a projíždění, tedy ta cena, na kterou si stěžuje #275, má medián snímku 0,00 ms
a nejhorší 0,01 ms i na celých 8,78 MB.

**Strop na velikost mohl jít nahoru, protože #214 měřilo něco jiného, než co aplikace dělá:**
`ensureLayout` + `usedRect`, tedy vynucenou sazbu celého dokumentu (631 ms), kdežto sheet text jen
předá (6,57 ms). Poučení, které tomu stropu přežije: měřit se musí ta cesta, kterou kód doopravdy
jde. Strop tedy nedrží kreslení, ale **stahování** — 8,78 MB stahuje `gh` ve třech měřeních 5,75 /
27,44 / 10,67 s, takže se velikost píše do hlášky, dokud se stahuje, a sbalení checku `gh` **zabije**
(změřeno 0 → 1 → 0 procesů). Příprava textu (814 ms na 8,78 MB) šla mimo hlavní vlákno, jinak by okno
stálo o tu dobu.

**Řádků je 4 000 a cena o tom nerozhoduje** (2,61 ms proti 1,14 ms u dvou tisíc; celý ten největší
log 5,50 ms). Nejdřív jsem rozhodl 2 000 s odůvodněním, že okýnko má 320 bodů a `Ukázat celý log` musí
zůstat k něčemu; uživatel si vyžádal 4 000 a **je to jeho volba, kterou měření unese** — původní
argument byl o ergonomii, ne o výkonu. Zapsaná cena zůstává: 4 000 řádků je v okýnku 175 obrazovek
scrollování (2 000 bylo 88), takže k dalšímu zvedání patří i vyšší okýnko. Rozdíl proti sheetu se
nesetřel, největší log má 25 533 řádků. S delším ocasem k tomu patřilo ještě jedno: okýnko se
**otevírá na konci logu**, ne na začátku ocasu, protože jinak by hledaná assertace byla sto obrazovek
daleko.

**Sheet `Ukázat celý log` je nově široký podle obrazovky**, ne 820 bodů. Sheet zalamuje, takže úzké
okno znamená víc řádků sazby na jeden řádek logu — změřeno **3,89×** při 820 bodech, 2,63× při 1 360
a **1,54×** na stropu 2 700, tedy o 60 % méně scrollování. Strop je tam, kde přestane zalamovat
mediánový řádek (333 znaků proti mediánu 327), a zvedl se z původně odhadnutých 1 600 po měření na
obrazovce, na které se aplikace používá (3 440 bodů) — tam 1 600 nechávalo polovinu scrollování navíc.
Je to tentýž vzor jako u vynucené sazby: **měřit se musí ta konfigurace, ve které se to používá.**

Testů je o 64 víc (2385 po zvednutí mainu), z toho **30 na tuhle opravu** ve dvou nových suitách.

**Přepínač vzhledu (#278).** Vzhled se do #278 řídil **jen** systémem a nedal se přebít, takže
porovnat, jak se diff čte ve světlém a v tmavém (což je celé #277), znamenalo přehodit celý systém.
Přepínač je **v levé liště pod oddělovačem**, jak ho kreslí návrh — a je to **jedno tlačítko, které
klikem cykluje** `světlý → tmavý → podle systému`. Stav nese **ikona**: slunce, měsíc, kolečko s „A“
pro automat; kam klik povede, říká nápověda. Rozhoduje jediný řádek — `NSApp.appearance`; barvy se
nikde nevětví, `Palette` zůstala nedotčená.

**Tři ikony jsou vědomá odchylka od návrhu**, který v railu kreslí jedno půlkolečko bez ohledu na
stav. Vyžádal si ji uživatel a důvod je dobrý: tlačítko, které cykluje, jinak neřekne, co platí.
Mezitím z toho byla i **nabídka s třemi volbami** — ta padla ze stejného důvodu, kvůli kterému
uživatel chtěl klikání. Do mockupu se to doplní při jeho překreslení (#299), potichu ho neměním.

**Nejdřív z toho byla stránka v nastavení a bylo to špatně.** Rozhodl jsem to sám, protože zadání
říkalo „rozhodni a zapiš“ — jenže návrh to místo určuje a já si ho k tomu prvku nepřečetl. Zpětně
vzato je to tentýž druh chyby, kvůli které vzniklo #286: kde ovládací prvek je, není otázka vkusu.
Stránka v nastavení proto **není** — dvě místa na tutéž volbu by znamenala dvě tvrzení o jednom
stavu a návrh druhé z nich nezná.

**Rail nedrží vlastní stav**: čte `configuration.global.appearance`, zapisuje
`AppStore.setAppearance(_:)` a to jde do souboru (volba přežije restart). Přepínač **není**
`RailSection` — sekce jsou obrazovky, kdežto vzhled žádnou neotevírá; kdyby byl jejím případem,
šlo by na něj „přepnout jako na obrazovku“ a nabídl by se v ⌘K mezi sekcemi. Uplatňuje se
v `AppStore.apply(_:)`, tedy tou jedinou cestou, kterou konfigurace vchází do běžící aplikace, což
pokrývá i okno, které v době přepnutí není vpředu.

Změřeno sondou, která vzhled přepne **za běhu nad složenou hierarchií** (`AppearanceSwitchProbe`):
`@Environment(\.colorScheme)` se pohne spolu s paletou, takže se obarvení kódu nerozejde s chromem —
to byla ta jediná otázka, kterou z kódu přečíst nešlo. Na tomtéž renderu je vidět i přebarvený diff
včetně syntaxe: vysázený text se přeskakuje podle podpisu a v tom podpisu režim je, takže se sází
znovu. Podpis se u toho sloučil do jednoho místa (`DiffBlockSignature`), protože ho obě podoby diffu
skládaly každá svým řetězcem.

Poloha v railu je **změřená z bitmapy** (oddělovač 20 × 1 bod, ikona ve středu railu, tedy 26
z 52) a vyzkoušená vložením regrese; barvu ikony ale čísla nechytila — `.menuStyle(.borderlessButton)`
ji obarvilo akcentem, takže vypadala jako aktivní sekce, a poznalo se to jedině z renderu. Testů je
o 30 víc (2449 po zvednutí mainu) ve šesti nových suitách, z nichž dvě jsou **sondy za přepínačem**: render railu ve všech
třech stavech a v obou režimech, a to přepnutí za běhu.

### CRLF past mimo #214 — dělení řádků má jedno místo (#295)

`#292` opravil `CRLF` tam, kde se to projevilo (hlavičky `gh api -i`), a **tatáž past ležela dál na
pěti dalších místech**. `"\r\n"` je ve Swiftu jeden `Character`, takže `split(separator: "\n")` na
textu s `CRLF` **nerozdělí vůbec** — z celého vstupu zbyde jediný „řádek“.

**Není to teorie.** Fixture, na které to teď stojí, je skutečné `gh pr diff` na veřejný
`microsoft/terminal#20524`: `CRLF` je tam na **70 řádcích ze 76**. Do #295 by se z takového diffu
stal jeden soubor s jedním nesmyslným kontextovým řádkem místo dvou hunků — a totéž se dělo s obsahem
souboru při rozbalování kontextu, s kódem v sheetu (obarvil se jako jeden řádek a šel do
`SyntaxRunCache` jako jeden klíč) a s popiskem `Kopírovat rozsah`, který nad rozsahem o dvaceti
řádcích hlásil `1 řádek`.

**Sešla se u toho i druhá past.** `components(separatedBy: .newlines)` dělí po unicode skalárech,
takže `CRLF` jsou pro ni **dva** oddělovače a mezi ně vloží prázdný řádek. V markdownu je prázdný
řádek konec odstavce, a těla komentářů z GitHubu `CRLF` mají — takže se každý řádek cizího komentáře
sázel jako vlastní odstavec. Dvě různé pasti, jeden důvod: dělit řádky se dá čtyřmi způsoby a tři
z nich jsou špatné. Proto je to od #295 na **jednom místě** (`TextLines` v `App/Support/`), včetně
toho, co už opravené bylo — výčet nemá výjimky.

**Řádek u nás končí `LF`, `CRLF` nebo samotným `CR`, ne `Character.isNewline`.** `isNewline` je
pravda i pro `U+2028` a spol., což jsou pro `git` znaky **obsahu**: rozdělit se na nich znamená
vyrobit řádek, který v souboru není, a posunout tím čísla všech řádků pod ním. `String.singleLine` si
`isNewline` naopak schválně nechává — sráží cizí text do jednoho popisku a `U+2028` popisek zalomí.
Dvě různé otázky, dvě odpovědi, a na obě je test.

**Vidět není nic** a je to tak správně: na `LF` vstupech se nezměnilo nic (přišpendleno testem, že
tentýž diff se `CRLF` a s `LF` dá **stejný model**) a `CRLF` PR v naší frontě není. Zapsaná cena
rozhodnutí: kopie do schránky nese `LF`, i když soubor měl `CRLF`, protože `CR` v textu řádku by
znamenal neviditelný znak v klíčích `SyntaxRunCache`, ve word-level rozdílu i v sazbě.

Testů je o 26 víc (2479), ve třech nových suitách. **Regrese ověřená vložením regrese dvakrát**:
vrácené `split(separator: "\n")` položí 41 testů v 8 suitách (mezi nimi i obě sady z #292, což
dokládá, že jejich převedení nic neztratilo), a rozšíření na `isNewline` položí přesně ty dva testy
o unicode oddělovačích.

**A po dalším proklikání se zvedly obě meze u konce logu: 4 000 → 6 000 řádků a okýnko 320 → 441 bodů**
(#303). Obojí bylo výslovné přání; **kolik přesně, rozhodlo měření**, ne odhad.

U řádků měření jen potvrdilo, že to cena unese (6 000 řádků 5,45 ms proti 2,02 ms u dvou tisíc, celý
největší log by byl 14,34 ms u desetitisícového ocasu) — rozhodla ale **skutečná data**. Devět
změřených logů z našich repů má 2 / 1 515 / 2 174 / 5 899 / 5 920 / 5 933 / 16 013 / 16 270 / 25 533
řádků, takže `Tests` joby sedí zrovna v pásmu, které stará mez ořezávala a nová ukáže celé — a nad mezí
zůstávají tři největší, takže `Ukázat celý log` i hlavička „starších N řádků se nevešlo“ mají dál co
dodat. Kdyby mez přelezla i je, sheet a okýnko by ukazovaly totéž a mez se zvedat neměla.

U výšky rozhodlo, **kolik zbude na seznam checků** — to je ta věc, kvůli které se detail checku
stěhoval do vlastního tabu (#215). Nová sonda (`CheckLogRoomProbe`) to čte z vyrendrované hierarchie:
na okně, ve kterém se aplikace používá (952 bodů), zbývá pod okýnkem **172 bodů, tedy 6 řádků**
seznamu; ve výchozím okně 700 se seznam odscrolluje, a to je zapsaná cena. Zamítnuto 525 bodů (z okýnka
by byl celý tab) i 357 bodů (+3 řádky nejsou změna, o kterou se prosilo).

**A cestou se našlo, že okýnko se na konci logu neotvíralo** — ta úmluva z #292 v aplikaci nikdy
nefungovala. Skákalo se z `DispatchQueue.main.async` hned po vsazení textu, ale okýnko vzniká teprve
ve chvíli, kdy log dorazí, takže v tu chvíli nemá výšku a `scrollToEndOfDocument` posun zahodí. #292 to
nechytilo proto, že jeho sonda dala `NSScrollView`u rozměr **předem** — tedy tatáž chyba jako u vynucené
sazby, jen o vrstvu vedle: měřila cestu, kterou aplikace nejde. Opraveno skokem z `layout()` a žádost se
zahodí teprve tehdy, když je konec **doopravdy vidět** (jinak se okýnko zastaví o řádek nad koncem,
když se vodorovný scroller objeví až po skoku). Cena, kterou to přineslo, je zapsaná: skok vynutí sazbu
až na konec dokumentu, 128 ms na šesti tisících řádcích.

Testů je 2484 (o 5 víc, z toho 3 skutečné a 2 za měření).
### Časové sondy pod zátěží — čekání na jev má jedno místo (#296)

Za jednu dávku paralelního vývoje vyrobily časově citlivé testy **pět falešně červených `mainů`**.
Rozhodovalo se měřením pod zátěží, ne odhadem, a diagnóza vyšla jinak, než jak issue znělo: nebyl to
přetažený strop, ale **vyhladovělý `MainActor`**. Sonda odpočtu si v plném běhu vyžádala odmlku
100 ms a probudila se za **7,5 až 8,6 s**, přitom její vlastní práce (bitmapa) stála 1 ms — takže za
čtyřsekundový strop stihla **jediný snímek** a hlásila „odpočet se nepřetikal“ o aplikaci, která byla
v pořádku. Hladověl kvůli ostatním suitám: `Task.yield()` práci nepustí na procesor, jen ji přeřadí
na konec fronty téhož aktoru, a Swift Testing pouští suity paralelně.

Takových míst mělo `Tests/` **56** a tentýž problém tam našlo **šest** míst zvlášť (#292, #269 a čtyři
suity, které si každá psala vlastní odmlku). Proto je z toho jedno místo — `Tests/Support/TestWaiting.swift`
se třemi primitivy (`waitUntil`, `settle`, `TestWait.pause`) — a ne šestá kopie. Strop **2 minuty** je
změřený: při třech souběžných clean buildech (load 24–36 na patnácti jádrech) trvala čekání, která se
**dočkala**, až **42,3 s**; se stropem 30 s padly tři plné běhy ze tří.

**Dvě rozhodnutí se cestou změnila proti zadání.** Sonda odpočtu **přestala tvrdit vteřinový takt
stropem** — tuhle roli jí dalo #269 a nefungovala, protože sonda potřebuje tři kola na `MainActoru`;
takt se dá ověřit deterministicky a bez hodin na `entries(from:mode:)` (rozvrh `by: 2` tam vyjde
`[42, 40, 38]`, dva pády za 0,001 s). A test zrušeného podprocesu **přestal měřit čas volání**
(5 s → pod zátěží 5,95 / 8,23 / 11,03 s, po zvětšení na 15 s pak až 26,7 s) a ptá se na **zmizelý
PID**, což je i silnější tvrzení: naměřený čas říká jen „vrátilo se to brzo“, takže by prošla i
implementace, která na proces zapomene.

U toho se našlo, že **pořadí tvrzení je součást testu**: `#expect(processHasGone)` musí být před
`await running.value`, protože to čekání skončí i tím, že procesu doběhne `sleep` — v opačném pořadí
test s vyndaným `requestKill()` **prošel** za 300 s. Sonda odpočtu proto od teď píše do hlášky i
**počet snímků**: nad zamrzlým odpočtem vyjde `snímků 1157` (zdravá sonda, rozbitá aplikace), pod
zátěží by tam stálo `snímků 1`. Bez toho čísla je „změn 0“ k nerozeznání od zamrzlého odpočtu.

**Vidět není nic** — je to změna v `Tests/`, `App/` zůstalo nedotčené. Doloženo plným během pod
souběžným buildem tří slotů a čtyřmi vloženými regresemi (vyndané zabíjení v runneru i ve streameru,
zamrzlý odpočet, rozvrh `by: 2`).

**Co #296 neopravilo a patří do vlastního issue:** `AppStoreProgressTests` je flaky i bez zátěže a i
samostatně (1 pád z 8 běhů, za 0,038 s) — pozdní události průběhu **vzkřísí** osu, kterou `keepFresh()`
zahodil, takže je to otázka na `AppStore`, ne strop v testu. A `Early unexpected exit … bootstrapping`
se nereprodukovalo; zapsané je aspoň to, jak se pozná.

**A pruh záložek přestal problikávat: tab `Kontroly` je v něm od začátku** (#306). Checky se tahají
s detailem PR, takže se šestá záložka objevovala až po otevření PR — pruh se přeskládal z pěti na
šest a obsah pod ním s ním. Otáčí to výslovné rozhodnutí z #215 („tab se nekreslí, když checky
nejsou, protože prázdný tab by o PR tvrdil, že se něco nepovedlo“) a otočilo ho **chování**:
problikávání je při každém otevření PR, kdežto prázdný tab jen u těch pár PR bez CI — a prázdný tab
s hláškou, ve které stojí, že to **není porucha**, ten původní argument ruší.

Trvale přítomný tab si vynutil odpověď na **každý** stav dat, ne na dva: `Policy.checksTab` mapuje
šest kombinací vstupů na čtyři stavy (nenačteno / bez CI / seznam / porucha, a seznam ještě
se zastaralostí i bez ní), přičemž „ještě nedorazily“ o CI netvrdí nic — je to tentýž rozdíl jako
mezi `čisté` a `failed` u review. Odznak se proto počítá **ze stavu tabu**, ne ze souhrnu: do #306
mlčel nad prázdnem jen shodou okolností, protože se tab neměl kde nakreslit.

**Zkontroloval se i řetěz, který na tom zmizení visel.** Věta o selhaném načtení checků se
z hlavičky PR vrátila **do tabu**, protože její jediný důvod byl ten, že tab mizí — a tab, který
nemizí, musí poruchu umět říct sám, jinak by nad chybou sítě tvrdil „nemá CI“. Zarovnání uložené
volby tabu odpadlo celé: ztratilo předmět a s ním i vedlejší účinek, se kterým se u #215 smířilo
(z `Kontrol` se vypadávalo při každém příchodu na PR). Cestou se našly dvě věci, které do té doby
nebylo z okna vidět: po chybě sítě se checky **nedotáhly nikdy** (`loadDetail` má cache podle
`updatedAt`), takže tab dostal `Zkusit znovu`; a po spadlém detailu se `loadChecks` nespustil vůbec,
takže by v tabu svítilo `Načítám kontroly…` navždycky — teď se checky tahají i tehdy.

Šestou záložku od téhle změny platí i PR bez CI, a je to **změřené**: nová sonda
(`ChecksTabRenderProbe`) rendruje tab ve všech pěti podobách stavu a pruh přes pásmo šířek. Bez
odznaků se pruh vejde na jeden řádek od ~780 bodů, se všemi od ~920; ve výchozím okně (1100 minus
rail) je to bez dopadu, projeví se to u okna stáhnutého k podlaze.

**A vlastní revize diffu našla ještě jednu díru**, kterou trvale přítomný tab teprve odhalil:
`loadChecks` běží až po detailu, takže **přepnutí PR uprostřed toho volání ho zrušilo** — a zrušení
se schválně nezapisuje. Po návratu na PR se detail vzal z cache, checky se už nedotáhly a v tabu by
`Načítám kontroly…` svítilo navždycky, aniž by cokoli běželo. Do #306 to nebylo vidět (tab se
nekreslil), teď se checky v té větvi z cache dotáhnou — ale **jen když není ani seznam, ani
porucha**, aby z nich nebyl polling při každém příchodu na PR.

Testů je 2490 (o 6 víc: šest kombinací vstupů, mlčící odznak nad každým stavem bez seznamu, volba
přežívající všechny čtyři stavy, `Zkusit znovu`, načtení checků po spadlém detailu i po zrušení
a pojistka, že hotovou odpověď návrat nepřepíše — zarovnání volby, zúžený pruh a jeho dělič odpadly,
protože ten stav už nejde vyrobit; dvě z toho jsou testy sondy). **Regrese ověřená vložením regrese
třikrát**: vrácené zarovnání volby položí tři tvrzení v jednom testu, zahozené dotažení z cache
položí test o zrušení a `loadChecks` vrácený do `do` bloku položí oba testy o spadlém detailu.

### README proti dnešnímu okně (#297)

`README.md` je první soubor, který kdokoli přečte, a `CLAUDE.md` má jako podmínku, že se aplikace
musí dát pochopit **z dokumentace bez čtení kódu** — takže dokumentace, která o obrazovce tvrdí
něco, co tam není, je horší než chybějící: čtenář podle ní hledá blok, který neexistuje. Ohlášené
byly dvě věty z #215, ale prošel se **celý soubor** a našlo se **třináct** nepravd — a **sedm z nich
bylo starších než #215**, tedy ohlášené to nebylo ani náhodou.

Z #215 a #214: **pět záložek místo šesti**, dělič mezi `Konverzací` a `Nálezy` (dnes mezi
`Kontrolami` a `Nálezy`), chybějící odznak `Kontrol` a blok `Kontroly na GitHubu` popsaný jako část
`Přehledu`, kde po #215 **nezbylo nic**. Místo té jedné odstavcové zmínky má tab vlastní sekci —
anotace, konec logu, sheet, a hlavně tři věci, které se u logu **nedělají** (nestahuje se dopředu,
neukládá na disk, nad 10 MB vůbec). Z #294: panel s nálezy byl na **dvou** místech popsaný jako
viditelný ve všech tabech, přitom je ve třech ze šesti.

**#306 se mezitím mergnul do `mainu` a sekce se po něm přepsala**, ne přidala vedle: napsané v ní
bylo, že se `Kontroly` u PR bez CI nekreslí, což byl pravdivý stav v době, kdy se ta sekce psala,
a nepravdivý o hodinu později. Dokumentace o mizející záložce vydaná po tom, co mizet přestala, je
zrovna ten druh věty, kvůli které #297 vzniklo — takže popsané je to dnešní chování (kreslí se
vždycky, čtyři stavy dat, okrová věta nad zastaralým seznamem) a přechod je v ní zapsaný jako obrat
proti #215, ne zamlčený.

Starší nepravdy, které to vyplavilo: dlaždice `Nálezy proti` se podle README kreslila „jen když se
hlava rozešla“ (od **#198** je vždycky a rozchod nese barva); `Zahodit nálezy` bylo v liště panelu
(od **#242** v hlavičce tabu `Nálezy`); okno nastavení mělo „dvě záložky“ (od **#177** je to boční
navigace se sedmi stránkami); filtr fronty byl „ikona v toolbaru vlevo“ (je vpravo v liště nad
frontou, a jen u fronty); a v `Požadavcích` stálo, že aplikace chodí na síť **jediným** vlastním
voláním — na téže cestě (`HTTPGetting`) jsou i **avatary**. K tomu „toolbar“ na dalších pěti
místech, který od **#180** neexistuje (okno má vlastní hlavičku), a stav proti milníkům: README
pořád tvrdil, že M6–M8 jsou to, „co přijde po v1“, přitom jsou všechny tři hotové.

Vedle nepravd se doplnilo, co v souboru **chybělo**: `.gitattributes`, `Tests/Fixtures/transcript/`
a `docs/paralelni-vyvoj.md` ve výpisu struktury a šest klíčů v seznamu toho, co drží `config.json`.

**Ověřovalo se pohledem, ne čtením kódu**, jak chtělo zadání: dashboard a rail ze snímku běžící
slotové aplikace (`screencapture -o -l<id>`, tedy zezadu a bez cizího obsahu na snímku) a všech šest
tabů z `DetailTabRenderProbe`. Z kódu se dobralo jen to, na co se přes kliknutí nedá dostat bez
skutečných dat — stropy logu, tvar konfigurace, umístění filtru v `HomeView`.

**Vidět není nic** — je to dokumentace, `App/` i `Tests/` zůstaly nedotčené, takže počet testů se
nemění. Cestou se opravila i jedna buňka v [`docs/architektura.md`](architektura.md), která
u `PullRequestTab` vypisovala pět případů a `checks` zmiňovala až v témže odstavci o dvě věty dál.

**Co se našlo a nespravilo** (patří jinam, ne do diffu o README): doc komentář u `SettingsView`
pořád říká „Tři záložky“, tedy stav před #177.

### Fakta nad popis PR (#280)

Řada čtyř dlaždic s fakty se v tabu `Přehled` přesunula **nad kartu s popisem**. Pořadí je odshora
banner „od minule“ → fakta → popis. Rozhodla **nesouměrnost délek**, ne důležitost obsahu: dlaždice
jsou vždycky tři čísla a dvě sha, kdežto popis je libovolně dlouhý — u pracovních PR běžně padesát
řádků — takže cenu za odrolování platil vždycky ten kratší obsah. A `Nálezy proti` odpovídá na
otázku „platí to, co v okně vidím?“, jejíž odpověď nepatří za prózu, jejíž délku neurčujeme my.

**Zadání se cestou zúžilo a to je na téhle změně to podstatné.** Původní znění issue chtělo čtyři
věci: přehodit pořadí, **sloučit** `HLAVA` a `NÁLEZY PROTI` do jednoho boxíku, uvolněné místo dát
**diffstatu** (`ZMĚNA +142 −38`) a **rozhodnout úzké okno**. Uživatel to o dvaadvacet minut později
přepsal na pouhé přehození pořadí a zbylé tři zapsal jako zamítnuté; v mockupu je to sekce 18
s odznaky `nedělá se` / `odloženo` a sekce 02 je překreslená do nového pořadí. Zamítnuté je zapsané
schválně, aby se příště nenavrhovalo znovu jako nový nápad — argumenty pro sloučení tím nezmizely,
jen se neuplatnily.

Implementace je proto **dva prvky prohozené ve `VStacku`** a zbytek je důkaz, že se u toho nic
jiného nestalo:

- **`OverviewOrderTests`** měří pořadí z pixelů (mezera mezi dlaždicemi je nekreslená, karta
  s popisem kreslí přes celou šířku — z toho se pozná, co je výš) přes osm šířek 128–1180.
  Ověřeno vloženou regresí: po prohození zpátky spadne ve všech osmi.
- **Render před a po** má při každé ze tří šířek, obou tématech i obou stavech banneru shodnou
  velikost plátna a **shodnou multimnožinu otisků vodorovných řádků** — řádky se jen přesunuly,
  žádný se nepřekreslil. To je doklad, že se popis nezúžil ani neosekal a že řada nedostala pružné
  rozměry, které v ní nebyly (#220, tedy to, na čem se `Přehled` rozbil u #291).
- **`OverviewWidthTests`** dál hlásí nulový přesah ve všech osmi šířkách.

**Úzké okno se nerozhodovalo** — návrh ho nechává `odloženo` a přehození se ho netýká: řada je
stejně široká jako předtím, jen stojí jinde. Že se v úzkém tabu drtí (`COMMIT/Y`, `abc12…`), platilo
i před změnou.

**Co se našlo a nespravilo** (patří jinam, ne do diffu o pořadí): zastaralá sha v dlaždici je
`Color.yellow`, kdežto mockup na ní má token `--stale` a zbytek okna `Palette.stale` (okrová
`0x9A6700`/`0xD4A72C`). Po přesunu nahoru to bije do očí víc, protože dlaždice teď sousedí s okrovým
pruhem „od minule“ — dvě různé žluté nad sebou. Není to ale chyba jedné dlaždice: `.yellow` používá
i stav `zastaralé` v řádku fronty (`ReviewStateAppearance`) a hlavička PR, takže jsou v okně **dvě
rodiny žluté** a sjednotit se musí naráz. Vedle toho je řada faktů od popisu vzdálená 16 bodů,
kdežto návrh má mezi prvky `Přehledu` 13 (`.ovpane { gap: 13px }`) — taky předchozí stav, ne
následek přehození.

### Tab `Commity` — nakreslený, nezaložený

Sedmá záložka detailu PR (seznam commitů a diff jednoho z nich) je **nakreslená v mockupu**,
sekce 19, a rozhodnutí i zamítnuté alternativy jsou v
[specifikaci](superpowers/specs/2026-07-31-prism-design.md), sekce *Tab Commity*. **V kódu není
nic** a issues na to zatím nevznikly — pravidlo *Návrh (mockup)* v `CLAUDE.md` chce nakreslit
a nechat schválit dřív, než se issue založí, takže tohle je zastávka mezi tím.

Cena je změřená, ne odhadnutá: sedmá záložka posune šířku, od které se pruh vejde na jeden
řádek, z 920 na **1035 bodů** okna. Ve výchozím okně (1100) je to tedy bez dopadu; nové je
pásmo 920–1035 a zaplatí ho `+X −Y` (108 b, tedy skoro přesně cena té záložky). Vedle toho se
ukázalo, že pruh se pod tou hranicí **zalamuje, nezkracuje** — oprava jedné věty
v [`docs/testovani.md`](testovani.md).

Až se založí, mají to být **dvě issues dělené datovou cestou**: seznam commitů
(`pulls/{n}/commits`, jedno volání, 1,20 s) a rozkliknutí na diff commitu (`commits/{sha}`
s `Accept: application/vnd.github.diff`, 0,99 s, unified diff pro dnešní `DiffParser`).

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
