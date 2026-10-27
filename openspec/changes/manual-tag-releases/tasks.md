## 1. Research bundle + repro (gates implementation)

- [x] 1.1 ctx7 research bundle recorded in proposal Impact (re-verify at apply time): `/websites/developer_apple_xcode` — "Xcode Cloud custom build script ci_post_clone" (script names, `ci_scripts/` discovery, shebang, automatic execution); `/websites/github_en_actions` — "environment protection rules required reviewers deployment" (required reviewers, wait timer, deployment objects). Pin: iOS 18 SDK via Xcode 16+. Waivers: HIG N/A — release tooling, no user-facing surface; SwiftUI/ActivityKit N/A — no app-framework API touched.
- [x] 1.2 Repro on record: release dry run `40211312698` failed at "Commit and push" with `GH013 — Changes must be made through a pull request` (log excerpt in the change discussion). No code fix proceeds on the bump-push model; this change replaces the model.

## 2. Phase 0 — unblock (manual operator steps + one paragraph)

- [ ] 2.1 Create you-only signed-tag rulesets for `internal/*`, `release/*`, `backend/*` (Settings → rulesets); verify with `gh api` output pasted as evidence. Confirm a bot-side tag push would be rejected (dry-run or ruleset evaluation).
- [x] 2.2 Document "bump retired, signed tags are the release act" in `docs/ci.md` (one paragraph + tag grammar table). No workflow edits yet.

## 3. Phase 1 — iOS channels

- [x] 3.1 Extend `ios/TimeOfLife/ci_scripts/ci_post_clone.sh`: parse exact-match tag (`internal/vM.m.p[.n]` / `release/vM.m.p[.n]`), derive MARKETING/CHANNEL, take Cloud per-workflow run number as build, stamp all targets post-`xcodegen generate`, assert unanimity or fail loudly. `sh -n` + local simulation with fake tags green.
- [ ] 3.2 Create Cloud workflows A (`Tag Changes internal/*` → Test → Archive → TestFlight Internal) and B (`release/*` → Test → Archive → External/Store per the open question). Record workflow IDs + first green internal build number as evidence.
- [ ] 3.3 Proof builds: throwaway `internal/v0.0.0[.2]` tags on a scratch commit go green with correct stamped versions (paste ASC log excerpts); a mistyped tag (e.g. `v0.0.0`) triggers nothing (screenshot or build-list evidence).
- [x] 3.4 Profile channel badge (` • Internal` on internal builds; dummy `0.0.0-dev` locally) with `en`+`ru` strings + `L10n` if new user-facing copy is added; unit tests on `AppVersion.formatted` inputs.
- [x] 3.5 Set `project.yml` versions to the dev dummy; confirm local simulator + `xcodebuild test` green on the dummy.
- [x] 3.6 Delete `release.yml` bump machinery (guards, bump, commit+push, recover, `verify` job + its comments/summary line); coordinate merge order with `migrate-ios-ci-to-xcode-cloud` so shared doc edits land once.

## 4. Phase 2 — backend identity

- [x] 4.1 `backend.yml`: build+push pinned `backend:<tag>` alongside `:latest` on `backend/*` tags; fix the `stage`-vs-`prod` env skew (code or comment, one of them is wrong).
- [x] 4.2 Stamp `version`/`sha` via `ldflags` build args; extend `GET /health` to `{status, version, sha}` with `"?"` fallback unstamped; sync `backend/api/openapi.yaml` health schema (S10) + contract test.
- [ ] 4.3 Adopt expand-contract for migrations from here on (note in `docs/project-context.md` deployment section); verify `/health` on a tagged stage deploy returns the tag + short SHA.

## 5. Docs

- [x] 5.1 Update `docs/ci.md` (tag grammar, rulesets, runbook: typo→no-build, key loss, rollback), `README.md` (CI + release paragraphs), `docs/project-context.md` (CI + deployment + signing paragraphs), `AGENTS.md` (workflow listing), `docs/review-process.md` (mandatory-checks line) to describe the tag model. No baseline spec edits by hand (archive folds the deltas).

## 6. Verification

- [x] 6.1 `grep -rn "workflow_call\|RELEASE_PLISTS\|chore(release): bump" .github/ docs/ README.md AGENTS.md` returns only historical mentions (noted) or empty.
- [x] 6.2 `openspec validate --all --strict` green on the PR.
- [x] 6.3 Backend suite green (`go test ./...` from `backend/`; `gofmt -l .` empty) + local iOS build + test pass (`xcodegen generate`, `swiftlint lint --strict`, `xcodebuild` build and `test` per `docs/ios-test-loop.md`).
- [ ] 6.4 Phase 3 follow-up filed (environments `testflight-internal`/`testflight-public`/`backend-prod` + one rollback drill per platform, internal-only) — linked issue or tasks section, not blocking archive.
