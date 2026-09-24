# Design — enable-sign-in-with-apple

## Context

The SIWA flow is implemented and unit-tested end-to-end (see proposal.md — Why): iOS `AppleSignInService` (injectable provider), `WelcomeViewModel.signInWithApple()` (cancel-silent, error-banner otherwise), `AuthService.signInWithApple` → `persist` → `SessionStore`; backend `internal/apple` verifier (RS256 + JWKS via keyfunc, `iss`/`aud`/`exp`), `UpsertUserByAppleSubject`, config-gated 503, per-IP rate limit, OpenAPI + contract tests. What has never happened is a run against real Apple infrastructure: no entitlement, no signing, no `APPLE_CLIENT_ID` in production.

Portal-side inputs are already collected: App ID `com.antonkosenko.timeoflifeapp` with the SIWA capability enabled (exact-match App ID — the wildcards `com.antonkosenko.*` and `*` cannot carry app services), and Apple Developer Team ID `7923U48U87`.

Constraints inherited from `docs/project-context.md`: XcodeGen-managed project (edit `project.yml`, run `xcodegen generate`); warnings-as-errors on app/test targets; CI (`ios.yml`) builds for the generic simulator destination and must stay green; pre-release policy — no legacy branches anywhere.

## Goals / Non-Goals

**Goals**

- A signed Release build that can present the real Apple sheet and complete sign-in against the production relay.
- CI and local Debug builds keep working unsigned (tests, `xcodebuild build`, simulator).
- The production relay accepts real Apple tokens (`APPLE_CLIENT_ID` set on the VM).
- A repeatable manual smoke checklist capturing the paths fakes cannot verify.

**Non-Goals**

- Nonce replay defense — separate `harden-apple-signin` change (touches OpenAPI request shape + both sides).
- Account deletion + Apple `/auth/revoke` (App Store 5.1.1(v)) — own change, required before App Store submission but not before TestFlight.
- Apple credential-state/revocation observation (`getCredentialState`, `ASAuthorizationAppleIDProviderCredentialRevokedNotification`).
- Identity merging between OTP-email accounts and Apple accounts (documented decision: separate identities).
- Automating the TestFlight upload (fastlane/App Store Connect API) — manual Xcode upload is acceptable at this scale.

## Decisions

### D1: Per-configuration signing — Debug unsigned, Release signed

Set `DEVELOPMENT_TEAM: 7923U48U87` and signing identity settings on the **Release** configuration only; Debug keeps `CODE_SIGNING_REQUIRED: NO` / empty identity. The comment block in `project.yml:12-19` (marked as the exact lines to flip) is updated to describe the new state.

- **Why**: CI (`ios.yml`) and every simulator test run use Debug; signing them would require a signing identity on every CI runner and a provisioning profile for the test target — churn with no benefit. Release is the only configuration that archives for TestFlight.
- **Alternatives considered**:
  - *Sign everything* — breaks CI unless runners hold distribution certs + keychain setup; rejected for now (fastlane match etc. is a later, separate investment).
  - *Leave signing off and sign ad hoc at archive time via xcodebuild flags* — keeps `project.yml` misleading and makes local archive reproduction fragile; rejected.
- XcodeGen applies config-scoped settings via the target's `configs:` map (same mechanism already used for `SWIFT_ACTIVE_COMPILATION_CONDITIONS` at `project.yml:91-93`).

### D2: Entitlement added to the existing entitlements file

Append `com.apple.developer.applesignin` (`Default` → the string `"default"` per Apple's SIWA entitlement format) to `TimeOfLife/Configuration/TimeOfLife.entitlements`, which already carries the App Group entry and is wired via `CODE_SIGN_ENTITLEMENTS` (`project.yml:79`). No new file, no `project.yml` entitlement plumbing beyond what exists.

### D3: Backend enablement is config-only, treated as a deployment step

`docker-compose.prod.yml` already passes the `APPLE_CLIENT_ID` env var through (empty = 503). The change only (a) sets the value on the VM's env file and (b) restarts the backend container. `APPLE_JWKS_URL` keeps its default (`https://appleid.apple.com/auth/keys`) — the verifier already pins RS256, `iss`, and 30s leeway, and `aud` validation enforces the Bundle ID match. No code changes on the backend.

### D4: Smoke checklist lives in `README.md` as a manual section

The checklist documents: build+install on a real device with the entitlement; tap Apple button → native sheet appears; complete sign-in with a sandbox Apple ID (Hide My Email variant) → lands signed-in; backend logs show the Apple upsert; cancel path shows no error; airplane-mode start (button disabled). These are the behaviors the unit tests explicitly fake out (`AppleAuthorizationProviding`), and the JWKS fetch is hit for real only in production config.

### D5: No Swift/Go source changes

The flow code exists and is covered by unit tests (`WelcomeViewModelTests`, `apple_test.go`, `verifier_test.go`, contract tests). This change is entitlement + build settings + deployment config + docs. If the device smoke exposes a code defect, it is fixed under this change's tasks but the design anticipates none.

## Risks / Trade-offs

- [Entitlement present but App ID capability mismatch → runtime authorization failure only visible on device] → the portal App ID was verified to carry SIWA before this change; the smoke checklist makes the failure mode explicit and early.
- [Signing Release may surface missing capabilities/profiles at archive time (e.g. App Group needs the group registered on the team)] → smoke the Release build locally (device install) before the TestFlight upload; register the App Group in the portal if Xcode's automatic signing reports it missing.
- [CI regression from regenerated project] → after `xcodegen generate`, run the exact `ios.yml` steps locally (swiftlint, simulator build, tests) before pushing.
- [`aud` mismatch between entitlement/portal/config is silent until first real sign-in] → all three now hold the same literal `com.antonkosenko.timeoflifeapp`; the smoke checklist's backend-log step confirms the chain end-to-end.
- [TestFlight testers hit a 503 because the VM env update was skipped] → the backend deployment step is a checklist item in tasks.md with a verification curl (503 before, 200 after a real token).

## Migration Plan

1. Local: entitlements + `project.yml` signing + `xcodegen generate` + lint/build/tests green (Debug unsigned path).
2. Local: Release device build/install → device smoke (sheet, sign-in vs local backend, cancel path).
3. Deploy: set `APPLE_CLIENT_ID` on the VM env, redeploy the backend container, verify `/auth/apple` transitions from 503 to live behavior.
4. Smoke against production relay from the device build.
5. Rollback: each step is independently revertible — remove the entitlement key, restore the empty `DEVELOPMENT_TEAM`, or unset `APPLE_CLIENT_ID` (route degrades to 503, OTP path unaffected; existing sessions keep working).

## Open Questions

None — portal inputs confirmed (App ID + capability, Team ID), production URL known (`https://timeoflife-api.antonkosenko.pro`), and the App Group registration state is a listed risk with an in-portal fix rather than a design unknown.