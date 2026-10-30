---
model: opencode-go/muse-spark-1.3-contributor#xhigh
description: "Process a PR to human-review-ready (Lifio-owned wrapper; survives openspec update)"
---

> Model routing: orchestrator runs on `opencode-go/muse-spark-1.3-contributor#xhigh`.
> Delegate ALL code edits, repros, and test/verify runs to the
> `lifio-implementer` subagent (`opencode-go/muse-spark-1.3-contributor#xhigh`)
> via the subagent tool. Do not implement or run tests in the orchestrator session.

Load the `process-pr` skill (`.opencode/skills/process-pr/SKILL.md`) via the skill tool and follow it end to end.

$ARGUMENTS
