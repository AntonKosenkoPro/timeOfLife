## Why

The "Time of Life" product name is already taken (App Store collision), so the app cannot ship under it. Renaming the user-facing product to **Lifio** now — before any TestFlight / external release — unblocks distribution while there is still no on-disk data or installed base to migrate.

## What Changes

- User-facing product name changes from "Time of Life" to **Lifio** everywhere the user can see it: Home-screen display name (`CFBundleDisplayName`), Welcome-screen brand title (`L10n.appName` / `app.name`), and all user-facing docs.
- `app.name` localizations become `"Lifio"` in both `en.lproj` and `ru.lproj` (brand name is invariant across locales); header comments updated.
- Code comments, spec prose, and repo docs that say "Time of Life" are updated to "Lifio" where they describe the product (icon source, Control availability text, Welcome doc comments, config comments).
- **BREAKING (pre-release, accepted)**: none for users — no shipped builds exist. Internal module / scheme / target names (`TimeOfLife`), source-directory layout, and all stable identifiers stay unchanged (see Non-goals).
- New `app-identity` capability records the branding contract so the name has a spec home going forward.

## Capabilities

### New Capabilities
- `app-identity`: product identity contract — the app SHALL present itself as "Lifio" (display name, Welcome brand title, localized `app.name`), while bundle / group / storage identifiers remain the stable legacy values listed in the spec.

### Modified Capabilities
- `app-icon`: product references change from "Time of Life" to "Lifio" (artwork source and icon-role requirements unchanged).
- `lock-screen-controls`: "Time of Life Control" availability prose changes to "Lifio Control" (Control behavior unchanged).

## Impact

- **iOS app**: `ios/TimeOfLife/project.yml` (`CFBundleDisplayName`), `TimeOfLife/Configuration/Info.plist`, `en.lproj` / `ru.lproj` `Localizable.strings` (`app.name`), `WelcomeView.swift` doc comment, `TimeOfLifeApp.swift` doc comment, `Config.Debug/Release.xcconfig` comments. Regenerate with `xcodegen generate` after `project.yml` edit.
- **Specs/docs**: new delta `specs/app-identity/spec.md`; deltas for `app-icon` and `lock-screen-controls`; follow-up updates to `README.md`, `AGENTS.md`, `docs/project-context.md`, `openspec/config.yaml` project context, `backend/api/openapi.yaml` title/description (docs-only), and `Design/*` product references — handled as doc tasks, not spec changes.
- **Non-goals (explicitly unchanged)**: `PRODUCT_BUNDLE_IDENTIFIER` (`com.antonkosenko.timeoflifeapp`), App Group (`group.com.antonkosenko.timeoflifeapp`), Keychain service / session keys (`com.timeoflife.*`), GRDB file name (`timeoflife.sqlite`), queue/label strings, backend DB names, Docker/image names, production API domain (`timeoflife-api.antonkosenko.pro`), Xcode scheme/target/module names (`TimeOfLife`), and icon artwork itself. Backend behavior, OpenAPI endpoints, and sync protocol are untouched. No data migration (pre-release policy: no on-disk compat).
