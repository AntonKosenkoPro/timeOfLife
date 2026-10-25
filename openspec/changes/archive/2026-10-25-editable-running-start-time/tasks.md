## 1. Research + spikes (gate implementation)

- [x] 1.1 Re-confirm ctx7 bundle on the implementation tree (pin `iOS 18 SDK via Xcode 16+`): SwiftUI `/websites/developer_apple_swiftui` — `DatePicker displayedComponents hourAndMinute datePickerStyle compact wheel`; HIG `/websites/developer_apple_design_human-interface-guidelines` — `pickers date time picker iOS best practices`; ActivityKit `/websites/developer_apple_activitykit` — `update Live Activity ContentState start date timer`. Record IDs + queries + pins; backend item waived (LocalStore-only, Stop relay path unchanged).
- [x] 1.2 Spike A (inline wheel, preferred): `Started HH:MM` caption + in-place hourAndMinute wheel + `[-30][-15][-10][-5]` presets as throwaway preview; verify D10 (Stop never moves) at default + large Dynamic Type.
- [x] 1.3 Spike B (half-sheet): same caption opening a `.presentationDetents([.medium])` sheet with presets + optional wheel + Done, as throwaway preview.
- [x] 1.4 Spike C (native compact): `DatePicker(.compact, hourAndMinute)` caption with OS popover, as throwaway preview.
- [x] 1.5 Spike review: pick winner (default A); confirm Live Activity `update(using:)` re-anchors the system timer in foreground (fallback end+request noted), confirm midnight rule (future wheel time = yesterday + yesterday label), confirm minute-floor precision.

## 2. Store + service

- [x] 2.1 Add `LocalStore.updateTimerDraftStartedAt` chokepoint (started_at-only rewrite, no outbox) + GRDB unit tests (field isolation, crash-restore keeps new start).
- [x] 2.2 Add `TimerService` start-edit path + Live Activity re-anchor (`update` same singleton, identical-start skip) + unit tests (ticker anchor, chips/icon unchanged, disabled-activities no-op).

## 3. Track UI (spike winner, default A)

- [x] 3.1 Build `Started HH:MM` reserved caption slot + winner editor UI (Theme-only colors; `Started %@` / yesterday strings in `en`+`ru` + `L10n`, U4); gate `newStart <= now` (confirm disabled, no error text); overlap allowed.
- [x] 3.2 Add `TrackViewModel.updateDraftStartedAt` (optimistic state + ticker restart, recoverable error keeps in-memory value) + ViewModel tests (elapsed jump, gate reject, midnight label, Stop derived duration).
- [x] 3.3 Verify CompactTimer follows free, VoiceOver announces caption + editor, Reduce Motion respected, no D10 regression.

## 4. Verify + docs

- [x] 4.1 Run `swiftlint lint --strict`, warning-as-error `xcodebuild build`, `xcodebuild test` full suite green; `gofmt -l .` empty (no backend change — verify only).
- [x] 4.2 Re-check `Requirements/FURPS/Timetracking.md` rows; update `docs/project-context.md`, `Design/` (new component → `COMPONENTS.md` first), and `README.md` only if behavior/run steps changed; run `openspec validate --all --strict`.
