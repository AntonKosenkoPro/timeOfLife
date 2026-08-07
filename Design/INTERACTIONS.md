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
- Render the banner below the navigation bar / top safe area using `.safeAreaInset(edge: .top)` so it does not overlap back buttons or navigation controls.
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

- Sign Out is a destructive, low-frequency account action owned by Profile.
- The Track toolbar does not expose account actions as a peer to capture.
- Tapping Sign Out must show a confirmation alert before clearing the local session, because local timer data may be lost.
- Sign Out must work offline by clearing the local session.

### Profile destination

- The person control opens Profile for all users — signed out and signed in.
- Signed out, the account section offers **Enable Sync**; local activity/category management, integrations, export, appearance, and data controls remain accessible independently.
- Signed in, the account section shows sync status ("Last synced"/"Syncing…"/error) and a manual "Sync now" action, plus sign-out.
- "Erase local data" is a destructive, confirmed action that wipes the local database (state + outbox + undo buffer + sync cursors).

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

## App shell (Track / History / Insights / Profile)

D1 (OpenSpec change `redesign-track-experience`). The root is a three-tab shell, not a timer-only root:

- **Track, History, Insights are the primary destinations.** Track is initially selected and is the only destination that starts or stops a timer.
- **Profile is a sheet, not a tab.** A consistent top-trailing person control on every tab opens it. Profile owns account/sync, activity and category management, integrations, export, appearance, and destructive data controls.
- **Switching destinations never changes timer state** and never discards the previous destination's state.
- **The app launches into Track without authentication**; History and Insights are reachable unsigned. Auth is an optional "Enable Sync" action inside Profile.
- **A running timer stays globally accessible.** While running, History and Insights show the compact timer immediately above the tab bar (`.safeAreaInset(edge: .bottom)`). Its main area returns to Track; its Stop button saves in place and keeps the current destination selected. Track does not duplicate it.
- **Sign Out is owned by Profile**, not the Track toolbar. Tapping Sign Out shows a confirmation alert before clearing the local session, because local timer data may be lost. Sign Out must work offline by clearing the local session.
- The hierarchy maps to a future macOS sidebar without changing meaning (Track/History/Insights primary; profile-owned features secondary).

## Accessibility identifiers

- Every interactive element has a stable `accessibilityIdentifier`.
- Format: `<Screen><Element><Role>`. Examples: `EmailContinueButton`, `OtpFieldError`, `TimerStartButton`.
- Reuse identifiers across the app only when the element is truly the same.

## Undo flow (catalog deletions)

R3 / U6 / U7; decision D17. Applies to activity and category deletions from Manage Activities / Manage Categories.

- A deletion is **not** committed to the local store or pushed to sync immediately. It enters a client-side **undo buffer** and is only committed + synced after a 30 s window passes.
- Present a transient `UndoToast` (`COMPONENTS.md`) at the bottom with an **Undo** button; auto-dismiss after 30 s.
- **Undo** (tap, or system shake-to-undo) re-inserts the deleted item(s) from the buffer before the window elapses; nothing is synced.
- The buffer is **superseded** by the next undoable action — only the most recent undoable deletion is restorable (matches U7 wording).
- After the window, commit locally (hard delete) and enqueue the `DELETE` for sync; the server hard-deletes (no trash, per `Activity_Catalog_API.md` Sync & ids).
- Bulk deletions (delete activity + its entries, F10) are undoable as a unit — the buffer holds the whole set and Undo restores all of it.
- **Undo API failure:** If the undo API call fails (network error, 404, 409), show an `ErrorBanner` ("Could not undo — try again") and keep the item in its edited state. The undo buffer is not cleared on failure, so the user can retry by triggering undo again (e.g. via a second UndoToast if still within the 30 s window).

### Durable undo buffer (local-first)

D3 (OpenSpec change `local-first-sync-architecture`). The undo buffer is **durable** — it lives in an `undo_buffer` table in the local GRDB database, not in memory:

- The 30 s window is **wall-clock** (`deleted_at + 30s`), not a `Timer`. A `Timer` is only a UI convenience for the UndoToast countdown; the window itself is computed from the stored timestamp.
- A deletion writes the buffer row (full serialized snapshot of the deleted records) and removes the records in **one transaction**; no outbox row is created while the deletion is in the buffer, so the relay is never notified of an undone deletion.
- **Expired buffers commit on the next foreground** — never in the background, and there is no background timer. On foreground, the app detects expired buffers and commits (deletes the buffer row + inserts the outbox rows) in one transaction.
- The buffer **survives suspension, kill, and cold launch**. After a cold launch within the window, no unsolicited UndoToast is shown; if the user navigates to the affected screen within the window, the deletion can still be undone from the durable buffer.
- **Supersession (U7):** only the most recent undoable deletion is restorable via shake-to-undo / UndoToast; an older deletion commits when its own 30 s window elapses.

### Shake-to-undo wiring (U7)

U7 says "no custom shake detection" — use the iOS system motion event. The view layer owns the binding:

- **iOS 17+:** add a `.onShake { vm.performUndo() }` modifier on the manage screen.
- **iOS 15/16:** create a small `ShakeHostingController` subclass of `UIHostingController` that overrides `motionEnded(_:with:)`. When the event is `UIEvent.EventType.motion` and the subtype is `.motionShake`, forward to the active manage screen's `performUndo()` (via a shared observable flag or `NotificationCenter`). Use the same controller subclass for the signed-in navigation stack so both `ManageActivitiesView` and `ManageCategoriesView` inherit the gesture.
- Do not implement custom accelerometer/gyro logic.

## Delete-scope confirmation (F10 / U5)

Decision D18. The confirm pattern depends on what is being deleted.

- **Activity with no entries:** single destructive confirm → undo flow.
- **Activity with entries:** `ScopeConfirmation` (`COMPONENTS.md`) offering two destructive choices, both naming the affected entry count: (a) delete the entire activity + all N entries, (b) delete only the current entry. Both are destructive and enter the undo flow as a unit.
- Destructive buttons use `role: .destructive` / `Theme.danger` tint.
- **Category:** single destructive confirm; the category's tag is removed from all activities (join cascade), entries are unaffected — state this clearly in the confirm copy. Still undoable for 30 s (Undo re-applies the tags).

## Sync conflict (last-write-wins)

R2. Reuses the Offline sync path; do not duplicate the Offline section above.

- Every mutable request carries the client `updated_at`. The server applies the write only if `client.updated_at > server.updated_at`; otherwise it returns **409 `conflict`** with the server's current version in `details`.
- On 409 `conflict`, the client shows an inline `ErrorBanner` ("Edited on another device") and adopts the server's version as the source of truth (keep-latest). No field-level merge at MVP.
- If the user dismisses the conflict `ErrorBanner` without choosing, default to keep-latest (adopt server version) — the banner is informational, not blocking.
- On 409 `activity_exists` / `category_exists` (case-insensitive name collision on create), the client re-maps local references to the surviving id (see `Activity_Catalog_API.md` Sync & ids) and proceeds; in the editor this means "reuse the existing activity" rather than surfacing an error.
- Idempotent `POST` (same id replayed) returns the existing record — the offline queue is safe to replay; do not surface this as an error.

### Confirmation-dialog cleanup

For destructive confirmations that use `.confirmationDialog` or `.alert`, the cancel callback attached to a `role: .cancel` button is **not** called when the user taps outside the sheet or swipes down. To avoid stale `pendingDelete` / "delete in progress" state, either:

- Observe the presentation binding (`isPresented`) in the parent ViewModel and clear pending state when it flips to `false`; or
- Provide an explicit `onDismiss` closure on the sheet/dialog and reset state there.

All manage-screen delete flows should follow this pattern consistently.

| Server response | Client action |
|---|---|
| 200/201 success | Apply locally, clear outbound queue entry |
| 404 not found (on DELETE) | Treat as success — item was already removed elsewhere; remove row locally, clear outbound queue entry |
| 409 `conflict` | `ErrorBanner`, adopt server version, keep-latest |
| 409 `activity_exists` / `category_exists` | Re-map local refs to surviving id, proceed |
| Idempotent POST (replay) | Treat as success; no error surfaced |

## Sync client (local-first)

D6 (OpenSpec change `local-first-sync-architecture`). Sync is an **optional transport feature**, not a prerequisite: the app works fully offline and unsigned; the `SyncController` activates only on sign-in and deactivates on sign-out.

- **Triggers:** (1) app enters foreground, (2) connectivity restored (`.satisfied`), (3) manual "Sync now" in Settings. No background task scheduling on iOS (unreliable); macOS may add a timer-based background sync later.
- **First-sync is pull-first:** on activation, pull the relay's full state, merge server-wins on `updated_at` conflicts, then drain the local outbox. Subsequent pulls are deltas via `?modified_since=` (per-resource cursor advanced to the max `updated_at` received).
- **Outbox drain:** one HTTP call per outbox row, in `created_at` order; idempotent POST / LWW PATCH / hard DELETE make replays safe. 409 `conflict` on push → adopt the server version (keep-latest) and clear the row; 409 `activity_exists`/`category_exists` → re-map local references to the winning id and proceed without an error.
- **Status display (Settings, visible only when signed in):** "Last synced: <relative time>" or "Syncing…" (button disabled while in progress) or an error state (button stays enabled to allow retry). The manual "Sync now" action calls the same drain+pull path as the automatic triggers.
- **Sign-out preserves local data and the outbox**; an explicit "Erase local data" action in Settings wipes them (destructive, confirmed).

## Catalog empty states

U8. Applies to Manage Activities and Manage Categories.

- Show `EmptyState` (`COMPONENTS.md`) when there are zero activities / zero categories (e.g. after deleting all, or if seeds are declined on first run).
- Empty states guide toward creation ("Add an activity") and **never block** free-text timer start — typing a name and starting always works (F4 / D20).

## Recency ordering

F8; decision D19.

- The Manage Activities list and timer suggestions are ordered by `last_used_at` (most-recent first), computed on-device (D16). No manual drag-reorder at MVP.
- `last_used_at` is bumped on every entry start and syncs across devices, so recency is shared (see `Activity_Catalog_API.md` Suggestions).

## Activity and category semantics

- An Activity is the concrete task selected for a timer and is required for an entry.
- A Category is optional analytics metadata; an Activity may have zero or more Categories.
- Track suggestions and the Activity picker show Activity names only. Category icons and names are omitted from capture.
- Manage Activities and Manage Categories are separate surfaces. The full Activity Editor may assign or remove Categories.
- Entries resolve the Activity's current Categories at query time. Changing an Activity's Categories reclassifies its existing history in Insights.

## Editor sheets and keyboard placement

D13 / D21. Applies to `ActivityEditor` and `CategoryEditor`.

- Editors are presented as sheets (`.sheet`, medium detents) and shared across create + edit modes (D21).
- Inside the sheet, follow the existing **Keyboard and primary input placement** rule above:
  - The name field is in the upper scrollable area, focused on appear.
  - The Save `PrimaryButton` is pinned to `.safeAreaInset(edge: .bottom)` so it follows the keyboard and stays tappable.
  - A measured bottom reserve prevents the field from being hidden on short screens.
- Dismiss the sheet on save success or cancel; do not leave the keyboard up after save.
