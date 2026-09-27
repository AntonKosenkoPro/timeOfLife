## 1. External docs + mechanical floor

- [x] 1.1 Re-verify ctx7 docs before coding (`/websites/developer_apple_swiftui` — "ControlWidget lock screen control", "Layout protocol custom flow layout"; pin: iOS 18 SDK via Xcode 16+); implementation tasks depend on this.
- [x] 1.2 Bump floor to 18.0 in `ios/TimeOfLife/project.yml` (all three pins), unify `TimeOfLifeTests` host at 18.0, drop `armv7`, run `xcodegen generate`, and confirm `openspec status --change bump-ios-deployment-to-18` artifacts resolve.
- [x] 1.3 Update `docs/project-context.md` (iOS 15+ → iOS 18+, coding-standards guards line, incomplete/deferred ControlWidget entry) and CI simulator choice (`ios.yml`, `docs/ios-test-loop.md`).

## 2. Deletional cleanup

- [x] 2.1 Delete the `AppNavigationStack` iOS 15 fallback (`popTo`, nested `AnyView` chain) and convert all 8 `NavigationView + .navigationViewStyle(.stack)` roots to `NavigationStack` (shell, Manage Categories, Log Time, editor scaffold, Insights/History previews).
- [x] 2.2 Replace `TagSelector` + `RecentActivitiesChips` greedy packing with one shared `Layout`-protocol flow layout; remove GeometryReader/PreferenceKey/UIFont measurement in both.
- [x] 2.3 Collapse `ShellToolbar` to a single scope, make `presentationDetents([.medium, .large])` unconditional, delete `Theme.color(_, alpha:)` (verify the old "`Color.opacity` is iOS 16+" comment; 4 call sites to native opacity), and remove dead `#available(iOS 14)` guards in `AppConfig`.
- [x] 2.4 Re-check `app-shell` / `timer-capture-experience` scenarios for implied old-toolbar behavior; add a delta spec only if a REQUIREMENT (not implementation) changed.

## 3. ControlWidget target

- [x] 3.1 Add the widget target in `project.yml` (+ entitlements, App Group) with the `ControlWidget` toggle + `alwaysAllowed` AppIntent against the active per-account file; intent writes state + outbox row in one transaction and never syncs directly (LocalStore chokepoint invariant).
- [x] 3.2 Cover the Control with tests where possible (intent transaction/outbox) and run the README real-device smoke (auth → track → History → lock-screen Control start/stop, incl. first-use-no-history and locked-device paths per the delta spec).

## 4. Verification + docs

- [x] 4.1 Run `swiftlint lint --strict`, warning-as-errors `xcodebuild` build, and the full `xcodebuild test` suite green.
- [x] 4.2 Re-read the relevant `Requirements/FURPS/*.md` rows; fix conflicts.
- [x] 4.3 Run `openspec validate --all --strict` and confirm the `lock-screen-controls` delta spec passes; update `docs/project-context.md` + `openspec/README.md` if the active-change set changed.
