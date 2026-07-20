# Auth Flow Screens

Implements `Requirements/Usecases/Sign-up_and_Sign-in.md` and `Requirements/FURPS/Sign-up_and_Sign-in.md`.

## Screen: EmailEntryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/EmailEntryView.swift`
- **Route**: `.emailEntry`
- **ViewModel**: `EmailEntryViewModel`

### Layout

Centered `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding`:

1. `Spacer()`
2. Title: `L10n.authWelcome` — `.title.bold()`, `Theme.textPrimary`
3. Subtitle: `L10n.authSubtitle` — `.subheadline`, `Theme.textSecondary`
4. Spacer fixed to `Theme.spacingSmall` (8 pt)
5. `TextFieldWithError`:
   - `accessibilityId`: `EmailField`
   - title/placeholder: `L10n.emailEntryEmail`
   - `keyboardType`: `.emailAddress`
   - `textContentType`: `.emailAddress`
   - `autocapitalization`: `.none`
   - `autocorrectionDisabled()`
   - `submitLabel`: `.continue`
6. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `EmailErrorBanner`
7. `PrimaryButton`:
   - title: `L10n.emailEntrySubmit`
   - `accessibilityId`: `EmailContinueButton`
   - disabled when email is empty
8. `AppleSignInButton` (deferred F2)
9. `Spacer()`

Background: `Theme.backgroundPrimary`.

### Behaviors

- Focus email field on appear.
- Validate on submit: email format and maximum length (≤ 254).
- On validation failure show one unified field error.
- On network success (`isEmailSent`) push `.otpEntry(email: vm.email)`.
- Clear field error when `vm.email` changes.
- Disable the Continue button while loading or when email is empty.
- Offline: show banner and disable submit; set `errorMessage` to `L10n.errorOffline` if submit is attempted.

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

Centered `VStack(spacing: Theme.spacingLarge)` with horizontal padding `Theme.screenHorizontalPadding`:

1. `Spacer()`
2. Title: `L10n.otpTitle` — `.title.bold()`, `Theme.textPrimary`
3. Sent-to message: `String(format: L10n.otpSentTo.text, vm.email)` — `.subheadline`, `Theme.textSecondary`
4. Spacer fixed to `Theme.spacingSmall` (8 pt)
5. `TextFieldWithError`:
   - `accessibilityId`: `OtpField`
   - title/placeholder: `L10n.otpCode`
   - `keyboardType`: `.numberPad`
   - `textContentType`: `.oneTimeCode`
   - `autocapitalization`: `.none`
   - `autocorrectionDisabled()`
6. `ErrorBanner` if `vm.errorMessage != nil`:
   - `accessibilityId`: `OtpErrorBanner`
7. `PrimaryButton`:
   - title: `L10n.otpSubmit`
   - `accessibilityId`: `OtpVerifyButton`
   - disabled when code is empty
8. Resend button:
   - Plain `Button` with `L10n.otpResend`, `.subheadline`, `Theme.accentPrimary`
   - `accessibilityId`: `OtpResendButton`
9. `Spacer()`

Background: `Theme.backgroundPrimary`.

### Behaviors

- Focus OTP field on appear.
- Validate on submit: exactly 6 digits.
- Auto-submit when 6 digits are entered and valid.
- On success (`isVerified`) push `.signedIn`.
- Allow navigation back to `EmailEntryView` with pre-filled email.
- Resend is enabled after a 30-second cooldown; on resend show a feedback message via `L10n.otpResent`.
- Consume deep link code from `navigation.pendingDeepLinkCode` on appear and on change.
- Clear field error when `vm.code` changes.
- Offline: show banner, disable submit, set `errorMessage` to `L10n.errorOffline` if submit is attempted.

### Implementation checklist

- [ ] All colors use `Theme.*` tokens.
- [ ] All strings use `L10n.*` keys.
- [ ] OTP field has `accessibilityIdentifier("OtpField")` and error label `OtpFieldError`.
- [ ] Verify button uses `PrimaryButton` with `OtpVerifyButton`.
- [ ] Resend button has `OtpResendButton`.
- [ ] Deep link code is consumed exactly once.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.

---

## Screen: SignedInView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/Auth/Views/SignedInView.swift`
- **Route**: `.signedIn`
- **State source**: `SessionStore`

### Layout

Centered `VStack(spacing: Theme.spacingMedium)` with padding `Theme.spacingMedium`:

1. Title: `L10n.signedInTitle` — `.title2.bold()`, `Theme.textPrimary`
2. If `session.cachedEmail` is not nil: `String(format: L10n.signedInEmail.text, email)` — `Theme.textSecondary`
3. Placeholder: `L10n.signedInPlaceholder` — `.subheadline`, `Theme.textSecondary`
4. `Spacer()`
5. Logout `PrimaryButton`:
   - title: `L10n.signedInLogout`
   - `tint: Theme.danger`
   - `accessibilityId`: `SignedInLogout`

Background: `Theme.backgroundPrimary`.

### Behaviors

- Display the signed-in user's cached email.
- Logout clears the local session and returns to `EmailEntryView`.
- Logout works offline.

### Implementation checklist

- [ ] All strings use `L10n.*` keys (move currently direct `NSLocalizedString` calls to `L10n`).
- [ ] Logout button uses `PrimaryButton` with destructive tint and `SignedInLogout`.
- [ ] Screen previews exist for light/dark and EN/RU.
- [ ] SwiftLint passes with zero findings.
