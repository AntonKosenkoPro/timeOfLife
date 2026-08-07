# App Shell — Track / History / Insights / Profile

Implements the `app-shell` capability (OpenSpec change `redesign-track-experience`): a stable product hierarchy for frequent capture, retrospective review, and analysis, with account and configuration tasks kept secondary and a running timer kept globally accessible.

## Hierarchy

```
TabView (Track | History | Insights)
  ├─ Track      — capture: activity chooser + numeric timer (SCREENS/TimeTracking.md)
  ├─ History    — retrospective review (empty state in this change)
  └─ Insights   — analysis (empty state in this change)
Profile (sheet, top-trailing person control on every tab)
  ├─ Account    — Enable Sync (signed out) / account + sync management (signed in)
  ├─ Library    — Manage Activities, Manage Categories
  ├─ Connections— Integrations, Export
  └─ App        — Appearance, Data and Privacy (incl. Erase local data)
```

- Track is the initially selected destination and the only place that starts or stops a timer.
- Profile is opened from a consistent top-trailing person control and is **not** a fourth tab.
- The hierarchy maps to a future macOS sidebar without changing meaning: Track, History, Insights become primary sidebar destinations; profile-owned features remain secondary.

## Screen: AppShellView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/AppShellView.swift`
- **Route**: root of `RootView` (replaces the timer-only root)
- **State**: `AppShellViewModel` (selected tab, running-timer observation)

### Layout

1. `TabView(selection:)` with three tabs:
   - Track — `Label(L10n.tabTrack, systemImage: "timer")`, `accessibilityIdentifier("TabTrack")`.
   - History — `Label(L10n.tabHistory, systemImage: "clock.arrow.circlepath")`, `accessibilityIdentifier("TabHistory")`.
   - Insights — `Label(L10n.tabInsights, systemImage: "chart.line.uptrend.xyaxis")`, `accessibilityIdentifier("TabInsights")`.
2. Each tab root carries the top-trailing person control (`ProfileButton`) opening the Profile sheet.
3. While a timer is running, History and Insights render the compact timer immediately above the tab bar via `.safeAreaInset(edge: .bottom)` (see `CompactTimer` in `COMPONENTS.md`). Track does not duplicate it — the full numeric timer is already visible.
4. `OfflineBanner` is rendered at the top by the root shell (unchanged).

### Behaviors

- Switching destinations never changes timer state and never discards the previous destination's state (tab state is preserved by `TabView`).
- The app launches into Track without requiring authentication; History and Insights are reachable unsigned.
- Profile opens for all users. Signed out, local configuration remains available and account sync is presented as an optional "Enable Sync" action.
- Dismissing Profile restores the previously selected destination and its state.
- The compact timer's main area returns to Track; its Stop button saves in place and keeps the current destination selected.

### Accessibility

- Tab items expose stable identifiers (`TabTrack`, `TabHistory`, `TabInsights`) and localized labels.
- The compact timer is a single accessible element announcing activity name, elapsed duration, running state, and available actions (see `COMPONENTS.md`).
- Navigation labels and compact timer content remain readable at accessibility Dynamic Type sizes without hiding Start/Stop actions.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys in English and Russian.
- [ ] Tab items and Profile button have stable identifiers.
- [ ] Compact timer appears only on History/Insights and only while running.
- [ ] Profile is a sheet, not a tab.
- [ ] VoiceOver, Dynamic Type, Reduce Motion, light/dark, and iOS 15 are tested.
- [ ] SwiftLint and warning-as-error builds pass.
