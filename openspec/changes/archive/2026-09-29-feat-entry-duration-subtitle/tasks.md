## 1. Change artifacts

- [x] 1.1 Write delta spec (`specs/entry-editor/spec.md`: live duration subtitle + invalid-state text) + `design.md` (principal-item choice, `naturalDuration` reuse, invalid-text rationale) + this `tasks.md`.
- [x] 1.2 `openspec validate feat-entry-duration-subtitle --strict` passes; fix all findings.

## 2. Implementation (`LogTimeView.swift` toolbar principal + pure display helper only)

- [x] 2.1 `LogTimeViewModel`: add pure display helper `durationSubtitleSeconds: Int?` (rounded Start→End seconds, nil when ≤ 0). Do NOT change save/validation behavior (`isAddEnabled`, auto-push, `save()`, `deleteConfirmed()` untouched).
- [x] 2.2 `LogTimeView`: replace the inline title with a `ToolbarItem(.principal)` VStack (mode title + footnote duration line, single-line truncation each). Valid interval: `Duration: <naturalDuration>` in `Theme.textSecondary`; invalid: localized invalid-interval text in `Theme.danger`. `Theme` colors only. Shared `chrome` modifier so CREATE + EDIT/LOCKED stay identical. Do NOT touch card order, cover/push presentation, `nameCard` internals, `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift`, `TrackView.swift`.
- [x] 2.3 `L10n` en+ru: `entry.duration` (`Duration: %@`), `entry.invalidInterval` (`End must be after Start`); bump `LocalizationTests` count.

## 3. Tests

- [x] 3.1 `LogTimeViewModelTests`: `durationSubtitleSeconds` — valid interval returns seconds; End == Start and End < Start return nil; default fresh sheet returns 3600.
- [x] 3.2 `LocalizationTests` parity covers the new keys (count 137 → 139 for this change alone; 141 combined with `feat-name-field-affordances`).
- [x] 3.3 Nav-bar rendering itself is NOT unit-testable (no view-test infra) — covered by the manual checklist (§4).

## 4. Manual on-device checklist (CREATE + EDIT + LOCKED)

- [x] 4.1 Valid interval shows `Duration: <natural>` updating live while Start/End pickers change. (Device pass 2026-09-29: pass.)
- [x] 4.2 End ≤ Start shows the invalid text in red; confirm stays disabled. (Device pass 2026-09-29: pass.)
- [x] 4.3 320 pt + Dynamic Type + light/dark + EN/RU: subtitle truncates, bar actions reachable. (Device pass 2026-09-29: pass.)
- [x] 4.4 EDIT pushed form: subtitle beside the back button; LOCKED form: read-only subtitle. (Device pass 2026-09-29: pass.)

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean (0 violations); warning-as-error `xcodebuild build-for-testing` green; full iOS suite green — 503 tests passed, 0 failed (serialized per `docs/ios-test-loop.md`, booted-sim-by-ID destination). Backend untouched (no `go` run needed).
- [x] 5.2 Re-checked `Requirements/FURPS/Timetracking.md` (F13 comment gains the subtitle sentence) + `Common.md` (no conflicts).
- [x] 5.3 Stacked PR (PR #56 opened, unmerged) targeting `fix/50-51-entry-form-gestures` (retargeted to `main` after #54 merges): title "Entry duration subtitle plus name-field affordances (#36, #42, #43)", body "Fixes #36, fixes #42, fixes #43" + what changed + verification evidence + untested checklist items. DO NOT merge.

## 6. AI-review findings fix (PR #56, OpenCodeReview LOW)

- [x] 6.1 `LogTimeViewModel.durationSubtitleSeconds`: guard `endsAt > startsAt` before rounding, then `max(0, Int(...rounded()))` — sub-second intervals (reachable via EDIT prefill) no longer show the red invalid text while Save stays enabled; nil ⟺ `isAddEnabled` gate disagreement closed.
- [x] 6.2 Added `durationSubtitleSubSecond` agreement test (`isAddEnabled` true ⟹ subtitle non-nil on a 0.4 s interval).
- [x] 6.3 `openspec validate feat-entry-duration-subtitle --strict` passes.
