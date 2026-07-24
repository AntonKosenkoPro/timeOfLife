# Time Tracking Screen

This is the first non-auth screen described for the app. `Requirements/FURPS/Timetracking.md` is currently empty, so this document bootstraps the MVP time-tracking experience: **start a timer for an activity, see elapsed time, stop and save the entry**.

Future use cases (history, categories, widgets, shortcuts, account/profile) will extend this screen.

## Use case

1. User is signed in and lands on the time-tracking screen.
2. User sees an activity name field and a large timer display.
3. User types or selects an activity name.
4. User taps **Start**.
5. The timer counts up from 00:00.
6. User taps **Stop** to finish the session.
7. The app saves the elapsed time locally and remotely when online.

## Screen: TimerView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/TimeTracking/Views/TimerView.swift`
- **Route**: `.timer`
- **ViewModel**: `TimerViewModel`

### Layout

Wrap the screen in a `NavigationStack` (or add a `.toolbar` with an inline navigation title) so the top toolbar can render.

The main content uses a `ScrollView` → `VStack(spacing: Theme.spacingMedium)` with padding `Theme.spacingLarge`:

1. `OfflineBanner()` is rendered at the top by `RootView`.
2. Title: `L10n.timerTitle` — `.title.bold()`, `Theme.textPrimary`
3. `Spacer` fixed to `Theme.spacingExtraLarge`
4. `TextFieldWithError` for activity name:
   - `accessibilityId`: `TimerActivityField`
   - title/placeholder: `L10n.timerActivityPlaceholder`
   - `submitLabel`: `.done`
   - disabled while timer is running
5. Large timer display:
   - Elapsed time formatted as `MM:SS` or `H:MM:SS`.
   - Font: `.system(size: 64, weight: .semibold, design: .rounded)`.
   - Color: `Theme.textPrimary`.
   - Fixed `minWidth: 220` and `.monospacedDigit()` so the digits do not shift as they change.
   - `accessibilityIdentifier`: `TimerDisplay`
6. `Spacer().frame(height: Theme.spacingLarge)`
7. Fixed reserve for the pinned bottom action bar

Top toolbar:

- `ToolbarItem(placement: .topBarTrailing)`:
  - `Button(L10n.timerSignOut, role: .destructive)` — `.subheadline`, `accessibilityIdentifier("TimerSignOutButton")`
  - Tapping it presents a confirmation alert with `L10n.signOutConfirmationTitle`, `L10n.signOutConfirmationMessage`, and primary/cancel actions `L10n.signOutConfirm` / `L10n.signOutCancel`.

Pinned bottom action bar via `.safeAreaInset(edge: .bottom)`:

- Primary control button (same position for Start and Stop):
  - Title/icon: `L10n.timerStart` + `play.fill` when idle; `L10n.timerStop` + `stop.fill` when running.
  - Tint: `Theme.accentPrimary` when idle, `Theme.danger` when running.
  - `accessibilityId`: `TimerStartButton` / `TimerStopButton`.
- Bottom hint (if offline):
  - `L10n.timerOfflineHint` — `.caption`, `Theme.textSecondary`.

Background: `Theme.backgroundPrimary`.

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Keyboard and primary input placement**. The activity field and timer display sit in the upper portion of the scrollable area so they remain visible when the keyboard opens. The Start/Stop button is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and is always tappable. A measured bottom reserve prevents the timer display from being hidden behind the action bar on short screens.

### Layout stability rule

The timer screen must not tremble when the timer starts or stops. To guarantee this:

- The timer display and the primary button always occupy the same slots.
- Only the button label, icon, and tint change between Start and Stop.
- No card with shadow appears/disappears in the main layout.
- The activity field is disabled while running but stays visible in the same place.
- The Sign Out toolbar item is always present and does not change size or position.

### Behaviors

- Focus the activity field on appear.
- Validate that activity name is non-empty before starting.
- Start timer updates `TimerViewModel.startDate` and begins a periodic `Timer.publish` to refresh display.
- Stop timer calculates elapsed time, stops publisher, and calls `TimerService.saveEntry(name:duration:startedAt:)`.
- If offline, save the entry locally and sync when connectivity returns.
- Reset input and timer display after successful save.
- Haptic feedback on start (`selection`) and stop (`success`).
- Keep screen awake while timer is running using `UIApplication.shared.isIdleTimerDisabled`.
- **Sign Out**:
  - Tapping the toolbar button shows a confirmation alert.
  - On confirm, clear the local session (offline-safe) and let `RootView` return to the auth flow.
  - Do not show a blocking loader; sign-out is local and immediate.

### States

| State | Visual |
|---|---|
| Idle | Activity field enabled; timer shows `00:00`; Start button shown |
| Running | Activity field disabled; timer updates live; Stop button shown (destructive tint) |
| Saving | Stop button shows `ProgressView`; timer continues until save completes |
| Error | Inline error below activity field or banner above controls |
| Sign Out confirmation | Alert with destructive confirm and cancel |

### Data model

```swift
struct TimeEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let activityName: String
    let startedAt: Date
    let endedAt: Date
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var synced: Bool
}
```

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys (add new keys to EN and RU).
- [ ] Activity field has `TimerActivityField`; display has `TimerDisplay`.
- [ ] Start/Stop buttons occupy the same position and have correct accessibility IDs.
- [ ] Timer display has a fixed width and `.monospacedDigit()`.
- [ ] Timer formatting is consistent and localized.
- [ ] Offline save-and-sync behavior is implemented and tested.
- [ ] Haptics follow `INTERACTIONS.md`.
- [ ] Sign Out toolbar item has `TimerSignOutButton` and shows a confirmation alert.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys required

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Timer
"timer.title" = "Timer";
"timer.activityPlaceholder" = "What are you working on?";
"timer.start" = "Start";
"timer.stop" = "Stop";
"timer.offlineHint" = "Entries are saved locally and synced when you’re back online.";
"timer.emptyActivityError" = "Enter an activity name.";
"timer.signOut" = "Sign Out";

// Sign out confirmation
"signOut.confirmationTitle" = "Sign Out?";
"signOut.confirmationMessage" = "This will clear your local session.";
"signOut.confirm" = "Sign Out";
"signOut.cancel" = "Cancel";
```

Russian:

```text
// Timer
"timer.title" = "Таймер";
"timer.activityPlaceholder" = "Над чем вы работаете?";
"timer.start" = "Старт";
"timer.stop" = "Стоп";
"timer.offlineHint" = "Записи сохраняются локально и синхронизируются после появления сети.";
"timer.emptyActivityError" = "Введите название активности.";
"timer.signOut" = "Выйти";

// Sign out confirmation
"signOut.confirmationTitle" = "Выйти?";
"signOut.confirmationMessage" = "Это очистит локальную сессию.";
"signOut.confirm" = "Выйти";
"signOut.cancel" = "Отмена";
```

---

## Future extensions

- `HistoryView` listing recent entries.
- Activity suggestions based on history.
- Widgets and shortcuts for one-tap start.
- Categories with color tags.
- Dedicated **Account/Profile** screen that replaces the interim `TimerView` Sign Out toolbar item.
