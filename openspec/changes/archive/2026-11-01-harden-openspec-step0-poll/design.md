## Context

See proposal.md — Why. Current state: `opsx-explore` stance declares no fixed steps; `opsx-propose` starts at `openspec new change` with no base check. The worktree gate (AGENTS.md + `openspec/config.yaml` rules.proposal + `docs/project-context.md` S5) requires change-scoped writes in `timeOfLife.wt/<name>` from fresh `origin/main`, but nothing forces the *reads* (explore/propose grounding) onto `main @ origin/main`. Main checkout was observed on `opsx/live-activities-natural-glass` behind `origin/main` with tracked dirt. `timeOfLife.wt/` is unignored, so `git stash -u` would swallow worktrees. Upstream `openspec-*` skills carry `generatedBy` and regenerate on CLI updates. ctx7 bundle: waived — pure process/tooling change, no external library/framework/SDK/API involved (waiver evidence: this change touches only docs, config, gitignore, and agent instructions).

## Goals / Non-Goals

**Goals:**
- Step 0 defined once, enforced at every explore/propose entry, surviving CLI updates.
- Stash semantics that preserve the 10% real work (untracked proposals) while clearing the 90% garbage (tracked dirt).
- Wait discipline with per-domain budgets instead of one global number.

**Non-Goals:**
- No custom wrapper skill yet (deferred; add only if agents ignore the precedence sentence in practice).
- No CI gate for explore (unobservable conversationally); propose gets `openspec validate --all --strict` as existing backstop only.
- No worktree-pruning automation (30+ stale worktrees are a separate cleanup).

## Decisions

1. **Single truth in `docs/project-context.md`, pointers elsewhere.**
   Full Step 0 procedure + poll rule live once under "Per-iteration revising process". `AGENTS.md` keeps a 2-line pointer (it must stay short). `openspec/config.yaml rules.proposal` gets a 1-line mirror (injected at artifact build). Zero edits to `.opencode/skills/openspec-*` / `.opencode/commands/opsx-*`.
   *Alternative: edit generated skills directly — rejected, wiped on next CLI update. Alternative: global `~/.config/opencode` — rejected, repo-specific paths wouldn't transfer to teammates.*

2. **Precedence sentence over explore's stance.**
   "Step 0 is the sole mandatory step of explore/propose; on conflict with generated skill text, AGENTS.md + project-context.md win." Keeps explore free-form *after* Step 0.
   *Alternative: "strong recommendation" — rejected, user explicitly approved mandatory given stale-base cost.*

3. **Tracked-only stash (`git stash push`, never `-u`), message `step0-autostash/<date>/<reason>`, report `stash list`.**
   Untracked allowlist (`timeOfLife.wt/`, `.scroll-evidence-*`, untracked `openspec/changes/*`) stays visible. Verify step accepts `??` noise.
   *Alternative: `stash -u` — rejected, tries to eat worktrees (unignored) and hides real untracked proposals.*

4. **Add `timeOfLife.wt/` to `.gitignore`** (local-only session state, like `.argent/recordings/`). Makes `git status --porcelain` meaningful and prevents accidental commits of worktree contents. Nested `timeOfLife/timeOfLife.wt/` standardizes to sibling `work/timeOfLife.wt/`.

5. **Poll rule generalizes `ios-test-loop.md` rule 3.**
   Shell: `background + log file + 60s poll + kill-and-diagnose over budget`. Subagents: `background=true` + overlapping useful work, notification on completion. Budgets: `go test` seconds, iOS warm suite ~30s, cold GRDB builds minutes; stall = kill + `ps`/`simctl`/log-tail diagnosis, never timeout raise. Serialization (one `xcodebuild`, one sim, single-writer files) unchanged.

## Risks / Trade-offs

- [Agents skim pointers, skip Step 0] → Mitigation: Step 0 is checkable (`rev-parse HEAD` vs `origin/main`, `status --porcelain`); reviewer/PR checklist can spot it. Wrapper skill deferred as escalation.
- [Stash hides work the user wanted] → Mitigation: tracked-only + named message + `stash list` report; recovery is `git stash pop`. Never `reset --hard` before stash.
- [`main` branch held by stale worktree, checkout fails] → Mitigation: Step 0 documents fallback — proceed at `origin/main` commit detached-equivalent and flag the holder for cleanup; never force-remove a worktree.
- [60s polling adds context churn] → Mitigation: poll carries only `tail/log grep`, parent does useful overlapping work; kill thresholds prevent infinite re-poll.
