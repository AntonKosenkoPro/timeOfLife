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
    let action: () -> Void
}
```

### States

| State | Visual |
|---|---|
| Default | `.borderedProminent`, `.controlSize(.large)`, `Theme.accentPrimary` tint |
| Loading | `ProgressView()` with white tint centered in the button; keeps full width |
| Disabled | `disabled(isLoading \|\| isDisabled)` — SwiftUI grays the button |
| Error | No change; errors are shown near the related field, not the button |

### Requirements

- Title uses `.body.bold()`.
- Frame is `maxWidth: .infinity`, height implied by `.controlSize(.large)`.
- Minimum tap area is satisfied by `.controlSize(.large)`.

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

## `OfflineBanner`

Top banner shown when the device is offline.

### Signature

Already implemented: `RootView.OfflineBanner` in `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/RootView.swift:32`.

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
