## 1. Research and implementation gate

- [x] 1.1 Obtain human proposal approval before implementation; reuse this worktree/branch/PR, fetch and rebase onto `origin/main`, and recheck the active notes/Stop change for overlap.
- [x] 1.2 Re-confirm the 2026-11-20 research bundle in `design.md`: topic/HIG `/websites/developer_apple_design_human-interface-guidelines`, Apple sheet API `/websites/developer_apple_swiftui` (iOS 18 SDK via Xcode 16+), and atomic writes `/groue/grdb.swift` against the repo-resolved version. Record any changed constraints; fetch current Foundation/lifecycle docs before introducing notification/calendar APIs. Keep cloud/ActivityKit waiver reasons explicit.
- [x] 1.3 Recheck `Requirements/FURPS/{Common,Timetracking,Activity_Catalog_and_Categories}.md`; document the local-only planner/outbox exception and text-only selection without changing Recents inheritance or entry/category Undo.

## 2. Account-local model and storage

- [x] 2.1 Add the minimal task model and additive `LocalStore` migration (`id`, validated text, creation/completion timestamps), with stable creation ordering and duplicate-text support; add fresh/migrated-file tests.
- [x] 2.2 Add transactional planner load/prune/create/check/uncheck/remove methods through `LocalStore`, with expected-account checks inside the store and existing suspension guards. Test persistence, validation, rollback, and zero outbox/undo/cursor changes.
- [x] 2.3 Implement injectable local-day cleanup: strictly prior-day completed rows only, retaining unfinished/current-day rows. Test exact midnight, uncheck/recheck, DST short/long days, multiple inactive days, time-zone/clock changes, and idempotent retry.
- [x] 2.4 Verify sign-out/re-login retention, independent duplicate tasks, account-switch races, and `eraseAll`/active/dormant account-file cleanup without cross-account effects or relay restoration.

## 3. Sheet state and timer integration

- [x] 3.1 Add a lazily loaded planner view model with serialized actions, loading/empty/failure states, durable-write feedback, preserved failed-Add input, retry, and account-generation invalidation. Keep planner reads out of the launch `TrackSnapshot`.
- [x] 3.2 Add safe foreground/resume/open reconciliation and a day-boundary trigger only while the sheet is open/active; re-evaluate time-context changes. Test suspension/resume retries and that no new background task, hidden-sheet midnight timer, or extension writer is introduced.
- [x] 3.3 Add the dedicated text-only Track preparation operation and successful-selection dismissal. Test exact-name historical category matches, empty categories/notes through Start, unchanged Recents/name-picker behavior, no timer/entry writes before Start, and no completion linkage on Start (Stop-completion delta tracked in §6).
- [x] 3.4 Test running/recoverable-error/saving selection guards, eligibility rechecks, stale-account selection, completed-task selection, unchanged prepared/running names after task removal/cleanup, and coexistence with the existing start editor and notes Review/Discard presentation (Stop-completes-match cases tracked in §6).

## 4. Planner UI and localization

- [x] 4.1 Add the Track-only toolbar button beside Profile and system sheet with adaptive medium/large presentation, Done/grabber/system dismissal, and a scrollable checklist; preserve the Track layout, other tabs, and navigation paths.
- [x] 4.2 Add plain-text Add input, separate row checkbox/name actions, stable ordering, and named destructive Remove confirmation (Enter-keeps-focus and verbatim-quote deltas tracked in §6). Keep checklist management usable while running and disable only unavailable actions; no suggestions, category prefill, rename, reorder, or queued-next behavior.
- [x] 4.3 Add all planner/validation/confirmation/error strings to `en`, `ru`, `zh-Hans`, `es-419`, `pt-BR` and `L10n`/localization tests; use Theme-only styling, 44pt targets, Dynamic Type, independent VoiceOver actions/state, and stable per-task IDs.

## 5. Documentation and acceptance verification

- [x] 5.1 Define reusable checklist controls in `Design/COMPONENTS.md` first, then document `Design/SCREENS/PlannerSheet.md` and the Track/AppShell entry points with implementation checklists. Update relevant `Design/INTERACTIONS.md`/`DECISIONS.md` rules for text-only preparation, local-day cleanup, and planner removal outside shared Undo.
- [x] 5.2 Update FURPS, `docs/project-context.md`, README as applicable, and `docs/manual-testing.md` with device-local/account-erasure limits and truthful midnight behavior. Leave baseline specs and OpenAPI untouched; verify the backend/sync diff stays empty.
- [x] 5.3 Run backend verification (`gofmt`, `go vet`, `golangci-lint`, build, full `go test`) and iOS verification (XcodeGen if needed, strict SwiftLint, warning-as-error build, full simulator suite per `docs/ios-test-loop.md`) on separate agents in parallel. Serialize all Xcode builds/generation/simulator use.
- [ ] 5.4 Run UI acceptance for sheet open/add/check/uncheck/select/dismiss, running checklist management, confirmed removal, keyboard/long-list/large-text/iPad layouts, VoiceOver, local-day rollover, offline/relaunch, account switching, and suspension retry. Include Enter-keeps-focus rapid entry, Stop-completes-match (single/duplicates/no-match), and verbatim removal quotes across locales. Preserve evidence outside git; do not imply UI verification from unit tests.
  - Status 2026-11-23: still blocked — the interactive device portion (VoiceOver/iPad/real-day rollover) sits behind OTP sign-in with no review-capable device session in this environment; simulator suites cannot exercise VoiceOver, Dynamic Type at device scale, or true local-midnight rollover. Automatable coverage landed instead: Stop-completes-match (store + VM suites: oldest-first, one-by-one duplicates, no-match, already-completed, case-sensitivity, account fencing, suspension deferral, receipt/entry/Live Activity unchanged), Enter-keeps-focus VM contract (consecutive adds stay interactive; FocusState half needs a device), verbatim-quote regression across all five locales. Manual checklist staged in `docs/manual-testing.md` items 3–5.
- [x] 5.5 Rebase again on fresh `origin/main`, rerun affected verification and `openspec validate --all --strict`, update completed tasks truthfully, and hand the same PR to `/lifio-pr`. No automatic merge or archive; issue #254 remains open for Stage 2.

## 6. Device-feedback corrections (2026-11-23, all block code sync)

- [x] 6.1 Stop completes matching task: on Stop, complete the oldest unfinished task with normalized text exactly equal to the stopped run (one per Stop, timestamped with stop; no-match changes nothing; Start never completes). Add store/VM/selection tests (duplicates, already-completed, no-match, account fencing, suspension) and keep Stop receipt/Live Activity behavior unchanged.
- [x] 6.2 Enter keeps keyboard focus: submitting via Enter/Add clears the field and retains focus for the next task; failures preserve text and focus; only Done/swipe dismisses. Add focus-retention tests and re-verify keyboard acceptance.
- [x] 6.3 Verbatim removal confirmation: interpolate the task name through localized format strings (no manual `\u` escapes); visual truncation keeps the full name in the accessibility label. Add regression tests with quotes/emoji/long names in all five locales.
- [x] 6.4 Re-verify after §6 code changes (backend + iOS suites on separate agents, serialized Xcode work), re-run `openspec validate --all --strict`, and hand the same PR to `/lifio-pr`. No merge or archive; issue #254 stays open.
