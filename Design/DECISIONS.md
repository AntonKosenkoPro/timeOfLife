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

## D15 — Retired: fixed activity/category color palette

- Superseded by the activity/category model reconciliation: activities no longer carry color or icon, categories carry a validated catalog icon, and the palette plus `Theme.activityColor(_:)` resolver are removed.

## D16 — On-device recency suggestions

- The timer's top-5 activity suggestions are computed locally from the synced catalog, ranked by `last_used_at`; there is no suggestions endpoint. Works fully offline. `last_used_at` still syncs so recency is shared across devices.
- Reason: F5/P1 — the client already holds the synced catalog, so a server round-trip would buy nothing and break offline; the backend only keeps `last_used_at` correct on entry start.

## D17 — Soft-delete via client undo buffer

- Deletions are held 30 s in a client-side undo buffer (transient `UndoToast` + system shake-to-undo) and only committed to the local store / pushed to sync after the window passes; the server hard-deletes (no long-lived trash). The buffer is superseded by the next undoable action or cleared on relaunch.
- Reason: R3/U6/U7 — undoable deletion without server-side trash; keeps destructive actions reversible for the common "oops" case while staying simple.

## D18 — Delete-scope confirmation for activities with history

- Deleting an activity that has past entries shows a destructive two-option confirm naming the affected entry count: delete the entire activity (+ all entries) vs. delete only the current entry. Both choices are destructive and enter the undo flow as a unit.
- Reason: F10/U5 — the user must understand the scope before losing history; the prompt names the count so the choice is informed.

## D19 — Recency ordering, no manual reorder at MVP

- Manage Activities and timer suggestions are ordered by `last_used_at` (most-recent first). No drag-to-reorder at MVP.
- Reason: F8 — manual reorder adds complexity for little value now; recency is the cheapest useful default.

## D20 — Free-text start stays first-class

- Typing a name and starting the timer still works in one step; if the name matches an existing activity (case-insensitive, trimmed) it is reused, otherwise a new activity is auto-created with no categories and linked to the entry. The user is never forced into the catalog to start a timer.
- Reason: F4 — forcing categorization would add friction and fight the app's minimal-effort premise; auto-create keeps the free-text flow frictionless while still giving every entry an `activity_id`.

## D21 — Editors as sheets, shared create/edit modes

- `ActivityEditor` and `CategoryEditor` are presented as sheets, each with create + edit modes, reused by the timer (quick-add, F7) and the Manage screens (F8). Keyboard placement follows D13.
- Reason: one editor component per entity avoids duplicate surfaces; sheets keep the user in context (timer / manage list) without a full navigation push.

## D22 — Categories have catalog icons

- Categories carry one icon from the validated `CatalogIcon` set, defaulting to `tag`; category icons are used in category rows, selectors, and activity/suggestion representations.
- This reverses the earlier “categories do not have icons” correction in `ManageCategories.md` and supersedes the retired color-palette decision (D15).
