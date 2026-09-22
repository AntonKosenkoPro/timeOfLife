## Why

"Erase local data" in Profile irreversibly wipes the local database (state + outbox + undo buffer + sync cursors), yet its row renders like a regular navigation row — blue `tag`-style icon treatment and primary text — instead of warning like the destructive action the `local-first-store` baseline and `Design/INTERACTIONS.md` say it is. The confirmation alert is correctly destructive, but the row the finger aims at gives no signal, and it is the least reversible delete in the app (entry/category deletes are buffered + restorable; erase is never restorable).

## What Changes

- Present the "Erase local data" Profile row as destructive (Option A, minimal): trash icon and title both render in `Theme.danger`, and the tappable control carries `Button(role: .destructive)` semantics.
- Fix the styling swallow: the current outer `.foregroundStyle(Theme.danger)` on `ProfileView.onDeviceSection` is overridden by `ListRow`'s hardcoded inner `Theme.accentPrimary` (icon) / `Theme.textPrimary` (title); move the danger styling inside the label so it actually lands.
- Keep everything else unchanged: same `On This Device` position below Categories, same footer, same title copy, same confirmation alert behavior.

Non-goals (explicitly out of scope for this change): moving Erase to its own section, adding a subtitle / permanence note / data counts to the row or alert, adding type-to-confirm or other friction, changing sign-out styling, changing the entry/category delete card pattern, any data-plane / sync / `LocalStore.eraseAll()` behavior change.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `local-first-store`: the "Explicit erase" requirement gains a row-presentation rule — the Profile "Erase local data" row SHALL present as destructive (danger icon + title, destructive button role), matching its already-specified destructive + irreversible semantics. No change to wipe semantics or auth-navigation reset.

## Impact

- Affected code: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/ProfileView.swift` (`onDeviceSection` erase row); possibly `ios/TimeOfLife/TimeOfLife/Core/Design/Components/ListRow.swift` if a reusable destructive/tint path is chosen over a local label override.
- Design tokens: `Theme.danger` only; no new colors, no raw `Color` literals.
- Strings: none (no copy change; existing `profile.eraseLocalData` keys reused in both locales).
- No API / OpenAPI, backend, sync-client, or on-disk format impact. No new dependencies.
