## Why

After a reinstall, the app flashes the login screen for 2–3s, then reveals an empty Track screen (no recents, empty name-picker list) that only becomes normal after leaving the tab and coming back. The shell is revealed before local init finishes and Track never reloads when init lands — a launch-lifecycle race, not slow hardware.

## What Changes

- Reorder `RootView.beginSignIn` to **open → commitAll → seed → reveal → activate**: the shell mounts only after the account file is bound, buffered deletions are committed, and starter categories are seeded. The first-sync network pull stays background (never blocks reveal).
- Make Track self-healing like History/Insights: reload recents/allNames/categories when the sync cycle exits (`.idle`/`.error`), so relay-pulled data appears without a tab switch.
- Add a restoring state to the launch gate: while `restoreSession()` is in flight the gate shows a splash (spinner, app identity) instead of the auth flow — no login flash when a session is being restored.
- Non-goals: gating the shell on first-sync pull completion; GRDB ValueObservation / live queries; offline-behavior changes (signed-in offline keeps working); Keychain / App Group storage migration; visual redesign of Track or auth screens.

## Capabilities

### New Capabilities
- None — this is a lifecycle/ordering bugfix over existing capabilities.

### Modified Capabilities
- `app-shell`: launch gate gains a restoring state (splash while session restore is in flight); shell mounts only after local bind+seed complete.
- `account-bound-store`: sign-in lifecycle ordering becomes open → commitAll → seed → reveal → activate (seed moves before reveal; pull stays background).
- `timer-capture-experience`: Track reloads after seed/sync land (no empty flash; name picker and recents converge without tab switch).

## Impact

- iOS only, no backend / OpenAPI change: `RootView.swift` (gate + `beginSignIn` ordering), `AppShellView.swift` / `TrackView.swift` (sync-status reload observer), `SessionStore`/`AuthService` (restoring signal), `AuthGateTests` + Track/History-pattern tests.
- No external-dependency behavior involved (pure SwiftUI lifecycle + GRDB reads already in use) — no ctx7 fetch; no version pin.
