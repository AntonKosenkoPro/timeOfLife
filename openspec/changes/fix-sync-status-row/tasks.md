## 1. Bucketed relative label

- [x] 1.1 Add pure helper mapping elapsed seconds → bucket + `allowedUnits` (under-a-minute / minutes 1–59 / hours 1–23 / days 24h+, future clamps to under-a-minute) with no `Date()` inside; quantity rendered by `DateComponentsFormatter` (`maximumUnitCount = 1`)
- [x] 1.2 Add en + ru glue keys (`profile.lastSynced.ago` order-wrapper + `profile.lastSynced.justNow`, same copy semantics); no `.stringsdict`
- [x] 1.3 Rewire `ProfileView.syncStatusRow` idle branch to the helper + keys; drop `RelativeDateTimeFormatter`; add minute-cadence refresh scoped to the visible idle row
- [x] 1.4 Add SwiftTesting coverage (`@MainActor` suite): bucket boundaries through the real formatter in en + ru (incl. RU 1/2/5/11/21/22/25 spot-checks), future-date clamp

## 2. Verify

- [x] 2.1 Run `swiftlint lint --strict`, `xcodebuild -scheme TimeOfLife -destination '<available simulator>'` build + full `test` green (one xcodebuild at a time; `LocalizationTests` count updated for added keys)
- [ ] 2.2 Manual smoke: keep Profile open across a minute boundary (label advances), ru locale buckets read correctly, device-clock-ahead shows under-a-minute, syncing/error rows unchanged
- [x] 2.3 Run `openspec validate --all --strict` green; re-check FURPS Timetracking F5 row for conflicts
