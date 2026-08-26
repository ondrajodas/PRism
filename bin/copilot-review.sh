#!/usr/bin/env bash
# Vyžádá na PR review od GitHub Copilota.
#
# Proč skript a ne `gh pr edit --add-reviewer Copilot`: ten na tomhle repu padá na
# deprecated Projects classic (`repository.pullRequest.projectCards`) a reviewer se
# nepřidá. REST endpoint /requested_reviewers vrátí 200, ale bota tiše ignoruje.
# Funguje jedině GraphQL mutace requestReviews s botIds.
#
# `union: true` je schvalne: pridava do sady, takze nesundava reviewery, ktere uz PR ma.
# Cena je, ze na spotrebovany request (job, ktery se zasekl a nikdy nezacal) tenhle skript
# nema ucinek — vyzada se to znovu az po vyprazdneni sady. Postup i mereni jsou
# v docs/github-cli.md, sekce "Kdyz se request spotrebuje mrtvym jobem".
set -euo pipefail

PR="${1:?použití: bin/copilot-review.sh <číslo PR>}"

# Globální node id bota copilot-pull-request-reviewer. Dá se znovu zjistit z timeline
# PR, na kterém už Copilot review dělal:
#   gh api repos/{owner}/{repo}/issues/<n>/timeline \
#     --jq '.[] | select(.event=="review_requested") | .requested_reviewer.node_id'
COPILOT_BOT_ID="BOT_kgDOCnlnWA"

PR_ID=$(gh api graphql \
    -f query='
        query($owner: String!, $repo: String!, $number: Int!) {
            repository(owner: $owner, name: $repo) {
                pullRequest(number: $number) { id }
            }
        }' \
    -f owner="$(gh repo view --json owner --jq .owner.login)" \
    -f repo="$(gh repo view --json name --jq .name)" \
    -F number="$PR" \
    --jq '.data.repository.pullRequest.id')

gh api graphql \
    -f query='
        mutation($pr: ID!, $bots: [ID!]) {
            requestReviews(input: {pullRequestId: $pr, botIds: $bots, union: true}) {
                pullRequest { number }
            }
        }' \
    -f pr="$PR_ID" \
    -f bots="$COPILOT_BOT_ID" \
    --jq '"Copilot review vyžádáno na PR #\(.data.requestReviews.pullRequest.number)"'
