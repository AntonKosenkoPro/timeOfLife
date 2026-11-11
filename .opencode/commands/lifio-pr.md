---
model: opencode-go/muse-spark-1.3-contributor#xhigh
description: "Process a PR to human-review-ready (Lifio-owned wrapper; survives openspec update)"
---

> Model routing: orchestrator runs on `opencode-go/muse-spark-1.3-contributor#xhigh`.
> Delegate ALL code edits, repros, and test/verify runs to the
> `lifio-implementer` subagent (`opencode-go/muse-spark-1.3-contributor#xhigh`)
> via the subagent tool. Do not implement or run tests in the orchestrator session.

> Proposal PR reuse (overrides the skill's create-first reading of Step 1): `/lifio-propose` already opened the draft PR, so expect `gh pr view` to resolve — reuse it (verify base `main`; drop the ` (proposal)` title suffix; refill `.github/pull_request_template.md` truthfully for the implemented tree, checking only verified S5/non-negotiables boxes). `gh pr create` runs only as fallback when no open PR exists for the branch.

Load the `process-pr` skill (`.opencode/skills/process-pr/SKILL.md`) via the skill tool and follow it end to end.

$ARGUMENTS
