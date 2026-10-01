## Why

Profile's "Last synced" row has three defects (all user-reported): it goes stale while Profile is open (rendered once per sync event, never refreshed); it shows second-level precision ("0 sec. ago") the user calls noise; and in Russian it can read nonsense ("Синхронизировано: через 0 сек." — future tense for a past event) because the relative fragment comes from the system `RelativeDateTimeFormatter`, not from localizable strings, so it cannot be found or fixed in the `.strings` files.

## What Changes

- Replace the system-formatter relative time with minute-bucketed labels: under a minute → "Less than a minute ago"; 1–59 minutes → "N minute(s) ago"; 1–23 hours → "N hour(s) ago"; 24 hours and up → "N day(s) ago" with no upper cap (no weeks/months/years, per user call). Dates in the future (clock skew) clamp to the under-a-minute bucket — the "через …" class of nonsense disappears by construction.
- Refresh the row in real time while Profile is visible (minute cadence tick driving re-render; no tick needed for syncing/error/inactive states).
- Keep system-formatter pluralization, drop system-formatter unit choice: per-bucket `DateComponentsFormatter` with restricted `allowedUnits` + `maximumUnitCount = 1` renders the quantity ("37 minutes", never seconds/weeks/years — verified: truncates, 400 days stays days, correct RU 1/2/5/11/21 forms free). Only glue words move into localization: a `profile.lastSynced.ago` order-wrapper plus a `profile.lastSynced.justNow` key in en + ru — so every future language costs 2 plural-free keys and zero plural logic. Dates in the future (clock skew) clamp to the just-now bucket.
- Behavior otherwise unchanged: same `SyncStatus` publisher, same row icon, same error/syncing/inactive branches, no sync-engine changes.
- Non-goals: no `SyncController` cycle logic changes; no exact-timestamp ("14:32") surface; no weeks/months/years buckets ever.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sync-client`: the "Manual sync and status visibility" requirement's "Last synced: \<relative time\>" becomes minute-bucketed, self-refreshing, and fully localized (new SHALLs + scenarios).

## Impact

- Affected code: `ProfileView.syncStatusRow` + relative-time helper (new pure helper: elapsed → bucket; quantity via `DateComponentsFormatter`), `Localization/String+Localized.swift` + en/ru `.strings` (2–3 glue keys, no `.stringsdict`), new SwiftTesting boundary/clamp tests.
- Docs: `Design/COMPONENTS.md` untouched (no component change); OpenSpec delta on `sync-client`.
- No API, migration, OpenAPI, or dependency changes. No external library behavior involved (Foundation date math + SwiftUI refresh only); no ctx7 fetch required.
