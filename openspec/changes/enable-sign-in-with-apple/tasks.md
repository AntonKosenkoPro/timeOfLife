# Tasks — enable-sign-in-with-apple

## 1. iOS: entitlement and signing

- [ ] 1.1 Add `com.apple.developer.applesignin` (value `default`) to `ios/TimeOfLife/TimeOfLife/Configuration/TimeOfLife.entitlements` alongside the existing App Group entry.
- [ ] 1.2 In `ios/TimeOfLife/project.yml`, set config-scoped Release signing: `DEVELOPMENT_TEAM: 7923U48U87`, `CODE_SIGN_STYLE: Automatic`, `CODE_SIGN_IDENTITY: Apple Distribution`, `CODE_SIGNING_REQUIRED: YES` under the target's `configs: Release:` block; keep Debug (`base`) unsigned. Update the comment block at `project.yml:12-19` to describe the new split.
- [ ] 1.3 Run `xcodegen generate` and confirm the `.pbxproj` diff contains only the expected signing/entitlement changes.
- [ ] 1.4 Verify the Debug/simulator path is untouched: `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build` (no signing identity needed), and `xcodebuild test` on an available simulator — all green with warnings-as-errors.

## 2. iOS: Release build + device smoke (local)

- [ ] 2.1 Build/Install the Release configuration on a real device (signed with team `7923U48U87`); resolve any provisioning complaints (e.g. register the App Group in the portal if reported missing).
- [ ] 2.2 Run the new smoke checklist from README.md against the local backend (`APPLE_CLIENT_ID` set locally, `EMAIL_BACKEND=console`): Apple button → native sheet appears; complete sign-in (sandbox Apple ID, Hide My Email variant) → signed-in shell; cancel path → no error; airplane mode → button disabled.
- [ ] 2.3 Record any defects found and fix them under this change (code changes belong here, not deferred); re-run 1.4 linters/tests after any fix.

## 3. Backend: production enablement

- [ ] 3.1 Set `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` (leave `APPLE_JWKS_URL` default) in the production VM env file; redeploy the backend container (`docker-compose.prod.yml` already passes it through).
- [ ] 3.2 Verify gating end-to-end: `POST /api/v1/auth/apple` with a junk token now returns 401 `invalid_apple_token` (was 503 `apple_not_configured`); the OTP path still works; no secrets in logs (R1).

## 4. Smoke against production relay

- [ ] 4.1 From the Release device build, complete a full Sign in with Apple against `https://timeoflife-api.antonkosenko.pro`; confirm signed-in state, "Sync now" visible in Profile, and sync completes.
- [ ] 4.2 Verify Private Relay email handling: the relay address (`*@privaterelay.appleid.com`) is stored as the user email and `email_verified` is true.

## 5. Documentation and requirements alignment

- [ ] 5.1 Add the manual SIWA smoke checklist to `README.md` (build/install, sheet presentation, sign-in, cancel, offline, production relay, Private Relay email).
- [ ] 5.2 Update `docs/project-context.md`: distribution section (signing now configured for Release, TestFlight steps), "Sign in with Apple (F2)" section (entitlement + team + `APPLE_CLIENT_ID` live), and remove/adjust the "code signing is disabled" and "capability not enabled" statements.
- [ ] 5.3 Update `AGENTS.md` only where it repeats the signing/Apple claims (keep it short, pointing at project-context).
- [ ] 5.4 Re-check `Requirements/FURPS/Sign-up_and_Sign-in.md` (F2, F1) and `Requirements/Usecases/` rows; correct any rows that conflict with the now-enabled state.
- [ ] 5.5 Confirm OpenAPI needs no change (`/auth/apple` contract unchanged; config-only enablement) — no spec edit expected.

## 6. Verification gates (S5)

- [ ] 6.1 Backend: `go build ./...`, `go test ./... -cover`, `golangci-lint run`, `gofmt -l .`, `go vet ./...` — green (no Go changes expected; run to prove it).
- [ ] 6.2 iOS: `xcodegen generate`, `swiftlint lint --strict`, simulator build + test (`xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`) — green.
- [ ] 6.3 CI: push a branch and confirm `ios.yml` (and `backend.yml` if touched) pass; PR mergeable with mandatory checks green.
- [ ] 6.4 Mark this change ready for archive only after the production smoke (section 4) passes; update `docs/project-context.md` "Incomplete / deferred" (SIWA follow-ups: nonce, account deletion, credential-state remain deferred to their own changes).