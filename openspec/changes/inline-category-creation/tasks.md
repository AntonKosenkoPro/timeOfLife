## 1. Research bundle (done in planning)

- [x] 1.1 ctx7 bundle executed (max 5 commands, no quota errors, pin iOS 18 SDK via Xcode 16+): SwiftUI `/websites/developer_apple_swiftui` docs `NavigationStack push navigation programmatic navigation path iOS 18`; HIG `/websites/developer_apple_design_human-interface-guidelines` docs `adding creation affordances buttons in context` (partial waiver — samples only, see design.md D2); SwiftUI a11y docs `accessibility custom button accessibilityLabel accessibilityValue VoiceOver` (reused ID). Cites live in proposal.md + design.md; implementation tasks depend on this section.
- [x] 1.2 Baseline + docs survey: `category-management` and `timer-capture-experience` requirement blocks, `Design/COMPONENTS.md` TagSelector, `Design/SCREENS/CategoryEditor.md`, `Activity_Catalog_and_Categories.md` F2/F8/U1/U8/U6/U7, `ShellRoute` cases, LogTime CREATE/EDIT presentation — all verified on this tree.

## 2. TagSelector creation footer + clamped viewport

- [x] 2.1 Replace the trailing creation chip with a pinned footer: `onCreate` (default `nil`) renders a quiet leading `+ Add category` text button below the chips; `nil` keeps the selector select-only.
- [x] 2.2 Clamp the chip region at 3.5 visible rows with internal scroll (half-row peek); content below the clamp sizes naturally with no dead space. Row math from scaled type metrics (`UIFont` + `minTapArea` floor), not magic points; selection toggles never change geometry.
- [x] 2.3 Accessibility: distinct identifier (`…NewCategory`), localized VoiceOver label without the trait word, 44 pt target; en + ru + `L10n` (U4) — reuses existing Add-category strings.
- [x] 2.4 Unit/preview coverage: footer renders iff `onCreate` non-nil; clamp math (compact vs clamped); 44 pt target; EN/RU previews including Dark.
- [x] 2.5 Hairline split + no glass: `Theme.hairline` divider between chips and footer (running-selector divider precedent), Liquid Glass treatment removed; verify on device.
- [x] 2.6 Edge-aware dividers: top fades in once scrolled, bottom fades out at the content end, both hidden when everything fits (`onScrollGeometryChange`, iOS 18+); pure edge math unit-tested; verify on device while scrolling.

## 8. Recents parity

- [x] 8.1 Extract shared `ChipViewport` clamp/edge math; `TagSelector` and `RecentActivitiesChips` use it (row heights stay caller-owned).
- [x] 8.2 Recents: 3.5-row flexible clamp (scaled subheadline metrics) + edge-aware dividers top and bottom, same fade contract.
- [x] 8.3 Artifacts: proposal bullet, `timer-capture-experience` Recents delta, `COMPONENTS.md` Recents section.
- [x] 8.4 Verify: lint + full suite green; deploy to iPhone and scroll Recents to both ends.

## 9. Chip typography sync + header divider removal

- [x] 9.1 Both chip groups use `.body` typography (Recents as reference): `TagSelector` chips adopt body-medium labels + 17 pt body-scaled glyphs/slot; Recents bumps from subheadline to body; row-height math follows.
- [x] 9.5 Revert to `.subheadline` regular per HIG compact-control research (body/medium too big+bold): both groups + footer; glyphs 14 pt; row math follows.
- [x] 9.2 Remove the constant header hairlines under Categories/Recents captions on Track (grouping now carried by the edge-aware viewport dividers).
- [x] 9.3 Artifacts: `COMPONENTS.md` TagSelector visual, `SCREENS/TimeTracking.md` divider doc, REMOVED `timer-capture-experience` header-separator requirement with reason + migration.
- [x] 9.4 Verify: lint + full suite green; deploy to iPhone.

## 10. AI review round 1 fixes (PR #178)

- [x] 10.1 Fix `chipRowHeight` double-scaling (resolve against the `dynamicTypeSize` environment trait, Recents pattern).
- [x] 10.2 Add missing `.fixedSize(horizontal: false, vertical: true)` to the TagSelector viewport (hug content up to the clamp).
- [x] 10.3 Bottom edge divider renders whenever content remains (not only with footer).
- [x] 10.4 `attachCreatedCategory` appends in `.error` too (updateDraftNotes parity) + test; fix AppShell comment.
- [x] 10.5 Gate push Back while a save is in flight (`navigationBarBackButtonHidden(vm.isLoading)`, sheet parity).
- [x] 10.6 Trim vacuous footer test to a single iff opt-in assertion.
- [x] 10.7 Re-verify (lint + full suite) and push.

## 3. Pushable category editor form

- [x] 3.1 Extract the editor form (name field + icon grid + validation + toolbar grammar) from `CategoryEditorView` sheet chrome so it can serve as a `navigationDestination`; keep a thin sheet wrapper with identical Manage Categories behavior (sheet parity check).
- [x] 3.2 Reuse `CategoryEditorViewModel.save()` unchanged (validation, duplicate stay-open + banner, outbox commit); no new save path.
- [x] 3.3 Existing editor tests green; add coverage for pushed-form save/dismiss and duplicate-stays-open from a push host.

## 4. Entry-form wiring (CREATE + EDIT)

- [x] 4.1 Wire `onCreate` in `LogTimeView.categoriesCard`: push the editor form (internal stack for CREATE sheet, `historyPath` for pushed EDIT).
- [x] 4.2 On save: reload `availableCategories`, append the new id to `vm.categoryIDs` in tap order, pop back with the rest of the draft intact; on Back/X: catalog and draft unchanged.
- [x] 4.3 Duplicate from the form: editor stays open with `errorCategoryExists`, draft preserved (no winner-selection).
- [x] 4.4 UI coverage: CREATE-sheet push + save-selects; EDIT push + save-selects; duplicate-stays-open; cancel-preserves-draft.

## 5. Track wiring (running + idle)

- [x] 5.1 Add a `ShellRoute` category-editor destination on `trackPath`; wire `onCreate` in `runningTagSelector` to push it.
- [x] 5.2 Running save: reload options, append the new id to the running draft (tap order) + persisted `timer_state` snapshot, pop back; timer keeps running, no history touched.
- [x] 5.3 Non-running states: the chip is unreachable (slot shows Recents; row hidden, no hit-testing) — no wiring; `attachCreatedCategory` still merges the category into the pool for pool-freshness, appending to a draft only while running.
- [x] 5.4 UI coverage: mid-run create + attach; idle create pool-only; duplicate-stays-open mid-run with timer unaffected.

## 6. Docs, strings, and contract checks

- [x] 6.1 `Design/COMPONENTS.md` TagSelector section: document the opt-in creation chip (signature, style, a11y); `Design/SCREENS/CategoryEditor.md`: document push hosting + Back-cancels + per-host save outcome; re-check each screen's Implementation checklist.
- [x] 6.2 Re-check `Requirements/FURPS/Activity_Catalog_and_Categories.md` rows (F2/F8/U1/U8/U6/U7); fix any conflict (creation entry points expand beyond Profile, behavior otherwise unchanged).
- [x] 6.3 Confirm no OpenAPI/backend/on-disk-format changes (creation reuses existing store + sync path); `docs/project-context.md` update only if architecture/contract/run steps changed.

## 7. Verify

- [x] 7.1 `swiftlint lint --strict`, warning-as-error build, and full iOS suite green (`xcodebuild test -scheme TimeOfLife`, per `docs/ios-test-loop.md` agent loop rules; one `xcodebuild`/one simulator at a time).
- [x] 7.2 Backend untouched — no `go` verify required (state the waiver explicitly in the PR).
- [ ] 7.3 Fresh-base double rebase (`git fetch origin` + rebase before implementing and before the PR; `push --force-with-lease`; never merge main), re-running affected linters/tests after each. Final PR refresh: fetched/rebased on `origin/main` on 2026-10-19 and re-ran both subsystem checks; the historical pre-implementation rebase is not independently verified.

## 13. Viewport sizing: flexible attempt, then fixed 4-row clamp

- [x] 13.1 `TagSelector`: `isScrollable` mode (default true); entry form passes false for natural height. (Kept.)
- [x] 13.2 Recents: flexible treatment first (dropped — outer ScrollView offers unbounded height, so flexible claimed full content and slid under the tab bar).
- [x] 13.3 `ChipViewport` keeps clamp + edge math (fixed 4 rows); update artifacts (proposal/specs/design/COMPONENTS).
- [x] 13.4 Tab-bar margin on the Track slot (glass-aware, zero on iOS 18/iPad); verified on iPhone SE sim (12 cats: 4-row clamp, internal scroll, siblings stationary, tab bar clear).

- [x] 11.1 Attach reloads options from the store (canonical order, no client collation); `attachCreatedCategory` async; callers Task-wrap; tests rewritten against a real store.

## 14. Fixed 4-row clamp + tab-bar margin (post flexible-attempt)

- [x] 14.1 Restore `ChipViewport.clampedHeight` with 4 rows (flexible .infinity abandoned: outer ScrollView offers unbounded height, viewport slid under the tab bar).
- [x] 14.2 Track slot bottom margin mirroring the glass tab bar float (zero on iOS 18 opaque bar and bar-less iPad); explicit `TagSelector.init`.
- [x] 14.3 Artifacts updated (proposal/specs/design/COMPONENTS); validate + lint green.
- [x] 14.4 Full suite green; deploy to iPhone.

## 15. Viewport border clearance (+2 pt, categories-only)

- [x] 15.1 ctx7 research (3 commands, no quota errors, pin iOS 18 SDK via Xcode 16+): SwiftUI library `/websites/developer_apple_swiftui` query `SwiftUI ScrollView clipping padding border clearance`; docs `ScrollView frame clipping border` (`scrollClipDisabled`, scroll-views: `ScrollView` clips to bounds by default — clearance via frame sizing, not by disabling clipping); docs `view frame layout padding safe area` (`safeAreaPadding`/`safeAreaInset` — not applicable inside a clamped chip viewport). HIG waived: no changed interaction, typography, or grouping — border clearance only. Cites live in design.md D2.
- [x] 15.2 `ChipViewport.borderBleed = 2` applied to the scrollable `TagSelector` viewport only as scroll-content `.padding(.vertical, borderBleed / 2)` (1 pt top/bottom) plus matching +2 pt max cap (`clampedHeight + borderBleed`); 4-row cap unchanged; natural-height entry-form rendering (`isScrollable: false`) unchanged; `RecentActivitiesChips` keeps the exact clamp. Prior frame-only +2 proved insufficient — user screenshot of exactly-four-row content showed content hugging with the bottom border still clipped.
- [x] 15.3 Artifacts updated (design.md D2, `Design/COMPONENTS.md` TagSelector viewport + States row); no spec change (row-count contract unchanged).
- [ ] 15.4 Visual verification on device (bottom chip border fully visible at the 4-row cut) — NOT marked complete. Focused verify per iOS worker: 21 tests across 3 suites + lint/build green; device screenshot check still pending.

## 16. Adaptive up-to-4 viewport + Recents clearance parity (Option 1, agreed)

- [x] 16.0 ctx7 research (pin iOS 18 SDK via Xcode 16+): library SwiftUI `/websites/developer_apple_swiftui` query `ScrollView finite height proposal GeometryReader`; docs `ScrollView content unbounded proposed height finite container` (`ProposedViewSize.height == nil` = unspecified/ideal height — finite budget measured outside the outer `ScrollView`, passed down). `GeometryReader` docs query failed on shell quoting — not claimed as fetched. HIG waived: interaction unchanged, bounded-geometry fix only. Cites live in design.md D2.
- [x] 16.1 Implemented adaptive cap: `TrackContent` measures the finite budget outside the outer `ScrollView` (viewport minus measured top/name/action/caption + fixed gaps + `tabBarMargin`) and passes it down; `ChipViewport` clamps to `min(4-row clamp + bleed, available budget)` with a 1-row floor so entire-page scroll engages only as the accessibility fallback. Short viewports (SE) show fewer rows with internal scroll; timer/name/Stop preserved with no tab-bar overlap.
- [x] 16.2 `RecentActivitiesChips` shares the same clearance: `ChipViewport.borderBleed = 2` as 1 pt top/bottom scroll-content inset plus matching +2 pt cap in both groups; natural-height entry-form rendering (`isScrollable: false`) unchanged.
- [x] 16.3 Artifacts updated to adaptive up-to-4 with shared clearance (proposal, both delta specs, design.md D2, `Design/COMPONENTS.md` TagSelector + Recents, `Design/SCREENS/TimeTracking.md` Recents); no baseline `openspec/specs` edits; no FURPS change (no row-count row; FURPS re-checked).
- [x] 16.4 Code + tests (iOS worker, no docs-worker code): shared `ChipViewport` math, caller-owned row heights unchanged; `swiftlint lint --strict` 0 violations; initial full suite 690 tests / 67 suites green. After final rebase on 2026-10-19: 694 tests passed, 0 failed/skipped; fixed compiler-proven create-chip test-suite actor isolation warnings with `@MainActor`. Backend lint/build/vet/race tests also passed; Xcode AppIntents metadata-extraction informational warning remains (no dependency in the app).
- [x] 16.5 Simulator verification (default Dynamic Type L, recaptured after earlier XS/XXXL): SE ~2.5 rows internal scroll no overlap; mini/max 4 rows + bottom divider; SE scroll-end `+Add` dashed border complete, top divider visible / bottom hidden, timer/name/Stop stationary; SE overflowing Recents (existing history fixture, 12 recents) cap adapts with internal scroll, last borders intact, Start stationary; idle single Recent hugs with no dividers. Evidence binaries kept OUT of git: `/private/var/folders/8c/pwh55jk140g1shxfnwm7zxf80000gn/` `track-se-L.png`, `track-mini-L.png`, `track-max-L.png`, `track-se-scrolled.png`, `track-se-recents-L.png`, `track-se-recents-end-L.png`.
- [ ] 16.6 Physical-phone verification of the adaptive update — NOT done, NOT deployed. Do not imply done from simulator evidence above. (15.4 physical clearance check likewise remains pending.)

## 17. Refreshed AI review sweep, round 1 fixes (run 39235603751: 4 summary + 4 inline, all PROVEN)

- [x] 17.0 Research waiver: internal state/test changes only — no new external dependency, API, or interaction. Divider overlay pattern already used in-repo; no ctx7 fetch (waiver reason recorded here).
- [x] 17.1 Divider siblings exceeded budget (finding 4312721732): both `TagSelector` and `RecentActivitiesChips` rendered edge hairlines as `VStack` siblings, growing the viewport 1–2 hairlines beyond the measured budget. Fixed: dividers are `.overlay` on the capped `ScrollView` outer frame (both groups) with `allowsHitTesting(false)` — zero layout height, no hit-testing, aligned to the frame never the scrolled content.
- [x] 17.2 `deleteConfirmed` missing shared gate (finding 4312721758): refused nothing while busy, unlike save/dismissal gating. Fixed: `guard !isLoading else { return false }` + `isLoading = true` / `defer { isLoading = false }`, matching dismissal gating; publisher tests capture in-flight `true` (LocalStore actor crossing can suspend).
- [x] 17.3 Attachment wait helpers could not fail (findings 4312721780 + 4312721811): two `TrackViewModelTests` attach cases relied on `waitForPersistedDraft` alone, which passes on timeout. Fixed: explicit persisted-snapshot assertions (`runningTimerDraft()?.categoryIDs == ["c1"]`) after the wait in both cases.
- [x] 17.4 Artifacts updated (tasks §17, `Design/COMPONENTS.md` divider overlays, `Design/SCREENS/CategoryEditor.md` delete gate); no spec change (contracts unchanged); `openspec validate --strict` green. Code confirmed present on this tree.
- [x] 17.5 Local verification: strict SwiftLint (180 files, 0 violations), build-for-testing, and full test-without-building passed; Swift Testing reported 693 tests / 67 suites, including both gate-transition tests and both persisted attachment assertions. Physical-phone verification remains pending under 15.4/16.6; CI and next review run are separate PR gates.
