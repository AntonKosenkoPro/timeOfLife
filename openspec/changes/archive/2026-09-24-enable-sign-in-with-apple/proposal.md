# Enable Sign in with Apple

## Why

Sign in with Apple (F2) is implemented end-to-end in code but has never run against real Apple servers: the build is unsigned (`DEVELOPMENT_TEAM: ""`), the SIWA entitlement is absent, and the production backend lacks `APPLE_CLIENT_ID` (the `/auth/apple` route answers 503). A TestFlight build is planned for next week, so the capability must be turned on and smoke-verified on a real device before distribution. App Store account deletion (5.1.1(v)) and token-revocation are explicitly deferred to a later change.

## What Changes

- Add the `com.apple.developer.applesignin` entitlement to `TimeOfLife.entitlements`.
- Enable code signing for distribution: set `DEVELOPMENT_TEAM: 7923U48U87` in `project.yml` while keeping simulator/CI builds working unsigned (per-configuration signing — Debug stays unsigned for CI and tests; Release signs with the team and automatic signing).
- Configure the production backend: set `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` (and keep the default `APPLE_JWKS_URL`) on the VM so `/auth/apple` serves real sign-ins instead of 503.
- Add a manual smoke checklist (real device + sandbox Apple ID) to `README.md` covering the only paths fakes cannot verify: the Apple sheet presentation, the real JWKS fetch, `aud` match, and Private Relay email handling.
- Update `docs/project-context.md` (TestFlight/distribution and SIWA sections) and `AGENTS.md` to reflect that signing is now configured and SIWA is live.

Non-goals (documented, deferred): nonce replay defense (separate `harden-apple-signin` change), account deletion + Apple `/auth/revoke` (App Store submission prerequisite, own change), Apple credential-state/revocation observation, and identity merging between OTP-email accounts and Apple accounts — Apple accounts and email accounts remain separate identities by design.

## Capabilities

### New Capabilities

- `apple-signin`: the end-to-end Sign in with Apple contract — the welcome-screen button as the primary auth path, the credential exchange for a session, config gating (`apple_not_configured` 503), and the deployment preconditions (entitlement, signing, `APPLE_CLIENT_ID`) that make the flow actually reachable. No auth baseline spec exists today; this change introduces one so the TestFlight-critical behavior is pinned.

### Modified Capabilities

<!-- None: existing baselines (app-shell, sync-client, local-first-store, ...) do not change. Session issuance reuses the existing token pair and SessionStore flow; no spec-level behavior of any existing capability changes. -->

## Impact

- **iOS**: `ios/TimeOfLife/project.yml` (signing settings), `TimeOfLife/Configuration/TimeOfLife.entitlements`; regenerates the `.pbxproj` via `xcodegen generate`. No Swift code changes expected — the flow already exists and is unit-tested with fakes.
- **Backend (config only)**: `APPLE_CLIENT_ID` on the production VM (documented in `.env.example` already; `docker-compose.prod.yml` already wires the env var). No Go code changes.
- **Distribution**: first signed build; the CI workflow (`ios.yml`, generic simulator destination) must stay green with unsigned Debug signing — verify after regenerating the project.
- **Docs**: `README.md` (smoke checklist), `docs/project-context.md` (distribution + SIWA sections), `AGENTS.md` (short pointer updates).
- **App Store Connect**: app record creation and TestFlight upload are manual operator steps, listed in the smoke checklist, not automated in this change.