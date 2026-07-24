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

## Keyboard and primary input placement

When a screen’s main purpose is to collect input from a single field (email, OTP, activity name, etc.), the layout must guarantee that the focused field and the primary action button remain visible while the system keyboard is open.

### Placement rules

1. **Primary input stays above the keyboard without scrolling.**
   - Position the input field in the upper half of the screen (top-aligned content), not vertically centered.
   - On appear, focus the field immediately. The user should already see the caret and typed characters without the app needing to scroll.
2. **Primary action follows the keyboard.**
   - Place the submit / continue / primary button in a pinned bottom action bar using `.safeAreaInset(edge: .bottom)`.
   - The action bar animates with the keyboard on iOS 15+ and stays tappable above the keyboard.
3. **Reserve space for the action bar in the scrollable content.**
   - Add a bottom spacer (measured via `BottomBarHeightPreferenceKey` or fixed) equal to the action bar height plus `Theme.spacingLarge` so the scrollable content ends well above the bar.
   - This prevents the input from being obscured on short screens (e.g., iPhone SE 1st gen) when the keyboard is open.
4. **Use a `ScrollView` as a safety net.**
   - Even though the input is positioned to avoid the keyboard, wrap the form in a `ScrollView` so the user can correct any overlap caused by larger dynamic-type sizes or smaller devices.
5. **Do not rely on `Spacer()` to center the form.**
   - Centering pushes the field into the keyboard zone on short devices. Use a small top padding and fixed spacers instead.

### Anti-patterns

- Centering the form with `Spacer()` above and below the input.
- Placing the primary action button inside the scrollable content where it can be scrolled behind the keyboard.
- Forcing the user to scroll manually to see what they are typing.

## Auth flow interactions

### Return-key submit

- Email fields use `.submitLabel(.continue)` and `.onSubmit` to submit via the keyboard Return key.
- A visible primary button that performs the same action must also exist. VoiceOver / Switch Control users may never discover the Return-key shortcut.

### OTP input and auto-submit

- The OTP field is a single hidden `TextField` with `.textContentType(.oneTimeCode)`. Visual digit boxes are decorative and hidden from VoiceOver.
- The hidden field stays first responder while the OTP screen is visible so SMS AutoFill / QuickType can insert the code.
- Tapping any digit box focuses the hidden field.
- Typing, pasting, or AutoFill updates the bound code.
- Auto-submit triggers only after the code reaches the required length (6 digits), debounced by 250 ms so the user sees the complete code before the network call.
- On a verification error, clear the code and re-focus the hidden field so the user can re-type immediately. Do not force focus when VoiceOver is running.
- Do not auto-submit partial codes or on every keystroke.

### Sign Out

- Sign Out is a destructive, low-frequency account action.
- Until a dedicated Account/Profile screen exists, Sign Out lives in the `TimerView` top toolbar.
- Tapping Sign Out must show a confirmation alert before clearing the local session, because local timer data may be lost.
- Sign Out must work offline by clearing the local session.

### Auth transitions

- Auth screens (Welcome → Email → OTP) are pushed on the shared `AppNavigationStack`.
- Use the system `NavigationStack` push slide. Do not add custom `.transition()` modifiers that could break the iOS 15 `NavigationView(.stack)` polyfill.
- iOS 18 native zoom navigation transitions are noted as future-only and require a separate decision.

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
