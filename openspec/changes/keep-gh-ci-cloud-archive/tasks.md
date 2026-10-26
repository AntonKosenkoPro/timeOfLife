## 1. Research bundle (ctx7, gates implementation)

- [x] 1.1 Re-verify the ctx7 research bundle before implementing and record library IDs + queries + pins in the PR evidence (done during proposal — re-confirm pins at apply time): `/websites/github_en_actions` — "workflow triggers pull_request paths workflow_call" (path-filtered `pull_request`/`push` triggers, reusable `workflow_call` for `release.yml verify`); `/websites/developer_apple_xcode` — "Xcode Cloud custom build script ci_scripts" (`ci_scripts/` naming, `chmod +x`, shebang, no `sudo`; Cloud workflows live in App Store Connect, not the repo). Pin: Xcode 27.x Cloud / local 27.0; xcodegen 2.46.0, SwiftLint 0.65.1. Waivers: HIG N/A — CI-only diff, no user-facing surface; Apple app-framework API N/A — diff is workflow YAML + ASC toggles + docs, no app code. [RE-VERIFIED 2026-10-26: pins match ci_post_clone.sh/ci_pre_xcodebuild.sh + docs/ci.md; pre-#147 trigger block recovered from 32202d4^]

## 2. GitHub lane restore

- [x] 2.1 Restore automatic triggers in `.github/workflows/ios.yml`: `pull_request` (`paths: ios/**`, `.github/workflows/ios.yml`) + `push` to `main` (`paths: ios/**`) alongside the existing `workflow_call` (+ Sentry secrets block). Job contents (`lint-build-test`, `sentry-dsym`) byte-unchanged from the current file. [DONE: diff vs 32202d4^ is exactly the #151 Sentry block + sentry-dsym job]
- [x] 2.2 Confirm `release.yml verify` still resolves (`uses: ./.github/workflows/ios.yml`, `secrets: inherit`) — no edits expected; fail the task if the job needs touching. [DONE: resolve block intact at release.yml:423-428, no edits needed]

## 3. Cloud cutover (manual operator steps, human in App Store Connect + GitHub Settings)

- [x] 3.1 Disable the `iOS PR Checks` Cloud workflow (PR Changes + Branch Changes start conditions off). Record the workflow state (screenshot or ASC build-list output) as evidence. [DONE 2026-10-26: operator (user) confirms PR workflow off + tag Test stripped; user-attested, no ASC artifact pasted — trusted per user]
- [x] 3.2 Strip the `Test` action from the Cloud tag workflow (`v*`), keeping Archive + `ci_post_clone.sh` + signing + `ci_post_xcodebuild.sh` dSYM upload. Record the action list as evidence. [DONE 2026-10-26: covered by the same user confirmation as 3.1; Analyze was never enabled as a required gate, so nothing to strip there]
- [ ] 3.3 Merge-day branch protection (GitHub Settings → `main`): require `ios / lint-build-test`, drop any required Cloud check; verify with the required-checks list (`gh api` output or screenshot) before merging, or every PR blocks/mis-gates post-merge. Paths-filter caveat (AI-review round 1, waived as code change): a required path-filtered check stays pending on PRs that touch no matching path (backend-/docs-only) — when requiring it, either accept admin-override for those PRs or revisit with an always-run aggregator job; do NOT restructure the lane here.

## 4. Docs

- [x] 4.1 Update `docs/ci.md` (provider split → GH-owned iOS checks + Cloud archive-only; workflow table; new-target checklist scheme coverage back to `ios.yml`), `README.md` (CI + release paragraphs), `docs/project-context.md` (CI paragraphs), `AGENTS.md` (workflows listing), `docs/review-process.md` (mandatory-checks line) to describe GH-owned iOS CI. No baseline spec edits (skip_specs change). [DONE]

## 5. Verification

- [x] 5.1 `openspec validate --all --strict` green on the PR. [DONE: 31 passed, 0 failed]
- [x] 5.2 Backend suite green (`go test ./...` from `backend/`; `gofmt -l .` empty) plus a local iOS pass (`xcodegen generate`, `swiftlint lint --strict`, `xcodebuild` build and `test` per `docs/ios-test-loop.md`) proving the tree is green under the restored lane. [DONE: backend gofmt/vet/test green; iOS xcodegen + swiftlint (0 violations, 202 files) + build green + full suite 847 passed / 0 failed (retry on SE3-iOS27-track sim; first attempt on iPhone 17 hung with 0 tests — wedged sim, environment-only)]
- [ ] 5.3 Post-merge proof: a no-op `ios/`-touching PR shows the GH `ios` check required + green with no Cloud PR build firing (link ASC build list); the next tag shows Archive-only → TestFlight.
- [ ] 5.4 Contingency note: if a release must land before the Nov 16 Cloud reset with <51m quota left, ship on GH-`verify`-only and retry Archive post-reset (record the decision in the release notes).
