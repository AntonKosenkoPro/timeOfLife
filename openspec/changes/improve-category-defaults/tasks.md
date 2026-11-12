## 1. Research and acceptance gates

- [ ] 1.1 After human proposal approval, fetch/rebase onto fresh `origin/main` on this same worktree/branch and re-confirm the research bundle recorded in `design.md`: HIG/topic `/websites/developer_apple_design_human-interface-guidelines` queries for recognizable category symbols and OS availability, Apple `UIImage.init(systemName:)` reference, iOS 18 SDK via Xcode 16+ pin, and external-library/setup waiver. Record any changed findings before code edits.
- [ ] 1.2 Record the current seven-starter/14-sports/two-food/one-child-specific baseline as characterization evidence, then verify all three decided additions (`carrot`, `stroller`, `teddybear`) with the existing renderability mechanism on an iOS 18 simulator. Require all three to pass; if any fails, record evidence and stop for an explicit decision without silently omitting or substituting an icon. This is a feature enhancement, not an unverified crash/bug fix; no application implementation before these gates.

## 2. Shared accepted icon catalog

- [ ] 2.1 Add exactly `carrot`, `stroller`, and `teddybear` to iOS `CatalogIcon`, authoritative OpenAPI `CategoryIcon`, and Go `validIcons` together, yielding exactly 66 symbols; retain all existing 63 values and do not add a schema migration or a wire-level hidden flag.
- [ ] 2.2 Extend backend handler coverage for create/update of all three new symbols and every hidden sports value, retain unsupported-icon rejection, and verify OpenAPI/Go exact-set parity. Update iOS `CatalogIconTests.canonicalSymbols` to the same 66-symbol set; test that hidden values still validate and render normally where available.

## 3. Curated picker and selected-value preservation

- [ ] 3.1 Add a testable picker subset excluding exactly `figure.strengthtraining`, `figure.soccer`, `figure.basketball`, `figure.tennis`, `figure.gymnastics`, `figure.mindandbody`, and `figure.core.training`. Preserve seven sports choices, explicitly including `bicycle`, and existing non-sports options. Add `carrot`, `stroller`, and `teddybear` without visible grouping or layout redesign; assert 59 curated symbols before OS renderability filtering and exactly three choices per requested domain.
- [ ] 3.2 Update shared `CategoryEditorForm` options to include the current supported selection once even if hidden or unrenderable. Preserve the original glyph where available and `tag` only for OS unavailability; name-only edits must not change the icon.
- [ ] 3.3 Add regression coverage for new-category exclusion, all hidden values remaining accepted, each hidden current selection surviving name-only save/reload/sync, explicit replacement, unavailable-selected fallback, no duplicate option, and compact domain counts. Exercise the shared editor through Profile and inline category creation paths.

## 4. Food starter and localization

- [ ] 4.1 Append Food/`fork.knife` to shipping starter icon/name lists and add `category.seed.food` through `L10n`. Preserve the current LocalStore marker, same-name skipping, atomic outbox write, account isolation, and no-reseed behavior; add no version gate or backfill.
- [ ] 4.2 Update LocalStore seeding tests to eight categories/outbox creates and the new invalid-name-count boundary. Add an existing-seven-starter-file regression with its old marker, edited/deleted starter cases, erase/reseed, collision skipping, locale switching, and per-account isolation.
- [ ] 4.3 Add Food names and `catalogIcon.<rawValue>` accessibility names for `carrot`, `stroller`, and `teddybear` in all five locales; keep all old icon names. Update localization snapshots/coverage and first-paint/sign-in lifecycle expectations to eight starters with fail-closed seed validation.
- [ ] 4.4 Audit `AppContainer+UITesting` seed tokens and capture fixtures for count assumptions. Preserve `shot-cat-food`, eight capture categories, and 55 fixture entries with no duplicate Food; add focused fixture regression coverage where needed. Do not regenerate panels or commit capture binaries.

## 5. Documentation and requirements alignment

- [ ] 5.1 Update `Design/TOKENS.md`, `Design/COMPONENTS.md` (`IconPickerGrid`), `Design/SCREENS/ManageCategories.md`, and `Design/SCREENS/CategoryEditor.md` with the seed addition, exact 66-symbol accepted set/seven hidden sports icons, selected-icon exception, five-locale coverage, and implementation checklists. Keep this change's delta aligned with the three decided additions and `bicycle` remaining visible; leave baseline specs untouched until archive.
- [ ] 5.2 Update category FURPS F6/resolved seed decision and stale affected EN+RU wording, and `docs/project-context.md` for eight starters and picker policy. Re-check F2/F12/U1/U9/R1–R3 and Common U1/U3/U4/U5/S3/S5/S10; leave CRUD/undo/conflict semantics unchanged. Update README/manual-testing guidance if its relevant defaults or acceptance steps change.

## 6. Verification and handoff

- [ ] 6.1 On a backend verification agent, run `gofmt -l .`, `go vet ./...`, `golangci-lint run`, `go build ./...`, and `go test ./...` including icon handler and OpenAPI parity regressions; record outcomes.
- [ ] 6.2 In parallel on a separate iOS verification agent, follow `docs/ios-test-loop.md`: SwiftLint strict, warning-free simulator build, focused regressions and full suite. Serialize `xcodebuild`/simulator use; run XcodeGen only when needed, never hand-edit the project.
- [ ] 6.3 Verify the same characterized UI paths on iOS 18: fresh-account dataset has Food, already-seeded data does not gain it, compact new choices work, hidden existing selections survive name-only edits, and first-position category icons render in rows/Recents. Check offline save then sync and VoiceOver/localized labels; keep evidence outside git. Record rollout order: additive relay acceptance before app distribution.
- [ ] 6.4 Fetch/rebase before updating the implementation PR, rerun affected checks after any base change, and run `openspec validate --all --strict`. Reuse this proposal PR via `/lifio-pr` for implementation CI/AI review; never merge or archive without the later human approval. Proposal review alone does not complete any implementation task.
