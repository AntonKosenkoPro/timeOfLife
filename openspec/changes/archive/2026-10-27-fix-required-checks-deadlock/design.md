## Context

See proposal.md (Why) for motivation and the PR #211 repro. Current state (post-#209, merged as 5194ec7): `ios.yml` `pull_request` + `push`-to-`main` are path-filtered to `ios/**` (+ workflow file); `backend.yml` likewise to `backend/**`. Ruleset `main protection` requires contexts `lint-and-test` + `lint-build-test` + `validate`. Path-skipped workflows report nothing, so non-matching PRs block forever. The gate must therefore always run and always report, while the expensive jobs stay path-gated.

## Goals / Non-Goals

**Goals:**
- Every PR reports a definitive iOS + backend signal (pass or legitimately-skipped), so the required checks never pend.
- Zero macOS cost for non-matching PRs (one ubuntu `changes` + `gate` job each, seconds).
- Fail-closed detection: if the diff cannot be computed, the lanes run.

**Non-Goals:**
- No `required_workflows` ruleset feature (same skip semantics, rejected).
- No fork-PR checkout support beyond fail-closed (repo flow is same-repo `opsx/*` branches; assumed, stated in code comment).
- No changes to `deploy`, `sentry-dsym`, pins, or Cloud workflows.

## Decisions

- **D1 — Detect paths in-workflow, not in `on:`.** `pull_request:` loses its `paths:` filter; a `changes` job (ubuntu) runs `git diff --name-only <base>...HEAD` and outputs `ios`/`backend` true/false. Rationale: workflow-level path filters prevent ANY job (including a gate) from reporting; the only fix is to always trigger and branch inside. Alternative (drop filters entirely) rejected: every docs PR would burn a full macOS run at 10× minutes.
- **D2 — Fail-closed detection.** Non-`pull_request` events output `true` (push path-filters already matched; `workflow_dispatch` callers opt in explicitly). If the base fetch or diff fails, output `true` — the lane runs. A detection failure must cost minutes, never silently skip verification.
- **D3 — Gate jobs carry the required contexts.** `ios-gate` / `backend-gate` (`if: always()`, `needs:` the lane job): pass iff needed result ∈ {success, skipped}. The ruleset requires the gates, never the lanes. Rationale: per GitHub docs, `always()` + `needs` is the supported gate pattern; `needs.X.result` distinguishes real-fail (gate fails) from path-skip (gate passes). Alternative (require lanes + aggregator) rejected: two required contexts per lane doubles the deadlock surface.
- **D4 — Keep `push` path filters.** Post-merge runs need no gate (nothing requires post-merge checks); keeping push filtered avoids pointless ubuntu runs on direct pushes and preserves current deploy/release behavior (`deploy` still `needs: lint-and-test` on push/dispatch).
- **D5 — Concurrency unchanged.** New ubuntu jobs join the existing groups (`ios-...`, backend has none); they finish in seconds and cannot starve or cancel the lanes. No `cancel-in-progress` changes.
- **D6 — `sentry-dsym` stays out of the gate.** It is release-path-only (`upload_dsyms` input); on PRs it skips. The gate `needs:` only `lint-build-test`, so the skipped dSYM job never affects the PR signal. On `release.yml verify`, both run and both must pass (unchanged semantics).

## Risks / Trade-Offs

- [Risk] Ruleset swap missed on merge day → new gates report but old lane contexts still required → same deadlock persists → Mitigation: explicit merge-day operator task with ruleset path + verification (open a docs-only PR or inspect required-checks list).
- [Risk] `changes` diff wrong on exotic events (e.g. `workflow_call` into ios.yml from a future caller) → Mitigation: D2 fail-closed (non-PR ⇒ true); PR path is the only one that can skip.
- [Risk] Fork PRs: base-sha fetch against the fork remote may miss → Mitigation: fail-closed to true (lane runs); documented assumption.

## Migration Plan

1. Land this PR (both lanes still run on it — it touches both workflow files — so the positive path is self-proving; the skip path is proven post-merge).
2. Merge-day operator: ruleset `main protection` → replace required `lint-build-test` with `ios-gate`, `lint-and-test` with `backend-gate`; verify on a docs-only PR (expect both gates green without lane runs).
3. Rollback: revert the two workflow files + swap the ruleset contexts back (exact inverse).

## Open Questions

None — fork-PR handling (D2 fail-closed + stated assumption) is decided above.
