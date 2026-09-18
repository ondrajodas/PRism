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

## Rozhovor nad PR (#452)

Třetí vyjmenovaná session. Sada je **užší než reviewerova** —
`--allowedTools Read,Grep,Glob,Bash(git:*)`, tedy bez `ReportFindings` a bez `Skill` —, zákazy jsou
**tatáž konstanta** `ClaudeCommand.disallowedTools` a rozhovor drží `--resume`.

**`--resume` v print režimu funguje a session si pamatuje předchozí odpověď** — ověřeno spuštěním
nad tímhle repem: druhá otázka („o kterém souboru jsi mluvil jako první?“) odpověděla konkrétním
souborem z první odpovědi, aniž by ho měla v promptu. **Vrácené `session_id` bylo v tom běhu
totéž**, ne nové; kód proto id po každé odpovědi **přepisuje** (nové by se jinak ztratilo)
a když nedorazí žádné, **zahazuje** ho — mrtvý identifikátor by rozhovor rozbil napořád.

**Kolik to stojí, změřeno na `ondrajodas/PRism#452` (opus-5, diff ~5 tisíc řádků):**

| Otázka | Cena | Trvání | Kol |
|---|---|---|---|
| první — *Co v tomhle PR nejvíc riskuje?* | **$1,56** | **125 s** | 18 |
| druhá přes `--resume` — jedna věta | **$0,96** | **6,8 s** | 1 |

Dvě věci, které z toho plynou a nejsou zjevné:

- **Cenu určuje kontext, ne délka otázky.** Druhá otázka byla jedna věta a jedno kolo, a stála
  skoro dolar — session s sebou nese celý rozhovor včetně přečteného diffu. „Krátká doplňující
  otázka je levná“ tedy neplatí.
- **Je to řádově dráž než dotažení textu issue** ($0,18–0,31) a srovnatelné s celým review. Proto
  je cena u **každé** odpovědi v okně vidět a počítá se do `Dneska stálo`; strop se nedává, protože
  za každou otázkou stojí člověk.

## Anotace hunků (#524) — nástroj, který si aplikace nevymyslí

**Sada je táž jako u rozhovoru výš, doslova.** `--allowedTools Read,Grep,Glob,Bash(git:*)`,
zákazy `ClaudeCommand.disallowedTools`, `--resume` se **nepoužívá**. Sedmá session tedy nepřidává
šestou sadu povolení; liší se **promptem a tím, jak se čte odpověď**.

### `ReportAnnotations` si session nezavolá, protože žádný takový nástroj není

Zadání #524 počítalo s vlastním nástrojem `ReportAnnotations`, definovaným „stejně jako
`ReportFindings`“. **Tak to nejde, a je to změřené.** Běh s tím jménem v `--allowedTools`:

- nástroj se **nezavolal ani jednou**;
- session ho **třikrát hledala přes `ToolSearch`** — jméno v povoleních vypadá jako odložený
  nástroj, ale nic za ním není;
- a nakonec odpověděla **prostým textem**.

Důvod je ten, že `ReportFindings` **není nástroj CLI** — obsluhuje ho harness review skillu.
Nástroj, který si „definuje aplikace“, by v `claude` musel být **MCP server**, tedy **další proces,
který by PRism spouštěl**; to je nová hranice pod tvrdou podmínkou č. 1 i č. 2 a zahodilo se to.
Jméno v `--allowedTools` samo o sobě **nic neregistruje**.

### Odpověď je JSON v `result` eventu — a právě tam umí sběr tiše nefungovat

Čte se tedy **poslední sdělení**, jako u kontroly nálezů (#150) a překladu: `AnnotateCommand.parse`
vykrojí text od prvního `{` po poslední `}` a dekóduje objekt se dvěma seznamy. Dvě věci, které
z toho plynou a které se **musí projevit v okně**:

- **Zabitá session `result` nepošle**, takže po ní nezbyde **nic** — ani částečná odpověď. Reviewer
  hlásí `ReportFindings` průběžně, tahle session ne.
- **Odpověď mimo tvar se nedá odlišit od prázdné**, pokud se to nepojmenuje. Session, která si popis
  nepřečte, napíše prózu — a prázdné seznamy by se pak četly jako „diff nemá co popsat“. Aplikace
  proto drží **`answered` vedle prázdných seznamů**; je to tatáž úmluva jako `calledReportFindings`
  u revieweera, jen tady s větší cenou za její vynechání.

### Jazyk v popisu pole neplatí (#592)

**Změřeno na dvou ostrých bězích téhož dne, týmž promptem a týmž modelem.** Jazyk odpovědi stál
tehdy jedině v popisu pole ve schématu — `why`: *„one sentence in Czech saying why this change is
here“* — a `source` k tomu měl **české příklady** (*„z commitu <subject>“*). Vyšlo z toho:

| Běh | Diff | Věty |
|---|---|---|
| `keboola/sandboxes-service#717` | PHP, popisy a commity česky | **česky** |
| `keboola/job-queue#727` | PHP, hodně cizojazyčného textu okolo | **rusky** — *„Временно указывает на ветку разработки…“*, `source`: *„коммит 3c4d82eb“* |

Obě odpovědi jsou v repu jako fixture (`Tests/Fixtures/annotations/`), protože jsou to **skutečné
výstupy** a jiné takové se bez zaplacené session nesehnají.

Tři věci, které z toho plynou:

- **Přívlastek v popisu tvaru je slabší než samostatná věta.** Popis pole odpovídá na „co do něj
  patří“, a model ho tak čte — jazyk v něm je vedlejší poznámka, kterou obsah vstupu přebije.
- **Prosba bez protikladu neplatí.** *„Napiš to česky“* diff v cizím jazyce nepřebije; teprve věta,
  která **říká, proti čemu platí** (*„ať je diff, commity, komentáře i identifikátory v jakémkoli
  jazyce; jazyk odpovědi je nastavení aplikace, ne vlastnost čteného kódu“*), dává modelu důvod
  rozhodnout se jinak, než co vidí.
- **Příklady v promptu jsou taky vstup.** České literály v popisu `source` jazyk **nevynutily**
  a v anglickém zadání matou dvakrát; jsou proto přepsané na popis tvaru bez ukázky v konkrétním
  jazyce.

#### Samostatná věta drží — doměřeno na těch samých dvou PR (#592)

**Po nasazení věty se oba PR popsaly znovu, naostro, v jedné instanci a týž den.** Věta tehdy ještě
brala jazyk z `findingsLanguage`, které bylo v té konfiguraci `en`, takže se dala změřit ta jediná
věc, na které záleží: **poslechne model větu i proti tomu, co vidí v diffu?**

| Běh | Co se žádalo | Věty | Cena |
|---|---|---|---|
| `keboola/job-queue#727` (hlava `3c4d82eb`) | anglicky | **anglicky**, 4 hunky, 3 soubory, `answered`, `dropped 0` | 0,062 $, 20,1 s, 3 turny |
| `keboola/sandboxes-service#717` | anglicky | **anglicky**, 20 hunků, 14 souborů | tentýž řád |

**To je ten rozdíl proti stavu do #592**: `keboola/job-queue#727` je právě ten diff, ze kterého
předtím vyšly **ruské** věty, a se samostatnou větou odpověděl v jazyce, o který si aplikace řekla.
Dva jazyky na dvou PR se tím srovnaly na jeden.

**Co tím ověřené není:** že to platí i pro **češtinu** (od #592 se žádá natvrdo česky — tatáž věta,
jiné slovo). Změřený je mechanismus, ne konkrétní jazyk; další běh nad týmž PR to ukáže a stojí
zhruba **0,06 $ a 20 s**.

## Slévání konfliktů (#467) — čtvrtá session, a první, která píše

Sada je `Read,Grep,Glob,Write(//<strom>/**),Edit(//<strom>/**)`, zákazy jsou **tatáž konstanta**
`ClaudeCommand.disallowedTools`, a **`Bash` v ní není vůbec**.

### `Write` a `Edit` jen ve svém stromě (#467)

**Holé `Write` v `--allowedTools` cestu neomezuje vůbec.** Změřeno: session s `cwd` v jedné složce
a `--allowedTools "Read,Grep,Glob,Write,Edit"` dostala dva úkoly — připsat řádek do souboru v `cwd`
a přepsat soubor v **sousední** složce. Provedla **obojí**. Prompt tedy brána není a být nemůže.

**Scoped pravidlo `Write(//<absolutní cesta>/**)` povoluje právě ten podstrom.** Se stejným
promptem, ale rozsahem na `cwd`, prošel zápis dovnitř a zápis ven skončil v `permission_denials`:

| Zadaná cesta | Rozsah = `cwd` | Rozsah = sousední složka |
|---|---|---|
| soubor v `cwd` | **projde** | **odmítnuto** |
| soubor v sousední složce | **odmítnuto** | **projde** |

Druhý sloupec je ta půlka, kterou bylo potřeba doměřit: bez něj se první výsledek dá vysvětlit
i tak, že scoped pravidlo nepovoluje nic a zápis do `cwd` prošel sám od sebe. **`cwd` implicitně
zapisovatelný není.**

**Obě obejití, která se nabízejí, se odmítnou.** Zkoušeno doslovnou cestou v `file_path` (s pokynem
ji nenormalizovat):

- `<strom>/../jinam/soubor` — **odmítnuto**; v hlášce už stojí normalizovaná cesta, takže se `..`
  vyhodnotí **před** kontrolou oprávnění;
- `<strom>/odkaz/soubor`, kde `odkaz` je symlink mimo strom — **odmítnuto**.

Odmítnutí je v `permission_denials` a **běh na něm nekončí chybou** (`subtype: success`) — tedy
tatáž vlastnost jako u odmítnutého `gh` u revieweera.

### Bez `Bash`e, se `zdiff3` místo něj

Sada `Bash` **nemá**, protože session nesmí commitovat: `git add` a `git rebase --continue` dělá
aplikace. Držet to výčtem zákazů by znamenalo hádat, co všechno se dá napsat — `git -C <strom>
commit` na vzor `Bash(git commit:*)` nezačíná.

Co se tím platí: session neuvidí `git show :1:soubor`, tedy **základ** konfliktu. Vyrovnává to
`git -c merge.conflictStyle=zdiff3 rebase`, po kterém je základ **ve značce**:

```
<<<<<<< HEAD
        $timeout = $this->config->timeout();
||||||| parent of 9a54877 (feat: add retries)
        $timeout = 30;
=======
        $timeout = 30;
        $retries = 3;
>>>>>>> 9a54877 (feat: add retries)
```

**Při rebase je `HEAD` základ, ne moje práce** — obráceně, než jak to člověk čte u merge. Prompt to
říká výslovně; model, který si to splete, zahodí zrovna tu práci, o kterou jde.

### Co to udělalo naostro

Změřeno na scratch repu s konfliktem, který má **správnou odpověď „vezmi obojí“**: `master` změnil
`$timeout` na hodnotu z konfigurace, přehrávaný commit pod něj přidal `$retries`.

| | |
|---|---|
| Výsledek | oba záměry zachované, **žádná značka nezůstala** |
| Kroky | `Read`, `Glob`, `Edit` — všechny **uvnitř** stromu |
| Účet | `{"files":[{"path":"SecretClient.php","action":"both"}],"caveats":"Proměnná $retries zůstává v metodě nepoužitá…"}` |
| Cena | **$0,355**, 4 kola, **23 s** |
| `permission_denials` | prázdné |

Dvě věci, které z toho plynou:

- **Odpověď přišla v tom tvaru, který `ConflictCommand.parse` čte** — objekt, `action: "both"`,
  `caveats` česky. Kontrakt tedy drží na obou stranách, ne jen v testu nad vymyšleným JSONem.
- **`caveats` nese informaci, kterou by aplikace sama nezjistila** (proměnná zůstala nepoužitá).
  Právě proto se ta věta ukazuje u výsledku a ne zahazuje.

Cena jednoho kola je řádově **desetina** rozhovoru nad PR — session čte kód kolem značky, ne celý
diff. Kol může být víc (rebase se zastaví u každého kolizního commitu), a proto je jich strop tři.

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


## Důvěra ke složce a režimy povolení (#460)

Obojí se týká **interaktivního** `claude`, tedy toho, co pouští `▶` v zásuvce. Review sessions se
to netýká: běží s `-p` a `--help` říká výslovně, že *„the workspace trust dialog is skipped when
Claude is run in non-interactive mode“*.

### Dotaz na důvěru ke složce

Interaktivní `claude` se v neznámém adresáři ptá **„Is this a project you created or one you
trust?“**. Pro PRism je to problém, který se sám neopotřebuje: **každý pull request dostane vlastní
pracovní strom**, takže je to pokaždé nová cesta a dialog by přišel u každého PR znovu.

Změřeno pty sondou (`claude` spuštěný v pty, čtení výstupu, žádný zápis do skutečné konfigurace —
podstrčený `HOME`). **Přeměřeno u #479 na `claude 2.1.250`**, protože měření z #460 se nedalo
zopakovat; postup i pasti, o které se ta první sonda rozbila, jsou
v [`docs/testovani.md`](testovani.md#sonda-na-dotaz-o-důvěru-ke-složce-479).

| Scénář | Výsledek |
|---|---|
| Adresář, který v konfiguraci není | **dialog** |
| `projects[<cesta>].hasTrustDialogAccepted = true` | bez dialogu |
| Registrovaný **předek** (1 až 6 pater výš) | **bez dialogu** — důvěra se dědí, a hloubka na tom nic nemění |
| Předek `true` + přesná cesta `false` | **bez dialogu** — `false` zděděné `true` **nepřebíjí** |
| Přesná cesta `false` a nic nad ní | **dialog** — `false` je tedy k nerozeznání od „nezapsáno“ |
| Předek `false` + přesná cesta `true` | bez dialogu |
| **Bare klon** (`git init --bare`) tři patra pod důvěryhodným předkem | bez dialogu |
| **Git pracovní strom** (`.git`) tři patra pod důvěryhodným předkem | **dialog** |
| Skutečný strom review v cache, jehož **bare klon je `true`** | bez dialogu |
| Skutečný strom review v cache, jehož bare klon je `false` (kořen cache `true`) | **dialog** |
| Týž strom se zapsanou **přesnou cestou** | bez dialogu |

Čtyři věci, které z toho plynou a nejsou zjevné:

- **Dědění se láme na git pracovním stromě, a je to jediná výjimka, kterou se podařilo najít.**
  Obyčejná složka i bare klon dědí důvěru z předka do libovolné hloubky; složka, ve které je `.git`,
  si žádá **vlastní záznam** — nebo záznam na svém repozitáři (strom `job-queue` prošel proto, že
  bare klon `job-queue.git` byl `true`). Kvůli tomu **PRism od #479 zapisuje i tu složku, ve které
  shell doopravdy stojí**, ne jen kořen cache: strom review je přesně to, kam `▶` míří.
- **Hypotéza z #479 se nepotvrdila.** Podezření padlo na explicitní `false` u bare klonů, jenže
  `false` se chová jako nezapsáno: zděděné `true` zůstává v platnosti (řádek 4 tabulky). Zapsané
  `hasTrustDialogAccepted: false` na naší cestě se proto přepsat **smí** — a taky se přepisuje.
- **Ta `false` si tam píše `claude` sám.** Nad složkou, kterou v konfiguraci nemá a která je
  důvěryhodná přes předka, si během startu záznam **založí** — s `hasTrustDialogAccepted: false`
  a s celou další výbavou (`allowedTools`, `mcpServers`, `lastVersionBase`, …). Není to tedy
  odpověď člověka „nevěřím“, ale výchozí hodnota záznamu. Když dialog **vyskočí a nikdo
  neodpoví**, nezapíše se naopak nic.
- **Klíčem je rozvinutá cesta.** Nad `/tmp/x` hlásí `claude` workspace `/private/tmp/x`. Rozvíjí to
  `realpath`, **ne `URL.resolvingSymlinksInPath()`** — ta `/tmp` ani `/var` schválně nerozvíjí
  (změřeno: vrátí `/tmp`), a přesně tyhle dva prefixy jsou na macOS symlinky.

**Co se naopak nepotvrdilo a stálo za měření: `claude` cizí zápis do konfigurace nepřepisuje.**
Podezření bylo, že si soubor přečte při startu a na konci ho uloží ze své kopie, takže by náš
záznam zmizel. Změřeno tak, že se do podstrčené konfigurace během běhu (v `t = 1`, `6` a `15` s)
zapsal značkový klíč — **ve všech třech případech přežil** a `claude` si vedle něj svůj záznam
založil. Čte tedy soubor znovu, než ho zapíše.

**Že je to podporovaná cesta, říká sám `claude`**: v jeho binárce stojí dvakrát věta *„…accept the
trust dialog here once interactively, or set `projects[<cesta>].hasTrustDialogAccepted` in
`~/.claude.json`“*. Žádná volba ani proměnná prostředí na to není — `--help` zná jen `-p`
(neinteraktivní režim), což je přesně to, co v zásuvce použít nejde.

### Režimy povolení

`--permission-mode` má šest hodnot: `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`,
`plan`. Zásuvka pouští `auto`, a je to vybrané, ne odhadnuté:

- **`auto` má vyjmenovaná a čitelná pravidla.** `claude auto-mode defaults` vypíše `allow`,
  `soft_deny` a `hard_deny` — hranice tedy existují a dá se do nich podívat. Je to jediný z těch
  šesti, u kterého to platí.
- **`bypassPermissions` je podle `--help` doslova „Bypass all permission checks“** — to, co zapíná
  `--dangerously-skip-permissions`. Do tohohle repa nepatří.
- **`manual` a `acceptEdits` dotazy neodstraní** (druhý jen u editací), **`plan` mění, co session
  dělá**, a `dontAsk` nemá vypsatelnou sadu pravidel, podle které by se dalo posoudit, co ještě
  zastaví.

## Co `claude` dělá s terminálem (#460)

Změřeno pty sondou nad běžícím `claude` — které řídicí sekvence pošle:

| Sekvence | Co znamená | Poslal? |
|---|---|---|
| `ESC[?1049h` | přepnutí do **alternativního bufferu** | **ano** |
| `ESC[?1000h`, `?1002h`, `?1003h` | hlášení kliknutí, tažení a **každého pohybu** myši | **ano** |
| `ESC[?1006h` | SGR režim souřadnic myši | **ano** |
| `ESC[?1007h` / `?1007l` | alternate scroll zapnout/vypnout | **nepošle ani jedno** |

Plyne z toho odpověď na „nejde mi v tom terminálu scrollovat“, a **není to chyba emulátoru**:
alternativní buffer scrollback **nemá** (proto není kam couvnout) a `claude` si navíc zapne **plné
hlášení myši**, takže kolečko se mu **doručuje jako událost** a co s ním udělá, je jeho rozhodnutí.
V holém shellu se roluje normálně — scrollback má 500 řádků a je změřené, že se výřez hýbe.
