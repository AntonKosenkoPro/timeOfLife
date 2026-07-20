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
