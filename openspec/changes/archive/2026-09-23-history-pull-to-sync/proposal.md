## Why

History is the only tab with no user-initiated sync: sync runs on foreground, connectivity-restored, and Profile "Sync now", but a user staring at a stale History list has no gesture to ask for fresh relay state. Pull-to-refresh closes that gap with a sync-only gesture (local-live is the named follow-up, not this change).

## What Changes

- History list gains pull-to-refresh (`.refreshable` on the populated list branch only) that triggers a sync cycle and rides the existing `sync.status → invalidate + load` reload.
- Pull while a cycle is already in flight **joins** it: the spinner awaits the in-flight cycle instead of starting a second one.
- Signed-out pull shows an inline signed-out banner with a sign-in link (opens the Enable Sync auth sheet), auto-dismissed after 5 seconds.
- Signed-in but offline pull shows an inline offline banner in the same slot, auto-dismissed after 5 seconds (pre-checks connectivity; does not burn a cycle).
- A pull-initiated sync failure presents a modal error dialog with a single OK button (background failures never pop the dialog).
- Empty History has no pull affordance in this change.

## Capabilities

### New Capabilities

None — behavior lands on existing capabilities.

### Modified Capabilities

- `history-entry-list`: pull-to-refresh gesture scope, inline verdict banners (signed-out with sign-in link / offline), pull-gated error dialog, empty-state exclusion.
- `sync-client`: pull as a fourth sync trigger; `syncNow` joins an in-flight cycle instead of running concurrently.

## Impact

- iOS: `HistoryView` (+ banner/dialog presentation state), `SyncController.syncNow` join semantics, Enable Sync sheet presentation ownership (currently Profile-only), new `L10n` keys (EN+RU per U4).
- No backend / OpenAPI change. No outbox/drain/pull/LWW/tombstone change. No `LocalStore` schema or publisher change.
- Tests: `SyncControllerTests` (join), new History pull-state tests, `LocalizationTests` (`L10n.allCases` if enumerated).

### Non-goals

- No explicit local reload in the pull path (relies on the existing cycle-exit reload; full live History is the follow-up).
- No pull on the empty state; no Retry button on the error dialog; no "Last synced" caption in History; no cross-process live updates; no midnight-rollover timer.
