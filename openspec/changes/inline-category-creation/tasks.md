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
- [ ] 7.3 Fresh-base double rebase (`git fetch origin` + rebase before implementing and before the PR; `push --force-with-lease`; never merge main), re-running affected linters/tests after each.

## 11. AI review round 2 fix (PR #178)

- [x] 11.1 Attach reloads options from the store (canonical order, no client collation); `attachCreatedCategory` async; callers Task-wrap; tests rewritten against a real store.
