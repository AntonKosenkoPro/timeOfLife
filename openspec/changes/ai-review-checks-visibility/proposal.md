## Why

The Checks-observability requirement from the parametrized-`/review` change is unmet: AI review triggers and runs correctly, but nothing ever appears in the PR Checks tab. `ai-review.yml` triggers on `issue_comment`, so GitHub anchors its check runs to the default-branch HEAD — not the PR head SHA the Checks tab filters by. The job summary therefore lives only on the Actions run page, where reviewers never look. Evidence (recorded 2026-10-27): PR #213 at head `da01033` shows only `validate` + Cloudflare Pages check runs, while the successful `review` jobs (e.g. run `40506216511`) created check runs against main HEAD `5194ec7`.

## What Changes

- `.github/workflows/ai-review.yml`: bridge visibility explicitly via the Checks API —
  - add `checks: write` to the job permissions (least-privilege addition; `contents: read` + `pull-requests: write` unchanged);
  - new step after Resolve PR refs: `POST /repos/{owner}/{repo}/check-runs` with `name: "ai-review"`, `head_sha` (already resolved), `status: in_progress`, storing the `check_run_id`;
  - rework the summary step into a finalize step (`if: always()`): `PATCH .../check-runs/{check_run_id}` with `status: completed`, `conclusion: success` (advisory stays advisory — green means "the review ran", never a merge gate), `output` carrying the same params/range/counts/summary-link/checkpoint markdown, `details_url` pointing at the Actions run; keep writing `$GITHUB_STEP_SUMMARY` for the Actions tab.
- `docs/review-process.md`: update the Checks-observability section — the PR Checks tab now shows a first-class `ai-review` entry with the findings summary; the job summary + streamed `[ocr]` log remain as the deep-dive surface.
- Explicit non-goals: no per-file annotations (inline findings already exist; avoids the 50-annotations-per-request friction that motivated the original decision); no merge-blocking behavior; no trigger change (manual `/review` stays); no endpoint/secret parametrization.

## Capabilities

### New Capabilities

- None — CI tooling only, no product behavior.

### Modified Capabilities

- None — no baseline spec requirement changes. This change keeps `skip_specs: true` in `.openspec.yaml` (`openspec validate` accepts zero deltas with that marker), mirroring the parametrized-`/review` change it completes.

## Impact

- Affected: `.github/workflows/ai-review.yml` (two new/changed steps + one permission), `docs/review-process.md` (Checks section rewrite). No app, backend, OpenAPI, or spec-contract changes.
- Reverses the earlier Non-Goal ("no custom Check Run via the Checks API"): the premise behind it — that a job summary renders "on the run page linked from the Checks tab" — proved false for `issue_comment` triggers, which produce no such link. Platform behavior invalidated the tradeoff (saved permission) behind the decision.
- Verification is workflow-level (test-PR live runs: bare `/review` shows the Checks entry, params reflected, cancel-supersede finalizes cleanly) plus `openspec validate`; no app test suites affected.
- Research bundle (ctx7): `/websites/github_en_rest` ("check runs create update output annotations" — POST/PATCH shapes, `output{title*, summary*, text?}`, `conclusion` vocabulary) and `/websites/github_en_actions` ("GITHUB_TOKEN permissions checks write job summaries" — job-level `permissions` least-privilege, unspecified → `none`). Pins: `actions/github-script@v7`, `alibaba/open-code-review@v1.12.9`. HIG waiver — CI-only diff, no UI (evidence: change touches only `.github/workflows/ai-review.yml` + `docs/review-process.md`). Apple-API waiver — no iOS code (same evidence).
