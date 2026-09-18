## 1. iOS functional rename

- [ ] 1.1 Set `CFBundleDisplayName: Lifio` in `ios/TimeOfLife/project.yml` and mirror the literal in `TimeOfLife/Configuration/Info.plist`; run `xcodegen generate` once and confirm the project diff is limited to display-name lines (never hand-edit the `.pbxproj`)
- [ ] 1.2 Set `"app.name" = "Lifio"` in both `TimeOfLife/Localization/en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, including the file header comments (U4: both locales + `L10n`)
- [ ] 1.3 Update product-name code comments to Lifio: `WelcomeView.swift` header, `TimeOfLifeApp.swift` header, `Config.Debug.xcconfig` / `Config.Release.xcconfig` comments; leave all identifiers (`TimeOfLife` module, bundle ID, group, keychain, queue labels, DB filename) untouched
- [ ] 1.4 Verify frozen identifiers byte-identical: `PRODUCT_BUNDLE_IDENTIFIER`, App Group entitlement + `LocalStore.appGroupID`, Keychain service/keys, `databaseFileName`, API base URLs, scheme/target/module names

## 2. Backend docs-only rename

- [ ] 2.1 Update `backend/api/openapi.yaml` human-readable product references (`title`, description) to Lifio; no endpoint, schema, or server-URL change (S10: contract itself untouched)
- [ ] 2.2 Update backend product-name code comments only (`cmd/server/main.go`, `Makefile`, compose-file header comments); leave DB names, image names, domains, and env examples byte-identical

## 3. Spec / doc prose sweep

- [ ] 3.1 Replace "Time of Life" product prose with Lifio in `README.md`, `AGENTS.md`, `docs/project-context.md`, `openspec/config.yaml` inline context, `Design/*.md` + `Design/SCREENS/*`, and localization file headers; explicitly exclude `openspec/changes/archive/**` (immutable history) and D4 identifier values
- [ ] 3.2 Run repo-wide `rg -i "time of life"` and confirm the only remaining hits are `openspec/changes/archive/` history and frozen identifier-adjacent values; run `rg '"app.name" = "Lifio"'` and confirm exactly the two locale files hit
- [ ] 3.3 Re-check the relevant `Requirements/FURPS/*.md` rows for product-name references and align any conflicts

## 4. Verification

- [ ] 4.1 From `ios/TimeOfLife/`: `swiftlint lint --strict` clean, warning-free `xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build`, `xcodebuild test -scheme TimeOfLife` green
- [ ] 4.2 From `backend/`: `gofmt -l .` empty, `go vet ./...`, `golangci-lint run`, `go test ./...` green
- [ ] 4.3 Simulator smoke: Home-screen name reads "Lifio"; Welcome brand title reads "Lifio" in both English and Russian locales
- [ ] 4.4 Human step (outside repo): confirm "Lifio" availability in App Store Connect before shipping
