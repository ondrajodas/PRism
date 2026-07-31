# pr-review — Design

**Date:** 2026-07-31
**Status:** Approved design, not yet implemented
**Repo:** `ondrajodas/pr-review` (private)

## Purpose

A native macOS app that watches GitHub pull requests assigned to me for review, runs
Claude Code review skills against them, and shows the findings in a native UI next to
the diff.

The app is an **orchestrator and a viewer**. It contains no review logic of its own —
all analysis lives in Claude Code skills. The app decides *when* to run *which* skill
*where*, captures structured output, and renders it.

## Non-goals

- **Nothing is ever posted to GitHub.** No comments, no reviews, no approvals. The
  verdict is a suggestion rendered in the app. This is a hard constraint, not a v1
  simplification.
- **No embedded terminal in v1.** Deferred (see Future work).
- **No GitLab / Bitbucket.** GitHub-only, hardcoded. Pretending otherwise would be
  wasted abstraction.
- **No CI replacement.** The app reviews code, it does not run the project's tests.

## Scope (v1)

| Aspect | Decision |
|---|---|
| PR source | `review-requested:@me` |
| Repositories | Any repo, not a fixed list |
| Review trigger | Button (manual) by default; auto mode opt-in per repo |
| Reviewers | Multiple skills, run independently and concurrently |
| Result model | Parallel opinions — no cross-reviewer merging of finding text |
| Checkout | Own cache, partial clone, one git worktree per review |
| Reviewer permissions | Read-only (no `Write`/`Edit` tools) |
| Output capture | `ReportFindings` tool calls from the `stream-json` event stream |

## Architecture

Seven modules with explicit boundaries. Each one is independently testable; the three
that touch the outside world sit behind protocols so they can be faked in tests.

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI views  (PRList, DiffView, FindingsPanel)       │
└───────────────────────┬─────────────────────────────────┘
                        │ observes
┌───────────────────────▼─────────────────────────────────┐
│  AppStore — owns state, coordinates, enforces limits    │
└──┬──────────┬──────────────┬───────────────┬────────────┘
   │          │              │               │
┌──▼───────┐┌─▼───────────┐┌─▼───────────┐┌──▼──────────┐
│GitHub    ││RepoCheckout ││ReviewRunner ││ReviewStore  │
│Gateway   ││             ││             ││             │
│(gh CLI)  ││(git)        ││(claude CLI) ││(disk)       │
└──────────┘└─────────────┘└─────────────┘└─────────────┘
                                  │ uses
                        ┌─────────▼──────────┐
                        │ Policy (pure fns)  │
                        │ Config (global +   │
                        │        per-repo)   │
                        └────────────────────┘
```

### 1. GitHubGateway

Wraps the `gh` CLI. **The app never handles a GitHub token** — authentication is
delegated entirely to `gh`, which already holds the credential in the keychain. This
removes token storage, refresh and revocation from the app's problem space.

Responsibilities:

- List PRs from a configured list of **sources**. A source is one search query. v1 ships
  a single source (`review-requested:@me`); adding team review requests later is a new
  config entry, not a code change.
- Merge and deduplicate results across sources by `owner/repo#number`.
- Fetch PR metadata: title, author, `headSha`, `baseSha`, URL, `updatedAt`, state.
- Fetch the diff for display (`gh pr diff`) — display only; reviewers read real files.

Polling on an interval (default 60s). One search query per source per poll is well
within GitHub's authenticated search rate limit.

### 2. RepoCheckout

Owns all working copies. **Never touches the user's own clones** — they may be dirty, on
another branch, or already have worktrees.

```
~/Library/Application Support/pr-review/
  repos/<owner>/<repo>.git          # bare, --filter=blob:none partial clone
  worktrees/<owner>-<repo>-<pr>-<sha>/   # detached worktree per review
```

- First encounter with a repo: `git clone --bare --filter=blob:none`. Blobs are fetched
  on demand, so even large monorepos clone in seconds rather than minutes.
- Per review: `git worktree add --detach <path> <headSha>`. Concurrent reviewers each
  get their own worktree, so they cannot interfere.
- Cleanup: remove the worktree when its reviews finish; evict a repo's cache when its
  last PR closes, or by LRU above a configurable size budget.

The clone is visible in the UI as a distinct `cloning` state — on an unfamiliar repo it
is genuinely perceptible, and showing it beats pretending the PR is not ready yet.

### 3. ReviewRunner

Spawns one Claude Code session per skill and turns its output into findings.

```
claude -p "<prompt>"
  --output-format stream-json --verbose
  --allowedTools Read,Grep,Glob,Bash(git:*)
  --model <configured>
  cwd: <worktree path>
```

- **Read-only by policy.** `--allowedTools` excludes `Write`, `Edit` and general `Bash`.
  This is both a safety property (a reviewer structurally cannot modify code or send
  anything anywhere) and a practical one: it removes almost every reason Claude would
  stop to ask for permission. A headless session cannot answer a permission prompt, so
  it would otherwise hang until timeout.
- **A repo's own `CLAUDE.md` is picked up for free**, because the session's cwd is a real
  checkout. Project conventions apply without the app transporting anything.
- **`session_id` is captured** from the stream's init event and stored, even though v1
  has no terminal. It costs one string and keeps two doors open: a future embedded
  terminal, or a *Copy `claude --resume <id>`* button.
- Findings come from **`ReportFindings` tool calls** intercepted in the event stream —
  structured JSON, not parsed prose. A text-parsing fallback handles skills that do not
  use the tool.
- Every run has a wall-clock timeout and is cancellable. Concurrency is capped globally
  (default 3 sessions) so a batch of PRs cannot saturate the machine or the account.

Runs are keyed by `(repo, prNumber, headSha, skillId)`. When new commits land, the
`headSha` changes and prior findings are marked **stale** rather than silently shown
against code that no longer exists.

### 4. ReviewStore

Persistence. `Codable` models in JSON files under Application Support, one file per
`(repo, pr, headSha)`. Chosen over SwiftData for v1 because the data is small, the
access pattern is trivially file-shaped, and plain `Codable` keeps the store fake-able
in tests without a database.

### 5. Policy — pure functions, no I/O

This is where the severity question landed, and the design deliberately **does not
invent a severity scale**. `ReportFindings` has no severity field; it has `category` (a
free-form kebab-case slug naming the *kind* of issue) and `verdict`
(`CONFIRMED` / `PLAUSIBLE`). Both are real data produced by the reviewer.

- **Grouping in the UI is by `category`** — the reviewer's own naming, not the app's
  interpretation. Within a group, `CONFIRMED` sorts above `PLAUSIBLE`.
- **Blocking is a single derived boolean:** a finding blocks when
  `verdict == CONFIRMED` **and** `category ∈ blockingCategories`
  (default `correctness`, `security`, `data-loss`; configurable).
- **Verdict suggestion is mechanical:** any blocking finding → *Request changes*,
  otherwise → *Approve*. No aggregation session, no extra cost, nothing to tune in
  prompts.
- **Consensus is mechanical too:** two reviewers reporting the same `file:line`
  independently are shown as one bubble badged `2×`. Their texts are never merged.

Consequence worth stating: **no skill needs to be rewritten.** The `blockingCategories`
set is the single knob for tuning what counts as serious.

### 6. Config

Two levels, resolved global → per-repo:

```
Global:   sources[], skills[], blockingCategories[], pollInterval,
          maxConcurrentReviews, model, cacheBudget
Per-repo: mode: auto | manual        # default: manual
          skills[]                   # override, e.g. drop PHP skills on a Go repo
          blockingCategories[]       # override
```

**New repositories default to `manual`.** With arbitrary repos in scope, an unknown repo
must not spend a full panel of Claude sessions unattended; it appears in the list and
waits for the button. `auto` is opted into per repo where it is wanted.

Skills are per-repo for a concrete reason: `oj-php-quality-check` on a Go or TypeScript
repo buys nothing and still costs a session. Language autodetection seeds the default
set on first encounter.

## UI

Three regions. Chosen shape: full-width diff with findings anchored at the code, plus a
tabbed panel below.

```
┌────────────┬──────────────────────────────────────────────┐
│ PR list    │ reviewer chips (state + filter) │ verdict    │
│ (mixed     ├──────────────────────────────────────────────┤
│  repos,    │ diff, full width                             │
│  review    │   bubble: must-fix, code-review + security 2× │
│  state)    │ diff continues                               │
│            ├──────────────────────────────────────────────┤
│            │ [ Findings · 9 ] [ Progress ]                │
│            │ table: category │ reviewer │ file:line │ …    │
└────────────┴──────────────────────────────────────────────┘
```

- **Main window is the PR list**, mixing repositories, each row showing review state
  (`3 blocking`, `running 2/3`, `clean`, `queued · cloning`, `stale`).
- **Diff gets the full width.** 120-character PHP lines fit.
- **Findings appear as bubbles at their `file:line`**, defaulted on, toggleable.
- **Findings without a line** (missing tests, architectural notes) live in the table.
  This is exactly why the table exists rather than bubbles alone.
- **Reviewer chips do double duty:** state (`✓ done · 5`, `◐ running`, `✕ off for this
  repo`) and filter.
- **Verdict is labelled a suggestion** and has no GitHub action attached to it.
- **Progress tab** renders the live `stream-json` event stream natively — which file the
  reviewer is reading, which tool it called. Structured rendering, not ANSI passthrough.

## Platform decisions

- **SwiftUI**, macOS 26 target, Xcode project committed. Bundle id
  `com.ondrajodas.pr-review`.
- **App Sandbox is off.** The app spawns `git`, `gh` and `claude` and writes to its cache
  outside a sandbox container. This is a personal tool, not an App Store submission.
  Ad-hoc code signing (`codesign -s -`) is sufficient for local use; a Developer ID
  signature and notarization would be needed only to distribute it.
- **Binaries must be resolved by absolute path.** A GUI app launched from Finder does
  not inherit the shell's `PATH`, so `gh`, `git` and `claude` will not be found by name.
  The app resolves them at startup (probing known locations — `/opt/homebrew/bin`,
  `~/.local/bin` — and/or reading the login shell's `PATH`) and surfaces a clear error
  if any is missing. This is a common and confusing failure mode; it is handled up
  front, not diagnosed later.

## Error handling

| Failure | Behaviour |
|---|---|
| `gh` / `git` / `claude` not found | Blocking startup error naming the missing binary and how to install it |
| `gh` not authenticated | Blocking error pointing at `gh auth login` |
| Clone or fetch fails | PR row shows `checkout failed` with the git stderr; retry button |
| Session exits non-zero | Run marked `failed`, stderr kept and viewable; other reviewers unaffected |
| Session produces no findings | Distinguished from failure: `clean`, not `failed` |
| Session exceeds timeout | Killed, marked `timed out`, partial findings kept |
| Malformed / absent `ReportFindings` | Fall back to text parsing; if that yields nothing, `unparseable` with raw output kept |
| Rate limited | Back off, show when polling resumes |
| Offline | Keep showing cached PRs and findings, marked stale |
| New commits mid-review | Run continues against its `headSha`; result stored and marked `stale` |

## Testing

The three outside-world modules sit behind protocols, so most of the system is testable
without network, git or Claude.

- **Policy** — pure functions, exhaustive unit tests: blocking derivation, verdict
  suggestion, consensus detection, sorting. Zero mocking needed.
- **Stream parsing** — the key seam. Record real `stream-json` output from actual review
  runs as fixtures, then test the parser against them. Covers init events,
  `ReportFindings` calls, malformed input, truncated streams.
- **Config resolution** — global + per-repo merge, unknown-repo defaults, autodetection.
- **Source merge/dedup** — same PR arriving from two sources appears once.
- **GitHubGateway / RepoCheckout / ReviewRunner** — faked in app-level tests; a small
  number of integration tests exercise the real binaries against a scratch repo.

## Future work

Deliberately excluded from v1, and the design keeps each one cheap to add:

- **Team review requests** — one more entry in `sources[]`.
- **Embedded terminal** (SwiftTerm + PTY) — `session_id` is already stored.
- **Merged verdict across reviewers** — dedup by `file:line`, using independent
  rediscovery as a confidence signal. Can be built on top of the same stored findings;
  the reverse would not have been possible.
- **`must fix / recommended / nit` scale** — if the category-based grouping proves too
  coarse, a prompt-enforced JSON envelope can add an explicit severity on top of this
  model rather than replacing it.
- **Notifications** when a review finishes.

## Decision log

| Decision | Rejected alternative | Why |
|---|---|---|
| App orchestrates, skills analyse | Review logic in the app | Skills already do this well and evolve independently |
| Consume `ReportFindings` | Parse review prose | Structured data with file, line, verdict already exists |
| Manual trigger, `auto` opt-in per repo | Auto on everything | Arbitrary repos; unattended cost and surprise |
| Own cache + partial clone | Reuse user's clones; diff-only review | Never touch dirty working trees; reviewers need real files and `CLAUDE.md` |
| Read-only `--allowedTools` | Full permissions | Safety, and headless sessions cannot answer permission prompts |
| Group by `category`, derive one blocking bool | Invent a 3-level severity scale | Uses real data; needs no skill rewrites; scale can be layered on later |
| Parallel reviewers, mechanical `2×` badge | Aggregation session merging findings | Disagreement between reviewers is information; merging costs a session and loses it |
| Findings keyed by `headSha` | Keyed by PR | New commits must invalidate, not silently mislead |
| No terminal in v1 | SwiftTerm from the start | `stream-json` rendered natively is better for observing; intervention is rare |

## To verify before implementation

Claude Code CLI flags were written from working knowledge and should be confirmed
against `claude --help` on the installed version (2.1.220) before being relied on:
exact spelling of `--output-format stream-json`, whether `--verbose` is required in
print mode, `--allowedTools` syntax for scoped Bash patterns, and the shape of the init
event carrying `session_id`.
