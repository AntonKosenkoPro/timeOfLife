# Erase Resets Auth Flow

## Why

"Erase local data" (`ProfileView.eraseLocalData`) wipes the database via `LocalStore.eraseAll()` and signs out via `AuthService.logout()`, but the auth navigation stack (`AppNavigationStack.path`, `@Published [AppRoute]`) keeps the routes the user previously walked: `[.emailEntry, .otpEntry(oldEmail)]`. After erasing, tapping "Enable Sync" reopens `AuthFlowView` straight onto the stale OTP screen pre-filled with the previous address — a fresh-install device presenting a half-completed sign-in for an account whose local data no longer exists. The device should return to a fresh-install-like state, including the auth flow.

## What Changes

- Confirming "Erase local data" resets the auth navigation path to `[]` alongside the existing wipe + sign-out, so the next "Enable Sync" opens `AuthFlowView` at the flow's start with an empty email field (fresh `EmailEntryViewModel`).
- No other behavior changes: erase still wipes the store and outbox and still signs out; the auth flow screens, presentation (from `present-enable-sync-sheet`), session machinery, and sync activation are untouched.

Non-goals: no changes to `AuthService.logout()` semantics (plain sign-out still keeps whatever nav state the user had — only erase resets it); no changes to `EnableSyncPresenter` or mid-flow sheet-abandon resume behavior; no auth-flow redesign; no backend/OpenAPI changes; no new localized strings.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `local-first-store`: the "Sign-out preserves local data" requirement's explicit-erase behavior is extended — erasing also resets the auth navigation so the auth flow starts over.

## Impact

- iOS only, one line in `ProfileView.eraseLocalData` (plus regression coverage where feasible). No backend, store, sync-client, or contract changes. Verification is simulator E2E (`eraseLocalData` is a private view function — unit coverage is not practical); `swiftlint --strict` and `xcodebuild test` must stay green.