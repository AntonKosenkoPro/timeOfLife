---
model: openai/gpt-6.1-sol#high
description: "Propose a change and open a proposal PR (Lifio-owned wrapper; survives openspec update)"
---

Load the `openspec-propose` skill (`.opencode/skills/openspec-propose/SKILL.md`) via the skill tool and follow it end to end, with the worktree + proposal-PR additions below (they override the skill on sequencing — the skill is authoritative on artifact content).

> Worktree gate (AGENTS.md, no reclassification): Step 0 runs in the main checkout on `main @ origin/main` (`git fetch origin`, tracked-only stash, verify `HEAD == origin/main`, `openspec list`). Resolve the kebab-case change name first (from `$ARGUMENTS`, or ask as the skill does), THEN before the first change-scoped write (including `openspec new change`) create `timeOfLife.wt/<change-name>` from fresh `origin/main` (one branch `opsx/<change-name>` per worktree), move the session into it (`session_move`), verify with `git worktree list`, and do all subsequent work there.

> Proposal-PR-first: after the skill's final `openspec status`, do NOT stop at "ready to implement" — open the proposal PR in the same turn:
> 1. Preconditions: `gh auth status` green; branch is `opsx/<change-name>`, base `main`; `openspec validate --all --strict` green locally.
> 2. Commit proposal artifacts (`openspec/changes/<name>/` only) and push: `git push -u origin opsx/<change-name>`.
> 3. If `gh pr view` already resolves an open PR for the branch, reuse it (verify base; update body). Otherwise create as **draft** per `process-pr` SKILL.md Step 1 mechanics (read `.github/pull_request_template.md`, fill truthfully for the proposal stage, attribution footer per that skill): `What & why` from `proposal.md` + linked change; OpenSpec boxes — check change-exists + baselines-untouched, leave `tasks.md`-ticked unchecked (no code yet); S5/non-negotiables — check only what this tree verified (worktree/rebase, research bundle if recorded), leave code-gated boxes unchecked with a `proposal-only, no code` note; Stage-2 boxes stay unchecked. Title form `<scope>: <what> (proposal)`.
> 4. Announce `PR: <url> (draft, proposal) | change: <name> | branch: opsx/<name>`. Do NOT trigger `/review`, do NOT `gh pr ready`, do NOT merge, do NOT archive.
> 5. STOP for human proposal review — do NOT run `/lifio-apply` in the same turn. Next: human approves/comments on the PR, then `/lifio-apply` implements on the same branch/worktree and `/lifio-pr` reuses this PR.

$ARGUMENTS
