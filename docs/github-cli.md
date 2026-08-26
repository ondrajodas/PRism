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

`gh pr create`, `gh pr list`, `gh pr merge` a `gh api` fungují normálně — zlobí jen ty dva.

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
a příčina je vidět **jen v logu akce**. Nejpravděpodobnější příčina je velikost `CLAUDE.md` —
rozbor je v [záznamu
rozhodnutí](superpowers/specs/2026-07-31-prism-design.md#claudemd-se-drží-malý-a-je-to-podmínka-ne-estetika-162-znovu-447).

## Merge z worktree

`gh pr merge` v pracovním stromě hlásí `fatal: 'main' is already used by worktree` — **merge na
GitHubu přesto proběhne**. Ověřuje se to zpětným čtením, ne návratovým kódem, a větev se pak
smaže přes REST:

```bash
gh api repos/{owner}/{repo}/pulls/<n> --jq '.merged'
gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<větev>
```
