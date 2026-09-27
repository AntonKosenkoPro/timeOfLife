## 1. Change artifacts

- [x] 1.1 Write delta specs (`specs/entry-editor/spec.md`: field order + all-native-gestures rule; `specs/manual-entry/spec.md`: CREATE shares the order) + `design.md` (before/after order, navigation-push choice with rationale, why wheel-in-ScrollView no longer collides) + this `tasks.md`.
- [x] 1.2 `openspec validate fix-entry-form-gestures --strict` passes; fix all findings.

## 2. Implementation (`LogTimeView.swift` card order + form presentation only)

- [x] 2.1 Reorder cards to Name → Start → End → Categories → Notes; split `startsEndsCard` into `startCard`/`endCard` (one `timeRow` each, identifiers preserved). Do NOT touch duration toolbar, `nameCard` internals, `CatalogIcon.swift`, `openapi.yaml`, `RootView.swift` OfflineBanner, or `TrackContent.swift`.
- [x] 2.2 Presentation/dismiss fix: EDIT/LOCKED via `.navigationDestination(item:)` push from History (real back stack → edge-back works); CREATE keeps its sheet; move the cover `onDismiss` reload to the push destination's `onDisappear`; `LogTimeView` skips its internal `NavigationStack` when pushed (`embeddedInNavigationStack`, shared chrome modifier — no nested stacks, no visual divergence).
- [x] 2.3 Keyboard dismissal: `@FocusState` on name/notes + `.scrollDismissesKeyboard(.interactively)` + tap-away resign. No gesture-blocking modifiers anywhere (`highPriorityGesture`/scroll-disable are forbidden by the spec rule — corrected 2026-09-27: `simultaneousGesture` does NOT block, so the `FormCard` tap-away uses it; see §6.1).

## 3. Tests

- [x] 3.1 No new unit tests: `LogTimeViewModel` behavior is byte-for-byte unchanged (existing `LogTimeViewModelTests` cover mode routing, gate, prefill, Start-push, save, stale-write, undo-buffer paths) and card order is view layout with no view-test infra. The new `TimeEntry: Hashable` (required by `.navigationDestination(item:)`) is compiler-pinned at the call site — removing it fails the warning-as-error build, so a unit test would add no signal. `LogTimeView.swift` carries `// swiftlint:disable file_length` per repo precedent (`LocalStore`, `SyncController`, `RemoteCatalogRepository`) after the two-presentation split grew it past 400 lines (updated 2026-09-27: the `FormCard` extraction cut 457 → 448 lines, still over 400 — suppression kept with a follow-up comment + tracking issue #57; see §6.4).
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

## 6. AI-review findings fix (PR #54 — OpenCodeReview, all severity low, all in `LogTimeView.swift`)

- [x] 6.1 Child Buttons absorbing taps (BUG): card tap-away is now `FormCard`'s `.simultaneousGesture(TapGesture().onEnded { focusedField = nil })` — tapping a chip/pill both toggles it and resigns focus. Corrects §2.3: the spec forbids *blocking* gestures, and a simultaneous tap blocks nothing.
- [x] 6.2 Tap-away asymmetry: all five cards (including name/notes) resign via `FormCard`; tapping a `TextField` itself still focuses it (the field's focus claim is applied after the gesture resign) — documented on `FormCard`, so uniformity holds with no deliberate asymmetry left.
- [x] 6.3 Duplicated card scaffolding extracted to `Features/ManualEntry/Views/FormCard.swift` (padding→background→clipShape→tap-away), used by all five cards. No new accessibility IDs (start/end cards keep none — `FormCard.accessibilityID` is optional). `resignFocus` is an autoclosure so call sites keep single-trailing-closure form (`multiple_closures_with_trailing_closure`).
- [x] 6.4 `swiftlint:disable file_length`: 457 → 448 lines, still over 400, so the suppression stays — now with a follow-up comment + tracking issue #57 (created 2026-09-27). Scoped `:next` verified unable to cover file rules (violation reported at EOF; the `:next` attempt also tripped `superfluous_disable_command`), and the `todo` rule forbids TODO comments repo-wide (zero precedents), hence a plain comment carrying the #57 reference.
- [x] 6.5 `openspec validate fix-entry-form-gestures --strict` passes; `swiftlint lint --strict` clean; warning-as-error build green; full iOS suite green. Pushed to `origin/fix/50-51-entry-form-gestures`; findings listed in a PR #54 comment. NOT merged.
