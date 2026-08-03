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
   - title: `L10n.timerActivityLabel`
   - placeholder: `L10n.timerActivityPlaceholder`
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

- Non-field error banner (if any):
  - `ErrorBanner(message: vm.errorMessage, accessibilityId: "TimerErrorBanner")` rendered above the primary button.
- Primary control button (same position for Start and Stop):
  - Title/icon: `L10n.timerStart` + `play.fill` when idle; `L10n.timerStop` + `stop.fill` when running.
  - Tint: `Theme.accentPrimary` when idle, `Theme.danger` when running.
  - `accessibilityId`: `TimerStartButton` / `TimerStopButton`.
  - Accessibility hint on Stop: `L10n.timerStopHint` — "Stops the timer and saves the entry".
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
- Defocus the activity field when the timer starts (drop `@FocusState` and keep the field disabled while running).
- Suggestions render only when the field is focused/idle and the typed name is empty or case-insensitively prefix-matches an existing activity. Hide suggestions while the user types a brand-new, non-matching name.
- Preserve `selectedActivityId` when the user edits the typed name but the trimmed, case-folded name still matches the linked activity; clear it only when the name diverges.
- Start timer updates `TimerViewModel.startDate` and begins a periodic `Timer.publish` to refresh display.
- Stop timer calculates elapsed time, stops publisher, and calls `TimerService.saveEntry(activityId:duration:startedAt:)`.
- If offline, save the entry locally and sync when connectivity returns.
- Non-field save errors (network/offline/server) are shown in an `ErrorBanner` above the primary button; field errors stay under the activity field.
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
| Idle with suggestions | Suggestions block visible below the activity field when the field is focused and the typed name is empty or matches an existing prefix (F5, D16) |
| Idle, typing a new name | Suggestions hidden once the typed name does not case-insensitively match any existing activity |
| Running | Activity field disabled and defocused; timer updates live; Stop button shown (destructive tint) |
| Running (suggestions hidden) | Suggestions block hidden while `vm.isRunning` (F5) |
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
- [ ] Suggestions render idle-only via `TimerSuggestionList` / `TimerSuggestion(<id>)` (F5/U3, D16).
- [ ] Quick-add button `TimerQuickAddButton` opens `ActivityEditor` as a sheet (F7, D21).
- [ ] Auto-create reuses an existing activity case-insensitively; otherwise creates an activity with no categories (F4/D20).
- [ ] Entry carries `activityId` (F9); `activityName` is derived, not stored.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## New localization keys required

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Timer
"timer.title" = "Timer";
"timer.activityLabel" = "Activity";
"timer.activityPlaceholder" = "What are you working on?";
"timer.start" = "Start";
"timer.stop" = "Stop";
"timer.stopHint" = "Stops the timer and saves the entry";
"timer.offlineHint" = "Entries are saved locally and synced when you’re back online.";
"timer.emptyActivityError" = "Enter an activity name.";
"timer.signOut" = "Sign Out";

// Sign out confirmation
"signOut.confirmationTitle" = "Sign Out?";
"signOut.confirmationMessage" = "This will clear your local session.";
"signOut.confirm" = "Sign Out";
"signOut.cancel" = "Cancel";

// Epic 1 — suggestions + quick-add + manage
"timer.suggestionsHeader" = "Recent";
"timer.quickAdd" = "New activity";
"timer.manageActivities" = "Manage activities";
```

Russian:

```text
// Timer
"timer.title" = "Таймер";
"timer.activityLabel" = "Активность";
"timer.activityPlaceholder" = "Над чем вы работаете?";
"timer.start" = "Старт";
"timer.stop" = "Стоп";
"timer.stopHint" = "Останавливает таймер и сохраняет запись";
"timer.offlineHint" = "Записи сохраняются локально и синхронизируются после появления сети.";
"timer.emptyActivityError" = "Введите название активности.";
"timer.signOut" = "Выйти";

// Sign out confirmation
"signOut.confirmationTitle" = "Выйти?";
"signOut.confirmationMessage" = "Это очистит локальную сессию.";
"signOut.confirm" = "Выйти";
"signOut.cancel" = "Отмена";

// Epic 1 — предложения + быстрое добавление + управление
"timer.suggestionsHeader" = "Недавние";
"timer.quickAdd" = "Новая активность";
"timer.manageActivities" = "Активности";
```

---

## Future extensions

- `HistoryView` listing recent entries.
- Activity suggestions based on history.
- Widgets and shortcuts for one-tap start.
- Categories with icons.
- Dedicated **Account/Profile** screen that replaces the interim `TimerView` Sign Out toolbar item.

---

## Epic 1 changes

Epic 1 (Activity Catalog & Categories) extends the timer with recency suggestions (F5), a quick-add entry point (F7), auto-create-with-`activity_id` (F4), and an updated entry model (F9). Implements `Requirements/Usecases/Activity_Catalog_and_Categories.md` flows 2 and 3.

### Suggestions (F5 / U3, D16 / D19)

A new block rendered directly below `TextFieldWithError`, **idle only** — hidden while `vm.isRunning` because the activity field is disabled (F5). `TimerSuggestionList` wraps up to 5 `SuggestionRow`s (`COMPONENTS.md`) ranked by `last_used_at` on-device; each row uses the first category's icon and comma-separated category names; there is no suggestions endpoint, so it works fully offline (D16). `last_used_at` syncs, so recency is shared across devices (D19 — no manual reorder at MVP).

- Container `accessibilityIdentifier("TimerSuggestionList")`.
- Each row `accessibilityIdentifier("TimerSuggestion(\(activity.id))")` (U3).
- One tap prefills `vm.activityName` with the activity's name AND sets `vm.selectedActivityId` so the entry links to it (F4/U3).
- If the catalog is empty, render nothing — free-text start still works (D20). No `timer.suggestionsEmpty` key is needed; the `EmptyState` pattern belongs to Manage screens (U8).

### Quick-add entry point (F7)

An `IconButton` (`COMPONENTS.md`) with `square.and.pencil` (`TOKENS.md` → Management icons) sits beside the activity field, `accessibilityIdentifier("TimerQuickAddButton")`. Tapping it presents the real `ActivityEditorView` in create-from-timer mode as a sheet (D21); keyboard placement inside the sheet follows D13. On save, the new activity is selected on the timer (name prefilled + `selectedActivityId` set) and the sheet dismisses. Disabled while the timer is running (the field is disabled while running).

### Auto-create behavior (F4 / D20)

On Start, trim + casefold the typed name. If it matches an existing activity (case-insensitive), reuse it — no duplicate. Otherwise auto-create a new activity with no categories and link `activity_id`. The user is never forced into the catalog to start a timer. This mirrors the backend's `UNIQUE (user_id, lower(name))` constraint and the 409 `activity_exists` reuse path (`Design/BACKEND/Activity_Catalog_API.md` Sync & ids): a case-insensitive collision returns the winning record's `{id,name}` in `details` and the client re-maps to the surviving id.

### Updated data model (F9)

`TimeEntry` gains a required `activityId: UUID` and an optional `categories: [Category]?` resolved at query time; `activityName` becomes a convenience derived from the activity (no longer the source of truth). Entries reference `activity_id`; the activity's name and tags resolve at query time (nothing is denormalized onto the entry).

```swift
struct TimeEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let activityId: UUID          // F9 — links to Activity.id
    let startedAt: Date
    let endedAt: Date
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var categories: [Category]?   // resolved at query time
    var activityName: String { /* derived from Activity via activityId */ }
    var synced: Bool
}
```

### Manage Activities / Categories entry points

The timer toolbar (or a future account/menu destination) links to `.manageActivities`. The interim Sign Out toolbar item stays until Epic 3's dedicated Account/Profile screen replaces it (D12).

### New localization keys

Appended to the "New localization keys required" blocks above: `timer.suggestionsHeader`, `timer.quickAdd`, `timer.manageActivities` (EN + RU). No `timer.suggestionsEmpty` key — render nothing when the catalog is empty (D20).
