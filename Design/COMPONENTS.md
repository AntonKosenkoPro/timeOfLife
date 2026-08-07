# Component Library

Each component listed here has a single SwiftUI implementation under `ios/TimeOfLife/TimeOfLife/Core/Design/Components/`. The spec below is the contract: an agent should implement the component to match the signature, states, accessibility identifier, and usage.

> **Rule:** prefer reusing an existing component over creating a new view. If a new component is needed, add it here first.

---

## `PrimaryButton`

Full-width prominent action button.

### Signature

```swift
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let accessibilityId: String
    let tint: Color? // default nil → Theme.accentPrimary
    let action: () -> Void
}
```

### States

| State | Visual |
|---|---|
| Default | Fixed 54pt filled rectangle, `Theme.cornerRadius` continuous corners, filled with `tint ?? Theme.accentPrimary` |
| Loading | `ProgressView()` with white tint centered in the button; keeps full width; fill dimmed to 50% alpha |
| Disabled | `disabled(isLoading \|\| isDisabled)`; fill dimmed to 50% alpha |
| Error | No change; errors are shown near the related field, not the button |

### Requirements

- Title uses `.body.bold()`.
- Frame is `maxWidth: .infinity`, fixed height `54` — matches `AppleSignInButton` geometry.
- Fill is `tint ?? Theme.accentPrimary`; dimmed via `Theme.color(fill, alpha: 0.5)` while loading or disabled.
- Corners are a continuous `RoundedRectangle` with `Theme.cornerRadius`.
- Do NOT use `.borderedProminent`/`.controlSize(.large)` — the system prominent style renders as a floating liquid-glass capsule on iOS 27 and breaks shape parity and keyboard tracking.

### Usage

```swift
PrimaryButton(
    title: L10n.emailEntrySubmit.text,
    icon: nil,
    isLoading: vm.isLoading,
    isDisabled: vm.email.trimmingCharacters(in: .whitespaces).isEmpty,
    accessibilityId: "EmailContinueButton"
) {
    Task { await vm.submit() }
}
```

---

## `TextFieldWithError`

A labeled text field with a single unified error label below it.

### Signature

```swift
struct TextFieldWithError: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let submitLabel: SubmitLabel
    let autocapitalization: UITextAutocapitalizationType
    let accessibilityId: String
    let onSubmit: () -> Void
}
```

### States

| State | Visual |
|---|---|
| Default | `Theme.backgroundSecondary` fill, `Theme.hairline` border |
| Error | Same fill, `Theme.danger` border and error text |
| Focus | System focus ring; no custom border change |

### Requirements

- Label appears above the field using `Theme.textSecondary` and `.caption`.
- Field uses `Theme.backgroundSecondary`, `.cornerRadius(Theme.cornerRadius)`, padding `Theme.spacingMedium`.
- Border is a 1 pt `RoundedRectangle` stroke: `Theme.hairline` normally, `Theme.danger` when `error != nil`.
- Error label uses `.caption` and `Theme.danger`, with `accessibilityIdentifier("<accessibilityId>Error")`.
- Clear error when `text` changes.

### Usage

```swift
TextFieldWithError(
    title: L10n.emailEntryEmail.text,
    placeholder: L10n.emailEntryEmail.text,
    text: $vm.email,
    error: vm.fieldErrors.email,
    keyboardType: .emailAddress,
    textContentType: .emailAddress,
    submitLabel: .continue,
    autocapitalization: .none,
    accessibilityId: "EmailField",
    onSubmit: { Task { await vm.submit() } }
)
```

---

## `OtpCodeField`

One styled input box per digit, backed by a single hidden `TextField` so paste, SMS AutoFill, and typing work as one continuous code.

### Signature

```swift
struct OtpCodeField: View {
    @Binding var code: String
    var length: Int = 6
    let error: String?
    let isLoading: Bool
    let accessibilityId: String

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
}
```

### Visual

- `ZStack`:
  - Hidden `TextField("", text: $code)`:
    - `.keyboardType(.numberPad)`
    - `.textContentType(.oneTimeCode)` for SMS AutoFill / QuickType
    - `.autocorrectionDisabled()`, `.textInputAutocapitalization(.never)`
    - `opacity(0)` and `.accessibilityHidden(true)` so only the boxes are visible
  - `HStack(spacing: Theme.spacingSmall)` with `length` boxes (default 6).
- Each box:
  - Size `44 × 56 pt` (minimum tap area 44 pt).
  - Background fill `Theme.backgroundSecondary` inside a `RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)` so the background matches the border shape and no square corners stick out.
  - Border 1 pt `RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)` stroke: `Theme.hairline` normally, `Theme.accentPrimary` on the active box while focused, `Theme.danger` when `error != nil`.
  - Digit shown in `Theme.textPrimary`, `.title2.monospacedDigit()` when filled; empty boxes are blank (no placeholder).
- The active box index is `min(code.count, length - 1)` while focused, else `-1` (no box highlighted).
- The whole group is horizontally centered.

### States

| State | Visual |
|---|---|
| Empty | Boxes blank; active box (index 0) has accent border while focused |
| Partial | Filled boxes show digits; remaining boxes blank; active box has accent border |
| Complete | All boxes filled; active box (last) has accent border |
| Error | All boxes use `Theme.danger` border; error text appears below the component |
| Loading | The hidden field is disabled; the parent shows loading via the primary action |

### Behavior

- The component focuses itself on appear (`.onAppear { isFocused = true }`). It owns its `@FocusState` internally and never needs an external focus binding; do not dismiss focus elsewhere.
- Tapping any box focuses the hidden field.
- Typing appends digits to `code`; focus management is irrelevant because there is only one real responder.
- `onChange(of: code)` sanitizes the value to digits only and truncates to `length`, writing back only when different to avoid feedback loops.
- Pasting a multi-character string fills as many boxes as possible from the start, truncated to `length`.
- Backspace removes the last digit.
- Auto-submit is the parent screen’s responsibility; the component only exposes the bound `code`.
- Clear `error` when `code` changes (parent logic).

### Accessibility

- Group the boxes into a single accessible element:
  - `.accessibilityElement(children: .combine)`
  - `.accessibilityLabel("One-time code, \(length) digits")`
  - `.accessibilityValue(code)`
  - `.accessibilityIdentifier(accessibilityId)`
- Hide individual visual boxes from VoiceOver with `.accessibilityHidden(true)`.
- The component focuses itself on appear via its own `@FocusState`; no external focus binding is needed. Do not force-focus while VoiceOver is running — do not fight the screen reader.

### Usage

```swift
OtpCodeField(
    code: $vm.code,
    length: 6,
    error: vm.fieldErrors.otp,
    isLoading: vm.isLoading,
    accessibilityId: "OtpCodeField"
)
```

### Notes

- If `length` exceeds 6, wrap the box row in a horizontal `ScrollView` so it does not clip on narrow screens.
- The component must not implement its own text engine, custom touch handling, or custom caret. The hidden `TextField` owns all text input.

---

## `OfflineBanner`

Top banner shown when the device is offline.

### Signature

Already implemented: `RootView.OfflineBanner` in `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/RootView.swift:33`.

### Visual

- Full width, top of screen via `ZStack(alignment: .top)`.
- Text: `L10n.offlineBanner`, `.footnote`, white.
- Background: `Theme.danger`.
- Padding vertical `6`, horizontal `12`.
- Transition: `.move(edge: .top).combined(with: .opacity)`.

---

## `ErrorBanner`

Centered inline error message used when the error is not tied to a specific field.

### Signature

```swift
struct ErrorBanner: View {
    let message: String
    let accessibilityId: String
}
```

### Visual

- Text: `.caption`, `Theme.danger`, `.multilineTextAlignment(.center)`.
- No background or icon in the MVP.

### Usage

```swift
if let errorMessage = vm.errorMessage {
    ErrorBanner(
        message: errorMessage,
        accessibilityId: "EmailErrorBanner"
    )
}
```

---

## `EmptyState`

Centered placeholder with icon, headline, and subheadline.

### Signature

```swift
struct EmptyState: View {
    let icon: String // SF Symbol name
    let title: String
    let subtitle: String
}
```

### Visual

- `VStack(spacing: Theme.spacingSmall)` centered.
- Icon: `Image(systemName: icon)`, `.font(.system(size: 48, weight: .light))`, `Theme.textSecondary`.
- Title: `.title2.bold()`, `Theme.textPrimary`.
- Subtitle: `.subheadline`, `Theme.textSecondary`, `.multilineTextAlignment(.center)`.
- Padding horizontal `Theme.spacingLarge`.

### Usage

```swift
EmptyState(
    icon: "clock.arrow.circlepath",
    title: L10n.historyEmptyTitle.text,
    subtitle: L10n.historyEmptySubtitle.text
)
```

---

## `ListRow`

A single row in a settings or history list.

### Signature

```swift
struct ListRow<Trailing: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing
}
```

### Visual

- `HStack(spacing: Theme.spacingMedium)` with `alignment: .firstTextBaseline`.
- Optional leading icon: `Theme.accentPrimary`, `.body`.
- Title: `.body`, `Theme.textPrimary`.
- Subtitle: `.caption`, `Theme.textSecondary`.
- Trailing view aligned to the right.
- Full width, padding vertical `Theme.spacingSmall`.

### Usage

```swift
ListRow(
    icon: "clock",
    title: activity.name,
    subtitle: durationString
) {
    Text("Today")
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
}
```

---

## `IconButton`

A circular button for icon-only actions.

### Signature

```swift
struct IconButton: View {
    let icon: String
    let accessibilityId: String
    let isDisabled: Bool
    let action: () -> Void
}
```

### Visual

- `Button` with `Image(systemName: icon)` label.
- Frame `Theme.minTapArea × Theme.minTapArea`.
- Foreground `Theme.accentPrimary`.
- Disabled when `isDisabled`.

---

## `IconPickerGrid`

Selectable grid of allowed SF Symbols for categories (F2/U1).

### Signature

```swift
struct IconPickerGrid: View {
    let options: [String]
    @Binding var selection: String
    let accessibilityId: String
}
```

**Callers should pass `CatalogIcon.allowedSymbols` (or another caller-validated set).** The component itself does not filter invalid or duplicate symbol names; invalid names render as blank cells and duplicate names break `ForEach` identity. Use the typed seam (`CatalogIcon`) to guarantee a valid set.

### Visual

- `LazyVGrid` of `IconButton`-style cells, 44 × 44 pt.
- Each cell: `Theme.backgroundSecondary` fill inside `RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)`, with `Image(systemName: symbol)` in `Theme.textPrimary`, `.body`.
- Selected cell gets a 2 pt `Theme.accentPrimary` border.

### States

| State | Visual |
|---|---|
| Default | 44 × 44 cell, `Theme.backgroundSecondary` fill, `Theme.cornerRadiusSmall` |
| Selected | Same fill + 2 pt `Theme.accentPrimary` border |

### Requirements

- `options` is the allowed category SF Symbols set (F2/U1); `selection` is the chosen symbol name. Callers must pass `CatalogIcon.allowedSymbols`.
- Each cell `accessibilityIdentifier("\(accessibilityId)Cell(\(symbol))")`.
- Min tap area 44 — matches the cell size exactly.
- Tapping a cell sets `selection` to that symbol.

### Usage

```swift
IconPickerGrid(
    options: CatalogIcon.allowedSymbols,
    selection: $vm.icon,
    accessibilityId: "CategoryEditorIcon"
)
```

### Accessibility

- Each cell is a button element with `.accessibilityLabel("Icon, \(symbol)")`.
- Selected cell exposes `.accessibilityValue("Selected")`.

---

## `TagSelector`

Multi-select category chips for an activity (F3). Wrapping `FlowLayout` of tappable chips; toggling a chip adds/removes the category id from `selected`.

### Signature

```swift
struct TagSelector: View {
    let options: [Category]
    @Binding var selected: Set<UUID>
    let accessibilityId: String
}
```

### Visual

- Wrapping `FlowLayout` (left-aligned, `Theme.spacingSmall` spacing).
- Unselected chip: `Theme.backgroundSecondary` fill + 1 pt `Theme.hairline` border.
- Selected chip: `Theme.accentPrimary` fill, white text, leading `checkmark` (`.caption`).
- Each chip: category icon (`.caption`, `Theme.textSecondary`) + name (`.caption`), padding `Theme.spacingSmall` horizontal / 4 vertical, `Capsule` shape.
- When `options` is empty, render a hint: `L10n.tagsEmptyHint` ("No categories yet — create one"), `.caption`, `Theme.textSecondary`.

### States

| State | Visual |
|---|---|
| Unselected | `Theme.backgroundSecondary` fill + `Theme.hairline` border |
| Selected | `Theme.accentPrimary` fill, white text, `checkmark` |
| Empty options | Centered `L10n.tagsEmptyHint` hint, no chips (U8) |

### Requirements

- Tapping a chip toggles its id in `selected` (F3).
- Each chip `accessibilityIdentifier("\(accessibilityId)Chip(\(id))")`.
- Tags are optional; an activity with no tags is valid (F3). The selector never forces a selection.
- Empty-state hint follows U8 — guides toward creation without blocking the editor.

### Usage

```swift
TagSelector(
    options: vm.allCategories,
    selected: $vm.selectedCategoryIds,
    accessibilityId: "ActivityEditorTags"
)
```

### Accessibility

- Each chip is a button element with `.accessibilityLabel("Category, \(name)")` and `.accessibilityValue(selected.contains(id) ? "Selected" : "Not selected")`.
- The empty-state hint is `.accessibilityHidden(true)` decoration; the parent screen owns the "create category" action.

---

## `NumericTimerReadout`

The centered numeric timer on Track (D2/D23). Its only purpose is displaying the exact elapsed duration; it has no dial, ring, sweep, goal, daily-total, or decorative progress visualization.

### Signature

```swift
struct NumericTimerReadout: View {
    let state: TrackState // idle / ready / running / saving / saved / error
    let elapsed: TimeInterval
    let activityName: String?
}
```

### Visual

- Elapsed time formatted as `MM:SS` or `H:MM:SS` (hours included once elapsed), `.monospacedDigit()`.
- Font: `Theme.timerFont()` (`.system(size: 64, weight: .semibold, design: .rounded)`), `Theme.textPrimary`.
- Centered in the main content region; keeps a stable frame across all timer states.
- A short state caption below the readout (`READY`, `RUNNING`, `SAVING`, `SAVED`, or the idle prompt) in `.caption`, `Theme.textSecondary`.
- `accessibilityIdentifier("TimerDisplay")`.

### States

| State | Visual |
|---|---|
| Idle | `00:00` + choose-an-Activity prompt |
| Ready | `00:00` + `READY` caption |
| Running | Live exact elapsed value + `RUNNING` caption |
| Saving | Readout stable; primary action shows progress |
| Saved | Brief `SAVED` confirmation; readout returns to `00:00` |
| Error | Readout stable; localized non-field error above the primary action |

### Accessibility

- Single accessible element: `.accessibilityElement(children: .combine)`.
- `.accessibilityLabel` announces the selected Activity, timer state, and elapsed duration; `.accessibilityValue` carries the exact formatted duration.
- `.accessibilityAddTraits(.updatesFrequently)` while running so VoiceOver announces the live value.

---

## `CompactTimer`

The persistent running-timer surface shown above the tab bar on History and Insights (D5). Track does not render it — the full numeric readout is already visible there.

### Signature

```swift
struct CompactTimer: View {
    let activityName: String
    let startedAt: Date
    let openTrack: () -> Void
    let stop: () -> Void
}
```

### Visual

- Inset above the tab bar via `.safeAreaInset(edge: .bottom)` on History/Insights roots.
- `HStack`: a non-destructive main area (activity name + live elapsed duration, `.monospacedDigit()`) that returns to Track, and a separate 44 pt circular Stop button (`stop.fill`, `Theme.danger` or accent tint).
- Surface: `Theme.backgroundSecondary` fill, `Theme.cornerRadius` continuous corners, `Theme.hairline` 1 pt stroke.
- `accessibilityIdentifier("CompactTimer")`; Stop button `accessibilityIdentifier("CompactTimerStopButton")`.

### States

| State | Visual |
|---|---|
| Running | Activity name + live elapsed duration + Stop |
| Stopped | Removed from the shell (entry saved in place) |

### Accessibility

- Main area: `.accessibilityLabel("\(activityName), timer running")`, `.accessibilityHint("Returns to Track")`.
- Stop button: `.accessibilityLabel("Stop and save timer")`.
- VoiceOver announces activity name, elapsed duration, running state, and available actions.
- The Stop target is a distinct 44 pt target separated from the navigation area (D5 risk mitigation).

---

## `ActivityChooser`

The searchable native sheet for selecting or creating the Activity to prepare on Track (D3). Category names and icons are never shown here.

### Signature

```swift
struct ActivityChooser: View {
    let activities: [Activity] // recency-ordered
    let onSelect: (Activity) -> Void
    let onCreate: (String) -> Void
    let onManageActivities: () -> Void
}
```

### Visual

- Native `List` in a sheet with `.searchable`.
- Before search: recent Activity names in recency order (`last_used_at`), one activation selects.
- While typing: case-insensitive name matches; unmatched valid input offers `Create "Name"`.
- Empty catalog: `EmptyState` explaining the empty state with creating the first Activity as the primary action.
- Secondary "Manage activities" row at the bottom.
- `accessibilityIdentifier("ActivityChooser")`; create row `accessibilityIdentifier("ActivityChooserCreateButton")`.

### States

| State | Visual |
|---|---|
| Recent | Recency-ordered Activity names |
| Searching | Case-insensitive matches only |
| Unmatched input | `Create "Name"` row |
| Empty catalog | `EmptyState` + primary create action |

### Accessibility

- Each row: `.accessibilityLabel("Select \(activity.name)")`.
- Create row: `.accessibilityLabel("Create \(name)")`.
- The sheet never requires a Category and never shows Category metadata.

---

## `SuggestionRow`

Recency-based Activity suggestion row on the Track screen (F5/U3). One tap prepares the Activity and links the upcoming entry.

### Signature

```swift
struct SuggestionRow: View {
    let activity: Activity
    let action: () -> Void
}
```

### Visual

- `Button`-styled `HStack(spacing: Theme.spacingMedium)`:
  - Name in `.subheadline`, `Theme.textPrimary`.
  - Optional recency subtitle in `.caption`, `Theme.textSecondary`.
- Full width, min height `Theme.minTapArea`.
- `accessibilityIdentifier("TimerSuggestion(\(activity.id))")`.

### States

| State | Visual |
|---|---|
| Default | `Theme.backgroundPrimary` row, full-width tap target |
| Pressed | System highlight (no custom pressed style) |

### Requirements

- Renders inside the `TimerSuggestionList` container; ranking is computed on-device from the local catalog ordered by `last_used_at` (F5, P1).
- Suggestions are hidden while the timer is running (F5).
- Tapping calls `action` — the parent screen prepares the Activity and links `activity.id` to the upcoming entry (F4/U3).

### Usage

```swift
ForEach(vm.suggestions) { a in
    SuggestionRow(activity: a) { vm.prefill(from: a) }
}
```

### Accessibility

- `accessibilityIdentifier("TimerSuggestion(\(activity.id))")` (U3).
- `.accessibilityLabel("Activity suggestion, \(activity.name)")`.
- `.accessibilityHint("Prepares this activity for timing")`.
- Category icons and names are intentionally not exposed by this capture component; they belong to Activity management and Insights.

---

## `ActivityRow`

Manage-list row for an activity (F8). Tap opens `ActivityEditor`; swipe-to-delete is handled by the parent `List`.

### Signature

```swift
struct ActivityRow: View {
    let activity: Activity
    let categories: [Category]
    let action: () -> Void
}
```

### Visual

- `HStack(spacing: Theme.spacingMedium)`:
  - Leading: the first category's icon in `Theme.textSecondary`, `.body`, when categories are present.
  - Middle `VStack(alignment: .leading, spacing: 2)`:
    - Name in `.headline`, `Theme.textPrimary`.
    - Comma-separated category names in `.caption`, hidden when `categories.isEmpty` (F3).
    - Last-used subtitle in `.footnote`, `Theme.textSecondary`.
  - Trailing `Image(systemName: "chevron.right")` in `Theme.textSecondary`.
- Min height `Theme.minTapArea`; full width.

### States

| State | Visual |
|---|---|
| Default | Row with first-category icon, name + category names + subtitle, trailing chevron |
| No categories | Category icon and names collapse; name sits directly above the subtitle |
| No last-used | Subtitle hidden |

### Requirements

- `accessibilityIdentifier("ActivityRow(\(activity.id))")`.
- List ordering is recency-based (most-recently-used first, F8). No manual reorder at MVP.
- Swipe-to-delete is owned by the parent `List`, not by this row.
- Tapping calls `action` — the parent navigates to `ActivityEditor`.

### Usage

```swift
List {
    ForEach(vm.activities) { a in
        ActivityRow(activity: a, categories: vm.categories(for: a)) { vm.edit(a) }
            .swipeActions { Button(role: .destructive) { vm.delete(a) } label: { Label(L10n.delete, systemImage: "trash") } }
    }
}
```

### Accessibility

- `accessibilityIdentifier("ActivityRow(\(activity.id))")`.
- The whole row is a single button element; category names and subtitle are `.accessibilityHidden(true)` and folded into the row label.

---

## `CategoryRow`

Manage-categories list row for a category (F2). Tap opens `CategoryEditor`.

### Signature

```swift
struct CategoryRow: View {
    let category: Category
    let action: () -> Void
}
```

### Visual

- `HStack(spacing: Theme.spacingMedium)`:
  - Leading `Image(systemName: category.icon.rawValue)` in `Theme.textSecondary`.
  - Name in `.body`, `Theme.textPrimary`.
  - Trailing `Image(systemName: "chevron.right")` in `Theme.textSecondary`.
- Min height `Theme.minTapArea`; full width.

### States

| State | Visual |
|---|---|
| Default | Category icon + name + trailing chevron |

### Requirements

- `accessibilityIdentifier("CategoryRow(\(category.id))")`.
- Swipe-to-delete is owned by the parent `List`.
- Tapping calls `action` — the parent navigates to `CategoryEditor`.

### Usage

```swift
List {
    ForEach(vm.categories) { c in
        CategoryRow(category: c) { vm.edit(c) }
    }
}
```

### Accessibility

- `accessibilityIdentifier("CategoryRow(\(category.id))")`.
- The whole row is a single button element: `.accessibilityLabel("Category, \(category.name)")`.

---

## `SectionHeader`

Simple section title used in editor screens to label input sections.

### Signature

```swift
struct SectionHeader: View {
    let title: String
}
```

### Visual

- `Text(title).font(.title2.bold()).foregroundStyle(Theme.textPrimary)`.
- Padded with `Theme.spacingMedium` leading / `Theme.spacingSmall` vertical.

### States

| State | Visual |
|---|---|
| Default | `.title2.bold()` title in `Theme.textPrimary` |

### Requirements

- Pure presentational — no state, no action.
- Used in `CategoryEditor` to label the icon section.

### Usage

```swift
SectionHeader(title: L10n.categoryEditorIconLabel)
IconPickerGrid(options: CatalogIcon.allowedSymbols, selection: $vm.icon, accessibilityId: "CategoryEditorIcon")
```

### Accessibility

- `.accessibilityAddTraits(.isHeader)` so VoiceOver announces it as a section header.

---

## `UndoToast`

Transient 30-second undo affordance shown after a delete (R3/U6). Purely presentational — the auto-dismiss timer and the 30 s undo window are owned by the parent ViewModel.

### Signature

```swift
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void
}
```

### Visual

- Floating bottom banner via `.safeAreaInset(edge: .bottom)` or overlay.
- `Theme.backgroundSecondary` fill with `Theme.shadowSmall`, `Theme.cornerRadiusLarge`.
- `HStack`: message (`.subheadline`, `Theme.textPrimary`) + `IconButton`-style Undo button (`L10n.undoButton`, `Theme.accentPrimary` tint) + dismiss `xmark`.
- `accessibilityIdentifier("UndoToastButton")` on the Undo button.

### States

| State | Visual |
|---|---|
| Visible | Banner in view at the bottom safe area |
| Dismissing | Slide-down + fade transition (`.move(edge: .bottom).combined(with: .opacity)`) |

### Requirements

- The toast is purely presentational (D17): it does not own the 30 s undo window or the auto-dismiss timer — the parent ViewModel starts both when it shows the toast and calls `onDismiss` when either fires.
- Undo button is accent-tinted, `accessibilityIdentifier("UndoToastButton")`.
- Both choices (undo, dismiss) are destructive-safe: undo restores from the client-side undo buffer before the deletion is committed (R3).

### Usage

```swift
if let undo = vm.undoToast {
    UndoToast(
        message: String(format: L10n.undoDeleteMessage.text, undo.itemName),
        onUndo: { vm.performUndo() },
        onDismiss: { vm.dismissUndo() }
    )
}
```

### Accessibility

- `accessibilityIdentifier("UndoToastButton")` on the Undo button.
- The toast container is `.accessibilityElement(children: .contain)` so VoiceOver focuses the message then the actions.
- `.accessibilityAddTraits(.updatesFrequently)` is NOT set — the toast is static for its 30 s lifetime.

---

## `ScopeConfirmation`

Destructive two-option confirmation for deleting an activity that has past entries (F10/U5). The user must choose between deleting the entire activity (and all its entries) or only the current entry.

### Signature

```swift
struct ScopeConfirmation: View {
    @Binding var isPresented: Bool
    let entryCount: Int
    let onDeleteAll: () -> Void
    let onDeleteEntryOnly: () -> Void
    let onCancel: () -> Void
}
```

### Visual

- System `.confirmationDialog` with:
  - Title: `L10n.deleteActivityTitle`.
  - Message: `String(format: L10n.deleteActivityMessage, entryCount)` — names the number of affected entries (U5).
  - Two destructive buttons (D18):
    - `L10n.deleteActivityEntire` with `%d` entries — `role: .destructive`, calls `onDeleteAll`.
    - `L10n.deleteActivityEntryOnly` — `role: .destructive`, calls `onDeleteEntryOnly`.
  - A cancel button calling `onCancel`.

### States

| State | Visual |
|---|---|
| Presented | System `.confirmationDialog` sheet |
| Dismissed | Binding flipped to `false` by any action |

### Requirements

- Both destructive choices trigger the undo flow (R3/U6) — the parent shows `UndoToast` after either runs.
- `entryCount` must be > 0; the parent only presents this dialog when the activity has entries (D18).
- For category delete, a simpler single-destructive `.confirmationDialog` is used directly in the parent screen — no separate component is needed, because a category has no entries-scope choice.

### Usage

```swift
ScopeConfirmation(
    isPresented: $vm.showDeleteScope,
    entryCount: vm.entryCount(for: activity),
    onDeleteAll: { vm.deleteActivityAndEntries(activity) },
    onDeleteEntryOnly: { vm.deleteEntryOnly(activity) },
    onCancel: { vm.cancelDelete() }
)
```

### Accessibility

- Relies on the system `.confirmationDialog` accessibility — no custom identifiers needed.
- The dialog title and message are read together; destructive buttons are announced as "Delete" with the destructive trait.
