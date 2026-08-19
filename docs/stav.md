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

10. **Vlastní PR** (M10, milník #12) — vlastní pull requesty v okně. Aplikace do #330 nevěděla,
    **kdo se dívá**, takže vlastní PR byly od cizích k nerozeznání — a půlka okna (fronta,
    dashboard, automat, notifikace, paleta) předpokládá, že „PR = něco, na co se čeká“. Milník to
    rozřadí podle autora a dá vlastním PR jinou práci: místo verdiktu, který GitHub na vlastním PR
    odmítá, se z nálezů a konverzace skládá zadání pro agenta. Sedm issues (#330–#336), nakreslené
    v sekcích 21 a 22 návrhu; **pořadí je v popisu milníku**, protože se podle něj rozhoduje, co jde
    souběžně. Hotové: rozřazení podle autora #330, sekce `Moje PR` v railu a druhá fronta na
    dashboardu #331, panel se zadáním pro agenta #333, vlastní skupina v paletě ⌘K #336.

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

**Větší objem práce dostane vlastní milník (#340)** — orientačně tři a víc issues, které patří
k sobě; nenechává se nasypaný v `Průběžné` a nečeká se, až o milník někdo požádá. Pravidlo je
v `CLAUDE.md` (jeden bod v *Pracovním postupu*, hned u verzování — milníky se jinde v pravidlech
neřeší), podoba milníku v [`paralelni-vyvoj.md`](paralelni-vyvoj.md) jako podsekce **§1**, protože
`POŘADÍ PRÁCE` je trvalá podoba právě toho rozvrhu, který v §1 vzniká. Zapsané je: titulek
`M<číslo> — <název>` s pokračujícím číslem, popis česky se sekcí `POŘADÍ PRÁCE` (formát z **M9**),
zakládání a přesouvání přes **REST** (`gh issue edit` padá na deprecated Projects classic) a to, že
odstavec do `docs/stav.md` patří do **prvního PR milníku**, ne do zvláštního úklidového. **Verzování
se nemění** — od `v1.0.0` běží jedna řada `v1.1.x` a číslo milníku v ní roli nehraje. Změřené jsou
u toho dvě věci o té REST cestě: `milestone=` bere `.number` milníku, ne `.id` (s `.id` přijde
`422 Validation Failed` a issue zůstane, kde byla), a řetězec v `-f` u toho celočíselného pole
projde stejně jako `-F`. Vzniklo z **M10** (milník #12), kde sedm provázaných issues #330–#336
leželo v `Průběžné` vedle drobností jako #152 a #299 — z takového seznamu není vidět rozsah ani
závislosti. `CLAUDE.md` narostl o jeden bod a odstavec u verzování (55 753 → 56 881 B), tedy
pořád hluboko pod stropem, kde Copilotovi praská kontext.

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

Změřeno: overlay bloku **3,05 ms → 0,12 ms** (26×) a zápis ploch do `DiffRowFrames` **24,1 ms →
0,25 ms** (hlásí se naráz za blok, protože úklid je lineární v počtu záznamů; u #274 přeměřeno
s přípravou mimo hodinky, do té doby tu stálo 22,6 → 1,40 ms). V aplikaci na
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

**Tři ikony byly vědomá odchylka od návrhu**, který v railu kreslil jedno půlkolečko bez ohledu na
stav. Vyžádal si ji uživatel a důvod je dobrý: tlačítko, které cykluje, jinak neřekne, co platí.
Mezitím z toho byla i **nabídka s třemi volbami** — ta padla ze stejného důvodu, kvůli kterému
uživatel chtěl klikání. **Odchylka už žádná není**: #299 to do mockupu dokreslilo (rail nese
kolečko s „A“, tedy výchozí automat, a poznámka u sekce 01 popisuje cyklení).

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
### Akcent z palety a token `mint` — stav se pozná od akce (#309)

V okně byly na jednu věc **tři barvy místo dvou**. `Color.accentColor` sedělo na osmi místech
v `App/` a všechna kreslila **systémovou modrou**: `.tint(Palette.accent)` z kořene okna se na něj
nevztahuje (zabírá jedině `.foregroundStyle(.tint)`, změřeno renderem u #298). K tomu chyběl token
pro **konstatování**, takže odznak shody `2×` a značka `✓ v mém review` — dvě věci, na které se
neklikne — vypadaly jako `Převzít` vedle nich.

**Akcent je vlastní barva aplikace** (vyžádané při proklikání #298) a `Palette.mint` je jeho
dvojice: akcent je to, co se nabízí udělat nebo co běží, mint to, co se jen konstatuje. Rozdělení
osmi míst nešlo udělat podle jména — rozhodovalo, jestli ta věc stojí **vedle akce**: mint dostal
`2×`, `✓ v mém review` (obojí v tabulce i v bublině, přes `FindingBadgeAppearance.stateTint`),
souhrn rozdělaných review ve stavovém řádku (pár desítek bodů od akcentového `Připravit`)
a odznak `odmítnuto`; akcent si nechal běžící review, událost „nahlásil nálezy“ na ose `Průběhu`,
verdikt `Komentář` a oba pruhy rozsahu v diffu. Návrh to nese stejně — mint v něm je na celé
stránce **dvakrát** a obojí je v řádku tabulky nálezů.

**Světlá větev mintu se proti návrhu ztmavila** (`#0E8F80` → `#0C7E71`): hodnota z mockupu měla
na ploše řádku kontrast 3,99, tedy pod AA, a byla jediným stavovým tokenem palety pod tou hranicí.
Ztmavení je na rodinu, ne na hranici — vychází na všech podkladech stejně jako `find` vedle něj.
Tmavá je z návrhu doslova. **Odchylka už žádná není**: #299 tu hodnotu dopsalo i do obou světlých
větví mockupu, takže paleta a návrh drží jednu pravdu.

**Komentář u `ReviewStateAppearance`**, který tvrdil, že barva má jít se systémovým akcentem,
zmizel i s důvodem: `Color(light:dark:)` se režimu přizpůsobí taky, takže první polovina toho
odůvodnění nebyla důvod pro systém, a druhá je zrovna to, co se zamítlo. Zbytek škály
(`.green`, `.orange`, `.red`, `.yellow`) **zůstává systémový vědomě** — převod je jiná otázka,
jinde v repu se zodpovídá měřením (#218, #277) a zelenou s červenou bere ze systému ještě zhruba
padesát míst v `App/`.

**Vidět to je**, takže se to ukazovalo renderem: tabulka, dvě bubliny, stavový řádek a odznaky
stavu na jednom plátně v obou režimech, položené vedle vyrenderované sekce 06 návrhu. Měření drží
`MintTokenTests` (2 504 testů celkem) — ΔE proti `ok` 16,6 / 21,1 a proti `stale` 37,9 / 39,4,
kontrasty 4,95 / 9,90 na ploše. Že odznak nesmí být akcent, je ověřené **vloženou regresí**.

**Co se našlo a nespravilo:** `✓ v mém review` je v tabulce kreslené jen jako ikona
(`.labelStyle(.iconOnly)`), kdežto návrh má v tom sloupci celý text; a `.stale: .yellow` je ve
světlém režimu na hranici čitelnosti.

### Prompt review z nastavení (#281)

Prompt review byl natvrdo v `ClaudeCommand`, takže se dal změnit jedině commitem — a přitom je to
zrovna to, co se u review mění nejčastěji a posuzuje se podle výsledku. Od #281 se píše v nastavení
na stránce `Review a skilly`, hned pod sadami skillů.

**Není to jedno pole na celý prompt.** Tři věty v tom textu nejsou styl, ale kontrakt aplikace,
takže se to dělí na **šablonu** se zástupnými texty `{{skill}}` a `{{baseSha}}` a na **jádro**
(`ReportFindings` i s prázdným seznamem, zákaz zápisu a odesílání, přebití skillu), které se
připojí **vždycky** a ze šablony se vyhodit nedá. Jádro přitom **není bezpečnostní opatření** —
read-only reviewera drží `--allowedTools` a `--disallowedTools`, tedy konstanty v kódu, se kterými
se šablona nikde nepotká. Chrání **sběr nálezů**: bez `ReportFindings` reviewer nálezy napíše
textem, sběr tiše nefunguje a v okně stojí „čisté review“.

Výchozí šablona je **doslova ten text, co byl v kódu**, a hlídá to test, který složený prompt
porovnává znak po znaku s literálem opsaným z minulé verze. Prázdná šablona znamená „ber výchozí“;
chybějící zástupný text je chyba **u pole** a taková šablona se **neuloží**. Do ručně editovaného
`config.json` se přesto dostat může, takže ji podruhé chytá `AppStore` a review s ní **nespustí** —
spadnout potichu na výchozí by znamenalo, že „nic se nestalo“ vypadá jako „funguje“. Pod polem je
**náhled**: šablona s ukázkovými hodnotami a pod ní zamčené jádro.

Šablona **putuje s požadavkem** jako `baseSha` a skládá ji jedna čistá funkce v `Policy`, takže
`Zkopírovat příkaz` v tabu `Průběh` (#242) dává tentýž text jako skutečný běh. Prompt **kontroly
nálezů** (#150) a **překladu nálezů** zůstává natvrdo: jejich odpověď nenese nástroj, ale parser,
takže by editovatelný prompt rozbil čtení, ne jen výsledek.

Vidět to je na stránce `Review a skilly`; stavy, na které se klikáním nedostane snadno, hlídá
render sonda (`ReviewPromptRenderProbe`) — a jednu reálnou chybu chytila: náhled se ve `Form`u
srazil na tři řádky a zbytek promptu uřízl. Testů je **2519**; regrese ověřena vložením (znak navíc
ve výchozí šabloně, nepřipojené jádro a vyhozený `guard` v `AppStore` naráz padne 22 tvrzení
v 15 testech).

### Sazba textu bloku — složení textu zlevněno, sazba zůstala (#275)

Po #252 byl `DiffPairBlockContainer.show` hlavní položkou ceny projíždění velkého diffu: **86,3 ms
na 27 blocích** po 60 řádcích samých dvojic (harness bez GUI, nejhorší případ). Nedalo se z kódu
poznat, kolik z toho je co, takže první práce byla **rozpad na fáze** — a ten teď v repu zůstává
jako měřidlo (`DiffPerformanceMeasurement.blockTypesettingBreakdown`, gated `PRISM_MEASURE`).

Vyšlo: `WordDiff` 14,0 ms, složení atributovaného textu 22,2 ms, nasazení do `NSTextStorage`
3,8 ms, **sazba v `NSLayoutManager`u ~36 ms**. Zlevnilo se **složení**: text bloku vzniká jako
jeden řetězec a barvy se do něj dopisují na rozsahy, místo aby se slepoval z `NSAttributedString`u
za každý run (16 000 objektů na projetí). K tomu se `NSColor(Color)` převádí jednou na blok, ne na
run (`SyntaxColors`). **22,2 → 4,5 ms**, celek **86,3 → 61,5 ms** (−29 %); s čerstvým kontejnerem,
jak to platí projíždění, **72,4 ms**.

**Absolutní čísla se hýbou se zátěží stroje**, poměr ne: tatáž dvojice vyšla na volnějším stroji
79,2 → 60,0 ms. Proto se obojí měřilo týmž měřidlem tentýž den a čte se z toho ten poměr.

**Sazba se zlevnit nepodařila a je to změřené, ne odložené.** Vynucuje si ji `sizeToFit()`, ze
kterého se čte přirozená šířka sloupce pro vodorovný posun — jenže vyhodit ho cenu nesmaže, jen ji
přesune do kreslení, protože `super.draw` rozvržení potřebuje taky (vykreslení sloupce do bitmapy
stojí 108,7 ms na 54 stranách). Zamítnutý je i fond kontejnerů, který zadání navrhovalo jako třetí
krok: postavit kontejner stojí 0,34 ms, tedy 11 ms ze 72 — desetina, ne polovina. Důvody
i zamítnuté alternativy jsou v [specifikaci](superpowers/specs/2026-07-31-prism-design.md).

**Vidět není nic a je to doložené rovností, ne pohledem**: dočasný test složil týž blok starým
i novým způsobem a porovnal `isEqual(to:)` na 400 řádcích ve dvou paletách. Co v repu zůstalo, je
`DiffBlockCompositionTests` — nová třída chyby, kterou přepis přinesl, jsou počítané rozsahy
v UTF-16, takže emoji je dva kódy; regrese ověřena vložením (`count` místo `utf16.count` položí tři
testy). Testů je **2540**.

### Pruh „Od tvé poslední návštěvy“ podle návrhu (#284)

Pruh nahoře v `Přehledu` seděl proti návrhu (sekce 02) čtyřmi věcmi a všechny čtyři jsou hotové.

**Sazba odrážek.** `lines` byl `[String]` a jeden `Text(verbatim:)`, takže v řádku nešlo nic
zdůraznit. Řádek se teď skládá z typovaných částí (`SinceLastVisitLine.Part`: `strong` / `plain` /
`sha`) a skládá je `SinceLastVisitLines` — **mimo view a mimo `Policy`**, jako `TimelineEventRow`:
je to próza pro člověka, ne rozhodnutí, takže se rozdělilo jedno skládání, nepřestěhovalo se.
U vět, které si pruh píše sám, je tučně **co se stalo**; u událostí časové osy se bere věta i s jejím
zvýrazněním z `TimelineEventRow`, tedy tučná **jména** — dvě různá pravidla schválně, protože druhé
znění téže věty by se s tím prvním rozešlo. Autor commitů se uvádí, **jen když je jeden**.

**Sha je podklad za písmem, ne kapsle s odsazením** — vědomá odchylka od návrhu a tatáž volba, jakou
už udělal inline kód v sazbě Markdownu (#279): `AttributedString` umí u běhu nastavit barvu pozadí,
ne jeho výplň a rádius, takže kapsle by znamenala kreslit každou sha jako vlastní view a tím
rozpadlé zalomení uprostřed věty. Odrážka je v úzkém `Přehledu` zalomená vždycky.

**Odznak místo věty.** `nálezy zastaraly` (`.pill.stale`) čte `AppStore.staleFindings(for:)`, tedy
**tentýž zdroj** jako hlavička nad taby — a rozsvítí se jedině tehdy, když nálezy doopravdy jsou.
`Pustit review znovu` se naopak nabízí **i bez nálezů**, když se přepsala historie: do #284 se
v takovém případě neukázalo nic, což byl třetí bod zadání.

**`Ukázat, co přibylo`** je nová datová cesta. Rozhodlo měření mezi dvěma nabízenými: klon v cache
**prohrál**, protože `refs/prism/pr/<n>` v něm vzniká teprve při checkoutu kvůli review a
`forgetPullRequest` ho maže (u většiny PR by se tlačítko nenabídlo), klon je `--filter=blob:none`
(takže by si `git diff` obsah stejně dotáhl ze sítě) a u PR z forku by v něm hlava nebyla vůbec.
Přibyla proto **dvanáctá čtecí metoda** na `GitHubGateway` — `compare/<viděná>...<dnešní>`
s `Accept: application/vnd.github.diff`, jedno volání, ~0,7 s. Rozsah se kreslí v tabu `Změněné
soubory` s lištou, ze které se jedním tlačítkem vrátíš na celý diff; celý diff se u toho **nezahazuje**,
je to to, proti čemu se píše review.

**Po přepsané historii se tlačítko nenabídne**, a je to změřené: trojtečkový `compare` začíná na
společném předku, takže by po force pushi vrátil **víc než celý diff PR** — na `cli/cli#14062` 102 kB
ve 22 souborech proti 15 kB ve třech. Tedy přesně to, co zadání zakazuje. Rozhoduje o tom čistá
funkce `Policy.incrementalDiff`; `rewroteHistory: nil` (nenačtená časová osa) se chová jako
„přepsala“.

Cestou vypadlo jedno poučení k šířkám: **`ViewThatFits` se na řadu s pružnými popisky spolehnout
nedá.** Odznak i tlačítka se ve zúžené řadě radši zkrátí, než by nahlásily, že se nevejdou — v liště
rozsahového diffu z toho vyšlo `Jen t…`, a `lineLimit(1)` ani `fixedSize` s tím nehnuly. Rozhoduje
proto **spočítaná** šířka popisků (`TextWidth`), jak to má #220. `OverflowProbe` na tuhle třídu chyb
**nestačí** — zkrácený popisek nikam nepřeteče —, ověřeno vloženou regresí, po které zůstaly
`OverviewWidthTests` zelené. Testů je **2584**.

### Tab `Commity` — seznam hotový (#316)

Sedmá záložka detailu PR je v okně: **seznam commitů PR, od nejnovějšího**, řádek s obrázkem
autora, první řádkou zprávy, jménem, relativním časem a sha, pilulkami `sloučení` a `hlava`
a pruhem s počtem nad tím. Sedí mezi `Změněnými soubory` a `Konverzací`, tedy nalevo od děliče —
a **dělič se tím neposunul**, protože se počítá z `isReviewerOutput`, ne z indexu. Data jsou
z nové čtecí metody `GitHubGateway.fetchCommits(id:)`, tahají se s detailem a jedním voláním;
tvrdá podmínka č. 1 se tím nemění, gateway pořád nemá čím něco odeslat.

**Cena sedmé záložky vyšla líp, než odhad předpovídal, a je změřená na skutečném pruhu.**
Specifikace měla z repliky 920 → 1035 bodů okna; naměřeno po jednom bodu šířky je to
**937 → 939**, protože `+X −Y` se v úzkém pruhu nekreslí (`ViewThatFits` se dvěma podobami)
a pilulka stojí skoro přesně tolik co ta záložka (110 proti 112 bodům). Absolutní čísla
ze specifikace byla o 17 bodů níž — replika je odhad, ne měření; **rozdíl** ale odhadla dobře.

**Pořadí se proti návrhu otočilo: nejnovější nahoře.** Mockup (sekce 19) i specifikace měly „od
nejstaršího, jako na GitHubu, protože PR se čte jako postup“ — ten důvod ale neobstál na hotové
obrazovce: v okně se PR nečte od začátku, ale od toho, co přibylo naposled, tedy tentýž pohyb jako
u pruhu `Od tvé poslední návštěvy` a tentýž důvod, proč jsou fakta v `Přehledu` nahoře (#280).
Otáčí se **na jednom místě** (`Policy.commitsNewestFirst` v `commitsTab`) a **otáčí, neřadí** —
pořadí z API je topologické, takže řazení podle data by po rebase postup rozházelo. Změnil se s tím
i pruh nad seznamem (`7 commitů · od nejnovějšího`), protože je to jediné místo, které pořadí
pojmenovává. Mockup to **od #299 kreslí stejně** — seznam v sekci 19 jde od nejnovějšího a pruh
nad ním s ním.

**Tři rozhodnutí, která zadání upřesnila.** Prázdná odpověď se hlásí jako **porucha**, ne jako
prázdný stav (pull request bez commitů neexistuje, takže hláška o prázdnu by tvrdila nemožný
stav — a `CommitsTabState` proto **nemá** `empty`, na rozdíl od `ChecksTabState`). Pilulku `hlava`
dostává commit, jehož sha se rovná `headSha` z detailu, **ne první řádek** — nahoře sice obvykle
stojí, ale po pushnutém commitu je seznam o krok pozadu a nad stropem API v něm hlava chybí úplně;
nálezy jsou klíčované `headSha`, takže se tehdy neoznačí nic. A **šipka u řádku se nenakreslila**,
protože rozkliknutí je #317: šipka, za kterou se nic nestane, slibuje interakci, která tam není.

Testů je po sloučení s `main` **2638**; tohle issue z nich přidalo **44** — pět nových suit (stav
tabu, model commitu, dekódování odpovědi, načítání ve store a šířka pruhu) plus render sonda a dva
případy dopsané do stávajících suit. Pět z těch čtyřiačtyřiceti hlídá pořadí: otočení čerstvého
i zastaralého seznamu, že se otáčí a neřadí, že v pruhu nezbylo staré slovo, a že mapa ve store drží
pořadí z API.

Rozkliknutí commitu přidalo **#317** a smrsknutí pruhu na ikony v úzkém okně **#318** — obojí níž.
Tab `Commity` je tím hotový celý.

### #320 — časový limit běhu do nastavení

Limit jedné `claude` session byl do #320 zadrátovaný (`ClaudeReviewRunner.defaultTimeout`, patnáct
minut), takže se dal zvednout jedině přeložením aplikace — a přitom `docs/architektura.md`
u rozlišení `timedOut` proti `interrupted` už tehdy tvrdila, že „dá se zvednout limit“. Teď je to
`GlobalConfig.reviewTimeoutMinutes` s **override per repo**, na stránce `Review a skilly` v sekci
`Režim review`. Výchozích patnáct minut je doslova ta hodnota, co byla v kódu, takže zavedení pole
nic nemění; hlídá to test porovnávající číslo, ne konstantu.

**Meze jsou 5–60 minut a „bez limitu“ mezi volbami není** — timeout je jediná pojistka proti
session, která se zacyklí, kdežto `autoRunsPerDay` a `maxConcurrentReviews` omezují jen **počet**
běhů. Obě čísla jsou naměřená, ne odhadnutá: 19 běhů z provozní cache dalo medián **2,5 min**
a nejdelší doběhlý **6,8 min** (dolní mez), a cena vyšla na ~**0,40 $/min** u běžného běhu, přičemž
v cache leží session za **14,67 $ pod minutou** — peníze tedy nejsou funkcí času, ale hodina navíc
je hodina utrácení bez dozoru (horní mez, ve vazbě na denní strop automatu).

Dvě rozhodnutí, o která si issue řeklo: **kontrola nálezů (#150) limit sdílí** — tatáž session,
tentýž strom, tytéž peníze, a spouští se jedině ručně —, a **překladače nálezů se to nedotýká**,
protože se uvažuje o jeho zániku (jazyk nálezů by přešel do promptu review). Číslo limitu se
navíc **nepíše k výsledku běhu**: uložený běh ho nenese, takže by šlo napsat jen to, co je
nastavené teď, a to je o starším timeoutu nepravda.

Limit **putuje s požadavkem** jako šablona promptu (#281), takže rozjeté review doběhne s tím
svým; runner po #320 vlastní pole nemá. Hodnota mimo meze soubor nepoloží, ale ani se nespolkne —
v konfiguraci zůstane syrová, srazí se až v `resolved(for:)` a nastavení pod polem napíše, kolik je
v souboru a s čím se doopravdy poběží. **Popisek „Bere globální“ na stránce `Repozitáře` vypisuje
sraženou hodnotu** — nálezem Copilota; „Bere globální: 240 min“ nad během, který poběží 60, je text,
který tvrdí víc, než data unesou.

Testů je **2663**; regrese ověřena vložením tří naráz (posunutá výchozí hodnota, runner s vlastní
konstantou, `resolved` bez sráření) — padne 18 tvrzení v 10 testech.

### Tab `Průběh` — živý výpis a surová session nakreslené, čekají na implementaci

Druhá vrstva dráhy v tabu `Průběh` (okno s kroky session pod fázemi, u běžícího reviewera
rozbalené) je **nakreslená v mockupu**, sekce 20, a rozhodnutí i zamítnuté alternativy jsou
ve [specifikaci](superpowers/specs/2026-07-31-prism-design.md), sekce *Tab Průběh — živý výpis
kroků*. **V kódu není nic** — pravidlo *Návrh (mockup)* v `CLAUDE.md` chce nakreslit a nechat
schválit dřív, než se issue založí.

**Není to nová funkce, je to nedodělané #22.** Specifikace tab popisuje jako živý pohled na to,
co reviewer dělá, od začátku; ze dvou z jeho pěti odrážek zbývá dodělat výpis událostí a
`Sledovat konec`. Data přitom už tečou (`ReviewProgress.attemptedTool` chodí do osy během běhu),
takže nová datová cesta ani závislost z toho nevychází. **Vestavěný terminál to není** a zůstává
tam, kde byl — řeší zásah do session, tohle sledování.

Tři věci se u kreslení našly v kódu a nesou se do zadání: **živá osa nemá strop** (uložená má 300,
takže se za běhu drží stovky událostí, které po restartu zmizí, a nikde to není napsané),
**odmítnutý nástroj vypadá jako provedený** až do konce běhu (ve streamu je vidět hned, jako
`tool_result` s `is_error`, ale `StreamParser` `user` eventy nečte) a
**`ReviewerTimeline.newestEntry(in:)` po zrušeném přepínači (#242) v aplikaci nemá volajícího** —
drží ho naživu jen tři testy. Zkracování cest se u toho opravuje v číslech: prefix pracovního
stromu není sedmdesát znaků, ale **131**, u `Bash` třikrát (změřeno 461 → 57 znaků, 8×).

**Druhá obrazovka téže sekce: surová session.** Výpis kroků je záměrně úzký (jen nástroje), takže
pro chvíli, kdy nestačí — review dopadlo divně, session spadla —, je pod ním **záchranná brzda**:
přepis celého transcriptu v sheetu, postavený na vzoru `Ukázat celý log` u spadlého checku. Ani
tohle není nová datová cesta: `TranscriptLocation` cestu odvodí a `TranscriptStore` soubor umí
otevřít, dneska z něj po pádu čte jen `ReportFindings` (#97).

Rozhodl to **rozbor 922 transcriptů na disku**: největší má 53,3 MB, ale jen **2 348 řádků** —
a jeden řádek v něm má **7,5 MB**. Řádek je tedy špatná jednotka a ocas o 6 000 řádcích z
`Policy.logTailLines` by nezabral vůbec; čte se proto **okno posledních 4 MB** plus **8 kB na
událost**, a protože je soubor lokální, stav „moc velký“ úplně odpadá. Objem přitom nedělá próza
modelu (**61 kB z 53 MB**, 0,11 %), ale výstupy nástrojů, a z mediánového řádku je **86 % obálka**
— proto přepis, ne syrové řádky. Podrobnosti i zamítnuté alternativy jsou ve
[specifikaci](superpowers/specs/2026-07-31-prism-design.md), sekce *Surová session — přepis
transcriptu*.

Implementace se dělí na **tři issues dělené vrstvou**: samotný výpis se stropem a sledováním konce
(UI a `Policy`), čtení `tool_result` ze streamu (`StreamParser`, model kroku) a surová session
(sheet nad `TranscriptStore`). Issues zatím **nejsou založené** — čeká se na souhlas s návrhem.

### Tab `Commity` — diff jednoho commitu (#317)

Kliknutí na řádek v tabu **přepne obsah tabu**: seznam zmizí a diff toho jednoho commitu dostane
celou plochu, jako to má GitHub. Nahoře hlavička se sha, zprávou i jejím tělem, autorem, časem,
počtem souborů, `+X −Y` a cestou zpět (`‹ Commity 2 ze 7`, plus `⎋`); pod ní `DiffView`, tedy oba
pohledy, word-level zvýraznění, sbalování, rozbalování kontextu, kopírování i strom souborů (`⌘1`).
Počty jsou **ze staženého diffu**, takže nestojí volání navíc.

**Je to prohlížeč, ne review — a je to vidět z typu, ne jen z chování.** `CommitDiffView` nedostane
`AppStore` ani identifikátor PR, takže nemá čím vyrobit bublinu nálezu ani rozdělaný komentář.
Důvody jsou dva a oba jsou tvrdé: komentář ke commitu by potřeboval **jiný klíč draftu** a **pátou
metodu v `ReviewPublishing`** (podmínka č. 1), a nálezy jsou klíčované `headSha` (podmínka č. 5),
takže by u staršího commitu ukazovaly na jiný kód. Tab se tvrdé podmínky č. 1 **nedotýká vůbec**:
`GitHubGateway` zůstal bez zápisových metod a `grep ReviewPublishing App/` vrací tentýž výčet.
V hlavičce je jedna tichá věta s odkazem do `Změněných souborů`, protože kdo přijde odtamtud, bude
do řádku chtít kliknout.

**Prázdný diff vychází z prázdných commitů, ne ze sloučení — a to je oprava zadání, ne detail.**
Zadání i návrh čekaly prázdno hlavně u sloučení. Změřeno na `keboola/job-queue#727`: tři sloučení
vrátila diff proti prvnímu rodiči o **842 B, 514 kB a 760 kB**, kdežto tři commity z
`git commit --allow-empty` (přetáčení CI) vrátily **nula bajtů** s nulovým návratovým kódem.
Prázdno je tedy stav odpovědi, ne vlastnost sloučení — obě vysvětlující věty proto musí obstát samy
o sobě a obě říkají „není to porucha“.

**Dvě čtecí metody gateway navíc, ne jedna společná.** `fetchDiff(repo:commit:)` vypadá jako totéž
co rozsah z #284 (týž `gh api`, táž hlavička), ale `compare/<a>...<b>` počítá od společného předka,
kdežto `commits/<sha>` je diff proti **prvnímu rodiči** — jedno napsané přes druhé by u sloučení
tiše ukázalo i přisloučenou větev. Sdílené je proto jen složení příkazu. Totéž u
`fetchFile(repo:path:at:)`: **ref není parametr**, protože „soubor na hlavě PR“ a „soubor v tomhle
commitu“ mají jinou záruku. Gateway má teď **čtrnáct** čtecích metod a pořád ani jednu zápisovou.

**Rozbalování kontextu se muselo klíčovat commitem.** Do #317 se obsah tahal z
`refs/pull/<n>/head`, takže by v diffu staršího commitu byly odkryté řádky z **dnešní** hlavy —
posunuté o všechno, co mezitím přibylo, a přitom naprosto věrohodné. `FileExpansionKey` proto nese
`commit: String?`; tentýž klíč drží i **sbalené soubory**, takže se sbalení mezi diffem PR a diffem
commitu nesdílí.

**Hlavička jde sbalit — a sbaluje se tělo zprávy, ne celá.** Vyžádané po proklikání hotové
obrazovky, aby diff dostal víc místa. Sbalují se **odstavce pod první řádkou**, protože to je
jediná část, která roste bez omezení: sha, autor, čas a počty jsou pořád tři řádky, kdežto tělo
squashnutého merge commitu má klidně třicet. Hlavička sbalená celá by se smrskla na pruh
s tlačítkem zpět a přestala odpovídat na „na co se to koukám“, tedy na to, kvůli čemu nad diffem
je. Ve sbaleném stavu proto zůstává cesta zpět, titulek, sha, odkaz na GitHub, autor, čas, počty
i tichá věta o čtení; **získá se 54 bodů u dvouřádkového těla a víc u delšího**, změřeno renderem.

Přepínač je **vlastní řádek s popiskem** (`⌄ Tělo zprávy` / `› Tělo zprávy · 6 řádků`), ne holá
šipka: po sbalení musí zbýt něco, na co se dá kliknout, a počet řádků je jediné, co o schovaném
textu řekne, kolik ho je. Volba je **globální ve store** — předvolba pohledu jako rozložený panel,
tedy ne mapa per PR a hlavně ne `@State`, který mezi pull requesty přetéká. **Výchozí stav je
rozbaleno** a u jednořádkové zprávy se nekreslí ani přepínač.

**Dvě rozhodnutí o paměti a o návratu.** V okně se drží **nejvýš jeden diff commitu na PR** (klíčem
je pull request, sha je v hodnotě) — mapa klíčovaná `(PR, sha)` by u PR se stovkou commitů rostla
o každý proklik. A „kde v seznamu jsem byl“ se **neukládá zvlášť**: je to sha posledního staženého
diffu, tedy táž hodnota, ze které se diff kreslí. Řádek se podle ní podbarví a seznam na něj
odscrolluje.

Testů je **2710**; tohle issue z nich přidalo **41**, z toho **8** sbalovací hlavička. Nejcennější
je `CommitDiffReadOnlyTests` — tvrdí, že se v tabu **nedá nic napsat**, a to ve třech vrstvách (co se `DiffView`u předá, co z toho
vyjde v řádcích, a že žádný řádek nenabídne akci), každá s protipólem v režimu review, aby
neprocházela naprázdno. Ověřeno vložením regrese: dosazené `findings:` a `canCompose: true` položí
tři testy z pěti a 50 tvrzení. Druhá a třetí regrese (obsah z hlavy PR místo z commitu, `unfoldAll`
bez filtru na commit) padnou v `AppStoreCommitDiffTests`.

### #318 — pruh záložek se v úzkém okně smrskne na ikony

Pruh se do #318 v užším okně **zalamoval**: `PullRequestTabBar` nikde nemá `lineLimit`, takže se
popisek lámal uvnitř záložky a v nejužším povoleném okně (700) byl pruh vysoký **90 bodů místo 30**.
Nebyla to cena sedmé záložky (#316) — se šesti to bylo 75 —, ale stav rozbitý i bez ní, a proto to
bylo vlastní issue.

Pruh má teď **tři podoby** místo dvou (`PullRequestTabBar.Layout`, pořád `ViewThatFits`), a bere se
první, která se vejde:

| Podoba | Ideální šířka tabu | Okno (+ rail 53) |
|---|---|---|
| `full` — popisky a `+X −Y` | 996–998 b | 1049–1051 b |
| `labels` — popisky, bez `+X −Y` (#316) | 886–888 b | 939–941 b |
| **`icons` — ikony s odznaky, popisek jen u aktivní** | **498–564 b** | **551–617 b** |

Pásma jsou tam proto, že v `icons` je aktivní popisek jediný, který se kreslí — horní konec drží
`Změněné soubory`, dolní `Nálezy`. **Pruh se tím nezalomí ani v nejužším okně**: s trojmístnými
odznaky u všech záložek naráz vyjde `icons` na 636 b (okno 689), pořád pod podlahou 700, a **proto
pruh nemá čtvrtou podobu** bez popisku i u aktivní — na tu se nedá přijít.

Tři rozhodnutí, o která si issue řeklo. **Popisky ustupují všechny naráz**, ne po jednom od
nejdelšího: postupně by z toho bylo sedm podob podle šířky místo tří. **Popisek u aktivní záložky
zůstává**, protože odpovídá na jinou otázku než ostatní — ne „kam se dá jít“, ale „kde jsem“ —
a podtržení samo mezi sedmi ikonami je málo. A **`ViewThatFits` zůstal**, i když u #284 na tutéž
úlohu nestačil: tam byly popisky v řadě se `lineLimit`em, takže se zkracovaly, kdežto pruh se
zalamuje a jeho ideální šířka tedy zůstává šířkou celého popisku. Není to úvaha — test porovnává
render celého pruhu proti jedné podobě vykreslené napřímo, v šesti šířkách, pixel po pixelu.

Odznaky zůstávají ve všech podobách a jméno záložky bez popisku nese **ikona** (`accessibilityLabel`)
a **nápověda** pod kurzorem, obojí jen v úzkém stupni. Sonda pruhu se u toho sloučila do jednoho
místa (`TabStripRenderProbe`) — do #318 se tentýž pruh rendroval ve dvou sondách tabů, pokaždé
v jiném pásmu, takže se obrázky nedaly položit vedle sebe.

Testů je **2669**; regrese ověřena vložením dvou (smazaná podoba `icons`, zahozený popisek
u aktivní) — první položí čtyři testy, druhá to tvrzení, které by výška pruhu nechytla.

### #343 — konec logu „o řádek vedle“ byl artefakt harnessu, ne vada aplikace

`LogTailOpeningTests.opensAtTheEndOfTheLog` padal nahodile: `documentVisibleRect.maxY` **83 989**
proti poslednímu řádku končícímu na **84 002**, tedy o jednu řádku nad koncem. Vyvolal to diff #339
(`main` 6× ze 6 zeleně, ta větev 4× ze 7) a pády byly **pokaždé na týchž číslech** — což je známka
skutečného stavu, ne zátěže.

**Příčina je v prostředí procesu, ne v `jumpToEnd`.** `NSScroller.preferredScrollerStyle` je po startu
procesu chvíli `overlay` a teprve za pár kol smyčky se doresolvuje na `legacy` — a legacy scroller
místo doopravdy zabírá. Když ta změna přijde *až po* dosazení cíle skoku, viewport se zmenší
(`clip.h` **441 → 424**, tedy 17 bodů, ne 13 jako rezerva ve `height` — ten rozpor vyřešilo #347, viz
níž: měření bylo správné, rezerva ne), `origin.y` zůstane a okýnko je
o řádku nad koncem — a **nikdo to nepřerovná**, protože další `layout()` přijít nemusí. Diff #339
na tom nic nezpůsobil, jen posunul, které suity běží v tom startovacím okně.

**Zadání se tím obrátilo, a je to zapsané jako vědomá odchylka.** #343 to popisovalo jako vadu
aplikace („ležící žádost nikdo nedovolá“) a chtělo **dosadit cíl dvakrát**. Zamítnuto po měření: obě
kola běží v témže průchodu, tedy pořád před doresolvováním stylu, takže na měřeném stavu nemění nic —
tři zelené běhy, na kterých ten návrh stál, byly shoda. Změřeno naopak, že když se styl nechá usadit
**před** postavením okýnka, je poloha správná **od nultého kola** (`origin.y = 83 582`,
`maxY = 84 006`) a **beze změny v aplikaci**. V aplikaci je totiž ten stav nedosažitelný: styl
scrollerů je usazený dávno předtím, než se dá otevřít detail checku.

Opraveno tedy **v testu** (`TestWait.awaitSettledScrollerStyle()`; u #343 to byla ještě privátní
metoda `LogTailOpeningTests`, do `TestWait` se to svedlo u #347), aplikace zůstala nedotčená. Zamítnuto i
čekat na „konec je vidět“ místo na `origin.y > 0`: bez změny v aplikaci to dojede na 120s strop a celý
běh má **184 issues**, protože pumpování smyčky vyhladoví `MainActor`.

**Vidět není nic** — je to čistě testovací vrstva, aplikace se nezměnila ani o řádek. Testů zůstává
**2710** (žádný nový; sada měla flake, ne mezeru). Regrese ověřena vložením regrese, a od #343
**deterministicky**: cíl spočítaný ze zastaralé výšky viewportu (`- 17`) položí tvrzení o posledním
řádku na téže signatuře jako původní flake (`83 989` proti `84 001`). Tři zelené plné běhy po opravě.

Poučení, které z toho zbývá i mimo tuhle sadu: **pády pokaždé na týchž číslech nejsou zátěž**, a kdo
staví AppKitovou hierarchii v testu, musí počítat s tím, že proces po startu ještě není usazený.

### #339 — počet řádků těla zprávy commitu neuměl CRLF

Popisek přepínače v hlavičce rozkliknutého commitu (`› Tělo zprávy · 6 řádků`) počítal řádky
`body.split(separator: "\n", omittingEmptySubsequences: false).count`, tedy vzorem, který
`CLAUDE.md` zakazuje od #292 a který #295 svedl na jedno místo. `"\r\n"` je ve Swiftu **jeden
`Character`**, takže se na `CRLF` nerozdělilo vůbec a v hlavičce stálo **`Tělo zprávy · 1 řádek`**
u zprávy jakékoli délky — přesný opak toho, na co ten popisek odpovídá („vyplatí se to rozbalit?“).
Zprávy commitů chodí z `gh` z cizích repozitářů, takže zakončení řádků si nevybíráme; nebyla to tedy
teorie. **Našel to grep z `CLAUDE.md`** při revizi #338, kde ten grep musí vyjít prázdný — a
nevycházel. Po opravě (`TextLines.all(body).count`) vychází.

**Sjednotil se u toho pojem „konec řádky“.** Titulek (`PullRequestCommit.subject`) a tělo
(`Policy.commitMessageBody`) jsou dvě půlky **jednoho** rozdělení, a obojí dělilo `isNewline` — na
`CRLF` to funguje, takže to nebyla ta chyba, ale po opravě počtu by se to s ním rozešlo. `isNewline`
je pravda i pro `VT`, `FF`, `NEL`, `U+2028` a `U+2029`, což jsou pro `git` znaky **obsahu**, takže
jedno `U+2028` v titulku by titulek usekalo a jeho zbytek by se v hlavičce objevil **ještě jako
první řádka těla** — tentýž text dvakrát. Obojí jde teď po `isLineTerminator`, stejně jako počet.
Sazbu to nerozhodí, oba pohledy titulek zkracují (`lineLimit` 1 v seznamu, 2 v hlavičce). Zamítnuto
přepsat tělo přes `TextLines` a zbytek spojit: spojení by `CRLF` uvnitř těla přepsalo na `LF`, tedy
změnilo text, který se kreslí.

**Fixture je skutečná odpověď, ne literál** — `gh api …/pulls/6293/commits` na veřejném
`git-for-windows/git`, commit `415ab35` s **míchanými** zakončeními: titulek `LF`, tělo `CRLF`,
tělo o třech řádcích. Jedna stránka (`per_page=1`, 3,6 kB), protože celá jich má 391 kB.
**`-text` v `.gitattributes` schválně nedostala**, ačkoli s ním zadání počítalo: `CR` je v JSONu
escapovaný jako dvojice `\` + `r`, takže surových `CR` bajtů je v souboru nula (změřeno — staged blob
má tytéž 3 664 B jako soubor na disku, přitom `core.autocrlf=input`) a normalizovat není co. Řádek by
byl kontrola, která nic nedělá; co zakončení doopravdy drží, je tvrzení v testu, a to platí bez ohledu
na nastavení gitu. Důvod je zapsaný v `.gitattributes` jako komentář, ať to příště nikdo „neopraví“.

**Vidět to je**, ale ke stavu se **normálním používáním nedá dojít** — musel by v tabu `Commity`
ležet PR s `CRLF` ve zprávě commitu. Je na něj proto šestý scénář sondy
(`CommitsTabRenderProbe`, `diff-commitu-sbalena-hlavicka-crlf`), který zprávu bere z té fixture;
v popisku na něm stojí `Tělo zprávy · 3 řádky`. Ověřeno u toho i to, co sonda nekreslí: rozbalené
`CRLF` tělo se sází jako tři řádky bez zbylých glyfů (jednorázově, přepnutým příznakem).

Testů je **2716** (o 6 víc), plus dva argumenty k existujícímu parametrizovanému. **Regrese ověřena
vložením regrese, dvakrát zvlášť**: vrácený `split(separator: "\n")` položí 3 testy a 5 tvrzení —
parametrizovaný spadne na 3 případech ze 4, protože `LF` projde, a to je přesně ten důvod, proč se
chyba nechytila dřív —, a `isNewline` zpátky v obou půlkách rozdělení položí test o `U+2028` třemi
tvrzeními naráz (titulek `feat: cache`, `secrets` přelité do těla, počet `3 řádky` místo `1 řádek`).

### #299 — mockup dohnal aplikaci, favicon je zapsaný

Mockup se po dávce s aplikací rozešel na šesti místech a **v kódu se nemění nic než komentáře** —
je to `docs/navrh.html`, dokumentace a záznam rozhodnutí. Pět z těch šesti odchylek bylo zapsaných
větou „mockup se překreslí v #299“ (v `Palette.swift`, `SidebarRail`, `AppearanceMode`,
`docs/architektura.md` a `docs/stav.md`), takže tohle issue je hlavně **splacení toho dluhu**.

**Sekce 02 už nekreslí souhrn `Kontroly na GitHubu`**, který #215 z `Přehledu` odebral celý (nejdřív
to byl seznam z #209, pak chvíli souhrn, nakonec ani ten). Do #299 to bylo zapsané jako „vědomě
zastaralé“, jenže mockup se čte obrázkem: čtenář v návrhu viděl blok, který v okně není. Z toho
vyšlo pravidlo do [`navrh.md`](navrh.md) — „novější sekce se do starší nepřekresluje“ platí
u **dvou variant vedle sebe** (dashboard 01 proti 21, průběh 07 proti 20), kdežto sekce, která
žádnou novější variantu vedle sebe nemá, **je záznam dneška a mění se s aplikací**.

**Hlavička karty popisu je nakreslená v širší ze dvou podob** (#291) a přibyla jí pilulka stavu,
kterou aplikace má od #111. Že se v úzkém tabu (320 bodů) zahodí celý relativní čas, nese věta
v poznámce — obě podoby vedle sebe by se čtly jako spor, ne jako reakce na šířku. Čas je u toho
**bez uvozujícího `otevřel`**: aplikace tam sází `updatedAt`, tedy poslední změnu, takže původní
popisek tvrdil víc, než data unesou.

**Patička nálezu nese popisky z aplikace po #283** — `Převzít do review`, `Neplatí`, `Nepatří sem`
—, a `Přeložit` z ní odešlo, protože se dělat nebude. Proč zrovna takhle, zůstává v záznamu
rozhodnutí u #283; návrh nese to, co v okně stojí.

**Osiřelá patička mimo `.doc-page` se smazala.** Byl to zbytek po přeskládání dokumentu do stránek
(#332) a router ho nikdy neskryje, takže se ta čtyři stará tlačítka kreslila **pod rozcestníkem
i pod každou obrazovkou**. Ve výřezu jedné sekce to vidět nebylo a grep na to nesedne, takže se
z toho stalo druhé pravidlo do `navrh.md`: po úpravě se **vyrendruje i celý dokument**, ne jen
vyříznutá sekce.

**Přepínač vzhledu v railu je kolečko s „A“**, ne půlkolečko — dluh z #278, který byl zapsaný na
třech místech s poznámkou „doplní se při překreslení (#299)“. Kreslí se automat, protože to je
výchozí režim; ostatních položek railu se to netýká (`◷` a `⚙` jsou návrh, ne dnešní stav).

**Seznam commitů v sekci 19 jde od nejnovějšího** (#316) a s ním i pruh nad ním
(`7 commitů · od nejnovějšího`). Původní důvod pro nejstarší nahoře v próze **zůstal** i s tím,
proč neobstál — záznam rozhodnutí se nemaže, jen se k němu dopíše, co se změnilo.

**Světlý `--mint` je `#0C7E71`**, jak ho aplikace má od #309. Tohle je jediná odchylka, kterou by
obrázek neprozradil — a přesně proto na ni existuje pravidlo, že tokeny v `:root` jsou `Palette`
jedna ku jedné. Mění se **obě** světlé větve (`:root` i `:root[data-theme="light"]`), jako se
u #277 měnily obě tmavé; **tmavých se tohle issue nedotklo** a vyčíslené hodnoty z #277
(`#0F2C13`, `#1D5625`, `#371210`, `#712521`) v nich zůstaly.

**Favicon je 🎨 a je zapsaný v [`navrh.md`](navrh.md)**, aby se příště nehádal. Dohledat ho nešlo
už u #277 — není v repu, v `Artifact`u ani ve výpisu artifactů —, přitom publikování si ho vynucuje
jako povinný parametr. Ikonka v tabu je součást identity stránky zrovna jako titulek, a ten
zapsaný byl.

Testů je **2716** a jsou zelené; na tomhle issue se v aplikaci nemění nic, takže žádný nepřibyl.
Shoda se ověřila **obrázkem vedle obrázku**: sekce 02, 03 a 19 vyříznuté a vyrenderované headless
Chromem proti renderu `OverviewRenderProbe`, `FindingActionColourProbe` a `CommitsTabRenderProbe`
z běžící hierarchie. A **jedna vada se ukázala až na renderu celého dokumentu** — osiřelá patička
mimo `.doc-page`, kterou ve výřezu jedné sekce nebylo jak vidět.

Že se v publikované kopii nezměnilo nic dalšího, je ověřené **diffem stažené stránky**: před
publikováním byla bajt na bajt shodná s `main`, po něm s tímhle commitem, a diff „před × po“
obsahuje jen změny vypsané výš.

### #274 — otevřená záložka zdražovala projíždění diffu

Zadání vycházelo z vedlejšího zjištění u #252: tentýž scénář (`job-queue-daemon#858`, split,
rozbalený úsek o 1 904 řádcích, 300 kroků) vyšel na **3,6 s** CPU po čerstvém spuštění s jednou
záložkou a na **10,8 s** v okně se čtyřmi. **Ten trojnásobek se nepovedlo zreprodukovat** — ani na
dnešním buildu (jedna záložka 2,77/3,50/3,28 s proti čtyřem 4,39/3,68/3,37 s, střídavě), ani na
buildu **před** #252 (4,92/4,57/4,96 s proti 4,30/4,30/4,45 s). Rozdíl mezi jednou a čtyřmi
záložkami leží pod rozptylem téhož měření, takže #252 tu příčinu cestou nespravil; nejpravděpodobněji
šlo o **stav sezení a režii řízení**, kterou tehdejší postup odečítal špatně (9,3 s z 15,6 s).

**Přišlo z toho lepší měřidlo, a to je hlavní výnos.** Posuvník se řídí přímo přes
`AXUIElementSetAttributeValue` podle PID, ne přes `System Events`: režie spadla z **9,3 s na
0,02 s** za 601 zápisů, takže naměřené sekundy jsou práce aplikace, ne odpovědi na dotazy AX.
K tomu čekání na usazení před měřením i po něm a **střídavé A/B**, protože drift sezení (2,15 →
4,39 s za půl hodiny) je větší než hledaný rozdíl. Postup i vylučovací tabulka jsou
v [`docs/testovani.md`](testovani.md), *Kolik stojí otevřená záložka*.

**Jedna věc s počtem prohlédnutých záložek doopravdy rostla:** `DiffRowFrames`. `@State` detailu
přetéká mezi pull requesty, takže jeden `DiffView` obsluhuje všechny záložky a v krabici ploch pro
tažení se vrstvily plochy každého prohlédnutého PR — vyklizení plochy je sundá jedině tam, kam nový
blok dosáhl. Zápis je lineární v jejich počtu: **0,25 ms** na blok s jedním PR, **0,49 ms** se dvěma,
**0,93 ms** se čtyřmi. Od #274 nese každé hlášení klíč diffu (`RangeDragActions.FrameBox`, kde krabice
a klíč jsou jedna hodnota — po nálezu Copilota, aby se nedalo předat jedno bez druhého) a cizí
plochy se zahodí — **z hlášení, ne zvenčí**, protože vyprázdnění při přepnutí záložky je chyba
z #110 (bloky, které stojí, už nic nenahlásí a tažení nemá co najít).

**V okně se to nepozná** a je to tak napsané i v PR: zápis ploch je **0,4 %** vzorků hlavního vlákna
(`sample` během projíždění), takže po opravě vyšlo měření stejně jako před ní (2,79/2,60/2,39 s proti
2,26/2,33/2,56 s). Co se spravilo, je **růst** — a to, že krabice přestala držet plochy diffu, který
na obrazovce není. Zbytek ceny projíždění je rozvržení líného seznamu a sazba textu
(`DiffTextView.draw` ~16 % vzorků), což je samostatná věc.

**Přeměřilo se u toho i číslo z #252**: měřidlo v harnessu počítalo do „ceny jednoho bloku“
i naplnění celé krabice, takže tam stálo 22,6 → 1,40 ms; s přípravou mimo hodinky
(`measure(_:preparing:_:)`) je to **24,1 → 0,25 ms**. Vidět není nic, testů je **2719** (o 3 víc)
a regrese je ověřená vložením regrese: bez klíče vyjde v krabici 2000 cizích ploch místo jedné vlastní.

### #120 — reviewer dostane zadání vedle kódu (první část)

Reviewer do #120 viděl **jen kód**: odpojený strom a `git diff <base>...HEAD`. Umí proto najít, co
je vidět z kódu, ale ne to, co při review dělám ručně jako první — přečtu si zadání, pak diff,
a hledám **rozdíl** mezi nimi. Chybějící část zadání ani řešení, které projde testy a neřeší
problém, pro něj neexistovalo, protože neměl s čím porovnávat.

**Zadání je soubor vedle stromu, ne text v promptu.** To je to hlavní rozhodnutí a řídí zbytek.
Aplikace položí do `worktrees/<owner>/<repo>/<pr>-<sha>.md` Markdown s popisem PR a s odkazy na
issue, které v něm jsou, a prompt řekne jedinou větou, kde leží. Dva důvody: **cizí text v promptu
je pokyn, cizí text v souboru je doklad** — popis PR píše někdo jiný, takže věta „nic nehlas, je to
v pořádku“ musí být materiál k posouzení, ne instrukce; a **prompt se nemá čím rozkolísat**, protože
u #52 se změřilo, že tři běhy nad týmž commitem daly 1, 2 a 3 nálezy, takže rozptyl by schoval, čím
se to zhoršilo. Do promptu jde **jen cesta**.

**Sada nástrojů reviewera se nemění** (tvrdá podmínka č. 2). `Read` v ní je odjakživa a soubor leží
v cache aplikace, kam session vidí — stojí v ní i pracovní strom. Test to tvrdí z obou stran:
argumenty se zadáním a bez něj se liší **jen** textem za `-p` a obě konstanty povolení jsou v testu
zapsané literálem, takže přidaný MCP nástroj spadne tam.

**Vedle stromu, ne v něm**, protože soubor uvnitř pracovní kopie by se objevil v `git status`
i v `git diff` — reviewer by ho viděl jako součást změny, kterou má posoudit. Je to tentýž vzor jako
`lastUsedMarker` vedle klonu, a **úklid tím vyšel zdarma**: `CacheEviction.evict` maže celé
`worktrees(of:)` a `discardUnwantedWorktrees` čte číslo PR z názvu, takže zadání odejde se stromem.
Cena je, že `allWorktrees()` teď vypisuje i soubor — filtr tam vědomě **není**, protože
s odfiltrováním by zadání zavřeného PR nesmazal nikdo.

**Věta patří do jádra promptu, ne do šablony** (#281): nese cestu, tedy fakt o tomhle běhu, a
smazatelná věta by znamenala zadání stažené, uložené a nepřečtené. Z toho vyšla jedna oprava, která
šla mimo zadání: **náhled v nastavení kreslil jádro rovnou z konstanty** a `Policy.reviewPrompt`
nevolal vůbec, takže nová věta by v něm nebyla vidět. Připojovaná půlka je proto teď funkce
(`Policy.reviewPromptCore(intentPath:)`), kterou volá běh i náhled — jedna pravda o jednom textu.
A `Policy.reviewPrompt` nemá na novém parametru **default**: s `= nil` by obě dnešní volání zůstala
zelená a věta by se nepřipojila nikdy.

**Prázdný popis znamená, že se nezakládá nic.** `PullRequest.body` je neoptional `String`
s defaultem `""`, takže prázdný a nedotažený popis jsou tatáž hodnota; věta „autor nenapsal nic“ by
tvrdila víc, než data unesou. Řeší se to tím, že se soubor bez obsahu **nezakládá** a věta se do
promptu nepřipojí — takové review běží přesně jako do #120. A pro případ, kdy popis chybí, ale odkaz
je (dosažitelné až v #345), stojí v souboru věta, která **nerozhoduje** mezi „autor nenapsal nic“
a „nedotáhlo se“.

**Příznak na ose (tab `Průběh`) tohle issue vědomě nedostalo** a patří celý do #345. Tady může
selhat jedině zápis do vlastní cache — a to ve chvíli, kdy o pár řádků výš prošlo vytvoření
pracovního stromu, tedy nesrovnatelně větší zápis do téže složky; odznak pro takový stav je UI, které
se nerozsvítí. #345 přináší tři tvary selhání, které nastávají běžně, a tam se vyplatí. Mlčet se
přitom nesmí, takže selhání zápisu jde do stavového řádku jako `intentFailure` — a review **doběhne**,
což je jedno z tvrzení, na kterých u tohohle issue nejvíc záleží.

**Doměřeno u toho schéma `ReportFindings`** na `claude` 2.1.233 (v `docs/claude-cli.md` byla 2.1.220),
ze schématu v binárce a bez platícího běhu: `file` je **povinné**, `line` volitelné, `findings` mají
strop **32** položek a `short_summary` **60 znaků**. Obecný nález se tedy neváže „nikam“, ale
k **souboru bez řádku** — cesta to unese bez práce (`Policy.draftTarget` z toho udělá tělo review
s odkazem na soubor) a texty v UI se prošly: žádný neslibuje nález bez souboru.

**Copilot našel jednu skutečnou díru** a je to přesně ten vzor z `CLAUDE.md`, tedy „kontrola, která
jinde v repu je, a tady chybí“: `existingFile` vracel cestu i tehdy, když na ní ležel **symbolický
odkaz** — a ta cesta jde do promptu, takže by reviewera poslala `Read`em **mimo cache aplikace**.
`contains` to nezachytí, protože rozbaluje symlinky na obou stranách; hlídá to `isSymbolicLink`,
tatáž kontrola, jakou u čtení z cache mají `ReviewStore` i `ReviewDraftStore` (#106). U **zápisu** se
to doměřilo, ať se nezakazuje naslepo: `write(to:options: .atomic)` odkaz **nahradí** souborem a cíl
nechá být, kdežto **bez** `.atomic` ho přepíše — zápis tedy díra nebyl, ale visel na příznaku
místo na vyjmenované kontrole, takže `isSymbolicLink` je i tam.

Testů je **2764** a jsou zelené (po sloučení s #274). Odkazy se testují na **skutečných linkbacích** ze dvou nových fixtures — popis
`metalbear-co/mirrord#4702` (markdownový odkaz se slugem) a linkback od `linear[bot]` na
`zcash/zcash-swift-wallet-sdk#1893` (HTML, sedm adres **bez** slugu). Regrese ověřena vložením:
zapomenuté `request.intentFile`, `try?` nad selhaným zápisem a odfiltrované `.md` v `allWorktrees()`
naráz položí 5 tvrzení v 5 testech napříč třemi sadami.

**Vidět je to v nastavení** na stránce `Review a skilly`, v náhledu promptu: za zamčeným jádrem
stojí věta o souboru se zadáním s ukázkovou cestou a pod blokem poznámka, že se připojí jen u PR,
ke kterému se zadání sehnalo.

### #347 — rezerva na scroller v konci logu byla odměřená na scrolleru, který se nekreslí

`LogTailTextView.horizontalScrollerHeight` nechávala na vodorovný scroller **13 bodů**, ale u #343 se
změřilo, že legacy scroller zabere **17**. Rozpor ležel zapsaný v `docs/architektura.md` bez vlastního
issue; #347 ho zakládalo proto, aby se neztratil.

**Nebyl to odhad, a to je na tom to podstatné.** Třináct bodů je
`NSScroller.scrollerWidth(for: .small, scrollerStyle: .legacy)`, tedy **skutečně odměřená hodnota —
jiného ovládacího prvku**. `makeScrollView()` nechává `NSScrollView`u výchozí **`.regular`**, a ten bere
17. Je to čítankový příklad #236 (kdo si říká o velikost, musí ji měřit na tom, na čem kreslí) a hůř se
hledá než odhad, protože konstanta vypadá odměřeně. Vypadala odměřeně i **testu**, který ji držel: ptal
se API na `.small`, tedy zopakoval tu samou úvahu, a byl proto zelený nad rozbitou hodnotou.

Změřeno **u obou stylů**, protože jeden je půlka problému: okýnko o výšce 441 má s **legacy** stylem
`clip.h` 424 (zábor **17**), s **overlay** 441 (zábor **0** — overlay plave nad obsahem, i když je
17 bodů vysoký). Rezervuje se legacy jako **horší případ**.

Co ty 4 body dělaly, a **na každém konci jinak**. Nezastropované okýnko bylo o **2 body** nižší než
jeho vlastní dokument (dva ze čtyř spolkl slack na prokládání posledního řádku, který `height` počítá
navíc), takže log, který se měl vejít celý, dostal svislý scroller a odscrolloval se — horní řádek se
ořezal (třířádkový log: `výška 63, na text 46, origin.y 2`, po opravě `67 / 50 / 0`). Zastropované
okýnko ukazovalo **29,71 řádku** místo třiceti, tedy strop sliboval 30 a ukázal 29.

**Rozhodnuto pro konstantu, ne pro dotaz na API**, a je to zapsané ve specifikaci i u konstanty:
`NSScroller.scrollerWidth` je `@MainActor` (dědí z `NSControl`), kdežto výška se počítá `nonisolated`
— a hlavně `CheckDetailView.logMaxHeight` je ručně vybraná konstanta, která musí být
`14N + 2 × inset + rezerva`; s rezervou známou teprve za běhu by se u stropu nedalo tvrdit, že padne na
celý řádek, právě tam, kde se vybírá. Ty dvě konstanty jsou **pár**, takže se strop posunul **441 → 445**
(pořád 30 řádků, `14N + 25`). Rozhodnutí „30 řádků“ z #303 tím zůstává; **přeměřeno**, co to stojí
seznam checků (`CheckLogRoomProbe`, řádek 28 bodů): na skutečném okně 172 → 168 bodů, tedy **pořád
6 řádků**, zaplatí to okno 810, kde ze 30 bodů zbyde 26.

Co se **nezměnilo**, ať to někdo nehledá jako regresi: u horní hrany zastropovaného okýnka je necelý
řádek vidět i po opravě — `2 × inset` leží uvnitř dokumentu a skáče se na jeho úplný konec, takže
mřížka řádků na hranu viewportu nepadne. Rezerva rozhoduje o **výšce**, ne o zarovnání mřížky. Zadání
mluvilo o „uříznutém posledním řádku“; ořezaný je horní, a jen u nezastropovaného okýnka.

Testů je **2768**: nová sada `LogTailScrollerReserveTests` přidala **5** (jeden z nich přes pásmo pěti
výšek okýnka) a **jeden ubyl** — ten vacuous, který se ptal API na `.small`. Nová sada se ptá
**kresby**, ne API: postaví `makeScrollView()`, vynutí styl na instanci a odečte, kolik z výšky ubylo.
Regrese ověřena vložením regrese a rozhodovalo, že padá **na těch bodech, ne na timeoutu**: s vrácenou
rezervou 13 a stropem 441 padnou **4 testy a 13 tvrzení** za 3,3 s (`abs(legacy − rezerva) → 4.0`,
`13.0 == 17.0`, `visible → 74.0 >= 75.5`, `origin.y → 2.0 == 0.0`, `0.2857` řádku). `LogTailHeightTests`
u toho projde celá — a je to ta hranice, proč je nová sada zvlášť.

**Vidět je to jen jako 4 body výšky okýnka**, takže na proklikání nebylo co ukazovat; zkontrolováno
offscreen renderem před a po (`CheckLogRoomProbe` i nový dump okýnka pod `PRISM_RENDER_DIR`). Zapsané
u toho zůstává, že v renderu celého tabu ta chyba **vidět není**: scrollery se v testovacím procesu
usadí obvykle na `overlay`, kde je rezerva čisté odsazení — proto ten dump vynucuje `legacy`.

Vedle toho se `TestWait.awaitSettledScrollerStyle()` (#343) přestěhoval z privátní metody
`LogTailOpeningTests` do **`TestWait`**, protože ho potřebuje i nová sada a čekání má v tomhle repu
jedno místo (#296).

### #351 — zabitá aplikace už nenechá běžet osiřelý `claude -p`

Od #264 se session zabíjí při zrušení i při ukončení, ale ta záruka platí jen pro **normální**
ukončení. Když aplikace ztuhne a zabije se
zvenčí, úklid se nemá kde spustit: potomek spuštěný `Foundation.Process`em přežije rodiči `SIGTERM`
**i** `SIGKILL` a přejde pod `launchd` (změřeno `ps -o ppid` na harnessu, který spouští potomka
stejně jako `LaunchedProcess`). Platí se tedy za review, jehož výsledek nemá kam doručit.

**Prevence se zamítla měřením, ne úvahou.** Darwin nemá nic jako `PDEATHSIG` (v `sys/spawn.h` takový
flag není, tedy ani přes `posix_spawn` napřímo), `PROC_SETPC_TERMINATE` je podle `libproc.h` o
hladovění po paměti a nastavuje se sám sobě, a procesová skupina nepomůže, protože
`Foundation.Process` dává potomkovi **vlastní** (změřeno: `PGID == PID` potomka). Zbývá tedy úklid
**po**: běžící session se zapisují do cache (`sessions.json`) a osiřelé zabije **další start**
aplikace. Cena je, že sirotek žije do dalšího spuštění — v praxi vteřiny, protože zaseknutá aplikace
se zabíjí právě proto, aby se spustila znovu.

**Nejcennější tvrzení je negativní: nezabije se cizí session.** Identita je `(pid, startedAt)`
z jádra, nikdy jen PID (čísla se recyklují) a nikdy hledání v `ps` podle jména nebo promptu — na
stroji běží `claude` i mimo aplikaci. `ProcessInspecting.kill` proto bere **identitu**, ne PID,
a ověří si ji ještě těsně před signálem. Záznam navíc nese **vlastníka**, tedy instanci aplikace,
která běh spustila, a sirotek je jen ten, jehož vlastník už neběží: bez toho by běh testů zabil
review běžící aplikace, protože testovací host má stejné `CFBundleName`, tedy tutéž cache.

Testů je **2793** a jsou zelené (po sloučení s #347). Rozhodnutí sedí v `Policy.orphanVerdict` jako čistá funkce se třemi
výsledky a testuje se vyčerpávajícím výčtem devíti kombinací; regrese ověřena vložením ve čtyřech
podobách (bez porovnání identity, bez kontroly vlastníka, bez zápisu značky, bez podmínky na zápis
při úklidu) a každá položí jiná tvrzení. **Na tomhle není co vidět** — v okně se nemění nic, je to
procesní hygiena.

**Změřeno na běžící aplikaci ve slotu, ne jen v testech.** Do cache slotu se položil stav, v jakém
aplikace je uprostřed review (značka s vlastníkem = běžící PRism a procesem = dlouho běžící
podproces), pak se aplikace zabila zvenčí a `ps -o ppid` řekl, co se stalo: po `kill -TERM` i po
`kill -KILL` podproces **přežil**, a po restartu aplikace **zmizel**. Kontrolní skupina — sirotek
se **živým** vlastníkem — zůstala běžet a její značka v souboru taky. Cizí `claude` na stroji
(dva paralelní agenti, uživatelovy session) se u toho nedotkl žádný: nejstarší běží dál deset dní.
A PID přitom během měření **přetekl** z 99902 na 201, což je doklad, že recyklace čísel není teorie.

### #350 — okno tuhlo při běžícím review, a byla to jedenáctibodová animace (jedna příčina ze dvou)

Hlavní aplikace se třikrát za jedno dopoledne dostala do stavu, ve kterém hlavní vlákno viselo na
**83–100 % CPU**, okno reagovalo se zpožděním a `bin/run.sh` na něm padal na `-1712`, protože Apple
event na ukončení nedostal odpověď. U prvních dvou spadlo CPU k nule v okamžiku, kdy dojela poslední
`claude` session; **u třetího neběželo nic** (98,6 % a nula potomků), což je ta nesrovnalost, ze
které nakonec vyšlo, že příčiny jsou dvě.

**Hypotéza v zadání byla mimo, a to o dva řády.** Vypadalo to na události průběhu review: každá
zašpiní tělo `PullRequestDetailView` (hlavička čte `reviewProgress(for:)`), takže se přepočítá pruh
záložek se všemi odznaky a přestaví se obsah tabu. Cena je změřená — **9–55 ms na událost** podle
toho, co je v okně vidět —, jenže **frekvence je 0,07 až 0,37 události za sekundu** (změřeno na
145 transcriptech skutečných běhů PRismu v `~/.claude/projects/`), tedy nejvýš dvě procenta
procesoru. Navíc se u toho ukázalo, že cena je v **zašpinění těla**, ne v té práci: zápis do
`reviewPhases`, který s časovou osou nedělá nic, stojí přesně tolik.

**Příčina byla ve `sample`u, jen se z něj musel číst podíl místo vrcholů zásobníku.** U druhého
tuhnutí mělo hlavní vlákno 3709 vzorků a **3599 z nich** (97 %) leželo pod
`NSDisplayCycleFlush → NSHostingView.layout()` — tedy v rozvržení, které se opakuje samo, **bez
jediného rámce aplikace**. Vinen byl `SpinningRing`, jedenáctibodový prstýnek „review běží“ v pruhu
záložek (#180), který se točil `withAnimation(.linear.repeatForever)`. Nekonečná animace ve SwiftUI
si vyžádá průchod při každém obtažení obrazovky a ten jde přes `NSHostingView.layout()`, které
rozvrhne **celé okno — a dvakrát**: jednou pro kresbu, jednou pro `minSize` do constraints
(půl na půl, 1378 proti 1374 vzorkům).

Sonda `IdleWindowSpinProbe` to reprodukovala v harnessu, u nečinného okna s otevřeným PR:
**99 % CPU** s prstýnkem ve SwiftUI, **2–3 %** po převedení na CoreAnimation — tedy přesně tolik,
kolik stojí totéž okno **bez prstýnku**, takže z ceny nezbylo nic. Klíčový je u toho čtvrtý případ:
**prstýnek sám, bez detailu v okně, stojí 3 % místo 99** — cena tedy není v tom prvku, ale v tom, co
je vedle něj v okně. Proto to nezáviselo ani na počtu běžících session, ani na tom, který tab byl
otevřený.

**Tři vzorky ze zadání ale mají dvě různé signatury, ne jednu, a tohle je právě to zjištění, které
z rozdělané práce po předchozí session zbývalo dodělat.** Rozhoduje **kořen** cesty, ne listy:

| Vzorek | Kořen 100 % vzorků hlavního vlákna | Co v něm je | Vysvětluje ho |
|---|---|---|---|
| 2 (computed properties detailu) | `NSDisplayCycleFlush → NSHostingView.layout()` (3591) + `NSAnimationContext.runAnimationGroup` (1754) | takt překreslování obrazovky | **prstýnek** — opraveno tady |
| 1 (osa konverzace) a 3 (diff) | `NSRunLoop.flushObservers → NSHostingView.beginTransaction → GraphHost.flushTransactions` (3663/3663, resp. 3679/3679), **display cycle nula, `runAnimationGroup` nula** | rozvržení líného seznamu (`LazySubviewPlacements`, `ScrollViewLayoutComputer.Engine.sizeThatFits`) | **jiná příčina** — #358 |

Že to nejsou dva pohledy na jedno, je **ověřené vložením regrese, ne úsudkem**: nad buildem
s vrácenou SwiftUI animací vyšel `sample` testovacího hosta zase na `NSDisplayCycleFlush`
(144 z 976) a `runAnimationGroup` (127), kdežto `flushObservers` v něm byl **nula**. Prstýnek tedy
signaturu vzorků 1 a 3 **neumí vyrobit**. A u vzorku 3 nebyl vůbec na obrazovce — pruh záložek ho
kreslí jedině při `isRunning`, což je `reviewTasks[pr] != nil`, a v tom vzorku neběžela žádná
session.

**Ta druhá příčina se nepřibalila** a je to schválně (pravidlo o jedné změně v jednom PR i o měření
před/po) — je z ní **#358**. Co se o ní ví: cena je v tom, že `ScrollView` počítá **ideální
velikost**, což donutí líný seznam projít `_LazyLayout_Subviews.apply` přes **celý** `ForEach`, a
děje se to při každém průchodu smyčky.

**Co graf špiní, se doměřilo na živém ztuhlém okně**, až když se to podařilo reprodukovat — je to
**hover**. Ve vzorku (30 s po 1 ms, 23 653 vzorků hlavního vlákna) leží 92,8 % v jedné transakci a
**žádný jiný callout tam není**: nula vzorků na timeru, nula na hlavní dispatch frontě, nula na
obsluze událostí, takže smyčku nekrmí nic zvenčí. Uvnitř je 1630 z 1690 vzorků
`Update.dispatchActions()` v `EventBindingManager.enqueueHoverUpdateIfNeeded()` →
`NSHostingView.didRequestHoverUpdate()` a přes `HoverResponder.updatePhase(_:)` se z něj volá
`.onContinuousHover` v `DiffPairBlockRowView`. Ta akce zapíše `@State hovered` **bez porovnání se
stávající hodnotou** — a je to `(index: Int, side: DiffSide)?`, tedy tuple, který v Swiftu
`Equatable` **není**, takže na něm nemůže zabrat ani žádné porovnání výš. Tím se kolo zavře: zápis →
neplatné tělo bloku → neplatné `LazySubviewPlacements` → přeloží se všechny podviews → změní se
geometrie responderů → další hover update. Druhý, slabší re-arm je
`LazyLayoutViewCache.signalPrefetch()` → `NSHostingView.requestUpdate(after:)` (55 vzorků).

**Ověřeno po opravě na běžící aplikaci, se zaparkovaným kurzorem nad blokem kódu ve split diffu**
(aplikace vpředu, ruce pryč). Za 20 s nečinnosti se kumulativní CPU čas procesu **nezměnil vůbec**
(`0:09.58 → 0:09.58`, tedy 0,00 s; kontrolní desetisekundový odečet taktéž 0,00 s), a ve `sample`u je
**4394 ze 4394** vzorků hlavního vlákna v `mach_msg2_trap` — vlákno tedy spí ve frontě událostí a
v celém vzorku není **ani jeden** výskyt `flushTransactions`, `LazySubviewPlacements`,
`dispatchActions`, `enqueueHoverUpdateIfNeeded`, `didRequestHoverUpdate` ani `signalPrefetch`.

Z toho plyne jedna věc, která byla do téhle chvíle **předpoklad, a je z ní měření**: slabší re-arm
přes `signalPrefetch` se **nesrovnal „nízko a nenulově“, zmizel úplně**. Prefetch si o další kolo
říkal právě proto, že se rozvržení pořád přepočítávalo — jak přestala být `LazySubviewPlacements`
neplatná, přestal i on. Poctivá výhrada k tomu měření: **poloha kurzoru se programově neověřila**
(systémový `python3` na stroji nemá `Quartz`), takže „myš ležela nad kódem“ je z lidského slova;
aplikace vpředu a ta nulová čísla ověřená jsou.

**Proč se to nedařilo reprodukovat:** chyběl **kurzor ležící v okně nad blokem kódu** (ověřeno na
živém stavu přes `NSEvent.mouseLocation` a `CGWindowListCopyWindowInfo`). Pokusy byly „otevřený PR se
třemi a čtyřmi soubory, přepnutí na `Změněné soubory`, projetí diffu, nečinnost“ → `%cpu` **0,0** —
a „nečinnost“ znamenala nechat myš tam, kde skončila. Bez hover responderu se smyčka nemá čím zavřít.
Podmínkou je **split diff** (`DiffPairBlockRowView`, tedy tuple stav); velký diff kolo jen zdraží,
neschová. A **běžící review je zhoršovák, ne podmínka**: doloženo tím, že potomek `claude` během
sledování skončil a okno zůstalo minutu dál na **98,2–100,5 %** CPU bez potomků.

Prstýnek je od #350 `SpinningRingView` — `NSView` se dvěma `CAShapeLayer`y a `CABasicAnimation` na
`transform.rotation.z`. Kresba je změřená na pixelech (oblouk 0,35 kruhu = 0,30 ze `strokeEnd` plus
kulaté zakončení tahu, tichý kruh 0,65) a otáčení na prezentační vrstvě (~1,4 rad za 0,2 s, tedy
jedna otáčka za 0,9 s). `ProgressView` v kapslích reviewerů zůstává — na macOS ho animuje AppKit,
takže do téhle pasti nepadá (3 %).

Z toho je nové pravidlo v `CLAUDE.md` i grep, který musí vyjít prázdný. Testů je **2803**; vidět je
totéž co dřív — kresba se ověřila na skutečném okně, tedy zvětšeným výřezem pruhu záložek z pěti
snímků po 0,7 s, na kterých sytý oblouk objíždí kruh po směru hodin. **Nepřibalené a otevřené**
zůstávají dvě věci, obě změřené: zašpinění těla detailu událostí průběhu (9–55 ms na událost při
0,07–0,37 události za sekundu, tedy nejvýš 2 % CPU) a **druhá příčina tuhnutí** z tabulky výš,
která je jako **#358** a s doměřenou příčinou (hover, viz výš). Na to zašpinění těla detailu
událostí průběhu vlastní issue zatím není.

### #358 — druhá příčina tuhnutí: hover si sám plánoval další kolo

Zbylá příčina z #350. Zadání ji mělo popsanou z vzorků, ale **chybělo v něm to jediné, na čem
oprava mohla stát: co ten graf pokaždé zašpiní.** Reprodukovat se to na vyžádání nedařilo (PR se
třemi a čtyřmi soubory, přepnutí na `Změněné soubory`, projetí diffu, nečinnost → `%cpu` 0,0),
takže se nejdřív musela najít reprodukce a teprve pak psát kód.

**Reprodukce má tři složky a ta třetí je celé vysvětlení, proč to dřív nešlo:** split (side-by-side)
diff, velký diff, a **kurzor ležící v okně nad blokem kódu**. „Nečinnost“ v neúspěšných pokusech
znamenala nechat myš tam, kde skončila — a bez hover responderu se kolo nemá čím zavřít. Ověřeno na
živém ztuhlém okně přes `NSEvent.mouseLocation` a `CGWindowListCopyWindowInfo`: ukazatel byl uvnitř
rámce okna. Velikost diffu kolo jen **zdraží** (jedno kolo je průchod celým `ForEach`em), nezpůsobí.

**Co graf špiní.** Ve vzorku (30 s po 1 ms, 23 653 vzorků hlavního vlákna) leží 92,8 % v jedné
transakci a **žádný jiný callout tam není**: nula na timeru, nula na hlavní dispatch frontě, nula na
obsluze událostí — smyčku tedy nekrmí nic zvenčí. Uvnitř je 1630 z 1690 vzorků
`Update.dispatchActions()` v `EventBindingManager.enqueueHoverUpdateIfNeeded()` →
`NSHostingView.didRequestHoverUpdate()` a přes `HoverResponder.updatePhase(_:)` se z něj volá
`.onContinuousHover` v `DiffPairBlockRowView`. Ta akce zapsala `@State hovered` **bez porovnání se
stávající hodnotou**, takže: zápis → neplatné tělo bloku → neplatné `LazySubviewPlacements` →
přeloží se všechny podviews → změní se geometrie responderů → další hover update. Odtud i ty listy
ze zadání (`FileDiff.id`, `DiffRow.id`) — nejsou příčina, jsou průchod.

**Tuple byl polovina problému.** Stav byl `(index: Int, side: DiffSide)?` a tuple v Swiftu
`Equatable` **není**, takže „zapiš jen při změně“ se tam nedalo napsat ani kdyby na to někdo přišel.
Je z něj proto `HoveredCell`, a rozhodnutí drží `Policy.hoverChange(from:to:)` — generické nad
`Equatable`, takže je jedno pro split (`HoveredCell?`) i pro pohled pod sebou (`Int?`). Předat se to
**nedá `inout`**: `@State` je počítaná vlastnost, takže `&hovered` projde setterem i beze změny, a
špiní právě setter.

**Sonda se zahodila, a je to změřené rozhodnutí.** Syntetická `.mouseMoved` do okna (`sendEvent`
i `NSApp.postEvent`) `onContinuousHover` **nevyvolá vůbec** — nula zásahů, SwiftUI hover řeší
z tracking areas a skutečné polohy kurzoru. První podoba sondy proto tvrdila 0 % CPU i nad buildem
s **vrácenou regresí**, tedy přesně ta vada, na kterou si `docs/testovani.md` stěžuje u kontrol
nespuštěných ve výjimečném stavu. Testuje se místo toho čistá funkce a hodnota, kterou dostane;
vložením regrese padá **6 tvrzení ve dvou sadách**. Celý zápis včetně tabulky pokusů je
v [`testovani.md`](testovani.md).

Testů je **2812** a jsou zelené. **Vidět je totéž co dřív** — pilulka na komentář svítí u řádku pod
myší a mění stranu podle poloviny; co se změnilo, je že okno u toho nespálí procesor.

**Aplikace ví, kdo se dívá (#330)** — `GitHubGateway.fetchViewer()` přes `gh api user`, login se
dotáhne **jednou při startu** a `Policy.ownership(of:mine:)` z něj rozřadí seznam na `.mine`
a `.theirs`. Rozhoduje **autor PR, ne zdroj**, ze kterého přišel: jeden PR umí splňovat víc dotazů
naráz, takže rozřazení podle zdroje by záviselo na tom, jak si člověk dotazy poskládal. Sama
`PullRequestList.merged` se nemění — rozřazení se počítá nad hotovým seznamem.

**Prázdný viewer znamená „nevím“, ne „to jsem já“**, a je to nejcennější věta celého issue: dokud
login nedorazí (nebo se ho nepodaří zjistit), je všechno `.theirs`. Obrácené výchozí chování by při
startu na okamžik přehodilo celý seznam do „moje“ a fronta cizích PR by zmizela. Vložená regrese
(`mine.isEmpty → .mine`) shodí **11 testů**, mezi nimi tři z #114 — porovnání je totiž doopravdy na
jednom místě: `Policy.isOwn(author:viewer:)` chodí přes tutéž funkci.

**`ownership` bere množinu loginů, ne jeden řetězec** (viewer + nový `ownLogins` v konfiguraci).
Agent s vlastním účtem (`github-actions[bot]`, Copilot) by do `.mine` nespadl; dneska to nevadí —
agenti v tomhle repu pushují přes moje `gh` a mají autora `ondrajodas` (ověřeno na živých datech) —
ale dolepovat druhý login potom by znamenalo projít všechna místa, která se ptají „je to moje“. Pole
je **jen v souboru, ne v okně nastavení**: nová sekce nastavení je změna vzhledu, tedy mockup
a schválení, a je to jednorázová věc pro toho, kdo si pouští agenta pod vlastním účtem.

**Do výchozích zdrojů přibylo `author:@me is:open`** (`Source.mine`) a je to **vědomá výjimka**
z pravidla, že se výchozí hodnoty nesmí rozejít s tím, jak aplikace běžela dřív: bez toho zdroje by
sekce `Moje PR` (#331) neměla odkud brát data. **Uložená konfigurace se nemigruje** — `decodeIfPresent`
vezme, co je v souboru —, takže na mém stroji ten zdroj nepřibude a sekce by zůstala prázdná; že
chybí, pozná `Policy.tracksOwnPullRequests` (poznává token `author:`, ne jméno zdroje) a napíše to
prázdný stav sekce. Dopsat uživateli do ručně editovaného souboru dotaz, o který neřekl, by byl
zásah do jeho věci — a dotaz navíc při každém tiku.

**Rozhodnuto jinak, než bylo v zadání**, dvakrát a v obou případech jen v detailu: `fetchViewer()` je
**šestnáctá** čtecí metoda protokolu, ne dvanáctá (dokumentace u toho měla o jeden vedle už dřív —
text tvrdil čtrnáct nad patnáctipoložkovým výčtem), a login se **dekóduje jako JSON**, ne přes
`--jq .login`: `--jq` na chybějící pole vypíše prázdný řádek s nulovým návratovým kódem, tedy
prázdný login — a to je zrovna ta hodnota, která v aplikaci znamená „nevím“. `AppStore.isOwnPullRequest(_:)`
zůstává na `Conversation.viewer` schválně: přepnout ho na login ze storu by změnilo, kdy se v panelu
předvyplňuje verdikt, a to je viditelná změna a věc panelu vlastního PR (#333).

Testů je **2843** a jsou zelené (+31). **V okně není vidět nic** — je to součástka, kterou zatím
nikdo nekreslí; jediné, co je vidět, je nový výchozí zdroj, a ten se projeví **jen na prázdné
cache**: v seznamu se pak vedle cizích PR objeví i vlastní (změřeno `gh search prs`: 13 cizích proti
17 vlastním). Fronta, dashboard, automat a notifikace se od vlastních PR odřízly v #332 (viz níž).

**Moje PR jsou druhá fronta (#331)** — v railu přibyla sekce `Moje PR` mezi `Frontou`
a `Rozdělanými` (`RailSection.mine`, šipka nad vaničkou) a na dashboardu **dva bloky pod sebou**
(`Čeká na moje review` a `Moje PR`) plus **pátá karta**. Seznam je **tentýž
`PullRequestListView`** nad druhou množinou (`PullRequestListScope`), takže filtr, řazení i otevření
záložky platí beze změny; rozřazuje `Policy.pullRequests(_:ownedBy:mine:)`, tedy **další zúžení nad
zúženým seznamem**, ne nový zdroj pravdy — kdyby na něm viselo cokoli z úklidu, přihlášení jiným
účtem by smazalo cache.

**Karta `Ve frontě` se přejmenovala na `Čeká na mě`** a přibyla `Moje PR`: velké číslo je počet
otevřených, věta pod ním kolik z nich **čeká na tah**. Akcentový proužek se přestěhoval z karty
`Rozdělaná review` sem, jak to má návrh — dva proužky vedle sebe by přestaly znamenat, která karta je
ta o mně.

**Odznak počítá práci, ne PR** (`Policy.ownPullRequestsAwaitingMove`): PR s nezpracovaným nálezem
nebo s nevyřešeným cizím vláknem. Šest PR, ze kterých pět čeká na CI, není šest věcí k práci. Vlákna
se počítají **jen z načtených konverzací** (tahají se při výběru řádku, ne při pollingu), takže je to
**spodní hranice** — a neúplnost je schválně v tomhle směru: odznak, který napočítá víc práce, než jí
je, se přestane čítat. **Doplnilo to #335**: konverzace vlastních PR dorazí sama (rozhlídka na pozadí), takže se hranice posunula — zbývá jen tam, kam jeden průchod nedosáhl.

**Prázdná sekce má tři různé věty** (`Policy.ownListEmptyReason`) a pořadí důvodů je celý obsah
issue: polling → chybějící zdroj → nenačtený login → filtr → prázdno. Bez zdroje `author:@me is:open`
se aplikace na vlastní PR vůbec neptá, takže „nic tu není“ by vypadalo jako uklizený stůl — sekce
místo toho nabídne nastavení. Nenačtený login je třetí stav: podle autora je pak všechno cizí, což
není „nic nemám“, ale „nevím, kdo jsem“ (dohodnuto už v #330).

**Rozhodnuto jinak, než bylo v zadání**, čtyřikrát a v každém případě s důvodem. Řádek vlastního PR
má `Prompt →` **vedle** odznaku stavu, ne místo něj: pilulku `6 k předání` z návrhu se dá napsat
teprve tehdy, až předání existuje (#333) a nese razítko (#334), kdežto odznak říká to, co se ví — že
reviewer běžel a s jakým výsledkem —, a to je zrovna materiál, který prompt ponese. Tlačítko bylo
v #331 **zakázané a ztlumené**, protože plné akcentové tlačítko, po kterém se nic nestane, je lež
o tom, co okno umí (napojilo ho #333, viz níž); ztlumení kreslí řádek, protože `MiniButtonStyle` se
na `isEnabled` neptá (v celé aplikaci, ne jen tady — vlastní otázka na návrh). Blok `Moje PR` na
dashboardu **nemá popisek** `jen s nálezy`, který návrh kreslí vpravo v hlavičce: nic se nefiltruje,
takže by ten text tvrdil něco, co se nedělá. A **věta pod pozdravem se nezměnila**, ačkoli návrh má
„Na dvou vlastních leží nálezy k předání.“ — dokud `Čeká na mě` počítá i vlastní PR, mluvila by ta
druhá věta o týchž pull requestech dvakrát. (Dopsalo ji #332, jak se ta karta zúžila.)

**Známé omezení, které tenhle kus vydal a #332 odstranilo:** `railQueueCount`, `Policy.dashboard`,
automat i notifikace počítaly pořád i vlastní PR, takže vlastní PR byl na dashboardu vidět **v obou
blocích** a v čísle karty `Čeká na mě` (nahlášeno z provozu jako 32 = 13 cizích + 19 vlastních). Byl
na to test, aby se ta oprava nestala mimochodem — v #332 se z něj stalo tvrzení obrácené.

Testů je **2881** a jsou zelené (+38). K tomu sonda `OwnPullRequestsRenderProbe` (dashboard a čtyři
podoby sekce), protože ke dvěma z těch stavů se klikáním nedostaneš a dashboard se ve skutečném okně
s třiceti PR ve frontě celý nevyfotí.

**Na vlastním PR panel sbírá zadání pro agenta, ne verdikt (#333)** — třetí mergnutý kus M10.
Pravý panel měl na vlastním PR všechny tři věci k ničemu (tělo, verdikt, `Odeslat`), protože
`APPROVE` i `REQUEST_CHANGES` tam GitHub vrací jako 422 (změřeno u #62). Segment `Moje review` proto
na vlastním PR **zmizel celý** (ne zašedl) a na jeho místě je `Zadání`: sedm zaškrtávacích voleb
s počty, náhled textu a `Sestavit prompt →`, který otevře sheet s celým markdownem, `Zkopírovat`
a `Uložit do souboru…`.

**Tlačítko `Prompt →` z #331 dostalo akci** a tím zmizel poslední zakázaný prvek v okně: otevře PR
a v něm panel `Zadání` (`AppStore.openAgentPrompt(in:)` = `openTab` + `revealAgentPrompt`). Otevřít PR
je **součást** akce, ne krok před ní — konverzace se nepersistuje a tahá se při zobrazení, takže
sestavit text rovnou ze seznamu by dalo zadání bez vláken, komentářů pod PR a souhrnů review, tedy
bez tří druhů ze čtyř. Ze stejného důvodu **není zakázané**: `hasAgentPromptItems` hlídá sazbu textu
(zkratka a `Sestavit prompt →`), a v seznamu by měřilo stav před otevřením PR — zakázalo by cestu
k panelu zrovna u PR, jehož materiál je v diskuzi. Řádek **bez akce** (náhled, test) tlačítko nekreslí
vůbec; je na to test na výšce řádku.

Text skládá čistá funkce `Policy.agentPrompt(…)` ze **čtyř druhů** toho, co aplikace o PR ví —
nálezy reviewerů, vlákna u řádků, komentáře pod PR a souhrny review. Seskupuje se **po souborech, ne
po zdrojích** (agent otevírá soubor, ne revieweera), původ se nese v textu, a co soubor nemá, stojí
v sekci `K celému PR (bez souboru)` **před** nimi. Vyřešená vlákna a odmítnuté nálezy v textu
nejsou, ale **jsou spočítané** a dají se zapnout; hlava PR je v hlavičce textu (tvrdá podmínka č. 5)
a nenačtená konverzace je přiznaná i v textu, protože zadání se předává dál.

**Draft review na vlastním PR nesmí ani vzniknout** a je to půlka issue: zakládá se čtyřmi cestami
přes diff, takže je zavírá jedna brána (`canComposeDraft(for:)`, dva volající ve view) tím, že se ta
tlačítka **nekreslí**. Co tam zbylo z dřívějška, se ale **nezahazuje** — zůstává vidět v panelu
`Zadání` i v bublinách diffu a jde smazat.

**Tvrdá podmínka č. 1 se nemění a od téhle změny na ni je test** (`SingleWayOutTests`): čte zdrojáky
a tvrdí pět souborů u `ReviewPublishing`, čtyři metody protokolu a že ani jeden ze souborů zadání
nezná publisher, payload, API ani podproces. Prompt končí ve schránce nebo v souboru, který
vybere člověk v `NSSavePanel`u — a selhání zápisu se **ukáže**, protože po zavření sheetu se text
nemá kde vzít znovu.

**Rozhodnuto jinak, než bylo v zadání**, ve třech detailech: popisky dvou voleb nejsou z mockupu
doslova (`Nevyřešená vlákna u řádků` a `Souhrny review` bez „od kolegů“, protože do zadání jde i to,
co jsem si na vlastním PR napsal sám); draft z dřívějška bydlí **v panelu se zadáním**, ne ve třetím
segmentu (tři segmenty se do 240 bodů nevejdou); a řádek stavové lišty `Vlastní PR — review se odsud
neodesílá` ani mint pilulka `moje PR` v hlavičce **nepřibyly** — je to chrom sdílený s #331 a #332.
Levý seznam `Co je potřeba opravit` ze sekce 22 tenhle kus taky nekreslí: zadání #333 vyjmenovává
panel, čistou funkci a sheet, a počty i celý obsah jsou v nich.

**Sheet se po proklikání rozšířil o polovinu** (`minWidth` 560 → 840, `idealWidth` 720 → 1080)
a posunul se **celý rozsah**, ne jedna mez: se zvednutým `idealWidth` by stažené okno spadlo zpátky
na šířku, kvůli které se to měnilo. Doloženo renderem v obou mezích — na 720 b spadl odznak
`vynecháno: 1 vyřešené vlákno` do druhé řady a úvodní odstavec zabral pět řádek, na 1080 se odznaky
vejdou do jedné řady a odstavec do tří. Mockup (sekce 23) drží tutéž hodnotu.

Testů přidala tahle změna **56** a po sloučení s #331 je jich **2943**; jsou zelené, z toho jeden je
sonda, která se pouští ručně.

**Paleta ⌘K má vlastní skupinu `Moje PR` (#336)** — čtvrtý mergnutý kus M10. Do té doby byla
skupina jedna a vlastní PR v ní k nerozeznání od cizích, přestože se s nimi dělá něco jiného.
Rozdělení stojí na **stropu**: `Policy.paletteGroupLimit` je šest a platí **na skupinu**, takže ve
společné skupině by při dvaceti cizích PR to moje nemuselo vyjít vůbec — a odznak `moje` u řádku ten
problém neřeší, jen ho schová, protože řádek, který se do šestice nevešel, není o čem odznak.

Přibyl **jeden případ** (`CommandPalette.Group.myPullRequests`, za `pullRequests`, protože cizí PR
jsou to, na co se čeká), první skupina se přejmenovala na `Pull requesty k review` a katalog
v `AppStore+Palette` rozřazuje řádky podle `Policy.ownership` — tedy tou samou funkcí jako rail
a dashboard (#330), podle **autora**, ne podle zdroje. Množina loginů se bere jednou pro celý
seznam. Dokud nedorazí `viewer`, je všechno cizí, takže se paleta při startu nepřehodí do druhé
skupiny a zpátky.

**Cíl zůstal `Target.pullRequest`** a skupina je jen zařazení: druhý případ by byl druhá cesta
k témuž a rozešel by se. Klávesová navigace se **nezměnila a nemusela**: kurzor v `CommandPaletteView`
běží nad `sections.flatMap(\.hits)`, takže se nadpisy do indexů nepočítají a pátá skupina se do
výsledků dostane sama z `allCases`. Strop výšky karty (400 b) zůstal — vejít se všechno nemohlo ani
ve čtyřech skupinách, takže by zvednutí jen posunulo, od kolika řádků se scrolluje.

**Rozhodnuto jinak, než má sekce 09 návrhu**, ve dvou detailech u řádku vlastního PR. Podtitulek
zůstává `PRism#324 · ondrajodas` místo `· 6 k předání`: je to tatáž úvaha, kterou u řádku seznamu
zapsalo #331 — předání nemá razítko (#334), takže by to byl počet, který nikdo nepředal. A puntík
zůstává v barvě **stavu PR**, ne v mintu: mint by říkal „moje“ podruhé (jednou to říká nadpis
skupiny) a přebil by jedinou věc, kterou ten puntík v paletě nese — `author:@me is:open` vrací
i drafty a slovo `draft` má jen řádek seznamu. **Měření mluví pro stav, ne proti**: `--ok` a `--mint`
se od sebe liší dost (ΔE76 34 ve světlém, 46 v tmavém režimu), takže by mint tu barvu doopravdy
přebil. Odhad z pohledu na malý puntík ve snímku říkal opak — proto se to počítalo, a je to zapsané
i jako poučení: barvu se nemá posuzovat na patnáctibodové ikoně.

Testů přidala tahle změna **devět** a je jich **2952**; jsou zelené, z toho jedno je sonda
`CommandPaletteRenderProbe`, která se pouští ručně (karta ve dvou podobách — zúžená na počty řádků
z návrhu a nad celým katalogem). Sonda existuje proto, že paletu otevírá jedině ⌘K a psát do cizí
instance se v paralelním běhu nemá. Rozdělení je ověřené **vloženou regresí**: se všemi PR v jedné
skupině a starým nadpisem padne pět testů a osm tvrzení.

Vedle toho z toho vyšla jedna oprava mimo zadání: `try! #require` v testu **položí celý běh**, takže
sečtený řádek hlásí „0 tests passed“ a kdo čte jen poslední řádek, přečte si opak. V `Tests/` byly
dva výskyty (jeden z #184, jeden nový) a padly oba — teď je test `throws` a `#require` se volá `try`.
**Fronta, dashboard, automat a notifikace se týkají cizích PR (#332)** — pátý mergnutý kus M10
a dokončení #331, ne úklid po něm. Do #332 čtla všechna ta místa plný seznam a předpokládala, že „PR
= něco, na co se čeká“, takže vlastní PR byl na dashboardu vidět **v obou blocích** a započítaný
v kartě `Čeká na mě` — v provozu z toho bylo `32 = 13 cizích + 19 vlastních`. Nic z toho nespadlo,
všechno jen tiše ukázalo špatné číslo.

**Zúžilo se to po místech, ne plošně**, a rozhodnutí „které místo chce kterou množinu“ je celý obsah
issue; tabulka je v [`architektura.md`](architektura.md). Jen cizí PR (`AppStore.queuePullRequests`,
`visibleQueuePullRequests`) čte sekce `Fronta` a její odznak, číslo schovaných řádků v liště nad ní,
prázdný stav fronty, karty `Čeká na mě` a `Blokuje`, blok `Čeká na moje review`, souhrn ve stavovém
řádku, hromadná akce `Pustit review na vše, co neběželo`, automat a notifikace. **Obojí** čte dál
úklid nálezů, `CacheEviction`, `forget(whatIsNotIn:)`, okno nastavení, nabídka filtru, sekce
`Rozdělaná` s kartou `Rozdělaná review` a klik na notifikaci — kdyby se úklid navázal na frontu,
přestaly by se uklízet klony vlastních PR a cache by tiše rostla.

**Blokující nález na vlastním PR se do karty `Blokuje` nepočítá**: je to seznam toho, co mám opravit,
ne toho, co mi stojí v cestě k odeslání review — a karta je červená, takže by z vlastní práce dělala
poplach.

**Automat vlastní PR nevydá nikdy a přepínač se zamítl.** Filtr je v
`Policy.automaticallyReviewable` **první v řadě**, takže neprojde ani globální `mode: automatic`, ani
`RepositoryConfig` jednoho repa. Důvody jsou tři: automat existuje kvůli **čekání** (u vlastního PR
není na co čekat — review si na něm pouštím, když vím, že jsem dopsal), vlastní PR se **mění pod
rukama** (každý push je nová hlava, tedy nálezy proti kódu, který za deset minut nebude) a přepínač by
přinesl jedině **způsob, jak si to zapnout omylem**. `mine` proto u téhle funkce **nemá výchozí
hodnotu**, na rozdíl od `Policy.dashboard`: prázdná množina znamená „nikdo nejsem“, takže by zapomenutý
parametr pravidlo tiše vypnul — a tady se za průchod platí session. `autoRunsPerDay` zůstává **jeden
společný** limit a po tomhle kusu ho čerpají jedině cizí PR. **Ruční spuštění na vlastním PR jde
dál**, i tlačítkem na řádku.

**Notifikace jsou cesta pro review requesty**, takže o vlastním PR nedají vědět ani o nálezu, ani
o novém PR. Zúžení u nových PR je **na vstupu**, aby se vlastní PR nedostal ani do snímku ohlášených.
**Dokud login nedorazí** (`gh api user` běží souběžně s prvním tikem), je všechno cizí, takže vlastní
PR z prvního tiku se ohlásit může — druhá strana by byla mlčet, dokud login nedorazí, a při selhaném
dotazu by to znamenalo ztracené notifikace o **cizích** PR. Vlastní text pro vlastní PR **dopsalo #335** (pátá událost `activity`).

**Prázdná fronta dostala vlastní důvod.** Tik, ve kterém přišla jen vlastní PR, nechá frontu prázdnou,
kdežto `PollState.emptyReason` mlčí (seznam prázdný není), takže by v okně zbyl prázdný seznam **bez
věty**. `Policy.listEmptyReason` proto vydá `poll(.noPullRequests)` — „až po tobě někdo bude chtít
review, objeví se tady“, což je nad vlastními PR ta správná odpověď.

**Rozhodnuto jinak, než bylo v zadání**, ve čtyřech detailech. Zadání jmenovalo pět míst; přibyla
k nim **tři další, která čtou totéž** — číslo schovaných řádků v liště nad frontou
(`hiddenQueuePullRequestCount`, jinak by hlásila schovaný vlastní řádek nad nezměněnou frontou),
prázdný stav fronty a hromadná akce `Pustit review na vše, co neběželo` (věta „fronta je vyřízená“
vedle ní mluví o téže množině jako karta). Karta `Rozdělaná review` se naopak **nezúžila**, i když
u ní stálo, že počítá totéž co souhrn ve stavovém řádku: draft je ručně psaná práce, od #333 na
vlastním PR nevznikne a ten z doby předtím je odkud dopsat jedině z ní. Věta pod pozdravem se
**dopsala** (zbytek po #331, který se na ni odkládal), ale ne doslova podle mockupu: číslo je
**číslicí** jako všude jinde v okně a mluví o „co předat agentovi“, ne o „nálezech“ — `awaitingMove`
počítá i nevyřešená cizí vlákna. A `PullRequestListScope` zůstal **vyjmenovaný typ**, ne
`PullRequestOwnership`, i když fronta teď na cizích PR opravdu stojí: sekce nese i to, mezi kolika
prázdny se rozhoduje a jak se mluví o schovaných řádcích.

**Řádek stavové lišty `Vlastní PR — review se odsud neodesílá` ani mint pilulka `moje PR` v hlavičce
pořád nepřibyly** — #333 je odložilo na „#331 a #332“, ale je to chrom **detailu PR**, kdežto tenhle
kus mění počty; zůstalo to otevřené a **dopsalo se u #334**, které do téže obrazovky sahá razítkem.

Testů přidala tahle změna **26** a po sloučení s #336 je jich **2978**; jsou zelené. **Ověřeno
vložením regrese, jedenácti** ve dvou dávkách —
každá shodila právě ten test, který ji má chytat; výčet je v [`testovani.md`](testovani.md).

**Předáno není hotovo: razítko předání a zastaralé zadání po pushi (#334)** — šestý mergnutý kus M10
a druhá polovina #333. Sestavit prompt byl do té doby jeden okamžik, po kterém se v okně nezměnilo
nic: odznak sekce `Moje PR` svítil pořád stejně i deset minut po zkopírování a po pushi se nedalo
poznat, že předané zadání mluví o kódu, který na PR není.

**Razítko je `(kdy, proti jaké hlavě, co)` a drží ho pull request**, ne prompt (`Handoff`,
`HandoffLedger`, `handoffs.json` v cache): prompt zaniká zavřením sheetu, kdežto „předáno v 14:20
proti 9c1de02“ musí přežít restart. **U nálezů bydlet nemůže** — předat se dá i zadání, ve kterém
není jediný nález, a takové PR nemá uložený záznam vůbec; založit ho kvůli razítku by znamenalo
záznam bez běhu, který v `Policy.currentRecords` vyhraje nad nálezy z minula.

**Rozhodnuto jinak, než bylo v zadání**, ve třech věcech. Razítko nese **identity předaných položek**,
ne jen počet: s počtem by částečné předání (vypnutá volba) odepsalo nevyřešené vlákno jako předané,
kdežto s identitami je `pending` přesné číslo a opakované review s **týmž** nálezem odznak nerozsvítí.
Do materiálu se tím ale rozšířil i odznak z #331 — do #334 počítal „nezpracovaný nález nebo nevyřešené
**cizí** vlákno“, od #334 to, co jde do zadání (tedy i moje vlastní nevyřešené vlákno, komentář pod PR
a souhrn review); otázka se změnila, takže se změnil i materiál, a jeden z testů #331 se proto obrátil.
A **neznámá dnešní hlava se bere jako „neposunula se“**: hlavu zná aplikace jedině z dotaženého
detailu, takže by jinak odznak po předání nikdy nezhasl — tedy přesně to, co issue opravuje.

**Panel má tři podoby**: razítko `✓ 6 položek · dnes 14:20 · proti 9c1de02` s větou, že nic nového
nepřišlo (volby se schovají, zbyde `Sestavit znovu`); razítko s větou „od předání přibyla 1 položka“
nad běžnými volbami; a po pushi varování s počtem commitů, dvěma řádky (`Nové v diskuzi`, `Nálezy
proti staré hlavě` okrově) a dvěma cestami dál — `Pustit review znovu →` a `Sestavit i tak (jen nové
vlákno)`, které předá jen to, co po předání přibylo v diskuzi. **Zastaralé nálezy nemizí** (#113),
jen se do zadání nepředvybírají. **Review se po pushi nepustí samo** — automat se vlastních PR netýká
vůbec (#332), takže je z toho tlačítko.

**Odchylka od návrhu**: dva řádky v panelu po pushi jsou **konstatování, ne zaškrtávátka**, jak je
kreslí mockup — v tom stavu o složení zadání rozhodují ta dvě tlačítka pod nimi, takže by zaškrtávátko
slibovalo volbu, kterou ani jedno z nich nenabízí. A když po předání nepřišlo nic, není tam zakázaný
odkaz `Sestavit i tak`, ale **věta proč**: `AccentLinkButtonStyle` kreslí akcent bez ohledu na
`disabled`, takže zakázaný odkaz vypadá klikatelně.

**Dopsal se i chrom detailu vlastního PR ze sekce 22**, na který se od #333 odkládalo: řádek stavové
lišty `Vlastní PR — review se odsud neodesílá` (`OwnPullRequestStatusView`, tichá mint věta jen nad
otevřeným vlastním PR) a **mint pilulka `moje PR`** v hlavičce. K tomu pilulka `N k předání` v řádku
seznamu i na dashboardu — ta v #331 nešla napsat, protože předání nemělo razítko; kreslí se **místo**
odznaku stavu review, protože obě čísla mluví o týchž nálezech a vedle sebe by se pralo „3 nálezy“
s „6 k předání“. Ze sekce 22 zbývá nenapsaný jen počet ve stavové liště (`6 k předání · 1 vyřešeno`):
pravá strana pruhu je tvrzení o **frontě**, ne o otevřeném PR, a číslo teď nese řádek i panel.

**Tvrdá podmínka č. 1 se nemění**: razítko je lokální stav v cache, `grep ReviewPublishing App/`
vypisuje tytéž soubory a `SingleWayOutTests` prošly **bez úprav**.

**Copilot našel tři reálné věci** (třetí v druhém kole, v sekci *Suppressed comments*) a všechny jsou
opravené — ta třetí je text: věta o posunuté hlavě tvrdila „nálezy už platí pro dnešní kód“ i na PR bez
nálezů, takže z ní o nálezech zbylo mlčení. Zbylé dvě: `.outdated` **končí**, jak se pustí review
proti dnešní hlavě (jinak by panel zůstal v režimu „pusť review znovu“ navždycky a volby by v něm
nešly zapnout), a zúžené předání `Sestavit i tak` **nehýbe hlavou razítka** ani nepřepisuje předané
položky — skládá se proti dnešní hlavě, ale nálezy v něm nejsou, takže by jinak panel přestal hlásit,
že uložené nálezy platí pro starý commit.

Testů přidala tahle změna **44** (`HandoffTests`, `AppStoreHandoffTests`, `HandoffLedgerTests`,
`HandoffTextTests`) a je jich **3023**; jsou zelené. **Ověřeno vložením regrese, dvakrát** — vypnutí
porovnání hlav shodilo sedm testů, smazání kontroly cizí odpovědi ve vlákně právě ten jeden, který ji
má chytat. Panel má sondu v **pěti stavech** (`AgentPromptRenderProbe`), protože ke třem z nich se
klikáním v aplikaci nedostaneš.

### #361 — kolo hoří dál, ale ne z ničeho, co jde v sondě vyrobit (otevřené)

Táž signatura jako #358 (`flushObservers → beginTransaction → flushTransactions`, nula na animaci
i na timeru), ale pohonem už není náš zápis: v hover podstromu obou vzorků **není ani jeden rámec
aplikace**. Issue proto žádalo měření, ne opravu — a **oprava z toho nevyšla**, protože se stav
nepodařilo vyrobit. Zapsané je, co se vyloučilo a čím:

- **Akce `onGeometryChange` do třídy chyb z #358 nepatří.** Změřeno novou sondou
  (`Tests/Views/LayoutCallbackProbe.swift`): 80 zašpinění grafu → **80× výpočet hodnoty, 0× zápis**;
  kontrolní scénář s měnící se geometrií dá 80× zápis, takže měřidlo počítá. Sedí to na vzorek, ve
  kterém je vidět jen ten výpočet (`DiffPairBlockRowView.swift:50`), ne akce.
- **Scéna sama kolo nezavírá.** `Tests/Views/IdleDiffSpinProbe.swift` hostuje plné okno na obrazovce
  (1512×874, `ContentView`, tři záložky, nálezy, konverzace, split diff, odscrollováno o 8000 pt):
  **3,26 % CPU v prvních pěti sekundách, pak 0,00 % po 35 s**. To první je usazení po posunu — proto
  se měří po úsecích; jedno číslo za třicet sekund by tvrdilo, že okno hoří.
- **Hover callbacky sonda nedosáhne**, a to je změřené, ne odhad: aplikace na pozadí je nedostává
  (80 zašpinění grafu → `onHover` 0×, `onContinuousHover` 0×, kurzor přitom v okně ležel).
- **Pod kurzorem přitom žádný náš zápis z hoveru nebyl.** 28 bodů od horní hrany okna je
  `ContentView.header` s `ReviewTabsView` a tlačítky, a tam `onHover` **není** — jen `.help()`.
  `PullRequestTabBar.swift:203` (jediné místo, které do hoveru píše bezpodmínečně, včetně **téže**
  hodnoty) sedí **pod** hlavičkou, uvnitř detailu. Je to vada k opravě, ale #361 nevysvětluje.
  Nejsilnější zbylá nitka je re-arm `NSHostingView.requestUpdate(after:)`, ke kterému se dostane
  `signalPrefetch` a — ze zásobníku AppKitové výjimky při stavbě sondy — taky
  `ViewGraph.invalidateTransform() → graphDidChange()`; transformaci si přitom v aplikaci vyžaduje
  jedině čtení **pojmenovaného** souřadnicového prostoru v seznamu řádků. Ověřit to jde jen na živém
  okně, takže se to neopravovalo: oprava neověřené domněnky se od opravy pozná jedině tím, že se změří.

Vedle toho vyšly z sondy tři pasti, kvůli kterým měřila prázdno a tvrdila, že je čisto (velikost okna
až za `contentViewController`em, předepsaný rozměr scény, PR do `ContentView` jen frontou) a dvě věci
k mechanice sond (pumpa musí být `Timer`, ne `Task.sleep`; sonda píše do `UserDefaults` skutečné
aplikace). Všechno v [`testovani.md`](testovani.md), sekce *Co je u #361 změřené a co z toho zbývá*.

Testů je **2849** a jsou zelené. **Vidět není nic** — nezměnilo se ani jedno view, přidaly se dvě
ruční sondy (obě za `PRISM_MEASURE`, takže se v běžném běhu přeskočí) a zápis měření.

### #371 — dashboard má strop pěti řádků a karty, které vedou do své sekce

Blok na dashboardu vypisoval **všechny** řádky, takže s delší frontou přestal být dashboard přehled:
blok `Moje PR` se schoval pod hranu okna a muselo se k němu rolovat (změřeno na živé aplikaci u #331
při 32 PR — o celou obrazovku; po #332 při třinácti — o půl). Druhá půlka byla cesta zpátky: číslo
`Čeká na mě 13` říkalo, že je co dělat, ale kliknout se na něj nedalo — do plné fronty se šlo jedině
ikonou v railu.

**Strop je pět řádků a patka pod nimi shrne zbytek** — `Zobrazit všech 13 ve frontě +8 →`. Skládá to
`Policy.dashboardBlock` (`DashboardBlock`), ne view, takže se počet v patce nemůže rozejít s tím,
kolik řádků se doopravdy nakreslilo. **Strop je o kresbě, ne o množině**: karta `Čeká na mě` ukazuje
dál 13 a odznak v railu taky — kdyby sestoupil do počítání, dashboard by začal lhát a poznalo by se
to až za týden. Blok pod stropem patku nemá (ani při přesně pěti řádcích) a **patka není řádek**:
nepočítá se do `rows`, takže se nedostane do klávesové navigace ani do počtu, který blok hlásí.

**Čtyři karty z pěti vedou do své sekce.** Cíl je `RailSection` (u `Blokuje` `DashboardDestination
.blockingQueue`), takže karta nemá vědět, že rail existuje — složit z toho přepnutí je práce storu
(`show(_:)`, jedna cesta i pro paletu ⌘K). `Blokuje` u toho zapíná **třetí osu filtru**
(`PullRequestFilter.onlyBlocking`) a jde na to `setFilter`, tedy tatáž funkce jako u filtrovacího
tlačítka (#117); ostatní volby zůstávají, jak si je člověk nastavil. **`Dneska stálo` klikatelná
není** — nemá kam vést, takže nedostala ani šipku, ani ukazováček, ani hover.

**Dvojitá dělící čára nevznikla, a je to změřené renderem.** S patkou za posledním řádkem přestane
platit „poslední řádek čáru nemá“, takže by se jeho spodní linka sečetla s horní linkou patky (v mockupu
z toho bylo 1 px + 1 px = 2 px). Patka proto vlastní horní linku **nemá** a tu jednu kreslí seznam
řádků před ní; ověřuje to `DashboardFooterSeparatorTests` z bitmapy — všech jedenáct vodorovných čar
v levém sloupci má 2 px a s vloženou regresí (`overlay` navíc nad patkou) vyjde jedna 4px a test spadne.

**Rozhodnuto jinak, než bylo v zadání**, ve dvou věcech. Osa „jen blokující“ dostala **odškrtávátko
v nabídce filtru** (`Jen s blokujícím nálezem`, kreslí ho návrh v patce nabídky jako zkratku) — zadání
o něm nemluví, ale kartou se ta osa zapíná, takže bez něj by nabídka nad zapnutým filtrem ukazovala
samá neodškrtnutá repa vedle ikony, která hlásí dvanáct schovaných PR, a jediná cesta zpátky by bylo
`Vymazat filtr`. A popisek karty dostal **odsazení pro šipku** i `lineLimit(1)`: šipka je podle návrhu
absolutně umístěná, takže by se `ROZDĚLANÁ REVIEW` v užším okně zalomilo pod ni a s ním by narostla
výška celé řady karet (ověřeno renderem na 640, 760 a 900 bodech).

Testů přidala tahle změna **25** a je jich **3003**; jsou zelené. **Ověřeno vložením regrese** u čáry
nad patkou (`overlay` navíc nad ní → jedna čára 4 px místo 2 px, test spadl).

### #335 — cizí aktivita na vlastních PR: komentář kolegy se dozví okno, ne prohlížeč

Poslední kus M10. Po #330–#334 byla sekce `Moje PR` **pasivní**: bylo v ní vidět, co jsem si sám
vyžádal, ale o tom, že přibyla práce, se aplikace nedozvěděla — přitom u vlastního PR je ta
nejdůležitější událost zrovna cizí (kolega odpověděl, Copilot dopsal review). Součástky přitom byly
hotové od #173 (`VisitChanges`, `VisitLedger`, `SinceLastVisitLine`); chybělo jediné — **někdo se na
to musí zeptat dřív, než PR otevřu**.

**Cena byla to podstatné rozhodnutí a je zapsaná** (specifikace, záznam #335). Tik pollingu je jeden
search dotaz a plná konverzace vlastních PR by z něj udělala `1 + N`. Drží to tři pojistky naráz:
**`updatedAt` ze searche jako předfiltr** (tahá se jedině to, kde se doopravdy něco stalo — klidný den
je **nula dotazů**), **vlastní pětiminutový interval** nezávislý na intervalu seznamu a **strop tři PR
na jednu rozhlídku**. Nejvyšší cena je tím shora omezená: **tři dotazy za pět minut**, tedy 0,6 na
minutový tik. Rate limit se nedědí druhou cestou, ale tou stejnou — rozhlídka běží uvnitř
`afterSuccessfulTick`, takže při backoffu se netiká a tedy se ani nekouká. Zamítnuto: samotné
`updatedAt` bez konverzace (neřekne co ani kolik), podmnožina podle stavu PR (vynechání draftů by
zamlčelo komentář zrovna tam, kde na něm záleží) a CI (`fetchChecks` je druhý dotaz a jiná událost).

**Druhé razítko je podmínka, ne pohodlí.** `VisitLedger` drží poslední **návštěvu**, kdežto tady je
potřeba poslední **oznámení** — oznámením PR nenavštívím, takže by „2 nové komentáře“ chodily každou
rozhlídku, dokud PR neotevřu. Přibyl proto `ActivityNoticeLedger` (v předvolbách vedle návštěv, jedno
datum na PR) a novinka je to, co je novější než **obojí**. Do razítka jde **datum té nejnovější
ohlášené položky**, ne „teď“: s časem doručení by propadl komentář, který přišel mezi dotazem a zápisem.
Dotažení konverzace na pozadí přitom **návštěva není** — značka „od minule“ se zakládá, návštěva se
nezapisuje; jinak by se posunula na teď a řádek by o komentáři kolegy mlčel.

**Cizí aktivita je další druh novosti, takže bydlí v `Policy.handoff`** (`HandoffReport.activity`), ne
vedle ní. Vlastní odpověď pro řádek seznamu by se rozešla s odznakem v railu i s panelem — a přesně
proti tomu #334 vzniklo. Commity v aktivitě **nejsou**: na vlastním PR je push obvykle můj a datum
commitu není datum pushnutí, takže by banner chodil o vlastní práci (pruh „od minule“ v detailu je
ukazuje dál).

**Vidět je to na dvou místech.** V řádku seznamu i v bloku dashboardu `2 nové komentáře od minule`
v `accent-2` — **místo autora a času**, jak to kreslí sekce 21; je to pořadí důležitosti, ne úspora
místa (autorem vlastního PR jsem já nebo můj agent) a obojí zůstává v hlavičce detailu. A pátá
notifikace s vlastním přepínačem `Ozval se někdo na mém PR` a **vlastní `replacementGroup`**: že mi
kolega odpověděl, nemá přebít výsledek review na tomtéž PR. Mockup je dokreslený (sekce 12 má pátý
banner a poznámku 31b).

Testů přidala tahle změna **44** a je jich **3096**; jsou zelené. **Ověřeno vložením regrese**:
značka jen z návštěvy (tedy zahozené druhé razítko) shodí právě ten test, který to má chytat —
`O témže komentáři se nehlásí dvakrát`, `(center.delivered.count → 2) == 1`. Jeden test #331 se
**obrátil**: odznak v railu teď vlákno počítá i bez kliknutí do PR, protože konverzaci dotáhne
rozhlídka — spodní hranice se posunula, nezmizela.

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**

**#375 je hygiena a pokrytí, ne oprava ztuhnutí** — a stojí za to vědět, proč se tak vydává. Sonda
nečinného okna k #361 pokrývala jen `Změněné soubory`, kdežto ztuhnutí z 2026-08-18 přišlo při
projíždění **konverzace**; sweep u toho našel v `ConversationNodeView` poslední výskyt pružné výšky
v řádku líného seznamu, tedy vzoru, který `CLAUDE.md` od #220 zakazuje. Podezření, že je to příčina,
se **neprokázalo**: nečinná konverzace stojí 0,00–0,01 % na všech záložkách a projíždění 1,30 s
s tím vzorem proti 1,28 s bez něj — a kontrola měřidla (šest pružných úrovní navíc → **1,08 s**,
tedy levněji) ukázala, že měřidlo tuhle třídu v tom scénáři nevidí. Vzor se proto vyřídil jako
latentní past, ne jako příčina, linka se překreslila jako **pozadí uzlu** a vzhled je prokazatelně
týž (byte-identické renders sedmi tabů). **#361 zůstává otevřené**, protože dnešní vzorky mají hover
na nule a jediný re-arm v `signalPrefetch` — je to jiná varianta než ta, kterou #361 popisuje.

Vypadly z toho dvě věci k sondám: `-only-testing` na jeden test ze `swift-testing` potřebuje
**závorky** (bez nich `Test run with 0 tests`, a to zeleně), a `DetailTabRenderProbe` od #294
rendrovala záložku `Konverzace` jako `Načítám konverzaci…`, takže každé srovnání vzhledu osy
porovnávalo dva spinnery. Obojí je opravené a zapsané v [`testovani.md`](testovani.md).

**Kolo z #361 se nepovedlo zreprodukovat ani projížděním kolečkem, takže #361 zůstává otevřené.**
Sonda umí od téhle dávky skládat **skutečné `scrollWheel` události** s fázemi a setrvačností
([`WheelGesture`](../Tests/Support/WheelGesture.swift)) — což `scroll(to:)` neumí, protože pro
`NSScrollView` je programový posun jen změna počátku a živé scrollování z něj nezačne. K tomu se
srovnaly dvě věci, které mohly sondu držet slepou: okno se staví **jako `WindowGroup`** (minimum
z obsahu, takže běží `minSize` → `_sizeThatFits`, tedy druhá aktualizace grafu na jiné nabídce
rozměru) a osa má **300 komentářů pěti různých výšek**. Po gestu se okno usadí na **0,00 %** ve všech
scénářích. A nula je od téhle dávky ověřená z druhé strany: kontrolní scéna se zpětnou vazbou
z rozvržení do stavu dá **32 %** v prvním úseku a nulu, jak jí dojde rozpočet kol — měřidlo tedy kolo
**vidí**. Rozpočet je tam po zkušenosti, kterou stojí za to nezapomenout: bez něj se okno sondy
nedalo zavřít a musela ho zabít ruka u stroje.

Padla tím i hypotéza, se kterou se do toho šlo — že kolo zavírá `ForEach(Array(nodes.enumerated()),
id: \.element.id)` v ose. Vzor tam byl po celou dobu těch měření a osa se usadila. **Vyřídil se jako
zlevnění cesty, ne jako oprava**: identita se čte z uloženého pole (`ConversationRow`, `Policy`), což
je 0,141 → 0,036 ms na přerovnání 300 řádků, a značka poslední návštěvy se přestěhovala z view do
`Policy`, kde na ni **poprvé** je test (osm případů, ověřené vloženou regresí). Vzhled je prokazatelně
týž — 23 byte-identických renderů. Zbylých devět výskytů toho vzoru v `App/` zůstává vědomě:
`id: \.offset` payload nekopíruje a u řádků textu nebo sha je pořadí jediná správná identita.

### #377 — zadání pro agenta se vybírá po položkách, ne po druzích

Sedm zaškrtávátek po druzích (#333) na skutečném zadání nestačilo, a bylo to změřené na promptu pro
`keboola/platform-libraries#561`: vypnutím druhu `souhrny review` odešel i verdikt bota se třemi
concerny, ponecháním se agent v textu nevyznal (Copilotův přehled diffu, linkback na Linear a moje
4,1 kB release notes). Od #377 má zaškrtávátko **každá položka**, bydlí to v **sheetu** (panel má
240–520 bodů, sheet 840–1080) a v panelu zůstávají volby po druzích jako hrubý filtr s počtem
**vybraných z celku** (`1 z 3`).

**Předvybírá aplikace a u každé položky je napsaný důvod**: `napsal jsi to ty` (`Conversation.isMine`),
`bez obsahu` (po odstranění nadpisů nezůstane nic — syntaktický test, ne heuristika) a `shrnuje diff`.
Vedle nich zůstávají `odmítl jsi ho` a `vyřešeno` z #333. **`shrnuje diff` je jediná heuristika**, leží
ve vlastním souboru (`AgentPromptDiffSummary.swift`) a pozná se na **nadpisu** `Pull request overview`.
Tabulka změněných souborů se jako druhá podmínka **zamítla**: starší formát Copilotova přehledu ji nemá
(změřeno na `cli/cli#11451`), takže by heuristika nedělala nic právě v tom případě, na který je.

Dvě věci se rozhodly jinak, než bylo v zadání:

- **Schválení s prázdným tělem se přestalo předvybírat do textu** (změna proti #333). Pro agenta je to
  nulová informace; ze seznamu nemizí a jedním kliknutím se vrátí. U #333 „vynechat“ znamenalo ztratit
  celý druh, teď jednu položku — proto se to obrátilo.
- **Co aplikace předvybere jako vypnuté, není materiál k předání** (`Policy.handoff`). Zadání #377
  říká, že po předání části položek má `pending` zůstat vyšší, a to platí pro **ruční** odškrtnutí.
  Kdyby to platilo i pro předvybrání, odznak `Moje PR` by nad mým PR nezhasl **nikdy**: release notes
  v komentáři pod PR tam píšu na každém, takže by mezi nepředanými navždycky zůstala položka, kterou
  zadání ani nenabízí — tedy zrovna ten „odznak, který se přestane čítat“, kvůli kterému #334 vzniklo.

Výběr ani rozbalení **nepřežijí zavření sheetu** (`@State` sheetu): sheet se otevírá k jednomu předání,
předvybrání se počítá z dat a uložený výběr by byl další stav u PR vedle razítka v `handoffs.json`,
který zastará pushem a nikdo o něm neví.

Testů přidala tahle změna **32** a je jich **3130**; jsou zelené. **Ověřeno vložením regrese,
čtyřikrát** — ignorovaný výběr, vyhozené vypnuté položky ze seznamu, heuristika vracející `true` na
cokoli a vyhozený filtr předvybraných z `Policy.handoff`; každá shodila právě ty testy, které to mají
chytat. Seznam se od sheetu rendruje **zvlášť** (co je rozbalené, drží `@State`, takže se offscreen
v sheetu rozbalit nedá) a v obou mezích šířky.

### #381 — týž nález nahlášený dvakrát je v bublině jednou

Reviewer zavolal `ReportFindings` **dvakrát**, protože si první text opravil (do češtiny mu prosákla
ruština: `второй`, `условие`), a v bublině pak ležel týž nález dvakrát — oba `blokuje`, `correctness`,
`CONFIRMED`, na `PhaseTransitionHandler.php:346` —, i když jeho vlastní log hlásil `1 finding`.
Deduplikace z #17 stála na `(file, line, summary)`, a korekce `summary` mění: stačilo `fáze` → `fázi`.

**Slévá se po sadách a rozhoduje místo, ne text.** Každé volání `ReportFindings` je celá sada
a pozdější sada na daném `(file, line)` přepíše tolik nálezů, kolik sama nese; drží to jedna čistá
funkce `Policy.mergedFindings(_:reporting:)` a parser jen složí sadu a předá ji. Uvnitř sady se
**neslévá nic** (co reviewer vypsal vedle sebe, jsou dva problémy — `review-with-findings` má dva
nálezy na `Cart.swift:17`) a nález, o kterém pozdější sada mlčí, **zůstane**, včetně přebytku na
tomtéž místě. Prázdná ani nečitelná sada proto nálezy nesmaže.

Dvě věci se rozhodly jinak, než doporučovalo zadání:

- **„Poslední volání vyhrává celé“ se zamítlo.** Změřeno na fixtures z reálných session:
  `ReportFindings` je ve **všech pěti** volané nejvýš jednou, takže premisu „závěrečné volání nese
  úplný seznam“ **z dat v repu ověřit nejde** — a když neplatí, ztratí se nález, což je v okně
  k nerozeznání od „reviewer nic nenašel“.
- **Slití podle `(file, line, category)` uvnitř sady se zamítlo** ze stejného důvodu, kvůli kterému
  `summary` do identity dal #17: dvě různé věci na jednom řádku by splynuly potichu.

**Uložené záznamy se nečistí ani při čtení.** V záznamu už struktura volání není, takže úklid by
hádal podle místa a slil by i legitimní dvojici na jednom řádku; k tomu jsou odmítnutí klíčovaná
`(reviewer, file, line, summary)`, takže vybrat jednu ze dvou verzí textu osiří označení té druhé.
Duplikát v jednom záznamu jednoho PR proto zůstává, dá se odmítnout (#113) a nové review ho odklidí.

Klíč odmítnutí zůstává na `summary` schválně — páruje **napříč běhy**, kde z pořadí volání nic vidět
není, a špatně spárované odmítnutí schová nález, kdežto špatné slití jen ukáže duplikát.

Testů přidala tahle změna **17** — šestnáct tvrzení a jedna sonda, která se pouští ručně — a je jich
**3160**; jsou zelené. **Ověřeno vložením regrese, třikrát**
(identita z #17 → 5 testů a v nálezu zůstane `условиевторой`; slití podle kategorie → 2 testy; poslední
sada vyhrává celá → 7 testů, s prázdnou sadou 9). Na obrazovce je to vidět, ale ten stav se v aplikaci ve
slotu vyrobit nedá — záznam s duplikátem leží v cache hlavní instance —, takže je na to offscreen
sonda `FindingDuplicateProbe`, která kreslí bublinu před opravou a po ní na jedno plátno.

### #384 — hover patky bloku sahal v návrhu po tokenu, který neexistuje

**V kódu se nemění nic než jeden komentář** — je to `docs/navrh.html`, dokumentace a publikování.
Zákres stropu dashboardu (#371, `v1.1.136`) měl u patky `background: var(--hover)`, ale token toho
jména paleta nemá, takže hover v návrhu **nekreslil nic**. Nedefinovaná custom property totiž není
chyba: deklarace se stane neplatnou při výpočtu hodnoty a vlastnost spadne na `unset`. V souboru to
proto vypadá hotově a na obrazovce po tom není stopa — všiml si toho až subagent u #371, při
implementaci, a hodnotu si v okně vybral sám.

**Srovnáno na `--panel-3`**, což je v `:root` protějšek `Palette.raised`, tedy přesně to, co okno
kreslí; nový token by byl token bez protějšku v paletě, a podle takového se nedá nic naprogramovat.
Odstín zůstává o stupeň tišší nad `--panel-2` bloku — tentýž pár, kterým se zvýrazňuje jinde.

**Byl to jediný nedefinovaný token v celém souboru** — před opravou 29 použitých proti 28
definovaným, po ní 28 proti 28 a žádný definovaný token není bez použití. Ověřeno **grepem, který
teď kontroluje třídu, ne ten
jeden výskyt** (v [`navrh.md`](navrh.md), *Jak se z něj čte*), a chytání regrese je z běhu nad
`HEAD` před opravou, ne z odhadu. Zkontrolovaly se u toho i **přebíjecí bloky** motivů: kdyby
token v jednom z nich chyběl, obarvil by se v tom tématu potichu ze světlého `:root` — neliší se
v nich nic než čtyři tokeny bez motivu (`--ui`, `--mono`, `--radius`, `--radius-sm`).

Jméno tokenu je v komentáři v návrhu **schválně bez `var(…)`**, aby ta kontrola zůstala prázdná;
kontrola, která hlásí sama sebe, je mrtvá kontrola.

**Ověřeno renderem, ne čtením CSS.** Headless snímek nemá myš, takže se ve výřezu přepsal
`:hover` na třídu (deklarace zůstala ta z návrhu) a barva se odečetla přes `getComputedStyle`:
`rgba(0, 0, 0, 0)` před opravou proti `rgb(28, 33, 44)` = `#1C212C` po ní v tmavém motivu
a `rgb(238, 241, 247)` = `#EEF1F7` ve světlém. Na snímcích je patka po opravě odlišená od těla
bloku, před ní splývá. Postup je zapsaný v [`navrh.md`](navrh.md).

**Publikovaná kopie dohnala repo o tři verze** (`v1.1.136` strop dashboardu, `v1.1.140` výběr
položek, plus tahle oprava) — na **tutéž adresu**, protože dva návrhy jsou horší než žádný.
Pravidlo „jedna úprava, jeden commit, jedno publikování“ se tím neruší, jen se splácí dluh po
dvou dávkách, kde se to nestalo.

### #361 — třetí kolo: `explicitAlignment` a `DiffView` vyloučené, přibyla diagnostika do živého okna (otevřené)

**Kolo z #361 se nepodařilo vyrobit ani potřetí, takže issue zůstává otevřené.** Zbyly z toho dvě
uzavřené otázky a jeden nástroj.

**`DiffView` pod záložkou `Konverzace` v hierarchii nezůstává** — a tím padá nejsilnější zbylá
hypotéza (že by v ose běžely dál `onGeometryChange` nad pojmenovaným prostorem `DiffView.contentSpace`
a `DragGesture` v něm). Změřeno ze dvou stran nad PR, které **má načtený diff**: 9 bloků kódu v okně
s vybraným diffem proti **0** s vybranou konverzací, a v úseku projíždění osy **0 průchodů tělem**
`DiffView` i `DiffRowView`. Sedí to na vzorky ztuhlé aplikace, ve kterých se `DiffView` ani
`contentSpace` neobjeví **ani jednou**.

**Ablace na `explicitAlignment` číslo nesundala.** Baseline zarovnání v odrážkách markdownu vyšlo
1,37 s proti 1,44 s (v šumu) a `.background(alignment: .topLeading)` v uzlu osy — tedy právě ten
`SecondaryLayerGeometryQuery`, který v profilu drží 449 z 3 585 vzorků — 1,42 s. Markdown celý ubere
18 %, ale odebere se tím veškerý obsah uzlu, takže to není srovnání téhož. **Žádná varianta po gestu
nehoří** (0,00 %), takže je `explicitAlignment` cena uvnitř cizího kola, ne to kolo. `SinceLastVisitView`
se neměřilo, protože **v ose vůbec není** (sedí v `Přehledu`). Čísla, včetně toho, že šedesát kroků
po čtyřiceti bodech je na ablaci málo, jsou v [`testovani.md`](testovani.md).

**Nástroj: diagnostika kreslení za `PRISM_DIAGNOSE=1`** (`./bin/run.sh --diagnose`). Dokud se kolo
nedá vyrobit v testu, je jediným zdrojem pravdy skutečné okno — a `sample` z něj řekne, **kde** hlavní
vlákno je, ne **kolikrát** se co přeložilo. Aplikace proto umí zapsat řádek za sekundu do
`<cache>/diagnostics.log`: počet kol runloopu, CPU hlavního vlákna a průchody `body` po typech views.
Vypnutá stojí načtení jednoho statického `Optional`u, počitadlo **není v observable stavu** (#252)
a nic si **neplánuje kolo** (#350) — řádky vypisuje observer runloopu, takže si diagnostika nevyžádá
ani jedno probuzení navíc. Přepínač v nastavení se **zamítl**: byla by to změna vzhledu se schvalovací
bránou, a hlavně by se dal zapomenout — proměnná prostředí umře s procesem, takže se diagnostika
vypne dalším `./bin/run.sh` sama. Ověřeno na běžící `PRism-a`; podrobnosti a co si měřidlo nesmí
dovolit jsou v [`architektura.md`](architektura.md), sekce *Diagnostika kreslení*.
