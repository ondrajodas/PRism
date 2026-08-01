# `claude` CLI — co je ověřené

**Ověřeno:** 2026-08-01 · **verze:** `2.1.220 (Claude Code)` · **stroj:** macOS 26

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

## Jak se review vyvolává (ověřeno u #17)

Nálezy sbírá aplikace z `ReportFindings` tool callů, takže **na promptu záleží**.

| Vyvolání | Co se stalo |
|---|---|
| `-p "/code-review …"` (vestavěný slash command) | Doběhne `success`, ale `num_turns: 0`, **žádný `tool_use`** a nálezy jsou v `result.result` jako text s JSON blokem. Sběr by tiše nefungoval — i když se o `ReportFindings` v promptu výslovně řekne |
| `-p "…Report every finding by calling the ReportFindings tool…"` (prostý prompt) | 13 tahů, `ReportFindings` se třemi nálezy. Totéž dělal spike u #12 |

Aplikace proto **slash command nepouští**. Až se sada reviewerů přesune do konfigurace
(#23), bude to potřeba vyřešit znovu: skutečné skilly by šly načíst nástrojem `Skill`, ten
je ale dneska v odmítnutých (v tom běhu se o něj session pokusila a nedostala ho).

Ten samý běh mimochodem doložil, že read-only drží i pod tlakem: reviewer si chtěl chybu
ověřit kompilací, takže zkusil `Write` a `mktemp … && swiftc …`. **Obojí odmítnuto** a v repu
po něm nic nezůstalo.

## Tvar streamu

Jeden JSON objekt na řádek. Typy v pořadí, v jakém chodí:

| `type` / `subtype` | K čemu |
|---|---|
| `system` / `hook_started`, `hook_response` | Hooky uživatelova prostředí. Pro aplikaci šum |
| `system` / `init` | Start session — 22 klíčů, mimo jiné `session_id`, `cwd`, `model`, `tools`, `permissionMode`. **`tools` není spolehlivý obraz povolení** (viz níž) |
| `assistant` | Zpráva modelu; `message.content[]` nese bloky `text` a `tool_use` |
| `user` | Výsledky nástrojů; `message.content[]` nese bloky `tool_result` |
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

## Fixtures

| Soubor | Co dokazuje |
|---|---|
| `review-with-findings.jsonl` | Úspěšný běh se čtyřmi nálezy — tvar `ReportFindings` i `result` |
| `review-clean.jsonl` | Běh bez nálezů: `ReportFindings` s prázdným seznamem |
| `review-killed.jsonl` | Běh zabitý uprostřed — **chybí `result` event** |
| `review-denied-write.jsonl` | Odmítnutý `Write`: `is_error` v `tool_result` i `permission_denials` v `result` |

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

V instalaci na tomhle stroji jsou **dva** slash commandy s tímhle jménem a dělají něco
úplně jiného:

| | |
|---|---|
| `code-review` (vestavěný) | Reviewuje lokální změny a nálezy hlásí přes `ReportFindings`. **Tenhle aplikace pouští** — z něj jsou i fixtures |
| `code-review:code-review` (plugin) | Reviewuje PR přes `gh pr diff` a v `allowed-tools` má `Bash(gh pr comment:*)`, tedy **píše komentář na GitHub**. Nálezy přes `ReportFindings` nehlásí vůbec |

Rozdíl je jeden prefix a důsledek je porušení tvrdé podmínky. Až se sada skillů přesune do
konfigurace (#23), musí se vybírat přesným id — a zákaz `Bash(gh:*)` tam musí zůstat jako
pojistka, protože co skill dělá, aplikace dopředu neví.
