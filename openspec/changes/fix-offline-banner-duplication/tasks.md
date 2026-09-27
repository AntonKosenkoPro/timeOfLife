## 1. Change artifacts

- [x] 1.1 Rewrite `proposal.md` (removal scope) + write `specs/app-shell/spec.md` (delta: no banner; offline via pull notice + sync status), `design.md`, and this `tasks.md`.
- [x] 1.2 `openspec validate fix-offline-banner-duplication --strict` passes; fix all findings.

## 2. Implementation (banner removal only)

- [x] 2.1 Remove the `OfflineBanner` struct (`RootView.swift:208-226`) plus its `.safeAreaInset(edge: .top)` insertion in the signed-in body (`RootView.swift:41-45`). Keep `Theme.danger` itself (used by `PrimaryButton`, `TextFieldWithError`, `ListRow`, `ErrorBanner`, `OtpCodeField`). Do NOT touch `LogTimeView.swift`, `HistoryView.swift` (read-only), `CatalogIcon.swift`, `openapi.yaml`, `TrackContent.swift`, `TrackView.swift`, `Design/TOKENS.md`.
- [x] 2.2 Remove the `offlineBanner` case from `String+Localized.swift` plus the `offline.banner` rows in `en.lproj`/`ru.lproj` `Localizable.strings`. Update `LocalizationTests.swift` (`allCasesCount` 137 → 136 + reword the stale "banner text" test name; the `error.offline` mapping test itself stays — it covers a different key).
- [x] 2.3 Keep-surfaces are read-only: confirm `HistoryPullModel` offline → `PullNoticeBanner` and `SyncController.status` `.error("offline")` → Profile row still render (no code change).

## 3. Tests

- [x] 3.1 No new unit tests: removal is compiler-pinned (a leftover `OfflineBanner()` or `L10n.offlineBanner` reference fails the warning-as-error build) and `LocalizationTests` covers the enum/strings parity. Existing `HistoryPullModelTests` (offline notice) and `SyncControllerTests` (offline status) cover the keep-surfaces.

## 4. Manual on-device checklist

- [ ] 4.1 Go offline on Track — no red banner, no other global offline hint.
- [ ] 4.2 Go offline on History, pull to refresh — inline offline notice appears (`HistoryOfflineNotice`), auto-dismisses.
- [ ] 4.3 Go offline, open Profile — sync-status error row visible; tap "Sync now" online recovers to idle.
- [ ] 4.4 Light/dark + EN/RU spot-check that no layout gap remains where the banner sat (top inset collapses).

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean (0 violations); warning-as-error `xcodebuild build-for-testing` green; full iOS suite green — 490 tests / 48 suites passed. Serialized per `docs/ios-test-loop.md` (log-file polling, booted-sim-by-ID destination). Backend untouched by this change (no `go` run needed; `openapi.yaml` not modified by this change).
- [x] 5.2 Re-checked `Requirements/FURPS/*.md` rows (`Timetracking.md` F1/F5/F9 local-first offline behavior unchanged — the banner is presentation, and F9's "inline offline banner" names the History pull notice which stays; `Common.md` U3 no conflict). No FURPS edit needed.
- [x] 5.3 Updated `docs/project-context.md` (the two `OfflineBanner` "remains/stays" lines → removal), this change's tasks checkboxes. No architecture/contract/run-step changes beyond the specified behavior.
- [x] 5.4 Push branch `fix/34-remove-offline-banner` + `gh pr create` targeting `main` (PR #55; title "Remove offline banner (#34)", body "Fixes #34" + removal rationale + the two keep-surfaces + the Track-tab consequence + verification evidence). DO NOT merge. Based on `main`, NOT on PR #53/#54 branches.
