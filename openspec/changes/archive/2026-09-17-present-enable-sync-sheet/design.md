# Design: Enable Sync Sheet

## Context

See `proposal.md` (Why) for motivation. Grounded facts shaping the approach:

- The row (`ProfileView.swift:45-54`) fires `authService.restoreSession()` with no feedback; `restoreSession()` early-returns when no refresh token exists (`AuthService.swift:76`) — the silent no-op.
- `AuthFlowView` is a plain `View` (Welcome root + email/otp push routes over `container.navigation`) with **no presentation site anywhere** — verified: the only `AppStack` consumer in the app. Hosting it in a `.sheet` cannot mirror pushes anywhere else.
- `SessionStore.state` is `signedOut` / `signedIn(CachedSession)`; sign-in flips come through `persist()` on both OTP and Apple paths, so observing the store covers every success route.
- RootView already restores on launch — the tap-time restore only matters for sessions that became unrestorable later (expiry, Keychain change), which is exactly the dead-tap population.
- No generic "Cancel" key exists (scoped copies only); the row copy (`profile.enableSync*`) predates the sync-as-upgrade framing.

## Goals / Non-Goals

Goals: every tap leads somewhere visible — silent success or the auth sheet — with unit-covered branching and localized sync-upgrade copy.

Design-level non-goals: no auth-flow screen changes, no session/token/backend changes, no new navigation infrastructure.

## Decisions

### D1: Restore-then-present branching in a tiny testable seam
ProfileView owns a `@State` sheet flag; on tap it runs `restoreSession()` then presents iff state is still `.signedOut`. To keep the branch unit-testable (the repo has no view tests), the decision lives in a focused `@MainActor` helper (e.g. an `EnableSyncPresenter` observable with injected `restore` + `isSignedIn` closures and a published sheet flag) rather than inline in the view body.

*Alternatives considered*: presenting the sheet unconditionally without restoring first (rejected — adds friction for the restorable-session case that works today); putting the branch directly in `ProfileView` with no seam (rejected — untestable branching is how this dead tap shipped in the first place).

### D2: Sheet hosts `AuthFlowView` unchanged, Cancel + auto-dismiss at the sheet level
Sheet content is `AuthFlowView().environmentObject(container)` (the Profile-sheet pattern) with a `cancellationAction` Cancel toolbar item (new scoped key, EN+RU) and dismissal on `.signedIn` (observed via an `isSignedIn` mapping, since the state enum carries an associated value) plus the swipe-to-dismiss the sheet gets for free. No changes inside Welcome/Email/OTP views.

*Alternative considered*: adding the close button inside `WelcomeView` (rejected — scatters sheet chrome into a flow screen; the sheet owns its chrome).

### D3: Copy reframes to sync-upgrade, reusing keys where honest
Row keeps its identity; the sheet title/subtitle use the "Enable cross-device sync" voice (new keys), Cancel gets one scoped key. Existing `profile.enableSync*` values are reworded only if they read as sign-in-gating; key names stay (no `L10n`/test churn beyond additions).

## Risks / Trade-offs

- [Risk] Shared `container.navigation` stack misbehaves inside a sheet → Mitigation: verified single `AppStack` consumer; pushes render only in the sheet. If the sheet ever shares the screen with another stack consumer, revisit.
- [Risk] Restore is slow (network `/me`) with no spinner — tap feels dead for a beat → Mitigation: disable the row while the restore Task runs (existing `disabled` pattern as on Sync Now); the sheet appears promptly after since restores resolve fast or fail fast. No new loading UI.
- [Risk] Sign-in completes while the user already swiped the sheet away → Mitigation: harmless — dismiss is idempotent, Profile re-renders signed-in underneath.

## Migration Plan

None. Presentation-only change; no persisted formats, no contract, no flags. Rollback = restore the old button action.

## Open Questions

None — API surfaces verified above; copy wording settles at implementation/review within the spec's normative frame.
