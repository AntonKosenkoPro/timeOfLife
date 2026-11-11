## Why

Live Activity Stop currently saves the running timer's confirmed notes but bypasses text still being edited on Track's notes page. Issue [#242](https://github.com/AntonKosenkoPro/timeOfLife/issues/242) needs to preserve those edits without delaying the recorded end time: stop first, then ask whether to attach the unsaved changes to the completed entry.

## What Changes

- Stop and save immediately when the app handles the Live Activity Stop request; capture the end time before asynchronous reload/save work, never when the notes decision is answered.
- Retain unconfirmed changes from the running timer's notes editor before stopping, including edits that clear previously confirmed notes.
- After a successful stop, ask **Save Changes** or **Discard Changes** only when that running-notes editor has changes. Explain that the timer has already stopped.
- Save updates only the notes of the exact completed entry through LocalStore and the transactional outbox. Discard preserves that entry's last confirmed notes. Neither action changes its end time, restarts the timer, or creates another entry.
- Preserve the pending text on validation or save failure so the user can correct/retry; prevent stale account/run identities and repeated Stop requests from targeting another entry.
- Keep starting another run unavailable while the post-stop notes decision is unresolved; the usual Saved confirmation itself is not extended.
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
