## 1. Change artifacts

- [x] 1.1 Write delta specs (`specs/entry-editor/spec.md`: field order + all-native-gestures rule; `specs/manual-entry/spec.md`: CREATE shares the order) + `design.md` (before/after order, navigation-push choice with rationale, why wheel-in-ScrollView no longer collides) + this `tasks.md`.
- [x] 1.2 `openspec validate fix-entry-form-gestures --strict` passes; fix all findings.

## 2. Implementation (`LogTimeView.swift` card order + form presentation only)

- [x] 2.1 Reorder cards to Name → Start → End → Categories → Notes; split `startsEndsCard` into `startCard`/`endCard` (one `timeRow` each, identifiers preserved). Do NOT touch duration toolbar, `nameCard` internals, `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift` OfflineBanner, or `TrackContent.swift`.
- [x] 2.2 Presentation/dismiss fix: EDIT/LOCKED via `.navigationDestination(item:)` push from History (real back stack → edge-back works); CREATE keeps its sheet; move the cover `onDismiss` reload to the push destination's `onDisappear`; `LogTimeView` skips its internal `NavigationStack` when pushed (`embeddedInNavigationStack`, shared chrome modifier — no nested stacks, no visual divergence).
- [x] 2.3 Keyboard dismissal: `@FocusState` on name/notes + `.scrollDismissesKeyboard(.interactively)` + tap-away resign. No gesture-blocking modifiers anywhere (`highPriorityGesture`/`simultaneousGesture`/scroll-disable are forbidden by the spec rule).

## 3. Tests

- [x] 3.1 No new unit tests: `LogTimeViewModel` behavior is byte-for-byte unchanged (existing `LogTimeViewModelTests` cover mode routing, gate, prefill, Start-push, save, stale-write, undo-buffer paths) and card order is view layout with no view-test infra. The new `TimeEntry: Hashable` (required by `.navigationDestination(item:)`) is compiler-pinned at the call site — removing it fails the warning-as-error build, so a unit test would add no signal. `LogTimeView.swift` carries `// swiftlint:disable file_length` per repo precedent (`LocalStore`, `SyncController`, `RemoteCatalogRepository`) after the two-presentation split grew it past 400 lines.
- [x] 3.2 Gestures are NOT unit-testable (edge-pop, wheel-vs-scroll, swipe-down) — covered by the manual checklist (§4), noted in the PR body.

## 4. Manual on-device gesture checklist (CREATE + EDIT + LOCKED)

> Status: UNTESTED ON DEVICE (no device run in this iteration — shared simulator host was running a concurrent change; see PR body). Recommended before merge: build Release to a physical iPhone, sign in, and walk the list below.

- [ ] 4.1 Scroll with picker closed (all modes) — pull-down-to-scroll works.
- [ ] 4.2 Scroll with date picker open + with time (wheel) picker open, drag starting outside the wheels (all modes) — form scrolls, picker stays open.
- [ ] 4.3 Swipe-down-to-dismiss the CREATE sheet — discards draft, no entry created.
- [ ] 4.4 Edge-back pop of the EDIT/LOCKED push — discards draft, lists unchanged; system back button also works.
- [ ] 4.5 Keyboard: focus name/notes → tap away dismisses (draft kept); scroll dismisses; Return (Done) dismisses.
- [ ] 4.6 Small-screen (320 pt) + Dynamic Type + light/dark + EN/RU spot-check with a picker expanded (card margins kept, no clipping).

## 5. Verification + docs (S5)

- [x] 5.1 `swiftlint lint --strict` clean (0 violations); warning-as-error `xcodebuild build-for-testing` green; full iOS suite green — 490 tests / 48 suites passed (see PR body). Serialized per `docs/ios-test-loop.md` (log-file polling, booted-sim-by-ID destination). Backend untouched by this change (no `go` run needed; `openapi.yaml` not modified by this change).
- [x] 5.2 Re-checked `Requirements/FURPS/Timetracking.md` (F13: sheet order + push presentation) + `Common.md` (no conflicts); F13 updated in this change.
- [x] 5.3 Updated `docs/project-context.md` (History push + card order), `Design/SCREENS/History.md`, `Design/DECISIONS.md` (D21). No architecture/contract/run-step changes beyond the specified behavior.
- [x] 5.4 Push + `gh pr create` targeting `main` (PR #54; title "Fix entry-form gestures + reorder (#50, #51)", body "Fixes #50, fixes #51" + what changed + verification evidence + checklist results/untested items + rebase-base note). DO NOT merge.
