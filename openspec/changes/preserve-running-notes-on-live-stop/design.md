## Context

See `proposal.md` for motivation and scope. The current link handler in `AppShellView` reloads Track and calls `TrackViewModel.stop()` without consulting `NotesEditorPage`'s local copy. The editor sends text to its caller only on ✓. After Stop, `updateDraftNotes` ignores saved/ready states, so the still-visible editor cannot attach its unconfirmed text to the completed run.

The relevant contracts are `timer-capture-experience` (running notes and Stop), `live-activities` (link-only Stop, auth gate, truthful Saved card), and `entry-editor` (copy-on-open notes, 2000-scalar validation). LocalStore remains the sole write boundary; entry writes and their outbox records remain transactional. This is a cross-module state-ownership change, so a design is required.

## Goals / Non-Goals

**Goals:** Separate timer completion from the optional notes decision; identify the saved entry explicitly; retain editable text across asynchronous reload, saved-state reset, validation, and retry.

**Non-Goals:** No global discard-warning policy, keystroke autosave, History/manual-entry redesign, new backend contract, notes on widget faces, or durable recovery of an editor's unconfirmed keystrokes. No stop-timestamp refactor or attempt to infer the physical Island tap timestamp from the existing timestamp-free deep link.

## Decisions

### 1. Preserve existing Stop timing; resolve notes only after success

Stop already completes without waiting for user confirmation. Preserve that pipeline and its existing timing, including reload-before-stop for cold opens; do not hoist timestamp capture or add new end-time plumbing for this notes fix. Retain any live running-notes editing session before reload/stop work can invalidate its text. The completed entry's existing end time is authoritative for all subsequent notes review and writes; deliberation must never change it.

Save the entry first with the confirmed notes. Return an explicit completion receipt containing account/store generation, run identity, completed entry UUID, and end time. A no-op, gated database, or failed stop produces no success receipt and no post-stop notes prompt. Keep the editor's text and existing recoverable-stop error behavior on failure. Do not change general failed-stop/retry timing beyond this successful-stop contract.

The current service ignores `createEntry`'s nonthrowing mutation outcome and performs create/draft-clear as separate calls. Before issuing a success receipt, require an actual created/idempotently-existing entry and an atomically completed entry/outbox/draft-clear transition in LocalStore, preserving the existing Stop contract. Failed transactions leave the run retryable; retries of one logical completion reuse its identity. Keep this work limited to the stop path needed for a trustworthy receipt, not a general storage refactor.

Rejected: pre-stop confirmation (user explicitly rejected timing delay), new pre-reload timestamp capture (unnecessary scope), or silently including editor text in the initial entry (violates explicit ✓/save semantics).

### 2. Give only Track's running-notes session an owner outside the page

Introduce a session-local owner for the running notes editor, bound to account/store generation and run identity. It retains confirmed baseline, current text, and editing/resolution phase. The shared editor gains only the plumbing necessary for this caller; History and Log Time retain copy-on-open X/✓/swipe behavior.

Dirty means exact text inequality against the confirmed baseline, not non-empty content: clearing notes is a change, while editing and reverting is not. Capture the current text before any awaited operation can reload Track. Briefly freeze that session's input/✓ while its Stop operation is in flight so the decision text cannot race the stop receipt. A successful receipt binds the retained session to the completed entry; `.saved` reset must not clear it. Clean sessions close without a decision after successful Stop; ordinary navigation-only Live Activity taps do not trigger this flow.

Rejected: inspect only route presence or persisted non-empty notes (neither detects dirty text), and debounce keystrokes into the running draft (changes every cancel contract).

### 3. Present a post-stop decision without making it the text owner

After successful entry completion, present on the surviving running-notes surface:

> **Timer stopped**
>
> You have unsaved note changes. Review them before saving?
>
> **Review Notes** · **Discard Changes**

The prompt never pauses, resumes, stops, or saves anything. Review Notes reveals the retained text in the notes editor, bound to the receipt's completed entry rather than the cleared running draft. Review alone neither validates nor writes: the user can read and edit before choosing ✓. Only that existing confirm action validates and attempts the notes-only write. X or the normal swipe-back discards the reviewed changes, as does Discard Changes in the prompt; all discard paths leave the entry's confirmed notes unchanged. Successful ✓ or explicit discard clears the session and returns to Track. Never label an action “Cancel Stop”. An implicit prompt dismissal is not discard: retain the session and allow review to be resumed.

The existing Saved confirmation runs on its normal schedule underneath this flow; answering notes does not reset or prolong its timer. Starting another run remains unavailable while this notes session is unresolved, even after the normal ready-state reset. That scoped guard prevents an old Stop retry from being mistaken for a request against a replacement run; it does not add a new start/stop control to the notes page.

Reuse the editor's existing 2000-scalar counter and ✓ validation, including shake/error-haptic/no-pop behavior for over-limit text. There is no separate alert-save validation or fallback from a failed direct Save to the editor. The timer stays stopped while the user corrects the reviewed text. A failed persistence attempt retains text and permits retry via ✓ or discard via X/back. Disable competing resolution actions while a write is in flight; do not claim success or clear retained text until the LocalStore transaction succeeds. Use existing error copy where suitable and localize every new key in all five locales; Theme-only colors, VoiceOver ordering, and Dynamic Type remain required. Do not echo note contents onto system surfaces or logs.

SwiftUI alert dismissal must be independent of the retained session: documented alert actions dismiss presentation automatically, so a transient presentation binding cannot be the sole owner of retryable text. Use an API available at the iOS 18 deployment floor; latest indexed convenience overloads are not automatically approved.

### 4. Save notes by receipt identity, through the existing entry/outbox path

Use the actual completed-entry UUID, never the newest History/Recents row or a timer name. Within the account-bound LocalStore, check that this exact entry still exists and update its notes using the latest row; preserve text, category order, start, end, and duration. Reuse the existing entry-update encoding/outbox semantics; add a narrow LocalStore helper only if needed to make the read-check-update transactional and prevent reverting concurrent unrelated edits. No raw GRDB write escapes LocalStore.

The initial create and optional later update must converge both when create is still queued and when it has already synced. A missing/deleted target is an error, never an invitation to recreate it. Account teardown invalidates the session; callbacks from an older account/store generation cannot write through the newly active store. A replacement running timer must never receive the old notes. Duplicate Stop deliveries during the same stop/resolution operation join or no-op: one entry, one decision, and at most one successful notes resolution. A stale duplicate must not stop a newly started timer while the prior resolution is pending.

Keep the ordinary create followed by a separate update operation, rather than rewriting the earlier queued create payload. The notes update needs an `updatedAt` strictly later than the current row at the wire's supported precision; same-tick create/update and a stale/false LWW result must not be reported as success. Trigger the normal entry-change reload/invalidation so visible History/search/notes indicators converge after this ordinary update. Existing record-level LWW conflict policy remains authoritative across devices.

Pending text survives ordinary foreground/background transitions and recoverable failures within the process, not termination or account teardown. Keep resolution scoped to the just-stopped Track session; no general-purpose durable draft queue is introduced.

### 5. Preserve the existing Live Activity lifecycle

The extension remains a renderer with Stop links only. Successful initial Stop ends the activity with its existing truthful Saved card immediately; the notes decision and its retries neither delay that result nor produce another Saved card. Cold-open/no-editor, clean-editor, auth-gated/no-file, stale/no-run, and navigation-only paths retain their existing behavior. No ActivityKit or WidgetKit API change is planned.

### 6. Research bundle and applicability

Fetched via ctx7 on 2026-11-11; reconfirm on the implementation tree. The approved review-first refinement reuses this retention/presentation guidance; the editor, not the prompt, owns validation and saving:

- **Topic / HIG:** `/websites/developer_apple_design_human-interface-guidelines`; query: “Alerts for unexpected loss of unsaved edits: descriptive Save Changes and Discard Changes actions, preserving work until an explicit decision”. [Modality](https://developer.apple.com/design/human-interface-guidelines/modality) supports retaining user-generated content until a save/discard resolution; [feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) distinguishes unexpected irreversible loss from intentional discard. Here the decision protects the notes, not timer completion. HIG is versionless, accessed 2026-11-11.
- **Apple API:** `/websites/developer_apple_swiftui`; query: “iOS 18 SDK via Xcode 16+: presenting an alert with a retained data item after an asynchronous operation; dismissal and action closures must not destroy the editable source of truth”. [Data-driven alert documentation](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)) says actions dismiss alerts and presentation data is stable while shown. Keep session ownership separate from alert state. Target floor: iOS 18 SDK via Xcode 16+; compile and availability checks at apply time select the supported overload, not an unverified latest-only overload.
- **ActivityKit-specific API lookup waived:** existing link and `runEnded` lifecycle are reused; no widget interaction or ActivityKit API surface changes. If apply discovers otherwise, research that API before editing it.
- **Third-party library/service setup lookup waived:** no dependency, remote endpoint, SQL schema, or GRDB usage pattern is introduced; the app's existing LocalStore entry-update/outbox abstraction is reused. A new external-library dependency would require additional research before implementation.

## Risks / Trade-offs

- [Stop success but notes update fails] → completed time is safe; retain notes and offer correction/retry/discard without running the timer again.
- [Backgrounded editor or saved-state reset loses local text] → retain a session outside the editor and capture it before reload; test background/foreground and the reset delay.
- [Repeated links / async ✓ / replacement run / account switch] → serialize same-run operations, use receipt/account generation checks, and reject stale callbacks; encode regression tests.
- [Sync merges or deletion before the decision] → update only the latest target's notes transactionally; never resurrect a missing entry or overwrite unrelated fields.
- [OS launch/reload latency] → preserve the existing Stop pipeline; this change does not promise physical-tap precision or introduce an earlier timestamp boundary. Notes review never extends the already-recorded run.
- [Process termination before resolution] → unconfirmed text remains volatile by explicit scope; the completed timer entry is durable, and a relaunch does not invent a pending decision.
- [No current-tree runtime repro yet] → first implementation tasks must reproduce and capture evidence before any fix; source inspection alone is not acceptance.

## Migration Plan

Proposal-only PR first, with no application edits. After human approval, reproduce on the fresh branch, reconfirm research, implement and test in the same worktree/PR, then perform the normal CI/AI/human review loop. No storage migration or backend rollout is planned; rollback restores the previous iOS behavior without changing saved entry shapes. Archive only after explicit human approval.
