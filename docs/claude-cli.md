# `claude` CLI — co je ověřené

**Ověřeno:** 2026-08-01 · **verze:** `2.1.220 (Claude Code)` · **stroj:** macOS 26 ·
**schéma `ReportFindings` doměřeno** 2026-08-17 na `2.1.233` ·
**dotažení textu issue změřeno** 2026-08-17 na `2.1.233` a ověřeno spuštěním 2026-08-19 na `2.1.236`

Spike k issue #12, doplněno a **opraveno** u #17. Specifikace měla flagy `claude` CLI psané
z pracovní znalosti; tenhle dokument je nahrazuje tím, co skutečně dělá nainstalované CLI.
Všechno níž je ověřené spuštěním, ne odvozené z nápovědy — kde se nápověda a chování liší,
je to napsané.

Surové streamy z těch běhů leží v [`Tests/Fixtures/stream-json/`](../Tests/Fixtures/stream-json).

## Headless režim

```bash
claude -p "<prompt>" \
    --output-format stream-json \
    --verbose \
    --allowedTools "Read,Grep,Glob,Bash(git:*),ReportFindings" \
    --disallowedTools "Bash(gh:*),Bash(git push:*)" \
    < /dev/null
```

Čtyři věci, které se nedají vynechat:

- **`--verbose` je povinný.** Bez něj `claude` skončí chybou
  `When using --print, --output-format=stream-json requires --verbose`. Není to volba,
  je to podmínka.
- **`ReportFindings` musí být v `--allowedTools`.** Bez něj reviewer nálezy **napíše jako
  text** místo aby zavolal nástroj — a sběr nálezů tiše zmizí. Návrh v specifikaci
  (`Read,Grep,Glob,Bash(git:*)`) tuhle chybu obsahoval; ověřeno oběma způsoby.
- **`stdin` musí být zavřený.** Jinak `claude` čeká tři sekundy a vypíše
  `Warning: no stdin data received in 3s`. `SubprocessRunner` posílá `FileHandle.nullDevice`,
  takže je to splněné — ale je to podmínka, ne shoda náhod.
- **Pracovní složka je `cwd` procesu.** Nedá se předat flagem — proto má `ProcessStreaming`
  `workingDirectory`, kdežto bufferovaná cesta si u `gitu` vystačí s `-C`.

## `--allowedTools`: co doopravdy dělá

Nápověda ukazuje `"Bash(git *) Edit"` s mezerou, ale **funguje i `Bash(git:*)`** — ověřeno,
`git status --short` přes něj prošel.

V shellu se ta hodnota musí dát do uvozovek: `*` by prošlo glob expansion a závorky jsou
v `bash` i `zsh` syntaktická chyba. Aplikace shell nepoužívá — `Process` dostává argumenty
polem, takže je to jen otázka ukázek v dokumentaci.

Podstatnější je, co ten flag **není**:

| | |
|---|---|
| **Není totéž co seznam dostupných nástrojů** | Init event vypisuje i nástroje, které povolené nejsou — `Write`, `Edit` i `Bash` v něm jsou, ať je v `--allowedTools` cokoli. Na část seznamu ale vliv má: bez `Grep`/`Glob` v povoleních zmizí i z `tools` |
| **Bash zužuje, ale vedle vzoru platí i vestavěný seznam** | S `--allowedTools "Bash(git:*)"` prošly `ls -la` i `cat soubor` — **ne** proto, že by scope neplatil, ale protože jsou to čtecí příkazy z vestavěného seznamu Claude Code. `gh auth status` **neprošel** (`This command requires approval`, viz `permission_denials`) |
| **Uvnitř vzoru projde všechno** | `Bash(git:*)` povolí **každý** git příkaz včetně `git push`. Ověřeno spuštěním: `git push --dry-run origin HEAD` se provedl a selhal až na chybějícím remote |
| **Zápis přesto neprojde** | `touch`, `rm` i nástroj `Write` skončily chybou a soubory nevznikly |

`--allowedTools` seznam nástrojů v init eventu **částečně ovlivňuje**, ale nepovolené
nástroje z něj nemizí. Ověřeno porovnáním dvou fixtures: běh s `--allowedTools "Read"` má
v `tools` 31 položek a chybí v nich `Grep` a `Glob`, kdežto běh s `Read,Grep,Glob,…` jich
má 33. **`Write`, `Edit` i `Bash` jsou přitom v obou** — tedy i tam, kde povolené nejsou.

**Oprava proti první verzi tohohle dokumentu (ověřeno u #17).** Původně tu stálo, že scope
`Bash` nezúží a že hranice vede podle toho, jestli je operace měnící. Obojí je nepřesné:

- Co je **mimo** vzor, se odmítne — pokud to není na vestavěném seznamu čtecích příkazů.
  `ls -la` a `cat` proto prošly, `gh auth status` ne.
- Co je **uvnitř** vzoru, projde celé. `Bash(git:*)` tedy pouští i `git push` — a to je
  jediná cesta, kterou by session z naší cache uměla něco odeslat, protože `origin` míří na
  skutečné repo a má credential helper.

## `--disallowedTools`: čím se to zavírá

Zákaz **přebíjí povolení** a funguje na vzor příkazu, ne jen na nástroj. Ověřeno:

```bash
--allowedTools "Read,Grep,Glob,Bash(git:*),ReportFindings" \
--disallowedTools "Bash(gh:*),Bash(git push:*)"
```

| Příkaz | Bez zákazu | Se zákazem |
|---|---|---|
| `git log --oneline` | projde | projde |
| `git push origin HEAD:…` | **projde** | `Permission to use Bash with command … has been denied` |
| `git push file://…/repo.git HEAD:…` | projde | odmítnuto — **ani s vypsanou URL** |
| `gh auth status` | odmítnuto (`requires approval`) | odmítnuto (výslovně) |

Na vzdálený repozitář po pokusu nedorazil žádný ref. Rozdíl v hlášce stojí za pozornost:
bez zákazu je to „vyžaduje schválení“ (tedy stav, který by v interaktivním režimu šel
odklepnout), se zákazem „bylo odepřeno“.

Odmítnutí je ve streamu vidět dvakrát: jako `tool_result` s `is_error: true` a textem
`Claude requested permissions to …, but you haven't granted it yet.`, a souhrnně v `result`
eventu v poli `permission_denials` (`tool_name`, `tool_use_id`, `tool_input`). Běh přitom
skončí `subtype: "success"` a `is_error: false` — **odmítnutý nástroj není chyba běhu**.

**Od odmítnutí se chyba nástroje pozná strukturou, ne textem hlášky** (#326). `user` event
s neprovedeným voláním nese vedle `message` ještě pole `tool_result_meta`:

```json
"tool_result_meta": [{"id": "toolu_01Ems…", "non_execution_kind": "user-rejected"}]
```

Je to jediná hodnota, která se v datech objevila — v `review-denied-write.jsonl`
i `intent-tool-denied.jsonl`. Aplikace na tom stojí: `is_error: true` **bez** `tool_result_meta` je
běžná chyba nástroje (`grep` bez shody vrací `is_error` při každém běhu), takže by z ní odznak
`ODMÍTNUTO` udělal poplach nad úplně normálním krokem. Do #326 tu stálo opačné rozhodnutí — že se
odmítnutí od chyby odlišit nedá —, viz `docs/architektura.md` a záznam rozhodnutí ve specifikaci.

**Odpověď dostane každý pokus, i `ReportFindings`.** Ve všech osmi fixtures je pokusů a odpovědí
stejně a `tool_use.id` sedí na `tool_result.tool_use_id`. Obsah odpovědi je řetězec, u některých
nástrojů pole bloků (`ToolSearch` vrací `tool_reference`). Zabitá session poslední odpověď
nedostane vůbec — to je ta situace, kvůli které je krok v ose pokus, dokud odpověď nedorazí.

## Jak se review vyvolává (ověřeno u #17, přepsáno u #78)

Nálezy sbírá aplikace z `ReportFindings` tool callů, takže **na promptu záleží**.

| Vyvolání | Co se stalo |
|---|---|
| `-p "/code-review …"` (slash command) | Doběhne `success`, ale `num_turns: 0`, **žádný `tool_use`** a nálezy jsou v `result.result` jako text s JSON blokem. Sběr by tiše nefungoval — i když se o `ReportFindings` v promptu výslovně řekne |
| `-p "You are running as the \"X\" reviewer …"` (jméno jen v próze) | Nálezy chodí přes `ReportFindings`, ale **jestli se skill načte, je na modelu** — viz níž |
| `-p "First call the Skill tool with skill=\"X\" …"` (výslovný pokyn) | Skill se načte a `ReportFindings` funguje dál. **Tohle aplikace dělá od #78** |

### Skill se nenačte tím, že se jmenuje (#78)

Do #78 prompt jméno skillu jen napsal do věty. Změřeno na scratch repu s vlastním skillem,
který nechává v každém nálezu poznávací značku:

| Jméno v promptu | Skill existuje? | Běhů | Načetl se |
|---|---|---|---|
| `prism-marker`, jen v próze | ano (projektový skill v repu) | 3 | 3× ano |
| `prism-marker`, výslovný pokyn | ano | 3 | 3× ano |
| `code-review`, jen v próze | **ne** | 3 | 3× si model **domyslel jiný** |

Rozhodující tedy není, jestli si model vzpomene, ale **jestli se jméno na něco mapuje**.
Když ne, sáhne po nejbližším, co jde nástrojem `Skill` oslovit. Ve všech třech bězích to
bylo `code-review:code-review` — a k tomu si navíc načetl projektový skill ležící
v reviewovaném repu a řídil se jím (poznat podle značky v nálezech).

Na skutečných bězích aplikace vyšel stejný obrázek: skill se načetl v **5 ze 14** běhů,
protože konfigurace jmenovala `code-review`.

### `code-review` není skill

Na tomhle stroji neexistuje žádný `SKILL.md` se jménem `code-review`. Co existuje:

| co | kde | jak se to adresuje |
|---|---|---|
| uživatelské skilly | `~/.claude/skills/<jméno>/SKILL.md` | jménem |
| plugin **command** `code-review` | `plugins/code-review/commands/code-review.md` | `code-review:code-review` |
| vestavěný `/code-review` | zadrátovaný v CLI, žádný soubor | jen jako slash command |

Konfigurace aplikace proto jmenuje **id nástroje `Skill`**, ne slash commandy.

### `Skill` prochází i mimo `--allowedTools`

Nástroj `Skill` se v běhu použil, i když v povoleních nebyl, a **bez** `permission_denials`
— je to čtecí builtin, stejně jako `ls` a `cat` (viz sekce o `--allowedTools`). Povolení
tedy není to, čím se načítání skillů řídí. V seznamu je od #78 stejně, protože ten seznam
má říkat, co reviewer smí.

### Projektové skilly z reviewovaného repa se načtou

Reviewer si načte i skill, který leží v `.claude/skills/` **uvnitř kontrolovaného
worktree**, a řídí se jím — doloženo tím, že nálezy nesly značku z takového skillu.
Znamená to, že si PR může přinést vlastní instrukce pro svého revieweera.

Bereme to jako **žádoucí**: repo, které si přinese vlastní review skill, ho má dostat.
Vypnout by to šlo `--setting-sources user` (načte jen uživatelské nastavení, ne projektové)
— **neověřeno, nezkoušelo se**, je to jen zaznamenaná možnost, kdyby se rozhodnutí otočilo.

### `code-review:code-review` pod omezeními aplikace

Dřív tu stálo, že tenhle plugin nálezy přes `ReportFindings` nehlásí. **To platilo pro
slash command podobu.** Vyvolaný nástrojem `Skill` s promptem aplikace se chová jinak
(ověřeno spuštěním u #78):

- `ReportFindings` zavolal, nálezy dorazily,
- `gh` ani `Task` **nezkusil ani jednou**, žádná odmítnutá oprávnění,
- diff si vzal z worktree (`git diff`, `git show`, `git blame`), ne přes `gh pr diff`.

Prompt mu k tomu výslovně říká, že GitHub k dispozici není a že **zákazy přebíjejí skill**.
Zákaz `Bash(gh:*)` v `--disallowedTools` zůstává jako pojistka — ten plugin má
`Bash(gh pr comment:*)` ve svých `allowed-tools`, takže si o odeslání umí říct sám.

## Tvar streamu

Jeden JSON objekt na řádek. Typy v pořadí, v jakém chodí:

| `type` / `subtype` | K čemu |
|---|---|
| `system` / `hook_started`, `hook_response` | Hooky uživatelova prostředí. Pro aplikaci šum |
| `system` / `init` | Start session — 22 klíčů, mimo jiné `session_id`, `cwd`, `model`, `tools`, `permissionMode`. **`tools` není spolehlivý obraz povolení** (viz níž) |
| `assistant` | Zpráva modelu; `message.content[]` nese bloky `text` a `tool_use` |
| `user` | Výsledky nástrojů; `message.content[]` nese bloky `tool_result`, u neprovedeného volání je vedle nich `tool_result_meta` (#326). **Aplikace to čte** — do #326 ne |
| `rate_limit_event` | Informace o limitech, chodí i uprostřed běhu |
| `system` / `thinking_tokens` | Průběžné počty; ve fixtures je jich nejvíc ze všech |
| `result` / `success` | Konec běhu: `duration_ms`, `num_turns`, `total_cost_usd`, `usage`, `permission_denials`, `result` |

Dvě věci, které se od návrhu liší:

- **`session_id` je na každém eventu**, ne jen v `init`. Parser si ho může vzít odkudkoli,
  ale spolehnout se dá i na `init`.
- **Přerušený běh nemá `result` event.** Ověřeno zabitím uprostřed: stream prostě skončí.
  Rozpoznání „doběhlo“ vs. „bylo zabito“ tedy stojí na přítomnosti `result`, ne na exit
  kódu. V zachyceném případě zůstaly všechny řádky celé, ale parser musí počítat i s tím,
  že poslední řádek bude useknutý uprostřed.

## `ReportFindings`

Volá se jako běžný `tool_use` blok uvnitř `assistant` eventu:

```json
{"type":"tool_use","id":"toolu_01TBc3jn…","name":"ReportFindings",
 "input":{"level":"…","findings":[ … ]}}
```

Jeden nález (ověřeno na skutečném běhu):

```json
{
  "file": "Cart.swift",
  "line": 13,
  "category": "correctness",
  "verdict": "CONFIRMED",
  "short_summary": "total() ignores Item.quantity",
  "summary": "…",
  "failure_scenario": "…"
}
```

`category` je volný kebab-case slug od reviewera, `verdict` je `CONFIRMED` nebo
`PLAUSIBLE` — tedy přesně to, na čem staví `Policy`. **Čisté review volá `ReportFindings`
s prázdným polem `findings`**, ne že by nástroj nezavolalo; obojí je ve fixtures.

### Co je v schématu povinné a co má strop (doměřeno u #120 na `2.1.233`)

Přečteno **ze schématu v binárce CLI**, ne z běhu — je to deklarace nástroje, takže se za ni
neplatí a nezávisí na tom, jak se model zachová:

| Pole | Povinné? | Strop |
|---|---|---|
| `file` | **ano** — `Repo-relative path of the file the finding is in` | — |
| `line` | ne (`1-indexed line the finding anchors to`) | — |
| `summary` | **ano** | — |
| `failure_scenario` | **ano** | — |
| `short_summary` | ne | **60 znaků** |
| `category` | ne | 40 znaků |
| `verdict` | ne | `CONFIRMED` \| `PLAUSIBLE` |
| `outcome` | ne | `fixed` \| `skipped` \| `no_change_needed` — jen při re-reportu po opravě |
| `findings` (celý seznam) | ano | **32 položek**, „most-severe first; empty if none survived“ |
| `level` (vedle `findings`) | ne | `low` \| `medium` \| `high` \| `xhigh` \| `max` |

**Co z toho plyne pro aplikaci** (#120, zadání pro reviewera):

- **Obecný nález přijde zakotvený k souboru bez řádku, ne bez místa.** Nález, který se váže
  k zadání a ne k řádku („chybí migrace, kterou zadání žádá“), tedy dorazí s `file` a bez
  `line`. Cesta to unese bez práce: `ReportedFinding.file` i `line` jsou optional
  a `Policy.draftTarget` z toho udělá `.body(path: <soubor>, line: nil)`, takže při převzetí
  skončí **v těle review s odkazem na soubor**.
- **Texty v UI nic neslibují.** Prošlo se to: `FindingRow.location` dá `—` a `locationHelp`
  větu „Nález nepatří ke konkrétnímu místu v kódu“ jen u nálezu, který soubor doopravdy nemá,
  a `FindingNavigationView` o nálezech bez místa mluví jedině tehdy, když `withoutPlace > 0`.
  Žádný text netvrdí, že nález bez souboru přijít **může** — a protože schéma `file` vyžaduje,
  je ten stav dosažitelný jen z uložených dat, ne z nového běhu.
- **`droppedFindings` je pořád potřeba.** Co CLI udělá, když model strop 32 překročí, **změřené
  není** — schéma je `strict`, takže se čeká odmítnutí volání, ale ověřené to není a spoléhat se
  na to nemá cenu: `findings` se stejně parsují z cizího JSONu a nález, ze kterého se nedá složit
  `ReportedFinding`, musí být vidět jako počet, ne zmizet.

## Dotažení textu issue (#345)

Zadání pro reviewera si text Linear issue tahá **vlastní krátkou session**. Vypadá takhle
(`IntentTextCommand.arguments`):

```bash
claude -p "<prompt s identifikátory a se jménem nástroje>" \
    --output-format stream-json \
    --verbose \
    --allowedTools "ToolSearch,mcp__claude_ai_Linear__get_issue" \
    --disallowedTools "Bash(gh:*),Bash(git push:*)" \
    --max-turns 6 \
    < /dev/null
```

Čtyři věci, které se **musely změřit** a nedaly se odvodit z toho, jak funguje překlad nálezů:

- **Linear MCP v headless session je.** `claude -p` vidí všech 38 claude.ai konektorů
  a `claude.ai Linear` hlásí v `init` eventu `status: "connected"`. Čtecí nástroj se jmenuje
  **`mcp__claude_ai_Linear__get_issue`** — ale je to jméno **serveru u tohohle uživatele**, ne
  kontrakt, takže patří do konfigurace (`GlobalConfig.issueTextTool`), ne do konstanty.
- **Bez `ToolSearch` to nefunguje.** Na stroji je v session **165 nástrojů**, takže CLI odkládá
  schémata: model musí napřed zavolat `ToolSearch` (`select:mcp__claude_ai_Linear__get_issue`)
  a **teprve pak** MCP nástroj. Doloženo ve všech bězích. Proto `--allowedTools ""` z překladu
  nefunguje a proto `--max-turns` nesmí být 1–2 (dotažení je ≥ 3 turny / 2 tool cally).
- **Cena.** Jedno dotažení: **$0,18 (sonnet) až $0,31 (opus-5), ~20 s**. Rozhoduje **boot session**
  (85–121 tis. cache-read + ~21 tis. cache-create: systémový prompt, 165 jmen nástrojů,
  `SessionStart` hook), ne text issue — takže víc issues v jednom PR je skoro zdarma, ale **každé
  review platí boot znovu**. Ověřovací běh u #345 (jedno issue, 2 410 znaků odpovědi): `num_turns: 3`,
  `$0,3099`, 21,4 s.
- **Tři tvary selhání, a dva vypadají jako úspěch:**

  | Případ | Exit | `result` event | Signál |
  |---|---|---|---|
  | server chybí / není přihlášený | **0** | `success`, `is_error: false`, `permission_denials: []` | jen **próza** modelu + `init.mcp_servers = []` |
  | server v konfiguraci, ale nejde spustit | **1** | `error_max_turns`, **klíč `result` v eventu vůbec není** | `init.mcp_servers[].status = "failed"`, na stderr nic |
  | nástroj není povolený | 0 | `success` | `permission_denials: ["…list_issues"]`, `tool_result` s `is_error` |

  **Nepřihlášený server je k nerozeznání od chybějícího** — servery se `status: "needs-auth"`
  nemají v `tools` ani jednu položku. Jediný **strojově čitelný** signál je tedy
  `init.mcp_servers[].status` (`connected` / `needs-auth` / `failed` / `pending`), a ten se dá
  přečíst **jedině streamem**; `TranslationCommand` proti tomu jede bufferovaně. Rozhodnout
  „dotáhlo se / nedotáhlo“ **podle prózy modelu je hádání**.

**Seznam nástrojů v `init` eventu není obraz oprávnění** — potvrzeno i tady: jsou v něm i všechny
**zápisové** Linear nástroje, přesto bylo povolené jen `get_issue` a nepovolený čtecí `list_issues`
skončil v `permission_denials`.

**Neověřená mezera z průzkumu:** skutečný pokus o **zápisový** Linear nástroj se nedělal (mantinel
„v Linearu nic neměnit“), takže důkaz je nepřímý — přes odmítnutý čtecí `list_issues`. Zlevnění
bootu (`--strict-mcp-config` jen pro Linear) se neměřilo, protože by to znamenalo šťourat do
uloženého OAuth tokenu.

## Fixtures

| Soubor | Co dokazuje |
|---|---|
| `review-with-findings.jsonl` | Úspěšný běh se čtyřmi nálezy — tvar `ReportFindings` i `result` |
| `review-clean.jsonl` | Běh bez nálezů: `ReportFindings` s prázdným seznamem |
| `review-killed.jsonl` | Běh zabitý uprostřed — **chybí `result` event** |
| `review-denied-write.jsonl` | Odmítnutý `Write`: `is_error` v `tool_result`, `non_execution_kind` v `tool_result_meta` (#326) i `permission_denials` v `result` |
| `intent-server-missing.jsonl` | #345: MCP server v session **není** — `mcp_servers: []`, přitom `exit 0` a `success` |
| `intent-server-failed.jsonl` | #345: `mcp_servers[].status = "failed"`, `error_max_turns` a **`result` event bez klíče `result`** |
| `intent-tool-denied.jsonl` | #345: nepovolený čtecí nástroj — `success` a `permission_denials` s jednou položkou |

**Transcript session není `stream-json`** (#327, #408) a fixtures na něj leží v
`Tests/Fixtures/transcript/`:

| Soubor | Co dokazuje |
|---|---|
| `interrupted-session.jsonl` | #97: `ReportFindings` v transcriptu zabité session, a typy `queue-operation` / `last-prompt`, které ve streamu nejsou |
| `review-session.jsonl` | #327: celé review — `attachment`, zadání session, `text`, `thinking`, tři nástroje s odpověďmi a `ReportFindings` |
| `denied-tool.jsonl` | #408: **odmítnutý nástroj** — `toolDenialKind` na **řádku**, hláška `Permission to use … has been denied.` |

Čtyři rozdíly proti streamu, každý ověřený na skutečném souboru:

| Ve streamu | V transcriptu |
|---|---|
| `session_id` | `sessionId` |
| `system` / `init` | není vůbec; místo něj `queue-operation` a `attachment` |
| `tool_result_meta[].non_execution_kind` | **`toolDenialKind` na řádku** (v bloku `tool_result` je `null`) |
| čas nikde | `timestamp` na skoro každém řádku |

**Hláška o odmítnutí se mezi nimi liší**, a je to potřeba vědět: stream píše `Claude requested
permissions to use Bash, but you haven't granted it yet.`, transcript `Permission to use Bash with
command wc -l ukazka.swift has been denied.` Je to druhý důvod, proč se odmítnutí nepozná podle textu
(první je v #326).

**`denied-tool.jsonl` se musela vyrobit** (`claude -p` s `--allowedTools 'Bash'` a
`--disallowedTools 'Bash(wc:*)'`, dva řádky ze vzniklého transcriptu). V transcriptech z review na
tomhle stroji odmítnutí **není ani jedno** — a dokud se to nezkusilo, vypadala jejich prázdnota jako
doklad o tom, že CLI ten klíč do souboru nepíše.

**Neúspěšný příkaz fixture nemá** (#326): ve všech osmi zachycených streamech přišel
`is_error: true` **vždycky** s `tool_result_meta`, tedy jako odmítnutí — `grep` bez shody ani `Read`
neexistujícího souboru se do nich nedostal. Rozlišení „chyba nástroje ≠ odmítnutí“ se proto testuje
inline JSONem v `StreamParserTests`; tvar bloku je tentýž, jen bez toho `meta`.

**Úspěšné dotažení textu issue fixture nemá, a je to schválně:** odpověď nese celý text skutečného
issue z firemního trackeru a firemní obsah do fixtures nepatří. Tvar eventů kolem něj je pokrytý
těmi třemi selháními (tentýž `init`, tentýž `result`), takže inline v testu zbývá jen to, co je
**náš vlastní formát** — značky v odpovědi. Rozbor nad skutečnou úspěšnou odpovědí se ověřil
spuštěním (dočasný test nad souborem ve scratchpadu, 2 359 znaků textu, `gap == nil`).

Issue #12 žádalo „kompletní surové streamy“ — redakce hook eventů je vědomá odchylka a týká
se jen obsahu, který do repa nepatří. Všechno, co parser potřebuje, je v nich tak, jak to
CLI vypsalo.

Streamy jsou surové **s jedinou výjimkou**: v `system/hook_response` eventech je obsah polí
`output` a `stdout` nahrazený placeholderem. `SessionStart` hook do nich vkládá celý text
nainstalovaných skillů — je to **cizí obsah**, který do tohohle repa nepatří, a pro parser
je to navíc šum. Ostatní eventy jsou beze změny, bajt po bajtu; redakce ubrala zhruba
pětinu objemu.

Prošly kontrolou na tajemství (tokeny, klíče, hesla, e-maily — nic). Nesou ale pořád
lokální prostředí: jména nainstalovaných pluginů a skillů v `init` eventu a cesty pod
`/Users/ondra`. Repo je privátní, takže to je v pořádku; kdyby se někdy zveřejňovalo, je to
místo ke kontrole.

Testovaný kód byl schválně chybný `Cart.swift` ve scratch repu (součet ignoruje množství,
celočíselné dělení u slevy, index bez kontroly prázdnosti) — v repu není, fixtures ho nesou
v obsahu streamu.

## Dva různé `code-review`

V instalaci na tomhle stroji jsou **dva** slash commandy s tímhle jménem:

| | |
|---|---|
| `code-review` (vestavěný) | Reviewuje lokální změny a nálezy hlásí přes `ReportFindings` |
| `code-review:code-review` (plugin) | Reviewuje PR a v `allowed-tools` má `Bash(gh pr comment:*)`, tedy **umí napsat komentář na GitHub** |

Aplikace pouští ten **pluginový**, protože jako jediný jde adresovat nástrojem `Skill`
(vestavěný slash command skill není). Rozdíl proti tomu, co tu stálo do #78: pod promptem
aplikace na GitHub nesáhne — viz měření výš — a zákaz `Bash(gh:*)` je nad tím pojistka.
