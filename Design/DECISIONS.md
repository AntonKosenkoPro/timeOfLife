# Design Decisions

Resolved design precedents for Time of Life. Add a new entry here when a visual or interaction decision has project-wide impact.

## D1 — Minimalistic, native iOS design

- Use SwiftUI system components and SF Symbols.
- No custom typefaces or illustrations for the MVP.
- Reason: matches `Requirements/FURPS/Common.md` U1, U2, U5, and S2 (native UI SDK).

## D2 — Passwordless auth

- No password fields, no "forgot password" screens.
- The email-OTP flow handles sign-up, sign-in, and access restoration.
- Reason: security requirement R1; eliminates an entire class of UI and state.

## D3 — Semantic color tokens

- All colors are referenced via `Theme.*` and resolved from `Assets.xcassets` color sets.
- No raw `Color(...)` literals in views.
- Reason: dark/light support U2 and deterministic agent implementation.

## D4 — Localized keys, not raw text

- Every user-facing string is referenced via `L10n` and present in both EN and RU.
- Server error codes map to `error.<code>` keys.
- Reason: localization requirement U4 and test parity (`LocalizationTests`).

## D5 — Text-based design specs

- The design system is Markdown in `Design/` rather than Figma or other external tools.
- SwiftUI Previews are the visual validation loop.
- Reason: easy to create and change; lives under version control; deterministic for AI agents.

## D6 — Accessibility identifiers

- Every interactive element gets a stable `accessibilityIdentifier`.
- Reason: supports UI tests and agent verification; aligns with Apple HIG U5.

## D7 — Offline-first where possible

- Auth session is cached; logout works offline.
- Time entries are saved locally and synced when online.
- Reason: `Requirements/FURPS/Common.md` U3.

## D8 — Sign in with Apple as the primary auth method

- The welcome screen leads with the native Apple sign-in button. Email/OTP is a secondary option reached via a plain text button.
- Reason: user request; Apple HIG recommends making Sign in with Apple prominent and avoiding excessive alternatives.

## D9 — Welcome screen as the auth-flow root

- The first signed-out screen shows the app name and a short tagline before asking for credentials.
- Reason: explains value; aligns with Apple HIG guidance to delay sign-in as long as possible.

## D10 — One-box-per-digit OTP via a single hidden TextField

- Decorative styled boxes give the “one digit per box” visual pattern, but the real responder is a single hidden `TextField` with `.textContentType(.oneTimeCode)`.
- Reason: supports typing, paste, and SMS AutoFill while avoiding a custom text engine. Visual boxes are hidden from VoiceOver; the group is exposed as one accessible element.

## D11 — Return-key and visible button coexist

- Email submission works via the keyboard Return key and via a visible Continue button. Both trigger the same action.
- Reason: Return key is a convenience for sighted users; the visible button is required for VoiceOver and Switch Control workflows.

## D12 — Interim Sign Out on TimerView

- Until a dedicated Account/Profile screen is built, Sign Out lives in the `TimerView` top toolbar as a destructive text button with a confirmation alert.
- Reason: user request; keeps the low-frequency account action out of the primary time-tracking controls.

## D13 — Primary input and action stay above the keyboard

- Screens built around a single text input place the field in the upper portion of the scrollable content, not vertically centered, so the field remains visible when the keyboard opens. The primary action is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and stays tappable without dismissing the keyboard first.
- Reason: guarantees the user can see what they type and reach the submit/continue button on every device, especially short screens like iPhone SE.

## D14 — Auto-submit only on OTP screen

- The `OtpEntryView` submits automatically once the 6-digit code is entered, debounced by 250 ms. There is no visible Verify button because the number pad has no Return key and the screen’s sole purpose is the single OTP field.
- Reason: the one-box-per-digit field already has a clear completion point (6 digits); adding a Verify button would duplicate the action without improving accessibility, since the field is exposed as a single editable accessibility element and AutoFill/paste work through the hidden `TextField`.
- Guard: keep the field focused after verification errors and ensure the component exposes the `.isTextField` trait so assistive tech recognizes it as editable.
