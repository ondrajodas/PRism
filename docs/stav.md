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
a `DiffRow.paired(_:)` v `App/Diff/DiffPairing.swift`, přepínač v liště nad
diffem, `global.diffLayout` v konfiguraci a `diffLayoutOverride` v `AppStore`. (Kreslil to
`DiffPairView`; od #157 to dělá blok a od #446 je ten view smazaný — viz níž.) **Starý a nový
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
**`ReviewerTimeline.newestEntry(in:)` po zrušeném přepínači (#242) v aplikaci nemá volajícího**
(#325 ho nakonec smazalo, viz níž) —
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

### #345 — text Linear issue a komentáře pod PR do zadání (druhá část #120)

Druhá polovina #120. Odkazy se teď hledají **i v komentářích pod PR** — linkback z trackeru chodí
zrovna komentářem a konverzace se do #345 v cestě review nenačítala vůbec — a jejich text se
**dotáhne krátkou `claude -p` session**. Cena je rozhodnutá uživatelem (2026-08-17): **tahá se
vždycky, i v automatu**, protože zadání vedle diffu je důvod, proč ta funkce existuje. Změřeno
$0,18 (sonnet) až $0,31 (opus-5) a ~20 s na review.

**Jádro issue je rozlišit „issue nic neříká“ od „nestáhlo se“**, a je to jádro proto, že průzkum
naměřil **tři tvary selhání a dva z nich vypadají jako úspěch**: chybějící (nebo nepřihlášený)
server skončí `exit 0` a `result` se `subtype: "success"`, jen s prózou modelu v odpovědi; server,
který se nespustí, skončí jedničkou a `error_max_turns` — a v tom eventu **klíč `result` vůbec
není**; nepovolený nástroj skončí zase úspěchem a je vidět jedině v `permission_denials`. Jediný
strojově čitelný signál je `init.mcp_servers[].status`, a ten se dá přečíst **jedině ze streamu** —
proto ta session jede `--output-format stream-json --verbose`, na rozdíl od bufferovaného překladu
nálezů. **Rozhodovat podle prózy modelu je hádání**; kdo čte exit kód, uloží si do zadání větu
„nemám povolení k použití nástroje…“, jako by to bylo zadání.

**Vzor `TranslationCommand` se nedal opsat** a je to změřené: na stroji je v session **165
nástrojů**, takže CLI odkládá schémata a model musí napřed zavolat `ToolSearch`. Povolení proto
vyjmenovává **oba** nástroje (`ToolSearch` a ten čtecí MCP) a `--max-turns` nesmí být 1–2 —
dotažení je ≥ 3 turny. `--allowedTools ""` by nefungovalo vůbec.

**Sada nástrojů revieweera se nemění** (tvrdá podmínka č. 2). Text tahá **zvlášť běžící** session
a `--disallowedTools` je u ní **tatáž konstanta** `ClaudeCommand.disallowedTools`, takže druhá sada
zákazů nevzniká; test hledá v povoleních `Write`, `Edit`, `Bash`, `ReportFindings` i `Skill`
a tvrdí, že tam nejsou.

**Jméno nástroje je v konfiguraci, ne v konstantě** (`issueTextTool`, jen v `config.json` jako
`ownLogins`). `mcp__claude_ai_Linear__get_issue` je jméno serveru **u tohohle uživatele**, ne
kontrakt. **Chybějící hodnota znamená „netahat“**, ne prázdný pokus — session bez nástroje, který by
zavolala, stojí boot a nevrátí nic —, a je to **vlastní stav**, který je na ose vidět: reviewer
dostal jen odkazy.

**Odpověď se čte podle řádkových značek, ne jako JSON**, a je to změna proti překladu nálezů:
hodnota je cizí markdown libovolné délky (4 439 znaků u jednoho issue z průzkumu, s uvozovkami
i zpětnými apostrofy) a překódovat ho na JSONový řetězec je krok, ve kterém model utne nebo zkazí
escapování — selhání by pak zahodilo **všechny** texty naráz. Značku (`IntentTextCommand.marked(_:)`)
skládá jedna funkce pro obě strany, takže se příklad v promptu a rozbor odpovědi nemají čím rozejít.
Text se páruje **podle `id`**, ne podle pořadí: vynechané issue by u pozičního párování přiřadilo
texty cizím issues.

**Na ose je to vidět jako odznak** `zadání není celé` v hlavičce dráhy, s důvodem v nápovědě — vzor
`loadedADifferentSkill` z #78: příznak se počítá v `ReviewerTimeline` z osy (takže **přežije
restart**), přenáší polem `ReviewerLane` (u syntetických drah `nil`) a kreslí `ReviewerLaneView`;
česká próza je v `ReviewerLaneText`, šest různých vět. Dvě věci, které z toho plynou: příznak jde do
osy **jako první událost každé dráhy**, ne po konci běhu (odpověď je hotová dřív, než se cokoli
spustí, a pozdní událost může dorazit do osy, kterou už nikdo nečte — souvisí s #308), a **osu
neposouvá**, takže dráha ve frontě netvrdí, že už něco dělá.

**V souboru se zadáním má každé issue vlastní podsekci** a u té, která se nedotáhla, stojí věta
s důvodem. Částečné dotažení (dvě issues, jeden text) proto **není selhání celku**: na osu nejde
nic a chybějící issue se pojmenuje u sebe — s větou **bez příčiny**, protože žádná zaznamenaná není
a hádat mezi „nezkoušelo se“ a „nepovedlo se“ je zrovna ta záměna, kterou tohle issue odstraňuje.
Selhaný dotaz na komentáře je zapsaný **u seznamu odkazů**: „no issue links found“ nad selhaným
dotazem by tvrdilo, že PR na žádném zadání nestojí.

**Ověřeno spuštěním**, ne jen z fixtures: jeden běh s argumenty, které skládá `IntentTextCommand`
(`claude` 2.1.236), doběhl `success` ve **3 turnech** za 21,4 s za $0,3099, značka přišla na vlastním
prvním řádku a rozbor nad tím streamem vydal text bez gapu. Tři tvary selhání jsou ve fixtures jako
**skutečné streamy** (`intent-server-missing`, `intent-server-failed`, `intent-tool-denied`);
**úspěšné dotažení fixture nemá schválně** — odpověď nese celý text firemního issue a ten do
fixtures nepatří, takže inline v testu zbývá jen náš vlastní formát.

**Copilot našel dvě věci a obě jsou ten vzor „text v UI tvrdí víc, než data unesou“.** První:
nepovedený zápis souboru posílal na osu příznak, který jinak platil — a věty u něj mluví o tom, co
v zadání **chybí** („reviewer dostal jen odkazy“), takže nad během, který soubor nedostal vůbec, by
lhaly; teď na osu nejde nic a zápis hlásí stavový řádek, jak to zavedlo #120. Druhá: nápověda
u nepřipojeného serveru vypisovala **stav** a vedle toho tvrdila, že se nepřihlášený server od
chybějícího nedá odlišit — což si u vypsaného stavu protiřečí, protože ten stav je zrovna to, čím se
liší. Ta úvaha („následek je pro uživatele stejný“) patří k modelu, ne do nápovědy.

Testů je **3227** a jsou zelené. Regrese ověřena vložením dvakrát: vypnutá kontrola serveru položí
**4 testy** nad skutečnými streamy, kdežto `?? ""` místo `guard let` u chybějícího klíče `result`
**nepoloží nic** — prázdný text nevydá ani jednu značku, takže skončí stejným `.noAnswer`. To je
zapsané i v kódu, ať se ten `guard` nepovažuje za mechanismus, na kterém dnes něco stojí.

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
Strop 8 MB platí na **soubor**, ne na sezení, a když se do něj nedá zapsat, diagnostika se
**nezapne a řekne to** (obojí nález Copilota na #386; ověřeno vloženou regresí).
Vypnutá stojí načtení jednoho statického `Optional`u, počitadlo **není v observable stavu** (#252)
a nic si **neplánuje kolo** (#350) — řádky vypisuje observer runloopu, takže si diagnostika nevyžádá
ani jedno probuzení navíc. Přepínač v nastavení se **zamítl**: byla by to změna vzhledu se schvalovací
bránou, a hlavně by se dal zapomenout — proměnná prostředí umře s procesem, takže se diagnostika
vypne dalším `./bin/run.sh` sama. Ověřeno na běžící `PRism-a`; podrobnosti a co si měřidlo nesmí
dovolit jsou v [`architektura.md`](architektura.md), sekce *Diagnostika kreslení*.

### #361 — čtvrté kolo: diagnostika se v záchvatu vypínala, teď píše z vlastního vlákna (otevřené)

**Kolo z #361 se nepodařilo vyrobit ani počtvrté**, ale poprvé je z živého záchvatu **záznam
o průběhu**, ne jen o tom, co bylo před ním.

**Nástroj měl vadu, kvůli které v záchvatu mlčel.** Do #391 řádky vypisoval observer hlavního
runloopu na `beforeWaiting` — a v tom kole se runloop do stavu čekání **vůbec nedostane**, protože
SwiftUI si flushuje transakce z takového observeru a z toho se nevrátí. Ve čtvrtém záchvatu je
poslední řádek `11:01:31`, ztuhnutí trvalo do `11:02:53` a mezi tím **nic**. Řádky proto zapisuje
vlastní vlákno (`Thread` + `Thread.sleep`), observer zůstal **jen jako počitadlo kol** a CPU hlavního
vlákna se čte přes jeho mach port (`threadCPUSeconds(of:)`), protože `CLOCK_THREAD_CPUTIME_ID` umí
jen vlákno samo o sobě. Zaseknutý úsek je z řádku vidět slovy: `0 kol runloopu`, celá sekunda CPU
a `— HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU`. Ověřeno **vyrobeným kolem** (blokující observer, 1 s): šest řádků z doby záchvatu,
všechny o zaseknutí — a **vloženou regresí** z druhé strany: se zápisem z observeru nezůstane ze
záchvatu nic. Nad skutečnou scénou (`FeedbackLoopList`, 31,72 % CPU) zapsala i půlsekundové úseky,
ve kterých hlavní vlákno runloop nepustilo ke slovu.

**Ze třicetisekundových vzorků vyšly tři odpovědi, žádná z nich ale není pohon.**
`SecondaryLayerGeometryQuery` (16,5 % hoření) je `.background(alignment: .topLeading)` v uzlu osy —
poznat je to z řetězce ve vzorku, který končí v `_HStackLayout`, takže aby SwiftUI našel vodicí čáru,
**umístí všechny děti řádku znovu**, a to na každý dotaz. Zůstává to tam: ablace u #386 tu cenu na
projíždění **neviděla** (1,42 proti 1,44 s) a odebrat to znamená odebrat linku osy.
`FillingWidth` v ose **nevyjednává** (ve vzorku je `_FrameLayout`, ne `_FlexFrameLayout`, takže
`availableWidth` z #220 dosáhne až do uzlu) a `ConversationRow` se kopíruje jen při čtení identity
v `ForEach`i (0,46 %).

**Nově vyloučené:** přesázení osy pod odscrollovaným seznamem (zkrácení u dna i v prostředku,
prodloužení, týž počet s jinými výškami — všechno se usadí do 0,01 %, a `NSScrollView` si navíc
počátek sám usekne) a **tažení za hranu okna** nad osou, tedy ta nitka z #363 přes `minSize` →
`_sizeThatFits` → `invalidateTransform` (1,82 s CPU za tažení, po něm 0,00 %). Čísla a mechanika
jsou v [`testovani.md`](testovani.md), sekce *Čtvrtý záchvat*.

**Co zbývá:** proč `signalPrefetch` nekonverguje. Nově se ví, že se to celé odehrává uvnitř jednoho
`flushTransactions` a že se v tom kole **nepřeloží ani jedno tělo** aplikace — je to přepočítávání
geometrie nad nezměněnou sadou podviews.

### #393 — `updateNSView` sázel blok diffu při každém průchodu kola

**Pátý záchvat ukázal poprvé náš kód** — a proto je z něj oprava, ne další negativní výsledek.
Kořen je pořád ten z #361 (transakční kolo, 19 116 z 21 240 vzorků), ale práce uvnitř je naše:
`updateNSView` u bloku dvojic drží **1 172 vzorků (5,5 %)** ve dvou nezávislých vzorcích, a to bez
jediného průchodu tělem.

**Co ten atribut špinilo, nebyla naše hodnota.** SwiftUI si `PlatformViewChild` přepočítá při každé
změně geometrie bloku, takže `updateNSView` chodí i tehdy, když se blok, jazyk ani režim nezměnily —
a všechno pod ním se platilo znovu: hash všech řádků a podpis do řetězce (275 vzorků), dvě pole
`DiffLine` a dvě množiny navíc, `left.singleLineHeight` jako dotaz layout manageru, `layoutColumns()`
se `sizeToFit()` na oba sloupce (279) a rámečky řádků i s jejich porovnáním (158).

**Rozhoduje o tom jeden klíč, ne hash.** `DiffBlockDrawing` (blok + `DiffBlockStyle` + šířka) leží
v `Coordinator`u a porovnává se celý blok: hodnota representable je v grafu, takže se porovnávají
**tatáž** pole a `Array.==` se vrátí na identitě úložiště. Změřeno na 27 blocích po 60 řádcích: klíč
**0,013 ms**, hash s podpisem **0,530 ms**, porovnání po řádcích u čerstvých polí **0,284 ms** —
stráž tedy nemá jak stát víc, než co ušetří. `DiffBlockSignature` z #157 tím zmizel: obsah se
porovnává na řádcích a v klíči sazby zbyly jazyk a barevný režim (`DiffBlockStyle`), ze kterého se
bere i paleta — jako parametr vedle režimu by to byly dvě hodnoty o jedné věci.

**Šířka je v jednom klíči a ve druhém ne, a je to celé rozhodnutí.** Rámečky řádků se z ní počítají
a ve split pohledu z nich vychází hranice pravé poloviny, takže bez šířky by po zúžení okna svítila
pilulka jinde, než kde se táhne rozsah. Do klíče **sazby** naopak nepatří: text se jen jinak zalomí,
kdežto přesázení ruší rozdělaný výběr (#157). U toho se změřilo, že **`bounds` v `updateNSView` je
o průchod pozadu** — první průchod vidí šířku nula a ten druhý tu skutečnou; platilo to i předtím,
jen to nebylo z čeho poznat.

**Kolo se tím nezastaví, a nevydává se to za opravu ztuhnutí.** Naše práce byla 5,5 % vzorků toho
kola; zbytek je přepočet geometrie líného seznamu uvnitř jednoho `flushTransactions`. Na projíždění
se oprava neprojeví vůbec (0,55 / 0,52 s se stráží proti 0,50 / 0,55 s bez ní, série A/B/A/B) — blok,
který vjede do okna, dostane jednu aktualizaci a nasadí se jednou, takže tam **není co ušetřit**.
Šetří se právě v tom kole, kde se geometrie počítá nad týmž blokem pořád dokola: nad usazenou scénou
15 aktualizací → **3 nasazení** místo 15.

**Ke čtení vzorku z toho plyne jedna oprava zadání:** v pátém záchvatu je `enqueueHoverUpdateIfNeeded`
**2 065 z 2 119** vzorků `dispatchActions` (ve druhém vzorku 1 440 z 1 486), takže je to ta **první**
varianta z #361 (hover re-arm), ne ta se `signalPrefetch`em. V zadání stálo, že je hover zanedbatelný —
to číslo ale bylo počet **řádků grepu**, ne vzorků. Náš kód v tom podstromu není (10 vzorků z 2 065),
takže je to pořád následek, ne příčina.

**Ostatní representable v okně se prověřila a stráž nedostala** — měřením, ne čtením:
`SelectableCodeView` sází text taky bezpodmínečně, ale nad tímtéž špiněním grafu dostane **jednu**
aktualizaci proti jedenácti u bloku dvojic (nemá `sizeThatFits`, takže nevisí na rozvržení).
Stráž, kterou nemá co vyvolat, by nešla ověřit vloženou regresí; `LogTailTextView` tentýž klíč má
od #292.

**Z pauzy vyšla ještě jedna oprava, a ta na obrazovce vidět je** (proto se render proti `main`u
liší schválně): v tmavém režimu byly **identifikátory černé na tmavém pozadí**, protože obyčejný text
neměl v atributovaném řetězci `.foregroundColor` vůbec — a chybějící barva se v TextKitu kreslí
**černě**, ne „jako okolí“. Ta úvaha se do #157 přenesla ze SwiftUI cesty, kde `foregroundColor = nil`
doopravdy dědí (`DiffLineView` tak kreslí úryvek u vlákna). Nasazuje se proto token `--ink`
(`Palette.ink`) jako základní atribut celého textu, který obarvení syntaxe přepisuje — v bloku diffu
i v sheetu s hunkem, kde byl **celý** log černý na tmavém. Kontrast na přidaném řádku **1,39 → 12,55**,
nejhorší místo (word-level přidaný) **2,41 → 7,24**, ve světlém režimu nepatrné zhoršení proti černé
(19,23 → 16,39) a všude nad AAA. Změřeno i nakresleným pixelem: `0,000/0,000/0,000` → `0,905/0,919/0,950`,
tedy přesně `#E7EAF2`. `DiffPaletteTests` ten kontrast přitom měřily odjakživa a procházely — měřily
**token**, ne kresbu; že se barva nasadí, tvrdí teď `DiffBlockCompositionTests`.

**Na stráži z #393 se tím nic nemění, jen se ukázala z druhé strany:** barva je funkcí barevného
režimu, který je v klíči, takže přepnutí motivu blok přesází — a to je zároveň ta kontrola, že se
stráž nezúžila špatně.

**Na zbytku obrazovky není co vidět, a je to doložené renderem.** `Změněné soubory` v obou pohledech a na
dvou šířkách vyšly proti `main`u **bajt v bajt stejné**; sonda je nejdřív ověřená sama proti sobě.
Blok drží tři počitadla (`updates`, `mounts`, `typesettings`), na kterých stojí sedm nových testů —
a obě strany stráže jsou ověřené **vloženou regresí**: vypnutá stráž (11 nasazení na 11 aktualizací)
i šířka vyhozená z klíče (rámečky zůstanou na staré šířce).

### M11 — Průběh běhu (milník #13)

Čtyři issues, které sahají do téhož — `ReviewProgress`, `ReviewerTimeline` a stav průběhu
v `AppStore` —, takže souběžně nejdou a rozvrh je polovina zadání: **#308** (smí pozdní událost
vzkřísit zahozenou osu) první a sama, protože dokud na to není odpověď, staví se #325 i #326 na
sadě, která padá; pak **#326** (krok je pokus, dokud nedorazí `tool_result` — vrstva dat), pak
**#325** (tab `Průběh`: živý výpis se stropem a sledováním konce) a nakonec **#327** (surová
session v sheetu). Nakreslené je to v sekci 20 návrhu.

### #308 — osu nevzkřísila pozdní událost, ale uložený záznam

**Odpověď na otázku z issue je „ne“ v obou polovinách, a jedna z nich se nedala doprogramovat,
protože nastat nemůže.** `AppStoreProgressTests` padalo na tom, že po tiku bez daného PR nebyla osa
prázdná, a z hlášky to vypadalo na událost, která dorazila po konci běhu a osu postavila znovu
(v ose chybělo `započalo` a razítka byla ze dvou různých hodin). Změřením se to ukázalo jinak:

- **Pozdní událost nastat nemůže.** Proud událostí se dojíždí uvnitř `review()`
  (`reporter.finish()` + `await drained`), takže po konci běhu už nic nepřijde — a dokud běh žije,
  `forget(whatIsNotIn:)` jeho osu z úklidu vyjímá. Zůstává to tedy strukturou, ne kontrolou:
  brána v `record(_:of:for:in:)` by byla mrtvý `if`, který by navíc měřidlu ceny události (#350)
  neuložil nic, protože do storu sype tou samou cestou.
- **„Vzkříšení“ byl fallback na disk.** `timelines(for:)` po úklidu odpovídá z uloženého záznamu
  a ten se **schválně neuklízí** (#137 z něj pozná re-review od novinky). Tik tedy pustí živou
  kopii osy, ne osu, a co okno ukáže potom, je tatáž odpověď jako po restartu (#203). Zahodit osu
  doopravdy by znamenalo zahodit i záznam, tedy rozbít #137 kvůli jedné mapě v paměti.
- **Padal ale skutečný závod, jen jinde.** Snímek osy pro **uložení** se bral mimo proud událostí,
  takže si čtení `reviewTimelines` závodilo s jeho plněním o `MainActor`. Do souboru proto šla osa
  celá, zkrácená na `[ve frontě]`, nebo vůbec žádná — a `dropped` u toho zůstalo nulové, tedy
  o zkrácení mlčelo. To je zrovna to tiché zkrácení, které #203 zakazuje; chybějící `započalo`
  bylo tímhle a druhé hodiny přidala `completeTail`, která konci osy dopočítala razítko
  z `finishedAt`.

**Oprava je jedna věta v návrhu: uložení jde tímtéž proudem jako konec běhu.** `ReviewEvent.finished`
nese celý `ReviewRun` a ukládá ho `drain` hned za zápisem konce osy, takže je osa v tu chvíli
hotová. Zamítnuté varianty: uložit všechny běhy až po `await drained` (ruší pravidlo „ukládá se po
každém doběhlém skillu“ z #97, takže by zavření aplikace uprostřed sady zahodilo i to, co doběhlo)
a synchronizovat zápis s proudem přes continuation (což #242 odmítlo jako cenu navíc v cestě, která
se ruší — a je zbytečná, když ukládá sám proud). Vedlejší efekt: **uložená osa má konec**, takže
doplňování z běhu (#242) platí od teď jen pro soubory uložené dřív; sada testů k němu zůstává,
protože staré záznamy na disku leží dál.

**Závod se dá vyrobit na zavolání, a to je na tom to hlavní.** Samotný test
(`-only-testing:…/forgetsTheTimelineOfAPullRequestThatLeftTheList()`) padal **3× ze 3**, se
souběžnou druhou suitou prošel **4× ze 4** — proto to nad plným během vypadalo náhodně a proto
o tom osm běhů u #296 neřeklo nic. Po opravě je to deterministické: **10 běhů sady z 10 zelených**
a plný běh 3162 testů taky.

**Tvrzení testu se přepsala podle rozhodnutí, ne aby přestala padat.** Místo „po tiku není osa
žádná“ stojí na tom, že se pustila živá kopie a že osa z disku má **tytéž události** — porovnání
celé osy chytá zkrácený rozjezd i konec z jiných hodin. K tomu je nové tvrzení o tom, že se něco
NEstalo: **běžícímu review tik osu nesebere a další události do ní pokračují**, tedy nevznikla
druhá osa ani nová. Krok nad kódem u toho dorazí až po tiku (`FakeReviewRunner` na to dostal
`progressAfterRelease:` — bez toho hlásí všechen průběh dřív, než se běh dá pozdržet), takže je to
zrovna ta „pozdní událost“ z názvu issue; bez ochrany běžícího review v `forget` zbyde v ose
`[tool(Read), finished]`, tedy osa začínající uprostřed běhu. Obojí je ověřené vloženou regresí
a obojí padá **na tvrzení, ne na timeoutu**.

**#360 s tím sdílí ten závod, ale ne diagnózu.** Tvrdilo, že tentýž test „vyčerpá strop čekání“
(20,4 s z 22 s celého běhu). Nevyčerpal: Swift Testing pouští suity paralelně a hlásí u testu
**uplynulý** čas, takže test, který se odbyde za 20 ms na začátku běhu, hlásí celou jeho délku.
Změřeno: **793 z 3383** hlášených položek hlásilo 20+ s v běhu, který trval 24 s, a tentýž test
hlášený jako 23,6 s se sám o sobě odbyde za 0,02 s. Čekání v něm žádný vlastní strop nemá — jde
přes `waitUntil` (#296) —, takže z #360 zbývá jen ten závod, který opravuje #308.

**Na obrazovce není co vidět.** Osa se v tabu `Průběh` kreslí ze stejného modelu jako dřív; mění se
jen to, co se z ní uloží na disk a v jakém okamžiku.

### #326 — krok v ose je pokus, dokud nedorazí `tool_result`

**Odmítnutý nástroj se v ose dozvíme hned, ne až s koncem běhu.** `StreamParser` čte od teď
i `user` eventy, tedy odpovědi na to, o co si model řekl (`tool_result` v `message.content[]`),
a páruje je s pokusem přes `tool_use.id`. Krok proto nese stav: **běží** (odpověď nedorazila),
**prošel** (a jak dlouho se na odpověď čekalo), **vrátil chybu**, nebo **byl odmítnut**.

Do téhle změny se odmítnutí poznalo jedině z `permission_denials` v závěrečném `result` eventu, tedy
o minuty později — a u revieweera, kde je odmítnutí **normální stav** (tvrdá podmínka č. 2 zakazuje
`Bash(gh:*)`), okno do té doby tvrdilo, že nástroj proběhl.

**Klíčové zjištění: odmítnutí se pozná strukturou, ne textem hlášky.** U #17 se rozhodlo, že se
`tool_result` čítat nebude, protože „rozeznat odmítnutí od běžné chyby nástroje se dá jen podle
anglického textu“. Neplatí to — `claude` posílá u neprovedeného volání navíc
`tool_result_meta[].non_execution_kind` (`user-rejected` v obou fixtures s odmítnutím). Rozlišení je
podstatné v obou směrech: `grep` bez shody vrací `is_error` při každém běhu, takže odznak
`ODMÍTNUTO` u něj by z read-only režimu udělal poplach. Chyba nástroje se proto kreslí jako prošlý
krok a hláška je v nápovědě řádku; červený odznak má jedině odmítnutí.

Co u toho ještě padlo: **`StreamSummary.deniedTools` je zrušené** — bylo to pole plněné z `result`
eventu, které se v UI neobjevilo, protože se dalo ukázat jen u kroku, a krok o svém odmítnutí
nevěděl. Odmítnutí teď nese krok, tedy to místo, kde se kreslí; druhý seznam by byl druhá pravda
o tomtéž. `permission_denials` zůstává jako **záchrana** pro
pokus, kterému odpověď nedorazila; při shodě prohrává s tou ze streamu, protože ta přišla, když se to
stalo, a nese trvání.

**Zpětná kompatibilita je testovaná, ne předpokládaná.** Nová pole (`ToolAttempt.id`, `outcome`) jsou
v souboru volitelná a u nespárovaného pokusu se neukládají vůbec, takže osy uložené dřív se čtou dál —
a **nekreslí se jako běžící**: `Policy.toolStepMark` u kroku bez `id` značku nevydá, protože se jeho
odpověď neměla s čím spárovat. Test nad literálem starého tvaru je doplněný druhým, který hlídá, že se
ten tvar nezměnil.

**Na obrazovce se mění řádek kroku** v rozbaleném výpisu v tabu `Průběh`: vpravo trvání (`0,2 s`),
`běží…` u pokusu bez odpovědi a odznak `ODMÍTNUTO` u odmítnutého — vysázené podle sekce 20 návrhu,
včetně barev (`find` u běžícího, `crit` na 14 % u odznaku). Zkontrolované offscreen renderem
(`ToolStepRenderProbe`) ve dvou šířkách; v úzkém místě se ořezává cesta, ne značka.

**Rozbalený výpis, strop a sledování konce zůstávají na #325** — tohle je vrstva dat pod ním. Osa se
o odpověď **neprodlužuje** (mění se krok, který v ní je), takže #325 dostane hotové to, co potřebuje
kreslit: jeden řádek na `tool_use` a na něm jeho stav.

### #325 — tab Průběh: živý výpis kroků se stropem a sledováním konce

**Nebyla to nová funkce, ale nedodělaná.** Kroky se do osy zapisovaly a umělo se je vykreslit už
od #22, jenže pod **zavřeným** rozbalením, bez stropu a bez vlastního scrollu — takže se za běhu
na to, co reviewer dělá, nedalo koukat. Od #325 visí pod fázemi **okno se stropem a s vlastním
scrollem**, u běžícího revieweera rozbalené; při doběhnutí se nezavírá samo.

Strop je podstatný: rostoucí blok by při **každé** události posunul všechno pod sebou, tedy
přerovnal celý tab několikrát za vteřinu.

**Do stropu je to ale výška obsahu, a to je oprava po proklikání.** První verze měla výšku pevnou
vždycky, takže běh o třech krocích nakreslil okno vysoké 138 bodů se dvěma třetinami prázdna — a to
je stav, ve kterém **každé** review začíná. Okno proto roste, dokud na strop nenarazí; přerovná se
tím nejvýš pod prvními osmi událostmi běhu, ne pod každou z tří stovek. Tři věci, které z toho
plynou:

- **výška se počítá z dat, ne z přeměřeného obsahu** — výška obsahu hlášená scrollem se při
  rozvržení mění i naplano (`1825 → 3505 → 1825` na jedné scéně), takže okno navěšené na ni by
  u nezměněného obsahu poskakovalo o řádek tam a zpět. Rozhoduje čistá funkce
  (`Policy.stepFeedWindow`) nad rozměry, které dodává view, protože se kreslí tam (#236);
- **o výšce řádku nesmí rozhodovat ikona** — SF Symboly jednu výšku nemají, takže řádek se
  zadáním, které nedorazilo celé, měřil 17 bodů proti 15 u ostatních a neznámý nástroj 16.
  Spravilo to `imageScale(.small)`, ne `frame(height:)`: rámec se v `firstTextBaseline` účtuje od
  dolní hrany, takže s ním řádek naopak vyrostl na 16. Návrh má ikonu menší než text taky;
- **`Sledovat konec` ani pilulka `↓ N nových` se nekreslí, dokud není co rolovat** — obojí slibuje
  posun tam, kde výpis už je.

Návrh (sekce 20) se u toho **překreslil taky**: `height: 138px` je `max-height`, protože v CSS to
pravidlo platilo i pro krátký výpis.

**Rozbalení drží tab, ne dráha.** Do #325 to byl `@State` uvnitř `ReviewerLaneView` a dráhy jsou
v `LazyVStack`u, takže odrolovaná dráha se zahodila i se svým stavem — výpis se sám zavřel zrovna
u běžícího revieweera. Automat rozbaluje jedině `running`, a **jednou za běh**: bez toho by
zavřený výpis běžící dráhy otevřela příští událost, tedy do vteřiny.

**Jeden strop, 300, pro živou i uloženou osu.** Do #325 ho měla jen uložená, takže se za běhu
držely stovky událostí, které po restartu zmizely — a nikde to nebylo napsané. Vyšší strop pro
živou osu by sliboval, že se ke krokům dá vrátit; nižší by zahodil kroky, které v souboru zůstanou.
Ořezává se začátek a **zkrácení se přiznává dvakrát**: v hlavičce výpisu a řezem na jeho začátku.

**Cena překreslování byla součást zadání a je změřená, ne odhadnutá** (offscreen render výpisu
o 300 řádcích, série střídavě podle #274):

| Co | Do #325 | Od #325 |
|---|---|---|
| složení dráhy z osy o 300 událostech | 0,328 ms | **0,004 ms** |
| jedna událost v otevřeném výpisu | 40,29 / 41,48 ms | **9,25 / 8,91 ms** |

To první je souhrn osy počítaný **při zápisu** (`ReviewerTimeline.Digest`) místo osmi průchodů
polem při každém překreslení. Vyšlo z toho i to, co nebylo v zadání: souhrn musí být u faktů
o běhu **monotónní**, jinak by ořez osy nechal fáze dráhy spadnout zpátky na `nedošlo na ni`.

**Sledování konce se vrátilo — do paměti, ne do konfigurace.** #242 ho zrušilo i s klíčem
`progressFollowsTail`, protože „s dráhami není co následovat“; se scrollujícím výpisem ten důvod
odpadl, ten druhý (uložená předvolba, kterou nikdo nečte) platí dál. Vypíná se odrolováním nahoru
i klikem, na konci se zapne zpátky, jinak je vidět pilulka `↓ N nových`.

**Dvě věci se u toho musely změřit, protože první verze byla špatně.** Posun ve stejném průchodu,
ve kterém obsah narostl, SwiftUI **zahodí** — výpis zůstal 20 bodů od konce a nedojel tam ani po
pěti kolech smyčky (tatáž past jako u fokusu, #184); a `defaultScrollAnchor(.bottom, for:
.sizeChanges)` na sledování konce **nestačí**, nechá výpis o řádek pozadu. Rozhodnutí „obsah
narostl“ proti „člověk odscrolloval“ je proto čistá funkce v `Policy`: narostlý obsah je o řádek
„mimo konec“, takže by se sledování vypnulo samo první událostí.

**`ReviewerTimeline.newestEntry(in:)` je smazané, i s testy** — zadání dalo na výběr použít, nebo
smazat. S výpisem **na revieweera** se každé okno drží svého konce, takže hledání nejnovější
události napříč reviewery by byl stav, který nikdo nečte.

**Co zůstalo #327:** surová session v sheetu, tedy próza modelu, výstupy nástrojů a systémové
události. Výpis kreslí jen kroky, a schválně — próza je řádově víc dat a v okně se stropem by
kroky vytlačila z dohledu. Tlačítko `Ukázat session`, které návrh kreslí v hlavičce výpisu,
proto v #325 **není**.

### #327 — surová session: přepis transcriptu v sheetu

**Posledním issue milníku M11**, a je to ta záchranná brzda pod výpisem kroků: sheet s celým
transcriptem session, tedy s tím, co výpis schválně zahazuje. Otevírá se z hlavičky výpisu **i z jeho
sbaleného řádku** (doběhlá dráha je ta častější) a bez známého `session_id` nebo pracovního stromu se
tlačítko **nekreslí** — stejné pravidlo jako u `Zkopírovat resume`.

**Nová datová cesta z toho nevznikla.** `TranscriptLocation` cestu odvodí, `TranscriptStore` soubor
umí otevřít od #97; přibyly dvě metody protokolu (`snapshot`, `size`) a přepis
(`TranscriptTranscriber`). Podrobnosti v [`architektura.md`](architektura.md), sekce *Surová session*.

**Oba stropy jsou z měření, ne z odhadu** (922 transcriptů pod `~/.claude/projects`): okno je
posledních **4 MB** zarovnaných na začátek řádku a jedna událost má **8 kB**. Řádek je špatná
jednotka — největší soubor má 53,3 MB a jen 2 348 řádků, takže ocas o 6 000 řádcích by na něm nezabral
vůbec; a nejdelší řádek má 7,5 MB, takže jeden `tool_result` bez druhého stropu sežere celé okno.
Protože je soubor **lokální**, čte se `seek`em od konce a **stav „moc velký“ nevzniká vůbec** — na
rozdíl od logu checku, kde ho vynutila síť.

**Tři odchylky od mockupu, všechny vědomé** (celé i s důvody ve specifikaci): počet událostí celého
souboru se **netvrdí** (šel by zjistit jedině přečtením 53 MB, tedy tou cenou, kvůli které okno je),
totéž u řezu na začátku textu, a tělo události se **zalamuje** — v jednom textovém kontejneru nejde
mít zalomené odstavce vedle nezalomených, a próza je to, kvůli čemu se sem chodí. K tomu jedna věc,
kterou návrh nepředvídal: prázdno má **dvě různé věty**, protože do téhož stavu spadne i soubor,
ve kterém bajty jsou a nedala se z nich přečíst ani jedna událost.

**Co se muselo změřit, protože odhad byl vedle.** Otevření nad 53MB transcriptem stálo napřed 627 ms
a vypadalo to na ořez těla po znacích (osm tisíc alokací `String`u na událost) — jeho odstranění
nezměnilo **nic**. Rozpad ceny ukázal, že rozbor JSONu stojí 6,9 ms a **dělení textu na řádky
216 ms**, tedy ta jediná věc, která jde nad megabajty po `Character`ech (`TextLines`, kvůli `CRLF`).
Ubralo se proto tam: dělí se jen `limit` bajtů, ne celé tělo a celý zbytek (**428 → 108 ms** za
přepis, 655 → 312 ms za celé otevření). Zbylých 216 ms zlevnit **nešlo** a nemá se to zkoušet znovu —
jediná cesta by byla druhé místo, kde se rozhoduje, co je řádek.

**A jednu chybu našel render, ne test:** vysázená hlavička neměla mezery mezi časem, druhem
a detailem (`23:13:36Bashgh pr view 412`), protože mezera byla jen ve skládání kopie. Od té doby je
`RawSessionScript.gap` jedna konstanta a testuje se, že `attributed(…).string == plain(…)`.

**A jednu podstatnou našel Copilot** (#408): odznak `ODMÍTNUTO` by se nad skutečnými daty neobjevil
nikdy. Kód hledal `non_execution_kind`, tedy tvar ze `stream-json` — transcript ale nese odmítnutí
jako `toolDenialKind` na **řádku** a i s jinou hláškou. Vyšlo z toho poučení, které přežije tenhle
issue: **nepřítomnost klíče v souborech, které tu situaci nemají, není doklad o formátu.** Původní
tvrzení „CLI to do souboru nepíše“ se opíralo o `grep` nad transcripty z review, ve kterých žádné
odmítnutí nebylo; doklad je až soubor, ve kterém odmítnutí je — a ten se musel vyrobit spuštěním
(`transcript/denied-tool.jsonl`).

Ze stejného kola je i **sonda v podobě bajtu před oknem** (okno zarovnané přesně na hranici řádku
o svou první událost přijít nesmí), zarovnání na `CR` a `CRLF`, ne jen na `LF`, a **generace** u čtení
přepisu — dvě kliknutí na `Načíst znovu` nad týmž cílem se od sebe cílem poznat nedají.

**Z proklikání přišly dvě připomínky a obojí je zapracované** (i do mockupu, sekce 20). Sheet se
**dá roztáhnout za okraj** a velikost si pamatuje mezi otevřeními; tlačítko se jmenuje **`Ukázat
session`**, protože v úzkém místě vedle `Sledovat konec` nese slovo „surová“ nejmíň — pojem
*surová session* zůstává v nadpisu sheetu i v dokumentaci.

U toho se ukázala chyba, která tam ležela od začátku: **bez `presentationSizing(.fitted)` SwiftUI
`idealWidth` u sheetu zahodí** a okno je široké jako `minWidth`, takže přepis byl 720 bodů široký
místo nakreslených 940 — a právě proto vypadal moc úzký. Nová výchozí velikost je **1 180 × 760**
a je změřená (ze 720 na 1 180 ubude 15 % řádků sazby, dál jednotky procent). Druhá past je, že se
sheet **rozvrhuje dvakrát a v prvním průchodu má podlahu**: bez odmlky by se ukládala ta podlaha
a sheet by se od druhého otevření otevíral nejmenší možný.

**Zbylo z toho jedno otevřené zjištění**, ne oprava: tatáž chyba je v `CodeTextSheet`u (celý log
a hunk kódu), kde `minWidth` je 560 a ideál spočítaný z obrazovky až 2 700 — tedy celé měření #292
se neuplatní. Je to **jiná obrazovka**, takže to spadá pod schvalovací bránu na vzhled a patří do
vlastního issue.

**Tím se zavírá milník M11.**

### #392 — labely a vyžádaní reviewery v panelu, panel i v `Commitech`

Dvě části jednoho zákresu (`docs/navrh.html`, sekce 24 a 25) a patří k sobě: labely a reviewery
bydlí v pravém panelu, a právě proto ten panel musí být i v *Commitech* — jinak se v jednom ze
čtyř tabů schová i to, co platí o celém PR.

**Aplikace o tom do #392 nevěděla to podstatné.** Labely neznala vůbec (v modelech po nich nebylo
ani pole), vyžádané reviewery znala jen jako **události v konverzaci** (`reviewRequested`,
`reviewRequestRemoved`), tedy „to se stalo“ — ne „kdo na tom stojí teď a jak odpověděl“. Kvůli
obojímu se chodilo do prohlížeče.

**Tvrdá podmínka č. 1 se tím vědomě změnila.** `ReviewPublishing` má šest metod místo čtyř
(`setLabels`, `requestReviewers`) a v `CLAUDE.md` je přepsané i to, co v zákazu **zůstává**:
approve mimo review, merge, zavření PR a milník. Důvod je tentýž a tentýž precedens jako u #73
(odpověď do vlákna) a #216 (komentář pod PR): u **vlastního** PR je štítek a reviewer součástí
toho, jak si člověk řídí svoji frontu, a je to poslední věc, kvůli které se od hotového review
přepíná do prohlížeče. Brána je **tatáž** (`allowsPublishing`, globálně i per repo) — druhý
přepínač by byl druhé místo, kde se dá „samo nic neodejde“ porušit. `GitHubGateway` zůstal **bez
zápisu**: čtení labelů PR i repa a reviewerů i assignable uživatelů jsou tři **čtecí** metody.

Co se u toho rozhodlo:

- **Měnit jen na vlastním PR, a na cizím akce nejsou vůbec** — ne zašedlé. Zašedlé tlačítko tvrdí
  „tady se to dělá, jen teď ne“, a to je u cizího PR nepravda. U **vypnuté brány** je naopak pravda,
  takže tam se akce kreslí zakázaná s důvodem.
- **Label bez potvrzovacího sheetu, ale jen z labelů, které repo zná.** Je vratný jedním klikem
  a nikoho neupozorní; volný text tam nepatří, protože z něj se dá omylem vyrobit nový label, a ten
  už z repozitáře sám nezmizí.
- **Reviewer jedním pojmenovaným kliknutím** (`Vyžádat review od …`). Request pošle člověku
  upozornění, které se odebráním **nedá vzít zpět**, takže potvrzení je v textu tlačítka.
  Odebrání odsud nejde — není to opravný krok, jen zametení.
- **Sada labelů se posílá celá, jedním `PUT`,** a payload jde souborem: sundání posledního štítku je
  `{"labels": []}`, kdežto `gh api` bez jediného `-f` neposílá tělo vůbec.
- **`headSha` se u obojího neověřuje**, stav PR ano. Štítek se váže na PR, ne na commit.

**Druhá polovina: panel v `Commitech`.** `PullRequestTab.showsReviewPanel` je u `.commits` `true`;
dělič v pruhu záložek se **neposunul**, protože se kreslí z `isReviewerOutput` (#242) a ta se
nemění. Přepsal se test `panelIsNotReviewerOutput`: `Commity` z jeho výčtu odešly a tvrzení
„vlastnosti nesplynuly“ drží **`Kontroly` samotné**.

**Ten tvrdší důvod, proč tam panel nebyl, se neobešel.** Nálezy jsou klíčované `headSha` (tvrdá
podmínka č. 5), takže u rozkliknutého **staršího** commitu neplatí pro to, co je na obrazovce —
a z podmínky se proto stala **věta v UI**: nad seznamem klidná (*Nálezy jsou proti hlavě e8d4a60.*),
u staršího commitu **výstraha** (*… Tenhle commit je 5e2b1aa, takže o kódu na obrazovce nemluví.*)
a **ztlumené karty**. Rozhoduje `Policy.findingsHeadNotice`, hlava se bere z **uloženého záznamu**,
ne z detailu PR.

**Změřeno, protože to zadání žádalo:** se stromem souborů (210 b) a rozloženým panelem (306 b) zbude
na diff commitu **531 bodů**, tedy **22 znaků na stranu** ve pohledu *Vedle sebe* a 49 pod sebou.
Slib 120 znaků na stranu by chtěl okno **~2665 bodů**. Nevynucuje se proto nic: složený proužek dá
ve splitu 39 znaků a bez stromu 52, takže u commitu je čím zaplatit (⌘1, ⌘2). Nejužší stav (okno
700, panel na podlaze) dá na diff **402 bodů** a v tom pásmu se od #392 měří i přetečení seznamu
commitů.

**Sekce 02 a 19 mockupu se přepsaly** — jsou to záznamy dneška, takže v panelu v *Přehledu* stojí
obě sekce a v *Commitech* je panel; sekce 24 a 25 zůstávají jako záznam rozhodnutí.

**Testů 3394** (z 3238), z toho pět nových suit k labelům a reviewerům, jedna k větě o hlavě a jedna
měřicí. Tři tvrzení jsou ověřená **vloženou regresí**: rezerva na `+N` (bez ní vzniknou tři řádky),
`box-sizing` u chipu (bez rámu je rozdíl 14 bodů) a to, že panel na notici reaguje (na
`tiffRepresentation` ten test procházel i s ignorovanou notící, na bajtech bitmapy spadne).

**Neověřené zbylo jedno:** stav „vlastní PR s labely a povoleným odesíláním“ se ve slotu vyrobit
nedá — `bin/slot-config.sh` odesílání schválně vypíná a zdroj je `review-requested`. Odeslání labelu
ani vyžádání reviewera proto **neproběhlo proti živému API**; kryjí to testy publisheru (nula
volání `gh` bez brány, tvar payloadu na bajtech) a offscreen render panelu ve všech stavech.

**Dvě věci dorazily z proklikání, ještě před mergem.** První byla **tichá ztráta**: GitHub drží
vyžádané reviewery ve **dvou** polích a čtlo se jen `requested_reviewers`, takže u PR s týmovou
žádostí byla sekce prázdná, i když review někdo vyžádal — změřeno na
`keboola/platform-architecture-and-concepts#278` (`requested_teams: ["ajda-swimlane"]`), a v jedné
frontě to byly **čtyři PR ze čtrnácti**. Týmy proto mají vlastní pole (`PullRequestMetadata.teams`)
a v panelu **čtvrtý druh řádku pod lidmi**: skupinová ikona ve čtverci místo kolečka s iniciálou
(kolečko znamená osobu) a `tým` v pravém sloupci — odpověď u týmu nemá význam, dá ji až ten, kdo za
tým odpoví, a ten se objeví jako osoba. `+ reviewer` umí vyžádat i tým, **týmž jedním voláním**
(`reviewers` + `team_reviewers`); nabídka týmů jde přes `orgs/{org}/teams`, protože
`repos/{o}/{r}/teams` vrátilo 404 i na repu, kam se dá psát (chce admin práva). Slug se u toho
sjednocuje na podobu bez předpony organizace — `gh pr view` dává `keboola/ajda-swimlane`, REST
`ajda-swimlane` a zápis chce to druhé.

Druhá věc: **zakázané tlačítko musí říct proč.** Vypnutá brána ve slotu vypadala jako rozbitá
aplikace, takže pod sekcemi stojí věta („Odesílání na GitHub není pro … povolené. Zapni ho
v nastavení (⌘,).“) — tatáž, na které skončí publisher, a tiše šedá, protože nastavení není porucha.

**Zakládání nových labelů do tohohle issue nepatří** a je to rozhodnuté: je to zápis do
**repozitáře**, ne do PR (`POST /repos/{owner}/{repo}/labels`), tedy sedmá metoda protokolu, k tomu
nové pole s barvou (nová věc na obrazovce → mockup a schválení) a hlavně: **nedá se vzít zpět jedním
klikem**, protože smazání labelu ho odebere ze všech PR v repu. Uzavřená množina
z `fetchRepositoryLabels` tedy zůstává; na zakládání je samostatné issue.

**Třetí a čtvrtá věc z proklikání: nabídka.** Položky nesly sloveso (`Vyžádat review od Ada…`),
takže čtrnáct řádků opakovalo totéž a předpona ořezala to jediné, čím se od sebe liší. Sloveso se
přesunulo do **nadpisu** (`Vyžádat review od`, u labelů `Přepnout label`, protože klik je přepínač)
a v položkách zbyla jména — pro čtečku obrazovky celá věta u položky zůstává, protože nadpis se
k ní nepřečte. A od šesti položek je nad seznamem **hledání**: pravidlo shody se **dělí s paletou
⌘K** (tytéž primitivy, tedy bez diakritiky, bez ohledu na velikost písmen, víc slov jako „a
zároveň“ a silnější shoda nahoru), filtruje se podle toho, co je v řádku vidět, a kurzor **ořezává,
necyklí**. Klávesnice funguje proto, že nabídka nikdy nebyla `Menu`, ale popover s vlastními views;
`esc` se schválně neobsluhuje, popover ho umí sám. Prázdný výsledek je **čtvrtý stav** nabídky
(vedle nenačteno / prázdné repo / porucha) a má vlastní větu — prázdná plocha by vypadala jako
spadlé načítání.

**Pátá věc z proklikání: kurzor patří do pole hned po otevření.** Bez toho je nabídka „otevři,
**klikni** a piš“, tedy o krok delší než ta, kterou nahradila. Do téhle opravy tam stálo
`onAppear` — a komentář u něj tvrdil, že fokus sedá, přitom nesedal; je z toho poučení, že
tuhle vlastnost **nedokládá kód, ale proklikání**. Dělá to `.task` s jedním `Task.yield()`, což
je tentýž mechanismus, který si na sobě změřila paleta ⌘K (#184): přiřazení ve stejném průchodu,
ve kterém pole vzniká, SwiftUI zahodí a `AXFocused` zůstane `false` **navždycky** — u `onAppear`,
u `task` bez yieldu i u `defaultFocus`. Rozhoduje **počet průchodů, ne čas**, takže tady není
žádná pauza ani nic, co by si plánovalo další kolo (#350, #358). Šipky a `↵` fungují i s fokusem
nastaveným při otevření (ověřeno sondou: `.handled` přebije pole hned, ne až po prvním stisku)
a fokus **nabídku nepřežije**, protože `@FocusState` sedí ve view, které s popoverem zaniká.

Z toho vypadly ještě dvě věci. Práh, odkdy se pole kreslí, se přesunul do
**`Policy.pickerShowsSearch(count:)`** — do té doby měla každá nabídka vlastní `searchFrom = 6`,
takže se mohly rozejít potichu; zároveň je to jediné, co se o tom poli dá tvrdit **číslem**, a tak
je na to výčet kolem hranice (ověřeno vloženou regresí: `>=` místo `>` shodí dva testy). A **sonda
fokusu v harnessu být nemůže**: testovací host nedostane aktivaci (`NSApp.isActive == false`,
`isKeyWindow == false` i po `activate(ignoringOtherApps:)`, strop 5 s), takže bez key okna nemá
fokus kam sednout a taková sonda by měřila něco jiného, než tvrdí. Měřilo se proto samostatným
přeloženým souborem mimo strom; tabulka variant je v [`testovani.md`](testovani.md).

**Neověřené zůstává i tady jedno:** že se v aplikaci doopravdy píše bez kliknutí. Samostatná sonda
`onAppear` nechá projít, takže na potvrzení nestačí — poslední slovo má proklikání v okně, stejně
jako u odeslání proti živému API.

Sekce 24 mockupu je o nabídku dokreslená (nadpis, hledací řádek s **kurzorem**, položky bez
slovesa, filtr, prázdný výsledek, patka s klávesami) a publikovaná na tutéž adresu.

### #361 — osmé kolo: instrumentace grafu (otevřené)

**Kolo se nepodařilo vyrobit ani poosmé, takže #361 zůstává otevřené** a tohle není oprava
tuhnutí. Zbyl z toho **nástroj**, který u předchozích sedmi kol chyběl: v hořícím kole se
nepřeloží ani jedno tělo, takže dosavadní počitadlo průchodů `body` v tu nejdůležitější sekundu
řeklo jen „0 kol runloopu, sekunda CPU“.

Nově se z něj dá přečíst, **co se v tom kole přepočítává a kdo si o to řekl**. Do záznamu
(`./bin/run.sh --diagnose`) jde za hlavní řádek úseku počet zásahů háků v líném seznamu
(`graf: DiffRow.id=857 …`) a **evaluační zásobník AttributeGraphu** — jména atributů od toho, co
se počítá teď, k tomu, kdo si o řadu řekl, a u vstupů příznak `changed`.

Ověřeno spuštěním, ne z dokumentace: `AGGraphDescription(nil, ["format": "stack/text"])` stojí
**0,0063 ms**, jde z `body`, z `Layout`u, z `of:` closure u `onGeometryChange` i z getteru
identity, a z **cizího vlákna** vrátí `nil` — proto se vzorek odebírá z háku na hlavním vlákně
a zapisovací vlákno z #391 zůstává jen zapisovatelem. `AGGraphSetTrace` ani
`AGGraphSetInvalidationCallback` se nepoužívají: obojí si nastavuje sám SwiftUICore, takže by se
přepisovalo to, co se měří. Vlastnictví návratové hodnoty se zjistilo **pádem** (`SIGSEGV`
v `objc_release` uvnitř `AutoreleasePoolPage::releaseUntil`) — footprint procesu tvrdil opak;
hodnota je autoreleased. Podrobnosti a čísla v [`architektura.md`](architektura.md), sekce
*Diagnostika kreslení*, rozhodnutí i zamítnuté cesty ve specifikaci.

**Nitka pro příští záchvat**: nad projížděním (tedy mimo záchvat) je kořenem dotazu
`LazySubviewPrefetcher<LazyVStackLayout>` — ten `signalPrefetch`, který je ve vzorcích jediný
re-arm —, vrcholem `LazySubviewPlacements` a jediný `changed` vstup je **transformace**
(`CoordinateSpaceNameTransform` v diffu, `ScrollViewChildTransform` v ose). V záchvatu se z týchž
řádků pozná, jestli se ta transformace mění i tehdy, když se nikam neroluje.

### #367 — test vzhledu měřil globální `NSApp.appearance`, takže v paralelním běhu padal

**Na tomhle není co vidět** — je to celé testovací vrstva, aplikace se nemění ani o řádek.

`AppStoreAppearanceTests/Bez cíle se na NSApp nesáhne` si bral `NSApp.appearance` před a po
a porovnával je. Při práci na #331 spadl, ve třech čistých bězích byl zelený, tedy **falešně červený
`main`** — a to je dražší než chybějící test: podle zelených testů se tady rozhoduje o mergi, takže
test, který padá „někdy“, učí ignorovat červenou.

**Druhý pisatel toho globálu je sám hostitel testů, a to je změřené**: v běhu, ve kterém na vzhled
nesahá žádná jiná suita, je `NSApp.appearance` po startu `nil` a asi **300 ms** poté
`NSAppearanceNameAqua`, protože živý `AppStore` uplatní volbu z konfigurace uživatele. Tím padly obě
zřejmé léčby — `.serialized` na sadu ani zámek v testech na hostitele nedosáhnou.

Tvrzení se proto přesunulo **nad zdrojáky** (`GlobalAppearanceTests`, tatáž konstrukce jako
`SingleWayOutTests`): `App/Store/` importuje jen `Foundation` a `Observation`, takže store `NSApp` nemá ani
jak napsat; živý
cíl se v `App/` jmenuje **jednou** a uplatňuje se jedině `appearance?.applyAppearance(`; a **žádný
soubor v `Tests/`** na globální vzhled nesahá. V `AppStoreAppearanceTests` zůstalo to, co je
vlastnost storu — volba se přečte i bez cíle a chybějící cíl není chybový stav.

**Sonda přepnutí vzhledu (#278) přepíná na svém okně**, ne na `NSApp`: `defer` vracel hodnotu až po
měření, takže mezitím platila vynucená tma pro všechno, co v procesu kreslilo. Odpověď na otázku
sondy se tím nemění, ověřeno spuštěním — světlý render vyjde světlý, tmavý tmavý a prostředí
`colorScheme` se pohne spolu s paletou.

**Ověřeno vložením regrese ze tří stran**: kolizní suita se 4000 přepnutími globálu (před opravou
padne původní test, po ní projde celá sada — 8 testů ve 2 suitách při 82 s souběžného přepínání),
výchozí hodnota `appearance: AppAppearance.application` v init pro testy (padne tvrzení o jednom
jmenování, `2 == 1`) a `import AppKit` s přímým zápisem v `apply(_:)` (padne pět tvrzení ve všech
třech testech). Guard nad `Tests/` se přiznal sám: kolizní suitu nahlásil, dokud se nesmazala.

**Z review na #400 přišel jeden reálný nález a je opravený**: zákaz `import AppKit` v `App/Store/` obchází
`import Cocoa`. Místo dalšího zakázaného jména se hlídá **výčet povolených** (`Foundation`, `Observation`),
což tu cestu zavírá celou — ověřeno vloženou regresí, `import Cocoa` výčet složí.

**A ještě jeden člen téže třídy, nalezený plným během**: `CommitPanelRoomTests` spadly na
`(both → 0) > (treeOnly → 35)`, tedy na víc místa a **méně** znaků, což z monotónní funkce vyjít
nemůže — šířka znaku mono písma byla computed property, takže se stav procesu čítal při každém
použití a mezi dvěma voláními v jednom testu se vyřešil jinak. Bere se **jednou za test**.


**Reviewer, který nepřečetl kód, se už nekreslí jako čisté review (issue #383).** `security-review`
hlásil od 17. 8. nulu nálezů ve 12 ze 14 běhů a stál desetinu toho, co předtím — okno z toho udělalo
`čisté`. Příčina je mimo aplikaci (skill přestal spouštět `Agent` a grepoval v transkriptu vlastní
session) a neopravuje se tady; aplikace je orchestrátor a prohlížeč. Naše vada byla jediná: *„nic
nenašel“* a *„nedělal práci“* se z obrazovky nedaly rozeznat.

Pozná se to z **uložené osy**, ne z ceny: `Policy.codeReading(of:)` se ptá, jestli v ose je `Read`
s cestou **uvnitř** pracovní kopie. Rozhodovalo se nad **40 uloženými běhy** z cache a cena se do
pravidla nedostala právě proto, že nediskriminuje — běh za 0,12 $ otevřel tři soubory, běh za 0,44 $
osmnáct, kdežto jeden ze čtyř podezřelých stál 0,74 $. Pravidlo pojmenovalo právě ty čtyři a u jednoho
z nich (`db-extractor-adapter#39`) našel `code-review` na tomtéž commitu **dva nálezy**, tedy doložené
falešné čisto.

**`CodeReading` má tři hodnoty, a ta třetí je pointa**: `unknown` (osa chybí, je zkrácená, nezná
strom, nebo je v ní `Grep`/`Agent`, u kterých cesta v záznamu není) **není `unread`**. Z chybějícího
záznamu se nesmí stát obvinění — osa se ukládá od #203, takže 15 ze 40 běhů ji nemá a okno by se
rozkřičelo nad každým starším review naráz.

V okně z toho je **třetí stav** vedle `čisté` a `selhalo` (`ReviewState.inconclusive(reason:)`):
odznak říká, co chybí (`kód nepřečten`, `bez hlášení`, `ztracené nálezy`), je okrový jako
`zastaralé` — session doběhla, takže červená by lhala —, a ta okrová jde **z palety** (`--stale`
z návrhu), protože systémová žlutá měla na kapsli odznaku ve světlém režimu kontrast **1,41** proti
4,00 u tokenu; přebarvilo se s ní i `zastaralé`, kde ta vada ležela od #172 (nález Copilota) a v prázdném tabu nálezů stojí věta i s tím,
čím to pustit znovu. Nová věc na obrazovce to není: přeznačil se existující odznak, chip revieweera
i díl proužku, takže brána na vzhled se neotevírala. Rozhodnutí o „čistu“ bydlí od #383 na **jednom
místě** (`Policy.inconclusiveReason(of:)`) — do té doby si ho skládal každý ze tří čtenářů sám
a lišili se pořadím, čtení kódu nekontroloval nikdo.

**Ověřeno vloženou regresí v obou směrech**: bez podmínky na čtení kódu padne 8 tvrzení v 6 testech
(falešné čisto), a když se z `unknown` udělá `unread`, padne 12 tvrzení v 8 sadách napříč repem
(falešný poplach). Testů 3509.


**Po slotu už nezůstává aplikace, doména ani záznam v databázi (issues #398, #399).** Paralelní běh
nechával na stroji dvě věci, o kterých repo nevědělo: záznam v LaunchServices mířící do worktree,
který už neexistuje (za jedno dopoledne **čtrnáct**, mazaných ručně), a **doménu v `UserDefaults`**
slotové aplikace — ta přežije smazání bundlu i cache, takže příští slot na tomtéž písmenu nastartoval
s nastavením po předchůdci, tedy i s tím, co z něj `bin/slot-config.sh` schválně vyndal (odesílání,
notifikace, automat).

Z pěti příkazů v dokumentaci je proto **`bin/slot-cleanup.sh`**: postup, který se dá vynechat, se
vynechá — doména v tom postupu nebyla vůbec a uklízela se jen proto, že to orchestrátor napsal
subagentům do zadání, tedy z jeho kontextu, ne z repa. Kontrola identity bundlu a odregistrování
z databáze se vyčlenily do `bin/lib/bundles.sh` a volají se **z úklidu i z `bin/run.sh`**, takže
databázi zametá i restart hlavní aplikace po každém mergi.

**Vybírá se podle toho, co na disku chybí, nikdy podle jména** — hlavní `/Applications/PRism.app`
i aplikace slotu, na které pracuje někdo jiný, jsou na disku, takže z úklidu vypadnou z principu,
ne díky výjimce.

Tři věci, které měření vyvrátilo, a všechny tři byly předtím v repu napsané jinak: `lsregister -u`
vrací **nenulu i nad cestou, která v databázi vůbec není**, takže jeho návratový kód o úspěchu
nemluví (rozhoduje druhý výpis) — první verze kvůli tomu hlásila poplach nad kopií, kterou `run.sh`
odregistroval o minutu dřív. **Na pořadí „napřed odregistrovat, pak smazat“ nezáleží** (od #250 to
byla podmínka): registrace smazání bundlu přežije a `-u` nad neexistující cestou funguje.
A `PlistBuddy` píše chyby **jednou na stdout, jednou na stderr** podle druhu, takže filtrovat je
podle textu je slepá cesta — identifikátor se bere jedině při nulovém návratovém kódu; ta vada
ležela v `run.sh` od #88 a znamenala nesmyslnou hlášku o cizím bundlu.

U domény platí totéž zpětné čtení: `defaults delete` vrací nad neexistující doménou **nenulu**
a po sobě nechá **prázdný plist** (42 B), na kterém `defaults read` už tvrdí, že doména neexistuje.
Maže se proto obojí a ověřuje se čtením, ne kódem.

**Skripty mají poprvé testy v harnessu** (`Tests/Scripts/`, 20 testů): že se bez slotu neuklidí nic
(ani se nevypíše hlavička), že se maže jedině cesta složená ze slotu (tvrzeno nad zdrojákem, jako
`SingleWayOutTests`), že doména i prázdný plist zmizí, a že zaniklý záznam jde pryč, kdežto
existující bundle zůstane. Obě chybové větve se **pouštějí** (`PRISM_LSREGISTER` na neexistující
cestu a na `/usr/bin/false`), regrese na přeskakování existujících cest se ověřuje proti záznamníku
místo `lsregister` — bez toho `if`u by odregistrovala hlavní aplikaci. Testů 3582.


**Odznak v railu a kapsle stavu podle návrhu (issues #366 a #348).** Dvě odchylky aplikace od toho,
co v mockupu **už nakreslené je** — tedy bez schvalovací brány, jako #283.

Odznak s počtem byl fialový akcent posunutý o 6 bodů **za** rám ikony, návrh (`.rail .ri .badge`) má
červený uvnitř rámu. Akcent v tomhle okně znamená „tady jsi“ (`.ri.on` je z něj celý), takže odznak
v téže barvě neříkal nic; `--crit` je „je co dělat“, což počet ve frontě přesně je. Rozměr se
**změřil na vyrenderované sekci 02**, ne odhadl z CSS: `min-width: 14px; height: 14px` je v návrhu
**obsah** (dokument `box-sizing` nikde nepřepisuje), takže s odsazením 3 a obtahem 2 vyjde odznak
**24 × 18** a v bitmapě je z toho červená plocha 20 × 14. Text je v barvě plochy okna (`--panel`),
ne bíle — kontrast **5,36** ve světlém a **5,50** v tmavém režimu proti 3,35, které by dala bílá na
světlé červené, a proti **3,27**, na kterých byl dosavadní bílý text na akcentu v tmavém režimu.
Co **zůstalo**: nula se nekreslí a `nil` se od nuly liší.

Kapsle stavu v hlavičce karty popisu byla `11 bez mono`, návrh má `.pill idle`, tedy **mono 10,5**.
Sazba se svedla do `designPill(tint:background:)`, protože ta metrika žila v **sedmi** kopiích a šest
z nich bylo shodných do bodu — rozejít se může jedině to, co je zapsané víckrát. Šířku z ní teď bere
i měření (`TextWidth.pill(_:)`), stejně jako `TextWidth.miniButton` bere řez z `MiniButtonStyle`.
Mono stojí **4 až 9,4 bodu** na šířku (naměřeno na čtyřech stavech PR) a je o **bod nižší** (řádek 12
proti 13), takže hlavička nemůže povyrůst; přetečení hlídá `OverviewWidthTests` v pásmu 128–1180.

**Zbylá část třídy se vědomě odložila** (#404, dotažené později): pět dalších kapslí v okně mělo
v návrhu `.pill` a v aplikaci nemono sazbu — `ReviewStateBadge` (`.caption`, 6/2), pilulky nálezů ve
`FindingCardView`, `FindingTableRowView` a `FindingBubbleView` (`.caption2`, 5/1) a odznaky
v `ThreadBubbleView` a `ConversationEntryView` (10,5 bez mono, 6/1). Jsou to **tři jiné metriky na
pěti obrazovkách** a jedna z nich sedí v bublině, jejíž výšku si blok kódu měří sám (#236), takže by
se do jedné vizuální pauzy neposoudily.

**Z review na #406 přišly dva reálné nálezy a oba jsou opravené.** Kapsle měla řez zapsaný dvakrát
— AppKit `NSFont` na měření a SwiftUI `.system(size:weight:design:)` na kresbu. Metrikou to bylo
totéž (`.AppleSystemUIFontMonospaced-Semibold`, `otevřený` 51,926 v obou), ale dvě specifikace
jednoho řezu jsou přesně ta třída chyby, kvůli které `TextWidth` vznikl (#284), takže se kreslí
`Font(DesignPill.font)`. A guard nad zdrojáky znal jen SwiftUI podobu zápisu, tedy minul
`monospacedSystemFont(ofSize: 10.5, weight: .semibold)` — což je zrovna tvar, který
`SinceLastVisitView` do #348 doopravdy mělo; hlídá teď obě a ověřeno je to vloženou regresí zvlášť
pro každou.

**Barva se v testu porovnává s nakreslenou, ne s tokenem**, a je to změřené: bitmapa
z `bitmapImageRepForCachingDisplay` je v profilu displeje, takže `crit` v ní vyjde
`0.799/0.292/0.272` proti `0.812/0.133/0.180` v sRGB — na absolutní porovnání by tolerance musela
být tak velká, že by prošel i akcent. Tokeny se proto kreslí **týmž harnessem** jako vzorník.
Ověřeno vložením regrese ze dvou stran: se starým odznakem padne 5 testů ze 6, a se samotným
`offset(x: 6, y: -2)` (červená ponechána) padne tvrzení o poloze na `46 > 43`. Testů 3594.

### #409 — klik na notifikaci nic neotevřel

**Na tomhle je co vidět, ale ne ve slotu**: `bin/slot-config.sh` čistí konfiguraci od notifikací,
takže se ve slotové aplikaci skutečná notifikace nedá vyrobit. Doloženo proto testy, ověření
v hlavní instanci zbývá na člověka (v nastavení povolit notifikace, nechat doběhnout review nebo
počkat na nové PR ve frontě a na banner kliknout — má se otevřít záložka toho PR a okno se na ni
přepnout).

Obsluha kliknutí nastavovala **jedině `selection`**, tedy stav, který od záložek (#180) v domácí
záložce nikdo nekreslí: `activeTab` zůstal na `.home`, žádná záložka nevznikla a výsledek byl
„aplikace naskočila a nic“. Byla to **regrese od #180** — obsluha je z #82–#88, kdy výběr řádku
otevření byl.

**Otevírání PR má od téhle změny jeden vstupní bod**: `AppStore.openTab(_ pr: PRIdentifier, in tab:
PullRequestTab? = nil)`. Jsou to totiž dva zápisy (`openTabs` a `activeTab`), takže „otevřít PR“ se
dá provést napůl — a přesně to se stalo. Volitelný `tab` je tam proto, že skok na nález nebo na
řádek dění nemá nad zavřenou záložkou kde přistát; do #409 to skládala paleta ⌘K vlastní privátní
metodou (`show(_:in:)`), která tím zmizela. **Použije ho i #414** (sekce `Dění`), aby klik na řádek
vedl do konkrétního tabu tou samou cestou jako klik na notifikaci. `tab: nil` uloženou volbu
**nepřepisuje** — klik na notifikaci tab nejmenuje, protože proud kliknutí nese `PRIdentifier`, ne
událost, takže by ho vybíral naslepo.

**Vlastní PR se nerozlišují.** Notifikace se o nich hlásí jedině o cizí aktivitě (#335), ale klik na
starší notifikaci může přijít na PR, který se mezitím do sekce `Moje PR` (#331) přesunul — a záložka
je na sekci railu nezávislá, protože obsah si bere z plného seznamu. Zúžení podle autora by tady
znamenalo zahozený klik za nic.

**Rozhodování je v `Policy.notificationClick(on:listed:visible:status:)`**, ne `if`y v obsluze
proudu, a zůstává v něm obojí, co obsluha řešila správně: PR mimo seznam se neotevírá naslepo
(výjimka je `notStarted`, kvůli kterému má proud buffer) a filtr, který PR schoval (#117), se ruší.
Cena za tu výjimku je, že do prvního tiku stojí v záložce hláška „Pull request zmizel ze seznamu“;
druhá varianta — čekat s otevřením na tik — je klik, po kterém se nic nestane, tedy zrovna to, co se
opravovalo.

**Ta zajímavější polovina issue jsou testy.** Čtyři testy na klik tvrdily `store.selection == pr`,
tedy přesně to jediné, co obsluha dělala: zelené byly právem a o tom, co uživatel vidí, neříkaly
nic. Přepsaly se na `activeTab` a `openTabs` a přidaly se tři případy, které nebyly vůbec (uložený
tab se nepřepisuje, filtr se ruší, vlastní PR se otevře). Ověřeno vložením regrese ze dvou stran:
`selection = pr` místo `openTab(pr)` složí šest testů ze třinácti v suitě (staré čtyři by prošly)
a `Policy`, která vrací `open` vždycky, složí test „klik na PR mimo seznam neotevře nic“ i čtyři
případy v `NotificationClickTests`. Testů 3724.

### #414 — Dění: pátá sekce railu, ve které notifikace zůstane

Notifikace proletí a nikde nezůstane. Banner zmizí, stejná identita přepíše to, co ještě visí (#87),
a v okně po tom zbude **jediný údaj**: čas posledního doručení u zvonku ve stavovém řádku (#138).
`Dění` je místo, kde ty události zůstanou — pátá sekce railu, na kterou ikona `◷` v návrhu čekala od
sekce 01. Zakreslené v **sekci 27**, odsouhlaseno 2026-08-23.

Podrobnosti — kdo drží záznam, co ho vyprazdňuje a jak se rozhoduje o řádku — jsou
v [`architektura.md`](architektura.md), sekce *Dění — pátá sekce railu (#414)*. Tady zbývá to, co se
rozhodlo **jinak, než bylo v zadání nebo v zákresu**.

**Osm druhů, ne šest.** Zadání mluví o šesti; v `ActivityEvent.Kind` jich je osm, protože se `nové PR`
dělí na příchod a re-review (#137) a `review doběhlo` na nálezy, čisto a selhání. Liší se glyfem
i cílem kliknutí, takže by se jako jeden druh s příznakem kreslily stejně — a to je zrovna to slití,
kterému se v tomhle okně brání (`čisté review` proti `review se nepovedlo`).

**Zastaralé nálezy se zapisují z `loadDetail`, ne z tiku**, a je to vědomé omezení, ne opomenutí.
`PullRequestSummary` ze searche `headSha` nenese (`gh search prs` ho neumí), takže tikem by to šlo
jedině přes `gh pr view` na každé PR — tedy N+1 past, kvůli které se netahá ani detail, a zadání
nové síťové volání zakazuje. Rozchod se proto zapíše ve chvíli, kdy se na PR podívám nebo nad ním
něco poběží; **od té chvíle ale zůstane**, kdežto dneska je to žlutý proužek, který zmizí
s obrazovkou. Zbytek — všimnout si toho tikem — je na **vlastní issue**; je to nový zdroj, tedy tatáž
kategorie jako zamítnuté spadlé CI.

**Text řádku se ukládá složený.** Vypadá to jako uložené UI, ale řádek mluví o tom, jak review
dopadlo **tehdy**, a nálezy z té chvíle na disku být nemusí (zahodily se, uklidila je lhůta, přepsal
je další běh) — přepočítaný řádek by tvrdil něco o dnešku pod datem z minulého týdne. Skládají ho
**tytéž funkce jako banner**, takže se nad jedním během nemají čím rozejít.

Z toho plynou **čtyři odchylky od zákresu**, každá proto, že by data pro nakreslený text musela
vzniknout druhou cestou:

- **Nálezy** mají v detailu ten **nejzávažnější nález** (`correctness: …`), ne seznam skillů
  (`php-review, security-review`). Je to tatáž věta jako v banneru a nese víc.
- **Čisté review** detail nemá vůbec, kdežto zákres má `· 3 skilly · 1,04 $`. Detail odpovídá na „co
  potřebuju vědět nad titulkem“ a u čista je to nic; kolik skillů běželo a co to stálo je záznam běhu
  a je v tabu `Průběh`, kam ten řádek vede.
- **Re-review** nese titulek PR, ne `od mého review přišlo 5 commitů`: ten počet by znamenal dopočítat
  commity od cizího review, a to z fronty ani ze snímku neplyne.
- **Cizí aktivita** má v detailu celý počet (`2 nové komentáře a 1 review`), ne jeho druhou půlku
  (`a 1 review od Copilota`). Skládá ho `Policy.activityHeadline`, tedy tatáž funkce jako titulek
  banneru — druhá věta o témž počtu by se s ní rozešla.

**Svislá čára osy jde středem puntíků, ne 4 body vedle.** V CSS zákresu se ty dvě hodnoty
rozcházejí: `.tl::before` je na `left: 30px` od hrany `.tl` (tedy střed 31), kdežto `.tl-dot`
vychází na `18 + 5` s průměrem 24, tedy střed **35**. Spočítáno z CSS, ne odhadnuto z obrázku.
V aplikaci mají obojí střed na 30, protože čára pod puntíkem je zjevně to, co zákres kreslit chtěl —
osa vedle puntíků vypadá jako chyba kreslení.

**Prázdna jsou čtyři, ne dva.** Zákres kreslí klid a zakázané oprávnění; přibyl **vypnutý přepínač**
v nastavení aplikace (bez něj by vypadal jako odmítnuté oprávnění a posílal člověka do Nastavení
systému, kde s tím nic neudělá) a **ztracený záznam**, který přebíjí všechny ostatní. Ten poslední je
z nich nejdůležitější: rozbitý soubor i prázdný záznam dají obojí prázdný seznam, takže by nad
ztracenou historií stálo klidné „za poslední dny se nic nestalo“ — přesně ten text, který tvrdí víc,
než data unesou. Chybějící soubor se od nečitelného odlišuje **dřív než dekódováním**, protože první
spuštění je normální stav, ne porucha.

**Odznak se na aktivní sekci nekreslí** (poznámka 95 v zákresu), a je to obejití vady dnešního railu:
odznak v něm ikonu **překryje**, takže by na položce, ve které zrovna stojím, zbyl červený puntík bez
identity. Počet je proto v nadpisu bloku. Ta překrytá ikona zbývá jako vlastní issue.

**Klik jde vstupním bodem z #409** (`openTab(_:in:)`) a **tab jmenuje** — řádek dění ví, o čem je.
Jediný řádek, který do okna nevede (PR odešel z fronty, takže v seznamu není), vede na GitHub a pozná
se to i barvou.

**Na tomhle je co vidět**, a do plné sekce se klikáním nedostaneš: čerstvá cache dění nemá. Pro
screenshot se zapíše `activity.json` do cache slotu a značka do jeho domény v `UserDefaults`; postup
je v [`testovani.md`](testovani.md). Testů 3791 (67 nových).

### #412 — diagnostika se vypínala sama: strop se počítal napříč sezeními

Diagnostika kreslení (#361) se po pár hodinách přestala zapisovat, a to zrovna při tom, na co je.
Naměřeno v provozu: záznam narazil na strop 8 MB v `2026-08-22T04:01:36` a dalších **42 hodin**
aplikace běžela bez záznamu — kdyby v nich záchvat byl, nevíme o něm nic. Kořen nebyla velikost
stropu, ale to, že platil na **soubor**, do kterého se přípisovalo napříč sezeními: při restartu ve
12:34 zbývalo 3,5 MB, tedy necelých sedm hodin, a restartuje se po každém mergi.

**Sezení má od teď svůj soubor.** Dosavadní záznam se při startu uloží vedle jako
`diagnostics-do-<čas posledního zápisu>.log` a nové sezení začíná prázdné. Jméno je z času posledního
zápisu, ne z času rotace — soubor ze pátku má mít v názvu pátek i tehdy, když se aplikace spustí
v pondělí; sekundy v něm jsou proto, že se restartuje šestkrát denně. Drží se **dvacet souborů a
64 MB** (dvě meze, každá na jinou poruchu) a **nejnovější se nemaže nikdy**, ani nad bajtovou mezí:
u #361 se čte zpětně, takže rotace, která zahodí historii, je horší než strop. Maže se **jedině podle
vzoru jména**, protože v kořeni cache leží i nálezy, drafty a `sessions.json`.

**Co rotace udělala, je napsané v záznamu** — kam se uložil předchozí, co se smazalo, co se nepovedlo.
Je to tatáž úvaha jako u limitního řádku z #386: soubor, který začíná od nuly, se nedá odlišit od
aplikace, která o předchozím sezení neví. Rotace přitom sedí **uvnitř otevírání souboru**, ne
u volajícího: jinak by log s otevřeným deskriptorem po přesunu zapisoval do archivu, a to potichu.

**Klid se sráží do minutového souhrnu** (`za 61.00 s klid: 57 úseků, 235 kol runloopu, 0.366 s CPU,
1 bez kola runloopu`). Změřeno nad skutečným záznamem z provozu (985 754 B, 11,5 h): úseků bez
průchodu tělem a bez hoření bylo **9 279 z 10 077** — 89 % hlavních řádků a 60 % objemu —, a **ani
k jednomu** z nich nestála příloha o grafu, takže se folding nemá čím dotknout toho, na co je záznam.
Kola runloopu už o „klidu“ nerozhodují (nečinné okno má 1–4 za sekundu, takže neodlišovala práci od
spánku) a **sečtená jsou v souhrnu**. Záchvat se pořád zapisuje **po sekundách** i s náběhem, a souhrn
jde **před** ten řádek, který klid přerušil, ať časy jdou vzestupně. Mezera v souboru tím zmizela
úplně, a to je vlastnost, ne kosmetika: do #412 se nedala odlišit od nástroje, který se vypnul.

**`bin/run.sh` nad plným záznamem už nekončí `exit 1`** — aplikace si ho odloží sama, takže odmítnout
start by znamenalo mazat rukou to, co má dělat aplikace. Hlášení zůstává: velikost předchozího
záznamu, věta o tom, že mu chybí konec, a počet uložených záznamů.

**Na tomhle není co vidět** — je to soubor v cache, obrazovka se nemění. Ověřeno spuštěním dvakrát za
sebou (`PRism-c`): 848 B předchozího sezení leží jako `diagnostics-do-2026-08-24T10-02-02.log`, nový
soubor začíná hlavičkou a řádkem `předchozí záznam (848 B) uložen jako …`, a za 70 s má **11 řádků
místo ~66**. Testů 3813 (22 nových), dvě z nich ověřená vloženou regresí. Z Copilot review přišel
jeden reálný nález: komentář tvrdil, že symlink pojmenovaný jako záznam se smaže („neškodně, smaže se
odkaz“) — sondou se změřilo, že `resourceValues` odkaz **nerozbaluje**, takže se do úklidu vůbec
nedostane. Chování zůstalo (bezpečnější strana omylu), komentář se přepsal na změřené a přibyl na to
test.

### #417 — sheet s logem a s hunkem se otevíral 560 bodů široký

Druhý výskyt třídy z #327: bez `presentationSizing(.fitted)` SwiftUI u sheetu **zahodí `idealWidth`**
a zbyde `minWidth`. U textu, jehož jediné téma je šířka, to byla ta nejhorší možná odpověď — 66 znaků
na řádek, z nich 29 sní timestamp, a 68 % řádků logu se lámalo. Zakresleno v sekci 28 návrhu, protože
tahle obrazovka v mockupu nakreslená nebyla; celé měření i rozhodnutí jsou v
[`architektura.md`](architektura.md), sekce *Sheet s kódem a s logem*, a ve specifikaci.

Co je na tom jiné než u #327: **jeden sheet, dva profily velikosti** (hunk 1 180 × 520 s podlahou
560 × 320, log obrazovka − 152 nejvýš 2 700 × 760 s podlahou 820 × 420) a **dva klíče** pro uloženou
velikost — s jedním by roztažení logu přes monitor otevíralo takhle i hunk o devíti řádcích.
Rozhoduje o tom čistá funkce `Policy.codeSheetSizing(kind:screen:)`, druh nese `CodeText`.

**Hlavička má tři řádky, akce jsou v patičce.** U logu má třetí řádka dvě podoby: u běžícího jobu
snímek s časem, u doběhlého `log je celý, nic už k němu nepřibude` — doběhlému jobu se log snímkem
nazývat nemá. ANSI se z logu sundá, **timestampy zůstávají** (29 znaků = 240 bodů šířky, ale sheet je
ta obrazovka, kde se člověk ptá po úplném textu) a připravuje se to **při stažení**, ne při kliknutí.

**Dvě věci se cestou vyloučily měřením**, ať to příště nikdo nezkouší znovu. Stráž v `updateNSView`
vypadala jako nutnost (tažení přeměřuje plochu, přesázení ruší výběr) — za patnáct kroků tažení
skutečného okna přišlo `updateNSView` **nula krát**, takže by ji nešlo ověřit vloženou regresí a v repu
není. A **tučné zvýraznění uvnitř třetí řádky** se nekreslí: uživatelské texty jsou `Text(verbatim:)`
a markdown by u jména jobu s podtržítkem začal kurzívovat.

**Na tomhle je co vidět**, ale k sheetu s logem se klikáním nedostaneš, kdykoli chceš — chce to PR se
spadlým checkem. Vedle skutečné aplikace je proto sonda `CodeSheetRenderProbe`, která oba druhy
vyrendruje v obou režimech. Testů **3832** (41 nových proti 3791 u #414), plný běh zelený.

### #422 — trvalé vodorovné pruhy v diffu vedle sebe (a rolování, které tam nebylo)

Ve splitu se nezalamuje (#157), takže dlouhý řádek odjede za okraj sloupce — a nebylo z čeho poznat,
že tam pokračuje: plochy měly `scrollerStyle = .overlay`, který se kreslí jen během rolování.
Stížnost je změřená (**64,5 %** řádků diffu je delších než 22 znaků, což je právě to, co se ve
výchozím okně s otevřenými panely do jedné strany vejde) a zakreslená v **sekci 29** návrhu.
Vydáno tak, jak to zákres kreslí: **legacy scroller pod každou půlkou**, autohide zapnutý, unified
beze změny.

**Hlavní nález je jinde než v zadání: rolovat se tam nedalo vůbec.** Issue předpokládalo, že posun
funguje odjakživa a chybí jen vidět. Změřeno, že ne — `DiffTextView` kreslí čísla řádků v gutteru
**uvnitř** textového view (text začíná na 84 b), kdežto AppKit počítá šířku dokumentu z `usedRect`,
který o gutteru neví: `sizeToFit()` vracel **nulovou** šířku a `isHorizontallyResizable` navíc srazil
rámec nastavený kontejnerem zpátky na šířku okýnka vždycky, když se do ní vešel samotný text (sloupec
s 12 znaky v šířce 129,5 b kreslí text do 190,4 b a dokument z toho vyšel 129,5). Dokument tedy nebyl
nikdy širší než plocha; s autohide by z celé změny vyšel pruh, který se **nezobrazí nikdy**. Šířku
proto od #422 určuje ten, kdo kreslí (`DiffTextView.naturalWidth`), self-sizing je vypnuté a hodnota
se pamatuje (39,6 ms na 54 stran spočítat, 0,003 ms z paměti).

**Druhé kolo: `usedRect(for:)` na celý kontejner byla špatná míra** — nahlášené při zkoušení jako
„moc velký posuvník, který jede do prázdného místa, kde nic není“. `usedRect` totiž umí zahrnout
**extra line fragment**, tedy řádek za posledním `\n`, který AppKit vysází vždycky, když text končí
zalomením — a tak končí každá půlka, jejíž poslední řádek je prázdný, což je každá **šrafovaná**
(chybějící) strana dvojice. Kontejner sloupce je neomezeně široký, takže má ten fragment rámec
**10 000 000** bodů: půlka se třemi šrafovanými řádky si řekla o dokument 10 000 084 bodů proti
okýnku 449,5, tedy `knobProportion` **4,49 × 10⁻⁵** (po opravě 0,0 — šrafovaná půlka pruh nedostane
vůbec). Odsud ten vlas u levého okraje a rolování do prázdna. **Kdy se fragment započítá, se řídit
nedá** (nad samotným sloupcem 34,1, nad tímtéž sloupcem v kontejneru 10 000 000) — odsud to
„někdy“. Šířka se proto počítá **výčtem vysázených
fragmentů** té půlky (`enumerateLineFragments`), který extra fragment nevydá vůbec; nad blokem
s neprázdným posledním řádkem vychází **týž počet jako dřív**, takže odsouhlasená geometrie se
nemění. Cena 0,005 ms na šedesátiřádkovém bloku (proti 0,0001 ms), platí se jednou na obsah. Výška
zůstává na `usedRect` schválně: tam je ten fragment skutečný řádek bloku.

**Výška bloku začala záležet na šířce, a to je ta past.** Pruh dostane jen blok, který má co skrývat,
takže rezervovat jeho 17 bodů musí **totéž místo, které o pruhu rozhoduje** —
`DiffPairBlockContainer.showsScroller(forWidth:)` a `height(forWidth:)`, pravidlo z #236. Kritérium je
navíc totéž, podle kterého se rozhoduje AppKit (`naturalWidth > šířka poloviny`), takže se nemají jak
rozejít; ptát se plochy za běhu nešlo, protože výška se musí znát **před** layoutem. Ověřeno vloženou
regresí: bez rezervace padne **108 tvrzení** a je mezi nimi `rows 98 <= 83`, tedy text pod pruhem.

**Pás se rezervuje na blok, ne na půlku.** Když pruh potřebuje jen jedna strana, má druhá v tom pásu
prázdno — vzniká to samo tím, že `NSScrollView` bere pás zespodu a clip view zůstává nad ním
(změřeno: plocha 200 b vysoká hlásí `contentSize` 183 a scroller na `y: 183`). Prázdnou stranu dvojice
u toho drží prázdný řádek (`DiffLine.blank`), ne minimální výška, takže rámečky obou půlek vyjdou na
bod stejné.

**Styl drží vlastní podtyp** (`DiffPairScrollView`), protože `scrollerStyle` je hodnota, kterou si
`NSScrollView` srovnává se systémovou volbou *Zobrazovat posuvníky* — setter proto vede zpátky na
`.legacy`, getter zůstává `super` (lhoucí getter by znamenal, že se plocha tiluje podle jedné hodnoty
a čte podle druhé). Systémové nastavení se u toho **nepřebíjí**: mění se ty dvě plochy, ne aplikace.

**Co se nemění:** čísla řádků odjedou s textem (nakreslené je to tak i v návrhu, poznámka 45)
a pohled pod sebou zůstává zalamovací — je na to vlastní sada testů, protože je to volba ze tří
možností, ne opomenutí.

Testů **3827** (14 nových, z toho jedna sonda na kresbu). Vloženými regresemi ověřených pět věcí
a každá padá jinde: bez rezervace výšky 108 tvrzení, se vráceným `sizeToFit()` 348 (z toho 182 na
nedosažitelném konci řádku), s overlay stylem 58 — a `predictionMatchesAppKit` z nich neselže ani
jedním, protože overlay se hlásí jako viditelný a nekreslí nic. Ze druhého kola: se `usedRect(for:)`
zpátky **244 tvrzení** (u šrafované půlky `10000084.0 <= 94.0`) a bez zahození zapamatované šířky
při změně obsahu **7 tvrzení** na recyklaci kontejneru — krátký blok tam zdědí po dlouhém 1701,2
místo 102,0.

### #428 — vodorovný pruh jede s výřezem

Pruh z #422 sedí na dolní hraně bloku, a ta je u dlouhého bloku pod dolní hranou okna: uživatelovými
slovy *„když je ten soubor se změnou moc dlouhý a já chci zkontrolovat něco nahoře, tak musím dolů…
posunout a nahoru“*. Změřeno, koho to potká — přes viditelnou část diffu (448 b) přeteče **9,6 %**
bloků (33 ze 343 ze 48 mergnutých PR) a jejich pás leží pod hranou okna o **229 b** (medián, p90
i nejvíc 533); v menším okně (400 b) je to 11,7 %. Zakresleno v **sekci 30** návrhu, vydáno tak, jak
to zákres kreslí.

**Celé pravidlo je jedna věta:** `y = min(vlastní pás, hrana výřezu − 17)`, tedy jedna spojitá funkce
posunu, ne dva stavy. Dokud blok hranu výřezu přesahuje, stojí pruh **na ní** a jeho poloha v okně se
rolováním nemění; jak se pás bloku do výřezu dostane, pruh v něm přistane a jde dál rychlostí kódu.
Přechod není animace — vyjde z toho minima sám. Rozhodnutí je čistá funkce
(`Policy.pinnedScrollerY`), takže se dá projet vyčerpávajícím výčtem i průjezdem po jednom bodu.

**Otázka „komu pruh patří“ se rozpustila, nerozhodovala se.** Pruh nikdy neopustí svůj blok, takže na
hraně výřezu může stát nejvýš jeden — ten, který k ní dosahuje —, a blok, jehož pás už je vidět, má
pruh ve svém pásu. Rozhodnutí #422 (pruh na blok a na půlku) zůstalo nedotčené.

**Prvků navíc nula, pozorovatelů jeden na blok.** Je to tentýž `NSScroller`, jen jinde nakreslený:
mění se mu `frame.origin.y`. Pozorovatel sedí na `boundsDidChange` **vnějšího** clip view (půlky se
při rolování nehýbou, hýbe se výřez) a jeho obsluha je aritmetika a dva zápisy rámců — nula zápisů do
observable stavu, protože zpětná vazba z každého snímku, která píše do stavu, zavírá kolo (#252,
#358). Změřeno: dvacet posunů po deseti bodech nepřidalo **ani jeden** průchod tělem, `updateNSView`,
nasazení bloku ani sazbu.

**Souřadnice se počítají v ploše sloupce**, a to je celý trik: `NSScrollView` **je flipped**
(změřeno) a plocha je vysoká jako celý blok, takže její `bounds` je rámec bloku s nulou na horní
hraně — přímo soustava, ve které se výsledek zapisuje scrolleru do rámce. Zapisuje ho **jedno
místo** a znovu se uplatní v `tile()`: rozvržení plochy scroller vrací na dolní hranu (změřeno,
z 183 na 283), takže zápis odjinud by po první změně šířky okna zmizel.

**Výška bloku se posunem nemění** — rezervace 17 b zůstala tam, kde ji #422 nechalo. Alternativa
„ubrat výřezu 17 b, dokud dlouhý blok sahá na hranu“ je zamítnutá v zákresu: inset, který přichází
a odchází, hýbe veškerým kódem pod kurzorem. Připíchnutý pruh proto kód **zakrývá** (17 b = 1,06
řádku, prakticky ten řádek, který hrana okna stejně řeže).

**Jediná heuristika je pojmenovaná:** pod třemi viditelnými řádky bloku se pruh nepřišpendlí. Je to
jediné číslo v téhle změně bez měřidla a je vypsané i v zákresu (poznámka 53); druhé se k němu
nepřidávalo. Autohide zůstal beze změny, takže na hraně okna někdy nic nestojí — a je to správná
odpověď, ne chybějící prvek, protože pruh nemění vlastníka.

**Kresba pruhu se v harnessu ověřit nedá a je to změřené, ne odhad**: legacy scroller se do
`cacheDisplay(in:to:)` nekreslí (nad červeným dokumentem vyjde pod pruhem tatáž barva jako vedle
něj) a `CGWindowListCreateImage` na macOS 26 není. Testům proto zůstala čísla — poloha scrolleru
v okně, výška bloku, počty průchodů —, a jak to při rolování vypadá, posoudil člověk na běžícím okně.
Z toho jedna otevřená domněnka: **neprůhledný podklad** pruhu (poznámka 49) kreslí legacy drážka
sama, a kdyby přes ni kód prosvítal, je to jeden řádek na `layer` toho scrolleru, ne nový prvek.

Testů **3880** (12 nových: 8 nad čistou funkcí, 4 nad scénou s `ScrollView`em). Vloženými regresemi
ověřené tři věci a každá padá jinde: bez `min(…)` padne 400 tvrzení v průjezdu, 28 v okenní scéně
a *„blok celý vidět“* (pruh vyjede pod blok, `1073 <= 683`); bez rezervace pásu 114 tvrzení o výšce;
bez uplatnění polohy v `tile()` 29 tvrzení o hraně výřezu.

### #420 — zastaralých nálezů si všimne tik, ne až otevřené PR

Odložený kus [#414](#414--dění-pátá-sekce-railu-ve-které-notifikace-zůstane). Novinka *nálezy
zastaraly* v dění fungovala, jenže se zapsala teprve tehdy, když aplikace novou hlavu **poznala** —
při `loadDetail` nebo při běhu review. To je zrovna ten okamžik, kdy je rozchod vidět i bez dění
(hlavička nad taby ho říká), takže ta novinka nepřinášela nic. Zadání #414 přitom nové síťové volání
na tik zakazovalo, protože `gh search prs` `headSha` nenese.

**Rozhodla měřená věc, ne úvaha.** Zadání #420 dávalo tři možnosti a klíčová otázka byla, jestli se
dá `headRefOid` pro celou frontu vytáhnout **jedním** dotazem, ne jedním na repozitář (u téhle
instalace je jich devět až jedenáct). Dá: GraphQL bere víc aliasovaných kořenových polí v jednom
dokumentu. Změřeno na živém API — 12 aliasů z 10 repozitářů **1 bod z 5000/h**, 1,25–2,59 s, odpověď
1,9 kB; **24 aliasů pořád 1 bod**, 1,25–1,96 s, 4,9 kB. Cena je tedy v tom dotazu, ne v počtu PR,
takže dotaz na repozitář by byl desetinásobek volání za tutéž odpověď. Nejmenší varianta ze zadání
(nedělat to tikem a jen datovat řádek zpětně) prohrála právě na tom, že měření dovolilo víc.

**Co to přidá na tik: na klidný den nula.** Ptá se `Policy.staleHeadProbe`, a to jedině na **cizí** PR
(o vlastních se nehlásí, #332), na kterých leží **uložené nálezy** a kterým se od posledního dotazu
pohnul **`updatedAt`** — bez toho posunu se hlava nemá čím změnit. Prázdný seznam se nespouští, takže
z klidného tiku není ani podproces. V bouři je to **jeden** dotaz za tik (~60 bodů z 5000 za hodinu)
a strop 20 PR na dokument.

**Řádek nese čas vzniku hlavy, ne čas zjištění.** Dotaz si proto říká i o `committedDate` toho commitu
a datuje jím řádek; bez toho by po každém spuštění aplikace vypadalo, že práce z minulého týdne
zastarala dneska — a restartuje se po každém mergi. Stojí to `commits(last: 1)` v dotazu, tedy 0,94 s
→ 1,25–2,15 s (měřeno střídavě A/B/A/B, `cost` v obou případech 1). `oid` v odpovědi je kvůli ověření,
že poslední commit spojení je opravdu ta hlava (shodovalo se u všech dvanácti měřených PR); neshoda
znamená **datum nevíme**, ne datum cizího commitu. Datuje o tom `Policy`, ne volající: rozchod umí
najít dvě cesty a identita řádku je klíčovaná hlavou, takže by tentýž rozchod měl dvě data podle toho,
kdo si ho všiml první.

**Porovnání sha se nezdvojilo** — vytáhlo se z `AppStore.staleFindings(for:)` do
`Policy.staleFindings(of:head:)` a store si nechal jen to, odkud dnešní hlavu bere (detail). Dávkový
dotaz je **druhý zdroj té sha, ne druhá pravda o tom, co je zastaralé** (tvrdá podmínka č. 5).

**Dvě vědomé ceny.** Řádek z tiku **o commitech nemluví** (`hlava je teď <sha>`): počet by se dal
spočítat jen ze seznamu commitů, a ten se tahá s detailem — tedy zpátky ta `N+1` past. A řádek
nalezený se zpožděním padne do **svého** dne, takže se nepočítá jako nepřečtený; druhé razítko by
rozbilo invariant, na kterém stojí pruh `Tady jsem skončil` (nové položky jsou předpona seznamu).

**Nenulový návratový kód `gh` u dávky není selhání volání**, a je to změřené: dotaz na tři PR, ze
kterých dvě neexistují, vrátil data prvního, `errors` ke zbytku a kód 1. Ta odpověď je uložená jako
fixture (`pr-heads-partial.json`), protože podstatné je právě to, co `gh` udělá se stdoutem. PR, která
neodpověděla, v mapě **není** a razítko nedostane — „nevíme“ se nesmí zapsat jako „zjištěno“.

Na obrazovce se nemění nic: řádek je nakreslený od #414, jen se objeví dřív. Testů **3918**
(38 nových). Vloženými regresemi ověřené dvě věci: datování okamžikem zjištění shodí `Řádek nese datum
commitu, ne okamžik zjištění` (a s ním restartový test), dotaz po jednotlivých PR shodí `Za tik jde
jeden dotaz, ne dotaz na každé PR` s hláškou `(gateway.headRequests.count → 3) == 1`.

### #361 — desáté kolo: líný seznam měl dva zapisovatele, teď má jeden (otevřené)

**Poprvé se pracovalo z celého zásobníku hořícího kola, ne z re-armu.** Devátý záchvat
(2026-08-25, tab `Konverzace`, 58 s nad 0,9 s CPU) měl `ConversationRow.id` 7 109 970× a v `sample`u
dvě střídající se transakce: aktualizaci grafu (`LazySubviewPlacements.updateValue`) a **graf
mutation** `LazyLayoutCacheItem.AllItemsPhaseMutation` → `LazyLayoutViewCache.updateItemPhases()` →
`AG::Graph::value_set` → `propagate_dirty`. Ten `value_set` je **jediný externí zápis v celém
vzorku** — tedy ten `_External -> State, changed`, který instrumentace vypsala jako změněný vstup.

**Co se z toho dá opravit:** druhý zapisovatel do stavu líného seznamu. Pružný rámec nad
`ScrollView`em předává dolů všechny dotazy, kterými se stack ptá na pružnost dítěte (`nil`, `0`,
`∞`), a `LazyVStack` na každý z nich odpovídá funkcí `measureEstimates(**updatingPosition**:…)`,
tedy zápisem do téže měnitelné krabice, ze které kreslí `placeSubviews`. Naměřeno **29–33 dotazů** na
jedno rozvržení, z toho jen 4 se skutečnou velikostí; se změřeným rozměrem (`fillingSlot()`) zbydou
**4** celkem. Ta řada je v hořícím kole doopravdy: 1524 z 13 479 vzorků v devátém záchvatu, 4274 z 19 930
v sedmém — v obou tabech, takže to není vlastnost jedné obrazovky.

**Zamítnuto měřením, ne úvahou:** vyplnit pružnému rámci `idealWidth`/`idealHeight` (dotaz `nil`
zmizí, průzkum `0`/`∞` zůstane celý — 29 dotazů proti 29–33, tedy nic), a chybějící pojmenovaný prostor
u `frame(in: .named(DiffView.contentSpace))` v úryvku na ose (s prostorem i bez něj **přesně** 2000
výpočtů hodnoty a 0,072 s CPU, tedy k nerozeznání).

**#361 zůstává otevřené a je to poctivé, ne opatrnost.** Kolo se v harnessu nepovedlo vyrobit ani
podesáté (nečinné okno 0,000 s CPU ze 4 s i s 300 zalomenými řádky různých výšek), takže tvrdit
„už to netuhne“ nelze. Tvrdí se **vazba**: `LazyIdealSizeTests` říká, že se ten druhý zapisovatel
nemá kde vzít, a je to ověřené vloženou regresí. Ověření v provozu je používat aplikaci s
`./bin/run.sh --diagnose` a koukat do `diagnostics.log`.

Na obrazovce se nemění nic (změřeno A/B na běžící slotové aplikaci: diff, osa konverzace, strom
souborů i `Dění` mají stejné rozvržení před i po). Testů **3922** (3 nové).


**Zbytek nemono kapslí sjednocený s návrhem (issue #404).** Dotažení toho, co #348 vědomě odložilo:
pět míst, která návrh kreslí jako `.pill`, a aplikace je měla nemono. Zase jen srovnání s tím, co
v mockupu **už nakreslené je**, tedy bez schvalovací brány — jako #283 a #348. Od téhle změny si
`designPill(tint:background:)` bere **třináct souborů** (17 míst) a metrika zůstává na jednom.

Tři jiné metriky šly pryč: `.caption` s odsazením 6/2 u odznaku fronty, `.caption2` s 5/1 u pilulek
nálezů (karta, tabulka, bublina) a `10,5 bez mono` s 6/1 u odznaků v konverzaci. Odznak kontroly
v `FindingCardView` u toho přestal mít vlastní kopii sazby — byl to zrovna ten výskyt, který se
u #348 přehlédl.

**Odznak fronty potřebuje `lineLimit(1)` i `fixedSize()`, a je to změřené, ne odvozené.**
`lineLimit(1)` zalomení zabrání, ale místo něj **zkracuje**: bez `fixedSize` se v řádku o 320 bodech
srazily dva nejdelší stavy o **20 a 33 bodů**, tedy na `3 nález…`. Vyloučilo to i první podobu toho
testu — ta měřila jen výšku a procházela i s odebraným `fixedSize()`. Cena mono je tady 10 až
**48 bodů** (`timeout · 2 · 1 blokuje` 116 → 164), takže se měří v řádku, ne na kapsli samotné:
`fittingSize` odpoví tou šířkou, kterou hostujícímu view někdo dal, kdežto o skutečnou se odznak
pere s titulkem PR. Kapsle v **tabulce** `fixedSize` naopak nedostala — sedí ve sloupci se
spočítanou šířkou (92 bodů, nejdelší popisek `irelevantní` 86).

**Výška vyrostla o bod** (15 → 16), na rozdíl od #348, kde o bod klesla: tam se srovnávalo se
systémovými 11 s odsazením 2, tady s `.caption2` s odsazením 1. V pruhu se značkou u bubliny nálezu
je kapsle to nejvyšší, takže výška pruhu je z ní — hlídá se stropem nad dvěma bublinami nad týmiž
daty, s kapslí `blokuje` a bez ní.

**Kontrast se měřil z bitmapy, ne z tokenů** (#393, #366), a **našel mezeru, kterou #404
neopravuje** (vyřídilo ji #432):
čtyři kapsle berou systémovou zelenou a červenou a ve světlém režimu jsou pod třemi — `vyřešeno`
**1,63**, `schválil` **1,70**, `vyžádal změny` 2,52, `3 nálezy · 1 blokuje` 2,70. Škálu drží
`ReviewStateAppearance`, jehož vlastní zdůvodnění z #309 říká, že převod zbytku na tokeny je jiná
otázka, která se zodpovídá měřením; je tedy změřená a zapsaná, a do vyřízení se hlídá, že se
nezhorší. Kapsle na paletových tokenech jsou 2,91 až 4,08 ve světlém a 4,16 až 6,47 v tmavém.

**Dvě věci se pojmenovaly tokenem, aniž by se změnil vzhled.** Odznak `já` dostal barvu textu
`Palette.ink` (do #404 dědil `primary`, a `labelColor` je poloprůhledná — tatáž past jako u textu
diffu, #393) a jeho wash se změnil z `.tint.opacity(0.18)` na `Palette.accent.opacity(0.18)`.
V okně je to **tatáž barva**, protože `.tint` se na kořeni nasazuje jako `Palette.accent` — ale mimo
okno dědění padalo na systémovou modrou, což je zrovna ta záměna, kterou řešila #309 u odznaku `2×`.
Kontrast `já` je **12,27 / 8,40**, a má vlastní tvrzení: společný práh by výměnu `ink` za `ink3`
nechytil.

**Dvě věci se vědomě nesjednotily.** `Bot` v konverzaci zůstává nemono, i když ho tabulka v #404
vyjmenovala: návrh ho kreslí jako `.tl-line .botchip` (`font-size: 10px`, **žádná `font-family`**),
tedy schválně nemono, ze stejného důvodu jako `.state-chip` v hlavičce PR — je to vlastnost účtu
vedle avataru, ne stav ani počet. A `⚠ blokuje` v kartě nálezu zůstává `Label` s ikonou: kapsle to
není (nemá plochu), takže převod by znamenal zahodit tu ikonu, a to je změna obrazovky, ne sazby.
Obojí patří do téhož issue jako barvy.

Testů **3879** (10 nových a jedna sonda, která kreslí všech pět míst na jedno plátno v obou
režimech). Vloženými regresemi ověřené dvě věci: odebrané `fixedSize()` srazí odznak o 20 a 33
bodů, a vrácená ruční sazba `vyřešeno` v `ThreadBubbleView` shodí guard nad zdrojáky.

### #413 — nový label se zakládá z nabídky, druhým krokem

Zakreslené v **sekci 26** návrhu a odsouhlasené. Nabídka za `+ label` byla od #392 uzavřená
doopravdy: nesla jedině labely, které repozitář zná, protože z volného textu se dá omylem vyrobit
label a ten už z repa sám nezmizí. Cena za to byl odskok do prohlížeče kvůli jedinému štítku — tedy
zrovna ten odskok, kvůli kterému #392 vzniklo.

**Mění to dvě tvrdé podmínky naráz a obojí je zapsané v `CLAUDE.md` i s důvodem.** Podmínka č. 1
dostala **sedmou** metodu `ReviewPublishing` (`createLabel`), a je to **první, která zapisuje do
repozitáře, ne do PR**: předchozích šest sahalo na věc vratnou jedním klikem nebo takovou, která se
zavřením PR přestane týkat čehokoli dalšího, kdežto label vzniklý omylem zůstane v repu navždycky.
`deleteLabel` se **nepřidá** — smazaný label zmizí ze všech issues a PR, na kterých leží, a aplikace
tu ztrátu neumí ani ukázat; `SingleWayOutTests` ho hlídají jmenovitě vedle `merge`, `close`, approve
mimo review a milníku. Souborů zůstává **šest**: zakládání je sedmá **metoda**, ne pátý volající.

**Podmínka č. 5 (jedno atomické volání) pro tuhle jednu akci neplatí.** `POST /repos/{repo}/labels`
a `PUT /issues/{n}/labels` se spojit nedají, takže existuje stav *label v repozitáři je, na PR není*.
Zamítnuté bylo **samotné `Založit`** bez přidání: atomické by bylo, ale v devíti z deseti případů by
po něm musel následovat klik na řádek v nabídce, tedy krok navíc za čistotu, kterou vidí jen
dokumentace. Výjimka se proto platí viditelností: vlastní stav `createdNotAdded(name:error:)` (ne
`failed`, které by tvrdilo, že se nestalo nic), zápis založeného labelu do nabídky **ještě před**
druhým voláním (bez něj by řádek do restartu nebyl, protože `loadRepositoryLabels` se podruhé neptá),
`dvě volání` v patce potvrzení a zákaz pustit mezi voláními cokoli dalšího.

**Uzavřený zůstal seznam, ne nabídka.** Řádky nesou dál jen labely repozitáře a `↵` na vybraném pořád
jen přepíná; založení je akce **pod děličem**, mimo dosah šipky dolů — jako řádek v seznamu by z ní
byl nejpravděpodobnější omyl v celé obrazovce. Zkratka je **`⌥↵`** a bere ji **pole**, ne okno: `⌘↵`
je v tomhle okně obsazená dvakrát (paleta ⌘K, potvrzení odeslání review) a #184 už jednou popsalo, že
vyhraje ta zaregistrovaná později. Obsluha je **jeden** `onKeyPress(keys:)` s modifikátorem čteným
z `KeyPress`, protože `modifiers` je množina, ve které stisk **smí** ležet, ne která musí sednout
přesně — dva zápisy by se přebíjely.

**Akce zmizí, když label toho jména existuje**, a shoda se posuzuje **týmž pravidlem jako hledání**
(`Policy.pickerSameName` nad `searchOptions`), takže `Bug` se nezaloží vedle `bug`. Nabídne se naopak
i tehdy, když seznam něco našel — `bug-ui` v repu, které zná `bug-ui-legacy`: podřetězec není tentýž
label. Pět důvodů, proč se akce nekreslí, drží **jedna** funkce (`Policy.newLabelOffer`); pátý přibyl
při implementaci a v zadání nebyl — **nenačtená nabídka**, protože bez seznamu z repa není proti čemu
hledat duplikát, takže by `Bug` prošlo vedle `bug` jen kvůli nedotažené odpovědi.

**Barvu vybírá aplikace podle jména** z šestnácti odstínů, které GitHub nabízí ve svém dialogu nového
labelu, a **posílá se vždycky**, aby náhled nelhal. Počítá to vlastní FNV-1a, ne `hashValue`:
Swiftové hashování je zaseté náhodně **při každém spuštění procesu**, takže tentýž label by po
restartu vyšel jinak a „podle jména“ by bylo „podle náhody“. Vzorník je zamítnutý — ve 300bodovém
popoveru je to třetí prvek, který si říká o šířku, kvůli hodnotě, na kterou se člověk podívá jednou.
Hex v zákresu (`#FBCA04` u `design-debt`) je proto **ukázka, ne hodnota**: hash dává `#D4C5F9`, a je
to data, ne token palety.

**Potvrzení je druhá obrazovka téhož popoveru, ne sheet**, a nemá **výchozí akci** — poslední klik
před něčím nevratným je klik (#68). Že se to do popoveru vejde, je změřené, ne odhadnuté:
`NewLabelPickerWidthTests` měří **pixely za hranou** (popover má pevný rámec 300 bodů, takže přesah
se rámce nedotkne) a prohání tím i jméno o 39 znacích ze zákresu — akce ho **zalomí, neořeže**.

**Dvě odchylky od #392, obě k mockupu, ne od něj:** nabídka labelů má teď pevnou šířku 300 bodů
(`.pkr`), aby obě obrazovky byly stejně široké a popover při přepnutí nepodskočil, a `Zavřít` u věty
v panelu je `.mini`, jak ho kreslí zákres — systémové tlačítko bylo v 300bodovém panelu skoro tak
vysoké jako celá věta. **Neuděláno schválně:** `.pkr-foot` s nápovědou kláves (`↑↓ vybírá`,
`↵ přepne`, `esc zavře`) kreslí sekce 24 u **obou** nabídek a v aplikaci není ani u jedné — je to
mezera po #392, ne po #413, takže ji má spravit jedno issue nad oběma nabídkami, ne půlka tady.

Testů **3955**, z toho **37 nových** (změřeno na větvi před rebasem: 3868 → 3905, zbytek přidal
mezitím mergnutý `main`). Vloženými regresemi ověřené dvě věci: bez zápisu
do nabídky (`remember(_:in:)`) padnou tři tvrzení včetně toho o dorovnání kliknutím (protože
`toggleLabel` label, který repo nezná, odmítne), a s `fixedSize()` místo
`fixedSize(horizontal: false, vertical: true)` na jménu v akci padne sonda přetečení na
devětatřicetiznakovém jménu. **Neověřené testy:** že `⌥↵` v popoveru doopravdy dojde do pole
(testovací host nedostane aktivaci, změřeno u #392) a chování `POST /labels` proti živému API —
brána je ve slotové konfiguraci vypnutá schválně.


### #432 — sémantická škála se kreslí z palety, ne ze systému

Dotažení mezery, kterou našlo měření u #404: čtyři kapsle brala systémová zelená a červená a ve
světlém režimu měly kontrast **pod 3** — `vyřešeno` **1,63**, `schválil` **1,70**, `vyžádal změny`
2,52, `3 nálezy · 1 blokuje` 2,70. Návrh má na těch místech `--ok` a `--crit`, takže je to
srovnání aplikace s tím, co v mockupu **už nakreslené je** (jako #283, #348, #366 a #404), a bez
schvalovací brány.

**Opravila se třída, ne ty čtyři výskyty**: `45 míst ve 25 souborech` `App/` bralo zelenou,
červenou, oranžovou nebo žlutou ze systému. Nejhorší z nich přitom v zadání ani nebyla —
`3 nálezy` na systémové oranžové má **1,85**, tedy méně než všechny čtyři vyjmenované, a sedí
v témže `switch`i o řádek výš (`blocking > 0 ? crit : find`). Nechat ji tam by znamenalo vydat
opravu čitelnosti, po které je nejméně čitelná kapsle v okně ta, o které se nemluvilo.

**Otočilo to rozhodnutí z #309** („zbytek `ReviewStateAppearance` zůstává systémový, protože
zelenou s červenou bere ze systému ještě padesát míst — převést zrovna tenhle enum by z něj udělalo
výjimku“). Ten argument platí, jen se otočil: převedlo se všech 45 míst, takže výjimkou se stal
systém. Naměřené hodnoty ve světlém režimu, kresba z bitmapy: 1,63 → **3,05**, 1,70 → **3,19**,
2,52 → **3,49**, 2,70 → **3,77**, 1,85 → **3,36**, 1,80 → **3,44** (`čisté`). V tmavém režimu je to
u tří kapslí výměna **dolů** (nejvíc `čisté`, 6,26 → 5,55) a je zapsaná, ne zamlčená: tmavá větev
palety je tmavší než systémová škála, takže se platí rezervou tam, kde jí bylo dost. Nejnižší
hodnota po převodu je v tmavém režimu 3,90 (`vyžádal změny`).

**Ze systému zůstávají tři věci a u každé je důvod v `StatusScaleTests`.** `.secondary` není barva
ze škály, ale „nemám co říct“. `.purple` u `merged` má **3,42**, tedy nad hranicí — a purpurovou má
paleta jen jako vyhrazený akcent, kterým se kreslí běžící review. `.blue` u `renamed` ve stromu
a `moved` u přenosu draftu je na **2,85**, tedy pod hranicí: je to reálná vada, ale mimo třídu #432
(dvě ikony, ne kapsle) a mockup pro ni token nemá — `alertNote` má v paletě napsané, že modrou okno
jinde nemá. Patří to do vlastního issue, které projde bránou na vzhled; do té doby je to **číslo
v testu, ne mlčení**.

**Hlídají to dvě různá tvrzení, protože ani jedno nestačí samo.** `StatusScaleTests` čte zdrojáky
a tvrdí, že v `App/` není `.green`, `.red`, `.yellow` ani `.orange` (kolikrát je něco zapsané, se za
běhu zjistit nedá) — a k tomu na hodnotách, že škála vrací doopravdy token. Prahy
v `PillTypesettingTests` měří kresbu z bitmapy; guard nad zdrojáky o čitelnosti neříká nic a prahy
zas nevidí kartu ani prázdný stav. Hledání se u guardu muselo naučit dvě věci: **konec
identifikátoru za jehlou** — ne písmeno, číslice ani podtržítko (jinak je `color.redComponent`
porušení pravidla) a **číslo řádku z původního souboru**
(první podoba hlásila řádek v textu bez komentářů, tedy o 68 řádků mimo).

**Vidět je to z renderu, ne z pauzy**: tentýž `PillRenderProbe` před převodem a po něm dá dva
snímky v obou režimech, ze kterých je rozdíl vidět bez čtení čísel — a hlavně to, že se nezměnilo
nic dalšího (sazba, krytí washů, popisky, geometrie). Krytí zůstává 0,15 u nálezů a ve frontě, 0,18
v konverzaci.

Testů **3974**, z toho **4 nová tvrzení** (tři v `StatusScaleTests`, jedno u proužku reviewerů)
a dva nové vzorky kontrastu (`3 nálezy`, `čisté`), které #404 neměřilo. Vloženými regresemi ověřené
obě strany: s vrácenou `.green` v `ThreadBubbleView` spadne guard nad zdrojáky, s vrácenou
systémovou barvou ve vzorku spadne práh (1,63 proti 3,0). **Neověřené:** nic — `SlotCleanupTests`
spadly v jednom plném běhu na tom, že si běžící hlavní instance přepsala `com.ondrajodas.prism.plist`
uprostřed měření (3 bajty), samostatně i v dalším plném běhu jsou zelené; je to třída, kterou řeší
#411, ne tahle změna.

### #411 — testovací host přestal být hlavní instancí

Do #411 běžel `xcodebuild test` jako `com.ondrajodas.prism`, protože slotovou příponu dosazoval
teprve `bin/run.sh`. Všechno, co v testu prošlo `@AppStorage` nebo `UserDefaults.standard`, tedy
zapisovalo **do nastavení, které se doopravdy používá** — a nebyla to teorie: v uživatelově doméně
ležela uložená velikost sheetu z regresního experimentu u #327 a v nové doméně hosta se po prvním
běhu objevily **návštěvy u vymyšlených PR** (`cli/cli#1` s časem z roku 1970) i
`releaseNotes.lastSeenTag`. Ta druhá dvojice je podstatná pro rozhodnutí: nejde z testovacího kódu,
ale z **výchozích argumentů** `AppStore` a `ReleaseNotesModel`, takže stráž nad `Tests/` by ji
nechytila.

**Opravou je jedna hodnota v `project.pbxproj`**: výchozí `PRISM_SLOT = ".testhost"`. Identitu
aplikace stanoví `bin/run.sh` (předává `PRISM_SLOT` vždycky, i prázdný), takže výchozí hodnota platí
právě pro build, který si o identitu neřekl. Host tedy běží jako `com.ondrajodas.prism.testhost`
a hlavní instance i sloty zůstávají, čím byly (ověřeno na nainstalovaném `PRism-b.app`:
`com.ondrajodas.prism.b`). Zamítnuté cesty i změřené slepé uličky — `PRODUCT_BUNDLE_IDENTIFIER`
testovacího targetu (bundle je hostovaný, `Bundle.main` je aplikace), podmínka podle `ACTION`
(u `build` i `test` je to `build`), vlastní konfigurace pro testovací akci (druhý strom produktů),
vrstva v kódu s detekcí testů (chyba se platí uživatelovým nastavením) — jsou
v [`testovani.md`](testovani.md).

Zbylé dva projevy téže třídy ta hodnota neřeší, takže mají svoje opravy. **Vlastní suita s pevným
jménem je globál napříč procesy** (souběžné běhy tří slotů si přepisovaly klíč, `1180` tam, kde se
tvrdí `nil`) — jméno proto skládá `ScratchDefaults` z `UUID` a uklízí po sobě i prázdný plist. Že to
je potřeba, se ukázalo hned: po samotném `removePersistentDomain` se prázdný soubor **vrátí koncem
procesu**, takže první plný běh byl zelený a pět souborů na disku; druhý, s mazáním z podprocesu,
nechal **nula**. A **sada, která tvrdí něco o úklidu, si hlavní instanci vyrábí** v podstrčeném
`HOME` místo toho, aby čtla tu skutečnou — do její domény píše běžící aplikace (6 296 → 6 343 B),
což byl **dvakrát falešně červený `main`**.

Na obrazovce se nemění nic — je to celé test target a jedna hodnota v projektu. Testů **3978**,
z toho **8 nových** (`ProcessPreferencesTests`), tři plné běhy zelené. Vloženými regresemi ověřeno
pět věcí: `UserDefaults.standard` v testu, suita pojmenovaná literálem, jméno domény i cesta
k nainstalovanému bundlu v testu, `PRISM_SLOT` vrácený na `""` a mazání mimo slot ve
`bin/slot-cleanup.sh`. **Co se testem hlídat nedá** a zůstává na ruční kontrole: že po plném běhu
nezůstala na stroji doména `cz.prism.tests.*` — souběžné běhy slotů mají svoje rozdělané, takže by
tvrzení „nic tu není“ bylo červené podle toho, kdo běží vedle.

Jak často se do toho šláplo, je vidět na sousedním záznamu: [#432](#432--sémantická-škála-se-kreslí-z-palety-ne-ze-systému)
skončil v jednom plném běhu červeně na tomtéž přepsaném plistu (3 bajty) a musel to odepsat jako
cizí třídu. Tohle je ta třída.

### #407 — metrika písma: nula z `NSFont`, tři léčby a jedno měřidlo

**Na tomhle není co vidět** — je to testovací vrstva a měřidlo pod ní; na obrazovce se nemění nic.

Zbytek třídy z #367: plný běh padal **dvakrát z deseti** na `CommitPanelRoomTests`
a `LogTailHeightTests`, vždycky na metrice písma a vždycky zeleně, když se sada pustila samostatně.
Tři léčby ležely na třech místech — jedno čtení za test (#367), totéž u `DesignPillTests` (#348),
jedno čtení na proces s náhradním měřením (#327) —, takže si to musela pamatovat každá nová sada.

**Co ta nula doopravdy je, se změřilo, ne odhadlo — a jsou to dvě věci.** Není to zastaralé číslo, je
to **přechodně nepoužitelná metrika**: `NSFont.monospacedSystemFont(ofSize:weight:)` v testovacím
hostu vydá instanci, u které `maximumAdvancement.width` nedá použitelnou hodnotu — a **sazba tímtéž
objektem spadne uvnitř CoreTextu** (`NSInvalidArgumentException` z `TAttributes::ApplyFont` pod
`NSAttributedString.size()`). Zachytila to **první podoba téhle opravy**, která měla jako náhradní
měření vysázet `0`: sazba se pustila právě na tom vadném písmu a **položila celý běh** (169 testů
ze 3 979). Nebýt toho pádu, zbyla by tichá záskočná hodnota a příčina by se pořád jen odhadovala.

Druhé měření je konkrétnější a udělalo poslední kus opravy. V osmém z deseti plných běhů spadlo
`CommitPanelRoomTests` na `šířka znaku: 0` a `tally` u té zprávy řekl proč:
`měření 2, náhradní cesta 0×, nepovedlo se 1×, zamítnuto 0.0` a vedle toho `šířka znaku: 8.0361328125`.
Tedy: **první měření vrátilo nulu na všech třech cestách** (nula, ne `NaN`, a nulu dalo i čerstvé
písmo z deskriptoru) a **totéž písmo o zlomek sekundy později** dalo správnou hodnotu. Vada netrvá,
takže žádná jiná cesta v tom okamžiku nepomůže — pomůže **zkusit to znovu později**. Odhalilo to
mimochodem to, že se hodnota v chybové zprávě `#expect`u **čte znovu**: vedle sebe stálo, co tvrzení
vidělo, a co je vidět teď.

**Kde ta vada není** — čtyři sondy, žádná anomálie: teplé písmo v samostatném procesu (96 000
čtení), závod na prvním rozřešení v 500 čerstvých procesech (57 600), čtenáři proti churnu ve font
cache pod load 22 (3 041 433) a plný běh v testovacím hostu (3 242 670, `FontMetricProbe`). Čtení
teplého písma to tedy není a hammerováním se to chytit nedá; je to rozřešení **konkrétního objektu**,
a těch je za běh hrstka.

Zbylo z toho `FontMetric` (`App/Views/FontMetric.swift`) — jediné místo v `App/`, kde se čte metrika
písma: jedno měření na proces, mez 64 hodnot, tři cesty (`measured` → `fresh` → `derived`)
**opakované až čtyřikrát s milisekundovou odmlkou**, a **nula se nepamatuje**. Každý ten kus je
z měření: `fresh` staví písmo znovu z deskriptoru, protože vadný je ten objekt; opakování je tam,
protože vada je přechodná (bez odmlky by to byl tentýž stav přečtený čtyřikrát — celý řetěz je pár
mikrosekund); `derived` je poslední, protože její čísla jsou jen meze (u šířky znaku horní, u rámce
dolní). **Náhradní měření nesází text** — spadlý proces je horší než červený test. Rozhodnutí „jde
to použít?“ je `Policy.usableFontMetric(_:)` a hlídá `isFinite`, ne jen kladnost: `NaN` je hodnota,
kterou skutečné `NSFont` vydá (změřeno na písmu s nekonečnou maticí), a `Int(NaN)` shodí proces.

Sebralo to **deset** míst, kde se metrika čítala samostatně: pět v `App/` — včetně jednoho, kde na
jednu výšku řádku byla **dvě různá čísla** podle toho, jak daleko bylo view v sestavování
(`DiffTextView.singleLineHeight`) — a pět v `Tests/`. Poslední dvě (`PillTypesettingTests`,
`CodeTextSheetSizingTests`) přišly až po rebasu, kdy se souběžné větve mergly; do té doby patřily
někomu jinému. Ta druhá je za zmínku: porovnávala `static let` konstantu se **svým** surovým čtením,
tedy dvě čtení metriky v jednom procesu — přesně ta vada, jen ještě nespadlá.

Testů **3994**, z toho **13 nových** (`FontMetricTests`; zbytek přidal mezitím mergnutý `main`).
Vloženými regresemi ověřené dvě věci: bez
zapamatování hlásí `Metrika se měří jednou` 32 000 měření místo jednoho, a s vlastním
`NSLayoutManager`em zpátky v `LogTailHeightTests` padne guard nad zdrojáky jmenovitě na tom souboru.

K tomu **dvakrát deset plných běhů pod souběžnou zátěží** (čtyři paralelní optimalizované kompilace,
load 10–22). Před opakováním 7 zelených z deseti a mezi červenými **ten jeden pád na metrice**, ze
kterého se vada přečetla; s opakováním 8 zelených a **na metrice písma nespadlo nic**. Zbylé červené
jsou cizí sady a jiná třída: `SlotCleanupTests` fingerprintují plist běžící hlavní instance (#411)
a `AppStoreCommentTests` skončily na `PublishError.timedOut` po 65 s pod load 19. Všech sedm dotčených sad projde izolovaně za 9,4 s — to je ten způsob, jak se load-flake
pozná od nálezu.

### #361 — třinácté kolo: ten zápis nezmizel, a „třetí pohon“ není náš (otevřené)

**Nejdůležitější zjištění je oprava čísla, ne nová hypotéza.** Do třináctého kola se pracovalo
s tím, že `measureEstimates` po opravě z #435 z hořícího kola zmizel („35 z 21 834“). Byla to
**chyba čtení `sample`u**: 35 je počet **řádků se vzorem** ve stromu volání a 21 834 počet **řádků
souboru**. Podíl ten uzel drží: **11,3 %** (9. záchvat, 1524 z 13 479), **11,2 %** (11., 1046
z 9330), **13,2 %** (12., 2173 z 16 486). `fillingSlot()` je tedy **zlevnění** — dotazy na
`ConversationRow.id` 7,1 M → 3,6 M → 2,3 M —, ne oprava, a dokumentace se dala číst jako opak.

**Ten dotaz na velikost neodstraní žádný tvar té štěrbiny.** O velikost si říká `ScrollView` sám
(`ScrollViewUtilities.sizeThatFits(in:contentComputer:axes:)` se ptá obsahu na svou šířku), takže ho
má pružný rámec, `fillingSlot()` i `GeometryReader` **bez** vnitřního rámce — čímž padá i domněnka,
že se `_FrameLayout` ptá kvůli zarovnání (třetí podoba nemá co centrovat a dotaz tam je). Mění se
jen odkud: pružný rámec si ho odpovídá **jako kořen** aktualizace (30 z 30 vzorků), měřená štěrbina
**vnořeně** (18 z 18). Kdo přesně je ten vnější kořen, **není stabilní** a jmenovat ho by bylo
tvrzení, které jednou vyjde a jednou ne.

**„Třetí pohon“ z aplikace není, protože tam není.** Invariant, který vede všechny tři záchvaty —
`_External -> State` (182 → 313 → 382) plus `DynamicLayoutComputer<_HStackLayout>` (180 → 312
→ 365) —, je **downstream** toho zápisu z `LazyLayoutViewCache`: v každém zásobníku je jich pět,
každý s layout computerem své položky v konstantním odstupu čísel uzlů (1288 B v aplikaci, 676 B
v harnessu), pětka je řádově počet viditelných uzlů osy, a `AG::Graph::value_set` je v celém vzorku
jediný a leží pod `updateItemPhases()`. `DynamicLayoutComputer<_HStackLayout>` je pak prostě
`HStack` v `ConversationNodeView`.

**Třetí největší kus toho kola dostal jméno:** `SecondaryLayerGeometryQuery` →
`ViewDimensions.subscript.getter` → `explicitAlignment`, tedy `.background(alignment: .topLeading)`
s linkou osy v `ConversationNodeView` — **2149 z 16 486** vzorků (13,0 %) ve dvanáctém záchvatu,
ale jen **409 z 13 479 (3,0 %)** v devátém, kdy kolo hořelo stejně.
Nechává se to tak: dotaz jen **čte** geometrii a v `changed` vstupech kola není ani jednou, takže je
to práce v kole, ne jeho pohon — a alternativa je vrátit linku do `ZStack`u, což je pružná výška
v řádku líného seznamu (zakázaná třída z #375).

**Zbývající možnost i s cenou:** přestat na ose používat `LazyVStack`. Je to jediná podoba, u které
se ta vazba nemá kde utvořit (v grafu ani jeden `LazySubview*` atribut), ale první rozvržení 300 uzlů
stojí **32–35 ms proti 2,2–3,4 ms** a to s obyčejným `Text`em, ne s markdownem — a diffu (7. záchvat,
tab `Soubory`) by to nepomohlo. Do repa se to proto nedostalo; je to rozhodnutí k posouzení, ne
mezera.

**Nové je i to, co je v záznamu těsně před zdí.** Poslední tři sekundy dvanáctého záchvatu nejsou
zašpiněné rozvržení, ale **průchod tělem odshora** (`ContentView=2 PullRequestDetailView=3
ConversationView=2 ActivityFeedView=1`), přičemž `ConversationRow.id` je ještě 60 a osmirámcový
zásobník kola už tam je — ten je tedy i ve **zdravé** sekundě a patologická je jen frekvence
(60 → 66 → 18 069 → zeď). Předehra ukazuje na **změnu ve storu**, nejspíš tik pollingu; napodobit
se to ale nepovedlo (čtrnáctý neúspěšný pokus, viz `burnsAfterTheDataStops`).

**#361 zůstává otevřené a oprava z tohohle kola žádná není** — to je celý výsledek a je záměrně
napsaný takhle. Nové je: sonda (`LazySelfReferenceProbe`, tři měření), guard nad vyloučením
(`ConversationAxisFeedbackTests` — v uzlu osy není `onGeometryChange`, `onContinuousHover`,
`GeometryReader`, `ViewThatFits`, `ScrollViewReader` ani `scrollTo(`) a postup, jak se `sample` čte,
aby se ta chyba s řádky neopakovala. **Třináctý** neúspěšný pokus kolo vyrobit: scéna tvaru celého
tabu s 300 uzly má po zastavení pumpy 0,000 s CPU ze 4 s.

Na obrazovce se nemění nic — je to měření, dokumentace a testy. Testů **4000**: dvě nová tvrzení
v `ConversationAxisFeedbackTests` a čtyři měření sondy (ta se v běžném běhu přeskočí); zbytek přidal
mezitím mergnutý `main`.

### #438 — geometrii řádku diffu nepočítá diff, ale úryvek na ose

**Na tomhle není co vidět** — mění se, co se počítá, ne co je na obrazovce; `onGeometryChange` do
rozvržení nezasahuje, a proto je v repu místo `GeometryReader`u.

Zadání vycházelo z toho, že `DiffLine.geometry` (**369 546** a **711 018** zásahů ve dvou záchvatech
#361, v obou vepředu Konverzace) počítá **diff pod jiným tabem**. Měření to vyvrátilo. Sonda
`IdleDiffSpinProbe.lineGeometryOrigin` projede kolečkem tutéž scénu ve dvou záložkách:

| Vepředu | před | po |
|---|---|---|
| diff (split, 13 souborů, tisíce řádků) | **0** | 0 |
| osa konverzace (60 vláken s `diffHunk`em) | **242** | **0** |

Diff se neptá **ani když je vepředu**, a není to o viditelnosti: `DiffView` slévá řádky do bloků
(`DiffRow.blocked(_:)`), takže v něm `DiffLineView` nekreslí ani jeden řádek. Zásahy jsou z osy —
úryvek u vlákna (`ThreadSnippetView`, #158) kreslí `DiffLineView` řádek po řádku a rámeček z něj
nemá kdo převzít, protože na ose se netáhne. Poměr sedí: 242 proti 461 dotazům na
`ConversationRow.id` v sondě, 369 546 proti milionům v záchvatu.

**Oprava je posun podmínky, která v repu byla odjakživa**: `guard let dragID` se vyhodnocoval až
v **akci**, tedy po čtení. Nově je před ním (`reportsFrame` — identita **i** krabice), takže se
`onGeometryChange` na ose vůbec nepřipojí. `dragAnchor` v té podmínce schválně **není**: řádek bez
kotvy se hlásí s prázdným seznamem a právě tím vyklízí zastaralé plochy pod sebou, bez čehož by
tažení chytalo řádky vedle (#110).

**#361 to nezavírá.** Nové je jedno pozorování: `GeometryActionBinder` byl na ose kořenem **3 ze 6**
odebraných zásobníků a po opravě je **0 ze 6**, tedy z osy zmizel jeden kořen aktualizace grafu. Že
tím kolo přestane vznikat, se doložit nedá — v harnessu se za třináct kol nevyrobilo ani jednou.

Testů **4006**, z toho **5 nových** (`DiffLineGeometryTests`) plus scénář sondy, který se v běžném
běhu přeskočí. Tvrdí se to nad zdrojáky schválně: práce, jejíž výsledek nikdo nepřevezme, nenechá
nic pozorovatelného a jediná stopa je počitadlo v `RenderDiagnostics.current` — globál procesu, do
kterého test zapisovat nesmí (#367, #411). **Ověřeno vloženou regresí v obou podobách**: s
`reportsFrame` na `true` spadne tvrzení o podmínce a sonda vydá zase 242, s `onGeometryChange`
vráceným do řetězce `row` spadne tvrzení o větvi.

### M12 — Ergonomie okna (milník #14)

Tři issues z jedné dávky, u kterých je rozvrh naopak krátký: **#441** (klávesové zkratky),
**#442** (prstýnek místo šipky, dokud se aplikace ptá) a **#443** (pět řádků dění na dashboardu)
jdou **souběžně**, žádná nestojí na jiné. Milník mají proto, že rozvrh — i když říká „všechno
naráz“ — je jediná věc, která tu informaci udrží napříč sessions; `Průběžné` je koš bez pořadí.
Jediná vazba: #441 chce mít `⌘R` zakázané, dokud běží obnovení, a `AppStore.isRefreshing` v repu
už je, takže na #442 nečeká. Nakreslené jsou #442 a #443 v sekcích 32 a 31 návrhu.

### #434 — nabídky v panelu dostaly patku s nápovědou kláves

Návrh kreslí `.pkr-foot` u **obou** nabídek v panelu (sekce 24) a v aplikaci nebyla ani u jedné —
mezera po #392, kterou #413 vědomě nechalo. Návrh se nemění, takže to bylo srovnání s tím, co
v mockupu už nakreslené je, a šlo se rovnou.

Patka je jedna třída v CSS a od #434 je i **jedno místo v kódu**: `PickerFooter` drží plochu (horní
linka `--line-soft`, podklad `--panel-2`, odsazení `6 × 11`, mezera `12`) a používají ji obě její
náplně — nápověda kláves i patka potvrzení nového labelu, která tam do #434 měla vlastní kopii těch
čtyř hodnot. Obsah nápovědy je `↑↓ vybírá`, `↵ přepne` (u reviewerů `vyžádá`), `esc zavře`; liší se
tedy **jediné slovo**.

**Nad prázdným výsledkem se patka nekreslí**, a je to jak v zákresu (nabídka s `.pkr-empty` ji nemá),
tak jediná možnost, která nelže: `pickerSelection` nad prázdnem vrátí `nil`, takže by dvě ze tří
položek slibovaly klávesu, po které se nic nestane. Rozhodnutí drží `Policy.pickerShowsKeyHints(rowCount:)`
a k němu tvrzení, že se s `pickerSelection` **shodne** — rozejít se to umí potichu, protože patka je
stav okna, kdežto tohle jsou dvě čísla.

**`⌥↵` v patce schválně není.** Zakládání nového labelu má zkratku napsanou u akce samotné a návrh to
tak kreslí i v tom stavu, kde ta akce je (sekce 26): patka i tam nese tři položky. Čtvrtá položka by
navíc neplatila ve třech ze čtyř stavů nabídky.

**Změřeno, ne odhadnuto** (zadání to žádalo výslovně): patka chce **194 b** (`přepne`), resp. **195 b**
(`vyžádá`) z 300, které má `.pkr` — rezerva 105 bodů. U nabídky reviewerů, která šířku nemá danou
rámcem, se tím **přirozená šířka posunula ze 145 na 195**: patka je v ní od #434 nejširší prvek.
Zapsané je to tak, jak to vyšlo, ne jak to bylo zamýšlené — tvrdí se, že nabídka nepřeteče za 300 ze
zákresu, ne že s ní patka nehne, protože druhé by bylo nepravdivé.

**Co se v harnessu ověřit nedá:** že ty klávesy fungují. Testovací host nedostane aktivaci (změřeno
u #392), takže nemá key okno a stisk nemá kam sednout — zvlášť u `⌥↵`, které je na poli, ne na okně.
Ověřuje to člověk na běžící aplikaci a je to podmínka toho, že patka smí ty klávesy tvrdit.

### #442 — obnovování je vidět i na tlačítku, ne jen na dashboardu

**#442 je hotové.** Dokud běží dotaz na GitHub, kreslí se v tlačítku `⟳` v hlavičce okna
`SpinningRing` — **týž** prstýnek, jaký na záložce znamená běžící review (nový by znamenal, že se
„pracuje se“ čte v jednom okně dvěma tvary, a hlavně by otevřel past z #350). Platí to i pro
automatický tik: rozhoduje `AppStore.isRefreshing`, ne to, kdo dotaz spustil.

Podmínka „zakázáno, dokud se ptáme“ leží **na jednom místě** (`Policy.refreshControl`) a čtou ji
tři cesty: podoba a `disabled` tlačítka, `AppStore.refresh()` jako pojistka proti druhému dotazu
(tutéž akci nabízí paleta ⌘K i `Zkusit znovu` v prázdném stavu, takže samotné zašedlé tlačítko by
nestačilo) a **#441 si odsud vezme povolení pro `⌘R`** — tím se ta vazba z rozvrhu vyřídila.
`PollingService.refresh()` guard nedostal: smyčka si ho volá sama a je sekvenční.

Rozměr tlačítka se nehnul (27 × 25, `HeaderButtonMetrics`) a je na to tvrzení nad `fittingSize`
obou stavů — hlavička nemá poskočit tím, že se aplikace ptá. Ověřeno i na běžící aplikaci:
z dávky snímků hlavičky pořízených hned po startu je na prvních prstýnek a na dalších šipka, ve
stejné poloze. Testů **4021** (devět nových); nápovědu se zkratkou `Obnovit seznam (⌘R)`, kterou
kreslí návrh, přidá #441, protože do té doby by uváděla zkratku, která v okně není.

### #443 — pět řádků dění na dashboardu

Sekce `Dění` (#414) je dobré místo, **když se do ní jde** — jenže se do ní muselo napřed přepnout,
aby se zjistilo, jestli je do čeho koukat: odznak v railu říká počet, ne co se stalo. Dashboard je
jediná obrazovka, na kterou se člověk podívá, aniž by se ptal, takže na něm od #443 stojí **pět
nejnovějších řádků** dění a cesta do celé sekce (návrh, sekce 31).

**Třetí blok pravého sloupce, pod `Co teď`** — a je to **změna proti prvnímu zadání i prvnímu
zákresu**, ne to, co bylo napsané. Původně měl blok stát pod oběma sloupci přes celou šířku; poznalo
se **až na běžící aplikaci**, že je to špatně, protože prázdné místo je vidět v okně, ne v poznámce.
Změřeno nad mockupem: levý sloupec s oběma frontami je **578 bodů** vysoký a pravý s legendou
a akcemi **153**, takže pod ním zbývalo **425 bodů prázdna** a pás přes celou šířku by začínal *až
pod* ním — dole na obrazovce, kam se nikdo nedívá. Blok má **266 bodů**, pravý sloupec s ním doroste
na **419** a pořád zůstane o 159 kratší než levý.

**Cenou je úzký tvar řádku a ta cena se platí obsahem, ne zalomením.** Pravý sloupec je `1fr`
z `1.45fr 1fr`, tedy 456 bodů, a celá událost se do nich nevejde — má **42 až 66 bodů**, dvě až tři
patra. V bloku proto zůstává **titulek, `repo#číslo` a čas**; podrobnost („přišly 3 commity“), sha,
chip `bez banneru`, autor i cíl (`→ Nálezy`) se vynechávají a zůstávají v sekci. Řádek pak má **24
bodů**, jednu řádku jako v sekci. **Nezalamuje se**: co se nevejde, ořízne **titulek**, protože
`repo#číslo` a čas jsou souřadnice, podle kterých se pozná, čeho se to týká — a že ustoupí zrovna
titulek, drží `layoutPriority` na obou souřadnicích (`flex: none` z návrhu).

**Ukázka a rozcestník, ne druhé dění.** Sekce zůstává tím, čím je — rolovat, číst po dnech
a dohledávat se chodí tam. Blok proto nemá vlastní pruh `Tady jsem skončil`, vlastní hlavičky dní
ani vlastní řádek: kreslí **týž `ActivityRowView`** jako sekce, jen v úzkém tvaru, a je vyčleněný do
vlastního souboru spolu s osou (`ActivityTimeline`). V hlavičce `ActivityFeedView` do té doby stálo,
že dění blokem na dashboardu **není**; ukázalo se, že ta ukázka je právě to, co chybělo, a ten
komentář je přepsaný i s důvodem.

**Značku poslední návštěvy blok neposouvá** — a je to to nejcennější tvrzení celého issue, protože
by se rozbilo potichu: kdyby ji posunul pohled na domácí záložku, vynulovalo by se nepřečtené
a odznak v railu by zmizel, aniž bych něco přečetl. Drží to `isActivityVisible` (rail **a** domácí
záložka), takže dashboard tou podmínkou neprojde, a testuje se to i přes klik na řádek — jediné
místo v tom bloku, které se storu vůbec dotýká.

**Rozhodnutí, která k tomu patřila:**

- **Jeden příznak na místo, ne dva booleany** (`ActivityRowPlace`). Úzký tvar i den u času plynou
  z **místa**, ne z události, takže dva nezávislé příznaky by šlo nastavit křížem a vznikla by z toho
  třetí podoba, kterou návrh nekreslí.
- **Den u času** (`Policy.activityTime(of:now:at:)`). V sekci nese den hlavička dne, tady ho nemá kdo
  nést, takže by `v 7:58` u včerejší události tvrdilo dnešní ráno. Formát je tentýž jako
  u `visitLabel` (`v 7:58`, `včera v 7:58`, `20. srpna v 7:58`) a rozhodnutí je **jedno** — dva
  výpočty téhož by se rozešly právě v tom, co je vidět jeden den v roce. Relativní podobu
  (`před 2 min`) skládá dál view, protože se v okně přepočítává sama.
- **Blok je součástí `Dashboard`**, ne vlastní getter: view si dashboard bere jednou za překreslení,
  takže druhý getter by znamenal druhý průchod záznamem při každém průchodu tělem.
- **Patka je `DashboardBlock.Footer`** z #371, ne nový typ. Tvar i chování jsou totéž (text, počet
  zbylých, sekce), takže druhá kresba patky by se s tou první rozešla v odsazení a v čáře nad ní.
- **`celé dění →` v hlavičce je odkaz, ostatní popisky v hlavičkách bloků zůstávají popisky.** Text
  v barvě akcentu, po kterém se nic nestane, je tatáž lež jako karta bez cíle (#371), jen menší.
- **Prázdno je jedna věta, ale pořád čtyři různé.** Ze tří prázdných obrazovek sekce zbude důvod;
  tlačítka (zapnout hlášení, otevřít Nastavení systému) patří tam, kam jsem přišel schválně, a cesta
  k nim vede tím odkazem v hlavičce. Klid, ztracená historie a dvě mlčení se nesmí slít ani tady.
- **`LazyVStack` sem nepatří** — pět řádků je strop z `Policy`, ne odhad, takže líný seznam by za
  měřenou velikost (#361) platil tam, kde se nejhorší případ vejde na obrazovku.

Testů **4070** po sloučení s #441, všechny zelené (samotná větev jich měla 4051): `DashboardActivityTests` výčtem (strop, patka, nadpis, den u času,
čtyři prázdna), tři tvrzení ve `AppStoreFeedTests` a pět v `ActivityRowShapeTests` — ta měří úzký
tvar **dvěma měřidly**: výškou to, že se vejde na jednu řádku a plný řádek ne, a přirozenou šířkou
to, co v něm **není**. Ověřeno vložením regrese dvakrát (vrácená podrobnost s cílem, zahozený
`lineLimit`). `DashboardFooterSeparatorTests` počítají dál **jedenáct** čar — blok stojí v pravém
sloupci a jejich vzorek jde přes levý, takže by změněný počet znamenal, že se kreslí jinam.

### #441 — zkratky na to, co se v okně dělá denně

**#441 je hotové.** Přibylo pět zkratek: `⌃W` (zavřít záložku pull requestu), `⌘R` (obnovit
seznam), `⌃1`–`⌃5` (sekce railu), `⌃⏎` jako **druhá** klávesa k `⌘⏎` u potvrzení odeslání
a `⌘.` (zastavit běžící review na PR v okně). `⌃W` schválně, ne `⌘W`: to patří systému —
a ze stejného důvodu jsou sekce railu na `Control`u, protože `⌘1` a `⌘2` jsou uvnitř PR strom
souborů a panel.

**Česká klávesnice byla jádro zadání, ne detail.** `keyboardShortcut` páruje na **znak**, takže
`⌃1` na české mapě nezabere vůbec — pod tou klávesou je `+`. Každá sekce railu proto dostala
**dvě** tlačítka s toutéž akcí (`⌃1`+`⌃+`, `⌃2`+`⌃ě`, `⌃3`+`⌃š`, `⌃4`+`⌃č`, `⌃5`+`⌃ř`). Dvě
tlačítka se stejnou akcí a jinou klávesou jsou v pořádku; dvě se **stejnou kombinací** ne.

**Kombinace se tím posbíraly do katalogu** (`Policy.windowShortcut`) a je to hlavní změna, kterou
z toho `App/` má. Do #441 se psaly ve čtyřech souborech a nakreslená popiska stála **vedle**
klávesy (`shortcut: "⌘⇧R"` v témže volání jako `key: KeyEquivalent("r")`) — obojí se dá rozejít
potichu. Teď je katalog jediné místo, kde se rozhoduje, co je pod kterou klávesou; popisku si
z něj **odvozuje** paleta ⌘K, chip v panelu zadání, řádky dashboardu i nápovědy tlačítek. Do
SwiftUI to překládá jedno místo (`WindowShortcutButtons`, `View.windowShortcut(_:)`) a `⌘R` si
povolení bere z `Policy.refreshControl` (#442), ne z druhé kopie té podmínky.

**Paleta ⌘K u akcí kreslí zkratku** — `⌘R`, `⌃1`–`⌃5` a nad běžícím review `⌘.` k tomu, co v ní
bylo (`⌘2`, `⌘,`). U sekcí je to **číslicová** varianta; česká by z jedné kapsle udělala dvě kvůli
údaji, který se člověk naučí jednou. Nápověda tlačítka obnovení má `Obnovit seznam (⌘R)`, jak to
kreslí návrh — do #441 by uváděla klávesu, která v okně není.

**Tvrdá podmínka č. 1 se nemění**: `⌃⏎` otevírá **potvrzení**, neodesílá, a v potvrzovacím sheetu
zkratka na odeslání není a nebude. Zakázané je přitom s `⌘⏎` naráz a za týchž podmínek — jsou to
dvě tlačítka s jednou akcí, ne dvě akce.

Testů **4040** (devatenáct nových, dvě upravená). Devatenáctý přibyl po Copilotovi a je z nich
nejužitečnější: hlídá, že se kombinace **nekreslí literálem**. Ta první stráž ho nechytala, protože
nakreslená kapsle žádnou klávesu neregistruje — jen o ní tvrdí. Tímhle způsobem zůstalo `⌘2`
natvrdo v hlavičce panelu, `⌘K` v kapsli hlavičky okna a `⎋` v nápovědě commitu. Ověřeno **vloženou regresí** z obou stran: kolize
`⌘K` shodí tvrzení o duplicitě, literální `keyboardShortcut` v `ContentView` shodí stráž nad
zdrojáky. **Co se v harnessu ověřit nedá:** že klávesy fungují — testovací host nedostane aktivaci
(#392), takže nemá key okno a stisk nemá kam sednout. Poslední kolo dělá člověk na běžící
aplikaci, na české i anglické mapě — a s ním dvě věci, o kterých rozhoduje systém: `⌃1`–`⌃5`
umí sebrat Mission Control (`Přepnout na plochu N`) a `⌘.` je v Cocoa druhé jméno pro Escape,
takže tam, kde je naše zastavení zakázané, se chová jako `⎋`. Obojí je zapsané v dokumentaci,
protože z katalogu ani z testu to vidět není.

### #361 — patnácté kolo: osa konverzace přestala používat líný seznam

**Tohle je první kolo #361 s opravou.** Předchozích čtrnáct hledalo, **co graf špiní**; čtrnáctý
záchvat na to odpověděl a odpověď zní, že to nešpiní nic z aplikace.

**Co je v těch dvou vzorcích ze živého hoření.** Obě signatury jsou shodné (na rozdíl od tří
vzorků u #350, které se vylučovaly): `LazySubviewPlacements.placeSubviews` **60,3 % / 60,5 %**
vzorků hlavního vlákna, `ForEachState.forEachItem` 30,4 / 29,7 %, `updateItemPhases()` 7,1 / 6,8 %
a `AG::Graph::value_set(` 6,8 / 6,7 %. Kruh je celý uvnitř SwiftUI — umístění položek zapíše fázi
do grafu, zašpiněný graf si vyžádá další update, umisťuje se znovu. **Pohon zvenčí je nula**
(žádný timer, `CVDisplayLink` ani hover) a **neběží ani jedno naše tělo**: ze 101, resp. 158 rámců
aplikace jsou všechny kromě dvou vstupních bodů jen value-witness kopie `ConversationRow`.

**Osa proto kreslí `VStack`.** Je to jediná podoba, u které se ta vazba nemá kde utvořit — v grafu
nevznikne ani jeden `LazySubview*` atribut, což je změřené z obou stran (`LazyVStack` 2 vzorky ze 2,
`VStack` 0). Zlevňování obsahu kola tím **končí**: #375, #379, #386, #393, #435 i #438 byly každý
o kus levnější kolo a ani jeden z nich neměl co zastavit.

**Cena je změřená a není malá** (`ConversationAxisShapeProbe`, skutečné `ConversationNodeView`,
Debug, okno 1000×800): první rozvržení **44 uzlů 55 ms proti 5**, 150 uzlů 187 proti 5, 300 uzlů
413 proti 5, 400 uzlů 614 proti 6; projíždění 150 × 40 pt **0,86 s proti 0,31 s** CPU. Únosné je to
jedině proto, že **osa je shora omezená**: `ConversationQuery` bere `first: 100` ze čtyř seznamů
a nestránkuje, takže víc než čtyři stovky uzlů odsud vyjít nemůže. Diff takovou mez nemá a líný
seznam v něm **zůstává**.

**`List` je změřený a zamítnutý.** První rozvržení má levné (78–112 ms bez ohledu na počet)
a `LazySubview*` v grafu taky nemá, ale výška obsahu je u něj **odhad** (44 uzlů 4 876 pt proti
6 745, 300 uzlů 11 020 proti 45 432), takže posuvník lže a poloha při projíždění skáče; syntetické
gesto s ním navíc **nepohne vůbec**, takže se cena projíždění naší sondou změřit nedá; a jeho řádek
nese vlastní chrome, tedy změnu vzhledu, která patří napřed do mockupu. Zůstává v sondě jako
měřená varianta.

**Co tím dokázané není:** že záchvat nepřijde. Kolo se v harnessu nepovedlo vyrobit ani počtrnáct,
takže „po opravě nehořelo“ by bylo tvrzení bez zkoušky — a přesně to se v tomhle issue čtrnáctkrát
nesmělo napsat. Doložené je **strukturálně**: ten zápis do grafu nemá na ose kdo udělat. A **diffu
to nepomáhá** (7. záchvat hořel nad tabem `Soubory`), takže se tatáž třída kola může vrátit tam;
tam se ale líný seznam vyhodit nedá, řádků jsou tisíce.

Hlídá to `ConversationAxisEagerTests`: v `ConversationView` není `LazyVStack` ani jeho sourozenci,
a ta mez se počítá **z plných stránek**, ne opisuje z konstanty. Ověřeno vložením regrese (vrácený
`LazyVStack` shodí první tvrzení). Syntetická osa se přesunula do `ConversationFixture`, aby obě
sondy měřily tentýž materiál.

Testů **4077**, všechny zelené: tři nová tvrzení v `ConversationAxisEagerTests` a k tomu čtyři
měření `ConversationAxisShapeProbe` (ta se v běžném běhu přeskočí); zbytek přidal mezitím mergnutý
`main`. **Na obrazovce se nemění nic** — osa vypadá stejně (ověřeno rendrem `DetailTabRenderProbe`
v obou šířkách), mění se jen to, kdy se uzly vyrábějí.

### #447 — `CLAUDE.md` podruhé přerostl hranici, u které si sám říká „čas rozdělovat“

`wc -c < CLAUDE.md` vrátil **104 597 B**. Soubor si tu hranici stanovil sám („nad ~100 kB je čas
rozdělovat znovu“) a není to estetika: Copilot si ho bere jako custom instructions se stropem
110 tisíc tokenů, a když ho přeroste, review na PR **vůbec nedoběhne** (stalo se to při 315 kB,
#162; první rozdělení do `docs/` bylo 873bc29 a nechalo 37 kB).

**Po rozdělení 66 576 B**, tedy o **36 % míň** a 839 řádků místo 1308. Zůstalo tady to, co je
potřeba znát **dřív, než se něco napíše**: věty pravidel, výčty tvrdých podmínek (sedm metod
`ReviewPublishing`, pět zakázaných akcí, sada nástrojů revieweera) a **dvacet grepů**, které se
pouštějí před pushem — ty by v `docs/` nikdo nespustil. Odstěhovala se **vysvětlení, naměřená
čísla a historie změn pravidel**, a ke každému zůstal odkaz.

Kam se co přestěhovalo: rozbory tvrdé podmínky č. 1 a č. 2, výkonové poučky (#220, #236, #252,
#275, #325, #327, #350, #358, #361, #393, #422, #428, #432, #441) a obří buňka `Policy` z tabulky
modulů do [`docs/architektura.md`](architektura.md); postupy měření (#269, #274, #391) do
[`docs/testovani.md`](testovani.md); historie změn samotných pravidel (#46, #125, #162, a proč se
merge a zavření issue od 2026-08-01 neptají) do **nové sekce specifikace** *Záznam rozhodnutí —
pravidla repa a pracovní postup*; a operační znalost o `gh` (co na tomhle repu padá, čím to
nahradit, jak číst výsledek Copilota) do **nového** [`docs/github-cli.md`](github-cli.md).

**Skončilo to na 66 kB, ne na orientačních 40, a je to rozhodnutí.** Poprvé se stěhovala
dokumentace, teď zbyla po odstěhování všech vysvětlení jen tři nestlačitelná pásma — výčty
tvrdých podmínek (9,7 kB), grepy před pushem a věty pravidel, kterých má repo proti stavu po
873bc29 skoro dvojnásobek. Cesta k 40 kB proto vedla jedině přes **mazání pravidel**, ne přes
stěhování vysvětlení; zdůvodnění je v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447-potřetí-496).
Kontrolní číslo v `CLAUDE.md` zůstává **hranice 100 kB**, ne cíl 40.

**Že se nic neztratilo, je doložené dvěma průchody, ne dojmem**: všech **173 tučných začátků
odrážek** z původního souboru má v novém protějšek a všech **28 odkazů na issue**, které
z `CLAUDE.md` zmizely, je v `docs/` nebo v README. Odkazy se ověřují skriptem, který spočítá
GitHub kotvy z nadpisů — **65 relativních odkazů, nula rozbitých**. **Na obrazovce se nemění
nic**, je to dokumentace.

### #453 — do běžící session se dá vstoupit, jen ne uvnitř okna

V hlavičce dráhy v tabu `Průběh` bylo `⧉`, které **zkopíruje** `claude --resume <id>`. Je to cesta
ven do terminálu a byla úmyslně nejmenší možná — jenže na jejím konci pořád zbývalo přepnout se do
Terminálu, vlepit a odentrovat. Vedle něj je od #453 **`▶`** (`Otevřít session v Terminálu`, návrh
sekce 34), které tentýž příkaz rovnou pustí v `Terminal.app`, a to **v pracovním stromu** té
session. Kopírování **zůstalo**: kdo si session pouští jinde (iTerm, tmux, jiný stroj), potřebuje
text, ne cizí okno — jsou to dvě akce, ne dvě podoby jedné.

**Tvrdá podmínka č. 1 se tím nemění, a to bylo jádro celého issue.** Terminál je **mimo aplikaci**
— je to totéž, jako když si člověk příkaz vlepí sám, jen bez těch tří kroků. Uvnitř okna žádný
terminál nevzniká: `grep ReviewPublishing App/` vypisuje **týž seznam šesti souborů** jako `main`
a `SingleWayOutTests` prošly beze změny. **Vestavěný terminál je zamítnutý a zapsané je proč**:
znamenal by, že se z okna dá spustit `gh pr merge` i `git push`, tedy že podmínka přestane platit
— a nepůjde ji uhlídat testem, protože ta cesta nevede přes kód aplikace.

**Pracovní strom je podmínka stejně jako `session_id`, a je to odchylka od zadání** (to mluvilo jen
o `id`). `claude --resume` hledá vlákno podle adresáře, ve kterém se spustí, takže tentýž příkaz
jinde session **nenajde** — otevřelo by se okno, ve kterém `claude` řekne, že takové vlákno nezná.
„Nabízí se to jen tam, kde je co obnovit“ tedy platí doslova, a je to tatáž dvojice podmínek jako
u `Ukázat session` (#327). Rozdíl není teoretický: dráha z uloženého běhu bez osy zná `session_id`
a strom ne (soubory z doby před #203). Rozhoduje `Policy.terminalSession(of:)`, ne `if` ve view.

**Ověřeno spuštěním, ne přečtením** — u téhle cesty se chyba projeví tím, že se okno neotevře
a nikdo se nic nedozví. Změřilo se ručně, mimo aplikaci (postup je v
[`testovani.md`](testovani.md)), a vyšly z toho dvě věci, které by se neodhadly: `osascript`
argument doopravdy předá do `on run argv` (takže se příkaz nemusí vlepovat do zdrojáku skriptu —
uvozovka v cestě by ho rozbila) a **z výstupu se úspěch nepozná**, protože `activate` na konci
nevrací nic; rozhoduje návratový kód, a přesně na něm to aplikace staví. Uzávorkování cesty sedí
i na apostrof (`cd '/tmp/it'\''s here'` vypsalo
`/tmp/it's here`); od #453 ho skládá **jedno místo** (`ShellQuoting`), sdílené se `Zkopírovat
příkaz`.

**Selhání se hlásí ve stavovém řádku** (`AppStore.terminalFailure`), doslova tím, čím ho vysvětlil
systém. Je to tentýž případ jako notifikace (#88): výsledek je vidět mimo aplikaci, takže `try?`
by z tlačítka udělal něco, co občas nedělá nic. Aplikace k tomu dostala
`NSAppleEventsUsageDescription` v `Info.plist` — bez něj macOS Apple event odmítne kódem `-1743`
a **ani se nezeptá**, protože ho přisuzuje odpovědnému procesu (aplikaci), ne tomu `osascript`u.

Testů **4098**, všechny zelené — z toho **21 nových**: `Policy` výčtem (kdy se tlačítko nekreslí,
že `▶` pouští týž příkaz, jaký kopíruje `⧉`, a že `cd` je s `&&`), tvar volání `osascript`u
(příkaz jde jako argument, ne do skriptu) a to hlavní ze storu — **neotevřené okno skončí hláškou,
ne tichem**.

### #446 — diff kreslí kód jen bloky, a `DiffPairView` je pryč

**Na tomhle není co vidět** — a právě to je tvrzení, které se muselo doložit. Kreslí se táž věc
touž cestou; ubyl kód, ke kterému se od #157 nedostal ani jeden řádek.

Zadání říkalo, že do `DiffRowView` z diffu nedojde ani `.line`, ani `.pair`, protože `DiffView`
sype do `ForEach` **vždycky** výsledek `blocked(_:)`, resp. `blockedPairs(_:)`. **Půlka toho
platí, půlka ne** — změřeno nad pěti skutečnými diffy z fixtures v obou pohledech:

| Případ | Dojde ke kreslení? |
|---|---|
| `.pair` | **Nikdy** — ani mezi bublinami, které blok rozetnou |
| `.line` | **Jednou**: poznámka `git`u (`\ No newline at end of file`) ve **split** pohledu |

Ta výjimka je průsečík dvou rozhodnutí, která spolu nesouvisejí: `DiffRow.paired(_:)` `meta` řádek
**nepáruje** (není to obsah souboru, takže nemá stranu — #98) a `blockedPairs(_:)` slévá **jen
dvojice**. V pohledu pod sebou výjimka není, tam ji `blocked(_:)` sebere do bloku.

**Smazal se proto `DiffPairView`** (sto řádků paralelního kreslení dvojice) a s ním dvě věci, které
tím ztratily jediného volajícího: `DiffLineView.side` — volba „jsem buňka dvojice“, tedy tři větve,
které nikdo nevyplnil — a `DiffMissingHatch` jako SwiftUI `Shape` (šrafu kreslí `DiffTextView`
v AppKitu, zbyla geometrie `segments(in:)`). Větev `.line` naopak **zůstala**, protože je živá.

**Případ `.pair` ve `switch`i zůstává, ale kreslí týž blok, ne `EmptyView`.** Enum se nezúžil, takže
`DiffRowView` musí být vyčerpávající — a prázdno by byla tichá díra v diffu, kdyby se tam dvojice
někdy dostala. Delegace je jeden řádek a je ověřená renderem: obě větve daly **bajt po bajtu tentýž
PNG**.

**Doloženo, že se na obrazovce nemění nic**: 14 offscreen snímků před změnou a po ní (tři soubory ×
dva pohledy × dva režimy, plus úryvek u vlákna na ose), všechny hashe **shodné**. Že je ten render
deterministický, se ověřilo třemi běhy nad nezměněným kódem.

**Proč to není kosmetika:** u #438 se kvůli téhle mrtvé cestě hledal výkonový problém na špatném
místě — zadání znělo „neviditelný diff počítá geometrii svých řádků“ a měření pak ukázalo, že diff
se na geometrii řádku neptá ani vepředu. #438 vyklizení odložilo s poznámkou, že je to vlastní
zadání; tohle je ono.

Testů **4108**, všechny zelené — z toho **10 nových**: `DiffRenderedRowsTests` (nad daty i nad
zdrojáky, s kontrolou měřidla z obou stran) a jeden případ v `DiffJumpTargetTests` na soubor, ve
kterém poznámka `git`u bloky rozděluje. **Ověřeno vloženou regresí** v obou směrech: `EmptyView()`
ve větvi `.pair` stráž shodí a před smazáním `DiffPairView` shodila tvrzení o jediném view.

### #462 — plný běh testů se zasekával na animaci objevení okna

**Na tomhle není co vidět** — je to celé v `Tests/` a v dokumentaci; `App/` se nemění ani o řádek.

Plný `xcodebuild test` se zasekával na **třech posledních suitách** (`komentář pod PR`, `odpovídání
do vláken`, `labely a reviewery`), tedy přesně na těch, které spouštějí podstrčený `gh` jako
podproces, a v hostu se u toho nasbíralo **76 vláken v `-[NSAnimation _runBlocking]`**. Obcházelo se
to během po polovinách. Vypadalo to jako rozbité testy a je to ten druh chyby, kvůli kterému v repu
stojí pravidlo psát výstup do souboru — jednou už kvůli tomu padlo přes půl hodiny na hledání
neexistující chyby.

**Příčinou je ukázání okna, ne SwiftUI a ne obsah.** `orderFront` na okně s výchozí
`animationBehavior` spustí animaci objevení, a ta na macOS běží jako `NSAnimation` v **threaded**
režimu — tedy `dispatch_async` na globální root frontu, ze které si na celou dobu animace drží
vlákno a odpovídá z něj display linku. Změřeno samostatnou sondou: 12 oken ukázaných naráz dá **25
vláken procesu, z toho 14 v `_runBlocking`**; totéž s `animationBehavior = .none` dá **5 a 0**;
tatáž dvojice vyjde i na `borderless` okně **bez jediného view**, a naopak 12 `NSHostingView`ů
v neukázaných oknech nestojí nic. `Tests/Views/` přitom ukazovalo okno na **48 místech** a Swift
Testing pouští suity paralelně.

**A že to zaplatí `gh`, je taky změřené.** Pool má na tomhle stroji strop **75** pracovních vláken
a `SubprocessRunner` z něj bere vlákna na blokující čtení pip. Při 80 obsazených vláknech (pool se
zastaví na 76 — přesně to číslo z hlášení) se práce na téže privátní souběžné frontě dostane na
procesor až za **28,0 s** místo **0,0001 s**, což je nad třicetisekundovým timeoutem `gh`. Odtud
`PublishError.timedOut` u těch tří suit pod zátěží: **jedna příčina, dva projevy**, ne dvě různé
věci.

**Opravou je jeden helper a stráž nad zdrojáky.** Okno se v testech ukazuje jedině přes
`orderFrontUnanimated()` (`Tests/Support/UnanimatedWindow.swift`), který napřed nastaví
`animationBehavior = .none`; hlídá to `UnanimatedWindowTests` — nad **zdrojáky**, ne nad během, ze
stejného důvodu jako u #367 (počet vláken procesu je vlastnost celého paralelního běhu, takže by
tvrzení o něm padalo podle toho, kdo běžel vedle). `App/` se nemění schválně: animace objevení okna
je v aplikaci v pořádku, otevírá se jich pár, ne padesát.

**Co se nepovedlo prokázat, a je to zapsané:** samotné zaseknutí se nereprodukovalo — všech šest
plných běhů (A/B/A/B/A/B) doběhlo, i ty bez opravy. Závěr proto stojí na mechanismu a na číslech,
ne na pozorovaném rozdílu mezi zaseknutým a nezaseknutým během. Změřená je špička vláken hostitele
(bez opravy 88 / 71 / 76, s opravou 42 / 57 / 54) a `_runBlocking` v opakovaných vzorcích — na
poslední dvojici, kde oba měřiče běžely celou dobu, **8 bez opravy a 2 s opravou**. Ty dvě jsou
okno **samotného hostitele** při startu, ne test: `-only-testing` na suitu bez jediného okna dá
`_runBlocking = 1`.

**Slabinou zůstává `SubprocessRunner`**: dokud čte `readToEnd()`, drží každé volání dvě vlákna
sdíleného poolu, takže ho umí zdržet kdokoli, kdo pool obsadí. V aplikaci to nehrozí (oken je pár,
paralelismus review drží `WorkCoordinator`), takže se produkční cesta nepřepisovala; cesta ven,
kdyby to bylo potřeba, je bufferovat z `readabilityHandler`u jako `SubprocessStreamer`.

Testů **4110**, z toho **2 nové** (`UnanimatedWindowTests`: stráž a pojistka, že doopravdy čte
zdrojáky). Rozbor i obě tabulky měření jsou v [`testovani.md`](testovani.md), poznámka o poolu
u podprocesů v [`architektura.md`](architektura.md).

### #452 — tab `Zeptat se`: rozhovor s Claudem nad pull requestem

Osmá záložka PR a **třetí vyjmenovaná session** vedle revieweera a dotažení textu issue (#345).
Odpovídá na otázku, na kterou reviewer nebyl puštěný — *proč tohle vůbec dělá*, *co z těch nálezů
je doopravdy problém* —, a ta se do #452 musela odnést do prohlížeče nebo do terminálu.

**Sada nástrojů je užší než reviewerova**: `Read,Grep,Glob,Bash(git:*)`, tedy bez `ReportFindings`
(nemá co hlásit) a bez `Skill` (skill načtený za běhu si umí říct o odeslání na GitHub);
`--disallowedTools` je **tatáž konstanta** jako u revieweera a obě hodnoty tvrdí test **literálem**,
jako u #345. **Tvrdá podmínka č. 1 se nehnula**: `grep ReviewPublishing App/` vrací týž seznam
a `SingleWayOutTests` prošly beze změny.

**Ukládá se k PR, ne k `headSha`**, a je to zapsaná výjimka z toho, jak se klíčuje všechno ostatní
kolem review: podmínka č. 5 mluví o **nálezech**, tedy o tvrzení proti kódu, kdežto otázka „proč se
ten mutex bere“ pushem nezastará. Rozhovor drží `--resume`, takže druhá otázka navazuje a materiál
se **přepisuje před každou otázkou** (pruh `ví o tomhle PR:` se počítá živě, takže zastaralý snímek
by nad navazující otázkou tvrdil víc, než data unesou). `session_id` se přepisuje po každé odpovědi,
protože `claude --resume` id **může vrátit jiné** — a když nedorazí žádné, staré se zahodí, aby
rozbité navázání rozhovor nepoložilo napořád.

**Kontext jde do promptu jako cesta k souboru** vedle pracovního stromu (precedens #120), ne jako
nástroj — na dotažení nálezů, konverzace a checků by session potřebovala `gh`. Diff v souboru není:
session si ho přečte `git diff base...HEAD`, tedy toutéž cestou jako reviewer.

**Osmá záložka posunula dvě naměřená čísla v pruhu záložek.** Ve výchozím okně 1100 se od #452
kreslí `labels`, tedy **bez `+X −Y`** (vrací se od ~1186 bodů) — je to ta výměna, kterou pořadí
podob předepisuje. A **přibyla čtvrtá podoba** (`compact`, jen ikony bez popisku i u aktivní
záložky): do #452 se na ni nedalo přijít, protože se `icons` i s trojmístnými odznaky vešly do okna
689; s osmi záložkami chtějí 645–711 bodů proti 647, které v nejužším okně jsou, takže by se pruh
v tom krajním stavu zalomil. `compact` se vejde s 598 body. Je to **změna měření, ne názoru**,
a zůstalo u ní zapsané obojí.

**Kolik jedna odpověď stojí, je změřené, ne odhadnuté**: první otázka nad tímhle PR (opus-5, diff
~5 tisíc řádků) vyšla na **$1,56 a 125 s**, navazující jednovětá přes `--resume` na **$0,96 a
6,8 s**. Cenu určuje **kontext, ne délka otázky**. Tentýž zkušební běh navíc **našel dvě věci
v téhle implementaci** a obě se opravily ještě před PR: materiál se skládal jen k první otázce
(pruh `ví o tomhle PR:` se přitom počítá živě, takže by nad navazující otázkou tvrdil víc, než
data unesou) a mrtvé `session_id` se nezahazovalo, takže rozbité navázání by rozhovor položilo
napořád.

**Proklikání otočilo tři zapsaná rozhodnutí a našlo jednu chybu.** Nabízené otázky do té doby jen
předvyplnily pole — odešle je teď **jeden klik**, protože předvyplněná otázka chce druhý klik na
tomtéž místě, kde měl stačit první. Nabídka je navíc **odvozená z pruhu `ví o tomhle PR:`**, takže
se otázka na nálezy nad PR bez nálezů nenabízí (ptala by se na nic) a nese **týž počet**, jaký
hlásí chip — jedno pole chipů jde do obojího, protože dvě čísla o jedné věci na jedné obrazovce
jsou ta třída chyby, kterou u tohohle tabu jednou vyrobil materiál skládaný jinde než pruh. A
přibyl **`Nový rozhovor`** (napřed dokreslený a odsouhlasený v sekci 33 návrhu): zahodí rozhovor,
soubor v cache i `sessionID`, ptá se jednou větou, protože zpátky se to nedá koupit, a v prázdném
tabu se nekreslí.

Ta chyba byla, že **odeslaná otázka zůstala v poli** — a stálo to za rozbor: store obě poloviny
výměny dělal správně, rozbité to bylo **okružní cestou**. Composer používal `DraftTextEditor`, který
text posílá dolů po **odmlce 400 ms** (rozdělané review čtou bubliny v diffu, takže se každý úhoz
zapisovat nedá), jenže tady je to, co se odesílá, **totéž pole**, do kterého se píše: klik trefený
do té odmlky odeslal **starší** otázku a rozepsanou dostal zpátky. Text proto drží composer
(`AskComposer`), store dostane otázku **až při odeslání** a `askDrafts` je od té doby jen záloha pro
přepnutí tabu. Odeslání vrací `Bool`, takže se pole vyprázdní **jen když otázka doopravdy odešla** —
neodeslaná v něm zůstane.

Testů **4196**, všechny zelené — nových je sedm sad kolem rozhovoru (`AskCommandTests`,
`AskTabTests`, `AskPromptTests`, `AskReferencesTests`, `AskStoreTests`, `AppStoreAskTests`,
`AskComposerTests`) a k tomu stráž `AskLogEagerTests`, že se do rozhovoru nevrátí líný seznam
(#361). `AskComposerTests` jedou nad **skutečným oknem a skutečnou klávesou**
(`window.performKeyEquivalent` s `⌘⏎`), protože `Button` je v tomhle okně kreslený SwiftUI a žádný
`NSButton` v hierarchii není — a nad storem se o té chybě nedalo tvrdit nic.

**Zabitá odpověď navíc nesmí nic dopsat.** Zrušení se nepozná jen podle `CancellationError` —
zabíjený `git` ani `claude` o něm nevědí a vyhodí svou vlastní chybu —, takže by po `Zastavit`
přibyla bublina „Nepovedlo se…“ a po `Nový rozhovor` by přistála do právě vyprázdněného rozhovoru
a **zapsala ho zpátky na disk**. Rozhoduje o tom jedno místo pro obě cesty (`AppStore+Ask.handle`);
ověřeno vloženou regresí.

**Poslední kolo Copilota našlo dvě věci a obě byly reálné.** První byla **chybějící hranice cache
v `AskStore`** — `contains` měl jen `delete`, takže `load` četl a `save` zapisoval po cestě, kterou
symlink v rodičovské složce vyvede ven (tvrdá podmínka č. 3). Opravilo se to **jako třída**:
pravidlo se svedlo do nového `CacheFile` a použily ho i `ReviewDraftStore` a `ReviewStore`, které tu
mezeru měly taky — je to store, ze kterého se opisovalo. Ledgery pod kořenem cache stráž vědomě
nedostaly (jejich soubory jsou přímé děti kořene, takže mezi kořenem a souborem není složka, která
by mohla být odkazem); zůstává u nich odkaz na **samotném souboru** jako zapsaná mezera. Ověřeno
vloženou regresí: bez té kontroly `save` cizí soubor mimo cache doopravdy přepsal a `delete` ho
smazal.

Druhá byla, že **měření rozhovoru jelo bez `NSWindow`u**, a dopadla zajímavěji. Mechanismus se
potvrdil (`ScrollView` bez okna obsah nerozvrhne — bez okna vyjde `obsah 0 pt`), ale **závěr ne**:
bez okna byl pevný stack **dražší**, ne levnější (300 bublin 283–308 ms proti 238–257 ms v okně)
a počet vyrobených prvků byl **totožný** (907). Rozhodnutí „pevný `VStack`, ne líný seznam“ tedy
z opraveného měření vychází stejně; čísla v okně jsou 18 ms u dvaceti bublin, 87 u stovky a 242
u tří set, proti 413 ms, se kterými se pevný stack přijal u osy konverzace (#361). Měřidlo od té
doby vypisuje **výšku obsahu a počet prvků**, protože zrovna tuhle chybu z časů poznat nejde.

**Zeleno bylo po většinu práce jen z běhu po polovinách**, protože plný `xcodebuild test` se na
tomhle stroji zasekával na **třech posledních suitách** (`AppStore — komentář pod PR`,
`— odpovídání do vláken`, `— labely a reviewery`): v testovacím hostu se nasbíralo **76 vláken
v `-[NSAnimation _runBlocking]`** a dispatch pool narazil na soft limit 75. **Nebylo to z #452** —
změřeno se **zastashovanými** změnami, se stejným výsledkem na týchž třech suitách. Zapsalo se to
jako #462 a vyřešilo se to tam; od jeho mergnutí do `main` **doběhne plný běh normálně**
(4 196 testů ve 412 suitách za 58 s), takže dělení na poloviny odpadlo.

**Stráž z #462 si u toho vyžádala dvě úpravy v téhle větvi**: `AskTabRenderProbe`
a `AskComposerTests` si okno ukazovaly `orderFront(nil)`, tedy s animací objevení, kterou #462
zakázalo — od merge používají `orderFrontUnanimated()`. Je to přesně ta situace, kvůli které je
ta stráž nad zdrojáky: obě sondy vznikly dřív, než pravidlo, a bez ní by se do `main` dostaly.

## #469 — okno tuhne nad diffem: kolo z #361 se nepřestěhovalo znovu, ale zaniklo

**Zadání znělo „udělej cokoliv, aby se to nesekalo“**, ne „vysvětli to“. Patnáct kol #361 udělalo
kolo levnější a odebralo mu jedno místo — osu konverzace —, jenže se tím **přestěhovalo do diffu**:
dva `sample`y z hořící instance 27. 8. měly `LazySubviewPlacements.placeSubviews` na 25 % vzorků
hlavního vlákna, `FileDiff.diagnosedID` i `DiffRow.diagnosedID` v zásobníku a nula `ConversationRow`.
Věta „nad **Soubory** se tatáž třída kola vrátit může“, kterou #361 nechalo v `docs/testovani.md`
jako výhradu, se tím stala předpovědí.

**Diff proto od #469 nekreslí `LazyVStack`.** Je to vědomá změna pravidla z #361 („líný seznam patří
tam, kde je seznam neomezený“): neomezenost není důvod ten vzor snést, protože kolo je vlastnost
lazy layoutu, ne délky seznamu.

**Samotný pevný stack by ale diff položil, a to se změřilo dřív, než se cokoli rozhodlo.** Nová
sonda `DiffShapeProbe` poměřila pět podob téhož místa a rozhodly dvě věci: pevný stack **bez
nasazených bloků** je v počtu řádků **plochý** (0,17–0,20 s CPU na 150 × 40 pt, ať je řádků 500 nebo
6000) a **třikrát levnější než líný seznam**, kdežto pevný stack **se všemi bloky** stojí 2,96 s na
20 blocích a **21 s** na 108. Cena projíždění tedy roste s počtem nasazených `NSTextView`, ne
s délkou seznamu — a `updateNSView` se při tom gestu nevolá ani jednou, takže to není naše práce.

**Laznost se proto nezahodila, jen přestěhovala z rozvržení do jednoho rozhodnutí.**
`Policy.mountBand(visible:)` řekne, ve kterém pásu obsahu má blok živý `NSTextView`; mimo pás zbyde
`Color.clear` s naposledy změřenou výškou. Nasazených bloků je **šest bez ohledu na velikost diffu**
(změřeno u 500, 6 000, 20 000 i 50 000 řádků; bez okna 20 / 108 / 340 / 840) a projíždění vyšlo
0,73 s u 500 řádků a 0,86 / 0,85 s u 6000, tedy proti líným 0,58 a 0,57 / 0,51 s **flat a ve stejném
řádu**.

**Doloženo je to strukturálně, ne tím, že po opravě nehořelo.** Kolo se za čtrnáct kol #361 nedalo
vyrobit na povel, takže „nehoří“ nedokazuje nic a v téhle větvi to nikde nestojí. Doklad je tentýž,
jakým to #361 doložilo u osy: v evaluačním zásobníku pod řádkem diffu je u `LazyVStack`u
`LazySubviewPlacements` ve **2 vzorcích ze 2**, u pevného stacku v **nule** — a `LazySubviewPlacements`
je jmenovitě ten atribut z hořícího `sample`u.

**Zaplatilo se to prvním rozvržením a je to napsané i tam, kde je to vysoké**: 50 ms u 6000 řádků,
206–304 ms u 20 000 a 983–1534 ms u 50 000 (Debug). Odhad výšky by tu cenu ušetřil a **je zamítnutý**:
obsah pod prstem by měnil výšku pokaždé, když se blok poprvé nasadí, a skok na nález by mířil vedle.
Zbylá odchylka je **0,4 %** a konverguje (46 065 → 46 241 pt u 2000řádkového diffu), kdežto
`LazyVStack` u 6000řádkového diffu odhadoval 99 687 pt tam, kde pevný stack **změří** 112 507 —
**12 % vedle**, a nedorovnal to nikdy; posuvník tedy od #469 lže míň, ne víc.

**Ukotvenou hlavičku souboru uměl jedině `LazyVStack(pinnedViews:)`, a zahodit ji nešlo** — v návrhu
je `.fhead { position: sticky; top: 0 }`, takže je to vzhled. Kreslí se proto jedna přes výřez
(`DiffPinnedHeader`, rozhoduje `Policy.pinnedFileHeader`). **Posouvat každou hlavičku zvlášť je
zamítnuté měřením** (0,83 s CPU navíc na 24 souborech) a `visualEffect`, který by ten posun udělal
zadarmo, **nesleduje hit testing** — a hlavička je celá tlačítko.

**Dvě věci na tom nejsou zjevné a stály kolo měření.** První: rámečky se musí číst v souřadnicích
**obsahu**, ne výřezu — první podoba se ptala každého bloku a každé hlavičky na rámeček ve výřezu,
tedy na hodnotu, která se scrollováním mění, a stálo to 3,5 s CPU proti 0,19 s. Druhá: `DiffViewport`
má **dvě** vlastnosti schválně, protože `@Observable` sleduje po vlastnostech — `band` čtou všechny
bloky a mění se jednou za výřez, `top` se mění při každém snímku a čte ho **jediné** view.

**Co zůstalo nedokázané**, a je to zapsané: že záchvat nepřijde, se tvrdit nedá; osm dalších
`LazyVStack`ů v aplikaci (strom souborů, tabulka nálezů, dění, commity, panel, výpis kroků, fakta,
průběh) **mají strop**, takže u nich platí pravidlo z #361 nezměněné, ale vyloučené to není. A cena
projíždění se u velkých diffů měří **jen na odemčené obrazovce** — pod zamčenou gesto nikam
neposune a všechny podoby vyjdou shodně, což se pozná podle záporného `dojelo na …` ve výpisu sondy.
## #459 — terminál je uvnitř okna, a tvrdá podmínka č. 1 se tím vědomě změnila

`` ⌃` `` vytáhne přes spodek záložky PR **zásuvku se skutečným shellem**, který stojí v kopii repa
toho pull requestu v cache aplikace. Návrh je sekce 35. Do #459 se dal terminál otevřít jedním
tlačítkem v tabu `Průběh` (#453) — je to levné a podmínky se u toho nehnuly, ale pořád to znamená
**odejít z okna** a vrátit se za deset minut.

**Zásuvka, ne devátá záložka**, a je to celý smysl: půlka užitku je vidět diff a **pod ním** výstup
příkazu. Roztahuje se tažením za horní hranu, výška si pamatuje mezi spuštěními a nad zásuvkou
vždycky kus obsahu zůstane — jinak by z ní ta záložka byla.

**Tvrdá podmínka č. 1 se změnila a je to přepsané, ne obejité.** Do #459 v `CLAUDE.md`
i v `architektura.md` stálo, že vestavěný terminál je **zamítnutý**, protože nepůjde uhlídat
testem. Obojí je pořád pravda; uživatel si tu funkci vyžádal jmenovitě a rozhodl, že se za ni ta
záruka vymění. Čte se to jako dvojice: **zůstává**, že aplikace **sama** nic neodesílá a
`ReviewPublishing` je jediná cesta ven **v jejím kódu** — `grep ReviewPublishing App/` vypisuje
**týž seznam** a `SingleWayOutTests` prošly **beze změny**, protože se na ně nesahalo; **padá**, že
se to dá **dokázat testem**, protože ze shellu jde `gh pr merge` i `git push` a ta cesta nevede přes
kód aplikace. Plnou moc má odsud **člověk**, ne aplikace — a **je to napsané na obrazovce**, ne jen
v dokumentaci: v hlavičce zásuvky stojí kapsle `plná práva`, protějšek `čte · neodesílá` z tabu
`Zeptat se`. **Tvrdá podmínka č. 3 platí beze změny.**

**`SwiftTerm` je první závislost třetí strany v tomhle repu** a **třetí vědomá výjimka** z pravidla
„do `project.pbxproj` nesahej“ (po `Signing.xcconfig` a `ASSETCATALOG_COMPILER_APPICON_NAME`).
Verze `1.11.2` je vybraná **měřením, ne opatrností**: `1.20.0` shodí build na
`Validate plug-in "SwiftTermBuildInfoPlugin"` (build tool plugin `xcodebuild` bez
`-skipPackagePluginValidation` neschválí) a `1.16.0` na `cannot execute tool 'metal' due to missing
Metal Toolchain`. Zamítnuté cesty jsou zapsané i s cenou: flag by přepsal **tři** dokumentované
příkazy a od té chvíle by se mlčky spouštěl **každý** plugin každého budoucího balíčku;
`-downloadComponent MetalToolchain` je několikagigabajtová komponenta Xcode kvůli rendereru, který
se v zásuvce nepoužije. **Připnutí drží všechny příkazy v repu beze změny**, `Package.resolved` je
v repu a cena — jsme na verzi z února 2026 — je napsaná.

**Klávesy patří terminálu, a hranice je `⌘`, ne `Control`.** Návrh mluví o `Control`u, jenže hranice
kolem jednoho modifikátoru by nechala venku `⎋` (vim, `claude`) a `⌥↑`/`⌥↓`, kde je `Option`
v terminálu meta. Pravidlo je proto jedna věta — *co nemá `⌘`, patří terminálu*
(`Policy.shortcutYieldsToTerminal`) — a jde ho projít **vyčerpávajícím výčtem nad celým katalogem**
(#441), takže si nová zkratka na `Control`u vynutí rozhodnutí sama. Jedinou výjimkou je `` ⌃` ``,
a rozhoduje o ní **akce, ne kombinace**. Na české mapě funguje i `⌃;`, ze stejného důvodu jako
`⌃+ěščř` u sekcí railu.

**Zabíjí se popředí pty, ne jen shell, a stálo to úvahu navíc.** Knihovní `terminate()` posílá
`SIGTERM` shellu — a to na závazek z #264 nestačí: `claude` spuštěný v interaktivním shellu dostane
vlastní process group (job control), takže by ho signál poslaný shellu **minul** a osiřel by na
`launchd` úplně stejně jako v #351. Zabíjí se proto `tcgetpgrp(childfd)` a **až pak** shell.
K tomu značka v `sessions.json` toutéž cestou jako u review, aby osiřelý shell zabil **další start**
po zabité aplikaci. **Zavření záložky shell zabije, schování zásuvky ne** — `` ⌃` `` je pohled, ne
konec práce.

**Proti návrhu je jedna věc jinak a je zapsaná**: kapsle v hlavičce ukazuje `běží` / `skončil (kód)`,
ne příkaz, který zrovna běží. Zjistit ho znamená ptát se jádra na popředí pty v pravidelném taktu,
tedy zavést v okně další časovač kvůli popisce. Je to méně, než slibuje mockup, ale nic z toho není
nepravda — a `exit 1` se od `exit 0` odliší, což je to, kvůli čemu se na kapsli člověk podívá.
Mockup se kvůli tomu **nepřekresluje** (schvaluje ho uživatel, #286).

Testů **4250**, všechny zelené — z toho **33 nových**: `Policy` výčtem (výška a její ořez, tažení,
kde shell startuje, co se spustí a s čím, dotaz při ukončení) a to podstatné ze storu a z delegáta —
**schování zásuvky shell nezabije**, **zavření záložky ano**, **`Zpět` v dialogu nezabije nic**
a **`PATH` aplikace se do shellu nepředá**.

**Nad tím je sonda se skutečným shellem** (`EmbeddedTerminalProbe`, mimo běžný běh) a našla dvě věci,
které by se z kódu nepoznaly. Zaprvé: shell startuje jako `Ss+`, tedy **session leader v popředí** —
takže `login_tty` proběhlo a job control uvnitř funguje; kdyby ne, `⌃C` v zásuvce by nepřerušilo nic.
Zadruhé: po `kill()` je stav `Z`, a **zombie se počítá jako mrtvý** — `kill(pid, 0)` na nesklizeném
potomkovi pořád vrací nulu, takže první podoba tvrzení hlásila, že shell přežil, i když neběžel.

**A dvě věci se ověřit nedají, změřeně.** Psaní do pty: `exit` poslané do shellu vycházelo náhodně
(z pěti běhů dva) a opakování to nespravilo, protože `send` jde přes druhý `DispatchIO` kanál nad
deskriptorem, jehož první kanál visí na hladové hlavní frontě. A obsah emulátoru vůbec. `LocalProcess` doručuje bajty přes
`DispatchQueue.main` a **hlavní dispatch fronta se v testovacím hostu nedrání vůbec** — z pozadí
zavolané `DispatchQueue.main.async` i `.sync` za pět sekund neproběhly ani jednou, přestože sonda
běží na hlavním vlákně a točí `RunLoop.main.run(until:)`. Sonda proto **nic z emulátoru nečte**
a všechno si zjišťuje z jádra (`lsof` na adresář, `ps` na stav, `exit` jako důkaz, že se do pty píše).
Je z toho pravidlo širší než #459 a je zapsané v [`testovani.md`](testovani.md): **co v aplikaci chodí
přes `DispatchQueue.main`, se v hostu pozorovat nedá.**

**Co ověřuje jedině člověk** (testovací host nedostane aktivaci, takže nemá key okno a stisk nemá
kam sednout, #392, #434): že se zkratky s fokusem v terminálu doopravdy neuplatní, že `claude
--resume` vypadá jako v Terminálu, že změna velikosti okna přeposílá `TIOCSWINSZ` a že po zavření
aplikace nezbyde běžící proces. Seznam kroků je v [`testovani.md`](testovani.md).

**`▶` v tabu `Průběh` zůstává na `Terminal.app`** — přepojení na zásuvku je **#460**.

### M13 — Vlastní PR do konce (milník #15)

Tři issues, které se **musí za sebou**, a proto je rozvrh polovina zadání: **#465** (mergnout
z panelu), **#466** (srovnat s `main` bez konfliktu) a **#467** (řešení konfliktů session).
Všechny sahají do téže nové sekce panelu (`Větev`) a druhá se třetí navíc sdílejí cestu zápisu do
remote, takže souběžně to nejde. Nakreslené je to v **sekci 36** návrhu.

Tvrdé podmínky se v tomhle milníku mění **dvakrát a pokaždé jinak**: merge je osmá metoda výčtu
(rozšíření), kdežto force push a session s `Write`/`Edit` jsou **nové třídy**, které v repu dosud
neexistovaly. Obojí se přepisuje v `CLAUDE.md` včetně toho, co za hranicí zůstává.

### #465 — mergnout vlastní PR z panelu

Do #465 se od hotového review odskakovalo do prohlížeče kvůli jediné věci: zeleno, nezbývá nic
jiného, a mergnout se dá jen tam. Panel dostal sekci **`Větev`** — dva řádky stavu (kam se to
slévá a jestli je větev srovnaná; kolik commitů a jak dopadly checky) a k nim `Mergnout…`
s potvrzením.

**Tvrdá podmínka č. 1 se tím mění vědomě, a je to největší změna, jakou v ní zatím byla.** Do #465
stálo v `CLAUDE.md` i v `SingleWayOutTests` jmenovitě, že `merge` sem nepatří; teď je to **osmá
metoda** `ReviewPublishing`, s pátým volajícím (`MergeSubmission`) a sedmým souborem ve výčtu.
Přepsal se výčet, ne jeho podoba — pořád je to jmenovitý seznam souborů i metod, ne rozsah.
V zákazu zůstává approve mimo review, zavření PR, milník a `deleteLabel`.

Nevratnost se platí **dvěma věcmi navíc**, které ostatní metody nemají: potvrzením s úplným
výpisem (jako #68) a **hlavou v payloadu**. `sha` je pro GitHub podmínka, takže na commit pushnutý
mezi pre-flightem a voláním odpoví `409` a nemergne nic — změřeno na sondě
`prism-review-sandbox#8`, která tam byla pro tenhle účel založená a nakonec mergnutá. Odtud jsou
i fixtures: skutečná odpověď mergu a skutečné tělo `409`.

**Metoda je jedna (`squash`) a je konstantou**, kterou čte payload i potvrzení. `commit_title` se
posílá doslova — bez něj si ho GitHub skládá podle nastavení repozitáře, do kterého aplikace
nevidí —, kdežto `commit_message` **ne**: tělo squash commitu složí GitHub ze zpráv slévaných
commitů, a přesně tak vypadá celá historie `main`u v tomhle repu. Že to tak bude, je **napsané
v potvrzení**, jinak by věta „vypsané je všechno, co se stane“ slibovala víc, než co je vidět.

**O tom, jestli se akce nabídne, rozhoduje `Policy` výčtem.** Na cizím PR se sekce nekreslí vůbec;
na vlastním je tlačítko zašedlé s **vypsanými** důvody (každý vede jinam) — vypnutá brána,
nenačtený stav, konflikt, větev pozadu, chráněná větev, červený check a **vlastní blokující nález**
(ten poslední **od #563 mezi překážkami není**, viz jeho záznam níž).
Červený check merge zakazuje, i když by ho GitHub u nepovinných pustil: zeleno je jediný stav, ve
kterém se dá mergnout bez čtení. Běžící check naopak nebrání.

**Past, kterou issue jmenovalo, se ošetřila a zároveň se nepodařilo vyrobit.** `mergeable`
i `mergeStateStatus` jsou u GitHubu líná pole — dotaz, který je nezastihne hotové, dostane
`UNKNOWN` a sám ten výpočet spustí. Gateway se proto ptá až třikrát. Změřené je, že `UNKNOWN` je
**trvalý stav mergnutého PR** (`PRism#470`), a taky to, že se `UNKNOWN` na živém PR **zastihnout
nepodařilo**: na sondě vyšlo `MERGEABLE`/`CLEAN` hned po založení i po každém ze tří pushů, přes
GraphQL i REST. Opakovaný dotaz je tedy pojistka proti doloženému chování API, ne proti stavu,
který se povedlo vyrobit.

**Počet „o kolik je větev vzadu“ v #465 není**, ačkoli ho návrh kreslí: `mergeStateStatus` ho
nedává a `compare` API by za to číslo stáhlo celý seznam souborů. Přijde s #466, kde bude po ruce
klon v cache a spočítá se lokálně.

Sekce je postavená tak, aby do ní šla přidat **druhá akce** (`Rebase`, #466): je to
`stav + nabídka`, ne jedno tlačítko, a akce se kreslí řadou i s jedním prvkem.

**Po úspěšném mergi se zavírá potvrzení i záložka toho PR** — přidáno do #465 ještě před mergem,
takže se v záznamu rozhodnutí mění jeden zamítnutý řádek na rozhodnutí. Původně se sheet nezavíral
s tím, že mergnutý PR ze seznamu vypadne a zmizela by jediná zpráva o výsledku; s tím, že odchází
i záložka, ten důvod padl — za sheetem není mrtvý tab, ale okno přepnuté jinam. **Jen po úspěchu**:
po `409`, `405` i po spadlé síti zůstává obojí i s hláškou, jinak by ji nebylo kde ukázat, a je na
to test z obou stran (obě regrese ověřené vložením). Pravidlo, že mergnutý PR jde ještě dočíst
a zavřít ho má člověk, ne tik pollingu, se tím **neruší**: mluví o pollingu, kdežto tady záložku
zavírá klik na `Mergnout`. Rozdělané review se zavřením neztrácí — draft leží na disku, takže se
nezavírá s ptaním, ani se nemaže.

### #472 — okno reagovalo pozdě, a nebylo to eager diffem

Ráno po #469 přestalo okno **tuhnout**, ale začalo **reagovat pozdě**: v klidu 0,43 s CPU za minutu,
při práci ale 0,5–0,9 s CPU **na každou sekundu**, a to skoro minutu v kuse. Hypotéza v zadání zněla,
že to násobí pevný diff z #469 — tedy že se vyměnilo zaseknuté okno za pomalé.

**Neplatí, a je to změřené.** `DetailRelayoutMeasurement` staví skutečný `ContentView` nad skutečným
`AppStore` a míchá čtyři osy (scéna, pohon, tab, náplň store). Jedno zneplatnění detailu stojí
**95–116 ms** a **nezávisí ani na délce diffu** (500 proti 2000 řádkům: 99 proti 105 ms), **ani na
tabu** — `Přehled`, kde žádný dlouhý seznam není, vyšel dokonce nejdráž. `DiffView.body` se u toho
**vůbec nepřeloží**. Cenu tedy nedělá eager diff; #469 zůstává, jak bylo.

**Ta čísla jsou z opravené sondy a je to poučení samo o sobě**: první podoba předepisovala rozměr
**obsahu**, a tím zmrazila dotaz na minimum okna (`.windowResizability(.contentMinSize)`) — vyšlo
z ní 33–43 ms, tedy třikrát míň, a **neměřila, co dělá aplikace**. Rozměr proto předepisuje okno.

**Co ji dělá, je hrubost sledované vlastnosti.** `PollingService` držel všech pět hodnot v jednom
`PollState`u, a `@Observable` sleduje po vlastnostech — takže `isRefreshing = true` na začátku tiku
probudilo i každého, kdo četl jen seznam PR. Ten čte `AppStore.author(of:)` → `ownership(of:)`, tedy
to, čím detail pozná, čí PR kreslí. **Tichý tik proto překresloval celé okno včetně diffu.** Po
rozdělení na pět vlastností (tatáž úvaha jako u `DiffViewport` v #469):

| Tichý tik, 2000řádkový diff | do #472 | od #472 |
|---|---|---|
| průchody tělem `PullRequestDetailView` (20 tiků) | 62 | **1** |
| průchody tělem `DiffView` | 69 | **7** |
| průchody tělem `DiffRowView` | 10 143 | **1 029** |
| CPU na tik | 551 ms | **343 ms** |

**Zamítnuto měřením: psát „jen změnu“.** `if pullRequests != merged { … }` vypadá jako druhá polovina
opravy a není — zápis téže hodnoty `@Observable` na tomhle toolchainu **nehlásí** (ověřeno vloženou
regresí; pinuje to `PollObservationTests.writingTheSameValueDoesNotWake`). Ze stejného důvodu se
nesahalo na `forget(whatIsNotIn:)`, který po tiku přepisuje přes třicet map výsledkem `filter`u.

**Průchodů tělem ubylo šedesátkrát, ale cena tiku spadla jen o třetinu** — a zbytek se hledal dál,
protože uživatel po nasazení hlásil, že „ten přechod je takový škubaný a přechází to prostě pomalu“.

**Ten zbytek je rozvržení, a nedá se obejít vedle něj.** Ve `sample`u té fáze je vlastní práce
aplikace **~1,5 %** hlavního vlákna (`AppStore` 21, `Policy` 15, `PullRequestDetailView` 36 vzorků
ze 14 726); zbytek je `GraphHost.flushTransactions`, `NSHostingView.layout` a
`LayoutEngineBox.sizeThatFits`. **Zkusila se tři zlevnění, všechna mechanicky fungují a žádné
cenu nezměnilo** — zkratka na dotaz o minimum okna (94 proti 98 ms), zapamatované výšky bloků přes
přepnutí tabu (5 778 použití z 6 924 dotazů, 422/576 proti 428/602 ms) a skládání uzávěrů jednou za
soubor místo za řádek (8 místo 2 352 alokací, uvnitř rozptylu). Z posledního zbyl **kratší kód**,
ostatní dvě se zahodily; čísla i ověření, že fungují, jsou v [`docs/testovani.md`](testovani.md).

**Co se u toho ale změřilo a je to nejlepší popis té bolesti, jaký zatím existuje:** přepnutí tabu
je **jiný a dražší scénář** než přerovnání — 407–682 ms proti 95–116 ms, a na rozdíl od přerovnání
**roste s velikostí diffu**. Obsah tabu se přepnutím zahodí a staví znovu, takže se platí **první
rozvržení** pevného seznamu z #469: 294 průchodů tělem `DiffRowView` a nasazení **všech** bloků
(50 z 50 proti pěti v ustáleném stavu).

**Ten redesign se pak zkusil — a je to čtvrtý zamítnutý kandidát.** Řádky se seskupily po
šestnácti a úsek mimo pás se nahradil jedním prázdným místem známé výšky (paměť výšek v `@State`
detailu, aby přežila přepnutí tabu; skok na nález si svůj úsek vynucuje, aby kotva v hierarchii
byla). **Mechanicky to fungovalo** — průchodů tělem `DiffRowView` na jedno přepnutí ubylo
**z 294 na 147** —, a **cena se nehnula**: 389/638 ms proti 407/602 ms. Půlka dětí ve stacku
zmizela a nezměnilo to nic, což je zároveň ten nejsilnější doklad, že **cena není v počtu řádků**.
Zahozeno.

**A pak se ta cena našla.** Ablace *slepá kostra* (rail, hlavička a stavový řádek nahrazené
obarvenými obdélníky, takže se měří **tvar**, ne sousedé) ukázala, že **obsah okna byl pružné dítě
`HStack`u**: stack mu při každém rozvržení posílá průzkumné nabídky na pružnost a pružný rámec je
**předá dolů celým detailem** — panelem, pruhem záložek i obsahem tabu. Je to tatáž třída jako #220
a #361, jen o patro výš.

Oprava je jeden modifikátor (`content.fillingSlot(alignment: .topLeading)` v `ContentView`) a na
realistických datech (konverzace 200 uzlů, 48 nálezů, 12 checků, 24 commitů) vyšla:

| Scénář (skutečné okno) | před | po |
|---|---|---|
| tichý tik pollingu | 512 ms | **20 ms** |
| přerovnání (zápis do store) | 104 ms | **10 ms** |
| přepnutí tabu bez diffu | 318 ms | **62 ms** |
| přepnutí tabu s diffem, 500 řádků | 410 ms | **243 ms** |
| přepnutí tabu s diffem, 2000 řádků | 638 ms | **466 ms** |

**Sousedé ani obsah v tom nebyli**: skutečný rail, hlavička a stavový řádek stojí proti slepým
obdélníkům **7 ms**, a táž kostra vyšla 81 ms s plným storem proti 70 ms s prázdným — obsah tedy
dělá **14 %**. Zbylých 86 % byla struktura — a **zpětně to vysvětluje všechny čtyři zamítnuté pokusy**:
zlevňovaly věci **uvnitř** detailu, kdežto platilo se za to, kolikrát se do detailu vůbec sestoupí.

**Zbývá pojmenovaná mezera**: přepnutí tabu **s diffem** stojí pořád 243 ms u 500řádkového a 466 ms
u 2000řádkového diffu, tedy o 180–400 ms víc než přepnutí bez něj. Roste to s velikostí diffu
a první rozvržení pevného seznamu z #469 je nejpravděpodobnější příčina; zkusit se to dá tím, že
se `fillingSlot()` dostane i **dovnitř** tabu, mezi obsah a jeho části.

**Původní ablace ukázala, kde ta cena doopravdy je**: přepnutí mezi dvěma taby **bez diffu**
(`Přehled` ↔ `Kontroly`) stojí **309 ms** proti 410 ms s diffem. **Tři čtvrtiny přepnutí tedy
s diffem nemají co dělat** — je to přestavba detailu samotného (hlavička, pruh záložek, panel,
`.task` kaskáda), která se přepnutím zahodí a staví znovu. Kdo na tom bude pracovat dál, má začít
tam, ne v diffu; a sedm průchodů tělem `DiffView` na dvacet tichých tiků taky nikdo nevysvětlil.

### #476 — přepnutí tabu s diffem: jedno zlevnění a čtyři zamítnutí

Po #472 stálo přepnutí tabu s diffem 466 ms u 2000řádkového proti **62 ms** bez něj a rostlo
s velikostí diffu. Rozklad na třech velikostech ukázal, že je to lineární v počtu řádků — a vzorek
ukázal, že to **není v jejich skládání**: stavba display listu 20 %, `updateNSView` bloku 9 %,
`sizeThatFits` 7 %, **stavba těl `DiffRowView` 1 %**.

**Nasazené je jedno zlevnění**: `lineFrames()` vybírá fragmenty jedním průchodem místo dotazu na
každý řádek — **462 → 433 ms** u 2000řádkového a 225 → 196 ms u 500řádkového diffu. Jeho test hned
chytil dvě **tiché** vady: `usedRect` fragmentu obsahuje `lineFragmentPadding` (rámečky o 5 bodů
vedle) a u zalomeného řádku vrací `boundingRect` šířku celého kontejneru (rozdíl 70–78 bodů). Obojí
by posunulo pilulku na komentář i kotvu ⇧ kliku, aniž by se to kdekoli ohlásilo.

**Čtyři cesty jsou zamítnuté a všechny s čísly** — úseky řádků (7,6 %), zapamatované výšky bloků
(465 proti 462 ms), držení tabu naživu (vzalo by výhru z #472: přerovnání okna 11 → 52 ms) a návrat
`LazyVStack`u (beze změny z #469). **Třikrát nezávisle vyšlo, že cena není v počtu řádků.**

**Zbytek je tedy doložený, ne odstraněný**: přepnutí na tab s diffem stojí 433 ms u 2000řádkového
diffu a je to cena **prvního rozvržení** obsahu, který se přepnutím zahodí a staví znovu. Kdo se
do toho pustí znovu, ať měří **přerovnání okna** jako první — tři ze čtyř zamítnutých se rozbily o něj.

## #460 — `▶` v `Průběhu` pouští session v zásuvce, a zásuvka drží víc relací naráz

Tlačítko `▶` v hlavičce dráhy přestalo otevírat cizí okno a **vytáhne zásuvku** (#459), přepne na
relaci té dráhy a pustí v ní `claude --resume <id>` v pracovním stromě té session. `⧉`
(`Zkopírovat resume`) **zůstává**: kdo si session pouští v iTermu, tmuxu nebo na jiném stroji,
potřebuje text. `Policy.resumeCommand(sessionID:)` a `ShellQuoting` se použily **beze změny**,
takže to, co se kopíruje, a to, co se pouští, se nemá čím rozejít.

**Zadání se během PR rozšířilo, a je to zapsané jako změna, ne jako součást plánu.** První podoba
psala do **jediného** shellu zásuvky, protože sekce 35 nakreslila jeden. Při proklikání se ukázalo,
že to nefunguje v tom stavu, kvůli kterému zásuvka vznikla: aplikace pouští review **paralelně**
(`maxConcurrentReviews` je ve výchozí konfiguraci 3), takže se člověk chce dívat na dvě session
naráz — a jeden shell ho nutil jednu ukončit, aby viděl druhou. Návrh se kvůli tomu překreslil
(sekce 35, `.term-tabs`, poznámka 112) a **brána na vzhled proběhla znovu**, dřív než se sáhlo na kód.

**Zásuvka proto drží N relací** (`TerminalSlot` = pull request + role, kde role je holý `shell`
nebo `session(skill)`) a přepíná se mezi nimi **záložkami**. Klíčem je dvojice, ne jen skill:
pracovní adresář je adresář *toho* PR. Plocha se v SwiftUI klíčuje relací (`.id(activeSlot)`), jinak
by po přepnutí záložky zůstala v hierarchii ta předchozí — `makeNSView` se volá jen při vzniku
representable.

**Strop je pět a vytlačuje se jedině neběžící relace, nejstarší.** Zdola je to `maxConcurrentReviews`
plus holý shell (čtyři jsou tedy běžný stav), shora řádek v hlavičce vedle cesty a kapsle
`plná práva`. Zahodit běžící shell by znamenalo zabít rozdělanou práci kvůli kliknutí, které o ní
nic neví; když neběžící žádná není, nová relace **nevznikne** a řekne se to — mlčky nevzniklá
záložka vypadá jako rozbité tlačítko. **Úklid platí pro všechny relace**: zavření záložky PR jde
přes seznam (`stopTerminals(for:)`), ne přes tu aktivní, protože osiřela by zrovna ta, která nebyla
vidět; ukončení aplikace zabíjí všechno a značku v `sessions.json` má každá relace vlastní.

**Puntík u záložky má tři stavy, i když návrh kreslí dva.** Do #460 stála v hlavičce kapsle
`skončil (kód)` a odlišit `exit 1` od `exit 0` bylo zrovna to, kvůli čemu se na ni člověk podíval;
tři kódy se do hlavičky nevejdou, takže z toho je puntík — ale `crit` znamená **nenulový** konec
a celý kód zůstává v nápovědě. Kód, který **nedorazil**, se kreslí jako klid: je to odpověď
„nevíme“, ne chyba.

**Posílá se celá `shellLine`** — `cd '<strom>' && claude --resume <id>`, tedy tatáž řádka, jakou od
#453 dostával `Terminal.app`. `cd` v ní není nadbytečné ani u vlastní relace: `▶` umí přijít i na
relaci, která už existuje a stojí jinde. **Do běžícího jobu se pořád nepíše** (`tcgetpgrp` jedním
voláním ve chvíli kliknutí, ne v časovači), jen se z toho přestala dělat slepá ulička — zásuvka se
na tu relaci přepne.

**Dvě věci jsou změřené pty sondou**: píše se `CR` (to, co posílá `↵`; `CR` i `LF` projdou stejně,
4 ze 4 v obou fázích, takže rozhodlo pravidlo) a **nečeká se na prompt** (bajty zapsané dřív, než
`ZLE` naběhne, počká linková disciplína — 5 z 5, i s `.zshrc`, který sekundu spí). Cena je jedna
ozvěna řádky navíc nad promptem.

**Resize se měřil, ne opravoval** (`TerminalResizeProbe`, přes `NSHostingView`, aby v cestě stál
i `TerminalSurface`). Šířka okna dojede do emulátoru (1 200 b → 163 sloupců, 700 b → 92, zpátky
1 000 b → 134) a **řádky se u toho nehnou**; jádro ví totéž (138×21 buněk, 1 000×300 px, po zúžení
82×21); a `TIOCSWINSZ` chodí jen na skutečnou změnu — **8** změn na 61 průchodů rozvržení přes
60 bodů. Přeskládání, které je vidět, je proto **reflow scrollbacku**, a `SwiftTerm` ho dělá podle
správné úmluvy: `isReflowEnabled == hasScrollback`, takže se přesází jen normální buffer, kdežto
alternativní (do kterého kreslí celoobrazovkové TUI) se nereflowuje vůbec. Tak se chová
`Terminal.app` i `iTerm`.

**`AppleScriptTerminal` se nemaže** — zůstává bez volajícího i s `NSAppleEventsUsageDescription`,
a je to rozhodnutí na jedno vydání s napsanou podmínkou zániku (specifikace, *Osud
`AppleScriptTerminal`*): shell v zásuvce se zabije se zavřením aplikace, kdežto okno `Terminal.app`
session přežije, a PRism se restartuje po každém mergi. Mrtvé pole z toho nezůstane: do
`AppStore.terminalFailure` od #460 píše `▶` sám.

**Dvě věci našel Copilot a obě byly reálné.** `stopTerminal` zabíjel plochu s **navěšenými
uzávěry**, takže asynchronně ohlášený konec procesu zapsal stav relace, která už v seznamu nebyla
(záznam, který nikdo nekreslí — a po vzniku stejnojmenné relace by ukázal cizí minulost); odpojují
se proto dřív než `kill()`, a značku v `sessions.json` to neohrozí, tu maže `kill()` sám. A `` ⌃` ``
**přepisovalo cestu v hlavičce i relaci, která už běží**, přestože hostitel vrací existující plochu
a nový adresář si nevezme — popiska by tedy ukazovala jinam, než kde shell stojí. Adresář se hledá
jen relaci, která ho ještě nemá.

**Tři věci z druhého proklikání, a dvě z nich se ukázaly jako správné chování.**

**Dotaz na důvěru ke složce se odstranil.** Interaktivní `claude` se v neznámém adresáři ptá
*„Is this a project you created or one you trust?“*; review sessions to netrápí (běží s `-p`), ale
`--resume` v zásuvce ano — a protože **každý PR dostane vlastní pracovní strom**, přišel by ten
dialog u každého PR znovu. Volba ani proměnná prostředí na to **není** (`--help` zná jen `-p`),
takže se zapisuje `hasTrustDialogAccepted` do `~/.claude.json` — což je cesta, na kterou **odkazuje
sám `claude`** ve své binárce. Změřeno, že se důvěra **dědí z libovolného předka**, takže stačí
**jeden záznam na kořen cache**, ne jeden na PR (**opraveno u #479** — do git pracovního stromu se
nedědí, viz níž); klíčem je `realpath`, protože Foundation `/tmp` ani `/var` schválně nerozvíjí.
Je to **první zápis aplikace mimo vlastní cache** a drží ho tři věci: na soubor, kterému nerozumí,
**nesáhne**, zapisuje **atomicky** s přenesenými právy a **jen jednou**.

**Session z `▶` běží v auto režimu** (`--permission-mode auto`). Je to **jiná třída session než ta
z tvrdé podmínky č. 2**: tam jde o session, které pouští aplikace, a jejich sady se **nemění ani
o položku**. Tahle je session, kterou **řídí člověk ve svém shellu** — a **nová práva nedostává**,
protože zásuvka je plnohodnotný shell s kapslí `plná práva`; odpadají dotazy, ne hranice. Z šesti
režimů je `auto` jediný s **vyjmenovanými a čitelnými pravidly** (`claude auto-mode defaults`);
`bypassPermissions` je „bypass all permission checks“ a do repa nepatří. **Napevno, ne v nastavení.**
`⧉` přepínač **nedostane**, takže se `▶` a `⧉` poprvé rozcházejí — skládá je ale pořád jedna funkce.

**Rolování se měřilo, neopravovalo.** Tři otázky, tři měření, **žádná chyba**: kolečko padne do
plochy emulátoru (`hitTest` **v okně** — bez okna vrátí kořen a plochu nenajde, což první podoba
sondy hlásila jako chybu, která není), scrollback má **500 řádků** a výřez se hýbe (`yDisp` 380 →
377), a nad alternativním bufferem se nehýbe. Rozhoduje to poslední: změřeno, že `claude` posílá
`ESC[?1049h` **a k tomu plné hlášení myši** (`?1000h`, `?1002h`, `?1003h`, `?1006h`), takže kolečko
se **doručuje jemu** a terminál nemá kam couvnout — alternativní buffer je z definice bez historie.
Tak se chová `Terminal.app` i `iTerm`.

> **Ten závěr byl z poloviny nepravdivý a opravilo ho #478** (níž): `claude` si o hlášení myši
> doopravdy řekl, ale `SwiftTerm` mu kolečko **nikdy nepředal**, takže se nedoručovalo nikam.

Testů **4373**, všechny zelené — z toho **53 nových**: `Policy` výčtem (kdo smí do zásuvky, co se
vytlačí, co je na záložce, co se řekne), store (**druhá session první nepřebije**, zavření záložky
zabije i neviditelnou relaci, plný strop novou nepustí) a sonda velikosti.

**Co ověřuje jedině člověk**: že se session v zásuvce doopravdy naváže, že přepínání mezi dvěma
běžícími nic neukončí, že se **neobjeví dotaz na důvěru ke složce** (ten dialog je interaktivní)
a jak obsah po přesázení **vypadá**. Do pty se v harnessu psát nedá a obsah emulátoru se odtud
nepřečte vůbec (změřeno u #459).

## #479 — dotaz na důvěru: zapisuje se složka, ve které shell stojí

Po #460 se dialog *„Is this a project you created or one you trust?“* objevoval **dál**, přestože
kořen cache byl v `~/.claude.json` zapsaný jako `true`. Aplikace teď zapisuje důvěru **i té složce,
ve které shell doopravdy startuje** — pracovnímu stromu review, nebo bare klonu —, takže na chování
dědění přestává záležet. Kořen **zůstává**: pokrývá složky, které v době zápisu ještě neexistují.

**Hypotéza z issue se nepotvrdila, a to je hlavní výsledek měření.** Podezření padlo na explicitní
`hasTrustDialogAccepted: false` u bare klonů — že přebije zděděné `true`. Změřeno na `claude
2.1.250` v pty s podstrčeným `HOME`, šest scénářů: `false` se chová **k nerozeznání od
nezapsaného** záznamu a zděděné `true` zůstává v platnosti.

**Skutečná příčina je jinde a je to jediná výjimka z dědění, kterou se podařilo najít: do git
pracovního stromu se důvěra z předka nedědí.** Obyčejná složka i bare klon dědí do libovolné
hloubky (měřeno 1 až 6 pater); složka s `.git` si žádá **vlastní záznam** — nebo záznam na svém
repozitáři. A strom review je přesně to, kam `▶` míří, takže kořen cache dialog nad ním nikdy
nepotlačil. **Bare klony, na které padlo podezření, byly celou dobu v pořádku.**

**Reprodukováno na skutečných datech**, ne na vymyšlených: do podstrčeného `HOME` se **zkopírovala**
skutečná konfigurace (nikdy se do ní nepsalo) a `claude` se pustil ve **skutečných** stromech
v cache. Strom, jehož bare klon je `true`, projde; strom, jehož klon je `false`, dialog vyvolá —
a se zapsanou přesnou cestou nevyvolá. Zapsané `false` **na naší cestě** se proto přepsat **smí**:
změřeno, že si ho `claude` zakládá **sám** při běhu nad složkou, kterou v konfiguraci nemá, takže
to není odpověď člověka „nevěřím“, ale výchozí hodnota záznamu.

**Vyloučila se i jedna alternativa**: `claude` cizí zápis do konfigurace **nepřepisuje** —
značkový klíč zapsaný během jeho běhu (v `t = 1`, `6` a `15` s) přežil ve všech třech případech.

Čtyři pojistky z #460 platí **beze změny**: na soubor, kterému aplikace nerozumí, se nesahá
(a chybějící se ani nezakládá), zachová se, co v souboru je, píše se atomicky s `0600` a jen když
je to potřeba. **Testy na ně měly díru a #479 ji zavřelo** — na práva `0600` se dokumentace
odvolávala, ale tvrzení nebylo nikde, takže je teď: práva zápis přežijí a dočasný soubor po sobě
nezůstane. Ve storu je místo příznaku **množina** zapsaných složek — příznak by po prvním pull
requestu zavřel cestu všem dalším, tedy přesně tam, kde dialog chodil. Výčet složek vydává
`Policy.workspacesToTrust(root:shell:)`: **napřed strom, pak kořen**.

**Hranici cache u toho drží kontrola, ne konstrukce.** Do #479 byla zapisovaná cesta konstanta
(kořen cache), takže tvrdou podmínku č. 3 držel typ; teď je to hodnota z osy review a z checkoutu,
takže ji drží `CacheFile.isInsideCache` — **to jedno místo, kde hranice cache v repu bydlí** (#452).
Zapsat `true` cizí složce do uživatelovy konfigurace je ta nejcitlivější věc, kterou aplikace umí,
a nikdo by to nepoznal; ověřeno vloženou regresí, že bez té kontroly `/Users/o/Projects/PRism`
zapsané `true` dostane.

**Bere se přitom `refusal`, tedy verdikt pro zápis — a to je nález Copilota.** První podoba brala
`isInsideCache`, což je verdikt pro **mazání**: rozbaluje jen **rodiče**, takže symbolický odkaz
uvnitř cache mířící ven by jím prošel, a klíč do konfigurace skládá `realpath`, který poslední
komponentu **rozvine**. Zapsalo by se `true` cizí cestou. Rozdíl obou verdiktů teď hlídá
`CacheFileVerdictTests` — do #479 na `CacheFile` přímý test **nebyl vůbec**, přestože je to jediné
místo, kde hranice cache v repu bydlí.

Testů **4387**, všechny zelené; **jedenáct nových** (tři nad `Policy`, tři nad storem, dva nad
zápisem do konfigurace, tři nad hranicí cache) a tři přepsaná tvrzení ve storu — jejich fixtury se
u toho **přestěhovaly do cache**, protože cesta `/Users/o/…` od téhle změny tvrdí něco, co v provozu
nenastane. **Ověřeno vloženou regresí** — u práv navíc **pásmem**: `Data.write(to:options:
.atomic)` test nechytá (Foundation atributy přenese taky), `removeItem` + `moveItem` ano. Sonda
testem není a nebude:
pouští skutečný interaktivní `claude` v pty, takže by z běhu testů dělala minuty čekání — postup
i **pět pastí**, o které se ta první sonda rozbila, jsou v [`docs/testovani.md`](testovani.md).

**Na tomhle není co vidět a člověk ověřuje jediné**: že se dialog neobjeví ani nad bare klonem,
tedy u PR, na kterém review ještě neběželo. Do pty se v harnessu psát nedá.

**Cestou se opravily zapomenuté značky konfliktu v tomhle souboru** — `, `=======`
a `>>>>>>> origin/main` se do `main`u dostaly s #477 a rozdělovaly záznamy #476 a #460. Odstranily
se jen ty tři řádky, obsah obou stran zůstal.

## #478 — kolečko se v zásuvce nepředalo aplikaci, která si o hlášení myši řekla

**Opravuje závěr z #460 a je to změna zjištění, ne názoru.** Tam se „nejde rolovat nad běžícím
`claude`“ uzavřelo jako správné chování s odůvodněním, že si `claude` zapíná alternativní buffer
**a hlášení myši**, takže kolečko dostává on. **První polovina platila, druhá ne.**

**`SwiftTerm` kolečko aplikaci nepředá nikdy.** `MacTerminalView.scrollWheel` roluje jen vlastní
scrollback — a ten v alternativním bufferu z definice není, takže se nestalo **nic** a `claude`
o kolečku nevěděl. Kliknutí a pohyb myši knihovna přitom předává; chybí jí právě ta jedna půlka.
`Terminal.app` i iTerm kolečko překládají na tlačítka **64 nahoru / 65 dolů** a posílají, proto
v nich rolování nad `claude` funguje.

**Sonda z #460 to nechytla, protože se ptala na špatnou stranu**, a to je z celého issue to
nejpřenositelnější zjištění. Měřila `yDisp`, tedy stav **emulátoru** — a nad alternativním bufferem
je nula správná odpověď **jak když to funguje, tak když ne**. Rozdíl je vidět jedině na tom, **co
odešlo do procesu**, a na to se neptal nikdo. Odtud pravidlo v `docs/testovani.md`: měřidlo, které
vydá tutéž hodnotu pro obě odpovědi, netvrdí nic — a vypadá u toho zeleně.

**`scrollWheel(with:)` se přebít nedá.** `TerminalView` je sice `open`, ale tuhle metodu deklaruje
jako `public override`, a `public` člen se z cizího modulu přepsat nesmí (`overriding non-open
instance method outside of its defining module`, ověřeno překladačem). Kolečko se proto bere
**lokálním odběrem** (`NSEvent.addLocalMonitorForEvents`), který je volaný **před** doručením do
okna. **Zamítnutá** byla druhá cesta — podhled, který si o kolečko řekne v `hitTest`u —, protože
`hitTest` typ události nezná a šlo by to říct jedině přes `NSApp.currentEvent`, tedy přes
domněnku. Kdo si otočku vezme, rozhoduje `claimsWheel`: **napřed obdélník `visibleRect`, teprve pak
hit test**, protože odběr je na celý proces a projde jím i každá otočka nad diffem (#469).

**Druhá půlka „nejde rolovat“ je chyba v knihovně a měřila se zvlášť.** `Terminal.userScrolling` se
v `SwiftTerm 1.11.2` čte **třikrát** a **nezapisuje se do něj z jediného místa** — zápisy, které
v balíčku jsou, míří na stejnojmennou vlastnost **plochy**, a tu zase nikdo nečte. Jsou to dvě mrtvé
poloviny jednoho příznaku, takže každý přiteklý řádek srovná výřez na dno. Změřeno chováním na ploše
800×300 (**21 řádků**) se 400 nakrmenými řádky: po `scrollUp(lines: 20)` je `yDisp` **360**, po
jediném dalším řádku **381**. Jeden řádek výstupu tedy zahodí celou stránku odrolování. Kompenzuje
to zaklesnutí výřezu (`pinnedRow`, `Policy.terminalViewportPin`/`terminalViewportRewind`), které se
vrací jedině **dolů → nahoru**, ruší se návratem na dno a **zahazuje se při přepnutí bufferu** —
jinak by poloha z doby před `claude` ožila ve chvíli, kdy se člověk vrátí do shellu.

**Rychlost je v počtu hlášení**, protože hlášení myši nese jen „cvaklo“. Posílá se proto tolikrát,
o kolik řádků by se posunula historie; křivka je opsaná ze `SwiftTermu` (`calcScrollingVelocity` je
`private`) a že se s ním nerozešla, hlídá test **chováním** — knihovní `scrollWheel` se pustí
napřímo a porovná se posun výřezu.

**Zapomenuté značky konfliktu z #477 se v tomhle souboru opravily dvakrát nezávisle** — tady i na
#479, které mergovalo dřív. Obě větve smazaly tytéž tři řádky, takže je git sloučil bez konfliktu;
zapsané to zůstává u #479 výš.

Testů **4394**, všechny zelené — z toho **21 nových**: `Policy` výčtem (hlásit / nehlásit, směr,
počet, zaklesnutí a návrat) a plocha bez pty (co odešlo do procesu, shoda křivky s knihovnou,
zaklesnutý výřez a **test, který schválně tvrdí chybu cizího kódu**). Všechny tři nové kusy chování
se ověřily **vloženou regresí**.

**Co ověřuje jedině člověk**: že se událost k `handle(wheel:)` doopravdy dostane. Doručování
událostí testovací host nerozpohybuje — je to tatáž hranice jako u fokusu (#184).

## #484 — `slot-cleanup.sh` po sobě uklidí i záznamy slotu z `~/.claude.json`

Skript uklízel bundle, cache, doménu v `UserDefaults`, plist i záznam v LaunchServices — ale ne to,
co si slot nechal v konfiguraci Claude Code. Po zaniklých slotech `a`, `b` a `c` tam ležely cesty
do jejich dávno smazaných cache. Všiml si toho subagent u #479 mimo zadání.

**Do #479 vznikal jeden záznam na repozitář, od #479 na každý pracovní strom review** — a to je
ten důvod, proč to začalo vadit teď: záznamů přibývá řádově víc a slot, který je vyrobil, přežijí.

Uklízí se **klíč rovný kořeni cache toho slotu, nebo začínající jím a lomítkem**. Lomítko je celý
rozdíl mezi slotem `a` a slotem `ab`; hlavní instance (`…/PRism/`) ani cizí projekty se pod ten
prefix nedostanou. Porovnává se s **cestou, ne s tím, co na disku zbylo** — cache je v tu chvíli
o krok dřív smazaná, takže výběr podle disku by nenašel nic a pořadí kroků by se stalo skrytou
podmínkou. A porovnává se s **oběma podobami kořene**, rozvinutou i nerozvinutou: klíč si `claude`
ukládá přes `realpath` a domovská složka umí ležet za symlinkem.

**Sahá se do souboru cizího nástroje, takže platí tytéž čtyři pojistky jako na zápis v aplikaci**
(`ClaudeWorkspaceTrust`): na soubor, kterému skript nerozumí, se **nesahá** (bez `jq` nebo nad
nečitelným obsahem se to jen ohlásí, úklid pokračuje a skončí `3`), zachová se, co v něm je, píše se
**atomicky** přes soubor vedle cílového a **s právy, která měl původní**, a když v něm po slotu nic
není, **nepřepíše se vůbec**. Kontroluje se to **nad výsledkem, ne nad filtrem** (tatáž volba jako
v `bin/slot-config.sh`): než se soubor vymění, musí v něm zbýt nula záznamů pod kořenem slotu
a **přesně tolik ostatních, kolik jich v něm bylo** — jinak se nezapíše nic.

Testů **4408**, všechny zelené — z toho **tři nové** v `SlotCleanupTests`. Cenné je na nich to
negativní: v podstrčeném `HOME` leží vedle záznamů slotu i **sousední slot, jehož jméno tím naším
začíná**, hlavní instance a cizí projekt, a všechny tři musí úklid přežít. Klíče skládá
`ClaudeWorkspaceTrust.key(for:)`, tedy táž funkce, kterou je zapisuje aplikace. **Ověřeno vložením
regrese, dvakrát**: bez lomítka v porovnání zmizí sousední slot (padnou dvě tvrzení), bez kontroly
čitelnosti umře skript na parse erroru `jq` s kódem `5` a **neuklidí ani doménu a databázi**.

**Na obrazovce není co vidět** — je to shell skript, aplikace se nezměnila.

**Zbylé záznamy po slotech `a`, `b` a `c`** uklidí nejbližší běh skriptu v tom kterém slotu, nebo se
smažou ručně; tenhle PR do konfigurace na stroji nesáhl.

## #466 — srovnat vlastní větev s `main`, a první zápis do remote

Druhá věc, kvůli které se od hotového review chodilo do prohlížeče: větev je pozadu za `main`em
a musí se srovnat. Bez konfliktu je to nudná operace — a přesně proto ji od #466 dělá okno. V sekci
`Větev` (#465) přibylo druhé tlačítko **`Rebase`**: rebase v kopii repa v cache a přetlačení
výsledku přes `--force-with-lease`.

**Tvrdá podmínka č. 1 se tím mění, a je to nová třída, ne rozšíření výčtu.** Do #466 aplikace do
remote **nezapisovala vůbec**: `GitHubGateway` je read-only, `RepoCheckout` pracuje lokálně
a `git push` je výslovně v `--disallowedTools` revieweera. Přibyl proto **druhý protokol**,
`BranchPushing`, s **jedinou** metodou `push` a třemi soubory v `App/Publish/` — a ne další metoda
`ReviewPublishing`, protože ten mluví přes `gh` s GitHub API, kdežto tohle přes `git` se serverem.
Slít je do jednoho by znamenalo, že se z výčtu přestane dát přečíst, co odchází kudy.

**Co z podmínky zůstalo**: `grep ReviewPublishing App/` vypisuje **týž seznam** a jeho tvrzení
v `SingleWayOutTests` prošla beze změny; `GitHubGateway` je pořád bez zápisu; `RepoCheckout`
rebasuje, ale **nemá čím nic odeslat**; brána je tatáž (`PublishScope`); pusher **není pole**
`AppStore`; `Bash(git push:*)` zůstává session zakázaný. Podrobný rozbor je
v [`architektura.md`](architektura.md#zápis-do-remote--branchpushing-466), zdůvodnění změny
v [záznamu rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--zápis-do-remote-466).

### Dva guardy, oba změřené spuštěním

**První — cílem smí být jedině hlava vlastního PR, posuzováno proti datům pull requestu.** Pre-flight
ověří **pět** věcí: autora, fork (`isCrossRepository`), stav PR, jméno větve a hlavu. Jméno větve si
nastaví kdokoli na cokoli, takže shoda jména by byla kontrola, která jenom **vypadá** jako kontrola;
`isCrossRepository == nil` je proto zákaz, ne povolení — `origin` v klonu aplikace je **základní**
repozitář, takže by push u PR z forku mířil jinam, než na co se člověk dívá.

**Druhý — `--force-with-lease` s vypsanou hodnotou, nikdy holé `--force`.** Změřeno na
`prism-review-sandbox` z klonu naklonovaného **přesně jako ten aplikace** (`--bare
--filter=blob:none`, refspec `+refs/heads/*:refs/heads/*`):

| Pokus | Výsledek | Hlava na remote po pokusu |
|---|---|---|
| lease čeká `65aff25`, na remote leží cizí `9bb4352` | `! [rejected] … (stale info)`, kód **1** | zůstala cizí |
| **holý** `--force-with-lease` bez hodnoty | `! [rejected] … (stale info)`, kód **1** | nezměněna |
| lease čeká `9bb4352`, tedy to, co tam je | `+ 9bb4352…2bf096a (forced update)`, kód 0 | přetlačeno |
| **kontrast: holé `--force`** s toutéž zastaralou znalostí | `+ f3e243e…2bf096a (forced update)`, kód 0 | **cizí commit zahozen** |

Dvě věci z toho: **rozdíl je doložený, ne teoretický** (v téže situaci, ve které lease odmítl a cizí
commit nechal, ho `--force` zahodilo), a **vypsaná hodnota je nutnost, ne opatrnost** — holý lease si
očekávanou hodnotu bere z remote-tracking refu, a ten v klonu aplikace **neexistuje** (`git config
--get-all remote.origin.fetch` nevypíše nic, `for-each-ref refs/remotes/` je prázdný), takže selže
i tam, kde se nic nepohnulo.

### Poloha větve: `mergeStateStatus` na to neodpovídá

**Změřeno na `prism-review-sandbox#9`** a je to jádro toho, jestli se akce vůbec nabídne: větev
o commit pozadu vrátila `mergeStateStatus: CLEAN`, kdežto GraphQL `ref(master).compare(headRef:)`
`aheadBy: 1, behindBy: 1`. `BEHIND` GitHub vydá **jedině tam, kde to vyžaduje ochrana větve**;
jinde je „pozadu“ stav, o kterém `mergeStateStatus` mlčí, protože mergi nebrání. Kdyby se
rozhodovalo podle něj, akce by se na většině repozitářů nenabídla nikdy.

**Do #465 tady stálo, že počet přijde z klonu v cache** — to se změnilo a je to vědomé: klon by ho
dal až po `fetch`i, tedy až po práci na síti, kdežto panel ho potřebuje hned při otevření PR. Cena je
jeden GraphQL dotaz na dvě pole, jako **druhé volání uvnitř téže metody** protokolu (`fetchBranchStatus`),
ne jako druhá metoda: sekce se ptá na jednu věc a dvě metody by znamenaly dva stavy, dvě cache a dvě
různá „nevím“ v jednom řádku panelu. Číslo teď stojí v panelu jako `o 4 commity vzadu`, tak jak to
kreslí návrh.

### Dva kroky, a dělí se podle vratnosti

**Změna z proklikání, ne ze zadání.** Původní implementace byla jedno kliknutí, které přehrálo
commity a hned přetlačilo. Na pauze to neobstálo, a bylo to správně: **rebase** je vratný (běží
v cache, nic neopouští stroj), **force push** ne. Rebase proto zůstal na jedno kliknutí a přetlačení
dostalo **potvrzovací sheet** s úplným výpisem (`Co odejde`: větev, počet commitů, nová hlava, hlava
pro lease), výstrahou o pojistce a tlačítkem `Force push` **bez výchozí akce**.

Hranice je **vratnost, ne složitost** — tatáž, podle které má sheet merge (#465) a nemá ho label
(#392). Sheet a ne tlačítko v panelu proto, že návrh (sekce 36) `Force push` kreslí v patičce
sheetu i pro konfliktní cestu, do 300bodového panelu se nevejde výstraha o lease, a repo u nevratných
věcí potvrzuje výpisem.

**#467 tím dostává hotovou půlku své práce**, a je to v záznamu rozhodnutí schválně: sheet, výpis,
výstraha i obě tlačítka existují. #467 do **téhož** sheetu jen přidá, co session udělala s konflikty,
a diff toho, co vzniklo.

**Mezi kroky je stav `rebased` — normální, ne porucha.** Drží ho panel (hláška s `Force push…`
a `Zahodit rebase`; `Zavřít` u ní schválně **není**), hledá se v cache při každém otevření vlastního
PR (`syncWorktreeState`) a **druhý rebase se nad ním nenabízí** — přehrát commity znovu nad
výsledkem, který neodešel, by tu práci zahodilo potichu.

### `Co odejde` počítá dvě různé věci a obě se jmenují

**Pátý nález z proklikání**, ze screenshotu sheetu. Změřeno na `#10`: přehrál se **jeden** vlastní
commit, ale refu na remote chyběly **dva** — rebase dostal do historie větve i ten commit z base,
kvůli kterému byla pozadu. `commitů 1` bylo pravdivé, ale odpovídalo na jinou otázku, než jakou
klade nadpis.

Vypisuje se proto `rebasedFrom..HEAD` (co na větvi bude), čísla jsou dvě a pojmenovaná (`přibude`,
`z toho tvých`) a commit z base má v seznamu značku. Nad výpisem přibyl nadpisek. `replayed` je
zpátky vlastní číslo — nejsou to dvě čísla o téže věci, ale dvě různé veličiny.

### Potvrzení force pushe vypisuje commity

**Čtvrtý nález z proklikání**: `Co odejde` říkalo *kolik* commitů, ne *které* — a potvrzení
u nevratné akce má být místo, kde se přečte celý payload. Vypisuje se krátká sha **po rebasu**
(dá se po pushi porovnat s GitHubem) a první řádek zprávy.

Strop je **osm**, zbytek se počítá (`a další N`); vnořený scroll byl zamítnutý, protože sheet je
rolovací plocha už teď. Ověřeno renderem na 50 commitech, že strop drží a výstraha o lease zůstává
vidět bez rolování, a na titulcích přes 120 znaků, že se zalomí. **Selhání nevzniká jako prázdný
výpis**: když se `git log` nepřečte, mezistav nevznikne vůbec.

### Po force pushi se čeká na hlavu, ne na `mergeable`

**Třetí nález z proklikání** („po force push nejde mergnout“) a uživatel rozhodl, že se řeší tady,
ne vlastním issue. Změřeno na `prism-review-sandbox#10` (čtyři force pushe): hlava (`headRefOid`) je
aktuální po **1,45–2,16 s**, `mergeable` usazený po **0,65–2,74 s**. Detail načtený hned po pushi
tedy nese **starou** hlavu — a merge s ní skončí na `409`, protože ji posílá v payloadu.

**Past je, že `mergeable` se usadí dřív, než dorazí hlava**, takže ta usazená odpověď platí pro
starou hlavu; čekat na `mergeable != UNKNOWN` by bylo **zavádějící**, ne jen nedostatečné. Rozhoduje
proto shoda hlavy: `awaitPushedHead` se ptá `fetchHeads` (`cost = 1`), dokud PR nehlásí sha, kterou
jsme pushnuli. Stráž z #465 to neporušuje — čeká se na **známý fakt**, ne na líné pole, strop je
tvrdý (8 × 0,4 s) a po jeho vyčerpání se nic netvrdí.

Spravilo to i `syncWorktreeState`: přerovnaná větev se pozná tím, že hlava stromu není hlavou PR —
se starou hlavou by po pushi nabídla pushnout znovu.

### Sheet se po úspěšném force pushi zavírá

Jako u mergu a **jedině po úspěchu**; záložka se ale **nezavírá**, na rozdíl od mergu. Zavírá se na
**přechodu stavu**, ne za `await push()`: ten čeká i na úklid (a ten na hlavu), takže by sheet nad
hotovým pushem visel několik sekund. Výsledek nese **panel** hláškou, kterou store nastavuje dřív,
než úklid začne — je na to test, protože bez něj by se ta informace zavřením mohla ztratit.

### Akce se jmenují `Rebase` a `Force push`

Rozhodnutí uživatele, které má přednost před pravidlem o českých uživatelských textech: gitové
operace se v téhle branži nepřekládají. Mění se **jména akcí**, ne próza okolo. Jméno základu
z popisku zmizelo, protože ho nese řádek stavu i nápověda — a `Srovnat s main` mělo 87 bodů, se
kterými tři tlačítka v řadě potřebovala 279 z 278 dostupných.

### Poloha větve se přeptává, protože razítko PR na ni nesedí

**Druhý nález z proklikání.** Panel tvrdil `srovnaná` nad větví o commit pozadu a nespravilo to ani
obnovení, ani zavření a otevření záložky — jedině restart. Změřeno na `prism-review-sandbox#9`, že
posunem základu se `updated_at` pull requestu **nezmění** a `base.sha` ani `baseRefOid` živou hlavu
základu nenesou, takže stav klíčovaný razítkem PR se o ten posun nemá jak dozvědět.

Sekce `Větev` proto obnovuje **po polovinách**: slévatelnost dál podle `updatedAt` (stráž z #465
beze změny), poloha větve přeptáním v tiku u otevřeného vlastního PR. Není to polling `mergeable` —
`compare` nad refem je hotová hodnota, `cost=1` a 0,51–0,62 s, kdežto `mergeable` je líné pole,
které se dotazem teprve spouští. Strop je nejvýš jedno PR na tik.

Cennější než ten nález je, **proč prošel testy**: test na cache existoval, ale hlídal jen směr
„neptá se, když se nic nezměnilo“. Druhý směr se s tehdejším fakem ani napsat nedal.

**Pojistka, která z rozdělení vypadla a v zadání nebyla**: lease se skládá z hlavy, **ze které se
rebasovalo**, ne z aktuální. Mezi rebasem a potvrzením se hlava PR může pohnout, a s aktuální
hodnotou by lease po cizím pushi **prošel** a ten commit přepsal. Takhle na něj narazí pre-flight
(`headMoved`) a nepřetlačí nic.

### Rozdělaný rebase je stav, ne chyba

Rebase běží ve **vlastním** stromě v cache (`<pr>-sync`), ne v tom od review — ten drží kód, proti
kterému platí nálezy a ve kterém stojí shell v zásuvce, a přehrát ho pod nimi je přesně ta tichá
divnost, které se tvrdá podmínka č. 5 vyhýbá. Klíčuje se **jen pull requestem**, aby se rozdělaný
rebase našel i po restartu aplikace.

Konflikt se **zahodí** (`git rebase --abort`) a řekne se to; když se zahodit nepovede, zůstane v cache
a v panelu se objeví věta s tlačítkem **`Zahodit rebase`**. Samo zahazování z okna přitom **maže
strom**, ne `rebase --abort`: od rozdělení akce se zahazují dvě různé věci a `--abort` umí jen
rozdělaný rebase — nad dokončeným by neudělal nic. Že `worktree remove --force --force` zvládne
i strom uprostřed rebase, je změřené integračním testem. Hledá se přitom **při každém otevření
vlastního PR**, ne jen po neúspěšném pokusu: aplikaci zabitou uprostřed rebase nemá kde nic zapsat.
Poznat ho jde jedině `gitem` (`rev-parse --git-path rebase-merge`) — u pracovního stromu ta složka
leží **uvnitř klonu**, ne ve stromě, takže dotaz `FileManageru` na `<strom>/.git/rebase-merge` by vyšel
prázdný. **Vlastní řešení konfliktů je #467**, ne tohle.

**`alreadyInSync` není `pushed(0)`** a **`unfinished` není `failed`** — „nic se neposlalo“ a „poslalo
se nula commitů“ jsou dvě různé věty a jenom jedna z nich je pravda; a z rozdělaného rebase plyne
jiný další krok než ze selhání. Když rebase vydá tutéž hlavu, **nepushuje se vůbec**.

### Co se u toho našlo v dokumentaci

Dvě věci, které #465 nedotáhlo a srovnaly se tady: `docs/architektura.md` tvrdila, že
`GitHubGateway` má **dvacet jedna** metod, ačkoli `fetchBranchStatus` byla dvaadvacátá; a `BranchStatus`
ani `BranchStatusState` nebyly v tabulce doménových modelů vůbec.

### Testy

Testů **4491**, všechny zelené — z toho **48 nových**. Nejcennější jsou ta negativní: bez povolení,
na cizím PR, na PR z forku, bez odpovědi o původu větve, nad konfliktem, nad rozdělaným rebasem
a při nezměněné hlavě se `git push` **nespustí** (měří se to zápisem argumentů podstrčeného `gitu`,
protože fake pusher by se do store podstrčit nedal — tvrdá podmínka č. 1 mu tam nedovolí ani
továrnu).

**Nejcennější z celého rozdělení** je ale test, který tvrdí, že **první krok nepushuje**: rebase
doběhne, v cache leží srovnaná větev a `git` se nespustil. Kdyby se to někdy „zjednodušilo“ zpátky,
pozná se to tam — ověřeno vloženou regresí, na kterou zareagovalo **pět** testů.

Vedle nich **integrační test proti skutečnému `gitu`** (`RealBranchRebaseTests`, remote je `file://`):
že se commity doopravdy přehrají, že se strom review nepohne, že se konflikt pozná a rebase zahodí,
že se rozdělaný rebase **najde a nepřepíše**, že se **přerovnaná větev najde i bez paměti aplikace**
(tedy po restartu), že nedotčený strom **není** přerovnaná větev, že se zahodit dá **i dokončený**
rebase a že neznámý základ skončí chybou, ne konfliktem. Tuhle půlku se namockovat nedá.

**Ověřeno vložením regrese, šestkrát**: první krok, který pushne sám, položí **pět** testů
(nejhlasitěji „Rebase nepushuje a skončí mezistavem“); `switch detail?.isCrossRepository` položí
tvrzení o nenačtené hlavičce. A k tomu čtyři z prvního kola: holé `--force` místo leasu položí
`SingleWayOutTests`
i `GitBranchPushTests`; vyndaný guard na autorství položí „Na cizí pull request se nepushuje“
(a pusher pak pushne); `["push", "--force"]` složené ve `AppStore+BranchSync` položí tvrzení, že
se push skládá jen na jednom místě; a `?? false` v dekodéru `isCrossRepository` položí tvrzení, že
chybějící pole je „nevím“, ne „ne“.

**Na obrazovce vidět je** — druhé tlačítko v sekci `Větev`, počet commitů vzadu v řádku stavu, věta
o tom, jak srovnání dopadlo, a potvrzovací sheet přetlačení. **Mockup (sekce 36) je překreslený
a publikovaný** ve stejném commitu: přibyl mezistav v panelu, potvrzení a dvě poznámky o tom, proč
se dělí podle vratnosti.

## #421 — tělo `DiffView`u se při tichém tiku pollingu pořád špiní (změřeno, nezavřeno)

Zadání #421 bylo z jiného soudku než ostatní: nejdřív **zjistit, jestli ta vada ještě je**, protože
mezi jejím záznamem (2026-08-23) a dneškem prošly tři opravy téhle třídy — #469 (`LazyVStack` z diffu
pryč, pevný `VStack` a nasazování bloků), #472 (`PollState` rozdělený na pět vlastností) a #476
(`lineFrames()` na jeden průchod).

**Vada je pořád tam, a pohonem je tik pollingu.** Naměřeno nad usazeným oknem (201 bloků kódu,
1 210 prvků, split, 1512×874) — čísla, postup a co z nich plyne jsou
v [`docs/testovani.md`](testovani.md#co-zašpiní-tělo-diffviewu-nad-nečinným-diffem-421):

| úsek | `DiffView` | `DiffRowView` | `DiffRow.id` |
|---|---|---|---|
| nečinnost 5 s | 0 | 0 | 0 |
| 10× tentýž rozsekaný běh smyčky **bez tiku** | 0 | 0 | 0 |
| **10 tichých tiků pollingu** | **6** | **1 182** | **2 541** |
| kontrola měřidla (přepnutý pohled diffu) | 4 | 788 | 1 656 |

Co se z toho **přišpendlilo**:

- **`LazyVStack` z toho zásobníku po #469 doopravdy zmizel.** `changed` vstup je dnes
  `StaticBody<…VStack<ForEach<Array<FileDiff>…`, ne `…LazyVStack<…`. Změnila se tedy **cena** jednoho
  zašpinění, ne to, že k němu dochází — zadání #421 tipovalo, že s `LazyVStack`em zmizí i vada, a to
  je vyvrácené.
- **Cesta na diff nevede přes data, a #472 drží.** Z jednadvaceti čtení, která okno nad nečinným
  diffem dělá, probudí tichý tik **jediné** — `isRefreshing`. Ani `diffState`, ani `expansion`, ani
  `isFolded`, ani `pullRequests`, ani `ownership`.
- **Není to práce po úspěšném tiku.** Bisekce přes všech pět kroků `afterSuccessfulTick`
  (`startAutomaticReviews`, `announceNewPullRequests`, `refreshStaleHeads`, `refreshOwnActivity`,
  `loadDailySpend`) dá **nulu**; celý tik dá 6.
- **Chrome okna to ztrojnásobuje.** Bez hlavičky a stavového řádku (jen detail PR) dá deset tiků
  `DiffView=2`, s nimi `DiffView=6`.

**Kde zbývající pohon je:** ne v tělech a ne v datech, ale v **rozvržení**. Během tiku se změřená
**výška** plochy diffu skáče (643 → 659 → 643 → 675 bodů, šířka konstantní 1388) a každý ten skok
přepíše `viewportHeight` v `@State`u `DiffView`u — což je průchod tělem. V nečinném úseku ani v úseku
bez tiků se nezmění ani jednou. Odkud těch 16 a 32 bodů je, se najít nepodařilo; jedna hypotéza je
**vyvrácená** — hlášení ve stavovém řádku (`AppNoticesView`) to nejsou, v té scéně žádné nesvítí ani
se nemění.

**Oprava, která se zkusila a zahodila.** `store.isRefreshing` se čte **v těle `ContentView`u**
dvakrát (tlačítko `⟳` a povolení pro `⌘R`) a mění se dvakrát za tik, takže to vypadalo na tutéž vadu
jako #472, jen o patro výš — hrubé **místo čtení** místo hrubé vlastnosti. Přestěhování do dvou
vlastních views se napsalo a **změřilo, a pak zahodilo**:

| | `ContentView` | dvě nová views | `DiffView` | `DiffRow.id` |
|---|---|---|---|---|
| jak to je | 13–21 | — | 6 | 2 541 |
| s přestěhováním | 9 | 9 + 9 | 6 | 2 541 |

Kořen okna se tedy špiní o pár průchodů méně, ale **celkem průchodů tělem přibude** a na tom, co je
drahé, se nezmění **nic**. Počitadlo `ContentView`u se navíc mezi běhy hýbe (13–21), kdežto
`DiffView` a `DiffRow.id` vyjdou do jedničky stejně — je to tedy ze tří sloupců ten nejhůř
měřitelný. Je to učebnicové „zlevnění, které práci jen přesunulo jinam“
(pravidlo z #275), takže do repa nešlo — a zapisuje se to sem proto, aby to příště nikdo nezkoušel
jako opravu #421 znovu.

**Issue proto zůstává otevřené** — „hotovo“ z jeho zadání (odstranit pohon, ne zlevnit následek)
splněné není. Dopsaná je do něj mapa toho, co je vyloučené a kam se jít podívat.

Testů **4412**, všechny zelené — z toho **jeden nový** (`PollObservationTests`, ověřený vloženou
regresí) a tři nové sondy pod `PRISM_MEASURE`. Sada sond je od téhle změny **`.serialized`**, a je to
podmínka: `RenderDiagnostics.current` je jedna hodnota na proces, takže dvě sondy naráz si do sebe
sbírají a navzájem si ji nulují (naměřeno — `DiffView` vyšel 9 místo 6 a úsek `kontrola měřidla`
vydal nulu, tedy „nezašpinilo se“ nad tím, co se právě zašpinilo). Je to tatáž třída jako #367.

**Na obrazovce není co vidět**: aplikace se nezměnila, přibyly jen sondy, jedno tvrzení
a dokumentace.

## #421, druhé kolo — čísla z prvního kola neplatila, protože měřidlo lhalo dvěma způsoby

Druhé kolo mělo přeměřit základ (mezi tím se mergnulo #152 a další) a pokračovat po stopě „skáče
výška plochy diffu“. Přeměření vydalo `DiffView=26` proti dřívějším 6, tedy na první pohled
**čtyřnásobnou regresi** — a to bylo špatně. Regrese žádná není; rozbité bylo měřidlo, a to
**dvakrát nezávisle**:

- **Testovací host pracoval v cache aplikace.** `CFBundleName` skládal `PRISM_SLOT_LABEL`, který měl
  v `project.pbxproj` **prázdnou** výchozí hodnotu, takže `xcodebuild test` pouštěl celou aplikaci
  nad `~/Library/Application Support/PRism`. Od #527 si tím při každém běhu testů **obnovil otevřené
  záložky uživatele**, dotáhl k nim detail i diff **skutečnými** dotazy na `gh` a vykreslil je ve
  svém okně — a `RenderDiagnostics.current` je jedna hodnota na proces, takže se ty průchody tělem
  přičetly k sondě. Poznalo se to podle `ContentView`u ve scénáři, ve kterém žádný `ContentView`
  není, a podle **druhého** `DiffView`u o 52 bodů užšího (rail hlavního okna). Je to **čtvrtý projev
  téhož kořene jako #367 a #411** a #411 to nechalo otevřené: identita hostitele stojí na dvou
  hodnotách a výchozí dostala jen jedna.
- **`spinMainRunLoop` drží hlavní actor.** Sonda se usazovala `spinMainRunLoop(seconds: 2)`, což je
  synchronní smyčka: rozvrhne okno, ale rozdělanou práci scény na hlavním actoru (`.task` v detailu,
  dotažení konverzace, značky `Prošlo`) k ní nepustí. Ta se rozběhla teprve v úseku, ve kterém sonda
  poprvé `await`la — a to byl zrovna ten „s tiky“. K tomu `FakeTimeSource.sleep(for:)` se vrací
  **hned**, takže smyčka `keepFresh()` startovaná `ContentView`em hořela tak rychle, jak jí hlavní
  actor dovolil.

**Po opravě jsou čísla opakovatelná do jedničky** a jeden závěr prvního kola je **vyvrácený**:

| úsek | `DiffView` | `DiffRowView` | `DiffRow.id` | dotazů na `gh` |
|---|---|---|---|---|
| nečinnost, běh smyčky bez tiku, **úloha na hlavním actoru bez tiku** | 0 | 0 | 0 | 0 |
| **10 tichých tiků** | **10** | **1 970** | **4 140** | 20 |
| 10 tiků **bez zdržení** (`isRefreshing` se nestihne projevit) | 10 | 1 970 | 4 140 | 20 |
| **10 tichých tiků, jen detail PR bez chromu okna** | **11** | **2 101** | **4 422** | 20 |

- **Chrome okna cenu neztrojnásobuje** — bez hlavičky a stavového řádku je **tatáž**. „Pohon sedí
  v hlavičce a ve stavovém řádku“ z prvního kola tedy neplatí; vzniklo to z toho, že cizí scéna
  hostitele přispívala jen do jednoho ze dvou scénářů.
- **Skoky výšky `623 → 639 → 623 → 655` patří usazování scény, ne tiku.** V úseku s tiky se
  `viewportHeight` nezmění ani jednou. Stopa, na které první kolo skončilo, byla vedle.
- **Není to `isRefreshing`** (nezdržený tik dá totéž), **není to `UserDefaults`** (nula změn domény
  za úsek), **není to `availableWidth`** ani **kotva scrollu z #527** (ablace obojího dá totéž).
- **Tik nezmění ve storu ani jedno pole**: nová sonda projde `Mirror`em **234** uložených polí
  `AppStore`u i jeho vnořených objektů a po tiku se liší **jediné** — log dotazů na fake gateway.

**Co z toho zbylo jako oprava v repu:** vlastní cache hostitele (`PRism-testhost`) a čtyři změny
měřidla — usazení podle počitadel místo podle času, hodiny, které doopravdy spí, počet dotazů na
`gh` u každého úseku a kontrolní úsek s úlohou na hlavním actoru. K tomu dvě tvrzení
v `ProcessPreferencesTests` (kořen cache za běhu, `PRISM_SLOT_LABEL` nad `project.pbxproj`), obě
ověřená vloženou regresí.

**Zúžení pro třetí kolo je konkrétní a nepříjemné:** tělo `DiffView`u se přeloží **1× za tik, a
všechny jeho vstupy jsou přitom shodné** (doloženo výpisem z těla — jedenáct identických řádek),
kdežto tělo rodiče se nepřeloží vůbec. Zbývá `forget(whatIsNotIn:)` s pětadvaceti bezpodmínečnými
přiřazeními map a **jméno toho, kdo z nich tělo zneplatní**; hledat se to musí **uvnitř** tiku, ne
po něm, protože po tiku je stav totožný. **Issue proto zůstává otevřené** — dořešilo ho třetí kolo
o záznam níž a to zúžení bylo správné (map je jich osmatřicet, ne pětadvacet, a ta hledaná se jmenuje
`diffSearches`).

Testů **5127**, všechny zelené — z toho **dvě nová tvrzení** a jedna nová sonda; dva starší testy
(`SmokeTests.appPresentsItselfAsPRism`, `CacheLayoutTests`) se musely přepsat, protože tvrdily
rovnost s `PRism`, což je zrovna ta vada.

**Na obrazovce není co vidět**: aplikace se nezměnila, změnil se testovací host, sondy
a dokumentace.

## #421, třetí kolo — pohonem byla jedna mapa, jejíž hodnotu nejde porovnat

**Hotovo, issue zavřené.** Zúžení z druhého kola („tělo `DiffView`u se přeloží 1× za tik a všechny
jeho vstupy jsou přitom shodné; zbývá `forget(whatIsNotIn:)`“) vedlo na **jednu řádku**:

**`diffSearches` je jediná z osmatřiceti map, které tik prořezává, jejíž hodnotu nejde porovnat.**
`@Observable` nehlásí zápis **téže** hodnoty — na tom stojí #472 a je to důvod, proč se ostatních
sedmatřicet map přiřazuje bezpodmínečně. Ta suprese ale platí jedině tehdy, když se ty dvě hodnoty
dají **porovnat**, a `DiffSearchState` je `@Observable` **třída** (schválně, kvůli #472), takže
`[DiffSearchKey: DiffSearchState]` `Equatable` není. Bezpodmínečné `x = x.filter { … }` proto budilo
své čtenáře při **každém** tichém tiku — **i nad prázdnou mapou**, tedy u každého, kdo v diffu nikdy
nehledal. Od #421 se tam zapisuje jen při změně; `count` stačí, protože `filter` umí jedině ubrat.

**Změřeno A/B/A/B** nad tímtéž buildem (rameno se přepínalo proměnnou prostředí), usazené okno,
18 nasazených bloků, 535 prvků, split, 1512×874:

| úsek, 10 tichých tiků | s vadou | po opravě |
|---|---|---|
| `DiffView` | 10, 10 | **0, 0** |
| `DiffRowView` | 1 970, 1 970 | **0, 0** |
| `DiffRow.id` | 4 140, 4 140 | **0, 0** |
| `ContentView` / `PullRequestDetailView` | 20 / 20 | 20 / 20 |
| kontrola měřidla, `DiffView` | 4 | 4 |

Spodní dvě řádky jsou to, čím se ta nula dá obhájit: kořen okna se **nezměnil** (práce se nikam
nepřesunula, pravidlo z #275) a **kontrolní úsek měří dál** (nula je odpověď, ne porucha, #478).
Ablace **celého** `forget(whatIsNotIn:)` vydala tatáž čísla jako ta jedna řádka, takže v tom úklidu
nic dalšího není.

**Čas se naměřit nepodařilo, a je to výsledek, ne mezera v práci.** Do sondy se kvůli #275 přidal
součet CPU hlavního vlákna za dobu, kdy se točí runloop. Nad scénou o **stu** souborů, kde je ten
rozdíl `DiffRowView` **12 530 proti nule**, dalo A/B/A/B `42, 26 ms` s vadou a `24, 58 ms` po opravě
— jedno „po opravě“ číslo je tedy **vyšší než obě „s vadou“**. Rozptyl měřidla je větší než efekt.
Proč: po #469 zašpiněné tělo **nepřerovnává nasazené bloky kódu** (`DiffBlockRow.geometry` se
v úsecích s tiky neobjeví vůbec, v kontrolním úseku má ~1 340), takže nasazených je pořád 18, ať má
diff dvanáct souborů nebo sto. Zbývají struktury řádků a dotazy na identitu, a ty jsou po jednom
levné. **Nula v počtech tedy znamená „ta práce se nedělá“, ne „ušetřilo se X ms“**; doložit ms by
chtělo scénu s řádově víc nasazenými bloky (ostrý diff přes `PRISM_DIFF_DIR`) a to **neuděláno**.

**Jak se na to dosáhlo**, protože předchozí dvě kola na to nedosáhla: `Self._printChanges()` v těle
diffu (privátní API, v repu **nezůstalo** — je to ablace) ukázalo `@self, _layout changed` a **nikdy
keypath**, tedy že si tělo tu mapu nečte samo. Pak ablace celého `forget`u, která oddělila
`isRefreshing` (kořen okna) od diffu. A pak odběr nad **mapami, které tik prořezává**, místo nad
čteními, která dělá diff — to je ten krok, který dal jméno. Druhé kolo se ptalo „co čte diff“
a odpověď „nic z toho“ byla **pravdivá**: `diffSearches` čte `searchActions`
v `PullRequestDetailView`u, tedy kód, který skládá **hodnotu** diffu.

**Zapsaná mez**: hodnota `DiffView`u se nikdy neshodne, protože `layout` je `Binding` stavěný
v computed property — takže probuzení kteréhokoli čtení „při skládání“ stojí celé tělo diffu.
Odstranit tu churn se **nezkoušelo**: po opravě nad nečinným diffem nic nebudí, takže by to bylo
zlevňování něčeho, co se nedělá. Je to ale kandidát na příčinu u **#541**. A není změřené, jestli
SwiftUI v takovém případě překládá celé tělo rodiče, nebo jen tu jeho část — sonda umí říct jedině
to, že se počitadlo `PullRequestDetailView`u **nehne**.

Testů **5132** v 503 suitách, zelené s jedním známým nálezem (`FontMetricTests`, záměr z #550);
nové je jedno tvrzení — `PollObservationTests.quietTickWakesNoneOfTheMapsTheTickPrunes` nad **všemi**
osmatřiceti mapami, ne jen nad tou jednou, aby další neporovnatelná hodnota spadla tam, ne v okně.
**Ověřeno vložením regrese**: bezpodmínečný zápis zpátky → `tichý tik probudil diffSearches`, a spadne
u toho právě jen tenhle test. Do sondy přibyla osa `PRISM_BIG_FILES` (počet syntetických souborů —
cena je lineární v počtu řádků, takže z jedné velikosti scény se to nepozná) a součet CPU.

**Na obrazovce není co vidět**: v `App/` je to jeden `if` v úklidu po tiku a nad nečinným diffem
z něj plyne, že se **nepřekresluje** to, co se do #421 překreslovalo zbytečně.

## #483 — Emotikony s našeptáváním shortcodů ve třech polích, která posílají text ven

Okno má tři místa, kde se píše text pro GitHub: composer komentáře pod PR (#216), odpověď do vlákna
(#73) a tělo review v panelu. Ve všech třech to bylo holé pole — emotikon se do něj dal jedině
vlepit odjinud. Od #483 se v nich píše `:ta` a nabídka doplní zbytek. Návrh, sekce 38.

**Odejde znak, ne shortcode.** Composer je obyčejné textové pole a odchází jeho obsah, takže vložený
`:tada:` by byl náhled, který tvrdí něco jiného než výsledek na GitHubu — tatáž úvaha, kvůli které se
u nového labelu posílá hex vždycky (#413). Shortcody bez Unicode (`:shipit:`, `:octocat:`) proto
v nabídce nejsou.

**Cesta ven se nezměnila o nic**: `grep ReviewPublishing App/` vypisuje týž seznam, `GitHubGateway`
nedostal dotaz a `SingleWayOutTests` se nesáhlo. Je to chování textového pole.

**Katalog je v aplikaci** (1870 znaků, 1913 shortcodů), generovaný `bin/make-emoji.swift` ze zdroje
v repu (`db/emoji.json` z github/gemoji, MIT). `GET /emojis` vrací jména a adresy obrázků, ne znaky.
Vygenerovaný soubor je **jeden velký řetězec**, protože doslovné pole 1870 struktur by type-checker
překládal minuty; řádky jsou **abecedně podle prvního shortcodu**, jinak by na dotaz `:ta` vyhrálo
jídlo (zdroj je seskupený po kategoriích) a `:tada:` by se do šesti řádků nevešlo.

**Dvě věci vyšly proti zadání jinak, a obě z měření.**

První: **nabídku nekreslí pole, ale volající.** `overlay`, který přesahuje plochu rodiče, ořízne
každý ořezávající předek — změřeno na skutečné hierarchii (`NSHostingView` v okně + `cacheDisplay`;
`ImageRenderer` `ScrollView` nevykreslí vůbec), a v obou případech zmizela nabídce horní hrana
**i vybraný řádek**. Dvě ze tří polí v takovém předkovi sedí: tělo review je první věc ve `ScrollView`u
panelu, odpověď do vlákna je v bublině s `clipShape` (97 bodů proti 203 plné nabídky). Nabídka se
proto kotví na tom předkovi, který neořezává, a stav si podávají přes `EmojiSuggestionBox`
(`@Observable`, jeden na majitele — hodnota ve `@State` by úhozem překreslovala tab, #472).
`popover` to nevyřeší: bere fokus, takže by v poli přestalo jít psát.

Druhé: **dlouhé jméno se samo nezalomí.** `Text` ve SwiftUI uvnitř slova nezalamuje, takže nejdelší
jméno v katalogu (`:hand_with_index_finger_and_thumb_crossed:`, 42 znaků) zůstalo na jednom řádku
a **přeteklo** za hranu, aniž by se změnila výška. Zlomy proto nabízí `Policy.emojiShortcodeLabel`
nulovou mezerou za `_`, `-` a `+`; nejdelší úsek mezi oddělovači má v katalogu 16 znaků. Do textu
zprávy se ze sazby nedostane nic — vkládá se znak.

**Hledání se s panelem dělí ve stupních shody, ne v `searchRange`**, a to ze dvou důvodů:
`.diacriticInsensitive` by na `:čá` nabídlo `taco` (shortcody jsou ASCII) a cena — 1,88 ms proti
0,50 ms na dotaz nad 1913 jmény (`-O`). Běží to při každém úhozu s otevřenou nabídkou.

Testů **4449**, všechny zelené — z toho **37 nových** v pěti suitách. Cenná je na nich negativní
půlka: devatenáct vstupů, u kterých se nabídka otevřít **nesmí** (`12:30`, `https:…`, `Poznámka:`,
`::ta`, `:1`, `:tada:`, kurzor mimo text), zastaralý rozsah, který **nevloží nic**, `:čá` bez shody,
a nad zdrojáky, že nabídku zapínají **jmenovitě tři** pole a tab `Zeptat se` mezi nimi není. Jedno
tvrzení se muselo utáhnout po vložené regresi: `suggestions: emoji` stojí v obou voláních, takže test
„kdo box podá, ten nabídku kreslí“ prošel i s polem, kterému se box vyndal.

**Proklikání našlo jednu věc a stála za to**: `:+` nabídku neotevřelo, takže `:+1:` ani `:-1:` —
dva nejčastější shortcody na GitHubu — se od dvojtečky napsat nedaly. Pravidlo se rozšířilo
**nesymetricky**: `+` projde hned, `-` až s druhým znakem. Důvod je `:-)` a `:-(`, které jsou v české
próze běžnější než `:-1:`: na samotném `:-` má katalog čtyři shody (👎, 📧 přes alias `e-mail`, 🚱,
🦖), takže by nabídka u každého smajlíku na jeden úhoz problikla. Zamítnutá symetrická varianta
i cena té zvolené jsou v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--znaménka-v-dotazu-a-smajlík-483).
Výčet v testu se tím rozšířil o pět otevírajících a pět zavřených vstupů a asymetrie je **ověřená
vloženou regresí**.

**Co ověřuje jedině člověk**: že klávesy zaberou (#184). `↑↓`, `↵`, ustupující `esc` a `⌘⏎`
s otevřenou nabídkou testovací host neunese — aktivaci nedostane.

## #482 — přepnout vlastní PR z draftu na *Ready for review*

Sekce `Větev` (#465) vypisuje, proč se nedá mergnout. Většina těch důvodů je práce: spravit červený
check, srovnat větev (#466), dovyřídit blokující nález. Jeden z nich byl ale **jedno kliknutí kdesi
jinde** — a aplikace to o sobě sama psala: `MergeObstacle.draftPullRequest` končilo větou *„Označ ho
na GitHubu jako připravený.“* Ta půlka věty byla návod, jak z okna odejít, a od #482 je z ní
tlačítko. Návrh, sekce 37.

**Tvrdá podmínka č. 1 se tím mění: přibyla devátá metoda `ReviewPublishing`**
(`markReadyForReview(on:)`). Je to tatáž třída jako labely a vyžádání reviewera (#392) nebo merge
(#465) — práce s **vlastní** frontou —, takže **nová třída jako `BranchPushing` z toho nevznikla**:
mluví se přes `gh` s GitHub API, ne přes `git` se serverem. **Počet souborů zůstal sedm**, protože
metoda přibyla do `MetadataSubmission`: rozhoduje, co to je za práci, ne kde je na to tlačítko —
a stav (`MetadataActionState`) se sdílí schválně, takže dvě odesílání nad jedním PR naráz neběží, ať
se klikne kdekoli. **Metoda je jednosměrná** a `convertPullRequestToDraft` je jmenovitě zakázaný:
obousměrná by měla půlku bez volajícího.

**Posílá se `gh pr ready --repo`, a je to jediná cesta ven, která nejde přes `gh api`.** Vybráno
měřením na `ondrajodas/prism-review-sandbox#11`, ne pohodlím, a obě zamítnuté varianty jsou
zapsané: **REST na tuhle věc endpoint nemá** (`PATCH /pulls/{n}` s `draft=false` vrátí `200`
a přepnutí **tiše zahodí** — tatáž past jako `POST /requested_reviewers` s Copilotem), a **GraphQL
mutace chce node ID**, které aplikace nemá odkud vzít; k tomu její chybový text koliduje s větví
`threadNotFound` v `PublishError`. Změřená je i idempotence: nad PR, který draft **není**, skončí
`gh pr ready` nulou (`! … is already "ready for review"`), takže dvojklik ani závod s prohlížečem
nevyrobí chybu, kterou by bylo potřeba někde ukazovat. Čísla a texty jsou
v [`docs/github-cli.md`](github-cli.md).

**Bez potvrzovacího sheetu, a je to úvaha o obsahu.** Sheet je u review (#68) a u merge (#465),
protože tam je payload dlouhý a okno je jediné místo, kde se dá přečíst celý. Tady je payload
**jeden bit**. Nevratná část na tom ale je — přepnutí vyžádá review od vlastníků kódu —, takže se
platí tím, čím #392 u `+ reviewer`: **sloveso tam, kde se kliká**, **věta pod tlačítkem**
o `CODEOWNERS` a o tom, že zpátky do draftu se chodí na GitHub, a **žádná výchozí akce** (hlídá to
stráž nad zdrojákem, ověřená vloženou regresí).

**Na obrazovce vidět je** — nad řadou `Mergnout…` / `Rebase` přibylo u vlastního draftu tlačítko
`Připravit k review` **přes celou šířku panelu**, pod ním ta věta, a když volání spadne, místo věty
chyba se `Zavřít`. Do řady s ostatními dvěma to nepatří **a je to změřené** — a **přeměřeno
aplikací to vychází jinak než v zákresu**: ne „279 z 278, o jediný bod“, ale **273–274 bodů na 274,
tedy přesně na hranu**, a rozhoduje o tom **podlaha panelu**, kde ta řada přetéká o ~60 bodů (214 b
na obsah). Čísla v zákresu jsou z CSS odsazení 11, aplikace má 13; závěr se nemění, takže se mockup
nepřekresloval. **Kreslí se jedině nad draftem** — nad otevřeným, zavřeným ani mergnutým PR není
v sekci o řádek víc, protože tam není co přepínat.

**Po úspěchu se načte detail i slévatelnost**, a v tom se to od merge liší: tam se `branchStatuses`
schválně nechává být (mergnutý PR vrací `UNKNOWN` navždycky), kdežto tady je to ta jediná hodnota,
která se přepnutím mění na užitečnou — draft má `mergeStateStatus` `DRAFT`, takže by po přepnutí
zůstal v panelu řádek `rozpracovaný`. **Záložka naopak zůstává otevřená**, taky opak #465: tam ji
zavírá tentýž klik, kterým člověk PR dokončil, kdežto tady se PR teprve předává ostatním.

Testů **4592**, všechny zelené — z toho **33 nových** ve třech suitách a tři nové scény v sondě
sekce `Větev`. Cenná je na nich negativní půlka: nula spuštění `gh` na cizím PR, s vypnutou branou,
nad všemi třemi nedraftovými stavy a bez `gh`; dvojklik jako jedno volání; `!arguments.contains("api")`;
a stráž, že v `PanelBranchView.swift` není `keyboardShortcut`. U cache se tvrdí **oba směry** — a ten
druhý se dal napsat jedině trikem: v testu selhání se novější detail podstrčí **taky**, jinak by
tvrzení „stav se znovu nenačetl“ prošlo i tehdy, kdyby se načetl.

**Dvě odchylky od zákresu**, obě v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--ready-for-review-jako-devátá-metoda-482):
věta o neúspěchu je jen `PublishError.userDescription` (zákresová *„Pull request je pořád
rozpracovaný“* je tvrzení, které data neunesou u `timedOut` a `interrupted`, a *„se nepovedlo“* říká
`unknown` taky), a plnou plochu tlačítka dělá `maxWidth: .infinity` **uvnitř** pevného rámce —
`borderedProminent` si plochu k popisku sám nedotáhne a bez toho z něj bylo tlačítko na 129 bodů
vystředěné v prázdném řádku (našel render, ne review).

**Cestou se zavřely dvě starší mezery a jedna se otevřela.** Zavřely: `405` u merge **nad draftem**
je změřený (u #465 to zakázala permission brána) a zní `Pull Request is still a draft`, takže
`notMergeable` na něj **nesedí** — neopravuje se to, protože merge se nad draftem neposílá.
A `docs/stav.md` měl od #487 v sobě **committnuté konfliktní značky** (`<<<<<<< HEAD`,
`>>>>>>> origin/main`), které rozdělovaly záznamy #466, #421 a #483; jsou pryč a **žádný text se
neztratil** — všechny tři strany byly přírůstkové. Otevřela: že se vyžádání review od `CODEOWNERS`
doopravdy pošle, ověřené **není** — chce to druhý účet se zápisem do sandboxu.


## #490 — dvě terminálové sondy padaly podle klávesnice, ne podle zátěže

Zadání mluvilo o dvou vadách jedné třídy: `TerminalWheelTests` (třikrát v jednom plném běhu)
a `TerminalScrollProbe` (jednou ze tří). **Byla to jedna příčina** — obě suity si skládaly kolečko
přes `CGEvent(scrollWheelEvent2Source: nil, …)`, což znamená kombinovaný stav sezení, tedy **živou
klávesnici**. Rozbor i tabulka modifikátorů je v [`docs/testovani.md`](testovani.md#událost-skládaná-pro-test-nesmí-dědit-živý-stav-procesu-490).

Skládá se to od #490 na jednom místě (`Tests/Support/WheelEvent.swift`), oběma směry naráz —
`privateState` **a** `flags` z argumentu — a hlídá to stráž nad zdrojáky (`WheelEventTests`), protože
za běhu se to tvrdit nedá: bez držené klávesy vydá rozbitá i opravená cesta prázdné `flags`. Je to
**čtvrtá podoba** téhož kořene po #367, #411 a #407.

**Proti zadání se dvě věci rozhodly jinak, a obojí je změřené.** Zaprvé u scroll sondy se
nepoužilo ani `waitUntil`, ani `.disabled`: v té sondě není nic asynchronního (`ProbeScrollHost`
žádný shell nespouští a `feed(text:)` je synchronní), takže není na co čekat, a `Shift` v ní byl
tatáž příčina jako `Control` u té druhé. Zadruhé **čas 43–45 s se zátěží nesouvisí s pádem**: po
opravě vydá plný běh 49–52 s **i pro novou suitu**, která nedělá skoro nic — je to čekání na hlavní
vlákno v paralelním běhu, a nic v té sondě nemá lhůtu.

Testů **4597**, pět plných běhů po sobě s oběma suitami zelenými (souběžně běžel druhý slot).
Nových je 5 tvrzení: tři stráže nad zdrojáky a dvě měření toho, **co by zděděná klávesa udělala**
(`Control` → tlačítko 80, `Shift` → překlopená osa, nehybný výřez, nic neodešlo). Obě vložené
regrese stráž chytá. **Na tomhle není co vidět** — mění se jen testy a jejich helper, aplikace
zůstala nedotčená.

**Cestou se otevřela jedna mezera, a je zvlášť**: `CommitPanelRoomTests` spadly v jednom z pěti
běhů na `šířka znaku: 0`, tedy #407 — `FontMetric` volajícímu tu nulu **vydá** (hlášku o zlomek
sekundy později složí už z 8,036). S #490 to nesouvisí a nepatří to do jednoho PR.

## #467 — konflikty při srovnání větve vyřeší session (M13)

**Čtvrtá session v téhle aplikaci, a první, která smí měnit soubory.** Do #467 skončil `Rebase`
(#466) nad konfliktní větví zašedlým tlačítkem a větou *„Konflikty odsud zatím vyřešit neumím —
otevři terminál.“*, tedy návodem, jak z okna odejít. Od #467 je slévá headless session se `Write`
a `Edit`; **commituje aplikace** (`git add`, `git rebase --continue`), do remote se pořád píše jedině
přes `BranchPushing` a jedině z potvrzení.

**Tvrdá podmínka č. 2 se tím mění, č. 1 ne** — a drží ji čtyři meze, každá kontrolovatelná: scoped
`Write(//<strom>/**)` na ten strom v cache, ve kterém rebase uvázl; **žádný `Bash`** (první taková
session tady); `gh` a `git push` v zákazech z téže konstanty jako jinde; a druhá vrstva, která čte ze
streamu, **kam session zkusila psát** — při zápisu mimo strom se výsledek nepřijme vůbec.

**Že je to brána a ne prompt, je změřené, a měřilo se to obojí.** Holé `Write` v `--allowedTools`
píše **kamkoli** (session přepsala soubor v sousední složce); scoped pravidlo povoluje právě ten
podstrom a `cwd` **implicitně zapisovatelný není**. `..` se normalizuje před kontrolou, symlink ze
stromu ven se odmítne. Čísla jsou v [`docs/claude-cli.md`](claude-cli.md#slévání-konfliktů-467--čtvrtá-session-a-první-která-píše).

**Naostro to udělalo to, co mělo.** Na scratch repu s konfliktem, jehož správná odpověď je „vezmi
obojí“ (`master` vzal timeout z konfigurace, přehrávaný commit pod něj přidal `$retries`), session
zachovala oba záměry, nezůstala žádná značka, sáhla jedině do svého stromu a účet přišel v tom tvaru,
který `ConflictCommand.parse` čte. **$0,355, 4 kola modelu, 23 s.** `caveats` k tomu nesly informaci,
kterou by aplikace sama nezjistila — *„$retries zůstává v metodě nepoužitá“*.

**Účet session a doklad z `gitu` se nesmí slít, a proto jsou v potvrzení vedle sebe.** *Co s tím
session udělala* je tvrzení modelu, ale **rozsah a pořadí výpisu drží `git`**: soubor, o kterém
session mlčí, dostane `beze změny`, a soubor, ve kterém `git` pořád vidí značky, dostane
`nevyřešeno` **bez ohledu na to, co o něm session tvrdí**. *Co z toho vzniklo* je `git diff HEAD --
<kolidující soubory>`, tedy kód, ne popis — brané **před** `git add`, protože `--cached` by po zápisu
obsahoval celý přehrávaný commit (změřeno).

**Co nerozřeší, přiznává se.** Tři konce nechají rozdělaný rebase v cache a nabídnou `Zahodit rebase`
i `Otevřít v terminálu` (#459, vlastní role relace v tom stromě, kde to uvázlo): zápis mimo strom,
zbylé značky, vyčerpaná kola (strop **tři**, proti účtu). **Zrušení má vlastní stav** — `.interrupted`
z #466 by nenabídlo tlačítka na úklid, přitom v kopii repa leží rozdělaná práce.

Testů **4660**, všechny zelené — z toho **68 nových** v pěti suitách a šest nových scén ve dvou
sondách. Nejcennější je negativní půlka: nula `git add` i nula `--continue` po zápisu mimo strom
a nad zbylými značkami, nula čtvrtých kol, nula spuštění session nad stromem mimo cache a nula
`push` v celé sadě. **Sady povolení všech čtyř session jsou od #467 na jednom místě**
(`SessionToolSetsTests`) a tvrdí se **literálem**: čtyři sady jsou čtyři místa, kde se dá tvrdá
podmínka č. 2 porušit, a rozdíly mezi nimi se ze čtyř souborů nedají přečíst. **Regrese se ověřila
vložením regrese** — bez kontroly značek spadly dva testy, bez `zdiff3` jeden.

**Dvě odchylky od zákresu, obě z renderu** a obě v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--session-která-smí-psát-467):
diff je v potvrzení **až za výstrahou o lease** (s diffem uprostřed spadla na podlaze sheetu pod
hranu výstraha **i celý** výpis `Co odejde`) a v patce stojí `Terminál`, ne `Otevřít v terminálu`
(čtvrté tlačítko se do 460 bodů nevejde; zahodit `Zrušit`, jak to kreslí zákres, bylo zamítnuto —
nese `⎋`). K tomu jedna oprava z renderu: `beze změny` má `—`, ne `✓`, protože glyf odpovídá na
„sáhla na to session“, ne na „dá se to commitnout“.

**Zapsaná mezera:** klik na `Rebase` nad skutečným konfliktním PR z okna **neměřil autor změny** —
brána odesílání je ve slotu vypnutá a zapnout si ji kvůli měření by znamenalo přepsat konfiguraci,
aby vyšel potřebný stav. Ověřené je obojí do sebe: session naostro nad skutečným konfliktem a celý
řetěz `git add` → `rebase --continue` proti skutečnému `gitu`.

**`CLAUDE.md` rozdělený potřetí (issue #496)** — z **99 525 B** na **82 340 B** (−18 %).
Spouštěčem byla hranice, kterou si pravidlo v souboru samo stanovilo (100 kB): byl **475 bajtů**
pod ní, takže kterékoli další issue by ji přidáním jednoho odstavce překročilo — a nad tou
hranicí review na PR **vůbec nedoběhne**, protože Copilot si `CLAUDE.md` bere jako custom
instructions se stropem 110 tisíc tokenů.

Objem nesly **dvě sekce, 56 % souboru** (`Tvrdé podmínky` 30,9 kB, `Konvence` 25,3 kB) a nesly ho
přesně tím, co pravidlo posílá do `docs/`: měřením, rozbory a historií změn rozhodnutí. Přepsalo
se sedm sekcí; zůstaly v nich **věty pravidel, výčty tvrdých podmínek a grepy**, odešly naměřená
čísla, „do #X tady stálo“ a zdůvodnění — a u každého přesunutého odstavce zůstal **odkaz**.
Cílové soubory už ty rozbory měly, takže se do `docs/` skoro nic nepřidávalo; nové je jen
[*proč brána na návrh sedí u zakládání issue*](navrh.md#proč-brána-sedí-u-zakládání-issue-ne-až-u-prvního-commitu)
a [záznam o tomhle
rozdělení](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447-potřetí-496).

**Že nezmizelo pravidlo, je doložené, ne tvrzené.** Všech **27 grepů** z `CLAUDE.md` běželo před
i po a dalo **týž výstup**; doslovný text grepů je byte za byte stejný; inventář nadpisů, odrážek
a tučných vět (145 → 140 položek) se porovnal položku po položce a každý úbytek je vysvětlený
(obvykle se dvě odrážky slily do jedné). **Odkazy se od #496 ověřují skriptem nad slugy** — 89 odkazů
z `CLAUDE.md` do `docs/`, všechny platné; jeden byl **rozbitý už předtím**
(`#tři-zlevnění…` proti přejmenované sekci *Čtyři zlevnění*) a #496 ho spravilo.

**Copilot našel dvě reálné nekonzistence a obě se opravily.** Vážnější byla **stráž, která
tvrdila něco jiného než test, který ji hlídá**: `grep ReviewPublishing App/` vypisoval
**dvaadvacet** souborů, ne sedm (a `grep BranchPushing App/` devět, ne tři), protože se na ta
jména odkazuje i z `///` komentářů — kdežto `SingleWayOutTests` srovnává **kód po odečtení
komentářových řádků**. Věta *„(proto ho ten grep nevypíše)“* u `AppStore` byla přímo
**nepravdivá**. Nasadil se **filtr, který ostatní grepy v tomhle souboru mají už dlouho**
(`| grep -vE ':[0-9]+: *///?'`), a to na **všechny tři** výčty téhle třídy včetně
`ConflictResolving`, kde dnes vychází stejně, ale komentář jinde by ho potichu rozbil; invarianta
se nezměnila. Druhý nález bylo **číslování modulů, které si odporovalo s tabulkou** — ordinály
odešly a moduly se jmenují. Rozbor je v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447-potřetí-496).

**Cíl „~66 kB jako u #447“ se nesplnil a je změřené proč** (rozpad v záznamu rozhodnutí): próza
pravidel spadla o 22 % na **~450 B na pravidlo**, tedy přesně na hodnotu, kterou #447 popsalo jako
nestlačitelnou. Rozdíl proti 66,5 kB dělá **počet pravidel a odkazů** (URL v odkazech samy
přibyly — pravidlo, ze kterého se stěhuje vysvětlení, si odkaz musí nechat), ne rozvláčnost.
Cesta pod 70 kB vede jedině přes **mazání pravidel**, což je vlastní issue.

**Na tomhle není co vidět** — aplikace se nemění, je to čistě dokumentace; testů **4667**
ve 457 suitách, všechny zelené (kód se nedotkl ani řádkou). **Dvě zapsané mezery:** grep na české
prózy v shell skriptech (`grep -nP …`) na tomhle stroji nejde spustit, protože systémový `grep` je
`ugrep` bez `-P` — pravidlo platí, jen se ten grep musí pustit jinak, a #496 na jeho text
**nesahalo**, aby se změna pravidla nemíchala s přeskládáním souboru. A dvě konkrétní fakta se
odstěhovala hlouběji, než by leckdo hledal: `⌥↵` u zakládání labelu zůstalo, ale *„jde přes
`gh pr ready --repo`, ne přes `gh api`“* je teď jen v
[`docs/architektura.md`](architektura.md#ready-for-review-482--devátá-metoda-a-nejmenší-z-nich)
a v [`docs/github-cli.md`](github-cli.md).

## #389 — `issueTextTool` a `ownLogins` se nastaví z okna, ne jen ze souboru

**Poslední dvě hodnoty globální konfigurace, které se daly napsat jedině ručně do `config.json`,
dostaly pole v okně** — a u obou to znamenalo, že funkce, která na nich stojí, byla bez editoru
textu nedostupná: bez `issueTextTool` (#345) se text issue vůbec netahá a u každého PR s odkazem
svítí `zadání není celé`, bez `ownLogins` (#330) spadne PR agenta s vlastním účtem do cizí fronty.
Zbytek globální konfigurace v okně byl, ověřeno položku po položce; `appearance` v něm schválně
není (přepíná se v railu, #278).

**Celé rozhodnutí bylo, kam ta dvě pole patří — a nejsou to sousedi.** `issueTextTool` je
**materiál zadání pro reviewera**, takže leží na stránce `Review a skilly` hned pod promptem
(sekce `Text issue z trackeru`). `ownLogins` je **identita**, takže leží na stránce `Zdroje PR` pod
zdroji (sekce `Moje loginy`). Společná sekce „ostatní“ je zamítnutá: dělení podle otázky je to, co
zavedlo #177, a sekce, do které se sype, co se nehodí jinam, se hledá podle toho, kdy co přibylo.

**Prázdno u každého z nich znamená něco jiného, takže se kreslí jinak.** U jména nástroje je to
**rozhodnutí `netahat`** (session bez nástroje stojí boot a nevrátí nic), takže pod polem stojí
věta — `Nevyplněno — text issue se netahá.` u prázdného, `Tahá se — u PR s odkazem na issue běží
session navíc.` u vyplněného a **varování** u jména bez prefixu `mcp__`. To varování je varování,
ne zákaz: jméno je fakt o cizím stroji, takže ho aplikace neumí ověřit, dokud session neběží.
U loginů je prázdno **běžný stav**, o kterém není co dodat — místo věty je nad polem **přihlášený
účet ke čtení** (z `gh api user`, napsat se nedá), protože bez něj by prázdný seznam vypadal jako
„nevím, kdo jsem“, a to je stav, ve kterém je každý PR cizí.

**Rozhoduje `Policy`, ne view**: `issueTextToolNote(for:)` (věta pod polem — a volá
`issueTextTool(from:)`, tedy **tatáž funkce**, která pouští session, aby nemohlo nastat pole s „tahá
se“ a review, ve kterém se netahá), `issueTextToolEdit(typed:)` (vymazané pole = **chybějící klíč**,
ne `""`; bílé znaky zůstávají, jak je člověk napsal, jinak by mezera zmizela pod rukou)
a `viewerAccount(login:)`. Tolerantní čtení `config.json` se nezměnilo ani o řádek — obě pole
dekodér měl.

**Zákres předběhl implementaci** (jediná schvalovací brána v repu) a přeskládal v sekci 10 návrhu
**boční navigaci**, která byla ještě pre-#177 — jinak nebylo kam pole umístit. Odsouhlaseno včetně
dvou věcí nad rámec issue: té navigace a read-only řádku `Přihlášený účet`.

**Testy: 4688 ve 460 suitách**, tři nové sady. Nejcennější tvrdí, že se něco **nestalo** — po
vymazání pole v okně se dotažení textu nepustí a na ose stojí `netahalo se`, ne `nepovedlo se`;
ověřeno **vložením regrese** (se `?? ""` místo té stráže padnou dva testy a je z nich vidět, že
session dostala prázdné jméno). Vedle toho protějšek s vyplněným polem — bez něj by první test
prošel i nad kódem, který pole do konfigurace nepropisuje vůbec — a **rozdíl bitmap** dvou renderů
stránky, který chytá pole nakreslené, ale nenapojené (regresí ověřeno: s `EmptyView()` místo pole
padnou dva ze čtyř testů).

**Zapsaná mezera:** že se věta pod polem **přepne při psaní**, je ověřené jen renderem dvou
hodnot — rozdíl bitmap tvrdí, že se stav kreslí, ne že se překreslí s úhozem; ta druhá věc jde
ověřit jedině klikáním.

## M18 — Otevřít jakýkoli PR (milník #20)

Dnes se v okně otevře **jen PR ze zdrojů**. Milník přidává cestu k libovolnému pull requestu:
v ⌘K se napíše jméno repa, aplikace ho najde v organizacích z nastavení, `↵` přepne paletu
o úroveň níž na otevřené PR toho repa a druhý `↵` otevře **záložku ke čtení**. Vložený odkaz
a URL schéma `prism://` jsou zkratka téže cesty. Rozvrh je v popisu milníku: **#531** (otevřít
PR mimo zdroje — základ, sám) souběžně s **#532** (organizace v nastavení a cache seznamu
repozitářů, jiné soubory), pak **#533** (paleta: skupina `Repozitáře` a druhá úroveň), která
staví na obojím. Nakreslené je to v **sekcích 09, 10 a 41** návrhu.

**Tvrdé podmínky se nemění ani o položku**: celá cesta je čtení, `GitHubGateway` zůstává bez
zápisových metod. Mění se `forget(whatIsNotIn:)`, tedy úklid po tiku — viz níž.

## #531 — otevřít jakýkoli PR jako záložku ke čtení

Do #531 vedla do okna jedna cesta: PR se musel objevit ve **zdrojích** (#4). Od #531 se dá otevřít
kterýkoli — vloženým odkazem v paletě ⌘K, přes `prism://open?url=…` a od #533 z repa organizací —
ale jen **ke čtení**: do fronty, na karty, do odznaku ani do automatu se takový PR nedostane,
protože frontu definují zdroje. Hlavička to říká pilulkou `mimo zdroje · jen ke čtení`.

**První krok issue byl přenos zákresu T9 z decku do `docs/navrh.html`** (sekce **09** dostala dvě
nové obrazovky — vložený odkaz a dvě úrovně nad repem —, sekce **10** výřez s organizacemi a nová
sekce **41** výřez hlavičky s pilulkou a se dvěma stavy záložky, o které se ví jen adresa).
Sekcí je tím **40**; číslo v [`docs/navrh.md`](navrh.md) přitom stálo 38 proti skutečným 39, takže
se rovnalo i to.

**Značka je množina, ne mapa se shrnutími.** `AppStore.externalPullRequests` drží jen
identifikátory a shrnutí se skládá z dotaženého detailu (`summary(for:)`) — dvě kopie téhož PR by se
uměly rozejít v okamžiku, kdy autor změní titulek. Množina tak odpovídá na jedinou otázku, *odkud se
ta záložka vzala*, a čte ji pilulka, řádek palety i úklid po tiku.

**Nejcennější věc na téhle změně je, že se fronta nerozšířila.** `pullRequests` zůstává tím, co
přišlo ze zdrojů, takže karty, odznak, souhrn, notifikace ani automat se o takové záložce nemají kde
dozvědět; automat navíc dostává `summaries` z tiku, ne stav store. Je na to sada testů, které
tvrdí, že se něco **nestalo** — včetně srovnání **celého** dashboardu, ne jednoho čísla.

**Zato úklid po tiku se změnit musel, a bez toho by to nefungovalo vůbec.**
`forget(whatIsNotIn:)` zahazuje detail, diff, konverzaci, checky, commity i labely pro PR mimo
seznam — takže by otevřenou záložku **vyprázdnil první tik** a v okně by zbyla věta „pull request
zmizel ze seznamu“, tedy porucha nad stavem, ve kterém se nic nepokazilo. Chtěná množina je proto
sjednocení (`pullRequestsInPlay(besides:)`) a bere ji **i eviction cache a mazání uložených
nálezů**: jinak by po otevřené záložce zbyl klon bez záznamu, nebo záznam bez klonu. Ověřeno
vložením regrese — bez sjednocení padnou tři tvrzení. Zahodit značku smí **jedině zavření
záložky**; tik, ve kterém PR v seznamu není, je u téhle záložky normální stav.

**Načítání, porucha a „zmizel ze seznamu“ jsou tři různé stavy** (`Policy.tabContent`, čtyři
případy). O PR mimo zdroje se ví jenom adresa, takže mezi otevřením záložky a hlavičkou je vteřina
čekání — a ta nesmí vypadat jako věta o zmizelém PR. U poruchy zůstává **syrová odpověď `gh`** a dvě
východiska: `Zkusit znovu` (adresa může být v pořádku a síť ne) a `Zavřít záložku` (adresa může být
překlep). Záložka přitom vzniká **hned**, ne až po dotažení: kliknutí, po kterém se sekundu neděje
nic, je k nerozeznání od kliknutí, které nic neudělalo. V pruhu se do té doby kreslí
`Policy.pendingSummary(for:)` — titulek `Načítá se…`, prázdný autor, `distantPast` — a do
`summary(for:)` se to **dostat nesmí**, jinak by z něj byla hlavička s vymyšleným stavem `otevřený`.

**Skupina `Odkaz` v paletě neprochází hledáním.** Zbytek palety hledá v katalogu z paměti; tenhle
řádek je odpověď na to, co je v poli napsané, a hledat adresu v titulcích by znamenalo, že se
vložený odkaz najde jedině náhodou. Je **první** — výjimka z „nálezy první“, protože při vložené
adrese se na nic jiného neptám — a objeví se **jen** tehdy, když se dotaz dá přečíst jako adresa PR.
Pravidlo „paleta se nikoho neptá“ (#184) platí dál: řádek se skládá z identifikátoru, PR se dotahuje
až po `↵`.

**Dvě funkce na „odkud je“, a je to zapsané rozhodnutí, ne opomenutí.** Pilulka odpovídá na *odkud
se ta záložka vzala* (u PR, který ze zdrojů vypadl, tedy nic — jinak by tvrdila, že si ho člověk
otevřel odkazem), kdežto řádek odkazu na *je ten PR v mých zdrojích teď* (u neznámého PR
`není ve zdrojích`). Rozdíl **odhalila první zelená sada**, ne review: s jednou funkcí tvrdil
řádek u cizího repa `je ve tvých zdrojích`.

**Odkaz umí aplikaci spustit**, takže `prism://` musí přežít i to, že store ještě není: žádost si
`PreflightModel` schová a vyzvedne po preflightu. Zahodit ji by znamenalo, že kliknutí na odkaz
PRism spustí a **nic neotevře** — a podruhé už poběží, takže by se to vypadalo jako náhoda. Jméno
schématu i akce jsou konstanty v `Policy` a **test je srovnává s `Info.plist`**.

**Copilot k tomu našel dvě věci a obě jsou opravené.** (1) **Dvě `↵` na řádku `Odkaz` spustila
dva dotazy** — `openPullRequest` se ptal, i když už jeden dotažení běželo. `.loading` v mapě proto
znamená „někdo se právě ptá“ a druhý pokus se nepustí; k tomu se ta značka musí uklidit **na každé
cestě ven** z `loadExternalDetail`, i na té, na které se zápis zahazuje (zavřená záložka) — jinak by
znovuotevření uvízlo na obrazovce načítání navždycky. Obojí je pokryté testem a ověřené vložením
regrese. (2) **Komentáře v `forget(whatIsNotIn:)` tvrdily „drží se jen to, co je v seznamu“**,
kdežto hranice je od #531 o tu jednu záložku širší. Opraveno **jako třída, ne jako výskyt**: jedna
věta u definice `wantedPullRequests` říká, co „v seznamu“ v komentářích níž znamená — dvacet
přepsaných komentářů by znamenalo dvacet míst, ve kterých se dá zapomenout jedno.

Testů **4859** ve 476 suitách (proti 4827 ve 473 na `main`u po #500); nové jsou tři sady
(`PullRequestLinkTests`, `PullRequestOriginTests`, `AppStoreExternalTabTests`). Co se v nich hlídá
a proč, je v [`docs/testovani.md`](testovani.md).

## #152 — hledání v diffu (⌘F)

**Nejstarší otevřené issue v repu** (srpen 2026), a půlka jeho odůvodnění při implementaci
neplatila — přeměřilo se dřív, než se začalo psát, a rozdíl je zapsaný v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--rozsah-hledání-v-diffu-152).
Zadání tvrdí, že se text v diffu nedá vybrat kvůli tisícům `Text`ů v líném seznamu: vybrat **jde**
(od #157 kreslí kód `NSTextView` s `isSelectable = true`) a diff **není líný seznam** (od #469 pevný
`VStack`). Závěr platí ze dvou jiných důvodů: výběr **končí na hranici bloku** (60 řádků) a nakreslený
text je jen **pás kolem výřezu** (`Policy.mountBand`), takže by hledání nad ním měnilo počet
s odrolováním.

**Otevřenou otázku o rozsahu rozhodlo, že se rozsah dá říct.** Hledá se v hunkách **a v rozbaleném
kontextu**; zbytek souborů se nedotahuje (u padesátisouborového PR je to padesát volání kvůli jednomu
slovu). Nad nenačteným kódem proto pruh **netvrdí, že tam nic není**: kapsle `jen v diffu` stojí
u počtu, prázdný výsledek je `v diffu nic — mimo hunky se nehledá` a vedle toho `rozbal kontext (⌄)
a započítá se`. Rozbalený úsek se do počtu započítá hned, sbalený z něj vypadne.

**Pruh je druhá řádka chromu pod lištou diffu**, ne pole v liště (ta se u #219 srazila na tři věci
schválně) a ne překryv nad kódem (zakryl by ukotvenou hlavičku souboru). Existuje jen otevřený; v liště
po něm zbyl jen popisek `⌕ Hledat ⌘F`, aby se hledání dalo najít myší. Zákres je **sekce 39**
mockupu a byl odsouhlasený dřív, než se napsala první řádka kódu.

**Dva nové tokeny se změřily před zákresem, ne po stížnosti** — obráceně než u #277. `--hit-bg`
/ `--hit-hi` (`Palette.searchHit`, `searchHitCurrent`) jsou vyčíslený akcent nad plochou, protože
výskyt leží střídavě na nezměněném, přidaném i odebraném řádku; od plochy ΔE 11,9 / 11,1, mezi sebou
11,0 / 10,9, řetězec IntelliJ Light 4,20 a 3,10, Darcula 3,75 a 2,61 (dnešní tmavá word-level vrstva
má 2,17). Sytější být nesmí: pod výsledkem hledání se musí dát číst.

**Skok jde stejnou cestou jako skok na nález** (`DiffRow.anchor` → `scrollTarget` → `blockSpot`)
a sbalený soubor se rozbalí **dřív, než se cíl nastaví**. Kotva se hledá nad hotovými řádky, ne
z `newNumber`: výskyt může být na odebraném řádku a ve split pohledu nese dvojice `id` pravého —
`scrollTo` na neexistující `id` by tiše neudělalo nic. Diff commitu proto dostal `scrollTarget`,
který do #152 byl `.constant(nil)`.

**Zvýraznění je třetí vrstva atributů** nad syntaxí a word-level rozdílem; **do `SyntaxRunCache`
nesmí** (#153), protože závisí na dotazu. Hledání z těch tří vrstev **vyhrává** — je to jediná,
kterou si člověk zapnul sám. Dotaz je proto v **klíči sazby** (`DiffBlockStyle.search`): bez toho by
se po jeho změně přesázení přeskočilo a v okně by zůstalo svítit slovo z minula.

**Stav je `@Observable` objekt ve store, ne struktura** (#472): dotaz se mění při každém písmenu,
takže ve slovníku by probudil i tělo detailu PR. Vlastnosti jsou rozdělené podle toho, kdo je čte
(`isOpen` × `query`/`hits` × `current` × `focusRequests`) a dovnitř diffu jdou **prostředím**, takže
`DiffView` čte jedinou z nich a psaním do pole se tělo diffu nepřekresluje. Výskyty se skládají jen
při změně (dotaz, `Aa`, rozbalení, nový diff, otevření pruhu) — nikdy z těla view.

**Klávesy:** `⌘F` (v katalogu, registruje diff), `⌘G`/`⌘⇧G` (v katalogu, registruje **pruh** — jsou
jen tam, kde je kam skákat), `⏎`/`⇧⏎` na poli a `⎋` na `✕`, tedy **mimo katalog**; místo toho se nad
otevřeným pruhem zakazuje zkratka okna, která `⎋` jinak má (`Policy.canCloseCommit`, od #152
s vyjmenovanými podmínkami místo `&&` ve view). Katalog má 24 akcí. **Že ty klávesy zaberou, ověřil
člověk** — v harnessu to nejde (#184).

**Z proklikání vyšla vada v tom, kam se skáče, a opravila se pro celou třídu skoků.** `scrollTo`
umisťuje **cíl**, a cílem je od #157 blok o nejvýš šedesáti řádcích — podíl výšky se tedy uplatnil na
blok a poloha řádku v něm do výpočtu nevstupovala. Změřeno: z dvou set řádků byly po skoku vidět
první čtyři desítky, řádek 195 skončil 2 181 pt pod hranou výřezu. Podíl se od té doby dopočítá
(`Policy.jumpAnchorY`, `DiffRow.blockSpot`) a poloha sedí na dva body; opravilo to i skok na **nález**
a na můj komentář, kde ta chyba byla potichu od #157. Vyjmout cíl do vlastního bloku se zkusilo,
změřilo a **zahodilo** (nové bloky nejsou v tom průchodu rozvržené). K tomu **vertikální umístění**:
výskyt hledání přistane na **třetině shora**, nález zůstává 90 pt pod hranou (bublinu nese pod sebou)
— a skáče se **vždycky**, i na výskyt, který je zrovna vidět, aby oko při `⏎ ⏎ ⏎` stálo na jednom
místě. [Záznam
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--kam-skok-posadí-cílový-řádek-152).

**Druhé kolo proklikání ukázalo dvě další věci a obě jsou opravené.** (1) **Skok vůbec neroloval do
šířky**: ve split pohledu se nezalamuje, takže výskyt na dlouhém řádku ležel za pravou hranou sloupce
(naměřeno x 2 708 proti výřezu 0–582) a pruh přitom hlásil `4 z 17`. Odhaluje ho teď **blok sám**
(`DiffPairBlockView` → `DiffPairScrollView`), a jedině když vidět není (`Policy.horizontalReveal`) —
vodorovnou polohu si člověk nastavil sám. (2) **Svislé míjení mělo ještě dvě příčiny**: zalomené
řádky (odhad výšky bloku 964 pt proti skutečným ~2 900, cíl skončil až **6 017 pt nad** výřezem —
rozměry se od té doby berou **změřené** z `DiffRowFrames`) a **animace skoku**, kterou o průchod
později uťal druhý posun (jeden skok z desítky se pohnul o dva až třináct bodů a zůstal stát). Skok
proto **není animovaný** (změna proti #72); druhý průchod zůstává, jen si rozměry **přeměří** —
první skok se počítá z ploch nahlášených dosud, a ty umí být z jiné šířky.

**Copilot k tomu našel ještě jednu věc a je opravená**: `refreshDiffSearch` přepočítával výskyty
i se **zavřeným** pruhem (dotaz si drží), tedy celý diff při každém rozbalení kontextu a při každém
novém diffu — a výsledek se přitom nemá kde nakreslit. Guard teď chce `isOpen`; při otevření se
skládá znovu, takže se nic neztratí.

Testů **4776** ve 468 suitách; nových je sedm sad (`DiffSearchTests`, `DiffSearchNavigationTests`,
`DiffSearchHighlightTests`, `AppStoreDiffSearchTests`, `DiffJumpAnchorTests`, `DiffSearchRevealTests`,
`DiffJumpPlacementTests` — poslední měří polohu po skoku v hostovaném okně), dvě měření barev
v `DiffPaletteTests` a sonda `DiffSearchRenderProbe`. Co se v které z nich hlídá a proč,
je v [`docs/testovani.md`](testovani.md).

### M14 — Čtení kódu (milník #16)

Milník o tom, kde se v review tráví čas: **čtení diffu**. Mění tři věci naráz a všechny čtou
tatáž data — kód zůstane souvislý a nálezy, vlákna i poznámky stojí v okraji vpravo u svého
řádku (směr B); pod hlavičkou je **mapa PR**, tedy celý diff jako pás podle souborů, barva podle
nálezů, prošlé tlumeně (směr E); strom souborů vyroste v **itinerář** se zastávkami a s tím, co
je hotové (směr A). Zákresy jsou v decku **Směry pro PRism**, stránky B, E, A a N1; přenos do
`docs/navrh.html` dělá **první issue každé dvojice nebo trojice** ve svém PR.

**Základem je značka `Prošlo` u souboru (#500)** — stojí na ní E i A, takže jde sama a jako první.
Pořadí zbytku i to, co jde souběžně, je v popisu milníku na GitHubu; tady se to neopisuje, aby se
ta dvě místa nerozešla.

Milník **otevírá čtyři zapsaná rozhodnutí**: #185 (bubliny pod řádkem), #182 (panel vpravo jako
seznam), #172 (spektrum reviewerů v řádku) a #197 (strom podle cesty). U každého vznikne záznam
rozhodnutí ve specifikaci — co tehdy platilo a co se mění v argumentu.

## #500 — značka `Prošlo` u souboru, vázaná na obsah

Diff do #500 nevěděl, kde jsem skončil. U PR o sedmi souborech se po přepnutí záložky, po tiku
s novým commitem nebo druhý den hledalo očima, co už bylo přečtené — a strom vlevo o tom mlčel,
nesl jen značku nálezu. GitHub na to má *Viewed* a byla to jediná věc z jeho diffu, která v okně
chyběla. Zákres je **sekce 40** návrhu (stránka *Změněné soubory*), přenesená z decku *Směry pro
PRism* (stránka *Opravy › N1*).

Přibylo: **zaškrtávátko v hlavičce** každého souboru za počty `+18 −6`, **✓ ve stromu** (a `↻`
u změněného), **`7 souborů · 3 prošlé`** v hlavičce stromu s tenkým proužkem podílu pod ní,
a klávesa **`⌥V`** na soubor pod ukotvenou hlavičkou. Prošlý soubor se sbalí, změněný se sám
rozbalí.

**Značka je o obsahu, ne o hlavě.** Ukládá se k PR (`read-marks/<owner>/<repo>/<pr>.json`, jako
rozhovor #452), ale nese **otisk** — sha z `index` řádky diffu, celou dvojici `<základ>..<hlava>`.
Commit, který soubor nemění, ji nechá; commit, který ho mění — i rebase, po které se změnil základ
— ji přepne na `změněno od prošlého`. Tvrdá podmínka č. 5 se tím neobchází, jen se doplňuje: mluví
o **nálezech**, tedy o tvrzení proti kódu, kdežto značka je tvrzení o mém čtení. Duch té podmínky
drží prostřední stav — nikdy „prošlo“ nad kódem, který už není.

**Otisk nestojí ani jedno volání navíc.** `index` řádka byla do #500 na seznamu ignorovaných
v `DiffParser`u, takže se z diffu, který se stahuje tak jako tak, jen začala číst;
`GitHubGateway` kvůli tomu nedostal metodu a `gh api …/pulls/{n}/files` (kde per-file `sha` je)
se zamítlo jako dotaz za údaj, který už v odpovědi je. **`nil` je platná hodnota**: přejmenování
se `similarity index 100%` `index` řádku nemá vůbec, takže se porovnává na rovnost **včetně
`nil`u** — dvakrát „nevím“ nad souborem, který se jen přesunul, je pořád tentýž soubor. Kdyby to
byla změna, značka by po zaškrtnutí okamžitě zhasla.

**Sbalení se odvozuje ze značky, nezapisuje se** — a to je ta věc, kterou by šlo udělat snadněji
a bylo by to špatně. Zapsané sbalení je stav okna, takže by se prošlé soubory po restartu otevřely
dokořán, i když značky na disku jsou. `AppStore.fileFolding` se proto z **množiny sbalených** stal
**mapou odchylek** (`true` sbaleno rukou, `false` rozbaleno rukou, chybějící klíč = platí značka)
a rozhoduje `Policy.isFileFolded(state:override:)`. Zdarma z toho vyšlo, že se `changed` rozbalí
sám — po druhém commitu zbude otevřené jen to, co se změnilo — a `Rozbalit vše` odchylky
nemaže, ale **přepisuje na `false`**, protože je to pokyn o tom, co je vidět, ne o tom, co je
přečtené.

**Ve stromu stojí ✓ vedle puntíku nálezu, ne místo něj.** Zákres tu kombinaci nekreslí (v něm
nenastane), ale stát se může: „je tu co spravit“ a „četl jsem to“ jsou dvě různé otázky, a schovat
jednu za druhou by znamenalo, že se počet v hlavičce rozejde s tím, co je v seznamu vidět.
Doplnilo se to do poznámek sekce 40, ne do kresby.

**Kde značka není:** v diffu commitu (#317) a v rozsahovém diffu „co od minule přibylo“ (#284).
Jejich `index` řádky mluví o rozsahu mezi dvěma commity, ne o hlavě PR, takže by se otisk se
značkou nepotkal a každý zaškrtnutý soubor by hned hlásil `změněno od prošlého`. Zaškrtávátko se
tam **nekreslí vůbec**, ne zašedle.

**Zkratka `⌥V` visí na jednom průhledném tlačítku**, ne na zaškrtávátku v každé hlavičce: padesát
tlačítek s touž kombinací je přesně ten stav, kdy vyhraje to zaregistrované později a ostatní
„nefungují“ (#151, #184). Katalog má **25 akcí**. Že klávesa zabere, ověřuje člověk — v harnessu
to nejde (#184).

**U toho se zjistilo, že publikovaná kopie návrhu se rozešla s repem**: artifact neměl sekci 39,
kterou #152 do `docs/navrh.html` přidalo — commit tedy proběhl a publikování ne. Postup, jak se
to porovná (a proč se z toho nedělá hlídané pravidlo), je v [`docs/navrh.md`](navrh.md).

Testů **4827** ve 473 suitách (proti 4776 ve 468 na `main`u); nové jsou tři sady
(`FileReviewStateTests`, `ReadMarkStoreTests` i s vnořenou `Značky mimo cache`,
`AppStoreReadMarkTests`), pět tvrzení v `DiffParserTests` a sonda `FileReadMarkRenderProbe`
(obrázek hlaviček i stromu, a hlaviček **na 420 bodech** — v úzkém místě ustoupí cesta a kapsle,
zaškrtávátko zůstane celé). Nejcennější jsou dvě, která říkají, že
se něco **NEstalo**: commit, který soubor nemění, značku nesundá, a `Rozbalit vše` ji nesmaže.
Regrese ověřena vložením regrese — otisk vyřazený z rozhodování shodí devět tvrzení, odvozené
sbalení vyřazené z `Policy` dalších pět. Co se v které sadě hlídá, je
v [`docs/testovani.md`](testovani.md); rozhodnutí i se zamítnutými variantami v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--značka-prošlo-u-souboru-500).

## #532 — organizace k prohledávání a cache seznamu repozitářů (M18)

**První polovina M18** (*Otevřít jakýkoli PR*): aby paleta ⌘K našla repo podle jména, musí mít
seznam rep — a ten se nedá tahat při každém úhozu. Přibyla tedy položka konfigurace
`searchOrganizations`, sekce **Nastavení › Zdroje PR › Organizace k prohledávání**, čtecí
`GitHubGateway.repositories(in:)` a cache `catalogs/<org>.json` s denní obnovou. Hledání v paletě na
tom staví #533; **odsud se nic nedostane do fronty, karet, odznaku ani automatu** — frontu definují
zdroje (#4) a věta pod sekcí to říká.

**Celé issue plyne z jednoho změřeného čísla.** Výpis rep organizace `keboola`
(`gh repo list --limit 1000 --json name,pullRequests,pushedAt`) stojí **46,8 s** a má 98 kB; bez pole
`pullRequests` je to **9,5 s**, tedy pětinásobek za jedno číslo v řádku nabídky. Počet otevřených PR
v tom zůstal (je v zákresu a platí se jednou denně), ale cena je zapsaná v
[`docs/testovani.md`](testovani.md#kolik-stojí-výpis-repozitářů-organizace-532), takže se to dá
kdykoli otočit s vědomím, co se tím koupí. Že `pullRequests.totalCount` je počet **otevřených** PR,
je změřené taky (`keboola/keboola-operator`: 17 proti 17 z `gh pr list --state open`).

**Tři věci z toho čísla vypadly.** (1) Výpis má **vlastní, delší limit** — do společných třiceti
sekund se nevejde, takže by ta organizace **vždycky** skončila `timedOut`; tvrdí to test nad
`FakeProcessRunner.timeouts`, protože test s prázdným výstupem by prošel i se špatným limitem.
(2) **`--limit 1000` se doopravdy dosáhl** (přesně tisíc položek), takže se z počtu pozná sražení
(`hitLimit`) a v okně stojí `nejméně 1 000 rep` — „tisíc rep“ by data neunesla. (3) **Dotahuje se
jedině na vyžádání**: tlačítko `Obnovit`, otevření stránky, dopsání organizace (`onSubmit`). Psaní
v poli nevolá nic — `keboola` po písmenech je sedm hodnot, tedy sedmkrát tři čtvrtě minuty a sedm
podprocesů `gh`. Je na to test a je to to nejcennější tvrzení celé oblasti, protože tvrdí, že se
něco **ne**stalo.

**Jedno rozhodnutí je odchylka od zadání a je zapsané.** Katalog **drží okno nastavení**, ne
`AppStore` (uzavřený kus stavu s vlastní persistencí; rozvrh dávky navíc nedovoloval třetí větev ve
stavu `AppStore.swift`), a s tím se **denní obnova dělá při použití, ne na tiku pollingu** — katalog
nikdo nečte, dokud neotevře nastavení nebo (od #533) paletu, takže obnova na tiku je desítky sekund
práce za nic. Kdo obnovu spouští, až katalog dostane paleta, patří k #533. Zbytek je v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--katalog-repozitářů-drží-okno-nastavení-532).

**Sekce je chipline podle zákresu** (`.chipline` + `.tagchip` + `.tagchip.plus`, sazba
v `TagChipStyle` jeden ku jedné). **První podoba měla řádky s poli**, aby se shodovala s `Moje
loginy` o řádek výš, kde je aplikace od #389 sází jako nativní seznam polí — to jsem **zamítl**:
kreslí se to, co je v návrhu, a sjednocení `Moje loginy` je jiné issue. Chipline potřebovala tři
věci, které statická kresba nemá: **křížek v chipu** (jinak se organizace nedá dostat pryč jinak než
zásahem do `config.json`), **pole místo přidávacího chipu** po kliknutí (jméno organizace je volný
text, na rozdíl od labelu z uzavřené množiny) a **věta o selhání pod chipline**, uvozenou jménem
organizace.

**Render vedle referenční kresby našel čtyři věci** (headless Chrome nad `docs/navrh.html` proti
offscreen renderu sekce). Tři z nich byly v přidávacím chipu a všechny měly týž kořen:
**`.tagchip.plus` přebíjí jen `color` a `border-style`**, kdežto řez, velikost, odsazení, poloměr
**i podklad** si dědí — první podoba mu dala UI font medium, průhlednou výplň a akcentový okraj.
Od oka vypadaly správně; našlo je jedině přečtení CSS doslova. Čtvrtá byla **souhrn nakreslený přes
první chip** (`kebo412 rep`): SwiftUI nemá `flex-shrink`, takže `FlowRow` s `maxWidth: .infinity`
si v `HStack`u řekne o celou šířku, a `layoutPriority(1)` to **nespravilo** (ideální šířka
nekonečného rámce zůstane nekonečná). Rozhoduje proto **rozměr, ne vyjednávání**: `ViewThatFits`
vybere řádek ze zákresu, dokud se vejde (změřeno — při 820 bodech ano), a v úzkém okně dva řádky pod
sebou (509 bodů). Hlídá to rozdíl bitmap při obou šířkách.

**A ještě dřív z renderu vypadla jedna oprava**: řádek organizace nesl **stav** (`412 rep`, `zatím
nenačteno`) a nad souhrnem, který říká totéž, z toho byla tatáž věta dvakrát pod sebou — u jedné
organizace se zdvojoval i počet rep. Zbyla jen věta o selhání (tu souhrn říct neumí, je na
organizaci) a `Policy.organizationRowStatus` se celá zahodila.

**Copilot našel dvě věci a obě jsou opravené.** (1) Souhrn hlásil `Obnovuje se…` pokaždé, když se
tahalo cokoli — tedy i organizace, kterou někdo z pole mezitím smazal; rozhoduje teď **průnik** se
seznamem. Tlačítko `Obnovit` zůstává na prázdnosti množiny a **je to rozdíl, ne tentýž omyl**: ptá se
„běží podproces `gh`?“, ne „děje se něco s tímhle katalogem“. (2) Komentář u detekce sraženého výpisu
tvrdil, že rozhoduje rovnost, kdežto kód má `>=`. Zůstává `>=` jako pojistka pro případ, že by `gh`
vydal víc, než o kolik se řeklo — `==` by takový výpis vydávalo za úplný — a komentář to teď říká.

**Chyba se přiznává u řádku, ne prázdným seznamem.** Organizace, na kterou účet nevidí, a organizace
bez repozitářů dávají obojí prázdno, takže se pod řádkem píše věta z `gh` (`the owner handle "…" was
not recognized…`). Selhané obnovení přitom **nezahodí starý snímek** a jedna nedostupná organizace
**nezastaví ostatní**. Souhrn vpravo bere **nejstarší** razítko (věta `obnoveno 7:58` je tvrzení
o celém katalogu) a organizaci bez snímku počítá **zvlášť** (`1 organizace nenačtena`), aby součet
mlčky nevynechal, co v něm není.

**Tvrdá podmínka č. 1 se nemění** — `repositories(in:)` je čtení, `SingleWayOutTests` prochází beze
změny. **Č. 3 taky**: `catalogs/` leží v cache aplikace a hranici u čtení, zápisu i mazání drží
`CacheFile`, tedy tatáž kontrola jako u nálezů a draftů. Složka se jmenuje `catalogs/`, ne
`repositories/` ze zadání, protože to jméno v `CacheLayout` ukazuje na `repos/` s bare klony.

Testů **4907** ve 479 suitách; nové jsou tři sady (`RepositoryCatalogPolicyTests`,
`RepositoryCatalogTests`, `GhRepositoryListTests`), rozšířené `ConfigurationTests`
a `SettingsFieldsRenderTests` (osm scén, dvě šířky) a fixture `gh/repo-list.json` (skutečný výstup nad veřejným `cli`).
Co se v které z nich hlídá a proč, je v [`docs/testovani.md`](testovani.md).

## #533 — paleta ⌘K: skupina Repozitáře a druhá úroveň s PR repa (M18)

**Poslední kámen M18**, a tím je cesta k libovolnému pull requestu hotová: napíšu `vault`, paleta
najde repo v organizacích z nastavení, `↵` ji přepne **o úroveň níž** na otevřené PR toho repa
a druhý `↵` otevře **záložku ke čtení** (#531). Odkaz už není potřeba mít odkud vzít.

**Přibyla jedna čtecí metoda gateway, jedna úroveň palety a dvě skupiny řádků.**
`GitHubGateway.pullRequests(in repo:)` je **pětadvacátá** čtecí metoda (`gh pr list --state open`);
tvrdá podmínka č. 1 se **nemění ani o položku** a `SingleWayOutTests` prochází beze změny.

**Psaní nedotahuje nic, a je to jediná vlastnost, na které to celé stojí.** V první úrovni se hledá
v katalogu z cache na disku (#532), ve druhé se filtruje dotažený seznam; jediné volání pouští
**vstup do repa**, tedy výslovné `↵`. Je na to test, který počítá volání gateway po pěti úhozech
v první úrovni, po vstupu a po čtyřech úhozech ve druhé — a **ověřený vložením regrese**: s
`refresh` uvnitř skládání řádků padne.

**Katalog rep se přestěhoval z okna nastavení do `AppStore`**, což #532 předpovědělo a nechalo na
tomhle issue. Čtou ho dvě obrazovky (paleta a stránka `Zdroje PR`), takže dvě instance by znamenaly
dvě cache téhož seznamu; typ se kvůli tomu neměnil, protože pravda leží v cache. **Store z něj sám
nic nedotahuje**: při startu přečte, co v cache leží (jenom disk), a dotažení ze sítě zůstalo tam,
kde bylo — otevření stránky, dopsaná organizace, tlačítko `Obnovit`. Výpis rep `keboola` stojí
46,8 s, takže na tik ani na úhoz nesmí.

**Čtyři rozhodnutí, která ze zadání neplynula:**

1. **Řazení rep podle počtu otevřených PR** (pak podle posledního pushe, pak jména). Je to nabídka
   **kam jít**, takže nahoru patří repo, ve kterém je co číst; zákres to tak kreslí (`vault` 7,
   `vault-cli` 2, `php-vault-client` 0). Dvě kritéria navíc jsou proto, aby pořadí nezáviselo na
   tom, jak `gh` seznam vydal.
2. **Druhá úroveň je filtr, ne hledání s vážením.** Nadpis tvrdí `řazeno podle poslední změny`,
   takže by řazení podle váhy shody po prvním písmenu z toho tvrzení udělalo lež. **Strop šesti
   řádků tam taky není** — šest je strop pro skupinu **mezi jinými**, kdežto tady je ta skupina
   obsah celé úrovně.
3. **Řadit se muselo v `Policy`, protože `gh pr list` neřadí podle poslední změny.** Změřeno na
   `cli/cli`: `#14282` s razítkem 28. 8. stálo v odpovědi **nad** `#14259` s 31. 8. Fixture je ten
   skutečný výstup i s touhle dvojicí, takže se to na vymyšleném JSONu nedá omylem „opravit“.
4. **Relativní čas se skládá v `Policy`, ne `Text(date, format:)` ve view** — a je to výjimka proti
   zbytku okna. Podtitulek je **jeden řetězec** (hledá se v něm a zvýrazňuje se v něm shoda)
   a návrh do něj píše `naposledy před hodinou`, tedy slovo, čas a nic mezi tím; rozdělit tu větu
   mezi `Policy` a kresbu by znamenalo, že polovinu podtitulku skládá view. Referenční okamžik je
   proto parametr (`Policy.momentAgo(_:now:)`) — `Date.RelativeFormatStyle` ho vzít neumí.

**Čtyři odchylky od zákresu, všechny s důvodem.** (1) **Patka zůstává v první úrovni `↵ otevřít`**,
i když úzký výřez v zákresu kreslí `↵ do repa`: patka se mění podle **úrovně**, ne podle vybraného
řádku, a návrh to sám říká u sekce `s09link`. (2) **Odznaky `ve frontě` / `moje` jsou v metrice
`DesignPill`** (10,5), ne v `9.5px` z inline stylu zákresu — kapsle stavu má v tomhle okně jedno
místo (#348) a osmá kopie metriky kvůli jednomu bodu je zrovna to, čemu se to místo vyhýbá.
(3) **Relativní čas má v obou skupinách týž tvar** (`před 2 hodinami`), kdežto zákres míchá plný
u repa a zkrácený u PR; dva tvary v jedné kartě jsou horší než jeden. (4) **Stáří posledního pushe
je na každém řádku repa**, kdežto zákres ho kreslí jen u prvního — mizející údaj u druhého řádku
není chování, které by šlo vysvětlit, takže je to zúžení kresby, ne rozhodnutí. Odchylka č. 1
zůstává i po opravě zákresu níž: patka první úrovně v něm má `↵ do repa`, protože ten výřez kreslí
kurzor na řádku repozitáře — a právě to je ten údaj, který se podle úrovně měnit nemá.

**A zákres si ve dvou věcech odporoval sám** — obojí se **opravilo v tomhle PR**, protože je to
rozpor uvnitř už odsouhlaseného zákresu, ne nový návrh (rozhodl uživatel při proklikání). Pořadí
v druhé úrovni mělo `#91 · před 2 h` **nad** `#85 · před hodinou`, ačkoli nadpis nad tím tvrdí
řazení podle poslední změny; teď je kresba přerovnaná od naposledy změněného a kapsle `↵ otevřít`
jde s kurzorem na první řádek, jak to dělá aplikace. A patka úzkého výřezu měla `↑↓ vybrat`, kdežto
hlavní kresba palety `↑↓ pohyb`; sjednoceno na `pohyb` v obou výřezech. Poznámka 60 u sekce to od
téhle změny **říká**, aby kresba neměla jak nadpisu odporovat znovu.

**Ten rozpor našlo srovnání renderu s kresbou, ne čtení.** Aplikace řadila správně od začátku (řadí
`Policy` a tvrdí to test výčtem), takže z kódu ani z textu zákresu se nedalo poznat nic — vylezlo to
teprve tím, že vedle sebe stály dva obrázky a v jednom byl první řádek jiný.

**Prázdný stav rozlišuje „nezeptal jsem se“ od „nenašlo se“**, což byla oprava z vlastní revize:
repo bez otevřených PR není prázdný **výsledek**, ale prázdné **repo**, a `Na „“ nic nesedí` nad
prázdným polem je věta o hledání, které nikdo nezačal. Rozhoduje `Policy.paletteEmpty(at:query:)`.

**A `CommandPaletteView` dostává výsledky uzávěrem, ne katalog.** Do #533 si je počítalo samo
**a zároveň** existoval `AppStore.paletteSections(for:)`, který volaly jen testy — tedy dvě
odpovědi na jednu otázku. Druhá úroveň by musela vzniknout v obou, takže se to svedlo do storu.

**Zapsaná mezera:** že `⌫` na prázdném poli vrací o úroveň a nad napsaným dotazem maže znaky, se
v harnessu ověřit nedá (klávesa v testovacím hostu nezabere). `Policy` tvrdí rozhodnutí
(`paletteBackspaceGoesBack(level:query:)`) a to, že se tlačítko se zkratkou doopravdy neobjeví,
zkouší člověk.

Testů **4958** ve 481 suitách; nové jsou dvě sady (`CommandPaletteLevelTests`,
`GhRepoPullRequestListTests`), rozšířené `CommandPaletteTests`, `AppStorePaletteTests`
a `CommandPaletteRenderProbe` (tři nové scény) a fixture `gh/pr-list-open.json` (skutečný výstup nad
veřejným `cli/cli`). Co se v které z nich hlídá a proč, je v
[`docs/testovani.md`](testovani.md#druhá-úroveň-palety-533).
## #501 — mapa PR: pás pod hlavičkou ze segmentů souborů

Na „jak velký a jak zlý je tenhle PR“ odpovídala pilulka `+248 −96` a pět čtverečků poměru v pruhu
záložek. **Kde** v diffu je to zlé, se z ní poznat nedalo — na to se muselo do stromu, a i tam jen
po puntíku u jména. Od #501 leží mezi hlavičkou a záložkami **pás, ve kterém je každý soubor
segment**: šířka roste s `log₂(řádků + 1)`, barva je nejhorší nález v souboru, nový soubor má tón
`ok`, prošlý (#500) je tlumený, vlákno je svislá čárka a soubor pod výřezem má obrys akcentem.
Vpravo stojí `7 souborů · 3 prošlé · 5 nálezů · 2 vlákna`. Klik skočí na soubor tou cestou, kterou
skáče paleta ⌘K; `⌥←`/`⌥→` posunou o soubor. Je to první issue směru E z milníku **M14** a zákres
se do `docs/navrh.html` přenesl jako **sekce 42**.

**Logaritmus je celé to issue.** Nad rozložením ze sekce 03 návrhu (sedm souborů, `composer.lock`
2 790 řádků z 2 952) by lineární šířka dala locku **94,5 %** pásu a ze zbytku šest čárek;
s `log₂(n + 1)` má **30,8 %** — pořád největší, ale test o 64 řádcích je vidět (175 bodů proti 21
v pásu o tisíci). Míří na to dvojice testů, z nichž jeden si lineární podíl spočítá **vlastní
cestou**, aby bylo vidět, o kolik se pás zhorší.

**Pilulku pás nahrazuje, nedoplňuje** — dvě místa s týmž údajem by se rozešla. Z `PullRequestTabBar`
tím odešla i podoba `Layout.full` (od `labels` se lišila jedině tím, že pilulku kreslila) a `Policy`
přišla o `diffstatBlocks`, protože je pak nikdo nečetl; pruh má **tři podoby** místo čtyř a nejširší
je `labels`. **Číslo `+248 −96` v okně tím ale nezůstalo nikde**, a je to zapsaná ztráta: pás nese
velikost jako plochu, kdo chce čísla, má je v nápovědě segmentu a v hlavičce souboru v diffu.
Popisek pásu odpovídá na jiné otázky, a tak ho má i schválený zákres.

**Obrys se čte z `DiffViewport`, a to bylo to jediné netriviální zapojení**: pás leží **nad** pruhem
záložek, tedy mimo `DiffView`, kde ta krabice do #501 žila jako `@State`. Od #501 ji drží detail PR
v `DiffTracking` a `DiffView` ji dostane parametrem (`nil` = diff commitu a náhled si drží vlastní,
takže se pro ně nemění nic). Cesta souboru pod výřezem je **vlastní `@Observable` krabice**
(`DiffFileCursor`), ne vlastnost `DiffViewport`u — tentýž důvod, jaký #469 mělo pro rozdělení
`band` a `top`: `top` se mění při každém otočení kolečka, tahle hodnota jen na hranici souborů.
Zapisuje do ní neviditelná sonda, takže se pás nepřekresluje při každém snímku. Odpověď dává
`Policy.mapCurrentSegment`, což je `pinnedFileHeader` beze zbytku posunu — **jedna odpověď** pro
obrys, ukotvenou hlavičku i `⌥V`.

**Šířky počítá `Policy`, umisťuje vlastní `Layout`** (#220): `frame(width:)` na každém segmentu by
potřeboval znát celkovou šířku, tedy druhé měření vedle toho, co rozvržení dělá samo (#236). Tři
pravidla drží pohromadě: podíl z logaritmu, minimum tři body **vytlačené z dělení** (bez přepočtu
by součet přerostl pás zrovna u PR s jedním lockem a šesti drobnostmi) a součet přesně na dostupnou
šířku. Když se nevejdou ani minima, dělí se rovným dílem — **segment se nezahodí nikdy**.

**Úzká podoba vyšla ze sondy, ne z návrhu.** Popisek stojí ~230 bodů, takže by v pohledu vedle sebe
(detail 347 b) nechal pásu 73 a ze segmentů byly čárky. Popisek proto **ustupuje první** (práh 180
bodů, `Policy.mapShowsSummary`) a v úzké podobě nese souhrn nápověda — tatáž úvaha jako u `+X −Y`
v pruhu záložek (#316): jeho čísla jsou i v hlavičce stromu a v odznacích záložek, kdežto pás jinde
není. Výšku řádky přitom drží pás (10 b), ne popisek (13 b), jinak by se hlavička při složení
panelu posunula o tři body.

**Odchylky od zákresu** jsou tři a všechny jsou v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--mapa-pr-pod-hlavičkou-501):
úzká podoba, odsazení 16 bodů místo 22 (rozhoduje hlavička nad pásem — změřeno, obojí na x = 68)
a nápověda jako nativní tooltip místo kreslené bubliny.

**Pilulka odešla ze sedmi rámů okna v návrhu** (sekce 02, 03 dvakrát, 04, 19 dvakrát a 25) a pás
tam přišel — to je pravidlo o záznamu dneška (#299), ne překreslování. Jediné místo, kde `.diffstat`
zůstal, je záznam měření stupňů pruhu v sekci 19: je to záznam z #316, ne dnešní obrazovka.

Testů **5000** ve 484 suitách (proti 4958 ve 481 na `main`u po #533); nové jsou tři sady — `PullRequestMapTests` (31 tvrzení nad čistou
funkcí), `PullRequestMapDrawingTests` (9 nad bitmapou) a `PullRequestMapGeometryTests` (6 nad
souřadnicemi a trefením kurzoru) — a sonda `PullRequestMapRenderProbe`
(obrázek přes pásmo šířek 347/647/1047/1347 v obou režimech). Odešla `DiffstatBlocksTests` s funkcí,
kterou hlídala, a dvě tvrzení o pilulce v `TabStripWidthTests` vyměnila **stráž nad zdrojákem**:
`DiffCounts` ani `diffCounts` se do pruhu záložek nesmí vrátit. Katalog zkratek má **27 akcí**
(`⌥←`, `⌥→`); že jsou ty glyfy v monospace písmu kapsle, je doměřené (`←` 1312, `→` 1314). Regrese
ověřena vložením regrese, čtyřmi: lineární váha, `raised` místo `okWash` u nového souboru, `opacity(1)`
místo tlumení a obtah nasazený dovnitř. Co se v které sadě hlídá, je v
[`docs/testovani.md`](testovani.md).

**Pás se musel přepsat po proklikání, a je to nejcennější kus téhle práce.** Ondra ohlásil „zas to
laguje při přepínání oken“ a zúžil to na přepínání tabů uvnitř PR. První podoba dělala ze segmentu
`Button` s nápovědou, dvěma `overlay`y a `contentShape`: u PR o **158 souborech** je to 158 tlačítek
a přes tisíc views v hlavičce — a hlavička se přerovnává při **každém** zápisu do sledované
vlastnosti, tedy při každém tiku pollingu i při každém kliknutí. Naměřeno nad ostrými diffy
(`cli/cli#14320`): **přerovnání okna 70 ms proti 14 ms bez pásu** a přepnutí tabu **bez diffu**
162 ms proti 57. Od opravy je to 19, resp. 63 ms — tedy tři až šest milisekund nad stavem, kdy pás
neexistuje. Segment přestal být view: kreslí ho `Canvas`, polohy počítá `PullRequestMapGeometry`
a nápovědu i klik obstarává jedno gesto (#252 — *nevyjednává se ani počet prvků*).

**Hypotéza, kterou to vyvrátilo, stojí za zapamatování**: nabízelo se, že tělo detailu špiní zápis
z `DiffView`u do `DiffTracking`u, který detail drží. Ablace to vylučuje a kód to vysvětluje —
`DiffTracking` není `@Observable` a `@State` drží jen referenci, takže zápis do `viewport`
zneplatní jedině ty tři malé views, které si `top` čtou. Cena rostla **s počtem souborů**, ne
s výřezem. Aby to sonda vůbec viděla, musela dostat dvě osy: počet souborů a **ostrý diff ze
souboru** — do té doby roztahovala fixture po řádcích, takže měla 9 až 14 souborů a nad pásem se
158 segmenty vydala totéž jako nad pilulkou `+X −Y` (#478).

**Přepnutí na `Změněné soubory` je přitom drahé i bez pásu** (914 až 1 336 ms podle velikosti
diffu) a **to už #501 nezpůsobilo** — ablace to ukazuje na tisícině. Je to pořád cena z #476, jen
nad diffem o 5 700 řádcích ve 158 souborech místo nad 2 000 řádky.

**Odchylka, která z toho vyšla nad zákres:** nad ~160 soubory si minimum tří bodů a šířka pásu
odporují (`3 × 300 + 2 × 299` je 1 498 bodů proti osmi stům), takže **mezera ustupuje dřív než
minimum** (`Policy.mapSpacing`) a z pásu zbude souvislý barevný pruh místo tečkované linky. Nad
300 souborů se to nedostane: `gh pr diff` vrátí nad tím stropem HTTP 406 a diff se nenačte vůbec
(změřeno na `home-assistant/core#181088`, 3 632 souborů). A zaplatilo se **odečítáním**: pás je
jeden accessibility element, ne 158 prvků; k souborům vedou dál strom a paleta ⌘K.

**Po druhém proklikání se v zákresu otevřely dvě otázky a leží tam jako varianty, ne jako
rozhodnutí.** Ondrovi v pásu chyběla **legenda** (z okna se nepozná, co který tón znamená) a k tomu
se zeptal, jestli **nemají být segmenty stejně široké** — na jeho PR bylo deset podobných souborů,
takže se lišily jedině šířkou a proměnná šířka vypadala jako šum. Významů je přitom **sedm** a řádka
pásu má **deset bodů**, takže se do ní všechny natrvalo nevejdou. V sekci 42 návrhu jsou proto čtyři
panely k výběru: **A** legenda na vyžádání z popisku (v řádce nepřibude nic, popover), **B** zkrácená
trvalá legenda místo počtů (natrvalo jen tři tóny závažnosti, souhrn odejde), **C** plná legenda jako
druhá řádka jen na širokém okně (16 bodů chromu, pod ~980 body mizí) a **W** `log₂` proti stejné
šířce na dvou rozloženích. **Vybere se jedno z každé dvojice a ostatní se ze zákresu zahodí** —
v repu nemají zůstat čtyři.

**Zákres si u toho vyžádal jednu opravu, která je věcná:** legenda brala barvy **inline**
(`style="background: var(--crit)"`), tedy z druhého místa než segmenty. Teď je čerpají ze **společného
selektoru**, protože rozejití se škálou by na obrázku nebylo vidět — je to ta samá barva, jen jinde.
V okně tomu odpovídá to, že legenda musí volat **tutéž funkci**, jakou kreslí `Canvas`.

**Copilot našel jednu reálnou věc a byla to zapsaná díra v pravidle**: `threadSpots` vracela u
souboru s nejvýš jedním řádkem podíl `0,5` **každému** vláknu, tedy bez kontroly `matches` — pás by
pak tvrdil diskuzi v souboru, ve kterém pro ni není řádek. Tvrzení `Vlákno mimo hunky čárku
nedostane` to nechytalo, protože běželo nad desetiřádkovým hunkem. Opraveno tak, že pravidlo platí
i v degenerovaném případě (bez řádků se nekreslí nic) a přibyla na to dvě tvrzení.

**Z těch dvou otázek je jedna dotažená a druhá otevřená znovu — a to druhé je výsledek měření.**
Ondra vybral **legendu A** (na vyžádání z popisku) a **`log₂` nechal**, ale s podmínkou: *„zobrazený
file by se měl teda spolehlivě zvýraznit"*. Je to protiváha za proměnnou šířku — když šířka nese
objem, neříká, kde jsem.

**Legenda A je hotová.** Popisek s počty je tlačítko (tečkované podtržení, `▾` — glyf 1126
v monospace písmu, doměřeno jako u kapslí zkratek) a klik otevře popover se všemi sedmi významy.
Dvě pasti, které u toho byly pojmenované předem, se ošetřily obě: **barvu vydává jedna funkce** pro
kresbu i pro legendu (`PullRequestMapView.fill(of:)` nad `PullRequestMapTone`, který tón dostane
segment rozhoduje `Policy.mapFill`), a hlídá to stráž nad zdrojákem — v legendě nesmí stát žádný
barevný token ze škály. A **legenda nevrátila to, co se zlevnilo**: popover se staví, až se otevře,
`isOpen` drží vlastní view (ne tělo pásu) a `.popover` visí na nulovém kotvicím view. To poslední je
změřené, ne odhadnuté: nasazený přímo na tlačítko zdražil průchod tělem pásu při 158 souborech ze
3,0–4,8 na **7,1–7,3 ms**, na kotvicím view je to 5,1–5,2 ms. Zbytek toho rozdílu se ale
**neprokázal** — ty podoby se měřily v samostatných bězích a stroj mezi nimi driftoval, takže je
v `docs/testovani.md` zapsané, co by bylo potřeba (prokládaná série, tedy přepínač v produkčním
kódu, který jsem nedal).

**Zvýraznění se změřilo a dnešní obrys ho neunese.** Z bitmapy, přes pásmo počtů souborů (3 až 158)
a šířek okna (347 až 1347 b), metodou „dva snímky téže scény a rozdílové body“: podíl toho, co
z obálky značky je **cílový segment**, je 91–98 % u tří souborů, 74–94 % u sedmi, 62–90 % u desíti,
44–83 % u dvaceti, **27–60 % u pětačtyřiceti** a **21–30 % u sto padesáti osmi**. Hranice je
u ~19 bodů šířky segmentu — obrys je totiž **odstup od segmentu**, takže je vždycky o osm bodů
širší než to, co obtahuje. A druhé číslo: při 158 souborech má celá značka **39 b² inkoustu** ve
dvou svislých čárkách dvou bodů, tedy **přesně tolik a přesně toho tvaru, co jedna čárka vlákna**
(36–44 b²). Kontrast akcentu proti ploše hlavičky je přitom v pořádku při každé šířce, takže
**samotné číslo z palety netvrdí nic** (#432).

**Obrys nahradil `jezdec`** — pevný trojúhelník 14 × 7 bodů pod pásem s hrotem v ose segmentu,
odsouhlasený 2. 9. 2026. Tři vlastnosti, kvůli kterým takhle: velikost nezávisí na šířce segmentu,
hrot je bod (ukazuje přesně, i když je značka širší než cíl) a tvar se nedá splést s čárkou vlákna.

**Že podmínku splňuje, je změřené tou samou metodou, ne prohlášené**: značka má **12–14 × 7 bodů
a 34–56 b² inkoustu ve všech kombinacích**, zatímco segment pod ní se mění z 1,4 na 433 bodů — a
protože je nad hustým pásem širší než cíl, rozhoduje **hrot**: odchylka od středu segmentu je
**0,0 až 0,6 bodu** a hrot leží v segmentu **ve všech 36 kombinacích**. Hlídají to **tři tvrzení
nad bitmapou**, protože „někdo to zítra zmenší" je reálná cesta, jak podmínku zrušit beze změny
čísel v `Policy`. **Ověřeno vložením regrese, třemi** — a ta třetí je poučná: hrot sevřený do
plochy (aby byl jezdec symetrický i na kraji) **projde uprostřed pásu** a spadne až na krajním
segmentu, takže první podoba toho tvrzení s jedním cílem regresi propustila.

**Hrot zůstává na skutečném středu segmentu, základna se ořezává do plochy** — na kraji pásu je
tedy jezdec nesymetrický, a je to vědomá volba: posunutý hrot by ukazoval na soubor, který to není.
Obrys měl na krajích tutéž vadu nepřiznaně (vnější hrana na `x = −4`, `Canvas` ji potichu ořezal).

**Jezdce kreslí i všech sedm rámů okna v dokumentu** (sekce 02, 03 dvakrát, 04, 19 dvakrát a 25),
takže si kresba neodporuje. Obrys zůstal jedině v panelu *Proč obrys odešel* jako **záznam
měření** — je to tentýž vztah, jaký má pilulka `+X −Y` k sekci 19.

**A hover dostal vlastní vrstvu, což je úklid na vlastním důvodu, ne oprava naslepo.** Dokud
`hovered` drželo tělo pásu, čtl ho popisek nápovědy v témže těle jako `Canvas` — přejezd hranice
segmentu tedy přeložil tělo a překreslil celou kresbu. Změřeno: jeden průchod tělem stojí při 158
souborech **7,2 ms**, a segment má při té hustotě dva až tři body, takže jeden přejezd pásu myší je
**157 hranic, tedy 1,1 s CPU hlavního vlákna**. Že to hover doopravdy nespustí, se v harnessu
ověřit nedá (offscreen okno hover nedostane, `CGEvent` je v testech zakázaný, #490), takže se to
tvrdí **nad zdrojákem** a je to zapsaná mez. **Ondrův nekliknutelný segment to nevysvětluje**
a nepředstírá se to: oprava nesymetrické trefné plochy je v předchozím kole a tohle je jiná věc.

**Sekce 42 se zúžila na vybrané podoby.** Panely B, C a W jsou z repa venku i s jejich CSS
(`.rv-legend.inline`, `.rv-legend.row`, `.rv-narrow`, `.rv-medium`); z W zůstala **poznámka 144**
o tom, že šířka nese objem a že `log₂` byl v zadání #501 jmenovitě, a v ní i odchylka o ustupujících
mezerách nad ~160 soubory, která **platí dál**.

## #537 — souběžné issues si v mockupu berou totéž číslo sekce

Pravidlo z reálné srážky, nic v aplikaci. Ve vlně 1 milníků M14 a M18 běžely souběžně **#500**
(PR #536) a **#531** (PR #535), obě měly v zadání přenést svůj zákres do `docs/navrh.html` jako
„další volné číslo proti `main`u“ — a obě si vzaly **`s40`**.

**Git to nenahlásil.** Jsou to dva bloky na různých místech souboru, takže by se slily čistě
a v repu by zbyly dvě sekce s týmž `id`; `#s40` vede vždycky na tu první, takže odkaz z druhého
PR i z jeho issue míří na cizí obrazovku. Našel to orchestrátor před mergem a přečíslování #531
na `s41` zadal ručně; od té doby čísla **přiděluje v zadání** (#501 → `s42`, #503 → `s43`,
#527 → `s44`).

**Podruhé, ne poprvé.** Přesně tohle se stalo u #401 a #410 a #410 z toho zapsalo kontrolu čísla
proti `mainu` v den publikování. Ta kontrola je v pořádku a platí dál, jenom na tuhle třídu
nedosáhne: obě větve se proti `mainu` porovnaly správně a obě dostaly tutéž odpověď. Chytá větev,
která leží týden — souběh dvou zákresů z jedné vlny ne. Pravidlo tedy nebylo špatně napsané,
bylo na **špatné straně**: u toho, kdo číslo používá, místo u toho, kdo ho rozdává.

**Druhá polovina je publikovaná kopie.** Publikování není merge (#410) — nahraje se celý dokument
a to předchozí z něj zmizí —, takže agent od #501 publikoval ze své větve a **smetl sekci `s43`**
z branche #503, a agent od #533 publikoval a smetl `s42`. Rada „naposled publikuje ten, který se
má ukazovat“ na to v dávce nedosáhne, protože je to plán a **pořadí mergů se neurčuje předem**.
Pravidlo se proto váže na merge: **publikuje každý, kdo merguje, a v pořadí mergů** — každé další
publikování jde ze stavu, který obsahuje i to předchozí, takže poslední merge srovná i to, co
smetl ten před ním, a nikdo nemusí vědět, že je poslední.

Zapsané je to do [`docs/paralelni-vyvoj.md`](paralelni-vyvoj.md#číslo-sekce-v-mockupu-přiděluje-orchestrátor)
(řádek `docs/navrh.html` v tabulce §1, nová podsekce s pravidlem a bod v zadání subagenta v §3),
do [`docs/navrh.md`](navrh.md) na tři místa a jednou větou do `CLAUDE.md` u sekce *Návrh
(mockup)*; velikost `CLAUDE.md` po tom je **84,9 kB** proti stropu ~100 kB.

**Ověření je grep, ne test** — vada nevzniká v repu, ale v pořadí dvou větví, které v jednom
pracovním stromě nikdy naráz nejsou. Nad slitým stavem musí vyjít prázdný:

```bash
grep -o 'id="s[0-9]*"' docs/navrh.html | sort | uniq -d
```

**A jedna věc se u toho ukázala jako levnější než čtení.** Agent od #501 chtěl vědět, jestli na
adrese neleží něco cizího, a místo přečtení **15 847 řádků** publikované kopie ji prohnal `diff`em
proti repu — bajt na bajt, bez spálení kontextu. Je to v `docs/navrh.md` u postupu porovnání,
protože „souhlasí znak po znaku“ je tvrzení o celém souboru, kdežto čtení je tvrzení o tom, čeho
si kdo všiml.

Na obrazovce se nemění nic; testů dál **4958** ve 481 suitách, beze změny.
## #527 — záložky přežijí restart

**Aplikace se podle pravidel repa restartuje `bin/run.sh` po každém mergi**, takže do #527 každý
merge zavřel všechno rozečtené a scroll v diffu se ztratil. Od #527 leží snímek pruhu
v `tabs.json` v kořeni cache slotu: identita PR, tab v ní, kotva scrollu jako **soubor a řádek**
a která záložka byla aktivní. Zapisuje se **při každé změně záložky a při ukončení**, čte se
**jednou** při startu — jako **první** krok `keepFresh()`, tedy před prvním tikem. Zákres je
v [sekci 44](navrh.html) návrhu (deck *Směry pro PRism*, stránka *Tření › T1*).

**Nejcennější věta celého issue: obnovení nic nespouští.** Nepustí review ani session, nepřipraví
pracovní kopii a nepřidá nic do fronty — dotáhne **detail**, a to čtením (`gh pr view` přes
`GitHubGateway`, který zápisové metody nemá). Automat čte `summaries` z tiku, takže se o obnovené
záložce nemá kde dozvědět (#4). Test na to má scénu **s prázdnými zdroji a zapnutým automatem**,
tedy ve stavu, kde je otevřená záložka to jediné, co by se dalo spustit; **ověřeno vložením
regrese** — `startReview` v obnovení shodí tři tvrzení.

**Puntík načítání je nový, pátý stav značky u záložky** — a je to jediná odchylka od zákresu.
Deck ho kreslí prstýnkem (`.spin`), jenže ten v tomhle okně znamená **běží review** (nápověda to
říká doslova) a po startu neběží nic; reuse by tedy pár sekund po každém startu tvrdil, že na
každé obnovené záložce běží review. Deck si přitom v poznámce sám říká, že je to *třetí věc* —
kresba jen sáhla po existující třídě. V aplikaci i v sekci 44 je proto **dutý nehybný kroužek**
(`.tdot-load`, `Palette.ink3`) a v návrhu je u něj napsané, proč `.dot` ani `.spin` nestačily.

**Značku skládá `Policy.tabMark`, ne `if`y ve view.** Pět pater — běh, načítání, rozdělané review,
mergnutý/zavřený PR, stav review — je rozhodnutí nad daty a jediné, co o něm jde tvrdit, je
**pořadí**. `ReviewTabsView` proto přišel o tři vstupy a dostal jeden. **Mergnutý a zavřený PR
kreslí stav pull requestu**, ne review: od nálezů se u nich další práce neodvíjí, dá se to jedině
dočíst a zavřít — a **zavírá to člověk, ne tik pollingu** (pravidlo z #67 tím dostalo druhou
půlku: teď se dá dočíst i po restartu).

**Značka přijaté záložky se z množiny stala mapou s důvodem** (`adoptedTabs`, `TabAdoption`:
`link` z #531, `restored` z #527). Obnovená záložka potřebuje totéž ve třech věcech (shrnutí
z detailu, přežití úklidu po tiku, `loading` místo `gone`) a liší se v jedné — pilulce
`mimo zdroje`, kterou **nedostane**: obnovení běží před prvním tikem, takže by bliklo u každé
záložky a u těch, které z fronty vypadly, by tvrdilo „otevřel jsi ho odkazem“. Druhá množina vedle
té z #531 by znamenala tři místa, na kterých se dá zapomenout jedna z nich, a potichu.

**Kotva scrollu je soubor a řádek, ne offset.** Offset po restartu neplatí — diff se v pohledu pod
sebou zalamuje podle šířky okna (změřeno u #152: odhad z počtu řádků byl proti skutečnosti
trojnásobně mimo). Posadí se **tou samou cestou, jakou skáče paleta na nález** (#152 a #325,
včetně druhého průchodu nad přeměřenými rozměry), takže sedne stejně dobře — a stejně nedokonale.
Hlásí ji **vlastní neviditelné view** (`DiffAnchorReporter`), ne tělo `DiffView`u, protože čte
`DiffViewport.top`; je to aritmetika nad krabicemi mimo observable stav, ne dotaz do grafu SwiftUI
(u #469 bylo drahé právě to druhé, 3,5 s CPU proti 0,19 s). Cíl **není sledovaná vlastnost**
(`@ObservationIgnored`), takže posun výřezu nikoho nepřekresluje, a na disk to jde s příští změnou
záložky nebo při ukončení — při scrollování se na soubor nesahá.

**Zapsané meze:** rozbalený kontext (#47) číslo řádku nenese, takže se výřez uvnitř velkého
odkrytého úseku obnoví na nejbližším řádku hunku pod ním; odebraný řádek má číslo ze staré verze
souboru, takže se bere první přidaný nebo kontextový pod ním. Obojí je degradace na „o kus vedle“,
ne na „jinde“. A **nečitelný snímek znamená prázdno**, ne chybu v okně: nejhorší následek je jedno
spuštění bez záložek, tedy stav před #527.

**`PullRequestTab` je od #527 `Codable`, a je to zapsaná změna proti jeho vlastní poznámce.**
Ta říkala „neukládá se, jinak bychom si pamatovali, na co se člověk koukal minulý týden“ — a platí
dál: volba **není** klíčovaná pull requestem na disku, ukládá se jako součást otevřené záložky
a se zavřením odchází.

**Tvrdé podmínky beze změny.** Č. 1: `SingleWayOutTests` prochází beze změny, grep na
`ReviewPublishing` i `BranchPushing` vypisuje týž seznam souborů. Č. 3: `tabs.json` leží v kořeni
cache slotu a hranici drží **tatáž kontrola jako jinde v repu** (`CacheFile.refusal`); kořen si
aplikace bere z `CFBundleName`, takže slotová separace (#228) je hotová bez řádku navíc.

**Copilot našel tři věci a všechny byly reálné**, dvě z nich tichá ztráta polohy v diffu.
(1) Snímek se skládal jen z `diffScrollAnchors`, které jsou po startu prázdné, takže **zápis hned
po obnovení kotvu smazal** — záložka, do jejíhož diffu se člověk nepodíval, by po druhém restartu
začínala na začátku. (2) `DiffAnchorReporter` hlásí polohu i **při vzniku**, tedy dřív než skok,
takže první hlášení nad nenaskrolovaným diffem uloženou polohu přepsalo za začátek souboru. Obojí
teď drží jedno pravidlo — *nedoposazená kotva je pořád ta poslední známá poloha* — a obojí má test
ověřený vložením regrese. (3) Doprovodná dokumentace zúžila `WindowTabMark.loading` na „obnovená
po restartu“, přitom ten stav dostane i záložka otevřená odkazem (#531); opraveno **jako třída**,
tedy včetně `README` a popisu parametru, ne jen na tom jednom řádku.

**Zapsaná mezera:** že se výřez po restartu doopravdy posadí tam, kde stál, se v harnessu ověřit
nedá — `ScrollView` se v testovacím hostu nevykreslí a skok je podle #152 **zmírnění, ne záruka**.
Zkouší to člověk na běžící aplikaci; já to změřil na slotové instanci (viz popis PR). K tomu
zbývá **jeden průchod grafu** mezi spotřebováním kotvy a skokem, ve kterém platí poloha před
skokem — zabité aplikaci v tom okamžiku se kotva posune o výřez.

Testů **5005** ve 486 suitách; nové jsou čtyři sady (`WindowTabMarkTests`,
`DiffScrollAnchorTests`, `OpenTabsStoreTests`, `AppStoreTabRestoreTests`), rozšířené
`PullRequestOriginTests` a `AppDelegateTerminationTests` a k tomu sonda
`WindowTabStripRenderProbe` (pruh se všemi pěti značkami, pouští se ručně jako ostatní sondy).
Co se v které z nich hlídá a proč, je v [`docs/testovani.md`](testovani.md).


## #503 — nálezy stojí v okraji vedle svých řádků (M14)

První a největší kus směru B z decku *Směry pro PRism*: pravý sloupec v tabu `Změněné soubory` se
stal **okrajem**, jako mají komentáře v Google Docs nebo ve Figmě. Karta nálezu stojí na výšce
svého řádku, řádek s kartou má na pravé hraně 3bodový pruh závažnosti a mezi nimi vede spojnice;
když se dvě karty potkají na sousedních řádcích, druhá jde níž a spojnice se zalomí do `L`. Kód
zůstal souvislý — bubliny pod řádky nezmizely, jen se přestěhovaly za přepínač `Nálezy pod řádky`,
aby šlo obojí porovnat a změřit. Zákres je v [`docs/navrh.html`, sekci 43](navrh.html).

**Karta vzniká z dat, poloha z geometrie.** O tom, které karty v okraji jsou, rozhoduje
`Policy.marginCards` nad diffem (soubor rozbalený, řádek se doopravdy kreslí); kdyby o tom
rozhodovalo hlášení z bloku, karta by zmizela pokaždé, když je její blok mimo nasazený pás (#469).
Nález **bez řádku** proto v okraji není a zůstává tam, kde byl: jako bublina u hlavičky souboru —
právě kvůli němu se přepínač netýká všech bublin, jen zakotvených, jinak by se tiše ztratil.

**Panel vpravo se pod okrajem složí, nezmizí** (`Policy.diffSideColumns`). Dokud panel drží seznam
nálezů, byly by vpravo dvě třistabodové kolony o téže věci; `⌘2` panel vrátí, jako u složení
sloupců ve split pohledu (#188). Je to **mezistav** — seznam v panelu ruší #504.

**Projíždění se změřilo, a poprvé to vyšlo špatně.** Se všemi kartami stálo gesto (150 × 40 pt,
2000 řádků, 11 nálezů) **1,65 / 1,67 s** CPU proti **1,47 s** nad tímtéž diffem bez nálezů. Karty
se proto nasazují **stejným pásem jako bloky** (`Policy.isBlockMounted`, #469) a číslo spadlo na
**1,56 / 1,53 s**, tedy 6 % nad základem a asi 0,5 ms na snímek; bubliny stojí 1,46 / 1,47 s, tedy
nic. Zbylých 6 % je cena za druhou vrstvu nad blokem a **zůstává** — okraj proti tomu ubral
z dokumentu 1 200 bodů, protože bubliny do něj kód rozrážely.

**Tři věci se u toho našly měřením, ne uvažováním.** (1) Nezměřený blok **nesmí hlásit ani
prázdno**: prázdné hlášení sundá starou polohu, takže si blok při každém přestavění přepsal
platnou polohu na nic — karty stály na sobě u horní hrany. (2) Rámečky řádků se musí posílat
**i argumentem**, ne jen přes `@State`: zápis do `frames` je vidět až v dalším průchodu tělem,
takže `noteRows()` hned za ním čte nulu, i když textové view zrovna ohlásilo devět. Plnilo se to
pak teprve z `onGeometryChange` — u tažení rozsahu to nikdo nepoznal, u karty v okraji není na co
čekat. (3) Sonda projíždění **vyhladověla hlavní aktor** (`RunLoop.current.run(until:)`), takže
měřila scénu, do které se rámečky nikdy nedostaly; čeká se proto `await`em a na **odpojení bloků**,
ne na odmlku (nerozvržená scéna dá 9,1–9,7 s místo 1,4–1,5 s).

**Tvrdé podmínky se nemění.** Okraj nic neodesílá — `SingleWayOutTests` prochází beze změny —
a nálezy jsou dál klíčované `headSha`; karta je jen jiné místo pro tentýž `FindingBubbleView`,
takže odznaky, shoda reviewerů, stav z kontroly (#150), odmítnutí (#113) i řada
`Převzít · Neplatí · Nepatří sem` (#283) zůstávají, jaké byly.

**Druhé kolo měření na ostrých datech** (po slití `main`u). Čísla z první verze jsou z vyrobené
scény — jeden soubor o dvou tisících řádcích —, takže na otázku „laguje to v praxi“ neodpovídají.
Druhé kolo proto měří **skutečné diffy** (`PRism#499`, `cli/cli#14104`, `cli/cli#14320`) a k tomu
**druhé gesto**: přepnutí na tab `Změněné soubory`, tedy to, na kterém se lag pozná — přepnutím se
obsah tabu zahodí a postaví znovu, takže se platí první rozvržení, kdežto projíždění tuhle třídu
změny nemusí ukázat vůbec.

**Nálezy na jednom z nich jsou skutečné.** Review nad `PRism#499` proběhlo touž cestou, jakou pouští
aplikace (`code-review:code-review`, tatáž sada povolení, prompt z `Policy.reviewPrompt`): 84 tahů,
14 minut, 21,97 USD — a **dva** nálezy na 45 souborech a +4 670 řádcích. Rozeseté nálezy sondy
(jedenáct) jsou tedy pětinásobek běžné hustoty, tedy horní odhad, ne obraz.

**A krajní případ z referenční sady aplikace nedostane vůbec**, což je vlastní nález: `gh pr diff`
nad PR o víc než 300 souborech vrací `HTTP 406`, a `GhGateway.fetchDiff(id:)` je zrovna
`gh pr diff` — takže `home-assistant/core#181088` (3 632 souborů) skončí na `.failed` dřív, než se
diff začne kreslit. Na rozdíl od logů z CI, které mez mají a **pojmenovanou**
(`Policy.logAvailability` → `.tooLarge`), diff žádný takový stav nemá; v okně je z toho obyčejná
chyba. Opravit to sem nepatří (je to jiná vrstva než okraj), ale zapsané to být musí.

**Oprava z proklikání: obsah diffu zalézal pod boční proužky.** `Policy.diffSideColumns`
rozhodovala jen podle pohledu, takže se v úzkém okně sešly strom (210), kód a okraj (300) v jednom
`HStack`u — a `HStack` rozdíl, který se nevejde, přesype doprava, tedy pod složený proužek panelu.
Naměřeno v okně 700 (podlaha `RootView`u): **35 bodů** s okrajem, **16** bez něj, v obou pohledech;
na obrazovce ukousnuté `+347 −0` v hlavičce souboru. Od téhle opravy je **šířka vstupem** rozhodnutí
a kolony se **odečítají**: kód nikdy neustoupí, strom jde první (`⌘1` ho vrátí), okraj až potom —
a **nikdy tak, aby nález zůstal bez domova**, takže se s ním rozloží panel, který karty převezme.
Zpětná vazba přes panel je monotónní, proto se to ustálí na první průchod. Přes celou mřížku
(pásmo šířek × pohled × okraj × ruční `⌘1`/`⌘2`, 64 případů) je přetečení **0**; před opravou až 35.
Zbylá mez je vědomá: v okně na podlaze se lišta diffu ořezává uvnitř své kolony, což patří k #505.

Testů **5110** v 501 suitách; nových je **devět** sad (`DiffMarginTests` nad
`Policy`, `DiffMarginPlacementTests` nad oknem, `DiffMarginScrollReadTests` nad zdrojáky
`DiffColumnFitTests` nad šířkami kolon a tři ruční měření — `DiffMarginWheelProbe` nad vyrobenou
scénou, `DiffMarginSharpProbe` nad skutečnými diffy, `DiffColumnFitProbe` nad rámci kolon v okně,
`CharactersPerSideProbe` nad tabulkou znaků na stranu a `CharacterGaugeAfterSwitchProbe` nad
ukazatelem po přepnutí pohledu).
Co se v nich hlídá a jak se měřilo, je
v [`docs/testovani.md`](testovani.md#okraj-na-ostrých-datech-503-druhé-kolo).

## #546 — obsah diffu se sází na svou kolonu

**Vada na `main`u, kterou bylo vidět při každém otevření diffu**: obsah se sázel na plochu širší,
než jakou dostal, a přesah odcházel **doleva** přes rail — levá polovina splitu tím přišla o čísla
řádků, cesta souboru začínala uprostřed a text uprostřed slova. Druhý projev téže vady byl
ukazatel `N znaků na stranu`: v okně 1 512 hlásil **84** nad kolonou, do které se jich vejde 62.

**Hypotéza ze zadání se nepotvrdila** a je to zapsané. #503 tipovalo, že `contentWidth` drží šířku
okna, protože je to `@State` z `onGeometryChange` a ten se při nezměněné hodnotě nespustí (#361).
Diagnostika ukázala opak: `onGeometryChange` běžel a měřil poctivě **tu plochu, na které stál** —
jenže ta plocha byla 1 110 b nad kolonou 970 b. Příčina je řetěz: `\.availableWidth` v podstromu
diffu zůstávala štěrbina **celého tabu**, `ThreadBubbleView` k tomu nezúžila prostředí o své
odsazení (`indent 84 + trailing 16`), `ScrollView` se v nescrollované ose řídí velikostí obsahu
a `fillingSlot()` tu přeteklou plochu **vystředil**. Sedí to na bod na třech živých měřeních
(obsah = štěrbina + 100 b) a ablace to potvrdila z druhé strany.

**Oprava je předání, ne dohadování** (#220): `Policy.diffCodeColumnWidth` počítá kolonu jedinou
aritmetikou (štěrbina − strom − okraj − mezera z #503), `DiffView` ji posílá **do prostředí i do
lišty**, a `ThreadBubbleView` se zúží o vlastní odsazení. Ukazatel je tím **důsledek**, ne cíl
opravy. `fillingSlot(alignment: .topLeading)` je pojistka: budoucí přetečení půjde vpravo, kde ho
zakryje okraj, ne doleva přes rail — a **vadu to nezakrývá**, protože šířka plochy se dál měří
a test na ni vidí. Sweep nad celým `App/` našel ten vadný tvar (`filling()` uvnitř odsazení bez
zúžení) v **jednom** souboru ze čtrnácti, které obojí mají.

**Čísla před/po** (živé okno 1 100 × 700, `Vedle sebe`, strom složený): kolona **970 b**, obsah
**1 110 → 970 b**, plocha **1 127 → 987 b** (rozdíl je pás posuvníku), ukazatel **58 → 49**.

**Diagnostika kreslení umí od #546 vypsat šířky** (`WidthSite`: štěrbina, spočítaná kolona,
změřená plocha) — na vlastní řádek a **i v klidném úseku**, protože kolony se rozvrhnou jednou
a pak se celé minuty nehnou.

Testů **5119** v 502 suitách; nová je jedna sada nad oknem (`DiffCodeColumnWidthTests` — pásmo
štěrbin × pohled × okraj, druhá polovina tvrzení nad měřidlem) a tři tvrzení v `DiffColumnFitTests`
nad `Policy`. **Ověřeno vložením regrese, obou polovin zvlášť.** Jak se to měřilo a proč to
hostované okno do #546 nereprodukovalo, je
v [`docs/testovani.md`](testovani.md#neověřená-mezera-71-znaků-na-stranu-v-živém-okně--vyřešeno-546).

## #548 — výchozí stav diffu jsou zase bubliny pod řádky

**Poznatek z používání, ne oprava chyby.** #503 postavilo nálezy do okraje vpravo a udělalo z toho
výchozí stav; proklikání po mergi ukázalo, že se ta kolona platí **300 body natrvalo** — i v souboru
bez nálezu, tedy skoro pořád. V okně 1 512 je to **pětina** šířky a ve `Vedle sebe` se bere
z kolony, která se ještě dělí na dvě strany, takže se platí dvakrát. Zákres to nepředvídal, protože
kreslí PR **s nálezy**; v běžném čtení jsou nálezy na pár řádcích z dvaceti souborů.

**Mění se jedna hodnota** (`DiffView.showBubbles` má výchozí `true`), okraj zůstává **za
přepínačem** `Nálezy pod řádky` a v kódu celý — zapnutí je jedno kliknutí. Odvozuje se z ní
všechno ostatní: prázdné `marginCards`, tedy `hasMargin == false`, tedy **nesložený panel**
(návrat k #188) a kolona kódu o **300 b širší** i s ukazatelem `N znaků na stranu`.
`Policy.codeColumnTrailingGap` (6 b, #503) **zůstává** — platí i na složený proužek panelu, ne
jen na okraj.

**Klíč `showInlineFindingBubbles` se nepřejmenovává, a je to rozdíl proti #503.** Tam se otočil
význam hodnoty, takže se starý klíč zahodit musel; tady se otáčí jen výchozí hodnota, takže je
uložená volba dál platná odpověď a nový klíč by zahodil rozhodnutí toho, kdo si okraj vědomě nechal.

**Změřené kolony** (kolona kódu podle `Policy.diffCodeColumnWidth`): 1 213 / `Vedle sebe`
**1 173 b** s bublinami proti **873 b** s okrajem; 1 422 / `Pod sebou` **1 206** proti **906**.
Rozdíl je 300 b v sedmi případech z osmi. Ten osmý je **správná odpověď, ne výjimka**: na podlaze
okna (štěrbina 610) v `Pod sebou` automatika okraj zahodí **a k tomu složí strom**, takže s okrajem
vyjde kolona naopak širší (**570 b** proti 394 b). Tvrzení „bubliny mají o 300 b víc“ se proto váže
na `columns.margin`, ne na šířku okna.

**Změřeno na živém okně** (slot `a`, 1 100 × 700, PR s jednou skupinou nálezů, přepínáno za
běhu): ve `Vedle sebe` **49 → 31 znaků na stranu** (kolona 970 → 670 b), tedy plných 300 b, protože
tam panel složilo už #188. V `Pod sebou` je to **48 → 44 znaků**, protože okraj panel **složí** a
300 b se skoro vrátí — cenou je tam **panel** (composer review, labely, `Větev`, `Zadání`), ne
kolona. Ta druhá řádka je ta neintuitivní část a patří k rozhodnutí.

**Tři z těch čtyř čtení sedí na vypočítanou kolonu na jeden znak**, což je zároveň kontrola
ukazatele z #546 na živém okně. Čtvrté (`Pod sebou` s bublinami, hlášeno 48 místo dopočítaných 49)
je **zapsaná mezera**: zpětně z něj vychází rozložený panel o 302–310 b místo konstanty 300.
Na rozhodnutí to nemá vliv a doměří to diagnostika kreslení (`WidthSite`).

**Zamítnuto: zahodit okraj úplně.** Vypnutý okraj **nestojí nic** (`marginCards` vydá prázdno na
prvním `guard`), kdežto zahození je nevratná práce, po které by vrácení bylo znovu celé PR #540.
Vrátíme se k tomu, až se ukáže, že si okraj **nikdo nezapíná**. **#504 a #505 se odkládají** z M14
do `Průběžné` — obě na okraji stojí a dělat je pro stav, který se neukazuje, je práce naslepo;
zbytek M14 (#502, #506, #507) je mapa a itinerář, těch se to netýká.

Testů **5124** v 503 suitách; nová je jedna sada nad oknem (`DiffBubbleDefaultTests` — výčet tří
stavů klíče × pásmo šířek × oba pohledy, panel, **přepnutí tam a zpět** a to, že bubliny doopravdy
zabírají svislé místo) a jedno sdílené hledání plochy obsahu (`NSView.diffContentArea()`).
**Ověřeno vložením regrese**: s výchozí hodnotou zpátky na `false` padnou čtyři tvrzení z pěti
(37 nálezů), zelené zůstane jen to nad `Policy`, které na výchozí hodnotě nezávisí. Co se v té sadě
měří a proč, je v [`docs/testovani.md`](testovani.md#výchozí-stav-diffu-jsou-bubliny-pod-řádky-548).

## #550 — tři starší stráže se daly obejít mezerou a `FontMetric` vydal nepoužitelnou nulu

Dvě věci z téže třídy jako #367, #411, #407, #462 a #490: **test tvrdí něco o prostředí, ne
o kódu**. Obojí vypadlo z práce na #490 a #152 jako zapsaná mezera a ani jedno se tam neopravovalo.
Rozhodnutí i zamítnuté varianty jsou
v [specifikaci](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--nepoužitelná-metrika-je-nil-ne-nula-550),
měření a vložené regrese
v [`docs/testovani.md`](testovani.md#páté-kolo-stráž-nad-surovým-textem-a-nula-z-měřidla-550).

**Stráže hledají v kódu bez mezer.** `UnanimatedWindowTests`, `GlobalAppearanceTests`
a `FontMetricTests` porovnávaly surový text, takže jim `orderFront (nil)`, `NSApp . appearance`
i `?? AppAppearance` (u zákazu, tedy **otevřená druhá cesta k `NSApp`**) prošly. Od #550 hledají
v `Source.condensed`, stejně jako `WheelEventTests` z #490 — a zhuštění je **uložené, ne počítané**,
protože jeden průchod přes 518 zdrojáků (5,1 MB) stojí 0,23 s a stráž se ptá až třikrát.
Seznamy výjimek se přitom **nezhušťují**
— jsou to cesty, ne text — a výčet povolených importů v `GlobalAppearanceTests` taky ne, protože
whitelist se mezerou obejít nedá.

**Zadání mělo u `FontMetricTests` jiný vzor, než který byl doopravdy dírou.** `maximumAdvancement`,
`defaultLineHeight` a `boundingRectForFont` jsou **jedno slovo**, takže je mezera rozdělit neumí;
obejít se dalo `FontMetric . shared` u kladného tvrzení. Zhuštění se přesto nasadilo i na ně —
rozhodovat u každého vzoru zvlášť je práce, na které se dřív nebo později udělá chyba.

**Nepoužitelná metrika je `nil`, ne nula.** #407 zavedlo jedno měřidlo a ověřilo, že vada je
přechodná, ale nepovedené měření z něj vypadlo jako **nula** — tedy jako měření.
`CommitPanelRoomTests` proto padaly zprávou `šířka znaku: 0`, kterou měřidlo o zlomek sekundy
později skládalo už z 8,036. Od #550 je primitivum `FontMetric.metric(_:of:) -> CGFloat?`; tři
pojmenované metody vydávají `CGFloat` dál a nulu z nich dělá **jedno místo**, protože z nich kreslí
okno a to čekat nesmí. **Nula tím zakrytá není**: rozhoduje o ní dál `Policy.usableFontMetric(_:)`,
takže legitimní nula by se vydala jako `.some(0)` a od `nil` se pozná.

**Kdo si čekání dovolit může, ten čeká.** Testy a sondy berou `TestWait.settledFontMetric(_:of:)`
(v `Tests/Support/TestWaiting.swift`, protože čekání má jedno místo, #296) — synchronně, se stropem
**5 s** místo `deadline` 120 s, protože blokuje vlákno; a když se nedočká, **zapíše nález** a test
spadne větou o metrice, ne číslem o šířce. Převedeno je **čtrnáct** čtení v deseti sadách a sondách; hlídá to
`FontMetricTests` dvěma tvrzeními — pět jmenovaných sad **čeká** a měřidlo si přímo nebere nikdo
mimo tři vyjmenované výjimky (stráž, `FontMetricProbe` a `CodeTextSheetSizingTests`, která
schválně čte touž nečekající cestou jako aplikace).

**Na tomhle není co vidět** — `App/` se změnilo o jednu novou metodu a tři `?? 0`, kresba dostává
tutéž hodnotu jako do #550. **Deset plných běhů, všechny zelené** (pět nad mezistavem, pět nad
výsledným kódem; 106,7–124,3 s, load 6,7–12,9, ve třech z nich souběžný build sousedního slotu —
`CommitPanelRoomTests` padaly právě pod zátěží). Testů **5128** ve 503 suitách; nové jsou čtyři (rozdíl `nil` proti nule,
vzdání se čekání nahlas, stráž nad zhuštěným kódem u `GlobalAppearanceTests` a zákaz nečekaného
čtení měřidla v `Tests/`). **Ověřeno vložením regrese** u každé stráže v **obcházející** podobě
a u měřidla vrácením `return 0` — všechny čtyři padly a každá jmenovala své místo.

**Zapsané mezery**: že se čekání doopravdy dočká *přechodné* vady, se v harnessu tvrdit nedá
(`FontMetric.shared` se nedá podstrčit a vadné písmo z matice je vadné natrvalo); `static let`
v `SelectableCodeView` a `DiffToolbar` může nulu pořád zapamatovat na celý proces (vlastnost z #407);
a **dvanáct dalších stráží porovnává surový text dál** — u nich to není přehození jedné vlastnosti,
protože hledané vzory samy obsahují mezery a zalomení, takže se musí přepsat literál po literálu
(nejbolavější je `SingleWayOutTests`, hlídá tvrdou podmínku č. 1).

## #517 — po pushi review jen přírůstku, se starými nálezy jako kontextem (M16)

První issue skupiny automatu (#517, #518, #519). Do #517 pouštěl automat po každém pushi **celé
review znovu**: reviewer prošel tentýž diff podruhé, staré nálezy nahlásil jako nové a odpověď na
„spravily to nové commity?“ se musela koupit zvlášť — vlastní session kontroly nálezů (#150).

**Po pushi teď reviewer dostane rozsah `<minulá hlava>…<hlava>` a k němu nálezy z minula jako
materiál v souboru** (cestou k souboru, precedens #120), takže z jednoho běhu vypadne obojí: nové
nálezy v přírůstku a verdikt o starých. Sada povolení se **nemění ani o položku** (tvrdá podmínka
č. 2) — je to rozsah v promptu a soubor, který si session přečte `Read`em.

**Rozhoduje se to na skill, ne na review** (`Policy.reviewScope`), a je to podmínka, ne
zjednodušení: dva reviewery nad jedním PR mohou být v jiném stavu a ten, který minule nedoběhl, kód
nad předchozí hlavou nepřečetl — přírůstek by ten zbytek přeskočil **potichu**. Na celý diff se
proto jde v šesti případech a každý je jiná věta v okně: vypnuté nastavení, první kolo, tatáž hlava,
reviewer bez doběhlého běhu, **přepsaná historie** a **nezjištěná** příbuznost.

**Společnou historii ověřuje `git`, ne časová osa PR.** `RepoCheckout.ancestry(of:in:)` je
`git merge-base --is-ancestor` v pracovní kopii a odpovídá **návratovým kódem** (0/1/jinak), takže
`rewritten` a `unknown` jsou dvě různé věty — tvrdit force push tam, kde `git` neodpověděl, by
tvrdilo víc, než data unesou. Cesta review konverzaci načtenou nemá, takže se `Policy.incrementalDiff`
z #284 použít nedá; je to **vědomě druhá cesta k téže otázce**, protože každá se ptá jiného zdroje.
Běží s `GIT_NO_LAZY_FETCH=1`, aby se odpověď nešla na partial klonu hledat po síti.

**Tvrdá podmínka č. 5 platí, jen se u přeneseného nálezu ptá dvou sha.** `Finding.headSha` se
přepíše na dnešní hlavu (běh nad dnešním kódem řekl, že nález trvá), `Finding.carriedFrom` nese,
odkud přišel — bez toho by nešlo poznat, že tu větu napsal reviewer o starším commitu a že číslo
řádku v ní může být z jiné verze souboru. Do **klíče** nálezu `carriedFrom` nepatří, jinak by
přenesení nález rozdvojilo a rozpáralo se s ním i odmítnutí (#113).

**Nic se neztrácí, a to je celý důvod, proč je nastavení výchozí zapnuté.** Přenášejí se **všechny**
staré nálezy — včetně vyřešených (`vyřešeno` je tvrzení modelu, ne fakt; sundat nález smí jedině
odmítnutí člověkem) i těch, ke kterým se běh nevyjádřil (v okně `bez odpovědi`). Odmítnutý se
neposílá ani nepřenáší: poslat ho zpátky do dalšího kola by ho vzkřísilo. **Rozbitá hodnota
v `config.json` se sráží na `false`**, tedy na celé review — na bezpečnou stranu, která je tady
opačná než default.

**Odznaky u nálezů skládá od #517 jedno místo** (`Policy.findingStatuses`): verdikt umí přinést
dvojí běh — kontrola (u nálezů starší hlavy) a přírůstek (u běhu na dnešní hlavě) —, a odznak
v okně je jeden. Dvě čtení by znamenala, že u nálezu stojí jeden a ve větě nad diffem druhý.

**V `Průběhu` k tomu přibyla kapsle `přírůstek` s rozsahem, souhrn pod dráhou** (`1 nový nález
v přírůstku · 2 starých trvá · 1 vyřešených pushem · 1 bez odpovědi`) **a cena přírůstku vedle ceny
celého běhu z prvního kola**. Ta cena se **nese s přírůstkem** a přes kola se řetězí: dohledávat ji
ze staršího záznamu by znamenalo, že po eviction věta tiše ztratí druhou polovinu. Rozsah jde do osy
jako událost, takže kapsle přežije restart; souhrn se bere z uloženého běhu, a jen když se
**na rozsahu shodnou** (uložený běh může být z minulého kola nad touž hlavou).

**Copilot našel jednu reálnou věc, a byla to zrovna ta, kterou tohle issue mělo zavřít**: rozhodnutí
o rozsahu se zahazovala vždycky, když nad přírůstkem neběžel nikdo — tedy u force pushe s jediným
reviewerem —, takže se věta `celý diff — historie se přepsala` nikdy nenakreslila a `Policy` by
rozhodovala do prázdna. Opraveno tím, že se zahazuje **materiál**, ne mapa rozhodnutí; ověřeno
vložením regrese. Cestou se opravila i věta u `noFinishedRun`: „minule nedoběhlo“ by u reviewera,
který nad předchozí hlavou vůbec nebyl, tvrdilo, že běžel.

Testů **5184** v 508 suitách, plný běh zelený (105,0 s, jedno známé `theWaitGivesUpLoudly`). Nové
sady jsou čtyři: `IncrementalReviewScopeTests` (výčet rozhodnutí, párování, přenášení),
`IncrementalReportTests` (souhrn a platnost odznaků), `IncrementalCommandTests` (prompt, soubor,
jedna konstanta tvaru verdiktů) a `AppStoreIncrementalTests` (celá cesta, včetně toho, že se
`git` v prvním kole vůbec neptá); k tomu ruční sonda `IncrementalLaneRenderProbe` — dráha v sedmi
stavech, dvě šířky, obě témata. `SessionToolSetsTests` prošly **beze změny**.

**Zapsané mezery**: nálezy revieweera, který v tomhle kole **neběžel** (odebral se ze sady, nebo se
opakuje jen podmnožina, #149), se nepřenesou — nemá je kdo odnést; je to totéž, co se dnes děje po
pushi u celého review. A **kvalita odpovědi na verdikty se v harnessu neměří**: že model v jednom
běhu doopravdy zavolá `ReportFindings` **a** ke všem starým nálezům se vyjádří, se pozná jedině na
skutečných bězích — dokud se to nepotvrdí, je vidět `N bez odpovědi`, což je záměrně to, co se
nedá přečíst jako „čisto“.

## #518 — routing reviewerů podle změněných cest (M16)

Druhé issue skupiny automatu (#517, #518, #519). Do #518 dostal každý reviewer ze sady každý PR:
`security-review` čítal i PR, který mění jen README, takže se za něj platila session a v okně z něj
vyšlo `čisté` — tedy tvrzení o kódu, na který se nikdo nedíval z důvodu, kvůli kterému ten reviewer
existuje.

**Reviewer teď může mít v nastavení repa vzory cest** (tabulka `Routing reviewerů`, řádek
reviewer → vzory) **a pustí se jen tehdy, když aspoň jeden změněný soubor sedí na aspoň jeden z
nich**. Rozhoduje o tom `Policy.reviewersToRun(files:rules:)`, tedy čistá funkce nad seznamem
souborů diffu — ne runner a ne store.

**Reviewer bez pravidla se pouští vždycky**, a je to ta podmínka, na které stojí, že tohle issue
nemění chování repa, které si routing nenastavilo: bez pravidel se na změněné cesty **ani
neptáme**, takže se nespustí ani podproces navíc (tvrdí to test). Prázdné pravidlo je totéž jako
žádné — řádek v tabulce vzniká prázdný, takže by jedno kliknutí revieweera tiše vypnulo; odpovědí
na „tady tenhle reviewer běžet nemá“ zůstává odebrání ze sady skillů.

**Cesty se berou z pracovní kopie, ne z GitHubu, a rozhodlo o tom měření**: `gh pr view --json
files` vydá **prvních sto** souborů a o zkrácení nic neřekne (změřeno na `kubernetes/kubernetes`
#141772 — 591 změněných souborů, v odpovědi 100). Routing nad zkráceným seznamem by přeskočil
revieweera, jehož soubor stojí na sto prvním místě, takže odpovídá nový lokální dotaz
`RepoCheckout.changedFiles(in:since:)` — úplně, a v cestě review zdarma. `--no-renames` je tam
schválně: soubor přesunutý **z** hlídané složky se pak v seznamu objeví i pod původní cestou.

**Přeskočený běh je vidět a není čisto.** V tabu `Průběh` má dráhu s kapslí `přeskočeno`, s důvodem
(`routing: žádný soubor z src/Auth/**, *.env*`), s cenou `0,00 $` (nula je tady fakt, ne odhad —
session se nespustila) a s tlačítkem `Pustit přesto`. Je to **čtvrtý stav dráhy**, ne varianta
`nespuštěno`: to mluví o revieweerovi, na kterého ještě nedošlo, kdežto tohle o tom, na kterého se
nedošlo schválně — tatáž hranice, jakou #383 zavedlo u `inconclusive`. **Ruční spuštění routing
nefiltruje**, takže `Pustit přesto` je tatáž cesta jako `Pustit znovu` u spadlé session; pravidlo
v nastavení se tím neruší.

**Rozhoduje se před rozpočtem, zadáním i session.** Routing stojí hned za odhadem jazyka repa (tedy
tam, kde je sada hotová) a před `canSpendSession` i `prepareIntent` — kdyby stál až v `runSkills`,
zaplatilo by se u přeskočeného PR zadání (#345, jedna `claude -p` session) a strhl denní rozpočet
za běh, který se nikdy nerozjel.

**Dvě rozhodnutí, která z zadání neplynula.** Přeskočení se pamatuje **jen v paměti**
(`AppStore.routingSkips`): je to odpověď na dnešní pravidlo nad dnešním diffem, takže na disku by
tichounce zestárla, a odvodit ji znovu nic nestojí — cena je restart, po kterém z dráhy zbude
`nespuštěno`. A **když se nepustí nikdo, nevznikne záznam**: prázdný záznam pro dnešní hlavu
vyhrává v `Policy.currentRecords` nad tím zastaralým, takže by nálezy z předchozí hlavy z okna
zmizely právě ve chvíli, kdy se na ně ptám. Řádek zůstane `neběželo` — nic neběželo, takže se nemá
co tvrdit.

**A jedna brána se kvůli tomu musela rozšířit**, jinak by routing zdražil místo zlevnil:
`hasCurrentReview` počítá za hotové i to, co routing přeskočil (`Policy.standingSkips`, jedině
týmiž vzory a nad touž hlavou). Bez toho by přeskočený reviewer neměl nikdy doběhlý běh, hotové
review by vypadalo jako nedokončené a stačil by komentář pod PR (mění `updatedAt`), aby si automat
zaplatil celé review znovu.

Testů **5214** v 510 suitách, plný běh zelený (110,4 s, jedno známé `FontMetric`). Nové sady jsou
dvě: `ReviewerRoutingTests` (výčet rozhodnutí, vzory obojí stranou, platnost přeskočení)
a `AppStoreRoutingTests` (celá cesta, včetně toho, že se bez pravidel na cesty vůbec neptá);
k tomu ruční sonda `RoutingRenderProbe` — přeskočená dráha ve čtyřech stavech a tabulka routingu
v nastavení, obojí ve dvou šířkách a v obou tématech. `SessionToolSetsTests` i `SingleWayOutTests`
prošly **beze změny** — routing nesahá na povolení ani na cesty ven.

**Z renderu vyšla jedna oprava**: bez tlačítka (běží jiné review) zůstávala pod dráhou věta
`Pustit ručně jde vždycky:` s dvojtečkou, za kterou nic nestálo. Věta má proto dvě podoby a
rozhoduje o tom, jestli je vedle ní tlačítko — netvrdí přitom **proč** tam není, to view neví.

**Copilot našel jednu věc a byla reálná**: do stavového řádku šel `error.localizedDescription`,
jenže `CheckoutError` není `LocalizedError`, takže by tam stálo `The operation couldn't be
completed. (PRism.CheckoutError error 5.)` — anglická věta o interním čísle případu místo toho,
co řekl `git`. Hlásí se proto `userDescription` s fallbackem (tentýž vzor jako
`AppStore+Checks.reason`) a tvrdí to test **z obou stran**: že tam ta věta je a že tam ta
systémová **není**. Ověřeno vložením regrese.

**Zapsané mezery**: po restartu z přeskočené dráhy zbude `nespuštěno` (viz výš — je to pravda, ne
ztráta); PR, jehož se netýká nikdo, zůstává v seznamu „na čem ještě neběželo“, takže ho hromadná
akce nabídne znovu (nic to neutratí, jen připraví pracovní kopii); a **jak dráha vypadá v úzkém
panelu, se tvrdit nedá** — kapsle, důvod a cena mají jeden řádek, takže se to zkouší kresbou.

## #515 — deska podle mého tahu (M16)

**Domov se přeskládal podle tahu, ne podle autora.** Karty (#181, #371) a dvě fronty podle autora
(#331) vystřídalo **šest pruhů**: `K merge`, `Dopsat a odeslat`, `Rozhodnout`, `Přečíst`,
`Předat agentovi`, `Čeká na ostatní` (návrh, sekce 45). Rozhoduje `Policy.lane` a testuje se to
**vyčerpávajícím výčtem** — 1 040 kombinací a tvrzení, že každý PR skončí v **právě jednom** pruhu.

**Z proklikání se změnily tři věci, tedy proti odsouhlasené kresbě.** Nejsilnější je
**rozřazení**: mergnutelný vlastní PR je `K merge`, i když na něm něco zbývá předat — projevilo se
to na schváleném PR se všemi osmi checky zelenými (`keboola/job-queue-daemon#934`), který ležel
v `Předat agentovi`, protože `pending > 0` rozhodovalo dřív než merge. **Výjimka z toho žádná
není**: první oprava nechala merge přebíjet stav `changed` (nevyřízená položka, typicky cizí
odpověď v předaném vlákně), druhé proklikání to zrušilo celé — **když je PR mergnutelný, patří do
`K merge`, tečka** —, a s tou výjimkou zanikl i `HandoffReport.outranksMerge`. **Informace se tím
neztrácí a nebylo pro to potřeba nic přidávat** — pilulka `N k předání` i `Prompt →` visí na řádku,
ne na pruhu, a na stavu předání nezávisí. **Blokující nález zůstává skutečnou překážkou**
(rozhoduje `mergeOffer`), takže s ním PR mergnutelný není.

**Zbylé věci z proklikání:** `K merge` šlo z čtvrtého
místa **na první** (a s ním `Dopsat a odeslat` z konce na druhé): osa pořadí přestala být „od cizí
práce k vlastní“ a je „jak blízko je řádek k tomu, aby míč nebyl u mě“ — mergnout je nejlevnější tah
a jediný, po kterém řádek z desky rovnou zmizí. A **prázdný pruh se nekreslí vůbec**, kdežto kresba
i první verze měly všech šest, i s nulou. Zbylé čtyři pruhy si relativní pořadí drží beze změny,
takže se proti kresbě přesunuly **jen dvě** položky.

**A jedna oprava, která nebyla připomínka, ale špatný překlad pokynu.** Pokyn *„návrhy z průběhu od
agenta dej jako poslední“* se do zadání dostal jako „poslední pruh na obrazovce“, takže `Předat
agentovi` jedno kolo stálo na konci desky. Myšlené to bylo jako **poslední pravidlo v rozřazování** —
tedy to, co už hotové bylo: `Policy.lane` se ptá v pořadí *draft · běžící review · cizí PR ·
slévatelnost · předání*, a tichý pruh je za tím **fallback**, ne pravidlo. Pruh je proto zpátky na
pátém místě a pořadí kresby už výjimku nemá. Že „poslední pravidlo“ **není** poslední řádek
`switch`e, hlídá nové tvrzení: kdyby se předání posunulo za `Čeká na ostatní`, nespadlo by do něj
nikdy nic.

**Skrývání zaplatilo tři věci a každá má stráž.** Deska přestala být stabilní, takže „první pruh“
je pokaždé jiný — proto **zkratka visí na pruhu, ne na pozici** (`⏎` u skrytého `Rozhodnout`
nepřevezme soused; hlídá to výčet přes všech 64 podmnožin pruhů). Vznikl stav, na kterém není ani
jeden pruh, a ten by jako prázdná plocha vypadal jako porucha — stojí v něm blok `Všechno vyřízené`,
a **nenačtená fronta se od vyřízené pozná** (`Načítám frontu`). A věta pod pozdravem se s deskou
nemá čím rozejít, protože skrytí pruhu i vypuštění části věty mají **tutéž podmínku**: nulu.

**Deska je pohled, ne množina.** Rail dál nabízí `Frontu` a `Moje PR` jako seznamy podle autora
a #332 platí beze změny: hromadné spuštění review, notifikace i automat čtou dál jen cizí PR. Akce
nad pruhem `Přečíst` je `startReviewsForNotReviewed()`, tedy tatáž množina, jakou store spouštěl
odjakživa — a je na to tvrzení z obou stran (co pruh ukazuje i co akce pustí).

**Co se rozhodlo jinak než v kresbě** (podrobně v záznamu rozhodnutí): `Sestavit N zadání` otevře
N záložek s rozloženým panelem `Zadání`, ne N sheetů za sebou (sheet, ve kterém se prompt skládá,
aplikace nemá); kapsle jako `Copilot · za mainem o 3` v tichém pruhu se nekreslí, protože se
z nenačteného PR nemají kde vzít; a `⏎` má jedině pruh `Rozhodnout` — `K merge` má tutéž akci bez
klávesy, aby na jedné kombinaci nebyly dvě; a patka pruhu má stříšku, ne šipku, protože rozbaluje
na místě.

**Co odešlo**: `Dashboard` a všechny čtyři karty, `DashboardCard`, `DashboardDestination`
(a s ním osa filtru zapínaná kartou `Blokuje` — odškrtává se v nabídce filtru dál),
`ReviewerShareOfFindings` s legendou reviewerů (blok `Reviewery` postaví #514), `DashboardBlock`
(z něj zbyla patka jako `BlockFooter`) a dva gettery podle autora. Blok `Dění` zůstal a strop se mu
zvedl z pěti na **osm** řádků, protože pravý sloupec drží dva bloky místo tří.

**Brief nahoře dodá #516** — do té doby je nad deskou dnešní pozdrav a věta o pruzích
(`8 věcí na tahu · 4 čekají na ostatní · 1 se dá mergnout`).

**Otevírá** #181 (karty), #331 (dvě fronty na domově — v railu platí dál) a #443 (bloky).

## #545 — do rozdělaného stromu se vstupuje `git -C`, ne `EnterWorktree`

Pravidlo z opakované srážky, v aplikaci nic. `docs/paralelni-vyvoj.md` v sekci *Strom po skončené
session* předepisovala agentovi, který jde do existujícího stromu, `EnterWorktree` s `path`. Ten
nástroj to **odmítne**: pustí cestu jedině ze session, která **už v nějakém worktree stojí**, kdežto
takový agent se pouští schválně **bez** `isolation: "worktree"`, tedy stojí v kořeni repa. Doslovná
odpověď je *„Cannot enter worktree: the current working directory … is the repository root, not an
isolated worktree“*. Ty dvě věty postupu si tedy odporovaly — první říkala „bez izolace“, druhá
předepisovala nástroj, který bez izolace použít nejde.

**Šest agentů, ne dva.** Issue popisovalo #501 a #503; do dne, kdy se vyřizovalo, k tomu přibyly
**#482, #152, #421 a #515**. Každý z nich dostal odmítnutí jako **první krok** a každý improvizoval
— a všech šest doplulo k témuž: **`git -C <absolutní cesta>`** v `Bash`i, což je i to, čím do stromu
sahá orchestrátor sám. Tak je to teď v postupu napsané, i s tím, **proč** `EnterWorktree` neprojde:
pravidlo bez důvodu příští session obejde, a tady ho šestkrát obešla. **Izolace se nevrací** —
založila by nový strom, tedy vzala větev, rozdělanou práci i otevřený PR.

**Chybějící polovina byl kontext předchůdce.** Cesta ke stromu v zadání stačí na to, aby se agent
dostal dovnitř, ne na to, aby věděl, co v něm leží. Do zadání proto patří **jméno větve, HEAD, počet
necommitnutých souborů, číslo existujícího PR a stav Copilota na něm**, a k tomu **pokyn přečíst si
`git log`, `git diff` a popis PR celé**, než na cokoli sáhne — jinak si to doplní domněnkou.
Slot se dál **nepřepisuje**: strom ho má v `.prism-slot` z minula a je gitignorovaný, takže
`git status --porcelain` ten počet nezkreslí. **Zákaz zakládat novou větev a nový PR** platí beze
změny a je u něj doplněné, že platí i tehdy, když by se z čisté větve psalo pohodlněji — nová větev
znamená nový PR a s ním zahozené kolo Copilota.

**A u toho se našla dvě další místa, kde postup předepisoval něco nefunkčního.**

1. **`SendMessage` subagent mít nemusí.** §4 tvrdila, že pauzu ohlásí `SendMessage`m na `main`;
   agent na tomhle issue ho neměl ani načtený, ani mezi odloženými (`ToolSearch select:SendMessage`
   nevydal nic). Premisa #256 platí dál — cesta k člověku vede přes orchestrátora a čeká se u ní
   pasivně —, mění se jen **kdo tu zprávu posílá**: subagent skončí turn s pauzou **ve svém
   hlášení**, orchestrátor ho dostane jako výsledek běhu, zeptá se a odpověď pošle zpátky.
   `SendMessage` je nástroj **orchestrátora**. Je to tatáž třída jako `EnterWorktree`: pokyn, který
   se dá vyplnit jedině nedostupným nástrojem, je pokyn k improvizaci.
2. **`gh pr merge` z pracovního stromu skončí nenulově a přesto mergne.** Padá na tom lokální krok
   za mergem (typicky `--delete-branch`), který si chce přepnout na základní větev — a tu drží
   hlavní strom. V [`github-cli.md`](github-cli.md#merge-z-worktree) to popsané bylo, jenže postup
   pro dávku na to neodkazoval, takže to agenti zjišťovali znovu; nejhorší, co si z toho můžou
   odnést, je „merge selhal“ a druhý pokus nad už mergnutým PR. §5 na to teď odkazuje a
   `github-cli.md` k tomu má větu o tom, **která** část příkazu padá.

Zapsané je to do [`docs/paralelni-vyvoj.md`](paralelni-vyvoj.md#strom-po-skončené-session) (§*Strom
po skončené session*, §4 a §5), do [`docs/github-cli.md`](github-cli.md#merge-z-worktree), dvěma
řádky do záznamu rozhodnutí ve specifikaci a **jednou půlvětou** do `CLAUDE.md` u pauzy v dávce;
velikost `CLAUDE.md` po tom je **93,2 kB** proti stropu ~100 kB (+58 B).

Na obrazovce se nemění nic a kód se nedotkl — sekce o slotech, o rozvrhu a o úklidu zůstaly, jak
byly, protože jsou proměřené provozem. Měnilo se jedině to, co bylo nepravdivé. Testů dál **5228**
v 511 suitách, beze změny.

## #502 — mapa PR v řádku fronty místo spektra reviewerů

Druhé issue směru E z milníku **M14**. V řádku fronty stál od #172 **proužek s podílem reviewerů**
na výsledku — odpovídal na „odkud ty nálezy jsou“. Od #502 je na jeho místě **mini pás mapy PR**
(110 × 6 bodů, `QueueMapStrip`): tentýž pás, jaký #501 postavilo pod hlavičku, jen v jiném měřítku.
Odpovídá na jinou a užitečnější otázku — **kde v PR to je a jak zle** —, a hlavně tím v okně zůstává
**jedno kódování: barva je závažnost**, ať se kreslí v řádku, pod hlavičkou nebo v okraji diffu.
**Nekreslilo se nic**: zákres té skupiny přenesl #501 jako sekci 42 a tohle issue se na ni odkazuje.

**Mini pás je velký pás v jiném měřítku, ne druhá mapa.** Data skládá `Policy.pullRequestMap`
a plochy kreslí `PullRequestMapView.drawSegments` — obojí **tatáž funkce**; odsud je jen geometrie.
Nad referenčním rozložením ze sekce 42 (sedm souborů, `composer.lock` 2 790 řádků z 2 952) vyjdou
**podíly na milióntinu stejné** ve 110 i v 800 bodech: lock 30,8 %, `composer.json` 6,2 %, tedy
**6,1 bodu** — nad minimem tří. Mezery ustupují tou samou nerovností (`Policy.mapSpacing`): ve 110
bodech od dvaceti tří souborů, a nad šestatřiceti nestačí ani minima, takže se dělí rovným dílem
(u 158 souborů po 0,7 bodu). To je zapsaná spodní hranice, ne vada: pás pak přestává mluvit
o velikosti, ale pořád říká, kolik červené v tom PR je.

**Co se o PR ve frontě doopravdy ví — a proto se pás u části řádků nekreslí.** Pás stojí na
seznamu souborů a jejich objemu, a to je jediný vstup, který ve frontě **není**: diff se dotahuje
až při otevření PR (#306), polling přinese jen shrnutí (`PullRequestSummary` nemá ani `headSha`,
natož soubory) a záznam review si seznam souborů neukládá. Dotáhnout ho pro každý řádek by bylo
N volání `gh` na tik — zamítnutá cesta, naposledy u #515. `AppStore.queueMap(for:)` proto vrací
`nil` ze **dvou** důvodů: (1) **na PR nic neběželo** — barva je závažnost, takže neutrální pás by
byl k nerozeznání od čistého review, což je tatáž úvaha, kvůli které se do #502 nekreslilo
spektrum u řádku bez běhu; (2) **diff se ještě nenačetl**. Druhá podmínka v zadání není, protože
předpokládalo, že soubory k dispozici jsou; **nejsou**, a je to zapsané rozhodnutí. Prakticky
tedy pás mají řádky PR, které už byly v tomhle spuštění otevřené, a ostatní vypadají jako řádek
do #502 bez spektra: odznak stavu, nic víc. **Prázdný obdélník se nekreslí nikdy** — tvářil by se
jako údaj. Posunout se to dá jedině tím, že by si aplikace seznam souborů **ukládala** (kandidát je
záznam review, který diff v ruce má); zapsáno jako mez, ne jako plán.

**Čárka vlákna ani jezdec v řádku nejsou, a je to důsledek téhož.** Konverzace se stejně jako diff
tahá až v detailu, takže by chybějící čárka u zavřeného PR neznamenala „žádná diskuze“, ale
„nevíme“; jezdec navíc ukazuje soubor pod výřezem, který u zavřeného PR neexistuje. Popisek mapy
proto v řádku o vláknech **mlčí** (`Policy.mapSummary` části bez obsahu vynechává) a nese ho
nápověda a `accessibilityValue`, ne řádka — v ní na něj místo není.

**Cache s otiskem vstupů, ne s ručním zneplatňováním** (#224). Pás by se jinak skládal při každém
průchodu tělem seznamu **u každého řádku**, tedy prací lineární v počtu souborů. Ruční
zneplatňování by znamenalo pět volajících (načtení diffu, doběhlé review, odmítnutí, značka,
změna konfigurace) a stačilo by zapomenout jedno, aby řádek kreslil pás z minula — **potichu**,
protože pás z minula vypadá jako pás. `QueueMapStamp` se proto skládá při každém dotazu a je v něm
všechno, co ta funkce čte (#153), a nic, co roste s počtem souborů: razítko diffu s počtem souborů,
z každého platného nálezu čtveřice *(soubor, řádek, kategorie, verdikt)*, značky `Prošlo`
a **blokující kategorie z konfigurace**. `@ObservationIgnored` je u té mapy podmínka, ne úspora —
zapisuje se do ní z průchodu tělem, takže sledovaná vlastnost by ten průchod zneplatnila sama
sebou; uklízí se v `forget(whatIsNotIn:)` spolu s diffem.

**`SpectrumBar` odešel celý**, a s ním `QueueRow.spectrum`, typ `ReviewerShare`
a `ReviewStateAppearance.color(of: ReviewerShare.Outcome)` — pole bez čtenáře je mrtvá váha, která
svádí spolehnout se na ni. `QueueRow` **zůstává** s jedním polem (`blocking`): je to pořád údaj
o výsledku a čte ho hrana řádku i odznak, kdežto holé `Int` by z `PullRequestRow(row:)` udělalo
nepojmenované číslo na čtyřech místech. Rozhodnutí *čisto versus nemám co říct*, které si proužek
počítal **znovu** (a #383 proto tutéž vadu opravovalo na dvou místech), zůstalo v `Policy.chips`,
kde se v okně doopravdy čte.

**Výška řádku se nemění** — měřeno `fittingSize` mimo obrazovku: 41 bodů s pásem i bez něj, a to
i v 636 bodech, tedy v obsahu nejužšího povoleného okna. **Tři inserted regrese** to potvrdily:
bez podmínky na běh spadne test „PR, na kterém nic neběželo, pás nedostane“; bez kategorií v otisku
spadne „blokující sada pás přebarví, i když už je v cache“; a pás vysoký 40 bodů shodí obě měření
výšky (41 proti 64). Čtvrtá ověřila stráž nad zdrojáky: `Policy.mapFill(` dosazený do
`QueueMapStrip` shodí tvrzení „barvu segmentu rozhoduje jediné místo“.

Testů **5239** v 514 suitách (proti 5228 v 511 na `main`u před tímhle PR); nové jsou dvě sady
(`AppStoreQueueMapTests`, `QueueMapStripTests`) a jedna sonda (`QueueRowRenderProbe` — řádek fronty
ve dvou šířkách a v obou režimech, pouští se ručně jako ostatní sondy). Naopak **ubylo** devět
tvrzení o proužku reviewerů; co z nich zůstalo a kde, je
v [`docs/testovani.md`](testovani.md).

**Mockup na to čeká.** `docs/navrh.html` kreslí v řádcích fronty pořád `.spectrum` (tři místa) —
tohle issue se do něj **nekreslilo schválně**: souběžně s ním běžela dvě jiná, která do téhož HTML
sahají, a třetí konflikt v jednom souboru je horší než den nesouladu. Je to **zapsaná mezera**:
`.spectrum` v sekcích s frontou má vystřídat mini pás.

## #556 — metoda merge je volba, ne konstanta

Merge vlastního PR posílal `merge_method: "squash"` z **konstanty** `MergeRequest.method`, a u té
konstanty stálo zdůvodnění, že volba mezi metodami by byla „třetí věc na potvrzení, kterou člověk
projde jednou za rok, a přepnout ji jde na GitHubu“. **Praxe to vyvrátila ze dvou stran**: odejít
z okna kvůli jedné hodnotě je dražší než ta hodnota, a squash není to, co se hodí ve všech repech.
Zdůvodnění se proto **přepsalo, ne smazalo** — a ten argument padl i sám o sobě: mluvil o světě,
ve kterém **žádná výchozí hodnota nebyla**, takže se rozhodoval každý merge.

**Výchozí hodnota je v nastavení, globálně i per repo.** Globální default (`squash`, tedy chování
do #556) leží na stránce `Odesílání` **pod** bránou — brána rozhoduje, jestli se dá mergnout vůbec,
tahle sekce jenom čím. Per repo to je čtyřhodnotový picker na `Repozitáře`, vedle ostatních
override: metoda merge je **zvyk repozitáře**, ne člověka, takže je to tatáž třída jako `mode`
nebo `incrementalAfterPush`, a ne jako `diffLayout` a vzhled okna, které override schválně nemají.

**Potvrzení metodu vypisuje a dovolí ji přebít pro jeden merge.** Picker leží **uvnitř výpisu
payloadu** — je to řádek payloadu, ve kterém se dá kliknout, ne krok před potvrzením —, takže
zamítnutí z #465 („druhá věc na potvrzení“) neplatí: mergne se pořád jedním kliknutím na
pojmenované tlačítko. **S metodou se přepíše celý výpis**: `commitů 3 → 1` je věta o squashi, u
merge commitu je to `3 + merge commit` a u rebase `3 přehrané`; titulek je u squashe `titulek PR
(#číslo)`, u merge commitu `Merge pull request #N from <větev>` a **u rebase žádný** (nevzniká tam
commit, takže by GitHub pole zahodil). Že přepnutí platí **jen pro tenhle merge**, stojí pod
výpisem — bez té věty by picker vypadal jako zkratka do nastavení.

**Věta o těle se přestala hádat.** Do #556 stálo v potvrzení „Tělo squash commitu složí GitHub ze
zpráv N commitů“, což je pravda jedině v repu se `squash_merge_commit_message = COMMIT_MESSAGES` —
tenhle repo ho má (změřeno), ale záruka to není. Zdroje těla přijdou **týmž voláním** jako povolené
metody, takže věta řekne, co v tom těle bude; kde se to zjistit nepodařilo, zůstává přiznání
„složí GitHub podle nastavení repozitáře“, a u rebase se o těle nemluví vůbec.

**Nové čtení je jedno volání za repo, a „nevím“ je třetí odpověď.**
`GitHubGateway.mergeSettings(repo:)` (šestadvacátá čtecí metoda; gateway zůstává bez zápisu) čte
`GET /repos/{o}/{r}` a drží se v cache klíčované **repem**; ptá se při otevření vlastního PR a při
výběru repa v nastavení, **ne na tik pollingu**. Změřeno: `ondrajodas/PRism` 0,62 s a všechny tři
`true`, `keboola/job-queue-daemon` `allow_rebase_merge: false`, a `cli/cli` — repo **bez práva
zápisu** — **všech pět polí GitHub vůbec nepošle**. To poslední je „nevím“, ne „nepovoluje“: nabídnou se všechny
tři metody a nic se netvrdí. Nepovolená metoda se z nabídky **neztratí**, jen se nedá vybrat
(zašedlá, přeškrtnutá, `nejde`) — zmizet nesmí, jinak se nedá poznat „repo to nepustí“ od „tuhle
metodu GitHub nemá“.

**A nepovolená výchozí metoda se nepodstrčí jinou.** Sheet se v tom stavu otevře **bez vybrané
metody**, `Mergnout` je zakázané, řádky `commitů` a `titulek` píšou ztlumeně `podle metody` a pod
výpisem stojí výstraha s tím, co repo povoluje. **Panel o tom mlčí** a `Mergnout…` v něm zůstává
povolené: mergnout jde, jen zbývá vybrat čím — a to je otázka payloadu, ne stavu větve.

**Tvrdá podmínka č. 1 se nezměnila ani o položku.** `ReviewPublishing` má pořád **devět** metod,
merge je pořád osmá, brána, potvrzení i dvojí ověření hlavy platí — `SingleWayOutTests` prošly
**nedotčené** a grep vydává týchž **sedm** souborů (`BranchPushing` tři). Co se změnilo, je obsah
payloadu, ne cesta ven. Rozdělilo se u toho jedno místo na dvě: `MergeProposal` je to, s čím se
sheet otevřel, `MergePlan` je **payload** — a `plan == nil` je platný stav („nic není vybráno“),
ne nedodělek.

Testů **5266** v 513 suitách (+38), z toho nové `MergeMethodChoiceTests` a
`GhRepositoryMergeSettingsTests`; fixtures jsou skutečné odpovědi `gh api` (`ondrajodas/PRism` a veřejné `cli/cli`), **zkrácené
o pole, která se nedekódují** — plná odpověď nese `temp_clone_token`, tedy krátkodobý credential
(nález Copilota na PR #560). `allow_rebase_merge: false` je inline JSONem, protože změřené je na
firemním repu. **Naostro se nemergovalo** — merge je nevratný a brána je ve slotové konfiguraci
vypnutá; ověřené je to, co odejde v payloadu (na hotových bajtech) a co repozitáře doopravdy
vracejí.

## #529 — Odznak v Docku a spuštění po přihlášení (zákres 49)

O frontě se dřív dalo dozvědět jen z otevřeného okna nebo z notifikace, která přijde jednou
a zmizí. **Dlaždice v Docku je proti tomu stav, který zůstane**, a **spuštění po přihlášení** je
jeden přepínač, ne launch agent v `~/Library`. Obojí sahá mimo okno, takže obojí dostalo novou
stránku `Systém` ve skupině `Prostředí` — osmou v okně nastavení.

**Odznak je rail v Docku, ne druhý výpočet.** `Policy.dockBadge` bere tutéž množinu jako odznak
fronty v railu (cizí PR **po filtru**) a totéž pravidlo o nule i o nenačteném seznamu. Volba je
`čekající / blokující / nic`, výchozí `čekající` — a **`blokující` je ta množina jen zúžená**, ne
`queueSummary.blocking`. Souhrn fronty totiž filtr ignoruje, takže by přepnutí volby umělo nad
zapnutým filtrem ukázat **větší** číslo; invariant `blokující ≤ čekající` drží jedině nad jedním
polem, a proto ho drží tvar té funkce.

**Prázdno, nula a „nevím“ kreslí totéž (nic), a je to rozhodnutí.** Dlaždice má jeden kanál, takže
se do ní věta o nenačtené frontě nedá napsat a `0` by v systémové červené hlásila poplach nad
ničím. Rozlišuje se to v okně: rail má nulu bez odznaku, nenačtený seznam pozná stavový řádek.

**Nasazuje se sledováním, ne rozesetým `refresh()`.** Rozeseté volání by bylo jedenáct míst (sedm
přiřazení `reviewRecords`, tik, filtr, konfigurace, obnova po startu) a dvanácté by chybělo;
`withObservationTracking`, které se z `onChange` přihlásí znovu, zapomenout nejde. Je to **první
výskyt toho vzoru v `App/`**, takže je u něj zapsané, proč nevyrábí smyčku, proč v něm není mezera
na ztracenou změnu a proč se ve výchozí volbě nesleduje ani mapa nálezů.

**Přihlašovací položka se nepíše do `config.json`** — je to stav systému, takže se **čte zpátky** ze
`SMAppService`, a to při každém zobrazení stránky. Přepínač se po nepovedeném zápisu **tiše
nevrátí** do vypnuté polohy (drží se i poloha, o kterou si člověk řekl), věta zmizí sama, jak jí
stav systému přestane odporovat, a u zákazu v Nastavení systému je pod přepínačem **odskok**
(vzor z #414). **Slotová instance položku nenabízí** — zašedlá s důvodem, protože
`bin/slot-cleanup.sh` ji sundat neumí; brána je v `AppStore.setLoginItem`, ne v zašedlém přepínači,
a do `bin/slot-config.sh` se nesahalo.

**Zašednutí se kreslí opacitou (0,55 ze zákresu), a je to změřené**: samotné `.disabled(_:)` se
v tomhle okně projeví jen odstínem přepínače a popiska zůstane plná — v key i nekey okně.

**Co se neověřilo a je to napsané**: do systému se **nezapsalo ani jednou** (ověřilo se jen čtení
`status`, které pro nebundlovaný proces vydá `notFound`), věta „mimo `/Applications` to nejde“
zůstává **cizím tvrzením z decku** (#88 měřilo tu mez u notifikací) a adresa panelu `Položky při
přihlášení` se neotevřela — tvrdí se jen tvar, jako u #414. K tomu **zapsaná mez**: s úplně
zavřeným oknem odznak zmrzne na poslední hodnotě, protože polling žije s hlavním oknem.

**Odznak si aplikace kreslí sama, a je to oprava po proklikání.** V prvním kole bylo všech šest
sad zelených, plná suita hlásila `TEST SUCCEEDED` — a v Docku nebylo číslo. `dockTile.badgeLabel`
je pod přepínačem `Odznaky` v Oznámeních a u aplikace, která si o `.badge` v `requestAuthorization`
neřekla (`PRism` žádá `[.alert, .sound]`, #88), ho Dock **potichu zahodí**: hodnota se nasadí,
přečte se zpátky, `display()` ani restart Docku nepomůže — a **týž kód v témže bundlu s jiným
`CFBundleIdentifier` odznak nakreslí**. Odznak proto kreslí `DockBadgeTileView` do
`dockTile.contentView`, což **nepotřebuje žádné povolení** a **přežije restart Docku**. Požádat
o `.badge` je **změřená a zamítnutá** varianta: u autorizované aplikace přeskočí `badgeSetting`
z `notSupported` na `disabled`, tedy přepínač v Nastavení systému **vznikne vypnutý**.

Zákres 49 se u toho **opravil**: `contentView` je plochou dlaždice ořezaný, takže odznak
dlaždici **nepřesahuje** a **nemá obtah**; velikost 0,38 krátké strany je **naměřená na
systémových odznacích v živém Docku** (17 px na dlaždici 45 px), ne 22/72 z CSS. Geometrii vydává
`Policy.dockBadgeLayout` a **strop na šířku pilulky našel test**, ne návrh — od pěti znaků odznak
jednou hranou vylézal.

Sedm sad testů, z většiny tvrzení o tom, co se **nestalo** — nula se nekreslí, nenačtená fronta se
nekreslí, ve výchozí volbě se na uložené nálezy vůbec nesáhne, slotová instance do systému
nezapíše. K tomu stráž nad zdrojáky (`DockBadgeWiringTests`, šestá podoba téhož kořene po #367,
#411, #421, #462 a #490), render stránky, ve kterém se zašedlý řádek porovnává **jen v pásu s tím
řádkem**, aby rozdíl nemohl přijít z věty pod ním, a **`DockBadgeTileRenderTests`** — sada, kterou
si vynutila právě ta vada z prvního kola: porovnává **bitmapu odznaku**, takže padne, když se
odznak nenakreslí. Celkem **5298 testů v 517 suitách** (proti 5228 v 511 před #529, tedy 70 nových
v šesti sadách), `TEST SUCCEEDED` za 113,3 s — měřeno se **souběžně běžícími sloty**, ne na volném
stroji; nad slitým `mainem` s #502 a #556 je to 5351 v 523 za 133,0 s. Regrese ověřená vložením regrese **šestkrát** (nefiltrovaná fronta, chybějící brána
u slotu, `SMAppService` ve storu, vynechaná kresba odznaku, návrat k `badgeLabel`).

## #506 — itinerář review místo stromu souborů (M14)

Levý sloupec záložky PR přestal být strom cest a stal se **dráhou se zastávkami**: *Od minule →
Popis a záměr → Soubory podle rizika → Kontroly → Verdikt*, u každé stav (✓ hotovo / ● aktuální /
○ zbývá) a údaj vpravo, v hlavičce `Itinerář · 4 z 11 · 10 min` a pod ní proužek podílu. Zákres
je v `docs/navrh.html` jako **sekce 47**. Důvod: okno mělo osm záložek a strom, ale **žádné
pořadí** — co číst první, kde jsem skončil a co zbývá, si člověk držel v hlavě. Reviewer má dráhu
s fázemi; člověk, který review dělá, neměl nic.

**Zastávky skládá `Policy` z dat, ne šablona**, a to je jádro toho issue: `Od minule` vznikne jen
se **záznamem předchozí návštěvy a commity** (#171), `Kontroly` jen s CI (#306), zbylé tři vždycky.
**Hotovo se pozná z dat** — soubor prošlý (#500), popis odscrollovaný na konec, spadlý check
rozbalený, verdikt odeslaný na GitHub. **Ručně se zaškrtne jedině soubor**: itinerář, který si
člověk odškrtává sám, je druhý seznam úkolů a přestane se udržovat po druhém PR.

Dvě odvození stála za novou stopu ve store, protože se nedala vyčíst z toho, co už bylo:
`overviewReadToEnd` (`OverviewView` hlásí `Policy.overviewAtEnd` přes `onScrollGeometryChange` —
akce jen při změně hodnoty, a jednosměrně: otázka je „přečetl jsem popis“, ne „kde je scroll teď“)
a `openedFailedChecks` (`expandedChecks` drží nejvýš **jeden** rozbalený check a sbalením se
vyprázdní, takže by zastávka po zavření logu zhasla zpátky na nehotovou). K tomu
`previouslyVisited`, a to z nutnosti: `noteVisit` zapíše dnešní návštěvu hned za
`seedVisitBaseline`, takže od té chvíle je `lastVisit` dnešní a „byl jsem tu už dřív“ se z ledgeru
poznat nedá. Všechny čtyři prořezává tik a všechny čtyři jsou ve výčtu
`PollObservationTests.quietTickWakesNoneOfTheMapsTheTickPrunes` — od #506 je jich **dvaačtyřicet**.

**Jednotkou počítadla je soubor, ne zastávka.** `4 z 11` má být počet věcí, které se doopravdy
čtou (sedm souborů plus čtyři zastávky); s jednotkou „zastávka“ by proužek u PR o padesáti
souborech skočil z pětiny na dvě pětiny jedním zaškrtnutím. **Odhad času** je z neprošlých řádků
(30 řádků za minutu) plus minuta za nehotovou zastávku, která soubory nečte; nad nenačteným diffem
i nad hotovým itinerářem se **nepíše nic** — `0 min` by nad nehotovou prací lhalo a nad hotovou
bylo šum.

**Strom podle cesty zanikl a otevírá se zpátky jako #197.** `FileTreeView` a `FileTree.swift`
odešly i s testy: cesta se od #219 píše v **hlavičce souboru** v diffu, takže ve sloupci nechybí, a
pořadí podle rizika odpovídá na otázku, na kterou hloubka složek odpovědět neumí — čím začít.
Držet mrtvý strom vedle itineráře by byl přesně ten vzor, na který Copilot v tomhle repu opakovaně
upozorňuje.

**Soubory podle rizika: klasifikace a kresba jsou dvě různá pořadí**, a je to vědomá odchylka od
zadání. Kreslí se blokující → nález → vlákno → nový → ostatní → konfigurace a locky (ty složené do
jedné položky), ale **rozhoduje** se konfigurací **dřív** než `nový`: nový `composer.lock` je pořád
tisíc řádků, které nikdo nepíše rukou. Nález a vlákno konfiguraci naopak **přebijí**, takže
`composer.json` s blokujícím nálezem je blokující soubor a neschová se. Konfigurace se pozná
z **výčtu jmen a přípon**, ne heuristikou — `.xml` v něm schválně není (Android layouty, XSLT).

**Šířka 260 místo 210 je změřená cena.** `ItineraryColumnRoomTests` na štěrbině 1 047 b a znaku
8,036 b: *Vedle sebe* **3 znaky na stranu** (41 → 38), *Pod sebou* **6 znaků** (86 → 80). Ve
`split`u se neplatí ani tou trojkou, protože se sloupec skládá (#188) — je to cena za to, když si
ho tam člověk otevře `⌘1`. Hranice, pod kterou se skládá, se posunula o týchž 50 bodů: 570 → 620
bez okraje karet a 870 → **920** s ním; ta druhá je nad podlahou `RootView`u (700), takže je to
jediná změna chování, kterou ta šířka na obrazovce udělala. První podoba toho testu měřila
o **šest bodů** vedle, protože do hranice přičítala mezeru před kolonou (#503) — `diffSideColumns`
ji neodečítá, odečítá ji až `diffCodeColumnWidth`.

**Zkratka `⌘1` se přejmenovala** ze `Strom souborů` na `Itinerář review` (i případ v katalogu:
`WindowShortcut.Action.itinerary`). Kombinace se nemění.

Nové sady jsou tři: `ReviewItineraryTests` (matice vstupů —
přítomnost zastávky odděleně od hotovosti), `FileRiskTests` (pořadí nad daty ze sekce 03 návrhu
a co je konfigurace) a `ItineraryColumnRoomTests` (to měření šířky); k tomu ruční sonda
`ReviewItineraryRenderProbe`.

**Zapsané mezery**: odhad času je **odhad**, ne měření — 30 řádků za minutu je odvozené z toho,
jak dlouho dvěstěřádkový soubor v tomhle okně doopravdy zabere, ne naměřené nad sezeními. A že
`⌘1` po přejmenování pořád zabere, se v harnessu ověřit nedá (testovací host nedostane aktivaci),
takže to zkouší člověk.

### Druhé kolo z proklikání: sloupec vedle všech tabů a klik na soubor

Z proklikání přišly **dvě připomínky** a obojí bylo věcně proti tomu, k čemu itinerář je.

**1. „Když se z něj překliknu na kontroly, tak to celý zmizí.“** Sloupec byl součástí obsahu tabu
`Změněné soubory`, takže mizel právě ve chvíli, kdy podle něj člověk někam odešel — a cesta zpátky
vedla přes pruh záložek. Sloupec je proto **o úroveň výš**: hostí ho `PullRequestDetailView`
(nový `ItineraryColumnView`) a stojí vlevo od obsahu záložky, tedy **vedle všech osmi tabů**.
`⌘1` ho skládá do proužku 34 bodů kdekoli.

Rozhodnutí, která u toho padla:

- **Plošné „ve všech tabech“, ne výběr.** Panel vpravo se ve třech tabech schovává (#294), protože
  je v nich vedle něj duplikát dat nebo obsah, který šířku potřebuje; u sloupce ani jedno neplatí —
  nic neduplikuje a v každém tabu vede **jinam**. Tab, ve kterém by zmizel, je tab, ze kterého se
  nedá vrátit.
- **Cena: 260 bodů rozložený, 34 složený**, tedy **787 b** místo 1 047 na výchozím okně. Jedna
  šířka pro všech osm je podmínka, ne zjednodušení: sloupec, který by se s tabem měnil, přeskládá
  okno při každém přepnutí. U diffu je ta cena změřená ve znacích (3 na stranu vedle sebe, 6 pod
  sebou — beze změny proti prvnímu kolu); u ostatních tabů se dál než k bodům měřit nedá, protože
  jsou to řádky a próza s pružnou sazbou, takže se zúžení projeví jinou pozicí zalomení.
- **Šířku obsahu měří rozvržení, společnou se předává.** Sloupec je sourozenec s pevným rámcem,
  takže `GeometryReader` obsahu tabu rovnou vidí, co po něm zbylo — žádné odečítání, které by se
  dalo splést (#546). Rozhodnutí o kolonách se ale ptá na tu **společnou** šířku, a tu počítá
  `Policy.widthWithItinerary` **tam, kde sloupec stojí**, a podává ji prostředím
  (`sideColumnsWidth`). Dopočítávat ji uvnitř `DiffView`u je **zamítnutá varianta**: v okně by
  seděla, ale v hostu bez sloupce vedle sebe by rozhodnutí měnilo svůj vlastní vstup a umělo by
  **kmitat**. `Policy.diffCodeColumnWidth` proto sloupec **neodečítá**.
- **O skládání rozhoduje dál `DiffView`, a je to zapsaná mezera.** Podlaha, kvůli které se sloupec
  skládá, je podlaha kolony kódu — v `Kontrolách` není co chránit. Mezera: v tabu bez diffu se
  nerozhoduje vůbec, takže zúžení okna nad `Kontrolami` sloupec nesloží; složí ho první průchod
  diffem.
- **Sloupec bez zastávek zanikl** a s ním `Policy.readFileShare` i `Policy.fileTreeSummary`
  (obojí #500): v prvním kole ho dostal diff commitu a rozsah od minule, protože byl součástí
  tabu; od druhého kola mluví vždycky o celém PR, takže nepovinné `itinerary` neměl kdo nastavit
  na `nil`.

**2. „Když kliknu na soubor tak se nic nestane.“** Sloupec měl vlastní skok
(`withAnimation { proxy.scrollTo(file.id, anchor: .top) }`) a ten byl vadný na dvou ze tří příčin
míjení, které vyjmenovalo #152: **animovaný** a **v jediném průchodu**. Od druhého kola jde klik
tou hotovou cestou, kterou skáče **mapa PR** (#501): `jump(toFile:)` → `anchor(inFile:line: nil)`
(rozbalí sbalený soubor, vrátí `file.id`) → `scroll(to:)`, tedy **přepnutí na `Změněné soubory`**
a `scrollTarget`; odtud dva průchody s přeměřenými rozměry a bez animace.

- **Kam soubor přistane**: hlavičkou **na hranu výřezu** (`DiffJumpTarget.fileHeader`, offset 0).
  Devadesát bodů jako u nálezu by ukazovalo konec předchozího souboru a ukotvená hlavička s týmž
  obsahem ji tam překryje. Nula je navíc **jediná hodnota nezávislá na výšce sekce**, a to je ta
  podstatná část: sekce souboru má tisíce bodů, takže by z podílu 0,12 byl skok o stovky bodů
  **do** souboru.
- **Druh cíle se pozná z identity cíle** (`Policy.jumpTarget(of:files:requested:)`), ne od
  volajícího — sloupec stojí mimo `DiffView`, takže by mu jeho `@State` nebyl k ničemu.
- **Opravilo to i mapu PR** (#501): mířila na `file.id` s druhem `.bubble`, takže u velkého souboru
  přeletěla stovky bodů do jeho vnitřku. Tatáž třída, jedna oprava v `Policy`.

Testů **5424** v 529 suitách (+88 proti `main`u), plný běh zelený nad stavem slitým s `main`em
(153,3 s, jedno známé `theWaitGivesUpLoudly`).
Nová sada je jedna — `ItineraryEveryTabTests` (cena, kruh společné šířky a stráže nad zdrojáky:
sloupec mimo `switch tab`, jedno místo, které ho kreslí, klik přes `jump(toFile:)`) — a k tomu tři
tvrzení o `.fileHeader` v `DiffJumpAnchorTests`. Přizpůsobené: `DiffColumnFitTests`
a `DiffCodeColumnWidthTests` (sloupec se od kolony neodečítá), `DiffColumnFitTests` u šířek kolon
(`ItineraryColumnView.width`), `ItineraryColumnRoomTests` a dvě sondy. **Zapsaná mezera**: že je sloupec vidět v každém tabu, se tvrdí
**strukturálně** — kolony jsou SwiftUI a v hostovaném okně se z accessibility tree přečíst nedají
(změřeno u #546), takže jak vypadá vedle `Kontrol` a `Konverzace`, ukazují rendery a posoudí to
člověk. Totéž u `⌘1`: testovací host nedostane aktivaci.

### Třetí kolo z proklikání: „někdy se ten levý panel zavře“

**Nález:** *„PRism-c — někdy se ten levý panel zavře když na něco kliknu…ale jen někdy.“*

**Příčina je následek druhého kola.** Sloupec se přestěhoval o úroveň výš, ale automatika #188
(*pohled vedle sebe složí postranní kolony*) zůstala v `DiffView`u — i se stráží proti druhému
uplatnění, kterou drží `@State appliedColumns`. Tím vznikl stav, který **přežívá**
(`diffTreeExpanded` v `UserDefaults`), hlídaný stráží, která **nepřežívá**: `switch tab` v detailu
diff při odchodu ze `Změněných souborů` zahodí, takže každý návrat byl nová instance s prázdnou
stráží, uplatnil rozhodnutí podruhé a **přepsal tím `⌘1`** — a protože se to ukládá, i pro příště.

**Změřeno, ne přečteno** (`ItineraryChoiceTests` nad hostovaným detailem, uložená hodnota klíče):

| Krok | *Vedle sebe*, `⌘1` otevřel | *Pod sebou*, `⌘1` složil |
|---|---|---|
| po prvním průchodu diffem | `false` (#188, záměr) | `true` |
| po `⌘1` | `true` | `false` |
| odchod do `Kontrol` / `Přehledu` | `true` | `false` |
| **návrat do `Změněných souborů`** | **`false`** | **`true`** |

**Odchod volbu nezmění, návrat ji přepíše** — to je celá vada. „Jen někdy“ znamená „jen když se
rozhodnutí od uložené hodnoty liší“: ve `Vedle sebe` se sloupec zavírá, v `Pod sebou` se naopak sám
otevírá (a to si člověk vysvětlí jako „nezabralo to“, takže se to v hlášení neobjevilo).

**Co je záměr a co vada.** Záměr je **první** uplatnění: ve `split`u se sloupec skládá od #188 a je
to změřené (34 bodů místo 260), takže PR otevřený *Vedle sebe* má sloupec složený a `⌘1` to přebije
„až do další změny pohledu“. Vada je, že „další změna pohledu“ nastala i tehdy, když se pohled
nezměnil a jen zanikl a znovu vznikl diff.

**Oprava: stav i stráž chodí do diffu parametrem** (`DiffColumnActions` — `expanded` a `applied`),
drží je `PullRequestDetailView`, jehož `@State` přepnutí tabu i složení panelu přežije. Rozhodnutí
zůstalo v `DiffView`u, protože podlaha, na kterou se ptá, je podlaha **kolony kódu**; přestěhovat ho
celé do detailu se **zamítlo** — `hasMargin` je funkce diff-interního stavu a diff commitu má
vlastní karty, takže by jedno rozhodnutí v detailu bylo pro dva různé diffy. `nil` znamená totéž
jako u `panelExpanded`: **kdo ho nedodá, tomu se nic nepřepíše**.

**Vedlejší nález, tatáž třída:** diff commitu měl vlastní `@AppStorage("diffTreeExpanded")`, takže
vybrání commitu v tabu `Commity` sloupec ve `Vedle sebe` taky zavřelo. Od třetího kola nemá
`DiffView` ten klíč vůbec.

**A nula z `GeometryReaderu` není nejužší okno**: `Policy.diffSideColumns` bere nekladné `available`
jako „nikdo to nezměřil“. `widthWithItinerary` to dělalo od druhého kola, ale fallback
`sharedWidth ?? slotWidth` nulu z prvního průchodu propustil — do #506 by to byl blik jednoho
snímku, od #506 zápis do volby člověka.

**Zobecnitelné pravidlo:** *stráž proti opakovanému uplatnění musí žít aspoň tak dlouho jako stav,
který mění.* `@State` uzlu, který se přestavuje častěji než ten stav, je stráž, která „jen někdy“
neplatí.

Nová sada je `ItineraryChoiceTests` (čtyři scény, obě strany vady, a k tomu druhá polovina: přepnutí
pohledu volbu přebít **smí**), k tomu dvě stráže nad zdrojáky v `ItineraryEveryTabTests` (klíč čte
jeden uzel; do stavu sloupce píšou vyjmenovaná místa a diff commitu mezi nimi není) a tvrzení
o nulové šířce. **Zapsaná mezera zůstává a je z ní tvrzení**: v tabu bez diffu se stavem sloupce
nehýbe nic — v aplikaci se do ní ani nedá dostat, protože pohled přepíná lišta nad diffem.

### Čtvrté kolo z proklikání: dvě cesty, kterými se volba přepisovala dál

Připomínka přišla **podruhé** (*„pořád se ten itinerář zavírá“*), takže třetí kolo opravilo jen
část. **První hypotéza byla správná, ale nebyla úplná** — zůstaly dvě nezávislé cesty a obě se
změřily v uživatelově okně (1 512 × 882 → 1 460 b na detail, tedy tam, kde se **nepřekračuje žádná
šířková mez**).

**První: stráž nepřežila ani `@State` detailu.** `ContentView` vybírá obsah okna
`switch store.activeTab`, a to je `@ViewBuilder` — jiná větev je jiná identita, takže kliknutí na
`Přehled` zahodí celý `PullRequestDetailView` i s jeho `@State`. Návrat na záložku PR byl nová
instance s prázdnou stráží, která #188 uplatnila jako první průchod a přepsala tím `⌘1`. Stráž proto
bydlí ve store (`AppStore.appliedSideColumns`), vedle `isReviewPanelExpanded` (#242) — tam, kde
přežije celé okno. **Lekce navíc proti třetímu kolu:** pravidlo *„stráž musí žít aspoň tak dlouho
jako stav, který mění“* se dá splnit **napůl** — `@State` detailu je delší život než `@State` diffu,
ale pořád ne život toho stavu, který je v `UserDefaults`. Otázka je *kde stav končí*, ne *kdo je
nejbližší rodič*.

**Druhá: uplatňovalo se celé rozhodnutí.** `DiffSideColumns` má tři pole a automatika sahá na dvě (`tree`, `panel`), zapisovala ale obě, jakmile
se rozhodnutí od minule změnilo **v čemkoli**. Třetí pole (`margin`) přitom závisí na
`showInlineFindingBubbles`, na sbalení souboru a na odkrytém kontextu — na věcech, které se
překlikávají běžně a se šířkou okna nemají nic společného. Klik, který v okraji vyrobil první kartu
nebo sundal poslední, tím přepsal `tree`, tedy **uloženou volbu u itineráře**.

**Naměřeno**: *Vedle sebe* + `⌘1` + klik na `Nálezy pod řádky` → sloupec zavřený; *Pod sebou* +
`⌘1` + tentýž klik → sloupec otevřený. Šířka se vzala z `CGWindowListCopyWindowInfo` nad běžící
aplikací, ne z 1 048, ze kterých počítá zákres — na těch vada nenastává a měřidlo třetího kola ji
proto nevidělo; a scéna vyrostla na celé `ContentView`, protože jen detail cestu přes `Přehled`
nemá kde vyrobit.

**Oprava: `Policy.sideColumnsToApply(applied:columns:)`** vrací `DiffSideColumnsUpdate` s dvěma
`Optional<Bool>`, kde `nil` znamená **„nechat být“**, ne „složit“. `applied` tím změnil význam: z „co
jsem naposledy zapsal“ na **„jak `Policy` naposledy rozhodla“** — posouvá se i tehdy, když se
neuplatnilo nic. #188 i #503 dál platí: přepnutí pohledu mění `tree` a uplatní se, zúžení okna pod
podlahu kolony kódu taky, a panel se za kartami dál srovná.

**Zamítnuté varianty dvě**: *„nepřepisuj volbu nikdy“* (nález v úzkém okně by zmizel z obrazovky,
#503 by přestalo platit) a *„odvoď efektivní stav z volby, bez zápisu“* (`available` se skládá
z měřené štěrbiny plus šířky toho, co se **kreslí**, takže by se přání a kresba rozešly
a rozhodnutí by se rozkmitalo).

**Zapsaná mezera:** šířka panelu do `available` pořád vstupuje, takže v okně natolik úzkém, že
složení panelu přehodí verdikt o podlaze kolony kódu, se sloupec za panelem pohne. V uživatelově
okně to nenastává a **je to změřené**.

**Zobecnitelné pravidlo:** *automatika, která rozhoduje o víc věcech naráz, smí uplatnit jen tu část,
o které rozhodla jinak než minule.* A druhé, o měření: *když připomínka přijde podruhé, měřidlo
z prvního kola tu druhou příčinu nevidělo.*

Nová tvrzení: čtyři v `DiffColumnFitTests` nad `Policy` (vyčerpávající výčet 8 × 8 dvojic; změna
jedině v `margin` neuplatní nic; první průchod uplatní obojí; přepnutí pohledu se uplatní), tři
v `ItineraryChoiceTests` na 1 460 bodech (dvě o tom, že se volba nepřepsala, a jedno o tom, že se
panel za kartami dál srovná — to poslední je proti variantě „nezapisuj nikdy“ schválně), dvě
v nové `ItineraryHomeReturnTests` nad hostovaným celým `ContentView`em a stráž nad zdrojáky
v `ItineraryEveryTabTests` (stráž deklaruje `Store/AppStore.swift`, detail se jí ptá storu).
**Regrese se ověřila vložením regrese u každé příčiny zvlášť** — a všech pět tvrzení zčervenalo.

**Z Copilotova kola k tomu přišel třetí nález, tatáž třída na jiném místě:** `reportReadToEnd`
se hlásilo i ve stavu `Načítám popis…`, protože `Policy.overviewAtEnd` odpovídá `true`, když se
obsah vejde do výřezu — a store tu značku ukládá **jednosměrně**, takže zastávka `Popis a záměr`
byla hotová u PR, jehož popis nikdo neviděl. Rozhoduje teď `isLoaded` uvnitř té funkce, a je to
`description != nil`, ne „je neprázdný“: PR bez popisu se odškrtnout **musí**, jinak by u něj
počítadlo nikdy nedošlo na konec. `Policy.stepFeedAtEnd` (#325) má tentýž tvar, ale do téhle třídy
nepatří — je to živý přepínač, ne jednosměrná značka.

## #507 — mezerník jako další zastávka a průběh ve stavovém řádku (M14)

Itinerář (#506) říká, **kde jsem**; #507 přidává **pohyb jednou klávesou** a větu, podle které se
dá rozhodnout, jestli review dodělat teď, nebo zítra. Tři věci: **mezerník** na další zastávku,
**`Krok 4 z 9 · 12 min`** ve stavovém řádku (`.sitem plain`, vedle stavu pracovní kopie) a **patka
sloupce** s klávesami `␣ další zastávka · ⌥↓ další nález · ⌥V prošlo`. Zákres přenesla #506,
sekce 47 se nemění.

**Mezerník normálně scrolluje, a proto o něm rozhoduje `Policy`, ne `if` ve view.**
`Policy.itineraryStep` má tři vstupy a klávesu vydá v **jediné kombinaci ze šesti**: mimo textové
pole, s výřezem na konci obsahu a jen když je kam jít. Zakázané tlačítko klávesu nebere, takže se
ve všech ostatních případech propadne scrollu — tentýž vzorec jako `⌘⏎` v tabu `Zeptat se` (#452)
a `⏎` nad otevřenou paletou (#515).

**Že se do pole píše, se nedalo odvodit z tabu** (jako `Policy.claimsReturnShortcut`, #452):
composer rozdělaného review stojí v panelu vedle `Přehledu` i `Změněných souborů`, tedy zrovna
v tabech, o kterých itinerář mluví nejvíc. Vznikl proto `TextFieldFocus` — **množina, ne `Bool`**,
protože pořadí dvou hlášení při přeskoku fokusu není zaručené —, hlásí do něj **čtyři** místa
(`DraftTextField` za všechny čtyři composery naráz, `DiffSearchBar`, `PickerSearchField`,
`CommandPaletteView`) a podává se prostředím jako `terminalFocused` (#459).

**Konec obsahu se měří přesně v těch třech tabech, do kterých vedou zastávky** (`Přehled`,
`Změněné soubory`, `Kontroly` — obor hodnot `ItineraryStop.tab`); jinde mezerník zůstává klávesou
scrollu, a je to odpověď, ne mezera. Hlášení nese, **odkud je** (pull request a tab): hodnota
z minulého tabu je v tom novém k nerozeznání od čerstvé, a nulovat ji úlohou při přepnutí nejde
spolehlivě, protože pořadí nulování a prvního hlášení nové geometrie nikdo negarantuje.

**Kurzor je „kde jsem v procházení“, ne „co je hotové“** (tatáž věc jako `FindingCursor`, #187,
včetně toho, že nepřetéká mezi PR). Bez kurzoru jde první stisk na **aktuální** zastávku, ne na
začátek dráhy; klik na zastávku ho posouvá **toutéž cestou**, jinak by mezerník po kliknutí
pokračoval odjinud, než kam člověk klikl. **Mezerníkem se nic neodškrtává** — hotovo se pozná
z dat.

**V pruhu jsou minuty uplynulé, v hlavičce sloupce zbývající**, a je to vědomý rozdíl: pruh říká,
jak dlouho je záložka otevřená (od otevření, **bez odečítání nečinnosti** — je to orientace, ne
měření práce), hlavička odhaduje, co zbývá. Počítadlo je přitom **jedno**
(`AppStore.itineraryProgress`). Čas drží `tabOpenTimes`, obnovená záložka (#527) se počítá od
restartu a uklízí to **zavření záložky**, ne tik — záložka mimo seznam z pollingu je normální stav
(#527, #531). Odtikává to `TimelineView` ukotvený v otevření záložky, takže se překreslí jeden
`Text`, ne stavový řádek (tatáž konstrukce jako `DashboardCountdown`, #260).

**Mezerník je druhá zkratka okna bez modifikátoru** (po `⏎` na desce, #515) a s tou první se
nepotká: `⏎` platí jedině na domácí záložce, mezerník jedině v detailu PR. Kreslí se glyfem `␣`,
protože ho monospace systémové písmo **má** (glyf 1330, změřeno); v proporcionálním chybí a padá
do `HelveticaNeue`, což se týká jedině nápovědy tlačítka. Patka sloupce je jedna řádka, jak ji má
návrh, a **vešla se až napodruhé**: k textu patří i mezery mezi osmi prvky `HStack`u, takže při
mezeře 5 b vyjde 236,5 b proti 234 b — a přetečení se projeví **oříznutým prvním popiskem**, ne
přetečením. S mezerou 3 b je to 222,5 b; našel to render, ne měřidlo.

Nová tvrzení: sedmnáct v `ItineraryWalkTests` (matice tří vstupů, kurzor mimo dráhu, hotová dráha,
vůle u konce obsahu, text pruhu i patky) a sedm v `ItinerarySpacebarWiringTests` (hlášení konce
podle tabu i PR, pořadí fokusu dvou polí a dvě stráže nad zdrojáky z obou stran). **Regrese
ověřená vložením regrese čtyřikrát** — vypnutý `isEditing`, `nil` brané jako „na konci“, pole bez
hlášení fokusu a tab bez hlášení konce.

**Neověřená mezera:** že klávesa doopravdy zabere a že ji v poli sebere text, ověří jedině člověk
na běžící aplikaci — testovací host nedostane aktivaci, takže nemá key okno (tatáž mezera jako
u celého katalogu, #441).

## #542 — pull request nad stropem souborů řekne proč

`gh pr diff` vrací nad 300 souborů `HTTP 406` (*„the diff exceeded the maximum number of files
(300)“*) a `home-assistant/core#181088` (3 632 souborů) se tím pádem v okně **nedal otevřít
k ničemu**: diff spadl do obecné cesty „Diff se nepodařilo načíst“ se syrovou odpovědí, tedy tam,
kde končí i vypršelý token a nedostupné repo. Tři různé příčiny, jeden text.

**Rozhoduje `Policy` výčtem** (`DiffFailure`: `tooManyFiles(limit:response:)` / `other`,
`Policy.diffFailure(_:)` a `diffFailureNotice(_:)`), ne `if` ve view. `DiffState.failed` proto
nese příčinu, ne hotovou větu. **Strop se pozná z odpovědi, ne z počtu souborů** — ten aplikace
v tu chvíli nezná —, **číslo ve větě je přečtené, nikdy dosazené**, a rozpoznání se **neváže na
třídu chyby** (`GitHubError.responseText`), protože `gh` znění hlášek měnit může. U stropu se
nenabízí `Zkusit znovu` (druhý pokus vrátí totéž), ale `Otevřít na GitHubu`.

**Zbytek okna zůstává k užitku**: přehled, commity, kontroly ani konverzace na diffu nestojí,
takže je záložka dál `PullRequestTabContent.detail` — rozdíl mezi „nemám diff, tady je proč“
a „nemám nic“ je vidět ze stavu. Review se tím neblokuje (reviewer čte diff z pracovní kopie),
ale nedoručený diff sám nespustí nic; tvrdí to test se zapnutým automatickým režimem.

**Zamítnuté varianty dvě.** Stránkovat `/pulls/{n}/files` (jiný formát, druhý rozbor vedle
`DiffParseru`, a review nad třemi tisíci soubory nemá smysl) a dotáhnout diff přes
`compare/<base>...<head>` — ten strop **nemá** a vrátil 14,8 MB unified diffu s kódem 0, jenže
tím se problém jen posune do kresby. **Užitečné je na tom měření**: rozsahový diff (#284) ani
diff commitu (#317) tuhle třídu selhání nemají.

Fixture je skutečná odpověď `gh pr diff` (`Tests/Fixtures/gh/pr-diff-too-large.txt`). Nová
tvrzení: devět v `DiffFailureTests` a tři v `AppStoreDiffCapTests`; **regrese ověřena vložením
regrese třikrát** (vypnuté rozpoznání, dosazený strop místo čteného, vyndaná kontrola číslic).
Mockup se nekreslil — mění se věta ve stavu, který v návrhu je.

## #491 — `idealWidth` bez `.fitted` na třech sheetech a v okně nastavení

**Zadání předpokládalo něco, co měření vyvrátilo, a to je na téhle změně to hlavní.** #327 zapsalo,
že sheet bez `presentationSizing(.fitted)` `idealWidth` **zahodí**; issue z toho udělalo pravidlo
o `ideal*` celém a nabídlo dvě cesty — přidat `.fitted` (změna vzhledu, tedy brána na návrh), nebo
`ideal*` odebrat jako mrtvou hodnotu (změna bez vizuálního projevu). Ta druhá by ale **zmenšila tři
hotové obrazovky**: `idealHeight` si sheet vezme i bez `.fitted`. Kdyby se šlo podle zadání,
`ReviewSubmissionSheet` by přišel o 140 bodů výšky, `MergeSheet` o 80 a `AgentPromptSheet` o 200 —
a vypadalo by to jako úklid.

**Výčet se potvrdil grepem nad dnešním `main`em**, ne převzal z issue (tabulka v něm je z doby před
#488 a `MergeSheet.swift` se u #556 hodně změnil). Sedí: `App/Views/AgentPromptSheet.swift`,
`MergeSheet.swift`, `ReviewSubmissionSheet.swift` a `Settings/SettingsView.swift`. K tomu je
v grepu ještě `App/Views/DiffSearchBar.swift`, a ten je **v pořádku** — obyčejný pružný rámec
(`minWidth: 160, idealWidth: 220, maxWidth: 260`), ne sheet.

**Změřeno dvěma nástroji.** Samostatný `swiftc` skript nad prázdným obsahem oddělil chování šířky od
výšky (šířka je vždycky `max(minWidth, 470)`, ideál se neuplatní ani nahoru, ani dolů; výška ideál
bere až po strop obrazovky) a druhý, zabalený do minimálního `.app`, změřil okno `Settings` scény —
tam je **mrtvé obojí** a oživit to nejde, `presentationSizing` je modifikátor prezentace, ne scény.
Nad skutečnými obrazovkami pak měří `SheetSizingTests`. Celé tabulky jsou v
[`docs/testovani.md`](testovani.md#co-dělá-ideal-u-sheetu-a-v-okně-settings-491), rozbor
v [`docs/architektura.md`](architektura.md#ideální-šířka-a-ideální-výška-nejsou-totéž-491).

**Výsledek: odešla jen ta šířka, která nikdy nic neznamenala.** U tří sheetů zůstal `idealHeight`,
u okna nastavení nezůstalo nic (obojí bylo mrtvé). Že je to neviditelné, se tvrdí **dvěma běhy téže
suity** — jednou s `idealWidth` v rámci a jednou bez něj — a vyšlo u obou totéž: 560 × 560,
507 × 380, 840 × 620.

**`.fitted` se u všech tří zamítlo**, tatáž odpověď jako u #466: rozšířit hotovou obrazovku a udělat
ji roztahovatelnou je změna vzhledu, a ta jde přes zákres do návrhu a souhlas — což tahle oprava
rozvržení není. `docs/navrh.html` se proto nezměnil.

**Do `Policy` se nic nestěhovalo, a je to zapsané rozhodnutí**: `Policy.rawSessionSheet*`
a `Policy.codeSheetSizing` existují proto, že se z nich **počítá**, kdežto tyhle tři sheety nic
neukládají a nic z obrazovky neberou — konstanta by jen přestěhovala literál a testu by vzala
možnost spadnout.

**Grep z `CLAUDE.md` zůstal výčtem k posouzení, ale ubyla mu ta část, kterou umí tvrdit test.**
`SheetSizingTests` drží dvě stráže nad zdrojáky: sheet s `idealWidth` musí mít `presentationSizing`,
a roster sheetů (`App/Views/*Sheet.swift`) je uzavřený, aby to nešlo obejít souborem s jiným jménem.
`idealHeight` se schválně nehlídá — funguje.

**Cestou se opravilo tvrzení v sondě.** `AgentPromptRenderProbe` rendrovala sheet a seznam ve dvou
šířkách (1 080 a 840) s odůvodněním, že se sheet otevře na ideálu a dá se stáhnout na podlahu —
jenže 1 080 byla šířka, kterou ta obrazovka **ani jednou neměla**. Zbylo 840.

**Zobecnitelné pravidlo:** *pravidlo zapsané o jedné ose neplatí automaticky o druhé* — a když se
zadání odvolává na starší měření, patří k práci ověřit, že to měření tvrdí zrovna to, co se z něj
cituje.

**Copilot na tomhle PR nedoběhl, a je to neověřená mezera.** Job běžel, ale spadl za 32 sekund na
`Resource not accessible by integration` při čtení metadat PR (`COPILOT_PERMISSION_GATE_REASON:
ineligible_app`) — tedy **ne** na velikosti `CLAUDE.md` (99 047 B, pod stropem) ani na spotřebovaném
requestu (job má správné jméno a doběhl). Padalo to na **osmi** kolech za pětatřicet minut napříč PR
z různých slotů a druhé vyžádání vyrobilo nový run, který spadl stejně, takže to není o téhle
změně. Je to **tatáž třetí příčina, kterou zapsalo #507 a doplnilo #542** — tady počtvrté a s údajem
navíc: tři kola nad **třemi různými PR** vznikla během 171 sekund a spadla všechna stejně, takže
o diff ani o jedno PR nejde. `CLAUDE.md` měla 99 047 B, o 339 B víc než u #507 a pořád pod stropem. Postup, jak ji odlišit od zbylých dvou, je
v [`docs/github-cli.md`](github-cli.md#třetí-příčina-resource-not-accessible-by-integration-507). Vlastní revize diffu
proběhla (grepy z `CLAUDE.md` plus čtení diffu) a našla v ní dvě věci: přehnané tvrzení v komentáři
u sondy (`ideal*` místo „ideální šířka“) a dvě smyčky přes jednoprvkové pole.

## #526 — odznak v railu do rohu a pruh aktivní položky (zákres 50)

**„Uvnitř rámu“ z #366 znamenalo „přes ikonu“.** Odznak je 24 × 18 na rámu 34 × 30, takže zakryje
jeho pravou horní čtvrtinu, ať je posazený kamkoli — v běžícím okně byla pod `5`, `3` a `30` vidět
jen spodní hrana glyfu a položky railu se poznávaly podle pořadí, ne podle ikony. Odznak proto jde
**do rohu** (`offset(x: 7, y: -5)`), tedy zase ven z rámu. Není to návrat před #366: tehdy vadila
**barva** (fialový akcent, tedy „tady jsi“) a šest bodů doprava bez protiváhy; teď jde ven o sedm,
je červený a identitu aktivní sekce mezitím převzal pruh. **Šířka railu 52 bodů se nemění** —
červená plocha končí na 47, obtah na 49 a obrys railu je na 51.

**Aktivní sekci značí pruh na hraně railu, ne barva ikony.** 2 × 18 bodů v akcentu, poloměr 1,
a je to **tentýž prvek, kterým `PullRequestRow` značí stav na hraně řádku fronty** — jen svisle.
Osmnáctka se počítá z **výšky řádku** (`top: 6`, `bottom: 6` v rámu vysokém 30), ne z ikony.
Aby se měl pruh kam pověsit, bere si **řádek položky celou šířku railu** (`SidebarRail.width`)
a tlačítko v něm zůstává 34 bodů: rozšířit rám tlačítka **nešlo**, klikací plocha by se nafoukla
na celou šířku a klik do prázdna vedle ikony by přepínal sekci.

**Změna zapsaného rozhodnutí z #414**: `Policy.activityBadge(unread:isActive:)` → `activityBadge(unread:)`.
`isActive` rozhodoval právě proto, že odznak ikonu překryl a na aktivní položce by zbyl červený
puntík bez identity (poznámka 95 v návrhu). S pruhem ten důvod odpadl, takže `Dění` ukazuje počet
nepřečtených **i zevnitř**. Parametr **zmizel celý**, ne že by se ignoroval — parametr, o kterém se
nerozhoduje, je jen místo, kam se dá omylem sáhnout. Značka poslední návštěvy se u toho nemění:
posouvá ji dál až **odchod** ze sekce, takže počet uvnitř `Dění` na nulu nespadne.

**Zákres je jedno pravidlo v CSS railu, ne komponenta.** Rail je chrom okna, takže se změna projeví
ve všech sekcích, které ho kreslí; sekce 50 drží jen zvětšený výřez, srovnání s dneškem a důvody.
Sekce 27 (`Dění`) je záznam dneška, takže se překreslila s ním — aktivní položka v ní má odznak.

Nová tvrzení: `RailBadgeTests` (poloha proti **změřenému** rámu ikony, ne proti konstantě; že odznak
nic neořezává — #483 —, poznáno z tvaru pravé hrany; pruh na hraně railu a to, že ho má **jedna**
položka) a výčet `Policy.activityBadge` nad jedním vstupem. **Regrese ověřena vložením regrese**:
s vráceným `offset(y: 1)` padne poloha, s vynechaným pruhem obě tvrzení o aktivní sekci — a barevná
tvrzení u obojího zůstanou zelená, takže se ty věci pořád měří zvlášť.

**Měřidlo pásů v `SidebarRailTests` přestalo brát vzorek pozadí z prvního bodu**: na hraně railu
teď leží pruh, takže by vzorek na řádcích aktivní položky vydal akcent a proti němu by se jako
„obsah“ jevil celý zbytek řádku. A **tolerance u washe aktivní položky je poloviční** — ve světlém
režimu je od `Palette.line` jen 0,032 daleko, takže se do měřeného rámu připočítával obrys railu
i oddělovač a rám vycházel přes celou výšku railu.

**Copilot k tomuhle PR nedoběhl a je to neověřená mezera** (2026-09-04). Job běžel, ale spadl na
**prvním** volání API — `Resource not accessible by integration` při `Fetching PR metadata` — a bylo
to tak u **čtyř různých větví** (#526, #542, #491 dvakrát), tedy repo-wide, ne na tomhle diffu.
Vyžádání se opakovalo třikrát, pokaždé stejně. Je to **tatáž třetí příčina, kterou o hodinu dřív
popsalo #507**; tenhle záznam k ní přidal jen čtvrtou větev a příkaz na čtení logu
([`docs/github-cli.md`](github-cli.md)).

**Místo něj proběhla druhá vlastní revize** (subagent nad `git diff main...HEAD`) a našla čtyři
reálné věci, které do PR přišly opravené:

- **Nadpis dne a odznak v railu nejsou totéž číslo.** README i komentář v sekci 27 tvrdily, že jsou —
  nadpis počítá nepřečtené **za ten den** (`Policy.dayNote`), odznak za **celý záznam**
  (`Policy.unreadActivity`). Přes půlnoc se rozejdou. Do #526 to nevadilo, protože ta dvě čísla
  nestála vedle sebe; tenhle diff je poprvé postavil na jednu obrazovku.
- **Sedm míst v repu pořád tvrdilo „odznak se na aktivní sekci nekreslí“** — včetně tabulky `Policy`
  v `architektura.md`, kde stála **neexistující signatura** `activityBadge(unread:isActive:)`.
  Opraveno jako třída, ne výskyt.
- **„Rail se kreslí ve dvaceti sekcích“ byl odhad**; grepem je jich **jedenáct**.
- **Dvě tvrzení v `RailBadgeTests` nemohla spadnout** (`rightmost.count == box.height` je identita,
  `touching > 0` tautologie nad maximem). Zůstalo to jediné nosné, `touching < box.height − 2`.

A jedna mezera se zavřela testem: tvrzení **„klikací plocha se rozšířit nesmí“** stálo jen
v komentáři, přitom visí na **pořadí modifikátorů** (`.frame` za `.buttonStyle`). Hlídá ho teď stráž
nad zdrojákem (`SidebarRailTests.widensTheRowButNotTheButton`, kód bez mezer podle #490/#550);
ověřená vložením regrese — s rámem 52 uvnitř labelu padne i test o šířce ikon.

**Vyčnívající roh odznaku už není klikatelný**, a je to důsledek, ne opomenutí: klikací plocha
zůstává rám tlačítka, protože jinak by sekci přepínal klik do prázdna vedle ikony. Odznak je údaj,
ne ovládání.

## #563 — mergnutelný PR patří do `K merge` i s blokujícím nálezem

Vyšlo to z proklikání na ostrých datech:
[`keboola/platform-libraries#566`](https://github.com/keboola/platform-libraries/pull/566) ležel
v `Předat agentovi`, přestože GitHub o něm hlásil `mergeable: true` a `mergeable_state: clean`, PR
nebyl draft a checky stály 22 pass / 22 skipping / 0 fail. Držel ho tam **jeden nález** z
`code-review:code-review` (`CONFIRMED`, `correctness`, `libs/input-mapping/src/Table/Strategy/Local.php:22`),
který nikdo neodmítl: `correctness` je ve výchozí sadě `Policy.defaultBlockingCategories`, takže
z něj vyšla překážka `MergeObstacle.blockingFindings(1)` → `MergeOffer.blocked` →
`isMergeReady == false` → pruh `handOff`.

**Pokyn z #515 se tím splnil jen napůl.** Třetí proklikání znělo *„co je mergeable, tak by mělo být
k mergnutí“*, a implementace z něj vzala jedině to, že slévatelnost přebíjí předání. `isMergeReady`
se ale pořád ptalo `mergeOffer`, a ta mezi překážky počítala **náš vlastní názor na kód**.

**Blokující nález přestal být překážkou merge úplně** — mizí z `Policy.mergeOffer`, ne jen
z `isMergeReady`. Je to tatáž třída, kterou `isMergeReady` už jednou vyřešilo pro `notAllowed`
(brána odesílání mluví o tom, co smí *aplikace*), jen o úroveň dál: nález mluví o tom, co si o kódu
myslí *reviewer*. Ani jedno není věta o tom, jak stojí *pull request*.

**Zamítnutá varianta: „jen pruh, tlačítko blokuje dál“.** Nechat překážku ve výčtu a obejít ji
v desce by dalo PR v `K merge` se **zakázaným** `Mergnout` — dvě odpovědi na jednu otázku.
`isPublishingGate` proto zůstává **jediná** výjimka. Případ i s jeho větou se ruší celý: stav, který
nikdo nečte, svádí spolehnout se na něj; v panelu po něm mrtvá větev nezbyla, protože se výstraha
skládá `obstacles.map(\.sentence)`.

**Spadlý check blokuje dál.** `mergeable: true` je věta o konfliktu, ne o zelené CI, takže přísnost
vůči `UNSTABLE` z #465 platí beze změny — nabídnout nevratnou akci nad rozbitým buildem je jiná
třída než nabídnout ji nad nálezem, o kterém člověk ví.

**Nic jiného se nemění.** Nález se dál počítá do odznaku na řádku, do osy filtru *jen blokující*, do
souhrnu fronty, do notifikace o doběhlém review i do pořadí řádků. Vidět je jako nález — v panelu,
na řádku a v okraji —, ne jako zámek na nevratné akci. Ruší se tím zapsané rozhodnutí z #465;
v záznamu zůstalo i s důvodem, proč přestalo platit.

**Testy.** Dvě věty, které se nesmí rozejít (nález nezakazuje, červený check zakazuje), stojí
v **jednom** testu nad scénou z #566; k tomu výčet všech jedenácti překážek, ve kterém žádná
nemluví o nálezu, a uvnitř vyčerpávající `switch`, který novou překážku nepustí přeložit.
Nejcennější je `AppStoreMergeTests.keepsTheBlockingFindingVisible` — tvrdí, že se **nic
neztratilo**: pruh `K merge`, `Mergnout` povolené, odznak na řádku, osa filtru i souhrn pořád
počítají ten nález. **Regrese ověřená vložením regrese** — chytla se dvakrát: vrácení případu do
enumu položí výčet **při překladu**, a doplněný `case` v něm pak shodí
`keepsTheBlockingFindingVisible` čtyřmi tvrzeními. Sonda sekce přišla o scénu
`vetev-blokujici-nalez`: nakreslila by se stejně jako `vetev-zeleno`, a dvě kopie jednoho snímku
tvrdí, že je co srovnávat.

**Na obrazovce se nemění vzhled, mění se, kam řádek spadne** — `docs/navrh.html` proto zůstal
beze změny.

**Ověřeno na ostrých datech.** Slot dostal do své cache **kopii** záznamu review k `#566` (nález
o `verifyToken()`, `CONFIRMED`, `correctness`) a PR se v něm otevřel přes `prism://open?url=…`.
V sekci `Větev` stojí `ondra/AJDA-3148 → main`, `1 commit · 44 checků · zeleno`, `o 21 commitů
vzadu` — a ve výstraze **jediná** věta, ta o vypnutém odesílání ve slotu. Do #563 by tam byla
druhá (*„Reviewer hlásí blokující nález.“*), takže je z toho poznat přesně ta změna: `notAllowed`
je jediná zbylá překážka, tedy `Policy.isMergeReady` vydá `true` a řádek patří do `K merge`.
Nález se přitom **neztratil** — `Nálezy 1`, pilulka `code-review 1` v hlavičce, `blokuje
correctness` v okraji a červená tečka u `Local.php` v itineráři.

**Neověřená mezera: pruh `K merge` na desce se ve slotu nafotit nepodařilo.** Stav větve se dotahuje
teprve při otevření PR (`loadBranchStatus` visí na `loadDetail`), takže deska ho před otevřením
záložky nezná a `#566` na ní do té doby leží v `Předat agentovi` kvůli `statusLoading` — tedy z jiného
důvodu, než o kterém #563 je. Přepnout zpátky na `Přehled` s už načteným stavem by chtělo klik do
okna a session neměla **povolený asistenční přístup** (`osascript` skončil na *„nemá povoleno
posílání stisknutí kláves“*, klik nedělal nic). Neobcházelo se to: pruh tvrdí
`AppStoreMergeTests.keepsTheBlockingFindingVisible` (řádek **v** pruhu `K merge`) a na obrazovce si
ho proklikne člověk.

## #570 — `CLAUDE.md` počtvrté pod hranici: stěhují se odstavce, ne se zkracují věty

**Soubor měl 99 047 B a strop je ~100 kB**, takže by ho příští issue, které do něj sáhne,
překročilo — a nad stropem 110 tisíc tokenů si ho Copilot bere jako custom instructions a review
na PR **vůbec nedoběhne**. Dvě sekce dělaly 56 % souboru: `## Konvence` 29 102 B a `## Tvrdé
podmínky` 26 188 B.

**Nejzajímavější výsledek je negativní: skoro nic se nestěhovalo, protože to v `docs/` už bylo.**
Před prací se pro každý odstavec, který měl odejít, pustil grep na jeho klíčové jméno přes `docs/`.
Ze zhruba padesáti sond vyšly prázdné tři — `| grep -q` s `pipefail` (#61), bundle konvence
(`CFBundleIconName`, `CFBundleDevelopmentRegion`, `stringsdata`) a tabulka pěti vzorů, které
**Copilot v tomhle repu nachází opakovaně**. První dvě proto v `CLAUDE.md` zůstaly beze změny,
třetí se přestěhovala do
[`docs/github-cli.md`](github-cli.md#co-copilot-v-tomhle-repu-nachází-opakovaně) a zbyla po ní věta
pravidla, jednořádkový výčet a odkaz. Všechno ostatní byla **duplikace**: pravidlo si k sobě
přitáhlo zdůvodnění, které vedle něj už stálo za odkazem. To je i odpověď na otázku, **proč soubor
roste** — nedělají to nová pravidla, ale zdůvodnění dopisovaná ke starým.

**Cíl 70 kB se nesplnil, vyšlo 74 329 B, a je to zapsané rozhodnutí.** Ze 99 047 B je to −25,0 %
a ~26 kB pod hranicí, u které Copilot přestává doběhnout. Poslední 4 kB se ale nedaly vzít jinak
než mazáním pravidel, což zadání zakazovalo: v hotovém souboru je 22 116 B tučného textu (věty
pravidel a zdůrazněné výčty), 5 919 B cílů odkazů, 5 618 B tabulek a 5 827 B `bash` bloků s grepy.
Každý další průchod už vydával pod 500 B a platilo se za něj čitelností. Rozbor je [v
specifikaci](superpowers/specs/2026-07-31-prism-design.md#počtvrté-570-stěhují-se-odstavce-ne-se-zkracují-věty--a-cíl-je-70-kb-ne-40).

**Čtyři invarianty se ověřovaly měřením, ne okem.** Inventář vět pravidel (mechanická definice:
tučný úsek na začátku logické řádky, plus položky seznamu bez tučného začátku) vydal **159 před
i po**, porovnáno `diff`em nad seřazenými seznamy. Všech **32 grepů** z `CLAUDE.md` se pustilo před
prací i po ní do souboru a výstupy jsou shodné do posledního řádku. Kotvy: **116 odkazů před, 85 po,
rozbitých 0** v obou případech — úbytek je slitím druhých a třetích odkazů u téhož pravidla.

**Na obrazovce se nemění nic** — je to čistě dokumentace. Testy proto nemají co chytat; pustily se
celé jen proto, aby stráže nad zdrojáky potvrdily, že se v `App/` ani `Tests/` nesáhlo na nic.

**Copilot se na tenhle PR schválně nepouštěl.** GitHub má výpadek entitlementu
(`COPILOT_PERMISSION_GATE_REASON: ineligible_app`, tatáž třetí příčina jako u #507, #542 a #491),
který v ten den selhal na osmi kolech napříč čtyřmi větvemi. Je to **neověřená mezera**; vlastní
revize diffu proběhla a je popsaná v PR.

## #530 — Otevřít soubor v editoru na řádku nálezu

Tlačítko `Otevřít v <editoru>` v hlavičce souboru (glyf `↗`) a na kartě nálezu (popisek celý).
Otevírá **kopii z cache aplikace**: u cizího PR pracovní strom review, u vlastního strom pro
srovnání větve (`-sync`), odkud změna odejde jedině přes `Force push` se sheetem (#466).
Uživatelův klon aplikace dál nezná.

Volba je v `Nastavení › Systém › Otevírat soubory v` (`Nic` / Xcode / VS Code / Cursor), výchozí
je `Nic` — a **bez zvoleného editoru se tlačítko nekreslí**, ne zašedne. Adresu skládá
`Policy.editorURL` jako čistou funkci (tři schémata, jedna sada escapování); hranici cache hlídá
`CacheFile.refusal`, tedy tatáž kontrola jako jinde v repu a **přísnější** z jejích dvou odpovědí,
protože symbolický odkaz na souboru by editor otevřel jeho cíl.

Rozbor je v [`docs/architektura.md`](architektura.md#otevření-souboru-v-editoru-530), měření
a mezery v [`docs/testovani.md`](testovani.md#otevření-souboru-v-editoru-530), rozhodnutí ve
[specifikaci](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--otevření-souboru-v-editoru-530).
Zákres je sekce **51** návrhu.

**Zapsané mezery jsou dvě.** Že se editor doopravdy otevře, ověřeno není — znamenalo by to
spustit cizí aplikaci bez vědomí uživatele; ověří to člověk kliknutím. A `xcode://open?url=…&line=`
je jediný ze tří tvarů, který nemá oporu v dokumentaci editoru, jen v tom, jak ho používají cizí
nástroje.

**Copilot se na tenhle PR schválně nepouštěl** — tentýž výpadek entitlementu na straně GitHubu
(`COPILOT_PERMISSION_GATE_REASON: ineligible_app`) jako u #507, #542, #491 a #563. Je to
**neověřená mezera**; vlastní revize diffu proběhla a je popsaná v PR.

## #572 — `K merge` po startu: slévatelnost se dotahuje tikem, ne až se záložkou

**Pruh `K merge` na domově byl po startu prázdný**, dokud se PR neotevřel. Vyšlo to z proklikání
#563: pravidlo *„co je `mergeable`, patří do `K merge`“* platilo až po otevření záložky. Nebyla to
regrese z #563 — starší stav, který se tím jen zviditelnil.

**Chybělo víc než slévatelnost.** `AppStore.isMergeReadyForLane(_:)` staví na `Policy.mergeOffer`,
a ta potřebuje hlavičku i stav větve; obojí se dotahovalo teprve v `loadDetail`. Deska proto
u vlastních PR vracela `waiting`, což je nad nenačtenými daty správná odpověď — opravit se to dá
jedině tím, že se data dozvíme dřív. **`Policy.mergeOffer`, `isMergeReady` ani `lane` se nezměnily
ani o písmeno**; přibyl vedle nich jen předfiltr `Policy.mergeReadinessProbe`, který odpovídá na
otázku „koho se zeptat“.

**Vybíralo se měřením, ne odhadem.** Nad 23 vlastními otevřenými PR ze 16 repozitářů stálo dotažení
po jednom **46 volání a 29,6 s** (s commity 69 volání a 40,6 s); jeden aliasovaný GraphQL dokument
stojí **1 volání, 2,60–3,64 s a 1 bod z 5000/h**. Vzor je tentýž jako u hlav z tiku (#420). Čísla
i zamítnutá cesta jsou v [`docs/testovani.md`](testovani.md#kolik-stojí-slévatelnost-vlastních-pr-572).

**Otevření vlastního PR tím zlevnilo**, ne zdražilo: slévatelnost je z tiku v cache, takže místo
dvou volání (`pr view` + `compare`) zbývá jedno — poloha větve proti základu se do hromadné
odpovědi nevejde, protože `compare` potřebuje jméno základu a hlavu z téže odpovědi.

**Tik zůstal tichý.** Předfiltr porovnává razítko `updatedAt` v `detailStates` a `branchStatuses`,
tedy tutéž cache, jakou má otevřená záložka: dokud se pull request nepohne, neposílá se nic. Na
mergnutý a zavřený PR se **neptá vůbec** — GitHub u nich vrací `mergeable: UNKNOWN` navždycky
(změřeno u #465 na `PRism#470`, doloženo znovu fixturou z `cli/cli#14363`).

**Na obrazovce se mění jediná věc: pruh `K merge` má obsah hned po startu.** Vzhled se nemění,
`docs/navrh.html` se nesáhlo. Testů je nad slitým stavem (po #530) **5 527**, z toho **+29**
z tohohle PR, a jsou zelené; regrese se ověřila vložením čtyř regresí.

**Plný běh nad slitým stavem byl jednou falešně červený a je to ta známá třída, ne regrese.**
Sedm suit (`AppStore — review`, `— odmítnuté nálezy`, `— opakování jednoho reviewera`,
`— routing reviewerů`, `— zadání pro reviewera`, `— notifikace o doběhlém review`
a `HealthMonitor`) spadlo pod load average 17 při souběžném buildu tří slotů. Pozná se to
podle tří věcí naráz: **hláška je o čekání** (24× `Nedočkalo se … strop 120.0 seconds`,
k tomu jednou `metrika písma`), **spadlé suity se změny netýkají** — všechny tři suity #572
v tom **červeném** běhu prošly — a **v izolaci projdou hned**: těch sedm plus tři suity #572
je **101 testů v 10 suitách za 0,329 s**.

**Copilot se na tenhle PR schválně nepouštěl** — GitHub má výpadek entitlementu, tatáž příčina jako
u #570. Je to **neověřená mezera**; vlastní revize diffu proběhla a je popsaná v PR.

## #541 — přepnutí na `Změněné soubory` se změřilo; zlevnit se nepodařilo

**Měřicí issue, a výsledek je negativní i doložený.** Přepnutí na tab s diffem stojí nad ostrým PR
**737 ms u 45 souborů, 1,10 s u 71 a 1,17 s u 157** (CPU hlavního vlákna, Debug, okno 1512×874).
Čísla z #541 tedy nad dnešním `main`em platí.

**Hlavní zjištění: ostrý diff není zvláštní, je jen větší.** Sonda uměla do #541 nejvýš 2 000
řádků, kdežto ostré diffy mají 5 200 až 6 200 — a měnily naráz tři věci. Přibylo proto **syntetické
dvojče** o týchž souborech, hunkách a řádcích, ale s generovaným textem; měří se **hned vedle své
předlohy v témž běhu**. Vyšlo stejně ve všech třech velikostech, takže zvýrazňování syntaxe,
word-level rozdíl ani rozmanitost obsahu tu cenu nedrží.

**Věta ze zadání, která už neplatí:** přepnutí **bez** diffu nestojí 54–60 ms nezávisle na počtu
souborů, ale **82 → 128 → 237 ms** se 45 → 71 → 157 soubory. Ta čísla v #541 měla ablovaný pás mapy;
v okně, jak ho člověk vidí, roste se soubory pás mapy PR (#501) i rozložený sloupec s itinerářem
(#506/2), protože oba stojí vedle **všech** tabů. Z té sekundy je tedy ~240 ms mimo diff.

**Šestá zamítnutá varianta v téhle rodině.** V `sample`u drží `DiffView.swift:517` (čtení `$0.size`
v `onGeometryChange`) 26 až 42 % hlavního vlákna. Přesun téhož modifikátoru na `background` ho
z profilu **odstranil** a **cenu nezměnil** — tatáž práce se objevila pod
`AnimatableFrameAttribute`. Zůstalo z toho pravidlo o čtení `sample`u, ne oprava.

**V `App/` se nezměnilo nic**, takže na obrazovce není co vidět; změny jsou v sondě a v dokumentaci.
Zapsané jsou i dvě meze měření: jeden ze čtyř vzorků ukazoval 44,6 % v procházení responder stromu
a tři další nulu (proto se kořen čte u každého vzorku zvlášť, #350), a sonda hlásí, že se bloky mimo
pás **neodnasazují vůbec** (219 z 219), kdežto #472 u 2 000 řádků zapsalo pět — to je **neověřená
mezera**, protože sonda diffem nescrolluje a v harnessu se to rozhodnout nedá.

**Měřilo se pod zátěží tří dalších slotů** (`load average` 3,9 až 9,4), proto jsou v tabulkách obě
hodnoty ze dvojice, ne průměr.

**Testů je nad slitým stavem (po #530 a #572) 5 530 v 542 sadách**, z toho **+3** z tohohle PR —
`DiffMaterialTwinTests`, protože na tom, že se dvojče předloze velikostí vyrovná, stojí celý závěr.

**Plný běh nad slitým stavem byl falešně červený a je to ta známá třída, ne regrese.** Dvanáct sad
spadlo pod souběžným plným během jiného slotu; pozná se to podle tří věcí naráz: **hláška je
o čekání** (46× `Nedočkalo se: review doběhne … strop 120.0 seconds`, k tomu jednou `metrika písma
se neusadila` a šestkrát `.timedOut` v `RepoCheckout proti skutečnému gitu`), **spadlé sady se
změny netýkají** — v `App/` se nezměnil znak a sada tohohle PR v tom **červeném** běhu prošla —
a **v izolaci projdou hned**: těch dvanáct plus `DiffMaterialTwinTests` je **104 testů ve 13 sadách
za 11,1 s**.

**Copilot se na tenhle PR schválně nepouštěl.** GitHub má výpadek entitlementu — tatáž příčina jako
u #572, #570, #530, #507, #542 a #491. Je to **neověřená mezera**; vlastní revize diffu proběhla
a je popsaná v PR.

## #528 — návrh změny kódu z výběru řádků a jeho čtení ve vlákně (zákres 54)

GitHubový blok ` ```suggestion ` je nejúčinnější druh komentáře — autor ho přijme jedním kliknutím.
Composer u řádku ho neuměl a ve vlákně od kolegy se kreslil jako obyčejný blok kódu. Přibylo obojí:
tlačítko **`Návrh změny`**, které vloží blok **předvyplněný původními řádky** a pod polem ukáže
náhled mini diffu, a **čtení návrhu ve vlákně** jako mini diff s tlačítkem `Do zadání pro agenta`
na vlastním PR.

**Tvrdá podmínka č. 1 se nemění ani o položku.** Návrh je **text komentáře** a odchází s review přes
`ReviewPublishing.submit`; grep vydává dál sedm souborů u `ReviewPublishing` a tři u `BranchPushing`,
`SingleWayOutTests` zůstaly beze změny. *Aplikovat* návrh (`applySuggestedChanges`) je zápis do
repozitáře a schválně tu není — na to je agent a push se sheetem (#466). Hlídají to **dvě stráže nad
zdrojáky**: to jméno se v `App/` nesmí vyskytnout a čtyři nové soubory nesmí znát ani jeden ze dvou
protokolů.

**Odmítnutí nese větu, ne zašedlé tlačítko.** Rozsah přes dva hunky je u komentáře v pořádku (#110),
u návrhu ne: mezi hunky leží kód, který diff neukazuje, a přijatý návrh by ho přepsal. Totéž u řádku
ze staré verze souboru a u kotvy, která v diffu není.

**Zapsaná mez u čtení:** červená strana mini diffu je **jeden řádek** (z `diffHunk`u, který končí
u komentovaného řádku). Kde rozsah vlákna začíná, data vlákna neříkají, takže hlavička bloku počítá
**nové** řádky, ne nahrazované — hádat rozsah by bylo tvrzení, které data neunesou.

**Sonda našla dvě věci, které z kódu vidět nebyly:** tlačítko `Do zadání pro agenta` se v panelu
o 300 bodech ořezávalo na `Do zadání pro ag…` (věta vedle něj se přesunula pod něj) a pole komentáře
ukazovalo z vloženého bloku dva řádky, protože `TextEditor` s obsahem neroste.

**Copilot se na tenhle PR schválně nepouštěl.** GitHub má výpadek entitlementu (`ineligible_app`) —
tatáž příčina jako u #541, #572, #570 a dalších. Je to **neověřená mezera**; vlastní revize diffu
proběhla a je popsaná v PR.

## #512 — Odložit PR: do rána, do dalšího pushe, do dalšího komentáře (M16, zákres 53)

**Filtr schová repo nebo autora, ne jeden pull request.** Botí PR ležel ve frontě týden, počítal se
do odznaku i do věty pod pozdravem — a automat na něj každou minutu zvažoval review.

**Odložení je stav, který něco skrývá, takže musí být poznat, že něco skryté je.** To je celé
zadání a promítlo se do **čtyř** vývodů, ne jednoho: blok `Odložené · 2` pod frontou, připsání
`· 2 odložené` do věty pod pozdravem na desce (odložené PR není v žádném pruhu), vlastní prázdný
stav fronty `Všechno odložené` a řádek `Vrátil se z odložení · přišel push` v `Dění`. Fronta, ze
které práce potichu zmizí, je horší než fronta, ve které leží.

**Podmínka, ne jen čas** — `Policy.snoozeExpired(_:head:comments:now:)` nad třemi případy. Měří se
proti **hodnotě**, ne proti `updatedAt`: to se hýbe i po štítku, takže by `do dalšího komentáře`
skončilo pushem. Rozhodlo se, že **neznámé měřidlo nikdy neznamená „vypršelo“** — základ dosadí
první rozhlídka a do té doby odložení trvá. Směr chyby je zvolený schválně: odložení, které se
zruší dřív, než mělo, vypadá jako porucha, kdežto odložení o minutu delší ukončí `Vrátit teď`.

**Zmizí všude naráz, včetně automatu.** `Policy.automaticallyReviewable` dostalo `isSnoozed` bez
výchozí hodnoty — *nechci to teď vidět* znamená i *neplať za to teď*. Běh, který už běží, se
**neruší**: session je utracená v okamžiku, kdy začne. Notifikace o doběhlém review se u odloženého
PR nepošle, ale **do dění se zapíše** (chip `bez banneru`).

**Ukládá se k PR, ne k `headSha`** (`snoozed.json`, `SnoozeStore`), a je to zapsaná volba proti
tvrdé podmínce č. 5: ta mluví o nálezech, kdežto odložení o kódu netvrdí nic — push ho nemá
zneplatnit, nýbrž **splnit**. Precedens je rozhovor nad PR (#452). Čte se **před prvním tikem**,
jinak by první tik po startu pustil review na PR, který jsem si schoval.

**Rozhlídka je jeden dávkový GraphQL dotaz na všechna odložená PR** (`SnoozeProbeQuery`,
`fetchSnoozeSignals`), s předfiltrem přes `updatedAt` a se stropem dvacet — na klidný den **nula
volání**, u časové podmínky **nikdy** žádné. Vlastní dotaz vedle toho na hlavy (#420), protože obě
rozhlídky mají jiný předfiltr; cena je jedno volání navíc v nejhorším případě.

**Odložit jde jen cizí PR**, a je to hranice **kresby**: blok visí pod frontou a na desce, takže
odložené vlastní PR by ze sekce `Moje PR` zmizelo a nikde by se neobjevilo. **Na cizím PR se odložit
dá naopak odevšad, kde se ten řádek kreslí** — a je to oprava po proklikání, ne původní návrh:
nabídka byla navěšená jedině ve `PullRequestListView`, kdežto `PullRequestRow` se kreslí na **třech**
místech, takže na domově (deska) odložit nešlo nic, přestože tam věta pod pozdravem hlásila
`2 odložené`. Opravily to tři věci: `SnoozeAction` jako **jedna hodnota z jednoho místa**
(`AppStore.snoozeAction(for:)`), **stráž nad zdrojáky** (kde stojí `PullRequestRow(`, tam musí stát
i `snoozeAction:`) a **týž blok `Odložené` v pravém sloupci desky**, kreslený z týchž řádků
(`SnoozedRowsView`). Číslo, ze kterého z té obrazovky nevede cesta, je horší než žádné číslo.

**Zákres je sekce 53** v `docs/navrh.html` (dva nové komponenty: `.s53-menu` a `.s53-snoozed`,
ten druhý s modifikátorem `.plain` pro rám bloku na desce).
**`Vlastní datum…` z kresby vypadlo** — kalendář v kontextové nabídce je vlastní obrazovka a delší
odklad než týden se dá složit dvojím odložením; je to **zapsaná mezera proti zadání issue**.

**Zákres sekce 53 to dokreslil zpětně**: druhá dvojice panelů (věta pod pozdravem vedle bloku
v pravém sloupci desky) a poznámka 193 mluví o **čtyřech** vývodech místo tří. `docs/navrh.md`
sedělo na 52 sekcích nad třiapadesáti — srovnáno.

Testů je nad slitým stavem (po #578) **5 641**, z toho **+80** z tohohle PR (pět nových sad, 78
testů, a dvě tvrzení navíc v `AutomaticReviewTests`), a jsou zelené; regrese se ověřila vložením sedmi
regresí — tří původních a čtyř po proklikání, mezi nimi i té, která do `main`u málem prošla
(vyhozené `snoozeAction:` z `BoardView`). **Copilot se na tenhle PR schválně
nepouštěl** — GitHub má výpadek entitlementu (`ineligible_app`), tatáž příčina jako u #570 a #572.
Je to **neověřená mezera**; vlastní revize diffu proběhla a je popsaná v PR.

## #509 — Dráha vlastního PR v řádku seznamu: pět teček a jedno slovo

**Tatáž smyčka jako v hlavičce (#508), zmenšená do řádku.** Vlastní PR má vpravo **pět teček**
a **pilulku se slovem k aktivní stanici** (`Push o 4 vzadu`, `CI 1 neprošel`, `Zadání 6 k předání`,
`hotovo`); **hrana řádku bere barvu z té stanice** a `Prompt →` je plné akcentové tlačítko **jen
tam, kde je co předat**. Otázka, kvůli které se u vlastního PR chodilo do prohlížeče — *a co
vlastně brání?* — je tím ve frontě, ne až v otevřené záložce. Do #509 řekl řádek jedině
`6 k předání` (#334), tedy stav **jediné** z těch pěti stanic. Cizí řádek se nemění vůbec.

**Skládá to `Policy.ownLoopRow` nad `Policy.ownLoop`, ne řádek.** Vlastní výčet stanic by
znamenal dvě odpovědi na jednu otázku: řádek by nad tímtéž PR ukázal jinou stanici než jeho
hlavička, a to se v okně nepozná jinak než pohledem na obojí naráz. Kreslí se **týmiž barvami**
jako kapsle dráhy (`LanePhaseChip.dotFill`/`dotStroke`), takže druhá kopie mapování stavu na barvu
nevznikla.

**Pohlcuje N4 z decku (*co brání mergi*) — a s ním se ruší `Policy.mergeBlocker`, který nikdy
nevznikl.** Slévatelnost dráha nezná schválně (od čtvrtého kola #508 nebere `MergeOffer` ani jako
vstup) a odpovídá na ni **pruh `K merge` na desce** (#515) a sekce *Větev* (#465). Řádek proto
říká `hotovo` (všech pět stanic je hotových), **ne `k merge`**, jak měl zákres — bylo by to druhé
tvrzení o jedné věci, složené z jiných dat.

**Dvě věci ze zákresu se nepřenesly, obojí zapsané v [`docs/architektura.md`](architektura.md):**
teček je **pět, ne sedm** (přímý důsledek čtvrtého kola #508) a **hlavička bloku
`1 k merge · 3 na tahu` nevznikla** — blok `Moje PR` z decku je na dashboardu, který #515 nahradil
pruhy, a ty ten počet nesou samy; sekce `Moje PR` v railu je `List` bez hlavičky, takže by šlo
o novou věc na obrazovce, a ta se kreslí a schvaluje dřív, než na ni vznikne issue.

**Řádek je od druhého kola zakreslený v mockupu** — v sekci **52** vedle dráhy v hlavičce, pět
stavů pod sebou (`Zadání 6 k předání`, `Push o 4 vzadu`, `CI 1 neprošel`, `hotovo` a neotevřený PR
s dutými tečkami). Leží to u dráhy, ne na stránce fronty, protože je to totéž rozhodnutí menší.
Nová třída je tam **jediná** (`.s52-dots`): řádek zůstává `.qrow`, slovo `.pill` a tlačítko
`.mini`. V poznámkách 199–204 jsou i **tři rozhodnutí proti zákresu** — pět teček místo sedmi,
`hotovo` místo `k merge` a hlavička `1 k merge · 3 na tahu`, která nevzniká.

**Cena je změřená na obou koncích** (#275, `OwnLoopRowMeasurement`), protože #508 si to výslovně
vyžádalo: tam dráha stála v hlavičce **jednoho** PR, v seznamu poběží nad **každým** řádkem.
Nejdražší vstup (`Policy.handoff`) si řádek počítá už dneska kvůli pilulce a novinkám, takže se
**předává parametrem** (`AppStore.ownLoop(for:handoff:)`). Nad 23 vlastními PR — skutečná fronta
téhle instalace — stojí průchod seznamem **0,88 ms** proti 0,53 ms před #509; naivní podoba, kde
si dráha report spočítá znovu, dala **1,39 ms**. Předání reportu tedy ušetří 60 % toho, co dráha
přidává, a je to lineární až do šedesáti PR. **Předfiltr vyšel jiný, než #508 čekalo**: ne levná
brána před drahým skládáním (`isMergeReadyForLane`), ale to drahé nepočítat podruhé.

**Zapsaná mezera: `CI` a `Review` jsou na neotevřeném PR duté tečky.** Poloha větve a slévatelnost
jsou skutečné (#572 je tahá hromadným dotazem na tik), ale checky a vyžádaní reviewery se
dotahují až s detailem záložky. Je to „nevím“, ne „nejde“, a hromadné dotažení checků do téhle
změny nepatří — byl by to další dotaz na tik za údaj, který se v řádku kreslí jako jedna tečka.

**Testů je nad slitým stavem (po #508) 5 699 v 557 sadách**, z toho **+20 ve dvou nových sadách**
z tohohle PR (`OwnLoopRowTests` maticí přes 41 600 vzorků, `OwnLoopRowRenderTests` měřením výšky
a stráží nad zdrojáky) a k tomu jedno měření, které se v běhu nepouští. Plný běh zelený (163,8 s,
jedno známé `Nedočkaná metrika zapíše nález, ne jen nulu`). **První plný běh byl přitom falešně
červený** — 77 nálezů typu `Nedočkalo se: review doběhne (strop 120 s)` pod souběžným buildem;
tytéž sady samostatně doběhly za **0,4 s** zeleně. Regrese se ověřila **vložením regrese pětkrát**;
tabulka je v [`docs/testovani.md`](testovani.md).

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu (`ineligible_app`),
tatáž příčina jako u #508, #570 a #572. Vlastní revize diffu proběhla a je popsaná v PR.
**A zákres v `docs/navrh.html` se nepřekresloval**: sekce 52 kreslí dráhu v **hlavičce**, řádek
seznamu v ní zakreslený není a nová podoba se na vlastní pěst nekreslí.

**Slito s #511 a #519 (17. 9. 2026), a slévání rozhodlo o jedné věci navíc.** Větev vyšla z mainu
ze 6. 9.; než se slila, přibyla pilulka běžícího agenta (#511) a odklad do tichých hodin (#519).
`git` na tom mlčel, ale obě změny sahaly do **téhož jediného slotu** vedle titulku. Rozhodnuto:
pořadí ve slotu je *agent → dráha → `N k předání` → odznak review*, **tečky se kreslí vždycky**.
Není to druhá odpověď z jiných dat — `agent běží · 4 min` i stanice `Push` čtou tentýž
`BranchSyncState` —, a pilulka agenta nese uplynulý čas, který dráha nemá kde vzít. Hlídá to
`OwnLoopRowRenderTests` nad pojmenovanou `PullRequestRow.showsLoopWord`; rozbor je
v [specifikaci](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--o-jediný-slot-v-řádku-se-agent-a-dráha-dělí-pořadím-ne-kompromisem-509-slito-s-511).

## #508 — Dráha smyčky vlastního PR: pět stanic v hlavičce

**Pod souřadnicemi vlastního PR stojí dráha s pěti stanicemi** — *Nálezy → Zadání → Push → CI →
Review* (návrh, sekce 52). Do #508 byla smyčka rozsekaná po místech a odpověď na „kde v tom kole
zrovna jsem“ si člověk skládal sám; teď ji vydá `Policy.ownLoop` jako jednu čistou funkci
a hlavička ji kreslí **týmiž třídami jako dráha reviewera**.

**Obsah stanic se nikam nestěhoval.** Panel *Zadání* (#334) i sekce *Větev* (#465, #466) zůstávají
tam, kde jsou; jediná akce aktivní stanice do nich **odkazuje**. Odesílat z dráhy nejde nic —
`ReviewPublishing` ani `BranchPushing` se nezměnily ani o metodu.

**Dvě rozhodnutí padla proti zákresu a obě z proklikání.** `Spustit review` se na dráze
**nenabízí**: to tlačítko stojí v hlavičce o pár bodů výš a #218 mu vyhradilo jediné akcentové
místo v pruhu — druhá kopie z hlavičky udělala semafor (vidět na screenshotu z prvního kola).
A akce dráhy je **malá** (`controlSize(.small)`), protože `font(.caption)` na `bordered` tlačítku
nezabírá: metriku si bere z control size.

**Druhé kolo z proklikání změnilo, co dráha kreslí za zastávkou.** Na
`keboola/platform-libraries#566` měl **schválený** PR se **zeleným CI** stanice `CI` i `Review`
šedé, protože se walk zastavil na `Zadání` u jediného nepředaného nálezu. Uživatelovo zadání:
*„chci zobrazit zeleně, co je hotové, abychom na první pohled viděli, co chybí.“* Stanice za
zastávkou se proto **vyhodnocují dál** a zelenají, kdykoli jsou jejich fakta **známá a aktuální**;
aktivní stanice, věta pod dráhou ani akce se nemění.

Hranici drží **jedna čistá funkce** — `Policy.ownLoopFacts(of:branch:)`, výčtem po stanicích.
`Nálezy` a `Push` nestojí na ničem (poloha větve je tvrzení o **dnešní** větvi), `Zadání` na
`Nálezech` a `CI` s `Review` na `Push`i, ale jedině tehdy, když se ví, že naše práce na GitHubu
není. Za zastávkou se kreslí `done`, nebo `idle`: **nenačtené checky ani neznámý stav
nezezelenají** a rozdělaná kapsle je vždycky jen jedna — ta aktivní.

**Třetí kolo opravilo dvě věci, které tu druhé nechalo — a obojí nahlásil uživatel na běžící
aplikaci.** Ta oprava z druhého kola `#566` totiž **nespravila**: větev je **o 21 commitů pozadu za
`main`em**, takže `Push` nebyl hotový, a `CI` s `Review` na něm stály natvrdo. Zúžilo se to podruhé
a tentokrát nad tím, co se doopravdy ví: `CI` a `Review` zhasne jedině **nepřetlačená práce
v cache** (rozhoduje `BranchSyncState`), poloha větve proti základu **ne** — hlavou na GitHubu
nehýbe, takže checky nad ní doběhly a schválení na ni platí. Druhá věc je stanice `Review`:
**schválení přebíjí visící žádost** (`#566` má schválení od `odinuv` a otevřenou žádost na
`MiroCillik`), a `chce změny` dál nezezelená nikdy. Tím padá issue #577. Poučení, kvůli kterému je
to v [záznamu rozhodnutí](superpowers/specs/2026-07-31-prism-design.md), je obecnější než oprava:
**hrubý předpoklad tvaru *stanice X stojí na stanici Y* zhasne i fakta, která s Y nesouvisí.**

**Ověření se ve třetím kole taky změnilo.** Druhé kolo stálo na sondě `OwnLoopRenderProbe`, která
kreslí view z **připravených** dat — a proto vyšlo zeleně něco, co uživateli zšedlo (pravidlo
z #478). Doklad je teď **snímek běžící aplikace** nad `#566` vedle testů nad těmi dvěma stavy.

**Čtvrté kolo ubralo dvě stanice a přidalo jim slovo.** Rozhodl to uživatel po proklikání a důvod
je věcný: `Agent` a `Merge` v okně **nikdy nic neukázaly**. `Agent` nemá živý obsah (zadání odchází
do cizího terminálu, dodat ho měla #511) a `Merge` stál na celém kole, takže byl prakticky vždycky
šedý. Ze sedmi stanic je tedy **pět** a kapsle, které mluví, dostaly víc místa. **Cesta k mergi se
nezhoršila**: merge se dál dělá ze sekce *Větev* (#465) týmž tlačítkem a týmž potvrzením a dráha na
ni ukazuje větou, jakmile kolo dojede do konce. `Policy.ownLoop` k tomu přestalo brát `MergeOffer`
jako vstup, takže odpadl i druhý průchod mapami v `AppStore.ownLoop(for:)`. **Co z toho plyne pro
#511, je zapsané, ne rozhodnuté** — buď se `Agent` vrátí i s obsahem, nebo se agent ukáže jinde.

**Druhá vada z proklikání: šedá kapsle za zastávkou byla němá.** Dráha stála na `Nálezech`, větev
byla o jednadvacet commitů pozadu a `Push` visel šedý **bez textu** — jediné místo, kde to šlo
přečíst, byla sekce *Větev*. Nehotová vyhodnocená stanice proto nese **jedno slovo** (`pozadu`,
`konflikt`, `nepřetlačeno`, `zjišťuju`, `neprošlo`, `běží`, `čeká`), rozhoduje o něm `Policy` na
jednom místě a platí to pro **každou** stanici, ne jen pro `Push`. Tři meze: **slovo, ne počet**
(číslo vedle cizí věty se čte jako tvrzení o tom, co je na tahu), **kapsle zůstává `idle`**
(rozdělaná je pořád jen jedna) a **stanice, která se nevyhodnocovala, mlčí dál** — nad
nepřetlačenou prací v cache jsou `CI` i `Review` prázdné, protože mluví o hlavě, která na GitHubu
není.

**Zákres v sekci 52 se překreslil ve stejném PR** (pět stanic, pět zastávek, slovo u šedých kapslí,
poznámky 190, 193 a 196). Regrese se ověřila **vložením regrese u každé opravy zvlášť**; tabulka je
v [`docs/testovani.md`](testovani.md).

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu
(`COPILOT_PERMISSION_GATE_REASON: ineligible_app`), takže se na tenhle PR schválně nepouštěl.
Vlastní revize diffu proběhla a je popsaná v PR.

## #510 — Agent opraví vlastní PR sám: zapisující session spuštěná cizí aktivitou (M15, zákres 55)

**Smyčka na vlastním PR se dodneška spouštěla ručně**: přišel komentář Copilota, já sestavil zadání
(#333), předal ho agentovi, počkal a pushnul. Aplikace přitom od #467 uměla pustit session, která
smí měnit soubory, a od #466 uměla větev přetlačit ze sheetu — chyběl **spouštěč**.

**Mění to tvrdou podmínku č. 2 o jednu větu**: zapisující session smí startovat **bez kliknutí**
jedině nad stromem `-sync` **vlastního** PR a jedině po **cizí** aktivitě (`foreignActivity`, #335).
**Sada povolení se nemění ani o položku** — `AgentFixCommand` ji bere doslova z `ConflictCommand`,
takže `Write` a `Edit` mají dál vypsaný rozsah, `Bash` v ní není vůbec a `gh` s `git push` zůstávají
v zákazu. Test to tvrdí literálem **i rovností** obou sad.

**#332 se neruší.** Ten zakázal automat na vlastním PR kvůli **review** — a to platí dál, reviewer se
na vlastní PR sám nepouští. Tohle je oprava po cizím review: podnětem není můj push, ale cizí hlas,
a výsledkem není nález proti kódu, který za deset minut nebude, ale **commit v kopii repa**.
Zdůvodnění i zamítnuté varianty jsou v záznamu rozhodnutí ve specifikaci.

**Čtyři brány, každá jinde a každá kontrolovatelná**: `Policy.agentFix` (vlastnictví, `autoAgent`,
stav PR, je co opravovat, běží už něco), **stav stromu `-sync`** (nad rozdělanou prací se nespouští
nic — rozhoduje o ní člověk), **denní rozpočet** (`autoRunsPerDay`, tentýž jako u automatu review)
a **druhá vrstva po běhu** (zápis mimo strom se čte ze streamu a výsledek se pak nepřijme, i když
ten pokus brána odmítla).

**Brána je globálně i per repo a ve výchozím stavu vypnutá** — právě to drží vlastnost „samo nic
nezačne“. Rozbitá hodnota v `config.json` se sráží na `false` a `Nepouštět` u repa **není** totéž
co „ber globální“, jako u odesílání.

**Commituje aplikace, ne session** (`RepoCheckout.commitAgentFix`, `git add --all` + `git commit`)
a **zprávu skládá `Policy`**: `fix: address review feedback (#N)`, anglicky a bez AI atribuce.
Hlavička commitu je jediné místo, kde by se text od modelu dostal do historie repa.

**Výsledek je stav, který panel už umí**: `rebased` s původem `.agent`, tedy mezistav *přerovnáno,
nepřetlačeno* z #466 — odtud vede `Force push…` se sheetem, lease z hlavy, ze které agent vyšel, a
bez výchozí akce. **Z #466 se nemění nic.** Vedle toho jsou dva nové stavy: `fixedNothing` (doběhlo,
v cache nic neleží, `Zahodit` se nenabízí) a `fixRejected` (výsledek se nepřijal, nabízí se
`Zahodit změny` i terminál).

**Razítko spuštění je třetí vedle návštěvy a oznámení** (`AgentFixLedger`) a posouvá se **při
startu**: kdyby se posouvalo po úspěchu, pouštěl by se neúspěšný běh při každém tiku. Podnět, který
přijde za běhu, se tím nezahodí — má novější datum, takže ho příští tik uvidí znovu, a to je celé
„zařadí se do fronty“. Při **prvním** setkání s PR se razítko jen zasadí, takže na starou diskuzi
agent nesáhne.

**Na dráhu vlastního PR (#508) se nic nevěsí** a notifikace v tomhle issue nejsou — dráha má od
6. 9. 2026 pět stanic a kde se běžící agent ukáže, rozhoduje #511. **Zapsaná mezera: testy nepouští
nikdo** — session je pustit nemůže (`Bash` v sadě není) a aplikace to zatím nedělá, takže je
v promptu věta, že se nesmí tvrdit, že bylo něco ověřeno spuštěním.

**Brána patří i do očisty slotu** (`bin/slot-config.sh`): má obě úrovně, takže zděděné `true` by
z dev instance pustilo agenta na moje skutečné PR — vyčistí se globálně i u rep a kontrola nad
výsledkem to hlásí jmenovitě, jako u odesílání a automatu.

**Zákres je sekce 55** v `docs/navrh.html` (bez nových CSS tříd — kreslí se tímtéž, čím sekce 36
a 48). `docs/navrh.md` sedělo na 53 sekcích nad čtyřiapadesáti — srovnáno.

**Z renderu sondy vypadly dvě opravy, které z diffu vidět nebyly**: pod větou „Agent upravil
2 soubory“ stálo `Zahodit rebase` (žádný rebase tam neproběhl) a řádek o tom, co agent zrovna dělá,
se nekreslil vůbec, protože podmínka ve view zněla `isResolving`. Obojí má teď tvrzení.

**Slití s #508 chtělo tři arms navíc, ne jen tichý `git`.** Dráha vlastního PR čte
`BranchSyncState` dvěma vyčerpávajícími `switch`i, takže tři nové stavy položily překlad — což je
přesně to, k čemu ty vyjmenované `case`y v `OwnLoopPolicy` jsou. Rozhodlo se: běžící agent je
`probíhá`, **nepřijatý** výsledek dostal vlastní slovo `nepřijato` (`rebase` by pojmenovalo něco,
co ve stromě neleží) a `fixedNothing` o poloze větve nerozhoduje vůbec, tedy jako `alreadyInSync`.
Totéž v `ownLoopFacts`: běžící agent i nepřijatá práce drží `CI` a `Review` šedé.

Testů je nad slitým stavem (po #508) **5 711** v 556 sadách, z toho **+33** z tohohle PR (dvě nové
sady a sedm tvrzení navíc ve stráži `SingleWayOutTests`, `SessionToolSetsTests`
a `BranchSyncOfferTests`; tři stavy navíc ve výčtech `OwnLoopTests` přišly až se slitím), a jsou
zelené; regrese se ověřila **vložením čtyř regresí** — vypnutá brána, vypnutá kontrola vlastnictví,
přijatý zápis mimo strom a vlastní komentář počítaný za cizí. Ta druhá je poučná: store test u ní
**prošel**, protože cizí PR zastaví už rozhlídka — guard hlídá `AgentFixPolicyTests`. Plný běh nad
slitým stavem byl **falešně červený pod souběžným buildem druhého slotu** (deset issues ve třech
sadách o čekání — `HealthMonitorTests`, notifikace a routing, nic z toho se tohohle PR netýká);
samostatný běh těch tří sad je zelený (29 testů).

**Tři neověřené mezery.** (1) **Copilot se na tenhle PR schválně nepouštěl** — GitHub má výpadek
entitlementu (`ineligible_app`), tatáž příčina jako u #508, #512, #570 a #572; vlastní revize diffu
proběhla a je popsaná v PR. (2) **Že session doopravdy opraví, co po ní zpětná vazba chce, se
v harnessu netvrdí** — je za tím cizí model, síť a peníze; testuje se spouštěč, brána, sada
povolení a přijetí výsledku, ne kvalita opravy. (3) **Testy nad výsledkem agenta nepouští nikdo** —
deck mluvil o „testy zelené (spustila aplikace)“, session je pustit nemůže (`Bash` v sadě není)
a aplikace to zatím nedělá; v promptu je proto věta, že se **nesmí tvrdit**, že bylo něco ověřeno
spuštěním.

## #511 — Běžící agent je vidět, a když doběhne, dá se to poznat (M15, zákres 56)

**První krok bylo rozhodnutí, ne kód.** Zadání stálo na větě „stanice *Agent* na dráze (#508)
ukazuje stav“ — jenže ta stanice z dráhy odešla přesně proto, že **neměla živý obsah**. Vybíralo se
mezi „vrátit ji, ale rovnou s obsahem“ a „ukázat agenta tam, kde ta práce je“. Rozhodlo se pro
druhé: do kapsle na dráze se vejde **jedno slovo**, kdežto obsah, který #511 dodává, je čtyřřádkový
ocas, věta o výsledku a tři tlačítka. Dráha zůstává **pětistanicová** a o agentovi nemlčí — stanice
`Push` hlásí `probíhá` i `nepřetlačeno` (#510), protože commit v kopii repa patří do jejího obsahu.
Zbytek bydlí v sekci `Větev`, tam, kde je ten strom a ta další akce.

**Co přibylo.** Živý ocas posledních čtyř kroků pod větou o stavu (kroky ze streamu, ne próza
modelu — tu aplikace nedrží). Věta výsledku z výčtu `AgentRunOutcome`, skládaná na **jednom místě**,
protože o témž výsledku mluví panel, banner i řádek v `Dění`: *Agent upravil 2 soubory ve stromě
499-sync · nic se neodeslalo.* Tlačítko **`Prohlédnout diff agenta`** — do téhle změny se ten commit
dal přečíst jedině **za nevratnou akcí**, tedy potvrdit force push a podívat se na GitHubu; teď se
čte `git` v kopii repa a kreslí to tatáž obrazovka jako diff commitu (#317). Notifikace s vlastním
přepínačem a řádek v `Dění`, který vzniká i bez banneru. A pilulka `agent běží · 4 min` /
`push čeká na tebe` v řádku `Moje PR` — ve stejném jediném slotu, kde jindy stojí `N k předání`.

**Výčet má pět případů, ne čtyři ze zadání.** Chybějící pátý je `nothing` a je to stav, který #510
výslovně oddělilo od selhání (doběhlá práce, po které v cache nic neleží). Slít ho do `failed` by to
rozhodnutí zrušilo, slít do `partial` by tvrdilo, že část opravy leží v kopii repa, přestože `git`
řekl, že se nezměnilo nic.

**Zadání chtělo větu „testy zelené“ — nedodala se, a je to podmínka.** Session testy pustit nemůže
(`Bash` v její sadě není) a aplikace je nad jejím výsledkem nepouští. V žádné z pěti vět, v žádném
titulku banneru ani v žádném dalším kroku se proto o testech nemluví, a **hlídá to test**, ne
komentář. Pustit testy nad výsledkem agenta by bylo vlastní issue.

**Vlastní revize diffu našla dvě věci.** `AgentRunOutcome` nesl dvě vlastnosti (`files`,
`awaitsPush`), které četly **jenom testy** — držený stav, který nikdo nečte, je jeden z pěti vzorů,
co Copilot v tomhle repu nachází; obojí odešlo. A `loadAgentDiff` neuměl to, co `loadCommitDiff`
umí: **přeskládat výskyty hledání** po dotažení diffu (#152), takže by `⌘F` nad diffem agenta
hlásilo nula výskytů nad textem, ve kterém jsou.

**Jedna mapa místo dvou.** `branchSyncActivity` (jeden řetězec) se stal `branchSyncTail` (pole).
Slévání konfliktů si z něj bere poslední prvek a kreslí se jako do #511; druhá mapa vedle by o téže
věci uměla tvrdit dvojí.

Testů je **5 750** v 559 sadách, z toho **+39** z tohohle PR (tři nové sady, dvě tvrzení navíc v `SettingsFieldsRenderTests`, pět tvrzení navíc
v `AppStoreAgentFixTests`, dvě přepsaná v `ActivityFeedTests` a dvě scény sondy). Plný běh je
zelený; regrese se ověřila **vložením tří regresí** — věta s „testy zelené“ (spadly tři testy ve
dvou sadách), hlášení o agentovi puštěné i na cizí PR (spadl `AgentRunNoticeTests`) a smazaný
přepínač ze stránky `Notifikace` (dvě stejně velké, ale různé bitmapy).

**Grepy tvrdé podmínky č. 1 vydávají po slití s `main`em týž výčet jako po #510**: sedm souborů
u `ReviewPublishing`, tři u `BranchPushing`, tři u `AgentFixing`. Sady nástrojů se nezměnily ani
o položku — `Prohlédnout diff agenta` je čtení `gitu`, ne session.

**Tři neověřené mezery.** (1) **Copilot se na tenhle PR schválně nepouštěl** — uživatel to zakázal,
GitHub má výpadek entitlementu (`ineligible_app`); vlastní revize diffu proběhla a je popsaná v PR.
(2) **Ocas za běhu netvrdí žádný store test**: krok se do něj zapisuje z odpovědi streamu přes
`Task { @MainActor }`, takže po usazení je běh dávno hotový a ocas prázdný. Co se dá tvrdit, se
tvrdí — strop a skládání v `Policy`, kresba čtyř řádků v sondě a to negativní, že po doběhnutí ocas
**nezůstane**. (3) **Že ve slotu doopravdy naběhne agent, se neověřilo** — brána je ve výchozím
stavu vypnutá a `slot-config.sh` ji z kopie konfigurace vyndává, takže se stavy panelu ověřily
renderem sondy a čtením konfigurace, ne živým během.

## #519 — velké PR se v automatu odloží do tichých hodin (M16)

Třetí a poslední issue skupiny automatu (#517, #518, #519). Do #519 se PR o dvou tisících řádcích
pouštěl ve tři odpoledne, když na něj někdo čekal, a bral slot menším.

**Automat teď PR nad prahem (výchozí 1 500 změněných řádků) odloží na nejbližší začátek tichých
hodin** (výchozí `22:00`–`6:00`, obojí v nastavení, stránka `Review a skilly`, sekce `Tiché
hodiny`). Rozhoduje `Policy.deferToQuietHours(pr:isOpen:now:rules:calendar:)` — čistá funkce
s předaným časem i kalendářem, takže se dá projít výčtem; hodiny ani zóna se uvnitř nečtou.

**Práh se bere z hlavičky PR** (`additions + deletions`), ne z diffu: nad 300 souborů vrací GitHub
406 (#542), takže by se velikost nedala změřit zrovna u toho PR, kvůli kterému práh existuje.
`PullRequest.changedLines` je proto nové pole a přibylo **do obou** cest, kterými detail přichází —
`gh pr view` i dávkový GraphQL dotaz —, jinak by se odklad rozhodoval jinak po startu a jinak po
otevření záložky. Chybějící číslo je `nil`, tedy „nevím“, a z toho vyjde `pusť to teď`.

**Odklad platí jen na automat a limit neobchází.** Ruční `Spustit review` ho nezná, PR, který mám
otevřený, se **neodkládá**, a denní limit i strop útraty se strhávají v `canSpendSession` stejně
jako ve dne — odklad mění **kdy**, ne **kolik**. `Pustit teď` v dráze je ruční běh, takže si
o rozpočet nesáhne, a pouští **celé** review: odklad padl na celý běh, ne na jednoho revieweera.

**Odložené běhy se zapisují do cache** (`deferred.json`, lhůta 7 dní) a čtou se před prvním tikem.
Bez toho by noc bez běžící aplikace nepustila nic a ráno by to vypadalo, že automat nefunguje —
a restart je v tomhle repu po každém mergi. **Zmeškaná noc se pouští ráno, ne odkládá na další**:
vyzvednutý odklad jde do `review` s `honoringQuietHours: false`, jinak by ho druhá brána poslala do
dalšího odkladu donekonečna. Osiřelý zápis (po PR, které se zavřelo) **vystřelit nemůže** —
`Policy.deferralsToRelease` bere seznam z tiku, ne obsah souboru — a uklidí ho lhůta.

**V tabu `Průběh` je to pátý stav dráhy** (`odloženo na noc`, jedna fáze `čeká na tiché hodiny`,
věta `2 790 řádků nad prahem 1 500 · nikdo na PR nečeká`, vpravo `poběží 23:00` a pod tím
`Pustit teď`). Nesmí se slít ani s `nespuštěno`, ani s `přeskočeno` (#518), ani s `ve frontě`: tenhle
jediný má běh **naplánovaný**. `0,00 $` u něj není — u odkladu to není konečná cena, jen ještě
nezaplacená. Zákres je sekce 46, kterou přenesla #517.

**Čas je past a řeší se třemi věcmi**: okno `22:00–6:00` **přechází přes půlnoc** (naivní
`hour >= 22 && hour < 6` je vždycky nepravda, takže by se v noci nepustilo nic), den má na přechodu
letního času **23 nebo 25 hodin** (proto `Calendar.nextDate`, ne `+86 400` — změřeno: 88 200 s
místo 84 600) a hodina, na kterou se míří, ten den **existovat nemusí** (jarní posun přeskočí
2:00–3:00). Nesmyslné okno odklad **vypne**, nezastaví review; `22`–`22` je prázdné okno, ne ticho
pořád. Podrobnosti jsou v [`docs/architektura.md`](architektura.md), měření
v [`docs/testovani.md`](testovani.md).

**Jedna věta ze zadání se implementovala jen z poloviny, a je to zapsané rozhodnutí.** Zadání má
bod „otevření PR ruší odklad“; otevřený PR se opravdu **neodkládá**, ale odklad, který už padl,
otevření záložky **nespustí**. Důvod je zákres: dráha `odloženo na noc` se kreslí jedině v otevřené
záložce, takže by pod původním pravidlem `poběží 23:00` ani `Pustit teď` nešly vidět — změřeno na
běžící aplikaci, odklad zmizel dřív, než se dráha vykreslila. Cesta ven je `Pustit teď`, a je to
navíc **ruční** běh, takže nesáhne na denní rozpočet.

**Vlastní revize diffu našla tichou díru**: vyzvednutí odloženého běhu bralo holý seznam z tiku,
takže PR, který jsem si **odložil** (#512), by se ve dvacet dva večer sám zreviewoval. Vyzvednutí
teď prochází tutéž dvojici zúžení jako plánovač (jen cizí, bez odložených).

Přibylo 40 testů ve třech sadách a dva rendery nastavení; regrese se ověřila **vložením regrese
u osmi věcí zvlášť**,
včetně kontrolního měření (malé PR toutéž cestou projde), bez kterého by sada nerozlišila funkční
odklad od vypnutého automatu.

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu
(`COPILOT_PERMISSION_GATE_REASON: ineligible_app`), takže se na tenhle PR na pokyn uživatele
nepouštěl. Vlastní revize diffu proběhla a je popsaná v PR.

## #516 — brief na domově: tři pojmenované věty ze stavu aplikace (M16, zákres 58)

Nad pruhy desky je **blok s až třemi pojmenovanými větami** — `Přibylo`, `Hoří`, `První na řadě` —,
které složila session Claude Code **bez jediného nástroje**. Dostane hotový text
z `Policy.briefInput` — počty z pruhů, řádky viditelných pruhů (repo, číslo, titulek, autor, stav
review, kolik z nálezů blokuje, stáří), počet odložených a blok `Dění` — a jenom ho
**přeformuluje**. Pod větami stojí `shrnuto 21:48 · 0,09 $ · ze stavu aplikace, ne z kódu`
a tlačítko `Shrň znovu`.

**Přibyla tím šestá session do tabulky v tvrdé podmínce č. 2, a je to druhá s prázdnou sadou**
(po překladu nálezů). `--disallowedTools` je tatáž konstanta jako u ostatních pěti a
`SessionToolSetsTests` tvrdí obojí literálem — od #516 je v tom výčtu **i překlad nálezů**, o kterém
se do té doby netvrdilo nic. **Není to review logika, je to čtení nahlas**: brief z kódu (session
s `Read` nad repozitáři) by review logika byl a ta patří do skillu, ne do aplikace.

**Vypnuto ve výchozím stavu**, a blok se pak nekreslí vůbec — ne zašedle. V nastavení jsou tři
volby (`Vypnuto` / `Na požádání` / `Při prvním tiku dne`), protože se rozhodují dvě věci: jestli se
brief skládá vůbec a jestli ho smí spustit **aplikace sama**. Ta poslední volba je vedle agenta
z #510 jediná cesta, kterou v téhle aplikaci startuje session bez kliknutí — a **dnešek se posuzuje
z uloženého briefu** (`brief.json` v cache), protože pojistka, kterou obejde restart, není pojistka.

**Cena každého briefu jde do `SpendLedger` a je vidět na jeho řádku**, i u běhu, který text
nevrátil — `nil` cena se píše jako `cenu nenahlásilo`, ne `0,00 $`. **Spadlá session nekončí
prázdnem**: blok řekne `Shrnutí se nepovedlo.`, pod tím důvod a nabídne `Zkusit znovu`. Prázdný
rámeček by byl k nerozeznání od vypnutého briefu, který se nekreslí.

**Pozdrav zůstává nad briefem**, na rozdíl od toho, co si #515 poznamenalo: pozdrav a věta o pruzích
mluví z dat, která aplikace má jistě, kdežto brief je text od modelu a smí se nepovést.

**Denní rozpočet `autoRunsPerDay` se nečerpá, a je to zapsané rozhodnutí** — je to pojistka proti
řadě patnáctiminutových review a agentů, kdežto brief je jeden odstavec bez nástrojů nejvýš jednou
za den. Účet přesto nikde nemlčí.

Zákres přenesla tahle issue do **sekce 58** (#515 v sekci 45 nechalo poznámku, že brief přijde
s #516); sekce 45 se nepřekresluje, blok visí pod pozdravem a nad pruhy.

### Co změnilo první proklikání

**Odstavec se rozpadl na tři pojmenované věty.** Souvislá próza na čtyři řádky se musela přečíst
celá, aby z ní vypadla jedna věc — a tím se rušil celý smysl briefu, totiž být **levnější než
přečíst čtyři bloky pod ním**. Odpověď session je od té doby **protokol** (`ADDED:` / `BURNING:` /
`NEXT:`), ne volný text, a blok ji kreslí jako sloupec návěští a sloupec vět. **Otázka, na kterou
ve vstupu odpověď není, mlčí** — struktura, jež si vynutí větu na každou otázku, si o vymyšlenou
větu říká.

**Cena se změřila a vyšla patnáctkrát vyšší, než stálo v hlášení: $0,46 za jeden brief**, tedy
~14 $ měsíčně při `Při prvním tiku dne`. Měření ukázalo, že **náš vstup je ~2 % účtu** a zbytek je
boot session zapsaná do hodinové cache, kterou brief nikdy nepoužije. Strop na velikost vstupu by
tedy neušetřil nic a **zamítl se**; místo toho brief jako **jediná session vynucuje model**
(`haiku`) a přidal `--strict-mcp-config`. **Změřeno ~$0,09 místo ~$0,46**, tj. ~2,50 $ místo ~14 $
měsíčně. Limit se zvedl na tři minuty, protože haiku běží ~60 s. Ta částka je teď vidět
**v nastavení u přepínače**, ne až na účtu.

**Nejednoznačný vstup je vada vstupu, ne promptu.** `blokuje 2` model přečetl jako počet
*reviewerů*; jsou to blokující nálezy. Opraveno na `z toho 2 blokující` a drží to test v obou
směrech.

**Třetí kolo po proklikání: čísla ve větách otevírají záložku.** Klikatelné je **jen číslo**
(`#727`), otevírá `AppStore.openPullRequest` — tedy **tatáž cesta** jako `prism://`, `Odkaz`
v paletě ⌘K a klik ve frontě, ne druhá. **Uzavřeným seznamem cílů je to, co do briefu doopravdy
šlo**: `Policy.briefInput` vrací od téhle změny `BriefMaterial` (text **a** seznam pull requestů,
jednou procházkou přes tytéž pruhy), seznam se ukládá v `Brief.mentioned` a v textu se jen hledá,
**kde** na ně ukazuje. Rozpoznávat `#\d+` z odpovědi by nestačilo ze dvou důvodů: model umí napsat
číslo, které na desce není, a **samo číslo cíl neurčuje** — v briefu stojí čísla z víc repozitářů.
Rozhoduje `Policy.briefSpans`: jméno repa před číslem vybírá cíl a **cizí jméno je odmítnutí, ne
nejbližší podobný**; bez jména rozhoduje **jednoznačnost**. Co se složit nedá, zůstane prostým
textem — žádné mrtvé tlačítko a žádná hláška. Čtení uloženého briefu je **tolerantní**, aby brief
bez seznamu nepřišel o razítko dnešního běhu.

Testů je v šesti sadách **69**; regrese se ověřila **vložením regrese u osmi věcí zvlášť** —
u čtyř z prvního kola, u vynuceného modelu a dvojtečky za klíčem návěští z druhého a nově
u jednoznačnosti cíle odkazu a u tolerantního čtení `mentioned`.

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu, takže se na pokyn
uživatele nepouštěl. Vlastní revize diffu proběhla a je popsaná v PR.

**Neověřená mezera: že klik doopravdy otevře záložku, ověřuje člověk.** Harness tvrdí, které číslo
se odkazem stane a na co ukazuje, ale `AttributedString` s `.link` a `OpenURLAction` se projeví až
v běžícím okně. Kdyby se odchycení nepovedlo, odkaz by se otevřel **v prohlížeči** místo v záložce
— tedy nic rozbitého, jen něco jiného, což zelený běh nechytí.

**Neověřená mezera: kvalita textu z haiku se posoudila na jednom vstupu.** Měřilo se nad jedním
realistickým stavem desky (čtyři pruhy, 13 PR); že haiku obstojí i nad prázdnou nebo naopak hodně
zaplněnou deskou, se nezkoušelo — každý běh stojí peníze uživatele.

**Neověřená mezera: `~$0,09` je dopočet, ne přímé měření studeného běhu.** Vychází z naměřeného
poměru tokenů a ceníku `haiku`; celý studený běh s prázdnou hodinovou cache se za tu cenu
**nezměřil**. Změřený je poměr *97 % boot / ~2 % vstup*, a právě ten rozhoduje o tom, že jediná
páka je model, ne délka vstupu.

**Neověřená mezera: blok s jedním či dvěma řádky odpovědi se v okně neproklikal.** Drží to test
parseru (`BriefCommandTests`), takže se to nerozpadne potichu — ale jak taková kratší odpověď
vypadá nad deskou, viděl harness, ne člověk.

## #523 — druhé kolo: karta, notifikace a předepsané schválení (M17, Z3a, zákres 60)

Druhá issue skupiny „Za mě“ a **kresba nad daty z #522**. V `Přehledu` cizího PR stojí nad pruhem
*Od tvé poslední návštěvy* karta **Odpověď na tvoje review z 29. 8.**: řádek na každý můj odeslaný
komentář (`✓ opraveno v 9c1de02` / `↩ odpověděl sykora-ji: „…“` / `○ bez odpovědi · řádek beze
změny`), pruh `návrh: Komentář · 1 bez odpovědi` a dvě tlačítka. Když nic nezbývá, je návrh
*Schválit*, tělo je předepsané (*„Díky, všech 5 opraveno.“*) a klik otevře **týž sheet jako dnes**.

**Schválení je návrh, ne akce.** Tlačítko zapíše verdikt a tělo do `ReviewDraft` — tedy do souboru
v cache — a otevře potvrzení toutéž cestou jako `Odeslat` v panelu. Tvrdá podmínka č. 1 se nemění
ani o metodu: grepy dál vydají **sedm** souborů u `ReviewPublishing` a **tři** u `BranchPushing`,
`ReviewVerdict` zůstává návrh z nálezů. Návrh druhého kola je proto **vlastní typ**, kde
`Komentář` je plnohodnotná odpověď („neschvaluju, protože něco zbývá“).

**Tři rozhodnutí, která v zadání nebyla.** (1) **Přes nezodpovězený bod se nepředepisuje ani
věta** — tlačítko se jmenuje `Schválit i tak` a tělo zůstane prázdné: poděkovat za bod, který
zbyl, znamená položit člověku do úst nepravdu. (2) **Useknutá stránka vláken bere schválení taky**,
i když nezodpovězený bod není — o části PR se neví nic; tentýž směr opatrnosti jako u zahozeného
nálezu. (3) **Chybějící data se přiznají** třemi různými větami (useknutá stránka, kontrola
neběžela, kontrola nedoběhla), protože každá se spravuje jinde.

**Změna proti zákresu: dvě karty nad sebou, ne jedna.** Z3 kreslil druhé kolo jako *podobu* pruhu
`.since`. Slít je doopravdy by sundalo odrážku o přepsané historii, odznak `nálezy zastaraly`
i obě tlačítka toho pruhu — a po pushi autora platí nejvíc. Karta druhého kola je proto
**akcentová** (`--stale` znamená „platilo to, dneska už ne“, tahle „je co udělat“) a stojí nad
pruhem; tak je i zakreslená v sekci 60. Zapsané v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#záznam-rozhodnutí--karta-druhého-kola-stojí-vedle-pruhu-od-minule-523).

**Hláška jde toutéž branou jako ostatní** (#414): banner *„sykora-ji opravil 3 z 5“* + *„1 bez
odpovědi“* a řádek v `Dění` (`replyRound`, vede na `Přehled`). Nehlásí se **na vlastním PR**, **bez
mého vlákna** a **když se nepohnulo nic**. Přepínač je **sedmý a vlastní** (`Autor odpověděl na
moje review`) s vlastní `replacementGroup` — že autor opravil tři body, nemá přebít výsledek
našeho revieweera.

**Zákres do `docs/navrh.html` je sekce 60** (číslo přidělil orchestrátor v dávce) — tedy Z3a, které
#522 schválně nekreslilo. Artifact se z tohohle PR **nepublikoval**, publikuje se ze slitého stavu
po mergi (#537).

Přibylo 30 testů ve třech sadách; regrese se ověřila **vložením regrese dvakrát** — u návrhu
verdiktu (padne šest z devíti buněk mřížky a k tomu dva pojmenované testy) a u brány na vlastní PR
(padne v `Policy` i ve storu).

**Ověřeno snímkem běžící aplikace** ve slotu `a`, položeným vedle renderu sekce 60 headless
Chromem. Stav se musel **vyrobit**: ve slotu není cizí PR, na kterém bych měl odeslaná vlákna,
takže `replyCard(for:)` dočasně vracela předepsanou kartu z proměnné prostředí (do commitu se to
nedostalo). **Z toho neplyne nic o párování** — jen to, jak se karta kreslí. Našlo to přitom
chybu, kterou testy nevidí: `Text("… \(Text(…))")` vybere `Text(String)`, takže se do razítka
vysázelo `Text(storage: SwiftUI…)`.

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu, takže se na pokyn
uživatele nepouštěl. Vlastní revize diffu proběhla a je popsaná v PR.

## #522 — druhé kolo: kontrola z #150 páruje moje odeslané komentáře (M17, Z3)

První issue skupiny „Za mě“ (#522, #523). Do #522 kontrola z #150 řekla, které **nálezy revieweera**
po pushi autora trvají — a o **mých odeslaných komentářích**, tedy o tom, co v druhém kole čtu
znovu, neřekla nic. Teď dostane k nálezům druhý seznam (soubor, řádek, text, identita vlákna)
a za každý komentář vydá jeden ze stavů *opraveno v `<sha>`* / *odpovězeno* / *bez odpovědi*.

**Je to tatáž session, ne nová.** Tentýž prompt, tatáž sada nástrojů (tvrdá podmínka č. 2 se
nezměnila ani o položku — `SessionToolSetsTests` tvrdí týž literál), **jedno pole odpovědí**:
nálezy `0…n−1`, komentáře od `RecheckMaterial.commentIDOffset`. Páruje se přes index, ne přes text
(#150) — text se mezi koly mění.

**Hranice, kterou model nesmí přejít, se drží dvakrát.** *Odpovězeno* je fakt z konverzace (#72),
ne verdikt: na zodpovězené vlákno se session **vůbec nezeptá**, a prompt to navíc říká výslovně
(`Do not judge whether anyone replied to a comment`). Kdyby se jen filtrovalo v zobrazení, ležel by
v úložišti verdikt, který se nikdy nemá ukázat — a platilo by se za něj.

**Dvě rozhodnutí, která v zadání nebyla.** (1) Když je vlákno zodpovězené **a** model řekl
„opraveno“, vyhraje *odpovězeno*: fakt přebíjí tvrzení, a opačné pořadí by schovalo větu kolegy,
kterou si mám přečíst. (2) `bez odpovědi` nese **tři** důvody (`beze změny` / `nejde říct` /
`nikdo se neptal`), protože slít je do jednoho je tatáž chyba jako slít `čisté` a `failed`.

**Tvrdá podmínka č. 5 se nemusela nijak ohýbat, a je to zapsané.** Verdikty o vláknech leží
v `StoredRecheck.replyStatuses`, tedy v témže uloženém běhu jako verdikty o nálezech — ten už je
klíčovaný `(PR, headSha)` a nese `againstHeadSha`. **Report se neukládá vůbec**: skládá se při
čtení z uložené kontroly a ze živé konverzace. Posun hlavy proto zhasne **jen osu modelu**,
odpovědi platí dál — a právě tím se `ReviewReplyReport` liší od `RecheckReport`, který zhasne celý.

**Na tomhle není v aplikaci co vidět** — kreslí #523. Jediná viditelná drobnost je věta v nápovědě
u tlačítka `Zkontrolovat nálezy`: říká, kolik komentářů se veze v téže session, protože session
stojí peníze a nápověda nesmí o délce promptu tvrdit míň, než co se doopravdy pošle.

**Vlastní revize diffu našla jednu chybějící kontrolu**: useknutá stránka vláken (`hasNextPage`)
nebyla v reportu vidět, takže by `2 opravené ze 3` platilo o třech vláknech, která dorazila,
a mlčelo o těch, která ne. Report ji teď nese — a **přes všechna vlákna PR, ne jen moje**: kolik
z chybějících je mých, se z odpovědi zjistit nedá.

Přibylo 37 testů v pěti sadách; regrese se ověřila **vložením regrese u pěti věcí zvlášť** —
autor vlákna podle prvního komentáře, přednost dat před modelem, ověření hlavy, posun indexu
a `decodeIfPresent` u nového pole (bez něj se přestane číst **celý** záznam, tedy i nálezy).

**Zákres do `docs/navrh.html` (sekce Z3a) patří k #523, ne sem** — tak to v dávce rozhodl
orchestrátor. Na #522 není co kreslit (vznikají data a testy), takže zákres vzniká tam, kde vzniká
i kresba: v #523, které si k tomu vyžádá číslo sekce. Není to tedy dluh tohohle PR, je to **zadání
pro #523**.

**Neověřená mezera: PR neprošel Copilotem.** GitHub má výpadek entitlementu
(`ineligible_app`), takže se na pokyn uživatele nepouštěl. Vlastní revize diffu proběhla a je
popsaná v PR.

## #513 — Série PR: fronta drží stohované pull requesty pohromadě (zákres 57)

**PR, jehož base větev je hlavou jiného otevřeného PR v tomtéž repozitáři, je v sérii.** Fronta ho
drží u ostatních členů v pořadí, v jakém se budou mergovat, řádek nese pilulku `1. v sérii` /
`2. · stojí na #14451` a přerušovanou čáru na kraji, nad skupinou stojí popisek
`série · AJDA-563 · 2 PR · review v pořadí ↓`. Hlavička PR ukazuje řetěz
`větev [3. v sérii] → větev [#14451] → trunk` a pod souřadnicemi větu *Diff je jen tahle vrstva:
4 soubory nad #14451. Až se #14451 mergne, GitHub přepne základ na trunk a řetěz zmizí sám.*
**Nic se nepíše** — je to čtení a čisté funkce nad daty.

**Věta ze zadání neplatila a opravila se.** Issue slibovalo „jedno porovnání nad hlavičkami, které
polling dotahuje“; `gh search prs` ale větve **nevrací vůbec** (ověřeno na CLI, seznam polí je
v [`docs/testovani.md`](testovani.md)), takže je `PullRequestSummary` nemá ani jako pole a cizí PR
ve frontě načtený detail nemají. Kreslený scénář je přitom právě **cizí** série, takže by série nad
dnešními daty nevznikla nikdy. Rozhodnutí (17. 9. 2026): **rozšířit dávkový dotaz na hlavy** (#420)
o `headRefName`, `baseRefName` a `isCrossRepository` a pustit ho přes frontu. Zamítnuta byla
levnější varianta „série jen u PR s načteným detailem“ — levné, ale kreslený scénář by nefungoval.
**Rozsah tím vyrostl z S na M** a je to vědomé.

**Nepřibývá volání ani bod.** Tři pole leží na témže uzlu téhož dotazu; změřeno na živém API, že
dvacet aliasů s větvemi stojí pořád **1 bod z 5000/h** (dokument roste o ~42 B na alias, odpověď
o ~100 B na PR). Dvě rozhlídky — zastaralé nálezy (#420) a větve (#513) — slévá
`Policy.headProbe(stale:refs:)` do **jednoho** seznamu, takže je z nich **jeden** dotaz: na klidný
tik nula, na pohnutý jeden. Čísla i tabulka dotazů na fake gateway jsou
v [`docs/testovani.md`](testovani.md).

**Ve čtyřech stavech se netvrdí nic**: hlava z forku, chybějící `isCrossRepository` (`nil` je zákaz,
ne povolení), dvě otevřená PR na téže větvi a nedotažené větve. Napříč repozitáři se větve nepárují
a mergnutý ani zavřený PR skupinu nedrží — **série tak zaniká sama** tím, že GitHub po mergi
spodního přepne base horního na `main`.

**Tři rozhodnutí, která zadání nechalo otevřená** (podrobně ve specifikaci): popisek a čára se
kreslí **jen ve frontě** (na desce a v sekci `Rozdělaná` zůstává pilulka, protože tam skupina
pohromadě nedrží); popisek se kreslí **uvnitř řádku** svého prvního člena, takže identita řádků
v líném seznamu zůstává `PRIdentifier` (#361); a **odložený člen** ze skupiny prostě vypadne —
pilulka u zbylého zůstane (je to pravda o PR), popisek zmizí, protože `2 PR` nad jedním řádkem
tvrdí víc, než je vidět.

**Po prvním proklikání se opravil řetěz v hlavičce.** Nesl pilulku `#14451 · 2. v sérii`, kdežto
řádek téhož PR ve frontě `3. · stojí na #14451` — obojí pravda (hlavička mluvila o base větvi, řádek
o otevřeném PR), ale vedle sebe to byly dvě odpovědi na jednu otázku a **pořadí otevřeného PR
z detailu nešlo přečíst vůbec**. Čísla se rozdělila podle toho, **u čí větve stojí**: u hlavy
`3. v sérii` (jediné pořadí v řetězu), u base větve pouhý odkaz `#14451`, pořadí toho spodního jen
v nápovědě u jeho čísla. Pilulku dostal i **základ série**. Řetěz od té doby skládá
`Policy.branchChain(head:base:series:)` a ne kresba, takže se nad tím dá tvrdit test: v pilulkách
řetězu je **právě jedno** pořadové číslo, patří hlavě a rovná se tomu, které o témž PR říká řádek
fronty (5 případů, pozice 2 až 6). Zamítnuto bylo odlišit obě čísla barvou (rozdíl je ve významu, ne
v důrazu) i psát `3. ze 3` (česká předložka se podle číslovky mění — `ze tří`, ale `z pěti`), takže
počet nese popisek nad skupinou a nápovědy.

Přibylo 74 testů ve čtyřech nových sadách (45 nad `Policy.series` a jejími větami, 10 nad
předfiltrem, 11 nad tikem, 5 měřených nad kresbou řádku) a tři nad rozšířeným dotazem, k tomu
jedna fixtura ze živého API (skutečná série `cli/cli`
#14451–#14453); regrese se ověřila **vložením regrese u čtyř věcí zvlášť**.

**Neověřená mezera: PR neprošel Copilotem** (výpadek entitlementu, na pokyn uživatele se nepouštěl)
a **popisek nad skupinou ve frontě je doložený jedině rendrem mockupu a testy** — na běžícím okně
se dá vyfotit pruh desky, ale přepnutí railu na sekci `Fronta` vyžaduje kliknutí, na které tenhle
stroj nemá asistenční přístup.

## #514 — Reviewery · 30 dní: co se z čího hlášení odmítá (M16, zákres 61)

Blok `Reviewery · 30 dní` v pravém sloupci domova a tabulka `Jak si reviewery vedou` v Nastavení ›
`Review a skilly`. Za každou dvojici **reviewer × repo** pruh *převzato / neplatí / nepatří sem /
nerozhodnuto* a věta, když odmítnutí přesáhnou polovinu — `9 z 14 neplatí → skill`,
`5 z 11 nepatří sem → pravidla repa`. Data existovala od #113 (důvod u každého odmítnutého nálezu),
jen se nikde nesčítala.

**Blok stojí na místě, kde byly `Nálezy podle reviewera` — jenže ty odešly už s #515**, tedy
o dvě issue dřív, ne tímhle PR. Co s nimi odešlo, je `ReviewerShareOfFindings` a
`Policy.reviewerShares`: **sedmidenní součet nálezů po reviewerech**, legenda `barva · jméno ·
počet`. Odpovídal na „kolik toho kdo našel“; jinde v aplikaci to číslo **není** a tenhle blok ho
nevrací — odpovídá na „kolik z toho platilo“, což je ta otázka, kvůli které se na takové číslo
kouká. **Zpátky se vrací jedno tvrzení, které s legendou odešlo** (#383): že **nula neznamená
čisto**. Tady ho nese rozdíl `nerozhodnuto` proti `převzato` — nález, na který se nikdo nepodíval,
se za schválení nevydává.

**Součet je čistá funkce nad diskem, ne počitadlo** — vědomě opačné rozhodnutí než u útraty
(`SpendLedger`): utracené peníze zůstanou utracené i po zahození záznamu, kdežto odmítnutí **je**
ten záznam. Přepočítává se na třech místech (start, doběhlé review, odmítnutí a jeho zrušení) a
stojí **~24 ms** nad cache o 2,6 MB; čísla i to, proč rozhoduje objem a ne počet souborů, jsou
v [`docs/testovani.md`](testovani.md#kolik-stojí-součet-odmítnutí-514).

**Čtyři rozhodnutí, která zadání nechalo otevřená** (podrobně ve specifikaci): `převzato` je nález
neodmítnutý nad **uzavřeným případem** (posunutá hlava, zavřený PR, přenesený nález), kdežto na živé
hlavě je `nerozhodnuto`; **nález se počítá jednou za PR**, ne za soubor, protože přírůstkové review
(#517) tentýž nález nechává ve dvou záznamech; věta má kromě prahu na podíl i **podlahu na počet**
(pět), protože `3 ze 4 neplatí → skill` je jedno kliknutí od `2 ze 4`; a **cesty ke složkám skillů
se zapisují do `config.json`** (`skillFolders`), ne editorem v okně — mockup kreslí tabulku
s tlačítkem, ne políčka na cesty.

Přibylo 30 testů ve čtyřech nových sadách (14 nad `Policy.reviewerTallies`, 15 nad větou, podílem
a cestou ke skillu, 6 nad kresbou, 2 nad diskem a 2 nad storem) a jedno měření. **Regrese se
ověřila vložením u tří věcí zvlášť** — a test na větu přitom **třikrát vyšel zeleně i s regresí
uvnitř**; proč a čím se to spravilo, je v [`docs/testovani.md`](testovani.md#reviewertallyrendertests--a-jak-se-to-měřidlo-třikrát-lhalo).

**Neověřené mezery: PR neprošel Copilotem** (na pokyn uživatele se nepouštěl) a **ve slotu neležela
žádná skutečná odmítnutí**, takže se stav pro screenshot vyrobil ručním zápisem do cache slotu —
neplyne z toho nic o tom, jak blok vypadá nad daty z ostrého provozu, jen to, že se z uložených
záznamů složí a nakreslí.

## #524 — Anotace hunků: sedmá session, která popisuje diff (M17, zákres 59)

Ke každému hunku jedna věta *proč* a ke každému souboru **druh změny** z pěti slov — `změna
chování`, `refaktor`, `test`, `konfigurace`, `generované`. Kreslení u hunku přijde až v #525;
z #524 je vidět **dráha `anotace` v tabu `Průběh`** a tlačítko `Popsat změny` **v liště nad
diffem**. Zákres je sekce 59 v `docs/navrh.html`.

**Zadání se změnilo ve dvou větách a obojí je zapsané rozhodnutí.**

První: **vlastní nástroj `ReportAnnotations` se zahodil.** Nástroj, který si „definuje aplikace“,
v `claude` CLI neexistuje jinak než jako **MCP server** — tedy jako další proces, který by PRism
spouštěl, a to je nová hranice pod tvrdou podmínkou č. 1 i č. 2. Změřeno: session si nástroj
**nezavolala**, třikrát ho zkusila najít přes `ToolSearch` a nakonec odpověděla textem. Odpovídá se
proto **JSON v posledním sdělení**, jako u kontroly nálezů (#150) a rozhovoru (#452).

Druhá plyne z první: **hranice mezi anotací a nálezem není v tvaru nástroje, ale v tvaru schématu,
které aplikace parsuje** — a v tom, že anotace **nemá pole pro závažnost**. Drží ji tři nezávislé
vrstvy: schéma bez toho pole, sada bez `ReportFindings` a `AnnotationRun` bez pole pro nález.

**Sedmá session, ale žádná šestá sada povolení.** Anotace běží doslova s
`AskCommand.allowedTools` (`Read,Grep,Glob,Bash(git:*)`) a liší se **promptem a parserem**, ne
právy; vlastní konstanta s týmž obsahem by byla druhé místo, kde se dá tvrdá podmínka č. 2 porušit.
Je to tatáž delegace jako u agenta (#510), který si sadu půjčuje od slévání konfliktů.

**Co cesta přes poslední sdělení stála:** zabitá session nepřinese **nic** (do posledního sdělení se
nedostala) a sběr umí **tiše nefungovat**, takže je „odpověď se nedala přečíst“ **vlastní stav**
(`answered`) vedle prázdných seznamů, ne totéž. Obojí je v okně poznat na dráze.

Anotace bydlí ve **vlastním storu** (`annotations/<owner>/<repo>/<pr>.json`), ne v `ReviewRecord`u:
ruční `Popsat změny` na PR bez review by jinak sundalo z okna nálezy z minula — tatáž past jako
u #150. Klíčuje se **hlavou**, ne otiskem obsahu jako `Prošlo` (#500), protože se páruje **pořadím
hunku**; hlavu drží uložený záznam **i běh**, jinak by dráha po pushi tvrdila „popsáno“ o diffu, ze
kterého se nekreslí nic. Spouští se **ručně z lišty nad diffem** (bránu nečte) nebo **po
automatickém review** za branou `annotatesHunks`, která je ve výchozím stavu **vypnutá**.

**Proklikání změnilo třetí větu zadání a odhalilo čtyři tiché cesty.** Akce měla být položkou
v nabídce `Sbalit vše ▾`; ze zkoušení vyšlo *„tlačítko nic nedělá“* a byla to pravda — na
obrazovce, ze které se pouští, se po kliknutí neměnilo **nic**. Sešly se čtyři věci: nabídka klik
**spolkne** (zavře se dřív, než se cokoli změní), odznak `Průběhu` sedmou session **nepočítal**,
větu z `annotationFailures` **nečetlo žádné view** a dva `guard … else { return }` byly **tiché**.
Opravuje se všechno čtyři — tlačítko je teď v liště a má **tři stavy** (spustit / zrušit / zkusit
znovu), odznak svítí i při popisu změn, selhání se dostane až do dráhy a oba `guard`y hlásí. Tichý
zůstává jediný, `isTerminating`, a smí být tichý proto, že okno mizí.

**Do lišty se to vejde, ale ne zadarmo, a to se změřilo:** lišta v plné výbavě si v podlahovém okně
(700 b → štěrbina 572 b) říká o **819 bodů**, tedy **přetéká už bez téhle akce** — vlastnost z #219,
ne důsledek #524. Celý popisek stojí dalších **104 b**, takže je `Popsat změny` jediný prvek lišty
bez pevné šířky: v tísni zbude **samotná ikona** a to, co v liště bylo dřív, zůstane.

**Vlastní revize diffu našla skutečnou chybu, a je z třídy „nejtišších“:** guard psaný jako
`!(value is Bool)` zahazuje JSONová čísla **0 a 1**, protože je Swift bridguje na `Bool` (`42` už
ne). U anotací by to znamenalo, že **hunk 1 nemá nikdy anotaci**. Opraveno přes
`CFGetTypeID(number) == CFBooleanGetTypeID()`; **tentýž guard stojí i v `StreamParser.line(from:)`**,
kde bere nález hlášený na řádku 1 — to je mimo rozsah tohohle issue a je na to vlastní úkol.

Přibylo **74 testů v sedmi sadách** (z toho jedna ruční sonda na kresbu lišty); regrese se ověřila
vložením regrese třikrát — u kontroly tvaru odpovědi a u **obou** polovin hlášení selhání zvlášť.

**Neověřená mezera: PR neprošel Copilotem** — na pokyn uživatele se nepouštěl. Vlastní revize diffu
proběhla a je popsaná v PR. **Druhá neověřená mezera: skutečný klik do okna.** Hostitelská aplikace
session nemá *Zpřístupnění*, takže `CGEvent` ani `System Events` do okna nedoletí — screenshotem je
doložené, že tlačítko v liště živé aplikace **stojí**, ale že po kliknutí naskočí běh, musí
proklikat člověk. **A kreslení anotací u hunku není součástí #524** — mockup je v téhle části zadání
pro #525, ne stav aplikace.

## #525 — Anotace v diffu: věta pod hunkem, druh v hlavičce (M17, zákres 59)

Hotovo. Session z #524 psala věty, které **nebylo kde vidět** (*„ty anotace se pustí, ale nikde je
nevidím“* — naostro 0,06 $, 27,4 s, 4 anotace, 3 soubory s druhem). #525 to kreslí: **věta *proč*
pod souřadnicí hunku**, **kapsle druhu změny v hlavičce souboru**, **přepínač `Anotace u hunků`**
v nabídce nad diffem a **`Anotace · 4 věty · proti 4f2ac91`** ve stavovém řádku. Druh změny k tomu
bere **pořadí souborů v itineráři** (#506).

**Tvrdá mez byla geometrie, ne kresba.** Věta je **vlastní řádek diffu** (`DiffRow.annotation`),
tedy tentýž druh řádku jako hlavička hunku — ne vložka do `NSTextView`, protože z výšky bloku se
počítá skok na nález i poloha karet v okraji (#469, #503). Cena je zapsaná: **kde není souřadnice
hunku, není ani věta** — rozbalený kontext hunky slévá a věta uprostřed by souvislý blok rozťala na
dva. Vrátí se, jak se kontext sbalí.

**Změnily se dvě věci proti zadání.** (1) Stavový řádek měl podle zákresu nést `1 session`; je
z něj **počet vět**, protože session je nad jednou hlavou vždycky jedna a konstanta v pruhu netvrdí
nic. (2) **Mapa PR druhem nebarví** — zadání to připouštělo („může“), ale pás má sedm pojmenovaných
tónů a legendu, takže pět druhů znamená pět nových tónů a pět řádků legendy, tedy novou věc na
obrazovce, která v zákresu není. Odloženo do vlastního issue i s překreslením legendy.

**Přepínač je v nabídce, akce v liště — vědomě naopak.** `Popsat změny` se u #524 z nabídky do
lišty přestěhovalo, protože je to akce, po které se musí něco změnit (a nabídka klik spolkne);
viditelnost vět je volba pohledu, tedy tatáž kategorie jako `Nálezy pod řádky`. **Kapsli druhu
přepínač neschová**: to je jedno slovo v hlavičce, která stojí tak jako tak.

Přibylo **44 testů ve čtyřech sadách**; geometrie se **měří na nakresleném bloku**, netvrdí se nad
modelem, a regrese se ověřila vložením regrese dvakrát (věta doprostřed hunku shodí 16 tvrzení,
ignorovaný přepínač 4).

**Neověřená mezera: PR neprošel Copilotem** — na pokyn uživatele se nepouštěl; vlastní revize diffu
proběhla a je popsaná v PR. **Druhá: snímek běžící aplikace nad skutečnými anotacemi.** `bin/run.sh`
ve slotu nedoběhl (v zásuvce běžel `claude --resume`, takže se aplikace zeptala a dialog zůstal
stát; session nemá *Zpřístupnění*, takže na něj nejde kliknout) a druhá instance z `build.noindex`
frontu nenačte. **Proklikání zbývá na člověka.**
