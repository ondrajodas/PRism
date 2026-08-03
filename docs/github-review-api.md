# Zápisové review API GitHubu — co je ověřené

**Ověřeno:** 2026-08-03 · **repo:** `ondrajodas/prism-review-sandbox` (soukromý) ·
**přes:** `gh api --input payload.json`

Spike k issue #62. Celý milník M6 stojí na předpokladu, že **review odejde jedním atomickým
voláním** (`POST /pulls/{n}/reviews` s `event`, `body` a polem `comments[]`) — a to se muselo
potvrdit dřív, než vznikne první řádek zápisového kódu. Všechno níž je ověřené voláním, ne
odvozené z dokumentace; kde se dokumentace k věci nevyjadřuje, je to napsané.

**Žádný appkový kód** — stejně jako spike #12. Tvrdá podmínka č. 1 („aplikace je vůči
GitHubu jen pro čtení“) zůstává v platnosti; ruší ji až #67.

Tvary chybových odpovědí leží jako fixtures v [`Tests/Fixtures/gh/`](../Tests/Fixtures/gh)
(`review-error-*.json`).

## Prostředí měření

Testovací PR zakládá workflow v sandboxu:

```bash
gh workflow run "Založit testovací PR" --repo ondrajodas/prism-review-sandbox
```

Autorem je `github-actions[bot]`, takže na těch PR jde `APPROVE` i `REQUEST_CHANGES`.
`Cart.php` má 52 řádků a mění se jediný uprostřed, takže jsou k dispozici všechny tři druhy
řádků naráz. Nad PR #4 vycházela čísla takhle:

| Druh řádku | Čísla (nový soubor) |
|---|---|
| Změněný (v hunku) | 28 |
| Kontextový (v hunku) | 25–27, 29–31 |
| Mimo hunky | 1–24, 32–52 |

Použité PR: **#4** (Q1, Q2, Q3, Q6), **#5** (Q5, Q4b), **#2** (Q4a), **#6** (Q7 — vlastní PR).
Zůstávají v sandboxu jako doklad; review id jsou v odpovědích níž.

## 1. Review s verdiktem i řádkovými komentáři odejde jedním voláním

**Ano.** Jedno `POST` s `event: REQUEST_CHANGES`, `body` a dvěma položkami v `comments[]`
vytvořilo review `4843112462` ve stavu `CHANGES_REQUESTED` se dvěma řádkovými komentáři.
Žádné druhé volání, žádné „nejdřív pending, pak submit“.

```json
{
  "commit_id": "<plný sha>",
  "body": "…",
  "event": "REQUEST_CHANGES",
  "comments": [
    { "path": "Cart.php", "line": 28, "side": "RIGHT", "body": "…" }
  ]
}
```

Předpoklad, na kterém stojí návrh M6, tedy platí. `ReviewPublisher` (#67) může být jedno
hrdlo s jedním voláním a nemusí umět částečné selhání.

## 2. Jeden komentář mimo diff → 422 a neodešle se nic

**Potvrzeno, a je to to hlavní zjištění.** Payload s **jedním platným** komentářem (řádek 28)
a **jedním neplatným** (řádek 5, mimo hunky) skončil:

```
422 {"message":"Unprocessable Entity","errors":["Line could not be resolved"]}
```

A po něm na PR **nezůstalo nic** — `reviews: 0`, `pulls/N/comments: 0`,
`issues/N/comments: 0`. Ani ten platný komentář.

Volání je tedy atomické: buď projde celé, nebo se nestane nic.

Co z toho **neplyne**: že aplikace nemusí nálezy podle diffu rozřazovat. Rozřadit je musí
tak jako tak, protože nález mimo hunky se má poslat jako permalink v těle (viz bod 6), ne
jako řádkový komentář — a to je rozhodnutí, které se dělá před odesláním. Data na to
v aplikaci **už jsou**: `DiffRow.anchor(in:file:line:)` příslušnost k hunku řeší od #19,
protože na ní stojí bubliny s `anchored: false`.

Co z toho plyne: **chyba v tom rozřazení je bezpečná.** Když se aplikace o řádku spletla,
GitHub odmítne celé review a na PR nezůstane nic — takže `ReviewPublisher` nepotřebuje
druhou, obrannou validaci nad tou první, ani úklid po částečném odeslání. Kdyby volání
procházelo částečně, znamenal by jeden špatně zařazený nález půlku review na PR kolegy,
kterou nelze vzít zpátky — a to je rozdíl mezi „pošli a reaguj na 422“ a „ověř dvakrát,
protože omyl je nevratný“.

Fixture: `review-error-line-outside-diff.json`

## 3. Kontextový řádek hunku komentovat jde, řádek mimo hunky ne

| Řádek | Druh | Výsledek |
|---|---|---|
| 28 | změněný v hunku | přijat |
| 26 | **kontextový** v hunku (nezměněný) | **přijat** |
| 5 | mimo hunky | 422 `Line could not be resolved` |

Rozhoduje tedy příslušnost k hunku, ne to, jestli se řádek změnil. Oba přijaté komentáře
vyšly jako `subject_type: "line"`, `side: "RIGHT"`.

## 4. `commit_id`, když mezitím přijde nový commit

Odpověď je dvojí a **první polovina je riziko**:

**Zastaralé `commit_id` se přijme.** Na PR #2 se head posunul (`0721c3ff` → `645f686c`)
a review poslané se **starým** sha prošlo (`4843128805`, `state: COMMENTED`), pinnuté na
starý commit. GitHub tedy proti odeslání review proti neexistujícímu stavu **nechrání** —
kontrola musí být v aplikaci, těsně před odesláním. Je to tentýž důvod, kvůli kterému jsou
nálezy klíčované `headSha` (tvrdá podmínka č. 5).

**Zastarání se pozná na `line`, ne na `position`.** Když komentovanému řádku zmizí kotva:

| Pole | Před | Po |
|---|---|---|
| `line` | 28 | **`null`** |
| `original_line` | 28 | 28 |
| `position` | 5 | 1 |
| `original_position` | 5 | 5 |
| `commit_id` | starý sha | starý sha (nemění se) |

Signál je tedy `line == nil` při zachovaném `original_line`. **`position` spolehlivý není** —
zůstalo nenulové.

**Omezení měření:** zastarání jsem vynutil tím, že jsem botovu změnu vrátil, čímž diff PR
vyšel **úplně prázdný**. To je krajní varianta. Mezistav „řádek se posunul, ale v diffu
zůstal“ neměřený — pro #69 (přenesení draftu na nový commit) ho bude potřeba doměřit,
protože právě on rozhoduje, jestli se dá kotva přepočítat, nebo se komentář musí zahodit.

## 5. Když už na PR leží rozepsané (pending) review

**422 s rozlišitelnou hláškou:**

```
422 {"message":"Unprocessable Entity",
     "errors":["User can only have one pending review per pull request"]}
```

Pending review vzniká `POST`em **bez `event`** (vrátí `state: PENDING`) — tak ho zakládá
i prohlížeč. Odeslání z aplikace tedy zablokuje rozepsané review, o kterém aplikace neví.

**Cesta zpátky existuje:** `DELETE /pulls/{n}/reviews/{review_id}` pending review smaže
(ověřeno, PR se vrátil na `reviews: 0`). Jestli ho aplikace smí mazat sama, je rozhodnutí
pro #67 — je to cizí rozdělaná práce, ne naše.

Fixture: `review-error-pending-exists.json`

## 6. Permalink v těle review se vyrenderuje jako úryvek kódu

**Ano, a je to použitelnější, než zadání čekalo.** `body_html` (přes
`Accept: application/vnd.github.html+json`) obsahuje místo odkazu celý blok s hlavičkou
`prism-review-sandbox/Cart.php`, číslem řádku, odkazem na commit a **obarveným** obsahem
řádku (`<span class="pl-k">final</span>`).

Funguje jednotlivý řádek i **rozsah**:

```
https://github.com/o/r/blob/<sha>/Cart.php#L5
https://github.com/o/r/blob/<sha>/Cart.php#L40-L43
```

Je to tím odpověď na problém z bodu 2: nález mimo diff nemůže být řádkovým komentářem, ale
**v těle review se dá ukázat jako skutečný úryvek kódu** — takže se nemusí zahodit ani
degradovat na holou cestu s číslem řádku.

## 7. Verdikt na vlastním PR

Zadání se ptalo na `APPROVE`. Zakázané je ale **i `REQUEST_CHANGES`**:

| `event` | Výsledek na vlastním PR |
|---|---|
| `APPROVE` | 422 `Review Can not approve your own pull request` |
| `REQUEST_CHANGES` | 422 `Review Can not request changes on your own pull request` |
| `COMMENT` | **projde** (`state: COMMENTED`) |

Na vlastním PR tedy z aplikace nejde poslat žádný verdikt, jen komentované review. A protože
`Policy.suggestedVerdict` umí právě `approve` a `requestChanges`, musí #68 tenhle stav
rozpoznat dřív, než nabídne tlačítko — jinak si o odeslání řekne a dostane 422.

Fixtures: `review-error-approve-own-pr.json`, `review-error-request-changes-own-pr.json`

## Mimo zadání: `commit_id` musí být plný sha

Zkrácený sha (`5b6250cb`) API odmítne:

```
422 {"message":"Unprocessable Entity",
     "errors":["Variable $commitOID of type GitObjectID was provided invalid value"]}
```

Aplikace plný `headSha` má (`gh pr view` ho vrací celý), takže to nic nemění — ale je to
past pro ruční zkoušení a hláška o příčině nemluví.

Fixture: `review-error-abbreviated-sha.json`

## Co z toho plyne pro návrh

| Zjištění | Dopad |
|---|---|
| Volání je atomické (1, 2) | `ReviewPublisher` (#67) je jedno volání, nemusí řešit částečné selhání ani mít obrannou validaci nad rozřazením nálezů — omyl v něm skončí 422 bez následků. Rozřadit nálezy podle hunků ale musí (bod 6), a `DiffRow.anchor` na to v aplikaci už je |
| Zastaralé `commit_id` se přijme (4) | Kontrola `headSha` musí být v aplikaci těsně před odesláním; GitHub ji neudělá |
| `line == nil` je signál zastarání (4) | Na tom postaví #69; `position` se použít nedá |
| Pending review blokuje (5) | #67 potřebuje vlastní stav pro „na PR leží cizí rozdělané review“ |
| Permalink renderuje úryvek (6) | Nález mimo diff se do review dostane v těle, ne zahozením |
| Na vlastním PR jen `COMMENT` (7) | #68 musí verdikt schovat, ne ho nabídnout a spadnout na 422 |

## Fixtures

| Soubor | Co dokazuje |
|---|---|
| `review-error-line-outside-diff.json` | 422 u komentáře mimo hunky — a že s ním padá celé review |
| `review-error-pending-exists.json` | 422, když na PR leží pending review |
| `review-error-approve-own-pr.json` | Zákaz `APPROVE` na vlastním PR |
| `review-error-request-changes-own-pr.json` | Zákaz `REQUEST_CHANGES` na vlastním PR |
| `review-error-abbreviated-sha.json` | Zkrácený `commit_id` se odmítne |

Jsou to **skutečné** odpovědi API, jen přeformátované `jq` — stejně jako fixtures v
`Fixtures/gh/`. Neobsahují tokeny ani nic z privátních rep; sandbox je testovací repo
založené na tohle.
