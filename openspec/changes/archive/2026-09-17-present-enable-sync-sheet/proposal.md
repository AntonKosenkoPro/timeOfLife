## Why

Tapping "Enable Sync" in Profile does nothing visible unless a valid session happens to sit in the Keychain: the row fires a silent `restoreSession()` (no sheet, no spinner, no error) that early-returns when no refresh token exists. Users hitting the dead tap conclude sync is broken. Auth is an optional, fully working flow (`AuthFlowView`: Welcome → EmailEntry → OtpEntry + Sign in with Apple) — it is just unreachable, with no presentation site anywhere since the app launches into the Track shell. This change wires the row to the flow it promises.

## What Changes

- Tapping "Enable Sync" first attempts the silent restore; when the session is still signed out afterward, it presents `AuthFlowView` as a sheet (same `.sheet` + `environmentObject(container)` pattern as the Profile sheet itself). A restorable session still signs in frictionlessly; a missing one now opens the auth flow instead of dying silently.
- The sheet dismisses on successful sign-in (session flips to `.signedIn`) and offers an explicit Cancel close affordance; dismissing without signing in returns to Profile, unsigned, with local data untouched.
- The row and sheet copy frames auth as an optional cross-device-sync upgrade ("Enable cross-device sync" voice), not as a sign-in gate — EN + RU + `L10n`, per U4.
- No changes to the auth machinery itself: OTP, Apple sign-in, token lifecycle, `restoreSession()` semantics, `SessionStore`, and sync activation on sign-in all stay exactly as they are.

Non-goals: no auth-flow redesign (Welcome/Email/OTP screens untouched); no token, Keychain, or backend changes (no OpenAPI touch); no launch-gating (the shell remains the root for signed-out users); no account-deletion/revocation work (deferred Sign in with Apple follow-ups stay deferred); no new sync triggers.

## Capabilities

### New Capabilities
(none — this revives and presents the existing auth flow)

### Modified Capabilities
- `app-shell`: the Profile "Enable Sync" action changes from silent-restore-only to restore-then-present-sheet, with dismiss-on-sign-in and an explicit close path.

## Impact

- iOS only: `ProfileView` (sheet state + restore-then-present branching + dismiss observation), possibly a close button on the sheet root, 2–4 new localized strings (sheet title/sync framing + Cancel), SwiftTesting coverage for the branching (restore-succeeds vs restore-still-signed-out) following existing auth VM patterns.
- No backend, sync-client, store, or navigation-stack changes. `AuthFlowView` gains its first (and only) presentation site.
