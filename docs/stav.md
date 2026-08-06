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

Vedle fází stojí milník **Průběžné**: koš na to, co do žádné z nich nepatří (ikona,
podpis, stavový řádek). Nemá pořadí ani termín a verze se z něj neodvozuje — viz
Pracovní postup.

Každá fáze je samostatně spustitelná a otestovatelná. **Tenhle seznam aktualizuj, jak
fáze ubývají.**
