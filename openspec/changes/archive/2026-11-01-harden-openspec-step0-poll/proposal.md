## Why

Explorations and proposals routinely start on a stale or dirty base (main checkout on a feature branch, behind `origin/main`), so reads of baselines, `docs/project-context.md`, and `openapi.yaml` ground thinking in the wrong contract. Separately, agents block 10+ minutes on foreground waits for tasks that complete in ~2 minutes, wasting session time and context. Upstream `openspec-*` skills regenerate on CLI updates, so enforcement placed inside them would be wiped.

## What Changes

- **Step 0 (mandatory, sole exception to explore's free-form stance)**: every `opsx-explore` / `opsx-propose` session starts in the main checkout, fetches `origin`, stashes tracked dirt (`git stash push`, NO `-u`), checks out `main`, fast-forwards to `origin/main`, verifies `HEAD == origin/main`, then runs `openspec list --json`. On conflict with generated skill text, `AGENTS.md` + `docs/project-context.md` win.
- **Stash scope**: tracked-only stash with `step0-autostash/<date>/<reason>` message; untracked (`timeOfLife.wt/`, `.scroll-evidence-*`, untracked `openspec/changes/*`) stays put. Adds `timeOfLife.wt/` to `.gitignore` so status stays meaningful.
- **60s-poll wait rule**: no foreground wait longer than ~60s; long shells run backgrounded to a log file with 60s polls (generalizing `docs/ios-test-loop.md` rule 3); subagents use background + useful overlapping work; per-domain stall budgets (`go test` seconds, iOS suite ~30s warm, cold builds minutes) with kill-and-diagnose over infinite re-poll.
- **Overwrite-proof placement**: full procedure lives once in `docs/project-context.md`; one-line pointers in `AGENTS.md` + `openspec/config.yaml rules.proposal`; zero edits to generated `.opencode/skills/openspec-*` / `.opencode/commands/opsx-*`.

## Capabilities

### New Capabilities

None — process/tooling change, no product behavior.

### Modified Capabilities

None — no baseline requirement changes. This change sets `skip_specs: true`.

## Impact

- Docs/config only: `docs/project-context.md`, `AGENTS.md`, `openspec/config.yaml`, `docs/ios-test-loop.md` (generalize rule 3 pointer), `.gitignore`, optionally `opencode.json` agent descriptions.
- No backend, iOS, API, or spec-baseline changes. No migration. Risk is agent non-compliance with precedence wording, mitigated by the explicit override sentence.
