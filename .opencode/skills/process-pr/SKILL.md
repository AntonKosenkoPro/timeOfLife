---
name: process-pr
description: Process a PR after implementation — open from repo template, drive CI green, loop AI review fixing only proven findings, hand off to human, archive OpenSpec change only after human approval. Use when implementation is done and the user wants the PR taken to human-review-ready without merging.
license: MIT
compatibility: Requires git + gh CLI (auth via `gh auth status`); OpenSpec archiving requires openspec CLI only when a change is linked.
metadata:
  author: lifio
  version: "1.0"
---

Take an implemented branch to **human-review-ready**. You open/fill the PR,
green the mandatory checks, sweep AI review (fixing only proven findings),
then STOP for a human. You never merge.

**Two-stage context (read before starting):** `docs/review-process.md`
(AI stage 1 = advisory `ai-review.yml` via `/review` comment; human stage 2
via PR-template checklist), `docs/ci.md` (mandatory `backend.yml` +
`ios.yml` + `openspec.yml`; advisory `ai-review.yml`), PR template
`.github/pull_request_template.md`, rules `.opencodereview/rule.json`.

**Input:** Optionally a branch name, PR number/URL, and/or OpenSpec change
name (e.g., `/opsx-pr`, `/opsx-pr 42`, `/opsx-pr my-branch my-change`).
If omitted: infer from conversation; if the current branch tracks an
open PR, use it; if `openspec list --json` shows exactly one active change
matching the branch, link it; otherwise ask (show `gh pr list --author @me`
+ `openspec list --json` candidates).

## Steps

### 0. Preconditions (fail fast, fix before opening anything)

- `gh auth status` green; `git status` clean on the work branch
  (commit or stash first — never open a PR with a dirty tree).
- Current branch is NOT `main` (`git branch --show-current`).
  Base is `main` unless the user names another.
- Linked OpenSpec change resolved (explicit arg > branch-name match >
  single active change > ask). Announce: `Using change: <name|none>`
  and `Using PR: <#|none yet>` and how to override (e.g., `/opsx-pr <other>`).

### 1. Open or reuse the PR (handle both)

**If an open PR exists for the branch** (`gh pr view` resolves): reuse it.
Verify base is correct; update title/body if the template sections are empty.

**Otherwise create it:**

1. Push: `git push -u origin <branch>`
2. Read `.github/pull_request_template.md` — it IS the body skeleton.
   Fill every section truthfully from the actual diff + change:
   - `What & why`: one paragraph + linked OpenSpec change (or state
     docs/tooling-only with justification).
   - `OpenSpec`: check only boxes that are actually true (deltas under
     `openspec/changes/<name>/`, baselines untouched, `tasks.md` ticked).
   - `Required on every iteration (S5)` + `Repo non-negotiables`: check
     only what you verified this tree (linters, tests, FURPS rows,
     docs/`openapi.yaml`, LocalStore chokepoint, Keychain/hashes,
     en+ru+L10n, Theme colors, `project.yml`+xcodegen). Leave the rest
     unchecked — CI/human will judge them.
   - `Stage 2 checklist (human review)`: leaveUnchecked for the human
     (UI run, test validity, diff size, dead code). Do NOT pre-check it.
3. Create as **draft** (sequencing mechanism per `review-process.md`):
   `gh pr create --draft --base main --title "<scope>: <what>" --body "<filled-template>"`
4. Announce: `PR: <url> (draft)`.

**Guardrails:** never `--fill` without reading the template; never open
against the wrong base; never commit secrets (no passwords/plaintext tokens).

### 2. Wait for mandatory checks

- Watch: `gh pr checks --watch --fail-fast` (or poll
  `gh pr checks` / `gh run list --branch <branch>` on timeout).
- Blocking = `backend`, `ios`, `openspec` workflows. Advisory
  `ai-review` never blocks — ignore its red/skip here.
- On timeout (> ~20 min no conclusion): report the stuck workflow
  (`gh run view <id> --log-failed`) and ask whether to keep waiting.

### 3. Resolve red mandatory checks (auto-fix + push)

For each failing check:

1. Pull the failure: `gh run view <run-id> --log-failed` (or
   `gh pr checks -v` → failed job → logs). Classify:
   backend lint/test/contract-gate, iOS xcodegen/swiftlint/build/test,
   openspec validate.
2. **Reproduce locally first** (bugfix rule from `docs/project-context.md`):
   `cd backend && gofmt -l . && go vet ./... && go test ./...` /
   `cd ios/TimeOfLife && xcodegen generate && swiftlint lint --strict` /
   `openspec validate --all --strict`. A CI-only flake gets one clean
   retry (`gh run rerun <id> --failed`) before code changes.
3. Fix on the PR branch (minimal, existing utilities first, no dead code;
   keep `backend/api/openapi.yaml` + handlers + iOS client in sync when
   the contract moves). Commit, push, return to step 2.
4. If a failure is infra (runner outage, secret missing, e.g. `OLLAMA_API_KEY`,
   signing Team), do NOT code around it — report + stop this step.

Proceed only when all mandatory checks are green.

### 4. Run AI review (stage 1)

- Trigger: `gh pr comment <PR#> --body "/review"` (nothing runs on push by
  design). One trigger per round — re-commenting cancels + restarts.
- Wait for the sticky summary + inline comments:
  poll `gh pr view <PR#> --comments` / `gh api repos/{owner}/{repo}/pulls/<PR#>/comments`
  until the run concludes (check `gh run list --workflow ai-review.yml`).
  Timeout (~15 min, workflow `timeout-minutes: 60`): report + ask.
- Collect every inline finding (file:line + message) plus the summary.

### 5. Triage findings — fix only what is proven

Stage 1 is **advisory** (`docs/review-process.md`): a quiet review is NOT
validation, and a noisy one is mostly noise until proven. For EACH finding:

1. **Prove or waive:** reproduce (failing test, local run, log excerpt) or
   confirm by reading the cited code + rule (`.opencodereview/rule.json`
   path rules: LocalStore chokepoint, OpenAPI sync, Theme/L10n/XcodeGen,
   Keychain-only, test validity). Style/formatting findings belong to
   the linters — if linters are green, waive with that reason.
2. **Fix proven ones only** on the PR branch (regression test where
   automatable; FURPS/docs updated if behavior moves). Push.
3. **Waive the rest in place:** reply to the thread
   (`gh pr review <PR#> --comment -b "<waive reason>"` or thread reply via
   `gh api`) with one line: `Waived: <reason + evidence>`.
   Never "fix" an unproven finding by editing code to silence the bot.
4. Resolve each thread only after fix-pushed or waive-reason posted.

### 6. Loop until clean (bounded)

- After pushing fixes: return to step 2 (mandatory checks must stay green),
  then step 4 (`/review` again — checkpoint mode reviews only
  `<checkpoint>..<head>`).
- **Bound: max 3 fix→review rounds.** After the 3rd, or when only waived
  items remain, stop looping and go to handoff — list fixed vs waived
  (with reasons) instead of chasing the bot to silence.

### 7. Handoff to human (STOP — never merge)

- Mark ready only when mandatory checks are green:
  `gh pr ready <PR#>` (draft → ready is the stage-1→stage-2 switch).
- Post the highlights comment on the PR AND print it in chat:

```markdown
## Ready for human review (stage 2)

**PR:** <url> — mandatory checks green, stage-1 loop done (rounds: N).
**What changed:** <1-2 lines + OpenSpec change link or docs/tooling-only note>.
**Fixed from AI review:** <bullets file:line → fix + commit>.
**Waived (false positives):** <bullets finding → reason + evidence>.
**Stage-2 pointers for you:** UI run in simulator? / tests-would-fail check /
  diff size (≤~400 or split?) / spec-fit + architecture judgment.
Merging is yours — I never merge.
```

- End the turn here. Do NOT merge, do NOT run `gh pr merge`,
  do NOT push to `main`, do NOT archive yet.

### 8. After human approval only — archive + merge ask

Run ONLY as a follow-up when the human replies that everything is OK
(explicit approval — never assume it from step 7):

1. Invoke the `openspec-archive-change` skill for the linked change
   (skip with a one-line note when the PR was docs/tooling-only with no
   change). Announce `Using change: <name>`; on incomplete-artifact/task
   warnings surface them and wait for confirmation per that skill.
2. Reply with the closing line (chat + PR comment):
   `Archived <change> to <path>. Green + approved — please merge when ready: <url>.`
3. Stop. The human presses merge.

## Output formats

- After step 1: `PR: <url> (draft) | change: <name|none> | base: main`
- After step 3: `CI: backend ✅ ios ✅ openspec ✅ (reruns: N)`
- After each review round: `Review round N: fixed <k>, waived <m> (reasons), pushed <sha>`
- Final handoff: the step-7 highlights block (PR comment + chat).

## Guardrails

- **Never merge.** No `gh pr merge`, no direct push to `main`, no
  "auto-merge when green". The human merges.
- **Never archive before human approval.** Step 8 needs explicit OK.
- **Mandatory checks gate; AI review advises.** Green CI is required;
  a clean AI review is not proof (stage 2 still runs).
- **Prove before fixing.** No code change for an unproven finding;
  waive with evidence instead.
- **Bound the loop.** 3 fix→review rounds max, then hand off with a ledger.
- **Template honesty.** Check only boxes you verified; leave stage-2 boxes
  for the human.
- **Small diffs.** If `gh pr diff --stat` shows > ~400 changed lines,
  propose stacked PRs in the handoff instead of silently proceeding.
- **Secrets.** No passwords/plaintext tokens in code, logs, or PR body;
  `otp/request` stays 202-always.
