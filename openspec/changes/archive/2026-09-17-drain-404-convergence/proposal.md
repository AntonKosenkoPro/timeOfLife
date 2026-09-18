## Why

Field report (iPhone vs cloud backend): Profile shows `Sync failed … server(activity_not_found): Referenced activity not found`, and every "Sync now" fails identically. The drain pushed an entry create/update for an activity the relay no longer has (deleted on another device; entries cascade-vanished relay-side), `throw`s, the cycle dies before pull, and the row stays queued — a permanent wedge, retrying the same doomed push forever.

Tombstones-first ordering prevents this when both sides run the tombstone protocol, but three gaps remain: (1) a phone on an older client build never fetches tombstones; (2) a pre-tombstone relay has no `/deletions` route at all; (3) a timer stopped after its activity was tombstoned away wedges locally (`createEntry` FK-throws before the timer state clears, so Stop can never succeed). The drain must treat "the relay already deleted it" as convergence, not failure.

## What Changes

- **Push-404 convergence (client-only, no backend change)**: in `drainOutbox`, `activity_not_found`/`not_found` on entry create/update and `not_found` on activity/category update converge locally via the existing `applyDeletionTombstone` (delete row, cascade, drop create/update rows incl. the failing one) and the cycle continues. DELETE-404 stays success; activity/category CREATE-404 stays loud (impossible per routes).
- **Pre-tombstone relay tolerance**: `fetchDeletions` → `not_found` skips the tombstone step with a log (stateless — a later relay upgrade just starts working) instead of failing the cycle.
- **Stop on a deleted activity**: `TimerService.stopTimer` clears the timer state first and, when the activity is gone, skips the entry and throws typed `activityDeleted`; Track settles to idle with a localized "deleted on another device" message instead of looping `.error` → retry → fail.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sync-client`: push-404 convergence + tombstone-fetch tolerance.
- `timer-capture-experience`: stop-on-deleted-activity behavior.

## Impact

- iOS only (`SyncController`, `TimerService`, `TrackViewModel` message mapping, one L10n key EN+RU, tests). No schema change, no OpenAPI change, no backend change.
- Out of scope: relay-side changes; tombstone GC; the already-archived tombstone protocol itself.
