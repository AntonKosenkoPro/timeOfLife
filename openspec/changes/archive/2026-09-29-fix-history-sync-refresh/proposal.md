## Why

Pulling cross-device changes via Profile → Sync now while staying on the History tab leaves the History list stale until the user leaves and re-enters the tab. Users cannot trust that sync worked, and may miss or duplicate entries.

## What Changes

- History list reloads automatically when a sync cycle completes while History is visible (no tab switch required).
- Insights breakdown reloads on the same signal (it shares History's guarded-reload lifecycle and has the same staleness bug).
- Sync itself is unchanged: same drain + pull + LWW + tombstone path; only the read-side invalidation changes.
- Non-goals: no push-triggered realtime sync, no background fetch changes, no LocalStore publisher refactor, no OpenAPI/backend changes, no new strings or visual design.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `history-entry-list`: History SHALL reflect committed entries merged by a sync cycle without requiring tab re-entry.
- `insights-breakdown`: Insights SHALL reflect committed entries merged by a sync cycle without requiring tab re-entry.

## Impact

- Affected code: `HistoryView` / `HistoryViewModel` (`invalidate` + `loadIfNeeded` lifecycle, new sync-completion observation), `InsightsView` / `InsightsViewModel` (same), `AppShellView` (wiring `SyncController.status` or dismissal signal into both tabs), `SyncController` (read-only status observation only — no cycle changes).
- Tests: `HistoryViewModelTests` / `InsightsViewModelTests` (reload-after-sync), plus a SwiftUI/host-level check that Profile-sheet dismissal after `syncNow` refreshes the visible list.
- No API, schema, entitlement, or localization impact.
