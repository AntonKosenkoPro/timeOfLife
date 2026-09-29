## Why

Investigation proved there is no second legacy banner: the only red banner is the `OfflineBanner` in `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/RootView.swift:210-226` (rendered via the `safeAreaInset` in the `RootView` body). The user tested latest `main`, confirms the banner shows, and wants it gone: in a local-first app offline is a normal state, not an emergency, and the red top banner is visual noise. Offline indication via the History pull-to-refresh offline notice and the Profile sync status is enough.

## What Changes

- Remove the `OfflineBanner` struct and its `safeAreaInset` insertion in the `RootView` body entirely — no global offline banner anywhere.
- Remove the now-unused `L10n.offlineBanner` key plus its `en`/`ru` `Localizable.strings` rows; update `LocalizationTests` consistently (`allCases` count, stale banner wording).
- Keep (read-only, untouched): the History pull-to-refresh offline notice (`HistoryPullModel` verdict → `PullNoticeBanner`) and the Profile sync-status row (`SyncController.status` `.error("offline")`).
- No behavior change to sync, connectivity detection, or offline editing — signed-in offline keeps working.
- Accepted consequence: the Track tab will show no offline hint (`TrackView.swift` already documents "no offline hint").

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `app-shell`: no global offline banner; offline is surfaced via the History pull-to-refresh offline notice plus the Profile sync status.

## Impact

- `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/RootView.swift` (`OfflineBanner` struct + body insertion removed).
- `ios/TimeOfLife/TimeOfLife/Localization/String+Localized.swift` (`offlineBanner` case removed) + `en.lproj`/`ru.lproj` `Localizable.strings` (`offline.banner` rows removed).
- `ios/TimeOfLife/TimeOfLifeTests/LocalizationTests.swift` (`allCases` count 137 → 136 + stale banner wording).
- No OpenAPI, store, sync, or navigation changes. Visual-only.
- Ownership guards (do NOT touch): `LogTimeView.swift`, `HistoryView.swift` (read-only), `CatalogIcon.swift`, `openapi.yaml`, `TrackContent.swift`, `TrackView.swift`, `Design/TOKENS.md`.
