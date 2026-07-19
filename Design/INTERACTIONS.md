# Interaction Patterns

These rules apply across all screens unless a screen spec explicitly overrides them.

## Loading states

- Buttons show an indeterminate `ProgressView` inside the button at full width.
- Do **not** show blocking full-screen loaders for primary actions.
- Disable submit and destructive actions while `isLoading == true`.
- Keep the rest of the UI interactive (e.g., the user can tap back or dismiss).

## Errors

- Field errors appear **directly beneath** the related input field.
- Use a single unified message per field (Requirements U4). Example: "Email must be a valid email address and be at most 254 characters."
- Non-field errors (server, offline) appear as a banner above the primary action.
- Clear field errors when the user edits the corresponding field.
- Map server error codes to localized strings via `ErrorLocalization.message(for:)`.

## Offline

- Show `OfflineBanner` at the top of every screen when `connectivity.isConnected == false`.
- Disable network-dependent submit buttons while offline.
- Cache the authenticated session; restore it on app launch.
- Logout must work offline by clearing the local session.

## Empty / placeholder states

- Use `EmptyState` with an SF Symbol, a headline, and a subheadline.
- Center it in the available space.
- No custom illustrations for the MVP.

## Focus management

- Focus the primary input field when a screen appears.
- Move focus to the next field with `.submitLabel(.continue)` and `.onSubmit`.
- Dismiss the keyboard when the primary action is triggered.

## Haptics

| Action | Haptic |
|---|---|
| Start timer | `.selection` |
| Stop / save timer | `.success` |
| Validation error | `.notification(.error)` |
| Sign in success | `.success` |

Keep haptics subtle. Do not vibrate on every keystroke.

## Navigation

- Use `AppNavigationStack` for programmatic push/pop.
- iOS 16+ uses `NavigationStack` + `navigationDestination(for:)`.
- iOS 15 uses `NavigationView(.stack)` with a hidden `NavigationLink` bound to `path.last`.
- Do not use `NavigationLink` directly for programmatic navigation.

## Accessibility identifiers

- Every interactive element has a stable `accessibilityIdentifier`.
- Format: `<Screen><Element><Role>`. Examples: `EmailContinueButton`, `OtpFieldError`, `TimerStartButton`.
- Reuse identifiers across the app only when the element is truly the same.
