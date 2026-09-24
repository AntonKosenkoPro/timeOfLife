# Tasks — enable-sign-in-with-apple

## 1. iOS: entitlement and signing

- [x] 1.1 Add `com.apple.developer.applesignin` (value `default`) to `ios/TimeOfLife/TimeOfLife/Configuration/TimeOfLife.entitlements` alongside the existing App Group entry.
- [x] 1.2 In `ios/TimeOfLife/project.yml`, set config-scoped Release signing: `DEVELOPMENT_TEAM: 7923U48U87`, `CODE_SIGN_STYLE: Automatic`, `CODE_SIGN_IDENTITY: Apple Development`, `CODE_SIGNING_REQUIRED: YES` under the target's `configs: Release:` block; keep Debug (`base`) unsigned. Update the comment block at `project.yml:12-19` to describe the new split.
- [x] 1.3 Run `xcodegen generate` and confirm the `.pbxproj` diff contains only the expected signing/entitlement changes.
- [x] 1.4 Verify the Debug/simulator path is untouched: `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build` (no signing identity needed), and `xcodebuild test` on an available simulator — all green with warnings-as-errors.

## 2. iOS: Release build + device smoke (local)

- [x] 2.1 Build/Install the Release configuration on a real device (signed with team `7923U48U87`); resolve any provisioning complaints (e.g. register the App Group in the portal if reported missing).
- [x] 2.2 Run the new smoke checklist from README.md against the local backend (`APPLE_CLIENT_ID` set locally, `EMAIL_BACKEND=console`): Apple button → native sheet appears; complete sign-in (sandbox Apple ID, Hide My Email variant) → signed-in shell; cancel path → no error; airplane mode → button disabled.
- [x] 2.3 Record any defects found and fix them under this change (code changes belong here, not deferred); re-run 1.4 linters/tests after any fix.
  - Defect 1: Release signing identity — `Apple Distribution` conflicts with automatic signing on device builds; fixed to `Apple Development` (archives pick distribution automatically).
  - Defect 2 (production): `UpsertUserByAppleSubject` Postgres conflict target omitted the partial-index predicate → SQLSTATE 42P10 on every real Apple sign-in; fixed in `postgres.go` (ON CONFLICT … WHERE apple_subject IS NOT NULL) + added `TestPostgres_UpsertUserByAppleSubject` Postgres parity test. Root cause invisible to SQLite unit tests (different upsert syntax).
  - Defect 3: portal provisioning profile referenced a different App ID (fixed by user in the portal); stale profile had to be deleted from `~/Library/Developer/Xcode/UserData/Provisioning Profiles` so Xcode regenerates it.
  - Follow-up defect (client polish, still open → moved to harden follow-up): server error codes (`invalid_apple_token`, `apple_not_configured`, `rate_limited` for Apple path) lack localized copy → generic "Something went wrong" banner masks the real cause.

## 3. Backend: production enablement

- [x] 3.1 Set `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` (leave `APPLE_JWKS_URL` default) in the production VM env file; redeploy the backend container (`docker-compose.prod.yml` already passes it through).
- [x] 3.2 Verify gating end-to-end: `POST /api/v1/auth/apple` with a junk token now returns 401 `invalid_apple_token` (was 503 `apple_not_configured`); the OTP path still works; no secrets in logs (R1).

## 4. Smoke against production relay

- [x] 4.1 From the Release device build, complete a full Sign in with Apple against `https://timeoflife-api.antonkosenko.pro`; confirm signed-in state, "Sync now" visible in Profile, and sync completes.
- [x] 4.2 Verify Private Relay email handling: the relay address (`*@privaterelay.appleid.com`) is stored as the user email and `email_verified` is true.

## 5. Documentation and requirements alignment

- [x] 5.1 Add the manual SIWA smoke checklist to `README.md` (build/install, sheet presentation, sign-in, cancel, offline, production relay, Private Relay email).
- [x] 5.2 Update `docs/project-context.md`: distribution section (signing now configured for Release, TestFlight steps), "Sign in with Apple (F2)" section (entitlement + team + `APPLE_CLIENT_ID` live), and remove/adjust the "code signing is disabled" and "capability not enabled" statements.
- [x] 5.3 Update `AGENTS.md` only where it repeats the signing/Apple claims (keep it short, pointing at project-context).
- [x] 5.4 Re-check `Requirements/FURPS/Sign-up_and_Sign-in.md` (F2, F1) and `Requirements/Usecases/` rows; correct any rows that conflict with the now-enabled state.
- [x] 5.5 Confirm OpenAPI needs no change (`/auth/apple` contract unchanged; config-only enablement) — no spec edit expected.

## 6. Verification gates (S5)

- [x] 6.1 Backend: `go build ./...`, `go test ./... -cover`, `golangci-lint run`, `gofmt -l .`, `go vet ./...` — green (no Go changes expected; run to prove it).
- [x] 6.2 iOS: `xcodegen generate`, `swiftlint lint --strict`, simulator build + test (`xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`) — green.
- [x] 6.3 CI: push a branch and confirm `ios.yml` (and `backend.yml` if touched) pass; PR mergeable with mandatory checks green. (PR #37: lint-build-test, lint-and-test, validate all pass.)
- [x] 6.4 Mark this change ready for archive only after the production smoke (section 4) passes; update `docs/project-context.md` "Incomplete / deferred" (SIWA follow-ups: nonce, account deletion, credential-state remain deferred to their own changes). (Production smoke passed 2026-09-24; deferred list updated incl. error-code copy + TRUSTED_PROXIES note.)