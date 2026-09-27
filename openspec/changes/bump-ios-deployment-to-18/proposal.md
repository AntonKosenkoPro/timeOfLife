## Why

The app still carries an iOS 15 deployment floor, forcing a NavigationStack polyfill, hand-rolled flow layouts, duplicated toolbar scopes, and guard-wrapped sheets. iOS 17 and iOS 18 share the identical device list (iPhone XS/XR and later), so targeting 18 costs zero devices versus 17, and the app is pre-release (no installed base, no on-disk migration). Now is the cheapest moment to bump and delete the version debt in one pass.

## What Changes

- **BREAKING**: Minimum supported iOS version 15.0 → 18.0 (`project.yml`: `options.deploymentTarget`, `IPHONEOS_DEPLOYMENT_TARGET`, app target; unify `TimeOfLifeTests` host at 18.0; drop obsolete `armv7` device capability).
- Delete the `AppNavigationStack` iOS 15 fallback (`NavigationView` + nested `NavigationLink` chain + `popTo`) and standardize all navigation roots on `NavigationStack` (shell, Manage Categories, Log Time, editor scaffold, previews).
- Replace the hand-rolled greedy chip packing in `TagSelector` and `RecentActivitiesChips` (GeometryReader + PreferenceKey + UIFont measurement) with one shared `Layout`-protocol flow layout.
- Collapse the `ShellToolbar` duplication (single toolbar scope with inline `if`), make `presentationDetents([.medium, .large])` unconditional in `EditorSheetScaffold`, and remove the `Theme.color(_, alpha:)` helper in favor of native opacity plus the dead `#available(iOS 14)` Logger guards in `AppConfig`.
- Migrate all one-parameter `onChange(of:)` call sites to the iOS 17+ two/zero-parameter form (required under warnings-as-errors on the new floor).
- Update the `lock-screen-controls` availability requirement (deployment IS 18, no `#available` guards; the Control target itself stays deferred), `docs/project-context.md` (iOS 15+ → iOS 18+, coding standards, incomplete/deferred list), and CI/test-loop simulator choice.

## Capabilities

### New Capabilities

- None — this change is a pure floor bump plus version-debt deletion; no user-visible behavior is introduced. The ControlWidget behavior stays specified-but-deferred under `lock-screen-controls` (no target).

### Modified Capabilities

- `lock-screen-controls`: the "Availability guard for iOS 18+" requirement changes — deployment target IS iOS 18 with no `#available` guards and no iOS 15–17 absent-branch; the Control target itself remains deferred.

## Impact

- iOS only; no backend, OpenAPI, or sync-protocol changes.
- Touched areas: `ios/TimeOfLife/project.yml` (+ generated `.pbxproj`), `Core/Navigation/`, `Core/Design/Components/TagSelector.swift`, `Features/TimeTracking/Views/RecentActivitiesChips.swift` (+ new shared `FlowLayout`), `Features/AppShell/Views/AppShellView.swift`, `Core/Design/Components/EditorSheetScaffold.swift`, `Core/Theme/Theme.swift` (+ 4 call sites), `Configuration/AppConfig.swift`, `Features/Catalog/Views/ManageCategoriesView.swift`, `Features/ManualEntry/Views/LogTimeView.swift`, `Features/AppShell/Views/HistoryView.swift`, `Features/Insights/Views/InsightsView.swift` (previews only), 14 `onChange(of:)` call sites, `docs/project-context.md`, CI (`ios.yml`, `docs/ios-test-loop.md`).
- Verification: `xcodegen generate`, `swiftlint lint --strict`, warning-as-errors `xcodebuild` build + full `xcodebuild test` suite.

## Non-goals

- No ControlWidget target (deferred again — judged excessive for now; the spec stays as future contract).

- No `@Observable`/`@Bindable` migration (20 view models keep `ObservableObject`; still fully supported on 18).
- No Swift Charts adoption for Insights (manual bars match the Design spec).
- No TipKit, Live Activities, or other new iOS 18 features beyond the already-spec'd Control.
- No rewrites of legitimate measurement code (`AdaptiveVerticalLayout`, `NumericTimerReadout`, History headers, `BottomBarMeasurement`) — `Layout` does not replace them.
- No Swift toolchain bump (`SWIFT_VERSION` stays), no backend changes.

## External docs (ctx7)

- Library: `/websites/developer_apple_swiftui` (library query: "NavigationStack deployment target").
- Docs queries used: "Layout protocol custom flow layout".
- Version pin: iOS 18 SDK via Xcode 16+.
