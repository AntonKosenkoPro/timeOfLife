---
model: openai/gpt-6.1-sol#medium
description: "Implement tasks from an OpenSpec change (Lifio-owned wrapper; survives openspec update)"
---

> Model routing: orchestrator runs on `openai/gpt-6.1-sol#medium`.
> Delegate ALL code edits, repros, and test/verify runs to the
> `lifio-implementer` subagent (`opencode-go/muse-spark-1.3-contributor#xhigh`)
> via the subagent tool. Do not implement or run tests in the orchestrator session.
> (The generated `openspec-apply-change` skill carries no delegation note; this wrapper adds it.)

Load the `openspec-apply-change` skill (`.opencode/skills/openspec-apply-change/SKILL.md`) via the skill tool and follow it end to end.

$ARGUMENTS
