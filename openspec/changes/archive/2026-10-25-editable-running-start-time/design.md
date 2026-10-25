## Context

See proposal.md (Why) for motivation. Current state: `TrackViewModel` freezes `startedAt` at Start-tap `Date()` into `.running(draft, startedAt:)`; `TimerService.startTimerDraft` persists the `timer_state` singleton; elapsed ticks from the anchor on three faces (Track `Ticker`, `CompactTimer` `TimelineView`, Live Activity system `timerInterval`). Mid-run mutations today are tags + notes only, each a draft-snapshot rewrite through `LocalStore` (single chokepoint). `LogTimeView` owns the Start/End inline picker grammar (graphical 360pt + wheel 216pt, single-open, `end > start` gate); this change needs time-only, no End, no nav chrome. D10 pins Track geometry (name row + Stop never move); `local-first-store` D8 owns the singleton; `live-activities` owns the singleton re-anchor precedent (retag keeps identity, chips update in place).

## Goals / Non-Goals

**Goals:**
- One-tap-reachable `Started HH:MM` caption with a lightweight editor; spike all three variants, converge on one (default A).
- Draft-local start rewrite with live recompute everywhere (Track, CompactTimer, Island/banner).

**Non-Goals:**
- Pre-Start custom time, End editing mid-run, date-picker UI, backend/OpenAPI changes, Recents-order changes, undo for start edits (History EDIT is the escape hatch).

## Decisions

- **Caption slot reserved in all states (D10).** New one-line caption under `NumericTimerReadout`, empty `Color.clear` when not running — same trick as `completionMarkRegion`. Alternative (subtitle inside locked-name card) rejected: card height is state-invariant and the name truncates; a second line risks wrap-shift at large Dynamic Type.
- **Winner B: presets half-sheet (spike review 1.5).** Caption opens a medium-detent sheet with presets + optional wheel + Done; nothing on Track moves (the inline variant's in-place expansion was shown on-device to push Stop down, breaking D10). Follow-up refinements from device review: presets position the wheel instead of applying (single gated Done), an explicit Today | Yesterday segment replaces the silent yesterday-fold (Today rejects future times with Done disabled — the spec gate; Yesterday is always in the past), the wheel is `in:`-bounded like the LogTime End pickers, presets are bidirectional cumulative steppers (`−30 −15 | +15 +30`, forward clamped at now), pills meet the 44pt hit region with a press state (HIG Buttons).
- **New chokepoint `updateTimerDraftStartedAt` (sibling to `updateTimerDraftNotes`).** `TrackViewModel.updateDraftStartedAt` mirrors `updateDraftNotes`: optimistic `state = .running(updated, startedAt: newStart)`, restart ticker, `Task { try await service... }`, recoverable error keeps in-memory value. No outbox write (draft never syncs). Alternative (reuse full `saveTimerDraft`) rejected: rewrites all fields, risks clobbering concurrent tag/note edits.
- **Live Activity re-anchor via `update(using:)` on the same singleton.** Chips/icon unchanged, `startedAt` = new value; identical-start skips update (retag precedent). If `update` proves unable to move the system timer anchor in background, fallback is end+request (still singleton-guarded). CompactTimer needs no change (reads draft each tick).
- **Overnight: label-only date.** Caption shows localized `yesterday HH:MM` when start is a prior day; picker stays time-only (wheel times later than now resolve to *yesterday* — documented in tasks spike). Full date UI rejected as sheet-weight creep.
- **Strings/Theme:** `Started %@` + `Started yesterday %@` in `en`/`ru` + `L10n` (U4); `Theme.textSecondary` caption, `Theme` surfaces only.

## Risks / Trade-offs

- [Risk] System `timerInterval` ignores in-place `startedAt` update → stale Island elapsed. → Mitigation: spike re-anchor first (task 3); fallback end+request, still singleton-guarded.
- [Risk] Wheel-in-top-flow pushes Stop at large Dynamic Type / small screens. → Mitigation: spike measures against D10; B (sheet) is the escape hatch.
- [Risk] Time-only wheel ambiguous across midnight (14:20 = today or yesterday?). → Mitigation: rule "future time = yesterday" + yesterday label; validated in spike review.
- [Risk] Fat-finger 2h backdate silently inflates entry. → Mitigation: presets bound the common case; History EDIT remains the fix path; no confirm step (keeps 2-tap flow).
- [Trade-off] No undo for start edits vs tags/notes (also undo-less). Consistent; accepted.

## Migration Plan

No migration: pre-release, no on-disk format change (edit `Codable` shape in place is not even needed — column exists). Rollback = revert change; drafts written with earlier `started_at` remain valid entries at Stop. No backend deploy.

## Open Questions

- None blocking. Spike review picks the winner (A default); if B or C wins, tasks 5–7 swap editor UI but specs/design stand (editor choice is not spec-visible beyond "the chosen start editor").

---
*ctx7 (pin `iOS 18 SDK via Xcode 16+`): SwiftUI `/websites/developer_apple_swiftui` — `DatePicker displayedComponents hourAndMinute datePickerStyle compact wheel`; HIG `/websites/developer_apple_design_human-interface-guidelines` — `pickers date time picker iOS best practices`; ActivityKit `/websites/developer_apple_activitykit` — `update Live Activity ContentState start date timer`. Backend/best-practice waived — `LocalStore`-only diff, Stop relay path unchanged. Invariants: `LocalStore` single chokepoint (D1), D10 geometry, Theme-only colors, U4 strings, S10 OpenAPI untouched.*
