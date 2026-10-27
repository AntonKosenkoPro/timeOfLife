## 1. Step 0 base rule (durable files only)

- [x] 1.1 Add full Step 0 procedure to `docs/project-context.md` (Per-iteration step 0): fetch, locate main checkout, tracked-only stash with `step0-autostash/<date>/<reason>` + `stash list` report, checkout `main` + ff to `origin/main`, verify `HEAD == origin/main`, then `openspec list --json`; document stale-`main`-holder fallback (proceed at `origin/main`, flag holder, never force-remove)
- [x] 1.2 Add 2-line Step 0 pointer to `AGENTS.md` Flow recommendations including precedence sentence (AGENTS.md + project-context.md win over generated skill text)
- [x] 1.3 Add 1-line Step 0 mirror to `openspec/config.yaml` rules.proposal; verify `openspec validate --all --strict` stays green
- [x] 1.4 Add `timeOfLife.wt/` to `.gitignore`; verify `git status --porcelain` in main checkout no longer lists worktrees

## 2. Wait discipline (60s poll)

- [x] 2.1 Generalize `docs/ios-test-loop.md` rule 3 into `docs/project-context.md` + `AGENTS.md` flow rec: no foreground wait >~60s, background shells to log file with 60s poll, background subagents with overlapping work, per-domain stall budgets with kill-and-diagnose
- [x] 2.2 Record ctx7 waiver (process/tooling change, no external library/SDK; evidence: docs/config/gitignore-only diff) in change artifacts; no `library`/`docs` fetches required

## 3. Verification

- [x] 3.1 Rehearse Step 0 on a clean tree: `git fetch origin`, verify `HEAD == origin/main`, `git status --porcelain` shows only allowlisted `??`, `openspec list --json` reads current baselines
- [x] 3.2 Run `openspec validate --all --strict` green; confirm zero edits to `.opencode/skills/openspec-*` and `.opencode/commands/opsx-*` (`git status --porcelain` shows none)
- [x] 3.3 Confirm `openspec status --change harden-openspec-step0-poll` shows proposal/design/tasks done, specs skipped
