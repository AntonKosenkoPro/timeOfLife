## Why

Profile's Sign Out row is the only row without an icon and without the shared `ListRow` geometry, so it reads as alien next to Sync now / Categories / Erase local data (issue #68, labels `bug` + `Visual only`). Small visual parity fix before release.

## What Changes

- Profile Account section: render Sign Out through the shared `ListRow` with leading SF Symbol `rectangle.portrait.and.arrow.right` and `tint: Theme.danger` (icon + title warn together), inside `Button(role: .destructive)` — same shape as the Erase local data row.
- Behavior unchanged: tap still calls `container.authService.logout()`; accessibility id stays `ProfileSignOutButton`; `RootView` gate sign-out placeholder untouched visually (not a List surface) but adopts the renamed key.
- Rename the mis-scoped L10n key `timer.signOut` → `profile.signOut` (en + ru, same copy; `ProfileView` + `RootView` gate call sites; `L10n.timerSignOut` → `L10n.profileSignOut`).
- Add lightweight coverage for the sign-out row contract (icon + danger tint + stable id) following existing SwiftTesting patterns.
- Non-goals: no auth-flow, sync, or data-model changes; no sign-out copy change; no GateSignOutButton restyle; no new component (reuse `ListRow`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-shell`: Profile destructive rows share one visual contract — Sign Out SHALL render with the same `ListRow` geometry, leading icon, and danger tint as the other destructive row.

## Impact

- Affected code: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/ProfileView.swift` (`accountSection`), `Features/Auth/Views/RootView.swift` (gate call site adopts renamed key), `Localization/String+Localized.swift` + `en`/`ru` `Localizable.strings` (rename, same copy).
- Docs: `Design/COMPONENTS.md` `ListRow` signature note (already drifted — implementation carries `tint`, spec block does not).
- Tests: new/extended SwiftTesting coverage for Profile sign-out row; `LocalizationTests` `allCases` count stays 146 (rename, not add).
- No API, migration, OpenAPI, or dependency changes. No external library behavior involved (system SF Symbol on iOS 18+ floor); no ctx7 fetch required.
