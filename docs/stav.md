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
   poslední návštěvy #173, procházení nálezů šipkami #187, nálezy jako karty #175, hlavička PR s větvemi #174. **Vlna A je hotová**; **vlna B je hotová** (#178, #177, #179). Z vlny C rail a záložky #180, dashboard #181, tab konverzace #183, dlaždice faktů #211, iniciály na kartě popisu #212, kontroly v `Přehledu` #213, sazba položek konverzace #216, sazba lišty diffu s hlavičkou souboru #219 a sazba bloku „od minule“ #226. Mimo plán přibylo
   **#220 — okno vytuhlo na PR s ~2000 změněnými řádky**: pružná šířka na každé úrovni zanoření
   stojí ~5,5× na úroveň, takže se šířka teď měří jednou a předává dolů. Odpadlo z toho #223
   (blok bez stropu) a #224 (barvení bez cache) do milníku Průběžné — obojí se měřením vyloučilo
   jako příčina.

   U #219 se **zrušil popover `Přejít na soubor`** — změna proti #197, kde se rozhodlo, že
   zůstane. Důvod je v specifikaci; s ním odešla plná sazba stromu (`FileTreeView.isCompact`)
   a sečtené počty po složkách (`FileTreeNode.additions`/`.deletions`), protože byl jejich
   jediný čtenář.

   U #216 se **rozšířila tvrdá podmínka č. 1**: `ReviewPublishing` má čtvrtou metodu
   (`comment`), protože composer komentáře pod PR je v návrhu a bez něj se pod PR nedá napsat
   z okna vůbec. Podrobnosti a důvod jsou v `CLAUDE.md` a ve specifikaci.

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

**Postup pro dávku issues zapsaný (#231)** — [`docs/paralelni-vyvoj.md`](paralelni-vyvoj.md).
Sloty daly paralelnímu vývoji prostředí, ale ne postup; bez zápisu by se seznam issues dál
vyřizoval sériově, protože výchozí chování je subagenty nepouštět. Je v něm, podle čeho se
pozná nezávislost (`ReviewPublishing` jde vždycky sám, `AppStore` stav a `Policy` jsou
rizikové, `docs/stav.md` konfliktuje vždy a nevadí), co subagent dělá a co ne (nemerguje,
nezavírá issue, nevydává release) a **že slot přiděluje orchestrátor** — subagent v izolovaném
worktree `.prism-slot` nemá, takže by přepsal aplikaci, se kterou se pracuje.

**Mění to jedno pravidlo:** v dávce se pauza na proklikání posouvá z „před prvním pushem“ na
„před merge“ a sbírá se za celou dávku naráz. Subagent nemá jak zavolat člověka a čekáním by
blokoval sebe i slot; PR před mergem je přitom pořád levný na přepsání, takže smysl pauzy to
drží. Podívat se na obrazovku sám a napřed platí dál.

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

**Notifikace o review nese počty v titulku (#200)** — `3 nálezy · 1 blokuje`, pod tím
nejzávažnější nález (`correctness: …`) a na třetím řádku `owner/repo#123`. Do té doby byla
v titulku identifikace PR a v těle věta o výsledku, tedy rozvržení, které na otázku „mám k tomu
jít hned?“ odpovídalo až druhým řádkem. Návrh (sekce 10) to má takhle od začátku; issue z toho
nevzniklo a našlo se to při kontrole návrhu proti implementaci.

Dvě věci vyšly z **měření na běžící aplikaci**, ne z odhadu. Do banneru se vejde titulek
a **čtyři řádky těla** — zadání počítalo se dvěma. A co se nevejde, macOS uřízne i s tím, co je
pod tím: 140znakový souhrn z banneru vymazal celý řádek s PR, takže se nález krátí na sto znaků
sám. `Čisté review` a `Review se nepovedlo` zůstávají dvě různé věty, teď jako dva různé titulky.

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
