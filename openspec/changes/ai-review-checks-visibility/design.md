## Context

See proposal.md (Why) for motivation. Current state: `ai-review.yml` triggers on `issue_comment`, resolves PR refs via `actions/github-script@v7`, runs `alibaba/open-code-review@v1.12.9` with parsed `/review` params, then writes params + action outputs (`range_summary`, `comments_total/inline/failed/routed`, `summary_comment_url`, `checkpoint_after`) to `$GITHUB_STEP_SUMMARY` via an `if: always()` step. That summary renders on the Actions run page — which, for `issue_comment` triggers, is anchored to the default-branch HEAD and has no link from the PR Checks tab (verified: PR #213 head `da01033` shows only `validate` + Cloudflare Pages). Permissions today: `contents: read`, `pull-requests: write` — no `checks:write`, so the workflow cannot attach anything to the PR head. Constraint from `docs/project-context.md`: AI review is advisory and must stay advisory — whatever surfaces in Checks must never gate merge.

## Goals / Non-Goals

**Goals:**
- One first-class `ai-review` entry in the PR Checks tab per `/review` run, carrying the same params/range/counts/summary-link/checkpoint content the job summary has today.
- Advisory-green semantics preserved: the Check Run concludes `success` whenever the bridge itself ran, regardless of finding counts.
- Keep the existing deep-dive surfaces untouched (job summary, streamed `[ocr]` log, sticky + inline comments).

**Non-Goals:**
- No per-file annotations on the Check Run (inline findings already exist; avoids the 50-annotations-per-request friction).
- No conclusion mapping from findings (no `failure`/`neutral`-on-findings; nothing in branch protection references `ai-review`).
- No trigger or params-grammar changes.

## Decisions

- **Create + finalize via `actions/github-script@v7`, no new action dependency.** The workflow already depends on it; Check Run calls are two REST calls (POST create, PATCH finalize) with `github.rest.checks.create/update` — same style as the existing refs/parse steps. ctx7 `/websites/github_en_rest` ("check runs create update output annotations"): POST `/repos/{owner}/{repo}/check-runs` with `name`, `head_sha`, `status`, `started_at`; PATCH `.../check-runs/{check_run_id}` with `status: completed`, `conclusion`, `completed_at`, `output{title*, summary*, text?}`.
- **Create immediately after Resolve PR refs; finalize replaces the summary step's tail.** Create needs `head_sha` (already an output) and must precede the review so the Checks tab shows `in_progress` while the model works; finalize is `if: always()` and writes both `$GITHUB_STEP_SUMMARY` (kept) and the PATCH. `details_url` → the Actions run URL, so Details jumps to logs + job summary.
- **Least-privilege permission: add `checks: write` only.** ctx7 `/websites/github_en_actions` ("GITHUB_TOKEN permissions checks write job summaries"): job-level `permissions` grants minimum access; unspecified permissions become `none`. Final set: `contents: read`, `pull-requests: write`, `checks: write`.
- **Constant check-run `name: "ai-review"`; per-run identity via `external_id`.** Same name aggregates in the Checks tab (latest wins); `external_id` = run + attempt identifies the run for debugging. Rejected: unique names per run (timestamp/run-id suffix) — would litter the Checks tab with one entry per `/review` comment.
- **Conclusion `success` whenever the bridge ran; `cancelled` for superseded runs.** The finalize step reads the review/parse outcomes for the `output` text but does not map them to the conclusion — findings, parse failures, and action errors are all reported *inside* the summary with a `success` conclusion (a parse usage error already fails the job; the Check Run mirrors the job outcome text while staying non-blocking). A run killed by the concurrency group (`cancel-in-progress`) PATCHes its *own* `check_run_id` to `cancelled` via `always()` — never the successor's.
- **No fork special-casing in v1.** The create call targets the base repo with the PR's `head_sha`; fork heads are expected to render on the PR like any check. Flagged as the spike in Open Questions rather than solved here.

## Risks / Trade-offs

- [Superseded run clobbers successor's check] → Mitigation: each job only ever PATCHes the `check_run_id` its own create step returned (passed via step outputs/env, never re-queried by name).
- [Summary step masking failures] → Same invariant as today: `if: always()` but never alters the job conclusion; the Check Run conclusion mirrors "bridge ran", not "review clean".
- [`output.summary` size caps] → Our summary is a dozen lines (params, range, 4 counts, 2 links); far below limits. Truncate defensively at write time if the range string ever grows.
- [Fork-head check runs invisible or permission-denied] → Spike first (Open Questions); if denied, fall back to documenting fork behavior + still publishing the job summary, and gate create on `head.repo.fork == false` rather than failing the run.
- [Two entries after rapid re-comment (`cancelled` + `success`)] → Accepted GitHub behavior for same-name runs; the latest conclusion is what reviewers read.

## Migration Plan

Workflow-only change: land, then exercise on a test PR — bare `/review` (expect `ai-review` `in_progress` → `success` with summary), one parametrized run (params reflected in Check Run output), one invalid value (job fails, Check Run carries the usage text, still non-blocking), rapid double `/review` (first run `cancelled`, second `success`). No data migration. Rollback: revert the workflow commit; Checks tab returns to today's state (no entry), sticky comments unaffected.

## Open Questions

- Fork-head rendering: does a `GITHUB_TOKEN` with `checks: write` in an `issue_comment` workflow successfully create a run against a fork's `head_sha` visible on the PR? Spike on a fork PR before declaring support; default to same-code-path unless the spike fails.
