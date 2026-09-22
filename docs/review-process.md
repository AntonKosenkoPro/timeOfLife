# Two-Stage Review Process

Every PR passes two review stages: **stage 1 — AI review** (automated, advisory) and **stage 2 — human review** (self-review against a checklist). The design follows evidence-based review practice: small diffs (~<400 changed lines; defect detection collapses above ~400 LOC per sitting), AI delegated mechanical findings while humans keep intent/architecture judgment, and AI findings are advisory so they can never silently gate a merge.

## Stage 1 — AI review (automated)

**Workflow:** `.github/workflows/ai-review.yml` — opencode agent (`anomalyco/opencode/github@latest`, model from `OPENCODE_REVIEW_MODEL` repo variable, default `ollama-cloud/deepseek-v4.1-flash` via Ollama Cloud) runs on every `pull_request` event (`opened/synchronize/reopened/ready_for_review`) and posts one summary comment.

- **Advisory by design:** the job never blocks merge — findings are severity-tagged comments only. The human decides what to fix and what to waive.
- **What it checks (in order):** (1) OpenSpec compliance — diff vs the change's delta specs, tasks.md scope, edge-case tests, direct edits to baseline `openspec/specs/`; (2) repo non-negotiables from `AGENTS.md` (LocalStore chokepoint, Keychain tokens, Theme colors, L10n en+ru, OpenAPI sync, XcodeGen); (3) correctness bugs (Go concurrency, Swift concurrency, error handling); (4) test quality (tests that cannot fail, deleted/skipped tests); (5) security (plaintext secrets, user enumeration).
- **What it skips:** style/formatting (golangci-lint + swiftlint already gate it), pre-existing issues, speculative redesigns.
- **Severity:** `🔴 BLOCKING` (real bug / contract violation / spec gap) vs `🟡 NIT` (max 5, never blocking). On re-reviews it reports only new findings.
- **Tuning:** edit the `prompt:` block in `ai-review.yml`; change the model via the `OPENCODE_REVIEW_MODEL` repository variable (Settings → Secrets and variables → Actions → Variables) — any opencode `provider/model` id, e.g. an Anthropic model. Auth uses the `OLLAMA_API_KEY` secret (Ollama Cloud, key from ollama.com → Settings → Keys); runs on your runner with `use_github_token: true` (no GitHub App), `share: false`.
- **Anti-rubber-stamping rule:** a quiet AI review is *not* validation. Stage 2 runs regardless of how clean stage 1 looks.

## Stage 2 — Human review (you)

Runs after stage 1 findings are addressed or consciously waived. Use the checklist in the PR template (`.github/pull_request_template.md`) — it encodes the S5 iteration rules and the repo non-negotiables. Principles behind it:

1. **Review as a reader, not the author** — read the whole diff top-to-bottom once with fresh eyes before approving; self-review catches most issues before any reviewer.
2. **Humans keep what AI is weak at:** intent/spec fit, architecture fit (LocalStore chokepoint, OpenAPI contract), concurrency, product behavior. **Verify UI changes by running the app**, not by reading code.
3. **Tests must be valid, not just present** — would they fail if the code broke? Watch for deleted/skipped tests, especially in AI-written chunks.
4. **Optimize for the reader in 6 months:** names communicate, comments explain *why* not *what*; `git log` + PR description are the historical record (what + why + linked OpenSpec change).
5. **Code health over perfection:** approve when the change definitely improves the codebase; mark non-blocking remarks as nits and defer or do them explicitly.
6. **Size discipline:** ≤ ~400 changed lines per PR; split refactors from features; tests ride with the code they test.

## Flow

```
implement on branch
  → open PR as DRAFT
  → stage 1: AI review runs automatically, fix 🔴 findings
  → mark ready
  → stage 2: self-review with the PR-template checklist,
    verify behavior by running the app where it matters
  → all CI checks green (backend/ios/openspec) → merge
  → update OpenSpec tasks.md / advance the change as part of the merge commit's context
```

Draft PRs are the sequencing mechanism: AI sweeps the diff before you invest in self-review.

## Supporting checks

- **`openspec.yml`** — spec-integrity gate: `openspec validate --all --strict` (CLI pinned `@1.8.0`) on every PR and push to `main`. Fails broken OpenSpec structure; protects the spec-driven contract.
- **PR template** — OpenSpec linkage + S5 + non-negotiables + stage-2 checklist checkboxes.
- **Existing mandatory checks** — `backend.yml` (gofmt/vet/golangci-lint/race tests/coverage floor 45%/OpenAPI contract gate) and `ios.yml` (xcodegen/swiftlint --strict/warnings-as-errors build/tests). See `docs/ci.md`.

## Metrics (lightweight, optional)

- **AI-finding acceptance rate** — share of 🔴 findings actually fixed (grep PR threads); the core quality signal for tuning the prompt.
- **Noise trend** — 🟡 nits per review; if it grows, tighten the prompt.
- **Defect escape** — post-merge bugs the diff introduced; note them in the OpenSpec change when archived; quarterly skim of `openspec/changes/archive/` gives the rate with no tooling.

## Cost

One agentic review per push on `deepseek-v4.1-flash` ≈ $0.02–0.08 for a typical 500-line diff ($0.15/$0.60 per MTok in/out). Tune cost with the `model:` input; the concurrency group cancels superseded runs on rapid pushes.

## References

- Google eng-practices (reviewer standard, small CLs): https://google.github.io/eng-practices/review/
- SmartBear/Cisco review best practices (~400 LOC rule, checklists): https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/
- GitHub on reviewing AI-generated code: https://docs.github.com/en/copilot/tutorials/review-ai-generated-code
- OpenSpec review workflow: `openspec/README.md`, https://github.com/Fission-AI/OpenSpec