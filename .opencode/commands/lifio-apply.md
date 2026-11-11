---
model: opencode-go/muse-spark-1.3-contributor#xhigh
description: "Implement tasks from an OpenSpec change (Lifio-owned wrapper; survives openspec update)"
---

> Model routing: orchestrator runs on `opencode-go/muse-spark-1.3-contributor#xhigh`.
> Delegate ALL code edits, repros, and test/verify runs to the
> `lifio-implementer` subagent (`opencode-go/muse-spark-1.3-contributor#xhigh`)
> via the subagent tool. Do not implement or run tests in the orchestrator session.
> (The generated `openspec-apply-change` skill carries no delegation note; this wrapper adds it.)

> Proposal PR already exists: `/lifio-propose` opened a draft proposal PR on `opsx/<change-name>`. Work in the same worktree/branch (`timeOfLife.wt/<change-name>`, `git worktree list` to confirm), push implementation commits there, and reuse the open PR (`gh pr view` must resolve) — do NOT `gh pr create` a second PR. Do NOT trigger `/review` or `gh pr ready`; CI greening + AI review stay in `/lifio-pr`. End-of-turn report prints the reused `PR: <url> (draft)` and points to `/lifio-pr` next.

Load the `openspec-apply-change` skill (`.opencode/skills/openspec-apply-change/SKILL.md`) via the skill tool and follow it end to end.

$ARGUMENTS
