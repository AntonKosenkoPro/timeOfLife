## Why

Navigating back from any pushed destination (Profile, Manage Categories, entry form, NamePicker) to a tab root (Track / History / Insights) restores the bottom tab bar in a late, separate animation pass: the page settles at full height first, then the bar slides back and the content jumps a second time. The per-destination `.toolbar(.hidden, for: .tabBar)` mechanism introduced by `per-tab-navigation-paths` is the cause — its own design doc accepted iOS toolbar interpolation as a non-goal, and the glitch is that risk materialized on every pop.

## What Changes

- Move tab-bar hiding ownership from each pushed destination to each tab's `NavigationStack` root, driven by the existing per-tab path emptiness (`trackPath` / `historyPath` / `insightsPath` empty = bar shown, non-empty = bar hidden), and convert the Track name row's caller-local push into the `ShellRoute.namePicker` value so every push past a tab root is path-observed (device spike: a stack-level declaration wins over destination modifiers unconditionally, so an unobserved link push would regress to a visible bar).
- Remove the per-destination `.toolbar(.hidden, for: .tabBar)` modifiers where the stack now owns the state (Profile, pushed entry form); keep agreeing backstops where pushes stay caller-local under non-empty paths or sheets (Manage Categories, NamePicker) — they never disagree with stack state, so no conflict is possible.
- Animate the root content-height change together with the bar transition so bar and content move in one transaction instead of two sequential passes (Track's adaptive spacing + History/Insights `safeAreaInset` compact timer ride the same transaction).
- Cover Back-tap, interactive swipe-back (commit and cancel), and tab-switch-mid-push with no wrong-state bar.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-shell`: the "Tab bar hidden on pushed destinations" requirement gains a return-transition contract — returning via Back reveals the tab bar synchronously with the pop (single coordinated layout pass, no post-settle relayout), with tab-root state intact. No change to which destinations hide the bar or to per-tab path independence.

## Impact

- Affected iOS code: `Features/AppShell/Views/AppShellView.swift` (three stacks), `Features/AppShell/Views/ProfileView.swift`, `Features/Catalog/Views/ManageCategoriesView.swift`, `Features/ManualEntry/Views/LogTimeView.swift`, `Core/Design/Components/NamePicker.swift`, `Features/TimeTracking/Views/AdaptiveVerticalLayout.swift` (+ `TrackContent.swift` spacing derivation), History/Insights `safeAreaInset` compact-timer geometry.
- No API, backend, OpenAPI, on-disk format, or string changes (no new user-facing strings; U4 unaffected).
- Non-goals: custom tab bar; UIKit `hidesBottomBarWhenPushed` bridge / SwiftUI-Introspect dependency; converting Profile to sheet/cover (violates the pushed-page spec); iPad floating-bar or Liquid Glass redesign; any Track/History/Insights content or sync behavior change.
- External docs (ctx7): SwiftUI `/websites/developer_apple_swiftui` — `docs "toolbar visibility tab bar hidden"` (`toolbarVisibility(_:for:)` flows to nearest bar container; no co-animation guarantee). Version pin: iOS 18+ floor (Xcode 16+); no new dependency.
- Tests: AppShell path-driven visibility unit tests + SVM snapshot-safe UI checks; manual screen-recording repro (Profile→Back per tab, swipe-back commit/cancel, tab switch mid-push) before and after.
