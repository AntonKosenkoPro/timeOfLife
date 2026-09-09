# Component Library

This file defines reusable component contracts. Implementations may live under `Core/Design/Components/` or beside the feature that owns them; contracts for deferred surfaces may not have an implementation yet.

> **Rule:** prefer reusing an existing component over creating a new view. If a new component is needed, add it here first.

---

## `EditorSheetScaffold`

Shared presentation shell for editor sheets. It owns the native collapsing large-title navigation header, localized Cancel action, standard scroll-content width and padding, measured bottom-bar reserve, keyboard-safe pinned action bar, loading-time dismissal lock, and optional iOS 16+ medium/large detents. Editor-specific fields, focus state, validation, and save behavior remain in the feature view.

### Signature

```swift
struct EditorSheetScaffold<Content: View, BottomBar: View>: View {
    init(
        title: String,
        cancelTitle: String,
        isLoading: Bool,
        cancelAccessibilityId: String,
        usesMediumDetent: Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    )
}
```

### Use

- Use for Activity, Category, and future editor sheets that combine scrollable fields with a pinned primary action.
- Supply existing localized title/Cancel strings and a stable Cancel accessibility identifier.
- Keep `@FocusState`, dismiss-on-save observation, validation, and field sections in the calling editor.
- Do not recreate the header with a custom title inside scroll content, scroll-offset tracking, top overlays, or `UINavigationBarAppearance` overrides.

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

**Callers should pass `CatalogIcon.renderableSymbols` (plus a currently selected valid raw value when it is unavailable on the running OS).** The cell renders the `tag` fallback for an unavailable but valid synchronized symbol and never changes the stored raw value.

### Visual

- `LazyVGrid` of icon-only button cells, 44 × 44 pt.
- Each cell: `Theme.backgroundSecondary` fill inside `RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)`, with `Image(systemName: symbol)` in `Theme.textPrimary`, `.body`.
- Selected cell gets a 2 pt `Theme.accentPrimary` border.

### States

| State | Visual |
|---|---|
| Default | 44 × 44 cell, `Theme.backgroundSecondary` fill, `Theme.cornerRadiusSmall` |
| Selected | Same fill + 2 pt `Theme.accentPrimary` border |

### Requirements

- `options` is the renderable subset of the allowed category SF Symbols set (F2/U1); `selection` is the chosen raw symbol name. A valid unavailable selection may be included so it remains visible and editable.
- Each cell `accessibilityIdentifier("\(accessibilityId)Cell(\(symbol))")` and a localized semantic icon label.
- Min tap area 44 — matches the cell size exactly.
- Tapping a cell sets `selection` to that symbol.

### Usage

```swift
IconPickerGrid(
    options: CatalogIcon.renderableSymbols,
    selection: $vm.icon,
    accessibilityId: "CategoryEditorIcon"
)
```

### Accessibility

- Each cell is a button element with a localized semantic icon label.
- Selected cell exposes `.accessibilityValue("Selected")`.

---

## `TagSelector`

Multi-select category chips for an activity (F3). A wrapping flow of content-sized tappable chips; toggling a chip adds/removes the category id from the parent-owned ordered selection.

### Signature

```swift
struct TagSelector: View {
    let options: [Category]
    let selected: Set<String>
    let onToggle: (String) -> Void
    let accessibilityId: String
}
```

### Visual

- Wrapping flow of content-sized chips (each chip as wide as its icon/checkmark, name, and uniform padding), left-aligned, equal `Theme.spacingSmall` gaps between chips and rows, compatible with iOS 15 (rows packed from measured chip widths).
- Unselected chip: only the category icon (30% larger than `.caption`, scaling with Dynamic Type) + name (`.caption`); `Theme.backgroundSecondary` fill + 1 pt `Theme.hairline` border; no outline circle.
- Selected chip: the icon is swapped for a `checkmark` of the same enlarged size (`.semibold`); `Theme.accentPrimary` fill, `Theme.textOnAccent` icon/checkmark and text; no outline circle.
- Each chip: `Theme.spacingChip` (10 pt) uniform padding on all sides, `minHeight Theme.minTapArea` (44 pt — Apple HIG / WCAG 2.2 SC 2.5.5 AAA), `Capsule` shape; long names truncate with `lineLimit(1)`.
- When `options` is empty, the selector renders no chips and the parent editor shows the localized Add-category action.

### States

| State | Visual |
|---|---|
| Unselected | `Theme.backgroundSecondary` fill + `Theme.hairline` border; enlarged category icon + name |
| Selected | `Theme.accentPrimary` fill, `Theme.textOnAccent` text, enlarged `checkmark` in place of the icon |
| Empty options | No chips; parent editor renders the Add-category action |

### Requirements

- Tapping a chip toggles its id in `selected` (F3).
- Chips are content-sized; gaps between chips are uniform (`Theme.spacingSmall`); toggling swaps the icon for the checkmark without re-packing rows.
- Each chip's tap target is at least 44×44 pt (`Theme.minTapArea`).
- Each chip `accessibilityIdentifier("\(accessibilityId)Chip(\(id))")`.
- Tags are optional; an activity with no tags is valid (F3). The selector never forces a selection.
- Empty-state action follows U8 — guides toward Category creation without blocking the editor.

### Usage

```swift
TagSelector(
    options: vm.allCategories,
    selected: $vm.selectedCategoryIds,
    accessibilityId: "ActivityEditorTags"
)
```

### Accessibility

- Each chip is a button element with a localized category label and localized selected/not-selected value.
- The icon/checkmark is `.accessibilityHidden(true)` decoration; selection state is conveyed visually by the icon↔checkmark swap in addition to fill color, and announced by the button's selected/not-selected value.
- The parent screen owns the empty-state "create category" action.

---

## `RecentActivitiesChips`

The Track Recents chip flow (D2/D3/D4): a wrapping flow of at most six
most-recently-used Activities with 44 pt tap targets; chips wrap onto
additional rows and never require horizontal scrolling. A single tap prepares
the Activity without starting timing.

### Signature

```swift
struct RecentActivitiesChips: View {
    let activities: [Activity]
    let categories: [String: Category]
    let selectedID: String?
    let onSelect: (Activity) -> Void
}
```

### Visual

- Wrapping flow of content-sized chips, left-aligned, equal `Theme.spacingSmall`
  gaps between chips and rows. Rows are packed from measured chip widths (the
  `Layout` protocol is iOS 16+ and the app supports iOS 15 — same greedy
  packing algorithm as `TagSelector`, container width via `GeometryReader` +
  preference key).
- Cap of six, most-recently-used first (`activities.prefix(6)`; the store
  already sorts by `last_used_at`).
- Each chip: fixed icon slot with the first assigned Category's
  `CatalogIcon(validated:).displaySymbol` + name (`.subheadline.weight(.medium)`,
  one line, tail-truncated), `Theme.spacingMedium` horizontal / 12 pt vertical
  padding, `minHeight Theme.minTapArea` (44 pt), `Capsule` shape.
- Categoryless Activities render name-only chips with no icon and no
  placeholder glyph.
- Unselected chip: `Theme.backgroundSecondary` fill + `Theme.hairline` border;
  icon and name in `Theme.textPrimary`.
- Selected chip (the prepared Activity, `selectedID == activity.id`): filled
  accent presentation — `Theme.accentPrimary` background, `Theme.textOnAccent`
  text and icon, accent border; the Category icon is kept; no checkmark.
- When `activities` is empty the component renders no chips; the parent screen
  shows the dedicated empty copy (`timer.recentsEmptyHint`).

### States

| State | Visual |
|---|---|
| Unselected | `Theme.backgroundSecondary` fill + `Theme.hairline` border; icon + name |
| Selected | `Theme.accentPrimary` fill, `Theme.textOnAccent` text/icon, accent border; icon kept |
| Empty | No chips; parent shows `timer.recentsEmptyHint` |

### Requirements

- Tapping a chip calls `onSelect` — the parent prepares the Activity without
  starting timing.
- Chips are content-sized with uniform `Theme.spacingSmall` gaps; a chip wider
  than the container renders at container width with a truncated name.
- Each chip's tap target is at least 44×44 pt (`Theme.minTapArea`) in every
  presentation (icon, no-icon, selected).
- Recents are hidden while a timer is running.
- Category names are never shown on chips; search results and the
  selected-Activity row remain category-free (D16 revision).

### Accessibility

- Each chip is a button element with `.accessibilityLabel("Select \(activity.name)")`
  (`L10n.timerSelectActivity`).
- The prepared Activity's chip additionally gets `.accessibilityAddTraits(.isSelected)`
  and `.accessibilityValue("Selected")`; unselected chips carry no value.
- The icon is `.accessibilityHidden(true)` decoration.
- `accessibilityIdentifier("TimerSuggestion(\(activity.id))")`.

### Usage

```swift
RecentActivitiesChips(
    activities: vm.activities,
    categories: vm.categoryMap,
    selectedID: state.activity?.id
) { vm.prefill(from: $0) }
```

---

## `AdaptiveVerticalLayout`

Deterministic spacing budget for the Track dual-flow layout (D34/D1): a
scrollable dual-flow vertical stack whose three flexible regions resolve from
the remaining space instead of relying on `Spacer` flexibility (which cannot
be capped).

### Signature

```swift
struct AdaptiveVerticalLayout<TopContent: View, BottomContent: View>: View {
    let spacerCap: CGFloat
    let topContent: TopContent
    let bottomContent: BottomContent

    init(
        spacerCap: CGFloat,
        @ViewBuilder topContent: () -> TopContent,
        @ViewBuilder bottomContent: () -> BottomContent
    )
}
```

### Behavior

- `spacerCap` is the shared maximum height for the top and bottom spacers
  (48 pt on Track, selected by the user from the 24/48/72/96 Pro Max spike
  comparison).
- With `slack = viewportHeight - contentHeight`:
  - `slack <= 0` — no adaptive spacing; the ordered content scrolls.
  - `0 < slack <= 2 * cap` — the slack splits evenly between the top and
    bottom spacers (`min(cap, slack / 2)` each); the central separator is
    zero.
  - `slack > 2 * cap` — both spacers hold at the shared cap and the surplus
    goes to the central separator between the top flow (completion mark…
    error region) and the bottom flow (search/refine…main action).
- Top and bottom flow heights are measured separately via `GeometryReader` +
  preference keys.
- On Track the top flow holds the completion-mark region through the error
  region; the bottom flow holds the search/refine row through the main action,
  with Recents below the main action inside the bottom flow.

### Requirements

- The three flexible regions never exceed the cap and never go negative; they
  collapse to zero before content clips, overlaps, or becomes unreachable.
- The main action sits above Recents so Choose Activity / Start / Stop stays
  reachable without scrolling on short screens.

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
- No checkmark overlay — the saved-state confirmation lives in the completion
  region above the readout (refine-track-recents D1), so the readout itself
  never renders a checkmark and the saved state does not move the timer.
- A short state caption below the readout (`READY`, `RUNNING`, `SAVING`, `SAVED`, or the idle prompt) in `.caption`, `Theme.textSecondary`.
- `accessibilityIdentifier("TimerDisplay")`.

### States

| State | Visual |
|---|---|
| Idle | `00:00` + choose-an-Activity prompt |
| Ready | `00:00` + `READY` caption |
| Running | Live exact elapsed value + `RUNNING` caption |
| Saving | Readout stable; primary action shows progress |
| Saved | `SAVED` caption; confirmation is shown in the completion region above the readout; readout returns to `00:00` without moving |
| Error | Readout stable; localized non-field error in the reserved region above the central separator |

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

## `ActivitySearchSheet` and `ActivitySearchContent`

`ActivitySearchSheet` is the full-height native-search presentation opened by
the `TimerActivitySearchButton` affordance on Track. It owns the native search
field and sheet dismissal. `ActivitySearchContent` is its results surface.
The operating system owns field placement, focus, keyboard, and Cancel;
Category names and icons are never shown here.

### Signature

```swift
struct ActivitySearchSheet: View {
    @ObservedObject var vm: TrackViewModel
}
```

### Visual

- Full-height sheet with an always-visible native search field and a native
  `List` content surface. It does not replace the Track body.
- Empty query: the complete catalog in recency order (`last_used_at`), with
  the prepared Activity marked by a checkmark.
- While typing: case-insensitive containment matches in recency order.
- Exact normalized match: identified first; no create action for that name.
- Valid unmatched input: one full-width quick-create button
  (`ActivitySearchCreateButton`) with a localized accessibility label.
- Non-expired pending-deletion identity: a restore row
  (`ActivitySearchRestoreButton`) replaces creation for that name.
- Empty catalog: `EmptyState` explaining the empty state and prompting the
  user to enter a name in the native search field.
- Invalid input: existing results stay available; localized validation
  guidance (`ActivitySearchValidationError`) is shown.
- Non-field errors: `ErrorBanner` (`ActivitySearchErrorBanner`).
- Native Cancel and sheet swipe-down dismiss the sheet without changing the
  committed ready/idle state. A confirmed result or creation prepares an
  Activity and then dismisses the sheet.

### States

| State | Visual |
|---|---|
| Browse (empty query) | Recency-ordered catalog, prepared Activity marked |
| Searching | Case-insensitive matches only |
| Unmatched valid input | Create row: full-width quick-create button |
| Pending-deletion identity | Restore row instead of creation |
| Empty catalog | `EmptyState` + prompt to type a name |
| Invalid input | Results + localized validation guidance |

### Accessibility

- Each result row: `.accessibilityLabel("Select \(activity.name)")`, with
  `.accessibilityValue("Ready")` when it is the prepared Activity.
- Create row: `.accessibilityLabel("Create \(name)")`.
- Restore row: `.accessibilityLabel("Restore \(name)")`.
- The content never requires a Category and never shows Category metadata.

---

## `TimerActivityRefineButton` (retired)

The Refine affordance on the Track selected-Activity row was removed in
refine-track-recents (D34/D9): Track has no editing affordance, and the
component is superseded by `RecentActivitiesChips` for Track's
preparation surface. The Activity editor sheet and its view-model
presentation machinery remain wired but unreachable from Track; editing
placement is deferred to a later change. Keep this section until a
replacement placement is designed.

## `SuggestionRow` (retired)

The single-row recency suggestion row on Track was replaced by
`RecentActivitiesChips` in refine-track-recents (D2): a wrapping chip flow
capped at six, with first-Category icons, a filled accent selected
presentation, and dedicated empty copy. Keep this section only as history;
Track no longer renders full-width suggestion rows.

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

## `EntryRow`

Read-only History row for a committed time entry (history-entry-list spec, Variant H layout). Purely presentational — grouping, category resolution, and duration formatting are owned by `HistoryViewModel`. (The activity detail sheet uses the entry-only `ActivityEntryRow` instead.)

### Signature

```swift
struct EntryRow: View {
    let entry: TimeEntry
    let icon: String
    let categoryNames: String
    let timeframeText: String
    let durationText: String
    let isInProgress: Bool
    var viaText: String = ""   // localized "via <Source>"; empty for manual
}
```

### Visual

Variant H (spike-confirmed, design.md D4):

```
  [icon]  Activity Name                    1h 20m
          Health, Morning, via Garmin  14:00 – 15:20
```

- `HStack(alignment: .top, spacing: Theme.spacingMedium)`:
  - Leading icon: first category's SF Symbol, `.title3`, `Theme.textSecondary`, 28 pt column, vertically spanning both text lines. Its optical top is top-aligned with the activity name's **cap-height top** (top of capital letters), not the text frame top — achieved with a negative top padding tuned for `.title3` icon + `.headline` name (`EntryRow.iconTopAdjustment`). If the font stack changes, the offset needs re-tuning.
  - `VStack(alignment: .leading, spacing: 2)`:
    - Line 1: activity name `.headline`, `Theme.textPrimary` (left, flexible) + duration `.headline`, `Theme.textPrimary`, `.monospacedDigit()` (right).
    - Line 2: category names + provenance label `.caption`, `Theme.textSecondary` (left, flexible) + timeframe `.caption`, `Theme.textSecondary`, `.monospacedDigit()` (right). The "via <Source>" label (entry-provenance spec) is appended to the category caption after a comma; `manual` entries show nothing.
- Min height `Theme.minTapArea`; dividers between rows lead after the icon column.

### States

| State | Visual |
|---|---|
| With categories | First category's icon leading; name + duration line 1; category names + timeframe line 2 |
| With provenance | The "via <Source>" label appended to line 2's left caption (after category names, or alone when no categories) |
| No categories | `questionmark` fallback icon; line 2 shows only the timeframe (plus the "via" label when present) |
| In progress (no `endedAt`) | Duration slot shows the localized in-progress indicator; timeframe shows the start time |

### Requirements

- `accessibilityIdentifier("EntryRow(\(entry.id))")`.
- Read-only: no tap action in this component (history-entry-list spec).
- The caller (`HistoryViewModel`) resolves the icon and category names from the activity's current category set at read time (D6).

### Usage

```swift
EntryRow(
    entry: entry,
    icon: vm.icon(for: entry),
    categoryNames: vm.categoryNames(for: entry),
    timeframeText: vm.timeframeText(for: entry),
    durationText: vm.durationText(for: entry),
    isInProgress: vm.isInProgress(entry),
    viaText: vm.viaText(for: entry)
)
```

### Accessibility

- `accessibilityIdentifier("EntryRow(\(entry.id))")`.
- The whole row is a single element: category names, timeframe, and duration are `.accessibilityHidden(true)` and folded into the row label, so VoiceOver reads one line per entry.

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

Simple section title used in editor screens to label input sections, and in History as the day-group header.

### Signature

```swift
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    /// Leading inset that visually aligns the title with a row's text column
    /// (e.g. flush with `EntryRow`'s content past its icon column). When nil,
    /// the title sits at the container's default leading inset.
    let contentLeadingInset: CGFloat?
}
```

### Visual

- `Text(title).font(.title2.bold()).foregroundStyle(Theme.textPrimary)` — or `.headline` when used as a History day-group header over `List` section rows (the editor usage keeps `.title2.bold()`).
- Optional trailing view (right-aligned), e.g. the History day total.
- Padded with `Theme.spacingMedium` leading / `Theme.spacingSmall` vertical (editors), or the History day-group paddings (see `SCREENS/History.md`).
- History day-group usage (D8/D10): day label left-aligned to the `EntryRow` icon column's leading edge via `contentLeadingInset`; when the header is elevated (pinned at the top of the list), the trailing view shows the day's total tracked time, right-aligned to the `EntryRow` duration/timeframe trailing edge. In-list (not elevated), the header shows only the day label.

### States

| State | Visual |
|---|---|
| Default (editor) | `.title2.bold()` title in `Theme.textPrimary` |
| Day-group in-list | Day label only |
| Day-group elevated (pinned) | Day label + right-aligned total ("2h 35m tracked") |

### Requirements

- Pure presentational — no state, no action.
- Editor usage: labels the icon section in `CategoryEditor`.
- History usage: day-group header. The parent gates the trailing total on the header's elevation state — the component itself has no notion of scrolling.

### Usage

```swift
SectionHeader(title: L10n.categoryEditorIconLabel)
IconPickerGrid(options: CatalogIcon.renderableSymbols, selection: $vm.icon, accessibilityId: "CategoryEditorIcon")

// History day group (D8/D10):
SectionHeader(title: dayGroup.label, contentLeadingInset: EntryRow.iconColumnWidth + Theme.spacingMedium) {
    if isElevated {
        Text("\(dayGroup.total) \(L10n.historyTracked.text)")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
    }
}
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
- `HStack`: message (`.subheadline`, `Theme.textPrimary`) + icon-only Undo button (`L10n.undoButton`, `Theme.accentPrimary` tint) + dismiss `xmark`.
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

---

## `ActivityDetailView`

Activity detail sheet presented from a History entry tap (activity-detail-sheet spec). Toolbar holds the activity name and the "Edit Activity" action stacking the existing `ActivityEditorView`. The body header shows each activity field exactly once (icon, categories with icons, notes) below a divider-separated Entries section whose header carries the all-time total; the activity's complete day-grouped committed-entry list renders on inert entry-only rows. Presented at medium detent, draggable to large. If the activity is cascade-deleted while the sheet is open, the sheet dismisses itself.

### Signature

```swift
struct ActivityDetailView: View {
    init(store: LocalStore, activityID: String)
}
```

### Visual

```
┌─ sheet (medium → large) ─────────────────────────────┐
│  ── toolbar title = activity name · [Edit Activity] ─ │
│  🏃  Categories: 🏷 Health, 🌅 Morning                │
│      Activity description                            │
│  ──────────────────────────────────────────────────  │
│  Entries                              Total: 12h 40m │
│    Today                                             │
│    14:00 – 15:20          [sync] Garmin     1h 20m 5s│
│    Yesterday, 23:34 – Today, 0:34            59m 50s │
└──────────────────────────────────────────────────────┘
```

- Header: leading icon (first category's symbol, `EntryRow.iconColumnWidth` column, `.title2`); "Categories:" caption with each category's icon + name, or the localized "none" value when the activity has no categories (the line is always shown); optional activity notes `.subheadline` below when present. No name — the toolbar owns it.
- A `Divider` separates the header from the Entries section. The Entries header is a `SectionHeader` ("Entries" + "Total: <three-component duration>" caption, monospaced digits).
- Entries: `ScrollView` + `LazyVStack(pinnedViews: [.sectionHeaders])`, `Section`-grouped by day with plain `SectionHeader` day labels. No scroll-driven elevation — headers always show only the day label.
- Reuses `HistoryViewModel.makeDayGroups` / `dayLabel` / `timeText` / `detailedDuration` pure helpers.

### Requirements

- Rows are inert: `ActivityEntryRow` receives no tap action; the whole sheet is read-only.
- "Edit Activity" (`ActivityDetailEditButton`) presents `ActivityEditorView` stacked over the sheet; Save dismisses the editor (the presenter clears its sheet item in `onSaved`) and Cancel dismisses via the editor's own Cancel; on editor dismiss the sheet reloads identity, categories, and total.
- Running sessions never appear (only committed entries; `totalDuration` sums `duration_seconds` only).
- The running timer's compact cross-tab control remains visible beneath the sheet on History (sheet overlays the tab content only).

### Usage

```swift
// In HistoryView, on entry-row tap:
.sheet(item: $detailTarget) { target in
    ActivityDetailView(store: container.localStore, activityID: target.activityID)
        .environmentObject(container)
}
```

### Accessibility

- Edit button: `accessibilityIdentifier("ActivityDetailEditButton")`.
- Entry rows (`ActivityEntryRow(id)`) are single elements folding range, provenance name, and duration.
- Day headers keep `SectionHeader`'s `.isHeader` trait.

---

## `ActivityEntryRow`

Entry-only row for the activity detail sheet (activity-detail-sheet spec): time range, provenance (shared `arrow.triangle.2.circlepath` sync icon + bare source name), duration. No activity identity. Purely presentational — the caller (`ActivityDetailViewModel`) computes all strings.

### Signature

```swift
struct ActivityEntryRow: View {
    static let provenanceIcon = "arrow.triangle.2.circlepath"
    let timeRangeText: String
    let provenanceName: String   // "" for manual entries
    let durationText: String
}
```

### Visual

```
  2:34 PM – 5:46 PM        [sync] Garmin       3h 11m 46s
```

- `HStack(alignment: .firstTextBaseline)`: range `.subheadline` `Theme.textPrimary` (left, flexible) + optional provenance `.caption` `Theme.textSecondary` + duration `.subheadline` `Theme.textPrimary` `.monospacedDigit()` (right).
- Min height `Theme.minTapArea`.

### Accessibility

- `accessibilityIdentifier("ActivityEntryRow(\(entry.id))")` set by the parent.
- Single element: range, provenance name, and duration folded into one label.
