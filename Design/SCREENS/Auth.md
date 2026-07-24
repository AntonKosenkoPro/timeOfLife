# Auth Flow Screens

Implements `Requirements/Usecases/Sign-up_and_Sign-in.md` and `Requirements/FURPS/Sign-up_and_Sign-in.md`.

The signed-out flow is now a linear `NavigationStack`:

```
WelcomeView  --(Continue with Email)-->  EmailEntryView  --(email sent)-->  OtpEntryView
```

`Sign in with Apple` is the primary action on `WelcomeView` and handles sign-up/sign-in in one step. The email/OTP path is a deliberate secondary option. When any auth path succeeds, `SessionStore` flips to `.signedIn` and `RootView` replaces the auth flow with `TimerView`.

---

## Screen: WelcomeView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/WelcomeView.swift`
- **Route**: none — root of `AuthFlowView`
- **ViewModel**: `WelcomeViewModel`

### Layout

Centered `ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding` and `Theme.maxContentWidth`:

1. `Spacer()`
2. Brand icon — `Image(systemName: "clock.arrow.circlepath")`, `.font(.system(size: 48, weight: .light))`, `Theme.accentPrimary`, `accessibilityHidden(true)`
3. App name: `L10n.appName` — `.largeTitle.bold()`, `Theme.textPrimary`, `multilineTextAlignment(.center)`
4. Tagline: `L10n.welcomeTagline` — `.headline`, `Theme.textSecondary`, `multilineTextAlignment(.center)`
5. `Spacer().frame(height: Theme.spacingExtraLarge)`
6. Fixed reserve for the pinned bottom action bar (`Color.clear` matching the measured bar height)

Background: `Theme.backgroundPrimary`.

Pinned bottom action bar via `.safeAreaInset(edge: .bottom)` → `MeasuredBottomBar`:

- `AppleSignInButton` — full width, height `54 pt`, dynamic style (`black` light / `white` dark). `accessibilityIdentifier("WelcomeSignInWithAppleButton")`
- `Spacer().frame(height: Theme.spacingSmall)`
- Plain `Button(L10n.welcomeContinueWithEmail)` — `.subheadline`, `Theme.accentPrimary`, `accessibilityIdentifier("WelcomeContinueWithEmailButton")`

### Behaviors

- Apple sign-in calls `WelcomeViewModel.signInWithApple()`. On success `AuthService` persists the session and `RootView` transitions to `TimerView` automatically.
- “Continue with Email” pushes `.emailEntry` through `AppNavigationStack`.
- Offline: show `OfflineBanner` and disable both sign-in actions.
- No keyboard handling needed on this screen.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys.
- [ ] Apple button uses the native control and dynamic light/dark style.
- [ ] Continue-with-email button has `WelcomeContinueWithEmailButton`.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## Screen: EmailEntryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/EmailEntryView.swift`
- **Route**: `.emailEntry`
- **ViewModel**: `EmailEntryViewModel`

### Layout

`ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding`:

1. Title: `L10n.emailEntryTitle` — `.title.bold()`, `Theme.textPrimary`
2. Subtitle: `L10n.emailEntrySubtitle` — `.subheadline`, `Theme.textSecondary`
3. `Spacer().frame(height: Theme.spacingSmall)`
4. `TextFieldWithError`:
   - `accessibilityId`: `EmailField`
   - title/placeholder: `L10n.emailEntryEmail`
   - `keyboardType`: `.emailAddress`
   - `textContentType`: `.emailAddress`
   - `autocapitalization`: `.none`
   - `autocorrectionDisabled()`
   - `submitLabel`: `.continue`
5. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `EmailErrorBanner`
6. `Spacer().frame(height: Theme.spacingLarge)`
7. Fixed reserve for the pinned bottom action bar

Background: `Theme.backgroundPrimary`.

Pinned bottom action bar:

- `PrimaryButton`:
  - title: `L10n.emailEntrySubmit`
  - `accessibilityId`: `EmailContinueButton`
  - disabled when email is empty/whitespace-only

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Keyboard and primary input placement**. The email field sits near the top of the scrollable area (title, subtitle, then field) so the caret remains visible when the keyboard opens. The Continue button is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and is always tappable without dismissing the keyboard first. A measured bottom reserve prevents the field from being hidden behind the action bar on short screens.

### Behaviors

- Focus the email field on appear.
- Validate on submit: email format and maximum length (≤ 254).
- Both `.onSubmit` (Return key) and the Continue button call the same `submit()` action.
- On validation failure show one unified field error beneath the email field.
- On network success (`isEmailSent`) push `.otpEntry(email: vm.email)`.
- When the user navigates back from `OtpEntryView`, pre-fill the email from `SessionStore.cachedEmail`.
- Clear field error when `vm.email` changes.
- Disable the Continue button while loading or when email is empty.
- Offline: show banner and disable submit; set `errorMessage` to `String.localized("error.offline")` if submit is attempted.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys.
- [ ] Email field has `accessibilityIdentifier("EmailField")` and error label `EmailFieldError`.
- [ ] Continue button uses `PrimaryButton` with `EmailContinueButton`.
- [ ] Loading and disabled states match `COMPONENTS.md`.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## Screen: OtpEntryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/OtpEntryView.swift`
- **Route**: `.otpEntry(email: String)`
- **ViewModel**: `OtpEntryViewModel`

### Layout

`ScrollView` → `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding`:

1. Title: `L10n.otpTitle` — `.title.bold()`, `Theme.textPrimary`
2. Sent-to message: `String(format: L10n.otpSentTo.text, vm.email)` — `.subheadline`, `Theme.textSecondary`
3. `Spacer().frame(height: Theme.spacingSmall)`
4. `OtpCodeField`:
   - `code`: `$vm.code`
   - `length`: `6`
   - `error`: `vm.fieldErrors.otp`
   - `isLoading`: `vm.isLoading`
   - `accessibilityId`: `OtpCodeField`
5. Resend button:
   - Plain `Button` with `L10n.otpResend` / `L10n.otpResendCountdown`, `.subheadline`, `Theme.accentPrimary`
   - `accessibilityId`: `OtpResendButton`
   - Lives directly below the code field because it is a context action tied to the input, not a primary screen action.
6. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `OtpErrorBanner`
7. `Spacer().frame(height: Theme.spacingLarge)`

Background: `Theme.backgroundPrimary`.

### Keyboard handling

Follows `Design/INTERACTIONS.md` → **Keyboard and primary input placement**. The `OtpCodeField` sits near the top of the scrollable area so the digit boxes remain visible above the keyboard. The Resend button lives in the scrollable content just below the field, so it stays visually grouped with the input as the keyboard opens. The system navigation back button (or swipe-back gesture) provides the escape action to return to `EmailEntryView`.

### Behaviors

- Focus the hidden OTP field on appear and re-focus it after a verification error.
- Auto-submit: when `vm.code` reaches 6 digits, debounce 250 ms then call `vm.submit()`. The debounce lets the user see the full code before the network call.
- On a verification error, clear `vm.code` and refocus so the user can re-enter the code.
- On success, `AuthService` updates `SessionStore`; `RootView` transitions to `TimerView`.
- Resend is enabled after a 30-second cooldown; on resend show a feedback message via `L10n.otpResent`.
- Clear field error when `vm.code` changes.
- Offline: show banner, disable submit, set `errorMessage` to `String.localized("error.offline")` if submit is attempted.

### OTP input details

See `Design/COMPONENTS.md` → `OtpCodeField`. At a high level:

- A single hidden `TextField` is the real responder. It has `.keyboardType(.numberPad)` and `.textContentType(.oneTimeCode)`.
- Six styled visual boxes reflect the current code.
- Tapping any box focuses the hidden field.
- Pasting or typing a full code fills the boxes and auto-submits after the debounce.
- Backspace removes the last digit.
- The component exposes one grouped VoiceOver element: label “One-time code, 6 digits”, value `code`, hint “Double tap to edit”.
- Each box uses `Theme.cornerRadiusSmall` (8 pt) instead of the global `Theme.cornerRadius` so the radius is proportionate to the 44×56 pt cell.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys.
- [ ] OTP uses `OtpCodeField` with `OtpCodeField` accessibility identifier.
- [ ] Resend button has `OtpResendButton`.
- [ ] Auto-submit debounces and clears the code on error.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## Deprecated: SignedInView

The `.signedIn` route and `SignedInView` are deprecated. Signed-in users now land directly on `TimerView` via `RootView`, so the intermediate confirmation screen is redundant. The implementation pass will:

- remove `case signedIn` from `AppRoute`
- delete `Features/Auth/Views/SignedInView.swift`
- remove the `navigation.push(.signedIn)` call from `OtpEntryView`
- remove the `signedIn.*` `L10n` keys and `.strings` entries
- update `LocalizationTests.allCases`
- update `AppContainer+UITesting.swift` seed screens

---

## New and changed localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// Welcome
"welcome.tagline" = "Personal time tracker.";
"welcome.continueWithEmail" = "Continue with Email";

// Email entry
"emailEntry.subtitle" = "Enter your email and we’ll send you a one-time code.";

```

Russian:

```text
// Welcome
"welcome.tagline" = "Личный трекер времени.";
"welcome.continueWithEmail" = "Войти по почте";

// Email entry
"emailEntry.subtitle" = "Введите адрес эл. почты, и мы отправим вам одноразовый код.";
```

### Key value changes

| Key | Old EN | New EN | Old RU | New RU |
|---|---|---|---|---|
| `emailEntry.title` | "Sign In" | "Continue with Email" | "Вход" | "Войти по почте" |

### Keys to remove

- `auth.welcome`
- `auth.subtitle`
- `signedIn.title`
- `signedIn.email`
- `signedIn.logout`
- `signedIn.placeholder`
- `otp.success` (unused after removing SignedInView; verify no other usage)
- `otp.changeEmail` (system back button replaces the custom Change-email button)

Remove the matching `L10n` enum cases and update `LocalizationTests.allCases`.
