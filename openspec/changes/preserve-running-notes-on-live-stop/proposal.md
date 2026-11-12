## Why

Live Activity Stop currently saves the running timer's confirmed notes but bypasses text still being edited on Track's notes page. Issue [#242](https://github.com/AntonKosenkoPro/timeOfLife/issues/242) needs to preserve those edits: stop first, then let the user review the unsaved notes before deciding what to save to the completed entry.

Existing behavior to preserve: Stop completes without waiting for a notes decision. Reviewing, editing, saving, or discarding notes must not delay Stop or change the entry's recorded end time. A new timestamp-capture strategy is out of scope.

## What Changes

- Retain unconfirmed changes from the running timer's notes editor before stopping, including edits that clear previously confirmed notes.
- After a successful stop, offer **Review Notes** or **Discard Changes** only when that running-notes editor has changes. Explain that the timer has already stopped; the prompt itself never saves notes.
- Review shows the retained, editable text without writing anything. Only ✓ in that editor validates and saves notes to the exact completed entry through LocalStore and the transactional outbox. X/back or Discard Changes abandons only the unconfirmed edits, preserving that entry's last confirmed notes.
- Reuse the notes editor's existing validation on ✓ rather than adding a separate prompt-save path. Preserve text on validation or save failure so the user can correct/retry; prevent stale account/run identities and repeated Stop requests from targeting another entry.
- Keep starting another run inaccessible through the existing modal alert and notes-editor navigation while the post-stop notes flow is presented. This is a UI outcome, not a new timer restriction: do not introduce extra Start-disable flags, guards, locks, or timer-state transitions to enforce it. The usual Saved confirmation and Start-button behavior remain unchanged.
- Leave clean/already-confirmed notes, terminated-app Stop, normal editor X/✓/back behavior, and History/Log Time editing unchanged. There is no pre-stop confirmation, autosave of keystrokes, extension writer, or new backend endpoint.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timer-capture-experience`: retain and resolve unconfirmed running-note changes against the stopped entry, independently of timer completion.
- `live-activities`: preserve immediate link-based Stop and its Saved result while presenting the notes decision only after successful completion.

## Impact

- iOS: AppShell Stop routing, Track stop result/identity, running-notes editor ownership, and existing LocalStore entry-update/outbox plumbing. The shared editor's other callers keep their current semantics.
- UI: localized decision/retry copy in `en`, `ru`, `zh-Hans`, `es-419`, `pt-BR` plus `L10n`; Theme colors, VoiceOver, Dynamic Type, and the existing 2000-scalar notes bound remain mandatory.
- Documentation at implementation: `Design/COMPONENTS.md`, `Design/SCREENS/TimeTracking.md`, relevant `Design/INTERACTIONS.md` guidance, `docs/manual-testing.md`, `docs/project-context.md`, and FURPS Track/Live Activity rows. Baselines remain untouched during proposal/implementation.
- No backend/API, dependency, auth, widget-face content, or durable-draft format change is planned. Unsaved editor text remains session-local; crash recovery of unconfirmed keystrokes is not introduced.
- Research (2026-11-11): topic/HIG `/websites/developer_apple_design_human-interface-guidelines` — “Alerts for unexpected loss of unsaved edits: descriptive Save Changes and Discard Changes actions, preserving work until an explicit decision”; Apple API `/websites/developer_apple_swiftui` — “iOS 18 SDK via Xcode 16+: presenting an alert with a retained data item after an asynchronous operation; dismissal and action closures must not destroy the editable source of truth”. See `design.md` for findings, links, applicability, and waivers. Reconfirm before implementation.
- Proposal status: source-traced only; no runtime reproduction or implementation is claimed. Current-tree reproduction and research confirmation jointly gate code changes in `tasks.md`.
