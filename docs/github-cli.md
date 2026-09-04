# `gh` v tomhle repu — co padá a čím to nahradit

Sourozenec [`docs/claude-cli.md`](claude-cli.md): tam je ověřené chování Claude Code CLI, tady
`gh`. Všechno níž je **narazené v provozu na `ondrajodas/PRism`**, ne odvozené z dokumentace.
Pravidlo, které z toho plyne, je v `CLAUDE.md` (*Pracovní postup*); sem se chodí pro příkazy
a pro to, jak se výsledek čte.

Vyčleněno z `CLAUDE.md` u #447 — je to operační znalost o cizím nástroji, ne pravidlo, které
je potřeba znát dřív, než se něco napíše.

## Dva příkazy, které na tomhle repu spadnou

`gh pr edit` a `gh issue view` si tahají **`projectCards`** a padnou na deprecated Projects
classic **dřív, než něco udělají**. Není to chyba zadání ani autorizace a nedá se to obejít
flagem — čte a upravuje se proto přes REST:

```bash
gh api repos/{owner}/{repo}/issues/3 --jq .body          # číst popis issue
jq -Rs '{body: .}' telo.md > payload.json                # tělo z Markdownu do JSONu
gh api repos/{owner}/{repo}/pulls/32 -X PATCH --input payload.json    # přepsat popis PR
gh api repos/{owner}/{repo}/issues/447 -X PATCH -f state=closed -f state_reason=completed
```

`gh pr create`, `gh pr list` a `gh api` fungují normálně — na `projectCards` zlobí jen ty dva.
`gh pr merge` je **třetí případ, ale jiný**: z pracovního stromu skončí nenulově, a přesto
mergne — viz *Merge z worktree* níž.

**Jedna REST cesta chybí:** `POST pulls/comments/{id}/replies` vrací **404**. Odpověď na inline
komentář se posílá jako `POST pulls/{n}/comments` s `in_reply_to`.

## Copilot jako reviewer

**`gh pr edit --add-reviewer Copilot` bota nepřidá.** Na tomhle repu spadne na tomtéž
`projectCards` jako všechno ostatní přes `gh pr edit`, a REST `/requested_reviewers` vrátí
**200 a bota tiše zahodí** — takže to vypadá, že se to povedlo, a review nikdy nepřijde.
Funguje jedině GraphQL mutace `requestReviews` s `botIds`, kterou dělá
[`bin/copilot-review.sh`](../bin/copilot-review.sh):

```bash
./bin/copilot-review.sh <číslo PR>
```

### Výsledek se čte ze dvou míst a pod dvěma jmény

Review píše `copilot-pull-request-reviewer[bot]`, ale inline komentáře **`Copilot`**. Filtr
`startswith("copilot")` je navíc citlivý na velikost písmen, takže na komentáře nesedí — a při
čtení to vypadá, že žádné nejsou:

```bash
gh api repos/{owner}/{repo}/pulls/37/reviews \
    --jq '.[] | select(.user.login | startswith("copilot")) | .body'
gh api repos/{owner}/{repo}/pulls/37/comments \
    --jq '.[] | select(.user.login | ascii_downcase | startswith("copilot")) |
          "\(.id) \(.path):\(.line)\n\(.body)"'
```

### „Generated no new comments“ neznamená, že nic nenašel

Část nálezů se schová do sekce *Suppressed comments* **uvnitř těla review** a v inline
komentářích nejsou vůbec. Tělo se proto musí přečíst celé — u #8 tam takhle ležely **dva reálné
nálezy** pod hlavičkou, že nové komentáře nejsou.

### Když nedoběhne vůbec

Do review napíše jen „Copilot encountered an error and was unable to review this pull request“
a příčina je vidět **jen v logu akce**. Jsou na to **tři** známé příčiny; první dvě se poznají
podle toho, **jestli job vůbec běžel**, tu třetí odliší až text chyby v logu:

- **Job běžel a spadl** → velikost `CLAUDE.md` ([záznam
  rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447-potřetí-496)).
- **Job nikdy nezačal** → request se spotřeboval, viz níž. Log v tom případě **není** (stažený zip
  má 138 B), takže se čte stav runu, ne jeho výstup.
- **Job běžel, spadl po dvou sekundách a v logu stojí `Resource not accessible by integration`**
  → výpadek na straně GitHubu, ne nic u nás. Viz hned níž.

### Když Copilot nevidí na pull request (#542, PR #564)

Job se rozjede, po dvou sekundách skončí a v logu stojí:

```
Fetching PR metadata for ondrajodas/PRism#564
HttpError: Resource not accessible by integration - .../rest/pulls/pulls#get-a-pull-request
Error creating PR review request: … Failed to fetch PR metadata for ondrajodas/PRism#564
```

**Není to velikost `CLAUDE.md`** — ta se u #542 nezměnila a téhož dne ve 14:20 na ní jiné kolo
doběhlo do `success`. Poznávací znamení je, že to **netrefuje jeden pull request**: ve stejné
minutě spadlo se stejnou hláškou i kolo nad `PRism#565` z cizí větve. Bot v tu chvíli nemá právo
přečíst si `GET /pulls/{n}`, tedy potíž instalace GitHub Appky, na kterou z repa nedosáhneme.

**Vyžádat znovu pomůže jedině tehdy, když výpadek mezitím skončil.** U #542 se to zkusilo
**třikrát** (20:46, 20:48, 20:56) a pokaždé to spadlo stejně; run přitom pokaždé **vznikl a běžel**,
takže to není spotřebovaný request z odstavce níž a `union: false` na tom nic nezmění. Cesta ven je
počkat a zkusit to znovu později — a do té doby to **hlásit jako neověřenou mezeru**, ne mergovat
s tím, že „Copilot nic nenašel“: nic nepřečetl.

```bash
# Rozpoznání: běžel job, a proč spadl.
gh api repos/{owner}/{repo}/actions/runs/{id}/jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
gh run view {id} --log-failed | grep -E "HttpError|PRism#[0-9]+"
```

### Když se request spotřebuje mrtvým jobem

Narazilo se na to u **#452 / PR #458** a stálo to čtyři a půl hodiny ticha. Rozpoznává se
**jménem workflow**, ne stavem — GitHub u toho hlásí stav, který neplatí:

```bash
gh api "repos/{owner}/{repo}/actions/runs?per_page=5" \
    --jq '.workflow_runs[] | "\(.id) \(.name) \(.status) \(.conclusion) \(.created_at)"'
```

Zdravé kolo běží jako **`Running Copilot Code Review`** a doběhne do jednotek minut (změřeno:
request 13:34:37Z → run `32975049374` v 13:34:55Z → review 13:40:26Z, tedy **6 minut**). Zaseknuté
kolo vyrobí run se jménem **`dynamic`**: `32985107256` vznikl 15:25:44Z, zůstal `status: queued`
a v 20:00:54Z, tedy **po čtyřech a půl hodinách**, byl pořád `queued` s `updated_at` rovným času
vzniku. Nikdy nezačal.

Tři věci, které z toho plynou a nejsou zjevné:

- **`requested_reviewers` je přitom prázdné.** Request je už *spotřebovaný* tím mrtvým jobem, takže
  se v seznamu neobjeví — a „Copilot tam není“ tedy **neznamená** „nikdo ho nevyžádal“.
- **Vyžádat znovu nic neudělá.** `bin/copilot-review.sh` jede `requestReviews` s **`union: true`**,
  tedy *přidej do sady*; na sadu, kterou GitHub v tu chvíli drží za obsazenou, se tím nepřidá nic.
  Změřeno: skript v 16:29:06Z ohlásil úspěch a **nevznikl ani nový run, ani nový
  `review_requested` event** v timeline.
- **Zaseknutý run nejde zrušit.** `POST actions/runs/{id}/cancel` i force-cancel vrátí **409
  `Cannot cancel a workflow run that has not been queued yet`** — a to přesto, že tentýž run přes
  API hlásí `status: queued`. Je v limbu a zůstane tam; **nezkoušej to**.

**Cesta ven je sadu vyprázdnit a vyžádat znovu.** `union: false` s prázdnými seznamy resetuje to,
co GitHub drží za obsazené:

```bash
PR_ID=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) { pullRequest(number: $number) { id } }
    }' -f owner=ondrajodas -f repo=PRism -F number=458 \
    --jq '.data.repository.pullRequest.id')

gh api graphql -f query='
    mutation($pr: ID!) {
        requestReviews(input: {pullRequestId: $pr, botIds: [], userIds: [], union: false}) {
            pullRequest { number }
        }
    }' -f pr="$PR_ID"

./bin/copilot-review.sh 458
```

Po tomhle vznikl run `33008048161` **se jménem `Running Copilot Code Review`**, tedy pod tím, pod
kterým běhala všechna úspěšná kola. Mrtvý request se mezitím ozval jedině **chybovým review**
(`5032835395`, 16:37:05Z) — a nebyla to velikost `CLAUDE.md`, ta měla 68 386 B, tedy hluboko pod
stropem.

**Do skriptu se to nedává, a je to rozhodnutí, ne lenost.** `union: false` s prázdnými seznamy je
**destruktivní**: nesmaže jen Copilota, ale **všechny vyžádané reviewery včetně lidí**. Skript se
pouští na každý PR, takže by z rutinního kroku udělal krok, který umí potichu sundat kolegovo
vyžádané review. Udělat to *jen když je to zaseknuté* by znamenalo poznat „zaseknuté“ z výpisu
runů — tedy z **`queued`, o kterém tahle sekce dokládá, že neplatí**. Za jeden výskyt to tolik
mechaniky nestojí; ruční postup výš je pět řádků a je vidět, co dělá.

## Merge z worktree

`gh pr merge` v pracovním stromě hlásí `fatal: 'main' is already used by worktree` — **merge na
GitHubu přesto proběhne**. Padá na tom **lokální** krok za mergem (typicky `--delete-branch`),
který si chce přepnout na základní větev, a tu drží hlavní strom; vzdálená část je v tu chvíli
hotová. Ověřuje se to zpětným čtením, ne návratovým kódem, a větev se pak smaže přes REST:

```bash
gh api repos/{owner}/{repo}/pulls/<n> --jq '.merged'
gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<větev>
```

## Merge přes API — co je změřené (#465)

Aplikace merguje `PUT /repos/{repo}/pulls/{n}/merge` (osmá metoda `ReviewPublishing`). Změřeno na
sondě `ondrajodas/prism-review-sandbox#8`, která tam byla pro tenhle účel založená, třikrát
pushnutá a nakonec mergnutá:

- **Úspěšná odpověď** je krátká a nese commit, který vznikl:

  ```json
  {"sha":"d5e454dd…","merged":true,"message":"Pull Request successfully merged"}
  ```

- **`sha` v payloadu je podmínka, ne údaj.** S cizí hodnotou vrátí GitHub `409`:

  ```json
  {"message":"Head branch was modified. Review and try the merge again.","status":"409"}
  ```

  `gh` to na stderr vypíše jako `gh: Head branch was modified. Review and try the merge again.
  (HTTP 409)`. Je to jediná ochrana, která zabere i na commit pushnutý **mezi** pre-flightem
  a voláním — u review taková možnost není, `commit_id` je tam údaj a zastaralé review projde
  (změřeno u #62).

- **`commit_title` se posílá, `commit_message` ne.** Výsledný squash commit měl titulek přesně
  ten, který šel v `commit_title`, a pod ním odrážky se **zprávami slévaných commitů** — tedy
  tělo, které GitHub složil sám. Tak vypadá celá historie `main`u v tomhle repu, takže se
  neposílá; kdo by ho poslal prázdné, tu prózu mergem zahodí.

- **`mergeable` a `mergeStateStatus` jsou líná pole.** Odpověď se počítá až na vyžádání a dotaz,
  který ji nezastihne hotovou, dostane `UNKNOWN` (v RESTu `null`) — a **sám ten výpočet spustí**.
  Co se povedlo změřit: mergnutý PR vrací `UNKNOWN` **navždycky** (`PRism#470`, obě pole). Co se
  změřit **nepovedlo**: zastihnout `UNKNOWN` na živém PR. Na sondě vyšlo `MERGEABLE`/`CLEAN` hned
  po založení PR i hned po každém ze tří pushů, přes `gh pr view` i přes REST.

- **`mergeStateStatus` vydá GitHub jen tomu, kdo má na repozitář zápis** — jinak vrací `BLOCKED`.
  Změřeno na `cli/cli#14278`, kde vyšlo `{"mergeStateStatus":"BLOCKED","mergeable":"MERGEABLE"}`.
  Věta v aplikaci proto nesmí `BLOCKED` překládat na „červený check“: znamená kterýkoli
  z „chybí schválení / běží povinný check / nemáš zápis“ a GitHub nedává, který.

- **`405` nad draftem změřený je od #482** (do té doby tady stálo, že převedení sondy na draft
  zakázala permission brána). Zpráva ale **není** `Pull Request is not mergeable`, nýbrž `Pull
  Request is still a draft` — podrobnosti a co z toho plyne pro `PublishError` jsou v sekci
  *Ready for review* níž. `405` u PR **v konfliktu** změřený pořád není a text v aplikaci je u něj
  z dokumentace GitHubu.

## Ready for review — co je změřené (#482)

Aplikace přepíná vlastní draft na *ready for review* přes **`gh pr ready <n> --repo <repo>`**
(devátá metoda `ReviewPublishing`). Změřeno na `ondrajodas/prism-review-sandbox#11`, což je draft
PR založený pro tenhle účel a opakovaně přepnutý tam a zpátky; **PR zůstává draft**, takže se každé
tvrzení níž dá přeměřit znovu — kolik kol to bylo, vypíše
`gh api repos/ondrajodas/prism-review-sandbox/issues/11/timeline --jq '.[].event'`.

**REST na tuhle věc endpoint nemá, a je to ta nejdůležitější půlka měření.** `PATCH
/repos/{repo}/pulls/{n}` s `draft=false` vrátí **`200` a přepnutí tiše zahodí** — v odpovědi na ten
samý dotaz stojí `"draft": true`:

```bash
gh api repos/ondrajodas/prism-review-sandbox/pulls/11 -X PATCH -F draft=false --jq .draft   # true
```

Je to **tatáž past** jako `POST /requested_reviewers` s Copilotem výš: úspěšné volání, po kterém se
nestalo nic. Kdo bude tuhle cestu předělávat, musí ji ověřovat **zpětným čtením**, ne návratovým
kódem.

**Co `gh pr ready --repo` doopravdy dělá** (stdout je u všech případů prázdný, věta jde na stderr):

| Situace | Kód | stderr |
|---|---|---|
| draft, z `/` i z git worktree | 0 | `✓ … is marked as "ready for review"` |
| PR, který draft **není** | 0 | `! … is already "ready for review"` |
| neexistující číslo PR | 1 | `GraphQL: Could not resolve to a PullRequest with the number of 9999.` |
| neplatný token | 1 | `HTTP 401: Bad credentials` + `Try authenticating with:  gh auth login` |

Tři věci z toho plynou:

- **Není to `gh pr merge`.** S `--repo` funguje **i z pracovního stromu** a skončí nulou — do
  lokálního repa nesahá vůbec. `--repo` je přitom povinné, ne úsporné: aplikace podprocesu
  nenastavuje pracovní složku, takže bez něj si `gh` repozitář hádá z toho, kde zrovna stojí.
- **Je to idempotentní.** Nad PR, který draft není, skončí nulou — dvojklik ani závod
  s prohlížečem tedy nevyrobí chybu, kterou by bylo potřeba někde ukázat.
- **Úspěch se nedá dekódovat, jen přečíst z návratového kódu.** Nový stav si proto aplikace
  **načte znovu** (`AppStore.pullRequestBecameReady`), stejně jako po vlastním mergi.

**GraphQL mutace `markPullRequestReadyForReview` funguje taky, a je zamítnutá.** Chce **node ID**
pull requestu, které aplikace nemá odkud vzít (`PullRequest` je `Codable` a persistovaný, takže by
to bylo další volitelné pole a s ním další „nevím“, které musí blokovat). Přitěžující okolnost je
změřená: nad neplatným ID hlásí

```
Could not resolve to a node with the global id of 'PR_bogus'
```

a na tomhle textu vydá `PublishError.init(failure:)` **`threadNotFound`** — tedy věta o vlákně nad
přepnutím draftu. Do draftu se PR vrací **opačnou** mutací (`convertPullRequestToDraft`); ta v
aplikaci **není a nebude** (tvrdá podmínka č. 1), ale při měření je to ona, čím se sonda resetuje:

```bash
gh api graphql -F id=<node id> -f query='
  mutation($id:ID!){convertPullRequestToDraft(input:{pullRequestId:$id}){pullRequest{isDraft}}}'
```

### Dvě věci, které tím měřením zavřely starší mezery

- **`405` u merge nad draftem už změřený je** (u #465 to zakázala permission brána, viz sekce
  výš). Zpráva ale **není** `Pull Request is not mergeable`, nýbrž:

  ```json
  {"message":"Pull Request is still a draft","status":"405"}
  ```

  Na tenhle text tedy `PublishError.notMergeable` **nesedí** a selhání by vyšlo jako `unknown`
  („Odeslání se nepovedlo: …“). Neopravuje se to a je to rozhodnutí: aplikace merge nad draftem
  **neposílá** (`Policy.mergeOffer` vydá `draftPullRequest`), takže by to byl případ bez volajícího
  — a věta `unknown` je pravdivá, jen neurčitá.
- **Vyžádání review od `CODEOWNERS` se potvrdit nepodařilo, a je to zapsaná mezera.** Změřeno je
  jen to, že s `CODEOWNERS` `* @ondrajodas` na základové větvi a s autorem `ondrajodas`
  se po přepnutí **žádný `review_requested` neobjeví** (timeline nese jen `ready_for_review`) —
  GitHub o review nikdy nežádá autora. Že se **jiný** vlastník kódu vyžádá, chce druhý účet se
  zápisem do sandboxu; věta pod tlačítkem v aplikaci je proto z dokumentace GitHubu, ne z měření.
