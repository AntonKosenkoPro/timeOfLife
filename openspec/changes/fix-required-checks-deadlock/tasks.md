## 1. Research bundle + repro (gate implementation)

- [x] 1.1 ctx7 research bundle re-verified at apply time: `/websites/github_en_actions` — "required status checks skipped workflows path filters always run gate job" (path-skipped workflows leave checks Pending and block PRs that require them; `always()` + `needs` gate pattern). Waivers: HIG N/A — CI-only diff; Apple app-framework API N/A — no Cloud changes in this diff.
- [x] 1.2 Repro recorded on the current tree (no code changes yet): PR #211 (docs/openspec-only) `mergeState: BLOCKED`, head check-runs = only `validate` + Cloudflare Pages; ruleset `main protection` requires `lint-and-test` + `lint-build-test`, neither reported. Evidence: `gh pr view 211`, `gh api .../check-runs`, ruleset dump.

## 2. iOS lane gate

- [x] 2.1 `ios.yml`: drop `paths:` from `pull_request` (keep `push` path filter); add ubuntu `changes` job (fetch base sha, `git diff --name-only base...HEAD`, outputs `ios`; fail-closed true on non-PR events and on detection failure); gate `lint-build-test` with `if: needs.changes.outputs.ios == 'true'` on pull_request (always run on push/workflow_call). [DONE]
- [x] 2.2 Add always-run ubuntu `ios-gate` (`if: always()`, `needs: [lint-build-test]`): pass iff result ∈ {success, skipped}. `sentry-dsym` untouched (still input-gated, not in the gate's `needs`). [DONE]

## 3. Backend lane gate

- [x] 3.1 `backend.yml`: same shape — drop `paths:` from `pull_request` (keep `push` filter + `workflow_dispatch` inputs); add ubuntu `changes` job (`backend/**` + workflow file, same fail-closed rule); gate `lint-and-test` on it for pull_request. [DONE]
- [x] 3.2 Add always-run ubuntu `backend-gate` (`if: always()`, `needs: [lint-and-test]`): pass iff result ∈ {success, skipped}. `deploy` untouched (`needs: lint-and-test`, push/dispatch only). [DONE]

## 4. Ruleset + docs (operator step + docs)

- [ ] 4.1 Merge-day operator (human, GitHub Settings → Rulesets → `main protection`): require `ios-gate` + `backend-gate` instead of `lint-build-test` + `lint-and-test`; verify with the required-checks list before merging follow-ups.
- [x] 4.2 Update `docs/ci.md` (required-gates section: gate semantics, ruleset swap, fail-closed rule; troubleshooting for Pending checks) to describe the gate model. [DONE]

## 5. Verification

- [ ] 5.1 `openspec validate --all --strict` green on the PR.
- [ ] 5.2 Backend suite green (`gofmt -l .`, `go vet`, `go test ./...`) plus local iOS pass (`swiftlint lint --strict`, `xcodebuild` build + test) proving the tree is green; Ruby YAML-validity check on both workflow files.
- [ ] 5.3 Post-merge proof: a docs-only PR shows `ios-gate` + `backend-gate` green with both lanes skipped; an `ios/`-touching PR shows the lane running and the gate passing through.
