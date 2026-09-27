## Why

The app still carries an iOS 15 deployment floor, forcing a NavigationStack polyfill, hand-rolled flow layouts, duplicated toolbar scopes, and guard-wrapped sheets — plus the lock-screen ControlWidget cannot ship as a real target and stays spec-only. iOS 17 and iOS 18 share the identical device list (iPhone XS/XR and later), so targeting 18 costs zero devices versus 17, and the app is pre-release (no installed base, no on-disk migration). Now is the cheapest moment to bump and delete the version debt in one pass.

## What Changes

- **BREAKING**: Minimum supported iOS version 15.0 → 18.0 (`project.yml`: `options.deploymentTarget`, `IPHONEOS_DEPLOYMENT_TARGET`, app target; unify `TimeOfLifeTests` host at 18.0; drop obsolete `armv7` device capability).
- Delete the `AppNavigationStack` iOS 15 fallback (`NavigationView` + nested `NavigationLink` chain + `popTo`) and standardize all navigation roots on `NavigationStack` (shell, Manage Categories, Log Time, editor scaffold, previews).
- Replace the hand-rolled greedy chip packing in `TagSelector` and `RecentActivitiesChips` (GeometryReader + PreferenceKey + UIFont measurement) with one shared `Layout`-protocol flow layout.
- Collapse the `ShellToolbar` duplication (single toolbar scope with inline `if`), make `presentationDetents([.medium, .large])` unconditional in `EditorSheetScaffold`, and remove the `Theme.color(_, alpha:)` helper in favor of native opacity plus the dead `#available(iOS 14)` Logger guards in `AppConfig`.
- Add the missing ControlWidget target in `project.yml` (WidgetKit `ControlWidget` toggle + `alwaysAllowed` AppIntent reading/writing the active per-account file in the App Group) so the already-spec'd lock-screen Controls become real.
- Update the `lock-screen-controls` availability requirement (deployment IS 18, no `#available` guards), `docs/project-context.md` (iOS 15+ → iOS 18+, coding standards, incomplete/deferred list), and CI/test-loop simulator choice.

## Capabilities

### New Capabilities

- None — the ControlWidget behavior is already specified under `lock-screen-controls`; this change delivers its missing target rather than introducing a new capability.

### Modified Capabilities

- `lock-screen-controls`: the "Availability guard for iOS 18+" requirement changes — deployment target IS iOS 18, the Control is offered natively with no `#available` guards and no iOS 15–17 absent-branch.

## Impact

- iOS only; no backend, OpenAPI, or sync-protocol changes.
- Touched areas: `ios/TimeOfLife/project.yml` (+ generated `.pbxproj`, new widget target + entitlements), `Core/Navigation/`, `Core/Design/Components/TagSelector.swift`, `Features/TimeTracking/Views/RecentActivitiesChips.swift`, `Features/AppShell/Views/AppShellView.swift`, `Core/Design/Components/EditorSheetScaffold.swift`, `Core/Theme/Theme.swift` (+ 4 call sites), `Configuration/AppConfig.swift`, `Features/Catalog/Views/ManageCategoriesView.swift`, `Features/ManualEntry/Views/LogTimeView.swift`, `Features/AppShell/Views/HistoryView.swift`, `Features/Insights/Views/InsightsView.swift` (previews only), `docs/project-context.md`, CI (`ios.yml`, `docs/ios-test-loop.md`).
- Verification: `xcodegen generate`, `swiftlint lint --strict`, warning-as-errors `xcodebuild` build + full `xcodebuild test` suite, real-device smoke (auth → track → History → Control toggle).

## Non-goals

- No `@Observable`/`@Bindable` migration (20 view models keep `ObservableObject`; still fully supported on 18).
- No Swift Charts adoption for Insights (manual bars match the Design spec).
- No TipKit, Live Activities, or other new iOS 18 features beyond the already-spec'd Control.
- No rewrites of legitimate measurement code (`AdaptiveVerticalLayout`, `NumericTimerReadout`, History headers, `BottomBarMeasurement`) — `Layout` does not replace them.
- No Swift toolchain bump (`SWIFT_VERSION` stays), no backend changes.

## External docs (ctx7)

- Library: `/websites/developer_apple_swiftui` (library query: "NavigationStack deployment target").
- Docs queries used: "ControlWidget lock screen control", "Layout protocol custom flow layout".
- Version pin: iOS 18 SDK via Xcode 16+.
