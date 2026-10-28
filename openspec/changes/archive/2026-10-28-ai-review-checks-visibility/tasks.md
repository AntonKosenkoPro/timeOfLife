## 1. Repro + research (gates implementation)

- [x] 1.1 Record the repro on the current tree: PR #213 head `da01033` check-runs list only `validate` + Cloudflare Pages (no `ai-review`); successful `review` jobs (e.g. run `40506216511`) created check runs against main HEAD `5194ec7` — evidence captured in the change proposal
- [x] 1.2 Complete the ctx7 research bundle: `/websites/github_en_rest` ("check runs create update output annotations" — POST/PATCH shapes, `output{title*, summary*, text?}`, conclusion vocabulary) + `/websites/github_en_actions` ("GITHUB_TOKEN permissions checks write job summaries" — job-level least-privilege); pins `actions/github-script@v7`, `alibaba/open-code-review@v1.12.9`; HIG waiver (CI-only, no UI) + Apple-API waiver (no iOS code) recorded in proposal

## 2. Workflow bridge

- [x] 2.1 Add `checks: write` to the `review` job permissions in `ai-review.yml` (`contents: read` + `pull-requests: write` unchanged); update the file header comments to describe the Check Run bridge
- [x] 2.2 Add a create step after Resolve PR refs: `POST check-runs` with `name: "ai-review"`, `head_sha` from refs, `status: in_progress`, `details_url` → this run, `external_id` → run + attempt; expose `check_run_id` as a step output
- [x] 2.3 Rework the summary step into an `if: always()` finalize step: PATCH `check-runs/{id}` with `status: completed`, conclusion `success` (bridge ran; `cancelled` when the job was superseded), `output` carrying the current summary markdown (params gated on parse outcome, `range_summary`, finding counts, summary URL, checkpoint); keep writing `$GITHUB_STEP_SUMMARY`
- [x] 2.4 Confirm advisory stays advisory: no branch-protection reference to `ai-review`, no `failure` conclusion mapped from findings, no `annotations` array (inline findings remain the only per-file surface)

## 3. Docs

- [x] 3.1 Update `docs/review-process.md` Checks-observability section: PR Checks tab now shows a first-class `ai-review` entry (in-progress while running, summary on completion); job summary + streamed `[ocr]` log remain the deep-dive surface
- [x] 3.2 Re-check the relevant `Requirements/FURPS/*.md` rows (CI/review process) and fix conflicts, if any — no conflicts: S5/S6 cover mandatory checks (backend/ios/openspec), ai-review stays advisory

## 4. Verification

- [x] 4.1 Run `openspec validate` for the change and confirm green
- [ ] 4.2 Post-merge live runs on a test PR (deferred: `issue_comment` workflows execute the file from `main`, so the bridge only takes effect after merge): bare `/review` (expect `ai-review` `in_progress` → `success` in the Checks tab with params/range/counts), one parametrized run, one invalid value (expect usage text in the Check Run, still non-blocking), rapid double `/review` (expect `cancelled` + `success`), and re-run the 1.1 repro to confirm the `ai-review` entry now appears on the PR head
- [ ] 4.3 Fork-head spike: confirm a fork PR's Check Run renders, or gate create on non-fork heads with job summary as the fallback surface
