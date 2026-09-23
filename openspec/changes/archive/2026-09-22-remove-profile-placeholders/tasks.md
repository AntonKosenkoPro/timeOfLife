## 1. Profile restructure

- [x] 1.1 Remove `connectionsSection` and the Appearance / Data & Privacy rows from `ProfileView`; fold Categories + Erase into a single `On This Device` section with local-first footer, Account untouched
- [x] 1.2 Verify signed-out (Enable Sync + 2 rows) and signed-in (sync status + Sync now + Sign out + 2 rows) states render with no inert rows, Erase stays last with `Theme.danger` + confirm alert

## 2. Localization cleanup

- [x] 2.1 Delete the 7 unused `L10n` keys (`profileLibrary`, `profileConnections`, `profileIntegrations`, `profileExport`, `profileApp`, `profileAppearance`, `profileDataAndPrivacy`) and their `en`/`ru` strings; add `profileOnDevice` (+ footer key) in both locales
- [x] 2.2 Run `LocalizationTests` parity (every `L10n` case resolves in both bundles)

## 3. Verification and docs

- [x] 3.1 Run `swiftlint lint --strict` and warning-as-error `xcodebuild` build + iOS test suite green
- [x] 3.2 Re-check `Requirements/FURPS/*.md` rows for Profile/shell alignment; confirm no OpenAPI/backend change needed
- [x] 3.3 Confirm spec scenario "No placeholder rows" holds by inspection on device/simulator (all visible rows tappable or live status)
