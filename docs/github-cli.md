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
a příčina je vidět **jen v logu akce**. Jsou na to dvě známé příčiny a **pozná se to podle toho,
jestli job vůbec běžel**:

- **Job běžel a spadl** → velikost `CLAUDE.md` ([záznam
  rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447)).
- **Job nikdy nezačal** → request se spotřeboval, viz níž. Log v tom případě **není** (stažený zip
  má 138 B), takže se čte stav runu, ne jeho výstup.

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
GitHubu přesto proběhne**. Ověřuje se to zpětným čtením, ne návratovým kódem, a větev se pak
smaže přes REST:

```bash
gh api repos/{owner}/{repo}/pulls/<n> --jq '.merged'
gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<větev>
```
