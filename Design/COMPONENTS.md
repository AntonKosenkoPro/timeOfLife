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
