# `claude` CLI — co je ověřené

**Ověřeno:** 2026-08-01 · **verze:** `2.1.220 (Claude Code)` · **stroj:** macOS 26

Spike k issue #12. Specifikace měla flagy `claude` CLI psané z pracovní znalosti; tenhle
dokument je nahrazuje tím, co skutečně dělá nainstalované CLI. Všechno níž je ověřené
spuštěním, ne odvozené z nápovědy — kde se nápověda a chování liší, je to napsané.

Surové streamy z těch běhů leží v [`Tests/Fixtures/stream-json/`](../Tests/Fixtures/stream-json).

## Headless režim

```bash
claude -p "<prompt>" \
    --output-format stream-json \
    --verbose \
    --allowedTools "Read,Grep,Glob,Bash(git:*),ReportFindings" \
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
- **Pracovní složka je `cwd` procesu.** Nedá se předat flagem, takže `ReviewRunner` bude
  potřebovat `cwd` v `ProcessRunning` (dnes tam není; `git` si vystačí s `-C`).

## `--allowedTools`: co doopravdy dělá

Nápověda ukazuje `"Bash(git *) Edit"` s mezerou, ale **funguje i `Bash(git:*)`** — ověřeno,
`git status --short` přes něj prošel.

Podstatnější je, co ten flag **není**:

| | |
|---|---|
| **Neomezuje seznam nástrojů** | Init event vypisuje všechny nástroje včetně `Write` a `Edit`, ať je v `--allowedTools` cokoli. Je to seznam **povolení**, ne dostupnosti |
| **Neomezuje `Bash` jen na uvedený vzor** | S `--allowedTools "Bash(git:*)"` prošly i `ls -la` a `cat soubor` |
| **Zápis přesto neprojde** | `touch`, `rm` i nástroj `Write` skončily chybou a soubory nevznikly |

Hranice tedy nevede podle vzoru v `--allowedTools`, ale podle toho, jestli je operace
**měnící**. Pro tvrdou podmínku „reviewer je read-only“ to dopadá dobře — mutace
strukturálně neprojdou — ale zdůvodnění v návrhu bylo chybné a je opravené.

Odmítnutí je ve streamu vidět dvakrát: jako `tool_result` s `is_error: true` a textem
`Claude requested permissions to …, but you haven't granted it yet.`, a souhrnně v `result`
eventu v poli `permission_denials` (`tool_name`, `tool_use_id`, `tool_input`). Běh přitom
skončí `subtype: "success"` a `is_error: false` — **odmítnutý nástroj není chyba běhu**.

## Tvar streamu

Jeden JSON objekt na řádek. Typy v pořadí, v jakém chodí:

| `type` / `subtype` | K čemu |
|---|---|
| `system` / `hook_started`, `hook_response` | Hooky uživatelova prostředí. Pro aplikaci šum |
| `system` / `init` | Start session — 22 klíčů, mimo jiné `session_id`, `cwd`, `model`, `tools`, `permissionMode` |
| `assistant` | Zpráva modelu; `message.content[]` nese bloky `text` a `tool_use` |
| `user` | Výsledky nástrojů; `message.content[]` nese bloky `tool_result` |
| `rate_limit_event` | Informace o limitech, chodí i uprostřed běhu |
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

Streamy jsou **surové**, nic se z nich nemazalo. Prošly kontrolou na tajemství (tokeny,
klíče, hesla, e-maily — nic).

Nesou ale lokální prostředí, a víc, než se na první pohled zdá: kromě jmen nainstalovaných
pluginů a cest pod `/Users/ondra` je v `hook_response.output.additionalContext` **celý text
některých skillů**, který si tam pověsil `SessionStart` hook. Je to i podstatná část objemu
fixtures. Repo je privátní, takže to je v pořádku — ale kdyby se někdy zveřejňovalo, tohle
je první místo ke kontrole, ne jen cesty.

Testovaný kód byl schválně chybný `Cart.swift` ve scratch repu (součet ignoruje množství,
celočíselné dělení u slevy, index bez kontroly prázdnosti) — v repu není, fixtures ho nesou
v obsahu streamu.
